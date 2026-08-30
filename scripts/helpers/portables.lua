local uevrUtils = require('libs/uevr_utils')
local attachments = require('libs/attachments')
local controllers = require('libs/controllers')
local physics = require('libs/physics')
local reticule = require('libs/reticule')
local mathLib = require('libs/core/math_lib')

local M = {}

local useVanilla = false

function M.usePhysicsBased(value)
	useVanilla = not value
end

-- Max range at a full-speed swing: 20 * THROW_GAIN / weightKg (gain 5, 10 kg -> 10 m).
-- Wrist speed between dropSpeed and fullSpeed (measured max flick ~704) scales that range.
local THROW_GAIN = 5.0
local DEFAULT_THROW_MASS = 2
local NORMAL_THROW_KG_METERS = 20.0
local THROW_LOCKOUT_MS = 1000
local ATTACH_NO_COLLISION_MS = 1000
local TRIGGER_THRESHOLD = 128
local AIM_OFFSET_YAW = -27
local AIM_OFFSET_PITCH = 10
local THROW_LOFT_PITCH = 15

local throwing = false
local throwingCallbacks = {}
local throwSampler = physics.createThrowSampler({
	maxSpeed = 1200,
	fullSpeed = 700,
	historySize = 24,
	releaseSamples = 4,
	minMoveSq = 1,
	dropSpeed = 50,
	dropIdle = 0.12,
	assumedReleaseHeight = 150.0,
	worldGravity = 980.0,
})

local portableDrop = {
	holding = false,
	mesh = nil,
	carryable = nil,
	lastMeshLoc = nil,
	hmdCopy = nil,
	pending = nil,
	wait = 0,
	releaseVelocity = nil,
}

local attachCollisionMesh = nil
local leftTriggerHeld = false
local pendingThrowAimLoc = nil
local pendingThrowAimRot = nil

local function restorePortableAttachCollision()
	local mesh = attachCollisionMesh
	attachCollisionMesh = nil
	if uevrUtils.getValid(mesh) == nil then
		return
	end
	---@diagnostic disable-next-line: need-check-nil, undefined-field
	mesh:SetCollisionEnabled(ECollisionEnabled.QueryAndPhysics)
end

local function beginPortableAttachNoCollision(mesh)
	if uevrUtils.getValid(mesh) == nil then
		return
	end
	if attachCollisionMesh ~= nil and attachCollisionMesh ~= mesh then
		restorePortableAttachCollision()
	end
	attachCollisionMesh = mesh
	---@diagnostic disable-next-line: need-check-nil, undefined-field
	mesh:SetCollisionEnabled(ECollisionEnabled.NoCollision)
	uevrUtils.updateDeferral("portable_attach")
end

local function getHoldingPortable()
	if pawn == nil or pawn.IsHoldingCarryable == nil then
		return nil
	end
	local ok, portable = pcall(function() return pawn:IsHoldingCarryable() end)
	if not ok then
		return nil
	end
	return portable
end

local function getPortableMeshFrom(portable)
	if portable == nil then
		return nil
	end
	local owner = portable:GetOwner()
	if owner == nil then
		return nil
	end
	return owner.RootComponent or owner.StaticMesh or owner.SkeletalMesh
end

function M.getPortableMesh()
	if portableDrop.mesh ~= nil then
		return portableDrop.mesh
	end
	return getPortableMeshFrom(getHoldingPortable())
end

function M.isThrowing()
	return throwing
end

function M.registerThrowingCallback(callback)
	if callback ~= nil then
		table.insert(throwingCallbacks, callback)
	end
end

local function setThrowing(value)
	if throwing == value then
		return
	end
	throwing = value
	for i = 1, #throwingCallbacks do
		throwingCallbacks[i](value)
	end
end

local function isPortableDocked(carryable)
	if uevrUtils.getValid(carryable) == nil then
		return false
	end
	if carryable:IsDocked() == true then
		return true
	end
	local owner = carryable:GetOwner()
	local dockable = owner ~= nil and owner.Dockable or nil
	return dockable ~= nil and dockable.RepDockedWith ~= nil
end

local function clearPortableDrop()
	restorePortableAttachCollision()
	portableDrop.pending = nil
	portableDrop.mesh = nil
	portableDrop.carryable = nil
	portableDrop.lastMeshLoc = nil
	portableDrop.wait = 0
	portableDrop.releaseVelocity = nil
	physics.resetThrowSampler(throwSampler)
end

local function applyPortableDrop(pending)
	if isPortableDocked(pending.carryable) then
		return true
	end
	local mesh = pending.mesh
	if uevrUtils.getValid(mesh) == nil then
		return true
	end
	if mesh.AttachParent ~= nil then
		mesh:DetachFromParent(true, false)
	end

	local loc = pending.loc
	if loc ~= nil and (loc.X * loc.X + loc.Y * loc.Y + loc.Z * loc.Z) > 1 then
		mesh:K2_SetWorldLocation(uevrUtils.vector(loc.X, loc.Y, loc.Z), false, reusable_hit_result, true)
	end
	restorePortableAttachCollision()
	mesh:SetCollisionResponseToChannel(ECollisionChannel.ECC_Pawn, ECollisionResponse.Ignore)
	physics.applyThrowVelocity(mesh, pending.velocity)
	return true
end

local function updateHoldSampling(portable, delta)
	if not portableDrop.holding then
		portableDrop.holding = true
		portableDrop.pending = nil
		portableDrop.wait = 0
		portableDrop.releaseVelocity = nil
		throwSampler.idleDelta = 0
	end
	portableDrop.carryable = portable
	if portableDrop.mesh == nil then
		portableDrop.mesh = getPortableMeshFrom(portable)
		if portableDrop.mesh ~= nil then
			beginPortableAttachNoCollision(portableDrop.mesh)
		end
	end
	local mesh = portableDrop.mesh
	if mesh ~= nil then
		local meshLoc = uevrUtils.getComponentLocation(mesh)
		if meshLoc ~= nil then
			local stored = portableDrop.lastMeshLoc
			if stored == nil then
				portableDrop.lastMeshLoc = { X = meshLoc.X, Y = meshLoc.Y, Z = meshLoc.Z }
			else
				stored.X = meshLoc.X
				stored.Y = meshLoc.Y
				stored.Z = meshLoc.Z
			end
		end
	end
	local hmd = controllers.getControllerLocation(2)
	local hx, hy, hz = nil, nil, nil
	if hmd ~= nil then
		hx = hmd.X
		hy = hmd.Y
		hz = hmd.Z
	end
	local loc = controllers.getControllerLocation(Handed.Right)
	if loc == nil then
		return
	end
	local hmdLoc = nil
	if hx ~= nil then
		hmdLoc = portableDrop.hmdCopy
		if hmdLoc == nil then
			hmdLoc = { X = hx, Y = hy, Z = hz }
			portableDrop.hmdCopy = hmdLoc
		else
			hmdLoc.X = hx
			hmdLoc.Y = hy
			hmdLoc.Z = hz
		end
	end
	physics.updateThrowSampler(throwSampler, loc, hmdLoc, delta)
end

local function captureWristVelocity()
	local kg = attachments.getAttachmentWeight(portableDrop.mesh)
	if kg == 0 then
		kg = DEFAULT_THROW_MASS
	end
	portableDrop.releaseVelocity = physics.getReleaseVelocity(throwSampler, NORMAL_THROW_KG_METERS * THROW_GAIN / kg)
end

local function onPortableReleased()
	setThrowing(true)
	uevrUtils.updateDeferral("portable_throwing")
	local mesh = portableDrop.mesh
	local loc = portableDrop.lastMeshLoc or throwSampler.lastHandLoc
	local velocity = nil
	if leftTriggerHeld then
		loc = pendingThrowAimLoc or loc
		local rot = pendingThrowAimRot
		local speed = 0
		local carryable = portableDrop.carryable
		if carryable ~= nil and carryable.InitialThrowSpeed ~= nil then
			speed = carryable.InitialThrowSpeed
		end
		if speed < 1 and uevrUtils.getValid(mesh) ~= nil then
			---@diagnostic disable-next-line: need-check-nil
			local current = mesh:GetPhysicsLinearVelocity()
			if current ~= nil then
				speed = math.sqrt((current.X or 0) * (current.X or 0) + (current.Y or 0) * (current.Y or 0) + (current.Z or 0) * (current.Z or 0))
			end
		end
		local forward = rot ~= nil and uevrUtils.getForwardVector(uevrUtils.rotator(rot)) or nil
		if forward ~= nil and speed >= 1 then
			velocity = { X = forward.X * speed, Y = forward.Y * speed, Z = forward.Z * speed }
		end
		pendingThrowAimLoc = nil
		pendingThrowAimRot = nil
	else
		velocity = portableDrop.releaseVelocity
		if velocity == nil then
			captureWristVelocity()
			velocity = portableDrop.releaseVelocity
		end
	end
	portableDrop.pending = {
		mesh = mesh,
		carryable = portableDrop.carryable,
		loc = loc,
		velocity = velocity,
	}
	portableDrop.holding = false
	portableDrop.mesh = nil
	portableDrop.lastMeshLoc = nil
	portableDrop.wait = 0
	physics.resetThrowSampler(throwSampler)
	attachments.detachGripAttachments(Handed.Right)
	if isPortableDocked(portableDrop.pending.carryable) then
		clearPortableDrop()
	end
end

local function updatePortableDrop(delta)
	local portable = getHoldingPortable()
	if portable ~= nil then
		updateHoldSampling(portable, delta)
		return
	end

	if portableDrop.holding then
		onPortableReleased()
	end

	local pending = portableDrop.pending
	if pending == nil then
		return
	end
	if uevrUtils.getValid(pending.mesh) == nil then
		clearPortableDrop()
		return
	end
	portableDrop.wait = portableDrop.wait + 1
	if applyPortableDrop(pending) or portableDrop.wait > 20 then
		clearPortableDrop()
	end
end

M.attachOptions = {
	detachFromOriginOnGrip = true,
	maintainWorldPositionOnDetachFromOrigin = true,
	detachFromParentOnRelease = true,
	maintainWorldPositionOnDetachFromParent = true,
	reattachToOriginOnRelease = false,
	restoreTransformToOriginOnReattach = false,
	useZeroTransformOnReattach = false,
	allowChildVisibilityHandling = false,
	allowChildHiddenInGameHandling = false,
	allowRenderInMainPassHandling = false,
	useCurrentAttachedSocketName = false,
	allowMobiltyChange = true,
}

uevrUtils.createDeferral("portable_throwing", THROW_LOCKOUT_MS, function()
	setThrowing(false)
end)

uevrUtils.createDeferral("portable_attach", ATTACH_NO_COLLISION_MS, function()
	if portableDrop.pending == nil then
		restorePortableAttachCollision()
	end
end)

local status = {}
uevr.sdk.callbacks.on_xinput_get_state(function(retval, user_index, state)
	--if not useVanilla then
		leftTriggerHeld = state.Gamepad.bLeftTrigger > TRIGGER_THRESHOLD
		if getHoldingPortable() ~= nil then
			if status.isThrowing ~= leftTriggerHeld then
				status.isThrowing = leftTriggerHeld
				if status.isThrowing then
					--print("Reticule: Right Controller")
					reticule.setTargetMethod(reticule.ReticuleTargetMethod.RIGHT_CONTROLLER)
					reticule.setTargetRotationOffset({Pitch=-AIM_OFFSET_PITCH, Yaw=AIM_OFFSET_YAW, Roll=0})
				else
					reticule.setTargetMethod(reticule.ReticuleTargetMethod.RIGHT_ATTACHMENT)
					reticule.setTargetRotationOffset({Pitch=0, Yaw=0, Roll=0})
				end
			end
		else
			if status.isThrowing then
				status.isThrowing = false
				reticule.setTargetMethod(reticule.ReticuleTargetMethod.RIGHT_ATTACHMENT)
				reticule.setTargetRotationOffset({Pitch=0, Yaw=0, Roll=0})
			end
		end
	--end
end)

-- Capture while the grip still exists. ServerRequestThrowCarryable never hits Lua.
local function captureThrowAim()
	local loc = attachments.getActiveAttachmentTransforms(Handed.Right)
	if loc == nil or (math.abs(loc.X or 0) <= 1 and math.abs(loc.Y or 0) <= 1 and math.abs(loc.Z or 0) <= 1) then
		return
	end
	pendingThrowAimLoc = uevrUtils.vector(loc.X, loc.Y, loc.Z)
	local rot = controllers.getControllerRotation(Handed.Right)
	if rot ~= nil then
		-- Match reticule aim (local offset then controller), then loft in world pitch for gravity.
		local aimRot = mathLib.composeRotators(uevrUtils.rotator(-AIM_OFFSET_PITCH, AIM_OFFSET_YAW, 0), rot)
		local forward = uevrUtils.getForwardVector(aimRot)
		local worldAim = kismet_math_library:Conv_VectorToRotator(forward)
		worldAim.Pitch = worldAim.Pitch + THROW_LOFT_PITCH
		pendingThrowAimRot = worldAim
	end
end

local function applyControllerPitchToGameThrow()
	if pendingThrowAimRot ~= nil and pawn ~= nil and pawn.GetPlayerCameraManager ~= nil then
		local pcm = pawn:GetPlayerCameraManager()
		local rotation = uevrUtils.getValid(pcm,{"CameraCachePrivate","POV","Rotation"})
		if rotation ~= nil then
			rotation.Pitch = pendingThrowAimRot.Pitch
			rotation.Yaw = pendingThrowAimRot.Yaw
		end
	end
end

hook_function("Class /Script/DeadIsland.CarryThrowAction", "OnThrowCarryable", true,
	function(fn, obj, locals)
		captureThrowAim()
		if useVanilla then
			applyControllerPitchToGameThrow()
			attachments.detachGripAttachments(Handed.Right)
		else
			if not leftTriggerHeld then
				captureWristVelocity()
			end
			setThrowing(true)
			uevrUtils.updateDeferral("portable_throwing")
		end
	end,
	nil,
	false
)

hook_function("Class /Script/DeadIsland.DIPlayerCharacter", "RequestCarryDeselect", true,
	function(fn, obj, locals)
		if not useVanilla and not leftTriggerHeld and portableDrop.holding then
			captureWristVelocity()
		end
	end,
	nil,
	false
)

uevr.sdk.callbacks.on_post_engine_tick(function(engine, delta)
	if not useVanilla then
		updatePortableDrop(delta)
	end
end)

local function hookFunctions()
	-- Y weapon-switch ends carry hold while the portable is still gripped.
	hook_function("BlueprintGeneratedClass /Game/DI2/Player/Actions/Carry/BP_Action_Player_CarryHold.BP_Action_Player_CarryHold_C", "OnEnd", false,
		function(fn, obj, locals)
			if useVanilla and getHoldingPortable() ~= nil then
				attachments.detachGripAttachments(Handed.Right)
			elseif not useVanilla and not leftTriggerHeld and portableDrop.holding then
				captureWristVelocity()
			end
		end,
		nil,
		false
	)
end

uevrUtils.registerLevelChangeCallback(function(level)
	hookFunctions()
end)


return M

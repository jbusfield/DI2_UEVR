local uevrUtils = require('libs/uevr_utils')
local attachments = require('libs/attachments')
local controllers = require('libs/controllers')
local physics = require('libs/physics')

local M = {}

-- Max range at a full-speed swing: 20 * THROW_GAIN / weightKg (gain 5, 10 kg -> 10 m).
-- Wrist speed between dropSpeed and fullSpeed (measured max flick ~704) scales that range.
local THROW_GAIN = 5.0
local DEFAULT_THROW_MASS = 2
local NORMAL_THROW_KG_METERS = 20.0
local THROW_LOCKOUT_MS = 1000
local ATTACH_NO_COLLISION_MS = 1000
local DOCK_WAIT_FRAMES = 10
local TRIGGER_THRESHOLD = 128

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
	pcall(function()
	---@diagnostic disable-next-line: need-check-nil
		mesh:SetCollisionEnabled(ECollisionEnabled.QueryAndPhysics)
	end)
end

local function beginPortableAttachNoCollision(mesh)
	if uevrUtils.getValid(mesh) == nil then
		return
	end
	if attachCollisionMesh ~= nil and attachCollisionMesh ~= mesh then
		restorePortableAttachCollision()
	end
	attachCollisionMesh = mesh
	pcall(function()
		mesh:SetCollisionEnabled(ECollisionEnabled.NoCollision)
	end)
	uevrUtils.updateDeferral("portable_attach")
end

local function getHoldingPortable()
	local pawn = uevrUtils.get_local_pawn()
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

-- Batteries and circuit breakers dock into slots; the game then owns the actor.
local function isPortableDocked(carryable)
	local docked = false
	pcall(function()
		if uevrUtils.getValid(carryable) == nil then
			return
		end
		if carryable:IsDocked() == true then
			docked = true
			return
		end
		local owner = carryable:GetOwner()
		local dockable = owner ~= nil and owner.Dockable or nil
		docked = dockable ~= nil and dockable.RepDockedWith ~= nil
	end)
	return docked
end

local function clearPortableDrop()
	restorePortableAttachCollision()
	portableDrop.pending = nil
	portableDrop.mesh = nil
	portableDrop.carryable = nil
	portableDrop.lastMeshLoc = nil
	portableDrop.wait = 0
	physics.resetThrowSampler(throwSampler)
end

local function applyPortableDrop(pending)
	if isPortableDocked(pending.carryable) then
		return true
	end
	if pending.dockWait > 0 then
		pending.dockWait = pending.dockWait - 1
		return false
	end
	if pending.armed ~= true then
		pending.armed = true
		setThrowing(true)
		uevrUtils.updateDeferral("portable_throwing")
	end
	local mesh = pending.mesh
	if uevrUtils.getValid(mesh) == nil then
		return true
	end
	if mesh.AttachParent ~= nil then
		pcall(function()
			mesh:DetachFromParent(true, false)
		end)
	end
	if mesh.AttachParent ~= nil then
		return false
	end

	if pending.placed ~= true then
		local loc = pending.loc
		if loc ~= nil and (loc.X * loc.X + loc.Y * loc.Y + loc.Z * loc.Z) > 1 then
			pcall(function()
				mesh:K2_SetWorldLocation(uevrUtils.vector(loc.X, loc.Y, loc.Z), false, reusable_hit_result, true)
			end)
		end
		pending.placed = true
		return false
	end

	restorePortableAttachCollision()
	physics.applyThrowVelocity(mesh, pending.velocity)
	return true
end

local function updatePortableDrop(delta)
	local portable = getHoldingPortable()
	if portable ~= nil then
		if not portableDrop.holding then
			portableDrop.holding = true
			portableDrop.pending = nil
			portableDrop.wait = 0
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
		return
	end

	if portableDrop.holding then
		local mesh = portableDrop.mesh
		local loc = portableDrop.lastMeshLoc or throwSampler.lastHandLoc
		local velocity = nil
		local dockWait = 0
		if leftTriggerHeld then
			loc = pendingThrowAimLoc or loc
			local rot = pendingThrowAimRot
			local speed = 0
			pcall(function()
				local carryable = portableDrop.carryable
				if carryable ~= nil and carryable.InitialThrowSpeed ~= nil then
					speed = carryable.InitialThrowSpeed
				end
			end)
			if speed < 1 and uevrUtils.getValid(mesh) ~= nil then
				pcall(function()
					local current = mesh:GetPhysicsLinearVelocity()
					if current ~= nil then
						speed = math.sqrt((current.X or 0) * (current.X or 0) + (current.Y or 0) * (current.Y or 0) + (current.Z or 0) * (current.Z or 0))
					end
				end)
			end
			local forward = rot ~= nil and uevrUtils.getForwardVector(uevrUtils.rotator(rot)) or nil
			if forward ~= nil and speed >= 1 then
				velocity = { X = forward.X * speed, Y = forward.Y * speed, Z = forward.Z * speed }
			end
			pendingThrowAimLoc = nil
			pendingThrowAimRot = nil
		else
			local kg = attachments.getAttachmentWeight(mesh)
			if kg == 0 then
				kg = DEFAULT_THROW_MASS
			end
			velocity = physics.getReleaseVelocity(throwSampler, NORMAL_THROW_KG_METERS * THROW_GAIN / kg)
			pcall(function()
				local owner = portableDrop.carryable ~= nil and portableDrop.carryable:GetOwner() or nil
				if owner ~= nil and owner.Dockable ~= nil then
					dockWait = DOCK_WAIT_FRAMES
				end
			end)
		end
		portableDrop.pending = {
			mesh = mesh,
			carryable = portableDrop.carryable,
			loc = loc,
			velocity = velocity,
			placed = false,
			dockWait = dockWait,
			armed = false,
		}
		portableDrop.holding = false
		portableDrop.mesh = nil
		portableDrop.lastMeshLoc = nil
		portableDrop.wait = 0
		physics.resetThrowSampler(throwSampler)
		attachments.detachGripAttachments(Handed.Right)
		if isPortableDocked(portableDrop.pending.carryable) then
			clearPortableDrop()
			return
		end
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
	if applyPortableDrop(pending) or (pending.dockWait <= 0 and portableDrop.wait > 20) then
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

uevr.sdk.callbacks.on_xinput_get_state(function(retval, user_index, state)
	leftTriggerHeld = state.Gamepad.bLeftTrigger > TRIGGER_THRESHOLD
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
		pendingThrowAimRot = uevrUtils.rotator(rot.Pitch, rot.Yaw, rot.Roll)
	end
end

hook_function("Class /Script/DeadIsland.CarryThrowAction", "OnThrowCarryable", true,
	function(fn, obj, locals)
		captureThrowAim()
	end,
	nil,
	false
)

uevr.sdk.callbacks.on_post_engine_tick(function(engine, delta)
	updatePortableDrop(delta)
end)

return M

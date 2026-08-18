local uevrUtils = require('libs/uevr_utils')
local mathLib = require('libs/core/math_lib')
local montage = require('libs/montage')
local gestures = require('libs/gestures')
local input = require('libs/input')
local attachments = require('libs/attachments')

---------------------------------------------------------------------------
-- VR melee: RequestBeginStandardAttack (durability / attack state), mute body
-- attack montages, manually SetLinkedWeapon + SetSweepActive for controller hits.
---------------------------------------------------------------------------
local status = {}
local EMeleeItemState = {
	Idle = 0,
	StandardAttack = 1,
}

local function isMeleeItemActor(actor)
	return uevrUtils.getValid(actor) ~= nil and actor.RequestBeginStandardAttack ~= nil
end

local function isAttackMontageName(name)
	if type(name) ~= "string" or name == "" then return false end
	return string.find(name, "StandardAttack", 1, true) ~= nil
		or string.find(name, "AttackAnticipation", 1, true) ~= nil
		or string.find(name, "AttackRecovery", 1, true) ~= nil
		or string.find(name, "HeavyAttack", 1, true) ~= nil
		or string.find(name, "RepeatTransition", 1, true) ~= nil
end

local function stopMutedAttackMontage()
	local muted = status.vrMeleeMutedMontage
	status.vrMeleeMutedMontage = nil
	if uevrUtils.getValid(muted) == nil then return end
	montage.stop(muted, nil, 0.0)
	local pawn = uevrUtils.get_local_pawn()
	local fp = pawn and (pawn.MeshFirstPerson or pawn.FPVMesh)
	if uevrUtils.getValid(fp) ~= nil and fp.AnimScriptInstance ~= nil then
		fp.AnimScriptInstance:Montage_Stop(0.0, muted)
	end
end

attachments.registerAttachmentChangeCallback(function(id, gripHand, attachment)
	local isMeleeWeapon = type(id) == "string" and string.find(id, "BP_MeleeWeapon", 1, true) == 1
	gestures.autoDetectGesture(gestures.Gesture.SWIPE_RIGHT, isMeleeWeapon)
	gestures.autoDetectGesture(gestures.Gesture.SWIPE_LEFT, isMeleeWeapon)
	status.isMeleeWeapon = isMeleeWeapon
end)

local function getMainhandItemActor()
	local pawn = uevrUtils.get_local_pawn()
	if pawn == nil then return nil end

	-- TODO check this. Why checking both hands? How do claws work?
	local proxy = pawn.BPC_Player_WeaponProxy
	if proxy ~= nil and proxy.GetChildActorForHand ~= nil then
		for hand = 0, 1 do
			local childComp = proxy:GetChildActorForHand(hand)
			local actor = childComp and childComp.ChildActor
			if isMeleeItemActor(actor) then
				return actor
			end
		end
	end

	-- backup method if above method failed
	if uevrUtils.getValid(status.cachedWeaponUtils) == nil then
		status.cachedWeaponUtils = uevrUtils.find_default_instance("Class /Script/DeadIsland.WeaponUtils")
	end
	if status.cachedWeaponUtils ~= nil and proxy ~= nil then
		for hand = 0, 1 do
			local item = status.cachedWeaponUtils:GetCurrentItemFromPlayerWeaponProxy(proxy, hand)
			if isMeleeItemActor(item) then
				return item
			end
		end
	end
	return nil
end

local function getMeleeSweepComponent(weapon)
	-- try the various ways of getting the sweep component
	local sweep = uevrUtils.getValid(pawn, {"BPC_Player_MeleeSweep"})
	if sweep ~= nil then return sweep end
	sweep = uevrUtils.getValid(weapon, {"CurrentMeleeSweep"})
	if sweep ~= nil then return sweep end
	sweep = uevrUtils.getValid(weapon, {"MeleeSweepComponent"})
	return sweep
end

local function getWeaponMesh()
	local pawn = uevrUtils.get_local_pawn()
	if pawn == nil then return nil end
	local proxy = pawn.BPC_Player_WeaponProxy
	if proxy == nil or proxy.GetChildActorForHand == nil then return nil end
	local childComp = proxy:GetChildActorForHand(0)
	local weaponActor = childComp and childComp.ChildActor
	if weaponActor == nil then return nil end
	return weaponActor.WeaponMesh or weaponActor.SkeletalMesh
end

local function endVrMeleeSweep()
	local sweep = status.vrMeleeSweep
	local weapon = status.vrMeleeWeapon
	if uevrUtils.getValid(sweep) ~= nil then
---@diagnostic disable-next-line: need-check-nil
		sweep:SetSweepActive(false)
	end
	stopMutedAttackMontage()
	if status.vrMeleeUsedRequestBegin and isMeleeItemActor(weapon) then
---@diagnostic disable-next-line: need-check-nil
		weapon:OnEndRequestedState(EMeleeItemState.StandardAttack)
	end
	if isMeleeItemActor(weapon) then
		weapon.ActiveState = EMeleeItemState.Idle
	end
	status.vrMeleeSweep = nil
	status.vrMeleeWeapon = nil
	status.vrMeleeSweepActive = false
	status.vrMeleeUsedRequestBegin = nil
end

local function beginVrMeleeSweep()
	local gripMesh = getWeaponMesh()
	if uevrUtils.getValid(gripMesh) == nil then return false end

	local weapon = getMainhandItemActor()
	if not isMeleeItemActor(weapon) then
---@diagnostic disable-next-line: need-check-nil
		local owner = gripMesh:GetOwner()
		if isMeleeItemActor(owner) then
			weapon = owner
		end
	end
	if not isMeleeItemActor(weapon) then return false end

	local sweep = getMeleeSweepComponent(weapon)
	if uevrUtils.getValid(sweep) == nil or sweep == nil then return false end

	status.vrMeleeSweep = sweep
	status.vrMeleeWeapon = weapon
	status.vrMeleeSweepActive = true
	status.vrMeleeUsedRequestBegin = false
	status.vrMeleeMutedMontage = nil

	sweep:SetLinkedWeapon(gripMesh)
	sweep:ClearPreviouslyHitComponents()

	---@diagnostic disable-next-line: need-check-nil
	local began = weapon:RequestBeginStandardAttack() == true
	status.vrMeleeUsedRequestBegin = began

	sweep:SetSweepActive(true)
	return true
end

uevrUtils.createDeferral("vr_melee_sweep", 700, function()
	endVrMeleeSweep()
end)

hook_function("Class /Script/Engine.AnimInstance", "Montage_Play", true,
	function(fn, obj, locals)
		if not status.vrMeleeSweepActive then return end
		local mont = locals and locals.MontageToPlay
		if uevrUtils.getValid(mont) == nil then return end
		if not isAttackMontageName(uevrUtils.getShortName(mont)) then return end
		locals.InPlayRate = 0.0
		status.vrMeleeMutedMontage = mont
	end,
	nil,
	false
)

local function animateMelee(direction)
	if status.isMeleeWeapon ~= true then return end
	input.setAimMethod(input.AimMethod.RIGHT_WEAPON)
	input.setAimRotationOffset(attachments.getActiveAttachmentMeleeRotationOffset(Handed.Right))

	if status.vrMeleeSweepActive then
		endVrMeleeSweep()
	end
	beginVrMeleeSweep()
	uevrUtils.updateDeferral("vr_melee_sweep")
end

gestures.registerSwipeRightCallback(function()
	animateMelee(1)
end)

gestures.registerSwipeLeftCallback(function()
	animateMelee(0)
end)

---------------------------------------------------------------------------
-- Melee throw aim: patch ServerRequestThrowItem to match RIGHT_ATTACHMENT.
---------------------------------------------------------------------------
local MELEE_THROW_USE_LINE_TRACE = true -- true is theoretically more accurate but both ways seems to give the same result
local MELEE_THROW_TRACE_DISTANCE = 10000.0
local MELEE_THROW_MIN_HIT_DISTANCE = 10.0
-- local meleeThrowAimActive = false

local function getMeleeThrowAimLocationRotation()
	local location, rotation = attachments.getActiveAttachmentTransforms(Handed.Right)
	if location == nil or rotation == nil then
		return nil, nil
	end
	return location, rotation
end

local function getMeleeThrowTargetLocation(spawnLoc, aimRot)
	local forward = uevrUtils.getForwardVector(aimRot)
	if forward == nil then
		return nil
	end
	if MELEE_THROW_USE_LINE_TRACE then
		local _, targetLoc = uevrUtils.getLineTraceHitResult(
			uevrUtils.vector(spawnLoc),
			forward,
			0,
			false,
			{},
			MELEE_THROW_MIN_HIT_DISTANCE,
			MELEE_THROW_TRACE_DISTANCE
		)
		if targetLoc ~= nil then
			return uevrUtils.vector(targetLoc)
		end
	end
	return uevrUtils.vector(
		spawnLoc.X + forward.X * MELEE_THROW_TRACE_DISTANCE,
		spawnLoc.Y + forward.Y * MELEE_THROW_TRACE_DISTANCE,
		spawnLoc.Z + forward.Z * MELEE_THROW_TRACE_DISTANCE
	)
end

local function buildMeleeThrowAimData()
	local spawnLoc, aimRot = getMeleeThrowAimLocationRotation()
	if spawnLoc == nil or aimRot == nil then
		return nil
	end

	local aimRotator = uevrUtils.rotator(aimRot)
	local targetLoc = getMeleeThrowTargetLocation(spawnLoc, aimRot)
	if targetLoc == nil then
		return nil
	end

	return {
		spawnLoc = spawnLoc,
		aimRotator = aimRotator,
		targetLoc = targetLoc,
		throwTransform = kismet_math_library:MakeTransform(uevrUtils.vector(spawnLoc), aimRotator, uevrUtils.vector(1, 1, 1)),
	}
end

local function applyMeleeThrowAimToThrowItem(locals)
	if locals == nil or not isMeleeItemActor(locals.Item) then
		return
	end

	local data = buildMeleeThrowAimData()
	if data == nil then
		return
	end

	locals.RequesterCameraTransform = locals.RequesterCameraTransform or data.throwTransform
	locals.ProjectileSpawnTransform = locals.ProjectileSpawnTransform or data.throwTransform
	locals.VisualTransform = locals.VisualTransform or data.throwTransform
	mathLib.assignTransformInPlace(locals.RequesterCameraTransform, data.throwTransform)
	mathLib.assignTransformInPlace(locals.ProjectileSpawnTransform, data.throwTransform)
	mathLib.assignTransformInPlace(locals.VisualTransform, data.throwTransform)

	local targetPointInfo = locals.TargetPointInfo
	if targetPointInfo ~= nil then
		targetPointInfo.VectorLocation = uevrUtils.vector(data.targetLoc)
		targetPointInfo.bVectorValid = true
		targetPointInfo.bRotatorValid = true
		targetPointInfo.RotatorRotation = data.aimRotator
	end
end

-- local function endMeleeThrowAim()
-- 	if not meleeThrowAimActive then
-- 		return
-- 	end
-- 	meleeThrowAimActive = false
-- end

-- local function beginMeleeThrowAim()
-- 	meleeThrowAimActive = true
-- 	uevrUtils.updateDeferral("melee_throw_aim")
-- end

-- uevrUtils.createDeferral("melee_throw_aim", MELEE_THROW_AIM_MS, function()
-- 	endMeleeThrowAim()
-- end)

-- hook_function("Class /Script/DeadIsland.MeleeWeaponItemActor", "RequestBeginThrow", true,
-- 	function(fn, obj, locals)
-- 		print("[DI2] RequestBeginThrow")
-- 		beginMeleeThrowAim()
-- 	end,
-- 	nil,
-- 	false
-- )

hook_function("Class /Script/DeadIsland.DIPlayerCharacter", "ServerRequestThrowItem", true,
	function(fn, obj, locals)
		--print("[DI2] ServerRequestThrowItem")
		applyMeleeThrowAimToThrowItem(locals)
		-- uevrUtils.updateDeferral("melee_throw_aim")
	end,
	nil,
	false
)

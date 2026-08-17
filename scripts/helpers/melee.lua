local uevrUtils = require('libs/uevr_utils')
local montage = require('libs/montage')
local gestures = require('libs/gestures')
local input = require('libs/input')
local attachments = require('libs/attachments')
local plugin = require('libs/core/plugin')

---------------------------------------------------------------------------
-- VR melee: RequestBeginStandardAttack (durability / attack state), mute body
-- attack montages, manually SetLinkedWeapon + SetSweepActive for controller hits.
---------------------------------------------------------------------------
local status = {}
local EMeleeItemState_Idle = 0
local EMeleeItemState_StandardAttack = 1
local cachedWeaponUtils = nil

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

	if uevrUtils.getValid(cachedWeaponUtils) == nil then
		cachedWeaponUtils = uevrUtils.find_default_instance("Class /Script/DeadIsland.WeaponUtils")
	end
	if cachedWeaponUtils ~= nil and proxy ~= nil then
		for hand = 0, 1 do
			local item = cachedWeaponUtils:GetCurrentItemFromPlayerWeaponProxy(proxy, hand)
			if isMeleeItemActor(item) then
				return item
			end
		end
	end
	return nil
end

local function getMeleeSweepComponent(weapon)
	local pawn = uevrUtils.get_local_pawn()
	if uevrUtils.getValid(pawn) ~= nil then
		local sweep = pawn.BPC_Player_MeleeSweep
		if uevrUtils.getValid(sweep) ~= nil then
			return sweep
		end
	end
	if uevrUtils.getValid(weapon) ~= nil then
		local sweep = weapon.CurrentMeleeSweep or weapon.MeleeSweepComponent
		if uevrUtils.getValid(sweep) ~= nil then
			return sweep
		end
	end
	return nil
end

local function getItemVisualWeaponMesh(weapon)
	if uevrUtils.getValid(weapon) == nil or weapon.GetVisualWeaponMeshComponents == nil then
		return nil
	end
	local result = plugin.executeFunction(weapon, "GetVisualWeaponMeshComponents", {})
	local visuals = result and (result.ReturnValue or result.OutMeshes or result.VisualWeaponMeshComponents)
	if type(visuals) ~= "table" then return nil end
	for _, v in ipairs(visuals) do
		if uevrUtils.getValid(v) ~= nil then
			return v
		end
	end
	return nil
end

local function prepareLinkedMeshForVr(grip, linked)
	if uevrUtils.getValid(grip) == nil or uevrUtils.getValid(linked) == nil or grip == linked then
		return
	end
	if status.vrMeleeLinkedPrepared then return end
	linked:DetachFromParent(true, false)
	linked:K2_AttachToComponent(grip, "", 2, 2, 2, false)
	if linked.SetRelativeLocation ~= nil then
		linked:SetRelativeLocation({X=0,Y=0,Z=0}, false, reusable_hit_result, false)
	end
	if linked.SetRelativeRotation ~= nil then
		linked:SetRelativeRotation({Pitch=0,Yaw=0,Roll=0}, false, reusable_hit_result, false)
	end
	if linked.SetMasterPoseComponent ~= nil then
		linked:SetMasterPoseComponent(grip, true)
	end
	status.vrMeleeLinkedPrepared = true
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
		weapon:OnEndRequestedState(EMeleeItemState_StandardAttack)
	end
	if isMeleeItemActor(weapon) then
		weapon.ActiveState = EMeleeItemState_Idle
	end
	local linked = status.vrMeleeLinkedMesh
	local grip = status.vrMeleeGripMesh
	if status.vrMeleeLinkedPrepared and uevrUtils.getValid(linked) ~= nil and linked ~= grip then
---@diagnostic disable-next-line: need-check-nil
		if linked.SetMasterPoseComponent ~= nil then
---@diagnostic disable-next-line: need-check-nil
			linked:SetMasterPoseComponent(nil, true)
		end
---@diagnostic disable-next-line: need-check-nil
		linked:DetachFromParent(true, false)
	end
	status.vrMeleeSweep = nil
	status.vrMeleeWeapon = nil
	status.vrMeleeGripMesh = nil
	status.vrMeleeLinkedMesh = nil
	status.vrMeleeLinkedPrepared = nil
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

	local itemVisual = getItemVisualWeaponMesh(weapon)
	local linkMesh = gripMesh
	if uevrUtils.getValid(itemVisual) ~= nil and itemVisual ~= gripMesh then
		linkMesh = itemVisual
	end

	local sweep = getMeleeSweepComponent(weapon)
	if uevrUtils.getValid(sweep) == nil then return false end

	status.vrMeleeGripMesh = gripMesh
	status.vrMeleeLinkedMesh = linkMesh
	status.vrMeleeLinkedPrepared = false
	status.vrMeleeSweep = sweep
	status.vrMeleeWeapon = weapon
	status.vrMeleeSweepActive = true
	status.vrMeleeUsedRequestBegin = false
	status.vrMeleeMutedMontage = nil

	prepareLinkedMeshForVr(gripMesh, linkMesh)
	local linkTarget = uevrUtils.getValid(gripMesh) ~= nil and gripMesh or linkMesh
	if uevrUtils.getValid(linkTarget) ~= nil then
---@diagnostic disable-next-line: need-check-nil
		sweep:SetLinkedWeapon(linkTarget)
	end
---@diagnostic disable-next-line: need-check-nil
	sweep:ClearPreviouslyHitComponents()

---@diagnostic disable-next-line: need-check-nil
	local began = weapon:RequestBeginStandardAttack() == true
	status.vrMeleeUsedRequestBegin = began
	if not began then
		weapon.ActiveState = EMeleeItemState_StandardAttack
	end

---@diagnostic disable-next-line: need-check-nil
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

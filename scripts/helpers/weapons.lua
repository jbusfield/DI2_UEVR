local uevrUtils = require('libs/uevr_utils')

local M = {}

function M.getWeaponMesh()
	local pawn = uevrUtils.get_local_pawn()
	if not pawn then
		return nil, nil
	end

	--ranged weapons
	local paperDoll = pawn.BPC_Player_PaperDoll
	local item = paperDoll and paperDoll.GetItemFor and paperDoll:GetItemFor(0) -- EDIPaperDollSlot.Weapon
	if uevrUtils.getValid(item) ~= nil then
		local modules = item.RangedWeaponModulesComponent
		local visual = modules and modules.GetOwnerVisualActor and modules:GetOwnerVisualActor()
		if uevrUtils.getValid(visual) ~= nil then
			if visual.WeaponMesh ~= nil then return visual.WeaponMesh, nil end
			if visual.SkeletalMesh ~= nil then return visual.SkeletalMesh, nil end
		end
	end

	--melee weapons
	local proxy = pawn.BPC_Player_WeaponProxy  -- UWeaponProxyComponent
	--right hand melee weapons
	local rightChildComp = proxy:GetChildActorForHand(0)
	local rightWeaponActor = rightChildComp and rightChildComp.ChildActor
	local rightMesh = nil
	if rightWeaponActor then
		local mesh = rightWeaponActor.WeaponMesh
		if mesh then
			rightMesh = mesh
		else
			rightMesh = rightWeaponActor.SkeletalMesh
		end
	end
	--left hand melee weapons
	local leftChildComp = proxy:GetChildActorForHand(1)
	local leftWeaponActor = leftChildComp and leftChildComp.ChildActor
	local leftMesh = nil
	if leftWeaponActor then
		local mesh = leftWeaponActor.WeaponMesh
		if mesh then
			leftMesh = mesh
		else
			leftMesh = leftWeaponActor.SkeletalMesh
		end
	end
	return rightMesh, leftMesh
end

function M.getMeleeWeaponMesh(hand)
	local pawn = uevrUtils.get_local_pawn()
	if pawn == nil then return nil end
	local proxy = pawn.BPC_Player_WeaponProxy
	if proxy == nil or proxy.GetChildActorForHand == nil then return nil end
	local handIndex = hand == Handed.Left and 1 or 0
	local childComp = proxy:GetChildActorForHand(handIndex)
	local weaponActor = childComp and childComp.ChildActor
	if weaponActor == nil then return nil end
	return weaponActor.WeaponMesh or weaponActor.SkeletalMesh
end

-- Grip only moves WeaponMesh; PSC FX on the actor root stay on MeshFirstPerson.
function M.reparentWeaponFx(weaponMesh)
	if uevrUtils.getValid(weaponMesh) == nil then return end
	local owner = uevrUtils.getValid(weaponMesh.GetOwner and weaponMesh:GetOwner() or nil)
	if owner == nil or owner.K2_GetComponentsByClass == nil then return end
	local pscClass = uevrUtils.get_class("Class /Script/Engine.ParticleSystemComponent")
	if pscClass == nil then return end
	---@diagnostic disable-next-line: undefined-field
	local comps = owner:K2_GetComponentsByClass(pscClass)
	if comps == nil then return end
	for _, fx in pairs(comps) do
		if uevrUtils.getValid(fx) ~= nil and fx.AttachParent ~= weaponMesh and fx.K2_AttachTo ~= nil then
			fx:K2_AttachTo(weaponMesh, uevrUtils.fname_from_string(""), 0, false)
		end
	end
end

return M

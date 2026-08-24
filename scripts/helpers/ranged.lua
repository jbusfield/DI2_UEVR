local uevrUtils = require('libs/uevr_utils')
local weapons = require('helpers/weapons')

local M = {}

----------------- Ranged weapon Aim fix -------------------------------------------
-- Hitscan guns default to RaycastLocalCameraFallbackToMuzzle, which follows the
-- FP camera (body yaw + aim pitch). RaycastFromMuzzle uses the weapon Muzzle socket.
-- Keep the 180° alignment push so VR hip-fire is not filtered.
local ETargetPointRaycastType_RaycastFromMuzzle = 1

local function applyMuzzleAimToProjectileSpawner(spawner)
	if uevrUtils.getValid(spawner) == nil then return end
	if spawner.RaycastType ~= nil then
		spawner.RaycastType = ETargetPointRaycastType_RaycastFromMuzzle
	end
	if spawner.bLocalUserPushActionIfMuzzleAligmentGreaterThanTolerance ~= nil then
		spawner.bLocalUserPushActionIfMuzzleAligmentGreaterThanTolerance = true
	end
	if spawner.LocalUserMuzzleAlignmentToleranceDegrees ~= nil then
		spawner.LocalUserMuzzleAlignmentToleranceDegrees = 180
	end
end

local function applyMuzzleAimToFireMode(fireMode)
	if uevrUtils.getValid(fireMode) == nil then return end
	applyMuzzleAimToProjectileSpawner(fireMode.ProjectileSpawner)
	applyMuzzleAimToProjectileSpawner(fireMode.SecondaryProjectileSpawner)
	local adj = fireMode.LaunchAdjustmentHandler
	if uevrUtils.getValid(adj) == nil then return end
	if adj.MaxAdjustScreenSpacePercentage ~= nil then
		adj.MaxAdjustScreenSpacePercentage = 0
	end
	if adj.bUseCachedPlayerAutoAimResults ~= nil then
		adj.bUseCachedPlayerAutoAimResults = false
	end
end

function M.applyRangedWeaponMuzzleAim()
	local pawn = uevrUtils.get_local_pawn()
	if pawn == nil then return end
	local paperDoll = pawn.BPC_Player_PaperDoll
	local item = paperDoll and paperDoll.GetItemFor and paperDoll:GetItemFor(0)
	local modules = uevrUtils.getValid(item) ~= nil and item.RangedWeaponModulesComponent or nil
	if uevrUtils.getValid(modules) == nil or modules == nil then return end
	if modules.GetSelectedProjectileSpawner ~= nil then
		applyMuzzleAimToProjectileSpawner(modules:GetSelectedProjectileSpawner())
	end
	if modules.GetSelectedFireMode ~= nil then
		applyMuzzleAimToFireMode(modules:GetSelectedFireMode())
	end
end

function M.setEquippedWeaponHidden(hidden)
	local mesh, _ = weapons.getWeaponMesh()
	if uevrUtils.getValid(mesh) == nil or mesh == nil then
		return
	end
	pcall(function()
		mesh:SetHiddenInGame(hidden, true)
	end)
	local owner = mesh.GetOwner ~= nil and mesh:GetOwner() or nil
	if owner ~= nil then
		pcall(function()
			owner:SetActorHiddenInGame(hidden)
		end)
	end
end
----------------- End Ranged weapon Aim fix -------------------------------------------

return M

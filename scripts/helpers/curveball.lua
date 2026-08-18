local uevrUtils = require('libs/uevr_utils')
local mathLib = require('libs/core/math_lib')
local attachments = require('libs/attachments')

---------------------------------------------------------------------------
-- Curveball aim: PerformQuickThrow still has the weapon; spawn does not.
---------------------------------------------------------------------------
local CURVEBALL_FAR_TARGET_DISTANCE = 10000.0

local function getRightAttachmentLocationRotation()
	local location, rotation = attachments.getActiveAttachmentTransforms(Handed.Right)
	if location == nil or rotation == nil then
		return nil, nil
	end
	return location, rotation
end

local function isUsableAimLocation(location)
	if location == nil then
		return false
	end
	return math.abs(location.X or 0) > 1 or math.abs(location.Y or 0) > 1 or math.abs(location.Z or 0) > 1
end

local pendingCurveballAimLoc = nil
local pendingCurveballAimRot = nil

local function captureCurveballAim()
	local loc, rot = getRightAttachmentLocationRotation()
	if loc == nil or rot == nil or not isUsableAimLocation(loc) then
		return
	end
	pendingCurveballAimLoc = uevrUtils.vector(loc.X, loc.Y, loc.Z)
	pendingCurveballAimRot = uevrUtils.rotator(rot.Pitch, rot.Yaw, rot.Roll)
end

local function getCurveballAimLocationRotation()
	if isUsableAimLocation(pendingCurveballAimLoc) then
		return pendingCurveballAimLoc, pendingCurveballAimRot
	end
	local location, rotation = getRightAttachmentLocationRotation()
	if isUsableAimLocation(location) then
		return location, rotation
	end
	return nil, nil
end

local function buildCurveballAimData()
	local spawnLoc, aimRot = getCurveballAimLocationRotation()
	if spawnLoc == nil or aimRot == nil then
		return nil
	end
	local forward = uevrUtils.getForwardVector(aimRot)
	if forward == nil then
		return nil
	end
	local aimRotator = uevrUtils.rotator(aimRot)
	return {
		spawnLoc = spawnLoc,
		aimRotator = aimRotator,
		forward = forward,
		throwTransform = kismet_math_library:MakeTransform(uevrUtils.vector(spawnLoc), aimRotator, uevrUtils.vector(1, 1, 1)),
	}
end

local function applyCurveballAimToSpawnParams(locals)
	local params = locals and locals.RequestSpawnProjectileParams
	if params == nil then
		return
	end
	local data = buildCurveballAimData()
	if data == nil then
		return
	end
	if params.Origin ~= nil then
		mathLib.assignVectorInPlace(params.Origin, data.spawnLoc)
	end
	params.Origin = uevrUtils.vector(data.spawnLoc)
	if params.Direction ~= nil then
		mathLib.assignVectorInPlace(params.Direction, data.forward)
	end
	params.Direction = uevrUtils.vector(data.forward)
	if params.RequesterCameraTransform ~= nil then
		mathLib.assignTransformInPlace(params.RequesterCameraTransform, data.throwTransform)
	end
	if params.CosmeticProjectileTransform ~= nil then
		mathLib.assignTransformInPlace(params.CosmeticProjectileTransform, data.throwTransform)
	end
	local target = params.TargetPointInfo
	if target ~= nil then
		local farTarget = uevrUtils.vector(
			data.spawnLoc.X + data.forward.X * CURVEBALL_FAR_TARGET_DISTANCE,
			data.spawnLoc.Y + data.forward.Y * CURVEBALL_FAR_TARGET_DISTANCE,
			data.spawnLoc.Z + data.forward.Z * CURVEBALL_FAR_TARGET_DISTANCE
		)
		if target.VectorLocation ~= nil then
			mathLib.assignVectorInPlace(target.VectorLocation, farTarget)
		end
		target.VectorLocation = farTarget
		target.bVectorValid = true
		target.bRotatorValid = false
	end
	pendingCurveballAimLoc = nil
	pendingCurveballAimRot = nil
end

hook_function("Class /Script/DeadIsland.DIPlayerCharacter", "PerformQuickThrow", true,
	function(fn, obj, locals)
		captureCurveballAim()
	end,
	nil,
	false
)

hook_function("Class /Script/DeadIsland.ActorProjectileSpawnModule", "ServerRequestSpawnProjectileActors", true,
	function(fn, obj, locals)
		if obj == nil or obj.bSpawnProjectilesAtLocalUserCameraOrigin ~= true then
			return
		end
		applyCurveballAimToSpawnParams(locals)
	end,
	nil,
	false
)

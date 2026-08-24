local uevrUtils = require('libs/uevr_utils')
local configui = require('libs/configui')

local M = {}

---------------------------------------------------------------------------
-- Flashlight (ScopedSpotlight on SpringArmComponentForTorch): the spring arm
-- uses pawn control rotation, so pitch comes from the aim pose while yaw stays
-- on the body. Drive the light from HMD / left / right via motion controller state.
---------------------------------------------------------------------------
local FlashlightLocation = {
	Head = 1,
	LeftHand = 2,
	RightHand = 3,
}

local flashlightOffsetIds = {
	[FlashlightLocation.Head] = { position = "flashlight_head_position", rotation = "flashlight_head_rotation" },
	[FlashlightLocation.LeftHand] = { position = "flashlight_left_position", rotation = "flashlight_left_rotation" },
	[FlashlightLocation.RightHand] = { position = "flashlight_right_position", rotation = "flashlight_right_rotation" },
}

local flashlightStatus = {}

local function flashlightHandFromLocation(location)
	if location == FlashlightLocation.LeftHand then return Handed.Left end
	if location == FlashlightLocation.RightHand then return Handed.Right end
	return 2 -- HMD
end

local function vec3FromConfig(value)
	if value == nil then return 0, 0, 0 end
	if value.X ~= nil then return value.X or 0, value.Y or 0, value.Z or 0 end
	if value.Pitch ~= nil then return value.Pitch or 0, value.Yaw or 0, value.Roll or 0 end
	return value[1] or 0, value[2] or 0, value[3] or 0
end

local function getFlashlightOffsets(location)
	local ids = flashlightOffsetIds[location] or flashlightOffsetIds[FlashlightLocation.Head]
	local px, py, pz = vec3FromConfig(configui.getValue(ids.position))
	local rx, ry, rz = vec3FromConfig(configui.getValue(ids.rotation))
	return px, py, pz, rx, ry, rz
end

local function applyFlashlightOffsets(state, location)
	if state == nil then return end
	local px, py, pz, rx, ry, rz = getFlashlightOffsets(location)
	state:set_location_offset(Vector3f.new(px, py, pz))
	state:set_rotation_offset(Vector3f.new(math.rad(rx), math.rad(ry), math.rad(rz)))
end

function M.updateFlashlightOffsetVisibility(location)
	location = location or configui.getValue("flashlight_location") or FlashlightLocation.Head
	for loc, ids in pairs(flashlightOffsetIds) do
		local hidden = loc ~= location
		configui.setHidden(ids.position, hidden)
		configui.setHidden(ids.rotation, hidden)
	end
end

function M.attachFlashlightToController(force)
	local pawn = uevrUtils.get_local_pawn()
	if pawn == nil then return end

	local light = pawn.ScopedSpotlight or pawn.ScopedSpotlightComponent
	if uevrUtils.getValid(light) == nil then return end

	local location = configui.getValue("flashlight_location") or FlashlightLocation.Head
	local hand = flashlightHandFromLocation(location)
	if not force and flashlightStatus.light == light and flashlightStatus.state ~= nil and flashlightStatus.hand == hand then
		applyFlashlightOffsets(flashlightStatus.state, location)
		return
	end

	local springArm = pawn.SpringArm1 or pawn.SpringArmComponentForTorch
	if uevrUtils.getValid(springArm) ~= nil then
		pcall(function() springArm.bUsePawnControlRotation = false end)
	end

	if flashlightStatus.light ~= nil then
		pcall(function() UEVR_UObjectHook.remove_motion_controller_state(flashlightStatus.light) end)
	end

	pcall(function()
		light:DetachFromParent(false, false)
	end)
	uevrUtils.set_component_relative_rotation(light, {Pitch = 0, Yaw = 0, Roll = 0})
	uevrUtils.set_component_relative_location(light, {X = 0, Y = 0, Z = 0})

	local state = UEVR_UObjectHook.get_or_add_motion_controller_state(light)
	if state == nil then return end
	state:set_hand(hand)
	state:set_permanent(true)
	applyFlashlightOffsets(state, location)

	flashlightStatus.light = light
	flashlightStatus.state = state
	flashlightStatus.hand = hand
end

function M.reset()
	flashlightStatus = {}
end

configui.onCreateOrUpdate("flashlight_location", function(value)
	M.updateFlashlightOffsetVisibility(value)
	M.attachFlashlightToController(true)
end)

for _, ids in pairs(flashlightOffsetIds) do
	configui.onCreateOrUpdate(ids.position, function()
		M.attachFlashlightToController(false)
	end)
	configui.onCreateOrUpdate(ids.rotation, function()
		M.attachFlashlightToController(false)
	end)
end
--------------------- End flashlight --------------------------------

return M

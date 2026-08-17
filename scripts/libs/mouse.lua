local uevrUtils = require('libs/uevr_utils')
local controllers = require('libs/controllers')
local mathLib = require('libs/core/math_lib')


local M = {}

local status = {}
local function getViewportSize()
---@diagnostic disable-next-line: undefined-field
    return GameUserSettings.ResolutionSizeX or 0, GameUserSettings.ResolutionSizeY or 0
end

local function projectWorldToScreen(worldLocation)
    -- TODO try these instead
    -- vr.get_ui_width()
    -- vr.get_ui_height()
    local viewportWidth , viewportHeight = getViewportSize()
    if viewportWidth == 0 or viewportHeight == 0 then return false, 0, 0 end

    local camLocation = status.worldPosition or controllers.getControllerLocation(2)
    local camRotation = status.worldRotation or controllers.getControllerRotation(2)
    local camFOV = 45 --seems to work best

    -- print("Camera Location:", camLocation.X, camLocation.Y, camLocation.Z)
    -- print("Camera Rotation:", camRotation.Pitch, camRotation.Yaw, camRotation.Roll)
    -- print("World Location:", worldLocation.X, worldLocation.Y, worldLocation.Z)

    local delta = worldLocation - camLocation
    local forward = mathLib.getForwardVector(camRotation, true)
    local right = mathLib.vectorRotate({ X = 0, Y = 1, Z = 0 }, camRotation, true)
    local up = mathLib.vectorRotate({ X = 0, Y = 0, Z = 1 }, camRotation, true)

    local finalX = mathLib.vectorDot(delta, forward, true)
    local finalY = mathLib.vectorDot(delta, right, true)
    local finalZ = mathLib.vectorDot(delta, up, true)

    -- 5. Fail if object is behind the camera plane 
    if finalX <= 0 then
        return false, 0, 0
    end

    -- 6. Manually construct Normalized Device Coordinates (NDC)
    local aspectRatio = viewportWidth / viewportHeight
    local halfFOV = math.rad(camFOV / 2)
    local tanHalfFOV = math.tan(halfFOV)

    local screenX = finalY / (finalX * tanHalfFOV * aspectRatio)
    local screenY = finalZ / (finalX * tanHalfFOV)

    -- 7. Map from NDC (-1 to 1) directly to absolute viewport pixels
    --print("Normalized Device Coordinates:", screenX, screenY)
    local pixelX = (screenX + 1.0) * 0.5 * viewportWidth
    local pixelY = (1.0 - screenY) * 0.5 * viewportHeight

    return true, pixelX, pixelY
end

function M.setWorldRotation(rotator)
    --print("Setting world rotation:", rotator.Pitch, rotator.Yaw, rotator.Roll)
    status.worldRotation = rotator
end
function M.setWorldPosition(position)
    --print("Setting world position:", position.X, position.Y, position.Z)
    status.worldPosition = position
end

function M.updateMousePosition()
	local playerController = uevr.api:get_player_controller(0)
	if playerController ~= nil then
        local controllerDir = controllers.getControllerDirection(Handed.Right)
        local controllerLoc = controllers.getControllerLocation(Handed.Right)
        controllerLoc = controllerLoc + controllerDir * 300 --project a point in front of the controller
        local result, x, y = projectWorldToScreen(controllerLoc)
        --print("Projected mouse position:", x, y, "Valid:", result)
        if result then
            playerController:SetMouseLocation(x, y)
        end
    end
end

function M.enable(state)
    status.enabled = state
    if state == true then
        M.initCameraPosition()
    end
end

function M.initCameraPosition()
    M.setWorldRotation(controllers.getControllerRotation(2))
    M.setWorldPosition(controllers.getControllerLocation(2))
 end

uevr.sdk.callbacks.on_pre_engine_tick(function(engine, delta)
    if status.enabled == true then
        M.updateMousePosition()
    end
end)

-- if the position of the camera changes significantly then re-initialize
setInterval(1000, function()
    if status.enabled == true then
        local pos = controllers.getControllerLocation(2)
        if mathLib.vectorDistanceSquared(pos, status.worldPosition, false) > 5000 then
            M.initCameraPosition()
        end
    end
end)

return M
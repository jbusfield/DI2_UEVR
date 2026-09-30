local uevrUtils = require('libs/uevr_utils')
local controllers = require('libs/controllers')
local mathLib = require('libs/core/math_lib')


local M = {}

local status = {}
local overrideEnable = true
function M.setOverrideEnable(state)
    overrideEnable = state
end

local function getViewportSize()
    local w = uevr.params.vr.get_ui_width()
    local h = uevr.params.vr.get_ui_height()
    if w ~= 0 and h ~= 0 then return w, h end

    if WidgetLayoutLibrary ~= nil then
        local size = WidgetLayoutLibrary:GetViewportSize(uevrUtils.get_world())
        if size ~= nil and size.X ~= 0 and size.Y ~= 0 then
            return size.X, size.Y
        end
    end
    local settings = (game_engine and game_engine.GameUserSettings) or GameUserSettings
    w = (settings and settings.ResolutionSizeX) or 0
    h = (settings and settings.ResolutionSizeY) or 0
    return w, h
end

local function projectWorldToScreen(worldLocation)
    local viewportWidth , viewportHeight = getViewportSize()
    if viewportWidth == 0 or viewportHeight == 0 then return false, 0, 0 end

    local camLocation = status.worldPosition or controllers.getControllerLocation(2)
    local camRotation = status.worldRotation or controllers.getControllerRotation(2)
    local camFOV = 45 --seems to work best

    local delta = worldLocation - camLocation
    local forward = mathLib.getForwardVector(camRotation, true)
    local right = mathLib.vectorRotate({ X = 0, Y = 1, Z = 0 }, camRotation, true)
    local up = mathLib.vectorRotate({ X = 0, Y = 0, Z = 1 }, camRotation, true)

    local finalX = mathLib.vectorDot(delta, forward, true)
    local finalY = mathLib.vectorDot(delta, right, true)
    local finalZ = mathLib.vectorDot(delta, up, true)

    if finalX <= 0 then
        return false, 0, 0
    end

    local aspectRatio = viewportWidth / viewportHeight
    local halfFOV = math.rad(camFOV / 2)
    local tanHalfFOV = math.tan(halfFOV)

    local screenX = finalY / (finalX * tanHalfFOV * aspectRatio)
    local screenY = finalZ / (finalX * tanHalfFOV)

    local pixelX = (screenX + 1.0) * 0.5 * viewportWidth
    local pixelY = (1.0 - screenY) * 0.5 * viewportHeight

    return true, pixelX, pixelY
end

function M.setWorldRotation(rotator)
    status.worldRotation = rotator
end
function M.setWorldPosition(position)
    status.worldPosition = position
end

function M.updateMousePosition()
	local playerController = uevr.api:get_player_controller(0)
	if playerController ~= nil then
        local controllerDir = controllers.getControllerDirection(Handed.Right)
        local controllerLoc = controllers.getControllerLocation(Handed.Right)
        controllerLoc = controllerLoc + controllerDir * 300
        local result, x, y = projectWorldToScreen(controllerLoc)
        if result then
            playerController:SetMouseLocation(x, y)
        end
    end
end

function M.enable(state)
    status.enabled = state
    status.lastShowCursor = nil
    if state == true then
        M.initCameraPosition()
    end
end

function M.initCameraPosition()
    local hmdLoc = controllers.getControllerLocation(2)
    local hmdRot = controllers.getControllerRotation(2)
    if hmdLoc == nil or hmdRot == nil then return end
    if math.abs(hmdLoc.X) + math.abs(hmdLoc.Y) + math.abs(hmdLoc.Z) < 1.0 then return end
    M.setWorldRotation(hmdRot)
    M.setWorldPosition(hmdLoc)
end

uevr.sdk.callbacks.on_pre_engine_tick(function(engine, delta)
    if overrideEnable == false then return end

    local uiEnabled = uevrUtils.executeUEVRCallbacksWithPriorityResult("is_controller_mouse_enabled")
    local active = uiEnabled == nil and status.enabled == true or uiEnabled == true
    if active and not status.active then
        M.initCameraPosition()
    end
    status.active = active
    if active then
        -- Mount UI enables before the HMD yaw settles; re-anchor when the cursor appears.
        local pc = uevr.api:get_player_controller(0)
        local show = pc ~= nil and pc.bShowMouseCursor == true
        if status.lastShowCursor == false and show then
            M.initCameraPosition()
        end
        status.lastShowCursor = show

        M.updateMousePosition()
    end
end)

setInterval(1000, function()
    if overrideEnable == false then return end

    if status.active then
        local pos = controllers.getControllerLocation(2)
        if pos ~= nil and status.worldPosition ~= nil and mathLib.vectorDistanceSquared(pos, status.worldPosition, false) > 5000 then
            M.initCameraPosition()
        end
    end
end)

return M

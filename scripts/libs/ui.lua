--[[ 
Usage
    Drop the lib folder containing this file into your project folder

     Add code like this in your script:
        local ui = require("libs/ui")
        local isDeveloperMode = true  
        ui.init(isDeveloperMode)

    This module provides functions to manage UI settings such as head-locked UI, viewport widget states, and motion sickness reduction.

    Available functions:

    ui.ShapeEnum - head-locked UI shape values (Flat = 1, Cylinder = 2)

    ui.init(isDeveloperMode, logLevel) - initializes the UI system
        example:
            ui.init(true, LogLevel.Debug)

    ui.setLogLevel(val) - sets the logging level for UI system messages
        example:
            ui.setLogLevel(LogLevel.Debug)

    ui.print(text, (optional)logLevel) - prints a message at the given (or Debug) log level
        example:
            ui.print("UI updated", LogLevel.Debug)

    ui.setIsHeadLocked(value) - enables/disables head-locked UI mode
        example:
            ui.setIsHeadLocked(true)

    ui.setHeadLockedUIPosition(value) - sets the position of head-locked UI
        example:
            ui.setHeadLockedUIPosition({X=0, Y=0, Z=2.0})

    ui.setHeadLockedUISize(value) - sets the size of head-locked UI
        example:
            ui.setHeadLockedUISize(2.0)

    ui.setHeadLockedUIShape(value) - sets the shape of head-locked UI (ui.ShapeEnum.Flat or ui.ShapeEnum.Cylinder)
        example:
            ui.setHeadLockedUIShape(ui.ShapeEnum.Cylinder)

    ui.setHeadLockedUIOptions(newOptions) - passes head-locked UI option overrides to the config UI
        example:
            ui.setHeadLockedUIOptions({ showShape = true })

    ui.disableHeadLockedUI(value) - temporarily disables head-locked UI without changing its state
        example:
            ui.disableHeadLockedUI(true)

    ui.isViewLocked() - returns true if UI view is currently forced locked (vs free-follow head-locked mode)
        example:
            if ui.isViewLocked() then return end

    ui.setIsInMotionSicknessCausingScene(value) - sets whether current scene may cause motion sickness
        example:
            ui.setIsInMotionSicknessCausingScene(true)

    ui.setRequireWidgetOpenState(value) - sets whether to require widget's GetOpenState() to consider it active
        In some games widgets will act like they are active even though they are not actually open
        Set this to true to require that the widget's GetOpenState() returns 0 (open) for it to be considered active
        example:
            ui.setRequireWidgetOpenState(true)

    ui.setRequireWidgetVisibility(value) - sets whether to require widget visibility to consider it active
        When true, only widgets with GetVisibility() of 0, 3, or 4 are treated as active
        example:
            ui.setRequireWidgetVisibility(true)

    ui.registerIsInMotionSicknessCausingSceneCallback(func) - registers a callback for motion sickness scene changes
        Second param  is an optional priority. Higher priority callbacks override lower priority ones.
        If the second param is not provided it defaults to 0.
        example:
            ui.registerIsInMotionSicknessCausingSceneCallback(function()
                return isInMotionSicknessCausingScene, 0
            end)

    ui.getConfigurationWidgets(options) - gets configuration UI widgets
        example:
            local widgets = ui.getConfigurationWidgets()

    ui.showConfiguration(saveFileName, options) - shows basic configuration UI
        example:
            ui.showConfiguration("ui_config")

    ui.addViewportWidget(widget) - registers a custom widget so UI state treats it like a viewport widget
        In developer mode also lists it in the UI config tool
        example:
            ui.addViewportWidget(myWidget)

    ui.removeViewportWidget(widget) - unregisters a previously added custom viewport widget
        example:
            ui.removeViewportWidget(myWidget)

    ui.registerWidgetChangeCallback(widgetName, func) - registers a callback for when specific high level 
        viewport widgets become active/inactive. The widgetName can be found in the UI interface list
        example:
            ui.registerWidgetChangeCallback("WBP_UniversalLockTooltipWidget_C", function(active)
                print("Widget changed:", active)
            end)

    ui.onUpdate(stateKey, func) - registers a callback invoked when a UI state value changes.
        Callback receives (value, priority). value may be true, false, or nil (default/cleared).
        Valid stateKey values: viewLocked, screen2D, decouplePitch, autoAdjustUI, inputEnabled,
        handsEnabled, remapEnabled, fadeCamera, pawnArmBones
        example:
            ui.onUpdate("remapEnabled", function(value)
                print("remapEnabled changed:", value)
            end)

    ui.setCustomState(stateKey, value, priority) -- allow you to force a specific state value, overriding normal behavior
	    Use nil to reset the state to its default behavior.
        example:
            ui.setCustomState("handsEnabled", false, 2)
            ui.setCustomState("handsEnabled", nil)

    ui.isInputDisabled() - returns true if UI state currently disables input
        example:
            if ui.isInputDisabled() then return end

    ui.isInputDisabledWithPriority() - returns disabled state (or nil) and priority for input callbacks
        example:
            local disabled, priority = ui.isInputDisabledWithPriority()

    ui.isRemapDisabled() - returns true if UI state currently disables remapping
        example:
            if ui.isRemapDisabled() then return end

    ui.isRemapDisabledWithPriority() - returns disabled state (or nil) and priority for remap callbacks
        example:
            local disabled, priority = ui.isRemapDisabledWithPriority()

    ui.isArmBonesHidden() - returns true if UI state currently hides pawn arm bones
        example:
            if ui.isArmBonesHidden() then return end

    ui.isArmBonesHiddenWithPriority() - returns hidden state (or nil) and priority for arm-bone callbacks
        example:
            local hidden, priority = ui.isArmBonesHiddenWithPriority()

    ui.isFadeCameraEnabled() - returns true if UI state currently enables camera fade
        example:
            if ui.isFadeCameraEnabled() then return end

    ui.isFadeCameraEnabledWithPriority() - returns enabled state (or nil) and priority for fade-camera callbacks
        example:
            local enabled, priority = ui.isFadeCameraEnabledWithPriority()

    ui.forceUpdate() - immediately recalculates UI state and applies view/UI settings
        example:
            ui.forceUpdate()

]]--

local uevrUtils = require("libs/uevr_utils")
local paramModule = require("libs/core/params")

local M = {}

M.ShapeEnum = {
	Flat = 1,
	Cylinder = 2
}
local uiConfigDev = nil
local uiConfig = nil

local headLockedUI = false
local headLockedUISize = 2.0
local headLockedUIPosition = {X=0, Y=0, Z=2.0}
local headLockedUIShape = M.ShapeEnum.Flat

local isFollowing = true
local reduceMotionSickness = false
local isInMotionSicknessCausingScene = false

local currentWidgetViewportState = {}
local currentCustomViewportWidgets = {}

--In some games widgets will act like they are active even though they are not actually open
--Set this to true to require that the widget's GetOpenState() returns 0 (open) for it to be considered active
local requireWidgetOpenState = false
local requireWidgetVisibility = false

local uiState = {viewLocked = nil, screen2D = nil, decouplePitch = nil, inputEnabled = nil, handsEnabled = nil}

local stateConfigWidget = {
    {stateKey = "viewLocked", valueKey = "lockedUIWhenActive"},
    {stateKey = "screen2D", valueKey = "screen2DWhenActive"},
    {stateKey = "decouplePitch", valueKey = "decouplePitchWhenActive"},
    {stateKey = "autoAdjustUI", valueKey = "autoAdjustUIWhenActive"},
    {stateKey = "inputEnabled", valueKey = "inputWhenActive"},
    {stateKey = "handsEnabled", valueKey = "handsWhenActive"},
    {stateKey = "remapEnabled", valueKey = "remapWhenActive"},
    {stateKey = "fadeCamera", valueKey = "fadeCameraWhenActive"},
    {stateKey = "pawnArmBones", valueKey = "pawnArmBonesWhenActive"}
}

local stateConfigGame = {
    {stateKey = "viewLocked", valueKey = "lockedUIWhenInGameState"},
    {stateKey = "screen2D", valueKey = "screen2DWhenInGameState"},
    {stateKey = "decouplePitch", valueKey = "decouplePitchWhenInGameState"},
    {stateKey = "autoAdjustUI", valueKey = "autoAdjustUIWhenInGameState"},
    {stateKey = "inputEnabled", valueKey = "inputWhenInGameState"},
    {stateKey = "handsEnabled", valueKey = "handsWhenInGameState"},
    {stateKey = "remapEnabled", valueKey = "remapWhenInGameState"},
    {stateKey = "fadeCamera", valueKey = "fadeCameraWhenInGameState"},
    {stateKey = "pawnArmBones", valueKey = "pawnArmBonesWhenInGameState"}
}

local gameStates = {"cutscene", "paused", "character_hidden"}

local parametersFileName = "ui_parameters"
local parameters = {}

local currentLogLevel = LogLevel.Error
function M.setLogLevel(val)
	currentLogLevel = val
end
function M.print(text, logLevel)
	if logLevel == nil then logLevel = LogLevel.Debug end
	if logLevel <= currentLogLevel then
		uevrUtils.print("[ui] " .. text, logLevel)
	end
end

--start with lerping disabled in case it was left on accidentally
uevrUtils.enableCameraLerp(false, true, true, true)
--start with snap turn disabled in case it was left on accidentally
uevrUtils.enableSnapTurn(false)

local paramManager = paramModule.new(parametersFileName, parameters, true)

local function saveParameter(key, value, persist)
	paramManager:set(key, value, persist)
	if uiConfigDev ~= nil then
		uiConfigDev.updateParameters(paramManager:getAll())
	end
end

local function getParameter(key)
    return paramManager:get(key)
end


local function updateUI(force)
    if force or uiState["viewLocked_last"] ~= uiState["viewLocked"] then
        local isLocked = false
        if uiState["viewLocked"] == nil then
            isLocked = headLockedUI
        else
            isLocked = not uiState["viewLocked"]
            if not isLocked then
                --if we're in a state where the view is locked, recenter the view so that we're facing the locked UI
                uevrUtils.executeUEVRCallbacks("recenter_view")
                --input.resetView()
            end
        end
        uevrUtils.enableUIFollowsView(isLocked)
        if isLocked then
            uevrUtils.setUIFollowsViewOffset(headLockedUIPosition)
            uevrUtils.setUIFollowsViewSize(headLockedUISize)
            uevrUtils.setUIShape(headLockedUIShape - 1)
        elseif headLockedUI then
            uevrUtils.setUIFollowsViewOffset({X=0, Y=0, Z=2.0})
            uevrUtils.setUIFollowsViewSize(2.0)
            uevrUtils.setUIShape(0)
        end
        uiState["viewLocked_last"] = uiState["viewLocked"]
        --M.print("Setting 2D mode to " .. tostring(viewportWidgetState["screen2D"]))
    end


    if uiState["screen2D_last"] ~= uiState["screen2D"] then
        if uiState["screen2D_last"] == nil then
            uiState["screen2D_cache"] = uevrUtils.get_2D_mode()
        end
        if uiState["screen2D"] == nil then
            uevrUtils.set_2D_mode(uiState["screen2D_cache"])
        else
            uevrUtils.set_2D_mode(uiState["screen2D"])
        end
        uiState["screen2D_last"] = uiState["screen2D"]
        --M.print("Setting 2D mode to " .. tostring(viewportWidgetState["screen2D"]))
    end

    if uiState["fadeCamera_last"] ~= uiState["fadeCamera"] then
        if uiState["fadeCamera"] == true then
            uevrUtils.fadeCamera(0.1, true)
        else
            uevrUtils.stopFadeCamera()
        end
        uiState["fadeCamera_last"] = uiState["fadeCamera"]
    end

    if uiState["decouplePitch_last"] ~= uiState["decouplePitch"] then
        if uiState["decouplePitch_last"] == nil then
            uiState["decouplePitch_cache"] = uevrUtils.get_decoupled_pitch()
        end
        if uiState["decouplePitch"] == nil then
            uevrUtils.set_decoupled_pitch(uiState["decouplePitch_cache"])
        else
            uevrUtils.set_decoupled_pitch(uiState["decouplePitch"])
        end
        uiState["decouplePitch_last"] = uiState["decouplePitch"]
    end

    if uiState["autoAdjustUI_last"] ~= uiState["autoAdjustUI"] then
        if uiState["autoAdjustUI_last"] == nil then
            uiState["autoAdjustUI_cache"] = uevrUtils.get_decoupled_pitch_adjust_ui()
        end
        -- if uiState["autoAdjustUI"] == nil then
        --     uevrUtils.set_decoupled_pitch_adjust_ui(uiState["autoAdjustUI_cache"])
        -- end
        if uiState["autoAdjustUI"] == nil then
            uevrUtils.set_decoupled_pitch_adjust_ui(uiState["autoAdjustUI_cache"])
        else
            uevrUtils.set_decoupled_pitch_adjust_ui(uiState["autoAdjustUI"])
        end
        uiState["autoAdjustUI_last"] = uiState["autoAdjustUI"]
    end
end

function M.isViewLocked()
    return uiState["viewLocked"] ~= nil and (uiState["viewLocked"]) or false
end

-- input.registerIsDisabledCallback(function()
-- 	return uiState["inputEnabled"] ~= nil and (not uiState["inputEnabled"]) or nil, uiState["inputEnabledPriority"]
-- end)

-- TODO this probable needs to use ternary operator like isArmBonesHiddenWithPriority
function M.isRemapDisabledWithPriority()
    return uiState["remapEnabled"] ~= nil and (not uiState["remapEnabled"]) or nil, uiState["remapEnabledPriority"]
end
function M.isRemapDisabled()
    return uiState["remapEnabled"] ~= nil and (not uiState["remapEnabled"]) or false
end

function M.isArmBonesHiddenWithPriority()
    return uevrUtils.ternary(uiState["pawnArmBones"] ~= nil, (not uiState["pawnArmBones"]), nil), uiState["pawnArmBonesPriority"]
end
function M.isArmBonesHidden()
    return uiState["pawnArmBones"] ~= nil and (not uiState["pawnArmBones"]) or false
end


function M.isFadeCameraEnabledWithPriority()
    return uiState["fadeCamera"] ~= nil and uiState["fadeCamera"] or nil, uiState["fadeCameraPriority"]
end
function M.isFadeCameraEnabled()
    return uiState["fadeCamera"] ~= nil and uiState["fadeCamera"] or false
end

function M.isInputDisabledWithPriority()
    return uiState["inputEnabled"] ~= nil and (not uiState["inputEnabled"]) or nil, uiState["inputEnabledPriority"]
end

function M.isInputDisabled()
    return uiState["inputEnabled"] ~= nil and (not uiState["inputEnabled"]) or false
end

uevrUtils.registerUEVRCallback("is_input_disabled", function()
	--return uiState["inputEnabled"] ~= nil and (not uiState["inputEnabled"]) or nil, uiState["inputEnabledPriority"]
    return M.isInputDisabledWithPriority()
end)

uevrUtils.registerUEVRCallback("is_remap_disabled", function()
    return M.isRemapDisabledWithPriority()
	--return uiState["remapEnabled"] ~= nil and (not uiState["remapEnabled"]) or nil, uiState["remapEnabledPriority"]
end)

uevrUtils.registerUEVRCallback("is_arms_bones_hidden", function()
    return M.isArmBonesHiddenWithPriority()
end)

uevrUtils.registerUEVRCallback("is_fade_camera_enabled", function()
    return M.isFadeCameraEnabledWithPriority()
end)

uevrUtils.registerUEVRCallback("is_hands_hidden", function()
	return uiState["handsEnabled"] ~= nil and (not uiState["handsEnabled"]) or nil, uiState["handsEnabledPriority"]
end)

local customUIState = {}
function M.setCustomState(stateKey, value, priority)
    if stateKey ~= nil then
        if value ~= nil then
            customUIState[stateKey] = {value = value, priority = priority or 0}
        else
            customUIState[stateKey] = nil
        end
    end
end

local function updateStateIfHigherPriority(data, stateKey, valueKey)
    local priority = tonumber(data[valueKey .. "Priority"]) or 0
    if priority >= uiState[stateKey .. "Priority"] then
        if data[valueKey] == 2 then
            uiState[stateKey] = true
            uiState[stateKey .. "Priority"] = priority
        elseif data[valueKey] == 3 then
            uiState[stateKey] = false
            uiState[stateKey .. "Priority"] = priority
        end
    end
end

local newWidgetViewportState = {}
local function updateWidgetChangeCallbacks()
    for id, isInViewport in pairs(newWidgetViewportState) do
        if currentWidgetViewportState[id] ~= isInViewport then
            currentWidgetViewportState[id] = isInViewport
            M.print("Widget " .. id .. " change, isInViewport = " .. tostring(isInViewport))
            uevrUtils.executeUEVRCallbacks("widget_change_" .. id, isInViewport)
        end
    end
    for id, isInViewport in pairs(currentWidgetViewportState) do
       newWidgetViewportState[id] = false
    end
end

local function setCurrentViewportWidgetsStr(str)
	if uiConfigDev ~= nil then
		uiConfigDev.setCurrentViewportWidgetsStr(str)
	end
end

local function setCurrentGameStateText(str)
	if uiConfigDev ~= nil then
		uiConfigDev.setCurrentGameStateText(str)
	end
end

local function updateUIState()
    local currentUIState = {}
    for _, config in ipairs(stateConfigWidget) do
        currentUIState[config.stateKey] = uiState[config.stateKey]
        currentUIState[config.stateKey .. "Priority"] = uiState[config.stateKey .. "Priority"]
        uiState[config.stateKey] = nil
        uiState[config.stateKey .. "Priority"] = 0
    end

    local currentViewportWidgetsStr = ""
    local widgetList = getParameter("widgetlist")
    if widgetList ~= nil then

        local foundWidgets = {}
        local widgetClass = uevrUtils.get_class("Class /Script/UMG.UserWidget")
        ---@diagnostic disable-next-line: undefined-field
        WidgetBlueprintLibrary:GetAllWidgetsOfClass(uevrUtils.get_world(), foundWidgets, widgetClass, true)
        --print("Found widgets: " .. #foundWidgets)

        --append currentCustomViewportWidgets to foundWidgets
        for _, widget in ipairs(currentCustomViewportWidgets) do
            if uevrUtils.getValid(widget) ~= nil then
                table.insert(foundWidgets, widget)
            else
                M.removeViewportWidget(widget)
            end
        end

        for index, widget in pairs(foundWidgets) do
            --if widget:IsInViewport() then --check not really needed since GetAllWidgetsOfClass with the last param true should only return viewport widgets.also currentCustomViewportWidgets might not be in viewport
            if requireWidgetOpenState == false or (widget.GetOpenState ~= nil and widget:GetOpenState() == 0) then
                if requireWidgetVisibility == false or widget:GetVisibility() == 0 or widget:GetVisibility() == 3 or widget:GetVisibility() == 4 then -- (widget.IsVisible ~= nil and widget:IsVisible()) then
                    --get the widget data from the configurations
                    local id = widget:get_class():get_full_name()
                    --print(id, widget:IsInteractable(), widget:IsVisible(), widget:HasUserFocus(), widget:GetVisibility(), widget:GetIsEnabled(), widget:GetIsVisible(), widget.GetOpenState and widget:GetOpenState() or "")
                    local data = widgetList[id]
                    if data ~= nil then
                        if data["label"] ~= nil then
                            currentViewportWidgetsStr = currentViewportWidgetsStr .. data["label"] .. "\n"
                        end
                        for _, config in ipairs(stateConfigWidget) do
                            updateStateIfHigherPriority(data, config.stateKey, config.valueKey)
                        end
                        newWidgetViewportState[data["label"]] = true
                        uevrUtils.setWidgetLayout(widget, data["scale"], data["alignment"])
                        --updateCurrentWidgetChangeCallbackState(data["label"], true)
                    end
                end
            end
            -- else
            --     print ("Widget " .. id .. " not in viewport")
            --end
        end
        updateWidgetChangeCallbacks()
    end
    setCurrentViewportWidgetsStr(currentViewportWidgetsStr)

    local currentGameStateText = "Current Game State: "
    local isInCutscene = uevrUtils.isInCutscene()
    local isPaused = uevrUtils.isGamePaused()
    local isCharacterHidden = uevrUtils.isCharacterHidden() --or uevrUtils.getValid(pawn,{ "Controller", "Character", "bHidden"}) or false
    currentGameStateText = currentGameStateText .. "Is In Cutscene = " .. tostring(isInCutscene) .. ", Is Paused = " .. tostring(isPaused) .. ", Is Character Hidden = " .. tostring(isCharacterHidden)
    for index, gameStateName in ipairs(gameStates) do
        local isActive = (gameStateName == "cutscene" and isInCutscene) or (gameStateName == "paused" and isPaused) or (gameStateName == "character_hidden" and isCharacterHidden)
        local gameState = getParameter(gameStateName)
        if gameState ~= nil and isActive then
            --print("Updating game state", gameStateName)
            for _, config in ipairs(stateConfigGame) do
                updateStateIfHigherPriority(gameState, config.stateKey, config.valueKey)
            end
        end
    end

    for stateKey, data in pairs(customUIState) do
        if data.value ~= nil then
            if data.priority >= uiState[stateKey .. "Priority"] then
                uiState[stateKey] = data.value
                uiState[stateKey .. "Priority"] = data.priority or 0
            end
        end
    end

    -- let any listeners know about state changes
    -- use like this
    -- ui.onUpdate("remapEnabled", function(state, priority)
    --     print("Remap enabled changed to " .. tostring(state) .. " with priority " .. tostring(priority))
    -- end)
    for _, config in ipairs(stateConfigWidget) do
        if currentUIState[config.stateKey] ~= uiState[config.stateKey] then
            --print("UI State " .. config.stateKey .. " changed to " .. tostring(uiState[config.stateKey]) .. " with priority " .. tostring(uiState[config.stateKey .. "Priority"]))
            uevrUtils.executeUEVRCallbacksWithPriorityResult("ui_state_change_" .. config.stateKey, uiState[config.stateKey], uiState[config.stateKey .. "Priority"])
        end
    end

    setCurrentGameStateText(currentGameStateText)
end
updateUIState = uevrUtils.profiler:wrap("UI: updateUIState", updateUIState)

local enableCutsceneDetection = doOnce(function()
    uevrUtils.registerCutsceneChangeCallback(function(inCutscene)
        M.forceUpdate()
    end)
end, Once.EVER)

local enablePauseDetection = doOnce(function()
    uevrUtils.registerGamePausedCallback(function(isPaused)
        M.forceUpdate()
    end)
end, Once.EVER)

local enableCharacterHiddenDetection = doOnce(function()
    uevrUtils.registerCharacterHiddenCallback(function(isHidden)
        M.forceUpdate()
    end)
end, Once.EVER)

local function createGameStateMonitor()
    for index, gameStateName in ipairs(gameStates) do
        local gameState = getParameter(gameStateName)
        if gameState ~= nil then
            for _, config in ipairs(stateConfigGame) do
                if gameState[config.valueKey] == 2 or gameState[config.valueKey] == 3 then
                    if gameStateName == "cutscene" then
                        enableCutsceneDetection()
                        M.print("Enabled cutscene detection")
                    end
                    if gameStateName == "paused" then
                        enablePauseDetection()
                        M.print("Enabled pause detection")
                    end
                    if gameStateName == "character_hidden" then
                        enableCharacterHiddenDetection()
                        M.print("Enabled character hidden detection")
                    end
                    break
                end
            end
        end
    end
end

function M.init(isDeveloperMode, logLevel)
    paramManager:load()

    if logLevel ~= nil then
        M.setLogLevel(logLevel)
    end
    if isDeveloperMode == nil and uevrUtils.getDeveloperMode() ~= nil then
        isDeveloperMode = uevrUtils.getDeveloperMode()
    end

    if isDeveloperMode then
       uiConfigDev = require("libs/config/ui_config_dev")
        uiConfigDev.init(paramManager:getAll())
		uiConfigDev.registerParameterChangedCallback(function(key, value)
			saveParameter(key, value, true)
		end)
    end

    local cutsceneOptions = getParameter("cutscene_options")
    if cutsceneOptions ~= nil then
        uevrUtils.setCutsceneDetectionOptions(cutsceneOptions)
    end

    enableCutsceneDetection()
    enablePauseDetection()
    enableCharacterHiddenDetection()

    --createGameStateMonitor()
end

local createConfigMonitor = doOnce(function()
	if uiConfig ~= nil then
		uiConfig.registerParametersChangedCallback(function(paramName, paramValue)
			if paramName == "headLockedUI" then
				M.setIsHeadLocked(paramValue)
			elseif paramName == "headLockedUIPosition" then
				M.setHeadLockedUIPosition(paramValue)
			elseif paramName == "headLockedUISize" then
				M.setHeadLockedUISize(paramValue)
			elseif paramName == "headLockedUIShape" then
				M.setHeadLockedUIShape(paramValue)
			elseif paramName == "reduceMotionSickness" then
                if reduceMotionSickness then
                    uevrUtils.enableCameraLerp(paramValue, true, true, true)
                else
                    uevrUtils.enableCameraLerp(paramValue and isInMotionSicknessCausingScene, true, true, true)
                end
				reduceMotionSickness = paramValue
			end
		end)
	end
end, Once.EVER)

function M.addViewportWidget(widget)
    if uiConfigDev ~= nil then
        uiConfigDev.registerViewportWidget(widget:get_class():get_full_name(), uevrUtils.getShortName(widget:get_class()))
    end
    --add uniquely to currentCustomViewportWidgets array
    local index = uevrUtils.indexOf(currentCustomViewportWidgets, widget)
    if index == nil then
        table.insert(currentCustomViewportWidgets, widget)
    end
end

function M.removeViewportWidget(widget)
    --remove from currentCustomViewportWidgets array
    local index = uevrUtils.indexOf(currentCustomViewportWidgets, widget)
    if index ~= nil then
        table.remove(currentCustomViewportWidgets, index)
    end
end

function M.getConfigurationWidgets(options)
	if uiConfig == nil then
		uiConfig = require("libs/config/ui_config")
	end
	createConfigMonitor()
    return uiConfig.getConfigurationWidgets(options)
end

function M.setHeadLockedUIOptions(newOptions)
    if uiConfig ~= nil then
	    uiConfig.setHeadLockedUIOptions(newOptions)
    end
end

function M.showConfiguration(saveFileName, options)
	if uiConfig == nil then
		uiConfig = require("libs/config/ui_config")
	end
	createConfigMonitor()
	uiConfig.showConfiguration(saveFileName, options)
end

function M.disableHeadLockedUI(value)
    if not value ~= isFollowing then
        isFollowing = not value
        updateUI(true)
    end
end

function M.setIsHeadLocked(value)
    if uiConfig ~= nil then uiConfig.setValue("headLockedUI", value, true) end
    headLockedUI = value
    if uevrUtils.isGamePaused() then
        M.disableHeadLockedUI(true)
    end
    updateUI(true)
end

function M.setHeadLockedUIPosition(value)
    M.print("Setting UI Position to " .. value.X .. ", " .. value.Y .. ", " .. value.Z)
    if uiConfig ~= nil then uiConfig.setValue("headLockedUIPosition", value, true) end
    headLockedUIPosition = value
    updateUI(true)
end
function M.setHeadLockedUISize(value)
    M.print("Setting UI Size to " .. tostring(value))
    if uiConfig ~= nil then uiConfig.setValue("headLockedUISize", value, true) end
    headLockedUISize = value
    updateUI(true)
end
function M.setHeadLockedUIShape(value)
    M.print("Setting UI Shape to " .. tostring(value))
    if uiConfig ~= nil then uiConfig.setValue("headLockedUIShape", value, true) end
    headLockedUIShape = value
    updateUI(true)
end

function M.setIsInMotionSicknessCausingScene(value)
    isInMotionSicknessCausingScene = value
    if reduceMotionSickness then
        uevrUtils.enableCameraLerp(isInMotionSicknessCausingScene, true, true, true)
    end
end

function M.setRequireWidgetOpenState(value)
    requireWidgetOpenState = value
end

function M.setRequireWidgetVisibility(value)
    requireWidgetVisibility = value
end

local function executeIsInMotionSicknessCausingSceneCallback(...)
	return uevrUtils.executeUEVRCallbacksWithPriorityBooleanResult("is_in_motion_sickness_causing_scene", table.unpack({...}))
end

function M.registerIsInMotionSicknessCausingSceneCallback(func)
	uevrUtils.registerUEVRCallback("is_in_motion_sickness_causing_scene", func)
end

function M.registerWidgetChangeCallback(widgetName, func)
    if widgetName ~= nil and widgetName ~= "" and type(widgetName) == "string" then
	    uevrUtils.registerUEVRCallback("widget_change_" .. widgetName, func)
    end
end

function M.onUpdate(stateKey, func)
    if stateKey ~= nil and stateKey ~= "" and type(stateKey) == "string" and type(func) == "function" then
        uevrUtils.registerUEVRCallback("ui_state_change_" .. stateKey, func)
    end
end

function M.forceUpdate()
    updateUIState()
    updateUI()
end

local isInMotionSicknessCausingSceneLast = false
uevrUtils.setInterval(500, function()
    M.forceUpdate()

    local m_isInMotionSicknessCausingScene, priority = executeIsInMotionSicknessCausingSceneCallback()
	if m_isInMotionSicknessCausingScene ~= isInMotionSicknessCausingSceneLast then
		isInMotionSicknessCausingSceneLast = m_isInMotionSicknessCausingScene or false
		M.setIsInMotionSicknessCausingScene(m_isInMotionSicknessCausingScene)
	end
end)

uevrUtils.registerPreLevelChangeCallback(function(level)
	isInMotionSicknessCausingSceneLast = false
    uevrUtils.enableCameraLerp(false, true, true, true)

end)

return M
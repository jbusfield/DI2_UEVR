local uevrUtils = require("libs/uevr_utils")
local configui = require("libs/configui")

local M = {}

local configFileName = "dev/gesture_config_dev"
local configTabLabel = "Gesture Dev Config"
local widgetPrefix = "uevr_gesture_"

local configDefaults = {}
local paramManager = nil

local currentLogLevel = LogLevel.Error
function M.setLogLevel(val)
	currentLogLevel = val
end
function M.print(text, logLevel)
	if logLevel == nil then logLevel = LogLevel.Debug end
	if logLevel <= currentLogLevel then
		uevrUtils.print("[gesture config] " .. text, logLevel)
	end
end

-- Nested defaults mirror gestures.lua parameter tree (gesture type -> fields).
local parameterDefaults = {
	punch = {
		minThresholdSpeed = 180,
		maxThresholdSpeed = 320,
		forwardDotThreshold = 0.75,
		cooldownTime = 0.8,
	},
	swipe = {
		minThresholdSpeed = 180,
		maxThresholdSpeed = 320,
		directionThreshold = 0.001,
		cooldownTime = 0.5,
		snapTurnYawThreshold = 45.0,
	},
	holster = {
		triggerAngle = -60.0,
	},
	reload = {
		triggerDistance = 20.0,
	},
	chest = {
		triggerDistance = 15.0,
		offsetZ = -35.0,
		offsetForward = 5.0,
		triggerThreshold = 128,
	},
	face = {
		triggerThreshold = 128,
		mouth = {
			triggerDistance = 25.0,
			forwardDotMaxThreshold = 0.65,
			forwardDotMinThreshold = 0.35,
		},
		head = {
			triggerDistance = 25.0,
			forwardDotMaxThreshold = 0.65,
			forwardDotMinThreshold = 0.0,
		},
		eyes = {
			triggerDistance = 15.0,
			forwardDotThreshold = 0.85,
		},
		ear = {
			triggerDistance = 25.0,
			forwardDotThreshold = 0.8,
		},
	},
	componentGrab = {
		maxDistance = 10.0,
	},
}

local helpText = "Developer gesture configuration. Adjust detection thresholds, distances, and cooldowns per gesture type. Changes apply live while the game is running."

local function isNestedTable(value)
	return type(value) == "table" and value[1] == nil
end

local function getNested(tbl, path)
	local cur = tbl
	for i = 1, #path do
		if cur == nil then return nil end
		cur = cur[path[i]]
	end
	return cur
end

-- Flatten nested parameterDefaults into { path = {"punch","minThresholdSpeed"}, id = "punch_minThresholdSpeed", default = 180 }
local widgetBindings = {}
local function collectBindings(node, path)
	for key, value in pairs(node) do
		local nextPath = {}
		for i = 1, #path do nextPath[i] = path[i] end
		nextPath[#nextPath + 1] = key
		if isNestedTable(value) then
			collectBindings(value, nextPath)
		else
			local id = table.concat(nextPath, "_")
			table.insert(widgetBindings, {
				path = nextPath,
				id = id,
				default = value,
			})
		end
	end
end
collectBindings(parameterDefaults, {})

local function defaultFor(path)
	return getNested(parameterDefaults, path)
end

local function valueFor(path)
	local fromConfig = getNested(configDefaults, path)
	if fromConfig ~= nil then return fromConfig end
	return defaultFor(path)
end

local function floatWidget(path, label, speed, range)
	local id = table.concat(path, "_")
	return {
		widgetType = "drag_float",
		id = widgetPrefix .. id,
		label = label,
		speed = speed or 0.1,
		range = range or {-500, 500},
		initialValue = valueFor(path),
	}
end

local function getConfigWidgets(m_paramManager)
	return spliceableInlineArray{
		expandArray(m_paramManager.getProfilePreConfigurationWidgets, widgetPrefix, "Gesture Profile"),

		{
			widgetType = "tree_node",
			id = widgetPrefix .. "punch_tree",
			initialOpen = true,
			label = "Punch"
		},
			floatWidget({"punch", "minThresholdSpeed"}, "Min Speed", 1, {0, 2000}),
			floatWidget({"punch", "maxThresholdSpeed"}, "Max Speed", 1, {0, 2000}),
			floatWidget({"punch", "forwardDotThreshold"}, "Forward Dot Threshold", 0.01, {-1, 1}),
			floatWidget({"punch", "cooldownTime"}, "Cooldown (sec)", 0.01, {0, 10}),
		{ widgetType = "tree_pop" },

		{
			widgetType = "tree_node",
			id = widgetPrefix .. "swipe_tree",
			initialOpen = true,
			label = "Swipe / Snatch"
		},
			floatWidget({"swipe", "minThresholdSpeed"}, "Min Speed", 1, {0, 2000}),
			floatWidget({"swipe", "maxThresholdSpeed"}, "Max Speed", 1, {0, 2000}),
			floatWidget({"swipe", "directionThreshold"}, "Direction Threshold", 0.0001, {0, 1}),
			floatWidget({"swipe", "cooldownTime"}, "Cooldown (sec)", 0.01, {0, 10}),
			floatWidget({"swipe", "snapTurnYawThreshold"}, "Snap Turn Yaw Threshold (deg)", 0.5, {0, 180}),
		{ widgetType = "tree_pop" },

		{
			widgetType = "tree_node",
			id = widgetPrefix .. "holster_tree",
			initialOpen = true,
			label = "Holster"
		},
			floatWidget({"holster", "triggerAngle"}, "Trigger Angle (deg)", 0.5, {-90, 0}),
		{ widgetType = "tree_pop" },

		{
			widgetType = "tree_node",
			id = widgetPrefix .. "reload_tree",
			initialOpen = true,
			label = "Reload"
		},
			floatWidget({"reload", "triggerDistance"}, "Hand Distance", 0.5, {0, 200}),
		{ widgetType = "tree_pop" },

		{
			widgetType = "tree_node",
			id = widgetPrefix .. "chest_tree",
			initialOpen = true,
			label = "Chest Grab"
		},
			floatWidget({"chest", "triggerDistance"}, "Trigger Distance", 0.5, {0, 200}),
			floatWidget({"chest", "offsetZ"}, "Chest Offset Z", 0.5, {-200, 200}),
			floatWidget({"chest", "offsetForward"}, "Chest Offset Forward", 0.5, {-200, 200}),
			floatWidget({"chest", "triggerThreshold"}, "Analog Trigger Threshold", 1, {0, 255}),
		{ widgetType = "tree_pop" },

		{
			widgetType = "tree_node",
			id = widgetPrefix .. "face_tree",
			initialOpen = true,
			label = "Face / Head Gestures"
		},
			floatWidget({"face", "triggerThreshold"}, "Analog Trigger Threshold", 1, {0, 255}),
			{
				widgetType = "tree_node",
				id = widgetPrefix .. "face_mouth_tree",
				initialOpen = true,
				label = "Mouth (Eat / Lip Scratch)"
			},
				floatWidget({"face", "mouth", "triggerDistance"}, "Trigger Distance", 0.5, {0, 200}),
				floatWidget({"face", "mouth", "forwardDotMinThreshold"}, "Forward Dot Min", 0.01, {-1, 1}),
				floatWidget({"face", "mouth", "forwardDotMaxThreshold"}, "Forward Dot Max", 0.01, {-1, 1}),
			{ widgetType = "tree_pop" },
			{
				widgetType = "tree_node",
				id = widgetPrefix .. "face_head_tree",
				initialOpen = true,
				label = "Head (Hat / Head Scratch)"
			},
				floatWidget({"face", "head", "triggerDistance"}, "Trigger Distance", 0.5, {0, 200}),
				floatWidget({"face", "head", "forwardDotMinThreshold"}, "Forward Dot Min", 0.01, {-1, 1}),
				floatWidget({"face", "head", "forwardDotMaxThreshold"}, "Forward Dot Max", 0.01, {-1, 1}),
			{ widgetType = "tree_pop" },
			{
				widgetType = "tree_node",
				id = widgetPrefix .. "face_eyes_tree",
				initialOpen = true,
				label = "Eyes (Glasses / Eye Scratch)"
			},
				floatWidget({"face", "eyes", "triggerDistance"}, "Trigger Distance", 0.5, {0, 200}),
				floatWidget({"face", "eyes", "forwardDotThreshold"}, "Forward Dot Threshold", 0.01, {-1, 1}),
			{ widgetType = "tree_pop" },
			{
				widgetType = "tree_node",
				id = widgetPrefix .. "face_ear_tree",
				initialOpen = true,
				label = "Ear (Ear Grab / Scratch)"
			},
				floatWidget({"face", "ear", "triggerDistance"}, "Trigger Distance", 0.5, {0, 200}),
				floatWidget({"face", "ear", "forwardDotThreshold"}, "Forward Dot Threshold", 0.01, {-1, 1}),
			{ widgetType = "tree_pop" },
		{ widgetType = "tree_pop" },

		{
			widgetType = "tree_node",
			id = widgetPrefix .. "component_grab_tree",
			initialOpen = true,
			label = "Component Grab"
		},
			floatWidget({"componentGrab", "maxDistance"}, "Default Max Distance", 0.5, {0, 200}),
		{ widgetType = "tree_pop" },

		expandArray(m_paramManager.getProfilePostConfigurationWidgets, widgetPrefix, "Gesture Profile"),

		{ widgetType = "new_line" },
		{
			widgetType = "tree_node",
			id = widgetPrefix .. "help_tree",
			initialOpen = false,
			label = "Help"
		},
			{
				widgetType = "text",
				id = widgetPrefix .. "help",
				label = helpText,
				wrapped = true
			},
		{ widgetType = "tree_pop" },
	}
end

local function updateSetting(key, value)
	uevrUtils.executeUEVRCallbacks("on_gesture_config_param_change", key, value, true)
end

local function setUIValue(pathOrKey, value)
	if type(pathOrKey) == "table" then
		if isNestedTable(value) then
			for childKey, childValue in pairs(value) do
				local childPath = {}
				for i = 1, #pathOrKey do childPath[i] = pathOrKey[i] end
				childPath[#childPath + 1] = childKey
				setUIValue(childPath, childValue)
			end
		else
			configui.setValue(widgetPrefix .. table.concat(pathOrKey, "_"), value, true)
		end
		return
	end

	if isNestedTable(value) then
		for childKey, childValue in pairs(value) do
			setUIValue({pathOrKey, childKey}, childValue)
		end
	else
		configui.setValue(widgetPrefix .. pathOrKey, value, true)
	end
end

local function updateUI(params)
	for key, value in pairs(params) do
		setUIValue(key, value)
	end
end

function M.getConfigurationWidgets(options)
	return configui.applyOptionsToConfigWidgets(getConfigWidgets(paramManager), options)
end

function M.showConfiguration(saveFileName, options)
	configui.createConfigPanel(configTabLabel, saveFileName, spliceableInlineArray{expandArray(M.getConfigurationWidgets, options)})
end

function M.init(m_paramManager)
	configDefaults = m_paramManager and m_paramManager:getAllActiveProfileParams() or {}
	paramManager = m_paramManager
	M.showConfiguration(configFileName)

	paramManager:initProfileHandler(widgetPrefix, function(profileParams)
		updateUI(profileParams)
	end)

	for _, binding in ipairs(widgetBindings) do
		configui.onUpdate(widgetPrefix .. binding.id, function(val)
			updateSetting(binding.path, val)
		end)
	end
end

uevrUtils.registerUEVRCallback("on_gesture_config_param_change", function(key, value)
	setUIValue(key, value)
end)

return M

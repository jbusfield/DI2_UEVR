local uevrUtils = require("libs/uevr_utils")
local configui = require("libs/configui")

local M = {}

local configFileName = "gesture_config"
local configTabLabel = "Gesture Config"
local widgetPrefix = "uevr_gesture_config_"

local configDefaults = {
	swipe = {
		minThresholdSpeed = 180,
	},
}

local function getNested(tbl, path)
	local cur = tbl
	for i = 1, #path do
		if cur == nil then return nil end
		cur = cur[path[i]]
	end
	return cur
end

local function valueFor(path)
	local fromConfig = getNested(configDefaults, path)
	if fromConfig ~= nil then return fromConfig end
	return nil
end

local function intWidget(path, label, range)
	local id = table.concat(path, "_")
	return {
		widgetType = "slider_int",
		id = widgetPrefix .. id,
		label = label,
		range = range or {0, 2000},
		initialValue = valueFor(path),
	}
end

local function getConfigWidgets()
	return spliceableInlineArray{
		intWidget({"swipe", "minThresholdSpeed"}, "Swipe Min Speed", {0, 2000}),
	}
end

local function updateSetting(path, value)
	uevrUtils.executeUEVRCallbacks("on_gesture_config_param_change", path, value, true)
end

local function setUIValue(pathOrKey, value)
	if type(pathOrKey) == "table" then
		configui.setValue(widgetPrefix .. table.concat(pathOrKey, "_"), value, true)
		return
	end
	if type(value) == "table" and value[1] == nil then
		for childKey, childValue in pairs(value) do
			setUIValue({pathOrKey, childKey}, childValue)
		end
	else
		configui.setValue(widgetPrefix .. pathOrKey, value, true)
	end
end

configui.onUpdate(widgetPrefix .. "swipe_minThresholdSpeed", function(value)
	updateSetting({"swipe", "minThresholdSpeed"}, value)
end)

configui.onCreate(widgetPrefix .. "swipe_minThresholdSpeed", function()
	configui.setValue(widgetPrefix .. "swipe_minThresholdSpeed", valueFor({"swipe", "minThresholdSpeed"}), true)
end)

local function selectWidgets(widgets, selections)
	local byId = {}
	for _, widget in ipairs(widgets) do
		if widget.id ~= nil then
			byId[widget.id] = widget
		end
	end
	local result = {}
	for _, sel in ipairs(selections) do
		local src = byId[sel.id]
		if src ~= nil then
			local copy = {}
			for k, v in pairs(src) do
				copy[k] = v
			end
			for k, v in pairs(sel) do
				copy[k] = v
			end
			result[#result + 1] = copy
		end
	end
	return result
end

function M.getConfigurationWidgets(options)
	local widgets = getConfigWidgets()
	if options ~= nil and options.select ~= nil then
		return selectWidgets(widgets, options.select)
	end
	return configui.applyOptionsToConfigWidgets(widgets, options)
end

function M.showConfiguration(saveFileName, options)
	configui.createConfigPanel(configTabLabel, saveFileName, spliceableInlineArray{
		expandArray(M.getConfigurationWidgets, options)
	})
end

function M.init(m_paramManager)
	configDefaults = m_paramManager and m_paramManager:getAllActiveProfileParams() or configDefaults

	if m_paramManager ~= nil then
		m_paramManager:registerProfileChangeCallback(function(profileParams)
			local swipe = profileParams and profileParams.swipe
			if swipe ~= nil and swipe.minThresholdSpeed ~= nil then
				configui.setValue(widgetPrefix .. "swipe_minThresholdSpeed", swipe.minThresholdSpeed, true)
			end
		end)
	end
end

uevrUtils.registerUEVRCallback("on_gesture_config_param_change", function(key, value)
	setUIValue(key, value)
end)

return M
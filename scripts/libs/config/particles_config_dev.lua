local uevrUtils = require("libs/uevr_utils")
local configui = require("libs/configui")
local controllers = require("libs/controllers")

local M = {}

local configFileName = "dev/particles_config_dev"
local configTabLabel = "Particles Config Dev"
local widgetPrefix = "uevr_particles_"

local paramManager = nil
local particlesModule = nil
local suppressUI = false

local currentLogLevel = LogLevel.Error
function M.setLogLevel(val)
	currentLogLevel = val
end
function M.print(text, logLevel)
	if logLevel == nil then logLevel = LogLevel.Debug end
	if logLevel <= currentLogLevel then
		uevrUtils.print("[particles config] " .. text, logLevel)
	end
end

local function getConfigWidgets(m_paramManager)
	return spliceableInlineArray {
		expandArray(m_paramManager.getProfilePreConfigurationWidgets, widgetPrefix, "Particle"),
        { widgetType = "begin_group", id = widgetPrefix .. "current_widget_info", isHidden = false }, { widgetType = "indent", width = 10 }, { widgetType = "text", label = "Widget Reticule Settings" }, { widgetType = "begin_rect", },
		{
			widgetType = "tree_node",
			id = widgetPrefix .. "finder_tool",
			initialOpen = true,
			label = "Particle System Finder"
		},
            {
				widgetType = "combo",
				id = widgetPrefix .. "finder_emitter_type",
				label = "Emitters Type",
				selections = {"NiagaraSystem", "ParticleSystem"},
				initialValue = 1,
			},
            {
                widgetType = "tree_node",
                id = widgetPrefix .. "finder_instruction_tree",
                initialOpen = false,
                label = "Particle Finder Instructions"
            },
                {
                    widgetType = "text",
                    id = widgetPrefix .. "finder_instructions",
                    label = "You can enter text in the search text box below to search for specific Particle Systems. Press the Find button to see an updated list of particle systems.",
                    wrapped = true
                },
            { widgetType = "tree_pop" },
			{
				widgetType = "input_text",
				id = widgetPrefix .. "finder_tool_search_text",
				label = "",
				initialValue = "",
			},
			{ widgetType = "same_line" },
			{
				widgetType = "button",
				id = widgetPrefix .. "finder_tool_search_button",
				label = "Find",
				size = {80, 22},
			},
			{
				widgetType = "button",
				id = widgetPrefix .. "finder_tool_list_prev",
				label = "<",
				size = {40, 22},
			},
			{ widgetType = "same_line" },
			{
				widgetType = "combo",
				id = widgetPrefix .. "finder_tool_list",
				label = "Particle Systems",
				selections = {"None"},
				initialValue = 1,
                width = 300,
			},
			{ widgetType = "same_line" },
			{
				widgetType = "button",
				id = widgetPrefix .. "finder_tool_list_next",
				label = ">",
				size = {40, 22},
			},
            { widgetType = "indent", width = 120 },
			{
				widgetType = "button",
				id = widgetPrefix .. "use_selected_button",
				label = "Use Selected",
				size = {120, 22},
			},
            { widgetType = "unindent", width = 120 },
        { widgetType = "tree_pop" },
		{
			widgetType = "input_text",
			id = widgetPrefix .. "asset",
			label = "Particle Class",
			initialValue = "",
		},
		{
			widgetType = "drag_float3",
			id = widgetPrefix .. "scale",
			label = "Scale",
			speed = 0.001,
			range = {0.001, 10},
			initialValue = {0.04, 0.04, 0.04},
		},
		{
			widgetType = "checkbox",
			id = widgetPrefix .. "loop",
			label = "Looping",
			initialValue = true,
		},
        { widgetType = "begin_group", id = widgetPrefix .. "looping_settings", isHidden = false }, { widgetType = "indent", width = 20 },		
            {
                widgetType = "drag_float",
                id = widgetPrefix .. "loopStart",
                label = "Start (s)",
                speed = 0.05,
                range = {0, 30},
                initialValue = 0.0,
                width = 100,
            },
            { widgetType = "same_line" },
            { widgetType = "space_horizontal", space = 30},
            {
                widgetType = "drag_float",
                id = widgetPrefix .. "loopEnd",
                label = "Loop End (s)",
                speed = 0.05,
                range = {0.05, 60},
                initialValue = 5.0,
                width = 100,
            },
        { widgetType = "unindent", width = 20 }, { widgetType = "end_group", },
		{
			widgetType = "combo",
			id = widgetPrefix .. "effect_list",
			label = "Effect Emitter",
			selections = {"None"},
			initialValue = 1,
            width = 300,
		},
        { widgetType = "same_line" },
		{
			widgetType = "checkbox",
			id = widgetPrefix .. "effect_enabled",
			label = "Emitter Enabled",
			initialValue = true,
		},
        { widgetType = "indent", width = 150 },
        { widgetType = "begin_group", id = widgetPrefix .. "test_group", isHidden = false },
		{ widgetType = "text", label = " " },
        { widgetType = "same_line" },
        {
			widgetType = "button",
			id = widgetPrefix .. "test_button",
			label = "Test",
			size = {80, 22},
		},
		{ widgetType = "same_line" },
		{
			widgetType = "button",
			id = widgetPrefix .. "stop_test_button",
			label = "Stop",
			size = {80, 22},
		},
        { widgetType = "end_group", },
        { widgetType = "unindent", width = 150 },
        { widgetType = "end_rect", additionalSize = 12, rounding = 5 }, { widgetType = "unindent", width = 10 }, { widgetType = "end_group", },
		{ widgetType = "new_line" },
        expandArray(m_paramManager.getProfilePostConfigurationWidgets, widgetPrefix, "Particle"),
	}
end

local searchText = nil
local niagaraNames = {}
local particleNames = {}

local function getFinderNames()
	if configui.getValue(widgetPrefix .. "finder_emitter_type") == 1 then
		return niagaraNames
	end
	return particleNames
end

local function loadParticlesSystems()
	local results = {}
	if configui.getValue(widgetPrefix .. "finder_emitter_type") == 1 then
		niagaraNames = {}
		local instances = uevrUtils.find_all_instances("Class /Script/Niagara.NiagaraSystem", false)
		if instances ~= nil then
			for _, niagara in pairs(instances) do
				if searchText == nil or searchText == "" or string.find(niagara:get_full_name(), searchText) then
					table.insert(niagaraNames, niagara:get_full_name())
				end
			end
		end
		results = niagaraNames
	else
		particleNames = {}
		local instances = uevrUtils.find_all_instances("Class /Script/Engine.ParticleSystem", false)
		if instances ~= nil then
			for _, particle in pairs(instances) do
				if searchText == nil or searchText == "" or string.find(particle:get_full_name(), searchText) then
					table.insert(particleNames, particle:get_full_name())
				end
			end
		end
		results = particleNames
	end
	configui.setSelections(widgetPrefix .. "finder_tool_list", results)
end

local currentTest = nil
local currentEffectNames = nil

local function clearEffectEmitterUI()
	currentEffectNames = nil
	configui.setSelections(widgetPrefix .. "effect_list", {"None"})
	configui.setValue(widgetPrefix .. "effect_list", 1, true)
	configui.setValue(widgetPrefix .. "effect_enabled", true, true)
end

local function stopTest()
	if currentTest ~= nil then
		if currentTest.stop ~= nil then currentTest:stop() end
		currentTest:destroy()
	end
	currentTest = nil
	configui.setHidden(widgetPrefix .. "test_button", false)
	configui.setHidden(widgetPrefix .. "stop_test_button", true)
end

function M.stopTest()
	stopTest()
end

local function updateSetting(key, value)
	if paramManager == nil then return end
	paramManager:setInActiveProfile(key, value, true)
end

local function updateUIValue(key, value)
	suppressUI = true
	if key == "emitters" then
		-- applied via effect_list / effect_enabled
	elseif key == "rotation" or key == "location" then
		-- not exposed in UI yet
	else
		configui.setValue(widgetPrefix .. key, value, true)
	end
	suppressUI = false
end

local function isEffectEmitterEnabled(name)
	if name == nil then return true end
	local overrides = paramManager and paramManager:getFromActiveProfile("emitters") or {}
	if overrides[name] ~= nil then
		return overrides[name] == true
	end
	return true
end

-- First time we see an emitter for this profile, snapshot the asset's current enable into params.
local function seedMissingEmitterParams(names, assetDefaults)
	if paramManager == nil or names == nil then return end
	local overrides = paramManager:getFromActiveProfile("emitters")
	if type(overrides) ~= "table" then
		overrides = {}
		updateSetting("emitters", overrides)
	end
	for _, name in ipairs(names) do
		if overrides[name] == nil then
			local on = true
			if assetDefaults ~= nil and assetDefaults[name] ~= nil then
				on = assetDefaults[name] == true
			end
			updateSetting({"emitters", name}, on)
		end
	end
end

local function refreshEffectEmitterUI()
	local asset = configui.getValue(widgetPrefix .. "asset")
	if asset == nil or asset == "" or particlesModule == nil or particlesModule.listEmittersFromAsset == nil then
		clearEffectEmitterUI()
		return
	end
	local names, assetDefaults = particlesModule.listEmittersFromAsset(asset)
	if names == nil or #names < 1 then
		clearEffectEmitterUI()
		return
	end
	seedMissingEmitterParams(names, assetDefaults)
	currentEffectNames = names
	configui.setSelections(widgetPrefix .. "effect_list", names)
	local idx = configui.getValue(widgetPrefix .. "effect_list") or 1
	if idx < 1 or idx > #names then idx = 1 end
	configui.setValue(widgetPrefix .. "effect_list", idx, true)
	configui.setValue(widgetPrefix .. "effect_enabled", isEffectEmitterEnabled(names[idx]), true)
end

local function startTest()
	stopTest()
	if paramManager == nil or particlesModule == nil then return end
	local profile = paramManager:getAllActiveProfileParams() or {}
	local opts = particlesModule.optionsFromProfile(profile)
	if opts == nil then
		M.print("Test failed: set an asset first (Use Selected)", LogLevel.Error)
		return
	end
	currentTest = particlesModule.new(opts)
	if currentTest == nil then
		M.print("Test failed: particle was not created", LogLevel.Error)
		return
	end
	currentTest:attachTo(controllers.getController(Handed.Left))
	currentTest:setRelativeLocation({X = 50, Y = 0, Z = 0})
	currentTest:start()
	configui.setHidden(widgetPrefix .. "test_button", true)
	configui.setHidden(widgetPrefix .. "stop_test_button", false)
	refreshEffectEmitterUI()
end

function M.getConfigurationWidgets(options)
	return configui.applyOptionsToConfigWidgets(getConfigWidgets(paramManager), options)
end

function M.showConfiguration(saveFileName, options)
	configui.createConfigPanel(configTabLabel, saveFileName, spliceableInlineArray{expandArray(M.getConfigurationWidgets, options)})
end

function M.init(m_paramManager, particlesApi)
	paramManager = m_paramManager
	particlesModule = particlesApi
	M.showConfiguration(configFileName)
	configui.setHidden(widgetPrefix .. "stop_test_button", true)
	loadParticlesSystems()

	paramManager:initProfileHandler(widgetPrefix, function(profileParams)
		stopTest()
		local defaults = paramManager.defaultParameters or {}
		for key, def in pairs(defaults) do
			local value = profileParams[key]
			if value == nil then value = def end
			updateUIValue(key, value)
		end
		refreshEffectEmitterUI()
	end)
end

configui.onUpdate(widgetPrefix .. "asset", function(value)
	if suppressUI then return end
	updateSetting("asset", value)
	refreshEffectEmitterUI()
end)
configui.onUpdate(widgetPrefix .. "scale", function(value)
	if suppressUI then return end
	updateSetting("scale", value)
end)
configui.onUpdate(widgetPrefix .. "loop", function(value)
	if suppressUI then return end
	updateSetting("loop", value == true)
    configui.setHidden(widgetPrefix .. "looping_settings", value == false)
end)
configui.onCreate(widgetPrefix .. "loop", function()
    configui.setHidden(widgetPrefix .. "looping_settings", configui.getValue(widgetPrefix .. "loop") == false)
end)
configui.onUpdate(widgetPrefix .. "loopStart", function(value)
	if suppressUI then return end
	updateSetting("loopStart", value)
end)
configui.onUpdate(widgetPrefix .. "loopEnd", function(value)
	if suppressUI then return end
	updateSetting("loopEnd", value)
end)

configui.onUpdate(widgetPrefix .. "finder_emitter_type", function()
	loadParticlesSystems()
end)
configui.onUpdate(widgetPrefix .. "finder_tool_search_text", function(value)
	searchText = value
end)
configui.onUpdate(widgetPrefix .. "finder_tool_search_button", function()
	loadParticlesSystems()
end)
configui.onUpdate(widgetPrefix .. "finder_tool_list_prev", function()
	local names = getFinderNames()
	local index = (configui.getValue(widgetPrefix .. "finder_tool_list") or 1) - 1
	if index < 1 then index = 1 end
	if names ~= nil and index <= #names then
		configui.setValue(widgetPrefix .. "finder_tool_list", index)
	end
end)
configui.onUpdate(widgetPrefix .. "finder_tool_list_next", function()
	local names = getFinderNames()
	if names == nil or #names < 1 then return end
	local index = (configui.getValue(widgetPrefix .. "finder_tool_list") or 1) + 1
	if index > #names then index = #names end
	configui.setValue(widgetPrefix .. "finder_tool_list", index)
end)
configui.onUpdate(widgetPrefix .. "use_selected_button", function()
	local names = getFinderNames()
	local index = configui.getValue(widgetPrefix .. "finder_tool_list")
	local asset = names and names[index]
	if asset == nil then return end
	updateSetting("asset", asset)
	updateSetting("emitters", {})
	suppressUI = true
	configui.setValue(widgetPrefix .. "asset", asset, true)
	suppressUI = false
	stopTest()
	refreshEffectEmitterUI()
end)

configui.onUpdate(widgetPrefix .. "test_button", function()
	startTest()
end)
configui.onUpdate(widgetPrefix .. "stop_test_button", function()
	stopTest()
	refreshEffectEmitterUI()
end)
configui.onUpdate(widgetPrefix .. "effect_list", function(value)
	if currentEffectNames == nil then return end
	local name = currentEffectNames[value]
	if name == nil then return end
	configui.setValue(widgetPrefix .. "effect_enabled", isEffectEmitterEnabled(name), true)
end)
configui.onUpdate(widgetPrefix .. "effect_enabled", function(value)
	if currentEffectNames == nil then return end
	local index = configui.getValue(widgetPrefix .. "effect_list")
	local name = currentEffectNames[index]
	if name == nil then return end
	if currentTest ~= nil and currentTest.setEmitterEnabled ~= nil then
		currentTest:setEmitterEnabled(name, value == true)
	end
	updateSetting({"emitters", name}, value == true)
end)

return M

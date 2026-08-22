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
	block = {
		maxDropCm = 45.0,
		maxRaiseCm = 10.0,
		inFront = 0.75,
		maxPointForward = 0.6,
		maxTiltDeg = 58.0,
		palmFacing = 0.5,
		releaseSlack = 0.25,
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

local punchHelpLines = {
	"Min Speed - How fast your hand must move before a punch counts. Higher = ignore slow reaches and nudges; lower = easier to trigger with a light jab.",
	"Max Speed - Caps how hard a punch feels for strength (0-1). Does not block detection. Higher = need a faster punch to reach full strength; lower = even moderate punches report as strong.",
	"Forward Dot Threshold - How strongly the hand must be moving in the direction the controller is pointing. Higher = must punch more straight along the controller aim; lower = allow glancing / off-axis hits.",
	"Cooldown (sec) - How long after a punch before another can fire. Higher = fewer rapid repeats; lower = can chain punches sooner.",
}

local swipeHelpLines = {
	"Min Speed - How fast your hand must move before a swipe/snatch counts. Higher = ignore slow waves and twitches; lower = easier to trigger with a light flick.",
	"Max Speed - Caps how hard a swipe feels for strength (0-1). Does not block detection. Higher = need a faster swing to reach full strength; lower = even moderate swings report as strong.",
	"Direction Threshold - How clearly the motion must favor one axis (left/right/up/down/pull-in) to pick that swipe type. Higher = stricter direction; lower = looser classification (more accidental directions).",
	"Cooldown (sec) - How long after a swipe before another can fire. Higher = fewer rapid repeats; lower = can chain swipes sooner.",
	"Snap Turn Yaw Threshold (deg) - Ignores hand motion when your view/yaw jumps this much (e.g. snap turn). Higher = tolerate bigger yaw jumps without canceling; lower = treat smaller turns as \"not a swipe\".",
}

local blockHelpLines = {
	"Max Drop Below Head (cm) - How far below your head the hand may sit and still count as a block. Higher = allow a lower guard (toward chest); lower = hand must stay up near face height.",
	"Max Raise Above Head (cm) - How far above your head the hand may sit. Higher = allow an overhead / high guard; lower = hand must stay at or below head height.",
	"Must Be In Front (0-1) - How directly in front of your face/chest the hand must be (not out beside your ear). Higher = hand must be more centered in front of you; lower = allow a wider/side guard. Also tightens how far out to either side the hand may drift.",
	"Max Pointing Forward (0-1) - Whether your forearm is laid across your body vs aimed out at what you're looking at. Lower = more \"guard bar across me\" (tip pointing left/right); higher = allow pointing forward a bit while still counting as a block (more reach/punch-like).",
	"Max Controller Tilt (deg) - How much the controller may tip up or down from horizontal (wrist / forearm pitch). Higher = allow a steeper forearm; lower = forearm must stay more level.",
	"Palm Facing Away (0-1) - How strongly the palm must face away from you (toward the threat), not down or toward you. Higher = stricter \"shield facing out\"; lower = allow a lazier / more rotated wrist.",
	"Release Slack (0-1) - How sticky the pose is when leaving it (hysteresis on all checks). Higher = stays active longer as you drift out of the ideal pose; lower = snaps off quickly.",
}

-- Collapsed Help tree for a gesture section. Usage: expandArray(getGestureHelpWidgets, "block", blockHelpLines)
local function getGestureHelpWidgets(name, lines)
	local widgets = {
		{
			widgetType = "tree_node",
			id = widgetPrefix .. name .. "_help_tree",
			initialOpen = false,
			label = "Help"
		},
	}
	for i, line in ipairs(lines or {}) do
		if i > 1 then
			widgets[#widgets + 1] = { widgetType = "new_line" }
		end
		widgets[#widgets + 1] = {
			widgetType = "text",
			id = widgetPrefix .. name .. "_help_" .. i,
			label = line,
			wrapped = true
		}
	end
	widgets[#widgets + 1] = { widgetType = "tree_pop" }
	return widgets
end

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

-- Test checkbox + Left/Right status row (ids: <name>_test, <name>_test_status_left/right)
local function getGestureTestWidgets(name)
	return {
		{ widgetType = "checkbox", id = widgetPrefix .. name .. "_test", label = "Test", initialValue = false },
		{ widgetType = "same_line" },
		{ widgetType = "text_colored", id = widgetPrefix .. name .. "_test_status_left", label = "Left Inactive", color = "#00000000" },
		{ widgetType = "same_line" },
		{ widgetType = "text_colored", id = widgetPrefix .. name .. "_test_status_right", label = "Right Inactive", color = "#00000000" },
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
		expandArray(getGestureTestWidgets, "punch"),
			floatWidget({"punch", "minThresholdSpeed"}, "Min Speed", 1, {0, 2000}),
			floatWidget({"punch", "maxThresholdSpeed"}, "Max Speed", 1, {0, 2000}),
			floatWidget({"punch", "forwardDotThreshold"}, "Forward Dot Threshold", 0.01, {-1, 1}),
			floatWidget({"punch", "cooldownTime"}, "Cooldown (sec)", 0.01, {0, 10}),
		expandArray(getGestureHelpWidgets, "punch", punchHelpLines),
		{ widgetType = "tree_pop" },

		{
			widgetType = "tree_node",
			id = widgetPrefix .. "swipe_tree",
			initialOpen = true,
			label = "Swipe / Snatch"
		},
		expandArray(getGestureTestWidgets, "swipe"),
			floatWidget({"swipe", "minThresholdSpeed"}, "Min Speed", 1, {0, 2000}),
			floatWidget({"swipe", "maxThresholdSpeed"}, "Max Speed", 1, {0, 2000}),
			floatWidget({"swipe", "directionThreshold"}, "Direction Threshold", 0.0001, {0, 1}),
			floatWidget({"swipe", "cooldownTime"}, "Cooldown (sec)", 0.01, {0, 10}),
			floatWidget({"swipe", "snapTurnYawThreshold"}, "Snap Turn Yaw Threshold (deg)", 0.5, {0, 180}),
		expandArray(getGestureHelpWidgets, "swipe", swipeHelpLines),
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
		expandArray(getGestureTestWidgets, "chest"),
			floatWidget({"chest", "triggerDistance"}, "Trigger Distance", 0.5, {0, 200}),
			floatWidget({"chest", "offsetZ"}, "Chest Offset Z", 0.5, {-200, 200}),
			floatWidget({"chest", "offsetForward"}, "Chest Offset Forward", 0.5, {-200, 200}),
			floatWidget({"chest", "triggerThreshold"}, "Analog Trigger Threshold", 1, {0, 255}),
		{ widgetType = "tree_pop" },

		{
			widgetType = "tree_node",
			id = widgetPrefix .. "block_tree",
			initialOpen = true,
			label = "Block"
		},
		expandArray(getGestureTestWidgets, "block"),
			floatWidget({"block", "maxDropCm"}, "Max Drop Below Head (cm)", 0.5, {0, 200}),
			floatWidget({"block", "maxRaiseCm"}, "Max Raise Above Head (cm)", 0.5, {0, 100}),
			floatWidget({"block", "inFront"}, "Must Be In Front (0-1)", 0.01, {0, 1}),
			floatWidget({"block", "maxPointForward"}, "Max Pointing Forward (0-1)", 0.01, {0, 1}),
			floatWidget({"block", "maxTiltDeg"}, "Max Controller Tilt (deg)", 0.5, {0, 90}),
			floatWidget({"block", "palmFacing"}, "Palm Facing Away (0-1)", 0.01, {0, 1}),
			floatWidget({"block", "releaseSlack"}, "Release Slack (0-1)", 0.01, {0, 1}),
		expandArray(getGestureHelpWidgets, "block", blockHelpLines),
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
			expandArray(getGestureTestWidgets, "face_mouth"),
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
			expandArray(getGestureTestWidgets, "face_head"),
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
			expandArray(getGestureTestWidgets, "face_eyes"),
				floatWidget({"face", "eyes", "triggerDistance"}, "Trigger Distance", 0.5, {0, 200}),
				floatWidget({"face", "eyes", "forwardDotThreshold"}, "Forward Dot Threshold", 0.01, {-1, 1}),
			{ widgetType = "tree_pop" },
			{
				widgetType = "tree_node",
				id = widgetPrefix .. "face_ear_tree",
				initialOpen = true,
				label = "Ear (Ear Grab / Scratch)"
			},
			expandArray(getGestureTestWidgets, "face_ear"),
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

-- Gesture ids match gestures.Gesture (avoid requiring gestures.lua).
local GESTURE_PUNCH = 0
local GESTURE_EARGRAB = 3
local GESTURE_EAT = 4
local GESTURE_GLASSESGRAB = 5
local GESTURE_HATGRAB = 6
local GESTURE_SWIPE_LEFT = 11
local GESTURE_CHESTGRAB = 17
local GESTURE_BLOCK = 18
local MOMENTARY_ACTIVE_MS = 500

local gestureTests = {}
local activeTestName = nil

local function setHandStatus(statusId, handLabel, active, visible)
	if not visible then
		configui.setLabel(statusId, handLabel .. " Inactive")
		configui.setColor(statusId, "#00000000")
		return
	end
	if active then
		configui.setLabel(statusId, handLabel .. " Active")
		configui.setColor(statusId, "#00FF00FF")
	else
		configui.setLabel(statusId, handLabel .. " Inactive")
		configui.setColor(statusId, "#FF0000FF")
	end
end

local function refreshGestureTest(test)
	setHandStatus(test.leftId, "Left", test.activeByHand[Handed.Left] == true, true)
	setHandStatus(test.rightId, "Right", test.activeByHand[Handed.Right] == true, true)
end

local function flashMomentaryHand(test, hand)
	test.activeByHand[hand] = true
	refreshGestureTest(test)
	test.flashGeneration = (test.flashGeneration or 0) + 1
	local generation = test.flashGeneration
	uevrUtils.delay(MOMENTARY_ACTIVE_MS, function()
		if not test.enabled or test.flashGeneration ~= generation then
			return
		end
		test.activeByHand[Handed.Left] = false
		test.activeByHand[Handed.Right] = false
		refreshGestureTest(test)
	end)
end

local function registerGestureTest(name, gestureId, opts)
	local test = {
		name = name,
		gestureId = gestureId,
		checkboxId = widgetPrefix .. name .. "_test",
		leftId = widgetPrefix .. name .. "_test_status_left",
		rightId = widgetPrefix .. name .. "_test_status_right",
		enabled = false,
		momentary = opts.momentary == true,
		combineCallbacks = opts.combineCallbacks == true,
		activeByHand = {},
		activeSourcesByHand = {
			[Handed.Left] = {},
			[Handed.Right] = {},
		},
		flashGeneration = 0,
	}
	gestureTests[name] = test

	for _, callbackName in ipairs(opts.callbacks) do
		uevrUtils.registerUEVRCallback(callbackName, function(activeOrStrength, hand)
			if hand == nil then
				return
			end
			if test.momentary then
				if not test.enabled then
					return
				end
				flashMomentaryHand(test, hand)
				return
			end
			if test.combineCallbacks then
				local sources = test.activeSourcesByHand[hand]
				sources[callbackName] = activeOrStrength == true
				local any = false
				for _, active in pairs(sources) do
					if active then
						any = true
						break
					end
				end
				test.activeByHand[hand] = any
			else
				test.activeByHand[hand] = activeOrStrength == true
			end
			if not test.enabled then
				return
			end
			refreshGestureTest(test)
		end)
	end
end

local function hideGestureTest(test)
	setHandStatus(test.leftId, "Left", false, false)
	setHandStatus(test.rightId, "Right", false, false)
	test.activeByHand[Handed.Left] = false
	test.activeByHand[Handed.Right] = false
	test.activeSourcesByHand[Handed.Left] = {}
	test.activeSourcesByHand[Handed.Right] = {}
	test.flashGeneration = (test.flashGeneration or 0) + 1
end
local function setGestureTestEnabled(name, enabled)
	local test = gestureTests[name]
	if test == nil then
		return
	end
	test.enabled = enabled == true
	if test.enabled then
		if activeTestName ~= nil and activeTestName ~= name and gestureTests[activeTestName] ~= nil then
			local other = gestureTests[activeTestName]
			other.enabled = false
			configui.setValue(other.checkboxId, false, true)
			hideGestureTest(other)
		end
		activeTestName = name
		uevrUtils.executeUEVRCallbacks("on_gesture_test", test.gestureId)
		refreshGestureTest(test)
	else
		if activeTestName == name then
			activeTestName = nil
			uevrUtils.executeUEVRCallbacks("on_gesture_test", nil)
		end
		hideGestureTest(test)
	end
end

registerGestureTest("punch", GESTURE_PUNCH, {
	momentary = true,
	callbacks = { "on_gesture_punch" },
})
registerGestureTest("swipe", GESTURE_SWIPE_LEFT, {
	momentary = true,
	callbacks = {
		"on_gesture_swipe_left",
		"on_gesture_swipe_right",
		"on_gesture_swipe_up",
		"on_gesture_swipe_down",
		"on_gesture_snatch",
	},
})
registerGestureTest("chest", GESTURE_CHESTGRAB, {
	momentary = false,
	callbacks = { "on_gesture_chestgrab" },
})
registerGestureTest("block", GESTURE_BLOCK, {
	momentary = false,
	callbacks = { "on_gesture_block" },
})
registerGestureTest("face_mouth", GESTURE_EAT, {
	momentary = false,
	combineCallbacks = true,
	callbacks = { "on_gesture_eat", "on_gesture_lipscratch" },
})
registerGestureTest("face_head", GESTURE_HATGRAB, {
	momentary = false,
	combineCallbacks = true,
	callbacks = { "on_gesture_hatgrab", "on_gesture_headscratch" },
})
registerGestureTest("face_eyes", GESTURE_GLASSESGRAB, {
	momentary = false,
	combineCallbacks = true,
	callbacks = { "on_gesture_glassesgrab", "on_gesture_eyescratch" },
})
registerGestureTest("face_ear", GESTURE_EARGRAB, {
	momentary = false,
	combineCallbacks = true,
	callbacks = { "on_gesture_eargrab", "on_gesture_earscratch" },
})

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

	for name, _ in pairs(gestureTests) do
		configui.onUpdate(widgetPrefix .. name .. "_test", function(enabled)
			setGestureTestEnabled(name, enabled)
		end)
		configui.setValue(widgetPrefix .. name .. "_test", false, true)
		hideGestureTest(gestureTests[name])
	end
	uevrUtils.executeUEVRCallbacks("on_gesture_test", nil)
end

uevrUtils.registerUEVRCallback("on_gesture_config_param_change", function(key, value)
	setUIValue(key, value)
end)

return M

local uevrUtils = require("libs/uevr_utils")
local controllers = require("libs/controllers")
local paramModule = require("libs/core/params")

--[[
Usage
	local gestures = require("libs/gestures")
	gestures.init()
	In developer mode, gestures.init(true) also loads the in-game gesture configuration tool.
	Parameters are stored in gesture_parameters.json (profiles supported).

Punch settings (forward strike — what each value means for your arm)
	minThresholdSpeed
		How fast your hand must move before a punch counts.
		Higher = ignore slow reaches and nudges; lower = easier to trigger with a light jab.

	maxThresholdSpeed
		Caps how hard a punch feels for strength (0-1). Does not block detection.
		Higher = need a faster punch to reach full strength; lower = even moderate punches report as strong.

	forwardDotThreshold
		How strongly the hand must be moving in the direction the controller is pointing.
		Higher = must punch more straight along the controller aim; lower = allow glancing / off-axis hits.

	cooldownTime
		How long after a punch before another can fire.
		Higher = fewer rapid repeats; lower = can chain punches sooner.

Block settings (sustained guard pose — what each value means for your arm)
	maxDropCm
		How far below your head the hand may sit and still count as a block.
		Higher = allow a lower guard (toward chest); lower = hand must stay up near face height.

	maxRaiseCm
		How far above your head the hand may sit.
		Higher = allow an overhead / high guard; lower = hand must stay at or below head height.

	inFront
		How directly in front of your face/chest the hand must be (not out beside your ear).
		Higher = hand must be more centered in front of you; lower = allow a wider/side guard.
		Also tightens how far out to either side the hand may drift.

	maxPointForward
		Whether your forearm is laid across your body vs aimed out at what you're looking at.
		Lower = more "guard bar across me" (tip pointing left/right); higher = allow pointing
		forward a bit while still counting as a block (more reach/punch-like).

	maxTiltDeg
		How much the controller may tip up or down from horizontal (wrist / forearm pitch).
		Higher = allow a steeper forearm; lower = forearm must stay more level.

	palmFacing
		How strongly the palm must face away from you (toward the threat), not down or toward you.
		Higher = stricter "shield facing out"; lower = allow a lazier / more rotated wrist.

	releaseSlack
		How sticky the pose is when leaving it (hysteresis on all checks).
		Higher = stays active longer as you drift out of the ideal pose; lower = snaps off quickly.

Swipe / Snatch settings (fast hand motion — what each value means for your arm)
	minThresholdSpeed
		How fast your hand must move before a swipe/snatch counts.
		Higher = ignore slow waves and twitches; lower = easier to trigger with a light flick.

	maxThresholdSpeed
		Caps how hard a swipe feels for strength (0-1). Does not block detection.
		Higher = need a faster swing to reach full strength; lower = even moderate swings report as strong.

	directionThreshold
		How clearly the motion must favor one axis (left/right/up/down/pull-in) to pick that swipe type.
		Higher = stricter direction; lower = looser classification (more accidental directions).

	cooldownTime
		How long after a swipe before another can fire.
		Higher = fewer rapid repeats; lower = can chain swipes sooner.

	snapTurnYawThreshold
		Ignores hand motion when your view/yaw jumps this much (e.g. snap turn).
		Higher = tolerate bigger yaw jumps without canceling; lower = treat smaller turns as "not a swipe".
]]

local M = {}

M.Gesture =
{
	PUNCH = 0,
	HOLSTER = 1,
	RELOAD = 2,
	EARGRAB = 3,
	EAT = 4,
	GLASSESGRAB = 5,
	HATGRAB = 6,
	EARSCRATCH = 7,
	HEADSCRATCH = 8,
	LIPSCRATCH = 9,
	EYESCRATCH = 10,
	SWIPE_LEFT = 11,
	SWIPE_RIGHT = 12,
	SWIPE_UP = 13,
	SWIPE_DOWN = 14,
	SNATCH = 15,
	GRIP_COMPONENT = 16,
	CHESTGRAB = 17,
	BLOCK = 18,
}

local parametersFileName = "gesture_parameters"
local parameters = {
	punch = {
		minThresholdSpeed = 180,       -- min hand speed to count as a punch
		maxThresholdSpeed = 320,       -- speed that maps to full strength (0-1); not a gate
		forwardDotThreshold = 0.75,    -- how strongly motion must align with controller aim
		cooldownTime = 0.8,            -- seconds before another punch can fire
	},
	swipe = {
		minThresholdSpeed = 180,       -- min hand speed to count as a swipe/snatch
		maxThresholdSpeed = 320,       -- speed that maps to full strength (0-1); not a gate
		directionThreshold = 0.001,    -- how strongly motion must favor one swipe axis
		cooldownTime = 0.5,            -- seconds before another swipe can fire
		snapTurnYawThreshold = 45.0,   -- ignore motion if view yaw jumps more than this (deg)
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
	-- Sustained pose: arm raised in front, forearm across body, palm facing away.
	-- releaseSlack loosens all checks when leaving the pose (hysteresis).
	-- Defaults tuned from a live ideal left-hand block sample.
	block = {
		maxDropCm = 45.0,       -- hand may be this far below the head
		maxRaiseCm = 10.0,      -- hand may be this far above the head
		inFront = 0.75,        -- 0 = anywhere, 1 = straight ahead of head
		maxPointForward = 0.6,  -- how much the controller may aim at the view (lower = more across-body)
		maxTiltDeg = 58.0,      -- max controller pitch from horizontal (wrist tilt OK)
		palmFacing = 0.5,       -- palm-out = controller right · look (left); mirrored on right
		releaseSlack = 0.25,    -- 0 = snap off, 1 = very sticky release
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

local paramManager = paramModule.new(parametersFileName, parameters, true)
local gestureConfigDev = nil

local currentLogLevel = LogLevel.Error
-- Set while Dev Config Test is active; used to gate test-only input fallbacks.
local gestureTestId = nil
function M.setLogLevel(val)
	currentLogLevel = val
end
function M.print(text, logLevel)
	if logLevel == nil then logLevel = LogLevel.Debug end
	if logLevel <= currentLogLevel then
		uevrUtils.print("[gestures] " .. text, logLevel)
	end
end

local function getParameter(key)
	return paramManager:getFromActiveProfile(key)
end

local function setParameter(key, value, persist)
	return paramManager:setInActiveProfile(key, value, persist)
end

local function getNestedDefault(path)
	local cur = parameters
	for i = 1, #path do
		if cur == nil then return nil end
		cur = cur[path[i]]
	end
	return cur
end

local function getParam(path)
	local value = getParameter(path)
	if value == nil then
		return getNestedDefault(path)
	end
	return value
end

local holsterMinDownDot = math.sin(math.rad(math.abs(parameters.holster.triggerAngle)))

local autoDetect = {}
local hasPunchGesture = false
local punchStrengthPercent = 0
local hasSwipeLeft = false
local hasSwipeRight = false
local hasSwipeUp = false
local hasSwipeDown = false
local hasSnatch = false
local swipeStrengthPercent = 0

local function createPunchDetector()
	return {
		prevLocalPos = nil,
		cooldown = 0,
		minThresholdSpeed = parameters.punch.minThresholdSpeed,
		maxThresholdSpeed = parameters.punch.maxThresholdSpeed,
		forwardDotThreshold = parameters.punch.forwardDotThreshold,
		cooldownTime = parameters.punch.cooldownTime,
		currentPunchSpeed = 0.0
	}
end

-- Per-hand detectors (shared state mixes left/right motion when both are polled).
local punchDetectors = {
	[Handed.Left] = createPunchDetector(),
	[Handed.Right] = createPunchDetector(),
}

local swipeDetectors = {
	[Handed.Left] = {
		prevControllerPos = nil,
		prevPawnPos = nil,
		prevPawnRot = nil,
		cooldown = 0,
		minThresholdSpeed = parameters.swipe.minThresholdSpeed,
		maxThresholdSpeed = parameters.swipe.maxThresholdSpeed,
		directionThreshold = parameters.swipe.directionThreshold,
		cooldownTime = parameters.swipe.cooldownTime,
		peakMotionVector = nil,
		peakSpeed = 0
	},
	[Handed.Right] = {
		prevControllerPos = nil,
		prevPawnPos = nil,
		prevPawnRot = nil,
		cooldown = 0,
		minThresholdSpeed = parameters.swipe.minThresholdSpeed,
		maxThresholdSpeed = parameters.swipe.maxThresholdSpeed,
		directionThreshold = parameters.swipe.directionThreshold,
		cooldownTime = parameters.swipe.cooldownTime,
		peakMotionVector = nil,
		peakSpeed = 0
	}
}

local function applyDetectorParameters()
	local punchMin = getParam({"punch", "minThresholdSpeed"})
	local punchMax = getParam({"punch", "maxThresholdSpeed"})
	local punchFwd = getParam({"punch", "forwardDotThreshold"})
	local punchCooldown = getParam({"punch", "cooldownTime"})
	for _, detector in pairs(punchDetectors) do
		detector.minThresholdSpeed = punchMin
		detector.maxThresholdSpeed = punchMax
		detector.forwardDotThreshold = punchFwd
		detector.cooldownTime = punchCooldown
	end

	local swipeMin = getParam({"swipe", "minThresholdSpeed"})
	local swipeMax = getParam({"swipe", "maxThresholdSpeed"})
	local swipeDir = getParam({"swipe", "directionThreshold"})
	local swipeCooldown = getParam({"swipe", "cooldownTime"})
	for _, detector in pairs(swipeDetectors) do
		detector.minThresholdSpeed = swipeMin
		detector.maxThresholdSpeed = swipeMax
		detector.directionThreshold = swipeDir
		detector.cooldownTime = swipeCooldown
	end

	local holsterAngle = getParam({"holster", "triggerAngle"})
	---@diagnostic disable-next-line: param-type-mismatch
	holsterMinDownDot = math.sin(math.rad(math.abs(holsterAngle)))
end

local function saveParameter(key, value, persist, noCallbacks)
	setParameter(key, value, persist)
	applyDetectorParameters()
	if not (noCallbacks == true) then
		uevrUtils.executeUEVRCallbacks("on_gesture_config_param_change", key, value, persist)
	end
end

local createConfigMonitor = doOnce(function()
	uevrUtils.registerUEVRCallback("on_gesture_config_param_change", function(key, value, persist)
		saveParameter(key, value, persist, true)
	end)
end, Once.EVER)

local function rotationToForwardVector(rot)
	local pitchRad = math.rad(rot.Pitch)
	local yawRad = math.rad(rot.Yaw)
	return {
		X = math.cos(pitchRad) * math.cos(yawRad),
		Y = math.cos(pitchRad) * math.sin(yawRad),
		Z = math.sin(pitchRad)
	}
end

local function subtract(a, b)
	return { X = a.X - b.X, Y = a.Y - b.Y, Z = a.Z - b.Z }
end

local function magnitude(v)
	return math.sqrt(v.X*v.X + v.Y*v.Y + v.Z*v.Z)
end

local function normalize(v)
	local mag = magnitude(v)
	if mag == 0 then return {X=0, Y=0, Z=0} end
	return { X = v.X / mag, Y = v.Y / mag, Z = v.Z / mag }
end

local function dot(a, b)
	return a.X*b.X + a.Y*b.Y + a.Z*b.Z
end

-- Rotate a vector by negative yaw to get local space
local function rotateVectorInverseYaw(vec, yawDeg)
	local yawRad = -math.rad(yawDeg)
	local cosY = math.cos(yawRad)
	local sinY = math.sin(yawRad)
	return {
		X = vec.X * cosY - vec.Y * sinY,
		Y = vec.X * sinY + vec.Y * cosY,
		Z = vec.Z -- Z remains unchanged for yaw-only
	}
end

local function getLocalForwardVector(controllerRot, pawnRot)
	return rotationToForwardVector({
		Pitch = controllerRot.Pitch,
		Yaw = controllerRot.Yaw - pawnRot.Yaw,
		Roll = controllerRot.Roll
	})
end

-- Get controller position relative to pawn
local function getLocalControllerPos(controllerPos, pawnPos, pawnRot)
	local offset = subtract(controllerPos, pawnPos)
	return rotateVectorInverseYaw(offset, pawnRot.Yaw)
end

local function getSpeedPercent(speed, minThresholdSpeed, maxThresholdSpeed)
	if maxThresholdSpeed == minThresholdSpeed then
		return 0 -- avoid division by zero
	end
	local clampedSpeed = math.max(minThresholdSpeed, math.min(speed, maxThresholdSpeed))
	return (clampedSpeed - minThresholdSpeed) / (maxThresholdSpeed - minThresholdSpeed)
end

local function updatePunchDetector(self, controllerPos, controllerRot, pawnPos, pawnRot, deltaTime)
	if self.cooldown > 0 then
		self.cooldown = self.cooldown - deltaTime
		self.prevLocalPos = getLocalControllerPos(controllerPos, pawnPos, pawnRot)
		return false, 0, 0
	end

	if not self.prevLocalPos then
		self.prevLocalPos = getLocalControllerPos(controllerPos, pawnPos, pawnRot)
		return false, 0, 0
	end

	local localPos = getLocalControllerPos(controllerPos, pawnPos, pawnRot)

	local localDelta = subtract(localPos, self.prevLocalPos)
	local speed = magnitude(localDelta) / deltaTime
	local forward = getLocalForwardVector(controllerRot, pawnRot)
	local motionDir = normalize(localDelta)
	local forwardDot = dot(forward, motionDir)

	local isPunch = false
	local punchSpeed = 0
	local punchSpeedPercent = 0
	local punchDetected = speed > self.minThresholdSpeed and forwardDot > self.forwardDotThreshold
	if self.currentPunchSpeed > 0 or punchDetected then
		if speed > self.currentPunchSpeed then
			self.currentPunchSpeed = speed
		else
			isPunch = true
			punchSpeed = self.currentPunchSpeed
			punchSpeedPercent = getSpeedPercent(punchSpeed, self.minThresholdSpeed, self.maxThresholdSpeed)
			self.currentPunchSpeed = 0
		end
	end

	if isPunch then
		self.cooldown = self.cooldownTime
	end

	self.prevLocalPos = localPos

	return isPunch, punchSpeedPercent, punchSpeed
end

local function updateSwipeDetector(self, controllerPos, controllerRot, pawnPos, pawnRot, deltaTime)
	if self.cooldown > 0 then
		self.cooldown = self.cooldown - deltaTime
		self.prevControllerPos = controllerPos
		self.prevPawnPos = pawnPos
		return false, false, false, false, false, false, 0
	end

	if not self.prevControllerPos or not self.prevPawnPos or not self.prevPawnRot then
		self.prevControllerPos = controllerPos
		self.prevPawnPos = pawnPos
		self.prevPawnRot = pawnRot
		return false, false, false, false, false, false, 0
	end

	local controllerDelta = subtract(controllerPos, self.prevControllerPos)
	local pawnDelta = subtract(pawnPos, self.prevPawnPos)

	-- Skip detection if it looks like a snap turn (sudden large rotation)
	local snapTurnYawThreshold = getParam({"swipe", "snapTurnYawThreshold"})
	if math.abs(pawnRot.Yaw - self.prevPawnRot.Yaw) > snapTurnYawThreshold then
		self.prevControllerPos = controllerPos
		self.prevPawnPos = pawnPos
		self.prevPawnRot = pawnRot
		return false, false, false, false, false, false, 0
	end

	local localDelta = subtract(controllerDelta, pawnDelta)
	local speed = magnitude(localDelta) / deltaTime
	local motionDir = normalize(localDelta)

	local isSwipeLeft = false
	local isSwipeRight = false
	local isSwipeUp = false
	local isSwipeDown = false
	local isPunch = false
	local isSnatch = false

	local swipeSpeedPercent = 0

	-- Track peak motion during acceleration
	local swipeDetected = false
	if speed > self.minThresholdSpeed then
		if speed > self.peakSpeed then
			self.peakSpeed = speed
			self.peakMotionVector = motionDir
		end
		swipeDetected = true
	end

	-- Check if movement has peaked and is now slowing down
	if not swipeDetected and self.peakSpeed > 0 and self.peakMotionVector then
		local peakVector = self.peakMotionVector

		if peakVector and peakVector.Y < -self.directionThreshold then
			isSwipeLeft = true
		else
			isSwipeRight = true
		end

		if peakVector and peakVector.Z > self.directionThreshold then
			isSwipeUp = true
		else
			isSwipeDown = true
		end

		if peakVector and math.abs(peakVector.X) > self.directionThreshold then
			if peakVector.X > 0 then
				isPunch = true
			else
				isSnatch = true
			end
		end

		swipeSpeedPercent = getSpeedPercent(self.peakSpeed, self.minThresholdSpeed, self.maxThresholdSpeed)

		self.peakSpeed = 0
		self.peakMotionVector = nil
	end

	if isSwipeLeft or isSwipeRight or isSwipeUp or isSwipeDown or isPunch or isSnatch then
		self.cooldown = self.cooldownTime
	end

	self.prevControllerPos = controllerPos
	self.prevPawnPos = pawnPos
	self.prevPawnRot = pawnRot

	return isSwipeLeft, isSwipeRight, isSwipeUp, isSwipeDown, isPunch, isSnatch, swipeSpeedPercent
end

local holsterGripOn = false
local function detectHolster(state, hand, continuous)
	local gripButton = XINPUT_GAMEPAD_RIGHT_SHOULDER
	if hand == Handed.Left then
		gripButton = XINPUT_GAMEPAD_LEFT_SHOULDER
	end
	if (continuous == true or not holsterGripOn) and uevrUtils.isButtonPressed(state, gripButton) then
		holsterGripOn = true
		-- World-space forward·down is stable under yaw/roll; Euler Pitch alone is not.
		local forward = controllers.getControllerDirection(hand)
		if forward ~= nil and -forward.Z >= holsterMinDownDot then
			return true
		end
	elseif holsterGripOn and uevrUtils.isButtonNotPressed(state, gripButton)  then
		holsterGripOn = false
	end
	return false
end

local reloadGripOn = false
local function detectReload(state, hand, continuous)
	local gripButton = XINPUT_GAMEPAD_LEFT_SHOULDER
	if hand == Handed.Left then
		gripButton = XINPUT_GAMEPAD_RIGHT_SHOULDER
	end
	if (continuous == true or not reloadGripOn) and uevrUtils.isButtonPressed(state, gripButton) then
		reloadGripOn = true
		local gripLocation = controllers.getControllerLocation(1-hand)
		local targetLocation = controllers.getControllerLocation(hand)
		if gripLocation ~= nil and targetLocation ~= nil then
			local distance = magnitude(subtract(gripLocation, targetLocation))
			if distance < getParam({"reload", "triggerDistance"}) then
				return true
			end
		end
	elseif reloadGripOn and uevrUtils.isButtonNotPressed(state, gripButton) then
		reloadGripOn = false
	end
	return false
end

local blockActive = {
	[Handed.Left] = false,
	[Handed.Right] = false,
}
local blockCallbackActive = {
	[Handed.Left] = false,
	[Handed.Right] = false,
}
local chestCallbackActive = {
	[Handed.Left] = false,
	[Handed.Right] = false,
}
local faceCallbackActive = {
	[Handed.Left] = {},
	[Handed.Right] = {},
}
local faceGestureCallbackNames = {
	[M.Gesture.EARGRAB] = "on_gesture_eargrab",
	[M.Gesture.EAT] = "on_gesture_eat",
	[M.Gesture.GLASSESGRAB] = "on_gesture_glassesgrab",
	[M.Gesture.HATGRAB] = "on_gesture_hatgrab",
	[M.Gesture.EARSCRATCH] = "on_gesture_earscratch",
	[M.Gesture.HEADSCRATCH] = "on_gesture_headscratch",
	[M.Gesture.LIPSCRATCH] = "on_gesture_lipscratch",
	[M.Gesture.EYESCRATCH] = "on_gesture_eyescratch",
}

-- Continuous pose: arm raised in front, forearm across body, palm facing away.
local function detectBlock(hand)
	if hand == nil then hand = Handed.Right end

	local headLocation = controllers.getControllerLocation(2)
	local handLocation = controllers.getControllerLocation(hand)
	local headForward = controllers.getControllerDirection(2)
	local handForward = controllers.getControllerDirection(hand)
	local handRight = controllers.getControllerRightVector(hand)
	if headLocation == nil or handLocation == nil or headForward == nil or handForward == nil or handRight == nil then
		blockActive[hand] = false
		return false
	end

	local flatHeadForward = { X = headForward.X, Y = headForward.Y, Z = 0 }
	local flatMag = magnitude(flatHeadForward)
	if flatMag > 0.001 then
		flatHeadForward = { X = flatHeadForward.X / flatMag, Y = flatHeadForward.Y / flatMag, Z = 0 }
	else
		flatHeadForward = headForward
	end

	local maxDropCm = getParam({"block", "maxDropCm"})
	local maxRaiseCm = getParam({"block", "maxRaiseCm"})
	local inFront = getParam({"block", "inFront"})
	local maxPointForward = getParam({"block", "maxPointForward"})
	local maxTiltDeg = getParam({"block", "maxTiltDeg"})
	local palmFacing = getParam({"block", "palmFacing"})
	local slack = math.max(0, math.min(1, getParam({"block", "releaseSlack"}) or 0.25))

	local handOffsetZ = handLocation.Z - headLocation.Z
	local headToHand = normalize(subtract(handLocation, headLocation))
	local frontDot = dot(flatHeadForward, headToHand)
	local headRight = { X = -flatHeadForward.Y, Y = flatHeadForward.X, Z = 0 }
	local sideDot = math.abs(dot(headRight, headToHand))
	local aimDot = math.abs(dot(handForward, flatHeadForward))
	local verticalDot = math.abs(handForward.Z)
	-- Palm facing away: ideal left block has controller-right aligned with look.
	-- Right hand is mirrored (-right · look).
	local palmDot = dot(handRight, flatHeadForward)
	if hand == Handed.Right then
		palmDot = -palmDot
	end
	local maxVerticalDot = math.sin(math.rad(maxTiltDeg))
	-- Keep the hand from sitting out to the side (not exposed in UI; derived from inFront).
	local maxSide = math.sqrt(math.max(0.0, 1.0 - inFront * inFront))

	if not blockActive[hand] then
		if handOffsetZ > -maxDropCm
			and handOffsetZ < maxRaiseCm
			and frontDot > inFront
			and sideDot < maxSide
			and aimDot < maxPointForward
			and verticalDot < maxVerticalDot
			and palmDot > palmFacing then
			blockActive[hand] = true
			return true
		end
		return false
	end

	local heightSlack = 10.0 + slack * 30.0
	local dotSlack = 0.05 + slack * 0.35
	local tiltSlackDeg = 5.0 + slack * 20.0
	if handOffsetZ < -(maxDropCm + heightSlack)
		or handOffsetZ > maxRaiseCm + heightSlack
		or frontDot < inFront - dotSlack
		or sideDot > maxSide + dotSlack
		or aimDot > maxPointForward + dotSlack
		or verticalDot > math.sin(math.rad(maxTiltDeg + tiltSlackDeg))
		or palmDot < palmFacing - dotSlack then
		blockActive[hand] = false
		return false
	end
	return true
end

local bodyGripOn = false

local function isVrActionActive(actionPath, hand)
	local vr = uevr and uevr.params and uevr.params.vr
	if vr == nil or vr.get_action_handle == nil or vr.is_action_active == nil then
		return false
	end
	local handle = vr.get_action_handle(actionPath)
	if handle == nil then
		return false
	end

	local source = hand == Handed.Right
		and (vr.get_right_joystick_source and vr.get_right_joystick_source() or nil)
		or (vr.get_left_joystick_source and vr.get_left_joystick_source() or nil)

	-- OpenXR encodes Hand::LEFT as nullptr (Lua nil). Passing numeric 0 crashes;
	-- passing nil lets Sol convert to nullptr = LEFT.
	if source == nil and hand ~= Handed.Left then
		return false
	end

	local ok, active = pcall(function()
		return vr.is_action_active(handle, source)
	end)
	return ok and active == true
end

-- Prefer XInput. During Dev Config Test only, also read OpenXR actions so grip/trigger
-- still work while the UEVR UI has captured gamepad input.
local function getHandGripTrigger(state, hand, triggerThreshold)
	local isGripped, isTriggerred = false, false
	if state ~= nil and state.Gamepad ~= nil then
		if hand == Handed.Right then
			isGripped = uevrUtils.isButtonPressed(state, XINPUT_GAMEPAD_RIGHT_SHOULDER)
			isTriggerred = state.Gamepad.bRightTrigger > triggerThreshold
		else
			isGripped = uevrUtils.isButtonPressed(state, XINPUT_GAMEPAD_LEFT_SHOULDER)
			isTriggerred = state.Gamepad.bLeftTrigger > triggerThreshold
		end
	end

	if gestureTestId ~= nil then
		if not isGripped then
			isGripped = isVrActionActive("/actions/default/in/Grip", hand)
		end
		if not isTriggerred then
			isTriggerred = isVrActionActive("/actions/default/in/Trigger", hand)
		end
	end
	return isGripped, isTriggerred
end

local function detectBody(state, hand, continuous)
	local gripChest = false

	local triggerThreshold = getParam({"chest", "triggerThreshold"})
	local isGripped, isTriggerred = getHandGripTrigger(state, hand, triggerThreshold)

	if (continuous == true or not bodyGripOn) and (isGripped or isTriggerred) then
		bodyGripOn = true
		local headLocation = controllers.getControllerLocation(2)
		local handLocation = controllers.getControllerLocation(hand)
		if headLocation ~= nil and handLocation ~= nil then
			local headForward = controllers.getControllerDirection(2)
			if headForward ~= nil then
				local chestOffsetForward = getParam({"chest", "offsetForward"})
				local chestOffsetZ = getParam({"chest", "offsetZ"})
				local chestLocation = {
					X = headLocation.X + headForward.X * chestOffsetForward,
					Y = headLocation.Y + headForward.Y * chestOffsetForward,
					Z = headLocation.Z + chestOffsetZ
				}
				local distance = magnitude(subtract(handLocation, chestLocation))
				if distance < getParam({"chest", "triggerDistance"}) then
					gripChest = isGripped
				end
			end
		end
	elseif bodyGripOn and not (isGripped or isTriggerred) then
		bodyGripOn = false
	end
	return gripChest
end

local headGripOn = false
local function detectFace(state, hand, continuous)
	local gripMouth, gripEyes, gripHead, gripEar = false, false, false, false
	local triggerMouth, triggerEyes, triggerHead, triggerEar = false, false, false, false

	local triggerThreshold = getParam({"face", "triggerThreshold"})
	local isGripped, isTriggerred = getHandGripTrigger(state, hand, triggerThreshold)

	if (continuous == true or not headGripOn) and (isGripped or isTriggerred)  then
		headGripOn = true
		local headLocation = controllers.getControllerLocation(2)
		local handLocation = controllers.getControllerLocation(hand)
		if headLocation ~= nil and handLocation ~= nil then
			local headForwardVector = controllers.getControllerDirection(2)
			local headToHandForwardVector = normalize(subtract(handLocation, headLocation))
			local forwardDot = dot(headForwardVector, headToHandForwardVector)
			local distance = magnitude(subtract(handLocation, headLocation))

			local mouthTriggerDistance = getParam({"face", "mouth", "triggerDistance"})
			local mouthForwardDotMinThreshold = getParam({"face", "mouth", "forwardDotMinThreshold"})
			local mouthForwardDotMaxThreshold = getParam({"face", "mouth", "forwardDotMaxThreshold"})
			local headTriggerDistance = getParam({"face", "head", "triggerDistance"})
			local headForwardDotMinThreshold = getParam({"face", "head", "forwardDotMinThreshold"})
			local headForwardDotMaxThreshold = getParam({"face", "head", "forwardDotMaxThreshold"})
			local eyesTriggerDistance = getParam({"face", "eyes", "triggerDistance"})
			local eyesForwardDotThreshold = getParam({"face", "eyes", "forwardDotThreshold"})
			local earGripTriggerDistance = getParam({"face", "ear", "triggerDistance"})
			local earGripForwardDotThreshold = getParam({"face", "ear", "forwardDotThreshold"})

			if distance < mouthTriggerDistance and forwardDot > mouthForwardDotMinThreshold and forwardDot < mouthForwardDotMaxThreshold and headLocation.Z-handLocation.Z > 0 then
				gripMouth = isGripped
				triggerMouth = isTriggerred
			elseif distance < headTriggerDistance and forwardDot > headForwardDotMinThreshold and forwardDot < headForwardDotMaxThreshold and headLocation.Z-handLocation.Z < 0 then
				gripHead = isGripped
				triggerHead = isTriggerred
			elseif distance < eyesTriggerDistance and forwardDot > eyesForwardDotThreshold then
				gripEyes = isGripped
				triggerEyes = isTriggerred
			end

			local headRightVector = controllers.getControllerRightVector(2)
			forwardDot = dot(headRightVector, headToHandForwardVector) * (hand == Handed.Left and -1 or 1)
			if distance < earGripTriggerDistance and forwardDot > earGripForwardDotThreshold then
				gripEar = isGripped
				triggerEar = isTriggerred
			end

		end
	elseif headGripOn and not (isGripped or isTriggerred) then
		headGripOn = false
	end
	return gripMouth, gripEyes, gripHead, gripEar, triggerMouth, triggerEyes, triggerHead, triggerEar
end

function M.getGesture(id)
	if id == M.Gesture.PUNCH then
		 return hasPunchGesture, punchStrengthPercent
	elseif id == M.Gesture.SWIPE_LEFT then
		return hasSwipeLeft, swipeStrengthPercent
	elseif id == M.Gesture.SWIPE_RIGHT then
		return hasSwipeRight, swipeStrengthPercent
	elseif id == M.Gesture.SWIPE_UP then
		return hasSwipeUp, swipeStrengthPercent
	elseif id == M.Gesture.SWIPE_DOWN then
		return hasSwipeDown, swipeStrengthPercent
	elseif id == M.Gesture.SNATCH then
		return hasSnatch, swipeStrengthPercent
	end
end

function M.detectGesture(id, deltaTime, hand, currentPos, currentRot, pawnPos, pawnRot )
	if hand == nil then hand = Handed.Right end
	if id == M.Gesture.BLOCK then
		return detectBlock(hand)
	end
	if currentPos == nil then
		currentPos = controllers.getControllerLocation(hand)
	end
	if currentRot == nil then
		currentRot = controllers.getControllerRotation(hand)
	end
	if pawnPos == nil then
		pawnPos = controllers.getControllerLocation(2)
	end
	if pawnRot == nil then
		pawnRot = controllers.getControllerRotation(2)
	end
	if currentPos == nil or currentRot == nil or pawnPos == nil or pawnRot == nil then
		M.print("Call to detectGesture() failed because controller was invalid")
		return false
	else
		if id == M.Gesture.PUNCH then
			 hasPunchGesture, punchStrengthPercent = updatePunchDetector(punchDetectors[hand], currentPos, currentRot, pawnPos, pawnRot, deltaTime)
			 return hasPunchGesture, punchStrengthPercent
		elseif id == M.Gesture.SWIPE_LEFT or id == M.Gesture.SWIPE_RIGHT or id == M.Gesture.SWIPE_UP or
		       id == M.Gesture.SWIPE_DOWN or id == M.Gesture.SNATCH then
			hasSwipeLeft, hasSwipeRight, hasSwipeUp, hasSwipeDown, _, hasSnatch, swipeStrengthPercent = updateSwipeDetector(swipeDetectors[hand], currentPos, currentRot, pawnPos, pawnRot, deltaTime)
			if id == M.Gesture.SWIPE_LEFT then
				return hasSwipeLeft, swipeStrengthPercent
			elseif id == M.Gesture.SWIPE_RIGHT then
				return hasSwipeRight, swipeStrengthPercent
			elseif id == M.Gesture.SWIPE_UP then
				return hasSwipeUp, swipeStrengthPercent
			elseif id == M.Gesture.SWIPE_DOWN then
				return hasSwipeDown, swipeStrengthPercent
			elseif id == M.Gesture.SNATCH then
				return hasSnatch, swipeStrengthPercent
			end
		end
	end
	return false
end

function M.detectGestureWithState(id, state, hand, continuous)
	if id == M.Gesture.HOLSTER then
		return detectHolster(state, hand, continuous)
	elseif id == M.Gesture.RELOAD then
		return detectReload(state, hand, continuous)
	elseif id == M.Gesture.CHESTGRAB then
		local gripChest = detectBody(state, hand, continuous)
		return gripChest
	elseif id == M.Gesture.EAT then
		local gripMouth, gripEyes, gripHead, gripEar, triggerMouth, triggerEyes, triggerHead, triggerEar = detectFace(state, hand, continuous)
		return gripMouth
	elseif id == M.Gesture.GLASSESGRAB then
		local gripMouth, gripEyes, gripHead, gripEar, triggerMouth, triggerEyes, triggerHead, triggerEar = detectFace(state, hand, continuous)
		return gripEyes
	elseif id == M.Gesture.HATGRAB then
		local gripMouth, gripEyes, gripHead, gripEar, triggerMouth, triggerEyes, triggerHead, triggerEar = detectFace(state, hand, continuous)
		return gripHead
	elseif id == M.Gesture.EARGRAB then
		local gripMouth, gripEyes, gripHead, gripEar, triggerMouth, triggerEyes, triggerHead, triggerEar = detectFace(state, hand, continuous)
		return gripEar
	elseif id == M.Gesture.LIPSCRATCH then
		local gripMouth, gripEyes, gripHead, gripEar, triggerMouth, triggerEyes, triggerHead, triggerEar = detectFace(state, hand, continuous)
		return triggerMouth
	elseif id == M.Gesture.EYESCRATCH then
		local gripMouth, gripEyes, gripHead, gripEar, triggerMouth, triggerEyes, triggerHead, triggerEar = detectFace(state, hand, continuous)
		return triggerEyes
	elseif id == M.Gesture.HEADSCRATCH then
		local gripMouth, gripEyes, gripHead, gripEar, triggerMouth, triggerEyes, triggerHead, triggerEar = detectFace(state, hand, continuous)
		return triggerHead
	elseif id == M.Gesture.EARSCRATCH then
		local gripMouth, gripEyes, gripHead, gripEar, triggerMouth, triggerEyes, triggerHead, triggerEar = detectFace(state, hand, continuous)
		return triggerEar
	elseif id == M.Gesture.BLOCK then
		return detectBlock(hand)
	end
end

function M.detectComponentGrab(state, hand, component, maxDistance)
	if component ~= nil then
		if uevrUtils.isButtonPressed(state, hand == Handed.Left and XINPUT_GAMEPAD_LEFT_SHOULDER or XINPUT_GAMEPAD_RIGHT_SHOULDER) then
			local distance = controllers.getDistanceFromController(hand, component)
			if distance ~= nil and distance < (maxDistance or getParam({"componentGrab", "maxDistance"})) then
				return true, distance
			end
		end
	end
	return false, nil
end

function M.getHeadGestures(state, hand, continuous)
	return detectFace(state, hand, continuous)
end

function M.getBodyGestures(state, hand, continuous)
	return detectBody(state, hand, continuous)
end

function M.getSwipeGestures(deltaTime, hand, currentPos, currentRot, pawnPos, pawnRot)
	if hand == nil then hand = Handed.Right end
	if currentPos == nil then
		currentPos = controllers.getControllerLocation(hand)
	end
	if currentRot == nil then
		currentRot = controllers.getControllerRotation(hand)
	end
	if pawnPos == nil then
		pawnPos = controllers.getControllerLocation(2)
	end
	if pawnRot == nil then
		pawnRot = controllers.getControllerRotation(2)
	end
	if currentPos == nil or currentRot == nil or pawnPos == nil or pawnRot == nil then
		return false, false, false, false, false, false, 0
	else
		return updateSwipeDetector(swipeDetectors[hand], currentPos, currentRot, pawnPos, pawnRot, deltaTime)
	end
end

function M.autoDetectGesture(id, val, hand)
	if val == nil then val = true end
	if hand == nil then hand = Handed.Right end
	if autoDetect[id] == nil then
		autoDetect[id] = {}
	end
	autoDetect[id][hand] = val
end

-- Dev config "Test" mode: when set, that gesture is treated as autodetect for both hands.
local swipeTestGestureIds = {
	[M.Gesture.SWIPE_LEFT] = true,
	[M.Gesture.SWIPE_RIGHT] = true,
	[M.Gesture.SWIPE_UP] = true,
	[M.Gesture.SWIPE_DOWN] = true,
	[M.Gesture.SNATCH] = true,
}
local faceTestGestureIds = {
	[M.Gesture.EARGRAB] = true,
	[M.Gesture.EAT] = true,
	[M.Gesture.GLASSESGRAB] = true,
	[M.Gesture.HATGRAB] = true,
	[M.Gesture.EARSCRATCH] = true,
	[M.Gesture.HEADSCRATCH] = true,
	[M.Gesture.LIPSCRATCH] = true,
	[M.Gesture.EYESCRATCH] = true,
}

uevrUtils.registerUEVRCallback("on_gesture_test", function(gestureId)
	if gestureId == nil or gestureId == false then
		gestureTestId = nil
	else
		gestureTestId = gestureId
	end
end)

local function hasAutodetect(id, hand)
	if gestureTestId ~= nil then
		if gestureTestId == id then
			return true
		end
		-- Testing any swipe/snatch id enables the whole swipe detector family.
		if swipeTestGestureIds[gestureTestId] and swipeTestGestureIds[id] then
			return true
		end
		-- Testing any face id enables the whole face detector family.
		if faceTestGestureIds[gestureTestId] and faceTestGestureIds[id] then
			return true
		end
	end
	if autoDetect[id] ~= nil then
		return autoDetect[id][hand] == true
	end
	return false
end

local function hasAnyFaceAutodetect(hand)
	for id, _ in pairs(faceTestGestureIds) do
		if hasAutodetect(id, hand) then
			return true
		end
	end
	return false
end

local function updateChestAutodetect(state, hand)
	local active = detectBody(state, hand, true) == true
	if active ~= chestCallbackActive[hand] then
		chestCallbackActive[hand] = active
		uevrUtils.executeUEVRCallbacks("on_gesture_chestgrab", active, hand)
	end
end

local function updateFaceAutodetect(state, hand)
	local gripMouth, gripEyes, gripHead, gripEar, triggerMouth, triggerEyes, triggerHead, triggerEar = detectFace(state, hand, true)
	local results = {
		[M.Gesture.EAT] = gripMouth == true,
		[M.Gesture.GLASSESGRAB] = gripEyes == true,
		[M.Gesture.HATGRAB] = gripHead == true,
		[M.Gesture.EARGRAB] = gripEar == true,
		[M.Gesture.LIPSCRATCH] = triggerMouth == true,
		[M.Gesture.EYESCRATCH] = triggerEyes == true,
		[M.Gesture.HEADSCRATCH] = triggerHead == true,
		[M.Gesture.EARSCRATCH] = triggerEar == true,
	}
	local prev = faceCallbackActive[hand]
	for id, active in pairs(results) do
		if active ~= (prev[id] == true) then
			prev[id] = active
			uevrUtils.executeUEVRCallbacks(faceGestureCallbackNames[id], active, hand)
		end
	end
end

uevrUtils.registerOnPreInputGetStateCallback(function(retval, user_index, state)
	if hasAutodetect(M.Gesture.CHESTGRAB, Handed.Right) then
		updateChestAutodetect(state, Handed.Right)
	end
	if hasAutodetect(M.Gesture.CHESTGRAB, Handed.Left) then
		updateChestAutodetect(state, Handed.Left)
	end
	if hasAnyFaceAutodetect(Handed.Right) then
		updateFaceAutodetect(state, Handed.Right)
	end
	if hasAnyFaceAutodetect(Handed.Left) then
		updateFaceAutodetect(state, Handed.Left)
	end
end)

uevr.sdk.callbacks.on_pre_engine_tick(function(engine, delta)
	if hasAutodetect(M.Gesture.PUNCH, Handed.Right) then
		local isPunch, strength = M.detectGesture(M.Gesture.PUNCH, delta, Handed.Right)
		if isPunch then
			uevrUtils.executeUEVRCallbacks("on_gesture_punch", strength, Handed.Right)
		end
	end
	if hasAutodetect(M.Gesture.PUNCH, Handed.Left) then
		local isPunch, strength = M.detectGesture(M.Gesture.PUNCH, delta, Handed.Left)
		if isPunch then
			uevrUtils.executeUEVRCallbacks("on_gesture_punch", strength, Handed.Left)
		end
	end
	if hasAutodetect(M.Gesture.SWIPE_LEFT, Handed.Right) or hasAutodetect(M.Gesture.SWIPE_RIGHT, Handed.Right) or hasAutodetect(M.Gesture.SWIPE_UP, Handed.Right) or hasAutodetect(M.Gesture.SWIPE_DOWN, Handed.Right) or hasAutodetect(M.Gesture.SNATCH, Handed.Right) then
		local left, right, up, down, punch, snatch, strength = M.getSwipeGestures(delta, Handed.Right)

		if left then uevrUtils.executeUEVRCallbacks("on_gesture_swipe_left", strength, Handed.Right) end
		if right then uevrUtils.executeUEVRCallbacks("on_gesture_swipe_right", strength, Handed.Right) end
		if up then uevrUtils.executeUEVRCallbacks("on_gesture_swipe_up", strength, Handed.Right) end
		if down then uevrUtils.executeUEVRCallbacks("on_gesture_swipe_down", strength, Handed.Right) end
		if snatch then uevrUtils.executeUEVRCallbacks("on_gesture_snatch", strength, Handed.Right) end
	end
	if hasAutodetect(M.Gesture.SWIPE_LEFT, Handed.Left) or hasAutodetect(M.Gesture.SWIPE_RIGHT, Handed.Left) or hasAutodetect(M.Gesture.SWIPE_UP, Handed.Left) or hasAutodetect(M.Gesture.SWIPE_DOWN, Handed.Left) or hasAutodetect(M.Gesture.SNATCH, Handed.Left) then
		local left, right, up, down, punch, snatch, strength = M.getSwipeGestures(delta, Handed.Left)

		if left then uevrUtils.executeUEVRCallbacks("on_gesture_swipe_left", strength, Handed.Left) end
		if right then uevrUtils.executeUEVRCallbacks("on_gesture_swipe_right", strength, Handed.Left) end
		if up then uevrUtils.executeUEVRCallbacks("on_gesture_swipe_up", strength, Handed.Left) end
		if down then uevrUtils.executeUEVRCallbacks("on_gesture_swipe_down", strength, Handed.Left) end
		if snatch then uevrUtils.executeUEVRCallbacks("on_gesture_snatch", strength, Handed.Left) end
	end
	if hasAutodetect(M.Gesture.BLOCK, Handed.Right) then
		local active = detectBlock(Handed.Right)
		if active ~= blockCallbackActive[Handed.Right] then
			blockCallbackActive[Handed.Right] = active
			uevrUtils.executeUEVRCallbacks("on_gesture_block", active, Handed.Right)
		end
	end
	if hasAutodetect(M.Gesture.BLOCK, Handed.Left) then
		local active = detectBlock(Handed.Left)
		if active ~= blockCallbackActive[Handed.Left] then
			blockCallbackActive[Handed.Left] = active
			uevrUtils.executeUEVRCallbacks("on_gesture_block", active, Handed.Left)
		end
	end
end)

local function registerGestureDetection(id, rightHand, leftHand)
	if rightHand == nil and leftHand == nil then
		M.autoDetectGesture(id, true, Handed.Right)
	else
		if rightHand == true then
			M.autoDetectGesture(id, true, Handed.Right)
		end
		if leftHand == true then
			M.autoDetectGesture(id, true, Handed.Left)
		end
	end
end
function M.registerSwipeLeftCallback(callback, rightHand, leftHand)
	registerGestureDetection(M.Gesture.SWIPE_LEFT, rightHand, leftHand)
	uevrUtils.registerUEVRCallback("on_gesture_swipe_left", callback)
end
function M.registerSwipeRightCallback(callback, rightHand, leftHand)
	registerGestureDetection(M.Gesture.SWIPE_RIGHT, rightHand, leftHand)
	uevrUtils.registerUEVRCallback("on_gesture_swipe_right", callback)
end
function M.registerSwipeUpCallback(callback, rightHand, leftHand)
	registerGestureDetection(M.Gesture.SWIPE_UP, rightHand, leftHand)
	uevrUtils.registerUEVRCallback("on_gesture_swipe_up", callback)
end
function M.registerSwipeDownCallback(callback, rightHand, leftHand)
	registerGestureDetection(M.Gesture.SWIPE_DOWN, rightHand, leftHand)
	uevrUtils.registerUEVRCallback("on_gesture_swipe_down", callback)
end
function M.registerBlockCallback(callback, rightHand, leftHand)
	registerGestureDetection(M.Gesture.BLOCK, rightHand, leftHand)
	uevrUtils.registerUEVRCallback("on_gesture_block", callback)
end

function M.init(isDeveloperMode, logLevel)
	paramManager:load(true)
	applyDetectorParameters()

	if logLevel ~= nil then
		M.setLogLevel(logLevel)
	end
	if isDeveloperMode == nil and uevrUtils.getDeveloperMode() ~= nil then
		isDeveloperMode = uevrUtils.getDeveloperMode()
	end

	if isDeveloperMode then
		gestureConfigDev = require("libs/config/gesture_config_dev")
		gestureConfigDev.init(paramManager)
		createConfigMonitor()
	end
end

return M

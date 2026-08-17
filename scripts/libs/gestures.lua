local uevrUtils = require("libs/uevr_utils")
local controllers = require("libs/controllers")
local paramModule = require("libs/core/params")

--[[
Usage
	local gestures = require("libs/gestures")
	gestures.init()
	In developer mode, gestures.init(true) also loads the in-game gesture configuration tool.
	Parameters are stored in gesture_parameters.json (profiles supported).
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
}

local parametersFileName = "gesture_parameters"
local parameters = {
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

local paramManager = paramModule.new(parametersFileName, parameters, true)
local gestureConfigDev = nil

local currentLogLevel = LogLevel.Error
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

local punchDetector = {
	prevLocalPos = nil,
	cooldown = 0,
	minThresholdSpeed = parameters.punch.minThresholdSpeed,
	maxThresholdSpeed = parameters.punch.maxThresholdSpeed,
	forwardDotThreshold = parameters.punch.forwardDotThreshold,
	cooldownTime = parameters.punch.cooldownTime,
	currentPunchSpeed = 0.0
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
	punchDetector.minThresholdSpeed = getParam({"punch", "minThresholdSpeed"})
	punchDetector.maxThresholdSpeed = getParam({"punch", "maxThresholdSpeed"})
	punchDetector.forwardDotThreshold = getParam({"punch", "forwardDotThreshold"})
	punchDetector.cooldownTime = getParam({"punch", "cooldownTime"})

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

function punchDetector:update(controllerPos, controllerRot, pawnPos, pawnRot, deltaTime)
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

local bodyGripOn = false
local function detectBody(state, hand, continuous)
	local gripChest = false

	local isGripped, isTriggerred = false, false
	local triggerThreshold = getParam({"chest", "triggerThreshold"})
	if hand == Handed.Right then
		isGripped = uevrUtils.isButtonPressed(state, XINPUT_GAMEPAD_RIGHT_SHOULDER)
		isTriggerred = state.Gamepad.bRightTrigger > triggerThreshold
	else
		isGripped = uevrUtils.isButtonPressed(state, XINPUT_GAMEPAD_LEFT_SHOULDER)
		isTriggerred = state.Gamepad.bLeftTrigger > triggerThreshold
	end

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

	local isGripped, isTriggerred = false, false
	local triggerThreshold = getParam({"face", "triggerThreshold"})
	if hand == Handed.Right then
		isGripped = uevrUtils.isButtonPressed(state, XINPUT_GAMEPAD_RIGHT_SHOULDER)
		isTriggerred = state.Gamepad.bRightTrigger > triggerThreshold
	else
		isGripped = uevrUtils.isButtonPressed(state, XINPUT_GAMEPAD_LEFT_SHOULDER)
		isTriggerred = state.Gamepad.bLeftTrigger > triggerThreshold
	end

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
			 hasPunchGesture, punchStrengthPercent = punchDetector:update(currentPos, currentRot, pawnPos, pawnRot, deltaTime)
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

local function hasAutodetect(id, hand)
	if autoDetect[id] ~= nil then
		return autoDetect[id][hand] == true
	end
	return false
end

uevr.sdk.callbacks.on_pre_engine_tick(function(engine, delta)
	if hasAutodetect(M.Gesture.PUNCH, Handed.Right) then
		M.detectGesture(M.Gesture.PUNCH, delta, Handed.Right)
	end
	if hasAutodetect(M.Gesture.PUNCH, Handed.Left) then
		M.detectGesture(M.Gesture.PUNCH, delta, Handed.Left)
	end
	if hasAutodetect(M.Gesture.SWIPE_LEFT, Handed.Right) or hasAutodetect(M.Gesture.SWIPE_RIGHT, Handed.Right) or hasAutodetect(M.Gesture.SWIPE_UP, Handed.Right) or hasAutodetect(M.Gesture.SWIPE_DOWN, Handed.Right) or hasAutodetect(M.Gesture.SNATCH, Handed.Right) then
		local left, right, up, down, punch, snatch, strength = M.getSwipeGestures(delta, Handed.Right)

		if left then uevrUtils.executeUEVRCallbacks("on_gesture_swipe_left", strength, Handed.Right) end
		if right then uevrUtils.executeUEVRCallbacks("on_gesture_swipe_right", strength, Handed.Right) end
		if up then uevrUtils.executeUEVRCallbacks("on_gesture_swipe_up", strength, Handed.Right) end
		if down then uevrUtils.executeUEVRCallbacks("on_gesture_swipe_down", strength, Handed.Right) end
	end
	if hasAutodetect(M.Gesture.SWIPE_LEFT, Handed.Left) or hasAutodetect(M.Gesture.SWIPE_RIGHT, Handed.Left) or hasAutodetect(M.Gesture.SWIPE_UP, Handed.Left) or hasAutodetect(M.Gesture.SWIPE_DOWN, Handed.Left) or hasAutodetect(M.Gesture.SNATCH, Handed.Left) then
		local left, right, up, down, punch, snatch, strength = M.getSwipeGestures(delta, Handed.Left)

		if left then uevrUtils.executeUEVRCallbacks("on_gesture_swipe_left", strength, Handed.Left) end
		if right then uevrUtils.executeUEVRCallbacks("on_gesture_swipe_right", strength, Handed.Left) end
		if up then uevrUtils.executeUEVRCallbacks("on_gesture_swipe_up", strength, Handed.Left) end
		if down then uevrUtils.executeUEVRCallbacks("on_gesture_swipe_down", strength, Handed.Left) end
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

-- Aiming and Direction control for Unreal Engine VR mods 
-- Decoupled Yaw code courtesy of Pande4360

--[[
Usage
	Drop the lib folder containing this file into your project folder
	To use input/body rotation for a game, add code like this in your script:
		local uevrUtils = require('libs/uevr_utils')
		local input = require('libs/input')
		input.init()
	In developer mode, input.init(true) also loads the in-game input configuration tool.
	Parameters are stored in input_parameters.json (profiles supported).

	This module drives decoupled-yaw body facing, pawn roomscale follow, aim-method
	control rotation, snap/smooth turn, VR camera root offsets, body-mesh relative
	placement, and spatial-audio listener attachment. Designed to work with UEVR
	decoupled pitch enabled (set automatically on load).

	Enums (from libs/enums/input):
		input.AimMethod - UEVR, HEAD, RIGHT_CONTROLLER, LEFT_CONTROLLER, RIGHT_WEAPON, LEFT_WEAPON
		input.PawnRotationMode - NONE, RIGHT_CONTROLLER, LEFT_CONTROLLER, LOCKED, SIMPLE, ADVANCED
		input.PawnPositionMode - NONE, FOLLOWS, ANIMATED

	Available functions:

	input.init((optional)isDeveloperMode, (optional)logLevel) - initializes the input module.
		Loads parameters. If isDeveloperMode is omitted, uses uevrUtils.getDeveloperMode().
		In developer mode the input_config_dev UI is loaded for live parameter editing.
		example:
			input.init()
			input.init(true, LogLevel.Debug)

	input.setLogLevel(val) - sets the logging level for input system messages
		example:
			input.setLogLevel(LogLevel.Debug)

	input.print(text, (optional)logLevel) - prints a message at the given (or Error) log level
		example:
			input.print("Hello", LogLevel.Debug)

	input.setDisabled(val) - overrides enable/disable for the whole input body/aim system.
		When disabled (true), clears decoupledYaw/bodyRotationOffset so re-enable re-inits facing.
		example:
			input.setDisabled(true)

	input.isDisabled() - returns true if the override or internal disabled flag is set
		example:
			if input.isDisabled() then return end

	input.registerIsDisabledCallback(func) - registers a priority boolean callback for
		"is_input_disabled". Return true to force input disabled for that frame.
		example:
			input.registerIsDisabledCallback(function()
				return status.inCinematic == true
			end)

	input.reset() - resets runtime state (yaw, meshes, camera, pawn settings) without wiping params
		example:
			input.reset()

	input.resetView() - clears decoupledYaw / bodyRotationOffset / timing (used on recenter)
		example:
			input.resetView()

	input.resetCapsuleComponent() - resets yaw state and zeroes RootComponent / actor rotation
		example:
			input.resetCapsuleComponent()

	input.setAimMethod(val) - persists aim method (input.AimMethod.*)
		example:
			input.setAimMethod(input.AimMethod.RIGHT_CONTROLLER)

	input.setOverrideAimMethod(val) - temporary aim-method override (nil clears to saved param)
		example:
			input.setOverrideAimMethod(input.AimMethod.HEAD)
			input.setOverrideAimMethod(nil)

	input.setAimCameraOverride(val) - temporary aim-camera descriptor override
		example:
			input.setAimCameraOverride("Pawn.Camera")

	input.setAimRotationOffset(offset) - sets runtime aim rotation offset (rotator-like table)
		example:
			input.setAimRotationOffset(uevrUtils.rotator(0, 5, 0))

	input.getAimRotationOffset() - returns the current aim rotation offset
		example:
			local offset = input.getAimRotationOffset()

	input.getAimOffsetAdjustedRotation(rotation) - returns rotation composed with aimRotationOffset
		(also used for gunstock adjustments when aim method is a controller)
		example:
			local adjusted = input.getAimOffsetAdjustedRotation(controllers.getControllerRotation(1))

	input.setWeaponRotation(leftRotation, rightRotation) - sets weapon aim rotators for
		LEFT_WEAPON / RIGHT_WEAPON aim methods (usually from attachment grip callbacks)
		example:
			input.setWeaponRotation(leftRot, rightRot)

	input.setPawnRotationMode(val) - persists body yaw mode (input.PawnRotationMode.*)
		example:
			input.setPawnRotationMode(input.PawnRotationMode.LOCKED)

	input.getPawnRotationMode() - returns the saved pawnRotationMode param (ignores overrides)
		example:
			local mode = input.getPawnRotationMode()

	input.getEffectivePawnRotationMode() - returns override if set, else saved pawnRotationMode.
		Use this when reacting to live body-yaw behavior. ik.lua uses this
		example:
			local mode = input.getEffectivePawnRotationMode()

	input.setOverridePawnRotationMode(val) - temporary body yaw mode override (nil clears).
		Does not change the saved profile value.
		example:
			input.setOverridePawnRotationMode(input.PawnRotationMode.RIGHT_CONTROLLER)
			input.setOverridePawnRotationMode(nil)

	input.setForcedBodyYaw(worldYawOrNil) - hold RootComponent to absolute world yaw
		(degrees). Nil releases. Does not change setRotationModeRotationDisabled or camera offsets.
		example:
			input.setForcedBodyYaw(root:K2_GetComponentRotation().Yaw)
			input.setForcedBodyYaw(nil)

	input.getForcedBodyYaw() - returns the current forced world yaw, or nil
		example:
			local yaw = input.getForcedBodyYaw()

	input.setBodyYawWritesSuppressed(val) - when true, stops writing RootComponent yaw
		so the game can own orientation; syncs bodyRotationOffset from root and mirrors large /
		any meaningful root yaw deltas into decoupledYaw (e.g. ladder top-mount 180°) so the VR
		view stays facing with the pawn. Does not change setRotationModeRotationDisabled.
		example:
			input.setBodyYawWritesSuppressed(true)
			input.setBodyYawWritesSuppressed(false)

	input.getBodyYawWritesSuppressed() - returns whether body yaw root writes are suppressed
		example:
			if input.getBodyYawWritesSuppressed() then ... end

	input.setRotationModeRotationDisabled(val) - when true, skips applying VR camera rotation
		offsets and snap-turn root writes for pawn rotation mode (parameter
		pawnRotationModeDisableRotation also gates this)
		example:
			input.setRotationModeRotationDisabled(true)

	input.setPlayerControllerRotationFollowsBody(followsBody) - when true (default, legacy),
		ControlRotation follows body yaw (decoupledYaw + bodyRotationOffset); when false,
		ControlRotation follows the current aim method (needed for e.g. Atomic Heart pickups)
		example:
			input.setPlayerControllerRotationFollowsBody(false)

	input.getRotationOffset() - returns decoupledYaw + bodyRotationOffset (0 if unavailable)
		example:
			local yaw = input.getRotationOffset()

	input.setPawnPositionMode(val) - persists roomscale follow mode (input.PawnPositionMode.*)
		example:
			input.setPawnPositionMode(input.PawnPositionMode.FOLLOWS)

	input.setPawnPositionAnimationScale(val) - movement-input scale when position mode is ANIMATED
		example:
			input.setPawnPositionAnimationScale(0.2)

	input.setPawnPositionSweepMovement(val) - whether FOLLOWS uses sweep on K2_AddWorldOffset
		example:
			input.setPawnPositionSweepMovement(true)

	input.setUseSnapTurn(val) - enables snap turn (else smooth turn)
		example:
			input.setUseSnapTurn(true)

	input.setSnapAngle(val) - snap turn angle in degrees
		example:
			input.setSnapAngle(45)

	input.setSmoothTurnSpeed(val) - smooth turn rate parameter
		example:
			input.setSmoothTurnSpeed(50)

	input.setOptimizeBodyYawCalculations(val) - when true (default), body yaw stereo updates
		prefer a single eye; set false if eyes desync or IK jitters on snap/fast head turns
		example:
			input.setOptimizeBodyYawCalculations(false)

	input.setHeadOffset(val) - persists headOffset vector (mesh relative XY / camera Z usage)
		example:
			input.setHeadOffset({X=0, Y=0, Z=0})

	input.getHeadOffset() - returns configured headOffset, or zero vector if input is disabled
		example:
			local offset = input.getHeadOffset()

	input.setRootOffset(val) - persists rootOffset for VR camera position alignment
		example:
			input.setRootOffset({X=0, Y=0, Z=0})

	input.setAdjustForAnimation(val) - enables neck/mesh correction from head/root bones during anim
		example:
			input.setAdjustForAnimation(true)

	input.setAdjustForEyeOffset(val) - enables eye-bone based mesh offset correction
		example:
			input.setAdjustForEyeOffset(true)

	input.setEyeOffset(val) - persists eyeOffset numeric param
		example:
			input.setEyeOffset(0)

	input.setFixSpatialAudio(val) - enables/disables audio listener override on the HMD controller
		example:
			input.setFixSpatialAudio(true)

	input.setBodyMeshOverride(meshList) - overrides the body mesh list used for relative placement
		(pass a table of meshes; nil falls back to pawnModule.getBodyMesh())
		example:
			input.setBodyMeshOverride({ myMesh })

	input.isBodyMeshPositionAdjustmentAllowed() - returns whether adjustBodyMeshPosition is enabled
		example:
			if input.isBodyMeshPositionAdjustmentAllowed() then ... end

	input.setMeshRelativePositionDisabled(val) - when true, stops updating body mesh RelativeLocation
		and immediately clears XY offsets
		example:
			input.setMeshRelativePositionDisabled(true)

	input.updateMeshRelativePosition((optional)setDisabled) - manually updates (or clears if
		setDisabled) body mesh RelativeLocation from head/anim/eye offsets
		example:
			input.updateMeshRelativePosition()
			input.updateMeshRelativePosition(true)

	input.preventPawnSettingsResetOnDisable(val) - when true, disabling input does not restore
		cached pawn bUseControllerRotation* / CharacterMovement orient flags
		example:
			input.preventPawnSettingsResetOnDisable(true)

	input.setCurrentProfile(profileID) - sets the active input parameter profile by id and resets runtime
		example:
			input.setCurrentProfile("055655c3-5c27-40fb-afa2-af6169aa5397")

	input.setCurrentProfileByLabel(profileLabel) - sets the active profile by display label
		example:
			input.setCurrentProfileByLabel("Default")

	input.getConfigurationWidgets((optional)options) - returns config UI widgets from input_config
		(non-dev overlay integration). Initializes the config module on first call.
		example:
			local widgets = input.getConfigurationWidgets()

	input.showConfiguration(saveFileName, (optional)options) - shows the input configuration UI
		example:
			input.showConfiguration("my_input_config")

--]]

local uevrUtils = require("libs/uevr_utils")
local mathLib = require("libs/core/math_lib")
local controllers = require("libs/controllers")
local bodyYaw = require("libs/body_yaw")
local pawnModule = require("libs/pawn")
local inputEnums = require("libs/enums/input")
local paramModule = require("libs/core/params")
local attachments = require("libs/attachments")
local plugin = require("libs/core/plugin")

local M = {}

M.AimMethod = inputEnums.AimMethod
M.PawnPositionMode = inputEnums.PawnPositionMode
M.PawnRotationMode = inputEnums.PawnRotationMode
--M.MovementMethod = inputEnums.MovementMethod

local parametersFileName = "input_parameters"
local parameters = {
    isDisabledOverride = false,
    aimMethod = M.AimMethod.UEVR,
    fixSpatialAudio = true,
	useRootOffset = true,
    rootOffset = {X=0,Y=0,Z=0},
    useSnapTurn = false,
    snapAngle = 30,
    smoothTurnSpeed = 50,
    pawnPositionMode = M.PawnPositionMode.FOLLOWS,
    pawnRotationMode = M.PawnRotationMode.RIGHT_CONTROLLER,
	pawnRotationLockedSmoothTime = 0.0,
    pawnPositionSweepMovement = true,
    pawnPositionAnimationScale = 0.2,
    headOffset = {X=0,Y=0,Z=0},
    adjustForAnimation = false,
    adjustForEyeOffset = false,
    eyeOffset = 0,
	headBoneName = "",
	rootBoneName = "",
	aimCamera = "",
	useControllerRotationPitch = 1,
	useControllerRotationYaw = 1,
	useControllerRotationRoll = 1,
	orientRotationToMovement = 1,
	useControllerDesiredRotation = 1,
--	movementMethod = M.MovementMethod.HEAD,
	optimizeBodyRotationCalculations = true,
	optimizeBodyLocationCalculations = true,
	pawnRotationModeDisableRotation = false,
	pawnRotationModeDisableInEarlyUpdate = false,
	usePawnControlRotation = 1,
	cameraResetAction = 1,
	adjustBodyMeshPosition = true,
	overridePlayerControllerPitch = false,
	overridePlayerControllerPitchValue = 0,
	overridePlayerControllerYaw = false,
	overridePlayerControllerYawValue = 0,
	overridePlayerControllerRoll = false,
	overridePlayerControllerRollValue = 0,
}

local isDisabled = false

local status = {}
local rootComponent = nil
local decoupledYaw = nil
local bodyRotationOffset = 0
local bodyMesh = nil
local pawnRotationModeOverride = nil
-- Optional absolute world-yaw hold. When set, updateBodyYaw writes this yaw and skips
-- mode tracking. Nil (default) leaves all games unchanged.
local forcedBodyYaw = nil
-- When true, updateBodyYaw does not write RootComponent (still syncs bodyRotationOffset
-- from current root). Opt-in; Nil/false default leaves all games unchanged.
local bodyYawWritesSuppressed = false
-- Last body-facing yaw before/during suppress; used to carry game snap-turns into
-- decoupledYaw so the VR view stays aligned with the pawn (e.g. ladder top mount).
local lastSuppressedBodyYaw = nil
local aimMethodOverride = nil
local aimCameraOverride = nil
local lastBodyYawUpdateTime = nil

--Normally body yaw only needs to be calculated for one eye only in on_early_calculate_stereo_view_offset
--but in some cases, like Avowed when climbing, the body yaw needs to be calculated for both eyes or else the eyes desync
--This flag enables optimizations to skip the second calculation when not needed
--Also if IK hands are jittery when snap turning or moving your head quickly, try setting this to false
local optimizeBodyYawCalculations = true

local rxState = 0
local snapTurnDeadZone = 8000

local aimRotationOffset = uevrUtils.rotator(0,0,0)
local weaponRotation = nil -- externally set for WEAPON aim method

local currentHeadRotator = uevrUtils.rotator(0,0,0)

local inputConfigDev = nil
local inputConfig = nil

local zeroRotator = uevrUtils.rotator(0,0,0)
local zeroVector = uevrUtils.vector(0,0,0)

--local localPawn = nil
local bodyMeshOverride = nil
local preventPawnSettingsResetOnDisable = false

--this module is designed to work with these UEVR settings 
uevrUtils.set_decoupled_pitch(true)
uevrUtils.set_decoupled_pitch_adjust_ui(true)

local currentLogLevel = LogLevel.Error
function M.setLogLevel(val)
	currentLogLevel = val
end
function M.print(text, logLevel)
	if logLevel == nil then logLevel = LogLevel.Debug end
	if logLevel <= currentLogLevel then
		uevrUtils.print("[input] " .. text, logLevel)
	end
end

local paramManager = paramModule.new(parametersFileName, parameters, true)

local function getParameter(key)
    return paramManager:getFromActiveProfile(key)
end

local function setParameter(key, value, persist)
    return paramManager:setInActiveProfile(key, value, persist)
end

local function getAimOffsetAdjustedRotation(rotation)
	if (aimRotationOffset.Pitch == nil or aimRotationOffset.Pitch == 0) and (aimRotationOffset.Yaw == nil or aimRotationOffset.Yaw == 0) and (aimRotationOffset.Roll == nil or aimRotationOffset.Roll == 0) then
		return rotation
	end
	return kismet_math_library:ComposeRotators(aimRotationOffset, rotation)

	-- --Quat_MakeFromEuler expects Roll Pitch Yaw
	-- local quat1 = kismet_math_library:Quat_MakeFromEuler(uevrUtils.vector(aimRotationOffset.Roll, aimRotationOffset.Pitch, aimRotationOffset.Yaw))
	-- local quat2 = kismet_math_library:Quat_MakeFromEuler(uevrUtils.vector(rotation.Roll, rotation.Pitch, rotation.Yaw))
	-- local quat3 = kismet_math_library:Multiply_QuatQuat(quat2, quat1)
	-- local final = kismet_math_library:Quat_Rotator(quat3)
	-- return final
end
getAimOffsetAdjustedRotation = uevrUtils.profiler:wrap("getAimOffsetAdjustedRotation", getAimOffsetAdjustedRotation)

function M.preventPawnSettingsResetOnDisable(val)
	preventPawnSettingsResetOnDisable = val
end	

function M.getAimOffsetAdjustedRotation(rotation)
	return getAimOffsetAdjustedRotation(rotation)
end

function M.setRotationModeRotationDisabled(val)
	status.rotationModeRotationDisabled = val
end

function M.setMeshRelativePositionDisabled(val)
	status.meshRelativePositionDisabled = val
	if val == true then
		M.updateMeshRelativePosition(true)
	end
end

local function isRotationModeRotationDisabled()
	return status.rotationModeRotationDisabled or (getParameter("pawnRotationModeDisableRotation") == true)
end

local function isRotationModeEarlyUpdateDisabled()
	return status.rotationModeEarlyUpdateDisabled or (getParameter("pawnRotationModeDisableInEarlyUpdate") == true)
end

function M.setBodyMeshOverride(meshList)
	bodyMeshOverride = meshList
end

function M.isBodyMeshPositionAdjustmentAllowed()
	return uevrUtils.ternary(getParameter("adjustBodyMeshPosition") == nil, true, getParameter("adjustBodyMeshPosition"))
end

local function getAimMethod()
	return aimMethodOverride ~= nil and aimMethodOverride or getParameter("aimMethod")
end

local function getRootOffsetEnabled()
	return uevrUtils.ternary(getParameter("useRootOffset") == nil, true, getParameter("useRootOffset"))
end

local function getBodyMesh()
	if bodyMeshOverride ~= nil then
		return bodyMeshOverride
	end
	if bodyMesh == nil then
		bodyMesh = pawnModule.getBodyMesh()
	end
	--print("Body Mesh:", bodyMesh and bodyMesh:get_full_name() or "None")
	return {bodyMesh}
end
getBodyMesh = uevrUtils.profiler:wrap("getBodyMesh", getBodyMesh)

local function getPawn()
	if uevrUtils.getValid(status.pawn) == nil then
		status.pawn = uevrUtils.getValid(pawnModule.getPawn() or pawn)
	end
	return status.pawn
end

-- Trying this for Dead Island 2 avatar changes
setInterval(1000, function()
	local current = uevrUtils.getValid(pawnModule.getPawn() or pawn)
	if status.pawn ~= current then
		M.reset()
		status.pawn = current
	end
end)


local cameraComponent = {
	initialized = false,
	component = nil,
	originalState = nil,
	currentControllerID = nil,
	originalParent = nil,
	init = function(self)
        -- local aimCamera = getParameter("aimCamera")
        -- local aimMethod = getParameter("aimMethod")
        -- if (aimMethod == M.AimMethod.LEFT_CONTROLLER or aimMethod == M.AimMethod.RIGHT_CONTROLLER or aimMethod == M.AimMethod.HEAD) and aimCamera ~= nil and aimCamera ~= "" and aimCamera ~= "None" then
		-- 	print("Initializing aim camera component from descriptor:", aimCamera)
		-- 	self.component = uevrUtils.getObjectFromDescriptor(aimCamera)
		-- 	if self.component ~= nil then
		-- 		self.originalState = self.component.bUsePawnControlRotation
		-- 		self.initialized = true
		-- 	end
		-- else
		-- 	self.initialized = true
        -- end
    end,
	get = function(self)
		-- if self.initialized == false then
		-- 	self:init()
		-- end
		-- if uevrUtils.getValid(self.component) ~= nil then
		-- 	return self.component
		-- end
		-- return nil
	end,
	reattachToParent = function(self)
		-- print("Reattaching aim camera to original parent if needed",self.component,self.originalParent)
		-- if uevrUtils.getValid(self.component) ~= nil then
		-- 	M.print("Detaching aim camera from controller")
		-- 	self.component:DetachFromParent(false,false)
		-- 	if uevrUtils.getValid(self.originalParent) ~= nil then
		-- 		M.print("Reattaching aim camera to original parent " .. self.originalParent:get_full_name())
		-- 		self.component:K2_AttachTo(self.originalParent, uevrUtils.fname_from_string(""), 0, false)
		-- 		self.originalParent = nil
		-- 	end
		-- end
	end,
	updateAim = function(self)
		local aimCamera = getParameter("aimCamera")
        local aimMethod = getAimMethod() -- getParameter("aimMethod")
		local validController = aimMethod == M.AimMethod.LEFT_CONTROLLER or aimMethod == M.AimMethod.RIGHT_CONTROLLER or aimMethod == M.AimMethod.HEAD
		local validWeapon = aimMethod == M.AimMethod.LEFT_WEAPON or aimMethod == M.AimMethod.RIGHT_WEAPON
		local validAimCamera = aimCamera ~= nil and aimCamera ~= "" and aimCamera ~= "None"
		if (validController or validWeapon) and validAimCamera then
			if self.component == nil then
				self.component = uevrUtils.getObjectFromDescriptor(aimCamera)
				if self.component ~= nil then
					self.originalState = self.component.bUsePawnControlRotation
				end
			end
		else
			if self.component ~= nil then
				self:reset()
			end
		end

		if uevrUtils.getValid(self.component) ~= nil and self.component.K2_SetWorldRotation ~= nil then
			if validController then
				local controllerID = aimMethod == M.AimMethod.LEFT_CONTROLLER and 0 or (aimMethod == M.AimMethod.RIGHT_CONTROLLER and 1 or (aimMethod == M.AimMethod.HEAD and 2 or 1))
				self.currentControllerID = controllerID

				local rotation = controllers.getControllerRotation(controllerID)
				local location = controllers.getControllerLocation(controllerID)
				if rotation ~= nil and location ~= nil then
					if aimMethod == M.AimMethod.LEFT_CONTROLLER or aimMethod == M.AimMethod.RIGHT_CONTROLLER then
						rotation = getAimOffsetAdjustedRotation(rotation)
					end
					--pcall( function() --gun for hire crashes here
						self.component:K2_SetWorldRotation(rotation, false, reusable_hit_result, false)
						self.component:K2_SetWorldLocation(location, false, reusable_hit_result, false)
					--end)
				end
			elseif validWeapon then
				--this if check does not appear to be needed
				--although it seems like if there is no weapon then location and rotation should be taken from the controller
				--so maybe its here because that was the original intention
				local attachment = attachments.getCurrentGrippedAttachment(aimMethod == M.AimMethod.LEFT_WEAPON and Handed.Left or Handed.Right)
				if attachment ~= nil then
					local controllerID = aimMethod == M.AimMethod.LEFT_WEAPON and Handed.Left or Handed.Right
					self.currentControllerID = controllerID

					local location, rotation = attachments.getActiveAttachmentTransforms(controllerID)
					rotation = getAimOffsetAdjustedRotation(rotation)

					if rotation ~= nil and location ~= nil then
						--pcall( function() --gun for hire crashes here
							self.component:K2_SetWorldRotation(rotation, false, reusable_hit_result, false)
							self.component:K2_SetWorldLocation(location, false, reusable_hit_result, false)
						--end)
					end
				end
			end
			return true
		end

		return false
	end,
	setUsePawnControlRotation = function(self, val)
		if uevrUtils.getValid(self.component) ~= nil and self.component.bUsePawnControlRotation ~= nil then
			--print(1, val, self.component:get_full_name())
			if val == nil then
				val = self.originalState
			end
			self.component.bUsePawnControlRotation = val
		end
	end,
	setRotation = function(self, rotation)
		-- if self.initialized == false then
		-- 	self:init()
		-- end
		-- if uevrUtils.getValid(self.component) ~= nil then
		-- 	--self.component.bUsePawnControlRotation = false
		-- 	self.component.RelativeRotation = rotation
		-- end
	end,
	reset = function(self)
		--print("Camera Component Reset called")
		if uevrUtils.getValid(self.component) ~= nil  then
			if self.component.AttachParent ~= nil then
				local cameraResetAction = getParameter("cameraResetAction")
				if cameraResetAction == 2 then
					M.print("Resetting camera component world transform to parent transform")
					local rotation = uevrUtils.getComponentRotation(self.component.AttachParent)
					local location = uevrUtils.getComponentLocation(self.component.AttachParent)
					self.component:K2_SetWorldRotation(rotation,false,reusable_hit_result,false)
					self.component:K2_SetWorldLocation(location,false,reusable_hit_result,false)
				else
					M.print("Not resetting camera component world transform on reset")
				end
			end
			if self.originalState ~= nil and self.component.bUsePawnControlRotation ~= nil then
				self.component.bUsePawnControlRotation = self.originalState
			end
		end
		self.component = nil
		self.originalState = nil
		self.currentControllerID = nil
		self.originalParent = nil
	end
}
cameraComponent.updateAim = uevrUtils.profiler:wrap("cameraComponent.updateAim", cameraComponent.updateAim)

--[[
--this one moves the camera to the controller which seems cleaner but causes issues
--with sanp turn and gestures when pawns suddenly change
local cameraComponent = {
	initialized = false,
	component = nil,
	originalState = nil,
	currentControllerID = nil,
	originalParent = nil,
	init = function(self)
        local aimCamera = getParameter("aimCamera")
        if getParameter("aimMethod") ~= M.AimMethod.UEVR and aimCamera ~= nil and aimCamera ~= "" and aimCamera ~= "None" then
			print("Initializing aim camera component from descriptor:", aimCamera)
			self.component = uevrUtils.getObjectFromDescriptor(aimCamera)
			if self.component ~= nil then
				self.originalState = self.component.bUsePawnControlRotation
				self.initialized = true
			end
		else
			self.initialized = true
        end
    end,
	get = function(self)
		if self.initialized == false then
			self:init()
		end
		if uevrUtils.getValid(self.component) ~= nil then
			return self.component
		end
		return nil
	end,
	reattachToParent = function(self)
		print("Reattaching aim camera to original parent if needed",self.component,self.originalParent)
		if uevrUtils.getValid(self.component) ~= nil then
			M.print("Detaching aim camera from controller")
			self.component:DetachFromParent(false,false)
			if uevrUtils.getValid(self.originalParent) ~= nil then
				M.print("Reattaching aim camera to original parent " .. self.originalParent:get_full_name())
				self.component:K2_AttachTo(self.originalParent, uevrUtils.fname_from_string(""), 0, false)
				self.originalParent = nil
			end
		end
	end,
	updateAim = function(self, aimMethod)
		if self.initialized == false then
			self:init()
		end
		if self.component ~= nil then
			local controllerID = aimMethod == M.AimMethod.LEFT_CONTROLLER and 0 or (aimMethod == M.AimMethod.RIGHT_CONTROLLER and 1 or (aimMethod == M.AimMethod.HEAD and 2 or -1))
			if controllerID == -1 then
				--not using a controller for aim, reattach to parent if needed
				self:reset()
				return false
			end

			if self.originalParent == nil then
				self.originalParent = self.component.AttachParent
			end
			if self.currentControllerID ~= controllerID then
				M.print("Attaching aim camera to controller " .. controllerID)
				self.component:DetachFromParent(false,false)
				controllers.attachComponentToController(controllerID, self.component)
				uevrUtils.set_component_relative_transform(self.component, {X=0,Y=0,Z=0}, {Pitch=0,Yaw=0,Roll=0})
				self.currentControllerID = controllerID
			end
			return true
		end

		return false
	end,
	setUsePawnControlRotation = function(self, val)
		if self.component ~= nil then
			--print(1, val, self.component:get_full_name())
			if val == nil then
				val = self.originalState
			end
			self.component.bUsePawnControlRotation = val
		end
	end,
	setRotation = function(self, rotation)
		if self.initialized == false then
			self:init()
		end
		if uevrUtils.getValid(self.component) ~= nil then
			--self.component.bUsePawnControlRotation = false
			self.component.RelativeRotation = rotation
		end
	end,
	reset = function(self)
		print("Camera Component Reset called")
		if self.initialized == true then
			self:reattachToParent()
			if uevrUtils.getValid(self.component) ~= nil and self.component.bUsePawnControlRotation and self.originalState ~= nil then
				self.component.bUsePawnControlRotation = self.originalState
			end
			print("Camera Component Was Reset")
		end
		self.initialized = false
		self.component = nil
		self.originalState = nil
		self.currentControllerID = nil
		self.originalParent = nil
	end
}
]]--

local pawnSettings = nil
local function resetPawnSettings()
	cameraComponent:reset()
	local pawn = uevrUtils.getValid(status.pawn)
	if pawn ~= nil and pawnSettings ~= nil and pawn.bUseControllerRotationPitch ~= nil then
		--restore pawn settings
		--print("Restoring pawn settings")
		pawn.bUseControllerRotationPitch = pawnSettings.bUseControllerRotationPitch
		pawn.bUseControllerRotationYaw = pawnSettings.bUseControllerRotationYaw
		pawn.bUseControllerRotationRoll = pawnSettings.bUseControllerRotationRoll
		if pawn.CharacterMovement ~= nil then
			pawn.CharacterMovement.bOrientRotationToMovement = pawnSettings.bOrientRotationToMovement
			pawn.CharacterMovement.bUseControllerDesiredRotation = pawnSettings.bUseControllerDesiredRotation
		end
		pawnSettings = nil
	end
end
resetPawnSettings = uevrUtils.profiler:wrap("resetPawnSettings", resetPawnSettings)

-- local function applyDecoupledYawToPlayerController()
-- 	if pawn ~= nil then
-- 		pawn.Controller:SetControlRotation(uevrUtils.rotator(0, decoupledYaw, 0))
-- 	end
-- end
-- applyDecoupledYawToPlayerController = uevrUtils.profiler:wrap("applyDecoupledYawToPlayerController", applyDecoupledYawToPlayerController)

local function updatePawnSettings()
	local pawn = status.pawn
	if pawn ~= nil and pawn.bUseControllerRotationPitch ~= nil then
		if pawnSettings == nil then
			pawnSettings = {}
			pawnSettings.bUseControllerRotationPitch = pawn.bUseControllerRotationPitch
			pawnSettings.bUseControllerRotationYaw = pawn.bUseControllerRotationYaw
			pawnSettings.bUseControllerRotationRoll = pawn.bUseControllerRotationRoll
			pawnSettings.bOrientRotationToMovement = pawn.CharacterMovement and pawn.CharacterMovement.bOrientRotationToMovement or false
			pawnSettings.bUseControllerDesiredRotation = pawn.CharacterMovement and pawn.CharacterMovement.bUseControllerDesiredRotation or false
		end

		local useControllerRotationPitch = getParameter("useControllerRotationPitch")
		if useControllerRotationPitch ~= nil and useControllerRotationPitch ~= ETriState.DEFAULT then
			pawn.bUseControllerRotationPitch = useControllerRotationPitch == ETriState.TRUE
		else
			pawn.bUseControllerRotationPitch = pawnSettings.bUseControllerRotationPitch
		end
		local useControllerRotationYaw = getParameter("useControllerRotationYaw")
		if useControllerRotationYaw ~= nil and useControllerRotationYaw ~= ETriState.DEFAULT then
			pawn.bUseControllerRotationYaw = useControllerRotationYaw == ETriState.TRUE
		else
			pawn.bUseControllerRotationYaw = pawnSettings.bUseControllerRotationYaw
		end
		local useControllerRotationRoll = getParameter("useControllerRotationRoll")
		if useControllerRotationRoll ~= nil and useControllerRotationRoll ~= ETriState.DEFAULT then
			pawn.bUseControllerRotationRoll = useControllerRotationRoll == ETriState.TRUE
		else
			pawn.bUseControllerRotationRoll = pawnSettings.bUseControllerRotationRoll
		end

		if pawn.CharacterMovement ~= nil then
			local orientRotationToMovement = getParameter("orientRotationToMovement")
			if orientRotationToMovement ~= nil and orientRotationToMovement ~= ETriState.DEFAULT then
				pawn.CharacterMovement.bOrientRotationToMovement = orientRotationToMovement == ETriState.TRUE
			else
				pawn.CharacterMovement.bOrientRotationToMovement = pawnSettings.bOrientRotationToMovement
			end
			local useControllerDesiredRotation = getParameter("useControllerDesiredRotation")
			if useControllerDesiredRotation ~= nil and useControllerDesiredRotation ~= ETriState.DEFAULT then
				pawn.CharacterMovement.bUseControllerDesiredRotation = useControllerDesiredRotation == ETriState.TRUE
			else
				pawn.CharacterMovement.bUseControllerDesiredRotation = pawnSettings.bUseControllerDesiredRotation
			end
		end

		local usePawnControlRotation = getParameter("usePawnControlRotation")
		if usePawnControlRotation ~= nil and usePawnControlRotation ~= ETriState.DEFAULT then
			cameraComponent:setUsePawnControlRotation(usePawnControlRotation == ETriState.TRUE)
		else
			cameraComponent:setUsePawnControlRotation(nil)
		end
	end
	--print("Pitch",pawn.bUseControllerRotationPitch,"Yaw",pawn.bUseControllerRotationYaw,"Roll",pawn.bUseControllerRotationRoll)
end
updatePawnSettings = uevrUtils.profiler:wrap("updatePawnSettings", updatePawnSettings)

--Thses shouldn't need to be done on the tick but if they are, move them to the function above
-- setInterval(1000, function ()
-- 	local movementMethod = getParameter("movementMethod")
-- 	if movementMethod ~= nil and movementMethod ~= 1 then
-- 		uevrUtils.setUEVRParam_int("VR_MovementOrientation", movementMethod - 1)
-- 	end

-- 	--updatePawnSettings()
-- end)

-- Im setting this to true for legacy purposes to be backwards compatible with old configs
-- I have a feeling though that this should default to false. Atomic Heart needs this to be false for correct pickup on chests.
local playerControllerRotationFollowsBody = true
function M.setPlayerControllerRotationFollowsBody(followsBody)
	playerControllerRotationFollowsBody = followsBody
end
local function setPlayerControllerRotation(followsBody)
	if followsBody == nil then followsBody = false end
	local pawn = status.pawn

	if followsBody then
		if pawn ~= nil and decoupledYaw ~= nil and pawn.Controller ~= nil then
			pawn.Controller:SetControlRotation(uevrUtils.rotator(0, decoupledYaw + bodyRotationOffset, 0))
		end
	else
		local aimMethod = getAimMethod() --getParameter("aimMethod")
		if aimMethod ~= M.AimMethod.UEVR then
			local rotation = nil
			if aimMethod == M.AimMethod.RIGHT_WEAPON then
				rotation = (weaponRotation ~= nil and weaponRotation.right ~= nil) and weaponRotation.right or controllers.getControllerRotation(Handed.Right)
			elseif aimMethod == M.AimMethod.LEFT_WEAPON then
				rotation = (weaponRotation ~= nil and weaponRotation.left ~= nil) and weaponRotation.left or controllers.getControllerRotation(Handed.Left)
			else
				local controllerID = aimMethod == M.AimMethod.LEFT_CONTROLLER and 0 or (aimMethod == M.AimMethod.HEAD and 2 or 1)
				rotation = controllers.getControllerRotation(controllerID)
				--only use aim offset adjust if aimMethod is left or right controller
				if aimMethod == M.AimMethod.LEFT_CONTROLLER or aimMethod == M.AimMethod.RIGHT_CONTROLLER then
					rotation = getAimOffsetAdjustedRotation(rotation) --things like gunstock may adjust the rotation
				end
			end
			if pawn ~= nil and pawn.Controller ~= nil and pawn.Controller.SetControlRotation ~= nil and rotation ~= nil then
				if uevrUtils.getExtremeCompatibilityMode() == false then
					pawn.Controller:SetControlRotation(rotation) --because the previous booleans were set, aiming with the hand or head doesnt affect the rotation of the pawn
				else
					local result = plugin.executeFunction(pawn.Controller, "SetControlRotation", rotation)
					--print("SetControlRotation: " , result.ReturnValue)
				end
			end
		end
	end
end

local function updateAim()
	local pawn = status.pawn
	if aimCameraOverride ~= true and cameraComponent:updateAim() == true then
		
		setPlayerControllerRotation(playerControllerRotationFollowsBody)
		-- if (aimRotationOffset.Pitch == nil or aimRotationOffset.Pitch == 0) and (aimRotationOffset.Yaw == nil or aimRotationOffset.Yaw == 0) and (aimRotationOffset.Roll == nil or aimRotationOffset.Roll == 0) then
		-- 	cameraComponent:setRotation(zeroRotator)
		-- else
		-- 	cameraComponent:setRotation(aimRotationOffset)
		-- end
		--cameraComponent:setRotation(getAimOffsetAdjustedRotation(uevrUtils.rotator(0,0,0)))
		--	print(pawn, rootComponent, decoupledYaw, bodyRotationOffset)

		-- if pawn ~= nil and decoupledYaw ~= nil and pawn.Controller ~= nil then
		-- 	pawn.Controller:SetControlRotation(uevrUtils.rotator(0, decoupledYaw + bodyRotationOffset, 0))
		-- end

		-- if pawn ~= nil and decoupledYaw ~= nil and pawn.Controller ~= nil then
		-- 	-- local rotation = uevrUtils.rotator(0, decoupledYaw + bodyRotationOffset, 0)
		-- 	-- if inputTestOffset ~= nil then
		-- 	-- 	print("INPUT TEST OFFSET", inputTestOffset)
		-- 	-- 	rotation = kismet_math_library:ComposeRotators(rotation, inputTestOffset)
		-- 	-- end
		-- 	local aimMethod = getAimMethod() --getParameter("aimMethod")
		-- 	local controllerID = aimMethod == M.AimMethod.LEFT_CONTROLLER and 0 or (aimMethod == M.AimMethod.HEAD and 2 or 1)
		-- 	local rotation = controllers.getControllerRotation(controllerID)
		-- 	rotation = getAimOffsetAdjustedRotation(rotation) --things like gunstock may adjust the rotation
		-- 	pawn.Controller:SetControlRotation(rotation)
		-- end
	else
		setPlayerControllerRotation(false)

		-- --if camera component isnt handling it then use the old way
		-- --This way wont work for most games because yaw is ignored in most games but it does work for Hello Neighbor
		-- local aimMethod = getAimMethod() --getParameter("aimMethod")
		-- if aimMethod ~= M.AimMethod.UEVR then
		-- 	local rotation = nil
		-- 	if aimMethod == M.AimMethod.RIGHT_WEAPON then
		-- 		rotation = (weaponRotation ~= nil and weaponRotation.right ~= nil) and weaponRotation.right or controllers.getControllerRotation(Handed.Right)
		-- 	elseif aimMethod == M.AimMethod.LEFT_WEAPON then
		-- 		rotation = (weaponRotation ~= nil and weaponRotation.left ~= nil) and weaponRotation.left or controllers.getControllerRotation(Handed.Left)
		-- 	else
		-- 		local controllerID = aimMethod == M.AimMethod.LEFT_CONTROLLER and 0 or (aimMethod == M.AimMethod.HEAD and 2 or 1)
		-- 		rotation = controllers.getControllerRotation(controllerID)
		-- 		--only use aim offset adjust if aimMethod is left or right controller
		-- 		if aimMethod == M.AimMethod.LEFT_CONTROLLER or aimMethod == M.AimMethod.RIGHT_CONTROLLER then
		-- 			rotation = getAimOffsetAdjustedRotation(rotation) --things like gunstock may adjust the rotation
		-- 		end
		-- 	end
		-- 	if pawn ~= nil and pawn.Controller ~= nil and pawn.Controller.SetControlRotation ~= nil and rotation ~= nil then
		-- 		pawn.Controller:SetControlRotation(rotation) --because the previous booleans were set, aiming with the hand or head doesnt affect the rotation of the pawn
		-- 	end
		-- end
	end

	-- --if camera component isnt handling it then use the old way
	-- local rotation = nil
	-- local aimMethod = getParameter("aimMethod")
	-- if aimMethod == M.AimMethod.RIGHT_WEAPON then
	-- 	rotation = (weaponRotation ~= nil and weaponRotation.right ~= nil) and weaponRotation.right or controllers.getControllerRotation(Handed.Right)
	-- elseif aimMethod == M.AimMethod.LEFT_WEAPON then
	-- 	rotation = (weaponRotation ~= nil and weaponRotation.left ~= nil) and weaponRotation.left or controllers.getControllerRotation(Handed.Left)
	-- else
	-- 	local controllerID = aimMethod == M.AimMethod.LEFT_CONTROLLER and 0 or (aimMethod == M.AimMethod.HEAD and 2 or 1)
	-- 	rotation = controllers.getControllerRotation(controllerID)
	-- 	--only use aim offset adjust if aimMethod is left or right controller
	-- 	if aimMethod == M.AimMethod.LEFT_CONTROLLER or aimMethod == M.AimMethod.RIGHT_CONTROLLER then
	-- 		rotation = getAimOffsetAdjustedRotation(rotation) --things like gunstock may adjust the rotation
	-- 	end
	-- end

	-- if uevrUtils.getValid(pawn) ~= nil and pawn.Controller ~= nil and pawn.Controller.SetControlRotation ~= nil and rotation ~= nil then
	-- 	--disassociates the rotation of the pawn from the rotation set by pawn.Controller:SetControlRotation()
	-- 	pawn.bUseControllerRotationPitch = false
	-- 	pawn.bUseControllerRotationYaw = false
	-- 	pawn.bUseControllerRotationRoll = false

	-- 	if pawn.CharacterMovement ~= nil then
	-- 		pawn.CharacterMovement.bOrientRotationToMovement = false
	-- 		pawn.CharacterMovement.bUseControllerDesiredRotation = false
	-- 	end

	-- 	--Pitch is actually the only part of the rotation that is used here in games like Robocop
	-- 	--Yaw is controlled by Movement Orientation for those games (may not be true now with cameraComponent:setUsePawnControlRotation(true))
	-- 	-- Use ClientSetRotation(rotation, false) in multiplayer games?
	-- 	pawn.Controller:SetControlRotation(rotation) --because the previous booleans were set, aiming with the hand or head doesnt affect the rotation of the pawn

	-- 	--cameraComponent:setUsePawnControlRotation(true)
	-- end


	-- local rotation = nil
	-- local aimMethod = getParameter("aimMethod")
	-- if aimMethod == M.AimMethod.RIGHT_WEAPON then
	-- 	rotation = (weaponRotation ~= nil and weaponRotation.right ~= nil) and weaponRotation.right or controllers.getControllerRotation(Handed.Right)
	-- elseif aimMethod == M.AimMethod.LEFT_WEAPON then
	-- 	rotation = (weaponRotation ~= nil and weaponRotation.left ~= nil) and weaponRotation.left or controllers.getControllerRotation(Handed.Left)
	-- else
	-- 	local controllerID = aimMethod == M.AimMethod.LEFT_CONTROLLER and 0 or (aimMethod == M.AimMethod.HEAD and 2 or 1)
	-- 	rotation = controllers.getControllerRotation(controllerID)
	-- 	--only use aim offset adjust if aimMethod is left or right controller
	-- 	if aimMethod == M.AimMethod.LEFT_CONTROLLER or aimMethod == M.AimMethod.RIGHT_CONTROLLER then
	-- 		rotation = getAimOffsetAdjustedRotation(rotation) --things like gunstock may adjust the rotation
	-- 	end
	-- end

	-- if uevrUtils.getValid(pawn) ~= nil and pawn.Controller ~= nil and pawn.Controller.SetControlRotation ~= nil and rotation ~= nil then
	-- 	--disassociates the rotation of the pawn from the rotation set by pawn.Controller:SetControlRotation()
	-- 	pawn.bUseControllerRotationPitch = true
	-- 	pawn.bUseControllerRotationYaw = false
	-- 	pawn.bUseControllerRotationRoll = true

	-- 	-- if pawn.CharacterMovement ~= nil then
	-- 	-- 	pawn.CharacterMovement.bOrientRotationToMovement = false
	-- 	-- 	pawn.CharacterMovement.bUseControllerDesiredRotation = false
	-- 	-- end

	-- 	--Pitch is actually the only part of the rotation that is used here in games like Robocop
	-- 	--Yaw is controlled by Movement Orientation for those games (may not be true now with cameraComponent:setUsePawnControlRotation(true))
	-- 	-- Use ClientSetRotation(rotation, false) in multiplayer games?
	-- 	print("AIM ROTATION", rotation.Yaw)
	-- 	print("BODY ROTATION", bodyRotationOffset)
	-- 	print("DECOUPLED YAW", decoupledYaw)

	-- 	rotation.Pitch = 0
	-- 	rotation.Yaw = decoupledYaw --setting this to 0 does everything except handle snap turn, commenting it causes right controller to dictate direction
	-- 	rotation.Roll = 0
	-- 	pawn.Controller:SetControlRotation(rotation) --because the previous booleans were set, aiming with the hand or head doesnt affect the rotation of the pawn

	-- 	--cameraComponent:setUsePawnControlRotation(true)
	-- 	--cameraComponent:setRotation(rotation)
	-- end
end
updateAim = uevrUtils.profiler:wrap("updateAim", updateAim)

local function saveParameter(key, value, persist, noCallbacks)
	--print("Saving Input Parameter:", key, value, persist)
	setParameter(key, value, persist)
	if not (noCallbacks == true) then
		uevrUtils.executeUEVRCallbacks("on_input_config_param_change", key, value, persist)
	end
	if key == "aimMethod" and value ~= M.AimMethod.UEVR then
		controllers.createController(0)
		controllers.createController(1)
		controllers.createController(2)
	end
	if key == "aimCamera" then
		cameraComponent:reset()
	end
	if key == "useMeshHeightForHeadOffset" then
		status["meshZOffset"] = nil
	end
	if key == "adjustBodyMeshPosition" then
		if value == false then
			M.updateMeshRelativePosition(true)
		end
	end
end

local createConfigMonitor = doOnce(function()
	uevrUtils.registerUEVRCallback("on_input_config_param_change", function(key, value, persist)
		saveParameter(key, value, persist, true)
	end)
end, Once.EVER)

function M.init(isDeveloperMode, logLevel)
	paramManager:load(true)

    if logLevel ~= nil then
        M.setLogLevel(logLevel)
    end
    if isDeveloperMode == nil and uevrUtils.getDeveloperMode() ~= nil then
        isDeveloperMode = uevrUtils.getDeveloperMode()
    end

    if isDeveloperMode then
        inputConfigDev = require("libs/config/input_config_dev")
        inputConfigDev.init(paramManager)
		createConfigMonitor()
    else
    end
end

function M.getConfigurationWidgets(options)
	if inputConfig == nil then
		inputConfig = require("libs/config/input_config")
	end
	createConfigMonitor()
	inputConfig.init(paramManager)
    return inputConfig.getConfigurationWidgets(options)
end

function M.showConfiguration(saveFileName, options)
	if inputConfig == nil then
		inputConfig = require("libs/config/ui_config")
	end
	createConfigMonitor()
	inputConfig.init(paramManager)
	inputConfig.showConfiguration(saveFileName, options)
end

function M.setDisabled(val)
	--print("Input Disabled:", val)
	saveParameter("isDisabledOverride", val)
	if val then
		--this ensures the camera gets reset to the current pawn orientation when input is re-enabled
		decoupledYaw = nil
		bodyRotationOffset = 0
		lastBodyYawUpdateTime = nil
		--M.reset()
	end
end

function M.resetCapsuleComponent()
	decoupledYaw = nil
	bodyRotationOffset = 0
	lastBodyYawUpdateTime = nil
	local pawn = status.pawn
	if pawn ~= nil and rootComponent ~= nil then
		rootComponent:K2_SetWorldRotation(uevrUtils.rotator(0,0,0),false,reusable_hit_result,false)
		pawn:K2_SetActorRotation(uevrUtils.rotator(0,0,0), false, reusable_hit_result, false)
	end
end

function M.isDisabled()
	return getParameter("isDisabledOverride") or isDisabled
end

local function executeIsDisabledCallback(...)
	local result, priority = uevrUtils.executeUEVRCallbacksWithPriorityBooleanResult("is_input_disabled", table.unpack({...}))
	return result
end

function M.registerIsDisabledCallback(func)
	uevrUtils.registerUEVRCallback("is_input_disabled", func)
end

local function doFixSpatialAudio()
	if getParameter("fixSpatialAudio") then
		local playerController = uevr.api:get_player_controller(0)
		local hmdController = controllers.getController(2)
		if playerController ~= nil and hmdController ~= nil then
			playerController:SetAudioListenerOverride(hmdController,uevrUtils.vector(0,0,0),uevrUtils.rotator(0,0,0))
		end
	else
		local playerController = uevr.api:get_player_controller(0)
		if playerController ~= nil then
			playerController:ClearAudioListenerOverride()
		end
	end
end



function M.setAimMethod(val)
	saveParameter("aimMethod", val)
end

function M.setOverrideAimMethod(val)
	aimMethodOverride = val
end

function M.setUseSnapTurn(val)
	saveParameter("useSnapTurn", val)
end

function M.setSmoothTurnSpeed(val)
	saveParameter("smoothTurnSpeed", val)
end

function M.setSnapAngle(val)
	saveParameter("snapAngle", val)
end

function M.setPawnRotationMode(val)
	saveParameter("pawnRotationMode", val)
end

function M.getPawnRotationMode()
	return getParameter("pawnRotationMode")
end

-- Includes setOverridePawnRotationMode; use this when reacting to live body yaw behavior.
function M.getEffectivePawnRotationMode()
	return pawnRotationModeOverride ~= nil and pawnRotationModeOverride or getParameter("pawnRotationMode")
end

function M.setOverridePawnRotationMode(val)
	pawnRotationModeOverride = val
end

-- Hold pawn root to an absolute world yaw (degrees), or nil to release.
-- Opt-in only: does not alter setRotationModeRotationDisabled or camera-offset behavior.
function M.setForcedBodyYaw(worldYawOrNil)
	forcedBodyYaw = worldYawOrNil
end

function M.getForcedBodyYaw()
	return forcedBodyYaw
end

-- When true, skip RootComponent yaw writes so the game (or caller) can own orientation.
-- Still syncs bodyRotationOffset from the current root. Large game-driven yaw snaps
-- (e.g. 180° ladder top mount) are mirrored into decoupledYaw so the VR view faces
-- with the pawn. Does not change camera-offset or setRotationModeRotationDisabled.
function M.setBodyYawWritesSuppressed(val)
	local enable = val and true or false
	if enable and not bodyYawWritesSuppressed and decoupledYaw ~= nil then
		-- Seed from the yaw we last owned so the next game snap is detectable.
		lastSuppressedBodyYaw = uevrUtils.clampAngle180(decoupledYaw + bodyRotationOffset)
	elseif not enable then
		lastSuppressedBodyYaw = nil
	end
	bodyYawWritesSuppressed = enable
end

function M.getBodyYawWritesSuppressed()
	return bodyYawWritesSuppressed
end

function M.setAimCameraOverride(val)
	aimCameraOverride = val
end

function M.setPawnPositionMode(val)
	saveParameter("pawnPositionMode", val)
end

function M.setPawnPositionAnimationScale(val)
	saveParameter("pawnPositionAnimationScale", val)
end

function M.setAdjustForAnimation(val)
	saveParameter("adjustForAnimation", val)
end

function M.setAdjustForEyeOffset(val)
	saveParameter("adjustForEyeOffset", val)
end

function M.setEyeOffset(val)
	saveParameter("eyeOffset", val)
end

function M.setFixSpatialAudio(val)
	saveParameter("fixSpatialAudio", val)
	doFixSpatialAudio()
end

function M.setPawnPositionSweepMovement(val)
	saveParameter("pawnPositionSweepMovement", val)
end

function M.setOptimizeBodyYawCalculations(val)
	optimizeBodyYawCalculations = val
end

function M.setHeadOffset(val)
	local v = uevrUtils.vector(val)
	if v ~= nil then
		saveParameter("headOffset", {X=v.X,Y=v.Y,Z=v.Z})
	end
end

function M.setRootOffset(val)
	local v = uevrUtils.vector(val)
	if v ~= nil then
		saveParameter("rootOffset", {X=v.X,Y=v.Y,Z=v.Z})
	end
end

--This function sets the global rootComponent variable 
local function getRootComponent()
	local pawn = getPawn()
	if pawn ~= nil and status.rootComponent == nil then
		local component = uevrUtils.getValid(pawn,{"RootComponent"})
		if component ~= nil and component.K2_GetComponentLocation ~= nil and component.K2_GetComponentRotation ~= nil and component.K2_SetWorldRotation ~= nil then
			status.rootComponent = component
		end
	end
	rootComponent = uevrUtils.getValid(status.rootComponent)
	if rootComponent == nil then
		status.rootComponent = nil
	end
	return rootComponent
	
	-- rootComponent = nil
	-- local component = uevrUtils.getValid(pawn,{"RootComponent"})
	-- if component ~= nil and component.K2_GetComponentLocation ~= nil and component.K2_GetComponentRotation ~= nil and component.K2_SetWorldRotation ~= nil then
	-- 	rootComponent = component
	-- end
	-- return rootComponent
end
getRootComponent = uevrUtils.profiler:wrap("getRootComponent", getRootComponent)

--VR_SwapControllerInputs check this to see if user has chosen left hand full input swap in the UEVR UI
local function updateDecoupledYaw(state, rotationHand)
	if rotationHand == nil then rotationHand = Handed.Right end
	local yawChange = 0
	if decoupledYaw ~= nil then
		local thumbLX = state.Gamepad.sThumbLX
		local thumbLY = state.Gamepad.sThumbLY
		local thumbRX = state.Gamepad.sThumbRX
		local thumbRY = state.Gamepad.sThumbRY

		if rotationHand == Handed.Left then
			thumbLX = state.Gamepad.sThumbRX
			thumbLY = state.Gamepad.sThumbRY
			thumbRX = state.Gamepad.sThumbLX
			thumbRY = state.Gamepad.sThumbLY
		end

		if getParameter("useSnapTurn") then
			local snapAngle = getParameter("snapAngle") or 45
			if thumbRX > snapTurnDeadZone and rxState == 0 then
				yawChange = snapAngle
				rxState=1
			elseif thumbRX < -snapTurnDeadZone and rxState == 0 then
				yawChange = -snapAngle
				rxState=1
			elseif thumbRX <= snapTurnDeadZone and thumbRX >=-snapTurnDeadZone then
				rxState=0
			end
		else
			local smoothTurnRate = (getParameter("smoothTurnSpeed") or 0) / 12.5
			local rate = thumbRX/32767
			rate =  rate*rate*rate*rate
			if thumbRX > 2200 then
				yawChange = (rate * smoothTurnRate)
			end
			if thumbRX < -2200 then
				yawChange =  -(rate * smoothTurnRate)
			end
		end

		--keep the decoupled yaw in the range of -180 to 180
		decoupledYaw = uevrUtils.clampAngle180(decoupledYaw + yawChange)
	end
	return yawChange
end
updateDecoupledYaw = uevrUtils.profiler:wrap("updateDecoupledYaw", updateDecoupledYaw)

local function initDecoupledYaw()
	if decoupledYaw == nil and rootComponent ~= nil and rootComponent.K2_GetComponentRotation ~= nil then
		if rootComponent ~= nil then
			local rotator = uevrUtils.getComponentRotation(rootComponent)
			if rotator ~= nil then decoupledYaw = rotator.Yaw end
		end
	end
end
initDecoupledYaw = uevrUtils.profiler:wrap("initDecoupledYaw", initDecoupledYaw)


-- When a pawn runs, the animation can move the mesh ahead of the pawn, allowing you to
-- see down the neck hole if you are looking down. This function calculates an offset by which a pawn's
-- mesh can be moved to keep the neck in its proper place with respect to the pawn. Concept courtesy of Pande4360
local function getAnimationHeadDelta(pawn, pawnYaw)
	if pawn ~= nil then
		local headBoneName = getParameter("headBoneName")
		local rootBoneName = getParameter("rootBoneName")
		if headBoneName ~= "" and rootBoneName ~= "" and getParameter("adjustForAnimation") == true then
			local mesh = getBodyMesh()
			if mesh ~= nil and mesh[1] ~= nil then
				mesh = mesh[1]
				local baseRotationOffsetRotatorYaw = 0
				if pawn.BaseRotationOffset ~= nil then
					local baseRotationOffsetRotator = kismet_math_library:Quat_Rotator(pawn.BaseRotationOffset)
					if baseRotationOffsetRotator ~= nil then
						baseRotationOffsetRotatorYaw = baseRotationOffsetRotator.Yaw
					end
				end

				--local pawnPos = rootComponent:K2_GetComponentLocation()
				local headSocketLocation = mesh:GetSocketLocation(uevrUtils.fname_from_string(headBoneName))
				local rootSocketLocation = mesh:GetSocketLocation(uevrUtils.fname_from_string(rootBoneName))
				local socketDelta = uevrUtils.vector(headSocketLocation.Y - rootSocketLocation.Y, headSocketLocation.X - rootSocketLocation.X, headSocketLocation.Z - rootSocketLocation.Z)
				socketDelta = kismet_math_library:RotateAngleAxis(socketDelta, pawnYaw - baseRotationOffsetRotatorYaw, uevrUtils.vector(0,0,1))
				--print(headBoneName, rootBoneName, socketDelta.X, socketDelta.Y, socketDelta.Z)
				return socketDelta
			end
		end
	end
	return uevrUtils.vector(0,0,0)
end
getAnimationHeadDelta = uevrUtils.profiler:wrap("getAnimationHeadDelta", getAnimationHeadDelta)

--because the eyes may not be centered on the origin, an hmd rotation can cause unexpected movement of the pawn mesh. This compensates for that movement
local function getEyeOffsetDelta(pawn, pawnYaw)
	local adjustForEyeOffset = getParameter("adjustForEyeOffset")
	if pawn ~= nil and adjustForEyeOffset == true then
		local eyeOffset = getParameter("eyeOffset")
		local eyeOffsetScale = (pawn.BaseTranslationOffset and pawn.BaseTranslationOffset.X or 0) + eyeOffset
		local eyeVector = kismet_math_library:Conv_RotatorToVector(uevrUtils.rotator(currentHeadRotator.Pitch, pawnYaw - currentHeadRotator.Yaw, currentHeadRotator.Roll))
		eyeVector = eyeVector * eyeOffsetScale
		--print("EYE1",eyeVector.X,eyeVector.Y,eyeVector.Z)
		return eyeVector
	else
		return uevrUtils.vector(0,0,0)
	end
end
getEyeOffsetDelta = uevrUtils.profiler:wrap("getEyeOffsetDelta", getEyeOffsetDelta)

local function getPawnRotationMode()
	return pawnRotationModeOverride ~= nil and pawnRotationModeOverride or getParameter("pawnRotationMode")
end

local function getBodyRotationSmoothingDelta(delta)
	if delta ~= nil and delta > 0 then
		lastBodyYawUpdateTime = os.clock()
		return delta
	end

	local now = os.clock()
	local fallbackDelta = lastBodyYawUpdateTime ~= nil and (now - lastBodyYawUpdateTime) or nil
	lastBodyYawUpdateTime = now

	if fallbackDelta == nil or fallbackDelta <= 0 then
		return 1 / 90
	end

	return math.min(fallbackDelta, 0.05)
end

local function smoothBodyRotationOffset(targetOffset, delta)
	targetOffset = uevrUtils.clampAngle180(targetOffset or 0)

	local smoothTime = getParameter("pawnRotationLockedSmoothTime") or 0
	if smoothTime <= 0 then
		return targetOffset
	end

	local smoothingDelta = getBodyRotationSmoothingDelta(delta)
	local alpha = 1 - math.exp(-smoothingDelta / smoothTime)
	local angleDelta = uevrUtils.clampAngle180(targetOffset - bodyRotationOffset)

	if math.abs(angleDelta) < 0.01 then
		return targetOffset
	end

	return uevrUtils.clampAngle180(bodyRotationOffset + angleDelta * math.min(1, alpha))
end

local lateYaw = false
--this is called from both on_pre_engine_tick and on_early_calculate_stereo_view_offset but K2_SetWorldRotation can only be called once per tick
--because of the currentOffset ~= bodyRotationOffset check
local function updateBodyYaw(delta)
	if forcedBodyYaw ~= nil and decoupledYaw ~= nil and rootComponent ~= nil then
		bodyRotationOffset = uevrUtils.clampAngle180(forcedBodyYaw - decoupledYaw)
		local ok, err = pcall(function()
			if rootComponent.K2_SetWorldRotation ~= nil then
				rootComponent:K2_SetWorldRotation(uevrUtils.rotator(0, forcedBodyYaw, 0), false, reusable_hit_result, false)
			end
		end)
		if not ok then
			M.print("Error setting world rotation: " .. err)
		end
		return
	end

	if bodyYawWritesSuppressed and decoupledYaw ~= nil and rootComponent ~= nil then
		-- Let the game own RootComponent yaw. Mirror every root yaw change into
		-- decoupledYaw so the VR view stays facing with the pawn (ladder mounts,
		-- including gradual/animated 180° top-mount turns).
		local ok, err = pcall(function()
			if rootComponent.K2_GetComponentRotation ~= nil then
				local rootRot = uevrUtils.getComponentRotation(rootComponent)
				if rootRot ~= nil then
					local rootYaw = rootRot.Yaw
					if lastSuppressedBodyYaw ~= nil then
						local yawDelta = uevrUtils.clampAngle180(rootYaw - lastSuppressedBodyYaw)
						if math.abs(yawDelta) > 1.0 then
							decoupledYaw = uevrUtils.clampAngle180(decoupledYaw + yawDelta)
						end
					end
					lastSuppressedBodyYaw = rootYaw
					bodyRotationOffset = uevrUtils.clampAngle180(rootYaw - decoupledYaw)
				end
			end
		end)
		if not ok then
			M.print("Error getting component rotation: " .. err)
		end
		return
	end

	local pawnRotationMode = getPawnRotationMode() -- getParameter("pawnRotationMode")
	if pawnRotationMode ~= M.PawnRotationMode.NONE then
		if decoupledYaw~= nil and rootComponent ~= nil then
			local currentOffset = bodyRotationOffset
			if delta ~= nil and delta > 0 then
				lastBodyYawUpdateTime = os.clock()
			end
			if lateYaw then
				if pawnRotationMode == M.PawnRotationMode.SIMPLE then
					bodyRotationOffset = bodyYaw.update(bodyRotationOffset, currentHeadRotator.Yaw - decoupledYaw, delta)
				elseif pawnRotationMode == M.PawnRotationMode.ADVANCED then
					--bodyRotationOffset = smoothBodyRotationOffset(bodyYaw.updateAdvanced(bodyRotationOffset, currentHeadRotator.Yaw - decoupledYaw, controllers.getControllerLocation(2), controllers.getControllerLocation(0),  controllers.getControllerLocation(1), delta), delta)
					bodyRotationOffset = bodyYaw.updateAdvanced(bodyRotationOffset, currentHeadRotator.Yaw - decoupledYaw, controllers.getControllerLocation(2), controllers.getControllerLocation(0),  controllers.getControllerLocation(1), delta)
				else
					local aimMethod = getAimMethod() --getParameter("aimMethod")
					if pawnRotationMode == M.PawnRotationMode.LOCKED then
						bodyRotationOffset = smoothBodyRotationOffset(currentHeadRotator.Yaw - decoupledYaw, delta)
					elseif pawnRotationMode == M.PawnRotationMode.LEFT_CONTROLLER then
	--TODO this seems wrong. Why is aim affecting body rotation?
						local rotation = (aimMethod == M.AimMethod.LEFT_WEAPON and weaponRotation ~= nil and weaponRotation.left ~= nil) and weaponRotation.left or controllers.getControllerRotation(Handed.Left)
						--did this to fix robocop. what happens with hello neighbor?
						if rotation ~= nil then
							local final = aimMethod ~= M.AimMethod.LEFT_WEAPON and getAimOffsetAdjustedRotation(rotation) or rotation
							bodyRotationOffset = smoothBodyRotationOffset(final.Yaw - decoupledYaw, delta)
						end
						--if rotation ~= nil then bodyRotationOffset = rotation.Yaw - decoupledYaw end
					elseif pawnRotationMode == M.PawnRotationMode.RIGHT_CONTROLLER then
	--TODO this seems wrong. Why is aim affecting body rotation?
						local rotation = (aimMethod == M.AimMethod.RIGHT_WEAPON and weaponRotation ~= nil and weaponRotation.right ~= nil) and weaponRotation.right or controllers.getControllerRotation(Handed.Right)
	--					local rotation = controllers.getControllerRotation(Handed.Right)
						--did this to fix robocop. what happens with hello neighbor? (even though hello neighbor doesnt need gunstock adjustments)
						if rotation ~= nil then
							local final = aimMethod ~= M.AimMethod.RIGHT_WEAPON and getAimOffsetAdjustedRotation(rotation) or rotation
							bodyRotationOffset = smoothBodyRotationOffset(final.Yaw - decoupledYaw, delta)
						end
						--if rotation ~= nil then bodyRotationOffset = rotation.Yaw - decoupledYaw end
					end
				end
				local ok, err = pcall(function()
					if currentOffset ~= bodyRotationOffset and rootComponent.K2_SetWorldRotation ~= nil then
						rootComponent:K2_SetWorldRotation(uevrUtils.rotator(0,decoupledYaw+bodyRotationOffset,0),false,reusable_hit_result,false)
					end
				end)
				if not ok then
					M.print("Error setting world rotation: " .. err)
				end
				return
			end
			if delta ~= nil then
				if pawnRotationMode == M.PawnRotationMode.SIMPLE then
					bodyRotationOffset = bodyYaw.update(bodyRotationOffset, currentHeadRotator.Yaw - decoupledYaw, delta)
				elseif pawnRotationMode == M.PawnRotationMode.ADVANCED then
					--bodyRotationOffset = smoothBodyRotationOffset(bodyYaw.updateAdvanced(bodyRotationOffset, currentHeadRotator.Yaw - decoupledYaw, controllers.getControllerLocation(2), controllers.getControllerLocation(0),  controllers.getControllerLocation(1), delta), delta)
					bodyRotationOffset = bodyYaw.updateAdvanced(bodyRotationOffset, currentHeadRotator.Yaw - decoupledYaw, controllers.getControllerLocation(2), controllers.getControllerLocation(0),  controllers.getControllerLocation(1), delta)
				end
				-- record last real tick time for fallback smoothing when delta is unavailable
				--lastBodyYawUpdateTime = os.clock()
			else
				local aimMethod = getAimMethod() --getParameter("aimMethod")
				if pawnRotationMode == M.PawnRotationMode.LOCKED then
					bodyRotationOffset = smoothBodyRotationOffset(currentHeadRotator.Yaw - decoupledYaw, delta)
				elseif pawnRotationMode == M.PawnRotationMode.LEFT_CONTROLLER then
--TODO this seems wrong. Why is aim affecting body rotation?
					local rotation = (aimMethod == M.AimMethod.LEFT_WEAPON and weaponRotation ~= nil and weaponRotation.left ~= nil) and weaponRotation.left or controllers.getControllerRotation(Handed.Left)
					--did this to fix robocop. what happens with hello neighbor?
					if rotation ~= nil then
						local final = aimMethod ~= M.AimMethod.LEFT_WEAPON and getAimOffsetAdjustedRotation(rotation) or rotation
						bodyRotationOffset = smoothBodyRotationOffset(final.Yaw - decoupledYaw, delta)
					end
					--if rotation ~= nil then bodyRotationOffset = rotation.Yaw - decoupledYaw end
				elseif pawnRotationMode == M.PawnRotationMode.RIGHT_CONTROLLER then
--TODO this seems wrong. Why is aim affecting body rotation?
					local rotation = (aimMethod == M.AimMethod.RIGHT_WEAPON and weaponRotation ~= nil and weaponRotation.right ~= nil) and weaponRotation.right or controllers.getControllerRotation(Handed.Right)
--					local rotation = controllers.getControllerRotation(Handed.Right)
					--did this to fix robocop. what happens with hello neighbor? (even though hello neighbor doesnt need gunstock adjustments)
					if rotation ~= nil then
						local final = aimMethod ~= M.AimMethod.RIGHT_WEAPON and getAimOffsetAdjustedRotation(rotation) or rotation
						bodyRotationOffset = smoothBodyRotationOffset(final.Yaw - decoupledYaw, delta)
					end
					--if rotation ~= nil then bodyRotationOffset = rotation.Yaw - decoupledYaw end
				end
			end
			local ok, err = pcall(function()
				if currentOffset ~= bodyRotationOffset and rootComponent.K2_SetWorldRotation ~= nil then
					rootComponent:K2_SetWorldRotation(uevrUtils.rotator(0,decoupledYaw+bodyRotationOffset,0),false,reusable_hit_result,false)
				end
			end)
			if not ok then
				M.print("Error setting world rotation: " .. err)
			end
		end
	else
		bodyRotationOffset = 0
	end
end
updateBodyYaw = uevrUtils.profiler:wrap("updateBodyYaw", updateBodyYaw)

function M.getRotationOffset()
	if decoupledYaw ~= nil and bodyRotationOffset ~= nil then
		return decoupledYaw+bodyRotationOffset
	end
	return 0
end

local function vectorRotate_Quat(vec, quat)
	return mathLib.vectorRotate_Quat(vec, quat, false)
end
vectorRotate_Quat = uevrUtils.profiler:wrap("Input vectorRotate_Quat", vectorRotate_Quat)

local function updatePawnPositionRoomscale(world_to_meters)
	local pawnPositionMode = getParameter("pawnPositionMode")
	if pawnPositionMode ~= M.PawnPositionMode.NONE and rootComponent ~= nil and decoupledYaw ~= nil then
		uevr.params.vr.get_standing_origin(temp_vec3f)

		local origin = {X=temp_vec3f.X,Y=temp_vec3f.Y,Z=temp_vec3f.Z}
		temp_quatf:set(0,0,0,0)
		uevr.params.vr.get_pose(uevr.params.vr.get_hmd_index(), temp_vec3f, temp_quatf)

		--delta is how much the real world position of the hmd is changed from the real world origin
		local delta = {X=(temp_vec3f.X-origin.X)*world_to_meters, Y=(temp_vec3f.Y-origin.Y)*world_to_meters, Z=(temp_vec3f.Z-origin.Z)*world_to_meters}
		-- local dist = delta.X*delta.X + delta.Y*delta.Y
		-- print(dist)
		-- temp_quatf contains how much the rotation of the hmd is relative to the real world vr coordinate system
		--local poseQuat = uevrUtils.quat(temp_quatf.Z, temp_quatf.X, -temp_quatf.Y, -temp_quatf.W)  --reordered terms to convert UEVR to unreal coord system
		--local poseRotator = kismet_math_library:Quat_Rotator(poseQuat)
		--print("POSE",poseRotator.Pitch, poseRotator.Yaw, poseRotator.Roll) --this is in the Unreal coord system

		temp_quatf:set(0,0,0,0)
		uevr.params.vr.get_rotation_offset(temp_quatf) --This is how much the head was twisted from the pose quat the last time "recenter view" was performed
		--local headQuat = uevrUtils.quat(temp_quatf.Z, temp_quatf.X, -temp_quatf.Y, temp_quatf.W) --reordered terms to convert UEVR to unreal coord system
		--local headRotator = kismet_math_library:Quat_Rotator(headQuat)
		--print("HEAD",headRotator.Pitch, headRotator.Yaw, headRotator.Roll) --this is in the Unreal coord system

		--rotate the delta by the amount of the hmd offset
		
		local forwardVector = vectorRotate_Quat({X=-delta.Z, Y=delta.X, Z=delta.Y}, {X=temp_quatf.Z, Y=temp_quatf.X, Z=-temp_quatf.Y, W=temp_quatf.W}) -- kismet_math_library:Quat_RotateVector(headQuat, uevrUtils.vector(-delta.Z, delta.X, delta.Y)) --converts UEVR to Unreal coord system
		--local forwardVector = vectorRotate_Quat(headQuat, uevrUtils.vector(-delta.Z, delta.X, delta.Y)) -- kismet_math_library:Quat_RotateVector(headQuat, uevrUtils.vector(-delta.Z, delta.X, delta.Y)) --converts UEVR to Unreal coord system

		--add the decoupledYaw yaw rotation to the delta vector
		forwardVector = kismet_math_library:RotateAngleAxis( forwardVector,  decoupledYaw, uevrUtils.vector(0,0,1))
		--local dist = forwardVector.X*forwardVector.X + forwardVector.Y*forwardVector.Y
		--if dist > 2.0 then
			--print("Here",dist)
			forwardVector.Z = 0 --do not affect up/down
			local ok, err = pcall(function()
				if pawnPositionMode == M.PawnPositionMode.ANIMATED  then
				local pawn = status.pawn
				if pawn ~= nil and pawn.AddMovementInput ~= nil then
						pawn:AddMovementInput(forwardVector, getParameter("pawnPositionAnimationScale"), false) --dont need to check for pawn because if rootComponent exists then pawn exists
					end
				elseif pawnPositionMode == M.PawnPositionMode.FOLLOWS and rootComponent.K2_AddWorldOffset ~= nil then
					--pcall(function()
					if uevrUtils.getValid(rootComponent) ~= nil then
						rootComponent:K2_AddWorldOffset(forwardVector, getParameter("pawnPositionSweepMovement"), reusable_hit_result, false)
					end
					--end)
					--rootComponent:K2_SetWorldLocation(uevrUtils.vector(pawnPos.X+forwardVector.X,pawnPos.Y+forwardVector.Y,pawnPos.Z),pawnPositionSweepMovement,reusable_hit_result,false)
				end
			end)
			if not ok then
				M.print("Error setting world offset: " .. err)
			end

			--temp_vec3f has the get_pose location
			temp_vec3f.Y = origin.Y --dont affect the up_down position
			uevr.params.vr.set_standing_origin(temp_vec3f)
		--end
	end
end
updatePawnPositionRoomscale = uevrUtils.profiler:wrap("updatePawnPositionRoomscale", updatePawnPositionRoomscale)

function M.getHeadOffset()
	if isDisabled then
		return uevrUtils.vector(0,0,0)
	end
	return uevrUtils.vector(getParameter("headOffset"))
end

local function updateMeshRelativePosition(setDisabled)
	if setDisabled then
		local meshList = getBodyMesh()
		if  meshList ~= nil then
			for _, mesh in ipairs(meshList) do
				if uevrUtils.getValid(mesh) ~= nil and mesh.RelativeLocation ~= nil then
					--mesh.RelativeLocation.X = 0
					--mesh.RelativeLocation.Y = 0
					uevrUtils.setComponentRelativeLocation(mesh, 0, 0, nil)
				end
			end
			uevrUtils.executeUEVRCallbacks("on_input_mesh_relative_position_change", 0, 0)
			return
		end
	end

	if status.meshRelativePositionDisabled == true then return end

	if rootComponent ~= nil and decoupledYaw ~= nil then
		local meshList = getBodyMesh()
		if meshList ~= nil then
			local ok, err = pcall(function()
				--the next line can fail even when checking for rootComprootComponent.K2_GetComponentRotation ~= nil so wrap in pcall
				local pawnRot = rootComponent:K2_GetComponentRotation()
				local animationDelta = getAnimationHeadDelta(status.pawn, pawnRot.Yaw)
				local eyeOffsetDelta = getEyeOffsetDelta(status.pawn, pawnRot.Yaw)

				local headOffset = M.getHeadOffset() --uevrUtils.vector(getParameter("headOffset"))

				-- headOffset is relative and mesh.RelativeLocation is getting set. Why was I calculating a forward vector?
				--temp_vec3:set(0, 0, 1) --the axis to rotate around
				--local forwardVector = kismet_math_library:RotateAngleAxis(headOffset, pawnRot.Yaw - bodyRotationOffset - decoupledYaw, temp_vec3)
				local forwardVector = headOffset or {X=0, Y=0}
				local x = -forwardVector.X
				local y = -forwardVector.Y
				if animationDelta ~= nil and eyeOffsetDelta ~= nil then
					x = x + animationDelta.X + eyeOffsetDelta.X
					y = y - animationDelta.Y - eyeOffsetDelta.Y
				end

				if animationDelta ~= nil and getParameter("useMeshHeightForHeadOffset") and status["meshZOffset"] == nil then
					status["meshZOffset"] = animationDelta.Z / 2 - 90 + (headOffset and headOffset.Z or 0)
					--print("Calculated meshZOffset:", status["meshZOffset"])
				end
				--dont worry about Z here. Z is applied directly to the RootComponent later
				--print("Setting mesh relative location to", mesh:get_full_name(), x, y)
				for _, mesh in ipairs(meshList) do
					mesh.RelativeLocation.X = x
					mesh.RelativeLocation.Y = y
				end
				uevrUtils.executeUEVRCallbacks("on_input_mesh_relative_position_change", x, y)
			end)
			if not ok then
				M.print("Error setting mesh relative position: " .. err)
			end
		end
	end
end
updateMeshRelativePosition = uevrUtils.profiler:wrap("updateMeshRelativePosition", updateMeshRelativePosition)

function M.updateMeshRelativePosition(setDisabled)
	updateMeshRelativePosition(setDisabled)
end

function M.setAimRotationOffset(offset)
	aimRotationOffset = uevrUtils.rotator(offset)
end

function M.getAimRotationOffset()
	return aimRotationOffset
end
	
function M.setWeaponRotation(leftRotation, rightRotation)
	weaponRotation = {
		left = uevrUtils.rotator(leftRotation),
		right = uevrUtils.rotator(rightRotation)
	}
	-- if weaponRotation.right ~= nil then
	-- 	weaponRotation.right.Yaw = weaponRotation.right.Yaw + 90
	-- 	local roll = weaponRotation.right.Pitch
	-- 	weaponRotation.right.Pitch = -weaponRotation.right.Roll
	-- 	weaponRotation.right.Roll = roll
	-- end
	--print("Weapon Rotation Set", weaponRotation.left.Pitch, weaponRotation.left.Yaw, weaponRotation.left.Roll, weaponRotation.right.Pitch, weaponRotation.right.Yaw, weaponRotation.right.Roll)
end

local function updateIsDisabled()
	local disabled = getParameter("isDisabledOverride") or executeIsDisabledCallback() or false
	if isDisabled ~= disabled then
		isDisabled = disabled
		--uevr.params.vr.recenter_view()
		uevrUtils.executeUEVRCallbacks("recenter_view")
		if preventPawnSettingsResetOnDisable == false then
			resetPawnSettings()
		end
		updateMeshRelativePosition(true)
	end
end

local function applyPlayerControllerRotationOverrides()
	local overridePitch = getParameter("overridePlayerControllerPitch") == true
	local overrideYaw = getParameter("overridePlayerControllerYaw") == true
	local overrideRoll = getParameter("overridePlayerControllerRoll") == true
	if not overridePitch and not overrideYaw and not overrideRoll then
		return
	end

	local playerController = uevr.api:get_player_controller(0)
	if playerController == nil or playerController.GetControlRotation == nil or playerController.SetControlRotation == nil then
		return
	end

	local cr = playerController:GetControlRotation()
	if cr == nil then
		return
	end

	if overridePitch then
		cr.Pitch = tonumber(getParameter("overridePlayerControllerPitchValue")) or 0
	end
	if overrideYaw then
		cr.Yaw = tonumber(getParameter("overridePlayerControllerYawValue")) or 0
	end
	if overrideRoll then
		cr.Roll = tonumber(getParameter("overridePlayerControllerRollValue")) or 0
	end

	playerController:SetControlRotation(cr)
end

uevr.sdk.callbacks.on_pre_engine_tick(function(engine, delta)
	--set the global rootComponent variable on the earliest tick callback so it will be valid everywhere

	--calculate the controller rotation here so it is available for updateBodyYaw and updateAim?

	updateIsDisabled()
	if not isDisabled then --and getParameter("aimMethod") ~= M.AimMethod.UEVR then
		getRootComponent()
		initDecoupledYaw()
		updatePawnSettings()
		updateAim()
		updateBodyYaw(delta)
		applyPlayerControllerRotationOverrides()
	else
		--print("Input is disabled")
	end

end)

local function getVRCameraOffsets()
	--if bodyRotationOffset ~= nil and rootComponent ~= nil and uevrUtils.getValid(rootComponent) ~= nil and rootComponent.K2_GetComponentLocation ~= nil then
	local rootOffset = getParameter("rootOffset")
	if rootOffset ~= nil then
		if status.rootComponent ~= nil and uevrUtils.getValid(rootComponent) ~= nil and status.rootComponent.K2_GetComponentLocation ~= nil then
			local pawnPos = uevrUtils.getComponentLocation(status.rootComponent)
			local pawnRot = uevrUtils.getComponentRotation(status.rootComponent)

			local capsuleHeight = status.rootComponent.CapsuleHalfHeight or 0

			local forwardVector = {X=0,Y=0,Z=0}
			if pawnRot ~= nil and (rootOffset.X ~= 0 or rootOffset.Y ~= 0  or rootOffset.Z ~= 0) then
				temp_vec3f:set(rootOffset.X, rootOffset.Y, rootOffset.Z) -- the vector representing the offset adjustment
				temp_vec3:set(0, 0, 1) --the axis to rotate around
				forwardVector = kismet_math_library:RotateAngleAxis(temp_vec3f, pawnRot.Yaw - (bodyRotationOffset or 0), temp_vec3)
			end
			--print("Current",status["meshZOffset"])
			if pawnPos == nil or pawnRot == nil then return nil, nil, nil, nil, nil, nil end
			return  pawnPos.x + forwardVector.X, pawnPos.y + forwardVector.Y, pawnPos.z + rootOffset.Z + capsuleHeight + getParameter("headOffset").Z + (status["meshZOffset"] or 0), 0, pawnRot.Yaw - (bodyRotationOffset or 0), 0
		end
	end
	return nil, nil, nil, nil, nil, nil
end
getVRCameraOffsets = uevrUtils.profiler:wrap("getVRCameraOffsets", getVRCameraOffsets)

--native stereo uses view_index 1 and 2
--AFW uses only 1
uevr.params.sdk.callbacks.on_early_calculate_stereo_view_offset(function(device, view_index, world_to_meters, position, rotation, is_double)
	if not isDisabled then --and getParameter("aimMethod") ~= M.AimMethod.UEVR then
		--print(optimizeBodyYawCalculations == false, getParameter("optimizeBodyRotationCalculations") ~= true, view_index)
		if isRotationModeEarlyUpdateDisabled() == false and lateYaw == false and (optimizeBodyYawCalculations == false or getParameter("optimizeBodyRotationCalculations") ~= true or view_index == 1) then
			updateBodyYaw()
		end
		--print(view_index)
		if getParameter("optimizeBodyLocationCalculations") ~= true or view_index == 1 then
			updatePawnPositionRoomscale(world_to_meters)
		end

		if lateYaw == false and view_index == 1 and M.isBodyMeshPositionAdjustmentAllowed() then
			updateMeshRelativePosition()
		end

		--Change the UEVR camera position and rotation to align with the pawn
		local x, y, z, pitch, yaw, roll = getVRCameraOffsets()
		if getRootOffsetEnabled() then
			if x ~= nil then position.x = x end
			if y ~= nil then position.y = y end
			if z ~= nil then position.z = z end
		end
		if getPawnRotationMode() ~= M.PawnRotationMode.NONE and isRotationModeRotationDisabled() ~= true then --getParameter("pawnRotationModeDisableRotation") ~= true then
			if pitch ~= nil then rotation.Pitch = pitch end
			if yaw ~= nil then rotation.Yaw = yaw end
			if roll ~= nil then rotation.Roll = roll end
		end

		-- local pawnRotationMode = getPawnRotationMode() -- getParameter("pawnRotationMode")
		-- if pawnRotationMode ~= M.PawnRotationMode.NONE then
		-- 	--Change the UEVR camera position and rotation to align with the pawn
		-- 	local x, y, z, pitch, yaw, roll = getVRCameraOffsets()
		-- 	position.x = x
		-- 	position.y = y
		-- 	position.z = z
		-- 	if isRotationModeRotationDisabled() ~= true then --getParameter("pawnRotationModeDisableRotation") ~= true then
		-- 		rotation.Pitch = pitch
		-- 		rotation.Yaw = yaw
		-- 		rotation.Roll = roll
		-- 	end
		-- end

		--Change the UEVR camera position and rotation to align with the pawn
		-- if bodyRotationOffset ~= nil and rootComponent ~= nil and uevrUtils.getValid(rootComponent) ~= nil and rootComponent.K2_GetComponentLocation ~= nil then
		-- 	local pawnPos = rootComponent:K2_GetComponentLocation()
		-- 	local pawnRot = rootComponent:K2_GetComponentRotation()

		-- 	local capsuleHeight = rootComponent.CapsuleHalfHeight or 0

		-- 	local forwardVector = {X=0,Y=0,Z=0}
		-- 	local rootOffset = getParameter("rootOffset")
		-- 	if rootOffset ~= nil then
		-- 		if rootOffset.X ~= 0 and rootOffset.Y ~= 0 then
		-- 			temp_vec3f:set(rootOffset.X, rootOffset.Y, rootOffset.Z) -- the vector representing the offset adjustment
		-- 			temp_vec3:set(0, 0, 1) --the axis to rotate around
		-- 			forwardVector = kismet_math_library:RotateAngleAxis(temp_vec3f, pawnRot.Yaw - bodyRotationOffset, temp_vec3)
		-- 		end

		-- 		position.x = pawnPos.x + forwardVector.X
		-- 		position.y = pawnPos.y + forwardVector.Y
		-- 		position.z = pawnPos.z + rootOffset.Z + capsuleHeight + getParameter("headOffset").Z
		-- 		rotation.Pitch = 0--pawnRot.Pitch 
		-- 		rotation.Yaw = pawnRot.Yaw - bodyRotationOffset
		-- 		rotation.Roll = 0--pawnRot.Roll 	

		-- 	end
		-- end
	else
		--print("Input disabled")
	end

	--Change the UEVR camera position and rotation to align with the pawn root component
	-- if rootComponent ~= nil then
	-- 	local offsetYaw = 0
	-- 	if not isDisabled and aimMethod ~= M.AimMethod.UEVR and bodyRotationOffset ~= nil then
	-- 		offsetYaw = bodyRotationOffset
	-- 	end

	-- 	local pawnPos = rootComponent:K2_GetComponentLocation()	
	-- 	local pawnRot = rootComponent:K2_GetComponentRotation()					

	-- 	temp_vec3f:set(rootOffset.X, rootOffset.Y, rootOffset.Z) -- the vector representing the offset adjustment
	-- 	temp_vec3:set(0, 0, 1) --the axis to rotate around
	-- 	local forwardVector = kismet_math_library:RotateAngleAxis(temp_vec3f, pawnRot.Yaw - offsetYaw, temp_vec3)

	-- 	position.x = pawnPos.x + forwardVector.X
	-- 	position.y = pawnPos.y + forwardVector.Y
	-- 	position.z = pawnPos.z + forwardVector.Z

	-- 	rotation.Pitch = 0--pawnRot.Pitch 
	-- 	rotation.Yaw = pawnRot.Yaw - offsetYaw
	-- 	rotation.Roll = 0--pawnRot.Roll 	
	-- end

end)

uevr.sdk.callbacks.on_post_calculate_stereo_view_offset(function(device, view_index, world_to_meters, position, rotation, is_double)
	--currentHeadRotator = rotation -- this doesnt work	
	if not isDisabled then
		currentHeadRotator.Pitch = rotation.Pitch
		currentHeadRotator.Yaw = rotation.Yaw
		currentHeadRotator.Roll = rotation.Roll
	end
end)


uevr.sdk.callbacks.on_post_engine_tick(function(engine, delta)
	if lateYaw then
		if not isDisabled then
			updateBodyYaw(delta)
			--updateBodyYaw()
			updateMeshRelativePosition()
		end
	end

	-- if not isDisabled then --and pawnRotationMode ~= M.PawnRotationMode.NONE then
	-- 	if decoupledYaw~= nil and rootComponent ~= nil then
	-- 		rootComponent:K2_SetWorldRotation(uevrUtils.rotator(0,decoupledYaw+bodyRotationOffset,0),false,reusable_hit_result,false)
	-- 	end
	-- end

end)

--without this the right controller left/right stick movement does nothing
uevr.sdk.callbacks.on_xinput_get_state(function(retval, user_index, state)
	--local pawnRotationMode = getPawnRotationMode() -- getParameter("pawnRotationMode")
	if not isDisabled then --and pawnRotationMode ~= M.PawnRotationMode.NONE then	
		if rootComponent ~= nil and isRotationModeRotationDisabled() ~= true then --getParameter("pawnRotationModeDisableRotation") ~= true then
			local yawChange = updateDecoupledYaw(state)
			if decoupledYaw ~= nil and yawChange ~= 0 then
				rootComponent:K2_SetWorldRotation(uevrUtils.rotator(0,decoupledYaw+bodyRotationOffset,0),false,reusable_hit_result,false)
			end
		end
	end
end)


-- register_key_bind("F1", function()
    -- print("F1 pressed\n")
	-- --pawn:StartBulletTime(0.0, 50.0, false, 1.0, 0.4, 2.0)
	-- --rootComponent:K2_SetWorldLocation(uevrUtilsvector(lastPosition),false,reusable_hit_result,false)
	-- local rootComponent = uevrUtils.getValid(pawn,{"RootComponent"})
	-- if rootComponent ~= nil then
		-- rootComponent:K2_AddWorldOffset(uevrUtils.vector(deltaX,deltaY,0), true, reusable_hit_result, false);
	-- end
-- end)

local function reset()
	status = {}
	decoupledYaw = nil
	bodyRotationOffset = 0
	lastBodyYawUpdateTime = nil
	forcedBodyYaw = nil
	bodyYawWritesSuppressed = false
	lastSuppressedBodyYaw = nil
	bodyMesh = nil
	--localPawn = nil
	cameraComponent:reset()
	resetPawnSettings()
	updateMeshRelativePosition(true)
end

function M.reset()
	reset()
end

uevrUtils.registerPreLevelChangeCallback(function(level)
	decoupledYaw = nil
	bodyRotationOffset = 0
	lastBodyYawUpdateTime = nil
	bodyMesh = nil
	cameraComponent:reset()
end)

uevr.params.sdk.callbacks.on_script_reset(function()
	reset()
end)

function M.resetView()
	decoupledYaw = nil
	bodyRotationOffset = 0
	lastBodyYawUpdateTime = nil
end

uevrUtils.registerUEVRCallback("recenter_view", function()
	M.resetView()
end)

uevrUtils.registerLevelChangeCallback(function(level)
	status = {}
	decoupledYaw = nil
	bodyRotationOffset = 0
	lastBodyYawUpdateTime = nil
	bodyMesh = nil
	if getParameter("aimMethod") ~= M.AimMethod.UEVR then
		controllers.createController(0)
		controllers.createController(1)
		controllers.createController(2)
	end

	doFixSpatialAudio()
end)

uevrUtils.registerUEVRCallback("gunstock_transform_change", function(id, newLocation, newRotation, newOffhandLocationOffset)
	--only handle gunstock transform changes if aim method is left or right controller since
	--if its left or right weapon, the weapon already has the gunstock adjustments applied
    local aimMethod = getAimMethod() --getParameter("aimMethod")
	if aimMethod == M.AimMethod.LEFT_CONTROLLER or aimMethod == M.AimMethod.RIGHT_CONTROLLER then
		M.setAimRotationOffset(newRotation)
	end
end)

uevrUtils.registerUEVRCallback("on_pawn_param_change", function(name, value)
	--if the pawn body mesh changes, clear the cached bodyMesh variable so a new one can be obtained on the next tick
	if name == "bodyMeshName" or name == "profile" then
		bodyMesh = nil
		status.pawn = nil
	end
end)

uevrUtils.registerUEVRCallback("attachment_grip_rotation_change", function(leftRotation, rightRotation)
	M.setWeaponRotation(leftRotation, rightRotation)
end)

function M.setCurrentProfile(profileID)
	paramManager:setActiveProfile(profileID)
	--if the profile changes, reset the camera component to ensure its using the correct settings
	reset()
	--resetPawnSettings()
end

function M.setCurrentProfileByLabel(profileLabel)
	local profileIDs, profileNames = paramManager:getProfiles()
	for i, name in ipairs(profileNames) do
		if name == profileLabel then
			M.setCurrentProfile(profileIDs[i])
			return
		end
	end
end


return M

	-- local controllerID = 1
	-- local rotation1 = controllers.getControllerRotation(controllerID)
	-- local direction1 = controllers.getControllerDirection(controllerID)
	-- local location1 = controllers.getControllerLocation(controllerID)
	-- local rotation2 = nil
	-- local location2 = nil
	-- local direction2 = nil
	-- local index = uevrUtils.getControllerIndex(controllerID)
	-- if index ~= nil then
		-- uevr.params.vr.get_pose(index, temp_vec3f, temp_quatf)
		-- local poseQuat = uevrUtils.quat(temp_quatf.Z, temp_quatf.X, -temp_quatf.Y, -temp_quatf.W)  --reordered terms to convert UEVR to unreal coord system
		-- print(temp_quatf.X,temp_quatf.Y,temp_quatf.Z,temp_quatf.W)
		-- direction2 = kismet_math_library:Quat_RotateVector(poseQuat, uevrUtils.vector(1, 0, 0)) --converts UEVR to Unreal coord system
		-- location2 = uevrUtils.vector(temp_vec3f.X*100,temp_vec3f.Z*100,temp_vec3f.Y*100)
		-- location2 = kismet_math_library:Quat_RotateVector(poseQuat,location2) --converts UEVR to Unreal coord system
		-- rotation2 = kismet_math_library:Quat_Rotator(poseQuat)
	-- end	
	-- uevr.params.vr.get_rotation_offset(temp_quatf) --This is how much the head was twisted from the pose quat the last time "recenter view" was performed
	-- local headQuat = uevrUtils.quat(temp_quatf.Z, temp_quatf.X, -temp_quatf.Y, temp_quatf.W) --reordered terms to convert UEVR to unreal coord system
	-- local headRotator = kismet_math_library:Quat_Rotator(headQuat)

	-- if rotation1 ~= nil then
		-- print("ROT1",rotation1.Pitch,rotation1.Yaw,rotation1.Roll)
	-- end
	-- -- if rotation2 ~= nil then
		-- -- print("ROT2",rotation2.Pitch,rotation2.Yaw,rotation2.Roll)
	-- -- end
	-- -- if location1 ~= nil then
		-- -- print("LOC1",location1.X,location1.Y,location1.Z)
	-- -- end
	-- -- if location2 ~= nil then
		-- -- print("LOC2",location2.X,location2.Y,location2.Z)
	-- -- end
	-- -- if direction1 ~= nil then
		-- -- print("DIR1",direction1.X,direction1.Y,direction1.Z)
	-- -- end
	-- -- if direction2 ~= nil then
		-- -- print("DIR2",direction2.X,direction2.Y,direction2.Z)
	-- -- end
	-- -- if headRotator ~= nil then
		-- -- print("HEAD",headRotator.Pitch,headRotator.Yaw,headRotator.Roll)
	-- -- end

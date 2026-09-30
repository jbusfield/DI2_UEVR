local uevrUtils = require("libs/uevr_utils")
local controllers = require("libs/controllers")
local attachments = require("libs/attachments")
--local paramModule = require("libs/core/params")
local accessoriesConfigDev = require("libs/config/accessories_config_dev")

local M = {}

local status = {}
local accessoryStatus = {}

-- Getting accessory parameters from config file currently
-- local parametersFileName = "accessories_parameters"
-- local parameters = {}
-- local paramManager = paramModule.new(parametersFileName, parameters, true)

-- Toggle for verbose marker/montage diagnostics.
-- Keep this false unless you are actively debugging marker timing/selection.
local MARKER_DEBUG = false
local function markerDebugPrint(msg)
	if MARKER_DEBUG then
		print(msg)
	end
end

if MARKER_DEBUG then
	print("[MarkerDebug] accessories.lua loaded; MARKER_DEBUG enabled")
end

local currentLogLevel = LogLevel.Error
function M.setLogLevel(val)
	currentLogLevel = val
end
function M.print(text, logLevel)
	if logLevel == nil then logLevel = LogLevel.Debug end
	if logLevel <= currentLogLevel then
		uevrUtils.print("[accessories] " .. text, logLevel)
	end
end

local isDisabled = false
function M.setDisabled(val)
	isDisabled = val
end

local releaseDelay = 0
function M.setReleaseDelay(seconds)
	seconds = tonumber(seconds)
	if seconds == nil or seconds < 0 or seconds == math.huge or seconds ~= seconds then return false end
	releaseDelay = seconds
	return true
end

-- A game may supply a non-attachment component and the accessory config key
-- associated with it. Games that do not set a provider keep the existing path.
local targetProvider = nil
local targetProviderErrorReported = false
function M.setTargetProvider(provider)
	if provider ~= nil and type(provider) ~= "function" then return false end
	if provider == nil and targetProvider ~= nil and accessoryStatus.targetAccessories ~= nil then
		for _, hand in ipairs({Handed.Left, Handed.Right}) do
			if accessoryStatus.targetAccessories[hand] ~= nil then
				M.attachHandToTargetAccessory(hand, nil)
			end
		end
	end
	targetProvider = provider
	targetProviderErrorReported = false
	return true
end

local function getProvidedTarget(hand)
	if targetProvider == nil then return nil, nil end
	local ok, target, configKey = pcall(targetProvider, hand)
	if not ok then
		if not targetProviderErrorReported then
			M.print("Target provider failed: " .. tostring(target), LogLevel.Error)
			targetProviderErrorReported = true
		end
		return nil, nil
	end
	targetProviderErrorReported = false
	return uevrUtils.getValid(target), configKey
end

function M.getPrimaryMarkerParams(accessoryParams)
	if accessoryParams == nil then return nil end
	if type(accessoryParams.markers) == "table" then
		return accessoryParams.markers[1]
	end
	return accessoryParams
end

function M.resolveMarkerParamsForTime(accessoryParams, currentTime)
	if accessoryParams == nil then return nil, nil end
	local markers = accessoryParams.markers
	if type(markers) ~= "table" then
		return accessoryParams, 1
	end
	if currentTime == nil then
		return markers[1], 1
	end

	local hasAnyRange = false
	local fallback = markers[1]
	for i, marker in ipairs(markers) do
		local startTime = marker.start_time or 0
		local endTime = marker.end_time or 0
		if startTime ~= 0 or endTime ~= 0 then
			hasAnyRange = true
			if currentTime >= startTime and currentTime <= endTime then
				return marker, i
			end
		else
			fallback = fallback or marker
		end
	end

	if hasAnyRange then
		return nil, nil
	end
	return fallback, 1
end

function M.accessoryHasTimeMarkers(accessoryParams)
	if accessoryParams == nil then return false end
	local markers = accessoryParams.markers
	if type(markers) == "table" then
		for _, marker in ipairs(markers) do
			local startTime = marker.start_time or 0
			local endTime = marker.end_time or 0
			if startTime ~= 0 or endTime ~= 0 then
				return true
			end
		end
		return false
	end
	local startTime = accessoryParams["start_time"] or 0
	local endTime = accessoryParams["end_time"] or 0
	return (startTime ~= 0 or endTime ~= 0)
end

function M.getAccessoryParams(accessoryID)
    return accessoriesConfigDev.getAccessoryParams(accessoryID)
    -- local accessoriesList = paramManager:get("accessories") or {}
    -- for attachmentID, accessories in pairs(accessoriesList) do
    --     for aID, accessoryParams in pairs(accessories) do
    --         if aID == accessoryID then
    --             return accessoryParams
    --         end
    --     end
    -- end
    -- return nil
end

function M.getAccessoriesForAttachment(attachmentID)
    return accessoriesConfigDev.getAccessoriesForAttachment(attachmentID)
    -- if attachmentID == nil or attachmentID == "" then
    --     return {}
    -- end
    -- return paramManager:get({"accessories", attachmentID}) or {}
end

function M.getAccessoryParamsForAttachment(attachmentID, accessoryID)
    return accessoriesConfigDev.getAccessoryParamsForAttachment(attachmentID, accessoryID)
    -- if attachmentID == nil or accessoryID == nil then
    --     return nil
    -- end
    -- local list = paramManager:get({"accessories", attachmentID})
    -- return list and list[accessoryID] or nil
end


local function checkMontageProximity(hand, accessoryParams, currentAttachment)
	local validDistance = true
	local activationHand = accessoryParams.activation_hand or 1
	if activationHand == 10 or (activationHand == 8 and hand == Handed.Left) or (activationHand == 9 and hand == Handed.Right) then
		return true
	end

	local activationDistance = accessoryParams.activation_distance or 0.0
	-- activation_hand:
	--  1=None
	--  2=Left Hand Proximity
	--  3=Right Hand Proximity
	--  4=Either Hand Proximity
	--  5=Left Hand Proximity During Montage Only
	--  6=Right Hand Proximity During Montage Only
	--  7=Either Hand Proximity During Montage Only
	--  8=Left Hand Always
	--  9=Right Hand Always
	-- 10=Either Hand Always
	local handOk =
		(activationHand == 4) or
		(activationHand == 2 and hand == Handed.Left) or
		(activationHand == 3 and hand == Handed.Right) or
		(activationHand == 7) or
		(activationHand == 5 and hand == Handed.Left) or
		(activationHand == 6 and hand == Handed.Right)
	if handOk and activationHand ~= 1 and activationDistance ~= nil and activationDistance > 0 then
		validDistance = false
		local controllerLoc = controllers.getControllerLocation(hand)
		if controllerLoc == nil then
			markerDebugPrint("[MarkerDebug] Proximity failed: controllerLoc nil; hand=" .. tostring(hand))
			return false
		end

		local targetLoc = nil
		local targetRot = nil
		local socketName = accessoryParams.socket_name or ""

		if socketName ~= "" and currentAttachment.GetSocketLocation ~= nil then
			targetLoc = currentAttachment:GetSocketLocation(uevrUtils.fname_from_string(socketName))
			targetRot = currentAttachment:GetSocketRotation(uevrUtils.fname_from_string(socketName))
		elseif currentAttachment.K2_GetComponentLocation ~= nil then
			targetLoc = currentAttachment:K2_GetComponentLocation()
			targetRot = currentAttachment:K2_GetComponentRotation()
		end
		if targetLoc ~= nil then
			targetLoc = targetLoc + uevrUtils.rotateVector(uevrUtils.vector(accessoryParams.location or {0,0,0}), targetRot)
			--targetLoc = targetLoc + uevrUtils.vector(accessoryParams.location or {0,0,0})
			local d = uevrUtils.distanceBetween(controllerLoc, targetLoc)
			if d ~= nil and d <= activationDistance then
				validDistance = true
			else
				markerDebugPrint("[MarkerDebug] Proximity failed: hand=" .. tostring(hand) ..
					" d=" .. tostring(d) ..
					" activationDistance=" .. tostring(activationDistance) ..
					" socket=" .. tostring(socketName))
			end
		else
			markerDebugPrint("[MarkerDebug] Proximity failed: targetLoc nil; hand=" .. tostring(hand) .. " socket=" .. tostring(socketName))
		end
	end
	return validDistance
end

local function executeIsRightAccessoryCallback(...)
	return uevrUtils.executeUEVRCallbacksWithPriorityResult("active_right_accessory", table.unpack({...}))
end

local function executeIsLeftAccessoryCallback(...)
	return uevrUtils.executeUEVRCallbacksWithPriorityResult("active_left_accessory", table.unpack({...}))
end

-- If on_accessory_attach will parent a component that is currently an ancestor of the
-- attachment, reparent the attachment to a MotionController first (KeepWorld) to avoid a
-- hierarchy cycle. Restore the original parent/relative offsets on accessory detach.
local restoreAttachmentFromParentCache

local function mcReparentPrint(msg)
	--print("[accessories][MCReparent] " .. tostring(msg))
end

local function getObjectName(obj)
	if obj == nil then return "nil" end
	local ok, name = pcall(function() return obj:get_full_name() end)
	if ok and name ~= nil then return tostring(name) end
	return tostring(obj)
end

local function describeParentChain(component)
	if component == nil then return "(nil component)" end
	local parts = { getObjectName(component) }
	local current = component.AttachParent
	local guard = 0
	while current ~= nil and guard < 64 do
		guard = guard + 1
		table.insert(parts, getObjectName(current))
		current = current.AttachParent
	end
	return table.concat(parts, " -> ")
end

local function collectUpcomingAttachComponents(handed)
	local upcoming = {}
	uevrUtils.executeUEVRCallbacks("accessory_attach_components", handed, upcoming)
	return upcoming
end

-- Returns the ancestor that matches an upcoming attach target, if any.
local function findUpcomingAttachAncestor(attachment, upcomingComponents)
	if uevrUtils.getValid(attachment) == nil or type(upcomingComponents) ~= "table" then
		return nil
	end
	if #upcomingComponents == 0 then
		mcReparentPrint("cycleCheck: no upcoming attach components reported")
		return nil
	end

	for i, component in ipairs(upcomingComponents) do
		mcReparentPrint("cycleCheck: upcoming[" .. tostring(i) .. "]=" .. getObjectName(component))
	end

	local current = attachment.AttachParent
	local guard = 0
	while current ~= nil and guard < 64 do
		guard = guard + 1
		for _, upcoming in ipairs(upcomingComponents) do
			if upcoming ~= nil and current == upcoming then
				mcReparentPrint("cycleCheck: HIT - ancestor depth " .. tostring(guard) .. " will be attached: " .. getObjectName(current))
				return current
			end
		end
		current = current.AttachParent
	end

	mcReparentPrint("cycleCheck: no upcoming attach target in parent chain")
	return nil
end

local function getGripMotionController(attachment)
	local gripHand = Handed.Right
	local attachmentData = attachments.getCurrentGrippedAttachmentData(Handed.Right)
	if attachmentData == nil or attachmentData.attachment ~= attachment then
		attachmentData = attachments.getCurrentGrippedAttachmentData(Handed.Left)
	end
	if attachmentData ~= nil and attachmentData.attachment == attachment and attachmentData.gripHand ~= nil then
		gripHand = attachmentData.gripHand
	end
	return controllers.getController(gripHand, true), gripHand
end

local function countOverrideHolders(override)
	if override == nil or type(override.holders) ~= "table" then return 0 end
	local count = 0
	for _, active in pairs(override.holders) do
		if active then count = count + 1 end
	end
	return count
end

local function ensureOverrideOnMotionController(override)
	if override == nil then return false end
	local attachment = uevrUtils.getValid(override.attachment)
	local mc = uevrUtils.getValid(override.motionController)
	if attachment == nil or mc == nil or attachment.K2_AttachTo == nil then
		return false
	end
	if attachment.AttachParent == mc then
		return true
	end
	mcReparentPrint("promote: drift detected; re-applying MC parent. current chain=" .. describeParentChain(attachment))
	local keepWorld = (EAttachLocation and EAttachLocation.KeepWorldPosition) or 1
	local ok, err = pcall(function()
		attachment:K2_AttachTo(mc, uevrUtils.fname_from_string(""), keepWorld, false)
	end)
	if not ok then
		mcReparentPrint("promote: FAILED drift re-apply: " .. tostring(err))
		return false
	end
	mcReparentPrint("promote: drift re-apply OK - new chain: " .. describeParentChain(attachment))
	return true
end

-- Shared override (not per-hand): both hands can hold the same gripped weapon. Restoring
-- when one hand detaches while the other still needs the MC parent causes snaps/spins.
restoreAttachmentFromParentCache = function(handed)
	local override = accessoryStatus["attachmentParentOverride"]
	if override == nil then
		mcReparentPrint("restore: no shared override")
		return
	end
	if type(override.holders) ~= "table" or override.holders[handed] ~= true then
		mcReparentPrint("restore: hand=" .. tostring(handed) .. " is not a holder")
		return
	end

	override.holders[handed] = nil
	local remaining = countOverrideHolders(override)
	if remaining > 0 then
		mcReparentPrint("restore: hand=" .. tostring(handed) .. " released; " .. tostring(remaining) .. " holder(s) remain — keeping MC parent")
		return
	end

	local attachment = uevrUtils.getValid(override.attachment)
	local parent = uevrUtils.getValid(override.parent)
	mcReparentPrint("restore: last holder hand=" .. tostring(handed) ..
		" attachment=" .. getObjectName(attachment) ..
		" parent=" .. getObjectName(parent) ..
		" socket=" .. tostring(override.socket) ..
		" loc=(" .. tostring(override.location and override.location.X) .. "," .. tostring(override.location and override.location.Y) .. "," .. tostring(override.location and override.location.Z) .. ")" ..
		" rot=(" .. tostring(override.rotation and override.rotation.Pitch) .. "," .. tostring(override.rotation and override.rotation.Yaw) .. "," .. tostring(override.rotation and override.rotation.Roll) .. ")")

	if attachment == nil then
		mcReparentPrint("restore: FAILED - cached attachment invalid")
	elseif parent == nil then
		mcReparentPrint("restore: FAILED - cached parent invalid")
	elseif attachment.K2_AttachTo == nil then
		mcReparentPrint("restore: FAILED - attachment has no K2_AttachTo")
	else
		local keepRelative = (EAttachLocation and EAttachLocation.KeepRelativeOffset) or 0
		local ok, err = pcall(function()
			attachment:K2_AttachTo(parent, uevrUtils.fname_from_string(override.socket or ""), keepRelative, false)
			uevrUtils.set_component_relative_transform(
				attachment,
				override.location or {0, 0, 0},
				override.rotation or {0, 0, 0},
				override.scale or {1, 1, 1}
			)
		end)
		if not ok then
			mcReparentPrint("restore: FAILED pcall: " .. tostring(err))
		else
			mcReparentPrint("restore: OK - new chain: " .. describeParentChain(attachment))
		end
	end

	accessoryStatus["attachmentParentOverride"] = nil
end

local function cacheAndReparentAttachmentToMotionController(handed, attachment)
	if uevrUtils.getValid(attachment) == nil then
		mcReparentPrint("promote: FAILED - attachment invalid; hand=" .. tostring(handed))
		return false
	end
	if attachment.K2_AttachTo == nil then
		mcReparentPrint("promote: FAILED - no K2_AttachTo on " .. getObjectName(attachment))
		return false
	end

	-- Offhand accessory on a weapon gripped by the other hand does not create an IK feedback
	-- loop: the weapon follows the grip-hand socket, while the offhand only reads that socket.
	-- Reparenting is only needed when the grip hand itself targets the attachment.
	local _, gripHand = getGripMotionController(attachment)
	if handed ~= gripHand then
		mcReparentPrint("promote: skip - accessory hand=" .. tostring(handed) .. " is not grip hand=" .. tostring(gripHand))
		return false
	end

	local override = accessoryStatus["attachmentParentOverride"]
	-- Same attachment already promoted: join as a holder and keep it on the MC.
	if override ~= nil and override.attachment == attachment then
		override.holders = override.holders or {}
		override.holders[handed] = true
		mcReparentPrint("promote: join existing override; hand=" .. tostring(handed) .. " holders=" .. tostring(countOverrideHolders(override)))
		return ensureOverrideOnMotionController(override)
	end

	-- Different attachment still overridden: release this hand's claim on the old one first.
	if override ~= nil and override.attachment ~= attachment then
		mcReparentPrint("promote: different attachment; releasing prior override claim for hand=" .. tostring(handed))
		restoreAttachmentFromParentCache(handed)
		override = accessoryStatus["attachmentParentOverride"]
		if override ~= nil then
			mcReparentPrint("promote: prior override still held by another hand; not promoting " .. getObjectName(attachment))
			return false
		end
	end

	mcReparentPrint("promote: hand=" .. tostring(handed) .. " attachment=" .. getObjectName(attachment) .. " chain=" .. describeParentChain(attachment))

	local upcoming = collectUpcomingAttachComponents(handed)
	local conflictingAncestor = findUpcomingAttachAncestor(attachment, upcoming)
	if conflictingAncestor == nil then
		mcReparentPrint("promote: skip - no hierarchy cycle risk")
		return false
	end

	local motionController, gripHand = getGripMotionController(attachment)
	if motionController == nil then
		mcReparentPrint("promote: FAILED - cycle risk with " .. getObjectName(conflictingAncestor) .. " but no MC for gripHand=" .. tostring(gripHand))
		return false
	end
	mcReparentPrint("promote: using gripHand=" .. tostring(gripHand) .. " MC=" .. getObjectName(motionController))

	local parent = attachment.AttachParent
	if parent == motionController then
		-- Second hand normally joins the shared override above. Hitting this means we're on the
		-- MC with no override to join — keep world pose and avoid caching MC-relative offsets
		-- as if they were the original grip-mesh transform (that snaps/spins on restore).
		mcReparentPrint("promote: skip - already on MC with no shared override to join")
		return false
	end

	if parent == nil then
		mcReparentPrint("promote: FAILED - AttachParent nil (cannot cache original parent)")
		return false
	end

	local socket = ""
	if attachment.AttachSocketName ~= nil and attachment.AttachSocketName.to_string ~= nil then
		socket = attachment.AttachSocketName:to_string() or ""
	end

	local scale = attachment.RelativeScale3D
	local loc = {
		X = attachment.RelativeLocation.X,
		Y = attachment.RelativeLocation.Y,
		Z = attachment.RelativeLocation.Z,
	}
	local rot = {
		Pitch = attachment.RelativeRotation.Pitch,
		Yaw = attachment.RelativeRotation.Yaw,
		Roll = attachment.RelativeRotation.Roll,
	}
	accessoryStatus["attachmentParentOverride"] = {
		attachment = attachment,
		parent = parent,
		socket = socket,
		location = loc,
		rotation = rot,
		scale = scale ~= nil and {X = scale.X, Y = scale.Y, Z = scale.Z} or {X = 1, Y = 1, Z = 1},
		motionController = motionController,
		holders = { [handed] = true },
	}

	mcReparentPrint("promote: caching parent=" .. getObjectName(parent) ..
		" socket=" .. tostring(socket) ..
		" loc=(" .. tostring(loc.X) .. "," .. tostring(loc.Y) .. "," .. tostring(loc.Z) .. ")" ..
		" rot=(" .. tostring(rot.Pitch) .. "," .. tostring(rot.Yaw) .. "," .. tostring(rot.Roll) .. ")" ..
		" conflict=" .. getObjectName(conflictingAncestor) ..
		" -> MC=" .. getObjectName(motionController))

	local keepWorld = (EAttachLocation and EAttachLocation.KeepWorldPosition) or 1
	local ok, err = pcall(function()
		attachment:K2_AttachTo(motionController, uevrUtils.fname_from_string(""), keepWorld, false)
	end)
	if not ok then
		accessoryStatus["attachmentParentOverride"] = nil
		mcReparentPrint("promote: FAILED K2_AttachTo pcall: " .. tostring(err))
		return false
	end
	mcReparentPrint("promote: OK - new chain: " .. describeParentChain(attachment))
	return true
end

-- While an accessory has promoted an attachment off its grip mesh, stop attachments.lua
-- from re-parenting it back onto the IK/hand mesh (which recreates the feedback loop).
uevrUtils.registerUEVRCallback("attachment_suppress_mesh_reattach", function(attachment, mesh)
	local override = accessoryStatus["attachmentParentOverride"]
	if override ~= nil and override.attachment == attachment then
		mcReparentPrint("suppress reattach: " .. getObjectName(attachment) .. " (override active, holders=" .. tostring(countOverrideHolders(override)) .. ")")
		return true
	end
end)
-------------------- End of reparenting logic --------------------

local function resolveAccessoryMarkerParamsForAttach(accessoryParams, useMontageProximity, animInstance, montageObject, markerIndexOverride, strictMontageTime)
	if accessoryParams == nil then return nil, nil end

	-- (1) Preview override / explicit marker selection
	if markerIndexOverride ~= nil then
		local markers = accessoryParams.markers
		if type(markers) == "table" and #markers > 0 then
			local idx = tonumber(markerIndexOverride) or 1
			if idx < 1 then idx = 1 end
			if idx > #markers then idx = #markers end
			return markers[idx], idx
		end
	end

	-- (2) Montage-time window selection
	if useMontageProximity then
		if animInstance == nil or montageObject == nil or animInstance.Montage_GetPosition == nil then
			if strictMontageTime then
				return nil, nil
			end
		else
			local ok, currentTime = pcall(function()
				return animInstance:Montage_GetPosition(montageObject)
			end)
			if ok then
				local markerParams, markerIndex = M.resolveMarkerParamsForTime(accessoryParams, currentTime)
				-- If any time windows exist but none match, resolveMarkerParamsForTime returns nil.
				-- Treat that as an intentional "detach".
				if markerParams == nil then
					return nil, nil
				end
				return markerParams, markerIndex
			elseif strictMontageTime then
				return nil, nil
			end
		end
	end

	-- (3) Default / non-windowed fallback
	local markerParams = M.getPrimaryMarkerParams(accessoryParams)
	return markerParams, (markerParams ~= nil and 1 or nil)
end

-- Attach a hand to an arbitrary scene component using an accessory stored under
-- configKey in accessories_parameters.json. The component is never treated as a
-- gripped attachment or reparented to a motion controller. Call with a nil
-- accessoryID to release the hand; call again to apply a new target or marker.
-- options: markerIndex, useMontageProximity, animInstance, montageObject,
--          strictMontageTime.
function M.attachHandToTargetAccessory(handed, accessoryID, targetComponent, configKey, options)
	if handed ~= Handed.Left and handed ~= Handed.Right then
		return false, "invalid hand"
	end

	accessoryStatus.targetAccessories = accessoryStatus.targetAccessories or {}
	local active = accessoryStatus.targetAccessories[handed]
	local activeKey = handed == Handed.Right and "activeRightAccessory" or "activeLeftAccessory"
	local function detach()
		if active == nil then return end
		uevrUtils.executeUEVRCallbacks("on_accessory_detach", handed)
		uevrUtils.executeUEVRCallbacks("on_accessory_animation", handed, nil)
		if type(accessoryStatus.gripAnimationOverride) == "table" then
			accessoryStatus.gripAnimationOverride[handed] = nil
		end
		accessoryStatus.targetAccessories[handed] = nil
	end

	if accessoryID == nil then
		detach()
		return true
	end

	local target = uevrUtils.getValid(targetComponent)
	if target == nil then
		detach()
		return false, "target must be a valid component"
	end
	if type(configKey) ~= "string" or configKey == "" then
		return false, "config key is required"
	end
	if options ~= nil and type(options) ~= "table" then
		return false, "options must be a table"
	end

	local accessoryParams = M.getAccessoryParamsForAttachment(configKey, accessoryID)
	if accessoryParams == nil then
		return false, "accessory not found under config key"
	end

	options = options or {}
	local markerParams, markerIndex = resolveAccessoryMarkerParamsForAttach(
		accessoryParams, options.useMontageProximity, options.animInstance,
		options.montageObject, options.markerIndex, options.strictMontageTime)
	if markerParams == nil then
		detach()
		return false, "no active marker"
	end
	local socketName = markerParams.socket_name or ""
	local hasSocketMethods = target.GetSocketLocation ~= nil and target.GetSocketRotation ~= nil
	if not hasSocketMethods and (socketName ~= "" or target.K2_GetComponentLocation == nil or target.K2_GetComponentRotation == nil) then
		detach()
		return false, "target cannot provide the configured transform"
	end
	if socketName ~= "" and target.GetSocketTransform == nil then
		return false, "target cannot provide socket transforms"
	end
	if options.useMontageProximity and not checkMontageProximity(handed, markerParams, target) then
		detach()
		return false, "hand is outside activation distance"
	end

	-- Release an attachment accessory before claiming the same hand. Normal
	-- attachment polling is suppressed while a target accessory is active.
	if active == nil and accessoryStatus[activeKey] ~= nil then
		M.attachHandToAccessory(handed, nil)
		accessoryStatus[activeKey] = nil
	end
	if status.montageMonitor ~= nil then
		status.montageMonitor[handed] = nil
		if next(status.montageMonitor) == nil then status.montageMonitor = nil end
	end

	uevrUtils.executeUEVRCallbacks("on_accessory_attach", handed, target,
		socketName, markerParams.attach_type or 0,
		markerParams.location or {0, 0, 0}, markerParams.rotation or {0, 0, 0})
	local gripAnim = markerParams.grip_animation
	uevrUtils.executeUEVRCallbacks("on_accessory_animation", handed,
		(type(gripAnim) == "string" and gripAnim ~= "") and gripAnim or nil)
	accessoryStatus.gripAnimationOverride = accessoryStatus.gripAnimationOverride or {}
	if type(gripAnim) == "string" and gripAnim ~= "" then
		accessoryStatus.gripAnimationOverride[handed] = {
			active = true, priority = tonumber(markerParams.grip_priority) or 1
		}
	else
		accessoryStatus.gripAnimationOverride[handed] = nil
	end
	accessoryStatus.targetAccessories[handed] = {
		accessoryID = accessoryID, target = target, configKey = configKey,
		markerIndex = markerIndex
	}
	return true
end

function M.attachHandToAccessory(handed, accessoryID, useMontageProximity, animInstance, montageObject, markerIndexOverride)
    if accessoryID == nil then
        --detach hand
		--print("Detaching hand ", handed, " from accessory")
        --local hand = M.getHandComponent(handed)
		--local statusKey = "hand_" .. tostring(handed)
		--if accessoryStatus[statusKey] ~= nil then
			markerDebugPrint("[MarkerDebug] Detaching hand=" .. tostring(handed) .. " (restoring previous parent/socket)")
			--restoreHandSnapshot(handed)
			restoreAttachmentFromParentCache(handed)
			uevrUtils.executeUEVRCallbacks("on_accessory_detach", handed)
		--end
		-- Reset grip animation to open hand
		--holdingAttachment[handed] = nil
		uevrUtils.executeUEVRCallbacks("on_accessory_animation", handed, nil)
		if type(accessoryStatus["gripAnimationOverride"]) == "table" then
			accessoryStatus["gripAnimationOverride"][handed] = nil
		end
		--M.updateAnimationState(handed)
    else
		--print("Attaching hand ", handed, " to accessory ", accessoryID)
        --local hand = M.getHandComponent(handed)
		--if hand ~= nil then
            local currentAttachment = attachments.getCurrentGrippedAttachment(Handed.Right)
           	if currentAttachment ~= nil then
				local attachmentID = attachments.getAttachmentIDFromAttachment(currentAttachment)
				local accessoryParams = (attachmentID ~= nil and attachmentID ~= "") and M.getAccessoryParamsForAttachment(attachmentID, accessoryID) or nil
				if accessoryParams == nil then
					accessoryParams = M.getAccessoryParams(accessoryID)
					if accessoryParams ~= nil then
						markerDebugPrint("[MarkerDebug] WARNING: accessoryID=" .. tostring(accessoryID) .. " not found under attachmentID=" .. tostring(attachmentID) .. "; using global lookup")
					end
				end

				if accessoryParams == nil then
					return
				end
				--check if we're using timelines with montages and if so, check if we have a valid time
				local markerParams = nil
				local markerIndex = nil
				markerParams, markerIndex = resolveAccessoryMarkerParamsForAttach(accessoryParams, useMontageProximity, animInstance, montageObject, markerIndexOverride)
				if markerParams == nil then
					local currentTime = nil
					if useMontageProximity and animInstance ~= nil and montageObject ~= nil and animInstance.Montage_GetPosition ~= nil then
						local ok, t = pcall(function()
							return animInstance:Montage_GetPosition(montageObject)
						end)
						if ok then currentTime = t end
					end
					markerDebugPrint("[MarkerDebug] Marker resolve returned nil; detaching. hand=" .. tostring(handed) ..
						" accessoryID=" .. tostring(accessoryID) ..
						" useMontageProximity=" .. tostring(useMontageProximity) ..
						" time=" .. tostring(currentTime) ..
						" markerIndexOverride=" .. tostring(markerIndexOverride))
					local markers = accessoryParams and accessoryParams.markers
					if type(markers) == "table" and #markers > 0 then
						for idx, m in ipairs(markers) do
							markerDebugPrint("[MarkerDebug]  marker[" .. tostring(idx) .. "] start=" .. tostring(m.start_time) ..
								" end=" .. tostring(m.end_time) ..
								" socket=" .. tostring(m.socket_name) ..
								" grip_animation=" .. tostring(m.grip_animation))
						end
					end
					-- outside any marker time range; detach
					M.attachHandToAccessory(handed, nil)
					return
				end

				--check proximity
				local proximityOK = true
				if useMontageProximity then proximityOK = checkMontageProximity(handed, markerParams, currentAttachment) end
				if proximityOK then
					markerDebugPrint("[MarkerDebug] Attaching hand=" .. tostring(handed) ..
						" accessoryID=" .. tostring(accessoryID) ..
						" markerIndex=" .. tostring(markerIndex) ..
						" socket=" .. tostring(markerParams.socket_name or "") ..
						" grip_animation=" .. tostring(markerParams.grip_animation))
					--local statusKey = "hand_" .. tostring(handed)
					-- Only snapshot the base state once per activation chain.
					-- if accessoryStatus[statusKey] == nil then
					-- 	saveHandSnapshot(handed, statusKey)
					-- end

					--attachHandToTarget(handed, currentAttachment, socketName, markerParams.attach_type or 0, markerParams.location or {0,0,0}, markerParams.rotation or {0,0,0})
					-- Flatten nested MC hierarchy once for a stable hand attach; restore on detach.
					cacheAndReparentAttachmentToMotionController(handed, currentAttachment)
					uevrUtils.executeUEVRCallbacks("on_accessory_attach", handed, currentAttachment, markerParams.socket_name or "", markerParams.attach_type or 0, markerParams.location or {0,0,0}, markerParams.rotation or {0,0,0})

					-- Set grip animation from accessory params
					local gripAnim = markerParams.grip_animation
					uevrUtils.executeUEVRCallbacks("on_accessory_animation", handed, (gripAnim and gripAnim ~= "") and gripAnim or nil)
					--holdingAttachment[handed] = (gripAnim and gripAnim ~= "") and gripAnim or nil
					accessoryStatus["gripAnimationOverride"] = accessoryStatus["gripAnimationOverride"] or {}
					if type(gripAnim) == "string" and gripAnim ~= "" then
						local p = tonumber(markerParams.grip_priority)
						if p == nil then p = 1 end
						accessoryStatus["gripAnimationOverride"][handed] = { active = true, priority = p }
					else
						accessoryStatus["gripAnimationOverride"][handed] = nil
					end
					--M.updateAnimationState(handed)
				elseif useMontageProximity then
					--stop the current montage
					--holdingAttachment[handed] = nil
					uevrUtils.executeUEVRCallbacks("on_accessory_animation", handed, nil)
					if type(accessoryStatus["gripAnimationOverride"]) == "table" then
						accessoryStatus["gripAnimationOverride"][handed] = nil
					end
					--M.updateAnimationState(handed)
					-- if handed == Handed.Left then
					-- 	accessoryStatus["leftProximityAnimationOverride"] = false
					-- else
					-- 	accessoryStatus["rightProximityAnimationOverride"] = false
					-- end
					--M.print("Hand is not within activation distance for this accessory.", LogLevel.Warning)
				end
            end
        --end
    end
    --M.print("Accessory ID: " .. tostring(accessoryID) .. " not found for attachment.", LogLevel.Warning)
end


-- Goal: re-apply current “active_*_accessory” when preview pokes,
-- even if the GUID didn’t change (so transforms update live).
local updateTargetAccessoryForHand
local function refreshAccessoryForHand(handed, force)
	local activeAccessory = nil
	if handed == Handed.Right then
		activeAccessory = select(1, executeIsRightAccessoryCallback())
	else
		activeAccessory = select(1, executeIsLeftAccessoryCallback())
	end

	local key = (handed == Handed.Right) and "activeRightAccessory" or "activeLeftAccessory"

	if force then
		-- Detach only when switching away from the current accessory. Re-applying the same
		-- one (preview slider tweaks) must not restore the weapon onto the IK mesh — that
		-- briefly recreates the hierarchy feedback loop and makes the arms go crazy.
		if accessoryStatus[key] ~= activeAccessory then
			M.attachHandToAccessory(handed, nil)
		end
		M.attachHandToAccessory(handed, activeAccessory)
		accessoryStatus[key] = activeAccessory
		return
	end

	-- Normal behavior (only on change)
	if activeAccessory ~= accessoryStatus[key] then
		accessoryStatus[key] = activeAccessory
		M.attachHandToAccessory(handed, activeAccessory)
	end
end

uevrUtils.registerUEVRCallback("on_accessory_preview_changed", function(handed, accessoryID, enabled, markerIndex)
	local targetAccessory = accessoryStatus.targetAccessories and accessoryStatus.targetAccessories[handed]
	if targetProvider == nil and targetAccessory ~= nil then
		if not enabled or accessoryID == targetAccessory.accessoryID then
			M.attachHandToTargetAccessory(handed, targetAccessory.accessoryID,
				targetAccessory.target, targetAccessory.configKey,
				{ markerIndex = enabled and markerIndex or nil })
		end
		return
	end
	if enabled and targetProvider ~= nil and accessoryID ~= nil then
		local target, configKey = getProvidedTarget(handed)
		if target ~= nil and configKey ~= nil and M.getAccessoryParamsForAttachment(configKey, accessoryID) ~= nil then
			M.attachHandToTargetAccessory(handed, accessoryID, target, configKey, { markerIndex = markerIndex })
			return
		end
	end
	if not enabled and targetProvider ~= nil and updateTargetAccessoryForHand ~= nil then
		local activeID, priority
		if handed == Handed.Right then
			activeID, priority = executeIsRightAccessoryCallback()
		else
			activeID, priority = executeIsLeftAccessoryCallback()
		end
		if updateTargetAccessoryForHand(handed, activeID, priority, true) then return end
	end
	if targetAccessory ~= nil then M.attachHandToTargetAccessory(handed, nil) end
	local key = (handed == Handed.Right) and "activeRightAccessory" or "activeLeftAccessory"
	if enabled then
		-- Same as refreshAccessoryForHand(force): only tear down when the accessory changes.
		-- Preview transform/socket tweaks poke this callback every update with the same ID.
		if targetAccessory == nil and accessoryStatus[key] ~= accessoryID then
			M.attachHandToAccessory(handed, nil)
		end
		M.attachHandToAccessory(handed, accessoryID, false, nil, nil, markerIndex)
		accessoryStatus[key] = accessoryID
		return
	end

	-- preview off: restore whatever the normal active accessory is
	refreshAccessoryForHand(handed, true)
end)

-----------------------------------------------------------

-- Proximity accessory activation ---------------------------------
local PROXIMITY_ACCESSORY_PRIORITY = 1

-- The first ten activation values are stored in existing game configs. Keep
-- their numbers; new hold and toggle choices are appended after them.
local activationClock = 0
local gripInput = {
	[Handed.Left] = { held = false, initialized = false, serial = 0, releases = 0, presses = {} },
	[Handed.Right] = { held = false, initialized = false, serial = 0, releases = 0, presses = {} },
}
local attachmentSelections = {}
local targetSelections = {}

uevrUtils.registerOnPreInputGetStateCallback(function(retval, userIndex, state)
	if userIndex ~= 0 or state == nil or state.Gamepad == nil
		or XINPUT_GAMEPAD_LEFT_SHOULDER == nil or XINPUT_GAMEPAD_RIGHT_SHOULDER == nil then return end
	for _, hand in ipairs({ Handed.Left, Handed.Right }) do
		local input = gripInput[hand]
		local button = hand == Handed.Left and XINPUT_GAMEPAD_LEFT_SHOULDER or XINPUT_GAMEPAD_RIGHT_SHOULDER
		local held = uevrUtils.isButtonPressed(state, button)
		if not input.initialized then
			input.initialized = true
		elseif held and not input.held then
			input.serial = input.serial + 1
			local location = controllers.getControllerLocation(hand)
			table.insert(input.presses, {
				serial = input.serial, time = activationClock,
				location = location and { X = location.X, Y = location.Y, Z = location.Z } or nil,
			})
			if #input.presses > 16 then table.remove(input.presses, 1) end
		elseif not held and input.held then
			input.releases = input.releases + 1
		end
		input.held = held
	end
end)

local function isActivationForHand(mode, hand)
	return (mode == 2 or mode == 11 or mode == 14) and hand == Handed.Left
		or (mode == 3 or mode == 12 or mode == 15) and hand == Handed.Right
		or mode == 4 or mode == 13 or mode == 16
end

local function gripDistance(handLocation, component, marker, attachmentID)
	if handLocation == nil then return nil end
	local socketName = marker.socket_name or ""
	local targetLoc, targetRot
	if socketName ~= "" and component.GetSocketLocation ~= nil and component.GetSocketRotation ~= nil then
		local socket = uevrUtils.fname_from_string(socketName)
		targetLoc = component:GetSocketLocation(socket)
		targetRot = component:GetSocketRotation(socket)
	elseif (socketName == "" or attachmentID ~= nil)
		and component.K2_GetComponentLocation ~= nil and component.K2_GetComponentRotation ~= nil then
		targetLoc = component:K2_GetComponentLocation()
		targetRot = component:K2_GetComponentRotation()
	end
	if targetLoc == nil or targetRot == nil then return nil end
	local offset = uevrUtils.vector(marker.location or { 0, 0, 0 })
	local offhandOffset = attachmentID and status.offhandOffset and status.offhandOffset[attachmentID]
	if offhandOffset ~= nil then
		local extra = uevrUtils.vector(offhandOffset)
		---@diagnostic disable-next-line: need-check-nil
		offset.X, offset.Y, offset.Z = offset.X + extra.X, offset.Y + extra.Y, offset.Z + extra.Z
	end
	return uevrUtils.distanceBetween(handLocation, targetLoc + uevrUtils.rotateVector(offset, targetRot))
end

local function closestAccessory(hand, component, attachmentID, list, handLocation, firstMode, lastMode)
	local bestID, bestMode, bestDistance
	for id, params in pairs(list) do
		local marker = M.getPrimaryMarkerParams(params) or params
		local mode = tonumber(marker.activation_hand) or 1
		if mode >= firstMode and mode <= lastMode and isActivationForHand(mode, hand) then
			local activationDistance = tonumber(marker.activation_distance) or 0
			if activationDistance > 0 then
				local distance = gripDistance(handLocation, component, marker, attachmentID)
				if distance ~= nil and distance <= activationDistance
					and (bestDistance == nil or distance < bestDistance) then
					bestID, bestMode, bestDistance = id, mode, distance
				end
			end
		end
	end
	return bestID, bestMode, bestDistance
end

local function selectAccessoryForSource(hand, component, configKey, list, selections, attachmentID)
	local input = gripInput[hand]
	local selection = selections[hand]
	if selection == nil or selection.component ~= component or selection.configKey ~= configKey then
		local prev = selections[hand]
		selection = {
			component = component, configKey = configKey, lastSerial = input.serial,
		}
		-- Allow a press just before the first 300 ms poll to start a grip.
		if prev == nil then
			for i = #input.presses, 1, -1 do
				local press = input.presses[i]
				if activationClock - press.time > 0.35 then break end
				selection.lastSerial = press.serial - 1
			end
		elseif prev.configKey == configKey then
			-- Same accessory set on a new component instance — keep latch and press cursor.
			selection.lastSerial = prev.lastSerial
			selection.activeID = prev.activeID
			selection.mode = prev.mode
			selection.outsideSince = prev.outsideSince
			selection.lastReleaseSerial = prev.lastReleaseSerial
		end
		selections[hand] = selection
	end

	local activeID, activeMode = selection.activeID, selection.mode
	local activeParams = activeID and list[activeID]
	local activeMarker = activeParams and (M.getPrimaryMarkerParams(activeParams) or activeParams)
	if activeMarker == nil or tonumber(activeMarker.activation_hand) ~= activeMode then
		activeID, activeMode, selection.outsideSince = nil, nil, nil
	end

	-- Grip toggles are polled every 300 ms. Multiple rising edges in that window
	-- (bounce, or a quick retry) used to activate then immediately deactivate.
	-- Net odd/even presses, and retry proximity while still held.
	local releasedToggle = false
	local pendingPresses = 0
	local latestPress = nil
	for _, press in ipairs(input.presses) do
		if press.serial > selection.lastSerial then
			pendingPresses = pendingPresses + 1
			latestPress = press
		end
	end
	if pendingPresses > 0 then
		local toggleActive = activeMode ~= nil and activeMode >= 14 and activeMode <= 16
		if toggleActive then
			if pendingPresses % 2 == 1 then
				activeID, activeMode, selection.outsideSince = nil, nil, nil
				releasedToggle = true
			end
			selection.lastSerial = input.serial
		elseif pendingPresses % 2 == 1 then
			local currentLocation = controllers.getControllerLocation(hand)
			local pressLocation = latestPress and latestPress.location or nil
			local id, mode = closestAccessory(hand, component, attachmentID, list, pressLocation, 14, 16)
			if id == nil and currentLocation ~= nil then
				id, mode = closestAccessory(hand, component, attachmentID, list, currentLocation, 14, 16)
			end
			if id ~= nil then
				activeID, activeMode, selection.outsideSince = id, mode, nil
				selection.lastSerial = input.serial
			elseif not input.held then
				selection.lastSerial = input.serial
			end
		else
			selection.lastSerial = input.serial
		end
	end

	if activeMode ~= nil and activeMode >= 14 and activeMode <= 16 then
		selection.activeID, selection.mode = activeID, activeMode
		return activeID
	end
	if releasedToggle then
		selection.activeID, selection.mode = nil, nil
		return nil
	end

	if activeMode ~= nil and activeMode >= 11 and activeMode <= 13 then
		if input.held and selection.lastReleaseSerial == input.releases then
			selection.activeID, selection.mode = activeID, activeMode
			return activeID
		end
		activeID, activeMode = nil, nil
	end

	-- Preserve the old always-mode precedence and nearest proximity behavior.
	for id, params in pairs(list) do
		local marker = M.getPrimaryMarkerParams(params) or params
		local mode = tonumber(marker.activation_hand) or 1
		if mode == 10 or (mode == 8 and hand == Handed.Left)
			or (mode == 9 and hand == Handed.Right) then
			selection.activeID, selection.mode, selection.outsideSince = id, mode, nil
			return id
		end
	end

	local handLocation = controllers.getControllerLocation(hand)
	local id, mode, distance = closestAccessory(hand, component, attachmentID, list, handLocation, 2, 4)
	if input.held then
		local gripID, gripMode, gripDistanceValue = closestAccessory(hand, component, attachmentID, list, handLocation, 11, 13)
		if gripID ~= nil and (distance == nil or gripDistanceValue < distance) then
			id, mode = gripID, gripMode
		end
	end
	if id == nil and activeMode ~= nil and activeMode >= 2 and activeMode <= 4 and releaseDelay > 0 then
		selection.outsideSince = selection.outsideSince or activationClock
		if activationClock - selection.outsideSince <= releaseDelay then id, mode = activeID, activeMode end
	else
		selection.outsideSince = nil
	end
	selection.activeID, selection.mode = id, mode
	if mode ~= nil and mode >= 11 and mode <= 13 then selection.lastReleaseSerial = input.releases end
	return id
end

local function releaseGripSelections()
	for _, hand in ipairs({ Handed.Left, Handed.Right }) do
		local target = targetSelections[hand]
		if target ~= nil and target.mode ~= nil and target.mode >= 11 then
			M.attachHandToTargetAccessory(hand, nil)
		end
		local attachment = attachmentSelections[hand]
		if attachment ~= nil and attachment.mode ~= nil and attachment.mode >= 11 then
			M.attachHandToAccessory(hand, nil)
			accessoryStatus[hand == Handed.Left and "activeLeftAccessory" or "activeRightAccessory"] = nil
		end
	end
end

local function proximityAccessoryForHand(hand)
	if targetProvider ~= nil then
		local target = getProvidedTarget(hand)
		if target ~= nil then attachmentSelections[hand] = nil; return nil end
	end
	local attachmentHand = Handed.Right
    local attachment = attachments.getCurrentGrippedAttachment(attachmentHand)
    if attachment == nil then attachmentSelections[hand] = nil; return nil end

    local attachmentID = attachments.getAttachmentIDFromAttachment(attachment)-- attachments.getActiveAttachmentID(attachmentHand)
    if attachmentID == nil or attachmentID == "" then attachmentSelections[hand] = nil; return nil end

    local list = M.getAccessoriesForAttachment(attachmentID)
    if list == nil then attachmentSelections[hand] = nil; return nil end
    return selectAccessoryForSource(hand, attachment, attachmentID, list, attachmentSelections, attachmentID)
end

-- Feed proximity as another "opinion" into the same montage/preview resolution path.
uevrUtils.registerUEVRCallback("active_left_accessory", function()
	local id = proximityAccessoryForHand(Handed.Left)
    if id ~= nil then
        return id, PROXIMITY_ACCESSORY_PRIORITY
    end
end)

uevrUtils.registerUEVRCallback("active_right_accessory", function()
	local id = proximityAccessoryForHand(Handed.Right)
    if id ~= nil then
        return id, PROXIMITY_ACCESSORY_PRIORITY
    end
end)

local TARGET_PROXIMITY_PRIORITY = 2

updateTargetAccessoryForHand = function(hand, rawActiveID, rawPriority, force)
	local active = accessoryStatus.targetAccessories and accessoryStatus.targetAccessories[hand]
	local target, configKey = getProvidedTarget(hand)
	if target == nil or type(configKey) ~= "string" or configKey == "" then
		-- Keep a latched grip-toggle selection across brief target gaps (hands not
		-- ready, cutscene flicker). Drop non-toggle state so proximity does not stick.
		local sel = targetSelections[hand]
		if sel == nil or sel.mode == nil or sel.mode < 14 then
			targetSelections[hand] = nil
		end
		if active ~= nil then M.attachHandToTargetAccessory(hand, nil) end
		return false
	end

	local list = M.getAccessoriesForAttachment(configKey)
	local selectedID = selectAccessoryForSource(hand, target, configKey, list, targetSelections)
	-- A higher-priority opinion can interrupt target proximity. A preview (or
	-- other opinion) for an ID under this config key still uses this target.
	if rawActiveID ~= nil and (tonumber(rawPriority) or 0) > TARGET_PROXIMITY_PRIORITY then
		selectedID = list[rawActiveID] ~= nil and rawActiveID or nil
	end
	if selectedID == nil then
		if active ~= nil then M.attachHandToTargetAccessory(hand, nil) end
		return false
	end

	if force or active == nil or active.accessoryID ~= selectedID
		or active.target ~= target or active.configKey ~= configKey then
		local attached = M.attachHandToTargetAccessory(hand, selectedID, target, configKey)
		if not attached then
			M.attachHandToTargetAccessory(hand, nil)
			return false
		end
	end
	return true
end

local function checkAccessories(isMontage, animInstance, montageObject)
	local rawActiveRightAccessory, priority = executeIsRightAccessoryCallback()
	if targetProvider ~= nil then updateTargetAccessoryForHand(Handed.Right, rawActiveRightAccessory, priority) end
	local targetAccessories = accessoryStatus.targetAccessories or {}
	local rightMonitor = status["montageMonitor"] and status["montageMonitor"][Handed.Right]
	if rightMonitor ~= nil and rightMonitor["accessoryID"] ~= rawActiveRightAccessory then
		status["montageMonitor"][Handed.Right] = nil
	end
	local activeRightAccessory = rawActiveRightAccessory
	if targetAccessories[Handed.Right] ~= nil then activeRightAccessory = nil end
	--M.print("Checked active right accessory: " .. tostring(activeRightAccessory) .. " with priority " .. tostring(priority))

	if status["montageMonitor"] and status["montageMonitor"][Handed.Right] and status["montageMonitor"][Handed.Right]["valid"] == false then
		activeRightAccessory = nil
	end
    if activeRightAccessory ~= accessoryStatus["activeRightAccessory"] then
        accessoryStatus["activeRightAccessory"] = activeRightAccessory
        M.print("Active right accessory changed to: " .. tostring(activeRightAccessory))
		local monitor = status["montageMonitor"] and status["montageMonitor"][Handed.Right]
		M.attachHandToAccessory(Handed.Right, activeRightAccessory, isMontage, animInstance or (monitor and monitor["animInstance"]), montageObject or (monitor and monitor["montageObject"]))
    end

	local rawActiveLeftAccessory, priority = executeIsLeftAccessoryCallback()
	if targetProvider ~= nil then updateTargetAccessoryForHand(Handed.Left, rawActiveLeftAccessory, priority) end
	targetAccessories = accessoryStatus.targetAccessories or {}
	local leftMonitor = status["montageMonitor"] and status["montageMonitor"][Handed.Left]
	if leftMonitor ~= nil and leftMonitor["accessoryID"] ~= rawActiveLeftAccessory then
		status["montageMonitor"][Handed.Left] = nil
	end
	local activeLeftAccessory = rawActiveLeftAccessory
	if targetAccessories[Handed.Left] ~= nil then activeLeftAccessory = nil end
	--M.print("Checked active left accessory: " .. tostring(activeLeftAccessory) .. " with priority " .. tostring(priority))
	if status["montageMonitor"] and status["montageMonitor"][Handed.Left] and status["montageMonitor"][Handed.Left]["valid"] == false then
		activeLeftAccessory = nil
	end
    if activeLeftAccessory ~= accessoryStatus["activeLeftAccessory"] then
        accessoryStatus["activeLeftAccessory"] = activeLeftAccessory
        M.print("Active left accessory changed to: " .. tostring(activeLeftAccessory))
		local monitor = status["montageMonitor"] and status["montageMonitor"][Handed.Left]
		M.attachHandToAccessory(Handed.Left, activeLeftAccessory, isMontage, animInstance or (monitor and monitor["animInstance"]), montageObject or (monitor and monitor["montageObject"]))
    end
end

local function activateMontageMonitor(montageObject, animInstance, accessoryID, accessoryParams, handed)
	status["montageMonitor"] = status["montageMonitor"] or {}
	status["montageMonitor"][handed] = {}
	status["montageMonitor"][handed]["montageObject"] = montageObject
	status["montageMonitor"][handed]["animInstance"] = animInstance
	status["montageMonitor"][handed]["accessoryID"] = accessoryID
	status["montageMonitor"][handed]["accessoryParams"] = accessoryParams
	status["montageMonitor"][handed]["valid"] = nil
	status["montageMonitor"][handed]["markerIndex"] = nil
end

local function checkSegmentedMontage(montageObject, montageName, label, animInstance)
	markerDebugPrint("[MarkerDebug] Montage change: montageName=" .. tostring(montageName) .. " label=" .. tostring(label))
	if animInstance == nil then
		print("Animation instance is nil in checkSegmentedMontage. Check comments in updateMontage() in uevrUtils")
	else
		local grippedAttachment = attachments.getCurrentGrippedAttachment(Handed.Right)
		local grippedAttachmentID = attachments.getAttachmentIDFromAttachment(grippedAttachment)
				local activeRightAccessory, priority = executeIsRightAccessoryCallback()
		markerDebugPrint("[MarkerDebug] active_right_accessory returned id=" .. tostring(activeRightAccessory) .. " priority=" .. tostring(priority))
		if activeRightAccessory ~= nil and not (accessoryStatus.targetAccessories and accessoryStatus.targetAccessories[Handed.Right]) then
			local accessoryParams = (grippedAttachmentID ~= nil and grippedAttachmentID ~= "") and M.getAccessoryParamsForAttachment(grippedAttachmentID, activeRightAccessory) or nil
			if accessoryParams == nil then
				accessoryParams = M.getAccessoryParams(activeRightAccessory)
				if accessoryParams ~= nil then
					markerDebugPrint("[MarkerDebug] WARNING: Right accessoryID=" .. tostring(activeRightAccessory) .. " not found under attachmentID=" .. tostring(grippedAttachmentID) .. "; using global lookup")
				end
			end
			if accessoryParams ~= nil then
				if M.accessoryHasTimeMarkers(accessoryParams) then
					markerDebugPrint("[MarkerDebug] Activating montage monitor: hand=Right accessoryID=" .. tostring(activeRightAccessory))
					activateMontageMonitor(montageObject, animInstance, activeRightAccessory, accessoryParams, Handed.Right)
				else
					markerDebugPrint("[MarkerDebug] No time markers: hand=Right accessoryID=" .. tostring(activeRightAccessory))
					local markers = accessoryParams.markers
					if type(markers) == "table" and #markers > 0 then
						for idx, m in ipairs(markers) do
							markerDebugPrint("[MarkerDebug]  marker[" .. tostring(idx) .. "] start=" .. tostring(m.start_time) ..
								" end=" .. tostring(m.end_time) ..
								" socket=" .. tostring(m.socket_name) ..
								" grip_animation=" .. tostring(m.grip_animation))
						end
					end
				end
			else
				markerDebugPrint("[MarkerDebug] Accessory params nil: hand=Right accessoryID=" .. tostring(activeRightAccessory))
			end
		else
			markerDebugPrint("[MarkerDebug] No active accessory: hand=Right")
			local gripped = attachments.getCurrentGrippedAttachment(Handed.Right)
			local grippedName = (gripped ~= nil and gripped.get_full_name ~= nil) and gripped:get_full_name() or tostring(gripped)
			markerDebugPrint("[MarkerDebug] Current gripped attachment (Right hand)=" .. tostring(grippedName))
			markerDebugPrint("[MarkerDebug] Current gripped attachmentID=" .. tostring(attachments.getAttachmentIDFromAttachment(gripped)))
		end
		local activeLeftAccessory, priority = executeIsLeftAccessoryCallback()
		markerDebugPrint("[MarkerDebug] active_left_accessory returned id=" .. tostring(activeLeftAccessory) .. " priority=" .. tostring(priority))
		if activeLeftAccessory ~= nil and not (accessoryStatus.targetAccessories and accessoryStatus.targetAccessories[Handed.Left]) then
			local accessoryParams = (grippedAttachmentID ~= nil and grippedAttachmentID ~= "") and M.getAccessoryParamsForAttachment(grippedAttachmentID, activeLeftAccessory) or nil
			if accessoryParams == nil then
				accessoryParams = M.getAccessoryParams(activeLeftAccessory)
				if accessoryParams ~= nil then
					markerDebugPrint("[MarkerDebug] WARNING: Left accessoryID=" .. tostring(activeLeftAccessory) .. " not found under attachmentID=" .. tostring(grippedAttachmentID) .. "; using global lookup")
				end
			end
			if accessoryParams ~= nil then
				if M.accessoryHasTimeMarkers(accessoryParams) then
					markerDebugPrint("[MarkerDebug] Activating montage monitor: hand=Left accessoryID=" .. tostring(activeLeftAccessory))
					activateMontageMonitor(montageObject, animInstance, activeLeftAccessory, accessoryParams, Handed.Left)
				else
					markerDebugPrint("[MarkerDebug] No time markers: hand=Left accessoryID=" .. tostring(activeLeftAccessory))
					local markers = accessoryParams.markers
					if type(markers) == "table" and #markers > 0 then
						for idx, m in ipairs(markers) do
							markerDebugPrint("[MarkerDebug]  marker[" .. tostring(idx) .. "] start=" .. tostring(m.start_time) ..
								" end=" .. tostring(m.end_time) ..
								" socket=" .. tostring(m.socket_name) ..
								" grip_animation=" .. tostring(m.grip_animation))
						end
					end
				end
			else
				markerDebugPrint("[MarkerDebug] Accessory params nil: hand=Left accessoryID=" .. tostring(activeLeftAccessory))
			end
		else
			markerDebugPrint("[MarkerDebug] No active accessory: hand=Left")
			local gripped = attachments.getCurrentGrippedAttachment(Handed.Right)
			local grippedName = (gripped ~= nil and gripped.get_full_name ~= nil) and gripped:get_full_name() or tostring(gripped)
			markerDebugPrint("[MarkerDebug] Current gripped attachment (Right hand)=" .. tostring(grippedName))
			markerDebugPrint("[MarkerDebug] Current gripped attachmentID=" .. tostring(attachments.getAttachmentIDFromAttachment(gripped)))
		end
	end
end

uevrUtils.registerUEVRCallback("on_module_montage_change", function(montageObject, montageName, label, animInstance)
	if isDisabled then return end

	checkSegmentedMontage(montageObject, montageName, label, animInstance)

	checkAccessories(montageName ~= nil and montageName ~= "", animInstance, montageObject) --sending this param allows for montage based proximity checks
	if montageName == nil or montageName == "" then
		--montage ended, if we had a proximity override active, re-check proximity to see if we need to re-apply it
		-- accessoryStatus["leftProximityAnimationOverride"] = nil
		-- accessoryStatus["rightProximityAnimationOverride"] = nil
		status["montageMonitor"] = nil
		-- M.updateAnimationState(Handed.Left)
		-- M.updateAnimationState(Handed.Right)
	end
end)

-- Monitor proximity, held grips, and toggles between montage callbacks.
uevrUtils.setInterval(300, function()
	if isDisabled then return end

	local isMontage = (status["montageMonitor"] ~= nil)
	checkAccessories(isMontage)
end)
-- ----------------------------------------------------------------

-- If an accessory marker has set an explicit grip animation (e.g. "sniper"),
-- that pose must trump montage-driven CopyPoseFromSkeletalComponent.
-- This must be accessory-scoped (NOT based on holdingAttachment, which is shared).
uevrUtils.registerUEVRCallback("is_hands_animating_from_mesh", function(hand)
	local gripOverride = accessoryStatus["gripAnimationOverride"]
	if type(gripOverride) ~= "table" then return end
	local entry = gripOverride[hand]
	if type(entry) ~= "table" or entry.active ~= true then return end
	local p = tonumber(entry.priority)
	if p == nil then p = 1 end
	return false, p
end)


uevrUtils.registerPostEngineTickCallback(function(engine, delta)
	activationClock = activationClock + (tonumber(delta) or 0)
	if isDisabled then return end

	if status["montageMonitor"] ~= nil then
		local changed = {
			[Handed.Left] = false,
			[Handed.Right] = false
		}
		for i = Handed.Left, Handed.Right do
			if accessoryStatus.targetAccessories and accessoryStatus.targetAccessories[i] then
				status["montageMonitor"][i] = nil
			elseif status["montageMonitor"][i] ~= nil then
				local monitor = status["montageMonitor"][i]
				local valid = true
				local markerIndex = nil
				local accessoryID = monitor["accessoryID"]
				local accessoryParams = monitor["accessoryParams"]
				local montageObject = monitor["montageObject"]
				local animInstance = monitor["animInstance"]

				if accessoryID == nil then
					-- stop monitoring this hand
					status["montageMonitor"][i] = nil
				else
					local prevValid = monitor["valid"]
					local prevMarkerIndex = monitor["markerIndex"]
					local markerParams = nil
					markerParams, markerIndex = resolveAccessoryMarkerParamsForAttach(accessoryParams, true, animInstance, montageObject, nil, true)
					valid = (markerParams ~= nil)

					if prevValid ~= valid or prevMarkerIndex ~= markerIndex then
						monitor["valid"] = valid
						monitor["markerIndex"] = markerIndex
						changed[i] = true
					end

					if changed[i] then
						local currentTime = nil
						if animInstance ~= nil and montageObject ~= nil and animInstance.Montage_GetPosition ~= nil then
							local ok, t = pcall(function()
								return animInstance:Montage_GetPosition(montageObject)
							end)
							if ok then currentTime = t end
						end
						markerDebugPrint("[MarkerDebug] Monitor change: hand=" .. tostring(i) ..
							" accessoryID=" .. tostring(accessoryID) ..
							" time=" .. tostring(currentTime) ..
							" valid " .. tostring(prevValid) .. " -> " .. tostring(valid) ..
							" markerIndex " .. tostring(prevMarkerIndex) .. " -> " .. tostring(markerIndex))
						-- Apply changes even if accessoryID didn't change (marker swap).
						local shouldAttach = valid and accessoryID or nil
						M.attachHandToAccessory(i, shouldAttach, true, animInstance, montageObject, markerIndex)
						local key = (i == Handed.Right) and "activeRightAccessory" or "activeLeftAccessory"
						accessoryStatus[key] = shouldAttach
					end
				end
			end
		end
		if next(status["montageMonitor"]) == nil then status["montageMonitor"] = nil end
	end
end)

uevrUtils.registerPreLevelChangeCallback(function(level)
	releaseGripSelections()
	attachmentSelections = {}
	targetSelections = {}
	gripInput = {
		[Handed.Left] = { held = false, initialized = false, serial = 0, releases = 0, presses = {} },
		[Handed.Right] = { held = false, initialized = false, serial = 0, releases = 0, presses = {} },
	}
	accessoryStatus = {}
	status = {}
end)

uevr.params.sdk.callbacks.on_script_reset(function()
	releaseGripSelections()
end)

uevrUtils.registerUEVRCallback("gunstock_transform_change", function(id, newLocation, newRotation, newOffhandLocationOffset)
	if status["offhandOffset"] == nil then status["offhandOffset"] = {} end
	status["offhandOffset"][id] = newOffhandLocationOffset
end)


-- Passing these functions through but modules can also just call accessories_config_dev directly.
function M.init(isDeveloperMode, logLevel, caller)
    accessoriesConfigDev.init(isDeveloperMode, logLevel, caller)
end

function M.getConfigWidgets(id, prefix, width)
    return accessoriesConfigDev.getConfigWidgets(id, prefix, width)
end

function M.createConfigCallbacks(id, prefix)
    accessoriesConfigDev.createConfigCallbacks(id, prefix)
end

function M.setSocketProvider(id, provider)
	return accessoriesConfigDev.setSocketProvider(id, provider)
end

return M

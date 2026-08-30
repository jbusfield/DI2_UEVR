local uevrUtils = require('libs/uevr_utils')
local controllers = require('libs/controllers')
local configui = require("libs/configui")
local reticule = require("libs/reticule")
local hands = require('libs/hands')
local attachments = require('libs/attachments')
local input = require('libs/input')
local pawnModule = require('libs/pawn')
local montage = require('libs/montage')
local interaction = require('libs/interaction')
local ui = require('libs/ui')
local remap = require('libs/remap')
local gestures = require('libs/gestures')
local gunstock = require('libs/gunstock')
local scopes = require('libs/scope')
local ik = require('libs/ik')
local animation = require('libs/animation')
local collision = require('libs/collision')
local laser = require('libs/laser')
local plugin = require('libs/core/plugin')
require("helpers/melee")
require("helpers/curveball")
local portables = require("helpers/portables")
local ranged = require("helpers/ranged")
local weapons = require("helpers/weapons")
local flashlight = require("helpers/flashlight")
local body = require("helpers/body")
local alyxWheel = require("helpers/alyx_wheel")

--uevrUtils.setLogLevel(LogLevel.Debug)
-- reticule.setLogLevel(LogLevel.Debug)
-- input.setLogLevel(LogLevel.Debug)
-- attachments.setLogLevel(LogLevel.Debug)
-- animation.setLogLevel(LogLevel.Debug)
-- ui.setLogLevel(LogLevel.Debug)
-- remap.setLogLevel(LogLevel.Debug)
-- hands.setLogLevel(LogLevel.Debug)
-- widgetModule.setLogLevel(LogLevel.Debug)
-- ik.setLogLevel(LogLevel.Debug)

--uevrUtils.setDeveloperMode(true)
--hands.enableConfigurationTool()
--uevrUtils.profiler:toggle(true)

ui.init()
montage.init()
interaction.init()
attachments.init()
attachments.setLaserColor("#00FF00FF")
reticule.init()
reticule.setHiddenWhenScopeActive(true)
pawnModule.init()
remap.init()
input.init()
gestures.init()
gunstock.showConfiguration()
scopes.setDefaultPitchOffset(90.0)
ik.init()
collision.init()

hands.setAutoCreateHands(false)
ik.setAutoCreateArms(false)

--since weapons are attached to the hand sockets for this game
--only let the hands be affected by gunstock offsets
attachments.setGunstockOffsetsEnabled(false)
hands.setGunstockOffsetsEnabled(true)
ik.setGunstockOffsetsEnabled(true)

local versionTxt = "v1.0.4"
local title = "Dead Island 2 First Person Mod " .. versionTxt
local configDefinition = {
	{
		panelLabel = "Dead Island 2 Config",
		saveFile = "dead_island_2_config",
		layout = spliceableInlineArray
		{
			{ widgetType = "text", id = "title", label = title },
			{ widgetType = "indent", width = 20 }, { widgetType = "text", label = "Control" }, { widgetType = "begin_rect", },
                {
                    widgetType = "combo",
                    id = "hands_type",
                    label = "Hands Type",
                    selections = {"Forearms", "IK Arms"},
                    initialValue = 1,
                },
                {
                    widgetType = "checkbox",
                    id = "weighted_weapons",
                    label = "Weighted Weapons",
                    initialValue = true,
                },
                {
                    widgetType = "checkbox",
                    id = "attachment_lasers",
                    label = "Gun Lasers",
                    initialValue = true,
                },
                { widgetType = "indent", width = 20 },
                {
                    widgetType = "checkbox",
                    id = "attachment_emmissive_lasers",
                    label = "Emissive",
                    initialValue = true,
                },
				{ widgetType = "unindent", width = 20 },
                {
                    widgetType = "checkbox",
                    id = "left_arm_block_dodge",
                    label = "Left Arm Block/Dodge",
                    initialValue = true,
                },
                { widgetType = "indent", width = 20 },
                {
                    widgetType = "text",
                    id = "left_arm_block_dodge_info",
                    wrapped = true,
                    label = "Raise your left arm in front of your face with palm out to block or dodge",
                },
                { widgetType = "unindent", width = 20 },
                {
                    widgetType = "checkbox",
                    id = "physics_portables",
                    label = "Physics Based Portables",
                    initialValue = true,
                },
				{
					widgetType = "combo",
					id = "interaction_control_mode",
					label = "Interaction Controls",
					selections = {"Vanilla", "Vanilla+", "Mixed", "Full Immersion"},
					initialValue = 1,
					width = 200,
				},
				{ widgetType = "indent", width = 20 }, { widgetType = "text", label = "How to use" }, { widgetType = "begin_rect", },
                { widgetType = "indent", width = 10 },

				{ widgetType = "text", wrapped = true, label = "Melee: Swing your right controller while holding melee weapon", },
				{ widgetType = "text", wrapped = true, label = "Heavy Attack: Hold Right Trigger while swinging", },

				{ widgetType = "begin_group", id = "interaction_info_vanilla_plus_group", isHidden = true },
					{ widgetType = "text", wrapped = true, label = "Jump: Right Stick forward", },
					{ widgetType = "text", wrapped = true, label = "Block/Dodge: Right Stick backward", },
				{ widgetType = "end_group", },

				{ widgetType = "begin_group", id = "interaction_info_mixed_group", isHidden = true },
					{ widgetType = "text", wrapped = true, label = "Inventory: Left Grip near ear", },
					{ widgetType = "text", wrapped = true, label = "Heal: Left Grip near mouth", },
					{ widgetType = "text", wrapped = true, label = "Rage: Left Trigger near eyes", },
				{ widgetType = "end_group", },

				{ widgetType = "begin_group", id = "interaction_info_full_group", isHidden = true },
					{ widgetType = "text", wrapped = true, label = "Inventory: Left Grip near ear", },
					{ widgetType = "text", wrapped = true, label = "Heal: Left Grip near mouth (no DPAD Down)", },
					{ widgetType = "text", wrapped = true, label = "Rage: Left Trigger near eyes (no L3+R3)", },
				{ widgetType = "end_group", },

                { widgetType = "unindent", width = 10 },
            	{ widgetType = "end_rect", additionalSize = 12, rounding = 5 }, { widgetType = "unindent", width = 20 },
				{ widgetType = "new_line" },
				expandArray(gestures.getConfigurationWidgets, {
					select = {
						{ id = "uevr_gesture_config_swipe_minThresholdSpeed", label = "Swing Effort Required", range = {100, 1000} },
					},
				}),
                {
                    widgetType = "combo",
                    id = "flashlight_location",
                    label = "Flashlight Location",
                    selections = {"Head", "Left Hand", "Right Hand"},
                    initialValue = 1,
                },
                { widgetType = "indent", width = 20 },
                {
                    widgetType = "drag_float3",
                    id = "flashlight_head_position",
                    label = "Flashlight Position",
                    speed = 0.1,
                    range = {-100, 100},
                    initialValue = {0, 0, 0},
                },
                {
                    widgetType = "drag_float3",
                    id = "flashlight_head_rotation",
                    label = "Flashlight Rotation",
                    speed = 0.5,
                    range = {-180, 180},
                    initialValue = {0, 0, 0},
                },
                {
                    widgetType = "drag_float3",
                    id = "flashlight_left_position",
                    label = "Flashlight Position",
                    speed = 0.1,
                    range = {-100, 100},
                    initialValue = {0, 0, 0},
                    isHidden = true,
                },
                {
                    widgetType = "drag_float3",
                    id = "flashlight_left_rotation",
                    label = "Flashlight Rotation",
                    speed = 0.5,
                    range = {-180, 180},
                    initialValue = {0, 0, 0},
                    isHidden = true,
                },
                {
                    widgetType = "drag_float3",
                    id = "flashlight_right_position",
                    label = "Flashlight Position",
                    speed = 0.1,
                    range = {-100, 100},
                    initialValue = {0, 0, 0},
                    isHidden = true,
                },
                {
                    widgetType = "drag_float3",
                    id = "flashlight_right_rotation",
                    label = "Flashlight Rotation",
                    speed = 0.5,
                    range = {-180, 180},
                    initialValue = {0, 0, 0},
                    isHidden = true,
                },
				{ widgetType = "unindent", width = 20 },
			{ widgetType = "end_rect", additionalSize = 12, rounding = 5 }, { widgetType = "unindent", width = 20 },
			{ widgetType = "new_line" },
			{ widgetType = "indent", width = 20 }, { widgetType = "text", label = "Weapon Wheel" }, { widgetType = "begin_rect", },
				{ widgetType = "text", label = "Half-Life: Alyx Style Weapon Wheel - Coutesy of vinion" },
				expandArray(alyxWheel.getConfigurationWidgets),
			{ widgetType = "end_rect", additionalSize = 12, rounding = 5 }, { widgetType = "unindent", width = 20 },
			{ widgetType = "new_line" },
			{ widgetType = "indent", width = 20 }, { widgetType = "text", label = "UI" }, { widgetType = "begin_rect", },
				expandArray(ui.getConfigurationWidgets),
			{ widgetType = "end_rect", additionalSize = 12, rounding = 5 }, { widgetType = "unindent", width = 20 },
			{ widgetType = "new_line" },
			{ widgetType = "indent", width = 20 }, { widgetType = "text", label = "Input" }, { widgetType = "begin_rect", },
				expandArray(input.getConfigurationWidgets),
			{ widgetType = "end_rect", additionalSize = 12, rounding = 5 }, { widgetType = "unindent", width = 20 },
			{ widgetType = "new_line" },
			{ widgetType = "indent", width = 20 }, { widgetType = "text", label = "Reticule" }, { widgetType = "begin_rect", },
				expandArray(reticule.getConfigurationWidgets,{{id="uevr_reticule_update_distance", initialValue=200},}),
			{ widgetType = "end_rect", additionalSize = 12, rounding = 5 }, { widgetType = "unindent", width = 20 },
			{ widgetType = "new_line" },
			{
				widgetType = "tree_node",
				id = "advanced_settings",
				initialOpen = false,
				label = "Advanced"
			},
				{
					widgetType = "checkbox",
					id = "use_skeletal_mesh_hiding",
					label = "Skeletal Mesh Hiding (More compatible, less performant)",
					initialValue = false
				},
				{
					widgetType = "checkbox",
					id = "black_overlay_fix",
					label = "Black Overlay Fix (enable if black overlays persist in scene changes. Can cause crashes)",
					initialValue = false
				},
			{ widgetType = "tree_pop" },
			{ widgetType = "new_line" },
		}
	}
}

local status = {}

local HandsType = {
	Forearms = 1,
	IKArms = 2,
}
local function regenerateHands(value)
	--detach attachments first so they dont get "lost" when hands are destroyed
	attachments.detachGripAttachments(Handed.Right)
	attachments.detachGripAttachments(Handed.Left)

    hands.setAutoCreateHands(value == HandsType.Forearms)
    ik.setAutoCreateArms(value == HandsType.IKArms)

    hands.destroyHands()
    ik.destroyAll()
end

configui.onUpdate("hands_type", function(value)
    regenerateHands(value)
end)

configui.onCreateOrUpdate("weighted_weapons", function(value)
	attachments.disableWeights(value ~= true)
end)

configui.onCreateOrUpdate("attachment_lasers", function(value)
	attachments.setLasersEnabled(value == true)
	configui.setHidden("attachment_emmissive_lasers", value ~= true)
end)

configui.onCreateOrUpdate("attachment_emmissive_lasers", function(value)
	laser.setUseEmissive(value == true)
end)


local function hideReticule(val)
	local reticle = uevrUtils.find_first_of("Class /Script/DeadIsland.HUDObject_Reticle", false)
	if uevrUtils.getValid(reticle) ~= nil and reticle ~= nil and reticle.SetBaseAssetShowing ~= nil then
		reticle:SetBaseAssetShowing(not val)
	end
end

ik.registerOnMeshCreatedCallback(function(meshComponentList, ikInstance)
    --print("IK Mesh created:", meshComponent ~= nil, ikInstance ~= nil and ikInstance.rigId or "")
    local meshComponent = meshComponentList and meshComponentList[1] or nil
	if meshComponent ~= nil then
        meshComponent.bCastDynamicShadow = false
        meshComponent.bRenderInDepthPass = false
        animation.setComponent("left_arms", meshComponent)
		animation.setComponent("right_arms", meshComponent)
    end
end)

local function getHandComponents()
    local rightHandComponent = nil
   	local leftHandComponent = nil
	local handsType = configui.getValue("hands_type")
    if handsType == HandsType.None then
        rightHandComponent = controllers.getController(Handed.Right)
        leftHandComponent = controllers.getController(Handed.Left)
    elseif handsType == HandsType.Forearms then
        rightHandComponent = hands.getHandComponent(Handed.Right)
        leftHandComponent = hands.getHandComponent(Handed.Left)
    elseif handsType == HandsType.IKArms then
        rightHandComponent = ik.getCurrentMesh()
		leftHandComponent = ik.getCurrentMesh()
    end

    return rightHandComponent, leftHandComponent
end

----------------- Game specific Cutscene detection -------------------------------------------
hook_function("Class /Script/DeadIsland.CutsceneActivityActor", "OnCutsceneBegin", true,
	function()
		uevrUtils.setIsInCutsceneOverride(true)
	end, nil, false)
hook_function("Class /Script/DeadIsland.CutsceneActivityActor", "OnCutsceneEnd", true,
	function()
		uevrUtils.setIsInCutsceneOverride(false)
	end, nil, false)
----------------- End Cutscene detection -------------------------------------------

-- Ensure weapons appearing dont interfere with thrown objects
local blockGripAfterThrow = false
portables.registerThrowingCallback(function(isThrowing)
	blockGripAfterThrow = isThrowing
	ranged.setEquippedWeaponHidden(isThrowing)
end)
----------------------------------------------------------------

local defaultAttachOptions = {
	detachFromOriginOnGrip = true,
	maintainWorldPositionOnDetachFromOrigin = true,
	detachFromParentOnRelease = true,
	maintainWorldPositionOnDetachFromParent = true,
	reattachToOriginOnRelease = true,
	restoreTransformToOriginOnReattach = true,
	useZeroTransformOnReattach = false,
	allowChildVisibilityHandling = false,
	allowChildHiddenInGameHandling = false,
	allowRenderInMainPassHandling = false,
	useCurrentAttachedSocketName = false,
	allowMobiltyChange = true,
}
attachments.registerOnGripUpdateCallback(function()
	if status.counterSequence then
		return nil, nil, nil, nil, nil, nil, defaultAttachOptions
	end

	if blockGripAfterThrow then
		ranged.setEquippedWeaponHidden(true)
		return
	end

	local attachOptions = portables.attachOptions
	local rightGripMesh = portables.getPortableMesh()
	local leftGripMesh = nil
	if rightGripMesh == nil then
		rightGripMesh, leftGripMesh = weapons.getWeaponMesh()
		attachOptions = defaultAttachOptions
	end
	local rightHandComponent, leftHandComponent = getHandComponents()
	local rightSocket = "weapon_01_rSocket" -- "Hand_R"
	local leftSocket = "weapon_01_lSocket" -- "Hand_L"
	return rightHandComponent and rightGripMesh, rightHandComponent, rightSocket, leftHandComponent and leftGripMesh, leftHandComponent, leftSocket, attachOptions
end)

attachments.registerAttachmentChangeCallback(function(id, gripHand, attachment)
	ranged.applyRangedWeaponMuzzleAim()
	--attachments.setLaserColor("#FFFFFF")

	if attachment ~= nil then
		weapons.reparentWeaponFx(attachment)
	end

	local isMeleeWeapon = (type(id) == "string" and string.find(id, "BP_MeleeWeapon", 1, true) == 1) or (attachment ~= nil and attachments.isActiveAttachmentMelee(gripHand))
	if isMeleeWeapon and attachment ~= nil then
		attachment:SetCollisionEnabled(ECollisionEnabled.QueryAndPhysics)
		attachment:SetCollisionResponseToAllChannels(ECollisionResponse.Ignore)
		attachment:SetCollisionResponseToChannel(5, ECollisionResponse.Block)
		attachment:SetCollisionResponseToChannel(15, ECollisionResponse.Block)
	end
	gestures.autoDetectGesture(gestures.Gesture.SWIPE_RIGHT, isMeleeWeapon, gripHand)
	gestures.autoDetectGesture(gestures.Gesture.SWIPE_LEFT, isMeleeWeapon, gripHand)
end)

local equippedItemsWheelClass = "BlueprintGeneratedClass /Game/DI2/UI/HUD/Objects/WeaponWheel/BP_HUDObject_EquippedItemsWheel.BP_HUDObject_EquippedItemsWheel_C"
local function hookEquippedItemsWheel()
	local _, openFn = hook_function(equippedItemsWheelClass, "OnOpenWheel", false, nil,
		function()
			uevrUtils.executeUEVRCallbacks("scaleform_ui_change", "BP_HUDObject_EquippedItemsWheel_C", true)
		end, false)
	local _, closeFn = hook_function(equippedItemsWheelClass, "OnCloseWheel", false, nil,
		function()
			uevrUtils.executeUEVRCallbacks("scaleform_ui_change", "BP_HUDObject_EquippedItemsWheel_C", false)
		end, false)
end

function on_level_change(level, levelName)
	hideReticule(true)
	regenerateHands(configui.getValue("hands_type"))
	gestures.autoDetectGesture(gestures.Gesture.SWIPE_RIGHT, false, Handed.Left)
	gestures.autoDetectGesture(gestures.Gesture.SWIPE_LEFT, false, Handed.Left)
	gestures.autoDetectGesture(gestures.Gesture.SWIPE_RIGHT, false, Handed.Right)
	gestures.autoDetectGesture(gestures.Gesture.SWIPE_LEFT, false, Handed.Right)
	flashlight.reset()
	flashlight.updateFlashlightOffsetVisibility()
	flashlight.attachFlashlightToController(true)
	hookEquippedItemsWheel()
end

uevrUtils.setInterval(1000, function()
	flashlight.attachFlashlightToController(false)
	--ranged.applyRangedWeaponMuzzleAim()
end)


function on_post_engine_tick(engine, delta)
	if blockGripAfterThrow then
		ranged.setEquippedWeaponHidden(true)
	end
	local animInstance = uevrUtils.getValid(pawn, {"MeshFirstPerson", "AnimScriptInstance"})
	if animInstance ~= nil then
		--this stops the pawn body from distorting with right controller pitch change.
		animInstance.UseFPCameraRotation = false --status.cutsceneDisabledOverride == true and true or false
	end
end

----------------- Counter / finishing move (show FP body materials) ----------------
local function setCounterSequenceActive(active)
	status.counterSequence = active == true
	attachments.forceGripUpdate()
	if active then
		local mesh = weapons.getWeaponMesh()
		if mesh then mesh:SetVisibility(true, true) end
	end
	uevrUtils.setIsInCutsceneOverride(active == true)
end

hook_function("Class /Script/DeadIsland.CoopSequenceTask_Counter", "OnActionBegin", true, nil,
	function()
		setCounterSequenceActive(true)
	end, true)
hook_function("Class /Script/DeadIsland.CoopSequenceTask_Counter", "OnOutroAnimationComplete", true, nil,
	function()
		setCounterSequenceActive(false)
	end, true)
hook_function("Class /Script/DeadIsland.CoopSequenceTask_Counter", "OnActionEnded", true, nil,
	function()
		setCounterSequenceActive(false)
	end, true)
----------------- End Counter ------------------------------------------------------


-- Show body when knocked down
montage.registerMontageChangeCallback(function(montageObject, montageName, label)
	--if montageName starts with "AM_Base_Hit_Knockdown" then
	if uevrUtils.startsWith(montageName, "AM_Base_Hit_Knockdown") or uevrUtils.startsWith(montageName, "AM_Base_Downed") or uevrUtils.startsWith(montageName, "AM_Base_Death") or uevrUtils.startsWith(montageName, "AM_1P_Death") then
		body.setHidden(false)
		input.setDisabled(true)
		status.knockdown = true
	elseif status.knockdown == true then
		body.setHidden(true)
		input.setDisabled(false)
		status.knockdown = false
	end
end)

---------------- Special Scaleform UI handlers since they are not widget based -----------------------------
local lastActiveScaleformMenus = {}
setInterval(500, function()
	local current = {}
	if uevrUtils.getValid(status.menuManager) == nil then
		status.menuManager = uevrUtils.find_first_of("Class /Script/DeadIsland.MenuManager", false)
	end
	local activeMenus = uevrUtils.getValid(status.menuManager) ~= nil and status.menuManager.ActiveMenus or nil
	if activeMenus ~= nil then
		local consecutiveNils = 0
		for i = 0, 31 do
			local menu = nil
			pcall(function() menu = activeMenus[i] end)
			if uevrUtils.getValid(menu) == nil then
				consecutiveNils = consecutiveNils + 1
				if consecutiveNils >= 2 then
					break
				end
			else
				consecutiveNils = 0
				local className = nil
				---@type any
				local validMenu = menu
				pcall(function()
					local cls = validMenu.get_class ~= nil and validMenu:get_class() or nil
					if cls ~= nil then --and cls.get_full_name ~= nil then
						className = uevrUtils.getShortName(cls) --cls:get_full_name()
					end
				end)
				if type(className) == "string" and className ~= "" then
					current[className] = true
				end
			end
		end
	end
	if uevrUtils.getValid(status.failScreen) == nil then
		status.failScreen = uevrUtils.find_first_of("Class /Script/DeadIsland.HUDObject_FailScreen", false)
	end
	if uevrUtils.getValid(status.failScreen) ~= nil then
		local showing = false
		pcall(function()
			showing = status.failScreen:IsBaseAssetShowing() == true or status.failScreen:IsInAnActiveState() == true
		end)
		if showing then
			current["BP_HUDObject_FailScreen_C"] = true
		end
	end

	if uevrUtils.getValid(status.credits) == nil then
		status.credits = uevrUtils.find_first_of("Class /Script/DeadIsland.HUDObject_Credits", false)
	end
	if uevrUtils.getValid(status.credits) ~= nil then
		local showing = false
		pcall(function()
			-- IsInAnActiveState stays true after credits (e.g. while pause menu is up).
			showing = status.credits:IsBaseAssetShowing() == true
		end)
		if showing then
			current["BP_HUDObject_Credits_C"] = true
		end
	end

	if uevrUtils.getValid(status.fader) == nil then
		status.fader = uevrUtils.find_first_of("Class /Script/DeadIsland.HUDObject_Fader", false)
	end
	if uevrUtils.getValid(status.fader) ~= nil then
		local showing = false
		pcall(function()
			local movie = status.fader:GetAsset("Fader")
			showing = movie ~= nil and movie:GetRootVisibility() == true
		end)
		if showing then
			current["BP_HUDObject_Fader_C"] = true
		end
	end

	for className, _ in pairs(current) do
		if lastActiveScaleformMenus[className] ~= true then
			uevrUtils.executeUEVRCallbacks("scaleform_ui_change", className, true)
		end
	end
	for className, _ in pairs(lastActiveScaleformMenus) do
		if current[className] ~= true then
			uevrUtils.executeUEVRCallbacks("scaleform_ui_change", className, false)
		end
	end
	lastActiveScaleformMenus = current

end)

setInterval(5000, function()
	if configui.getValue("black_overlay_fix") ~= true then return end
	pcall(function()
		status.fader = uevrUtils.find_first_of("Class /Script/DeadIsland.HUDObject_Fader", false)
		if uevrUtils.getValid(status.fader) == nil then return end

		if lastActiveScaleformMenus["BP_HUDObject_Fader_C"] ~= true then return end
		local widget = uevrUtils.find_first_of("Class /Script/DeadIsland.ManualHUDFaderWidget", false)
		if widget == nil or widget.EasedEffectValue > 0.05 then return end
		status.fader:GetAsset("Fader"):SetRootVisibility(false)
		--uevrUtils.stopFadeCamera()
		print("[DI2] stuck movie fader, hiding")
	end)
end)

uevrUtils.registerUEVRCallback("scaleform_ui_change", function(className, visible)
	--print("[DI2] scaleform_ui_change", className, visible)
	if className == "BP_HUDObject_Credits_C" or className == "BP_HUDObject_FailScreen_C" then
		--print("Character Hidden Override: ", visible)
		-- nil clears override; false would stick and block automatic detection
		uevrUtils.setIsCharacterHiddenOverride(visible and true or nil)
		if className == "BP_HUDObject_FailScreen_C" and visible == false then
			regenerateHands(configui.getValue("hands_type"))
			body.setHidden(true)
			--input.reset()
		end
	elseif className == "BP_HUDObject_EquippedItemsWheel_C" then
		--print("Character Hidden Override: ", visible)
		uevrUtils.setIsCharacterHiddenOverride(visible and true or nil)
		status.isWeaponWheelVisible = visible
	elseif className == "BP_MenuInstance_Locker_C" then
		regenerateHands(configui.getValue("hands_type"))
	elseif className == "BP_HUDObject_Fader_C" then
		--this seems to hard lock the game in certain instances like the clown scene. Leave it out for now.
		-- if visible == true then
		-- 	uevrUtils.fadeCamera(0.1)
		-- else
		-- 	delay(300, function()
		-- 		uevrUtils.stopFadeCamera()
		-- 	end)
		-- end
	end
end)
--------------------- End Special Scaleform UI handlers -----------------------------

local remapLabels = {"Vanilla", "Vanilla Plus", "Mixed", "Full Immersion"}
configui.onCreateOrUpdate("interaction_control_mode", function(value)
	configui.setHidden("interaction_info_vanilla_plus_group", value == 1)
	configui.setHidden("interaction_info_mixed_group", value ~= 3)
	configui.setHidden("interaction_info_full_group", value ~= 4)

	remap.setCurrentProfileByLabel(remapLabels[value])
end)

configui.onCreateOrUpdate("left_arm_block_dodge", function(value)
	configui.setHidden("left_arm_block_dodge_info", value ~= true)
	gestures.autoDetectGesture(gestures.Gesture.BLOCK, value == true, Handed.Left)
	if value ~= true then
		status.isBlocking = false
	end
end)

configui.onCreateOrUpdate("physics_portables", function(value)
	portables.usePhysicsBased(value)
end)

configui.create(configDefinition)

gestures.registerBlockCallback(function(active, hand)
	status.isBlocking = active
end, false, false)

local xInputStatus = {}
uevrUtils.registerOnPreInputGetStateCallback(function(retval, user_index, state)
	if status.isWeaponWheelVisible == true then
		if uevrUtils.isButtonPressed(state, XINPUT_GAMEPAD_B) then
			if state.Gamepad.sThumbRX < -22000 then
				uevrUtils.pressButton(state, XINPUT_GAMEPAD_DPAD_LEFT)
			end
			if state.Gamepad.sThumbRX > 22000 then
				uevrUtils.pressButton(state, XINPUT_GAMEPAD_DPAD_RIGHT)
			end
			state.Gamepad.sThumbRX = 0
		end
	end

	if ui.isRemapDisabled() == true then return end

	if configui.getValue("left_arm_block_dodge") and status.isBlocking then
		uevrUtils.pressButton(state, XINPUT_GAMEPAD_LEFT_SHOULDER)
	end

	local interactionControlMode = configui.getValue("interaction_control_mode") or 1
	if interactionControlMode == 3 or interactionControlMode == 4 then --(ui.isRemapDisabled()) ~= true then
		local gripMouth, gripEyes, gripHead, gripEar, triggerMouth, triggerEyes, triggerHead, triggerEar = gestures.getHeadGestures(state, 1 - uevrUtils.getHandedness(), true)

		if interactionControlMode == 4 then
			if uevrUtils.isButtonPressed(state, XINPUT_GAMEPAD_LEFT_THUMB) and uevrUtils.isButtonPressed(state, XINPUT_GAMEPAD_RIGHT_THUMB) then
				uevrUtils.unpressButton(state, XINPUT_GAMEPAD_LEFT_THUMB)
				uevrUtils.unpressButton(state, XINPUT_GAMEPAD_RIGHT_THUMB)
			end
			if uevrUtils.isButtonPressed(state, XINPUT_GAMEPAD_DPAD_DOWN) then
				uevrUtils.unpressButton(state, XINPUT_GAMEPAD_DPAD_DOWN)
			end
		end

		if xInputStatus.triggerEyes ~= triggerEyes then
			xInputStatus.triggerEyes = triggerEyes
			if triggerEyes then
				uevrUtils.pressButton(state, XINPUT_GAMEPAD_LEFT_THUMB)
				uevrUtils.pressButton(state, XINPUT_GAMEPAD_RIGHT_THUMB)
			end
		end

		if xInputStatus.isGrippingEar ~= gripEar then
			xInputStatus.isGrippingEar = gripEar
			if gripEar then
				uevrUtils.pressButton(state, XINPUT_GAMEPAD_BACK)
			end
		end

		if xInputStatus.isGrippingMouth ~= gripMouth then
			xInputStatus.isGrippingMouth = gripMouth
			if gripMouth then
				uevrUtils.pressButton(state, XINPUT_GAMEPAD_DPAD_DOWN)
			end
		end
		if gripMouth then
			uevrUtils.unpressButton(state, XINPUT_GAMEPAD_LEFT_SHOULDER)
		end

	end
end)

-- register_key_bind("F1", function()
-- 	uevrUtils.profiler:report()
-- end)


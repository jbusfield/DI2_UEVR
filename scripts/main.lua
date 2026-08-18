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
local particlesConfigDev = require('libs/config/particles_config_dev')
local ik = require('libs/ik')
local animation = require('libs/animation')
local collision = require('libs/collision')
local laser = require('libs/laser')
local plugin = require('libs/core/plugin')
require("helpers/melee")
local portables = require("helpers/portables")
local dev = require('libs/uevr_dev')
dev.init()

uevrUtils.setLogLevel(LogLevel.Debug)
-- reticule.setLogLevel(LogLevel.Debug)
-- input.setLogLevel(LogLevel.Debug)
attachments.setLogLevel(LogLevel.Debug)
-- animation.setLogLevel(LogLevel.Debug)
-- ui.setLogLevel(LogLevel.Debug)
-- remap.setLogLevel(LogLevel.Debug)
-- hands.setLogLevel(LogLevel.Debug)
-- widgetModule.setLogLevel(LogLevel.Debug)
-- ik.setLogLevel(LogLevel.Debug)

uevrUtils.setDeveloperMode(true)
--hands.enableConfigurationTool()
--uevrUtils.profiler:toggle(true)


ui.init()
--ui.setRequireWidgetOpenState(true)
montage.init()
--montage.addMeshMonitor("Arms", "Pawn.FPVMesh")
interaction.init()
attachments.init()
--attachments.setLaserColor("#00FFFFFF")
reticule.init()
--reticule.setHiddenWhenScopeActive(true)
pawnModule.init()
remap.init()
input.init()
gestures.init()
gunstock.showConfiguration()
scopes.setDefaultPitchOffset(90.0)
--particlesConfigDev.init()
ik.init()
collision.init()

hands.setAutoCreateHands(false)
ik.setAutoCreateArms(false)
--laser.setUseEmissive(true)

local versionTxt = "v1.0.0"
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
                    label = "Weapon Lasers",
                    initialValue = true,
                },
                {
                    widgetType = "combo",
                    id = "flashlight_location",
                    label = "Flashlight Location",
                    selections = {"Head", "Left Hand", "Right Hand"},
                    initialValue = 1,
                },
                {
                    widgetType = "drag_float3",
                    id = "flashlight_head_position",
                    label = "Head Position",
                    speed = 0.1,
                    range = {-100, 100},
                    initialValue = {0, 0, 0},
                },
                {
                    widgetType = "drag_float3",
                    id = "flashlight_head_rotation",
                    label = "Head Rotation",
                    speed = 0.5,
                    range = {-180, 180},
                    initialValue = {0, 0, 0},
                },
                {
                    widgetType = "drag_float3",
                    id = "flashlight_left_position",
                    label = "Left Hand Position",
                    speed = 0.1,
                    range = {-100, 100},
                    initialValue = {0, 0, 0},
                    isHidden = true,
                },
                {
                    widgetType = "drag_float3",
                    id = "flashlight_left_rotation",
                    label = "Left Hand Rotation",
                    speed = 0.5,
                    range = {-180, 180},
                    initialValue = {0, 0, 0},
                    isHidden = true,
                },
                {
                    widgetType = "drag_float3",
                    id = "flashlight_right_position",
                    label = "Right Hand Position",
                    speed = 0.1,
                    range = {-100, 100},
                    initialValue = {0, 0, 0},
                    isHidden = true,
                },
                {
                    widgetType = "drag_float3",
                    id = "flashlight_right_rotation",
                    label = "Right Hand Rotation",
                    speed = 0.5,
                    range = {-180, 180},
                    initialValue = {0, 0, 0},
                    isHidden = true,
                },
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

local function getWeaponMesh()
    local pawn = uevrUtils.get_local_pawn()
    if not pawn then
        return
    end
    --alternates
    -- UWeaponUtils::GetCurrentItemFromPlayerWeaponProxy
    -- -- returns AItemActor* for that hand
    -- local pawn = uevrUtils.get_local_pawn()
    --local proxy = pawn.BPC_Player_WeaponProxy  -- UWeaponProxyComponent
    -- local WeaponUtils = uevrUtils.find_default_instance("Class /Script/DeadIsland.WeaponUtils")
    -- local item = WeaponUtils:GetCurrentItemFromPlayerWeaponProxy(proxy, 0) -- EWeaponHand.Mainhand = 0
    -- -- Offhand = 1

	-- local weaponUtils = uevrUtils.find_default_instance("Class /Script/DeadIsland.WeaponUtils")
	-- local item = weaponUtils:GetCurrentItemFromPlayerWeaponProxy(pawn.BPC_Player_WeaponProxy, 0)

	--ranged weapons
	local paperDoll = pawn.BPC_Player_PaperDoll
	local item = paperDoll and paperDoll.GetItemFor and paperDoll:GetItemFor(0) -- EDIPaperDollSlot.Weapon
	if uevrUtils.getValid(item) ~= nil then
		local modules = item.RangedWeaponModulesComponent
		local visual = modules and modules.GetOwnerVisualActor and modules:GetOwnerVisualActor()
		if uevrUtils.getValid(visual) ~= nil then
			if visual.WeaponMesh ~= nil then return visual.WeaponMesh end
			if visual.SkeletalMesh ~= nil then return visual.SkeletalMesh end
		end
	end

	--melee weapons
    local proxy = pawn.BPC_Player_WeaponProxy  -- UWeaponProxyComponent
    local childComp = proxy:GetChildActorForHand(0) -- ChildActorComponent
    local weaponActor = childComp and childComp.ChildActor
	if weaponActor then
		local mesh = weaponActor.WeaponMesh
		if mesh then return mesh end
		mesh = weaponActor.SkeletalMesh
		if mesh then return mesh end
	end
	return nil
end

----------------- Ranged weapon Aim fix -------------------------------------------
-- Hitscan guns default to RaycastLocalCameraFallbackToMuzzle, which follows the
-- FP camera (body yaw + aim pitch). RaycastFromMuzzle uses the weapon Muzzle socket.
-- Keep the 180° alignment push so VR hip-fire is not filtered.
local ETargetPointRaycastType_RaycastFromMuzzle = 1

local function applyMuzzleAimToProjectileSpawner(spawner)
	if uevrUtils.getValid(spawner) == nil then return end
	if spawner.RaycastType ~= nil then
		spawner.RaycastType = ETargetPointRaycastType_RaycastFromMuzzle
	end
	if spawner.bLocalUserPushActionIfMuzzleAligmentGreaterThanTolerance ~= nil then
		spawner.bLocalUserPushActionIfMuzzleAligmentGreaterThanTolerance = true
	end
	if spawner.LocalUserMuzzleAlignmentToleranceDegrees ~= nil then
		spawner.LocalUserMuzzleAlignmentToleranceDegrees = 180
	end
end

local function applyMuzzleAimToFireMode(fireMode)
	if uevrUtils.getValid(fireMode) == nil then return end
	applyMuzzleAimToProjectileSpawner(fireMode.ProjectileSpawner)
	applyMuzzleAimToProjectileSpawner(fireMode.SecondaryProjectileSpawner)
	local adj = fireMode.LaunchAdjustmentHandler
	if uevrUtils.getValid(adj) == nil then return end
	if adj.MaxAdjustScreenSpacePercentage ~= nil then
		adj.MaxAdjustScreenSpacePercentage = 0
	end
	if adj.bUseCachedPlayerAutoAimResults ~= nil then
		adj.bUseCachedPlayerAutoAimResults = false
	end
end

local function applyRangedWeaponMuzzleAim()
	local pawn = uevrUtils.get_local_pawn()
	if pawn == nil then return end
	local paperDoll = pawn.BPC_Player_PaperDoll
	local item = paperDoll and paperDoll.GetItemFor and paperDoll:GetItemFor(0)
	local modules = uevrUtils.getValid(item) ~= nil and item.RangedWeaponModulesComponent or nil
	if uevrUtils.getValid(modules) == nil or modules == nil then return end
	if modules.GetSelectedProjectileSpawner ~= nil then
		applyMuzzleAimToProjectileSpawner(modules:GetSelectedProjectileSpawner())
	end
	if modules.GetSelectedFireMode ~= nil then
		applyMuzzleAimToFireMode(modules:GetSelectedFireMode())
	end
end

local function setEquippedWeaponHidden(hidden)
	local mesh = getWeaponMesh()
	if uevrUtils.getValid(mesh) == nil or mesh == nil then
		return
	end
	pcall(function()
		mesh:SetHiddenInGame(hidden, true)
	end)
	local owner = mesh.GetOwner ~= nil and mesh:GetOwner() or nil
	if owner ~= nil then
		pcall(function()
			owner:SetActorHiddenInGame(hidden)
		end)
	end
end
----------------- End Ranged weapon Aim fix -------------------------------------------

----------------- Game specific Cutscene detection -------------------------------------------
setInterval(200,function()
	local inCutscene = uevrUtils.getValid(uevrUtils.get_player_controller(),{ "PlayerCameraManager", "CutsceneComponent", "CurrentViewTargetCameraComponent"}) ~= nil
	uevrUtils.setIsInCutsceneOverride(inCutscene == true and true or nil)
end)
----------------- End Cutscene detection -------------------------------------------

-- Ensure weapons appearing dont interfere with thrown objects
local blockGripAfterThrow = false
portables.registerThrowingCallback(function(isThrowing)
	blockGripAfterThrow = isThrowing
	setEquippedWeaponHidden(isThrowing)
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
	if blockGripAfterThrow then
		setEquippedWeaponHidden(true)
		return
	end
	local portableMesh = portables.getPortableMesh()
	local gripMesh = portableMesh or getWeaponMesh()
	local attachOptions = portableMesh ~= nil and portables.attachOptions or defaultAttachOptions
	local rightHandComponent, leftHandComponent = getHandComponents()
	local rightSocket = "weapon_01_rSocket" -- "Hand_R"
	return rightHandComponent and gripMesh, rightHandComponent, rightSocket, nil, nil, nil, attachOptions
end)

attachments.registerAttachmentChangeCallback(function(id, gripHand, attachment)
	applyRangedWeaponMuzzleAim()
	--attachments.setLaserColor("#FFFFFF")

	local isMeleeWeapon = type(id) == "string" and string.find(id, "BP_MeleeWeapon", 1, true) == 1
	if isMeleeWeapon and attachment ~= nil then
		attachment:SetCollisionEnabled(ECollisionEnabled.QueryAndPhysics)
		attachment:SetCollisionResponseToAllChannels(ECollisionResponse.Ignore)
		attachment:SetCollisionResponseToChannel(5, ECollisionResponse.Block)
		attachment:SetCollisionResponseToChannel(15, ECollisionResponse.Block)
	end
	gestures.autoDetectGesture(gestures.Gesture.SWIPE_RIGHT, isMeleeWeapon)
	gestures.autoDetectGesture(gestures.Gesture.SWIPE_LEFT, isMeleeWeapon)
end)

---------------------------------------------------------------------------
-- Flashlight (ScopedSpotlight on SpringArmComponentForTorch): the spring arm
-- uses pawn control rotation, so pitch comes from the aim pose while yaw stays
-- on the body. Drive the light from HMD / left / right via motion controller state.
---------------------------------------------------------------------------
local FlashlightLocation = {
	Head = 1,
	LeftHand = 2,
	RightHand = 3,
}

local flashlightOffsetIds = {
	[FlashlightLocation.Head] = { position = "flashlight_head_position", rotation = "flashlight_head_rotation" },
	[FlashlightLocation.LeftHand] = { position = "flashlight_left_position", rotation = "flashlight_left_rotation" },
	[FlashlightLocation.RightHand] = { position = "flashlight_right_position", rotation = "flashlight_right_rotation" },
}

local flashlightStatus = {}

local function flashlightHandFromLocation(location)
	if location == FlashlightLocation.LeftHand then return Handed.Left end
	if location == FlashlightLocation.RightHand then return Handed.Right end
	return 2 -- HMD
end

local function vec3FromConfig(value)
	if value == nil then return 0, 0, 0 end
	if value.X ~= nil then return value.X or 0, value.Y or 0, value.Z or 0 end
	if value.Pitch ~= nil then return value.Pitch or 0, value.Yaw or 0, value.Roll or 0 end
	return value[1] or 0, value[2] or 0, value[3] or 0
end

local function getFlashlightOffsets(location)
	local ids = flashlightOffsetIds[location] or flashlightOffsetIds[FlashlightLocation.Head]
	local px, py, pz = vec3FromConfig(configui.getValue(ids.position))
	local rx, ry, rz = vec3FromConfig(configui.getValue(ids.rotation))
	return px, py, pz, rx, ry, rz
end

local function applyFlashlightOffsets(state, location)
	if state == nil then return end
	local px, py, pz, rx, ry, rz = getFlashlightOffsets(location)
	state:set_location_offset(Vector3f.new(px, py, pz))
	state:set_rotation_offset(Vector3f.new(math.rad(rx), math.rad(ry), math.rad(rz)))
end

local function updateFlashlightOffsetVisibility(location)
	location = location or configui.getValue("flashlight_location") or FlashlightLocation.Head
	for loc, ids in pairs(flashlightOffsetIds) do
		local hidden = loc ~= location
		configui.setHidden(ids.position, hidden)
		configui.setHidden(ids.rotation, hidden)
	end
end

local function attachFlashlightToController(force)
	local pawn = uevrUtils.get_local_pawn()
	if pawn == nil then return end

	local light = pawn.ScopedSpotlight or pawn.ScopedSpotlightComponent
	if uevrUtils.getValid(light) == nil then return end

	local location = configui.getValue("flashlight_location") or FlashlightLocation.Head
	local hand = flashlightHandFromLocation(location)
	if not force and flashlightStatus.light == light and flashlightStatus.state ~= nil and flashlightStatus.hand == hand then
		applyFlashlightOffsets(flashlightStatus.state, location)
		return
	end

	local springArm = pawn.SpringArm1 or pawn.SpringArmComponentForTorch
	if uevrUtils.getValid(springArm) ~= nil then
		pcall(function() springArm.bUsePawnControlRotation = false end)
	end

	if flashlightStatus.light ~= nil then
		pcall(function() UEVR_UObjectHook.remove_motion_controller_state(flashlightStatus.light) end)
	end

	pcall(function()
		light:DetachFromParent(false, false)
	end)
	uevrUtils.set_component_relative_rotation(light, {Pitch = 0, Yaw = 0, Roll = 0})
	uevrUtils.set_component_relative_location(light, {X = 0, Y = 0, Z = 0})

	local state = UEVR_UObjectHook.get_or_add_motion_controller_state(light)
	if state == nil then return end
	state:set_hand(hand)
	state:set_permanent(true)
	applyFlashlightOffsets(state, location)

	flashlightStatus.light = light
	flashlightStatus.state = state
	flashlightStatus.hand = hand
end

configui.onCreateOrUpdate("flashlight_location", function(value)
	updateFlashlightOffsetVisibility(value)
	attachFlashlightToController(true)
end)

for _, ids in pairs(flashlightOffsetIds) do
	configui.onCreateOrUpdate(ids.position, function()
		attachFlashlightToController(false)
	end)
	configui.onCreateOrUpdate(ids.rotation, function()
		attachFlashlightToController(false)
	end)
end
--------------------- End flashlight --------------------------------

function on_level_change(level, levelName)
	hideReticule(true)
	regenerateHands(configui.getValue("hands_type"))
	gestures.autoDetectGesture(gestures.Gesture.SWIPE_RIGHT, false)
    gestures.autoDetectGesture(gestures.Gesture.SWIPE_LEFT, false)
	flashlightStatus = {}
	updateFlashlightOffsetVisibility()
	attachFlashlightToController(true)
end

uevrUtils.setInterval(1000, function()
	attachFlashlightToController(false)
	--applyRangedWeaponMuzzleAim()
end)


function on_post_engine_tick(engine, delta)
	if blockGripAfterThrow then
		setEquippedWeaponHidden(true)
	end
	local animInstance = uevrUtils.getValid(pawn, {"MeshFirstPerson", "AnimScriptInstance"})
	if animInstance ~= nil then
		--this stops the pawn body from distorting with right controller pitch change.
		animInstance.UseFPCameraRotation = false
		-- animInstance.__CustomProperty_UseFPCameraRotation_46F4C949444CC010A691BB88CA8E4C8C = false
		-- animInstance.__CustomProperty_Pitch_46F4C949444CC010A691BB88CA8E4C8C = 0.0
		-- animInstance.__CustomProperty_Yaw_46F4C949444CC010A691BB88CA8E4C8C = 0.0
		--print("here")
	end
end

---------------------------------------------------------------------------
-- MeshFirstPerson materials: keep body slots, hide arms/gloves/accessories.
-- Match against the object/parent *asset name* only (not the full path — pawn
-- names like Skin_PremiumCosplay would false-keep every MID).
-- Do not keep generic "skin": MI_*Skin is torso/body skin on FP meshes.
---------------------------------------------------------------------------
local keepList = { "lower", "skinlegs" }

local hiddenMaterialIds = {}
local lastMaterialCount = -1

local function getMeshFirstPerson()
	return uevrUtils.getObjectFromDescriptor("Pawn.MeshFirstPerson")
end

local function getNumMaterials(mesh)
	if mesh == nil or mesh.GetNumMaterials == nil then return 0 end
	local ok, n = pcall(function() return mesh:GetNumMaterials() end)
	return (ok and type(n) == "number") and n or 0
end

local function getMaterialFullName(mat)
	if mat == nil then return nil end
	local ok, full = pcall(function() return mat:get_full_name() end)
	return (ok and type(full) == "string") and full or nil
end

local function getMaterialLabel(mat)
	if mat == nil then return "(nil)" end
	local label = getMaterialFullName(mat) or tostring(mat)
	local parent = nil
	pcall(function() parent = mat.Parent end)
	if parent == nil and mat.GetBaseMaterial ~= nil then
		pcall(function() parent = mat:GetBaseMaterial() end)
	end
	local parentName = getMaterialFullName(parent)
	if parentName ~= nil then
		label = label .. " | parent=" .. parentName
	end
	return label
end

-- Short asset name: "MI_FemRogueZSLower" from a full path, never the pawn/map prefix.
local function getObjectAssetName(obj)
	if obj == nil then return nil end
	local ok, fname = pcall(function()
		if obj.get_fname ~= nil then
			local n = obj:get_fname()
			if type(n) == "string" then return n end
			if n ~= nil and n.to_string ~= nil then return n:to_string() end
		end
		return nil
	end)
	if ok and type(fname) == "string" and fname ~= "" then
		return string.lower(fname)
	end
	local full = getMaterialFullName(obj)
	if full == nil then return nil end
	local name = string.match(full, "%.([^%.]+)$") or full
	return string.lower(name)
end

-- MIC / MID asset names only; skip base Material assets (M_Skin / M_Clothing).
local function getMaterialMatchTexts(mat)
	local texts = {}
	local function add(obj)
		if obj == nil then return end
		local full = getMaterialFullName(obj)
		if type(full) == "string" and string.find(full, "Material /", 1, true)
			and not string.find(full, "MaterialInstance", 1, true) then
			return
		end
		local name = getObjectAssetName(obj)
		if name ~= nil then
			table.insert(texts, name)
		end
	end
	add(mat)
	local parent = nil
	pcall(function() parent = mat.Parent end)
	add(parent)
	return texts
end

local function materialShouldKeep(mat)
	if mat == nil then return false end
	for _, text in ipairs(getMaterialMatchTexts(mat)) do
		for _, sub in ipairs(keepList) do
			if string.find(text, sub, 1, true) then
				return true
			end
		end
	end
	return false
end

local maxSectionProbe = 32

local function setMaterialSectionVisible(mesh, matId, visible)
	-- ShowMaterialSection only applies when RenderSections[section].MaterialIndex == matId.
	-- Glove/hand slots on ZS mesh use section indices past GetNumMaterials()-1.
	local sectionCount = math.max(getNumMaterials(mesh), maxSectionProbe)
	for sectionIdx = 0, sectionCount - 1 do
		pcall(function() mesh:ShowMaterialSection(matId, sectionIdx, visible, 0) end)
	end
end

local function restoreMeshFirstPersonSections(mesh)
	if mesh == nil then return end
	if mesh.ShowAllMaterialSections ~= nil then
		pcall(function() mesh:ShowAllMaterialSections(0) end)
	end
	for matId = 0, getNumMaterials(mesh) - 1 do
		setMaterialSectionVisible(mesh, matId, true)
	end
end

local function findMaterialsToHide(mesh)
	local ids = {}
	for i = 0, getNumMaterials(mesh) - 1 do
		local ok, mat = pcall(function() return mesh:GetMaterial(i) end)
		if not materialShouldKeep(ok and mat or nil) then
			table.insert(ids, i)
		end
	end
	return ids
end

local function applyHiddenMaterials(mesh)
	for _, matId in ipairs(hiddenMaterialIds) do
		setMaterialSectionVisible(mesh, matId, false)
	end
end

local function refreshHiddenMaterials(mesh)
	hiddenMaterialIds = findMaterialsToHide(mesh)
	lastMaterialCount = getNumMaterials(mesh)
	applyHiddenMaterials(mesh)
end

local function maintainMeshFirstPersonMaterials()
	if status.fpMaterialsHidden == false then return end
	local mesh = getMeshFirstPerson()
	if uevrUtils.getValid(mesh) == nil then return end
	-- Always re-apply. Do not gate on fpMaterialsHidden — restore leaves that false and
	-- the interval would otherwise never hide glove/arms again.
	if getNumMaterials(mesh) ~= lastMaterialCount or #hiddenMaterialIds == 0 then
		refreshHiddenMaterials(mesh)
	else
		applyHiddenMaterials(mesh)
	end
end

local function setMeshFirstPersonMaterialsHidden(hidden)
	status.fpMaterialsHidden = hidden
	local mesh = getMeshFirstPerson()
	if uevrUtils.getValid(mesh) == nil then return end
	if hidden then
		refreshHiddenMaterials(mesh)
	else
		restoreMeshFirstPersonSections(mesh)
	end
end

-- UI pawnArmBones: true = Enable (show). Montage pawnArmBones: true = Hidden, false = Visible.
local uiArmBones = nil
local montageArmBones = nil
local function syncFpMaterialsToArmBoneState()
	local showBody = uiArmBones == true or montageArmBones == false
	setMeshFirstPersonMaterialsHidden(not showBody)
end
ui.onUpdate("pawnArmBones", function(value)
	uiArmBones = value
	syncFpMaterialsToArmBoneState()
end)
montage.onUpdate("pawnArmBones", function(value)
	montageArmBones = value
	syncFpMaterialsToArmBoneState()
end)

local function dumpMeshFirstPersonMaterials()
	local mesh = getMeshFirstPerson()
	if uevrUtils.getValid(mesh) == nil then
		print("[DI2] MeshFirstPerson not found")
		return
	end
	local meshName = getMaterialFullName(mesh) or tostring(mesh)
	print("[DI2] MeshFirstPerson: " .. meshName)
	local numMaterials = getNumMaterials(mesh)
	print("[DI2] GetNumMaterials: " .. tostring(numMaterials))
	for i = 0, numMaterials - 1 do
		local ok, mat = pcall(function() return mesh:GetMaterial(i) end)
		mat = ok and mat or nil
		local action = materialShouldKeep(mat) and "KEEP" or "HIDE"
		print(string.format("[DI2] Material[%d] [%s]: %s", i, action, getMaterialLabel(mat)))
	end
	if #hiddenMaterialIds > 0 then
		print("[DI2] Currently hidden ids: " .. table.concat(hiddenMaterialIds, ", "))
	end
end

uevrUtils.delay(500, maintainMeshFirstPersonMaterials)
uevrUtils.setInterval(2000, maintainMeshFirstPersonMaterials)
----------------------- End body mesh hiding -----------------------------


-- local lastTrackedPawn = nil
-- local pendingFirstPersonRestore = false

-- local function restoreFirstPersonView(fullReset)
-- 	input.reset()
-- 	flashlightStatus = {}
-- 	lastMaterialCount = -1
-- 	hiddenMaterialIds = {}
-- 	local localPawn = uevrUtils.get_local_pawn()
-- 	if uevrUtils.getValid(localPawn) == nil then
-- 		return
-- 	end
-- 	pcall(function()
-- 		if localPawn.SetPerspective ~= nil then
-- 			localPawn:SetPerspective(1)
-- 		end
-- 	end)
-- 	pcall(function()
-- 		local cam = localPawn.FirstPersonPlayerCamera
-- 		local mesh = localPawn.MeshFirstPerson
-- 		if cam ~= nil and mesh ~= nil and cam.K2_AttachTo ~= nil then
-- 			cam:K2_AttachTo(mesh, uevrUtils.fname_from_string("camera_root"), 0, false)
-- 		end
-- 	end)
-- 	if fullReset then
-- 		attachFlashlightToController(true)
-- 		regenerateHands(configui.getValue("hands_type"))
-- 		uevrUtils.delay(200, maintainMeshFirstPersonMaterials)
-- 	end
-- end

-- Show body when knocked down
-- TODO show/hide arms bones and enable/disable input for montage
montage.registerMontageChangeCallback(function(montageObject, montageName, label)
	--if montageName starts with "AM_Base_Hit_Knockdown" then
	if uevrUtils.startsWith(montageName, "AM_Base_Hit_Knockdown") then
		setMeshFirstPersonMaterialsHidden(false)
		input.setDisabled(true)
		status.knockdown = true
	elseif status.knockdown == true then
		setMeshFirstPersonMaterialsHidden(true)
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
				pcall(function()
					local cls = menu:get_class()
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
	pcall(function()
		if lastActiveScaleformMenus["BP_HUDObject_Fader_C"] ~= true then return end
		local widget = uevrUtils.find_first_of("Class /Script/DeadIsland.ManualHUDFaderWidget", false)
		if widget.EasedEffectValue > 0.05 then return end
		status.fader:GetAsset("Fader"):SetRootVisibility(false)
		uevrUtils.stopFadeCamera()
		print("[DI2] stuck movie fader, hiding")
	end)
end)

uevrUtils.registerUEVRCallback("scaleform_ui_change", function(className, visible)
	print("[DI2] scaleform_ui_change", className, visible)
	if className == "BP_MenuInstance_Locker_C" or className == "BP_HUDObject_FailScreen_C" and visible == false then
		regenerateHands(configui.getValue("hands_type"))
		--input.reset()
	elseif className == "BP_HUDObject_Fader_C" then
		if visible == true then
			uevrUtils.fadeCamera(0.1)
		else
			uevrUtils.stopFadeCamera()
		end
	end
end)
--------------------- End Special Scaleform UI handlers -----------------------------

-- function on_client_restart(newPawn)
-- 	lastTrackedPawn = newPawn
-- 	if lastActiveScaleformMenus["BP_MenuInstance_Locker_C"] == true then
-- 		pendingFirstPersonRestore = true
-- 		return
-- 	end
-- 	uevrUtils.delay(250, function()
-- 		restoreFirstPersonView(true)
-- 	end)
-- end

register_key_bind("F1", dumpMeshFirstPersonMaterials)

configui.create(configDefinition)

local meshHidden = false
register_key_bind("F2", function()
	meshHidden = not meshHidden
	setMeshFirstPersonMaterialsHidden(meshHidden)
end)

register_key_bind("F3", function()
	pcall(function()
		if uevrUtils.getValid(status.fader) == nil then
			status.fader = uevrUtils.find_first_of("Class /Script/DeadIsland.HUDObject_Fader", false)
		end
		local movie = status.fader:GetAsset("Fader")
		movie:SetRootVisibility(false)
		uevrUtils.stopFadeCamera()
		print("[DI2] fader SetRootVisibility(false)", movie:GetRootVisibility())
	end)
end)

uevrUtils.registerOnPreInputGetStateCallback(function(retval, user_index, state)
	--print(state.Gamepad.sThumbRY)
end)



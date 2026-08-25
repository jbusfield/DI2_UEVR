local uevrUtils = require('libs/uevr_utils')
local configui = require('libs/configui')
local ui = require('libs/ui')
local montage = require('libs/montage')

local M = {}

-- false = material-section hide (default, cheaper). true = poseable arm-bone scale.
local useSkeletalHiding = false
-- Desired arms-hidden state shared by both modes (true = hide arms / show legs).
local desiredHidden = true
local counterSequence = nil

---------------------------------------------------------------------------
-- Materials mode: keep body slots, hide arms/gloves/accessories.
-- Match MIC/MID short names only (not full paths). Do not keep generic "skin".
-- Refresh always hides every section index. Maintain only re-hides if the
-- game re-showed a slot. Do not trust IsMaterialSectionShown to pick a cheaper
-- hide — after skeletal a single-section hide flips that flag while hands stay.
---------------------------------------------------------------------------
local keepList = { "lower", "skinlegs" }
local maxSectionProbe = 32

local hiddenMaterialIds = {}
local lastMaterialCount = -1
local lastMaterialsMesh = nil
local fpMaterialsHidden = nil
local cachedFpMaterialsMesh = nil
local maintainMaterials

local function getMeshFirstPerson()
	if cachedFpMaterialsMesh ~= nil and uevrUtils.getValid(cachedFpMaterialsMesh) ~= nil then
		return cachedFpMaterialsMesh
	end
	cachedFpMaterialsMesh = uevrUtils.getObjectFromDescriptor("Pawn.MeshFirstPerson")
	return cachedFpMaterialsMesh
end

local function materialShouldKeep(mat)
	if uevrUtils.getValid(mat) == nil then return false end
	local function matchesKeep(obj)
		if uevrUtils.getValid(obj) == nil then return false end
		local full = obj:get_full_name()
		if string.find(full, "Material /", 1, true)
			and not string.find(full, "MaterialInstance", 1, true) then
			return false
		end
		local name = string.lower(uevrUtils.getShortName(obj))
		for _, sub in ipairs(keepList) do
			if string.find(name, sub, 1, true) then return true end
		end
		return false
	end
	return matchesKeep(mat) or matchesKeep(mat.Parent)
end

local function hideMatSections(mesh, matId, sectionCount)
	local show = mesh.ShowMaterialSection
	for sectionIdx = 0, sectionCount - 1 do
		show(mesh, matId, sectionIdx, false, 0)
	end
end

local function hideListedMaterials(mesh)
	for i = 1, #hiddenMaterialIds do
		hideMatSections(mesh, hiddenMaterialIds[i], maxSectionProbe)
	end
end

-- Hot path: only pay for ShowMaterialSection if the game re-showed the slot.
local function applyDirty(mesh)
	local isShown = mesh.IsMaterialSectionShown
	local ids = hiddenMaterialIds
	for i = 1, #ids do
		if isShown(mesh, ids[i], 0) then
			hideMatSections(mesh, ids[i], maxSectionProbe)
		end
	end
end

local function restoreMeshFirstPersonSections(mesh)
	if mesh == nil then return end
	if mesh.ShowAllMaterialSections ~= nil then
		mesh:ShowAllMaterialSections(0)
	end
	hiddenMaterialIds = {}
	lastMaterialCount = -1
	lastMaterialsMesh = nil
end

local function refreshHiddenMaterials(mesh)
	local n = mesh:GetNumMaterials()
	hiddenMaterialIds = {}
	for i = 0, n - 1 do
		if not materialShouldKeep(mesh:GetMaterial(i)) then
			hiddenMaterialIds[#hiddenMaterialIds + 1] = i
		end
	end
	lastMaterialCount = n
	lastMaterialsMesh = mesh
	hideListedMaterials(mesh)
end

local function cleanupMaterialsMode()
	-- Leave section hides on the source mesh. Clearing fpMaterialsHidden here
	-- would stop maintain from re-hiding after death while skeletal is on.
	hiddenMaterialIds = {}
	lastMaterialCount = -1
	lastMaterialsMesh = nil
	cachedFpMaterialsMesh = nil
end

local function setMaterialsHidden(hidden)
	fpMaterialsHidden = hidden == true
	cachedFpMaterialsMesh = nil
	lastMaterialsMesh = nil
	hiddenMaterialIds = {}
	lastMaterialCount = -1
	if not fpMaterialsHidden then
		local mesh = getMeshFirstPerson()
		if uevrUtils.getValid(mesh) ~= nil then
			restoreMeshFirstPersonSections(mesh)
		end
		return
	end
	-- Same as a materials-mode start: hide on the delayed maintain, not this frame.
	uevrUtils.delay(200, maintainMaterials)
end

maintainMaterials = function()
	if fpMaterialsHidden == false then return end
	local mesh = getMeshFirstPerson()
	if mesh == nil then return end
	-- New mesh after death/respawn (same material count) must rediscover, not dirty-check.
	if mesh ~= lastMaterialsMesh or #hiddenMaterialIds == 0 then
		refreshHiddenMaterials(mesh)
		return
	end
	if mesh:GetNumMaterials() ~= lastMaterialCount then
		refreshHiddenMaterials(mesh)
		return
	end
	applyDirty(mesh)
end
maintainMaterials = uevrUtils.profiler:wrap("Body: maintainMaterials", maintainMaterials)

function M.dumpMeshFirstPersonMaterials()
	local mesh = getMeshFirstPerson()
	if uevrUtils.getValid(mesh) == nil then
		print("[DI2] MeshFirstPerson not found")
		return
	end
	print("[DI2] MeshFirstPerson: " .. uevrUtils.getShortName(mesh))
	local n = mesh:GetNumMaterials()
	print("[DI2] GetNumMaterials: " .. tostring(n))
	for i = 0, n - 1 do
		local mat = mesh:GetMaterial(i)
		local action = materialShouldKeep(mat) and "KEEP" or "HIDE"
		local parent = mat and mat.Parent or nil
		local label = uevrUtils.getShortName(mat)
		if parent ~= nil then
			label = label .. " | parent=" .. uevrUtils.getShortName(parent)
		end
		print(string.format("[DI2] Material[%d] [%s]: %s", i, action, label))
	end
	if #hiddenMaterialIds > 0 then
		print("[DI2] Currently hidden ids: " .. table.concat(hiddenMaterialIds, ", "))
	end
end

---------------------------------------------------------------------------
-- Skeletal mode: poseable copy with arm bones scaled down.
-- Only destroy poseables we created (tracked in createdPoseables).
---------------------------------------------------------------------------
local armBones = { "clavicle_l", "clavicle_r", "upperarm_l", "upperarm_r" }
local armBoneScale = uevrUtils.vector(0.001, 0.001, 0.001)
local armBoneFNames = nil

local poseableBodyActive = false
local renderMesh = nil
local sourceMesh = nil
local sourceSkeletalMesh = nil
local sourceRenderSuppressed = false
local cachedFpMesh = nil
local createdPoseables = {}

local function getArmBoneFNames()
	if armBoneFNames == nil then
		armBoneFNames = {}
		for i = 1, #armBones do
			armBoneFNames[i] = uevrUtils.fname_from_string(armBones[i])
		end
	end
	return armBoneFNames
end

local function getMesh()
	if cachedFpMesh ~= nil and uevrUtils.getValid(cachedFpMesh) ~= nil then
		return cachedFpMesh
	end
	cachedFpMesh = uevrUtils.getObjectFromDescriptor("Pawn.MeshFirstPerson")
	return cachedFpMesh
end

local function destroyTrackedPoseable(comp)
	if uevrUtils.getValid(comp) == nil then return end
	uevrUtils.detachAndDestroyComponent(comp, false, false)
end

local function destroyAllCreatedPoseables()
	for i = 1, #createdPoseables do
		destroyTrackedPoseable(createdPoseables[i])
		createdPoseables[i] = nil
	end
	createdPoseables = {}
	renderMesh = nil
	sourceMesh = nil
	sourceSkeletalMesh = nil
	sourceRenderSuppressed = false
end

local function hideArmBonesOnCopy(copy)
	local names = getArmBoneFNames()
	for i = 1, #names do
		copy:SetBoneScaleByName(names[i], armBoneScale, 0)
	end
end

local function disableCopyShadows(copy)
	copy:SetCastShadow(false)
	copy.bCastDynamicShadow = false
	copy.bCastStaticShadow = false
	copy.bCastFarShadow = false
	copy.bCastInsetShadow = false
	copy.bCastCapsuleDirectShadow = false
	copy.bCastCapsuleIndirectShadow = false
end

local function setSourceRendering(mesh, enabled)
	if uevrUtils.getValid(mesh) == nil then return end
	mesh:call("SetRenderInMainPass", enabled == true)
	mesh.bRenderInDepthPass = enabled == true
	if mesh.bRenderNearest ~= nil then
		mesh.bRenderNearest = enabled == true
	end
	sourceRenderSuppressed = enabled ~= true
end

local function createRenderMesh(mesh)
	destroyAllCreatedPoseables()
	local owner = mesh.GetOwner ~= nil and mesh:GetOwner() or nil
	if uevrUtils.getValid(owner) == nil or uevrUtils.getValid(mesh.SkeletalMesh) == nil then return nil end

	-- manualAttachment=true: register on pawn without auto-attaching to capsule.
	local newRenderMesh = uevrUtils.create_component_of_class( "Class /Script/Engine.PoseableMeshComponent", true, nil, false, owner, nil )
	if newRenderMesh == nil or uevrUtils.getValid(newRenderMesh) == nil then return nil end
	createdPoseables[#createdPoseables + 1] = newRenderMesh

	newRenderMesh.SkeletalMesh = mesh.SkeletalMesh
	if newRenderMesh.SetMasterPoseComponent ~= nil then
		newRenderMesh:SetMasterPoseComponent(mesh, true)
		newRenderMesh:SetMasterPoseComponent(nil, false)
	elseif newRenderMesh.SetLeaderPoseComponent ~= nil then
		newRenderMesh:SetLeaderPoseComponent(mesh, true)
		newRenderMesh:SetLeaderPoseComponent(nil, false)
	end
	pcall(function()
		newRenderMesh:CopyPoseFromSkeletalComponent(mesh)
	end)

	newRenderMesh:K2_AttachToComponent(mesh, "", 0, 0, 0, false)
	newRenderMesh:SetCollisionEnabled(0, false)
	newRenderMesh:SetVisibility(true, false)
	newRenderMesh:SetHiddenInGame(false, false)
	newRenderMesh:call("SetRenderInMainPass", true)
	if newRenderMesh.bRenderNearest ~= nil then
		newRenderMesh.bRenderNearest = true
	end
	newRenderMesh.bOnlyOwnerSee = true
	disableCopyShadows(newRenderMesh)

	renderMesh = newRenderMesh
	sourceMesh = mesh
	sourceSkeletalMesh = mesh.SkeletalMesh
	uevrUtils.copyMaterials(mesh, newRenderMesh, false)
	hideArmBonesOnCopy(newRenderMesh)
	return newRenderMesh
end

local function ensureRenderMesh(mesh)
	if mesh == nil or mesh.SkeletalMesh == nil then
		destroyAllCreatedPoseables()
		return nil
	end
	if renderMesh ~= nil and sourceMesh == mesh and sourceSkeletalMesh == mesh.SkeletalMesh then
		return renderMesh
	end
	return createRenderMesh(mesh)
end

local function stopPoseableBody()
	local mesh = getMesh()
	destroyAllCreatedPoseables()
	cachedFpMesh = nil
	if uevrUtils.getValid(mesh) ~= nil then
		setSourceRendering(mesh, true)
	end
end

local function cleanupSkeletalMode()
	stopPoseableBody()
	poseableBodyActive = false
end

local function updateRenderMesh()
	if not useSkeletalHiding or poseableBodyActive ~= true then return end

	local mesh = getMesh()
	if mesh == nil then
		destroyAllCreatedPoseables()
		return
	end

	local copy = ensureRenderMesh(mesh)
	if copy == nil then return end

	copy:CopyPoseFromSkeletalComponent(mesh)
	hideArmBonesOnCopy(copy)

	if not sourceRenderSuppressed or mesh.bRenderNearest == true then
		setSourceRendering(mesh, false)
	end
end
updateRenderMesh = uevrUtils.profiler:wrap("Body: updateRenderMesh", updateRenderMesh)

local function setSkeletalHidden(hidden)
	poseableBodyActive = hidden == true
	if poseableBodyActive then
		updateRenderMesh()
	else
		stopPoseableBody()
	end
end

---------------------------------------------------------------------------
-- Shared API / mode switching
---------------------------------------------------------------------------
local function applyHidden(hidden)
	-- Always hide/restore sections on the original FP mesh. Death restores them
	-- even while skeletal mode is on and the source starts drawing again.
	setMaterialsHidden(hidden == true)
	if useSkeletalHiding then
		setSkeletalHidden(hidden == true)
	end
end

function M.setHidden(hidden)
	desiredHidden = hidden == true
	if counterSequence then
		applyHidden(false)
		return
	end
	applyHidden(desiredHidden)
end

local function setSkeletalHidingEnabled(enabled)
	enabled = enabled == true
	if enabled == useSkeletalHiding then return end

	if useSkeletalHiding then
		cleanupSkeletalMode()
	else
		cleanupMaterialsMode()
	end

	useSkeletalHiding = enabled
	if counterSequence then
		applyHidden(false)
	else
		applyHidden(desiredHidden)
	end
end

function M.setCounterSequence(active)
	counterSequence = active == true
	if counterSequence then
		applyHidden(false)
	else
		applyHidden(desiredHidden)
	end
end

-- UI: true=Enable (show). Montage: Hidden->true, Visible->false.
local uiArmBones, montageArmBones = nil, nil
local armBoneStateSeen = false
local function syncToArmBoneState()
	if counterSequence then
		applyHidden(false)
		return
	end
	if uiArmBones == nil and montageArmBones == nil then
		if armBoneStateSeen then
			M.setHidden(true)
		end
		return
	end
	armBoneStateSeen = true
	local showFullFpBody = uiArmBones == true or montageArmBones == false
	M.setHidden(not showFullFpBody)
end

ui.onUpdate("pawnArmBones", function(value)
	uiArmBones = value
	syncToArmBoneState()
end)

montage.onUpdate("pawnArmBones", function(value)
	montageArmBones = value
	syncToArmBoneState()
end)

configui.onCreateOrUpdate("use_skeletal_mesh_hiding", function(value)
	setSkeletalHidingEnabled(value == true)
end)

uevrUtils.delay(200, maintainMaterials)
uevrUtils.setInterval(2000, maintainMaterials)

uevrUtils.registerPostEngineTickCallback(function()
	updateRenderMesh()
end)

uevrUtils.registerPreLevelChangeCallback(function()
	cachedFpMaterialsMesh = nil
	cachedFpMesh = nil
	lastMaterialsMesh = nil
	hiddenMaterialIds = {}
	destroyAllCreatedPoseables()
end)

-- uevrUtils.registerUEVRCallback("on_client_restart", function()
-- 	cachedFpMaterialsMesh = nil
-- 	cachedFpMesh = nil
-- 	lastMaterialsMesh = nil
-- 	hiddenMaterialIds = {}
-- 	uevrUtils.delay(200, maintainMaterials)
-- end)

uevr.params.sdk.callbacks.on_script_reset(function()
	destroyAllCreatedPoseables()
end)

return M


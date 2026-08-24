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
-- Match against the object/parent *asset name* only (not the full path — pawn
-- names like Skin_PremiumCosplay would false-keep every MID).
-- Do not keep generic "skin": MI_*Skin is torso/body skin on FP meshes.
---------------------------------------------------------------------------
local keepList = { "lower", "skinlegs" }

local hiddenMaterialIds = {}
local lastMaterialCount = -1
local fpMaterialsHidden = nil

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

local function cleanupMaterialsMode()
	local mesh = getMeshFirstPerson()
	if uevrUtils.getValid(mesh) ~= nil then
		restoreMeshFirstPersonSections(mesh)
	end
	hiddenMaterialIds = {}
	lastMaterialCount = -1
	fpMaterialsHidden = false
end

local function setMaterialsHidden(hidden)
	fpMaterialsHidden = hidden == true
	local mesh = getMeshFirstPerson()
	if uevrUtils.getValid(mesh) == nil then return end
	if fpMaterialsHidden then
		refreshHiddenMaterials(mesh)
	else
		restoreMeshFirstPersonSections(mesh)
	end
end

local function maintainMaterials()
	if useSkeletalHiding or fpMaterialsHidden == false then return end
	local mesh = getMeshFirstPerson()
	if uevrUtils.getValid(mesh) == nil then return end
	if getNumMaterials(mesh) ~= lastMaterialCount or #hiddenMaterialIds == 0 then
		refreshHiddenMaterials(mesh)
	else
		applyHiddenMaterials(mesh)
	end
end
maintainMaterials = uevrUtils.profiler:wrap("Body: maintainMaterials", maintainMaterials)

function M.dumpMeshFirstPersonMaterials()
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

---------------------------------------------------------------------------
-- Skeletal mode: poseable copy with arm bones scaled down.
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

local function destroyRenderMesh()
	if uevrUtils.getValid(renderMesh) ~= nil then
		---@diagnostic disable-next-line: need-check-nil, undefined-field
		renderMesh:K2_DestroyComponent()
	end
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

local function destroyOrphanPoseables(owner)
	if uevrUtils.getValid(owner) == nil then return end
	local comps = nil
	pcall(function()
		comps = owner:K2_GetComponentsByClass(uevrUtils.get_class("Class /Script/Engine.PoseableMeshComponent"))
	end)
	if comps == nil then return end
	local function consider(comp)
		if uevrUtils.getValid(comp) == nil then return end
		pcall(function()
			comp:call("SetRenderInMainPass", false)
			if comp.bRenderNearest ~= nil then comp.bRenderNearest = false end
			comp:K2_DestroyComponent()
		end)
	end
	if comps[0] ~= nil or (type(comps) == "userdata") then
		for i = 0, 16 do
			local c = comps[i]
			if c == nil then break end
			consider(c)
		end
	elseif type(comps) == "table" then
		for _, c in pairs(comps) do
			consider(c)
		end
	end
end

local function createRenderMesh(mesh)
	destroyRenderMesh()
	local owner = mesh.GetOwner ~= nil and mesh:GetOwner() or nil
	if uevrUtils.getValid(owner) == nil or uevrUtils.getValid(mesh.SkeletalMesh) == nil then return nil end
	destroyOrphanPoseables(owner)

	local newRenderMesh = uevrUtils.create_component_of_class(
		"Class /Script/Engine.PoseableMeshComponent",
		false, nil, false, owner, nil
	)
	if newRenderMesh == nil or uevrUtils.getValid(newRenderMesh) == nil then return nil end
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
		destroyRenderMesh()
		return nil
	end
	if renderMesh ~= nil and sourceMesh == mesh and sourceSkeletalMesh == mesh.SkeletalMesh then
		return renderMesh
	end
	return createRenderMesh(mesh)
end

local function stopPoseableBody()
	local mesh = getMesh()
	destroyRenderMesh()
	cachedFpMesh = nil
	if uevrUtils.getValid(mesh) ~= nil then
		local owner = mesh.GetOwner ~= nil and mesh:GetOwner() or nil
		destroyOrphanPoseables(owner)
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
		destroyRenderMesh()
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
	if useSkeletalHiding then
		setSkeletalHidden(hidden == true)
	else
		setMaterialsHidden(hidden == true)
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

-- UI: true=Enable (show). Montage: Hidden→true, Visible→false.
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

uevrUtils.delay(500, maintainMaterials)
uevrUtils.setInterval(2000, maintainMaterials)

uevrUtils.registerPostEngineTickCallback(function()
	updateRenderMesh()
end)

uevrUtils.registerPreLevelChangeCallback(function()
	cachedFpMesh = nil
	if useSkeletalHiding then
		stopPoseableBody()
	end
end)

return M
--[[
    local particles = require("libs/particles")
    particles.init()

    -- From a saved profile (Particles Config Dev: New / Rename / etc.)
    -- create() tracks by profile key: reuses a live instance, or rebuilds if gone.
    -- destroyAll() on level change / script reset; optional particles.destroy("WandTip") or tip:destroy()
    local tip = particles.create("WandTip")
    tip:attachTo(wandMesh, "MuzzleSocket")

    -- Or build inline (no profile required)
    local plasma = particles.new({
        particleSystemAsset = "ParticleSystem /Game/.../PS_Plasma_Ball.PS_Plasma_Ball",
        scale = {0.04, 0.04, 0.04},
    })
    plasma:attachTo(weaponMesh, "muzzle_socket")
    plasma:destroy()

    -- loopStart+loopEnd: double-buffer a finite FX over that window
    local tip = particles.new({
        particleSystemAsset = "NiagaraSystem /Game/.../SomeSystem.SomeSystem",
        loopStart = 1.0,
        loopEnd = 3.0,
        scale = {0.04, 0.04, 0.04},
    })
]]--
local uevrUtils = require("libs/uevr_utils")
local paramModule = require("libs/core/params")
local plugin = require("libs/core/plugin")
require("libs/enums/unreal")

local M = {}

local particlesConfigDev = nil
local currentLogLevel = LogLevel.Error
local parametersFileName = "particles_parameters"
local activeInstances = {}
local createdByKey = {}
local parameters = {
	asset = "",
	scale = {0.04, 0.04, 0.04},
	rotation = {0, 0, 0},
	location = {0, 0, 0},
	loop = true,
	loopStart = 1.0,
	loopEnd = 3.0,
	emitters = {},
}

local paramManager = paramModule.new(parametersFileName, parameters, true)

local function registerInstance(inst)
	if inst == nil then return nil end
	table.insert(activeInstances, inst)
	return inst
end

local function unregisterInstance(inst)
	for i = #activeInstances, 1, -1 do
		if activeInstances[i] == inst then
			table.remove(activeInstances, i)
			return
		end
	end
end

local function clearCreatedKey(inst)
	if inst == nil or inst.profileKey == nil then return end
	if createdByKey[inst.profileKey] == inst then
		createdByKey[inst.profileKey] = nil
	end
	inst.profileKey = nil
end

function M.destroyAll()
	if particlesConfigDev ~= nil and particlesConfigDev.stopTest ~= nil then
		particlesConfigDev.stopTest()
	end
	createdByKey = {}
	local list = activeInstances
	activeInstances = {}
	for i = 1, #list do
		local inst = list[i]
		if inst ~= nil and inst.destroy ~= nil then
			inst.profileKey = nil
			inst:destroy()
		end
	end
end

function M.setLogLevel(val)
	currentLogLevel = val
end

function M.print(text, logLevel)
	if logLevel == nil then logLevel = LogLevel.Debug end
	if logLevel <= currentLogLevel then
		uevrUtils.print("[particles] " .. text, logLevel)
	end
end

function M.setParametersFileName(fileName)
	parametersFileName = fileName
	paramManager.fileName = fileName
end

function M.getParamManager()
	return paramManager
end

function M.getParameters()
	return paramManager:getAll()
end

-- Build options from a profile's parameter table (for Test UI or create).
function M.optionsFromProfile(profile)
	if profile == nil or profile.asset == nil or profile.asset == "" then return nil end
	local opts = {
		particleSystemAsset = profile.asset,
		scale = profile.scale or {0.04, 0.04, 0.04},
		rotation = profile.rotation or {0, 0, 0},
		location = profile.location or {0, 0, 0},
		autoActivate = true,
		emitterOverrides = profile.emitters or {},
	}
	if profile.loop == true then
		opts.loopStart = profile.loopStart or 1.0
		opts.loopEnd = profile.loopEnd or 3.0
	end
	return opts
end

local function findProfile(idOrLabel)
	if idOrLabel == nil then return nil, nil end
	local all = paramManager:getAll()
	if all == nil then return nil, nil end
	if idOrLabel ~= "_profileState" and idOrLabel ~= "_profileLabels" and type(all[idOrLabel]) == "table" then
		return idOrLabel, all[idOrLabel]
	end
	local labels = all._profileLabels or {}
	for id, label in pairs(labels) do
		if label == idOrLabel and type(all[id]) == "table" then
			return id, all[id]
		end
	end
	return nil, nil
end

-- Destroy by profile id/label, or by instance. Optional — create() reuses/replaces by key.
function M.destroy(idOrLabelOrInst)
	if idOrLabelOrInst == nil then return end
	if type(idOrLabelOrInst) == "table" and idOrLabelOrInst.destroy ~= nil then
		idOrLabelOrInst:destroy()
		return
	end
	local id = select(1, findProfile(idOrLabelOrInst))
	if id == nil then id = idOrLabelOrInst end
	local inst = createdByKey[id]
	if inst ~= nil then
		inst:destroy()
	end
end

function M.get(idOrLabel)
	local id = select(1, findProfile(idOrLabel))
	if id == nil then return nil end
	local inst = createdByKey[id]
	if inst ~= nil and inst.isValid ~= nil and inst:isValid() then
		return inst
	end
	return nil
end

function M.getPresetList()
	local ids, names = paramManager:getProfiles()
	local list = {}
	for i, id in ipairs(ids) do
		table.insert(list, { id = id, label = names[i] or id })
	end
	return list
end

-- Create/reuse a configured instance from a profile id or label. Caller attaches it.
function M.create(idOrLabel)
	local id, profile = findProfile(idOrLabel)
	if profile == nil then
		M.print("create: profile not found: " .. tostring(idOrLabel), LogLevel.Error)
		return nil
	end
	local existing = createdByKey[id]
	if existing ~= nil then
		if existing.isValid ~= nil and existing:isValid() then
			return existing
		end
		existing:destroy()
	end
	local opts = M.optionsFromProfile(profile)
	if opts == nil then
		M.print("create: profile has no asset: " .. tostring(idOrLabel) .. " (" .. tostring(id) .. ")", LogLevel.Error)
		return nil
	end
	local inst = M.new(opts)
	if inst ~= nil then
		inst.profileKey = id
		createdByKey[id] = inst
		inst:start()
	end
	return inst
end

local function migrateLegacyParticleList()
	local raw = paramManager.parameters
	if raw == nil or raw.particleList == nil then
		return false
	end
	local list = raw.particleList
	local currentId = raw.currentParticleID
	local defaults = paramManager.defaultParameters
	local migrated = {
		_profileState = { currentEditingProfile = "default" },
		_profileLabels = {},
	}
	if #list == 0 then
		migrated.default = uevrUtils.deepCopyTable(defaults)
		migrated._profileLabels.default = "Default"
	else
		local firstId = nil
		for _, p in ipairs(list) do
			local id = p.id or uevrUtils.guid()
			if firstId == nil then firstId = id end
			local opt = p.options or {}
			migrated[id] = {
				asset = p.asset or "",
				scale = opt.scale or uevrUtils.deepCopyTable(defaults.scale),
				rotation = opt.rotation or uevrUtils.deepCopyTable(defaults.rotation),
				location = opt.location or uevrUtils.deepCopyTable(defaults.location),
				loop = opt.loop == true,
				loopStart = opt.loopStart or defaults.loopStart,
				loopEnd = opt.loopEnd or defaults.loopEnd,
				emitters = opt.emitters or {},
			}
			migrated._profileLabels[id] = p.label or id
		end
		if currentId ~= nil and migrated[currentId] ~= nil then
			migrated._profileState.currentEditingProfile = currentId
		elseif firstId ~= nil then
			migrated._profileState.currentEditingProfile = firstId
		end
	end
	paramManager.parameters = migrated
	paramManager.isDirty = true
	return true
end

function M.init(isDeveloperMode, logLevel)
	if logLevel ~= nil then
		M.setLogLevel(logLevel)
	end
	if isDeveloperMode == nil and uevrUtils.getDeveloperMode() ~= nil then
		isDeveloperMode = uevrUtils.getDeveloperMode()
	end
	paramManager:load(false)
	if not migrateLegacyParticleList() then
		paramManager:convertToProfile()
	end
	if isDeveloperMode then
		particlesConfigDev = require("libs/config/particles_config_dev")
		particlesConfigDev.init(paramManager, M)
	end
end

local ParticleSystem = {}
ParticleSystem.__index = ParticleSystem

local function isNiagaraAsset(asset)
	local cls = uevrUtils.get_class("Class /Script/Niagara.NiagaraSystem")
	return asset ~= nil and cls ~= nil and asset:is_a(cls)
end

local function resolveParticleAsset(assetRef)
	if assetRef == nil then
		return nil
	end
	if type(assetRef) ~= "string" then
		return uevrUtils.getValid(assetRef)
	end
	local loaded = uevrUtils.getLoadedAsset(assetRef)
	if loaded ~= nil then
		return loaded
	end
	-- Finder lists resident assets by full name; AssetRegistry can miss Niagara.
	local className = string.find(assetRef, "NiagaraSystem", 1, true)
		and "Class /Script/Niagara.NiagaraSystem"
		or "Class /Script/Engine.ParticleSystem"
	local instances = uevrUtils.find_all_instances(className, false)
	if instances ~= nil then
		for _, inst in pairs(instances) do
			if inst ~= nil and inst:get_full_name() == assetRef then
				return inst
			end
		end
	end
	return nil
end

local function fnameToString(fname)
	if fname == nil then return "?" end
	if type(fname) == "string" then return fname end
	if type(fname) == "userdata" and fname.to_string ~= nil then return fname:to_string() end
	return tostring(fname)
end

local function dumpConfigurableParams(ps, particleComponent, isNiagara)
	if ps == nil then return end
	print("--- particle configurable params ---")
	if isNiagara then
		print(string.format("Niagara flags: bAutoDeactivate=%s bIsInfiniteLooping=%s WarmupTime=%s",
			tostring(ps.bAutoDeactivate), tostring(ps.bIsInfiniteLooping), tostring(ps.WarmupTime)))
		local store = plugin.getProperty(ps, "ExposedParameters")
		if type(store) == "table" then
			local offsets = store.SortedParameterOffsets
			if type(offsets) == "table" then
				print("ExposedParameters: " .. tostring(#offsets))
				for i, entry in ipairs(offsets) do
					if type(entry) == "table" then
						print(string.format("  [%d] %s  offset=%s", i, fnameToString(entry.Name), tostring(entry.Offset)))
					end
				end
			else
				print("ExposedParameters: (no SortedParameterOffsets)")
			end
		end
		local handles = plugin.getProperty(ps, "EmitterHandles")
		if type(handles) == "table" then
			print("Emitters: " .. tostring(#handles))
			for i, h in ipairs(handles) do
				if type(h) == "table" then
					print(string.format("  [%d] %s  enabled=%s", i, fnameToString(h.Name), tostring(h.bIsEnabled)))
				end
			end
		end
	else
		local params = particleComponent and plugin.getProperty(particleComponent, "InstanceParameters")
		if type(params) == "table" then
			print("InstanceParameters: " .. tostring(#params))
			for i, p in ipairs(params) do
				if type(p) == "table" then
					print(string.format("  [%d] %s  type=%s  scalar=%s",
						i, fnameToString(p.Name), tostring(p.ParamType), tostring(p.Scalar)))
				end
			end
		end
	end
	print("--- end params ---")
end

local function listEmitterNamesFromAsset(ps, isNiagara)
	local names, enabled = {}, {}
	if ps == nil then return names, enabled end
	if isNiagara then
		local handles = plugin.getProperty(ps, "EmitterHandles")
		if type(handles) == "table" then
			for _, h in ipairs(handles) do
				if type(h) == "table" and h.Name ~= nil then
					local n = fnameToString(h.Name)
					if n ~= "" and n ~= "?" then
						table.insert(names, n)
						enabled[n] = h.bIsEnabled ~= false
					end
				end
			end
		end
	else
		local emitters = plugin.getProperty(ps, "Emitters")
		if type(emitters) == "table" then
			for _, em in ipairs(emitters) do
				local n = type(em) == "table" and fnameToString(em.EmitterName or em.Name)
					or (em and em.EmitterName and fnameToString(em.EmitterName))
				if n and n ~= "" and n ~= "?" then
					table.insert(names, n)
					enabled[n] = true
				end
			end
		end
	end
	return names, enabled
end

-- Emitter names/defaults from an asset path or object (no spawn required).
function M.listEmittersFromAsset(assetRef)
	local ps = resolveParticleAsset(assetRef)
	if ps == nil then return {}, {} end
	return listEmitterNamesFromAsset(ps, isNiagaraAsset(ps))
end

-- Niagara SetEmitterEnable is a no-op on HL; toggle FNiagaraEmitterHandle.bIsEnabled then Reinitialize.
local function syncNiagaraEmitterEnables(asset, names, defaults, overrides)
	if asset == nil or names == nil then return end
	for i, name in ipairs(names) do
		local on = true
		if overrides and overrides[name] ~= nil then
			on = overrides[name] == true
		elseif defaults and defaults[name] ~= nil then
			on = defaults[name] == true
		end
		local path = "EmitterHandles[" .. (i - 1) .. "]"
		local handle = plugin.getProperty(asset, path)
		if type(handle) == "table" then
			handle.bIsEnabled = on
			plugin.setProperty(asset, path, handle)
		end
	end
end

local function setLeafVisible(inst, visible)
	if inst == nil then return end
	local pc = uevrUtils.getValid(inst.particleComponent)
	if pc ~= nil and pc.SetHiddenInGame ~= nil then
		pc:SetHiddenInGame(not visible, true)
	end
end

local function createLeaf(options)
	local self = setmetatable({
		particleComponent = nil,
		anchorComponent = nil,
		particleSystemAsset = options.particleSystemAsset,
		scale = options.scale or {1, 1, 1},
		rotation = options.rotation or {0, 0, 0},
		location = options.location or {0, 0, 0},
		autoActivate = options.autoActivate ~= false,
		poolMethod = options.poolMethod or EPSCPoolMethod.None,
		collisionEnabled = options.collisionEnabled or ECollisionEnabled.QueryAndPhysics,
		collisionResponse = options.collisionResponse or ECollisionResponse.Block,
		isNiagara = false,
		quiet = options.quiet == true,
		resolvedAsset = nil,
		emitterNames = nil,
		emitterDefaults = nil,
		emitterOverrides = options.emitterOverrides or {},
		restoreEmittersOnDestroy = options.restoreEmittersOnDestroy,
		looping = false,
		visible = true,
	}, ParticleSystem)
	self:create()
	return self
end

function M.new(options)
	options = options or {}
	if not options.particleSystemAsset then
		print("Error: particleSystemAsset is required to create ParticleSystem")
		return
	end

	local loopStart = tonumber(options.loopStart)
	local loopEnd = tonumber(options.loopEnd)
	if loopStart ~= nil and loopEnd ~= nil and loopEnd > loopStart then
		local self = setmetatable({
			particleSystemAsset = options.particleSystemAsset,
			scale = options.scale or {1, 1, 1},
			rotation = options.rotation or {0, 0, 0},
			location = options.location or {0, 0, 0},
			poolMethod = options.poolMethod or EPSCPoolMethod.None,
			collisionEnabled = options.collisionEnabled or ECollisionEnabled.QueryAndPhysics,
			collisionResponse = options.collisionResponse or ECollisionResponse.Block,
			loopStart = loopStart,
			loopEnd = loopEnd,
			period = loopEnd - loopStart,
			rootAnchor = nil,
			buffers = {},
			running = false,
			generation = 0,
			dumpedParams = false,
			emitterOverrides = options.emitterOverrides or {},
			emitterNames = nil,
			emitterDefaults = nil,
			looping = true,
			visible = true,
		}, ParticleSystem)
		self.rootAnchor = uevrUtils.create_component_of_class("Class /Script/Engine.SceneComponent")
		if self.rootAnchor ~= nil then
			self.rootAnchor.RelativeLocation = uevrUtils.vector(self.location)
			self.rootAnchor.RelativeRotation = uevrUtils.rotator(self.rotation)
			self.rootAnchor.RelativeScale3D = uevrUtils.vector(self.scale)
		end
		return registerInstance(self)
	end

	return registerInstance(createLeaf(options))
end

function ParticleSystem:create()
	if self.particleComponent ~= nil then
		return self.particleComponent
	end
	self.anchorComponent = uevrUtils.create_component_of_class("Class /Script/Engine.SceneComponent")
	if self.anchorComponent == nil then
		return nil
	end

	print("Creating particle system: ", self.particleSystemAsset)
	local ps = resolveParticleAsset(self.particleSystemAsset)
	if ps == nil then
		M.print("Failed to resolve particle asset: " .. tostring(self.particleSystemAsset), LogLevel.Error)
		return nil
	end

	self.isNiagara = isNiagaraAsset(ps)
	self.resolvedAsset = ps
	self.emitterNames, self.emitterDefaults = listEmitterNamesFromAsset(ps, self.isNiagara)

	local location = uevrUtils.vector(self.location)
	local rotation = uevrUtils.rotator(self.rotation)
	local scale = uevrUtils.vector(self.scale)
	self.anchorComponent.RelativeLocation = location
	self.anchorComponent.RelativeRotation = rotation
	self.anchorComponent.RelativeScale3D = scale

	if self.isNiagara then
		-- SetAsset/SpawnSystemAttached crash under sol; assign Asset property instead.
		local owner = self.anchorComponent.GetOwner ~= nil and self.anchorComponent:GetOwner() or nil
		self.particleComponent = uevrUtils.create_component_of_class(
			"Class /Script/Niagara.NiagaraComponent", true, nil, false, owner)
		if self.particleComponent ~= nil then
			self.particleComponent.Asset = ps
			self.particleComponent:K2_AttachTo(self.anchorComponent, uevrUtils.fname_from_string(""), 0, false)
			self.particleComponent.bAutoActivate = self.autoActivate
			if next(self.emitterOverrides) ~= nil then
				syncNiagaraEmitterEnables(ps, self.emitterNames, self.emitterDefaults, self.emitterOverrides)
			end
			if self.autoActivate then
				self.particleComponent.bIsActive = true
				plugin.executeFunction(self.particleComponent, "Activate", true)
				plugin.executeFunction(self.particleComponent, "ResetSystem")
			end
		end
	else
		self.particleComponent = Statics:SpawnEmitterAttached(
			ps, self.anchorComponent, uevrUtils.fname_from_string(""),
			location, rotation, scale, EAttachLocation.KeepRelativeOffset,
			true, self.poolMethod, true)
		if self.particleComponent ~= nil then
			self.particleComponent:SetAutoActivate(self.autoActivate)
			self.particleComponent.SecondsBeforeInactive = 0.0
			self.particleComponent:SetCollisionEnabled(self.collisionEnabled)
			self.particleComponent:SetCollisionResponseToAllChannels(self.collisionResponse)
			self.particleComponent:SetRenderInMainPass(true)
			self.particleComponent.bRenderInDepthPass = true
		end
	end

	if self.particleComponent == nil then
		M.print("Failed to spawn particle component for " .. tostring(self.particleSystemAsset), LogLevel.Error)
	elseif not self.quiet then
		dumpConfigurableParams(ps, self.particleComponent, self.isNiagara)
	end
	return self.particleComponent
end

function ParticleSystem:spawnBuffer()
	if self.rootAnchor == nil or not self.running then return end
	local gen, loopStart, loopEnd, period = self.generation, self.loopStart, self.loopEnd, self.period

	local ps = resolveParticleAsset(self.particleSystemAsset)
	if isNiagaraAsset(ps) then
		if self.emitterNames == nil then
			self.emitterNames, self.emitterDefaults = listEmitterNamesFromAsset(ps, true)
		end
		syncNiagaraEmitterEnables(ps, self.emitterNames, self.emitterDefaults, self.emitterOverrides)
	end

	local inst = createLeaf({
		particleSystemAsset = self.particleSystemAsset,
		autoActivate = true,
		poolMethod = self.poolMethod,
		collisionEnabled = self.collisionEnabled,
		collisionResponse = self.collisionResponse,
		quiet = self.dumpedParams,
		emitterOverrides = self.emitterOverrides,
		restoreEmittersOnDestroy = false,
	})
	self.dumpedParams = true
	if inst == nil then return end

	if not inst.isNiagara then
		local pc = uevrUtils.getValid(inst.particleComponent)
		for name, enabled in pairs(self.emitterOverrides) do
			if pc ~= nil then
				plugin.executeFunction(pc, "SetEmitterEnable", name, enabled == true)
			end
		end
	end
	inst:attachTo(self.rootAnchor)
	setLeafVisible(inst, false)
	if self.emitterNames == nil then
		self.emitterNames = inst.emitterNames
		self.emitterDefaults = inst.emitterDefaults
	end
	table.insert(self.buffers, inst)

	setTimeout(loopStart * 1000, function()
		if self.generation == gen and self.running then
			setLeafVisible(inst, self.visible ~= false)
		end
	end)
	setTimeout(period * 1000, function()
		if self.generation == gen and self.running then
			self:spawnBuffer()
		end
	end)
	setTimeout(loopEnd * 1000, function()
		if self.generation ~= gen then return end
		setLeafVisible(inst, false)
		for i = #self.buffers, 1, -1 do
			if self.buffers[i] == inst then
				table.remove(self.buffers, i)
				break
			end
		end
		inst:destroy()
	end)
end

function ParticleSystem:start()
	if not self.looping then return end
	self:stop()
	if self.rootAnchor == nil then return end
	self.running = true
	self.generation = self.generation + 1
	self:spawnBuffer()
end

function ParticleSystem:stop()
	if not self.looping then return end
	self.running = false
	self.generation = self.generation + 1
	for i = #self.buffers, 1, -1 do
		local inst = self.buffers[i]
		self.buffers[i] = nil
		if inst ~= nil then inst:destroy() end
	end
	self.buffers = {}
end

function ParticleSystem:setLoopRange(loopStart, loopEnd)
	loopStart, loopEnd = tonumber(loopStart), tonumber(loopEnd)
	if not self.looping or loopStart == nil or loopEnd == nil or loopEnd <= loopStart then
		return false
	end
	self.loopStart, self.loopEnd, self.period = loopStart, loopEnd, loopEnd - loopStart
	if self.running then self:start() end
	return true
end

local function anchorOf(self)
	return uevrUtils.getValid(self.rootAnchor or self.anchorComponent)
end

function ParticleSystem:attachTo(mesh, socketName, attachType, weld)
	local anchor = anchorOf(self)
	local m = uevrUtils.getValid(mesh)
	if anchor ~= nil and m ~= nil then
		return anchor:K2_AttachTo(m, uevrUtils.fname_from_string(socketName or ""), attachType or 0, weld or false)
	end
end

-- Detach and keep world pose. Clears create() key so a new profile instance can be spawned.
function ParticleSystem:detach(maintainWorld)
	local anchor = anchorOf(self)
	if anchor ~= nil then
		anchor:DetachFromParent(maintainWorld ~= false, false)
	end
	clearCreatedKey(self)
end

function ParticleSystem:getParticleComponent()
	return self.particleComponent
end

function ParticleSystem:getAnchorComponent()
	return self.rootAnchor or self.anchorComponent
end

function ParticleSystem:getEmitterNames()
	if self.emitterNames ~= nil then return self.emitterNames end
	local ps = self.resolvedAsset or resolveParticleAsset(self.particleSystemAsset)
	self.emitterNames, self.emitterDefaults = listEmitterNamesFromAsset(ps, isNiagaraAsset(ps))
	return self.emitterNames
end

function ParticleSystem:isEmitterEnabled(emitterName)
	if self.emitterOverrides[emitterName] ~= nil then return self.emitterOverrides[emitterName] end
	if self.emitterDefaults and self.emitterDefaults[emitterName] ~= nil then return self.emitterDefaults[emitterName] end
	return true
end

function ParticleSystem:setEmitterEnabled(emitterName, enabled)
	self.emitterOverrides[emitterName] = enabled == true
	local names = self:getEmitterNames()
	if self.looping then
		local ps = resolveParticleAsset(self.particleSystemAsset)
		if isNiagaraAsset(ps) then
			syncNiagaraEmitterEnables(ps, names, self.emitterDefaults, self.emitterOverrides)
			for _, inst in ipairs(self.buffers) do
				if inst ~= nil then
					inst.emitterOverrides[emitterName] = enabled == true
					local pc = uevrUtils.getValid(inst.particleComponent)
					if pc ~= nil then
						plugin.executeFunction(pc, "ReinitializeSystem")
						pc.bIsActive = true
						plugin.executeFunction(pc, "Activate", true)
					end
				end
			end
		else
			for _, inst in ipairs(self.buffers) do
				if inst ~= nil then inst:setEmitterEnabled(emitterName, enabled) end
			end
		end
		return
	end

	local pc = uevrUtils.getValid(self.particleComponent)
	if self.isNiagara then
		syncNiagaraEmitterEnables(self.resolvedAsset, names, self.emitterDefaults, self.emitterOverrides)
		if pc ~= nil then
			plugin.executeFunction(pc, "ReinitializeSystem")
			pc.bIsActive = true
			plugin.executeFunction(pc, "Activate", true)
		end
	elseif pc ~= nil then
		plugin.executeFunction(pc, "SetEmitterEnable", emitterName, enabled == true)
	end
end

function ParticleSystem:destroy()
	clearCreatedKey(self)
	unregisterInstance(self)
	if self.looping then
		self:stop()
		local ps = resolveParticleAsset(self.particleSystemAsset)
		if isNiagaraAsset(ps) then
			syncNiagaraEmitterEnables(ps, self.emitterNames or listEmitterNamesFromAsset(ps, true), self.emitterDefaults, nil)
		end
		local root = uevrUtils.getValid(self.rootAnchor)
		if root ~= nil then
			root:DetachFromParent(false, false)
			uevrUtils.destroyComponent(self.rootAnchor, true, true)
		end
		self.rootAnchor = nil
		return
	end

	if self.isNiagara and self.resolvedAsset ~= nil and self.restoreEmittersOnDestroy ~= false then
		syncNiagaraEmitterEnables(self.resolvedAsset, self.emitterNames or self:getEmitterNames(), self.emitterDefaults, nil)
	end
	local pc = uevrUtils.getValid(self.particleComponent)
	if pc ~= nil then
		if pc.SetAutoActivate ~= nil then pc:SetAutoActivate(false) end
		if self.isNiagara then
			pc.bIsActive = false
			plugin.executeFunction(pc, "Deactivate")
		elseif pc.Deactivate ~= nil then
			pc:Deactivate()
		end
		pc:SetVisibility(false, false)
		uevrUtils.destroyComponent(self.particleComponent, true, true)
	end
	self.particleComponent = nil
	local ac = uevrUtils.getValid(self.anchorComponent)
	if ac ~= nil then
		ac:DetachFromParent(false, false)
		uevrUtils.destroyComponent(self.anchorComponent, true, true)
	end
	self.anchorComponent = nil
end

function ParticleSystem:setWorldLocation(location, sweep)
	local anchor = anchorOf(self)
	if anchor ~= nil and location ~= nil then
		anchor:K2_SetWorldLocation(uevrUtils.vector(location), sweep or false, reusable_hit_result, false)
	end
end

function ParticleSystem:setWorldRotation(rotation, sweep)
	local anchor = anchorOf(self)
	if anchor ~= nil and rotation ~= nil then
		anchor:K2_SetWorldRotation(uevrUtils.rotator(rotation), sweep or false, reusable_hit_result, false)
	end
end

function ParticleSystem:setWorldTransform(location, rotation, scale)
	local anchor = anchorOf(self)
	if anchor ~= nil then
		uevrUtils.set_component_world_transform(
			anchor,
			location and uevrUtils.vector(location),
			rotation and uevrUtils.rotator(rotation),
			scale and uevrUtils.vector(scale))
	end
end

function ParticleSystem:setRelativeLocation(location)
	local anchor = anchorOf(self)
	if anchor ~= nil and location ~= nil then
		anchor.RelativeLocation = uevrUtils.vector(location)
	end
end

function ParticleSystem:setRelativeRotation(rotation)
	local anchor = anchorOf(self)
	if anchor ~= nil and rotation ~= nil then
		anchor.RelativeRotation = uevrUtils.rotator(rotation)
	end
end

function ParticleSystem:setRelativeScale(scale)
	local anchor = anchorOf(self)
	if anchor ~= nil and scale ~= nil then
		anchor.RelativeScale3D = uevrUtils.vector(scale)
	end
end

function ParticleSystem:setScale(scale)
	self.scale = scale or {1, 1, 1}
	self:setRelativeScale(self.scale)
end

function ParticleSystem:setVisibility(isVisible, propagateToChildren)
	local visible = isVisible == true
	self.visible = visible
	local propagate = propagateToChildren ~= false
	if self.looping then
		local root = uevrUtils.getValid(self.rootAnchor)
		if root ~= nil then
			root:SetVisibility(visible, propagate)
			if root.SetHiddenInGame ~= nil then
				root:SetHiddenInGame(not visible, propagate)
			end
		end
		for _, inst in ipairs(self.buffers or {}) do
			setLeafVisible(inst, visible)
		end
		return
	end
	local anchor = uevrUtils.getValid(self.anchorComponent)
	if anchor ~= nil then
		anchor:SetVisibility(visible, propagate)
		if anchor.SetHiddenInGame ~= nil then
			anchor:SetHiddenInGame(not visible, propagate)
		end
	end
	setLeafVisible(self, visible)
end

function ParticleSystem:isValid()
	if self.looping then
		return uevrUtils.getValid(self.rootAnchor) ~= nil
	end
	return uevrUtils.getValid(self.particleComponent) ~= nil and uevrUtils.getValid(self.anchorComponent) ~= nil
end

uevrUtils.registerPreLevelChangeCallback(function()
	M.destroyAll()
end)

uevr.params.sdk.callbacks.on_script_reset(function()
	M.destroyAll()
end)

return M
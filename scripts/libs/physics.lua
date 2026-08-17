local uevrUtils = require("libs/uevr_utils")
local paramModule = require("libs/core/params")
local controllers = require("libs/controllers")

local M = {}

local status = {}

-- local parametersFileName = "physics_parameters"
-- local parameters = {
-- }
-- local paramManager = paramModule.new(parametersFileName, parameters, true)
-- paramManager:load(true)

local function createPhysicsHandle(id, parent, tranformCallback, options)
    if options == nil then options = {} end
    M.destroyPhysicsHandle(id)
--    local profileData = paramManager:get(id)
--    if profileData ~= nil then
        print("Creating physics handle for ", id)
        local physicsHandle = nil
        physicsHandle = uevrUtils.create_component_of_class("Class /Script/Engine.PhysicsHandleComponent", false, nil, false, parent)
        if physicsHandle ~= nil then
            if options.interpolationSpeed ~= nil then physicsHandle:SetInterpolationSpeed(options.interpolationSpeed) end
            if options.linearStiffness ~= nil then physicsHandle:SetLinearStiffness(options.linearStiffness) end
            if options.linearDamping ~= nil then physicsHandle:SetLinearDamping(options.linearDamping) end
            if options.angularStiffness ~= nil then physicsHandle:SetAngularStiffness(options.angularStiffness) end
            if options.angularDamping ~= nil then physicsHandle:SetAngularDamping(options.angularDamping) end

            if status.physicsHandles == nil then status.physicsHandles = {} end
            status.physicsHandles[id] = {physicsHandle = physicsHandle, canDestoryParent = parent == nil, tranformCallback = tranformCallback}
        end
--    end
end
function M.createPhysicsHandle(id, parent)
    if status.physicsHandles == nil then status.physicsHandles = {} end
    if status.physicsHandles[id] == nil then
        createPhysicsHandle(id, parent)
    end
end

function M.destroyPhysicsHandle(id)
    if status.physicsHandles == nil or status.physicsHandles[id] == nil then return end
	local physicsHandle = uevrUtils.getValid(status.physicsHandles[id]["physicsHandle"])
	if physicsHandle ~= nil then
        M.releaseComponentWithPhysicsHandle(id)
		uevrUtils.destroyComponent(physicsHandle, status.physicsHandles[id].canDestoryParent, false)
	end
	status.physicsHandles[id] = nil
end

function M.destroyAllPhysicsHandles()
    if status.physicsHandles == nil then return end
    for id, data in pairs(status.physicsHandles) do
        M.destroyPhysicsHandle(id)
    end
    status.physicsHandles = nil
end

function M.destroyAll()
    M.destroyAllPhysicsHandles()
end

function M.grabComponentWithPhysicsHandle(id, component)
    if component == nil or status.physicsHandles == nil or status.physicsHandles[id] == nil then return end
    local physicsHandle = uevrUtils.getValid(status.physicsHandles[id]["physicsHandle"])
    if physicsHandle ~= nil then
        --if you use this then the grip location will be whereever the controller is at the moment of grip
        --good if you want the object to orient to the current hand pose but suffers
        --from the fact that your hand could initially be in the center of the object (not realistic)
            --local location = controllers.getControllerLocation(Handed.Right)
            --local rotation = controllers.getControllerRotation(Handed.Right)
        --if you use this one the grip location will be the center of the gripped component
        --good if you use fixed offsets that will give a consistent hold orientation every time
        local location = uevrUtils.getComponentLocation(component)
        local rotation = uevrUtils.getComponentRotation(component)

---@diagnostic disable-next-line: need-check-nil
        print("Grabbing component ", component:get_full_name(), "with physics handle ", physicsHandle:get_full_name(), "at location ", location.X, location.Y, location.Z, "and rotation ", rotation.Pitch, rotation.Yaw, rotation.Roll)
        physicsHandle:GrabComponentAtLocationWithRotation(component, uevrUtils.fname_from_string(""), location, rotation)
        --physicsHandle:GrabComponent(component, uevrUtils.fname_from_string("None"), location, true)
    end
end

function M.getGrabbedComponentWithPhysicsHandle(id)
    if status.physicsHandles == nil or status.physicsHandles[id] == nil then return end
    local physicsHandle = uevrUtils.getValid(status.physicsHandles[id]["physicsHandle"])
    if physicsHandle ~= nil then
        return physicsHandle:GetGrabbedComponent()
    end
    return nil
end

function M.releaseComponentWithPhysicsHandle(id)
    if status.physicsHandles == nil or status.physicsHandles[id] == nil then return end
    local physicsHandle = uevrUtils.getValid(status.physicsHandles[id]["physicsHandle"])
    if physicsHandle ~= nil then
        physicsHandle:ReleaseComponent()
    end
end

local function update()
    if status.physicsHandles ~= nil then
        for id, data in pairs(status.physicsHandles) do
            local physicsHandle = uevrUtils.getValid(data["physicsHandle"])
            if physicsHandle ~= nil then
                local grabbed = uevrUtils.getValid(physicsHandle.GetGrabbedComponent and physicsHandle:GetGrabbedComponent())
                if grabbed ~= nil then
                    local location, rotation = nil, nil
                    if data.tranformCallback ~= nil then
                        location, rotation = data.tranformCallback(id, grabbed)
                    else -- default to controller location and rotation
                        location = controllers.getControllerLocation(Handed.Right)
                        rotation = controllers.getControllerRotation(Handed.Right)
                    end
                    if location ~= nil and rotation ~= nil then
                        physicsHandle:SetTargetLocationAndRotation(location, rotation)
                    end
                end
            end
        end
    end
end

local noneBone = nil

-- Samples HMD-relative hand motion for aim and throw effort.
-- targetRangeMeters is max range at fullSpeed. Effort scales 0..1 from dropSpeed
-- to fullSpeed. Faster than maxSpeed is a hitch and is not stored.
function M.createThrowSampler(options)
    if options == nil then options = {} end
    local historySize = options.historySize or 24
    local maxSpeed = options.maxSpeed or 1200
    local fullSpeed = options.fullSpeed or maxSpeed
    local history = {}
    for i = 1, historySize do
        history[i] = { X = 0, Y = 0, Z = 0, S = 0 }
    end
    return {
        history = history,
        historySize = historySize,
        releaseSamples = options.releaseSamples or 4,
        minMoveSq = options.minMoveSq or 1,
        maxSpeed = maxSpeed,
        maxSpeedSq = maxSpeed * maxSpeed,
        fullSpeed = fullSpeed,
        dropSpeed = options.dropSpeed or 200,
        dropSpeedSq = (options.dropSpeed or 200) * (options.dropSpeed or 200),
        dropIdle = options.dropIdle or 0.12,
        assumedReleaseHeight = options.assumedReleaseHeight or 150.0,
        worldGravity = options.worldGravity or 980.0,
        primed = false,
        lastRel = { X = 0, Y = 0, Z = 0 },
        lastHmdLoc = { X = 0, Y = 0, Z = 0 },
        lastHandLoc = { X = 0, Y = 0, Z = 0 },
        hmdVel = { X = 0, Y = 0, Z = 0 },
        count = 0,
        write = 0,
        idleDelta = 0,
        lastRawSpeed = 0,
        peakRawSpeed = 0,
    }
end

function M.resetThrowSampler(sampler)
    if sampler == nil then return end
    sampler.primed = false
    sampler.hmdVel.X = 0
    sampler.hmdVel.Y = 0
    sampler.hmdVel.Z = 0
    sampler.count = 0
    sampler.write = 0
    sampler.idleDelta = 0
    sampler.lastRawSpeed = 0
    sampler.peakRawSpeed = 0
end

-- Differentiate hand-minus-HMD so locomotion does not look like a swing.
function M.updateThrowSampler(sampler, handLoc, hmdLoc, delta)
    if sampler == nil or handLoc == nil or delta == nil or delta <= 0 then return end

    local hx = handLoc.X
    local hy = handLoc.Y
    local hz = handLoc.Z
    local mx, my, mz = hx, hy, hz
    if hmdLoc ~= nil then
        mx = mx - hmdLoc.X
        my = my - hmdLoc.Y
        mz = mz - hmdLoc.Z
    end

    if sampler.primed ~= true then
        sampler.lastRel.X = mx
        sampler.lastRel.Y = my
        sampler.lastRel.Z = mz
        sampler.lastHandLoc.X = hx
        sampler.lastHandLoc.Y = hy
        sampler.lastHandLoc.Z = hz
        if hmdLoc ~= nil then
            sampler.lastHmdLoc.X = hmdLoc.X
            sampler.lastHmdLoc.Y = hmdLoc.Y
            sampler.lastHmdLoc.Z = hmdLoc.Z
        end
        sampler.primed = true
        sampler.idleDelta = 0
        return
    end

    sampler.idleDelta = sampler.idleDelta + delta
    local dx = mx - sampler.lastRel.X
    local dy = my - sampler.lastRel.Y
    local dz = mz - sampler.lastRel.Z
    if dx * dx + dy * dy + dz * dz < sampler.minMoveSq then
        if sampler.idleDelta > sampler.dropIdle then
            sampler.count = 0
            sampler.write = 0
        end
        return
    end

    local dt = sampler.idleDelta
    sampler.idleDelta = 0
    local vx = dx / dt
    local vy = dy / dt
    local vz = dz / dt
    local speedSq = vx * vx + vy * vy + vz * vz
    local rawSpeed = math.sqrt(speedSq)
    sampler.lastRawSpeed = rawSpeed
    if rawSpeed > sampler.peakRawSpeed then
        sampler.peakRawSpeed = rawSpeed
    end
    if speedSq <= sampler.maxSpeedSq then
        local i = sampler.write + 1
        if i > sampler.historySize then
            i = 1
        end
        sampler.write = i
        if sampler.count < sampler.historySize then
            sampler.count = sampler.count + 1
        end
        local sample = sampler.history[i]
        sample.X = vx
        sample.Y = vy
        sample.Z = vz
        sample.S = speedSq
    end

    sampler.lastRel.X = mx
    sampler.lastRel.Y = my
    sampler.lastRel.Z = mz
    sampler.lastHandLoc.X = hx
    sampler.lastHandLoc.Y = hy
    sampler.lastHandLoc.Z = hz
    if hmdLoc ~= nil then
        sampler.hmdVel.X = (hmdLoc.X - sampler.lastHmdLoc.X) / dt
        sampler.hmdVel.Y = (hmdLoc.Y - sampler.lastHmdLoc.Y) / dt
        sampler.hmdVel.Z = (hmdLoc.Z - sampler.lastHmdLoc.Z) / dt
        sampler.lastHmdLoc.X = hmdLoc.X
        sampler.lastHmdLoc.Y = hmdLoc.Y
        sampler.lastHmdLoc.Z = hmdLoc.Z
    end
end

-- targetRangeMeters is max horizontal travel (meters) at fullSpeed.
-- Wrist speed between dropSpeed and fullSpeed scales that range (0..1).
-- Direction from recent samples; launch speed is ballistic for scaled range.
function M.getThrowVelocity(sampler, targetRangeMeters)
    if sampler == nil then return nil end
    sampler.debugRecentPeak = 0
    sampler.debugEffort = 0
    local history = sampler.history
    local count = sampler.count
    local write = sampler.write
    local historySize = sampler.historySize
    if count <= 0 then
        return nil
    end

    local peakS = 0
    for i = 1, count do
        local s = history[i].S
        if s > peakS then
            peakS = s
        end
    end
    if peakS <= 0 then
        return nil
    end

    local dx, dy, dz, dsum = 0, 0, 0, 0
    local recentPeakS = 0
    local recent = count
    if recent > sampler.releaseSamples then
        recent = sampler.releaseSamples
    end
    for k = 0, recent - 1 do
        local i = write - k
        if count < historySize then
            if i < 1 then
                break
            end
        elseif i < 1 then
            i = i + historySize
        end
        local sample = history[i]
        local w = sample.S
        if w > recentPeakS then
            recentPeakS = w
        end
        if w > 0 then
            dx = dx + sample.X * w
            dy = dy + sample.Y * w
            dz = dz + sample.Z * w
            dsum = dsum + w
        end
    end
    sampler.debugRecentPeak = math.sqrt(recentPeakS)
    if dsum <= 0 or recentPeakS < sampler.dropSpeedSq then
        return nil
    end
    local dirSpeed = math.sqrt(dx * dx + dy * dy + dz * dz)
    if dirSpeed <= 0 then
        return nil
    end
    local ux = dx / dirSpeed
    local uy = dy / dirSpeed
    local uz = dz / dirSpeed
    local horizontal = math.sqrt(ux * ux + uy * uy)
    if horizontal <= 0.0001 then
        return nil
    end

    local drop = sampler.dropSpeed
    local full = sampler.fullSpeed
    local effort = 1
    if full > drop then
        effort = (sampler.debugRecentPeak - drop) / (full - drop)
        if effort < 0 then
            effort = 0
        elseif effort > 1 then
            effort = 1
        end
    end
    sampler.debugEffort = effort
    if effort <= 0 then
        return nil
    end

    -- Unreal units (cm). Solve launch speed so this (effort-scaled) range lands under gravity.
    local range = (targetRangeMeters or 0) * 100.0 * effort
    local verticalRoom = sampler.assumedReleaseHeight + uz * range / horizontal
    local mag
    if verticalRoom > 1.0 then
        mag = math.sqrt(0.5 * sampler.worldGravity * range * range / (horizontal * horizontal * verticalRoom))
    else
        mag = math.sqrt(sampler.worldGravity * range)
    end
    return { X = ux * mag, Y = uy * mag, Z = uz * mag }
end

-- Throw: effort-scaled ballistic velocity plus HMD world carry.
-- Drop (below dropSpeed): HMD carry only, so a still hand while running does not launch.
function M.getReleaseVelocity(sampler, targetRangeMeters)
    local velocity = M.getThrowVelocity(sampler, targetRangeMeters)
    if sampler ~= nil then
        print(string.format(
            "[throw] wristPeak=%.1f  recentPeak=%.1f  last=%.1f  drop=%.0f  fullSpeed=%.0f  hitch=%.0f  effort=%.2f  %s",
            sampler.peakRawSpeed or 0,
            sampler.debugRecentPeak or 0,
            sampler.lastRawSpeed or 0,
            sampler.dropSpeed or 0,
            sampler.fullSpeed or 0,
            sampler.maxSpeed or 0,
            sampler.debugEffort or 0,
            velocity == nil and "drop" or "throw"
        ))
    end
    local hv = sampler and sampler.hmdVel
    if velocity == nil then
        if hv ~= nil then
            return { X = hv.X, Y = hv.Y, Z = hv.Z }
        end
        return nil
    end
    if hv ~= nil then
        velocity.X = velocity.X + hv.X
        velocity.Y = velocity.Y + hv.Y
        velocity.Z = velocity.Z + hv.Z
    end
    return velocity
end

function M.applyThrowVelocity(mesh, velocity)
    if uevrUtils.getValid(mesh) == nil then
        return
    end
    if noneBone == nil then
        noneBone = uevrUtils.fname_from_string("None")
    end
    pcall(function()
        mesh:SetSimulatePhysics(true)
        mesh:SetEnableGravity(true)
        mesh:WakeRigidBody(noneBone)
        if velocity ~= nil then
            mesh:SetPhysicsLinearVelocity(uevrUtils.vector(velocity.X, velocity.Y, velocity.Z), false, noneBone)
        else
            mesh:SetPhysicsLinearVelocity(uevrUtils.vector(0, 0, 0), false, noneBone)
        end
    end)
end

-- This should normally be enough but games using their own physics
-- may have additional requirements
function M.makeComponentPhysicsGrippable(grippedComponent)
    -- grippedComponent:SetCollisionResponseToChannel(2, 0)
    -- --component:GetOwner().bActorEnableCollision = false
    -- status.grabComponent = grippedComponent
    grippedComponent.BodyInstance.bSimulatePhysics = true
    grippedComponent.BodyInstance.bEnableGravity = true
    grippedComponent.BodyInstance.bOverrideMass = true
    grippedComponent:SetEnableGravity(true)
    --grippedComponent.BodyInstance.bUpdateKinematicFromSimulation = true
    grippedComponent:SetCollisionEnabled(ECollisionEnabled.QueryAndPhysics)
    grippedComponent:SetCollisionObjectType(ECollisionChannel.ECC_PhysicsBody)    -- or WorldDynamic
    --grippedComponent:SetMassOverrideInKg(100)
    grippedComponent:WakeAllRigidBodies()
    grippedComponent:SetMobility(EComponentMobility.Movable)
    grippedComponent:SetSimulatePhysics(true)
    grippedComponent:SetCollisionResponseToChannel(ECollisionChannel.ECC_Pawn, ECollisionResponse.Ignore)

end

function M.reset()
    M.destroyAll()
    status = {}
end

uevr.sdk.callbacks.on_pre_engine_tick(function(engine, delta)
    update()
end)

uevrUtils.registerPreLevelChangeCallback(function(level)
	M.reset()
end)

uevr.params.sdk.callbacks.on_script_reset(function()
	M.reset()
end)

return M
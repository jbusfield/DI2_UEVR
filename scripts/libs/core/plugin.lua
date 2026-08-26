-- Contributers: ideas and inspiration for this module courtesy of gwizdek
--[[
    This module allows you call any function in the game's SDK without limitations such
    as the TArray issue that may exist in native lua calls. Notice that this module itself
    does not require the rest of uevrUtils in order to be used in your project. 
    The executeFunction function takes any valid uevr/unreal objects and structures with or without uevrUtils.
    In addition to the getFunction call you can also get any property of an object using
    the getProperty function, or set a property with setProperty. 

    executeFunction can be called Asynchronously or Synchronously

    Examples:
        local plugin = require("libs/core/plugin")

        plugin.showDebug = true
        local location = component:K2_GetComponentLocation()
        local radius = 20
        local objectTypes = {0,5,14,19}
        local classFilter = uevrUtils.get_class("Class /Script/Engine.PrimitiveComponent")
        local ignoreActors = {pawn}
        local foundComponents = {}
    
        -- ############# Synchronous call ##############
        --   This is what the API version looks like in KismetSystemLibrary
        --     static bool SphereOverlapComponents(const class UObject* WorldContextObject, const struct FVector& SpherePos, float SphereRadius, const TArray<EObjectTypeQuery>& ObjectTypes, class UClass* ComponentClassFilter, const TArray<class AActor*>& ActorsToIgnore, TArray<class UPrimitiveComponent*>* OutComponents);
        --
        --   This is the equivalent call using the plugin. Notice result.OutComponents uses the exact name that the API returns. 
        --   If the function returns a value then result.ReturnValue will be set to the returned value.
        -- ##############################################
        local result = plugin.executeFunction(kismet_system_library, "SphereOverlapComponents", uevrUtils.get_world(), location, radius, objectTypes, classFilter, ignoreActors, foundComponents)
        if result ~= nil then
            if result.ReturnValue == true then
                local components = result.OutComponents or {}
                for i = 1, #components do
                    local comp = components[i]
                    print("Component:", comp:get_full_name())
                end
            end
        end

        -- ############# Asynchronous call ##############
        --   This is what the API version looks like in KismetSystemLibrary
        --     static bool SphereOverlapComponents(const class UObject* WorldContextObject, const struct FVector& SpherePos, float SphereRadius, const TArray<EObjectTypeQuery>& ObjectTypes, class UClass* ComponentClassFilter, const TArray<class AActor*>& ActorsToIgnore, TArray<class UPrimitiveComponent*>* OutComponents);
        --
        --   This is the equivalent asynchronous call using the plugin
        -- ##############################################
        local resultCallback = plugin.executeFunctionAsync(kismet_system_library, "SphereOverlapComponents", uevrUtils.get_world(), location, radius, objectTypes, classFilter, ignoreActors, foundComponents)
        resultCallback(function(result)
            local components = result.OutComponents or {}
            for i = 1, #components do
                local comp = components[i]
                print("Component:", comp:get_full_name())
            end
        end)

        -- ############# GetProperty example ##############
        --   This is what the API version of ActionMappings looks like
        --      TArray<struct FInputActionKeyMapping>         ActionMappings;                                    // 0x0090(0x0010)(Edit, ZeroConstructor, Config, NativeAccessSpecifierPrivate)
	    -- ##############################################
        local inputSettings = uevrUtils.find_default_instance("Class /Script/Engine.InputSettings")
        local result = plugin.getProperty(inputSettings, "ActionMappings")
        for i, mappingData in ipairs(result) do
            local gameKey = mappingData["Key"]["KeyName"]
            print("Mapping found for key:", mappingData["ActionName"], gameKey)
        end

        -- ############# SetProperty example ##############
        --   Set a field, map entry, or array element. Same indexed syntax as getProperty.
        --   Returns nothing; failures are printed to the log.
        -- ##############################################

        -- SDK Definition for TMap example:
        --class UIndianaUIControllerIconsData final : public UDataAsset
        --{
        --public:
        --    TMap<class FName, class UTexture2D*>          Icons;                                             // 0x00D8(0x0050)(Protected, NativeAccessSpecifierProtected)
        --}
        -- Lua implementation
	    local XBOX_ICONS_DATA = "IndianaUIControllerIconsData /Game/UI/XboxOneControllerIcons.XboxOneControllerIcons"
	    local iconsData = uevrUtils.find_required_object(XBOX_ICONS_DATA)
        local XBOX_RB_TEXTURE = "Texture2D /Game/UI/Art/FrontEnd/General/Navigation/Xbox/T_Button_Xbox_RB.T_Button_Xbox_RB"
	    local rbTexture = uevrUtils.find_required_object(XBOX_RB_TEXTURE)
        plugin.setProperty(iconsData, "Icons[Gamepad_FaceButton_Left]", rbTexture)
        
        plugin.setProperty(someActor, "ChildArray[2]", newElement)
        
        plugin.setProperty(someObject, "Opacity", 1.5)


]]--
local M = {}

M.showDebug = false

local pendingExecuteFunctionCallbacks = {}

local function guid()
    local template = 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'
    return string.gsub(template, '[xy]', function (c)
        local v = (c == 'x') and math.random(0, 0xf) or math.random(8, 0xb)
        return string.format('%x', v)
    end)
end

local function convertInputStruct(arg)
    local out = {}
	if arg.get_struct ~= nil then
		local childProperty = arg:get_struct():get_child_properties()
		if childProperty == nil then
			--ValueStr = string.format("%s %s %s\n\t%s", UEVR_UStruct.static_class(Value):get_full_name(), Value, Value:get_struct(), "<Empty>")
			print("!!!Empty structure childProperty found", arg)
            ---@diagnostic disable-next-line: cast-local-type
            out = string.format("%s", "")
		else
			while childProperty ~= nil do
                local propName = childProperty:get_fname():to_string()
                if M.showDebug then print(propName,childProperty:get_class():get_name()) end
                if childProperty:get_class():get_name() == "ArrayProperty" then
                    out[propName] = M.convertInputParams(arg[propName])
                elseif childProperty:get_class():get_name() == "StructProperty" then
                    out[propName] = convertInputStruct(arg[propName])
                else
                    out[propName] = arg[propName]
                end
				childProperty = childProperty:get_next()
			end
		end
	elseif string.match(string.format("%s",arg), "sol.glm::vec<3,float,0>*" ) then
		out = {X=arg.X, Y=arg.Y, Z=arg.Z }
	elseif string.match(string.format("%s",arg), "sol.glm::vec<3,double,0>*" ) then
		out = {X=arg.X, Y=arg.Y, Z=arg.Z }
	else
		print("!!!Unknown Struct type found!!!",UEVR_UStruct.static_class(arg):get_full_name(), arg)
		print(type(arg),arg:get_field_name())
	end
    return out
end

-- Walk all keys (array slots and named struct fields) and convert UObjects to addresses.
-- ipairs would skip { NotifyStateClass = obj, Duration = 0.1 } because those are not t[1], t[2], ...
local function convertInputParams(argsArray)
	for i, arg in pairs(argsArray) do
		if M.showDebug then print("Argument is type", type(arg)) end
		if type(arg) == "userdata" then
            if arg.get_struct ~= nil then
	            if M.showDebug then print("this object is a struct") end
                argsArray[i] = convertInputStruct(arg)
	        elseif arg.get_address then --its an object whose address can be retrieved
			    argsArray[i] = arg:get_address()
            elseif string.match(string.format("%s",arg), "sol.glm::vec<3,float,0>*" ) then
                argsArray[i] = {X=arg.X, Y=arg.Y, Z=arg.Z }
            elseif string.match(string.format("%s",arg), "sol.glm::vec<3,double,0>*" ) then
                argsArray[i] = {X=arg.X, Y=arg.Y, Z=arg.Z }
            end

		end
		if type(arg) == "table" then
			convertInputParams(arg)
		end
	end
end
function M.convertInputParams(argsArray)
    convertInputParams(argsArray)
end

local function convertResultDataType(dataType, dataValue)
    if dataType == "ObjectProperty" then
        return uevr.api:to_uobject(dataValue)

    -- FIX: Intercept StructProperties and force the recursion to process its inner fields
    elseif dataType == "StructProperty" then
        if type(dataValue) == "table" then
            return M.convertResultData(dataValue)
        else
            return dataValue
        end

    -- Handle arrays of property blocks (ArrayProperty)
    elseif dataType == "ArrayProperty" then
        if type(dataValue) == "table" then
            local arr = {}
            for i, v in ipairs(dataValue) do
                arr[i] = M.convertResultData(v)
            end
            return arr
        else
            return dataValue
        end

    -- MapProperty arrives as an array of {key, value} property blocks; build a Lua map
    elseif dataType == "MapProperty" then
        if type(dataValue) == "table" then
            local map = {}
            for _, entry in ipairs(dataValue) do
                if type(entry) == "table" and entry.key ~= nil and entry.value ~= nil then
                    local mapKey = M.convertResultData(entry.key)
                    if mapKey ~= nil then
                        map[mapKey] = M.convertResultData(entry.value)
                    end
                end
            end
            return map
        else
            return dataValue
        end

    else
        return dataValue
    end
end


-- Helper function to check if a table represents a {"type": ..., "value": ...} property block
local function isPropertyBlock(t)
    return type(t) == "table" and t.type ~= nil and t.value ~= nil
end

function M.convertResultData(inData)
    -- Base case: if it's a property block, unpack it immediately
    if isPropertyBlock(inData) then
        return convertResultDataType(inData.type, inData.value)
    end

    -- If it's a regular table (either an array or an object map), process its children
    if type(inData) == "table" then
        local outData = {}
        for key, data in pairs(inData) do
            outData[key] = M.convertResultData(data)
        end
        return outData
    end

    -- Fallback for raw primitive data types
    return inData
end

local function printTableStructure(tbl, indent)
    indent = indent or ""

    if tbl == nil then return end

    -- Top-level scalar / UObject results (e.g. Map element via Icons[Key]) are not tables
    if type(tbl) ~= "table" then
        if type(tbl) == "userdata" then
            print(string.format("%s%s (Userdata/UObject Instance)", indent, tostring(tbl)))
        else
            print(string.format("%s%s (%s)", indent, tostring(tbl), type(tbl)))
        end
        return
    end

    for key, val in pairs(tbl) do
        local valType = type(val)

        if valType == "table" then
            -- Check if it's an array-like table or a standard dictionary
            if #val > 0 then
                print(string.format("%s[\"%s\"] = Array (Size: %d):", indent, tostring(key), #val))
            else
                print(string.format("%s[\"%s\"] = Dictionary/Table:", indent, tostring(key)))
            end
            -- Recursively print inner elements
            printTableStructure(val, indent .. "    ")

        elseif valType == "userdata" then
            -- This validates that uevr.api:to_uobject() successfully converted the value
            print(string.format("%s[\"%s\"] = %s (Userdata/UObject Instance)", indent, tostring(key), tostring(val)))

        else
            -- Print primitive types like booleans, strings, or numbers
            print(string.format("%s[\"%s\"] = %s (%s)", indent, tostring(key), tostring(val), valType))
        end
    end
end

local AsyncRegistry = {}

function M.executeFunctionAsync(callerObject, functionName, ...)
    if callerObject == nil then
        print("[plugin]Error: executeFunctionAsync callerObject is nil")
        return nil
    end

    local argsArray = {...}
	convertInputParams(argsArray)
	local data =
	{
		debug = M.showDebug,
		caller_object = callerObject:get_address(),
		function_name = functionName,
		params = argsArray
	}
    if M.showDebug then print("ExecuteFunction dispatching for function:\n", functionName, json.dump_string(data)) end
	local callID = "ExecuteFunction_" .. guid()

    -- Initialize the task state inside our registry under its unique ID
    AsyncRegistry[callID] = {
        completed = false,
        finalResult = nil,
        registeredCallback = nil
    }
    if M.showDebug then print("AsyncRegistry entry created", callID) end

	uevr.api:dispatch_custom_event(callID, json.dump_string(data))

    -- 2. Return the tracking function
    return function(userCallback)
        local task = AsyncRegistry[callID]

        -- Safety check in case the task was deleted before this was called
        if not task then
            print("Warning: Task " .. callID .. " no longer exists.")
            return
        end

        if task.completed then
            -- If finished early, run it and immediately clean up
            userCallback(task.finalResult)
            AsyncRegistry[callID] = nil
        else
            -- Otherwise, store the callback to be executed later
            task.registeredCallback = userCallback
        end
    end
end

function M.executeFunction(callerObject, functionName, ...)
    if callerObject == nil then
        print("[plugin]Error: executeFunction callerObject is nil")
        return nil
    end

    local argsArray = {...}
	convertInputParams(argsArray)

	local data =
	{
		debug = M.showDebug,
		caller_object = callerObject:get_address(),
		function_name = functionName,
		params = argsArray
	}
    if M.showDebug then print("\n############################\nExecuteFunction dispatching for function:\n", functionName, json.dump_string(data)) end
	local callID = "ExecuteFunction_" .. guid()

    -- Initialize the task state inside our registry under its unique ID
    AsyncRegistry[callID] = {
        completed = false,
        finalResult = nil,
        registeredCallback = nil,
        delayedCleanup = false
    }
    if M.showDebug then print("AsyncRegistry entry created", callID) end

	uevr.api:dispatch_custom_event(callID, json.dump_string(data))

    local result = AsyncRegistry[callID].finalResult
    AsyncRegistry[callID] = nil
    return result
end

function M.getProperty(callerObject, propertyName)
    if callerObject == nil then
        print("[plugin]Error: getProperty callerObject is nil")
        return nil
    end

	local data =
	{
		debug = M.showDebug,
		caller_object = callerObject:get_address(),
		param_name = propertyName,
	}
    if M.showDebug then print("\n#############################\nGetProperty dispatching for property:\n", propertyName) end
	local callID = "GetProperty_" .. guid()

        -- Initialize the task state inside our registry under its unique ID
    AsyncRegistry[callID] = {
        completed = false,
        finalResult = nil,
        registeredCallback = nil,
        delayedCleanup = false
    }
    if M.showDebug then print("AsyncRegistry entry created", callID) end

	uevr.api:dispatch_custom_event(callID, json.dump_string(data))

    local result = AsyncRegistry[callID].finalResult
    AsyncRegistry[callID] = nil
    return result
end

-- Sets a property (or map/array element via param_name indexing). Returns nothing.
-- Failures are printed from on_lua_event when the response contains an error field.
function M.setProperty(callerObject, propertyName, value)
    if callerObject == nil then
        print("[plugin]Error: setProperty callerObject is nil")
        return nil
    end
    
    local valueParams = {value}
    convertInputParams(valueParams)

	local data =
	{
		debug = M.showDebug,
		caller_object = callerObject:get_address(),
		param_name = propertyName,
		value = valueParams[1],
	}
    if M.showDebug then print("\n############################\nSetProperty dispatching for property:\n", propertyName, json.dump_string(data)) end
	local callID = "SetProperty_" .. guid()

    AsyncRegistry[callID] = {
        completed = false,
        finalResult = nil,
        registeredCallback = nil,
        delayedCleanup = false
    }
    if M.showDebug then print("AsyncRegistry entry created", callID) end

	uevr.api:dispatch_custom_event(callID, json.dump_string(data))

    -- Void: errors already printed in on_lua_event; success has no caller payload
    AsyncRegistry[callID] = nil
end

function M.addComponent(actorObject, componentClass)
    if actorObject == nil or componentClass == nil then
        print("[plugin]Error: addComponent requires actor and component class")
        return nil
    end

    local data = {
        debug = M.showDebug,
        actor = actorObject:get_address(),
        component_class = componentClass:get_address(),
    }
    local callID = "AddComponent_" .. guid()
    AsyncRegistry[callID] = {
        completed = false,
        finalResult = nil,
        registeredCallback = nil,
        delayedCleanup = false
    }

    uevr.api:dispatch_custom_event(callID, json.dump_string(data))

    local result = AsyncRegistry[callID].finalResult
    AsyncRegistry[callID] = nil
    if type(result) == "table" then
        return result.component
    end
    return nil
end

uevr.sdk.callbacks.on_lua_event(function(eventName, eventData)
    if M.showDebug then print("on_lua_event", eventName, eventData) end
    local id = eventName
    local task = AsyncRegistry[id]

    -- Safety check: Ensure the task wasn't cancelled/deleted prematurely
    if not task then return end

    if M.showDebug then print("--------- on_lua_event raw return value -------------:\n", eventData) end

    local parsed = json.load_string(eventData)
    local result = nil
    if type(parsed) == "table" and parsed.error ~= nil then
        print("[plugin] error (" .. tostring(id) .. "):", parsed.error, "Enable debug for more information")
    elseif type(parsed) == "table" and parsed.success == true then
        if M.showDebug then
            print("--------- on_lua_event success -------------")
        end
    else
        result = M.convertResultData(parsed)
        if M.showDebug then
            print("--------- on_lua_event Converted structure -------------")
            printTableStructure(result)
        end
    end

    task.completed = true
    task.finalResult = result

    -- If the user already attached their callback, fire it now
    if task.registeredCallback then
        task.registeredCallback(result)
        --Free the memory immediately after execution
        AsyncRegistry[id] = nil
    elseif task.delayedCleanup ~= false then
        -- If the user did not attach their callback in an async call, free the memory after 2 seconds
        -- The delay function is implemented in uevr_utils.lua. If you dont want to use
        -- uevr_utils.lua then make sure you always use the return callback from the 
        -- ExecuteFunctionAsync call or else memory will leak
        if delay ~= nil then
            delay(2000, function()
                AsyncRegistry[id] = nil
            end)
        end
    end
end)

return M
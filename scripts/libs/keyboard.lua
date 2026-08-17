--[[==========================================================================[
--==========================================================================]
                         EXAMPLES 
--==========================================================================]

How to use 
local keyboard = require("libs/keyboard")
keyboard.setInput(eventType, patternStr)

-- event_type can be "KeyDown", "KeyUp", or "KeyPress" 
-- patternStr see SUPPORTED TOKEN DICTIONARY below for formatting examples

-- 1. STANDARD KEYPRESS EXAMPLES (Fire and Forget)
-- Simulates a complete click lifecycle: Presses forward, holds 100ms, releases reverse.

-- Open a game menu or inventory screen
-- keyboard.setInput("KeyPress", "I")

-- Universal Windows copy command
-- keyboard.setInput("KeyPress", "CTRL+C")

-- Select all text or items in a UI field
-- keyboard.setInput("KeyPress", "CONTROL+A")

-- In-game quicksave macro
-- keyboard.setInput("KeyPress", "SHIFT+F5")


-- 2. MOUSE INTEGRATION EXAMPLES
-- Combines hardware modifier keys with simulated mouse clicks.

-- Simulates holding Shift while clicking (e.g., split item stack)
-- keyboard.setInput("KeyPress", "SHIFT+CLICK")

-- Contextual right-click option shortcut
-- keyboard.setInput("KeyPress", "CTRL+RCLICK")


-- 3. STATE MANAGEMENT EXAMPLES (Hold & Release)
-- Perfect for running actions continuously while a physical VR button is held down.

-- Trigger this immediately when a VR button or gesture is FIRST detected:
-- keyboard.setInput("KeyDown", "ALT")

-- ... (Your game logic or script loop runs here while key is held) ...

-- Trigger this when the VR button or gesture is finally RELEASED:
-- keyboard.setInput("KeyUp", "ALT")


-- 4. EXTENDED KEYS & PUNCTUATION EXAMPLES
-- Handles special layouts and hardware flags automatically.

-- Navigate a UI menu down one step using extended hardware scan codes
-- keyboard.setInput("KeyPress", "DOWN")

-- Send an in-game terminal command or opening bracket
-- keyboard.setInput("KeyPress", "SHIFT+[")

--[==========================================================================[
                        SUPPORTED TOKEN DICTIONARY                     
--==========================================================================]
-- Pass these tokens into 'patternStr' separated by a '+' (e.g., "CTRL+SHIFT+A").
-- Tokens are entirely case-insensitive.
-- 
-- [MOUSE CLICKS]
-- - Left Click   : "CLICK", "LCLICK", "LEFTCLICK"
-- - Right Click  : "RCLICK", "RIGHTCLICK"
-- - Middle Click : "MCLICK", "MIDDLECLICK"
-- 
-- [MODIFIERS & UTILITY]
-- - Control      : "CTRL", "CONTROL"
-- - Shift        : "SHIFT"
-- - Alt          : "ALT"
-- - Tab          : "TAB"
-- - Escape       : "ESC", "ESCAPE"
-- - Enter        : "ENTER", "RETURN"
-- - Spacebar     : "SPACE"
-- - Backspace    : "BACKSPACE"
-- 
-- [NAVIGATION & EDITING]
-- - Delete       : "DELETE", "DEL"
-- - Insert       : "INSERT"
-- - Home         : "HOME"
-- - End          : "END"
-- - Page Up      : "PAGEUP"
-- - Page Down    : "PAGEDOWN"
-- 
-- [DIRECTIONAL ARROWS] (Handled automatically as Windows Extended Keys)
-- - Up Arrow     : "UP"
-- - Down Arrow   : "DOWN"
-- - Left Arrow   : "LEFT"
-- - Right Arrow  : "RIGHT"
-- 
-- [PUNCTUATION & SYMBOLS]
-- - Semicolon    : ";"  or "SEMICOLON"
-- - Equal Sign   : "="  or "EQUAL"
-- - Comma        : ","  or "COMMA"
-- - Minus / Dash : "-"  or "MINUS"
-- - Period       : "."  or "PERIOD"
-- - Forward Slash: "/"  or "SLASH"
-- - Backtick     : "`"  or "TILDE"
-- - Left Bracket : "["  or "LBRACKET"
-- - Backslash    : "\\" or "BACKSLASH"
-- - Right Bracket: "]"  or "RBRACKET"
-- - Single Quote : "'"  or "QUOTE"
-- 
-- [ALPHANUMERIC]
-- - Any single character key 'A' through 'Z' or '0' through '9'.

--==========================================================================]]

local M = {}
local function setInput(eventType, patternStr)
    if eventType == "KeyPress" then
        uevr.api:dispatch_custom_event("KeyDown", patternStr)
        delay(100, function()
            uevr.api:dispatch_custom_event("KeyUp", patternStr)
        end)
    else
        uevr.api:dispatch_custom_event(eventType, patternStr)
    end
end
function M.setInput(eventType, patternStr)
    setInput(eventType, patternStr)
end

-- These are convenience functions when updating the keyboard state based on continuous input events.
-- For instance pressing the trigger continuously fires repeated input events and
-- these methods allow the keypress event to fire once until the trigger is released
--Example:
--  keyboard.updateToggleState(state.Gamepad.sThumbLY > 20000, "W") -- forward
--  keyboard.updateButtonState(state.Gamepad.bRightTrigger > 0, "LCLICK")

local keyboardStatus = {}
local function updateOneShotState(active, key)
    if active then
        if keyboardStatus[key] ~= true then
            setInput("KeyDown", key)
            delay(100, function()
                setInput("KeyUp", key)
            end)
            keyboardStatus[key] = true
        end
    else
       if keyboardStatus[key] == true then
            --SetInput("KeyUp", key)
            keyboardStatus[key] = false
        end
    end
end
function M.updateOneShotState(active, key)
    updateOneShotState(active, key)
end

-- KeyDown is sent immediately when the trigger is pressed.
-- KeyUp is not sent until the trigger is released.
local function updateToggleState(active, key)
    if active then
        if keyboardStatus[key] ~= true then
            setInput("KeyDown", key)
            keyboardStatus[key] = true
        end
    else
       if keyboardStatus[key] == true then
            setInput("KeyUp", key)
            keyboardStatus[key] = false
        end
    end
end
function M.updateToggleState(active, key)
    updateToggleState(active, key)
end

-- KeyPress is sent immediately when the trigger is pressed.
-- but no more will be sent until the trigger is released.
local function updateButtonState(active, key)
    if active then
        if keyboardStatus[key] ~= true then
            setInput("KeyPress", key)
            keyboardStatus[key] = true
        end
    else
        if keyboardStatus[key] == true then
            keyboardStatus[key] = false
        end
    end
end
function M.updateButtonState(active, key)
    updateButtonState(active, key)
end

-- hander for long button vs short button press
-- example
--   keyboard.updateShortLongButtonState(uevrUtils.isButtonPressed(state, XINPUT_GAMEPAD_X), "C", "T", "switchWeaponsButton", LONG_PRESS_SECONDS)
local function updateShortLongButtonState(active, shortKey, longKey, stateKey, holdSeconds)
    local buttonState = keyboardStatus[stateKey]
    if buttonState == nil then
        buttonState = {}
        keyboardStatus[stateKey] = buttonState
    end

    if active then
        if buttonState.isPressed ~= true then
            buttonState.isPressed = true
            buttonState.pressStartedAt = os.clock()
            buttonState.longPressTriggered = false
        elseif buttonState.longPressTriggered ~= true and buttonState.pressStartedAt ~= nil and (os.clock() - buttonState.pressStartedAt) >= holdSeconds then
            setInput("KeyPress", longKey)
            buttonState.longPressTriggered = true
        end
    elseif buttonState.isPressed == true then
        if buttonState.longPressTriggered ~= true then
            local heldFor = buttonState.pressStartedAt ~= nil and (os.clock() - buttonState.pressStartedAt) or 0
            if heldFor >= holdSeconds then
                setInput("KeyPress", longKey)
            else
                setInput("KeyPress", shortKey)
            end
        end

        buttonState.isPressed = false
        buttonState.pressStartedAt = nil
        buttonState.longPressTriggered = false
    end
end
function M.updateShortLongButtonState(active, shortKey, longKey, stateKey, holdSeconds)
    updateShortLongButtonState(active, shortKey, longKey, stateKey, holdSeconds)
end

return M
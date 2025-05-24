local addonName, addonTable = ...
local frame = CreateFrame("Frame", nil, UIParent)

-- Variables to store game state
local isRunning = false
local actionButtons = {}
local currentActionButton
local startTime
local totalReactionTime = 0
local buttonCount = 0
local buttonStartTime -- Declared here, will be set in NextButton

-- List of action bar names (updated for Dragonflight)
local actionBars = {
    "ActionButton",
    "MultiBarBottomLeftButton",
    "MultiBarBottomRightButton",
    "MultiBarRightButton",
    "MultiBarLeftButton",
    "MultiBar5Button", -- Note: These specific MultiBar names (5-8) might not correspond to default _G accessible frames
    "MultiBar6Button", -- depending on the user's UI setup (e.g., if using bar addons).
    "MultiBar7Button", -- The code will gracefully skip them if _G[buttonName] is nil.
    "MultiBar8Button",
}

-- Create a frame for displaying the icon
local iconFrame = CreateFrame("Frame", nil, UIParent)
iconFrame:SetSize(64, 64)
iconFrame:SetPoint("CENTER")
iconFrame:Hide()

local iconTexture = iconFrame:CreateTexture(nil, "ARTWORK")
iconTexture:SetAllPoints()
iconFrame.texture = iconTexture

local iconText = iconFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
iconText:SetPoint("BOTTOM", iconFrame, "TOP", 0, 5)
iconFrame.text = iconText

-- Create a frame for displaying the number of remaining queries
local queryFrame = CreateFrame("Frame", nil, UIParent)
queryFrame:SetSize(200, 50)
queryFrame:SetPoint("TOP", 0, -50)
queryFrame:Hide()

local queryText = queryFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
queryText:SetPoint("CENTER")
queryFrame.text = queryText

-- Forward declare functions that might call each other before full definition
local NextButton, EndGame, CheckBind

-- Function to update the query count display
local function UpdateQueryCount()
    queryText:SetText("Remaining Queries: " .. #actionButtons)
    queryFrame:Show()
end

-- Function to start the game
local function StartGame()
    DEFAULT_CHAT_FRAME:AddMessage("StartGame function called")
    if isRunning then 
        DEFAULT_CHAT_FRAME:AddMessage("Game is already running")
        return 
    end
    isRunning = true
    totalReactionTime = 0
    buttonCount = 0
    actionButtons = {}
    startTime = GetTime()  -- Set the start time of the game

    -- Use a set to track unique actions to avoid testing the same spell/macro multiple times
    -- if it appears on multiple action bar slots.
    local uniqueActions = {}

    -- Scan all action bars to find buttons with assigned spells or macros and keybindings
    for _, barName in ipairs(actionBars) do
        DEFAULT_CHAT_FRAME:AddMessage("Scanning bar: " .. barName)
        for buttonIndex = 1, 12 do
            local buttonName = barName .. buttonIndex
            local button = _G[buttonName] -- Get the global frame object for the button
            if button then
                DEFAULT_CHAT_FRAME:AddMessage("Found button: " .. buttonName)
                local slot = button:GetPagedID() -- Get the action slot ID this button is currently showing
                local actionType, id, subType = GetActionInfo(slot) -- Get info about what's on the button

                if actionType and id then -- We need an action type and an ID (spell ID or macro ID)
                    local uniqueKey = actionType .. ":" .. id -- Create a unique key for this action
                    if not uniqueActions[uniqueKey] then
                        local actionName, icon
                        
                        -- Retrieve action name and icon based on type
                        if actionType == "macro" then
                            local macroNameText = GetActionText(slot) -- GetActionText returns the macro's name from the button
                            if macroNameText and macroNameText ~= "" then
                                local macroIdx = GetMacroIndexByName(macroNameText) -- Get a macro's index by its name
                                if macroIdx and macroIdx > 0 then
                                    -- GetMacroInfo provides the canonical name and icon texture using the index
                                    local mName, mIcon = GetMacroInfo(macroIdx) 
                                    if mName and mName ~= "" and mIcon then -- Ensure the retrieved info is valid
                                        actionName = mName
                                        icon = mIcon
                                    end
                                end
                            end
                        elseif actionType == "spell" then
                            local sName, _, sIcon = GetSpellInfo(id) -- Get spell info by its ID
                            if sName and sName ~= "" and sIcon then -- Ensure the retrieved info is valid
                                actionName = sName
                                icon = sIcon
                            end
                        end

                        -- Only proceed if we successfully got a valid action name and icon
                        if actionName and icon then
                            local collectedKeyBindings = {}
                            local processedForThisAction = {} -- Helper to avoid adding the same keybind string twice for one action

                            -- Helper function to add a keybind if it's valid, not a mouse wheel bind, and not a duplicate
                            local function addKeyIfValid(keyString)
                                if keyString and keyString ~= "" then -- Ensure keyString is not nil or empty
                                    local upperKeyString = string.upper(keyString)
                                    
                                    -- << MODIFICATION: SKIP MOUSE WHEEL BINDS >>
                                    if string.find(upperKeyString, "MOUSEWHEELUP") or string.find(upperKeyString, "MOUSEWHEELDOWN") then
                                        DEFAULT_CHAT_FRAME:AddMessage("Skipping mouse wheel bind: " .. keyString .. " for action on button " .. buttonName)
                                    elseif not processedForThisAction[keyString] then -- Check if already processed for this specific action
                                        table.insert(collectedKeyBindings, keyString)
                                        processedForThisAction[keyString] = true
                                    end
                                end
                            end

                            -- Retrieve key bindings for the action button (checking both "CLICK" and direct slot binds)
                            addKeyIfValid(GetBindingKey("CLICK " .. buttonName .. ":LeftButton"))
                            
                            local buttonSpecificActionName = "" -- Determine the direct binding string (e.g., "ACTIONBUTTON1")
                            if buttonName:find("^ActionButton") then buttonSpecificActionName = "ACTIONBUTTON" .. buttonIndex
                            elseif buttonName:find("^MultiBarBottomLeftButton") then buttonSpecificActionName = "MULTIACTIONBAR1BUTTON" .. buttonIndex
                            elseif buttonName:find("^MultiBarBottomRightButton") then buttonSpecificActionName = "MULTIACTIONBAR2BUTTON" .. buttonIndex
                            elseif buttonName:find("^MultiBarRightButton") then buttonSpecificActionName = "MULTIACTIONBAR3BUTTON" .. buttonIndex
                            elseif buttonName:find("^MultiBarLeftButton") then buttonSpecificActionName = "MULTIACTIONBAR4BUTTON" .. buttonIndex
                            elseif buttonName:find("^MultiBar5Button") then buttonSpecificActionName = "MULTIACTIONBAR5BUTTON" .. buttonIndex
                            elseif buttonName:find("^MultiBar6Button") then buttonSpecificActionName = "MULTIACTIONBAR6BUTTON" .. buttonIndex
                            elseif buttonName:find("^MultiBar7Button") then buttonSpecificActionName = "MULTIACTIONBAR7BUTTON" .. buttonIndex
                            elseif buttonName:find("^MultiBar8Button") then buttonSpecificActionName = "MULTIACTIONBAR8BUTTON" .. buttonIndex
                            end
                            
                            if buttonSpecificActionName ~= "" then
                                addKeyIfValid(GetBindingKey(buttonSpecificActionName))
                            end

                            -- If we found any non-mouse wheel keybindings for this action
                            if #collectedKeyBindings > 0 then
                                table.insert(actionButtons, {
                                    buttonName = buttonName, 
                                    keyBindings = collectedKeyBindings, 
                                    icon = icon, 
                                    actionName = actionName
                                })
                                uniqueActions[uniqueKey] = true -- Mark this action as processed
                                DEFAULT_CHAT_FRAME:AddMessage("Found button with valid keybinding(s): " .. buttonName .. " - " .. actionName .. " - Key Bindings: " .. table.concat(collectedKeyBindings, ", "))
                            else
                                DEFAULT_CHAT_FRAME:AddMessage("Button " .. buttonName .. " (".. (actionName or "Unknown Action") ..") has no suitable (non-mouse wheel) keybindings or was a duplicate action.")
                            end
                        else
                            -- This message would appear if GetMacroInfo or GetSpellInfo failed to return valid data
                            -- DEFAULT_CHAT_FRAME:AddMessage("Button " .. buttonName .. " - Skipped (actionType " .. actionType .. ") - did not yield valid actionName or icon.")
                        end
                    end
                else
                    DEFAULT_CHAT_FRAME:AddMessage("No action type and id found for button: " .. buttonName)
                end
            else
                DEFAULT_CHAT_FRAME:AddMessage("Button not found: " .. buttonName)
            end
        end
    end

    -- Check if any action buttons with suitable keybindings were found
    if #actionButtons == 0 then
        DEFAULT_CHAT_FRAME:AddMessage("No action buttons with suitable (non-mouse wheel) keybindings found to test.")
        isRunning = false
        return
    end

    -- Update the query count display
    UpdateQueryCount()

    -- Start testing the first button
    DEFAULT_CHAT_FRAME:AddMessage("Starting the game with " .. #actionButtons .. " actions to test.")
    frame:EnableKeyboard(true)
    UIParent:EnableMouse(true)  -- Enable mouse input on UIParent (for the OnMouseDown hook)
    NextButton()
end

-- Function to end the game
EndGame = function() 
    if not isRunning then return end
    isRunning = false
    frame:EnableKeyboard(false)
    UIParent:EnableMouse(false)  -- Disable mouse input on UIParent
    local endTime = GetTime()
    local totalTime = endTime - startTime 
    local scorePerSecond = 0
    if totalTime > 0 then 
        scorePerSecond = buttonCount / totalTime
    else
        if buttonCount > 0 then scorePerSecond = math.huge end -- Handle case where game ends instantly
    end
    DEFAULT_CHAT_FRAME:AddMessage("Finished! Time : " .. string.format("%.2f", totalTime) .. " seconds.")
    DEFAULT_CHAT_FRAME:AddMessage("Score per second : " .. string.format("%.2f", scorePerSecond))
    
    -- Clear the override binding
    ClearOverrideBindings(frame)

    -- Hide the icon frame
    iconFrame:Hide()

    -- Hide the query frame
    queryFrame:Hide()
end

-- Function to test the next button
NextButton = function() 
    if not isRunning or #actionButtons == 0 then
        EndGame()
        return
    end

    -- Choose a random untested button
    local index = math.random(1, #actionButtons)
    currentActionButton = actionButtons[index]
    table.remove(actionButtons, index)
    
    DEFAULT_CHAT_FRAME:AddMessage("Testing button: " .. currentActionButton.buttonName .. " (" .. currentActionButton.actionName .. ")")

    -- Display the button icon and name on the screen
    iconFrame.texture:SetTexture(currentActionButton.icon)
    iconFrame.text:SetText(currentActionButton.actionName)
    iconFrame:Show()

    -- Update the query count display
    UpdateQueryCount()

    -- Set the override binding for the current action button
    ClearOverrideBindings(frame)
    local keyBindings = currentActionButton.keyBindings

    if #keyBindings == 0 then
        -- This case should ideally not be hit if StartGame filters properly,
        -- but good to have as a fallback.
        DEFAULT_CHAT_FRAME:AddMessage("No key bindings found for button: " .. currentActionButton.buttonName .. ". Skipping.")
        NextButton() -- Try next button
        return
    end

    for _, key in ipairs(keyBindings) do
        SetOverrideBindingClick(frame, true, key, currentActionButton.buttonName)
        DEFAULT_CHAT_FRAME:AddMessage("Binding key: " .. key .. " to button: " .. currentActionButton.buttonName)
    end

    -- Record the start time for this button
    buttonStartTime = GetTime()  -- This is now specific to each button
end

-- Function to get key bindings for a given button
-- This is a utility function and also skips mouse wheel binds for consistency.
local function GetKeyBindingsForButton(buttonName)
    local keyBindings = {}
    local processedForThisAction = {}

    local function addKey(keyString)
        if keyString and keyString ~= "" then
            local upperKeyString = string.upper(keyString)
            -- Skip mouse wheel binds here too
            if string.find(upperKeyString, "MOUSEWHEELUP") or string.find(upperKeyString, "MOUSEWHEELDOWN") then
                -- Optionally log skipping if this function is used for user display
            elseif not processedForThisAction[keyString] then
                table.insert(keyBindings, keyString)
                processedForThisAction[keyString] = true
            end
        end
    end

    local bindingAction = "CLICK " .. buttonName .. ":LeftButton"
    addKey(GetBindingKey(bindingAction))

    local buttonIndex = tonumber(buttonName:match("%d+$"))
    local buttonSpecificAction = ""

    if buttonIndex then 
        if buttonName:find("^ActionButton") then
            buttonSpecificAction = "ACTIONBUTTON" .. buttonIndex
        elseif buttonName:find("^MultiBarBottomLeftButton") then
            buttonSpecificAction = "MULTIACTIONBAR1BUTTON" .. buttonIndex
        elseif buttonName:find("^MultiBarBottomRightButton") then
            buttonSpecificAction = "MULTIACTIONBAR2BUTTON" .. buttonIndex
        elseif buttonName:find("^MultiBarRightButton") then
            buttonSpecificAction = "MULTIACTIONBAR3BUTTON" .. buttonIndex
        elseif buttonName:find("^MultiBarLeftButton") then
            buttonSpecificAction = "MULTIACTIONBAR4BUTTON" .. buttonIndex
        elseif buttonName:find("^MultiBar5Button") then
            buttonSpecificAction = "MULTIACTIONBAR5BUTTON" .. buttonIndex
        elseif buttonName:find("^MultiBar6Button") then
            buttonSpecificAction = "MULTIACTIONBAR6BUTTON" .. buttonIndex
        elseif buttonName:find("^MultiBar7Button") then
            buttonSpecificAction = "MULTIACTIONBAR7BUTTON" .. buttonIndex
        elseif buttonName:find("^MultiBar8Button") then
            buttonSpecificAction = "MULTIACTIONBAR8BUTTON" .. buttonIndex
        end
    end

    if buttonSpecificAction ~= "" then
        addKey(GetBindingKey(buttonSpecificAction))
    end

    return keyBindings
end

CheckBind = function(keyOrButton) 
    if not isRunning then return end
    -- Guard against currentActionButton being nil, which could happen if EndGame was called
    -- or if NextButton had an issue before currentActionButton was fully set.
    if not currentActionButton or not currentActionButton.keyBindings then 
        -- DEFAULT_CHAT_FRAME:AddMessage("DEBUG: CheckBind called but currentActionButton or its keyBindings are nil.")
        return
    end

    local function GetModifiedKey(key)
        local modKey = key
        if IsShiftKeyDown() then
            modKey = "SHIFT-" .. modKey
        end
        if IsControlKeyDown() then
            modKey = "CTRL-" .. modKey
        end
        if IsAltKeyDown() then
            modKey = "ALT-" .. modKey
        end
        return modKey
    end

    local pressedKey = GetModifiedKey(keyOrButton)
    DEFAULT_CHAT_FRAME:AddMessage("Key or button pressed: " .. pressedKey)
    
    -- Check if the pressed key matches the current action button binding
    local keyBindings = currentActionButton.keyBindings
    local expectedKeys = table.concat(keyBindings, ", ")
    if #keyBindings == 0 then
        DEFAULT_CHAT_FRAME:AddMessage("No key bindings found for the current action button ("..currentActionButton.actionName.."). This shouldn't happen if filtered in StartGame.")
    else
        for _, keyBinding in ipairs(keyBindings) do
            DEFAULT_CHAT_FRAME:AddMessage("Checking key binding: " .. keyBinding)
            if pressedKey == keyBinding then
                local endTime = GetTime()
                local reactionTime = endTime - buttonStartTime
                totalReactionTime = totalReactionTime + reactionTime
                buttonCount = buttonCount + 1
                DEFAULT_CHAT_FRAME:AddMessage("Bravo! ("..currentActionButton.actionName..") Reaction time : " .. string.format("%.2f", reactionTime) .. " seconds.")

                iconFrame:Hide() -- Hide the icon frame for the completed action
                NextButton()     -- Test the next button
                return           -- Exit CheckBind as we found a match
            end
        end
        DEFAULT_CHAT_FRAME:AddMessage("Wrong key for "..currentActionButton.actionName.."! Expected: " .. expectedKeys)
    end
end

-- Event to capture key presses
frame:SetScript("OnKeyDown", function(self, key)
    if isRunning then
        if key == "ESCAPE" then
            DEFAULT_CHAT_FRAME:AddMessage("ESCAPE pressed, ending game.")
            EndGame()
            return
        end
        CheckBind(key)
    end
end)

-- Event to capture mouse button presses (hooked onto UIParent)
UIParent:HookScript("OnMouseDown", function(self, button)
    if isRunning then
        local processedButton = string.upper(button) -- e.g., "LEFTBUTTON", "RIGHTBUTTON", "MIDDLEBUTTON", "BUTTON4", "BUTTON5"
        if processedButton == "MIDDLEBUTTON" then -- Standardize MiddleButton to BUTTON3 for consistency with GetBindingKey
            processedButton = "BUTTON3"
        end
        -- For Button4, Button5 etc., string.upper(button) usually results in "BUTTON4", "BUTTON5"
        -- which matches GetBindingKey output, so no further special handling usually needed.
        DEFAULT_CHAT_FRAME:AddMessage("Mouse button pressed: " .. processedButton)
        CheckBind(processedButton)
    end
end)

-- Create a slash command to start the game
SLASH_KB1 = "/kb" -- Defines the slash command
SlashCmdList["KB"] = function() -- Associates the function with the command
    DEFAULT_CHAT_FRAME:AddMessage("/kb command received")
    StartGame()
end

-- Register event for initial setup (like disabling keyboard input for the frame at login)
frame:RegisterEvent("PLAYER_LOGIN")
frame:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_LOGIN" then
        self:EnableKeyboard(false) -- Ensure our frame doesn't globally capture keyboard input unless isRunning
        UIParent:EnableMouse(false)  -- Ensure mouse input is initially disabled on UIParent by this addon's logic
                                     -- Note: Other addons or the base UI will still enable mouse for UIParent.
                                     -- This line in the original was likely to try and control mouse input state,
                                     -- but UIParent:EnableMouse(true) in StartGame is what matters for the hook.
    end
end)
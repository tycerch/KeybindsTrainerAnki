local addonName, addonTable = ...
local frame = CreateFrame("Frame", nil, UIParent)

-- Variables to store game state
local isRunning = false
local actionButtons = {}
local currentActionButton
local startTime
local totalReactionTime = 0
local buttonCount = 0

-- List of action bar names (updated for Dragonflight)
local actionBars = {
    "ActionButton",
    "MultiBarBottomLeftButton",
    "MultiBarBottomRightButton",
    "MultiBarRightButton",
    "MultiBarLeftButton",
    "MultiBar5Button",
    "MultiBar6Button",
    "MultiBar7Button",
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

    -- Use a set to track unique actions
    local uniqueActions = {}

    -- Scan all action bars to find buttons with assigned spells or macros and keybindings
    for _, barName in ipairs(actionBars) do
        DEFAULT_CHAT_FRAME:AddMessage("Scanning bar: " .. barName)
        for buttonIndex = 1, 12 do
            local buttonName = barName .. buttonIndex
            local button = _G[buttonName]
            if button then
                DEFAULT_CHAT_FRAME:AddMessage("Found button: " .. buttonName)
                local slot = button:GetPagedID()
                local actionType, id, subType = GetActionInfo(slot)
                if actionType and id then
                    local uniqueKey = actionType .. ":" .. id
                    if not uniqueActions[uniqueKey] then
                        local actionName, icon
                        if actionType == "macro" then
                            local macroName = GetActionText(slot)
                            local _, macroIcon = GetMacroInfo(macroName)
                            actionName = macroName
                            icon = macroIcon
                        elseif actionType == "spell" then
                            actionName, _, icon = GetSpellInfo(id)
                        end

                        if actionName and icon then
                            local keyBindings = {}
                            local bindingAction = "CLICK " .. buttonName .. ":LeftButton"
                            
                            -- Retrieve key bindings for the action button
                            local keys = { GetBindingKey(bindingAction) }
                            for _, key in ipairs(keys) do
                                if key then
                                    table.insert(keyBindings, key)
                                end
                            end

                            -- Also check for bindings using the "ACTIONBUTTON" prefix specific to the current button slot
                            local buttonSpecificAction = "ACTIONBUTTON" .. buttonIndex

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

                            local buttonKeys = { GetBindingKey(buttonSpecificAction) }
                            for _, key in ipairs(buttonKeys) do
                                if key then
                                    table.insert(keyBindings, key)
                                end
                            end

                            if #keyBindings > 0 then
                                table.insert(actionButtons, {buttonName = buttonName, keyBindings = keyBindings, icon = icon, actionName = actionName})
                                uniqueActions[uniqueKey] = true
                                DEFAULT_CHAT_FRAME:AddMessage("Found button with keybinding: " .. buttonName .. " - " .. actionName .. " - Key Bindings: " .. table.concat(keyBindings, ", "))
                            else
                                DEFAULT_CHAT_FRAME:AddMessage("Button with action but no keybinding: " .. buttonName .. " - " .. actionName)
                            end
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

    -- Check if any action buttons with keybindings were found
    if #actionButtons == 0 then
        DEFAULT_CHAT_FRAME:AddMessage("No action buttons with keybindings found.")
        isRunning = false
        return
    end

    -- Update the query count display
    UpdateQueryCount()

    -- Start testing the first button
    DEFAULT_CHAT_FRAME:AddMessage("Starting the game with " .. #actionButtons .. " buttons.")
    frame:EnableKeyboard(true)
    UIParent:EnableMouse(true)  -- Enable mouse input on UIParent
    NextButton()
end

-- Function to end the game
local function EndGame()
    if not isRunning then return end
    isRunning = false
    frame:EnableKeyboard(false)
    UIParent:EnableMouse(false)  -- Disable mouse input on UIParent
    local endTime = GetTime()
    local totalTime = endTime - startTime  -- Calculate total time since the game started
    local scorePerSecond = buttonCount / totalTime
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
function NextButton()
    if not isRunning or #actionButtons == 0 then
        EndGame()
        return
    end

    -- Choose a random untested button
    local index = math.random(1, #actionButtons)
    currentActionButton = actionButtons[index]
    table.remove(actionButtons, index)
    
    DEFAULT_CHAT_FRAME:AddMessage("Testing button: " .. currentActionButton.buttonName)

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
        DEFAULT_CHAT_FRAME:AddMessage("No key bindings found for button: " .. currentActionButton.buttonName)
    else
        for _, key in ipairs(keyBindings) do
            SetOverrideBindingClick(frame, true, key, currentActionButton.buttonName)
            DEFAULT_CHAT_FRAME:AddMessage("Binding key: " .. key .. " to button: " .. currentActionButton.buttonName)
        end
    end

    -- Record the start time for this button
    buttonStartTime = GetTime()  -- This is now specific to each button
end

-- Function to get key bindings for a given button
local function GetKeyBindingsForButton(buttonName)
    local keyBindings = {}

    -- Check for key bindings associated with the "CLICK ButtonName:LeftButton" action
    local bindingAction = "CLICK " .. buttonName .. ":LeftButton"
    local keys = { GetBindingKey(bindingAction) }
    for _, key in ipairs(keys) do
        if key then
            table.insert(keyBindings, key)
        end
    end

    -- Also check for key bindings associated with the button slot directly
    local buttonIndex = tonumber(buttonName:match("%d+$"))
    local buttonSpecificAction

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

    if buttonSpecificAction then
        local buttonKeys = { GetBindingKey(buttonSpecificAction) }
        for _, key in ipairs(buttonKeys) do
            if key then
                table.insert(keyBindings, key)
            end
        end
    end

    return keyBindings
end

local function CheckBind(keyOrButton)
    if not isRunning then return end

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
        DEFAULT_CHAT_FRAME:AddMessage("No key bindings found for the current action button.")
    else
        for _, keyBinding in ipairs(keyBindings) do
            DEFAULT_CHAT_FRAME:AddMessage("Checking key binding: " .. keyBinding)
            if pressedKey == keyBinding then
                local endTime = GetTime()
                local reactionTime = endTime - buttonStartTime  -- Use button start time here
                totalReactionTime = totalReactionTime + reactionTime
                buttonCount = buttonCount + 1
                DEFAULT_CHAT_FRAME:AddMessage("Bravo ! Reaction time : " .. string.format("%.2f", reactionTime) .. " seconds.")

                -- Hide the icon frame
                iconFrame:Hide()

                -- Test the next button
                NextButton()
                return
            end
        end
        DEFAULT_CHAT_FRAME:AddMessage("Wrong key! Try again. Expected: " .. expectedKeys)
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

-- Event to capture mouse button presses
UIParent:HookScript("OnMouseDown", function(self, button)
    if isRunning then
        if string.find(button, "Button") then
            button = string.upper(button)
        end
        if string.upper(button) == "MIDDLEBUTTON" then
            button = "BUTTON3"
        end
        DEFAULT_CHAT_FRAME:AddMessage("Mouse button pressed: " .. button)
        CheckBind(button)
    end
end)

-- Create a slash command to start the game
SLASH_KB1 = "/kb"
SlashCmdList["KB"] = function()
    DEFAULT_CHAT_FRAME:AddMessage("/kb command received")
    StartGame()
end

-- Register event to enable keyboard input only when the game starts
frame:RegisterEvent("PLAYER_LOGIN")
frame:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_LOGIN" then
        self:EnableKeyboard(false)
        UIParent:EnableMouse(false)  -- Ensure mouse input is initially disabled on UIParent
    end
end)

local addonName, addonTable = ...
-- KBT_SavedData will be our table for storing persistent data,
-- including reaction times for the Anki-style feature.
-- WoW will automatically manage loading and saving this table if declared in the .toc file.
-- KBT_SavedData = nil -- No need to initialize to nil here; WoW handles it.

local frame = CreateFrame("Frame", nil, UIParent)

-- Configuration for the Anki-style feature
local PROMPTS_PER_SESSION = 20 -- How many of the "slowest" actions to test each session

-- Variables to store game state
local isRunning = false
local actionButtons = {} -- This will hold the selected actions for the current session
local currentActionButton
local startTime
local totalReactionTime = 0
local buttonCount = 0
local buttonStartTime -- To record reaction time for individual binds

-- List of action bar names (updated for Dragonflight)
local actionBars = {
    "ActionButton",
    "MultiBarBottomLeftButton",
    "MultiBarBottomRightButton",
    "MultiBarRightButton",
    "MultiBarLeftButton",
    "MultiBar5Button", -- Note: These specific MultiBar names (5-8) might not correspond
    "MultiBar6Button", -- to default _G accessible frames depending on the user's UI setup.
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
    -- Only show the query frame if the game is running and there are actions
    if isRunning and #actionButtons > 0 then
        queryText:SetText("Remaining Queries: " .. #actionButtons)
        queryFrame:Show()
    else
        queryFrame:Hide() -- Hide if not running or no actions selected for the session
    end
end

-- Function to start the game
local function StartGame()
    DEFAULT_CHAT_FRAME:AddMessage("StartGame function called")
    if isRunning then 
        DEFAULT_CHAT_FRAME:AddMessage("Game is already running. Use ESC to stop current session.")
        return 
    end
    
    isRunning = true
    totalReactionTime = 0
    buttonCount = 0
    actionButtons = {} -- This will be populated with the top N slowest actions
    startTime = GetTime()  -- Set the start time of the game session

    -- Use a set to track unique actions to avoid processing the same spell/macro multiple times
    -- if it appears on different action bar slots during the initial scan.
    local uniqueActions = {}
    local allScannedActions = {} -- Temporary list to hold ALL found and eligible actions before sorting and slicing

    DEFAULT_CHAT_FRAME:AddMessage("Scanning action bars for all eligible actions...")
    -- Scan all action bars to find buttons with assigned spells or macros and keybindings
    for _, barName in ipairs(actionBars) do
        -- DEFAULT_CHAT_FRAME:AddMessage("Scanning bar: " .. barName) -- Can be verbose
        for buttonIndex = 1, 12 do
            local buttonName = barName .. buttonIndex
            local button = _G[buttonName] -- Get the global frame object for the button
            if button then
                -- DEFAULT_CHAT_FRAME:AddMessage("Found button: " .. buttonName) -- Can be verbose
                local slot = button:GetPagedID() -- Get the action slot ID this button is currently showing
                local actionType, id, subType = GetActionInfo(slot) -- Get info about what's on the button

                if actionType and id then -- We need an action type and an ID (spell ID or macro ID)
                    local uniqueKey = actionType .. ":" .. id -- Create a unique key for this action (e.g., "spell:12345")
                    if not uniqueActions[uniqueKey] then
                        local actionName, icon
                        
                        -- Retrieve action name and icon based on type, with enhanced robustness
                        if actionType == "macro" then
                            local macroNameText = GetActionText(slot) -- GetActionText returns the macro's name
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
                                    
                                    -- Automatically skip any MOUSEWHEELUP or MOUSEWHEELDOWN binds
                                    if string.find(upperKeyString, "MOUSEWHEELUP") or string.find(upperKeyString, "MOUSEWHEELDOWN") then
                                        -- DEFAULT_CHAT_FRAME:AddMessage("Skipping mouse wheel bind: " .. keyString .. " for action on button " .. buttonName)
                                    elseif not processedForThisAction[keyString] then -- Check if already processed for this specific action
                                        table.insert(collectedKeyBindings, keyString)
                                        processedForThisAction[keyString] = true
                                    end
                                end
                            end

                            -- Retrieve key bindings for the action button
                            addKeyIfValid(GetBindingKey("CLICK " .. buttonName .. ":LeftButton"))
                            
                            -- Also check for bindings using the "ACTIONBUTTON" prefix specific to the current button slot
                            local buttonSpecificActionName = "" 
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
                                -- Add to the temporary list of all scannable actions
                                table.insert(allScannedActions, {
                                    buttonName = buttonName, 
                                    keyBindings = collectedKeyBindings, 
                                    icon = icon, 
                                    actionName = actionName,
                                    uniqueKey = uniqueKey -- Store the uniqueKey for reaction time tracking
                                })
                                uniqueActions[uniqueKey] = true -- Mark this action type as found to avoid duplicates
                                -- DEFAULT_CHAT_FRAME:AddMessage("Scanned: " .. actionName .. " (Button: " .. buttonName .. ") - Keys: " .. table.concat(collectedKeyBindings, ", "))
                            else
                                -- This message appears if an action's only binds were mouse wheel (and thus skipped) or it genuinely had no binds.
                                -- DEFAULT_CHAT_FRAME:AddMessage("Button " .. buttonName .. " ("..actionName..") has no suitable keybindings.")
                            end
                        end
                    end
                else
                    -- DEFAULT_CHAT_FRAME:AddMessage("No action type and id found for button: " .. buttonName)
                end
            else
                -- DEFAULT_CHAT_FRAME:AddMessage("Button not found: " .. buttonName) -- Can be verbose
            end
        end
    end

    -- Check if any actions were found at all
    if #allScannedActions == 0 then
        DEFAULT_CHAT_FRAME:AddMessage("No scannable actions with suitable (non-mouse wheel) keybindings found.")
        isRunning = false
        return
    end
    DEFAULT_CHAT_FRAME:AddMessage("Found " .. #allScannedActions .. " total eligible actions with keybinds.")

    -- Sort allScannedActions by last reaction time (descending - slowest first)
    -- This is part of the "Anki-style" prioritization.
    DEFAULT_CHAT_FRAME:AddMessage("Sorting actions by last reaction time (slowest/newest first)...")
    if KBT_SavedData and KBT_SavedData.reactionTimes then
        table.sort(allScannedActions, function(a, b)
            -- If no reaction time is stored (e.g., new action), default to math.huge.
            -- This ensures new/unseen items are treated as the "slowest" and prioritized.
            local rtA = KBT_SavedData.reactionTimes[a.uniqueKey] or math.huge 
            local rtB = KBT_SavedData.reactionTimes[b.uniqueKey] or math.huge
            return rtA > rtB -- Sort descending: higher (slower, or math.huge) times first
        end)
    else
        DEFAULT_CHAT_FRAME:AddMessage("No reaction time data found for sorting; using scanned order (or default sort behavior).")
    end

    -- Populate the actual 'actionButtons' for this session with the top N (or fewer)
    local countToTake = math.min(PROMPTS_PER_SESSION, #allScannedActions)
    DEFAULT_CHAT_FRAME:AddMessage("Selecting the " .. countToTake .. " slowest/newest actions for this session.")
    for i = 1, countToTake do
        table.insert(actionButtons, allScannedActions[i])
    end
    
    -- For debugging the selected session actions:
    -- DEFAULT_CHAT_FRAME:AddMessage("Actions for this session (Slowest " .. countToTake .. "):")
    -- for i, action in ipairs(actionButtons) do
    --    local rtDisplay = "New"
    --    if KBT_SavedData and KBT_SavedData.reactionTimes and KBT_SavedData.reactionTimes[action.uniqueKey] then
    --        rtDisplay = string.format("%.2fs", KBT_SavedData.reactionTimes[action.uniqueKey])
    --    end
    --    DEFAULT_CHAT_FRAME:AddMessage(i .. ". " .. action.actionName .. " (Last RT: " .. rtDisplay .. ")")
    -- end

    if #actionButtons == 0 then
        -- This might happen if PROMPTS_PER_SESSION is 0, or if somehow allScannedActions was emptied.
        DEFAULT_CHAT_FRAME:AddMessage("No actions selected for this session. Ending.")
        isRunning = false
        return
    end

    -- Update the query count display
    UpdateQueryCount()

    -- Start testing the first button
    DEFAULT_CHAT_FRAME:AddMessage("Starting game with " .. #actionButtons .. " actions to test (sorted by slowness).")
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
    
    -- Hide the UI frames
    if iconFrame then iconFrame:Hide() end
    if queryFrame then queryFrame:Hide() end

    local endTime = GetTime()
    local totalTime = endTime - (startTime or endTime) -- Ensure startTime is not nil
    local scorePerSecond = 0
    if totalTime > 0 and buttonCount > 0 then 
        scorePerSecond = buttonCount / totalTime
    end
    DEFAULT_CHAT_FRAME:AddMessage("Finished! Time: " .. string.format("%.2f", totalTime) .. "s. Correct: " .. buttonCount .. ". Score/sec: " .. string.format("%.2f", scorePerSecond))
    
    -- Clear the override binding
    ClearOverrideBindings(frame)
end

-- Function to test the next button
NextButton = function() 
    if not isRunning or #actionButtons == 0 then
        EndGame()
        return
    end

    -- Get the next action from the pre-sorted list (slowest first)
    currentActionButton = actionButtons[1]
    table.remove(actionButtons, 1)         
    
    -- Defensive check for valid action data
    if not currentActionButton or not currentActionButton.actionName or not currentActionButton.icon or not currentActionButton.keyBindings then
        DEFAULT_CHAT_FRAME:AddMessage("Error: Invalid action data encountered in NextButton. Attempting to skip.")
        NextButton() -- Try to get the next valid one
        return
    end
    
    DEFAULT_CHAT_FRAME:AddMessage("Testing: " .. currentActionButton.actionName .. " (Bound to: " .. table.concat(currentActionButton.keyBindings, " or ") ..")")

    -- Display the button icon and name on the screen
    if iconFrame and iconFrame.texture and iconFrame.text then
        iconFrame.texture:SetTexture(currentActionButton.icon)
        iconFrame.text:SetText(currentActionButton.actionName)
        iconFrame:Show()
    else
        DEFAULT_CHAT_FRAME:AddMessage("Error: iconFrame or its components are nil in NextButton. Cannot display prompt.")
        EndGame() -- Critical UI element missing, end the game
        return
    end
    
    -- Update the query count display
    UpdateQueryCount()

    -- Set the override binding for the current action button
    ClearOverrideBindings(frame)
    local keyBindings = currentActionButton.keyBindings

    -- This check should ideally not be necessary if StartGame filters correctly, but as a safeguard:
    if #keyBindings == 0 then
        DEFAULT_CHAT_FRAME:AddMessage("No key bindings found for current action: " .. currentActionButton.actionName .. ". Skipping.")
        NextButton() -- Try next button
        return
    end

    for _, key in ipairs(keyBindings) do
        SetOverrideBindingClick(frame, true, key, currentActionButton.buttonName)
        -- DEFAULT_CHAT_FRAME:AddMessage("Binding key: " .. key .. " to button: " .. currentActionButton.buttonName) -- Can be verbose
    end

    -- Record the start time for this specific button prompt
    buttonStartTime = GetTime()
end

-- Function to get key bindings for a given button (utility function)
-- Also skips mouse wheel binds for consistency if used elsewhere.
local function GetKeyBindingsForButton(buttonName)
    local keyBindings = {}
    local processedForThisAction = {}

    local function addKey(keyString)
        if keyString and keyString ~= "" then
            local upperKeyString = string.upper(keyString)
            if string.find(upperKeyString, "MOUSEWHEELUP") or string.find(upperKeyString, "MOUSEWHEELDOWN") then
                -- Skip mouse wheel binds
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
        if buttonName:find("^ActionButton") then buttonSpecificAction = "ACTIONBUTTON" .. buttonIndex
        elseif buttonName:find("^MultiBarBottomLeftButton") then buttonSpecificAction = "MULTIACTIONBAR1BUTTON" .. buttonIndex
        elseif buttonName:find("^MultiBarBottomRightButton") then buttonSpecificAction = "MULTIACTIONBAR2BUTTON" .. buttonIndex
        elseif buttonName:find("^MultiBarRightButton") then buttonSpecificAction = "MULTIACTIONBAR3BUTTON" .. buttonIndex
        elseif buttonName:find("^MultiBarLeftButton") then buttonSpecificAction = "MULTIACTIONBAR4BUTTON" .. buttonIndex
        elseif buttonName:find("^MultiBar5Button") then buttonSpecificAction = "MULTIACTIONBAR5BUTTON" .. buttonIndex
        elseif buttonName:find("^MultiBar6Button") then buttonSpecificAction = "MULTIACTIONBAR6BUTTON" .. buttonIndex
        elseif buttonName:find("^MultiBar7Button") then buttonSpecificAction = "MULTIACTIONBAR7BUTTON" .. buttonIndex
        elseif buttonName:find("^MultiBar8Button") then buttonSpecificAction = "MULTIACTIONBAR8BUTTON" .. buttonIndex
        end
    end

    if buttonSpecificAction ~= "" then
        addKey(GetBindingKey(buttonSpecificAction))
    end

    return keyBindings
end

-- Function to check the pressed key against the current action's keybinds
CheckBind = function(keyOrButton) 
    if not isRunning then return end
    -- Guard against currentActionButton being nil
    if not currentActionButton or not currentActionButton.keyBindings then 
        return
    end

    local function GetModifiedKey(key)
        local modKey = key
        if IsShiftKeyDown() then modKey = "SHIFT-" .. modKey end
        if IsControlKeyDown() then modKey = "CTRL-" .. modKey end
        if IsAltKeyDown() then modKey = "ALT-" .. modKey end
        return modKey
    end

    local pressedKey = GetModifiedKey(keyOrButton)
    -- DEFAULT_CHAT_FRAME:AddMessage("Key or button pressed: " .. pressedKey) -- Can be verbose
    
    local keyBindings = currentActionButton.keyBindings
    local expectedKeys = table.concat(keyBindings, " or ") -- More user-friendly list
    
    if #keyBindings == 0 then
        -- This path should ideally not be hit if StartGame filters actions without valid binds.
        DEFAULT_CHAT_FRAME:AddMessage("Error: No key bindings for current action: " .. currentActionButton.actionName)
        return
    end

    for _, keyBinding in ipairs(keyBindings) do
        -- DEFAULT_CHAT_FRAME:AddMessage("Checking key binding: " .. keyBinding) -- Can be verbose
        if pressedKey == keyBinding then
            local reactionTime = GetTime() - buttonStartTime  -- Use button start time here
            totalReactionTime = totalReactionTime + reactionTime
            buttonCount = buttonCount + 1
            DEFAULT_CHAT_FRAME:AddMessage("Correct! ("..currentActionButton.actionName..") Reaction time: " .. string.format("%.2f", reactionTime) .. " seconds.")

            -- Save the reaction time for this specific action (uniqueKey)
            if currentActionButton.uniqueKey then
                -- Ensure SavedVariables table structure exists
                if KBT_SavedData and KBT_SavedData.reactionTimes then
                    KBT_SavedData.reactionTimes[currentActionButton.uniqueKey] = reactionTime
                end
            end

            if iconFrame then iconFrame:Hide() end -- Hide the icon frame
            NextButton()     -- Test the next button
            return           -- Exit CheckBind as we found a match
        end
    end
    DEFAULT_CHAT_FRAME:AddMessage("Wrong key for "..currentActionButton.actionName.."! Expected: " .. expectedKeys .. ". Got: " .. pressedKey)
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
        local processedButton = string.upper(button) 
        if processedButton == "MIDDLEBUTTON" then
            processedButton = "BUTTON3"
        end
        -- DEFAULT_CHAT_FRAME:AddMessage("Mouse button pressed: " .. processedButton) -- Can be verbose
        CheckBind(processedButton)
    end
end)

-- Create a slash command to start the game
SLASH_KB1 = "/kb" -- Defines the slash command
SlashCmdList["KB"] = function() -- Associates the function with the command
    if isRunning then
        DEFAULT_CHAT_FRAME:AddMessage("KeybindsTrainer is already running. Use ESC to stop current session.")
    else
        DEFAULT_CHAT_FRAME:AddMessage("/kb command received. Starting new session.")
        StartGame()
    end
end

-- Register event for initial setup, like initializing SavedVariables
frame:RegisterEvent("PLAYER_LOGIN")
frame:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_LOGIN" then
        self:EnableKeyboard(false) -- Ensure our frame doesn't globally capture keyboard input unless isRunning
        UIParent:EnableMouse(false)  -- This addon doesn't need to control UIParent's mouse state globally at login
        
        -- Initialize SavedVariables
        if KBT_SavedData == nil then
            KBT_SavedData = {}
            DEFAULT_CHAT_FRAME:AddMessage("KeybindsTrainer: Initializing SavedVariables.")
        end
        if KBT_SavedData.reactionTimes == nil then
            KBT_SavedData.reactionTimes = {}
            DEFAULT_CHAT_FRAME:AddMessage("KeybindsTrainer: Initialized reaction time storage.")
        else
            local count = 0
            for _ in pairs(KBT_SavedData.reactionTimes) do count = count + 1 end
            DEFAULT_CHAT_FRAME:AddMessage("KeybindsTrainer: Loaded " .. count .. " stored reaction times.")
        end
    end
    -- No other event handling (like MOUSE_WHEEL_UP/DOWN) needed for this frame in this version
end)
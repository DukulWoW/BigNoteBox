-- BigNoteBox Core/Events.lua — Central event frame & dispatcher
-- One event frame for the entire addon instead of scattered frames per module.

local BNB = BigNoteBox

--------------------------------------------------------------------------------
-- EVENT BUS
-- Modules register callbacks via BNB.RegisterEvent(event, callback).
-- All events funnel through a single frame.
--------------------------------------------------------------------------------
local eventFrame = CreateFrame("Frame")
local handlers = {}

function BNB.RegisterEvent(event, callback)
    eventFrame:RegisterEvent(event)
    handlers[event] = handlers[event] or {}
    table.insert(handlers[event], callback)
end

function BNB.UnregisterEvent(event)
    eventFrame:UnregisterEvent(event)
end

eventFrame:SetScript("OnEvent", function(self, event, ...)
    for _, handler in ipairs(handlers[event] or {}) do
        handler(event, ...)
    end
end)

-- Expose for modules that need direct access
BNB.eventFrame = eventFrame

--------------------------------------------------------------------------------
-- ADDON_LOADED — early initialization gate
--------------------------------------------------------------------------------
BNB.RegisterEvent("ADDON_LOADED", function(event, addonName)
    if addonName == BNB.ADDON_NAME then
        -- DB init happens here so it's available before PLAYER_LOGIN
        BNB.InitializeDB()
        BNB._addonLoaded = true
    elseif addonName == "BigNoteBoxDB" then
        -- BigNoteBoxDB loaded after BigNoteBox (unusual but possible).
        -- Notes are now in memory — initialise them and clear the unavailable flag.
        BNB.InitNotesDB()
        BNB.MigrateNotesDB()
        BNB._notesAvailable = true
    end
end)

--------------------------------------------------------------------------------
-- PLAYER_LOGIN — main startup trigger
--------------------------------------------------------------------------------
BNB.RegisterEvent("PLAYER_LOGIN", function()
    -- Randomize skin preset on login/reload if enabled (before window creation)
    local db = BigNoteBoxDB
    if db and db.skinMode and db.skinRandomize then
        local keys = {}
        for k in pairs(BNB.SKIN_PRESETS or {}) do
            if k ~= (db.skinPreset or "obsidian") then
                keys[#keys + 1] = k
            end
        end
        if #keys > 0 then
            db.skinPreset = keys[math.random(#keys)]
        end
        -- Randomize brightness too if enabled, unless the new preset is OLED
        if db.skinRandomizeBrightness and db.skinPreset ~= "oled" then
            -- Pick a random brightness in the 0.5–2.0 range (avoids extremes)
            local MIN_BR, MAX_BR = 0.5, 2.0
            local steps = math.floor((MAX_BR - MIN_BR) / 0.05)
            db.skinBrightness = MIN_BR + math.random(0, steps) * 0.05
        end
    end

    -- Clear the transient "hide all stickies" flag unless the player has opted
    -- to keep stickies hidden persistently across sessions.
    C_Timer.After(0, function()
        local db = BigNoteBoxDB
        if db and db.stickiesHidden and not db.stickiesHiddenPersist then
            db.stickiesHidden = false
        end
    end)
    C_Timer.After(0.5, function()
        if BNB.Initialize then BNB.Initialize() end
        -- Show What's New popup if the user has updated since they last saw it.
        -- Suppressed during first-time setup so the wizard isn't interrupted.
        C_Timer.After(0.5, function()
            if BNB.WhatsNew and BNB.WhatsNew.CheckAndShow then
                local db = BigNoteBoxDB
                if not (db and db.setupComplete == true) then return end
                BNB.WhatsNew.CheckAndShow()
            end
        end)
        -- Show migration popup if any supported addon is detected and not dismissed.
        -- Suppressed during first-time setup so the wizard isn't interrupted.
        C_Timer.After(1.0, function()
            if BNB.Migration and BNB.Migration.ShowPopup then
                local db = BigNoteBoxDB
                if not (db and db.setupComplete == true) then return end
                local available = BNB.Migration.DetectAvailable()
                if available and #available > 0 then
                    BNB.Migration.ShowPopup()
                end
            end
        end)
    end)
end)

--------------------------------------------------------------------------------
-- PLAYER_ENTERING_WORLD — zone change detection (contextual surfacing)
--------------------------------------------------------------------------------
BNB.RegisterEvent("PLAYER_ENTERING_WORLD", function()
    if BNB.CheckContextualNotes then
        C_Timer.After(1, BNB.CheckContextualNotes)
    end
end)

--------------------------------------------------------------------------------
-- ZONE_CHANGED_NEW_AREA — major zone transitions
--------------------------------------------------------------------------------
BNB.RegisterEvent("ZONE_CHANGED_NEW_AREA", function()
    if BNB.CheckContextualNotes then
        C_Timer.After(0.5, BNB.CheckContextualNotes)
    end
end)

--------------------------------------------------------------------------------
-- ZONE_CHANGED — sub-zone transitions within the same zone
--------------------------------------------------------------------------------
BNB.RegisterEvent("ZONE_CHANGED", function()
    if BNB.CheckContextualNotes then
        C_Timer.After(0.5, BNB.CheckContextualNotes)
    end
end)

--------------------------------------------------------------------------------
-- ZONE_CHANGED_INDOORS — entering/leaving buildings (can change sub-zone)
--------------------------------------------------------------------------------
BNB.RegisterEvent("ZONE_CHANGED_INDOORS", function()
    if BNB.CheckContextualNotes then
        C_Timer.After(0.5, BNB.CheckContextualNotes)
    end
end)

--------------------------------------------------------------------------------
-- PLAYER_TARGET_CHANGED — target changed (player-context notes)
--------------------------------------------------------------------------------
BNB.RegisterEvent("PLAYER_TARGET_CHANGED", function()
    if BNB.CheckContextualNotes then
        C_Timer.After(0.1, BNB.CheckContextualNotes)
    end
end)

--------------------------------------------------------------------------------
-- PLAYER_REGEN_DISABLED — entered combat
--------------------------------------------------------------------------------
BNB.RegisterEvent("PLAYER_REGEN_DISABLED", function()
    local db = BigNoteBoxDB
    if not db then return end
    local action = db.combatAction or "nothing"

    -- If focus mode is open, exit it first so UIParent is restored before
    -- we apply any combat visibility changes.
    if BNB.IsFocusModeOpen and BNB.IsFocusModeOpen() then
        if BNB.CloseFocusMode then BNB.CloseFocusMode() end
    end

    if action == "nothing" then return end

    -- Record what we hid so we can restore it on leaving combat.
    BNB._combatHiddenMain     = false
    BNB._combatHiddenStickies = false

    -- Hide main window + all companion windows if they are open.
    if BNB.mainFrame and BNB.mainFrame:IsShown() then
        BNB.CloseCompanionWindows()
        BNB.mainFrame:Hide()
        BNB._combatHiddenMain = true
    end

    -- Handle sticky notes based on action.
    if action == "hide_all" then
        -- Hide stickies entirely
        if BNB.Sticky and BNB.Sticky.HideAll then
            BNB.Sticky.HideAll()
            BNB._combatHiddenStickies = true
        end
    elseif action == "hide_minimize" then
        -- Collapse open stickies to their icon tile
        if BNB.Sticky and BNB.Sticky.MinimizeAll then
            BNB.Sticky.MinimizeAll()
            BNB._combatMinimizedStickies = true
        end
    end
end)

--------------------------------------------------------------------------------
-- PLAYER_REGEN_ENABLED — left combat
--------------------------------------------------------------------------------
BNB.RegisterEvent("PLAYER_REGEN_ENABLED", function()
    -- Restore windows that were hidden when combat started.
    if BNB._combatHiddenMain and BNB.mainFrame then
        BNB.mainFrame:Show()
    end
    if BNB._combatHiddenStickies and BNB.Sticky and BNB.Sticky.ShowAll then
        BNB.Sticky.ShowAll()
    end
    if BNB._combatMinimizedStickies and BNB.Sticky and BNB.Sticky.UnminimizeAll then
        BNB.Sticky.UnminimizeAll()
    end
    BNB._combatHiddenMain         = false
    BNB._combatHiddenStickies     = false
    BNB._combatMinimizedStickies  = false
end)

-- BigNoteBox Core/Events.lua — Central event frame & dispatcher
-- One event frame for the entire addon instead of scattered frames per module.

local BNB = BigNoteBox
local L = BNB.L

--------------------------------------------------------------------------------
-- WoW: Forever beta notice (FOR-10). Blizzard fixed the SavedVariables loader on
-- 2026-09-25, so this is now a "still in development, keep backups" note with a
-- "Don't show this again" box (BigNoteBoxDB.foreverNoticeHidden). Its own window
-- rather than a StaticPopup, so the button is the new SharedButtonTemplate one.
--------------------------------------------------------------------------------
local _foreverNotice

-- Forever only, until "Don't show this again" is ticked, and never while the setup
-- wizard is still to be done: its Finish reloads (so the next login shows it) and
-- its Quit calls this directly (UI/SetupWizard.lua BNB_QUIT_SETUP).
function BNB.ShowForeverNoticeIfDue()
    local db = BigNoteBoxDB
    if not BNB.IsForever or not db then return end
    if db.foreverNoticeHidden or db.setupComplete ~= true then return end
    pcall(BNB.ShowForeverNotice)
end
function BNB.ShowForeverNotice()
    local f = _foreverNotice
    if not f then
        local W, PAD = 400, 20
        f = CreateFrame("Frame", "BNBForeverNoticeFrame", UIParent, "ButtonFrameTemplate")
        f:SetWidth(W)
        f:SetPoint("CENTER", UIParent, "CENTER", 0, 120)
        f:SetFrameStrata("DIALOG")
        f:SetToplevel(true)
        f:SetClampedToScreen(true)
        f:EnableMouse(true)
        f:SetMovable(true)
        f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", f.StartMoving)
        f:SetScript("OnDragStop", f.StopMovingOrSizing)
        ButtonFrameTemplate_HidePortrait(f)
        ButtonFrameTemplate_HideButtonBar(f)
        if f.Inset then f.Inset:Hide() end
        BNB.SeatChrome(f)
        BNB.AddForeverGlow(f, f.Bg)
        f:SetTitle(L["FOREVER_NOTICE_TITLE"])
        tinsert(UISpecialFrames, "BNBForeverNoticeFrame")

        local body = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        body:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, -40)
        body:SetWidth(W - PAD * 2)
        body:SetJustifyH("LEFT")
        body:SetSpacing(2)
        body:SetText(L["FOREVER_TEST_NOTICE"])

        local ok = CreateFrame("Button", nil, f, BNB.PanelButtonTemplate())
        ok:SetSize(120, 26)
        ok:SetPoint("BOTTOM", f, "BOTTOM", 0, 16)
        ok:SetText(L["OK"])
        ok:SetScript("OnClick", function() f:Hide() end)

        -- Report-a-bug links (ALL-73), under the text
        local bugs = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        bugs:SetPoint("TOPLEFT", body, "BOTTOMLEFT", 0, -16)
        bugs:SetWidth(W - PAD * 2)
        bugs:SetJustifyH("LEFT")
        bugs:SetText(L["FOREVER_NOTICE_BUGS"])
        local links = BNB.CreateBugLinkButtons(f, W - PAD * 2)
        links:SetPoint("TOPLEFT", bugs, "BOTTOMLEFT", 0, -8)

        -- Checkbox + label, centred as a group above the OK button
        local row = CreateFrame("Frame", nil, f)
        row:SetHeight(24)
        row:SetPoint("BOTTOM", ok, "TOP", 0, 8)
        local cb = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
        cb:SetSize(24, 24)
        cb:SetPoint("LEFT", row, "LEFT", 0, 0)
        local cbLabel = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        cbLabel:SetPoint("LEFT", cb, "RIGHT", 2, 0)
        cbLabel:SetText(L["FOREVER_NOTICE_DONT_SHOW"])
        row:SetWidth(24 + 2 + cbLabel:GetStringWidth())
        -- Label clicks toggle the box too
        local hit = CreateFrame("Button", nil, f)
        hit:SetPoint("TOPLEFT", cbLabel, "TOPLEFT", -2, 4)
        hit:SetPoint("BOTTOMRIGHT", cbLabel, "BOTTOMRIGHT", 2, -4)
        hit:SetScript("OnClick", function() cb:Click() end)

        -- The box is saved on close (OK, X or Escape), not on each click
        f:SetScript("OnHide", function()
            if BigNoteBoxDB then
                BigNoteBoxDB.foreverNoticeHidden = cb:GetChecked() and true or nil
            end
        end)
        -- Height from the wrapped text: title bar, body, bug line + links, checkbox
        -- row, button row. Set here, not in OnShow: the frame is created shown, so
        -- OnShow never fired and the template's default size stayed.
        f:SetHeight(40 + body:GetStringHeight() + 16 + bugs:GetStringHeight() + 8
            + BNB.BUG_LINKS_H + 16 + 24 + 8 + 26 + 16)
        f._cb = cb
        _foreverNotice = f
    end
    f._cb:SetChecked(false)
    f:Show()
    f:Raise()
end

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
        -- The Blizzard icon list loads at PLAYER_LOGIN from its own
        -- load-on-demand addon (UI/BlizzardIconList.lua, ALL-62)
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
        BNB.ShowForeverNoticeIfDue()
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

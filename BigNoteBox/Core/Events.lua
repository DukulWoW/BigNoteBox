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

-- Plunderstorm frame art from the game's own sheet (Interface\FrameGeneral\
-- UIFramePlunderstorm, 256x1024, file id 5607571; not shipped). Four corners with long
-- arms, a top and a bottom edge strip, a two-part crest for the top and an ornament
-- for the bottom. The sheet has no side strips: the sides are a plain stretch of the
-- corners' own vertical arms (a horizontal strip turned on its side is lit from the
-- wrong direction and never matched them). Every edge is one stretched slice from a
-- part of the art that does not change along its length, so there are no joints.
-- Pieces are {x0, x1, y0, y1} in sheet px; cx/cy is where the frame's outer corner
-- sits in a corner cell. Drawn at PS_SCALE (Dukul, 2026-09-27).
local PS_TEX, PS_W, PS_H = "Interface\\FrameGeneral\\UIFramePlunderstorm", 256, 1024
local PS_SCALE = 0.75
local PS_EDGE  = 21            -- edge thickness, sheet px
local PS_NUDGE = 0.5           -- left/bottom/right edges moved out by this, UI units
local PS_CORNERS = {
    TOPLEFT     = { 0, 168, 402, 568, cx = 5,   cy = 3 },
    TOPRIGHT    = { 0, 168, 570, 736, cx = 165, cy = 3 },
    BOTTOMLEFT  = { 0, 168,  64, 232, cx = 5,   cy = 164 },
    BOTTOMRIGHT = { 0, 168, 232, 400, cx = 165, cy = 164 },
}
local PS_TOP    = { 100, 156, 37, 58 }     -- outer side up
local PS_BOTTOM = { 100, 156,  7, 28 }     -- outer side down
local PS_LEFT   = {   5,  26, 548, 566 }   -- top-left arm; same rows as the bottom-left arm's top
local PS_RIGHT  = { 144, 165, 242, 254 }   -- bottom-right arm; matches the top-right arm's foot
local PS_CREST_L, PS_CREST_R = { 0, 119, 736, 794 }, { 119, 238, 736, 794 }
local PS_ORNAMENT = { 0, 122, 794, 841 }

-- inset = half a texel in, for pieces packed against another piece on the sheet
local function PSTex(f, p, sub, inset)
    local h = inset and 0.5 or 0
    local t = f:CreateTexture(nil, "BORDER", nil, sub or 0)
    t:SetTexture(PS_TEX)
    t:SetTexCoord((p[1] + h) / PS_W, (p[2] - h) / PS_W, (p[3] + h) / PS_H, (p[4] - h) / PS_H)
    t:SetSize((p[2] - p[1]) * PS_SCALE, (p[4] - p[3]) * PS_SCALE)
    return t
end

local function BuildPlunderChrome(f)
    local S, E = PS_SCALE, PS_EDGE * PS_SCALE
    -- The main window's Forever wood with its glow on top (UI/Chrome.lua)
    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetTexture(BNB.FOREVER_BG_TEXTURE, "REPEAT", "REPEAT")
    bg:SetHorizTile(true); bg:SetVertTile(true)
    bg:SetPoint("TOPLEFT", E / 2, -E / 2); bg:SetPoint("BOTTOMRIGHT", -E / 2, E / 2)
    BNB.AddForeverGlow(f, bg)

    -- Edges run the full side; the corners draw over their ends. Left, bottom and
    -- right sat PS_NUDGE inside the corner arms in game, so they move out by that
    -- (Dukul, 2026-09-27); the top lined up as it was.
    local N = PS_NUDGE
    local top, bottom = PSTex(f, PS_TOP), PSTex(f, PS_BOTTOM)
    top:SetPoint("TOPLEFT");                    top:SetPoint("TOPRIGHT")
    bottom:SetPoint("BOTTOMLEFT", 0, -N);       bottom:SetPoint("BOTTOMRIGHT", 0, -N)
    local left, right = PSTex(f, PS_LEFT), PSTex(f, PS_RIGHT)
    left:SetPoint("TOPLEFT", -N, 0);            left:SetPoint("BOTTOMLEFT", -N, 0)
    right:SetPoint("TOPRIGHT", N, 0);           right:SetPoint("BOTTOMRIGHT", N, 0)

    for point, c in pairs(PS_CORNERS) do
        local t = PSTex(f, c, 2, true)
        local ox = point:find("LEFT") and -c.cx * S or (c[2] - c[1] - c.cx) * S
        local oy = point:find("TOP")  and  c.cy * S or -((c[4] - c[3]) - c.cy) * S
        t:SetPoint(point, f, point, ox, oy)
    end

    -- Crest: its base rests on the top edge's inner line; ornament over the bottom edge
    local cl, cr = PSTex(f, PS_CREST_L, 4, true), PSTex(f, PS_CREST_R, 4, true)
    cl:SetPoint("BOTTOMRIGHT", f, "TOP", 0, -E)
    cr:SetPoint("BOTTOMLEFT",  f, "TOP", 0, -E)
    local orn = PSTex(f, PS_ORNAMENT, 4, true)
    orn:SetPoint("TOP", f, "BOTTOM", 0, E + 3 * S)
end

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
        local W, PAD, TOP = 420, 30, 58
        f = CreateFrame("Frame", "BNBForeverNoticeFrame", UIParent)
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
        BNB.SetMoveCursor(f)
        tinsert(UISpecialFrames, "BNBForeverNoticeFrame")
        -- ESC by hand as well: UISpecialFrames alone does not close a standalone
        -- window on Forever (see the Reference Box)
        BNB.AttachEscClose(f, f.Hide)

        local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        title:SetPoint("TOP", f, "TOP", 0, -26)
        title:SetText(L["FOREVER_NOTICE_TITLE"])
        local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
        close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -14, -14)
        close:SetFrameLevel(f:GetFrameLevel() + 5)   -- above the corner art

        local body = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        body:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, -TOP)
        body:SetWidth(W - PAD * 2)
        body:SetJustifyH("LEFT")
        body:SetSpacing(2)
        body:SetText(L["FOREVER_TEST_NOTICE"])

        local ok = CreateFrame("Button", nil, f, BNB.PanelButtonTemplate())
        ok:SetSize(120, 26)
        ok:SetPoint("BOTTOM", f, "BOTTOM", 0, 28)
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
        f:SetHeight(TOP + body:GetStringHeight() + 16 + bugs:GetStringHeight() + 8
            + BNB.BUG_LINKS_H + 16 + 24 + 8 + 26 + 28)
        BuildPlunderChrome(f)
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
-- Shared events funnel through this one frame. Some modules still keep their
-- own event frame for events only they use (Focus mode, setup wizard,
-- Reference Box, Direct Send...); that is fine, the bus is not exclusive.
-- Each handler runs through securecallfunction: an error is reported
-- (BugSack / scriptErrors) and the remaining handlers still run. At
-- PLAYER_LOGOUT that chain is note save, sticky inline-edit save, then history
-- snapshots, so one failure must not cost the rest (ARCH-01).
--------------------------------------------------------------------------------
local eventFrame = CreateFrame("Frame")
local handlers = {}

function BNB.RegisterEvent(event, callback)
    eventFrame:RegisterEvent(event)
    handlers[event] = handlers[event] or {}
    table.insert(handlers[event], callback)
end

-- Removes one handler; the frame event is unregistered only when none are
-- left. The list is replaced, not edited in place, so an OnEvent loop that is
-- running over the old list is not disturbed.
function BNB.UnregisterEvent(event, callback)
    local list = handlers[event]
    if not list then return end
    local kept = {}
    for _, h in ipairs(list) do
        if h ~= callback then kept[#kept + 1] = h end
    end
    if #kept == 0 then
        handlers[event] = nil
        eventFrame:UnregisterEvent(event)
    else
        handlers[event] = kept
    end
end

eventFrame:SetScript("OnEvent", function(self, event, ...)
    local list = handlers[event]
    if not list then return end
    for i = 1, #list do
        securecallfunction(list[i], event, ...)
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
-- Situation checks (contextual surfacing). Every event below asks for one
-- check through ScheduleContextCheck, which keeps a single pending check
-- (PERF-05): a zone change fires two or three of these events, and each ran
-- its own full check. A request never makes a pending check run sooner, so the
-- zone events keep their settle time when a target change lands in between.
--------------------------------------------------------------------------------
local CONTEXT_CHECK_KEY = "contextCheck"
local _contextCheckAt   = nil   -- GetTime() of the pending check
local function RunContextCheck()
    _contextCheckAt = nil
    if BNB.CheckContextualNotes then BNB.CheckContextualNotes() end
end
local function ScheduleContextCheck(delay)
    if not BNB.CheckContextualNotes then return end
    local at = GetTime() + delay
    if _contextCheckAt and _contextCheckAt > at then at = _contextCheckAt end
    _contextCheckAt = at
    BNB.Debounce(CONTEXT_CHECK_KEY, at - GetTime(), RunContextCheck)
end

-- Target and group changes only matter to player situations
local function PlayerContextsInUse()
    return not BNB.HasPlayerContexts or BNB.HasPlayerContexts()
end

--------------------------------------------------------------------------------
-- PLAYER_ENTERING_WORLD — zone change detection (contextual surfacing)
--------------------------------------------------------------------------------
BNB.RegisterEvent("PLAYER_ENTERING_WORLD", function()
    ScheduleContextCheck(1)
end)

--------------------------------------------------------------------------------
-- ZONE_CHANGED_NEW_AREA — major zone transitions
--------------------------------------------------------------------------------
BNB.RegisterEvent("ZONE_CHANGED_NEW_AREA", function()
    ScheduleContextCheck(0.5)
end)

--------------------------------------------------------------------------------
-- ZONE_CHANGED — sub-zone transitions within the same zone
--------------------------------------------------------------------------------
BNB.RegisterEvent("ZONE_CHANGED", function()
    ScheduleContextCheck(0.5)
end)

--------------------------------------------------------------------------------
-- ZONE_CHANGED_INDOORS — entering/leaving buildings (can change sub-zone)
--------------------------------------------------------------------------------
BNB.RegisterEvent("ZONE_CHANGED_INDOORS", function()
    ScheduleContextCheck(0.5)
end)

--------------------------------------------------------------------------------
-- PLAYER_TARGET_CHANGED — target changed (player-context notes). Tab-targeting
-- keeps moving the check out, so it runs once the target settles.
--------------------------------------------------------------------------------
BNB.RegisterEvent("PLAYER_TARGET_CHANGED", function()
    if PlayerContextsInUse() then ScheduleContextCheck(0.1) end
end)

--------------------------------------------------------------------------------
-- GROUP_ROSTER_UPDATE — someone joined or left (player situations match group
-- members, BUG-25). Fires in bursts in a raid, so one check per second at most.
--------------------------------------------------------------------------------
local _rosterCheckPending = false
BNB.RegisterEvent("GROUP_ROSTER_UPDATE", function()
    if _rosterCheckPending or not BNB.CheckContextualNotes then return end
    if not PlayerContextsInUse() then return end
    _rosterCheckPending = true
    C_Timer.After(1, function()
        _rosterCheckPending = false
        ScheduleContextCheck(0)
    end)
end)

--------------------------------------------------------------------------------
-- PLAYER_REGEN_DISABLED — entered combat
--------------------------------------------------------------------------------
BNB.RegisterEvent("PLAYER_REGEN_DISABLED", function()
    local db = BigNoteBoxDB
    if not db then return end
    local action = db.combatAction or BNB.DEFAULTS.combatAction

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
        -- _skipConfirm: with "Confirm before closing" on, OnHide would re-show
        -- the window and open the confirm popup in combat (BUG-20)
        BNB.mainFrame._skipConfirm = true
        BNB.mainFrame:Hide()
        BNB.mainFrame._skipConfirm = false
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

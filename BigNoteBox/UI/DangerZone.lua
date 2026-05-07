-- BigNoteBox UI/DangerZone.lua
--
-- Standalone "Danger Zone" window containing all destructive reset operations.
-- Opened from the Advanced tab in Settings via a single "Danger Zone!" button.
-- Always uses a red-tinted skin regardless of normal/skin mode setting.
--
-- PUBLIC API:
--   BNB.DangerZone.Open()
--   BNB.DangerZone.Close()
--
-- WINDOW:
--   420x440px (matches Migration window size)
--   Scrollable content area, fixed Close button at the bottom
--   Red backdrop skin hardcoded — bypasses preset system
--   PixelGlow around the frame border (settings at top of file)
--   ESC closes it (OnKeyDown handler, not UISpecialFrames)
--
-- CONTENTS:
--   1. Reset Settings         — wipes BigNoteBoxDB, reloads
--   2. Empty Trash            — hard-deletes all trashed notes
--   3. Clear All History      — wipes all auto-snapshots from every note
--   4. Clear Manual Restore Points — removes note.manualSnapshot from all notes
--   5. Reset Sticky Layouts   — wipes db.postits (per-note sticky config)
--   6. Clear Migration History — resets migrationDone/migrationDeclined
--   7. Remove All Characters  — clears db.knownChars
--   8. Delete All Notes       — wipes BigNoteBoxNotesDB.notes
--   9. Factory Reset          — wipes everything, reloads

local BNB = BigNoteBox
BNB.DangerZone = BNB.DangerZone or {}
local DZ = BNB.DangerZone

-- ── Glow constants (edit here to tune) ───────────────────────────────────────
local GLOW_KEY   = "bnb_dangerzone"
local GLOW_COLOR = { 0.9, 0.15, 0.15, 1.0 }  -- red
local GLOW_LINES = 30
local GLOW_FREQ  = 0.05
local GLOW_LEN   = 20

-- ── Layout constants ──────────────────────────────────────────────────────────
local WIN_W    = 420
local WIN_H    = 440
local PAD      = 16
local CW       = WIN_W - PAD * 2 - 20   -- content width (accounts for scrollbar)
local TITLE_H  = 28
local CLOSE_H  = 36                      -- fixed close button area height
local SEC_GAP  = 14                      -- gap between sections

-- ── Red skin colors ───────────────────────────────────────────────────────────
local RED_BG_R,  RED_BG_G,  RED_BG_B,  RED_BG_A  = 0.14, 0.03, 0.03, 0.97
local RED_BD_R,  RED_BD_G,  RED_BD_B,  RED_BD_A  = 0.65, 0.10, 0.10, 1.00
local RED_STRIP_R, RED_STRIP_G, RED_STRIP_B       = 0.20, 0.04, 0.04

-- ── Module state ──────────────────────────────────────────────────────────────
local _frame   = nil
local _overlay = nil
local _LCG     = nil

local function GetLCG()
    if not _LCG then
        _LCG = LibStub and LibStub("LibCustomGlow-1.0", true)
    end
    return _LCG
end

local function StartGlow(f)
    local lcg = GetLCG()
    if lcg and f then
        pcall(lcg.PixelGlow_Start, f, GLOW_COLOR, GLOW_LINES, GLOW_FREQ, GLOW_LEN,
              nil, nil, nil, nil, GLOW_KEY)
    end
end

local function StopGlow(f)
    local lcg = GetLCG()
    if lcg and f then
        pcall(lcg.PixelGlow_Stop, f, GLOW_KEY)
    end
end

-- ── Overlay ───────────────────────────────────────────────────────────────────
local function GetOverlay()
    if _overlay then return _overlay end
    local ov = CreateFrame("Frame", nil, UIParent)
    ov:SetAllPoints()
    ov:SetFrameStrata("DIALOG")
    ov:SetFrameLevel(1)
    ov:EnableMouse(false)
    local tex = ov:CreateTexture(nil, "BACKGROUND")
    tex:SetAllPoints()
    tex:SetColorTexture(0.4, 0.0, 0.0, 0.55)
    ov:Hide()
    _overlay = ov
    return ov
end

local function ShowOverlay() GetOverlay():Show() end
local function HideOverlay() if _overlay then _overlay:Hide() end end

-- ── Red button factory ────────────────────────────────────────────────────────
-- Bypasses BNB.CreateButton / CreateSkinButton so the buttons are always
-- red regardless of skin mode or preset. Matches the window's red palette.
local RED_BTN_R,  RED_BTN_G,  RED_BTN_B  = 0.28, 0.05, 0.05   -- base fill
local RED_BTN_BR, RED_BTN_BG, RED_BTN_BB = 0.65, 0.10, 0.10   -- border

local function MakeRedButton(parent, text, w, h)
    local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
    btn:SetSize(w or 80, h or 24)
    BNB.SetBackdrop(btn,
        RED_BTN_R, RED_BTN_G, RED_BTN_B, 0.95,
        RED_BTN_BR, RED_BTN_BG, RED_BTN_BB, 1)

    local hl = btn:CreateTexture(nil, "HIGHLIGHT")
    hl:SetPoint("TOPLEFT",     btn, "TOPLEFT",     2, -2)
    hl:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -2,  2)
    hl:SetColorTexture(1, 1, 1, 0.08)

    btn:SetScript("OnMouseDown", function(self)
        if self.SetBackdropColor then
            self:SetBackdropColor(RED_BTN_R * 0.65, RED_BTN_G * 0.65, RED_BTN_B * 0.65, 0.98)
        end
    end)
    btn:SetScript("OnMouseUp", function(self)
        if self.SetBackdropColor then
            self:SetBackdropColor(RED_BTN_R, RED_BTN_G, RED_BTN_B, 0.95)
        end
    end)

    local lbl = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    lbl:SetAllPoints()
    lbl:SetJustifyH("CENTER")
    lbl:SetJustifyV("MIDDLE")
    lbl:SetTextColor(1, 0.65, 0.65)
    lbl:SetText(text or "")

    function btn:SetText(t) lbl:SetText(t or "") end
    function btn:GetText()  return lbl:GetText() end
    function btn:GetFontString() return lbl end

    return btn
end

-- ── Double-confirm helper ─────────────────────────────────────────────────────
-- Identical to the pattern used in the old BuildResetContent.
-- Button text counts down then auto-hides after AUTO_HIDE_SECS.
local function ArmConfirm(confirmBtn, onConfirm)
    local LOCK_SECS      = 5
    local AUTO_HIDE_SECS = 5
    local originalText   = confirmBtn:GetText() or "CONFIRM"

    confirmBtn:SetEnabled(false)
    confirmBtn:SetAlpha(0.55)
    confirmBtn:Show()

    local remaining = LOCK_SECS
    local tickTimer = nil

    local function UpdateLabel()
        if remaining > 0 then
            confirmBtn:SetText(originalText .. " (" .. remaining .. ")")
        else
            confirmBtn:SetText(originalText)
        end
    end
    UpdateLabel()

    local function Tick()
        remaining = remaining - 1
        UpdateLabel()
        if remaining <= 0 then
            if tickTimer then tickTimer:Cancel(); tickTimer = nil end
            confirmBtn:SetEnabled(true)
            confirmBtn:SetAlpha(1.0)
            local hideTimer = C_Timer.NewTimer(AUTO_HIDE_SECS, function()
                confirmBtn:Hide()
                confirmBtn:SetEnabled(false)
                confirmBtn:SetAlpha(0.55)
                confirmBtn:SetText(originalText)
            end)
            confirmBtn:SetScript("OnClick", function()
                hideTimer:Cancel()
                confirmBtn:Hide()
                confirmBtn:SetEnabled(false)
                confirmBtn:SetAlpha(0.55)
                confirmBtn:SetText(originalText)
                onConfirm()
            end)
        end
    end
    tickTimer = C_Timer.NewTicker(1, Tick, LOCK_SECS)
    confirmBtn:SetScript("OnClick", function() end)
end

-- ── Content builder helpers ───────────────────────────────────────────────────
local function MakeHeader(ct, y, text)
    local lbl = ct:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    lbl:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
    lbl:SetTextColor(1, 0.35, 0.35)
    lbl:SetText(text)
    return y - 22
end

local function MakeDesc(ct, y, text)
    local lbl = ct:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    lbl:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
    lbl:SetWidth(CW); lbl:SetJustifyH("LEFT"); lbl:SetWordWrap(true)
    lbl:SetTextColor(0.75, 0.60, 0.60)
    lbl:SetText(text)
    lbl:SetHeight(lbl:GetStringHeight() + 4)
    local h = lbl:GetStringHeight() + 4
    lbl:SetHeight(h)
    return y - h - 4
end

local function MakeRule(ct, y)
    local t = ct:CreateTexture(nil, "ARTWORK")
    t:SetHeight(1)
    t:SetColorTexture(0.45, 0.10, 0.10, 1)
    t:SetPoint("TOPLEFT",  ct, "TOPLEFT",  0, y)
    t:SetPoint("TOPRIGHT", ct, "TOPRIGHT", 0, y)
    return y - 10
end

local function MakeActionRow(ct, y, btnLabel, btnW, confirmLabel, confirmW, onConfirm)
    local btn = MakeRedButton(ct, btnLabel, btnW, 24)
    btn:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)

    local confirmBtn = MakeRedButton(ct, confirmLabel, confirmW, 24)
    confirmBtn:SetPoint("LEFT", btn, "RIGHT", 8, 0)
    confirmBtn:Hide()

    btn:SetScript("OnClick", function()
        ArmConfirm(confirmBtn, onConfirm)
    end)

    return y - 32, btn, confirmBtn
end

-- ── Populate scroll content ───────────────────────────────────────────────────
local function PopulateContent(ct, sf)
    local y = -PAD

    -- ── 0. Run Setup Again ───────────────────────────────────────────────────
    -- Safe action — resets only the setup completion flag, not notes or settings.
    y = MakeHeader(ct, y, "Setup Wizard")
    y = MakeDesc(ct, y,
        "Re-run the first-time setup wizard. |cff66bb6aYour notes and settings are not affected.|r "..
        "The UI will reload.")
    local runSetupBtn = CreateFrame("Button", nil, ct, "UIPanelButtonTemplate")
    runSetupBtn:SetSize(180, 26)
    runSetupBtn:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
    runSetupBtn:SetText("Run Setup Again...")
    runSetupBtn:SetScript("OnClick", function()
        StaticPopup_Show("BNB_RUN_SETUP_AGAIN")
    end)

    if not StaticPopupDialogs["BNB_RUN_SETUP_AGAIN"] then
        StaticPopupDialogs["BNB_RUN_SETUP_AGAIN"] = {
            text    = "Setup wizard will open on your next login.\n\nReload now?",
            button1 = "Reload",
            button2 = "Later",
            timeout = 0, whileDead = true, hideOnEscape = true,
            OnAccept = function()
                local db = BigNoteBoxDB
                if db then
                    db.setupComplete = false
                    db.setupPage     = nil
                end
                C_UI.Reload()
            end,
        }
    end
    y = y - 34
    y = y - SEC_GAP

    -- ── 1. Reset Settings ────────────────────────────────────────────────────
    y = MakeHeader(ct, y, "Reset Settings")
    y = MakeDesc(ct, y,
        "Resets all settings to defaults. |cff66bb6aYour notes are not affected.|r "..
        "The UI will reload.")
    y, _, _ = MakeActionRow(ct, y,
        "Reset Settings...", 140,
        "|cffff4444CONFIRM - reset|r", 160,
        function()
            BigNoteBoxDB = nil
            C_UI.Reload()
        end)
    y = y - SEC_GAP

    -- ── 2. Empty Trash ───────────────────────────────────────────────────────
    y = MakeRule(ct, y); y = y - 8
    y = MakeHeader(ct, y, "Empty Trash")
    y = MakeDesc(ct, y,
        "Permanently hard-deletes all notes currently in the trash. "..
        "|cffff4444There is no undo.|r Notes deleted this way cannot be recovered.")
    y, _, _ = MakeActionRow(ct, y,
        "Empty Trash...", 130,
        "|cffff4444CONFIRM - empty|r", 160,
        function()
            if BNB.EmptyTrash then BNB.EmptyTrash() end
            BNB:Print("|cffff9900Trash emptied.|r")
        end)
    y = y - SEC_GAP

    -- ── 3. Clear All Session History ─────────────────────────────────────────
    y = MakeRule(ct, y); y = y - 8
    y = MakeHeader(ct, y, "Clear All Session History")
    y = MakeDesc(ct, y,
        "Removes all auto-snapshots from every note. Manual restore points are "..
        "not affected. New snapshots will be created on your next edit session.")
    y, _, _ = MakeActionRow(ct, y,
        "Clear History...", 140,
        "|cffff4444CONFIRM - clear|r", 160,
        function()
            local ndb = BigNoteBoxNotesDB
            if ndb and ndb.notes then
                local count = 0
                for _, note in pairs(ndb.notes) do
                    if note.history then
                        note.history = nil
                        count = count + 1
                    end
                end
                BNB:Print(string.format(
                    "|cffff9900Auto-snapshots cleared from %d note(s).|r", count))
            end
            if BNB.RefreshHistoryWindow    then BNB.RefreshHistoryWindow()    end
            if BNB.RefreshNoteHistoryPanel then BNB.RefreshNoteHistoryPanel() end
            if BNB.SyncHistoryBtnState     then BNB.SyncHistoryBtnState()     end
        end)
    y = y - SEC_GAP

    -- ── 4. Clear Manual Restore Points ───────────────────────────────────────
    y = MakeRule(ct, y); y = y - 8
    y = MakeHeader(ct, y, "Clear Manual Restore Points")
    y = MakeDesc(ct, y,
        "Removes all manually saved restore points from every note. "..
        "Auto-snapshots are not affected. |cffff4444There is no undo.|r")
    y, _, _ = MakeActionRow(ct, y,
        "Clear Restore Points...", 180,
        "|cffff4444CONFIRM - clear|r", 160,
        function()
            local ndb = BigNoteBoxNotesDB
            if ndb and ndb.notes then
                local count = 0
                for _, note in pairs(ndb.notes) do
                    if note.manualSnapshot then
                        note.manualSnapshot = nil
                        count = count + 1
                    end
                end
                BNB:Print(string.format(
                    "|cffff9900%d manual restore point(s) cleared.|r", count))
            end
            if BNB.SyncHistoryBtnState     then BNB.SyncHistoryBtnState()     end
            if BNB.SyncHistoryNoteBtnState then BNB.SyncHistoryNoteBtnState() end
            if BNB.RefreshHistoryWindow    then BNB.RefreshHistoryWindow()    end
            if BNB.RefreshNoteHistoryPanel then BNB.RefreshNoteHistoryPanel() end
        end)
    y = y - SEC_GAP

    -- ── 5. Reset Sticky Note Layouts ─────────────────────────────────────────
    y = MakeRule(ct, y); y = y - 8
    y = MakeHeader(ct, y, "Reset Sticky Note Layouts")
    y = MakeDesc(ct, y,
        "Resets all per-note sticky settings to defaults: font, size, color, "..
        "text alignment, outline, and position. Note content is not affected.")
    y, _, _ = MakeActionRow(ct, y,
        "Reset Sticky Layouts...", 180,
        "|cffff4444CONFIRM - reset|r", 160,
        function()
            if BigNoteBoxDB then
                BigNoteBoxDB.postits = {}
            end
            BNB:Print("|cffff9900Sticky note layouts reset to defaults.|r")
            -- Close any open sticky notes so they rebuild cleanly
            if BNB._stickyFrames then
                for _, f in pairs(BNB._stickyFrames) do
                    if f and f:IsShown() then f:Hide() end
                end
            end
        end)
    y = y - SEC_GAP

    -- ── 6. Clear Migration History ───────────────────────────────────────────
    y = MakeRule(ct, y); y = y - 8
    y = MakeHeader(ct, y, "Clear Migration History")
    y = MakeDesc(ct, y,
        "Resets all migration records. The migration popup will appear again on "..
        "next login if supported addons are detected. Use this to re-run a "..
        "migration you want to redo.")
    y, _, _ = MakeActionRow(ct, y,
        "Clear Migration History...", 200,
        "|cffff4444CONFIRM - clear|r", 160,
        function()
            local db = BigNoteBoxDB
            if db then
                db.migrationDone     = {}
                db.migrationDeclined = {}
            end
            BNB:Print("|cffff9900Migration history cleared. Reloading...|r")
            C_Timer.After(0.5, function()
                C_UI.Reload()
            end)
        end)
    y = y - SEC_GAP

    -- ── 7. Remove All Characters ─────────────────────────────────────────────
    y = MakeRule(ct, y); y = y - 8
    y = MakeHeader(ct, y, "Remove All Characters")
    y = MakeDesc(ct, y,
        "Clears all characters from the known characters list used for note "..
        "scope autocomplete. Your current character is re-added automatically. "..
        "Notes are not affected.")
    y, _, _ = MakeActionRow(ct, y,
        "Remove All Characters...", 200,
        "|cffff4444CONFIRM - remove|r", 160,
        function()
            local db = BigNoteBoxDB
            if db and db.knownChars then
                db.knownChars = {}
                if BNB.currentChar then
                    local name  = UnitName("player") or "Unknown"
                    local realm = GetNormalizedRealmName() or "Unknown"
                    local _, cls = UnitClass("player")
                    db.knownChars[BNB.currentChar] = {
                        name = name, realm = realm,
                        class = cls or "WARRIOR", lastSeen = time(),
                    }
                end
            end
            BNB:Print("|cffff9900Known characters cleared.|r")
        end)
    y = y - SEC_GAP

    -- ── 8. Delete All Notes ──────────────────────────────────────────────────
    y = MakeRule(ct, y); y = y - 8
    y = MakeHeader(ct, y, "Delete All Notes")
    y = MakeDesc(ct, y,
        "|cffff4444WARNING:|r Permanently deletes every note. "..
        "|cffff4444There is no undo.|r You will confirm twice.")
    y, _, _ = MakeActionRow(ct, y,
        "Delete All Notes...", 160,
        "|cffff4444CONFIRM - delete everything|r", 220,
        function()
            BigNoteBoxNotesDB.notes     = {}
            BigNoteBoxNotesDB.noteOrder = {}
            BNB._currentNoteID = nil
            if BigNoteBoxDB then BigNoteBoxDB.selectedNoteID = nil end
            if BNB.RefreshNoteList  then BNB.RefreshNoteList() end
            if BNB.LoadNoteInEditor then BNB.LoadNoteInEditor(nil) end
            BNB:Print("|cffff4444All notes deleted.|r")
        end)
    y = y - SEC_GAP

    -- ── 9. Factory Reset ─────────────────────────────────────────────────────
    y = MakeRule(ct, y); y = y - 8
    y = MakeHeader(ct, y, "Factory Reset")
    y = MakeDesc(ct, y,
        "|cffff4444WARNING:|r Wipes |cffff4444everything|r — all notes, all settings, "..
        "all characters. The addon will be in a completely fresh state after "..
        "reload. |cffff4444There is absolutely no undo.|r You will confirm twice.")
    y, _, _ = MakeActionRow(ct, y,
        "Factory Reset...", 140,
        "|cffff2222CONFIRM - wipe everything|r", 220,
        function()
            BigNoteBoxNotesDB = {}
            BigNoteBoxDB      = {}
            BNB:Print("|cffff2222Factory reset complete. Reloading UI...|r")
            C_Timer.After(0.5, function()
                C_UI.Reload()
            end)
        end)
    y = y - PAD

    -- Finalise scroll child height
    local contentH = math.abs(y)
    ct:SetHeight(math.max(contentH, sf:GetHeight()))

    -- Show/hide scrollbar
    local bar = sf.ScrollBar
    C_Timer.After(0.05, function()
        local sfH = sf:GetHeight()
        ct:SetHeight(math.max(contentH, sfH))
        if bar then
            bar:SetAlpha(contentH > sfH + 2 and 1 or 0)
        end
    end)
end

-- ── Build the window (lazily, once) ──────────────────────────────────────────
local function BuildWindow()
    if _frame then return _frame end

    local f = BNB.CreateBackdropFrame("Frame", "BigNoteBoxDangerZoneFrame", UIParent)
    BNB.SetBackdrop(f,
        RED_BG_R, RED_BG_G, RED_BG_B, RED_BG_A,
        RED_BD_R, RED_BD_G, RED_BD_B, RED_BD_A)
    f:SetFrameStrata("DIALOG")
    f:SetToplevel(true)
    f:SetSize(WIN_W, WIN_H)
    f:SetPoint("CENTER")
    f:SetMovable(true)
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) self:StartMoving() end)
    f:SetScript("OnDragStop",  function(self) self:StopMovingOrSizing() end)

    -- Title bar strip
    local titleBar = CreateFrame("Frame", nil, f)
    titleBar:SetPoint("TOPLEFT",  f, "TOPLEFT",  4, -4)
    titleBar:SetPoint("TOPRIGHT", f, "TOPRIGHT", -4, -4)
    titleBar:SetHeight(TITLE_H)
    titleBar:EnableMouse(true)
    titleBar:RegisterForDrag("LeftButton")
    titleBar:SetScript("OnDragStart", function() f:StartMoving() end)
    titleBar:SetScript("OnDragStop",  function() f:StopMovingOrSizing() end)

    local titleTex = titleBar:CreateTexture(nil, "BACKGROUND")
    titleTex:SetAllPoints()
    titleTex:SetColorTexture(RED_STRIP_R, RED_STRIP_G, RED_STRIP_B, 1)

    local titleLbl = titleBar:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    titleLbl:SetPoint("CENTER", titleBar, "CENTER", 0, 0)
    titleLbl:SetTextColor(1, 0.30, 0.30)
    titleLbl:SetText("!! Danger Zone !!")

    -- X close button in title bar
    local xBtn = CreateFrame("Button", nil, titleBar, "UIPanelCloseButton")
    xBtn:SetSize(28, 28)
    xBtn:SetPoint("RIGHT", titleBar, "RIGHT", 2, 0)
    xBtn:SetScript("OnClick", function() DZ.Close() end)

    -- Scroll area between title bar and close button
    local sf = CreateFrame("ScrollFrame", nil, f, "ScrollFrameTemplate")
    sf:SetPoint("TOPLEFT",     f, "TOPLEFT",   PAD, -(4 + TITLE_H + 8))
    sf:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -(PAD + 20), CLOSE_H + PAD)

    local bar = sf.ScrollBar
    if bar then bar:SetAlpha(0) end

    local ct = CreateFrame("Frame", nil, sf)
    ct:SetWidth(CW)
    ct:SetHeight(1)
    sf:SetScrollChild(ct)

    -- Fixed close button anchored to the bottom of the window
    local closeBtn = MakeRedButton(f, "Close", WIN_W - PAD * 2, 26)
    closeBtn:SetPoint("BOTTOM", f, "BOTTOM", 0, PAD - 2)
    closeBtn:SetScript("OnClick", function() DZ.Close() end)

    -- ESC: handle via OnKeyDown so DZ.Close() runs (cleans up overlay + glow).
    -- Do NOT use UISpecialFrames — it calls Hide() directly, bypassing DZ.Close().
    f:EnableKeyboard(true)
    f:SetScript("OnKeyDown", function(self, key)
        if key ~= "ESCAPE" then self:SetPropagateKeyboardInput(true); return end
        self:SetPropagateKeyboardInput(false)
        DZ.Close()
    end)

    f._sf = sf
    f._ct = ct

    PopulateContent(ct, sf)

    f:Hide()
    _frame = f
    return f
end

-- ── Public: Open ─────────────────────────────────────────────────────────────
function DZ.Open()
    local f = BuildWindow()
    ShowOverlay()
    f:Show()
    f:Raise()
    StartGlow(f)
end

-- ── Public: Close ─────────────────────────────────────────────────────────────
function DZ.Close()
    HideOverlay()
    if _frame then
        StopGlow(_frame)
        _frame:Hide()
    end
end

-- BigNoteBox UI/DebugWindow.lua
--
-- Standalone Developer / debug tools window (ALL-30). Opened from the Advanced tab
-- in Settings and by /bnb debug. Replaces the inline Developer section.
--
-- PUBLIC API:
--   BNB.DebugWindow.Open()
--   BNB.DebugWindow.Close()
--   BNB.DebugWindow.Toggle()
--
-- BEHAVIOUR (Dukul, 2026-09-24):
--   * The window holds the master "Activate Debug mode" checkbox itself, so the
--     Advanced button needs no gate. The state is re-read from the DB on every
--     show: debugMode is cleared on each reload (Core/Database.lua).
--   * Checkboxes are staged. OK commits and closes, Cancel discards, Reload commits
--     and reloads (pseudo-locale and seeded data only fully apply after a reload).
--   * One-shot tool buttons (toast, wizard, seed data) act at once, but only while
--     the staged master checkbox is on.
--   * A warning paragraph is always visible at the top.
--   Normal mode: ButtonFrameTemplate. Skin mode: a skin frame with its own title
--   strip, like UI/ToolWindow.lua (ALL-79, Dukul 2026-09-26).

local BNB = BigNoteBox
local L = BNB.L
BNB.DebugWindow = BNB.DebugWindow or {}
local DW = BNB.DebugWindow

local SK_TITLE_H   = 28   -- skin title strip height
local WIN_W, WIN_H = 400, 430
local PAD          = 20
local ROW_H        = 26
local SUB_INDENT   = 20

local _frame

-- Staged values, refreshed from the DB on every show.
local staged = {}

local function Commit()
    local db = BigNoteBoxDB
    if not db then return end

    db.debugMode = staged.master and true or nil
    BNB._debugMode = db.debugMode
    if not db.debugMode then
        -- Sub-options are meaningless with the master off (same as the old inline section)
        staged.wp, staged.pseudo, staged.imm = false, false, false
        db.debugWaypoint = nil; BNB._debugWaypoint = nil
    else
        db.debugWaypoint = staged.wp and true or nil
        BNB._debugWaypoint = db.debugWaypoint
    end
    db.debugPseudoLocale = staged.pseudo and true or nil
    BNB._debugImmersionPos = staged.imm and true or nil
    BNB:Print("|cff88bbff" .. (db.debugMode and "Debug mode enabled." or "Debug mode disabled.") .. "|r")
end

local function Tip(widget, title, body, extra)
    widget:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if title then GameTooltip:AddLine(title, 1, 1, 1) end
        if body then GameTooltip:AddLine(body, 0.8, 0.8, 0.8, true) end
        if extra then
            GameTooltip:AddLine(" ")
            for _, line in ipairs(extra) do GameTooltip:AddLine(line, 0.55, 0.85, 1) end
        end
        GameTooltip:Show()
    end)
    widget:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

local function BuildWindow()
    if _frame then return _frame end

    local skin = BigNoteBoxDB and BigNoteBoxDB.skinMode
    local f
    if skin then
        f = BNB.CreateSkinFrame(UIParent, false, "BigNoteBoxDebugFrame", false)
    else
        f = CreateFrame("Frame", "BigNoteBoxDebugFrame", UIParent, "ButtonFrameTemplate")
    end
    f:SetToplevel(true)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:SetClampedToScreen(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) self:StartMoving() end)
    f:SetScript("OnDragStop",  function(self) self:StopMovingOrSizing() end)
    f:SetFrameStrata("DIALOG")
    f:SetSize(WIN_W, WIN_H)
    f:SetPoint("CENTER")

    if skin then
        -- Skin title strip, same build as UI/ToolWindow.lua (ALL-79)
        local titleBar = BNB.CreateSkinStrip(f, true, false)
        titleBar:SetPoint("TOPLEFT",  f, "TOPLEFT",  0, 0)
        titleBar:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
        titleBar:SetHeight(SK_TITLE_H)
        titleBar:EnableMouse(true)
        titleBar:RegisterForDrag("LeftButton")
        titleBar:SetScript("OnDragStart", function() f:StartMoving() end)
        titleBar:SetScript("OnDragStop",  function() f:StopMovingOrSizing() end)

        local titleLbl = titleBar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        titleLbl:SetPoint("CENTER", titleBar, "CENTER", -15, 0)
        titleLbl:SetTextColor(1, 0.82, 0)
        titleLbl:SetText(L["DEV_WIN_TITLE"])

        -- X = Cancel
        local closeBtn = BNB.CreateSkinCloseButton(titleBar, function() DW.Close() end)
        closeBtn:SetPoint("RIGHT", titleBar, "RIGHT", -3, 0)
        -- Preset recolour runs in the OnShow handler at the bottom (SetScript there)
    else
        ButtonFrameTemplate_HidePortrait(f)
        ButtonFrameTemplate_HideButtonBar(f)
        if f.Inset then f.Inset:Hide() end
        BNB.SeatChrome(f)
        f._forGlow = BNB.AddForeverGlow(f, f.Bg)
        f:SetTitle(L["DEV_WIN_TITLE"])

        -- X = Cancel
        if f.CloseButton then f.CloseButton:SetScript("OnClick", function() DW.Close() end) end
    end
    tinsert(UISpecialFrames, "BigNoteBoxDebugFrame")

    local y = -36

    -- Warning text, always visible
    local warn = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    warn:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, y)
    warn:SetWidth(WIN_W - PAD * 2)
    warn:SetJustifyH("LEFT"); warn:SetJustifyV("TOP"); warn:SetWordWrap(true)
    warn:SetHeight(88)
    warn:SetTextColor(1, 0.55, 0.25)
    warn:SetText(L["DEV_WIN_WARNING"])
    y = y - 96

    local rule = f:CreateTexture(nil, "ARTWORK")
    rule:SetHeight(1)
    rule:SetColorTexture(0.5, 0.5, 0.5, 0.6)
    if skin then BNB.RegisterSkinRule(rule, 0.6) end
    rule:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, y)
    rule:SetPoint("TOPRIGHT", f, "TOPRIGHT", -PAD, y)
    y = y - 10

    local dependents = {}   -- widgets that follow the staged master checkbox

    local function MakeCheck(indent, label, key, tipTitle, tipBody, tipExtra)
        local cb = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
        cb:SetSize(24, 24)
        cb:SetPoint("TOPLEFT", f, "TOPLEFT", PAD + indent - 2, y + 2)
        local lbl = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        lbl:SetPoint("LEFT", cb, "RIGHT", 4, 0)
        lbl:SetJustifyH("LEFT")
        lbl:SetText(label)
        Tip(cb, tipTitle, tipBody, tipExtra)
        cb._key, cb._lbl = key, lbl
        y = y - ROW_H
        return cb
    end

    local function MakeButton(label, w, tipTitle, tipBody, onClick)
        local b = BNB.CreateButton(nil, f, label, w, 22)
        b:SetPoint("TOPLEFT", f, "TOPLEFT", PAD + SUB_INDENT, y + 2)
        b:SetScript("OnClick", function()
            if not staged.master then return end
            onClick()
        end)
        Tip(b, tipTitle, tipBody)
        y = y - ROW_H
        return b
    end

    local function Refresh()
        for _, w in ipairs(dependents) do
            local on = staged.master
            if w.cb then w.cb:SetEnabled(on); w.cb:SetAlpha(on and 1.0 or 0.4) end
            if w.btn then w.btn:SetEnabled(on); w.btn:SetAlpha(on and 1.0 or 0.4) end
            if w.lbl then w.lbl:SetTextColor(on and 1 or 0.45, on and 0.82 or 0.45, on and 0 or 0.45) end
        end
    end

    local master = MakeCheck(0, L["CFG_DEV_ACTIVATE_LABEL"], "master",
        nil, L["CFG_DEV_ACTIVATE_TIP"])
    master:SetScript("OnClick", function(self)
        staged.master = self:GetChecked() and true or false
        Refresh()
    end)
    master._lbl:SetTextColor(1, 0.82, 0)

    local function Sub(label, key, tipTitle, tipBody, tipExtra)
        local cb = MakeCheck(SUB_INDENT, label, key, tipTitle, tipBody, tipExtra)
        cb:SetScript("OnClick", function(self) staged[key] = self:GetChecked() and true or false end)
        dependents[#dependents + 1] = { cb = cb, lbl = cb._lbl }
        return cb
    end

    local wpCb = Sub(L["CFG_DEV_WP_LABEL"], "wp", nil, L["CFG_DEV_WP_TIP"], {
        "/bnb testwp status - shows current note's waypoint data",
        "/bnb testwp fire - simulates zone-enter (places waypoints)",
        "/bnb testwp leave - simulates zone-leave (clears waypoints)",
        "/bnb testwp auto - shows auto-placed waypoint tracking",
    })
    local pseudoCb = Sub(L["CFG_DEV_PSEUDOLOC_LABEL"], "pseudo",
        L["CFG_DEV_PSEUDOLOC_TIP_TITLE"], L["CFG_DEV_PSEUDOLOC_TIP_BODY"])
    local immCb = Sub(L["CFG_DEV_IMM_LABEL"], "imm", L["CFG_DEV_IMM_LABEL"], L["CFG_DEV_IMM_TIP"])

    y = y - 4

    local toastBtn = MakeButton(L["CFG_DEV_TOAST_BTN"], 170,
        L["CFG_DEV_TOAST_TIP_TITLE"], L["CFG_DEV_TOAST_TIP_BODY"], function()
            BNB:Print("|cff88bbffFiring test toast...|r")
            BNB._contextMatches = {}
            if BNB.CheckContextualNotes then BNB.CheckContextualNotes() end
            local matches = BNB._contextMatches or {}
            if #matches == 0 then
                BNB:Print("|cffff9900No notes match your current zone. Bind a note to your current zone first.|r")
            else
                BNB:Print(string.format("|cff88bbff%d note(s) matched - toast should appear.|r", #matches))
            end
        end)
    local setupBtn = MakeButton(L["CFG_DEV_SETUP_BTN"], 170,
        L["CFG_DEV_SETUP_TIP_TITLE"], L["CFG_DEV_SETUP_TIP_BODY"], function()
            if BNB.ShowSetupWizard then BNB.ShowSetupWizard() end
        end)
    local migBtn = MakeButton(L["CFG_DEV_MIGRATE_BTN"], 170,
        L["CFG_DEV_MIGRATE_TIP_TITLE"], L["CFG_DEV_MIGRATE_TIP_BODY"], function()
            if BNB.Migration and BNB.Migration.SeedDebugData then
                BNB.Migration.SeedDebugData()
                BNB:Print("|cff88bbffFake migration data seeded for all supported addons.|r")
                BNB.Migration.ShowPopup()
            end
        end)
    dependents[#dependents + 1] = { btn = toastBtn }
    dependents[#dependents + 1] = { btn = setupBtn }
    dependents[#dependents + 1] = { btn = migBtn }

    -- Bottom row: Reload / OK / Cancel
    local bw = (WIN_W - PAD * 2 - 16) / 3
    local reloadBtn = BNB.CreateButton(nil, f, L["DZ_POPUP_RELOAD"], bw, 24)
    reloadBtn:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", PAD, PAD - 4)
    reloadBtn:SetScript("OnClick", function() Commit(); C_UI.Reload() end)
    Tip(reloadBtn, L["DZ_POPUP_RELOAD"], L["DEV_WIN_RELOAD_TIP"])

    local okBtn = BNB.CreateButton(nil, f, L["OK"], bw, 24)
    okBtn:SetPoint("LEFT", reloadBtn, "RIGHT", 8, 0)
    okBtn:SetScript("OnClick", function() Commit(); DW.Close() end)

    local cancelBtn = BNB.CreateButton(nil, f, L["CANCEL"], bw, 24)
    cancelBtn:SetPoint("LEFT", okBtn, "RIGHT", 8, 0)
    cancelBtn:SetScript("OnClick", function() DW.Close() end)

    -- Re-read the DB every time the window shows
    f:SetScript("OnShow", function()
        if skin and BNB.ApplyMainWindowSkin then BNB.ApplyMainWindowSkin() end
        local db = BigNoteBoxDB or {}
        staged.master = db.debugMode == true
        staged.wp     = db.debugWaypoint == true
        staged.pseudo = db.debugPseudoLocale == true
        staged.imm    = BNB._debugImmersionPos == true
        master:SetChecked(staged.master)
        wpCb:SetChecked(staged.wp)
        pseudoCb:SetChecked(staged.pseudo)
        immCb:SetChecked(staged.imm)
        Refresh()
    end)

    f:Hide()
    _frame = f
    return f
end

function DW.Open()
    local f = BuildWindow()
    f:Show()
    f:Raise()
end

function DW.Close()
    if _frame then _frame:Hide() end
end

function DW.Toggle()
    if _frame and _frame:IsShown() then DW.Close() else DW.Open() end
end

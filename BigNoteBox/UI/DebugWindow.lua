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
--   Built with BNB.CreateToolWindow, both modes (ALL-79, CMP-02 S3).

local BNB = BigNoteBox
local L = BNB.L
BNB.DebugWindow = BNB.DebugWindow or {}
local DW = BNB.DebugWindow

local WIN_W, WIN_H = 400, 508
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
    if not db.debugMode then
        -- Sub-options are meaningless with the master off (same as the old inline section)
        staged.wp, staged.pseudo, staged.imm, staged.ctxTrace = false, false, false, false
        db.debugWaypoint = nil; BNB._debugWaypoint = nil
    else
        db.debugWaypoint = staged.wp and true or nil
        BNB._debugWaypoint = db.debugWaypoint
    end
    db.debugPseudoLocale = staged.pseudo and true or nil
    BNB._debugImmersionPos = staged.imm and true or nil
    db.debugContextTrace = staged.ctxTrace and true or nil
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

    -- Chrome for both modes (CMP-02 S3); the X is Cancel
    local f = BNB.CreateToolWindow({
        name = "BigNoteBoxDebugFrame", w = WIN_W, h = WIN_H,
        title = L["DEV_WIN_TITLE"], toplevel = true, escClose = true,
        onClose = function() DW.Close() end,
    })
    local skin = f._isSkin
    f:SetPoint("CENTER")

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
        BNB.LabelHit(cb)   -- the tooltip and click reach over its label too
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
    -- Situation check trace (ALL-192, Features/ContextNotes.lua). Saved, so it
    -- survives the reload it is meant to watch; in dev mode debug mode is
    -- re-armed every load (Core/Database.lua InitDevMode), so it keeps running.
    local ctxCb = Sub(L["CFG_DEV_CTX_TRACE_LABEL"], "ctxTrace",
        L["CFG_DEV_CTX_TRACE_LABEL"], L["CFG_DEV_CTX_TRACE_TIP"])

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
    -- The search bar theme layout tool (ALL-69, BigNoteBox_Dev Labs/SearchLayoutTool.lua), same as
    -- /bnb searchlayout.
    local layoutBtn = MakeButton(L["CFG_DEV_SEARCHLAYOUT_BTN"], 170,
        L["CFG_DEV_SEARCHLAYOUT_BTN"], L["CFG_DEV_SEARCHLAYOUT_TIP_BODY"], function()
            if BNB.ToggleSearchLayoutTool then BNB.ToggleSearchLayoutTool() end
        end)
    -- Hover boxes for every drag cursor (ALL-95, UI/Cursor.lua)
    local cursorBtn = MakeButton(L["CFG_DEV_CURSOR_BTN"], 170,
        L["CFG_DEV_CURSOR_BTN"], L["CFG_DEV_CURSOR_TIP_BODY"], function()
            if BNB.OpenCursorTest then BNB.OpenCursorTest() end
        end)
    -- Game background preview for the sticky list (ALL-110, BigNoteBox_Dev Labs/BackgroundLab.lua)
    local bgLabBtn = MakeButton(L["CFG_DEV_BGLAB_BTN"], 170,
        L["CFG_DEV_BGLAB_BTN"], L["CFG_DEV_BGLAB_TIP_BODY"], function()
            if BNB.OpenBackgroundLab then BNB.OpenBackgroundLab() end
        end)
    -- Beside Cursor Test rather than a new row, so the window keeps its height
    bgLabBtn:ClearAllPoints()
    bgLabBtn:SetPoint("LEFT", cursorBtn, "RIGHT", 8, 0)
    y = y + ROW_H
    -- Note icon frame measuring (ALL-126, BigNoteBox_Dev Labs/IconLab.lua), beside Search layout
    local iconLabBtn = MakeButton(L["CFG_DEV_ICONLAB_BTN"], 170,
        L["CFG_DEV_ICONLAB_BTN"], L["CFG_DEV_ICONLAB_TIP_BODY"], function()
            if BNB.OpenIconLab then BNB.OpenIconLab() end
        end)
    iconLabBtn:ClearAllPoints()
    iconLabBtn:SetPoint("LEFT", layoutBtn, "RIGHT", 8, 0)
    y = y + ROW_H
    -- The menu engine on its own (ALL-148, UI/ContextMenu.lua), beside Setup wizard
    local ctxBtn
    ctxBtn = MakeButton(L["CFG_DEV_CTXMENU_BTN"], 170,
        L["CFG_DEV_CTXMENU_BTN"], L["CFG_DEV_CTXMENU_TIP_BODY"], function()
            BNB.OpenContextMenuTest(ctxBtn)
        end)
    ctxBtn:ClearAllPoints()
    ctxBtn:SetPoint("LEFT", setupBtn, "RIGHT", 8, 0)
    y = y + ROW_H
    -- The top tabs tuning panel (ALL-248), beside Migration test. It lives in
    -- the dev addon (/bnbtabs), so the button is only there while that is loaded.
    local tabsBtn = MakeButton(L["CFG_DEV_TOPTABS_BTN"], 170,
        L["CFG_DEV_TOPTABS_BTN"], L["CFG_DEV_TOPTABS_TIP_BODY"], function()
            if SlashCmdList.BNBTOPTABS then SlashCmdList.BNBTOPTABS() end
        end)
    tabsBtn:ClearAllPoints()
    tabsBtn:SetPoint("LEFT", migBtn, "RIGHT", 8, 0)
    y = y + ROW_H
    if not SlashCmdList.BNBTOPTABS then tabsBtn:Hide() end
    -- The labs live in the dev addon too (ARCH-04)
    if not BNB.ToggleSearchLayoutTool then layoutBtn:Hide() end
    if not BNB.OpenBackgroundLab then bgLabBtn:Hide() end
    if not BNB.OpenIconLab then iconLabBtn:Hide() end
    dependents[#dependents + 1] = { btn = tabsBtn }
    dependents[#dependents + 1] = { btn = ctxBtn }
    dependents[#dependents + 1] = { btn = iconLabBtn }
    dependents[#dependents + 1] = { btn = bgLabBtn }
    dependents[#dependents + 1] = { btn = toastBtn }
    dependents[#dependents + 1] = { btn = layoutBtn }
    dependents[#dependents + 1] = { btn = cursorBtn }
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
    f:HookScript("OnShow", function()
        local db = BigNoteBoxDB or {}
        staged.master = db.debugMode == true
        staged.wp     = db.debugWaypoint == true
        staged.pseudo = db.debugPseudoLocale == true
        staged.imm    = BNB._debugImmersionPos == true
        master:SetChecked(staged.master)
        wpCb:SetChecked(staged.wp)
        pseudoCb:SetChecked(staged.pseudo)
        immCb:SetChecked(staged.imm)
        staged.ctxTrace = db.debugContextTrace == true
        ctxCb:SetChecked(staged.ctxTrace)
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

-- Context Menu Test (ALL-148): the engine with every kind of row, no notes
function BNB.OpenContextMenuTest(owner)
    local function Say(what) return function() BNB:Print("|cff88bbffMenu:|r " .. what) end end
    BNB.ContextMenu.Open(owner, function(root)
        root:CreateTitle("Context Menu Test", { icon = "Interface\\Icons\\INV_Misc_Note_01", badge = true,
            color = { r = 0.45, g = 0.8, b = 1 } })   -- as a note's titleColor arrives
        root:CreateDivider()
        local open = root:CreateButton("Open note", Say("Open note (parent click)"), { icon = "note" })
        open:CreateButton("Open sticky note", Say("Open sticky note"))
        open:CreateButton("Open ESC sticky note", Say("Open ESC sticky note"))
        local create = root:CreateButton("Create", nil, { icon = "create" })
        create:CreateButton("Create alarm", Say("Create alarm"))
        create:CreateButton("Create task", Say("Create task"))
        create:CreateButton("Create situation", Say("Create situation"))
        root:CreateDivider()
        root:CreateButton("Pin to top", Say("Pin to top"), { icon = "pinned" })
        root:CreateButton("Add to favorites", Say("Add to favorites"), { icon = "favorite",
            tip = "Tooltip test", tipSub = "A second, wrapped line under the title." })
        root:CreateButton("Lock note (disabled)", Say("never"), { icon = "locked", disabled = true })
        local act = root:CreateButton("Actions", nil, { icon = "action" })
        act:CreateButton("Duplicate", Say("Duplicate"))
        act:CreateButton("A rather long label to check that the width follows the longest row", Say("Long label"))
        act:CreateDivider()
        act:CreateButton("Disabled sub-menu row", Say("never"), { disabled = true })
        local hist = root:CreateButton("History", nil, { icon = "history" })
        hist:CreateButton("View note history", Say("View note history"))
        local prev = hist:CreateButton("Restore previous")
        prev:CreateButton("Manual restore point", Say("Manual restore point"))
        prev:CreateDivider()
        for n = 1, 3 do prev:CreateButton("Snapshot " .. n, Say("Snapshot " .. n)) end
        prev:CreateButton("View all...", Say("View all"))
        root:CreateDivider()
        root:CreateButton("Move to trash", Say("Move to trash"), { icon = "trash" })
        root:CreateButton("Delete permanently", Say("Delete permanently"), { icon = "danger" })
    end)
end

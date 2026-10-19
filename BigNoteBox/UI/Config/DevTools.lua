-- BigNoteBox UI/Config/DevTools.lua - Settings > Advanced > Developer tools page
--
-- The developer tools as a Settings sub-page (ALL-395, replaces the old
-- standalone window UI/DebugWindow.lua from ALL-30). The page is reached from
-- the Advanced tab's Developer tools button, which is enabled only while the
-- dev addon BigNoteBox_Dev is loaded (BNB.IsDevMode), and by /bnb debug.
--
-- BEHAVIOUR (Dukul, 2026-10-08):
--   * Debug mode itself is a checkbox on the Advanced tab, not on this page:
--     it works without the dev addon (debug slash commands, !!KEY markers), and
--     in dev mode it is always on (Core/Database.lua InitDevMode). Session only:
--     InitSettingsDB clears it on every load. BNB.SetDebugMode(on) is the one
--     switch (checkbox and /bnb debug on|off).
--   * Three sections: Options (checkboxes, saved at once), Labs (the dev
--     addon's labs) and Tools and tests. No OK / Cancel; Reload stays.
--   * A warning box is always at the top.
--
-- PUBLIC API:
--   BNB.SetDebugMode(on)        -- false = refused (dev mode keeps it on)
--   BNB.IsDebugMode()
--   BNB.OpenDevTools()          -- the page in dev mode, else the Advanced tab
--   BNB.ToggleDevToolsWindow()  -- /bnb devtools: the page alone in its own window (dev mode)
--   BNB.OpenContextMenuTest(owner)
--   BNB.DEVTOOL_URL

local BNB = BigNoteBox
local L   = BNB.L

local K = BNB._ConfigKit
local CONTENT_W = K.CONTENT_W
local AddRule, AddHeader, AddCheck = K.AddRule, K.AddHeader, K.AddCheck

BNB.DEVTOOL_URL = "https://github.com/DukulWoW/BigNoteBox/blob/main/DEVTOOL.md"

function BNB.IsDebugMode()
    return BigNoteBoxDB ~= nil and BigNoteBoxDB.debugMode == true
end

-- The one debug mode switch. In dev mode debug mode stays on (Dukul,
-- 2026-10-08): returns false and changes nothing when asked to switch it off.
function BNB.SetDebugMode(on)
    local db = BigNoteBoxDB
    if not db then return false end
    if not on and BNB.IsDevMode() then
        BNB:Print("|cff88bbff" .. L["DEBUG_MODE_DEV_ON"] .. "|r")
        return false
    end
    db.debugMode = on and true or nil
    if not on then
        -- Waypoint debug only means something while debug mode is on
        db.debugWaypoint = nil; BNB._debugWaypoint = nil
    end
    BNB:Print("|cff88bbff" .. (on and L["DEBUG_MODE_ENABLED"] or L["DEBUG_MODE_DISABLED"]) .. "|r")
    return true
end

function BNB.OpenDevTools()
    if BNB.OpenSettingsPage then
        BNB.OpenSettingsPage("advanced", BNB.IsDevMode() and "devtools" or nil)
    end
end

-- Tooltip on a button: hooked, since a skin button draws its hover in its own
-- OnEnter / OnLeave.
local function Tip(widget, title, body, extra)
    widget:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if title then GameTooltip:AddLine(title, 1, 1, 1) end
        if body then GameTooltip:AddLine(body, 0.8, 0.8, 0.8, true) end
        if extra then
            GameTooltip:AddLine(" ")
            for _, line in ipairs(extra) do GameTooltip:AddLine(line, 0.55, 0.85, 1) end
        end
        GameTooltip:Show()
    end)
    widget:HookScript("OnLeave", function() GameTooltip:Hide() end)
end

local function Slash(key)
    return function()
        if SlashCmdList[key] then SlashCmdList[key]("") else BNB.DevToolMissing() end
    end
end

-- Buttons two to a row. A tool that is not loaded leaves no gap.
-- entries: { label, tipBody, onClick, available, placeholder }
-- placeholder = true: shown greyed out, tooltip only (a lab still to come)
local function AddButtonGrid(ct, y, entries)
    local GAP = 8
    local bw = math.floor((CONTENT_W - GAP) / 2)
    local col = 0
    for _, e in ipairs(entries) do
        if e[4] ~= false then
            local b = BNB.CreateButton(nil, ct, e[1], bw, 24)
            b:SetPoint("TOPLEFT", ct, "TOPLEFT", col * (bw + GAP), y)
            local fn = e[3]
            if fn then b:SetScript("OnClick", function(self) fn(self) end) end
            -- A disabled button still gets OnEnter, so the tooltip shows
            if e[5] then b:SetEnabled(false) end
            Tip(b, e[1], e[2])
            if col == 1 then col = 0; y = y - 30 else col = 1 end
        end
    end
    if col == 1 then y = y - 30 end
    return y
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

-- A plain note listing every UI link: the gold link to click, then the
-- form to type in a rich note. Tagged Draft, so the help build leaves it out.
-- Its id is kept in the lab DB, so a second click rewrites the same note.
function BNB.MakeUILinkListNote()
    local UL = BNB.UILinks
    if not UL then return end
    local groups = { { "Settings", {} }, { "Windows", {} }, { "Help topics", {} } }
    for _, p in ipairs(UL.List()) do
        local g = p.key:find("^settings%.") and 1 or p.key:find("^help%.") and 3 or 2
        local t = groups[g][2]
        t[#t + 1] = "- " .. UL.Link(p.key) .. "    {link*bnbui:" .. p.key .. "*}"
    end
    local lines = {
        "Every BigNoteBox link (bnbui), made by Developer tools > UI link list. Click a gold link to try it.",
        "In a rich note, type the form on the right. With nothing after the second *, the link shows the place's name;",
        "put your own text or an {icon:Name:16} there for a button: {link*bnbui:oracle*{icon:INV_Misc_Spyglass_03:16}}.",
        "Help topics link as bnbui:help.<key> (the key is made from the title on the first help build).",
        "Made " .. BNB.Date("%Y-%m-%d %H:%M", time()) .. ". Tagged Draft: the help build leaves this note out.",
    }
    for _, g in ipairs(groups) do
        lines[#lines + 1] = ""
        lines[#lines + 1] = g[1] .. " (" .. #g[2] .. ")"
        if #g[2] == 0 then lines[#lines + 1] = "- none yet: Help topics come with the first help build" end
        for _, l in ipairs(g[2]) do lines[#lines + 1] = l end
    end
    local title, body = "UI links (every key)", table.concat(lines, "\n")
    local lab = BNB.LabDB()
    local id = lab and lab.devUILinkNote
    local ndb = BNB.NotesDB()
    if not (id and ndb and ndb.notes and ndb.notes[id]) then
        id = BNB.CreateNote(title, body)
        if not id then return end
        if lab then lab.devUILinkNote = id end
    end
    BNB.UpdateNote(id, { title = title, body = body, richMode = false, scope = "global", tags = { "Draft" } })
    if BNB.OpenNoteInMain then BNB.OpenNoteInMain(id) end
    BNB:Print("|cff88bbffUI link list note written (" .. #UL.List() .. " links).|r")
end

StaticPopupDialogs["BNB_DOC_MODE_RELOAD"] = {
    text = L["CFG_DEV_DOC_RELOAD"],
    button1 = RELOADUI or "Reload", button2 = LATER or "Later",
    OnAccept = function() C_UI.Reload() end,   -- in the click itself (protected)
    timeout = 0, whileDead = true, hideOnEscape = true,
}

-- The page body, built by K.NewSubPage from the Advanced tab.
function K.BuildDevToolsPage(sf, ct, y)
    local db = BigNoteBoxDB

    -- ── Warning box ─────────────────────────────────────────────────────────
    local box = BNB.CreateBackdropFrame("Frame", nil, ct)
    BNB.SetBackdrop(box, 0.22, 0.10, 0.03, 0.85, 0.85, 0.45, 0.15, 1)
    box:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
    box:SetWidth(CONTENT_W)
    local warn = box:CreateFontString(nil, "OVERLAY", "BNBFontNormal")
    warn:SetPoint("TOPLEFT", box, "TOPLEFT", 10, -10)
    warn:SetWidth(CONTENT_W - 20)
    warn:SetJustifyH("LEFT"); warn:SetJustifyV("TOP"); warn:SetWordWrap(true)
    warn:SetTextColor(1, 0.65, 0.3)
    warn:SetText(L["DEV_WIN_WARNING"])
    local wh = math.ceil(warn:GetStringHeight())
    warn:SetHeight(wh)
    box:SetHeight(wh + 20)
    y = y - (wh + 20) - 14

    -- ── Options ─────────────────────────────────────────────────────────────
    y = AddHeader(ct, y, L["DEV_HDR_OPTIONS"])
    -- Two columns, filled row by row (Dukul, 2026-10-10): each column is its
    -- own frame, so AddCheck's label stops at the column edge
    local COL_GAP = 8
    local colW = math.floor((CONTENT_W - COL_GAP) / 2)
    local cols = {}
    for i = 1, 2 do
        cols[i] = CreateFrame("Frame", nil, ct)
        cols[i]:SetPoint("TOPLEFT", ct, "TOPLEFT", (i - 1) * (colW + COL_GAP), y)
        cols[i]:SetSize(colW, 10)
    end
    local colY, slot = { 0, 0 }, 0
    local function OptCheck(...)
        slot = slot % 2 + 1
        local cb
        colY[slot], cb = AddCheck(cols[slot], colY[slot], ...)
        return cb
    end
    local wpCb, immCb, ctxCb, toastCb
    wpCb = OptCheck(L["CFG_DEV_WP_LABEL"],
        function() return db.debugWaypoint == true end,
        function(v) db.debugWaypoint = v or nil; BNB._debugWaypoint = db.debugWaypoint end)
    Tip(wpCb, nil, L["CFG_DEV_WP_TIP"], {
        "/bnb testwp status - shows current note's waypoint data",
        "/bnb testwp fire - simulates zone-enter (places waypoints)",
        "/bnb testwp leave - simulates zone-leave (clears waypoints)",
        "/bnb testwp auto - shows auto-placed waypoint tracking",
    })
    immCb = OptCheck(L["CFG_DEV_IMM_LABEL"],
        function() return BNB._debugImmersionPos == true end,
        function(v) BNB._debugImmersionPos = v or nil end,
        L["CFG_DEV_IMM_TIP"])
    -- Situation check trace (ALL-192, Features/ContextNotes.lua). Saved, so it
    -- survives the reload it is meant to watch; debug mode is re-armed every
    -- load in dev mode, so it keeps running.
    ctxCb = OptCheck(L["CFG_DEV_CTX_TRACE_LABEL"],
        function() return db.debugContextTrace == true end,
        function(v) db.debugContextTrace = v or nil end,
        L["CFG_DEV_CTX_TRACE_TIP"])
    K.ReadOnShow(wpCb, function() return db.debugWaypoint == true end)
    K.ReadOnShow(immCb, function() return BNB._debugImmersionPos == true end)
    -- Toast anchor drag: prints the saved offset (UI/Toast.lua), to find a better default
    toastCb = OptCheck(L["CFG_DEV_TOAST_ANCHOR_LABEL"],
        function() return db.debugToastAnchor == true end,
        function(v) db.debugToastAnchor = v or nil end,
        L["CFG_DEV_TOAST_ANCHOR_TIP"])
    K.ReadOnShow(ctxCb, function() return db.debugContextTrace == true end)
    K.ReadOnShow(toastCb, function() return db.debugToastAnchor == true end)
    -- Player note encounters every minute, ignoring the zone-visit rule
    -- (ALL-474 testing, Features/PlayerNoteAuto.lua)
    local encCb = OptCheck(L["CFG_DEV_ENC_GAP_LABEL"],
        function() return db.debugEncounterGap == true end,
        function(v) db.debugEncounterGap = v or nil end,
        L["CFG_DEV_ENC_GAP_TIP"])
    K.ReadOnShow(encCb, function() return db.debugEncounterGap == true end)
    -- Doc mode (ALL-512): the help topics set, switched at the next load
    -- (Core/Database.lua InitDevMode); the popup's own click reloads
    if BNB.IsDevMode() and type(BigNoteBoxDevDB) == "table" then
        local docCb = OptCheck(L["CFG_DEV_DOC_LABEL"],
            function() return BigNoteBoxDevDB.docMode == true end,
            function(v)
                BigNoteBoxDevDB.docMode = v or nil
                if (v == true) ~= BNB.IsDocMode() then StaticPopup_Show("BNB_DOC_MODE_RELOAD") end
            end,
            L["CFG_DEV_DOC_TIP"])
        K.ReadOnShow(docCb, function() return BigNoteBoxDevDB.docMode == true end)
    end
    y = y + math.min(colY[1], colY[2])

    -- ── Labs (the dev addon, ARCH-04) ───────────────────────────────────────
    AddRule(ct, y - 4); y = y - 18
    y = AddHeader(ct, y, L["DEV_HDR_LABS"])
    y = AddButtonGrid(ct, y, {
        { L["CFG_DEV_BGLAB_BTN"], L["CFG_DEV_BGLAB_TIP_BODY"],
            function() BNB.OpenBackgroundLab() end, BNB.OpenBackgroundLab ~= nil },
        { L["CFG_DEV_ICONLAB_BTN"], L["CFG_DEV_ICONLAB_TIP_BODY"],
            function() BNB.OpenIconLab() end, BNB.OpenIconLab ~= nil },
        { L["CFG_DEV_TOASTLAB_BTN"], L["CFG_DEV_TOASTLAB_TIP_BODY"],
            function() BNB.OpenToastLab() end, BNB.OpenToastLab ~= nil },
        { L["CFG_DEV_SKINLAB_BTN"], L["CFG_DEV_SKINLAB_TIP_BODY"],
            function() BNB.OpenSkinLab() end, BNB.OpenSkinLab ~= nil },
        -- Placeholder until the lab exists (Dukul, 2026-10-10)
        { L["CFG_DEV_THEMELAB_BTN"], L["CFG_DEV_THEMELAB_TIP_BODY"], nil, true, true },
        { L["CFG_DEV_SEARCHLAYOUT_BTN"], L["CFG_DEV_SEARCHLAYOUT_TIP_BODY"],
            function() BNB.ToggleSearchLayoutTool() end, BNB.ToggleSearchLayoutTool ~= nil },
    })

    -- ── Tools and tests ─────────────────────────────────────────────────────
    AddRule(ct, y - 4); y = y - 18
    y = AddHeader(ct, y, L["DEV_HDR_TOOLS"])
    y = AddButtonGrid(ct, y, {
        { L["CFG_DEV_TOAST_BTN"], L["CFG_DEV_TOAST_TIP_BODY"], function()
            BNB:Print("|cff88bbffFiring test toast...|r")
            BNB._contextMatches = {}
            if BNB.CheckContextualNotes then BNB.CheckContextualNotes() end
            local matches = BNB._contextMatches or {}
            if #matches == 0 then
                BNB:Print("|cffff9900No notes match your current zone. Bind a note to your current zone first.|r")
            else
                BNB:Print(string.format("|cff88bbff%d note(s) matched - toast should appear.|r", #matches))
            end
        end },
        -- The toast as after an update (ALL-409; it opens the release in the
        -- Patch notes folder since ALL-511): the stamped version is cleared,
        -- id / checksum kept, so an old pinned patch note is removed too
        { L["CFG_DEV_PATCHNOTE_BTN"], L["CFG_DEV_PATCHNOTE_TIP_BODY"], function()
            local ndb = BNB.NotesDB()
            if type(ndb) == "table" and type(ndb.patchNote) == "table" then ndb.patchNote.version = nil end
            BNB.WhatsNew.CheckAndShow(false)
            if not (BNB.ToastsEnabled() and BNB.ToastSourceOn("patchnotes")) then
                BNB:Print("|cffff9900The patch notes toast is off in Settings > Modules > Toasts.|r")
            end
        end },
        -- Every UI link key as a note (ALL-513, Dukul 2026-10-19: "Easier to work
        -- with if I know what they all are"): made from the registry, so it is
        -- never out of date; the same note is rewritten on the next click
        { L["CFG_DEV_UILINKS_BTN"], L["CFG_DEV_UILINKS_TIP_BODY"], function()
            if BNB.MakeUILinkListNote then BNB.MakeUILinkListNote() end
        end, BNB.UILinks ~= nil },
        -- The fresh-install welcome note (ALL-242), for this character's faction
        { L["CFG_DEV_WELCOMENOTE_BTN"], L["CFG_DEV_WELCOMENOTE_TIP_BODY"], function()
            BNB.WhatsNew.CheckWelcome(true, true)
        end },
        { L["CFG_DEV_SETUP_BTN"], L["CFG_DEV_SETUP_TIP_BODY"], function()
            if BNB.ShowSetupWizard then BNB.ShowSetupWizard() end
        end },
        { L["CFG_DEV_MIGRATE_BTN"], L["CFG_DEV_MIGRATE_TIP_BODY"], function()
            if BNB.Migration and BNB.Migration.SeedDebugData then
                BNB.Migration.SeedDebugData()
                BNB:Print("|cff88bbffFake migration data seeded for all supported addons.|r")
                BNB.Migration.ShowPopup()
            end
        end },
        -- Hover boxes for every drag cursor (ALL-95, UI/Cursor.lua)
        { L["CFG_DEV_CURSOR_BTN"], L["CFG_DEV_CURSOR_TIP_BODY"], function()
            if BNB.OpenCursorTest then BNB.OpenCursorTest() end
        end },
        -- The menu engine on its own (ALL-148, UI/ContextMenu.lua)
        { L["CFG_DEV_CTXMENU_BTN"], L["CFG_DEV_CTXMENU_TIP_BODY"],
            function(btn) BNB.OpenContextMenuTest(btn) end },
        -- The rest live in the dev addon as slash commands
        { L["CFG_DEV_TOPTABS_BTN"], L["CFG_DEV_TOPTABS_TIP_BODY"],
            Slash("BNBTOPTABS"), SlashCmdList.BNBTOPTABS ~= nil },
        { L["CFG_DEV_SKINW_BTN"], L["CFG_DEV_SKINW_TIP_BODY"],
            Slash("BNBSKINWIDGETS"), SlashCmdList.BNBSKINWIDGETS ~= nil },
        { L["CFG_DEV_BTNTEST_BTN"], L["CFG_DEV_BTNTEST_TIP_BODY"],
            Slash("BNBBUTTONTEST"), SlashCmdList.BNBBUTTONTEST ~= nil },
        { L["CFG_DEV_ICONPROBE_BTN"], L["CFG_DEV_ICONPROBE_TIP_BODY"],
            Slash("BNBICONPROBE"), SlashCmdList.BNBICONPROBE ~= nil },
        -- Fake characters of different ages + their notes (ALL-312, dev addon)
        { L["CFG_DEV_FAKEADD_BTN"], L["CFG_DEV_FAKEADD_TIP_BODY"],
            Slash("BNBFAKEDATA"), SlashCmdList.BNBFAKEDATA ~= nil },
        { L["CFG_DEV_FAKEDEL_BTN"], L["CFG_DEV_FAKEDEL_TIP_BODY"], function()
            if SlashCmdList.BNBFAKEDATA then SlashCmdList.BNBFAKEDATA("remove") else BNB.DevToolMissing() end
        end, SlashCmdList.BNBFAKEDATA ~= nil },
    })

    -- ── Reload ──────────────────────────────────────────────────────────────
    AddRule(ct, y - 4); y = y - 18
    local reloadBtn = BNB.CreateButton(nil, ct, L["DZ_POPUP_RELOAD"], 180, 24)
    reloadBtn:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
    reloadBtn:SetScript("OnClick", function() C_UI.Reload() end)   -- in the click itself (protected)
    Tip(reloadBtn, L["DZ_POPUP_RELOAD"], L["DEV_WIN_RELOAD_TIP"])
    y = y - 34

    sf:FinaliseHeight(math.abs(y) + 20)
end

-- ── /bnb devtools: the same page in a window of its own ──────────────────────
-- Dev mode only (Dukul, 2026-10-08): no Settings, no main window. Sized to the
-- content (no scroll); the position is kept in the dev addon's DB.
local _devWin
local WIN_PAD = 16

local function SaveWinPos(f)
    local point, _, relPoint, x, y = f:GetPoint(1)
    if point then BNB.LabDB().devToolsPos = { point, relPoint, x, y } end
end

local function BuildDevToolsWindow()
    local f = BNB.CreateToolWindow({
        name = "BigNoteBoxDevToolsFrame", w = CONTENT_W + WIN_PAD * 2, h = 600,
        title = L["DEV_WIN_TITLE"], toplevel = true, escClose = true,
        onDragStop = function() SaveWinPos(_devWin) end,
    })
    local pos = BNB.LabDB().devToolsPos
    f:ClearAllPoints()
    if type(pos) == "table" and pos[1] then
        f:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
    else
        f:SetPoint("CENTER")
    end
    BNB.AddDevModeOverlay(f)

    local top = (f._isSkin and BNB.TOOL_SKIN_TITLE_H or 24) + 10
    local ct = CreateFrame("Frame", nil, f)
    ct:SetPoint("TOPLEFT", f, "TOPLEFT", WIN_PAD, -top)
    ct:SetSize(CONTENT_W, 10)
    -- The page builder ends with sf:FinaliseHeight: here it sizes the window
    local host = { FinaliseHeight = function(_, h) f:SetHeight(top + h) end }
    K.BuildDevToolsPage(host, ct, 0)
    return f
end

function BNB.ToggleDevToolsWindow()
    if not BNB.IsDevMode() then BNB.DevToolMissing(); return end
    if InCombatLockdown() then BNB:Print(L["COMBAT_BLOCKED"]); return end
    _devWin = _devWin or BuildDevToolsWindow()
    if _devWin:IsShown() then _devWin:Hide() else _devWin:Show(); _devWin:Raise() end
end

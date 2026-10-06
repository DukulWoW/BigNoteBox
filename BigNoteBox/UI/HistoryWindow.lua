-- BigNoteBox UI/HistoryWindow.lua
--
-- Main history browser. Lists all notes that have any history (auto or manual).
-- Same width as TrashWindow, same height tracking (follows main window height).
-- Anchors TOPRIGHT of main window's TOPLEFT, same as Trash.
--
-- Two pages in one window (ALL-258): the list (root) and one note's
-- snapshots ("note", built by UI/NoteHistoryPanel.lua). A row click shows
-- that note's page; its back arrow or ESC returns to the list.
--
-- Public API:
--   BNB.ToggleHistoryWindow()
--   BNB.OpenHistoryWindow()
--   BNB.ShowHistoryWindow(pageKey, ...)  -- opens the window on a page
--   BNB.ReopenHistoryWindow()            -- Focus mode: the page it closed on
--   BNB.CloseHistoryWindow()
--   BNB.RefreshHistoryWindow()
--   BNB.InitHistoryWindow()

local BNB = BigNoteBox
local L   = BNB.L

local HW_W           = BNB.SIDE_WINDOW_W   -- 400 (ALL-269)
local TITLE_H        = 32
local PAD            = 14
local ROW_H          = 56    -- compact: icon + title + date
local ROW_GAP        = 4
local ICON_SZ        = 36
local ICON_X         = 6    -- room for an icon frame's left edge: at 0 the scroll frame cut it (ALL-332)
local TEXT_LEFT      = PAD + ICON_SZ + 10
local CONTENT_W      = HW_W - PAD * 2 - 30
local BOTTOM_STRIP_H = 44

local DEFAULT_ICON = "Interface\\Icons\\INV_Misc_Note_06"

local _hwFrame    = nil
local _rows       = {}
local _emptyLbl   = nil
local _clearAllBtn = nil
local _sizeLbl    = nil
local _reopenNote = nil   -- the note page's note when the window last closed on it

-- Select mode (ALL-301), as in Trash: rows tick, the footer swaps to
-- Clear selected | Select all | Cancel
local _multiMode  = false
local _multiSel   = {}    -- { [noteID] = true }
local _selectBtn, _clearSelBtn, _selAllBtn, _cancelSelBtn = nil, nil, nil, nil
local _entries    = {}    -- the rows' note ids, as last populated

--------------------------------------------------------------------------------
-- INTERNAL: count total slots across auto + manual
--------------------------------------------------------------------------------
local function SlotCount(id)
    local slots = BNB.HistoryGetSlots(id)
    local n = #slots.auto
    if slots.manual then n = n + 1 end
    return n
end

--------------------------------------------------------------------------------
-- INTERNAL: build one row frame for a note entry
--------------------------------------------------------------------------------

local function BuildRow(parent, note, id, yOff)
    local row = CreateFrame("Button", nil, parent)
    row:SetHeight(ROW_H)
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    row:SetPoint("TOPLEFT",  parent, "TOPLEFT",  0,         yOff)
    row:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0,         yOff)

    -- Hover highlight
    local hl = row:CreateTexture(nil, "BACKGROUND")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.05)
    hl:Hide()
    row:SetScript("OnEnter", function() hl:Show() end)
    row:SetScript("OnLeave", function() hl:Hide() end)

    -- Selection highlight (Select mode, ALL-301)
    local selHi = row:CreateTexture(nil, "BACKGROUND", nil, 1)
    selHi:SetAllPoints()
    selHi:SetColorTexture(0.20, 0.40, 0.20, 0.25)
    selHi:SetShown(_multiMode and _multiSel[id] == true)

    -- Icon
    local icon = row:CreateTexture(nil, "ARTWORK")
    icon:SetSize(ICON_SZ, ICON_SZ)
    icon:SetPoint("LEFT", row, "LEFT", ICON_X, 0)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    local iconTex = note.icon or DEFAULT_ICON
    if type(iconTex) == "number" or iconTex:find("^Interface") or iconTex:find("^%d+$") then
        icon:SetTexture(iconTex)
    else
        pcall(function() icon:SetAtlas(iconTex) end)
    end
    -- The note's icon frame, as the note list and Trash draw it (ALL-296)
    if BNB.ApplyIconFrame then BNB.ApplyIconFrame(icon, note, ICON_SZ) end

    -- Title
    local titleLbl = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    titleLbl:SetPoint("TOPLEFT",  row, "TOPLEFT", TEXT_LEFT,   -4)
    titleLbl:SetPoint("TOPRIGHT", row, "TOPRIGHT", -4, -4)
    titleLbl:SetJustifyH("LEFT")
    titleLbl:SetHeight(16)
    titleLbl:SetText(note.title or L["HW_UNTITLED"])

    -- Slot count
    local n   = SlotCount(id)
    local sub = n == 1 and L["HW_SNAPSHOT_ONE"] or string.format(L["HW_SNAPSHOT_N_FMT"], n)
    local subLbl = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    subLbl:SetPoint("TOPLEFT",  row, "TOPLEFT", TEXT_LEFT,   -22)
    subLbl:SetPoint("TOPRIGHT", row, "TOPRIGHT", -4, -22)
    subLbl:SetJustifyH("LEFT")
    subLbl:SetHeight(14)
    subLbl:SetTextColor(0.55, 0.55, 0.55)
    subLbl:SetText(sub)

    -- Size
    local sz = BNB.HistoryFormatSize(BNB.HistoryNoteSize(id))
    local szLbl = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    szLbl:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -4, 6)
    szLbl:SetHeight(12)
    szLbl:SetJustifyH("RIGHT")
    szLbl:SetTextColor(0.40, 0.40, 0.40)
    szLbl:SetText(sz)

    -- Bottom separator
    local sep = row:CreateTexture(nil, "ARTWORK")
    sep:SetHeight(1)
    sep:SetPoint("BOTTOMLEFT",  row, "BOTTOMLEFT",  0, 0)
    sep:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 0)
    sep:SetColorTexture(0.22, 0.22, 0.25, 1)

    row:SetScript("OnClick", function(self, mouseBtn)
        if _multiMode then
            if mouseBtn ~= "LeftButton" then return end
            if _multiSel[id] then _multiSel[id] = nil else _multiSel[id] = true end
            selHi:SetShown(_multiSel[id] == true)
            if _clearSelBtn then _clearSelBtn:SetEnabled(next(_multiSel) ~= nil) end
            return
        end
        if mouseBtn == "RightButton" then
            BNB.ContextMenu.Open(row, function(root)   -- ALL-148
                root:CreateButton(L["HISTORY_CTX_VIEW"], function()
                    if BNB.OpenNoteHistoryPanel then BNB.OpenNoteHistoryPanel(id) end
                end)
                root:CreateButton(L["HW_CTX_OPEN_EDITOR"], function()
                    if BNB.mainFrame then
                        BNB.mainFrame:Show()
                        if BNB.SelectNote      then BNB.SelectNote(id) end
                    end
                end)
                root:CreateDivider()
                root:CreateButton(L["HW_CTX_CLEAR_NOTE"], function()
                    local title = note.title and note.title ~= "" and note.title or L["HW_UNTITLED"]
                    StaticPopupDialogs["BNB_HISTORY_CLEAR_NOTE"] = {
                        text           = string.format(L["HW_CLEAR_NOTE_CONFIRM_FMT"], title),
                        button1        = L["DELETE"],
                        button2        = L["CANCEL"],
                        OnAccept       = function()
                            BNB.HistoryDeleteAuto(id)
                            BNB.RefreshHistoryWindow()
                            BNB.RefreshNoteHistoryPanel()
                        end,
                        timeout        = 0,
                        whileDead      = true,
                        hideOnEscape   = true,
                        preferredIndex = 3,
                    }
                    StaticPopup_Show("BNB_HISTORY_CLEAR_NOTE")
                end, { danger = true })   -- irreversible = red (Dukul)
            end)
        else
            if BNB.OpenNoteHistoryPanel then
                BNB.OpenNoteHistoryPanel(id)
            end
        end
    end)

    return row
end

--------------------------------------------------------------------------------
-- Select mode (ALL-301): swaps the footer and redraws the rows
--------------------------------------------------------------------------------
local function SetHistoryMultiMode(on)
    _multiMode = on and true or false
    _multiSel  = {}
    if _clearAllBtn  then _clearAllBtn:SetShown(not _multiMode) end
    if _selectBtn    then _selectBtn:SetShown(not _multiMode) end
    if _sizeLbl      then _sizeLbl:SetShown(not _multiMode) end
    if _clearSelBtn  then _clearSelBtn:SetShown(_multiMode); _clearSelBtn:SetEnabled(false) end
    if _selAllBtn    then _selAllBtn:SetShown(_multiMode) end
    if _cancelSelBtn then _cancelSelBtn:SetShown(_multiMode) end
    BNB.RefreshHistoryWindow()
end

-- "Clear selected": the same clear as Clear all (automatic snapshots; a manual
-- restore point is kept), for the ticked notes, after one confirm with the count
local function ClearSelectedConfirm()
    local ids = {}
    for id in pairs(_multiSel) do ids[#ids + 1] = id end
    if #ids == 0 then return end
    StaticPopupDialogs["BNB_HISTORY_CLEAR_SEL"] = StaticPopupDialogs["BNB_HISTORY_CLEAR_SEL"] or {
        text = L["HW_CLEAR_SEL_CONFIRM_FMT"],
        button1 = L["DELETE"], button2 = L["CANCEL"],
        OnAccept = function(self, data)
            if type(data) ~= "table" then return end
            for _, id in ipairs(data) do BNB.HistoryDeleteAuto(id) end
            SetHistoryMultiMode(false)
            if BNB.SyncHistoryBtnState then BNB.SyncHistoryBtnState() end
        end,
        timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3, showAlert = true,
    }
    StaticPopup_Show("BNB_HISTORY_CLEAR_SEL", tostring(#ids), nil, ids)
end

--------------------------------------------------------------------------------
-- PopulateHistoryWindow — rebuild the scroll list
--------------------------------------------------------------------------------
function BNB.PopulateHistoryWindow()
    if not _hwFrame then return end
    local child = _hwFrame._scrollChild
    if not child then return end

    -- Clear old rows
    for _, r in ipairs(_rows) do r:Hide(); r:SetParent(nil) end
    _rows = {}

    -- Collect notes with history, sorted by most recent snapshot timestamp
    local ndb = BNB.NotesDB()
    if not ndb or not ndb.notes then
        _emptyLbl:Show()
        child:SetHeight(40)
        if _clearAllBtn then _clearAllBtn:SetEnabled(false) end
        if _sizeLbl     then _sizeLbl:SetText("") end
        return
    end

    local entries = {}
    for id, note in pairs(ndb.notes) do
        if BNB.HistoryNoteHasAny(id) then
            -- Most recent timestamp across auto+manual
            local ts = 0
            if note.history and note.history[1] then
                ts = note.history[1].timestamp or 0
            end
            if note.manualSnapshot then
                ts = math.max(ts, note.manualSnapshot.timestamp or 0)
            end
            entries[#entries + 1] = { id = id, note = note, ts = ts }
        end
    end
    table.sort(entries, function(a, b) return a.ts > b.ts end)

    if #entries == 0 then
        _emptyLbl:Show()
        child:SetHeight(40)
        _entries = {}
        if _clearAllBtn then _clearAllBtn:SetEnabled(false) end
        if _selectBtn   then _selectBtn:SetEnabled(false) end
        if _sizeLbl     then _sizeLbl:SetText(L["HISTORY_SIZE_NONE"]) end
        return
    end
    if _selectBtn then _selectBtn:SetEnabled(true) end

    _emptyLbl:Hide()
    if _clearAllBtn then _clearAllBtn:SetEnabled(true) end
    _entries = {}
    for i, e in ipairs(entries) do _entries[i] = e.id end

    local yOff = 0
    for _, e in ipairs(entries) do
        local row = BuildRow(child, e.note, e.id, -yOff)
        _rows[#_rows + 1] = row
        yOff = yOff + ROW_H + ROW_GAP
    end
    child:SetHeight(math.max(yOff, 40))

    -- Update size label
    if _sizeLbl then
        local total = BNB.HistoryTotalSize()
        _sizeLbl:SetText(string.format(L["HISTORY_SIZE_TOTAL"], BNB.HistoryFormatSize(total)))
    end
end

-- The list page only: the note page refreshes itself (RefreshNoteHistoryPanel)
function BNB.RefreshHistoryWindow()
    if not _hwFrame or not _hwFrame:IsShown() or _hwFrame:PageKey() ~= "list" then return end
    BNB.PopulateHistoryWindow()
end

--------------------------------------------------------------------------------
-- BuildHistoryWindow — lazy-build on first open. One body for both modes
-- (CMP-02 S3): chrome, footer divider, drag and ESC entry from CreateToolWindow.
--------------------------------------------------------------------------------
local function BuildHistoryWindow()
    if _hwFrame then return _hwFrame end

    local f
    f = BNB.CreateToolWindow({
        name = "BigNoteBoxHistoryFrame", w = HW_W, h = 400,   -- height follows the main window
        title = L["HISTORY_WINDOW_TITLE"], strata = "HIGH", toplevel = true, escClose = true,
        pad = PAD, footH = BOTTOM_STRIP_H - 1, footR = PAD + 28,
        onClose = function() BNB.CloseHistoryWindow() end,
        -- Focus mode reopens the page the window closed on (ReopenHistoryWindow)
        -- Reads the frame from its argument: the builder's own Hide() runs
        -- this before `f` is assigned
        onHide = function(self)
            local np = self._pages.note
            _reopenNote = self:PageKey() == "note" and np and np._noteID or nil
            if _multiMode then SetHistoryMultiMode(false) end
        end,
    })
    local top = f._isSkin and BNB.TOOL_SKIN_TITLE_H or TITLE_H
    -- Root page: the list, filled on every show (back from a note included)
    local list = f:AddPage("list", { onShow = function() BNB.PopulateHistoryWindow() end })

    -- Scroll frame
    local sf = BNB.CreateScrollFrame(nil, list)
    sf:SetPoint("TOPLEFT",     f, "TOPLEFT",      PAD, -(top + 4))
    sf:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -28,   BOTTOM_STRIP_H)
    f._scrollFrame = sf

    if sf.ScrollBar then
        sf.ScrollBar:SetAlpha(0)
        sf:HookScript("OnScrollRangeChanged", function(_, _, yRange)
            sf.ScrollBar:SetAlpha((yRange or 0) > 1 and 1.0 or 0)
        end)
    end

    local child = CreateFrame("Frame", nil, sf)
    child:SetWidth(CONTENT_W); child:SetHeight(200)
    sf:SetScrollChild(child)
    f._scrollChild = child

    -- Empty state
    local emptyLbl = child:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    emptyLbl:SetPoint("TOP", child, "TOP", 0, -20)
    emptyLbl:SetWidth(CONTENT_W); emptyLbl:SetJustifyH("CENTER")
    emptyLbl:SetTextColor(0.4, 0.4, 0.4)
    emptyLbl:SetText(L["HISTORY_EMPTY"])
    emptyLbl:Hide()
    _emptyLbl = emptyLbl

    -- Clear all button
    local clearBtn = BNB.CreateButton(nil, list, L["HISTORY_CLEAR_ALL_BTN"], 140, 26)
    clearBtn:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", PAD, 10)
    clearBtn:SetEnabled(false)
    clearBtn:SetScript("OnClick", function()
        StaticPopup_Show("BNB_HISTORY_CLEAR_ALL")
    end)
    clearBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(L["HISTORY_CLEAR_ALL_TIP"], 1, 1, 1)
        GameTooltip:AddLine(L["HW_CANNOT_UNDO_TIP"], 0.8, 0.4, 0.4, true)
        GameTooltip:Show()
    end)
    clearBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    _clearAllBtn = clearBtn

    -- Select mode (ALL-301): Select | then Clear selected | Select all | Cancel
    local selectBtn = BNB.CreateButton(nil, list, L["MW_SELECT_BTN"], 72, 26)
    selectBtn:SetPoint("LEFT", clearBtn, "RIGHT", 6, 0)
    selectBtn:SetEnabled(false)
    selectBtn:SetScript("OnClick", function() SetHistoryMultiMode(true) end)
    selectBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(L["HW_SELECT_TIP"], 1, 1, 1)
        GameTooltip:Show()
    end)
    selectBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    _selectBtn = selectBtn

    local clearSelBtn = BNB.CreateButton(nil, list, L["HW_CLEAR_SEL_BTN"], 120, 26)
    clearSelBtn:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", PAD, 10)
    clearSelBtn:SetScript("OnClick", ClearSelectedConfirm)
    clearSelBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(L["HW_CLEAR_SEL_TIP"], 1, 1, 1)
        GameTooltip:AddLine(L["HW_CANNOT_UNDO_TIP"], 0.8, 0.4, 0.4, true)
        GameTooltip:Show()
    end)
    clearSelBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    clearSelBtn:Hide()
    _clearSelBtn = clearSelBtn

    local selAllBtn = BNB.CreateButton(nil, list, L["TAG_MGR_SELECT_ALL_BTN"], 80, 26)
    selAllBtn:SetPoint("LEFT", clearSelBtn, "RIGHT", 6, 0)
    selAllBtn:SetScript("OnClick", function()
        for _, id in ipairs(_entries) do _multiSel[id] = true end
        BNB.RefreshHistoryWindow()
        clearSelBtn:SetEnabled(next(_multiSel) ~= nil)
    end)
    selAllBtn:Hide()
    _selAllBtn = selAllBtn

    local cancelSelBtn = BNB.CreateButton(nil, list, L["CANCEL"], 68, 26)
    cancelSelBtn:SetPoint("LEFT", selAllBtn, "RIGHT", 6, 0)
    cancelSelBtn:SetScript("OnClick", function() SetHistoryMultiMode(false) end)
    cancelSelBtn:Hide()
    _cancelSelBtn = cancelSelBtn

    -- Size label
    local szLbl = list:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    szLbl:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -PAD - 28, 14)
    szLbl:SetJustifyH("RIGHT")
    szLbl:SetTextColor(0.45, 0.45, 0.45)
    _sizeLbl = szLbl

    -- The per-note page (UI/NoteHistoryPanel.lua)
    BNB._BuildNoteHistoryPage(f, top)

    -- StaticPopup for clear all
    if not StaticPopupDialogs["BNB_HISTORY_CLEAR_ALL"] then
        StaticPopupDialogs["BNB_HISTORY_CLEAR_ALL"] = {
            text          = L["HISTORY_CLEAR_ALL_CONFIRM"],
            button1       = L["HISTORY_OVERRIDE_OVERRIDE"],
            button2       = L["CANCEL"],
            OnAccept      = function()
                local ndb = BNB.NotesDB()
                if ndb and ndb.notes then
                    for id in pairs(ndb.notes) do
                        BNB.HistoryDeleteAuto(id)
                    end
                end
                BNB.RefreshHistoryWindow()
                BNB.SyncHistoryBtnState()
            end,
            timeout       = 0,
            whileDead     = true,
            hideOnEscape  = true,
            preferredIndex = 3,
        }
    end

    _hwFrame = f
    return f
end

--------------------------------------------------------------------------------
-- Height sync (mirrors TrashWindow pattern), every page (ALL-258)
--------------------------------------------------------------------------------
local function SyncHistoryHeight()
    if not _hwFrame or not BNB.mainFrame then return end
    local h = BNB.mainFrame:GetHeight()
    if h and h > 0 then _hwFrame:SetHeight(h) end
end

function BNB.HookHistoryHeightTracking()
    if not BNB.mainFrame then return end
    BNB.mainFrame:HookScript("OnSizeChanged", SyncHistoryHeight)
    BNB.mainFrame:HookScript("OnShow",        SyncHistoryHeight)
end

--------------------------------------------------------------------------------
-- Public toggle / open / close
--------------------------------------------------------------------------------
-- Opens the window on a page: "list", or "note" with the note id
-- (BNB.OpenNoteHistoryPanel). Extra arguments go to the page's onShow.
function BNB.ShowHistoryWindow(pageKey, ...)
    if InCombatLockdown() then BNB:Print(L["COMBAT_BLOCKED"]); return end
    local f = BuildHistoryWindow()
    -- Close Trash if open (per ESC-chain rules)
    local tw = _G["BigNoteBoxTrashFrame"]
    if tw and tw:IsShown() then tw:Hide() end
    if not f:IsShown() then
        SyncHistoryHeight()
        -- Side from Settings > Notes > Session History (ALL-269, right by default)
        if not BNB.PlaceBesideMain(f, BNB.WindowSide("historySide")) then
            f:ClearAllPoints()
            f:SetPoint("CENTER")
        end
        f:Show()
    end
    f:Raise()
    f:ShowPage(pageKey, ...)
end

function BNB.OpenHistoryWindow()
    BNB.ShowHistoryWindow("list")
end

-- Focus mode's reopen (MainWindow.lua WINDOWS): the page it closed on
function BNB.ReopenHistoryWindow()
    if _reopenNote then BNB.ShowHistoryWindow("note", _reopenNote)
    else BNB.ShowHistoryWindow("list") end
end

function BNB.CloseHistoryWindow()
    if _hwFrame then _hwFrame:Hide() end
end

function BNB.ToggleHistoryWindow()
    if InCombatLockdown() then BNB:Print(L["COMBAT_BLOCKED"]); return end
    if _hwFrame and _hwFrame:IsShown() then
        BNB.CloseHistoryWindow()
    else
        BNB.OpenHistoryWindow()
    end
end

function BNB.InitHistoryWindow()
    BNB.HookHistoryHeightTracking()
end

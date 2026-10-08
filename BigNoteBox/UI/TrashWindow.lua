-- BigNoteBox UI/TrashWindow.lua — Trash Browser
--
-- Rows as in Note History (ALL-299): icon, title, how long it has been in the
-- trash, size. A click opens the note's page; right-click = View / Restore / Delete.
-- Bottom strip (left->right): Empty Trash | Select; in Select mode
-- Restore selected | Delete selected | Select all | Cancel (ALL-300).
-- Info block (bottom-right): "Kept X days / X notes in trash"
--
-- Empty Trash and Delete selected confirm with a StaticPopup.
-- Two pages in one window (ALL-258): the list (root) and View, one trashed
-- note's title and body with Restore / Delete (a 3 s "Sure?" step) and, for a
-- rich note, a Markup / Note button (opens on Note); back arrow or ESC = the list.

local BNB = BigNoteBox
local L   = BNB.L

local DEFAULT_ICON = "Interface\\Icons\\INV_Misc_Note_06"

-- Layout constants
local TW_W           = BNB.SIDE_WINDOW_W   -- 400 (ALL-269)
local TITLE_H        = 32
local PAD            = 14
local ROW_H          = 56    -- as Note History's rows (ALL-299)
local ROW_GAP        = 4
local ICON_SZ        = 36
local ICON_X         = 6    -- room for an icon frame's left edge: at 0 the scroll frame cut it (ALL-332)
local CONTENT_W      = TW_W - PAD * 2 - 30   -- 30px scrollbar clearance
local BOTTOM_STRIP_H = 52

-- Module state
local _twFrame   = nil
local _rows      = {}
local _emptyLbl  = nil
local _emptyBtn      = nil
local _selectBtn     = nil   -- "Select" (normal mode only)
local _restoreSelBtn = nil   -- "Restore selected" (select mode only)
local _deleteSelBtn  = nil   -- "Delete selected"  (select mode only)
local _cancelSelBtn  = nil   -- "Cancel"            (select mode only)
local _selAllBtn     = nil   -- "Select all"        (select mode only, ALL-300)
local _infoLbl       = nil   -- "Kept X days\nX notes in trash" (bottom-right)
local _multiSel  = {}
local _multiMode = false
local _itemOrder = {}    -- { id, note } per row, as last populated (row index = position)

-- Date helper
local function FormatDeleted(ts)
    if not ts then return L["TW_TIME_UNKNOWN"] end
    local delta = time() - ts
    if delta < 60        then return L["TW_TIME_JUST_NOW"]
    elseif delta < 3600  then return string.format(L["TW_TIME_MIN_AGO_FMT"], math.floor(delta / 60))
    elseif delta < 86400 then return string.format(L["TW_TIME_HOUR_AGO_FMT"], math.floor(delta / 3600))
    elseif delta < 86400 * 2 then return L["TW_TIME_YESTERDAY"]
    else   return string.format(L["TW_TIME_DAY_AGO_FMT"], math.floor(delta / 86400))
    end
end

-- Multi-select toggle
local function SetTrashMultiMode(enabled)
    _multiMode = enabled
    _multiSel  = {}
    -- Normal-mode buttons: visible only when NOT selecting
    if _emptyBtn    then
        local ndb = BNB.NotesDB()
        local hasItems = ndb and ndb.trash and next(ndb.trash) ~= nil or false
        _emptyBtn:SetShown(not enabled)
        _emptyBtn:SetEnabled(not enabled and hasItems)
    end
    if _selectBtn   then _selectBtn:SetShown(not enabled) end
    -- Select-mode buttons: visible only when selecting
    if _restoreSelBtn then
        _restoreSelBtn:SetShown(enabled)
        _restoreSelBtn:SetEnabled(false)   -- enabled once ≥1 row is ticked
    end
    if _deleteSelBtn  then
        _deleteSelBtn:SetShown(enabled)
        _deleteSelBtn:SetEnabled(false)
    end
    if _cancelSelBtn  then _cancelSelBtn:SetShown(enabled) end
    if _selAllBtn     then _selAllBtn:SetShown(enabled) end
    if _infoLbl       then _infoLbl:SetShown(not enabled) end   -- the four buttons need the width
    BNB.RefreshTrashWindow()
end

-- A note's size as Note History counts it: title + body
local function NoteSize(note)
    local b = #(note.title or "") + #(note.body or "")
    if BNB.HistoryFormatSize then return BNB.HistoryFormatSize(b) end
    return b < 1024 and (b .. " B") or string.format("%.1f KB", b / 1024)
end

-- Enables the select-mode actions by the number of ticked rows
local function SyncSelButtons()
    local hasAny = next(_multiSel) ~= nil
    if _restoreSelBtn then _restoreSelBtn:SetEnabled(hasAny) end
    if _deleteSelBtn  then _deleteSelBtn:SetEnabled(hasAny)  end
end

-- Update the info block (retention + count)
local function UpdateInfoLbl(n)
    if not _infoLbl then return end
    local days = BigNoteBoxDB and BigNoteBoxDB.trashRetainDays
    if days == nil then days = 30 end
    local line1 = days == 0 and L["TW_INFO_DISABLED"]
               or days == 1 and L["TW_INFO_KEPT_1_DAY"]
               or              string.format(L["TW_INFO_KEPT_DAYS_FMT"], days)
    local line2
    if n == 0 then     line2 = L["TW_INFO_EMPTY"]
    elseif n == 1 then line2 = L["TW_INFO_ONE_NOTE"]
    else               line2 = string.format(L["TW_INFO_N_NOTES_FMT"], n)
    end
    _infoLbl:SetText(line1 .. "\n" .. line2)
end

-- Thin local alias — real implementation lives in NoteManager as BNB.SyncTrashBtnState
-- so all trash-mutating paths (DeleteNote, RestoreNote, EmptyTrash) can call it
-- without depending on TrashWindow being loaded.  PopulateTrashWindow calls it too.
local function UpdateTrashBtnState()
    if BNB.SyncTrashBtnState then BNB.SyncTrashBtnState() end
end

-- "Delete selected": permanently removes the ticked rows, after a confirm.
-- It used to purge on the first click with no way back (found with ALL-58).
-- ids: a list to delete instead of the ticked rows (a row's right-click Delete)
local function PurgeSelectedConfirm(ids)
    if not ids then
        ids = {}
        for id in pairs(_multiSel) do ids[#ids + 1] = id end
    end
    if #ids == 0 then return end
    if not StaticPopupDialogs["BNB_TRASH_PURGE_SEL"] then
        StaticPopupDialogs["BNB_TRASH_PURGE_SEL"] = {
            text = L["POPUP_TRASH_PURGE_SEL"],
            button1 = L["BTN_DELETE_CONFIRM"],
            button2 = L["CANCEL"],
            OnAccept = function(self, data)
                local sel = data or self.data
                if type(sel) ~= "table" then return end
                BNB.PurgeTrashed(sel)
                SetTrashMultiMode(false)
            end,
            timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
            showAlert = true,
        }
    end
    local popup = StaticPopup_Show("BNB_TRASH_PURGE_SEL", tostring(#ids), nil, ids)
    if popup then popup.data = ids end
end

-- Row builder: a Button with backdrop, laid out as Note History's rows (ALL-299)
local function GetRow(parent, index)
    local row = _rows[index]
    if row then row:SetParent(parent); row:Show(); return row end

    -- No background or border, a divider under each row: exactly Note
    -- History's rows (Dukul, 2026-10-05; replaces ALL-272's see-through box)
    row = CreateFrame("Button", nil, parent)
    row:SetHeight(ROW_H)
    local sep = row:CreateTexture(nil, "ARTWORK")
    sep:SetHeight(1)
    sep:SetPoint("BOTTOMLEFT",  row, "BOTTOMLEFT",  0, 0)
    sep:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 0)
    sep:SetColorTexture(0.22, 0.22, 0.25, 1)
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    -- Hover, Select mode and focus-flash backgrounds (row art in normal mode)
    local hl = BNB.CreateListRowArt(row, "hover", { 1, 1, 1, 0.05 })
    row:SetScript("OnEnter", function() hl:Show() end)
    row:SetScript("OnLeave", function() hl:Hide() end)
    row:SetScript("OnHide",  function() hl:Hide() end)   -- a pooled row reused under the pointer
    row._selHi   = BNB.CreateListRowArt(row, "multi-selection", { 0.20, 0.40, 0.20, 0.25 })
    row._flashHi = BNB.CreateListRowArt(row, "selection",       { 0.20, 0.40, 0.20, 0.25 })

    -- Icon (its frame, if the note has one, comes from ApplyIconFrame)
    local icon = row:CreateTexture(nil, "ARTWORK", nil, 2)
    icon:SetSize(ICON_SZ, ICON_SZ)
    icon:SetPoint("LEFT", row, "LEFT", ICON_X, 0)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    row._icon = icon

    local textLeft = ICON_X + ICON_SZ + 10
    -- Title
    local titleLbl = row:CreateFontString(nil, "OVERLAY", "BNBFontNormal")
    titleLbl:SetPoint("TOPLEFT",  row, "TOPLEFT",  textLeft, -4)
    titleLbl:SetPoint("TOPRIGHT", row, "TOPRIGHT", -4, -4)
    titleLbl:SetJustifyH("LEFT")
    titleLbl:SetMaxLines(1); titleLbl:SetWordWrap(false)
    row._titleLbl = titleLbl

    -- How long it has been in the trash
    local dateLbl = row:CreateFontString(nil, "OVERLAY", "BNBFontNormalSmall")
    dateLbl:SetPoint("TOPLEFT", row, "TOPLEFT", textLeft, -22)
    dateLbl:SetJustifyH("LEFT")
    dateLbl:SetTextColor(0.55, 0.55, 0.55)
    row._dateLbl = dateLbl

    -- Size, bottom-right
    local sizeLbl = row:CreateFontString(nil, "OVERLAY", "BNBFontNormalSmall")
    sizeLbl:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -4, 6)
    sizeLbl:SetJustifyH("RIGHT")
    sizeLbl:SetTextColor(0.40, 0.40, 0.40)
    row._sizeLbl = sizeLbl

    _rows[index] = row
    return row
end

-- Populate / refresh
function BNB.RefreshTrashWindow()
    if not _twFrame or not _twFrame:IsShown() then return end
    BNB.PopulateTrashWindow()
end

-- Every change to the trash (delete to trash, restore, purge, empty) sends
-- TrashChanged (Core/NoteManager.lua): the window and the toolbar button
-- follow it, once per frame, so a restore of 20 selected notes is one redraw.
local function FollowTrash()
    -- The note on the View page left the trash (restored, purged, expired)
    local vp = _twFrame and _twFrame._pages.view
    if vp and vp:IsVisible() then
        local ndb = BNB.NotesDB()
        if not (ndb and ndb.trash and ndb.trash[vp._noteID]) then _twFrame:PageBack() end
    end
    BNB.RefreshTrashWindow()
    UpdateTrashBtnState()
end
BNB.RegisterMessage("TrashWindow", "TrashChanged", function()
    BNB.Debounce("trashWindow", 0, FollowTrash)
end)

-- The View page (ALL-258; was the BNBTrashViewPopup window): a trashed note's
-- title as the heading and its body, with Restore and Delete (the rows' 3 s
-- "Sure?" step). Either action goes back to the list: Restore and Sure? by
-- TrashChanged (FollowTrash), since the note leaves the trash.
-- ShowPage("view", id, note) fills it.
local function BuildViewPage(f, top)
    local page
    page = f:AddPage("view", {
        top = top, pad = PAD, padR = PAD + 28,
        onShow = function(p, id, note)
            p._noteID = id
            p._note = note
            p._markup = false   -- a rich note opens on Note (ALL-299)
            p:SetHeading((note.title and note.title ~= "") and note.title or L["TW_VIEW_UNTITLED"])
            p._showBody()
            if p._sureTimer then p._sureTimer:Cancel(); p._sureTimer = nil end
            p._sureBtn:Hide()
        end,
    })

    local sf = BNB.CreateScrollFrame(nil, page)
    sf:SetPoint("TOPLEFT",     f, "TOPLEFT",      PAD, -(page.top + 4))
    sf:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -28,   BOTTOM_STRIP_H)
    if sf.ScrollBar then
        sf.ScrollBar:SetAlpha(0)
        sf:HookScript("OnScrollRangeChanged", function(_, _, yRange)
            sf.ScrollBar:SetAlpha((yRange or 0) > 1 and 1.0 or 0)
        end)
    end
    page._sf = sf
    local ct = CreateFrame("Frame", nil, sf)
    ct:SetWidth(CONTENT_W); sf:SetScrollChild(ct)
    local bodyFs = ct:CreateFontString(nil, "OVERLAY", "BNBFontNormalSmall")
    bodyFs:SetPoint("TOPLEFT"); bodyFs:SetWidth(CONTENT_W)
    bodyFs:SetJustifyH("LEFT"); bodyFs:SetWordWrap(true)
    bodyFs:SetTextColor(0.85, 0.85, 0.85, 1)
    page._bodyFs = bodyFs; page._bodyCt = ct

    -- A rich note is shown rendered (Note) or as its source (Markup), one
    -- button flipping between them (ALL-299). Built on first use.
    local AM = BNB.AdvancedMode
    local rf
    local toggleBtn = BNB.CreateButton(nil, page, L["NE_RICH_TAB_MARKUP"], 76, 26)
    toggleBtn:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -PAD - 28, 14)
    toggleBtn:Hide()
    page._showBody = function()
        local note = page._note or {}
        local rich = AM and AM.ToHTML and AM.IsRich(note) and true or false   -- Rich Notes off = plain (ALL-343)
        local html = rich and not page._markup
        if html and not rf then
            rf = AM.CreateRenderFrame(nil, ct)
            rf:SetPoint("TOPLEFT")
            rf:SetWidth(CONTENT_W)
        end
        local h
        if html then
            local sz = note.fontSize or (BigNoteBoxDB and BigNoteBoxDB.fontSize) or BNB.DEFAULTS.fontSize
            AM.ApplyFontsToRenderFrame(rf, sz, AM.OutlineFlagStr(note.fontOutline))
            rf:SetHTML(AM.ToHTML(note.body or "", sz))
            rf:Show(); bodyFs:Hide()
            h = rf:GetHeight()
        else
            if rf then rf:Hide() end
            bodyFs:SetText(note.body or "")
            bodyFs:Show()
            h = bodyFs:GetStringHeight()
        end
        ct:SetHeight(math.max(h or 0, 1))
        sf:SetVerticalScroll(0)
        -- The button names the view it switches to
        toggleBtn:SetText(page._markup and L["NE_RICH_TAB_NOTE"] or L["NE_RICH_TAB_MARKUP"])
        toggleBtn:SetShown(rich)
    end
    toggleBtn:SetScript("OnClick", function()
        page._markup = not page._markup
        page._showBody()
    end)

    local restoreBtn = BNB.CreateButton(nil, page, L["TW_ROW_RESTORE_BTN"], 110, 26)
    restoreBtn:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", PAD, 14)
    restoreBtn:SetScript("OnClick", function()
        if BNB.RestoreNote then BNB.RestoreNote(page._noteID) end
    end)

    local delBtn = BNB.CreateButton(nil, page, L["TW_ROW_DELETE_BTN"], 72, 26)
    delBtn:SetPoint("LEFT", restoreBtn, "RIGHT", 6, 0)
    delBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(L["TW_CANNOT_UNDO_TIP"], 0.8, 0.4, 0.4, true)
        GameTooltip:Show()
    end)
    delBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    local sureBtn = BNB.CreateButton(nil, page, L["TW_ROW_SURE_BTN"], 60, 26)
    sureBtn:SetPoint("LEFT", delBtn, "RIGHT", 4, 0)
    sureBtn:Hide()
    page._sureBtn = sureBtn

    delBtn:SetScript("OnClick", function()
        sureBtn:Show()
        if page._sureTimer then page._sureTimer:Cancel() end
        page._sureTimer = C_Timer.NewTimer(3, function()
            sureBtn:Hide(); page._sureTimer = nil
        end)
    end)
    sureBtn:SetScript("OnClick", function()
        if page._sureTimer then page._sureTimer:Cancel(); page._sureTimer = nil end
        BNB.PurgeTrashed({ page._noteID })
    end)
    return page
end

function BNB.PopulateTrashWindow()
    if not _twFrame then return end

    -- Never cache ndb across calls: always read it through BNB.NotesDB() (ALL-129)
    local ndb = BNB.NotesDB()
    if not ndb then return end
    if not ndb.trash then ndb.trash = {} end

    local items = {}
    for id, note in pairs(ndb.trash) do
        items[#items + 1] = { id = id, note = note }
    end
    table.sort(items, function(a, b)
        return (a.note.deletedAt or 0) > (b.note.deletedAt or 0)
    end)
    _itemOrder = items

    local n = #items
    UpdateInfoLbl(n)
    UpdateTrashBtnState()

    for _, r in ipairs(_rows) do if r then r:Hide() end end

    if _emptyLbl then _emptyLbl:SetShown(n == 0) end
    if _emptyBtn then _emptyBtn:SetEnabled(n > 0 and not _multiMode) end

    if _selectBtn then
        if n == 0 then
            _selectBtn:SetEnabled(false)
            if _multiMode then
                _multiMode = false; _multiSel = {}
            end
        else
            _selectBtn:SetEnabled(true)
        end
        _selectBtn:SetShown(not _multiMode)
    end
    -- Keep select-mode buttons in sync with mode on every refresh
    if _restoreSelBtn then _restoreSelBtn:SetShown(_multiMode) end
    if _deleteSelBtn  then _deleteSelBtn:SetShown(_multiMode)  end
    if _cancelSelBtn  then _cancelSelBtn:SetShown(_multiMode)  end
    if _selAllBtn     then _selAllBtn:SetShown(_multiMode)     end
    if _infoLbl       then _infoLbl:SetShown(not _multiMode)   end
    if _emptyBtn      then _emptyBtn:SetShown(not _multiMode)  end

    local scrollChild = _twFrame._scrollChild
    if not scrollChild then return end

    local totalH = 0
    for i, item in ipairs(items) do
        local row = GetRow(scrollChild, i)
        local note = item.note
        local id   = item.id

        row:ClearAllPoints()
        row:SetPoint("TOPLEFT",  scrollChild, "TOPLEFT",  0, -totalH)
        row:SetPoint("TOPRIGHT", scrollChild, "TOPRIGHT", 0, -totalH)

        -- Icon
        local iconPath = (note.icon and note.icon ~= "") and note.icon or DEFAULT_ICON
        row._icon:SetTexture(iconPath)
        if BNB.ApplyIconFrame then BNB.ApplyIconFrame(row._icon, note, ICON_SZ) end

        -- Title
        row._titleLbl:SetText(
            (note.title and note.title ~= "") and note.title or L["TW_UNTITLED"])
        -- The note's own title colour, as in the note list; gold without one (ALL-272)
        local tc = note.titleColor
        if tc and tc.r then row._titleLbl:SetTextColor(tc.r, tc.g, tc.b, 1)
        else BNB.SetHeaderColor(row._titleLbl) end

        -- In the trash since, and size (ALL-299)
        row._dateLbl:SetText(string.format(L["TW_ROW_DELETED_FMT"], FormatDeleted(note.deletedAt)))
        row._sizeLbl:SetText(NoteSize(note))

        -- Selection highlight
        if row._selHi then
            row._selHi:SetShown(_multiMode and _multiSel[id] == true)
        end

        -- Select mode: a click ticks the row. Otherwise a click opens the
        -- note's page and right-click offers View / Restore / Delete (ALL-299)
        row:SetScript("OnClick", function(self, button)
            if _multiMode then
                if button ~= "LeftButton" then return end
                if _multiSel[id] then _multiSel[id] = nil else _multiSel[id] = true end
                if row._selHi then row._selHi:SetShown(_multiSel[id] == true) end
                SyncSelButtons()
            elseif button == "RightButton" then
                BNB.ContextMenu.Open(row, function(root)
                    root:CreateButton(L["TW_ROW_VIEW_BTN"], function()
                        if item.note then _twFrame:ShowPage("view", id, item.note) end
                    end)
                    root:CreateButton(L["TW_ROW_RESTORE_BTN"], function()
                        if BNB.RestoreNote then BNB.RestoreNote(id) end
                    end)
                    root:CreateDivider()
                    root:CreateButton(L["TW_ROW_DELETE_BTN"], function()
                        PurgeSelectedConfirm({ id })   -- the same confirm as Delete selected
                    end, { danger = true })   -- irreversible = red (Dukul)
                end)
            elseif item.note then
                _twFrame:ShowPage("view", id, item.note)
            end
        end)

        totalH = totalH + ROW_H + ROW_GAP
    end

    -- GetHeight() on the scroll frame can return 0 before the layout engine has
    -- committed geometry (first open).  Fall back to computing the available
    -- height from the parent frame's configured height minus fixed chrome.
    local minH = _twFrame._scrollFrame and _twFrame._scrollFrame:GetHeight() or 0
    if minH < 10 then
        minH = math.max(200, (_twFrame:GetHeight() or 400) - TITLE_H - BOTTOM_STRIP_H - 36)
    end
    scrollChild:SetHeight(math.max(minH, totalH > 0 and totalH or 40))

    -- Keep action buttons in sync with current selection count
    if _multiMode then SyncSelButtons() end

    -- Auto-close when the last item is removed
    if n == 0 and _twFrame:IsShown() then
        if _multiMode then SetTrashMultiMode(false) end
        _twFrame:Hide()
    end
end

-- Build window (once). One body for both modes (CMP-02 S3): the chrome,
-- footer divider, drag, ESC entry and Forever glow come from CreateToolWindow.
local function BuildTrashWindow()
    if _twFrame then return _twFrame end

    local f = BNB.CreateToolWindow({
        name = "BigNoteBoxTrashFrame", w = TW_W, h = 400,   -- height follows the main window
        title = L["TW_TITLE"], strata = "HIGH", toplevel = true, escClose = true,
        pad = PAD, footH = BOTTOM_STRIP_H - 1, footR = PAD + 28,
        onClose = function()
            if _multiMode then SetTrashMultiMode(false) end
            _twFrame:Hide()
        end,
        -- Leave select mode on any hide (ESC, main window close), not only the close button
        onHide = function()
            if _multiMode then SetTrashMultiMode(false) end
        end,
    })
    local top = f._isSkin and BNB.TOOL_SKIN_TITLE_H or TITLE_H
    -- Root page: the list, filled on every show (back from View included)
    local list = f:AddPage("list", { onShow = function() BNB.PopulateTrashWindow() end })

    -- Scroll frame (28px right clearance for scrollbar)
    local sf = BNB.CreateScrollFrame(nil, list)
    sf:SetPoint("TOPLEFT",     f, "TOPLEFT",      PAD, -(top + 4))
    sf:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -28,   BOTTOM_STRIP_H)
    f._scrollFrame = sf

    -- Hide scrollbar when there is nothing to scroll, same as sticky notes.
    -- Uses alpha only — never Show/Hide, which fights ScrollFrameTemplate.
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

    -- Empty state label
    local emptyLbl = child:CreateFontString(nil, "OVERLAY", "BNBFontNormal")
    emptyLbl:SetPoint("TOP", child, "TOP", 0, -20)
    emptyLbl:SetWidth(CONTENT_W); emptyLbl:SetJustifyH("CENTER")
    emptyLbl:SetTextColor(0.4, 0.4, 0.4); emptyLbl:SetText(L["TW_EMPTY_STATE"])
    emptyLbl:Hide()
    _emptyLbl = emptyLbl

    -- ── Normal mode: Empty Trash | Select ────────────────────────────────────
    local emptyBtn = BNB.CreateButton(nil, list, L["TW_EMPTY_BTN"], 110, 26)
    emptyBtn:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", PAD, 14)
    emptyBtn:SetEnabled(false)
    emptyBtn:SetScript("OnClick", function() StaticPopup_Show("BNB_EMPTY_TRASH") end)
    emptyBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(L["TW_EMPTY_TIP"], 1, 1, 1)
        GameTooltip:AddLine(L["TW_CANNOT_UNDO_TIP"], 0.8, 0.4, 0.4, true)
        GameTooltip:Show()
    end)
    emptyBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    _emptyBtn = emptyBtn

    local selectBtn = BNB.CreateButton(nil, list, L["MW_SELECT_BTN"], 72, 26)
    selectBtn:SetPoint("LEFT", emptyBtn, "RIGHT", 6, 0)
    selectBtn:SetEnabled(false)
    selectBtn:SetScript("OnClick", function() SetTrashMultiMode(true) end)
    selectBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(L["TW_SELECT_TIP"], 1, 1, 1)
        GameTooltip:Show()
    end)
    selectBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    _selectBtn = selectBtn

    -- ── Select mode: Restore selected | Delete selected | Cancel ──────────────
    local restoreSelBtn = BNB.CreateButton(nil, list, L["TW_RESTORE_SEL_BTN"], 104, 26)
    restoreSelBtn:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", PAD, 14)
    restoreSelBtn:SetEnabled(false)
    restoreSelBtn:SetScript("OnClick", function()
        local ids = {}
        for id in pairs(_multiSel) do ids[#ids + 1] = id end
        for _, id in ipairs(ids) do
            if BNB.RestoreNote then BNB.RestoreNote(id) end
        end
        SetTrashMultiMode(false)
    end)
    restoreSelBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(L["TW_RESTORE_SEL_TIP"], 1, 1, 1)
        GameTooltip:Show()
    end)
    restoreSelBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    restoreSelBtn:Hide()
    _restoreSelBtn = restoreSelBtn

    local deleteSelBtn = BNB.CreateButton(nil, list, L["TW_DELETE_SEL_BTN"], 100, 26)
    deleteSelBtn:SetPoint("LEFT", restoreSelBtn, "RIGHT", 6, 0)
    deleteSelBtn:SetEnabled(false)
    deleteSelBtn:SetScript("OnClick", function() PurgeSelectedConfirm() end)
    deleteSelBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(L["TW_DELETE_SEL_TIP"], 1, 1, 1)
        GameTooltip:AddLine(L["TW_CANNOT_UNDO_TIP"], 0.8, 0.4, 0.4, true)
        GameTooltip:Show()
    end)
    deleteSelBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    deleteSelBtn:Hide()
    _deleteSelBtn = deleteSelBtn

    -- Select all (ALL-300): ticks every row
    local selAllBtn = BNB.CreateButton(nil, list, L["TAG_MGR_SELECT_ALL_BTN"], 76, 26)
    selAllBtn:SetPoint("LEFT", deleteSelBtn, "RIGHT", 6, 0)
    selAllBtn:SetScript("OnClick", function()
        for _, item in ipairs(_itemOrder) do _multiSel[item.id] = true end
        BNB.RefreshTrashWindow()
    end)
    selAllBtn:Hide()
    _selAllBtn = selAllBtn

    local cancelSelBtn = BNB.CreateButton(nil, list, L["CANCEL"], 62, 26)
    cancelSelBtn:SetPoint("LEFT", selAllBtn, "RIGHT", 6, 0)
    cancelSelBtn:SetScript("OnClick", function() SetTrashMultiMode(false) end)
    cancelSelBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(L["TW_CANCEL_SEL_TIP"], 1, 1, 1)
        GameTooltip:Show()
    end)
    cancelSelBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    cancelSelBtn:Hide()
    _cancelSelBtn = cancelSelBtn

    -- Info block: "Kept X days\nX notes in trash" — bottom-right of strip
    local infoLbl = list:CreateFontString(nil, "OVERLAY", "BNBFontNormalSmall")
    infoLbl:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -PAD - 28, 10)
    infoLbl:SetJustifyH("RIGHT")
    infoLbl:SetTextColor(0.45, 0.45, 0.45)
    _infoLbl = infoLbl

    BuildViewPage(f, top)

    _twFrame = f
    return f
end

-- Height tracking (mirrors Config pattern)
local function SyncTrashHeight()
    if not _twFrame or not BNB.mainFrame then return end
    local h = BNB.mainFrame:GetHeight()
    if h and h > 0 then _twFrame:SetHeight(h) end
end

function BNB.HookTrashHeightTracking()
    if not BNB.mainFrame then return end
    BNB.mainFrame:HookScript("OnSizeChanged", SyncTrashHeight)
    BNB.mainFrame:HookScript("OnShow",        SyncTrashHeight)
end

local TrashFrame = BuildTrashWindow

local function ShowTrashWindow(f)
    SyncTrashHeight()
    -- Side from Settings > Notes > Trash (ALL-269, right by default)
    if not BNB.PlaceBesideMain(f, BNB.WindowSide("trashSide")) then
        f:ClearAllPoints()
        f:SetPoint("CENTER")
    end
    f:Show()
    f:ShowPage("list")   -- fills it
end

-- Public API
function BNB.ToggleTrashWindow()
    if InCombatLockdown() then BNB:Print(L["COMBAT_BLOCKED"]); return end
    local f = TrashFrame()
    if f:IsShown() then
        if _multiMode then SetTrashMultiMode(false) end
        f:Hide(); return
    end
    ShowTrashWindow(f)
end

-- ESC reaches this window through the main window's key handler
-- (MainWindow.lua OnEscapeKey). Opened on its own (the Oracle bar's `b`
-- prefix) the main window is closed, so that cascade never runs, and
-- UISpecialFrames is not reliable on Forever. Our own handler closes it
-- then (the View page goes back first), and steps aside while the main window is shown,
-- so the cascade order is untouched. Same pattern as UI/ReferenceBox.lua
-- OpenReferenceBox (ALL-69.2).
local function HookStandaloneEscape(f)
    if f._escHooked then return end
    f._escHooked = true
    BNB.AttachEscClose(f, function(self)
        if self:PageBack() then return end
        if _multiMode then SetTrashMultiMode(false) end
        self:Hide()
    end)
end

-- Scrolls the list to a trashed note and flashes its row for a moment.
local function FocusTrashItem(id)
    local idx
    for i, item in ipairs(_itemOrder) do
        if item.id == id then idx = i; break end
    end
    if not (idx and _twFrame) then return end
    local sf, row = _twFrame._scrollFrame, _rows[idx]
    -- A tick later: on the first open the scroll range is still 0.
    C_Timer.After(0, function()
        if not (sf and _twFrame:IsShown()) then return end
        sf:UpdateScrollChildRect()
        local want = (idx - 1) * (ROW_H + ROW_GAP)
        sf:SetVerticalScroll(math.min(want, sf:GetVerticalScrollRange() or 0))
    end)
    if row and row._flashHi and not _multiMode then
        row._flashHi:Show()
        C_Timer.After(2.5, function() row._flashHi:Hide() end)
    end
end

-- Opens the Trash window if it is not already showing (never closes it);
-- used by the Oracle bar's `b` prefix (ALL-69.2), which needs "open", not
-- "toggle". focusID: a trashed note to scroll to and flash.
function BNB.OpenTrashWindow(focusID)
    if InCombatLockdown() then BNB:Print(L["COMBAT_BLOCKED"]); return end
    local f = TrashFrame()
    HookStandaloneEscape(f)
    if not f:IsShown() then ShowTrashWindow(f) else f:ShowPage("list") end
    f:Raise()
    if focusID then FocusTrashItem(focusID) end
end

function BNB.InitTrashWindow()
    BNB.HookTrashHeightTracking()
end

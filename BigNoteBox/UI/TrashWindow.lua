-- BigNoteBox UI/TrashWindow.lua — Trash Browser
--
-- Row style matches NoteList: icon left, title + 3-line preview right, date top-right.
-- Bottom strip (left→right): Empty Trash | Select/Cancel
-- Info block (bottom-right): "Kept X days / X notes in trash"
--
-- Empty Trash uses a StaticPopup for confirmation (same pattern as Reset).
-- Per-row Delete shows an inline "Sure?" button for 3 seconds.
-- Select toggles multi-select mode; label becomes "Cancel" to exit without restoring.
-- "Restore" and "Restore selected" are the explicit restore actions.

local BNB = BigNoteBox
local L   = BNB.L

local DEFAULT_ICON = "Interface\\Icons\\INV_Misc_Note_06"

-- Layout constants
local TW_W           = 400
local TITLE_H        = 32
local PAD            = 14
local ROW_H          = 86
local ROW_GAP        = 4
local ICON_SZ        = 42
local TEXT_LEFT      = PAD + ICON_SZ + 10
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
local _infoLbl       = nil   -- "Kept X days\nX notes in trash" (bottom-right)
local _multiSel  = {}
local _multiMode = false

-- Date helper
local function FormatDeleted(ts)
    if not ts then return "Unknown" end
    local delta = time() - ts
    if delta < 60        then return "Just now"
    elseif delta < 3600  then return math.floor(delta / 60)   .. "m ago"
    elseif delta < 86400 then return math.floor(delta / 3600) .. "h ago"
    elseif delta < 86400 * 2 then return "Yesterday"
    else   return math.floor(delta / 86400) .. "d ago"
    end
end

-- Multi-select toggle
local function SetTrashMultiMode(enabled)
    _multiMode = enabled
    _multiSel  = {}
    -- Normal-mode buttons: visible only when NOT selecting
    if _emptyBtn    then
        local hasItems = false
        local ndb = BigNoteBoxNotesDB
        if ndb and ndb.trash then
            for _ in pairs(ndb.trash) do hasItems = true; break end
        end
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
    BNB.RefreshTrashWindow()
end

-- Update the info block (retention + count)
local function UpdateInfoLbl(n)
    if not _infoLbl then return end
    local days = BigNoteBoxDB and BigNoteBoxDB.trashRetainDays
    if days == nil then days = 30 end
    local line1 = days == 0 and "Trash disabled"
               or days == 1 and "Kept 1 day"
               or              "Kept " .. days .. " days"
    local line2
    if n == 0 then     line2 = "Empty"
    elseif n == 1 then line2 = "1 note in trash"
    else               line2 = n .. " notes in trash"
    end
    _infoLbl:SetText(line1 .. "\n" .. line2)
end

-- Thin local alias — real implementation lives in NoteManager as BNB.SyncTrashBtnState
-- so all trash-mutating paths (DeleteNote, RestoreNote, EmptyTrash) can call it
-- without depending on TrashWindow being loaded.  PopulateTrashWindow calls it too.
local function UpdateTrashBtnState()
    if BNB.SyncTrashBtnState then BNB.SyncTrashBtnState() end
end

-- Row builder — Button with backdrop, matching NoteList style
local function GetRow(parent, index)
    local row = _rows[index]
    if row then row:SetParent(parent); row:Show(); return row end

    row = BNB.CreateBackdropFrame("Button", nil, parent)
    BNB.SetBackdrop(row, 0.07, 0.07, 0.09, 0.55, 0.22, 0.22, 0.26, 1)
    row:SetHeight(ROW_H)
    row:RegisterForClicks("LeftButtonUp")

    -- Selection highlight
    local selHi = row:CreateTexture(nil, "ARTWORK", nil, 1)
    selHi:SetAllPoints()
    selHi:SetColorTexture(0.20, 0.40, 0.20, 0.25)
    selHi:Hide()
    row._selHi = selHi

    -- Icon
    local icon = row:CreateTexture(nil, "ARTWORK")
    icon:SetSize(ICON_SZ, ICON_SZ)
    icon:SetPoint("LEFT", row, "LEFT", PAD, 0)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    row._icon = icon

    -- Icon border
    local iconBorder = row:CreateTexture(nil, "OVERLAY")
    iconBorder:SetSize(ICON_SZ + 2, ICON_SZ + 2)
    iconBorder:SetPoint("CENTER", icon, "CENTER", 0, 0)
    iconBorder:SetTexture("Interface\\Common\\WhiteIconFrame")
    row._iconBorder = iconBorder

    -- Title — full width, no right truncation needed since date is no longer beside it
    local titleLbl = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    titleLbl:SetPoint("TOPLEFT",  row, "TOPLEFT",  TEXT_LEFT, -8)
    titleLbl:SetPoint("TOPRIGHT", row, "TOPRIGHT", -8, -8)
    titleLbl:SetJustifyH("LEFT")
    titleLbl:SetMaxLines(1); titleLbl:SetWordWrap(false)
    row._titleLbl = titleLbl

    -- Deletion date — bottom-right corner, same baseline as action buttons
    local dateLbl = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    dateLbl:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -8, 8)
    dateLbl:SetJustifyH("RIGHT")
    dateLbl:SetTextColor(0.50, 0.50, 0.50)
    row._dateLbl = dateLbl

    -- Body preview (3 lines) — stops above the bottom action strip
    local previewLbl = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    previewLbl:SetPoint("TOPLEFT",  row, "TOPLEFT",  TEXT_LEFT, -24)
    previewLbl:SetPoint("TOPRIGHT", row, "TOPRIGHT", -8, -24)
    previewLbl:SetPoint("BOTTOM",   row, "BOTTOM",    0,  28)
    previewLbl:SetJustifyH("LEFT")
    previewLbl:SetJustifyV("TOP")
    previewLbl:SetMaxLines(3); previewLbl:SetWordWrap(true)
    previewLbl:SetTextColor(0.55, 0.55, 0.55)
    row._previewLbl = previewLbl

    -- Action buttons (bottom of row): View | Restore | Delete | Sure?
    local viewBtn = BNB.CreateButton(nil, row, "View", 52, 20)
    viewBtn:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", TEXT_LEFT, 6)
    row._viewBtn = viewBtn

    local restoreBtn = BNB.CreateButton(nil, row, "Restore", 72, 20)
    restoreBtn:SetPoint("LEFT", viewBtn, "RIGHT", 6, 0)
    row._restoreBtn = restoreBtn

    local permDelBtn = BNB.CreateButton(nil, row, "|cffff4444Delete|r", 60, 20)
    permDelBtn:SetPoint("LEFT", restoreBtn, "RIGHT", 6, 0)
    row._permDelBtn = permDelBtn

    -- "Sure?" confirm button — appears right of Delete for 3s, then hides
    local sureBtn = BNB.CreateButton(nil, row, "|cffff4444Sure?|r", 52, 20)
    sureBtn:SetPoint("LEFT", permDelBtn, "RIGHT", 4, 0)
    sureBtn:Hide()
    row._sureBtn = sureBtn
    row._sureTimer = nil

    _rows[index] = row
    return row
end

-- Populate / refresh
function BNB.RefreshTrashWindow()
    if not _twFrame or not _twFrame:IsShown() then return end
    BNB.PopulateTrashWindow()
end

function BNB.PopulateTrashWindow()
    if not _twFrame then return end

    -- Never rebind ndb — always read/write BigNoteBoxNotesDB directly
    local ndb = BigNoteBoxNotesDB
    if not ndb then return end
    if not ndb.trash then ndb.trash = {} end

    local items = {}
    for id, note in pairs(ndb.trash) do
        items[#items + 1] = { id = id, note = note }
    end
    table.sort(items, function(a, b)
        return (a.note.deletedAt or 0) > (b.note.deletedAt or 0)
    end)

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

        -- Title
        row._titleLbl:SetText(
            (note.title and note.title ~= "") and note.title or "|cff666666(untitled)|r")

        -- Date
        row._dateLbl:SetText(FormatDeleted(note.deletedAt))

        -- Preview
        local bodyStr = note.body or ""
        row._previewLbl:SetText(bodyStr ~= "" and bodyStr or "|cff444444(no content)|r")

        -- Selection highlight
        if row._selHi then
            row._selHi:SetShown(_multiMode and _multiSel[id] == true)
        end

        -- Cancel any pending Sure? timer on refresh
        if row._sureTimer then row._sureTimer:Cancel(); row._sureTimer = nil end
        if row._sureBtn   then row._sureBtn:Hide() end

        if _multiMode then
            row._viewBtn:Hide(); row._restoreBtn:Hide(); row._permDelBtn:Hide()
            if row._sureBtn then row._sureBtn:Hide() end
            row:SetScript("OnClick", function()
                if _multiSel[id] then _multiSel[id] = nil
                else                  _multiSel[id] = true end
                if row._selHi then
                    row._selHi:SetShown(_multiSel[id] == true)
                end
                -- Update action button enabled state immediately
                local selCount = 0
                for _ in pairs(_multiSel) do selCount = selCount + 1 end
                local hasAny = selCount > 0
                if _restoreSelBtn then _restoreSelBtn:SetEnabled(hasAny) end
                if _deleteSelBtn  then _deleteSelBtn:SetEnabled(hasAny)  end
            end)
        else
            row._viewBtn:Show(); row._restoreBtn:Show(); row._permDelBtn:Show()
            row:SetScript("OnClick", nil)

            -- View: open a popup showing the full note title + body
            row._viewBtn:SetScript("OnClick", function()
                local note = item.note
                if not note then return end
                local title = (note.title and note.title ~= "") and note.title or "(Untitled)"
                local body  = note.body or ""
                -- Reuse a simple resizable backdrop frame
                if not _twFrame._viewPopup then
                    local vp = BNB.CreateBackdropFrame("Frame", "BNBTrashViewPopup", UIParent)
                    vp:SetSize(340, 340); vp:SetFrameStrata("DIALOG"); vp:SetToplevel(true)
                    vp:SetMovable(true); vp:EnableMouse(true)
                    vp:RegisterForDrag("LeftButton")
                    vp:SetScript("OnDragStart", function(self) self:StartMoving() end)
                    vp:SetScript("OnDragStop",  function(self) self:StopMovingOrSizing() end)
                    BNB.SetBackdrop(vp, 0.07, 0.07, 0.09, 0.97, 0.35, 0.35, 0.38, 1)
                    local titleFs = vp:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                    titleFs:SetPoint("TOPLEFT", vp, "TOPLEFT", 12, -12)
                    titleFs:SetPoint("TOPRIGHT", vp, "TOPRIGHT", -12, -12)
                    titleFs:SetJustifyH("LEFT"); titleFs:SetWordWrap(true)
                    titleFs:SetTextColor(1, 0.82, 0.0, 1)
                    vp._titleFs = titleFs
                    local div = vp:CreateTexture(nil, "ARTWORK")
                    div:SetHeight(1)
                    div:SetPoint("TOPLEFT", vp, "TOPLEFT", 12, -32)
                    div:SetPoint("TOPRIGHT", vp, "TOPRIGHT", -12, -32)
                    div:SetColorTexture(0.28, 0.28, 0.30, 1)
                    local sf = CreateFrame("ScrollFrame", nil, vp, "ScrollFrameTemplate")
                    sf:SetPoint("TOPLEFT", vp, "TOPLEFT", 12, -38)
                    sf:SetPoint("BOTTOMRIGHT", vp, "BOTTOMRIGHT", -28, 40)
                    if sf.ScrollBar then sf.ScrollBar:SetAlpha(1) end
                    local ct = CreateFrame("Frame", nil, sf)
                    ct:SetWidth(300); sf:SetScrollChild(ct)
                    local bodyFs = ct:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                    bodyFs:SetPoint("TOPLEFT"); bodyFs:SetWidth(300)
                    bodyFs:SetJustifyH("LEFT"); bodyFs:SetWordWrap(true)
                    bodyFs:SetTextColor(0.85, 0.85, 0.85, 1)
                    vp._bodyFs = bodyFs; vp._bodyCt = ct
                    local restoreVpBtn = BNB.CreateButton(nil, vp, "Restore", 90, 24)
                    restoreVpBtn:SetPoint("BOTTOM", vp, "BOTTOM", -48, 10)
                    vp._restoreVpBtn = restoreVpBtn
                    local closeBtn = BNB.CreateButton(nil, vp, "Close", 80, 24)
                    closeBtn:SetPoint("BOTTOM", vp, "BOTTOM", 50, 10)
                    closeBtn:SetScript("OnClick", function() vp:Hide() end)
                    tinsert(UISpecialFrames, "BNBTrashViewPopup")
                    _twFrame._viewPopup = vp
                end
                local vp = _twFrame._viewPopup
                -- Wire Restore to current item (rewired each open)
                vp._restoreVpBtn:SetScript("OnClick", function()
                    if BNB.RestoreNote then BNB.RestoreNote(id) end
                    vp:Hide()
                end)
                vp._titleFs:SetText(title)
                vp._bodyFs:SetText(body)
                local textH = vp._bodyFs:GetStringHeight()
                vp._bodyCt:SetHeight(math.max(textH, 1))
                vp:ClearAllPoints()
                vp:SetPoint("CENTER", UIParent, "CENTER", 0, 30)
                vp:Show(); vp:Raise()
            end)

            row._restoreBtn:SetScript("OnClick", function()
                if BNB.RestoreNote then BNB.RestoreNote(id) end
            end)

            -- Delete: show "Sure?" for 3s, then auto-hide
            row._permDelBtn:SetScript("OnClick", function()
                local sb = row._sureBtn
                if not sb then return end
                sb:Show()
                if row._sureTimer then row._sureTimer:Cancel() end
                row._sureTimer = C_Timer.NewTimer(3, function()
                    sb:Hide(); row._sureTimer = nil
                end)
            end)

            -- Sure?: permanently delete from trash
            row._sureBtn:SetScript("OnClick", function()
                if row._sureTimer then row._sureTimer:Cancel(); row._sureTimer = nil end
                if BigNoteBoxNotesDB and BigNoteBoxNotesDB.trash then
                    BigNoteBoxNotesDB.trash[id] = nil
                end
                BNB.RefreshTrashWindow()
            end)
        end

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
    if _multiMode then
        local selCount = 0
        for _ in pairs(_multiSel) do selCount = selCount + 1 end
        local hasAny = selCount > 0
        if _restoreSelBtn then _restoreSelBtn:SetEnabled(hasAny) end
        if _deleteSelBtn  then _deleteSelBtn:SetEnabled(hasAny)  end
    end

    -- Auto-close when the last item is removed
    if n == 0 and _twFrame:IsShown() then
        if _multiMode then SetTrashMultiMode(false) end
        _twFrame:Hide()
    end
end

-- Build window (once)
local function BuildTrashWindow()
    if _twFrame then return _twFrame end

    local f = CreateFrame("Frame", "BigNoteBoxTrashFrame", UIParent, "ButtonFrameTemplate")
    f:SetWidth(TW_W)
    f:SetFrameStrata("HIGH"); f:SetToplevel(true)
    f:EnableMouse(true); f:SetMovable(true); f:SetClampedToScreen(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) self:StartMoving() end)
    f:SetScript("OnDragStop",  function(self) self:StopMovingOrSizing() end)

    ButtonFrameTemplate_HidePortrait(f)
    ButtonFrameTemplate_HideButtonBar(f)
    if f.Inset then f.Inset:Hide() end
    f:SetTitle("Trash")

    if f.CloseButton then
        f.CloseButton:SetScript("OnClick", function()
            if _multiMode then SetTrashMultiMode(false) end
            f:Hide()
        end)
    end

    -- Scroll frame (28px right clearance for scrollbar)
    local sf = CreateFrame("ScrollFrame", nil, f, "ScrollFrameTemplate")
    sf:SetPoint("TOPLEFT",     f, "TOPLEFT",      PAD, -(TITLE_H + 4))
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
    local emptyLbl = child:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    emptyLbl:SetPoint("TOP", child, "TOP", 0, -20)
    emptyLbl:SetWidth(CONTENT_W); emptyLbl:SetJustifyH("CENTER")
    emptyLbl:SetTextColor(0.4, 0.4, 0.4); emptyLbl:SetText("Trash is empty.")
    emptyLbl:Hide()
    _emptyLbl = emptyLbl

    -- Bottom strip rule
    local rule = f:CreateTexture(nil, "ARTWORK")
    rule:SetHeight(1); rule:SetColorTexture(0.25, 0.25, 0.28, 1)
    rule:SetPoint("BOTTOMLEFT",  f, "BOTTOMLEFT",  PAD,       BOTTOM_STRIP_H - 1)
    rule:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -PAD - 28, BOTTOM_STRIP_H - 1)

    -- ── Normal mode: Empty Trash | Select ────────────────────────────────────
    local emptyBtn = BNB.CreateButton(nil, f, "Empty Trash", 110, 26)
    emptyBtn:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", PAD, 14)
    emptyBtn:SetEnabled(false)
    emptyBtn:SetScript("OnClick", function() StaticPopup_Show("BNB_EMPTY_TRASH") end)
    emptyBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Permanently delete all trashed notes", 1, 1, 1)
        GameTooltip:AddLine("This cannot be undone.", 0.8, 0.4, 0.4, true)
        GameTooltip:Show()
    end)
    emptyBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    _emptyBtn = emptyBtn

    local selectBtn = BNB.CreateButton(nil, f, "Select", 72, 26)
    selectBtn:SetPoint("LEFT", emptyBtn, "RIGHT", 6, 0)
    selectBtn:SetEnabled(false)
    selectBtn:SetScript("OnClick", function() SetTrashMultiMode(true) end)
    selectBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Select notes to restore or delete in bulk", 1, 1, 1)
        GameTooltip:Show()
    end)
    selectBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    _selectBtn = selectBtn

    -- ── Select mode: Restore selected | Delete selected | Cancel ──────────────
    local restoreSelBtn = BNB.CreateButton(nil, f, "Restore selected", 110, 26)
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
        GameTooltip:AddLine("Move selected notes back to your note list", 1, 1, 1)
        GameTooltip:Show()
    end)
    restoreSelBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    restoreSelBtn:Hide()
    _restoreSelBtn = restoreSelBtn

    local deleteSelBtn = BNB.CreateButton(nil, f, "|cffff4444Delete selected|r", 110, 26)
    deleteSelBtn:SetPoint("LEFT", restoreSelBtn, "RIGHT", 6, 0)
    deleteSelBtn:SetEnabled(false)
    deleteSelBtn:SetScript("OnClick", function()
        local ids = {}
        for id in pairs(_multiSel) do ids[#ids + 1] = id end
        if BigNoteBoxNotesDB and BigNoteBoxNotesDB.trash then
            for _, id in ipairs(ids) do
                BigNoteBoxNotesDB.trash[id] = nil
            end
        end
        SetTrashMultiMode(false)
    end)
    deleteSelBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Permanently delete selected notes", 1, 1, 1)
        GameTooltip:AddLine("This cannot be undone.", 0.8, 0.4, 0.4, true)
        GameTooltip:Show()
    end)
    deleteSelBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    deleteSelBtn:Hide()
    _deleteSelBtn = deleteSelBtn

    local cancelSelBtn = BNB.CreateButton(nil, f, "Cancel", 68, 26)
    cancelSelBtn:SetPoint("LEFT", deleteSelBtn, "RIGHT", 6, 0)
    cancelSelBtn:SetScript("OnClick", function() SetTrashMultiMode(false) end)
    cancelSelBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Exit selection mode", 1, 1, 1)
        GameTooltip:Show()
    end)
    cancelSelBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    cancelSelBtn:Hide()
    _cancelSelBtn = cancelSelBtn

    -- Info block: "Kept X days\nX notes in trash" — bottom-right of strip
    local infoLbl = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    infoLbl:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -PAD - 28, 10)
    infoLbl:SetJustifyH("RIGHT")
    infoLbl:SetTextColor(0.45, 0.45, 0.45)
    _infoLbl = infoLbl

    -- ButtonFrameTemplate starts shown — hide immediately so ToggleTrashWindow
    -- sees IsShown() == false on the first click and takes the show branch.
    f:Hide()
    tinsert(UISpecialFrames, "BigNoteBoxTrashFrame")

    _twFrame = f
    return f
end

local SK_TW_TITLE_H = 28

local function BuildTrashWindowSkin()
    if _twFrame then return _twFrame end

    local f = BNB.CreateSkinFrame(UIParent, false, "BigNoteBoxTrashFrame", false)
    _G["BigNoteBoxTrashFrame"] = f
    f:SetWidth(TW_W)
    f:SetFrameStrata("HIGH"); f:SetToplevel(true)
    f:EnableMouse(true); f:SetMovable(true); f:SetClampedToScreen(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) self:StartMoving() end)
    f:SetScript("OnDragStop",  function(self) self:StopMovingOrSizing() end)

    -- Title strip
    local titleBar = BNB.CreateSkinStrip(f, true, false)
    titleBar:SetPoint("TOPLEFT",  f, "TOPLEFT",  0, 0)
    titleBar:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
    titleBar:SetHeight(SK_TW_TITLE_H)
    titleBar:EnableMouse(true)
    titleBar:RegisterForDrag("LeftButton")
    titleBar:SetScript("OnDragStart", function() f:StartMoving() end)
    titleBar:SetScript("OnDragStop",  function() f:StopMovingOrSizing() end)

    local titleLbl = titleBar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    titleLbl:SetPoint("CENTER", titleBar, "CENTER", -12, 0)
    titleLbl:SetTextColor(1, 0.82, 0)
    titleLbl:SetText("Trash")

    local closeBtn = BNB.CreateSkinCloseButton(titleBar, function()
        if _multiMode then SetTrashMultiMode(false) end
        f:Hide()
    end)
    closeBtn:SetPoint("RIGHT", titleBar, "RIGHT", -3, 0)

    -- Scroll frame
    local sf = CreateFrame("ScrollFrame", nil, f, "ScrollFrameTemplate")
    sf:SetPoint("TOPLEFT",     f, "TOPLEFT",      PAD, -(SK_TW_TITLE_H + 4))
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

    -- Empty state label
    local emptyLbl = child:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    emptyLbl:SetPoint("TOP", child, "TOP", 0, -20)
    emptyLbl:SetWidth(CONTENT_W); emptyLbl:SetJustifyH("CENTER")
    emptyLbl:SetTextColor(0.4, 0.4, 0.4); emptyLbl:SetText("Trash is empty.")
    emptyLbl:Hide()
    _emptyLbl = emptyLbl

    -- Footer divider (host frame avoids backdrop overdraw)
    local footHost = CreateFrame("Frame", nil, f)
    footHost:SetHeight(1)
    footHost:SetPoint("BOTTOMLEFT",  f, "BOTTOMLEFT",  PAD,       BOTTOM_STRIP_H - 1)
    footHost:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -PAD - 28, BOTTOM_STRIP_H - 1)
    local footDiv = BNB.CreateDivider(footHost, "HORIZONTAL", 0.25, 0.25, 0.28, 1)
    footDiv:SetPoint("TOPLEFT",  footHost, "TOPLEFT",  0, 0)
    footDiv:SetPoint("TOPRIGHT", footHost, "TOPRIGHT", 0, 0)

    -- ── Normal mode: Empty Trash | Select ────────────────────────────────────
    local emptyBtn = BNB.CreateButton(nil, f, "Empty Trash", 110, 26)
    emptyBtn:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", PAD, 14)
    emptyBtn:SetEnabled(false)
    emptyBtn:SetScript("OnClick", function() StaticPopup_Show("BNB_EMPTY_TRASH") end)
    emptyBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Permanently delete all trashed notes", 1, 1, 1)
        GameTooltip:AddLine("This cannot be undone.", 0.8, 0.4, 0.4, true)
        GameTooltip:Show()
    end)
    emptyBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    _emptyBtn = emptyBtn

    local selectBtn = BNB.CreateButton(nil, f, "Select", 72, 26)
    selectBtn:SetPoint("LEFT", emptyBtn, "RIGHT", 6, 0)
    selectBtn:SetEnabled(false)
    selectBtn:SetScript("OnClick", function() SetTrashMultiMode(true) end)
    selectBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Select notes to restore or delete in bulk", 1, 1, 1)
        GameTooltip:Show()
    end)
    selectBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    _selectBtn = selectBtn

    -- ── Select mode: Restore selected | Delete selected | Cancel ──────────────
    local restoreSelBtn = BNB.CreateButton(nil, f, "Restore selected", 110, 26)
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
        GameTooltip:AddLine("Move selected notes back to your note list", 1, 1, 1)
        GameTooltip:Show()
    end)
    restoreSelBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    restoreSelBtn:Hide()
    _restoreSelBtn = restoreSelBtn

    local deleteSelBtn = BNB.CreateButton(nil, f, "|cffff4444Delete selected|r", 110, 26)
    deleteSelBtn:SetPoint("LEFT", restoreSelBtn, "RIGHT", 6, 0)
    deleteSelBtn:SetEnabled(false)
    deleteSelBtn:SetScript("OnClick", function()
        local ids = {}
        for id in pairs(_multiSel) do ids[#ids + 1] = id end
        if BigNoteBoxNotesDB and BigNoteBoxNotesDB.trash then
            for _, id in ipairs(ids) do
                BigNoteBoxNotesDB.trash[id] = nil
            end
        end
        SetTrashMultiMode(false)
    end)
    deleteSelBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Permanently delete selected notes", 1, 1, 1)
        GameTooltip:AddLine("This cannot be undone.", 0.8, 0.4, 0.4, true)
        GameTooltip:Show()
    end)
    deleteSelBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    deleteSelBtn:Hide()
    _deleteSelBtn = deleteSelBtn

    local cancelSelBtn = BNB.CreateButton(nil, f, "Cancel", 68, 26)
    cancelSelBtn:SetPoint("LEFT", deleteSelBtn, "RIGHT", 6, 0)
    cancelSelBtn:SetScript("OnClick", function() SetTrashMultiMode(false) end)
    cancelSelBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Exit selection mode", 1, 1, 1)
        GameTooltip:Show()
    end)
    cancelSelBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    cancelSelBtn:Hide()
    _cancelSelBtn = cancelSelBtn

    -- Info block: "Kept X days\nX notes in trash" -- bottom-right of strip
    local infoLbl = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    infoLbl:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -PAD - 28, 10)
    infoLbl:SetJustifyH("RIGHT")
    infoLbl:SetTextColor(0.45, 0.45, 0.45)
    _infoLbl = infoLbl

    f:SetScript("OnShow", function()
        if BNB.ApplyMainWindowSkin then BNB.ApplyMainWindowSkin() end
    end)

    f:Hide()
    tinsert(UISpecialFrames, "BigNoteBoxTrashFrame")

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

-- Public API
function BNB.ToggleTrashWindow()
    if InCombatLockdown() then BNB:Print(L["COMBAT_BLOCKED"]); return end
    local f
    if BigNoteBoxDB and BigNoteBoxDB.skinMode then
        f = BuildTrashWindowSkin()
    else
        f = BuildTrashWindow()
    end
    if f:IsShown() then
        if _multiMode then SetTrashMultiMode(false) end
        f:Hide(); return
    end
    SyncTrashHeight()
    f:ClearAllPoints()
    if BNB.mainFrame and BNB.mainFrame:IsShown() then
        f:SetPoint("TOPRIGHT", BNB.mainFrame, "TOPLEFT", -8, 0)
    else
        f:SetPoint("CENTER")
    end
    f:Show()
    BNB.PopulateTrashWindow()
end

function BNB.InitTrashWindow()
    BNB.HookTrashHeightTracking()
end

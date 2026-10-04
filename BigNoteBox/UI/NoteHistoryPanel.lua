-- BigNoteBox UI/NoteHistoryPanel.lua
--
-- Per-note history panel. Shows one note's manual snapshot (top) and
-- auto snapshot slots (below), separated by a section divider.
--
-- Height: dynamic — grows with slot count up to the main window's height.
-- Width: same as HistoryWindow (HW_W = 400).
-- Anchors same as HistoryWindow (TOPRIGHT of main window TOPLEFT).
--
-- When open, greys out the HistoryWindow if it is also open.
-- Can be opened standalone (from right-click or WYSIWYG tb-history button).
--
-- Public API:
--   BNB.OpenNoteHistoryPanel(noteID)
--   BNB.CloseNoteHistoryPanel()
--   BNB.RefreshNoteHistoryPanel()

local BNB = BigNoteBox
local L   = BNB.L

local HW_W           = 400
local TITLE_H        = 32
local PAD            = 14
local ROW_H          = 64
local ROW_GAP        = 4
local ICON_SZ        = 36
local TEXT_LEFT      = PAD + ICON_SZ + 10
local CONTENT_W      = HW_W - PAD * 2 - 30
local BOTTOM_STRIP_H = 44
local SECTION_H      = 22   -- section header height
local MIN_H          = 200

local DEFAULT_ICON = "Interface\\Icons\\INV_Misc_Note_06"

local _nhpFrame  = nil
local _currentID = nil
local _rows      = {}

local FmtTs = BNB.FmtTs

--------------------------------------------------------------------------------
-- ComputeHeight — panel height based on slot count
--------------------------------------------------------------------------------
local function ComputeHeight(numAuto, hasManual)
    local rows = numAuto + (hasManual and 1 or 0)
    local sectionHeaders = 1 + (hasManual and 1 or 0)   -- "Auto" always; "Manual" if exists
    local interGap = hasManual and 4 or 0               -- extra gap between manual and auto
    local h = TITLE_H + PAD
        + PAD                                           -- top padding before first header
        + sectionHeaders * (SECTION_H + 4)
        + rows * (ROW_H + ROW_GAP)
        + interGap
        + BOTTOM_STRIP_H + 8
    -- Cap at main window height
    local maxH = (BNB.mainFrame and BNB.mainFrame:GetHeight()) or 640
    return math.max(MIN_H, math.min(h, maxH))
end

--------------------------------------------------------------------------------
-- BuildSectionHeader — pinned/notes style divider + label
--------------------------------------------------------------------------------
local function BuildSectionHeader(parent, y, label, r, g, b)
    -- y is negative (WoW downward convention). Returns next y below the header.
    r = r or 0.55; g = g or 0.55; b = b or 0.55

    local rule = parent:CreateTexture(nil, "ARTWORK")
    rule:SetHeight(1)
    rule:SetPoint("TOPLEFT",  parent, "TOPLEFT",  0, y)
    rule:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, y)
    rule:SetColorTexture(0.22, 0.22, 0.25, 1)

    local lbl = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    lbl:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, y - 2)
    lbl:SetHeight(SECTION_H - 2)
    lbl:SetJustifyH("LEFT")
    lbl:SetTextColor(r, g, b)
    lbl:SetText(label)

    return y - SECTION_H
end

--------------------------------------------------------------------------------
-- BuildSnapRow — one snapshot entry
--------------------------------------------------------------------------------

local function BuildSnapRow(parent, snap, noteID, slotType, slotIndex, yOff)
    -- slotType = "manual" or "auto"; slotIndex = 1-based for auto
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(ROW_H)
    row:SetPoint("TOPLEFT",  parent, "TOPLEFT",  0, yOff)
    row:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, yOff)
    row:EnableMouse(true)

    -- Note icon from the snapshot; snapshots since SV-11 carry no icon, so the
    -- note's current one
    local icon = row:CreateTexture(nil, "ARTWORK")
    icon:SetSize(ICON_SZ, ICON_SZ)
    icon:SetPoint("LEFT", row, "LEFT", 0, 0)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    local live    = BNB.GetNote and BNB.GetNote(noteID)
    local iconTex = snap.icon or (live and live.icon) or DEFAULT_ICON
    if type(iconTex) == "number" or iconTex:find("^Interface") or iconTex:find("^%d+$") then
        icon:SetTexture(iconTex)
    else
        pcall(function() icon:SetAtlas(iconTex) end)
    end

    -- Timestamp
    local tsLbl = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    tsLbl:SetPoint("TOPLEFT",  row, "TOPLEFT",  TEXT_LEFT, -4)
    tsLbl:SetPoint("TOPRIGHT", row, "TOPRIGHT", -4,        -4)
    tsLbl:SetJustifyH("LEFT"); tsLbl:SetHeight(16)
    tsLbl:SetText(FmtTs(snap.timestamp))

    -- Size
    local szBytes = (snap.title and #snap.title or 0)
                  + (snap.body  and #snap.body  or 0)
                  + 64
    local szLbl = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    szLbl:SetPoint("TOPRIGHT", row, "TOPRIGHT", -4, -4)
    szLbl:SetHeight(14); szLbl:SetJustifyH("RIGHT")
    szLbl:SetTextColor(0.40, 0.40, 0.40)
    szLbl:SetText(BNB.HistoryFormatSize(szBytes))

    -- Title preview
    local prevLbl = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    prevLbl:SetPoint("TOPLEFT",  row, "TOPLEFT",  TEXT_LEFT, -20)
    prevLbl:SetPoint("TOPRIGHT", row, "TOPRIGHT", -90,       -20)
    prevLbl:SetJustifyH("LEFT"); prevLbl:SetHeight(14)
    prevLbl:SetTextColor(0.60, 0.60, 0.60)
    local title = snap.title and snap.title ~= "" and snap.title or "(untitled)"
    prevLbl:SetText(title)

    -- Compare button
    local cmpBtn = BNB.CreateButton(nil, row, L["HISTORY_OVERRIDE_COMPARE"], 72, 22)
    cmpBtn:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", TEXT_LEFT, 6)
    cmpBtn:SetScript("OnClick", function()
        if BNB.OpenHistoryCompare then
            BNB.OpenHistoryCompare(noteID, snap)
        end
    end)
    cmpBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(L["HISTORY_COMPARE_TIP"], 1, 1, 1)
        GameTooltip:Show()
    end)
    cmpBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Delete button
    local delBtn = BNB.CreateButton(nil, row, L["BTN_DELETE_NOTE"], 60, 22)
    delBtn:SetPoint("LEFT", cmpBtn, "RIGHT", 6, 0)
    local delConfirm = BNB.CreateButton(nil, row, "|cffff4444" .. L["HISTORY_SLOT_DELETE_CONFIRM"] .. "|r", 60, 22)
    delConfirm:SetPoint("LEFT", delBtn, "RIGHT", 4, 0)
    delConfirm:Hide()

    delBtn:SetScript("OnClick", function()
        delBtn:Hide()
        delConfirm:Show()
        C_Timer.After(3, function()
            if delConfirm:IsShown() then
                delConfirm:Hide(); delBtn:Show()
            end
        end)
    end)
    delConfirm:SetScript("OnClick", function()
        if slotType == "manual" then
            BNB.HistoryDeleteManual(noteID)
        else
            BNB.HistoryDeleteAutoSlot(noteID, slotIndex)
        end
        BNB.RefreshNoteHistoryPanel()
        BNB.RefreshHistoryWindow()
    end)

    -- Right-click context menu: Compare, Restore (direct), Delete (keeps the
    -- row's own confirm step rather than a second popup).
    row:SetScript("OnMouseUp", function(self, button)
        if button ~= "RightButton" then return end
        BNB.ContextMenu.Open(row, function(root)   -- ALL-148
            root:CreateButton(L["HISTORY_OVERRIDE_COMPARE"], function()
                if BNB.OpenHistoryCompare then BNB.OpenHistoryCompare(noteID, snap) end
            end)
            root:CreateButton(L["HISTORY_CTX_RESTORE"], function()
                BNB.HistoryRestoreNote(noteID, snap, true)
                BNB:Print(L["HISTORY_RESTORED"])
            end)
            root:CreateDivider()
            root:CreateButton(L["BTN_DELETE_NOTE"], function()
                local onClick = delBtn:GetScript("OnClick")
                if onClick then onClick(delBtn) end
            end, { danger = true })   -- irreversible = red (Dukul)
        end)
    end)

    -- Bottom separator
    local sep = row:CreateTexture(nil, "ARTWORK")
    sep:SetHeight(1)
    sep:SetPoint("BOTTOMLEFT",  row, "BOTTOMLEFT",  0, 0)
    sep:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 0)
    sep:SetColorTexture(0.18, 0.18, 0.20, 1)

    return row
end

--------------------------------------------------------------------------------
-- PopulateNoteHistoryPanel — rebuild content for _currentID
--------------------------------------------------------------------------------
function BNB.PopulateNoteHistoryPanel()
    if not _nhpFrame or not _currentID then return end
    local sf = _nhpFrame._scrollFrame
    if not sf then return end

    -- Destroy the old scroll child entirely so all parented textures and
    -- fontstrings (created by BuildSectionHeader) are discarded with it.
    -- Plain Hide/reparent only works for Frames, not for CreateTexture /
    -- CreateFontString objects, which would otherwise stack on re-populate.
    if _nhpFrame._scrollChild then
        _nhpFrame._scrollChild:Hide()
        _nhpFrame._scrollChild:SetParent(nil)
    end
    local child = CreateFrame("Frame", nil, sf)
    child:SetWidth(CONTENT_W); child:SetHeight(200)
    sf:SetScrollChild(child)
    _nhpFrame._scrollChild = child
    _rows = {}

    local slots = BNB.HistoryGetSlots(_currentID)
    local numAuto   = #slots.auto
    local hasManual = slots.manual ~= nil

    if numAuto == 0 and not hasManual then
        local e = child:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        e:SetPoint("TOP", child, "TOP", 0, -20)
        e:SetWidth(CONTENT_W); e:SetJustifyH("CENTER")
        e:SetTextColor(0.4, 0.4, 0.4)
        e:SetText(L["HISTORY_NOTE_EMPTY"])
        _rows[1] = e
        child:SetHeight(80)
        _nhpFrame:SetHeight(ComputeHeight(0, false))
        return
    end

    -- Use a single negative y cursor (WoW convention: y goes down as negative).
    -- Start with top padding so the first section header clears the title bar.
    local y = -PAD

    -- Manual section (top, amber)
    if hasManual then
        y = BuildSectionHeader(child, y, L["HISTORY_SECTION_MANUAL"], 0.85, 0.65, 0.20)
        local r = BuildSnapRow(child, slots.manual, _currentID, "manual", nil, y)
        _rows[#_rows + 1] = r
        y = y - ROW_H - ROW_GAP - 4   -- extra gap before auto section
    end

    -- Auto section
    y = BuildSectionHeader(child, y, string.format(L["HISTORY_SECTION_AUTO"], numAuto),
        0.55, 0.55, 0.55)
    for i, snap in ipairs(slots.auto) do
        local r = BuildSnapRow(child, snap, _currentID, "auto", i, y)
        _rows[#_rows + 1] = r
        y = y - ROW_H - ROW_GAP
    end

    child:SetHeight(math.max(math.abs(y) + 8, 40))
    _nhpFrame:SetHeight(ComputeHeight(numAuto, hasManual))

    -- Update title
    local ndb  = BNB.NotesDB()
    local note = ndb and ndb.notes and ndb.notes[_currentID]
    local title = note and note.title or "(untitled)"
    local nhpTitle = string.format(L["HISTORY_NOTE_TITLE"], title)
    _nhpFrame:SetWindowTitle(nhpTitle)
end

function BNB.RefreshNoteHistoryPanel()
    if not _nhpFrame or not _nhpFrame:IsShown() then return end
    BNB.PopulateNoteHistoryPanel()
end

--------------------------------------------------------------------------------
-- BuildNoteHistoryPanel — lazy-build. One body for both modes (CMP-02 S3):
-- chrome, footer divider, drag and ESC entry from CreateToolWindow.
--------------------------------------------------------------------------------
local function BuildNoteHistoryPanel()
    if _nhpFrame then return _nhpFrame end

    local f = BNB.CreateToolWindow({
        name = "BigNoteBoxNoteHistoryFrame", w = HW_W, h = MIN_H,   -- Populate sizes it
        title = L["HISTORY_WINDOW_TITLE"], strata = "HIGH", toplevel = true, escClose = true,
        pad = PAD, footH = BOTTOM_STRIP_H - 1, footR = PAD + 28,
        onClose = function() BNB.CloseNoteHistoryPanel() end,
        -- A hide that skips CloseNoteHistoryPanel (UISpecialFrames) still un-greys
        onHide = function()
            if BNB.SetHistoryWindowGreyout then BNB.SetHistoryWindowGreyout(false) end
        end,
    })
    local top = f._isSkin and BNB.TOOL_SKIN_TITLE_H or TITLE_H

    local sf = CreateFrame("ScrollFrame", nil, f, "ScrollFrameTemplate")
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

    local clearBtn = BNB.CreateButton(nil, f, L["HISTORY_CLEAR_NOTE_BTN"], 150, 26)
    clearBtn:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", PAD, 10)
    clearBtn:SetScript("OnClick", function()
        if _currentID then
            BNB.HistoryDeleteAuto(_currentID)
            BNB.CloseNoteHistoryPanel()
            BNB.RefreshHistoryWindow()
        end
    end)
    clearBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(L["HISTORY_CLEAR_NOTE_TIP"], 1, 1, 1)
        GameTooltip:AddLine(L["HISTORY_CLEAR_NOTE_SUB"], 0.8, 0.4, 0.4, true)
        GameTooltip:Show()
    end)
    clearBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    _nhpFrame = f
    return f
end

--------------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------------
-- While the panel is open it switches to the note selected in the main window
-- (NoteSelected from SelectNote; a hand call there until ARCH-02)
BNB.RegisterMessage("NoteHistoryPanel", "NoteSelected", function(_, id)
    local nhp = _G["BigNoteBoxNoteHistoryFrame"]
    if nhp and nhp:IsShown() then BNB.OpenNoteHistoryPanel(id) end
end)

function BNB.OpenNoteHistoryPanel(noteID)
    if InCombatLockdown() then return end
    _currentID = noteID
    local f = BuildNoteHistoryPanel()

    -- Grey out history window if open
    if BNB.SetHistoryWindowGreyout then
        BNB.SetHistoryWindowGreyout(true)
    end

    f:SetHeight(MIN_H)   -- will be resized by Populate
    f:ClearAllPoints()
    if BNB.mainFrame and BNB.mainFrame:IsShown() then
        f:SetPoint("TOPRIGHT", BNB.mainFrame, "TOPLEFT", -8, 0)
    else
        f:SetPoint("CENTER")
    end
    f:Show()
    f:Raise()
    BNB.PopulateNoteHistoryPanel()
end

function BNB.CloseNoteHistoryPanel()
    if _nhpFrame then _nhpFrame:Hide() end
    _currentID = nil
    -- Un-grey history window
    if BNB.SetHistoryWindowGreyout then
        BNB.SetHistoryWindowGreyout(false)
    end
end

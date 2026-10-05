-- BigNoteBox UI/NoteHistoryPanel.lua
--
-- Per-note history page. Shows one note's manual snapshot (top) and
-- auto snapshot slots (below), separated by a section divider.
--
-- A page of the History window (ALL-258, Dukul 2026-10-05: one window with a
-- back button instead of a second window on top): BuildHistoryWindow calls
-- BNB._BuildNoteHistoryPage, the back arrow and ESC return to the list.
-- Opened from a History row, the note right-click menu or the WYSIWYG
-- tb-history button; it follows the note selected in the main window.
--
-- Public API:
--   BNB.OpenNoteHistoryPanel(noteID)   -- the History window on this note's page
--   BNB.CloseNoteHistoryPanel()        -- back to the list, if on the page
--   BNB.RefreshNoteHistoryPanel()

local BNB = BigNoteBox
local L   = BNB.L

local HW_W           = BNB.SIDE_WINDOW_W   -- 400 (ALL-269)
local PAD            = 14
local ROW_H          = 64
local ROW_GAP        = 4
local ICON_SZ        = 36
local TEXT_LEFT      = PAD + ICON_SZ + 10
local CONTENT_W      = HW_W - PAD * 2 - 30
local BOTTOM_STRIP_H = 44
local SECTION_H      = 22   -- section header height

local DEFAULT_ICON = "Interface\\Icons\\INV_Misc_Note_06"

local _hwFrame = nil   -- the History window
local _page    = nil   -- its "note" page; _page._noteID = the note shown
local _rows    = {}

local FmtTs = BNB.FmtTs

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
-- PopulateNoteHistoryPanel — rebuild content for the page's note
--------------------------------------------------------------------------------
function BNB.PopulateNoteHistoryPanel()
    local id = _page and _page._noteID
    if not id then return end
    local sf = _page._scrollFrame

    -- Destroy the old scroll child entirely so all parented textures and
    -- fontstrings (created by BuildSectionHeader) are discarded with it.
    -- Plain Hide/reparent only works for Frames, not for CreateTexture /
    -- CreateFontString objects, which would otherwise stack on re-populate.
    if _page._scrollChild then
        _page._scrollChild:Hide()
        _page._scrollChild:SetParent(nil)
    end
    local child = CreateFrame("Frame", nil, sf)
    child:SetWidth(CONTENT_W); child:SetHeight(200)
    sf:SetScrollChild(child)
    sf:SetVerticalScroll(0)
    _page._scrollChild = child
    _rows = {}

    local ndb  = BNB.NotesDB()
    local note = ndb and ndb.notes and ndb.notes[id]
    local title = note and note.title
    _page:SetHeading((title and title ~= "") and title or L["HW_UNTITLED"])
    _page._sizeLbl:SetText(BNB.HistoryFormatSize(BNB.HistoryNoteSize(id)))

    local slots = BNB.HistoryGetSlots(id)
    local numAuto   = #slots.auto
    local hasManual = slots.manual ~= nil
    _page._clearBtn:SetEnabled(numAuto > 0)

    if numAuto == 0 and not hasManual then
        local e = child:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        e:SetPoint("TOP", child, "TOP", 0, -20)
        e:SetWidth(CONTENT_W); e:SetJustifyH("CENTER")
        e:SetTextColor(0.4, 0.4, 0.4)
        e:SetText(L["HISTORY_NOTE_EMPTY"])
        _rows[1] = e
        child:SetHeight(80)
        return
    end

    -- Use a single negative y cursor (WoW convention: y goes down as negative).
    -- The page's rule sits right above, so the first header starts close under it.
    local y = -4

    -- Manual section (top, amber)
    if hasManual then
        y = BuildSectionHeader(child, y, L["HISTORY_SECTION_MANUAL"], 0.85, 0.65, 0.20)
        local r = BuildSnapRow(child, slots.manual, id, "manual", nil, y)
        _rows[#_rows + 1] = r
        y = y - ROW_H - ROW_GAP - 4   -- extra gap before auto section
    end

    -- Auto section
    y = BuildSectionHeader(child, y, string.format(L["HISTORY_SECTION_AUTO"], numAuto),
        0.55, 0.55, 0.55)
    for i, snap in ipairs(slots.auto) do
        local r = BuildSnapRow(child, snap, id, "auto", i, y)
        _rows[#_rows + 1] = r
        y = y - ROW_H - ROW_GAP
    end

    child:SetHeight(math.max(math.abs(y) + 8, 40))
end

function BNB.RefreshNoteHistoryPanel()
    if not (_page and _page:IsVisible()) then return end
    BNB.PopulateNoteHistoryPanel()
end

--------------------------------------------------------------------------------
-- BNB._BuildNoteHistoryPage(f, top) — the "note" page of the History window,
-- built with it (BuildHistoryWindow). top = the window's content top.
--------------------------------------------------------------------------------
function BNB._BuildNoteHistoryPage(f, top)
    _hwFrame = f
    local page = f:AddPage("note", {
        top = top, pad = PAD, padR = PAD + 28,
        onShow = function(p, noteID)
            if noteID then p._noteID = noteID end
            BNB.PopulateNoteHistoryPanel()
        end,
    })
    _page = page

    local sf = CreateFrame("ScrollFrame", nil, page, "ScrollFrameTemplate")
    sf:SetPoint("TOPLEFT",     f, "TOPLEFT",      PAD, -(page.top + 4))
    sf:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -28,   BOTTOM_STRIP_H)
    page._scrollFrame = sf

    if sf.ScrollBar then
        sf.ScrollBar:SetAlpha(0)
        sf:HookScript("OnScrollRangeChanged", function(_, _, yRange)
            sf.ScrollBar:SetAlpha((yRange or 0) > 1 and 1.0 or 0)
        end)
    end

    local clearBtn = BNB.CreateButton(nil, page, L["HISTORY_CLEAR_NOTE_BTN"], 150, 26)
    clearBtn:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", PAD, 10)
    clearBtn:SetScript("OnClick", function()
        if page._noteID then
            BNB.HistoryDeleteAuto(page._noteID)
            f:PageBack()   -- the list refreshes as it shows
        end
    end)
    clearBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(L["HISTORY_CLEAR_NOTE_TIP"], 1, 1, 1)
        GameTooltip:AddLine(L["HISTORY_CLEAR_NOTE_SUB"], 0.8, 0.4, 0.4, true)
        GameTooltip:Show()
    end)
    clearBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    page._clearBtn = clearBtn

    -- This note's history size, where the list page shows the total
    local szLbl = page:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    szLbl:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -PAD - 28, 14)
    szLbl:SetJustifyH("RIGHT")
    szLbl:SetTextColor(0.45, 0.45, 0.45)
    page._sizeLbl = szLbl
end

--------------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------------
-- While the note page is open it switches to the note selected in the main
-- window (NoteSelected from SelectNote)
BNB.RegisterMessage("NoteHistoryPanel", "NoteSelected", function(_, id)
    if _page and _page:IsVisible() and id and id ~= _page._noteID then
        _hwFrame:ShowPage("note", id)
    end
end)

function BNB.OpenNoteHistoryPanel(noteID)
    if not noteID then return end
    BNB.ShowHistoryWindow("note", noteID)
end

function BNB.CloseNoteHistoryPanel()
    if _page and _page:IsVisible() then _hwFrame:PageBack() end
end

-- The formatting toolbar's History button is a toggle (ALL-131): a second
-- click while this note's page is open closes the History window
function BNB.ToggleNoteHistoryPanel(noteID)
    if not noteID then return end
    if _page and _page:IsVisible() and _page._noteID == noteID then
        _hwFrame:Hide()
    else
        BNB.OpenNoteHistoryPanel(noteID)
    end
end

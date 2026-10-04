-- BigNoteBox UI/HistoryWindow.lua
--
-- Main history browser. Lists all notes that have any history (auto or manual).
-- Same width as TrashWindow, same height tracking (follows main window height).
-- Anchors TOPRIGHT of main window's TOPLEFT, same as Trash.
--
-- When a row is clicked, opens NoteHistoryPanel for that note on top.
-- The history window greys out (alpha + click blocker) while the panel is open.
--
-- Public API:
--   BNB.ToggleHistoryWindow()
--   BNB.OpenHistoryWindow()
--   BNB.CloseHistoryWindow()
--   BNB.RefreshHistoryWindow()
--   BNB.SetHistoryWindowGreyout(bool)   -- called by NoteHistoryPanel
--   BNB.InitHistoryWindow()

local BNB = BigNoteBox
local L   = BNB.L

local HW_W           = 400
local TITLE_H        = 32
local PAD            = 14
local ROW_H          = 56    -- compact: icon + title + date
local ROW_GAP        = 4
local ICON_SZ        = 36
local TEXT_LEFT      = PAD + ICON_SZ + 10
local CONTENT_W      = HW_W - PAD * 2 - 30
local BOTTOM_STRIP_H = 44

local DEFAULT_ICON = "Interface\\Icons\\INV_Misc_Note_06"

local _hwFrame    = nil
local _rows       = {}
local _emptyLbl   = nil
local _blocker    = nil   -- invisible frame to eat clicks when greyed out
local _clearAllBtn = nil
local _sizeLbl    = nil

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

    -- Icon
    local icon = row:CreateTexture(nil, "ARTWORK")
    icon:SetSize(ICON_SZ, ICON_SZ)
    icon:SetPoint("LEFT", row, "LEFT", 0, 0)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    local iconTex = note.icon or DEFAULT_ICON
    if type(iconTex) == "number" or iconTex:find("^Interface") or iconTex:find("^%d+$") then
        icon:SetTexture(iconTex)
    else
        pcall(function() icon:SetAtlas(iconTex) end)
    end

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
        if _clearAllBtn then _clearAllBtn:SetEnabled(false) end
        if _sizeLbl     then _sizeLbl:SetText(L["HISTORY_SIZE_NONE"]) end
        return
    end

    _emptyLbl:Hide()
    if _clearAllBtn then _clearAllBtn:SetEnabled(true) end

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

function BNB.RefreshHistoryWindow()
    if not _hwFrame or not _hwFrame:IsShown() then return end
    BNB.PopulateHistoryWindow()
end

--------------------------------------------------------------------------------
-- SetHistoryWindowGreyout — dim + block clicks while NoteHistoryPanel is open
--------------------------------------------------------------------------------
function BNB.SetHistoryWindowGreyout(grey)
    if not _hwFrame then return end
    _hwFrame:SetAlpha(grey and 0.45 or BNB.WindowAlpha(_hwFrame))   -- ALL-78
    if _blocker then
        if grey then _blocker:Show() else _blocker:Hide() end
    end
end

--------------------------------------------------------------------------------
-- BuildHistoryWindow — lazy-build on first open. One body for both modes
-- (CMP-02 S3): chrome, footer divider, drag and ESC entry from CreateToolWindow.
--------------------------------------------------------------------------------
local function BuildHistoryWindow()
    if _hwFrame then return _hwFrame end

    local f = BNB.CreateToolWindow({
        name = "BigNoteBoxHistoryFrame", w = HW_W, h = 400,   -- height follows the main window
        title = L["HISTORY_WINDOW_TITLE"], strata = "HIGH", toplevel = true, escClose = true,
        pad = PAD, footH = BOTTOM_STRIP_H - 1, footR = PAD + 28,
        onClose = function() BNB.CloseHistoryWindow() end,
    })
    local top = f._isSkin and BNB.TOOL_SKIN_TITLE_H or TITLE_H

    -- Scroll frame
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

    -- Empty state
    local emptyLbl = child:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    emptyLbl:SetPoint("TOP", child, "TOP", 0, -20)
    emptyLbl:SetWidth(CONTENT_W); emptyLbl:SetJustifyH("CENTER")
    emptyLbl:SetTextColor(0.4, 0.4, 0.4)
    emptyLbl:SetText(L["HISTORY_EMPTY"])
    emptyLbl:Hide()
    _emptyLbl = emptyLbl

    -- Clear all button
    local clearBtn = BNB.CreateButton(nil, f, L["HISTORY_CLEAR_ALL_BTN"], 140, 26)
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

    -- Size label
    local szLbl = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    szLbl:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -PAD - 28, 14)
    szLbl:SetJustifyH("RIGHT")
    szLbl:SetTextColor(0.45, 0.45, 0.45)
    _sizeLbl = szLbl

    -- Invisible click blocker (shown when NoteHistoryPanel greys us out)
    local blocker = CreateFrame("Frame", nil, f)
    blocker:SetAllPoints()
    blocker:SetFrameLevel(f:GetFrameLevel() + 50)
    blocker:EnableMouse(true)
    blocker:Hide()
    _blocker = blocker

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
-- Height sync (mirrors TrashWindow pattern)
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
function BNB.OpenHistoryWindow()
    if InCombatLockdown() then BNB:Print(L["COMBAT_BLOCKED"]); return end
    local f = BuildHistoryWindow()
    -- Close NoteHistoryPanel and Trash if open (per ESC-chain rules)
    if BNB.CloseNoteHistoryPanel then BNB.CloseNoteHistoryPanel() end
    local tw = _G["BigNoteBoxTrashFrame"]
    if tw and tw:IsShown() then tw:Hide() end
    SyncHistoryHeight()
    f:ClearAllPoints()
    if BNB.mainFrame and BNB.mainFrame:IsShown() then
        f:SetPoint("TOPRIGHT", BNB.mainFrame, "TOPLEFT", -8, 0)
    else
        f:SetPoint("CENTER")
    end
    f:Show()
    BNB.PopulateHistoryWindow()
end

function BNB.CloseHistoryWindow()
    if BNB.CloseNoteHistoryPanel then BNB.CloseNoteHistoryPanel() end
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

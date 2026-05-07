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
local ASSETS       = "Interface\\AddOns\\BigNoteBox\\Assets\\"

local _hwFrame    = nil
local _rows       = {}
local _emptyLbl   = nil
local _blocker    = nil   -- invisible frame to eat clicks when greyed out
local _clearAllBtn = nil
local _sizeLbl    = nil

--------------------------------------------------------------------------------
-- INTERNAL: format a unix timestamp as a short date+time string
--------------------------------------------------------------------------------
local function FmtSnap(ts)
    if not ts or ts == 0 then return "Unknown" end
    local db  = BigNoteBoxDB
    local use24 = db and db.use24Hour ~= false
    local d = date("%Y-%m-%d", ts)
    local t
    if use24 then
        t = date("%H:%M", ts)
    else
        local h = tonumber(date("%H", ts))
        local ampm = h >= 12 and "pm" or "am"
        h = h % 12; if h == 0 then h = 12 end
        t = h .. ":" .. date("%M", ts) .. " " .. ampm
    end
    return d .. "  " .. t
end

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
    titleLbl:SetText(note.title or "(untitled)")

    -- Slot count
    local n   = SlotCount(id)
    local sub = n == 1 and "1 snapshot" or (n .. " snapshots")
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

    row:SetScript("OnClick", function()
        if BNB.OpenNoteHistoryPanel then
            BNB.OpenNoteHistoryPanel(id)
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
    local ndb = BigNoteBoxNotesDB
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
    _hwFrame:SetAlpha(grey and 0.45 or 1.0)
    if _blocker then
        if grey then _blocker:Show() else _blocker:Hide() end
    end
end

--------------------------------------------------------------------------------
-- BuildHistoryWindow — lazy-build on first open
--------------------------------------------------------------------------------
local SK_HW_TITLE_H = 28

local function BuildHistoryWindowSkin()
    if _hwFrame then return _hwFrame end

    local f = BNB.CreateSkinFrame(UIParent, false, "BigNoteBoxHistoryFrame", false)
    _G["BigNoteBoxHistoryFrame"] = f
    f:SetWidth(HW_W)
    f:SetFrameStrata("HIGH"); f:SetToplevel(true)
    f:EnableMouse(true); f:SetMovable(true); f:SetClampedToScreen(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) self:StartMoving() end)
    f:SetScript("OnDragStop",  function(self) self:StopMovingOrSizing() end)

    local titleBar = BNB.CreateSkinStrip(f, true, false)
    titleBar:SetPoint("TOPLEFT",  f, "TOPLEFT",  0, 0)
    titleBar:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
    titleBar:SetHeight(SK_HW_TITLE_H)
    titleBar:EnableMouse(true)
    titleBar:RegisterForDrag("LeftButton")
    titleBar:SetScript("OnDragStart", function() f:StartMoving() end)
    titleBar:SetScript("OnDragStop",  function() f:StopMovingOrSizing() end)

    local titleLbl = titleBar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    titleLbl:SetPoint("CENTER", titleBar, "CENTER", -12, 0)
    titleLbl:SetTextColor(1, 0.82, 0)
    titleLbl:SetText(L["HISTORY_WINDOW_TITLE"])

    local closeBtn = BNB.CreateSkinCloseButton(titleBar, function() BNB.CloseHistoryWindow() end)
    closeBtn:SetPoint("RIGHT", titleBar, "RIGHT", -3, 0)

    -- Scroll frame
    local sf = CreateFrame("ScrollFrame", nil, f, "ScrollFrameTemplate")
    sf:SetPoint("TOPLEFT",     f, "TOPLEFT",      PAD, -(SK_HW_TITLE_H + 4))
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

    -- Footer divider (host frame avoids backdrop overdraw)
    local footHost = CreateFrame("Frame", nil, f)
    footHost:SetHeight(1)
    footHost:SetPoint("BOTTOMLEFT",  f, "BOTTOMLEFT",  PAD,       BOTTOM_STRIP_H - 1)
    footHost:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -PAD - 28, BOTTOM_STRIP_H - 1)
    local footDiv = BNB.CreateDivider(footHost, "HORIZONTAL", 0.25, 0.25, 0.28, 1)
    footDiv:SetPoint("TOPLEFT",  footHost, "TOPLEFT",  0, 0)
    footDiv:SetPoint("TOPRIGHT", footHost, "TOPRIGHT", 0, 0)

    -- Clear all button
    local clearBtn = BNB.CreateButton(nil, f, L["HISTORY_CLEAR_ALL_BTN"], 140, 26)
    clearBtn:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", PAD, 10)
    clearBtn:SetEnabled(false)
    clearBtn:SetScript("OnClick", function() StaticPopup_Show("BNB_HISTORY_CLEAR_ALL") end)
    clearBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(L["HISTORY_CLEAR_ALL_TIP"], 1, 1, 1)
        GameTooltip:AddLine("This cannot be undone.", 0.8, 0.4, 0.4, true)
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

    -- Click blocker
    local blocker = CreateFrame("Frame", nil, f)
    blocker:SetAllPoints()
    blocker:SetFrameLevel(f:GetFrameLevel() + 50)
    blocker:EnableMouse(true)
    blocker:Hide()
    _blocker = blocker

    if not StaticPopupDialogs["BNB_HISTORY_CLEAR_ALL"] then
        StaticPopupDialogs["BNB_HISTORY_CLEAR_ALL"] = {
            text          = L["HISTORY_CLEAR_ALL_CONFIRM"],
            button1       = L["HISTORY_OVERRIDE_OVERRIDE"],
            button2       = "Cancel",
            OnAccept      = function()
                local ndb = BigNoteBoxNotesDB
                if ndb and ndb.notes then
                    for id in pairs(ndb.notes) do BNB.HistoryDeleteAuto(id) end
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

    f:SetScript("OnShow", function()
        if BNB.ApplyMainWindowSkin then BNB.ApplyMainWindowSkin() end
    end)
    f:Hide()
    tinsert(UISpecialFrames, "BigNoteBoxHistoryFrame")
    _hwFrame = f
    return f
end

local function BuildHistoryWindow()
    if _hwFrame then return _hwFrame end

    local f = CreateFrame("Frame", "BigNoteBoxHistoryFrame", UIParent,
        "ButtonFrameTemplate")
    f:SetWidth(HW_W)
    f:SetFrameStrata("HIGH"); f:SetToplevel(true)
    f:EnableMouse(true); f:SetMovable(true); f:SetClampedToScreen(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) self:StartMoving() end)
    f:SetScript("OnDragStop",  function(self) self:StopMovingOrSizing() end)

    ButtonFrameTemplate_HidePortrait(f)
    ButtonFrameTemplate_HideButtonBar(f)
    if f.Inset then f.Inset:Hide() end
    f:SetTitle(L["HISTORY_WINDOW_TITLE"])

    if f.CloseButton then
        f.CloseButton:SetScript("OnClick", function() BNB.CloseHistoryWindow() end)
    end

    -- Scroll frame
    local sf = CreateFrame("ScrollFrame", nil, f, "ScrollFrameTemplate")
    sf:SetPoint("TOPLEFT",     f, "TOPLEFT",      PAD, -(TITLE_H + 4))
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

    -- Bottom rule
    local rule = f:CreateTexture(nil, "ARTWORK")
    rule:SetHeight(1); rule:SetColorTexture(0.25, 0.25, 0.28, 1)
    rule:SetPoint("BOTTOMLEFT",  f, "BOTTOMLEFT",  PAD,        BOTTOM_STRIP_H - 1)
    rule:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -PAD - 28,  BOTTOM_STRIP_H - 1)

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
        GameTooltip:AddLine("This cannot be undone.", 0.8, 0.4, 0.4, true)
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
            button2       = "Cancel",
            OnAccept      = function()
                local ndb = BigNoteBoxNotesDB
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

    f:Hide()
    tinsert(UISpecialFrames, "BigNoteBoxHistoryFrame")
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
    local f
    if BigNoteBoxDB and BigNoteBoxDB.skinMode then
        f = BuildHistoryWindowSkin()
    else
        f = BuildHistoryWindow()
    end
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

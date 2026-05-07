-- BigNoteBox UI/AlarmOverview.lua
-- Two responsibilities:
--   1. BNB.AlarmPopup  — the in-game popup that fires when an alarm is due.
--   2. BNB.AlarmOverview — the global alarm overview window (left of main window).

local BNB = BigNoteBox
if not BNB then return end

-- ============================================================================
-- ALARM POPUP
-- ============================================================================
BNB.AlarmPopup = BNB.AlarmPopup or {}
local AP = BNB.AlarmPopup

local POPUP_W   = 300
local POPUP_PAD = 12

local _popupFrame = nil

local function BuildPopup()
    if _popupFrame then return _popupFrame end

    -- Use sticky-note style: dark bg, default border, slight transparency
    local f = BNB.CreateBackdropFrame("Frame", "BNBAlarmPopupFrame", UIParent)
    f:SetSize(POPUP_W, 10)
    f:SetFrameStrata("DIALOG")
    f:SetToplevel(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function() f:StartMoving() end)
    f:SetScript("OnDragStop",  function() f:StopMovingOrSizing() end)
    -- Sticky note background: dark with slight transparency and border
    BNB.SetBackdrop(f, 0.07, 0.07, 0.09, 0.96, 0.35, 0.35, 0.38, 1)
    f:Hide()

    -- Icon (32x32)
    local iconTx = f:CreateTexture(nil, "ARTWORK")
    iconTx:SetSize(32, 32)
    iconTx:SetPoint("TOPLEFT", f, "TOPLEFT", POPUP_PAD, -POPUP_PAD)
    f._iconTx = iconTx

    -- Two glow targets:
    --   _windowGlowHost — full window frame (used for Pixel, AutoCast, Border)
    --   _iconGlowHost   — over the icon only (used for Proc)
    -- AP.Show picks which to register based on the alarm's glow type.
    local windowGlowHost = CreateFrame("Frame", nil, f)
    windowGlowHost:SetAllPoints(f)
    windowGlowHost:SetFrameLevel(f:GetFrameLevel() + 10)
    windowGlowHost:EnableMouse(false)
    f._windowGlowHost = windowGlowHost

    local iconGlowHost = CreateFrame("Frame", nil, f)
    iconGlowHost:SetSize(32, 32)
    iconGlowHost:SetPoint("TOPLEFT", f, "TOPLEFT", POPUP_PAD, -POPUP_PAD)
    iconGlowHost:SetFrameLevel(f:GetFrameLevel() + 11)
    iconGlowHost:EnableMouse(false)
    f._iconGlowHost = iconGlowHost

    -- Title
    local titleLbl = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    titleLbl:SetPoint("TOPLEFT",  f, "TOPLEFT",  POPUP_PAD + 38, -POPUP_PAD)
    titleLbl:SetPoint("TOPRIGHT", f, "TOPRIGHT", -POPUP_PAD,     -POPUP_PAD)
    titleLbl:SetJustifyH("LEFT")
    titleLbl:SetTextColor(1, 0.85, 0.2, 1)
    f._titleLbl = titleLbl

    -- Label
    local labelLbl = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    labelLbl:SetPoint("TOPLEFT",  f, "TOPLEFT",  POPUP_PAD + 38, -POPUP_PAD - 16)
    labelLbl:SetPoint("TOPRIGHT", f, "TOPRIGHT", -POPUP_PAD,     -POPUP_PAD - 16)
    labelLbl:SetJustifyH("LEFT")
    labelLbl:SetTextColor(0.9, 0.9, 0.9, 1)
    f._labelLbl = labelLbl

    -- Divider
    local div = f:CreateTexture(nil, "ARTWORK")
    div:SetHeight(1)
    div:SetPoint("TOPLEFT",  f, "TOPLEFT",  POPUP_PAD, -POPUP_PAD - 42)
    div:SetPoint("TOPRIGHT", f, "TOPRIGHT", -POPUP_PAD, -POPUP_PAD - 42)
    div:SetColorTexture(0.28, 0.28, 0.30, 1)

    -- Snooze row: button + dropdown
    local snoozeEntries = {
        { label = "1 min",  value = 1  },
        { label = "5 min",  value = 5  },
        { label = "10 min", value = 10 },
        { label = "15 min", value = 15 },
        { label = "30 min", value = 30 },
        { label = "60 min", value = 60 },
    }
    local contentW = POPUP_W - POPUP_PAD * 2

    -- Snooze button
    local snoozeBtn = BNB.CreateButton(nil, f, "Snooze", math.floor(contentW * 0.5) - 4, 24)
    snoozeBtn:SetPoint("TOPLEFT", f, "TOPLEFT", POPUP_PAD, -POPUP_PAD - 52)
    f._snoozeBtn = snoozeBtn

    -- Snooze duration dropdown (right of snooze button)
    local snoozeDDW = math.floor(contentW * 0.5)
    local snoozeDDContainer
    if C_XMLUtil and C_XMLUtil.GetTemplateInfo
       and C_XMLUtil.GetTemplateInfo("WowStyle1DropdownTemplate") then
        local dd = CreateFrame("DropdownButton", nil, f, "WowStyle1DropdownTemplate")
        dd:SetToplevel(true)
        dd:SetWidth(snoozeDDW)
        dd:SetHeight(24)
        dd:SetPoint("LEFT", snoozeBtn, "RIGHT", 8, 0)
        dd._selected = 5
        dd:SetText("5 min")
        dd:SetupMenu(function(_, root)
            for _, e in ipairs(snoozeEntries) do
                root:CreateRadio(e.label,
                    function() return dd._selected == e.value end,
                    function()
                        dd._selected = e.value
                        dd:SetText(e.label)
                    end)
            end
        end)
        snoozeDDContainer = dd
    else
        snoozeDDContainer = BNB.CreateBackdropFrame("Button", nil, f)
        snoozeDDContainer:SetSize(snoozeDDW, 24)
        snoozeDDContainer:SetPoint("LEFT", snoozeBtn, "RIGHT", 8, 0)
        local l = snoozeDDContainer:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
        l:SetAllPoints(); l:SetText("5 min"); l:SetJustifyH("CENTER")
        snoozeDDContainer._selected = 5
    end
    f._snoozeDDContainer = snoozeDDContainer

    -- Dismiss button
    -- Bottom row: | Open Note | Dismiss |
    local btnRowW = math.floor(contentW / 2) - 4
    local openNoteBtn = BNB.CreateButton(nil, f, "Open Note", btnRowW, 24)
    openNoteBtn:SetPoint("TOPLEFT", f, "TOPLEFT", POPUP_PAD, -POPUP_PAD - 52 - 32)
    f._openNoteBtn = openNoteBtn

    local dismissBtn = BNB.CreateButton(nil, f, "Dismiss", btnRowW, 24)
    dismissBtn:SetPoint("LEFT", openNoteBtn, "RIGHT", 8, 0)
    f._dismissBtn = dismissBtn

    f:SetHeight(POPUP_PAD + 42 + 32 + 32 + POPUP_PAD)

    _popupFrame = f
    return f
end

function AP.Show(noteID, alarm, missedList)
    local f    = BuildPopup()
    local note = BNB.GetNote and BNB.GetNote(noteID)
    if not note then return end

    f._currentNoteID = noteID

    -- Icon
    if note.icon then
        f._iconTx:SetTexture(note.icon)
    else
        f._iconTx:SetTexture("Interface/AddOns/BigNoteBox/Assets/Topbar/tp-alarm")
    end

    -- Text
    local titleText = (note.title and note.title ~= "") and note.title or "Untitled"
    f._titleLbl:SetText(titleText)
    local labelText = (alarm and alarm.label and alarm.label ~= "") and alarm.label or ""
    f._labelLbl:SetText(labelText)
    f._labelLbl:SetShown(labelText ~= "")

    -- Snooze default
    local defSnooze = (alarm and alarm.snoozeDefault) or 5
    if f._snoozeDDContainer._selected then
        f._snoozeDDContainer._selected = defSnooze
        if f._snoozeDDContainer.SetText then
            f._snoozeDDContainer:SetText(defSnooze .. " min")
        end
    end

    -- Wire buttons
    f._openNoteBtn:SetScript("OnClick", function()
        if BNB.Alarm and BNB.Alarm.GlowStop then BNB.Alarm.GlowStop(f._glowNoteID) end
        if f._iconHost and BNB.Alarm and BNB.Alarm.UnregisterGlowTarget then
            BNB.Alarm.UnregisterGlowTarget(f._glowNoteID, f._iconHost)
        end
        BNB.Alarm.Dismiss(noteID)
        f:Hide()
        if not BNB.mainFrame then
            if BNB.CreateMainWindow then BNB.CreateMainWindow() end
        end
        if BNB.mainFrame then BNB.mainFrame:Show() end
        if BNB.SelectNote then BNB.SelectNote(noteID) end
    end)

    f._snoozeBtn:SetScript("OnClick", function()
        local mins = f._snoozeDDContainer._selected or defSnooze
        if BNB.Alarm and BNB.Alarm.GlowStop then BNB.Alarm.GlowStop(f._glowNoteID) end
        if f._iconHost and BNB.Alarm and BNB.Alarm.UnregisterGlowTarget then
            BNB.Alarm.UnregisterGlowTarget(f._glowNoteID, f._iconHost)
        end
        BNB.Alarm.Snooze(noteID, mins)
        f:Hide()
    end)
    f._dismissBtn:SetScript("OnClick", function()
        if BNB.Alarm and BNB.Alarm.GlowStop then BNB.Alarm.GlowStop(f._glowNoteID) end
        if f._iconHost and BNB.Alarm and BNB.Alarm.UnregisterGlowTarget then
            BNB.Alarm.UnregisterGlowTarget(f._glowNoteID, f._iconHost)
        end
        BNB.Alarm.Dismiss(noteID)
        f:Hide()
    end)

    f:ClearAllPoints()
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 60)
    f:Show()
    f:Raise()

    -- Pick glow target: Proc (4) → icon only; all others → full window
    if BNB.Alarm then
        local gType = BNB.Alarm.GetGlowType and BNB.Alarm.GetGlowType(alarm) or 2
        local target = (gType == 4) and f._iconGlowHost or f._windowGlowHost
        -- Keep backward compat field so dismiss/snooze cleanup still works
        f._iconHost = target
        if BNB.Alarm.RegisterGlowTarget then
            BNB.Alarm.RegisterGlowTarget(noteID, target)
        end
        if BNB.Alarm.GlowStart then
            BNB.Alarm.GlowStart(noteID)
        end
    end
    f._glowNoteID = noteID
end

-- ============================================================================
-- ALARM OVERVIEW WINDOW
-- ============================================================================
BNB.AlarmOverview = BNB.AlarmOverview or {}
local AO = BNB.AlarmOverview

local OV_W    = 310
local OV_H    = 400
local OV_PAD  = 10
local OV_ROW  = 36

local _ovFrame    = nil
local _ovCtxDD    = nil  -- reusable right-click dropdown
local _ovMultiMode = false
local _ovMultiSel  = {}  -- { [noteID] = true }
-- Footer button refs (set during BuildOverview, used by SetOvMultiMode)
local _ovSelectBtn    = nil   -- "Select" (normal) / "Cancel" (select mode)
local _ovSelectAllBtn = nil   -- "Select All" (select mode only)
local _ovDeleteSelBtn = nil   -- "Delete (N)" (select mode only)
local _ovFootDiv      = nil   -- footer separator line

local function UpdateOvDeleteLabel()
    if not _ovDeleteSelBtn then return end
    local n = 0
    for _ in pairs(_ovMultiSel) do n = n + 1 end
    _ovDeleteSelBtn:SetText(n > 0 and ("Delete (" .. n .. ")") or "Delete (0)")
    _ovDeleteSelBtn:SetEnabled(n > 0)
    if _ovDeleteSelBtn.GetFontString and _ovDeleteSelBtn:GetFontString() then
        _ovDeleteSelBtn:GetFontString():SetTextColor(0.9, 0.4, 0.4, 1)
    end
end

local function FormatFireTime(noteID)
    local t = BNB.Alarm and BNB.Alarm.GetNextFireTime(noteID)
    if not t then return "|cffff4444Fired|r" end
    local diff = t - time()
    if diff < 0    then return "|cffff4444Overdue|r" end
    if diff < 60   then return "|cff66bb6a< 1 min|r" end
    if diff < 3600 then return string.format("|cff66bb6a%d min|r", math.floor(diff / 60)) end
    if diff < 86400 then return string.format("|cff66bb6a%dh %dm|r",
        math.floor(diff / 3600), math.floor((diff % 3600) / 60)) end
    return string.format("|cff66bb6a%s|r", date("%Y-%m-%d %H:%M", t))
end

-- Full timestamp for tooltip
local function FullFireTime(noteID)
    local t = BNB.Alarm and BNB.Alarm.GetNextFireTime(noteID)
    if not t then return "No scheduled time" end
    return date("%Y-%m-%d %H:%M", t)
end

-- (status color now embedded in FormatFireTime via color codes)

local OV_TITLE_H  = 32
local OV_CONTENT_W = OV_W - OV_PAD * 2 - 28  -- 28px right clearance (scrollbar)

local OV_FOOT_H = 44   -- footer strip height (buttons 26px + 14px bottom offset + 4px gap)

local function SetOvMultiMode(enabled)
    _ovMultiMode = enabled
    _ovMultiSel  = {}

    local f = _ovFrame
    if not f then return end

    -- How many alarms exist? Hide Select entirely on empty list.
    local hasAlarms = false
    local ndb = BigNoteBoxNotesDB
    if ndb and ndb.notes then
        for _, note in pairs(ndb.notes) do
            if note.alarm then hasAlarms = true; break end
        end
    end

    local BW1 = OV_W - OV_PAD * 2
    local BW3 = math.floor((OV_W - OV_PAD * 2 - 12) / 3)

    if enabled then
        -- Three-button layout: Cancel | Select All | Delete (N)
        if _ovSelectBtn then
            _ovSelectBtn:SetText("Cancel")
            _ovSelectBtn:SetWidth(BW3)
            _ovSelectBtn:ClearAllPoints()
            _ovSelectBtn:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", OV_PAD, 14)
            _ovSelectBtn:Show()
        end
        if _ovSelectAllBtn then
            _ovSelectAllBtn:SetWidth(BW3)
            _ovSelectAllBtn:ClearAllPoints()
            _ovSelectAllBtn:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", OV_PAD + BW3 + 6, 14)
            _ovSelectAllBtn:Show()
        end
        if _ovDeleteSelBtn then
            _ovDeleteSelBtn:SetWidth(BW3)
            _ovDeleteSelBtn:ClearAllPoints()
            _ovDeleteSelBtn:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", OV_PAD + (BW3 + 6) * 2, 14)
            _ovDeleteSelBtn:Show()
            UpdateOvDeleteLabel()
        end
    else
        -- Normal mode: one full-width "Select" button (hidden when no alarms)
        if _ovSelectBtn then
            _ovSelectBtn:SetText("Select")
            _ovSelectBtn:SetWidth(BW1)
            _ovSelectBtn:ClearAllPoints()
            _ovSelectBtn:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", OV_PAD, 14)
            _ovSelectBtn:SetShown(hasAlarms)
        end
        if _ovSelectAllBtn then _ovSelectAllBtn:Hide() end
        if _ovDeleteSelBtn  then _ovDeleteSelBtn:Hide()  end
    end

    if BNB.AlarmOverview and BNB.AlarmOverview.Refresh then
        BNB.AlarmOverview.Refresh()
    end
end

local function BuildOverview()
    if _ovFrame then return _ovFrame end

    -- Use ButtonFrameTemplate to match TrashWindow/TagManager visual style
    local f = CreateFrame("Frame", "BNBAlarmOverviewFrame", UIParent, "ButtonFrameTemplate")
    f:SetSize(OV_W, OV_H)
    f:SetFrameStrata("HIGH"); f:SetToplevel(true)
    f:SetMovable(true); f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) self:StartMoving() end)
    f:SetScript("OnDragStop",  function(self) self:StopMovingOrSizing() end)

    ButtonFrameTemplate_HidePortrait(f)
    ButtonFrameTemplate_HideButtonBar(f)
    if f.Inset then f.Inset:Hide() end
    f:SetTitle("Alarms")

    if f.CloseButton then
        f.CloseButton:SetScript("OnClick", function() f:Hide() end)
    end

    -- Scroll frame — bottom raised to leave room for footer strip
    local sf = CreateFrame("ScrollFrame", nil, f, "ScrollFrameTemplate")
    sf:SetPoint("TOPLEFT",     f, "TOPLEFT",     OV_PAD, -(OV_TITLE_H + 4))
    sf:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -28, OV_FOOT_H + OV_PAD)

    -- Hide scrollbar when not needed (alpha only - never Show/Hide ScrollFrameTemplate)
    if sf.ScrollBar then
        sf.ScrollBar:SetAlpha(0)
        sf:HookScript("OnScrollRangeChanged", function(_, _, yRange)
            sf.ScrollBar:SetAlpha((yRange or 0) > 1 and 1.0 or 0)
        end)
    end

    local ct = CreateFrame("Frame", nil, sf)
    ct:SetWidth(OV_CONTENT_W)
    ct:SetHeight(1)
    sf:SetScrollChild(ct)

    -- ── Footer strip ──────────────────────────────────────────────────────────
    local footDiv = f:CreateTexture(nil, "ARTWORK")
    footDiv:SetHeight(1)
    footDiv:SetPoint("BOTTOMLEFT",  f, "BOTTOMLEFT",  OV_PAD, OV_FOOT_H)
    footDiv:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -OV_PAD, OV_FOOT_H)
    footDiv:SetColorTexture(0.28, 0.28, 0.30, 1)
    _ovFootDiv = footDiv

    local BW1 = OV_W - OV_PAD * 2
    local BW3 = math.floor((OV_W - OV_PAD * 2 - 12) / 3)

    local selectBtn = BNB.CreateButton(nil, f, "Select", BW1, 26)
    selectBtn:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", OV_PAD, 14)
    selectBtn:SetScript("OnClick", function()
        SetOvMultiMode(not _ovMultiMode)
    end)
    _ovSelectBtn = selectBtn

    local selectAllBtn = BNB.CreateButton(nil, f, "Select All", BW3, 26)
    selectAllBtn:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", OV_PAD + BW3 + 6, 14)
    selectAllBtn:Hide()
    selectAllBtn:SetScript("OnClick", function()
        local ndb = BigNoteBoxNotesDB
        if ndb and ndb.notes then
            for noteID, note in pairs(ndb.notes) do
                if note.alarm then _ovMultiSel[noteID] = true end
            end
        end
        UpdateOvDeleteLabel()
        if BNB.AlarmOverview and BNB.AlarmOverview.Refresh then
            BNB.AlarmOverview.Refresh()
        end
    end)
    _ovSelectAllBtn = selectAllBtn

    local deleteSelBtn = BNB.CreateButton(nil, f, "Delete (0)", BW3, 26)
    deleteSelBtn:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", OV_PAD + (BW3 + 6) * 2, 14)
    deleteSelBtn:GetFontString():SetTextColor(0.9, 0.4, 0.4, 1)
    deleteSelBtn:SetEnabled(false)
    deleteSelBtn:Hide()
    deleteSelBtn:SetScript("OnClick", function()
        for noteID in pairs(_ovMultiSel) do
            if BNB.Alarm and BNB.Alarm.ClearAlarm then BNB.Alarm.ClearAlarm(noteID) end
        end
        SetOvMultiMode(false)
    end)
    _ovDeleteSelBtn = deleteSelBtn

    f._scrollContent = ct
    f._rowPool       = {}

    f:HookScript("OnHide", function() SetOvMultiMode(false) end)

    f:Hide()
    tinsert(UISpecialFrames, "BNBAlarmOverviewFrame")
    _ovFrame = f
    return f
end

-- ---------------------------------------------------------------------------
-- BUILD OVERVIEW  (SKIN VERSION)
-- ---------------------------------------------------------------------------
local SK_OV_TITLE_H = 28

local function BuildOverviewSkin()
    if _ovFrame then return _ovFrame end

    local f = BNB.CreateSkinFrame(UIParent, false, "BNBAlarmOverviewFrame", false)
    _G["BNBAlarmOverviewFrame"] = f
    f:SetSize(OV_W, OV_H)
    f:SetFrameStrata("HIGH"); f:SetToplevel(true)
    f:SetMovable(true); f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) self:StartMoving() end)
    f:SetScript("OnDragStop",  function(self) self:StopMovingOrSizing() end)

    -- Title strip
    local titleBar = BNB.CreateSkinStrip(f, true, false)
    titleBar:SetPoint("TOPLEFT",  f, "TOPLEFT",  0, 0)
    titleBar:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
    titleBar:SetHeight(SK_OV_TITLE_H)
    titleBar:EnableMouse(true)
    titleBar:RegisterForDrag("LeftButton")
    titleBar:SetScript("OnDragStart", function() f:StartMoving() end)
    titleBar:SetScript("OnDragStop",  function() f:StopMovingOrSizing() end)

    local titleLbl = titleBar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    titleLbl:SetPoint("CENTER", titleBar, "CENTER", -12, 0)
    titleLbl:SetTextColor(1, 0.82, 0)
    titleLbl:SetText("Alarms")

    local closeBtn = BNB.CreateSkinCloseButton(titleBar, function() f:Hide() end)
    closeBtn:SetPoint("RIGHT", titleBar, "RIGHT", -3, 0)

    -- Scroll frame
    local sf = CreateFrame("ScrollFrame", nil, f, "ScrollFrameTemplate")
    sf:SetPoint("TOPLEFT",     f, "TOPLEFT",     OV_PAD, -(SK_OV_TITLE_H + 4))
    sf:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -28, OV_FOOT_H + OV_PAD)

    if sf.ScrollBar then
        sf.ScrollBar:SetAlpha(0)
        sf:HookScript("OnScrollRangeChanged", function(_, _, yRange)
            sf.ScrollBar:SetAlpha((yRange or 0) > 1 and 1.0 or 0)
        end)
    end

    local ct = CreateFrame("Frame", nil, sf)
    ct:SetWidth(OV_CONTENT_W)
    ct:SetHeight(1)
    sf:SetScrollChild(ct)

    -- Footer divider (host frame avoids backdrop overdraw)
    local footHost = CreateFrame("Frame", nil, f)
    footHost:SetHeight(1)
    footHost:SetPoint("BOTTOMLEFT",  f, "BOTTOMLEFT",  OV_PAD, OV_FOOT_H)
    footHost:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -OV_PAD, OV_FOOT_H)
    local footDiv = BNB.CreateDivider(footHost, "HORIZONTAL", 0.28, 0.28, 0.30, 1)
    footDiv:SetPoint("TOPLEFT",  footHost, "TOPLEFT",  0, 0)
    footDiv:SetPoint("TOPRIGHT", footHost, "TOPRIGHT", 0, 0)
    _ovFootDiv = footHost   -- hide the host to hide the divider

    local BW1 = OV_W - OV_PAD * 2
    local BW3 = math.floor((OV_W - OV_PAD * 2 - 12) / 3)

    local selectBtn = BNB.CreateButton(nil, f, "Select", BW1, 26)
    selectBtn:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", OV_PAD, 14)
    selectBtn:SetScript("OnClick", function() SetOvMultiMode(not _ovMultiMode) end)
    _ovSelectBtn = selectBtn

    local selectAllBtn = BNB.CreateButton(nil, f, "Select All", BW3, 26)
    selectAllBtn:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", OV_PAD + BW3 + 6, 14)
    selectAllBtn:Hide()
    selectAllBtn:SetScript("OnClick", function()
        local ndb = BigNoteBoxNotesDB
        if ndb and ndb.notes then
            for noteID, note in pairs(ndb.notes) do
                if note.alarm then _ovMultiSel[noteID] = true end
            end
        end
        UpdateOvDeleteLabel()
        if BNB.AlarmOverview and BNB.AlarmOverview.Refresh then
            BNB.AlarmOverview.Refresh()
        end
    end)
    _ovSelectAllBtn = selectAllBtn

    local deleteSelBtn = BNB.CreateButton(nil, f, "Delete (0)", BW3, 26)
    deleteSelBtn:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", OV_PAD + (BW3 + 6) * 2, 14)
    deleteSelBtn:GetFontString():SetTextColor(0.9, 0.4, 0.4, 1)
    deleteSelBtn:SetEnabled(false)
    deleteSelBtn:Hide()
    deleteSelBtn:SetScript("OnClick", function()
        for noteID in pairs(_ovMultiSel) do
            if BNB.Alarm and BNB.Alarm.ClearAlarm then BNB.Alarm.ClearAlarm(noteID) end
        end
        SetOvMultiMode(false)
    end)
    _ovDeleteSelBtn = deleteSelBtn

    f._scrollContent = ct
    f._rowPool       = {}

    f:HookScript("OnHide", function() SetOvMultiMode(false) end)

    f:SetScript("OnShow", function()
        if BNB.ApplyMainWindowSkin then BNB.ApplyMainWindowSkin() end
    end)

    f:Hide()
    tinsert(UISpecialFrames, "BNBAlarmOverviewFrame")
    _ovFrame = f
    return f
end

local function GetOrBuildOverview()
    if _ovFrame then return _ovFrame end
    if BigNoteBoxDB and BigNoteBoxDB.skinMode then
        return BuildOverviewSkin()
    else
        return BuildOverview()
    end
end

-- Row layout matches HistoryWindow: 36px icon left, title + label text,
-- date/time bottom-right, separator line at bottom.
local OV_ICON_SZ   = 36
local OV_TEXT_LEFT = OV_PAD + OV_ICON_SZ + 8

local function MakeRow(parent)
    local row = CreateFrame("Button", nil, parent)
    row:SetHeight(OV_ROW)
    row:SetPoint("LEFT",  parent, "LEFT", 0, 0)
    row:SetWidth(OV_CONTENT_W)

    -- Hover highlight
    local hl = row:CreateTexture(nil, "BACKGROUND")
    hl:SetAllPoints(); hl:SetColorTexture(1,1,1,0.05); hl:Hide()
    row:SetScript("OnEnter", function(self) hl:Show() end)
    row:SetScript("OnLeave", function(self) hl:Hide() end)

    -- Selection highlight (multi-select mode)
    local selHi = row:CreateTexture(nil, "BACKGROUND")
    selHi:SetAllPoints(); selHi:SetColorTexture(0.4, 0.7, 0.4, 0.18); selHi:Hide()
    row._selHi = selHi

    -- Icon (36x36 matching HistoryWindow)
    local iconTx = row:CreateTexture(nil, "ARTWORK")
    iconTx:SetSize(OV_ICON_SZ, OV_ICON_SZ)
    iconTx:SetPoint("LEFT", row, "LEFT", OV_PAD, 0)
    iconTx:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    -- Glow target frame over the icon (for alarm glow animation in overview)
    local iconGlowFrame = CreateFrame("Frame", nil, row)
    iconGlowFrame:SetSize(OV_ICON_SZ, OV_ICON_SZ)
    iconGlowFrame:SetPoint("LEFT", row, "LEFT", OV_PAD, 0)
    iconGlowFrame:SetFrameLevel(row:GetFrameLevel() + 10)
    iconGlowFrame:EnableMouse(false)

    -- Title
    local titleLbl = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    titleLbl:SetPoint("TOPLEFT",  row, "TOPLEFT",  OV_TEXT_LEFT, -5)
    titleLbl:SetPoint("TOPRIGHT", row, "TOPRIGHT", -4, -5)
    titleLbl:SetJustifyH("LEFT"); titleLbl:SetHeight(16)

    -- Alarm label (subtitle)
    local labelLbl = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    labelLbl:SetPoint("TOPLEFT",  row, "TOPLEFT",  OV_TEXT_LEFT, -22)
    labelLbl:SetPoint("TOPRIGHT", row, "TOPRIGHT", -4, -22)
    labelLbl:SetJustifyH("LEFT"); labelLbl:SetHeight(14)
    labelLbl:SetTextColor(0.55, 0.55, 0.55, 1)

    -- Date/time bottom-right
    local timeLbl = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    timeLbl:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -4, 6)
    timeLbl:SetHeight(12); timeLbl:SetJustifyH("RIGHT")
    timeLbl:SetTextColor(0.50, 0.50, 0.50, 1)

    -- Reset button (shown when alarm.fired)
    local resetBtn = BNB.CreateButton(nil, row, "Reset", 52, 16)
    resetBtn:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -4, 4)
    resetBtn:Hide()

    -- Bottom separator (same as HistoryWindow)
    local sep = row:CreateTexture(nil, "ARTWORK")
    sep:SetHeight(1)
    sep:SetPoint("BOTTOMLEFT",  row, "BOTTOMLEFT",  0, 0)
    sep:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 0)
    sep:SetColorTexture(0.22, 0.22, 0.25, 1)

    row._iconTx        = iconTx
    row._iconGlowFrame = iconGlowFrame
    row._titleLbl      = titleLbl
    row._labelLbl      = labelLbl
    row._timeLbl       = timeLbl
    row._resetBtn      = resetBtn
    return row
end

local function GetSortedAlarmNotes()
    local ndb = BigNoteBoxNotesDB
    if not ndb or not ndb.notes then return {} end
    local list = {}
    for noteID, note in pairs(ndb.notes) do
        if note.alarm then
            table.insert(list, { noteID = noteID, note = note })
        end
    end
    -- Sort: active first, then snoozed, then fired; within group by next fire time
    table.sort(list, function(a, b)
        local aa, ba = a.note.alarm, b.note.alarm
        local afired = aa.fired and 1 or 0
        local bfired = ba.fired and 1 or 0
        if afired ~= bfired then return afired < bfired end
        local at = BNB.Alarm.GetNextFireTime(a.noteID) or math.huge
        local bt = BNB.Alarm.GetNextFireTime(b.noteID) or math.huge
        return at < bt
    end)
    return list
end

function AO.Refresh()
    local f = GetOrBuildOverview()
    local ct = f._scrollContent
    local pool = f._rowPool

    -- Hide all pooled rows
    for _, row in ipairs(pool) do row:Hide() end

    local entries = GetSortedAlarmNotes()
    ct:SetHeight(math.max(1, #entries * (OV_ROW + 2)))

    -- Track glow frames from previous pass to stop stale glows
    local prevGlowNotes = f._ovGlowNotes or {}
    f._ovGlowNotes = {}

    for i, entry in ipairs(entries) do
        local row = pool[i]
        if not row then
            row = MakeRow(ct)
            pool[i] = row
        end

        local noteID = entry.noteID
        local note   = entry.note
        local alarm  = note.alarm

        row:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, -(i-1) * (OV_ROW + 2))
        row:Show()

        -- Sync selection highlight
        if row._selHi then row._selHi:SetShown(_ovMultiSel[noteID] == true) end

        -- Icon
        local iconTex = note.icon or "Interface/AddOns/BigNoteBox/Assets/icon"
        row._iconTx:SetTexture(iconTex)

        -- Title
        local t = (note.title and note.title ~= "") and note.title or "Untitled"
        row._titleLbl:SetText(t)

        -- Alarm label
        local lbl = (alarm.label and alarm.label ~= "") and alarm.label or ""
        row._labelLbl:SetText(lbl)
        row._labelLbl:SetShown(lbl ~= "")

        -- Desaturate icon and grey title for fired alarms
        if alarm.fired then
            pcall(function() row._iconTx:SetDesaturated(true) end)
            row._titleLbl:SetTextColor(0.45, 0.45, 0.45, 1)
            row._timeLbl:Hide(); row._resetBtn:Show()
            row._resetBtn:SetScript("OnClick", function()
                BNB.Alarm.ResetFired(noteID)
            end)
        else
            pcall(function() row._iconTx:SetDesaturated(false) end)
            row._titleLbl:SetTextColor(1, 1, 1, 1)
            row._timeLbl:SetText(FormatFireTime(noteID))
            row._timeLbl:Show(); row._resetBtn:Hide()
        end

        -- Glow on icon for active alarms that have glow configured
        -- Register the icon glow frame so AlarmManager can animate it
        if BNB.Alarm and BNB.Alarm.RegisterGlowTarget then
            BNB.Alarm.RegisterGlowTarget(noteID, row._iconGlowFrame)
        end
        f._ovGlowNotes[noteID] = row._iconGlowFrame

        -- Left-click: open alarm config for this note
        -- Right-click: context menu
        row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        row:SetScript("OnClick", function(self, btn)
            -- In multi-select mode, left-click toggles selection
            if _ovMultiMode then
                if btn == "LeftButton" then
                    if _ovMultiSel[noteID] then
                        _ovMultiSel[noteID] = nil
                    else
                        _ovMultiSel[noteID] = true
                    end
                    -- Update selection highlight and delete label
                    UpdateOvDeleteLabel()
                    if row._selHi then row._selHi:SetShown(_ovMultiSel[noteID] == true) end
                end
                return
            end
            if btn == "RightButton" then
                -- Right-click context menu
                if not _ovCtxDD then
                    _ovCtxDD = CreateFrame("DropdownButton", "BNBAlarmOvCtxDD",
                        UIParent, "WowStyle1DropdownTemplate")
                    _ovCtxDD:SetSize(1,1); _ovCtxDD:SetAlpha(0)
                end
                _ovCtxDD:ClearAllPoints()
                _ovCtxDD:SetPoint("TOPLEFT", self, "TOPRIGHT", 0, 0)
                local nid = noteID  -- capture for closures
                _ovCtxDD:SetupMenu(function(_, root)
                    root:CreateTitle(t)
                    root:CreateButton("Open Alarm", function()
                        if BNB.AlarmWindow and BNB.AlarmWindow.OpenLeftOfMain then
                            BNB.AlarmWindow.OpenLeftOfMain(nid)
                        end
                    end)
                    root:CreateButton("Open Note", function()
                        if not BNB.mainFrame then
                            if BNB.CreateMainWindow then BNB.CreateMainWindow() end
                        end
                        if BNB.mainFrame then BNB.mainFrame:Show() end
                        if BNB.SelectNote then BNB.SelectNote(nid) end
                    end)
                    root:CreateButton("Open as Sticky Note", function()
                        if BNB.Sticky and BNB.Sticky.Open then BNB.Sticky.Open(nid) end
                    end)
                    root:CreateDivider()
                    root:CreateButton("|cffff4444Delete Alarm|r", function()
                        local popup = StaticPopup_Show("BNB_DELETE_ALARM_CONFIRM")
                        if popup then popup.data = nid end
                    end)
                end)
                _ovCtxDD:OpenMenu()
            else
                -- Left-click: open alarm config
                if BNB.AlarmWindow and BNB.AlarmWindow.OpenLeftOfMain then
                    BNB.AlarmWindow.OpenLeftOfMain(noteID)
                end
            end
        end)

        row:SetScript("OnEnter", function()
            GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
            GameTooltip:AddLine(t, 1,1,1)
            if lbl ~= "" then GameTooltip:AddLine(lbl, 0.8,0.8,0.8) end
            local fullTime = FullFireTime(noteID)
            GameTooltip:AddLine(fullTime, 0.6, 0.9, 0.6)
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end

    -- Unregister glow frames for notes no longer in the list
    for noteID, gf in pairs(prevGlowNotes) do
        if not f._ovGlowNotes[noteID] then
            if BNB.Alarm and BNB.Alarm.UnregisterGlowTarget then
                BNB.Alarm.UnregisterGlowTarget(noteID, gf)
            end
        end
    end

    -- Sync Select button and footer divider visibility based on whether alarms exist
    if not _ovMultiMode and _ovSelectBtn then
        _ovSelectBtn:SetShown(#entries > 0)
    end
    if _ovFootDiv then _ovFootDiv:SetShown(#entries > 0) end

    -- Empty state
    if #entries == 0 then
        ct:SetHeight(40)
        if not f._emptyLbl then
            f._emptyLbl = ct:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
            f._emptyLbl:SetPoint("TOP", ct, "TOP", 0, -10)
            f._emptyLbl:SetText("No alarms set.")
            f._emptyLbl:SetTextColor(0.5, 0.5, 0.5, 1)
        end
        f._emptyLbl:Show()
    else
        if f._emptyLbl then f._emptyLbl:Hide() end
    end
end

function AO.Toggle()
    local f = GetOrBuildOverview()
    if f:IsShown() then
        f:Hide()
    else
        AO.Refresh()
        -- Anchor left of main window
        local mf = BNB.mainFrame
        if mf then
            f:ClearAllPoints()
            f:SetPoint("TOPRIGHT", mf, "TOPLEFT", -4, 0)
        else
            f:ClearAllPoints()
            f:SetPoint("CENTER", UIParent, "CENTER", -200, 0)
        end
        f:Show()
        f:Raise()
    end
end

-- Called by AlarmManager when missed alarms are detected on login
-- StaticPopup for alarm delete confirmation
StaticPopupDialogs["BNB_DELETE_ALARM_CONFIRM"] = {
    text = "Delete this alarm?",
    button1 = "Delete",
    button2 = "Cancel",
    OnAccept = function(self)
        local noteID = self.data
        if noteID and BNB.Alarm and BNB.Alarm.ClearAlarm then
            BNB.Alarm.ClearAlarm(noteID)
            AO.Refresh()
        end
    end,
    timeout = 0, whileDead = true, hideOnEscape = true,
}

function AO.ShowMissed(noteIDs)
    local f = GetOrBuildOverview()
    AO.Refresh()
    local mf = BNB.mainFrame
    if mf then
        f:ClearAllPoints()
        f:SetPoint("TOPRIGHT", mf, "TOPLEFT", -4, 0)
    else
        f:ClearAllPoints()
        f:SetPoint("CENTER", UIParent, "CENTER", -200, 0)
    end
    f:Show()
    f:Raise()
    BNB:Print(string.format("[BNB] %d alarm(s) fired while you were offline.", #noteIDs))
end

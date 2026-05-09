-- BigNoteBox UI/TaskEditWindow.lua
-- Per-task configuration window.  ButtonFrameTemplate (normal) or skin frame.
-- Single scroll area -- no tabs.  Fields: text, reset type, situation.
--
-- Public API:
--   BNB.TaskEditWindow.Open(noteID, taskID, anchorFrame)
--   BNB.TaskEditWindow.Close()
--   BNB.TaskEditWindow.IsOpen() -> bool
--   BNB.TaskEditWindow.GetTaskID() -> taskID | nil

local BNB = BigNoteBox
if not BNB then return end

BNB.TaskEditWindow = BNB.TaskEditWindow or {}
local TW = BNB.TaskEditWindow

-- ---------------------------------------------------------------------------
-- LAYOUT
-- ---------------------------------------------------------------------------
local TW_W       = 264
local TW_H       = 340
local TW_PAD     = 12
local TW_CW      = 224   -- content width  (TW_W - 2*TW_PAD - scrollbar pad)
local TW_TOP_Y   = 32    -- below title bar (ButtonFrameTemplate)
local SK_TITLE_H = 28    -- skin title bar height
local TW_FOOT_H  = 38    -- static footer height (Save / Cancel)
local TW_ROW     = 22
local TW_GAP     = 8
local TW_LBL     = 14
local TW_SECT_GAP = 12

local ASSETS = "Interface/AddOns/BigNoteBox/Assets/"

-- ---------------------------------------------------------------------------
-- STATE
-- ---------------------------------------------------------------------------
local _frame        = nil
local _noteID       = nil
local _taskID       = nil
local _isDirty      = false
local _isPopulating = false

-- Widget refs
local _textEB, _resetDD, _sitTypeDD, _sitValueRow, _sitValueEb
local _sitUseCurBtn, _sitBrowseBtn, _sitClearBtn
local _saveBtn

-- Situation state
local _selSitType = "none"
local _pendingText = ""  -- backing store for task text label/editbox

-- ---------------------------------------------------------------------------
-- HELPERS
-- ---------------------------------------------------------------------------
local function HasWowStyle1()
    return C_XMLUtil and C_XMLUtil.GetTemplateInfo
        and C_XMLUtil.GetTemplateInfo("WowStyle1DropdownTemplate") ~= nil
end

local function MarkDirty()
    if _isPopulating then return end
    _isDirty = true
    if _saveBtn then _saveBtn:SetEnabled(true) end
end

-- Local MakeDD mirroring AlarmWindow pattern
local function MakeDD(parent, entries, initial, onChange, width)
    width = width or TW_CW
    local c = CreateFrame("Frame", nil, parent)
    c:SetSize(width, TW_ROW)

    if HasWowStyle1() then
        local dd = CreateFrame("DropdownButton", nil, c, "WowStyle1DropdownTemplate")
        dd:SetToplevel(true); dd:SetWidth(width); dd:SetHeight(TW_ROW)
        dd:SetPoint("TOPLEFT")
        dd._selected = initial
        dd:SetupMenu(function(_, root)
            for _, e in ipairs(entries) do
                local ev = e.value
                root:CreateRadio(e.label,
                    function() return dd._selected == ev end,
                    function()
                        dd._selected = ev; dd:SetText(e.label)
                        MarkDirty()
                        if onChange then onChange(ev) end
                    end)
            end
        end)
        for _, e in ipairs(entries) do
            if e.value == initial then dd:SetText(e.label); break end
        end
        function c:SetSelected(v)
            dd._selected = v
            for _, e in ipairs(entries) do
                if e.value == v then dd:SetText(e.label); return end
            end
            dd:SetText("")
        end
        function c:GetSelected() return dd._selected end
        c._dd = dd
    else
        local idx = 1
        for i, e in ipairs(entries) do if e.value == initial then idx = i; break end end
        local btn = BNB.CreateBackdropFrame("Button", nil, c)
        btn:SetSize(width, TW_ROW); btn:SetPoint("TOPLEFT")
        local lbl = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        lbl:SetAllPoints(); lbl:SetJustifyH("CENTER")
        local function Rf() lbl:SetText(entries[idx] and entries[idx].label or "") end; Rf()
        btn:SetScript("OnClick", function()
            idx = (idx % #entries) + 1; Rf(); MarkDirty()
            if onChange then onChange(entries[idx].value) end
        end)
        function c:SetSelected(v)
            for i, e in ipairs(entries) do if e.value == v then idx = i; Rf(); return end end
        end
        function c:GetSelected() return entries[idx] and entries[idx].value end
    end
    return c
end

-- Yellow section header
local function SectionHdr(parent, text, y)
    local l = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    l:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, y)
    l:SetWidth(TW_CW); l:SetJustifyH("LEFT")
    l:SetText(text)
    l:SetTextColor(1, 0.82, 0.0, 1)
    return l
end

-- Small grey label
local function SmallLbl(parent, text, y)
    local l = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    l:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, y)
    l:SetWidth(TW_CW); l:SetJustifyH("LEFT")
    l:SetText(text); l:SetTextColor(0.68, 0.68, 0.68, 1)
    return l
end

-- ---------------------------------------------------------------------------
-- SITUATION helpers
-- ---------------------------------------------------------------------------
local SIT_TYPES  = { "none", "zone", "subzone", "instance", "player" }
local SIT_LABELS = { "None (global)", "Zone", "Sub-zone", "Instance", "Player" }

local function ParseSituation(raw)
    if not raw or raw == "" then return "none", "" end
    local t, v = raw:match("^([^:]+):(.+)$")
    if not t then return "none", "" end
    return t, v
end

-- ---------------------------------------------------------------------------
-- BUILD CONTENT (shared by normal and skin builders)
-- Receives the scroll content frame (ct) and save button.
-- ---------------------------------------------------------------------------
local function BuildContent(f, ct, saveBtn)
    local y = -4

    -- Section: Task text — shows as a plain label; click to enter edit mode.
    SectionHdr(ct, "Task text", y); y = y - TW_LBL - 2

    local textLbl = ct:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    textLbl:SetPoint("TOPLEFT", ct, "TOPLEFT", 6, y)
    textLbl:SetPoint("TOPRIGHT", ct, "TOPRIGHT", -6, y)
    textLbl:SetHeight(TW_ROW)
    textLbl:SetJustifyH("LEFT")
    textLbl:SetWordWrap(false)
    textLbl:SetTextColor(0.9, 0.9, 0.9)

    local textEB = BNB.CreateBackdropFrame("EditBox", nil, ct)
    textEB:SetSize(TW_CW, TW_ROW); textEB:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
    textEB:SetAutoFocus(false); textEB:SetMaxLetters(500)
    textEB:SetFontObject("GameFontNormalSmall")
    textEB:SetScript("OnEnterPressed", function(self)
        local t = self:GetText()
        _pendingText = t
        textLbl:SetText(t ~= "" and t or "|cff888888(empty)|r")
        self:Hide(); textLbl:Show()
        self:ClearFocus()
        MarkDirty()
    end)
    textEB:SetScript("OnEscapePressed", function(self)
        self:SetText(_pendingText)
        self:Hide(); textLbl:Show()
        self:ClearFocus()
    end)
    textEB:SetScript("OnEditFocusLost", function(self)
        if self:IsShown() then
            local t = self:GetText()
            _pendingText = t
            textLbl:SetText(t ~= "" and t or "|cff888888(empty)|r")
            self:Hide(); textLbl:Show()
            MarkDirty()
        end
    end)
    textEB:Hide()
    _textEB = textEB
    _textEB._lbl = textLbl  -- store for Populate

    textLbl:SetScript("OnMouseDown", function()
        textLbl:Hide()
        textEB:SetText(_pendingText)
        textEB:Show()
        textEB:SetFocus()
    end)

    y = y - TW_ROW - TW_SECT_GAP

    -- Section: Reset
    SectionHdr(ct, "Reset", y); y = y - TW_LBL - 2
    SmallLbl(ct, "Automatically re-check after a period.", y)
    y = y - TW_LBL - 4
    local resetEntries = {
        { label = "None",   value = "none"   },
        { label = "Daily",  value = "daily"  },
        { label = "Weekly", value = "weekly" },
    }
    local resetDD = MakeDD(ct, resetEntries, "none", nil, TW_CW)
    resetDD:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
    -- Tooltip on the dropdown container frame
    resetDD:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Task reset schedule", 1, 1, 1)
        GameTooltip:AddLine("None: task stays completed until you uncheck it manually.", 0.8, 0.8, 0.8, true)
        GameTooltip:AddLine("Daily: resets at the WoW daily reset (time varies by region).", 0.8, 0.8, 0.8, true)
        GameTooltip:AddLine("Weekly: resets at the WoW weekly reset (varies by region).", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    resetDD:SetScript("OnLeave", function() GameTooltip:Hide() end)
    _resetDD = resetDD
    y = y - TW_ROW - TW_SECT_GAP

    -- Section: Situation
    SectionHdr(ct, "Situation", y); y = y - TW_LBL - 2
    SmallLbl(ct, "Bind this task to a context.", y)
    y = y - TW_LBL - 4

    -- Situation type dropdown
    local sitTypeEntries = {}
    for i, label in ipairs(SIT_LABELS) do
        sitTypeEntries[i] = { label = label, value = SIT_TYPES[i] }
    end

    local function OnSitTypeChanged(newType)
        _selSitType = newType
        if newType == "none" then
            _sitValueRow:Hide()
        else
            _sitValueRow:Show()
            local labelStr = "Value:"
            if newType == "zone"     then labelStr = "Zone:"
            elseif newType == "subzone"  then labelStr = "Sub-zone:"
            elseif newType == "instance" then labelStr = "Instance:"
            elseif newType == "player"   then labelStr = "Player:" end
            _sitValueRow._lbl:SetText(labelStr)
            if newType == "player" then
                if _sitBrowseBtn then _sitBrowseBtn:Hide() end
            else
                if _sitBrowseBtn then _sitBrowseBtn:Show() end
            end
        end
    end

    local sitTypeDD = MakeDD(ct, sitTypeEntries, "none", OnSitTypeChanged)
    sitTypeDD:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
    _sitTypeDD = sitTypeDD
    y = y - TW_ROW - TW_GAP

    -- Situation value row (hidden when type is "none")
    local valueRow = CreateFrame("Frame", nil, ct)
    valueRow:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
    valueRow:SetWidth(TW_CW)
    valueRow:SetHeight(TW_ROW)
    valueRow:Hide()
    _sitValueRow = valueRow

    local valueLbl = valueRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    valueLbl:SetPoint("LEFT", valueRow, "LEFT", 0, 0)
    valueLbl:SetWidth(65); valueLbl:SetJustifyH("LEFT")
    valueLbl:SetTextColor(0.78, 0.78, 0.78)
    valueLbl:SetText("Value:")
    valueRow._lbl = valueLbl

    local valueEb = CreateFrame("EditBox", nil, valueRow, "BackdropTemplate")
    BNB.EnsureBackdrop(valueEb)
    valueEb:SetPoint("LEFT", valueLbl, "RIGHT", 6, 0)
    valueEb:SetPoint("RIGHT", valueRow, "RIGHT", -26, 0)
    valueEb:SetHeight(20)
    valueEb:SetFontObject("GameFontNormal")
    valueEb:SetAutoFocus(false); valueEb:SetMaxLetters(128)
    valueEb:SetTextInsets(4, 4, 0, 0)
    valueEb:SetTextColor(1, 1, 1)
    BNB.SetBackdropDark(valueEb)
    valueEb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    valueEb:SetScript("OnEnterPressed",  function(self) self:ClearFocus() end)
    valueEb:HookScript("OnTextChanged", function() MarkDirty() end)
    _sitValueEb = valueEb

    -- Browse button (zone picker)
    local browseBtn = CreateFrame("Button", nil, valueRow)
    browseBtn:SetSize(20, 20)
    browseBtn:SetPoint("RIGHT", valueRow, "RIGHT", 0, 0)
    local browseTx = browseBtn:CreateTexture(nil, "ARTWORK")
    browseTx:SetAllPoints()
    browseTx:SetTexture(ASSETS .. "Overlay/ov-situation")
    browseBtn:SetScript("OnEnter", function(self)
        self:SetAlpha(1.0)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Browse zones and instances", 1, 1, 1)
        GameTooltip:Show()
    end)
    browseBtn:SetScript("OnLeave", function(self)
        self:SetAlpha(0.7); GameTooltip:Hide()
    end)
    browseBtn:SetAlpha(0.7)
    browseBtn:SetScript("OnClick", function()
        if BNB.ZonePicker then
            if BNB.ZonePicker.IsShown and BNB.ZonePicker.IsShown() then
                BNB.ZonePicker.Close()
            else
                BNB.ZonePicker.Open(valueRow, function(name, kind)
                    valueEb:SetText(name)
                    if kind and kind ~= _selSitType then
                        _selSitType = kind
                        sitTypeDD:SetSelected(kind)
                    end
                    MarkDirty()
                end)
            end
        end
    end)
    _sitBrowseBtn = browseBtn
    y = y - TW_ROW - TW_GAP

    -- "Use Current" + "Clear Current" buttons
    local useCurBtn = BNB.CreateButton(nil, ct, "Use Current", 90, 20)
    useCurBtn:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
    useCurBtn:SetScript("OnClick", function()
        local val = ""
        if _selSitType == "zone" then
            val = GetZoneText() or ""
        elseif _selSitType == "subzone" then
            val = GetSubZoneText and GetSubZoneText() or ""
        elseif _selSitType == "instance" then
            val = (GetInstanceInfo and select(1, GetInstanceInfo())) or GetRealZoneText() or ""
        elseif _selSitType == "player" then
            val = UnitName("target") or ""
        end
        if _sitValueEb then _sitValueEb:SetText(val) end
        MarkDirty()
    end)
    _sitUseCurBtn = useCurBtn

    local clrCurBtn = BNB.CreateButton(nil, ct, "Clear", 60, 20)
    clrCurBtn:SetPoint("LEFT", useCurBtn, "RIGHT", 6, 0)
    clrCurBtn:SetScript("OnClick", function()
        if _sitValueEb then _sitValueEb:SetText("") end
        if _sitTypeDD  then _sitTypeDD:SetSelected("none") end
        _selSitType = "none"
        if _sitValueRow then _sitValueRow:Hide() end
        MarkDirty()
    end)
    clrCurBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Clear situation", 1, 1, 1)
        GameTooltip:AddLine("Removes the context binding from this task.", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    clrCurBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Enable/disable Clear based on whether a situation value is set
    local function UpdateClrCur()
        local hasVal = _sitValueEb and _sitValueEb:GetText() ~= ""
        local hasSit = _selSitType and _selSitType ~= "none"
        clrCurBtn:SetEnabled(hasVal or hasSit)
    end
    if _sitValueEb then
        _sitValueEb:HookScript("OnTextChanged", function() UpdateClrCur() end)
    end
    clrCurBtn:SetEnabled(false)  -- disabled until populated
    _sitClearBtn = clrCurBtn

    y = y - 24 - TW_GAP

    -- Record content height for scroll
    ct._contentH = math.abs(y) + 8

    -- ── SAVE HANDLER ─────────────────────────────────────────────────────────
    saveBtn:SetScript("OnClick", function()
        local T = BNB.Task
        if not T or not _noteID or not _taskID then TW.Close(); return end
        local task = T.FindTask(_noteID, _taskID)
        if not task then TW.Close(); return end

        -- Text
        local newText = _pendingText or ""
        local changes = { text = newText }
        local clears  = {}

        -- Reset
        local rv = _resetDD and _resetDD:GetSelected() or "none"
        if rv == "none" then
            clears[#clears + 1] = "resetType"
            clears[#clears + 1] = "resetEvery"
            clears[#clears + 1] = "lastReset"
        else
            changes.resetType = rv
        end

        -- Situation
        local sv = _sitValueEb and _sitValueEb:GetText() or ""
        sv = sv:match("^%s*(.-)%s*$") or ""
        if _selSitType == "none" or sv == "" then
            clears[#clears + 1] = "situation"
        else
            changes.situation = _selSitType .. ":" .. sv
        end

        if #clears > 0 then changes._clear = clears end
        T.UpdateTask(_noteID, _taskID, changes)
        TW.Close()
    end)
end

-- ---------------------------------------------------------------------------
-- BUILD WINDOW -- normal (ButtonFrameTemplate)
-- ---------------------------------------------------------------------------
local function BuildWindow()
    if _frame then return _frame end

    local f = CreateFrame("Frame", "BNBTaskEditWindow", UIParent, "ButtonFrameTemplate")
    f:SetSize(TW_W, TW_H)
    f:SetFrameStrata("DIALOG")
    f:EnableMouse(true); f:SetMovable(true); f:SetClampedToScreen(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) self:StartMoving() end)
    f:SetScript("OnDragStop",  function(self) self:StopMovingOrSizing() end)

    ButtonFrameTemplate_HidePortrait(f)
    ButtonFrameTemplate_HideButtonBar(f)
    if f.Inset then f.Inset:Hide() end
    f:SetAlpha(0.95)
    f:SetTitle("Edit Task")
    if f.CloseButton then
        f.CloseButton:SetScript("OnClick", function() TW.Close() end)
    end
    f:HookScript("OnHide", function()
        _noteID = nil; _taskID = nil; _isDirty = false; _isPopulating = false
    end)

    -- Footer divider
    local footerDiv = f:CreateTexture(nil, "ARTWORK")
    footerDiv:SetHeight(1)
    footerDiv:SetPoint("BOTTOMLEFT",  f, "BOTTOMLEFT",  TW_PAD, TW_FOOT_H)
    footerDiv:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -TW_PAD, TW_FOOT_H)
    footerDiv:SetColorTexture(0.28, 0.28, 0.30, 1)

    -- Buttons
    local bW = math.floor(TW_CW / 2) - 4
    local saveBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    saveBtn:SetSize(bW, 26); saveBtn:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", TW_PAD, 6)
    saveBtn:SetText("Save"); saveBtn:SetEnabled(false)
    _saveBtn = saveBtn

    local cancelBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    cancelBtn:SetSize(bW, 26)
    cancelBtn:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", TW_PAD + bW + 8, 6)
    cancelBtn:SetText("Cancel")
    cancelBtn:SetScript("OnClick", function() TW.Close() end)

    -- Scroll panel
    local sf = CreateFrame("ScrollFrame", nil, f, "ScrollFrameTemplate")
    if sf.ScrollBar then sf.ScrollBar:SetAlpha(0) end
    sf:SetPoint("TOPLEFT",     f, "TOPLEFT",     TW_PAD, -TW_TOP_Y)
    sf:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -24,     TW_FOOT_H + 6)
    local ct = CreateFrame("Frame", nil, sf)
    ct:SetWidth(TW_CW); ct:SetHeight(1)
    sf:SetScrollChild(ct)

    local function ApplyScroll()
        local sfH = sf:GetHeight(); if sfH < 4 then return end
        local ctH = ct._contentH or 1
        ct:SetHeight(math.max(ctH, sfH))
        local bar = sf.ScrollBar
        if ctH <= sfH + 2 then
            if bar then bar:SetAlpha(0) end; ct:SetWidth(TW_CW + 20)
        else
            if bar then bar:SetAlpha(1) end; ct:SetWidth(TW_CW)
        end
    end
    sf:SetScript("OnSizeChanged", ApplyScroll)
    sf:HookScript("OnShow", function() C_Timer.After(0.05, ApplyScroll) end)

    -- Content
    BuildContent(f, ct, saveBtn)

    f:Hide()
    tinsert(UISpecialFrames, "BNBTaskEditWindow")
    _frame = f
    return f
end

-- ---------------------------------------------------------------------------
-- BUILD WINDOW -- skin mode
-- ---------------------------------------------------------------------------
local function BuildWindowSkin()
    if _frame then return _frame end

    local f = BNB.CreateSkinFrame(UIParent, false, "BNBTaskEditWindow", false)
    _G["BNBTaskEditWindow"] = f
    f:SetSize(TW_W, TW_H)
    f:SetFrameStrata("DIALOG")
    f:EnableMouse(true); f:SetMovable(true); f:SetClampedToScreen(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) self:StartMoving() end)
    f:SetScript("OnDragStop",  function(self) self:StopMovingOrSizing() end)
    f:SetAlpha(0.95)

    f:HookScript("OnHide", function()
        _noteID = nil; _taskID = nil; _isDirty = false; _isPopulating = false
    end)

    -- Title bar
    local titleBar = BNB.CreateSkinStrip(f, true, false)
    titleBar:SetPoint("TOPLEFT",  f, "TOPLEFT",  0, 0)
    titleBar:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
    titleBar:SetHeight(SK_TITLE_H)
    titleBar:EnableMouse(true)
    titleBar:RegisterForDrag("LeftButton")
    titleBar:SetScript("OnDragStart", function() f:StartMoving() end)
    titleBar:SetScript("OnDragStop",  function() f:StopMovingOrSizing() end)

    local titleLbl = titleBar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    titleLbl:SetPoint("CENTER", titleBar, "CENTER", -15, 0)
    titleLbl:SetTextColor(1, 0.82, 0)
    titleLbl:SetText("Edit Task")

    local closeBtn = BNB.CreateSkinCloseButton(titleBar, function() TW.Close() end)
    closeBtn:SetPoint("RIGHT", titleBar, "RIGHT", -3, 0)

    -- Footer
    local footerHost = CreateFrame("Frame", nil, f)
    footerHost:SetHeight(1)
    footerHost:SetPoint("BOTTOMLEFT",  f, "BOTTOMLEFT",  TW_PAD, TW_FOOT_H)
    footerHost:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -TW_PAD, TW_FOOT_H)
    local footerDiv = BNB.CreateDivider(footerHost, "HORIZONTAL", 0.28, 0.28, 0.30, 1)
    footerDiv:SetPoint("TOPLEFT",  footerHost, "TOPLEFT",  0, 0)
    footerDiv:SetPoint("TOPRIGHT", footerHost, "TOPRIGHT", 0, 0)

    -- Buttons
    local bW = math.floor(TW_CW / 2) - 4
    local saveBtn = BNB.CreateButton(nil, f, "Save", bW, 26)
    saveBtn:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", TW_PAD, 6)
    saveBtn:SetEnabled(false)
    _saveBtn = saveBtn

    local cancelBtn = BNB.CreateButton(nil, f, "Cancel", bW, 26)
    cancelBtn:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", TW_PAD + bW + 8, 6)
    cancelBtn:SetScript("OnClick", function() TW.Close() end)

    -- Scroll panel
    local sf = CreateFrame("ScrollFrame", nil, f, "ScrollFrameTemplate")
    local bar = sf.ScrollBar; if bar then bar:SetAlpha(0) end
    sf:SetPoint("TOPLEFT",     f, "TOPLEFT",     TW_PAD, -(SK_TITLE_H + 4))
    sf:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -24,     TW_FOOT_H + 6)
    local ct = CreateFrame("Frame", nil, sf)
    ct:SetWidth(TW_CW); ct:SetHeight(1)
    sf:SetScrollChild(ct)

    local function ApplyScroll()
        local sfH = sf:GetHeight(); if sfH < 4 then return end
        local ctH = ct._contentH or 1
        ct:SetHeight(math.max(ctH, sfH))
        if ctH <= sfH + 2 then
            if bar then bar:SetAlpha(0) end; ct:SetWidth(TW_CW + 20)
        else
            if bar then bar:SetAlpha(1) end; ct:SetWidth(TW_CW)
        end
    end
    sf:SetScript("OnSizeChanged", ApplyScroll)
    sf:HookScript("OnShow", function() C_Timer.After(0.05, ApplyScroll) end)

    -- Content
    BuildContent(f, ct, saveBtn)

    f:HookScript("OnShow", function()
        if BNB.ApplyMainWindowSkin then BNB.ApplyMainWindowSkin() end
    end)

    f:Hide()
    tinsert(UISpecialFrames, "BNBTaskEditWindow")
    _frame = f
    return f
end

-- ---------------------------------------------------------------------------
-- POPULATE
-- ---------------------------------------------------------------------------
local function Populate(noteID, taskID)
    local T = BNB.Task; if not T then return end
    local task = T.FindTask(noteID, taskID)
    if not task then return end

    _isPopulating = true

    -- Text: store in _pendingText via the editbox backing store, show via label.
    if _textEB then
        local txt = task.text or ""
        _pendingText = txt
        _textEB:SetText(txt)
        _textEB:Hide()
        if _textEB._lbl then
            _textEB._lbl:SetText(txt ~= "" and txt or "|cff888888(empty)|r")
            _textEB._lbl:Show()
        end
    end

    -- Reset
    local rv = task.resetType or "none"
    if _resetDD then _resetDD:SetSelected(rv) end

    -- Situation
    local sitType, sitVal = ParseSituation(task.situation)
    _selSitType = sitType
    if _sitTypeDD then _sitTypeDD:SetSelected(sitType) end
    if _sitValueEb then _sitValueEb:SetText(sitVal) end

    -- Show/hide value row
    if sitType == "none" then
        if _sitValueRow then _sitValueRow:Hide() end
    else
        if _sitValueRow then
            _sitValueRow:Show()
            local labelStr = "Value:"
            if sitType == "zone"     then labelStr = "Zone:"
            elseif sitType == "subzone"  then labelStr = "Sub-zone:"
            elseif sitType == "instance" then labelStr = "Instance:"
            elseif sitType == "player"   then labelStr = "Player:" end
            _sitValueRow._lbl:SetText(labelStr)
            if sitType == "player" then
                if _sitBrowseBtn then _sitBrowseBtn:Hide() end
            else
                if _sitBrowseBtn then _sitBrowseBtn:Show() end
            end
        end
    end

    -- Update Clear Current button state
    if _sitClearBtn then
        _sitClearBtn:SetEnabled(sitType ~= "none" or sitVal ~= "")
    end

    _isDirty = false
    if _saveBtn then _saveBtn:SetEnabled(false) end
    _isPopulating = false
end

-- ---------------------------------------------------------------------------
-- OPEN / CLOSE
-- ---------------------------------------------------------------------------
local function DoOpen(noteID, taskID, anchorFrame)
    if not _frame then
        if BigNoteBoxDB and BigNoteBoxDB.skinMode then
            BuildWindowSkin()
        else
            BuildWindow()
        end
    end
    local f = _frame

    _noteID = noteID; _taskID = taskID
    Populate(noteID, taskID)
    f:Show(); f:Raise()
    -- Ensure skin colours are current (covers preset changes while window was hidden)
    if BigNoteBoxDB and BigNoteBoxDB.skinMode and BNB.ApplyMainWindowSkin then
        BNB.ApplyMainWindowSkin()
    end
    return f
end

function TW.Open(noteID, taskID, anchorFrame)
    if not noteID or not taskID then return end
    local f = DoOpen(noteID, taskID, anchorFrame)
    f:ClearAllPoints()
    if anchorFrame and anchorFrame.GetWidth then
        local scrW = UIParent:GetWidth()
        local cx   = anchorFrame:GetCenter()
        local aw   = anchorFrame:GetWidth()
        local right = ((cx or 0) + (aw or 0) / 2 + 8 + TW_W) <= scrW
        if right then f:SetPoint("LEFT",  anchorFrame, "RIGHT",  8, 0)
        else          f:SetPoint("RIGHT", anchorFrame, "LEFT",  -8, 0) end
    else
        f:SetPoint("CENTER", UIParent, "CENTER", 0, 60)
    end
end

function TW.Close()
    if _frame then _frame:Hide() end
    if BNB.ZonePicker and BNB.ZonePicker.Close then BNB.ZonePicker.Close() end
    _noteID = nil; _taskID = nil; _isDirty = false; _pendingText = ""
end

function TW.IsOpen()    return _frame and _frame:IsShown() end
function TW.GetTaskID() return _taskID end

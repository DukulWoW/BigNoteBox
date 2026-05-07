-- BigNoteBox UI/AlarmWindow.lua
-- Alarm setter. ButtonFrameTemplate, 3 tabs, static Save/Delete footer.
-- Attaches to opener sticky; dragging detaches. Mutually exclusive with
-- Sticky Note Settings.
--
-- Public API:
--   BNB.AlarmWindow.Open(noteID, anchorFrame, stickyFrame)
--   BNB.AlarmWindow.OpenLeftOfMain(noteID)
--   BNB.AlarmWindow.Close()
--   BNB.AlarmWindow.IsOpen() -> bool
--   BNB.AlarmWindow.GetNoteID() -> noteID | nil

local BNB = BigNoteBox
if not BNB then return end

BNB.AlarmWindow = BNB.AlarmWindow or {}
local AW = BNB.AlarmWindow

-- ---------------------------------------------------------------------------
-- LAYOUT
-- ---------------------------------------------------------------------------
local AW_W       = 264
local AW_H       = 570   -- tall enough to avoid scrollbar on General tab
local AW_PAD     = 12
local AW_CW      = 224   -- content width
local AW_TAB_Y   = 62    -- top of tab content area
local AW_FOOT_H  = 38    -- static footer height (Save / Delete)
local AW_ROW     = 22
local AW_GAP     = 8     -- increased gap between items
local AW_LBL     = 14    -- section header height
local AW_SECT_GAP = 12   -- gap between sections

-- BNB green
local BNB_GR, BNB_GG, BNB_GB = 0.400, 0.733, 0.416

local DEFAULT_SOUND = "Interface/AddOns/BigNoteBox/Assets/Sounds/default.ogg"
local DAY_NAMES     = { "Mon","Tue","Wed","Thu","Fri","Sat","Sun" }

-- ---------------------------------------------------------------------------
-- STATE
-- ---------------------------------------------------------------------------
local _frame       = nil
local _noteID      = nil
local _stickyFrame = nil
local _isDirty     = false   -- true once user has changed anything
local _isPopulating = false  -- true while Populate() is running; suppresses MarkDirty

-- Calendar upvalues
local _calYear, _calMonth, _calSelDay

-- Widget refs
local _labelEB, _timeDDCont, _realSection, _realTimeRow, _igSection
local _igHourDD, _igMinDD, _hourDD, _minDD
local _recurDD, _wdChecks, _wdRow, _ndaysEB, _ndaysRow
local _soundDD, _glowTypeDD, _glowModeDD, _fireModeDD
local _snoozeEnableCB, _snoozeIntervalDD, _snoozeRepeatDD
local _combatDD, _postDD
local _saveBtn   -- ref so Populate can enable/disable it

-- ---------------------------------------------------------------------------
-- HELPERS
-- ---------------------------------------------------------------------------
local function HasWowStyle1()
    return C_XMLUtil and C_XMLUtil.GetTemplateInfo
        and C_XMLUtil.GetTemplateInfo("WowStyle1DropdownTemplate") ~= nil
end

-- Slider value helpers (used by BuildWindow and Populate)
local function SetSliderVal(sl, v)
    if not sl then return end
    sl._rawVal = v
    if sl.Slider then sl.Slider:SetValue(v) end
end

-- Mark dirty and enable save button
local function MarkDirty()
    if _isPopulating then return end
    _isDirty = true
    if _saveBtn then _saveBtn:SetEnabled(true) end
end

-- Compact dropdown.
local function MakeDD(parent, entries, initial, onChange, width)
    width = width or AW_CW
    local c = CreateFrame("Frame", nil, parent)
    c:SetSize(width, AW_ROW)

    if HasWowStyle1() then
        local dd = CreateFrame("DropdownButton", nil, c, "WowStyle1DropdownTemplate")
        dd:SetToplevel(true); dd:SetWidth(width); dd:SetHeight(AW_ROW)
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
        for i, e in ipairs(entries) do if e.value == initial then idx=i; break end end
        local btn = BNB.CreateBackdropFrame("Button", nil, c)
        btn:SetSize(width, AW_ROW); btn:SetPoint("TOPLEFT")
        local lbl = btn:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
        lbl:SetAllPoints(); lbl:SetJustifyH("CENTER")
        local function Rf() lbl:SetText(entries[idx] and entries[idx].label or "") end; Rf()
        btn:SetScript("OnClick", function()
            idx = (idx % #entries)+1; Rf(); MarkDirty()
            if onChange then onChange(entries[idx].value) end
        end)
        function c:SetSelected(v)
            for i,e in ipairs(entries) do if e.value==v then idx=i; Rf(); return end end
        end
        function c:GetSelected() return entries[idx] and entries[idx].value end
    end
    return c
end

-- Yellow section header (matches NoteConfig/StickySettings style)
local function SectionHdr(parent, text, y)
    local l = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    l:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, y)
    l:SetWidth(AW_CW); l:SetJustifyH("LEFT")
    l:SetText(text)
    l:SetTextColor(1, 0.82, 0.0, 1)  -- gold / yellow
    return l
end

-- Small grey label
local function Lbl(parent, text, y)
    local l = parent:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
    l:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, y)
    l:SetWidth(AW_CW); l:SetJustifyH("LEFT")
    l:SetText(text); l:SetTextColor(0.68, 0.68, 0.68, 1)
    return l
end

local function Div(parent, y)
    local d = parent:CreateTexture(nil,"ARTWORK")
    d:SetSize(AW_CW,1); d:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, y)
    if BigNoteBoxDB and BigNoteBoxDB.skinMode and BNB.GetSkinPreset then
        local p = BNB.GetSkinPreset()
        local br, bg_, bb = BNB.SkinBorderOf(p)
        d:SetColorTexture(br, bg_, bb, 0.9)
        BNB.RegisterSkinRule(d, 0.9)
    else
        d:SetColorTexture(0.28, 0.28, 0.30, 1)
    end
end

local SOUND_FILES = {
    sound01 = "Interface/AddOns/BigNoteBox/Assets/Sounds/sound01.ogg",
    sound02 = "Interface/AddOns/BigNoteBox/Assets/Sounds/sound02.ogg",
    sound03 = "Interface/AddOns/BigNoteBox/Assets/Sounds/sound03.ogg",
    sound04 = "Interface/AddOns/BigNoteBox/Assets/Sounds/sound04.ogg",
    sound05 = "Interface/AddOns/BigNoteBox/Assets/Sounds/sound05.ogg",
    sound06 = "Interface/AddOns/BigNoteBox/Assets/Sounds/sound06.ogg",
    sound07 = "Interface/AddOns/BigNoteBox/Assets/Sounds/sound07.ogg",
    sound08 = "Interface/AddOns/BigNoteBox/Assets/Sounds/sound08.ogg",
    sound09 = "Interface/AddOns/BigNoteBox/Assets/Sounds/sound09.ogg",
    sound10 = "Interface/AddOns/BigNoteBox/Assets/Sounds/sound10.ogg",
}

local function SoundPath(key)
    if not key or key == "default" then return DEFAULT_SOUND end
    if key == "silent" then return nil end
    return SOUND_FILES[key]
end

-- ---------------------------------------------------------------------------
-- BUILD (once)
-- ---------------------------------------------------------------------------
local function BuildWindow()
    if _frame then return _frame end

    local f = CreateFrame("Frame", "BNBAlarmWindow", UIParent, "ButtonFrameTemplate")
    f:SetSize(AW_W, AW_H)
    f:SetFrameStrata("DIALOG"); f:SetToplevel(true)
    f:EnableMouse(true); f:SetMovable(true); f:SetClampedToScreen(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) self:StartMoving(); _stickyFrame = nil end)
    f:SetScript("OnDragStop",  function(self) self:StopMovingOrSizing() end)

    ButtonFrameTemplate_HidePortrait(f)
    ButtonFrameTemplate_HideButtonBar(f)
    if f.Inset then f.Inset:Hide() end
    f:SetAlpha(0.95)
    f:SetTitle("Set Alarm")
    if f.CloseButton then
        f.CloseButton:SetScript("OnClick", function() AW.Close() end)
    end
    f:HookScript("OnHide", function()
        _noteID = nil; _stickyFrame = nil; _isDirty = false; _isPopulating = false
    end)

    -- ── STATIC FOOTER ────────────────────────────────────────────────────────
    local footerDiv = f:CreateTexture(nil, "ARTWORK")
    footerDiv:SetHeight(1)
    footerDiv:SetPoint("BOTTOMLEFT",  f, "BOTTOMLEFT",  AW_PAD, AW_FOOT_H)
    footerDiv:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -AW_PAD, AW_FOOT_H)
    footerDiv:SetColorTexture(0.28, 0.28, 0.30, 1)

    local bW = math.floor(AW_CW/2) - 4
    local saveBtn = BNB.CreateButton(nil, f, "Save", bW, 26)
    saveBtn:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", AW_PAD, 6)
    saveBtn:SetEnabled(false)

    local delBtn = BNB.CreateButton(nil, f, "Remove Alarm", bW, 26)
    delBtn:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", AW_PAD + bW + 8, 6)
    delBtn:GetFontString():SetTextColor(0.9, 0.4, 0.4, 1)

    _saveBtn = saveBtn

    -- ── TABS ─────────────────────────────────────────────────────────────────
    local tpl = (C_XMLUtil and C_XMLUtil.GetTemplateInfo
        and C_XMLUtil.GetTemplateInfo("PanelTopTabButtonTemplate"))
        and "PanelTopTabButtonTemplate" or "PanelTabButtonTemplate"

    local tabBtns, tabPanels = {}, {}
    local function SelectTab(idx)
        for i = 1, 3 do
            if tabBtns[i] then
                if i==idx then PanelTemplates_SelectTab(tabBtns[i])
                else            PanelTemplates_DeselectTab(tabBtns[i]) end
            end
            if tabPanels[i] then tabPanels[i]:SetShown(i==idx) end
        end
        f._activeTab = idx
    end
    f._selectTab = SelectTab

    local lastBtn
    for i, text in ipairs({"General","Animation","Advanced"}) do
        local btn = CreateFrame("Button","BNBAlarmWindowTab"..i, f, tpl)
        btn:SetText(text)
        pcall(function()
            if tpl=="PanelTopTabButtonTemplate" then
                PanelTemplates_TabResize(btn,15,nil,70)
            else
                PanelTemplates_TabResize(btn,0)
            end
        end)
        btn:SetID(i)
        if lastBtn then btn:SetPoint("LEFT",lastBtn,"RIGHT",5,0)
        else             btn:SetPoint("TOPLEFT",f,"TOPLEFT",7,-25) end
        btn:SetScript("OnClick", function(self) SelectTab(self:GetID()) end)
        tabBtns[i]=btn; lastBtn=btn
    end
    PanelTemplates_SetNumTabs(f,3); f.numTabs=3

    -- ── SCROLL PANEL FACTORY ─────────────────────────────────────────────────
    local function MakeSP()
        local sf = CreateFrame("ScrollFrame",nil,f,"ScrollFrameTemplate")
        local bar = sf.ScrollBar; if bar then bar:SetAlpha(0) end
        sf:SetPoint("TOPLEFT",     f,"TOPLEFT",     AW_PAD, -AW_TAB_Y)
        sf:SetPoint("BOTTOMRIGHT", f,"BOTTOMRIGHT", -24, AW_FOOT_H + 6)
        local ct = CreateFrame("Frame",nil,sf)
        ct:SetWidth(AW_CW); ct:SetHeight(1); sf:SetScrollChild(ct)
        local function Apply()
            local sfH = sf:GetHeight(); if sfH<4 then return end
            local ctH = ct._contentH or 1
            ct:SetHeight(math.max(ctH,sfH))
            if ctH <= sfH+2 then
                if bar then bar:SetAlpha(0) end; ct:SetWidth(AW_CW+20)
            else
                if bar then bar:SetAlpha(1) end; ct:SetWidth(AW_CW)
            end
        end
        sf:SetScript("OnSizeChanged",Apply)
        sf:HookScript("OnShow",function() C_Timer.After(0.05,Apply) end)
        sf:Hide()
        return sf, ct
    end

    local sf1,ct1 = MakeSP()
    local sf2,ct2 = MakeSP()
    local sf3,ct3 = MakeSP()
    tabPanels[1]=sf1; tabPanels[2]=sf2; tabPanels[3]=sf3

    f:Hide()
    tinsert(UISpecialFrames, "BNBAlarmWindow")
    _frame=f
    return f, sf1, sf2, sf3, ct1, ct2, ct3, saveBtn, delBtn, SelectTab
end

-- ---------------------------------------------------------------------------
-- BUILD WINDOW  (SKIN VERSION)
-- Same chrome height as normal (62px total) so all tab content anchors are
-- identical. Uses SkinSystem API for backdrop frames.
-- ---------------------------------------------------------------------------
local SK_AW_TITLE_H = 28   -- title bar strip height
local SK_AW_TAB_H   = 24   -- skin tab row height
local SK_AW_TAB_GAP = 10   -- gap below tabs to reach AW_TAB_Y (62px total)

local function BuildWindowSkin()
    if _frame then return _frame end

    local f = BNB.CreateSkinFrame(UIParent, false, "BNBAlarmWindow", false)
    _G["BNBAlarmWindow"] = f
    f:SetSize(AW_W, AW_H)
    f:SetFrameStrata("DIALOG"); f:SetToplevel(true)
    f:EnableMouse(true); f:SetMovable(true); f:SetClampedToScreen(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) self:StartMoving(); _stickyFrame = nil end)
    f:SetScript("OnDragStop",  function(self) self:StopMovingOrSizing() end)
    f:SetAlpha(0.95)

    f:HookScript("OnHide", function()
        _noteID = nil; _stickyFrame = nil; _isDirty = false; _isPopulating = false
    end)

    -- Title bar strip
    local titleBar = BNB.CreateSkinStrip(f, true, false)
    titleBar:SetPoint("TOPLEFT",  f, "TOPLEFT",  0, 0)
    titleBar:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
    titleBar:SetHeight(SK_AW_TITLE_H)
    titleBar:EnableMouse(true)
    titleBar:RegisterForDrag("LeftButton")
    titleBar:SetScript("OnDragStart", function() f:StartMoving(); _stickyFrame = nil end)
    titleBar:SetScript("OnDragStop",  function() f:StopMovingOrSizing() end)

    local titleLbl = titleBar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    titleLbl:SetPoint("CENTER", titleBar, "CENTER", -15, 0)
    titleLbl:SetTextColor(1, 0.82, 0)
    titleLbl:SetText("Set Alarm")

    local closeBtn = BNB.CreateSkinCloseButton(titleBar, function() AW.Close() end)
    closeBtn:SetPoint("RIGHT", titleBar, "RIGHT", -3, 0)

    -- ── FOOTER ────────────────────────────────────────────────────────────────
    local footerHost = CreateFrame("Frame", nil, f)
    footerHost:SetHeight(1)
    footerHost:SetPoint("BOTTOMLEFT",  f, "BOTTOMLEFT",  AW_PAD, AW_FOOT_H)
    footerHost:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -AW_PAD, AW_FOOT_H)
    local footerDiv = BNB.CreateDivider(footerHost, "HORIZONTAL", 0.28, 0.28, 0.30, 1)
    footerDiv:SetPoint("TOPLEFT",  footerHost, "TOPLEFT",  0, 0)
    footerDiv:SetPoint("TOPRIGHT", footerHost, "TOPRIGHT", 0, 0)

    local bW = math.floor(AW_CW/2) - 4
    local saveBtn = BNB.CreateButton(nil, f, "Save", bW, 26)
    saveBtn:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", AW_PAD, 6)
    saveBtn:SetEnabled(false)

    local delBtn = BNB.CreateButton(nil, f, "Remove Alarm", bW, 26)
    delBtn:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", AW_PAD + bW + 8, 6)
    delBtn:GetFontString():SetTextColor(0.9, 0.4, 0.4, 1)

    _saveBtn = saveBtn

    -- ── SKIN TABS ─────────────────────────────────────────────────────────────
    local tabPanels = {}
    local tabCtrl = BNB.CreateSkinTabs(f, {"General","Animation","Advanced"}, function(idx)
        for i = 1, 3 do
            if tabPanels[i] then tabPanels[i]:SetShown(i == idx) end
        end
        f._activeTab = idx
    end)
    tabCtrl.frame:SetPoint("TOPLEFT",  f, "TOPLEFT",  AW_PAD, -(SK_AW_TITLE_H + SK_AW_TAB_GAP))
    tabCtrl.frame:SetPoint("TOPRIGHT", f, "TOPRIGHT", -AW_PAD, -(SK_AW_TITLE_H + SK_AW_TAB_GAP))

    f._selectTab = function(idx)
        tabCtrl.Select(idx)
    end

    -- ── SCROLL PANEL FACTORY (identical anchor to normal — AW_TAB_Y = 62) ────
    local function MakeSP()
        local sf = CreateFrame("ScrollFrame",nil,f,"ScrollFrameTemplate")
        local bar = sf.ScrollBar; if bar then bar:SetAlpha(0) end
        sf:SetPoint("TOPLEFT",     f,"TOPLEFT",     AW_PAD, -AW_TAB_Y)
        sf:SetPoint("BOTTOMRIGHT", f,"BOTTOMRIGHT", -24, AW_FOOT_H + 6)
        local ct = CreateFrame("Frame",nil,sf)
        ct:SetWidth(AW_CW); ct:SetHeight(1); sf:SetScrollChild(ct)
        local function Apply()
            local sfH = sf:GetHeight(); if sfH<4 then return end
            local ctH = ct._contentH or 1
            ct:SetHeight(math.max(ctH,sfH))
            if ctH <= sfH+2 then
                if bar then bar:SetAlpha(0) end; ct:SetWidth(AW_CW+20)
            else
                if bar then bar:SetAlpha(1) end; ct:SetWidth(AW_CW)
            end
        end
        sf:SetScript("OnSizeChanged",Apply)
        sf:HookScript("OnShow",function() C_Timer.After(0.05,Apply) end)
        sf:Hide()
        return sf, ct
    end

    local sf1,ct1 = MakeSP()
    local sf2,ct2 = MakeSP()
    local sf3,ct3 = MakeSP()
    tabPanels[1]=sf1; tabPanels[2]=sf2; tabPanels[3]=sf3

    f:SetScript("OnShow", function()
        if BNB.ApplyMainWindowSkin then BNB.ApplyMainWindowSkin() end
    end)

    f:Hide()
    tinsert(UISpecialFrames, "BNBAlarmWindow")
    _frame=f
    return f, sf1, sf2, sf3, ct1, ct2, ct3, saveBtn, delBtn, tabCtrl.Select
end

-- ---------------------------------------------------------------------------
-- BUILD TAB CONTENT  (shared by both normal and skin builders)
-- Receives the outer frame and the three scroll content frames.
-- Builds all widgets for tabs 1/2/3 and wires save/delete buttons.
-- ---------------------------------------------------------------------------
local function BuildTabContent(f, sf1, sf2, sf3, ct1, ct2, ct3, saveBtn, delBtn)
    -- ================================================================
    -- TAB 1: GENERAL
    -- ================================================================
    local y = -4

    -- Section: Reminder
    SectionHdr(ct1, "Reminder", y); y = y - AW_LBL - 2
    local labelEB = BNB.CreateBackdropFrame("EditBox",nil,ct1)
    labelEB:SetSize(AW_CW,AW_ROW); labelEB:SetPoint("TOPLEFT",ct1,"TOPLEFT",0,y)
    labelEB:SetAutoFocus(false); labelEB:SetMaxLetters(80)
    BNB.AddPlaceholder(labelEB,"Short reminder text...")
    labelEB:SetFontObject("GameFontNormalSmall")
    labelEB:HookScript("OnTextChanged", function() MarkDirty() end)
    y = y - AW_ROW - AW_SECT_GAP
    Div(ct1,y); y = y - AW_GAP

    -- Section: Time
    SectionHdr(ct1,"Time",y); y = y - AW_LBL - 2
    Lbl(ct1,"Type",y); y = y - AW_LBL
    local timeEntries = {
        {label="Real-world",value="real"},
        {label="In-game",   value="ingame"},
    }
    local timeDDCont = MakeDD(ct1,timeEntries,"real",nil)
    timeDDCont:SetPoint("TOPLEFT",ct1,"TOPLEFT",0,y)
    y = y - AW_ROW - AW_GAP

    -- Calendar (real-world)
    local CAL_CELL = math.floor(AW_CW/7)
    local CAL_H_HDR,CAL_H_DAYS,CAL_H_ROW,CAL_ROWS_N = 20,14,18,6
    local CAL_TOTAL = CAL_H_HDR+CAL_H_DAYS+CAL_ROWS_N*CAL_H_ROW

    local realSection = CreateFrame("Frame",nil,ct1)
    realSection:SetPoint("TOPLEFT",ct1,"TOPLEFT",0,y)
    realSection:SetWidth(AW_CW); realSection:SetHeight(CAL_TOTAL)

    local calTitle = realSection:CreateFontString(nil,"OVERLAY","GameFontNormal")
    calTitle:SetPoint("TOP",realSection,"TOP",0,-1)
    calTitle:SetWidth(AW_CW-44); calTitle:SetJustifyH("CENTER")

    -- Left arrow (previous month) — icon button matching MainWindow titlebar style
    local CAL_BTN_SZ = 18
    local CAL_BTN_ASSETS = "Interface\\AddOns\\BigNoteBox\\Assets\\Buttons\\"
    local pBtn = CreateFrame("Button", nil, realSection)
    pBtn:SetSize(CAL_BTN_SZ, CAL_BTN_SZ)
    pBtn:SetPoint("TOPLEFT", realSection, "TOPLEFT", 0, 0)
    pBtn:SetHighlightTexture(""); pBtn:SetPushedTexture("")
    local pNorm  = pBtn:CreateTexture(nil,"ARTWORK"); pNorm:SetAllPoints()
    pNorm:SetTexture(CAL_BTN_ASSETS .. "bt-left-normal")
    local pHover = pBtn:CreateTexture(nil,"ARTWORK"); pHover:SetAllPoints()
    pHover:SetTexture(CAL_BTN_ASSETS .. "bt-left-hover"); pHover:Hide()
    local pPress = pBtn:CreateTexture(nil,"ARTWORK"); pPress:SetAllPoints()
    pPress:SetTexture(CAL_BTN_ASSETS .. "bt-left-press"); pPress:Hide()
    pBtn:SetScript("OnEnter",    function() pNorm:Hide(); pHover:Show() end)
    pBtn:SetScript("OnLeave",    function() pHover:Hide(); pPress:Hide(); pNorm:Show() end)
    pBtn:SetScript("OnMouseDown",function() pPress:Show(); pNorm:Hide(); pHover:Hide() end)
    pBtn:SetScript("OnMouseUp",  function() pPress:Hide(); pHover:Show() end)

    -- Right arrow (next month)
    local nBtn = CreateFrame("Button", nil, realSection)
    nBtn:SetSize(CAL_BTN_SZ, CAL_BTN_SZ)
    nBtn:SetPoint("TOPRIGHT", realSection, "TOPRIGHT", 0, 0)
    nBtn:SetHighlightTexture(""); nBtn:SetPushedTexture("")
    local nNorm  = nBtn:CreateTexture(nil,"ARTWORK"); nNorm:SetAllPoints()
    nNorm:SetTexture(CAL_BTN_ASSETS .. "bt-right-normal")
    local nHover = nBtn:CreateTexture(nil,"ARTWORK"); nHover:SetAllPoints()
    nHover:SetTexture(CAL_BTN_ASSETS .. "bt-right-hover"); nHover:Hide()
    local nPress = nBtn:CreateTexture(nil,"ARTWORK"); nPress:SetAllPoints()
    nPress:SetTexture(CAL_BTN_ASSETS .. "bt-right-press"); nPress:Hide()
    nBtn:SetScript("OnEnter",    function() nNorm:Hide(); nHover:Show() end)
    nBtn:SetScript("OnLeave",    function() nHover:Hide(); nPress:Hide(); nNorm:Show() end)
    nBtn:SetScript("OnMouseDown",function() nPress:Show(); nNorm:Hide(); nHover:Hide() end)
    nBtn:SetScript("OnMouseUp",  function() nPress:Hide(); nHover:Show() end)

    for i,dn in ipairs(DAY_NAMES) do
        local dl = realSection:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
        dl:SetSize(CAL_CELL,CAL_H_DAYS)
        dl:SetPoint("TOPLEFT",realSection,"TOPLEFT",(i-1)*CAL_CELL,-CAL_H_HDR)
        dl:SetText(dn:sub(1,1)); dl:SetJustifyH("CENTER")
        dl:SetTextColor(0.5,0.5,0.5,1)
    end

    local dayBtns = {}
    for row=0,CAL_ROWS_N-1 do for col=0,6 do
        local db = BNB.CreateBackdropFrame("Button",nil,realSection)
        db:SetSize(CAL_CELL-2,CAL_H_ROW-1)
        db:SetPoint("TOPLEFT",realSection,"TOPLEFT",
            col*CAL_CELL, -(CAL_H_HDR+CAL_H_DAYS+row*CAL_H_ROW))
        local fl = db:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
        fl:SetAllPoints(); fl:SetJustifyH("CENTER")
        db._lbl=fl; db._day=nil
        local selBg = db:CreateTexture(nil,"BACKGROUND")
        selBg:SetAllPoints(); selBg:SetColorTexture(BNB_GR,BNB_GG,BNB_GB,0.35)
        selBg:Hide(); db._selBg=selBg
        table.insert(dayBtns,db)
    end end

    local function RefreshCalendar()
        if not _calYear or not _calMonth then return end
        calTitle:SetText(string.format("%s %d",
            date("%B",time({year=_calYear,month=_calMonth,day=1,hour=0,min=0,sec=0})),
            _calYear))
        local first = time({year=_calYear,month=_calMonth,day=1,hour=0,min=0,sec=0})
        local sw = tonumber(date("%w",first))
        local off = sw==0 and 6 or sw-1
        local nxt = _calMonth==12
            and time({year=_calYear+1,month=1,day=1})
            or  time({year=_calYear,month=_calMonth+1,day=1})
        local dim = math.floor((nxt-first)/86400)
        for i,db in ipairs(dayBtns) do
            local day = i-off
            if day>=1 and day<=dim then
                db._lbl:SetText(tostring(day)); db._day=day; db:Show()
                local sel=(day==_calSelDay)
                db._lbl:SetTextColor(sel and BNB_GR or 1,sel and BNB_GG or 1,sel and BNB_GB or 1,1)
                db._selBg:SetShown(sel)
                db:SetScript("OnClick",function() _calSelDay=day; MarkDirty(); RefreshCalendar() end)
            else
                db._lbl:SetText(""); db._day=nil; db._selBg:Hide(); db:Hide()
            end
        end
    end
    pBtn:SetScript("OnClick",function()
        _calMonth=_calMonth-1; if _calMonth<1 then _calMonth=12;_calYear=_calYear-1 end
        RefreshCalendar() end)
    nBtn:SetScript("OnClick",function()
        _calMonth=_calMonth+1; if _calMonth>12 then _calMonth=1;_calYear=_calYear+1 end
        RefreshCalendar() end)

    y = y - CAL_TOTAL - AW_GAP

    -- Hour:Min (real-world)
    local realTimeRow = CreateFrame("Frame",nil,ct1)
    realTimeRow:SetSize(AW_CW,AW_ROW); realTimeRow:SetPoint("TOPLEFT",ct1,"TOPLEFT",0,y)
    local hEntries,mEntries={},{}
    for h=0,23 do table.insert(hEntries,{label=string.format("%02d",h),value=h}) end
    for m=0,55,5 do table.insert(mEntries,{label=string.format("%02d",m),value=m}) end
    local hw = math.floor(AW_CW/2)-6
    local hourDD = MakeDD(realTimeRow,hEntries,9,nil,hw)
    hourDD:SetPoint("LEFT",realTimeRow,"LEFT",0,0)
    local cln = realTimeRow:CreateFontString(nil,"OVERLAY","GameFontNormal")
    cln:SetPoint("LEFT",realTimeRow,"LEFT",hw+4,0); cln:SetText(":")
    local minDD = MakeDD(realTimeRow,mEntries,0,nil,hw)
    minDD:SetPoint("LEFT",realTimeRow,"LEFT",hw+12,0)
    y = y - AW_ROW - AW_GAP

    -- In-game time
    local igSection = CreateFrame("Frame",nil,ct1)
    igSection:SetSize(AW_CW, AW_LBL+AW_ROW+AW_GAP)
    -- position igSection at same y as realSection (before calendar)
    local igTopY = y + AW_ROW + AW_GAP + CAL_TOTAL + AW_GAP
    igSection:SetPoint("TOPLEFT",ct1,"TOPLEFT",0,igTopY)
    igSection:Hide()

    local igNote = igSection:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
    igNote:SetPoint("TOPLEFT",igSection,"TOPLEFT",0,0)
    igNote:SetWidth(AW_CW); igNote:SetJustifyH("LEFT")
    igNote:SetText("Server time — fires every day at this time")
    igNote:SetTextColor(0.55,0.55,0.55,1)

    local igRow = CreateFrame("Frame",nil,igSection)
    igRow:SetSize(AW_CW,AW_ROW); igRow:SetPoint("TOPLEFT",igSection,"TOPLEFT",0,-AW_LBL)
    local igHourDD = MakeDD(igRow,hEntries,9,nil,hw); igHourDD:SetPoint("LEFT",igRow,"LEFT",0,0)
    local igCln = igRow:CreateFontString(nil,"OVERLAY","GameFontNormal")
    igCln:SetPoint("LEFT",igRow,"LEFT",hw+4,0); igCln:SetText(":")
    local igMinDD = MakeDD(igRow,mEntries,0,nil,hw); igMinDD:SetPoint("LEFT",igRow,"LEFT",hw+12,0)

    local function SetTimeType(v)
        local real=(v=="real" or not v)
        realSection:SetShown(real); realTimeRow:SetShown(real); igSection:SetShown(not real)
    end
    if timeDDCont._dd then
        timeDDCont._dd:SetupMenu(function(_,root)
            for _,e in ipairs(timeEntries) do
                local ev=e.value
                root:CreateRadio(e.label,
                    function() return timeDDCont._dd._selected==ev end,
                    function()
                        timeDDCont._dd._selected=ev; timeDDCont._dd:SetText(e.label)
                        MarkDirty(); SetTimeType(ev)
                    end)
            end
        end)
    end

    Div(ct1,y); y = y - AW_GAP

    -- Section: Repeat
    SectionHdr(ct1,"Repeat",y); y = y - AW_LBL - 2
    local recurEntries={
        {label="None",              value=nil        },
        {label="WoW weekly reset",  value="weekly"   },
        {label="Specific weekdays", value="weekdays" },
        {label="Every N days",      value="interval" },
    }
    local recurDD = MakeDD(ct1,recurEntries,nil,nil)
    recurDD:SetPoint("TOPLEFT",ct1,"TOPLEFT",0,y); y = y - AW_ROW - AW_GAP

    local wdRow = CreateFrame("Frame",nil,ct1)
    wdRow:SetSize(AW_CW,22); wdRow:SetPoint("TOPLEFT",ct1,"TOPLEFT",0,y); wdRow:Hide()
    local wdChecks={}; local wdCW=math.floor(AW_CW/7)
    for i,dn in ipairs(DAY_NAMES) do
        local cb=CreateFrame("CheckButton",nil,wdRow,"UICheckButtonTemplate")
        cb:SetSize(20,20); cb:SetPoint("LEFT",wdRow,"LEFT",(i-1)*wdCW,0)
        cb:HookScript("OnClick",function() MarkDirty() end)
        local dl=wdRow:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
        dl:SetPoint("LEFT",cb,"RIGHT",1,0); dl:SetText(dn:sub(1,1))
        dl:SetTextColor(0.72,0.72,0.72,1); cb._dayIndex=i; wdChecks[i]=cb
    end

    local ndRow = CreateFrame("Frame",nil,ct1)
    ndRow:SetSize(AW_CW,AW_ROW); ndRow:SetPoint("TOPLEFT",ct1,"TOPLEFT",0,y); ndRow:Hide()
    local ndL=ndRow:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
    ndL:SetPoint("LEFT"); ndL:SetText("Every ")
    local ndEB=BNB.CreateBackdropFrame("EditBox",nil,ndRow)
    ndEB:SetSize(36,AW_ROW); ndEB:SetPoint("LEFT",ndRow,"LEFT",44,0)
    ndEB:SetAutoFocus(false); ndEB:SetNumeric(true); ndEB:SetMaxLetters(3)
    ndEB:SetFontObject("GameFontNormalSmall"); ndEB:SetText("7")
    ndEB:HookScript("OnTextChanged",function() MarkDirty() end)
    local ndS=ndRow:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
    ndS:SetPoint("LEFT",ndEB,"RIGHT",4,0); ndS:SetText(" days")

    local function SetRecur(v)
        wdRow:SetShown(v=="weekdays"); ndRow:SetShown(v=="interval")
    end
    if recurDD._dd then
        recurDD._dd:SetupMenu(function(_,root)
            for _,e in ipairs(recurEntries) do
                local ev=e.value
                root:CreateRadio(e.label,
                    function() return recurDD._dd._selected==ev end,
                    function()
                        recurDD._dd._selected=ev; recurDD._dd:SetText(e.label)
                        MarkDirty(); SetRecur(ev)
                    end)
            end
        end)
    end

    y = y - AW_ROW - AW_SECT_GAP
    Div(ct1,y); y = y - AW_GAP

    -- Section: Sound
    SectionHdr(ct1,"Sound",y); y = y - AW_LBL - 2
    -- Silent first, then Default, then custom sounds
    local sndEntries={
        {label="Silent",      value="silent"  },
        {label="Default",     value="default" },
        {label="Double hit",  value="sound01" },
        {label="Long pop",    value="sound02" },
        {label="Magic",       value="sound03" },
        {label="Scream",      value="sound04" },
        {label="Yell",        value="sound05" },
        {label="Triple hit",  value="sound06" },
        {label="Drum & Ding", value="sound07" },
        {label="Xylophone",   value="sound08" },
        {label="Tada",        value="sound09" },
        {label="Soft dings",  value="sound10" },
    }
    local sDDW = AW_CW - 56
    local soundDD = MakeDD(ct1,sndEntries,"default",nil,sDDW)
    soundDD:SetPoint("TOPLEFT",ct1,"TOPLEFT",0,y)
    local testSnd=BNB.CreateButton(nil,ct1,"Test",50,AW_ROW)
    testSnd:SetPoint("TOPLEFT",ct1,"TOPLEFT",sDDW+6,y)
    testSnd:SetScript("OnClick",function()
        local p=SoundPath(soundDD:GetSelected()); if p then PlaySoundFile(p,"Master") end
    end)
    y = y - AW_ROW - 4
    ct1._contentH = math.abs(y)

    -- ================================================================
    -- TAB 2: ANIMATION
    -- ================================================================
    local y2 = -4

    SectionHdr(ct2,"Glow",y2); y2 = y2 - AW_LBL - 2

    Lbl(ct2,"Type",y2); y2 = y2 - AW_LBL
    local gtEntries={
        {label="Default",  value=nil},
        {label="Pixel",    value=1  },
        {label="AutoCast", value=2  },
        {label="Border",   value=3  },
        {label="Proc",     value=4  },
    }
    local glowTypeDD=MakeDD(ct2,gtEntries,nil,nil)
    glowTypeDD:SetPoint("TOPLEFT",ct2,"TOPLEFT",0,y2); y2 = y2 - AW_ROW - AW_GAP

    Lbl(ct2,"Mode",y2); y2 = y2 - AW_LBL
    local gmEntries={
        {label="Default",        value=nil          },
        {label="Continuous",     value="continuous" },
        {label="Pulse (10s)",    value="pulse"      },
        {label="Once (10s)",     value="once"       },
    }
    local glowModeDD=MakeDD(ct2,gmEntries,nil,nil)
    glowModeDD:SetPoint("TOPLEFT",ct2,"TOPLEFT",0,y2); y2 = y2 - AW_ROW - AW_GAP

    Lbl(ct2,"Color",y2); y2 = y2 - AW_LBL
    local swatchBtn=BNB.CreateBackdropFrame("Button",nil,ct2)
    swatchBtn:SetSize(AW_ROW,AW_ROW); swatchBtn:SetPoint("TOPLEFT",ct2,"TOPLEFT",0,y2)
    local swTx=swatchBtn:CreateTexture(nil,"OVERLAY"); swTx:SetAllPoints()
    swTx:SetColorTexture(BNB_GR,BNB_GG,BNB_GB,1)
    local glowColorVal=nil

    local rstCol=BNB.CreateButton(nil,ct2,"Reset to default",AW_CW-AW_ROW-6,AW_ROW)
    rstCol:SetPoint("TOPLEFT",ct2,"TOPLEFT",AW_ROW+6,y2)
    rstCol:SetScript("OnClick",function()
        glowColorVal=nil; swTx:SetColorTexture(BNB_GR,BNB_GG,BNB_GB,1); MarkDirty()
    end)
    swatchBtn:SetScript("OnClick",function()
        local pv=glowColorVal or {BNB_GR,BNB_GG,BNB_GB,1}
        ColorPickerFrame:SetupColorPickerAndShow({
            swatchFunc=function()
                local r,g,b=ColorPickerFrame:GetColorRGB()
                glowColorVal={r,g,b,1}; swTx:SetColorTexture(r,g,b,1); MarkDirty()
            end,
            cancelFunc=function()
                glowColorVal=pv; swTx:SetColorTexture(pv[1],pv[2],pv[3],1)
            end,
            hasOpacity=false,r=pv[1],g=pv[2],b=pv[3],
        })
    end)
    y2 = y2 - AW_ROW - AW_GAP
    Div(ct2,y2); y2 = y2 - AW_GAP

    -- ── Advanced glow params — sliders, shown/hidden per type ────────────────
    -- Float params stored ×100 or ×10 internally (integer slider steps), divided on read.
    local fmtF2 = function(v) return string.format("%.2f", v/100) end  -- ×100 int → "0.25"
    local fmtF1 = function(v) return string.format("%.1f", v/10)  end  -- ×10  int → "0.5"

    -- Each slider row = 36px slider + 16px value label + 10px gap = 62px per param
    local SL_H     = 36   -- slider widget height
    local SL_VAL_H = 16   -- value label height
    local SL_GAP   = 10   -- gap between param rows
    local SL_ROW   = SL_H + SL_VAL_H + SL_GAP

    -- Helper: create one slider + value label inside a parent frame at yOff
    -- Returns the slider widget; value label is updated by the slider's onChange.
    local function MakeParamSlider(parent, label, mn, mx, def, yOff, onChange, fmt)
        local valLbl = parent:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
        valLbl:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, yOff - SL_H)
        valLbl:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, yOff - SL_H)
        valLbl:SetJustifyH("RIGHT")
        valLbl:SetHeight(SL_VAL_H)
        valLbl:SetTextColor(0.8, 0.8, 0.8, 1)

        local sl = BNB.CreateSlider(parent, label, mn, mx, def, def,
            function(v)
                local display = fmt and fmt(v) or tostring(v)
                valLbl:SetText(display)
                onChange(v)
            end)
        sl:SetWidth(AW_CW)
        sl:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, yOff)
        sl._rawVal = def
        -- Set initial label
        valLbl:SetText(fmt and fmt(def) or tostring(def))
        return sl
    end

    -- Pixel params (3 rows)
    local pixelPanel = CreateFrame("Frame",nil,ct2)
    pixelPanel:SetSize(AW_CW, SL_ROW*3); pixelPanel:SetPoint("TOPLEFT",ct2,"TOPLEFT",0,y2)

    local pixelLinesSL = MakeParamSlider(pixelPanel,"Lines",1,20,8,0,
        function(v) pixelPanel._pixelLinesSL._rawVal=v; MarkDirty()
            if not _isPopulating and f._restartPreview then f._restartPreview() end end)
    pixelPanel._pixelLinesSL = pixelLinesSL

    local pixelFreqSL = MakeParamSlider(pixelPanel,"Frequency",-100,100,25,-SL_ROW,
        function(v) pixelPanel._pixelFreqSL._rawVal=v; MarkDirty()
            if not _isPopulating and f._restartPreview then f._restartPreview() end end, fmtF2)
    pixelPanel._pixelFreqSL = pixelFreqSL

    local pixelLengthSL = MakeParamSlider(pixelPanel,"Length",1,30,10,-SL_ROW*2,
        function(v) pixelPanel._pixelLengthSL._rawVal=v; MarkDirty()
            if not _isPopulating and f._restartPreview then f._restartPreview() end end)
    pixelPanel._pixelLengthSL = pixelLengthSL
    pixelPanel:Hide()

    -- AutoCast params (3 rows)
    local acPanel = CreateFrame("Frame",nil,ct2)
    acPanel:SetSize(AW_CW, SL_ROW*3); acPanel:SetPoint("TOPLEFT",ct2,"TOPLEFT",0,y2)

    local acParticlesSL = MakeParamSlider(acPanel,"Particles",1,12,4,0,
        function(v) acPanel._acParticlesSL._rawVal=v; MarkDirty()
            if not _isPopulating and f._restartPreview then f._restartPreview() end end)
    acPanel._acParticlesSL = acParticlesSL

    local acFreqSL = MakeParamSlider(acPanel,"Frequency",-100,100,13,-SL_ROW,
        function(v) acPanel._acFreqSL._rawVal=v; MarkDirty()
            if not _isPopulating and f._restartPreview then f._restartPreview() end end, fmtF2)
    acPanel._acFreqSL = acFreqSL

    local acScaleSL = MakeParamSlider(acPanel,"Scale",5,30,10,-SL_ROW*2,
        function(v) acPanel._acScaleSL._rawVal=v; MarkDirty()
            if not _isPopulating and f._restartPreview then f._restartPreview() end end, fmtF1)
    acPanel._acScaleSL = acScaleSL
    acPanel:Hide()

    -- Border params (1 row)
    local borderPanel = CreateFrame("Frame",nil,ct2)
    borderPanel:SetSize(AW_CW, SL_ROW); borderPanel:SetPoint("TOPLEFT",ct2,"TOPLEFT",0,y2)

    local borderDurSL = MakeParamSlider(borderPanel,"Pulse duration (s)",10,200,70,0,
        function(v) borderPanel._borderDurSL._rawVal=v; MarkDirty()
            if not _isPopulating and f._restartPreview then f._restartPreview() end end, fmtF2)
    borderPanel._borderDurSL = borderDurSL
    borderPanel:Hide()

    -- Proc params (1 row)
    local procPanel = CreateFrame("Frame",nil,ct2)
    procPanel:SetSize(AW_CW, SL_ROW); procPanel:SetPoint("TOPLEFT",ct2,"TOPLEFT",0,y2)

    local procDurSL = MakeParamSlider(procPanel,"Duration (s)",10,500,100,0,
        function(v) procPanel._procDurSL._rawVal=v; MarkDirty()
            if not _isPopulating and f._restartPreview then f._restartPreview() end end, fmtF2)
    procPanel._procDurSL = procDurSL
    procPanel:Hide()

    -- Show/hide param panels when glow type changes; also restart preview
    local _glowParamPanels = {
        [1]=pixelPanel, [2]=acPanel, [3]=borderPanel, [4]=procPanel,
    }
    local function RefreshGlowParams(gType)
        for _, p in pairs(_glowParamPanels) do p:Hide() end
        if gType and _glowParamPanels[gType] then
            _glowParamPanels[gType]:Show()
        end
    end
    if glowTypeDD._dd then
        glowTypeDD._dd:SetupMenu(function(_,root)
            for _,e in ipairs(gtEntries) do
                local ev=e.value
                root:CreateRadio(e.label,
                    function() return glowTypeDD._dd._selected==ev end,
                    function()
                        glowTypeDD._dd._selected=ev; glowTypeDD._dd:SetText(e.label)
                        MarkDirty(); RefreshGlowParams(ev)
                        if not _isPopulating and f._restartPreview then f._restartPreview() end
                    end)
            end
        end)
    end

    -- Store slider refs
    f._pixelLinesSL   = pixelLinesSL
    f._pixelFreqSL    = pixelFreqSL
    f._pixelLengthSL  = pixelLengthSL
    f._acParticlesSL  = acParticlesSL
    f._acFreqSL       = acFreqSL
    f._acScaleSL      = acScaleSL
    f._borderDurSL    = borderDurSL
    f._procDurSL      = procDurSL
    f._refreshGlowParams = RefreshGlowParams

    -- Max param panel height is 3 rows; advance y2 past it
    y2 = y2 - SL_ROW*3 - AW_SECT_GAP
    Div(ct2,y2); y2 = y2 - AW_GAP

    -- ── Preview (continuous — runs while tab is visible) ─────────────────────
    -- Placed at the bottom so param sliders have full width above.
    SectionHdr(ct2,"Preview",y2); y2 = y2 - AW_LBL - 2

    local PREV_ICON_SZ = 48
    local previewHost = CreateFrame("Frame",nil,ct2)
    previewHost:SetSize(PREV_ICON_SZ,PREV_ICON_SZ)
    previewHost:SetPoint("TOP",ct2,"TOPLEFT",AW_CW/2,y2)
    previewHost:SetFrameLevel(ct2:GetFrameLevel()+10)
    previewHost:EnableMouse(false)

    local previewIconTx = ct2:CreateTexture(nil,"ARTWORK")
    previewIconTx:SetSize(PREV_ICON_SZ,PREV_ICON_SZ)
    previewIconTx:SetPoint("TOP",ct2,"TOPLEFT",AW_CW/2,y2)
    previewIconTx:SetTexCoord(0.08,0.92,0.08,0.92)

    y2 = y2 - PREV_ICON_SZ - AW_GAP
    ct2._contentH = math.abs(y2)

    -- Preview engine: builds a scratch alarm from current UI values, never touches DB.
    local function BuildPreviewAlarm()
        local gType = glowTypeDD:GetSelected()
        local lines, freq, length, particles, scale, duration
        if gType == 1 then
            lines    = pixelLinesSL._rawVal
            freq     = pixelFreqSL._rawVal / 100
            length   = pixelLengthSL._rawVal
        elseif gType == 2 then
            particles = acParticlesSL._rawVal
            freq      = acFreqSL._rawVal / 100
            scale     = acScaleSL._rawVal / 10
        elseif gType == 3 then
            duration  = borderDurSL._rawVal / 100
        elseif gType == 4 then
            duration  = procDurSL._rawVal / 100
        end
        return {
            glowType=gType, glowColor=glowColorVal, glowMode="continuous",
            glowLines=lines, glowFrequency=freq, glowLength=length,
            glowParticles=particles, glowScale=scale, glowDuration=duration,
        }
    end

    local _previewNoteID = "bnb-preview-anim"
    local function StartPreview()
        if not BNB.Alarm then return end
        local AM = BNB.Alarm
        AM.UnregisterGlowTarget(_previewNoteID, previewHost)
        AM.GlowStop(_previewNoteID)
        AM.RegisterGlowTarget(_previewNoteID, previewHost)
        local scratchAlarm = BuildPreviewAlarm()
        if AM._LCGStart then AM._LCGStart(previewHost, scratchAlarm) end
    end

    local function StopPreview()
        if not BNB.Alarm then return end
        BNB.Alarm.GlowStop(_previewNoteID)
        BNB.Alarm.UnregisterGlowTarget(_previewNoteID, previewHost)
        if BNB.Alarm._LCGStop then BNB.Alarm._LCGStop(previewHost) end
    end

    f._restartPreview = function()
        if not sf2:IsShown() then return end
        StopPreview(); StartPreview()
    end

    -- Wire color controls to restart preview
    local origRstCol = rstCol:GetScript("OnClick")
    rstCol:SetScript("OnClick", function(self)
        if origRstCol then origRstCol(self) end
        if not _isPopulating then f._restartPreview() end
    end)

    -- Start/stop preview with tab visibility
    sf2:HookScript("OnShow", function() StartPreview() end)
    sf2:HookScript("OnHide", function() StopPreview() end)

    -- Store preview refs
    f._previewIconTx = previewIconTx
    f._previewHost   = previewHost

    -- ================================================================
    -- TAB 3: ADVANCED
    -- ================================================================
    local y3 = -4

    -- Section: Snooze
    SectionHdr(ct3,"Snooze",y3); y3 = y3 - AW_LBL - 2

    local snoozeEnableCB=CreateFrame("CheckButton",nil,ct3,"UICheckButtonTemplate")
    snoozeEnableCB:SetPoint("TOPLEFT",ct3,"TOPLEFT",0,y3+2)
    snoozeEnableCB:SetChecked(true)
    snoozeEnableCB:HookScript("OnClick",function() MarkDirty() end)
    local snoozeEnableLbl=ct3:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
    snoozeEnableLbl:SetPoint("LEFT",snoozeEnableCB,"RIGHT",2,0)
    snoozeEnableLbl:SetText("Enable snooze")
    snoozeEnableLbl:SetTextColor(0.85,0.85,0.85,1)
    y3 = y3 - 28 - AW_GAP

    Lbl(ct3,"Interval",y3); y3 = y3 - AW_LBL
    local snzEntries={
        {label="1 minute",  value=1 },
        {label="5 minutes", value=5 },
        {label="10 minutes",value=10},
        {label="15 minutes",value=15},
        {label="30 minutes",value=30},
        {label="60 minutes",value=60},
    }
    local snoozeIntervalDD=MakeDD(ct3,snzEntries,5,nil)
    snoozeIntervalDD:SetPoint("TOPLEFT",ct3,"TOPLEFT",0,y3); y3 = y3 - AW_ROW - AW_GAP

    Lbl(ct3,"Repeat",y3); y3 = y3 - AW_LBL
    local snzRepEntries={
        {label="1 time",  value=1},
        {label="3 times", value=3},
        {label="5 times", value=5},
        {label="Forever", value=0},
    }
    local snoozeRepeatDD=MakeDD(ct3,snzRepEntries,0,nil)
    snoozeRepeatDD:SetPoint("TOPLEFT",ct3,"TOPLEFT",0,y3); y3 = y3 - AW_ROW - AW_SECT_GAP

    -- Wire snooze enable checkbox to grey/enable sub-controls
    local function RefreshSnoozeState()
        local on = snoozeEnableCB:GetChecked()
        if snoozeIntervalDD._dd then snoozeIntervalDD._dd:SetEnabled(on) end
        if snoozeRepeatDD._dd   then snoozeRepeatDD._dd:SetEnabled(on)   end
        snoozeEnableLbl:SetTextColor(on and 0.85 or 0.45, 0.85, on and 0.85 or 0.45, 1)
    end
    snoozeEnableCB:HookScript("OnClick",function() RefreshSnoozeState() end)

    Div(ct3,y3); y3 = y3 - AW_GAP

    -- Section: On Fire behaviour
    SectionHdr(ct3,"On Fire",y3); y3 = y3 - AW_LBL - 2
    local fmEntries={
        {label="Alarm popup (default)",          value="popup"    },
        {label="Open sticky note",               value="sticky"   },
        {label="Minimized sticky with animation",value="minimized"},
    }
    local fireModeDD=MakeDD(ct3,fmEntries,"popup",nil)
    fireModeDD:SetPoint("TOPLEFT",ct3,"TOPLEFT",0,y3); y3 = y3 - AW_ROW - AW_SECT_GAP

    Div(ct3,y3); y3 = y3 - AW_GAP

    -- Section: Combat
    SectionHdr(ct3,"Combat",y3); y3 = y3 - AW_LBL - 2

    Lbl(ct3,"During combat",y3); y3 = y3 - AW_LBL
    local cbtEntries={
        {label="Fire immediately",       value="fire" },
        {label="Wait for combat to end", value="queue"},
    }
    local combatDD=MakeDD(ct3,cbtEntries,"queue",nil)
    combatDD:SetPoint("TOPLEFT",ct3,"TOPLEFT",0,y3); y3 = y3 - AW_ROW - AW_GAP

    Lbl(ct3,"After combat (if queued)",y3); y3 = y3 - AW_LBL
    local pstEntries={
        {label="Fire popup immediately",value="immediate"},
        {label="Show summary count",    value="summary"  },
        {label="Chat message + popup",  value="chat"     },
    }
    local postDD=MakeDD(ct3,pstEntries,"immediate",nil)
    postDD:SetPoint("TOPLEFT",ct3,"TOPLEFT",0,y3); y3 = y3 - AW_ROW - AW_GAP
    ct3._contentH=math.abs(y3)

    -- ── STORE REFS ────────────────────────────────────────────────────────────
    _labelEB         = labelEB
    _timeDDCont      = timeDDCont
    _realSection     = realSection
    _realTimeRow     = realTimeRow
    _igSection       = igSection
    _igHourDD        = igHourDD
    _igMinDD         = igMinDD
    _hourDD          = hourDD
    _minDD           = minDD
    _recurDD         = recurDD
    _wdChecks        = wdChecks
    _wdRow           = wdRow
    _ndaysEB         = ndEB
    _ndaysRow        = ndRow
    _soundDD         = soundDD
    _glowTypeDD      = glowTypeDD
    _glowModeDD      = glowModeDD
    -- _fireModeDD assigned below after Advanced tab builds it
    _fireModeDD      = fireModeDD
    _snoozeEnableCB  = snoozeEnableCB
    _snoozeIntervalDD= snoozeIntervalDD
    _snoozeRepeatDD  = snoozeRepeatDD
    _combatDD        = combatDD
    _postDD          = postDD

    f._getGlowColor = function() return glowColorVal end
    f._setGlowColor = function(c)
        glowColorVal=c
        if c then swTx:SetColorTexture(c[1],c[2],c[3],1)
        else       swTx:SetColorTexture(BNB_GR,BNB_GG,BNB_GB,1) end
    end
    f._setTimeType      = SetTimeType
    f._setRecur         = SetRecur
    f._refreshCalendar  = RefreshCalendar
    f._refreshSnoozeState = RefreshSnoozeState
    f._setCalDate = function(yr,mo,dy)
        _calYear=yr; _calMonth=mo; _calSelDay=dy; RefreshCalendar()
    end

    -- ── SAVE ─────────────────────────────────────────────────────────────────
    saveBtn:SetScript("OnClick",function()
        local note=_noteID and BNB.GetNote and BNB.GetNote(_noteID)
        if not note then AW.Close(); return end
        local alarm=note.alarm or {}

        alarm.label=labelEB:GetRealText()
        if alarm.label=="" then alarm.label=nil end

        local tt=timeDDCont:GetSelected() or "real"
        alarm.timeType=tt
        if tt=="ingame" then
            alarm.igTime=string.format("%02d:%02d",
                igHourDD:GetSelected() or 9,igMinDD:GetSelected() or 0)
            alarm.time=nil
        else
            alarm.time=time({
                year=_calYear or 2026,month=_calMonth or 1,
                day=_calSelDay or 1,
                hour=hourDD:GetSelected() or 9,
                min=minDD:GetSelected() or 0,sec=0,
            })
            alarm.igTime=nil
        end

        local recur=recurDD:GetSelected(); alarm.recur=recur
        if recur=="weekdays" then
            alarm.recurDays={}
            for _,cb in ipairs(wdChecks) do
                if cb:GetChecked() then table.insert(alarm.recurDays,cb._dayIndex) end
            end
        elseif recur=="interval" then
            alarm.recurEvery=tonumber(ndEB:GetText()) or 7
        else alarm.recurDays=nil; alarm.recurEvery=nil end

        alarm.sound         = soundDD:GetSelected()
        local savedGlowType = glowTypeDD:GetSelected()
        alarm.glowType  = savedGlowType
        alarm.glowMode  = glowModeDD:GetSelected()
        alarm.glowColor = glowColorVal

        -- Save advanced params from sliders (nil = use LCG default)
        -- Integer sliders store raw units; floats stored ×100 or ×10, divided on read.
        if savedGlowType == 1 then      -- Pixel
            alarm.glowLines     = _frame._pixelLinesSL and _frame._pixelLinesSL._rawVal
            alarm.glowFrequency = _frame._pixelFreqSL  and _frame._pixelFreqSL._rawVal  / 100
            alarm.glowLength    = _frame._pixelLengthSL and _frame._pixelLengthSL._rawVal
            alarm.glowParticles = nil; alarm.glowScale = nil; alarm.glowDuration = nil
        elseif savedGlowType == 2 then  -- AutoCast
            alarm.glowParticles = _frame._acParticlesSL and _frame._acParticlesSL._rawVal
            alarm.glowFrequency = _frame._acFreqSL      and _frame._acFreqSL._rawVal      / 100
            alarm.glowScale     = _frame._acScaleSL     and _frame._acScaleSL._rawVal     / 10
            alarm.glowLines = nil; alarm.glowLength = nil; alarm.glowDuration = nil
        elseif savedGlowType == 3 then  -- Border
            alarm.glowDuration  = _frame._borderDurSL and _frame._borderDurSL._rawVal / 100
            alarm.glowLines = nil; alarm.glowFrequency = nil; alarm.glowLength = nil
            alarm.glowParticles = nil; alarm.glowScale = nil
        elseif savedGlowType == 4 then  -- Proc
            alarm.glowDuration  = _frame._procDurSL and _frame._procDurSL._rawVal / 100
            alarm.glowLines = nil; alarm.glowFrequency = nil; alarm.glowLength = nil
            alarm.glowParticles = nil; alarm.glowScale = nil
        else  -- nil = default, clear all
            alarm.glowLines=nil; alarm.glowFrequency=nil; alarm.glowLength=nil
            alarm.glowParticles=nil; alarm.glowScale=nil; alarm.glowDuration=nil
        end

        alarm.fireMode      = fireModeDD:GetSelected()
        alarm.snoozeEnabled = snoozeEnableCB:GetChecked()
        alarm.snoozeDefault = snoozeIntervalDD:GetSelected()
        alarm.snoozeRepeat  = snoozeRepeatDD:GetSelected()
        alarm.combatMode    = combatDD:GetSelected()
        alarm.combatPost    = postDD:GetSelected()
        alarm.fired         = alarm.fired or false

        BNB.Alarm.SetAlarm(_noteID,alarm)
        AW.Close()
    end)

    delBtn:SetScript("OnClick",function()
        if _noteID then BNB.Alarm.ClearAlarm(_noteID) end
        AW.Close()
    end)
end

-- ---------------------------------------------------------------------------
-- POPULATE
-- ---------------------------------------------------------------------------
local function Populate(noteID)
    local f=_frame; if not f then return end
    local note  = noteID and BNB.GetNote and BNB.GetNote(noteID)
    local alarm = (note and note.alarm) or {}
    local hasExisting = note and note.alarm ~= nil

    _isPopulating = true

    -- Reset label (always — stale text from a previous alarm must not carry over)
    _labelEB:SetRealText(alarm.label or "")

    local tt=alarm.timeType or "real"
    _timeDDCont:SetSelected(tt); f._setTimeType(tt)

    -- Always set calendar to today (or alarm date if editing)
    local t = alarm.time and date("*t",alarm.time) or date("*t")
    f._setCalDate(t.year, t.month, t.day)
    -- Always reset hour/min — explicit default 9:00 for new alarms
    _hourDD:SetSelected(alarm.time and t.hour or 9)
    _minDD:SetSelected(alarm.time and math.floor(t.min/5)*5 or 0)
    -- Always reset in-game time dropdowns
    if alarm.igTime then
        local h,m=alarm.igTime:match("^(%d+):(%d+)$")
        if h then
            _igHourDD:SetSelected(tonumber(h))
            _igMinDD:SetSelected(math.floor(tonumber(m)/5)*5)
        end
    else
        _igHourDD:SetSelected(9)
        _igMinDD:SetSelected(0)
    end

    _recurDD:SetSelected(alarm.recur); f._setRecur(alarm.recur)
    -- Always reset weekday checkboxes
    if alarm.recur=="weekdays" and alarm.recurDays then
        local ds={}; for _,d in ipairs(alarm.recurDays) do ds[d]=true end
        for _,cb in ipairs(_wdChecks) do cb:SetChecked(ds[cb._dayIndex] or false) end
    else
        for _,cb in ipairs(_wdChecks) do cb:SetChecked(false) end
    end
    if alarm.recur=="interval" then _ndaysEB:SetText(tostring(alarm.recurEvery or 7))
    else _ndaysEB:SetText("7") end

    _soundDD:SetSelected(alarm.sound or "default")
    _glowTypeDD:SetSelected(alarm.glowType)
    _glowModeDD:SetSelected(alarm.glowMode)
    f._setGlowColor(alarm.glowColor)
    -- Populate sliders — convert stored floats back to integer slider units
    if f._pixelLinesSL   then SetSliderVal(f._pixelLinesSL,   alarm.glowLines     or 8)   end
    if f._pixelFreqSL    then SetSliderVal(f._pixelFreqSL,    math.floor((alarm.glowFrequency or 0.25)*100)) end
    if f._pixelLengthSL  then SetSliderVal(f._pixelLengthSL,  alarm.glowLength    or 10)  end
    if f._acParticlesSL  then SetSliderVal(f._acParticlesSL,  alarm.glowParticles or 4)   end
    if f._acFreqSL       then SetSliderVal(f._acFreqSL,       math.floor((alarm.glowFrequency or 0.125)*100)) end
    if f._acScaleSL      then SetSliderVal(f._acScaleSL,      math.floor((alarm.glowScale     or 1.0)*10))    end
    if f._borderDurSL    then SetSliderVal(f._borderDurSL,    math.floor((alarm.glowDuration  or 0.7)*100))   end
    if f._procDurSL      then SetSliderVal(f._procDurSL,      math.floor((alarm.glowDuration  or 1.0)*100))   end
    if f._refreshGlowParams then f._refreshGlowParams(alarm.glowType) end
    if _fireModeDD then _fireModeDD:SetSelected(alarm.fireMode or "popup") end

    -- Advanced
    local snoozeOn = alarm.snoozeEnabled
    if snoozeOn == nil then snoozeOn = true end  -- default on
    _snoozeEnableCB:SetChecked(snoozeOn)
    _snoozeIntervalDD:SetSelected(alarm.snoozeDefault or 5)
    _snoozeRepeatDD:SetSelected(alarm.snoozeRepeat or 0)
    f._refreshSnoozeState()

    _combatDD:SetSelected(alarm.combatMode or "queue")
    _postDD:SetSelected(alarm.combatPost or "immediate")

    -- Update preview icon
    if f._previewIconTx then
        local icon = note and note.icon
        if icon and icon ~= "" then
            f._previewIconTx:SetTexture(icon)
            f._previewIconTx:Show()
        else
            f._previewIconTx:SetTexture("Interface/AddOns/BigNoteBox/Assets/icon")
            f._previewIconTx:Show()
        end
    end

    -- Save button: enabled immediately for new alarms so user can save defaults.
    -- For existing alarms, start disabled until the user makes a change.
    _isDirty = false
    if _saveBtn then _saveBtn:SetEnabled(not hasExisting) end
    _isPopulating = false
end

-- ---------------------------------------------------------------------------
-- OPEN HELPERS
-- ---------------------------------------------------------------------------
local function DoOpen(noteID, anchorFrame, stickyFrame)
    if not _frame then
        local f, sf1, sf2, sf3, ct1, ct2, ct3, saveBtn, delBtn
        if BigNoteBoxDB and BigNoteBoxDB.skinMode then
            f, sf1, sf2, sf3, ct1, ct2, ct3, saveBtn, delBtn = BuildWindowSkin()
        else
            f, sf1, sf2, sf3, ct1, ct2, ct3, saveBtn, delBtn = BuildWindow()
        end
        BuildTabContent(f, sf1, sf2, sf3, ct1, ct2, ct3, saveBtn, delBtn)
    end
    local f = _frame

    local ss = _G["BigNoteBoxStickySettingsFrame"]
    if ss and ss:IsShown() then
        if BNB.Sticky and BNB.Sticky.CloseSettings then BNB.Sticky.CloseSettings()
        else ss:Hide() end
    end

    _noteID = noteID; _stickyFrame = stickyFrame or nil
    Populate(noteID)
    if f._selectTab then f._selectTab(1) end  -- always open on General tab
    f:Show(); f:Raise()
    return f
end

-- ---------------------------------------------------------------------------
-- PUBLIC API
-- ---------------------------------------------------------------------------
function AW.Open(noteID, anchorFrame, stickyFrame)
    if not noteID then return end
    local f = DoOpen(noteID, anchorFrame, stickyFrame)
    f:ClearAllPoints()
    local anchor = stickyFrame or anchorFrame
    if anchor and anchor.GetWidth then
        local scrW = UIParent:GetWidth()
        local cx   = anchor:GetCenter()
        local aw   = anchor:GetWidth()
        local right = ((cx or 0)+(aw or 0)/2+8+AW_W) <= scrW
        if right then f:SetPoint("LEFT",  anchor,"RIGHT",  8,0)
        else          f:SetPoint("RIGHT", anchor,"LEFT",  -8,0) end
    else
        f:SetPoint("CENTER",UIParent,"CENTER",0,60)
    end
end

function AW.OpenLeftOfMain(noteID)
    if not noteID then return end
    local f = DoOpen(noteID, nil, nil)
    f:ClearAllPoints()
    local mf = BNB.mainFrame
    if mf then f:SetPoint("TOPRIGHT",mf,"TOPLEFT",-4,0)
    else       f:SetPoint("CENTER",UIParent,"CENTER",0,60) end
end

function AW.Close()
    if _frame then _frame:Hide() end
    _noteID=nil; _stickyFrame=nil; _isDirty=false
end

function AW.IsOpen()    return _frame and _frame:IsShown() end
function AW.GetNoteID() return _noteID end

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
local L = BNB.L

BNB.AlarmWindow = BNB.AlarmWindow or {}
local AW = BNB.AlarmWindow

-- ---------------------------------------------------------------------------
-- LAYOUT
-- ---------------------------------------------------------------------------
local AW_W       = 290   -- same size as the Reference Box (Dukul 2026-10-01)
local AW_H       = 640
local AW_PAD     = 12
local AW_CW      = AW_W - 40   -- content width
local AW_TAB_Y   = 62    -- top of tab content area
local AW_FOOT_H  = 38    -- static footer height (Save / Delete)
local AW_ROW     = 22
local AW_GAP     = 8     -- increased gap between items
local AW_LBL     = 14    -- section header height
local AW_SECT_GAP = 12   -- gap between sections
local SOUND_REPEAT_DEFAULT = 10  -- alarm.soundRepeat nil = every 10 s (AlarmManager SOUND_REPEAT)

-- BNB green
local BNB_GR, BNB_GG, BNB_GB = 0.400, 0.733, 0.416

-- Keys, not resolved strings: this table is built at file load, before
-- BigNoteBoxDB (and debugPseudoLocale) is restored, so caching L[...] results
-- here would freeze them at their pre-SavedVariables value forever. Resolve
-- each key through L at the two call sites below instead.
local DAY_NAME_KEYS = { "AW_DAY_MON", "AW_DAY_TUE", "AW_DAY_WED", "AW_DAY_THU",
                         "AW_DAY_FRI", "AW_DAY_SAT", "AW_DAY_SUN" }

-- ---------------------------------------------------------------------------
-- STATE
-- ---------------------------------------------------------------------------
local _frame       = nil
local _noteID      = nil
local _isPopulating = false  -- true while Populate() is running; suppresses MarkDirty

-- Calendar upvalues
local _calYear, _calMonth, _calSelDay

-- Widget refs
local _labelEB, _timeDDCont
local _igTP, _realTP   -- hour/minute(/AM-PM) fields, see TimePair
local _recurDD, _wdChecks, _ndaysEB
local _soundDD, _soundRepDD, _glowTypeDD, _glowModeDD, _fireModeDD
local _snoozeEnableCB, _snoozeIntervalDD, _snoozeRepeatDD
local _combatDD, _postDD
local _saveBtn   -- ref so Populate can enable/disable it
local _delBtn    -- Remove Alarm, or Cancel while the alarm is not saved yet (ALL-346)

-- ---------------------------------------------------------------------------
-- HELPERS
-- ---------------------------------------------------------------------------
-- Slider value helpers (used by BuildWindow and Populate)
local function SetSliderVal(sl, v)
    if not sl then return end
    sl._rawVal = v
    sl:SetValue(v)
end

-- Mark dirty and enable save button
local function MarkDirty()
    if _isPopulating then return end
    if _saveBtn then _saveBtn:SetEnabled(true) end
end

-- Layout adapters over the shared pieces in UI/Widgets.lua (ALL-65.8)
local function MakeDD(parent, entries, initial, onChange, width)
    return BNB.CreateValueDropdown(parent, entries, initial, onChange, width or AW_CW, AW_ROW, MarkDirty)
end
local function SectionHdr(parent, text, y) return BNB.CreateSectionHeader(parent, text, y, AW_CW) end
local function Lbl(parent, text, y)        return BNB.CreateSmallLabel(parent, text, y, AW_CW) end
local function Div(parent, y)              BNB.CreateRule(parent, y, AW_CW) end

-- The sound files live in AlarmManager (BNB.Alarm.SoundPath), which also
-- rings the alarm: the Test button plays exactly what the alarm will
local function SoundPath(key)
    return BNB.Alarm and BNB.Alarm.SoundPath and BNB.Alarm.SoundPath(key)
end

-- ---------------------------------------------------------------------------
-- SCROLL PANEL FACTORY — one per tab
-- ---------------------------------------------------------------------------
local function MakeScrollPanel(f)
    local sf, ct = BNB.CreateAutoScrollPanel(f, AW_CW, AW_CW + 20)
    sf:SetPoint("TOPLEFT",     f,"TOPLEFT",     AW_PAD, -AW_TAB_Y)
    sf:SetPoint("BOTTOMRIGHT", f,"BOTTOMRIGHT", -24, AW_FOOT_H + 6)
    sf:Hide()
    return sf, ct
end

-- ---------------------------------------------------------------------------
-- BUILD (once). Chrome from BNB.CreateToolWindow (UI/ToolWindow.lua) in
-- either mode; the tab row differs per mode but both end at AW_TAB_Y (62px),
-- so all tab content anchors are identical.
-- ---------------------------------------------------------------------------
local SK_AW_TITLE_H = 28   -- skin title bar strip height
local SK_AW_TAB_GAP = 10   -- gap below tabs to reach AW_TAB_Y (62px total)

local function BuildWindow()
    if _frame then return _frame end

    local f, saveBtn, delBtn = BNB.CreateToolWindow({
        name = "BNBAlarmWindow", w = AW_W, h = AW_H, title = L["AW_TITLE"],
        pad = AW_PAD, cw = AW_CW, footH = AW_FOOT_H,
        btn1 = L["SAVE"], btn2 = L["AW_REMOVE_ALARM_BTN"],
        toplevel = true, escClose = true,
        onClose     = function() AW.Close() end,
        onHide      = function()
            _noteID = nil; _isPopulating = false
        end,
    })
    saveBtn:SetEnabled(false)
    delBtn._plainColor = { delBtn:GetFontString():GetTextColor() }
    _saveBtn = saveBtn
    _delBtn  = delBtn

    -- ── TABS ─────────────────────────────────────────────────────────────────
    local tabNames = {L["AW_TAB_GENERAL"], L["AW_TAB_ANIMATION"], L["AW_TAB_ADVANCED"]}
    local tabPanels = {}
    if f._isSkin then
        local tabCtrl = BNB.CreateSkinTabs(f, tabNames, function(idx)
            for i = 1, 3 do
                if tabPanels[i] then tabPanels[i]:SetShown(i == idx) end
            end
            f._activeTab = idx
        end)
        tabCtrl.frame:SetPoint("TOPLEFT",  f, "TOPLEFT",  AW_PAD, -(SK_AW_TITLE_H + SK_AW_TAB_GAP))
        tabCtrl.frame:SetPoint("TOPRIGHT", f, "TOPRIGHT", -AW_PAD, -(SK_AW_TITLE_H + SK_AW_TAB_GAP))
        f._selectTab = function(idx) tabCtrl.Select(idx) end
    else
        local tpl = "PanelTopTabButtonTemplate"

        local tabBtns = {}
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
        for i, text in ipairs(tabNames) do
            local btn = CreateFrame("Button","BNBAlarmWindowTab"..i, f, tpl)
            btn:SetText(text)
            pcall(function()
                PanelTemplates_TabResize(btn,15,nil,70)
            end)
            btn:SetID(i)
            if lastBtn then btn:SetPoint("LEFT",lastBtn,"RIGHT",5,0)
            else             btn:SetPoint("TOPLEFT",f,"TOPLEFT",7,-25) end
            btn:SetScript("OnClick", function(self) SelectTab(self:GetID()) end)
            tabBtns[i]=btn; lastBtn=btn
        end
        PanelTemplates_SetNumTabs(f,3); f.numTabs=3
        -- Keep the row inside the window (ALL-170: Classic tabs ran outside)
        BNB.FitTabRow(f, tabBtns, 7, 5)
    end

    local sf1,ct1 = MakeScrollPanel(f)
    local sf2,ct2 = MakeScrollPanel(f)
    local sf3,ct3 = MakeScrollPanel(f)
    tabPanels[1]=sf1; tabPanels[2]=sf2; tabPanels[3]=sf3

    _frame=f
    return f, sf1, sf2, sf3, ct1, ct2, ct3, saveBtn, delBtn
end

-- ---------------------------------------------------------------------------
-- TAB 1 PIECES: Time, Repeat and Sound, split out of BuildTabContent (CMP-07).
-- Repeat and Sound are frames of their own, placed by the Type's relayout
-- right under the Type's rows; Repeat is hidden for the reset types (ALL-342).
-- ---------------------------------------------------------------------------
-- Type value -> reset kind (BNB.Alarm.ResetKind's answer)
local RESET_OF = { dailyreset = "daily", weeklyreset = "weekly" }
local RESET_H  = 30 + AW_GAP   -- the reset types' two-line note

-- Hour and minute are typeable fields with a value list (ALL-136.3):
-- Tab or ":" moves between them, Enter leaves the field, every minute
-- 00-59. With a 12-hour clock (Appearance > Timestamp format) the hour
-- runs 1-12 and an AM/PM field follows. tp:Set / tp:Get use 0-23 hours.
local function TimePair(row)
    local tp = {}
    local hBox, mBox
    hBox = BNB.CreateNumberCombo(row,0,23,9,100,AW_ROW,{ onDirty=MarkDirty,
        onTab=function() mBox.eb:SetFocus() end })
    mBox = BNB.CreateNumberCombo(row,0,59,0,100,AW_ROW,{ onDirty=MarkDirty,
        onTab=function() hBox.eb:SetFocus() end })
    local cln = row:CreateFontString(nil,"OVERLAY","GameFontNormal"); cln:SetText(":")
    local apDD = MakeDD(row,{ {label=L["AW_AM"],value="am"}, {label=L["AW_PM"],value="pm"} },"am",nil,
        math.floor((AW_CW-20)/3))
    local use24 = true
    function tp:Layout()
        local db = BigNoteBoxDB
        local h, m = tp:Get()   -- in the old mode, before use24 changes
        use24 = db == nil or db.use24Hour ~= false
        local w = use24 and (math.floor(AW_CW/2)-6) or math.floor((AW_CW-20)/3)
        hBox:SetFieldWidth(w); mBox:SetFieldWidth(w)
        hBox:ClearAllPoints(); hBox:SetPoint("LEFT",row,"LEFT",0,0)
        cln:ClearAllPoints();  cln:SetPoint("LEFT",row,"LEFT",w+4,0)
        mBox:ClearAllPoints(); mBox:SetPoint("LEFT",row,"LEFT",w+12,0)
        apDD:ClearAllPoints(); apDD:SetPoint("LEFT",row,"LEFT",w*2+20,0)
        apDD:SetShown(not use24)
        if use24 then hBox:SetRange(0,23) else hBox:SetRange(1,12) end
        tp:Set(h, m)
    end
    function tp:Set(h, m)
        h = tonumber(h) or 9
        if use24 then
            hBox:SetValue(h)
        else
            apDD:SetSelected(h >= 12 and "pm" or "am")
            local h12 = h % 12; if h12 == 0 then h12 = 12 end
            hBox:SetValue(h12)
        end
        mBox:SetValue(m or 0)
    end
    function tp:Get()
        local h = hBox:GetValue()
        if not use24 then h = h % 12 + (apDD:GetSelected() == "pm" and 12 or 0) end
        return h, mBox:GetValue()
    end
    return tp
end

-- Section: Time (Type dropdown + the Type's own rows). Returns a table:
-- dd, realTP, igTP, setType(v), refreshCalendar, topY (where the Type's rows
-- start), heights[real / ingame / reset]; the caller sets T.relayout(v).
local function BuildTimeSection(ct1, y)
    local T = {}
    SectionHdr(ct1,L["AW_SECT_TIME"],y); y = y - AW_LBL - 2
    Lbl(ct1,L["AW_LBL_TYPE"],y); y = y - AW_LBL
    -- Daily / Weekly reset ring at the reset itself, every day / week: no
    -- date, time or Repeat for them (ALL-342, Dukul 2026-10-06)
    local timeEntries = {
        {label=L["AW_TIME_REAL"],         value="real"},
        {label=L["AW_TIME_INGAME"],       value="ingame"},
        {label=L["AW_TIME_DAILY_RESET"],  value="dailyreset"},
        {label=L["AW_TIME_WEEKLY_RESET"], value="weeklyreset"},
    }
    local timeDDCont = MakeDD(ct1,timeEntries,"real",nil)
    timeDDCont:SetPoint("TOPLEFT",ct1,"TOPLEFT",0,y)
    y = y - AW_ROW - AW_GAP
    local topY = y

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

    -- Previous / next month arrows: icon buttons, skin look in skin mode (ALL-210)
    local CAL_BTN_SZ = 18
    local pBtn = BNB.CreateIconButton(realSection, CAL_BTN_SZ, "left")
    pBtn:SetPoint("TOPLEFT", realSection, "TOPLEFT", 0, 0)
    local nBtn = BNB.CreateIconButton(realSection, CAL_BTN_SZ, "right")
    nBtn:SetPoint("TOPRIGHT", realSection, "TOPRIGHT", 0, 0)

    for i,dnKey in ipairs(DAY_NAME_KEYS) do
        local dn = L[dnKey]
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
    local realTP = TimePair(realTimeRow)

    -- In-game time, in the calendar's place
    local igSection = CreateFrame("Frame",nil,ct1)
    igSection:SetSize(AW_CW, AW_LBL+AW_ROW+AW_GAP)
    igSection:SetPoint("TOPLEFT",ct1,"TOPLEFT",0,topY)
    igSection:Hide()

    local igNote = igSection:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
    igNote:SetPoint("TOPLEFT",igSection,"TOPLEFT",0,0)
    igNote:SetWidth(AW_CW); igNote:SetJustifyH("LEFT")
    igNote:SetText(L["AW_INGAME_NOTE"])
    igNote:SetTextColor(0.55,0.55,0.55,1)

    local igRow = CreateFrame("Frame",nil,igSection)
    igRow:SetSize(AW_CW,AW_ROW); igRow:SetPoint("TOPLEFT",igSection,"TOPLEFT",0,-AW_LBL)
    local igTP = TimePair(igRow)

    -- Daily / Weekly reset: what it does and when it rings next (ALL-342)
    local resetSection = CreateFrame("Frame",nil,ct1)
    resetSection:SetSize(AW_CW, RESET_H)
    resetSection:SetPoint("TOPLEFT",ct1,"TOPLEFT",0,topY)
    resetSection:Hide()
    local resetNote = resetSection:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
    resetNote:SetPoint("TOPLEFT",resetSection,"TOPLEFT",0,0)
    resetNote:SetWidth(AW_CW); resetNote:SetJustifyH("LEFT"); resetNote:SetWordWrap(true)
    resetNote:SetTextColor(0.55,0.55,0.55,1)

    local function SetTimeType(v)
        v = v or "real"
        local kind = RESET_OF[v]
        realSection:SetShown(v=="real"); realTimeRow:SetShown(v=="real")
        igSection:SetShown(v=="ingame"); resetSection:SetShown(kind ~= nil)
        if kind then
            local txt = L[kind=="daily" and "AW_RESET_NOTE_DAILY" or "AW_RESET_NOTE_WEEKLY"]
            local nextT = BNB.Alarm and BNB.Alarm.NextResetTime and BNB.Alarm.NextResetTime(kind)
            if nextT then
                txt = txt .. "\n" .. string.format(L["AW_RESET_NEXT_FMT"],
                    BNB.FmtDate(nextT) .. " " .. BNB.FmtClock(nextT))
            end
            resetNote:SetText(txt)
        end
        if T.relayout then T.relayout(v) end
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

    T.dd, T.realTP, T.igTP = timeDDCont, realTP, igTP
    T.setType, T.refreshCalendar = SetTimeType, RefreshCalendar
    T.topY = topY
    T.heights = {
        real   = CAL_TOTAL + AW_GAP + AW_ROW + AW_GAP,
        ingame = AW_LBL + AW_ROW + AW_GAP,
        reset  = RESET_H,
    }
    return T
end

-- Section: Repeat, its own frame (hidden for the reset types). Returns
-- { frame, h, dd, wdChecks, ndEB, setRecur }.
local function BuildRepeatBlock(ct1)
    local blk = CreateFrame("Frame",nil,ct1)
    blk:SetWidth(AW_CW)
    local y = 0
    Div(blk,y); y = y - AW_GAP
    SectionHdr(blk,L["AW_SECT_REPEAT"],y); y = y - AW_LBL - 2
    -- The WoW weekly reset is a Type since ALL-342, no longer a Repeat choice
    local recurEntries={
        {label=L["AW_RECUR_NONE"],     value=nil        },
        {label=L["AW_RECUR_WEEKDAYS"], value="weekdays" },
        {label=L["AW_RECUR_INTERVAL"], value="interval" },
    }
    local recurDD = MakeDD(blk,recurEntries,nil,nil)
    recurDD:SetPoint("TOPLEFT",blk,"TOPLEFT",0,y); y = y - AW_ROW - AW_GAP

    local wdRow = CreateFrame("Frame",nil,blk)
    wdRow:SetSize(AW_CW,22); wdRow:SetPoint("TOPLEFT",blk,"TOPLEFT",0,y); wdRow:Hide()
    local wdChecks={}; local wdCW=math.floor(AW_CW/7)
    for i,dnKey in ipairs(DAY_NAME_KEYS) do
        local dn = L[dnKey]
        local cb=CreateFrame("CheckButton",nil,wdRow,"UICheckButtonTemplate")
        BNB.LabelHit(cb)   -- the tooltip and click reach over its label too
        cb:SetSize(20,20); cb:SetPoint("LEFT",wdRow,"LEFT",(i-1)*wdCW,0)
        cb:HookScript("OnClick",function() MarkDirty() end)
        local dl=wdRow:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
        dl:SetPoint("LEFT",cb,"RIGHT",1,0); dl:SetText(dn:sub(1,1))
        dl:SetTextColor(0.72,0.72,0.72,1); cb._dayIndex=i; wdChecks[i]=cb
        BNB.CheckTip(cb, string.format(L["AW_WEEKDAY_TIP_FMT"], dn))   -- the label is one letter
    end

    local ndRow = CreateFrame("Frame",nil,blk)
    ndRow:SetSize(AW_CW,AW_ROW); ndRow:SetPoint("TOPLEFT",blk,"TOPLEFT",0,y); ndRow:Hide()
    -- A plain number field: the dropdown above already says "Every N days",
    -- and the bare 7 between "Every" and "days" did not read as editable
    -- (ALL-347, Dukul 2026-10-06)
    local ndEB=BNB.CreateBackdropFrame("EditBox",nil,ndRow)
    ndEB:SetSize(60,AW_ROW); ndEB:SetPoint("LEFT",ndRow,"LEFT",0,0)
    BNB.SetBackdropDark(ndEB); ndEB:SetTextInsets(6,6,0,0)
    ndEB:SetAutoFocus(false); ndEB:SetNumeric(true); ndEB:SetMaxLetters(3)
    ndEB:SetFontObject("GameFontHighlightSmall"); ndEB:SetText("7")
    ndEB:SetScript("OnEnterPressed",function(self) self:ClearFocus() end)
    ndEB:SetScript("OnEscapePressed",function(self) self:ClearFocus() end)
    ndEB:HookScript("OnTextChanged",function() MarkDirty() end)

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
    blk:SetHeight(-y)
    return { frame = blk, h = -y, dd = recurDD, wdChecks = wdChecks, ndEB = ndEB, setRecur = SetRecur }
end

-- Section: Sound, its own frame. Returns { frame, h, dd, repDD }.
local function BuildSoundBlock(ct1)
    local blk = CreateFrame("Frame",nil,ct1)
    blk:SetWidth(AW_CW)
    local y = 0
    Div(blk,y); y = y - AW_GAP
    SectionHdr(blk,L["AW_SECT_SOUND"],y); y = y - AW_LBL - 2
    -- Silent first, then Default, then custom sounds
    local sndEntries=BNB.AlarmSoundEntries()   -- Features/AlarmManager.lua SOUND_LIST
    local sDDW = AW_CW - 56
    local soundDD = MakeDD(blk,sndEntries,"default",nil,sDDW)
    soundDD:SetPoint("TOPLEFT",blk,"TOPLEFT",0,y)
    local testSnd=BNB.CreateButton(nil,blk,L["AW_TEST_BTN"],50,AW_ROW)
    testSnd:SetPoint("TOPLEFT",blk,"TOPLEFT",sDDW+6,y)
    testSnd:SetScript("OnClick",function()
        local p=SoundPath(soundDD:GetSelected()); if p then PlaySoundFile(p,"Master") end
    end)
    y = y - AW_ROW - AW_GAP

    -- How often the sound repeats while the alarm rings (alarm.soundRepeat,
    -- seconds; 0 = once; nil = every 10 s, the behaviour before ALL-136.3)
    Lbl(blk,L["AW_LBL_SOUND_REPEAT"],y); y = y - AW_LBL
    local sndRepEntries={
        {label=L["AW_SNDREP_ONCE"], value=0  },
        {label=L["AW_SNDREP_10S"],  value=10 },
        {label=L["AW_SNDREP_30S"],  value=30 },
        {label=L["AW_SNDREP_1MIN"], value=60 },
        {label=L["AW_SNDREP_5MIN"], value=300},
    }
    local soundRepDD = MakeDD(blk,sndRepEntries,SOUND_REPEAT_DEFAULT,nil)
    soundRepDD:SetPoint("TOPLEFT",blk,"TOPLEFT",0,y)
    y = y - AW_ROW - 4
    blk:SetHeight(-y)
    return { frame = blk, h = -y, dd = soundDD, repDD = soundRepDD }
end

-- Save: the Type's time and the Repeat choice into alarm (ALL-342)
local function SaveTimeAndRepeat(alarm)
    local oldTT,oldTime,oldIg=alarm.timeType or "real",alarm.time,alarm.igTime
    local tt=_timeDDCont:GetSelected() or "real"
    local kind=RESET_OF[tt]
    alarm.timeType=tt
    if kind then
        -- Rings at the reset: a due time only when it has none still ahead
        -- (new, another type before, or past)
        if tt~=oldTT or not oldTime or oldTime<=time() then
            alarm.time=BNB.Alarm.NextResetTime(kind)
        end
        alarm.igTime=nil
    elseif tt=="ingame" then
        alarm.igTime=string.format("%02d:%02d",_igTP:Get())
        -- A concrete due time, the next time the server clock reads igTime
        -- (BUG-04). Kept when only other settings changed.
        if alarm.igTime~=oldIg or oldTT~="ingame" or not oldTime then
            alarm.time=BNB.Alarm.NextInGameTime(alarm.igTime)
        end
    else
        -- Read as server time when the player chose it (ALL-104)
        local rh,rm=_realTP:Get()
        alarm.time=BNB.Time({
            year=_calYear or 2026,month=_calMonth or 1,
            day=_calSelDay or 1,
            hour=rh,
            min=rm,sec=0,
        })
        alarm.igTime=nil
    end

    if kind then
        -- recur too, so an older build still repeats a weekly one
        alarm.recur=kind; alarm.recurDays=nil; alarm.recurEvery=nil
    else
        local recur=_recurDD:GetSelected(); alarm.recur=recur
        if recur=="weekdays" then
            alarm.recurDays={}
            for _,cb in ipairs(_wdChecks) do
                if cb:GetChecked() then table.insert(alarm.recurDays,cb._dayIndex) end
            end
        elseif recur=="interval" then
            alarm.recurEvery=tonumber(_ndaysEB:GetText()) or 7
        else alarm.recurDays=nil; alarm.recurEvery=nil end
    end
    return tt, oldTT, oldTime, oldIg
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
    SectionHdr(ct1, L["AW_SECT_REMINDER"], y); y = y - AW_LBL - 2
    local labelEB = BNB.CreateBackdropFrame("EditBox",nil,ct1)
    labelEB:SetSize(AW_CW,AW_ROW); labelEB:SetPoint("TOPLEFT",ct1,"TOPLEFT",0,y)
    labelEB:SetAutoFocus(false); labelEB:SetMaxLetters(80)
    BNB.AddPlaceholder(labelEB,L["AW_REMINDER_PLACEHOLDER"])
    labelEB:SetFontObject("GameFontNormalSmall")
    labelEB:HookScript("OnTextChanged", function() MarkDirty() end)
    y = y - AW_ROW - AW_SECT_GAP
    Div(ct1,y); y = y - AW_GAP

    -- Time, Repeat and Sound: local builders above (CMP-07). Repeat and Sound
    -- sit right under the Type's own rows, and Repeat is hidden for the reset
    -- types (ALL-342)
    local TS = BuildTimeSection(ct1, y)
    local RB = BuildRepeatBlock(ct1)
    local SB = BuildSoundBlock(ct1)
    TS.relayout = function(tt)
        local reset = RESET_OF[tt] ~= nil
        local yy = TS.topY - (reset and TS.heights.reset or TS.heights[tt] or TS.heights.real)
        RB.frame:SetShown(not reset)
        if not reset then
            RB.frame:ClearAllPoints(); RB.frame:SetPoint("TOPLEFT",ct1,"TOPLEFT",0,yy)
            yy = yy - RB.h
        end
        SB.frame:ClearAllPoints(); SB.frame:SetPoint("TOPLEFT",ct1,"TOPLEFT",0,yy)
        yy = yy - SB.h
        ct1._contentH = math.abs(yy)
        if sf1._applyScrollbar then sf1._applyScrollbar() end
    end
    TS.relayout("real")
    local timeDDCont, realTP, igTP = TS.dd, TS.realTP, TS.igTP
    local SetTimeType, RefreshCalendar = TS.setType, TS.refreshCalendar
    local recurDD, wdChecks, ndEB, SetRecur = RB.dd, RB.wdChecks, RB.ndEB, RB.setRecur
    local soundDD, soundRepDD = SB.dd, SB.repDD

    -- ================================================================
    -- TAB 2: ANIMATION
    -- ================================================================
    local y2 = -4

    SectionHdr(ct2,L["AW_SECT_GLOW"],y2); y2 = y2 - AW_LBL - 2

    Lbl(ct2,L["AW_LBL_TYPE"],y2); y2 = y2 - AW_LBL
    local gtEntries={
        {label=L["AW_GLOW_DEFAULT"],  value=nil},
        {label=L["AW_GLOW_PIXEL"],    value=1  },
        {label=L["AW_GLOW_AUTOCAST"], value=2  },
        {label=L["AW_GLOW_BORDER"],   value=3  },
        {label=L["AW_GLOW_PROC"],     value=4  },
    }
    local glowTypeDD=MakeDD(ct2,gtEntries,nil,nil)
    glowTypeDD:SetPoint("TOPLEFT",ct2,"TOPLEFT",0,y2); y2 = y2 - AW_ROW - AW_GAP

    Lbl(ct2,L["AW_LBL_MODE"],y2); y2 = y2 - AW_LBL
    local gmEntries={
        {label=L["AW_GLOW_DEFAULT"],        value=nil          },
        {label=L["AW_GLOWMODE_CONTINUOUS"],     value="continuous" },
        {label=L["AW_GLOWMODE_PULSE"],    value="pulse"      },
        {label=L["AW_GLOWMODE_ONCE"],     value="once"       },
    }
    local glowModeDD=MakeDD(ct2,gmEntries,nil,nil)
    glowModeDD:SetPoint("TOPLEFT",ct2,"TOPLEFT",0,y2); y2 = y2 - AW_ROW - AW_GAP

    Lbl(ct2,L["AW_LBL_COLOR"],y2); y2 = y2 - AW_LBL
    local swatchBtn=BNB.CreateBackdropFrame("Button",nil,ct2)
    swatchBtn:SetSize(AW_ROW,AW_ROW); swatchBtn:SetPoint("TOPLEFT",ct2,"TOPLEFT",0,y2)
    local swTx=swatchBtn:CreateTexture(nil,"OVERLAY"); swTx:SetAllPoints()
    swTx:SetColorTexture(BNB_GR,BNB_GG,BNB_GB,1)
    local glowColorVal=nil

    local rstCol=BNB.CreateButton(nil,ct2,L["AW_RESET_TO_DEFAULT_BTN"],AW_CW-AW_ROW-6,AW_ROW)
    rstCol:SetPoint("TOPLEFT",ct2,"TOPLEFT",AW_ROW+6,y2)
    rstCol:SetScript("OnClick",function()
        glowColorVal=nil; swTx:SetColorTexture(BNB_GR,BNB_GG,BNB_GB,1); MarkDirty()
    end)
    swatchBtn:SetScript("OnClick",function()
        local pv=glowColorVal or {BNB_GR,BNB_GG,BNB_GB,1}
        BNB.OpenColorPicker(pv[1],pv[2],pv[3],
            function(r,g,b)
                glowColorVal={r,g,b,1}; swTx:SetColorTexture(r,g,b,1); MarkDirty()
                if f._restartPreview then f._restartPreview() end
            end,
            function()
                glowColorVal=pv; swTx:SetColorTexture(pv[1],pv[2],pv[3],1)
                if f._restartPreview then f._restartPreview() end
            end)
    end)
    y2 = y2 - AW_ROW - AW_GAP
    Div(ct2,y2); y2 = y2 - AW_GAP

    -- ── Advanced glow params — sliders, shown/hidden per type ────────────────
    -- Float params stored ×100 or ×10 internally (integer slider steps), divided on read.
    local fmtF2 = function(v) return string.format("%.2f", v/100) end  -- ×100 int → "0.25"
    local fmtF1 = function(v) return string.format("%.1f", v/10)  end  -- ×10  int → "0.5"

    -- Each slider row = one stacked slider (label, value, Reset; ALL-121) + gap
    local SL_GAP   = 10   -- gap between param rows
    local SL_ROW   = BNB.STACKED_SLIDER_H + SL_GAP

    -- Helper: one stacked slider inside a parent frame at yOff; def is also
    -- what Reset puts back.
    local function MakeParamSlider(parent, label, mn, mx, def, yOff, onChange, fmt)
        local sl = BNB.CreateStackedSlider(parent, AW_CW, {
            label = label, min = mn, max = mx, value = def, default = def,
            fmt = fmt, onChange = onChange,
        })
        sl:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, yOff)
        sl._rawVal = def
        return sl
    end

    -- Pixel params (3 rows)
    local pixelPanel = CreateFrame("Frame",nil,ct2)
    pixelPanel:SetSize(AW_CW, SL_ROW*3); pixelPanel:SetPoint("TOPLEFT",ct2,"TOPLEFT",0,y2)

    local pixelLinesSL = MakeParamSlider(pixelPanel,L["AW_PARAM_LINES"],1,20,8,0,
        function(v) pixelPanel._pixelLinesSL._rawVal=v; MarkDirty()
            if not _isPopulating and f._restartPreview then f._restartPreview() end end)
    pixelPanel._pixelLinesSL = pixelLinesSL

    local pixelFreqSL = MakeParamSlider(pixelPanel,L["AW_PARAM_FREQUENCY"],-100,100,25,-SL_ROW,
        function(v) pixelPanel._pixelFreqSL._rawVal=v; MarkDirty()
            if not _isPopulating and f._restartPreview then f._restartPreview() end end, fmtF2)
    pixelPanel._pixelFreqSL = pixelFreqSL

    local pixelLengthSL = MakeParamSlider(pixelPanel,L["AW_PARAM_LENGTH"],1,30,10,-SL_ROW*2,
        function(v) pixelPanel._pixelLengthSL._rawVal=v; MarkDirty()
            if not _isPopulating and f._restartPreview then f._restartPreview() end end)
    pixelPanel._pixelLengthSL = pixelLengthSL
    pixelPanel:Hide()

    -- AutoCast params (3 rows)
    local acPanel = CreateFrame("Frame",nil,ct2)
    acPanel:SetSize(AW_CW, SL_ROW*3); acPanel:SetPoint("TOPLEFT",ct2,"TOPLEFT",0,y2)

    local acParticlesSL = MakeParamSlider(acPanel,L["AW_PARAM_PARTICLES"],1,12,4,0,
        function(v) acPanel._acParticlesSL._rawVal=v; MarkDirty()
            if not _isPopulating and f._restartPreview then f._restartPreview() end end)
    acPanel._acParticlesSL = acParticlesSL

    local acFreqSL = MakeParamSlider(acPanel,L["AW_PARAM_FREQUENCY"],-100,100,13,-SL_ROW,
        function(v) acPanel._acFreqSL._rawVal=v; MarkDirty()
            if not _isPopulating and f._restartPreview then f._restartPreview() end end, fmtF2)
    acPanel._acFreqSL = acFreqSL

    local acScaleSL = MakeParamSlider(acPanel,L["AW_PARAM_SCALE"],5,30,10,-SL_ROW*2,
        function(v) acPanel._acScaleSL._rawVal=v; MarkDirty()
            if not _isPopulating and f._restartPreview then f._restartPreview() end end, fmtF1)
    acPanel._acScaleSL = acScaleSL
    acPanel:Hide()

    -- Border params (1 row)
    local borderPanel = CreateFrame("Frame",nil,ct2)
    borderPanel:SetSize(AW_CW, SL_ROW); borderPanel:SetPoint("TOPLEFT",ct2,"TOPLEFT",0,y2)

    local borderDurSL = MakeParamSlider(borderPanel,L["AW_PARAM_PULSE_DURATION"],10,200,70,0,
        function(v) borderPanel._borderDurSL._rawVal=v; MarkDirty()
            if not _isPopulating and f._restartPreview then f._restartPreview() end end, fmtF2)
    borderPanel._borderDurSL = borderDurSL
    borderPanel:Hide()

    -- Proc params (1 row)
    local procPanel = CreateFrame("Frame",nil,ct2)
    procPanel:SetSize(AW_CW, SL_ROW); procPanel:SetPoint("TOPLEFT",ct2,"TOPLEFT",0,y2)

    local procDurSL = MakeParamSlider(procPanel,L["AW_PARAM_DURATION"],10,500,100,0,
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
    SectionHdr(ct2,L["AW_SECT_PREVIEW"],y2); y2 = y2 - AW_LBL - 2

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
    SectionHdr(ct3,L["AW_SECT_SNOOZE"],y3); y3 = y3 - AW_LBL - 2

    local snoozeEnableCB=CreateFrame("CheckButton",nil,ct3,"UICheckButtonTemplate")
    BNB.LabelHit(snoozeEnableCB)   -- the tooltip and click reach over its label too
    snoozeEnableCB:SetPoint("TOPLEFT",ct3,"TOPLEFT",0,y3+2)
    snoozeEnableCB:SetChecked(true)
    snoozeEnableCB:HookScript("OnClick",function() MarkDirty() end)
    local snoozeEnableLbl=ct3:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
    snoozeEnableLbl:SetPoint("LEFT",snoozeEnableCB,"RIGHT",2,0)
    snoozeEnableLbl:SetText(L["AW_ENABLE_SNOOZE"])
    snoozeEnableLbl:SetTextColor(0.85,0.85,0.85,1)
    BNB.CheckTip(snoozeEnableCB, L["AW_ENABLE_SNOOZE_TIP"])
    y3 = y3 - 28 - AW_GAP

    Lbl(ct3,L["AW_LBL_INTERVAL"],y3); y3 = y3 - AW_LBL
    local snzEntries={
        {label=L["AW_SNZ_1MIN"],  value=1 },
        {label=L["AW_SNZ_5MIN"], value=5 },
        {label=L["AW_SNZ_10MIN"],value=10},
        {label=L["AW_SNZ_15MIN"],value=15},
        {label=L["AW_SNZ_30MIN"],value=30},
        {label=L["AW_SNZ_60MIN"],value=60},
    }
    local snoozeIntervalDD=MakeDD(ct3,snzEntries,5,nil)
    snoozeIntervalDD:SetPoint("TOPLEFT",ct3,"TOPLEFT",0,y3); y3 = y3 - AW_ROW - AW_GAP

    Lbl(ct3,L["AW_SECT_REPEAT"],y3); y3 = y3 - AW_LBL
    local snzRepEntries={
        {label=L["AW_REP_1TIME"],  value=1},
        {label=L["AW_REP_3TIMES"], value=3},
        {label=L["AW_REP_5TIMES"], value=5},
        {label=L["AW_REP_FOREVER"], value=0},
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
    SectionHdr(ct3,L["AW_SECT_ON_FIRE"],y3); y3 = y3 - AW_LBL - 2
    local fmEntries={
        {label=L["AW_FIRE_POPUP"],          value="popup"    },
        {label=L["AW_FIRE_STICKY"],               value="sticky"   },
        {label=L["AW_FIRE_MINIMIZED"],value="minimized"},
    }
    local fireModeDD=MakeDD(ct3,fmEntries,"popup",nil)
    fireModeDD:SetPoint("TOPLEFT",ct3,"TOPLEFT",0,y3); y3 = y3 - AW_ROW - AW_SECT_GAP

    Div(ct3,y3); y3 = y3 - AW_GAP

    -- Section: Combat
    SectionHdr(ct3,L["AW_SECT_COMBAT"],y3); y3 = y3 - AW_LBL - 2

    Lbl(ct3,L["AW_LBL_DURING_COMBAT"],y3); y3 = y3 - AW_LBL
    local cbtEntries={
        {label=L["AW_COMBAT_FIRE"],       value="fire" },
        {label=L["AW_COMBAT_QUEUE"], value="queue"},
    }
    local combatDD=MakeDD(ct3,cbtEntries,"queue",nil)
    combatDD:SetPoint("TOPLEFT",ct3,"TOPLEFT",0,y3); y3 = y3 - AW_ROW - AW_GAP

    Lbl(ct3,L["AW_LBL_AFTER_COMBAT"],y3); y3 = y3 - AW_LBL
    local pstEntries={
        {label=L["AW_POST_IMMEDIATE"],value="immediate"},
        {label=L["AW_POST_SUMMARY"],    value="summary"  },
        {label=L["AW_POST_CHAT"],  value="chat"     },
    }
    local postDD=MakeDD(ct3,pstEntries,"immediate",nil)
    postDD:SetPoint("TOPLEFT",ct3,"TOPLEFT",0,y3); y3 = y3 - AW_ROW - AW_GAP
    ct3._contentH=math.abs(y3)

    -- ── STORE REFS ────────────────────────────────────────────────────────────
    _labelEB         = labelEB
    _timeDDCont      = timeDDCont
    _igTP            = igTP
    _realTP          = realTP
    _recurDD         = recurDD
    _wdChecks        = wdChecks
    _ndaysEB         = ndEB
    _soundDD         = soundDD
    _soundRepDD      = soundRepDD
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

        local tt, oldTT, oldTime, oldIg = SaveTimeAndRepeat(alarm)

        alarm.sound         = soundDD:GetSelected()
        local rep = soundRepDD:GetSelected()
        alarm.soundRepeat   = (rep ~= SOUND_REPEAT_DEFAULT) and rep or nil
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
        -- A new time re-arms the alarm: an alarm that had fired stayed fired
        -- after being moved to a future time (ALL-136.3). A stale snooze would
        -- override the new time, so it goes too.
        local moved = tt~=oldTT or (tt=="ingame" and alarm.igTime~=oldIg)
                      or (tt~="ingame" and alarm.time~=oldTime)
        if moved then
            alarm.snoozedUntil = nil
            if alarm.time and alarm.time > time() then alarm.fired = false end
        end

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

    -- A reset alarm shows as its Type, also the old Repeat = weekly reset shape (ALL-342)
    local resetKind = BNB.Alarm.ResetKind(alarm)
    local tt = resetKind and (resetKind .. "reset") or alarm.timeType or "real"
    _timeDDCont:SetSelected(tt); f._setTimeType(tt)

    -- Always set calendar to today (or alarm date if editing)
    local t = BNB.Date("*t", alarm.time)
    f._setCalDate(t.year, t.month, t.day)
    -- Always reset hour/min — explicit default 9:00 for new alarms
    -- A new alarm starts at the current time, in the clock the field uses
    -- (local, or server with "use server time"); an existing one at its own
    _realTP:Layout(); _igTP:Layout()   -- follows the 12/24-hour setting
    _realTP:Set(t.hour, t.min)
    -- Always reset in-game time dropdowns
    if alarm.igTime then
        local h,m=alarm.igTime:match("^(%d+):(%d+)$")
        if h then
            _igTP:Set(tonumber(h), tonumber(m))
        end
    else
        -- New in-game alarm: the current server time
        local sh, sm = GetGameTime()
        _igTP:Set(sh or 9, sm or 0)
    end

    local recur = (not resetKind) and alarm.recur or nil
    _recurDD:SetSelected(recur); f._setRecur(recur)
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
    _soundRepDD:SetSelected(alarm.soundRepeat or SOUND_REPEAT_DEFAULT)
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
    if _fireModeDD then
        _fireModeDD:SetSelected(alarm.fireMode or "popup")
        -- Sticky Notes off (ALL-343): every alarm rings as a popup, the
        -- saved mode is kept for when the module is back on
        local on = BNB.StickiesEnabled()
        if _fireModeDD._dd then _fireModeDD._dd:SetEnabled(on) end
        _fireModeDD:SetAlpha(on and 1 or 0.45)
    end

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
    if _saveBtn then _saveBtn:SetEnabled(not hasExisting) end
    if _delBtn then
        _delBtn:SetText(hasExisting and L["AW_REMOVE_ALARM_BTN"] or L["CANCEL"])
        local fs = _delBtn:GetFontString()
        if hasExisting then fs:SetTextColor(0.9, 0.4, 0.4, 1)
        else fs:SetTextColor(unpack(_delBtn._plainColor)) end
    end
    _isPopulating = false
end

-- ---------------------------------------------------------------------------
-- OPEN HELPERS
-- ---------------------------------------------------------------------------
local function DoOpen(noteID, anchorFrame, stickyFrame)
    if not _frame then
        BuildTabContent(BuildWindow())
    end
    local f = _frame

    local ss = _G["BigNoteBoxStickySettingsFrame"]
    if ss and ss:IsShown() then
        if BNB.Sticky and BNB.Sticky.CloseSettings then BNB.Sticky.CloseSettings()
        else ss:Hide() end
    end

    _noteID = noteID
    Populate(noteID)
    if f._selectTab then f._selectTab(1) end  -- always open on General tab
    f:Show(); f:Raise()
    return f
end

-- ---------------------------------------------------------------------------
-- PUBLIC API
-- ---------------------------------------------------------------------------
-- Both refuse while the Alarms module is off (ALL-343): a way in that was
-- missed when the module was gated still opens nothing
function AW.Open(noteID, anchorFrame, stickyFrame)
    if not noteID or not BNB.AlarmsEnabled() then return end
    local f = DoOpen(noteID, anchorFrame, stickyFrame)
    BNB.PlaceBeside(f, stickyFrame or anchorFrame, AW_W)
end

function AW.OpenLeftOfMain(noteID)
    if not noteID or not BNB.AlarmsEnabled() then return end
    local f = DoOpen(noteID, nil, nil)
    f:ClearAllPoints()
    local mf = BNB.mainFrame
    -- Exactly where Note Settings opens (NoteConfig.lua: TOPRIGHT, -8, 0)
    if mf then f:SetPoint("TOPRIGHT",mf,"TOPLEFT",-8,0)
    else       f:SetPoint("CENTER",UIParent,"CENTER",0,60) end
end

function AW.Close()
    if _frame then _frame:Hide() end
    _noteID = nil
end

function AW.IsOpen()    return _frame and _frame:IsShown() end
function AW.GetNoteID() return _noteID end

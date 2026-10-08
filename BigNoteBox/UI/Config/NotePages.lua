-- BigNoteBox UI/Config/NotePages.lua - Modules sub-pages for parts of how notes
-- work: Rich Notes (with Live Preview), Note History, Trash and Alarms. Moved
-- off the Notes and General tabs (ALL-290, Dukul 2026-10-05). Listed on the
-- Modules tab (UI/Config/Modules.lua), built by K.NewSubPage; open one from
-- outside with BNB.OpenSettingsPage("modules", "richNotes" | "history" |
-- "trash" | "alarms" | "placement"). Window placement (ALL-291) holds a copy
-- of every placement setting; the originals stay where they are.

local BNB = BigNoteBox
local L   = BNB.L

local K = BNB._ConfigKit
local CONTENT_W, ROW_H, ROW_GAP, SLIDER_H = K.CONTENT_W, K.ROW_H, K.ROW_GAP, K.SLIDER_H
local AddRule, AddHeader, AddCheck, MakeKeybindRow = K.AddRule, K.AddHeader, K.AddCheck, K.MakeKeybindRow

-- ─────────────────────────────────────────────────────────────────────────────
-- RICH NOTES: new-note default, open in editor, heading sizes, live preview
-- ─────────────────────────────────────────────────────────────────────────────
function K.BuildRichNotesPage(sf, ct, y, page)
    local db = BigNoteBoxDB

    -- Module switch (ALL-343). Applies live: off shows every note as plain
    -- text with its markup visible and hides every way to make a rich note;
    -- the notes stay rich and render again when it is switched back on.
    local enableCb
    y, enableCb = AddCheck(ct, y, L["CFG_RICH_ENABLE_LABEL"],
        function() return BNB.RichEnabled() end,
        function(v)
            if not BigNoteBoxDB then return end
            BigNoteBoxDB.richEnabled = v
            if BNB.ApplyRichModule then BNB.ApplyRichModule(v) end
        end,
        L["CFG_RICH_ENABLE_TIP"])
    page.enableCb = enableCb   -- twin on the Modules overview row

    -- Moved from Features tab: new-note default + open-in-editor behaviours
    y = AddCheck(ct, y, L["CFG_RICH_NOTES_DEFAULT"],
        function() return db.newNotesRichByDefault == true end,
        function(v) db.newNotesRichByDefault = v end,
        L["CFG_RICH_NOTES_DEFAULT_TIP"])

    y = AddCheck(ct, y, L["CFG_RICH_OPEN_EDITOR"],
        function() return db.richOpenInEditor == true end,
        function(v) db.richOpenInEditor = v end,
        L["CFG_RICH_OPEN_EDITOR_TIP"])

    y = MakeKeybindRow(ct, y, L["CFG_KB_TOGGLE_RV"], "BIGNOTEBOXTOGGLERV", L["CFG_KB_HINT_NONE"], L["CFG_KB_TOGGLE_RV_TIP"])

    -- ── Heading sizes ─────────────────────────────────────────────────────────
    -- Helper: trigger a live re-render of the currently open rich note preview.
    local function TriggerRichRerender()
        if BNB.RichPreview and BNB.RichPreview.ScheduleRender then
            BNB.RichPreview.ScheduleRender()
        end
        if BNB.RichPreviewFocus and BNB.RichPreviewFocus.ScheduleRefresh then
            BNB.RichPreviewFocus.ScheduleRefresh()
        end
    end

    -- Helper: what each size would be in multiplier mode (used for greyed display).
    local function MultiplierSize(mult)
        local base = (db and db.fontSize) or BNB.DEFAULTS.fontSize
        return math.floor(base * mult + 0.5)
    end

    local indepActive = db and db.richIndependentSizes == true
    local sizeSliders = {}

    local function SetSlidersEnabled(enabled)
        for _, sl in ipairs(sizeSliders) do
            sl:SetAlpha(enabled and 1.0 or 0.4)
            sl:SetEnabled(enabled)
        end
    end

    -- Checkbox first so it sits above the sliders in the layout flow.
    local indepCb = CreateFrame("CheckButton", nil, ct, "UICheckButtonTemplate")
    BNB.LabelHit(indepCb)   -- the tooltip and click reach over its label too
    indepCb:SetSize(24, 24)
    indepCb:SetPoint("TOPLEFT", ct, "TOPLEFT", -2, y + 2)
    indepCb:SetChecked(indepActive)
    local indepLbl = ct:CreateFontString(nil, "OVERLAY", "BNBFontNormal")
    indepLbl:SetPoint("LEFT",  indepCb, "RIGHT", 4, 0)
    indepLbl:SetPoint("RIGHT", ct,      "RIGHT", 0, 0)
    indepLbl:SetJustifyH("LEFT"); indepLbl:SetHeight(ROW_H)
    indepLbl:SetText(L["CFG_RICH_SIZES_INDEPENDENT"])
    indepCb:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(L["CFG_RICH_SIZES_IND_TIP"], 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    indepCb:SetScript("OnLeave", function() GameTooltip:Hide() end)
    y = y - (ROW_H + ROW_GAP)

    -- Four size sliders — built after checkbox so indepCb is in scope for OnClick.
    local h1sl, h2sl, h3sl, psl

    local function MakeSizeSlider(label, dbKey, default, mult)
        -- In multiplier mode show the derived value so the user sees what they'd take over.
        local initVal = indepActive
            and (db and db[dbKey] or default)
            or  MultiplierSize(mult)
        local sl = BNB.CreateStackedSlider(ct, CONTENT_W, {
            label = label, min = 6, max = 72, value = initVal, default = default,
            onChange = function(v)
                if not (db and db.richIndependentSizes) then return end
                if db then db[dbKey] = v end
                TriggerRichRerender()
            end,
        })
        sl:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
        sizeSliders[#sizeSliders + 1] = sl
        return sl
    end

    h1sl = MakeSizeSlider(L["CFG_RICH_SIZE_H1"], "richH1Size",   BNB.DEFAULTS.richH1Size,   2.0); y = y - (SLIDER_H + ROW_GAP)
    h2sl = MakeSizeSlider(L["CFG_RICH_SIZE_H2"], "richH2Size",   BNB.DEFAULTS.richH2Size,   1.6); y = y - (SLIDER_H + ROW_GAP)
    h3sl = MakeSizeSlider(L["CFG_RICH_SIZE_H3"], "richH3Size",   BNB.DEFAULTS.richH3Size,   1.3); y = y - (SLIDER_H + ROW_GAP)
    psl  = MakeSizeSlider(L["CFG_RICH_SIZE_P"],  "richBodySize", BNB.DEFAULTS.richBodySize, 1.0); y = y - (SLIDER_H + ROW_GAP)

    -- Wire checkbox OnClick now that all slider locals are defined.
    indepCb:SetScript("OnClick", function(self)
        local on = self:GetChecked() and true or false
        if db then db.richIndependentSizes = on end
        SetSlidersEnabled(on)
        if on then
            -- Snap to stored DB values (or defaults) when switching on
            h1sl:SetValue(db and db.richH1Size   or 25)
            h2sl:SetValue(db and db.richH2Size   or 20)
            h3sl:SetValue(db and db.richH3Size   or 16)
            psl:SetValue( db and db.richBodySize or BNB.DEFAULTS.richBodySize)
        else
            -- Show multiplier ghost values when switching off
            h1sl:SetValue(MultiplierSize(2.0), true)
            h2sl:SetValue(MultiplierSize(1.6), true)
            h3sl:SetValue(MultiplierSize(1.3), true)
            psl:SetValue( MultiplierSize(1.0), true)
            TriggerRichRerender()
        end
    end)

    SetSlidersEnabled(indepActive)

    -- ── Live Preview ─────────────────────────────────────────────────────────
    AddRule(ct, y); y = y - 18
    y = AddHeader(ct, y, L["CFG_HDR_LIVE_PREVIEW"])

    do
        local lpDesc = ct:CreateFontString(nil, "OVERLAY", "BNBFontNormalSmall")
        lpDesc:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
        lpDesc:SetWidth(CONTENT_W); lpDesc:SetJustifyH("LEFT")
        lpDesc:SetWordWrap(true); lpDesc:SetHeight(28)
        lpDesc:SetTextColor(0.60, 0.60, 0.60)
        lpDesc:SetText(L["CFG_PREVIEW_DESC"])
        y = y - 32
    end

    y = AddCheck(ct, y, L["CFG_RICH_PREVIEW_AUTO"],
        function() return db.richPreviewAutoShow ~= false end,
        function(v) db.richPreviewAutoShow = v end,
        L["CFG_RICH_PREVIEW_AUTO_TIP"])

    -- Which side the rich preview opens on (ALL-269)
    y = K.AddSideRow(ct, y, L["CFG_SIDE_PREVIEW"], "richPreviewSide", "BigNoteBoxRichPreviewFrame")

    y = AddCheck(ct, y, L["CFG_FOCUS_PREVIEW_ALWAYS"],
        function() return db.focusPreviewAlwaysShow ~= false end,
        function(v)
            if BigNoteBoxDB then BigNoteBoxDB.focusPreviewAlwaysShow = v end
        end,
        L["CFG_FOCUS_PREVIEW_ALWAYS_TIP"])

    do
        local dlDesc = ct:CreateFontString(nil, "OVERLAY", "BNBFontNormalSmall")
        dlDesc:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
        dlDesc:SetWidth(CONTENT_W); dlDesc:SetJustifyH("LEFT")
        dlDesc:SetWordWrap(true)
        dlDesc:SetTextColor(0.55, 0.55, 0.55)
        dlDesc:SetText(L["CFG_PREVIEW_DELAY_DESC"])
        local h = dlDesc:GetStringHeight() + 4
        dlDesc:SetHeight(h); y = y - h - 2
    end

    local curDebounce = db and db.previewDebounce or BNB.DEFAULTS.previewDebounce
    local debounceSlider = BNB.CreateStackedSlider(ct, CONTENT_W, {
        label = L["CFG_PREVIEW_DELAY_SLIDER"], min = 1, max = 10,
        value = math.floor(curDebounce * 10 + 0.5), default = math.floor(BNB.DEFAULTS.previewDebounce * 10 + 0.5),
        fmt = function(v) return string.format("%.1f", v / 10) end,
        onChange = function(v)
            local val = v / 10
            if BigNoteBoxDB then BigNoteBoxDB.previewDebounce = val end
        end,
        tipTitle = L["CFG_PREVIEW_DELAY_TIP_TITLE"],
        tip = { L["CFG_PREVIEW_DELAY_TIP1"], L["CFG_PREVIEW_DELAY_TIP2"] },
    })
    debounceSlider:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
    y = y - (SLIDER_H + ROW_GAP)

    sf:FinaliseHeight(math.abs(y) + 12)
end

-- ─────────────────────────────────────────────────────────────────────────────
-- NOTE HISTORY: session snapshots (undo / redo stays on the Notes tab)
-- ─────────────────────────────────────────────────────────────────────────────
function K.BuildHistoryPage(sf, ct, y, page)
    -- Module switch (ALL-343). Applies live: off hides every way in and takes
    -- no logout snapshots; the snapshots already taken stay on their notes.
    local enableCb
    y, enableCb = AddCheck(ct, y, L["CFG_HISTORY_ENABLE_LABEL"],
        function() return BNB.HistoryEnabled() end,
        function(v)
            if not BigNoteBoxDB then return end
            BigNoteBoxDB.historyEnabled = v
            if BNB.ApplyHistoryModule then BNB.ApplyHistoryModule(v) end
        end,
        L["CFG_HISTORY_ENABLE_TIP"])
    page.enableCb = enableCb   -- twin on the Modules overview row

    local histDesc = ct:CreateFontString(nil, "OVERLAY", "BNBFontNormalSmall")
    histDesc:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
    histDesc:SetWidth(CONTENT_W); histDesc:SetJustifyH("LEFT")
    histDesc:SetWordWrap(true); histDesc:SetHeight(28)
    histDesc:SetTextColor(0.60, 0.60, 0.60)
    histDesc:SetText(L["CFG_AUTOSAVE_HIST_DESC"])
    y = y - 32

    -- Which side Note History opens on (ALL-269)
    y = K.AddSideRow(ct, y, L["CFG_SIDE_HISTORY"], "historySide", "BigNoteBoxHistoryFrame")

    -- History slots slider
    local curSlots = BigNoteBoxDB and BigNoteBoxDB.historyMaxSlots or BNB.DEFAULTS.historyMaxSlots
    local slotsSlider = BNB.CreateStackedSlider(ct, CONTENT_W, {
        label = L["CFG_AUTOSAVE_SLOTS_TIP_TITLE"], min = 1, max = 20,
        value = curSlots, default = BNB.DEFAULTS.historyMaxSlots,
        onChange = function(v)
            if BigNoteBoxDB then BigNoteBoxDB.historyMaxSlots = v end
        end,
        tipTitle = L["CFG_AUTOSAVE_SLOTS_TIP_TITLE"],
        tip = { L["CFG_AUTOSAVE_SLOTS_TIP1"], L["CFG_AUTOSAVE_SLOTS_TIP2"], L["CFG_AUTOSAVE_SLOTS_TIP3"] },
    })
    slotsSlider:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
    y = y - (SLIDER_H + ROW_GAP)

    -- Size readout — computed when the tab is shown
    local histSizeLbl = ct:CreateFontString(nil, "OVERLAY", "BNBFontNormalSmall")
    histSizeLbl:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
    histSizeLbl:SetWidth(CONTENT_W); histSizeLbl:SetJustifyH("LEFT")
    histSizeLbl:SetHeight(20)
    histSizeLbl:SetTextColor(0.45, 0.45, 0.45)
    histSizeLbl:SetText(L["CFG_AUTOSAVE_HISTSIZE_CALC"])
    y = y - 24

    -- Refresh size label when the page becomes visible
    sf:HookScript("OnShow", function()
        if BNB.HistoryTotalSize then
            local bytes = BNB.HistoryTotalSize()
            local ndb   = BNB.NotesDB()
            local noteCount = 0
            if ndb and ndb.notes then
                for id in pairs(ndb.notes) do
                    if BNB.HistoryNoteHasAny and BNB.HistoryNoteHasAny(id) then
                        noteCount = noteCount + 1
                    end
                end
            end
            local sizeStr = BNB.HistoryFormatSize and BNB.HistoryFormatSize(bytes)
                or string.format(L["CFG_UNIT_KB_FMT"], math.floor(bytes / 1024))
            histSizeLbl:SetText(string.format(
                L["CFG_AUTOSAVE_HISTSIZE_FMT"],
                sizeStr, noteCount))
        end
    end)

    sf:FinaliseHeight(math.abs(y) + 12)
end

-- ─────────────────────────────────────────────────────────────────────────────
-- TRASH: the checkbox is the page's master switch (twin on the overview row)
-- ─────────────────────────────────────────────────────────────────────────────
function K.BuildTrashPage(sf, ct, y, page)
    local db = BigNoteBoxDB
    -- ── Trash enable/disable checkbox ─────────────────────────────────────────
    -- Capture all child widget refs so we can grey them out when disabled.
    local trashEnableCb = CreateFrame("CheckButton", nil, ct, "UICheckButtonTemplate")
    BNB.LabelHit(trashEnableCb)   -- the tooltip and click reach over its label too
    trashEnableCb:SetSize(24, 24)
    trashEnableCb:SetPoint("TOPLEFT", ct, "TOPLEFT", -2, y + 2)
    trashEnableCb:SetChecked(db.trashFeature ~= false)
    local trashEnableLbl = ct:CreateFontString(nil, "OVERLAY", "BNBFontNormal")
    trashEnableLbl:SetPoint("LEFT",  trashEnableCb, "RIGHT", 4, 0)
    trashEnableLbl:SetPoint("RIGHT", ct, "RIGHT", 0, 0)
    trashEnableLbl:SetJustifyH("LEFT"); trashEnableLbl:SetHeight(ROW_H)
    trashEnableLbl:SetText(L["CFG_TRASH_ENABLE_LABEL"])
    BNB.CheckTip(trashEnableCb, L["CFG_TRASH_ENABLE_TIP"])
    page.enableCb = trashEnableCb   -- twin on the Modules overview row
    y = y - (ROW_H + ROW_GAP)

    -- ── Warn before deleting checkbox ─────────────────────────────────────────
    local warnCb = CreateFrame("CheckButton", nil, ct, "UICheckButtonTemplate")
    BNB.LabelHit(warnCb)   -- the tooltip and click reach over its label too
    warnCb:SetSize(24, 24)
    warnCb:SetPoint("TOPLEFT", ct, "TOPLEFT", -2, y + 2)
    warnCb:SetChecked(db.warnBeforeDelete ~= false)
    warnCb:SetScript("OnClick", function(self)
        db.warnBeforeDelete = self:GetChecked() and true or false
    end)
    warnCb:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(L["CFG_TRASH_WARN_TIP"], 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    warnCb:SetScript("OnLeave", function() GameTooltip:Hide() end)
    local warnLbl = ct:CreateFontString(nil, "OVERLAY", "BNBFontNormal")
    warnLbl:SetPoint("LEFT",  warnCb, "RIGHT", 4, 0)
    warnLbl:SetPoint("RIGHT", ct, "RIGHT", 0, 0)
    warnLbl:SetJustifyH("LEFT"); warnLbl:SetHeight(ROW_H)
    warnLbl:SetText(L["CFG_TRASH_WARN_LABEL"])
    y = y - (ROW_H + ROW_GAP)

    -- ── Retention slider ───────────────────────────────────────────────────────
    local retainSlider = BNB.CreateStackedSlider(ct, CONTENT_W, {
        label = L["CFG_TRASH_RETAIN_SLIDER"], min = 0, max = 90,
        value = db.trashRetainDays or BNB.DEFAULTS.trashRetainDays, default = BNB.DEFAULTS.trashRetainDays,
        onChange = function(v) db.trashRetainDays = v end,
        tip = L["CFG_TRASH_RETAIN_TIP"],
    })
    retainSlider:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
    y = y - (SLIDER_H + ROW_GAP)

    -- Which side the Trash window opens on (ALL-269)
    local trashSideDD
    y, trashSideDD = K.AddSideRow(ct, y, L["CFG_SIDE_TRASH"], "trashSide", "BigNoteBoxTrashFrame")

    -- ── Apply greying / trash button visibility ────────────────────────────────
    local function ApplyTrashSection(enabled)
        local a = enabled and 1 or 0.35
        warnCb:SetEnabled(enabled)
        warnCb:SetAlpha(a)
        warnLbl:SetAlpha(a)
        retainSlider:SetAlpha(a)
        retainSlider:SetEnabled(enabled)
        trashSideDD:SetAlpha(a); trashSideDD._lbl:SetAlpha(a)
        if trashSideDD._dd then trashSideDD._dd:SetEnabled(enabled) end
        -- Show/hide the trashcan icon in the main window toolbar; the row
        -- closes up so no gap is left (reads db.trashFeature, set by the caller)
        if BNB.ApplyToolbarIcons then BNB.ApplyToolbarIcons() end
        -- Close the trash window if it's open and we're disabling
        if not enabled and BNB.ToggleTrashWindow then
            local tf = _G["BigNoteBoxTrashFrame"]
            if tf and tf:IsShown() then tf:Hide() end
        end
    end

    trashEnableCb:SetScript("OnClick", function(self)
        local v = self:GetChecked() and true or false
        db.trashFeature = v
        ApplyTrashSection(v)
    end)

    -- Apply immediately (handles saved state on config open)
    ApplyTrashSection(db.trashFeature ~= false)

    sf:FinaliseHeight(math.abs(y) + 12)
end

-- ─────────────────────────────────────────────────────────────────────────────
-- ALARMS: the module switch and the window side; defaults for new alarms
-- come with ALL-292 (BigNoteBoxDB.alarmDefaults has no settings yet)
-- ─────────────────────────────────────────────────────────────────────────────
function K.BuildAlarmsPage(sf, ct, y, page)
    -- Module switch (ALL-343). Applies live: off hides every way in and no
    -- alarm rings; the alarms stay on their notes (BNB.Alarm.ApplyModule).
    local enableCb, sideDD, showLbl, showDD
    local function ApplyAlarmsSection(on)
        local a = on and 1 or 0.35
        sideDD:SetAlpha(a); sideDD._lbl:SetAlpha(a)
        if sideDD._dd then sideDD._dd:SetEnabled(on) end
        showLbl:SetAlpha(a); showDD:SetAlpha(a)
        if showDD._dd then showDD._dd:SetEnabled(on) end
    end
    y, enableCb = AddCheck(ct, y, L["CFG_ALARMS_ENABLE_LABEL"],
        function() return BNB.AlarmsEnabled() end,
        function(v)
            if not BigNoteBoxDB then return end
            BigNoteBoxDB.alarmsEnabled = v
            if BNB.Alarm and BNB.Alarm.ApplyModule then BNB.Alarm.ApplyModule(v) end
            ApplyAlarmsSection(v)
        end,
        L["CFG_ALARMS_ENABLE_TIP"])
    page.enableCb = enableCb   -- twin on the Modules overview row

    -- Which side the Alarms window opens on (ALL-269)
    y, sideDD = K.AddSideRow(ct, y, L["CFG_SIDE_ALARMS"], "alarmsSide", "BNBAlarmOverviewFrame")

    -- Alarm window or toast (ALL-385): BigNoteBoxDB.alarmDisplay nil = the
    -- window, "toast". Only for alarms whose fire mode is Popup; missed alarms
    -- are toasts either way (Features/AlarmManager.lua)
    showLbl = ct:CreateFontString(nil, "OVERLAY", "BNBFontNormal")
    showLbl:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
    showLbl:SetHeight(K.ROW_H); showLbl:SetJustifyH("LEFT")
    showLbl:SetText(L["CFG_ALARM_SHOW_AS"])
    y = y - (K.ROW_H + 2)
    showDD = BNB.CreateValueDropdown(ct, {
            { label = L["CFG_ALARM_SHOW_WINDOW"], value = "window" },
            { label = L["CFG_ALARM_SHOW_TOAST"],  value = "toast" },
        }, BigNoteBoxDB and BigNoteBoxDB.alarmDisplay == "toast" and "toast" or "window",
        function(v)
            if not BigNoteBoxDB then return end
            if v == "toast" then BigNoteBoxDB.alarmDisplay = "toast" else BigNoteBoxDB.alarmDisplay = nil end
        end, K.CONTENT_W, 26)
    showDD:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
    local tipOwner = showDD._dd or showDD
    tipOwner:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(L["CFG_ALARM_SHOW_AS"], 1, 1, 1)
        GameTooltip:AddLine(L["CFG_ALARM_SHOW_TIP"], 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    tipOwner:HookScript("OnLeave", function() GameTooltip:Hide() end)
    y = y - (32 + K.ROW_GAP)

    ApplyAlarmsSection(BNB.AlarmsEnabled())
    sf:FinaliseHeight(math.abs(y) + 12)
end

-- ─────────────────────────────────────────────────────────────────────────────
-- WINDOW PLACEMENT (ALL-291, Dukul 2026-10-05): a copy of every placement
-- setting in one place. The originals stay on their own pages; both write the
-- same saved key, and every row re-reads it when its page shows (AddSideRow,
-- K.ReadOnShow), so the two never disagree. A new placement setting gets a
-- row here too. The character sidebar's side is left out: it is part of the
-- main window, not a window.
-- ─────────────────────────────────────────────────────────────────────────────
function K.BuildPlacementPage(sf, ct, y)
    local db = BigNoteBoxDB
    local cb

    -- Main window: applied at login / reload (Core/Initialize.lua 5b, ALL-270);
    -- nil = off. Only here since 2026-10-06 (was also on General > Window)
    y = AddHeader(ct, y, L["CFG_PLACE_HDR_MAIN"])
    local function ResetPos() return db.resetWindowPosOnLoad == true end
    y, cb = AddCheck(ct, y, L["CFG_CHK_RESET_WIN_POS_LABEL"], ResetPos,
        function(v) db.resetWindowPosOnLoad = v or nil end,
        L["CFG_CHK_RESET_WIN_POS_TIP"])
    K.ReadOnShow(cb, ResetPos)
    local function ResetSize() return db.resetWindowSizeOnLoad == true end
    y, cb = AddCheck(ct, y, L["CFG_CHK_RESET_WIN_SIZE_LABEL"], ResetSize,
        function(v) db.resetWindowSizeOnLoad = v or nil end,
        L["CFG_CHK_RESET_WIN_SIZE_TIP"])
    K.ReadOnShow(cb, ResetSize)

    -- Windows beside the main window (each also on its own page; the Tag
    -- Manager on Notes, the Reference Box on its Modules page)
    y = AddRule(ct, y) - 4
    y = AddHeader(ct, y, L["CFG_PLACE_HDR_SIDES"])
    y = K.AddSideRow(ct, y, L["CFG_SIDE_HISTORY"], "historySide",     "BigNoteBoxHistoryFrame")
    y = K.AddSideRow(ct, y, L["CFG_SIDE_TRASH"],   "trashSide",       "BigNoteBoxTrashFrame")
    y = K.AddSideRow(ct, y, L["CFG_SIDE_ALARMS"],  "alarmsSide",      "BNBAlarmOverviewFrame")
    y = K.AddSideRow(ct, y, L["CFG_SIDE_TAGMGR"],  "tagManagerSide",  "BigNoteBoxTagManagerFrame")
    y = K.AddSideRow(ct, y, L["CFG_SIDE_PREVIEW"], "richPreviewSide", "BigNoteBoxRichPreviewFrame")
    y = K.AddSideRow(ct, y, L["CFG_SIDE_REFBOX"],  "refboxSide",      nil, K.ApplyRefboxSide)

    -- Things placed by dragging: the same buttons as on their pages
    y = AddRule(ct, y) - 4
    y = AddHeader(ct, y, L["CFG_PLACE_HDR_SCREEN"])
    local function PlaceButton(text, tip, onClick)
        local btn = BNB.CreateButton(nil, ct, text, 200, 22)
        btn:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
        btn:SetScript("OnClick", onClick)
        btn:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(tip, 0.8, 0.8, 0.8, true)
            GameTooltip:Show()
        end)
        btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
        y = y - (22 + 6)
        return btn
    end
    -- Toasts (Modules > Toasts, ALL-384): greyed while the module is off
    K.GreyWhileOff(PlaceButton(L["CFG_TOAST_ANCHOR_BTN"], L["CFG_TOAST_ANCHOR_TIP"], function()
        BNB.Toast.ToggleAnchor()
    end), function() return BNB.ToastsEnabled() end)
    -- The search bar (Modules > Oracle Search)
    PlaceButton(L["CFG_PLACE_ORACLE_RESET"], L["CFG_ORACLE_RESET_TIP"], function()
        if BNB.Oracle and BNB.Oracle.ResetPosition then BNB.Oracle.ResetPosition() end
    end)

    sf:FinaliseHeight(math.abs(y) + 12)
end

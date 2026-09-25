-- BigNoteBox UI/Config/Editor.lua - Settings Editor tab
-- Split out of ConfigWindow.lua (ALL-65.10).

local BNB = BigNoteBox
local L   = BNB.L

local K = BNB._ConfigKit
local CONTENT_W, ROW_H, ROW_GAP, SLIDER_H = K.CONTENT_W, K.ROW_H, K.ROW_GAP, K.SLIDER_H
local AddRule, AddHeader, AddCheck, MakeKeybindRow = K.AddRule, K.AddHeader, K.AddCheck, K.MakeKeybindRow

-- ─────────────────────────────────────────────────────────────────────────────
-- TAB 4 (new) -- EDITOR
-- Undo/redo depth + WYSIWYG toolbar toggle.
-- ─────────────────────────────────────────────────────────────────────────────
local function BuildEditorTab(sf, ct)
    local db = BigNoteBoxDB
    local y  = -8

    -- ── Saving ───────────────────────────────────────────────────────────────
    -- Save mode (ALL-52): nil = automatic, "manual" = Save button. First in
    -- the tab because it changes how the whole editor works (Dukul, 2026-09-24).
    -- Automatic uses the idle delay / forced interval under Undo / Redo.
    y = AddHeader(ct, y, L["CFG_HDR_SAVING"])
    y = AddCheck(ct, y, L["CFG_CHK_AUTOSAVE_LABEL"],
        function() return db.saveMode ~= "manual" end,
        function(v)
            if v then db.saveMode = nil else db.saveMode = "manual" end
            -- Switching to automatic saves what is pending right away
            if v and BNB.SaveCurrentNoteQuiet then BNB.SaveCurrentNoteQuiet() end
            if BNB.ApplySaveMode then BNB.ApplySaveMode() end
        end,
        L["CFG_CHK_AUTOSAVE_TIP"])

    -- ── Formatting Toolbar ────────────────────────────────────────────────────
    AddRule(ct, y); y = y - 18
    y = AddHeader(ct, y, L["CFG_HDR_FORMATTING_TOOLBAR"])

    local tbDesc = ct:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    tbDesc:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
    tbDesc:SetWidth(CONTENT_W); tbDesc:SetJustifyH("LEFT")
    tbDesc:SetWordWrap(true); tbDesc:SetHeight(28)
    tbDesc:SetTextColor(0.60, 0.60, 0.60)
    tbDesc:SetText(L["CFG_TOOLBAR_DESC"])
    y = y - 32

    y = AddCheck(ct, y, L["CFG_CHK_WYSIWYG_LABEL"],
        function() return BigNoteBoxDB and BigNoteBoxDB.wysiwygBarVisible ~= false end,
        function(v)
            if BigNoteBoxDB then BigNoteBoxDB.wysiwygBarVisible = v end
            if BNB.ToggleWysiwygBar then BNB.ToggleWysiwygBar(v) end
        end,
        L["CFG_CHK_WYSIWYG_TIP"])

    -- ── Rich Notes ───────────────────────────────────────────────────────────
    AddRule(ct, y); y = y - 18
    y = AddHeader(ct, y, L["CFG_RICH_SIZES_HEADER"])

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
        local base = (db and db.fontSize) or 13
        return math.floor(base * mult + 0.5)
    end

    local indepActive = db and db.richIndependentSizes == true
    local sizeSliders = {}

    local function SetSlidersEnabled(enabled)
        for _, sl in ipairs(sizeSliders) do
            sl:SetAlpha(enabled and 1.0 or 0.4)
            sl:EnableMouse(enabled)
            if sl.Slider then sl.Slider:SetEnabled(enabled) end
        end
    end

    -- Checkbox first so it sits above the sliders in the layout flow.
    local indepCb = CreateFrame("CheckButton", nil, ct, "UICheckButtonTemplate")
    indepCb:SetSize(24, 24)
    indepCb:SetPoint("TOPLEFT", ct, "TOPLEFT", -2, y + 2)
    indepCb:SetChecked(indepActive)
    local indepLbl = ct:CreateFontString(nil, "OVERLAY", "GameFontNormal")
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
        local sl = BNB.CreateSlider(ct, label, 6, 72, initVal, default,
            function(v)
                if not (db and db.richIndependentSizes) then return end
                if db then db[dbKey] = math.floor(v + 0.5) end
                TriggerRichRerender()
            end)
        sl:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
        sl:SetWidth(CONTENT_W)
        sizeSliders[#sizeSliders + 1] = sl
        return sl
    end

    h1sl = MakeSizeSlider(L["CFG_RICH_SIZE_H1"], "richH1Size",   25, 2.0); y = y - (SLIDER_H + ROW_GAP)
    h2sl = MakeSizeSlider(L["CFG_RICH_SIZE_H2"], "richH2Size",   20, 1.6); y = y - (SLIDER_H + ROW_GAP)
    h3sl = MakeSizeSlider(L["CFG_RICH_SIZE_H3"], "richH3Size",   16, 1.3); y = y - (SLIDER_H + ROW_GAP)
    psl  = MakeSizeSlider(L["CFG_RICH_SIZE_P"],  "richBodySize", 12, 1.0); y = y - (SLIDER_H + ROW_GAP)

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
            psl:SetValue( db and db.richBodySize or 12)
        else
            -- Show multiplier ghost values when switching off
            h1sl:SetValue(MultiplierSize(2.0))
            h2sl:SetValue(MultiplierSize(1.6))
            h3sl:SetValue(MultiplierSize(1.3))
            psl:SetValue( MultiplierSize(1.0))
            TriggerRichRerender()
        end
    end)

    SetSlidersEnabled(indepActive)

    -- ── Live Preview ─────────────────────────────────────────────────────────
    AddRule(ct, y); y = y - 18
    y = AddHeader(ct, y, L["CFG_HDR_LIVE_PREVIEW"])

    do
        local lpDesc = ct:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
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

    y = AddCheck(ct, y, L["CFG_FOCUS_PREVIEW_ALWAYS"],
        function() return db.focusPreviewAlwaysShow ~= false end,
        function(v)
            if BigNoteBoxDB then BigNoteBoxDB.focusPreviewAlwaysShow = v end
        end,
        L["CFG_FOCUS_PREVIEW_ALWAYS_TIP"])

    do
        local dlDesc = ct:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        dlDesc:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
        dlDesc:SetWidth(CONTENT_W); dlDesc:SetJustifyH("LEFT")
        dlDesc:SetWordWrap(true)
        dlDesc:SetTextColor(0.55, 0.55, 0.55)
        dlDesc:SetText(L["CFG_PREVIEW_DELAY_DESC"])
        local h = dlDesc:GetStringHeight() + 4
        dlDesc:SetHeight(h); y = y - h - 2
    end

    local SLIDER_W = CONTENT_W - 20
    local curDebounce = db and db.previewDebounce or 0.3
    local debounceSlider = BNB.CreateSlider(ct, L["CFG_PREVIEW_DELAY_SLIDER"], 1, 10,
        math.floor(curDebounce * 10 + 0.5), 3,
        function(v)
            local val = v / 10
            if BigNoteBoxDB then BigNoteBoxDB.previewDebounce = val end
        end,
        function(v) return string.format("%.1f", v / 10) end)
    debounceSlider:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
    debounceSlider:SetWidth(SLIDER_W)
    debounceSlider:EnableMouse(true)
    debounceSlider:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(L["CFG_PREVIEW_DELAY_TIP_TITLE"], 1, 1, 1)
        GameTooltip:AddLine(L["CFG_PREVIEW_DELAY_TIP1"], 0.8, 0.8, 0.8, true)
        GameTooltip:AddLine(L["CFG_PREVIEW_DELAY_TIP2"], 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    debounceSlider:SetScript("OnLeave", function() GameTooltip:Hide() end)
    y = y - (SLIDER_H + ROW_GAP)

    -- ── Undo / Redo ───────────────────────────────────────────────────────────
    AddRule(ct, y); y = y - 18
    y = AddHeader(ct, y, L["CFG_HDR_UNDO_REDO"])

    local undoDesc = ct:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    undoDesc:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
    undoDesc:SetWidth(CONTENT_W); undoDesc:SetJustifyH("LEFT")
    undoDesc:SetWordWrap(true); undoDesc:SetHeight(28)
    undoDesc:SetTextColor(0.60, 0.60, 0.60)
    undoDesc:SetText(L["CFG_UNDO_DESC"])
    y = y - 32

    -- Warning label declared before slider so the onChange closure can reference it.
    -- Anchored relative to where the slider will sit (y - SLIDER_H - ROW_GAP).
    local warnLbl = ct:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    warnLbl:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y - (SLIDER_H + ROW_GAP))
    warnLbl:SetWidth(CONTENT_W); warnLbl:SetJustifyH("LEFT")
    warnLbl:SetWordWrap(true); warnLbl:SetHeight(28)
    warnLbl:SetTextColor(0.90, 0.30, 0.30)
    warnLbl:SetText(L["CFG_UNDO_DEPTH_WARN"])
    local curDepth = db and db.undoDepth or 50
    warnLbl:SetShown(curDepth > 50)

    -- Slider width: subtract extra 20px so the 3-digit value label is never clipped.
    local SLIDER_W = CONTENT_W - 20
    local depthSlider = BNB.CreateSlider(ct, L["CFG_UNDO_DEPTH_SLIDER"], 10, 200,
        curDepth, 50,
        function(v)
            local val = math.floor(v + 0.5)
            if BigNoteBoxDB then BigNoteBoxDB.undoDepth = val end
            warnLbl:SetShown(val > 50)
        end)
    depthSlider:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
    depthSlider:SetWidth(SLIDER_W)
    depthSlider:EnableMouse(true)
    depthSlider:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(L["CFG_UNDO_DEPTH_TIP1"], 0.8, 0.8, 0.8, true)
        GameTooltip:AddLine(L["CFG_UNDO_DEPTH_TIP2"], 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    depthSlider:SetScript("OnLeave", function() GameTooltip:Hide() end)
    y = y - (SLIDER_H + ROW_GAP)

    -- Always reserve warning label height so layout stays stable
    y = y - 34

    -- Idle delay slider (0.3 – 3.0 s, step 0.1, default 0.8)
    -- Stored as a float; displayed with one decimal place.
    do
        local lbl = ct:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        lbl:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
        lbl:SetWidth(CONTENT_W); lbl:SetJustifyH("LEFT"); lbl:SetWordWrap(true)
        lbl:SetTextColor(0.55, 0.55, 0.55)
        lbl:SetText(L["CFG_AUTOSAVE_IDLE_DESC"])
        local h = lbl:GetStringHeight() + 4
        lbl:SetHeight(h); y = y - h - 2
    end
    local curIdle = db and db.undoIdleDelay or 0.8
    local idleSlider = BNB.CreateSlider(ct, L["CFG_AUTOSAVE_IDLE_SLIDER"], 3, 30,
        math.floor(curIdle * 10 + 0.5), 8,
        function(v)
            local val = v / 10
            if BigNoteBoxDB then BigNoteBoxDB.undoIdleDelay = val end
        end,
        function(v) return string.format("%.1f", v / 10) end)
    idleSlider:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
    idleSlider:SetWidth(SLIDER_W)
    idleSlider:EnableMouse(true)
    idleSlider:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(L["CFG_AUTOSAVE_IDLE_TIP_TITLE"], 1, 1, 1)
        GameTooltip:AddLine(L["CFG_AUTOSAVE_IDLE_TIP1"], 0.8, 0.8, 0.8, true)
        GameTooltip:AddLine(L["CFG_AUTOSAVE_IDLE_TIP2"], 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    idleSlider:SetScript("OnLeave", function() GameTooltip:Hide() end)
    y = y - (SLIDER_H + ROW_GAP)

    -- Forced interval slider (1 – 10 s, whole seconds, default 3)
    -- Fires even if you never stop typing, capping continuous-typing chunk size.
    do
        local lbl = ct:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        lbl:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
        lbl:SetWidth(CONTENT_W); lbl:SetJustifyH("LEFT"); lbl:SetWordWrap(true)
        lbl:SetTextColor(0.55, 0.55, 0.55)
        lbl:SetText(L["CFG_AUTOSAVE_FORCED_DESC"])
        local h = lbl:GetStringHeight() + 4
        lbl:SetHeight(h); y = y - h - 2
    end
    local curForced = db and db.undoForcedInterval or 3
    local forcedSlider = BNB.CreateSlider(ct, L["CFG_AUTOSAVE_FORCED_SLIDER"], 1, 10,
        curForced, 3,
        function(v)
            local val = math.floor(v + 0.5)
            if BigNoteBoxDB then BigNoteBoxDB.undoForcedInterval = val end
        end)
    forcedSlider:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
    forcedSlider:SetWidth(SLIDER_W)
    forcedSlider:EnableMouse(true)
    forcedSlider:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(L["CFG_AUTOSAVE_FORCED_TIP_TITLE"], 1, 1, 1)
        GameTooltip:AddLine(L["CFG_AUTOSAVE_FORCED_TIP1"], 0.8, 0.8, 0.8, true)
        GameTooltip:AddLine(L["CFG_AUTOSAVE_FORCED_TIP2"], 0.8, 0.8, 0.8, true)
        GameTooltip:AddLine(L["CFG_AUTOSAVE_FORCED_TIP3"], 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    forcedSlider:SetScript("OnLeave", function() GameTooltip:Hide() end)
    y = y - (SLIDER_H + ROW_GAP)

    -- ── Session History ───────────────────────────────────────────────────────
    AddRule(ct, y); y = y - 18
    y = AddHeader(ct, y, L["CFG_HDR_SESSION_HISTORY"])

    local histDesc = ct:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    histDesc:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
    histDesc:SetWidth(CONTENT_W); histDesc:SetJustifyH("LEFT")
    histDesc:SetWordWrap(true); histDesc:SetHeight(28)
    histDesc:SetTextColor(0.60, 0.60, 0.60)
    histDesc:SetText(L["CFG_AUTOSAVE_HIST_DESC"])
    y = y - 32

    -- History slots slider
    local curSlots = BigNoteBoxDB and BigNoteBoxDB.historyMaxSlots or 5
    local slotsSlider = BNB.CreateSlider(ct, L["CFG_AUTOSAVE_SLOTS_TIP_TITLE"], 1, 20,
        curSlots, 5,
        function(v)
            local val = math.floor(v + 0.5)
            if BigNoteBoxDB then BigNoteBoxDB.historyMaxSlots = val end
        end)
    slotsSlider:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
    slotsSlider:SetWidth(SLIDER_W)
    slotsSlider:EnableMouse(true)
    slotsSlider:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(L["CFG_AUTOSAVE_SLOTS_TIP_TITLE"], 1, 1, 1)
        GameTooltip:AddLine(L["CFG_AUTOSAVE_SLOTS_TIP1"], 0.8, 0.8, 0.8, true)
        GameTooltip:AddLine(L["CFG_AUTOSAVE_SLOTS_TIP2"], 0.8, 0.8, 0.8, true)
        GameTooltip:AddLine(L["CFG_AUTOSAVE_SLOTS_TIP3"], 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    slotsSlider:SetScript("OnLeave", function() GameTooltip:Hide() end)
    y = y - (SLIDER_H + ROW_GAP)

    -- Size readout — computed when the tab is shown
    local histSizeLbl = ct:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    histSizeLbl:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
    histSizeLbl:SetWidth(CONTENT_W); histSizeLbl:SetJustifyH("LEFT")
    histSizeLbl:SetHeight(20)
    histSizeLbl:SetTextColor(0.45, 0.45, 0.45)
    histSizeLbl:SetText(L["CFG_AUTOSAVE_HISTSIZE_CALC"])
    y = y - 24

    -- Refresh size label when the Editor tab becomes visible
    sf:HookScript("OnShow", function()
        if BNB.HistoryTotalSize then
            local bytes = BNB.HistoryTotalSize()
            local ndb   = BigNoteBoxNotesDB
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

K.BUILDERS.editor = BuildEditorTab

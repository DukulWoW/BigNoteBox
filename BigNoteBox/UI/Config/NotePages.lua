-- BigNoteBox UI/Config/NotePages.lua - Modules sub-pages for parts of how notes
-- work: Rich Notes (with Live Preview), Note History, Trash and Alarms. Moved
-- off the Notes and General tabs (ALL-290, Dukul 2026-10-05). Listed on the
-- Modules tab (UI/Config/Modules.lua), built by K.NewSubPage; open one from
-- outside with BNB.OpenSettingsPage("modules", "richNotes" | "history" |
-- "undo" | "trash" | "alarms" | "placement" | "folders"). Window placement (ALL-291) holds a copy
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

-- A red line saying the BigNoteBox_History addon is missing or disabled, only
-- while it is (ALL-466). Height from the text. Returns the new y.
function K.AddNeedsHistoryLine(ct, y)
    if BNB.HistoryAddonLoaded() then return y end
    local fs = ct:CreateFontString(nil, "OVERLAY", "BNBFontNormalSmall")
    fs:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
    fs:SetWidth(CONTENT_W); fs:SetJustifyH("LEFT"); fs:SetWordWrap(true)
    fs:SetTextColor(1, 0.4, 0.4)
    fs:SetText(L["CFG_HISTORY_NEEDS_ADDON"])
    local h = fs:GetStringHeight() + 4
    fs:SetHeight(h)
    return y - h - 6
end

-- ─────────────────────────────────────────────────────────────────────────────
-- NOTE HISTORY: session snapshots (undo / redo has its own page, ALL-460)
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
    -- Needs the BigNoteBox_History addon (ALL-466): without it the module is
    -- off and its box greyed, with the reason under it
    page.available = BNB.HistoryAddonLoaded
    K.GreyWhileOff(enableCb, BNB.HistoryAddonLoaded)
    y = K.AddNeedsHistoryLine(ct, y)

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

    K.BuildRescueSection(sf, ct, y)   -- sets the page height
end

-- ─────────────────────────────────────────────────────────────────────────────
-- RESCUE (ALL-466 stage 3, Dukul 2026-10-13): the notes that exist only in the
-- history file, or are empty while their history has text
-- (BNB.HistoryRescueList, Features/NoteHistory.lua). What it does in plain
-- words, a count, Rescue all, then one row per note: title, which kind and
-- when, a Rescue button and (lost notes only) an X that drops the history
-- for good after a confirm. Settings > Backup and the History window open
-- this page. Sets the page height itself (rows grow it).
-- ─────────────────────────────────────────────────────────────────────────────
function K.BuildRescueSection(sf, ct, y)
    AddRule(ct, y); y = y - 18
    y = AddHeader(ct, y, L["RESCUE_HDR"])
    do
        local desc = ct:CreateFontString(nil, "OVERLAY", "BNBFontNormalSmall")
        desc:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
        desc:SetWidth(CONTENT_W); desc:SetJustifyH("LEFT"); desc:SetWordWrap(true)
        desc:SetTextColor(0.60, 0.60, 0.60)
        desc:SetText(L["RESCUE_DESC"])
        local h = desc:GetStringHeight() + 4
        desc:SetHeight(h); y = y - h - 6
    end

    local countLbl = ct:CreateFontString(nil, "OVERLAY", "BNBFontNormalSmall")
    countLbl:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
    countLbl:SetWidth(CONTENT_W); countLbl:SetJustifyH("LEFT"); countLbl:SetHeight(18)
    countLbl:SetTextColor(0.55, 0.55, 0.55)
    y = y - 22

    local RefreshRescue
    local allBtn = BNB.CreateButton(nil, ct, L["RESCUE_ALL_BTN"], 160, 22)
    allBtn:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
    allBtn:SetScript("OnClick", function()
        if BNB.HistoryRescueAll then BNB.HistoryRescueAll() end
        RefreshRescue()
    end)
    allBtn:SetMotionScriptsWhileDisabled(true)   -- greyed, the tooltip says why
    allBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(L["RESCUE_ALL_BTN"], 1, 1, 1)
        GameTooltip:AddLine(L["RESCUE_ALL_TIP"], 0.8, 0.8, 0.8, true)
        if not self:IsEnabled() then GameTooltip:AddLine(L["RESCUE_NONE_SHORT"], 0.8, 0.4, 0.4, true) end
        GameTooltip:Show()
    end)
    allBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    y = y - (22 + ROW_GAP)

    local ROW, BTN_W, listTop, rows = 28, 70, y - 4, {}
    local ICON = "Interface\\Icons\\INV_Misc_Note_06"
    local function Row(i)
        local r = rows[i]
        if r then return r end
        r = CreateFrame("Frame", nil, ct)
        r:SetSize(CONTENT_W, ROW)
        r._del = BNB.CreateIconButton(r, 16, "close", { tip = L["RESCUE_ROW_DEL_TIP"], tipWrap = true, tipAnchor = "ANCHOR_TOP" })
        r._del:SetPoint("RIGHT", r, "RIGHT", -2, 0)
        r._btn = BNB.CreateButton(nil, r, L["RESCUE_ROW_BTN"], BTN_W, 20)
        r._btn:SetPoint("RIGHT", r, "RIGHT", -24, 0)
        r._info = r:CreateFontString(nil, "OVERLAY", "BNBFontNormalSmall")
        r._info:SetPoint("RIGHT", r._btn, "LEFT", -8, 0)
        r._info:SetJustifyH("RIGHT"); r._info:SetTextColor(0.55, 0.55, 0.55)
        r._icon = r:CreateTexture(nil, "ARTWORK")
        r._icon:SetSize(22, 22); r._icon:SetPoint("LEFT", r, "LEFT", 4, 0)
        r._icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        r._title = r:CreateFontString(nil, "OVERLAY", "BNBFontNormal")
        r._title:SetPoint("LEFT", r._icon, "RIGHT", 8, 0)
        r._title:SetPoint("RIGHT", r._info, "LEFT", -8, 0)
        r._title:SetJustifyH("LEFT"); r._title:SetWordWrap(false)
        BNB.SetTextWhite(r._title)
        r._btn:SetScript("OnClick", function()
            if BNB.HistoryRescue then BNB.HistoryRescue(r._id) end
            RefreshRescue()
        end)
        r._btn:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:AddLine(L["RESCUE_ROW_BTN"], 1, 1, 1)
            local tip = L["RESCUE_ROW_TIP"]
            if r._kind == "empty" then tip = L["RESCUE_ROW_EMPTY_TIP"] end
            GameTooltip:AddLine(tip, 0.8, 0.8, 0.8, true)
            GameTooltip:Show()
        end)
        r._btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
        r._del:SetScript("OnClick", function()
            local id, title = r._id, r._title:GetText() or ""
            StaticPopup_Show("BNB_MULTI_CONFIRM", string.format(L["RESCUE_DEL_CONFIRM_FMT"], title), nil, function()
                if BNB.HistoryRescueDiscard then BNB.HistoryRescueDiscard(id) end
                RefreshRescue()
            end)
        end)
        rows[i] = r
        return r
    end

    RefreshRescue = function()
        local list = BNB.HistoryRescueList and BNB.HistoryRescueList() or {}
        local n = #list
        if not BNB.HistoryAddonLoaded() then
            countLbl:SetText(L["CFG_HISTORY_NEEDS_ADDON"])
        elseif n == 0 then
            countLbl:SetText(L["RESCUE_NONE"])
        else
            countLbl:SetText(BNB.HistoryRescueCountText(n))
        end
        allBtn:SetEnabled(n > 0)
        local ry = listTop
        for i, e in ipairs(list) do
            local r = Row(i)
            r._id, r._kind = e.id, e.kind
            r._title:SetText(e.title ~= "" and e.title or L["UNTITLED"])
            local note = e.kind == "empty" and BNB.GetNote(e.id)
            r._icon:SetTexture(note and note.icon and note.icon ~= "" and note.icon or ICON)
            local when = BNB.FmtTime and BNB.FmtTime(e.ts) or ""
            if e.kind == "empty" then
                r._info:SetText(string.format(L["RESCUE_INFO_EMPTY_FMT"], when))
            else
                local fmt = L["RESCUE_INFO_FMT"]
                if e.count == 1 then fmt = L["RESCUE_INFO_ONE_FMT"] end
                r._info:SetText(string.format(fmt, when, e.count))
            end
            r._del:SetShown(e.kind == "missing")   -- an empty note is deleted or written in, not here
            r:ClearAllPoints()
            r:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, ry)
            r:Show()
            ry = ry - ROW
        end
        for i = n + 1, #rows do rows[i]:Hide() end
        sf:FinaliseHeight(math.abs(ry) + 12)
    end

    sf:HookScript("OnShow", RefreshRescue)
    -- A note created, changed or deleted elsewhere while the page is open (an
    -- empty note written in, a rescue from the popup): one redraw per frame
    local function Follow()
        if sf:IsVisible() then BNB.Debounce("RescueRows", 0, RefreshRescue) end
    end
    for _, msg in ipairs({ "NoteCreated", "NoteChanged", "NoteDeleted", "NoteRestored", "TrashChanged", "HistoryRescueChanged" }) do
        BNB.RegisterMessage("RescuePage", msg, Follow)
    end
    sf:FinaliseHeight(math.abs(listTop) + 12)
end

-- Opens the Rescue list (Settings > Modules > Note History), for the buttons
-- on Settings > Backup and in the History window
function BNB.OpenRescuePage()
    if BNB.OpenSettingsPage then BNB.OpenSettingsPage("modules", "history") end
end

-- ─────────────────────────────────────────────────────────────────────────────
-- UNDO / REDO (ALL-460, Dukul 2026-10-13): moved off the Notes tab, plus
-- "Keep between sessions" (Features/UndoKeep.lua, the BigNoteBox_History
-- addon). Undo itself cannot be switched off, so the page has no master
-- checkbox and sits with the settings-only pages; the keep switch is its own.
-- ─────────────────────────────────────────────────────────────────────────────
function K.BuildUndoPage(sf, ct, y, page)
    local db = BigNoteBoxDB


    local undoDesc = ct:CreateFontString(nil, "OVERLAY", "BNBFontNormalSmall")
    undoDesc:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
    undoDesc:SetWidth(CONTENT_W); undoDesc:SetJustifyH("LEFT")
    undoDesc:SetWordWrap(true); undoDesc:SetHeight(28)
    undoDesc:SetTextColor(0.60, 0.60, 0.60)
    undoDesc:SetText(L["CFG_UNDO_DESC"])
    y = y - 32

    -- Warning label declared before slider so the onChange closure can reference it.
    -- Anchored relative to where the slider will sit (y - SLIDER_H - ROW_GAP).
    local warnLbl = ct:CreateFontString(nil, "OVERLAY", "BNBFontNormalSmall")
    warnLbl:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y - (SLIDER_H + ROW_GAP))
    warnLbl:SetWidth(CONTENT_W); warnLbl:SetJustifyH("LEFT")
    warnLbl:SetWordWrap(true); warnLbl:SetHeight(28)
    warnLbl:SetTextColor(0.90, 0.30, 0.30)
    warnLbl:SetText(L["CFG_UNDO_DEPTH_WARN"])
    local curDepth = db and db.undoDepth or BNB.DEFAULTS.undoDepth
    warnLbl:SetShown(curDepth > 50)

    local depthSlider = BNB.CreateStackedSlider(ct, CONTENT_W, {
        label = L["CFG_UNDO_DEPTH_SLIDER"], min = 10, max = 200,
        value = curDepth, default = BNB.DEFAULTS.undoDepth,
        onChange = function(v)
            if BigNoteBoxDB then BigNoteBoxDB.undoDepth = v end
            warnLbl:SetShown(v > 50)
        end,
        tip = { L["CFG_UNDO_DEPTH_TIP1"], L["CFG_UNDO_DEPTH_TIP2"] },
    })
    depthSlider:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
    y = y - (SLIDER_H + ROW_GAP)

    -- Always reserve warning label height so layout stays stable
    y = y - 34

    -- Idle delay slider (0.3 – 3.0 s, step 0.1, default 0.8)
    -- Stored as a float; displayed with one decimal place.
    do
        local lbl = ct:CreateFontString(nil, "OVERLAY", "BNBFontNormalSmall")
        lbl:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
        lbl:SetWidth(CONTENT_W); lbl:SetJustifyH("LEFT"); lbl:SetWordWrap(true)
        lbl:SetTextColor(0.55, 0.55, 0.55)
        lbl:SetText(L["CFG_AUTOSAVE_IDLE_DESC"])
        local h = lbl:GetStringHeight() + 4
        lbl:SetHeight(h); y = y - h - 2
    end
    local curIdle = db and db.undoIdleDelay or BNB.DEFAULTS.undoIdleDelay
    local idleSlider = BNB.CreateStackedSlider(ct, CONTENT_W, {
        label = L["CFG_AUTOSAVE_IDLE_SLIDER"], min = 3, max = 30,
        value = math.floor(curIdle * 10 + 0.5), default = math.floor(BNB.DEFAULTS.undoIdleDelay * 10 + 0.5),
        fmt = function(v) return string.format("%.1f", v / 10) end,
        onChange = function(v)
            local val = v / 10
            if BigNoteBoxDB then BigNoteBoxDB.undoIdleDelay = val end
        end,
        tipTitle = L["CFG_AUTOSAVE_IDLE_TIP_TITLE"],
        tip = { L["CFG_AUTOSAVE_IDLE_TIP1"], L["CFG_AUTOSAVE_IDLE_TIP2"] },
    })
    idleSlider:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
    y = y - (SLIDER_H + ROW_GAP)

    -- Forced interval slider (1 – 10 s, whole seconds, default 3)
    -- Fires even if you never stop typing, capping continuous-typing chunk size.
    do
        local lbl = ct:CreateFontString(nil, "OVERLAY", "BNBFontNormalSmall")
        lbl:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
        lbl:SetWidth(CONTENT_W); lbl:SetJustifyH("LEFT"); lbl:SetWordWrap(true)
        lbl:SetTextColor(0.55, 0.55, 0.55)
        lbl:SetText(L["CFG_AUTOSAVE_FORCED_DESC"])
        local h = lbl:GetStringHeight() + 4
        lbl:SetHeight(h); y = y - h - 2
    end
    local curForced = db and db.undoForcedInterval or BNB.DEFAULTS.undoForcedInterval
    local forcedSlider = BNB.CreateStackedSlider(ct, CONTENT_W, {
        label = L["CFG_AUTOSAVE_FORCED_SLIDER"], min = 1, max = 10,
        value = curForced, default = BNB.DEFAULTS.undoForcedInterval,
        onChange = function(v)
            if BigNoteBoxDB then BigNoteBoxDB.undoForcedInterval = v end
        end,
        tipTitle = L["CFG_AUTOSAVE_FORCED_TIP_TITLE"],
        tip = { L["CFG_AUTOSAVE_FORCED_TIP1"], L["CFG_AUTOSAVE_FORCED_TIP2"], L["CFG_AUTOSAVE_FORCED_TIP3"] },
    })
    forcedSlider:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
    y = y - (SLIDER_H + ROW_GAP)


    -- ── Keep between sessions ────────────────────────────────────────────────────
    AddRule(ct, y); y = y - 18
    y = AddHeader(ct, y, L["CFG_HDR_UNDO_KEEP"])

    -- What keeping does, in plain words, before the switch (Dukul 2026-10-13).
    -- Height from the text, so a longer translation pushes the rows down.
    do
        local keepDesc = ct:CreateFontString(nil, "OVERLAY", "BNBFontNormalSmall")
        keepDesc:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
        keepDesc:SetWidth(CONTENT_W); keepDesc:SetJustifyH("LEFT"); keepDesc:SetWordWrap(true)
        keepDesc:SetTextColor(0.60, 0.60, 0.60)
        keepDesc:SetText(L["CFG_UNDO_KEEP_DESC"])
        local h = keepDesc:GetStringHeight() + 4
        keepDesc:SetHeight(h); y = y - h - 6
    end

    local keepCb
    y, keepCb = AddCheck(ct, y, L["CFG_UNDO_KEEP_LABEL"],
        function() return BNB.UndoKeepEnabled() end,
        function(v) if BNB.UndoKeepApply then BNB.UndoKeepApply(v) end end,
        L["CFG_UNDO_KEEP_TIP"])
    K.GreyWhileOff(keepCb, BNB.HistoryAddonLoaded)   -- needs BigNoteBox_History (ALL-466)
    local function KeepOn() return keepCb:GetChecked() and true or false end

    local daysSlider
    y, daysSlider = K.AddSlider(ct, y, L["CFG_UNDO_KEEP_DAYS"], 1, 30,
        function() return (db and db.undoKeepDays) or BNB.DEFAULTS.undoKeepDays end,
        function(v) if BigNoteBoxDB then BigNoteBoxDB.undoKeepDays = v end end,
        { L["CFG_UNDO_KEEP_DAYS_TIP"] }, BNB.DEFAULTS.undoKeepDays)

    -- Size readout + Reset, re-read whenever the page shows
    local sizeLbl = ct:CreateFontString(nil, "OVERLAY", "BNBFontNormalSmall")
    sizeLbl:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
    sizeLbl:SetWidth(CONTENT_W); sizeLbl:SetJustifyH("LEFT"); sizeLbl:SetWordWrap(true)
    sizeLbl:SetHeight(30)
    sizeLbl:SetTextColor(0.55, 0.55, 0.55)
    y = y - 32

    local RefreshList   -- below the Delete button (ALL-465)
    local function RefreshSize()
        local bytes, n
        if BNB.UndoKeepSize then bytes, n = BNB.UndoKeepSize() end
        if not bytes then
            sizeLbl:SetText(L["CFG_UNDO_KEEP_SIZE_MISSING"])
        elseif n == 0 then
            sizeLbl:SetText(L["CFG_UNDO_KEEP_SIZE_NONE"])
        else
            local str = BNB.HistoryFormatSize and BNB.HistoryFormatSize(bytes)
                or string.format(L["CFG_UNIT_KB_FMT"], math.floor(bytes / 1024))
            sizeLbl:SetText(string.format(L["CFG_UNDO_KEEP_SIZE_FMT"], str, n))
        end
    end

    local resetBtn = BNB.CreateButton(nil, ct, L["CFG_UNDO_KEEP_RESET"], 200, 22)
    resetBtn:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
    resetBtn:SetScript("OnClick", function()
        StaticPopup_Show("BNB_MULTI_CONFIRM", L["CFG_UNDO_KEEP_RESET_CONFIRM"], nil, function()
            if BNB.UndoKeepReset then BNB.UndoKeepReset() end
            RefreshSize(); RefreshList()
        end)
    end)
    resetBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(L["CFG_UNDO_KEEP_RESET"], 1, 1, 1)
        GameTooltip:AddLine(L["CFG_UNDO_KEEP_RESET_TIP"], 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    resetBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Reload now, an icon right of Delete (Dukul's bt-save art, 2026-10-13: one
    -- button here, not one per row). Greyed while no row waits to be written.
    -- C_UI.Reload is protected, so it runs in the click itself.
    local reloadBtn = BNB.CreateIconButton(ct, 22, "save", {
        tip = L["CFG_UNDO_KEEP_ROW_RELOAD"], tipSub = L["CFG_UNDO_KEEP_ROW_RELOAD_TIP"],
        tipWrap = true, onClick = function() C_UI.Reload() end })
    reloadBtn:SetPoint("LEFT", resetBtn, "RIGHT", 6, 0)
    y = y - (22 + ROW_GAP)

    -- One row per note with saved (or this session's, written at logout) undo
    -- history (ALL-465, Dukul 2026-10-13): title opens the note, size + when
    -- it was saved, X deletes that note's history without asking. Rows are
    -- pooled and rebuilt whenever the page shows or something is deleted.
    -- Icon + frame and title colour as in the note list / Trash rows (Dukul 2026-10-13)
    local LIST_ROW_H, LIST_ICON, LIST_ICON_X, listTop, rows = 28, 22, 4, y - 6, {}
    local DEFAULT_ICON = "Interface\\Icons\\INV_Misc_Note_06"
    local function TitleColour(r)
        local note = BNB.GetNote(r._id)
        local tc = note and note.titleColor
        if tc and tc.r then r._title:SetTextColor(tc.r, tc.g, tc.b, 1)
        else BNB.SetTextWhite(r._title) end
    end
    local function Row(i)
        local r = rows[i]
        if r then return r end
        r = CreateFrame("Frame", nil, ct)
        r:SetSize(CONTENT_W, LIST_ROW_H)
        r._del = BNB.CreateIconButton(r, 16, "close",
            { tip = L["CFG_UNDO_KEEP_ROW_DEL_TIP"], tipAnchor = "ANCHOR_TOP" })
        r._del:SetPoint("RIGHT", r, "RIGHT", -2, 0)
        r._info = r:CreateFontString(nil, "OVERLAY", "BNBFontNormalSmall")
        r._info:SetPoint("RIGHT", r._del, "LEFT", -8, 0)
        r._info:SetJustifyH("RIGHT")
        r._info:SetTextColor(0.55, 0.55, 0.55)
        r._open = CreateFrame("Button", nil, r)
        -- Room on the left for an icon frame's overhang (as Trash, ALL-332)
        r._icon = r:CreateTexture(nil, "ARTWORK", nil, 2)
        r._icon:SetSize(LIST_ICON, LIST_ICON)
        r._icon:SetPoint("LEFT", r, "LEFT", LIST_ICON_X, 0)
        r._icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        r._open:SetPoint("LEFT", r._icon, "RIGHT", 8, 0)
        r._open:SetPoint("RIGHT", r._info, "LEFT", -8, 0)
        r._open:SetHeight(LIST_ROW_H)
        r._title = r._open:CreateFontString(nil, "OVERLAY", "BNBFontNormal")
        r._title:SetAllPoints(); r._title:SetJustifyH("LEFT"); r._title:SetWordWrap(false)
        r._open:SetScript("OnEnter", function(self)
            r._title:SetAlpha(0.75)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:AddLine(L["CFG_UNDO_KEEP_ROW_OPEN_TIP"], 0.8, 0.8, 0.8)
            GameTooltip:Show()
        end)
        r._open:SetScript("OnLeave", function()
            r._title:SetAlpha(1); GameTooltip:Hide()
        end)
        r._open:SetScript("OnClick", function() if BNB.OpenNoteInMain then BNB.OpenNoteInMain(r._id) end end)
        r._del:SetScript("OnClick", function()
            if BNB.UndoKeepDeleteNote then BNB.UndoKeepDeleteNote(r._id) end
            RefreshSize(); RefreshList()
        end)
        rows[i] = r
        return r
    end

    RefreshList = function()
        local list = BNB.UndoKeepList and BNB.UndoKeepList() or {}
        local ry = listTop
        for i, e in ipairs(list) do
            local r, note = Row(i), BNB.GetNote(e.id)
            r._id = e.id
            local title = note and note.title
            r._title:SetText((title and title ~= "") and title or L["UNTITLED"])
            TitleColour(r)
            local icon = note and note.icon
            r._icon:SetTexture((icon and icon ~= "") and icon or DEFAULT_ICON)
            r:Show()   -- shown before the frame: a hidden icon gets none
            if BNB.ApplyIconFrame then BNB.ApplyIconFrame(r._icon, note, LIST_ICON) end
            local size = e.bytes and (BNB.HistoryFormatSize and BNB.HistoryFormatSize(e.bytes)
                or string.format(L["CFG_UNIT_KB_FMT"], math.floor(e.bytes / 1024)))
            local when
            if e.pending then when = L["CFG_UNDO_KEEP_ROW_PENDING"]
            else when = BNB.FmtTime and BNB.FmtTime(e.t) or "" end
            r._info:SetText(size and (size .. "  -  " .. when) or when)
            r:ClearAllPoints()
            r:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, ry)
            r:Show()
            ry = ry - LIST_ROW_H
        end
        for i = #list + 1, #rows do rows[i]:Hide() end
        -- Reload now is useful only while something waits to be written
        local waiting = false
        for _, e in ipairs(list) do if e.pending then waiting = true; break end end
        reloadBtn:SetEnabled(waiting)
        sf:FinaliseHeight(math.abs(ry) + 12)
    end

    -- The days only matter while keeping is on; the readout and Reset work
    -- either way (what is saved stays when it is switched off)
    local function SyncKeep()
        local on = KeepOn()
        daysSlider:SetEnabled(on); daysSlider:SetAlpha(on and 1 or 0.35)
    end
    keepCb:HookScript("OnClick", function() SyncKeep(); RefreshSize(); RefreshList() end)
    sf:HookScript("OnShow", function()
        keepCb:SetChecked(BNB.UndoKeepEnabled())
        SyncKeep(); RefreshSize(); RefreshList()
    end)
    SyncKeep()

    -- A note's title, icon, frame or title colour changed (or it was deleted)
    -- while the page is open: redraw the rows, as the note list does
    -- (Dukul 2026-10-13). Batched to one redraw per frame.
    local function OnNoteMsg()
        if sf:IsVisible() then BNB.Debounce("UndoPageRows", 0, RefreshList) end
    end
    for _, msg in ipairs({ "NoteChanged", "NoteDeleted", "NoteRestored" }) do
        BNB.RegisterMessage("UndoPage", msg, OnNoteMsg)
    end

    sf:FinaliseHeight(math.abs(y) + 12)   -- RefreshList sets it again with the rows
end

-- ─────────────────────────────────────────────────────────────────────────────
-- TRASH: the checkbox is the page's master switch (twin on the overview row)
-- ─────────────────────────────────────────────────────────────────────────────
-- ─────────────────────────────────────────────────────────────────────────────
-- FOLDERS (ALL-514): the module switch, how a new folder starts, and the
-- Patch notes system folder (ALL-511), which is not part of the module and
-- works with it off
-- ─────────────────────────────────────────────────────────────────────────────
function K.BuildFoldersPage(sf, ct, y, page)
    local db = BigNoteBoxDB
    local startCb
    local function Sync()
        local on = BNB.FoldersEnabled()
        if startCb then
            startCb:SetEnabled(on); startCb:SetAlpha(on and 1 or 0.35)
            if startCb._lbl then startCb._lbl:SetAlpha(on and 1 or 0.35) end
        end
    end

    local enableCb
    y, enableCb = AddCheck(ct, y, L["CFG_FOLDERS_ENABLE_LABEL"],
        function() return BNB.FoldersEnabled() end,
        function(v)
            db.foldersEnabled = v
            BNB.ApplyFoldersModule(v)
            Sync()
        end,
        L["CFG_FOLDERS_ENABLE_TIP"])
    page.enableCb = enableCb   -- twin on the Modules overview row

    -- Each folder keeps its own open / closed; this is how a new one starts
    -- (ALL-510, Dukul 2026-10-19)
    y, startCb = AddCheck(ct, y, L["CFG_FOLDER_START_OPEN"],
        function() return db.folderStartOpen ~= false end,
        function(v) db.folderStartOpen = v end,
        L["CFG_FOLDER_START_OPEN_TIP"])
    startCb:HookScript("OnShow", Sync)

    -- System folders (ALL-511): from BigNoteBox itself, after your notes
    y = AddRule(ct, y - 4) - 6
    y = AddHeader(ct, y, L["CFG_SYS_FOLDERS_HEADER"])
    -- The Patch notes folder is the Help book's Patch notes tab now (ALL-614)
    -- The Help folder (ALL-512): a help link still opens a topic while it is off
    y = AddCheck(ct, y, L["CFG_SYS_HELP"],
        function() return db.sysHelp ~= false end,
        function(v)
            db.sysHelp = v
            if BNB.SystemNotes then BNB.SystemNotes.Reveal("help", false) end
            BNB.SendMessage("SystemNotesChanged", "help")
        end,
        L["CFG_SYS_HELP_TIP"])
    Sync()
    sf:FinaliseHeight(math.abs(y) + 12)
end

-- ─────────────────────────────────────────────────────────────────────────────
-- EXPLORER VIEW (ALL-414, Dukul 2026-10-21): the module switch and the view
-- the main window opens on after each login
-- ─────────────────────────────────────────────────────────────────────────────
function K.BuildExplorerPage(sf, ct, y, page)
    local db = BigNoteBoxDB
    local dd, ddLbl, keepCb
    local function Sync()
        local on = BNB.ExplorerEnabled()
        if dd then dd:SetEnabled(on); dd:SetAlpha(on and 1 or 0.35) end
        if ddLbl then ddLbl:SetAlpha(on and 1 or 0.35) end
        if keepCb then keepCb:SetEnabled(on); keepCb:SetAlpha(on and 1 or 0.35) end
    end

    local enableCb
    y, enableCb = AddCheck(ct, y, L["CFG_EXPLORER_ENABLE_LABEL"],
        function() return BNB.ExplorerEnabled() end,
        function(v)
            db.explorerEnabled = v
            if BNB.ApplyExplorerModule then BNB.ApplyExplorerModule(v) end
            Sync()
        end,
        L["CFG_EXPLORER_ENABLE_TIP"])
    page.enableCb = enableCb   -- twin on the Modules overview row

    ddLbl = ct:CreateFontString(nil, "OVERLAY", "BNBFontNormal")
    ddLbl:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
    ddLbl:SetHeight(ROW_H); ddLbl:SetJustifyH("LEFT")
    ddLbl:SetText(L["CFG_EXPLORER_DEFAULT"])
    y = y - (ROW_H + 2)
    dd = BNB.SkinDropdown(CreateFrame("DropdownButton", nil, ct, "WowStyle1DropdownTemplate"))
    dd:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
    dd:SetWidth(220)
    dd:SetupMenu(function(_, root)
        for _, c in ipairs({ { "explorer", "CFG_EXPLORER_DEFAULT_EXPLORER" }, { "list", "CFG_EXPLORER_DEFAULT_LIST" } }) do
            local key = c[1]
            root:CreateRadio(L[c[2]],
                function() return (db.explorerDefault or "explorer") == key end,
                function() db.explorerDefault = key end)
        end
    end)
    dd:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(L["CFG_EXPLORER_DEFAULT"], 1, 1, 1)
        GameTooltip:AddLine(L["CFG_EXPLORER_DEFAULT_TIP"], 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    dd:HookScript("OnLeave", function() GameTooltip:Hide() end)
    dd:HookScript("OnShow", Sync)
    y = y - 32
    -- No note list to find it again in (Dukul, 2026-10-22): off by default
    y, keepCb = AddCheck(ct, y, L["CFG_EXPLORER_KEEP_NOTE"],
        function() return db.explorerKeepNote == true end,
        function(v) db.explorerKeepNote = v and true or false end,
        L["CFG_EXPLORER_KEEP_NOTE_TIP"])
    Sync()
    sf:FinaliseHeight(math.abs(y) + 12)
end

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
-- ALARMS: the module switch, the window side, how alarms show and the
-- defaults for new alarms (ALL-292)
-- ─────────────────────────────────────────────────────────────────────────────
function K.BuildAlarmsPage(sf, ct, y, page)
    -- Module switch (ALL-343). Applies live: off hides every way in and no
    -- alarm rings; the alarms stay on their notes (BNB.Alarm.ApplyModule).
    local enableCb, sideDD, showLbl, showDD, GreyDefaults
    local function ApplyAlarmsSection(on)
        local a = on and 1 or 0.35
        sideDD:SetAlpha(a); sideDD._lbl:SetAlpha(a)
        if sideDD._dd then sideDD._dd:SetEnabled(on) end
        showLbl:SetAlpha(a); showDD:SetAlpha(a)
        if showDD._dd then showDD._dd:SetEnabled(on) end
        if GreyDefaults then GreyDefaults(on) end
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

    -- Defaults for new alarms (ALL-292): BigNoteBoxDB.alarmDefaults, read at
    -- ring time (AlarmManager Defaults()). An alarm whose glow type / mode /
    -- colour is "Default" follows these, so a change here reaches it too; the
    -- snooze interval is copied into a new alarm when the Set alarm window
    -- opens. glowColor is always replaced, never changed in place.
    y = AddRule(ct, y) - 4
    y = AddHeader(ct, y, L["CFG_ALARM_DEFAULTS_HDR"])
    local function AD()
        BigNoteBoxDB.alarmDefaults = BigNoteBoxDB.alarmDefaults or CopyTable(BNB.DEFAULTS.alarmDefaults)
        return BigNoteBoxDB.alarmDefaults
    end
    local defWidgets = {}
    local function DefDropdown(label, entries, key)
        local lbl = ct:CreateFontString(nil, "OVERLAY", "BNBFontNormal")
        lbl:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
        lbl:SetHeight(K.ROW_H); lbl:SetJustifyH("LEFT")
        lbl:SetText(label)
        y = y - (K.ROW_H + 2)
        local dd = BNB.CreateValueDropdown(ct, entries,
            AD()[key] or BNB.DEFAULTS.alarmDefaults[key],
            function(v) AD()[key] = v end, K.CONTENT_W, 26)
        dd:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
        dd._lbl = lbl
        dd:HookScript("OnShow", function(self)
            self:SetSelected(AD()[key] or BNB.DEFAULTS.alarmDefaults[key])
        end)
        defWidgets[#defWidgets + 1] = dd
        y = y - (32 + K.ROW_GAP)
    end
    DefDropdown(L["CFG_ALARM_DEF_SNOOZE"], {
        { label = L["AW_SNZ_1MIN"],  value = 1 },
        { label = L["AW_SNZ_5MIN"],  value = 5 },
        { label = L["AW_SNZ_10MIN"], value = 10 },
        { label = L["AW_SNZ_15MIN"], value = 15 },
        { label = L["AW_SNZ_30MIN"], value = 30 },
        { label = L["AW_SNZ_60MIN"], value = 60 },
    }, "snoozeDefault")
    DefDropdown(L["CFG_ALARM_DEF_GLOW"], {
        { label = L["AW_GLOW_PIXEL"],    value = 1 },
        { label = L["AW_GLOW_AUTOCAST"], value = 2 },
        { label = L["AW_GLOW_BORDER"],   value = 3 },
        { label = L["AW_GLOW_PROC"],     value = 4 },
    }, "glowType")
    DefDropdown(L["CFG_ALARM_DEF_GLOW_MODE"], {
        { label = L["AW_GLOWMODE_CONTINUOUS"], value = "continuous" },
        { label = L["AW_GLOWMODE_PULSE"],      value = "pulse" },
        { label = L["AW_GLOWMODE_ONCE"],       value = "once" },
    }, "glowMode")

    -- Glow colour: the palette with the picker tile, as every colour choice
    -- (ALL-327). The grid lives in its own frame so it can be greyed whole.
    local colLbl = ct:CreateFontString(nil, "OVERLAY", "BNBFontNormal")
    colLbl:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
    colLbl:SetHeight(K.ROW_H); colLbl:SetJustifyH("LEFT")
    colLbl:SetText(L["CFG_ALARM_DEF_COLOR"])
    y = y - (K.ROW_H + 2)
    local colBlk = CreateFrame("Frame", nil, ct)
    colBlk:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
    colBlk:SetWidth(K.CONTENT_W)
    local function GlowColor()
        local c = AD().glowColor or BNB.DEFAULTS.alarmDefaults.glowColor
        return c[1], c[2], c[3]
    end
    local gy = BNB.BuildColorGrid(colBlk, 0, K.CONTENT_W, function(r, g, b)
        AD().glowColor = { r, g, b, 1 }
    end, GlowColor)
    colBlk:SetHeight(-gy)
    y = y + gy - K.ROW_GAP

    GreyDefaults = function(on)
        local a = on and 1 or 0.35
        for _, dd in ipairs(defWidgets) do
            dd:SetAlpha(a); dd._lbl:SetAlpha(a)
            if dd._dd then dd._dd:SetEnabled(on) end
        end
        colLbl:SetAlpha(a); colBlk:SetAlpha(a)
        for _, child in ipairs({ colBlk:GetChildren() }) do child:EnableMouse(on) end
    end
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

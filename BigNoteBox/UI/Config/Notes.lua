-- BigNoteBox UI/Config/Notes.lua - Settings Notes tab (was Editor, ALL-84)
-- Split out of ConfigWindow.lua (ALL-65.10).

local BNB = BigNoteBox
local L   = BNB.L

local K = BNB._ConfigKit
local CONTENT_W, ROW_H, ROW_GAP, SLIDER_H = K.CONTENT_W, K.ROW_H, K.ROW_GAP, K.SLIDER_H
local AddRule, AddHeader, AddCheck, MakeKeybindRow = K.AddRule, K.AddHeader, K.AddCheck, K.MakeKeybindRow

-- A smaller gold heading for a group inside a section (Trash, Tag tree under Notes).
local function AddSubHeader(ct, y, text)
    local lbl = ct:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    lbl:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y - 6)
    lbl:SetTextColor(1, 0.82, 0)
    lbl:SetText(text)
    return y - 26
end

-- ─────────────────────────────────────────────────────────────────────────────
-- TAB 2 -- NOTES
-- Notes (new note, lock, trash, tag tree), then the editor: saving, toolbar,
-- rich notes, live preview, undo/redo, session history.
-- ─────────────────────────────────────────────────────────────────────────────
local function BuildNotesTab(sf, ct)
    local db = BigNoteBoxDB
    local y  = -8

    -- ── Notes (moved from the Features tab, ALL-84) ─────────────────────────────
    y = AddHeader(ct, y, L["CFG_HDR_NOTES"])

    -- New note behaviour dropdown
    do
        local lbl = ct:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        lbl:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
        lbl:SetHeight(ROW_H); lbl:SetJustifyH("LEFT")
        lbl:SetText(L["CFG_NEWNOTE_BEHAVIOUR"])
        y = y - (ROW_H + 2)

        local NEW_NOTE_ITEMS = {
            { key = "prompt",    label = L["CFG_NEWNOTE_ITEM_PROMPT"] },
            { key = "immediate", label = L["CFG_NEWNOTE_ITEM_IMMEDIATE"]             },
        }
        local curBehaviour = db.newNoteBehaviour or "prompt"
        local nnDD = CreateFrame("DropdownButton", nil, ct, "WowStyle1DropdownTemplate")
        nnDD:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
        nnDD:SetWidth(CONTENT_W)
        nnDD:SetupMenu(function(_, root)
            for _, item in ipairs(NEW_NOTE_ITEMS) do
                root:CreateRadio(item.label,
                    function() return curBehaviour == item.key end,
                    function()
                        curBehaviour = item.key
                        db.newNoteBehaviour = item.key
                        nnDD:GenerateMenu()
                    end)
            end
        end)
        nnDD:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(L["CFG_NEWNOTE_BEHAVIOUR"], 1, 1, 1)
            GameTooltip:AddLine(L["CFG_NEWNOTE_PROMPT"], 0.8, 0.8, 0.8, true)
            GameTooltip:AddLine(L["CFG_NEWNOTE_IMMEDIATE"], 0.8, 0.8, 0.8, true)
            GameTooltip:Show()
        end)
        nnDD:SetScript("OnLeave", function() GameTooltip:Hide() end)
        y = y - (32 + ROW_GAP)
    end

    -- What double-clicking a note in the list does (ALL-100); nil = settings
    do
        local lbl = ct:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        lbl:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
        lbl:SetHeight(ROW_H); lbl:SetJustifyH("LEFT")
        lbl:SetText(L["CFG_LIST_DBLCLICK"])
        y = y - (ROW_H + 2)

        local entries = {}
        for _, a in ipairs(BNB.LIST_DOUBLE_CLICK_ACTIONS) do
            entries[#entries + 1] = { label = L[a.key], value = a.value }
        end
        local dcDD = BNB.CreateValueDropdown(ct, entries, db.listDoubleClick or "settings",
            function(v) db.listDoubleClick = (v ~= "settings") and v or nil end,
            CONTENT_W, 26)
        dcDD:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
        local tipOwner = dcDD._dd or dcDD
        tipOwner:HookScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(L["CFG_LIST_DBLCLICK"], 1, 1, 1)
            GameTooltip:AddLine(L["CFG_LIST_DBLCLICK_TIP"], 0.8, 0.8, 0.8, true)
            GameTooltip:Show()
        end)
        tipOwner:HookScript("OnLeave", function() GameTooltip:Hide() end)
        y = y - (32 + ROW_GAP)
    end

    -- Moved from Advanced > Keybindings (ALL-84)
    y = MakeKeybindRow(ct, y, L["CFG_KB_NEW_NOTE"],
        "BIGNOTEBOXNEWNOTE",   "(" .. string.format(L["SW_KB_DEFAULT_FMT"], "F8") .. ")", L["CFG_KB_DESC_NEW_NOTE"])

    -- nil = on (the old behaviour); read by BNB.OpenConfigOnNew (UI/MainWindow.lua)
    y = AddCheck(ct, y, L["CFG_CHK_OPEN_CONFIG_NEW_LABEL"],
        function() return db.openConfigOnNew ~= false end,
        function(v) if v then db.openConfigOnNew = nil else db.openConfigOnNew = false end end,
        L["CFG_CHK_OPEN_CONFIG_NEW_TIP"])

    local lockRowY = y
    local lockCb
    y, lockCb = AddCheck(ct, y, L["CFG_CHK_LOCK_NOTES_LABEL"],
        function() return db.lockNotes == true end,
        function(v)
            db.lockNotes = v
            -- Refresh the editor lock state for the currently open note
            if BNB.RefreshEditorLock then BNB.RefreshEditorLock() end
            if BNB.Sticky and BNB.Sticky.RefreshLockIcons then BNB.Sticky.RefreshLockIcons() end
        end,
        L["CFG_CHK_LOCK_NOTES_TIP"])

    -- Reset all: every note with its own lock (note.locked true/false, written
    -- by any Lock / Unlock) follows the setting above again (nil). Not an
    -- edit, so "Edited" sort stays put (noTouch).
    do
        local function Overrides()
            local ids, ndb = {}, BNB.NotesDB()
            for id, n in pairs(ndb and ndb.notes or {}) do
                if n.locked ~= nil then ids[#ids + 1] = id end
            end
            return ids
        end
        local btn = BNB.CreateButton(nil, ct, L["CFG_LOCK_RESET_BTN"], 90, 22)
        btn:SetPoint("TOPRIGHT", ct, "TOPRIGHT", 0, lockRowY + 1)
        lockCb._lbl:SetPoint("RIGHT", btn, "LEFT", -6, 0)
        btn:SetMotionScriptsWhileDisabled(true)   -- the tooltip explains the grey
        local function Refresh() btn:SetEnabled(#Overrides() > 0) end
        btn:HookScript("OnShow", Refresh)
        btn:SetScript("OnEnter", function(s)
            GameTooltip:SetOwner(s, "ANCHOR_TOP")
            GameTooltip:AddLine(L["CFG_LOCK_RESET_BTN"], 1, 0.82, 0)
            GameTooltip:AddLine(s:IsEnabled() and L["CFG_LOCK_RESET_TIP"] or L["CFG_LOCK_RESET_NONE"],
                0.85, 0.85, 0.85, true)
            GameTooltip:Show()
        end)
        btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
        btn:SetScript("OnClick", function()
            local ids = Overrides()
            if #ids == 0 then Refresh(); return end
            StaticPopup_Show("BNB_MULTI_CONFIRM", string.format(L["CFG_LOCK_RESET_CONFIRM"], #ids), nil, function()
                for _, id in ipairs(Overrides()) do
                    BNB.UpdateNote(id, { _clear = { "locked" } }, { noTouch = true })
                end
                if BNB.RefreshEditorLock then BNB.RefreshEditorLock() end
                if BNB.Sticky and BNB.Sticky.RefreshLockIcons then BNB.Sticky.RefreshLockIcons() end
                if BNB.LoadNoteInEditor and BNB._currentNoteID then BNB.LoadNoteInEditor(BNB._currentNoteID) end
                if BNB.RefreshReferenceBox then BNB.RefreshReferenceBox() end
                Refresh()
            end)
        end)
        -- A Lock / Unlock anywhere else while Settings is open
        BNB.RegisterMessage("ConfigLockReset", "NoteChanged", function(_, _, fields)
            if fields and (fields.locked ~= nil or fields._clear) and btn:IsVisible() then Refresh() end
        end)
    end

    -- Trash and Tag tree are part of how notes work, not modules (ALL-84)
    y = AddSubHeader(ct, y, L["CFG_HDR_TRASH"])
    -- ── Trash enable/disable checkbox ─────────────────────────────────────────
    -- Capture all child widget refs so we can grey them out when disabled.
    local trashEnableCb = CreateFrame("CheckButton", nil, ct, "UICheckButtonTemplate")
    trashEnableCb:SetSize(24, 24)
    trashEnableCb:SetPoint("TOPLEFT", ct, "TOPLEFT", -2, y + 2)
    trashEnableCb:SetChecked(db.trashFeature ~= false)
    local trashEnableLbl = ct:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    trashEnableLbl:SetPoint("LEFT",  trashEnableCb, "RIGHT", 4, 0)
    trashEnableLbl:SetPoint("RIGHT", ct, "RIGHT", 0, 0)
    trashEnableLbl:SetJustifyH("LEFT"); trashEnableLbl:SetHeight(ROW_H)
    trashEnableLbl:SetText(L["CFG_TRASH_ENABLE_LABEL"])
    y = y - (ROW_H + ROW_GAP)

    -- ── Warn before deleting checkbox ─────────────────────────────────────────
    local warnCb = CreateFrame("CheckButton", nil, ct, "UICheckButtonTemplate")
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
    local warnLbl = ct:CreateFontString(nil, "OVERLAY", "GameFontNormal")
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

    -- ── Apply greying / trash button visibility ────────────────────────────────
    local function ApplyTrashSection(enabled)
        local a = enabled and 1 or 0.35
        warnCb:SetEnabled(enabled)
        warnCb:SetAlpha(a)
        warnLbl:SetAlpha(a)
        retainSlider:SetAlpha(a)
        retainSlider:SetEnabled(enabled)
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

    y = AddSubHeader(ct, y, L["CFG_TAGTREE_HEADER"])
    y = AddCheck(ct, y, L["CFG_TAGTREE_STAY_OPEN"],
        function() return db.tagTreeStayOpen ~= false end,
        function(v) db.tagTreeStayOpen = v end,
        L["CFG_TAGTREE_STAY_OPEN_TIP"])

    y = AddCheck(ct, y, L["CFG_TAGTREE_START_EXPANDED"],
        function() return db.tagTreeStartExpanded == true end,
        function(v) db.tagTreeStartExpanded = v end,
        L["CFG_TAGTREE_START_EXPANDED_TIP"])

    y = AddRule(ct, y) - 4

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
        local lbl = ct:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
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
        local lbl = ct:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
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

K.BUILDERS.notes = BuildNotesTab

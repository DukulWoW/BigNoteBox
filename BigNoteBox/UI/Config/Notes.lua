-- BigNoteBox UI/Config/Notes.lua - Settings Notes tab (was Editor, ALL-84)
-- Split out of ConfigWindow.lua (ALL-65.10).

local BNB = BigNoteBox
local L   = BNB.L

local K = BNB._ConfigKit
local CONTENT_W, ROW_H, ROW_GAP, SLIDER_H = K.CONTENT_W, K.ROW_H, K.ROW_GAP, K.SLIDER_H
local AddRule, AddHeader, AddCheck, MakeKeybindRow = K.AddRule, K.AddHeader, K.AddCheck, K.MakeKeybindRow

-- A smaller gold heading for a group inside a section (Trash, Tag tree under Notes).
local function AddSubHeader(ct, y, text)
    local lbl = ct:CreateFontString(nil, "OVERLAY", "BNBFontNormal")
    lbl:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y - 6)
    BNB.SetHeaderColor(lbl)
    lbl:SetText(text)
    return y - 26
end

-- ─────────────────────────────────────────────────────────────────────────────
-- TAB 2 -- NOTES
-- Notes (new note, lock, tag tree), then the editor: saving, toolbar,
-- undo/redo. Trash, rich notes + live preview and session history are
-- Modules pages since ALL-290 (UI/Config/NotePages.lua).
-- ─────────────────────────────────────────────────────────────────────────────
local function BuildNotesTab(sf, ct)
    local db = BigNoteBoxDB
    local y  = -8

    -- ── Notes (moved from the Features tab, ALL-84) ─────────────────────────────
    y = AddHeader(ct, y, L["CFG_HDR_NOTES"])

    -- New note behaviour dropdown
    do
        local lbl = ct:CreateFontString(nil, "OVERLAY", "BNBFontNormal")
        lbl:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
        lbl:SetHeight(ROW_H); lbl:SetJustifyH("LEFT")
        lbl:SetText(L["CFG_NEWNOTE_BEHAVIOUR"])
        y = y - (ROW_H + 2)

        local NEW_NOTE_ITEMS = {
            { key = "prompt",    label = L["CFG_NEWNOTE_ITEM_PROMPT"] },
            { key = "immediate", label = L["CFG_NEWNOTE_ITEM_IMMEDIATE"]             },
        }
        local curBehaviour = db.newNoteBehaviour or "prompt"
        local nnDD = BNB.SkinDropdown(CreateFrame("DropdownButton", nil, ct, "WowStyle1DropdownTemplate"))
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

    -- Which character a new note belongs to (ALL-267); nil = the selected
    -- tab. Read by BNB.NewNoteScope (Core/NoteManager.lua), which the New
    -- note dialog's character dropdown starts on.
    do
        local lbl = ct:CreateFontString(nil, "OVERLAY", "BNBFontNormal")
        lbl:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
        lbl:SetHeight(ROW_H); lbl:SetJustifyH("LEFT")
        lbl:SetText(L["CFG_NEWNOTE_SCOPE"])
        y = y - (ROW_H + 2)

        local scDD = BNB.CreateValueDropdown(ct, {
                { label = L["CFG_NEWNOTE_SCOPE_FOLLOW"], value = "follow" },
                { label = L["CFG_NEWNOTE_SCOPE_GLOBAL"], value = "global" },
                { label = L["CFG_NEWNOTE_SCOPE_CHAR"],   value = "char"   },
            }, db.newNoteScope or "follow",
            function(v) db.newNoteScope = (v ~= "follow") and v or nil end,
            CONTENT_W, 26)
        scDD:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
        local tipOwner = scDD._dd or scDD
        tipOwner:HookScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(L["CFG_NEWNOTE_SCOPE"], 1, 1, 1)
            GameTooltip:AddLine(L["CFG_NEWNOTE_SCOPE_TIP"], 0.8, 0.8, 0.8, true)
            GameTooltip:Show()
        end)
        tipOwner:HookScript("OnLeave", function() GameTooltip:Hide() end)
        y = y - (32 + ROW_GAP)
    end

    -- What double-clicking a note in the list does (ALL-100); nil = settings
    do
        local lbl = ct:CreateFontString(nil, "OVERLAY", "BNBFontNormal")
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

    y = AddSubHeader(ct, y, L["CFG_TAGTREE_HEADER"])
    y = AddCheck(ct, y, L["CFG_TAGTREE_STAY_OPEN"],
        function() return db.tagTreeStayOpen ~= false end,
        function(v) db.tagTreeStayOpen = v end,
        L["CFG_TAGTREE_STAY_OPEN_TIP"])

    y = AddCheck(ct, y, L["CFG_TAGTREE_START_EXPANDED"],
        function() return db.tagTreeStartExpanded == true end,
        function(v) db.tagTreeStartExpanded = v end,
        L["CFG_TAGTREE_START_EXPANDED_TIP"])

    -- Which side the Tag Manager opens on (ALL-269)
    y = K.AddSideRow(ct, y, L["CFG_SIDE_TAGMGR"], "tagManagerSide", "BigNoteBoxTagManagerFrame")

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

    local tbDesc = ct:CreateFontString(nil, "OVERLAY", "BNBFontNormalSmall")
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

    -- The same toolbar in the Focus mode editor, writing tools only (ALL-163)
    y = AddCheck(ct, y, L["CFG_CHK_FOCUS_WYSIWYG_LABEL"],
        function() return db.focusWysiwygBar ~= false end,
        function(v)
            db.focusWysiwygBar = v
            if BNB.ApplyFocusWysiwygBar then BNB.ApplyFocusWysiwygBar() end
        end,
        L["CFG_CHK_FOCUS_WYSIWYG_TIP"])

    -- ── Undo / Redo ───────────────────────────────────────────────────────────
    AddRule(ct, y); y = y - 18
    y = AddHeader(ct, y, L["CFG_HDR_UNDO_REDO"])

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

    sf:FinaliseHeight(math.abs(y) + 12)
end

K.BUILDERS.notes = BuildNotesTab

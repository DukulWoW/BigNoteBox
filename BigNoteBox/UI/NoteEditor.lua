-- BigNoteBox UI/NoteEditor.lua — Right pane note editor

local BNB = BigNoteBox
local L   = BNB.L

BNB._coordWaypoint = nil  -- TomTom UID of the current BNB coord waypoint, or nil

local TOOLBAR_H   = 36
local MARKUP_H    = 24   -- height of the rich note markup toolbar
local PAD         = 8
local TSTAMP_H    = 16   -- height of the timestamp strip below title
local CHIP_ROW_H  = 22   -- height of one row of tag chips
local TAG_STRIP_H = CHIP_ROW_H  -- kept for legacy references; strip grows dynamically

local saveBtn  -- forward ref

-- Debounce timers for undo snapshots, keyed by noteID
local _undoTimers  = {}
-- Forced-interval timers — fire every 3s regardless of typing speed
local _undoForced  = {}
-- Shared with UI/WysiwygBar.lua (undo/redo cancel pending snapshots). Both tables
-- keep their identity: clear entries, never reassign the locals.
BNB._EditorKit = { undoTimers = _undoTimers, undoForced = _undoForced }

--------------------------------------------------------------------------------
-- LOCK HELPERS
-- A note is locked when:
--   note.locked == true                  (explicit per-note lock)
--   note.locked == nil AND db.lockNotes  (follows global setting)
-- It is explicitly unlocked when:
--   note.locked == false                 (explicit per-note override)
--------------------------------------------------------------------------------
local function NoteIsLocked(note)
    if not note then return false end
    if note.locked == true  then return true  end
    if note.locked == false then return false end
    return BigNoteBoxDB.lockNotes == true
end

--------------------------------------------------------------------------------
-- SAVE BUTTON STATE
--------------------------------------------------------------------------------
function BNB.UpdateSaveButtonState()
    if not saveBtn then return end
    local enabled = BNB._dirty == true
    saveBtn:SetEnabled(enabled)
    saveBtn:SetAlpha(enabled and 1.0 or 0.4)
    pcall(function() saveBtn._tx:SetDesaturated(not enabled) end)
    -- Keep focus button in sync: disabled when no note is selected
    local hasNote = BNB._currentNoteID ~= nil
    if BNB._focusModeBtn then
        BNB._focusModeBtn:SetEnabled(hasNote)
        BNB._focusModeBtn:SetAlpha(hasNote and 1.0 or 0.35)
        pcall(function() BNB._focusModeBtn._n:SetDesaturated(not hasNote) end)
    end
    -- Share button: enabled whenever a note is selected
    if BNB._wysiwygShareBtn then
        BNB._wysiwygShareBtn:SetIconEnabled(hasNote)
    end
end

BNB.MarkDirty = function()
    BNB._dirty = true
    BNB.UpdateSaveButtonState()
    if BNB.ScheduleAutoSave then BNB.ScheduleAutoSave() end   -- ALL-52
end

-- Automatic save mode hides the Save button and closes its gap: the buttons
-- after it are anchored at fixed x offsets, so each moves left by one slot.
-- _baseX is recorded once, when the toolbar is built.
local SAVE_SLOT_W = 32
function BNB.ApplySaveMode()
    local bar = BNB._editorToolbar
    if not (bar and saveBtn) then return end
    local auto = BNB.IsAutoSave and BNB.IsAutoSave()
    saveBtn:SetShown(not auto)
    for _, c in ipairs({ bar:GetChildren() }) do
        if c._baseX then
            c:ClearAllPoints()
            c:SetPoint("LEFT", bar, "LEFT", c._baseX - (auto and SAVE_SLOT_W or 0), 0)
        end
    end
end

--------------------------------------------------------------------------------
-- TIMESTAMP FORMATTING
-- Respects BigNoteBoxDB.dateFormat and BigNoteBoxDB.use24Hour.
-- Relative format uses coarse buckets (< 1m, < 1h, < 1d, < 7d, < 30d, etc.)
--------------------------------------------------------------------------------
local function FmtTime(ts)
    if not ts or ts == 0 then return "" end
    local db       = BigNoteBoxDB
    local fmt      = db and db.dateFormat or "YYYY-MM-DD"
    local use24    = db == nil or db.use24Hour ~= false

    if fmt == "relative" then
        local diff = time() - ts
        if diff < 60         then return L["REL_JUST_NOW"]
        elseif diff < 3600   then return string.format(L["REL_MIN_AGO_FMT"],    math.floor(diff/60))
        elseif diff < 86400  then return string.format(L["REL_HOUR_AGO_FMT"],   math.floor(diff/3600))
        elseif diff < 604800 then return string.format(L["REL_DAY_AGO_FMT"],    math.floor(diff/86400))
        elseif diff < 2592000 then return string.format(L["REL_WEEK_AGO_FMT"],  math.floor(diff/604800))
        elseif diff < 31536000 then return string.format(L["REL_MONTH_AGO_FMT"], math.floor(diff/2592000))
        else return string.format(L["REL_YEAR_AGO_FMT"], math.floor(diff/31536000)) end
    end

    -- Build date part
    local datePart
    if fmt == "DD-MM-YYYY" then
        datePart = date("%d-%m-%Y", ts)
    elseif fmt == "MM-DD-YYYY" then
        datePart = date("%m-%d-%Y", ts)
    else  -- YYYY-MM-DD (default)
        datePart = date("%Y-%m-%d", ts)
    end

    -- Build time part
    local timePart
    if use24 then
        timePart = date("%H:%M", ts)
    else
        local h = tonumber(date("%H", ts))
        local m = date("%M", ts)
        local ampm = h >= 12 and "pm" or "am"
        h = h % 12; if h == 0 then h = 12 end
        timePart = h .. ":" .. m .. " " .. ampm
    end

    return datePart .. " " .. timePart
end
-- Shared with UI/FocusEditor.lua (called at runtime, so load order does not matter)
BNB.FmtTime = FmtTime

--------------------------------------------------------------------------------
-- TITLE FIELD
-- AddPlaceholder called ONCE at build time.
--------------------------------------------------------------------------------
local function BuildTitleField(parent)
    local bg = BNB.CreateBackdropFrame("Frame", nil, parent)
    bg:SetPoint("TOPLEFT",  parent, "TOPLEFT",  PAD,  -PAD)
    bg:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -PAD, -PAD)
    bg:SetHeight(36)
    BNB.SetBackdrop(bg, 0.06, 0.06, 0.09, 0, 0.30, 0.30, 0.32, 0)

    local eb = CreateFrame("EditBox", nil, bg)
    eb:SetPoint("TOPLEFT",    bg, "TOPLEFT",    6, 0)
    eb:SetPoint("BOTTOMRIGHT",bg, "BOTTOMRIGHT",-6, 0)
    local boldPath = BNB.GetBoldFont and BNB.GetBoldFont()
    if boldPath then
        pcall(function() eb:SetFont(boldPath, 20, "") end)
    else
        local font, _, flags = GameFontNormalHuge:GetFont()
        if font then eb:SetFont(font, 20, flags or "")
        else eb:SetFontObject("GameFontNormalLarge") end
    end
    eb:SetAutoFocus(false)
    eb:SetMaxLetters(200)
    eb:SetTextInsets(2, 2, 2, 2)

    -- Underline (always visible)
    local underline = parent:CreateTexture(nil, "ARTWORK")
    underline:SetHeight(1)
    underline:SetPoint("TOPLEFT",  bg, "BOTTOMLEFT",  0, -1)
    underline:SetPoint("TOPRIGHT", bg, "BOTTOMRIGHT", 0, -1)
    underline:SetColorTexture(0.16, 0.16, 0.18, 1)

    -- Timestamp strip anchored below the underline
    local tsStrip = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    tsStrip:SetPoint("TOPLEFT",  underline, "BOTTOMLEFT",  2, -2)
    tsStrip:SetPoint("TOPRIGHT", underline, "BOTTOMRIGHT", -2, -2)
    tsStrip:SetHeight(TSTAMP_H)
    tsStrip:SetJustifyH("LEFT")
    tsStrip:SetText("")
    if BigNoteBoxDB and BigNoteBoxDB.skinMode and BNB.GetSkinPreset then
        local p = BNB.GetSkinPreset()
        local br, bg_, bb = BNB.SkinBorderOf(p)
        tsStrip:SetTextColor(br * 0.90, bg_ * 0.90, bb * 0.90)
        BNB.RegisterSkinLabel(tsStrip, 0.90)
    else
        tsStrip:SetTextColor(0.55, 0.55, 0.55)
    end

    -- Invisible hover frame over the timestamp strip.
    -- Always shows full detail tooltip: absolute dates, zone, and coords.
    local tsHover = CreateFrame("Frame", nil, parent)
    tsHover:SetPoint("TOPLEFT",  underline, "BOTTOMLEFT",  0, -1)
    tsHover:SetPoint("TOPRIGHT", underline, "BOTTOMRIGHT", 0, -1)
    tsHover:SetHeight(TSTAMP_H + 2)
    tsHover:EnableMouse(true)
    tsHover:SetScript("OnEnter", function(self)
        local note = BNB._currentNoteID and BNB.GetNote(BNB._currentNoteID)
        if not note then return end
        local db    = BigNoteBoxDB
        local use24 = db == nil or db.use24Hour ~= false
        local function AbsTime(ts)
            if not ts or ts == 0 then return nil end
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
            return d .. " " .. t
        end
        local created = note.created and AbsTime(note.created)
        local updated = note.updated and AbsTime(note.updated)
        if not created and not updated then return end
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        if created then GameTooltip:AddLine(string.format(L["NE_CREATED_FMT"], created), 0.7, 0.7, 0.7) end
        if updated then GameTooltip:AddLine(string.format(L["NE_EDITED_FMT"], updated), 0.7, 0.7, 0.7) end
        local zone = note.coordZone or L["CFG_EXPORT_UNKNOWN_AUTHOR"]
        GameTooltip:AddLine(string.format(L["NE_ZONE_FMT"], zone), 0.7, 0.7, 0.7)
        if note.coordX and note.coordY then
            GameTooltip:AddLine(string.format(L["NE_COORDS_FMT"], note.coordX, note.coordY), 0.7, 0.7, 0.7)
        end
        GameTooltip:Show()
    end)
    tsHover:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Word/char count label (M) — right-aligned in the same strip
    local statsStrip = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    statsStrip:SetPoint("TOPRIGHT",  underline, "BOTTOMRIGHT", -2, -2)
    statsStrip:SetPoint("TOPLEFT",   underline, "BOTTOMLEFT",  2,  -2)
    statsStrip:SetHeight(TSTAMP_H)
    statsStrip:SetJustifyH("RIGHT")
    statsStrip:SetText("")
    if BigNoteBoxDB and BigNoteBoxDB.skinMode and BNB.GetSkinPreset then
        local p = BNB.GetSkinPreset()
        local br, bg_, bb = BNB.SkinBorderOf(p)
        statsStrip:SetTextColor(br * 0.90, bg_ * 0.90, bb * 0.90)
        BNB.RegisterSkinLabel(statsStrip, 0.90)
    else
        statsStrip:SetTextColor(0.55, 0.55, 0.55)
    end

    local phFocusGained, phFocusLost

    eb:SetScript("OnEditFocusGained", function(self)
        if bg.SetBackdropColor then
            bg:SetBackdropColor(0.06, 0.06, 0.09, 0.85)
            bg:SetBackdropBorderColor(0.35, 0.35, 0.38, 1)
        end
        if phFocusGained then phFocusGained(self) end
    end)
    eb:SetScript("OnEditFocusLost", function(self)
        if bg.SetBackdropColor then
            bg:SetBackdropColor(0.06, 0.06, 0.09, 0)
            bg:SetBackdropBorderColor(0.30, 0.30, 0.32, 0)
        end
        if phFocusLost then phFocusLost(self) end
    end)

    BNB.AddPlaceholder(eb, L["NOTE_TITLE_HINT"], 0.35, 0.35, 0.35)

    phFocusGained = eb:GetScript("OnEditFocusGained")
    phFocusLost   = eb:GetScript("OnEditFocusLost")
    eb:SetScript("OnEditFocusGained", function(self)
        if bg.SetBackdropColor then
            bg:SetBackdropColor(0.06, 0.06, 0.09, 0.85)
            bg:SetBackdropBorderColor(0.35, 0.35, 0.38, 1)
        end
        if phFocusGained then phFocusGained(self) end
    end)
    -- Cancel an unsaved new note: if the title is empty when focus leaves the
    -- title box, check whether this is a "pending new note" (_pendingNewNoteID).
    -- If it is pending AND focus didn't move to the body or NoteConfig, show a
    -- discard confirmation popup. If the title has text, clear the pending flag
    -- (note is now named — clicking away just saves normally).
    local function MaybeCancelNewNote()
        local id = BNB._currentNoteID
        if not id then return end
        local note = BNB.GetNote(id)
        if not note then return end
        local liveTitle = eb._showingPlaceholder and "" or (eb:GetText() or "")

        -- If title now has text, this note is no longer "pending" — nothing to do.
        if liveTitle ~= "" then
            if BNB._pendingNewNoteID == id then BNB._pendingNewNoteID = nil end
            return
        end

        -- Only act on pending new notes (notes created via CreateNewNote with no title yet).
        if BNB._pendingNewNoteID ~= id then return end

        -- Check where focus went. If it went to the body or to NoteConfig, leave
        -- the note alive — the user is still working on it.
        local kf = GetCurrentKeyboardFocus and GetCurrentKeyboardFocus()
        if kf == BNB._editorBody then return end
        local nc = _G["BigNoteBoxNoteConfigFrame"]
        if nc and nc:IsShown() then return end

        -- Focus went elsewhere — show the discard popup.
        StaticPopup_Show("BNB_DISCARD_NEW_NOTE")
    end

    -- Register the discard confirmation popup (once, idempotent).
    if not StaticPopupDialogs["BNB_DISCARD_NEW_NOTE"] then
        StaticPopupDialogs["BNB_DISCARD_NEW_NOTE"] = {
            text      = L["NE_DISCARD_POPUP_TEXT"],
            button1   = L["NE_DISCARD_BTN"],
            button2   = L["NE_KEEP_EDITING_BTN"],
            OnAccept  = function()
                local id = BNB._pendingNewNoteID
                BNB._pendingNewNoteID = nil
                if not id then return end
                BNB._currentNoteID = nil
                if BNB.PurgeNote        then BNB.PurgeNote(id) end
                if BNB.RefreshNoteList  then BNB.RefreshNoteList() end
                if BNB.LoadNoteInEditor then BNB.LoadNoteInEditor(nil) end
                -- Close NoteConfig if it was open for this note
                local nc = _G["BigNoteBoxNoteConfigFrame"]
                if nc and nc:IsShown() then nc:Hide() end
            end,
            OnCancel  = function()
                -- "Keep Editing" — re-focus the title field
                C_Timer.After(0.05, function()
                    if BNB._editorTitle then BNB._editorTitle:SetFocus() end
                end)
            end,
            timeout = 0, whileDead = true, hideOnEscape = false,
        }
    end

    eb:SetScript("OnEditFocusLost", function(self)
        if bg.SetBackdropColor then
            bg:SetBackdropColor(0.06, 0.06, 0.09, 0)
            bg:SetBackdropBorderColor(0.30, 0.30, 0.32, 0)
        end
        if phFocusLost then phFocusLost(self) end
        -- Defer so a click on the body editbox or NoteConfig registers first
        C_Timer.After(0.1, MaybeCancelNewNote)
    end)

    eb:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
        MaybeCancelNewNote()
    end)
    eb:SetScript("OnEnterPressed",  function(self)
        self:ClearFocus()
        if BNB._editorBody then BNB._editorBody:SetFocus() end
    end)
    eb:SetScript("OnTextChanged", function(self, userInput)
        if userInput and not self._showingPlaceholder then
            BNB.MarkDirty()
            -- Once the user has typed a title, the note is no longer "pending"
            local liveTitle = self._showingPlaceholder and "" or (self:GetText() or "")
            if liveTitle ~= "" and BNB._pendingNewNoteID == BNB._currentNoteID then
                BNB._pendingNewNoteID = nil
            end
            -- Live-sync NoteConfig title bar as the user types
            if BNB._syncNoteConfigTitle then BNB._syncNoteConfigTitle() end
        end
    end)

    return bg, eb, underline, tsStrip, statsStrip
end

--------------------------------------------------------------------------------
-- STATS STRIP (M) — "1,234 chars  •  187 words"
-- Right-aligned FontString in the timestamp strip row.
-- Updated on every body OnTextChanged and on note load.
--------------------------------------------------------------------------------
local function UpdateStatsStrip(text)
    local strip = BNB._editorStatsStrip
    if not strip then return end
    if not text or text == "" then
        strip:SetText(L["NE_STATS_EMPTY"])
        return
    end
    local chars = #text
    local words = 0
    for _ in text:gmatch("%S+") do words = words + 1 end
    local function fmt(n)
        local s      = tostring(n)
        local result = ""
        local len    = #s
        for i = 1, len do
            if i > 1 and (len - i + 1) % 3 == 0 then result = result .. "," end
            result = result .. s:sub(i, i)
        end
        return result
    end
    strip:SetText(string.format(L["NE_STATS_FMT"], fmt(chars), fmt(words)))
end

--------------------------------------------------------------------------------
-- BODY SCROLL EDITBOX
-- AddPlaceholder called ONCE at build time.
-- topAnchor: the frame to anchor TOPLEFT to (WYSIWYG bar, or tsStrip if bar
-- is hidden). BNB.UpdateBodyTopAnchor() re-anchors live on bar toggle.
--------------------------------------------------------------------------------
local function BuildBodyField(parent, topAnchor)
    local bodyPath, bodySize
    if BNB.GetBodyFont then
        bodyPath, bodySize = BNB.GetBodyFont()
    end
    bodySize = bodySize or (BigNoteBoxDB and BigNoteBoxDB.fontSize) or 12

    local sf, eb = BNB.CreateScrolledEditBox("BigNoteBoxBodyScroll", parent, bodySize)
    if bodyPath then
        pcall(function() eb:SetFont(bodyPath, bodySize, "") end)
    end

    sf:SetPoint("TOPLEFT",     topAnchor, "BOTTOMLEFT",  PAD, -4)
    sf:SetPoint("BOTTOMRIGHT", parent,    "BOTTOMRIGHT", -22,  TOOLBAR_H + TAG_STRIP_H + PAD)

    BNB.AddPlaceholder(eb, L["NOTE_BODY_HINT"], 0.35, 0.35, 0.35)

    -- Drag-and-drop + Insert Info right-click menu
    if BNB.WireDropTarget       then BNB.WireDropTarget(eb)       end
    if BNB.WireInsertInfoTarget  then BNB.WireInsertInfoTarget(eb) end

    eb:SetScript("OnTextChanged", function(self, userInput)
        if not self._showingPlaceholder then
            if userInput then
                BNB.MarkDirty()
                -- Notify live preview directly (hooksecurefunc on MarkDirty is
                -- unreliable for plain Lua closures — call directly instead)
                if BNB.RichPreview then BNB.RichPreview.ScheduleRender() end
                if BNB._editorBodyScroll and BNB._editorBodyScroll.UpdateScrollbar then
                    BNB._editorBodyScroll:UpdateScrollbar()
                end
                -- Undo snapshot — hybrid debounce + forced interval.
                -- Both timings are user-configurable in Config > Editor.
                local id = BNB._currentNoteID
                if id and not BNB._undoActive then
                    local idleDelay = (BigNoteBoxDB and BigNoteBoxDB.undoIdleDelay)    or 0.8
                    local forcedInt = (BigNoteBoxDB and BigNoteBoxDB.undoForcedInterval) or 3.0
                    -- First snapshot for this note: push immediately so Undo
                    -- always has a "before" state to return to.
                    if not BNB._undoSnap[id] or BNB._undoStack[id] == nil then
                        BNB.UndoPush(id, self:GetText() or "", self:GetCursorPosition() or 0)
                        if BNB._refreshUndoButtons then BNB._refreshUndoButtons() end
                    else
                        -- Reset idle debounce
                        if _undoTimers[id] then
                            _undoTimers[id]:Cancel()
                            _undoTimers[id] = nil
                        end
                        _undoTimers[id] = C_Timer.NewTimer(idleDelay, function()
                            _undoTimers[id] = nil
                            -- Also cancel any forced-interval timer -- idle won
                            if _undoForced and _undoForced[id] then
                                _undoForced[id]:Cancel()
                                _undoForced[id] = nil
                            end
                            if not BNB._undoActive then
                                BNB.UndoPush(id, self:GetText() or "", self:GetCursorPosition() or 0)
                                if BNB._refreshUndoButtons then BNB._refreshUndoButtons() end
                            end
                        end)
                        -- Start forced-interval timer only if not already running
                        if not _undoForced then _undoForced = {} end
                        if not _undoForced[id] then
                            _undoForced[id] = C_Timer.NewTimer(forcedInt, function()
                                _undoForced[id] = nil
                                -- Cancel the idle debounce -- forced wins
                                if _undoTimers[id] then
                                    _undoTimers[id]:Cancel()
                                    _undoTimers[id] = nil
                                end
                                if not BNB._undoActive then
                                    BNB.UndoPush(id, self:GetText() or "", self:GetCursorPosition() or 0)
                                    if BNB._refreshUndoButtons then BNB._refreshUndoButtons() end
                                end
                            end)
                        end
                    end
                end
            end
            UpdateStatsStrip(self:GetText())
        end
    end)

    -- Ctrl+Z = undo, Ctrl+Shift+Z or Ctrl+Y = redo.
    -- We only call SetPropagateKeyboardInput(false) for keys we consume.
    -- EditBox absorbs all other input natively — no else branch needed.
    eb:SetScript("OnKeyDown", function(self, key)
        local ctrl  = IsControlKeyDown()
        local shift = IsShiftKeyDown()

        if ctrl and key == "Z" and not shift then
            -- Undo
            self:SetPropagateKeyboardInput(false)
            local id = BNB._currentNoteID
            if id and BNB.UndoCanUndo(id) and not BNB._editorLocked then
                -- Cancel pending debounce and forced-interval timer
                if _undoTimers[id] then _undoTimers[id]:Cancel(); _undoTimers[id] = nil end
                if _undoForced[id]  then _undoForced[id]:Cancel();  _undoForced[id]  = nil end
                BNB._undoActive = true
                local text, cursor = BNB.UndoStep(id)
                if text then
                    self:SetText(text)
                    C_Timer.After(0, function() self:SetCursorPosition(cursor or 0) end)
                    BNB.MarkDirty()
                end
                BNB._undoActive = false
                if BNB._refreshUndoButtons then BNB._refreshUndoButtons() end
            end

        elseif ctrl and ((key == "Z" and shift) or key == "Y") then
            -- Redo
            self:SetPropagateKeyboardInput(false)
            local id = BNB._currentNoteID
            if id and BNB.UndoCanRedo(id) and not BNB._editorLocked then
                if _undoTimers[id] then _undoTimers[id]:Cancel(); _undoTimers[id] = nil end
                if _undoForced[id]  then _undoForced[id]:Cancel();  _undoForced[id]  = nil end
                BNB._undoActive = true
                local text, cursor = BNB.RedoStep(id)
                if text then
                    self:SetText(text)
                    C_Timer.After(0, function() self:SetCursorPosition(cursor or 0) end)
                    BNB.MarkDirty()
                end
                BNB._undoActive = false
                if BNB._refreshUndoButtons then BNB._refreshUndoButtons() end
            end
        end
    end)

    return sf, eb
end

--------------------------------------------------------------------------------
-- PUBLIC: re-anchor body scroll top when wysiwyg bar is shown/hidden.
-- Also handles markup bar (rich notes) and render frame (view mode).
-- Called by ToggleWysiwygBar and rich mode enter/exit.
--------------------------------------------------------------------------------
function BNB.UpdateBodyTopAnchor()
    local sf   = BNB._editorBodyScroll
    local rsf  = BNB._editorRenderScroll
    local bar  = BNB._editorWysiwygBar
    local mbar = BNB._editorMarkupBar
    local ts   = BNB._editorTimestamp
    if not ts then return end

    -- Build anchor chain: tsStrip -> wysiwygBar (if shown) -> markupBar (if shown)
    local topAnchor = ts
    if bar  and bar:IsShown()  then topAnchor = bar  end
    if mbar and mbar:IsShown() then topAnchor = mbar end

    local bottomOffset = TOOLBAR_H
        + (BNB._editorTagStrip and BNB._editorTagStrip:GetHeight() or TAG_STRIP_H)
        + PAD

    if sf then
        sf:ClearAllPoints()
        sf:SetPoint("TOPLEFT",     topAnchor,      "BOTTOMLEFT",  PAD, -4)
        sf:SetPoint("BOTTOMRIGHT", BNB.editorPane, "BOTTOMRIGHT", -22, bottomOffset)
    end
    if rsf then
        rsf:ClearAllPoints()
        rsf:SetPoint("TOPLEFT",     topAnchor,      "BOTTOMLEFT",  PAD, -4)
        rsf:SetPoint("BOTTOMRIGHT", BNB.editorPane, "BOTTOMRIGHT", -22, bottomOffset)
    end
end

--------------------------------------------------------------------------------
-- PUBLIC: toggle WYSIWYG bar visibility (called from Config checkbox)
--------------------------------------------------------------------------------
function BNB.ToggleWysiwygBar(shown)
    local bar = BNB._editorWysiwygBar
    if not bar then return end
    local db = BigNoteBoxDB
    if shown == nil then
        shown = not bar:IsShown()
    end
    if shown then bar:Show() else bar:Hide() end
    if db then db.wysiwygBarVisible = shown end
    BNB.UpdateBodyTopAnchor()
end

--------------------------------------------------------------------------------
-- TOOLBAR
-- Layout (left -> right): Save | Delete | Duplicate | Edit(locked) | Pin
-- Right side: Send | [tag chips + add-tag input]
--------------------------------------------------------------------------------
local function BuildToolbar(parent)
    local bar = CreateFrame("Frame", nil, parent)
    bar:SetPoint("BOTTOMLEFT",  parent, "BOTTOMLEFT",  0, 0)
    bar:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, 0)
    bar:SetHeight(TOOLBAR_H)

    local sep = BNB.CreateDivider(parent, "HORIZONTAL", 0.16, 0.16, 0.18, 0.20)
    sep:SetPoint("BOTTOMLEFT",  parent, "BOTTOMLEFT",  0, TOOLBAR_H)
    sep:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -1, TOOLBAR_H)

    -- Icon button helper — 26×26, texture from Assets/
    -- Returns btn, tx. Calling btn:SetIconEnabled(bool) sets alpha + desaturation.
    -- Hover: button grows to 30×30 and restores to 26×26 on leave (no colour flash).
    local ASSETS = "Interface\\AddOns\\BigNoteBox\\Assets\\"
    local BTN_NORMAL = 26
    local BTN_HOVER  = 30
    local function MakeIconBtn(parent, texName, tip, w, h)
        local btn = CreateFrame("Button", nil, parent)
        local bw = w or BTN_NORMAL
        local bh = h or BTN_NORMAL
        btn:SetSize(bw, bh)
        local tx = btn:CreateTexture(nil, "ARTWORK")
        tx:SetAllPoints()
        tx:SetTexture(ASSETS .. texName)
        btn:SetScript("OnEnter", function(self)
            self:SetSize(bw + 4, bh + 4)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:AddLine(tip, 1, 1, 1)
            GameTooltip:Show()
        end)
        btn:SetScript("OnLeave", function(self)
            self:SetSize(bw, bh)
            GameTooltip:Hide()
        end)
        btn._tx = tx
        -- Helper: set enabled + visual state (alpha + desaturation)
        btn.SetIconEnabled = function(self, enabled)
            self:SetEnabled(enabled)
            self:SetAlpha(enabled and 1.0 or 0.4)
            pcall(function() tx:SetDesaturated(not enabled) end)
        end
        return btn, tx
    end

    -- Save
    saveBtn, _ = MakeIconBtn(bar, "Actionbar\\ab-save", L["BTN_SAVE_NOTE"])
    saveBtn:SetPoint("LEFT", bar, "LEFT", 6, 0)
    saveBtn:SetEnabled(false)
    saveBtn:SetAlpha(0.4)
    pcall(function() saveBtn._tx:SetDesaturated(true) end)
    saveBtn:SetScript("OnClick", function()
        BNB.SaveCurrentNote()
        BNB.UpdateSaveButtonState()
    end)

    -- Reference Box toggle
    do
        local refboxBtn, _ = MakeIconBtn(bar, "Actionbar\\ab-refbox", L["NE_TOGGLE_REFBOX_TIP"])
        refboxBtn:SetPoint("LEFT", bar, "LEFT", 38, 0)
        refboxBtn:SetScript("OnClick", function()
            if BNB.ToggleReferenceBox then BNB.ToggleReferenceBox() end
        end)
        BNB._editorRefBoxBtn = refboxBtn
    end

    -- Tasks button — adds a task to the current note (same as + button in RefBox)
    do
        local tasksBtn, _ = MakeIconBtn(bar, "Actionbar\\ab-tasks", L["NE_ADD_TASK_TIP"])
        tasksBtn:SetPoint("LEFT", bar, "LEFT", 70, 0)
        tasksBtn:SetScript("OnClick", function()
            local id = BNB._currentNoteID; if not id then return end
            local taskID = BNB.Task and BNB.Task.AddTask(id, "")
            if taskID then
                if BNB.OpenReferenceBox then BNB.OpenReferenceBox(id) end
                C_Timer.After(0.05, function()
                    if BNB.FocusTaskEditBox then BNB.FocusTaskEditBox(taskID) end
                end)
            end
        end)
    end

    -- Delete
    local delBtn = MakeIconBtn(bar, "Actionbar\\ab-delete", L["BTN_DELETE_NOTE"])
    delBtn:SetPoint("LEFT", bar, "LEFT", 102, 0)
    delBtn:SetScript("OnClick", function()
        local id = BNB._currentNoteID; if not id then return end
        local note = BNB.GetNote(id);  if not note then return end
        local title = (note.title ~= "" and note.title) or L["UNTITLED"]
        local warn = BigNoteBoxDB and BigNoteBoxDB.warnBeforeDelete ~= false
        if BNB.TrashEnabled and BNB.TrashEnabled() then
            if warn then
                local popup = StaticPopup_Show("BNB_DELETE_NOTE_TRASH", title, nil, id)
                if popup then popup.data = id end
            else
                if BNB.DeleteNote then BNB.DeleteNote(id) end
            end
        else
            if warn then
                local popup = StaticPopup_Show("BNB_DELETE_NOTE", title, nil, id)
                if popup then popup.data = id end
            else
                if BNB.DeleteNote then BNB.DeleteNote(id) end
            end
        end
    end)

    -- Duplicate
    local dupBtn = MakeIconBtn(bar, "Actionbar\\ab-duplicate", L["NE_DUPLICATE_NOTE_TIP"])
    dupBtn:SetPoint("LEFT", bar, "LEFT", 134, 0)
    dupBtn:SetScript("OnClick", function()
        local id = BNB._currentNoteID; if not id then return end
        local src = BNB.GetNote(id);   if not src then return end
        BNB.SaveCurrentNote()
        -- Full copy (rich mode, tasks, attachments...): see BNB.CopyNote
        local newID = BNB.CopyNote(id, {
            title = src.title ~= "" and (src.title .. " (copy)") or "" })
        if not newID then return end
        if BNB.RefreshNoteList then BNB.RefreshNoteList() end
        if BNB.SelectNote      then BNB.SelectNote(newID) end
    end)

    -- Copy to clipboard — copies title + body silently via editbox trick
    local copyBtn = MakeIconBtn(bar, "Actionbar\\ab-copy", L["BTN_COPY_NOTE"])
    copyBtn:SetPoint("LEFT", bar, "LEFT", 166, 0)
    copyBtn:SetScript("OnClick", function()
        local id = BNB._currentNoteID; if not id then return end
        local note = BNB.GetNote(id);  if not note then return end
        BNB.SaveCurrentNote()
        local content = (note.title ~= "" and (note.title .. "\n") or "")
                     .. (note.body or "")
        -- Always use the hint path — C_System.SetClipboard is restricted in
        -- modern WoW and cannot write to the OS clipboard from addon code.
        BNB:Print(L["BTN_COPY_NOTE_CLASSIC"])
        if BNB.ShowClipboardHint then BNB.ShowClipboardHint(content) end
    end)

    -- Lock / Unlock icon button — always visible in the toolbar.
    -- lock.tga   = note is unlocked → click to lock it persistently.
    -- unlock.tga = note is locked   → click to unlock it persistently.
    local lockBtn, lockTx = MakeIconBtn(bar, "Actionbar\\ab-lock", "")   -- tip set dynamically below
    lockBtn:SetPoint("LEFT", bar, "LEFT", 228, 0)
    lockBtn:Hide()
    lockBtn:SetScript("OnClick", function()
        local id = BNB._currentNoteID; if not id then return end
        local note = BNB.GetNote(id); if not note then return end
        local isLocked = NoteIsLocked(note)
        if isLocked then
            -- Unlock persistently (same as right-click "Unlock note")
            BNB.UpdateNote(id, { locked = false })
        else
            -- Lock persistently (same as right-click "Lock note")
            BNB.UpdateNote(id, { locked = true })
        end
        if BNB.Sticky and BNB.Sticky.RefreshLockIcons then BNB.Sticky.RefreshLockIcons(id) end
        if BNB.RefreshNoteList    then BNB.RefreshNoteList()    end
        BNB.LoadNoteInEditor(id)
    end)
    -- OnEnter/OnLeave include grow (BTN_NORMAL/BTN_HOVER from MakeIconBtn closure)
    -- and also show the dynamic tooltip. We re-set both scripts here so they
    -- replace the static-tip ones set inside MakeIconBtn.
    lockBtn:SetScript("OnEnter", function(self)
        self:SetSize(BTN_HOVER, BTN_HOVER)
        local id   = BNB._currentNoteID
        local note = id and BNB.GetNote(id)
        local isLocked = note and NoteIsLocked(note)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(isLocked and L["NE_CLICK_UNLOCK_TIP"]
                                      or L["NE_CLICK_LOCK_TIP"], 1, 1, 1)
        GameTooltip:Show()
    end)
    lockBtn:SetScript("OnLeave", function(self)
        self:SetSize(BTN_NORMAL, BTN_NORMAL)
        GameTooltip:Hide()
    end)
    bar._lockBtn = lockBtn
    bar._lockTx  = lockTx

    -- Sticky Note pin button — offset 132, always visible
    local pinBtn = CreateFrame("Button", nil, bar)
    pinBtn:SetSize(24, 24)
    pinBtn:SetPoint("LEFT", bar, "LEFT", 198, 0)
    local pinTx = pinBtn:CreateTexture(nil, "ARTWORK")
    pinTx:SetAllPoints()
    pinTx:SetTexture("Interface\\AddOns\\BigNoteBox\\Assets\\Actionbar\\ab-stickynote")
    pinBtn:SetScript("OnClick", function()
        local id = BNB._currentNoteID; if not id then return end
        if InCombatLockdown() then BNB:Print(L["STICKY_COMBAT"]); return end
        if BNB.Sticky then BNB.Sticky.Toggle(id) end
        C_Timer.After(0, function()
            if pinBtn:IsMouseOver() then
                GameTooltip:ClearLines()
                local open = BNB.Sticky and BNB.Sticky.IsOpen(id)
                GameTooltip:AddLine(open and L["STICKY_UNPIN_TIP"] or L["STICKY_PIN_TIP"], 1, 1, 1)
                GameTooltip:Show()
            end
        end)
    end)
    pinBtn:SetScript("OnEnter", function(self)
        self:SetSize(28, 28)
        local id   = BNB._currentNoteID
        local open = id and BNB.Sticky and BNB.Sticky.IsOpen(id)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(open and L["STICKY_UNPIN_TIP"] or L["STICKY_PIN_TIP"], 1, 1, 1)
        GameTooltip:Show()
    end)
    pinBtn:SetScript("OnLeave", function(self)
        self:SetSize(24, 24)
        GameTooltip:Hide()
    end)
    -- Send to Chat button (right side) — icon-only using send.tga
    local sendBtn, _ = MakeIconBtn(bar, "Actionbar\\ab-send", L["SEND_TITLE"], 28, 28)
    sendBtn:SetPoint("RIGHT", bar, "RIGHT", -10, 0)
    -- Override OnEnter to add the sub-line tooltip
    sendBtn:SetScript("OnEnter", function(self)
        self:SetSize(32, 32)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(L["SEND_TITLE"], 1, 1, 1)
        GameTooltip:AddLine(L["NE_SEND_TIP_BODY"], 0.78, 0.78, 0.78)
        GameTooltip:Show()
    end)
    sendBtn:SetScript("OnLeave", function(self)
        self:SetSize(28, 28)
        GameTooltip:Hide()
    end)
    sendBtn:SetScript("OnClick", function()
        local id = BNB._currentNoteID; if not id then return end
        if BNB.OpenSendToChat then BNB.OpenSendToChat(id) end
    end)
    bar._saveBtn = saveBtn
    bar._delBtn  = delBtn

    -- Record the left-anchored buttons after Save for BNB.ApplySaveMode
    for _, c in ipairs({ bar:GetChildren() }) do
        local p, rel, _, x = c:GetPoint(1)
        if c ~= saveBtn and p == "LEFT" and rel == bar and x then c._baseX = x end
    end
    return bar
end

--------------------------------------------------------------------------------
-- INLINE TAG EDITOR
-- Displayed as a second strip just above the toolbar.
-- Shows existing tags as removable chips + an "Add tag..." input.
-- Height: 22px. Anchored above the toolbar divider.
-- MAX_TAGS = 24, MAX_TAG_LEN = 20
--------------------------------------------------------------------------------
local MAX_TAGS     = 24
local MAX_TAG_LEN  = 20

local tagChips        = {}     -- active chip frames
local tagStripFrame   = nil    -- the strip frame (module-level so LoadNote can refresh)
local _tagStripCollapsed = false
local ASSETS_TAG      = "Interface\\AddOns\\BigNoteBox\\Assets\\"

local function RebuildTagChips(strip, tags)
    for _, c in ipairs(tagChips) do c:Hide(); c:SetParent(nil) end
    tagChips = {}

    local stripW   = strip:GetWidth()
    if not stripW or stripW <= 0 then stripW = 400 end
    local CHIP_PAD = 3
    local ROW_PAD  = 3
    local x        = 4
    local row      = 1

    for _, tag in ipairs(tags or {}) do
        local chip = BNB.CreateBackdropFrame("Frame", nil, strip)
        chip:SetHeight(16)
        -- Chip backdrop: skin lifted colour + border when in skin mode, dark otherwise
        if BigNoteBoxDB and BigNoteBoxDB.skinMode and BNB.GetSkinPreset then
            local p = BNB.GetSkinPreset()
            local r = math.min(1, p.r + p.lift * 1.5)
            local g = math.min(1, p.g + p.lift * 1.5)
            local b = math.min(1, p.b + p.lift * 1.5)
            local br, bg_, bb = BNB.SkinBorderOf(p)
            BNB.SetBackdrop(chip, r, g, b, 0.92, br, bg_, bb, 1)
        else
            BNB.SetBackdrop(chip, 0.15, 0.15, 0.20, 1, 0.35, 0.35, 0.40, 1)
        end

        local lblBtn = CreateFrame("Button", nil, chip)
        lblBtn:SetHeight(16)
        local lbl = lblBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        lbl:SetPoint("LEFT",  lblBtn, "LEFT",  4, 0)
        lbl:SetPoint("RIGHT", lblBtn, "RIGHT", 0, 0)
        -- White text in skin mode, gold otherwise
        if BigNoteBoxDB and BigNoteBoxDB.skinMode then
            lbl:SetTextColor(1, 1, 1, 1)
        else
            lbl:SetTextColor(1, 0.82, 0, 1)
        end
        lbl:SetText(tag)
        lbl:SetWordWrap(false)
        local capturedTag = tag
        lblBtn:SetScript("OnEnter", function(self)
            lbl:SetTextColor(1, 1, 0.4)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:AddLine(string.format(L["NE_FILTER_BY_TAG_FMT"], capturedTag), 1, 1, 1)
            GameTooltip:AddLine(L["NE_CLICK_CLEAR_FILTER_TIP"], 0.6, 0.6, 0.6)
            GameTooltip:Show()
        end)
        lblBtn:SetScript("OnLeave", function()
            lbl:SetTextColor(1, 0.82, 0, 1)
            GameTooltip:Hide()
        end)
        lblBtn:SetScript("OnClick", function()
            if BNB.FilterByTag then BNB.FilterByTag(capturedTag) end
        end)

        local closeChip = CreateFrame("Button", nil, chip)
        closeChip:SetSize(14, 14)
        closeChip:SetPoint("LEFT", lblBtn, "RIGHT", 2, 0)
        local closeLbl = closeChip:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        closeLbl:SetAllPoints(); closeLbl:SetText("x"); closeLbl:SetTextColor(0.65, 0.65, 0.65)
        closeChip:SetScript("OnEnter", function() closeLbl:SetTextColor(1, 0.3, 0.3) end)
        closeChip:SetScript("OnLeave", function() closeLbl:SetTextColor(0.65, 0.65, 0.65) end)
        closeChip:SetScript("OnClick", function()
            local id = BNB._currentNoteID; if not id then return end
            local note = BNB.GetNote(id);   if not note then return end
            local newTags = {}
            for _, t in ipairs(note.tags or {}) do
                if t ~= capturedTag then newTags[#newTags + 1] = t end
            end
            BNB.UpdateNote(id, { tags = newTags })
            if BNB._editorTagStrip then BNB.RefreshTagStrip() end
            if BNB.RefreshNoteList  then BNB.RefreshNoteList()  end
        end)

        -- GetStringWidth() can return 0 before layout — use string length as floor
        local strW = math.max(lbl:GetStringWidth(), #tag * 6)
        local chipW = strW + 14 + 18
        chip:SetWidth(chipW)
        lblBtn:SetWidth(strW + 4)
        lblBtn:SetPoint("LEFT", chip, "LEFT", 0, 0)

        -- On row 1, reserve 54px on the right for the collapse-toggle button and
        -- its hidden-count badge so chips can never overlap them.
        local rowLimit = (row == 1) and (stripW - 54) or (stripW - 4)
        if x + chipW > rowLimit and x > 4 then
            x   = 4
            row = row + 1
        end

        local rowY = (row - 1) * CHIP_ROW_H
        chip:SetPoint("LEFT",   strip, "LEFT",   x, 0)
        chip:SetPoint("BOTTOM", strip, "BOTTOM", 0, ROW_PAD + rowY)
        chip._row = row   -- store so ToggleTagStrip can hide/show by row
        chip:Show()
        tagChips[#tagChips + 1] = chip
        x = x + chipW + CHIP_PAD
    end

    local numRows = math.max(1, row)
    local newH    = numRows * CHIP_ROW_H
    strip:SetHeight(newH)
    strip._numRows   = numRows  -- total rows, used by ToggleTagStrip
    strip._inputRow  = nil      -- cleared; set below if input is placed

    if strip._addInput then
        if #(tags or {}) >= MAX_TAGS then
            strip._addInput:Hide()
        else
            local inputMinW = 60
            if x + inputMinW > stripW - 4 and x > 4 then
                row  = row + 1
                x    = 4
                newH = row * CHIP_ROW_H
                strip:SetHeight(newH)
            end
            strip._numRows  = math.max(1, row)
            strip._inputRow = row   -- remember which row the input is on
            local rowY = (row - 1) * CHIP_ROW_H
            strip._addInput:ClearAllPoints()
            strip._addInput:SetPoint("LEFT",   strip, "LEFT",   x,  0)
            strip._addInput:SetPoint("RIGHT",  strip, "RIGHT",  -4, 0)
            strip._addInput:SetPoint("BOTTOM", strip, "BOTTOM", 0,  ROW_PAD + rowY)
            strip._addInput:Show()
        end
    end

    -- Show the collapse toggle only when chips span more than one row.
    -- Hides itself when everything fits on one line; reappears when the window
    -- is resized narrow enough to wrap chips onto a second row.
    if strip._toggleBtn then
        if (strip._numRows or 1) > 1 then
            strip._toggleBtn:Show()
        else
            strip._toggleBtn:Hide()
            -- Also clear the badge and reset collapsed state so a single-row
            -- strip never gets stuck in a visually collapsed state.
            if strip._hiddenLbl then strip._hiddenLbl:Hide() end
            if _tagStripCollapsed then
                _tagStripCollapsed = false
                if strip._toggleTx then
                    strip._toggleTx:SetTexture(ASSETS_TAG .. "UI\\ui-tags-open")
                end
                -- Ensure all chips visible and strip at full height
                for _, chip in ipairs(tagChips) do chip:Show() end
                strip:SetHeight((strip._numRows or 1) * CHIP_ROW_H)
            end
        end
    end
end

local function BuildTagStrip(parent, toolbarFrame)
    local strip = CreateFrame("Frame", nil, parent)
    strip:SetHeight(TAG_STRIP_H)
    strip:SetPoint("BOTTOMLEFT",  parent, "BOTTOMLEFT",  0, TOOLBAR_H)
    strip:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -1, TOOLBAR_H)

    -- Sep anchors to the strip's top so it moves up as the strip grows
    local sep = BNB.CreateDivider(parent, "HORIZONTAL", 0.14, 0.14, 0.16, 0.18)
    sep:SetPoint("BOTTOMLEFT",  strip, "TOPLEFT",  0, 0)
    sep:SetPoint("BOTTOMRIGHT", strip, "TOPRIGHT", 0, 0)

    -- OnSizeChanged fires for both width and height changes.
    -- When WIDTH changes (window resize), re-wrap chips so they don't overflow.
    -- When HEIGHT changes (rows added/removed), reanchor the body scroll.
    -- Debounce width-driven rebuilds so we don't rebuild every pixel of a drag.
    local _lastStripW = 0
    local _resizeTimer = nil
    strip:SetScript("OnSizeChanged", function(self, w, h)
        -- Always reanchor body scroll to match current strip height
        local bs = BNB._editorBodyScroll
        if bs then
            bs:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -22,
                TOOLBAR_H + self:GetHeight() + PAD)
        end
        -- If width changed, debounce a chip rebuild
        if w and math.abs(w - _lastStripW) > 2 then
            _lastStripW = w
            if _resizeTimer then _resizeTimer:Cancel() end
            _resizeTimer = C_Timer.NewTimer(0.05, function()
                _resizeTimer = nil
                if BNB.RefreshTagStrip then BNB.RefreshTagStrip() end
            end)
        end
    end)

    -- Add-tag EditBox
    local addEb = CreateFrame("EditBox", nil, strip)
    addEb:SetPoint("LEFT",  strip, "LEFT", 4, 0)
    addEb:SetPoint("RIGHT", strip, "RIGHT", -4, 0)
    addEb:SetPoint("BOTTOM", strip, "BOTTOM", 0, 3)
    addEb:SetHeight(16)
    addEb:SetFontObject("GameFontNormalSmall")
    addEb:SetAutoFocus(false)
    addEb:SetMaxLetters(MAX_TAG_LEN)
    BNB.AddPlaceholder(addEb, L["TAG_ADD_HINT"], 0.35, 0.35, 0.35)

    addEb:SetScript("OnEnterPressed", function(self)
        local id = BNB._currentNoteID; if not id then return end
        local note = BNB.GetNote(id);   if not note then return end
        local text = self._showingPlaceholder and "" or (self:GetText():match("^%s*(.-)%s*$") or "")
        if text == "" then self:ClearFocus(); return end
        if #text > MAX_TAG_LEN then
            BNB:Print(L["TAG_TOO_LONG"]); return
        end
        text = BNB.NormalizeTag and BNB.NormalizeTag(text) or text
        local tags = note.tags or {}
        if #tags >= MAX_TAGS then BNB:Print(L["TAG_MAX"]); return end
        -- Deduplicate (case-insensitive — normalized form is canonical)
        for _, t in ipairs(tags) do
            if t:lower() == text:lower() then
                self:SetRealText(""); self:ClearFocus(); return
            end
        end
        tags[#tags + 1] = text
        BNB.UpdateNote(id, { tags = tags })
        -- Reset to placeholder without re-calling AddPlaceholder (which would
        -- overwrite the OnEditFocusLost hook set by AttachTagAutocomplete)
        self:SetRealText("")
        if BNB._editorTagStrip then BNB.RefreshTagStrip() end
        if BNB.RefreshNoteList  then BNB.RefreshNoteList()  end
        -- Re-open autocomplete showing updated tag list
        if BNB._tagAC then BNB._tagAC:ShowFor(self, "") end
    end)
    addEb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    -- Attach tag autocomplete (suggests existing tags as the user types)
    if BNB.AttachTagAutocomplete then BNB.AttachTagAutocomplete(addEb) end
    strip._addInput = addEb

    -- ── Collapse toggle ───────────────────────────────────────────────────────
    -- TGA icon button on the right edge of the tag bar.
    -- tags-open.tga  = tags are visible  (click to collapse to one row)
    -- tags-close.tga = tags are collapsed (click to expand)
    -- A small "+N" badge to the left of the button shows how many chips are
    -- hidden when collapsed.
    local ASSETS = "Interface\\AddOns\\BigNoteBox\\Assets\\"
    local toggleBtn = CreateFrame("Button", nil, parent)
    toggleBtn:SetSize(18, 18)
    toggleBtn:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -24, TOOLBAR_H + 2)

    local toggleTx = toggleBtn:CreateTexture(nil, "ARTWORK")
    toggleTx:SetAllPoints()
    toggleTx:SetTexture(ASSETS .. "UI\\ui-tags-open")
    toggleBtn._tx = toggleTx

    local hiTx = toggleBtn:CreateTexture(nil, "HIGHLIGHT")
    hiTx:SetAllPoints()
    hiTx:SetColorTexture(1, 1, 1, 0.25)

    -- Hidden-count badge: "+N" label that appears to the left of the toggle button
    local hiddenLbl = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hiddenLbl:SetPoint("RIGHT", toggleBtn, "LEFT", -2, 0)
    hiddenLbl:SetTextColor(0.60, 0.60, 0.65)
    hiddenLbl:Hide()
    strip._hiddenLbl = hiddenLbl

    toggleBtn:SetScript("OnEnter", function()
        GameTooltip:SetOwner(toggleBtn, "ANCHOR_TOP")
        GameTooltip:AddLine(_tagStripCollapsed and L["NE_EXPAND_TAGS_TIP"] or L["NE_COLLAPSE_TAGS_TIP"], 1, 1, 1)
        GameTooltip:Show()
    end)
    toggleBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    toggleBtn:SetScript("OnClick", function()
        if BNB.ToggleTagStrip then BNB.ToggleTagStrip() end
    end)
    strip._toggleBtn = toggleBtn
    strip._toggleTx  = toggleTx

    tagStripFrame = strip

    -- Register chip rebuild as a skin backdrop callback so chips recolour
    -- immediately when the user changes preset or brightness in config.
    if BigNoteBoxDB and BigNoteBoxDB.skinMode and BNB.RegisterSkinBackdrop then
        BNB.RegisterSkinBackdrop(function()
            if BNB.RefreshTagStrip then BNB.RefreshTagStrip() end
        end)
    end

    return strip, sep
end

-- Public: toggle tag strip between full height and one-row-collapsed height.
-- Collapsed = first row only remains visible; chips on rows 2+ are hidden.
-- The toggle TGA swaps between open/close icons.
local function ApplyTagStripCollapse(strip, collapsed)
    if not strip then return end
    if collapsed then
        -- Hide all chips on row 2+ and count them
        local hiddenCount = 0
        for _, chip in ipairs(tagChips) do
            if chip._row and chip._row > 1 then
                chip:Hide()
                hiddenCount = hiddenCount + 1
            else
                chip:Show()
            end
        end
        -- Hide add-input if it landed on row 2+
        if strip._addInput then
            if (strip._inputRow or 1) > 1 then
                strip._addInput:Hide()
            end
        end
        strip:SetHeight(CHIP_ROW_H)
        -- Show badge if any chips are hidden
        if strip._hiddenLbl then
            if hiddenCount > 0 then
                strip._hiddenLbl:SetText("+" .. hiddenCount)
                strip._hiddenLbl:Show()
            else
                strip._hiddenLbl:Hide()
            end
        end
    else
        -- Show everything
        for _, chip in ipairs(tagChips) do chip:Show() end
        if strip._addInput and (strip._numRows or 1) < (MAX_TAGS) then
            strip._addInput:Show()
        end
        strip:SetHeight((strip._numRows or 1) * CHIP_ROW_H)
        -- Hide badge when expanded
        if strip._hiddenLbl then strip._hiddenLbl:Hide() end
    end
end

function BNB.ToggleTagStrip()
    local strip = tagStripFrame
    if not strip then return end
    _tagStripCollapsed = not _tagStripCollapsed
    local sep = BNB._editorTagStripSep

    ApplyTagStripCollapse(strip, _tagStripCollapsed)

    if sep then sep:Show() end
    local bs = BNB._editorBodyScroll
    if bs then
        bs:SetPoint("BOTTOMRIGHT", BNB.editorPane, "BOTTOMRIGHT", -22,
            TOOLBAR_H + strip:GetHeight() + PAD)
    end
    if strip._toggleTx then
        strip._toggleTx:SetTexture(ASSETS_TAG ..
            (_tagStripCollapsed and "UI\\ui-tags-close" or "UI\\ui-tags-open"))
    end
end

-- Public: rebuild chips for current note
function BNB.RefreshTagStrip()
    if not tagStripFrame then return end
    local id   = BNB._currentNoteID
    local note = id and BNB.GetNote(id)
    RebuildTagChips(tagStripFrame, note and note.tags or {})
    -- Reapply collapsed state so chips on rows 2+ stay hidden if toggled
    if _tagStripCollapsed then
        ApplyTagStripCollapse(tagStripFrame, true)
        local bs = BNB._editorBodyScroll
        if bs then
            bs:SetPoint("BOTTOMRIGHT", BNB.editorPane, "BOTTOMRIGHT", -22,
                TOOLBAR_H + CHIP_ROW_H + PAD)
        end
    else
        local bs = BNB._editorBodyScroll
        if bs then
            bs:SetPoint("BOTTOMRIGHT", BNB.editorPane, "BOTTOMRIGHT", -22,
                TOOLBAR_H + tagStripFrame:GetHeight() + PAD)
        end
    end
end

--------------------------------------------------------------------------------
-- SET EDITOR LOCKED STATE
-- locked = true  → editboxes disabled, Edit button shown, Save hidden
-- locked = false → editboxes enabled,  Edit button hidden, Save shown
--------------------------------------------------------------------------------
local function SetEditorLocked(locked)
    BNB._editorLocked = locked

    if BNB._editorTitle then
        BNB._editorTitle:SetEnabled(not locked)
    end
    if BNB._editorBody then
        BNB._editorBody:SetEnabled(not locked)
        local a = locked and 0.55 or 1
        pcall(function() BNB._editorBody:SetAlpha(a) end)
    end

    local toolbar = BNB._editorToolbar
    if toolbar then
        -- Lock button: always visible.
        -- lock.tga   = note is unlocked  → click to lock
        -- unlock.tga = note is locked    → click to unlock
        local id2      = BNB._currentNoteID
        local note2    = id2 and BNB.GetNote(id2)
        local noteLocked = note2 and NoteIsLocked(note2)
        if toolbar._lockBtn then
            toolbar._lockBtn:SetShown(true)
            if toolbar._lockTx then
                local ASSETS = "Interface\\AddOns\\BigNoteBox\\Assets\\"
                toolbar._lockTx:SetTexture(ASSETS .. (noteLocked and "Actionbar\\ab-unlock" or "Actionbar\\ab-lock"))
            end
        end
        -- Pin button: always visible (lock state does not hide it)
        -- (no change needed — pinBtn has no SetShown call here)

        -- Only save and delete are greyed when locked
        if toolbar._saveBtn then
            saveBtn:SetEnabled(not locked and BNB._dirty == true)
            saveBtn:SetAlpha((not locked and BNB._dirty == true) and 1.0 or 0.4)
            pcall(function() saveBtn._tx:SetDesaturated(locked or not BNB._dirty) end)
        end
        if toolbar._delBtn then toolbar._delBtn:SetIconEnabled(not locked) end
        -- dup, copy, pin, send -- always active regardless of lock state
    end
    -- Undo/redo buttons must also dim when the note is locked
    if BNB._refreshUndoButtons then BNB._refreshUndoButtons() end
end

--------------------------------------------------------------------------------
-- LOAD NOTE IN EDITOR
--------------------------------------------------------------------------------
function BNB.LoadNoteInEditor(id)
    local note       = id and BNB.GetNote(id)
    local emptyState = BNB._editorEmptyState
    local titleBg    = BNB._editorTitleBg
    local titleEb    = BNB._editorTitle
    local bodyEb     = BNB._editorBody
    local toolbar    = BNB._editorToolbar
    local titleUl    = BNB._editorTitleUnderline
    local tsStrip    = BNB._editorTimestamp

    if not note then
        if emptyState then emptyState:Show() end
        if titleBg    then titleBg:Hide()    end
        if titleUl    then titleUl:Hide()    end
        if tsStrip    then tsStrip:Hide()    end

        if BNB._editorStatsStrip  then BNB._editorStatsStrip:Hide()  end
        if BNB._editorBodyScroll  then BNB._editorBodyScroll:Hide()  end
        if BNB._editorRenderScroll then BNB._editorRenderScroll:Hide() end
        if BNB._editorRenderFrame  then BNB._editorRenderFrame:Hide()  end
        if BNB._editorMarkupBar    then BNB._editorMarkupBar:Hide()    end
        if BNB._editorRichTabs     then BNB._editorRichTabs:Hide()     end
        BNB._editorInViewMode = false
        BNB._viewModeGen = (BNB._viewModeGen or 0) + 1
        if BNB._editorTagStrip    then BNB._editorTagStrip:Hide()    end
        if BNB._editorTagStripSep then BNB._editorTagStripSep:Hide() end
        if BNB._editorTagStrip and BNB._editorTagStrip._toggleBtn then
            BNB._editorTagStrip._toggleBtn:Hide()
            if BNB._editorTagStrip._hiddenLbl then
                BNB._editorTagStrip._hiddenLbl:Hide()
            end
        end
        if toolbar    then toolbar:Hide()    end
        if BNB._editorWysiwygBar then BNB._editorWysiwygBar:Hide() end
        BNB._currentNoteID = nil
        BNB._dirty = false
        if BNB._sessionUnlocked and id then BNB._sessionUnlocked[id] = nil end
        BNB.UpdateSaveButtonState()
        if BNB.RichPreview then BNB.RichPreview.OnNoteCleared() end
        return
    end

    if emptyState then emptyState:Hide() end
    if titleBg    then titleBg:Show()    end
    if titleUl    then titleUl:Show()    end
    if BNB._editorBodyScroll  then BNB._editorBodyScroll:Show()  end
    -- Respect collapsed state; always show the toggle button
    if BNB._editorTagStrip then
        if _tagStripCollapsed then
            BNB._editorTagStrip:Hide()
            if BNB._editorTagStripSep then BNB._editorTagStripSep:Hide() end
        else
            BNB._editorTagStrip:Show()
            if BNB._editorTagStripSep then BNB._editorTagStripSep:Show() end
        end
        if BNB._editorTagStrip._toggleBtn then
            BNB._editorTagStrip._toggleBtn:Show()
        end
    end
    if toolbar    then toolbar:Show()    end

    -- Show/hide wysiwyg bar per persisted setting
    local wyBar = BNB._editorWysiwygBar
    if wyBar then
        local db2 = BigNoteBoxDB
        if db2 and db2.wysiwygBarVisible ~= false then
            wyBar:Show()
        else
            wyBar:Hide()
        end
    end

    BNB._dirty = false

    -- Cancel any pending snapshot timers for the previous note before resetting.
    local prevID = BNB._currentNoteID  -- still the old ID at this point in LoadNoteInEditor
    if prevID then
        if _undoTimers[prevID] then _undoTimers[prevID]:Cancel(); _undoTimers[prevID] = nil end
        if _undoForced[prevID] then _undoForced[prevID]:Cancel(); _undoForced[prevID] = nil end
    end

    -- Reset undo/redo stacks for the newly loaded note.
    -- We pass the body text so UndoPush has a clean starting snapshot.
    BNB.UndoReset(id, note.body or "")
    if BNB._refreshUndoButtons    then BNB._refreshUndoButtons()    end
    if BNB._refreshWysiwygFont    then BNB._refreshWysiwygFont()    end
    if BNB.SyncHistoryNoteBtnState then BNB.SyncHistoryNoteBtnState() end
    if BNB._wysiwygRestoreBtn  then BNB._wysiwygRestoreBtn:SetIconEnabled(true)  end
    if BNB._wysiwygCopyMoveBtn then BNB._wysiwygCopyMoveBtn:SetIconEnabled(true) end

    -- Timestamps + creation coordinates
    if tsStrip then
        local db  = BigNoteBoxDB
        local fmt = db and db.dateFormat or "YYYY-MM-DD"
        local isRelative = (fmt == "relative")

        local createdStr, updatedStr
        if isRelative then
            createdStr = note.created and (string.format(L["NE_CREATED_FMT"], FmtTime(note.created))) or ""
            updatedStr = note.updated and (string.format(L["NE_TS_SEP_EDITED_FMT"], FmtTime(note.updated))) or ""
        else
            createdStr = note.created and (string.format(L["NE_TS_CREATED_SHORT_FMT"], FmtTime(note.created))) or ""
            updatedStr = note.updated and (string.format(L["NE_TS_SEP_EDITED_SHORT_FMT"], FmtTime(note.updated))) or ""
        end

        local coords
        if note.coordX and note.coordY then
            coords = string.format(L["NE_TS_SEP_COORDS_FMT"], note.coordX, note.coordY)
        else
            coords = L["NE_TS_SEP_UNKNOWN"]
        end
        tsStrip:SetText(createdStr .. updatedStr .. coords)
        tsStrip:Show()
    end
    -- Enable map button only when the note has coord data
    if BNB._wysiwygMapBtn then
        BNB._wysiwygMapBtn:SetIconEnabled(note.coordX ~= nil and note.coordMapID ~= nil)
    end
    if BNB._editorStatsStrip then BNB._editorStatsStrip:Show() end

    -- Per-note font override
    local fontOverride = note.fontOverride
    local appliedOverride = false
    if fontOverride and BNB.ResolveFontDef then
        local def = BNB.ResolveFontDef(fontOverride)
        if def then
            local sz = (note.fontSize) or (BigNoteBoxDB and BigNoteBoxDB.fontSize) or 12
            if BNB._editorBody  then pcall(function() BNB._editorBody:SetFont(def.regular, sz, "") end) end
            if BNB._editorTitle then pcall(function() BNB._editorTitle:SetFont(def.bold, 20, "") end) end
            appliedOverride = true
        end
    end
    if not appliedOverride then
        if BNB.ApplyFont then BNB.ApplyFont() end
    end
    -- Apply per-note font size override regardless of font override
    if note.fontSize and BNB._editorBody then
        local path = select(1, BNB._editorBody:GetFont())
        if path then pcall(function() BNB._editorBody:SetFont(path, note.fontSize, "") end) end
    end
    if BNB._editorBody then
        pcall(function() BNB._editorBody:SetJustifyH(note.textAlign or "LEFT") end)
        local outline = note.fontOutline or "None"
        local flags = ""
        if     outline == "Outline"            then flags = "OUTLINE"
        elseif outline == "Thick Outline"      then flags = "THICKOUTLINE"
        elseif outline == "Monochrome Outline" then flags = "MONOCHROME,OUTLINE"
        elseif outline == "SLUG"               then flags = "SLUG"
        elseif outline == "SLUG Outline"       then flags = "OUTLINE, SLUG"
        elseif outline == "SLUG Thick Outline" then flags = "THICKOUTLINE, SLUG" end
        local ox, oy, sr, sg, sb, sa = 0, 0, 0, 0, 0, 0
        if     outline == "Drop Shadow"           then ox,oy,sr,sg,sb,sa = 1,-1,0,0,0,0.8
        elseif outline == "Strong Drop Shadow"    then ox,oy,sr,sg,sb,sa = 2,-2,0,0,0,1.0
        elseif outline == "Strongest Drop Shadow" then ox,oy,sr,sg,sb,sa = 3,-3,0,0,0,1.0 end
        local path, sz2 = BNB._editorBody:GetFont()
        if path then pcall(function() BNB._editorBody:SetFont(path, sz2, flags) end) end
        pcall(function() BNB._editorBody:SetShadowOffset(ox, oy) end)
        pcall(function() BNB._editorBody:SetShadowColor(sr, sg, sb, sa) end)
    end

    if titleEb then titleEb:SetRealText(note.title or "") end
    if bodyEb  then
        bodyEb:SetRealText(note.body or "")
        if BNB._editorBodyScroll then
            BNB._editorBodyScroll:SetVerticalScroll(0)
            if BNB._editorBodyScroll.UpdateScrollbar then
                BNB._editorBodyScroll:UpdateScrollbar()
            end
        end
        UpdateStatsStrip(bodyEb:GetRealText())
    end

    if toolbar then BNB.RefreshTagStrip() end

    BNB._dirty = false
    BNB.UpdateSaveButtonState()

    -- Apply lock state (session unlock overrides)
    local sessionUnlocked = BNB._sessionUnlocked and BNB._sessionUnlocked[id]
    local locked = (not sessionUnlocked) and NoteIsLocked(note)
    SetEditorLocked(locked)
    -- Sync note list lock icon and RefBox desaturation whenever editor state changes
    if BNB.RefreshNoteList     then BNB.RefreshNoteList()     end
    if BNB.RefreshReferenceBox then BNB.RefreshReferenceBox() end

    -- Rich note: default to View mode unless config says otherwise.
    -- New notes (just created this session) always open in Editor so the user
    -- can start typing immediately.
    local isRich = BNB.AdvancedMode and BNB.AdvancedMode.IsRich(note)
    if isRich then
        local openInEditor = BNB._justCreatedNoteID == id
            or (BigNoteBoxDB and BigNoteBoxDB.richOpenInEditor)
        BNB._justCreatedNoteID = nil

        if openInEditor then
            if BNB._editorMarkupBar then BNB._editorMarkupBar:Show() end
            if BNB._editorRenderScroll then BNB._editorRenderScroll:Hide() end
            if BNB._editorRenderFrame  then BNB._editorRenderFrame:Hide()  end
            if BNB._editorBodyScroll   then BNB._editorBodyScroll:Show()   end
            BNB._editorInViewMode = false
            BNB.AM_RefreshTabs()
            BNB.UpdateBodyTopAnchor()
        else
            if BNB._editorMarkupBar then BNB._editorMarkupBar:Hide() end
            BNB.AM_RefreshTabs()
            BNB.UpdateBodyTopAnchor()
            BNB.AM_EnterViewMode(id)
        end
    else
        if BNB._editorMarkupBar    then BNB._editorMarkupBar:Hide()    end
        if BNB._editorRenderScroll then BNB._editorRenderScroll:Hide() end
        if BNB._editorRenderFrame  then BNB._editorRenderFrame:Hide()  end
        if BNB._editorBodyScroll   then BNB._editorBodyScroll:Show()   end
        BNB.AM_RefreshTabs()
        BNB.UpdateBodyTopAnchor()
    end

    -- Notify live preview of note selection (rich or not)
    if BNB.RichPreview then
        BNB.RichPreview.OnNoteSelected(note)
    end
end

--------------------------------------------------------------------------------
-- PUBLIC: refresh lock state for current note (called when global lock changes)
--------------------------------------------------------------------------------
function BNB.RefreshEditorLock()
    local id   = BNB._currentNoteID
    local note = id and BNB.GetNote(id)
    if not note then return end
    local sessionUnlocked = BNB._sessionUnlocked and BNB._sessionUnlocked[id]
    SetEditorLocked((not sessionUnlocked) and NoteIsLocked(note))
    if BNB.RefreshNoteList     then BNB.RefreshNoteList()     end
    if BNB.RefreshReferenceBox then BNB.RefreshReferenceBox() end
end

--------------------------------------------------------------------------------
-- MARKUP BAR (rich notes only)
-- Sits between WYSIWYG bar and body. Shown only when a rich note is loaded.
-- Buttons insert rich-note markup tag pairs at the cursor position.
--------------------------------------------------------------------------------
local function InsertTagPair(open, close)
    local eb = BNB._editorBody
    if not eb then return end
    eb:SetFocus()

    local fullText = eb:GetText() or ""
    local curEnd   = eb:GetCursorPosition() or #fullText

    -- Detect selection: Insert("") collapses it and deletes selected text.
    -- Compare text before/after to find what was selected.
    local before = fullText
    eb:Insert("")
    local after  = eb:GetText() or ""
    local curStart = eb:GetCursorPosition() or 0

    if #after < #before then
        -- Text was selected: selected = before[curStart+1 .. curStart+(#before-#after)]
        local selected = before:sub(curStart + 1, curStart + (#before - #after))
        eb:Insert(open .. selected .. close)
        -- Place cursor after the close tag
        eb:SetCursorPosition(curStart + #open + #selected + #close)
    else
        -- No selection: insert pair and place cursor between tags
        eb:Insert(open .. close)
        eb:SetCursorPosition(curStart + #open)
    end

    BNB.MarkDirty()
end

local function InsertTag(tag)
    local eb = BNB._editorBody
    if not eb then return end
    eb:SetFocus()

    -- If text is selected, replace it; otherwise insert at cursor
    local before = eb:GetText() or ""
    eb:Insert("")
    local after = eb:GetText() or ""
    local cursor = eb:GetCursorPosition() or 0

    eb:Insert(tag)
    eb:SetCursorPosition(cursor + #tag)
    BNB.MarkDirty()
end

local function BuildMarkupBar(parent, wysiwygBar)
    local bar = CreateFrame("Frame", "BigNoteBoxMarkupBar", parent)
    bar:SetPoint("TOPLEFT",  wysiwygBar, "BOTTOMLEFT",  0, 0)
    bar:SetPoint("TOPRIGHT", wysiwygBar, "BOTTOMRIGHT", 0, 0)
    bar:SetHeight(MARKUP_H)

    -- Top separator
    local sep = bar:CreateTexture(nil, "ARTWORK")
    sep:SetHeight(1)
    sep:SetPoint("TOPLEFT",  bar, "TOPLEFT",  0, 0)
    sep:SetPoint("TOPRIGHT", bar, "TOPRIGHT", 0, 0)
    if BigNoteBoxDB and BigNoteBoxDB.skinMode and BNB.GetSkinPreset then
        local p = BNB.GetSkinPreset()
        local br, bg_, bb = BNB.SkinBorderOf(p)
        sep:SetColorTexture(br, bg_, bb, 0.20)
        BNB.RegisterSkinRule(sep, 0.20)
    else
        sep:SetColorTexture(0.22, 0.22, 0.24, 1)
    end

    -- Bottom separator (between markup bar and note body)
    local sepB = bar:CreateTexture(nil, "ARTWORK")
    sepB:SetHeight(1)
    sepB:SetPoint("BOTTOMLEFT",  bar, "BOTTOMLEFT",  0, 0)
    sepB:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 0, 0)
    if BigNoteBoxDB and BigNoteBoxDB.skinMode and BNB.GetSkinPreset then
        local p = BNB.GetSkinPreset()
        local br, bg_, bb = BNB.SkinBorderOf(p)
        sepB:SetColorTexture(br, bg_, bb, 0.20)
        BNB.RegisterSkinRule(sepB, 0.20)
    else
        sepB:SetColorTexture(0.22, 0.22, 0.24, 1)
    end

    -- Button helper
    local MkBtn, Divider = BNB.MakeToolbarFactory(bar, PAD)

    MkBtn("H1", "Insert H1 header: {h1}...{/h1}",
        function() InsertTagPair("{h1}", "{/h1}") end)
    MkBtn("H2", "Insert H2 header: {h2}...{/h2}",
        function() InsertTagPair("{h2}", "{/h2}") end)
    MkBtn("H3", "Insert H3 header: {h3}...{/h3}",
        function() InsertTagPair("{h3}", "{/h3}") end)
    Divider()
    MkBtn("P",  "Insert paragraph: {p}...{/p}",
        function() InsertTagPair("{p}", "{/p}") end)
    MkBtn("Pc", "Insert centered paragraph: {p:c}...{/p}",
        function() InsertTagPair("{p:c}", "{/p}") end)
    MkBtn("Pr", "Insert right-aligned paragraph: {p:r}...{/p}",
        function() InsertTagPair("{p:r}", "{/p}") end)
    MkBtn("Br", "Insert line break: {br}",
        function() InsertTag("{br}") end)
    Divider()
    -- Color picker state for Col button (shared across clicks)
    local _colPickerActive = false
    local _colPickerCancelled = false
    local _colPickerR, _colPickerG, _colPickerB = 1, 1, 1
    local _colPickerHooked = false

    MkBtn("Col", "Pick a colour, then insert {col:rrggbb}...{/col}",
        function()
            local eb = BNB._editorBody
            if not eb then return end
            _colPickerActive = true
            _colPickerCancelled = false
            _colPickerR, _colPickerG, _colPickerB = 1, 1, 1
            if ColorPickerFrame.SetupColorPickerAndShow then
                ColorPickerFrame:SetupColorPickerAndShow({
                    swatchFunc = function()
                        _colPickerR, _colPickerG, _colPickerB = ColorPickerFrame:GetColorRGB()
                    end,
                    cancelFunc = function() _colPickerCancelled = true end,
                    hasOpacity = false, r = 1, g = 1, b = 1,
                })
                if not _colPickerHooked then
                    _colPickerHooked = true
                    ColorPickerFrame:HookScript("OnHide", function()
                        if not _colPickerActive then return end
                        _colPickerActive = false
                        if _colPickerCancelled then return end
                        local hex = string.format("%02x%02x%02x",
                            math.floor(_colPickerR * 255 + 0.5),
                            math.floor(_colPickerG * 255 + 0.5),
                            math.floor(_colPickerB * 255 + 0.5))
                        InsertTagPair("{col:" .. hex .. "}", "{/col}")
                    end)
                end
            end
        end)
    MkBtn("Lnk", L["NE_INSERT_LINK_TIP"],
        function() BNB.OpenLnkDialog(InsertTag) end)
    MkBtn("Ico", L["NE_INSERT_ICON_TIP"],
        function() BNB.OpenIcoDialog(InsertTag) end)
    MkBtn("Img", L["NE_INSERT_IMAGE_TIP"],
        function() BNB.OpenImgDialog(InsertTag) end)

    -- "Live Preview" toggle — right-aligned, does not advance btnX
    local previewBtn = BNB.CreateBarTextButton(bar, L["MARKUP_PREVIEW_BTN"], 72, 18)
    previewBtn:SetPoint("RIGHT", bar, "RIGHT", -PAD, 0)
    previewBtn:SetAlpha(0.45)   -- dim until a preview window is open
    previewBtn:SetScript("OnClick", function()
        if BNB.RichPreview then BNB.RichPreview.Toggle() end
    end)
    previewBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(L["MARKUP_PREVIEW_TIP"], 1, 1, 1)
        GameTooltip:Show()
    end)
    previewBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    BNB._markupPreviewBtn = previewBtn

    bar:Hide()
    return bar
end

--------------------------------------------------------------------------------
-- RICH NOTE: Editor/View tab strip
-- Children of mainFrame, anchored below the editorPane right half.
-- Only visible when a rich note is loaded.
--------------------------------------------------------------------------------
local TAB_H        = 32   -- height of the Editor/View icon button strip
local _richTabStrip = nil

local function BuildRichTabStrip()
    if _richTabStrip then return _richTabStrip end
    local mf = BNB.mainFrame
    if not mf then return nil end

    local strip = CreateFrame("Frame", "BigNoteBoxRichTabStrip", mf)
    strip:SetHeight(TAB_H)
    -- Anchored below editorPane right portion; left edge at list/editor split
    local function ReAnchor()
        local lw = BNB._listPaneW or 256
        strip:ClearAllPoints()
        strip:SetPoint("TOPLEFT",    mf, "BOTTOMLEFT",  lw + 1, 0)
        strip:SetPoint("TOPRIGHT",   mf, "BOTTOMRIGHT", 0,      0)
    end
    ReAnchor()
    mf:HookScript("OnSizeChanged", function() ReAnchor() end)

    -- Tab buttons
    local BTN_PATH = "Interface\\AddOns\\BigNoteBox\\Assets\\Buttons\\"

    -- Creates a textured icon button for the Editor/View toggle.
    -- normal/hover/press are bare asset names (no path prefix needed).
    -- active = true  -> full alpha (this is the current mode)
    -- active = false -> dimmed alpha (the other mode)
    local function MakeRichBtn(assetBase, tip, xOff)
        local btn = CreateFrame("Button", nil, strip)
        btn:SetSize(32, 32)
        btn:SetPoint("TOPLEFT", strip, "TOPLEFT", xOff, -(TAB_H - 32) / 2)
        btn:SetHighlightTexture("")
        btn:SetPushedTexture("")

        local n = btn:CreateTexture(nil, "ARTWORK"); n:SetAllPoints()
        n:SetTexture(BTN_PATH .. assetBase .. "-normal")
        local h = btn:CreateTexture(nil, "ARTWORK"); h:SetAllPoints()
        h:SetTexture(BTN_PATH .. assetBase .. "-hover"); h:Hide()
        local p = btn:CreateTexture(nil, "ARTWORK"); p:SetAllPoints()
        p:SetTexture(BTN_PATH .. assetBase .. "-press"); p:Hide()

        btn._n, btn._h, btn._p = n, h, p

        btn:SetScript("OnMouseDown", function(self)
            p:Show(); n:Hide(); h:Hide()
        end)
        btn:SetScript("OnMouseUp", function(self)
            p:Hide(); h:Show(); n:Hide()
        end)
        btn:SetScript("OnEnter", function(self)
            n:Hide(); h:Show()
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:AddLine(tip, 1, 1, 1)
            GameTooltip:Show()
        end)
        btn:SetScript("OnLeave", function()
            p:Hide(); h:Hide(); n:Show()
            GameTooltip:Hide()
        end)
        return btn
    end

    local editorTab = MakeRichBtn("bt-editor", L["NE_RICH_EDITOR_MODE_TIP"], 0)
    local viewTab   = MakeRichBtn("bt-view",   L["NE_RICH_VIEW_MODE_TIP"],        36)

    strip._editorTab = editorTab
    strip._viewTab   = viewTab
    strip:Hide()

    editorTab:SetScript("OnClick", function()
        if BNB.AM_EnterEditMode then BNB.AM_EnterEditMode() end
    end)
    viewTab:SetScript("OnClick", function()
        -- Save unsaved changes so View mode renders the latest content
        if BNB._dirty and BNB.SaveCurrentNote then BNB.SaveCurrentNote() end
        if BNB.AM_EnterViewMode then BNB.AM_EnterViewMode(BNB._currentNoteID) end
    end)

    _richTabStrip = strip
    BNB._editorRichTabs = strip
    return strip
end

--------------------------------------------------------------------------------
-- PUBLIC: Rich mode enter/exit
--------------------------------------------------------------------------------
function BNB.AM_RefreshTabs()
    local strip = BNB._editorRichTabs or _richTabStrip
    if not strip then return end
    local note  = BNB._currentNoteID and BNB.GetNote(BNB._currentNoteID)
    if not (note and note.richMode) then
        strip:Hide()
        return
    end
    strip:Show()
    -- Active button: full alpha. Inactive: dimmed (transparency only, per design).
    local inView = BNB._editorInViewMode == true
    local ACTIVE_ALPHA   = 1.0
    local INACTIVE_ALPHA = 0.40
    if strip._editorTab then strip._editorTab:SetAlpha(inView and INACTIVE_ALPHA or ACTIVE_ALPHA) end
    if strip._viewTab   then strip._viewTab:SetAlpha(inView and ACTIVE_ALPHA or INACTIVE_ALPHA)   end
end

function BNB.AM_EnterViewMode(id)
    BNB._editorInViewMode = true
    local note = id and BNB.GetNote(id)
    if not note then return end

    -- Build render scroll frame + render frame lazily
    if not BNB._editorRenderScroll then
        local rsf = CreateFrame("ScrollFrame", "BigNoteBoxRenderScroll",
                                BNB.editorPane, "ScrollFrameTemplate")
        BNB._editorRenderScroll = rsf

        local scrollBar = rsf.ScrollBar
        if scrollBar then
            scrollBar:SetAlpha(0)
            rsf:HookScript("OnScrollRangeChanged", function(_, _, yRange)
                scrollBar:SetAlpha((yRange or 0) > 1 and 1.0 or 0)
            end)
        end

        local rf = BNB.AdvancedMode.CreateRenderFrame(
            "BigNoteBoxRenderFrame", rsf)
        BNB._editorRenderFrame = rf
        rf:SetWidth(rsf:GetWidth() > 0 and rsf:GetWidth() or 400)
        rf:SetHeight(1)
        rsf:SetScrollChild(rf)

        -- Keep render frame width in sync with scroll frame.
        -- Also re-renders on resize (window drag) so content reflows at new width.
        rsf:SetScript("OnSizeChanged", function(self)
            local w = self:GetWidth()
            if not w or w <= 0 then return end
            rf:SetWidth(w)
            -- Re-render if view mode is currently active
            if BNB._editorInViewMode and BNB._currentNoteID then
                local rn = BNB.GetNote(BNB._currentNoteID)
                if rn then
                    local bs = rn.fontSize or (BigNoteBoxDB and BigNoteBoxDB.fontSize) or 12
                    local fs = BNB.AdvancedMode.OutlineFlagStr(rn.fontOutline)
                    BNB.AdvancedMode.ApplyFontsToRenderFrame(rf, bs, fs)
                    local rawST = getmetatable(rf).__index.SetText
                    rawST(rf, BNB.AdvancedMode.ToHTML(rn.body or "", bs))
                    rf:SetHeight(rf:GetContentHeight())
                end
            end
        end)

        rsf:Hide()
    end

    if BNB._editorBodyScroll then BNB._editorBodyScroll:Hide() end
    if BNB._editorMarkupBar  then BNB._editorMarkupBar:Hide()  end

    local rsf = BNB._editorRenderScroll
    local rf  = BNB._editorRenderFrame
    BNB.UpdateBodyTopAnchor()
    rf:Show()
    rsf:Show()
    rsf:SetVerticalScroll(0)

    -- Generation counter: stale deferred ticks from previous note switches
    -- must not overwrite the current note's content.
    BNB._viewModeGen = (BNB._viewModeGen or 0) + 1
    local gen = BNB._viewModeGen

    -- Defer content rendering by one frame so the layout engine resolves
    -- editorPane width. On the same tick the window is first shown, GetWidth()
    -- returns 0, which leaves the SimpleHTML with no reflow width -> blank.
    C_Timer.After(0, function()
        -- Stale tick from a previous note switch or mode change
        if BNB._viewModeGen ~= gen then return end
        if not BNB._editorInViewMode then return end
        if not rsf:IsShown() then return end

        local paneW = BNB.editorPane:GetWidth()
        if paneW and paneW > 0 then
            rf:SetWidth(paneW - PAD - 22)
        end

        -- Re-read note in case it was saved between the call and the tick
        local freshNote = id and BNB.GetNote(id)
        if not freshNote then return end

        local bodySize = freshNote.fontSize or (BigNoteBoxDB and BigNoteBoxDB.fontSize) or 12
        local flagStr  = BNB.AdvancedMode.OutlineFlagStr(freshNote.fontOutline)
        BNB.AdvancedMode.ApplyFontsToRenderFrame(rf, bodySize, flagStr)

        local html = BNB.AdvancedMode.ToHTML(freshNote.body or "", bodySize)
        local rawST = getmetatable(rf).__index.SetText
        rawST(rf, html)
        rf:SetHeight(rf:GetContentHeight())

        -- Scroll to top
        rsf:SetVerticalScroll(0)
    end)

    BNB.AM_RefreshTabs()
end

function BNB.AM_EnterEditMode()
    BNB._editorInViewMode = false
    BNB._viewModeGen = (BNB._viewModeGen or 0) + 1  -- invalidate pending deferred ticks
    if BNB._editorRenderScroll then BNB._editorRenderScroll:Hide() end
    if BNB._editorRenderFrame  then BNB._editorRenderFrame:Hide()  end
    if BNB._editorBodyScroll   then BNB._editorBodyScroll:Show()   end

    local note = BNB._currentNoteID and BNB.GetNote(BNB._currentNoteID)
    if note and note.richMode and BNB._editorMarkupBar then
        BNB._editorMarkupBar:Show()
    end

    BNB.UpdateBodyTopAnchor()
    BNB.AM_RefreshTabs()
end

-- Toggle between view and editor mode for the currently loaded rich note.
-- No-op if no note is selected or the selected note is not a rich note.
-- Called by the keybind (BNB_KeybindToggleRichView) and can also be used
-- by other systems that want to flip modes programmatically.
function BNB.ToggleRichViewEdit()
    local note = BNB._currentNoteID and BNB.GetNote(BNB._currentNoteID)
    if not note or not note.richMode then return end
    if BNB._editorInViewMode then
        if BNB.AM_EnterEditMode then BNB.AM_EnterEditMode() end
    else
        if BNB.AM_EnterViewMode then BNB.AM_EnterViewMode(BNB._currentNoteID) end
    end
end

--------------------------------------------------------------------------------
-- BUILD NOTE EDITOR
--------------------------------------------------------------------------------
function BNB.BuildNoteEditor()
    local pane = BNB.editorPane
    if not pane then return end

    local emptyState = BNB._BuildEditorEmptyState(pane)
    BNB._editorEmptyState = emptyState

    local titleBg, titleEb, titleUl, tsStrip, statsStrip = BuildTitleField(pane)
    BNB._editorTitleBg        = titleBg
    BNB._editorTitle          = titleEb
    BNB._editorTitleUnderline = titleUl
    BNB._editorTimestamp      = tsStrip
    BNB._editorStatsStrip     = statsStrip

    -- Invisible button overlaid on the right half of the timestamp strip.
    -- Becomes clickable only when the current note has coord data.
    local toolbar = BuildToolbar(pane)
    BNB._editorToolbar = toolbar
    BNB.ApplySaveMode()

    -- Tag strip sits between body and toolbar — build after toolbar so we know TOOLBAR_H
    local tagStrip, tagStripSep = BuildTagStrip(pane, toolbar)
    BNB._editorTagStrip    = tagStrip
    BNB._editorTagStripSep = tagStripSep

    -- WYSIWYG bar sits between timestamp strip and body.
    -- topAnchor is the bar when visible, tsStrip when hidden.
    local wysiwygBar = BNB._BuildWysiwygBar(pane, tsStrip)
    BNB._editorWysiwygBar = wysiwygBar

    -- Markup bar sits between WYSIWYG bar and body (rich notes only).
    local markupBar = BuildMarkupBar(pane, wysiwygBar)
    BNB._editorMarkupBar = markupBar

    local topAnchor  = (BigNoteBoxDB and BigNoteBoxDB.wysiwygBarVisible ~= false)
                       and wysiwygBar or tsStrip
    local bodyScroll, bodyEb = BuildBodyField(pane, topAnchor)
    BNB._editorBodyScroll = bodyScroll
    BNB._editorBody       = bodyEb

    -- When focus enters the body, the user is still working on the new note —
    -- dismiss any open discard popup so it doesn't fire while they type.
    bodyEb:HookScript("OnEditFocusGained", function()
        if BNB._pendingNewNoteID == BNB._currentNoteID then
            StaticPopup_Hide("BNB_DISCARD_NEW_NOTE")
        end
    end)

    titleBg:Hide()
    titleUl:Hide()
    tsStrip:Hide()
    statsStrip:Hide()
    bodyScroll:Hide()
    tagStrip:Hide()
    tagStripSep:Hide()
    if tagStrip._toggleBtn then tagStrip._toggleBtn:Hide() end
    if tagStrip._hiddenLbl then tagStrip._hiddenLbl:Hide() end
    toolbar:Hide()
    wysiwygBar:Hide()
    markupBar:Hide()
    emptyState:Show()

    -- Build rich tab strip (deferred one tick so mainFrame exists and is sized)
    C_Timer.After(0, function() BuildRichTabStrip() end)
end


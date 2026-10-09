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

-- Whether the editor treats note id as locked right now. Oracle search
-- (ALL-69) asks before putting the cursor in a note.
function BNB.IsNoteLockedInEditor(id)
    return NoteIsLocked(id and BNB.GetNote(id))
end

--------------------------------------------------------------------------------
-- SAVE BUTTON STATE
--------------------------------------------------------------------------------
-- Focus mode button: off with no note selected, and off while the note is
-- locked, since Focus mode does not honour the lock (Dukul, 2026-09-27)
local function RefreshFocusButton()
    local btn = BNB._focusModeBtn
    if not btn then return end
    local ok = BNB._currentNoteID ~= nil and not BNB._editorLocked
    btn:SetEnabled(ok)   -- the icon button draws its own disabled look
end

function BNB.UpdateSaveButtonState()
    if not saveBtn then return end
    local enabled = BNB._dirty == true
    saveBtn._showsDirty = enabled   -- MarkDirty skips the update while true
    saveBtn:SetEnabled(enabled)
    saveBtn:SetAlpha(enabled and 1.0 or 0.4)
    if saveBtn._tx then saveBtn._tx:SetDesaturated(not enabled) end
    -- Keep focus button in sync: disabled with no note or a locked note
    local hasNote = BNB._currentNoteID ~= nil
    RefreshFocusButton()
    -- Share button: enabled whenever a note is selected
    if BNB._wysiwygShareBtn then
        BNB._wysiwygShareBtn:SetIconEnabled(hasNote)
    end
end

BNB.MarkDirty = function()
    BNB.Editor.SetDirty(true)
    -- Runs on every keystroke: the buttons only change when the Save button
    -- does not show the note as changed yet (PERF-04)
    if not (saveBtn and saveBtn._showsDirty) then BNB.UpdateSaveButtonState() end
    if BNB.ScheduleAutoSave then BNB.ScheduleAutoSave() end   -- ALL-52
    BNB.SendMessage("EditorDirty")   -- the rich preview follows (RichPreview.lua)
end

-- Automatic save mode hides the Save button and closes its gap: the buttons
-- after it are anchored at fixed x offsets, so each moves left by one slot.
-- The Reference Box button does the same when that module is off (Dukul,
-- 2026-09-28; it used to stay, greyed), and so does the Tasks button when
-- Tasks is off (ALL-102). _baseX is recorded once, when the toolbar is built.
-- Called on save-mode, Reference Box and Tasks toggles.
-- The ab-forever action bar art is more detailed, so its icons (and slots) are
-- drawn AB_GROW px larger wherever it is used (Dukul, 2026-09-27; BNB.AbDetailed,
-- Init.lua). Set by BuildToolbar, once the settings are loaded.
local AB_GROW     = 0
local SAVE_SLOT_W = 32
function BNB.ApplySaveMode()
    local bar = BNB._editorToolbar
    if not (bar and saveBtn) then return end
    local auto = BNB.IsAutoSave and BNB.IsAutoSave()
    saveBtn:SetShown(not auto)
    local hidden = {}   -- module buttons switched off, each closing its slot
    local rb    = BNB._editorRefBoxBtn
    local rbOff = BigNoteBoxDB and BigNoteBoxDB.referenceBoxEnabled == false
    if rb then rb:SetShown(not rbOff); if rbOff then hidden[#hidden + 1] = rb end end
    local tb    = BNB._editorTasksBtn
    local tbOff = BNB.TasksEnabled and not BNB.TasksEnabled()
    if tb then tb:SetShown(not tbOff); if tbOff then hidden[#hidden + 1] = tb end end
    for _, c in ipairs({ bar:GetChildren() }) do
        if c._baseX then
            local shift = auto and SAVE_SLOT_W or 0
            for _, h in ipairs(hidden) do
                if h._baseX and c._baseX > h._baseX then shift = shift + SAVE_SLOT_W end
            end
            c:ClearAllPoints()
            c:SetPoint("LEFT", bar, "LEFT", c._baseX - shift, 0)
        end
    end
end

--------------------------------------------------------------------------------
-- TIMESTAMP FORMATTING
-- Respects BigNoteBoxDB.dateFormat and BigNoteBoxDB.use24Hour.
-- Relative format uses coarse buckets (< 1m, < 1h, < 1d, < 7d, < 30d, etc.)
--------------------------------------------------------------------------------
local function FmtDatePart(ts, fmt)
    if fmt == "DD-MM-YYYY" then
        return BNB.Date("%d-%m-%Y", ts)
    elseif fmt == "MM-DD-YYYY" then
        return BNB.Date("%m-%d-%Y", ts)
    end
    return BNB.Date("%Y-%m-%d", ts)  -- YYYY-MM-DD (default)
end

local function FmtClockPart(ts, use24)
    if use24 then return BNB.Date("%H:%M", ts) end
    local h = tonumber(BNB.Date("%H", ts))
    local m = BNB.Date("%M", ts)
    local ampm = h >= 12 and "pm" or "am"
    h = h % 12; if h == 0 then h = 12 end
    return h .. ":" .. m .. " " .. ampm
end

local function FmtTime(ts)
    if not ts or ts == 0 then return "" end
    local db       = BigNoteBoxDB
    local fmt      = db and db.dateFormat or BNB.DEFAULTS.dateFormat
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

    return FmtDatePart(ts, fmt) .. " " .. FmtClockPart(ts, use24)
end
-- Shared with UI/FocusEditor.lua (called at runtime, so load order does not matter)
BNB.FmtTime = FmtTime

-- Absolute date / clock in the Appearance format, for text inserted into a
-- note (ALL-66). The Relative setting has no fixed date, so it gives YYYY-MM-DD.
function BNB.FmtDate(ts)
    local db = BigNoteBoxDB
    return FmtDatePart(ts or time(), db and db.dateFormat)
end
function BNB.FmtClock(ts)
    local db = BigNoteBoxDB
    return FmtClockPart(ts or time(), db == nil or db.use24Hour ~= false)
end

-- Fixed "YYYY-MM-DD  H:MM" stamp for history rows, whatever the date setting
-- (a list of versions reads best in one sortable form). Moved here from
-- Widgets.lua so all four formatters share the date and clock parts (CMP-05).
function BNB.FmtTs(ts)
    if not ts or ts == 0 then return L["TS_UNKNOWN"] end
    local db = BigNoteBoxDB
    return FmtDatePart(ts) .. "  " .. FmtClockPart(ts, db == nil or db.use24Hour ~= false)
end

--------------------------------------------------------------------------------
-- TITLE FIELD
-- AddPlaceholder called ONCE at build time.
--------------------------------------------------------------------------------
local RICH_BADGE_SIZE = 22

-- Shows the rich badge for a rich note and moves the title's right edge
-- clear of it. Run by LoadNoteInEditor, which every rich/plain switch calls.
local function RefreshRichBadge(note)
    local badge, eb = BNB._editorRichBadge, BNB._editorTitle
    if not (badge and eb) then return end
    local rich = BNB.AdvancedMode.IsRich(note)   -- false while Rich Notes is off (ALL-343)
    badge:SetShown(rich)
    eb:SetPoint("BOTTOMRIGHT", eb:GetParent(), "BOTTOMRIGHT", rich and -(RICH_BADGE_SIZE + 12) or -6, 0)
end

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
        pcall(function() eb:SetFont(boldPath, BNB.FontPx(boldPath, 20), "") end)
    else
        local font, _, flags = GameFontNormalHuge:GetFont()
        if font then eb:SetFont(font, 20, flags or "")
        else eb:SetFontObject("BNBFontNormalLarge") end
    end
    eb:SetAutoFocus(false)
    eb:SetMaxLetters(200)
    eb:SetTextInsets(2, 2, 2, 2)

    -- Rich-note badge at the right end of the title, the icon Oracle search
    -- shows on rich results (Dukul, 2026-09-27). Shown by RefreshRichBadge.
    local richBadge = CreateFrame("Frame", nil, bg)
    richBadge:SetSize(RICH_BADGE_SIZE, RICH_BADGE_SIZE)
    richBadge:SetPoint("RIGHT", bg, "RIGHT", -6, 0)
    local richTx = richBadge:CreateTexture(nil, "ARTWORK")
    richTx:SetAllPoints()
    -- Skin mode: Dukul's white s-icon-skin-rich in the skin's accent colour
    -- (2026-10-08; the Oracle keeps s-icon-rich until its skin set is done)
    if BigNoteBoxDB and BigNoteBoxDB.skinMode then
        richTx:SetTexture("Interface\\AddOns\\BigNoteBox\\Assets\\Search\\s-icon-skin-rich")
        BNB.RegisterSkinAccentTex(richTx)
    else
        richTx:SetTexture("Interface\\AddOns\\BigNoteBox\\Assets\\Search\\s-icon-rich")
    end
    richBadge:EnableMouse(true)
    richBadge:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT")
        GameTooltip:AddLine(L["ORACLE_BADGE_RICH"], 1, 1, 1)
        GameTooltip:AddLine(L["NE_RICH_BADGE_TIP"], 0.7, 0.7, 0.7, true)
        GameTooltip:Show()
    end)
    richBadge:SetScript("OnLeave", function() GameTooltip:Hide() end)
    richBadge:Hide()
    BNB._editorRichBadge = richBadge

    -- Underline (always visible)
    local underline = BNB.CreateNoteRule(parent)
    underline:SetPoint("TOPLEFT",  bg, "BOTTOMLEFT",  0, -1)
    underline:SetPoint("TOPRIGHT", bg, "BOTTOMRIGHT", 0, -1)

    -- Timestamp strip anchored below the underline
    local tsStrip = parent:CreateFontString(nil, "OVERLAY", "BNBFontNormalSmall")
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
            local d = BNB.Date("%Y-%m-%d", ts)
            local t
            if use24 then
                t = BNB.Date("%H:%M", ts)
            else
                local h = tonumber(BNB.Date("%H", ts))
                local ampm = h >= 12 and "pm" or "am"
                h = h % 12; if h == 0 then h = 12 end
                t = h .. ":" .. BNB.Date("%M", ts) .. " " .. ampm
            end
            return d .. " " .. t
        end
        local created = note.created and AbsTime(note.created)
        local updated = note.updated and AbsTime(note.updated)
        if not created and not updated then return end
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
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
    BNB._editorTsHover = tsHover   -- hidden with the strip in a rich note's Note view (ALL-286)

    -- Word/char count label (M) — right-aligned in the same strip
    local statsStrip = parent:CreateFontString(nil, "OVERLAY", "BNBFontNormalSmall")
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

    -- Markup to fix (ALL-264): left of the counts, over the timestamp hover,
    -- in a rich note's Markup view. Placed and filled by RefreshMarkupWarn.
    local warn = CreateFrame("Frame", nil, parent)
    warn:SetFrameLevel(tsHover:GetFrameLevel() + 2)
    warn:SetHeight(TSTAMP_H + 2)
    warn:EnableMouse(true)
    local warnTx = warn:CreateFontString(nil, "OVERLAY", "BNBFontNormalSmall")
    warnTx:SetPoint("RIGHT")
    warnTx:SetTextColor(1, 0.6, 0.2)
    warn._text = warnTx
    warn:SetScript("OnEnter", function(self)
        local list = self._repairs
        if not list then return end
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(L["NE_MARKUP_WARN_TITLE"], 1, 0.6, 0.2)
        local MAX = 10
        for i = 1, math.min(#list, MAX) do
            GameTooltip:AddLine(BNB.AdvancedMode.DescribeRepair(list[i]), 1, 1, 1, true)
        end
        if #list > MAX then
            GameTooltip:AddLine(string.format(L["NE_MARKUP_WARN_MORE_FMT"], #list - MAX), 0.7, 0.7, 0.7)
        end
        GameTooltip:AddLine(L["NE_MARKUP_WARN_DESC"], 0.7, 0.7, 0.7, true)
        GameTooltip:Show()
    end)
    warn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    warn:Hide()
    BNB._editorMarkupWarn = warn

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
        -- (GetCurrentKeyboardFocus does not exist on any client, so this
        -- check never fired before batch 11: ask the box itself.)
        if BNB._editorBody and BNB._editorBody:HasFocus() then return end
        local nc = _G["BigNoteBoxNoteConfigFrame"]
        if nc and nc:IsShown() then return end

        -- Focus went elsewhere — show the discard popup.
        StaticPopup_Show("BNB_DISCARD_NEW_NOTE")
    end

    -- Register the discard confirmation popup (once, idempotent).
    if not StaticPopupDialogs["BNB_DISCARD_NEW_NOTE"] then
        StaticPopupDialogs["BNB_DISCARD_NEW_NOTE"] = {
            preferredIndex = 3,
            text      = L["NE_DISCARD_POPUP_TEXT"],
            button1   = L["NE_DISCARD_BTN"],
            button2   = L["NE_KEEP_EDITING_BTN"],
            OnAccept  = function()
                local id = BNB._pendingNewNoteID
                BNB._pendingNewNoteID = nil
                if not id then return end
                BNB.Editor.SetCurrent(nil)
                if BNB.PurgeNote        then BNB.PurgeNote(id) end
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
-- The markup warning (ALL-264): shown with the counts in a rich note's Markup
-- view (an unlocked one: a locked note is never repaired, ALL-277) while the
-- text has repairs, just left of the count text. Runs with every count update
-- and every view change (UpdateBodyTopAnchor).
local function RefreshMarkupWarn()
    local warn, strip, eb = BNB._editorMarkupWarn, BNB._editorStatsStrip, BNB._editorBody
    if not (warn and strip and eb) then return end
    local note = BNB._currentNoteID and BNB.GetNote(BNB._currentNoteID)
    local list
    if strip:IsShown() and not BNB._editorInViewMode and not BNB._editorLocked
       and BNB.AdvancedMode.IsRich(note) then
        list = BNB.AdvancedMode.MarkupRepairs(eb._showingPlaceholder and "" or (eb:GetText() or ""))
    end
    if not (list and #list > 0) then
        warn._repairs = nil
        warn:Hide()
        return
    end
    warn._repairs = list
    warn._text:SetText(string.format(L["NE_MARKUP_WARN_FMT"], #list))
    warn:SetWidth(warn._text:GetStringWidth() + 4)
    warn:ClearAllPoints()
    warn:SetPoint("RIGHT", strip, "RIGHT", -(strip:GetStringWidth() + 12), 0)
    warn:Show()
    if GameTooltip:IsOwned(warn) then warn:GetScript("OnEnter")(warn) end
end

local function UpdateStatsStrip(text)
    local strip = BNB._editorStatsStrip
    if not strip then return end
    if not text or text == "" then
        strip:SetText(L["NE_STATS_EMPTY"])
    else
        local chars = #text
        local words = 0
        for _ in text:gmatch("%S+") do words = words + 1 end
        local fmt = BreakUpLargeNumbers or tostring
        strip:SetText(string.format(L["NE_STATS_FMT"], fmt(chars), fmt(words)))
    end
    RefreshMarkupWarn()
end

-- Typing updates the strip once the keys pause (PERF-04): the word count
-- walks the whole body, too much per keystroke in a long note.
local STATS_DELAY = 0.15
local function UpdateStatsFromEditor()
    local eb = BNB._editorBody
    if eb then UpdateStatsStrip(eb.GetRealText and eb:GetRealText() or eb:GetText()) end
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
    bodySize = bodySize or (BigNoteBoxDB and BigNoteBoxDB.fontSize) or BNB.DEFAULTS.fontSize

    local sf, eb = BNB.CreateScrolledEditBox("BigNoteBoxBodyScroll", parent, bodySize)
    if bodyPath then
        pcall(function() eb:SetFont(bodyPath, BNB.FontPx(bodyPath, bodySize), "") end)
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
                -- MarkDirty also schedules the live preview: RichPreview.lua
                -- hooks it (loads after this file, so the hook wraps this
                -- override). Calling ScheduleRender here too ran it twice.
                BNB.MarkDirty()
                if BNB._editorBodyScroll and BNB._editorBodyScroll.UpdateScrollbar then
                    BNB._editorBodyScroll:UpdateScrollbar()
                end
                -- Undo snapshot — hybrid debounce + forced interval.
                -- Both timings are user-configurable in Config > Editor.
                local id = BNB._currentNoteID
                if id and not BNB._undoActive then
                    local idleDelay = (BigNoteBoxDB and BigNoteBoxDB.undoIdleDelay)    or 0.8
                    local forcedInt = (BigNoteBoxDB and BigNoteBoxDB.undoForcedInterval) or BNB.DEFAULTS.undoForcedInterval
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
            BNB.Debounce("editorStats", STATS_DELAY, UpdateStatsFromEditor)
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
            BNB.SetPropagate(self, false)
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
            BNB.SetPropagate(self, false)
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

    -- A rich note's Note view shows only the title, its rule and the note: no
    -- timestamp / stats row and no formatting toolbar (Dukul, ALL-286). Back
    -- in Markup view they return, the toolbar per its setting. Every mode
    -- change and note load ends here, so this is the one place that decides.
    local ul   = BNB._editorTitleUnderline
    local note = BNB._currentNoteID and BNB.GetNote(BNB._currentNoteID)
    local bare = BNB.AdvancedMode.IsRich(note) and BNB._editorInViewMode == true and ul
    if note then
        local stats, tsHover = BNB._editorStatsStrip, BNB._editorTsHover
        if bare then
            ts:Hide()
            if stats   then stats:Hide()   end
            if tsHover then tsHover:Hide() end
            if bar     then bar:Hide()     end
        else
            ts:Show()
            if stats   then stats:Show()   end
            if tsHover then tsHover:Show() end
            if bar then
                if BigNoteBoxDB and BigNoteBoxDB.wysiwygBarVisible == false then bar:Hide() else bar:Show() end
            end
        end
    end

    -- Build anchor chain: tsStrip -> wysiwygBar (if shown) -> markupBar (if shown)
    local topAnchor = bare and ul or ts
    if bar  and bar:IsShown()  then topAnchor = bar  end
    if mbar and mbar:IsShown() then topAnchor = mbar end
    if mbar and mbar._sepT then
        if bar and bar:IsShown() then mbar._sepT:Hide() else mbar._sepT:Show() end
    end

    local bottomOffset = TOOLBAR_H
        + (BNB._editorTagStrip and BNB._editorTagStrip:GetHeight() or TAG_STRIP_H)
        + PAD
    -- The rule starts 2 px left of the strip (BuildTitleField): same text edge
    local topX, topY = PAD, -4
    if topAnchor == ul then topX, topY = PAD + 2, -6 end

    if sf then
        sf:ClearAllPoints()
        sf:SetPoint("TOPLEFT",     topAnchor,      "BOTTOMLEFT",  topX, topY)
        sf:SetPoint("BOTTOMRIGHT", BNB.editorPane, "BOTTOMRIGHT", -22, bottomOffset)
    end
    if rsf then
        rsf:ClearAllPoints()
        rsf:SetPoint("TOPLEFT",     topAnchor,      "BOTTOMLEFT",  topX, topY)
        rsf:SetPoint("BOTTOMRIGHT", BNB.editorPane, "BOTTOMRIGHT", -22, bottomOffset)
    end
    RefreshMarkupWarn()   -- shown in Markup view only (ALL-264)
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
    AB_GROW     = BNB.AbDetailed() and 6 or 0
    SAVE_SLOT_W = 32 + AB_GROW
    -- The larger icons left 2 px above and below them on Retail / Classic normal
    -- mode, where the window's bottom edge sits closer than Forever's chrome
    -- (Dukul, 2026-10-08): the bar grows there. Built before anything else reads it
    if AB_GROW > 0 and not BNB.IsForever then TOOLBAR_H = 36 + 10 end
    local bar = CreateFrame("Frame", nil, parent)
    bar:SetPoint("BOTTOMLEFT",  parent, "BOTTOMLEFT",  0, 0)
    bar:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, 0)
    bar:SetHeight(TOOLBAR_H)

    local sep = BNB.CreateNoteRule(parent)
    sep:SetPoint("BOTTOMLEFT",  parent, "BOTTOMLEFT",  0, TOOLBAR_H)
    sep:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -1, TOOLBAR_H)

    -- Icon button helper — 26×26, texture from Assets/
    -- Returns btn, tx. Calling btn:SetIconEnabled(bool) sets alpha + desaturation.
    -- Hover: the ui-hover-64 glow behind the icon (gold in normal mode, the skin
    -- accent in skin mode, BNB.TintUIIcon) instead of growing the button
    -- (Dukul, 2026-10-08). Shown only while the button is enabled.
    local ASSETS = "Interface\\AddOns\\BigNoteBox\\Assets\\"
    local BTN_NORMAL = 26 + AB_GROW
    local function AddHoverBg(btn)
        local hv = btn:CreateTexture(nil, "BACKGROUND")
        hv:SetAllPoints()
        hv:SetTexture(BNB.UI_HOVER_TEX)
        BNB.TintUIIcon(hv)
        hv:Hide()
        btn._hoverBg = hv
        return hv
    end
    local function HoverOn(btn)  if btn:IsEnabled() then btn._hoverBg:Show() end end
    local function HoverOff(btn) btn._hoverBg:Hide() end
    local function SlotX(i) return 6 + i * SAVE_SLOT_W end   -- left edge of slot i
    local function MakeIconBtn(parent, texName, tip, w, h)
        local btn = CreateFrame("Button", nil, parent)
        local bw = w or BTN_NORMAL
        local bh = h or BTN_NORMAL
        btn:SetSize(bw, bh)
        local tx = btn:CreateTexture(nil, "ARTWORK")
        tx:SetAllPoints()
        tx:SetTexture(ASSETS .. texName)
        AddHoverBg(btn)
        btn:SetScript("OnEnter", function(self)
            HoverOn(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:AddLine(type(tip) == "function" and tip() or tip, 1, 1, 1)
            GameTooltip:Show()
        end)
        btn:SetScript("OnLeave", function(self)
            HoverOff(self)
            GameTooltip:Hide()
        end)
        btn:HookScript("OnDisable", HoverOff)
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
    saveBtn = MakeIconBtn(bar, "Actionbar\\ab-save", L["BTN_SAVE_NOTE"])
    saveBtn:SetPoint("LEFT", bar, "LEFT", SlotX(0), 0)
    saveBtn:SetEnabled(false)
    saveBtn:SetAlpha(0.4)
    pcall(function() saveBtn._tx:SetDesaturated(true) end)
    saveBtn:SetScript("OnClick", function()
        BNB.SaveCurrentNote()
        BNB.UpdateSaveButtonState()
    end)

    -- Reference Box toggle
    do
        local refboxBtn, _ = MakeIconBtn(bar, BNB.AbIcon("refbox"), L["NE_TOGGLE_REFBOX_TIP"])
        refboxBtn:SetPoint("LEFT", bar, "LEFT", SlotX(1), 0)
        refboxBtn:SetScript("OnClick", function()
            if BNB.ToggleReferenceBox then BNB.ToggleReferenceBox() end
        end)
        BNB._editorRefBoxBtn = refboxBtn
    end

    -- Tasks button: adds a task to the current note (same as + button in RefBox).
    -- With the Reference Box off it opens/closes the tasks-only window on a note
    -- that has tasks (BNB.OnTasksBarButton, ALL-102); hidden while Tasks is off.
    do
        local function TasksTip()
            local id = BNB._currentNoteID
            local rbOff = BigNoteBoxDB and BigNoteBoxDB.referenceBoxEnabled == false
            if rbOff and id and BNB.Task and BNB.Task.HasTasks(id) then
                return L["NE_TOGGLE_TASKS_TIP"]
            end
            return L["NE_ADD_TASK_TIP"]
        end
        local tasksBtn, _ = MakeIconBtn(bar, BNB.AbIcon("tasks"), TasksTip)
        tasksBtn:SetPoint("LEFT", bar, "LEFT", SlotX(2), 0)
        tasksBtn:SetScript("OnClick", function()
            if BNB.OnTasksBarButton then BNB.OnTasksBarButton(BNB._currentNoteID) end
        end)
        BNB._editorTasksBtn = tasksBtn
    end

    -- Delete
    local delBtn = MakeIconBtn(bar, BNB.AbIcon("delete"), L["BTN_DELETE_NOTE"])
    delBtn:SetPoint("LEFT", bar, "LEFT", SlotX(3), 0)
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
    local dupBtn = MakeIconBtn(bar, BNB.AbIcon("duplicate"), L["NE_DUPLICATE_NOTE_TIP"])
    dupBtn:SetPoint("LEFT", bar, "LEFT", SlotX(4), 0)
    dupBtn:SetScript("OnClick", function()
        local id = BNB._currentNoteID; if not id then return end
        local src = BNB.GetNote(id);   if not src then return end
        BNB.SaveCurrentNote()
        -- Full copy (rich mode, tasks, attachments...): see BNB.CopyNote
        local newID = BNB.CopyNote(id, {
            title = src.title ~= "" and (src.title .. " (copy)") or "" })
        if not newID then return end
        if BNB.SelectNote      then BNB.SelectNote(newID) end
    end)

    -- Copy to clipboard — copies title + body silently via editbox trick
    local copyBtn = MakeIconBtn(bar, BNB.AbIcon("copy"), L["BTN_COPY_NOTE"])
    copyBtn:SetPoint("LEFT", bar, "LEFT", SlotX(5), 0)
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
    -- lock.tga   = note is locked (shows current state); click unlocks it.
    -- unlock.tga = note is unlocked; click locks it.
    local lockBtn, lockTx = MakeIconBtn(bar, BNB.AbIcon("unlock"), "")   -- tip set dynamically below
    lockBtn:SetPoint("LEFT", bar, "LEFT", SlotX(7) - 2, 0)
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
        BNB.LoadNoteInEditor(id)
    end)
    -- OnEnter/OnLeave include the hover glow (HoverOn / HoverOff) and also show
    -- the dynamic tooltip. We re-set both scripts here so they
    -- replace the static-tip ones set inside MakeIconBtn.
    lockBtn:SetScript("OnEnter", function(self)
        HoverOn(self)
        local id   = BNB._currentNoteID
        local note = id and BNB.GetNote(id)
        local isLocked = note and NoteIsLocked(note)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(isLocked and L["NE_CLICK_UNLOCK_TIP"]
                                      or L["NE_CLICK_LOCK_TIP"], 1, 1, 1)
        GameTooltip:Show()
    end)
    lockBtn:SetScript("OnLeave", function(self)
        HoverOff(self)
        GameTooltip:Hide()
    end)
    bar._lockBtn = lockBtn
    bar._lockTx  = lockTx

    -- Sticky Note pin button — offset 132, always visible
    local pinBtn = CreateFrame("Button", nil, bar)
    pinBtn:SetSize(24 + AB_GROW, 24 + AB_GROW)
    pinBtn:SetPoint("LEFT", bar, "LEFT", SlotX(6), 0)
    local pinTx = pinBtn:CreateTexture(nil, "ARTWORK")
    pinTx:SetAllPoints()
    pinTx:SetTexture("Interface\\AddOns\\BigNoteBox\\Assets\\" .. BNB.AbIcon("stickynote"))
    AddHoverBg(pinBtn)
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
        HoverOn(self)
        local id   = BNB._currentNoteID
        local open = id and BNB.Sticky and BNB.Sticky.IsOpen(id)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(open and L["STICKY_UNPIN_TIP"] or L["STICKY_PIN_TIP"], 1, 1, 1)
        GameTooltip:Show()
    end)
    pinBtn:SetScript("OnLeave", function(self)
        HoverOff(self)
        GameTooltip:Hide()
    end)
    -- Hidden while the Sticky Notes module is off (ALL-343); its slot stays
    -- empty, as the Tasks button's does
    function BNB.ApplyEditorStickyBtn()
        pinBtn:SetShown(BNB.StickiesEnabled())
    end
    BNB.ApplyEditorStickyBtn()
    -- Send to Chat button (right side) — icon-only using send.tga
    local sendBtn, _ = MakeIconBtn(bar, BNB.AbIcon("send"), L["SEND_TITLE"], 28 + AB_GROW, 28 + AB_GROW)
    -- -26 keeps it clear of the main window's 16 px resize grip (BOTTOMRIGHT -2, 2)
    sendBtn:SetPoint("RIGHT", bar, "RIGHT", -26, 0)
    -- Override OnEnter to add the sub-line tooltip
    sendBtn:SetScript("OnEnter", function(self)
        HoverOn(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(L["SEND_TITLE"], 1, 1, 1)
        GameTooltip:AddLine(L["NE_SEND_TIP_BODY"], 0.78, 0.78, 0.78)
        GameTooltip:Show()
    end)
    sendBtn:SetScript("OnLeave", function(self)
        HoverOff(self)
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
            local r, g, b = BNB.SkinButtonOf(p)
            local br, bg_, bb = BNB.SkinBorderOf(p)
            BNB.SetBackdrop(chip, r, g, b, 0.92, br, bg_, bb, 1)
        else
            BNB.SetBackdrop(chip, 0.15, 0.15, 0.20, 1, 0.35, 0.35, 0.40, 1)
        end

        local lblBtn = CreateFrame("Button", nil, chip)
        lblBtn:SetHeight(16)
        local lbl = lblBtn:CreateFontString(nil, "OVERLAY", "BNBFontNormalSmall")
        lbl:SetPoint("LEFT",  lblBtn, "LEFT",  4, 0)
        lbl:SetPoint("RIGHT", lblBtn, "RIGHT", 0, 0)
        -- White text in skin mode, gold otherwise
        if BigNoteBoxDB and BigNoteBoxDB.skinMode then
            BNB.SetTextWhite(lbl)
        else
            BNB.SetHeaderColor(lbl)
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
            BNB.SetHeaderColor(lbl)
            GameTooltip:Hide()
        end)
        lblBtn:SetScript("OnClick", function()
            if BNB.FilterByTag then BNB.FilterByTag(capturedTag) end
        end)

        local closeChip = CreateFrame("Button", nil, chip)
        closeChip:SetSize(14, 14)
        closeChip:SetPoint("LEFT", lblBtn, "RIGHT", 2, 0)
        local closeLbl = closeChip:CreateFontString(nil, "OVERLAY", "BNBFontNormalSmall")
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
    local sep = BNB.CreateNoteRule(parent)
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
    addEb:SetFontObject("BNBFontNormalSmall")
    addEb:SetAutoFocus(false)
    addEb:SetMaxLetters(MAX_TAG_LEN)
    -- Brighter than the other hints: at 0.35 players missed the field (ALL-61)
    BNB.AddPlaceholder(addEb, L["TAG_ADD_HINT"], 0.55, 0.55, 0.55)

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
    local hiddenLbl = parent:CreateFontString(nil, "OVERLAY", "BNBFontNormalSmall")
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

-- The open note's chips follow its tag changes, wherever they come from (the
-- strip itself, the Tag Manager, a history restore; ARCH-02). Once per frame.
BNB.RegisterMessage("NoteEditor", "NoteChanged", function(_, id, fields)
    if id ~= BNB._currentNoteID or not fields then return end
    local touched = fields.tags ~= nil
    for _, k in ipairs(fields._clear or {}) do
        if k == "tags" then touched = true end
    end
    if touched then BNB.Debounce("editorTagStrip", 0, BNB.RefreshTagStrip) end
end)

-- The open note's title colour changed (Note Settings, New note): the editor
-- title follows it (ALL-260)
BNB.RegisterMessage("NoteEditorTitleColor", "NoteChanged", function(_, id, fields)
    if id ~= BNB._currentNoteID or not fields or not BNB._editorTitle then return end
    local touched = fields.titleColor ~= nil
    for _, k in ipairs(fields._clear or {}) do
        if k == "titleColor" then touched = true end
    end
    if not touched then return end
    local note = BNB.GetNote(id)
    BNB._editorTitle:SetRealColor(note and note.titleColor)
end)

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
-- Hover cursor kind for the editor's text frames (BNB.SetHoverCursor): the
-- lock while the open note is locked (ALL-95, ALL-239)
function BNB.EditorLockKind() if BNB._editorLocked then return "lock" end end

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
        -- lock.tga   = note is locked (current state)
        -- unlock.tga = note is unlocked (current state)
        local id2      = BNB._currentNoteID
        local note2    = id2 and BNB.GetNote(id2)
        local noteLocked = note2 and NoteIsLocked(note2)
        if toolbar._lockBtn then
            toolbar._lockBtn:SetShown(true)
            if toolbar._lockTx then
                local ASSETS = "Interface\\AddOns\\BigNoteBox\\Assets\\"
                toolbar._lockTx:SetTexture(ASSETS .. (noteLocked and BNB.AbIcon("lock") or BNB.AbIcon("unlock")))
            end
        end
        -- Pin button: always visible (lock state does not hide it)
        -- (no change needed — pinBtn has no SetShown call here)

        -- Only save and delete are greyed when locked
        if toolbar._saveBtn then
            saveBtn._showsDirty = (not locked and BNB._dirty == true)
            saveBtn:SetEnabled(not locked and BNB._dirty == true)
            saveBtn:SetAlpha((not locked and BNB._dirty == true) and 1.0 or 0.4)
            pcall(function() saveBtn._tx:SetDesaturated(locked or not BNB._dirty) end)
        end
        if toolbar._delBtn then toolbar._delBtn:SetIconEnabled(not locked) end
        -- dup, copy, pin, send -- always active regardless of lock state
    end
    -- Undo/redo buttons must also dim when the note is locked
    if BNB._refreshUndoButtons then BNB._refreshUndoButtons() end
    RefreshFocusButton()
    RefreshMarkupWarn()   -- a locked note is never repaired (ALL-277)
end

--------------------------------------------------------------------------------
-- LOAD NOTE IN EDITOR
--------------------------------------------------------------------------------
function BNB.LoadNoteInEditor(id)
    local note       = id and BNB.GetNote(id)
    RefreshRichBadge(note)
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
        if BNB._editorMarkupWarn  then BNB._editorMarkupWarn:Hide()  end
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
        BNB.Editor.SetCurrent(nil)
        BNB.Editor.SetDirty(false)
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

    BNB.Editor.SetDirty(false)

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
        local fmt = db and db.dateFormat or BNB.DEFAULTS.dateFormat
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
            local sz = (note.fontSize) or (BigNoteBoxDB and BigNoteBoxDB.fontSize) or BNB.DEFAULTS.fontSize
            if BNB._editorBody  then pcall(function() BNB._editorBody:SetFont(def.regular, BNB.FontPx(def.regular, sz), "") end) end
            if BNB._editorTitle then pcall(function() BNB._editorTitle:SetFont(def.bold, BNB.FontPx(def.bold, 20), "") end) end
            appliedOverride = true
        end
    end
    if not appliedOverride then
        if BNB.ApplyFont then BNB.ApplyFont() end
    end
    -- Apply per-note font size override regardless of font override
    if note.fontSize and BNB._editorBody then
        local path = select(1, BNB._editorBody:GetFont())
        if path then pcall(function() BNB._editorBody:SetFont(path, BNB.FontPx(path, note.fontSize), "") end) end
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

    if titleEb then
        titleEb:SetRealColor(note.titleColor)   -- the note's title colour (ALL-260)
        titleEb:SetRealText(note.title or "")
    end
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

    BNB.Editor.SetDirty(false)
    BNB.UpdateSaveButtonState()

    -- Apply lock state
    SetEditorLocked(NoteIsLocked(note))
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
    SetEditorLocked(NoteIsLocked(note))
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
    eb:Insert("")
    local cursor = eb:GetCursorPosition() or 0

    eb:Insert(tag)
    eb:SetCursorPosition(cursor + #tag)
    BNB.MarkDirty()
end

local function BuildMarkupBar(parent, wysiwygBar)
    local bar = CreateFrame("Frame", nil, parent)
    bar:SetPoint("TOPLEFT",  wysiwygBar, "BOTTOMLEFT",  0, 0)
    bar:SetPoint("TOPRIGHT", wysiwygBar, "BOTTOMRIGHT", 0, 0)
    bar:SetHeight(MARKUP_H)

    -- Top separator: drawn only while the WYSIWYG bar is hidden, whose bottom
    -- line sits right above it (together they drew one 2px line);
    -- BNB.UpdateBodyTopAnchor shows / hides it
    local sep = BNB.CreateNoteRule(bar)
    sep:SetPoint("TOPLEFT",  bar, "TOPLEFT",  0, 0)
    sep:SetPoint("TOPRIGHT", bar, "TOPRIGHT", 0, 0)
    bar._sepT = sep

    -- Bottom separator (between markup bar and note body)
    local sepB = BNB.CreateNoteRule(bar)
    sepB:SetPoint("BOTTOMLEFT",  bar, "BOTTOMLEFT",  0, 0)
    sepB:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 0, 0)

    -- Button helper
    local MkBtn, Divider = BNB.MakeToolbarFactory(bar, PAD)

    MkBtn("H1", L["NE_MU_H1_TIP"],
        function() InsertTagPair("{h1}", "{/h1}") end)
    MkBtn("H2", L["NE_MU_H2_TIP"],
        function() InsertTagPair("{h2}", "{/h2}") end)
    MkBtn("H3", L["NE_MU_H3_TIP"],
        function() InsertTagPair("{h3}", "{/h3}") end)
    Divider()
    MkBtn("P",  L["NE_MU_P_TIP"],
        function() InsertTagPair("{p}", "{/p}") end)
    MkBtn("Pc", L["NE_MU_PC_TIP"],
        function() InsertTagPair("{p:c}", "{/p}") end)
    MkBtn("Pr", L["NE_MU_PR_TIP"],
        function() InsertTagPair("{p:r}", "{/p}") end)
    MkBtn("Br", L["NE_MU_BR_TIP"],
        function() InsertTag("{br}") end)
    Divider()
    -- Color picker state for Col button (shared across clicks)
    local _colPickerActive = false
    local _colPickerCancelled = false
    local _colPickerR, _colPickerG, _colPickerB = 1, 1, 1
    local _colPickerHooked = false

    MkBtn("Col", L["NE_MU_COL_TIP"],
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
        function() BNB.OpenLnkDialog(InsertTag, BNB.PeekSelection(BNB._editorBody, true)) end)
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

-- Text tabs (both clients) cut from the game's own UIFrameTabsPaperdollInfo sheet
-- (64x512, file id 4200159; not shipped with the addon). Blue (Source) is the black tab with the blue
-- overlay on top; yellow (View) is the gold tab. The inactive tab is dimmed with
-- vertex colour, never alpha (Dukul, 2026-09-27). Pieces are {x0, x1, y0, y1} px.
local FTAB_TEX   = "Interface\\PaperDollInfoFrame\\UIFrameTabsPaperdollInfo"
local FTAB_H     = 32     -- drawn height, incl. ~5 px of shadow under the border
local FTAB_CAP   = 16     -- width of the left and right end pieces
local FTAB_MIN_W = 96
local FTAB_X, FTAB_Y, FTAB_GAP = 6, 2, 2   -- first tab's offset in the strip, gap between tabs
local FTAB_DIM   = 0.45   -- vertex colour of the inactive tab and its text
local FTAB_PIECES = {
    -- gold tab with its top 7 rows cropped, so it matches the black tab's height
    yellow = { l = { 0, 16, 139, 171 }, m = { 16, 48,   7,  39 }, r = { 45, 61, 100, 132 } },
    black  = { l = { 0, 16, 203, 235 }, m = { 16, 48,  39,  71 }, r = { 40, 56, 171, 203 } },
    -- overlay, drawn over the black tab: top 3 rows cropped, inset to sit inside its border
    blue   = { l = { 0, 16, 260, 279 }, m = { 16, 48,  74,  93 }, r = { 35, 51, 238, 257 } },
}
local FTAB_BLUE_L, FTAB_BLUE_R, FTAB_BLUE_Y = 4, 3, 8
-- The icon-button symbol beside the label (both clients, Dukul 2026-10-03): the glyph sits
-- in about 14..54 x 17..48 of the 64 px canvas, so a square around it is cut out.
local FTAB_SYM     = "Interface\\AddOns\\BigNoteBox\\Assets\\Buttons\\Symbols\\bt-"
local FTAB_ICON    = 18
local FTAB_ICON_TC = { 13 / 64, 55 / 64, 12 / 64, 54 / 64 }
local FTAB_ICON_GAP = 3

-- Three textures (left cap, stretched middle, right cap) for one piece set, filling
-- `frame` between the given insets. Returns them for vertex colouring.
local function AddForeverTabPieces(frame, set, layer, sub, li, ri, top)
    local P, out = FTAB_PIECES[set], {}
    local function Tex(p)
        local t = frame:CreateTexture(nil, layer, nil, sub)
        t:SetTexture(FTAB_TEX)
        -- Half a texel in from top and bottom: the pieces are packed edge to edge, and
        -- filtering pulled the next piece's opaque top row in as a black line under each tab.
        t:SetTexCoord(p[1] / 64, p[2] / 64, (p[3] + 0.5) / 512, (p[4] - 0.5) / 512)
        t:SetHeight(p[4] - p[3])
        out[#out + 1] = t
        return t
    end
    local l, m, r = Tex(P.l), Tex(P.m), Tex(P.r)
    l:SetWidth(FTAB_CAP); r:SetWidth(FTAB_CAP)
    l:SetPoint("TOPLEFT",  frame, "TOPLEFT",  li,  -top)
    r:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -ri, -top)
    m:SetPoint("TOPLEFT", l, "TOPRIGHT"); m:SetPoint("TOPRIGHT", r, "TOPLEFT")
    return out
end

-- The icon-button symbol left of a text label, centred as one group on the tab
-- (yOff from its centre). Sets the tab's width; returns the icon and label.
local function AddTabFace(btn, symbol, label, yOff)
    local fs = btn:CreateFontString(nil, "OVERLAY", "BNBFontHighlightSmall")
    fs:SetText(label)
    local icon = btn:CreateTexture(nil, "ARTWORK", nil, 2)
    icon:SetTexture(FTAB_SYM .. symbol .. "-normal")
    icon:SetTexCoord(unpack(FTAB_ICON_TC))
    icon:SetSize(FTAB_ICON, FTAB_ICON)
    local groupW = FTAB_ICON + FTAB_ICON_GAP + math.ceil(fs:GetStringWidth())
    icon:SetPoint("LEFT", btn, "CENTER", -groupW / 2, yOff)
    fs:SetPoint("LEFT", icon, "RIGHT", FTAB_ICON_GAP, 0)
    btn:SetWidth(math.max(FTAB_MIN_W, groupW + 2 * FTAB_CAP))
    return icon, fs
end

-- Skin mode: the skin icon buttons' box (preset colours, tooltip border) with no
-- top border, tucked SKTAB_TUCK px up under the main window, which hides its top
-- end behind the window's own border (Dukul, 2026-10-03). The strip is put in the
-- strata below the window by AM_RefreshTabs. The inactive tab is darkened.
local SKTAB_H, SKTAB_TUCK = 37, 8   -- frame height; visible height = SKTAB_H - SKTAB_TUCK
local SKTAB_BOX = { bgFile = "Interface\\Buttons\\White8x8",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 14,
    insets = { left = 3, right = 3, top = 3, bottom = 3 } }
local STRATA_BELOW = { MEDIUM = "LOW", HIGH = "MEDIUM", DIALOG = "HIGH",
    FULLSCREEN = "DIALOG", FULLSCREEN_DIALOG = "FULLSCREEN", TOOLTIP = "FULLSCREEN_DIALOG" }

local function MakeSkinTab(parent, symbol, label, tip)
    local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
    btn:SetHeight(SKTAB_H)
    local icon, fs = AddTabFace(btn, symbol, label, -SKTAB_TUCK / 2)   -- centred in the visible part
    btn:SetBackdrop(SKTAB_BOX)   -- once: Paint only sets colours, a new SetBackdrop rebuilds the pieces
    -- No top border: drop the top edge and corners, run the side edges up to the top
    for _, k in ipairs({ "TopEdge", "TopLeftCorner", "TopRightCorner" }) do
        if btn[k] then btn[k]:Hide() end
    end
    if btn.LeftEdge and btn.RightEdge then
        btn.LeftEdge:SetPoint("TOPLEFT", btn, "TOPLEFT")
        btn.RightEdge:SetPoint("TOPRIGHT", btn, "TOPRIGHT")
    end
    local hl = btn:CreateTexture(nil, "ARTWORK", nil, 1)
    hl:SetPoint("TOPLEFT", 3, -3); hl:SetPoint("BOTTOMRIGHT", -3, 3)
    hl:SetColorTexture(1, 1, 1, 0.10)
    hl:Hide()

    local active, hover = true, false
    local function Paint()
        local p = BNB.GetSkinPreset()
        local br, bg_, bb = BNB.SkinBorderOf(p)
        local m = active and 1 or 0.6
        local fr, fg, fb = BNB.SkinButtonOf(p)
        btn:SetBackdropColor(fr * m, fg * m, fb * m, 0.97)
        btn:SetBackdropBorderColor(br, bg_, bb, 1)
        hl:SetShown(hover and not active)
        -- Icon in the accent, as the top bar and toolbar icons (Dukul,
        -- 2026-10-08). The bt- symbol is gold art, darker than the white
        -- icons once desaturated, so it is lifted by one factor capped where
        -- the brightest channel hits 1. Active = white label; inactive = icon
        -- and label in the accent at half its saturation
        local ar, ag, ab = BNB.SkinAccentOf(p)
        if not active then
            local lum = 0.299 * ar + 0.587 * ag + 0.114 * ab
            ar, ag, ab = (ar + lum) / 2, (ag + lum) / 2, (ab + lum) / 2
        end
        local k = math.min(1.7, 1 / math.max(ar, ag, ab, 0.001))
        icon:SetDesaturated(true)
        -- Inactive icon and label at 0.7 opacity (Dukul, 2026-10-08)
        icon:SetVertexColor(ar * k, ag * k, ab * k, active and 1 or 0.7)
        if active then fs:SetTextColor(BNB.TextWhite()) else fs:SetTextColor(ar, ag, ab, 0.7) end
    end
    function btn:SetActive(on) active = on and true or false; Paint() end
    btn:SetScript("OnEnter", function(self)
        hover = true; Paint()
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(tip, 1, 1, 1)
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function()
        hover = false; Paint()
        GameTooltip:Hide()
    end)
    BNB.RegisterSkinButton(Paint, btn)
    Paint()
    return btn
end

-- A bottom tab in the Forever look: "blue" or "yellow" art, the icon-button symbol
-- left of a text label, a tooltip. tab:SetActive(bool) brightens or dims all of it.
local function MakeForeverTab(parent, color, symbol, label, tip)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetHeight(FTAB_H)
    local texs
    if color == "blue" then
        texs = AddForeverTabPieces(btn, "black", "BACKGROUND", 0, 0, 0, 0)
        for _, t in ipairs(AddForeverTabPieces(btn, "blue", "BACKGROUND", 1,
                FTAB_BLUE_L, FTAB_BLUE_R, FTAB_BLUE_Y)) do texs[#texs + 1] = t end
    else
        texs = AddForeverTabPieces(btn, "yellow", "BACKGROUND", 0, 0, 0, 0)
    end
    local icon, fs = AddTabFace(btn, symbol, label, 2)   -- above the shadow

    local active, hover = true, false
    local function Paint()
        local v = active and 1 or (hover and 0.7 or FTAB_DIM)
        for _, t in ipairs(texs) do t:SetVertexColor(v, v, v) end
        icon:SetVertexColor(v, v, v)
        fs:SetTextColor(v, v, v)
    end
    function btn:SetActive(on) active = on and true or false; Paint() end
    btn:SetScript("OnEnter", function(self)
        hover = true; Paint()
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(tip, 1, 1, 1)
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function()
        hover = false; Paint()
        GameTooltip:Hide()
    end)
    Paint()
    return btn
end

local function BuildRichTabStrip()
    if _richTabStrip then return _richTabStrip end
    local mf = BNB.mainFrame
    if not mf then return nil end

    local strip = CreateFrame("Frame", nil, mf)
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

    -- Fallback tab buttons: icon buttons for the Editor/View toggle (UI/IconButton.lua).
    -- The current mode is drawn at full alpha, the other dimmed (AM_RefreshTabs).
    local function MakeRichBtn(symbol, tip, xOff)
        local btn = BNB.CreateIconButton(strip, 32, symbol, { tip = tip, tipAnchor = "ANCHOR_TOP" })
        btn:SetPoint("TOPLEFT", strip, "TOPLEFT", xOff, -(TAB_H - 32) / 2)
        return btn
    end

    -- The Forever text tabs on both clients (Dukul, 2026-10-03). The sheet is game art,
    -- not shipped: should a client ever lack it, fall back to the icon buttons rather
    -- than draw green squares.
    local editorTab, viewTab
    local hasSheet = not (C_UIFileAsset and C_UIFileAsset.IsKnownFile)
        or C_UIFileAsset.IsKnownFile(FTAB_TEX)
    if BigNoteBoxDB and BigNoteBoxDB.skinMode then
        editorTab = MakeSkinTab(strip, "editor", L["NE_RICH_TAB_MARKUP"], L["NE_RICH_EDITOR_MODE_TIP"])
        viewTab   = MakeSkinTab(strip, "view",   L["NE_RICH_TAB_NOTE"],   L["NE_RICH_VIEW_MODE_TIP"])
        local w = math.max(editorTab:GetWidth(), viewTab:GetWidth())
        editorTab:SetWidth(w); viewTab:SetWidth(w)
        editorTab:SetPoint("TOPLEFT", strip, "TOPLEFT", FTAB_X, SKTAB_TUCK)
        viewTab:SetPoint("LEFT", editorTab, "RIGHT", FTAB_GAP, 0)
        strip._under = true
    elseif hasSheet then
        editorTab = MakeForeverTab(strip, "blue",   "editor", L["NE_RICH_TAB_MARKUP"], L["NE_RICH_EDITOR_MODE_TIP"])
        viewTab   = MakeForeverTab(strip, "yellow", "view",   L["NE_RICH_TAB_NOTE"],   L["NE_RICH_VIEW_MODE_TIP"])
        local w = math.max(editorTab:GetWidth(), viewTab:GetWidth())   -- same width, the wider label's
        editorTab:SetWidth(w); viewTab:SetWidth(w)
        editorTab:SetPoint("TOPLEFT", strip, "TOPLEFT", FTAB_X, FTAB_Y)
        viewTab:SetPoint("LEFT", editorTab, "RIGHT", FTAB_GAP, 0)
    else
        editorTab = MakeRichBtn("editor", L["NE_RICH_EDITOR_MODE_TIP"], 0)
        viewTab   = MakeRichBtn("view",   L["NE_RICH_VIEW_MODE_TIP"],   36)
    end

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
    if not BNB.AdvancedMode.IsRich(note) then
        strip:Hide()
        return
    end
    if strip._under and BNB.mainFrame then   -- skin tabs hang under the window (a child's level cannot)
        strip:SetFrameStrata(STRATA_BELOW[BNB.mainFrame:GetFrameStrata()] or "LOW")
    end
    strip:Show()
    -- Active button: full alpha. Inactive: dimmed (transparency only, per design).
    local inView = BNB._editorInViewMode == true
    if strip._editorTab and strip._editorTab.SetActive then   -- text tabs: dim, not fade
        strip._editorTab:SetActive(not inView)
        strip._viewTab:SetActive(inView)
        return
    end
    local ACTIVE_ALPHA   = 1.0
    local INACTIVE_ALPHA = 0.40
    if strip._editorTab then strip._editorTab:SetAlpha(inView and INACTIVE_ALPHA or ACTIVE_ALPHA) end
    if strip._viewTab   then strip._viewTab:SetAlpha(inView and ACTIVE_ALPHA or INACTIVE_ALPHA)   end
end

function BNB.AM_EnterViewMode(id)
    BNB._editorInViewMode = true
    local note = id and BNB.GetNote(id)
    if not note then BNB.SendMessage("EditorViewMode", id); return end

    -- Build render scroll frame + render frame lazily
    if not BNB._editorRenderScroll then
        local rsf = BNB.CreateScrollFrame("BigNoteBoxRenderScroll", BNB.editorPane)
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
        -- FOR-30: never inside OnSizeChanged. It fires in the client's layout
        -- pass; a SetText there frees the SimpleHTML's lines while that pass is
        -- still walking them (Forever ACCESS_VIOLATION on a freed FontString,
        -- 2026-10-07: rich note -> click a plain note). Reflow on the next frame.
        local function Reflow()
            local w = rsf:GetWidth()
            if not w or w <= 0 then return end
            rf:SetWidth(w)
            -- Re-render if view mode is currently active on a rich note
            if BNB._editorInViewMode and BNB._currentNoteID then
                local rn = BNB.GetNote(BNB._currentNoteID)
                if rn and BNB.AdvancedMode.IsRich(rn) then
                    local bs = rn.fontSize or (BigNoteBoxDB and BigNoteBoxDB.fontSize) or BNB.DEFAULTS.fontSize
                    local fs = BNB.AdvancedMode.OutlineFlagStr(rn.fontOutline)
                    BNB.AdvancedMode.ApplyFontsToRenderFrame(rf, bs, fs)
                    local rawST = getmetatable(rf).__index.SetText
                    rawST(rf, BNB.AdvancedMode.ToHTML(rn.body or "", bs))
                    rf:SetHeight(rf:GetContentHeight())
                end
            end
        end
        rsf:SetScript("OnSizeChanged", function()
            BNB.Debounce("editorRichReflow", 0, Reflow)
        end)

        -- Double-click the rendered text (or the empty area below it) opens the
        -- editor, unless the note is locked (ALL-93). Neither frame type has
        -- OnDoubleClick: two presses within 0.35s, as the sticky inline edit.
        local lastPress = 0
        local function OnPress(_, btn)
            if btn ~= "LeftButton" then return end
            local now = GetTime()
            if now - lastPress > 0.35 then lastPress = now; return end
            lastPress = 0
            if not BNB._editorInViewMode or BNB._editorLocked then return end
            BNB.AM_EnterEditMode()
            C_Timer.After(0, function()
                if BNB._editorBody and not BNB._editorInViewMode then BNB._editorBody:SetFocus() end
            end)
        end
        rsf:EnableMouse(true); rsf:HookScript("OnMouseDown", OnPress)
        rf:EnableMouse(true);  rf:HookScript("OnMouseDown", OnPress)
        -- Lock cursor over the rendered text too (ALL-239)
        BNB.SetHoverCursor(rsf, BNB.EditorLockKind)
        BNB.SetHoverCursor(rf, BNB.EditorLockKind)

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

        local bodySize = freshNote.fontSize or (BigNoteBoxDB and BigNoteBoxDB.fontSize) or BNB.DEFAULTS.fontSize
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
    BNB.SendMessage("EditorViewMode", id)   -- the rich preview closes (RichPreview.lua)
end

function BNB.AM_EnterEditMode()
    BNB._editorInViewMode = false
    BNB._viewModeGen = (BNB._viewModeGen or 0) + 1  -- invalidate pending deferred ticks
    if BNB._editorRenderScroll then BNB._editorRenderScroll:Hide() end
    if BNB._editorRenderFrame  then BNB._editorRenderFrame:Hide()  end
    if BNB._editorBodyScroll   then BNB._editorBodyScroll:Show()   end

    local note = BNB._currentNoteID and BNB.GetNote(BNB._currentNoteID)
    if BNB.AdvancedMode.IsRich(note) and BNB._editorMarkupBar then
        BNB._editorMarkupBar:Show()
    end

    BNB.UpdateBodyTopAnchor()
    BNB.AM_RefreshTabs()
    BNB.SendMessage("EditorEditMode")
end

-- Toggle between view and editor mode for the currently loaded rich note.
-- No-op if no note is selected or the selected note is not a rich note.
-- Called by the keybind (BNB_KeybindToggleRichView) and can also be used
-- by other systems that want to flip modes programmatically.
function BNB.ToggleRichViewEdit()
    local note = BNB._currentNoteID and BNB.GetNote(BNB._currentNoteID)
    if not BNB.AdvancedMode.IsRich(note) then return end
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
    -- ALL-95: the lock cursor over a locked note's text. The scroll frame too,
    -- always: a short plain note leaves most of the area to it (ALL-239). The
    -- rich view frames get it where they are built (AM_EnterViewMode)
    BNB.SetHoverCursor(bodyEb, BNB.EditorLockKind)
    BNB.SetHoverCursor(bodyScroll, BNB.EditorLockKind)

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


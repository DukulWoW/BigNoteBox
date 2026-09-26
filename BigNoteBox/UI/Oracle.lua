-- BigNoteBox UI/Oracle.lua -- Oracle search: the bar and its results (ALL-69)
--
-- A search bar in the middle of the screen, opened by its keybinding
-- (BIGNOTEBOXORACLE, default Ctrl+Space) or /bnb search [text], without
-- opening the main window. It searches every note (all characters and
-- global; the sidebar filter does not apply) through Features/OracleSearch.lua
-- and lists the best matches under the bar, drawn in the same search theme
-- as the bar (UI/SearchChrome.lua) minus the ornament.
--
-- Up / Down (and Tab / Shift+Tab) move the selection, the mouse selects on
-- hover. Enter or a click opens the note in the main window; held modifiers
-- open it elsewhere: Shift = sticky, Ctrl = focus mode, Alt = Reference Box.
-- Esc, a click outside or the keybinding again closes it.
--
-- Prefixes (ALL-69.2): letter prefixes before the search text narrow it (s/f/r
-- pick where a result opens instead of a held modifier, b searches the trash;
-- p/n/i/z/c/g/k/a/x/l filter; d takes a date). #tag, @who, *favourite, -exclude
-- and "exact phrase" work inside the search text itself. "?" alone shows the
-- full list. The grammar lives in Features/OracleSearch.lua (ParseQuery),
-- localized letters/date words are built here from L (PrefixMap/DateWordMap).

local BNB = BigNoteBox
local L   = BNB.L

local Oracle = {}
BNB.Oracle = Oracle

local MAX_ROWS   = 8
local ROW_H      = 36
local ROW_GAP    = 2
local ICON_SIZE  = 26
local HINT_H     = 18
local PANEL_GAP  = 2    -- space between the bar and the results panel
local DEFAULT_ICON = "Interface\\Icons\\INV_Misc_Note_06"
local BADGE_SIZE = 18
local BADGE_GAP  = 4
local BADGE_ART  = "Interface\\AddOns\\BigNoteBox\\Assets\\Search\\"

-- What an NPC note is about: "elite", "mob" or "npc". Target notes made
-- before targetAttackable existed (ALL-69) show as an NPC.
local ELITE = { elite = true, rareelite = true, worldboss = true }
local function NpcKind(note)
    if note.source ~= "target" then return nil end
    if not note.targetAttackable then return "npc" end
    return ELITE[note.targetClassification or ""] and "elite" or "mob"
end

-- Small icons on the right of a result, so a note's kind shows at a glance.
-- Drawn right to left in this order: the first five (who the note is about)
-- never share a note, so they keep the rightmost column. show(note) decides
-- each. Art by Dukul, 32x32 TGA in Assets\Search\. More kinds are added here.
local BADGES = {
    { file = "s-icon-npc",      show = function(note) return NpcKind(note) == "npc" end },
    { file = "s-icon-mobs",     show = function(note) return NpcKind(note) == "mob" end },
    { file = "s-icon-elite",    show = function(note) return NpcKind(note) == "elite" end },
    { file = "s-icon-alliance", show = function(note)
        return note.source == "inspect" and note.inspectFaction == "Alliance" end },
    { file = "s-icon-horde",    show = function(note)
        return note.source == "inspect" and note.inspectFaction == "Horde" end },
    -- Quest, gossip and book notes (QuickNote.lua); older ones by their quest
    { file = "s-icon-quest",    show = function(note)
        return note.source == "quicknote" or BNB.OracleSearch.HasAttachment(note, "quest") end },
    -- An item in the Reference Box, or an item link pasted into the text
    { file = "s-icon-items",    show = function(note) return BNB.OracleSearch.HasItem(note) end },
    { file = "s-icon-rich",     show = function(note) return note.richMode == true end },
}

local bar, panel, eb, placeholder, hintFS, emptyFS, helpFS
local rows    = {}
local results = {}
local sel     = 0
local openT   = nil   -- GetTime() of the frame the bar opened in

--------------------------------------------------------------------------------
-- DATA
--------------------------------------------------------------------------------
-- Every live note, in list order. Trashed notes live elsewhere and never show
-- in a normal search: only the `b` prefix (open-as "trash") reaches them.
local function AllNotes()
    local ndb = BigNoteBoxNotesDB
    local out = {}
    if not (ndb and ndb.notes) then return out end
    for _, id in ipairs(ndb.noteOrder or {}) do
        local n = ndb.notes[id]
        if n then out[#out + 1] = n end
    end
    return out
end

local function TrashNotes()
    local ndb = BigNoteBoxNotesDB
    local out = {}
    if not (ndb and ndb.trash) then return out end
    for _, n in pairs(ndb.trash) do out[#out + 1] = n end
    return out
end

--------------------------------------------------------------------------------
-- PREFIXES (ALL-69.2)
--------------------------------------------------------------------------------
-- Localized letter -> role, and date keyword -> kind, maps built from L once
-- (translators may override the English defaults; most will not, per the
-- decision with Dukul 2026-09-26). Passed into OracleSearch.ParseQuery.
local prefixMap, dateWordMap

local function PrefixMap()
    if prefixMap then return prefixMap end
    local OS = BNB.OracleSearch
    prefixMap = {}
    for letter, role in pairs(OS.DEFAULT_PREFIXES) do
        local loc = L[OS.PREFIX_L_KEYS[letter]]
        prefixMap[(type(loc) == "string" and loc ~= "" and loc or letter):lower()] = role
    end
    return prefixMap
end

local function DateWordMap()
    if dateWordMap then return dateWordMap end
    local OS = BNB.OracleSearch
    dateWordMap = {}
    for word, kind in pairs(OS.DEFAULT_DATE_WORDS) do
        local loc = L[OS.DATE_WORD_L_KEYS[word]]
        dateWordMap[(type(loc) == "string" and loc ~= "" and loc or word):lower()] = kind
    end
    return dateWordMap
end

-- role -> localized letter, for the help listing (reverse of PrefixMap()).
local function RoleLetter(role)
    for letter, r in pairs(PrefixMap()) do
        if r == role then return letter end
    end
end

local OPEN_AS_ORDER = { "sticky", "focus", "refbox", "trash" }
local FILTER_ORDER  = { "player", "npc", "item", "zone", "char", "global", "tasks", "alarm", "rich", "plain" }
local ROLE_DESC_KEY = {
    sticky = "ORACLE_PREFIX_DESC_STICKY", focus = "ORACLE_PREFIX_DESC_FOCUS",
    refbox = "ORACLE_PREFIX_DESC_REFBOX", trash = "ORACLE_PREFIX_DESC_TRASH",
    player = "ORACLE_PREFIX_DESC_PLAYER", npc = "ORACLE_PREFIX_DESC_NPC",
    item   = "ORACLE_PREFIX_DESC_ITEM",   zone = "ORACLE_PREFIX_DESC_ZONE",
    char   = "ORACLE_PREFIX_DESC_CHAR",   global = "ORACLE_PREFIX_DESC_GLOBAL",
    tasks  = "ORACLE_PREFIX_DESC_TASKS",  alarm = "ORACLE_PREFIX_DESC_ALARM",
    rich   = "ORACLE_PREFIX_DESC_RICH",   plain = "ORACLE_PREFIX_DESC_PLAIN",
}

-- The full prefix list, shown in the results area when the query is "?".
-- helpLines is the line count, used to size the panel: GetStringHeight() on
-- a FontString the same tick it is first shown can read back 0 (the same
-- "GetWidth() on a newly shown frame" timing gap CLAUDE.md flags for
-- SimpleHTML), which collapsed the panel to one line the first time Kim
-- pressed "?" (found 2026-09-26).
local helpText, helpLines
local HELP_LINE_H = 14
local function HelpText()
    if helpText then return helpText end
    local lines = { L["ORACLE_HELP_OPENAS"] }
    for _, role in ipairs(OPEN_AS_ORDER) do
        local letter = RoleLetter(role)
        if letter then lines[#lines + 1] = ("  %s   %s"):format(letter, L[ROLE_DESC_KEY[role]]) end
    end
    lines[#lines + 1] = ""
    lines[#lines + 1] = L["ORACLE_HELP_FILTERS"]
    for _, role in ipairs(FILTER_ORDER) do
        local letter = RoleLetter(role)
        if letter then lines[#lines + 1] = ("  %s   %s"):format(letter, L[ROLE_DESC_KEY[role]]) end
    end
    local dLetter = RoleLetter("date")
    if dLetter then lines[#lines + 1] = ("  %s   %s"):format(dLetter, L["ORACLE_PREFIX_DESC_DATE"]) end
    lines[#lines + 1] = ""
    lines[#lines + 1] = L["ORACLE_HELP_OTHER"]
    lines[#lines + 1] = "  #tag   " .. L["ORACLE_SYMBOL_DESC_TAG"]
    lines[#lines + 1] = "  @name  " .. L["ORACLE_SYMBOL_DESC_WHO"]
    lines[#lines + 1] = "  *      " .. L["ORACLE_SYMBOL_DESC_FAVORITE"]
    lines[#lines + 1] = "  -word  " .. L["ORACLE_SYMBOL_DESC_EXCLUDE"]
    lines[#lines + 1] = '  "..."  ' .. L["ORACLE_SYMBOL_DESC_PHRASE"]
    helpLines = #lines
    helpText = table.concat(lines, "\n")
    return helpText
end

-- "Global", or the owning character's name.
local function ScopeLabel(note)
    local sc = note.scope
    if not sc or sc == "global" then return L["ORACLE_SCOPE_GLOBAL"] end
    local key = sc:match("^char:(.+)$")
    if not key then return "" end
    local rec = BigNoteBoxDB and BigNoteBoxDB.knownChars and BigNoteBoxDB.knownChars[key]
    return (rec and rec.name) or key:match("^([^-]+)") or key
end

--------------------------------------------------------------------------------
-- OPENING A NOTE
-- Each returns true when the note opened; false keeps the bar open.
--------------------------------------------------------------------------------
-- How a note opened in the main window starts (BigNoteBoxDB.oracleOpenMode,
-- picked on the settings page in ALL-69.4; agreed with Dukul 2026-09-26):
--   "open"   rich notes in View, no cursor
--   "plain"  (default, nil) cursor in the body of plain notes; rich in View
--   "all"    rich notes switch to Editor too, cursor in the body
-- It overrides "Always open rich notes in editor mode" for Oracle opens only.
-- A locked note never gets the cursor.
local function ApplyOpenMode(id)
    local note = BNB.GetNote(id)
    if not note then return end
    local mode = BigNoteBoxDB and BigNoteBoxDB.oracleOpenMode or "plain"
    local rich = BNB.AdvancedMode and BNB.AdvancedMode.IsRich(note)
    if rich then
        if mode == "all" then
            if BNB._editorInViewMode and BNB.AM_EnterEditMode then BNB.AM_EnterEditMode() end
        elseif not BNB._editorInViewMode and BNB.AM_EnterViewMode then
            BNB.AM_EnterViewMode(id)
        end
    end
    local typeHere = (mode == "all") or (mode == "plain" and not rich)
    if not typeHere then return end
    if BNB.IsNoteLockedInEditor and BNB.IsNoteLockedInEditor(id) then return end
    -- A tick later, after the bar has closed and released its own focus.
    C_Timer.After(0.05, function()
        local body = BNB._editorBody
        if body and BNB._currentNoteID == id and body:IsVisible() then body:SetFocus() end
    end)
end

-- noMode: leave the editor as SelectNote left it (focus mode takes over).
local function OpenInMain(id, noMode)
    if InCombatLockdown() then BNB:Print(L["COMBAT_BLOCKED"]); return false end
    if BNB.OpenMainWindow then BNB.OpenMainWindow() end
    if not BNB.mainFrame then return false end
    -- A note the sidebar or the list search hides: show everything first.
    if BNB.RevealNoteInList then BNB.RevealNoteInList(id) end
    if BNB.SaveCurrentNote then BNB.SaveCurrentNote() end
    -- SelectNote refuses while a new note has no title; it says so itself
    -- and focuses the title box, so the bar closes and gets out of the way.
    if BNB.SelectNote then BNB.SelectNote(id) end
    if not noMode and BNB._currentNoteID == id then ApplyOpenMode(id) end
    return true
end

-- As the note list's "Open as sticky": a world sticky, never ESC-only. One
-- already open in the world is only raised (or restored if minimised).
local function OpenAsSticky(id)
    local SN = BNB.Sticky
    if not (SN and SN.Open) then return false end
    if InCombatLockdown() then BNB:Print(L["STICKY_COMBAT"]); return false end
    local db = BigNoteBoxDB
    local cfg = db and db.postits and db.postits[id] and db.postits[id].cfg
    if not (SN.IsOpen(id) and not (cfg and cfg.escOnly)) then
        if db then
            db.postits = db.postits or {}
            db.postits[id] = db.postits[id] or {}
            db.postits[id].cfg = db.postits[id].cfg or {}
            db.postits[id].cfg.escOnly = false
        end
        if SN.IsOpen(id) then SN.Close(id) end
    end
    SN.Open(id)
    return true
end

-- Focus mode edits the selected note, so the note is selected first.
local function OpenInFocus(id)
    if InCombatLockdown() then BNB:Print(L["COMBAT_BLOCKED"]); return false end
    if not OpenInMain(id, true) then return false end
    if BNB._currentNoteID ~= id then return true end   -- SelectNote refused
    if BNB.OpenFocusMode then BNB.OpenFocusMode() end
    return true
end

local function OpenInRefBox(id)
    if BigNoteBoxDB and BigNoteBoxDB.referenceBoxEnabled == false then
        BNB:Print(L["REFBOX_DISABLED"]); return false
    end
    if BNB.OpenReferenceBox then BNB.OpenReferenceBox(id) end
    return true
end

-- The `b` prefix searches the trash and replaces the usual open actions:
-- Enter opens the Trash window (on that note, not scrolled to it -- there is
-- no per-item focus API yet), Shift+Enter restores it. Ctrl/Alt do nothing.
local function OpenTrashResult(id)
    if IsShiftKeyDown() then
        if BNB.RestoreNote then BNB.RestoreNote(id); return true end
        return false
    end
    if BNB.OpenTrashWindow then BNB.OpenTrashWindow(); return true end
    return false
end

-- Shift wins over Ctrl, Ctrl over Alt, when more than one is held. With no
-- modifier, an open-as prefix (s/f/r) picks the action instead of the main
-- window.
local function OpenResult(i)
    local r = results[i]
    if not r then return end
    local id = r.note.id
    if Oracle._openAs == "trash" then
        if OpenTrashResult(id) then Oracle.Close() end
        return
    end
    local ok
    if IsShiftKeyDown() then ok = OpenAsSticky(id)
    elseif IsControlKeyDown() then ok = OpenInFocus(id)
    elseif IsAltKeyDown() then ok = OpenInRefBox(id)
    elseif Oracle._openAs == "sticky" then ok = OpenAsSticky(id)
    elseif Oracle._openAs == "focus" then ok = OpenInFocus(id)
    elseif Oracle._openAs == "refbox" then ok = OpenInRefBox(id)
    else ok = OpenInMain(id) end
    if ok then Oracle.Close() end
end

--------------------------------------------------------------------------------
-- RESULTS
--------------------------------------------------------------------------------
local function SetSelection(i)
    if #results == 0 then sel = 0 else sel = math.max(1, math.min(#results, i)) end
    for n, row in ipairs(rows) do row.selTex:SetShown(n == sel) end
end

local function RowText(row, r)
    local note = r.note
    local icon = BNB.NpcNoteIcon and BNB.NpcNoteIcon(note) or note.icon
    row.icon:SetTexture((icon and icon ~= "") and icon or DEFAULT_ICON)
    local title = (note.title and note.title ~= "") and note.title or L["UNTITLED"]
    row.title:SetText(title)
    local tc = note.titleColor
    if tc then row.title:SetTextColor(tc.r, tc.g, tc.b) else row.title:SetTextColor(1, 1, 1) end
    row.snippet:SetText(r.snippet or "")
    row.scope:SetText(ScopeLabel(note))

    -- Badges from the right edge; the scope label and snippet end left of them.
    local x = -8
    for b, def in ipairs(BADGES) do
        local tex = row.badges[b]
        if def.show(note) then
            if not tex then
                tex = row:CreateTexture(nil, "ARTWORK")
                tex:SetSize(BADGE_SIZE, BADGE_SIZE)
                tex:SetTexture(BADGE_ART .. def.file)
                row.badges[b] = tex
            end
            tex:ClearAllPoints()
            tex:SetPoint("RIGHT", row, "RIGHT", x, 0)
            tex:Show()
            x = x - BADGE_SIZE - BADGE_GAP
        elseif tex then
            tex:Hide()
        end
    end
    if x < -8 then x = x - 4 end   -- a little air between badges and text
    row.scope:ClearAllPoints()
    row.scope:SetPoint("TOPRIGHT", row, "TOPRIGHT", x, -4)
    row.snippet:SetPoint("RIGHT", row, "RIGHT", x, 0)
end

local function BuildRow(i)
    local row = CreateFrame("Button", nil, panel)
    row:SetHeight(ROW_H)
    row:RegisterForClicks("LeftButtonUp")

    local selTex = row:CreateTexture(nil, "BACKGROUND", nil, 1)
    selTex:SetAllPoints()
    selTex:SetColorTexture(BNB.GetSearchHighlight(BigNoteBoxDB and BigNoteBoxDB.oracleTheme))
    selTex:Hide()
    row.selTex = selTex
    row.badges = {}

    local icon = row:CreateTexture(nil, "ARTWORK")
    icon:SetSize(ICON_SIZE, ICON_SIZE)
    icon:SetPoint("LEFT", 6, 0)
    icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    row.icon = icon

    local scope = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    scope:SetPoint("TOPRIGHT", -8, -4)
    scope:SetJustifyH("RIGHT")
    scope:SetWordWrap(false)
    row.scope = scope

    local title = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    title:SetPoint("TOPLEFT", icon, "TOPRIGHT", 8, 0)
    title:SetPoint("RIGHT", scope, "LEFT", -8, 0)
    title:SetJustifyH("LEFT")
    title:SetWordWrap(false)
    row.title = title

    local snippet = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    snippet:SetPoint("BOTTOMLEFT", icon, "BOTTOMRIGHT", 8, 0)
    snippet:SetPoint("RIGHT", row, "RIGHT", -8, 0)
    snippet:SetJustifyH("LEFT")
    snippet:SetWordWrap(false)
    row.snippet = snippet

    row:SetScript("OnEnter", function() SetSelection(i) end)
    row:SetScript("OnClick", function() OpenResult(i) end)
    rows[i] = row
    return row
end

-- Set by Refresh() when the query is "?" (OracleSearch's parsed.help):
-- Layout() then shows the prefix list instead of rows/empty text.
local showingHelp = false

local function Layout()
    local size = panel._size
    local padX = math.floor(size.border * 0.6 + 0.5)
    local padY = math.floor((size.borderY or size.border) * 0.6 + 0.5)
    local y = -padY

    if showingHelp then
        for _, row in ipairs(rows) do row:Hide() end
        emptyFS:Hide()
        helpFS:ClearAllPoints()
        helpFS:SetPoint("TOPLEFT", panel, "TOPLEFT", padX + 6, y - 6)
        helpFS:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -padX - 6, y - 6)
        helpFS:Show()
        hintFS:Hide()
        panel:SetHeight(padY - y + (helpLines or 1) * HELP_LINE_H + 12)
        return
    end
    helpFS:Hide()
    hintFS:Show()

    local n = #results
    for i = 1, MAX_ROWS do
        local row = rows[i]
        if i <= n then
            row = row or BuildRow(i)
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", panel, "TOPLEFT", padX, y)
            row:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -padX, y)
            RowText(row, results[i])
            row:Show()
            y = y - ROW_H - ROW_GAP
        elseif row then
            row:Hide()
        end
    end
    if n == 0 then
        emptyFS:ClearAllPoints()
        emptyFS:SetPoint("TOPLEFT", panel, "TOPLEFT", padX + 6, y - 6)
        emptyFS:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -padX - 6, y - 6)
        emptyFS:Show()
        y = y - 30
    else
        emptyFS:Hide()
    end
    hintFS:ClearAllPoints()
    hintFS:SetPoint("TOPLEFT", panel, "TOPLEFT", padX + 6, y - 2)
    hintFS:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -padX - 6, y - 2)
    panel:SetHeight(-y + HINT_H + padY)
end

local function Refresh()
    local text = eb:GetText() or ""
    if text == "" then placeholder:Show() else placeholder:Hide() end

    local parsed = BNB.OracleSearch.ParseQuery(text, { prefixes = PrefixMap(), dateWords = DateWordMap() })
    Oracle._openAs = parsed.openAs
    showingHelp = parsed.help
    if showingHelp then
        results = {}
        helpFS:SetText(HelpText())
        Layout()
        return
    end

    local notes = (parsed.openAs == "trash") and TrashNotes() or AllNotes()
    local ctx = { charScope = "char:" .. (BNB.currentChar or ""), now = time() }
    results = BNB.OracleSearch.SearchParsed(notes, parsed, { max = MAX_ROWS, ctx = ctx })
    if #results == 0 then
        emptyFS:SetText(#notes == 0 and L["ORACLE_NO_NOTES"] or L["ORACLE_NO_MATCHES"])
    end
    hintFS:SetText(text == "" and L["ORACLE_HINT_EMPTY"] or L["ORACLE_HINT"])
    Layout()
    SetSelection(1)
end

--------------------------------------------------------------------------------
-- KEYS
--------------------------------------------------------------------------------
-- True when key plus the held modifiers is one of the Oracle's bindings. A
-- focused EditBox eats key presses before bindings see them, so pressing the
-- binding again to close has to be caught here.
local function IsOracleBinding(key)
    if key == "LSHIFT" or key == "RSHIFT" or key == "LCTRL" or key == "RCTRL"
        or key == "LALT" or key == "RALT" then return false end
    local combo = (IsAltKeyDown() and "ALT-" or "") .. (IsControlKeyDown() and "CTRL-" or "")
        .. (IsShiftKeyDown() and "SHIFT-" or "") .. key
    for _, b in ipairs({ GetBindingKey("BIGNOTEBOXORACLE") }) do
        if b == combo then return true end
    end
    return false
end

--------------------------------------------------------------------------------
-- BUILD
--------------------------------------------------------------------------------
local function Build()
    bar = CreateFrame("Frame", "BigNoteBoxOracleFrame", UIParent)
    bar:SetFrameStrata("FULLSCREEN_DIALOG")
    bar:SetToplevel(true)
    bar:SetClampedToScreen(true)
    bar:EnableMouse(true)
    bar:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    BNB.ApplySearchChrome(bar, BigNoteBoxDB and BigNoteBoxDB.oracleTheme)
    -- A click on the bar's frame (not the text) puts the cursor back.
    bar:SetScript("OnMouseDown", function() eb:SetFocus() end)

    eb = CreateFrame("EditBox", nil, bar)
    eb:SetPoint("TOPLEFT", bar._searchPieces.text, "TOPLEFT")
    eb:SetPoint("BOTTOMRIGHT", bar._searchPieces.text, "BOTTOMRIGHT")
    eb:SetFontObject("GameFontHighlightLarge")
    eb:SetAutoFocus(false)
    eb:SetMaxLetters(200)

    placeholder = bar:CreateFontString(nil, "OVERLAY", "GameFontDisableLarge")
    placeholder:SetPoint("LEFT", eb, "LEFT", 0, 0)
    placeholder:SetText(L["ORACLE_PLACEHOLDER"])

    panel = CreateFrame("Frame", nil, bar)
    panel:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 0, -PANEL_GAP)
    panel:SetPoint("TOPRIGHT", bar, "BOTTOMRIGHT", 0, -PANEL_GAP)
    panel:EnableMouse(true)
    panel._size = BNB.ApplySearchChrome(panel, BigNoteBoxDB and BigNoteBoxDB.oracleTheme, nil, nil, { panel = true })
        or { border = 24, borderY = 24 }
    -- Esc still closes it if the box has lost focus to another window.
    tinsert(UISpecialFrames, "BigNoteBoxOracleFrame")

    emptyFS = panel:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    emptyFS:SetJustifyH("LEFT")

    helpFS = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    helpFS:SetJustifyH("LEFT")
    helpFS:SetWordWrap(false)
    helpFS:Hide()

    hintFS = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hintFS:SetJustifyH("CENTER")
    hintFS:SetWordWrap(false)
    hintFS:SetText(L["ORACLE_HINT_EMPTY"])

    eb:SetScript("OnTextChanged", function() Refresh() end)
    -- The key that opened the bar can arrive as a typed character in the
    -- same frame (Ctrl+Space types a space): drop anything typed then.
    eb:SetScript("OnChar", function(self)
        if openT and GetTime() == openT then self:SetText("") end
    end)
    eb:SetScript("OnEscapePressed", function() Oracle.Close() end)
    eb:SetScript("OnEnterPressed", function() OpenResult(sel) end)
    eb:SetScript("OnArrowPressed", function(_, key)
        if key == "UP" then SetSelection(sel - 1)
        elseif key == "DOWN" then SetSelection(sel + 1) end
    end)
    eb:SetScript("OnTabPressed", function()
        SetSelection(IsShiftKeyDown() and sel - 1 or sel + 1)
    end)
    eb:SetScript("OnKeyDown", function(self, key)
        if IsOracleBinding(key) then
            Oracle.Close()
        end
    end)

    -- A click anywhere outside the bar and the results closes it.
    bar:SetScript("OnEvent", function(_, event)
        if event == "GLOBAL_MOUSE_DOWN" and bar:IsShown()
            and not bar:IsMouseOver() and not panel:IsMouseOver() then
            Oracle.Close()
        end
    end)
    bar:SetScript("OnShow", function(self) pcall(self.RegisterEvent, self, "GLOBAL_MOUSE_DOWN") end)
    bar:SetScript("OnHide", function(self)
        self:UnregisterEvent("GLOBAL_MOUSE_DOWN")
        eb:ClearFocus()
    end)
    bar:Hide()
end

--------------------------------------------------------------------------------
-- PUBLIC
--------------------------------------------------------------------------------
-- text: optional starting search text (/bnb search raid).
function Oracle.Open(text)
    if not bar then Build() end
    openT = GetTime()
    eb:SetText(text or "")
    eb:SetCursorPosition(#(text or ""))
    Refresh()
    bar:Show()
    bar:Raise()
    -- Focus a frame later, so the key press that opened the bar is spent
    -- before the box can take it as typing.
    C_Timer.After(0, function()
        if bar:IsShown() then eb:SetFocus() end
    end)
end

function Oracle.Close()
    if bar then bar:Hide() end
end

function Oracle.IsOpen()
    return bar ~= nil and bar:IsShown()
end

function Oracle.Toggle()
    if Oracle.IsOpen() then Oracle.Close() else Oracle.Open() end
end

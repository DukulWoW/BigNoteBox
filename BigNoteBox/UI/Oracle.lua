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
local ROW_GAP    = 2
local HINT_H     = 18
local DEFAULT_ICON = "Interface\\Icons\\INV_Misc_Note_06"
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

-- Whose note it is, as the rightmost badge (Dukul, 2026-09-28; it was a
-- "Global" / name label): the globe for a global note, else the owning
-- character's class icon as the main window sidebar shows it (its custom
-- slot icon when one is set), drawn round.
local ROUND_MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local function ScopeKey(note)
    local sc = note.scope
    if not sc or sc == "global" then return nil end
    return sc:match("^char:(.+)$")
end
-- Texture, and true when it is a class icon (drawn round).
local function ScopeIcon(note)
    local key = ScopeKey(note)
    if not key then return BADGE_ART .. "s-icon-global", false end
    local SB = BNB.Sidebar
    return (SB and SB.IconForKey and SB.IconForKey("char:" .. key)) or DEFAULT_ICON, true
end
local function ScopeTip(note)
    local key = ScopeKey(note)
    if not key then return L["ORACLE_SCOPE_GLOBAL"] end
    local rec = BigNoteBoxDB and BigNoteBoxDB.knownChars and BigNoteBoxDB.knownChars[key]
    local name = rec and rec.name and rec.realm and (rec.name .. " - " .. rec.realm)
        or (key:gsub("%-", " - ", 1))
    return string.format(L["ORACLE_SCOPE_CHAR_TIP"], name)
end

-- Small icons on the right of a result, so a note's kind shows at a glance.
-- Drawn right to left in this order: first whose note it is (scope, on every
-- note), then the five that say who the note is about, which never share a
-- note, so they keep the next column. show(note) decides each; tip is the L
-- key of its hover text (tipFn(note) for text that depends on the note).
-- Art by Dukul, 32x32 TGA in Assets\Search\. More kinds are added here.
local BADGES = {
    { scope = true, tipFn = ScopeTip, show = function() return true end },
    { file = "s-icon-npc",      tip = "ORACLE_BADGE_NPC",
      show = function(note) return NpcKind(note) == "npc" end },
    { file = "s-icon-mobs",     tip = "ORACLE_BADGE_MOB",
      show = function(note) return NpcKind(note) == "mob" end },
    { file = "s-icon-elite",    tip = "ORACLE_BADGE_ELITE",
      show = function(note) return NpcKind(note) == "elite" end },
    { file = "s-icon-alliance", tip = "ORACLE_BADGE_ALLIANCE", show = function(note)
        return note.source == "inspect" and note.inspectFaction == "Alliance" end },
    { file = "s-icon-horde",    tip = "ORACLE_BADGE_HORDE", show = function(note)
        return note.source == "inspect" and note.inspectFaction == "Horde" end },
    -- Quest, gossip and book notes (QuickNote.lua); older ones by their quest
    { file = "s-icon-quest",    tip = "ORACLE_BADGE_QUEST", show = function(note)
        return note.source == "quicknote" or BNB.OracleSearch.HasAttachment(note, "quest") end },
    -- An item in the Reference Box, or an item link pasted into the text
    { file = "s-icon-items",    tip = "ORACLE_BADGE_ITEM",
      show = function(note) return BNB.OracleSearch.HasItem(note) end },
    { file = "s-icon-rich",     tip = "ORACLE_BADGE_RICH",
      show = function(note) return note.richMode == true end },
    -- A situation (the note settings Situation tab: zone, instance, player...)
    { file = "s-icon-situation", tip = "ORACLE_BADGE_SITUATION", show = function(note)
        return BNB.HasSituation(note) end },
    -- Only while the Alarms module is on (ALL-343)
    { file = "s-icon-alarm",    tip = "ORACLE_BADGE_ALARM",
      show = function(note) return BNB.AlarmsEnabled() and note.alarm ~= nil end },
    -- Only while the Tasks module is on (ALL-102)
    { file = "s-icon-tasks",    tip = "ORACLE_BADGE_TASKS", show = function(note)
        return BNB.Task ~= nil and BNB.Task.Shows(note.id) end },
}

local bar, panel, eb, placeholder, hintFS, emptyFS
local helpFrame, helpLines   -- the "?" listing, built once (BuildHelp)
local rows    = {}
local results = {}
local sel     = 0
local openT   = nil   -- GetTime() of the frame the bar opened in
local drawnTheme      -- the theme id the bar was last drawn with (ThemeID)
local drawnRev        -- BNB.SEARCH_STYLE_REV it was drawn at (custom style edits)
local fontPath        -- a backdrop theme's font file, nil = WoW's (ApplyFonts)
local previewing = false   -- the settings page's move / preview mode is up
local moveTip              -- "drag to move" strip under the panel, preview only

--------------------------------------------------------------------------------
-- SETTINGS (ALL-69.4, Settings > Modules > Oracle search). nil = default.
--   oracleEnabled     false = the keybinding and /bnb search only say so
--   oracleTheme       search theme id (UI/SearchChrome.lua); nil = the
--                     character's faction theme (Dukul, 2026-09-27)
--   oracleX / Y       bar centre, offset from the screen centre; nil =
--                     DEFAULT_X / DEFAULT_Y (200 px above centre, Dukul)
--   oracleMaxResults  rows shown, 1 to MAX_ROWS
--   oracleKeepOpen    true = the bar stays open after a note opens
--   oracleOpenMode    see ApplyOpenMode;  oracleWeights  see OracleSearch
--------------------------------------------------------------------------------
Oracle.MAX_ROWS = MAX_ROWS
local DEFAULT_X, DEFAULT_Y = 0, 200

-- Theme for a nil oracleTheme: Alliance or Horde by the character's faction,
-- else nil (Neutral), which GetSearchTheme turns into the default theme.
local FACTION_THEME = { Alliance = "alliance", Horde = "horde" }
function Oracle.FactionTheme()
    local faction = UnitFactionGroup("player")
    local id = faction and FACTION_THEME[faction]
    return (id and BNB.SEARCH_THEMES[id]) and id or nil
end

function Oracle.ThemeID()
    local t = BigNoteBoxDB and BigNoteBoxDB.oracleTheme
    if t ~= nil then return t end
    return Oracle.FactionTheme()
end

local function MaxRows()
    local n = BigNoteBoxDB and tonumber(BigNoteBoxDB.oracleMaxResults)
    if not n then return MAX_ROWS end
    return math.max(1, math.min(MAX_ROWS, math.floor(n)))
end

-- Result rows (ALL-69.6, every theme; nil = the default here):
--   oracleTitleSize / oracleSnippetSize   title and preview text, px
--   oracleIconSize  / oracleShowIcons     note icon on the left, false = off
--   oracleBadgeSize / oracleShowBadges    badges on the right, false = off
-- The row height follows them (RowMetrics).
local RESULT_SIZES = {
    title  = { key = "oracleTitleSize",   min = 10, max = 20, def = 13 },
    small  = { key = "oracleSnippetSize", min = 8,  max = 18, def = 11 },
    icon   = { key = "oracleIconSize",    min = 16, max = 40, def = 26, show = "oracleShowIcons" },
    badge  = { key = "oracleBadgeSize",   min = 12, max = 28, def = 18, show = "oracleShowBadges" },
}
Oracle.RESULT_SIZES = RESULT_SIZES

local function RowMetrics()
    local db = BigNoteBoxDB or {}
    local m = {}
    for name, s in pairs(RESULT_SIZES) do
        local n = tonumber(db[s.key])
        n = n and math.max(s.min, math.min(s.max, math.floor(n))) or s.def
        if s.show and db[s.show] == false then n = 0 end
        m[name] = n
    end
    -- Text block: title over preview, at least as tall as the icon, so at
    -- the defaults (26 px icon, 13 + 11 text) the row is the old 36 px.
    m.text = math.max(m.title + m.small + 2, m.icon)
    m.rowH = math.max(m.text + 10, m.badge + 8)
    return m
end

local function KeepOpen()
    return BigNoteBoxDB and BigNoteBoxDB.oracleKeepOpen == true
end

local function ApplyPosition()
    local db = BigNoteBoxDB
    bar:ClearAllPoints()
    bar:SetPoint("CENTER", UIParent, "CENTER",
        db and db.oracleX or DEFAULT_X, db and db.oracleY or DEFAULT_Y)
end

--------------------------------------------------------------------------------
-- DATA
--------------------------------------------------------------------------------
-- Every live note, in list order. Trashed notes live elsewhere and never show
-- in a normal search: only the `b` prefix (open-as "trash") reaches them.
local function AllNotes()
    local ndb = BNB.NotesDB()
    local out = {}
    if not (ndb and ndb.notes) then return out end
    for _, id in ipairs(ndb.noteOrder or {}) do
        local n = ndb.notes[id]
        if n then out[#out + 1] = n end
    end
    return out
end

local function TrashNotes()
    local ndb = BNB.NotesDB()
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

-- The prefixes in use: no alarm filter while the Alarms module is off, no
-- focus open-as while Focus Mode is off (ALL-343), so the letter is plain
-- search text and drops out of the help
local function ActivePrefixes()
    local alarmsOn, focusOn = BNB.AlarmsEnabled(), BNB.FocusEnabled()
    if alarmsOn and focusOn then return PrefixMap() end
    local m = {}
    for letter, role in pairs(PrefixMap()) do
        if (role ~= "alarm" or alarmsOn) and (role ~= "focus" or focusOn) then m[letter] = role end
    end
    return m
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
    for letter, r in pairs(ActivePrefixes()) do
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

-- The localized word for a date kind ("week"), reverse of DateWordMap().
local function DateWord(kind)
    for word, k in pairs(DateWordMap()) do
        if k == kind then return word end
    end
end

-- The "?" listing: a full-width line on how a query is built, then two
-- columns, prefix letters on the left, symbols and examples on the right.
-- Two columns because one ran to ~30 lines, off the bottom of the screen
-- below a centred bar. Each column is a list of lines:
--   { h = text }          header
--   { k = key, d = desc } key (white) and description (grey)
--   { ex = query }        an example query, its { sub = desc } line below
--   { sub = text }        indented grey line
--   {}                    blank
local function HelpColumns()
    local left = { { h = L["ORACLE_HELP_OPENAS"] } }
    for _, role in ipairs(OPEN_AS_ORDER) do
        local letter = RoleLetter(role)
        if letter then left[#left + 1] = { k = letter, d = L[ROLE_DESC_KEY[role]] } end
    end
    left[#left + 1] = {}
    left[#left + 1] = { h = L["ORACLE_HELP_FILTERS"] }
    for _, role in ipairs(FILTER_ORDER) do
        local letter = RoleLetter(role)
        if letter then left[#left + 1] = { k = letter, d = L[ROLE_DESC_KEY[role]] } end
    end
    local d = RoleLetter("date")
    if d then
        left[#left + 1] = { k = d, d = L["ORACLE_PREFIX_DESC_DATE"] }
        local words = {}
        for _, kind in ipairs({ "today", "yesterday", "week", "month", "year" }) do
            words[#words + 1] = DateWord(kind)
        end
        left[#left + 1] = { sub = table.concat(words, ", ") }
        left[#left + 1] = { sub = L["ORACLE_HELP_DATE_NUMBERS"] }
    end

    local right = { { h = L["ORACLE_HELP_OTHER"] },
        { k = "#tag",  d = L["ORACLE_SYMBOL_DESC_TAG"] },
        { k = "@name", d = L["ORACLE_SYMBOL_DESC_WHO"] },
        { k = "*",     d = L["ORACLE_SYMBOL_DESC_FAVORITE"] },
        { k = "-word", d = L["ORACLE_SYMBOL_DESC_EXCLUDE"] },
        { k = '"..."', d = L["ORACLE_SYMBOL_DESC_PHRASE"] },
        {},
        { h = L["ORACLE_HELP_EXAMPLES"] },
    }
    -- Example queries are format strings filled with this locale's letters
    -- (and date word), so they always show what really works.
    local function example(fmtKey, ...)
        for i = 1, select("#", ...) do
            if not (select(i, ...)) then return end   -- a letter the locale left out
        end
        right[#right + 1] = { ex = L[fmtKey]:format(...) }
        right[#right + 1] = { sub = L[fmtKey .. "_DESC"] }
    end
    example("ORACLE_EX_1", RoleLetter("sticky"))
    example("ORACLE_EX_2", RoleLetter("player"), RoleLetter("tasks"))
    example("ORACLE_EX_3", d, DateWord("week"))
    example("ORACLE_EX_4", d)
    example("ORACLE_EX_5", RoleLetter("npc"))
    return left, right
end

-- Builds the listing once, as its own frame on the results panel; Layout()
-- only shows it and sizes the panel from helpLines. Fixed line pitch, never
-- a measured string height (GetStringHeight() reads 0 the tick a string
-- first shows), and one FontString per line: a single multi-line one with
-- SetWordWrap(false) showed only its first line plus "..." (2026-09-26).
local HELP_LINE_H  = 14
local HELP_KEY_W   = { 18, 42 }   -- key column, left and right
local HELP_INDENT  = 14           -- a { sub } line under an example
local HELP_COL_GAP = 12

local function BuildHelp()
    helpFrame = CreateFrame("Frame", nil, panel)
    local function FS(font, text)
        local fs = helpFrame:CreateFontString(nil, "OVERLAY", font)
        fs:SetJustifyH("LEFT")
        fs:SetWordWrap(false)
        fs:SetText(text)
        return fs
    end

    local intro = FS("GameFontHighlightSmall", L["ORACLE_HELP_SYNTAX"])
    intro:SetPoint("TOPLEFT", helpFrame, "TOPLEFT", 0, 0)
    intro:SetPoint("TOPRIGHT", helpFrame, "TOPRIGHT", 0, 0)

    local left, right = HelpColumns()
    local most = 0
    for c, col in ipairs({ left, right }) do
        -- Column c runs from its left edge to the frame's middle (left) or
        -- right edge (right); text that would cross it ends in "..." instead.
        local x0          = (c == 1) and 0 or HELP_COL_GAP / 2
        local anchor      = (c == 1) and "TOPLEFT" or "TOP"
        local rightEdge   = (c == 1) and -HELP_COL_GAP / 2 or 0
        local rightAnchor = (c == 1) and "TOP" or "TOPRIGHT"
        for i, line in ipairs(col) do
            local y = -(i + 1) * HELP_LINE_H   -- below the intro and a blank line
            local fs, x
            if line.h then
                fs, x = FS("GameFontNormalSmall", line.h), x0
            elseif line.k then
                local key = FS("GameFontHighlightSmall", line.k)
                key:SetPoint("TOPLEFT", helpFrame, anchor, x0 + 4, y)
                fs, x = FS("GameFontDisableSmall", line.d), x0 + 4 + HELP_KEY_W[c]
            elseif line.ex then
                fs, x = FS("GameFontHighlightSmall", line.ex), x0 + 4
            elseif line.sub then
                -- Under `d` it lines up with the descriptions, under an
                -- example it is indented a little.
                local indent = (c == 1) and HELP_KEY_W[1] or HELP_INDENT
                fs, x = FS("GameFontDisableSmall", line.sub), x0 + 4 + indent
            end
            if fs then
                fs:SetPoint("TOPLEFT", helpFrame, anchor, x, y)
                fs:SetPoint("RIGHT", helpFrame, rightAnchor, rightEdge, 0)
            end
        end
        most = math.max(most, #col)
    end
    helpLines = most + 2
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
    -- A bar that stays open keeps the keyboard (AfterOpen).
    if KeepOpen() then return end
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
-- Enter opens the Trash window scrolled to that note, which flashes;
-- Shift+Enter restores it (a chat line says so, the bar has closed by then).
-- Ctrl/Alt do nothing extra.
local function OpenTrashResult(id)
    if IsShiftKeyDown() then
        if not BNB.RestoreNote then return false end
        local tn = ((BNB.NotesDB() or {}).trash or {})[id]
        local title = tn and tn.title ~= "" and tn.title or L["UNTITLED"]
        BNB.RestoreNote(id)
        BNB:Print(L["ORACLE_RESTORED_FMT"]:format(title))
        return true
    end
    if BNB.OpenTrashWindow then BNB.OpenTrashWindow(id); return true end
    return false
end

-- Shift wins over Ctrl, Ctrl over Alt, when more than one is held. With no
-- modifier, an open-as prefix (s/f/r) picks the action instead of the main
-- window.
-- After a note opened: close the bar, or, with "Close after opening a note"
-- off, keep it up with the keyboard so several notes can be opened in a row.
-- A sticky or window that opened may have been raised over it.
local function AfterOpen()
    if not KeepOpen() then Oracle.Close(); return end
    C_Timer.After(0, function()
        if not bar:IsShown() then return end
        bar:Raise()
        BNB.PlaceSearchPanel(panel, bar, drawnTheme)
        eb:SetFocus()
    end)
end

local function OpenResult(i)
    local r = results[i]
    if not r then return end
    local id = r.note.id
    if Oracle._openAs == "trash" then
        if OpenTrashResult(id) then AfterOpen() end
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
    if ok then AfterOpen() end
end

--------------------------------------------------------------------------------
-- RESULTS
--------------------------------------------------------------------------------
local function SetSelection(i)
    if #results == 0 then sel = 0 else sel = math.max(1, math.min(#results, i)) end
    for n, row in ipairs(rows) do row.selTex:SetShown(n == sel) end
end

-- How many badges a note shows (none while badges are off).
local function BadgeCount(note, m)
    local n = 0
    if m.badge == 0 then return 0 end
    for _, def in ipairs(BADGES) do
        if def.show(note) then n = n + 1 end
    end
    return n
end

-- textRight: x offset from the row's right edge where the scope label and
-- snippet end. The same for every row (Layout sizes it to the row with the
-- most badges), so the text lines up and does not shift with the badges.
local function RowText(row, r, textRight, m)
    local note = r.note
    local icon = BNB.NpcNoteIcon and BNB.NpcNoteIcon(note) or note.icon
    row.icon:SetTexture((icon and icon ~= "") and icon or DEFAULT_ICON)
    -- NPC notes: the NPC's face, as in the note list (ALL-46). Until its
    -- display ID is looked up the note icon stays; Oracle.RefreshPortraits
    -- redraws when the lookup finishes.
    if BNB.SetNpcNotePortrait then BNB.SetNpcNotePortrait(row.icon, note) end
    if BNB.ApplyIconFrame then BNB.ApplyIconFrame(row.icon, note) end
    local title = (note.title and note.title ~= "") and note.title or L["UNTITLED"]
    row.title:SetText(title)
    local tc = note.titleColor
    if tc then row.title:SetTextColor(tc.r, tc.g, tc.b) else row.title:SetTextColor(1, 1, 1) end
    row.snippet:SetText(r.snippet or "")
    row.scope:SetText("")   -- the scope is the rightmost badge now

    -- Badges from the right edge, inside the column right of textRight.
    local x = -8
    for b, def in ipairs(BADGES) do
        local badge = row.badges[b]
        if m.badge > 0 and def.show(note) then
            if not badge then
                -- A small frame, not a bare texture, so it can show what it
                -- means on hover. It takes the mouse from the row, so it
                -- passes hover (selection) and clicks (open) on to it.
                badge = CreateFrame("Frame", nil, row)
                badge:SetSize(m.badge, m.badge)
                badge:EnableMouse(true)
                local tex = badge:CreateTexture(nil, "ARTWORK")
                tex:SetAllPoints()
                if def.file then tex:SetTexture(BADGE_ART .. def.file) end
                badge.tex = tex
                if def.scope then
                    -- A second, masked texture for the round class icon
                    local round = badge:CreateTexture(nil, "ARTWORK")
                    round:SetAllPoints()
                    pcall(round.SetMask, round, ROUND_MASK)
                    badge.round = round
                end
                badge:SetScript("OnEnter", function(self)
                    local onEnter = row:GetScript("OnEnter")
                    if onEnter then onEnter(row) end
                    GameTooltip:SetOwner(self, "ANCHOR_TOP")
                    local text = def.tipFn and self._note and def.tipFn(self._note) or L[def.tip]
                    GameTooltip:SetText(text, 1, 1, 1)
                    GameTooltip:Show()
                end)
                badge:SetScript("OnLeave", function() GameTooltip:Hide() end)
                badge:SetScript("OnMouseUp", function(self, button)
                    if (button == "LeftButton" or button == "RightButton") and self:IsMouseOver() then
                        row:Click(button)
                    end
                end)
                row.badges[b] = badge
            end
            badge._note = note
            if def.scope then
                local file, round = ScopeIcon(note)
                badge.tex:SetShown(not round)
                badge.round:SetShown(round)
                if round then badge.round:SetTexture(file) else badge.tex:SetTexture(file) end
            end
            badge:SetSize(m.badge, m.badge)
            badge:ClearAllPoints()
            badge:SetPoint("RIGHT", row, "RIGHT", x, 0)
            badge:Show()
            x = x - m.badge - BADGE_GAP
        elseif badge then
            badge:Hide()
        end
    end
    row.scope:ClearAllPoints()
    row.scope:SetPoint("TOPRIGHT", row, "TOPRIGHT", textRight, -4)
    row.snippet:SetPoint("RIGHT", row, "RIGHT", textRight, 0)
end

-- A row's text in the theme's font (ALL-69.5): only a backdrop theme sets
-- one (fontPath); nil puts WoW's font objects back. The font's size setting
-- is for the typed text; the rows take the Results sizes (ALL-69.6). On
-- WoW's font they scale the font object (SetTextScale) instead of a raw
-- SetFont, which would drop its per-alphabet fallback on translated titles;
-- the scale is relative to the default size, so the defaults look as before.
local function ScaleText(fs, px, def)
    if fs.SetTextScale then pcall(fs.SetTextScale, fs, fontPath and 1 or px / def) end
end
local function RowFonts(row, m)
    m = m or RowMetrics()
    local T, S = RESULT_SIZES.title.def, RESULT_SIZES.small.def
    BNB.SetFontSafe(row.title,   fontPath, m.title, "GameFontHighlight")
    BNB.SetFontSafe(row.snippet, fontPath, m.small, "GameFontDisableSmall")
    BNB.SetFontSafe(row.scope,   fontPath, m.small, "GameFontDisableSmall")
    ScaleText(row.title, m.title, T)
    ScaleText(row.snippet, m.small, S)
    ScaleText(row.scope, m.small, S)
    row._fontSig = (fontPath or "") .. ":" .. m.title .. ":" .. m.small
end

-- Sizes a row for m (RowMetrics): height, icon (hidden at 0) and the two
-- text lines centred as a block, left of them the icon when it shows.
local function RowLayout(row, m)
    row:SetHeight(m.rowH)
    local icon = row.icon
    icon:SetShown(m.icon > 0)
    if m.icon > 0 then icon:SetSize(m.icon, m.icon) end
    local left = (m.icon > 0) and (6 + m.icon + 8) or 8
    local top = math.floor((m.rowH - m.text) / 2 + 0.5)
    row.title:ClearAllPoints()
    row.title:SetPoint("TOPLEFT", row, "TOPLEFT", left, -top)
    row.title:SetPoint("RIGHT", row.scope, "LEFT", -8, 0)
    row.snippet:ClearAllPoints()
    row.snippet:SetPoint("BOTTOMLEFT", row, "TOPLEFT", left, -(top + m.text))
    local sig = (fontPath or "") .. ":" .. m.title .. ":" .. m.small
    if row._fontSig ~= sig then RowFonts(row, m) end
end

-- A result row on parent. onEnter / onClick: nil for the layout tool's
-- preview rows, which take no mouse at all. Sizes and text anchors are set
-- by RowLayout on every layout.
local function BuildRow(parent, onEnter, onClick)
    local row = CreateFrame("Button", nil, parent)
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    local selTex = row:CreateTexture(nil, "BACKGROUND", nil, 1)
    selTex:SetAllPoints()
    selTex:SetColorTexture(BNB.GetSearchHighlight(Oracle.ThemeID()))
    selTex:Hide()
    row.selTex = selTex
    row.badges = {}

    local icon = row:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("LEFT", 6, 0)
    icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    row.icon = icon

    local scope = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    scope:SetPoint("TOPRIGHT", -8, -4)
    scope:SetJustifyH("RIGHT")
    scope:SetWordWrap(false)
    row.scope = scope

    local title = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    title:SetJustifyH("LEFT")
    title:SetWordWrap(false)
    row.title = title

    local snippet = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    snippet:SetJustifyH("LEFT")
    snippet:SetWordWrap(false)
    row.snippet = snippet

    if onEnter then row:SetScript("OnEnter", onEnter) end
    if onClick then row:SetScript("OnClick", onClick) else row:EnableMouse(false) end
    RowLayout(row, RowMetrics())
    return row
end

-- Right-click on a result: the note list's menu (ALL-148). Any entry
-- clicked closes the bar, as opening a result does. Not for trash results:
-- the menu is for live notes.
local function ResultMenu(row, i)
    local r = results[i]
    if not (r and BNB.ShowNoteContextMenu) or Oracle._openAs == "trash" then return end
    SetSelection(i)
    BNB.ShowNoteContextMenu(row, r.note.id, nil, Oracle.Close)
end

-- The real list's row i.
local function MainRow(i)
    rows[i] = BuildRow(panel, function() SetSelection(i) end, function(self, button)
        if button == "RightButton" then ResultMenu(self, i) else OpenResult(i) end
    end)
    return rows[i]
end

-- Lays out list (results) on the rows of parent from y down, building rows
-- with build(i) as needed, one badge column for all. Returns the new y.
-- pad: the theme's content inset (BNB.GetSearchPanelPad), left / right used here.
local function PlaceRows(parent, rowList, list, y, pad, build)
    local n = #list
    local m = RowMetrics()
    -- Badge column as wide as the row with the most badges, plus a little
    -- air between badges and text.
    local most = 0
    for i = 1, n do most = math.max(most, BadgeCount(list[i].note, m)) end
    local textRight = -8
    if most > 0 then textRight = -8 - most * (m.badge + BADGE_GAP) - 4 end
    for i = 1, math.max(MAX_ROWS, #rowList) do
        local row = rowList[i]
        if i <= n then
            row = row or build(i)
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", parent, "TOPLEFT", pad.left, y)
            row:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -pad.right, y)
            RowLayout(row, m)
            RowText(row, list[i], textRight, m)
            row:Show()
            y = y - m.rowH - ROW_GAP
        elseif row then
            row:Hide()
        end
    end
    return y
end

-- Set by Refresh() when the query is "?" (OracleSearch's parsed.help):
-- Layout() then shows the prefix list instead of rows/empty text.
local showingHelp = false

local function Layout()
    -- Where the content sits inside the panel art (the theme's panelPad).
    local pad = panel._pad
    local y = -pad.top

    if showingHelp then
        for _, row in ipairs(rows) do row:Hide() end
        emptyFS:Hide()
        if not helpFrame then BuildHelp() end
        helpFrame:ClearAllPoints()
        helpFrame:SetPoint("TOPLEFT", panel, "TOPLEFT", pad.left + 6, y - 6)
        helpFrame:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -pad.right - 6, y - 6)
        helpFrame:SetHeight(helpLines * HELP_LINE_H)
        helpFrame:Show()
        hintFS:Hide()
        panel:SetHeight(pad.bottom - y + helpLines * HELP_LINE_H + 12)
        return
    end
    if helpFrame then helpFrame:Hide() end
    hintFS:Show()

    local n = #results
    y = PlaceRows(panel, rows, results, y, pad, MainRow)
    if n == 0 then
        emptyFS:ClearAllPoints()
        emptyFS:SetPoint("TOPLEFT", panel, "TOPLEFT", pad.left + 6, y - 6)
        emptyFS:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -pad.right - 6, y - 6)
        emptyFS:Show()
        y = y - 30
    else
        emptyFS:Hide()
    end
    hintFS:ClearAllPoints()
    hintFS:SetPoint("TOPLEFT", panel, "TOPLEFT", pad.left + 6, y - 2)
    hintFS:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -pad.right - 6, y - 2)
    panel:SetHeight(-y + HINT_H + pad.bottom)
end

-- Where the player is, for the "current zone" weight (ALL-69.3).
local function ZoneCtx()
    if not BNB.GetCurrentZone then return nil end
    local kind, name = BNB.GetCurrentZone()
    return { kind = kind, name = (name or ""):lower(),
             sub = ((GetSubZoneText and GetSubZoneText()) or ""):lower() }
end

-- The current target, for the "current target" weight: matched on the
-- same fields a target or inspect note saves. Unit data can be a secret
-- value on Midnight (combat, instances), so it is read in a pcall and a
-- failure only drops the weight.
local function TargetCtx()
    if not UnitExists("target") then return nil end
    local ok, t = pcall(function()
        local name, realm = BNB.UnitNameRealm("target")
        if not name then return nil end
        local out = { name = name, isPlayer = UnitIsPlayer("target") and true or false }
        if out.isPlayer then
            out.realm = (realm and realm ~= "") and realm or GetNormalizedRealmName() or ""
        else
            local guid = UnitGUID("target")
            out.npcID = guid and BNB.CreatureIDFromGUID and BNB.CreatureIDFromGUID(guid)
            out.isPet = guid and guid:find("^Pet%-") and true or false
        end
        return out
    end)
    return ok and t or nil
end

-- The saved weights, with the alarm boost off while the Alarms module is
-- off (ALL-343). A copy: the saved table is never changed.
local function AlarmlessWeights(w)
    if BNB.AlarmsEnabled() then return w end
    local c = {}
    for k, v in pairs(w or {}) do c[k] = v end
    c.alarm = "off"
    return c
end

local function Refresh()
    if previewing then return end   -- the preview draws its own rows
    local text = eb:GetText() or ""
    if text == "" then placeholder:Show() else placeholder:Hide() end

    local parsed = BNB.OracleSearch.ParseQuery(text, { prefixes = ActivePrefixes(), dateWords = DateWordMap() })
    Oracle._openAs = parsed.openAs
    showingHelp = parsed.help
    if showingHelp then
        results = {}
        Layout()
        return
    end

    local notes = (parsed.openAs == "trash") and TrashNotes() or AllNotes()
    local ctx = {
        charScope = "char:" .. (BNB.currentChar or ""), now = time(),
        -- Reference Box items store only an id; nil while the item is uncached.
        itemName = function(itemID) return (C_Item.GetItemInfo(itemID)) end,
        -- Weights (ALL-69.3): levels per boost, nil = the defaults.
        weights = AlarmlessWeights(BigNoteBoxDB and BigNoteBoxDB.oracleWeights),
        zone = ZoneCtx(), target = TargetCtx(),
    }
    results = BNB.OracleSearch.SearchParsed(notes, parsed, { max = MaxRows(), ctx = ctx })
    if #results == 0 then
        emptyFS:SetText(#notes == 0 and L["ORACLE_NO_NOTES"] or L["ORACLE_NO_MATCHES"])
    end
    if text == "" then hintFS:SetText(L["ORACLE_HINT_EMPTY"])
    elseif parsed.openAs == "trash" then hintFS:SetText(L["ORACLE_HINT_TRASH"])
    else hintFS:SetText(L["ORACLE_HINT"]) end
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
-- MOVE / PREVIEW (ALL-69.4)
-- The settings page shows the real bar at its saved spot with sample results
-- (the layout tool's fake notes, PREVIEW below) for as long as the page is
-- open. While it is up the bar takes no typing, a click outside leaves it
-- open, and a drag on the bar or its results moves it; leaving the page ends it.
-- Theme and result-count changes redraw it at once (Oracle.RefreshPreview).
--------------------------------------------------------------------------------
local function SavePosition()
    local cx, cy = bar:GetCenter()
    local scx, scy = UIParent:GetCenter()
    if not (cx and scx) then return end
    if BigNoteBoxDB then
        BigNoteBoxDB.oracleX = math.floor(cx - scx + 0.5)
        BigNoteBoxDB.oracleY = math.floor(cy - scy + 0.5)
    end
    ApplyPosition()
end

-- The preview lives exactly as long as the settings page (Dukul, 2026-09-28),
-- so the tip has no Done button.
local function BuildMoveTip()
    moveTip = BNB.CreateBackdropFrame("Frame", nil, bar)
    moveTip:SetSize(240, 30)
    BNB.SetBackdrop(moveTip, 0.10, 0.10, 0.12, 0.92, 0.45, 0.70, 0.45, 1)
    local fs = moveTip:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    fs:SetPoint("LEFT", moveTip, "LEFT", 8, 0)
    fs:SetPoint("RIGHT", moveTip, "RIGHT", -8, 0)
    fs:SetJustifyH("CENTER")
    fs:SetWordWrap(false)
    fs:SetText(L["ORACLE_MOVE_TIP"])
end

-- Esc closes the bar through a proxy: a 1 px frame that is in UISpecialFrames
-- for good and is shown only while the bar is up and not previewing. Esc hides
-- the proxy, the proxy closes the bar. (It used to take the bar's own name out
-- of UISpecialFrames with table.remove, which shifts other addons' entries,
-- GLB-04.) While previewing, Esc goes to the settings page (back one page).
local escProxy
local function SyncEscProxy()
    if not escProxy then return end
    local want = bar and bar:IsShown() and not previewing
    if want then escProxy:Show() else
        escProxy._quiet = true; escProxy:Hide(); escProxy._quiet = nil
    end
end

-- While previewing, the bar sits under dialogs (HIGH, not FULLSCREEN_DIALOG),
-- so the colour picker and the style popups open over it.
local function SetPreviewLayer(on)
    bar:SetFrameStrata(on and "HIGH" or "FULLSCREEN_DIALOG")
    SyncEscProxy()
end

local function DrawPreviewRows()
    for _, row in ipairs(rows) do row:Hide() end
    emptyFS:Hide(); hintFS:Hide()
    if helpFrame then helpFrame:Hide() end
    Oracle.DrawPreview(panel, drawnTheme, MaxRows())
    panel._hint:Show()
    -- Under the results, which change height with the row count.
    moveTip:ClearAllPoints()
    moveTip:SetPoint("TOP", panel, "BOTTOM", 0, -8)
end

-- Run from the bar's OnHide: whatever hid it, the preview is over.
-- Only while the bar really is hidden: on the first open after a reload the
-- OnHide from Build's own Hide came after StartPreview had set previewing,
-- which cleared it with the bar up, and the next click closed the bar
-- (Dukul, 2026-09-28).
local function ClearPreview()
    if not previewing or bar:IsShown() then return end
    previewing = false
    SetPreviewLayer(false)
    if moveTip then moveTip:Hide() end
    eb:EnableMouse(true)
    for _, row in ipairs(panel._rows or {}) do row:Hide() end
    if panel._hint then panel._hint:Hide() end
end

-- The typed text, the placeholder and the rows in the theme's font. A
-- plain SetFont on the box (not SetFontSafe: its re-apply re-sets the text,
-- which would move the cursor while typing).
local function ApplyFonts(themeID)
    local path, size = BNB.GetSearchFont(themeID)
    fontPath = path
    eb:SetFontObject("GameFontHighlightLarge")
    placeholder:SetFontObject("GameFontDisableLarge")
    if path then
        local px = BNB.FontPx(path, size)
        pcall(eb.SetFont, eb, path, px, "")
        pcall(placeholder.SetFont, placeholder, path, px, "")
    elseif size then
        -- A backdrop theme on WoW's font still takes the size.
        local file, _, flags = eb:GetFont()
        if file then
            pcall(eb.SetFont, eb, file, size, flags or "")
            pcall(placeholder.SetFont, placeholder, file, size, flags or "")
        end
    end
    for _, row in ipairs(rows) do RowFonts(row) end
    for _, row in ipairs(panel._rows or {}) do RowFonts(row) end
end

--------------------------------------------------------------------------------
-- BUILD
--------------------------------------------------------------------------------
local function Build()
    bar = CreateFrame("Frame", "BigNoteBoxOracleFrame", UIParent)
    bar:SetFrameStrata("FULLSCREEN_DIALOG")
    -- Room below the bar, so the results can draw under it (panelPos.under).
    bar:SetFrameLevel(BNB.SEARCH_BAR_LEVEL)
    bar:SetToplevel(true)
    bar:SetClampedToScreen(true)
    bar:EnableMouse(true)
    ApplyPosition()
    drawnTheme = Oracle.ThemeID()
    BNB.ApplySearchChrome(bar, drawnTheme)
    -- A click on the bar's frame (not the text) puts the cursor back.
    -- A click raises the bar (SetToplevel), lifting the results with it:
    -- put them back under it after the raise.
    bar:SetScript("OnMouseDown", function(_, button)
        if previewing then return end
        if button == "RightButton" then Oracle.OpenSettings(); return end
        eb:SetFocus()
        C_Timer.After(0, function() BNB.PlaceSearchPanel(panel, bar, drawnTheme) end)
    end)

    eb = CreateFrame("EditBox", nil, bar)
    eb:SetPoint("TOPLEFT", bar._searchPieces.text, "TOPLEFT")
    eb:SetPoint("BOTTOMRIGHT", bar._searchPieces.text, "BOTTOMRIGHT")
    eb:SetFontObject("GameFontHighlightLarge")
    eb:SetAutoFocus(false)
    eb:SetMaxLetters(200)

    -- A right-click in the text opens the settings page, as on the bar.
    eb:HookScript("OnMouseDown", function(_, button)
        if button == "RightButton" and not previewing then Oracle.OpenSettings() end
    end)

    placeholder = bar:CreateFontString(nil, "OVERLAY", "GameFontDisableLarge")
    placeholder:SetPoint("LEFT", eb, "LEFT", 0, 0)
    placeholder:SetText(L["ORACLE_PLACEHOLDER"])

    panel = CreateFrame("Frame", nil, bar)
    BNB.PlaceSearchPanel(panel, bar, drawnTheme)   -- the theme's panelPos
    panel:EnableMouse(true)
    panel:SetScript("OnMouseDown", function(_, button)
        if previewing then return end
        if button == "RightButton" then Oracle.OpenSettings(); return end
        C_Timer.After(0, function() BNB.PlaceSearchPanel(panel, bar, drawnTheme) end)
    end)
    panel._size = BNB.ApplySearchChrome(panel, drawnTheme, nil, nil, { panel = true })
        or { border = 24, borderY = 24 }
    panel._pad = BNB.GetSearchPanelPad(drawnTheme, panel._size)
    drawnRev = BNB.SEARCH_STYLE_REV
    ApplyFonts(drawnTheme)
    -- Esc still closes it if the box has lost focus to another window
    -- (through the proxy, see SyncEscProxy).
    escProxy = CreateFrame("Frame", "BigNoteBoxOracleEscProxy", UIParent)
    escProxy:SetSize(1, 1)
    escProxy:Hide()
    escProxy:SetScript("OnHide", function(self)
        if self._quiet then return end
        if bar:IsShown() and not previewing then bar:Hide() end
    end)
    tinsert(UISpecialFrames, "BigNoteBoxOracleEscProxy")

    emptyFS = panel:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    emptyFS:SetJustifyH("LEFT")


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
    -- Arrows and Tab wrap: down from the last result goes to the first,
    -- up from the first to the last (Dukul, 2026-09-27).
    local function Step(d)
        local n = #results
        if n == 0 then return end
        SetSelection((sel - 1 + d) % n + 1)
    end
    eb:SetScript("OnArrowPressed", function(_, key)
        if key == "UP" then Step(-1)
        elseif key == "DOWN" then Step(1) end
    end)
    eb:SetScript("OnTabPressed", function()
        Step(IsShiftKeyDown() and -1 or 1)
    end)
    eb:SetScript("OnKeyDown", function(self, key)
        if IsOracleBinding(key) then
            Oracle.Close()
        end
    end)

    -- A click anywhere outside the bar and the results closes it. A result's
    -- right-click menu sits outside both and counts as inside (ALL-148).
    bar:SetScript("OnEvent", function(_, event)
        if event == "GLOBAL_MOUSE_DOWN" and bar:IsShown() and not previewing
            and not bar:IsMouseOver() and not panel:IsMouseOver()
            and not (BNB.ContextMenu and BNB.ContextMenu.IsMouseOver()) then
            Oracle.Close()
        end
    end)
    bar:SetScript("OnShow", function(self)
        pcall(self.RegisterEvent, self, "GLOBAL_MOUSE_DOWN")
        SyncEscProxy()
    end)
    bar:SetScript("OnHide", function(self)
        ClearPreview()
        self:UnregisterEvent("GLOBAL_MOUSE_DOWN")
        eb:ClearFocus()
        SyncEscProxy()
    end)

    -- Dragging moves the bar in the preview only. SetUserPlaced(false)
    -- keeps WoW's layout cache out of it: the position is ours to save.
    bar:SetMovable(true)
    bar:RegisterForDrag("LeftButton")
    panel:RegisterForDrag("LeftButton")
    local function DragStart() if previewing then bar:StartMoving() end end
    local function DragStop()
        bar:StopMovingOrSizing()
        bar:SetUserPlaced(false)
        if previewing then SavePosition() end
    end
    bar:SetScript("OnDragStart", DragStart)
    bar:SetScript("OnDragStop", DragStop)
    panel:SetScript("OnDragStart", DragStart)
    panel:SetScript("OnDragStop", DragStop)
    -- ALL-95: move cursor while the settings page's preview lets it drag
    local function MoveKind() if previewing then return "move" end end
    BNB.SetHoverCursor(bar, MoveKind)
    BNB.SetHoverCursor(panel, MoveKind)
    bar:Hide()
end

--------------------------------------------------------------------------------
-- PUBLIC
--------------------------------------------------------------------------------
-- text: optional starting search text (/bnb search raid).
-- Redraws the bar, the results panel and the row highlight when the theme
-- setting changed since the bar was last drawn, so a new theme shows on
-- the next open without a reload.
local function SyncTheme()
    local want = Oracle.ThemeID()
    if want == drawnTheme and drawnRev == BNB.SEARCH_STYLE_REV then return end
    drawnTheme, drawnRev = want, BNB.SEARCH_STYLE_REV
    ApplyFonts(want)
    BNB.ApplySearchChrome(bar, want)
    panel._size = BNB.ApplySearchChrome(panel, want, nil, nil, { panel = true }) or panel._size
    panel._pad = BNB.GetSearchPanelPad(want, panel._size)
    BNB.PlaceSearchPanel(panel, bar, want)
    for _, row in ipairs(rows) do row.selTex:SetColorTexture(BNB.GetSearchHighlight(want)) end
end

function Oracle.Open(text)
    if BigNoteBoxDB and BigNoteBoxDB.oracleEnabled == false then
        BNB:Print(L["ORACLE_OFF"]); return
    end
    Oracle.EndPreview()
    if not bar then Build() else SyncTheme() end
    openT = GetTime()
    eb:SetText(text or "")
    eb:SetCursorPosition(#(text or ""))
    Refresh()
    bar:Show()
    bar:Raise()
    BNB.PlaceSearchPanel(panel, bar, drawnTheme)   -- raising lifted the panel too
    -- Focus a frame later, so the key press that opened the bar is spent
    -- before the box can take it as typing.
    C_Timer.After(0, function()
        if bar:IsShown() then eb:SetFocus() end
    end)
end

-- Fake results for the search bar layout tool (BigNoteBox_Dev Labs/SearchLayoutTool.lua), drawn
-- with the real row code so a theme is judged on what players see. Between
-- them they show every badge. Developer tool only, so plain English.
local PREVIEW = {
    { note = { title = "Hogger", source = "target", targetAttackable = true,
        targetClassification = "elite", icon = "Interface\\Icons\\INV_Misc_Head_Orc_01" },
      snippet = "Elite gnoll in Elwynn Forest. Pull him away from the camp." },
    { note = { title = "Thrall", source = "inspect", inspectFaction = "Horde",
        icon = "Interface\\Icons\\Ability_Warrior_BattleShout" },
      snippet = "Met him in Orgrimmar, asked about the Earthen Ring." },
    { note = { title = "Raid tactics", richMode = true, titleColor = { r = 1, g = 0.5, b = 0.25 },
        icon = "Interface\\Icons\\INV_Misc_Book_09" },
      snippet = "Phase two: spread out, tank faces the boss away from the group." },
    { note = { title = "Shopping list", body = "|Hitem:1:|h[Flask]|h", scope = "char:Dukul-Realm",
        icon = "Interface\\Icons\\INV_Misc_Bag_08" },
      snippet = "Flasks, food and a stack of runes before Thursday." },
    { note = { title = "The Missing Diplomat", source = "quicknote" },
      snippet = "Quest chain: start in Stormwind, then Westfall and Duskwood." },
}

-- Draws the preview rows on pv, a results panel the layout tool has
-- themed (pv._size set by ApplySearchChrome; pv._pad optional), and sizes it. Row 1 shows
-- selected, in the theme's highlight colour. count: how many rows (1 to
-- MAX_ROWS, the fake notes repeat); left out = all of them.
function Oracle.DrawPreview(pv, themeID, count)
    pv._rows = pv._rows or {}
    local list = PREVIEW
    if count then
        list = {}
        for i = 1, math.max(1, math.min(MAX_ROWS, count)) do list[i] = PREVIEW[(i - 1) % #PREVIEW + 1] end
    end
    -- pv._pad: the layout tool's working copy; else the theme's own.
    local pad = pv._pad or BNB.GetSearchPanelPad(themeID, pv._size)
    local y = PlaceRows(pv, pv._rows, list, -pad.top, pad, function(i)
        pv._rows[i] = BuildRow(pv)
        return pv._rows[i]
    end)
    for i, row in ipairs(pv._rows) do
        -- pv._hl: the layout tool's working colour; else the theme's.
        if pv._hl then row.selTex:SetColorTexture(unpack(pv._hl))
        else row.selTex:SetColorTexture(BNB.GetSearchHighlight(themeID)) end
        row.selTex:SetShown(i == 1)
        for _, badge in pairs(row.badges) do badge:EnableMouse(false) end
    end
    if not pv._hint then
        pv._hint = pv:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        pv._hint:SetJustifyH("CENTER")
        pv._hint:SetWordWrap(false)
    end
    pv._hint:SetText(L["ORACLE_HINT"])
    pv._hint:ClearAllPoints()
    pv._hint:SetPoint("TOPLEFT", pv, "TOPLEFT", pad.left + 6, y - 2)
    pv._hint:SetPoint("TOPRIGHT", pv, "TOPRIGHT", -pad.right - 6, y - 2)
    pv:SetHeight(-y + HINT_H + pad.bottom)
end

-- Redraws the NPC portraits of the shown results, after
-- Features/TargetNote.lua has looked up a display ID.
function Oracle.RefreshPortraits()
    if not (bar and bar:IsShown() and BNB.SetNpcNotePortrait) then return end
    for i, row in ipairs(rows) do
        local r = results[i]
        if r and row:IsShown() then BNB.SetNpcNotePortrait(row.icon, r.note) end
    end
end

function Oracle.Close()
    if bar then bar:Hide() end
end

-- Right-click on the bar: its settings page (the bar closes first).
function Oracle.OpenSettings()
    Oracle.Close()
    if BNB.OpenSettingsPage then BNB.OpenSettingsPage("modules", "oracle") end
end

-- The settings page's Move / preview (see MOVE / PREVIEW above). Works
-- with the module switched off too, so it can be set up first.
function Oracle.StartPreview()
    if not bar then Build() else SyncTheme() end
    if bar:IsShown() then bar:Hide() end   -- a live search gives way
    if not moveTip then BuildMoveTip() end
    previewing = true
    SetPreviewLayer(true)
    eb:SetText("")
    eb:ClearFocus()
    eb:EnableMouse(false)
    placeholder:Show()
    ApplyPosition()
    DrawPreviewRows()
    moveTip:Show()
    bar:Show()
    bar:Raise()
    BNB.PlaceSearchPanel(panel, bar, drawnTheme)
end

function Oracle.EndPreview()
    if previewing and bar then bar:Hide() end
end

function Oracle.IsPreviewing()
    return previewing
end

-- Redraws the preview after a theme or result-count change.
function Oracle.RefreshPreview()
    if not previewing then return end
    SyncTheme()
    DrawPreviewRows()
    BNB.PlaceSearchPanel(panel, bar, drawnTheme)
end

-- Settings page Reset: back to the default spot.
function Oracle.ResetPosition()
    if BigNoteBoxDB then BigNoteBoxDB.oracleX, BigNoteBoxDB.oracleY = nil, nil end
    if bar then ApplyPosition() end
end

function Oracle.IsOpen()
    return bar ~= nil and bar:IsShown()
end

function Oracle.Toggle()
    if Oracle.IsOpen() then Oracle.Close() else Oracle.Open() end
end

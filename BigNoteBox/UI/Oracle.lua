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
-- each; tip is the L key of its hover text. Art by Dukul, 32x32 TGA in
-- Assets\Search\. More kinds are added here.
local BADGES = {
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
}

local bar, panel, eb, placeholder, hintFS, emptyFS
local helpFrame, helpLines   -- the "?" listing, built once (BuildHelp)
local rows    = {}
local results = {}
local sel     = 0
local openT   = nil   -- GetTime() of the frame the bar opened in
local drawnTheme      -- the oracleTheme value the bar was last drawn with

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
-- Enter opens the Trash window scrolled to that note, which flashes;
-- Shift+Enter restores it (a chat line says so, the bar has closed by then).
-- Ctrl/Alt do nothing extra.
local function OpenTrashResult(id)
    if IsShiftKeyDown() then
        if not BNB.RestoreNote then return false end
        local tn = BigNoteBoxNotesDB and BigNoteBoxNotesDB.trash and BigNoteBoxNotesDB.trash[id]
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

-- How many badges a note shows.
local function BadgeCount(note)
    local n = 0
    for _, def in ipairs(BADGES) do
        if def.show(note) then n = n + 1 end
    end
    return n
end

-- textRight: x offset from the row's right edge where the scope label and
-- snippet end. The same for every row (Layout sizes it to the row with the
-- most badges), so the text lines up and does not shift with the badges.
local function RowText(row, r, textRight)
    local note = r.note
    local icon = BNB.NpcNoteIcon and BNB.NpcNoteIcon(note) or note.icon
    row.icon:SetTexture((icon and icon ~= "") and icon or DEFAULT_ICON)
    -- NPC notes: the NPC's face, as in the note list (ALL-46). Until its
    -- display ID is looked up the note icon stays; Oracle.RefreshPortraits
    -- redraws when the lookup finishes.
    if BNB.SetNpcNotePortrait then BNB.SetNpcNotePortrait(row.icon, note) end
    local title = (note.title and note.title ~= "") and note.title or L["UNTITLED"]
    row.title:SetText(title)
    local tc = note.titleColor
    if tc then row.title:SetTextColor(tc.r, tc.g, tc.b) else row.title:SetTextColor(1, 1, 1) end
    row.snippet:SetText(r.snippet or "")
    row.scope:SetText(ScopeLabel(note))

    -- Badges from the right edge, inside the column right of textRight.
    local x = -8
    for b, def in ipairs(BADGES) do
        local badge = row.badges[b]
        if def.show(note) then
            if not badge then
                -- A small frame, not a bare texture, so it can show what it
                -- means on hover. It takes the mouse from the row, so it
                -- passes hover (selection) and clicks (open) on to it.
                badge = CreateFrame("Frame", nil, row)
                badge:SetSize(BADGE_SIZE, BADGE_SIZE)
                badge:EnableMouse(true)
                local tex = badge:CreateTexture(nil, "ARTWORK")
                tex:SetAllPoints()
                tex:SetTexture(BADGE_ART .. def.file)
                badge:SetScript("OnEnter", function(self)
                    local onEnter = row:GetScript("OnEnter")
                    if onEnter then onEnter(row) end
                    GameTooltip:SetOwner(self, "ANCHOR_TOP")
                    GameTooltip:SetText(L[def.tip], 1, 1, 1)
                    GameTooltip:Show()
                end)
                badge:SetScript("OnLeave", function() GameTooltip:Hide() end)
                badge:SetScript("OnMouseUp", function(self, button)
                    if button == "LeftButton" and self:IsMouseOver() then row:Click() end
                end)
                row.badges[b] = badge
            end
            badge:ClearAllPoints()
            badge:SetPoint("RIGHT", row, "RIGHT", x, 0)
            badge:Show()
            x = x - BADGE_SIZE - BADGE_GAP
        elseif badge then
            badge:Hide()
        end
    end
    row.scope:ClearAllPoints()
    row.scope:SetPoint("TOPRIGHT", row, "TOPRIGHT", textRight, -4)
    row.snippet:SetPoint("RIGHT", row, "RIGHT", textRight, 0)
end

-- A result row on parent. onEnter / onClick: nil for the layout tool's
-- preview rows, which take no mouse at all.
local function BuildRow(parent, onEnter, onClick)
    local row = CreateFrame("Button", nil, parent)
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

    if onEnter then row:SetScript("OnEnter", onEnter) end
    if onClick then row:SetScript("OnClick", onClick) else row:EnableMouse(false) end
    return row
end

-- The real list's row i.
local function MainRow(i)
    rows[i] = BuildRow(panel, function() SetSelection(i) end, function() OpenResult(i) end)
    return rows[i]
end

-- Lays out list (results) on the rows of parent from y down, building rows
-- with build(i) as needed, one badge column for all. Returns the new y.
local function PlaceRows(parent, rowList, list, y, padX, build)
    local n = #list
    -- Badge column as wide as the row with the most badges, plus a little
    -- air between badges and text.
    local most = 0
    for i = 1, n do most = math.max(most, BadgeCount(list[i].note)) end
    local textRight = -8
    if most > 0 then textRight = -8 - most * (BADGE_SIZE + BADGE_GAP) - 4 end
    for i = 1, math.max(MAX_ROWS, #rowList) do
        local row = rowList[i]
        if i <= n then
            row = row or build(i)
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", parent, "TOPLEFT", padX, y)
            row:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -padX, y)
            RowText(row, list[i], textRight)
            row:Show()
            y = y - ROW_H - ROW_GAP
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
    local size = panel._size
    local padX = math.floor(size.border * 0.6 + 0.5)
    local padY = math.floor((size.borderY or size.border) * 0.6 + 0.5)
    local y = -padY

    if showingHelp then
        for _, row in ipairs(rows) do row:Hide() end
        emptyFS:Hide()
        if not helpFrame then BuildHelp() end
        helpFrame:ClearAllPoints()
        helpFrame:SetPoint("TOPLEFT", panel, "TOPLEFT", padX + 6, y - 6)
        helpFrame:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -padX - 6, y - 6)
        helpFrame:SetHeight(helpLines * HELP_LINE_H)
        helpFrame:Show()
        hintFS:Hide()
        panel:SetHeight(padY - y + helpLines * HELP_LINE_H + 12)
        return
    end
    if helpFrame then helpFrame:Hide() end
    hintFS:Show()

    local n = #results
    y = PlaceRows(panel, rows, results, y, padX, MainRow)
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

local function Refresh()
    local text = eb:GetText() or ""
    if text == "" then placeholder:Show() else placeholder:Hide() end

    local parsed = BNB.OracleSearch.ParseQuery(text, { prefixes = PrefixMap(), dateWords = DateWordMap() })
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
        weights = BigNoteBoxDB and BigNoteBoxDB.oracleWeights,
        zone = ZoneCtx(), target = TargetCtx(),
    }
    results = BNB.OracleSearch.SearchParsed(notes, parsed, { max = MAX_ROWS, ctx = ctx })
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
    bar:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    drawnTheme = BigNoteBoxDB and BigNoteBoxDB.oracleTheme
    BNB.ApplySearchChrome(bar, drawnTheme)
    -- A click on the bar's frame (not the text) puts the cursor back.
    -- A click raises the bar (SetToplevel), lifting the results with it:
    -- put them back under it after the raise.
    bar:SetScript("OnMouseDown", function()
        eb:SetFocus()
        C_Timer.After(0, function() BNB.PlaceSearchPanel(panel, bar, drawnTheme) end)
    end)

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
    BNB.PlaceSearchPanel(panel, bar, drawnTheme)   -- the theme's panelPos
    panel:EnableMouse(true)
    panel:SetScript("OnMouseDown", function()
        C_Timer.After(0, function() BNB.PlaceSearchPanel(panel, bar, drawnTheme) end)
    end)
    panel._size = BNB.ApplySearchChrome(panel, drawnTheme, nil, nil, { panel = true })
        or { border = 24, borderY = 24 }
    -- Esc still closes it if the box has lost focus to another window.
    tinsert(UISpecialFrames, "BigNoteBoxOracleFrame")

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
-- Redraws the bar, the results panel and the row highlight when the theme
-- setting changed since the bar was last drawn, so a new theme shows on
-- the next open without a reload.
local function SyncTheme()
    local want = BigNoteBoxDB and BigNoteBoxDB.oracleTheme
    if want == drawnTheme then return end
    drawnTheme = want
    BNB.ApplySearchChrome(bar, want)
    panel._size = BNB.ApplySearchChrome(panel, want, nil, nil, { panel = true }) or panel._size
    BNB.PlaceSearchPanel(panel, bar, want)
    for _, row in ipairs(rows) do row.selTex:SetColorTexture(BNB.GetSearchHighlight(want)) end
end

function Oracle.Open(text)
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

-- Fake results for the search bar layout tool (UI/SearchChrome.lua), drawn
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
-- themed (pv._size set by ApplySearchChrome), and sizes it. Row 1 shows
-- selected, in the theme's highlight colour. count: how many rows (1 to
-- MAX_ROWS, the fake notes repeat); left out = all of them.
function Oracle.DrawPreview(pv, themeID, count)
    pv._rows = pv._rows or {}
    local list = PREVIEW
    if count then
        list = {}
        for i = 1, math.max(1, math.min(MAX_ROWS, count)) do list[i] = PREVIEW[(i - 1) % #PREVIEW + 1] end
    end
    local size = pv._size or { border = 24, borderY = 24 }
    local padX = math.floor(size.border * 0.6 + 0.5)
    local padY = math.floor((size.borderY or size.border) * 0.6 + 0.5)
    local y = PlaceRows(pv, pv._rows, list, -padY, padX, function(i)
        pv._rows[i] = BuildRow(pv)
        return pv._rows[i]
    end)
    for i, row in ipairs(pv._rows) do
        row.selTex:SetColorTexture(BNB.GetSearchHighlight(themeID))
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
    pv._hint:SetPoint("TOPLEFT", pv, "TOPLEFT", padX + 6, y - 2)
    pv._hint:SetPoint("TOPRIGHT", pv, "TOPRIGHT", -padX - 6, y - 2)
    pv:SetHeight(-y + HINT_H + padY)
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

function Oracle.IsOpen()
    return bar ~= nil and bar:IsShown()
end

function Oracle.Toggle()
    if Oracle.IsOpen() then Oracle.Close() else Oracle.Open() end
end

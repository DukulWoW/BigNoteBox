--------------------------------------------------------------------------------
-- TextShortcuts.lua -- text shortcuts (ALL-559 stage 4)
--
-- Type a shortcut and then a space, Enter or . , ! ? ; : ) " and it turns into its
-- text: "brb " -> "be right back ". One Undo brings back what was typed
-- (the main editor and Focus mode; a sticky's inline edit has no undo).
-- Part of the Spelling module (Dukul, 2026-10-25): works while Spelling is on
-- and "Expand my text shortcuts" (spellShortcuts, DEFAULTS true) is ticked.
--
-- Rules (Dukul's picks, 2026-10-25):
--   * Matched as a whole word, any a-z case. Typed in lower case = the text
--     as written; a capital first letter (Brb, BRB) = the text with a
--     capital first letter.
--   * The text may hold markup ({b}...{/b}) and note tokens: they go in as if
--     typed. A normal note gets every token's value at once, a rich note gets
--     snapshot tokens ({{date}}, {{zone}}) filled and keeps live ones.
--   * Never inside {...} markup being typed, links, lines that start with "/",
--     after \ or a few other characters (see SKIP_BEFORE), and never for a
--     paste (only when the text grew by the one character typed).
--   * Shortcut names are known words for the spellchecker.
--
-- Kept with the notes, not the settings (a settings reset leaves them):
--   BigNoteBoxNotesDB.spellShortcuts[name:lower()] = { name = "brb", text = "be right back" }
-- In the JSON backup as "spellShortcuts", a list of { name, text }.
-- Settings: Settings > Modules > Spelling, "Text shortcuts" (UI/Config/Spelling.lua).
--------------------------------------------------------------------------------
local BNB = BigNoteBox
local L   = BNB.L

local TS = {}
BNB.TextShortcuts = TS

TS.MAX_NAME = 20      -- bytes
TS.MAX_TEXT = 255     -- bytes

-- The typed character that turns a shortcut into its text
local TRIGGER = { [" "] = true, ["\n"] = true, ["."] = true, [","] = true, ["!"] = true,
                  ["?"] = true, [";"] = true, [":"] = true, [")"] = true, ["\""] = true }
-- A word right after one of these is not a shortcut: markup, escapes,
-- paths, addresses, names joined by - or _
local SKIP_BEFORE = { ["{"] = true, ["|"] = true, ["\\"] = true, ["/"] = true, ["@"] = true,
                      ["_"] = true, ["-"] = true, ["."] = true, [":"] = true }

-- a-z only (WoW's lower() breaks UTF-8 lead bytes, CLAUDE.md)
local function LowerAscii(w) return (w:gsub("[A-Z]", string.lower)) end

local function Store(create)
    local ndb = BNB.NotesDB and BNB.NotesDB()
    if not ndb then return nil end
    if create and type(ndb.spellShortcuts) ~= "table" then ndb.spellShortcuts = {} end
    return type(ndb.spellShortcuts) == "table" and ndb.spellShortcuts or nil
end

-- A name as it may be stored: one word of letters, digits and ', no
-- longer than MAX_NAME -> the name or nil
function TS.CleanName(n)
    if type(n) ~= "string" then return nil end
    n = n:match("^%s*(.-)%s*$")
    if n == "" or #n > TS.MAX_NAME then return nil end
    if not n:find("^[%w\128-\255][%w\128-\255']*$") then return nil end
    return n
end

-- The text as it may be stored: one line, no | (escape codes), trimmed
function TS.CleanText(t)
    if type(t) ~= "string" then return nil end
    t = t:gsub("[\r\n]+", " "):match("^%s*(.-)%s*$")
    if t == "" or #t > TS.MAX_TEXT or t:find("|", 1, true) then return nil end
    return t
end

local function Changed()
    if BNB.Spell then BNB.Spell.Reset() end   -- the names are known words
    BNB.SendMessage("SpellShortcutsChanged")
end

-- Every shortcut, sorted by name -> { { name, text }, ... }
function TS.List()
    local out = {}
    for _, r in pairs(Store() or {}) do
        if type(r) == "table" and type(r.name) == "string" and type(r.text) == "string" then
            out[#out + 1] = { name = r.name, text = r.text }
        end
    end
    table.sort(out, function(a, b)
        local la, lb = LowerAscii(a.name), LowerAscii(b.name)
        if la ~= lb then return la < lb end
        return a.name < b.name
    end)
    return out
end

-- The record for a name (any case) or nil
function TS.Get(name)
    local s = Store()
    local r = s and type(name) == "string" and s[LowerAscii(name)]
    if type(r) == "table" and type(r.text) == "string" then return r end
end

-- The names, lower-case, as a set (the spellchecker's known words)
function TS.Names()
    local set = {}
    for k, r in pairs(Store() or {}) do
        if type(r) == "table" then set[k] = true end
    end
    return set
end

-- Add or change one. oldName = the shortcut being edited (nil = a new one).
-- -> true, or nil + the reason to print
function TS.Set(name, text, oldName)
    local n, t = TS.CleanName(name), TS.CleanText(text)
    if not n then return nil, string.format(L["SHORTCUT_BAD_NAME_FMT"], TS.MAX_NAME) end
    if not t then return nil, string.format(L["SHORTCUT_BAD_TEXT_FMT"], TS.MAX_TEXT) end
    local key = LowerAscii(n)
    local oldKey = oldName and LowerAscii(oldName) or nil
    local s = Store(true)
    if key ~= oldKey and s[key] then
        return nil, string.format(L["SHORTCUT_TAKEN_FMT"], n)
    end
    if oldKey and oldKey ~= key then s[oldKey] = nil end
    s[key] = { name = n, text = t }
    Changed()
    -- A real word as a shortcut turns into its text every time it is typed
    if key ~= oldKey and BNB.Spell and BNB.Spell.InDictionary and BNB.Spell.InDictionary(n) then
        BNB:Print(string.format(L["SHORTCUT_IS_WORD_FMT"], n))
    end
    return true
end

function TS.Delete(name)
    local s = Store()
    if not (s and type(name) == "string") then return end
    s[LowerAscii(name)] = nil
    Changed()
end

-- Every shortcut gone (Danger Zone, ALL-578) -> the number deleted
function TS.DeleteAll()
    local n = #TS.List()
    local ndb = BNB.NotesDB and BNB.NotesDB()
    if ndb then ndb.spellShortcuts = nil end
    Changed()
    return n
end

-- The JSON full backup (Features/NoteExport.lua)
function TS.BackupList() return TS.List() end
-- -> the number added; names already here are kept as they are
function TS.ImportList(list)
    if type(list) ~= "table" then return 0 end
    local n = 0
    for _, r in ipairs(list) do
        if type(r) == "table" then
            local name, text = TS.CleanName(r.name), TS.CleanText(r.text)
            if name and text and not TS.Get(name) then
                Store(true)[LowerAscii(name)] = { name = name, text = text }
                n = n + 1
            end
        end
    end
    if n > 0 then Changed() end
    return n
end

function TS.Enabled()
    if not (BNB.SpellEnabled and BNB.SpellEnabled()) then return false end
    local v = BigNoteBoxDB and BigNoteBoxDB.spellShortcuts
    if v == nil then v = BNB.DEFAULTS.spellShortcuts end
    return v ~= false
end

--------------------------------------------------------------------------------
-- Expanding as typed
--------------------------------------------------------------------------------

-- The text a shortcut gives in this note: case from the typed word, tokens
-- as if typed (Features/Tokens.lua)
local function Expansion(typed, rec, noteID)
    local t = rec.text
    if typed:find("^[A-Z]") then t = BNB.UpperFirst(t) end
    local Tk = BNB.Tokens
    if Tk and t:find("{{", 1, true) then
        if Tk.NotePlain(noteID) then t = Tk.FreezeText(t) or t
        else t = Tk.Snapshot(t) or t end
    end
    return t
end

-- true when the word at first..last of text is prose a shortcut may replace
local function FreeWord(text, first, last)
    local prev = first > 1 and text:sub(first - 1, first - 1) or ""
    if SKIP_BEFORE[prev] then return false end
    -- Its line up to the word: a "/" line, an open { or a link around it
    local ls = first
    while ls > 1 and text:sub(ls - 1, ls - 1) ~= "\n" do ls = ls - 1 end
    local before = text:sub(ls, first - 1)
    if before:find("^[ \t]*/") then return false end
    local open = before:match(".*()%{")
    if open and not before:find("}", open, true) then return false end
    local lk = before:match(".*()|H")
    if lk and not before:find("|h.-|h", lk) then return false end
    return true
end

-- ed: the spellchecker's editor record (Features/Spellcheck.lua AttachEditor):
-- ed.kind (main / focus / sticky), ed.noteID(), ed.active()
function TS.Wire(eb, ed)
    if not eb or eb._bnbShortcuts then return end
    eb._bnbShortcuts = true
    local lastLen
    hooksecurefunc(eb, "SetText", function(self) lastLen = #(self:GetText() or "") end)
    eb:HookScript("OnTextChanged", function(self, userInput)
        local text = self:GetText() or ""
        local grewByOne = lastLen ~= nil and #text == lastLen + 1
        lastLen = #text
        if not userInput or not grewByOne or self._showingPlaceholder or BNB._undoActive then return end
        if not TS.Enabled() then return end
        if ed.active and not ed.active() then return end
        local cur = self:GetCursorPosition() or 0
        if cur < 2 or not TRIGGER[text:sub(cur, cur)] then return end
        local first = text:sub(1, cur - 1):find("[%w\128-\255][%w\128-\255']*$")
        if not first then return end
        local typed = text:sub(first, cur - 1)
        if #typed > TS.MAX_NAME then return end
        local rec = TS.Get(typed)
        if not rec or not FreeWord(text, first, cur - 1) then return end
        local id = ed.noteID and ed.noteID()
        if not id or tostring(id):find("^sys%-") then return end

        local exp = Expansion(typed, rec, id)
        local newText = text:sub(1, first - 1) .. exp .. text:sub(cur)
        local newCur  = first - 1 + #exp + 1
        local undoID = ed.kind ~= "sticky" and id or nil
        -- What was typed first, so one Undo brings it back
        if undoID then BNB.UndoPush(undoID, text, cur) end
        BNB._undoActive = true
        self:SetText(newText)
        BNB._undoActive = false
        self:SetCursorPosition(newCur)
        if undoID then
            BNB.UndoPush(undoID, newText, newCur)
            if BNB._refreshUndoButtons then BNB._refreshUndoButtons() end
        end
    end)
end

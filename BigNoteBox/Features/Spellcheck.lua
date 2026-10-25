--------------------------------------------------------------------------------
-- Spellcheck.lua -- the spellchecker (ALL-559 stage 1)
--
-- Marks words that are not in the dictionary with a red line under them in
-- the note editors' bodies. The text is never touched: the lines are drawn over
-- the box by UI/TextLines.lua. No autocorrect, ever (Dukul, 2026-10-25:
-- notes are full of names, bosses and shorthand).
--
-- The word lists are the load-on-demand addon BigNoteBox_Spell (English US
-- and UK, from the English Speller Database, made by
-- _work/tools/dict-build.py). It is loaded the first time a note is checked,
-- never at login. Missing or disabled = no marks, no error; the Spelling
-- page says why.
--
-- Settings (Settings > Modules > Spelling, UI/Config/Spelling.lua):
--   spellEnabled   the module (on for English game clients)
--   spellLang      "enUS" / "enGB"
--   spellMode      "type" = marks while typing, "click" = only after Check
--                  spelling (the toolbar button). A note over LONG_BYTES is
--                  checked on click whatever the setting (Dukul's idea, 2026-10-25)
--   spellSkipCaps  a capitalized word inside a sentence is taken as a name
--   spellSkipUpper words in capitals are not checked (off: LFG, ICC are in
--                  the game word list, Dukul 2026-10-25)
--   spellSkipDigits words with a number are not checked; off = their letters
--                  are (three or more), 1st / 2nd / 3rd / 4th always pass
--   spellRepeats   the same word twice in a row ("the the") is marked
--
-- Stage 2: right-click on a marked word = up to six suggestions (one undo
-- step through BNB.ReplaceInEditor), Add to dictionary, Ignore (until the
-- reload), at the top of the body's Insert Info menu (Features/InsertInfo.lua).
-- Since 2026-10-25 the suggestions sit above Insert Info and the actions
-- (Add "word" to dictionary, Ignore, Correct spelling...) between the token
-- groups and New token; the word under the pointer comes from the drawn
-- lines (TextLines ctl.RangeAtPointer). Correct spelling = UI/SpellCorrect.lua.
-- Repeated words ("the the") are marked too and can be removed.
-- Your words: BigNoteBoxNotesDB.spellWords, listed on the Spelling page, in
-- the JSON full backup. The Check spelling key: BIGNOTEBOXSPELLCHECK (ALL-567),
-- the Correct spelling key: BIGNOTEBOXSPELLCORRECT (ALL-568).
-- Stage 3: the same in Focus mode (marks, right-click, the toolbar's spell
-- buttons, the key, Correct spelling over Focus mode) and in a sticky's
-- inline edit (marks only while editing; suggestions, Add and Ignore on top
-- of the sticky's own menu, no Correct spelling window). One checker per box
-- (SP.AttachEditor, kind main / focus / sticky); SP.ActiveEditor() = Focus
-- mode while it is open, else the main editor.
-- Stage 4: text shortcuts (brb -> be right back) in the same boxes,
-- Features/TextShortcuts.lua, wired from SP.AttachEditor; their names are
-- known words (Extra).
--
-- Not checked: game links, textures, color codes, every complete {...}
-- markup and {{token}}, web and mail addresses, lines that start with "/"
-- (slash commands, /way), words with a digit in them, words in capitals
-- (LFG, DPS), mixed case (BigNoteBox), one-letter words, anything not in a
-- Latin script (Chinese, Korean, Russian words are skipped, not marked).
--------------------------------------------------------------------------------
local BNB = BigNoteBox
local L   = BNB.L

local SP = {}
BNB.Spell = SP

local ADDON      = "BigNoteBox_Spell"
local LONG_BYTES = 20000      -- longer notes: checked on click only
local MEMO_MAX   = 20000      -- remembered word answers before the memo is reset

local _data    = {}           -- lang -> what BigNoteBox_Spell handed over
local _tried   = false        -- LoadAddOn is tried once per session
local _failure = nil          -- why it could not load
local _memo, _memoN = {}, 0   -- word -> true / false, for the language in use
local _extra   = nil          -- game words of this player: classes, characters, tags
local _own     = nil          -- the player's own words, lower-case (BigNoteBoxNotesDB.spellWords)
local _ignored = {}           -- Ignore in the right-click menu: until the next reload
local _ignoredRep = {}        -- the same for a repeated word ("the the")
local _editors = {}           -- edit box -> its checker (SP.AttachEditor, below)
local _main                   -- the main editor's checker

-- Called by BigNoteBox_Spell's files when they run
function BNB.ReceiveSpellData(lang, data)
    if type(lang) == "string" and type(data) == "table" then _data[lang] = data end
end

function BNB.SpellEnabled()
    return BigNoteBoxDB ~= nil and BigNoteBoxDB.spellEnabled == true
end

function SP.Lang()
    return BigNoteBoxDB and BigNoteBoxDB.spellLang == "enGB" and "enGB" or "enUS"
end

-- Loads BigNoteBox_Spell once. -> true when the lists are there
function SP.EnsureLoaded()
    if _data.enUS then return true end
    if _tried then return false end
    _tried = true
    local ok, loaded, reason = pcall(C_AddOns.LoadAddOn, ADDON)
    if not ok then
        _failure = "ERROR"
    elseif not loaded then
        _failure = reason or "MISSING"
    elseif not _data.enUS then
        _failure = "ERROR"
    end
    return _data.enUS ~= nil
end

-- For the settings page: nil when loaded, else the reason
function SP.Failure() return _failure end
function SP.WordCount()
    local d = _data[SP.Lang()] or _data.enUS
    return d and d.count or 0
end

-- Why it cannot work, in a chat line (when the player switches it on)
function SP.Announce()
    if SP.EnsureLoaded() then return end
    if _failure == "MISSING" then BNB:Print(L["SPELL_ADDON_MISSING"])
    elseif _failure == "DISABLED" then BNB:Print(L["SPELL_ADDON_DISABLED"])
    else BNB:Print(string.format(L["SPELL_ADDON_FAILED_FMT"], tostring(_failure))) end
end

--------------------------------------------------------------------------------
-- Looking a word up
--------------------------------------------------------------------------------

-- A bucket is every word of one byte length and first byte, joined: a hit
-- counts only at a multiple of the length (see dict-build.py)
local function InBuckets(bk, w)
    if not bk then return false end
    local n = #w
    local blk = bk[n * 256 + w:byte(1)]
    if not blk then return false end
    local p = 1
    while true do
        p = blk:find(w, p, true)
        if not p then return false end
        if (p - 1) % n == 0 then return true end
        p = p + 1
    end
end

-- a-z only: WoW's lower() also changes bytes 128-255 and would break a
-- UTF-8 letter (CLAUDE.md, ALL-507)
local function LowerAscii(w) return (w:gsub("[A-Z]", string.lower)) end

-- Words from this player's game: class names, known characters, tags
local function AddWords(set, text)
    if type(text) ~= "string" then return end
    for w in text:gmatch("[A-Za-z\128-\255']+") do set[LowerAscii(w)] = true end
end
local function Extra()
    if _extra then return _extra end
    local set = {}
    for _, t in ipairs({ LOCALIZED_CLASS_NAMES_MALE, LOCALIZED_CLASS_NAMES_FEMALE }) do
        if type(t) == "table" then for _, name in pairs(t) do AddWords(set, name) end end
    end
    local kc = BigNoteBoxDB and BigNoteBoxDB.knownChars
    if type(kc) == "table" then
        for key in pairs(kc) do AddWords(set, (tostring(key):match("^([^-]+)"))) end
    end
    if BNB.GetAllTags then
        local ok, tags = pcall(BNB.GetAllTags)
        if ok and type(tags) == "table" then
            for _, t in ipairs(tags) do AddWords(set, t.tag) end
        end
    end
    -- Text shortcuts (stage 4): brb is a word once it is a shortcut
    if BNB.TextShortcuts then
        for k in pairs(BNB.TextShortcuts.Names()) do set[k] = true end
    end
    _extra = set
    return set
end

--------------------------------------------------------------------------------
-- Your words (stage 2): Add to dictionary, Settings > Modules > Spelling.
-- Kept with the notes, not the settings, so a settings reset leaves them,
-- and carried by the JSON full backup as `spellWords` (a list). Stored as
-- typed, { [word] = true }; matched without regard to a-z case.
--------------------------------------------------------------------------------
local MAX_WORD = 60           -- bytes; a longer "word" is not one

local function OwnStore(create)
    local ndb = BNB.NotesDB and BNB.NotesDB()
    if not ndb then return nil end
    if create and type(ndb.spellWords) ~= "table" then ndb.spellWords = {} end
    return type(ndb.spellWords) == "table" and ndb.spellWords or nil
end

-- A word as it may be stored: trimmed, one word, no escape codes
local function CleanWord(w)
    if type(w) ~= "string" then return nil end
    w = w:gsub("\226\128\153", "'"):match("^%s*(.-)%s*$")
    if w == "" or #w > MAX_WORD or w:find("[%s|{}]") then return nil end
    return w
end

function SP.OwnSet()
    if _own then return _own end
    local set = {}
    for w in pairs(OwnStore() or {}) do
        if type(w) == "string" then set[LowerAscii(w)] = true end
    end
    _own = set
    return set
end

-- Your words, sorted (a-z case ignored)
function SP.WordList()
    local out = {}
    for w in pairs(OwnStore() or {}) do
        if type(w) == "string" then out[#out + 1] = w end
    end
    table.sort(out, function(a, b)
        local la, lb = LowerAscii(a), LowerAscii(b)
        if la ~= lb then return la < lb end
        return a < b
    end)
    return out
end

local function OwnChanged()
    _own = nil
    SP.Reset()
    BNB.SendMessage("SpellWordsChanged")
end

-- -> true when the word was added (false = already there or not a word)
function SP.AddWord(w, quiet)
    w = CleanWord(w)
    if not w then return false end
    if SP.OwnSet()[LowerAscii(w)] then return false end
    OwnStore(true)[w] = true
    OwnChanged()
    if not quiet then BNB:Print(string.format(L["SPELL_ADDED_FMT"], w)) end
    return true
end

-- Ignore (the right-click menu): this word is not marked until the next reload
function SP.Ignore(w)
    w = CleanWord(w)
    if not w then return end
    _ignored[LowerAscii(w)] = true
    SP.Reset()
end

-- Ignore on a repeated word: that word twice in a row is fine until the next reload
function SP.IgnoreRepeat(w)
    if type(w) ~= "string" or w == "" then return end
    _ignoredRep[LowerAscii(w)] = true
    SP.Reset()
end

-- One word out of your list (the X on the Spelling page)
function SP.RemoveWord(w)
    local store = OwnStore()
    if not (store and type(w) == "string") then return end
    local lw = LowerAscii(w)
    for k in pairs(store) do
        if type(k) == "string" and LowerAscii(k) == lw then store[k] = nil end
    end
    OwnChanged()
end

-- A word in your list changed (clicked on the Spelling page). -> true when
-- done; false when new is not a word or is in the list already
function SP.RenameWord(old, new)
    new = CleanWord(new)
    if not (new and type(old) == "string") then return false end
    if new == old then return true end
    local lo, ln = LowerAscii(old), LowerAscii(new)
    if ln ~= lo and SP.OwnSet()[ln] then return false end
    local store = OwnStore(true)
    for k in pairs(store) do
        if type(k) == "string" and LowerAscii(k) == lo then store[k] = nil end
    end
    store[new] = true
    OwnChanged()
    return true
end

-- The JSON full backup (Features/NoteExport.lua)
function SP.BackupList() return SP.WordList() end
-- -> the number of words added; words already here are left alone
function SP.ImportList(list)
    if type(list) ~= "table" then return 0 end
    local n = 0
    local store
    for _, w in ipairs(list) do
        w = CleanWord(w)
        if w and not SP.OwnSet()[LowerAscii(w)] then
            store = store or OwnStore(true)
            store[w] = true
            _own[LowerAscii(w)] = true
            n = n + 1
        end
    end
    if n > 0 then OwnChanged() end
    return n
end

-- The word as it is, in the language in use
local function Known(w)
    local lang = SP.Lang()
    local d = _data[lang]
    if d and d.base then
        if InBuckets(d.add, w) then return true end
        if InBuckets(d.drop, w) then return false end
        d = _data[d.base]
    end
    d = d or _data.enUS
    if d and InBuckets(d.words, w) then return true end
    return _data.wow ~= nil and InBuckets(_data.wow.words, w)
end

-- In the word lists (any a-z case), leaving out the player's own words and
-- game words: a text shortcut that is a real word gets a warning (stage 4)
function SP.InDictionary(w)
    if type(w) ~= "string" or not SP.EnsureLoaded() then return false end
    return Known(w) or Known(LowerAscii(w))
end

-- w: the word with ' for a typographic apostrophe. "The" at a sentence's
-- start is "the"; "PARIS" may be "Paris"; "dog's" is "dog"
local function CheckWord(w)
    local c = _memo[w]
    if c ~= nil then return c end
    local ok = Known(w)
    if not ok then
        local lw = LowerAscii(w)
        if lw ~= w then
            ok = Known(lw)
            if not ok and not w:find("[a-z]") then ok = Known(w:sub(1, 1) .. lw:sub(2)) end
        end
        if not ok and (Extra()[lw] or SP.OwnSet()[lw] or _ignored[lw]) then ok = true end
        if not ok then
            local stem = w:match("^(.+)'[sS]$") or w:match("^(.+[sS])'$")
            if stem and #stem > 1 then ok = CheckWord(stem) end
        end
    end
    if _memoN >= MEMO_MAX then _memo, _memoN = {}, 0 end
    _memo[w] = ok
    _memoN = _memoN + 1
    return ok
end

-- Settings, the language or the player's words changed
function SP.Reset()
    _memo, _memoN, _extra = {}, 0, nil
    for _, ed in pairs(_editors) do
        -- Click mode: the marks of the last check, asked again (Add / Ignore)
        if ed.clickText then ed.clickRanges = SP.Mistakes(ed.clickText) end
        ed.Redraw()
    end
end

--------------------------------------------------------------------------------
-- Finding the words
--------------------------------------------------------------------------------

local function Blank(m) return string.rep(" ", #m) end

-- The text with everything that is not prose turned into spaces, byte for
-- byte, so every position still points into the real text
local function Masked(text)
    local t = text
    t = t:gsub("|H.-|h.-|h", Blank)                 -- game and note links
    t = t:gsub("|T.-|t", Blank)                     -- textures
    t = t:gsub("|A.-|a", Blank)                     -- atlases
    t = t:gsub("|c%x%x%x%x%x%x%x%x", Blank)         -- colors
    t = t:gsub("|cn[%w_]+:", Blank)
    t = t:gsub("|r", Blank)
    t = t:gsub("||", Blank)
    t = t:gsub("{[^{}\n]*}", Blank)                 -- complete markup only (S0: an open { swallowed the note)
    t = t:gsub("%a[%w+.%-]*://[^%s]*", Blank)       -- web addresses
    t = t:gsub("www%.[^%s]+", Blank)
    t = t:gsub("[%w._%%+%-]+@[%w.%-]+", Blank)      -- mail addresses
    -- Lines that start with "/": slash commands, /way lines
    t = ("\n" .. t):gsub("(\n)([ \t]*/[^\n]*)", function(nl, line) return nl .. Blank(line) end):sub(2)
    return t
end

local byte = string.byte

-- An upper-case first letter: A-Z, or a Latin-1 capital (U+00C0-U+00DE)
local function UpperFirst(w)
    local b = byte(w, 1)
    if b >= 65 and b <= 90 then return true end
    local b2 = byte(w, 2)
    return b == 195 and b2 ~= nil and b2 >= 128 and b2 <= 158 and b2 ~= 151
end
-- Any lower-case letter: a-z, or a Latin-1 small one (U+00DF-U+00FF)
local function HasLower(w)
    return w:find("[a-z]") ~= nil or w:find("\195[\159-\191]") ~= nil
end
-- A capital after the first letter (BigNoteBox, iPhone)
local function MixedCase(w)
    return w:sub(2):find("[A-Z]") ~= nil and HasLower(w)
end

-- Is the word at byte s the first of a sentence (or of a line)?
local function SentenceStart(t, s)
    local i = s - 1
    while i >= 1 do
        local c = t:sub(i, i)
        if c == "\n" or c == "." or c == "!" or c == "?" or c == ":" then return true end
        if not c:find("[%s\"'%(%[%-%*]") then return false end
        i = i - 1
    end
    return true
end

-- 1st, 2nd, 23rd, 4th: never marked
local function Ordinal(w)
    return w:find("^%d+[sS][tT]$") or w:find("^%d+[nN][dD]$") or w:find("^%d+[rR][dD]$")
        or w:find("^%d+[tT][hH]$")
end

-- The words that are not in the dictionary -> { { first, last, "x" }, ... }.
-- A repeated word also has rep = the byte after the word before it (the
-- space taken out with it)
function SP.Mistakes(text)
    local out = {}
    if type(text) ~= "string" or text == "" or not SP.EnsureLoaded() then return out end
    local t = Masked(text)
    local n = #t
    local db = BigNoteBoxDB or {}
    local skipCaps   = db.spellSkipCaps ~= false
    local skipUpper  = db.spellSkipUpper == true
    local skipDigits = db.spellSkipDigits ~= false
    local repeats    = db.spellRepeats ~= false
    local prevW, prevE                      -- the word before, for "the the"
    -- -> true when the word got marked
    local function Check(s, e, w)
        local lower = HasLower(w)
        local check
        if lower then check = not MixedCase(w) else check = not skipUpper end
        if check and lower and skipCaps and UpperFirst(w) and not SentenceStart(t, s) then check = false end
        if check and not CheckWord(w) then out[#out + 1] = { s, e, "x" }; return true end
        return false
    end
    local pos = 1
    while true do
        local s = t:find("[A-Za-z0-9\195-\197]", pos)
        if not s then break end
        local i, digit = s, false
        local prev = s > 1 and byte(t, s - 1) or 0
        if prev >= 48 and prev <= 57 then digit = true end
        while i <= n do
            local b = byte(t, i)
            if (b >= 65 and b <= 90) or (b >= 97 and b <= 122) or b == 39 then
                i = i + 1
            elseif b >= 48 and b <= 57 then
                digit = true; i = i + 1
            elseif b >= 195 and b <= 197 then
                local b2 = byte(t, i + 1)
                if b2 and b2 >= 128 and b2 <= 191 and not (b == 195 and (b2 == 151 or b2 == 183)) then
                    i = i + 2
                else break end
            elseif b == 226 and byte(t, i + 1) == 128 and byte(t, i + 2) == 153 then
                i = i + 3                              -- a typographic apostrophe
            else break end
        end
        if i == s then i = s + 1 end                   -- a lone lead byte
        local e = i - 1
        -- Quotes at the end are not part of the word
        while e >= s do
            if byte(t, e) == 39 then e = e - 1
            elseif e - 2 >= s and t:sub(e - 2, e) == "\226\128\153" then e = e - 3
            else break end
        end
        pos = i
        if e > s and not digit then
            local w = t:sub(s, e):gsub("\226\128\153", "'")
            local marked = Check(s, e, w)
            -- The same word right after the last, only spaces between in the
            -- real text (a link or markup between is not a repeat)
            local lw = LowerAscii(w)
            if repeats and not marked and prevW == lw and not _ignoredRep[lw]
               and text:sub(prevE + 1, s - 1):find("^[ \t]+$") then
                out[#out + 1] = { s, e, "x", rep = prevE + 1 }
            end
            prevW, prevE = lw, e
        elseif e > s then
            prevW = nil
            -- Setting off: the letters of a word with a number in it (teh2 -> teh)
            local w = t:sub(s, e)
            if not skipDigits and not Ordinal(w) then
                local p = 1
                while true do
                    local a, b = w:find("[A-Za-z\128-\255']+", p)
                    if not a then break end
                    if b - a + 1 >= 3 then Check(s + a - 1, s + b - 1, w:sub(a, b)) end
                    p = b + 1
                end
            end
        else
            prevW = nil
        end
    end
    return out
end

-- Checked only on click: the setting, or a long note
function SP.ClickOnly(text)
    return (BigNoteBoxDB and BigNoteBoxDB.spellMode == "click") or #(text or "") > LONG_BYTES
end
SP.LONG_BYTES = LONG_BYTES

function SP.Color() return 1, 0.30, 0.30 end

--------------------------------------------------------------------------------
-- Suggestions (stage 2): only on a right-click, never while typing
--
-- Every word in the lists of a similar length with the same first letter is
-- scored by an edit distance in which a neighbouring key, two swapped letters
-- and a doubled letter cost less than another letter (teh -> the, necesary ->
-- necessary). The game's own CalculateStringEditDistance (Retail and Forever;
-- ~50x the Lua one, ALL-559 stage 0) throws out the far ones first. A wrong
-- first letter is found by trying the 54 one-letter changes at the front, and
-- two words run together by splitting.
--------------------------------------------------------------------------------
local MAX_SUGGEST = 6
local CASE_COST   = 0.25      -- a name offered for a word typed in lower case
-- Two words run together score well only when one of them is one of these
local COMMON = {}
for w in ("a an the of to in on at is it as by or and for not no so up i do if all"):gmatch("%a+") do COMMON[w] = true end
local GameDistance = CalculateStringEditDistance

-- QWERTY keys next to each other
local KEY_POS = {}
do
    local rows, shift = { "qwertyuiop", "asdfghjkl", "zxcvbnm" }, { 0, 0.25, 0.75 }
    for r, row in ipairs(rows) do
        for c = 1, #row do KEY_POS[row:byte(c)] = { r, c + shift[r] } end
    end
end
local function Near(a, b)
    local p, q = KEY_POS[a], KEY_POS[b]
    if not (p and q) then return false end
    local dr, dc = p[1] - q[1], p[2] - q[2]
    return dr * dr + dc * dc <= 1.6
end

local VOWEL = { [97] = true, [101] = true, [105] = true, [111] = true, [117] = true }   -- a e i o u

-- Weighted distance from a (typed) to b, or nil when over limit
local _r0, _r1, _r2 = {}, {}, {}
local function Score(a, b, limit)
    local la, lb = #a, #b
    local prev2, prev, cur = _r0, _r1, _r2
    for j = 0, lb do prev[j] = j end
    local prevMin = 0   -- a swap reaches two rows back: stop only when two rows are over
    for i = 1, la do
        local ca = byte(a, i)
        cur[0] = i
        local rowMin = i
        for j = 1, lb do
            local cb = byte(b, j)
            local v = prev[j - 1] + ((ca == cb) and 0 or (Near(ca, cb) and 0.6 or 1))
            -- A letter too many / too few; a doubled letter costs half, a vowel less
            local del = prev[j] + ((i > 1 and byte(a, i - 1) == ca) and 0.5 or (VOWEL[ca] and 0.8 or 1))
            local ins = cur[j - 1] + ((j > 1 and byte(b, j - 1) == cb) and 0.5 or (VOWEL[cb] and 0.8 or 1))
            if del < v then v = del end
            if ins < v then v = ins end
            -- Two letters swapped
            if i > 1 and j > 1 and ca == byte(b, j - 1) and byte(a, i - 1) == cb then
                local t = prev2[j - 2] + 0.5
                if t < v then v = t end
            end
            cur[j] = v
            if v < rowMin then rowMin = v end
        end
        if rowMin > limit and prevMin > limit then return nil end
        prevMin = rowMin
        prev2, prev, cur = prev, cur, prev2
    end
    local s = prev[lb]
    return s <= limit and s or nil
end

-- The bucket tables of the language in use, and the one taken out of it (UK)
local function Sources()
    local d = _data[SP.Lang()]
    local list, drop = {}, nil
    if d and d.base then list[#list + 1] = d.add; drop = d.drop; d = _data[d.base] end
    d = d or _data.enUS
    if d then list[#list + 1] = d.words end
    if _data.wow then list[#list + 1] = _data.wow.words end
    return list, drop
end

local function CapFirst(w) return (w:gsub("^[a-z]", string.upper)) end

-- -> up to MAX_SUGGEST words, best first, in the typed word's case
function SP.Suggest(word)
    local out = {}
    if type(word) ~= "string" or not SP.EnsureLoaded() then return out end
    local w  = word:gsub("\226\128\153", "'")
    local lw = LowerAscii(w)
    local n  = #lw
    if n < 2 then return out end
    local limit = n <= 3 and 1 or 2
    local band  = math.floor(limit)
    local srcs, drop = Sources()
    local found = {}   -- lower-case -> { word, score }
    local function Take(cand, s)
        local key = LowerAscii(cand)
        if key == lw or (drop and InBuckets(drop, cand)) then return end
        local old = found[key]
        if not old or s < old[2] or (s == old[2] and cand < old[1]) then found[key] = { cand, s } end
    end
    -- Same first letter: every word in the band, lower-case and capitalized
    local cap = CapFirst(lw)
    local firsts = { lw }
    if cap ~= lw then firsts[2] = cap end
    for _, q in ipairs(firsts) do
        local fb = byte(q, 1)
        for len = math.max(1, n - band), n + band do
            for _, bk in ipairs(srcs) do
                local blk = bk and bk[len * 256 + fb]
                if blk then
                    for p = 1, #blk, len do
                        local cand = blk:sub(p, p + len - 1)
                        -- Levenshtein counts a swap as 2: one more than the limit
                        if not GameDistance or GameDistance(q, cand) <= band + 1 then
                            local s = Score(q, cand, limit)
                            if s then Take(cand, s + ((q ~= lw) and CASE_COST or 0)) end
                        end
                    end
                end
            end
        end
    end
    -- A wrong first letter: swapped, changed, left out, one too many
    local rest = lw:sub(2)
    local tries = { lw:sub(2, 2) .. lw:sub(1, 1) .. lw:sub(3), rest }
    for c = 97, 122 do
        local ch = string.char(c)
        tries[#tries + 1] = ch .. rest
        tries[#tries + 1] = ch .. lw
    end
    for _, t in ipairs(tries) do
        if #t > 0 and t ~= lw and Known(t) then
            local s = Score(lw, t, limit)
            if s then Take(t, s) end
        end
    end
    -- Two words run together (alot -> a lot)
    for i = 1, n - 1 do
        local a, b = lw:sub(1, i), lw:sub(i + 1)
        if (#a > 1 or a == "a" or a == "i") and (#b > 1 or b == "a")
           and Known(a == "i" and "I" or a) and Known(b) then
            Take((a == "i" and "I" or a) .. " " .. b, (COMMON[a] or COMMON[b]) and 0.5 or 1)
        end
    end
    local list = {}
    for _, v in pairs(found) do list[#list + 1] = v end
    local last = byte(lw, n)
    table.sort(list, function(x, y)
        if x[2] ~= y[2] then return x[2] < y[2] end
        local dx, dy = math.abs(#x[1] - n), math.abs(#y[1] - n)
        if dx ~= dy then return dx < dy end
        local sx, sy = x[1]:find(" ", 1, true) ~= nil, y[1]:find(" ", 1, true) ~= nil
        if sx ~= sy then return sy end   -- one word before two
        local ex, ey = byte(x[1], #x[1]) == last, byte(y[1], #y[1]) == last
        if ex ~= ey then return ex end
        -- A lower-case word before a name, as typed
        local ux, uy = UpperFirst(x[1]), UpperFirst(y[1])
        if ux ~= uy then return not ux end
        return x[1] < y[1]
    end)
    local typedCap = UpperFirst(w)
    local typedAll = #w > 1 and not HasLower(w)   -- TEH -> THE
    for i = 1, math.min(MAX_SUGGEST, #list) do
        local s = list[i][1]
        if typedAll then out[i] = (s:gsub("[a-z]", string.upper))
        else out[i] = typedCap and CapFirst(s) or s end
    end
    return out
end

--------------------------------------------------------------------------------
-- The editors: the main editor's body, Focus mode's body (stage 3) and each
-- sticky's inline edit box (stage 3, marks only while editing). One record
-- per box in _editors, kind "main" / "focus" / "sticky"
--------------------------------------------------------------------------------

-- eb or ed -> ed (nil when the box has no checker)
local function EdOf(x)
    if type(x) ~= "table" then return nil end
    if x.eb and x.kind then return x end
    return _editors[x]
end

-- The box a check, the key or Correct spelling is for: Focus mode while it
-- is open, else the main editor
function SP.ActiveEditor()
    if BNB.IsFocusModeOpen and BNB.IsFocusModeOpen() then
        local fe = _editors[BNB._focusEditorBody]
        if fe then return fe end
    end
    return _main
end
function SP.EditorKind(eb)
    local ed = EdOf(eb)
    return ed and ed.kind or nil
end

-- noteID(): the note in the box. opts (optional):
--   kind     "main" (default) / "focus" / "sticky"
--   active() false = no marks now (a sticky outside its inline edit)
--   prepare() runs before a fix or a menu action (a sticky starts its
--            inline edit again: a click on the menu may have ended it)
--   replace(first, last, new, noFocus) -> true; the fix for a box with no
--            formatting bar (no undo there: the sticky inline edit)
-- Call after the box's last SetScript
function SP.AttachEditor(eb, sf, noteID, opts)
    if not (BNB.TextLines and eb and sf) or _editors[eb] then return end
    opts = opts or {}
    local ed = { eb = eb, kind = opts.kind or "main", noteID = noteID,
                 active = opts.active, prepare = opts.prepare, replace = opts.replace }
    local lastText, lastRanges
    ed.clickText, ed.clickRanges = nil, nil

    -- Every marked word of text, the one being typed too
    local function AllRanges(text)
        if not BNB.SpellEnabled() then return nil end
        if ed.active and not ed.active() then return nil end
        local id = noteID()
        if not id or tostring(id):find("^sys%-") then return nil end   -- Patch notes / Help
        if SP.ClickOnly(text) then
            if ed.clickText == text then return ed.clickRanges end
            ed.clickText, ed.clickRanges = nil, nil
            return nil
        end
        if text ~= lastText then lastText, lastRanges = text, SP.Mistakes(text) end
        return lastRanges
    end
    function ed.Current()
        if eb._showingPlaceholder then return nil end
        return AllRanges(eb:GetText() or "")
    end

    local function Ranges(text)
        if not AllRanges(text) then return nil end
        if SP.ClickOnly(text) then return ed.clickRanges end
        -- The word being typed is not marked until the cursor leaves it
        if eb:HasFocus() and #lastRanges > 0 then
            local cur = eb:GetCursorPosition() or -1
            local list
            for _, r in ipairs(lastRanges) do
                if r[2] ~= cur then list = list or {}; list[#list + 1] = r end
            end
            return list or {}
        end
        return lastRanges
    end

    ed.ctl = BNB.TextLines.Attach(eb, sf, Ranges, SP.Color)
    function ed.Redraw()
        lastText, lastRanges = nil, nil
        if ed.ctl then ed.ctl.Recolor() end
    end
    -- A sticky's inline edit starts and ends with the focus
    eb:HookScript("OnEditFocusGained", function() if ed.ctl then ed.ctl.Refresh() end end)
    eb:HookScript("OnEditFocusLost", function() if ed.ctl then ed.ctl.Refresh() end end)
    -- The Check spelling key while typing: bindings never see it then (ALL-567)
    eb:HookScript("OnKeyDown", function(_, key)
        if not BNB.KeyIsBinding then return end
        if BNB.KeyIsBinding("BIGNOTEBOXSPELLCHECK", key) then SP.CheckAndReport(ed)
        elseif ed.kind ~= "sticky" and BNB.KeyIsBinding("BIGNOTEBOXSPELLCORRECT", key) then
            if BNB.SpellCorrect then BNB.SpellCorrect.Open(nil, eb) end   -- no window for a sticky
        end
    end)
    _editors[eb] = ed
    if ed.kind == "main" then _main = ed end
    -- Text shortcuts (stage 4) in every box the checker is on
    if BNB.TextShortcuts then BNB.TextShortcuts.Wire(eb, ed) end
    return ed
end

-- Check spelling (the toolbar button): marks the text now, in either mode.
-- x = the box or its ed (nil = SP.ActiveEditor()).
-- -> the number of words marked, or nil when the lists are not there
function SP.CheckNow(x)
    local ed = EdOf(x) or SP.ActiveEditor()
    if not (ed and BNB.SpellEnabled()) then return end
    if not SP.EnsureLoaded() then SP.Announce(); return end
    local text = ed.eb:GetText() or ""
    ed.clickText, ed.clickRanges = text, SP.Mistakes(text)
    if ed.ctl then ed.Redraw() end
    return #ed.clickRanges
end

-- Check spelling as the toolbar buttons and the key do it, the count in
-- chat. x = the box or its ed (nil = SP.ActiveEditor()); the main editor's
-- rich View mode is switched to Edit first; a sticky only while editing
function SP.CheckAndReport(x)
    local ed = EdOf(x) or SP.ActiveEditor()
    if not (ed and BNB.SpellEnabled()) then return end
    if ed.active and not ed.active() then return end
    local id = ed.noteID()
    if not id or tostring(id):find("^sys%-") then return end
    local function Run()
        local n = SP.CheckNow(ed)
        if n == 0 then BNB:Print(L["SPELL_NONE_FOUND"])
        elseif n then BNB:Print(string.format(L["SPELL_FOUND_FMT"], n)) end
    end
    if ed.kind == "main" and BNB._editorInViewMode and BNB.AM_EnterEditMode then
        BNB.AM_EnterEditMode()
        C_Timer.After(0, Run)
    else
        Run()
    end
end

-- The key binding (BNB_KeybindSpellCheck, ALL-567) when no box has the
-- keyboard: Focus mode while it is open, else the main window's note
function SP.CheckFromKey()
    if BNB.IsFocusModeOpen and BNB.IsFocusModeOpen() then
        local fe = _editors[BNB._focusEditorBody]
        if fe then SP.CheckAndReport(fe) end
        return
    end
    local mf = BNB.mainFrame
    if not (mf and mf:IsVisible() and _main) then return end
    SP.CheckAndReport(_main)
end

-- The Correct spelling key (BNB_KeybindSpellCorrect, ALL-568) when no box
-- has the keyboard: the window on Focus mode's note or the main editor's
-- (BNB.SpellCorrect.Open picks the one in front and checks the rest)
function SP.CorrectFromKey()
    if not (BNB.SpellCorrect and BNB.SpellEnabled()) then return end
    if not (BNB.IsFocusModeOpen and BNB.IsFocusModeOpen()) then
        local mf = BNB.mainFrame
        if not (mf and mf:IsVisible()) then return end
    end
    BNB.SpellCorrect.Open()
end

--------------------------------------------------------------------------------
-- Fixing a word (stage 2): the body's right-click menu (Features/InsertInfo.lua)
-- and the toolbar's Add to dictionary
--------------------------------------------------------------------------------

local function EditorOf(eb)
    local ed = eb and _editors[eb]
    if ed and BNB.SpellEnabled() then return ed end
end
SP._EditorOf = EditorOf

-- A range -> { first, last, word, rep } (rep: a repeated word, the byte
-- after the word before it)
local function Hit(eb, r)
    if not r then return nil end
    local word = (eb:GetText() or ""):sub(r[1], r[2])
    return { first = r[1], last = r[2], word = word, rep = r.rep }
end
SP._Hit = Hit

-- The marked word under the mouse pointer -> a hit or nil. Asked on the
-- right-click's mouse down, before the box moves its cursor (the menu
-- opens a frame after the mouse up)
function SP.HitAtPointer(eb)
    local ed = EditorOf(eb)
    if not (ed and ed.ctl and ed.ctl.RangeAtPointer) then return end
    local r = ed.ctl.RangeAtPointer()
    if not r then return end
    -- Still that word (the lines may be a frame behind the text)
    local text = eb:GetText() or ""
    if r[2] > #text then return end
    return Hit(eb, r)
end

-- The marked word the text cursor is in or right after -> a hit or nil
function SP.HitAtCursor(eb)
    local ed = EditorOf(eb)
    if not ed then return end
    local ranges = ed.Current()
    if not ranges then return end
    local cur = eb:GetCursorPosition() or -1   -- bytes before the cursor
    for _, r in ipairs(ranges) do
        if cur >= r[1] - 1 and cur <= r[2] then return Hit(eb, r) end
    end
end
function SP.WordAtCursor(eb)
    local h = SP.HitAtCursor(eb)
    return h and not h.rep and h.word or nil
end

-- The word put right, if the text there is still that word; a repeated
-- word with new == "" goes with the space before it. noFocus: the box does
-- not take the keyboard (the Correct spelling window). -> true when done
function SP.Replace(eb, hit, new, noFocus)
    local ed = _editors[eb]
    if ed and ed.prepare then ed.prepare() end
    if (eb:GetText() or ""):sub(hit.first, hit.last) ~= hit.word then return false end
    local clickMode = SP.ClickOnly(eb:GetText() or "")
    local first = (hit.rep and new == "") and hit.rep or hit.first
    local done
    if ed and ed.replace then done = ed.replace(first, hit.last, new, noFocus)
    else done = BNB.ReplaceInEditor(eb, first, hit.last, new, noFocus) end
    if not done then
        BNB:Print(L["SPELL_REPLACE_FAILED"])
        return false
    end
    -- Measured once more a moment later: the next frame's redraw can still
    -- see the box laid out with the old text (a sticky's fix sets the text
    -- twice in one frame), so a later word's line kept the old width and
    -- place (Dukul, 2026-10-25: "the the" removed, "onee" underlined as "one")
    if ed then C_Timer.After(0.1, function() ed.Redraw() end) end
    if clickMode then
        -- Click mode drops the marks on an edit: the other words keep theirs
        C_Timer.After(0, function() SP.CheckNow(eb) end)
    end
    return true
end

-- A menu row's action: a sticky gets its inline edit back first (prepare)
local function Act(eb, fn)
    return function()
        local ed = _editors[eb]
        if ed and ed.prepare then ed.prepare() end
        fn()
    end
end

local function MenuWord(hit) return (hit.word:gsub("\226\128\153", "'")) end

-- The top of the body's right-click menu (Features/InsertInfo.lua): the
-- suggestions, or Remove for a repeated word, then a divider
function SP.AddMenuTop(root, eb, hit)
    if not (hit and EditorOf(eb)) then return end
    local word = MenuWord(hit)
    if hit.rep then
        root:CreateButton(string.format(L["SPELL_MENU_REMOVE_FMT"], word), function() SP.Replace(eb, hit, "") end,
            { icon = "spell-remove", tip = L["SPELL_MENU_REMOVE_TIP_HDR"], tipSub = L["SPELL_MENU_REMOVE_TIP"] })
    else
        local list = SP.Suggest(word)
        if #list == 0 then
            root:CreateButton(L["SPELL_MENU_NONE"], nil, { disabled = true, icon = "spell-suggest" })
        end
        for _, s in ipairs(list) do
            root:CreateButton(s, function() SP.Replace(eb, hit, s) end, { icon = "spell-suggest" })
        end
    end
    root:CreateDivider()
end

-- The middle of the menu, between the token groups and New token: Add to
-- dictionary, Ignore, Correct spelling (Dukul, 2026-10-25). A sticky's menu
-- has them under the suggestions, without Correct spelling (no window for
-- a sticky: Dukul, 2026-10-25)
function SP.AddMenuActions(root, eb, hit)
    local ed = hit and EditorOf(eb)
    if not ed then return end
    local word = MenuWord(hit)
    if not hit.rep then
        root:CreateButton(string.format(L["SPELL_MENU_ADD_FMT"], word), Act(eb, function() SP.AddWord(word) end),
            { icon = "dictionary", tip = L["SPELL_MENU_ADD"], tipSub = L["SPELL_MENU_ADD_TIP"] })
    end
    local ignoreTip = L["SPELL_MENU_IGNORE_TIP"]
    if hit.rep then ignoreTip = L["SPELL_MENU_IGNORE_REP_TIP"] end
    root:CreateButton(L["SPELL_MENU_IGNORE"], Act(eb, function()
        if hit.rep then SP.IgnoreRepeat(word) else SP.Ignore(word) end
    end), { icon = "spell-ignore", tip = L["SPELL_MENU_IGNORE"], tipSub = ignoreTip })
    if ed.kind == "sticky" then return end
    root:CreateButton(L["SPELL_MENU_CORRECT"], function()
        if BNB.SpellCorrect then BNB.SpellCorrect.Open(hit.first, eb) end
    end, { icon = "spell-correct", tip = L["SPELL_CORRECT_TITLE"], tipSub = L["NE_SPELL_CORRECT_BODY"] })
end

-- Add to dictionary on the toolbar: a popup asks first, the word filled in
-- and editable (Dukul, 2026-10-25: "that way you know which words to add")
local function PopupEditBox(self)
    return (self.GetEditBox and self:GetEditBox()) or self.EditBox or self.editBox
end
local function TryAdd(w)
    local clean = CleanWord(w)
    if not clean then
        if type(w) == "string" and w:match("%S") then BNB:Print(L["SPELL_ADD_NOT_WORD"]) end
        return
    end
    if not SP.AddWord(clean) then BNB:Print(string.format(L["SPELL_ADD_ALREADY_FMT"], clean)) end
end
SP.TryAdd = TryAdd   -- Focus mode's own ask window (UI/SpellCorrect.lua)
SP.MAX_WORD = MAX_WORD
StaticPopupDialogs["BNB_SPELL_ADD_WORD"] = {
    preferredIndex = 3,
    text = L["SPELL_ADD_POPUP"], hasEditBox = true, maxLetters = MAX_WORD,
    button1 = L["SPELL_ADD_POPUP_BTN"], button2 = CANCEL,
    OnShow = function(self, data)
        local eb = PopupEditBox(self)
        if eb then
            eb:SetText(data and data.word or "")
            eb:SetFocus()
            eb:HighlightText()
        end
    end,
    OnAccept = function(self)
        local eb = PopupEditBox(self)
        TryAdd(eb and eb:GetText())
    end,
    EditBoxOnEnterPressed = function(eb)
        TryAdd(eb:GetText())
        eb:GetParent():Hide()
    end,
    EditBoxOnEscapePressed = function(eb) eb:GetParent():Hide() end,
    timeout = 0, whileDead = true, hideOnEscape = true,
}
-- In Focus mode a game popup would sit under the Focus window (or be hidden
-- with the UI): the same question in a window of our own there
function SP.AskAddWord(word)
    word = word and word:gsub("\226\128\153", "'") or ""
    if BNB.IsFocusModeOpen and BNB.IsFocusModeOpen() and BNB.SpellCorrect and BNB.SpellCorrect.AskAdd then
        BNB.SpellCorrect.AskAdd(word)
        return
    end
    StaticPopup_Show("BNB_SPELL_ADD_WORD", nil, nil, { word = word })
end

-- The module switch (Settings > Modules > Spelling, the setup wizard)
function BNB.ApplySpellModule(on)
    if on then SP.Announce() end
    if BNB._wySpellSync then BNB._wySpellSync() end
    SP.Reset()
end

-- A tag added or renamed is one of the player's words (the list redraws after a tag edit)
BNB.RegisterMessage("Spellcheck", "NoteListRefreshed", function() _extra = nil; _memo, _memoN = {}, 0 end)

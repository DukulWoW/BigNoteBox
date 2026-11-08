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
--   spellLang      the default dictionary: "enUS" / "enGB", or one from the
--                  extra download BigNoteBox_SpellPack ("frFR", ALL-559 S5;
--                  "deDE", S5b);
--                  a note can have its own (note.spellLang, the right-click
--                  menu's Language row), nil = the default
--   spellMode      "type" = marks while typing, "click" = only after Check
--                  spelling (the toolbar button). A note over LONG_BYTES is
--                  checked on click whatever the setting (Dukul's idea, 2026-10-25)
--   spellSkipCaps  a capitalized word inside a sentence is taken as a name
--   spellSkipUpper words in capitals are not checked (off: LFG, ICC are in
--                  the game word list, Dukul 2026-10-25)
--   spellSkipDigits words with a number are not checked; off = their letters
--                  are (three or more), 1st / 2nd / 3rd / 4th always pass
--   spellRepeats   the same word twice in a row ("the the") is marked
--   spellCompounds compound words our looser rule finds pass (German; off =
--                  only the dictionary's own compound rules, ALL-559 S5b)
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
-- Stage 5 (ALL-559 S5): more languages, one load-on-demand folder each in the
-- extra download BigNoteBox_SpellPack (French first: BigNoteBox_Spell_frFR,
-- from the Hunspell dictionary, see _work/tools/dict-build.py --lang fr).
-- Each check runs in one language (_cur): the note's own, else the default.
-- A language's data may list elisions (French l' d' qu'...): "l'arbre" is
-- looked up as "arbre". Lower-casing knows Latin-1 capitals (E-acute), and
-- suggestions compare letters, not bytes, an accent alone costing little.
-- Stage 5b (German, BigNoteBox_Spell_deDE): nouns start with a capital, so a
-- German check never skips capitalized words (Skip names is for the other
-- languages); a word in capitals may spell sharp s as SS (STRASSE). Compound
-- words (Compound): the dictionary's own parts (begin / middle / endx in the
-- data), and, unless spellCompounds is off, our looser rule: noun + noun,
-- the first with its linking s / es / e (Arbeitsplatz, Schulbuch), every
-- part 3 letters or more, game words count (Questgeber). Suggestions for a
-- long word fix the broken part and keep the rest (CompoundSuggest).
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

local ADDON      = "BigNoteBox_Spell"   -- English (US + UK), in the main zip
local LONG_BYTES = 20000      -- longer notes: checked on click only
local MEMO_MAX   = 20000      -- remembered word answers before the memo is reset

local _data    = {}           -- lang -> what its word list folder handed over
local _tried   = {}           -- folder -> true: LoadAddOn is tried once per session
local _failure = {}           -- folder -> why it could not load
local _memo    = {}           -- lang -> { word -> true / false }
local _memoN   = {}           -- lang -> words in its memo
local _cur     = "enUS"       -- the language of the check running now (SP.Mistakes / SP.Suggest)
local _extra   = nil          -- game words of this player: classes, characters, tags
local _own     = nil          -- the player's own words, lower-case (BigNoteBoxNotesDB.spellWords)
local _ignored = {}           -- Ignore in the right-click menu: until the next reload
local _ignoredRep = {}        -- the same for a repeated word ("the the")
local _editors = {}           -- edit box -> its checker (SP.AttachEditor, below)
local _main                   -- the main editor's checker

-- The dictionaries, in the order the Spelling page and the menu list them.
-- addon = the folder that holds the list (English ships with BigNoteBox,
-- the rest are the extra download BigNoteBox_SpellPack, ALL-559 S5);
-- accents = suggestions also look at words that start with an accented
-- letter and allow this many more bytes (an accented letter is two); nouns = capitalized
-- words are always checked (German nouns); sharps = SS in a word in capitals
-- may be a sharp s. Compound words come with the data (begin, S5b)
local LANGS = {
    { code = "enUS", addon = ADDON, name = "CFG_SPELL_LANG_US", flag = "us" },
    { code = "enGB", addon = ADDON, name = "CFG_SPELL_LANG_UK", flag = "uk" },
    { code = "frFR", addon = "BigNoteBox_Spell_frFR", name = "CFG_SPELL_LANG_FR", flag = "fr", accents = 4 },
    { code = "deDE", addon = "BigNoteBox_Spell_deDE", name = "CFG_SPELL_LANG_DE", flag = "de", accents = 2,
      nouns = true, sharps = true },
}
local LANG_BY = {}
for _, l in ipairs(LANGS) do LANG_BY[l.code] = l end
SP.LANGS = LANGS

-- Called by the word list folders' files when they run
function BNB.ReceiveSpellData(lang, data)
    if type(lang) ~= "string" or type(data) ~= "table" then return end
    if type(data.elide) == "table" then
        local set = {}
        for _, e in ipairs(data.elide) do set[e] = true end
        data.elideSet = set
    end
    _data[lang] = data
end

function BNB.SpellEnabled()
    return BigNoteBoxDB ~= nil and BigNoteBoxDB.spellEnabled == true
end

-- Is the language's folder in the AddOns folder (enabled or not)?
function SP.Installed(lang)
    local def = LANG_BY[lang]
    if not def then return false end
    local ok, exists = pcall(C_AddOns.DoesAddOnExist, def.addon)
    return ok and exists and true or false
end

-- The default language: the Spelling page's pick while it is installed
function SP.DefaultLang()
    local v = BigNoteBoxDB and BigNoteBoxDB.spellLang
    if v and LANG_BY[v] and SP.Installed(v) then return v end
    return "enUS"
end

-- The language a note is checked in: its own (note.spellLang) while that
-- one is installed, else the default. No id = the default
function SP.Lang(noteID)
    if noteID and BNB.GetNote then
        local note = BNB.GetNote(noteID)
        local v = note and note.spellLang
        if v and LANG_BY[v] and SP.Installed(v) then return v end
    end
    return SP.DefaultLang()
end

-- A language's display name ("English (US)", "French")
function SP.LangName(lang)
    local def = LANG_BY[lang]
    if def then return L[def.name] end
    return tostring(lang)
end
function SP.LangFlag(lang)
    local def = LANG_BY[lang]
    return def and def.flag
end

-- The spelling shield on the title rows (Dukul, 2026-11-01): the note's
-- language when it is not the game's own. English US / UK are one family on
-- an English client, as German on a German one; a client with no dictionary
-- of its own language counts as English. Returns lang, shield file or nil
function SP.TitleShield(noteID)
    if not (noteID and BNB.SpellEnabled()) or tostring(noteID):find("^sys%-") then return nil end
    local lang = SP.Lang(noteID)
    local loc, home = (GetLocale and GetLocale() or "enUS"):sub(1, 2), "en"
    for _, l in ipairs(LANGS) do
        if l.code:sub(1, 2) == loc then home = loc; break end
    end
    if lang:sub(1, 2) == home or not SP.LangFlag(lang) then return nil end
    return lang, "shield-" .. SP.LangFlag(lang)
end

-- The open note's title-row shields again (a language, the default or the
-- module changed: SP.Reset)
function SP.RefreshTitleShields()
    local id = BNB._currentNoteID
    local note = id and BNB.GetNote and BNB.GetNote(id)
    if not note then return end
    if BNB.RefreshEditorLangBadge then BNB.RefreshEditorLangBadge(note.body) end
    if BNB.RefreshFocusLangBadge then BNB.RefreshFocusLangBadge(note.body) end
end

local function LoadFolder(addon)
    if _tried[addon] then return end
    _tried[addon] = true
    local ok, loaded, reason = pcall(C_AddOns.LoadAddOn, addon)
    if not ok then _failure[addon] = "ERROR"
    elseif not loaded then _failure[addon] = reason or "MISSING" end
end
local function Ready(lang)
    local d = _data[lang]
    if not d then return false end
    return not d.base or _data[d.base] ~= nil
end

-- Loads the language's word list once. -> true when the list is there.
-- The game words are always here (Features/SpellWords.lua), so a French
-- player never loads the English folder (Dukul, 2026-11-01)
function SP.EnsureLoaded(lang)
    lang = lang or SP.DefaultLang()
    if Ready(lang) then return true end
    local def = LANG_BY[lang] or LANG_BY.enUS
    LoadFolder(def.addon)
    if not Ready(lang) and not _failure[def.addon] then _failure[def.addon] = "ERROR" end
    return Ready(lang)
end

-- For the settings page: nil when loaded, else the reason
function SP.Failure(lang)
    local def = LANG_BY[lang or SP.DefaultLang()] or LANG_BY.enUS
    return _failure[def.addon]
end
function SP.WordCount(lang)
    local d = _data[lang or SP.DefaultLang()]
    return d and d.count or 0
end

-- Why it cannot work, in a chat line (when the player switches it on)
function SP.Announce(lang)
    lang = lang or SP.DefaultLang()
    if SP.EnsureLoaded(lang) then return end
    local f = SP.Failure(lang)
    if f == "MISSING" then BNB:Print(L["SPELL_ADDON_MISSING"])
    elseif f == "DISABLED" then BNB:Print(L["SPELL_ADDON_DISABLED"])
    else BNB:Print(string.format(L["SPELL_ADDON_FAILED_FMT"], tostring(f))) end
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

-- Never WoW's lower(): it changes bytes 128-255 one by one and would break
-- a UTF-8 letter (CLAUDE.md, ALL-507). a-z, then the Latin-1 capitals
-- (U+00C0-00DE but the times sign: C3 80-9E -> C3 A0-BE), OE (C5 92 -> 93)
-- and Y-diaeresis (C5 B8 -> C3 BF): the same byte count (ALL-559 S5)
local function LowerLatin1(c)
    local b = c:byte()
    if b == 151 then return nil end
    return "\195" .. string.char(b + 32)
end
local function LowerWord(w)
    w = w:gsub("[A-Z]", string.lower)
    if w:find("[\195\197]") then
        w = w:gsub("\195([\128-\158])", LowerLatin1)
        w = w:gsub("\197\146", "\197\147"):gsub("\197\184", "\195\191")
    end
    return w
end

local byte = string.byte

-- Never WoW's upper() (ALL-507): a-z, and the Latin-1 small letters
-- (C3 A0-BE but the division sign -> C3 80-9E, ALL-559 S5)
local function UpperLatin1(c)
    local b = c:byte()
    if b == 183 then return nil end
    return "\195" .. string.char(b - 32)
end
local function CapFirst(w)
    if byte(w, 1) == 195 then return (w:gsub("^\195([\160-\190])", UpperLatin1)) end
    return (w:gsub("^[a-z]", string.upper))
end
-- An upper-case first letter: A-Z, or a Latin-1 capital (U+00C0-U+00DE)
local function UpperFirst(w)
    local b = byte(w, 1)
    if b >= 65 and b <= 90 then return true end
    local b2 = byte(w, 2)
    return b == 195 and b2 ~= nil and b2 >= 128 and b2 <= 158 and b2 ~= 151
end

-- Words from this player's game: class names, known characters, tags
local function AddWords(set, text)
    if type(text) ~= "string" then return end
    for w in text:gmatch("[A-Za-z\128-\255']+") do set[LowerWord(w)] = true end
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
        if type(w) == "string" then set[LowerWord(w)] = true end
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
        local la, lb = LowerWord(a), LowerWord(b)
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
    if SP.OwnSet()[LowerWord(w)] then return false end
    OwnStore(true)[w] = true
    OwnChanged()
    if not quiet then BNB:Print(string.format(L["SPELL_ADDED_FMT"], w)) end
    return true
end

-- Ignore (the right-click menu): this word is not marked until the next reload
function SP.Ignore(w)
    w = CleanWord(w)
    if not w then return end
    _ignored[LowerWord(w)] = true
    SP.Reset()
end

-- Ignore on a repeated word: that word twice in a row is fine until the next reload
function SP.IgnoreRepeat(w)
    if type(w) ~= "string" or w == "" then return end
    _ignoredRep[LowerWord(w)] = true
    SP.Reset()
end

-- One word out of your list (the X on the Spelling page)
function SP.RemoveWord(w)
    local store = OwnStore()
    if not (store and type(w) == "string") then return end
    local lw = LowerWord(w)
    for k in pairs(store) do
        if type(k) == "string" and LowerWord(k) == lw then store[k] = nil end
    end
    OwnChanged()
end

-- A word in your list changed (clicked on the Spelling page). -> true when
-- done; false when new is not a word or is in the list already
function SP.RenameWord(old, new)
    new = CleanWord(new)
    if not (new and type(old) == "string") then return false end
    if new == old then return true end
    local lo, ln = LowerWord(old), LowerWord(new)
    if ln ~= lo and SP.OwnSet()[ln] then return false end
    local store = OwnStore(true)
    for k in pairs(store) do
        if type(k) == "string" and LowerWord(k) == lo then store[k] = nil end
    end
    store[new] = true
    OwnChanged()
    return true
end

-- The JSON full backup (Features/NoteExport.lua)
-- Every word in your list gone (Danger Zone, ALL-578) -> the number deleted
function SP.ClearWords()
    local n = #SP.WordList()
    local ndb = BNB.NotesDB and BNB.NotesDB()
    if ndb then ndb.spellWords = nil end
    OwnChanged()
    return n
end

function SP.BackupList() return SP.WordList() end
-- -> the number of words added; words already here are left alone
function SP.ImportList(list)
    if type(list) ~= "table" then return 0 end
    local n = 0
    local store
    for _, w in ipairs(list) do
        w = CleanWord(w)
        if w and not SP.OwnSet()[LowerWord(w)] then
            store = store or OwnStore(true)
            store[w] = true
            _own[LowerWord(w)] = true
            n = n + 1
        end
    end
    if n > 0 then OwnChanged() end
    return n
end

-- The word as it is, in the language of the check running now (_cur)
local function KnownPlain(w)
    local d = _data[_cur]
    if d and d.base then
        if InBuckets(d.add, w) then return true end
        if InBuckets(d.drop, w) then return false end
        d = _data[d.base]
    end
    if d and InBuckets(d.words, w) then return true end
    return _data.wow ~= nil and InBuckets(_data.wow.words, w)
end

--------------------------------------------------------------------------------
-- Compound words (German, ALL-559 S5b). Every part is looked up as it is
-- written; a part after the first starts with a small letter (Gilden + bank:
-- "Bank" is the noun looked up). The dictionary's rules: a start from its
-- begin list, middles from its middle list, an end that is a noun (or one
-- of endx), parts of cmin bytes. Our looser rule (spellCompounds, a noun
-- compound only): any noun starts one, also with the linking s / es, or
-- without its last e; parts of 3 bytes or more; game words count
--------------------------------------------------------------------------------
local LOOSE_MIN = 3

-- Never split inside a letter: a part cannot start with a UTF-8 continuation byte
local function Cut(w, i)
    local b = byte(w, i)
    return b ~= nil and (b < 128 or b > 191)
end
local function LooseOn()
    return not (BigNoteBoxDB and BigNoteBoxDB.spellCompounds == false)
end
-- A word of the language's list, or a game word (raid, quest)
local function InWords(w)
    local d = _data[_cur]
    if d and InBuckets(d.words, w) then return true end
    return _data.wow ~= nil and InBuckets(_data.wow.words, LowerWord(w))
end

local function HeadStrict(h)
    local d = _data[_cur]
    return #h >= (d.cmin or 2) and InBuckets(d.begin, h)
end
local function MidStrict(m)
    local d = _data[_cur]
    return #m >= (d.cmin or 2) and InBuckets(d.middle, m)
end
local function TailStrict(t)
    local d = _data[_cur]
    return #t >= (d.cmin or 2) and (InBuckets(d.endx, t) or InBuckets(d.words, CapFirst(t)))
end

-- h starts with its capital: Arbeits(platz), Tages(licht), Schul(buch)
local function HeadLoose(h)
    local n = #h
    if n < LOOSE_MIN then return false end
    local d = _data[_cur]
    if InWords(h) or InBuckets(d.begin, h) then return true end
    if byte(h, n) == 115 and n > LOOSE_MIN then                   -- s
        if InBuckets(d.words, h:sub(1, n - 1)) then return true end
        if n > LOOSE_MIN + 1 and byte(h, n - 1) == 101
           and InBuckets(d.words, h:sub(1, n - 2)) then return true end   -- es
    end
    return InBuckets(d.words, h .. "e")
end
local function MidLoose(m)
    return HeadLoose(CapFirst(m)) or InBuckets(_data[_cur].middle, m)
end
-- A noun, or a word as written (Heil + traenke: the dictionary has the verb form only)
local function TailLoose(t)
    if #t < LOOSE_MIN then return false end
    local d = _data[_cur]
    return InWords(CapFirst(t)) or InBuckets(d.words, t) or InBuckets(d.endx, t)
end

-- w as parts: a head, any middles, an end. The ends are found first (few
-- of them pass), then the start is split up to them; memo per call
local function Splits(w, minp, headOk, midOk, tailOk)
    local n = #w
    local ends
    for k = minp + 1, n - minp + 1 do
        if Cut(w, k) and tailOk(w:sub(k)) then
            ends = ends or {}
            ends[#ends + 1] = k
        end
    end
    if not ends then return false end
    local memo = {}
    -- w:sub(i, k - 1) as one part or more: a head when i == 1, else middles
    local function Chain(i, k, depth)
        local key = i * 4096 + k
        local c = memo[key]
        if c ~= nil then return c end
        local okFn = (i == 1) and headOk or midOk
        local ok = (k - i >= minp) and okFn(w:sub(i, k - 1)) or false
        if not ok and depth < 4 then
            for j = i + minp, k - minp do
                if Cut(w, j) and okFn(w:sub(i, j - 1)) and Chain(j, k, depth + 1) then ok = true; break end
            end
        end
        memo[key] = ok
        return ok
    end
    for _, k in ipairs(ends) do
        if Chain(1, k, 1) then return true end
    end
    return false
end

local function Compound(w)
    local d = _data[_cur]
    if not (d and d.begin) or #w < 4 then return false end
    if Splits(w, d.cmin or 2, HeadStrict, MidStrict, TailStrict) then return true end
    if not LooseOn() or #w < 2 * LOOSE_MIN or not UpperFirst(w) then return false end
    return Splits(w, LOOSE_MIN, HeadLoose, MidLoose, TailLoose)
end

-- A compound's start before a "-" in the text: "Arbeits- und Sozialminister"
local function HyphenHead(w)
    local d = _data[_cur]
    if not (d and d.begin) then return false end
    return HeadStrict(w) or (LooseOn() and UpperFirst(w) and HeadLoose(w))
end

-- Known as it is: in the lists, or (German) a compound of known parts
local function Known(w)
    if KnownPlain(w) then return true end
    local d = _data[_cur]
    return d ~= nil and d.begin ~= nil and Compound(w)
end

-- In the word lists (any case), leaving out the player's own words and
-- game words: a text shortcut that is a real word gets a warning (stage 4)
function SP.InDictionary(w)
    _cur = SP.DefaultLang()
    if type(w) ~= "string" or not SP.EnsureLoaded(_cur) then return false end
    return KnownPlain(w) or KnownPlain(LowerWord(w))
end

-- Any lower-case letter (a-z or a Latin-1 small one)
local function HasLowerLetter(w)
    return w:find("[a-z]") ~= nil or w:find("\195[\159-\191]") ~= nil
end

-- w: the word with ' for a typographic apostrophe. "The" at a sentence's
-- start is "the"; "PARIS" may be "Paris"; "dog's" is "dog"
local function CheckWord(w)
    local memo = _memo[_cur]
    if not memo then memo = {}; _memo[_cur] = memo; _memoN[_cur] = 0 end
    local c = memo[w]
    if c ~= nil then return c end
    local ok = Known(w)
    if not ok then
        local lw = LowerWord(w)
        if lw ~= w then
            ok = Known(lw)
            -- PARIS -> Paris; an accented capital is two bytes (ECOLE)
            if not ok and not HasLowerLetter(w) then
                local fl = (byte(w, 1) >= 192) and 2 or 1
                ok = Known(w:sub(1, fl) .. lw:sub(fl + 1))
                -- German STRASSE: Strasse is written with a sharp s
                local def = LANG_BY[_cur]
                if not ok and def and def.sharps and lw:find("ss", 1, true) then
                    local sharp = lw:gsub("ss", "\195\159")
                    ok = Known(sharp) or Known(CapFirst(sharp))
                end
            end
        end
        if not ok and (Extra()[lw] or SP.OwnSet()[lw] or _ignored[lw]) then ok = true end
        -- An elision (French l'arbre, qu'il): the word after it
        if not ok then
            local el = _data[_cur] and _data[_cur].elideSet
            local pre = el and lw:match("^(.-')")
            if pre and el[pre] and #w - #pre > 1 then ok = CheckWord(w:sub(#pre + 1)) end
        end
        if not ok then
            local stem = w:match("^(.+)'[sS]$") or w:match("^(.+[sS])'$")
            if stem and #stem > 1 then ok = CheckWord(stem) end
        end
    end
    if _memoN[_cur] >= MEMO_MAX then memo = {}; _memo[_cur] = memo; _memoN[_cur] = 0 end
    memo[w] = ok
    _memoN[_cur] = _memoN[_cur] + 1
    return ok
end

-- Settings, the language or the player's words changed
function SP.Reset()
    _memo, _memoN, _extra = {}, {}, nil
    for _, ed in pairs(_editors) do
        -- Click mode: the marks of the last check, asked again (Add / Ignore)
        if ed.clickText then ed.clickRanges = SP.Mistakes(ed.clickText, ed.Lang()) end
        ed.Redraw()
    end
    pcall(SP.RefreshTitleShields)
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
function SP.Mistakes(text, lang)
    local out = {}
    _cur = lang or SP.DefaultLang()
    if type(text) ~= "string" or text == "" or not SP.EnsureLoaded(_cur) then return out end
    local t = Masked(text)
    local n = #t
    local db = BigNoteBoxDB or {}
    local skipCaps   = db.spellSkipCaps ~= false
    local skipUpper  = db.spellSkipUpper == true
    local skipDigits = db.spellSkipDigits ~= false
    local repeats    = db.spellRepeats ~= false
    -- German: every noun has a capital, so capitals are never taken as names
    if LANG_BY[_cur] and LANG_BY[_cur].nouns then skipCaps = false end
    local prevW, prevE                      -- the word before, for "the the"
    -- -> true when the word got marked
    local function Check(s, e, w)
        local lower = HasLower(w)
        local check
        if lower then check = not MixedCase(w) else check = not skipUpper end
        if check and lower and skipCaps and UpperFirst(w) and not SentenceStart(t, s) then check = false end
        if check and not CheckWord(w) and not (byte(t, e + 1) == 45 and HyphenHead(w)) then
            out[#out + 1] = { s, e, "x" }
            return true
        end
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
            local lw = LowerWord(w)
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

-- Suggestions compare letters, not bytes (ALL-559 S5): a word is scored in
-- Latin-1, one byte per letter (UTF-8 C2 / C3 xx -> one byte, OE -> 156),
-- and a letter that differs from the typed one only by its accent costs
-- ACCENT_COST (ete -> ete-acute). BASE = the plain letter of a Latin-1 one
local ACCENT_COST = 0.3
local BASE = {}
local ACCENTED = {}   -- plain letters that have accented forms (a, e, ... and capitals)
do
    local groups = {
        a = { 224, 225, 226, 227, 228, 229 }, c = { 231 }, e = { 232, 233, 234, 235 },
        i = { 236, 237, 238, 239 }, n = { 241 }, o = { 242, 243, 244, 245, 246, 248, 156 },
        u = { 249, 250, 251, 252 }, y = { 253, 255 },
    }
    for letter, list in pairs(groups) do
        local b = letter:byte()
        ACCENTED[b], ACCENTED[b - 32] = true, true
        for _, c in ipairs(list) do
            BASE[c] = b
            if c >= 224 and c ~= 255 then BASE[c - 32] = b - 32 end   -- the capital
            if VOWEL[b] then VOWEL[c] = true end
        end
    end
    BASE[223] = 115    -- German sharp s ~ s (Strase -> Strasse, S5b)
end
local function ToL1(w)
    if not w:find("[\194\195\197]") then return w end
    w = w:gsub("\195([\128-\191])", function(c) return string.char(c:byte() + 64) end)
    w = w:gsub("\194([\128-\191])", "%1")
    return (w:gsub("\197[\146\147]", "\156"))
end
-- Accents gone: the plain letters, for the game's edit distance
local function Plain(l1)
    if not l1:find("[\128-\255]") then return l1 end
    return (l1:gsub("[\128-\255]", function(c)
        local b = BASE[c:byte()]
        return b and string.char(b) or c
    end))
end

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
            local sub = 1
            if ca == cb then sub = 0
            elseif (BASE[ca] or ca) == (BASE[cb] or cb) then sub = ACCENT_COST
            elseif Near(ca, cb) then sub = 0.6 end
            local v = prev[j - 1] + sub
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

-- The bucket tables of the check's language, and the one taken out of it (UK)
local function Sources()
    local d = _data[_cur]
    local list, drop = {}, nil
    if d and d.base then list[#list + 1] = d.add; drop = d.drop; d = _data[d.base] end
    if d then list[#list + 1] = d.words end
    if _data.wow then list[#list + 1] = _data.wow.words end
    return list, drop
end

local function UpperWord(w)
    return (w:gsub("[a-z]", string.upper):gsub("\195([\160-\190])", UpperLatin1))
end

-- Scored candidates for lw into found (lower-case key -> { word, score })
-- -> how many were taken. whole: lw is the typed word itself (then the
-- first-letter tries and two words run together too). pre / post: lw is a
-- part of a compound (German, S5b): a candidate is joined back to the rest
-- of the word, and taken only when the checker knows the result
local function Collect(lw, found, whole, pre, post)
    local l1 = ToL1(lw)        -- one byte per letter
    local n  = #l1             -- letters
    if n < 2 then return 0 end
    local limit = n <= 3 and 1 or 2
    local band  = math.floor(limit)
    local accents = LANG_BY[_cur] and LANG_BY[_cur].accents
    local nouns = LANG_BY[_cur] and LANG_BY[_cur].nouns and whole
    local srcs, drop = Sources()
    local taken = 0
    local function Take(cand, s)
        local key = LowerWord(cand)
        if (key == lw and not (nouns and cand ~= lw)) or (drop and InBuckets(drop, cand)) then return end
        if pre or post then
            if pre then
                local fl = (byte(cand, 1) >= 192) and 2 or 1
                cand = pre .. LowerWord(cand:sub(1, fl)) .. cand:sub(fl + 1)
            end
            if post then cand = cand .. post end
            if not Known(cand) then
                cand = CapFirst(cand)
                if not Known(cand) then return end
            end
            key = LowerWord(cand)
        end
        local old = found[key]
        if not old or s < old[2] or (s == old[2] and cand < old[1]) then
            found[key] = { cand, s }
            taken = taken + 1
        end
    end
    -- Same first letter: every word in the band, lower-case and capitalized.
    -- A language with accents also looks under the other first bytes of
    -- that letter (e -> words that start with e-acute and the reverse) and
    -- a few more bytes (every accent is one byte more than its letter); a
    -- letter with no accented forms (d, g) has nothing under those bytes
    local cap = CapFirst(lw)
    local firsts = { lw }
    if cap ~= lw then firsts[2] = cap end
    local extra = accents or 0
    local bl = #lw
    for _, q in ipairs(firsts) do
        local fb = byte(q, 1)
        local ql1 = ToL1(q)
        local qBase = BASE[byte(ql1, 1)] or byte(ql1, 1)
        local fbs = { fb }
        if accents then
            if fb ~= 195 then
                if ACCENTED[qBase] then fbs[2] = 195 end
            elseif qBase < 128 then fbs[2] = qBase end
        end
        for _, firstByte in ipairs(fbs) do
            for len = math.max(1, bl - band - extra), bl + band + extra do
                for _, bk in ipairs(srcs) do
                    local blk = bk and bk[len * 256 + firstByte]
                    if blk then
                        for p = 1, #blk, len do
                            local cand = blk:sub(p, p + len - 1)
                            local c1 = accents and ToL1(cand) or cand
                            local ok = math.abs(#c1 - n) <= band
                            -- Another first byte: only words of the same plain first letter
                            if ok and firstByte ~= fb then ok = (BASE[byte(c1, 1)] or byte(c1, 1)) == qBase end
                            -- Levenshtein counts a swap as 2: one more than the limit
                            if ok and GameDistance then
                                if accents then ok = GameDistance(Plain(ql1), Plain(c1)) <= band + 1
                                else ok = GameDistance(q, cand) <= band + 1 end
                            end
                            if ok then
                                local s = Score(ql1, c1, limit)
                                if s then Take(cand, s + ((q ~= lw) and CASE_COST or 0)) end
                            end
                        end
                    end
                end
            end
        end
    end
    if not whole then return taken end
    -- A wrong first letter: swapped, changed, left out, one too many
    -- (a-z: plain letters only)
    local rest = lw:sub(2)
    local tries = { lw:sub(2, 2) .. lw:sub(1, 1) .. lw:sub(3), rest }
    for c = 97, 122 do
        local ch = string.char(c)
        tries[#tries + 1] = ch .. rest
        tries[#tries + 1] = ch .. lw
    end
    for _, t in ipairs(tries) do
        if #t > 0 and t ~= lw and KnownPlain(t) then
            local s = Score(l1, ToL1(t), limit)
            if s then Take(t, s) end
        end
    end
    -- Two words run together (alot -> a lot)
    for i = 1, n - 1 do
        local a, b = lw:sub(1, i), lw:sub(i + 1)
        if (#a > 1 or a == "a" or a == "i") and (#b > 1 or b == "a")
           and KnownPlain(a == "i" and "I" or a) and KnownPlain(b) then
            Take((a == "i" and "I" or a) .. " " .. b, (COMMON[a] or COMMON[b]) and 0.5 or 1)
        end
    end
    return taken
end

-- A long German word: a good start (a word that can start a compound) and
-- a good end (one that can end it), and the piece between gets suggestions,
-- joined back (Drachen + schupen + ruestung -> Drachenschuppenruestung). The
-- shortest pieces first; a few scans at most, each one is a scan of its own
local SUGGEST_SCANS = 4
local function CompoundSuggest(lw, found)
    local n = #lw
    local loose = LooseOn()
    local function HeadOk(h) return HeadStrict(h) or (loose and HeadLoose(h)) end
    local function TailOk(t) return TailStrict(t) or (loose and TailLoose(t)) end
    local starts, ends = { 0 }, { n + 1 }      -- 0 / n + 1 = no start / no end
    for i = LOOSE_MIN, n - LOOSE_MIN do
        if Cut(lw, i + 1) and HeadOk(CapFirst(lw:sub(1, i))) then starts[#starts + 1] = i end
    end
    for k = LOOSE_MIN + 1, n - LOOSE_MIN + 1 do
        if Cut(lw, k) and TailOk(lw:sub(k)) then ends[#ends + 1] = k end
    end
    local pieces = {}
    for _, i in ipairs(starts) do
        for _, k in ipairs(ends) do
            local len = k - i - 1
            if len >= LOOSE_MIN and len < n then pieces[#pieces + 1] = { i, k, len } end
        end
    end
    table.sort(pieces, function(a, b)
        if a[3] ~= b[3] then return a[3] < b[3] end
        return a[1] > b[1]
    end)
    local scans = 0
    for _, p in ipairs(pieces) do
        local i, k = p[1], p[2]
        local pre  = i > 0 and lw:sub(1, i) or nil
        local post = k <= n and lw:sub(k) or nil
        scans = scans + 1
        Collect(lw:sub(i + 1, k - 1), found, false, pre, post)
        if scans >= SUGGEST_SCANS then break end
    end
end

-- -> up to MAX_SUGGEST words, best first, in the typed word's case.
-- lang: the note's language (nil = the default)
function SP.Suggest(word, lang)
    local out = {}
    _cur = lang or SP.DefaultLang()
    if type(word) ~= "string" or not SP.EnsureLoaded(_cur) then return out end
    local w  = word:gsub("\226\128\153", "'")
    local lw = LowerWord(w)
    local n  = #ToL1(lw)       -- letters
    if n < 2 then return out end
    local found = {}   -- lower-case -> { word, score }
    Collect(lw, found, true)
    local d = _data[_cur]
    if d and d.begin and n >= 8 then CompoundSuggest(lw, found) end
    local list = {}
    for _, v in pairs(found) do list[#list + 1] = v end
    table.sort(list, function(x, y)
        if x[2] ~= y[2] then return x[2] < y[2] end
        local dx, dy = math.abs(#ToL1(x[1]) - n), math.abs(#ToL1(y[1]) - n)
        if dx ~= dy then return dx < dy end
        local sx, sy = x[1]:find(" ", 1, true) ~= nil, y[1]:find(" ", 1, true) ~= nil
        if sx ~= sy then return sy end   -- one word before two
        local ex, ey = byte(x[1], #x[1]) == byte(lw, #lw), byte(y[1], #y[1]) == byte(lw, #lw)
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
        if typedAll then out[i] = UpperWord(s)
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
    -- The note's language (ALL-559 S5)
    function ed.Lang() return SP.Lang(noteID()) end
    local lastText, lastRanges, lastLang
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
        local lang = ed.Lang()
        if text ~= lastText or lang ~= lastLang then
            lastText, lastLang, lastRanges = text, lang, SP.Mistakes(text, lang)
        end
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
    local lang = ed.Lang()
    if not SP.EnsureLoaded(lang) then SP.Announce(lang); return end
    local text = ed.eb:GetText() or ""
    ed.clickText, ed.clickRanges = text, SP.Mistakes(text, lang)
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
-- The language of the note in a box (the default when it has no checker)
function SP.LangOfBox(eb)
    local ed = eb and _editors[eb]
    return ed and ed.Lang() or SP.DefaultLang()
end

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
        local list = SP.Suggest(word, SP.LangOfBox(eb))
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
    SP.AddLanguageMenu(root, ed)
    if ed.kind == "sticky" then return end
    root:CreateButton(L["SPELL_MENU_CORRECT"], function()
        if BNB.SpellCorrect then BNB.SpellCorrect.Open(hit.first, eb) end
    end, { icon = "spell-correct", tip = L["SPELL_CORRECT_TITLE"], tipSub = L["NE_SPELL_CORRECT_BODY"] })
end

-- The note's language (ALL-559 S5, Dukul 2026-10-29: "change on the fly
-- (per note maybe?)"): a Language sub-menu, the default first, then every
-- installed dictionary. Saved on the note as spellLang (nil = the default)
local FLAG_ART = "Interface\\AddOns\\BigNoteBox\\Assets\\Flags\\shield-"
function SP.SetNoteLang(noteID, lang)
    if not (noteID and BNB.GetNote and BNB.GetNote(noteID)) then return end
    if tostring(noteID):find("^sys%-") then return end
    if lang then BNB.UpdateNote(noteID, { spellLang = lang }, { noTouch = true })
    else BNB.UpdateNote(noteID, { _clear = { "spellLang" } }, { noTouch = true }) end
    SP.Reset()
end
function SP.AddLanguageMenu(root, ed)
    local id = ed and ed.noteID()
    if not id or tostring(id):find("^sys%-") then return end
    if not (BNB.GetNote and BNB.GetNote(id)) then return end
    local cur = ed.Lang()
    local parent = root:CreateButton(string.format(L["SPELL_MENU_LANG_FMT"], SP.LangName(cur)), nil,
        { icon = "spell-language", tip = L["SPELL_MENU_LANG"], tipSub = L["SPELL_MENU_LANG_TIP"] })
    SP.AddLanguageRows(parent, id, ed.eb)
end

-- The language rows (a shield each, the note's pick ticked): the default
-- first, then every installed dictionary. Shared by the right-click
-- sub-menu and the toolbar's tb-language menu (Dukul, 2026-11-01).
-- eb = the note's edit box (its editor gets ready before the change)
function SP.AddLanguageRows(parent, id, eb)
    local note = id and BNB.GetNote and BNB.GetNote(id)
    if not note or tostring(id):find("^sys%-") then return end
    local ed = { eb = eb }
    local def = SP.DefaultLang()
    parent:CreateRadio(string.format(L["SPELL_MENU_LANG_DEFAULT_FMT"], SP.LangName(def)),
        function() return note.spellLang == nil end,
        Act(ed.eb, function() SP.SetNoteLang(id, nil) end),
        { iconTex = FLAG_ART .. SP.LangFlag(def) })
    for _, l in ipairs(LANGS) do
        if SP.Installed(l.code) then
            parent:CreateRadio(L[l.name],
                function() return note.spellLang == l.code end,
                Act(ed.eb, function() SP.SetNoteLang(id, l.code) end),
                { iconTex = FLAG_ART .. l.flag })
        end
    end
end

-- Add to dictionary on the toolbar: a dialog asks first, the word filled in
-- and editable (Dukul, 2026-10-25: "that way you know which words to add")
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
-- In Focus mode a game popup would sit under the Focus window (or be hidden
-- with the UI): the same question in a window of our own there
function SP.AskAddWord(word)
    word = word and word:gsub("\226\128\153", "'") or ""
    if BNB.IsFocusModeOpen and BNB.IsFocusModeOpen() and BNB.SpellCorrect and BNB.SpellCorrect.AskAdd then
        BNB.SpellCorrect.AskAdd(word)
        return
    end
    -- Our own dialog (ALL-572 S2); Focus mode keeps its window above
    BNB.Dialog.Prompt({
        title = L["SPELL_MENU_ADD"], text = L["SPELL_ADD_POPUP"], value = word,
        maxLetters = MAX_WORD, okLabel = L["SPELL_ADD_POPUP_BTN"],
        onAccept = TryAdd,
    })
end

-- The module switch (Settings > Modules > Spelling, the setup wizard)
function BNB.ApplySpellModule(on)
    if on then SP.Announce() end
    if BNB._wySpellSync then BNB._wySpellSync() end
    SP.Reset()
end

-- A tag added or renamed is one of the player's words (the list redraws after a tag edit)
BNB.RegisterMessage("Spellcheck", "NoteListRefreshed", function() _extra = nil; _memo, _memoN = {}, {} end)

--------------------------------------------------------------------------------
-- Spellcheck.lua -- the spellchecker (ALL-559 stage 1)
--
-- Marks words that are not in the dictionary with a red line under them in
-- the main editor's body. The text is never touched: the lines are drawn over
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
    _extra = set
    return set
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
        if not ok and Extra()[lw] then ok = true end
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
    if SP._editor then SP._editor.Redraw() end
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

-- The words that are not in the dictionary -> { { first, last, "x" }, ... }
function SP.Mistakes(text)
    local out = {}
    if type(text) ~= "string" or text == "" or not SP.EnsureLoaded() then return out end
    local t = Masked(text)
    local n = #t
    local skipCaps = not BigNoteBoxDB or BigNoteBoxDB.spellSkipCaps ~= false
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
            local check = HasLower(w) and not MixedCase(w)
            if check and skipCaps and UpperFirst(w) and not SentenceStart(t, s) then check = false end
            if check and not CheckWord(w) then out[#out + 1] = { s, e, "x" } end
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
-- The main editor's body (stage 3: Focus mode and the sticky inline edit)
--------------------------------------------------------------------------------

-- noteID(): the note in the box. Call after the box's last SetScript
function SP.AttachEditor(eb, sf, noteID)
    if not (BNB.TextLines and eb and sf) or SP._editor then return end
    local ed = { eb = eb }
    local lastText, lastRanges
    ed.clickText, ed.clickRanges = nil, nil

    local function Ranges(text)
        if not BNB.SpellEnabled() then return nil end
        local id = noteID()
        if not id or tostring(id):find("^sys%-") then return nil end   -- Patch notes / Help
        if SP.ClickOnly(text) then
            if ed.clickText == text then return ed.clickRanges end
            ed.clickText, ed.clickRanges = nil, nil
            return nil
        end
        if text ~= lastText then lastText, lastRanges = text, SP.Mistakes(text) end
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
    eb:HookScript("OnEditFocusLost", function() if ed.ctl then ed.ctl.Refresh() end end)
    SP._editor = ed
end

-- Check spelling (the toolbar button): marks the text now, in either mode.
-- -> the number of words marked, or nil when the lists are not there
function SP.CheckNow()
    local ed = SP._editor
    if not (ed and BNB.SpellEnabled()) then return end
    if not SP.EnsureLoaded() then SP.Announce(); return end
    local text = ed.eb:GetText() or ""
    ed.clickText, ed.clickRanges = text, SP.Mistakes(text)
    if ed.ctl then ed.Redraw() end
    return #ed.clickRanges
end

-- The module switch (Settings > Modules > Spelling, the setup wizard)
function BNB.ApplySpellModule(on)
    if on then SP.Announce() end
    if BNB._wySpellSync then BNB._wySpellSync() end
    SP.Reset()
end

-- A tag added or renamed is one of the player's words (the list redraws after a tag edit)
BNB.RegisterMessage("Spellcheck", "NoteListRefreshed", function() _extra = nil; _memo, _memoN = {}, 0 end)

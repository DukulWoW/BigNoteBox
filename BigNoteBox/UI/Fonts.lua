-- BigNoteBox UI/Fonts.lua — Custom font registry
--
-- Font families shipped:
--   Noto Serif    — default; widest UTF-8 coverage, good for prose
--   EB Garamond   — classic serif, elegant at larger sizes
--   Noto Sans     — clean sans-serif alternative
--   JetBrains Mono — monospace; structured notes, rosters, code
--
-- WHY DEFERRED INIT:
--   CreateFont() called at file-load time (before PLAYER_LOGIN) can produce
--   blank glyphs on the first session because WoW's font renderer hasn't
--   finished registering the .ttf files yet.  BNB.InitFonts() is called
--   from Initialize.lua (after PLAYER_LOGIN + 0.5s timer) where the renderer
--   is fully ready, which fixes the double-reload symptom.
--
-- Public API:
--   BNB.FONTS            — ordered list of font definition tables
--   BNB.GetFontDef(id)   — returns the def table for a given id
--   BNB.GetBodyFont()    — returns (path, size) for the current DB choice
--   BNB.GetBoldFont()    — returns bold path for the current DB choice
--   BNB.GetUIFont() / BNB.GetUIBoldFont() — same, but WoW's locale font on CJK
--                          clients when the choice is a bundled (Latin-only) TTF
--   BNB.ApplyFont(id, size) — saves choice + applies to all live widgets
--   BNB.InitFonts()      — called once on login; creates WoW Font objects
--
-- Font sets (ALL-14): every card belongs to a script set ("latin", "hans"). The
-- active language picks the set, the pickers show only that set's cards, and each
-- set remembers its own pick. Saved choices are never rewritten: a choice that
-- cannot be shown under the active set (wrong set, pack or LSM font gone) falls
-- back to the set's default at display time only.
--   BNB.GetActiveFontSet()     — "latin" or "hans"
--   BNB.GetFontChoice()        — the stored pick for the active set (may be unusable)
--   BNB.GetEffectiveFontID()   — the id actually drawn for the global font
--   BNB.ResolveFontID(id)      — id if usable under the active set, else nil
--   BNB.ResolveFontDef(id)     — def for a per-note override, or the global def
--   BNB.GetPickerFonts(withLSM) — the cards for the active set, max 8
--   BNB.RegisterFontPack(pack) — called by a font pack addon at load time

local BNB = BigNoteBox
local L   = BNB.L

local BASE        = "Interface\\AddOns\\BigNoteBox\\Assets\\Fonts\\"

-- Language -> font set. A language not listed here uses the Latin set. Add a line
-- when a new CJK language ships (plus a SET_DEFAULT entry and its cards).
local LANG_SET    = { zhCN = "hans", zhTW = "hant" }
local SET_DEFAULT = { latin = "notoserif", hans = "wowhei", hant = "wowkai_tw" }
-- What a saved "wow" (WoW Default) choice means under a non-Latin set, where the
-- checkbox is hidden because the set's cards are WoW's own fonts already.
local SET_WOW_ALIAS = { hans = "wowkai", hant = "wowkai_tw" }
local GRID_MAX    = 8   -- 2x4 grid; ALL-39 makes it scroll for more

-- ── Font definitions ──────────────────────────────────────────────────────────
BNB.FONTS = {
    {
        id      = "notoserif",
        cyrillic = true, greek = true,   -- has the letters (checked in the TTF, ALL-619)
        label   = "Noto Serif",
        regular = BASE .. "NotoSerif-Regular.ttf",
        bold    = BASE .. "NotoSerif-Bold.ttf",
        mono    = false,
        preview = "Aa Bb Çç Ää Üü",
    },
    {
        id      = "ebgaramond",
        cyrillic = true, greek = true,   -- has the letters (checked in the TTF, ALL-619)
        label   = "EB Garamond",
        regular = BASE .. "EBGaramond-Regular.ttf",
        bold    = BASE .. "EBGaramond-Bold.ttf",
        mono    = false,
        preview = "Aa Bb Çç Ää Üü",
        -- Small x-height: drawn larger so a size setting looks the same as on the
        -- other cards (ALL-60). Cap height says 1.10, x-height 1.34.
        scale   = 1.2,
    },
    {
        id      = "notosans",
        cyrillic = true, greek = true,   -- has the letters (checked in the TTF, ALL-619)
        label   = "Noto Sans",
        regular = BASE .. "NotoSans-Regular.ttf",
        bold    = BASE .. "NotoSans-Bold.ttf",
        mono    = false,
        preview = "Aa Bb Çç Ää Üü",
    },
    {
        id      = "jetbrains",
        cyrillic = true, greek = true,   -- has the letters (checked in the TTF, ALL-619)
        label   = "JetBrains Mono",
        regular = BASE .. "JetBrainsMono-Regular.ttf",
        bold    = BASE .. "JetBrainsMono-Bold.ttf",
        mono    = true,
        preview = "Aa 0O Il {}[]",
    },
    {
        id      = "gloriahallelujah",
        label   = "Gloria Hallelujah",
        regular = BASE .. "GloriaHallelujah-Regular.ttf",
        bold    = BASE .. "GloriaHallelujah-Regular.ttf",  -- no bold variant
        mono    = false,
        preview = "Aa Bb Cc Dd Ee",
    },
    {
        id      = "opendyslexic",
        label   = "OpenDyslexic",
        regular = BASE .. "OpenDyslexic-Regular.ttf",
        bold    = BASE .. "OpenDyslexic-Regular.ttf",  -- no bold variant
        mono    = false,
        preview = "Aa Bb Cc Dd Ee",
    },
    {
        id      = "fredoka",
        label   = "Fredoka",
        regular = BASE .. "Fredoka-Regular.ttf",
        bold    = BASE .. "Fredoka-Bold.ttf",
        mono    = false,
        preview = "Aa Bb Cc Dd Ee",
    },
    {
        id      = "playwrite",
        label   = "Playwrite IE",
        regular = BASE .. "PlaywriteIE-Regular.ttf",
        bold    = BASE .. "PlaywriteIE-Regular.ttf",  -- no bold variant
        mono    = false,
        preview = "Aa Bb Cc Dd Ee",
    },
    {
        -- Uses WoW's locale-installed font, resolved at login via GameFontNormal:GetFont().
        -- On zhCN/zhTW/koKR/jaJP clients this resolves to a CJK-capable font.
        id      = "wow",
        label   = "WoW Default",
        regular = "Fonts\\FRIZQT__.TTF",   -- overwritten in InitFonts(); placeholder only
        bold    = "Fonts\\FRIZQT__.TTF",
        mono    = false,
        preview = "Aa Bb Cc Dd Ee",
        _isWoW  = true,
    },
    -- ── Simplified Chinese set ("hans") ─────────────────────────────────────────
    -- WoW's own installed Chinese fonts, so a Chinese user never gets boxes even
    -- without a font pack. 0 MB: every client ships them for the alphabet
    -- fallbacks. Preview reads "Chinese font Aa Bb".
    {
        id      = "wowhei",
        label   = L["FONT_WOW_HEI"],
        regular = "Fonts\\ARHei.ttf",
        bold    = "Fonts\\ARHei.ttf",
        mono    = false,
        preview = "\228\184\173\230\150\135\229\173\151\228\189\147 Aa Bb",
        set     = "hans",
    },
    {
        id      = "wowkai",
        label   = L["FONT_WOW_KAI"],
        regular = "Fonts\\ARKai_T.ttf",
        bold    = "Fonts\\ARKai_T.ttf",
        mono    = false,
        preview = "\228\184\173\230\150\135\229\173\151\228\189\147 Aa Bb",
        set     = "hans",
    },
    -- ── Traditional Chinese set ("hant") ────────────────────────────────────────
    -- Same WoW-installed font as zhCN's "wowkai" (ARKai_T.ttf serves both locales
    -- per FORCED_LOCALE_FONT above); a separate card id so it can carry its own
    -- SET_DEFAULT/SET_WOW_ALIAS entry independent of the hans set's.
    {
        id      = "wowkai_tw",
        label   = L["FONT_WOW_KAI"],
        regular = "Fonts\\ARKai_T.ttf",
        bold    = "Fonts\\ARKai_T.ttf",
        mono    = false,
        preview = "\228\184\173\230\150\135\229\173\151\233\171\148 Aa Bb",
        set     = "hant",
    },
}

-- Quick lookup by id
local _byID = {}
for _, def in ipairs(BNB.FONTS) do _byID[def.id] = def end

local function SetOf(def) return def.set or "latin" end

-- ── A font that can draw the note (ALL-619) ───────────────────────────────────
-- An edit box whose text holds a character its font file cannot draw stops
-- showing font, size and outline changes (Dukul, 2026-10-30: one Korean or
-- Chinese character in a note with a Latin font; 你 with a Chinese card was
-- fine). A font family did not help (no font object ever showed on these
-- boxes). So a note with Korean or Chinese text is drawn in a file that has
-- those letters: the chosen card when it can, else WoW's own file. The font
-- lists grey out the cards that cannot (BNB.FontBlockedFor).
-- Cyrillic: WoW's ARIALN (its game font family's Russian member); Greek: no
-- WoW file has it, so the bundled Noto Sans
local SCRIPT_FILE = { korean = "Fonts\\2002.TTF", chinese = "Fonts\\ARKai_T.ttf",
    cyrillic = "Fonts\\ARIALN.TTF", greek = BASE .. "NotoSans-Regular.ttf" }
-- Lower-case parts of file names that have the letters (WoW's own files; the
-- hans / hant cards are known by their set)
local SCRIPT_FILE_HINT = {
    korean  = { "2002", "k_damage", "k_pagetext" },
    chinese = { "arkai", "arhei", "arheiuhk", "blei" },
    cyrillic = { "arialn", "_cyr" },
}

-- The alphabets of two bytes in UTF-8 (Dukul, 2026-10-30): Cyrillic
-- U+0400-04FF (D0 80 - D3 BF), Greek U+0370-03FF (CD B0 - CF BF)
local function TwoByteScript(text)
    if text:find("[\208-\211][\128-\191]") then return "cyrillic" end
    if text:find("\205[\176-\191]") or text:find("[\206\207][\128-\191]") then return "greek" end
    return nil
end

-- "korean", "chinese" or nil for a note's text. UTF-8 lead bytes: Hangul
-- syllables EA B0 - ED 9E (U+AC00-D7A3), Jamo E1 84-87, compatibility Jamo
-- E3 84-86; CJK ideographs E4-E9 (U+4000-9FFF), extension A E3 90-BF, kana
-- E3 81-83, CJK punctuation E3 80, full-width forms EF BC / BD. Korean first:
-- a note with both gets the Korean file (Korean and Chinese together is the
-- known edge case, Dukul 2026-10-30).
function BNB.TextScript(text)
    if type(text) ~= "string" then return nil end
    if not text:find("[\225-\239]") then return TwoByteScript(text) end
    if text:find("[\234\235\236\237][\128-\191][\128-\191]")
       or text:find("\225[\132-\135]") or text:find("\227[\132-\134]") then
        return "korean"
    end
    if text:find("[\228-\233][\128-\191]") or text:find("\227[\128-\131\144-\191]")
       or text:find("\239[\188\189]") then
        return "chinese"
    end
    return TwoByteScript(text)
end

-- The language shield for a note's text (the editor's title row): "ko",
-- "ja" (kana, E3 81-83), "cn", "ua" (every Cyrillic text: Dukul, 2026-10-30,
-- the Ukrainian flag, not the Russian one) or "gr", else nil
function BNB.TextShield(text)
    local script = BNB.TextScript(text)
    if script == "korean" then return "ko" end
    if script == "cyrillic" then return "ua" end
    if script == "greek" then return "gr" end
    if not script then return nil end
    if text:find("\227[\129-\131]") then return "ja" end
    return "cn"
end

-- Can this card draw this script? def = a BNB.FONTS card
local function Covers(def, script)
    if not script then return true end
    if script == "chinese" and SetOf(def) ~= "latin" then return true end
    if def[script] then return true end   -- the card flags cyrillic / greek
    local file = (def._isWoW and BNB.GetLocaleFont and BNB.GetLocaleFont()) or def.regular or ""
    file = file:lower()
    for _, hint in ipairs(SCRIPT_FILE_HINT[script] or {}) do
        if file:find(hint, 1, true) then return true end
    end
    return false
end

-- The file to draw a note's text with: the card's own, or WoW's file for the
-- text's script when the card cannot draw it
function BNB.NoteFontFile(def, text)
    local script = BNB.TextScript(text)
    if Covers(def, script) then
        return (def._isWoW and BNB.GetLocaleFont and BNB.GetLocaleFont()) or def.regular
    end
    return SCRIPT_FILE[script]
end

-- nil when the card can draw the note's text, else the tooltip line that says
-- why its card is greyed out in a font list
function BNB.FontBlockedFor(def, text)
    local script = BNB.TextScript(text)
    if not def or Covers(def, script) then return nil end
    if script == "korean" then return L["FONT_BLOCKED_KOREAN"] end
    if script == "cyrillic" then return L["FONT_BLOCKED_CYRILLIC"] end
    if script == "greek" then return L["FONT_BLOCKED_GREEK"] end
    return L["FONT_BLOCKED_CHINESE"]
end

-- Calls reapply(text) when typing adds the first or takes away the last
-- Korean / Chinese character, so the box switches file without leaving the
-- note (Dukul, 2026-10-30). eb._bnbScript = the script its font was set for
-- (the font setters store it). One hook per box; a later call only swaps
-- the function (a new note in the same box).
function BNB.WatchTextScript(eb, reapply)
    if not eb then return end
    local hooked = eb._bnbScriptWatch ~= nil
    eb._bnbScriptWatch = reapply
    if hooked then return end
    local key = "TextScript" .. tostring(eb)
    eb:HookScript("OnTextChanged", function(self, user)
        if not user then return end
        BNB.Debounce(key, 0.25, function()
            local text = self:GetText() or ""
            if BNB.TextScript(text) ~= self._bnbScript and self._bnbScriptWatch then
                self._bnbScriptWatch(text)
            end
        end)
    end)
end

-- Greys out a font card in a list (Note Settings, sticky settings) after
-- PaintSelectCard: a card that cannot draw the note is dimmed
function BNB.DimFontCard(nameLbl, prevLbl, blocked)
    if blocked and nameLbl then nameLbl:SetTextColor(0.42, 0.42, 0.42) end
    if prevLbl then prevLbl:SetAlpha(blocked and 0.35 or 1) end
end

-- Keeps the box's layout fresh after a font, size, outline or colour change:
-- one pixel narrower for a frame, then back (Dukul's probe, 2026-10-30, on a
-- box with Korean in it). Once per frame however many changes came in; the
-- width is put back only if nothing else changed it meanwhile.
function BNB.RelayoutEditBox(eb)
    if not eb or eb._bnbRelayout then return end
    eb._bnbRelayout = true
    C_Timer.After(0, function()
        eb._bnbRelayout = nil
        local w = eb:GetWidth()
        if not w or w <= 1 then return end
        eb:SetWidth(w - 1)
        C_Timer.After(0, function()
            if math.abs((eb:GetWidth() or 0) - (w - 1)) < 0.01 then eb:SetWidth(w) end
        end)
    end)
end

-- Note outline names (Note Settings) -> font flags and drop shadow
local OUTLINE_FLAGS = {
    ["Outline"] = "OUTLINE", ["Thick Outline"] = "THICKOUTLINE",
    ["Monochrome Outline"] = "MONOCHROME,OUTLINE", ["SLUG"] = "SLUG",
    ["SLUG Outline"] = "OUTLINE, SLUG", ["SLUG Thick Outline"] = "THICKOUTLINE, SLUG",
}
local OUTLINE_SHADOW = {
    ["Drop Shadow"] = { 1, -1, 0, 0, 0, 0.8 }, ["Strong Drop Shadow"] = { 2, -2, 0, 0, 0, 1.0 },
    ["Strongest Drop Shadow"] = { 3, -3, 0, 0, 0, 1.0 },
}

-- A note's body font on an edit box (the main editor, Focus mode, ALL-619):
-- the note's font card (else the global one) or, for Korean / Chinese text
-- the card cannot draw, WoW's file (BNB.NoteFontFile); size (else the global
-- one) and, with withLook, its outline / shadow and alignment.
-- text (optional): what the box holds while typing (BNB.WatchTextScript),
-- else the saved body.
function BNB.ApplyNoteFont(eb, note, withLook, text)
    if not eb then return end
    text = text or (note and note.body)
    eb._bnbScript = BNB.TextScript(text)
    BNB.WatchTextScript(eb, function(t) BNB.ApplyNoteFont(eb, note, withLook, t) end)
    local db  = BigNoteBoxDB
    local def = BNB.ResolveFontDef(note and note.fontOverride)
    local sz  = (note and note.fontSize) or (db and db.fontSize) or BNB.DEFAULTS.fontSize
    local outline = withLook and note and note.fontOutline or "None"
    local flags, shadow = OUTLINE_FLAGS[outline] or "", OUTLINE_SHADOW[outline]
    -- The note's text, not the box's: the box may still hold the last note's
    local file = BNB.NoteFontFile(def, text)
    pcall(eb.SetFont, eb, file, BNB.FontPx(file, sz), flags)
    local sh = shadow or { 0, 0, 0, 0, 0, 0 }
    pcall(eb.SetShadowOffset, eb, sh[1], sh[2])
    pcall(eb.SetShadowColor, eb, sh[3], sh[4], sh[5], sh[6])
    if withLook then pcall(eb.SetJustifyH, eb, note and note.textAlign or "LEFT") end
    -- The title row's language shield follows the text (typing too)
    if eb == BNB._editorBody and BNB.RefreshEditorLangBadge then BNB.RefreshEditorLangBadge(text) end
    if eb == BNB._focusEditorBody and BNB.RefreshFocusLangBadge then BNB.RefreshFocusLangBadge(text) end
    BNB.RelayoutEditBox(eb)
end

-- The open note's fonts in the main editor: body through ApplyNoteFont (font,
-- size, outline, alignment), title in the card's bold file. Every place that
-- changes a note's font, size, outline or alignment calls this (note load,
-- Note Settings, the global font).
function BNB.ApplyEditorFonts()
    local id   = BNB._currentNoteID
    local note = id and BNB.GetNote(id)
    if BNB._editorBody then BNB.ApplyNoteFont(BNB._editorBody, note, true) end
    if BNB._editorTitle then
        local bold = BNB.ResolveFontDef(note and note.fontOverride).bold
        pcall(function() BNB._editorTitle:SetFont(bold, BNB.FontPx(bold, 20), "") end)
    end
end

-- ── Per-font size factor (ALL-60) ─────────────────────────────────────────────
-- A card may carry `scale`; every SetFont on note text passes its size through
-- BNB.FontPx(path, size), so the size settings mean the same visual size for
-- every font. Keyed by file path, so a size re-applied from GetFont() must NOT go
-- through it again (it is already scaled). Rebuilt when font packs add cards.
local _scaleByPath, _scaleCount = {}, -1
function BNB.FontPx(path, size)
    if not size then return size end
    if _scaleCount ~= #BNB.FONTS then
        _scaleByPath, _scaleCount = {}, #BNB.FONTS
        for _, def in ipairs(BNB.FONTS) do
            if def.scale then
                if def.regular then _scaleByPath[def.regular] = def.scale end
                if def.bold    then _scaleByPath[def.bold]    = def.scale end
            end
        end
    end
    local s = path and _scaleByPath[path]
    return s and size * s or size
end

-- ── Early preload (ALL-16) ────────────────────────────────────────────────────
-- The client loads a TTF lazily, when a FontString using it is first drawn. On a
-- cold first login SetFont still returns success before the file is ready, and the
-- string stays blank until its font is applied again; a /reload "fixes" it because
-- the file is cached by then. Draw every bundled TTF once, right away, on a
-- near-invisible 1px frame so the loads start before any picker is built. A hidden
-- frame is not enough - hidden strings are never drawn, so nothing loads.
-- Only the active set's fonts are preloaded (plus the Latin ones, which chrome may
-- use); font packs call this again for their own files when they register.
function BNB.GetActiveFontSet()
    local lang = (BNB.GetActiveLanguage and BNB.GetActiveLanguage()) or (GetLocale and GetLocale()) or ""
    return LANG_SET[lang] or "latin"
end

local function PreloadFonts(defs)
    return pcall(function()
        local pre = CreateFrame("Frame", nil, UIParent)
        pre:SetSize(1, 1)
        pre:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 0, 0)
        pre:SetAlpha(0.01)
        local seen = {}
        for _, def in ipairs(defs) do
            if not def._isWoW then
                for _, p in ipairs({ def.regular, def.bold }) do
                    if p and not seen[p] then
                        seen[p] = true
                        local fs = pre:CreateFontString(nil, "BACKGROUND")
                        fs:SetPoint("BOTTOMLEFT", pre, "BOTTOMLEFT", 0, 0)
                        fs:SetFont(p, 12, "")
                        fs:SetText(def.preview or "Aa")
                    end
                end
            end
        end
        pre:Show()
        C_Timer.After(10, function() pre:Hide() end)
    end)
end

do
    local active, list = BNB.GetActiveFontSet(), {}
    for _, def in ipairs(BNB.FONTS) do
        local s = SetOf(def)
        if s == "latin" or s == active then list[#list + 1] = def end
    end
    PreloadFonts(list)
end

-- Sets a TTF on a FontString and survives the not-yet-loaded case. SetFont's
-- return value cannot be trusted here (it reports success while the file is
-- still loading), so the font is re-applied - with a size nudge and a text
-- re-set to force a redraw - a few times after it is set, and again every time
-- the owning frame is shown. The fallback font object goes on first so a real
-- failure still leaves readable text. Used by every font picker.
local REFRESH_DELAYS = { 0.2, 1.0, 3.0 }

local function RefreshFont(fs)
    local spec = fs._bnbFontSpec
    if not spec then return end
    pcall(fs.SetFont, fs, spec.path, spec.size + 1, "")
    pcall(fs.SetFont, fs, spec.path, spec.size, "")
    local t = fs:GetText() or ""
    fs:SetText("")
    fs:SetText(t)
end

local function ScheduleRefresh(fs)
    for _, d in ipairs(REFRESH_DELAYS) do
        C_Timer.After(d, function() RefreshFont(fs) end)
    end
end

function BNB.SetFontSafe(fs, path, size, fallbackObj)
    if not fs then return end
    fs:SetFontObject(fallbackObj or "BNBFontNormal")
    if not path or path == "" then fs._bnbFontSpec = nil; return end
    size = BNB.FontPx(path, size)
    fs._bnbFontSpec = { path = path, size = size }
    pcall(fs.SetFont, fs, path, size, "")
    ScheduleRefresh(fs)
    -- Refresh again whenever the owner is shown: picker pages are often built
    -- hidden, so the timers above can run out before the text is ever drawn.
    local owner = fs:GetParent()
    if owner and owner.HookScript then
        if not owner._bnbFontStrings then
            owner._bnbFontStrings = {}
            owner:HookScript("OnShow", function(self)
                for _, f in ipairs(self._bnbFontStrings) do ScheduleRefresh(f) end
            end)
        end
        local list, known = owner._bnbFontStrings, false
        for _, f in ipairs(list) do if f == fs then known = true break end end
        if not known then list[#list + 1] = fs end
    end
end

local function GetWoWFontPath()
    local ok, path = pcall(function() return GameFontNormal:GetFont() end)
    return (ok and path and path ~= "") and path or "Fonts\\FRIZQT__.TTF"
end

-- WoW's own font for the ACTIVE language. When the language is the client's own,
-- GameFontNormal already has the right file. When a language is forced, GetFont()
-- still reports the client's Latin file (FRIZQT on an English client) even though
-- font objects fall back per alphabet, so a raw SetFont with it draws boxes; the
-- forced language's file is named here instead, as BigChatBox does.
local FORCED_LOCALE_FONT = {
    zhCN = "Fonts\\ARKai_T.ttf", zhTW = "Fonts\\ARKai_T.ttf",
    jaJP = "Fonts\\ARKai_T.ttf", koKR = "Fonts\\2002.ttf",
}
local function LocaleFontPath()
    local lang = BNB.GetActiveLanguage and BNB.GetActiveLanguage()
    if lang and GetLocale and lang ~= GetLocale() and FORCED_LOCALE_FONT[lang] then
        return FORCED_LOCALE_FONT[lang]
    end
    return GetWoWFontPath()
end

-- WoW's own chrome font for the active language: FRIZQT on an English client, the
-- client's CJK font on a CJK client, the forced language's file when forced. For
-- translated text that must stay in WoW's look (big Blizzard-template buttons)
-- but needs a raw SetFont for its size. Never hardcode FRIZQT for such text: it has
-- no CJK glyphs, and a raw SetFont drops the font objects' per-alphabet fallback.
function BNB.GetLocaleFont() return LocaleFontPath() end

function BNB.GetFontDef(id)
    -- _byID keys are font id strings for bundled fonts and raw .ttf paths for LSM fonts.
    -- Identity lookup only; anything that draws text uses ResolveFontDef instead.
    return _byID[id] or _byID["notoserif"]
end

-- ── Set resolution (ALL-14) ───────────────────────────────────────────────────
function BNB.GetFontSetDefault()
    return SET_DEFAULT[BNB.GetActiveFontSet()] or "notoserif"
end

-- The stored pick for the active set. The Latin set keeps using fontChoice; other
-- sets live in fontChoiceBySet[set] and, until one is picked, inherit fontChoice
-- so an existing WoW Default or LSM pick carries over (a Latin card does not
-- resolve under them and falls to the set default).
function BNB.GetFontChoice()
    local db = BigNoteBoxDB
    if not db then return nil end
    local set = BNB.GetActiveFontSet()
    if set == "latin" then return db.fontChoice end
    local t = db.fontChoiceBySet
    return (t and t[set]) or db.fontChoice
end

-- id if it can be drawn under the active set, else nil. LSM fonts follow the user
-- across sets; "wow" maps to the set's own WoW font where the checkbox is hidden.
function BNB.ResolveFontID(id)
    local def = id and _byID[id]
    if not def then return nil end
    if def._isLSM then return id end
    local set = BNB.GetActiveFontSet()
    if def._isWoW then
        if set == "latin" then return id end
        return SET_WOW_ALIAS[set]
    end
    if SetOf(def) == set then return id end
    return nil
end

function BNB.GetEffectiveFontID()
    return BNB.ResolveFontID(BNB.GetFontChoice()) or BNB.GetFontSetDefault()
end

-- Def to draw for a per-note / per-sticky override: the override if usable, else
-- the global effective font (the same as having no override).
function BNB.ResolveFontDef(id)
    local rid = BNB.ResolveFontID(id) or BNB.GetEffectiveFontID()
    return _byID[rid] or _byID["notoserif"]
end

-- Cards for the active set, in list order, capped to the 2x4 grid. withLSM
-- appends LSM fonts after them, for the two pickers that show LSM as cards.
function BNB.GetPickerFonts(withLSM)
    local set, out, lsm = BNB.GetActiveFontSet(), {}, {}
    for _, def in ipairs(BNB.FONTS) do
        if def._isLSM then
            lsm[#lsm + 1] = def
        elseif not def._isWoW and SetOf(def) == set and #out < GRID_MAX then
            out[#out + 1] = def
        end
    end
    if withLSM then
        for _, def in ipairs(lsm) do out[#out + 1] = def end
    end
    return out
end

-- Rows the card grid always reserves, so a set with fewer cards keeps the layout.
BNB.FONT_GRID_ROWS = GRID_MAX / 2

-- The WoW Default checkbox only exists under the Latin set.
function BNB.ShowWoWFontCheckbox()
    return BNB.GetActiveFontSet() == "latin"
end

-- ── Getters ───────────────────────────────────────────────────────────────────
-- A stored choice that no longer exists (LSM font gone, pack uninstalled) or that
-- belongs to another set is drawn as the set default, but never written back.
function BNB.GetBodyFont()
    local db  = BigNoteBoxDB
    local def = _byID[BNB.GetEffectiveFontID()] or _byID["notoserif"]
    local sz  = (db and db.fontSize) or BNB.DEFAULTS.fontSize
    return def.regular, sz
end

function BNB.GetBoldFont()
    local def = _byID[BNB.GetEffectiveFontID()] or _byID["notoserif"]
    return def.bold
end

-- ── UI chrome fonts (ALL-22) ──────────────────────────────────────────────────
-- Buttons, the welcome greeting and other interface text show translated strings,
-- so they must be able to draw the client's script. None of the bundled TTFs carry
-- CJK glyphs: on a zhCN/zhTW/koKR client they render every label as boxes. There,
-- chrome falls back to WoW's own locale font unless the user picked WoW Default or
-- an LSM font (which may well be CJK-capable). Note text keeps the chosen font.
function BNB.IsCJKClient()
    local locale = BNB.GetActiveLanguage and BNB.GetActiveLanguage() or (GetLocale and GetLocale()) or ""
    return locale == "zhCN" or locale == "zhTW" or locale == "koKR"
end

-- Returns (regular, bold). The WoW font is read live rather than from the "wow"
-- def, whose paths are a Latin placeholder until InitFonts has run. A card from a
-- non-Latin set (WoW Hei, a pack font) draws that set's script, so chrome uses it.
local function ChromePaths()
    local def = _byID[BNB.GetEffectiveFontID()] or _byID["notoserif"]
    if def._isLSM or (SetOf(def) ~= "latin" and not def._isWoW) then
        return def.regular, def.bold
    end
    if def._isWoW or BNB.IsCJKClient() then
        local p = LocaleFontPath()
        return p, p
    end
    return def.regular, def.bold
end

function BNB.GetUIFont()     return (ChromePaths()) end
function BNB.GetUIBoldFont() return select(2, ChromePaths()) end

-- ── Deferred font setup ───────────────────────────────────────────────────────
-- Called from Initialize.lua AFTER PLAYER_LOGIN.  Safe to call multiple times
-- (guarded). It used to create 16 BNB_Body* / BNB_Title* font objects that
-- nothing read; creating a font object loads nothing (PreloadFonts above does
-- that by drawing strings), so they went in batch 11 (DEAD-02).
function BNB.InitFonts()
    if BNB._fontsInitialised then return end
    BNB._fontsInitialised = true

    -- ── WoW Default font path resolution ────────────────────────────────────────
    -- GameFontNormal:GetFont() returns the locale-appropriate path installed by WoW.
    -- On zhCN/zhTW/koKR/jaJP this is a CJK-capable font; on English it is FRIZQT__.
    -- A forced CJK language gets that language's file instead (LocaleFontPath).
    local wowDef = _byID["wow"]
    if wowDef then
        local resolved = LocaleFontPath()
        wowDef.regular = resolved
        wowDef.bold    = resolved
    end

    -- ── LibSharedMedia font registration ────────────────────────────────────────
    -- Only runs if the user has opted in via Advanced tab (db.lsmFonts = true).
    -- Appends LSM font defs to BNB.FONTS and _byID so all pickers see them.
    -- Uses the raw .ttf path as the id since LSM names are not guaranteed unique.
    -- Bundled fonts that appear in LSM by path are skipped to avoid duplicates.
    local db = BigNoteBoxDB
    if db and db.lsmFonts then
        local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
        if LSM then
            -- Build a set of paths already covered by bundled fonts
            local bundledPaths = {}
            for _, def in ipairs(BNB.FONTS) do
                if def.regular then bundledPaths[def.regular:lower()] = true end
                if def.bold    then bundledPaths[def.bold:lower()]    = true end
            end
            local names = LSM:List("font") or {}
            table.sort(names)  -- alphabetical for consistent ordering
            for _, name in ipairs(names) do
                local path = LSM:Fetch("font", name)
                if path and not bundledPaths[path:lower()] then
                    local lsmDef = {
                        id      = path,       -- raw path used as unique key
                        label   = name,
                        regular = path,
                        bold    = path,       -- LSM has no bold variant; use same path
                        mono    = false,
                        preview = "Aa Bb Cc Dd Ee",
                        _isLSM  = true,
                    }
                    BNB.FONTS[#BNB.FONTS + 1] = lsmDef
                    _byID[path] = lsmDef
                    bundledPaths[path:lower()] = true  -- guard against LSM duplicates
                end
            end
        end
    end
end

-- ── Apply font to all live editor widgets ─────────────────────────────────────
-- id   — font id string (nil = keep current choice)
-- size — font size in points (nil = keep current size)
function BNB.ApplyFont(id, size)
    local db = BigNoteBoxDB
    if not db then return end
    if id then
        -- Each set keeps its own pick (ALL-14); the Latin set is fontChoice.
        local set = BNB.GetActiveFontSet()
        if set == "latin" then
            db.fontChoice = id
        else
            db.fontChoiceBySet = db.fontChoiceBySet or {}
            db.fontChoiceBySet[set] = id
        end
    end
    if size then db.fontSize   = size end

    -- The open note keeps its own font, size and outline (this used to put the
    -- global font over them until the note was opened again)
    BNB.ApplyEditorFonts()
    -- Each sticky keeps its own font, size and outline; one without its own
    -- follows the new global font (ALL-620: this used to reset them all)
    if BNB.Sticky and BNB.Sticky.ApplyBodyFonts then pcall(BNB.Sticky.ApplyBodyFonts) end
    if BNB.RefreshFocusFont then BNB.RefreshFocusFont() end
    -- Interface text that follows the font choice (ALL-25)
    if BNB.SendMessage then BNB.SendMessage("UIFontChanged") end
end

-- ── Font packs (ALL-14) ───────────────────────────────────────────────────────
-- A font pack is a separate addon (## Dependencies: BigNoteBox) that calls this at
-- load time, before InitFonts runs on PLAYER_LOGIN:
--
--   BigNoteBox.RegisterFontPack({
--       id      = "fontscn",              -- matches its BNB.KNOWN_PACKS entry
--       addon   = "BigNoteBox_FontsCN",   -- folder name, for the version lookup
--       version = "1.0.0",                -- optional; read from the TOC if absent
--       set     = "hans",                 -- which card set the fonts join
--       fonts   = {
--           { id = "notosanssc", label = "Noto Sans SC",
--             regular = "Interface\\AddOns\\BigNoteBox_FontsCN\\Fonts\\NotoSansSC-Regular.ttf",
--             bold    = "Interface\\AddOns\\BigNoteBox_FontsCN\\Fonts\\NotoSansSC-Bold.ttf",
--             preview = "..." },
--       },
--   })
--
-- Font ids must be unique across BNB; a clashing id is skipped. Cards past the
-- 2x4 grid are kept (menus and saved choices still see them) but not drawn as
-- cards until ALL-39 makes the grid scroll. Returns true when the pack was taken.
BNB._fontPacks = BNB._fontPacks or {}

local function AddOnVersion(addon)
    if addon and C_AddOns and C_AddOns.GetAddOnMetadata then
        local ok, v = pcall(C_AddOns.GetAddOnMetadata, addon, "Version")
        if ok and v and v ~= "" then return v end
    end
    return nil
end

function BNB.RegisterFontPack(pack)
    if type(pack) ~= "table" or type(pack.id) ~= "string" or type(pack.fonts) ~= "table" then
        return false
    end
    local set = pack.set or "latin"
    if not SET_DEFAULT[set] then return false end

    local added = {}
    for _, f in ipairs(pack.fonts) do
        if type(f) == "table" and type(f.id) == "string" and type(f.regular) == "string"
           and not _byID[f.id] then
            local def = {
                id      = f.id,
                label   = f.label or f.id,
                regular = f.regular,
                bold    = f.bold or f.regular,
                mono    = f.mono and true or false,
                preview = f.preview or "Aa Bb Cc Dd Ee",
                set     = set,
                _pack   = pack.id,
            }
            -- Keep pack cards ahead of any LSM entries InitFonts may already have added.
            local pos = #BNB.FONTS + 1
            for i, d in ipairs(BNB.FONTS) do
                if d._isLSM then pos = i; break end
            end
            table.insert(BNB.FONTS, pos, def)
            _byID[f.id] = def
            added[#added + 1] = def
        end
    end

    BNB._fontPacks[pack.id] = {
        id      = pack.id,
        addon   = pack.addon,
        version = pack.version or AddOnVersion(pack.addon),
        set     = set,
        count   = #added,
    }
    if set == BNB.GetActiveFontSet() and #added > 0 then PreloadFonts(added) end
    return true
end

-- ── Known packs ───────────────────────────────────────────────────────────────
-- Every pack BNB knows about, for the status icons on the General tab and the
-- empty-grid hint. The icon pack (ALL-40) joins this list when it ships; if the
-- list grows past fonts it can move to its own file.
-- Tooltip text is in the PACK's language whatever the UI language is, so it is
-- data here, not locale keys. English meaning of the zhCN lines:
--   "BigNoteBox Chinese font pack"
--   "Install it to get more Chinese fonts and the full Chinese experience."
--   "Click to copy the CurseForge download link."
--   "Installed, v%s"
BNB.KNOWN_PACKS = {
    {
        id       = "fontscn",
        addon    = "BigNoteBox_FontsCN",
        set      = "hans",
        langs    = { zhCN = true },   -- a missing pack shows only for these languages
        icon     = "Interface\\AddOns\\BigNoteBox\\Assets\\Flags\\shield-cn",   -- Dukul's shield (2026-10-03)
        -- iconCrop = true: trim a Blizzard icon's built-in border (our own art is drawn whole)
        url      = "https://www.curseforge.com/wow/addons/bignotebox-fonts-cn",
        hintKey  = "FONT_PACK_HINT_HANS",
        tipTitle     = "BigNoteBox \228\184\173\230\150\135\229\173\151\228\189\147\229\140\133",
        tipMissing   = "\229\174\137\232\163\133\229\144\142\229\143\175\228\189\191\231\148\168\230\155\180\229\164\154\228\184\173\230\150\135\229\173\151\228\189\147\239\188\140\232\142\183\229\190\151\229\174\140\230\149\180\231\154\132\228\184\173\230\150\135\228\189\147\233\170\140\227\128\130",
        tipClick     = "\231\130\185\229\135\187\229\164\141\229\136\182 CurseForge \228\184\139\232\189\189\233\147\190\230\142\165\227\128\130",
        tipInstalled = "\229\183\178\229\174\137\232\163\133\239\188\140v%s",
    },
}

local function IsAddOnLoadedSafe(name)
    return name ~= nil and C_AddOns.IsAddOnLoaded(name) and true or false
end

-- Returns installed (bool), version (string or nil).
function BNB.GetPackStatus(pack)
    local reg = BNB._fontPacks[pack.id]
    local installed = reg ~= nil or IsAddOnLoadedSafe(pack.addon)
    if not installed then return false, nil end
    return true, (reg and reg.version) or AddOnVersion(pack.addon)
end

-- Installed packs always show; a missing one only when its language is the active
-- or the client language (packs without langs always show).
function BNB.IsPackRelevant(pack)
    if BNB.GetPackStatus(pack) then return true end
    if not pack.langs then return true end
    local active = BNB.GetActiveLanguage and BNB.GetActiveLanguage()
    local client = GetLocale and GetLocale()
    return (active and pack.langs[active]) or (client and pack.langs[client]) or false
end

-- Empty-grid hint: under a non-Latin set with no pack fonts installed, the grid
-- has free rows, so they carry a line saying a pack exists. Clicking it copies the
-- download link. x/y are offsets from anchor's TOPLEFT to the first free row.
-- Returns the hint button, or nil when there is nothing to say.
function BNB.AddFontPackHint(parent, anchor, x, y, w, h, fontObj)
    local set = BNB.GetActiveFontSet()
    if set == "latin" or h < 14 then return nil end
    for _, def in ipairs(BNB.FONTS) do
        if def._pack and SetOf(def) == set then return nil end
    end
    local pack
    for _, p in ipairs(BNB.KNOWN_PACKS) do
        if p.set == set then pack = p; break end
    end
    if not pack then return nil end

    local btn = CreateFrame("Button", nil, parent)
    btn:SetPoint("TOPLEFT", anchor, "TOPLEFT", x, y)
    btn:SetSize(w, h)
    local fs = btn:CreateFontString(nil, "OVERLAY", fontObj or "BNBFontNormalSmall")
    fs:SetPoint("TOPLEFT",  btn, "TOPLEFT",  4, -4)
    fs:SetPoint("TOPRIGHT", btn, "TOPRIGHT", -4, -4)
    fs:SetJustifyH("LEFT"); fs:SetJustifyV("TOP")
    fs:SetTextColor(0.65, 0.65, 0.65)
    fs:SetText(L[pack.hintKey])
    btn:SetScript("OnEnter", function() BNB.SetHeaderColor(fs) end)
    btn:SetScript("OnLeave", function() fs:SetTextColor(0.65, 0.65, 0.65) end)
    btn:SetScript("OnClick", function(self)
        if BNB.ShowClipboardHint then BNB.ShowClipboardHint(pack.url, self, true, true) end
    end)
    return btn
end

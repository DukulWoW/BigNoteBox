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
local DEFAULT_SIZE = 13

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
        label   = "Noto Serif",
        regular = BASE .. "NotoSerif-Regular.ttf",
        bold    = BASE .. "NotoSerif-Bold.ttf",
        mono    = false,
        preview = "Aa Bb Çç Ää Üü",
    },
    {
        id      = "ebgaramond",
        label   = "EB Garamond",
        regular = BASE .. "EBGaramond-Regular.ttf",
        bold    = BASE .. "EBGaramond-Bold.ttf",
        mono    = false,
        preview = "Aa Bb Çç Ää Üü",
    },
    {
        id      = "notosans",
        label   = "Noto Sans",
        regular = BASE .. "NotoSans-Regular.ttf",
        bold    = BASE .. "NotoSans-Bold.ttf",
        mono    = false,
        preview = "Aa Bb Çç Ää Üü",
    },
    {
        id      = "jetbrains",
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
    BNB._fontPreloadOK = PreloadFonts(list)
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
    fs:SetFontObject(fallbackObj or "GameFontNormal")
    if not path or path == "" then fs._bnbFontSpec = nil; return end
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
    local sz  = (db and db.fontSize) or DEFAULT_SIZE
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

-- ── Deferred font object creation ─────────────────────────────────────────────
-- Called from Initialize.lua AFTER PLAYER_LOGIN so WoW's font renderer has
-- finished loading the .ttf files.  Safe to call multiple times (guarded).
function BNB.InitFonts()
    if BNB._fontsInitialised then return end
    BNB._fontsInitialised = true

    local function Make(name, path, size)
        local ok, obj = pcall(function()
            local f = CreateFont(name)
            f:SetFont(path, size, "")
            return f
        end)
        return ok and obj or nil
    end

    BNB.FontBodyNotoSerif   = Make("BNB_BodyNotoSerif",   BASE.."NotoSerif-Regular.ttf",    DEFAULT_SIZE)
    BNB.FontTitleNotoSerif  = Make("BNB_TitleNotoSerif",  BASE.."NotoSerif-Bold.ttf",        20)
    BNB.FontBodyEBGaramond  = Make("BNB_BodyEBGaramond",  BASE.."EBGaramond-Regular.ttf",   DEFAULT_SIZE)
    BNB.FontTitleEBGaramond = Make("BNB_TitleEBGaramond", BASE.."EBGaramond-Bold.ttf",       20)
    BNB.FontBodyNotoSans    = Make("BNB_BodyNotoSans",    BASE.."NotoSans-Regular.ttf",      DEFAULT_SIZE)
    BNB.FontTitleNotoSans   = Make("BNB_TitleNotoSans",   BASE.."NotoSans-Bold.ttf",         20)
    BNB.FontBodyJetBrains   = Make("BNB_BodyJetBrains",  BASE.."JetBrainsMono-Regular.ttf", DEFAULT_SIZE)
    BNB.FontTitleJetBrains  = Make("BNB_TitleJetBrains", BASE.."JetBrainsMono-Bold.ttf",    20)
    BNB.FontBodyGloria      = Make("BNB_BodyGloria",      BASE.."GloriaHallelujah-Regular.ttf", DEFAULT_SIZE)
    BNB.FontTitleGloria     = Make("BNB_TitleGloria",     BASE.."GloriaHallelujah-Regular.ttf", 20)
    BNB.FontBodyDyslexic    = Make("BNB_BodyDyslexic",    BASE.."OpenDyslexic-Regular.ttf",     DEFAULT_SIZE)
    BNB.FontTitleDyslexic   = Make("BNB_TitleDyslexic",   BASE.."OpenDyslexic-Regular.ttf",     20)
    BNB.FontBodyFredoka     = Make("BNB_BodyFredoka",     BASE.."Fredoka-Regular.ttf",           DEFAULT_SIZE)
    BNB.FontTitleFredoka    = Make("BNB_TitleFredoka",    BASE.."Fredoka-Bold.ttf",              20)
    BNB.FontBodyPlaywrite   = Make("BNB_BodyPlaywrite",   BASE.."PlaywriteIE-Regular.ttf",       DEFAULT_SIZE)
    BNB.FontTitlePlaywrite  = Make("BNB_TitlePlaywrite",  BASE.."PlaywriteIE-Regular.ttf",       20)

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

    local def      = _byID[BNB.GetEffectiveFontID()] or _byID["notoserif"]
    local sz       = db.fontSize or DEFAULT_SIZE
    local bodyPath = def.regular
    local boldPath = def.bold

    if BNB._editorBody then
        pcall(function() BNB._editorBody:SetFont(bodyPath, sz, "") end)
    end
    if BNB._editorTitle then
        pcall(function() BNB._editorTitle:SetFont(boldPath, 20, "") end)
    end
    if BNB._stickyFrames then
        for _, pi in pairs(BNB._stickyFrames) do
            if pi._bodyEb then
                pcall(function() pi._bodyEb:SetFont(bodyPath, sz, "") end)
            end
        end
    end
    if BNB.RefreshFocusFont then BNB.RefreshFocusFont() end
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
        icon     = "Interface\\Icons\\INV_Misc_Book_09",   -- placeholder until Kim draws one
        url      = "https://www.curseforge.com/wow/addons/bignotebox-fonts-cn",
        hintKey  = "FONT_PACK_HINT_HANS",
        tipTitle     = "BigNoteBox \228\184\173\230\150\135\229\173\151\228\189\147\229\140\133",
        tipMissing   = "\229\174\137\232\163\133\229\144\142\229\143\175\228\189\191\231\148\168\230\155\180\229\164\154\228\184\173\230\150\135\229\173\151\228\189\147\239\188\140\232\142\183\229\190\151\229\174\140\230\149\180\231\154\132\228\184\173\230\150\135\228\189\147\233\170\140\227\128\130",
        tipClick     = "\231\130\185\229\135\187\229\164\141\229\136\182 CurseForge \228\184\139\232\189\189\233\147\190\230\142\165\227\128\130",
        tipInstalled = "\229\183\178\229\174\137\232\163\133\239\188\140v%s",
    },
}

local function IsAddOnLoadedSafe(name)
    if not name then return false end
    if C_AddOns and C_AddOns.IsAddOnLoaded then
        return C_AddOns.IsAddOnLoaded(name) and true or false
    end
    return IsAddOnLoaded and IsAddOnLoaded(name) and true or false
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
    local fs = btn:CreateFontString(nil, "OVERLAY", fontObj or "GameFontNormalSmall")
    fs:SetPoint("TOPLEFT",  btn, "TOPLEFT",  4, -4)
    fs:SetPoint("TOPRIGHT", btn, "TOPRIGHT", -4, -4)
    fs:SetJustifyH("LEFT"); fs:SetJustifyV("TOP")
    fs:SetTextColor(0.65, 0.65, 0.65)
    fs:SetText(L[pack.hintKey])
    btn:SetScript("OnEnter", function() fs:SetTextColor(1, 0.82, 0) end)
    btn:SetScript("OnLeave", function() fs:SetTextColor(0.65, 0.65, 0.65) end)
    btn:SetScript("OnClick", function(self)
        if BNB.ShowClipboardHint then BNB.ShowClipboardHint(pack.url, self, true) end
    end)
    return btn
end

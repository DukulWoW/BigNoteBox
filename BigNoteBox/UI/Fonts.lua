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

local BNB = BigNoteBox

local BASE        = "Interface\\AddOns\\BigNoteBox\\Assets\\Fonts\\"
local DEFAULT_SIZE = 13

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
}

-- Quick lookup by id
local _byID = {}
for _, def in ipairs(BNB.FONTS) do _byID[def.id] = def end

-- ── Early preload (ALL-16) ────────────────────────────────────────────────────
-- The client loads a TTF lazily, when a FontString using it is first drawn. On a
-- cold first login SetFont still returns success before the file is ready, and the
-- string stays blank until its font is applied again; a /reload "fixes" it because
-- the file is cached by then. Draw every bundled TTF once, right away, on a
-- near-invisible 1px frame so the loads start before any picker is built. A hidden
-- frame is not enough - hidden strings are never drawn, so nothing loads.
do
    local ok = pcall(function()
        local pre = CreateFrame("Frame", nil, UIParent)
        pre:SetSize(1, 1)
        pre:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 0, 0)
        pre:SetAlpha(0.01)
        local seen = {}
        for _, def in ipairs(BNB.FONTS) do
            if not def._isWoW then
                for _, p in ipairs({ def.regular, def.bold }) do
                    if p and not seen[p] then
                        seen[p] = true
                        local fs = pre:CreateFontString(nil, "BACKGROUND")
                        fs:SetPoint("BOTTOMLEFT", pre, "BOTTOMLEFT", 0, 0)
                        fs:SetFont(p, 12, "")
                        fs:SetText("Aa")
                    end
                end
            end
        end
        pre:Show()
        C_Timer.After(10, function() pre:Hide() end)
    end)
    BNB._fontPreloadOK = ok
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

function BNB.GetFontDef(id)
    -- _byID keys are font id strings for bundled fonts and raw .ttf paths for LSM fonts.
    return _byID[id] or _byID["notoserif"]
end

-- ── Getters ───────────────────────────────────────────────────────────────────
function BNB.GetBodyFont()
    local db  = BigNoteBoxDB
    local choice = db and db.fontChoice or "notoserif"
    -- If the stored choice is no longer in _byID the LSM font is gone (addon uninstalled
    -- or setting disabled). Reset to the default so the editor doesn't go fontless.
    if not _byID[choice] then
        if db then db.fontChoice = "notoserif" end
        choice = "notoserif"
    end
    local def = BNB.GetFontDef(choice)
    local sz  = (db and db.fontSize) or DEFAULT_SIZE
    return def.regular, sz
end

function BNB.GetBoldFont()
    local db  = BigNoteBoxDB
    local choice = db and db.fontChoice or "notoserif"
    if not _byID[choice] then choice = "notoserif" end
    local def = BNB.GetFontDef(choice)
    return def.bold
end

-- ── UI chrome fonts (ALL-22) ──────────────────────────────────────────────────
-- Buttons, the welcome greeting and other interface text show translated strings,
-- so they must be able to draw the client's script. None of the bundled TTFs carry
-- CJK glyphs: on a zhCN/zhTW/koKR client they render every label as boxes. There,
-- chrome falls back to WoW's own locale font unless the user picked WoW Default or
-- an LSM font (which may well be CJK-capable). Note text keeps the chosen font.
function BNB.IsCJKClient()
    local locale = GetLocale and GetLocale() or ""
    return locale == "zhCN" or locale == "zhTW" or locale == "koKR"
end

-- Returns (regular, bold). The WoW font is read live rather than from the "wow"
-- def, whose paths are a Latin placeholder until InitFonts has run.
local function ChromePaths()
    local db  = BigNoteBoxDB
    local def = BNB.GetFontDef(db and db.fontChoice or "notoserif")
    if def._isWoW or (BNB.IsCJKClient() and not def._isLSM) then
        local p = GetWoWFontPath()
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
    local wowDef = _byID["wow"]
    if wowDef then
        local resolved = GetWoWFontPath()
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
    if id   then db.fontChoice = id   end
    if size then db.fontSize   = size end

    local def      = BNB.GetFontDef(db.fontChoice)
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

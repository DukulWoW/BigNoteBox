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
}

-- Quick lookup by id
local _byID = {}
for _, def in ipairs(BNB.FONTS) do _byID[def.id] = def end

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

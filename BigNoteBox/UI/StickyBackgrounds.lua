-- BigNoteBox UI/StickyBackgrounds.lua
-- The sticky background registry (ALL-110). Drawn by BNB.BgLayer
-- (UI/BgLayer.lua); picked in sticky settings (UI/StickySettings.lua).
--
-- An entry: { key, label, cat, file, mode, anchor, scale, w, h }.
--   key    saved in the sticky's cfg.bgTexture; never rename one
--   label  shown name (an L key, resolved here)
--   cat    picker tab: stone | parchment | scenery | profession | classic
--   file   game file ID, or an addon path; w / h = its native size
-- "none" is always first (plain colour).
--
-- The game backgrounds come from the Background Lab (UI/BackgroundLab.lua,
-- /bnb bglab), Dukul 2026-09-27; its Export is the source for new lines here.
-- The old bundled TGAs live in the load-on-demand addon BigNoteBox_BGs, which
-- adds them with BigNoteBox.RegisterStickyBackgrounds when it loads. It is
-- loaded lazily: the first time a sticky asks for a key that is not here yet,
-- or when sticky settings open. A missing or disabled BigNoteBox_BGs means
-- those stickies draw plain colour; the saved key is never rewritten.

local BNB = BigNoteBox
local L   = BNB.L

local SBG = {}
BNB.StickyBG = SBG

local BGS_ADDON = "BigNoteBox_BGs"

local function E(key, label, cat, file, w, h, mode, anchor, scale)
    return { key = key, label = label, cat = cat, file = file, w = w, h = h,
             mode = mode, anchor = anchor, scale = scale or 1 }
end

-- Labels are L key names here; resolved to text below
local LIST = {
    { key = "none", label = "STICKY_BG_NONE" },
    -- Stone & Wood
    E("uicommonbackgrounds",               "STICKY_BG_BROWN_STONE",       "stone", 8198947,  256,  256, "tile",    "TOPLEFT"),
    E("bankframebackgroundc60",            "STICKY_BG_DARK_USED_STONE",   "stone", 8118796,  256,  256, "tile",    "TOPLEFT"),
    E("creditsscreenbackground0wowc60",    "STICKY_BG_RED_CEMENT",        "stone", 7976009,  256,  256, "tile",    "TOPLEFT"),
    E("gamepadmapbackgroundtile",          "STICKY_BG_REDDISH_WOOD",      "stone", 7163692,  512,  512, "tile",    "TOPLEFT"),
    E("uiframethewarwithinbackground",     "STICKY_BG_DARK_CONCRETE",     "stone", 5874260,  256,  256, "tile",    "TOPLEFT"),
    E("bankframebackground",               "STICKY_BG_RUINS",             "stone", 5782252,  256,  256, "tile",    "TOPLEFT"),
    E("glueannouncementpopupbackground",   "STICKY_BG_CUT_WOOD",          "stone", 3775278,  512,  512, "tile",    "TOPLEFT"),
    E("uiframeventhyrbackground",          "STICKY_BG_DARK_SCALES",       "stone", 3634718,  256,  256, "tile",    "TOPLEFT"),
    E("uiframekyrianbackground",           "STICKY_BG_CRACKED_KYRIAN",    "stone", 3550882,  256,  256, "tile",    "TOPLEFT"),
    E("uiframeoribosbackground",           "STICKY_BG_DARK_ORIBOS_STONE", "stone", 3507722,  256,  256, "tile",    "TOPLEFT"),
    E("uiframemechagonbackground",         "STICKY_BG_METAL_GRATE",       "stone", 3025300,  256,  256, "tile",    "TOPLEFT"),
    E("uiframemarinebackground",           "STICKY_BG_DIRT_GROUND",       "stone", 2921659,  256,  256, "tile",    "TOPLEFT"),
    E("ui-background-testwatermarkbackground", "STICKY_BG_WATER",         "stone", 2447133,  256,  256, "tile",    "TOPLEFT"),
    E("uiframeneutralbackground",          "STICKY_BG_WOOD_PLANKS",       "stone", 2142322,  256,  256, "tile",    "TOPLEFT"),
    E("uiframealliancebackground",         "STICKY_BG_DARK_COBBLESTONE",  "stone", 2142253,  256,  256, "tile",    "TOPLEFT"),
    E("classhallbackground",               "STICKY_BG_SCUFFED_WALLS",     "stone", 1450462,  256,  256, "tile",    "TOPLEFT"),
    E("journeysframebackground2x",         "STICKY_BG_CONCRETE_PATH",     "stone", 7486949,  256,  256, "cover",   "TOPLEFT", 1.4),
    E("file609607",                        "STICKY_BG_DARK_RUINS",        "stone", 609607,  1024,  512, "tile",    "TOPLEFT"),
    E("file5703596",                       "STICKY_BG_BLACK_STONE",       "stone", 5703596,  512,  512, "tile",    "TOPLEFT", 0.3),
    E("file7486947",                       "STICKY_BG_STONE_FLOOR",       "stone", 7486947, 1024, 1024, "tile",    "TOPLEFT"),
    -- Parchment
    E("file235412",                        "STICKY_BG_PARCHMENT_DRAGON",  "parchment", 235412, 512,  512, "cover", "TOPLEFT"),
    E("file457640",                        "STICKY_BG_PARCHMENT_EMPTY",   "parchment", 457640, 1024, 1024, "tile", "CENTER"),
    E("file839173",                        "STICKY_BG_PARCHMENT_DIRTY",   "parchment", 839173, 512,  512, "tile",  "CENTER", 0.5),
    -- Scenery
    E("creditsscreenbackground11midnight", "STICKY_BG_PURPLE_HAZE",       "scenery", 7242873,  256,  256, "tile",    "TOPLEFT"),
    E("creditsscreenbackground9dragonflight", "STICKY_BG_RED_HAZE",       "scenery", 4547578,  256,  256, "tile",    "TOPLEFT"),
    E("uiframenightfaebackground",         "STICKY_BG_SPARKLY_FAE",       "scenery", 3634712,  256,  256, "tile",    "TOPLEFT"),
    E("8xp_burningteldrassil_backgroundgradient", "STICKY_BG_TELDRASSIL_SKYLINE", "scenery", 1970360, 1024, 1024, "tileX", "CENTER"),
    E("7arg_argus_floatingislebackground03", "STICKY_BG_FLOATING_ISLE_YELLOW", "scenery", 1693869, 1024, 1024, "cover", "TOP"),
    E("7arg_argus_floatingislebackground02", "STICKY_BG_FLOATING_ISLE_GREEN",  "scenery", 1693866, 1024, 1024, "cover", "TOP"),
    E("kultiran_background_02",            "STICKY_BG_DAYLIGHT",          "scenery", 5582795, 1024, 1024, "tileX",   "CENTER"),
    E("file191123",                        "STICKY_BG_THICK_FOG",         "scenery", 191123,   512,  512, "stretch", "TOPLEFT"),
    E("file644000",                        "STICKY_BG_STORMWIND_SKY",     "scenery", 644000,  1024,  512, "cover",   "CENTER"),
    E("file650623",                        "STICKY_BG_IRONFORGE_SKY",     "scenery", 650623,   256,  256, "cover",   "CENTER"),
    E("file1119242",                       "STICKY_BG_DARKEST_SKY",       "scenery", 1119242,  128,  128, "stretch", "TOPLEFT"),
    E("file1260093",                       "STICKY_BG_RISING_DAWN",       "scenery", 1260093, 1024, 1024, "stretch", "CENTER"),
    -- Professions (alphabetical)
    E("professionbackgroundartalchemy",        "STICKY_BG_PROF_ALCHEMY",        "profession", 4625450, 1024, 1024, "tile", "TOP"),
    E("professionbackgroundartblacksmithing",  "STICKY_BG_PROF_BLACKSMITHING",  "profession", 4625448, 1024, 1024, "tile", "TOP"),
    E("file4671747",                           "STICKY_BG_PROF_COOKING",        "profession", 4671747, 1024, 1024, "tile", "TOP"),
    E("professionbackgroundartenchanting",     "STICKY_BG_PROF_ENCHANTING",     "profession", 4723320, 1024, 1024, "tile", "TOP"),
    E("professionbackgroundartengineering",    "STICKY_BG_PROF_ENGINEERING",    "profession", 4722478, 1024, 1024, "tile", "TOP"),
    E("professionspecializationbackgroundartfirstaid", "STICKY_BG_PROF_FIRST_AID", "profession", 7744229, 1024, 1024, "tile", "TOP"),
    E("professionbackgroundartfishing",        "STICKY_BG_PROF_FISHING",        "profession", 4723316, 1024, 1024, "tile", "TOP"),
    E("professionbackgroundartherbalism",      "STICKY_BG_PROF_HERBALISM",      "profession", 4723159, 1024, 1024, "tile", "TOP"),
    E("professionbackgroundartinscription",    "STICKY_BG_PROF_INSCRIPTION",    "profession", 4723119, 1024, 1024, "tile", "TOP"),
    E("professionbackgroundartjewelcrafting",  "STICKY_BG_PROF_JEWELCRAFTING",  "profession", 4723112, 1024, 1024, "tile", "TOP"),
    E("professionbackgroundartleatherworking", "STICKY_BG_PROF_LEATHERWORKING", "profession", 4723154, 1024, 1024, "tile", "TOP"),
    E("professionbackgroundartmining",         "STICKY_BG_PROF_MINING",         "profession", 4723189, 1024, 1024, "tile", "TOP"),
    E("professionspecializationbackgroundartpoisons", "STICKY_BG_PROF_POISON",  "profession", 7744227, 1024, 1024, "tile", "TOP"),
    E("professionbackgroundartskinning",       "STICKY_BG_PROF_SKINNING",       "profession", 4723308, 1024, 1024, "tile", "TOP"),
    E("professionbackgroundarttailoring",      "STICKY_BG_PROF_TAILORING",      "profession", 4627497, 1024, 1024, "tile", "TOP"),
    -- Classic: the one old texture that stays in BigNoteBox (the Reference
    -- Box task panel uses it too); the rest come from BigNoteBox_BGs
    E("bg-stone", "STICKY_BG_STONE", "classic",
      "Interface\\AddOns\\BigNoteBox\\Assets\\UI\\ui-bg-stone.tga", 256, 256, "tile", "TOPLEFT"),
}
SBG.LIST = LIST

local _byKey = {}
local function Index(e)
    e.label = L[e.label] or e.label
    _byKey[e.key] = e
end
for _, e in ipairs(LIST) do Index(e) end

-- Called by BigNoteBox_BGs when it loads. Entries use the fields above
-- (label = an L key name, cat defaults to "classic"). A key already here is
-- skipped. LIST is extended in place, so every holder of it sees the new ones.
function BNB.RegisterStickyBackgrounds(defs)
    if type(defs) ~= "table" then return end
    for _, d in ipairs(defs) do
        if type(d) == "table" and d.key and d.file and not _byKey[d.key] then
            d.cat = d.cat or "classic"
            d.scale = d.scale or 1
            LIST[#LIST + 1] = d
            Index(d)
        end
    end
end

-- Loads BigNoteBox_BGs once per session. Safe to call often.
local _tried = false
function SBG.LoadClassic()
    if _tried then return end
    _tried = true
    local load = (C_AddOns and C_AddOns.LoadAddOn) or LoadAddOn
    if load then pcall(load, BGS_ADDON) end
end

-- The entry for key; LIST[1] ("none") when it is unknown or unavailable
function SBG.Get(key)
    if not key or key == "none" then return LIST[1] end
    local e = _byKey[key]
    if not e and not _tried then
        SBG.LoadClassic()
        e = _byKey[key]
    end
    return e or LIST[1]
end

function SBG.Label(key)
    return SBG.Get(key).label
end

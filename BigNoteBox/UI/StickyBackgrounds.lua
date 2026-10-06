-- BigNoteBox UI/StickyBackgrounds.lua
-- The sticky background registry (ALL-110). Drawn by BNB.BgLayer
-- (UI/BgLayer.lua); picked in sticky settings (UI/StickySettings.lua).
--
-- An entry: { key, label, cat, file, mode, anchor, scale, w, h }.
--   key    saved in the sticky's cfg.bgTexture; never rename one
--   label  shown name (an L key, resolved here)
--   cat    picker tab: stone | parchment | scenery | profession | classic
--   file   game file ID, or an addon path; w / h = its native size
--   crop   optional { x, y, w, h }; flip optional "h" / "v" / "hv"; bright
--          optional -1..1, curated in the Lab (all UI/BgLayer.lua)
-- "none" is always first (plain colour).
--
-- The game backgrounds come from the Background Lab (BigNoteBox_Dev Labs/BackgroundLab.lua,
-- /bnb bglab), Dukul 2026-09-27; its Export is the source for new lines here.
-- The old bundled TGAs (the load-on-demand addon BigNoteBox_BGs) were removed
-- in ALL-338; SETTINGS v19 set their saved keys back to "none".

local BNB = BigNoteBox
local L   = BNB.L

local SBG = {}
BNB.StickyBG = SBG

-- The game's grey rock (file 374155), on every client
local STONE_FILE = "Interface\\FrameGeneral\\UI-Background-Rock"

-- The task panel's stone (UI/ReferenceBoxTasks.lua): the rock when the
-- client has it, else a dark plain colour, never a missing file's green square
function BNB.SetStoneTexture(tex)
    if C_UIFileAsset and C_UIFileAsset.IsKnownFile and not C_UIFileAsset.IsKnownFile(374155) then
        tex:SetColorTexture(0.10, 0.10, 0.11, 1)
    else
        tex:SetTexture(STONE_FILE)
    end
end

local function E(key, label, cat, file, w, h, mode, anchor, scale, crop, flip, bright)
    return { key = key, label = label, cat = cat, file = file, w = w, h = h,
             mode = mode, anchor = anchor, scale = scale or 1, crop = crop, flip = flip, bright = bright }
end

-- The profession art fills only the top left 677 x 550 of its 1024 file; the
-- rest is transparent and showed the note colour on a big sticky (Dukul
-- 2026-09-27, measured from wow.export PNGs). The specialization art fades
-- out over its top and bottom 2 px, so its crop starts below that.
local PROF_CROP = { 0, 0, 677, 550 }
local SPEC_CROP = { 0, 2, 677, 546 }

-- Art that exists on one client only draws as a green square on the other.
-- Those entries are left out of LIST there, so the picker never shows them
-- and a note that saved one reads None on that client; the key is kept.
-- Found by Dukul 2026-09-27 (green on Retail, fine on Forever); a Retail-only
-- list follows once he has been through the Retail files in wow.export.
local FOREVER_ONLY = {
    bankframebackgroundc60                        = true,   -- Dark Used Stone
    creditsscreenbackground0wowc60                = true,   -- Red Cement
    gamepadmapbackgroundtile                      = true,   -- Reddish Wood
    professionspecializationbackgroundartfirstaid = true,
    professionspecializationbackgroundartpoisons  = true,
}
local RETAIL_ONLY = {}

local function OnThisClient(key)
    if BNB.IsForever then return not RETAIL_ONLY[key] end
    return not FOREVER_ONLY[key]
end

-- Labels are L key names here; resolved to text below
local ALL = {
    { key = "none", label = "STICKY_BG_NONE" },
    -- The main window's own background: grey rock on Retail, our wood grain
    -- on Forever (UI/Chrome.lua). The Oracle's Default style uses it (ALL-69.5,
    -- Dukul 2026-09-28). Rock size 256 assumed; check the tiling in game.
    BNB.IsForever
        and E("windowbg", "STICKY_BG_WINDOW", "stone",
              "Interface\\AddOns\\BigNoteBox\\Assets\\UI\\ui-bg-forever", 512, 512, "tile", "TOPLEFT")
        or  E("windowbg", "STICKY_BG_WINDOW", "stone",
              "Interface\\FrameGeneral\\UI-Background-Rock", 256, 256, "tile", "TOPLEFT"),
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
    E("professionbackgroundartalchemy",        "STICKY_BG_PROF_ALCHEMY",        "profession", 4625450, 1024, 1024, "cover", "TOP", 1, PROF_CROP),
    E("professionbackgroundartblacksmithing",  "STICKY_BG_PROF_BLACKSMITHING",  "profession", 4625448, 1024, 1024, "cover", "TOP", 1, PROF_CROP),
    E("file4671747",                           "STICKY_BG_PROF_COOKING",        "profession", 4671747, 1024, 1024, "cover", "TOP", 1, PROF_CROP),
    E("professionbackgroundartenchanting",     "STICKY_BG_PROF_ENCHANTING",     "profession", 4723320, 1024, 1024, "cover", "TOP", 1, PROF_CROP),
    E("professionbackgroundartengineering",    "STICKY_BG_PROF_ENGINEERING",    "profession", 4722478, 1024, 1024, "cover", "TOP", 1, PROF_CROP),
    E("professionspecializationbackgroundartfirstaid", "STICKY_BG_PROF_FIRST_AID", "profession", 7744229, 1024, 1024, "cover", "TOP", 1, SPEC_CROP),
    E("professionbackgroundartfishing",        "STICKY_BG_PROF_FISHING",        "profession", 4723316, 1024, 1024, "cover", "TOP", 1, PROF_CROP),
    E("professionbackgroundartherbalism",      "STICKY_BG_PROF_HERBALISM",      "profession", 4723159, 1024, 1024, "cover", "TOP", 1, PROF_CROP),
    E("professionbackgroundartinscription",    "STICKY_BG_PROF_INSCRIPTION",    "profession", 4723119, 1024, 1024, "cover", "TOP", 1, PROF_CROP),
    E("professionbackgroundartjewelcrafting",  "STICKY_BG_PROF_JEWELCRAFTING",  "profession", 4723112, 1024, 1024, "cover", "TOP", 1, PROF_CROP),
    E("professionbackgroundartleatherworking", "STICKY_BG_PROF_LEATHERWORKING", "profession", 4723154, 1024, 1024, "cover", "TOP", 1, PROF_CROP),
    E("professionbackgroundartmining",         "STICKY_BG_PROF_MINING",         "profession", 4723189, 1024, 1024, "cover", "TOP", 1, PROF_CROP),
    E("professionspecializationbackgroundartpoisons", "STICKY_BG_PROF_POISON",  "profession", 7744227, 1024, 1024, "cover", "TOP", 1, SPEC_CROP),
    E("professionbackgroundartskinning",       "STICKY_BG_PROF_SKINNING",       "profession", 4723308, 1024, 1024, "cover", "TOP", 1, PROF_CROP),
    E("professionbackgroundarttailoring",      "STICKY_BG_PROF_TAILORING",      "profession", 4627497, 1024, 1024, "cover", "TOP", 1, PROF_CROP),
}
-- "Stone", the Reference Box task panel's background too. Our 768 KB TGA
-- became the game's own rock (ALL-164); on Retail that is the Window entry
-- already, so there the key resolves to it (below the index)
if BNB.IsForever or BNB.IsClassic then
    ALL[#ALL + 1] = E("bg-stone", "STICKY_BG_STONE", "classic", STONE_FILE, 256, 256, "tile", "TOPLEFT")
end
local LIST = {}
for _, e in ipairs(ALL) do
    if OnThisClient(e.key) then LIST[#LIST + 1] = e end
end
SBG.LIST = LIST

local _byKey = {}
local function Index(e)
    e.label = BNB.HasL(e.label) and L[e.label] or e.label
    _byKey[e.key] = e
end
for _, e in ipairs(LIST) do Index(e) end
-- Retail: "Stone" is the same rock as "Window" (ALL-164), one picker entry
if not _byKey["bg-stone"] then _byKey["bg-stone"] = _byKey["windowbg"] end

-- The entry for key; LIST[1] ("none") when it is unknown or unavailable
function SBG.Get(key)
    if not key or key == "none" then return LIST[1] end
    return _byKey[key] or LIST[1]
end

function SBG.Label(key)
    return SBG.Get(key).label
end

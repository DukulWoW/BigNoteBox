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

-- The Classic clients (Era, Anniversary, MoP) have only a few of these files,
-- so there the list is the other way round: only these keys show, one list
-- for all three (Dukul, Classic beta, 2026-10-07, ALL-366). A new entry is
-- hidden on Classic until it has been seen there and added here.
local CLASSIC_SHOWS = {
    none                = true,
    windowbg            = true,   -- Window
    classhallbackground = true,   -- Scuffed Walls
    file609607          = true,   -- Dark Ruins
    file235412          = true,   -- Dragon Parchment
    file457640          = true,   -- Sand Stone
    file839173          = true,   -- Dirty Paper
    file191123          = true,   -- Thick Fog
    file644000          = true,   -- Stormwind Sky
    file650623          = true,   -- Ironforge Sky
    ["bg-stone"]        = true,   -- Stone
}

local function OnThisClient(key)
    if BNB.IsForever then return not RETAIL_ONLY[key] end
    if BNB.IsClassic then return CLASSIC_SHOWS[key] == true end
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
    -- Size and look from the Background Lab (ALL-370, Dukul 2026-10-07)
    E("file609607",                        "STICKY_BG_DARK_RUINS",        "stone", 609607,   256,  256, "cover",   "TOP", 1, { 0, 0, 256, 256 }),
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
    E("file191123",                        "STICKY_BG_THICK_FOG",         "scenery", 191123,  2048, 1024, "tile",    "TOPLEFT"),   -- Lab, ALL-370
    E("file644000",                        "STICKY_BG_STORMWIND_SKY",     "scenery", 644000,  1024,  512, "cover",   "CENTER"),
    E("file650623",                        "STICKY_BG_IRONFORGE_SKY",     "scenery", 650623,   256,  256, "cover",   "CENTER"),
    E("file1119242",                       "STICKY_BG_DARKEST_SKY",       "scenery", 1119242,  128,  128, "stretch", "TOPLEFT"),
    E("file1260093",                       "STICKY_BG_RISING_DAWN",       "scenery", 1260093, 1024, 1024, "stretch", "CENTER"),
    -- Dukul's Background Lab export, 2026-10-07 (ALL-370, Retail)
    -- Stone & Wood
    E("auctionhouse-background-buy-commodities", "STICKY_BG_GRAY_STONE", "stone", 3054898, 2048, 1024, "cover", "CENTER", 1, { 1, 1, 367, 396 }, nil, 0.10),
    E("warboard-background", "STICKY_BG_OLD_WOOD_PLANKS", "stone", 1823937, 1024, 512, "cover", "TOP", 1, { 1, 1, 597, 502 }),
    E("collectionsbackgroundtile", "STICKY_BG_REDDISH_STONE", "stone", 984835, 256, 256, "cover", "CENTER"),
    E("Garr_InfoBox-BackgroundTile", "STICKY_BG_RED_WOOD", "stone", 939610, 256, 256, "tile", "TOPLEFT", 1, { 0, 0, 256, 256 }),
    E("ui-lfg-background-heroic", "STICKY_BG_BORDERED_DARK_STONE", "stone", 340816, 512, 256, "stretch", "TOPLEFT", 1, { 0, 0, 327, 256 }),
    E("ui-lfg-background-dungeonwall", "STICKY_BG_DARK_BRICK_WALL", "stone", 337489, 512, 256, "cover", "TOPLEFT", 1, { 0, 0, 320, 256 }),
    E("ui-paperdoll-slotbackground", "STICKY_BG_CRACKED_BLACK_STONE", "stone", 136531, 512, 512, "cover", "CENTER", 1, { 140, 68, 264, 363 }),
    E("communities-widebackground", "STICKY_BG_MURAL_OF_THE_OLD", "stone", 1981967, 1024, 512, "cover", "TOPLEFT", 1, { 1, 1, 613, 336 }),
    E("AlliedRace-UnlockingFrame-Background", "STICKY_BG_STAINED_STONE", "stone", 1699827, 1024, 1024, "cover", "TOP", 1, { 339, 1, 342, 583 }, nil, 0.30),
    E("tradeskill-background-recipe-unlearned", "STICKY_BG_STACK_OF_SCROLLS", "stone", 1319046, 1024, 512, "cover", "BOTTOMRIGHT", 1, { 303, 1, 300, 383 }),
    E("honorsystem-talents-bg", "STICKY_BG_DARK_PURPLE", "stone", 1249993, 1024, 1024, "cover", "TOPLEFT", 1, { 1, 1, 635, 383 }),
    E("Capacitance-Blacksmithing-BG", "STICKY_BG_STONE_DOOR", "stone", 973339, 512, 512, "stretch", "TOPLEFT", 1, { 1, 1, 321, 370 }),
    E("guildvaultbg", "STICKY_BG_RED_STONE", "stone", 590068, 256, 256, "cover", "CENTER", 1, { 0, 0, 256, 256 }),
    E("ui-petframe-frame", "STICKY_BG_FRAMED_RED_LEATHER", "stone", 237622, 512, 256, "stretch", "CENTER", 1, { 0, 0, 312, 224 }),
    E("itemtext-marble-topleft", "STICKY_BG_WHITE_MARBLE", "stone", 136271, 256, 256, "cover", "CENTER", 1, { 0, 19, 256, 237 }),
    -- Parchment
    E("catalogshopvirtualcurrencymenubackground", "STICKY_BG_MAELSTROM", "parchment", 7570997, 2048, 1024, "cover", "TOP", 1, { 0, 161, 1830, 494 }),
    E("loottab-background", "STICKY_BG_OLD_PARCHMENT", "parchment", 1495388, 1024, 512, "cover", "TOP", 1, { 1, 55, 752, 327 }),
    E("QuestBG-Alliance", "STICKY_BG_ALLIANCE", "parchment", 1412268, 1024, 1024, "cover", "TOPLEFT", 1, { 1, 1, 299, 407 }),
    E("QuestBG-Horde", "STICKY_BG_HORDE", "parchment", 1412268, 1024, 1024, "cover", "TOPLEFT", 1, { 1, 410, 299, 407 }),
    E("dressupbackground-pet1", "STICKY_BG_BURNT_PARCHMENT", "parchment", 632823, 256, 256, "cover", "TOPLEFT", 1, { 0, 0, 256, 256 }),
    E("ui-achievement-parchment-horizontal-desaturated", "STICKY_BG_REALLY_DIRTY_PARCHMENT", "parchment", 130660, 512, 256, "cover", "TOPLEFT", 1, { 0, 0, 512, 256 }),
    E("ui-achievement-parchment", "STICKY_BG_YELLOW_PAPER", "parchment", 130662, 512, 512, "stretch", "TOPLEFT", 1, { 0, 0, 253, 512 }),
    E("garrisonmissionparchment", "STICKY_BG_GREY_PARCHMENT", "parchment", 953549, 256, 256, "tile", "TOPLEFT"),
    E("garrisonshipmissionparchment", "STICKY_BG_BLUE_PARCHMENT", "parchment", 1118640, 256, 256, "tile", "TOPLEFT", 1, { 0, 0, 256, 256 }),
    E("photosensitivitywarningparchment", "STICKY_BG_DARK_BROWNISH_PARCHMENT", "parchment", 5907435, 512, 512, "tile", "TOPLEFT"),
    E("UI-Frame-Neutral-CardParchmentWider", "STICKY_BG_BURNT_PAGE", "parchment", 2142239, 1024, 1024, "stretch", "CENTER", 1, { 281, 152, 489, 438 }),
    E("warboard-parchment", "STICKY_BG_PINNED_NOTE", "parchment", 1823881, 1024, 1024, "cover", "TOP", 1, { 1, 474, 350, 473 }),
    E("alliedracesunlockingframe", "STICKY_BG_PAGES_OF_A_BOOK", "parchment", 1699827, 1024, 1024, "cover", "TOPLEFT", 1, { 352, 0, 327, 587 }),
    E("ClassTrial-End-Frame", "STICKY_BG_BUCKLED_PARCHMENT", "parchment", 1399006, 1024, 1024, "cover", "TOPLEFT", 1, { 41, 15, 482, 321 }),
    E("book-bg", "STICKY_BG_INSIDE_THE_BOOK", "parchment", 1368285, 512, 512, "tile", "TOPLEFT", 1, { 1, 1, 486, 494 }),
    E("NoQuestsBackground", "STICKY_BG_FORGOTTEN_PARCHMENT", "parchment", 904010, 1024, 1024, "cover", "TOPLEFT", 1, { 1, 1, 287, 464 }),
    -- Scenery
    E("shop-frame-carousel-large-bg", "STICKY_BG_DIRTY_FOG", "scenery", 7370730, 1024, 1024, "stretch", "CENTER", 1, { 1, 455, 782, 441 }),
    E("ui-lfg-background-moltencoreq", "STICKY_BG_MOLTEN_CORE", "scenery", 1037398, 512, 256, "cover", "CENTER", 1, { 0, 0, 325, 256 }),
    E("taximap1", "STICKY_BG_KALIMDOR", "scenery", 137029, 512, 512, "cover", "CENTER", 1, nil, nil, -0.40),
    E("taximap0", "STICKY_BG_EASTERN_KINGDOMS", "scenery", 137028, 512, 512, "cover", "CENTER", 1, { 0, 0, 512, 512 }, nil, -0.40),
    E("taximap571", "STICKY_BG_NORTHREND", "scenery", 137031, 512, 512, "cover", "CENTER", 1, { 0, 0, 512, 512 }),
    E("taximap530", "STICKY_BG_OUTLAND", "scenery", 137030, 512, 512, "cover", "CENTER", 1, { 0, 0, 512, 512 }),
    E("ui-lfg-background-fallofdeathwingq", "STICKY_BG_DEATHWING", "scenery", 576354, 512, 256, "cover", "CENTER", 1, { 0, 0, 325, 256 }),
    -- Events (cat "event")
    E("ui-lfg-holiday-background-summer", "STICKY_BG_MIDSUMMER_FIRE_FESTIVAL", "event", 368573, 512, 256, "cover", "TOP", 1, { 0, 0, 322, 256 }),
    E("ui-lfg-holiday-background-brew", "STICKY_BG_BREWFEST", "event", 368570, 512, 256, "tileX", "TOP", 1, { 0, 0, 323, 256 }),
    E("ui-lfg-holiday-background-halloween", "STICKY_BG_HALLOWS_END", "event", 368571, 512, 256, "cover", "TOP", 1, { 0, 0, 322, 256 }),
    E("ui-lfg-holiday-background-love", "STICKY_BG_LOVE_IS_IN_THE_AIR", "event", 368572, 512, 256, "cover", "TOP", 1, { 0, 0, 319, 250 }),
    -- No category: shown under All only
    E("ui-friendsframe-highlightbar-blue", "STICKY_BG_BLUE_GRADIENT", nil, 440557, 256, 32, "stretch", "CENTER", 1, { 0, 2, 256, 29 }),
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

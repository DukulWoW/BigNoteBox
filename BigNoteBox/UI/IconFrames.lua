-- BigNoteBox UI/IconFrames.lua
-- The note icon frame registry (ALL-127). Drawn by BNB.IconFrameLayer
-- (UI/IconFrameLayer.lua); picked in BNB.IconFramePicker, applied everywhere
-- a note icon is drawn through BNB.ApplyIconFrame (NoteList, sticky icon
-- badge + mini tile, Reference Box, Oracle, Trash).
--
-- An entry: { key, label, cat, file, w, h, crop, hole, shape, layer, tint }.
--   key   saved in note.iconFrame; never rename one
--   label shown name (an L key, resolved here)
--   cat   "square" | "circle": the picker tab (Dukul's naming in the Lab,
--         "Square - " / "Circle - "; not always the same as shape)
--   the rest matches an IconFrameLayer def (see its header comment); crop
--   and hole are already in absolute file pixels, atlas regions resolved
-- "none" is not listed here; a missing/empty note.iconFrame means no frame.
--
-- Source: the Icon Lab (BigNoteBox_Dev Labs/IconLab.lua, /bnb iconlab), Dukul's Export.
-- Second batch (replaces the first): _work/iconlab-export-2026-09-28b.lua,
-- 52 entries renamed and checked on Retail. Nope and Locked In were
-- exported without a hole; they carry the Lab's stand-in (middle 70 % of
-- the area), which is what the Lab showed. Locked In is named Circle in the
-- export but is square (Dukul). Thick Silver / Golden Dragon from the first
-- batch were dropped on purpose.

local BNB = BigNoteBox
local L   = BNB.L

local IF = {}
BNB.IconFrames = IF

local function E(key, label, cat, file, w, h, crop, hole, shape, layer)
    return { key = key, label = label, cat = cat, file = file, w = w, h = h,
             crop = crop, hole = hole, shape = shape, layer = layer, tint = true }
end

-- Art that exists on one client only draws as a green square on the other
-- (see UI/StickyBackgrounds.lua's FOREVER_ONLY for the pattern this follows). A note
-- with such a frame saved draws none on the other client (Get -> nil); the
-- key is kept.
local FOREVER_ONLY = {}
local RETAIL_ONLY = {
    commoninsideframe2x = true,   -- Ornate Corners, file 8033663 (Dukul, Forever, 2026-10-04)
}

local function OnThisClient(key)
    if BNB.IsForever then return not RETAIL_ONLY[key] end
    return not FOREVER_ONLY[key]
end

-- Labels are L key names here; resolved to text below
local ALL = {
    E("pandarentraininglarge_circular_frame", "ICON_FRAME_STONE_ROPE", "circle", 629942, 256, 256, nil, { 78, 78, 100, 100 }, "circle"),
    E("petbattle-goldspeedframe", "ICON_FRAME_GOLDEN_GLOW", "square", 648078, 128, 128, { 12, 14, 85, 82 }, { 22, 22, 65, 65 }),
    E("arcane_circular_frame", "ICON_FRAME_ARCANE_POWER", "circle", 669472, 128, 128, nil, { 30.5, 30.5, 70, 70 }, "circle"),
    E("combatassistanthighlightsingleframe", "ICON_FRAME_BLUE_GLOW", "square", 7464534, 128, 128, { 0, 0, 78, 78 }, { 9, 9, 60, 60 }),
    E("housingitemwoodiconframe", "ICON_FRAME_TIN_FRAME", "square", 7498608, 128, 128, { 0, 0, 66, 66 }, { 2, 2, 62, 62 }),
    E("commoninsideframe2x", "ICON_FRAME_ORNATE_CORNERS", "square", 8033663, 256, 256, { 0, 0, 215, 215 }, { 12, 13, 191, 189 }),
    E("worldquest-followerabilityframe", "ICON_FRAME_GOLDEN_HUNTER", "square", 1339312, 512, 512, { 99, 296, 101, 86 }, { 123, 311, 51, 43 }),
    E("ui-achievement-bling", "ICON_FRAME_GOLDEN_WREATH", "square", 130651, 128, 128, { 0, 0, 120, 120 }, { 30.5, 30.5, 59, 59 }, "circle"),
    E("ui-achievement-iconframe", "ICON_FRAME_GOLD_FRAME", "square", 130656, 128, 128, { 0, 0, 71, 70 }, { 8, 7.5, 55, 55 }),
    E("ui-playerframe-deathknight-goldborder", "ICON_FRAME_TWO_GOLDEN_CIRCLES", "circle", 136622, 256, 128, { 25, 20, 80, 80 }, { 31.5, 31.5, 57, 57 }, "circle"),
    E("socket-cogwheel-closed", "ICON_FRAME_SOCKET_GOLD", "square", 2958680, 512, 256, { 178, 107, 49, 47 }, { 185.5, 114, 34, 33 }),
    E("Adventure-Mission-Gold-Dragon", "ICON_FRAME_ELITE_DRAGON", "circle", 3463360, 1024, 2048, { 1, 1770, 97, 93 }, { 22, 1787.5, 52, 49 }, "circle"),
    E("Adventure-Mission-Silver-Dragon", "ICON_FRAME_RARE_SILVER_DRAGON", "circle", 3463360, 1024, 2048, { 100, 1770, 97, 93 }, { 120, 1789.5, 52, 49 }, "circle"),
    E("Adventures-Buff-Heal-Burst", "ICON_FRAME_LIGHT_BURST", "circle", 3463360, 1024, 2048, { 686, 806, 129, 138 }, { 715.5, 836.5, 70, 70 }, "circle", "under"),
    E("Adventurers-Frame-Soulbind-Necrolord", "ICON_FRAME_STONE", "circle", 3463360, 1024, 2048, { 96, 1671, 96, 98 }, { 107.5, 1683, 73, 74 }, "circle"),
    E("Adventures-EndCombat-Fail", "ICON_FRAME_TWO_SWORDS", "circle", 3463360, 1024, 2048, { 503, 806, 181, 153 }, { 543, 843, 107, 107 }, "circle", "under"),
    E("socket-blue-open", "ICON_FRAME_GEMS_BLUE", "square", 2958680, 512, 256, { 1, 1, 60, 57 }, { 10, 9.5, 42, 40 }),
    E("socket-meta-open", "ICON_FRAME_GEMS_YELLOW", "square", 2958680, 512, 256, { 1, 60, 60, 57 }, { 10, 68.5, 42, 40 }),
    E("socket-red-open", "ICON_FRAME_GEMS_RED", "square", 2958680, 512, 256, { 1, 119, 60, 57 }, { 10, 127.5, 42, 40 }),
    E("ui-glyphframe", "ICON_FRAME_GOLDEN_ORB", "circle", 237655, 1024, 1024, { 878, 227, 84, 84 }, { 890, 239, 60, 60 }, "circle"),
    E("ui-glyphframe-glow", "ICON_FRAME_HOLY_AURA", "circle", 237653, 512, 512, { 0, 0, 390, 400 }, { 64, 77, 250, 250 }, "circle", "under"),
    E("ui-glyphframe-2", "ICON_FRAME_SIMPLE_GLASS_ORB", "circle", 237655, 1024, 1024, { 946, 0, 63, 63 }, { 950.5, 3.5, 56, 56 }, "circle"),
    E("ui-gearmanager-leaveitem-transparent", "ICON_FRAME_NOPE", "circle", 255353, 64, 64, nil, { 9.5, 9.5, 45, 45 }, "circle"),  -- no hole in the export: the Lab's stand-in
    E("ui-glyphframe-3", "ICON_FRAME_LOCKED_IN", "square", 237655, 1024, 1024, { 878, 1, 67, 67 }, { 888, 11, 47, 47 }),  -- no hole in the export: the Lab's stand-in
    E("ui-tutorial-frame", "ICON_FRAME_INNER_BLUE_AURA", "circle", 341461, 512, 512, { 385, 112, 55, 55 }, { 388, 116, 48, 48 }, "circle"),
    E("ui-icon-questborder", "ICON_FRAME_INNER_GOLD_AURA", "square", 368363, 64, 64, nil, { 2.5, 2.5, 59, 59 }),
    E("guildachievements", "ICON_FRAME_VINTAGE_FRAME", "square", 446202, 1024, 256, { 409, 117, 76, 76 }, { 422, 131, 48, 48 }),
    E("guildextra", "ICON_FRAME_FILIGREE_CARVINGS", "circle", 446203, 512, 128, { 290, 0, 120, 80 }, { 316, 4, 66, 69 }, "circle"),
    E("generic1player_circular_frame", "ICON_FRAME_STEEL", "circle", 449445, 128, 128, nil, { 33, 33, 62, 62 }, "circle"),
    E("alliance_circular_frame", "ICON_FRAME_ALLIANCE_CIRCLET", "circle", 457561, 128, 128, nil, { 32, 32, 64, 64 }, "circle"),
    E("atramedes_circular_frame", "ICON_FRAME_RUNIC_PORTAL", "circle", 457566, 128, 128, nil, { 34.5, 34.5, 59, 59 }, "circle"),
    E("horde_circular_frame", "ICON_FRAME_HORDE_CIRCLET", "circle", 457585, 128, 128, { 0, 0, 128, 128 }, { 34, 34, 60, 60 }, "circle"),
    E("mechanical_circular_frame", "ICON_FRAME_MECHANICAL_GEAR", "circle", 457591, 128, 128, { 0, 0, 128, 128 }, { 33.5, 33.5, 61, 61 }, "circle"),
    E("metaleternium_circular_frame", "ICON_FRAME_STUDDED_METAL", "circle", 457597, 128, 128, { 0, 0, 128, 128 }, { 33.5, 33.5, 61, 61 }, "circle"),
    E("stonetan_circular_frame", "ICON_FRAME_TAN_STONE", "circle", 457611, 128, 128, { 0, 0, 128, 128 }, { 34, 34, 60, 60 }, "circle"),
    E("woodboards_circular_frame", "ICON_FRAME_WOOD", "circle", 457614, 128, 128, { 0, 0, 128, 128 }, { 34, 34, 60, 60 }, "circle"),
    E("wowui_circular_frame", "ICON_FRAME_STONE_GOLD", "circle", 457623, 128, 128, { 0, 0, 128, 128 }, { 35, 35, 58, 58 }, "circle"),
    E("air_circular_frame", "ICON_FRAME_AIR", "circle", 458987, 128, 128, { 0, 0, 128, 128 }, { 33, 33, 62, 62 }, "circle"),
    E("fire_circular_frame", "ICON_FRAME_FIRE", "circle", 458991, 128, 128, { 0, 0, 128, 128 }, { 33, 33, 62, 62 }, "circle"),
    E("ice_circular_frame", "ICON_FRAME_ICE", "circle", 458995, 128, 128, { 0, 0, 128, 128 }, { 33, 33, 62, 62 }, "circle"),
    E("meat_circular_frame", "ICON_FRAME_MEAT", "circle", 458999, 128, 128, { 0, 0, 128, 128 }, { 33, 33, 62, 62 }, "circle"),
    E("moltenrock_circular_frame", "ICON_FRAME_MOLTEN_ROCK", "circle", 459003, 128, 128, { 0, 0, 128, 128 }, { 33, 33, 62, 62 }, "circle"),
    E("rock_circular_frame", "ICON_FRAME_EARTH", "circle", 459007, 128, 128, { 0, 0, 128, 128 }, { 33, 33, 62, 62 }, "circle"),
    E("undeadmeat_circular_frame", "ICON_FRAME_UNDEAD_MEAT", "circle", 459011, 128, 128, { 0, 0, 128, 128 }, { 33, 33, 62, 62 }, "circle"),
    E("water_circular_frame", "ICON_FRAME_WATER", "circle", 459015, 128, 128, { 0, 0, 128, 128 }, { 33, 33, 62, 62 }, "circle"),
    E("minimap-glow", "ICON_FRAME_THE_SUN", "circle", 461873, 256, 256, { 0, 0, 192, 192 }, { 20, 20, 148, 148 }, "circle", "under"),
    E("talents-texture", "ICON_FRAME_ARMBAND", "circle", 538611, 512, 256, { 201, 45, 100, 107 }, { 215.5, 55.5, 73, 78 }, "circle"),
    E("explosionb_32frames", "ICON_FRAME_SOLAR_FLARE", "circle", 897403, 1024, 512, { 391, 10, 114, 119 }, { 414.5, 41.5, 67, 70 }, "circle", "under"),
    E("explosiona_32frames512_nature", "ICON_FRAME_POISONOUS_CLOUD", "circle", 916383, 512, 256, { 196, 3, 53, 58 }, { 206.5, 17, 34, 36 }, "circle", "under"),
    E("explosiona_32frames512_shadow", "ICON_FRAME_SHADOW_MIST", "circle", 916387, 512, 256, { 193, 0, 62, 62 }, { 205, 14, 38, 38 }, "circle", "under"),
    E("explosiona_32frames512_wind", "ICON_FRAME_AIRY_MIST", "circle", 916393, 512, 256, { 195, 0, 57, 62 }, { 206.5, 16.5, 35, 34 }, "circle", "under"),
    E("talentframeatlas", "ICON_FRAME_CORNER_ORNAMENT", "square", 921230, 256, 1024, { 133, 941, 64, 59 }, { 133, 941, 64, 52 }),
}
local LIST = {}
for _, e in ipairs(ALL) do
    if OnThisClient(e.key) then LIST[#LIST + 1] = e end
end
IF.LIST = LIST

local _byKey = {}
for _, e in ipairs(LIST) do
    e.label = BNB.HasL(e.label) and L[e.label] or e.label
    _byKey[e.key] = e
end

-- The entry for key; nil when it is unknown, unavailable on this client, or
-- "none" (no frame)
function IF.Get(key)
    if not key or key == "none" or key == "" then return nil end
    return _byKey[key]
end

function IF.Label(key)
    local e = IF.Get(key)
    return e and e.label
end

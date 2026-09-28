-- BigNoteBox UI/IconFrames.lua
-- The note icon frame registry (ALL-127). Drawn by BNB.IconFrameLayer
-- (UI/IconFrameLayer.lua); picked in BNB.IconFramePicker, applied everywhere
-- a note icon is drawn through BNB.ApplyIconFrame (NoteList, sticky icon
-- badge + mini tile, Reference Box, Oracle, Trash).
--
-- An entry: { key, label, file, w, h, crop, hole, shape, layer, tint }.
--   key   saved in note.iconFrame; never rename one
--   label shown name (an L key, resolved here)
--   the rest matches an IconFrameLayer def (see its header comment); crop
--   and hole are already in absolute file pixels, atlas regions resolved
-- "none" is not listed here; a missing/empty note.iconFrame means no frame.
--
-- Source: the Icon Lab (UI/IconLab.lua, /bnb iconlab), Dukul's Export. First
-- batch: _work/iconlab-export-2026-09-28.lua, 24 entries looked at on
-- Retail, 21 named (3 left unnamed by Dukul are left out here; he can name
-- and re-export them later). "Stone  Circle" had a double space in the
-- export, fixed here. Arcane Power's hole reads 1.5 px off the file's true
-- centre in the export; left as measured, revisit in the Lab if it looks
-- off in the picker.

local BNB = BigNoteBox
local L   = BNB.L

local IF = {}
BNB.IconFrames = IF

local function E(key, label, file, w, h, crop, hole, shape, layer)
    return { key = key, label = label, file = file, w = w, h = h,
             crop = crop, hole = hole, shape = shape, layer = layer, tint = true }
end

-- Art that exists on one client only draws as a green square on the other;
-- empty until a Forever export finds one (see BigNoteBox_BGs' FOREVER_ONLY
-- for the pattern this follows).
local FOREVER_ONLY = {}
local RETAIL_ONLY = {}

local function OnThisClient(key)
    if BNB.IsForever then return not RETAIL_ONLY[key] end
    return not FOREVER_ONLY[key]
end

-- Labels are L key names here; resolved to text below
local ALL = {
    E("pandarentraininglarge_circular_frame", "ICON_FRAME_STONE_ROPE",           629942, 256, 256, nil,                       { 78, 78, 100, 100 }, "circle"),
    E("petbattle-goldspeedframe",              "ICON_FRAME_GOLDEN_GLOW",         648078, 128, 128, { 12, 14, 85, 82 },         { 22, 22, 65, 65 }),
    E("arcane_circular_frame",                 "ICON_FRAME_ARCANE_POWER",        669472, 128, 128, nil,                       { 30.5, 30.5, 70, 70 }, "circle"),
    E("combatassistanthighlightsingleframe",   "ICON_FRAME_BLUE_GLOW",           7464534, 128, 128, { 0, 0, 78, 78 },          { 9, 9, 60, 60 }),
    E("housingitemwoodiconframe",              "ICON_FRAME_TIN_FRAME",           7498608, 128, 128, { 0, 0, 66, 66 },          { 2, 2, 62, 62 }),
    E("commoninsideframe2x",                   "ICON_FRAME_ORNATE_CORNERS",      8033663, 256, 256, { 0, 0, 215, 215 },        { 12, 13, 191, 189 }),
    E("worldquest-followerabilityframe",       "ICON_FRAME_GOLDEN_HUNTER",       1339312, 512, 512, { 99, 296, 101, 86 },      { 123, 311, 51, 43 }),
    E("ui-achievement-bling",                  "ICON_FRAME_GOLDEN_WREATH",       130651,  128, 128, { 0, 0, 120, 120 },        { 30.5, 30.5, 59, 59 }, "circle"),
    E("worldquest-questmarker-dragon-silver",  "ICON_FRAME_THICK_SILVER_DRAGON", 1339312, 512, 512, { 268, 296, 64, 64 },      { 283, 311, 35, 35 }, "circle"),
    E("worldquest-questmarker-dragon",         "ICON_FRAME_THICK_GOLDEN_DRAGON", 1339312, 512, 512, { 202, 428, 64, 64 },      { 217, 443, 35, 35 }, "circle"),
    E("ui-achievement-iconframe",              "ICON_FRAME_GOLD_FRAME",          130656,  128, 128, { 0, 0, 71, 70 },          { 8, 7.5, 55, 55 }),
    E("ui-playerframe-deathknight-goldborder", "ICON_FRAME_TWO_GOLDEN_CIRCLES",  136622,  256, 128, { 25, 20, 80, 80 },        { 31.5, 31.5, 57, 57 }, "circle"),
    E("socket-cogwheel-closed",                "ICON_FRAME_SOCKET_GOLD",         2958680, 512, 256, { 178, 107, 49, 47 },      { 185.5, 114, 34, 33 }),
    E("Adventure-Mission-Gold-Dragon",         "ICON_FRAME_ELITE_DRAGON",        3463360, 1024, 2048, { 1, 1770, 97, 93 },     { 22, 1787.5, 52, 49 }, "circle"),
    E("Adventure-Mission-Silver-Dragon",       "ICON_FRAME_RARE_SILVER_DRAGON",  3463360, 1024, 2048, { 100, 1770, 97, 93 },   { 120, 1789.5, 52, 49 }, "circle"),
    E("Adventures-Buff-Heal-Burst",            "ICON_FRAME_SUN_BURST",           3463360, 1024, 2048, { 686, 806, 129, 138 },  { 715.5, 836.5, 70, 70 }, "circle", "under"),
    E("Adventurers-Frame-Soulbind-Necrolord",  "ICON_FRAME_STONE_CIRCLE",        3463360, 1024, 2048, { 96, 1671, 96, 98 },    { 107.5, 1683, 73, 74 }, "circle"),
    E("Adventures-EndCombat-Fail",             "ICON_FRAME_TWO_SWORDS",          3463360, 1024, 2048, { 503, 806, 181, 153 }, { 543, 843, 107, 107 }, "circle", "under"),
    E("socket-blue-open",                      "ICON_FRAME_GEMS_BLUE",           2958680, 512, 256, { 1, 1, 60, 57 },          { 10, 9.5, 42, 40 }),
    E("socket-meta-open",                      "ICON_FRAME_GEMS_YELLOW",         2958680, 512, 256, { 1, 60, 60, 57 },         { 10, 68.5, 42, 40 }),
    E("socket-red-open",                       "ICON_FRAME_GEMS_RED",            2958680, 512, 256, { 1, 119, 60, 57 },        { 10, 127.5, 42, 40 }),
}
local LIST = {}
for _, e in ipairs(ALL) do
    if OnThisClient(e.key) then LIST[#LIST + 1] = e end
end
IF.LIST = LIST

local _byKey = {}
for _, e in ipairs(LIST) do
    e.label = L[e.label] or e.label
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

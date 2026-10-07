-- BigNoteBox UI/ToastStyles.lua -- Toast styles (ALL-376 S2, from ALL-160)
--
-- A style is one picture (a game atlas, or a game file with a crop) or a
-- plain backdrop, plus where the icon, title, text line, timer bar and the
-- "+N more" label sit on it. Measured in the Toast Lab (BigNoteBox_Dev
-- Labs/ToastLab.lua), whose Export gives one entry per style for STYLES
-- below. The lab draws its preview with BNB.ToastStyles.Apply, so the lab
-- shows exactly what a toast shows.
--
-- A style def (all numbers in toast pixels at Toast scale 1, from the
-- toast's top-left, y downward):
--   key      saved in toastStyle / note settings: never rename one
--   label    locale key (a lab export carries name instead until it gets one)
--   w, h     the toast's size
--   back     "plain" = the black backdrop; "skin" = the skin preset's colours
--   atlas    a game atlas drawn over the whole toast (nil with back / file)
--   file     a game file id + fw, fh (its size) + crop = { x, y, w, h } in
--            file pixels (nil = the whole file); flip "h" / "v" / "hv"
--   icon     { x, y, size, shape = "square" | "circle", frame = an
--            IconFrames key, border = { atlas, pad } (an atlas drawn around
--            the icon, pad px past it on every side; or { file = id, pad }),
--            ownFrame = true: only the style's own frame / border (or the
--            art's built-in socket), never the note's icon frame }
--   title    { x, y, w, font, size, scale, justify }: font = a GAME_FONTS key
--            or a BNB.FONTS id (nil = the game's font object), size = px
--            (nil = the font object's size x scale; scale is the older way,
--            1 = GameFontNormal), justify = where the text sits inside w
--   text     { x, y, w, font, size, scale, justify }: why the toast showed
--   line2    { x, y, w, font, size, scale, justify }: the note's tl;dr or first line (S3)
--   bar      { x, y, w, h } or false (no timer bar)
--   more     { x, y } = the TOPRIGHT of the "+N more" label
--   gap      px between this toast and the next in the stack (nil = the
--            engine's GAP); two styles side by side use the larger one
--   faction  true = a meta style: the Horde / Alliance entry of `pick`
-- A style whose art this client lacks draws as "plain" with plain's layout.
-- A Latin-only font draws as the game's font on zhCN / zhTW / koKR, where it
-- has no glyphs for a note title (as the UI chrome font, ALL-22).

local BNB = BigNoteBox
local L   = BNB.L

local TS = {}
BNB.ToastStyles = TS

-- ── The styles ──────────────────────────────────────────────────────────────
-- plain / skin share one layout (today's toast, 260 x 48)
local PLAIN_LAYOUT = {
    w = 260, h = 62,
    icon  = { x = 8,  y = 11, size = 38, shape = "square" },
    title = { x = 54, y = 8,  w = 198, scale = 1 },
    text  = { x = 54, y = 25, w = 150, scale = 1 },
    line2 = { x = 54, y = 40, w = 198, scale = 1 },
    bar   = { x = 0,  y = 60, w = 260, h = 2 },
    more  = { x = 254, y = 25 },
}

local function WithLayout(def, layout)
    for k, v in pairs(layout) do if def[k] == nil then def[k] = v end end
    return def
end

local STYLES = {
    WithLayout({ key = "plain", label = "TOAST_STYLE_PLAIN", back = "plain" }, PLAIN_LAYOUT),
    WithLayout({ key = "skin",  label = "TOAST_STYLE_SKIN",  back = "skin",  classic = true, skinOnly = true }, PLAIN_LAYOUT),
    { key = "faction", label = "TOAST_STYLE_FACTION", faction = true,
      pick = { Horde = "loot-horde", Alliance = "loot-alliance" } },
    -- Toast Lab export, Dukul 2026-10-07 (test set; the faction loot toasts
    -- keep their locale labels, the rest show their lab name until S5 gives
    -- them one). Keys are saved in toastStyle: never rename one
    { key = "loot-horde", label = "TOAST_STYLE_LOOT_HORDE", atlas = "loottoast-bg-horde",
      w = 280, h = 99, gap = -2,
      icon  = { x = 26, y = 25, size = 50, shape = "square", border = { atlas = "loottoast-itemborder-gold", pad = 4 } },
      title = { x = 88, y = 24, w = 164, font = "morpheus", scale = 1.10, justify = "CENTER" },
      text  = { x = 88, y = 46, w = 115, scale = 1 },
      line2 = { x = 88, y = 62, w = 164, scale = 1 },
      bar   = { x = 61, y = 89, w = 158, h = 2 },
      more  = { x = 252, y = 46 } },
    { key = "loot-alliance", label = "TOAST_STYLE_LOOT_ALLIANCE", atlas = "loottoast-bg-alliance",
      w = 280, h = 99,
      icon  = { x = 24, y = 24, size = 50, shape = "square", border = { atlas = "loottoast-itemborder-gold", pad = 4 } },
      title = { x = 84, y = 21, w = 170, scale = 1.10 },
      text  = { x = 86, y = 43, w = 121, scale = 1 },
      line2 = { x = 86, y = 60, w = 170, scale = 1 },
      bar   = { x = 40, y = 78, w = 201, h = 2 },
      more  = { x = 256, y = 43 } },
    { key = "loottoast-dragonriding", name = "Dragon Riding", atlas = "loottoast-dragonriding",
      w = 281, h = 115,
      icon  = { x = 26, y = 36, size = 48, shape = "square" },
      title = { x = 85, y = 31, w = 174, scale = 1 },
      text  = { x = 86, y = 54, w = 118, scale = 1 },
      line2 = { x = 86, y = 71, w = 167, scale = 1 },
      bar   = { x = 20, y = 89, w = 240, h = 2 },
      more  = { x = 253, y = 54 } },
    { key = "LootToast-Azerite", name = "Azerite", atlas = "LootToast-Azerite",
      w = 277, h = 98,
      icon  = { x = 25, y = 25, size = 48, shape = "square", frame = "petbattle-goldspeedframe" },
      title = { x = 84, y = 22, w = 168, scale = 1 },
      text  = { x = 84, y = 43, w = 119, scale = 1 },
      line2 = { x = 84, y = 61, w = 168, scale = 1 },
      bar   = { x = 19, y = 81, w = 239, h = 2 },
      more  = { x = 252, y = 43 } },
    { key = "loottoast-nzoth", name = "N'Zoth", atlas = "loottoast-nzoth",
      w = 277, h = 98, gap = -6,
      icon  = { x = 22, y = 23, size = 48, shape = "square" },
      title = { x = 84, y = 23, w = 168, scale = 1 },
      text  = { x = 84, y = 43, w = 119, scale = 1 },
      line2 = { x = 84, y = 60, w = 168, scale = 1 },
      bar   = { x = 45, y = 84, w = 188, h = 3 },
      more  = { x = 252, y = 43 } },
    { key = "shop-toast", name = "Blue & Gold", atlas = "shop-toast",
      w = 277, h = 98,
      icon  = { x = 23, y = 25, size = 48, shape = "square" },
      title = { x = 80, y = 26, w = 178, scale = 1 },
      text  = { x = 80, y = 43, w = 129, scale = 1 },
      line2 = { x = 80, y = 57, w = 178, scale = 1 },
      bar   = { x = 18, y = 75, w = 240, h = 2 },
      more  = { x = 258, y = 43 } },
    { key = "loottoast-oribos", name = "Oribos", atlas = "loottoast-oribos",
      w = 276, h = 96,
      icon  = { x = 25, y = 24, size = 48, shape = "square" },
      title = { x = 81, y = 19, w = 178, scale = 1 },
      text  = { x = 84, y = 41, w = 119, scale = 1 },
      line2 = { x = 84, y = 60, w = 168, scale = 1 },
      bar   = { x = 21, y = 79, w = 235, h = 2 },
      more  = { x = 252, y = 41 } },
    { key = "loottoast-camp", name = "Camp", atlas = "loottoast-camp",
      w = 271, h = 85,
      icon  = { x = 18, y = 18, size = 48, shape = "square" },
      title = { x = 78, y = 13, w = 188, scale = 1 },
      text  = { x = 82, y = 35, w = 123, scale = 1 },
      line2 = { x = 82, y = 53, w = 172, scale = 1 },
      bar   = { x = 17, y = 70, w = 235, h = 1 },
      more  = { x = 254, y = 35 } },
    { key = "loottoast-glow", name = "Glowing", atlas = "loottoast-glow",
      w = 281, h = 115, gap = -22,
      icon  = { x = 26, y = 33, size = 48, shape = "square", frame = "ui-glyphframe-glow" },
      title = { x = 85, y = 31, w = 174, size = 14 },
      text  = { x = 86, y = 54, w = 118, scale = 1 },
      line2 = { x = 86, y = 71, w = 167, scale = 1 },
      bar   = { x = 20, y = 90, w = 240, h = 2 },
      more  = { x = 253, y = 54 } },
    { key = "LegendaryToast-background", name = "Legendary", atlas = "LegendaryToast-background",
      w = 281, h = 115,
      icon  = { x = 48, y = 35, size = 42, shape = "square", frame = "ui-icon-questborder" },
      title = { x = 101, y = 29, w = 156, scale = 1 },
      text  = { x = 103, y = 50, w = 106, scale = 1 },
      line2 = { x = 103, y = 67, w = 155, scale = 1 },
      bar   = { x = 117, y = 85, w = 140, h = 2 },
      more  = { x = 258, y = 50 } },
    { key = "MountToast-background", name = "Buckle Up", atlas = "MountToast-background",
      w = 281, h = 115,
      icon  = { x = 28, y = 32, size = 48, shape = "square" },
      title = { x = 85, y = 28, w = 169, scale = 1 },
      text  = { x = 88, y = 54, w = 117, scale = 1 },
      line2 = { x = 88, y = 71, w = 166, scale = 1 },
      bar   = { x = 100, y = 95, w = 82, h = 2 },
      more  = { x = 254, y = 54 } },
    { key = "PetToast-background", name = "Wooden Chest", atlas = "PetToast-background",
      w = 281, h = 115,
      icon  = { x = 29, y = 36, size = 48, shape = "square" },
      title = { x = 88, y = 27, w = 174, font = "skurri", size = 14 },
      text  = { x = 88, y = 51, w = 167, scale = 1 },
      line2 = { x = 88, y = 69, w = 167, scale = 1 },
      bar   = { x = 20, y = 89, w = 240, h = 2 },
      more  = { x = 265, y = 100 } },
    { key = "cosmetictoast-background", name = "Transmogrification", atlas = "cosmetictoast-background",
      w = 281, h = 115, gap = -8,
      icon  = { x = 36, y = 44, size = 42, shape = "square" },
      title = { x = 36, y = 27, w = 174, size = 14 },
      text  = { x = 89, y = 50, w = 106, scale = 1 },
      line2 = { x = 89, y = 70, w = 155, scale = 1 },
      bar   = { x = 78, y = 12, w = 124, h = 3 },
      more  = { x = 244, y = 50 } },
    { key = "Garr_MissionToast", name = "Metal", atlas = "Garr_MissionToast",
      w = 317, h = 82, gap = -6,
      icon  = { x = 26, y = 15, size = 48, shape = "square" },
      title = { x = 86, y = 15, w = 191, size = 14 },
      text  = { x = 86, y = 34, w = 143, scale = 1 },
      line2 = { x = 86, y = 47, w = 191, scale = 1 },
      bar   = { x = 8, y = 72, w = 297, h = 1 },
      more  = { x = 277, y = 34 } },
    { key = "Garr_Toast", name = "Garrison", atlas = "Garr_Toast",
      w = 317, h = 82,
      icon  = { x = 20, y = 19, size = 40, shape = "square" },
      title = { x = 78, y = 17, w = 194, font = "morpheus", size = 14 },
      text  = { x = 78, y = 35, w = 145, scale = 1 },
      line2 = { x = 78, y = 46, w = 194, scale = 1 },
      bar   = { x = 78, y = 60, w = 194, h = 2 },
      more  = { x = 272, y = 35 } },
    { key = "ShipMission_Toast", name = "Blue Steel", atlas = "ShipMission_Toast",
      w = 317, h = 82,
      icon  = { x = 25, y = 15, size = 48, shape = "square" },
      title = { x = 83, y = 14, w = 204, size = 16 },
      text  = { x = 83, y = 35, w = 155, scale = 1 },
      line2 = { x = 83, y = 50, w = 204, scale = 1 },
      bar   = { x = 83, y = 63, w = 204, h = 1 },
      more  = { x = 287, y = 35 } },
    { key = "Garr_MissionToast-Blank", name = "Bordered Parchment", atlas = "Garr_MissionToast-Blank",
      w = 272, h = 59, gap = 24,
      icon  = { x = 0, y = 1, size = 59, shape = "square", frame = "ui-achievement-iconframe" },
      title = { x = 77, y = 7, w = 176, scale = 1 },
      text  = { x = 77, y = 24, w = 127, scale = 1 },
      line2 = { x = 77, y = 39, w = 176, scale = 1 },
      bar   = { x = 77, y = 53, w = 176, h = 3 },
      more  = { x = 253, y = 24 } },
    { key = "CacheToast", name = "Ship Crate", atlas = "CacheToast",
      w = 276, h = 96,
      icon  = { x = 29, y = 25, size = 48, shape = "square" },
      title = { x = 86, y = 21, w = 158, scale = 1 },
      text  = { x = 90, y = 45, w = 154, scale = 1 },
      line2 = { x = 90, y = 60, w = 154, scale = 1 },
      bar   = { x = 20, y = 91, w = 240, h = 1 },
      more  = { x = 265, y = 100 } },
    { key = "transmog-toast-bg", name = "Purple Glow", atlas = "transmog-toast-bg",
      w = 253, h = 75, gap = -6,
      icon  = { x = 18, y = 18, size = 38, shape = "square" },
      title = { x = 64, y = 19, w = 170, size = 11 },
      text  = { x = 64, y = 33, w = 170, scale = 1 },
      line2 = { x = 64, y = 45, w = 170, scale = 1 },
      bar   = { x = 15, y = 67, w = 221, h = 2 },
      more  = { x = 236, y = 70 } },
    { key = "recipetoast-bg", name = "Parchment", atlas = "recipetoast-bg",
      w = 312, h = 89, gap = 0,
      icon  = { x = 22, y = 16, size = 56, shape = "circle" },
      title = { x = 88, y = 15, w = 200, scale = 1 },
      text  = { x = 89, y = 38, w = 199, scale = 1 },
      line2 = { x = 89, y = 56, w = 199, scale = 1 },
      bar   = { x = 21, y = 84, w = 270, h = 2 },
      more  = { x = 304, y = 81 } },
    { key = "campaign_alliance", name = "Alliance Parchment", atlas = "campaign_alliance",
      w = 304, h = 69,
      icon  = { x = 0, y = 0, size = 60, shape = "square" },
      title = { x = 73, y = 7, w = 227, size = 17 },
      text  = { x = 73, y = 29, w = 212, scale = 1 },
      line2 = { x = 73, y = 43, w = 212, scale = 1 },
      bar   = { x = 0, y = 59, w = 304, h = 1 },
      more  = { x = 265, y = 100 } },
    { key = "campaign_horde", name = "Horde Parchment", atlas = "campaign_horde",
      w = 304, h = 69,
      icon  = { x = 0, y = 0, size = 60, shape = "square" },
      title = { x = 73, y = 7, w = 227, scale = 1 },
      text  = { x = 73, y = 29, w = 212, scale = 1 },
      line2 = { x = 73, y = 43, w = 212, scale = 1 },
      bar   = { x = 0, y = 59, w = 304, h = 1 },
      more  = { x = 265, y = 100 } },
    { key = "storyheader-bg", name = "Magic Book", atlas = "storyheader-bg",
      w = 304, h = 69,
      icon  = { x = 9, y = 9, size = 48, shape = "circle", frame = "arcane_circular_frame" },
      title = { x = 73, y = 7, w = 223, font = "morpheus", size = 15 },
      text  = { x = 73, y = 28, w = 223, scale = 1 },
      line2 = { x = 73, y = 42, w = 223, scale = 1 },
      bar   = { x = 0, y = 0, w = 304, h = 1 },
      more  = { x = 302, y = 63 } },
    { key = "talkingheads-alliance-textbackground", name = "Alliance Light", atlas = "talkingheads-alliance-textbackground",
      w = 300, h = 80,
      icon  = { x = 17, y = 17, size = 48, shape = "square" },
      title = { x = 80, y = 16, w = 163, size = 15 },
      text  = { x = 80, y = 36, w = 114, scale = 1 },
      line2 = { x = 80, y = 53, w = 163, scale = 1 },
      bar   = { x = 31, y = 77, w = 240, h = 2 },
      more  = { x = 243, y = 36 } },
    { key = "talkingheads-textbackground", name = "Soft Transparency", atlas = "talkingheads-textbackground",
      w = 280, h = 80,
      icon  = { x = 17, y = 16, size = 48, shape = "square" },
      title = { x = 82, y = 15, w = 174, size = 14 },
      text  = { x = 82, y = 35, w = 125, scale = 1 },
      line2 = { x = 82, y = 52, w = 174, scale = 1 },
      bar   = { x = 20, y = 89, w = 240, h = 2 },
      more  = { x = 256, y = 35 } },
    { key = "communities-chat-body-remove", name = "Aggro", atlas = "communities-chat-body-remove",
      w = 300, h = 56,
      icon  = { x = 4, y = 4, size = 48, shape = "square" },
      title = { x = 68, y = 4, w = 224, scale = 1 },
      text  = { x = 68, y = 23, w = 175, scale = 1 },
      line2 = { x = 68, y = 40, w = 224, scale = 1 },
      bar   = { x = 1, y = 56, w = 300, h = 3 },
      more  = { x = 292, y = 23 } },
    { key = "communities-chat-body-add", name = "Calm", atlas = "communities-chat-body-add",
      w = 300, h = 56,
      icon  = { x = 4, y = 4, size = 48, shape = "square" },
      title = { x = 68, y = 4, w = 224, scale = 1 },
      text  = { x = 68, y = 23, w = 175, scale = 1 },
      line2 = { x = 68, y = 40, w = 224, scale = 1 },
      bar   = { x = 1, y = 56, w = 300, h = 3 },
      more  = { x = 292, y = 23 } },
    { key = "communities-nav-button-green-normal", name = "Emerald Green", atlas = "communities-nav-button-green-normal",
      w = 224, h = 80,
      icon  = { x = 19, y = 16, size = 48, shape = "square" },
      title = { x = 79, y = 16, w = 124, scale = 1 },
      text  = { x = 79, y = 30, w = 124, scale = 1 },
      line2 = { x = 79, y = 52, w = 124, scale = 1 },
      bar   = { x = 20, y = 89, w = 240, h = 2 },
      more  = { x = 203, y = 41 } },
    { key = "ui-lfg-dungeontoast", name = "The Dungeon", atlas = "ui-lfg-dungeontoast",
      w = 338, h = 72,
      icon  = { x = 14, y = 13, size = 46, shape = "square" },
      title = { x = 80, y = 17, w = 228, scale = 1 },
      text  = { x = 80, y = 32, w = 179, scale = 1 },
      line2 = { x = 80, y = 44, w = 227, scale = 1 },
      bar   = { x = 80, y = 58, w = 227, h = 3 },
      more  = { x = 308, y = 32 } },
    { key = "ui-classtrainer-detailheaderleft", name = "Gradient Black", file = 130964, fw = 256, fh = 64,
      w = 256, h = 64,
      icon  = { x = 8, y = 6, size = 37, shape = "square" },
      title = { x = 53, y = 6, w = 203, scale = 1 },
      text  = { x = 53, y = 20, w = 167, scale = 1 },
      line2 = { x = 53, y = 32, w = 203, scale = 1 },
      bar   = { x = 5, y = 49, w = 251, h = 3 },
      more  = { x = 256, y = 21 } },
    { key = "ui-friendsframe-buttonspatch", name = "Stone Slab", file = 131127, fw = 256, fh = 64,
      w = 300, h = 64,
      icon  = { x = 35, y = 7, size = 48, shape = "square" },
      title = { x = 90, y = 11, w = 167, scale = 1 },
      text  = { x = 90, y = 27, w = 118, scale = 1 },
      line2 = { x = 90, y = 41, w = 167, scale = 1 },
      bar   = { x = 35, y = 55, w = 224, h = 2 },
      more  = { x = 257, y = 27 } },
    { key = "ui-readycheckframe", name = "Ornate Carvings", file = 136825, fw = 512, fh = 128,
      w = 400, h = 96,
      icon  = { x = 7, y = 5, size = 35, shape = "circle" },
      title = { x = 47, y = 19, w = 188, size = 14, justify = "CENTER" },
      text  = { x = 57, y = 36, w = 129, scale = 1 },
      line2 = { x = 18, y = 49, w = 217, scale = 1 },
      bar   = { x = 20, y = 89, w = 240, h = 2 },
      more  = { x = 235, y = 36 } },
    { key = "lfr-texture", name = "Centered Circle", file = 575645, fw = 512, fh = 256, crop = { 0, 78, 289, 70 },
      w = 289, h = 63, gap = 30,
      icon  = { x = 113, y = 4, size = 57, shape = "circle" },
      title = { x = 0, y = -12, w = 289, size = 14, justify = "CENTER" },
      text  = { x = 4, y = 41, w = 118, size = 10 },
      line2 = { x = 0, y = 57, w = 288, scale = 1 },
      bar   = { x = 0, y = 54, w = 289, h = 3 },
      more  = { x = 287, y = 41 } },
    { key = "raf_textures", name = "Blizzard", file = 925997, fw = 512, fh = 512, crop = { 31, 109, 295, 83 },
      w = 295, h = 83,
      icon  = { x = 20, y = 19, size = 48, shape = "square", frame = "ui-icon-questborder" },
      title = { x = 80, y = 23, w = 194, size = 15 },
      text  = { x = 80, y = 47, w = 145, scale = 1 },
      line2 = { x = 80, y = 59, w = 194, scale = 1 },
      bar   = { x = 7, y = 79, w = 279, h = 1 },
      more  = { x = 274, y = 47 } },
}

local BY_KEY = {}
for _, s in ipairs(STYLES) do BY_KEY[s.key] = s end
TS.STYLES = STYLES
TS.DEFAULT = "faction"

-- ── Lookup ──────────────────────────────────────────────────────────────────
local _atlasOK = {}
local function HasAtlas(name)
    if _atlasOK[name] == nil then
        local ok, info = pcall(C_Texture.GetAtlasInfo, name)
        _atlasOK[name] = (ok and info) and true or false
    end
    return _atlasOK[name]
end

-- A game file this client has (a file style draws a green square without it)
local _fileOK = {}
local function HasFile(id)
    if _fileOK[id] == nil then
        local known = C_UIFileAsset and C_UIFileAsset.IsKnownFile
        local ok, has = true, true
        if known then ok, has = pcall(known, id) end
        _fileOK[id] = (not ok) or has and true or false
    end
    return _fileOK[id]
end

local function SkinOn()
    return BigNoteBoxDB and BigNoteBoxDB.skinMode and true or false
end

-- Whether a style can be drawn on this client right now (art present, skin
-- mode on for the skin style). The faction style asks its pick.
function TS.Usable(def)
    if not def then return false end
    if def.faction then
        local pick = def.pick and def.pick[UnitFactionGroup("player") or ""]
        return pick ~= nil and TS.Usable(BY_KEY[pick])
    end
    if def.skinOnly and not SkinOn() then return false end
    if def.atlas and not HasAtlas(def.atlas) then return false end
    if def.file and not HasFile(def.file) then return false end
    return true
end

-- key -> the style def to draw: the faction style becomes its Horde /
-- Alliance entry, an unknown or unusable one becomes plain. A lab override
-- (TS.SetOverride) wins while set.
local _override = nil
function TS.Resolve(key)
    if _override then return _override end
    local def = BY_KEY[key or TS.DEFAULT] or BY_KEY[TS.DEFAULT]
    if def.faction then
        local pick = def.pick[UnitFactionGroup("player") or ""]
        def = BY_KEY[pick or ""]
    end
    if not TS.Usable(def) then def = BY_KEY.plain end
    return def
end

function TS.Get(key) return BY_KEY[key] end

-- A style's name: its locale key, else the lab name it was exported with
function TS.Label(def)
    if def.label and BNB.HasL(def.label) then return L[def.label] end
    return def.name or def.key
end

-- The player's chosen style key (nil = the default, the faction style)
function TS.Current()
    local db = BigNoteBoxDB
    return (db and db.toastStyle) or TS.DEFAULT
end

-- Styles the player can pick here, in list order: { { key, label }, ... }
function TS.List()
    local out = {}
    for _, s in ipairs(STYLES) do
        if TS.Usable(s) then out[#out + 1] = { key = s.key, label = TS.Label(s) } end
    end
    return out
end

-- The Toast Lab's live preview of an entry being made: every toast and the
-- anchor draw it until cleared with nil
function TS.SetOverride(def)
    _override = def
    if BNB.Toast and BNB.Toast.Restyle then BNB.Toast.Restyle() end
end

-- ── Fonts ───────────────────────────────────────────────────────────────────
-- The game's own fonts a style may name (every client has these files);
-- anything else is a BNB.FONTS id (bundled fonts, font packs)
TS.GAME_FONTS = {
    { key = "frizqt",   label = "Friz Quadrata", path = "Fonts\\FRIZQT__.TTF" },
    { key = "arialn",   label = "Arial Narrow",  path = "Fonts\\ARIALN.TTF" },
    { key = "skurri",   label = "Skurri",        path = "Fonts\\skurri.ttf" },
    { key = "morpheus", label = "Morpheus",      path = "Fonts\\MORPHEUS.TTF" },
}
local GAME_FONT = {}
for _, g in ipairs(TS.GAME_FONTS) do GAME_FONT[g.key] = g end

-- The font object each text part starts from (its colour too)
TS.TEXT_OBJ = { title = "GameFontNormal", text = "GameFontNormalSmall", line2 = "GameFontHighlightSmall" }

-- A BNB.FONTS def for exactly this id (GetFontDef falls back to the default)
local function FontDef(key)
    local def = BNB.GetFontDef and BNB.GetFontDef(key)
    return (def and def.id == key) and def or nil
end

-- key -> file path, latinOnly; nil = the font object (no key, WoW Default,
-- a font pack that is not installed)
function TS.FontPath(key)
    if not key then return nil end
    local g = GAME_FONT[key]
    if g then return g.path, true end
    local def = FontDef(key)
    if not def or def._isWoW then return nil end
    return def.regular, (def.set or "latin") == "latin" and not def._isLSM
end

function TS.FontLabel(key)
    if not key then return nil end
    if GAME_FONT[key] then return GAME_FONT[key].label end
    local def = FontDef(key)
    return def and def.label or (key .. " (missing)")
end

-- The size a text part draws at, in px: its own, else the font object's x scale
function TS.TextSize(part, box)
    if box and box.size then return box.size end
    local obj = _G[TS.TEXT_OBJ[part] or "GameFontNormal"]
    local base = obj and select(2, obj:GetFont()) or 12
    return base * ((box and box.scale) or 1)
end

-- ── Drawing ─────────────────────────────────────────────────────────────────
local DEFAULT_ICON = "Interface\\AddOns\\BigNoteBox\\Assets\\icon"

-- SetAtlas with any earlier SetTexCoord cleared (resetTexCoords, 4th arg)
local function SetAtlasClean(tex, atlas)
    tex:SetTexCoord(0, 1, 0, 1)
    tex:SetAtlas(atlas, false, nil, true)
end

local function Flip(l, r, t, b, flip)
    if flip == "h" or flip == "hv" then l, r = r, l end
    if flip == "v" or flip == "hv" then t, b = b, t end
    return l, r, t, b
end

-- The toast frame's own parts, made once per frame
function TS.Build(f)
    if f._tsBuilt then return end
    f._tsBuilt = true
    local art = f:CreateTexture(nil, "BACKGROUND")
    art:SetAllPoints()
    f._art = art

    local icon = f:CreateTexture(nil, "ARTWORK")
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    f._icon = icon
    local border = f:CreateTexture(nil, "OVERLAY")
    f._iconBorder = border
    f._iconFrame  = f:CreateTexture(nil, "OVERLAY")

    -- Each text keeps its font object and colour: a style's font is set on
    -- top, and going back to the object resets the colour
    local function Text(part, col)
        local fs = f:CreateFontString(nil, "OVERLAY", TS.TEXT_OBJ[part])
        fs:SetWordWrap(false)
        fs._part, fs._fontObj, fs._col = part, TS.TEXT_OBJ[part], col
        if col then fs:SetTextColor(col[1], col[2], col[3]) end
        return fs
    end
    f._lbl   = Text("title")
    f._sub   = Text("text",  { 0.65, 0.65, 0.65 })
    f._line2 = Text("line2", { 0.85, 0.85, 0.85 })

    -- The note has a waypoint the situation places: a small pin on the
    -- icon's top-right corner
    local pin = f:CreateTexture(nil, "OVERLAY", nil, 3)
    pin:SetSize(16, 16)
    pin:SetPoint("CENTER", icon, "TOPRIGHT", -2, -2)
    pin:Hide()
    f._pin = pin

    local more = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    more:SetJustifyH("RIGHT")
    more:SetTextColor(1, 0.82, 0)
    more:Hide()
    f._more = more

    local bar = f:CreateTexture(nil, "OVERLAY", nil, 2)
    bar:SetColorTexture(0.3, 0.75, 0.3, 0.9)
    f._bar = bar
end

-- The style's font and size on a text; only when they changed, since a
-- toast is laid out again on every fill
local function SetTextFont(fs, box)
    local path, latinOnly = TS.FontPath(box.font)
    if path and latinOnly and BNB.IsCJKClient and BNB.IsCJKClient() then path = nil end
    local size = TS.TextSize(fs._part, box)
    local sig = (path or "") .. "|" .. size
    if fs._fontSig == sig then return end
    fs._fontSig = sig
    local col = fs._col
    if path then
        fs:SetTextScale(1)
        BNB.SetFontSafe(fs, path, size, fs._fontObj)
    else
        -- The font object keeps the game's per-alphabet fallback; the size
        -- comes from the text scale
        BNB.SetFontSafe(fs, nil, nil, fs._fontObj)
        local obj = _G[fs._fontObj]
        local base = obj and select(2, obj:GetFont()) or size
        fs:SetTextScale(size / base)
    end
    if col then fs:SetTextColor(col[1], col[2], col[3]) end
end

-- Left / Center / Right go by the anchor, not SetJustifyH: a justify change
-- on a box-wide FontString did not redraw (Center held until the font
-- changed, Right never showed; Dukul, 2026-10-07). The string sits at the
-- box's left edge, middle or right edge at its own width, and FitText cuts
-- it at the box width
local JUSTIFY_AT = { LEFT = { "TOPLEFT", 0 }, CENTER = { "TOP", 0.5 }, RIGHT = { "TOPRIGHT", 1 } }

-- After a SetText: the string's own width, the box width when it is longer
-- (word wrap is off, so it ends in "...")
local function FitText(fs)
    local box = fs._box
    if not box then return end
    fs:SetWidth(0)
    local w = box.w or 100
    if (fs:GetStringWidth() or 0) > w then fs:SetWidth(w) end
end

local function PlaceText(fs, box, f)
    fs:ClearAllPoints()
    fs._box = box
    if not box then fs:SetText(""); fs:Hide(); return end
    -- Font first: SetFontObject (inside SetTextFont) puts back the object's
    -- own justify
    SetTextFont(fs, box)
    local j = JUSTIFY_AT[box.justify or "LEFT"] or JUSTIFY_AT.LEFT
    fs:SetPoint(j[1], f, "TOPLEFT", box.x + (box.w or 100) * j[2], -box.y)
    fs:SetJustifyH(box.justify or "LEFT")
    fs:Show()
    FitText(fs)
end

-- Lays f out as def: size, background, icon box, text boxes, bar, more.
-- Content (icon texture, texts) is the caller's; the bar's width is reset
-- to full (the engine shortens it as time runs).
function TS.Apply(f, def)
    TS.Build(f)
    def = def or BY_KEY.plain
    f._style = def
    f:SetSize(def.w, def.h)

    -- Background: a backdrop for plain / skin, a picture for the rest
    local art = f._art
    if def.back then
        art:Hide()
        if def.back == "skin" and SkinOn() and BNB.GetSkinPreset then
            local p = BNB.GetSkinPreset()
            local r, g, b = BNB.SkinColourOf(p)
            local br, bg, bb = BNB.SkinBorderOf(p)
            BNB.SetBackdrop(f, r, g, b, BNB.GetSkinBgAlpha(), br, bg, bb, 1)
        else
            BNB.SetBackdrop(f, 0.06, 0.06, 0.09, 0.94, 0.40, 0.40, 0.42, 1)
        end
    else
        BNB.SetBackdrop(f, 0, 0, 0, 0, 0, 0, 0, 0)
        if def.atlas and def.flip then
            -- A flipped atlas: its file and corners, mirrored
            local info = C_Texture.GetAtlasInfo(def.atlas)
            art:SetTexture(info.file or info.filename)
            art:SetTexCoord(Flip(info.leftTexCoord, info.rightTexCoord,
                                 info.topTexCoord, info.bottomTexCoord, def.flip))
        elseif def.atlas then
            -- Toast frames are reused: a crop or flip from the last style
            -- must not carry over (SetAtlas keeps old texcoords unless told
            -- to reset them; the Azerite art drew as a zoomed patch, Dukul
            -- 2026-10-07)
            SetAtlasClean(art, def.atlas)
        elseif def.file then
            art:SetTexture(def.file)
            local W, H = def.fw, def.fh
            local c = def.crop
            if c and W and H then
                -- Half-texel inset, as the icon frames: no neighbour line
                art:SetTexCoord(Flip((c[1] + 0.5) / W, (c[1] + c[3] - 0.5) / W,
                                     (c[2] + 0.5) / H, (c[2] + c[4] - 0.5) / H, def.flip))
            else
                art:SetTexCoord(Flip(0, 1, 0, 1, def.flip))
            end
        end
        art:Show()
    end

    -- Icon, its shape, frame and border
    local ib, icon = def.icon, f._icon
    if ib then
        icon:ClearAllPoints()
        icon:SetSize(ib.size, ib.size)
        icon:SetPoint("TOPLEFT", f, "TOPLEFT", ib.x, -ib.y)
        icon:Show()
        local IFL = BNB.IconFrameLayer
        local fdef = ib.frame and BNB.IconFrames and BNB.IconFrames.Get(ib.frame)
        if IFL and fdef then
            IFL.Apply(icon, f._iconFrame, fdef, ib.size)
        elseif IFL then
            IFL.HideTex(f._iconFrame)
            IFL.SetShape(icon, ib.shape)
        end
        local bd = ib.border
        local bdOK = bd and ((bd.atlas and HasAtlas(bd.atlas)) or bd.file)
        if bdOK then
            local pad = bd.pad or 0
            if bd.atlas then SetAtlasClean(f._iconBorder, bd.atlas)
            else f._iconBorder:SetTexture(bd.file); f._iconBorder:SetTexCoord(0, 1, 0, 1) end
            f._iconBorder:ClearAllPoints()
            f._iconBorder:SetPoint("TOPLEFT", icon, "TOPLEFT", -pad, pad)
            f._iconBorder:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", pad, -pad)
            f._iconBorder:Show()
        else
            f._iconBorder:Hide()
        end
    else
        icon:Hide(); f._iconBorder:Hide()
        if BNB.IconFrameLayer then BNB.IconFrameLayer.HideTex(f._iconFrame) end
    end

    -- A note's own icon frame from the last fill (BNB.ApplyIconFrame)
    if icon._ifTex and BNB.IconFrameLayer then BNB.IconFrameLayer.HideTex(icon._ifTex) end
    f._pin:Hide()

    PlaceText(f._lbl, def.title, f)
    PlaceText(f._sub, def.text, f)
    PlaceText(f._line2, def.line2, f)

    local bar = f._bar
    bar:ClearAllPoints()
    if def.bar then
        bar:SetPoint("TOPLEFT", f, "TOPLEFT", def.bar.x, -def.bar.y)
        bar:SetHeight(def.bar.h)
        bar:SetWidth(def.bar.w)
        f._barW = def.bar.w
    else
        f._barW = nil
        bar:Hide()
    end

    f._more:ClearAllPoints()
    local m = def.more or { x = def.w - 6, y = def.h - 18 }
    f._more:SetPoint("TOPRIGHT", f, "TOPLEFT", m.x, -m.y)
end

-- The waypoint pin: the game's chat map pin where the client has it
local PIN_ATLAS = "Waypoint-MapPin-ChatIcon"
local PIN_FILE  = "Interface\\Icons\\INV_Misc_Map_01"

-- Fills the content of a laid-out toast (used by the engine and the lab):
-- c = { icon, title, titleColor, text, line2, pin, noIcon, iconSetup }.
-- iconSetup(tex, f, ownFrame) runs after the icon is set (a note's portrait
-- or its own icon frame); it returns true when it drew a frame, which then
-- replaces the style's frame and border. ownFrame = the style keeps its own
-- border: iconSetup must not draw the note's frame (portrait only)
function TS.Fill(f, c)
    local icon = f._icon
    local def = f._style
    if c.noIcon or not (def and def.icon) then
        icon:Hide(); f._iconBorder:Hide()
        if BNB.IconFrameLayer then BNB.IconFrameLayer.HideTex(f._iconFrame) end
    else
        icon:SetTexture(c.icon or DEFAULT_ICON)
        local own = def.icon.ownFrame and true or false
        if c.iconSetup and c.iconSetup(icon, f, own) and not own then
            f._iconBorder:Hide()
            if BNB.IconFrameLayer then BNB.IconFrameLayer.HideTex(f._iconFrame) end
        end
    end
    f._lbl:SetText(c.title or ""); FitText(f._lbl)
    local tc = c.titleColor
    if tc then f._lbl:SetTextColor(tc.r or 1, tc.g or 0.82, tc.b or 0, 1)
    else       f._lbl:SetTextColor(1, 0.82, 0, 1) end
    f._sub:SetText(c.text or ""); FitText(f._sub)
    f._line2:SetText(c.line2 or ""); FitText(f._line2)
    if c.pin and icon:IsShown() then
        if HasAtlas(PIN_ATLAS) then f._pin:SetAtlas(PIN_ATLAS)
        else f._pin:SetTexture(PIN_FILE) end
        f._pin:Show()
    else
        f._pin:Hide()
    end
end

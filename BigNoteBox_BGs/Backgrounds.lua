-- BigNoteBox_BGs Backgrounds.lua
--
-- The original sticky note background textures, moved out of BigNoteBox when
-- it switched to backgrounds from the game's own files (ALL-110).
-- A load-on-demand addon: BigNoteBox loads it with C_AddOns.LoadAddOn the
-- first time a sticky uses one of these, or when sticky settings open. If this
-- folder is missing or disabled, those stickies just draw their plain colour
-- and keep their saved choice.
--
-- Labels are BigNoteBox locale keys; see UI/StickyBackgrounds.lua there for
-- the entry fields.

local BNB = BigNoteBox
if not (BNB and BNB.RegisterStickyBackgrounds) then return end

local P = "Interface\\AddOns\\BigNoteBox_BGs\\"

BNB.RegisterStickyBackgrounds({
    { key = "bgtexture-01", label = "STICKY_BG_OLD_WHITE_PAPER", file = P .. "bgtexture-01.tga", mode = "stretch" },
    { key = "bgtexture-02", label = "STICKY_BG_DAMAGED_STONE",   file = P .. "bgtexture-02.tga", mode = "tile", anchor = "TOPLEFT", w = 256, h = 256 },
    { key = "bgtexture-03", label = "STICKY_BG_BLACK_MARBLE",    file = P .. "bgtexture-03.tga", mode = "tile", anchor = "TOPLEFT", w = 256, h = 256 },
    { key = "bgtexture-04", label = "STICKY_BG_GOLDEN_PAPER",    file = P .. "bgtexture-04.tga", mode = "stretch" },
    { key = "bgtexture-05", label = "STICKY_BG_OLD_DUTCH_PAPER", file = P .. "bgtexture-05.tga", mode = "stretch" },
    { key = "bgtexture-06", label = "STICKY_BG_PARCHMENT",       file = P .. "bgtexture-06.tga", mode = "tile", anchor = "TOPLEFT", w = 256, h = 256 },
    { key = "bgtexture-08", label = "STICKY_BG_CREASED_PAPER",   file = P .. "bgtexture-08.tga", mode = "tile", anchor = "TOPLEFT", w = 256, h = 256 },
    { key = "bgtexture-12", label = "STICKY_BG_DARK_MARBLE",     file = P .. "bgtexture-12.tga", mode = "stretch" },
    { key = "bgtexture-16", label = "STICKY_BG_SANDSTONE",       file = P .. "bgtexture-16.tga", mode = "stretch" },
    { key = "bgtexture-17", label = "STICKY_BG_WORN_LEATHER",    file = P .. "bgtexture-17.tga", mode = "stretch" },
    { key = "bgtexture-19", label = "STICKY_BG_DARK_GRANITE",    file = P .. "bgtexture-19.tga", mode = "tile", anchor = "TOPLEFT", w = 256, h = 256 },
    { key = "bgtexture-20", label = "STICKY_BG_DARK_STONE",      file = P .. "bgtexture-20.tga", mode = "stretch" },
})

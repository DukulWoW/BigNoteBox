-- BigNoteBox Assets/Search/SearchThemes.lua -- Search bar themes
--
-- One Register call per theme. The theme's art goes in its own folder next
-- to this file, with these file names (32x32 TGA, the ornament any size):
--
--   s-bg  s-top  s-bottom  s-left  s-right
--   s-top-left  s-top-right  s-bottom-left  s-bottom-right  s-ornament
--
-- The smallest theme is a folder and a name:
--
--   Register({ name = "My theme", folder = "MyTheme" })
--
-- It then uses Eye of Kilrogg's layout, which fits art drawn on the same
-- 32 px grid. To tune it, /bnb searchlayout (debug mode on), pick it with
-- the Theme button, adjust, and Export: that gives the full Register call
-- with layout and size, to paste here in place of the short one.
--
-- A theme without an ornament: files = { ornament = false }.
--
-- Optional middle pieces: s-top-ornament and s-bottom-ornament sit in the
-- middle of the top and bottom edge, with the edge art on either side:
--
--   topleft  top  topornament  top2  topright
--
-- top2 / bottom2 reuse s-top / s-bottom. A theme using them needs its own
-- layout (The Eye below is the example). Any piece a layout leaves out is
-- simply not drawn, e.g. The Eye has no topleft, bottomleft or right.
--
-- A background of its own for the Oracle's results panel: panelBg =
-- "s-bg-results". It is tiled, not stretched, so its size must be a power of
-- two (128x128...), and the Forever highlight glow is drawn over it.
--
-- The selected result in the Oracle's list is tinted with highlight =
-- { r, g, b, alpha } (0-1 each). Left out, it is BigNoteBox gold.
--
-- NOTE: an addon update replaces this file. A theme of your own is safer in
-- a small addon of its own that calls BigNoteBox.RegisterSearchTheme with
-- path = "Interface\\AddOns\\<YourAddon>\\<folder>\\" instead of folder.

local Register = BigNoteBox.RegisterSearchTheme

-- Tuned by Dukul with the layout tool, 2026-09-26.
Register({
    name   = "Eye of Kilrogg",
    folder = "Kilrogg",
    layout = {
        bg          = { a1 = "TOPLEFT",     x1 =   8,     y1 =  -8,    a2 = "BOTTOMRIGHT", x2 =  -8,    y2 =   8     },
        top         = { a1 = "TOPLEFT",     x1 =  32,     y1 =   0,    a2 = "TOPRIGHT",    x2 = -32,    y2 = -32     },
        bottom      = { a1 = "BOTTOMLEFT",  x1 =  32,     y1 =  32,    a2 = "BOTTOMRIGHT", x2 = -32,    y2 =   0     },
        left        = { a1 = "TOPLEFT",     x1 =   0,     y1 = -32,    a2 = "BOTTOMLEFT",  x2 =  32,    y2 =  32     },
        right       = { a1 = "TOPRIGHT",    x1 = -32,     y1 = -32,    a2 = "BOTTOMRIGHT", x2 =   0,    y2 =  32     },
        topleft     = { a1 = "TOPLEFT",     x1 =   0,     y1 =   0,    a2 = "TOPLEFT",     x2 =  32,    y2 = -32     },
        topright    = { a1 = "TOPRIGHT",    x1 = -32,     y1 =   0,    a2 = "TOPRIGHT",    x2 =   0,    y2 = -32     },
        bottomleft  = { a1 = "BOTTOMLEFT",  x1 =   0,     y1 =  32,    a2 = "BOTTOMLEFT",  x2 =  32,    y2 =   0     },
        bottomright = { a1 = "BOTTOMRIGHT", x1 = -32,     y1 =  32,    a2 = "BOTTOMRIGHT", x2 =   0,    y2 =   0     },
        ornament    = { a1 = "TOPLEFT",     x1 = -52.67,  y1 =   4.67, a2 = "TOPLEFT",     x2 =  40.67, y2 = -88.67 },
        text        = { a1 = "TOPLEFT",     x1 =  36,     y1 = -21,    a2 = "BOTTOMRIGHT", x2 = -32,    y2 =  19     },
    },
    size = { w = 500, h = 50, border = 24, borderY = 24 },
    highlight = { 0.40, 0.73, 0.42, 0.18 },   -- BigNoteBox green (#66bb6a)
})

-- Drawn by Dukul at 64 px on the 32 px grid, tuned with the layout tool,
-- 2026-09-26.
Register({
    name   = "Alliance",
    folder = "Alliance",
    layout = {
        bg          = { a1 = "TOPLEFT",     x1 =   8,     y1 =  -8,     a2 = "BOTTOMRIGHT", x2 =  -8,     y2 =   8     },
        top         = { a1 = "TOPLEFT",     x1 =  32,     y1 =   0,     a2 = "TOPRIGHT",    x2 = -32,     y2 = -32     },
        bottom      = { a1 = "BOTTOMLEFT",  x1 =  32,     y1 =  32,     a2 = "BOTTOMRIGHT", x2 = -32,     y2 =   0     },
        left        = { a1 = "TOPLEFT",     x1 =   0,     y1 = -32,     a2 = "BOTTOMLEFT",  x2 =  33.33,  y2 =  32     },
        right       = { a1 = "TOPRIGHT",    x1 = -33.33,  y1 = -32,     a2 = "BOTTOMRIGHT", x2 =   0,     y2 =  32     },
        topleft     = { a1 = "TOPLEFT",     x1 =   0,     y1 =   0,     a2 = "TOPLEFT",     x2 =  32,     y2 = -32     },
        topright    = { a1 = "TOPRIGHT",    x1 = -32,     y1 =   0,     a2 = "TOPRIGHT",    x2 =   0,     y2 = -32     },
        bottomleft  = { a1 = "BOTTOMLEFT",  x1 =   0,     y1 =  32,     a2 = "BOTTOMLEFT",  x2 =  32,     y2 =   0     },
        bottomright = { a1 = "BOTTOMRIGHT", x1 = -32,     y1 =  32,     a2 = "BOTTOMRIGHT", x2 =   0,     y2 =   0     },
        ornament    = { a1 = "TOPLEFT",     x1 = -12.67,  y1 =  12.67,  a2 = "TOPLEFT",     x2 =  80.67,  y2 = -80.67  },
        text        = { a1 = "TOPLEFT",     x1 =  36,     y1 = -21,     a2 = "BOTTOMRIGHT", x2 = -32,     y2 =  19     },
    },
    size = { w = 500, h = 50, border = 26, borderY = 26 },
    panelBg = "s-bg-results",
})

Register({
    name   = "Horde",
    folder = "Horde",
    layout = {
        bg          = { a1 = "TOPLEFT",     x1 =   8,     y1 =  -8,     a2 = "BOTTOMRIGHT", x2 =  -8,     y2 =   8     },
        top         = { a1 = "TOPLEFT",     x1 =  32,     y1 =   0,     a2 = "TOPRIGHT",    x2 = -32,     y2 = -32     },
        bottom      = { a1 = "BOTTOMLEFT",  x1 =  32,     y1 =  32,     a2 = "BOTTOMRIGHT", x2 = -32,     y2 =   0     },
        left        = { a1 = "TOPLEFT",     x1 =   0,     y1 = -32,     a2 = "BOTTOMLEFT",  x2 =  32,     y2 =  32     },
        right       = { a1 = "TOPRIGHT",    x1 = -32,     y1 = -32,     a2 = "BOTTOMRIGHT", x2 =   0,     y2 =  32     },
        topleft     = { a1 = "TOPLEFT",     x1 =   0,     y1 =   0,     a2 = "TOPLEFT",     x2 =  32,     y2 = -32     },
        topright    = { a1 = "TOPRIGHT",    x1 = -32,     y1 =   0,     a2 = "TOPRIGHT",    x2 =   0,     y2 = -32     },
        bottomleft  = { a1 = "BOTTOMLEFT",  x1 =   0,     y1 =  32,     a2 = "BOTTOMLEFT",  x2 =  32,     y2 =   0     },
        bottomright = { a1 = "BOTTOMRIGHT", x1 = -32,     y1 =  32,     a2 = "BOTTOMRIGHT", x2 =   0,     y2 =   0     },
        ornament    = { a1 = "TOPLEFT",     x1 = -49.67,  y1 =  28.67,  a2 = "TOPLEFT",     x2 =  43.67,  y2 = -64.67  },
        text        = { a1 = "TOPLEFT",     x1 =  36,     y1 = -21,     a2 = "BOTTOMRIGHT", x2 = -32,     y2 =  19     },
    },
    size = { w = 500, h = 50, border = 24, borderY = 24 },
    panelBg = "s-bg-results",
})

-- Full-height bracket on the left (no top/bottom-left corners), right end
-- is two corners with no edge between them, and a middle piece on the top
-- and bottom edge. A starting layout, not tuned yet: Dukul is redrawing
-- the art (2026-09-26). Registered so the layout tool can show it; keep it
-- out of the player's theme picker (ALL-69.4) until it is finished.
Register({
    name   = "The Eye",
    folder = "The-Eye",
    layout = {
        bg             = { a1 = "TOPLEFT",     x1 =  24, y1 =  -8, a2 = "BOTTOMRIGHT", x2 =  -8, y2 =   8 },
        top            = { a1 = "TOPLEFT",     x1 =  64, y1 =   0, a2 = "TOP",         x2 = -32, y2 = -32 },
        topornament    = { a1 = "TOP",         x1 = -32, y1 =   0, a2 = "TOP",         x2 =  32, y2 = -32 },
        top2           = { a1 = "TOP",         x1 =  32, y1 =   0, a2 = "TOPRIGHT",    x2 = -32, y2 = -32 },
        topright       = { a1 = "TOPRIGHT",    x1 = -32, y1 =   0, a2 = "TOPRIGHT",    x2 =   0, y2 = -32 },
        bottom         = { a1 = "BOTTOMLEFT",  x1 =  64, y1 =  32, a2 = "BOTTOM",      x2 = -32, y2 =   0 },
        bottomornament = { a1 = "BOTTOM",      x1 = -32, y1 =  32, a2 = "BOTTOM",      x2 =  32, y2 =   0 },
        bottom2        = { a1 = "BOTTOM",      x1 =  32, y1 =  32, a2 = "BOTTOMRIGHT", x2 = -32, y2 =   0 },
        bottomright    = { a1 = "BOTTOMRIGHT", x1 = -32, y1 =  32, a2 = "BOTTOMRIGHT", x2 =   0, y2 =   0 },
        left           = { a1 = "TOPLEFT",     x1 =   0, y1 =   0, a2 = "BOTTOMLEFT",  x2 =  64, y2 =   0 },
        ornament       = { a1 = "TOPLEFT",     x1 = -48, y1 =   0, a2 = "TOPLEFT",     x2 =  80, y2 = -64 },
        text           = { a1 = "TOPLEFT",     x1 =  84, y1 = -21, a2 = "BOTTOMRIGHT", x2 = -32, y2 =  19 },
    },
    size = { w = 500, h = 50, border = 24, borderY = 24 },
    highlight = { 0.40, 0.73, 0.42, 0.18 },   -- green, like Kilrogg
})

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
})

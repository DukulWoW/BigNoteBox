-- BigNoteBox Assets/Search/Kilrogg/theme.lua -- "Eye of Kilrogg" search bar theme
--
-- How a theme file works: Assets\Search\README.txt.

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

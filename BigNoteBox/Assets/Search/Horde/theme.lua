-- BigNoteBox Assets/Search/Horde/theme.lua -- "Horde" search bar theme
--
-- How a theme file works: Assets\Search\README.txt.

local Register = BigNoteBox.RegisterSearchTheme

Register({
    name   = "Horde",
    folder = "Horde",
    layout = {
        bg             = { a1 = "TOPLEFT", x1 = 8, y1 = -8, a2 = "BOTTOMRIGHT", x2 = -8, y2 = 8 },
        top            = { a1 = "TOPLEFT", x1 = 32, y1 = 0, a2 = "TOPRIGHT", x2 = -32, y2 = -32 },
        bottom         = { a1 = "BOTTOMLEFT", x1 = 32, y1 = 32, a2 = "BOTTOMRIGHT", x2 = -32, y2 = 0 },
        left           = { a1 = "TOPLEFT", x1 = 0, y1 = -32, a2 = "BOTTOMLEFT", x2 = 32, y2 = 32 },
        right          = { a1 = "TOPRIGHT", x1 = -32, y1 = -32, a2 = "BOTTOMRIGHT", x2 = 0, y2 = 32 },
        topleft        = { a1 = "TOPLEFT", x1 = 0, y1 = 0, a2 = "TOPLEFT", x2 = 32, y2 = -32 },
        topright       = { a1 = "TOPRIGHT", x1 = -32, y1 = 0, a2 = "TOPRIGHT", x2 = 0, y2 = -32 },
        bottomleft     = { a1 = "BOTTOMLEFT", x1 = 0, y1 = 32, a2 = "BOTTOMLEFT", x2 = 32, y2 = 0 },
        bottomright    = { a1 = "BOTTOMRIGHT", x1 = -32, y1 = 32, a2 = "BOTTOMRIGHT", x2 = 0, y2 = 0 },
        ornament       = { a1 = "TOPLEFT", x1 = -49.67, y1 = 28.67, a2 = "TOPLEFT", x2 = 43.67, y2 = -64.67 },
        text           = { a1 = "TOPLEFT", x1 = 36, y1 = -21, a2 = "BOTTOMRIGHT", x2 = -32, y2 = 19 },
    },
    size = { w = 500, h = 50, border = 24, borderY = 24 },
    panelLayout = {
        bg             = { a1 = "TOPLEFT", x1 = 8, y1 = -8, a2 = "BOTTOMRIGHT", x2 = -8, y2 = 8 },
        top            = { a1 = "TOPLEFT", x1 = 32, y1 = 0, a2 = "TOPRIGHT", x2 = -32, y2 = -32 },
        bottom         = { a1 = "BOTTOMLEFT", x1 = 32, y1 = 32, a2 = "BOTTOMRIGHT", x2 = -32, y2 = 0 },
        left           = { a1 = "TOPLEFT", x1 = 0, y1 = -32, a2 = "BOTTOMLEFT", x2 = 32, y2 = 32 },
        right          = { a1 = "TOPRIGHT", x1 = -32, y1 = -32, a2 = "BOTTOMRIGHT", x2 = 0, y2 = 32 },
        topleft        = { a1 = "TOPLEFT", x1 = 0, y1 = 0, a2 = "TOPLEFT", x2 = 32, y2 = -32 },
        topright       = { a1 = "TOPRIGHT", x1 = -32, y1 = 0, a2 = "TOPRIGHT", x2 = 0, y2 = -32 },
        bottomleft     = { a1 = "BOTTOMLEFT", x1 = 0, y1 = 32, a2 = "BOTTOMLEFT", x2 = 32, y2 = 0 },
        bottomright    = { a1 = "BOTTOMRIGHT", x1 = -32, y1 = 32, a2 = "BOTTOMRIGHT", x2 = 0, y2 = 0 },
        pornament1     = { a1 = "BOTTOMLEFT", x1 = 494.33, y1 = 3.67, a2 = "BOTTOMLEFT", x2 = 665, y2 = -81.67 },
        pornament2     = { a1 = "BOTTOMRIGHT", x1 = -169, y1 = 24.67, a2 = "BOTTOMRIGHT", x2 = -83.67, y2 = -7.33 },
    },
    panelSize = { border = 24, borderY = 24 },
    panelPos = { left = 0, right = 0, gap = 2, under = true },
    panelBg = "s-bg-results",
})

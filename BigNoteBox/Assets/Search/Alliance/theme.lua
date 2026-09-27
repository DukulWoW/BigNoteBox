-- BigNoteBox Assets/Search/Alliance/theme.lua -- "Alliance" search bar theme
--
-- How a theme file works: Assets\Search\README.txt.

local Register = BigNoteBox.RegisterSearchTheme

-- Drawn by Dukul at 64 px on the 32 px grid, tuned with the layout tool,
-- 2026-09-26.
Register({
    name   = "Alliance",
    folder = "Alliance",
    layout = {
        bg             = { a1 = "TOPLEFT", x1 = 8, y1 = -8, a2 = "BOTTOMRIGHT", x2 = -8, y2 = 8 },
        top            = { a1 = "TOPLEFT", x1 = 32, y1 = 0, a2 = "TOPRIGHT", x2 = -32, y2 = -32 },
        bottom         = { a1 = "BOTTOMLEFT", x1 = 32, y1 = 32, a2 = "BOTTOMRIGHT", x2 = -32, y2 = 0 },
        left           = { a1 = "TOPLEFT", x1 = 0, y1 = -32, a2 = "BOTTOMLEFT", x2 = 33.33, y2 = 32 },
        right          = { a1 = "TOPRIGHT", x1 = -33.33, y1 = -32, a2 = "BOTTOMRIGHT", x2 = 0, y2 = 32 },
        topleft        = { a1 = "TOPLEFT", x1 = 0, y1 = 0, a2 = "TOPLEFT", x2 = 32, y2 = -32 },
        topright       = { a1 = "TOPRIGHT", x1 = -32, y1 = 0, a2 = "TOPRIGHT", x2 = 0, y2 = -32 },
        bottomleft     = { a1 = "BOTTOMLEFT", x1 = 0, y1 = 32, a2 = "BOTTOMLEFT", x2 = 32, y2 = 0 },
        bottomright    = { a1 = "BOTTOMRIGHT", x1 = -32, y1 = 32, a2 = "BOTTOMRIGHT", x2 = 0, y2 = 0 },
        ornament       = { a1 = "TOPLEFT", x1 = -12.67, y1 = 12.67, a2 = "TOPLEFT", x2 = 80.67, y2 = -80.67 },
        text           = { a1 = "TOPLEFT", x1 = 36, y1 = -21, a2 = "BOTTOMRIGHT", x2 = -32, y2 = 19 },
    },
    size = { w = 500, h = 50, border = 26, borderY = 26 },
    panelLayout = {
        bg             = { a1 = "TOPLEFT", x1 = 8, y1 = -8, a2 = "BOTTOMRIGHT", x2 = -8, y2 = 8 },
        top            = { a1 = "TOPLEFT", x1 = 32, y1 = 0, a2 = "TOPRIGHT", x2 = -32, y2 = -32 },
        bottom         = { a1 = "BOTTOMLEFT", x1 = 32, y1 = 32, a2 = "BOTTOMRIGHT", x2 = -32, y2 = 0 },
        left           = { a1 = "TOPLEFT", x1 = 0, y1 = -32, a2 = "BOTTOMLEFT", x2 = 33.33, y2 = 32 },
        right          = { a1 = "TOPRIGHT", x1 = -33.33, y1 = -32, a2 = "BOTTOMRIGHT", x2 = 0, y2 = 32 },
        topleft        = { a1 = "TOPLEFT", x1 = 0, y1 = 0, a2 = "TOPLEFT", x2 = 32, y2 = -32 },
        topright       = { a1 = "TOPRIGHT", x1 = -32, y1 = 0, a2 = "TOPRIGHT", x2 = 0, y2 = -32 },
        bottomleft     = { a1 = "BOTTOMLEFT", x1 = 0, y1 = 32, a2 = "BOTTOMLEFT", x2 = 32, y2 = 0 },
        bottomright    = { a1 = "BOTTOMRIGHT", x1 = -32, y1 = 32, a2 = "BOTTOMRIGHT", x2 = 0, y2 = 0 },
        pornament1     = { a1 = "TOPLEFT", x1 = 456, y1 = -419, a2 = "TOPLEFT", x2 = 613.54, y2 = -497.77 },
        pornament2     = { a1 = "TOPRIGHT", x1 = -186, y1 = -414, a2 = "TOPRIGHT", x2 = -136.77, y2 = -463.23 },
    },
    panelSize = { border = 26, borderY = 26 },
    panelPos = { left = 0, right = 0, gap = 2, under = true },
    panelBg = "s-bg-results",
})

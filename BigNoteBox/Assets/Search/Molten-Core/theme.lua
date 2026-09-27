-- BigNoteBox Assets/Search/Molten-Core/theme.lua -- "Molten Core" search bar theme
--
-- How a theme file works: Assets\Search\README.txt.

local Register = BigNoteBox.RegisterSearchTheme

-- Drawn by Dukul at 64 px (2026-09-27). The bar: one long top, bottom and
-- background piece, a three-piece right end (s-middle-right is the right
-- edge), and the ornament covers the left end, which has no pieces. The
-- results panel has its own art (s-results-*) and background (s-bg-results,
-- a lava tile: tiled, since stretched it smeared, Dukul 2026-09-27) and no
-- top edge: it tucks under the bar.
Register({
    name   = "Molten Core",
    folder = "Molten-Core",
    layout = {
        bg             = { a1 = "TOPLEFT", x1 = 8, y1 = -8, a2 = "BOTTOMRIGHT", x2 = -8, y2 = 8 },
        top            = { a1 = "TOPLEFT", x1 = 19, y1 = 22, a2 = "TOPRIGHT", x2 = -45, y2 = -10 },
        bottom         = { a1 = "BOTTOMLEFT", x1 = 19, y1 = 22, a2 = "BOTTOMRIGHT", x2 = -45, y2 = -10 },
        right          = { a1 = "TOPRIGHT", x1 = -47, y1 = -10, a2 = "BOTTOMRIGHT", x2 = 17, y2 = 22 },
        topright       = { a1 = "TOPRIGHT", x1 = -45, y1 = 22, a2 = "TOPRIGHT", x2 = 19, y2 = -10 },
        bottomright    = { a1 = "BOTTOMRIGHT", x1 = -45, y1 = 22, a2 = "BOTTOMRIGHT", x2 = 19, y2 = -10 },
        ornament       = { a1 = "TOPLEFT", x1 = -53, y1 = 85, a2 = "TOPLEFT", x2 = 77.91, y2 = -120.71 },
        text           = { a1 = "TOPLEFT", x1 = 66, y1 = -15, a2 = "BOTTOMRIGHT", x2 = -46, y2 = 25 },
    },
    size = { w = 500, h = 50, border = 22, borderY = 14 },
    panelLayout = {
        bg             = { a1 = "TOPLEFT", x1 = 8.33, y1 = -6.67, a2 = "BOTTOMRIGHT", x2 = -18.33, y2 = 14.67 },
        bottom         = { a1 = "BOTTOMLEFT", x1 = 43.67, y1 = 32, a2 = "BOTTOMRIGHT", x2 = -49.67, y2 = 0 },
        left           = { a1 = "TOPLEFT", x1 = -15, y1 = -3.33, a2 = "BOTTOMLEFT", x2 = 17, y2 = 71.33 },
        right          = { a1 = "TOPRIGHT", x1 = -27, y1 = -13, a2 = "BOTTOMRIGHT", x2 = 5, y2 = 75 },
        topright       = { a1 = "TOPRIGHT", x1 = -45, y1 = 22, a2 = "TOPRIGHT", x2 = 19, y2 = -10 },
        bottomleft     = { a1 = "BOTTOMLEFT", x1 = -20, y1 = 75, a2 = "BOTTOMLEFT", x2 = 44, y2 = -53 },
        bottomright    = { a1 = "BOTTOMRIGHT", x1 = -50, y1 = 75, a2 = "BOTTOMRIGHT", x2 = 14, y2 = -53 },
        pornament1     = { a1 = "BOTTOMRIGHT", x1 = -179.67, y1 = 9.67, a2 = "BOTTOMRIGHT", x2 = -9, y2 = -75.67 },
    },
    panelSize = { border = 24, borderY = 24 },
    panelPos = { left = 0, right = 0, gap = -16, under = true },
    files = { right = "s-middle-right" },
    panelFiles = { bottom = "s-results-bottom", bottomleft = "s-results-bottom-left", bottomright = "s-results-bottom-right", left = "s-results-left", right = "s-results-right" },
    panelBg = "s-bg-results",
    highlight = { 1, 0.3, 0.05, 0.22 },   -- red-orange, like lava (Dukul, 2026-09-27)
})

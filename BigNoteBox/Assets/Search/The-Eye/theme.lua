-- BigNoteBox Assets/Search/The-Eye/theme.lua -- "The Eye" search bar theme
--
-- How a theme file works: Assets\Search\README.txt.

local Register = BigNoteBox.RegisterSearchTheme

-- Full-height bracket on the left (no top/bottom-left corners), right end
-- is two corners with no edge between them, and a middle piece on the top
-- and bottom edge. A starting layout, not tuned yet: Dukul is redrawing
-- the art (2026-09-26). Registered so the layout tool can show it; hidden
-- keeps it out of the player's theme picker (ALL-69.4) until it is finished.
Register({
    name   = "The Eye",
    folder = "The-Eye",
    hidden = true,
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

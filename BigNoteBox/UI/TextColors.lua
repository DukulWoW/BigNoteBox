-- BigNoteBox UI/TextColors.lua: header / accent text colour in one place (ALL-402)
--
-- Every text that was gold (headers, window titles, labels drawn with the
-- game's GameFontNormal*) takes one colour, decided here:
--   skin mode   = the preset's accent (BNB.SkinAccentOf: the border hue turned,
--                 never white; Obsidian / OLED / Argent get a muted warm gold)
--   normal mode = BNB.HEADER_COLOR_NORMAL (BNB green; gold is one edit away)
--
-- How text gets it:
--   * Font objects BNBFontNormal / Small / Large / Huge (UI/HeaderFonts.xml):
--     use them wherever GameFontNormal* would be used. Text on them follows
--     every preset change by itself; a string that sets its own colour keeps it.
--   * BNB.HeaderColor() for a colour set by hand (hover off, enable, ...).
--     BNB.SetHeaderColor(fs) also follows preset changes while the string
--     still shows the header colour.
--   * BNB.AccentMarkup(text) turns the gold |cffffd100 escape in a string
--     into the header colour (wizard and help texts).
-- Item quality, class colours, chat lines and game tooltips keep their own.

local BNB = BigNoteBox

-- Normal-mode header colour (Dukul, 2026-10-08: "try making it BNB green in
-- normal mode, but make it so it's easily changed back"). Gold = { 1, 0.82, 0 }
BNB.HEADER_COLOR_NORMAL = { 0.55, 0.82, 0.55 }

local FONT_OBJECTS = { "BNBFontNormal", "BNBFontNormalSmall", "BNBFontNormalLarge", "BNBFontNormalHuge" }

function BNB.HeaderColor()
    if BigNoteBoxDB and BigNoteBoxDB.skinMode and BNB.SkinAccentOf then
        return BNB.SkinAccentOf(BNB.GetSkinPreset())
    end
    local c = BNB.HEADER_COLOR_NORMAL
    return c[1], c[2], c[3]
end

-- "|cffRRGGBB" for the header colour
function BNB.HeaderColorCode()
    local r, g, b = BNB.HeaderColor()
    return string.format("|cff%02x%02x%02x", math.floor(r * 255 + 0.5),
        math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5))
end

function BNB.AccentMarkup(text)
    if type(text) ~= "string" then return text end
    local code = BNB.HeaderColorCode()
    return (text:gsub("|[cC][fF][fF][fF][fF][dD]100", function() return code end))
end

-- Strings coloured by hand that should follow a preset change. Weak keys:
-- a string's frame is never freed, but a dropped reference costs nothing
local _hand = setmetatable({}, { __mode = "k" })
local _lastR, _lastG, _lastB

function BNB.SetHeaderColor(fs, a)
    if not fs or not fs.SetTextColor then return end
    local r, g, b = BNB.HeaderColor()
    fs:SetTextColor(r, g, b, a or 1)
    _hand[fs] = a or 1
end

local function Same(x, y) return x and y and math.abs(x - y) < 0.01 end

-- Recolour the font objects and the hand-coloured strings. Called at login
-- (Core/Initialize.lua) and on every preset or brightness change
-- (BNB.ApplyMainWindowSkin). Only on those: a font object recolour walks every
-- string that uses it (FOR-30), so never per frame.
function BNB.ApplyHeaderColor()
    local r, g, b = BNB.HeaderColor()
    if Same(r, _lastR) and Same(g, _lastG) and Same(b, _lastB) then return end
    for _, name in ipairs(FONT_OBJECTS) do
        local fo = _G[name]
        if fo and fo.SetTextColor then fo:SetTextColor(r, g, b) end
    end
    for fs, a in pairs(_hand) do
        -- A string now in another colour (greyed, hovered) is left alone
        local cr, cg, cb = fs:GetTextColor()
        if not _lastR or (Same(cr, _lastR) and Same(cg, _lastG) and Same(cb, _lastB)) then
            fs:SetTextColor(r, g, b, a)
        end
    end
    _lastR, _lastG, _lastB = r, g, b
end

-- BigNoteBox UI/TextColors.lua: header and text colours in one place (ALL-402)
--
-- Headings and important text take the accent; everything else is white
-- (Dukul, 2026-10-08: "checkbox, dropdown titles etc. should be white, green
-- on headers and important things").
--
-- Accent (headings, window titles, selected entries, wizard highlights):
--   skin mode   = the preset's accent (BNB.SkinAccentOf: the border hue turned,
--                 never white; Obsidian / OLED / Argent get a muted warm gold)
--   normal mode = BNB.HEADER_COLOR_NORMAL (BNB green; gold is one edit away)
--   * Font objects BNBFontNormalLarge / Huge (UI/HeaderFonts.xml) carry it.
--   * BNB.SetHeaderColor(fs) for a normal-size heading; it follows preset
--     changes while the string still shows the header colour.
--     BNB.HeaderColor() for a colour set by hand (hover off, enable, ...).
--   * BNB.AccentMarkup(text) turns the gold |cffffd100 escape in a string
--     into the header colour (wizard and help texts).
--
-- White (labels, checkbox labels, dropdown titles, body text): white on every
-- preset but one with a muted `text` colour in BNB.SKIN_PRESETS (OLED, 0.80:
-- pure white on black was too sharp; read through BNB.SkinTextOf).
--   * Font objects BNBFontNormal / Small (the game's gold GameFontNormal*, as
--     white labels) and BNBFontHighlight / Small / Large.
--   * BNB.TextWhite(v) for a white or light grey set by hand (v = the grey it
--     would be, nil = 1); BNB.SetTextWhite(fs, v, a) also follows preset changes.
--
-- Item quality, class colours, chat lines, game tooltips and toasts keep their
-- own. A note's own colours (title colour, text colour, rich markup) win.

local BNB = BigNoteBox

-- Normal-mode header colour (Dukul, 2026-10-08: "try making it BNB green in
-- normal mode, but make it so it's easily changed back"). Gold = { 1, 0.82, 0 }
BNB.HEADER_COLOR_NORMAL = { 0.55, 0.82, 0.55 }

local HEADER_OBJECTS = { "BNBFontNormalLarge", "BNBFontNormalHuge" }
local WHITE_OBJECTS  = { "BNBFontNormal", "BNBFontNormalSmall",
    "BNBFontHighlight", "BNBFontHighlightSmall", "BNBFontHighlightLarge" }

local function Same(x, y) return x and y and math.abs(x - y) < 0.01 end

-- The brightest white text on the current preset (skin mode only):
-- BNB.SkinTextOf, an exact colour or one grey
local function TextCap()
    if not (BigNoteBoxDB and BigNoteBoxDB.skinMode and BNB.SkinTextOf) then return 1, 1, 1 end
    return BNB.SkinTextOf(BNB.GetSkinPreset())
end

-- v = the white / light grey the text would have (nil = 1); returns r, g, b,
-- each capped by the preset's text colour
function BNB.TextWhite(v)
    v = v or 1
    local cr, cg, cb = TextCap()
    return math.min(v, cr), math.min(v, cg), math.min(v, cb)
end

function BNB.HeaderColor()
    if BigNoteBoxDB and BigNoteBoxDB.skinMode and BNB.SkinAccentOf then
        return BNB.SkinHeaderOf(BNB.GetSkinPreset())
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
local _hand  = setmetatable({}, { __mode = "k" })   -- header: [fs] = alpha
local _white = setmetatable({}, { __mode = "k" })   -- white:  [fs] = { v, alpha }
local _lastR, _lastG, _lastB

function BNB.SetHeaderColor(fs, a)
    if not fs or not fs.SetTextColor then return end
    local r, g, b = BNB.HeaderColor()
    fs:SetTextColor(r, g, b, a or 1)
    _white[fs] = nil
    _hand[fs] = a or 1
end

function BNB.SetTextWhite(fs, v, a)
    if not fs or not fs.SetTextColor then return end
    local r, g, b = BNB.TextWhite(v)
    fs:SetTextColor(r, g, b, a or 1)
    _hand[fs] = nil
    _white[fs] = { v or 1, a or 1 }
end

local function IsGold(r, g, b) return r > 0.99 and math.abs(g - 0.82) < 0.01 and b < 0.01 end

-- A checkbox label (BNB.LabelHit): the template's own label is the game's gold
-- GameFontNormal*; it moves onto our white copy. A label in a colour of its
-- own (not gold, not the header colour) keeps that colour.
function BNB.UseLabelFont(fs)
    if not (fs and fs.GetFontObject) or fs._bnbLabelFont then return end
    local fo = fs:GetFontObject()
    local to = ((fo == GameFontNormal or fo == _G.BNBFontNormal) and "BNBFontNormal")
        or ((fo == GameFontNormalSmall or fo == _G.BNBFontNormalSmall) and "BNBFontNormalSmall")
    if not to then return end
    fs._bnbLabelFont = true
    local r, g, b, a = fs:GetTextColor()
    local hr, hg, hb = BNB.HeaderColor()
    local wr, wg, wb = TextCap()
    local own = not (IsGold(r, g, b)
        or (Same(r, hr) and Same(g, hg) and Same(b, hb))     -- header colour
        or (Same(r, wr) and Same(g, wg) and Same(b, wb))     -- already our white
        or (r > 0.99 and g > 0.99 and b > 0.99))             -- plain white
    if fo ~= _G[to] then fs:SetFontObject(to) end
    if own then fs:SetTextColor(r, g, b, a) else BNB.SetTextWhite(fs, nil, a) end
end

local _lastCap   -- { r, g, b } the white strings were last drawn with
local function ApplyTextWhite()
    local cr, cg, cb = TextCap()
    local last = _lastCap
    if last and Same(cr, last[1]) and Same(cg, last[2]) and Same(cb, last[3]) then return end
    for _, name in ipairs(WHITE_OBJECTS) do
        local fo = _G[name]
        if fo and fo.SetTextColor then fo:SetTextColor(cr, cg, cb) end
    end
    for fs, e in pairs(_white) do
        -- Only a string still showing its white (not greyed or hovered)
        local r0, g0, b0 = fs:GetTextColor()
        if not last or (Same(r0, math.min(e[1], last[1])) and Same(g0, math.min(e[1], last[2]))
           and Same(b0, math.min(e[1], last[3]))) then
            local r, g, b = BNB.TextWhite(e[1])
            fs:SetTextColor(r, g, b, e[2])
        end
    end
    _lastCap = { cr, cg, cb }
end

-- Recolour the font objects and the hand-coloured strings. Called at login
-- (Core/Initialize.lua) and on every preset or brightness change
-- (BNB.RefreshSkinAccents). Only on those: a font object recolour walks every
-- string that uses it (FOR-30), so never per frame.
function BNB.ApplyHeaderColor()
    ApplyTextWhite()
    local r, g, b = BNB.HeaderColor()
    if Same(r, _lastR) and Same(g, _lastG) and Same(b, _lastB) then return end
    for _, name in ipairs(HEADER_OBJECTS) do
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

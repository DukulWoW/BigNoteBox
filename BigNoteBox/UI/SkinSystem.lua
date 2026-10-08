-- BigNoteBox UI/SkinSystem.lua
-- Central skin system. Loaded before all other UI files.
-- Provides preset definitions, target registry, apply function,
-- frame/strip/tab builders, and the main-window open router.
--
-- Public API:
--   BNB.GetSkinPreset()                          -> preset table
--   BNB.SkinColourOf(preset, lifted)             -> r, g, b
--   BNB.CreateSkinFrame(parent, lifted, name)    -> frame (visible border, registered)
--   BNB.CreateSkinStrip(parent, lifted)          -> frame (invisible border, registered)
--   BNB.RegisterSkinTarget(frame, lifted, strip) -> registers external window frames
--   BNB.ApplyMainWindowSkin()                    -> recolours all registered targets
--   BNB.CreateSkinTabs(parent, labels, onSelect) -> tab row widget
--   BNB.OpenMainWindow()                         -> routes to skin or normal window
--------------------------------------------------------------------------------

local BNB = BigNoteBox
local L   = BNB.L

--------------------------------------------------------------------------------
-- PRESET DEFINITIONS
-- Each preset: { r, g, b, lift, br, bg_, bb } plus optional exact colours
--   r/g/b     = base fill colour
--   lift      = how much brighter chrome strips (title/toolbar/footer) are vs body
--   br/bg_/bb = border colour (bg_ avoids collision with Lua 'bg' idiom)
-- Optional exact colours (ALL-403, written by the Skin Lab's Export), each
-- { r, g, b }; nil = worked out as before, so a preset without them looks
-- exactly as it did:
--   lifted = the strips' colour before brightness   (nil = body + lift)
--   button = skin button fill, not scaled           (nil = body + lift * 1.5)
--   accent = accent at the default brightness 1.50, scales with brightness
--            (nil = the border hue turned, BNB.SkinAccentOf)
--   header = heading colour, scales as accent        (nil = accent)
--   text   = the brightest white text, or one grey  (nil = white)
--   noBright = true: the brightness setting does not apply (OLED)
-- Read them only through SkinColourOf / SkinLiftedOf / SkinButtonOf /
-- SkinAccentOf / SkinHeaderOf / SkinTextOf, never the fields.
--------------------------------------------------------------------------------
BNB.SKIN_PRESETS = {
    obsidian   = { r=0.070, g=0.070, b=0.070, lift=0.05, br=0.28, bg_=0.28, bb=0.28 },
    void       = { r=0.090, g=0.030, b=0.130, lift=0.05, br=0.32, bg_=0.15, bb=0.40 },
    dragonfire = { r=0.110, g=0.040, b=0.040, lift=0.05, br=0.35, bg_=0.18, bb=0.18 },
    arcane     = { r=0.130, g=0.055, b=0.100, lift=0.05, br=0.40, bg_=0.22, bb=0.32 },
    fel        = { r=0.040, g=0.100, b=0.060, lift=0.05, br=0.18, bg_=0.32, bb=0.22 },
    titan      = { r=0.100, g=0.090, b=0.030, lift=0.05, br=0.32, bg_=0.30, bb=0.14 },
    icecrown   = { r=0.040, g=0.060, b=0.130, lift=0.05, br=0.18, bg_=0.24, bb=0.38 },
    holy       = { r=0.110, g=0.100, b=0.020, lift=0.05, br=0.40, bg_=0.36, bb=0.12 },
    azshara    = { r=0.030, g=0.100, b=0.110, lift=0.05, br=0.15, bg_=0.34, bb=0.38 },
    ragnaros   = { r=0.130, g=0.070, b=0.020, lift=0.05, br=0.40, bg_=0.26, bb=0.12 },
    earthen    = { r=0.090, g=0.070, b=0.040, lift=0.05, br=0.30, bg_=0.24, bb=0.14 },
    argent     = { r=0.090, g=0.090, b=0.095, lift=0.05, br=0.36, bg_=0.36, bb=0.40 },
    -- text = the brightest white text on this preset (ALL-402 S2: OLED's pure
    -- white on black was too sharp); nil = 1. Read through BNB.TextWhite
    oled       = { r=0.000, g=0.000, b=0.000, lift=0.00, br=0.18, bg_=0.18, bb=0.18, text=0.80, noBright=true },
}

-- Display order of the presets: the one list Settings > Appearance and the
-- setup wizard read (CMP-05; each kept its own copy). Labels come from the key:
-- CFG_SKIN_PRESET_<KEY> ("Void  (purple)") for Settings, SW_PRESET_<KEY>
-- ("Void") for the wizard. A new preset = one SKIN_PRESETS line, one entry
-- here and the two locale keys.
BNB.SKIN_PRESET_ORDER = {
    "obsidian", "void", "dragonfire", "arcane", "fel",
    "titan", "icecrown", "holy", "azshara", "ragnaros",
    "earthen", "argent", "oled",
}

function BNB.SkinPresetLabel(key, short)
    local k = (short and "SW_PRESET_" or "CFG_SKIN_PRESET_") .. key:upper()
    return BNB.HasL(k) and L[k] or key
end

-- Skin Lab override (ALL-403): while the lab is open every skin colour reads
-- its preset, brightness and opacity instead of the saved ones, on every open
-- window. o = { key, preset, brightness, alpha } (brightness / alpha nil =
-- the saved ones), nil = off. The caller re-applies (BNB.ApplyMainWindowSkin);
-- nothing is saved.
local _override
function BNB.SetSkinOverride(o) _override = o end
function BNB.GetSkinOverride() return _override end

-- The active preset's key (the lab's while it overrides)
function BNB.GetSkinPresetKey()
    if _override then return _override.key end
    return BigNoteBoxDB and BigNoteBoxDB.skinPreset or "obsidian"
end

-- Returns the active preset table, falling back to obsidian.
function BNB.GetSkinPreset()
    if _override and _override.preset then return _override.preset end
    local key = BigNoteBoxDB and BigNoteBoxDB.skinPreset or "obsidian"
    return BNB.SKIN_PRESETS[key] or BNB.SKIN_PRESETS.obsidian
end

-- Returns the current brightness multiplier (0.5 - 3.0, default BNB.DEFAULTS.skinBrightness = 1.5).
-- Always returns 1.0 for a noBright preset (OLED: pure black must stay pure black).
function BNB.GetSkinBrightness()
    if BNB.GetSkinPreset().noBright then return 1.0 end
    if _override and _override.brightness then return _override.brightness end
    return (BigNoteBoxDB and BigNoteBoxDB.skinBrightness) or BNB.DEFAULTS.skinBrightness
end

-- Returns the window background opacity (0.0 - 1.0, default 0.97).
function BNB.GetSkinBgAlpha()
    if _override and _override.alpha then return _override.alpha end
    return (BigNoteBoxDB and BigNoteBoxDB.skinBgAlpha) or 0.97
end

-- Resting frame alpha for a whole window (ALL-78). Classic windows sit at 0.95.
-- A skin window stays at 1: its background already carries the Window opacity
-- setting above, and a frame alpha below 1 would stack on top of it, so 1.00
-- could never be reached. Skin frames are marked _isSkin by BNB.CreateSkinFrame.
function BNB.WindowAlpha(f)
    return (f and f._isSkin) and 1.0 or 0.95
end

-- The strips' (title bar, toolbar, footer) colour before brightness: the
-- exact `lifted` colour, else body + lift. Sticky headers use it unscaled.
function BNB.SkinLiftedOf(preset)
    local c = preset.lifted
    if c then return c[1], c[2], c[3] end
    local lift = preset.lift or 0
    return math.min(1, preset.r + lift), math.min(1, preset.g + lift), math.min(1, preset.b + lift)
end

-- Skin button fill, not scaled by brightness: the exact `button` colour, else
-- body + lift * 1.5 (the colour every skin button had by hand)
function BNB.SkinButtonOf(preset)
    local c = preset.button
    if c then return c[1], c[2], c[3] end
    local lift = (preset.lift or 0) * 1.5
    return math.min(1, preset.r + lift), math.min(1, preset.g + lift), math.min(1, preset.b + lift)
end

-- Returns r, g, b for a preset body colour (lifted = the strips' colour),
-- scaled by the current brightness multiplier.
function BNB.SkinColourOf(preset, lifted)
    local brt = BNB.GetSkinBrightness()
    local r, g, b = preset.r, preset.g, preset.b
    if lifted then r, g, b = BNB.SkinLiftedOf(preset) end
    return math.min(1, r * brt), math.min(1, g * brt), math.min(1, b * brt)
end

-- The brightest white text on a preset: the exact `text` colour (a number =
-- one grey), else white. BNB.TextWhite (UI/TextColors.lua) caps by it.
function BNB.SkinTextOf(preset)
    local c = preset.text
    if type(c) == "number" then return c, c, c end
    if type(c) == "table" then return c[1], c[2], c[3] end
    return 1, 1, 1
end

-- Divider rules (ALL-394): the border colour, with the brightness stopping at
-- the default (1.50). A window edge carries a bright border; a 1 px rule
-- across a page went glaring from 2.00 up (Dukul 2026-10-08, screenshots at
-- 1.00 / 2.00 / 3.00). Every rule colour (RegisterSkinRule targets and their
-- first colour) comes from here.
function BNB.SkinRuleOf(preset)
    local cap = BNB.DEFAULTS and BNB.DEFAULTS.skinBrightness or 1.5
    local brt = math.min(BNB.GetSkinBrightness(), cap)
    return math.min(1, preset.br * brt),
           math.min(1, preset.bg_ * brt),
           math.min(1, preset.bb * brt)
end

-- Accent colour (Dukul, 2026-10-08): white art in skin mode (top bar icons)
-- is drawn in a colour that pairs with the preset instead of the preset's own
-- hue ("not purple on purple"): the border hue turned SKIN_ACCENT_HUE degrees,
-- a little more saturated, as bright as the brightness asks but never past the
-- brightest shade of that colour (never white). Presets with next to no hue
-- (Obsidian, OLED, Argent) get a warm gold, a little muted. The turn is
-- BNB.skinAccentHue (tune live with /bnb skinhue <degrees>, debug mode).
BNB.skinAccentHue = 30
local ACCENT_MULT    = 2.2    -- brightness boost, as the icon symbols had
local GREY_SAT       = 0.15   -- below this a preset counts as colourless
local MUTED_GOLD_H   = 42 / 360
local MUTED_GOLD_S   = 0.62

local function RGBtoHSV(r, g, b)
    local mx, mn = math.max(r, g, b), math.min(r, g, b)
    local d = mx - mn
    local h = 0
    if d > 0 then
        if mx == r then h = ((g - b) / d) % 6
        elseif mx == g then h = (b - r) / d + 2
        else h = (r - g) / d + 4 end
        h = h / 6
    end
    return h, (mx > 0) and d / mx or 0, mx
end

local function HSVtoRGB(h, s, v)
    local i = math.floor(h * 6) % 6
    local f = h * 6 - math.floor(h * 6)
    local p, q, t = v * (1 - s), v * (1 - f * s), v * (1 - (1 - f) * s)
    if i == 0 then return v, t, p elseif i == 1 then return q, v, p
    elseif i == 2 then return p, v, t elseif i == 3 then return p, q, v
    elseif i == 4 then return t, p, v end
    return v, p, q
end

-- An exact colour (accent / header) at the default brightness, scaled by the
-- current brightness (and mult against the usual ACCENT_MULT), never past the
-- brightest shade of its hue
local function ScaleExact(c, mult)
    local h, s, v = RGBtoHSV(c[1], c[2], c[3])
    local def = BNB.DEFAULTS and BNB.DEFAULTS.skinBrightness or 1.5
    local brt = BNB.GetSkinPreset().noBright and def or BNB.GetSkinBrightness()
    v = math.min(1, v * (brt / def) * ((mult or ACCENT_MULT) / ACCENT_MULT))
    return HSVtoRGB(h, s, v)
end

function BNB.SkinAccentOf(preset, mult)
    if preset.accent then return ScaleExact(preset.accent, mult) end
    local h, s, v = RGBtoHSV(preset.br, preset.bg_, preset.bb)
    v = math.min(1, v * BNB.GetSkinBrightness() * (mult or ACCENT_MULT))
    if s < GREY_SAT then
        -- Never below 0.78: OLED's dark border (0.18) left them looking
        -- disabled (Dukul, 2026-10-08)
        return HSVtoRGB(MUTED_GOLD_H, MUTED_GOLD_S, math.min(0.9, math.max(v, 0.78)))
    end
    h = (h + (BNB.skinAccentHue or 30) / 360) % 1
    return HSVtoRGB(h, math.min(1, s * 1.2 + 0.1), v)
end

-- Heading colour (BNB.HeaderColor in skin mode): the exact `header`, else the accent
function BNB.SkinHeaderOf(preset)
    if preset.header then return ScaleExact(preset.header) end
    return BNB.SkinAccentOf(preset)
end

-- Returns br, bg_, bb for a preset scaled by the current brightness multiplier.
function BNB.SkinBorderOf(preset)
    local brt = BNB.GetSkinBrightness()
    return math.min(1, preset.br * brt),
           math.min(1, preset.bg_ * brt),
           math.min(1, preset.bb * brt)
end

--------------------------------------------------------------------------------
-- TARGET REGISTRY
-- _mainTargets : registered by MainWindowSkin during its own build (private)
-- _extTargets  : registered by all other skinned windows via BNB.RegisterSkinTarget
-- _skinButtons : registered by CreateSkinButton, updated on preset change
--------------------------------------------------------------------------------
local _mainTargets   = {}
local _extTargets    = {}
local _skinButtons   = {}
local _skinTabs      = {}  -- stores RefreshVisual functions from CreateSkinTabs
local _skinRules     = {}  -- stores {tex, alpha} for divider textures
local _skinLabels    = {}  -- stores {fs, mult} for FontStrings that track border colour
local _skinIconTexs  = {}  -- stores {tx, mult} for icon textures tinted to border colour
local _skinBackdrops = {}  -- stores applyFn callbacks for wysiwyg backdrop frames

-- Private: used only by BNB.CreateSkinFrame / BNB.CreateSkinStrip when building
-- the main window. Other windows must use BNB.RegisterSkinTarget.
local function RegisterMain(frame, lifted, strip)
    _mainTargets[#_mainTargets + 1] = {
        frame  = frame,
        lifted = lifted or false,
        strip  = strip  or false,
    }
end

-- Public: called by any skinned window other than the main window.
function BNB.RegisterSkinTarget(frame, lifted, strip)
    _extTargets[#_extTargets + 1] = {
        frame  = frame,
        lifted = lifted or false,
        strip  = strip  or false,
    }
end

-- Public: called by CreateSkinButton for each skin button that should update
-- on preset change. applyFn is a zero-arg function that re-applies the preset.
-- owner (optional): the button, when it re-applies the preset itself on
-- OnShow. Such a button is skipped while hidden, and dropped once it has no
-- parent (a rebuilt row), so a window show does not walk every skin button
-- ever made (PERF-09).
function BNB.RegisterSkinButton(applyFn, owner)
    _skinButtons[#_skinButtons + 1] = { fn = applyFn, owner = owner }
end

-- Public: called by CreateSkinTabs so tabs recolour on preset change.
function BNB.RegisterSkinTabs(refreshFn)
    _skinTabs[#_skinTabs + 1] = refreshFn
end

-- Public: called by AddRule (ConfigWindow.lua) for each divider texture that
-- should track the current preset border colour + brightness.
-- alpha defaults to 0.9 if nil.
function BNB.RegisterSkinRule(tex, alpha)
    _skinRules[#_skinRules + 1] = { tex = tex, alpha = alpha or 0.9 }
end

-- Public: FontString that should tint to border colour × mult.
-- mult=0.60 gives a readable-but-secondary metadata text colour.
function BNB.RegisterSkinLabel(fs, mult)
    _skinLabels[#_skinLabels + 1] = { fs = fs, mult = mult or 0.60 }
end

-- Public: icon Texture that should be tinted to border colour × mult.
-- mult=2.2 pushes the tint bright enough to pop against a dark background.
function BNB.RegisterSkinIconTex(tx, mult)
    _skinIconTexs[#_skinIconTexs + 1] = { tx = tx, mult = mult or 2.2 }
end
-- An icon texture drawn in the accent colour (BNB.SkinAccentOf), re-tinted
-- on every preset change. shade scales it (0.6 = the top bar hover plate,
-- darker so the icon stands out); registering a texture again sets its shade
local _accentTexs = {}
function BNB.RegisterSkinAccentTex(tx, shade)
    if not tx then return end
    _accentTexs[tx] = shade or 1
    if BNB.GetSkinPreset then
        local r, g, b = BNB.SkinAccentOf(BNB.GetSkinPreset())
        local k = _accentTexs[tx]
        tx:SetVertexColor(r * k, g * k, b * k)
    end
end
function BNB.RefreshSkinAccents()
    if not BNB.GetSkinPreset then return end
    local r, g, b = BNB.SkinAccentOf(BNB.GetSkinPreset())
    for tx, k in pairs(_accentTexs) do tx:SetVertexColor(r * k, g * k, b * k) end
    -- Header / accent text follows the same colour (UI/TextColors.lua, ALL-402)
    if BNB.ApplyHeaderColor then BNB.ApplyHeaderColor() end
end

-- Public: zero-arg callback that re-applies the skin backdrop to a frame.
-- Used by wysiwyg font/size backdrop frames so they update on preset change.
function BNB.RegisterSkinBackdrop(applyFn)
    _skinBackdrops[#_skinBackdrops + 1] = applyFn
end

--------------------------------------------------------------------------------
-- APPLY
-- Recolours every registered target to the current preset.
-- Called on window show and on preset change from Config.
--------------------------------------------------------------------------------
function BNB.ApplyMainWindowSkin()
    local preset = BNB.GetSkinPreset()

    local function applyList(list)
        for _, t in ipairs(list) do
            if t.frame and t.frame.SetBackdropColor then
                local r, g, b = BNB.SkinColourOf(preset, t.lifted)
                t.frame:SetBackdropColor(r, g, b, BNB.GetSkinBgAlpha())
                local br, bg_, bb = BNB.SkinBorderOf(preset)
                if t.strip then
                    t.frame:SetBackdropBorderColor(r, g, b, 0)
                else
                    t.frame:SetBackdropBorderColor(br, bg_, bb, 1)
                end
            end
        end
    end

    applyList(_mainTargets)
    applyList(_extTargets)

    -- Recolour all registered skin buttons; prune the orphaned ones
    local n = 0
    for i = 1, #_skinButtons do
        local e = _skinButtons[i]
        local owner = e.owner
        if not owner or owner:GetParent() then
            n = n + 1
            _skinButtons[n] = e
            if not owner or owner:IsVisible() then pcall(e.fn) end
        end
    end
    for i = #_skinButtons, n + 1, -1 do _skinButtons[i] = nil end

    -- Recolour all registered skin tabs
    for _, refreshFn in ipairs(_skinTabs) do
        pcall(refreshFn)
    end

    -- Recolour all registered divider rule textures (brightness capped, ALL-394)
    local rr, rg, rb = BNB.SkinRuleOf(preset)
    for _, r in ipairs(_skinRules) do
        if r.tex and r.tex.SetColorTexture then
            r.tex:SetColorTexture(rr, rg, rb, r.alpha)
        end
    end
    local br, bg_, bb = BNB.SkinBorderOf(preset)

    -- Recolour registered FontString labels (metadata strips, etc.)
    for _, l in ipairs(_skinLabels) do
        if l.fs and l.fs.SetTextColor then
            l.fs:SetTextColor(br * l.mult, bg_ * l.mult, bb * l.mult)
        end
    end

    BNB.RefreshSkinAccents()

    -- Tint registered icon textures to the border colour at boosted brightness.
    for _, ic in ipairs(_skinIconTexs) do
        if ic.tx and ic.tx.SetVertexColor then
            ic.tx:SetVertexColor(
                math.min(1, br * ic.mult),
                math.min(1, bg_ * ic.mult),
                math.min(1, bb * ic.mult))
        end
    end

    -- Re-apply skin backdrop to registered wysiwyg backdrop frames.
    for _, fn in ipairs(_skinBackdrops) do
        pcall(fn)
    end
    -- (The splitter grip colour is set by UI/MainWindowSkin.lua.)

    -- Stickies on the default colour follow the preset (UI/StickyNote.lua)
    if BNB.SendMessage then BNB.SendMessage("SkinChanged") end
end

--------------------------------------------------------------------------------
-- FRAME BUILDERS
-- BNB.CreateSkinFrame  — outer window frame: visible border, uses border colours.
-- BNB.CreateSkinStrip  — internal chrome strip: border alpha=0 (invisible).
--
-- isMain flag: true when building the main window (registers to _mainTargets),
-- false/nil for all other windows (registers to _extTargets via RegisterSkinTarget).
--------------------------------------------------------------------------------
function BNB.CreateSkinFrame(parent, lifted, name, isMain)
    local preset = BNB.GetSkinPreset()
    local r, g, b = BNB.SkinColourOf(preset, lifted)
    local br, bg_, bb = BNB.SkinBorderOf(preset)
    local f = BNB.CreateBackdropFrame("Frame", name, parent)
    BNB.SetBackdrop(f, r, g, b, BNB.GetSkinBgAlpha(), br, bg_, bb, 1)
    f._isSkin = true   -- read by BNB.WindowAlpha
    if isMain then
        RegisterMain(f, lifted, false)
    else
        BNB.RegisterSkinTarget(f, lifted, false)
    end
    return f
end

function BNB.CreateSkinStrip(parent, lifted, isMain)
    local preset = BNB.GetSkinPreset()
    local r, g, b = BNB.SkinColourOf(preset, lifted)
    local f = BNB.CreateBackdropFrame("Frame", nil, parent)
    BNB.SetBackdrop(f, r, g, b, BNB.GetSkinBgAlpha(), r, g, b, 0)
    if isMain then
        RegisterMain(f, lifted, true)
    else
        BNB.RegisterSkinTarget(f, lifted, true)
    end
    -- ALL-95: a strip that registers for drag is a title bar, so it gets the
    -- move cursor. Hooked on RegisterForDrag, not here, so strips that never
    -- drag get no mouse scripts at all.
    hooksecurefunc(f, "RegisterForDrag", function(self) BNB.SetMoveCursor(self) end)
    return f
end

--------------------------------------------------------------------------------
-- SKIN CLOSE BUTTON
-- BNB.CreateSkinCloseButton(parent, onClick)
--
-- Shared 22x22 close button used by every skinned window's title bar: the
-- "close" icon button in its skin look (UI/IconButton.lua, ALL-210).
-- Callers are responsible for anchoring; the convention is:
--     btn:SetPoint("RIGHT", titleBar, "RIGHT", -2, 0)
-- The -2 inset keeps the button slightly clear of the window border while
-- still overlapping it enough to match Blizzard's native close-button style.
--------------------------------------------------------------------------------
function BNB.CreateSkinCloseButton(parent, onClick)
    -- onClick is called with no arguments: callers pass functions like onClose
    local btn = BNB.CreateIconButton(parent, 22, "close", { skin = true,
        onClick = function() if onClick then onClick() end end })
    return btn
end

--------------------------------------------------------------------------------
-- SKIN TABS
-- BNB.CreateSkinTabs(parent, labels, onSelect)
--
-- Creates a horizontal row of flat tab buttons styled to match the skin.
-- parent    : frame to parent buttons to
-- labels    : array of strings e.g. {"General","Animation","Advanced"}
-- onSelect  : function(idx) called when a tab is clicked
--
-- Returns a controller table:
--   ctrl.buttons  : array of Button frames
--   ctrl.Select(idx) : programmatically select a tab
--   ctrl.frame    : invisible container Frame (SetPoint this to position the row)
--
-- Each button is 24px tall. The container width stretches to parent width.
-- Caller anchors ctrl.frame; buttons fill it left-to-right with 2px gaps.
--------------------------------------------------------------------------------
local SK_TAB_H     = 24
local SK_TAB_GAP   = 2

function BNB.CreateSkinTabs(parent, labels, onSelect)
    local container = CreateFrame("Frame", nil, parent)
    container:SetHeight(SK_TAB_H)

    local buttons = {}
    local ctrl = { buttons = buttons, frame = container }

    local function RefreshVisual(selectedIdx)
        local preset = BNB.GetSkinPreset()
        local br, bg_, bb = BNB.SkinBorderOf(preset)
        -- Selected tab label: bright preset border colour
        -- Unselected tab label: white (dimmed via alpha)
        local selR = math.min(1, br * 3.0)
        local selG = math.min(1, bg_ * 3.0)
        local selB = math.min(1, bb * 3.0)
        for i, btn in ipairs(buttons) do
            local selected = (i == selectedIdx)
            if selected then
                btn:SetAlpha(1.0)
                btn:SetEnabled(false)
                if btn._bg and btn._bg.SetBackdropColor then
                    local r, g, b = BNB.SkinColourOf(preset, true)
                    btn._bg:SetBackdropColor(r, g, b, 0.97)
                    btn._bg:SetBackdropBorderColor(br, bg_, bb, 1)
                end
                if btn._lbl then btn._lbl:SetTextColor(selR, selG, selB) end
            else
                btn:SetAlpha(0.55)
                btn:SetEnabled(true)
                if btn._bg and btn._bg.SetBackdropColor then
                    local r, g, b = BNB.SkinColourOf(preset, false)
                    btn._bg:SetBackdropColor(r, g, b, 0.97)
                    btn._bg:SetBackdropBorderColor(br, bg_, bb, 1)
                end
                if btn._lbl then BNB.SetTextWhite(btn._lbl) end
            end
        end
    end

    function ctrl.Select(idx)
        ctrl._selected = idx
        RefreshVisual(idx)
        if onSelect then onSelect(idx) end
    end

    -- Visual-only update — sets the selected appearance without firing onSelect.
    -- Use this when the caller is already handling tab switching logic itself
    -- (e.g. _NoteConfigSelectTab, _NoteConfigStickyTab) to avoid mutual recursion.
    function ctrl.SetVisual(idx)
        ctrl._selected = idx
        RefreshVisual(idx)
    end

    -- Build buttons after we have ctrl.Select defined
    local n = #labels
    for i, label in ipairs(labels) do
        local btn = CreateFrame("Button", nil, container)
        btn:SetHeight(SK_TAB_H)

        -- Backdrop background for the tab
        local bg = BNB.CreateBackdropFrame("Frame", nil, btn)
        bg:SetAllPoints()
        local preset = BNB.GetSkinPreset()
        local r, g, b = BNB.SkinColourOf(preset, false)
        local br, bg_, bb = BNB.SkinBorderOf(preset)
        BNB.SetBackdrop(bg, r, g, b, 0.97, br, bg_, bb, 1)
        btn._bg = bg

        -- Label parented to _bg so it renders above the backdrop fill
        local lbl = bg:CreateFontString(nil, "OVERLAY", "BNBFontNormalSmall")
        lbl:SetAllPoints()
        lbl:SetJustifyH("CENTER")
        lbl:SetText(label)
        BNB.SetTextWhite(lbl)  -- white; RefreshVisual sets selected colour
        btn._lbl = lbl

        btn:SetScript("OnClick", function()
            ctrl.Select(i)
        end)
        btn:SetScript("OnEnter", function(self)
            if ctrl._selected ~= i then self:SetAlpha(0.85) end
        end)
        btn:SetScript("OnLeave", function(self)
            if ctrl._selected ~= i then self:SetAlpha(0.55) end
        end)

        buttons[i] = btn
    end

    -- Position buttons. Use OnSizeChanged so they reflow if container resizes.
    local function LayoutButtons()
        local w = container:GetWidth()
        if not w or w < 4 then return end
        local btnW = math.floor((w - (n - 1) * SK_TAB_GAP) / n)
        for i, btn in ipairs(buttons) do
            btn:SetWidth(btnW)
            btn:SetHeight(SK_TAB_H)
            if i == 1 then
                btn:SetPoint("TOPLEFT", container, "TOPLEFT", 0, 0)
            else
                btn:SetPoint("TOPLEFT", buttons[i-1], "TOPRIGHT", SK_TAB_GAP, 0)
            end
        end
    end

    container:SetScript("OnSizeChanged", LayoutButtons)
    -- Defer initial layout one tick so parent has a valid width
    C_Timer.After(0, LayoutButtons)

    -- Default: select first tab without firing onSelect
    ctrl._selected = 1
    RefreshVisual(1)

    -- Register so ApplyMainWindowSkin re-applies colours on preset change
    BNB.RegisterSkinTabs(function()
        RefreshVisual(ctrl._selected or 1)
    end)

    return ctrl
end


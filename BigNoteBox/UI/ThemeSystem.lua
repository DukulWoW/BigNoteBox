-- BigNoteBox UI/ThemeSystem.lua
-- Themes for normal mode (ALL-647, Dukul 2026-11-10: "Normal mode gets a
-- dropdown like skin mode has for the different skins we make"). Skin mode
-- has colour presets; normal mode has themes: Default (the game's own window
-- art) and any theme registered here. Each theme lives in its own folder,
-- Themes/<Name>/, with its art in Themes/<Name>/Assets and its Lua beside it.
--
-- The theme is read once per load: a change asks for a reload, like the skin
-- mode switch. The saved key is never rewritten; a theme this client cannot
-- draw (Forever on the Forever client, a profile from Retail) or that is not
-- installed draws Default.
--
-- Public API:
--   BNB.RegisterTheme(key, def)   def = {
--       labelKey  = locale key of the dropdown label
--       available = function() -> bool, nil = every client
--       DressWindow(f) = draw a ButtonFrameTemplate window in the theme; runs
--                        from BNB.SeatChrome, after our close button exists
--                        and before any content. f.CloseButton may be
--                        replaced (the window sets its OnClick afterwards).
--       (S2-S4 add more builders: buttons, scrollbars, sliders; a missing
--        builder = the Default look for that piece)
--   }
--   BNB.ActiveTheme()      -> def, key  (nil in skin mode or on Default)
--   BNB.ThemeList()        -> { key, ... } the themes this client can pick,
--                             "default" first
--   BNB.ThemeLabel(key)    -> label for the dropdown
--   BNB.DressWindow(f)     -> the active theme's DressWindow, pcall-wrapped

local BNB = BigNoteBox
if not BNB then return end

local THEMES = {}
local ORDER  = { "default" }

function BNB.RegisterTheme(key, def)
    if type(key) ~= "string" or key == "default" or type(def) ~= "table" then return end
    if not THEMES[key] then ORDER[#ORDER + 1] = key end
    THEMES[key] = def
end

local function Available(key)
    if key == "default" then return true end
    local def = THEMES[key]
    if not def then return false end
    if def.available then
        local ok, on = pcall(def.available)
        return ok and on and true or false
    end
    return true
end

-- Decided once per load (the first window asks), as the skin mode switch is
local _decided, _def, _key
function BNB.ActiveTheme()
    if not _decided then
        _decided = true
        local db = BigNoteBoxDB
        local key = db and db.normalTheme or BNB.DEFAULTS.normalTheme
        if not (db and db.skinMode) and key ~= "default" and Available(key) then
            _def, _key = THEMES[key], key
        end
    end
    return _def, _key
end

function BNB.ThemeList()
    local out = {}
    for _, key in ipairs(ORDER) do
        if Available(key) then out[#out + 1] = key end
    end
    return out
end

function BNB.ThemeLabel(key)
    if key == "default" then return BNB.L["CFG_THEME_DEFAULT"] end
    local def = THEMES[key]
    if def and def.labelKey and BNB.HasL(def.labelKey) then return BNB.L[def.labelKey] end
    return key
end

function BNB.DressWindow(f)
    local def = BNB.ActiveTheme()
    if def and def.DressWindow and f then pcall(def.DressWindow, f) end
end

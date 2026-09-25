-- BigNoteBox UI/GlowOverlay.lua
--
-- Shared LibCustomGlow-1.0 lookup, the fade-alpha helper, the skin-tinted
-- overlay colour check, and the AutoCastGlow/PixelGlow start-stop wrappers
-- that used to be copied into WhatsNew, FeatureList, SetupWizard, DangerZone
-- and FocusEditor (ALL-65.4). Glow placement (padding, Forever/Retail
-- nudging) stays in UI/Chrome.lua; this file only wraps the LCG calls and
-- the small bits of math every window repeated around them.

local BNB = BigNoteBox

-- ── LibCustomGlow lookup ──────────────────────────────────────────────────────
local _lcg
function BNB.GetLCG()
    if not _lcg then _lcg = LibStub and LibStub("LibCustomGlow-1.0", true) end
    return _lcg
end

-- ── Fade ──────────────────────────────────────────────────────────────────────
function BNB.FadeTo(target, fromAlpha, toAlpha, duration, onDone)
    target:SetScript("OnUpdate", nil)   -- cancel any in-flight fade first
    local elapsed = 0
    target:SetAlpha(fromAlpha)
    target:SetScript("OnUpdate", function(self, dt)
        elapsed = elapsed + dt
        local t = math.min(elapsed / duration, 1)
        self:SetAlpha(fromAlpha + (toAlpha - fromAlpha) * t)
        if t >= 1 then
            self:SetScript("OnUpdate", nil)
            if onDone then onDone() end
        end
    end)
end

-- ── Skin-tinted overlay colour ────────────────────────────────────────────────
-- Full-screen dimmers (WhatsNew, FeatureList, FocusEditor and its AFK overlay)
-- all tint to the active skin colour when db.focusOverlayUseSkinColor is set,
-- black otherwise.
function BNB.OverlayColor()
    local db = BigNoteBoxDB
    if db and db.skinMode and db.focusOverlayUseSkinColor
       and BNB.GetSkinPreset and BNB.SkinColourOf then
        return BNB.SkinColourOf(BNB.GetSkinPreset(), false)
    end
    return 0, 0, 0
end

-- ── AutoCastGlow window border ────────────────────────────────────────────────
-- key must be unique per window. pad = { l, t, r, b } for a frame that is not
-- a seated ButtonFrameTemplate (BNB.BasicFrameGlowPad()); omit for the normal
-- seated-window placement. color/n/freq/scale default to the BNB-green glow
-- shared by WhatsNew and FeatureList; pass their own to use a different one
-- (e.g. SetupWizard's skin-border colour).
local DEFAULT_GLOW_COLOR = { 0.400, 0.733, 0.416, 1.0 }
local DEFAULT_GLOW_N     = 15
local DEFAULT_GLOW_FREQ  = 0.03
local DEFAULT_GLOW_SCALE = 1.5
-- FOR-16: the library pads left+right / top+bottom symmetrically, so asymmetric
-- clearance needs the glow frame re-anchored by hand afterward. Forever only:
-- its window chrome clips the glow at top and bottom, Retail's does not.
local GLOW_PAD_RIGHT  = 2
local GLOW_PAD_TOP    = 6
local GLOW_PAD_BOTTOM = 5

function BNB.StartWindowGlow(f, key, pad, color, n, freq, scale)
    if not f or not key then return end
    local lcg = BNB.GetLCG()
    if not lcg then return end
    pcall(lcg.AutoCastGlow_Start, f, color or DEFAULT_GLOW_COLOR, n or DEFAULT_GLOW_N,
          freq or DEFAULT_GLOW_FREQ, scale or DEFAULT_GLOW_SCALE, nil, nil, key)
    if pad then
        BNB.PadWindowGlow(f, key, pad.l, pad.t, pad.r, pad.b)
    elseif BNB.IsForever then
        local g = f["_AutoCastGlow" .. key]
        if g then
            local d = BNB.CHROME_DELTA or { l = 0, t = 0, r = 0, b = 0 }
            g:ClearAllPoints()
            g:SetPoint("TOPLEFT",     f, "TOPLEFT",     -d.l,                 GLOW_PAD_TOP + d.t)
            g:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", GLOW_PAD_RIGHT + d.r, -(GLOW_PAD_BOTTOM + d.b))
        end
    else
        BNB.NudgeRetailGlow(f, key)   -- RET-04
    end
end

function BNB.StopWindowGlow(f, key)
    if not f or not key then return end
    local lcg = BNB.GetLCG()
    if lcg then pcall(lcg.AutoCastGlow_Stop, f, key) end
end

-- ── PixelGlow border (DangerZone's red variant) ──────────────────────────────
function BNB.StartPixelGlow(f, key, color, n, freq, len)
    if not f or not key then return end
    local lcg = BNB.GetLCG()
    if lcg then
        pcall(lcg.PixelGlow_Start, f, color, n, freq, len, nil, nil, nil, nil, key)
    end
end

function BNB.StopPixelGlow(f, key)
    if not f or not key then return end
    local lcg = BNB.GetLCG()
    if lcg then pcall(lcg.PixelGlow_Stop, f, key) end
end

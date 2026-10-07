-- BigNoteBox UI/ToastStyles.lua -- Toast styles (ALL-376 S2, from ALL-160)
--
-- A style is one picture (a game atlas, or a game file with a crop) or a
-- plain backdrop, plus where the icon, title, text line, timer bar and the
-- "+N more" label sit on it. Measured in the Toast Lab (BigNoteBox_Dev
-- Labs/ToastLab.lua), whose Export gives one entry per style for STYLES
-- below. The lab draws its preview with BNB.ToastStyles.Apply, so the lab
-- shows exactly what a toast shows.
--
-- A style def (all numbers in toast pixels at Toast scale 1, from the
-- toast's top-left, y downward):
--   key      saved in toastStyle / note settings: never rename one
--   label    locale key (a lab export carries name instead until it gets one)
--   w, h     the toast's size
--   back     "plain" = the black backdrop; "skin" = the skin preset's colours
--   atlas    a game atlas drawn over the whole toast (nil with back / file)
--   file     a game file id + fw, fh (its size) + crop = { x, y, w, h } in
--            file pixels (nil = the whole file); flip "h" / "v" / "hv"
--   icon     { x, y, size, shape = "square" | "circle", frame = an
--            IconFrames key, border = { atlas, pad } (an atlas drawn around
--            the icon, pad px past it on every side; or { file = id, pad }) }
--   title    { x, y, w, scale = text scale (1 = GameFontNormal), justify }
--   text     { x, y, w, scale, justify }: why the toast showed
--   line2    { x, y, w, scale, justify }: the note's tl;dr or first line (S3)
--   bar      { x, y, w, h } or false (no timer bar)
--   more     { x, y } = the TOPRIGHT of the "+N more" label
--   faction  true = a meta style: the Horde / Alliance entry of `pick`
-- A style whose art this client lacks draws as "plain" with plain's layout.

local BNB = BigNoteBox
local L   = BNB.L

local TS = {}
BNB.ToastStyles = TS

-- ── The styles ──────────────────────────────────────────────────────────────
-- plain / skin share one layout (today's toast, 260 x 48)
local PLAIN_LAYOUT = {
    w = 260, h = 62,
    icon  = { x = 8,  y = 11, size = 38, shape = "square" },
    title = { x = 54, y = 8,  w = 198, scale = 1 },
    text  = { x = 54, y = 25, w = 150, scale = 1 },
    line2 = { x = 54, y = 40, w = 198, scale = 1 },
    bar   = { x = 0,  y = 60, w = 260, h = 2 },
    more  = { x = 254, y = 25 },
}

local function WithLayout(def, layout)
    for k, v in pairs(layout) do if def[k] == nil then def[k] = v end end
    return def
end

-- The loot toast pieces (Interface/LootFrame/LootToastAtlas): the art is
-- 282 x 100 (Horde) / 278 x 98 (Alliance) with an icon socket at the left.
-- First guess from Blizzard's LootWonAlertFrame; Dukul tunes it in the lab.
local LOOT_LAYOUT = {
    w = 280, h = 99,
    icon  = { x = 24, y = 24, size = 50, shape = "square",
              border = { atlas = "loottoast-itemborder-gold", pad = 4 } },
    title = { x = 88, y = 26, w = 170, scale = 1.1 },
    text  = { x = 88, y = 46, w = 130, scale = 1 },
    line2 = { x = 88, y = 62, w = 170, scale = 1 },
    bar   = { x = 86, y = 80, w = 172, h = 2 },
    more  = { x = 258, y = 46 },
}

local STYLES = {
    WithLayout({ key = "plain", label = "TOAST_STYLE_PLAIN", back = "plain" }, PLAIN_LAYOUT),
    WithLayout({ key = "skin",  label = "TOAST_STYLE_SKIN",  back = "skin",  classic = true, skinOnly = true }, PLAIN_LAYOUT),
    { key = "faction", label = "TOAST_STYLE_FACTION", faction = true,
      pick = { Horde = "loot-horde", Alliance = "loot-alliance" } },
    WithLayout({ key = "loot-horde",    label = "TOAST_STYLE_LOOT_HORDE",    atlas = "loottoast-bg-horde" },    LOOT_LAYOUT),
    WithLayout({ key = "loot-alliance", label = "TOAST_STYLE_LOOT_ALLIANCE", atlas = "loottoast-bg-alliance" }, LOOT_LAYOUT),
    -- Lab exports go here, one entry per style (ALL-376 S2)
}

local BY_KEY = {}
for _, s in ipairs(STYLES) do BY_KEY[s.key] = s end
TS.STYLES = STYLES
TS.DEFAULT = "faction"

-- ── Lookup ──────────────────────────────────────────────────────────────────
local _atlasOK = {}
local function HasAtlas(name)
    if _atlasOK[name] == nil then
        local ok, info = pcall(C_Texture.GetAtlasInfo, name)
        _atlasOK[name] = (ok and info) and true or false
    end
    return _atlasOK[name]
end

local function SkinOn()
    return BigNoteBoxDB and BigNoteBoxDB.skinMode and true or false
end

-- Whether a style can be drawn on this client right now (art present, skin
-- mode on for the skin style). The faction style asks its pick.
function TS.Usable(def)
    if not def then return false end
    if def.faction then
        local pick = def.pick and def.pick[UnitFactionGroup("player") or ""]
        return pick ~= nil and TS.Usable(BY_KEY[pick])
    end
    if def.skinOnly and not SkinOn() then return false end
    if def.atlas and not HasAtlas(def.atlas) then return false end
    return true
end

-- key -> the style def to draw: the faction style becomes its Horde /
-- Alliance entry, an unknown or unusable one becomes plain. A lab override
-- (TS.SetOverride) wins while set.
local _override = nil
function TS.Resolve(key)
    if _override then return _override end
    local def = BY_KEY[key or TS.DEFAULT] or BY_KEY[TS.DEFAULT]
    if def.faction then
        local pick = def.pick[UnitFactionGroup("player") or ""]
        def = BY_KEY[pick or ""]
    end
    if not TS.Usable(def) then def = BY_KEY.plain end
    return def
end

function TS.Get(key) return BY_KEY[key] end

-- A style's name: its locale key, else the lab name it was exported with
function TS.Label(def)
    if def.label and BNB.HasL(def.label) then return L[def.label] end
    return def.name or def.key
end

-- The player's chosen style key (nil = the default, the faction style)
function TS.Current()
    local db = BigNoteBoxDB
    return (db and db.toastStyle) or TS.DEFAULT
end

-- Styles the player can pick here, in list order: { { key, label }, ... }
function TS.List()
    local out = {}
    for _, s in ipairs(STYLES) do
        if TS.Usable(s) then out[#out + 1] = { key = s.key, label = TS.Label(s) } end
    end
    return out
end

-- The Toast Lab's live preview of an entry being made: every toast and the
-- anchor draw it until cleared with nil
function TS.SetOverride(def)
    _override = def
    if BNB.Toast and BNB.Toast.Restyle then BNB.Toast.Restyle() end
end

-- ── Drawing ─────────────────────────────────────────────────────────────────
local DEFAULT_ICON = "Interface\\AddOns\\BigNoteBox\\Assets\\icon"

local function Flip(l, r, t, b, flip)
    if flip == "h" or flip == "hv" then l, r = r, l end
    if flip == "v" or flip == "hv" then t, b = b, t end
    return l, r, t, b
end

-- The toast frame's own parts, made once per frame
function TS.Build(f)
    if f._tsBuilt then return end
    f._tsBuilt = true
    local art = f:CreateTexture(nil, "BACKGROUND")
    art:SetAllPoints()
    f._art = art

    local icon = f:CreateTexture(nil, "ARTWORK")
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    f._icon = icon
    local border = f:CreateTexture(nil, "OVERLAY")
    f._iconBorder = border
    f._iconFrame  = f:CreateTexture(nil, "OVERLAY")

    local lbl = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    lbl:SetWordWrap(false)
    f._lbl = lbl
    local sub = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    sub:SetWordWrap(false)
    sub:SetTextColor(0.65, 0.65, 0.65)
    f._sub = sub
    local line2 = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    line2:SetWordWrap(false)
    line2:SetTextColor(0.85, 0.85, 0.85)
    f._line2 = line2

    -- The note has a waypoint the situation places: a small pin on the
    -- icon's top-right corner
    local pin = f:CreateTexture(nil, "OVERLAY", nil, 3)
    pin:SetSize(16, 16)
    pin:SetPoint("CENTER", icon, "TOPRIGHT", -2, -2)
    pin:Hide()
    f._pin = pin

    local more = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    more:SetJustifyH("RIGHT")
    more:SetTextColor(1, 0.82, 0)
    more:Hide()
    f._more = more

    local bar = f:CreateTexture(nil, "OVERLAY", nil, 2)
    bar:SetColorTexture(0.3, 0.75, 0.3, 0.9)
    f._bar = bar
end

local function PlaceText(fs, box, f)
    fs:ClearAllPoints()
    if not box then fs:SetText(""); fs:Hide(); return end
    fs:SetPoint("TOPLEFT", f, "TOPLEFT", box.x, -box.y)
    fs:SetWidth(box.w or 100)
    fs:SetJustifyH(box.justify or "LEFT")
    fs:SetTextScale(box.scale or 1)
    fs:Show()
end

-- Lays f out as def: size, background, icon box, text boxes, bar, more.
-- Content (icon texture, texts) is the caller's; the bar's width is reset
-- to full (the engine shortens it as time runs).
function TS.Apply(f, def)
    TS.Build(f)
    def = def or BY_KEY.plain
    f._style = def
    f:SetSize(def.w, def.h)

    -- Background: a backdrop for plain / skin, a picture for the rest
    local art = f._art
    if def.back then
        art:Hide()
        if def.back == "skin" and SkinOn() and BNB.GetSkinPreset then
            local p = BNB.GetSkinPreset()
            local r, g, b = BNB.SkinColourOf(p)
            local br, bg, bb = BNB.SkinBorderOf(p)
            BNB.SetBackdrop(f, r, g, b, BNB.GetSkinBgAlpha(), br, bg, bb, 1)
        else
            BNB.SetBackdrop(f, 0.06, 0.06, 0.09, 0.94, 0.40, 0.40, 0.42, 1)
        end
    else
        BNB.SetBackdrop(f, 0, 0, 0, 0, 0, 0, 0, 0)
        if def.atlas and def.flip then
            -- A flipped atlas: its file and corners, mirrored
            local info = C_Texture.GetAtlasInfo(def.atlas)
            art:SetTexture(info.file or info.filename)
            art:SetTexCoord(Flip(info.leftTexCoord, info.rightTexCoord,
                                 info.topTexCoord, info.bottomTexCoord, def.flip))
        elseif def.atlas then
            art:SetAtlas(def.atlas)
        elseif def.file then
            art:SetTexture(def.file)
            local W, H = def.fw, def.fh
            local c = def.crop
            if c and W and H then
                -- Half-texel inset, as the icon frames: no neighbour line
                art:SetTexCoord(Flip((c[1] + 0.5) / W, (c[1] + c[3] - 0.5) / W,
                                     (c[2] + 0.5) / H, (c[2] + c[4] - 0.5) / H, def.flip))
            else
                art:SetTexCoord(Flip(0, 1, 0, 1, def.flip))
            end
        end
        art:Show()
    end

    -- Icon, its shape, frame and border
    local ib, icon = def.icon, f._icon
    if ib then
        icon:ClearAllPoints()
        icon:SetSize(ib.size, ib.size)
        icon:SetPoint("TOPLEFT", f, "TOPLEFT", ib.x, -ib.y)
        icon:Show()
        local IFL = BNB.IconFrameLayer
        local fdef = ib.frame and BNB.IconFrames and BNB.IconFrames.Get(ib.frame)
        if IFL and fdef then
            IFL.Apply(icon, f._iconFrame, fdef, ib.size)
        elseif IFL then
            IFL.HideTex(f._iconFrame)
            IFL.SetShape(icon, ib.shape)
        end
        local bd = ib.border
        local bdOK = bd and ((bd.atlas and HasAtlas(bd.atlas)) or bd.file)
        if bdOK then
            local pad = bd.pad or 0
            if bd.atlas then f._iconBorder:SetAtlas(bd.atlas)
            else f._iconBorder:SetTexture(bd.file); f._iconBorder:SetTexCoord(0, 1, 0, 1) end
            f._iconBorder:ClearAllPoints()
            f._iconBorder:SetPoint("TOPLEFT", icon, "TOPLEFT", -pad, pad)
            f._iconBorder:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", pad, -pad)
            f._iconBorder:Show()
        else
            f._iconBorder:Hide()
        end
    else
        icon:Hide(); f._iconBorder:Hide()
        if BNB.IconFrameLayer then BNB.IconFrameLayer.HideTex(f._iconFrame) end
    end

    -- A note's own icon frame from the last fill (BNB.ApplyIconFrame)
    if icon._ifTex and BNB.IconFrameLayer then BNB.IconFrameLayer.HideTex(icon._ifTex) end
    f._pin:Hide()

    PlaceText(f._lbl, def.title, f)
    PlaceText(f._sub, def.text, f)
    PlaceText(f._line2, def.line2, f)

    local bar = f._bar
    bar:ClearAllPoints()
    if def.bar then
        bar:SetPoint("TOPLEFT", f, "TOPLEFT", def.bar.x, -def.bar.y)
        bar:SetHeight(def.bar.h)
        bar:SetWidth(def.bar.w)
        f._barW = def.bar.w
    else
        f._barW = nil
        bar:Hide()
    end

    f._more:ClearAllPoints()
    local m = def.more or { x = def.w - 6, y = def.h - 18 }
    f._more:SetPoint("TOPRIGHT", f, "TOPLEFT", m.x, -m.y)
end

-- The waypoint pin: the game's chat map pin where the client has it
local PIN_ATLAS = "Waypoint-MapPin-ChatIcon"
local PIN_FILE  = "Interface\\Icons\\INV_Misc_Map_01"

-- Fills the content of a laid-out toast (used by the engine and the lab):
-- c = { icon, title, titleColor, text, line2, pin, noIcon, iconSetup }.
-- iconSetup(tex, f) runs after the icon is set (a note's portrait or its own
-- icon frame); it returns true when it drew a frame, which then replaces the
-- style's frame and border
function TS.Fill(f, c)
    local icon = f._icon
    local def = f._style
    if c.noIcon or not (def and def.icon) then
        icon:Hide(); f._iconBorder:Hide()
        if BNB.IconFrameLayer then BNB.IconFrameLayer.HideTex(f._iconFrame) end
    else
        icon:SetTexture(c.icon or DEFAULT_ICON)
        if c.iconSetup and c.iconSetup(icon, f) then
            f._iconBorder:Hide()
            if BNB.IconFrameLayer then BNB.IconFrameLayer.HideTex(f._iconFrame) end
        end
    end
    f._lbl:SetText(c.title or "")
    local tc = c.titleColor
    if tc then f._lbl:SetTextColor(tc.r or 1, tc.g or 0.82, tc.b or 0, 1)
    else       f._lbl:SetTextColor(1, 0.82, 0, 1) end
    f._sub:SetText(c.text or "")
    f._line2:SetText(c.line2 or "")
    if c.pin and icon:IsShown() then
        if HasAtlas(PIN_ATLAS) then f._pin:SetAtlas(PIN_ATLAS)
        else f._pin:SetTexture(PIN_FILE) end
        f._pin:Show()
    else
        f._pin:Hide()
    end
end

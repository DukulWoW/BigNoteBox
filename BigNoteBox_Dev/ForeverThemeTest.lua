-- ForeverThemeTest.lua
-- A test window in the WoW Forever look, for Retail and Classic (Dukul,
-- 2026-11-01: "create a test forever window for retail and classic so we can
-- see how it looks"). /bnbforever toggles it. Dev only, never packaged;
-- nothing in BigNoteBox is changed.
--
-- Art: BigNoteBox/Themes/Forever/Assets, TGA made from the PNGs Dukul pulled
-- from the Forever client (_work/tools/forever-art.py). Shown here:
--   Frame     the metal frame (corners, tiled edges, the top band's title
--             strip), with the double top-right corner as a second style
--   Buttons   red icon buttons (normal / pressed / disabled), the three-part
--             red text button, the small title-bar buttons
--   Scrollbar the minimal scrollbar, drawn by hand; arrows inactive at the ends
-- The background is not Forever art (none was found): plain dark and two
-- game tiles (Background button). Frame scale: the -2x art's own size is
-- 0.5; 0.40 is the default (Dukul, 2026-11-01: the X then matches the
-- Retail main window's). The scale slider is bronze: the scrollbar art
-- turned a quarter left.

local function B() return BigNoteBox end

local ART = "Interface\\AddOns\\BigNoteBox\\Themes\\Forever\\Assets\\"
local function T(p) return ART .. p end

local W, H, PAD = 600, 560, 22
local panel
local SCALE_DEFAULT = 0.4
local scale   = SCALE_DEFAULT  -- frame art scale
local style   = "metal"      -- "metal" or "double" (the diamond / header art went 2026-11-10)
local STYLES  = { metal = "Metal", double = "Metal, double" }
local NEXT    = { metal = "double", double = "metal" }
local bgIndex = 1
local BGS = {
    -- The Forever look the main window uses (UI/Chrome.lua): our tileable wood
    -- grain with the soft orange glow stretched over it (Dukul, 2026-11-01)
    { name = "Forever", file = "Interface\\AddOns\\BigNoteBox\\Assets\\UI\\ui-bg-forever", tile = 256,
      glow = "Interface\\AddOns\\BigNoteBox\\Assets\\UI\\ui-bg-sp-highlight" },
    { name = "Dark",   color = { 0.06, 0.05, 0.04, 0.96 } },
    { name = "Dialog", file = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark", tile = 64 },
    { name = "Rock",   file = "Interface\\FrameGeneral\\UI-Background-Rock", tile = 256 },
}
local LOREM = "The minimal scrollbar from the Forever client, drawn piece by piece: "
    .. "arrows on top and bottom, a track (top, a 1 px middle stretched, bottom) and a thumb "
    .. "(top cap, a stretched middle, a bottom cap that fades into it). Hover and press the "
    .. "thumb and the arrows to see their over and down art; the arrow under the bar jumps "
    .. "to the bottom, the way chat does.\n\n"
    .. "Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor "
    .. "incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud "
    .. "exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat.\n\n"
    .. "Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu "
    .. "fugiat nulla pariatur. Excepteur sint occaecat cupidatat non proident, sunt in culpa "
    .. "qui officia deserunt mollit anim id est laborum.\n\n"
    .. "Sed ut perspiciatis unde omnis iste natus error sit voluptatem accusantium doloremque "
    .. "laudantium, totam rem aperiam, eaque ipsa quae ab illo inventore veritatis et quasi "
    .. "architecto beatae vitae dicta sunt explicabo."

-- ── Background and frame ─────────────────────────────────────────────────────
local bg, glow
local bgInset = 0
local parts = {}

local function PaintBg()
    local d = BGS[bgIndex]
    if d.color then
        bg:SetColorTexture(d.color[1], d.color[2], d.color[3], d.color[4])
        bg:SetTexCoord(0, 1, 0, 1)
    else
        bg:SetTexture(d.file, "REPEAT", "REPEAT")
        bg:SetVertexColor(1, 1, 1, 1)
        bg:SetTexCoord(0, (panel:GetWidth() - 2 * bgInset) / d.tile, 0, (panel:GetHeight() - 2 * bgInset) / d.tile)
    end
    if d.glow then glow:SetTexture(d.glow); glow:Show() else glow:Hide() end
end

-- The background stays inside the frame (Dukul, 2026-11-01: it overflowed):
-- 10 art px in from the frame's outer line, where every corner's bevel is
-- fully opaque
local function PlaceBg()
    local i = 10 * scale
    bgInset = i
    for _, t in ipairs({ bg, glow }) do
        t:ClearAllPoints()
        t:SetPoint("TOPLEFT", panel, "TOPLEFT", i, -i)
        t:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -i, i)
    end
end

local function BuildFrame()
    local function Tex(sub) return panel:CreateTexture(nil, "BORDER", nil, sub) end
    -- Metal (Dukul's corrected set, 2026-11-01): corners 190 x 190 (bottom
    -- 190 x 200), side edges 190 x 256 tiled down, top / bottom bands 256 wide
    -- tiled across. The pieces meet at their own sizes, no offsets.
    parts.mtl = Tex(3); parts.mtl:SetTexture(T("Frame\\metal-corner-topleft"))
    parts.mtr = Tex(3)
    parts.mbl = Tex(3); parts.mbl:SetTexture(T("Frame\\metal-corner-bottomleft"))
    parts.mbr = Tex(3); parts.mbr:SetTexture(T("Frame\\metal-corner-bottomright"))
    parts.mtop    = Tex(2); parts.mtop:SetTexture(T("Frame\\metal-edge-top"), "REPEAT", "CLAMP")
    parts.mbottom = Tex(2); parts.mbottom:SetTexture(T("Frame\\metal-edge-bottom"), "REPEAT", "CLAMP")
    parts.mleft   = Tex(1); parts.mleft:SetTexture(T("Frame\\metal-edge-left"), "CLAMP", "REPEAT")
    parts.mright  = Tex(1); parts.mright:SetTexture(T("Frame\\metal-edge-right"), "CLAMP", "REPEAT")
end

-- Metal: the frame's outer line is column 23 on the left, 187 of 190 on the
-- right, row 24 at the top and 190 of 200 at the bottom; those go on the
-- window's edges, so the bars lie just inside the window. The top band's
-- dark title strip is rows 24-83 (title and title-bar buttons centred on 53).
local ML, MR, MT, MB, MBAND = 23, 3, 24, 10, 53.5
local function LayoutMetal(w, h)
    local p, s = parts, scale
    local C = 190 * s
    p.mtr:SetTexture(T(style == "double" and "Frame\\metal-corner-toprightdouble" or "Frame\\metal-corner-topright"))
    for _, k in ipairs({ "mtl", "mtr", "mbl", "mbr" }) do p[k]:ClearAllPoints() end
    p.mtl:SetSize(C, C); p.mtr:SetSize(C, C)
    p.mbl:SetSize(C, 200 * s); p.mbr:SetSize(C, 200 * s)
    p.mtl:SetPoint("TOPLEFT", panel, "TOPLEFT", -ML * s, MT * s)
    p.mtr:SetPoint("TOPRIGHT", panel, "TOPRIGHT", MR * s, MT * s)
    p.mbl:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", -ML * s, -MB * s)
    p.mbr:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", MR * s, -MB * s)
    local span  = math.max(1, w + (ML + MR) * s - 2 * C)
    local vspan = math.max(1, h + (MT + MB) * s - 190 * s - 200 * s)
    p.mtop:ClearAllPoints(); p.mbottom:ClearAllPoints(); p.mleft:ClearAllPoints(); p.mright:ClearAllPoints()
    p.mtop:SetPoint("TOPLEFT", p.mtl, "TOPRIGHT"); p.mtop:SetPoint("BOTTOMRIGHT", p.mtr, "BOTTOMLEFT")
    p.mtop:SetTexCoord(0, span / (256 * s), 0, 1)
    p.mbottom:SetPoint("TOPLEFT", p.mbl, "TOPRIGHT"); p.mbottom:SetPoint("BOTTOMRIGHT", p.mbr, "BOTTOMLEFT")
    p.mbottom:SetTexCoord(0, span / (256 * s), 0, 1)
    p.mleft:SetPoint("TOPLEFT", p.mtl, "BOTTOMLEFT"); p.mleft:SetPoint("BOTTOMRIGHT", p.mbl, "TOPRIGHT")
    p.mleft:SetTexCoord(0, 1, 0, vspan / (256 * s))
    p.mright:SetPoint("TOPLEFT", p.mtr, "BOTTOMLEFT"); p.mright:SetPoint("BOTTOMRIGHT", p.mbr, "TOPRIGHT")
    p.mright:SetTexCoord(0, 1, 0, vspan / (256 * s))
end

-- Title and the title-bar buttons in the top band's title strip, sized to it
local function LayoutTitle()
    local title, sub, tb = panel._title, panel._sub, panel._tb
    if not title then return end
    local s = scale
    local cy = (MT - MBAND) * s
    title:ClearAllPoints()
    title:SetPoint("CENTER", panel, "TOP", 0, cy)
    sub:ClearAllPoints()
    sub:SetPoint("TOP", panel, "TOP", 0, (MT - 83) * s - 5)
    local size = math.max(16, math.floor(56 * s + 0.5))
    for i, b in ipairs(tb) do
        b:SetSize(size, size)
        b:ClearAllPoints()
        -- The X covers the right border as well as the band's top and
        -- bottom (Dukul, 2026-11-01): its right edge past the window's
        if i == 1 then b:SetPoint("RIGHT", panel, "TOPRIGHT", 4 * s, cy)
        else b:SetPoint("RIGHT", tb[i - 1], "LEFT", -1, 0) end
    end
end

local function LayoutFrame()
    LayoutMetal(panel:GetWidth(), panel:GetHeight())
    PlaceBg()
    PaintBg()
    LayoutTitle()
end

-- ── Buttons ──────────────────────────────────────────────────────────────────
-- A square button from a base name: normal / -pressed / -disabled files
local function SetStates(b, base)
    b:SetNormalTexture(T(base))
    b:SetPushedTexture(T(base .. "-pressed"))
    b:SetDisabledTexture(T(base .. "-disabled"))
end

-- 128 px red icon button; highlight = its own art added at 30 %
local function IconButton(parent, name, size)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(size, size)
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints(); hl:SetBlendMode("ADD"); hl:SetAlpha(0.3)
    function b:SetArt(n)
        SetStates(self, "Buttons\\redbutton-" .. n)
        hl:SetTexture(T("Buttons\\redbutton-" .. n))
    end
    b:SetArt(name)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("redbutton-" .. (self._name or name), 1, 1, 1)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return b
end

-- 64 px (2x) title-bar button with the art's own red glow as highlight
local function SmallButton(parent, name, size)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(size, size)
    function b:SetArt(n) SetStates(self, "Buttons\\small-" .. n) end
    b:SetArt(name)
    b:SetHighlightTexture(T("Buttons\\small-highlight"), "ADD")
    return b
end

-- The three-part red text button: left cap 114, center 64 (tiled), right
-- 292, all 128 high; scaled to the button's height
local function TextButton(parent, text, width, height)
    height = height or 32
    local k = height / 128
    width = math.max(width, math.ceil((114 + 292) * k))
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(width, height)
    local l = b:CreateTexture(nil, "BACKGROUND"); l:SetPoint("TOPLEFT"); l:SetSize(114 * k, height)
    local r = b:CreateTexture(nil, "BACKGROUND"); r:SetPoint("TOPRIGHT"); r:SetSize(292 * k, height)
    local c = b:CreateTexture(nil, "BACKGROUND")
    c:SetPoint("TOPLEFT", l, "TOPRIGHT"); c:SetPoint("BOTTOMRIGHT", r, "BOTTOMLEFT")
    local cw = width - (114 + 292) * k
    local hls = {}
    for i, src in ipairs({ l, c, r }) do
        local hl = b:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints(src); hl:SetBlendMode("ADD"); hl:SetAlpha(0.22)
        hls[i] = hl
    end
    local function Paint(state)
        local s = state and ("-" .. state) or ""
        l:SetTexture(T("Buttons\\redbutton-left" .. s))
        r:SetTexture(T("Buttons\\redbutton-right" .. s))
        c:SetTexture(T("Buttons\\redbutton-center" .. s), "REPEAT", "CLAMP")
        c:SetTexCoord(0, math.max(cw, 0.01) / (64 * k), 0, 1)
        hls[1]:SetTexture(T("Buttons\\redbutton-left"))
        hls[3]:SetTexture(T("Buttons\\redbutton-right"))
        hls[2]:SetTexture(T("Buttons\\redbutton-center"), "REPEAT", "CLAMP")
        hls[2]:SetTexCoord(0, math.max(cw, 0.01) / (64 * k), 0, 1)
    end
    local fs = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    fs:SetPoint("CENTER")
    fs:SetText(text)
    b._label = fs
    Paint(nil)
    b:SetScript("OnMouseDown", function(self)
        if not self:IsEnabled() then return end
        Paint("pressed"); fs:ClearAllPoints(); fs:SetPoint("CENTER", 1, -1)
    end)
    b:SetScript("OnMouseUp", function(self)
        if not self:IsEnabled() then return end
        Paint(nil); fs:ClearAllPoints(); fs:SetPoint("CENTER")
    end)
    function b:SetOff(off)
        self:SetEnabled(not off)
        Paint(off and "disabled" or nil)
        if off then fs:SetTextColor(0.5, 0.5, 0.5) else fs:SetTextColor(1, 0.82, 0) end
    end
    return b
end

-- ── Minimal scrollbar ────────────────────────────────────────────────────────
-- The normal minimal scrollbar only (Dukul, 2026-11-01: the small one's
-- track has a gray rim). text = the box's text (default the long one).
local function MinimalScroll(parent, w, h, text)
    local pre = "Scrollbar\\"
    local host = CreateFrame("Frame", nil, parent)
    host:SetSize(w, h)
    local shade = host:CreateTexture(nil, "BACKGROUND")
    shade:SetAllPoints(); shade:SetColorTexture(0, 0, 0, 0.35)

    local sf = CreateFrame("ScrollFrame", nil, host)
    sf:SetPoint("TOPLEFT", 8, -8)
    sf:SetPoint("BOTTOMRIGHT", -28, 8)
    local child = CreateFrame("Frame", nil, sf)
    child:SetSize(w - 36, 10)
    sf:SetScrollChild(child)
    local fs = child:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fs:SetPoint("TOPLEFT")
    fs:SetWidth(w - 36)
    fs:SetJustifyH("LEFT")
    fs:SetText(text or LOREM)

    local bar = CreateFrame("Frame", nil, host)
    bar:SetPoint("TOPRIGHT", -5, -6)
    bar:SetPoint("BOTTOMRIGHT", -5, 6)
    bar:SetWidth(17)
    local function Arrow(name, ah)
        local b = CreateFrame("Button", nil, bar)
        b:SetSize(17, ah)
        b:SetNormalTexture(T(pre .. name))
        b:SetPushedTexture(T(pre .. name .. "-down"))
        b:SetHighlightTexture(T(pre .. name .. "-over"), "BLEND")
        return b
    end
    local up   = Arrow("arrow-top", 11);            up:SetPoint("TOP")
    local ret  = Arrow("arrow-returntobottom", 15); ret:SetPoint("BOTTOM")
    local down = Arrow("arrow-bottom", 11);         down:SetPoint("BOTTOM", ret, "TOP", 0, 3)

    local track = CreateFrame("Frame", nil, bar)
    track:SetWidth(8)
    track:SetPoint("TOP", up, "BOTTOM", 0, -3)
    track:SetPoint("BOTTOM", down, "TOP", 0, 3)
    local tt = track:CreateTexture(nil, "BACKGROUND"); tt:SetSize(8, 8); tt:SetPoint("TOP")
    tt:SetTexture(T(pre .. "track-top"))
    local tb = track:CreateTexture(nil, "BACKGROUND"); tb:SetSize(8, 8); tb:SetPoint("BOTTOM")
    tb:SetTexture(T(pre .. "track-bottom"))
    local tm = track:CreateTexture(nil, "BACKGROUND")
    tm:SetPoint("TOPLEFT", tt, "BOTTOMLEFT"); tm:SetPoint("BOTTOMRIGHT", tb, "TOPRIGHT")
    tm:SetTexture(T(pre .. "track-middle"))

    -- Thumb: top 8, bottom 36 over the middle; the middle is 515 px of art
    -- shown 1:1 from its top, never squeezed
    local BOT, MIDH = 36, 515
    local MINH = 8 + BOT
    local thumb = CreateFrame("Button", nil, track)
    thumb:SetWidth(8)
    local th = thumb:CreateTexture(nil, "ARTWORK", nil, 1); th:SetSize(8, 8); th:SetPoint("TOP")
    local tbot = thumb:CreateTexture(nil, "ARTWORK", nil, 2); tbot:SetSize(8, BOT); tbot:SetPoint("BOTTOM")
    local tmid = thumb:CreateTexture(nil, "ARTWORK", nil, 0)
    tmid:SetPoint("TOPLEFT", th, "BOTTOMLEFT"); tmid:SetPoint("BOTTOMRIGHT", thumb, "BOTTOMRIGHT", 0, 8)
    local function PaintThumb(state)
        local s = state and ("-" .. state) or ""
        th:SetTexture(T(pre .. "thumb-top" .. s))
        tbot:SetTexture(T(pre .. "thumb-bottom" .. s))
        tmid:SetTexture(T(pre .. "thumb-middle" .. s))
    end
    PaintThumb(nil)

    local function Range() return sf:GetVerticalScrollRange() or 0 end
    local function Update()
        local range, trackH, vis = Range(), track:GetHeight(), sf:GetHeight()
        local pos = sf:GetVerticalScroll()
        -- Each arrow goes inactive at its end (Dukul, 2026-11-01), dimmed:
        -- the art has no disabled look of its own
        local atBottom = range <= 0 or pos >= range - 0.5
        for _, a in ipairs({ { up, range > 0 and pos > 0.5 }, { down, not atBottom }, { ret, not atBottom } }) do
            a[1]:SetEnabled(a[2])
            a[1]:SetAlpha(a[2] and 1 or 0.35)
        end
        if range <= 0 or trackH <= 0 then thumb:Hide(); return end
        thumb:Show()
        local tH = math.max(MINH, math.floor(trackH * vis / (vis + range)))
        thumb:SetHeight(tH)
        local off = (trackH - tH) * sf:GetVerticalScroll() / range
        thumb:ClearAllPoints()
        thumb:SetPoint("TOP", track, "TOP", 0, -off)
        tmid:SetTexCoord(0, 1, 0, math.min(1, math.max(1, tH - 16) / MIDH))
    end
    local function SetScroll(v)
        sf:SetVerticalScroll(math.max(0, math.min(Range(), v)))
        Update()
    end
    host._update = function()
        child:SetHeight(fs:GetStringHeight() + 4)
        Update()
    end

    sf:EnableMouseWheel(true)
    sf:SetScript("OnMouseWheel", function(_, d) SetScroll(sf:GetVerticalScroll() - d * 30) end)
    sf:SetScript("OnScrollRangeChanged", function() Update() end)
    up:SetScript("OnClick", function() SetScroll(sf:GetVerticalScroll() - 30) end)
    down:SetScript("OnClick", function() SetScroll(sf:GetVerticalScroll() + 30) end)
    ret:SetScript("OnClick", function() SetScroll(Range()) end)

    -- A click on the track pages toward the cursor
    track:EnableMouse(true)
    track:SetScript("OnMouseDown", function(self)
        local _, cy = GetCursorPosition()
        cy = cy / self:GetEffectiveScale()
        local tTop = thumb:GetTop() or 0
        local page = sf:GetHeight() - 20
        SetScroll(sf:GetVerticalScroll() + (cy > tTop and -page or page))
    end)

    thumb:SetScript("OnEnter", function(self) if not self._drag then PaintThumb("over") end end)
    thumb:SetScript("OnLeave", function(self) if not self._drag then PaintThumb(nil) end end)
    thumb:SetScript("OnMouseDown", function(self, btn)
        if btn ~= "LeftButton" then return end
        PaintThumb("down")
        local s = self:GetEffectiveScale()
        local _, cy = GetCursorPosition()
        self._drag = { y = cy / s, pos = sf:GetVerticalScroll() }
        self:SetScript("OnUpdate", function(me)
            local _, y = GetCursorPosition()
            local span = track:GetHeight() - me:GetHeight()
            if span > 0 then SetScroll(me._drag.pos + (me._drag.y - y / s) * Range() / span) end
        end)
    end)
    thumb:SetScript("OnMouseUp", function(self)
        self:SetScript("OnUpdate", nil)
        self._drag = nil
        PaintThumb(self:IsMouseOver() and "over" or nil)
    end)
    return host
end

-- ── Bronze slider ────────────────────────────────────────────────────────────
-- The minimal scrollbar's art turned a quarter left (Dukul, 2026-11-01: "the
-- one used for frame scale should also be bronze"): the art's top goes left,
-- its bottom right, so up / down arrows become < / >, the caps follow.
-- v = how much of the art's height to show (the thumb middle), default all.
local function Rot(tex, v)
    v = v or 1
    tex:SetTexCoord(1, 0, 0, 0, 1, v, 0, v)
end

-- o = { label, min, max, step, value, default, onChange }. Row 1: label,
-- value, default, Reset (gray at the default). Row 2: < track >; the arrows
-- go inactive at the ends like the scrollbar's. Drag the thumb, click the
-- track, or the mouse wheel.
local function ForeverSlider(parent, width, o)
    local pre = "Scrollbar\\"
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(width, 48)

    local lbl = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    lbl:SetPoint("TOPLEFT", 0, -4)
    lbl:SetText(o.label)
    local val = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    val:SetPoint("LEFT", lbl, "RIGHT", 6, 0)
    local def = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    def:SetPoint("LEFT", val, "RIGHT", 6, 0)
    def:SetText(string.format("(Default: %.2f)", o.default))
    local reset = TextButton(f, "Reset", 74, 22)
    reset:SetPoint("TOPRIGHT")

    local function Arrow(name)
        local b = CreateFrame("Button", nil, f)
        b:SetSize(11, 17)
        b:SetNormalTexture(T(pre .. name));             Rot(b:GetNormalTexture())
        b:SetPushedTexture(T(pre .. name .. "-down"));  Rot(b:GetPushedTexture())
        b:SetHighlightTexture(T(pre .. name .. "-over"), "BLEND"); Rot(b:GetHighlightTexture())
        return b
    end
    local left  = Arrow("arrow-top");    left:SetPoint("BOTTOMLEFT", 0, 0)
    local right = Arrow("arrow-bottom"); right:SetPoint("BOTTOMRIGHT", 0, 0)

    local track = CreateFrame("Frame", nil, f)
    track:SetHeight(8)
    track:SetPoint("LEFT", left, "RIGHT", 4, 0)
    track:SetPoint("RIGHT", right, "LEFT", -4, 0)
    local tl = track:CreateTexture(nil, "BACKGROUND"); tl:SetSize(8, 8); tl:SetPoint("LEFT")
    tl:SetTexture(T(pre .. "track-top")); Rot(tl)
    local tr = track:CreateTexture(nil, "BACKGROUND"); tr:SetSize(8, 8); tr:SetPoint("RIGHT")
    tr:SetTexture(T(pre .. "track-bottom")); Rot(tr)
    local tm = track:CreateTexture(nil, "BACKGROUND")
    tm:SetPoint("TOPLEFT", tl, "TOPRIGHT"); tm:SetPoint("BOTTOMRIGHT", tr, "BOTTOMLEFT")
    tm:SetTexture(T(pre .. "track-middle")); Rot(tm)

    -- Thumb: Dukul's bronze diamond knob (2026-11-01, slider-diamond, 32 px
    -- art shown at 22) centred on the track. It has one look: hover adds
    -- its own art as a glow, a press darkens it a little.
    local TW = 22
    local thumb = CreateFrame("Button", nil, track)
    thumb:SetSize(TW, TW)
    local knob = thumb:CreateTexture(nil, "ARTWORK")
    knob:SetAllPoints()
    knob:SetTexture(T(pre .. "slider-diamond"))
    local knobGlow = thumb:CreateTexture(nil, "OVERLAY")
    knobGlow:SetAllPoints()
    knobGlow:SetTexture(T(pre .. "slider-diamond"))
    knobGlow:SetBlendMode("ADD")
    knobGlow:SetAlpha(0.35)
    local function PaintThumb(state)
        if state == "over" then knobGlow:Show() else knobGlow:Hide() end
        local c = (state == "down") and 0.75 or 1
        knob:SetVertexColor(c, c, c)
    end
    PaintThumb(nil)

    local value = o.value
    local function Snap(v)
        v = math.floor((v - o.min) / o.step + 0.5) * o.step + o.min
        return math.max(o.min, math.min(o.max, v))
    end
    local function Place()
        local span = track:GetWidth() - TW
        local x = span > 0 and span * (value - o.min) / (o.max - o.min) or 0
        thumb:ClearAllPoints()
        thumb:SetPoint("LEFT", track, "LEFT", x, 0)
        val:SetText(string.format("%.2f", value))
        local lo, hi = value > o.min + 1e-6, value < o.max - 1e-6
        left:SetEnabled(lo);  left:SetAlpha(lo and 1 or 0.35)
        right:SetEnabled(hi); right:SetAlpha(hi and 1 or 0.35)
        reset:SetOff(math.abs(value - o.default) < 1e-6)
    end
    local function Set(v)
        v = Snap(v)
        if math.abs(v - value) < 1e-6 then Place(); return end
        value = v
        Place()
        o.onChange(v)
    end
    -- Value at a cursor x (UI units), the thumb's grab point kept under it
    local function ValueAt(cx, grab)
        local span = track:GetWidth() - TW
        if span <= 0 then return value end
        return o.min + (cx - (track:GetLeft() or 0) - grab) / span * (o.max - o.min)
    end

    left:SetScript("OnClick", function() Set(value - o.step) end)
    right:SetScript("OnClick", function() Set(value + o.step) end)
    reset:SetScript("OnClick", function() Set(o.default) end)
    f:EnableMouseWheel(true)
    f:SetScript("OnMouseWheel", function(_, d) Set(value + d * o.step) end)
    track:EnableMouse(true)
    track:SetScript("OnMouseDown", function(self)
        local cx = GetCursorPosition() / self:GetEffectiveScale()
        Set(ValueAt(cx, TW / 2))
    end)
    thumb:SetScript("OnEnter", function(self) if not self._drag then PaintThumb("over") end end)
    thumb:SetScript("OnLeave", function(self) if not self._drag then PaintThumb(nil) end end)
    thumb:SetScript("OnMouseDown", function(self, btn)
        if btn ~= "LeftButton" then return end
        PaintThumb("down")
        local sc = self:GetEffectiveScale()
        self._drag = GetCursorPosition() / sc - (self:GetLeft() or 0)
        self:SetScript("OnUpdate", function(me)
            Set(ValueAt(GetCursorPosition() / sc, me._drag))
        end)
    end)
    thumb:SetScript("OnMouseUp", function(self)
        self:SetScript("OnUpdate", nil)
        self._drag = nil
        PaintThumb(self:IsMouseOver() and "over" or nil)
    end)
    -- Placed once the track has a width
    f:SetScript("OnSizeChanged", Place)
    f:SetScript("OnShow", function() C_Timer.After(0, Place) end)
    C_Timer.After(0, Place)
    return f
end

-- ── The window ───────────────────────────────────────────────────────────────
local function ClientName()
    local b = B()
    if b and b.IsForever then return "WoW Forever" end
    if b and b.IsClassic then return "Classic" end
    return "Retail"
end

local function Build()
    panel = CreateFrame("Frame", "BNBForeverThemeTest", UIParent)
    panel:SetSize(W, H)
    panel:SetPoint("CENTER")
    panel:SetFrameStrata("DIALOG")
    panel:SetToplevel(true)
    panel:SetClampedToScreen(true)
    panel:EnableMouse(true)
    panel:SetMovable(true)
    panel:RegisterForDrag("LeftButton")
    panel:SetScript("OnDragStart", panel.StartMoving)
    panel:SetScript("OnDragStop", panel.StopMovingOrSizing)
    tinsert(UISpecialFrames, "BNBForeverThemeTest")

    bg = panel:CreateTexture(nil, "BACKGROUND")
    glow = panel:CreateTexture(nil, "BACKGROUND", nil, 7)
    BuildFrame()

    local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -16)
    title:SetText("Forever theme test")
    panel._title = title
    local sub = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    sub:SetPoint("TOP", title, "BOTTOM", 0, -3)
    panel._sub = sub
    sub:SetText("Art from the WoW Forever client, drawn on " .. ClientName())

    -- Title bar: the small 2x buttons at 32 px
    local fullH = H
    local close = SmallButton(panel, "exit", 32)
    close:SetScript("OnClick", function() panel:Hide() end)
    local fold = SmallButton(panel, "condense", 32)
    local mini = SmallButton(panel, "minicondense", 32)
    panel._tb = { close, fold, mini }   -- placed per frame style (LayoutTitle)
    mini:SetScript("OnClick", function() print("|cff66bb6aBNB|r small-minicondense clicked (no action in the test)") end)

    -- Everything under the title, hidden when folded
    local body = CreateFrame("Frame", nil, panel)
    body:SetAllPoints()
    fold:SetScript("OnClick", function(self)
        local folded = body:IsShown()
        if folded then body:Hide(); panel:SetHeight(70); self:SetArt("expand")
        else body:Show(); panel:SetHeight(fullH); self:SetArt("condense") end
    end)

    local function BHeader(text, y)
        local fs = body:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        fs:SetPoint("TOPLEFT", PAD, y)
        fs:SetText(text)
        return fs
    end

    -- Icon buttons
    BHeader("Icon buttons (128 px art at 36 px)", -64)
    local icons = {}
    local x = PAD
    for _, n in ipairs({ "arrowdown", "arrowupglow", "delete", "exit", "minus", "plus", "refresh", "visibilityon" }) do
        local b = IconButton(body, n, 36)
        b._name = n
        b:SetPoint("TOPLEFT", x, -84)
        x = x + 42
        icons[#icons + 1] = b
        if n == "visibilityon" then
            b:SetScript("OnClick", function(self)
                self._name = (self._name == "visibilityon") and "visibilityoff" or "visibilityon"
                self:SetArt(self._name)
            end)
        end
    end
    local off = CreateFrame("CheckButton", nil, body, "UICheckButtonTemplate")
    off:SetSize(24, 24)
    off:SetPoint("TOPLEFT", x + 10, -90)
    local offLbl = body:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    offLbl:SetPoint("LEFT", off, "RIGHT", 2, 0)
    offLbl:SetText("Disabled")

    -- Text buttons
    BHeader("Text buttons (three parts, 128 px art at 32 px)", -134)
    local accept = TextButton(body, "Accept", 150, 32)
    accept:SetPoint("TOPLEFT", PAD, -154)
    local cancel = TextButton(body, "Cancel", 150, 32)
    cancel:SetPoint("LEFT", accept, "RIGHT", 10, 0)
    local wide = TextButton(body, "A wider button with longer text", 250, 32)
    wide:SetPoint("LEFT", cancel, "RIGHT", 10, 0)
    local short = TextButton(body, "Small", 110, 24)
    short:SetPoint("TOPLEFT", PAD, -194)
    local stuck = TextButton(body, "Always disabled", 170, 24)
    stuck:SetPoint("LEFT", short, "RIGHT", 10, 0)
    stuck:SetOff(true)
    local texts = { accept, cancel, wide, short }

    off:SetScript("OnClick", function(self)
        local on = self:GetChecked() and true or false
        for _, b in ipairs(icons) do b:SetEnabled(not on) end
        for _, b in ipairs(texts) do b:SetOff(on) end
    end)

    -- Scrollbars
    BHeader("Minimal scrollbar", -232)
    local hdr2 = body:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    hdr2:SetPoint("TOPLEFT", PAD + 285, -232)
    hdr2:SetText("Minimal scrollbar, nothing to scroll")
    local s1 = MinimalScroll(body, 270, 190)
    s1:SetPoint("TOPLEFT", PAD, -252)
    local s2 = MinimalScroll(body, 270, 190, "A short text that fits: no thumb, and every arrow inactive.")
    s2:SetPoint("TOPLEFT", PAD + 285, -252)
    panel._scrolls = { s1, s2 }

    -- Controls, in the Forever buttons too
    local styleBtn, bgBtn
    styleBtn = TextButton(body, "Frame: " .. STYLES[style], 160, 28)
    styleBtn:SetPoint("BOTTOMLEFT", PAD, 24)
    styleBtn:SetScript("OnClick", function()
        style = NEXT[style]
        styleBtn._label:SetText("Frame: " .. STYLES[style])
        LayoutFrame()
    end)
    bgBtn = TextButton(body, "Background: " .. BGS[bgIndex].name, 160, 28)
    bgBtn:SetPoint("LEFT", styleBtn, "RIGHT", 10, 0)
    bgBtn:SetScript("OnClick", function()
        bgIndex = bgIndex % #BGS + 1
        bgBtn._label:SetText("Background: " .. BGS[bgIndex].name)
        PaintBg()
    end)
    -- Its own row above the buttons: at 210 px beside them the label row
    -- ("Frame scale 0.40 (Default: 0.40)" + Reset) needs ~280 and ran under
    -- Reset (Dukul's screenshot, 2026-11-01)
    local slider = ForeverSlider(body, 300, {
        label = "Frame scale", min = 0.3, max = 0.8, step = 0.05,
        value = scale, default = SCALE_DEFAULT,
        onChange = function(v) scale = v; LayoutFrame() end,
    })
    slider:SetPoint("BOTTOMRIGHT", -PAD, 60)

    panel:SetScript("OnSizeChanged", function() LayoutFrame(); PaintBg() end)
    LayoutFrame()
    PaintBg()
end

SLASH_BNBFOREVER1 = "/bnbforever"
SlashCmdList.BNBFOREVER = function()
    if not BigNoteBox then return end
    if not panel then Build() end
    panel:SetShown(not panel:IsShown())
    if panel:IsShown() then
        panel:Raise()
        -- Scroll heights once the text is laid out
        C_Timer.After(0, function()
            for _, s in ipairs(panel._scrolls or {}) do pcall(s._update) end
        end)
    end
end

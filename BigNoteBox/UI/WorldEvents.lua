-- BigNoteBox UI/WorldEvents.lua
-- World event decorations (ALL-584): art laid over our windows during one of
-- Blizzard's world events, starting with the Feast of Winter Veil (snow).
-- The art never takes the mouse and is never tinted.
--
-- Setting (Settings > Appearance > World events): BigNoteBoxDB.worldEvents
--   "auto" (default) = the event whose dates are on now
--   "off"            = never
--   <event key>      = that event all year; no other event replaces it
-- Developer tools > Holiday: BigNoteBoxDB.debugHoliday (nil = follow the
-- setting, "none", or an event key) overrides both, for testing.
--
-- Where the art goes:
--   - every named MEDIUM tool window (BNB.CreateToolWindow): small art up to
--     SMALL_MAX_W wide (the Reference Box size), the large art on wider ones;
--     a fixed spot between the left edge and the close X and a fixed mirror,
--     both made from the window's name, so every player sees the same
--   - main window: the bottom piece behind the editor's action buttons, and
--     the large art along the top while the character tabs are not on top
--   - the Reference Box model tab: the tab piece
--   - the Reference Box model view and the Focus mode backdrop: snow falling
--     in three depth layers (far = small, faint, slow), ALL-585
-- Skin mode: not on OLED / OLED Flat; darker (grey, never coloured) while the
-- brightness slider is in its bottom quarter.
--
-- Public API:
--   BNB.WORLD_EVENTS               ordered event list (key, name, dates, art)
--   BNB.ActiveWorldEvent()         the event shown now, or nil
--   BNB.WorldEventArt(host, piece, place, cond) -> texture
--                                  place(tex, host, mirrored) anchors it;
--                                  cond() false = hidden
--   BNB.DecorateToolWindow(f, name)
--   BNB.RefreshWorldEvents()       re-applies every piece

local BNB = BigNoteBox
if not BNB then return end

local ART = "Interface\\AddOns\\BigNoteBox\\Assets\\Holidays\\"

-- from / to = { month, day }, both days included; a range may wrap the new
-- year. Dates are the server's calendar date. Each event's art: small = side
-- windows, large = wide windows and the main window top, bottom = main window
-- bottom, tab = the Reference Box tab, flake = the snow falling behind the
-- Reference Box model (ALL-585; an event without it has no falling art).
BNB.WORLD_EVENTS = {
    { key = "winterveil", name = "WE_WINTERVEIL", from = { 12, 16 }, to = { 1, 2 },
      art = { small  = ART .. "WinterVeil\\snow-small",
              large  = ART .. "WinterVeil\\snow-large",
              bottom = ART .. "WinterVeil\\snow-bottom",
              tab    = ART .. "WinterVeil\\snow-tab",
              flake  = ART .. "WinterVeil\\snow-flake" } },
}
local BY_KEY = {}
for _, ev in ipairs(BNB.WORLD_EVENTS) do BY_KEY[ev.key] = ev end

-- Piece sizes (the art's own pixel size) and how far above the edge it sits:
-- yOff = the art's top edge above the window's top edge (positive = up)
local PIECE = {
    small  = { w = 128, h = 64, yOff = 45 },
    large  = { w = 256, h = 32, yOff = 16 },
    bottom = { w = 256, h = 64 },
    tab    = { w = 64,  h = 64 },
}
local SMALL_MAX_W = 380   -- windows up to this wide take the small art
local CLOSE_ROOM  = 34    -- kept clear at the right: the close X

local NO_ART_PRESETS = { oled = true, oledflat = true }

local function DateOn(ev)
    local t = C_DateAndTime and C_DateAndTime.GetCurrentCalendarTime and C_DateAndTime.GetCurrentCalendarTime()
    local m, d
    if t and t.month then m, d = t.month, t.monthDay
    else local n = BNB.Date("*t"); m, d = n.month, n.day end
    local now  = m * 100 + d
    local from = ev.from[1] * 100 + ev.from[2]
    local to   = ev.to[1] * 100 + ev.to[2]
    if from <= to then return now >= from and now <= to end
    return now >= from or now <= to   -- wraps the new year
end

function BNB.ActiveWorldEvent()
    local db = BigNoteBoxDB
    if not db then return nil end
    local dev = db.debugHoliday
    if dev == "none" then return nil end
    if dev and BY_KEY[dev] then return BY_KEY[dev] end
    local mode = db.worldEvents or BNB.DEFAULTS.worldEvents
    if mode == "off" then return nil end
    if BY_KEY[mode] then return BY_KEY[mode] end
    for _, ev in ipairs(BNB.WORLD_EVENTS) do
        if DateOn(ev) then return ev end
    end
    return nil
end

-- 1 = as drawn; skin mode darkens toward 0.7 over the bottom quarter of the
-- brightness slider (0.5 .. 3.0)
local function Shade()
    local db = BigNoteBoxDB
    if not (db and db.skinMode) or not BNB.GetSkinBrightness then return 1 end
    local b = BNB.GetSkinBrightness()
    local lo, top = 0.5, 0.5 + (3.0 - 0.5) / 4
    if b >= top then return 1 end
    return 0.7 + 0.3 * math.max(0, b - lo) / (top - lo)
end

local function SkinAllows()
    local db = BigNoteBoxDB
    if not (db and db.skinMode) then return true end
    local key = BNB.GetSkinPresetKey and BNB.GetSkinPresetKey()
    return not NO_ART_PRESETS[key]
end

-- A fixed number 0..1 and a mirror flag from a name (the same for everyone)
local function Seed(name)
    local h = 7
    for i = 1, #name do h = (h * 31 + name:byte(i)) % 2147483647 end
    return (h % 1000) / 1000, math.floor(h / 1000) % 2 == 1
end

local _pieces = {}   -- every texture made here, re-applied by RefreshWorldEvents

local function Apply(tex)
    local ev = SkinAllows() and BNB.ActiveWorldEvent()
    local piece = type(tex._piece) == "function" and tex._piece() or tex._piece
    local path = ev and piece and ev.art[piece]
    if not path or (tex._cond and not tex._cond()) then
        tex:Hide(); return
    end
    tex:SetTexture(path)
    local p = PIECE[piece]
    tex:SetSize(p.w * (tex._scale or 1), p.h * (tex._scale or 1))
    if tex._mirror then tex:SetTexCoord(1, 0, 0, 1) else tex:SetTexCoord(0, 1, 0, 1) end
    local s = Shade()
    tex:SetVertexColor(s, s, s, 1)
    tex:ClearAllPoints()
    tex._place(tex, tex._host, p)
    tex:Show()
end

-- host: the frame the texture lives on (its layer frame). piece: a piece key
-- or a function returning one. place(tex, host, pieceInfo) anchors it.
-- opts: cond, mirror, scale, layer, sub
function BNB.WorldEventArt(host, piece, place, opts)
    opts = opts or {}
    local tex = host:CreateTexture(nil, opts.layer or "OVERLAY", nil, opts.sub or 7)
    tex._host, tex._piece, tex._place = host, piece, place
    tex._cond, tex._mirror, tex._scale = opts.cond, opts.mirror, opts.scale
    tex:Hide()
    _pieces[#_pieces + 1] = tex
    host:HookScript("OnShow", function() Apply(tex) end)
    host:HookScript("OnSizeChanged", function() Apply(tex) end)
    Apply(tex)
    return tex
end

-- Tool windows (called by BNB.CreateToolWindow for named MEDIUM windows)
function BNB.DecorateToolWindow(f, name)
    if not (f and name) then return end
    local frac, mirror = Seed(name)
    local layer = CreateFrame("Frame", nil, f)
    layer:SetAllPoints(f)
    layer:SetFrameLevel(f:GetFrameLevel() + 10)
    layer:EnableMouse(false)
    local function Piece()
        return (f:GetWidth() or 0) <= SMALL_MAX_W and "small" or "large"
    end
    BNB.WorldEventArt(layer, Piece, function(tex, host, p)
        local room = math.max(0, (f:GetWidth() or 0) - CLOSE_ROOM - p.w)
        tex:SetPoint("TOPLEFT", host, "TOPLEFT", math.floor(room * frac), p.yOff)
    end, { mirror = mirror })
end

-- Main window: the bottom piece on the editor's action bar (behind its
-- buttons) and the large piece along the top while the tabs are not on top
local MAIN_BOTTOM_X, MAIN_BOTTOM_Y = -14, 0   -- art centre on the bottom edge (+ Y)
local MAIN_TOP_RIGHT_ROOM = 130                 -- the title bar's icons and X
local function TabsOnTop()
    local db = BigNoteBoxDB
    return db and db.sidebarSide == "top" and BNB.Sidebar and BNB.Sidebar.IsEnabled
        and BNB.Sidebar.IsEnabled() or false
end
local function SidebarLeftW()
    local db = BigNoteBoxDB
    local on = BNB.Sidebar and BNB.Sidebar.IsEnabled and BNB.Sidebar.IsEnabled()
    return (on and db and db.sidebarSide == "left") and 64 or 0
end

function BNB.DecorateMainWindow(f, actionBar)
    if not f or f._weDone then return end
    f._weDone = true
    -- The top piece follows the tabs (on top or not)
    if BNB.Sidebar and BNB.Sidebar.Refresh then
        hooksecurefunc(BNB.Sidebar, "Refresh", BNB.RefreshWorldEvents)
    end
    if actionBar then
        local low = CreateFrame("Frame", nil, actionBar)
        low:SetAllPoints(f)
        low:SetFrameLevel(actionBar:GetFrameLevel())   -- its buttons sit one higher
        low:EnableMouse(false)
        -- Right end on the action bar (left of a right-side tab strip),
        -- height on the window's bottom edge
        BNB.WorldEventArt(low, "bottom", function(tex, _, p)
            tex:SetPoint("RIGHT",  actionBar, "RIGHT",  MAIN_BOTTOM_X, 0)
            tex:SetPoint("BOTTOM", f,         "BOTTOM", 0, MAIN_BOTTOM_Y - p.h / 2)
        end, { layer = "BACKGROUND", sub = 0 })
    end
    local frac, mirror = Seed("BigNoteBoxFrame")
    local top = CreateFrame("Frame", nil, f)
    top:SetAllPoints(f)
    top:SetFrameLevel(f:GetFrameLevel() + 10)
    top:EnableMouse(false)
    BNB.WorldEventArt(top, "large", function(tex, host, p)
        local left = SidebarLeftW()
        local room = math.max(0, (f:GetWidth() or 0) - left - MAIN_TOP_RIGHT_ROOM - p.w)
        tex:SetPoint("TOPLEFT", host, "TOPLEFT", left + math.floor(room * frac), p.yOff)
    end, { mirror = mirror, cond = function() return not TabsOnTop() end })
end

-- Reference Box: the tab piece on the model tab (the upper one), mirrored on
-- the right side so it leans the same way against the box
local TAB_SCALE = 0.75   -- 64 px art on the 48 px tab
function BNB.DecorateRefBoxTab(btn, isRight)
    if not btn then return end
    if not btn._weTex then
        btn._weTex = BNB.WorldEventArt(btn, "tab", function(tex, host)
            tex:SetPoint("BOTTOM", host, "TOP", 0, -tex:GetHeight() * 0.45)
        end, { scale = TAB_SCALE })
    end
    btn._weTex._mirror = isRight and true or nil
    Apply(btn._weTex)
end

-- ── Falling snow behind the Reference Box model and the Focus mode backdrop
-- (ALL-585) ──────────────────────────────────────────────────────────────────
-- Textures on a host frame: on the model frame they draw behind the 3D model
-- (as its parchment and crest do), on the Focus overlay over its dark fill.
-- Each flake falls from the top edge to the bottom edge, fading in and out,
-- so nothing needs clipping; the first fall starts part way down so the area
-- is full at once. Only AnimationGroups, no OnUpdate, and only while the host
-- is shown during an event. Spots and speeds come from a fixed seed (the same
-- for everyone); fall times are for SNOW_REF_H and scale with the height, so
-- a taller area keeps the same speed.
local SNOW_LAYERS = {   -- far to near
    { n = 24, s1 = 3, s2 = 4,  a = 0.30, t1 = 14, t2 = 18, drift = 10, sub = 2 },
    { n = 14, s1 = 5, s2 = 7,  a = 0.50, t1 = 9,  t2 = 12, drift = 18, sub = 3 },
    { n = 8,  s1 = 8, s2 = 11, a = 0.75, t1 = 6,  t2 = 8,  drift = 26, sub = 4 },
}
local SNOW_EDGE  = 6      -- kept clear at the top and bottom edges
local SNOW_REF_H = 360    -- the height the fall times above are for
local FADE       = 0.12   -- share of a fall spent fading in, and fading out

local function Rand(r)   -- Park-Miller, 0..1, exact in doubles
    r.v = (r.v * 16807) % 2147483647
    return r.v / 2147483647
end

local function MakeFlake(host, L, r, sizeMul)
    local fl = { a = L.a }
    fl.tex = host:CreateTexture(nil, "BACKGROUND", nil, L.sub)
    local sz = (L.s1 + (L.s2 - L.s1) * Rand(r)) * sizeMul
    fl.tex:SetSize(sz, sz)
    fl.tex:Hide()
    fl.xf, fl.phase = Rand(r), Rand(r)
    fl.dur   = L.t1 + (L.t2 - L.t1) * Rand(r)
    fl.drift = (Rand(r) * 2 - 1) * L.drift * sizeMul
    -- the endless fall, top to bottom
    fl.loop = fl.tex:CreateAnimationGroup()
    fl.loop:SetLooping("REPEAT")
    fl.loopMove = fl.loop:CreateAnimation("Translation")
    fl.loopMove:SetOrder(1)
    fl.fin = fl.loop:CreateAnimation("Alpha")
    fl.fin:SetFromAlpha(0); fl.fin:SetToAlpha(fl.a); fl.fin:SetOrder(1)
    fl.fout = fl.loop:CreateAnimation("Alpha")
    fl.fout:SetFromAlpha(fl.a); fl.fout:SetToAlpha(0); fl.fout:SetOrder(1)
    -- the first fall, from part way down
    fl.intro = fl.tex:CreateAnimationGroup()
    fl.introMove = fl.intro:CreateAnimation("Translation")
    fl.introMove:SetOrder(1)
    fl.introFade = fl.intro:CreateAnimation("Alpha")
    fl.introFade:SetFromAlpha(fl.a); fl.introFade:SetToAlpha(0); fl.introFade:SetOrder(1)
    fl.intro:SetScript("OnFinished", function()
        fl.tex:ClearAllPoints()
        fl.tex:SetPoint("CENTER", host, "TOPLEFT", fl.x, -SNOW_EDGE)
        fl.loop:Play()
    end)
    return fl
end

local _snows = {}

local function StopSnow(sn)
    for _, fl in ipairs(sn.flakes) do
        fl.intro:Stop(); fl.loop:Stop(); fl.tex:Hide()
    end
end

local function RunSnow(sn)
    StopSnow(sn)
    local host = sn.host
    local ev = host:IsVisible() and SkinAllows() and BNB.ActiveWorldEvent()
    local path = ev and ev.art.flake
    local w, h = host:GetWidth() or 0, host:GetHeight() or 0
    if not path or w < 60 or h < 60 then return end
    local fallH = h - SNOW_EDGE * 2
    local speed = math.max(0.5, fallH / SNOW_REF_H)
    local shade = Shade()
    for _, fl in ipairs(sn.flakes) do
        local lo = SNOW_EDGE + math.abs(fl.drift)
        local hi = w - SNOW_EDGE - math.abs(fl.drift)
        fl.x = lo + (hi - lo) * fl.xf
        local d = fl.dur * speed
        fl.tex:SetTexture(path)
        fl.tex:SetVertexColor(shade, shade, shade, 1)
        fl.loopMove:SetOffset(fl.drift, -fallH)
        fl.loopMove:SetDuration(d)
        fl.fin:SetDuration(d * FADE)
        fl.fout:SetDuration(d * FADE); fl.fout:SetStartDelay(d * (1 - FADE))
        local rest = 1 - fl.phase
        fl.introMove:SetOffset(fl.drift * rest, -fallH * rest)
        fl.introMove:SetDuration(math.max(0.1, d * rest))
        fl.introFade:SetDuration(math.max(0.05, d * math.min(rest, FADE)))
        fl.introFade:SetStartDelay(math.max(0, d * (rest - FADE)))
        fl.tex:ClearAllPoints()
        fl.tex:SetPoint("CENTER", host, "TOPLEFT", fl.x, -SNOW_EDGE - fallH * fl.phase)
        fl.tex:SetAlpha(fl.a)   -- the fades run from it; held between them either way
        fl.tex:Show()
        fl.intro:Play()
    end
end

-- host: the Reference Box's DressUpModel (UI/ReferenceBox.lua
-- BuildModelViewer) or the Focus mode overlay (UI/FocusEditor.lua).
-- mult = how many times the base flake count (a bigger area), sizeMul =
-- flake size and drift (nil = 1 each).
function BNB.AddFallingSnow(host, mult, sizeMul)
    if not host or host._weSnow then return end
    local sn = { host = host, flakes = {} }
    host._weSnow = sn
    local r = { v = 584 }
    for _, L in ipairs(SNOW_LAYERS) do
        for _ = 1, math.floor(L.n * (mult or 1) + 0.5) do
            sn.flakes[#sn.flakes + 1] = MakeFlake(host, L, r, sizeMul or 1)
        end
    end
    _snows[#_snows + 1] = sn
    sn.key = "WorldEvents.snow" .. #_snows
    host:HookScript("OnShow", function() RunSnow(sn) end)
    host:HookScript("OnHide", function() StopSnow(sn) end)
    host:HookScript("OnSizeChanged", function()
        BNB.Debounce(sn.key, 0.15, function() RunSnow(sn) end)
    end)
end

function BNB.RefreshWorldEvents()
    for _, tex in ipairs(_pieces) do Apply(tex) end
    for _, sn in ipairs(_snows) do RunSnow(sn) end
end

BNB.RegisterMessage("WorldEvents", "SkinChanged", BNB.RefreshWorldEvents)

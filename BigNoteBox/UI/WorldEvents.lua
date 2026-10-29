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
--     the large art along the top while the character tabs are not on top;
--     a garland along the outside of its bottom edge, behind the tabs there
--     (ALL-607);
--     on the welcome page (no note open) the bottom piece and a small piece
--     on the Create new note button
--   - the Reference Box model tab: the tab piece
--   - the Reference Box model view and the Focus mode backdrop: snow falling
--     in three depth layers (far = small, faint, slow), ALL-585
-- Skin mode: not on OLED / OLED Flat; darker (grey, never coloured) while the
-- brightness slider is in its bottom quarter.
--
-- Public API:
--   BNB.WORLD_EVENTS               ordered event list (key, name, dates, art)
--   BNB.ActiveWorldEvent()         the event shown now, or nil
--   BNB.WorldEventArt(host, piece, place, opts) -> texture
--                                  place(tex, host, pieceInfo, pos) anchors it
--   BNB.DecorateToolWindow(f, name) / DecorateMainWindow / DecorateWelcome /
--   DecorateRefBoxTab              put the pieces on our windows
--   BNB.RefreshWorldEvents()       re-applies every piece
--   BNB.SetPlacingSnow(on) / IsPlacingSnow() / ResetPlacedSnow()
--                                  Developer tools > Place snow (see PLACE)

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
              holly  = ART .. "WinterVeil\\snow-holly",
              flake  = ART .. "WinterVeil\\snow-flake" } },
}
local BY_KEY = {}
for _, ev in ipairs(BNB.WORLD_EVENTS) do BY_KEY[ev.key] = ev end

-- Off for players until Dukul has placed the art on every client (Forever
-- and Classic draw the windows differently): no Appearance setting and no
-- event by date; Developer tools > Holiday still shows it (Dukul, 2026-10-26:
-- show it after Forever launches and has been tested there)
BNB.WORLD_EVENTS_LIVE = false

-- Piece sizes (the art's own pixel size) and how far above the edge it sits:
-- yOff = the art's top edge above the window's top edge (positive = up)
local PIECE = {
    small  = { w = 128, h = 64, yOff = 45 },
    large  = { w = 256, h = 32, yOff = 16 },
    bottom = { w = 256, h = 64 },
    tab    = { w = 64,  h = 64 },
    holly  = { w = 128, h = 32 },   -- the garland under the main window, repeated
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
    if not BNB.WORLD_EVENTS_LIVE then return nil end
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

-- A window's snow spot: the left edge, the middle or the right edge (0, 0.5,
-- 1) and a mirror flag, from its name. Spread values left the windows used
-- most all on the left half (Dukul, 2026-10-26); with these the Reference Box,
-- Focus and preview sit left, Note Settings, Focus preview and New Note right
local SLOTS = { 0, 0.5, 1 }
local function WindowSeed(name)
    local h = 7
    for i = 1, #name do h = (h * 31 + name:byte(i)) % 2147483647 end
    for _ = 1, 3 do h = (h * 48271) % 2147483647 end   -- exact in doubles
    return SLOTS[h % 3 + 1], math.floor(h / 3) % 2 == 1
end

local _pieces = {}   -- every texture made here, re-applied by RefreshWorldEvents

-- ── Placement ────────────────────────────────────────────────────────────────
-- Every piece has an id and a spot: x / y offsets from its anchor, s = size
-- (1 = the art's own size), m = mirrored. A spot comes from, in order:
-- Developer tools > Place snow (BigNoteBoxDB.debugSnowSpots, dev testing
-- only), PLACE below (spots Dukul placed), the piece's default. Both are kept
-- per client and look ("retail-normal", "retail-skin", ...): the windows are
-- drawn differently on each; a client with no spots of its own uses Retail's.
-- Tool windows share y and s per art size ("size:small" / "size:large", one
-- drag sets every window of that size); their x lies between xl (from the
-- left edge) and the window's width minus xr, picked from the window's name,
-- as is the mirror; Place snow can pin x / m for one window ("win:<name>").
local PLACE = {
    ["retail-normal"] = {   -- Dukul, 2026-10-26
        ["size:small"]     = { y = 28,  s = 0.9,  xl = 2,  xr = 125 },
        ["size:large"]     = { y = 10,  s = 1,    xl = 0,  xr = 267 },
        ["refbox:tab"]     = { x = 4,   y = -23,  s = 0.85 },
        ["main:corner"]    = { x = 0,   y = -87,  s = 0.55 },
        ["main:explorer"]  = { x = -1,  y = -86,  s = 0.55 },
        ["welcome:newbtn"] = { x = -50, y = -30,  s = 0.8 },
    },
    ["retail-skin"] = {     -- Dukul, 2026-10-26
        ["size:small"]     = { y = 32,  s = 0.9,  xl = -3, xr = 124 },
        ["size:large"]     = { y = 10,  s = 1,    xl = -5, xr = 266 },
        ["refbox:tab"]     = { x = 4,   y = -23,  s = 0.85 },
        ["main:corner"]    = { x = -1,  y = -83,  s = 0.5 },
        ["main:explorer"]  = { x = -1,  y = -83,  s = 0.5 },
        ["welcome:newbtn"] = { x = -50, y = -30,  s = 0.8 },
    },
    -- Every other Classic spot is Retail's (Dukul, 2026-10-26)
    ["classic-normal"] = {  -- Dukul, 2026-10-26
        ["main:corner"]    = { x = 1,   y = -82,  s = 0.55 },
        ["main:explorer"]  = { x = 1,   y = -82,  s = 0.55 },
    },
}

local function LookKey()
    local client = (BNB.IsForever and "forever") or (BNB.IsClassic and "classic") or "retail"
    local look = (BigNoteBoxDB and BigNoteBoxDB.skinMode) and "skin" or "normal"
    return client .. "-" .. look, "retail-" .. look
end

-- PLACE's entry for an id (this client's, else Retail's), or nil
local function Placed(id)
    local key, retail = LookKey()
    local own = PLACE[key] and PLACE[key][id]
    if own then return own end
    return PLACE[retail] and PLACE[retail][id]
end

-- The Place snow spots for this client and look (made on first write)
local function DevSpots(make)
    local db = BigNoteBoxDB
    if not db then return nil end
    local key = LookKey()
    if make then
        db.debugSnowSpots = db.debugSnowSpots or {}
        db.debugSnowSpots[key] = db.debugSnowSpots[key] or {}
    end
    return db.debugSnowSpots and db.debugSnowSpots[key]
end

local _placing = false   -- Developer tools > Place snow (session only)

local function IdOf(tex, field)
    return tex._idOf and tex._idOf(field) or tex._id
end

local FIELDS = { "x", "y", "s", "m" }
local function PosOf(tex, p)
    local dev = DevSpots(false)
    local def = tex._def(p)
    local pos = {}
    for _, fld in ipairs(FIELDS) do
        local id = IdOf(tex, fld)
        local placed = Placed(id)
        local v
        if dev and dev[id] and dev[id][fld] ~= nil then v = dev[id][fld]
        elseif placed and placed[fld] ~= nil then v = placed[fld] end
        if v == nil then v = def[fld] end
        pos[fld] = v
    end
    return pos
end

local Handle   -- forward: the drag handle, made on first use while placing

local function Apply(tex)
    local ev = SkinAllows() and BNB.ActiveWorldEvent()
    local piece = type(tex._piece) == "function" and tex._piece() or tex._piece
    local path = ev and piece and ev.art[piece]
    if not path or (tex._cond and not tex._cond()) then
        tex:Hide()
        if tex._handle then tex._handle:Hide() end
        return
    end
    local p = PIECE[piece]
    local pos = PosOf(tex, p)
    tex._pos = pos
    tex:SetTexture(path)
    tex:SetSize(p.w * pos.s, p.h * pos.s)
    local mir = pos.m and true or false
    if tex._flip and tex._flip() then mir = not mir end
    if mir then tex:SetTexCoord(1, 0, 0, 1) else tex:SetTexCoord(0, 1, 0, 1) end
    local s = Shade()
    tex:SetVertexColor(s, s, s, 1)
    tex:ClearAllPoints()
    tex._place(tex, tex._host, p, pos)
    tex:Show()
    if _placing then Handle(tex):Show()
    elseif tex._handle then tex._handle:Hide() end
end

-- host: the frame the texture lives on (its layer frame). piece: a piece key
-- or a function returning one. place(tex, host, pieceInfo, pos) anchors it.
-- opts: id (string), idOf(field) (an id per field, else id), def(pieceInfo)
-- -> { x, y, s, m } (the default spot), flip() (true = mirror the other way),
-- xSign (-1 = a drag to the right lowers x), cond, layer, sub
function BNB.WorldEventArt(host, piece, place, opts)
    opts = opts or {}
    local tex = host:CreateTexture(nil, opts.layer or "OVERLAY", nil, opts.sub or 7)
    tex._host, tex._piece, tex._place = host, piece, place
    tex._id, tex._idOf, tex._flip = opts.id, opts.idOf, opts.flip
    tex._def = opts.def or function() return { x = 0, y = 0, s = 1, m = false } end
    tex._xSign = opts.xSign or 1
    tex._cond = opts.cond
    tex:Hide()
    _pieces[#_pieces + 1] = tex
    host:HookScript("OnShow", function() Apply(tex) end)
    host:HookScript("OnSizeChanged", function() Apply(tex) end)
    Apply(tex)
    return tex
end

-- ── Place snow (Developer tools) ────────────────────────────────────────────
-- While on, every piece on screen gets a blue box: drag = move, right-click =
-- mirror, wheel = size. Each change is saved in BigNoteBoxDB.debugSnowSpots and
-- printed to chat, for copying into PLACE above (kept per client and look).
local function SetVal(tex, field, v)
    local spots = DevSpots(true)
    if not spots then return end
    local id = IdOf(tex, field)
    spots[id] = spots[id] or {}
    spots[id][field] = v
end

local function Round(v) return math.floor(v + 0.5) end

local function Report(tex)
    local pos = tex._pos
    if not pos then return end
    local ids = IdOf(tex, "x")
    if IdOf(tex, "y") ~= ids then ids = ids .. " + " .. IdOf(tex, "y") end
    local mir = ""
    if pos.m then mir = BNB.L["CFG_DEV_SNOW_MIRRORED"] end
    BNB:Print(string.format(BNB.L["CFG_DEV_SNOW_POS_FMT"], ids, pos.x, pos.y, pos.s, mir))
end

function Handle(tex)
    local h = tex._handle
    if h then return h end
    h = CreateFrame("Button", nil, tex._host)
    h:SetAllPoints(tex)
    local fill = h:CreateTexture(nil, "BACKGROUND")
    fill:SetAllPoints()
    fill:SetColorTexture(0.2, 0.6, 1, 0.15)
    local function Edge(p1, p2, horiz)
        local e = h:CreateTexture(nil, "BORDER")
        e:SetColorTexture(0.3, 0.7, 1, 0.9)
        e:SetPoint(p1); e:SetPoint(p2)
        if horiz then e:SetHeight(1) else e:SetWidth(1) end
    end
    Edge("TOPLEFT", "TOPRIGHT", true);    Edge("BOTTOMLEFT", "BOTTOMRIGHT", true)
    Edge("TOPLEFT", "BOTTOMLEFT", false); Edge("TOPRIGHT", "BOTTOMRIGHT", false)
    h:EnableMouseWheel(true)
    h:SetScript("OnMouseDown", function(self, btn)
        if btn ~= "LeftButton" or not tex._pos then return end
        local cx, cy = GetCursorPosition()
        local sc = self:GetEffectiveScale()
        local x0, y0 = tex._pos.x, tex._pos.y
        self:SetScript("OnUpdate", function()
            local nx, ny = GetCursorPosition()
            SetVal(tex, "x", x0 + Round((nx - cx) / sc * tex._xSign))
            SetVal(tex, "y", y0 + Round((ny - cy) / sc))
            Apply(tex)
        end)
    end)
    h:SetScript("OnMouseUp", function(self, btn)
        if btn == "LeftButton" then
            if not self:GetScript("OnUpdate") then return end
            self:SetScript("OnUpdate", nil)
        elseif btn == "RightButton" and tex._pos then
            SetVal(tex, "m", not tex._pos.m)
        else return end
        BNB.RefreshWorldEvents()   -- a shared y moves the other windows too
        Report(tex)
    end)
    h:SetScript("OnMouseWheel", function(_, delta)
        if not tex._pos then return end
        local s = math.floor((tex._pos.s + delta * 0.05) * 100 + 0.5) / 100
        SetVal(tex, "s", math.max(0.2, math.min(3, s)))
        Apply(tex)
        BNB.Debounce("WorldEvents.report", 0.4, function() Report(tex) end)
    end)
    h:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(IdOf(tex, "x"), 1, 1, 1)
        if IdOf(tex, "y") ~= IdOf(tex, "x") then GameTooltip:AddLine(IdOf(tex, "y"), 1, 1, 1) end
        GameTooltip:AddLine(BNB.L["CFG_DEV_SNOW_HANDLE_TIP"], 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    h:SetScript("OnLeave", function() GameTooltip:Hide() end)
    h:Hide()
    tex._handle = h
    return h
end

function BNB.IsPlacingSnow() return _placing end
function BNB.SetPlacingSnow(on)
    _placing = on and true or false
    for _, tex in ipairs(_pieces) do
        if not _placing and tex._handle then
            tex._handle:SetScript("OnUpdate", nil)
            tex._handle:Hide()
        end
    end
    BNB.RefreshWorldEvents()
end
function BNB.ResetPlacedSnow()
    if BigNoteBoxDB then
        BigNoteBoxDB.debugSnowSpots = nil
        BigNoteBoxDB.debugSnowPos = nil   -- the first build's key, one look for all
    end
    BNB.RefreshWorldEvents()
end

-- Over the window's border: the layer hangs off the window's close button,
-- which ButtonFrameTemplate keeps over its border (the main window's title
-- bar icons do the same). Never a SetFrameLevel from the window's children:
-- the window stack (UI/WindowStack.lua) measures how deep a window's
-- children reach, and a layer lifted over every frame in the window broke
-- the main window's order on the next click (2026-10-26). No close button
-- (skin mode): 10 levels over the window, as before.
local function ChromeLayer(win)
    local cb = win.CloseButton
    local layer
    if cb then
        layer = CreateFrame("Frame", nil, cb)
    else
        layer = CreateFrame("Frame", nil, win)
        layer:SetFrameLevel(win:GetFrameLevel() + 10)
    end
    layer:SetAllPoints(win)
    layer:EnableMouse(false)
    return layer
end

-- A piece on a chrome layer shown with another frame (cond checks it)
local function Follow(tex, owner)
    owner:HookScript("OnShow", function() Apply(tex) end)
    owner:HookScript("OnHide", function() Apply(tex) end)
end

-- Tool windows (called by BNB.CreateToolWindow for named MEDIUM windows)
-- piece = "small" / "large" to pick the art whatever the width (nil = by width)
function BNB.DecorateToolWindow(f, name, piece)
    if not (f and name) then return end
    local frac, mirror = WindowSeed(name)
    local layer = ChromeLayer(f)
    local function Piece()
        if piece then return piece end
        return (f:GetWidth() or 0) <= SMALL_MAX_W and "small" or "large"
    end
    BNB.WorldEventArt(layer, Piece, function(tex, host, _, pos)
        tex:SetPoint("TOPLEFT", host, "TOPLEFT", pos.x, pos.y)
    end, {
        idOf = function(field)
            if field == "y" or field == "s" then return "size:" .. Piece() end
            return "win:" .. name
        end,
        def = function(p)
            local sz = Placed("size:" .. Piece()) or {}
            local s  = sz.s or 1
            local xl = sz.xl or 0
            local xr = (f:GetWidth() or 0) - (sz.xr or (CLOSE_ROOM + p.w * s))
            if xr < xl then xr = xl end
            return { x = math.floor(xl + (xr - xl) * frac), y = p.yOff, s = s, m = mirror }
        end,
    })
end

-- Main window: in the note list view a piece under the top bar's right-hand
-- icons (x from the editor pane's right edge, y from the window's top edge;
-- the welcome page and an open note alike), in the explorer view the same
-- piece from the window's top right (it stays put when the window is resized),
-- and the large piece along the top while the tabs are not on top
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
local function ExplorerOn()
    return BigNoteBoxDB and BigNoteBoxDB.explorerView == true
end

-- The garland (ALL-607, Dukul, 2026-10-28): holly pieces strung along the
-- outside of the main window's bottom edge, as many as fit, each stretched
-- sideways so the row fills the width; a resize adds or drops pieces. Behind
-- the tabs that hang there (the rich note's Markup / Note tabs): one strata
-- under theirs, which is the window's own, or the one below it in skin mode
-- (NoteEditor.lua BuildRichTabStrip). x = the inset from both sides, y = the
-- row's top edge over the window's bottom edge (positive = up, under the
-- window). The first piece is the placeable one (Place snow); the others copy it.
local GARLAND_BELOW = { LOW = "BACKGROUND", MEDIUM = "LOW", HIGH = "MEDIUM", DIALOG = "HIGH",
    FULLSCREEN = "DIALOG", FULLSCREEN_DIALOG = "FULLSCREEN", TOOLTIP = "FULLSCREEN_DIALOG" }

local function DecorateGarland(f)
    local host = CreateFrame("Frame", nil, f)
    host:SetAllPoints(f)
    host:EnableMouse(false)
    local extra = {}
    local first
    first = BNB.WorldEventArt(host, "holly", function(tex, _, p, pos)
        local tabs = f:GetFrameStrata()
        if BigNoteBoxDB and BigNoteBoxDB.skinMode then tabs = GARLAND_BELOW[tabs] or tabs end
        local strata = GARLAND_BELOW[tabs] or "BACKGROUND"
        if host:GetFrameStrata() ~= strata then host:SetFrameStrata(strata) end
        local w = math.max(0, (f:GetWidth() or 0) - 2 * pos.x)
        local h = p.h * pos.s
        local n = math.max(1, math.floor(w / (p.w * pos.s) + 0.5))
        local pw = w / n
        tex:SetSize(pw, h)
        tex:SetPoint("TOPLEFT", f, "BOTTOMLEFT", pos.x, pos.y)
        local path = tex:GetTexture()
        local cr, cg, cb = tex:GetVertexColor()   -- the shade Apply set
        for i = 2, n do
            local t = extra[i]
            if not t then
                t = host:CreateTexture(nil, "OVERLAY", nil, 7)
                extra[i] = t
            end
            t:SetTexture(path)
            if pos.m then t:SetTexCoord(1, 0, 0, 1) else t:SetTexCoord(0, 1, 0, 1) end
            t:SetVertexColor(cr, cg, cb, 1)
            t:SetSize(pw, h)
            t:ClearAllPoints()
            t:SetPoint("TOPLEFT", extra[i - 1] or tex, "TOPRIGHT")
            t:Show()
        end
        for i = n + 1, #extra do if extra[i] then extra[i]:Hide() end end
    end, { id = "main:garland",
           def = function() return { x = 0, y = 8, s = 1, m = false } end })
    -- Apply hides only the first piece (event off, OLED skin): the rest go with it
    hooksecurefunc(first, "Hide", function()
        for _, t in pairs(extra) do t:Hide() end
    end)
end

function BNB.DecorateMainWindow(f)
    if not f or f._weDone then return end
    f._weDone = true
    -- The top piece follows the tabs (on top or not), the corner and the
    -- explorer pieces the view
    if BNB.Sidebar and BNB.Sidebar.Refresh then
        hooksecurefunc(BNB.Sidebar, "Refresh", BNB.RefreshWorldEvents)
    end
    if BNB.Explorer and BNB.Explorer.SetActive then
        hooksecurefunc(BNB.Explorer, "SetActive", BNB.RefreshWorldEvents)
    end
    local pane = BNB.editorPane
    if pane then
        -- its top right = the window's top edge over the pane's right edge
        local corner = CreateFrame("Frame", nil, f)
        corner:SetPoint("TOPLEFT",     f,    "TOPLEFT")
        corner:SetPoint("BOTTOMRIGHT", pane, "TOPRIGHT")
        local tex = BNB.WorldEventArt(ChromeLayer(f), "bottom", function(tex, _, _, pos)
            tex:SetPoint("BOTTOMRIGHT", corner, "TOPRIGHT", pos.x, pos.y)
        end, { id = "main:corner",
               cond = function() return not ExplorerOn() and pane:IsVisible() end,
               def = function() return { x = -1, y = -116, s = 0.7, m = false } end })
        Follow(tex, pane)
    end
    BNB.WorldEventArt(ChromeLayer(f), "bottom", function(tex, _, _, pos)
        tex:SetPoint("BOTTOMRIGHT", f, "TOPRIGHT", pos.x, pos.y)
    end, { id = "main:explorer", cond = ExplorerOn,
           def = function() return { x = -1, y = -86, s = 0.55, m = false } end })
    DecorateGarland(f)
    local frac, mirror = Seed("BigNoteBoxFrame")
    local top = ChromeLayer(f)
    BNB.WorldEventArt(top, "large", function(tex, host, _, pos)
        tex:SetPoint("TOPLEFT", host, "TOPLEFT", SidebarLeftW() + pos.x, pos.y)
    end, { id = "main:top", cond = function() return not TabsOnTop() end,
           def = function(p)
               local room = math.max(0, (f:GetWidth() or 0) - SidebarLeftW() - MAIN_TOP_RIGHT_ROOM - p.w)
               return { x = math.floor(room * frac), y = p.yOff, s = 1, m = mirror }
           end })
end

-- Main window welcome page (no note open, UI/WelcomePanel.lua): a small piece
-- on the Create new note button (the corner piece above covers the page too)
function BNB.DecorateWelcome(panel, newBtn)
    if not panel or panel._weDone or not newBtn then return end
    panel._weDone = true
    local cap = CreateFrame("Frame", nil, newBtn)
    cap:SetAllPoints(newBtn)
    cap:SetFrameLevel(newBtn:GetFrameLevel() + 5)
    cap:EnableMouse(false)
    BNB.WorldEventArt(cap, "small", function(tex, host, _, pos)
        tex:SetPoint("BOTTOM", host, "TOP", pos.x, pos.y)
    end, { id = "welcome:newbtn",
           def = function() return { x = 0, y = -12, s = 0.6, m = false } end })
end

-- Reference Box: the tab piece on the model tab (the upper one), mirrored on
-- the right side so it leans the same way against the box; x counts toward
-- the box on both sides. The tab strip is drawn under the box (a lower strata
-- or stacked under it), so the piece lives on the box's chrome layer, over
-- its border, anchored to the tab and shown while the tab is
function BNB.DecorateRefBoxTab(btn, isRight, box)
    if not btn then return end
    btn._weRight = isRight and true or nil
    box = box or (btn:GetParent() and btn:GetParent():GetParent())
    if not btn._weTex and box then
        local layer = ChromeLayer(box)
        btn._weTex = BNB.WorldEventArt(layer, "tab", function(tex, _, _, pos)
            local sign = btn._weRight and -1 or 1
            tex:SetPoint("BOTTOM", btn, "TOP", pos.x * sign, pos.y)
        end, { id = "refbox:tab",
               flip = function() return btn._weRight end,
               cond = function() return btn:IsVisible() end,
               def = function(p) return { x = 0, y = -math.floor(p.h * 0.75 * 0.45), s = 0.75, m = false } end })
        Follow(btn._weTex, btn)
    end
    if not btn._weTex then return end
    btn._weTex._xSign = btn._weRight and -1 or 1
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

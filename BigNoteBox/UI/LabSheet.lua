-- BigNoteBox UI/LabSheet.lua
-- The crop sheet shared by the developer labs: a window that shows one game
-- file with boxes drawn on it in file pixels. Lifted from the Icon Lab's
-- sheet (UI/IconLab.lua, ALL-126) for the Background Lab (2026-10-02); the
-- Icon Lab still has its own copy and moves onto this one later.
--
-- On the sheet: left-drag draws the active box, dragging a box edge or
-- corner resizes it, wheel zooms around the pointer, right/middle-drag pans,
-- arrows move the active box 1 px (Shift 10), Ctrl+arrows move its right or
-- bottom edge. A click without a drag picks the atlas region under the
-- pointer. An optional aspect ratio (cfg.Aspect) holds the box to that shape
-- in every one of those tools.
--
-- K.NewSheet(cfg) -> sheet. The lab owns all saved data; the sheet asks for
-- it through cfg:
--   name            global frame name
--   View()          table for the sheet's own saved options (bg, grid, zoom,
--                   showRegions, guides, sw, sh)
--   File()          id, W, H, title, failed (nil W/H while loading; failed =
--                   the file did not load on this client)
--   boxes           { { key, label, col }, ... } in draw order
--   Active()        key of the box the tools act on
--   SetActive(key)  (only needed with more than one box)
--   Box(key)        x, y, w, h, or nil while unset
--   ToolBox(key)    the box the tools start from when unset (x, y, w, h)
--   Bounds(key)     what the box is measured and kept against
--   SetBox(key, x, y, w, h)  store it (the lab rounds and clamps)
--   Changed()       after any box change (the lab's Refresh)
--   Regions()       the current file's atlas regions, or nil
--   RegionRect(reg, W, H)  x, y, w, h, live
--   CurrentRegion() name of the region the entry is, or nil
--   PickRegion(name)
--   Aspect()        w / h ratio to hold the box to, or nil
--   AddTools(f, last, sheet)  optional: add buttons to the bottom bar after last
--   Whole(key)      optional: false lets Resize / Centre leave the box on a
--                   half pixel (the Icon Lab's hole); default whole pixels
-- Dev tools only; nothing here is translated.

local BNB = BigNoteBox
if not BNB then return end
local K = BNB._LabKit

local SHEET_BGS = {      -- behind the sheet, cycled with Bg
    { 0.08, 0.08, 0.10 }, { 0.55, 0.55, 0.58 }, { 0.85, 0.20, 0.75 },
    { 0.08, 0.08, 0.10, atlas = "scoreboard-background-islands-horde" },
    { 0.08, 0.08, 0.10, atlas = "scoreboard-background-islands-alliance" },
    { 0.08, 0.08, 0.10, atlas = "scoreboard-background-warfronts-alliance" },
    { 0.08, 0.08, 0.10, atlas = "scoreboard-background-warfronts-horde" },
}
K.SHEET_BGS = SHEET_BGS
local COL_HOVER = { 0.35, 0.85, 1, 1 }
local COL_REG   = { 1, 0, 1, 1 }            -- bright magenta (Dukul)
local COL_EVEN  = { 0.30, 1, 0.40 }         -- guide gaps that match their pair
local COL_ODD   = { 1, 0.25, 0.25 }
local EDGE_TOL  = 5
local ARROWS = { LEFT = { -1, 0 }, RIGHT = { 1, 0 }, UP = { 0, -1 }, DOWN = { 0, 1 } }

local function R(v) return math.floor(v + 0.5) end

-- Outline frame, 1 px unless given
local function Outline(parent, col, px)
    local o = BNB.CreateBackdropFrame("Frame", nil, parent)
    o:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = px or 1 })
    o:SetBackdropBorderColor(col[1], col[2], col[3], col[4])
    o:EnableMouse(false)
    return o
end

-- A picture Bg (b.atlas) behind the whole window f, on f.pic. Cover fit
-- inside the atlas region: fills the window at the art's aspect, the side
-- that overflows is cropped evenly at both ends. True when it drew one, so
-- the caller clears its colour base.
function K.DrawPictureBg(f, b)
    local pic = f.pic
    local id, info = K.ResolveAtlas(b.atlas)
    local FW, FH = f:GetSize()
    if not (id and info.width and info.width > 0 and info.height > 0 and FW > 8 and FH > 8) then
        pic:Hide(); return false
    end
    local l, r, t, bt = info.leftTexCoord, info.rightTexCoord, info.topTexCoord, info.bottomTexCoord
    local BW, BH = FW - 8, FH - 8
    local sc = math.max(BW / info.width, BH / info.height)
    local u, v = BW / (info.width * sc), BH / (info.height * sc)   -- visible share of the region
    local cu, cv, du, dv = (l + r) / 2, (t + bt) / 2, (r - l) * u / 2, (bt - t) * v / 2
    pic:SetTexture(id)
    pic:SetTexCoord(cu - du, cu + du, cv - dv, cv + dv)
    pic:Show()
    return true
end

-- ── Aspect (pure) ────────────────────────────────────────────────────────────
-- The biggest w x h box of ratio r (w / h) that keeps the point at fractions
-- ax, ay of the box where it is, stays inside bounds b = { x, y, w, h }, and
-- is no bigger than the given w. Returns x, y, w, h.
function K.FitAspect(x, y, w, h, r, ax, ay, b)
    local px, py = x + ax * w, y + ay * h
    local maxW = w
    local function Lim(v) if v < maxW then maxW = math.max(1, v) end end
    if b then
        if ax > 0 then Lim((px - b[1]) / ax) end
        if ax < 1 then Lim((b[1] + b[3] - px) / (1 - ax)) end
        if ay > 0 then Lim((py - b[2]) / ay * r) end
        if ay < 1 then Lim((b[2] + b[4] - py) / (1 - ay) * r) end
    end
    local nw = maxW
    local nh = nw / r
    return px - ax * nw, py - ay * nh, nw, nh
end

function K.NewSheet(cfg)
    local S = {}
    local f
    local view            -- the current view rect and scale (file px <-> area units)
    local fitS            -- scale of the fitted view
    local mview           -- wheel zoom / pan (session only), for mview.file
    local hoverRegion

    local function V() return cfg.View() end
    local function Active() return cfg.Active() end
    local function Regions() return cfg.Regions and cfg.Regions() or nil end

    local function GuidesOn()
        local g = V().guides
        if g ~= nil then return g end
        local regs = Regions()
        return not (regs and #regs > 0)
    end

    -- The part of the file on show: the whole file, or the active box plus a
    -- margin when zoomed (the first box when the active one is not set yet)
    local function ViewRect(W, H)
        local x, y, w, h = cfg.Box(Active())
        if not x then x, y, w, h = cfg.Box(cfg.boxes[1].key) end
        if V().zoom and x then
            local m = math.max(8, math.floor(math.max(w, h) * 0.25))
            local x0, y0 = math.max(0, x - m), math.max(0, y - m)
            local x1, y1 = math.min(W, x + w + m), math.min(H, y + h + m)
            return x0, y0, x1 - x0, y1 - y0
        end
        return 0, 0, W, H
    end

    local function ManualView()
        local id = cfg.File()
        return mview and mview.file == id and mview or nil
    end

    -- File pixels -> offset from the area's TOPLEFT
    local function ToArea(x, y)
        return view.ox + (x - view.vx) * view.s, -(view.oy + (y - view.vy) * view.s)
    end

    local function Place(o, x, y, w, h)
        local ax, ay = ToArea(x, y)
        o:ClearAllPoints()
        o:SetPoint("TOPLEFT", f.area, "TOPLEFT", ax - 1, ay + 1)
        o:SetSize(math.max(3, w * view.s + 2), math.max(3, h * view.s + 2))
        o:Show()
    end

    -- ── Guides ───────────────────────────────────────────────────────────────
    -- At each corner of the active box, a line to the bounds' side edge and
    -- one to its top or bottom edge, with the four gaps written beside them;
    -- green when left = right (or top = bottom)
    local function GLine(i)
        local g = f.guides
        local t = g.lines[i]
        if not t then
            t = g:CreateTexture(nil, "OVERLAY")
            g.lines[i] = t
        end
        return t
    end
    local function HLine(i, x0, x1, y, col)
        local t = GLine(i)
        local ax, ay = ToArea(math.min(x0, x1), y)
        local bx = ToArea(math.max(x0, x1), y)
        t:ClearAllPoints()
        t:SetPoint("TOPLEFT", f.area, "TOPLEFT", ax, ay + 1)
        t:SetSize(math.max(1, bx - ax), 2)
        t:SetColorTexture(col[1], col[2], col[3], 0.9)
        t:Show()
    end
    local function VLine(i, x, y0, y1, col)
        local t = GLine(i)
        local ax, ay = ToArea(x, math.min(y0, y1))
        local _, by = ToArea(x, math.max(y0, y1))
        t:ClearAllPoints()
        t:SetPoint("TOPLEFT", f.area, "TOPLEFT", ax - 1, ay)
        t:SetSize(2, math.max(1, ay - by))
        t:SetColorTexture(col[1], col[2], col[3], 0.9)
        t:Show()
    end

    -- The four gaps of the active box to its bounds: l, t, r, b
    function S.Gaps()
        local which = Active()
        local x, y, w, h = cfg.Box(which)
        local bx, by, bw, bh = cfg.Bounds(which)
        if not (x and bx) then return nil end
        return x - bx, y - by, (bx + bw) - (x + w), (by + bh) - (y + h)
    end

    -- Faint cross through the centre of the active box's bounds
    local function LayoutCross()
        local g = f.guides
        local bx, by, bw, bh = cfg.Bounds(Active())
        if not bx then g.crossH:Hide(); g.crossV:Hide(); return end
        local lx, ty = ToArea(bx, by)
        local rx, byy = ToArea(bx + bw, by + bh)
        local mx, my = ToArea(bx + bw / 2, by + bh / 2)
        g.crossH:ClearAllPoints()
        g.crossH:SetPoint("TOPLEFT", f.area, "TOPLEFT", lx, my)
        g.crossH:SetSize(math.max(1, rx - lx), 1)
        g.crossV:ClearAllPoints()
        g.crossV:SetPoint("TOPLEFT", f.area, "TOPLEFT", mx, ty)
        g.crossV:SetSize(1, math.max(1, ty - byy))
        g.crossH:Show(); g.crossV:Show()
    end

    local function LayoutGuides()
        local g = f.guides
        for _, t in ipairs(g.lines) do t:Hide() end
        for _, fs in pairs(g.labels) do fs:Hide() end
        if not GuidesOn() then return end
        local which = Active()
        local x, y, w, h = cfg.Box(which)
        local bx, by, bw, bh = cfg.Bounds(which)
        if not (x and bx) then return end
        local gl, gt, gr, gb = S.Gaps()
        local cH = (gl == gr) and COL_EVEN or COL_ODD
        local cV = (gt == gb) and COL_EVEN or COL_ODD
        local x1, y1, bx1, by1 = x + w, y + h, bx + bw, by + bh
        HLine(1, bx, x, y, cH);    VLine(2, x, by, y, cV)      -- top left
        HLine(3, x1, bx1, y, cH);  VLine(4, x1, by, y, cV)     -- top right
        HLine(5, bx, x, y1, cH);   VLine(6, x, y1, by1, cV)    -- bottom left
        HLine(7, x1, bx1, y1, cH); VLine(8, x1, y1, by1, cV)   -- bottom right
        local function Label(key, text, col, px, py, point)
            local fs = g.labels[key]
            if not fs then
                fs = g:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                g.labels[key] = fs
            end
            local ax, ay = ToArea(px, py)
            fs:ClearAllPoints()
            fs:SetPoint(point, f.area, "TOPLEFT", ax, ay)
            fs:SetText(text)
            fs:SetTextColor(col[1], col[2], col[3], 1)
            fs:Show()
        end
        Label("l", "L " .. gl, cH, (bx + x) / 2, y, "BOTTOM")
        Label("t", "T " .. gt, cV, x, (by + y) / 2, "RIGHT")
        Label("r", "R " .. gr, cH, (x1 + bx1) / 2, y1, "TOP")
        Label("b", "B " .. gb, cV, x1, (y1 + by1) / 2, "LEFT")
    end

    -- One line per file pixel over the shown picture, from 4 screen px per
    -- file pixel up (below that it is a grey wash); every 8th line stronger
    local function LayoutGrid()
        local g = f.grid
        for _, t in ipairs(g.lines) do t:Hide() end
        local v = view
        if not (V().grid and v and v.s >= 4) then return end
        local n = 0
        local function Line(vertical, pos, strong)
            n = n + 1
            local t = g.lines[n]
            if not t then
                t = g:CreateTexture(nil, "ARTWORK")
                g.lines[n] = t
            end
            t:SetColorTexture(1, 1, 1, strong and 0.35 or 0.14)
            t:ClearAllPoints()
            if vertical then
                t:SetPoint("TOPLEFT", f.area, "TOPLEFT", pos, -v.oy)
                t:SetSize(1, v.vh * v.s)
            else
                t:SetPoint("TOPLEFT", f.area, "TOPLEFT", v.ox, -pos)
                t:SetSize(v.vw * v.s, 1)
            end
            t:Show()
        end
        for x = math.ceil(v.vx), math.floor(v.vx + v.vw) do
            Line(true, v.ox + (x - v.vx) * v.s, x % 8 == 0)
        end
        for y = math.ceil(v.vy), math.floor(v.vy + v.vh) do
            Line(false, v.oy + (y - v.vy) * v.s, y % 8 == 0)
        end
    end

    -- ── Layout ───────────────────────────────────────────────────────────────
    function S.Layout()
        if not (f and f:IsShown()) then return end
        local id, W, H, title, failed = cfg.File()
        local area, tex = f.area, f.tex
        local b = SHEET_BGS[V().bg or 1] or SHEET_BGS[1]
        f.base:SetColorTexture(b[1], b[2], b[3], K.DrawPictureBg(f, b) and 0 or 1)
        f.title:SetText(title or "")

        local AW, AH = area:GetSize()
        for _, o in ipairs(f.pool) do o:Hide() end
        for _, o in pairs(f.boxOutlines) do o:Hide() end
        f.hover:Hide()
        for _, t in ipairs(f.guides.lines) do t:Hide() end
        for _, fs in pairs(f.guides.labels) do fs:Hide() end
        f.guides.crossH:Hide(); f.guides.crossV:Hide()
        for _, t in ipairs(f.grid.lines) do t:Hide() end
        view = nil
        if not (id and AW > 1 and AH > 1) then tex:Hide(); return end
        if not (W and H and W > 0 and H > 0) then
            tex:Hide()
            f.warn:SetText(failed and "Texture did not load on this client" or "Loading...")
            f.warn:Show()
            return
        end
        f.warn:Hide()

        local vx, vy, vw, vh = ViewRect(W, H)
        local s = math.min(AW / vw, AH / vh)
        local dw, dh = vw * s, vh * s
        local ox, oy = (AW - dw) / 2, (AH - dh) / 2
        fitS = s
        local mv = ManualView()
        if mv then
            -- The area's aspect; the view's centre kept on the file, so some
            -- of it always shows
            s = AW / mv.w
            local mh = AH / s
            mv.x = math.max(-mv.w / 2, math.min(W - mv.w / 2, mv.x))
            mv.y = math.max(-mh / 2, math.min(H - mh / 2, mv.y))
            vx, vy = math.max(0, mv.x), math.max(0, mv.y)
            vw, vh = math.min(W, mv.x + mv.w) - vx, math.min(H, mv.y + mh) - vy
            dw, dh = vw * s, vh * s
            ox, oy = (vx - mv.x) * s, (vy - mv.y) * s
        end
        view = { vx = vx, vy = vy, vw = vw, vh = vh, s = s, ox = ox, oy = oy, W = W, H = H }

        tex:SetTexture(id)
        tex:SetTexCoord(vx / W, (vx + vw) / W, vy / H, (vy + vh) / H)
        tex:ClearAllPoints()
        tex:SetPoint("TOPLEFT", area, "TOPLEFT", ox, -oy)
        tex:SetSize(dw, dh)
        tex:Show()

        local n = 0
        for _, reg in ipairs(Regions() or {}) do
            local x, y, w, h = cfg.RegionRect(reg, W, H)
            if x then
                if reg[1] == hoverRegion then
                    Place(f.hover, x, y, w, h)
                elseif V().showRegions ~= false then
                    n = n + 1
                    local o = f.pool[n]
                    if not o then
                        o = Outline(area, COL_REG)
                        f.pool[n] = o
                    end
                    Place(o, x, y, w, h)
                end
            end
        end
        local active = Active()
        local lv = area:GetFrameLevel()
        for i, bx in ipairs(cfg.boxes) do
            local o = f.boxOutlines[bx.key]
            local x, y, w, h = cfg.Box(bx.key)
            if x then Place(o, x, y, w, h) end
            o:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = active == bx.key and 2 or 1 })
            o:SetBackdropBorderColor(unpack(bx.col))
            o:SetFrameLevel(lv + 19 + i)
        end
        f.hover:SetFrameLevel(lv + 22)
        f.guides:SetFrameLevel(lv + 23)
        f.grid:SetFrameLevel(lv + 10)
        LayoutGrid()
        LayoutGuides()
        LayoutCross()
        f.gridBtn:SetText(V().grid and "Grid on" or "Grid off")
        f.zoomBtn:SetText(ManualView() and "Reset view" or V().zoom and "Whole file" or "Zoom to box")
        f.regBtn:SetText(V().showRegions ~= false and "Hide regions" or "Show regions")
        f.guideBtn:SetText(GuidesOn() and "Guides on" or "Guides off")
        if f.boxBtns then K.PutRing(f.boxRing, f.boxBtns[active]) end
        local x, _, w, h = cfg.ToolBox(active)
        f.sizeText:SetText(x and string.format("%d x %d", R(w), R(h)) or "-")
    end

    -- ── Pointer ──────────────────────────────────────────────────────────────
    -- The file-pixel rect the whole area shows now, margins included
    local function ShownRect()
        local AW, AH = f.area:GetSize()
        return view.vx - view.ox / view.s, view.vy - view.oy / view.s, AW / view.s, AH / view.s
    end

    -- Wheel: zoom around the pointer. Out past the fitted view goes back to
    -- it; in stops at about 64 screen px per file pixel.
    local function ZoomAt(delta)
        if not view then return end
        local AW = f.area:GetWidth()
        local sc = f.area:GetEffectiveScale()
        local mx, my = GetCursorPosition()
        local x, y, w = ShownRect()
        local px = x + (mx / sc - f.area:GetLeft()) / view.s
        local py = y + (f.area:GetTop() - my / sc) / view.s
        local nw = math.max(AW / 64, w * (delta > 0 and 0.8 or 1.25))
        if AW / nw <= (fitS or 0) then
            mview = nil
        else
            local k = nw / w
            mview = { file = (cfg.File()), x = px - (px - x) * k, y = py - (py - y) * k, w = nw }
        end
        S.Layout()
    end

    -- Pointer in area units: x right, y down from the area's TOPLEFT
    local function PointerArea()
        local sc = f.area:GetEffectiveScale()
        local mx, my = GetCursorPosition()
        return mx / sc - f.area:GetLeft(), f.area:GetTop() - my / sc
    end

    -- The file pixel under the pointer as a float, not clamped to the file
    local function PointerFile()
        local ax, ay = PointerArea()
        return view.vx + (ax - view.ox) / view.s, view.vy + (ay - view.oy) / view.s
    end

    -- The file pixel under the pointer, or nil when it is off the picture
    -- (clamped to the file instead when clamp is set, for dragging)
    local function PointerPixel(clamp)
        if not (view and f.tex:IsShown()) then return nil end
        if not clamp and not f.tex:IsMouseOver() then return nil end
        local sc = f.area:GetEffectiveScale()
        local mx, my = GetCursorPosition()
        mx, my = mx / sc, my / sc
        local px = view.vx + (mx - f.tex:GetLeft()) / view.s
        local py = view.vy + (f.tex:GetTop() - my) / view.s
        if clamp then
            px, py = math.max(0, math.min(view.W, px)), math.max(0, math.min(view.H, py))
        end
        return math.floor(px + (clamp and 0.5 or 0)), math.floor(py + (clamp and 0.5 or 0))
    end

    -- The saved box edge(s) under the pointer, active box first: key, and
    -- { l, r, t, b } (a corner sets two). Within EDGE_TOL area units.
    local function EdgeAt()
        if not (view and f.area:IsMouseOver()) then return nil end
        local ax, ay = PointerArea()
        local order = { Active() }
        for _, b in ipairs(cfg.boxes) do
            if b.key ~= order[1] then order[#order + 1] = b.key end
        end
        for _, which in ipairs(order) do
            local x, y, w, h = cfg.Box(which)
            if x then
                local l, t = view.ox + (x - view.vx) * view.s, view.oy + (y - view.vy) * view.s
                local r, b = l + w * view.s, t + h * view.s
                local inX = ax >= l - EDGE_TOL and ax <= r + EDGE_TOL
                local inY = ay >= t - EDGE_TOL and ay <= b + EDGE_TOL
                local e = {}
                if inY then
                    local dl, dr = math.abs(ax - l), math.abs(ax - r)
                    if dl <= EDGE_TOL and dl <= dr then e.l = true
                    elseif dr <= EDGE_TOL then e.r = true end
                end
                if inX then
                    local dt, db = math.abs(ay - t), math.abs(ay - b)
                    if dt <= EDGE_TOL and dt <= db then e.t = true
                    elseif db <= EDGE_TOL then e.b = true end
                end
                if next(e) then return which, e end
            end
        end
    end

    -- The smallest region of the current file under the pointer
    local function RegionAt(px, py)
        local _, W, H = cfg.File()
        local best, bestA
        for _, reg in ipairs(Regions() or {}) do
            local x, y, w, h = cfg.RegionRect(reg, W, H)
            if x and px >= x and px < x + w and py >= y and py < y + h and (not bestA or w * h < bestA) then
                best, bestA = reg, w * h
            end
        end
        return best
    end

    -- ── Box tools ────────────────────────────────────────────────────────────
    local function Ratio() return cfg.Aspect and cfg.Aspect() or nil end
    local function BoundsT(which)
        local bx, by, bw, bh = cfg.Bounds(which)
        if bx then return { bx, by, bw, bh } end
    end

    -- Holds a box to the aspect, keeping the point at ax, ay of it in place;
    -- width rules unless byH. Without an aspect it comes back unchanged.
    local function Hold(which, x, y, w, h, ax, ay, byH)
        local r = Ratio()
        if not r then return x, y, w, h end
        if byH then w = h * r end
        return K.FitAspect(x, y, w, w / r, r, ax, ay, BoundsT(which))
    end

    local function Store(which, x, y, w, h)
        cfg.SetBox(which, x, y, w, h)
        cfg.Changed()
    end

    -- Resize / Centre on whole pixels: the extra pixel of an odd change goes
    -- to the left / top
    local function Snap(which, x, y)
        if cfg.Whole and cfg.Whole(which) == false then return x, y end
        return math.floor(x), math.floor(y)
    end

    -- Width and height by d, the centre kept
    function S.Resize(d)
        local which = Active()
        local x, y, w, h = cfg.ToolBox(which)
        if not x or w + d < 1 or h + d < 1 then return end
        local r = Ratio()
        local nw, nh = w + d, h + d
        if r then nh = nw / r end
        local nx, ny = x + w / 2 - nw / 2, y + h / 2 - nh / 2
        if r and d > 0 then nx, ny, nw, nh = Hold(which, nx, ny, nw, nh, 0.5, 0.5) end
        nx, ny = Snap(which, nx, ny)
        Store(which, nx, ny, nw, nh)
    end

    -- Equal gaps left/right and top/bottom inside the bounds, size kept
    function S.Centre()
        local which = Active()
        local x, y, w, h = cfg.ToolBox(which)
        local bx, by, bw, bh = cfg.Bounds(which)
        if not (x and bx) then return end
        local nx, ny = Snap(which, bx + (bw - w) / 2, by + (bh - h) / 2)
        Store(which, nx, ny, w, h)
    end

    -- The biggest box of the aspect inside the current one, centred on it
    function S.MatchAspect()
        local which = Active()
        local r = Ratio()
        local x, y, w, h = cfg.ToolBox(which)
        if not (r and x) then return end
        local nw, nh = w, w / r
        if nh > h then nh, nw = h, h * r end
        Store(which, x + (w - nw) / 2, y + (h - nh) / 2, nw, nh)
    end

    local function Nudge(dx, dy, dw, dh)
        local which = Active()
        local x, y, w, h = cfg.ToolBox(which)
        if not x or w + dw < 1 or h + dh < 1 then return end
        if dw ~= 0 or dh ~= 0 then
            x, y, w, h = Hold(which, x, y, w + dw, h + dh, 0, 0, dw == 0)
        end
        Store(which, x + dx, y + dy, w, h)
    end

    -- Arrows move the active box 1 px (Shift 10); Ctrl+arrows move its right
    -- or bottom edge. Only while the pointer is over the sheet, and never in
    -- combat (SetPropagateKeyboardInput is blocked there).
    local function OnSheetKey(self, key)
        if InCombatLockdown() then return end
        local a = ARROWS[key]
        if not a then self:SetPropagateKeyboardInput(true); return end
        self:SetPropagateKeyboardInput(false)
        local step = IsShiftKeyDown() and 10 or 1
        if IsControlKeyDown() then Nudge(0, 0, a[1] * step, a[2] * step)
        else Nudge(a[1] * step, a[2] * step, 0, 0) end
    end

    function S.SetHoverRegion(name)
        if name ~= hoverRegion then hoverRegion = name; S.Layout() end
    end

    -- ── Build ────────────────────────────────────────────────────────────────
    function S.Build()
        f = BNB.CreateBackdropFrame("Frame", cfg.name, UIParent)
        S.frame = f
        f:SetSize(600, 560)
        f:SetFrameStrata("MEDIUM")
        f:SetClampedToScreen(true)
        f:SetMovable(true); f:SetResizable(true)
        f:SetResizeBounds(cfg.minW or 470, 260, 1800, 1200)
        f:EnableMouse(true)
        f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", f.StartMoving)
        f:SetScript("OnDragStop", f.StopMovingOrSizing)
        f:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 14,
            insets = { left = 3, right = 3, top = 3, bottom = 3 },
        })
        f:SetBackdropColor(0.05, 0.05, 0.06, 0.97)
        f:SetBackdropBorderColor(0.6, 0.6, 0.65, 1)
        if BNB.SetMoveCursor then BNB.SetMoveCursor(f) end

        f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        f.title:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -9)
        f.title:SetPoint("RIGHT", f, "RIGHT", -376, 0)
        f.title:SetJustifyH("LEFT")
        f.title:SetWordWrap(false)

        -- Top bar: view
        f.bgBtn = K.SmallBtn(f, "Bg", 40, function()
            -- Changed, not just Layout: a lab's preview may share the Bg
            local v = V(); v.bg = ((v.bg or 1) % #SHEET_BGS) + 1; cfg.Changed()
        end)
        f.bgBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -8, -6)
        f.regBtn = K.SmallBtn(f, "Hide regions", 110, function()
            -- nil = shown, false = hidden. Not `x and nil or false`: always false
            local v = V()
            if v.showRegions == false then v.showRegions = nil else v.showRegions = false end
            S.Layout()
        end)
        f.regBtn:SetPoint("RIGHT", f.bgBtn, "LEFT", -6, 0)
        f.zoomBtn = K.SmallBtn(f, "Zoom to box", 110, function()
            if ManualView() then mview = nil
            else local v = V(); v.zoom = not v.zoom or nil end
            S.Layout()
        end)
        f.zoomBtn:SetPoint("RIGHT", f.regBtn, "LEFT", -6, 0)
        f.gridBtn = K.SmallBtn(f, "Grid off", 70, function()
            local v = V(); v.grid = not v.grid or nil; S.Layout()
        end)
        f.gridBtn:SetPoint("RIGHT", f.zoomBtn, "LEFT", -6, 0)

        -- Bottom bar: box tools
        local last
        if #cfg.boxes > 1 then
            f.boxBtns = {}
            f.boxRing = K.Ring(f)
            for _, b in ipairs(cfg.boxes) do
                local btn = K.SmallBtn(f, b.label, 50, function() cfg.SetActive(b.key); cfg.Changed() end)
                if last then btn:SetPoint("LEFT", last, "RIGHT", 6, 0)
                else btn:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 10, 26) end
                f.boxBtns[b.key], last = btn, btn
            end
        end
        local shrink = K.SmallBtn(f, "-", 26, function() S.Resize(IsShiftKeyDown() and -10 or -1) end)
        if last then shrink:SetPoint("LEFT", last, "RIGHT", 14, 0)
        else shrink:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 10, 26) end
        f.sizeText = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        f.sizeText:SetPoint("LEFT", shrink, "RIGHT", 4, 0)
        f.sizeText:SetWidth(84)
        local grow = K.SmallBtn(f, "+", 26, function() S.Resize(IsShiftKeyDown() and 10 or 1) end)
        grow:SetPoint("LEFT", f.sizeText, "RIGHT", 4, 0)
        local centre = K.SmallBtn(f, "Centre", 64, S.Centre)
        centre:SetPoint("LEFT", grow, "RIGHT", 10, 0)
        f.guideBtn = K.SmallBtn(f, "Guides on", 84, function()
            V().guides = not GuidesOn()
            S.Layout()
        end)
        f.guideBtn:SetPoint("LEFT", centre, "RIGHT", 6, 0)
        for _, b in ipairs({ shrink, grow }) do
            b:HookScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_TOP")
                GameTooltip:AddLine(self == shrink and "Smaller by 1 px, centre kept" or "Bigger by 1 px, centre kept", 1, 1, 1)
                GameTooltip:AddLine("Shift: 10", 0.7, 0.7, 0.7)
                GameTooltip:Show()
            end)
            b:HookScript("OnLeave", function() GameTooltip:Hide() end)
        end
        if cfg.AddTools then cfg.AddTools(f, f.guideBtn, S) end

        local area = CreateFrame("Frame", nil, f)
        area:SetPoint("TOPLEFT", f, "TOPLEFT", 8, -32)
        area:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -8, 52)
        area:SetClipsChildren(true)
        f.area = area
        f.base = area:CreateTexture(nil, "BACKGROUND", nil, -8)
        f.base:SetAllPoints()
        f.pic = f:CreateTexture(nil, "BACKGROUND", nil, 7)   -- picture Bg, the whole window
        f.pic:SetPoint("TOPLEFT", 4, -4)
        f.pic:SetPoint("BOTTOMRIGHT", -4, 4)
        f.pic:Hide()
        f.tex = area:CreateTexture(nil, "ARTWORK")
        f.pool = {}
        f.boxOutlines = {}
        for _, b in ipairs(cfg.boxes) do f.boxOutlines[b.key] = Outline(area, b.col) end
        f.hover = Outline(area, COL_HOVER)
        f.draw  = Outline(area, { 1, 1, 1, 1 })
        f.draw:SetFrameLevel(area:GetFrameLevel() + 25)
        f.grid = CreateFrame("Frame", nil, area)
        f.grid:SetAllPoints()
        f.grid.lines = {}
        f.guides = CreateFrame("Frame", nil, area)
        f.guides:SetAllPoints()
        f.guides.lines, f.guides.labels = {}, {}
        for _, k in ipairs({ "crossH", "crossV" }) do
            local c = f.guides:CreateTexture(nil, "ARTWORK")
            c:SetColorTexture(1, 1, 1, 0.22)
            f.guides[k] = c
        end

        f.warn = f:CreateFontString(nil, "OVERLAY", "GameFontRedSmall")
        f.warn:SetPoint("CENTER", area, "CENTER")

        -- Pointer readout: file pixel and the region under it
        f.coords = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        f.coords:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 10, 8)
        f.coords:SetPoint("RIGHT", f, "RIGHT", -24, 0)
        f.coords:SetJustifyH("LEFT")
        f.coords:SetWordWrap(false)

        -- Left-drag draws the active box; a click without a drag picks the
        -- region under the pointer
        local drag, lastKey, pan
        area:SetScript("OnUpdate", function()
            if pan then
                if not IsMouseButtonDown(pan.btn) then pan = nil; return end
                local sx, sy = GetCursorPosition()
                local k = area:GetEffectiveScale() * pan.s
                mview = { file = pan.file, w = pan.w,
                          x = pan.x - (sx - pan.sx) / k, y = pan.y + (sy - pan.sy) / k }
                S.Layout()
                return
            end
            if drag then
                if not IsMouseButtonDown("LeftButton") then drag = nil; f.draw:Hide(); return end
                if not view then return end
                if drag.edge then
                    -- Dragging a box edge: whole pixels, never past the
                    -- opposite edge; saved on release like a drawn box
                    local fx, fy = PointerFile()
                    local x, y, w, h = unpack(drag.box)
                    local r, b = x + w, y + h
                    local e = drag.edge
                    if e.l then x = math.min(R(fx), r - 1) end
                    if e.r then r = math.max(R(fx), x + 1) end
                    if e.t then y = math.min(R(fy), b - 1) end
                    if e.b then b = math.max(R(fy), y + 1) end
                    w, h = r - x, b - y
                    -- The opposite edge or corner stays put under an aspect
                    x, y, w, h = Hold(drag.which, x, y, w, h,
                        e.l and 1 or 0, e.t and 1 or 0, not (e.l or e.r))
                    drag.rect = { x, y, w, h }
                    Place(f.draw, x, y, w, h)
                    f.coords:SetText(string.format("%s  x %d  y %d   %d x %d",
                        drag.which, R(x), R(y), R(w), R(h)))
                    return
                end
                local px, py = PointerPixel(true)
                if not px then return end
                if not drag.moved then
                    local sx, sy = GetCursorPosition()
                    if math.abs(sx - drag.sx) + math.abs(sy - drag.sy) < 6 then return end
                    drag.moved = true
                end
                if px == drag.lx and py == drag.ly then return end
                drag.lx, drag.ly = px, py
                local x0, y0 = math.min(px, drag.px), math.min(py, drag.py)
                local w, h = math.abs(px - drag.px), math.abs(py - drag.py)
                local r = Ratio()
                if r and w >= 1 and h >= 1 then
                    -- The start corner stays put; the longer side (in ratio) rules
                    local ax, ay = px < drag.px and 1 or 0, py < drag.py and 1 or 0
                    x0, y0, w, h = Hold(Active(), x0, y0, w, h, ax, ay, h * r > w)
                end
                -- Only a white outline while drawing: the box is saved on
                -- release, so the zoom and the preview do not chase it
                drag.rect = (w >= 1 and h >= 1) and { x0, y0, w, h } or nil
                if drag.rect then Place(f.draw, x0, y0, w, h) else f.draw:Hide() end
                f.coords:SetText(string.format("x %d  y %d   drawing %d x %d", px, py, R(w), R(h)))
                return
            end
            local onEdge = EdgeAt() ~= nil
            if onEdge ~= (f._edgeCursor or false) then
                f._edgeCursor = onEdge
                if onEdge then BNB.ShowCursor("size") else BNB.ClearCursor() end
            end
            local px, py = PointerPixel()
            local reg = px and RegionAt(px, py)
            local key = px and (px .. "," .. py .. (reg and reg[1] or "")) or ""
            if key == lastKey then return end
            lastKey = key
            f.coords:SetText(px and string.format("x %d  y %d%s", px, py,
                reg and ("   |cff59d9ff" .. reg[1] .. "|r (click to pick)") or "") or
                "Drag: draw the box   Drag an edge: resize   Wheel: zoom   Right-drag: pan   Arrows: move 1 (Shift 10)   Ctrl+arrows: resize")
            S.SetHoverRegion(reg and reg[1] or nil)
        end)
        area:EnableMouse(true)
        area:EnableMouseWheel(true)
        area:SetScript("OnMouseWheel", function(_, delta) ZoomAt(delta) end)
        area:SetScript("OnMouseDown", function(_, btn)
            if (btn == "RightButton" or btn == "MiddleButton") and view and not drag then
                local x, y, w = ShownRect()
                local sx, sy = GetCursorPosition()
                pan = { btn = btn, sx = sx, sy = sy, x = x, y = y, w = w, s = view.s, file = (cfg.File()) }
                return
            end
            if btn ~= "LeftButton" then return end
            local which, edges = EdgeAt()
            if which then
                drag = { edge = edges, which = which, box = { cfg.Box(which) } }
                return
            end
            local px, py = PointerPixel(true)
            if not px then return end
            local sx, sy = GetCursorPosition()
            drag = { px = px, py = py, sx = sx, sy = sy }
        end)
        area:SetScript("OnMouseUp", function(_, btn)
            if btn ~= "LeftButton" or not drag then return end
            local d = drag
            drag, lastKey = nil, nil
            f.draw:Hide()
            if d.edge then
                if d.rect then
                    if #cfg.boxes > 1 and d.which ~= Active() then cfg.SetActive(d.which) end
                    Store(d.which, unpack(d.rect))
                end
                return
            end
            if d.moved then
                if d.rect then Store(Active(), unpack(d.rect)) end
                return
            end
            local px, py = PointerPixel()
            local reg = px and RegionAt(px, py)
            if reg and cfg.PickRegion then cfg.PickRegion(reg[1]) end
        end)
        pcall(area.SetPropagateKeyboardInput, area, true)
        area:SetScript("OnKeyDown", OnSheetKey)
        area:SetScript("OnEnter", function(self)
            if not InCombatLockdown() then self:EnableKeyboard(true) end
        end)
        area:SetScript("OnLeave", function(self)
            if not InCombatLockdown() then self:EnableKeyboard(false) end
            if f._edgeCursor then f._edgeCursor = nil; BNB.ClearCursor() end
            S.SetHoverRegion(nil)
        end)

        local grip = CreateFrame("Button", nil, f)
        grip:SetSize(16, 16)
        grip:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
        grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
        grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
        grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
        grip:SetScript("OnMouseDown", function(_, btn)
            if btn == "LeftButton" then BNB.StartGripSizing(f) end
        end)
        grip:SetScript("OnMouseUp", function()
            BNB.StopGripSizing(f)
            local v = V(); v.sw, v.sh = f:GetSize()
        end)

        f:SetScript("OnSizeChanged", S.Layout)
        f:HookScript("OnShow", S.Layout)
        local v = V()
        if v.sw and v.sh then f:SetSize(v.sw, v.sh) end
        f:Hide()
        return f
    end

    return S
end

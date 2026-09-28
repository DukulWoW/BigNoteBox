-- BigNoteBox UI/IconLab.lua
-- Developer Tools > Icon Lab (/bnb iconlab, debug mode). ALL-126.
-- Measures game art for note icon frames: one cropped picture with a hole
-- that is laid over a note icon. Three windows:
--   control - picks the entry, name, exact numbers, atlas regions, Add
--   sheet   - the file with the picture area (gold), the hole (green) and
--             the atlas regions drawn on it; draw a box by dragging, move it
--             with the arrow keys, shrink/grow/centre it, corner guides
--   preview - a frame around real icons at every size the addon uses, with
--             shape (square / circle), layer (over / under) and tint
-- Work in progress is kept in BigNoteBoxDB.devIconLab across reloads.
--
-- Seed files and their atlas regions come from UI/IconLabData.lua, generated
-- by _work/tools/iconlab-regions.py and loaded only in dev builds (#@debug@
-- in the TOC); without it the Lab starts empty and takes pasted files.
-- An entry is one file, or one file + atlas pair (a region picked from the
-- list), the same as the Background Lab. Shared pieces: UI/LabKit.lua; the
-- preview draws through UI/IconFrameLayer.lua, as the note icons will.
-- Button and mode names on the sheet and preview are dev-only English.

local BNB = BigNoteBox
if not BNB then return end
local L = BNB.L
local K = BNB._LabKit
local IFL = BNB.IconFrameLayer

local GROUPS = {
    seed  = { label = "Files (Icon Lab data)" },
    added = { label = "Added in game" },
}

local LIST = {}          -- { g, id, path, atlas, key }
local REGIONS = {}       -- [file id] = { { name, w, h, l, r, t, b }, ... }

local C_W, C_H = 340, 690
local C_PAD    = 16
local SHEET_BGS = {      -- behind the sheet and the preview, cycled with Bg
    { 0.08, 0.08, 0.10 }, { 0.55, 0.55, 0.58 }, { 0.85, 0.20, 0.75 },
    -- Pictures, by atlas (the art is a 1022x602 region of a 1024x1024 file):
    -- behind the whole window, cover-fitted (fills it, keeps the aspect,
    -- crops the overflow evenly). The colour shows if the atlas is missing.
    { 0.08, 0.08, 0.10, atlas = "scoreboard-background-islands-horde" },
    { 0.08, 0.08, 0.10, atlas = "scoreboard-background-islands-alliance" },
    { 0.08, 0.08, 0.10, atlas = "scoreboard-background-warfronts-alliance" },
    { 0.08, 0.08, 0.10, atlas = "scoreboard-background-warfronts-horde" },
}
local COL_CROP  = { 1, 0.82, 0, 1 }
local COL_HOLE  = { 0.30, 1, 0.40, 1 }
local COL_HOVER = { 0.35, 0.85, 1, 1 }
local COL_REG   = { 1, 0, 1, 1 }            -- bright magenta (Dukul)
local COL_EVEN  = { 0.30, 1, 0.40 }      -- guide gaps that match their pair
local COL_ODD   = { 1, 0.25, 0.25 }

-- Icon sizes the addon draws note icons at (NoteList compact / Oracle
-- default / NoteList / sticky / Trash and spacious list), plus a big one
local PREVIEW_SIZES = { { 16, "16" }, { 26, "26" }, { 32, "32" }, { 36, "36" }, { 42, "42" }, { 64, "64" } }
local SAMPLE_ICONS = {
    "INV_Misc_Note_01", "INV_Misc_Book_09", "INV_Sword_04", "INV_Misc_Map_01",
    "INV_Potion_54", "Spell_Fire_FlameBolt", "Spell_Nature_Lightning", "Ability_Warrior_Charge",
    "INV_Misc_Gem_Diamond_02", "Spell_Holy_HolyBolt", "INV_Misc_Head_Dragon_01", "Ability_Mount_RidingHorse",
    "INV_Misc_Coin_01", "Spell_Shadow_ShadowBolt", "INV_Helmet_03", "Spell_Frost_FrostBolt02",
}

local BOX_FIELDS = { area = { "cx", "cy", "cw", "ch" }, hole = { "hx", "hy", "hw", "hh" } }

local _ctl, _sh, _pv
local _idx = 1
local _hoverRegion      -- region name under the list or sheet pointer
local _prober = K.NewProber()
local _sizes  = _prober.sizes

-- ── Saved state ──────────────────────────────────────────────────────────────
local function Store()
    BigNoteBoxDB.devIconLab = BigNoteBoxDB.devIconLab or { e = {} }
    return BigNoteBoxDB.devIconLab
end

local function State(i)
    local e = LIST[i]
    local s = Store().e
    s[e.key] = s[e.key] or {}
    return s[e.key]
end

-- Which box the sheet tools act on: "area" (picture area) or "hole"
local function Active() return Store().active == "hole" and "hole" or "area" end

-- File sizes are saved once probed (Store().sizes), so Export has them for
-- entries not opened this session. A failed probe is not saved: the file
-- may load another time.
local function FileSize(id)
    local sz = _sizes[id]
    if sz == nil then sz = Store().sizes and Store().sizes[id] end
    return sz
end

local function RememberSize(id)
    local sz = _sizes[id]
    if type(sz) == "table" then
        local s = Store()
        s.sizes = s.sizes or {}
        s.sizes[id] = { sz[1], sz[2] }
    end
end

local function NativeSize(i)
    local st, sz = State(i), FileSize(LIST[i].id)
    return st.w or (sz and sz[1]), st.h or (sz and sz[2])
end

-- A box in file pixels, or nil while it is not set
local function Box(i, which)
    local st, f = State(i), BOX_FIELDS[which]
    if st[f[3]] and st[f[4]] then return st[f[1]] or 0, st[f[2]] or 0, st[f[3]], st[f[4]] end
end

-- Picture area, or the whole file when none is set
local function AreaOrFile(i)
    local x, y, w, h = Box(i, "area")
    if x then return x, y, w, h end
    local W, H = NativeSize(i)
    if W and H then return 0, 0, W, H end
end

-- What a box is measured against: the file for the area, the area for the hole
local function Bounds(i, which)
    if which == "hole" then return AreaOrFile(i) end
    local W, H = NativeSize(i)
    if W and H then return 0, 0, W, H end
end

-- Stores a box; nil x clears it. Sizes are whole pixels. The picture area
-- is cut from the file, so it stays inside it on whole pixels. The hole only
-- positions the icon, so it may sit on a half pixel (an even hole centred in
-- an odd gap) and outside the file (negative x/y), which puts the art beside
-- or below the icon rather than around it.
local function SetBox(i, which, x, y, w, h)
    local st, f = State(i), BOX_FIELDS[which]
    if not x then
        st[f[1]], st[f[2]], st[f[3]], st[f[4]] = nil, nil, nil, nil
        return
    end
    local function R(v) return math.floor(v + 0.5) end
    local function P(v)
        if which == "hole" then return math.floor(v * 2 + 0.5) / 2 end
        return R(v)
    end
    x, y, w, h = P(x), P(y), math.max(1, R(w)), math.max(1, R(h))
    local W, H = NativeSize(i)
    if W and H and which == "area" then
        x, y = math.max(0, math.min(x, W - 1)), math.max(0, math.min(y, H - 1))
        w, h = math.min(w, W - x), math.min(h, H - y)
    end
    st[f[1]], st[f[2]], st[f[3]], st[f[4]] = x, y, w, h
end

-- The box the tools start from: the saved one, else the whole area (area) or
-- its middle 70 % (hole: about the opening of a plain ring)
local function ToolBox(i, which)
    local x, y, w, h = Box(i, which)
    if x then return x, y, w, h end
    local bx, by, bw, bh = AreaOrFile(i)
    if not bx then return nil end
    if which == "area" then return bx, by, bw, bh end
    return bx + bw * 0.15, by + bh * 0.15, bw * 0.7, bh * 0.7
end

-- The entry as an IconFrameLayer def, or nil while the file size is unknown.
-- Without a hole the middle 70 % of the area stands in (second return true),
-- so shape and layer can be tried before the hole is measured.
local function FrameDef(i)
    local W, H = NativeSize(i)
    if not (W and H) then return nil end
    local standIn = not Box(i, "hole")
    local hx, hy, hw, hh = ToolBox(i, "hole")
    if not hx then return nil end
    local cx, cy, cw, ch = AreaOrFile(i)
    local st = State(i)
    return { file = LIST[i].id, w = W, h = H, crop = { cx, cy, cw, ch }, hole = { hx, hy, hw, hh },
             shape = st.shape, layer = st.layer, tint = st.tint, scale = st.scale }, standIn
end

-- ── The list: seed files, then files and regions added in game ───────────────
-- An entry is a file, or a file + atlas pair, plus an optional variant
-- number: "New frame from this file" makes another entry on the same file
-- (or region) for a sheet that holds several frames, keyed "<key>-2" etc.
local function SameEntry(e, id, atlas, variant)
    return e.id == id and (e.atlas or "") == (atlas or "") and (e.variant or 1) == (variant or 1)
end

local function Append(g, id, path, atlas, variant)
    for i, e in ipairs(LIST) do
        if SameEntry(e, id, atlas, variant) then return i end
    end
    local key = K.EntryKey(id, path or "", atlas)
    if variant and variant > 1 then key = key .. "-" .. variant end
    LIST[#LIST + 1] = { g = g, id = id, path = path or "", atlas = atlas, variant = variant, key = key }
    -- Any other file: the full atlas table (UI/IconLabAtlas.lua), keyed by
    -- lower-case path without extension, or by file ID
    local A = BNB.IconLabAtlas
    if not REGIONS[id] and A then
        local p = (path or ""):gsub("\\", "/"):lower():gsub("%.[^./]+$", "")
        REGIONS[id] = A[id] or (p ~= "" and A[p]) or nil
    end
    return #LIST
end

local _loaded
local function LoadList()
    if _loaded then return end
    _loaded = true
    local data = BNB.IconLabData
    for _, f in ipairs(data and data.files or {}) do
        if K.ValidID(f.id) then
            Append("seed", f.id, f.path)
            REGIONS[f.id] = f.regions
        end
    end
    local s = Store()
    local kept = {}
    for _, c in ipairs(s.custom or {}) do
        if type(c) == "table" and K.ValidID(c.id) then
            kept[#kept + 1] = c
            Append("added", c.id, c.path, c.atlas, c.variant)
        end
    end
    if s.custom then s.custom = kept end
end

local function AddCustom(id, path, atlas, variant)
    if not K.ValidID(id) then return nil end
    for i, e in ipairs(LIST) do
        if SameEntry(e, id, atlas, variant) then return i end   -- already listed: just go there
    end
    local s = Store()
    s.custom = s.custom or {}
    s.custom[#s.custom + 1] = { id = id, path = path or "", atlas = atlas, variant = variant }
    return Append("added", id, path, atlas, variant)
end

-- Another entry on the current entry's file (and region), next free number
local function NewVariant()
    local e = LIST[_idx]
    if not e then return nil end
    local n = 2
    for _, o in ipairs(LIST) do
        if o.id == e.id and (o.atlas or "") == (e.atlas or "") then
            n = math.max(n, (o.variant or 1) + 1)
        end
    end
    return AddCustom(e.id, e.path ~= "" and e.path or FilePath(e.id), e.atlas, n)
end

local function RemoveCustom(i)
    local e = LIST[i]
    if not (e and e.g == "added") then return end
    local s = Store()
    for n = #(s.custom or {}), 1, -1 do
        if SameEntry(s.custom[n], e.id, e.atlas, e.variant) then table.remove(s.custom, n) end
    end
    s.e[e.key] = nil
    table.remove(LIST, i)
end

-- The path of a file as the list knows it (an atlas entry has none of its own)
local function FilePath(id)
    for _, e in ipairs(LIST) do
        if e.id == id and e.path ~= "" then return e.path end
    end
    return ""
end

-- ── Regions ──────────────────────────────────────────────────────────────────
-- A region's rectangle in file pixels. The live atlas wins when this client
-- has it on the same file; otherwise the generated (Retail) coordinates.
-- Returns x, y, w, h, live (true / false), or nil while the size is unknown.
-- Cached per file and size: the sheet asks for every region on each pointer move.
local _rects = {}   -- [file id] = { W, H, [name] = { x, y, w, h, live } or false }

local function RegionRect(fileID, reg, W, H)
    if not (W and H) then return nil end
    local c = _rects[fileID]
    if not (c and c.W == W and c.H == H) then
        c = { W = W, H = H }
        _rects[fileID] = c
    end
    local r = c[reg[1]]
    if r == nil then
        r = false
        local id, info = K.ResolveAtlas(reg[1])
        if id == fileID and info then
            local x, y, w, h = K.CropFromTexCoords(info.leftTexCoord, info.rightTexCoord,
                info.topTexCoord, info.bottomTexCoord, W, H)
            if x then r = { x, y, w, h, true } end
        end
        if not r then
            local x, y, w, h = K.CropFromTexCoords(reg[4], reg[5], reg[6], reg[7], W, H)
            if x then r = { x, y, w, h, false } end
        end
        c[reg[1]] = r
    end
    if r then return r[1], r[2], r[3], r[4], r[5] end
end

local function FindRegion(fileID, name)
    for _, reg in ipairs(REGIONS[fileID] or {}) do
        if reg[1] == name then return reg end
    end
end

-- Fills an atlas entry's picture area once, while none is set (a hand-tuned
-- one survives later visits)
local function ApplyAtlasCrop(i)
    local e = LIST[i]
    if not (e and e.atlas) then return end
    local st = State(i)
    local W, H = NativeSize(i)
    if st.cw or not (W and H) then return end
    local reg = FindRegion(e.id, e.atlas) or { e.atlas, 0, 0, 0, 0, 0, 0 }
    local x, y, w, h = RegionRect(e.id, reg, W, H)
    if x then st.cx, st.cy, st.cw, st.ch = x, y, w, h end
end

-- Guides are on by default only for files without atlas regions: on a sheet
-- the gap to the file edge means nothing
local function GuidesOn()
    local g = Store().guides
    if g ~= nil then return g end
    local e = LIST[_idx]
    return not (e and REGIONS[e.id] and #REGIONS[e.id] > 0)
end

-- ── Sheet window ─────────────────────────────────────────────────────────────
local Refresh, Go, LayoutPreview

-- Outline frame, 1 px unless given
local function Outline(parent, col, px)
    local o = BNB.CreateBackdropFrame("Frame", nil, parent)
    o:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = px or 1 })
    o:SetBackdropBorderColor(col[1], col[2], col[3], col[4])
    o:EnableMouse(false)
    return o
end

-- The part of the file on show: the whole file, or the active box plus a
-- margin when zoomed (the picture area when the hole is not set yet)
local function ViewRect(W, H)
    local x, y, w, h = Box(_idx, Active())
    if not x then x, y, w, h = Box(_idx, "area") end
    if Store().zoom and x then
        local m = math.max(8, math.floor(math.max(w, h) * 0.25))
        local x0, y0 = math.max(0, x - m), math.max(0, y - m)
        local x1, y1 = math.min(W, x + w + m), math.min(H, y + h + m)
        return x0, y0, x1 - x0, y1 - y0
    end
    return 0, 0, W, H
end

-- File pixels -> offset from the sheet area's TOPLEFT
local function ToArea(x, y)
    local v = _sh._view
    return v.ox + (x - v.vx) * v.s, -(v.oy + (y - v.vy) * v.s)
end

-- Corner guides: at each corner of the active box, a line to the bounds'
-- side edge and one to its top or bottom edge, with the four gaps written
-- beside them; green when left = right (or top = bottom)
local function Line(i)
    local g = _sh.guides
    local t = g.lines[i]
    if not t then
        t = g:CreateTexture(nil, "OVERLAY")
        g.lines[i] = t
    end
    return t
end

local function HLine(i, x0, x1, y, col)
    local t = Line(i)
    local ax, ay = ToArea(math.min(x0, x1), y)
    local bx = ToArea(math.max(x0, x1), y)
    t:ClearAllPoints()
    t:SetPoint("TOPLEFT", _sh.area, "TOPLEFT", ax, ay + 1)
    t:SetSize(math.max(1, bx - ax), 2)
    t:SetColorTexture(col[1], col[2], col[3], 0.9)
    t:Show()
end

local function VLine(i, x, y0, y1, col)
    local t = Line(i)
    local ax, ay = ToArea(x, math.min(y0, y1))
    local _, by = ToArea(x, math.max(y0, y1))
    t:ClearAllPoints()
    t:SetPoint("TOPLEFT", _sh.area, "TOPLEFT", ax - 1, ay)
    t:SetSize(2, math.max(1, ay - by))
    t:SetColorTexture(col[1], col[2], col[3], 0.9)
    t:Show()
end

-- The four gaps of the active box to its bounds: l, t, r, b
local function Gaps()
    local which = Active()
    local x, y, w, h = Box(_idx, which)
    local bx, by, bw, bh = Bounds(_idx, which)
    if not (x and bx) then return nil end
    return x - bx, y - by, (bx + bw) - (x + w), (by + bh) - (y + h)
end

-- Faint cross through the centre of the active box's bounds (the file for
-- the picture area, the picture area for the hole), always shown
local function LayoutCross()
    local g = _sh.guides
    local bx, by, bw, bh = Bounds(_idx, Active())
    if not bx then g.crossH:Hide(); g.crossV:Hide(); return end
    local cx, cy = bx + bw / 2, by + bh / 2
    local lx, ty = ToArea(bx, by)
    local rx, byy = ToArea(bx + bw, by + bh)
    local mx, my = ToArea(cx, cy)
    g.crossH:ClearAllPoints()
    g.crossH:SetPoint("TOPLEFT", _sh.area, "TOPLEFT", lx, my)
    g.crossH:SetSize(math.max(1, rx - lx), 1)
    g.crossV:ClearAllPoints()
    g.crossV:SetPoint("TOPLEFT", _sh.area, "TOPLEFT", mx, ty)
    g.crossV:SetSize(1, math.max(1, ty - byy))
    g.crossH:Show(); g.crossV:Show()
end

local function LayoutGuides()
    local g = _sh.guides
    for _, t in ipairs(g.lines) do t:Hide() end
    for _, fs in pairs(g.labels) do fs:Hide() end
    if not GuidesOn() then return end
    local which = Active()
    local x, y, w, h = Box(_idx, which)
    local bx, by, bw, bh = Bounds(_idx, which)
    if not (x and bx) then return end
    local gl, gt, gr, gb = Gaps()
    local cH = (gl == gr) and COL_EVEN or COL_ODD
    local cV = (gt == gb) and COL_EVEN or COL_ODD
    local x1, y1, bx1, by1 = x + w, y + h, bx + bw, by + bh
    HLine(1, bx, x, y, cH);   VLine(2, x, by, y, cV)      -- top left
    HLine(3, x1, bx1, y, cH); VLine(4, x1, by, y, cV)     -- top right
    HLine(5, bx, x, y1, cH);  VLine(6, x, y1, by1, cV)    -- bottom left
    HLine(7, x1, bx1, y1, cH); VLine(8, x1, y1, by1, cV)  -- bottom right
    local function Label(key, text, col, px, py, point)
        local fs = g.labels[key]
        if not fs then
            fs = g:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            g.labels[key] = fs
        end
        local ax, ay = ToArea(px, py)
        fs:ClearAllPoints()
        fs:SetPoint(point, _sh.area, "TOPLEFT", ax, ay)
        fs:SetText(text)
        fs:SetTextColor(col[1], col[2], col[3], 1)
        fs:Show()
    end
    Label("l", "L " .. gl, cH, (bx + x) / 2, y, "BOTTOM")
    Label("t", "T " .. gt, cV, x, (by + y) / 2, "RIGHT")
    Label("r", "R " .. gr, cH, (x1 + bx1) / 2, y1, "TOP")
    Label("b", "B " .. gb, cV, x1, (y1 + by1) / 2, "LEFT")
end

local function Place(o, x, y, w, h)
    local v = _sh._view
    local ax, ay = ToArea(x, y)
    o:ClearAllPoints()
    o:SetPoint("TOPLEFT", _sh.area, "TOPLEFT", ax - 1, ay + 1)
    o:SetSize(math.max(3, w * v.s + 2), math.max(3, h * v.s + 2))
    o:Show()
end

-- Wheel zoom and right-drag pan on the sheet (session only): the file-pixel
-- rect the whole area shows, with the area's aspect, for the file at idx.
-- nil = the fitted view (ViewRect). A new file drops it.
local _mview

local function ManualView()
    return _mview and _mview.idx == _idx and _mview or nil
end

-- The file-pixel rect the whole area shows now, margins included
local function ShownRect()
    local v = _sh._view
    local AW, AH = _sh.area:GetSize()
    return v.vx - v.ox / v.s, v.vy - v.oy / v.s, AW / v.s, AH / v.s
end

local LayoutSheet

-- Wheel over the sheet: zoom around the pointer. Out past the fitted view
-- goes back to it; in stops at about 64 screen px per file pixel.
local function ZoomAt(delta)
    local v = _sh and _sh._view
    if not v then return end
    local AW = _sh.area:GetWidth()
    local sc = _sh.area:GetEffectiveScale()
    local mx, my = GetCursorPosition()
    local x, y, w = ShownRect()
    local px = x + (mx / sc - _sh.area:GetLeft()) / v.s
    local py = y + (_sh.area:GetTop() - my / sc) / v.s
    local k = delta > 0 and 0.8 or 1.25
    local nw = math.max(AW / 64, w * k)
    if AW / nw <= (_sh._fitS or 0) then
        _mview = nil
    else
        local f = nw / w
        _mview = { idx = _idx, x = px - (px - x) * f, y = py - (py - y) * f, w = nw }
    end
    LayoutSheet()
end

-- Pointer in area units: x right, y down from the area's TOPLEFT
local function PointerArea()
    local sc = _sh.area:GetEffectiveScale()
    local mx, my = GetCursorPosition()
    return mx / sc - _sh.area:GetLeft(), _sh.area:GetTop() - my / sc
end

-- The file pixel under the pointer as a float, not clamped to the file
local function PointerFile()
    local v = _sh._view
    local ax, ay = PointerArea()
    return v.vx + (ax - v.ox) / v.s, v.vy + (ay - v.oy) / v.s
end

-- The saved box edge(s) under the pointer, active box first: which, and
-- { l, r, t, b } (a corner sets two). Within EDGE_TOL area units.
local EDGE_TOL = 5
local function EdgeAt()
    local v = _sh and _sh._view
    if not (v and _sh.area:IsMouseOver()) then return nil end
    local ax, ay = PointerArea()
    local first = Active()
    for _, which in ipairs({ first, first == "hole" and "area" or "hole" }) do
        local x, y, w, h = Box(_idx, which)
        if x then
            local l, t = v.ox + (x - v.vx) * v.s, v.oy + (y - v.vy) * v.s
            local r, b = l + w * v.s, t + h * v.s
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

-- One line per file pixel over the shown picture, from 4 screen px per file
-- pixel up (below that it is a grey wash); every 8th line stronger
local function LayoutGrid()
    local g = _sh.grid
    for _, t in ipairs(g.lines) do t:Hide() end
    local v = _sh._view
    if not (Store().grid and v and v.s >= 4) then return end
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
            t:SetPoint("TOPLEFT", _sh.area, "TOPLEFT", pos, -v.oy)
            t:SetSize(1, v.vh * v.s)
        else
            t:SetPoint("TOPLEFT", _sh.area, "TOPLEFT", v.ox, -pos)
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

-- A picture Bg (b.atlas) behind the whole window f, on f.pic. Cover fit
-- inside the atlas region: fills the window at the art's aspect, the side
-- that overflows is cropped evenly at both ends. True when it drew one, so
-- the caller clears its colour base.
local function DrawPictureBg(f, b)
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

function LayoutSheet()
    if not (_sh and _sh:IsShown() and LIST[_idx]) then return end
    local e = LIST[_idx]
    local area, tex = _sh.area, _sh.tex
    local b = SHEET_BGS[Store().bg or 1] or SHEET_BGS[1]
    _sh.base:SetColorTexture(b[1], b[2], b[3], DrawPictureBg(_sh, b) and 0 or 1)
    _sh.title:SetText(e.atlas or e.key)

    local AW, AH = area:GetSize()
    local W, H = NativeSize(_idx)
    for _, o in ipairs(_sh.pool) do o:Hide() end
    _sh.crop:Hide(); _sh.hole:Hide(); _sh.hover:Hide()
    for _, t in ipairs(_sh.guides.lines) do t:Hide() end
    for _, fs in pairs(_sh.guides.labels) do fs:Hide() end
    _sh.guides.crossH:Hide(); _sh.guides.crossV:Hide()
    for _, t in ipairs(_sh.grid.lines) do t:Hide() end
    if not (AW > 1 and AH > 1) then return end
    if not (W and H and W > 0 and H > 0) then
        tex:Hide()
        _sh.warn:SetText(_sizes[e.id] == false and "Texture did not load on this client"
            or "Loading...")
        _sh.warn:Show()
        return
    end
    _sh.warn:Hide()

    local vx, vy, vw, vh = ViewRect(W, H)
    local s = math.min(AW / vw, AH / vh)
    local dw, dh = vw * s, vh * s
    local ox, oy = (AW - dw) / 2, (AH - dh) / 2
    _sh._fitS = s
    local mv = ManualView()
    if mv then
        -- The area's aspect; the view's centre kept on the file, so some of
        -- it always shows
        s = AW / mv.w
        local mh = AH / s
        mv.x = math.max(-mv.w / 2, math.min(W - mv.w / 2, mv.x))
        mv.y = math.max(-mh / 2, math.min(H - mh / 2, mv.y))
        vx, vy = math.max(0, mv.x), math.max(0, mv.y)
        vw, vh = math.min(W, mv.x + mv.w) - vx, math.min(H, mv.y + mh) - vy
        dw, dh = vw * s, vh * s
        ox, oy = (vx - mv.x) * s, (vy - mv.y) * s
    end
    _sh._view = { vx = vx, vy = vy, vw = vw, vh = vh, s = s, ox = ox, oy = oy, W = W, H = H }

    tex:SetTexture(e.id)
    tex:SetTexCoord(vx / W, (vx + vw) / W, vy / H, (vy + vh) / H)
    tex:ClearAllPoints()
    tex:SetPoint("TOPLEFT", area, "TOPLEFT", ox, -oy)
    tex:SetSize(dw, dh)
    tex:Show()

    local n = 0
    for _, reg in ipairs(REGIONS[e.id] or {}) do
        local x, y, w, h = RegionRect(e.id, reg, W, H)
        if x then
            if reg[1] == _hoverRegion then
                Place(_sh.hover, x, y, w, h)
            elseif Store().showRegions ~= false then
                n = n + 1
                local o = _sh.pool[n]
                if not o then
                    o = Outline(area, COL_REG)
                    _sh.pool[n] = o
                end
                Place(o, x, y, w, h)
            end
        end
    end
    local active = Active()
    local cx, cy, cw, ch = Box(_idx, "area")
    if cx then Place(_sh.crop, cx, cy, cw, ch) end
    local hx, hy, hw, hh = Box(_idx, "hole")
    if hx then Place(_sh.hole, hx, hy, hw, hh) end
    _sh.crop:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = active == "area" and 2 or 1 })
    _sh.crop:SetBackdropBorderColor(unpack(COL_CROP))
    _sh.hole:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = active == "hole" and 2 or 1 })
    _sh.hole:SetBackdropBorderColor(unpack(COL_HOLE))
    local lv = area:GetFrameLevel()
    _sh.crop:SetFrameLevel(lv + 20)
    _sh.hole:SetFrameLevel(lv + 21)
    _sh.hover:SetFrameLevel(lv + 22)
    _sh.guides:SetFrameLevel(lv + 23)
    _sh.grid:SetFrameLevel(lv + 10)
    LayoutGrid()
    LayoutGuides()
    LayoutCross()
    _sh.gridBtn:SetText(Store().grid and "Grid on" or "Grid off")

    _sh.zoomBtn:SetText(ManualView() and "Reset view"
        or Store().zoom and "Whole file" or "Zoom to box")
    _sh.regBtn:SetText(Store().showRegions ~= false and "Hide regions" or "Show regions")
    _sh.guideBtn:SetText(GuidesOn() and "Guides on" or "Guides off")
    K.PutRing(_sh.boxRing, active == "hole" and _sh.holeBtn or _sh.areaBtn)
    local x, y, w, h = ToolBox(_idx, active)
    _sh.sizeText:SetText(x and string.format("%d x %d", w, h) or "-")
end

-- The file pixel under the pointer, or nil when it is off the sheet
-- (clamped to the file instead when clamp is set, for dragging)
local function PointerPixel(clamp)
    local v = _sh and _sh._view
    if not (v and _sh.tex:IsShown()) then return nil end
    if not clamp and not _sh.tex:IsMouseOver() then return nil end
    local sc = _sh.area:GetEffectiveScale()
    local mx, my = GetCursorPosition()
    mx, my = mx / sc, my / sc
    local px = v.vx + (mx - _sh.tex:GetLeft()) / v.s
    local py = v.vy + (_sh.tex:GetTop() - my) / v.s
    if clamp then
        px, py = math.max(0, math.min(v.W, px)), math.max(0, math.min(v.H, py))
    end
    return math.floor(px + (clamp and 0.5 or 0)), math.floor(py + (clamp and 0.5 or 0))
end

-- The smallest region of the current file under the pointer
local function RegionAt(px, py)
    local e = LIST[_idx]
    local W, H = NativeSize(_idx)
    local best, bestA
    for _, reg in ipairs(REGIONS[e.id] or {}) do
        local x, y, w, h = RegionRect(e.id, reg, W, H)
        if x and px >= x and px < x + w and py >= y and py < y + h and (not bestA or w * h < bestA) then
            best, bestA = reg, w * h
        end
    end
    return best
end

local function PickRegion(name)
    local e = LIST[_idx]
    local i = AddCustom(e.id, FilePath(e.id), name)
    if i then Go(i) end
end

-- ── Box tools (sheet) ────────────────────────────────────────────────────────
local function Changed()
    Refresh()
end

-- Every side in by d (out when negative); the centre stays put
-- Width and height by d (1 px steps), the centre kept. On the picture area
-- (whole pixels) the extra pixel goes to alternate sides.
local function Resize(d)
    local which = Active()
    local x, y, w, h = ToolBox(_idx, which)
    if not x or w + d < 1 or h + d < 1 then return end
    local nx, ny = x + w / 2 - (w + d) / 2, y + h / 2 - (h + d) / 2
    if which == "area" then nx, ny = math.floor(nx), math.floor(ny) end
    SetBox(_idx, which, nx, ny, w + d, h + d)
    Changed()
end

-- Equal gaps left/right and top/bottom inside the bounds, size kept
local function Centre()
    local which = Active()
    local x, y, w, h = ToolBox(_idx, which)
    local bx, by, bw, bh = Bounds(_idx, which)
    if not (x and bx) then return end
    local nx, ny = bx + (bw - w) / 2, by + (bh - h) / 2
    if which == "area" then nx, ny = math.floor(nx), math.floor(ny) end
    SetBox(_idx, which, nx, ny, w, h)
    Changed()
end

local function Nudge(dx, dy, dw, dh)
    local which = Active()
    local x, y, w, h = ToolBox(_idx, which)
    if not x or w + dw < 1 or h + dh < 1 then return end
    SetBox(_idx, which, x + dx, y + dy, w + dw, h + dh)
    Changed()
end

-- Arrows move the active box 1 px (Shift 10); Ctrl+arrows move its right or
-- bottom edge. Only while the pointer is over the sheet, and never in combat
-- (SetPropagateKeyboardInput is blocked there).
local ARROWS = { LEFT = { -1, 0 }, RIGHT = { 1, 0 }, UP = { 0, -1 }, DOWN = { 0, 1 } }
local function OnSheetKey(self, key)
    if InCombatLockdown() then return end
    local a = ARROWS[key]
    if not a then self:SetPropagateKeyboardInput(true); return end
    self:SetPropagateKeyboardInput(false)
    local step = IsShiftKeyDown() and 10 or 1
    if IsControlKeyDown() then Nudge(0, 0, a[1] * step, a[2] * step)
    else Nudge(a[1] * step, a[2] * step, 0, 0) end
end

local function BuildSheet()
    local f = BNB.CreateBackdropFrame("Frame", "BigNoteBoxIconLabSheet", UIParent)
    f:SetSize(560, 560)
    f:SetFrameStrata("MEDIUM")
    f:SetClampedToScreen(true)
    f:SetMovable(true); f:SetResizable(true)
    f:SetResizeBounds(470, 260, 1800, 1200)
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

    -- Top bar: view
    f.bgBtn = K.SmallBtn(f, "Bg", 40, function()
        local s = Store(); s.bg = ((s.bg or 1) % #SHEET_BGS) + 1; LayoutSheet(); LayoutPreview()
    end)
    f.bgBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -8, -6)
    f.regBtn = K.SmallBtn(f, "Hide regions", 110, function()
        -- nil = shown, false = hidden. Not `x and nil or false`: always false
        local s = Store()
        if s.showRegions == false then s.showRegions = nil else s.showRegions = false end
        LayoutSheet()
    end)
    f.regBtn:SetPoint("RIGHT", f.bgBtn, "LEFT", -6, 0)
    f.zoomBtn = K.SmallBtn(f, "Zoom to box", 110, function()
        if ManualView() then _mview = nil
        else local s = Store(); s.zoom = not s.zoom or nil end
        LayoutSheet()
    end)
    f.zoomBtn:SetPoint("RIGHT", f.regBtn, "LEFT", -6, 0)
    f.gridBtn = K.SmallBtn(f, "Grid off", 70, function()
        local s = Store(); s.grid = not s.grid or nil; LayoutSheet()
    end)
    f.gridBtn:SetPoint("RIGHT", f.zoomBtn, "LEFT", -6, 0)

    -- Bottom bar: box tools
    local function SetActive(which)
        Store().active = (which == "hole") and "hole" or nil
        Refresh()
    end
    f.areaBtn = K.SmallBtn(f, "Area", 50, function() SetActive("area") end)
    f.areaBtn:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 10, 26)
    f.holeBtn = K.SmallBtn(f, "Hole", 50, function() SetActive("hole") end)
    f.holeBtn:SetPoint("LEFT", f.areaBtn, "RIGHT", 6, 0)
    f.boxRing = K.Ring(f)
    local shrink = K.SmallBtn(f, "-", 26, function() Resize(IsShiftKeyDown() and -10 or -1) end)
    shrink:SetPoint("LEFT", f.holeBtn, "RIGHT", 14, 0)
    f.sizeText = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    f.sizeText:SetPoint("LEFT", shrink, "RIGHT", 4, 0)
    f.sizeText:SetWidth(84)
    local grow = K.SmallBtn(f, "+", 26, function() Resize(IsShiftKeyDown() and 10 or 1) end)
    grow:SetPoint("LEFT", f.sizeText, "RIGHT", 4, 0)
    local centre = K.SmallBtn(f, "Centre", 64, Centre)
    centre:SetPoint("LEFT", grow, "RIGHT", 10, 0)
    f.guideBtn = K.SmallBtn(f, "Guides on", 84, function()
        Store().guides = not GuidesOn()
        LayoutSheet()
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
    f.crop  = Outline(area, COL_CROP)
    f.hole  = Outline(area, COL_HOLE)
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

    -- Left-drag draws the active box; a click without a drag picks the
    -- region under the pointer
    local drag, last, pan
    area:SetScript("OnUpdate", function()
        if pan then
            if not IsMouseButtonDown(pan.btn) then pan = nil; return end
            local sx, sy = GetCursorPosition()
            local k = area:GetEffectiveScale() * pan.s
            _mview = { idx = _idx, w = pan.w,
                       x = pan.x - (sx - pan.sx) / k, y = pan.y + (sy - pan.sy) / k }
            LayoutSheet()
            return
        end
        if drag then
            if not IsMouseButtonDown("LeftButton") then drag = nil; f.draw:Hide(); return end
            if drag.edge then
                -- Dragging a box edge: whole pixels, never past the opposite
                -- edge; saved on release like a drawn box
                local fx, fy = PointerFile()
                local x, y, w, h = unpack(drag.box)
                local r, b = x + w, y + h
                local e = drag.edge
                local function R(n) return math.floor(n + 0.5) end
                if e.l then x = math.min(R(fx), r - 1) end
                if e.r then r = math.max(R(fx), x + 1) end
                if e.t then y = math.min(R(fy), b - 1) end
                if e.b then b = math.max(R(fy), y + 1) end
                drag.rect = { x, y, r - x, b - y }
                Place(f.draw, x, y, r - x, b - y)
                f.coords:SetText(string.format("%s  x %g  y %g   %g x %g",
                    drag.which, x, y, r - x, b - y))
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
            -- Only a white outline while drawing: the box is saved on release,
            -- so the zoom and the preview do not chase a half-drawn box
            drag.rect = (w >= 1 and h >= 1) and { x0, y0, w, h } or nil
            if drag.rect then Place(f.draw, x0, y0, w, h) else f.draw:Hide() end
            f.coords:SetText(string.format("x %d  y %d   drawing %d x %d", px, py, w, h))
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
        if key == last then return end
        last = key
        f.coords:SetText(px and string.format("x %d  y %d%s", px, py,
            reg and ("   |cff59d9ff" .. reg[1] .. "|r (click to pick)") or "") or
            "Drag: draw the box   Drag an edge: resize   Wheel: zoom   Right-drag: pan   Arrows: move 1 (Shift 10)   Ctrl+arrows: resize")
        local name = reg and reg[1] or nil
        if name ~= _hoverRegion then _hoverRegion = name; LayoutSheet() end
    end)
    area:EnableMouse(true)
    area:EnableMouseWheel(true)
    area:SetScript("OnMouseWheel", function(_, delta) ZoomAt(delta) end)
    area:SetScript("OnMouseDown", function(_, btn)
        if (btn == "RightButton" or btn == "MiddleButton") and _sh._view and not drag then
            local x, y, w = ShownRect()
            local sx, sy = GetCursorPosition()
            pan = { btn = btn, sx = sx, sy = sy, x = x, y = y, w = w, s = _sh._view.s }
            return
        end
        if btn ~= "LeftButton" then return end
        local which, edges = EdgeAt()
        if which then
            drag = { edge = edges, which = which, box = { Box(_idx, which) } }
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
        drag, last = nil, nil
        f.draw:Hide()
        if d.edge then
            if d.rect then
                Store().active = (d.which == "hole") and "hole" or nil
                SetBox(_idx, d.which, unpack(d.rect))
                Refresh()
            end
            return
        end
        if d.moved then
            if d.rect then SetBox(_idx, Active(), unpack(d.rect)); Refresh() end
            return
        end
        local px, py = PointerPixel()
        local reg = px and RegionAt(px, py)
        if reg then PickRegion(reg[1]) end
    end)
    pcall(area.SetPropagateKeyboardInput, area, true)
    area:SetScript("OnKeyDown", OnSheetKey)
    area:SetScript("OnEnter", function(self)
        if not InCombatLockdown() then self:EnableKeyboard(true) end
    end)
    area:SetScript("OnLeave", function(self)
        if not InCombatLockdown() then self:EnableKeyboard(false) end
        if f._edgeCursor then f._edgeCursor = nil; BNB.ClearCursor() end
        if _hoverRegion then _hoverRegion = nil; LayoutSheet() end
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
        local s = Store(); s.sw, s.sh = f:GetSize()
    end)

    f:SetScript("OnSizeChanged", LayoutSheet)
    f:HookScript("OnShow", LayoutSheet)
    local s = Store()
    if s.sw and s.sh then f:SetSize(s.sw, s.sh) end
    f:Hide()
    return f
end

-- ── Preview window ───────────────────────────────────────────────────────────
-- The frame around real icons at every size note icons are drawn at, then a
-- mock note list and a mock sticky, all through UI/IconFrameLayer.lua (what
-- ALL-127 draws on notes). Opens right of the control window and follows
-- every change live.
local PV_W       = 560    -- fixed preview width (height: PV_H)
local PV_H       = 600
local ROW_ICON   = 32     -- NoteList ICON_SIZE_NORMAL
local ROW_H      = 44
local STICKY_ICON = 36    -- StickyNote ICON_SZ, inset 6
local MOCK_W     = 280    -- mock note list and sticky width
local CELL_MAX   = 120    -- largest size strip cell

-- A strip cell's fixed size for an icon size: room for a frame about twice
-- the icon, up to CELL_MAX
local function CellSize(S) return math.min(CELL_MAX, math.max(44, math.floor(S * 2.4))) end
local MOCK_NOTES = {
    { "Molten Core tactics",  "Tank swap on Magmadar, decurse on Lucifron" },
    { "Auction house flips",  "Buy under 40g, list at 55g on Tuesdays" },
    { "Guild raid Tuesday",   "Bring flasks, food and the new trinket" },
}

local _icons = {}
local function ShuffleIcons()
    for n = 1, #PREVIEW_SIZES + #MOCK_NOTES + 1 do
        _icons[n] = "Interface\\Icons\\" .. SAMPLE_ICONS[math.random(#SAMPLE_ICONS)]
    end
end

-- An icon with its frame texture. The textures sit on an inner frame (the
-- circle mask is made on the icon's parent) so a clipping slot can cut an
-- oversized frame at its own edge; the mock rows and sticky do not clip,
-- as a real note list would not.
local function IconSlot(parent, clip)
    local c = CreateFrame("Frame", nil, parent)
    if clip then c:SetClipsChildren(true) end
    local inner = CreateFrame("Frame", nil, c)
    inner:SetAllPoints()
    c.icon = inner:CreateTexture(nil, "ARTWORK")
    c.frame = inner:CreateTexture(nil, "OVERLAY")
    return c
end

local function DrawSlot(c, S, iconPath, def, st)
    c.icon:SetSize(S, S)
    c.icon:SetTexture(iconPath)
    c.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)   -- as the note list draws icons
    IFL.Apply(c.icon, c.frame, def, S, st.tint and 0.6 or 1)
end

LayoutPreview = function()
    if not (_pv and _pv:IsShown() and LIST[_idx]) then return end
    local st = State(_idx)
    local def, standIn = FrameDef(_idx)
    local b = SHEET_BGS[Store().bg or 1] or SHEET_BGS[1]
    _pv.base:SetColorTexture(b[1], b[2], b[3], DrawPictureBg(_pv, b) and 0 or 1)
    _pv.title:SetText((st.name and st.name ~= "") and st.name or (LIST[_idx].atlas or LIST[_idx].key))
    if not def then
        _pv.warn:SetText("Waiting for the file size...")
        _pv.warn:Show()
    elseif standIn then
        _pv.warn:SetText("No hole set: a guess stands in. Hole, then fit the green box to the inside of the ring")
        _pv.warn:Show()
    else
        _pv.warn:Hide()
    end

    -- Size strip
    -- Fixed layout: the window keeps its size whatever the frame does. Each
    -- strip cell has a fixed size for its icon and clips a bigger frame.
    local W = PV_W
    local y = -52
    local total = -6
    for _, sz in ipairs(PREVIEW_SIZES) do total = total + CellSize(sz[1]) + 6 end
    local x = math.floor((W - total) / 2)
    for n, sz in ipairs(PREVIEW_SIZES) do
        local S = sz[1]
        local c = _pv.cells[n]
        local cs = CellSize(S)
        c:ClearAllPoints()
        c:SetPoint("TOPLEFT", _pv, "TOPLEFT", x, y - math.floor((CELL_MAX - cs) / 2))
        c:SetSize(cs, cs)
        c.icon:ClearAllPoints()
        c.icon:SetPoint("CENTER")
        DrawSlot(c, S, _icons[n], def, st)
        c.label:SetText(sz[2])
        x = x + cs + 6
    end
    y = y - CELL_MAX - 22

    -- Mock note list and sticky, centred
    local mx = math.floor((W - MOCK_W) / 2)
    _pv.listHdr:ClearAllPoints()
    _pv.listHdr:SetPoint("TOPLEFT", _pv, "TOPLEFT", mx, y)
    y = y - 16
    for n, row in ipairs(_pv.rows) do
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", _pv, "TOPLEFT", mx, y)
        row:SetSize(MOCK_W, ROW_H)
        DrawSlot(row.slot, ROW_ICON, _icons[#PREVIEW_SIZES + n], def, st)
        y = y - ROW_H - 2
    end
    y = y - 12

    _pv.stickyHdr:ClearAllPoints()
    _pv.stickyHdr:SetPoint("TOPLEFT", _pv, "TOPLEFT", mx, y)
    y = y - 16
    local sk = _pv.sticky
    sk:ClearAllPoints()
    sk:SetPoint("TOPLEFT", _pv, "TOPLEFT", mx, y)
    sk:SetSize(MOCK_W, 150)
    DrawSlot(sk.slot, STICKY_ICON, _icons[#PREVIEW_SIZES + #MOCK_NOTES + 1], def, st)

    K.PutRing(_pv.shapeRing, st.shape == "circle" and _pv.circleBtn or _pv.squareBtn)
    K.PutRing(_pv.layerRing, st.layer == "under" and _pv.underBtn or _pv.overBtn)
    _pv.tint:SetChecked(st.tint == true)
    _pv.scaleText:SetText(string.format("%d %%", math.floor((st.scale or 1) * 100 + 0.5)))
end

local function BuildPreview()
    local f = BNB.CreateBackdropFrame("Frame", "BigNoteBoxIconLabPreview", UIParent)
    f:SetSize(PV_W, PV_H)
    f:SetClipsChildren(true)
    f:SetFrameStrata("MEDIUM")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
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

    -- Background band (Bg colour) under everything; content sits on frames
    -- above it, so nothing is hidden behind its texture
    local band = CreateFrame("Frame", nil, f)
    band:SetPoint("TOPLEFT", f, "TOPLEFT", 4, -4)
    band:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -4, 60)
    band:SetFrameLevel(f:GetFrameLevel() + 1)
    f.base = band:CreateTexture(nil, "BACKGROUND")
    f.base:SetAllPoints()
    f.pic = f:CreateTexture(nil, "BACKGROUND", nil, 7)   -- picture Bg, the whole window
    f.pic:SetPoint("TOPLEFT", 4, -4)
    f.pic:SetPoint("BOTTOMRIGHT", -4, 4)
    f.pic:Hide()
    local top = CreateFrame("Frame", nil, f)
    top:SetAllPoints()
    top:SetFrameLevel(f:GetFrameLevel() + 5)

    f.title = top:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.title:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -9)
    f.title:SetPoint("RIGHT", f, "RIGHT", -110, 0)
    f.title:SetJustifyH("LEFT")
    local newIcons = K.SmallBtn(top, "New icons", 90, function() ShuffleIcons(); LayoutPreview() end)
    newIcons:SetPoint("TOPRIGHT", f, "TOPRIGHT", -8, -6)
    f.warn = top:CreateFontString(nil, "OVERLAY", "GameFontRedSmall")
    f.warn:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -30)
    f.warn:SetPoint("RIGHT", f, "RIGHT", -10, 0)
    f.warn:SetJustifyH("LEFT")

    f.cells = {}
    for n = 1, #PREVIEW_SIZES do
        local c = IconSlot(top, true)
        c.label = c:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        c.label:SetPoint("TOP", c, "BOTTOM", 0, -2)
        f.cells[n] = c
    end

    -- Mock note list rows: icon, title, preview line (NoteList look)
    f.listHdr = top:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.listHdr:SetText("Note list")
    f.rows = {}
    for n, note in ipairs(MOCK_NOTES) do
        local row = BNB.CreateBackdropFrame("Frame", nil, top)
        BNB.SetBackdropDark(row)
        row.slot = IconSlot(row)
        row.slot:SetAllPoints()
        row.slot.icon:SetPoint("LEFT", row, "LEFT", 6, 0)
        local t = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        t:SetPoint("TOPLEFT", row, "TOPLEFT", 6 + ROW_ICON + 8, -7)
        t:SetPoint("RIGHT", row, "RIGHT", -6, 0)
        t:SetJustifyH("LEFT"); t:SetText(note[1])
        local p = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        p:SetPoint("TOPLEFT", t, "BOTTOMLEFT", 0, -3)
        p:SetPoint("RIGHT", row, "RIGHT", -6, 0)
        p:SetJustifyH("LEFT"); p:SetWordWrap(false); p:SetText(note[2])
        row.slot:SetFrameLevel(row:GetFrameLevel() + 2)
        f.rows[n] = row
    end

    -- Mock sticky: border, icon badge top left, title, body
    f.stickyHdr = top:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.stickyHdr:SetText("Sticky note")
    local sk = BNB.CreateBackdropFrame("Frame", nil, top)
    sk:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 14,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    sk:SetBackdropColor(0.07, 0.07, 0.09, 0.97)
    sk:SetBackdropBorderColor(0.7, 0.7, 0.75, 1)
    sk.slot = IconSlot(sk)
    sk.slot:SetAllPoints()
    sk.slot:SetFrameLevel(sk:GetFrameLevel() + 2)
    sk.slot.icon:SetPoint("TOPLEFT", sk, "TOPLEFT", 6, -6)
    local st = sk:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    st:SetPoint("TOPLEFT", sk, "TOPLEFT", 6 + STICKY_ICON + 8, -16)
    st:SetPoint("RIGHT", sk, "RIGHT", -10, 0)
    st:SetJustifyH("LEFT"); st:SetText(MOCK_NOTES[1][1])
    local body = sk:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    body:SetPoint("TOPLEFT", sk, "TOPLEFT", 10, -6 - STICKY_ICON - 10)
    body:SetPoint("BOTTOMRIGHT", sk, "BOTTOMRIGHT", -10, 8)
    body:SetJustifyH("LEFT"); body:SetJustifyV("TOP"); body:SetWordWrap(true)
    body:SetText(L["DEV_WIN_BGLAB_SAMPLE"])
    f.sticky = sk

    -- Frame options for the entry
    local function Set(field, v) State(_idx)[field] = v; LayoutPreview() end
    f.squareBtn = K.SmallBtn(top, "Square", 62, function() Set("shape", nil) end)
    f.squareBtn:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 8, 34)

    -- Frame size on top of the hole (5 %, Shift 25 %); the only size control
    -- for art with no real hole, such as corner ornaments
    local function Scale(d)
        local st = State(_idx)
        local v = math.max(0.1, math.min(5, (st.scale or 1) + d))
        v = math.floor(v * 100 + 0.5) / 100
        st.scale = (v ~= 1) and v or nil
        LayoutPreview()
    end
    local sLbl = top:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    sLbl:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 10, 13)
    sLbl:SetText("Frame size")
    local sMinus = K.SmallBtn(top, "-", 26, function() Scale(IsShiftKeyDown() and -0.25 or -0.05) end)
    sMinus:SetPoint("LEFT", sLbl, "RIGHT", 8, 0)
    f.scaleText = top:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    f.scaleText:SetPoint("LEFT", sMinus, "RIGHT", 4, 0)
    f.scaleText:SetWidth(52)
    local sPlus = K.SmallBtn(top, "+", 26, function() Scale(IsShiftKeyDown() and 0.25 or 0.05) end)
    sPlus:SetPoint("LEFT", f.scaleText, "RIGHT", 4, 0)
    local s100 = K.SmallBtn(top, "100 %", 56, function() State(_idx).scale = nil; LayoutPreview() end)
    s100:SetPoint("LEFT", sPlus, "RIGHT", 8, 0)
    local sHint = top:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    sHint:SetPoint("LEFT", s100, "RIGHT", 8, 0)
    sHint:SetText("Shift: 25 %")
    f.circleBtn = K.SmallBtn(top, "Circle", 62, function() Set("shape", "circle") end)
    f.circleBtn:SetPoint("LEFT", f.squareBtn, "RIGHT", 4, 0)
    f.shapeRing = K.Ring(top)
    f.overBtn = K.SmallBtn(top, "Over", 56, function() Set("layer", nil) end)
    f.overBtn:SetPoint("LEFT", f.circleBtn, "RIGHT", 12, 0)
    f.underBtn = K.SmallBtn(top, "Under", 56, function() Set("layer", "under") end)
    f.underBtn:SetPoint("LEFT", f.overBtn, "RIGHT", 4, 0)
    f.layerRing = K.Ring(top)
    local tint = CreateFrame("CheckButton", nil, top, "UICheckButtonTemplate")
    tint:SetSize(24, 24)
    tint:SetPoint("LEFT", f.underBtn, "RIGHT", 8, 0)
    tint.text = tint.text or tint:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    tint.text:SetPoint("LEFT", tint, "RIGHT", 2, 0)
    tint.text:SetFontObject("GameFontHighlightSmall")
    tint.text:SetText("Tint")
    tint:SetScript("OnClick", function(self) Set("tint", self:GetChecked() or nil) end)
    tint:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Tint", 1, 1, 1)
        GameTooltip:AddLine("The note's border brightness applies to this frame. Previewed at 60 %.", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    tint:SetScript("OnLeave", function() GameTooltip:Hide() end)
    f.tint = tint
    for _, bt in ipairs({ { f.overBtn, "Frame drawn over the icon" }, { f.underBtn, "Frame drawn under the icon" } }) do
        bt[1]:HookScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:AddLine(bt[2], 1, 1, 1)
            GameTooltip:Show()
        end)
        bt[1]:HookScript("OnLeave", function() GameTooltip:Hide() end)
    end

    ShuffleIcons()
    f:HookScript("OnShow", LayoutPreview)
    f:Hide()
    return f
end

-- ── Export ───────────────────────────────────────────────────────────────────
local function Q(s) return string.format("%q", s) end

local function ExportText()
    local out, n, done, unnamed = {}, 0, 0, 0
    for i, e in ipairs(LIST) do
        local st = Store().e[e.key]
        if st and st.done then
            done = done + 1
        elseif st and not (st.name and st.name ~= "") then
            if next(st) then unnamed = unnamed + 1 end
        elseif st then
            n = n + 1
            local W, H = NativeSize(i)
            local cx, cy, cw, ch = Box(i, "area")
            local hx, hy, hw, hh = Box(i, "hole")
            out[#out + 1] = string.format(
                "{ key = %s, name = %s, file = %d, path = %s, w = %s, h = %s%s%s%s%s%s%s%s%s },",
                Q(e.key), Q(st.name or ""), e.id, Q(e.path ~= "" and e.path or FilePath(e.id)),
                tostring(W or "nil"), tostring(H or "nil"),
                e.atlas and (", atlas = " .. Q(e.atlas)) or "",
                cx and string.format(", crop = { %d, %d, %d, %d }", cx, cy, cw, ch) or "",
                hx and string.format(", hole = { %g, %g, %d, %d }", hx, hy, hw, hh) or "",
                st.shape and (", shape = " .. Q(st.shape)) or "",
                st.layer and (", layer = " .. Q(st.layer)) or "",
                st.tint and ", tint = true" or "",
                st.scale and string.format(", scale = %.2f", st.scale) or "",
                _sizes[e.id] == false and ", loaded = false" or "")
        end
    end
    table.insert(out, 1, string.format(
        "-- Icon Lab export: %d named of %d, left out: %d done, %d not named yet. Client %s",
        n, #LIST, done, unnamed, BNB.IsForever and "Forever" or "Retail"))
    return table.concat(out, "\n")
end

-- ── Control window ───────────────────────────────────────────────────────────
local REG_ROW_H = 16

Go = function(i)
    if #LIST == 0 then Refresh(); return end
    _idx = ((i - 1) % #LIST) + 1
    Store().idx = _idx
    if _ctl and _ctl.nameEb then _ctl.nameEb._pending = nil end   -- a new entry shows its saved name
    _hoverRegion = nil
    Refresh()
    local e = LIST[_idx]
    _prober:Probe(_ctl, e.id, function()
        RememberSize(e.id)
        if LIST[_idx] == e then ApplyAtlasCrop(_idx); Refresh() end
    end)
end

-- Measures every listed file with no saved size, one at a time, on its own
-- prober (the entry prober drops a probe when you move on)
local _bgProber = K.NewProber()
local function ProbeAllSizes()
    local queue, seen = {}, {}
    for _, e in ipairs(LIST) do
        if not seen[e.id] and type(FileSize(e.id)) ~= "table" then
            seen[e.id] = true
            queue[#queue + 1] = e.id
        end
    end
    local n = 0
    local function NextOne()
        n = n + 1
        local id = queue[n]
        if not id then return end
        _bgProber:Probe(_ctl, id, function()
            if _sizes[id] == nil then   -- a table, or false: did not load here
                _sizes[id] = _bgProber.sizes[id]
                RememberSize(id)
                if LIST[_idx] and LIST[_idx].id == id then Refresh() end
            end
            NextOne()
        end)
    end
    NextOne()
end

-- Adds every line of the paste box: listfile lines (path;fileID), bare file
-- IDs and atlas names. Returns how many were added and the last index.
local function AddLines(text)
    local added, bad, last = 0, 0, nil
    for line in (text or ""):gmatch("[^\r\n]+") do
        line = line:gsub("^%s+", ""):gsub("%s+$", "")
        if line ~= "" then
            local id, path = K.ParseListfileLine(line)
            local i
            if id then
                i = AddCustom(id, path)
            else
                local aid = not line:find("[/\\;]") and K.ResolveAtlas(line)
                if aid then i = AddCustom(aid, FilePath(aid), line) end
            end
            if i then added, last = added + 1, i else bad = bad + 1 end
        end
    end
    return added, bad, last
end

local function BuildControl()
    local f, exportBtn, closeBtn = BNB.CreateToolWindow({
        name = "BigNoteBoxIconLab", w = C_W, h = C_H,
        title = L["DEV_WIN_ICONLAB_TITLE"], pad = C_PAD, cw = C_W - C_PAD * 2, footH = 40,
        btn1 = L["DEV_WIN_BGLAB_EXPORT"], btn2 = L["CLOSE"],
        onClose = function() _ctl:Hide() end,
        toplevel = true, escClose = true,
    })
    f:SetPoint("CENTER", UIParent, "CENTER", 100, 0)   -- sheet to the left, preview to the right
    closeBtn:SetScript("OnClick", function() f:Hide() end)
    exportBtn:SetScript("OnClick", function() BNB.ShowClipboardHint(ExportText(), f, true) end)
    f:HookScript("OnHide", function()
        if _sh then _sh:Hide() end
        if _pv then _pv:Hide() end
    end)
    _ctl = f

    local cw = C_W - C_PAD * 2
    local body = CreateFrame("Frame", nil, f)
    body:SetPoint("TOPLEFT", f, "TOPLEFT", C_PAD, -34)
    body:SetSize(cw, C_H - 80)
    local y = 0

    -- Navigation: < jump list >
    -- < > step over done entries while Hide done is on
    local function Step(d)
        local i = _idx
        for _ = 1, #LIST do
            i = ((i + d - 1) % #LIST) + 1
            local st = Store().e[LIST[i].key]
            if not (Store().hideDone and st and st.done) then break end
        end
        Go(i)
    end
    local prev = K.SmallBtn(body, "<", 30, function() Step(-1) end)
    prev:SetPoint("TOPLEFT", body, "TOPLEFT", 0, y)
    -- Hide done: a list filter for < >, the dropdown, and every entry, so it
    -- sits on this row rather than beside the entry's own Done
    local hideCb = CreateFrame("CheckButton", nil, body, "UICheckButtonTemplate")
    hideCb:SetSize(24, 24)
    hideCb.text = hideCb.text or hideCb:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    hideCb.text:ClearAllPoints()
    hideCb.text:SetPoint("LEFT", hideCb, "RIGHT", 0, 0)
    hideCb.text:SetFontObject("GameFontHighlightSmall")
    hideCb.text:SetText(L["DEV_WIN_ICONLAB_HIDE_DONE"])
    hideCb:SetPoint("TOPLEFT", body, "TOPLEFT", cw - hideCb.text:GetStringWidth() - 22, y + 2)
    hideCb:SetScript("OnClick", function(self)
        Store().hideDone = self:GetChecked() or nil
    end)
    hideCb:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(L["DEV_WIN_ICONLAB_HIDE_DONE_TIP"], 1, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    hideCb:SetScript("OnLeave", function() GameTooltip:Hide() end)
    f.hideDoneCb = hideCb
    local nextB = K.SmallBtn(body, ">", 30, function() Step(1) end)
    nextB:SetPoint("TOPRIGHT", hideCb, "TOPLEFT", -4, -2)
    local dd = CreateFrame("DropdownButton", nil, body, "WowStyle1DropdownTemplate")
    dd:SetPoint("LEFT", prev, "RIGHT", 6, 0)
    dd:SetPoint("RIGHT", nextB, "LEFT", -6, 0)
    -- One section per file: the whole file first, then the regions picked
    -- from it (green = has a hole)
    dd:SetupMenu(function(_, root)
        pcall(function() root:SetScrollMode(500) end)
        local order, byFile = {}, {}
        for i, e in ipairs(LIST) do
            if not byFile[e.id] then byFile[e.id] = {}; order[#order + 1] = e.id end
            local l = byFile[e.id]
            if e.atlas or e.variant then l[#l + 1] = i else table.insert(l, 1, i) end
        end
        for n, id in ipairs(order) do
            if n > 1 then root:CreateDivider() end
            local path = FilePath(id)
            local title = path ~= "" and path:match("([^/]+)$"):gsub("%.[^.]+$", "") or ("file " .. id)
            root:CreateTitle(title)
            for _, i in ipairs(byFile[id]) do
                local e = LIST[i]
                local st = Store().e[e.key]
                local hidden = Store().hideDone and st and st.done and _idx ~= i
                local lbl = (st and st.name and st.name ~= "") and st.name
                    or ((e.atlas and ("  " .. e.atlas) or "  (whole file)") .. (e.variant and (" #" .. e.variant) or ""))
                if st and st.done then lbl = "|cff888888" .. lbl .. " (done)|r"
                elseif st and st.name and st.name ~= "" then lbl = "|cff66bb6a" .. lbl .. "|r" end
                if not hidden then
                    root:CreateRadio(lbl, function() return _idx == i end, function() Go(i) end)
                end
            end
        end
    end)
    f.dd = dd
    y = y - 28

    local info = body:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    info:SetPoint("TOPLEFT", body, "TOPLEFT", 0, y)
    info:SetWidth(cw); info:SetJustifyH("LEFT"); info:SetWordWrap(true)
    f.info = info
    y = y - 44

    -- Name
    BNB.CreateSmallLabel(body, L["DEV_WIN_ICONLAB_NAME"], y, cw)
    y = y - 14
    -- The name is saved only when accepted (Tab, Enter or OK). A named entry
    -- is green in the list and goes into Export; Esc puts the saved name
    -- back. Leaving the box keeps the typed text: clicking OK takes the
    -- focus away before its OnClick, and a revert there emptied the box.
    -- The next entry switch shows the saved name again.
    local nameHost = K.PlainBox(body, cw - 40, 22)
    nameHost:SetPoint("TOPLEFT", body, "TOPLEFT", 0, y)
    local nameEb = nameHost.eb
    nameEb:SetFontObject("GameFontHighlight")
    nameEb:SetMaxLetters(40)
    nameEb:SetScript("OnTextChanged", function(self, user)
        if user then self._pending = true end   -- typed, not accepted yet
    end)
    local function AcceptName()
        nameEb._pending = nil
        local v = nameEb:GetText():gsub("^%s+", ""):gsub("%s+$", "")
        State(_idx).name = (v ~= "") and v or nil
        nameEb:ClearFocus()
        Refresh()
    end
    nameEb:SetScript("OnEnterPressed", AcceptName)
    nameEb:SetScript("OnTabPressed", function() AcceptName(); Step(1) end)
    nameEb:SetScript("OnEscapePressed", function(self) self._pending = nil; self:ClearFocus(); Refresh() end)
    local okBtn = K.SmallBtn(body, "OK", 34, AcceptName)
    okBtn:SetPoint("LEFT", nameHost, "RIGHT", 6, 0)
    f.nameEb = nameEb
    y = y - 28

    -- Done: left out of Export (Hide done, on the navigation row, keeps it
    -- out of the dropdown and < >)
    local function Check(label, x, onClick)
        local cb = CreateFrame("CheckButton", nil, body, "UICheckButtonTemplate")
        cb:SetSize(24, 24)
        cb:SetPoint("TOPLEFT", body, "TOPLEFT", x - 4, y)
        cb.text = cb.text or cb:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        cb.text:SetPoint("LEFT", cb, "RIGHT", 2, 0)
        cb.text:SetFontObject("GameFontHighlightSmall")
        cb.text:SetText(label)
        cb:SetScript("OnClick", onClick)
        return cb
    end
    f.doneCb = Check(L["DEV_WIN_ICONLAB_DONE"], 0, function(self)
        State(_idx).done = self:GetChecked() or nil
        Refresh()
    end)
    y = y - 30

    -- Native size override
    BNB.CreateSmallLabel(body, L["DEV_WIN_BGLAB_SIZE"], y, cw)
    y = y - 16
    local wBox = K.NumBox(body, 70, function(v)
        State(_idx).w = (v and v > 0) and v or nil; Refresh()
    end, function() Refresh() end)
    wBox:SetPoint("TOPLEFT", body, "TOPLEFT", 0, y)
    local xLbl = body:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    xLbl:SetPoint("LEFT", wBox, "RIGHT", 6, 0); xLbl:SetText("x")
    local hBox = K.NumBox(body, 70, function(v)
        State(_idx).h = (v and v > 0) and v or nil; Refresh()
    end, function() Refresh() end)
    hBox:SetPoint("LEFT", xLbl, "RIGHT", 6, 0)
    f.wBox, f.hBox = wBox, hBox
    y = y - 30

    -- The active box (picture area or hole), exact numbers
    f.boxLbl = BNB.CreateSmallLabel(body, "", y, cw)
    y = y - 16
    f.boxBoxes = {}
    local last
    for n = 1, 4 do
        local box = K.NumBox(body, 50, function(v)
            if not v then return end   -- an empty box left alone sets nothing
            local which = Active()
            local x, yy, w, h = ToolBox(_idx, which)
            if not x then return end
            local vals = { x, yy, w, h }
            -- x/y of the hole may be negative (SetBox); the area's are kept in the file
            if n <= 2 or v > 0 then vals[n] = v end
            SetBox(_idx, which, vals[1], vals[2], vals[3], vals[4])
            Refresh()
        end, function() Refresh() end)
        if last then box:SetPoint("LEFT", last, "RIGHT", 5, 0)
        else box:SetPoint("TOPLEFT", body, "TOPLEFT", 0, y) end
        f.boxBoxes[n], last = box, box
    end
    K.TabChain({ wBox, hBox, f.boxBoxes[1], f.boxBoxes[2], f.boxBoxes[3], f.boxBoxes[4] })
    local clear = K.SmallBtn(body, L["DEV_WIN_BGLAB_RESET"], cw - 4 * 55 - 5, function()
        SetBox(_idx, Active(), nil)
        if Active() == "area" then ApplyAtlasCrop(_idx) end
        Refresh()
    end)
    clear:SetPoint("LEFT", last, "RIGHT", 5, 0)
    y = y - 24
    f.gaps = body:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.gaps:SetPoint("TOPLEFT", body, "TOPLEFT", 0, y)
    f.gaps:SetWidth(cw); f.gaps:SetJustifyH("LEFT")
    y = y - 22

    -- Regions of this file: hover outlines it on the sheet, click picks it
    f.regHdr = BNB.CreateSectionHeader(body, "", y, cw)
    y = y - 20
    local LIST_H = 160
    local sf, ct = BNB.CreateAutoScrollPanel(body, cw - 24, cw)
    sf:SetPoint("TOPLEFT", body, "TOPLEFT", 0, y)
    sf:SetSize(cw - 24, LIST_H)
    f.regSf, f.regCt, f.regRows = sf, ct, {}
    f.regEmpty = body:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    f.regEmpty:SetPoint("TOPLEFT", body, "TOPLEFT", 0, y)
    f.regEmpty:SetWidth(cw); f.regEmpty:SetJustifyH("LEFT")
    f.regEmpty:SetText(L["DEV_WIN_ICONLAB_NO_REGIONS"])
    y = y - LIST_H - 10

    -- Add: paste listfile lines, file IDs or atlas names, one per line
    BNB.CreateSectionHeader(body, L["DEV_WIN_BGLAB_ADD_HDR"], y, cw)
    local variantBtn = K.SmallBtn(body, L["DEV_WIN_ICONLAB_VARIANT"], 170, function()
        local i = NewVariant()
        if i then Go(i) end
    end)
    variantBtn:SetPoint("TOPRIGHT", body, "TOPRIGHT", 0, y + 2)
    variantBtn:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(L["DEV_WIN_ICONLAB_VARIANT"], 1, 1, 1)
        GameTooltip:AddLine(L["DEV_WIN_ICONLAB_VARIANT_TIP"], 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    variantBtn:HookScript("OnLeave", function() GameTooltip:Hide() end)
    y = y - 20
    local addHost = K.PlainBox(body, cw - 66, 44)
    addHost:SetPoint("TOPLEFT", body, "TOPLEFT", 0, y)
    local addEb = addHost.eb
    addEb:SetMultiLine(true)
    addEb:SetMaxLetters(0)
    addEb:SetTextInsets(6, 6, 4, 4)
    local hint
    local function DoAdd()
        local added, bad, i = AddLines(addEb:GetText())
        hint:SetText(string.format(L["DEV_WIN_ICONLAB_ADDED"], added, bad))
        if added > 0 then addEb:SetText("") end
        addEb:ClearFocus()
        if i then Go(i) end
    end
    local addBtn = K.SmallBtn(body, L["DEV_WIN_BGLAB_ADD"], 60, DoAdd)
    addBtn:SetPoint("TOPLEFT", addHost, "TOPRIGHT", 6, 0)
    hint = body:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("TOPLEFT", addHost, "BOTTOMLEFT", 0, -3)
    hint:SetWidth(cw); hint:SetJustifyH("LEFT")
    hint:SetText(L["DEV_WIN_ICONLAB_ADD_HINT"])
    y = y - 44 - 20

    local bw = math.floor((cw - 12) / 3)
    local removeBtn = K.SmallBtn(body, L["DEV_WIN_BGLAB_REMOVE"], bw, function()
        RemoveCustom(_idx)
        Go(math.min(_idx, math.max(1, #LIST)))
    end)
    removeBtn:SetPoint("TOPLEFT", body, "TOPLEFT", 0, y)
    f.removeBtn = removeBtn
    local sheetBtn = K.SmallBtn(body, L["DEV_WIN_ICONLAB_SHEET"], bw, function()
        if _sh:IsShown() then _sh:Hide() else _sh:Show() end
    end)
    sheetBtn:SetPoint("TOPLEFT", body, "TOPLEFT", bw + 6, y)
    local pvBtn = K.SmallBtn(body, L["DEV_WIN_ICONLAB_PREVIEW"], bw, function()
        if _pv:IsShown() then _pv:Hide() else _pv:Show() end
    end)
    pvBtn:SetPoint("TOPLEFT", body, "TOPLEFT", (bw + 6) * 2, y)
    return f
end

local function RegionRow(i)
    local rows = _ctl.regRows
    if rows[i] then return rows[i] end
    local r = CreateFrame("Button", nil, _ctl.regCt)
    r:SetHeight(REG_ROW_H)
    r:SetPoint("TOPLEFT", _ctl.regCt, "TOPLEFT", 0, -(i - 1) * REG_ROW_H)
    r:SetPoint("RIGHT", _ctl.regCt, "RIGHT", 0, 0)
    r.hl = r:CreateTexture(nil, "BACKGROUND")
    r.hl:SetAllPoints()
    r.hl:SetColorTexture(1, 0.82, 0, 0.18)
    r:SetHighlightTexture("Interface\\Buttons\\WHITE8x8")
    r:GetHighlightTexture():SetVertexColor(0.35, 0.85, 1, 0.15)
    r.text = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.text:SetPoint("LEFT", 4, 0)
    r.text:SetPoint("RIGHT", -60, 0)
    r.text:SetJustifyH("LEFT"); r.text:SetWordWrap(false)
    r.size = r:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    r.size:SetPoint("RIGHT", -4, 0)
    r:SetScript("OnEnter", function(self)
        _hoverRegion = self._name; LayoutSheet()
    end)
    r:SetScript("OnLeave", function()
        _hoverRegion = nil; LayoutSheet()
    end)
    r:SetScript("OnClick", function(self) PickRegion(self._name) end)
    rows[i] = r
    return r
end

local function RefreshRegions()
    local e = LIST[_idx]
    local regs = (e and REGIONS[e.id]) or {}
    local W, H = NativeSize(_idx)
    _ctl.regHdr:SetText(string.format(L["DEV_WIN_ICONLAB_REGIONS"], #regs))
    for i, reg in ipairs(regs) do
        local r = RegionRow(i)
        r._name = reg[1]
        local _, _, w, h, live = RegionRect(e.id, reg, W, H)
        r.text:SetText(live == false and ("|cff999999" .. reg[1] .. "|r") or reg[1])
        r.size:SetText(w and string.format("%dx%d", w, h) or string.format("%gx%g", reg[2], reg[3]))
        if e.atlas == reg[1] then r.hl:Show() else r.hl:Hide() end
        r:Show()
    end
    for i = #regs + 1, #_ctl.regRows do _ctl.regRows[i]:Hide() end
    if #regs == 0 then _ctl.regEmpty:Show() else _ctl.regEmpty:Hide() end
    _ctl.regSf:FinaliseHeight(#regs * REG_ROW_H)
end

Refresh = function()
    if not _ctl then return end
    local f = _ctl
    local e = LIST[_idx]
    if not e then
        f.info:SetText(L["DEV_WIN_ICONLAB_EMPTY"])
        pcall(function() f.dd:OverrideText("-") end)
        f.removeBtn:Hide()
        return
    end
    local st = State(_idx)
    local sz = FileSize(e.id)
    local W, H = NativeSize(_idx)
    local status = (sz == nil and "loading...") or (sz == false and "|cffff5555did not load|r")
        or string.format("%dx%d", sz[1], sz[2])
    local live = ""
    if e.atlas then
        local aid = K.ResolveAtlas(e.atlas)
        live = aid == e.id and "" or "  |cffff9900atlas not on this client|r"
    end
    f.info:SetText(string.format("%d / %d  |cffffd100%s|r\n%s\nfile %d  -  %s%s",
        _idx, #LIST, GROUPS[e.g].label, e.atlas and ("atlas " .. e.atlas) or e.path,
        e.id, status, live))
    pcall(function() f.dd:OverrideText((st.name and st.name ~= "") and st.name or (e.atlas or e.key)) end)
    if not (f.nameEb:HasFocus() or f.nameEb._pending) then f.nameEb:SetText(st.name or "") end
    f.doneCb:SetChecked(st.done == true)
    f.hideDoneCb:SetChecked(Store().hideDone == true)
    if not f.wBox.eb:HasFocus() then f.wBox.eb:SetText(W and tostring(W) or "") end
    if not f.hBox.eb:HasFocus() then f.hBox.eb:SetText(H and tostring(H) or "") end

    local which = Active()
    f.boxLbl:SetText(which == "hole" and L["DEV_WIN_ICONLAB_HOLE"] or L["DEV_WIN_ICONLAB_CROP"])
    local vals = { Box(_idx, which) }
    for n, box in ipairs(f.boxBoxes) do
        if not box.eb:HasFocus() then box.eb:SetText(vals[n] and tostring(vals[n]) or "") end
    end
    local gl, gt, gr, gb = Gaps()
    if gl then
        local function C(a, b2) return (a == b2) and "|cff4dff66" or "|cffff4040" end
        f.gaps:SetText(string.format("%sL %g  R %g|r    %sT %g  B %g|r", C(gl, gr), gl, gr, C(gt, gb), gt, gb))
    else
        f.gaps:SetText("")
    end
    f.removeBtn:SetShown(e.g == "added")
    RefreshRegions()
    LayoutSheet()
    LayoutPreview()
end

function BNB.OpenIconLab()
    if not BigNoteBoxDB then return end
    LoadList()
    if not _ctl then BuildControl() end
    _sh = _sh or BuildSheet()
    _pv = _pv or BuildPreview()
    if not _sh:GetPoint() then _sh:SetPoint("RIGHT", _ctl, "LEFT", -12, 0) end
    if not _pv:GetPoint() then _pv:SetPoint("TOPLEFT", _ctl, "TOPRIGHT", 12, 0) end
    _ctl:Show(); _ctl:Raise()
    _sh:Show()
    _pv:Show()
    Go(Store().idx or _idx)
    ProbeAllSizes()
end

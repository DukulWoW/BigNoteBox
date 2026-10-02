-- BigNoteBox UI/BgLayer.lua
-- Texture-layer backgrounds (ALL-110). A backdrop bgFile can only tile or
-- stretch; this draws the art as a texture of its own, so it can also cover,
-- fit, tile along one axis or sit at native size, placed by a 3x3 anchor.
-- Used by sticky notes (UI/StickyNote.lua) and the Background Lab
-- (UI/BackgroundLab.lua), so the Lab preview is exactly what a sticky shows.
--
-- A background def: { file = fileID or path, mode, anchor, scale, w, h, crop }.
-- w / h = the file's native size; every mode but stretch needs them.
-- crop = { x, y, w, h } in file pixels: the part of the file that holds the
-- picture, when the rest is empty (the profession art fills 677 x 550 of a
-- 1024 file, Dukul 2026-09-27). Only that part is drawn and every mode sizes
-- it as the image. REPEAT wraps the whole file, never a part of it, so a
-- tiled crop is drawn as separate copies (BL.PlaceTiles), each cut to the
-- crop with a half-texel inset so a packed sheet's neighbour art does not
-- show as a line between them (Dukul 2026-10-02: atlas regions would not tile).
-- flip = "h", "v" or "hv": the picture mirrored left-right and/or top-bottom
-- (ALL-187). Placement is unchanged; a crop mirrors inside its own rectangle.
-- bright = -1..1, the background's own brightness, curated in the Background
-- Lab (Dukul 2026-10-02: many game backgrounds look better a little lighter).
-- The layer adds the player's Texture brightness to it (BL.SetColors), so
-- the player's 0 means "as curated".
-- Fill modes (per axis: a repeating axis tiles, anything else is one copy
-- placed by the anchor and clipped to the area):
--   tile     repeat both ways at native size x scale
--   tileX    repeat across, one copy high
--   tileY    repeat down, one copy wide
--   stretch  fill the area, aspect ignored
--   cover    keep aspect, fill the area, crop the overflow
--   fit      keep aspect, whole image visible, base colour around it
--   width    keep aspect, match the area width
--   height   keep aspect, match the area height
--   native   native size x scale, no stretching

local BNB = BigNoteBox
if not BNB then return end

local BL = {}
BNB.BgLayer = BL

-- Mode labels are dev-only (Background Lab) and not translated
BL.MODES = {
    { key = "tile",    label = "Tile" },
    { key = "tileX",   label = "Tile across" },
    { key = "tileY",   label = "Tile down" },
    { key = "stretch", label = "Stretch" },
    { key = "cover",   label = "Cover" },
    { key = "fit",     label = "Fit" },
    { key = "width",   label = "Fit width" },
    { key = "height",  label = "Fit height" },
    { key = "native",  label = "Native" },
}
-- Anchor -> horizontal / vertical alignment (0 = left/top, 1 = right/bottom)
BL.ANCHORS = {
    { "TOPLEFT",    0,   0 },   { "TOP",    0.5, 0 },   { "TOPRIGHT",    1, 0 },
    { "LEFT",       0, 0.5 },   { "CENTER", 0.5, 0.5 }, { "RIGHT",       1, 0.5 },
    { "BOTTOMLEFT", 0,   1 },   { "BOTTOM", 0.5, 1 },   { "BOTTOMRIGHT", 1, 1 },
}
local ANCHOR_AL = {}
for _, a in ipairs(BL.ANCHORS) do ANCHOR_AL[a[1]] = { a[2], a[3] } end

-- ── Placement maths (pure) ───────────────────────────────────────────────────
-- One axis of length len, image length d, alignment al (0 start, 1 end).
-- Returns offset, visible length, texcoord start, texcoord end; nil = nothing
-- visible. rep = the axis repeats, so the texcoords run past 0..1.
local function Axis(len, d, rep, al)
    if rep then
        local n = len / d
        local t0 = al * (1 - n)
        return 0, len, t0, t0 + n
    end
    local o = (len - d) * al
    local v0, v1 = math.max(0, o), math.min(len, o + d)
    if v1 - v0 < 0.5 then return nil end
    return v0, v1 - v0, (v0 - o) / d, (v1 - o) / d
end

-- Where def lands in a W x H area. Returns x, y (down from the top left),
-- w, h, u0, u1, v0, v1, repeatX, repeatY; nil = nothing to draw (no native
-- size for a mode that needs one, or the image falls outside the area).
function BL.Place(W, H, def)
    local m, sc = def.mode or "stretch", def.scale or 1
    local fw, fh = def.w, def.h
    local c = def.crop
    if c and not (fw and fh and fw > 0 and fh > 0 and c[3] > 0 and c[4] > 0) then c = nil end
    local nw, nh = fw, fh
    if c then nw, nh = c[3], c[4] end
    local dw, dh, rx, ry
    if m == "stretch" then
        dw, dh = W, H
    else
        if not (nw and nh and nw > 0 and nh > 0) then return nil end
        if m == "tile" or m == "tileX" or m == "tileY" or m == "native" then
            dw, dh = nw * sc, nh * sc
            rx, ry = (m == "tile" or m == "tileX"), (m == "tile" or m == "tileY")
            if c then rx, ry = false, false end
        else
            local s
            if     m == "cover" then s = math.max(W / nw, H / nh)
            elseif m == "fit"   then s = math.min(W / nw, H / nh)
            elseif m == "width" then s = W / nw
            else                     s = H / nh end
            dw, dh = nw * s * sc, nh * s * sc
        end
    end
    local al = ANCHOR_AL[def.anchor] or ANCHOR_AL.CENTER
    local x, w, u0, u1 = Axis(W, dw, rx, al[1])
    local y, h, v0, v1 = Axis(H, dh, ry, al[2])
    if not (x and y) then return nil end
    -- Mirror in image space (0..1 per copy) before the crop maps it into the
    -- file, so a crop flips inside itself; reversed texcoords draw mirrored
    local fl = def.flip
    if fl == "h" or fl == "hv" then u0, u1 = 1 - u0, 1 - u1 end
    if fl == "v" or fl == "hv" then v0, v1 = 1 - v0, 1 - v1 end
    if c then
        u0, u1 = (c[1] + u0 * c[3]) / fw, (c[1] + u1 * c[3]) / fw
        v0, v1 = (c[2] + v0 * c[4]) / fh, (c[2] + v1 * c[4]) / fh
    end
    return x, y, w, h, u0, u1, v0, v1, rx, ry
end

-- One repeating axis cut into copies: { offset, length, t0, t1 } with t in
-- image space 0..1 per copy, the phase as Axis gives it (the anchor decides
-- where whole copies sit). At most MAX_SEGS per axis; past that the rest of
-- the area stays base colour.
local MAX_SEGS = 32   -- 1024 copies at most; a region that small is no background anyway
local function Segments(len, d, al)
    local segs = {}
    local t = al * (1 - len / d)   -- image position at offset 0
    local x = 0
    while x < len - 0.01 and #segs < MAX_SEGS do
        local frac = t - math.floor(t)
        if (1 - frac) * d < 0.01 then t = math.floor(t) + 1; frac = 0 end
        local w = math.min((1 - frac) * d, len - x)
        segs[#segs + 1] = { x, w, frac, frac + w / d }
        x, t = x + w, t + w / d
    end
    return segs
end

-- A tile mode with a crop: the copies to draw, as a list of
-- { x, y, w, h, u0, u1, v0, v1 } (file texcoords, flip applied). nil when
-- def is not a tiled crop (BL.Place draws it as one texture).
function BL.PlaceTiles(W, H, def)
    local m, c, fw, fh = def.mode, def.crop, def.w, def.h
    if not (c and (m == "tile" or m == "tileX" or m == "tileY")) then return nil end
    if not (fw and fh and fw > 0 and fh > 0 and c[3] > 0 and c[4] > 0) then return nil end
    local sc = def.scale or 1
    local dw, dh = c[3] * sc, c[4] * sc
    local al = ANCHOR_AL[def.anchor] or ANCHOR_AL.CENTER
    local function AxisSegs(len, d, rep, a)
        if rep then return Segments(len, d, a) end
        local o, w, t0, t1 = Axis(len, d, false, a)
        return o and { { o, w, t0, t1 } } or {}
    end
    local xs = AxisSegs(W, dw, m ~= "tileY", al[1])
    local ys = AxisSegs(H, dh, m ~= "tileX", al[2])
    local fl = def.flip
    local fx, fy = (fl == "h" or fl == "hv"), (fl == "v" or fl == "hv")
    -- Image space -> file texcoords, kept half a texel inside the crop
    local function Map(t, flip, o, len, full)
        if flip then t = 1 - t end
        local px = o + t * len
        px = math.max(o + 0.5, math.min(o + len - 0.5, px))
        return px / full
    end
    local out = {}
    for _, sy in ipairs(ys) do
        local v0, v1 = Map(sy[3], fy, c[2], c[4], fh), Map(sy[4], fy, c[2], c[4], fh)
        for _, sx in ipairs(xs) do
            out[#out + 1] = { sx[1], sy[1], sx[2], sy[2],
                Map(sx[3], fx, c[1], c[3], fw), Map(sx[4], fx, c[1], c[3], fw), v0, v1 }
        end
    end
    return out
end

local function SetTex(t, file, wrapH, wrapV)
    if t._file ~= file or t._wh ~= wrapH or t._wv ~= wrapV then
        pcall(function() t:SetTexture(file, wrapH, wrapV) end)
        t._file, t._wh, t._wv = file, wrapH, wrapV
    end
end

local function PutTex(t, area, x, y, w, h, u0, u1, v0, v1)
    t:ClearAllPoints()
    t:SetPoint("TOPLEFT", area, "TOPLEFT", x, -y)
    t:SetSize(w, h)
    t:SetTexCoord(u0, u1, v0, v1)
    t:Show()
end

-- The extra copies of a tiled crop live on tex._tiles, made on tex's own
-- parent in its draw layer and blend mode, and take its vertex colour, so
-- tint and brightness (set on tex before Draw) reach every copy.
local function HideTiles(tex, from)
    local pool = tex._tiles
    if not pool then return end
    for n = from, #pool do pool[n]:Hide() end
end

local function TileTex(tex, n)
    tex._tiles = tex._tiles or {}
    local t = tex._tiles[n]
    if not t then
        local layer, sub = tex:GetDrawLayer()
        t = tex:GetParent():CreateTexture(nil, layer, nil, sub)
        t:SetBlendMode(tex:GetBlendMode())
        tex._tiles[n] = t
    end
    t:SetVertexColor(tex:GetVertexColor())
    return t
end

-- Draws def into tex, placed inside area. Returns false (tex hidden) when
-- nothing is visible.
function BL.Draw(tex, area, def)
    local W, H = area:GetSize()
    if not (def and def.file and W > 1 and H > 1) then tex:Hide(); HideTiles(tex, 1); return false end
    local tiles = BL.PlaceTiles(W, H, def)
    if tiles then
        if #tiles == 0 then tex:Hide(); HideTiles(tex, 1); return false end
        SetTex(tex, def.file, "CLAMP", "CLAMP")
        PutTex(tex, area, unpack(tiles[1]))
        for n = 2, #tiles do
            local t = TileTex(tex, n - 1)
            SetTex(t, def.file, "CLAMP", "CLAMP")
            PutTex(t, area, unpack(tiles[n]))
        end
        HideTiles(tex, #tiles)
        return true
    end
    HideTiles(tex, 1)
    local x, y, w, h, u0, u1, v0, v1, rx, ry = BL.Place(W, H, def)
    if not x then tex:Hide(); return false end
    SetTex(tex, def.file, rx and "REPEAT" or "CLAMP", ry and "REPEAT" or "CLAMP")
    PutTex(tex, area, x, y, w, h, u0, u1, v0, v1)
    return true
end

-- ── The layer ────────────────────────────────────────────────────────────────
-- Base colour + art behind host, inset from its edges. A child frame one
-- level below the host, so the host's backdrop border draws over it. Opacity
-- goes on the layer frame, which fades base and art together as one surface
-- (two half-transparent layers would let the base bleed through the art).
-- Children follow their parent's frame level by the same delta, so a Raise
-- keeps it underneath; Seat is re-run on show and on every alpha change anyway.
function BL.Seat(layer)
    local host = layer._host
    local lv = host:GetFrameLevel()
    if lv < 1 then host:SetFrameLevel(1); lv = 1 end
    layer:SetFrameLevel(lv - 1)
end

function BL.Create(host)
    local layer = CreateFrame("Frame", nil, host)
    layer:EnableMouse(false)
    layer._host = host
    layer.base = layer:CreateTexture(nil, "BACKGROUND", nil, -8)
    layer.base:SetAllPoints()
    layer.tex = layer:CreateTexture(nil, "BACKGROUND", nil, 0)
    -- Brightness above 0: a second copy of the art in ADD blend on top, so
    -- light parts get brighter and dark lines stay dark (Dukul 2026-09-27)
    layer.add = layer:CreateTexture(nil, "BACKGROUND", nil, 1)
    layer.add:SetBlendMode("ADD")
    layer.add:Hide()
    layer:SetScript("OnSizeChanged", function(self) BL.Layout(self) end)
    host:HookScript("OnShow", function() BL.Seat(layer) end)
    layer:Hide()
    return layer
end

-- def = nil hides the layer. inset = distance from each of the host's edges.
function BL.Set(layer, def, inset)
    layer._def = def
    if not def then layer:Hide(); return end
    local i = inset or 0
    if layer._inset ~= i then
        layer:ClearAllPoints()
        layer:SetPoint("TOPLEFT", layer._host, "TOPLEFT", i, -i)
        layer:SetPoint("BOTTOMRIGHT", layer._host, "BOTTOMRIGHT", -i, i)
        layer._inset = i
    end
    BL.Seat(layer)
    layer:Show()
    BL.ApplyTint(layer)
    BL.Layout(layer)
end

-- The brightness drawn: the player's value plus the background's curated
-- one (def.bright), kept within -1..1
function BL.Brightness(player, def)
    local k = (player or 0) + (def and def.bright or 0)
    return math.max(-1, math.min(1, k))
end

-- Base colour under the art, and the tint multiplied into the art.
-- bright = the player's -1..1, nil = 0, added to the def's own (BL.Brightness):
-- below 0 darkens the art toward black, above 0 adds that fraction of the
-- tinted art again (ADD). The base is untouched.
function BL.SetColors(layer, br, bg, bb, tr, tg, tb, bright)
    layer.base:SetColorTexture(br, bg, bb, 1)
    layer._tint = { tr, tg, tb }
    layer._bright = bright or 0
    BL.ApplyTint(layer)
    BL.Layout(layer)
end

-- Tint and brightness onto the art; re-run when the def changes (Set), as
-- its curated brightness may differ
function BL.ApplyTint(layer)
    local t = layer._tint
    if not t then return end
    local k = BL.Brightness(layer._bright, layer._def)
    local m = k < 0 and (1 + k) or 1
    layer.tex:SetVertexColor(t[1] * m, t[2] * m, t[3] * m, 1)
    layer._k = k
    if k > 0 then layer.add:SetVertexColor(t[1] * k, t[2] * k, t[3] * k, 1) end
    -- The copies of a tiled crop take the colour when drawn (Layout follows)
end

function BL.SetAlpha(layer, a)
    BL.Seat(layer)
    layer:SetAlpha(a)
end

function BL.Layout(layer)
    if not (layer._def and layer:IsShown()) then return end
    local drawn = BL.Draw(layer.tex, layer, layer._def)
    if drawn and (layer._k or 0) > 0 then BL.Draw(layer.add, layer, layer._def)
    else BL.Draw(layer.add, layer, nil) end   -- hides it and any tiled copies
end

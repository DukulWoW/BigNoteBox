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
-- it as the image. A crop cannot repeat (REPEAT wraps the whole file), so
-- the tile modes draw one copy with a crop.
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
    if c then
        u0, u1 = (c[1] + u0 * c[3]) / fw, (c[1] + u1 * c[3]) / fw
        v0, v1 = (c[2] + v0 * c[4]) / fh, (c[2] + v1 * c[4]) / fh
    end
    return x, y, w, h, u0, u1, v0, v1, rx, ry
end

-- Draws def into tex, placed inside area. Returns false (tex hidden) when
-- nothing is visible.
function BL.Draw(tex, area, def)
    local W, H = area:GetSize()
    if not (def and def.file and W > 1 and H > 1) then tex:Hide(); return false end
    local x, y, w, h, u0, u1, v0, v1, rx, ry = BL.Place(W, H, def)
    if not x then tex:Hide(); return false end
    local wrapH, wrapV = rx and "REPEAT" or "CLAMP", ry and "REPEAT" or "CLAMP"
    if tex._file ~= def.file or tex._wh ~= wrapH or tex._wv ~= wrapV then
        pcall(function() tex:SetTexture(def.file, wrapH, wrapV) end)
        tex._file, tex._wh, tex._wv = def.file, wrapH, wrapV
    end
    tex:ClearAllPoints()
    tex:SetPoint("TOPLEFT", area, "TOPLEFT", x, -y)
    tex:SetSize(w, h)
    tex:SetTexCoord(u0, u1, v0, v1)
    tex:Show()
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
    BL.Layout(layer)
end

-- Base colour under the art, and the tint multiplied into the art.
-- bright = -1..1, nil = 0: below 0 darkens the art toward black, above 0
-- adds that fraction of the tinted art again (ADD). The base is untouched.
function BL.SetColors(layer, br, bg, bb, tr, tg, tb, bright)
    local k = bright or 0
    layer.base:SetColorTexture(br, bg, bb, 1)
    local m = k < 0 and (1 + k) or 1
    layer.tex:SetVertexColor(tr * m, tg * m, tb * m, 1)
    layer._bright = k
    if k > 0 then
        layer.add:SetVertexColor(tr * k, tg * k, tb * k, 1)
        BL.Layout(layer)
    else
        layer.add:Hide()
    end
end

function BL.SetAlpha(layer, a)
    BL.Seat(layer)
    layer:SetAlpha(a)
end

function BL.Layout(layer)
    if not (layer._def and layer:IsShown()) then return end
    local drawn = BL.Draw(layer.tex, layer, layer._def)
    if drawn and (layer._bright or 0) > 0 then BL.Draw(layer.add, layer, layer._def)
    else layer.add:Hide() end
end

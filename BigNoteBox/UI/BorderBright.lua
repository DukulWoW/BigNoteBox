-- BigNoteBox UI/BorderBright.lua
-- Border brightness on one scale everywhere (ALL-123, ALL-142): 0..200 %,
-- 100 = as drawn, below darkens toward black, above brightens. The client
-- clamps vertex colours at 1.0, so the part above 100 % is drawn by an ADD
-- copy of each border piece over it at (pct - 100) % of its colour: light
-- parts get brighter and dark lines stay dark (the Oracle's way since
-- ALL-69.5, Dukul 2026-09-28). A copy lives on the piece's own frame, one
-- sublevel up in the same draw layer, and is re-synced on every draw and size
-- change (a backdrop's edges change their texture coordinates with the size).
-- Used by the sticky window border, every note icon edge border, tinted icon
-- frames and the Oracle's backdrop themes (UI/SearchChrome.lua).

local BNB = BigNoteBox
if not BNB then return end

local BB = {}
BNB.BorderBright = BB

BB.MIN, BB.MAX, BB.DEFAULT = 0, 200, 100

-- No sources: shared, so a hover fade at 100 % or less allocates nothing
local EMPTY = {}

-- The edge pieces of a BackdropTemplate frame (also a NineSlice's names)
BB.BOX_BORDER = { "TopLeftCorner", "TopRightCorner", "BottomLeftCorner", "BottomRightCorner",
                  "TopEdge", "BottomEdge", "LeftEdge", "RightEdge" }

-- A saved percentage (nil = 100) inside the scale
function BB.Clamp(pct)
    pct = tonumber(pct) or BB.DEFAULT
    if pct < BB.MIN then return BB.MIN end
    if pct > BB.MAX then return BB.MAX end
    return pct
end

-- pct -> (multiplier for the base colour 0..1, ADD strength 0..1)
function BB.Split(pct)
    pct = BB.Clamp(pct)
    if pct <= 100 then return pct / 100, 0 end
    return 1, (pct - 100) / 100
end

local function SyncCopy(add, src)
    local ht, vt = src:GetHorizTile(), src:GetVertTile()
    add:SetTexture(src:GetTexture(), ht and "REPEAT" or nil, vt and "REPEAT" or nil)
    add:SetTexCoord(src:GetTexCoord())
    add:SetHorizTile(ht)
    add:SetVertTile(vt)
    add:ClearAllPoints()
    add:SetAllPoints(src)
    -- The source may have moved layer since (an icon frame drawn under / over)
    local layer, sub = src:GetDrawLayer()
    add:SetDrawLayer(layer, math.min(7, (sub or 0) + 1))
end

-- Re-sync every shown copy on f (after a size change)
function BB.Resync(f)
    for _, list in pairs(f._bbAdds or {}) do
        for _, add in ipairs(list) do
            if add:IsShown() and add._src then SyncCopy(add, add._src) end
        end
    end
end

local function HookSize(f)
    if f._bbSizeHooked then return end
    f._bbSizeHooked = true
    -- Hooked: runs after the backdrop's own OnSizeChanged has re-cut its edges
    f:HookScript("OnSizeChanged", BB.Resync)
end

-- The ADD copies of sources (a list of textures) under f._bbAdds[key]: shown
-- at k (0..1) times r, g, b with alpha a while k > 0 and the source is shown.
function BB.SetCopies(f, key, sources, k, r, g, b, a)
    f._bbAdds = f._bbAdds or {}
    local list = f._bbAdds[key] or {}
    f._bbAdds[key] = list
    for i, src in ipairs(sources) do
        local add = list[i]
        if not add or add._src ~= src then
            if add then add:Hide() end
            local layer, sub = src:GetDrawLayer()
            add = src:GetParent():CreateTexture(nil, layer, nil, math.min(7, (sub or 0) + 1))
            add:SetBlendMode("ADD")
            add._src = src
            list[i] = add
        end
        if k > 0 and src:IsShown() then
            SyncCopy(add, src)
            add:SetVertexColor(r * k, g * k, b * k, a or 1)
            add:Show()
        else
            add:Hide()
        end
    end
    for i = #sources + 1, #list do list[i]:Hide() end
    if k > 0 and #sources > 0 then HookSize(f) end
end

function BB.HideCopies(f, key)
    local list = f._bbAdds and f._bbAdds[key]
    if list then for _, add in ipairs(list) do add:Hide() end end
end

-- The named pieces of owner that are textures
function BB.Pieces(owner, names)
    local out = {}
    for _, n in ipairs(names or BB.BOX_BORDER) do
        local t = owner and owner[n]
        if t and t.GetTexture then out[#out + 1] = t end
    end
    return out
end

-- A backdrop frame's border colour at pct: SetBackdropBorderColor with the
-- darkened colour, plus the ADD copies above 100 %. a = the border's alpha
-- (0 hides the copies too). Call it wherever SetBackdropBorderColor was.
function BB.SetBackdropBorder(f, pct, r, g, b, a)
    local m, k = BB.Split(pct)
    a = a or 1
    pcall(f.SetBackdropBorderColor, f, r * m, g * m, b * m, a)
    BB.SetCopies(f, "backdrop", (k > 0 and a > 0) and BB.Pieces(f) or EMPTY, k, r, g, b, a)
end

-- One texture (an icon frame): its vertex colour and one ADD copy
function BB.SetTexture(tex, pct, r, g, b, a)
    local m, k = BB.Split(pct)
    r, g, b, a = r or 1, g or 1, b or 1, a or 1
    tex:SetVertexColor(r * m, g * m, b * m, a)
    local host = tex:GetParent()
    BB.SetCopies(host, tex, (k > 0 and tex:IsShown()) and { tex } or EMPTY, k, r, g, b, a)
end

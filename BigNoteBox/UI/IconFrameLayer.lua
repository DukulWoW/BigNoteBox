-- BigNoteBox UI/IconFrameLayer.lua
-- Draws an icon frame (ALL-126/127): one picture cut from a game file, with a
-- hole, laid over or under a note icon. Shared by the Icon Lab preview
-- (UI/IconLab.lua) and the note icons, so the Lab shows what a note shows.
--
-- A def is { file, w, h, crop = { x, y, w, h }, hole = { x, y, w, h },
-- shape = "square" | "circle", layer = "over" | "under", tint = true|nil,
-- scale = number|nil },
-- all in file pixels (crop nil = the whole file). The hole's larger side is
-- scaled to the icon size and its centre put on the icon's centre; the frame
-- grows outward from there and the icon keeps its own size. scale (default
-- 1) sizes the frame on top of that, for art with no real hole (corner
-- ornaments), around the same hole centre.

local BNB = BigNoteBox
if not BNB then return end

local IFL = {}
BNB.IconFrameLayer = IFL

local CIRCLE_MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"

-- Round or square icon. The mask is made once per icon and only added or
-- removed after that.
function IFL.SetShape(icon, shape)
    if shape == "circle" then
        local m = icon._ifMask
        if not m then
            m = icon:GetParent():CreateMaskTexture()
            m:SetTexture(CIRCLE_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
            m:SetAllPoints(icon)
            icon._ifMask = m
        end
        if not icon._ifMasked then icon:AddMaskTexture(m); icon._ifMasked = true end
    elseif icon._ifMasked then
        icon:RemoveMaskTexture(icon._ifMask)
        icon._ifMasked = nil
    end
end

-- The frame's size and its TOPLEFT offset from the icon's centre, for an
-- icon of the given size. Returns w, h, x, y, or nil for an unusable def.
function IFL.Measure(def, size)
    local hole = def and def.hole
    if not (hole and def.w and def.h and hole[3] > 0 and hole[4] > 0) then return nil end
    local c = def.crop or { 0, 0, def.w, def.h }
    local k = size / math.max(hole[3], hole[4]) * (def.scale or 1)
    return c[3] * k, c[4] * k,
        -(hole[1] + hole[3] / 2 - c[1]) * k,
         (hole[2] + hole[4] / 2 - c[2]) * k
end

-- Puts def's frame on tex around icon (both on the same parent frame).
-- nil def hides it and makes the icon square again. bright (default 1) is
-- applied only to a def with tint = true.
function IFL.Apply(icon, tex, def, size, bright)
    size = size or icon:GetWidth()
    local fw, fh, ox, oy = IFL.Measure(def, size)
    if not fw then
        tex:Hide()
        IFL.SetShape(icon, nil)
        return
    end
    local W, H = def.w, def.h
    local c = def.crop or { 0, 0, W, H }
    tex:SetTexture(def.file)
    -- Half-texel inset: on a packed sheet, filtering otherwise draws the
    -- neighbouring art as a line along the edge
    tex:SetTexCoord((c[1] + 0.5) / W, (c[1] + c[3] - 0.5) / W,
                    (c[2] + 0.5) / H, (c[2] + c[4] - 0.5) / H)
    tex:SetSize(fw, fh)
    tex:ClearAllPoints()
    tex:SetPoint("TOPLEFT", icon, "CENTER", ox, oy)
    tex:SetDrawLayer(def.layer == "under" and "BORDER" or "OVERLAY", 1)
    local m = (def.tint and bright) or 1
    tex:SetVertexColor(math.min(1, m), math.min(1, m), math.min(1, m), 1)
    tex:Show()
    IFL.SetShape(icon, def.shape)
end

-- Applies note.iconFrame to icon (a note icon texture whose parent has room
-- for the frame art to overhang it). Returns true when a frame was drawn, so
-- the caller can skip its own LSM edge border for this icon (ALL-127: the
-- two are drawn one at a time, picking one clears the other). Reuses the
-- note's borderScale/Offset/Brightness sliders, the same ones the LSM edge
-- border already uses. size: the icon's size, for an icon sized by two
-- anchors whose width is not laid out yet (else GetWidth). A hidden icon
-- (Oracle with icons off) gets no frame.
function BNB.ApplyIconFrame(icon, note, size)
    if not icon then return false end
    local def = BNB.IconFrames and BNB.IconFrames.Get(note and note.iconFrame)
    if not icon:IsShown() then def = nil end
    if not def then
        if icon._ifTex then icon._ifTex:Hide() end
        IFL.SetShape(icon, nil)
        return false
    end
    if not icon._ifTex then
        icon._ifTex = icon:GetParent():CreateTexture(nil, "OVERLAY")
    end
    local scale  = (note.borderScale or 100) / 100
    local bright = (note.borderBrightness or 100) / 100
    size = size or icon:GetWidth() or 0
    if size <= 0 then size = 20 end
    size = size * scale
    IFL.Apply(icon, icon._ifTex, def, size, bright)
    return true
end

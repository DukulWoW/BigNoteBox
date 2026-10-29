-- BigNoteBox UI/NewMarker.lua — the "NEW" badge on new features (ALL-166)
--
-- A feature in NEW below shows the game's NEW badge (the character-create
-- notification, its Alliance half: the streak trails right, so it sits after
-- a name) for the whole release it came in: it goes with the next minor
-- release (X.Y), opened or not (Dukul, 2026-10-22: "they should stay till the
-- next Y version, they should not go away when you go into or use it").
--
--   BNB.IsNew(key)                 still marked
--   BNB.AddNewMarker(key, fs)      a badge after fontstring fs's text; nil
--                                  when key is not new

local BNB = BigNoteBox

-- key -> the release it came in ("major.minor"); the badge shows while the
-- addon is that release or older (a dev build of it)
local NEW = {
    explorer = "2.0",    -- Settings > Modules > Explorer view (ALL-414)
    folders  = "2.0",    -- Settings > Modules > Folders (ALL-510)
    accessibility = "2.0",    -- Settings > Modules > Accessibility (ALL-548)
    spelling = "2.0",    -- Settings > Modules > Spelling (ALL-559)
}

local TEX    = 929716   -- interface/glues/charactercreate/newcharacternotification
local COORD  = { 0.007812, 0.882812, 0.007812, 0.460938 }   -- NewCharacter-Alliance, 112 x 58
local H      = 24
local GAP    = 4
-- Tinted the BNB green of the headings (Dukul, 2026-10-22), read at draw
-- time from BNB.HEADER_COLOR_NORMAL (UI/TextColors.lua)
local TINT_FALLBACK = { 0.55, 0.82, 0.55 }


local function MajorMinor(v)
    local a, b = tostring(v or ""):match("^(%d+)%.(%d+)")
    return tonumber(a) or 0, tonumber(b) or 0
end

local _hasArt
local function HasArt()
    if _hasArt == nil then
        _hasArt = not (C_UIFileAsset and C_UIFileAsset.IsKnownFile) or C_UIFileAsset.IsKnownFile(TEX) and true or false
    end
    return _hasArt
end

function BNB.IsNew(key)
    local tag = key and NEW[key]
    if not tag then return false end
    local am, an = MajorMinor(BNB.ADDON_VERSION)
    local tm, tn = MajorMinor(tag)
    return am < tm or (am == tm and an <= tn)
end

-- The badge texture alone, h pixels high (default 24) on parent; nil on a
-- client without the art. Also the release welcome's "marked NEW" row (ALL-617)
function BNB.NewBadgeTexture(parent, h)
    if not (parent and HasArt()) then return nil end
    h = h or H
    local t = parent:CreateTexture(nil, "OVERLAY")
    t:SetTexture(TEX)
    t:SetTexCoord(COORD[1], COORD[2], COORD[3], COORD[4])
    t:SetDesaturated(true)
    local c = BNB.HEADER_COLOR_NORMAL or TINT_FALLBACK
    t:SetVertexColor(c[1], c[2], c[3])
    t:SetSize(math.floor(h * 112 / 58 + 0.5), h)
    return t
end

function BNB.AddNewMarker(key, fs)
    if not (fs and BNB.IsNew(key)) then return nil end
    local t = BNB.NewBadgeTexture(fs:GetParent(), H)
    if not t then return nil end
    -- After the text, not the fontstring's box: a row title spans the row
    local function Place()
        t:ClearAllPoints()
        t:SetPoint("LEFT", fs, "LEFT", math.ceil(fs:GetStringWidth() or 0) + GAP, 0)
    end
    Place()
    local p = fs:GetParent()
    if p and p.HookScript then p:HookScript("OnShow", Place) end   -- a cold font measures 0 at build
    return t
end

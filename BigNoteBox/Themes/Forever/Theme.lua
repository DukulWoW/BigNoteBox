-- BigNoteBox Themes/Forever/Theme.lua
-- The Forever theme (ALL-647): the WoW Forever client's window art on Retail
-- and Classic (Dukul, 2026-11-10: "Retail and Classic only"; the Forever
-- client's Default already draws it). Art: Themes/Forever/Assets, made by
-- _work/tools/forever-art.py; tuned in the dev test window /bnbforever
-- (BigNoteBox_Dev/ForeverThemeTest.lua), whose numbers these are.
--
-- S1 (2026-11-10): tool windows (BNB.CreateToolWindow in normal mode). The
-- window stays a ButtonFrameTemplate, so its title, close button handle and
-- content anchors work as tuned; only the template's border art is hidden
-- and the metal frame drawn in its place.

local BNB = BigNoteBox
if not (BNB and BNB.RegisterTheme) then return end

local ART  = "Interface\\AddOns\\BigNoteBox\\Themes\\Forever\\Assets\\"
local BG   = "Interface\\AddOns\\BigNoteBox\\Assets\\UI\\ui-bg-forever"
local GLOW = "Interface\\AddOns\\BigNoteBox\\Assets\\UI\\ui-bg-sp-highlight"

-- Frame scale: the art's -2x size is 0.5; 0.40 fixed (Dukul, 2026-11-01: the
-- X then matches the Retail main window's; 2026-11-10: not a setting)
local S = 0.4

-- The metal frame's outer line is column 23 on the left, 187 of 190 on the
-- right, row 24 at the top and 190 of 200 at the bottom: those go on the
-- window's edges. The top band's dark title strip is rows 24-83, its middle
-- row 53.5. Corners 190 x 190 (bottom 190 x 200), side edges 190 x 256, top
-- and bottom bands 256 wide; edges tile.
-- Inside the window at 0.40 (measured 2026-11-10): ~5 px on the sides, ~7 px
-- at the bottom, the band ~24 px: close to ButtonFrameTemplate's own border.
local ML, MR, MT, MB, MBAND = 23, 3, 24, 10, 53.5
local CORNER, TILE = 190, 256
local BG_INSET = 10   -- art px in from the outer line, where every bevel is opaque

local function Tex(host, sub, file, hw, vw)
    local t = host:CreateTexture(nil, "BORDER", nil, sub)
    if hw then t:SetTexture(ART .. file, hw, vw) else t:SetTexture(ART .. file) end
    return t
end

-- The frame on its own child frame: its OnSizeChanged is ours alone, so a
-- window that sets its own size script cannot drop the tiling
local function BuildFrame(f)
    local c = CreateFrame("Frame", nil, f)
    c:SetAllPoints(f)
    c:SetFrameLevel(f:GetFrameLevel() + 1)
    local C = CORNER * S
    local tl = Tex(c, 3, "Frame\\metal-corner-topleft")
    local tr = Tex(c, 3, "Frame\\metal-corner-topright")
    local bl = Tex(c, 3, "Frame\\metal-corner-bottomleft")
    local br = Tex(c, 3, "Frame\\metal-corner-bottomright")
    tl:SetSize(C, C); tr:SetSize(C, C)
    bl:SetSize(C, 200 * S); br:SetSize(C, 200 * S)
    tl:SetPoint("TOPLEFT", c, "TOPLEFT", -ML * S, MT * S)
    tr:SetPoint("TOPRIGHT", c, "TOPRIGHT", MR * S, MT * S)
    bl:SetPoint("BOTTOMLEFT", c, "BOTTOMLEFT", -ML * S, -MB * S)
    br:SetPoint("BOTTOMRIGHT", c, "BOTTOMRIGHT", MR * S, -MB * S)
    local top    = Tex(c, 2, "Frame\\metal-edge-top", "REPEAT", "CLAMP")
    local bottom = Tex(c, 2, "Frame\\metal-edge-bottom", "REPEAT", "CLAMP")
    local left   = Tex(c, 1, "Frame\\metal-edge-left", "CLAMP", "REPEAT")
    local right  = Tex(c, 1, "Frame\\metal-edge-right", "CLAMP", "REPEAT")
    top:SetPoint("TOPLEFT", tl, "TOPRIGHT");     top:SetPoint("BOTTOMRIGHT", tr, "BOTTOMLEFT")
    bottom:SetPoint("TOPLEFT", bl, "TOPRIGHT");  bottom:SetPoint("BOTTOMRIGHT", br, "BOTTOMLEFT")
    left:SetPoint("TOPLEFT", tl, "BOTTOMLEFT");  left:SetPoint("BOTTOMRIGHT", bl, "TOPRIGHT")
    right:SetPoint("TOPLEFT", tr, "BOTTOMLEFT"); right:SetPoint("BOTTOMRIGHT", br, "TOPRIGHT")
    local function Layout()
        local w, h = c:GetWidth(), c:GetHeight()
        if not (w and h) or w <= 0 then return end
        local span  = math.max(1, w + (ML + MR) * S - 2 * C)
        local vspan = math.max(1, h + (MT + MB) * S - CORNER * S - 200 * S)
        top:SetTexCoord(0, span / (TILE * S), 0, 1)
        bottom:SetTexCoord(0, span / (TILE * S), 0, 1)
        left:SetTexCoord(0, 1, 0, vspan / (TILE * S))
        right:SetTexCoord(0, 1, 0, vspan / (TILE * S))
    end
    c:SetScript("OnSizeChanged", Layout)
    c:SetScript("OnShow", Layout)
    Layout()
    return c
end

-- Wood grain with the soft orange glow (the Forever look the Forever client's
-- normal mode has, UI/Chrome.lua), kept inside the frame
local function DressBg(f)
    local bg = f.Bg or f:CreateTexture(nil, "BACKGROUND")
    f.Bg = bg
    bg:SetTexture(BG, "REPEAT", "REPEAT")
    bg:SetHorizTile(true); bg:SetVertTile(true)
    bg:SetVertexColor(1, 1, 1, 1)
    bg:ClearAllPoints()
    local i = BG_INSET * S
    bg:SetPoint("TOPLEFT", f, "TOPLEFT", i, -i)
    bg:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -i, i)
    bg:Show()
    local glow = f:CreateTexture(nil, "BACKGROUND", nil, 7)
    glow:SetAllPoints(bg)
    glow:SetTexture(GLOW)
    f._themeGlow = glow
end

-- The red title-bar X, over the right border and the band's top and bottom
-- (Dukul, 2026-11-01). Takes over f.CloseButton (the window sets its OnClick
-- next); a tooltip is f.CloseButton._tip, as on our own close button.
local function DressClose(f, level, cy)
    local old = f.CloseButton
    local size = math.floor(56 * S + 0.5)
    local b = CreateFrame("Button", nil, f)
    b:SetSize(size, size)
    b:SetNormalTexture(ART .. "Buttons\\small-exit")
    b:SetPushedTexture(ART .. "Buttons\\small-exit-pressed")
    b:SetDisabledTexture(ART .. "Buttons\\small-exit-disabled")
    b:SetHighlightTexture(ART .. "Buttons\\small-highlight", "ADD")
    b:SetPoint("RIGHT", f, "TOPRIGHT", 4 * S, cy)
    b:SetFrameLevel(level)
    b._bnbClose = true
    b:SetScript("OnClick", function() f:Hide() end)
    b:SetScript("OnEnter", function(self)
        if not self._tip then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(self._tip, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    if old then old:Hide() end
    f.CloseButton = b
end

local function DressWindow(f)
    if f._bnbThemed then return end
    f._bnbThemed = "forever"
    local tc = f.TitleContainer
    local tt = (tc and tc.TitleText) or f.TitleText

    -- Hide the template's own art: everything on the window now except the
    -- background, the title and the close button (NineSlice, tile streaks;
    -- portrait, button bar and inset are hidden already)
    local keep, list = {}, { f.Bg, tc, tt, f.CloseButton }   -- any may be nil
    for i = 1, 4 do if list[i] then keep[list[i]] = true end end
    for _, r in ipairs({ f:GetRegions() }) do
        if not keep[r] then r:Hide() end
    end
    for _, ch in ipairs({ f:GetChildren() }) do
        if not keep[ch] then ch:Hide() end
    end

    DressBg(f)
    local chrome = BuildFrame(f)
    f._themeChrome = chrome
    local lvl = chrome:GetFrameLevel()
    local cy = (MT - MBAND) * S   -- the title strip's middle, from the top

    -- Title centred in the strip, clear of the X
    if tc then tc:SetFrameLevel(lvl + 1) end
    if tt then
        tt:ClearAllPoints()
        tt:SetPoint("LEFT", f, "TOPLEFT", 30, cy)
        tt:SetPoint("RIGHT", f, "TOPRIGHT", -30, cy)
        tt:SetJustifyH("CENTER")
        tt:SetWordWrap(false)
    end
    DressClose(f, lvl + 2, cy)
end

BNB.RegisterTheme("forever", {
    labelKey  = "CFG_THEME_FOREVER",
    available = function() return not BNB.IsForever end,
    DressWindow = DressWindow,
})

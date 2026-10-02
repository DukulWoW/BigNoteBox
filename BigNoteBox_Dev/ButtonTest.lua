-- ButtonTest.lua
-- Test window for the layered button art in Test-Graphics/Buttons (Dukul,
-- 2026-10-02). /bnbbt toggles it. Dev only, never packaged.
--
-- Left: every state drawn still, at the art's own size, for the 64 and 128
-- sets with both borders. Right: live buttons (hover #1 and hover #2) at the
-- sizes BNB uses, 18 (skin title bar) up to 38 (Forever toolbar hover).
-- The window is scaled so 1 UI unit = 1 screen pixel ("1:1" button).

local PATH = "Interface\\AddOns\\BigNoteBox_Dev\\Test-Graphics\\Buttons\\"
-- File name suffix per art set: bt-background.tga / bt-background-128.tga
local SET_SUFFIX = { [64] = "", [128] = "-128" }
local SETS = { 64, 128 }
local BORDERS = { "retail", "forever" }
local LIVE_SIZES = { 18, 20, 24, 26, 28, 32, 38 }
-- Disabled: desaturated, then darkened by these. The icon (eye) layer goes darker
-- than the rest; Retail is a little brighter, its border is darker than Forever's (Dukul)
local DIM      = { retail = 0.7,  forever = 0.6 }
local DIM_ICON = { retail = 0.42, forever = 0.35 }

local NORMAL  = { "bt-background", "bt-button", "bt-eye-normal", "BORDER" }
local HOVER1  = { "bt-background", "bt-button", "bt-eye-normal", "bt-hover", "BORDER" }
local HOVER2  = { "bt-background", "bt-button", "bt-hover", "bt-eye-normal", "BORDER" }
local PRESSED = { "bt-background", "bt-button-pressed", "bt-eye-pressed", "BORDER" }

local STATES = {
    { label = "Normal",   layers = NORMAL },
    { label = "Hover #1", layers = HOVER1 },
    { label = "Hover #2", layers = HOVER2 },
    { label = "Pressed",  layers = PRESSED },
    { label = "Disabled", layers = NORMAL, dim = true },
}

local PAD, TOP, LABEL_W, GAP, SEC_GAP = 14, 64, 96, 14, 40

local f
local liveButtons = {}
local liveDisabled = false
local pixelPerfect = true

local function File(name, set, border)
    if name == "BORDER" then name = "bt-border-" .. border end
    return PATH .. name .. SET_SUFFIX[set]
end

-- One button look: a frame with the layers stacked bottom to top
local function MakeStack(parent, set, border, layers, dim)
    local s = CreateFrame("Frame", nil, parent)
    s:SetAllPoints()
    s.tex = {}
    for i, name in ipairs(layers) do
        local t = s:CreateTexture(nil, "ARTWORK", nil, i - 1)
        t:SetAllPoints()
        t:SetTexture(File(name, set, border))
        t._dim = (name:find("^bt%-eye") and DIM_ICON or DIM)[border]
        s.tex[i] = t
    end
    function s:SetDim(on)
        for _, t in ipairs(self.tex) do
            t:SetDesaturated(on)
            local d = on and t._dim or 1
            t:SetVertexColor(d, d, d)
        end
    end
    if dim then s:SetDim(true) end
    return s
end

local function MakeLabel(text, template)
    local fs = f:CreateFontString(nil, "OVERLAY", template or "GameFontNormal")
    fs:SetText(text)
    return fs
end

local function MakeLive(set, border, hoverLayers)
    local b = CreateFrame("Button", nil, f)
    b.looks = {
        normal  = MakeStack(b, set, border, NORMAL),
        hover   = MakeStack(b, set, border, hoverLayers),
        pressed = MakeStack(b, set, border, PRESSED),
    }
    function b:ShowLook(which)
        for k, s in pairs(self.looks) do s:SetShown(k == which) end
    end
    function b:Refresh()
        local dis = not self:IsEnabled()
        self.looks.normal:SetDim(dis)
        if dis then self:ShowLook("normal")
        elseif self.down then self:ShowLook("pressed")
        elseif self:IsMouseOver() then self:ShowLook("hover")
        else self:ShowLook("normal") end
    end
    b:SetScript("OnEnter", function(self) self:Refresh() end)
    b:SetScript("OnLeave", function(self) self:Refresh() end)
    b:SetScript("OnMouseDown", function(self) if self:IsEnabled() then self.down = true; self:Refresh() end end)
    b:SetScript("OnMouseUp", function(self) self.down = false; self:Refresh() end)
    b:Refresh()
    liveButtons[#liveButtons + 1] = b
    return b
end

local function ApplyScale()
    local s = 1
    if pixelPerfect then
        local _, physH = GetPhysicalScreenSize()
        s = 768 / physH / UIParent:GetScale()
    end
    f:SetScale(s)
end

local function Build()
    f = CreateFrame("Frame", "BigNoteBoxDevButtonTest", UIParent, "BasicFrameTemplateWithInset")
    f:SetFrameStrata("DIALOG")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetClampedToScreen(true)
    if f.TitleText then f.TitleText:SetText("BNB button art test") end
    tinsert(UISpecialFrames, f:GetName())

    local tpl = BigNoteBox and BigNoteBox.PanelButtonTemplate and BigNoteBox.PanelButtonTemplate()
    local function ToolBtn(text, w, onClick)
        local b = CreateFrame("Button", nil, f, tpl or "UIPanelButtonTemplate")
        b:SetSize(w, 22)
        b:SetText(text)
        b:SetScript("OnClick", onClick)
        return b
    end
    local pixBtn
    pixBtn = ToolBtn("1:1 pixels: on", 130, function()
        pixelPerfect = not pixelPerfect
        pixBtn:SetText(pixelPerfect and "1:1 pixels: on" or "1:1 pixels: off")
        ApplyScale()
    end)
    pixBtn:SetPoint("TOPLEFT", PAD, -30)
    local disBtn
    disBtn = ToolBtn("Disable live buttons", 160, function()
        liveDisabled = not liveDisabled
        disBtn:SetText(liveDisabled and "Enable live buttons" or "Disable live buttons")
        for _, b in ipairs(liveButtons) do b:SetEnabled(not liveDisabled); b:Refresh() end
    end)
    disBtn:SetPoint("LEFT", pixBtn, "RIGHT", 8, 0)

    -- Still states: columns = states, rows = set x border, drawn at the art's own size
    local colW = 128
    local y = -(TOP + 20)
    for ci, st in ipairs(STATES) do
        local h = MakeLabel(st.label)
        h:SetPoint("BOTTOM", f, "TOPLEFT", PAD + LABEL_W + (ci - 1) * (colW + GAP) + colW / 2, y + 4)
    end
    for _, set in ipairs(SETS) do
        for _, border in ipairs(BORDERS) do
            local rl = MakeLabel(set .. " " .. border, "GameFontHighlight")
            rl:SetPoint("LEFT", f, "TOPLEFT", PAD, y - set / 2)
            for ci, st in ipairs(STATES) do
                local cell = CreateFrame("Frame", nil, f)
                cell:SetSize(set, set)
                cell:SetPoint("TOPLEFT", f, "TOPLEFT", PAD + LABEL_W + (ci - 1) * (colW + GAP) + (colW - set) / 2, y)
                MakeStack(cell, set, border, st.layers, st.dim)
            end
            y = y - set - GAP
        end
    end
    local leftW = PAD + LABEL_W + #STATES * (colW + GAP) - GAP
    local leftH = -y

    -- Live buttons: rows = set x border x hover variant, columns = sizes
    local liveX = leftW + SEC_GAP
    local liveLabelW = 130
    local cellW = LIVE_SIZES[#LIVE_SIZES]
    local ly = -(TOP + 20)
    local head = MakeLabel("Live buttons (hover and press them)")
    head:SetPoint("BOTTOMLEFT", f, "TOPLEFT", liveX, ly + 22)
    for ci, size in ipairs(LIVE_SIZES) do
        local h = MakeLabel(tostring(size), "GameFontNormalSmall")
        h:SetPoint("BOTTOM", f, "TOPLEFT", liveX + liveLabelW + (ci - 1) * (cellW + GAP) + cellW / 2, ly + 4)
    end
    for _, set in ipairs(SETS) do
        for _, border in ipairs(BORDERS) do
            for hv, hoverLayers in ipairs({ HOVER1, HOVER2 }) do
                local rl = MakeLabel(set .. " " .. border .. " hover #" .. hv, "GameFontHighlightSmall")
                rl:SetPoint("LEFT", f, "TOPLEFT", liveX, ly - cellW / 2)
                for ci, size in ipairs(LIVE_SIZES) do
                    local b = MakeLive(set, border, hoverLayers)
                    b:SetSize(size, size)
                    b:SetPoint("CENTER", f, "TOPLEFT", liveX + liveLabelW + (ci - 1) * (cellW + GAP) + cellW / 2, ly - cellW / 2)
                end
                ly = ly - cellW - 10
            end
        end
    end
    local rightW = liveLabelW + #LIVE_SIZES * (cellW + GAP) - GAP

    f:SetSize(liveX + rightW + PAD, math.max(leftH, -ly) + PAD)
    f:SetPoint("CENTER")
    ApplyScale()
end

SLASH_BNBBUTTONTEST1 = "/bnbbt"
SlashCmdList.BNBBUTTONTEST = function()
    if not f then Build(); f:Show(); return end
    f:SetShown(not f:IsShown())
end

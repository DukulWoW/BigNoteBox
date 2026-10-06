-- BigNoteBox UI/IconFramePicker.lua
-- Thumbnail grid for note icon frames (ALL-127), opened from the Icon Frame
-- button in NoteConfig's Appearance tab. Tabs All / Square / Circle (the
-- game-art registry BNB.IconFrames, filtered by its cat, like the sticky
-- background picker) and Edge borders (the existing LSM border list).
-- Every tile wears the note's own current icon (Dukul, 2026-09-28), so what
-- you pick is what you'll actually see. Picking one clears the other, since
-- a note only ever draws one.
--
--   IFP.Open(noteID, anchor, h)   anchor = the window to sit beside, top
--                                 aligned to its top (not BNB.PlaceBeside's
--                                 vertical-center rule; pass the config
--                                 window itself, not the button clicked).
--                                 h = { getFrame, setFrame, getBorder,
--                                       setBorder, getBright, getIcon,
--                                       strata }  strata nil = its own
--                                 getBright -> 0..2, defaults to 1.
--                                 getIcon -> the note's icon path/fileID.
--                                 Toggles.
--   IFP.Close() / IFP.IsOpenFor(noteID)

local BNB = BigNoteBox
if not BNB then return end
local L = BNB.L

local IFP = {}
BNB.IconFramePicker = IFP

local W, H       = 410, 460
local PAD        = 14
local CONTENT_Y  = 62
local FOOT_H     = 38
local COLS       = 5
local CELL       = 68
local LABEL_H    =  0   -- no name under a tile, it is the tooltip (ALL-156)
local GAP_X, GAP_Y = 8, 10
local GRID_W     = COLS * CELL + (COLS - 1) * GAP_X
local ROW_H      = CELL + LABEL_H + GAP_Y
local ICON_SZ    = 34
local WHITE      = "Interface\\Buttons\\White8x8"
local SEL_R, SEL_G, SEL_B = 0.40, 0.85, 0.40
local DEFAULT_ICON = "Interface\\Icons\\INV_Misc_Note_06"

-- Frame tabs filter by the registry's cat ("all" = every frame)
local TABS = {
    { id = "frame", cat = "all",    label = "ICON_FRAME_PICKER_TAB_ALL" },
    { id = "frame", cat = "square", label = "ICON_FRAME_PICKER_TAB_SQUARE" },
    { id = "frame", cat = "circle", label = "ICON_FRAME_PICKER_TAB_CIRCLE" },
    { id = "edge",                  label = "ICON_FRAME_PICKER_TAB_EDGE" },
}
local EDGE_TAB = 4

local function GetLSM() return LibStub and LibStub("LibSharedMedia-3.0", true) end
local function LSMBorderNames()
    local l = GetLSM()
    local seen = { ["None"] = true }
    local r = { "None" }
    if l then
        for _, v in ipairs(l:List("border")) do
            if not seen[v] then seen[v] = true; r[#r + 1] = v end
        end
    end
    return r
end

local _f, _sf, _ct, _revertBtn
local _tabIdx = 1   -- remembered for the session
local _tabVisual
local _tiles = {}
local _noteID, _h, _origFrame, _origBorder
local Render

local function PreviewIcon()
    local icon = _h and _h.getIcon and _h.getIcon()
    return (icon and icon ~= "") and icon or DEFAULT_ICON
end

local function Outline(parent, r, g, b, a, size)
    local o = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    o:SetAllPoints(parent)
    o:SetFrameLevel(parent:GetFrameLevel() + 5)
    o:SetBackdrop({ edgeFile = WHITE, edgeSize = size })
    o:SetBackdropBorderColor(r, g, b, a)
    o:EnableMouse(false)
    o:Hide()
    return o
end

local function FrameEntries(cat)
    local out = { { key = "none", label = L["STICKY_BG_NONE"] } }
    for _, e in ipairs(BNB.IconFrames.LIST) do
        if cat == "all" or e.cat == cat then out[#out + 1] = e end
    end
    return out
end

local function BorderEntries()
    local out = {}
    for _, name in ipairs(LSMBorderNames()) do
        out[#out + 1] = { key = name, label = name }
    end
    return out
end

local function CurTabID() return TABS[_tabIdx].id end

local function EntriesForTab()
    return CurTabID() == "frame" and FrameEntries(TABS[_tabIdx].cat) or BorderEntries()
end

local function CurKey()
    if CurTabID() == "frame" then
        local k = _h.getFrame()
        return (k and k ~= "") and k or "none"
    end
    local b = _h.getBorder()
    return (b and b ~= "") and b or "None"
end

local function Pick(entry)
    if not _h then return end
    if CurTabID() == "frame" then
        _h.setFrame(entry.key)
        if entry.key ~= "none" and _h.getBorder and _h.getBorder() ~= "None"
                and _h.getBorder() ~= "" then
            _h.setBorder("None")
        end
    else
        _h.setBorder(entry.key)
        if entry.key ~= "None" then
            local fk = _h.getFrame and _h.getFrame()
            if fk and fk ~= "" and fk ~= "none" then _h.setFrame("none") end
        end
    end
    Render()
end

local function MakeTile()
    local t = CreateFrame("Button", nil, _ct)
    t:SetSize(CELL, CELL + LABEL_H)
    t.box = CreateFrame("Frame", nil, t)
    t.box:SetPoint("TOPLEFT", t, "TOPLEFT", 0, 0)
    t.box:SetSize(CELL, CELL)
    t.icon = t.box:CreateTexture(nil, "ARTWORK")
    t.icon:SetSize(ICON_SZ, ICON_SZ)
    t.icon:SetPoint("CENTER", t.box, "CENTER", 0, 0)
    t.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    -- Edge border preview overlay (frame preview uses IconFrameLayer's own
    -- texture, icon._ifTex, created by IFL.Apply on first use)
    t.edge = BNB.CreateBackdropFrame("Frame", nil, t.box)
    t.edge:SetPoint("TOPLEFT",     t.icon, "TOPLEFT",     -2,  2)
    t.edge:SetPoint("BOTTOMRIGHT", t.icon, "BOTTOMRIGHT",  2, -2)
    t.edge:EnableMouse(false)
    t.edge:Hide()
    t.sel = Outline(t.box, SEL_R, SEL_G, SEL_B, 1, 2)
    t.hov = Outline(t.box, 1, 1, 1, 0.5, 1)
    t.lbl = t:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    t.lbl:SetPoint("TOPLEFT",  t.box, "BOTTOMLEFT",  0, -3)
    t.lbl:SetPoint("TOPRIGHT", t.box, "BOTTOMRIGHT", 0, -3)
    t.lbl:SetJustifyH("CENTER")
    t.lbl:SetWordWrap(false)
    t.lbl:Hide()   -- the name is the tooltip below the tile (ALL-156)
    t:SetScript("OnClick", function(self) Pick(self.entry) end)
    -- Double-click = pick and close: the first click already picked (ALL-141)
    t:SetScript("OnDoubleClick", function(self) Pick(self.entry); IFP.Close() end)
    t:SetScript("OnEnter", function(self)
        self.hov:Show()
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetText(self.entry.label, 1, 1, 1)
        GameTooltip:Show()
    end)
    t:SetScript("OnLeave", function(self)
        self.hov:Hide()
        GameTooltip:Hide()
    end)
    return t
end

local function PaintFrame(t, entry)
    t.edge:Hide()
    local def = entry.key ~= "none" and BNB.IconFrames.Get(entry.key)
    if def and BNB.IconFrameLayer then
        if not t.icon._ifTex then t.icon._ifTex = t.box:CreateTexture(nil, "OVERLAY") end
        local bright = _h.getBright and _h.getBright() or 1
        BNB.IconFrameLayer.Apply(t.icon, t.icon._ifTex, def, ICON_SZ, bright)
    elseif t.icon._ifTex then
        BNB.IconFrameLayer.HideTex(t.icon._ifTex)
        BNB.IconFrameLayer.SetShape(t.icon, nil)
    end
end

local function PaintEdge(t, entry)
    if t.icon._ifTex then BNB.IconFrameLayer.HideTex(t.icon._ifTex) end
    if BNB.IconFrameLayer then BNB.IconFrameLayer.SetShape(t.icon, nil) end
    if entry.key == "None" then t.edge:Hide(); return end
    local LSM = GetLSM()
    local path = LSM and LSM:Fetch("border", entry.key)
    if not path then t.edge:Hide(); return end
    pcall(function()
        t.edge:SetBackdrop({ edgeFile = path, edgeSize = 12,
            insets = { left = 0, right = 0, top = 0, bottom = 0 } })
        t.edge:SetBackdropColor(0, 0, 0, 0)
        t.edge:SetBackdropBorderColor(0.70, 0.70, 0.75, 0.85)
    end)
    t.edge:Show()
end

Render = function()
    if not _h then return end
    local list = EntriesForTab()
    local cur = CurKey()
    local isFrame = CurTabID() == "frame"
    local icon = PreviewIcon()
    for i, e in ipairs(list) do
        local t = _tiles[i]
        if not t then t = MakeTile(); _tiles[i] = t end
        t.entry = e
        local row = math.floor((i - 1) / COLS)
        t:ClearAllPoints()
        t:SetPoint("TOPLEFT", _ct, "TOPLEFT", ((i - 1) % COLS) * (CELL + GAP_X), -row * ROW_H)
        t.icon:SetTexture(icon)
        t.lbl:SetText(e.label)
        local on = (e.key == cur)
        t.sel:SetShown(on)
        t.lbl:SetTextColor(on and SEL_R or 0.9, on and SEL_G or 0.9, on and SEL_B or 0.9)
        t:Show()
        if isFrame then pcall(PaintFrame, t, e) else pcall(PaintEdge, t, e) end
    end
    for i = #list + 1, #_tiles do
        local t = _tiles[i]
        t:Hide()
        if t.icon._ifTex then BNB.IconFrameLayer.HideTex(t.icon._ifTex) end
        t.edge:Hide()
    end
    _sf:FinaliseHeight(math.ceil(#list / COLS) * ROW_H)
    _revertBtn:SetEnabled((_h.getFrame() ~= _origFrame) or (_h.getBorder() ~= _origBorder))
end

local function SelectTab(idx)
    _tabIdx = idx
    if _tabVisual then _tabVisual(idx) end
    if _h then Render() end
end

local function Build()
    if _f then return end
    local f, revertBtn, closeBtn = BNB.CreateToolWindow({
        name = "BigNoteBoxIconFramePicker", w = W, h = H, title = L["ICON_FRAME_PICKER_TITLE"],
        pad = PAD, cw = W - 2 * PAD, footH = FOOT_H,
        btn1 = L["STICKY_BGP_REVERT"], btn2 = L["CLOSE"],
        toplevel = true, escClose = true,
        onClose = function() IFP.Close() end,
        onHide  = function()
            _noteID, _h, _origFrame, _origBorder = nil, nil, nil, nil
            GameTooltip:Hide()
        end,
    })
    _f, _revertBtn = f, revertBtn
    f._defStrata = f:GetFrameStrata()
    revertBtn:SetScript("OnClick", function()
        if not _h then return end
        _h.setFrame(_origFrame)
        _h.setBorder(_origBorder)
        Render()
    end)
    closeBtn:SetScript("OnClick", function() IFP.Close() end)

    local labels = {}
    for i, t in ipairs(TABS) do labels[i] = L[t.label] end
    if f._isSkin then
        local ctrl = BNB.CreateSkinTabs(f, labels, function(idx) SelectTab(idx) end)
        ctrl.frame:SetPoint("TOPLEFT",  f, "TOPLEFT",  PAD, -38)
        ctrl.frame:SetPoint("TOPRIGHT", f, "TOPRIGHT", -PAD, -38)
        _tabVisual = function(idx) ctrl.SetVisual(idx) end
    else
        local tpl = "PanelTopTabButtonTemplate"
        local btns, last = {}, nil
        for i, text in ipairs(labels) do
            local btn = CreateFrame("Button", "BigNoteBoxIconFramePickerTab" .. i, f, tpl)
            btn:SetText(text)
            pcall(function()
                PanelTemplates_TabResize(btn, 8, nil, 60)
            end)
            btn:SetID(i)
            if last then btn:SetPoint("LEFT", last, "RIGHT", 2, 0)
            else btn:SetPoint("TOPLEFT", f, "TOPLEFT", 7, -25) end
            btn:SetScript("OnClick", function(self) SelectTab(self:GetID()) end)
            btns[i], last = btn, btn
        end
        PanelTemplates_SetNumTabs(f, #btns); f.numTabs = #btns
        _tabVisual = function(idx)
            for i, b in ipairs(btns) do
                if i == idx then PanelTemplates_SelectTab(b) else PanelTemplates_DeselectTab(b) end
            end
        end
    end

    _sf, _ct = BNB.CreateAutoScrollPanel(f, GRID_W, GRID_W)
    _sf:SetPoint("TOPLEFT",     f, "TOPLEFT",     PAD, -CONTENT_Y)
    _sf:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -(W - PAD - GRID_W), FOOT_H + 6)
end

function IFP.IsOpenFor(noteID)
    return _f and _f:IsShown() and _noteID == noteID or false
end

function IFP.Open(noteID, anchor, h)
    if IFP.IsOpenFor(noteID) then IFP.Close(); return end
    Build()
    _noteID, _h = noteID, h
    _origFrame  = h.getFrame()
    _origBorder = h.getBorder()
    local hasFrame  = _origFrame and _origFrame ~= "" and _origFrame ~= "none"
    local hasBorder = _origBorder and _origBorder ~= "" and _origBorder ~= "None"
    if hasBorder and not hasFrame then _tabIdx = EDGE_TAB
    elseif _tabIdx == EDGE_TAB then _tabIdx = 1 end
    -- Top-aligned beside anchor (its window, not a button inside it), unlike
    -- BNB.PlaceBeside's vertical-center placement: Dukul wanted this window's
    -- top level with the config window's top, 2026-09-28.
    _f:ClearAllPoints()
    if anchor and anchor.GetRight then
        local ar = anchor:GetRight() or 0
        if ar + 8 + W <= UIParent:GetWidth() then
            _f:SetPoint("TOPLEFT", anchor, "TOPRIGHT", 8, 0)
        else
            _f:SetPoint("TOPRIGHT", anchor, "TOPLEFT", -8, 0)
        end
    else
        _f:SetPoint("CENTER", UIParent, "CENTER", 0, 60)
    end
    _f:SetAlpha(BNB.WindowAlpha(_f))
    -- h.strata: the New note dialog sits over a FULLSCREEN_DIALOG dimmer (ALL-350)
    _f:SetFrameStrata(h.strata or _f._defStrata)
    _f:Show()
    _f:Raise()
    SelectTab(_tabIdx)
end

function IFP.Rebind(noteID, h)
    if not IFP.IsOpenFor(noteID) then return end
    _h = h
    Render()
end

function IFP.Close()
    if _f and _f:IsShown() then _f:Hide() end
end

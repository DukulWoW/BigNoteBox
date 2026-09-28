-- BigNoteBox UI/StickyBgPicker.lua
-- Thumbnail grid for sticky backgrounds (ALL-110 part 2b), opened from the
-- background row in sticky settings (UI/StickySettings.lua). Each tile is the
-- note itself shrunk: its size, colour, Colorize % and border, with one entry
-- of BNB.StickyBG drawn by BNB.BgLayer, so a tile looks the way the note will.
-- A click applies at once and the window stays open; Revert puts back the
-- background the note had when the grid opened (Dukul, 2026-09-27).
-- Entries flagged for the other client are not in BNB.StickyBG.LIST at all.
--
--   SBP.Open(noteID, anchor, h)  h = the settings row: { cfg = fn -> cfg,
--                                get = fn -> key, set = fn(key) }. Toggles.
--                                Not a sticky: noteID is any unique key and
--                                h.state = fn -> { w, h, inset, backdrop,
--                                br, bg, bb, ba } (see NoteState).
--   SBP.Rebind(noteID, h)        settings rebuilt for the same note
--   SBP.Refresh()                the key changed elsewhere (the arrows)
--   SBP.Close() / SBP.IsOpenFor(noteID)
-- Colour or size changes made while it is open are picked up by a light
-- poll (a signature of what the tiles draw), so no settings widget has to
-- call in. It closes itself when the sticky closes.

local BNB = BigNoteBox
if not BNB then return end
local L = BNB.L

local SBP = {}
BNB.StickyBgPicker = SBP

local W, H        = 490, 500
local PAD         = 14
local CONTENT_Y   = 62     -- below the tab row in both modes, as AlarmWindow
local FOOT_H      = 38
local SK_TITLE_H  = 28
local SK_TAB_GAP  = 10
local COLS        = 4
local CELL_W, CELL_H = 104, 72   -- the thumbnail box
local LABEL_H     = 16
local GAP_X, GAP_Y = 8, 10
local GRID_W      = COLS * CELL_W + (COLS - 1) * GAP_X
local ROW_H       = CELL_H + LABEL_H + GAP_Y
local POLL        = 0.25
local WHITE       = "Interface\\Buttons\\White8x8"
local SEL_R, SEL_G, SEL_B = 0.40, 0.85, 0.40   -- BNB green, Sidebar ACTIVE_R/G/B

-- Filter tabs, by look; cat = the registry's cat field
local TABS = {
    { cat = "all",        label = "STICKY_BGP_TAB_ALL" },
    { cat = "stone",      label = "STICKY_BGP_TAB_STONE" },
    { cat = "parchment",  label = "STICKY_BGP_TAB_PARCHMENT" },
    { cat = "scenery",    label = "STICKY_BGP_TAB_SCENERY" },
    { cat = "profession", label = "STICKY_BGP_TAB_PROFESSION" },
    -- The old bundled TGAs; tab named "BNB", not Classic, which reads as
    -- WoW Classic (Dukul 2026-09-27). Only with BigNoteBox_BGs
    { cat = "classic",    label = "STICKY_BGP_TAB_BNB" },
}

local _f, _sf, _ct, _revertBtn
local _tabs            -- the TABS shown
local _tabIdx = 1      -- remembered for the session
local _tabVisual       -- fn(idx), per mode
local _tiles  = {}
local _noteID, _h, _origKey, _sig
local Render           -- forward: tiles call it through Pick

local function Kit() return BNB.Sticky and BNB.Sticky._kit end

-- The key the grid marks: an unavailable saved key reads as "none", as the
-- settings button does
local function CurKey()
    return BNB.StickyBG.Get(_h.get()).key
end

-- What every tile copies from the open sticky; nil once it has closed.
-- A caller that is not a sticky (the Oracle settings page, ALL-69.5) passes
-- h.state() returning the same fields itself; nil closes the grid.
local function NoteState()
    if _h and _h.state then
        local st = _h.state()
        if st then st.cfg = st.cfg or _h.cfg() end
        return st
    end
    local K = Kit()
    local sf = K and _noteID and K.openFrames[_noteID]
    if not (sf and _h) then return nil end
    local w, h = sf:GetSize()
    local st = { cfg = _h.cfg(), w = math.max(w or 0, 40), h = math.max(h or 0, 30),
                 inset = sf._bgInset or 0, br = 1, bg = 1, bb = 1, ba = 0 }
    if sf.GetBackdrop then st.backdrop = sf:GetBackdrop() end
    if sf.GetBackdropBorderColor then
        local r, g, b, a = sf:GetBackdropBorderColor()
        -- The sticky's border alpha follows its opacity; a tile draws it solid
        st.br, st.bg, st.bb, st.ba = r or 1, g or 1, b or 1, (a and a > 0) and 1 or 0
    end
    return st
end

local function Signature(st, key)
    local c, bd = st.cfg, st.backdrop
    return table.concat({ key, math.floor(st.w), math.floor(st.h), st.inset,
        c.bgR or 0, c.bgG or 0, c.bgB or 0, c.bgColorOpacity or 1, c.bgBrightness or 0,
        tostring(bd and bd.edgeFile), bd and bd.edgeSize or 0,
        st.br, st.bg, st.bb, st.ba }, "|")
end

-- ── Tiles ─────────────────────────────────────────────────────────────────────
-- Drawn inside the box: the scroll frame clips anything outside it, which
-- cut the outline of the first and last column and the top row
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

local function Pick(key)
    if not _h then return end
    _h.set(key)
    Render(false)
end

local function MakeTile()
    local t = CreateFrame("Button", nil, _ct)
    t:SetSize(CELL_W, CELL_H + LABEL_H)
    t.box = CreateFrame("Frame", nil, t)
    t.box:SetPoint("TOPLEFT", t, "TOPLEFT", 0, 0)
    t.box:SetSize(CELL_W, CELL_H)
    -- The note at its real size, scaled into the box (Paint)
    t.mini = CreateFrame("Frame", nil, t.box, "BackdropTemplate")
    t.mini:SetPoint("CENTER", t.box, "CENTER", 0, 0)
    t.layer = BNB.BgLayer.Create(t.mini)
    t.sel = Outline(t.box, SEL_R, SEL_G, SEL_B, 1, 2)
    t.hov = Outline(t.box, 1, 1, 1, 0.5, 1)
    t.lbl = t:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    t.lbl:SetPoint("TOPLEFT",  t.box, "BOTTOMLEFT",  0, -3)
    t.lbl:SetPoint("TOPRIGHT", t.box, "BOTTOMRIGHT", 0, -3)
    t.lbl:SetJustifyH("CENTER")
    t.lbl:SetWordWrap(false)
    t:SetScript("OnClick", function(self) Pick(self.entry.key) end)
    t:SetScript("OnEnter", function(self)
        self.hov:Show()
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(self.entry.label, 1, 1, 1)
        GameTooltip:Show()
    end)
    t:SetScript("OnLeave", function(self)
        self.hov:Hide()
        GameTooltip:Hide()
    end)
    return t
end

-- Draws the tile's entry the way UI/StickyNote.lua draws the note: base =
-- note colour, art tinted by Colorize %, backdrop centre clear under art
local function Paint(t, st)
    local K, c, e = Kit(), st.cfg, t.entry
    local s = math.min(CELL_W / st.w, CELL_H / st.h)
    t.mini:SetScale(s)
    t.mini:SetSize(st.w, st.h)
    t.mini:SetBackdrop(st.backdrop or { bgFile = WHITE })
    t.mini:SetBackdropBorderColor(st.br, st.bg, st.bb, st.ba)
    local r = c.bgR or K.COL_BG[1]
    local g = c.bgG or K.COL_BG[2]
    local b = c.bgB or K.COL_BG[3]
    if e.file then
        BNB.BgLayer.Set(t.layer, e, st.inset)
        local tr, tg, tb = K.TintedBgColor(c)
        BNB.BgLayer.SetColors(t.layer, r, g, b, tr, tg, tb, c.bgBrightness)
        BNB.BgLayer.SetAlpha(t.layer, 1)
        t.mini:SetBackdropColor(0, 0, 0, 0)
    else
        BNB.BgLayer.Set(t.layer, nil)
        t.mini:SetBackdropColor(r, g, b, 1)
    end
end

local function EntriesFor(cat)
    local out = {}
    for _, e in ipairs(BNB.StickyBG.LIST) do
        if e.key == "none" or cat == "all" or e.cat == cat then out[#out + 1] = e end
    end
    return out
end

-- scrollToSel: a new tab or a fresh open; starts at the top, or at the
-- selected tile when it is below the view
Render = function(scrollToSel)
    local st = NoteState()
    if not st then SBP.Close(); return end
    local list = EntriesFor(_tabs[_tabIdx].cat)
    local cur  = CurKey()
    local selRow
    for i, e in ipairs(list) do
        local t = _tiles[i]
        if not t then t = MakeTile(); _tiles[i] = t end
        t.entry = e
        local row = math.floor((i - 1) / COLS)
        t:ClearAllPoints()
        t:SetPoint("TOPLEFT", _ct, "TOPLEFT", ((i - 1) % COLS) * (CELL_W + GAP_X), -row * ROW_H)
        t.lbl:SetText(e.label)
        local on = (e.key == cur)
        t.sel:SetShown(on)
        if on then
            selRow = row
            t.lbl:SetTextColor(SEL_R, SEL_G, SEL_B)
        else
            t.lbl:SetTextColor(0.9, 0.9, 0.9)
        end
        t:Show()
        pcall(Paint, t, st)
    end
    for i = #list + 1, #_tiles do _tiles[i]:Hide() end
    _sf:FinaliseHeight(math.ceil(#list / COLS) * ROW_H)
    _revertBtn:SetEnabled(_h.get() ~= _origKey)
    _sig = Signature(st, cur)

    if scrollToSel then
        _sf:SetVerticalScroll(0)
        if selRow and selRow > 0 then
            -- After FinaliseHeight (0.05s) has set the scroll range
            C_Timer.After(0.1, function()
                if not (_f and _f:IsShown()) then return end
                if (selRow + 1) * ROW_H > _sf:GetHeight() then
                    _sf:SetVerticalScroll(math.min(_sf:GetVerticalScrollRange() or 0, selRow * ROW_H))
                end
            end)
        end
    end
end

local function SelectTab(idx)
    _tabIdx = idx
    if _tabVisual then _tabVisual(idx) end
    if _h then Render(true) end
end

-- ── Window ───────────────────────────────────────────────────────────────────
local function Build()
    if _f then return end
    local f, revertBtn, closeBtn = BNB.CreateToolWindow({
        name = "BigNoteBoxStickyBgPicker", w = W, h = H, title = L["STICKY_BGP_TITLE"],
        pad = PAD, cw = W - 2 * PAD, footH = FOOT_H,
        btn1 = L["STICKY_BGP_REVERT"], btn2 = L["CLOSE"],
        toplevel = true, escClose = true,
        onClose = function() SBP.Close() end,
        onHide  = function()
            _noteID, _h, _origKey, _sig = nil, nil, nil, nil
            GameTooltip:Hide()
        end,
    })
    _f, _revertBtn = f, revertBtn
    revertBtn:SetScript("OnClick", function() if _origKey then Pick(_origKey) end end)
    closeBtn:SetScript("OnClick", function() SBP.Close() end)

    _tabs = {}
    for _, t in ipairs(TABS) do
        if t.cat ~= "classic" or BNB.StickyBG.HasClassic() then _tabs[#_tabs + 1] = t end
    end
    if _tabIdx > #_tabs then _tabIdx = 1 end
    local labels = {}
    for i, t in ipairs(_tabs) do labels[i] = L[t.label] end

    if f._isSkin then
        local ctrl = BNB.CreateSkinTabs(f, labels, function(idx) SelectTab(idx) end)
        ctrl.frame:SetPoint("TOPLEFT",  f, "TOPLEFT",  PAD, -(SK_TITLE_H + SK_TAB_GAP))
        ctrl.frame:SetPoint("TOPRIGHT", f, "TOPRIGHT", -PAD, -(SK_TITLE_H + SK_TAB_GAP))
        _tabVisual = function(idx) ctrl.SetVisual(idx) end
    else
        local tpl = (C_XMLUtil and C_XMLUtil.GetTemplateInfo
            and C_XMLUtil.GetTemplateInfo("PanelTopTabButtonTemplate"))
            and "PanelTopTabButtonTemplate" or "PanelTabButtonTemplate"
        local btns, last = {}, nil
        for i, text in ipairs(labels) do
            local btn = CreateFrame("Button", "BigNoteBoxStickyBgPickerTab" .. i, f, tpl)
            btn:SetText(text)
            -- Six tabs: tighter than the usual 15 / 70 so they fit the width
            pcall(function()
                if tpl == "PanelTopTabButtonTemplate" then PanelTemplates_TabResize(btn, 8, nil, 44)
                else PanelTemplates_TabResize(btn, 0) end
            end)
            btn:SetID(i)
            if last then btn:SetPoint("LEFT", last, "RIGHT", 2, 0)
            else btn:SetPoint("TOPLEFT", f, "TOPLEFT", 7, -25) end
            btn:SetScript("OnClick", function(self) SelectTab(self:GetID()) end)
            btns[i], last = btn, btn
        end
        -- Still wider than the window (a long translation): shrink every
        -- tab by the same factor so the last one stays inside
        local avail, total = W - 14 - 2 * (#btns - 1), 0
        for _, b in ipairs(btns) do total = total + b:GetWidth() end
        if total > avail then
            local k = avail / total
            for _, b in ipairs(btns) do
                local bw = math.floor(b:GetWidth() * k)
                pcall(function() PanelTemplates_TabResize(b, 0, bw) end)
            end
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

    -- Picks up colour, border and size changes made while the grid is open
    f:HookScript("OnUpdate", function(self, elapsed)
        self._t = (self._t or 0) + elapsed
        if self._t < POLL then return end
        self._t = 0
        local st = NoteState()
        if not st then SBP.Close(); return end
        if Signature(st, CurKey()) ~= _sig then Render(false) end
    end)
end

function SBP.IsOpenFor(noteID)
    return _f and _f:IsShown() and _noteID == noteID or false
end

function SBP.Open(noteID, anchor, h)
    if SBP.IsOpenFor(noteID) then SBP.Close(); return end
    BNB.StickyBG.LoadClassic()
    Build()
    _noteID, _h = noteID, h
    _origKey = h.get()
    BNB.PlaceBeside(_f, anchor, W)
    _f:SetAlpha(BNB.WindowAlpha(_f))
    _f:Show()
    _f:Raise()
    SelectTab(_tabIdx)
end

function SBP.Rebind(noteID, h)
    if not SBP.IsOpenFor(noteID) then return end
    _h = h
    Render(false)
end

function SBP.Refresh()
    if _f and _f:IsShown() and _h then Render(false) end
end

function SBP.Close()
    if _f and _f:IsShown() then _f:Hide() end
end

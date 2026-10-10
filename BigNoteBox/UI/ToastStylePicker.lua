-- BigNoteBox UI/ToastStylePicker.lua
-- Thumbnail grid for toast styles (ALL-401), like the sticky background and
-- icon frame pickers: two columns of real toast frames (BNB.ToastStyles
-- Apply + Fill), each shrunk into its tile, no name under a tile (it is the
-- tooltip). A click applies at once and the window stays open, a
-- double-click applies and closes, Revert puts back the style there was when
-- the grid opened. The Follow button clears the choice: "Follow my faction"
-- on Modules > Toasts, "As in Settings" for a note (Dukul, 2026-10-10).
-- The faction meta style has no tile: its Horde / Alliance art has its own.
--
--   TSP.Open(key, anchor, h)  toggles. key = any unique owner key ("global",
--                             "note:<id>"); anchor = the window to sit beside.
--                             h = { get = fn -> style key or nil (nil =
--                             following), set = fn(key or nil), noteID = the
--                             note whose content the tiles show (nil = the
--                             Test button's sample), follow = locale key of
--                             the Follow button, followTip = its tooltip,
--                             following = fn -> the style key nil stands
--                             for (nil = the default, the faction style) }
--   TSP.Rebind(key, h)        the owner switched note: follow it
--   TSP.Refresh()             the style changed elsewhere (the arrows)
--   TSP.Close(key) / TSP.IsOpenFor(key)   Close(nil) closes for any owner
--   TSP.Step(h, d, withFollow) the < > arrows beside a style name: one step
--                             through the styles (and "following" first when
--                             withFollow), wrapping; returns the new value

local BNB = BigNoteBox
if not BNB then return end
local L = BNB.L

local TSP = {}
BNB.ToastStylePicker = TSP

local PAD         = 14
local FOOT_H      = 38
local COLS        = 2
local CELL_W, CELL_H = 210, 86   -- the thumbnail box; a 281 x 115 toast fills it
local GAP_X, GAP_Y = 10, 10
local GRID_W      = COLS * CELL_W + (COLS - 1) * GAP_X
local ROW_H       = CELL_H + GAP_Y
local W, H        = GRID_W + PAD + 36, 560   -- 36 = room for the scroll bar
local WHITE       = "Interface\\Buttons\\White8x8"
local SEL_R, SEL_G, SEL_B = 0.40, 0.85, 0.40   -- BNB green, as the other pickers

local _f, _sf, _ct, _followBtn, _revertBtn
local _tiles = {}
local _key, _h, _orig, _origSet
local Render           -- forward: tiles call it through Pick

local function TS() return BNB.ToastStyles end

-- The styles a tile is drawn for: what this client can draw now, without
-- the faction meta style
local function Entries()
    local out = {}
    for _, e in ipairs(TS().List()) do
        if e.key ~= "faction" then out[#out + 1] = e end
    end
    return out
end

-- What every tile shows: the note's own toast content, or the sample
local function Content()
    local spec = BNB.ToastPreviewSpec and BNB.ToastPreviewSpec(_h and _h.noteID)
    return spec or { title = L["TOAST_TEST_1"], line2 = L["TOAST_TEST_BODY_1"] }
end

-- ── Tiles ─────────────────────────────────────────────────────────────────────
-- Drawn inside the box: the scroll frame clips anything outside it
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
    t:SetSize(CELL_W, CELL_H)
    t.box = CreateFrame("Frame", nil, t)
    t.box:SetAllPoints(t)
    -- A toast frame at its real size, scaled into the box (Paint)
    t.mini = BNB.CreateBackdropFrame("Frame", nil, t.box)
    t.mini:SetPoint("CENTER", t.box, "CENTER", 0, 0)
    t.mini:EnableMouse(false)
    TS().Build(t.mini)
    t.sel = Outline(t.box, SEL_R, SEL_G, SEL_B, 1, 2)
    t.hov = Outline(t.box, 1, 1, 1, 0.5, 1)
    t:SetScript("OnClick", function(self) Pick(self.entry.key) end)
    -- Double-click = pick and close: the first click already picked
    t:SetScript("OnDoubleClick", function(self) Pick(self.entry.key); TSP.Close() end)
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

-- The tile's style with the toast's content, full timer bar, no "+N more"
local function Paint(t, c)
    local ts, m = TS(), t.mini
    local def = ts.Get(t.entry.key)
    ts.Apply(m, def)
    ts.Fill(m, c)
    m:SetScale(math.min(CELL_W / def.w, CELL_H / def.h))
    if m._barW then m._bar:SetColorTexture(0.3, 0.75, 0.3, 0.9); m._bar:Show() end
    m._more:Hide()
end

local function Current() return _h and _h.get() end

-- scrollToSel: a fresh open; starts at the top, or at the selected tile
-- when it is below the view
Render = function(scrollToSel)
    if not _h then return end
    local list = Entries()
    local cur  = Current()
    -- Following, or a saved style with no tile (the faction meta style): the
    -- tile it draws as now is marked faintly
    local shown = TS().Resolve(cur or (_h.following and _h.following())).key
    local c = Content()
    local selRow
    for i, e in ipairs(list) do
        local t = _tiles[i]
        if not t then t = MakeTile(); _tiles[i] = t end
        t.entry = e
        local row = math.floor((i - 1) / COLS)
        t:ClearAllPoints()
        t:SetPoint("TOPLEFT", _ct, "TOPLEFT", ((i - 1) % COLS) * (CELL_W + GAP_X), -row * ROW_H)
        local on = (e.key == shown)
        t.sel:SetBackdropBorderColor(SEL_R, SEL_G, SEL_B, (e.key == cur) and 1 or 0.45)
        t.sel:SetShown(on)
        if on then selRow = row end
        t:Show()
        pcall(Paint, t, c)
    end
    for i = #list + 1, #_tiles do _tiles[i]:Hide() end
    _sf:FinaliseHeight(math.ceil(#list / COLS) * ROW_H)
    _revertBtn:SetEnabled(cur ~= _orig)
    _followBtn:SetEnabled(cur ~= nil)

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

-- ── Window ───────────────────────────────────────────────────────────────────
local function Tip(btn, title, text)
    btn:HookScript("OnEnter", function(self)
        local tt = title()
        if not tt then return end
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(tt, 1, 1, 1)
        local s = text and text()
        if s then GameTooltip:AddLine(s, 0.8, 0.8, 0.8, true) end
        GameTooltip:Show()
    end)
    btn:HookScript("OnLeave", function() GameTooltip:Hide() end)
end

local function Build()
    if _f then return end
    local cw = W - 2 * PAD
    local f, followBtn, revertBtn = BNB.CreateToolWindow({
        name = "BigNoteBoxToastStylePicker", w = W, h = H, title = L["TOAST_PICKER_TITLE"],
        pad = PAD, cw = cw, footH = FOOT_H,
        btn1 = L["TOAST_CM_DEFAULT"], btn2 = L["STICKY_BGP_REVERT"],
        toplevel = true, escClose = true,
        onClose = function() TSP.Close() end,
        onHide  = function()
            _key, _h, _orig, _origSet = nil, nil, nil, nil
            GameTooltip:Hide()
        end,
    })
    _f, _followBtn, _revertBtn = f, followBtn, revertBtn

    -- Three footer buttons: Follow, Revert, Close
    local bW = math.floor((cw - 16) / 3)
    followBtn:SetWidth(bW)
    revertBtn:SetWidth(bW)
    revertBtn:ClearAllPoints()
    revertBtn:SetPoint("LEFT", followBtn, "RIGHT", 8, 0)
    local closeBtn = BNB.CreateButton(nil, f, L["CLOSE"], bW, 26)
    closeBtn:SetPoint("LEFT", revertBtn, "RIGHT", 8, 0)
    BNB.TruncateButtonText(followBtn)

    followBtn:SetScript("OnClick", function() Pick(nil) end)
    revertBtn:SetScript("OnClick", function() if _origSet then Pick(_orig) end end)
    closeBtn:SetScript("OnClick", function() TSP.Close() end)
    Tip(followBtn, function() return _h and L[_h.follow or "TOAST_CM_DEFAULT"] end,
        function() return _h and _h.followTip and L[_h.followTip] end)

    local top = f._isSkin and BNB.TOOL_SKIN_TITLE_H or 32
    _sf, _ct = BNB.CreateAutoScrollPanel(f, GRID_W, GRID_W)
    _sf:SetPoint("TOPLEFT",     f, "TOPLEFT",     PAD, -(top + 10))
    _sf:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -(W - PAD - GRID_W), FOOT_H + 6)

    -- The note changed (title, icon, tl;dr, its style from the toast's menu)
    BNB.RegisterMessage("ToastStylePicker", "NoteChanged", function(_, id)
        if _h and _h.noteID == id and f:IsShown() then Render(false) end
    end)
    BNB.RegisterMessage("ToastStylePicker", "NoteDeleted", function(_, id)
        if _h and _h.noteID == id then TSP.Close() end
    end)
end

function TSP.IsOpenFor(key)
    return _f and _f:IsShown() and _key == key or false
end

function TSP.Open(key, anchor, h)
    if TSP.IsOpenFor(key) then TSP.Close(); return end
    Build()
    _key, _h = key, h
    _orig, _origSet = h.get(), true
    _followBtn:SetText(L[h.follow or "TOAST_CM_DEFAULT"])
    BNB.TruncateButtonText(_followBtn)
    BNB.PlaceBeside(_f, anchor, W)
    _f:SetAlpha(BNB.WindowAlpha(_f))
    BNB.SeatWindow(_f, _f._strata)
    _f:Show()
    _f:Raise()
    Render(true)
end

function TSP.Rebind(key, h)
    if not TSP.IsOpenFor(key) then return end
    _h = h
    _orig = h.get()
    Render(true)
end

function TSP.Refresh()
    if _f and _f:IsShown() and _h then Render(false) end
end

function TSP.Close(key)
    if _f and _f:IsShown() and (key == nil or key == _key) then _f:Hide() end
end

-- One arrow step from the current value: the styles in grid order (and
-- nil = following first, withFollow), wrapping. Following steps from the
-- style it shows now when nil is not in the cycle.
function TSP.Step(h, d, withFollow)
    local list = Entries()
    local cycle = {}
    if withFollow then cycle[1] = false end
    for _, e in ipairs(list) do cycle[#cycle + 1] = e.key end
    local cur = h.get()
    if cur == nil and not withFollow then
        cur = TS().Resolve(h.following and h.following()).key
    end
    local want = cur
    if want == nil then want = false end
    local idx
    for i, k in ipairs(cycle) do
        if k == want then idx = i; break end
    end
    -- A saved style not in the grid (the faction meta style, art this client
    -- lacks): the first step goes to the first / last entry
    if not idx then idx = (d > 0) and 0 or (#cycle + 1) end
    local nxt = cycle[(idx - 1 + d) % #cycle + 1]
    if nxt == false then nxt = nil end
    h.set(nxt)
    TSP.Refresh()
    return nxt
end

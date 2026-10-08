-- BigNoteBox UI/IconButton.lua
-- Layered icon buttons (ALL-214, ALL-210). Every square icon button in BNB is
-- one shared plate + border + hover glow with one symbol on top, so a new
-- button needs only its symbol, and the plate or border changes in one place.
--
-- Art (64x64, all on the same canvas), Assets\Buttons\:
--   Layers\bt-background, bt-button, bt-button-pressed, bt-hover,
--          bt-border-retail, bt-border-forever
--   Symbols\bt-<name>-normal, bt-<name>-press (the pressed symbol is its own
--          drawing, shifted into the pushed plate, not the normal one shrunk)
--
-- Normal look, bottom to top (Dukul, 2026-10-02 art test, /bnbbt):
--   normal   = background, button, symbol-normal, border
--   hover    = background, button, hover, symbol-normal, border
--   pressed  = background, button-pressed, symbol-press, border
--   disabled = normal, desaturated and darkened (DIM below)
-- Skin look (a skin window in skin mode): the box of BNB.CreateSkinButton and
-- the wysiwyg bar's icon buttons (preset fill, tooltip-style preset border,
-- corners scaled to the button, SkinBox), the symbol desaturated and tinted to the preset border x 2.2
-- like the skin toolbar icons; press darkens the plate and moves the symbol
-- 1 px. It follows preset changes through RegisterSkinButton. Symbols in
-- UNTINTED keep their own colours (random skin, Dukul 2026-10-03).
--
-- Public API:
--   BNB.CreateIconButton(parent, size, symbol, opts) -> Button
--     symbol : "close", "plus", "eye-open"... (file bt-<symbol>-normal/-press)
--     opts   : onClick (gets self, mouseButton), tip (string, or function
--              returning title, sub, extra), tipSub, tipAnchor ("ANCHOR_BOTTOM"),
--              tipWrap (wrap the sub line),
--              skin (true/false; nil = follow BigNoteBoxDB.skinMode; false
--              for buttons on Blizzard frames and stickies), name (global)
--   btn:SetSymbol(symbol)  swap the symbol (toggle buttons)
--   btn:SetDim(on)         disabled look while staying clickable
--   btn:SetEnabled(on)     Blizzard API; disabled buttons get the dim look
--
-- The button owns its OnEnter / OnLeave / OnMouseDown / OnMouseUp / OnEnable /
-- OnDisable scripts. Add behaviour with HookScript, never SetScript.
--------------------------------------------------------------------------------

local BNB = BigNoteBox

local BTN = "Interface\\AddOns\\BigNoteBox\\Assets\\Buttons\\"
local LAYERS  = BTN .. "Layers\\"
local SYMBOLS = BTN .. "Symbols\\"
local BORDER  = LAYERS .. (BNB.IsForever and "bt-border-forever" or "bt-border-retail")

-- Disabled: desaturate, then darken by these. The symbol goes darker than the
-- plate; Retail is a little brighter, its border is darker than Forever's (Dukul)
local DIM      = BNB.IsForever and 0.6  or 0.7
local DIM_SYM  = BNB.IsForever and 0.35 or 0.42
local SKIN_SYM_MULT = 2.2    -- symbol tint = preset border x this (skin toolbar icons)
local SKIN_DIM      = 0.45   -- skin look: symbol tint scale while disabled
local UNTINTED = { skinchange = true }

-- The skin box: BNB.SetBackdrop's tooltip-style border, with the corner size
-- half the button (at most 14, the window size), so the four corners of a
-- 14-18 px button no longer overlap into a crosshatch (Dukul 2026-10-03, I6).
local _boxes = {}
local function SkinBox(size)
    local edge = math.min(14, math.floor(size / 2))
    local box = _boxes[edge]
    if not box then
        local ins = math.max(1, math.floor(edge * 3 / 14 + 0.5))
        box = { bgFile = "Interface\\Buttons\\White8x8",
                edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = edge,
                insets = { left = ins, right = ins, top = ins, bottom = ins } }
        _boxes[edge] = box
    end
    return box
end

local function Layer(btn, sub, file)
    local t = btn:CreateTexture(nil, "ARTWORK", nil, sub)
    t:SetAllPoints()
    if file then t:SetTexture(file) end
    return t
end

-- A tip function may return a third, dimmer line (a key or right-click hint)
local function ShowTip(self)
    local tip, sub, extra = self._tip, self._tipSub, nil
    if type(tip) == "function" then tip, sub, extra = tip(self) end
    if not tip then return end
    GameTooltip:SetOwner(self, self._tipAnchor or "ANCHOR_BOTTOM")
    GameTooltip:AddLine(tip, 1, 1, 1)
    if sub then GameTooltip:AddLine(sub, 0.78, 0.78, 0.78, self._tipWrap) end
    if extra then GameTooltip:AddLine(extra, 0.55, 0.55, 0.55) end
    GameTooltip:Show()
end

-- Normal look ---------------------------------------------------------------
local function RefreshArt(self)
    local dim  = self._dim or not self:IsEnabled()
    local down = self._down and not dim
    local over = self._over and not dim
    self._plate:SetTexture(LAYERS .. (down and "bt-button-pressed" or "bt-button"))
    self._sym:SetTexture(SYMBOLS .. "bt-" .. self._symbol .. (down and "-press" or "-normal"))
    self._hover:SetShown(over and not down)
    local d, ds = dim and DIM or 1, dim and DIM_SYM or 1
    for _, t in ipairs(self._plateLayers) do
        t:SetDesaturated(dim)
        t:SetVertexColor(d, d, d)
    end
    self._sym:SetDesaturated(dim)
    self._sym:SetVertexColor(ds, ds, ds)
end

-- Skin look -----------------------------------------------------------------
local function SkinColours()
    local p = BNB.GetSkinPreset()
    local r, g, b = BNB.SkinButtonOf(p)
    return p, r, g, b
end

local function RefreshSkin(self)
    local dim  = self._dim or not self:IsEnabled()
    local down = self._down and not dim
    local p, r, g, b = SkinColours()
    local br, bg_, bb = BNB.SkinBorderOf(p)
    local m = down and 0.7 or 1
    self:SetBackdropColor(r * m, g * m, b * m, 0.92)
    self:SetBackdropBorderColor(br, bg_, bb, 1)
    self._hl:SetShown(self._over and not dim and not down)
    -- The press symbol is drawn dark (it sits in the pushed plate's shadow), so
    -- tinting it would come out near black: the skin look moves the normal one
    self._sym:SetTexture(SYMBOLS .. "bt-" .. self._symbol .. "-normal")
    local px = down and 1 or 0
    self._sym:ClearAllPoints()
    self._sym:SetPoint("TOPLEFT", px, -px)
    self._sym:SetPoint("BOTTOMRIGHT", px, -px)
    if UNTINTED[self._symbol] then
        local d = dim and DIM_SYM or 1
        self._sym:SetDesaturated(dim)
        self._sym:SetVertexColor(d, d, d)
        return
    end
    local s = SKIN_SYM_MULT * (dim and SKIN_DIM or 1)
    self._sym:SetDesaturated(true)
    self._sym:SetVertexColor(math.min(1, br * s), math.min(1, bg_ * s), math.min(1, bb * s))
end

local function Refresh(self)
    if self._skin then RefreshSkin(self) else RefreshArt(self) end
end

function BNB.CreateIconButton(parent, size, symbol, opts)
    opts = opts or {}
    local skin = opts.skin
    if skin == nil then skin = BigNoteBoxDB and BigNoteBoxDB.skinMode and true or false end

    local btn = CreateFrame("Button", opts.name, parent, skin and "BackdropTemplate" or nil)
    btn:SetSize(size, size)
    btn._skin, btn._symbol = skin, symbol
    btn._tip, btn._tipSub, btn._tipAnchor = opts.tip, opts.tipSub, opts.tipAnchor
    btn._tipWrap = opts.tipWrap

    if skin then
        local box = SkinBox(size)
        btn:SetBackdrop(box)   -- the box shape once; Refresh sets the colours
        local ins = box.insets.left
        local hl = btn:CreateTexture(nil, "ARTWORK", nil, 1)
        hl:SetPoint("TOPLEFT", ins, -ins)   -- inside the border, as CreateSkinButton
        hl:SetPoint("BOTTOMRIGHT", -ins, ins)
        hl:SetColorTexture(1, 1, 1, 0.10)
        hl:Hide()
        btn._hl = hl
        btn._sym = Layer(btn, 2)
        BNB.RegisterSkinButton(function() Refresh(btn) end, btn)
        btn:HookScript("OnShow", Refresh)
    else
        local bg = Layer(btn, 0, LAYERS .. "bt-background")
        btn._plate = Layer(btn, 1)
        btn._hover = Layer(btn, 2, LAYERS .. "bt-hover")
        btn._sym   = Layer(btn, 3)
        local border = Layer(btn, 4, BORDER)
        btn._plateLayers = { bg, btn._plate, btn._hover, border }
    end

    if opts.onClick then btn:SetScript("OnClick", opts.onClick) end
    btn:SetScript("OnEnter", function(self) self._over = true; Refresh(self); ShowTip(self) end)
    btn:SetScript("OnLeave", function(self)
        self._over, self._down = false, false
        Refresh(self)
        if GameTooltip:IsOwned(self) then GameTooltip:Hide() end
    end)
    btn:SetScript("OnMouseDown", function(self) self._down = true; Refresh(self) end)
    btn:SetScript("OnMouseUp",   function(self) self._down = false; Refresh(self) end)
    btn:SetScript("OnEnable",  Refresh)
    btn:SetScript("OnDisable", Refresh)
    -- A click that hides the button (a page change, a closed window) never
    -- sends OnLeave, so it would come back showing hover or pressed
    btn:HookScript("OnHide", function(self)
        self._over, self._down = false, false
        Refresh(self)
    end)

    function btn:SetSymbol(name)
        if name and name ~= self._symbol then self._symbol = name; Refresh(self) end
    end
    function btn:SetDim(on)
        on = on and true or false
        if on ~= self._dim then self._dim = on; Refresh(self) end
    end
    -- Redraw after a change the button cannot see (a tooltip owner, a rebuilt row)
    btn.RefreshLook = Refresh
    -- Re-show the tooltip, e.g. after a click changed what it says
    btn.RefreshTip = function(self) if self:IsMouseOver() then ShowTip(self) end end

    Refresh(btn)
    return btn
end

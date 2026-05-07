-- BigNoteBox UI/Widgets.lua — Shared widget construction helpers
-- Visual style matches BCB: dark metal backdrop, UIPanelButtonTemplate buttons,
-- ScrollFrameTemplate scrollbars with smart hide/show.

local BNB = BigNoteBox

--------------------------------------------------------------------------------
-- BACKDROP DEFINITIONS
-- White8x8 bg + Tooltip border — present on all WoW versions.
-- Mirrors the BCB / ButtonFrameTemplate dark look.
--------------------------------------------------------------------------------
local BACKDROP_FRAME = {
    bgFile   = "Interface\\Buttons\\White8x8",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile     = false, tileSize = 0, edgeSize = 14,
    insets   = { left = 3, right = 3, top = 3, bottom = 3 },
}
local BACKDROP_INSET = {
    bgFile   = "Interface\\Buttons\\White8x8",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile     = false, tileSize = 0, edgeSize = 10,
    insets   = { left = 2, right = 2, top = 2, bottom = 2 },
}

function BNB.SetBackdrop(frame, r, g, b, a, bR, bG, bB, bA)
    if frame.SetBackdrop then
        frame:SetBackdrop(BACKDROP_FRAME)
        frame:SetBackdropColor(r or 0.06, g or 0.06, b or 0.06, a or 0.97)
        frame:SetBackdropBorderColor(bR or 0.40, bG or 0.40, bB or 0.40, bA or 1)
    end
end

function BNB.SetBackdropLight(frame)
    if frame.SetBackdrop then
        frame:SetBackdrop(BACKDROP_INSET)
        frame:SetBackdropColor(0.08, 0.08, 0.10, 0.92)
        frame:SetBackdropBorderColor(0.28, 0.28, 0.28, 0.9)
    end
end

function BNB.SetBackdropDark(frame)
    if frame.SetBackdrop then
        frame:SetBackdrop(BACKDROP_INSET)
        frame:SetBackdropColor(0.03, 0.03, 0.04, 0.98)
        frame:SetBackdropBorderColor(0.30, 0.30, 0.30, 1)
    end
end

--------------------------------------------------------------------------------
-- ENSURE BACKDROP MIXIN
--------------------------------------------------------------------------------
function BNB.EnsureBackdrop(frame)
    if not frame.SetBackdrop then
        pcall(function() Mixin(frame, BackdropTemplateMixin) end)
    end
end

function BNB.CreateBackdropFrame(frameType, name, parent, extraTemplate)
    local tpl = "BackdropTemplate" .. (extraTemplate and ("," .. extraTemplate) or "")
    local f = CreateFrame(frameType or "Frame", name, parent, tpl)
    BNB.EnsureBackdrop(f)
    return f
end

--------------------------------------------------------------------------------
-- UI PANEL BUTTON  (BCB style: UIPanelButtonTemplate — the standard WoW button)
-- Returns: button
--------------------------------------------------------------------------------
function BNB.CreateButton(name, parent, text, w, h)
    if BigNoteBoxDB and BigNoteBoxDB.skinMode then
        return BNB.CreateSkinButton(name, parent, text, w, h)
    end
    local btn = CreateFrame("Button", name, parent, "UIPanelButtonTemplate")
    btn:SetSize(w or 80, h or 22)
    btn:SetText(text or "")
    return btn
end

--------------------------------------------------------------------------------
-- TINT BUTTON  (skin mode only)
-- Recolours all texture regions of a UIPanelButtonTemplate-based button to
-- match the current skin preset's border colour, and sets the label white.
-- Call after button creation, and again on OnShow if preset may change.
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
-- SKIN BUTTON  (skin mode only)
-- A backdrop-based Button that matches the current preset and never uses
-- UIPanelButtonTemplate — avoiding NineSlice vertex-colour issues entirely.
-- w, h, fontSize default to 80, 22, 13.
-- Registered with ApplyMainWindowSkin so it updates on preset change.
--------------------------------------------------------------------------------
function BNB.CreateSkinButton(name, parent, text, w, h, fontSize)
    w = w or 80; h = h or 22; fontSize = fontSize or 13

    local btn = CreateFrame("Button", name, parent, "BackdropTemplate")
    btn:SetSize(w, h)

    local function ApplyPreset()
        local p = BNB.GetSkinPreset and BNB.GetSkinPreset()
        if not p then return end
        local r = math.min(1, p.r + p.lift * 1.5)
        local g = math.min(1, p.g + p.lift * 1.5)
        local b = math.min(1, p.b + p.lift * 1.5)
        local br, bg_, bb = BNB.SkinBorderOf(p)
        BNB.SetBackdrop(btn, r, g, b, 0.92, br, bg_, bb, 1)
        btn._br, btn._bg_, btn._bb = r, g, b
    end
    ApplyPreset()

    -- Highlight overlay on mouse over — inset 2px to stay inside the border
    local hl = btn:CreateTexture(nil, "HIGHLIGHT")
    hl:SetPoint("TOPLEFT", btn, "TOPLEFT", 2, -2)
    hl:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -2, 2)
    hl:SetColorTexture(1, 1, 1, 0.10)

    -- Darken on mouse down, restore on mouse up
    btn:SetScript("OnMouseDown", function(self)
        if self.SetBackdropColor then
            self:SetBackdropColor(
                (self._br or 0.10) * 0.70,
                (self._bg_ or 0.10) * 0.70,
                (self._bb or 0.12) * 0.70, 0.95)
        end
    end)
    btn:SetScript("OnMouseUp", function(self)
        if self.SetBackdropColor then
            self:SetBackdropColor(self._br or 0.10, self._bg_ or 0.10, self._bb or 0.12, 0.92)
        end
    end)

    -- Label in OVERLAY — above backdrop, unaffected by highlight.
    -- Starts with GameFontNormal (always safe) and upgrades to the TTF body font
    -- once BNB.InitFonts has run. On first login, CreateSkinButton can run before
    -- PLAYER_LOGIN / InitFonts — if we SetFont to a TTF path before the renderer
    -- has cached the file, the label renders blank. This defers the swap so the
    -- button always shows text, even on the very first session open.
    local lbl = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    lbl:SetAllPoints()
    lbl:SetJustifyH("CENTER")
    lbl:SetJustifyV("MIDDLE")
    lbl:SetTextColor(1, 1, 1)
    lbl:SetText(text or "")
    btn._lbl = lbl

    local function ApplyLabelFont()
        if not BNB._fontsInitialised then return false end
        local ok = pcall(function()
            local path = BNB.GetBodyFont and select(1, BNB.GetBodyFont())
            if path then lbl:SetFont(path, fontSize, "") end
        end)
        return ok
    end

    -- Try once now (works on every session after the first, once InitFonts has run).
    if not ApplyLabelFont() then
        -- Not ready yet — retry when the button is first shown, and again shortly
        -- after in case InitFonts is still pending on that exact frame.
        local tried = false
        btn:HookScript("OnShow", function()
            if tried then return end
            if ApplyLabelFont() then tried = true; return end
            C_Timer.After(0.1, function()
                if ApplyLabelFont() then tried = true end
            end)
        end)
    end

    -- Mimic standard Button API
    function btn:SetText(t) lbl:SetText(t or "") end
    function btn:GetFontString() return lbl end

    -- Re-skin when preset changes (triggered by ApplyMainWindowSkin).
    btn:HookScript("OnShow", ApplyPreset)
    BNB.RegisterSkinButton(ApplyPreset)

    return btn
end

-- Legacy stub kept for any call sites that still reference TintButton.
-- In skin mode buttons should be created with CreateSkinButton instead.
function BNB.TintButton(btn) end

--------------------------------------------------------------------------------
-- ICON BUTTON — small square with a texture, no text
-- Used for cog (config) in the title bar.
--------------------------------------------------------------------------------
function BNB.CreateIconButton(name, parent, texturePath, size)
    size = size or 20
    local btn = CreateFrame("Button", name, parent)
    btn:SetSize(size, size)

    local icon = btn:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints()
    if texturePath then icon:SetTexture(texturePath) end
    btn._icon = icon

    local hi = btn:CreateTexture(nil, "HIGHLIGHT")
    hi:SetAllPoints()
    hi:SetColorTexture(1, 1, 1, 0.18)

    return btn
end

--------------------------------------------------------------------------------
-- SMART SCROLL FRAME  (mirrors BCB's CreateSmartScrollFrame)
-- "ScrollFrameTemplate" — modern scrollbar inside frame bounds.
-- Scrollbar auto-hides when content fits.
-- Caller anchors the scroll frame; this function only sets up the child and bar.
--
-- Returns: scrollFrame, scrollChild
--------------------------------------------------------------------------------
function BNB.CreateSmartScrollFrame(name, parent)
    local sf = CreateFrame("ScrollFrame", name, parent, "ScrollFrameTemplate")

    local scrollBar = sf.ScrollBar   -- exists on ScrollFrameTemplate

    local child = CreateFrame("Frame", name and (name .. "Child") or nil, sf)
    child:SetWidth(sf:GetWidth())
    child:SetHeight(1)
    sf:SetScrollChild(child)

    -- Hide scrollbar when content fits; restore when scrollable.
    -- Alpha-only — never Show/Hide, which fights ScrollFrameTemplate.
    if scrollBar then
        scrollBar:SetAlpha(0)
        sf:HookScript("OnScrollRangeChanged", function(_, _, yRange)
            scrollBar:SetAlpha((yRange or 0) > 1 and 1.0 or 0)
        end)
    end

    function sf:UpdateScrollbar()
        C_Timer.After(0.05, function()
            if not sf:IsVisible() then return end
            local contentH = child:GetHeight()
            local visibleH = sf:GetHeight()
            if scrollBar then
                scrollBar:SetAlpha(contentH > visibleH + 2 and 1.0 or 0)
            end
        end)
    end

    sf:SetScript("OnSizeChanged", function(self)
        child:SetWidth(self:GetWidth())
    end)

    return sf, child
end

--------------------------------------------------------------------------------
-- SCROLLED EDIT BOX  (multi-line body editor)
-- Uses ScrollFrameTemplate.  Returns: scrollFrame, editBox
--------------------------------------------------------------------------------
function BNB.CreateScrolledEditBox(name, parent, fontSize)
    local sf = CreateFrame("ScrollFrame", name, parent, "ScrollFrameTemplate")

    local eb = CreateFrame("EditBox", name and (name .. "EditBox") or nil, sf)
    eb:SetMultiLine(true)
    eb:SetAutoFocus(false)
    eb:SetFontObject("GameFontNormal")
    if fontSize then
        local fontPath = eb:GetFont()
        if fontPath then pcall(function() eb:SetFont(fontPath, fontSize, "") end) end
    end
    eb:SetTextInsets(6, 6, 4, 4)
    eb:SetMaxLetters(0)
    eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

    sf:SetScrollChild(eb)

    local scrollBar = sf.ScrollBar

    -- Hide scrollbar when content fits; restore when scrollable.
    -- Alpha-only — never Show/Hide, which fights ScrollFrameTemplate.
    if scrollBar then
        scrollBar:SetAlpha(0)
        sf:HookScript("OnScrollRangeChanged", function(_, _, yRange)
            scrollBar:SetAlpha((yRange or 0) > 1 and 1.0 or 0)
        end)
    end

    ---------------------------------------------------------------------------
    -- Width sync — sf has no anchors at creation time.
    -- When the scrollbar is visible, subtract its width so the editbox
    -- matches the actual visible text area.
    ---------------------------------------------------------------------------
    local function SyncWidth()
        local w = sf:GetWidth()
        if not w or w <= 0 then return end
        if scrollBar and scrollBar:IsShown() then
            local sbW = scrollBar:GetWidth()
            if sbW and sbW > 0 then w = w - sbW end
        end
        eb:SetWidth(w)
    end

    sf:SetScript("OnSizeChanged", function(self) SyncWidth() end)
    sf:HookScript("OnShow", function()
        C_Timer.After(0, function() SyncWidth() end)
    end)

    function sf:UpdateScrollbar()
        -- ScrollFrameTemplate manages scrollbar natively.
        -- Re-sync width in case scrollbar appeared/disappeared.
        C_Timer.After(0.05, function()
            if sf:IsVisible() then SyncWidth() end
        end)
    end

    sf:SetScript("OnMouseDown", function(self, btn)
        if btn == "LeftButton" then eb:SetFocus() end
    end)

    -- Scroll to top on SetText (note load).
    local _isSetTextCall = false
    hooksecurefunc(eb, "SetText", function()
        _isSetTextCall = true
        C_Timer.After(0, function()
            if _isSetTextCall then
                SyncWidth()
                sf:SetVerticalScroll(0)
                _isSetTextCall = false
            end
        end)
    end)

    -- Re-sync width on text change (scrollbar may appear/disappear).
    eb:SetScript("OnTextChanged", function(self)
        C_Timer.After(0.05, function()
            if sf:IsVisible() then SyncWidth() end
        end)
    end)

    -- Cursor follow — scroll the parent to keep the caret visible as the user types.
    eb:SetScript("OnCursorChanged", function(self, _, y, _, h)
        y = -y
        local offset = sf:GetVerticalScroll()
        if y < offset then
            sf:SetVerticalScroll(y)
        else
            local bottom = y + (h or 16) - sf:GetHeight()
            if bottom > offset then
                sf:SetVerticalScroll(bottom)
            end
        end
    end)

    return sf, eb
end

--------------------------------------------------------------------------------
-- PLACEHOLDER EDITBOX
-- pcall(SetTextColor) throughout — safe on all clients, no GetFontString().
--------------------------------------------------------------------------------
function BNB.AddPlaceholder(eb, text, r, g, b)
    r, g, b = r or 0.45, g or 0.45, b or 0.45

    local function setColor(self, cr, cg, cb)
        pcall(function() self:SetTextColor(cr, cg, cb) end)
    end

    local function showPlaceholder()
        if eb:GetText() == "" and not eb:HasFocus() then
            eb:SetText(text)
            setColor(eb, r, g, b)
            eb._showingPlaceholder = true
        end
    end

    local function hidePlaceholder()
        if eb._showingPlaceholder then
            eb:SetText("")
            setColor(eb, 1, 1, 1)
            eb._showingPlaceholder = false
        end
    end

    eb:SetScript("OnEditFocusGained", function() hidePlaceholder() end)
    eb:SetScript("OnEditFocusLost",   function() showPlaceholder() end)

    if eb:GetText() == "" then showPlaceholder() end

    eb.GetRealText = function(self)
        if self._showingPlaceholder then return "" end
        return self:GetText()
    end
    eb.SetRealText = function(self, t)
        hidePlaceholder()
        self:SetText(t or "")
        setColor(self, 1, 1, 1)
        if not t or t == "" then showPlaceholder() end
    end
end

--------------------------------------------------------------------------------
-- DIVIDER LINE
-- In skin mode: ignores caller r/g/b and uses the preset border colour instead,
-- then registers the texture for live recolouring on preset/brightness change.
-- The caller's alpha value is preserved as the registration alpha.
--------------------------------------------------------------------------------
function BNB.CreateDivider(parent, orientation, r, g, b, a)
    local t = parent:CreateTexture(nil, "ARTWORK")
    local alpha = a or 1
    if BigNoteBoxDB and BigNoteBoxDB.skinMode
       and BNB.GetSkinPreset and BNB.SkinBorderOf and BNB.RegisterSkinRule then
        local p = BNB.GetSkinPreset()
        local br, bg_, bb = BNB.SkinBorderOf(p)
        t:SetColorTexture(br, bg_, bb, alpha)
        BNB.RegisterSkinRule(t, alpha)
    else
        t:SetColorTexture(r or 0.25, g or 0.25, b or 0.25, alpha)
    end
    if orientation == "VERTICAL" then t:SetWidth(1)
    else t:SetHeight(1) end
    return t
end

--------------------------------------------------------------------------------
-- SLIDER  — matches BCB's Config.CreateSlider exactly.
--
-- Retail:  MinimalSliderWithSteppersTemplate (the modern look).
--
-- Usage:
--   local s = BNB.CreateSlider(parent, label, min, max, current, default,
--                               onChange, formatFn)
--   s:SetPoint(...)   -- caller anchors; widget is SetHeight(36)
--   s:SetWidth(...)   -- caller sets width
--
-- onChange(value)  fires only when the integer value actually changes.
-- formatFn(value)  optional; returns the display string for the value label.
-- default          optional; appended to label as "(Default: N)" hint.
--
-- Returns the container frame.  container.Slider is the raw Slider widget.
-- container:SetValue(n) — programmatic set.
--------------------------------------------------------------------------------
function BNB.CreateSlider(parent, label, mn, mx, cur, def, onChange, fmt)
    local h = CreateFrame("Frame", nil, parent)
    h:SetHeight(36)

    local displayLabel = label
    if def ~= nil then
        displayLabel = label .. "  |cff666666(Default: " .. tostring(def) .. ")|r"
    end

    local lbl = h:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    lbl:SetJustifyH("LEFT")
    lbl:SetPoint("LEFT",  h, "LEFT",   0, 0)
    lbl:SetPoint("RIGHT", h, "CENTER", -40, 0)
    lbl:SetText(displayLabel)

    local sl = CreateFrame("Slider", nil, h, "MinimalSliderWithSteppersTemplate")
    sl:SetPoint("LEFT",  h, "CENTER", -40, 0)
    sl:SetPoint("RIGHT", h, "RIGHT",   0, 0)
    sl:SetHeight(20)

    local fF = fmt or function(v) return tostring(math.floor(v)) end

    sl:Init(cur, mn, mx, mx - mn, {
        [MinimalSliderWithSteppersMixin.Label.Right] =
            CreateMinimalSliderFormatter(
                MinimalSliderWithSteppersMixin.Label.Right,
                function(v)
                    return WHITE_FONT_COLOR:WrapTextInColorCode(fF(v))
                end),
    })

    local trackedVal = cur
    sl:RegisterCallback(
        MinimalSliderWithSteppersMixin.Event.OnValueChanged,
        function(_, v)
            trackedVal = math.floor(v)
            if onChange then onChange(trackedVal) end
        end)

    h:EnableMouseWheel(true)
    h:SetScript("OnMouseWheel", function(_, delta)
        local newVal = math.max(mn, math.min(mx, trackedVal + delta))
        if newVal ~= trackedVal then sl:SetValue(newVal) end
    end)

    h.Slider = sl
    function h:SetValue(v)
        trackedVal = math.floor(v)
        sl:SetValue(trackedVal)
    end

    return h
end

--------------------------------------------------------------------------------
-- FLOAT SLIDER
-- Like CreateSlider but supports fractional step values (e.g. 0.05).
-- step     : snap increment (e.g. 0.05)
-- fmt      : optional display formatter, defaults to "%.2f"
--------------------------------------------------------------------------------
function BNB.CreateFloatSlider(parent, label, mn, mx, cur, step, def, onChange, fmt)
    step = step or 0.05
    local fF = fmt or function(v) return string.format("%.2f", v) end

    local function Snap(v)
        return math.floor(v / step + 0.5) * step
    end

    local h = CreateFrame("Frame", nil, parent)
    h:SetHeight(36)

    local displayLabel = label or ""
    if def ~= nil then
        displayLabel = displayLabel .. "  |cff666666(Default: " .. fF(def) .. ")|r"
    end

    local lbl = h:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    lbl:SetJustifyH("LEFT")
    lbl:SetPoint("LEFT",  h, "LEFT",   0, 0)
    lbl:SetPoint("RIGHT", h, "CENTER", -40, 0)
    lbl:SetText(displayLabel)

    local sl = CreateFrame("Slider", nil, h, "MinimalSliderWithSteppersTemplate")
    sl:SetPoint("LEFT",  h, "CENTER", -40, 0)
    sl:SetPoint("RIGHT", h, "RIGHT", -36, 0)  -- leave room for the right value label
    sl:SetHeight(20)

    sl:Init(cur, mn, mx, (mx - mn) / step, {
        [MinimalSliderWithSteppersMixin.Label.Right] =
            CreateMinimalSliderFormatter(
                MinimalSliderWithSteppersMixin.Label.Right,
                function(v) return WHITE_FONT_COLOR:WrapTextInColorCode(fF(Snap(v))) end),
    })

    local trackedVal = Snap(cur)
    sl:RegisterCallback(
        MinimalSliderWithSteppersMixin.Event.OnValueChanged,
        function(_, v)
            local newV = Snap(v)
            if math.abs(newV - trackedVal) > 0.001 then
                trackedVal = newV
                if onChange then onChange(trackedVal) end
            end
        end)

    h:EnableMouseWheel(true)
    h:SetScript("OnMouseWheel", function(_, delta)
        local newVal = math.max(mn, math.min(mx, Snap(trackedVal + delta * step)))
        sl:SetValue(newVal)
    end)

    h.Slider = sl
    function h:SetValue(v)
        trackedVal = Snap(v)
        sl:SetValue(trackedVal)
    end

    return h
end
-- 24-color grid: 8 columns × 3 rows.
-- Row 1: class colors (Death Knight → Paladin)
-- Row 2: class colors (Priest → Warrior) + 4 BNB accent colors
-- Row 3: item quality colors + BNB accent gold + BNB teal
-- label: concise color description used in tooltips.
-- Tooltip format: "Description (R:255 G:255 B:255)"
--------------------------------------------------------------------------------
BNB.COLOR_PALETTE = {
    -- Row 1 — white + black first, then class colors
    { r=1.000, g=1.000, b=1.000, label="White"           },
    { r=0.000, g=0.000, b=0.000, label="Black"           },
    { r=0.769, g=0.118, b=0.227, label="Crimson Red"     },  -- Death Knight
    { r=0.639, g=0.188, b=0.788, label="Deep Purple"     },  -- Demon Hunter
    { r=1.000, g=0.486, b=0.039, label="Burnt Orange"    },  -- Druid
    { r=0.200, g=0.576, b=0.498, label="Teal Green"      },  -- Evoker
    { r=0.667, g=0.827, b=0.447, label="Sage Green"      },  -- Hunter
    { r=0.247, g=0.780, b=0.922, label="Sky Blue"        },  -- Mage
    -- Row 2 — class colors + BNB accents
    { r=0.000, g=1.000, b=0.596, label="Mint Green"      },  -- Monk
    { r=0.957, g=0.549, b=0.729, label="Rose Pink"       },  -- Paladin
    { r=1.000, g=0.957, b=0.408, label="Pale Yellow"     },  -- Rogue
    { r=0.529, g=0.533, b=0.933, label="Periwinkle"      },  -- Warlock
    { r=0.776, g=0.608, b=0.427, label="Warm Tan"        },  -- Warrior
    { r=0.961, g=0.902, b=0.784, label="Warm Cream"      },  -- BNB accent
    { r=0.416, g=0.690, b=0.831, label="Soft Blue"       },  -- BNB accent
    { r=0.478, g=0.749, b=0.541, label="Muted Green"     },  -- BNB accent
    -- Row 3 — item quality colors + BNB accents
    { r=0.616, g=0.616, b=0.616, label="Stone Grey"      },  -- Poor
    { r=0.118, g=1.000, b=0.000, label="Bright Green"    },  -- Uncommon
    { r=0.000, g=0.439, b=0.867, label="Royal Blue"      },  -- Rare
    { r=0.639, g=0.208, b=0.933, label="Vivid Purple"    },  -- Epic
    { r=1.000, g=0.502, b=0.000, label="Flame Orange"    },  -- Legendary
    { r=0.902, g=0.800, b=0.502, label="Antique Gold"    },  -- Artifact
    { r=1.000, g=0.800, b=0.000, label="Gold"            },  -- BNB accent gold
    { r=0.302, g=0.851, b=0.675, label="Aqua Teal"       },  -- BNB teal
}

--------------------------------------------------------------------------------
-- BuildColorGrid
-- Renders BNB.COLOR_PALETTE as an 8×3 swatch grid on `ct` starting at y.
-- contentW: available pixel width — swatch size is computed from it.
-- onPick(r, g, b): called when a swatch is clicked.
-- Returns the new y below the grid.
--------------------------------------------------------------------------------
function BNB.BuildColorGrid(ct, y, contentW, onPick)
    local COLS = 8
    local ROWS = 3
    local GAP  = 3
    local SZ   = math.floor((contentW - (COLS - 1) * GAP) / COLS)

    for i, c in ipairs(BNB.COLOR_PALETTE) do
        local col = (i - 1) % COLS
        local row = math.floor((i - 1) / COLS)
        local sw  = CreateFrame("Button", nil, ct)
        sw:SetSize(SZ, SZ)
        sw:SetPoint("TOPLEFT", ct, "TOPLEFT",
            col * (SZ + GAP),
            y - row * (SZ + GAP))

        local tx = sw:CreateTexture(nil, "ARTWORK")
        tx:SetAllPoints()
        tx:SetColorTexture(c.r, c.g, c.b)

        local hi = sw:CreateTexture(nil, "HIGHLIGHT")
        hi:SetAllPoints()
        hi:SetColorTexture(1, 1, 1, 0.35)

        -- Thin border frame so swatches have a subtle outline
        local bdr = BNB.CreateBackdropFrame("Frame", nil, sw)
        bdr:SetAllPoints()
        bdr:SetFrameLevel(sw:GetFrameLevel() - 1)
        BNB.SetBackdrop(bdr, 0, 0, 0, 0, 0.30, 0.30, 0.32, 0.9)
        bdr:EnableMouse(false)

        local cr, cg, cb, lbl = c.r, c.g, c.b, c.label
        sw:SetScript("OnClick", function() onPick(cr, cg, cb) end)
        sw:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:AddLine(string.format("%s (R:%d G:%d B:%d)",
                lbl,
                math.floor(cr * 255 + 0.5),
                math.floor(cg * 255 + 0.5),
                math.floor(cb * 255 + 0.5)), cr, cg, cb)
            GameTooltip:Show()
        end)
        sw:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end

    return y - (ROWS * (SZ + GAP)) - 4
end

--------------------------------------------------------------------------------
-- TAG CHIP
--------------------------------------------------------------------------------
function BNB.CreateTagChip(parent, text)
    local chip = BNB.CreateBackdropFrame("Frame", nil, parent)
    if chip.SetBackdrop then
        chip:SetBackdrop(BACKDROP_INSET)
        chip:SetBackdropColor(0.12, 0.22, 0.12, 0.9)
        chip:SetBackdropBorderColor(0.3, 0.6, 0.3, 1)
    end
    local lbl = chip:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    lbl:SetPoint("CENTER")
    lbl:SetText(text or "")
    chip:SetSize(lbl:GetStringWidth() + 10, 16)
    return chip
end

--------------------------------------------------------------------------------
-- TAG AUTOCOMPLETE
-- Shared dropdown for tag input fields (NoteEditor + NoteConfig).
-- Modelled on BCB's autocomplete: backdrop frame, row buttons, highlight tex.
-- Usage:
--   BNB.AttachTagAutocomplete(editbox)
-- The dropdown opens above the editbox (tags sit at panel bottom).
-- Selecting a row or pressing Tab fills the field and fires OnEnterPressed.
-- The dropdown is a single shared instance, repositioned on each open.
--------------------------------------------------------------------------------
local _tagAC = nil   -- shared autocomplete frame (built once)
local MAX_AC_ROWS = 8
local AC_ROW_H    = 22

local function BuildTagAutocomplete()
    if _tagAC then return _tagAC end

    local popup = CreateFrame("Frame", "BigNoteBoxTagAC", UIParent, "BackdropTemplate")
    popup:SetBackdrop({
        bgFile   = "Interface\\Buttons\\White8x8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 10,
        insets   = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    popup:SetBackdropColor(0.05, 0.05, 0.08, 0.95)
    popup:SetBackdropBorderColor(0.4, 0.4, 0.5, 1)
    popup:SetFrameStrata("FULLSCREEN_DIALOG")
    popup:SetFrameLevel(200)
    popup:SetClampedToScreen(true)
    popup:Hide()
    popup:EnableMouse(true)
    popup.rows    = {}
    popup.matches = {}
    popup.selIdx  = 0
    popup._eb     = nil   -- currently attached editbox

    for i = 1, MAX_AC_ROWS do
        local row = CreateFrame("Button", nil, popup)
        row:SetHeight(AC_ROW_H)
        row:SetPoint("TOPLEFT",  popup, "TOPLEFT",  4, -4 - (i-1)*AC_ROW_H)
        row:SetPoint("TOPRIGHT", popup, "TOPRIGHT", -4, -4 - (i-1)*AC_ROW_H)

        local hl = row:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(0.3, 0.5, 0.8, 0.3)

        local sel = row:CreateTexture(nil, "BACKGROUND")
        sel:SetAllPoints()
        sel:SetColorTexture(0.2, 0.4, 0.7, 0.5)
        sel:Hide()
        row.selTex = sel

        -- Tag name (left)
        local nameLbl = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        nameLbl:SetPoint("LEFT", 8, 0)
        nameLbl:SetJustifyH("LEFT")
        row.nameLbl = nameLbl

        -- Count (right, dimmed)
        local countLbl = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        countLbl:SetPoint("RIGHT", -8, 0)
        countLbl:SetJustifyH("RIGHT")
        countLbl:SetTextColor(0.5, 0.5, 0.5)
        row.countLbl = countLbl

        local idx = i
        row:SetScript("OnClick", function()
            popup:Select(idx)
        end)
        row:SetScript("OnEnter", function()
            popup.selIdx = idx
            popup:UpdateSel()
        end)
        popup.rows[i] = row
    end

    function popup:UpdateSel()
        for i, r in ipairs(self.rows) do
            r.selTex[i == self.selIdx and "Show" or "Hide"](r.selTex)
        end
    end

    function popup:Select(idx)
        local m = self.matches[idx]
        if not m or not self._eb then return end
        local eb = self._eb
        self._selecting = true   -- prevent OnEditFocusLost from hiding while we commit
        if eb.SetRealText then
            eb:SetRealText(m.tag)
        else
            eb:SetText(m.tag)
        end
        self:Hide()
        -- Fire OnEnterPressed so the tag gets committed immediately
        local fn = eb:GetScript("OnEnterPressed")
        if fn then fn(eb) end
        self._selecting = false
    end

    function popup:ShowFor(eb, partial)
        self._eb = eb
        -- Gather matches: tagIndex keys that start with partial (case-insensitive)
        local db = BigNoteBoxDB
        local idx = db and db.tagIndex
        if not idx then self:Hide(); return end
        local lpartial = partial:lower()
        -- Build set of tags already on the current note so we can exclude them
        local noteTags = {}
        local noteID = BNB._currentNoteID
        local note   = noteID and BNB.GetNote and BNB.GetNote(noteID)
        if note and note.tags then
            for _, t in ipairs(note.tags) do
                noteTags[t:lower()] = true
            end
        end
        local found = {}
        for tag, ids in pairs(idx) do
            -- Skip tags already on this note
            if not noteTags[tag:lower()] then
                if #partial == 0 or tag:lower():sub(1, #lpartial) == lpartial then
                    if tag:lower() ~= lpartial then   -- don't suggest exact match
                        local count = 0
                        for _ in pairs(ids) do count = count + 1 end
                        found[#found + 1] = { tag = tag, count = count }
                    end
                end
            end
        end
        if #found == 0 then self:Hide(); return end
        -- Sort: least-used first so most-used appears at the bottom
        -- (dropdown opens upward, so most-used is closest to the input field)
        table.sort(found, function(a, b)
            if a.count ~= b.count then return a.count < b.count end
            return a.tag:lower() > b.tag:lower()
        end)
        self.matches = found
        local visible = math.min(#found, MAX_AC_ROWS)
        self.selIdx  = visible   -- start selection at bottom (most-used)
        for i = 1, MAX_AC_ROWS do
            if i <= visible then
                self.rows[i].nameLbl:SetText(found[i].tag)
                self.rows[i].countLbl:SetText("(" .. found[i].count .. ")")
                self.rows[i]:Show()
            else
                self.rows[i]:Hide()
            end
        end
        self:SetHeight(visible * AC_ROW_H + 8)
        self:SetWidth(math.max(eb:GetWidth(), 160))
        self:ClearAllPoints()
        -- Open upward (tag fields sit at the bottom of panels)
        self:SetPoint("BOTTOMLEFT", eb, "TOPLEFT", 0, 2)
        self:Show()
        self:UpdateSel()
    end

    function popup:MoveSelection(delta)
        local n = math.min(#self.matches, MAX_AC_ROWS)
        if n == 0 then return end
        self.selIdx = ((self.selIdx - 1 + delta) % n) + 1
        self:UpdateSel()
    end

    _tagAC = popup
    BNB._tagAC = popup   -- exposed for OnEnterPressed handlers in tag inputs
    return popup
end

-- Attach tag autocomplete behaviour to a tag-input EditBox.
-- The editbox must already have AddPlaceholder applied.
function BNB.AttachTagAutocomplete(eb)
    local ac = BuildTagAutocomplete()

    -- Show full tag list (most-used first) as soon as the field is clicked
    eb:HookScript("OnEditFocusGained", function(self)
        ac:ShowFor(self, "")
    end)

    eb:HookScript("OnTextChanged", function(self, userInput)
        if not userInput then return end
        local text = self._showingPlaceholder and "" or (self:GetText() or "")
        text = text:match("^%s*(.-)%s*$") or ""
        if text == "" then
            ac:Hide()
        else
            ac:ShowFor(self, text)
        end
    end)

    -- Tab key: cycle through suggestions or confirm top match
    eb:HookScript("OnTabPressed", function(self)
        if ac:IsShown() and ac._eb == self then
            if #ac.matches > 0 then
                ac:Select(ac.selIdx)
            end
        end
    end)

    -- Arrow keys navigate; Enter commits selection; Escape dismisses
    -- Block Backspace/Delete when the placeholder text is showing — otherwise
    -- the placeholder itself becomes editable and deletable.
    -- Also block ALL key propagation while focused so game bindings (WASD, C, etc.)
    -- don't fire while the player is typing a tag.
    local PASSTHROUGH = { ESCAPE = true, TAB = true }
    eb:HookScript("OnKeyDown", function(self, key)
        if self._showingPlaceholder and (key == "BACKSPACE" or key == "DELETE") then
            self:SetPropagateKeyboardInput(false)
            return
        end
        -- Pass Escape/Tab through so WoW handles focus/close; eat everything else
        self:SetPropagateKeyboardInput(PASSTHROUGH[key] == true)
    end)

    eb:HookScript("OnKeyDown", function(self, key)
        if not ac:IsShown() or ac._eb ~= self then return end
        if key == "UP" then
            ac:MoveSelection(-1)
            self:SetPropagateKeyboardInput(false)
        elseif key == "DOWN" then
            ac:MoveSelection(1)
            self:SetPropagateKeyboardInput(false)
        elseif key == "ESCAPE" then
            ac:Hide()
            self:SetPropagateKeyboardInput(false)
        elseif key == "ENTER" or key == "NUMPADENTER" then
            -- Fill the field with the highlighted suggestion so OnEnterPressed
            -- receives the completed tag text rather than the partial typed text.
            if #ac.matches > 0 then
                local m = ac.matches[ac.selIdx]
                if m then
                    if self.SetRealText then self:SetRealText(m.tag)
                    else self:SetText(m.tag) end
                    ac:Hide()
                    -- Let the real OnEnterPressed fire with the filled text
                end
            end
            -- Don't block propagation — OnEnterPressed needs to run
        end
    end)

    -- Hide dropdown when focus leaves
    eb:HookScript("OnEditFocusLost", function()
        -- Tiny delay so a row click registers before hide.
        -- Don't hide if Select() is mid-commit (row click).
        C_Timer.After(0.15, function()
            if ac._selecting then return end
            if ac._eb == eb then ac:Hide(); ac._eb = nil end
        end)
    end)
end

--------------------------------------------------------------------------------
-- CLIPBOARD HINT  —  floating "Press Ctrl+C to copy" prompt shown whenever
-- the addon pre-selects text in the hidden clipboard helper editbox.
--
-- Usage:  BNB.ShowClipboardHint(content [, anchorFrame [, deferFocus]])
--   Selects `content` in the hidden helper editbox, positions a small hint
--   frame near the cursor (or below anchorFrame if supplied), and waits for
--   Ctrl+C (copies + dismisses) or ESC (dismisses without copying).
--   The frame is named BNBClipboardHintFrame so the MainWindow ESC chain can
--   find and close it at the highest priority.
--
--   `deferFocus` (optional, default false): pass true when the calling button's
--   OnClick path makes synchronous focus unreliable. Defers SetFocus() by one
--   tick so it lands after any same-tick focus contention.
--
-- IMPORTANT: The hint frame is at TOOLTIP strata. It MUST NOT have
-- EnableKeyboard(true), because TOOLTIP strata beats editbox focus in WoW's
-- keyboard routing priority — and Ctrl+C would be routed to the hint frame
-- (a plain Frame, which cannot perform the engine-level copy) instead of the
-- focused helper editbox. ESC dismissal is handled by the helper's OnKeyDown.
--------------------------------------------------------------------------------
function BNB.ShowClipboardHint(content, anchorFrame, deferFocus)
    -- ── 1. Ensure the invisible text-selection editbox exists ─────────────────
    if not BNB._clipboardHelper then
        local helper = CreateFrame("EditBox", nil, UIParent)
        helper:SetSize(1, 1)
        helper:SetAlpha(0)
        helper:SetPoint("CENTER")
        helper:SetAutoFocus(false)
        helper:SetMultiLine(true)
        helper:SetMaxLetters(0)
        helper:Hide()
        BNB._clipboardHelper = helper
    end

    -- ── 2. Ensure the hint frame exists (built once, reused) ─────────────────
    if not BNB._clipboardHint then
        local f = BNB.CreateBackdropFrame("Frame", "BNBClipboardHintFrame", UIParent)
        f:SetFrameStrata("TOOLTIP")
        f:SetFrameLevel(200)
        f:SetSize(220, 48)
        f:Hide()
        BNB.SetBackdrop(f, 0.06, 0.06, 0.08, 0.97, 0.45, 0.45, 0.45, 1)

        -- ── AutoCast glow (LibCustomGlow) in BNB green — started on show ──────
        -- LCG is loaded by the time ShowClipboardHint is first called (post-login).
        local CLIP_GLOW_COLOR = { 0.400, 0.733, 0.416, 1.0 }  -- BNB green
        local _clipGlowActive = false
        -- glow started/stopped in Dismiss and show path below

        -- ── Keyboard icon ──────────────────────────────────────────────────────
        local icon = f:CreateTexture(nil, "ARTWORK")
        icon:SetSize(24, 24)
        icon:SetPoint("LEFT", f, "LEFT", 10, 0)
        pcall(function()
            icon:SetAtlas("groupfinder-icon-keyboard", true)
        end)

        -- ── Main label ─────────────────────────────────────────────────────────
        local lbl = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        lbl:SetPoint("LEFT",  icon, "RIGHT", 8, 4)
        lbl:SetPoint("RIGHT", f,    "RIGHT", -8, 4)
        lbl:SetJustifyH("LEFT")
        lbl:SetText("Press |cff66bb6aCtrl+C|r to copy")
        lbl:SetTextColor(0.400, 0.733, 0.416, 1)

        -- ── Sub-label ──────────────────────────────────────────────────────────
        local sub = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        sub:SetPoint("LEFT",  icon, "RIGHT", 8, -10)
        sub:SetPoint("RIGHT", f,    "RIGHT", -8, -10)
        sub:SetJustifyH("LEFT")
        sub:SetTextColor(0.55, 0.55, 0.55)
        sub:SetText("Press Esc to cancel")

        -- ── Main frame pulse animation ─────────────────────────────────────────
        -- Breathes the whole frame between 0.80 and 1.0 alpha.
        local pulseAG = f:CreateAnimationGroup()
        pulseAG:SetLooping("REPEAT")
        local p1 = pulseAG:CreateAnimation("Alpha")
        p1:SetFromAlpha(1.0)
        p1:SetToAlpha(0.80)
        p1:SetDuration(0.7)
        p1:SetSmoothing("IN_OUT")
        p1:SetOrder(1)
        local p2 = pulseAG:CreateAnimation("Alpha")
        p2:SetFromAlpha(0.80)
        p2:SetToAlpha(1.0)
        p2:SetDuration(0.7)
        p2:SetSmoothing("IN_OUT")
        p2:SetOrder(2)
        f._pulseAG = pulseAG

        -- ── Dismiss ────────────────────────────────────────────────────────────
        local function Dismiss()
            f._pulseAG:Stop()
            -- Stop LCG AutoCast glow. LCG uses dot syntax: first arg is the frame, NOT self.
            local LCG2 = LibStub and LibStub("LibCustomGlow-1.0", true)
            if LCG2 then pcall(LCG2.AutoCastGlow_Stop, f, "bnb_clip") end
            _clipGlowActive = false
            f:Hide()
            BNB._clipboardHelper:ClearFocus()
            BNB._clipboardHelper:Hide()
        end

        f._dismiss = Dismiss
        BNB._clipboardHint = f
    end

    -- ── 3. Load content into helper and focus it ──────────────────────────────
    local helper = BNB._clipboardHelper
    local hint   = BNB._clipboardHint

    helper:Show()
    helper:SetText(content)
    if deferFocus then
        -- Defer focus by one tick for callers whose OnClick path makes
        -- synchronous focus unreliable (e.g. Share Note's copy button).
        C_Timer.After(0, function()
            if helper:IsShown() then
                helper:SetFocus()
                helper:HighlightText()
            end
        end)
    else
        helper:SetFocus()
        helper:HighlightText()
    end

    -- Intercept keys on the focused editbox.
    --
    -- Ctrl+C fix: do NOT propagate the key. The OS copy is performed by the
    -- WoW engine at the editbox level (highlighted text → clipboard) before
    -- key propagation happens, so swallowing the key here still copies the
    -- text but prevents WoW from also firing the "C" keybind (Character window).
    --
    -- ESC: swallow and dismiss without copying.
    helper:SetScript("OnKeyDown", function(self, key)
        if key == "C" and IsControlKeyDown() then
            self:SetPropagateKeyboardInput(false)         -- copy happens; swallow to block keybinds
            hint._dismiss()
        elseif key == "ESCAPE" then
            self:SetPropagateKeyboardInput(false)
            hint._dismiss()
        else
            self:SetPropagateKeyboardInput(true)
        end
    end)

    -- ── 4. Position below anchorFrame if given, otherwise near cursor ──────────
    local hw, hh = 220, 48
    hint:ClearAllPoints()
    if anchorFrame then
        -- Anchor centred below the button that triggered the hint
        hint:SetPoint("TOP", anchorFrame, "BOTTOM", 0, -6)
    else
        local scale  = UIParent:GetEffectiveScale()
        local cx, cy = GetCursorPosition()
        cx = cx / scale
        cy = cy / scale
        local ox = cx + 16
        local oy = cy + 16
        if ox + hw > GetScreenWidth()  then ox = cx - hw - 4 end
        if oy + hh > GetScreenHeight() then oy = cy - hh - 4 end
        hint:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", ox, oy)
    end
    hint:Show()
    hint:Raise()
    hint._pulseAG:Play()
    -- Start AutoCast glow (BNB green) on the hint frame.
    -- Signature: AutoCastGlow_Start(frame, color, N, frequency, scale, xOffset, yOffset, key, frameLevel)
    -- LCG uses dot syntax: first arg is the frame, NOT self.
    local LCG2 = LibStub and LibStub("LibCustomGlow-1.0", true)
    if LCG2 then
        pcall(LCG2.AutoCastGlow_Start, hint,
            { 0.400, 0.733, 0.416, 1.0 }, nil, nil, nil, nil, nil, "bnb_clip")
    end
end

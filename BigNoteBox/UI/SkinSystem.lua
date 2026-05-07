-- BigNoteBox UI/SkinSystem.lua
-- Central skin system. Loaded before all other UI files.
-- Provides preset definitions, target registry, apply function,
-- frame/strip/tab builders, and the main-window open router.
--
-- Public API:
--   BNB.GetSkinPreset()                          -> preset table
--   BNB.SkinColourOf(preset, lifted)             -> r, g, b
--   BNB.CreateSkinFrame(parent, lifted, name)    -> frame (visible border, registered)
--   BNB.CreateSkinStrip(parent, lifted)          -> frame (invisible border, registered)
--   BNB.RegisterSkinTarget(frame, lifted, strip) -> registers external window frames
--   BNB.ApplyMainWindowSkin()                    -> recolours all registered targets
--   BNB.CreateSkinTabs(parent, labels, onSelect) -> tab row widget
--   BNB.OpenMainWindow()                         -> routes to skin or normal window
--------------------------------------------------------------------------------

local BNB = BigNoteBox
local L   = BNB.L

--------------------------------------------------------------------------------
-- PRESET DEFINITIONS
-- Each preset: { r, g, b, lift, br, bg_, bb }
--   r/g/b     = base fill colour
--   lift      = how much brighter chrome strips (title/toolbar/footer) are vs body
--   br/bg_/bb = border colour (bg_ avoids collision with Lua 'bg' idiom)
--------------------------------------------------------------------------------
BNB.SKIN_PRESETS = {
    obsidian   = { r=0.070, g=0.070, b=0.070, lift=0.05, br=0.28, bg_=0.28, bb=0.28 },
    void       = { r=0.090, g=0.030, b=0.130, lift=0.05, br=0.32, bg_=0.15, bb=0.40 },
    dragonfire = { r=0.110, g=0.040, b=0.040, lift=0.05, br=0.35, bg_=0.18, bb=0.18 },
    arcane     = { r=0.130, g=0.055, b=0.100, lift=0.05, br=0.40, bg_=0.22, bb=0.32 },
    fel        = { r=0.040, g=0.100, b=0.060, lift=0.05, br=0.18, bg_=0.32, bb=0.22 },
    titan      = { r=0.100, g=0.090, b=0.030, lift=0.05, br=0.32, bg_=0.30, bb=0.14 },
    icecrown   = { r=0.040, g=0.060, b=0.130, lift=0.05, br=0.18, bg_=0.24, bb=0.38 },
    holy       = { r=0.110, g=0.100, b=0.020, lift=0.05, br=0.40, bg_=0.36, bb=0.12 },
    azshara    = { r=0.030, g=0.100, b=0.110, lift=0.05, br=0.15, bg_=0.34, bb=0.38 },
    ragnaros   = { r=0.130, g=0.070, b=0.020, lift=0.05, br=0.40, bg_=0.26, bb=0.12 },
    earthen    = { r=0.090, g=0.070, b=0.040, lift=0.05, br=0.30, bg_=0.24, bb=0.14 },
    argent     = { r=0.090, g=0.090, b=0.095, lift=0.05, br=0.36, bg_=0.36, bb=0.40 },
    oled       = { r=0.000, g=0.000, b=0.000, lift=0.00, br=0.18, bg_=0.18, bb=0.18 },
}

-- Returns the active preset table, falling back to obsidian.
function BNB.GetSkinPreset()
    local key = BigNoteBoxDB and BigNoteBoxDB.skinPreset or "obsidian"
    return BNB.SKIN_PRESETS[key] or BNB.SKIN_PRESETS.obsidian
end

-- Returns the current brightness multiplier (0.5 - 2.0, default 1.0).
-- Always returns 1.0 for the OLED preset (pure black must stay pure black).
function BNB.GetSkinBrightness()
    local key = BigNoteBoxDB and BigNoteBoxDB.skinPreset or "obsidian"
    if key == "oled" then return 1.0 end
    return (BigNoteBoxDB and BigNoteBoxDB.skinBrightness) or 1.0
end

-- Returns r, g, b for a preset body colour at the given lift level,
-- scaled by the current brightness multiplier.
function BNB.SkinColourOf(preset, lifted)
    local lift = lifted and preset.lift or 0
    local brt  = BNB.GetSkinBrightness()
    return math.min(1, (preset.r + lift) * brt),
           math.min(1, (preset.g + lift) * brt),
           math.min(1, (preset.b + lift) * brt)
end

-- Returns br, bg_, bb for a preset scaled by the current brightness multiplier.
function BNB.SkinBorderOf(preset)
    local brt = BNB.GetSkinBrightness()
    return math.min(1, preset.br * brt),
           math.min(1, preset.bg_ * brt),
           math.min(1, preset.bb * brt)
end

--------------------------------------------------------------------------------
-- TARGET REGISTRY
-- _mainTargets : registered by MainWindowSkin during its own build (private)
-- _extTargets  : registered by all other skinned windows via BNB.RegisterSkinTarget
-- _skinButtons : registered by CreateSkinButton, updated on preset change
--------------------------------------------------------------------------------
local _mainTargets   = {}
local _extTargets    = {}
local _skinButtons   = {}
local _skinTabs      = {}  -- stores RefreshVisual functions from CreateSkinTabs
local _skinRules     = {}  -- stores {tex, alpha} for divider textures
local _skinLabels    = {}  -- stores {fs, mult} for FontStrings that track border colour
local _skinIconTexs  = {}  -- stores {tx, mult} for icon textures tinted to border colour
local _skinBackdrops = {}  -- stores applyFn callbacks for wysiwyg backdrop frames

-- Private: used only by BNB.CreateSkinFrame / BNB.CreateSkinStrip when building
-- the main window. Other windows must use BNB.RegisterSkinTarget.
local function RegisterMain(frame, lifted, strip)
    _mainTargets[#_mainTargets + 1] = {
        frame  = frame,
        lifted = lifted or false,
        strip  = strip  or false,
    }
end

-- Public: called by any skinned window other than the main window.
function BNB.RegisterSkinTarget(frame, lifted, strip)
    _extTargets[#_extTargets + 1] = {
        frame  = frame,
        lifted = lifted or false,
        strip  = strip  or false,
    }
end

-- Public: called by CreateSkinButton for each skin button that should update
-- on preset change. applyFn is a zero-arg function that re-applies the preset.
function BNB.RegisterSkinButton(applyFn)
    _skinButtons[#_skinButtons + 1] = applyFn
end

-- Public: called by CreateSkinTabs so tabs recolour on preset change.
function BNB.RegisterSkinTabs(refreshFn)
    _skinTabs[#_skinTabs + 1] = refreshFn
end

-- Public: called by AddRule (ConfigWindow.lua) for each divider texture that
-- should track the current preset border colour + brightness.
-- alpha defaults to 0.9 if nil.
function BNB.RegisterSkinRule(tex, alpha)
    _skinRules[#_skinRules + 1] = { tex = tex, alpha = alpha or 0.9 }
end

-- Public: FontString that should tint to border colour × mult.
-- mult=0.60 gives a readable-but-secondary metadata text colour.
function BNB.RegisterSkinLabel(fs, mult)
    _skinLabels[#_skinLabels + 1] = { fs = fs, mult = mult or 0.60 }
end

-- Public: icon Texture that should be tinted to border colour × mult.
-- mult=2.2 pushes the tint bright enough to pop against a dark background.
function BNB.RegisterSkinIconTex(tx, mult)
    _skinIconTexs[#_skinIconTexs + 1] = { tx = tx, mult = mult or 2.2 }
end

-- Public: zero-arg callback that re-applies the skin backdrop to a frame.
-- Used by wysiwyg font/size backdrop frames so they update on preset change.
function BNB.RegisterSkinBackdrop(applyFn)
    _skinBackdrops[#_skinBackdrops + 1] = applyFn
end

--------------------------------------------------------------------------------
-- APPLY
-- Recolours every registered target to the current preset.
-- Called on window show and on preset change from Config.
--------------------------------------------------------------------------------
function BNB.ApplyMainWindowSkin()
    local preset = BNB.GetSkinPreset()

    local function applyList(list)
        for _, t in ipairs(list) do
            if t.frame and t.frame.SetBackdropColor then
                local r, g, b = BNB.SkinColourOf(preset, t.lifted)
                t.frame:SetBackdropColor(r, g, b, 0.97)
                local br, bg_, bb = BNB.SkinBorderOf(preset)
                if t.strip then
                    t.frame:SetBackdropBorderColor(r, g, b, 0)
                else
                    t.frame:SetBackdropBorderColor(br, bg_, bb, 1)
                end
            end
        end
    end

    applyList(_mainTargets)
    applyList(_extTargets)

    -- Recolour all registered skin buttons
    for _, applyFn in ipairs(_skinButtons) do
        pcall(applyFn)
    end

    -- Recolour all registered skin tabs
    for _, refreshFn in ipairs(_skinTabs) do
        pcall(refreshFn)
    end

    -- Recolour all registered divider rule textures
    local br, bg_, bb = BNB.SkinBorderOf(preset)
    for _, r in ipairs(_skinRules) do
        if r.tex and r.tex.SetColorTexture then
            r.tex:SetColorTexture(br, bg_, bb, r.alpha)
        end
    end

    -- Recolour registered FontString labels (metadata strips, etc.)
    for _, l in ipairs(_skinLabels) do
        if l.fs and l.fs.SetTextColor then
            l.fs:SetTextColor(br * l.mult, bg_ * l.mult, bb * l.mult)
        end
    end

    -- Tint registered icon textures to the border colour at boosted brightness.
    for _, ic in ipairs(_skinIconTexs) do
        if ic.tx and ic.tx.SetVertexColor then
            ic.tx:SetVertexColor(
                math.min(1, br * ic.mult),
                math.min(1, bg_ * ic.mult),
                math.min(1, bb * ic.mult))
        end
    end

    -- Re-apply skin backdrop to registered wysiwyg backdrop frames.
    for _, fn in ipairs(_skinBackdrops) do
        pcall(fn)
    end

    -- Recolour splitter grip dots.
    if mf and mf._splitter then
        local br, bg_, bb = BNB.SkinBorderOf(preset)
        local dotR = math.min(1, br + 0.06)
        local dotG = math.min(1, bg_ + 0.06)
        local dotB = math.min(1, bb + 0.06)
        for _, region in ipairs({mf._splitter:GetRegions()}) do
            if region.SetColorTexture then
                region:SetColorTexture(dotR, dotG, dotB, 0.9)
            end
        end
    end
end

--------------------------------------------------------------------------------
-- FRAME BUILDERS
-- BNB.CreateSkinFrame  — outer window frame: visible border, uses border colours.
-- BNB.CreateSkinStrip  — internal chrome strip: border alpha=0 (invisible).
--
-- isMain flag: true when building the main window (registers to _mainTargets),
-- false/nil for all other windows (registers to _extTargets via RegisterSkinTarget).
--------------------------------------------------------------------------------
function BNB.CreateSkinFrame(parent, lifted, name, isMain)
    local preset = BNB.GetSkinPreset()
    local r, g, b = BNB.SkinColourOf(preset, lifted)
    local br, bg_, bb = BNB.SkinBorderOf(preset)
    local f = BNB.CreateBackdropFrame("Frame", name, parent)
    BNB.SetBackdrop(f, r, g, b, 0.97, br, bg_, bb, 1)
    if isMain then
        RegisterMain(f, lifted, false)
    else
        BNB.RegisterSkinTarget(f, lifted, false)
    end
    return f
end

function BNB.CreateSkinStrip(parent, lifted, isMain)
    local preset = BNB.GetSkinPreset()
    local r, g, b = BNB.SkinColourOf(preset, lifted)
    local f = BNB.CreateBackdropFrame("Frame", nil, parent)
    BNB.SetBackdrop(f, r, g, b, 0.97, r, g, b, 0)
    if isMain then
        RegisterMain(f, lifted, true)
    else
        BNB.RegisterSkinTarget(f, lifted, true)
    end
    return f
end

--------------------------------------------------------------------------------
-- SKIN CLOSE BUTTON
-- BNB.CreateSkinCloseButton(parent, onClick)
--
-- Shared 22x22 textured close button used by every skinned window's title bar.
-- Matches the bt-close-normal/hover/press asset set used by MainWindowSkin's
-- MakeTexBtn. Callers are responsible for anchoring; the convention is:
--     btn:SetPoint("RIGHT", titleBar, "RIGHT", -2, 0)
-- The -2 inset keeps the button slightly clear of the window border while
-- still overlapping it enough to match Blizzard's native close-button style.
--------------------------------------------------------------------------------
local BNB_BTNS = "Interface\\AddOns\\BigNoteBox\\Assets\\Buttons\\"

function BNB.CreateSkinCloseButton(parent, onClick)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(22, 22)
    btn:SetHighlightTexture("")
    btn:SetPushedTexture("")

    local n = btn:CreateTexture(nil, "ARTWORK"); n:SetAllPoints()
    n:SetTexture(BNB_BTNS .. "bt-close-normal")
    local h = btn:CreateTexture(nil, "ARTWORK"); h:SetAllPoints()
    h:SetTexture(BNB_BTNS .. "bt-close-hover"); h:Hide()
    local p = btn:CreateTexture(nil, "ARTWORK"); p:SetAllPoints()
    p:SetTexture(BNB_BTNS .. "bt-close-press"); p:Hide()

    btn:SetScript("OnClick",     function() if onClick then onClick() end end)
    btn:SetScript("OnMouseDown", function(self) if self:IsEnabled() then p:Show(); n:Hide(); h:Hide() end end)
    btn:SetScript("OnMouseUp",   function(self) p:Hide(); if self:IsEnabled() then h:Show() else n:Show() end end)
    btn:SetScript("OnEnter",     function(self) if self:IsEnabled() then n:Hide(); h:Show() end end)
    btn:SetScript("OnLeave",     function() p:Hide(); h:Hide(); n:Show() end)

    btn._n, btn._h, btn._p = n, h, p
    return btn
end

--------------------------------------------------------------------------------
-- SKIN TABS
-- BNB.CreateSkinTabs(parent, labels, onSelect)
--
-- Creates a horizontal row of flat tab buttons styled to match the skin.
-- parent    : frame to parent buttons to
-- labels    : array of strings e.g. {"General","Animation","Advanced"}
-- onSelect  : function(idx) called when a tab is clicked
--
-- Returns a controller table:
--   ctrl.buttons  : array of Button frames
--   ctrl.Select(idx) : programmatically select a tab
--   ctrl.frame    : invisible container Frame (SetPoint this to position the row)
--
-- Each button is 24px tall. The container width stretches to parent width.
-- Caller anchors ctrl.frame; buttons fill it left-to-right with 2px gaps.
--------------------------------------------------------------------------------
local SK_TAB_H     = 24
local SK_TAB_GAP   = 2

function BNB.CreateSkinTabs(parent, labels, onSelect)
    local container = CreateFrame("Frame", nil, parent)
    container:SetHeight(SK_TAB_H)

    local buttons = {}
    local ctrl = { buttons = buttons, frame = container }

    local function RefreshVisual(selectedIdx)
        local preset = BNB.GetSkinPreset()
        local br, bg_, bb = BNB.SkinBorderOf(preset)
        -- Selected tab label: bright preset border colour
        -- Unselected tab label: white (dimmed via alpha)
        local selR = math.min(1, br * 3.0)
        local selG = math.min(1, bg_ * 3.0)
        local selB = math.min(1, bb * 3.0)
        for i, btn in ipairs(buttons) do
            local selected = (i == selectedIdx)
            if selected then
                btn:SetAlpha(1.0)
                btn:SetEnabled(false)
                if btn._bg and btn._bg.SetBackdropColor then
                    local r, g, b = BNB.SkinColourOf(preset, true)
                    btn._bg:SetBackdropColor(r, g, b, 0.97)
                    btn._bg:SetBackdropBorderColor(br, bg_, bb, 1)
                end
                if btn._lbl then btn._lbl:SetTextColor(selR, selG, selB) end
            else
                btn:SetAlpha(0.55)
                btn:SetEnabled(true)
                if btn._bg and btn._bg.SetBackdropColor then
                    local r, g, b = BNB.SkinColourOf(preset, false)
                    btn._bg:SetBackdropColor(r, g, b, 0.97)
                    btn._bg:SetBackdropBorderColor(br, bg_, bb, 1)
                end
                if btn._lbl then btn._lbl:SetTextColor(1, 1, 1) end
            end
        end
    end

    function ctrl.Select(idx)
        ctrl._selected = idx
        RefreshVisual(idx)
        if onSelect then onSelect(idx) end
    end

    -- Visual-only update — sets the selected appearance without firing onSelect.
    -- Use this when the caller is already handling tab switching logic itself
    -- (e.g. _NoteConfigSelectTab, _NoteConfigStickyTab) to avoid mutual recursion.
    function ctrl.SetVisual(idx)
        ctrl._selected = idx
        RefreshVisual(idx)
    end

    -- Build buttons after we have ctrl.Select defined
    local n = #labels
    for i, label in ipairs(labels) do
        local btn = CreateFrame("Button", nil, container)
        btn:SetHeight(SK_TAB_H)

        -- Backdrop background for the tab
        local bg = BNB.CreateBackdropFrame("Frame", nil, btn)
        bg:SetAllPoints()
        local preset = BNB.GetSkinPreset()
        local r, g, b = BNB.SkinColourOf(preset, false)
        local br, bg_, bb = BNB.SkinBorderOf(preset)
        BNB.SetBackdrop(bg, r, g, b, 0.97, br, bg_, bb, 1)
        btn._bg = bg

        -- Label parented to _bg so it renders above the backdrop fill
        local lbl = bg:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        lbl:SetAllPoints()
        lbl:SetJustifyH("CENTER")
        lbl:SetText(label)
        lbl:SetTextColor(1, 1, 1)  -- white; RefreshVisual sets selected colour
        btn._lbl = lbl

        btn:SetScript("OnClick", function()
            ctrl.Select(i)
        end)
        btn:SetScript("OnEnter", function(self)
            if ctrl._selected ~= i then self:SetAlpha(0.85) end
        end)
        btn:SetScript("OnLeave", function(self)
            if ctrl._selected ~= i then self:SetAlpha(0.55) end
        end)

        buttons[i] = btn
    end

    -- Position buttons. Use OnSizeChanged so they reflow if container resizes.
    local function LayoutButtons()
        local w = container:GetWidth()
        if not w or w < 4 then return end
        local btnW = math.floor((w - (n - 1) * SK_TAB_GAP) / n)
        for i, btn in ipairs(buttons) do
            btn:SetWidth(btnW)
            btn:SetHeight(SK_TAB_H)
            if i == 1 then
                btn:SetPoint("TOPLEFT", container, "TOPLEFT", 0, 0)
            else
                btn:SetPoint("TOPLEFT", buttons[i-1], "TOPRIGHT", SK_TAB_GAP, 0)
            end
        end
    end

    container:SetScript("OnSizeChanged", LayoutButtons)
    -- Defer initial layout one tick so parent has a valid width
    C_Timer.After(0, LayoutButtons)

    -- Default: select first tab without firing onSelect
    ctrl._selected = 1
    RefreshVisual(1)

    -- Register so ApplyMainWindowSkin re-applies colours on preset change
    BNB.RegisterSkinTabs(function()
        RefreshVisual(ctrl._selected or 1)
    end)

    return ctrl
end

--------------------------------------------------------------------------------
-- OPEN MAIN WINDOW ROUTER
-- Replaces direct calls to CreateMainWindow / CreateMainWindowSkin everywhere.
-- Builds the frame on first call, then shows it.
--------------------------------------------------------------------------------
function BNB.OpenMainWindow()
    if BigNoteBoxDB and BigNoteBoxDB.skinMode then
        if not BNB.mainFrame then
            if BNB.CreateMainWindowSkin then BNB.CreateMainWindowSkin() end
        end
    else
        if not BNB.mainFrame then
            if BNB.CreateMainWindow then BNB.CreateMainWindow() end
        end
    end
    if BNB.mainFrame then BNB.mainFrame:Show() end
end

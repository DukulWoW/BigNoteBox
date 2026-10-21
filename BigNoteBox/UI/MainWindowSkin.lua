-- BigNoteBox UI/MainWindowSkin.lua
-- Custom-backdrop chrome for the main window. Loaded after MainWindow.lua.
-- Used when BigNoteBoxDB.skinMode == true: BNB.CreateMainWindow (MainWindow.lua)
-- builds the window body once and asks BNB.BuildMainWindowSkinChrome for the
-- frame, title bar and skin styling (see CHROME CONTRACT in MainWindow.lua).
--
-- Skin preset logic, target registry, BNB.ApplyMainWindowSkin,
-- BNB.CreateSkinFrame, BNB.CreateSkinStrip, BNB.CreateSkinTabs,
-- and BNB.OpenMainWindow all live in SkinSystem.lua.
--------------------------------------------------------------------------------

local BNB = BigNoteBox
local L   = BNB.L

-- ── Layout constants ──────────────────────────────────────────────────────────
-- Title bar 28 like every other skin window (Dukul 2026-10-03; it was 20)
local SK_TITLE_H     = 28    -- top row: window title + X / lock / focus buttons
local SK_TOOLBAR_H   = 40    -- sort dropdowns + topbar icons strip (35 until 2026-10-20: Dukul wanted air above and below; 44 until 2026-10-21: as tall as the normal look's)
local SK_CHROME_H    = SK_TITLE_H + SK_TOOLBAR_H   -- 68
local SK_TOOLBAR_SHADE = 0.6  -- the toolbar strip band: body colour x this
local SK_FILL_INSET  = 3     -- BNB.SetBackdrop's fill stops this far in (BACKDROP_FRAME insets)
local SK_ICON        = 20    -- the top bar icons
local SORT_BTN_H     = 22

--------------------------------------------------------------------------------
-- SKIN CHROME
--------------------------------------------------------------------------------
function BNB.BuildMainWindowSkinChrome()
    -- Pass isMain=true to CreateSkinFrame/CreateSkinStrip so frames register to
    -- the main-window target list (not the external list).
    local f = BNB.CreateSkinFrame(UIParent, false, "BigNoteBoxFrame", true)

    -- ── Title bar strip (window title + X / lock / focus) ────────────────────
    local titleBar = BNB.CreateSkinStrip(f, true, true)
    titleBar:SetPoint("TOPLEFT",  f, "TOPLEFT",  0,  0)
    titleBar:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0,  0)
    titleBar:SetHeight(SK_TITLE_H)
    titleBar:EnableMouse(true)

    -- ── Toolbar strip band: a flat colour darker than the title bar, so the
    -- row reads as its own part as in normal mode (Dukul, 2026-10-20). The
    -- body colour shaded, re-tinted with the preset; under the strip's
    -- controls. A plain texture, not a backdrop: a backdrop's fill stops
    -- SK_FILL_INSET in, and with the title bar's own inset that left a gap.
    -- It reaches up into the title bar's inset and stays inside the border.
    -- On the window itself, BACKGROUND sub-level 7: over the backdrop's fill,
    -- under every child frame. A child frame at the window's own level had
    -- no fixed draw order against the backdrop: it vanished and flickered
    -- back while the brightness slider moved (Dukul, 2026-10-20)
    local toolbarFill = f:CreateTexture(nil, "BACKGROUND", nil, 7)
    toolbarFill:SetPoint("TOPLEFT",  titleBar, "BOTTOMLEFT",   SK_FILL_INSET, SK_FILL_INSET)
    toolbarFill:SetPoint("TOPRIGHT", titleBar, "BOTTOMRIGHT", -SK_FILL_INSET, SK_FILL_INSET)
    toolbarFill:SetHeight(SK_TOOLBAR_H + SK_FILL_INSET)
    local function PaintToolbarBg()
        local r, g, b = BNB.SkinColourOf(BNB.GetSkinPreset(), false)
        toolbarFill:SetColorTexture(r * SK_TOOLBAR_SHADE, g * SK_TOOLBAR_SHADE, b * SK_TOOLBAR_SHADE,
            BNB.GetSkinBgAlpha())
    end
    PaintToolbarBg()
    BNB.RegisterSkinBackdrop(PaintToolbarBg)

    local titleLbl = titleBar:CreateFontString(nil, "OVERLAY", "BNBFontNormal")
    -- Offset left by ~40px so it centres in the space left of the buttons
    titleLbl:SetPoint("CENTER", titleBar, "CENTER", -40, 0)
    BNB.SetHeaderColor(titleLbl)
    titleLbl:SetText(BNB.MainWindowTitle())

    local closeBtn = BNB.CreateSkinCloseButton(titleBar,
        function() BNB.RequestCloseMainWindow() end)
    closeBtn:SetPoint("RIGHT", titleBar, "RIGHT", -2, 0)

    -- Toolbar strip (sort row left, icons right) sits under the title bar;
    -- the controls are centred in it vertically.
    local btnY = -SK_TITLE_H - (SK_TOOLBAR_H - SORT_BTN_H) / 2
    return {
        frame     = f,
        dragBar   = titleBar,   -- the title bar is also a drag handle
        headerH   = SK_CHROME_H,
        closeBtn  = closeBtn,
        btnParent = titleBar,
        btnSize   = 18,
        btnGap    = 4,
        sortX     = 8,
        sortY     = btnY,
        selY      = btnY,
        iconX     = -8,
        iconY     = -(SK_TITLE_H + (SK_TOOLBAR_H - SK_ICON) / 2),   -- centred in the strip, as the dropdowns

        -- Skin randomise button, left of the lock
        AddTitleButtons = function(lockBtn)
            local PRESET_KEYS = {}
            for k in pairs(BNB.SKIN_PRESETS) do PRESET_KEYS[#PRESET_KEYS + 1] = k end
            local skinChangeBtn = BNB.CreateIconButton(titleBar, 18, "skinchange", {
                tip = L["MWS_RANDOM_SKIN_TIP"], tipSub = L["MWS_RANDOM_SKIN_TIP_SUB"],
                onClick = function()
                    local db = BigNoteBoxDB; if not db then return end
                    local cur = db.skinPreset or "obsidian"
                    -- Pick a random preset that isn't the current one
                    local pool = {}
                    for _, k in ipairs(PRESET_KEYS) do
                        if k ~= cur then pool[#pool + 1] = k end
                    end
                    if #pool == 0 then return end
                    db.skinPreset = pool[math.random(#pool)]
                    -- Randomise brightness between 0.5 and 3.0 (step 0.05)
                    local steps = math.random(0, 50)  -- 0..50 → 0.5..3.0
                    db.skinBrightness = 0.5 + steps * 0.05
                    if BNB.ApplyMainWindowSkin then BNB.ApplyMainWindowSkin() end
                    if BNB._refreshSkinConfig then BNB._refreshSkinConfig() end
                end })
            skinChangeBtn:SetPoint("RIGHT", lockBtn, "LEFT", -4, 0)
        end,

        -- Tint the topbar icons (white art) to the accent colour, a hue that
        -- pairs with the preset (BNB.SkinAccentOf, Dukul 2026-10-08).
        -- SetVertexColor + SetDesaturated(true) produces the greyed-out look
        -- for disabled buttons (history etc.).
        StyleIcons = function(icons)
            if not BNB.GetSkinPreset then return end
            for _, btn in ipairs(icons) do
                BNB.RegisterSkinAccentTex(btn._tx)
                if btn.SetSkinHover then btn:SetSkinHover(true) end   -- ui-hover-64 plate
            end
            BNB.RefreshSkinAccents()
        end,

        -- Splitter grip dots follow the preset, a little lighter than the border
        DotColour = function()
            local p = BNB.GetSkinPreset()
            return math.min(1, p.br + 0.15), math.min(1, p.bg_ + 0.15), math.min(1, p.bb + 0.15)
        end,

        -- Apply the current preset live on show
        OnShow = function() BNB.ApplyMainWindowSkin() end,
    }
end

-- BNB.OpenMainWindow is defined in SkinSystem.lua.

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
local SK_TITLE_H     = 20    -- top row: window title + X / lock / focus buttons
local SK_TOOLBAR_H   = 35    -- sort dropdowns + topbar icons strip
local SK_CHROME_H    = SK_TITLE_H + SK_TOOLBAR_H   -- 55
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

    local titleLbl = titleBar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    -- Offset left by ~40px so it centres in the space left of the buttons
    titleLbl:SetPoint("CENTER", titleBar, "CENTER", -40, 0)
    titleLbl:SetTextColor(1, 0.82, 0)
    titleLbl:SetText(L["WINDOW_TITLE"])

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
        iconY     = -(SK_CHROME_H - 8 - 20),   -- icon bottom 8px above the panes

        -- Skin randomise button, left of the lock
        AddTitleButtons = function(lockBtn, MakeTexBtn)
            local PRESET_KEYS = {}
            for k in pairs(BNB.SKIN_PRESETS) do PRESET_KEYS[#PRESET_KEYS + 1] = k end
            local skinChangeBtn = MakeTexBtn(titleBar, "bt-skinchange", 18,
                function()
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
                end,
                L["MWS_RANDOM_SKIN_TIP"], L["MWS_RANDOM_SKIN_TIP_SUB"])
            skinChangeBtn:SetPoint("RIGHT", lockBtn, "LEFT", -4, 0)
        end,

        -- Tint the topbar icons to SkinBorderOf × 2.2, matching the wysiwyg
        -- icon tint pattern. SetVertexColor + SetDesaturated(true) produces the
        -- correct greyed-out look for disabled buttons (history etc.). The BCB
        -- button is only tinted when BCB is installed; without BCB it shows the
        -- promo icon, which stays unskinned.
        StyleIcons = function(icons)
            if not BNB.GetSkinPreset then return end
            local br, bg_, bb = BNB.SkinBorderOf(BNB.GetSkinPreset())
            local MULT = 2.2
            local hasBCB = BigChatBox and BigChatBox.SendDirect
            for _, btn in ipairs(icons) do
                if btn ~= BNB._toolbarImportBtn or hasBCB then
                    btn._tx:SetVertexColor(math.min(1, br * MULT),
                        math.min(1, bg_ * MULT), math.min(1, bb * MULT))
                    BNB.RegisterSkinIconTex(btn._tx, MULT)
                end
            end
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

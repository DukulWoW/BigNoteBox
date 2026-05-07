-- BigNoteBox UI/MainConfigSkin.lua
-- Custom-backdrop Config window. Loaded after ConfigWindow.lua and SkinSystem.lua.
-- Used when BigNoteBoxDB.skinMode == true. BNB.CreateConfigWindowSkin() is
-- called from BNB.OpenConfig() (defined in ConfigWindow.lua).
--
-- Forks the window chrome only — title strip, close button, skin tab row.
-- The six tab panels and their contents are built by BNB._BuildConfigTabPanels
-- which lives in ConfigWindow.lua and is shared with the classic chrome path.
-- This mirrors the MainWindow.lua / MainWindowSkin.lua split.
--
-- Skin preset logic, target registry, BNB.ApplyMainWindowSkin,
-- BNB.CreateSkinFrame, BNB.CreateSkinStrip, BNB.CreateSkinTabs all live in
-- SkinSystem.lua.
--------------------------------------------------------------------------------

local BNB = BigNoteBox
local L   = BNB.L

-- ── Layout constants ──────────────────────────────────────────────────────────
-- Wider than the classic 480px so the 6 tab labels have comfortable widths.
-- At 520 each tab is ~85px wide — "Appearance" fits cleanly.
local SK_CFG_W        = 520
local SK_CFG_TITLE_H  = 28     -- title strip height (matches NoteConfig skin)
local SK_CFG_TAB_H    = 24     -- matches SK_TAB_H in SkinSystem.lua
local SK_CFG_GAP      = 6      -- gap between tab row and content panels
local SK_CFG_CHROME   = SK_CFG_TITLE_H + SK_CFG_TAB_H + SK_CFG_GAP   -- 58

--------------------------------------------------------------------------------
-- CREATE CONFIG WINDOW (SKIN VERSION)
--------------------------------------------------------------------------------
function BNB.CreateConfigWindowSkin()
    local TABS = BNB._configTabs
    if not TABS then return nil end   -- ConfigWindow.lua not loaded yet (shouldn't happen)

    local cfgH = (BNB._GetConfigTargetHeight and BNB._GetConfigTargetHeight()) or 640

    -- ── Outer window frame ────────────────────────────────────────────────────
    -- Named so existing UISpecialFrames hook can still find it if needed.
    local f = BNB.CreateSkinFrame(UIParent, false, "BigNoteBoxConfigFrame", false)
    _G["BigNoteBoxConfigFrame"] = f
    f:SetSize(SK_CFG_W, cfgH)
    f:SetPoint("CENTER")
    f:SetToplevel(true)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:SetClampedToScreen(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) self:StartMoving() end)
    f:SetScript("OnDragStop",  function(self) self:StopMovingOrSizing() end)

    -- ── Title strip ───────────────────────────────────────────────────────────
    local titleBar = BNB.CreateSkinStrip(f, true, false)
    titleBar:SetPoint("TOPLEFT",  f, "TOPLEFT",  0, 0)
    titleBar:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
    titleBar:SetHeight(SK_CFG_TITLE_H)
    -- Title strip is also a drag handle
    titleBar:EnableMouse(true)
    titleBar:RegisterForDrag("LeftButton")
    titleBar:SetScript("OnDragStart", function() f:StartMoving() end)
    titleBar:SetScript("OnDragStop",  function() f:StopMovingOrSizing() end)

    local titleLbl = titleBar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    -- Offset left a bit so it reads centred once the close button takes space on the right.
    titleLbl:SetPoint("CENTER", titleBar, "CENTER", -12, 0)
    titleLbl:SetTextColor(1, 0.82, 0)
    titleLbl:SetText(L["CONFIG_TITLE"])

    -- Close button — shared skin textured close (bt-close asset set).
    local closeBtn = BNB.CreateSkinCloseButton(titleBar, function() f:Hide() end)
    closeBtn:SetPoint("RIGHT", titleBar, "RIGHT", -3, 0)

    -- ── Tab panels (built by shared helper) ───────────────────────────────────
    -- Must be built BEFORE the skin tab row so the tab onSelect can reference
    -- the panels array.
    local panels, contents = BNB._BuildConfigTabPanels(f, SK_CFG_CHROME)

    -- Local tab selector — hides all panels and shows the selected one.
    -- Does NOT touch PanelTemplates_SelectTab (no PanelTab buttons exist here);
    -- CreateSkinTabs handles its own visual state.
    local function SelectTab(idx)
        for i = 1, #panels do
            if panels[i] then
                if i == idx then panels[i]:Show()
                else             panels[i]:Hide() end
            end
        end
        f._activeTab = idx
    end

    -- ── Skin tab row ──────────────────────────────────────────────────────────
    local labels = {}
    for i, tab in ipairs(TABS) do labels[i] = tab.label() end

    local tabCtrl = BNB.CreateSkinTabs(f, labels, function(idx) SelectTab(idx) end)
    tabCtrl.frame:SetPoint("TOPLEFT",  f, "TOPLEFT",  0, -SK_CFG_TITLE_H)
    tabCtrl.frame:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, -SK_CFG_TITLE_H)
    f._skinTabCtrl = tabCtrl

    -- ── Recolour chrome and refresh fonts on show ─────────────────────────────
    f:SetScript("OnShow", function()
        if BNB.ApplyMainWindowSkin then BNB.ApplyMainWindowSkin() end
        if BNB._RefreshConfigFonts then BNB._RefreshConfigFonts() end
    end)

    -- Start on first tab (matches classic chrome default)
    SelectTab(1)

    f:Hide()
    return f
end

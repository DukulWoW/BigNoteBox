-- BigNoteBox UI/MainConfigSkin.lua
-- Custom-backdrop Config window. Loaded after ConfigWindow.lua and SkinSystem.lua.
-- Used when BigNoteBoxDB.skinMode == true. BNB.CreateConfigWindowSkin() is
-- called from BNB.OpenConfig() (defined in ConfigWindow.lua).
--
-- Forks the skin tab row only; the window, title strip and close button come
-- from BNB._CreateConfigShell (ConfigWindow.lua, the shared CreateToolWindow
-- shell, CMP-02).
-- The six tab panels and their contents are built by BNB._BuildConfigTabPanels
-- which lives in ConfigWindow.lua and is shared with the classic chrome path.
-- This mirrors the MainWindow.lua / MainWindowSkin.lua split.
--
-- Skin preset logic, target registry, BNB.ApplyMainWindowSkin,
-- BNB.CreateSkinFrame, BNB.CreateSkinStrip, BNB.CreateSkinTabs all live in
-- SkinSystem.lua.
--------------------------------------------------------------------------------

local BNB = BigNoteBox

-- ── Layout constants ──────────────────────────────────────────────────────────
-- The same width as normal mode (ConfigWindow.lua CFG_W), whose content width
-- both modes use, so the 6 tab labels have comfortable widths.
-- At 520 each tab is ~85px wide — "Appearance" fits cleanly.
local SK_CFG_W        = 520
local SK_CFG_TAB_H    = 24     -- matches SK_TAB_H in SkinSystem.lua
local SK_CFG_GAP      = 6      -- gap between tab row and content panels

--------------------------------------------------------------------------------
-- CREATE CONFIG WINDOW (SKIN VERSION)
--------------------------------------------------------------------------------
function BNB.CreateConfigWindowSkin()
    local TABS = BNB._configTabs
    if not TABS then return nil end   -- ConfigWindow.lua not loaded yet (shouldn't happen)

    -- ── Outer window frame, title strip and close (shared shell) ─────────────
    local f = BNB._CreateConfigShell(SK_CFG_W)
    local SK_CFG_TITLE_H = BNB.TOOL_SKIN_TITLE_H
    local SK_CFG_CHROME  = SK_CFG_TITLE_H + SK_CFG_TAB_H + SK_CFG_GAP   -- 58

    -- ── Tab panels (built by shared helper) ───────────────────────────────────
    -- Must be built BEFORE the skin tab row so the tab onSelect can reference
    -- the panels array.
    local panels = BNB._BuildConfigTabPanels(f, SK_CFG_CHROME)

    -- Local tab selector — hides all panels and shows the selected one.
    -- Does NOT touch PanelTemplates_SelectTab (no PanelTab buttons exist here);
    -- CreateSkinTabs handles its own visual state.
    local function SelectTab(idx)
        if BNB._CloseConfigSubPage then BNB._CloseConfigSubPage() end   -- ALL-84
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
    -- ALL-229: in from both edges by the New note button's inset (ConfigWindow's TAB_SIDE)
    tabCtrl.frame:SetPoint("TOPLEFT",  f, "TOPLEFT",  8,  -SK_CFG_TITLE_H)
    tabCtrl.frame:SetPoint("TOPRIGHT", f, "TOPRIGHT", -8, -SK_CFG_TITLE_H)
    f._skinTabCtrl = tabCtrl

    -- ── Refresh fonts on show (the shell recolours the chrome) ────────────────
    f:HookScript("OnShow", function()
        if BNB._RefreshConfigFonts then BNB._RefreshConfigFonts() end
    end)

    -- Start on first tab (matches classic chrome default)
    SelectTab(1)

    return f
end

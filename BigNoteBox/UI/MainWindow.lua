-- BigNoteBox UI/MainWindow.lua
-- The main window: two-pane layout with a draggable splitter between the list
-- and editor panes. Built once by BNB.CreateMainWindow for both looks; the
-- frame and title bar come from a chrome builder (see CHROME CONTRACT below).

local BNB = BigNoteBox
local L   = BNB.L

-- ── Layout constants ────────────────────────────────────────────────────────
local MIN_W      = 500
local MIN_H      = 400
local MAX_W      = 1400
local MAX_H      = 1000
local DEFAULT_W  = 820
local DEFAULT_H  = 640

-- Initial left pane width — user can drag the splitter to change it.
-- Saved in BigNoteBoxDB.splitX between sessions.
local MIN_LIST_W     = 160
local MAX_LIST_W     = 460
local DEFAULT_LIST_W = BNB.DEFAULTS.splitX
-- Icon-only collapsed width: 8px left pad + 32px icon + 8px right pad + 22px scrollbar + 2px buffer = 72px
-- Must match COLLAPSED_W in NoteList.lua
local COLLAPSED_W    = 90   -- PAD_L(8) + ICON_SIZE_SPACIOUS(42) + square row art margin(12) + 6 + scrollbar(22)

local SORT_BTN_H = 22   -- height to match WowStyle1 button
local ICON_STEP  = 24   -- toolbar icon size (20) + gap (4)

local TOPBAR = "Interface\\AddOns\\BigNoteBox\\Assets\\Topbar\\"
local BCB_PROMO_ICON = "Interface\\AddOns\\BigNoteBox\\Assets\\BCB\\bcb-icon"

-- Runtime split position (set from DB on first window open)
BNB._listPaneW = DEFAULT_LIST_W

--------------------------------------------------------------------------------
-- CHROME CONTRACT
-- The window body (toolbar, sort, multi-select, splitter, resize, ESC, show
-- and hide) is built once in BNB.CreateMainWindow. The frame itself and what
-- differs between the two looks comes from a chrome builder: BuildClassicChrome
-- below (ButtonFrameTemplate), or BNB.BuildMainWindowSkinChrome in
-- MainWindowSkin.lua when BigNoteBoxDB.skinMode is on. A builder creates the
-- frame named "BigNoteBoxFrame" and returns a table:
--   frame        the window
--   dragBar      optional extra drag handle (a mouse-enabled title strip)
--   headerH      title + toolbar height; the panes start below it
--   closeBtn     the close button; focus and lock line up to its left
--   btnParent    parent of the focus / lock buttons
--   btnSize      focus / lock button size; btnGap the space between buttons
--   sortX, sortY TOPLEFT of the sort dropdown, from the window's TOPLEFT
--   selY         TOP of the Select button, from the window's TOP
--   iconX, iconY TOPRIGHT of the right-most toolbar icon (sidebar toggle)
-- Optional hooks:
--   AddTitleButtons(lockBtn)              extra title-bar buttons left of lock
--   StyleIcons(icons)                     once, with the toolbar icon buttons
--   DotColour()                           splitter grip colour at rest (r,g,b)
--   StylePanes(listPane, editorPane)      once, after the panes exist
--   OnShow()                              each show, after the position is restored
--------------------------------------------------------------------------------

--------------------------------------------------------------------------------
-- POSITION / SIZE / SPLIT PERSISTENCE
--------------------------------------------------------------------------------
local function SaveWindowPos(f)
    local pos = BigNoteBoxDB.windowPos
    local s   = f:GetEffectiveScale()
    local x, y = f:GetCenter()
    if x then pos.x = x * s end
    if y then pos.y = y * s end
    pos.w = f:GetWidth()
    pos.h = f:GetHeight()
end

local function RestoreWindowPos(f)
    local pos = BigNoteBoxDB.windowPos
    -- Capped at the screen, so a size saved at a smaller UI scale still fits (ALL-97)
    local w = math.max(math.min(pos.w or DEFAULT_W, UIParent:GetWidth()),  MIN_W)
    local h = math.max(math.min(pos.h or DEFAULT_H, UIParent:GetHeight()), MIN_H)
    f:SetSize(w, h)
    if pos.x and pos.x ~= 0 then
        local s = f:GetEffectiveScale()
        f:ClearAllPoints()
        f:SetPoint("CENTER", UIParent, "BOTTOMLEFT", pos.x / s, pos.y / s)
    else
        f:ClearAllPoints()
        f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    end
end

-- Apply the current split position to the list pane / splitter / editor pane.
-- Called after drag, resize, collapse and on window show.
local function ApplySplit(f)
    local lw, top = BNB._listPaneW, -f._headerH
    BNB.listPane:SetWidth(lw)
    f._splitter:SetPoint("TOPLEFT",    f, "TOPLEFT",    lw - 3, top)
    f._splitter:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", lw - 3, 0)
    BNB.editorPane:SetPoint("TOPLEFT",     f, "TOPLEFT",     lw + 1, top)
    BNB.editorPane:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
end

--------------------------------------------------------------------------------
-- BUTTON HELPERS
--------------------------------------------------------------------------------
-- Title-bar icon buttons are BNB.CreateIconButton (UI/IconButton.lua, ALL-214).

-- Toolbar icon: plain Button, no template, fixed TOPRIGHT anchor on the window.
-- Toolbar icon button. Two looks:
--   single texture (skin mode, the BCB promo icon): drawn inset at rest and
--   grown over the hitbox on hover, greyed by alpha + desaturation;
--   four-state art (normal mode, Assets\Topbar\Normal\<base>-normal / -press /
--   -disabled / -hover): one picture per state, the hover glow drawn under
--   whichever of the other three shows (Dukul, 2026-10-08).
-- btn:SetIconEnabled(on) greys it in either look; btn:SetStateArt(base, tex)
-- switches look (base nil = single texture tex); btn:SetArtDim(on) shows the
-- disabled picture on a button that stays clickable (sidebar toggle while the
-- sidebar is hidden).
local TB_ART = 24   -- four-state art size, centred on the 20 px hitbox
local function MakeIconToolbarBtn(f, iconTex, tooltipText, x, y, onClick, stateBase)
    local ICON_BTN_SIZE = 20
    local btn = CreateFrame("Button", nil, f)
    btn:SetSize(ICON_BTN_SIZE, ICON_BTN_SIZE)
    btn:SetPoint("TOPRIGHT", f, "TOPRIGHT", x, y)

    local hoverTx = btn:CreateTexture(nil, "BACKGROUND")
    hoverTx:SetSize(TB_ART, TB_ART)
    hoverTx:SetPoint("CENTER")
    hoverTx:Hide()
    local iconTx = btn:CreateTexture(nil, "ARTWORK")
    btn._tx = iconTx   -- exposed for SetDesaturated / alpha callers
    local REST  = 2    -- single texture: inset each side at rest  (ICON_BTN_SIZE - 4)
    local HOVER = 2    -- single texture: outset each side on hover (ICON_BTN_SIZE + 4)
    local over, pressed = false, false

    local function Refresh()
        iconTx:ClearAllPoints()
        local base = btn._stateArt
        if base then
            iconTx:SetSize(TB_ART, TB_ART)
            iconTx:SetPoint("CENTER")
            local state = pressed and btn:IsEnabled() and "-press"
                or ((not btn:IsEnabled() or btn._artDim) and "-disabled" or "-normal")
            iconTx:SetTexture(base .. state)
            hoverTx:SetShown(over)
        elseif btn._skinHover then
            -- Skin mode: the icon keeps its size; tp-hover sits under it
            iconTx:SetPoint("TOPLEFT",     btn, "TOPLEFT",      REST, -REST)
            iconTx:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -REST,  REST)
            hoverTx:SetShown(over)
        else
            local d = over and -HOVER or REST
            iconTx:SetPoint("TOPLEFT",     btn, "TOPLEFT",      d, -d)
            iconTx:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -d,  d)
            hoverTx:Hide()
        end
    end

    -- Skin mode's white icons (Dukul, 2026-10-08): a hover plate (tp-hover)
    -- under the icon in a darker accent colour instead of growing the icon.
    -- Off = the grow-on-hover look (the BCB promo icon)
    function btn:SetSkinHover(on)
        self._skinHover = on and true or nil
        if on and not self._stateArt then
            hoverTx:SetTexture(TOPBAR .. "tp-hover")
            if BNB.RegisterSkinAccentTex then BNB.RegisterSkinAccentTex(hoverTx, 0.6) end
        end
        Refresh()
    end

    function btn:SetStateArt(base, tex)
        self._stateArt = base and (TOPBAR .. "Normal\\" .. base) or nil
        if base then
            hoverTx:SetTexture(self._stateArt .. "-hover")
            iconTx:SetDesaturated(false)
            self:SetAlpha(1.0)
        else
            iconTx:SetTexture(tex)
        end
        Refresh()
    end
    function btn:SetArtDim(on)
        self._artDim = on and true or nil
        Refresh()
    end
    function btn:SetIconEnabled(on)
        self:SetEnabled(on)
        if self._stateArt then
            Refresh()
        else
            self:SetAlpha(on and 1.0 or 0.4)
            pcall(function() iconTx:SetDesaturated(not on) end)
        end
    end

    btn:SetScript("OnEnter", function(self)
        over = true; Refresh()
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:AddLine(tooltipText, 1, 1, 1)
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function()
        over = false; Refresh()
        GameTooltip:Hide()
    end)
    btn:SetScript("OnMouseDown", function(self)
        if self:IsEnabled() then pressed = true; Refresh() end
    end)
    btn:SetScript("OnMouseUp", function() pressed = false; Refresh() end)
    btn:SetScript("OnHide", function() over, pressed = false, false; Refresh() end)
    btn:SetScript("OnClick", onClick)
    btn:SetStateArt(stateBase, iconTex)
    return btn
end

-- Text button with a tooltip (title line plus optional grey sub line).
local function MakeTipButton(parent, text, w, tip, tipSub, onClick)
    local btn = BNB.CreateButton(nil, parent, text, w, SORT_BTN_H)
    btn:SetScript("OnClick", onClick)
    btn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:AddLine(tip, 1, 1, 1)
        if tipSub then GameTooltip:AddLine(tipSub, 0.78, 0.78, 0.78) end
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return btn
end

--------------------------------------------------------------------------------
-- SCALE-LOCK BUTTON
-- Locked → "lock" symbol, unlocked → "unlock". State persists via
-- BigNoteBoxDB.scaleLocked. Right-click resets the window size and position.
--------------------------------------------------------------------------------
local function IsLocked() return BigNoteBoxDB and BigNoteBoxDB.scaleLocked end

local function MakeLockBtn(f, parent, size)
    local lockBtn = BNB.CreateIconButton(parent, size, IsLocked() and "lock" or "unlock", {
        tip = function()
            if IsLocked() then return L["MW_LOCK_TIP"], L["MW_LOCK_TIP_SUB"], L["MW_LOCK_RESET_TIP"] end
            return L["MW_UNLOCK_TIP"], L["MW_UNLOCK_TIP_SUB"], L["MW_LOCK_RESET_TIP"]
        end })

    local function RefreshLockBtn()
        lockBtn:SetSymbol(IsLocked() and "lock" or "unlock")
    end

    lockBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    lockBtn:SetScript("OnClick", function(_, btn)
        if btn == "RightButton" then
            -- Reset window to default size and position
            f:SetSize(DEFAULT_W, DEFAULT_H)
            f:ClearAllPoints()
            f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
            SaveWindowPos(f)
            return
        end
        local db = BigNoteBoxDB; if not db then return end
        db.scaleLocked = not db.scaleLocked
        RefreshLockBtn()
        if BNB._applyScaleLock then BNB._applyScaleLock() end
        -- Still hovered: redraw the Locked/Unlocked tooltip (ALL-59)
        lockBtn:RefreshTip()
    end)
    BNB._refreshLockBtn = RefreshLockBtn
    return lockBtn
end

-- Apply scale lock state from DB (called on show and on lock toggle)
function BNB._applyScaleLock()
    local locked = IsLocked()
    local rh = BNB.mainFrame and BNB.mainFrame._resizeHandle
    if rh then rh:SetShown(not locked) end
    if BNB.mainFrame and BNB.mainFrame.SetResizable then
        BNB.mainFrame:SetResizable(not locked)
    end
    if BNB._refreshLockBtn then BNB._refreshLockBtn() end
end

--------------------------------------------------------------------------------
-- ESC HANDLING
-- Handle ESC manually so we control the close order and can intercept
-- confirmClose. We do NOT add BigNoteBoxFrame to UISpecialFrames —
-- that would make it compete with ConfigFrame and NoteConfigFrame for
-- the same ESC press. Instead we catch ESC via OnKeyDown and close the
-- top-most BNB window first, the main window last.
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
-- WINDOW REGISTRY (ARCH-03)
-- Every BNB window the main window manages, in ESC order: the one ESC closes
-- first is first. It replaces four lists kept by hand (the ESC cascade,
-- CloseCompanionWindows, the raise list and Focus mode's snapshot). A new
-- window = one entry here. Fields:
--   name       global frame name (nil for an ESC step that is not a window)
--   esc        true = Hide on ESC while shown; a function = how ESC closes it
--              (called only while shown; a nameless step returns true when
--              it handled the key)
--   companion  closes with the main window: true = Hide if shown, a function
--              = called every time (the close functions check for themselves)
--   raise      raised together with the main window when it is clicked
--   focus      Focus mode closes it and reopens it afterwards; the number is
--              the reopen order, `reopen(noteID)` how
-- Close and open functions live in files that load later, so every entry
-- looks them up when it runs, never at load time.
--------------------------------------------------------------------------------
local function Call(t, k, ...) local fn = t and t[k]; if fn then return fn(...) end end
local function ShowNamed(name) local w = _G[name]; if w then w:Show() end end

local WINDOWS = {
    { name = "BigNoteBoxSendConfirm", raise = true },
    { name = "BigNoteBoxSendDialog",  raise = true,
      companion = function() Call(BNB, "CloseSendToChat") end,
      focus = 8, reopen = function(id) Call(BNB, "OpenSendToChat", id) end },
    -- DIALOG-strata popups first: New Note dialog, clipboard hint, any open
    -- right-click menu (it takes ESC itself while it has the keyboard; this
    -- catches the rest)
    { name = "BNBNewNoteDialogFrame",
      esc       = function() Call(BNB.NewNoteDialog, "Close") end,
      companion = function() Call(BNB.NewNoteDialog, "Close") end },
    { name = "BNBClipboardHintFrame",
      esc = function() Call(BNB._clipboardHint, "_dismiss") end },
    { esc = function()
          local cm = BNB.ContextMenu
          if cm and cm.IsOpen() then cm.Close(); return true end
      end },
    { name = "BigNoteBoxExportFrame",   esc = true, companion = true, raise = true },
    { name = "BigNoteBoxCopyMoveFrame", esc = true, companion = true, raise = true },
    { name = "BigNoteBoxHistoryCompareFrame", raise = true,
      esc       = function() Call(BNB, "CloseHistoryCompare") end,
      companion = function() Call(BNB, "CloseHistoryCompare") end },
    -- Alarm setter window closes before sticky settings
    { name = "BNBAlarmWindow", raise = true,
      esc       = function() Call(BNB.AlarmWindow, "Close") end,
      companion = function() Call(BNB.AlarmWindow, "Close") end },
    { name = "BNBAlarmOverviewFrame", esc = true, companion = true, raise = true },
    { name = "BigNoteBoxStickySettingsFrame", raise = true,
      esc = function() Call(BNB.Sticky, "CloseSettings") end },
    -- The Tag Manager's note picker is a second page (ALL-302): ESC goes back first
    { name = "BigNoteBoxTagManagerFrame", companion = true, raise = true,
      esc = function(w) if not w:PageBack() then w:Hide() end end,
      focus = 4, reopen = function() Call(BNB, "ToggleTagManager") end },
    -- Note History and Trash have a second page (ALL-258): ESC goes back to
    -- the list first, then closes the window
    { name = "BigNoteBoxHistoryFrame", raise = true,
      esc       = function(w) if not w:PageBack() then Call(BNB, "CloseHistoryWindow") end end,
      companion = function() Call(BNB, "CloseHistoryWindow") end,
      focus = 5, reopen = function() Call(BNB, "ReopenHistoryWindow") end },
    { name = "BigNoteBoxTrashFrame", companion = true, raise = true,
      esc = function(w) if not w:PageBack() then w:Hide() end end,
      focus = 3, reopen = function() ShowNamed("BigNoteBoxTrashFrame") end },
    -- Icon frame picker (opened from NoteConfig) before NoteConfig itself
    { name = "BigNoteBoxIconFramePicker",
      esc = function() Call(BNB.IconFramePicker, "Close") end },
    -- Its owners close their own picks; the sidebar's (Change icon, ALL-243)
    -- closes with the main window
    { name = "BigNoteBoxIconPicker",
      esc       = function() Call(BNB.IconPicker, "Close") end,
      companion = function() Call(BNB.IconPicker, "Close", "sidebar") end },
    { name = "BigNoteBoxNoteConfigFrame", esc = true, companion = true, raise = true,
      focus = 1, reopen = function(id) Call(BNB, "OpenNoteConfig", id) end },
    -- Task Edit Window before the Reference Box
    { name = "BNBTaskEditWindow", raise = true,
      esc = function() Call(BNB.TaskEditWindow, "Close") end },
    { name = "BigNoteBoxReferenceBoxFrame", esc = true, raise = true,
      companion = function() Call(BNB, "CloseReferenceBox") end,
      focus = 7, reopen = function(id) Call(BNB, "OpenReferenceBox", id) end },
    -- Share preview, then share, then import, all before the main window
    { name = "BNBSharePreviewFrame", raise = true,
      esc = function() Call(BNB, "CloseSharePreview") end },
    { name = "BNBShareFrame", raise = true,   -- closing it also closes the preview
      esc       = function() Call(BNB, "CloseShareWindow") end,
      companion = function() Call(BNB, "CloseShareWindow") end },
    { name = "BNBImportFrame", raise = true,
      esc       = function() Call(BNB, "CloseImportWindow") end,
      companion = function() Call(BNB, "CloseImportWindow") end },
    -- Addon settings window: a sub-page goes back to its tab first
    { esc = function() return Call(BNB, "ConfigSubPageBack") end },
    { name = "BigNoteBoxConfigFrame", esc = true, raise = true,
      companion = function(w)
          if w and w:IsShown() and not BNB._keepSettingsOpen then w:Hide() end
      end,
      focus = 2, reopen = function() ShowNamed("BigNoteBoxConfigFrame") end },
    -- Rich preview has no fixed frame name; it only closes with the main window
    { companion = function() Call(BNB, "CloseRichPreview") end },
}
BNB.WINDOWS = WINDOWS

-- The game's ESC menu (an ESC sticky opens it) sits on top of our windows:
-- let the game close it first. Sticky settings opened over it still close
-- before it, below.
local function EscToGameMenu()
    local ss = _G["BigNoteBoxStickySettingsFrame"]
    return GameMenuFrame and GameMenuFrame:IsShown() and not (ss and ss:IsShown())
end

-- ESC on the main window (BNB.AttachEscClose; in combat the game has ESC):
-- the first shown window in WINDOWS closes, the main window last
local function OnEscapeKey()
    for _, e in ipairs(WINDOWS) do
        local esc = e.esc
        if esc then
            if not e.name then
                if esc() then return end
            else
                local w = _G[e.name]
                if w and w:IsShown() then
                    if esc == true then w:Hide() else esc(w) end
                    return
                end
            end
        end
    end
    -- Otherwise close main window (with confirm if enabled)
    BNB.RequestCloseMainWindow()
end

--------------------------------------------------------------------------------
-- DEV MODE MARKING  (ALL-129: the dev notes set must never pass for the real one)
--------------------------------------------------------------------------------
-- Lives in the dev addon (never packaged), so the shipped zip does not carry it
local DEV_BG = "Interface\\AddOns\\BigNoteBox_Dev\\Assets\\ui-bg-devmode"

-- Main window title, both chromes: "BigNoteBox (Development Mode Enabled)" in dev mode
function BNB.MainWindowTitle()
    if BNB.IsDevMode and BNB.IsDevMode() then
        return string.format(L["CFG_DEV_WINDOW_TITLE_FMT"], L["WINDOW_TITLE"])
    end
    return L["WINDOW_TITLE"]
end

-- Tiled overlay over the window background (Dukul's ui-bg-devmode, faint by its
-- own alpha). Top of BACKGROUND: over the template Bg / skin backdrop, under
-- the borders and every child frame. Also on Settings and the Developer
-- Tools window (ALL-395).
local function AddDevModeOverlay(f)
    if not (BNB.IsDevMode and BNB.IsDevMode()) then return end
    local ov = f:CreateTexture(nil, "BACKGROUND", nil, 7)
    if f.Bg then
        ov:SetAllPoints(f.Bg)
    else
        ov:SetPoint("TOPLEFT", 3, -3)
        ov:SetPoint("BOTTOMRIGHT", -3, 3)
    end
    ov:SetTexture(DEV_BG, "REPEAT", "REPEAT")
    ov:SetHorizTile(true)
    ov:SetVertTile(true)
    f._devOverlay = ov
end
BNB.AddDevModeOverlay = AddDevModeOverlay

-- Toolbar strip art, normal mode only (ALL-240, Dukul 2026-10-04): a tiling
-- header piece from a game file, one per client, repeated across the strip under
-- the title, behind the sort dropdowns and the toolbar icons. Drawn as copies cut
-- from the file (an atlas piece cannot SetHorizTile), the last one cut short,
-- half a texel inside the region. Tune live with /bnb topbar (debug mode);
-- nothing saved.
--   file, fw, fh  the game file and its size in pixels
--   region        x, y, w, h of the tiling piece in file pixels
--   y        top of the strip, from the window's TOP (just under the title bar)
--   h        drawn height
--   cropTop  file rows cut off the top of the region
--   tileW    drawn width of one copy
--   l, r     insets from the window's left and right edges
--   lift     how much higher the sort row and toolbar icons sit while the strip
--            is drawn, centred on its art; the icons also drop their 2px offset
--            so they line up with the dropdowns
--   header   title + toolbar height while the strip is drawn (the panes start
--            below it); nil = the chrome's own
local TOPBAR_ARTS = {
    -- Forever: atlas QuestLog-reward-top-frame (Interface\QuestFrame\QuestlogFrame2x).
    -- 8 rows off the top, drawn taller; lift 7 measured on Dukul's screenshot
    -- (3 was still low), "Perfect" (Dukul)
    forever = { file = 5684767, fw = 1024, fh = 1024, region = { 1, 593, 614, 103 },
                y = -22, h = 46, cropTop = 8, tileW = 307, l = 2, r = 2, lift = 7 },
    -- Retail: atlas _UI-Frame-DiamondMetal-Header-Tile
    -- (Interface\FrameGeneral\UIFrameDiamondMetalHeader2x), 38 rows off the top
    -- (Dukul); the 40 rows left drawn 64 wide and stretched to 50 tall, so its
    -- bottom rim clears the dropdowns (at 40 it ran right under them). l = 8:
    -- at 2 it showed past the left border line, whose outer side is see-through
    -- on Retail (measured on Dukul's screenshot, 2026-10-04). At h 50 / header 60
    -- the dropdowns filled the art's dark panel and the search box sat right
    -- under its rims, so the header grows to 82 (the strip ends at -78) and the
    -- art to 56 (dark panel ~40 of it); lift 8 = the dropdowns' visual centre on
    -- the panel's (measured at 1.17 px per unit: their centre is -50 + lift).
    -- Then "much better", but too much space under the rims: h 66 (ends at -88,
    -- over the empty top of the panes), lift 5 (panel centre 3.5 lower)
    retail  = { file = 3058483, fw = 128, fh = 256, region = { 0, 0.5, 64, 78 },
                y = -22, h = 66, cropTop = 38, tileW = 64, l = 8, r = 2, lift = 5,
                header = 82 },
}
local TOPBAR_ART = BNB.IsForever and TOPBAR_ARTS.forever or TOPBAR_ARTS.retail

-- Toolbar icon row (see TOOLBAR ICON ROW below); declared here so the live
-- lift can move the slots
local _tbRow, _tbSlots

-- Moves every point of frame that hangs off rel by dy
local function ShiftPointsOn(frame, rel, dy)
    local pts = {}
    for i = 1, frame:GetNumPoints() do pts[i] = { frame:GetPoint(i) } end
    frame:ClearAllPoints()
    for _, p in ipairs(pts) do
        frame:SetPoint(p[1], p[2], p[3], p[4], p[5] + (p[2] == rel and dy or 0))
    end
end

local function TopBarArtKnown()
    return not (C_UIFileAsset and C_UIFileAsset.IsKnownFile)
        or C_UIFileAsset.IsKnownFile(TOPBAR_ART.file)
end

local function LayoutTopBarArt(f)
    local tiles = f._topBarArt
    if not tiles then return end
    local a = TOPBAR_ART
    local rg = a.region
    local W = (f:GetWidth() or 0) - a.l - a.r
    local cut = math.max(0, math.min(rg[4] - 2, a.cropTop))
    local v0, v1 = (rg[2] + cut + 0.5) / a.fh, (rg[2] + rg[4] - 0.5) / a.fh
    local n, x = 0, 0
    while W > 0 and a.tileW > 0 and x < W - 0.01 do
        n = n + 1
        local t = tiles[n]
        if not t then
            t = f:CreateTexture(nil, "BORDER")
            t:SetTexture(a.file, "CLAMP", "CLAMP")
            tiles[n] = t
        end
        local w = math.min(a.tileW, W - x)
        local u1 = rg[1] + (w / a.tileW) * rg[3]
        t:ClearAllPoints()
        t:SetPoint("TOPLEFT", f, "TOPLEFT", a.l + x, a.y)
        t:SetSize(w, a.h)
        t:SetTexCoord((rg[1] + 0.5) / a.fw, (u1 - 0.5) / a.fw, v0, v1)
        t:Show()
        x = x + w
    end
    for i = n + 1, #tiles do tiles[i]:Hide() end
end

-- Returns true when the strip is drawn
local function AddTopBarArt(f)
    if not TopBarArtKnown() then return false end
    f._topBarArt = {}
    f:HookScript("OnSizeChanged", LayoutTopBarArt)
    LayoutTopBarArt(f)
    return true
end

-- /bnb topbar [y h cropTop tileW lift l header]: live tuning; no args = print the current set
function BNB.TuneTopBarArt(y, h, cropTop, tileW, lift, l, header)
    local a, f = TOPBAR_ART, BNB.mainFrame
    if y then a.y, a.h, a.cropTop, a.tileW = y, h or a.h, cropTop or a.cropTop, tileW or a.tileW end
    if l then a.l = l end
    if f then LayoutTopBarArt(f) end
    if header and f and f._topBarArt and BNB.listPane then
        a.header, f._headerH = header, header
        BNB.listPane:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -header)
        ApplySplit(f)
    end
    -- The lift only exists while the strip is drawn (the row was built with it)
    if lift and f and f._topBarArt and lift ~= a.lift then
        local dy = lift - a.lift
        for _, fr in ipairs(f._liftFrames or {}) do ShiftPointsOn(fr, f, dy) end
        for _, p in ipairs(_tbSlots or {}) do p[5] = p[5] + dy end
        a.lift = lift
        BNB.ApplyToolbarIcons()
    end
    return a.y, a.h, a.cropTop, a.tileW, a.lift, a.l, f and f._headerH, (f and f._topBarArt) ~= nil
end

--------------------------------------------------------------------------------
-- CLASSIC CHROME  (ButtonFrameTemplate, matches BCB)
--------------------------------------------------------------------------------
local function BuildClassicChrome()
    -- TITLE_H: height of the ButtonFrameTemplate title area (includes the
    -- icon toolbar strip beneath the "BigNoteBox" heading).
    local TITLE_H = 60

    local f = CreateFrame("Frame", "BigNoteBoxFrame", UIParent, "ButtonFrameTemplate")
    f:SetSize(DEFAULT_W, DEFAULT_H)
    ButtonFrameTemplate_HidePortrait(f)
    ButtonFrameTemplate_HideButtonBar(f)
    if f.Inset then f.Inset:Hide() end
    BNB.SeatChrome(f)   -- FOR-05: Forever border offset (UI/Chrome.lua)
    f:SetAlpha(0.95)
    f:SetTitle(BNB.MainWindowTitle())
    local drawn = AddTopBarArt(f)   -- ALL-240
    local lift = drawn and TOPBAR_ART.lift or 0

    if f.CloseButton then
        f.CloseButton:SetScript("OnClick", function()
            BNB.RequestCloseMainWindow()
        end)
    end

    -- The toolbar strip sits in the title area below the "BigNoteBox" title:
    -- sort row top-left, icons top-right 4px above the pane top edge.
    local sortY = -(TITLE_H - 14) + SORT_BTN_H / 2 + lift
    return {
        frame     = f,
        headerH   = drawn and TOPBAR_ART.header or TITLE_H,
        closeBtn  = f.CloseButton,
        -- Parented to the CloseButton so they inherit its frame level and
        -- stacking context — guaranteed above ButtonFrameTemplate chrome.
        btnParent = f.CloseButton,
        btnSize   = 20,
        btnGap    = 2,
        sortX     = 12,
        sortY     = sortY,
        selY      = sortY + 1,
        iconX     = -6,
        iconY     = -(TITLE_H - 22) + (lift > 0 and lift + 2 or 0),
        -- Forever: soft glow behind the note list so the side panel stands out
        -- against the wood grain; stretches with the pane (splitter, resize, collapse).
        -- The note pane gets the same glow (trial, Dukul 2026-09-26).
        StylePanes = function(listPane, editorPane)
            listPane._forGlow = BNB.AddForeverGlow(listPane)
            if editorPane then
                editorPane._forGlow = BNB.AddForeverGlow(editorPane)
                -- 30% weaker than the list's (test, Dukul 2026-09-26)
                if editorPane._forGlow then editorPane._forGlow:SetAlpha(0.7) end
            end
        end,
    }
end

--------------------------------------------------------------------------------
-- OPEN MAIN WINDOW ROUTER
-- Builds the frame on first call, then shows it. CreateMainWindow picks the
-- classic or skin chrome from BigNoteBoxDB.skinMode. Moved from SkinSystem.lua
-- (ARCH-06).
--------------------------------------------------------------------------------
function BNB.OpenMainWindow()
    if not BNB.mainFrame and BNB.CreateMainWindow then BNB.CreateMainWindow() end
    if BNB.mainFrame then BNB.mainFrame:Show() end
end

--------------------------------------------------------------------------------
-- CREATE MAIN WINDOW
--------------------------------------------------------------------------------
function BNB.CreateMainWindow()
    if BNB.mainFrame then return end

    -- Restore saved split width
    BNB._listPaneW = math.max(MIN_LIST_W,
        math.min(MAX_LIST_W, BigNoteBoxDB.splitX or BNB.DEFAULTS.splitX))

    local skin = BigNoteBoxDB.skinMode and BNB.BuildMainWindowSkinChrome
    local chrome = skin and BNB.BuildMainWindowSkinChrome() or BuildClassicChrome()
    local f = chrome.frame
    f._headerH = chrome.headerH
    AddDevModeOverlay(f)

    f:SetSize(DEFAULT_W, DEFAULT_H)
    f:SetPoint("CENTER")
    f:SetToplevel(true)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:SetResizable(true)   -- REQUIRED — ButtonFrameTemplate does not set this
    f:SetClampedToScreen(true)
    -- BNB.StartDragMoving, not f:StartMoving(): the client's mover threw this
    -- window toward the top of the screen on every drag (ALL-97, UI/Widgets.lua)
    for _, handle in ipairs({ f, chrome.dragBar }) do
        handle:RegisterForDrag("LeftButton")
        handle:SetScript("OnDragStart", function() BNB.StartDragMoving(f) end)
        handle:SetScript("OnDragStop",  function()
            BNB.StopDragMoving(f)
            SaveWindowPos(f)
        end)
    end
    -- When the main window is clicked/raised, bring all visible BNB windows
    -- to the front together so none get left behind other frames.
    f:SetScript("OnMouseDown", function()
        if BNB.RaiseBNBWindows then BNB.RaiseBNBWindows() end
    end)

    -- ── Title-bar buttons: focus mode, sticky eye, scale lock (right to left) ─
    if chrome.closeBtn then
        local focusBtn = BNB.CreateIconButton(chrome.btnParent, chrome.btnSize, "focus", {
            onClick = function() if BNB.OpenFocusMode then BNB.OpenFocusMode() end end,
            tip = L["FOCUS_MODE_TIP"], tipSub = L["FOCUS_MODE_TIP_SUB"] })
        focusBtn:SetPoint("RIGHT", chrome.closeBtn, "LEFT", -chrome.btnGap, 0)
        BNB._focusModeBtn = focusBtn
        -- Start disabled — no note selected yet; UpdateSaveButtonState re-enables on note load
        focusBtn:SetEnabled(false)

        -- Sticky eye (ALL-101): open = stickies shown (click hides them all),
        -- closed = hidden by Hide all / its keybind. Two buttons, one shown.
        local function ToggleStickies()
            if BNB.Sticky and BNB.Sticky.ToggleHidden then BNB.Sticky.ToggleHidden() end
        end
        local eyeOpen = BNB.CreateIconButton(chrome.btnParent, chrome.btnSize, "eye-open", {
            onClick = ToggleStickies, tip = L["MW_EYE_HIDE_TIP"], tipSub = L["MW_EYE_HIDE_SUB"] })
        local eyeClosed = BNB.CreateIconButton(chrome.btnParent, chrome.btnSize, "eye-closed", {
            onClick = ToggleStickies, tip = L["MW_EYE_SHOW_TIP"] })
        local lockBtn = MakeLockBtn(f, chrome.btnParent, chrome.btnSize)
        -- Focus Mode module off (ALL-343): no focus button, the eye moves up
        -- to the close button. Sticky Notes off: no eye (RefreshStickyEyeBtn),
        -- the lock moves up the same way
        function BNB.ApplyFocusTitleBtn()
            local on = BNB.FocusEnabled()
            focusBtn:SetShown(on)
            local right = on and focusBtn or chrome.closeBtn
            for _, eb in ipairs({ eyeOpen, eyeClosed }) do
                eb:ClearAllPoints()
                eb:SetPoint("RIGHT", right, "LEFT", -chrome.btnGap, 0)
            end
            lockBtn:ClearAllPoints()
            lockBtn:SetPoint("RIGHT", BNB.StickiesEnabled() and eyeOpen or right, "LEFT", -chrome.btnGap, 0)
        end
        for _, eb in ipairs({ eyeOpen, eyeClosed }) do
            eb:HookScript("OnEnter", function(self)
                local SN = BNB.Sticky
                if self == eyeClosed and SN and SN.HiddenCount then
                    GameTooltip:AddLine(string.format(L["MW_EYE_SHOW_SUB_FMT"], SN.HiddenCount()), 0.78, 0.78, 0.78)
                end
                local key = SN and SN.HideKeyText and SN.HideKeyText()
                if key then GameTooltip:AddLine(string.format(L["MW_EYE_KEY_FMT"], key), 0.55, 0.55, 0.55) end
                GameTooltip:Show()
            end)
        end
        -- Greyed while no world sticky is open or hidden (ALL-237); refreshed
        -- by sticky open / close / hide / show and the ESC-screen toggle
        function BNB.RefreshStickyEyeBtn()
            local hidden = BigNoteBoxDB and BigNoteBoxDB.stickiesHidden == true
            local on = BNB.StickiesEnabled()   -- Sticky Notes module (ALL-343)
            eyeOpen:SetShown(on and not hidden)
            eyeClosed:SetShown(on and hidden)
            local any = BNB.Sticky and BNB.Sticky.WorldCount and BNB.Sticky.WorldCount() > 0
            eyeOpen:SetEnabled(any and true or false)
            eyeClosed:SetEnabled(any and true or false)
        end
        BNB.RefreshStickyEyeBtn()
        BNB.ApplyFocusTitleBtn()

        if chrome.AddTitleButtons then chrome.AddTitleButtons(lockBtn) end
    end

    -- ── Toolbar icons (right side of the toolbar strip) ──────────────────────
    -- Slot 0 is the right-most (sidebar toggle); each slot one ICON_STEP left.
    -- Normal mode draws the four-state art from Assets\Topbar\Normal\ (base =
    -- its file name without the state); skin mode keeps the single tinted
    -- texture (tex)
    local function TBIcon(tex, tip, slot, onClick, base)
        return MakeIconToolbarBtn(f, tex, tip,
            chrome.iconX - ICON_STEP * slot, chrome.iconY, onClick,
            not skin and base or nil)
    end

    local sidebarToggleBtn = TBIcon(TOPBAR .. "tp-sidebar-open", L["MW_SIDEBAR_TIP"], 0,
        function()
            if BNB.Sidebar and BNB.Sidebar.ToggleCollapsed then
                BNB.Sidebar.ToggleCollapsed()
            end
        end, "tp-sidebar")
    BNB._toolbarSidebarBtn = sidebarToggleBtn

    -- Refreshes sidebar toggle icon to match current state: normal mode shows
    -- the disabled picture while the sidebar is hidden (still clickable), skin
    -- mode swaps the open / closed icon. Hidden while the Character Sidebar
    -- module is off (ApplyToolbarIcons)
    function BNB.RefreshSidebarToggleBtn()
        local collapsed = BigNoteBoxDB and BigNoteBoxDB.sidebarCollapsed
        if BNB._toolbarSidebarBtn._stateArt then
            BNB._toolbarSidebarBtn:SetArtDim(collapsed)
            return
        end
        local tex = TOPBAR .. (collapsed and "tp-sidebar-closed" or "tp-sidebar-open")
        pcall(function() BNB._toolbarSidebarBtn._tx:SetTexture(tex) end)
    end
    BNB.RefreshSidebarToggleBtn()

    local configBtn = TBIcon(TOPBAR .. "tp-settings", L["MW_CONFIG_TIP"], 1,
        function() if BNB.OpenConfig then BNB.OpenConfig() end end, "tp-settings")

    local trashBtn = TBIcon(TOPBAR .. "tp-trash", L["MW_TRASH_TIP"], 2,
        function() if BNB.ToggleTrashWindow then BNB.ToggleTrashWindow() end end, "tp-trash")
    BNB._toolbarTrashBtn = trashBtn

    -- History button (desaturated until history exists)
    local histBtn = TBIcon(TOPBAR .. "tp-notehistory", L["HISTORY_TOOLBAR_TIP"], 3,
        function() if BNB.ToggleHistoryWindow then BNB.ToggleHistoryWindow() end end, "tp-notehistory")
    histBtn:SetIconEnabled(false)
    BNB._toolbarHistoryBtn = histBtn

    local tagsBtn = TBIcon(TOPBAR .. "tp-tagmanager", L["TAG_MGR_TOOLTIP"], 4,
        function() if BNB.ToggleTagManager then BNB.ToggleTagManager() end end, "tp-tagmanager")
    BNB._toolbarTagsBtn = tagsBtn

    -- Share/import button — toggles the import-only window
    local shareTopBtn = TBIcon(TOPBAR .. "tp-import", L["MW_IMPORT_SHARED_TIP"], 5,
        function()
            local iw = _G["BNBImportFrame"]
            if iw and iw:IsShown() then
                if BNB.CloseImportWindow then BNB.CloseImportWindow() end
            else
                if BNB.OpenImportWindow then BNB.OpenImportWindow() end
            end
        end, "tp-import")

    -- Alarm overview button
    local alarmOvBtn = TBIcon(TOPBAR .. "tp-alarms", L["MW_ALARM_TIP"], 6,
        function()
            if BNB.AlarmOverview and BNB.AlarmOverview.Toggle then
                BNB.AlarmOverview.Toggle()
            end
        end, "tp-alarms")
    BNB._toolbarAlarmsBtn = alarmOvBtn   -- greyed while no note has an alarm (ALL-352)
    if BNB.SyncAlarmsBtnState then BNB.SyncAlarmsBtnState() end

    -- Send-to-BCB button. Icon: tp-bcb when BCB is installed (four-state art in
    -- normal mode), bcb-icon when absent. Always full colour. Click: BNB.SendCurrentNoteToBCB (below the
    -- window builder; ChatCapture wires the same function).
    local importBtn = TBIcon(
        (BigChatBox and BigChatBox.SendDirect) and TOPBAR .. "tp-bcb" or BCB_PROMO_ICON,
        L["MW_BCB_SEND_TIP"], 7,
        function() BNB.SendCurrentNoteToBCB() end)
    -- Re-evaluates BCB presence and swaps icon; called after BCB loads late.
    local function RefreshImportBtn()
        local hasBCB = BigChatBox and BigChatBox.SendDirect and true or false
        pcall(function()
            if skin or not hasBCB then
                importBtn:SetStateArt(nil, hasBCB and TOPBAR .. "tp-bcb" or BCB_PROMO_ICON)
            else
                importBtn:SetStateArt("tp-bcb")
            end
            importBtn._tx:SetDesaturated(false)
            importBtn:SetAlpha(1.0)
            -- Skin mode, BCB loaded late: the white tp-bcb takes the accent
            -- and the hover plate like the other icons
            if skin and hasBCB and BNB.RegisterSkinAccentTex then
                BNB.RegisterSkinAccentTex(importBtn._tx)
                importBtn:SetSkinHover(true)
            end
        end)
    end
    RefreshImportBtn()
    BNB._toolbarImportBtn = importBtn
    BNB._refreshImportBtn = RefreshImportBtn

    if chrome.StyleIcons then
        chrome.StyleIcons({ sidebarToggleBtn, configBtn, trashBtn, histBtn,
            tagsBtn, shareTopBtn, alarmOvBtn, importBtn })
    end

    -- ── Sort + order dropdowns — top-left of the toolbar strip ───────────────
    -- WowStyle1 dropdowns. The order dropdown is disabled (greyed out) when
    -- sort is "custom" since order has no meaning there.
    local SORT_MODES = {
        { key="custom",   label=L["SORT_MODE_CUSTOM"]   },
        { key="creation", label=L["SORT_MODE_CREATION"] },
        { key="edited",   label=L["SORT_MODE_EDITED"]   },
        { key="alpha",    label=L["SORT_MODE_ALPHA"]    },
        { key="location", label=L["SORT_MODE_LOCATION"] },
    }
    local DIR_MODES = {
        { key="desc", label=L["DIR_MODE_DESC"] },
        { key="asc",  label=L["DIR_MODE_ASC"]  },
    }
    local function IsCustomSort()  return BigNoteBoxDB.sortBy == "custom" end
    local function CurrentDirKey() return BigNoteBoxDB.sortAsc and "asc" or "desc" end

    local sortDD, dirDD             -- WowStyle1 DropdownButtons
    local DD_W = 120

    local function UpdateDirEnabled()
        local custom = IsCustomSort()
        dirDD:SetEnabled(not custom); dirDD:SetAlpha(custom and 0.4 or 1.0)
    end

    -- Refreshes the list, then the order control (its state follows the sort key)
    local function ApplySort()
        if BNB.RefreshNoteList then BNB.RefreshNoteList() end
        UpdateDirEnabled()
        dirDD:GenerateMenu()
    end

    sortDD = BNB.SkinDropdown(CreateFrame("DropdownButton", nil, f, "WowStyle1DropdownTemplate"))
    sortDD:SetSize(DD_W, SORT_BTN_H)
    sortDD:SetPoint("TOPLEFT", f, "TOPLEFT", chrome.sortX, chrome.sortY)
    sortDD:SetupMenu(function(_, root)
        for _, m in ipairs(SORT_MODES) do
            local key = m.key
            root:CreateRadio(m.label,
                function() return (BigNoteBoxDB.sortBy or BNB.DEFAULTS.sortBy) == key end,
                function() BigNoteBoxDB.sortBy = key; sortDD:GenerateMenu(); ApplySort() end)
        end
    end)

    dirDD = BNB.SkinDropdown(CreateFrame("DropdownButton", nil, f, "WowStyle1DropdownTemplate"))
    dirDD:SetSize(DD_W, SORT_BTN_H)
    dirDD:SetPoint("LEFT", sortDD, "RIGHT", 4, 0)
    dirDD:SetupMenu(function(_, root)
        for _, m in ipairs(DIR_MODES) do
            local key = m.key
            root:CreateRadio(m.label,
                function() return CurrentDirKey() == key end,
                function() BigNoteBoxDB.sortAsc = (key == "asc"); dirDD:GenerateMenu(); ApplySort() end)
        end
    end)

    -- Exposed so TagTree can disable sorting while tree view is active.
    -- Also disables the direction control, which has no meaning without sort
    -- either; re-enabling defers to UpdateDirEnabled so "custom" sort still
    -- greys it out (BUG found ALL-65.9, 2026-09-25: it never touched direction).
    function BNB.SetSortEnabled(enabled)
        sortDD:SetEnabled(enabled)
        sortDD:SetAlpha(enabled and 1.0 or 0.4)
        if enabled then
            UpdateDirEnabled()
        else
            dirDD:SetEnabled(false)
            dirDD:SetAlpha(0.4)
        end
    end

    -- ── Select-mode toggle + multi-select action buttons ─────────────────────
    local selBtn = MakeTipButton(f, L["MW_SELECT_BTN"], 52,
        L["MW_SELECT_TIP"], L["MW_SELECT_TIP_SUB"], nil)
    selBtn:SetPoint("LEFT", dirDD, "RIGHT", 6, 0)
    selBtn:SetPoint("TOP", f, "TOP", 0, chrome.selY)
    f._liftFrames = { sortDD, selBtn }   -- /bnb topbar lift (ALL-240)
    selBtn:SetScript("OnClick", function()
        -- Read the list's own state: popups, export and the sidebar leave multi
        -- mode through SetMultiMode, which a local flag here never saw (ALL-58)
        local entering = not (BNB.IsMultiMode and BNB.IsMultiMode())
        if BNB.SetMultiMode then BNB.SetMultiMode(entering) end
        selBtn:SetText(entering and L["CANCEL"] or L["MW_SELECT_BTN"])
        if BNB._setToolbarMultiMode then BNB._setToolbarMultiMode(entering) end
    end)
    BNB._multiSelBtn = selBtn

    -- Action buttons, hidden until multi-select mode is on; each sits right of
    -- the previous one
    local prev = selBtn
    local function MultiBtn(text, w, tip, tipSub, onClick)
        local btn = MakeTipButton(f, text, w, tip, tipSub, onClick)
        btn:SetPoint("LEFT", prev, "RIGHT", 4, 0)
        btn:SetPoint("TOP",  selBtn, "TOP", 0, 0)
        btn:Hide()
        prev = btn
        return btn
    end

    BNB._multiSelectAllBtn = MultiBtn(L["MW_SELECT_ALL_BTN"], 76,
        L["MW_SELECT_ALL_TIP"], nil,
        function() if BNB.SelectAll then BNB.SelectAll() end end)

    BNB._multiDeleteBtn = MultiBtn(string.format(L["MULTI_DELETE_FMT"], "(0)"), 90,
        L["MW_MULTI_DELETE_TIP"], nil,
        function() if BNB.DeleteMultiSelected then BNB.DeleteMultiSelected() end end)

    BNB._multiCopyMoveBtn = MultiBtn(string.format(L["MULTI_COPYMOVE_FMT"], "(0)"), 120,
        L["MW_MULTI_COPYMOVE_TIP"], nil,
        function() if BNB.CopyMoveMultiSelected then BNB.CopyMoveMultiSelected() end end)

    -- Bulk export (JSON, re-importable)
    BNB._multiExportBtn = MultiBtn(string.format(L["MULTI_EXPORT_FMT"], "(0)"), 90,
        L["MW_MULTI_EXPORT_TIP"], L["MW_MULTI_EXPORT_TIP_SUB"],
        function()
            if BNB.ExportMultiJSON and BNB._multiGetSelected then
                BNB.ExportMultiJSON(BNB._multiGetSelected())
            end
            if BNB.SetMultiMode then BNB.SetMultiMode(false) end
        end)
    -- The bulk actions start disabled: nothing is selected yet
    BNB._multiDeleteBtn:SetEnabled(false)
    BNB._multiCopyMoveBtn:SetEnabled(false)
    BNB._multiExportBtn:SetEnabled(false)

    -- Right-side toolbar icons, in slot order right to left (see
    -- BNB.InitToolbarIconRow). They hide in multi-select so the action buttons
    -- don't overlap them; the sidebar toggle right of the cog stays. Title bar
    -- buttons (focus, lock, close) are never hidden by multiselect.
    BNB.InitToolbarIconRow({
        configBtn, trashBtn, histBtn, tagsBtn, shareTopBtn, alarmOvBtn, importBtn,
    })
    function BNB._setToolbarMultiMode() BNB.ApplyToolbarIcons() end

    C_Timer.After(0, ApplySort)

    BNB.AttachEscClose(f, OnEscapeKey, EscToGameMenu)

    -- ── Resize (whole window, bottom-right) ─────────────────────────────────
    f:SetResizeBounds(MIN_W, MIN_H, MAX_W, MAX_H)

    -- Small label that tracks the cursor during resize and shows WxH.
    local sizeLabel = CreateFrame("Frame", nil, UIParent)
    sizeLabel:SetSize(90, 22)
    sizeLabel:SetFrameStrata("TOOLTIP")
    sizeLabel:SetFrameLevel(100)
    sizeLabel:Hide()
    local sizeLabelBg = sizeLabel:CreateTexture(nil, "BACKGROUND")
    sizeLabelBg:SetAllPoints()
    sizeLabelBg:SetColorTexture(0, 0, 0, 0.75)
    local sizeLabelTxt = sizeLabel:CreateFontString(nil, "OVERLAY", "BNBFontNormalSmall")
    sizeLabelTxt:SetAllPoints()
    sizeLabelTxt:SetJustifyH("CENTER")
    BNB.SetTextWhite(sizeLabelTxt)

    -- Sidebar width (BTN_SZ in Sidebar.lua = 64) subtracted when sidebar is visible
    -- so the label shows the notepad window size, not including the sidebar strip.
    -- (none for the top tabs, ALL-248)
    local function SidebarW()
        local top = BigNoteBoxDB and BigNoteBoxDB.sidebarSide == "top"
        return (not top and BNB.Sidebar and BNB.Sidebar.IsEnabled and BNB.Sidebar.IsEnabled()) and 64 or 0
    end
    -- Label text is the current size; it sits 14px right of and 4px below the cursor
    local function UpdateSizeLabel()
        sizeLabelTxt:SetText(math.floor(f:GetWidth() - SidebarW()) .. " x " .. math.floor(f:GetHeight()))
        local cx, cy = GetCursorPosition()
        local uisc   = UIParent:GetEffectiveScale()
        sizeLabel:ClearAllPoints()
        sizeLabel:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", cx / uisc + 14, cy / uisc + 4)
    end

    local _resizing = false
    f:HookScript("OnSizeChanged", function()
        if _resizing then UpdateSizeLabel() end
    end)

    -- The shared grip (UI/Widgets.lua, ALL-263): the damage meter's scale
    -- handle, BNB.StartGripSizing, not StartSizing (ALL-97). Art and click area
    -- move together. Retail normal: as far from the right edge as from the
    -- bottom (RET-07: x 1, set by Dukul in game 2026-10-06); Retail skin
    -- keeps -4.
    -- Forever: normal mode 3 px further down-right, skin mode 2 px (FOR-29)
    local gripX, gripY = -4, 0
    if not BNB.IsForever and not BigNoteBoxDB.skinMode then gripX = 1 end
    if BNB.IsForever then
        if BigNoteBoxDB.skinMode then gripX, gripY = 0, 0 else gripX, gripY = 1, -1 end
    end
    local resizeHandle = BNB.CreateResizeGrip(f, {
        x = gripX, y = gripY,
        onStart = function()
            _resizing = true
            -- Seed the label with current size before first OnSizeChanged fires
            UpdateSizeLabel()
            sizeLabel:Show()
        end,
        onStop = function()
            _resizing = false
            sizeLabel:Hide()
            local w = math.max(MIN_W, math.min(MAX_W, f:GetWidth()))
            local h = math.max(MIN_H, math.min(MAX_H, f:GetHeight()))
            f:SetSize(w, h)
            SaveWindowPos(f)
            -- Re-apply split so panes adjust to new width
            ApplySplit(f)
            -- Recalculate sidebar slot visibility after resize
            if BNB.Sidebar and BNB.Sidebar.Refresh then BNB.Sidebar.Refresh() end
        end,
    })
    f._resizeHandle = resizeHandle  -- stored for scale-lock toggle

    -- ── Splitter drag handle (7px wide button over the divider) ─────────────
    -- Three grip dots, plus the game's Size cursor (ALL-95). An addon file
    -- as a cursor draws a black box: only game cursors work (UI/Cursor.lua).
    local splitter = CreateFrame("Button", nil, f)
    f._splitter = splitter
    splitter:SetWidth(7)
    splitter:SetFrameLevel(f:GetFrameLevel() + 5)

    local function DotColour()
        if chrome.DotColour then return chrome.DotColour() end
        return 0.65, 0.65, 0.65
    end
    local function ColourDots(r, g, b, a)
        for _, reg in ipairs({ splitter:GetRegions() }) do
            if reg.SetColorTexture then reg:SetColorTexture(r, g, b, a) end
        end
    end

    -- Three grip dots centred vertically on the splitter
    for i = -1, 1 do
        local dot = splitter:CreateTexture(nil, "OVERLAY")
        dot:SetSize(3, 3)
        dot:SetPoint("CENTER", splitter, "CENTER", 0, i * 5)
    end
    local dr, dg, db = DotColour()
    ColourDots(dr, dg, db, 0.9)

    -- Highlight dots on hover
    splitter:SetScript("OnEnter", function() ColourDots(1, 0.82, 0, 1) end)
    splitter:SetScript("OnLeave", function()
        local r, g, b = DotColour()
        ColourDots(r, g, b, 0.9)
    end)

    local dragging = false
    splitter:SetScript("OnMouseDown", function(self, btn)
        if btn ~= "LeftButton" then return end
        dragging = true
        self:SetScript("OnUpdate", function(self)
            if not dragging then self:SetScript("OnUpdate", nil); return end
            local mx = GetCursorPosition() / f:GetEffectiveScale()
            local fx = f:GetLeft()
            if not mx or not fx then return end
            local newW = math.max(MIN_LIST_W, math.min(MAX_LIST_W,
                math.floor(mx - fx)))
            -- Also ensure right pane has at least 300px
            local minRight = 300
            local maxW = f:GetWidth() - minRight - 1
            newW = math.min(newW, maxW)
            if newW ~= BNB._listPaneW then
                BNB._listPaneW = newW
                ApplySplit(f)
            end
        end)
    end)
    splitter:SetScript("OnMouseUp", function(self, btn)
        if btn ~= "LeftButton" then return end
        dragging = false
        self:SetScript("OnUpdate", nil)
        BigNoteBoxDB.splitX = BNB._listPaneW
    end)
    BNB.SetHoverCursor(splitter, "size")   -- ALL-95

    -- ── Left pane (note list) ────────────────────────────────────────────────
    local listPane = CreateFrame("Frame", nil, f)
    listPane:SetPoint("TOPLEFT",    f, "TOPLEFT",    0, -chrome.headerH)
    listPane:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, 0)
    BNB.listPane = listPane

    -- ── Right pane (editor) ──────────────────────────────────────────────────
    local editorPane = CreateFrame("Frame", nil, f)
    editorPane:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
    BNB.editorPane = editorPane

    if chrome.StylePanes then chrome.StylePanes(listPane, editorPane) end

    -- Apply initial split (sets widths and anchors splitter/editorPane)
    ApplySplit(f)

    -- ── Lifecycle ────────────────────────────────────────────────────────────
    f:SetScript("OnShow", function(self)
        if BigNoteBoxDB.listCollapsed then
            BNB._listPaneW = COLLAPSED_W
            splitter:EnableMouse(false)
        else
            BNB._listPaneW = math.max(MIN_LIST_W,
                math.min(MAX_LIST_W, BigNoteBoxDB.splitX or BNB.DEFAULTS.splitX))
            splitter:EnableMouse(true)
        end
        ApplySplit(f)
        -- Skip RestoreWindowPos when returning from focus mode — position was
        -- already set by CopyFramePosition in CloseFocusMode.
        if not self._fromFocusMode then
            RestoreWindowPos(self)
        end
        self._fromFocusMode = false
        if chrome.OnShow then chrome.OnShow() end
        if BNB.RefreshNoteList then BNB.RefreshNoteList() end
        local sel = BigNoteBoxDB.selectedNoteID
        local ndb = BNB.NotesDB()
        -- Recovery: if the previously selected note is a title-less stub (abandoned
        -- new-note creation from a prior session), purge it silently before restoring.
        if sel and ndb.notes[sel] then
            local stub = ndb.notes[sel]
            if stub.title == nil or stub.title == "" then
                if BNB.PurgeNote then BNB.PurgeNote(sel) end
                BigNoteBoxDB.selectedNoteID = nil
                sel = nil
            end
        end
        if sel and ndb.notes[sel] then
            if BNB.SelectNote then BNB.SelectNote(sel) end
        end
        -- Apply scale lock state from saved DB
        BNB._applyScaleLock()
    end)

    f:SetScript("OnHide", function(self)
        -- The Hide that ends this build (below) is not a close: the frame is
        -- still at its default size in the centre, and saving here wrote that
        -- over the saved position whenever the UI was already visible while the
        -- window was built (ALL-97 J4, 2026-10-03: "moves back to the center")
        if not self._built then return end
        -- Focus mode hides the main window silently — skip confirm/save.
        if self._focusHide then
            -- Focus mode also leaves multi-select, same as a close
            if BNB.IsMultiMode and BNB.IsMultiMode() then BNB.SetMultiMode(false) end
            return
        end
        -- If confirmClose is on and this hide wasn't explicitly approved,
        -- re-show the window and display the confirm popup instead.
        -- _skipConfirm is set by RequestCloseMainWindow when the user confirmed.
        if BigNoteBoxDB and BigNoteBoxDB.confirmClose and not self._skipConfirm then
            -- Re-show immediately (this OnHide fires before the frame is hidden)
            C_Timer.After(0, function()
                if not self:IsShown() then
                    self:Show()
                    StaticPopup_Show("BNB_CONFIRM_CLOSE")
                end
            end)
            return
        end
        BNB.SaveCurrentNote()
        -- An untouched quick note goes with the window (ALL-199). Only on a
        -- real close: Focus mode returns above, so a note being written there stays
        if BNB.DropEmptyQuickNote then BNB.DropEmptyQuickNote(nil) end
        SaveWindowPos(self)
        BigNoteBoxDB.selectedNoteID = BNB._currentNoteID
        BigNoteBoxDB.splitX = BNB._listPaneW
        -- Reset favourite filter so it doesn't persist across window open/close
        BNB._favFilterActive = false
        if BNB._favBtn then
            BNB._favBtn:SetAlpha(0.35)
            pcall(function() BNB._favBtn._tx:SetDesaturated(true) end)
        end
        -- Leave multi-select: its buttons and selection must not survive a close.
        -- After the confirmClose check, so a cancelled close keeps the selection
        if BNB.IsMultiMode and BNB.IsMultiMode() then BNB.SetMultiMode(false) end
        -- Close companion windows
        BNB.CloseCompanionWindows()
    end)

    f:Hide()
    f._built = true
    BNB.mainFrame = f

    -- Re-check BCB presence each time the window opens (BCB may load after BNB)
    f:HookScript("OnShow", function()
        if BNB._refreshImportBtn then BNB._refreshImportBtn() end
    end)

    if BNB._notesAvailable then
        if BNB.BuildNoteList   then BNB.BuildNoteList()   end
        if BNB.BuildNoteEditor then BNB.BuildNoteEditor() end
    else
        BNB.BuildNotesUnavailablePanel(listPane, editorPane)
    end

    -- Hook for NoteList collapse toggle: adjusts split position
    -- collapsed = true  → pane shrinks to COLLAPSED_W, splitter disabled
    -- collapsed = false → pane restores to saved width, splitter re-enabled
    BNB._applyListCollapse = function(collapsed, collapsedW)
        if collapsed then
            BigNoteBoxDB.splitX = BNB._listPaneW
            BNB._listPaneW = collapsedW
            -- Disable splitter so the divider can't be dragged in icon-only mode
            splitter:EnableMouse(false)
        else
            BNB._listPaneW = math.max(
                BigNoteBoxDB.splitX or BNB.DEFAULTS.splitX,
                collapsedW + 40)
            splitter:EnableMouse(true)
        end
        ApplySplit(f)
    end
end

--------------------------------------------------------------------------------
-- TOOLBAR ICON ROW
-- row:   icons in slot order, right to left, each already anchored at its own
--        slot. Their anchors are recorded as the slot positions; visible icons
--        are packed into the first slots, so a hidden icon leaves no gap.
-- Visibility: everything hides in multi-select (the action buttons use that
-- space); the trash icon also hides while Trash is off in Settings, the
-- alarms and history icons while their modules are off, the sidebar toggle
-- while the Character Sidebar is off.
--------------------------------------------------------------------------------
-- _tbRow, _tbSlots are declared with the toolbar strip art above (live lift)

function BNB.InitToolbarIconRow(row)
    _tbRow, _tbSlots = row, {}
    for i, btn in ipairs(row) do
        _tbSlots[i] = { btn:GetPoint(1) }
    end
    BNB.ApplyToolbarIcons()
end

function BNB.ApplyToolbarIcons()
    if not _tbRow then return end
    local multi   = BNB.IsMultiMode and BNB.IsMultiMode() or false
    local trashOn = not BigNoteBoxDB or BigNoteBoxDB.trashFeature ~= false
    local alarmsOn = BNB.AlarmsEnabled()    -- Alarms module (ALL-343)
    local histOn   = BNB.HistoryEnabled()   -- Note History module (ALL-343)
    local sideOn   = BNB.Sidebar and BNB.Sidebar.IsEnabled and BNB.Sidebar.IsEnabled() or false
    local slot = 0
    for _, btn in ipairs(_tbRow) do
        local show = not multi and (btn ~= BNB._toolbarTrashBtn or trashOn)
                     and (btn ~= BNB._toolbarAlarmsBtn or alarmsOn)
                     and (btn ~= BNB._toolbarHistoryBtn or histOn)
                     and (btn ~= BNB._toolbarSidebarBtn or sideOn)
        btn:SetShown(show)
        if show then
            slot = slot + 1
            local p = _tbSlots[slot]
            btn:ClearAllPoints()
            btn:SetPoint(p[1], p[2], p[3], p[4], p[5])
        end
    end
end

--------------------------------------------------------------------------------
-- REQUEST CLOSE — respects the confirmClose setting
-- Used by CloseButton, ESC (UISpecialFrames hides the frame directly, so we
-- override OnHide to intercept that path too).
--------------------------------------------------------------------------------
function BNB.RequestCloseMainWindow()
    if not BNB.mainFrame then return end
    if BigNoteBoxDB.confirmClose and not BNB.mainFrame._skipConfirm then
        StaticPopup_Show("BNB_CONFIRM_CLOSE")
    else
        BNB.mainFrame._skipConfirm = true
        BNB.mainFrame:Hide()
        BNB.mainFrame._skipConfirm = false
    end
end

-- Hides the main window but leaves Settings open: the Oracle settings page
-- shows its preview in the main window's place (UI/Config/OracleSettings.lua).
-- The note is saved as on any close; no close confirmation. Returns true
-- when the window was shown, so the caller knows to bring it back.
-- BNB._keepSettingsOpen is the page's own flag, set for as long as the page
-- is open (not just around this Hide: a close that ran outside it, traced
-- 2026-09-28, still took Settings with it).
function BNB.HideMainWindowKeepSettings()
    local f = BNB.mainFrame
    if not (f and f:IsShown()) then return false end
    f._skipConfirm = true
    f:Hide()
    f._skipConfirm = false
    return true
end

-- Close all companion windows (the `companion` entries in WINDOWS).
-- Called from OnHide and from RequestCloseMainWindow so all close paths are covered.
function BNB.CloseCompanionWindows()
    for _, e in ipairs(WINDOWS) do
        local c = e.companion
        if c then
            local w = e.name and _G[e.name]
            if c == true then
                if w and w:IsShown() then w:Hide() end
            else
                c(w)
            end
        end
    end
end

-- Raise all currently-visible BNB frames together so clicking the main window
-- never leaves companion windows stranded behind other addon frames. The main
-- window first, then WINDOWS from the bottom up, so the window ESC would close
-- first ends on top.
local function RaiseShown(name)
    local fr = _G[name]
    if fr and fr:IsShown() then pcall(fr.Raise, fr) end
end
-- The open windows keep their stacking among themselves: raised lowest first
-- (strata, then frame level), so the one on top stays on top. Raising them in
-- WINDOWS order reset the stack to that order on every click.
local STRATA_RANK = { BACKGROUND = 1, LOW = 2, MEDIUM = 3, HIGH = 4, DIALOG = 5,
    FULLSCREEN = 6, FULLSCREEN_DIALOG = 7, TOOLTIP = 8 }
function BNB.RaiseBNBWindows()
    RaiseShown("BigNoteBoxFrame")
    local open = {}
    for _, e in ipairs(WINDOWS) do
        local fr = e.raise and _G[e.name]
        if fr and fr:IsShown() then open[#open + 1] = fr end
    end
    table.sort(open, function(a, b)
        local ra, rb = STRATA_RANK[a:GetFrameStrata()] or 0, STRATA_RANK[b:GetFrameStrata()] or 0
        if ra ~= rb then return ra < rb end
        return a:GetFrameLevel() < b:GetFrameLevel()
    end)
    for _, fr in ipairs(open) do pcall(fr.Raise, fr) end
end

-- Focus mode (UI/FocusEditor.lua): which `focus` windows are open now, and
-- reopening them afterwards in their `focus` order.
function BNB.SnapshotWindows()
    local open = {}
    for _, e in ipairs(WINDOWS) do
        local w = e.focus and _G[e.name]
        if w and w:IsShown() then open[e.name] = true end
    end
    return open
end

function BNB.ReopenWindows(open, noteID)
    if not open then return end
    local list = {}
    for _, e in ipairs(WINDOWS) do
        if e.focus and open[e.name] then list[#list + 1] = e end
    end
    table.sort(list, function(a, b) return a.focus < b.focus end)
    for _, e in ipairs(list) do e.reopen(noteID) end
end

--------------------------------------------------------------------------------
-- TOGGLE WINDOW
--------------------------------------------------------------------------------
function BNB.ToggleWindow()
    if InCombatLockdown() then BNB:Print(L["COMBAT_BLOCKED"]); return end
    if not BNB.mainFrame then BNB.OpenMainWindow() end
    if BNB.mainFrame:IsShown() then
        BNB.RequestCloseMainWindow()
    else
        BNB.mainFrame:Show()
    end
end

--------------------------------------------------------------------------------
-- BCB PROMO POPUP
-- Shown when the user clicks the BCB toolbar button or "Get BigChatBox" icon
-- while BigChatBox is not installed.  One-time lazy-built frame, reused.
--------------------------------------------------------------------------------
local _bcbPromoFrame

-- Where BigChatBox can be downloaded: one full-width button per site, as on the
-- Report a bug window (ALL-390). A site joins the list when BCB ships there.
local BCB_LINKS = {
    { "CurseForge", "https://www.curseforge.com/wow/addons/bigchatbox" },
}

-- Same look as the Report a bug window (UI/BugReport.lua, ALL-390): its width,
-- padding, link buttons and Close button, height measured from the text.
local function BuildBCBPromo()
    local W, PAD   = 400, 20
    local LOGO     = 128
    local ASSETS   = "Interface\\AddOns\\BigNoteBox\\Assets\\"
    local f = BNB.CreateToolWindow({   -- shared chrome (CMP-02)
        name = "BigNoteBoxBCBPromoFrame", w = W, h = 1,
        title = L["MW_BCB_PROMO_TITLE"], toplevel = true, escClose = true, keyEsc = true,
    })
    local titleH = f._isSkin and BNB.TOOL_SKIN_TITLE_H or 36
    local innerW = W - PAD * 2

    -- ── BCB logo (256x256 displayed at 128x128, centred) ──────────────────────
    local logo = f:CreateTexture(nil, "ARTWORK")
    logo:SetSize(LOGO, LOGO)
    logo:SetPoint("TOP", f, "TOP", 0, -(titleH + 12))
    logo:SetTexture(ASSETS .. "BCB\\bcb-logo")

    -- ── "By Dukul" ────────────────────────────────────────────────────────────
    local byLbl = f:CreateFontString(nil, "OVERLAY", "BNBFontNormalLarge")
    byLbl:SetPoint("TOP", logo, "BOTTOM", 0, -12)
    byLbl:SetWidth(innerW)
    byLbl:SetJustifyH("CENTER")
    byLbl:SetTextColor(0.31, 0.76, 1.0, 1)
    byLbl:SetText(L["MW_BCB_PROMO_BY"])

    -- ── Description ───────────────────────────────────────────────────────────
    local desc = f:CreateFontString(nil, "OVERLAY", "BNBFontHighlight")
    desc:SetPoint("TOP", byLbl, "BOTTOM", 0, -10)
    desc:SetWidth(innerW)
    desc:SetJustifyH("CENTER")
    desc:SetSpacing(2)
    desc:SetText(L["MW_BCB_PROMO_DESC"])

    -- ── Site buttons, full width ──────────────────────────────────────────────
    local BTN_H, GAP = BNB.LINK_BTN_H or 24, BNB.LINK_BTN_GAP or 6
    local prev = desc
    for i, site in ipairs(BCB_LINKS) do
        local b = BNB.CreateLinkButton(f, site[1], site[2], f._isSkin)
        b:SetPoint("TOP", prev, "BOTTOM", 0, i == 1 and -16 or -GAP)
        b:SetWidth(innerW)
        prev = b
    end
    local linksH = #BCB_LINKS * BTN_H + (#BCB_LINKS - 1) * GAP

    -- ── Screenshots: bcb-left + bcb-right side by side, 80% of the width ──────
    local half = math.floor(W * 0.80 / 2)   -- 160 each
    local ssLeft = f:CreateTexture(nil, "ARTWORK")
    ssLeft:SetSize(half, half)
    ssLeft:SetPoint("TOPRIGHT", prev, "BOTTOM", 0, -16)
    ssLeft:SetTexture(ASSETS .. "BCB\\bcb-left")

    local ssRight = f:CreateTexture(nil, "ARTWORK")
    ssRight:SetSize(half, half)
    ssRight:SetPoint("LEFT", ssLeft, "RIGHT", 0, 0)
    ssRight:SetTexture(ASSETS .. "BCB\\bcb-right")

    local close = BNB.CreateButton(nil, f, L["CLOSE"], 120, 26)
    close:SetPoint("BOTTOM", f, "BOTTOM", 0, 16)
    close:SetScript("OnClick", function() f:Hide() end)

    f:SetHeight(titleH + 12 + LOGO + 12 + byLbl:GetStringHeight() + 10
        + desc:GetStringHeight() + 16 + linksH + 16 + half + 20 + 26 + 16)

    f:Hide()
    return f
end

-- The toolbar's Send to BCB: the note into BCB's multi-line box. A BCB with no
-- box (Classic, or switched off in BCB) gets the Send to Chat window instead,
-- which sends line by line through BCB (ALL-367); no BCB = the promo.
function BNB.SendCurrentNoteToBCB()
    if not (BigChatBox and BigChatBox.SendDirect) then
        if BNB.ShowBCBPromo then BNB.ShowBCBPromo() end
        return
    end
    local id   = BNB._currentNoteID
    local note = id and BNB.GetNote(id)
    local body = note and (note.body or "") or ""
    if body == "" then
        BNB:Print(L["MW_NOTE_EMPTY"])
        return
    end
    if not BNB.OpenInBCB(body) and BNB.OpenSendToChat then BNB.OpenSendToChat(id) end
end

function BNB.ShowBCBPromo()
    if not _bcbPromoFrame then
        _bcbPromoFrame = BuildBCBPromo()
    end
    if _bcbPromoFrame:IsShown() then
        _bcbPromoFrame:Hide()
    else
        _bcbPromoFrame:ClearAllPoints()
        _bcbPromoFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 60)
        _bcbPromoFrame:Show()
        _bcbPromoFrame:Raise()
    end
end
-- Settings > Notes "Open Note Settings for new notes" (nil = on). Both ways of
-- making a new note ask this: CreateNewNote below and UI/NewNoteDialog.lua.
function BNB.OpenConfigOnNew()
    return not (BigNoteBoxDB and BigNoteBoxDB.openConfigOnNew == false)
end

function BNB.CreateNewNote()
    if InCombatLockdown() then BNB:Print(L["COMBAT_BLOCKED"]); return end

    local behaviour = BigNoteBoxDB and BigNoteBoxDB.newNoteBehaviour
    -- Default (nil) = "prompt"
    if behaviour ~= "immediate" then
        -- Open the styled creation dialog
        if BNB.NewNoteDialog and BNB.NewNoteDialog.Open then
            BNB.NewNoteDialog.Open()
        end
        return
    end

    -- "Create immediately" path ─────────────────────────────────────────────
    -- If there's already an empty unsaved note in the editor, just show the
    -- window and focus the title field instead of creating another stub.
    if BNB._currentNoteID then
        local cur = BNB.GetNote(BNB._currentNoteID)
        if cur and (cur.title == nil or cur.title == "") and (cur.body == nil or cur.body == "") then
            if not BNB.mainFrame then BNB.OpenMainWindow() end
            if not BNB.mainFrame:IsShown() then BNB.mainFrame:Show() end
            C_Timer.After(0.05, function()
                if BNB._editorTitle then BNB._editorTitle:SetFocus() end
            end)
            return
        end
    end

    BNB.SaveCurrentNote()

    local id = BNB.CreateNote("")   -- empty title -> placeholder shows
    BNB._justCreatedNoteID = id    -- tells LoadNoteInEditor to open in Editor mode
    local NOTE_ICONS = {
        "Interface\\Icons\\INV_Misc_Note_01",
        "Interface\\Icons\\INV_Misc_Note_02",
        "Interface\\Icons\\INV_Misc_Note_03",
        "Interface\\Icons\\INV_Misc_Note_05",
        "Interface\\Icons\\INV_Misc_Note_06",
    }
    BNB.UpdateNote(id, { icon = NOTE_ICONS[math.random(#NOTE_ICONS)] })

    if not BNB.mainFrame then BNB.OpenMainWindow() end
    if not BNB.mainFrame:IsShown() then BNB.mainFrame:Show() end

    -- "New notes belong to" may put it outside the selected tab (ALL-267)
    if BNB.RevealNoteInList then BNB.RevealNoteInList(id) end
    if BNB.SelectNote      then BNB.SelectNote(id)   end

    C_Timer.After(0.05, function()
        if BNB._editorTitle then BNB._editorTitle:SetFocus() end
        if BNB.OpenConfigOnNew() and BNB.OpenNoteConfig then BNB.OpenNoteConfig(id) end
    end)
    -- Mark this note as pending (no title yet) so the discard guard knows
    -- to prompt before silently deleting it.
    BNB._pendingNewNoteID = id
end

--------------------------------------------------------------------------------
-- NOTES UNAVAILABLE PANEL
-- Shown in place of the note list + editor when BigNoteBoxDB is not loaded.
-- Spans the full inner area of the main window.
--------------------------------------------------------------------------------
function BNB.BuildNotesUnavailablePanel(listPane, editorPane)
    -- Hide the normal panes so the warning fills the window
    listPane:Hide()
    editorPane:Hide()

    local f = BNB.mainFrame
    if not f then return end

    local panel = CreateFrame("Frame", nil, f)
    panel:SetPoint("TOPLEFT",     f, "TOPLEFT",     0, -40)
    panel:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0,   0)
    panel:EnableMouse(false)

    -- Big red warning icon (use a standard Blizzard alert texture)
    local icon = panel:CreateTexture(nil, "ARTWORK")
    icon:SetSize(64, 64)
    icon:SetPoint("TOP", panel, "TOP", 0, -40)
    icon:SetAtlas("UI-Frame-ErrorDialog-Icon")

    -- Header
    local header = panel:CreateFontString(nil, "OVERLAY", "BNBFontNormalHuge")
    header:SetPoint("TOP", icon, "BOTTOM", 0, -16)
    header:SetTextColor(1, 0.25, 0.25)
    header:SetText(L["MW_DB_UNAVAILABLE_HEADER"])

    -- Body explanation
    local body = panel:CreateFontString(nil, "OVERLAY", "BNBFontNormal")
    body:SetPoint("TOP", header, "BOTTOM", 0, -16)
    body:SetWidth(480)
    body:SetJustifyH("CENTER")
    body:SetSpacing(3)
    body:SetTextColor(0.85, 0.85, 0.85)
    body:SetText(L["MW_DB_UNAVAILABLE_BODY"])

    -- Reload button
    local reloadBtn = BNB.CreateButton(nil, panel, L["CFG_RELOAD_UI_BTN"], 140, 30)
    reloadBtn:SetPoint("TOP", body, "BOTTOM", 0, -24)
    reloadBtn:SetScript("OnClick", function() C_UI.Reload() end)
end

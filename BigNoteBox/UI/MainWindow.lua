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
local DEFAULT_LIST_W = 240
-- Icon-only collapsed width: 8px left pad + 32px icon + 8px right pad + 22px scrollbar + 2px buffer = 72px
-- Must match COLLAPSED_W in NoteList.lua
local COLLAPSED_W    = 82   -- PAD_L(8) + ICON_SIZE_SPACIOUS(42) + PAD_L(8) + scrollbar(22) + 2

local SORT_BTN_H = 22   -- height to match WowStyle1 button
local ICON_STEP  = 24   -- toolbar icon size (20) + gap (4)

local BTNS   = "Interface\\AddOns\\BigNoteBox\\Assets\\Buttons\\"
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
--   AddTitleButtons(lockBtn, MakeTexBtn)  extra title-bar buttons left of lock
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
    local w = math.max(pos.w or DEFAULT_W, MIN_W)
    local h = math.max(pos.h or DEFAULT_H, MIN_H)
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
-- Texture button with a normal / hover / press TGA set (Assets\Buttons\).
-- Textures are exposed as _n / _h / _p for callers that desaturate or swap them.
local function MakeTexBtn(parent, baseName, size, onClick, tipTitle, tipSub)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(size, size)
    -- Suppress WoW's default button flash so our press texture shows cleanly
    btn:SetHighlightTexture("")
    btn:SetPushedTexture("")

    local n = btn:CreateTexture(nil, "ARTWORK"); n:SetAllPoints()
    n:SetTexture(BTNS .. baseName .. "-normal")
    local h = btn:CreateTexture(nil, "ARTWORK"); h:SetAllPoints()
    h:SetTexture(BTNS .. baseName .. "-hover"); h:Hide()
    local p = btn:CreateTexture(nil, "ARTWORK"); p:SetAllPoints()
    p:SetTexture(BTNS .. baseName .. "-press"); p:Hide()

    btn:SetScript("OnClick",     function() if onClick then onClick() end end)
    btn:SetScript("OnMouseDown", function(self) if self:IsEnabled() then p:Show(); n:Hide(); h:Hide() end end)
    btn:SetScript("OnMouseUp",   function(self) p:Hide(); if self:IsEnabled() then h:Show() else n:Show() end end)
    btn:SetScript("OnEnter", function(self)
        if self:IsEnabled() then n:Hide(); h:Show() end
        if tipTitle then
            GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
            GameTooltip:AddLine(tipTitle, 1, 1, 1)
            if tipSub then GameTooltip:AddLine(tipSub, 0.78, 0.78, 0.78) end
            GameTooltip:Show()
        end
    end)
    btn:SetScript("OnLeave", function()
        p:Hide(); h:Hide(); n:Show()
        GameTooltip:Hide()
    end)

    btn._n, btn._h, btn._p = n, h, p
    return btn
end

-- Toolbar icon: plain Button, no template, fixed TOPRIGHT anchor on the window.
local function MakeIconToolbarBtn(f, iconTex, tooltipText, x, y, onClick)
    local ICON_BTN_SIZE = 20
    local btn = CreateFrame("Button", nil, f)
    btn:SetSize(ICON_BTN_SIZE, ICON_BTN_SIZE)
    btn:SetPoint("TOPRIGHT", f, "TOPRIGHT", x, y)

    local iconTx = btn:CreateTexture(nil, "ARTWORK")
    -- Texture slightly inset at rest; expands to fill (and slightly overflow)
    -- the fixed hitbox on hover — gives a centred grow effect without moving
    -- the frame anchor or shifting cursor hit registration.
    local REST  = 2   -- inset each side at rest  (renders at ICON_BTN_SIZE - 4)
    local HOVER = 2   -- outset each side on hover (renders at ICON_BTN_SIZE + 4)
    iconTx:SetPoint("TOPLEFT",     btn, "TOPLEFT",      REST, -REST)
    iconTx:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -REST,  REST)
    iconTx:SetTexture(iconTex)
    btn._tx = iconTx   -- exposed for SetDesaturated / alpha callers

    btn:SetScript("OnEnter", function(self)
        iconTx:SetPoint("TOPLEFT",     btn, "TOPLEFT",      -HOVER,  HOVER)
        iconTx:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT",   HOVER, -HOVER)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:AddLine(tooltipText, 1, 1, 1)
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function()
        iconTx:SetPoint("TOPLEFT",     btn, "TOPLEFT",      REST, -REST)
        iconTx:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -REST,  REST)
        GameTooltip:Hide()
    end)
    btn:SetScript("OnClick", onClick)
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
-- Locked → bt-lock textures, unlocked → bt-unlock. State persists via
-- BigNoteBoxDB.scaleLocked. Right-click resets the window size and position.
--------------------------------------------------------------------------------
local function IsLocked() return BigNoteBoxDB and BigNoteBoxDB.scaleLocked end

local function MakeLockBtn(f, parent, size)
    local lockBtn = CreateFrame("Button", nil, parent)
    lockBtn:SetSize(size, size)
    lockBtn:SetHighlightTexture("")
    lockBtn:SetPushedTexture("")

    local lockTex     = lockBtn:CreateTexture(nil, "ARTWORK"); lockTex:SetAllPoints()
    local unlockTex   = lockBtn:CreateTexture(nil, "ARTWORK"); unlockTex:SetAllPoints()
    local lockHov     = lockBtn:CreateTexture(nil, "ARTWORK"); lockHov:SetAllPoints();     lockHov:Hide()
    local unlockHov   = lockBtn:CreateTexture(nil, "ARTWORK"); unlockHov:SetAllPoints();   unlockHov:Hide()
    local lockPress   = lockBtn:CreateTexture(nil, "ARTWORK"); lockPress:SetAllPoints();   lockPress:Hide()
    local unlockPress = lockBtn:CreateTexture(nil, "ARTWORK"); unlockPress:SetAllPoints(); unlockPress:Hide()

    lockTex:SetTexture(BTNS .. "bt-lock-normal")
    unlockTex:SetTexture(BTNS .. "bt-unlock-normal")
    lockHov:SetTexture(BTNS .. "bt-lock-hover")
    unlockHov:SetTexture(BTNS .. "bt-unlock-hover")
    lockPress:SetTexture(BTNS .. "bt-lock-press")
    unlockPress:SetTexture(BTNS .. "bt-unlock-press")

    local function RefreshLockBtn()
        local locked = IsLocked()
        lockTex:SetShown(locked);   unlockTex:SetShown(not locked)
        lockHov:Hide(); unlockHov:Hide(); lockPress:Hide(); unlockPress:Hide()
    end
    RefreshLockBtn()

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
    end)
    lockBtn:SetScript("OnMouseDown", function()
        local locked = IsLocked()
        lockTex:Hide(); unlockTex:Hide(); lockHov:Hide(); unlockHov:Hide()
        if locked then lockPress:Show() else unlockPress:Show() end
    end)
    lockBtn:SetScript("OnMouseUp", function()
        lockPress:Hide(); unlockPress:Hide()
        if IsLocked() then lockHov:Show() else unlockHov:Show() end
    end)
    lockBtn:SetScript("OnEnter", function(self)
        local locked = IsLocked()
        if locked then lockTex:Hide();   lockHov:Show()
        else           unlockTex:Hide(); unlockHov:Show() end
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        if locked then
            GameTooltip:AddLine(L["MW_LOCK_TIP"], 1, 1, 1)
            GameTooltip:AddLine(L["MW_LOCK_TIP_SUB"], 0.78, 0.78, 0.78)
        else
            GameTooltip:AddLine(L["MW_UNLOCK_TIP"], 1, 1, 1)
            GameTooltip:AddLine(L["MW_UNLOCK_TIP_SUB"], 0.78, 0.78, 0.78)
        end
        GameTooltip:AddLine(L["MW_LOCK_RESET_TIP"], 0.55, 0.55, 0.55)
        GameTooltip:Show()
    end)
    lockBtn:SetScript("OnLeave", function() RefreshLockBtn(); GameTooltip:Hide() end)
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
-- Hides a shown window through its close function (plain Hide without one).
local function TryHide(name, closeFn)
    local w = _G[name]
    if w and w:IsShown() then
        if closeFn then closeFn() else w:Hide() end
        return true
    end
end

local function OnEscapeKey(self, key)
    if key ~= "ESCAPE" then self:SetPropagateKeyboardInput(true); return end
    self:SetPropagateKeyboardInput(false)
    -- DIALOG-strata popups first: New Note dialog, clipboard hint, icon picker
    -- (sidebar right-click → Change icon), Insert Info menu
    if TryHide("BNBNewNoteDialogFrame",
        BNB.NewNoteDialog and BNB.NewNoteDialog.Close) then return end
    if TryHide("BNBClipboardHintFrame",
        BNB._clipboardHint and BNB._clipboardHint._dismiss) then return end
    if TryHide("BNBSidebarIconPickerFrame") then return end
    if BNB.CloseInsertInfoMenu and BNB.CloseInsertInfoMenu() then return end
    if TryHide("BigNoteBoxExportFrame")   then return end
    if TryHide("BigNoteBoxCopyMoveFrame") then return end
    if TryHide("BigNoteBoxHistoryCompareFrame", BNB.CloseHistoryCompare) then return end
    -- Alarm setter window closes before sticky settings
    if TryHide("BNBAlarmWindow", BNB.AlarmWindow and BNB.AlarmWindow.Close) then return end
    if TryHide("BNBAlarmOverviewFrame") then return end
    if TryHide("BigNoteBoxStickySettingsFrame",
        BNB.Sticky and BNB.Sticky.CloseSettings) then return end
    if TryHide("BigNoteBoxTagManagerFrame") then return end
    -- Per-note history panel, then the main history window (also closes panel)
    if TryHide("BigNoteBoxNoteHistoryFrame", BNB.CloseNoteHistoryPanel) then return end
    if TryHide("BigNoteBoxHistoryFrame",     BNB.CloseHistoryWindow)    then return end
    -- Trash view popup before the trash window itself
    if TryHide("BNBTrashViewPopup")    then return end
    if TryHide("BigNoteBoxTrashFrame") then return end
    if TryHide("BigNoteBoxNoteConfigFrame") then return end
    -- Task Edit Window before the Reference Box
    if TryHide("BNBTaskEditWindow",
        BNB.TaskEditWindow and BNB.TaskEditWindow.Close) then return end
    if TryHide("BigNoteBoxReferenceBoxFrame") then return end
    -- Share preview, then share, then import, all before the main window
    if TryHide("BNBSharePreviewFrame", BNB.CloseSharePreview) then return end
    if TryHide("BNBShareFrame",        BNB.CloseShareWindow)  then return end
    if TryHide("BNBImportFrame",       BNB.CloseImportWindow) then return end
    -- Addon settings window
    if TryHide("BigNoteBoxConfigFrame") then return end
    -- Otherwise close main window (with confirm if enabled)
    BNB.RequestCloseMainWindow()
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
    f:SetTitle(L["WINDOW_TITLE"])

    if f.CloseButton then
        f.CloseButton:SetScript("OnClick", function()
            BNB.RequestCloseMainWindow()
        end)
    end

    -- The toolbar strip sits in the title area below the "BigNoteBox" title:
    -- sort row top-left, icons top-right 4px above the pane top edge.
    local sortY = -(TITLE_H - 14) + SORT_BTN_H / 2
    return {
        frame     = f,
        headerH   = TITLE_H,
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
        iconY     = -(TITLE_H - 22),
        -- Forever: soft glow behind the note list so the side panel stands out
        -- against the wood grain; stretches with the pane (splitter, resize, collapse)
        StylePanes = function(listPane)
            listPane._forGlow = BNB.AddForeverGlow(listPane)
        end,
    }
end

--------------------------------------------------------------------------------
-- CREATE MAIN WINDOW
--------------------------------------------------------------------------------
function BNB.CreateMainWindow()
    if BNB.mainFrame then return end

    -- Restore saved split width
    BNB._listPaneW = math.max(MIN_LIST_W,
        math.min(MAX_LIST_W, BigNoteBoxDB.splitX or DEFAULT_LIST_W))

    local skin = BigNoteBoxDB.skinMode and BNB.BuildMainWindowSkinChrome
    local chrome = skin and BNB.BuildMainWindowSkinChrome() or BuildClassicChrome()
    local f = chrome.frame
    f._headerH = chrome.headerH

    f:SetSize(DEFAULT_W, DEFAULT_H)
    f:SetPoint("CENTER")
    f:SetToplevel(true)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:SetResizable(true)   -- REQUIRED — ButtonFrameTemplate does not set this
    f:SetClampedToScreen(true)
    for _, handle in ipairs({ f, chrome.dragBar }) do
        handle:RegisterForDrag("LeftButton")
        handle:SetScript("OnDragStart", function() f:StartMoving() end)
        handle:SetScript("OnDragStop",  function()
            f:StopMovingOrSizing()
            SaveWindowPos(f)
        end)
    end
    -- When the main window is clicked/raised, bring all visible BNB windows
    -- to the front together so none get left behind other frames.
    f:SetScript("OnMouseDown", function()
        if BNB.RaiseBNBWindows then BNB.RaiseBNBWindows() end
    end)

    -- ── Title-bar buttons: focus mode, scale lock (right to left) ─────────────
    if chrome.closeBtn then
        local focusBtn = MakeTexBtn(chrome.btnParent, "bt-focus", chrome.btnSize,
            function() if BNB.OpenFocusMode then BNB.OpenFocusMode() end end,
            L["FOCUS_MODE_TIP"], L["FOCUS_MODE_TIP_SUB"])
        focusBtn:SetPoint("RIGHT", chrome.closeBtn, "LEFT", -chrome.btnGap, 0)
        BNB._focusModeBtn = focusBtn
        -- Start disabled — no note selected yet; UpdateSaveButtonState re-enables on note load
        focusBtn:SetEnabled(false)
        focusBtn:SetAlpha(0.35)
        pcall(function() focusBtn._n:SetDesaturated(true) end)

        local lockBtn = MakeLockBtn(f, chrome.btnParent, chrome.btnSize)
        lockBtn:SetPoint("RIGHT", focusBtn, "LEFT", -chrome.btnGap, 0)

        if chrome.AddTitleButtons then chrome.AddTitleButtons(lockBtn, MakeTexBtn) end
    end

    -- ── Toolbar icons (right side of the toolbar strip) ──────────────────────
    -- Slot 0 is the right-most (sidebar toggle); each slot one ICON_STEP left.
    local function TBIcon(tex, tip, slot, onClick)
        return MakeIconToolbarBtn(f, tex, tip,
            chrome.iconX - ICON_STEP * slot, chrome.iconY, onClick)
    end

    local sidebarToggleBtn = TBIcon(TOPBAR .. "tp-sidebar-open", L["MW_SIDEBAR_TIP"], 0,
        function()
            if BNB.Sidebar and BNB.Sidebar.ToggleCollapsed then
                BNB.Sidebar.ToggleCollapsed()
            end
        end)
    BNB._toolbarSidebarBtn = sidebarToggleBtn

    -- Refreshes sidebar toggle icon to match current state
    function BNB.RefreshSidebarToggleBtn()
        local collapsed = BigNoteBoxDB and BigNoteBoxDB.sidebarCollapsed
        local tex = TOPBAR .. (collapsed and "tp-sidebar-closed" or "tp-sidebar-open")
        pcall(function() BNB._toolbarSidebarBtn._tx:SetTexture(tex) end)
    end
    BNB.RefreshSidebarToggleBtn()

    local configBtn = TBIcon(TOPBAR .. "tp-cog", L["MW_CONFIG_TIP"], 1,
        function() if BNB.OpenConfig then BNB.OpenConfig() end end)
    BNB._toolbarConfigBtn = configBtn

    local trashBtn = TBIcon(TOPBAR .. "tp-trash", L["MW_TRASH_TIP"], 2,
        function() if BNB.ToggleTrashWindow then BNB.ToggleTrashWindow() end end)
    BNB._toolbarTrashBtn = trashBtn

    -- History button (desaturated until history exists)
    local histBtn = TBIcon(TOPBAR .. "tp-history", L["HISTORY_TOOLBAR_TIP"], 3,
        function() if BNB.ToggleHistoryWindow then BNB.ToggleHistoryWindow() end end)
    histBtn:SetEnabled(false)
    histBtn:SetAlpha(0.4)
    pcall(function() histBtn._tx:SetDesaturated(true) end)
    BNB._toolbarHistoryBtn = histBtn

    local tagsBtn = TBIcon(TOPBAR .. "tp-tags", L["TAG_MGR_TOOLTIP"], 4,
        function() if BNB.ToggleTagManager then BNB.ToggleTagManager() end end)
    BNB._toolbarTagsBtn = tagsBtn

    -- Share/import button — toggles the import-only window
    local shareTopBtn = TBIcon(TOPBAR .. "tp-share", L["MW_IMPORT_SHARED_TIP"], 5,
        function()
            local iw = _G["BNBImportFrame"]
            if iw and iw:IsShown() then
                if BNB.CloseImportWindow then BNB.CloseImportWindow() end
            else
                if BNB.OpenImportWindow then BNB.OpenImportWindow() end
            end
        end)
    BNB._toolbarShareTopBtn = shareTopBtn

    -- Alarm overview button
    local alarmOvBtn = TBIcon(TOPBAR .. "tp-alarm", L["MW_ALARM_TIP"], 6,
        function()
            if BNB.AlarmOverview and BNB.AlarmOverview.Toggle then
                BNB.AlarmOverview.Toggle()
            end
        end)
    BNB._toolbarAlarmOvBtn = alarmOvBtn

    -- Send-to-BCB button. Icon: tp-bcb when BCB is installed, bcb-icon when
    -- absent. Always full colour.
    local importBtn = TBIcon(
        (BigChatBox and BigChatBox.SendDirect) and TOPBAR .. "tp-bcb" or BCB_PROMO_ICON,
        L["MW_BCB_SEND_TIP"], 7,
        function()
            if not (BigChatBox and BigChatBox.SendDirect) then
                -- BCB absent: show promo popup
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
            if BCB_OpenMultiline then BCB_OpenMultiline() end
            C_Timer.After(0.05, function()
                if BigChatBox.mlEditBox then
                    BigChatBox.mlEditBox:SetText(body)
                    BigChatBox.mlEditBox:SetFocus()
                    BigChatBox.mlEditBox:SetCursorPosition(#body)
                end
            end)
        end)
    -- Re-evaluates BCB presence and swaps icon; called after BCB loads late.
    local function RefreshImportBtn()
        local hasBCB = BigChatBox and BigChatBox.SendDirect and true or false
        pcall(function()
            importBtn._tx:SetTexture(hasBCB and TOPBAR .. "tp-bcb" or BCB_PROMO_ICON)
            importBtn._tx:SetDesaturated(false)
            importBtn:SetAlpha(1.0)
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
    -- WowStyle1 dropdowns where the template exists, cycling buttons otherwise.
    -- The order dropdown is disabled (greyed out) when sort is "custom" since
    -- order has no meaning there.
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
    local function CurrentSortLabel()
        for _, m in ipairs(SORT_MODES) do
            if m.key == (BigNoteBoxDB.sortBy or "creation") then return m.label end
        end
        return L["SORT_MODE_CREATION"]
    end
    local function IsCustomSort()  return BigNoteBoxDB.sortBy == "custom" end
    local function CurrentDirKey() return BigNoteBoxDB.sortAsc and "asc" or "desc" end
    local function CurrentDirLabel()
        return BigNoteBoxDB.sortAsc and L["DIR_MODE_ASC"] or L["DIR_MODE_DESC"]
    end

    local sortDD, dirDD             -- WowStyle1 DropdownButtons (retail)
    local sortCycleBtn, dirCycleBtn -- fallback cycling buttons
    local DD_W = 120

    local function UpdateDirEnabled()
        local custom = IsCustomSort()
        if dirDD       then dirDD:SetEnabled(not custom);       dirDD:SetAlpha(custom and 0.4 or 1.0)       end
        if dirCycleBtn then dirCycleBtn:SetEnabled(not custom); dirCycleBtn:SetAlpha(custom and 0.4 or 1.0) end
    end

    -- Refreshes the list, then the order control (its state follows the sort key)
    local function ApplySort()
        if BNB.RefreshNoteList then BNB.RefreshNoteList() end
        UpdateDirEnabled()
        if dirDD and dirDD.GenerateMenu then dirDD:GenerateMenu() end
        if dirCycleBtn then dirCycleBtn:SetText(CurrentDirLabel()) end
    end

    local useNativeSort = C_XMLUtil and C_XMLUtil.GetTemplateInfo
        and C_XMLUtil.GetTemplateInfo("WowStyle1DropdownTemplate")

    if useNativeSort then
        sortDD = CreateFrame("DropdownButton", "BNBMainSortDD", f, "WowStyle1DropdownTemplate")
        sortDD:SetSize(DD_W, SORT_BTN_H)
        sortDD:SetPoint("TOPLEFT", f, "TOPLEFT", chrome.sortX, chrome.sortY)
        sortDD:SetupMenu(function(_, root)
            for _, m in ipairs(SORT_MODES) do
                local key = m.key
                root:CreateRadio(m.label,
                    function() return (BigNoteBoxDB.sortBy or "creation") == key end,
                    function() BigNoteBoxDB.sortBy = key; sortDD:GenerateMenu(); ApplySort() end)
            end
        end)

        dirDD = CreateFrame("DropdownButton", "BNBMainDirDD", f, "WowStyle1DropdownTemplate")
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
    else
        sortCycleBtn = BNB.CreateButton(nil, f, CurrentSortLabel(), DD_W, SORT_BTN_H)
        sortCycleBtn:SetPoint("TOPLEFT", f, "TOPLEFT", chrome.sortX, chrome.sortY)
        sortCycleBtn:SetScript("OnClick", function(self)
            local cur = BigNoteBoxDB.sortBy or "creation"
            local idx = 1
            for i, m in ipairs(SORT_MODES) do if m.key == cur then idx = i; break end end
            idx = (idx % #SORT_MODES) + 1
            BigNoteBoxDB.sortBy = SORT_MODES[idx].key
            self:SetText(CurrentSortLabel())
            ApplySort()
        end)

        dirCycleBtn = BNB.CreateButton(nil, f, CurrentDirLabel(), DD_W, SORT_BTN_H)
        dirCycleBtn:SetPoint("LEFT", sortCycleBtn, "RIGHT", 4, 0)
        dirCycleBtn:SetScript("OnClick", function(self)
            BigNoteBoxDB.sortAsc = not BigNoteBoxDB.sortAsc
            self:SetText(CurrentDirLabel())
            ApplySort()
        end)
    end

    -- Exposed so TagTree can disable sorting while tree view is active.
    -- Also disables the direction control, which has no meaning without sort
    -- either; re-enabling defers to UpdateDirEnabled so "custom" sort still
    -- greys it out (BUG found ALL-65.9, 2026-09-25: it never touched direction).
    function BNB.SetSortEnabled(enabled)
        local sortCtl = sortDD or sortCycleBtn
        sortCtl:SetEnabled(enabled)
        sortCtl:SetAlpha(enabled and 1.0 or 0.4)
        if enabled then
            UpdateDirEnabled()
        else
            local dirCtl = dirDD or dirCycleBtn
            dirCtl:SetEnabled(false)
            dirCtl:SetAlpha(0.4)
        end
    end

    -- ── Select-mode toggle + multi-select action buttons ─────────────────────
    local selBtn = MakeTipButton(f, L["MW_SELECT_BTN"], 52,
        L["MW_SELECT_TIP"], L["MW_SELECT_TIP_SUB"], nil)
    selBtn:SetPoint("LEFT", dirDD or dirCycleBtn, "RIGHT", 6, 0)
    selBtn:SetPoint("TOP", f, "TOP", 0, chrome.selY)
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

    f:SetPropagateKeyboardInput(false)
    f:EnableKeyboard(true)
    f:SetScript("OnKeyDown", OnEscapeKey)

    -- ── Resize (whole window, bottom-right) ─────────────────────────────────
    f:SetResizeBounds(MIN_W, MIN_H, MAX_W, MAX_H)
    local resizeHandle = CreateFrame("Button", nil, f)
    resizeHandle:SetSize(16, 16)
    resizeHandle:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -2, 2)
    resizeHandle:SetFrameLevel(f:GetFrameLevel() + 10)
    local rtex = resizeHandle:CreateTexture(nil, "OVERLAY")
    rtex:SetAllPoints()
    rtex:SetTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    f._resizeHandle = resizeHandle  -- stored for scale-lock toggle

    -- Small label that tracks the cursor during resize and shows WxH.
    local sizeLabel = CreateFrame("Frame", nil, UIParent)
    sizeLabel:SetSize(90, 22)
    sizeLabel:SetFrameStrata("TOOLTIP")
    sizeLabel:SetFrameLevel(100)
    sizeLabel:Hide()
    local sizeLabelBg = sizeLabel:CreateTexture(nil, "BACKGROUND")
    sizeLabelBg:SetAllPoints()
    sizeLabelBg:SetColorTexture(0, 0, 0, 0.75)
    local sizeLabelTxt = sizeLabel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    sizeLabelTxt:SetAllPoints()
    sizeLabelTxt:SetJustifyH("CENTER")
    sizeLabelTxt:SetTextColor(1, 1, 1)

    -- Sidebar width (BTN_SZ in Sidebar.lua = 64) subtracted when sidebar is visible
    -- so the label shows the notepad window size, not including the sidebar strip.
    local function SidebarW()
        return (BNB.Sidebar and BNB.Sidebar.IsEnabled and BNB.Sidebar.IsEnabled()) and 64 or 0
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

    resizeHandle:SetScript("OnMouseDown", function(self, btn)
        if btn ~= "LeftButton" then return end
        -- GetLeft/GetTop return nil if the frame hasn't been laid out yet;
        -- otherwise they are already in UIParent coordinate space
        local left, top = f:GetLeft(), f:GetTop()
        if left and top then
            f:ClearAllPoints()
            f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
        end
        _resizing = true
        -- Seed the label with current size before first OnSizeChanged fires
        UpdateSizeLabel()
        sizeLabel:Show()
        f:StartSizing("BOTTOMRIGHT")
    end)
    resizeHandle:SetScript("OnMouseUp", function()
        _resizing = false
        sizeLabel:Hide()
        f:StopMovingOrSizing()
        local w = math.max(MIN_W, math.min(MAX_W, f:GetWidth()))
        local h = math.max(MIN_H, math.min(MAX_H, f:GetHeight()))
        f:SetSize(w, h)
        SaveWindowPos(f)
        -- Re-apply split so panes adjust to new width
        ApplySplit(f)
        -- Recalculate sidebar slot visibility after resize
        if BNB.Sidebar and BNB.Sidebar.Refresh then BNB.Sidebar.Refresh() end
    end)

    -- ── Splitter drag handle (7px wide button over the divider) ─────────────
    -- No SetCursor — it produces a black box on some clients.
    -- Instead we make the splitter visually obvious with three grip dots.
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
                math.min(MAX_LIST_W, BigNoteBoxDB.splitX or DEFAULT_LIST_W))
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
        -- Recovery: if the previously selected note is a title-less stub (abandoned
        -- new-note creation from a prior session), purge it silently before restoring.
        if sel and BigNoteBoxNotesDB.notes[sel] then
            local stub = BigNoteBoxNotesDB.notes[sel]
            if stub.title == nil or stub.title == "" then
                if BNB.PurgeNote then BNB.PurgeNote(sel) end
                BigNoteBoxDB.selectedNoteID = nil
                sel = nil
                if BNB.RefreshNoteList then BNB.RefreshNoteList() end
            end
        end
        if sel and BigNoteBoxNotesDB.notes[sel] then
            if BNB.SelectNote then BNB.SelectNote(sel) end
        end
        -- Apply scale lock state from saved DB
        BNB._applyScaleLock()
    end)

    f:SetScript("OnHide", function(self)
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
                BigNoteBoxDB.splitX or DEFAULT_LIST_W,
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
-- space); the trash icon also hides while Trash is off in Settings.
--------------------------------------------------------------------------------
local _tbRow, _tbSlots

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
    local slot = 0
    for _, btn in ipairs(_tbRow) do
        local show = not multi and (btn ~= BNB._toolbarTrashBtn or trashOn)
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

-- Close all companion windows (NoteConfig, Config, SendToChat).
-- Called from OnHide and from RequestCloseMainWindow so all close paths are covered.
function BNB.CloseCompanionWindows()
    local nc  = _G["BigNoteBoxNoteConfigFrame"]
    local cfg = _G["BigNoteBoxConfigFrame"]
    local tw  = _G["BigNoteBoxTrashFrame"]
    local tm  = _G["BigNoteBoxTagManagerFrame"]
    local cm  = _G["BigNoteBoxCopyMoveFrame"]
    local ex  = _G["BigNoteBoxExportFrame"]
    if nc  and nc:IsShown()  then nc:Hide()  end
    if cfg and cfg:IsShown() then cfg:Hide() end
    if tw  and tw:IsShown()  then tw:Hide()  end
    if tm  and tm:IsShown()  then tm:Hide()  end
    if cm  and cm:IsShown()  then cm:Hide()  end
    if ex  and ex:IsShown()  then ex:Hide()  end
    if BNB.CloseRichPreview      then BNB.CloseRichPreview()      end
    if BNB.CloseHistoryCompare   then BNB.CloseHistoryCompare()   end
    if BNB.CloseNoteHistoryPanel then BNB.CloseNoteHistoryPanel() end
    if BNB.CloseHistoryWindow    then BNB.CloseHistoryWindow()    end
    if BNB.CloseSendToChat       then BNB.CloseSendToChat()       end
    if BNB.CloseShareWindow      then BNB.CloseShareWindow()      end  -- also closes preview
    if BNB.CloseImportWindow     then BNB.CloseImportWindow()     end
    if BNB.CloseReferenceBox     then BNB.CloseReferenceBox()     end
    if BNB.AlarmWindow and BNB.AlarmWindow.Close then BNB.AlarmWindow.Close() end
    local ao = _G["BNBAlarmOverviewFrame"]
    if ao and ao:IsShown() then ao:Hide() end
    if BNB.NewNoteDialog and BNB.NewNoteDialog.Close then BNB.NewNoteDialog.Close() end
end

-- Raise all currently-visible BNB frames together so clicking the main window
-- never leaves companion windows stranded behind other addon frames.
local BNB_RAISE_FRAMES = {
    "BigNoteBoxFrame",
    "BigNoteBoxReferenceBoxFrame",
    "BigNoteBoxNoteConfigFrame",
    "BigNoteBoxConfigFrame",
    "BigNoteBoxTrashFrame",
    "BigNoteBoxTagManagerFrame",
    "BigNoteBoxCopyMoveFrame",
    "BigNoteBoxExportFrame",
    "BigNoteBoxHistoryFrame",
    "BigNoteBoxHistoryCompareFrame",
    "BigNoteBoxNoteHistoryFrame",
    "BigNoteBoxStickySettingsFrame",
    "BNBAlarmWindow",
    "BNBAlarmOverviewFrame",
    "BNBShareFrame",
    "BNBSharePreviewFrame",
    "BNBImportFrame",
    "BNBTaskEditWindow",
    "BNBSidebarIconPickerFrame",
    "BigNoteBoxTagManagerFrame",
    "BigNoteBoxSendDialog",
    "BigNoteBoxSendConfirm",
}
function BNB.RaiseBNBWindows()
    for _, name in ipairs(BNB_RAISE_FRAMES) do
        local fr = _G[name]
        if fr and fr:IsShown() then
            pcall(function() fr:Raise() end)
        end
    end
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

local SK_PROMO_TITLE_H = 28

local function BuildBCBPromo()
    local PROMO_W  = 360
    local PROMO_H  = 550
    local PAD_P    = 16
    local ASSETS   = "Interface\\AddOns\\BigNoteBox\\Assets\\"
    local skinMode = BigNoteBoxDB and BigNoteBoxDB.skinMode
    local titleH   = skinMode and SK_PROMO_TITLE_H or 36

    local f
    if skinMode then
        f = BNB.CreateSkinFrame(UIParent, false, "BigNoteBoxBCBPromoFrame", false)
        _G["BigNoteBoxBCBPromoFrame"] = f
        f:SetSize(PROMO_W, PROMO_H)
        f:SetFrameStrata("DIALOG")
        f:SetToplevel(true); f:SetClampedToScreen(true)
        f:SetMovable(true); f:EnableMouse(true)
        f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", function(self) self:StartMoving() end)
        f:SetScript("OnDragStop",  function(self) self:StopMovingOrSizing() end)

        local titleBar = BNB.CreateSkinStrip(f, true, false)
        titleBar:SetPoint("TOPLEFT",  f, "TOPLEFT",  0, 0)
        titleBar:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
        titleBar:SetHeight(SK_PROMO_TITLE_H)
        titleBar:EnableMouse(true)
        titleBar:RegisterForDrag("LeftButton")
        titleBar:SetScript("OnDragStart", function() f:StartMoving() end)
        titleBar:SetScript("OnDragStop",  function() f:StopMovingOrSizing() end)

        local titleLbl = titleBar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        titleLbl:SetPoint("CENTER", titleBar, "CENTER", -12, 0)
        titleLbl:SetTextColor(1, 0.82, 0)
        titleLbl:SetText(L["MW_BCB_PROMO_TITLE"])

        local closeBtn = BNB.CreateSkinCloseButton(titleBar, function() f:Hide() end)
        closeBtn:SetPoint("RIGHT", titleBar, "RIGHT", -3, 0)

        f:SetScript("OnShow", function()
            if BNB.ApplyMainWindowSkin then BNB.ApplyMainWindowSkin() end
        end)
    else
        f = CreateFrame("Frame", "BigNoteBoxBCBPromoFrame", UIParent, "ButtonFrameTemplate")
        f:SetSize(PROMO_W, PROMO_H)
        f:SetFrameStrata("DIALOG")
        f:SetToplevel(true)
        f:SetClampedToScreen(true)
        f:SetMovable(true)
        f:EnableMouse(true)
        f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", function(self) self:StartMoving() end)
        f:SetScript("OnDragStop",  function(self) self:StopMovingOrSizing() end)
        ButtonFrameTemplate_HidePortrait(f)
        ButtonFrameTemplate_HideButtonBar(f)
        if f.Inset then f.Inset:Hide() end
        BNB.SeatChrome(f)   -- FOR-05: Forever border offset (UI/Chrome.lua)
        f:SetTitle(L["MW_BCB_PROMO_TITLE"])
        if f.CloseButton then
            f.CloseButton:SetScript("OnClick", function() f:Hide() end)
        end
    end
    tinsert(UISpecialFrames, "BigNoteBoxBCBPromoFrame")
    f:SetScript("OnKeyDown", function(self, key)
        if key == "ESCAPE" then f:Hide() end
    end)
    f:EnableKeyboard(true)

    -- Running Y cursor, starts just below the title bar
    local y = -(titleH + PAD_P)

    -- ── BCB logo (256×256 displayed at 128×128, centred) ──────────────────────
    local logo = f:CreateTexture(nil, "ARTWORK")
    logo:SetSize(128, 128)
    logo:SetPoint("TOP", f, "TOP", 0, y)
    y = y - 128 - 14

    -- ── "By Dukul" — large, same blue as URL ──────────────────────────────────
    local byLbl = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    byLbl:SetPoint("TOP", f, "TOP", 0, y)
    byLbl:SetWidth(PROMO_W - PAD_P * 2)
    byLbl:SetJustifyH("CENTER")
    byLbl:SetTextColor(0.31, 0.76, 1.0, 1)   -- same blue as URL box
    byLbl:SetText(L["MW_BCB_PROMO_BY"])
    y = y - 26 - 10

    -- ── Description ───────────────────────────────────────────────────────────
    local desc = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    desc:SetPoint("TOP", f, "TOP", 0, y)
    desc:SetWidth(PROMO_W - PAD_P * 2)
    desc:SetJustifyH("CENTER")
    desc:SetTextColor(0.80, 0.80, 0.80, 1)
    desc:SetSpacing(3)
    desc:SetText(L["MW_BCB_PROMO_DESC"])
    y = y - 52 - 12

    -- ── URL label ─────────────────────────────────────────────────────────────
    local urlLbl = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    urlLbl:SetPoint("TOP", f, "TOP", 0, y)
    urlLbl:SetWidth(PROMO_W - PAD_P * 2)
    urlLbl:SetJustifyH("CENTER")
    urlLbl:SetTextColor(0.55, 0.55, 0.55, 1)
    urlLbl:SetText(L["MW_BCB_PROMO_URL_LBL"])
    y = y - 18 - 6

    -- ── Copyable URL editbox ───────────────────────────────────────────────────
    local urlBox = CreateFrame("EditBox", nil, f)
    urlBox:SetPoint("TOP", f, "TOP", 0, y)
    urlBox:SetSize(PROMO_W - PAD_P * 2, 22)
    urlBox:SetAutoFocus(false)
    urlBox:SetMultiLine(false)
    urlBox:SetMaxLetters(200)
    urlBox:SetFontObject("GameFontNormalSmall")
    urlBox:SetTextColor(0.31, 0.76, 1.0, 1)
    urlBox:SetJustifyH("CENTER")
    urlBox:SetText("https://www.curseforge.com/wow/addons/bigchatbox")
    urlBox:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
    urlBox:SetScript("OnEscapePressed",   function(self) self:ClearFocus() end)
    y = y - 22

    -- Underline for URL box
    local urlUnder = f:CreateTexture(nil, "ARTWORK")
    urlUnder:SetHeight(1)
    urlUnder:SetPoint("TOPLEFT",  urlBox, "BOTTOMLEFT",  0, -2)
    urlUnder:SetPoint("TOPRIGHT", urlBox, "BOTTOMRIGHT", 0, -2)
    urlUnder:SetColorTexture(0.25, 0.55, 0.85, 0.7)
    y = y - 6 - 20   -- gap after underline before screenshots

    -- ── Screenshots: bcb-left + bcb-right side by side, 80% of dialog width ──
    -- Each image is 128×128 TGA. Displayed together they fill 80% of PROMO_W.
    -- screenshotW = PROMO_W * 0.8 = 288. Each half = 144×144 (scaled up slightly).
    local ssW   = math.floor(PROMO_W * 0.80)   -- 288
    local halfW = math.floor(ssW / 2)          -- 144
    local ssH   = 144
    local ssX   = -math.floor((PROMO_W - ssW) / 2)   -- offset from centre to left edge = -36

    local ssLeft = f:CreateTexture(nil, "ARTWORK")
    ssLeft:SetSize(halfW, ssH)
    -- TOP anchor is at frame's top-centre. Offset by -halfW/2 so the pair is centred.
    ssLeft:SetPoint("TOP", f, "TOP", -math.floor(halfW / 2), y)
    ssLeft:SetTexture(ASSETS .. "BCB\\bcb-left")

    local ssRight = f:CreateTexture(nil, "ARTWORK")
    ssRight:SetSize(halfW, ssH)
    ssRight:SetPoint("LEFT", ssLeft, "RIGHT", 0, 0)
    ssRight:SetTexture(ASSETS .. "BCB\\bcb-right")

    -- ── Close button, well below the screenshots ───────────────────────────────
    local closeBtn = BNB.CreateButton(nil, f, L["CLOSE"], 80, 24)
    closeBtn:SetPoint("BOTTOM", f, "BOTTOM", 0, PAD_P + 4)
    closeBtn:SetScript("OnClick", function() f:Hide() end)

    -- Deferred texture set (needs PLAYER_LOGIN for safe GPU load in some cases)
    logo:SetTexture(ASSETS .. "BCB\\bcb-logo")

    f:Hide()
    return f
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

    if BNB.RefreshNoteList then BNB.RefreshNoteList() end
    if BNB.SelectNote      then BNB.SelectNote(id)   end

    C_Timer.After(0.05, function()
        if BNB._editorTitle then BNB._editorTitle:SetFocus() end
        if BNB.OpenNoteConfig then BNB.OpenNoteConfig(id) end
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
    local header = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    header:SetPoint("TOP", icon, "BOTTOM", 0, -16)
    header:SetTextColor(1, 0.25, 0.25)
    header:SetText(L["MW_DB_UNAVAILABLE_HEADER"])

    -- Body explanation
    local body = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
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

-- BigNoteBox UI/MainWindow.lua
-- ButtonFrameTemplate window (matches BCB).
-- Two-pane layout with draggable splitter between list and editor panes.

local BNB = BigNoteBox
local L   = BNB.L

-- ── Layout constants ────────────────────────────────────────────────────────
-- TITLE_H: height of the ButtonFrameTemplate title area (includes the reserved
-- icon toolbar strip beneath the "BigNoteBox" heading).
local TITLE_H    = 60
local TOOLBAR_H  = 32   -- editor bottom toolbar
local MIN_W      = 500
local MIN_H      = 400
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

-- Expose for child modules
BNB.MAIN_TITLE_H   = TITLE_H
BNB.MAIN_TOOLBAR_H = TOOLBAR_H

-- Runtime split position (set from DB on first window open)
BNB._listPaneW = DEFAULT_LIST_W

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

-- Apply the current split position to listPane / editorPane / divider.
-- Called after drag and on window show.
local function ApplySplit(f, listPane, editorPane, _divider, splitter)
    local lw = BNB._listPaneW
    listPane:SetWidth(lw)
    if _divider then
        _divider:SetPoint("TOPLEFT",    f, "TOPLEFT",   lw, -TITLE_H)
        _divider:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", lw, 0)
    end
    splitter:SetPoint("TOPLEFT",    f, "TOPLEFT",   lw - 3, -TITLE_H)
    splitter:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", lw - 3, 0)
    editorPane:SetPoint("TOPLEFT",     f, "TOPLEFT",    lw + 1, -TITLE_H)
    editorPane:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
end

--------------------------------------------------------------------------------
-- CREATE MAIN WINDOW
--------------------------------------------------------------------------------
function BNB.CreateMainWindow()
    if BNB.mainFrame then return end

    -- Restore saved split width
    BNB._listPaneW = math.max(MIN_LIST_W,
        math.min(MAX_LIST_W, BigNoteBoxDB.splitX or DEFAULT_LIST_W))

    local f = CreateFrame("Frame", "BigNoteBoxFrame", UIParent, "ButtonFrameTemplate")
    f:SetSize(DEFAULT_W, DEFAULT_H)
    f:SetPoint("CENTER")
    f:SetToplevel(true)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:SetResizable(true)   -- REQUIRED — ButtonFrameTemplate does not set this
    f:SetClampedToScreen(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) self:StartMoving() end)
    f:SetScript("OnDragStop",  function(self)
        self:StopMovingOrSizing()
        SaveWindowPos(self)
    end)
    -- When the main window is clicked/raised, bring all visible BNB windows
    -- to the front together so none get left behind other frames.
    f:SetScript("OnMouseDown", function()
        if BNB.RaiseBNBWindows then BNB.RaiseBNBWindows() end
    end)

    ButtonFrameTemplate_HidePortrait(f)
    ButtonFrameTemplate_HideButtonBar(f)
    if f.Inset then f.Inset:Hide() end
    f:SetAlpha(0.95)
    f:SetTitle(L["WINDOW_TITLE"])

    if f.CloseButton then
        f.CloseButton:SetScript("OnClick", function()
            BNB.RequestCloseMainWindow()
        end)
    end

    -- ── Focus mode button ────────────────────────────────────────────────────
    -- Parented to f.CloseButton so it inherits the correct frame level and
    -- stacking context — guaranteed above ButtonFrameTemplate chrome.
    -- Uses focus-normal.tga at rest, focus-hover.tga on mouse-over.
    if f.CloseButton then
        local ASSETS = "Interface\\AddOns\\BigNoteBox\\Assets\\Buttons\\"
        local focusBtn = CreateFrame("Button", nil, f.CloseButton)
        focusBtn:SetSize(20, 20)
        focusBtn:SetPoint("RIGHT", f.CloseButton, "LEFT", -2, 0)

        -- Suppress WoW's default button flash so our press texture shows cleanly
        focusBtn:SetHighlightTexture("")
        focusBtn:SetPushedTexture("")

        local focusNormal = focusBtn:CreateTexture(nil, "ARTWORK")
        focusNormal:SetAllPoints()
        focusNormal:SetTexture(ASSETS .. "bt-focus-normal")

        local focusHover = focusBtn:CreateTexture(nil, "ARTWORK")
        focusHover:SetAllPoints()
        focusHover:SetTexture(ASSETS .. "bt-focus-hover")
        focusHover:Hide()

        local focusPress = focusBtn:CreateTexture(nil, "ARTWORK")
        focusPress:SetAllPoints()
        focusPress:SetTexture(ASSETS .. "bt-focus-press")
        focusPress:Hide()

        focusBtn:SetScript("OnClick", function()
            if BNB.OpenFocusMode then BNB.OpenFocusMode() end
        end)
        focusBtn:SetScript("OnMouseDown", function()
            focusPress:Show(); focusNormal:Hide(); focusHover:Hide()
        end)
        focusBtn:SetScript("OnMouseUp", function()
            focusPress:Hide(); focusHover:Show()
        end)
        focusBtn:SetScript("OnEnter", function()
            focusNormal:Hide()
            focusHover:Show()
            GameTooltip:SetOwner(focusBtn, "ANCHOR_BOTTOM")
            GameTooltip:AddLine(L["FOCUS_MODE_TIP"], 1, 1, 1)
            GameTooltip:AddLine(L["FOCUS_MODE_TIP_SUB"], 0.78, 0.78, 0.78)
            GameTooltip:Show()
        end)
        focusBtn:SetScript("OnLeave", function()
            focusPress:Hide(); focusHover:Hide()
            focusNormal:Show()
            GameTooltip:Hide()
        end)
        BNB._focusModeBtn = focusBtn
        -- Start disabled — no note selected yet; UpdateSaveButtonState re-enables on note load
        focusBtn:SetEnabled(false)
        focusBtn:SetAlpha(0.35)
        pcall(function() focusBtn._tx:SetDesaturated(true) end)
    end

    -- ── Scale-lock button ─────────────────────────────────────────────────────
    -- Sits between the focus button and the X (CloseButton).
    -- Locked   → button-lock.tga    / button-lock-hover.tga
    -- Unlocked → button-unlock.tga  / button-unlock-hover.tga
    -- State persists via BigNoteBoxDB.scaleLocked.
    if f.CloseButton then
        local LOCK_ASSETS = "Interface\\AddOns\\BigNoteBox\\Assets\\Buttons\\"
        local lockBtn = CreateFrame("Button", nil, f.CloseButton)
        lockBtn:SetSize(20, 20)
        -- Focus button is RIGHT of CloseButton at -2; lock sits left of focus button
        lockBtn:SetPoint("RIGHT", BNB._focusModeBtn or f.CloseButton, "LEFT", -2, 0)

        local function IsLocked() return BigNoteBoxDB and BigNoteBoxDB.scaleLocked end

        -- Suppress WoW's default button flash so our press texture shows cleanly
        lockBtn:SetHighlightTexture("")
        lockBtn:SetPushedTexture("")

        local lockTex   = lockBtn:CreateTexture(nil, "ARTWORK")
        lockTex:SetAllPoints()
        local unlockTex = lockBtn:CreateTexture(nil, "ARTWORK")
        unlockTex:SetAllPoints()
        local lockHov   = lockBtn:CreateTexture(nil, "ARTWORK")
        lockHov:SetAllPoints(); lockHov:Hide()
        local unlockHov = lockBtn:CreateTexture(nil, "ARTWORK")
        unlockHov:SetAllPoints(); unlockHov:Hide()
        local lockPress   = lockBtn:CreateTexture(nil, "ARTWORK")
        lockPress:SetAllPoints(); lockPress:Hide()
        local unlockPress = lockBtn:CreateTexture(nil, "ARTWORK")
        unlockPress:SetAllPoints(); unlockPress:Hide()

        lockTex:SetTexture(LOCK_ASSETS .. "bt-lock-normal")
        unlockTex:SetTexture(LOCK_ASSETS .. "bt-unlock-normal")
        lockHov:SetTexture(LOCK_ASSETS .. "bt-lock-hover")
        unlockHov:SetTexture(LOCK_ASSETS .. "bt-unlock-hover")
        lockPress:SetTexture(LOCK_ASSETS .. "bt-lock-press")
        unlockPress:SetTexture(LOCK_ASSETS .. "bt-unlock-press")

        local function RefreshLockBtn()
            local locked = IsLocked()
            lockTex:SetShown(locked)
            unlockTex:SetShown(not locked)
            lockHov:Hide(); unlockHov:Hide()
            lockPress:Hide(); unlockPress:Hide()
        end
        RefreshLockBtn()

        lockBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        lockBtn:SetScript("OnClick", function(_, btn)
            if btn == "RightButton" then
                f:SetSize(DEFAULT_W, DEFAULT_H)
                f:ClearAllPoints()
                f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
                SaveWindowPos(f)
                return
            end
            local db = BigNoteBoxDB
            if not db then return end
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
            local locked = IsLocked()
            if locked then lockHov:Show() else unlockHov:Show() end
        end)
        lockBtn:SetScript("OnEnter", function()
            local locked = IsLocked()
            if locked then lockTex:Hide();   lockHov:Show()
            else           unlockTex:Hide(); unlockHov:Show() end
            GameTooltip:SetOwner(lockBtn, "ANCHOR_BOTTOM")
            if locked then
                GameTooltip:AddLine("Window scale is locked", 1, 1, 1)
                GameTooltip:AddLine("Click to allow resizing", 0.78, 0.78, 0.78)
            else
                GameTooltip:AddLine("Window scale is unlocked", 1, 1, 1)
                GameTooltip:AddLine("Click to lock and hide the resize handle", 0.78, 0.78, 0.78)
            end
            GameTooltip:AddLine("Right-click to reset window size and position", 0.55, 0.55, 0.55)
            GameTooltip:Show()
        end)
        lockBtn:SetScript("OnLeave", function()
            RefreshLockBtn()
            GameTooltip:Hide()
        end)
        BNB._lockScaleBtn     = lockBtn
        BNB._refreshLockBtn   = RefreshLockBtn
    end

    -- Apply scale lock state from DB (called here and after DB loads)
    function BNB._applyScaleLock()
        local locked = BigNoteBoxDB and BigNoteBoxDB.scaleLocked
        local rh = BNB.mainFrame and BNB.mainFrame._resizeHandle
        if rh then rh:SetShown(not locked) end
        if BNB.mainFrame then
            if BNB.mainFrame.SetResizable then
                BNB.mainFrame:SetResizable(not locked)
            end
        end
        if BNB._refreshLockBtn then BNB._refreshLockBtn() end
    end

    -- ── Icon toolbar strip ───────────────────────────────────────────────────
    -- The ButtonFrameTemplate title area is TITLE_H (60px) tall.
    -- The "BigNoteBox" title text sits ~8px from the top, leaving ~28px below
    -- it before the pane content starts.  We place small icon-texture buttons
    -- there: Config (cog), Export, Import.
    --
    -- All three are plain CreateFrame("Button") — no template — so they work
    -- identically across templates with no SetWidth/GetFontString issues.
    -- Icons are 20×20, sitting 4px above the pane edge (y = -(TITLE_H - 22)).

    local ICON_BTN_SIZE = 20
    local ICON_BTN_Y    = -(TITLE_H - 22)   -- 4px above the pane top edge

    local function MakeIconToolbarBtn(iconTex, tooltipText, xOffset, onClick)
        local btn = CreateFrame("Button", nil, f)
        btn:SetSize(ICON_BTN_SIZE, ICON_BTN_SIZE)
        btn:SetPoint("TOPRIGHT", f, "TOPRIGHT", xOffset, ICON_BTN_Y)

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
        btn:SetScript("OnLeave", function(self)
            iconTx:SetPoint("TOPLEFT",     btn, "TOPLEFT",      REST, -REST)
            iconTx:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -REST,  REST)
            GameTooltip:Hide()
        end)
        btn:SetScript("OnClick", onClick)
        return btn
    end

    -- Config button (cog icon) — right-most (slot 0)
    local configBtn = MakeIconToolbarBtn(
        "Interface\\AddOns\\BigNoteBox\\Assets\\Topbar\\tp-cog",
        "Settings (/bnb config)",
        -(30),
        function()
            if BNB.OpenConfig then BNB.OpenConfig() end
        end)
    BNB._toolbarConfigBtn = configBtn

    -- Sidebar toggle button — right of cog
    local TOPBAR_PATH = "Interface\\AddOns\\BigNoteBox\\Assets\\Topbar\\"
    local sidebarToggleBtn = MakeIconToolbarBtn(
        TOPBAR_PATH .. "tp-sidebar-open",
        "Toggle sidebar",
        -(30 - (ICON_BTN_SIZE + 4)),
        function()
            if BNB.Sidebar and BNB.Sidebar.ToggleCollapsed then
                BNB.Sidebar.ToggleCollapsed()
            end
        end)
    BNB._toolbarSidebarBtn = sidebarToggleBtn

    -- Refreshes sidebar toggle icon to match current state
    function BNB.RefreshSidebarToggleBtn()
        local collapsed = BigNoteBoxDB and BigNoteBoxDB.sidebarCollapsed
        local tex = "Interface\\AddOns\\BigNoteBox\\Assets\\Topbar\\"
            .. (collapsed and "tp-sidebar-closed" or "tp-sidebar-open")
        pcall(function() BNB._toolbarSidebarBtn._tx:SetTexture(tex) end)
    end
    BNB.RefreshSidebarToggleBtn()

    -- Trash button — left of cog
    local trashBtn = MakeIconToolbarBtn(
        "Interface\\AddOns\\BigNoteBox\\Assets\\Topbar\\tp-trash",
        "Trash  (deleted notes)",
        -(30 + ICON_BTN_SIZE + 4),
        function()
            if BNB.ToggleTrashWindow then BNB.ToggleTrashWindow() end
        end)
    BNB._toolbarTrashBtn = trashBtn

    -- History button — left of trash (desaturated until history exists)
    local histBtn = MakeIconToolbarBtn(
        "Interface\\AddOns\\BigNoteBox\\Assets\\Topbar\\tp-history",
        L["HISTORY_TOOLBAR_TIP"],
        -(30 + (ICON_BTN_SIZE + 4) * 2),
        function()
            if BNB.ToggleHistoryWindow then BNB.ToggleHistoryWindow() end
        end)
    histBtn:SetEnabled(false)
    histBtn:SetAlpha(0.4)
    pcall(function() histBtn._tx:SetDesaturated(true) end)
    BNB._toolbarHistoryBtn = histBtn

    -- Tags button — left of history (slot 3)
    local tagsBtn = MakeIconToolbarBtn(
        "Interface\\AddOns\\BigNoteBox\\Assets\\Topbar\\tp-tags",
        L["TAG_MGR_TOOLTIP"],
        -(30 + (ICON_BTN_SIZE + 4) * 3),
        function()
            if BNB.ToggleTagManager then BNB.ToggleTagManager() end
        end)
    BNB._toolbarTagsBtn = tagsBtn

    -- Alarm overview button (slot 5, left of share)
    local alarmOvBtn = MakeIconToolbarBtn(
        "Interface\\AddOns\\BigNoteBox\\Assets\\Topbar\\tp-alarm",
        "Alarms",
        -(30 + (ICON_BTN_SIZE + 4) * 5),
        function()
            if BNB.AlarmOverview and BNB.AlarmOverview.Toggle then
                BNB.AlarmOverview.Toggle()
            end
        end)
    BNB._toolbarAlarmOvBtn = alarmOvBtn

    -- Share/import button (slot 4, left of tags) — opens import-only window
    local shareTopBtn = MakeIconToolbarBtn(
        "Interface\\AddOns\\BigNoteBox\\Assets\\Topbar\\tp-share",
        "Import a shared note",
        -(30 + (ICON_BTN_SIZE + 4) * 4),
        function()
            local iw = _G["BNBImportFrame"]
            if iw and iw:IsShown() then
                if BNB.CloseImportWindow then BNB.CloseImportWindow() end
            else
                if BNB.OpenImportWindow then BNB.OpenImportWindow() end
            end
        end)
    BNB._toolbarShareTopBtn = shareTopBtn

    -- Import button (slot 6, wired to BCB chat capture by Features/ChatCapture.lua)
    -- Icon: tp-bcb when BCB is installed, bcb-icon when absent. Always full colour.
    local importBtn = MakeIconToolbarBtn(
        (BigChatBox and BigChatBox.SendDirect)
            and "Interface\\AddOns\\BigNoteBox\\Assets\\Topbar\\tp-bcb"
            or  "Interface\\AddOns\\BigNoteBox\\Assets\\BCB\\bcb-icon",
        "Send note to BigChatBox multiline input",
        -(30 + (ICON_BTN_SIZE + 4) * 6),
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
                BNB:Print("|cffff6666This note is empty.|r")
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
        local tex = hasBCB
            and "Interface\\AddOns\\BigNoteBox\\Assets\\Topbar\\tp-bcb"
            or  "Interface\\AddOns\\BigNoteBox\\Assets\\BCB\\bcb-icon"
        pcall(function()
            importBtn._tx:SetTexture(tex)
            importBtn._tx:SetDesaturated(false)
            importBtn:SetAlpha(1.0)
        end)
    end
    RefreshImportBtn()
    BNB._toolbarImportBtn  = importBtn
    BNB._refreshImportBtn  = RefreshImportBtn

    -- ── Sort dropdown — top-LEFT of title strip ──────────────────────────────
    local SORT_STRIP_MID_Y = -(TITLE_H - 14)
    local SORT_BTN_H = 22   -- height to match WowStyle1 button

    local SORT_MODES = {
        { key="custom",   label="Custom"   },
        { key="creation", label="Creation" },
        { key="edited",   label="Edited"   },
        { key="alpha",    label="A-Z"      },
        { key="location", label="Location" },
    }
    local function CurrentSortLabel()
        local db = BigNoteBoxDB
        for _, m in ipairs(SORT_MODES) do
            if m.key == (db.sortBy or "creation") then return m.label end
        end
        return "Creation"
    end

    local useNativeSort = C_XMLUtil and C_XMLUtil.GetTemplateInfo
        and C_XMLUtil.GetTemplateInfo("WowStyle1DropdownTemplate")

    local sortDD       -- WowStyle1 DropdownButton (retail)
    local sortCycleBtn -- fallback cycling button
    local sortDDWidth  = 120

    local function ApplySort()
        if BNB.RefreshNoteList then BNB.RefreshNoteList() end
    end

    if useNativeSort then
        sortDD = CreateFrame("DropdownButton", "BNBMainSortDD", f, "WowStyle1DropdownTemplate")
        sortDD:SetSize(sortDDWidth, SORT_BTN_H)
        sortDD:SetPoint("TOPLEFT", f, "TOPLEFT", 12, SORT_STRIP_MID_Y + SORT_BTN_H / 2)
        local function RebuildSortMenu()
            sortDD:SetupMenu(function(_, root)
                for _, m in ipairs(SORT_MODES) do
                    local key = m.key
                    root:CreateRadio(m.label,
                        function() return (BigNoteBoxDB.sortBy or "creation") == key end,
                        function()
                            BigNoteBoxDB.sortBy = key
                            sortDD:GenerateMenu()
                            ApplySort()
                        end)
                end
            end)
        end
        RebuildSortMenu()
        BNB._rebuildSortMenu = RebuildSortMenu
        BNB._sortDD = sortDD
    else
        -- Fallback: cycling button
        sortCycleBtn = BNB.CreateButton(nil, f, CurrentSortLabel(), sortDDWidth, SORT_BTN_H)
        sortCycleBtn:SetPoint("TOPLEFT", f, "TOPLEFT", 12, SORT_STRIP_MID_Y + SORT_BTN_H / 2)
        sortCycleBtn:SetScript("OnClick", function(self)
            local cur = BigNoteBoxDB.sortBy or "creation"
            local idx = 1
            for i, m in ipairs(SORT_MODES) do if m.key == cur then idx = i; break end end
            idx = (idx % #SORT_MODES) + 1
            BigNoteBoxDB.sortBy = SORT_MODES[idx].key
            self:SetText(CurrentSortLabel())
            ApplySort()
        end)
        BNB._sortCycleBtn = sortCycleBtn
    end

    -- Exposed so TagTree can disable sorting while tree view is active.
    function BNB.SetSortEnabled(enabled)
        if sortDD then
            sortDD:SetEnabled(enabled)
            sortDD:SetAlpha(enabled and 1.0 or 0.4)
        end
        if sortCycleBtn then
            sortCycleBtn:SetEnabled(enabled)
            sortCycleBtn:SetAlpha(enabled and 1.0 or 0.4)
        end
    end

    -- ── Order dropdown (Asc/Desc) — WowStyle1 or cycling button ─────────────
    -- Disabled (greyed out) when sort is "custom" since order has no meaning there.
    local DIR_MODES = {
        { key="desc", label="Descending" },
        { key="asc",  label="Ascending"  },
    }
    local function IsCustomSort() return BigNoteBoxDB.sortBy == "custom" end
    local function CurrentDirKey() return BigNoteBoxDB.sortAsc and "asc" or "desc" end
    local function CurrentDirLabel()
        return BigNoteBoxDB.sortAsc and "Ascending" or "Descending"
    end

    local dirDD       -- WowStyle1 DropdownButton
    local dirCycleBtn -- fallback cycling button
    local dirDDWidth  = 120

    -- Shared: update enabled/disabled state based on sort mode
    local function UpdateDirEnabled()
        local custom = IsCustomSort()
        if dirDD then
            dirDD:SetEnabled(not custom)
            dirDD:SetAlpha(custom and 0.4 or 1.0)
        end
        if dirCycleBtn then
            dirCycleBtn:SetEnabled(not custom)
            dirCycleBtn:SetAlpha(custom and 0.4 or 1.0)
        end
    end

    if useNativeSort then
        dirDD = CreateFrame("DropdownButton", "BNBMainDirDD", f, "WowStyle1DropdownTemplate")
        dirDD:SetSize(dirDDWidth, SORT_BTN_H)
        dirDD:SetPoint("LEFT", sortDD, "RIGHT", 4, 0)
        local function RebuildDirMenu()
            dirDD:SetupMenu(function(_, root)
                for _, m in ipairs(DIR_MODES) do
                    local key = m.key
                    root:CreateRadio(m.label,
                        function() return CurrentDirKey() == key end,
                        function()
                            BigNoteBoxDB.sortAsc = (key == "asc")
                            dirDD:GenerateMenu()
                            ApplySort()
                        end)
                end
            end)
        end
        RebuildDirMenu()
        BNB._rebuildDirMenu = RebuildDirMenu
    else
        dirCycleBtn = BNB.CreateButton(nil, f, CurrentDirLabel(), dirDDWidth, SORT_BTN_H)
        dirCycleBtn:SetPoint("LEFT", sortCycleBtn, "RIGHT", 4, 0)
        dirCycleBtn:SetScript("OnClick", function(self)
            BigNoteBoxDB.sortAsc = not BigNoteBoxDB.sortAsc
            self:SetText(CurrentDirLabel())
            UpdateDirEnabled()
            ApplySort()
        end)
    end

    -- Hook ApplySort to also refresh dir dropdown state after sort key changes
    local _origApplySort = ApplySort
    ApplySort = function()
        _origApplySort()
        UpdateDirEnabled()
        if dirDD and dirDD.GenerateMenu then dirDD:GenerateMenu() end
        if dirCycleBtn then dirCycleBtn:SetText(CurrentDirLabel()) end
    end

    -- ── Select-mode toggle button ─────────────────────────────────────────────
    local selBtn = BNB.CreateButton(nil, f, "Select", 52, 22)
    if useNativeSort then
        selBtn:SetPoint("LEFT", dirDD, "RIGHT", 6, 0)
    else
        selBtn:SetPoint("LEFT", dirCycleBtn, "RIGHT", 6, 0)
    end
    selBtn:SetPoint("TOP", f, "TOP", 0, SORT_STRIP_MID_Y + SORT_BTN_H / 2 + 1)
    BNB._multiSelBtn = selBtn
    selBtn:SetScript("OnClick", function()
        local entering = not BNB._multiMode
        BNB._multiMode = entering
        if BNB.SetMultiMode then BNB.SetMultiMode(entering) end
        selBtn:SetText(entering and "Cancel" or "Select")
        if BNB._setToolbarMultiMode then BNB._setToolbarMultiMode(entering) end
    end)
    selBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:AddLine("Toggle multi-select mode", 1,1,1)
        GameTooltip:AddLine("Select notes to bulk-delete them", 0.78,0.78,0.78)
        GameTooltip:Show()
    end)
    selBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    BNB._multiMode = false

    -- Select All button (hidden until multi-select mode is on)
    local selectAllBtn = BNB.CreateButton(nil, f, "Select All", 76, 22)
    selectAllBtn:SetPoint("LEFT", selBtn, "RIGHT", 4, 0)
    selectAllBtn:SetPoint("TOP",  selBtn, "TOP",   0, 0)
    selectAllBtn:Hide()
    selectAllBtn:SetScript("OnClick", function()
        if BNB.SelectAll then BNB.SelectAll() end
    end)
    selectAllBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:AddLine("Select all notes", 1,1,1)
        GameTooltip:Show()
    end)
    selectAllBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    BNB._multiSelectAllBtn = selectAllBtn

    -- Bulk-delete button (hidden until multi-select mode is on)
    local multiDelBtn = BNB.CreateButton(nil, f, "Delete (0)", 90, 22)
    multiDelBtn:SetPoint("LEFT", selectAllBtn, "RIGHT", 4, 0)
    multiDelBtn:SetPoint("TOP",  selBtn, "TOP", 0, 0)
    multiDelBtn:SetEnabled(false)
    multiDelBtn:Hide()
    multiDelBtn:SetScript("OnClick", function()
        if BNB.DeleteMultiSelected then BNB.DeleteMultiSelected() end
    end)
    multiDelBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:AddLine("Delete selected notes", 1,1,1)
        GameTooltip:Show()
    end)
    multiDelBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    BNB._multiDeleteBtn = multiDelBtn

    -- Bulk copy/move button
    local multiCopyMoveBtn = BNB.CreateButton(nil, f, "Copy / Move (0)", 120, 22)
    multiCopyMoveBtn:SetPoint("LEFT", multiDelBtn, "RIGHT", 4, 0)
    multiCopyMoveBtn:SetPoint("TOP",  selBtn, "TOP", 0, 0)
    multiCopyMoveBtn:SetEnabled(false)
    multiCopyMoveBtn:Hide()
    multiCopyMoveBtn:SetScript("OnClick", function()
        if BNB.CopyMoveMultiSelected then BNB.CopyMoveMultiSelected() end
    end)
    multiCopyMoveBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:AddLine("Copy or move selected notes to another character or scope", 1,1,1)
        GameTooltip:Show()
    end)
    multiCopyMoveBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    BNB._multiCopyMoveBtn = multiCopyMoveBtn

    -- Bulk export button (JSON, re-importable)
    local multiExportBtn = BNB.CreateButton(nil, f, "Export (0)", 90, 22)
    multiExportBtn:SetPoint("LEFT", multiCopyMoveBtn, "RIGHT", 4, 0)
    multiExportBtn:SetPoint("TOP",  selBtn, "TOP", 0, 0)
    multiExportBtn:SetEnabled(false)
    multiExportBtn:Hide()
    multiExportBtn:SetScript("OnClick", function()
        if BNB.ExportMultiJSON and BNB._multiGetSelected then
            BNB.ExportMultiJSON(BNB._multiGetSelected())
        end
        if BNB.SetMultiMode then BNB.SetMultiMode(false) end
    end)
    multiExportBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:AddLine("Export selected notes as JSON", 1,1,1)
        GameTooltip:AddLine("Output can be re-imported via the Backup tab", 0.78,0.78,0.78)
        GameTooltip:Show()
    end)
    multiExportBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    BNB._multiExportBtn = multiExportBtn

    -- Hides/shows the right-side toolbar icons while multi-select mode is active,
    -- so the action buttons don't overlap them.
    function BNB._setToolbarMultiMode(on)
        -- Only hide the top-right toolbar buttons. Title bar buttons (focus,
        -- lock, close) are never hidden by multiselect.
        local btns = {
            BNB._toolbarConfigBtn,  BNB._toolbarTrashBtn,   BNB._toolbarHistoryBtn,
            BNB._toolbarTagsBtn,    BNB._toolbarAlarmOvBtn, BNB._toolbarImportBtn,
            BNB._toolbarShareTopBtn,
        }
        for _, btn in ipairs(btns) do
            if btn then btn:SetShown(not on) end
        end
    end

    C_Timer.After(0, function() UpdateDirEnabled(); ApplySort() end)

    -- Handle ESC manually so we control the close order and can intercept
    -- confirmClose. We do NOT add BigNoteBoxFrame to UISpecialFrames —
    -- that would make it compete with ConfigFrame and NoteConfigFrame for
    -- the same ESC press. Instead we catch ESC via OnKeyDown.
    -- Order: NoteConfig (right) → Config (left) → Main window
    f:SetPropagateKeyboardInput(false)
    f:EnableKeyboard(true)
    f:SetScript("OnKeyDown", function(self, key)
        if key ~= "ESCAPE" then self:SetPropagateKeyboardInput(true); return end
        self:SetPropagateKeyboardInput(false)
        -- ESC close order:
        -- 0. Clipboard hint (DIALOG strata — always first)
        -- 1. Export window (DIALOG strata)
        -- 2. Any open sticky note settings window
        -- 3. NoteConfig (per-note settings, left of main)
        -- 4. Config (addon settings, right of main)
        -- 5. Main window itself
        -- New Note dialog (DIALOG strata — always first)
        local nnd = _G["BNBNewNoteDialogFrame"]
        if nnd and nnd:IsShown() then
            if BNB.NewNoteDialog and BNB.NewNoteDialog.Close then
                BNB.NewNoteDialog.Close()
            else
                nnd:Hide()
            end
            return
        end
        local ch = _G["BNBClipboardHintFrame"]
        if ch and ch:IsShown() then
            if BNB._clipboardHint and BNB._clipboardHint._dismiss then
                BNB._clipboardHint._dismiss()
            else
                ch:Hide()
            end
            return
        end
        -- Icon picker (sidebar right-click → Change icon)
        local ip = _G["BNBSidebarIconPickerFrame"]
        if ip and ip:IsShown() then ip:Hide(); return end
        -- Insert Info menu (closes before all BNB windows)
        if BNB.CloseInsertInfoMenu and BNB.CloseInsertInfoMenu() then return end
        local ew = _G["BigNoteBoxExportFrame"]
        if ew and ew:IsShown() then ew:Hide(); return end
        -- Copy/Move popup
        local cm = _G["BigNoteBoxCopyMoveFrame"]
        if cm and cm:IsShown() then cm:Hide(); return end
        -- History compare window (closes before everything else)
        local hcw = _G["BigNoteBoxHistoryCompareFrame"]
        if hcw and hcw:IsShown() then BNB.CloseHistoryCompare(); return end
        -- Alarm setter window closes before sticky settings
        local aw = _G["BNBAlarmWindow"]
        if aw and aw:IsShown() then
            if BNB.AlarmWindow and BNB.AlarmWindow.Close then
                BNB.AlarmWindow.Close()
            else
                aw:Hide()
            end
            return
        end
        -- Alarm overview window (all alarms list)
        local ao = _G["BNBAlarmOverviewFrame"]
        if ao and ao:IsShown() then ao:Hide(); return end
        local ss = _G["BigNoteBoxStickySettingsFrame"]
        if ss and ss:IsShown() then
            if BNB.Sticky and BNB.Sticky.CloseSettings then
                BNB.Sticky.CloseSettings()
            else
                ss:Hide()
            end
            return
        end
        -- If tag manager is open, close it next
        local tm = _G["BigNoteBoxTagManagerFrame"]
        if tm and tm:IsShown() then tm:Hide(); return end
        -- If per-note history panel is open, close it next
        local nhp = _G["BigNoteBoxNoteHistoryFrame"]
        if nhp and nhp:IsShown() then BNB.CloseNoteHistoryPanel(); return end
        -- If main history window is open, close it next (also closes panel)
        local hw = _G["BigNoteBoxHistoryFrame"]
        if hw and hw:IsShown() then BNB.CloseHistoryWindow(); return end
        -- If trash view popup is open, close it before the trash window itself
        local tvp = _G["BNBTrashViewPopup"]
        if tvp and tvp:IsShown() then tvp:Hide(); return end
        -- If trash window is open, close it next
        local tw = _G["BigNoteBoxTrashFrame"]
        if tw and tw:IsShown() then tw:Hide(); return end
        -- If NoteConfig is open, close it next
        local nc = _G["BigNoteBoxNoteConfigFrame"]
        if nc and nc:IsShown() then nc:Hide(); return end
        -- If Task Edit Window is open, close it before RefBox
        local tew = _G["BNBTaskEditWindow"]
        if tew and tew:IsShown() then
            if BNB.TaskEditWindow and BNB.TaskEditWindow.Close then
                BNB.TaskEditWindow.Close()
            else
                tew:Hide()
            end
            return
        end
        -- If Reference Box is open, close it next
        local rb = _G["BigNoteBoxReferenceBoxFrame"]
        if rb and rb:IsShown() then rb:Hide(); return end
        -- Share preview window closes before share/import windows
        local spv = _G["BNBSharePreviewFrame"]
        if spv and spv:IsShown() then BNB.CloseSharePreview(); return end
        -- Share window closes before import window and main window
        local sw = _G["BNBShareFrame"]
        if sw and sw:IsShown() then BNB.CloseShareWindow(); return end
        -- Import window closes before main window
        local iw = _G["BNBImportFrame"]
        if iw and iw:IsShown() then BNB.CloseImportWindow(); return end
        -- If right settings window is open, close it first
        local cfg = _G["BigNoteBoxConfigFrame"]
        if cfg and cfg:IsShown() then cfg:Hide(); return end
        -- Otherwise close main window (with confirm if enabled)
        BNB.RequestCloseMainWindow()
    end)

    -- ── Resize (whole window, bottom-right) ─────────────────────────────────
    f:SetResizeBounds(MIN_W, MIN_H, 1400, 1000)
    local resizeHandle = CreateFrame("Button", nil, f)
    resizeHandle:SetSize(16, 16)
    resizeHandle:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -2, 2)
    resizeHandle:SetFrameLevel(f:GetFrameLevel() + 10)
    local rtex = resizeHandle:CreateTexture(nil, "OVERLAY")
    rtex:SetAllPoints()
    rtex:SetTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    f._resizeHandle = resizeHandle  -- stored for scale-lock toggle
    -- ── Resize size tooltip ──────────────────────────────────────────────────
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

    local _resizing = false
    -- Sidebar width (BTN_SZ in Sidebar.lua = 64) subtracted when sidebar is visible
    -- so the tooltip shows the notepad window size, not including the sidebar strip.
    local function SidebarW()
        return (BNB.Sidebar and BNB.Sidebar.IsEnabled and BNB.Sidebar.IsEnabled()) and 64 or 0
    end

    f:HookScript("OnSizeChanged", function(self)
        if not _resizing then return end
        local w = math.floor(self:GetWidth()  - SidebarW())
        local h = math.floor(self:GetHeight())
        sizeLabelTxt:SetText(w .. " x " .. h)
        -- Position the label 14px to the right and 4px below the cursor
        local cx, cy = GetCursorPosition()
        local uisc   = UIParent:GetEffectiveScale()
        sizeLabel:ClearAllPoints()
        sizeLabel:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT",
            cx / uisc + 14, cy / uisc + 4)
    end)

    resizeHandle:SetScript("OnMouseDown", function(self, btn)
        if btn == "LeftButton" then
            local left = f:GetLeft()
            local top  = f:GetTop()
            -- GetLeft/GetTop return nil if the frame hasn't been laid out yet
            if left and top then
                f:ClearAllPoints()
                f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
            end
            _resizing = true
            -- Seed the label with current size before first OnSizeChanged fires
            sizeLabelTxt:SetText(
                math.floor(f:GetWidth() - SidebarW()) .. " x " .. math.floor(f:GetHeight()))
            local uisc = UIParent:GetEffectiveScale()
            local cx, cy = GetCursorPosition()
            sizeLabel:ClearAllPoints()
            sizeLabel:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT",
                cx / uisc + 14, cy / uisc + 4)
            sizeLabel:Show()
            f:StartSizing("BOTTOMRIGHT")
        end
    end)
    resizeHandle:SetScript("OnMouseUp", function()
        _resizing = false
        sizeLabel:Hide()
        f:StopMovingOrSizing()
        local w = math.max(MIN_W, math.min(1400, f:GetWidth()))
        local h = math.max(MIN_H, math.min(1000, f:GetHeight()))
        f:SetSize(w, h)
        SaveWindowPos(f)
        -- Re-apply split so panes adjust to new width
        ApplySplit(f, BNB.listPane, BNB.editorPane,
            nil, f._splitter)
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

    -- Three grip dots centred vertically on the splitter
    local dotSize = 3
    local dotGap  = 5
    for i = -1, 1 do
        local dot = splitter:CreateTexture(nil, "OVERLAY")
        dot:SetSize(dotSize, dotSize)
        dot:SetPoint("CENTER", splitter, "CENTER", 0, i * dotGap)
        dot:SetColorTexture(0.65, 0.65, 0.65, 0.9)
    end

    -- Highlight dots on hover
    splitter:SetScript("OnEnter", function(self)
        for _, r in ipairs({self:GetRegions()}) do
            if r.SetColorTexture then r:SetColorTexture(1, 0.82, 0, 1) end
        end
    end)
    splitter:SetScript("OnLeave", function(self)
        for _, r in ipairs({self:GetRegions()}) do
            if r.SetColorTexture then r:SetColorTexture(0.65, 0.65, 0.65, 0.9) end
        end
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
                ApplySplit(f, BNB.listPane, BNB.editorPane, nil, splitter)
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
    listPane:SetPoint("TOPLEFT",    f, "TOPLEFT",    0, -TITLE_H)
    listPane:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, 0)
    BNB.listPane = listPane

    -- ── Right pane (editor) ──────────────────────────────────────────────────
    local editorPane = CreateFrame("Frame", nil, f)
    editorPane:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
    BNB.editorPane = editorPane

    -- Apply initial split (sets widths and anchors divider/splitter/editorPane)
    ApplySplit(f, listPane, editorPane, nil, splitter)

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
        ApplySplit(f, listPane, editorPane, nil, splitter)
        -- Skip RestoreWindowPos when returning from focus mode — position was
        -- already set by CopyFramePosition in CloseFocusMode.
        if not self._fromFocusMode then
            RestoreWindowPos(self)
        end
        self._fromFocusMode = false
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
        if BNB._applyScaleLock then BNB._applyScaleLock() end
    end)

    f:SetScript("OnHide", function(self)
        -- Focus mode hides the main window silently — skip confirm/save.
        if self._focusHide then return end
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
        ApplySplit(f, listPane, editorPane, nil, splitter)
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
        titleLbl:SetText("Get BigChatBox")

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
        f:SetTitle("Get BigChatBox")
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
    byLbl:SetText("By Dukul")
    y = y - 26 - 10

    -- ── Description ───────────────────────────────────────────────────────────
    local desc = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    desc:SetPoint("TOP", f, "TOP", 0, y)
    desc:SetWidth(PROMO_W - PAD_P * 2)
    desc:SetJustifyH("CENTER")
    desc:SetTextColor(0.80, 0.80, 0.80, 1)
    desc:SetSpacing(3)
    desc:SetText("Send your notes line-by-line to any channel,\npush them into BCB's multiline editor,\nor share notes with other players\nusing BNB's built-in share system.")
    y = y - 52 - 12

    -- ── URL label ─────────────────────────────────────────────────────────────
    local urlLbl = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    urlLbl:SetPoint("TOP", f, "TOP", 0, y)
    urlLbl:SetWidth(PROMO_W - PAD_P * 2)
    urlLbl:SetJustifyH("CENTER")
    urlLbl:SetTextColor(0.55, 0.55, 0.55, 1)
    urlLbl:SetText("Find it on CurseForge — copy the URL below:")
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
    local closeBtn = BNB.CreateButton(nil, f, "Close", 80, 24)
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
    header:SetText("BigNoteBoxDB is not loaded")

    -- Body explanation
    local body = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    body:SetPoint("TOP", header, "BOTTOM", 0, -16)
    body:SetWidth(480)
    body:SetJustifyH("CENTER")
    body:SetSpacing(3)
    body:SetTextColor(0.85, 0.85, 0.85)
    body:SetText(
        "BigNoteBox now stores your notes in a separate addon called |cffffcc00BigNoteBoxDB|r.\n\n" ..
        "This addon should have been installed alongside BigNoteBox.\n" ..
        "Please check your addon manager and make sure |cffffcc00BigNoteBoxDB|r is enabled,\n" ..
        "then reload your UI.\n\n" ..
        "|cffaaaaaaYour existing notes are safe and will reappear once BigNoteBoxDB is active.|r"
    )

    -- Reload button
    local reloadBtn = BNB.CreateButton(nil, panel, "Reload UI", 140, 30)
    reloadBtn:SetPoint("TOP", body, "BOTTOM", 0, -24)
    reloadBtn:SetScript("OnClick", function() C_UI.Reload() end)

    BNB._notesUnavailablePanel = panel
end

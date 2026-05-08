-- BigNoteBox UI/MainWindowSkin.lua
-- Custom-backdrop main window. Loaded after SkinSystem.lua.
-- Used when BigNoteBoxDB.skinMode == true. BNB.CreateMainWindowSkin() is called
-- from BNB.OpenMainWindow() (defined in SkinSystem.lua).
--
-- Sets BNB.mainFrame so all child modules (NoteList, NoteEditor, Sidebar, etc.)
-- work without modification.
--
-- Skin preset logic, target registry, BNB.ApplyMainWindowSkin,
-- BNB.CreateSkinFrame, BNB.CreateSkinStrip, BNB.CreateSkinTabs,
-- and BNB.OpenMainWindow all live in SkinSystem.lua.
--------------------------------------------------------------------------------

local BNB = BigNoteBox
local L   = BNB.L

-- ── Layout constants ──────────────────────────────────────────────────────────
local SK_WIN_W       = 820
local SK_WIN_H       = 640
local SK_TITLE_H     = 20    -- top row: window title + X / lock / focus buttons
local SK_TOOLBAR_H   = 35    -- sort dropdowns + topbar icons strip
local SK_LIST_W      = 250   -- left pane total width
local SK_SEARCH_H    = 30    -- search bar at top of list pane
local SK_LIST_BOT_H  = 40    -- New Note / Quick Note bar at bottom of list pane
local SK_NOTE_HDR_H  = 50    -- note title editbox area
local SK_TS_H        = 20    -- timestamp strip
local SK_WYS_H       = 25    -- WYSIWYG formatting toolbar
local SK_TAG_H       = 20    -- tag chips strip
local SK_BOT_H       = 40    -- editor action bar

local SK_CHROME_H    = SK_TITLE_H + SK_TOOLBAR_H   -- 55

local SK_MIN_W       = 500
local SK_MIN_H       = 400
local SK_MIN_LIST_W  = 160
local SK_MAX_LIST_W  = 460
local SK_COLLAPSED_W = 82    -- must match COLLAPSED_W in NoteList.lua

-- ── Asset paths ──────────────────────────────────────────────────────────────
local BTNS   = "Interface\\AddOns\\BigNoteBox\\Assets\\Buttons\\"
local TOPBAR = "Interface\\AddOns\\BigNoteBox\\Assets\\Topbar\\"

-- ── Skin system — see SkinSystem.lua ─────────────────────────────────────────
-- BNB.GetSkinPreset, BNB.SkinColourOf, BNB.CreateSkinFrame, BNB.CreateSkinStrip,
-- BNB.RegisterSkinTarget, BNB.ApplyMainWindowSkin all live in SkinSystem.lua.
-- Pass isMain=true to CreateSkinFrame/CreateSkinStrip so frames register to the
-- main-window target list (not the external list).
local function SkinFrame(frameType, name, parent, lifted)
    return BNB.CreateSkinFrame(parent, lifted, name, true)
end
local function SkinFrameStrip(parent, lifted)
    return BNB.CreateSkinStrip(parent, lifted, true)
end

--------------------------------------------------------------------------------
-- POSITION / SIZE / SPLIT PERSISTENCE  (shared with MainWindow.lua)
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
    local w   = math.max(pos.w or SK_WIN_W, SK_MIN_W)
    local h   = math.max(pos.h or SK_WIN_H, SK_MIN_H)
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

local function ApplySplit(f, listPane, editorPane, _divider, splitter)
    local lw = BNB._listPaneW
    listPane:SetWidth(lw)
    splitter:SetPoint("TOPLEFT",    f, "TOPLEFT",    lw - 3, -SK_CHROME_H)
    splitter:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", lw - 3,  0)
    editorPane:SetPoint("TOPLEFT",     f, "TOPLEFT",     lw + 1, -SK_CHROME_H)
    editorPane:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT",  0,      0)
end

--------------------------------------------------------------------------------
-- ICON TOOLBAR BUTTON  (identical behaviour to MainWindow.lua)
-- parent     : frame to parent the button to (f, to avoid backdrop border bleed)
-- anchorFrame: frame to anchor BOTTOMRIGHT position against (toolBar)
--------------------------------------------------------------------------------
local function MakeIconToolbarBtn(parent, anchorFrame, iconTex, tooltipText, xOff, yOff, onClick)
    local ICON_SZ = 20
    local REST    = 2
    local HOVER   = 2
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(ICON_SZ, ICON_SZ)
    btn:SetPoint("BOTTOMRIGHT", anchorFrame, "BOTTOMRIGHT", xOff, yOff)

    local tx = btn:CreateTexture(nil, "ARTWORK")
    tx:SetPoint("TOPLEFT",     btn, "TOPLEFT",      REST, -REST)
    tx:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -REST,  REST)
    tx:SetTexture(iconTex)
    btn._tx = tx

    btn:SetScript("OnEnter", function(self)
        tx:SetPoint("TOPLEFT",     btn, "TOPLEFT",     -HOVER,  HOVER)
        tx:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT",  HOVER, -HOVER)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:AddLine(tooltipText, 1, 1, 1)
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function()
        tx:SetPoint("TOPLEFT",     btn, "TOPLEFT",      REST, -REST)
        tx:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -REST,  REST)
        GameTooltip:Hide()
    end)
    btn:SetScript("OnClick", onClick)
    return btn
end

--------------------------------------------------------------------------------
-- TEXTURE BUTTON  (normal / hover / press TGA set)
--------------------------------------------------------------------------------
local function MakeTexBtn(parent, baseName, size, onClick, tipTitle, tipSub)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(size, size)
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

    -- expose textures for external refresh (lock button toggles them)
    btn._n, btn._h, btn._p = n, h, p
    return btn
end

--------------------------------------------------------------------------------
-- CREATE MAIN WINDOW (SKIN VERSION)
--------------------------------------------------------------------------------
function BNB.CreateMainWindowSkin()
    if BNB.mainFrame then return end

    -- Expose chrome height so child modules (NoteEditor anchor, etc.) use correct value
    BNB.MAIN_TITLE_H   = SK_CHROME_H
    BNB.MAIN_TOOLBAR_H = SK_BOT_H

    BNB._listPaneW = math.max(SK_MIN_LIST_W,
        math.min(SK_MAX_LIST_W, BigNoteBoxDB.splitX or SK_LIST_W))

    -- ── Outer window frame ────────────────────────────────────────────────────
    local f = SkinFrame("Frame", "BigNoteBoxFrame", UIParent, false)
    f:SetSize(SK_WIN_W, SK_WIN_H)
    f:SetPoint("CENTER")
    f:SetToplevel(true)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:SetResizable(true)
    f:SetClampedToScreen(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) self:StartMoving() end)
    f:SetScript("OnDragStop",  function(self)
        self:StopMovingOrSizing()
        SaveWindowPos(self)
    end)

    -- ── Title bar strip (window title + X / lock / focus) ────────────────────
    local titleBar = SkinFrameStrip(f, true)
    titleBar:SetPoint("TOPLEFT",  f, "TOPLEFT",  0,  0)
    titleBar:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0,  0)
    titleBar:SetHeight(SK_TITLE_H)
    -- Title bar is also the drag handle
    titleBar:EnableMouse(true)
    titleBar:RegisterForDrag("LeftButton")
    titleBar:SetScript("OnDragStart", function() f:StartMoving() end)
    titleBar:SetScript("OnDragStop",  function() f:StopMovingOrSizing(); SaveWindowPos(f) end)

    local titleLbl = titleBar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    -- Offset left by ~40px so it centres in the space left of the buttons
    titleLbl:SetPoint("CENTER", titleBar, "CENTER", -40, 0)
    titleLbl:SetTextColor(1, 0.82, 0)
    titleLbl:SetText(L["WINDOW_TITLE"])

    -- Close button
    local closeBtn = BNB.CreateSkinCloseButton(titleBar,
        function() BNB.RequestCloseMainWindow() end)
    closeBtn:SetPoint("RIGHT", titleBar, "RIGHT", -2, 0)

    -- Focus mode button
    local focusBtn = MakeTexBtn(titleBar, "bt-focus", 18,
        function() if BNB.OpenFocusMode then BNB.OpenFocusMode() end end,
        L["FOCUS_MODE_TIP"], L["FOCUS_MODE_TIP_SUB"])
    focusBtn:SetPoint("RIGHT", closeBtn, "LEFT", -4, 0)
    BNB._focusModeBtn = focusBtn
    -- Start disabled — no note selected yet; UpdateSaveButtonState re-enables on note load
    focusBtn:SetEnabled(false)
    focusBtn:SetAlpha(0.35)
    pcall(function() focusBtn._n:SetDesaturated(true) end)

    -- Scale-lock button
    local function IsLocked() return BigNoteBoxDB and BigNoteBoxDB.scaleLocked end

    local lockBtn = CreateFrame("Button", nil, titleBar)
    lockBtn:SetSize(18, 18)
    lockBtn:SetPoint("RIGHT", focusBtn, "LEFT", -4, 0)
    lockBtn:SetHighlightTexture("")
    lockBtn:SetPushedTexture("")

    local lockTex     = lockBtn:CreateTexture(nil, "ARTWORK"); lockTex:SetAllPoints()
    local unlockTex   = lockBtn:CreateTexture(nil, "ARTWORK"); unlockTex:SetAllPoints()
    local lockHov     = lockBtn:CreateTexture(nil, "ARTWORK"); lockHov:SetAllPoints();   lockHov:Hide()
    local unlockHov   = lockBtn:CreateTexture(nil, "ARTWORK"); unlockHov:SetAllPoints(); unlockHov:Hide()
    local lockPress   = lockBtn:CreateTexture(nil, "ARTWORK"); lockPress:SetAllPoints(); lockPress:Hide()
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
            f:SetSize(SK_WIN_W, SK_WIN_H)
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
        if locked then lockTex:Hide(); lockHov:Show()
        else           unlockTex:Hide(); unlockHov:Show() end
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
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
    lockBtn:SetScript("OnLeave", function() RefreshLockBtn(); GameTooltip:Hide() end)
    BNB._lockScaleBtn   = lockBtn
    BNB._refreshLockBtn = RefreshLockBtn

    function BNB._applyScaleLock()
        local locked = BigNoteBoxDB and BigNoteBoxDB.scaleLocked
        local rh = BNB.mainFrame and BNB.mainFrame._resizeHandle
        if rh then rh:SetShown(not locked) end
        if BNB.mainFrame and BNB.mainFrame.SetResizable then
            BNB.mainFrame:SetResizable(not locked)
        end
        if BNB._refreshLockBtn then BNB._refreshLockBtn() end
    end

    -- Skin randomise button (top-left of title bar)
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
            local pick = pool[math.random(#pool)]
            db.skinPreset = pick
            -- Randomise brightness between 0.5 and 3.0 (step 0.05)
            local steps = math.random(0, 50)  -- 0..50 → 0.5..3.0
            db.skinBrightness = 0.5 + steps * 0.05
            if BNB.ApplyMainWindowSkin then BNB.ApplyMainWindowSkin() end
            if BNB._refreshSkinConfig then BNB._refreshSkinConfig() end
        end,
        "Random skin", "Click to randomly change the skin preset and brightness")
    skinChangeBtn:SetPoint("RIGHT", lockBtn, "LEFT", -4, 0)

    -- ── Toolbar strip (sort dropdowns + topbar icons) ─────────────────────────
    -- Plain frame — no backdrop so the main window body shows through seamlessly.
    local toolBar = CreateFrame("Frame", nil, f)
    toolBar:SetPoint("TOPLEFT",  f, "TOPLEFT",  0, -SK_TITLE_H)
    toolBar:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, -SK_TITLE_H)
    toolBar:SetHeight(SK_TOOLBAR_H)

    -- Sort + direction dropdowns and Select button
    local SORT_BTN_H = 22
    local SORT_MODES = {
        { key="custom",   label="Custom"   },
        { key="creation", label="Creation" },
        { key="edited",   label="Edited"   },
        { key="alpha",    label="A-Z"      },
        { key="location", label="Location" },
    }
    local DIR_MODES = {
        { key="desc", label="Descending" },
        { key="asc",  label="Ascending"  },
    }
    local function CurrentSortLabel()
        for _, m in ipairs(SORT_MODES) do
            if m.key == (BigNoteBoxDB.sortBy or "creation") then return m.label end
        end
        return "Creation"
    end
    local function IsCustomSort()  return BigNoteBoxDB.sortBy == "custom" end
    local function CurrentDirKey() return BigNoteBoxDB.sortAsc and "asc" or "desc" end
    local function CurrentDirLabel()
        return BigNoteBoxDB.sortAsc and "Ascending" or "Descending"
    end

    local sortDD, sortCycleBtn, dirDD, dirCycleBtn
    local sortDDWidth = 120
    local dirDDWidth  = 120

    local function ApplySort()
        if BNB.RefreshNoteList then BNB.RefreshNoteList() end
    end

    local function UpdateDirEnabled()
        local custom = IsCustomSort()
        if dirDD       then dirDD:SetEnabled(not custom);       dirDD:SetAlpha(custom and 0.4 or 1.0)       end
        if dirCycleBtn then dirCycleBtn:SetEnabled(not custom); dirCycleBtn:SetAlpha(custom and 0.4 or 1.0) end
    end

    local useNativeSort = C_XMLUtil and C_XMLUtil.GetTemplateInfo
        and C_XMLUtil.GetTemplateInfo("WowStyle1DropdownTemplate")

    local BTN_Y = -(SK_TOOLBAR_H - SORT_BTN_H) / 2   -- vertically centred in toolbar

    if useNativeSort then
        -- Parent to f (not toolBar) — WowStyle1DropdownTemplate must not inherit
        -- a backdrop frame's border. Anchor position still tracks the toolbar strip.
        sortDD = CreateFrame("DropdownButton", "BNBMainSortDD", f, "WowStyle1DropdownTemplate")
        sortDD:SetSize(sortDDWidth, SORT_BTN_H)
        sortDD:SetPoint("TOPLEFT", toolBar, "TOPLEFT", 8, BTN_Y)
        sortDD:SetupMenu(function(_, root)
            for _, m in ipairs(SORT_MODES) do
                local key = m.key
                root:CreateRadio(m.label,
                    function() return (BigNoteBoxDB.sortBy or "creation") == key end,
                    function() BigNoteBoxDB.sortBy = key; sortDD:GenerateMenu(); ApplySort() end)
            end
        end)
        BNB._rebuildSortMenu = function()
            if sortDD and sortDD.GenerateMenu then sortDD:GenerateMenu() end
        end

        dirDD = CreateFrame("DropdownButton", "BNBMainDirDD", f, "WowStyle1DropdownTemplate")
        dirDD:SetSize(dirDDWidth, SORT_BTN_H)
        dirDD:SetPoint("LEFT", sortDD, "RIGHT", 4, 0)
        dirDD:SetupMenu(function(_, root)
            for _, m in ipairs(DIR_MODES) do
                local key = m.key
                root:CreateRadio(m.label,
                    function() return CurrentDirKey() == key end,
                    function() BigNoteBoxDB.sortAsc = (key == "asc"); dirDD:GenerateMenu(); ApplySort() end)
            end
        end)
        BNB._rebuildDirMenu = function()
            if dirDD and dirDD.GenerateMenu then dirDD:GenerateMenu() end
        end
    else
        sortCycleBtn = BNB.CreateButton(nil, f, CurrentSortLabel(), sortDDWidth, SORT_BTN_H)
        sortCycleBtn:SetPoint("TOPLEFT", toolBar, "TOPLEFT", 8, BTN_Y)
        sortCycleBtn:SetScript("OnClick", function(self)
            local cur = BigNoteBoxDB.sortBy or "creation"
            local idx = 1
            for i, m in ipairs(SORT_MODES) do if m.key == cur then idx = i; break end end
            idx = (idx % #SORT_MODES) + 1
            BigNoteBoxDB.sortBy = SORT_MODES[idx].key
            self:SetText(CurrentSortLabel())
            ApplySort()
        end)

        dirCycleBtn = BNB.CreateButton(nil, f, CurrentDirLabel(), dirDDWidth, SORT_BTN_H)
        dirCycleBtn:SetPoint("LEFT", sortCycleBtn, "RIGHT", 4, 0)
        dirCycleBtn:SetScript("OnClick", function(self)
            BigNoteBoxDB.sortAsc = not BigNoteBoxDB.sortAsc
            self:SetText(CurrentDirLabel())
            UpdateDirEnabled(); ApplySort()
        end)
    end

    -- Hook ApplySort to also refresh direction state
    local _origApplySort = ApplySort
    ApplySort = function()
        _origApplySort(); UpdateDirEnabled()
        if dirDD and dirDD.GenerateMenu then dirDD:GenerateMenu() end
        if dirCycleBtn then dirCycleBtn:SetText(CurrentDirLabel()) end
    end

    -- Select button
    local selBtn = BNB.CreateButton(nil, toolBar, "Select", 52, SORT_BTN_H)
    if useNativeSort then
        selBtn:SetPoint("LEFT", dirDD, "RIGHT", 6, 0)
    else
        selBtn:SetPoint("LEFT", dirCycleBtn, "RIGHT", 6, 0)
    end
    selBtn:SetPoint("TOP", toolBar, "TOP", 0, BTN_Y)
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

    -- Multi-select action buttons (hidden until select mode active)
    local function MakeMultiBtn(text, w, onClick, tip)
        local btn = BNB.CreateButton(nil, toolBar, text, w, SORT_BTN_H)
        btn:SetPoint("LEFT", selBtn, "RIGHT", 4, 0)   -- will be re-anchored below
        btn:SetPoint("TOP",  selBtn, "TOP",   0,  0)
        btn:SetEnabled(false); btn:Hide()
        btn:SetScript("OnClick", onClick)
        btn:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
            GameTooltip:AddLine(tip, 1,1,1)
            GameTooltip:Show()
        end)
        btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
        return btn
    end

    local selectAllBtn = BNB.CreateButton(nil, toolBar, "Select All", 76, SORT_BTN_H)
    selectAllBtn:SetPoint("LEFT", selBtn, "RIGHT", 4, 0)
    selectAllBtn:SetPoint("TOP",  selBtn, "TOP",   0, 0)
    selectAllBtn:Hide()
    selectAllBtn:SetScript("OnClick", function() if BNB.SelectAll then BNB.SelectAll() end end)
    selectAllBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:AddLine("Select all notes", 1,1,1); GameTooltip:Show()
    end)
    selectAllBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    BNB._multiSelectAllBtn = selectAllBtn

    local multiDelBtn = BNB.CreateButton(nil, toolBar, "Delete (0)", 90, SORT_BTN_H)
    multiDelBtn:SetPoint("LEFT", selectAllBtn, "RIGHT", 4, 0)
    multiDelBtn:SetPoint("TOP",  selBtn, "TOP", 0, 0)
    multiDelBtn:SetEnabled(false); multiDelBtn:Hide()
    multiDelBtn:SetScript("OnClick", function() if BNB.DeleteMultiSelected then BNB.DeleteMultiSelected() end end)
    multiDelBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:AddLine("Delete selected notes", 1,1,1); GameTooltip:Show()
    end)
    multiDelBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    BNB._multiDeleteBtn = multiDelBtn

    local multiCopyMoveBtn = BNB.CreateButton(nil, toolBar, "Copy / Move (0)", 120, SORT_BTN_H)
    multiCopyMoveBtn:SetPoint("LEFT", multiDelBtn, "RIGHT", 4, 0)
    multiCopyMoveBtn:SetPoint("TOP",  selBtn, "TOP", 0, 0)
    multiCopyMoveBtn:SetEnabled(false); multiCopyMoveBtn:Hide()
    multiCopyMoveBtn:SetScript("OnClick", function()
        if BNB.CopyMoveMultiSelected then BNB.CopyMoveMultiSelected() end
    end)
    multiCopyMoveBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:AddLine("Copy or move selected notes", 1,1,1); GameTooltip:Show()
    end)
    multiCopyMoveBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    BNB._multiCopyMoveBtn = multiCopyMoveBtn

    local multiExportBtn = BNB.CreateButton(nil, toolBar, "Export (0)", 90, SORT_BTN_H)
    multiExportBtn:SetPoint("LEFT", multiCopyMoveBtn, "RIGHT", 4, 0)
    multiExportBtn:SetPoint("TOP",  selBtn, "TOP", 0, 0)
    multiExportBtn:SetEnabled(false); multiExportBtn:Hide()
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

    -- Topbar icon buttons (right side of toolbar strip)
    -- Parented to f, not toolBar, to avoid inheriting the backdrop border.
    -- Anchored to toolBar's BOTTOMRIGHT so position still tracks the strip.
    local ICON_Y_OFF = 8   -- px from toolbar bottom edge
    local function TBIcon(tex, tip, xOff, onClick)
        return MakeIconToolbarBtn(f, toolBar, tex, tip, xOff, ICON_Y_OFF, onClick)
    end

    local configBtn = TBIcon(TOPBAR.."tp-cog", "Settings (/bnb config)", -(8+24),
        function()
            if BNB.OpenConfig        then BNB.OpenConfig()        end
        end)
    BNB._toolbarConfigBtn = configBtn

    -- Sidebar toggle button — right of cog
    local sidebarToggleBtn = TBIcon(TOPBAR.."tp-sidebar-open", "Toggle sidebar", -8,
        function()
            if BNB.Sidebar and BNB.Sidebar.ToggleCollapsed then
                BNB.Sidebar.ToggleCollapsed()
            end
        end)
    BNB._toolbarSidebarBtn = sidebarToggleBtn

    function BNB.RefreshSidebarToggleBtn()
        local collapsed = BigNoteBoxDB and BigNoteBoxDB.sidebarCollapsed
        local tex = TOPBAR .. (collapsed and "tp-sidebar-closed" or "tp-sidebar-open")
        pcall(function() BNB._toolbarSidebarBtn._tx:SetTexture(tex) end)
    end
    BNB.RefreshSidebarToggleBtn()

    local trashBtn = TBIcon(TOPBAR.."tp-trash", "Trash  (deleted notes)", -(8+24*2),
        function() if BNB.ToggleTrashWindow then BNB.ToggleTrashWindow() end end)
    BNB._toolbarTrashBtn = trashBtn

    local histBtn = TBIcon(TOPBAR.."tp-history", L["HISTORY_TOOLBAR_TIP"], -(8+24*3),
        function() if BNB.ToggleHistoryWindow then BNB.ToggleHistoryWindow() end end)
    histBtn:SetEnabled(false); histBtn:SetAlpha(0.4)
    pcall(function() histBtn._tx:SetDesaturated(true) end)
    BNB._toolbarHistoryBtn = histBtn

    local tagsBtn = TBIcon(TOPBAR.."tp-tags", L["TAG_MGR_TOOLTIP"], -(8+24*4),
        function() if BNB.ToggleTagManager then BNB.ToggleTagManager() end end)
    BNB._toolbarTagsBtn = tagsBtn

    local alarmOvBtn = TBIcon(TOPBAR.."tp-alarm", "Alarms", -(8+24*6),
        function()
            if BNB.AlarmOverview and BNB.AlarmOverview.Toggle then
                BNB.AlarmOverview.Toggle()
            end
        end)
    BNB._toolbarAlarmOvBtn = alarmOvBtn

    local shareTopBtn = TBIcon(TOPBAR.."tp-share", "Import a shared note", -(8+24*5),
        function()
            if BNB.OpenImportWindow then BNB.OpenImportWindow() end
        end)
    BNB._toolbarShareTopBtn = shareTopBtn

    local importBtnTex = (BigChatBox and BigChatBox.SendDirect)
        and TOPBAR.."tp-bcb"
        or  "Interface\\AddOns\\BigNoteBox\\Assets\\BCB\\bcb-icon"
    local importBtn = TBIcon(importBtnTex, "Send note to BigChatBox multiline input", -(8+24*7),
        function()
            if not (BigChatBox and BigChatBox.SendDirect) then
                if BNB.ShowBCBPromo then BNB.ShowBCBPromo() end; return
            end
            local id   = BNB._currentNoteID
            local note = id and BNB.GetNote(id)
            local body = note and (note.body or "") or ""
            if body == "" then BNB:Print("|cffff6666This note is empty.|r"); return end
            if BCB_OpenMultiline then BCB_OpenMultiline() end
            C_Timer.After(0.05, function()
                if BigChatBox.mlEditBox then
                    BigChatBox.mlEditBox:SetText(body)
                    BigChatBox.mlEditBox:SetFocus()
                    BigChatBox.mlEditBox:SetCursorPosition(#body)
                end
            end)
        end)
    local function RefreshImportBtn()
        local hasBCB = BigChatBox and BigChatBox.SendDirect and true or false
        pcall(function()
            importBtn._tx:SetTexture(hasBCB
                and TOPBAR.."tp-bcb"
                or  "Interface\\AddOns\\BigNoteBox\\Assets\\BCB\\bcb-icon")
            importBtn._tx:SetDesaturated(false)
            importBtn:SetAlpha(1.0)
        end)
    end
    RefreshImportBtn()
    BNB._toolbarImportBtn = importBtn
    BNB._refreshImportBtn = RefreshImportBtn

    -- ── Topbar icon tinting (skin mode only) ──────────────────────────────────
    -- Tint all topbar icon textures to SkinBorderOf × 2.2, matching the wysiwyg
    -- icon tint pattern. BCB import button is only tinted when BCB is installed;
    -- without BCB it shows the promo icon which should stay unskinned.
    -- SetVertexColor + SetDesaturated(true) produces the correct greyed-out look
    -- for disabled buttons (history etc.), same as wysiwyg disabled icons.
    if BigNoteBoxDB and BigNoteBoxDB.skinMode and BNB.GetSkinPreset then
        local p = BNB.GetSkinPreset()
        local br, bg_, bb = BNB.SkinBorderOf(p)
        local MULT = 2.2
        local function TintTx(tx)
            if not tx then return end
            tx:SetVertexColor(math.min(1, br * MULT), math.min(1, bg_ * MULT), math.min(1, bb * MULT))
            BNB.RegisterSkinIconTex(tx, MULT)
        end
        TintTx(configBtn._tx)
        TintTx(sidebarToggleBtn._tx)
        TintTx(trashBtn._tx)
        TintTx(histBtn._tx)
        TintTx(tagsBtn._tx)
        TintTx(alarmOvBtn._tx)
        TintTx(shareTopBtn._tx)
        -- BCB button: only tint when BCB is installed (tp-bcb icon); skip promo icon
        if BigChatBox and BigChatBox.SendDirect then
            TintTx(importBtn._tx)
        end
    end

    function BNB._setToolbarMultiMode(on)
        local btns = {
            BNB._toolbarSidebarBtn, BNB._toolbarConfigBtn,  BNB._toolbarTrashBtn,
            BNB._toolbarHistoryBtn, BNB._toolbarTagsBtn,    BNB._toolbarShareTopBtn,
            BNB._toolbarAlarmOvBtn, BNB._toolbarImportBtn,
        }
        for _, btn in ipairs(btns) do if btn then btn:SetShown(not on) end end
    end

    C_Timer.After(0, function() UpdateDirEnabled(); ApplySort() end)

    -- ── ESC handling ──────────────────────────────────────────────────────────
    f:SetPropagateKeyboardInput(false)
    f:EnableKeyboard(true)
    f:SetScript("OnKeyDown", function(self, key)
        if key ~= "ESCAPE" then self:SetPropagateKeyboardInput(true); return end
        self:SetPropagateKeyboardInput(false)
        local function TryHide(name, closeFn)
            local w = _G[name]
            if w and w:IsShown() then
                if closeFn then closeFn() else w:Hide() end
                return true
            end
        end
        if TryHide("BNBNewNoteDialogFrame",
            function() if BNB.NewNoteDialog and BNB.NewNoteDialog.Close then BNB.NewNoteDialog.Close() end end)
        then return end
        if TryHide("BNBClipboardHintFrame",
            function() if BNB._clipboardHint and BNB._clipboardHint._dismiss then BNB._clipboardHint._dismiss() end end)
        then return end
        if TryHide("BNBSidebarIconPickerFrame") then return end
        if BNB.CloseInsertInfoMenu and BNB.CloseInsertInfoMenu() then return end
        if TryHide("BigNoteBoxExportFrame")   then return end
        if TryHide("BigNoteBoxCopyMoveFrame") then return end
        if TryHide("BigNoteBoxHistoryCompareFrame",
            function() BNB.CloseHistoryCompare() end) then return end
        if TryHide("BNBAlarmWindow",
            function() if BNB.AlarmWindow and BNB.AlarmWindow.Close then BNB.AlarmWindow.Close() end end)
        then return end
        if TryHide("BNBAlarmOverviewFrame") then return end
        if TryHide("BigNoteBoxStickySettingsFrame",
            function() if BNB.Sticky and BNB.Sticky.CloseSettings then BNB.Sticky.CloseSettings() end end)
        then return end
        if TryHide("BigNoteBoxTagManagerFrame") then return end
        if TryHide("BigNoteBoxNoteHistoryFrame",
            function() BNB.CloseNoteHistoryPanel() end) then return end
        if TryHide("BigNoteBoxHistoryFrame",
            function() BNB.CloseHistoryWindow() end) then return end
        if TryHide("BNBTrashViewPopup")       then return end
        if TryHide("BigNoteBoxTrashFrame")    then return end
        if TryHide("BigNoteBoxNoteConfigFrame") then return end
        if TryHide("BigNoteBoxReferenceBoxFrame") then return end
        if TryHide("BigNoteBoxConfigFrame")   then return end
        BNB.RequestCloseMainWindow()
    end)

    -- ── Resize handle ─────────────────────────────────────────────────────────
        f:SetResizeBounds(SK_MIN_W, SK_MIN_H, 1400, 1000)

    local resizeHandle = CreateFrame("Button", nil, f)
    resizeHandle:SetSize(16, 16)
    resizeHandle:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -2, 2)
    resizeHandle:SetFrameLevel(f:GetFrameLevel() + 10)
    local rtex = resizeHandle:CreateTexture(nil, "OVERLAY")
    rtex:SetAllPoints()
    rtex:SetTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    f._resizeHandle = resizeHandle

    local sizeLabel = CreateFrame("Frame", nil, UIParent)
    sizeLabel:SetSize(90, 22); sizeLabel:SetFrameStrata("TOOLTIP"); sizeLabel:Hide()
    local slBg  = sizeLabel:CreateTexture(nil, "BACKGROUND"); slBg:SetAllPoints()
    slBg:SetColorTexture(0, 0, 0, 0.75)
    local slTxt = sizeLabel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    slTxt:SetAllPoints(); slTxt:SetJustifyH("CENTER"); slTxt:SetTextColor(1,1,1)

    local _resizing = false
    local function SidebarW()
        return (BNB.Sidebar and BNB.Sidebar.IsEnabled and BNB.Sidebar.IsEnabled()) and 64 or 0
    end

    f:HookScript("OnSizeChanged", function(self)
        if not _resizing then return end
        local w = math.floor(self:GetWidth() - SidebarW())
        local h = math.floor(self:GetHeight())
        slTxt:SetText(w .. " x " .. h)
        local cx, cy = GetCursorPosition()
        local uisc = UIParent:GetEffectiveScale()
        sizeLabel:ClearAllPoints()
        sizeLabel:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", cx/uisc+14, cy/uisc+4)
    end)

    resizeHandle:SetScript("OnMouseDown", function(self, btn)
        if btn ~= "LeftButton" then return end
        local left, top = f:GetLeft(), f:GetTop()
        if left and top then
            -- GetLeft/GetTop return values already in UIParent coordinate space
            f:ClearAllPoints()
            f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
        end
        _resizing = true
        slTxt:SetText(math.floor(f:GetWidth()-SidebarW()) .. " x " .. math.floor(f:GetHeight()))
        local cx, cy = GetCursorPosition()
        local uisc = UIParent:GetEffectiveScale()
        sizeLabel:ClearAllPoints()
        sizeLabel:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", cx/uisc+14, cy/uisc+4)
        sizeLabel:Show()
        f:StartSizing("BOTTOMRIGHT")
    end)
    resizeHandle:SetScript("OnMouseUp", function()
        _resizing = false; sizeLabel:Hide(); f:StopMovingOrSizing()
        local w = math.max(SK_MIN_W, math.min(1400, f:GetWidth()))
        local h = math.max(SK_MIN_H, math.min(1000, f:GetHeight()))
        f:SetSize(w, h); SaveWindowPos(f)
        ApplySplit(f, BNB.listPane, BNB.editorPane, nil, f._splitter)
        if BNB.Sidebar and BNB.Sidebar.Refresh then BNB.Sidebar.Refresh() end
    end)

    -- ── Splitter ──────────────────────────────────────────────────────────────
    local splitter = CreateFrame("Button", nil, f)
    f._splitter = splitter
    splitter:SetWidth(7)
    splitter:SetFrameLevel(f:GetFrameLevel() + 5)

    local _splitterDots = {}
    for i = -1, 1 do
        local dot = splitter:CreateTexture(nil, "OVERLAY")
        dot:SetSize(3, 3)
        dot:SetPoint("CENTER", splitter, "CENTER", 0, i * 5)
        local p0 = BNB.GetSkinPreset()
        dot:SetColorTexture(math.min(1,p0.br+0.15), math.min(1,p0.bg_+0.15), math.min(1,p0.bb+0.15), 0.9)
        _splitterDots[#_splitterDots + 1] = dot
    end
    splitter:SetScript("OnEnter", function(self)
        for _, r in ipairs({self:GetRegions()}) do
            if r.SetColorTexture then r:SetColorTexture(1, 0.82, 0, 1) end
        end
    end)
    splitter:SetScript("OnLeave", function(self)
        local p = BNB.GetSkinPreset()
        local dotR = math.min(1, p.br + 0.15)
        local dotG = math.min(1, p.bg_ + 0.15)
        local dotB = math.min(1, p.bb + 0.15)
        for _, r in ipairs({self:GetRegions()}) do
            if r.SetColorTexture then r:SetColorTexture(dotR, dotG, dotB, 0.9) end
        end
    end)

    local _splitting = false
    splitter:SetScript("OnMouseDown", function(self, btn)
        if btn ~= "LeftButton" then return end
        _splitting = true
        self:SetScript("OnUpdate", function()
            if not _splitting then self:SetScript("OnUpdate", nil); return end
            local mx = GetCursorPosition() / f:GetEffectiveScale()
            local fx = f:GetLeft()
            if not mx or not fx then return end
            local newW = math.max(SK_MIN_LIST_W, math.min(SK_MAX_LIST_W, math.floor(mx - fx)))
            local maxW = f:GetWidth() - 300 - 1
            newW = math.min(newW, maxW)
            if newW ~= BNB._listPaneW then
                BNB._listPaneW = newW
                ApplySplit(f, BNB.listPane, BNB.editorPane, nil, splitter)
            end
        end)
    end)
    splitter:SetScript("OnMouseUp", function(self, btn)
        if btn ~= "LeftButton" then return end
        _splitting = false
        self:SetScript("OnUpdate", nil)
        BigNoteBoxDB.splitX = BNB._listPaneW
    end)

    -- ── Left pane (note list) ─────────────────────────────────────────────────
    local listPane = CreateFrame("Frame", nil, f)
    listPane:SetPoint("TOPLEFT",    f, "TOPLEFT",    0, -SK_CHROME_H)
    listPane:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0,  0)
    BNB.listPane = listPane

    -- ── Right pane (editor) ───────────────────────────────────────────────────
    local editorPane = CreateFrame("Frame", nil, f)
    editorPane:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
    BNB.editorPane = editorPane

    ApplySplit(f, listPane, editorPane, nil, splitter)

    -- ── Lifecycle ─────────────────────────────────────────────────────────────
    f:SetScript("OnShow", function(self)
        if BigNoteBoxDB.listCollapsed then
            BNB._listPaneW = SK_COLLAPSED_W
            splitter:EnableMouse(false)
        else
            BNB._listPaneW = math.max(SK_MIN_LIST_W,
                math.min(SK_MAX_LIST_W, BigNoteBoxDB.splitX or SK_LIST_W))
            splitter:EnableMouse(true)
        end
        ApplySplit(f, listPane, editorPane, nil, splitter)
        if not self._fromFocusMode then RestoreWindowPos(self) end
        self._fromFocusMode = false
        BNB.ApplyMainWindowSkin()   -- apply current preset live on show
        if BNB.RefreshNoteList then BNB.RefreshNoteList() end
        local sel = BigNoteBoxDB.selectedNoteID
        if sel and BigNoteBoxNotesDB.notes[sel] then
            local stub = BigNoteBoxNotesDB.notes[sel]
            if stub.title == nil or stub.title == "" then
                if BNB.PurgeNote then BNB.PurgeNote(sel) end
                BigNoteBoxDB.selectedNoteID = nil; sel = nil
                if BNB.RefreshNoteList then BNB.RefreshNoteList() end
            end
        end
        if sel and BigNoteBoxNotesDB.notes[sel] then
            if BNB.SelectNote then BNB.SelectNote(sel) end
        end
        if BNB._applyScaleLock then BNB._applyScaleLock() end
    end)

    f:SetScript("OnHide", function(self)
        if self._focusHide then return end
        if BigNoteBoxDB and BigNoteBoxDB.confirmClose and not self._skipConfirm then
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
        BNB._favFilterActive = false
        if BNB._favBtn then
            BNB._favBtn:SetAlpha(0.35)
            pcall(function() BNB._favBtn._tx:SetDesaturated(true) end)
        end
        BNB.CloseCompanionWindows()
    end)

    f:Hide()
    BNB.mainFrame = f

    f:HookScript("OnShow", function()
        if BNB._refreshImportBtn then BNB._refreshImportBtn() end
    end)

    if BNB._notesAvailable then
        if BNB.BuildNoteList   then BNB.BuildNoteList()   end
        if BNB.BuildNoteEditor then BNB.BuildNoteEditor() end
    else
        BNB.BuildNotesUnavailablePanel(listPane, editorPane)
    end

    BNB._applyListCollapse = function(collapsed, collapsedW)
        if collapsed then
            BigNoteBoxDB.splitX = BNB._listPaneW
            BNB._listPaneW = collapsedW
            splitter:EnableMouse(false)
        else
            BNB._listPaneW = math.max(
                BigNoteBoxDB.splitX or SK_LIST_W, collapsedW + 40)
            splitter:EnableMouse(true)
        end
        ApplySplit(f, listPane, editorPane, nil, splitter)
    end
end

-- BNB.OpenMainWindow is defined in SkinSystem.lua.

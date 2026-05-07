-- BigNoteBox UI/Sidebar.lua
--
-- Character sidebar: a vertical strip of filter buttons attached to the right
-- edge of the main window. Filters the note list by scope.
--
-- Slot order (top to bottom):
--   All     -- shows every note regardless of scope
--   Global  -- shows only scope="global" notes
--   Pinned characters (up to 5, user-defined order)
--   Recent unpinned characters (most-recently-seen first, as many as fit)
--
-- Layout:
--   64px hidden "phantom" slot at top (clears the title bar area)
--   5px gap
--   Each slot: 64x64 button with sidebar-border.tga + 32x32 icon at (4, -7)
--   5px gap between slots
--
-- Active slot: icon at full brightness/saturation
-- Inactive slots: icon desaturated + 55% brightness
--
-- Public API:
--   BNB.Sidebar.Build(parent)
--   BNB.Sidebar.Refresh()
--   BNB.Sidebar.SetActive(key)
--   BNB.Sidebar.GetActive()
--   BNB.Sidebar.UpdateCounts()
--   BNB.Sidebar.IsEnabled()

local BNB = BigNoteBox
BNB.Sidebar = BNB.Sidebar or {}
local SB = BNB.Sidebar

--------------------------------------------------------------------------------
-- Constants
--------------------------------------------------------------------------------
local ASSETS        = "Interface\\AddOns\\BigNoteBox\\Assets\\"
local ICON_PATH     = "Interface\\AddOns\\BigNoteBox\\Assets\\Icons\\Classes\\"
local BTN_SZ        = 64     -- button frame size (matches sidebar-border.tga)

-- Icon folders available in the sidebar icon picker (Classes, Races, Factions only).
local SLOT_ICON_FOLDERS = {
    { path = "Interface\\AddOns\\BigNoteBox\\Assets\\Icons\\Classes\\" },
    { path = "Interface\\AddOns\\BigNoteBox\\Assets\\Icons\\Races\\" },
    { path = "Interface\\AddOns\\BigNoteBox\\Assets\\Icons\\Factions\\" },
}

-- Flat icon list built from the above folders at load time.
local SLOT_ICON_LIST = {}
do
    local manifest = BigNoteBox and BigNoteBox.ICON_MANIFEST or {}
    for _, folder in ipairs(SLOT_ICON_FOLDERS) do
        local lower = folder.path:lower()
        for _, path in ipairs(manifest) do
            if path:lower():sub(1, #lower) == lower then
                SLOT_ICON_LIST[#SLOT_ICON_LIST + 1] = path
            end
        end
    end
end
local ICON_SZ       = 48     -- icon texture size: fills the border's inner frame opening (full size)
local ICON_X        = 5     -- icon left offset (inner frame starts at 13px from left)
local ICON_Y        = -8     -- icon top offset  (inner frame starts at 8px from top)
local GAP           = 1      -- gap between slots
local TOP_PAD       = BTN_SZ + GAP   -- phantom slot height + gap (recalculated in GetLayoutVars)
local SLOT_STEP     = BTN_SZ + GAP   -- total vertical space per slot (recalculated in GetLayoutVars)

-- Returns current layout values based on DB settings.
-- Called at Refresh() time so changes take effect without a reload.
local function GetLayoutVars()
    local db = BigNoteBoxDB
    local small = db and db.sidebarSmallIcons == true
    local sz    = small and 32 or BTN_SZ       -- button frame size
    local isz   = small and 24 or ICON_SZ      -- icon texture size
    local ix    = small and 3  or ICON_X       -- icon left offset
    local iy    = small and -4 or ICON_Y       -- icon top offset
    local gap   = GAP
    local top   = sz + gap
    local step  = sz + gap
    return sz, isz, ix, iy, gap, top, step
end
local INACTIVE_SAT  = true   -- desaturate inactive icons
local INACTIVE_V    = 0.90   -- brightness multiplier for inactive icons
-- Colour of the active slot glow in non-skin mode (white TGA × green = BNB green)
local ACTIVE_R, ACTIVE_G, ACTIVE_B = 0.40, 0.85, 0.40
-- BNB_SIDEBAR_ACTIVE_GLOW_MULT: multiplier for skin mode active glow brightness (search this to adjust)
local ACTIVE_GLOW_MULT = 2.0
local MAX_PINNED    = 5

-- Class → icon filename (Assets/Icons/Classes/)
local CLASS_ICONS = {
    WARRIOR      = "ClassIcon_Warrior",
    PALADIN      = "ClassIcon_Paladin",
    HUNTER       = "ClassIcon_Hunter",
    ROGUE        = "ClassIcon_Rogue",
    PRIEST       = "ClassIcon_Priest",
    DEATHKNIGHT  = "ClassIcon_DeathKnight",
    SHAMAN       = "ClassIcon_Shaman",
    MAGE         = "ClassIcon_Mage",
    WARLOCK      = "ClassIcon_Warlock",
    MONK         = "ClassIcon_Monk",
    DRUID        = "ClassIcon_Druid",
    DEMONHUNTER  = "ClassIcon_DemonHunter",
    EVOKER       = "ClassIcon_Evoker",
}

--------------------------------------------------------------------------------
-- State
--------------------------------------------------------------------------------
local _strip      = nil   -- the container Frame (child of mainFrame)
local _activeKey  = "all"
local _btnPool    = {}    -- reusable button widgets { btn, borderTex, iconTex, badgeStr }
local _builtKeys  = {}    -- key order of currently visible buttons

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------
local function IsEnabled()
    local db = BigNoteBoxDB
    return db and db.sidebarEnabled == true
end
SB.IsEnabled = IsEnabled

local function GetActive()
    return _activeKey
end
SB.GetActive = GetActive

-- Returns icon texture path for a given slot key
local function IconForKey(key)
    if key == "all" then
        return ASSETS .. "Sidebar\\sb-all"
    elseif key == "global" then
        return ASSETS .. "Sidebar\\sb-global"
    else
        local charKey = key:match("^char:(.+)$")
        if charKey then
            local db  = BigNoteBoxDB
            local rec = db and db.knownChars and db.knownChars[charKey]
            -- Custom icon set by user takes priority
            if rec and rec.slotIcon then return rec.slotIcon end
            -- Fall back to class icon
            local cls = rec and rec.class or "WARRIOR"
            cls = cls:upper():gsub(" ", "")
            local iconFile = CLASS_ICONS[cls] or "ClassIcon_Warrior"
            return ICON_PATH .. iconFile
        end
    end
    return ASSETS .. "Sidebar\\sb-all"
end
SB.IconForKey = IconForKey

-- Count notes matching a sidebar filter key
local function CountForKey(key)
    local ndb = BigNoteBoxNotesDB
    if not ndb or not ndb.notes then return 0 end
    if key == "all" then
        local n = 0
        for _ in pairs(ndb.notes) do n = n + 1 end
        return n
    elseif key == "global" then
        local n = 0
        for _, note in pairs(ndb.notes) do
            if (note.scope == "global" or note.scope == nil) then n = n + 1 end
        end
        return n
    else
        -- char slot
        local n = 0
        for _, note in pairs(ndb.notes) do
            if note.scope == key then n = n + 1 end
        end
        return n
    end
end

-- Tooltip text for a slot button
local function TooltipForKey(key)
    if key == "all" then
        return "All Notes", "Shows all notes regardless of scope."
    elseif key == "global" then
        return "Global Notes", "Shows notes shared across all characters."
    else
        local charKey = key:match("^char:(.+)$")
        if charKey then
            local db  = BigNoteBoxDB
            local rec = db and db.knownChars and db.knownChars[charKey]
            if rec then
                local title = rec.name or charKey
                local lines = {}
                if rec.level then
                    lines[#lines + 1] = "Level " .. rec.level
                end
                if rec.class then
                    local cls = rec.class:sub(1,1):upper() .. rec.class:sub(2):lower()
                    lines[#lines + 1] = cls
                end
                if rec.guild then
                    lines[#lines + 1] = "<" .. rec.guild .. ">"
                end
                local sub = #lines > 0 and table.concat(lines, "  |  ") or charKey
                return title, sub
            end
            return charKey, ""
        end
    end
    return key, ""
end

-- Apply active/inactive visual state to a button widget set
local function ApplyActiveState(widgets, isActive)
    local iconTex = widgets.iconTex
    if not iconTex then return end
    if isActive then
        iconTex:SetDesaturated(false)
        iconTex:SetVertexColor(1, 1, 1, 1)
    else
        iconTex:SetDesaturated(INACTIVE_SAT)
        iconTex:SetVertexColor(INACTIVE_V, INACTIVE_V, INACTIVE_V, 1)
    end
    if widgets.activeTex then
        if isActive then widgets.activeTex:Show() else widgets.activeTex:Hide() end
    end
end

--------------------------------------------------------------------------------
-- Build ordered slot key list from DB state + available height
--------------------------------------------------------------------------------
local function GetVisibleKeys(availH)
    local db = BigNoteBoxDB
    if not db then return { "all", "global" } end

    local _, _, _, _, _, _, step = GetLayoutVars()

    -- Fixed slots
    local keys = { "all", "global" }
    local slotsUsed = 2

    -- Collect known chars
    local chars = db.knownChars or {}

    -- Separate pinned (sorted by pinnedOrder) and unpinned (sorted by lastSeen desc)
    local pinned, recent = {}, {}
    for charKey, rec in pairs(chars) do
        if not rec.slotHidden then
            if rec.slotPinned then
                pinned[#pinned + 1] = { key = "char:" .. charKey, rec = rec }
            else
                recent[#recent + 1] = { key = "char:" .. charKey, rec = rec }
            end
        end
    end

    table.sort(pinned, function(a, b)
        local ao = a.rec.pinnedOrder or 99
        local bo = b.rec.pinnedOrder or 99
        return ao < bo
    end)
    table.sort(recent, function(a, b)
        return (a.rec.lastSeen or 0) > (b.rec.lastSeen or 0)
    end)

    -- Cap pinned at MAX_PINNED
    for i = 1, math.min(#pinned, MAX_PINNED) do
        keys[#keys + 1] = pinned[i].key
        slotsUsed = slotsUsed + 1
    end

    -- Fit as many recent as available height allows
    local maxTotal = math.floor(availH / step)
    for _, r in ipairs(recent) do
        if slotsUsed >= maxTotal then break end
        keys[#keys + 1] = r.key
        slotsUsed = slotsUsed + 1
    end

    return keys
end

--------------------------------------------------------------------------------
-- Get or create a pooled button widget at a given pool index
--------------------------------------------------------------------------------
-- Returns the TexCoord values for sb-border / sb-active based on sidebar side.
-- The textures are designed as horizontal artwork that must be rotated to run
-- vertically. WoW SetTexCoord(ULx,ULy, URx,URy, LLx,LLy, LRx,LRy).
-- All 8 texture orientations for reference (ULx,ULy, URx,URy, LLx,LLy, LRx,LRy):
--   0   normal:            0,0, 1,0, 0,1, 1,1
--   1   H-flip:            1,0, 0,0, 1,1, 0,1
--   2   V-flip:            0,1, 1,1, 0,0, 1,0
--   3   180:               1,1, 0,1, 1,0, 0,0
--   4   90 CW:             0,1, 0,0, 1,1, 1,0
--   5   90 CW  + H-flip:   0,0, 0,1, 1,0, 1,1
--   6   90 CCW:            1,0, 1,1, 0,0, 0,1
--   7   90 CCW + H-flip:   1,1, 1,0, 0,1, 0,0
-- Current right=6, left=7. Rotate both 90 degrees further → right=4, left=3.
local function SidebarTexCoord()
    local db = BigNoteBoxDB
    if db and db.sidebarSide == "left" then
        return 1,0, 1,1, 0,0, 0,1   -- orientation 6: 90 CCW
    end
    return 0,1, 0,0, 1,1, 1,0       -- orientation 4: 90 CW
end

local function GetPooledBtn(idx, parent)
    if not _btnPool[idx] then
        -- Button container
        local btn = CreateFrame("Button", nil, parent)
        btn:SetSize(BTN_SZ, BTN_SZ)   -- resized in Refresh via ApplyBtnLayout
        btn:EnableMouse(true)

        -- Border texture (always shown, full button size)
        local borderTex = btn:CreateTexture(nil, "OVERLAY")
        borderTex:SetAllPoints(btn)
        borderTex:SetTexture(ASSETS .. "Sidebar\\sb-border")
        -- Tint border to match skin preset in skin mode.
        if BigNoteBoxDB and BigNoteBoxDB.skinMode and BNB.GetSkinPreset then
            local p = BNB.GetSkinPreset()
            local br, bg_, bb = BNB.SkinBorderOf(p)
            borderTex:SetVertexColor(br, bg_, bb, 1)
        end

        -- Icon texture (offset inside border; resized in ApplyBtnLayout)
        local iconTex = btn:CreateTexture(nil, "ARTWORK")
        iconTex:SetSize(ICON_SZ, ICON_SZ)
        iconTex:SetPoint("TOPLEFT", btn, "TOPLEFT", ICON_X, ICON_Y)

        -- Active overlay (sb-active.tga) — shown only on the currently active slot.
        local activeTex = btn:CreateTexture(nil, "OVERLAY", nil, -1)
        activeTex:SetAllPoints(btn)
        activeTex:SetTexture(ASSETS .. "Sidebar\\sb-active")
        activeTex:Hide()
        if BigNoteBoxDB and BigNoteBoxDB.skinMode and BNB.GetSkinPreset then
            local p = BNB.GetSkinPreset()
            local br, bg_, bb = BNB.SkinBorderOf(p)
            activeTex:SetVertexColor(math.min(1, br * ACTIVE_GLOW_MULT), math.min(1, bg_ * ACTIVE_GLOW_MULT), math.min(1, bb * ACTIVE_GLOW_MULT), 1)
        else
            activeTex:SetVertexColor(ACTIVE_R, ACTIVE_G, ACTIVE_B, 1)
        end

        -- Badge fontstring (note count, bottom-right of icon)
        local badge = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        badge:SetPoint("BOTTOMRIGHT", iconTex, "BOTTOMRIGHT", 0, 0)
        badge:SetJustifyH("RIGHT")
        badge:SetTextColor(1, 1, 1)
        badge:Hide()

        _btnPool[idx] = { btn = btn, borderTex = borderTex, iconTex = iconTex, activeTex = activeTex, badge = badge }
    end
    local w = _btnPool[idx]
    w.btn:SetParent(parent)
    return w
end

-- Apply current layout vars (size, icon offset) and texcoords to a pooled button.
-- Called from Refresh() every time so changes without reload work correctly.
local function ApplyBtnLayout(w, sz, isz, ix, iy)
    w.btn:SetSize(sz, sz)
    w.iconTex:SetSize(isz, isz)
    w.iconTex:ClearAllPoints()
    local db = BigNoteBoxDB
    local xOff = (db and db.sidebarSide == "left") and (ix + 5) or ix
    w.iconTex:SetPoint("TOPLEFT", w.btn, "TOPLEFT", xOff, iy)
    local ulx,uly,urx,ury,llx,lly,lrx,lry = SidebarTexCoord()
    w.borderTex:SetTexCoord(ulx,uly,urx,ury,llx,lly,lrx,lry)
    w.activeTex:SetTexCoord(ulx,uly,urx,ury,llx,lly,lrx,lry)
end

--------------------------------------------------------------------------------
-- ── Sidebar icon picker ───────────────────────────────────────────────────────
-- Flat scrollable grid of all Classes/Races/Factions icons, 6 per row.
local _iconPickerFrame = nil
local _ipBtns          = {}

local function BuildIconPickerFrame()
    if _iconPickerFrame then return _iconPickerFrame end

    local COLS    = 6
    local CELL    = 36
    local GPAD    = 4
    local PAD     = 10
    local TITLE_H = 32
    -- Width: 6 cells + 5 inner gaps + 2*pad + 28px scrollbar clearance
    local PW = PAD * 2 + COLS * CELL + (COLS - 1) * GPAD + 28
    local PH = 320

    local skinMode = BigNoteBoxDB and BigNoteBoxDB.skinMode
    local SK_IP_TITLE_H = 28
    local ipTitleH = skinMode and SK_IP_TITLE_H or TITLE_H
    local f

    if skinMode then
        f = BNB.CreateSkinFrame(UIParent, false, "BNBSidebarIconPickerFrame", false)
        _G["BNBSidebarIconPickerFrame"] = f
        f:SetSize(PW, PH)
        f:SetFrameStrata("TOOLTIP")
        f:SetToplevel(true)
        f:SetClampedToScreen(true)
        f:SetMovable(true)
        f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", function(s) s:StartMoving() end)
        f:SetScript("OnDragStop",  function(s) s:StopMovingOrSizing() end)

        local titleBar = BNB.CreateSkinStrip(f, true, false)
        titleBar:SetPoint("TOPLEFT",  f, "TOPLEFT",  0, 0)
        titleBar:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
        titleBar:SetHeight(SK_IP_TITLE_H)
        titleBar:EnableMouse(true)
        titleBar:RegisterForDrag("LeftButton")
        titleBar:SetScript("OnDragStart", function() f:StartMoving() end)
        titleBar:SetScript("OnDragStop",  function() f:StopMovingOrSizing() end)

        local titleLbl = titleBar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        titleLbl:SetPoint("CENTER", titleBar, "CENTER", -12, 0)
        titleLbl:SetTextColor(1, 0.82, 0)
        titleLbl:SetText("Choose Icon")

        local closeBtn = BNB.CreateSkinCloseButton(titleBar, function() f:Hide() end)
        closeBtn:SetPoint("RIGHT", titleBar, "RIGHT", -3, 0)

        f:SetScript("OnShow", function()
            if BNB.ApplyMainWindowSkin then BNB.ApplyMainWindowSkin() end
        end)
    else
        f = CreateFrame("Frame", "BNBSidebarIconPickerFrame", UIParent,
            "ButtonFrameTemplate")
        f:SetSize(PW, PH)
        f:SetFrameStrata("TOOLTIP")
        f:SetToplevel(true)
        f:SetClampedToScreen(true)
        f:SetMovable(true)
        f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", function(s) s:StartMoving() end)
        f:SetScript("OnDragStop",  function(s) s:StopMovingOrSizing() end)
        ButtonFrameTemplate_HidePortrait(f)
        ButtonFrameTemplate_HideButtonBar(f)
        if f.Inset then f.Inset:Hide() end
        f:SetTitle("Choose Icon")
        if f.CloseButton then
            f.CloseButton:SetScript("OnClick", function() f:Hide() end)
        end
    end
    tinsert(UISpecialFrames, "BNBSidebarIconPickerFrame")

    local sf = CreateFrame("ScrollFrame", nil, f, "ScrollFrameTemplate")
    sf:SetPoint("TOPLEFT",     f, "TOPLEFT",      PAD, -(ipTitleH + 6))
    sf:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -28, 8)
    if sf.ScrollBar then sf.ScrollBar:SetAlpha(0)
        sf:HookScript("OnScrollRangeChanged", function(_, _, r)
            sf.ScrollBar:SetAlpha((r or 0) > 1 and 1 or 0)
        end)
    end
    local sc = CreateFrame("Frame", nil, sf)
    sc:SetWidth(COLS * CELL + (COLS - 1) * GPAD)
    sc:SetHeight(1)
    sf:SetScrollChild(sc)

    local icons = SLOT_ICON_LIST
    local rows  = math.max(1, math.ceil(#icons / COLS))
    sc:SetHeight(rows * (CELL + GPAD) + GPAD)

    for i, path in ipairs(icons) do
        local btn = CreateFrame("Button", nil, sc)
        btn:SetSize(CELL, CELL)
        local col = (i - 1) % COLS
        local row = math.floor((i - 1) / COLS)
        btn:SetPoint("TOPLEFT", sc, "TOPLEFT",
            col * (CELL + GPAD),
            -(GPAD + row * (CELL + GPAD)))
        local tex = btn:CreateTexture(nil, "ARTWORK")
        tex:SetAllPoints()
        tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        tex:SetTexture(path)
        local hi = btn:CreateTexture(nil, "HIGHLIGHT")
        hi:SetAllPoints()
        hi:SetColorTexture(1, 1, 1, 0.3)
        btn:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine((path):match("([^\\/]+)$") or "", 1, 1, 1)
            GameTooltip:Show()
        end)
        btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
        btn._path = path
        _ipBtns[i] = btn
    end

    f:Hide()
    _iconPickerFrame = f
    return f
end

local function ShowSidebarIconPicker(charKey, anchorBtn)
    local db  = BigNoteBoxDB
    local rec = db and db.knownChars and db.knownChars[charKey]
    if not rec then return end

    local f = BuildIconPickerFrame()

    for _, btn in ipairs(_ipBtns) do
        local p = btn._path
        btn:SetScript("OnClick", function()
            rec.slotIcon = p
            SB.Refresh()
            if BNB.RefreshNoteList then BNB.RefreshNoteList() end
            f:Hide()
        end)
    end

    f:ClearAllPoints()
    if anchorBtn then
        f:SetPoint("TOPLEFT", anchorBtn, "TOPRIGHT", 4, 0)
    else
        local cx, cy = GetCursorPosition()
        local s = UIParent:GetEffectiveScale()
        f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", cx / s, cy / s + f:GetHeight())
    end
    f:Show()
    f:Raise()
end


-- Right-click context menu for character slots
--------------------------------------------------------------------------------
local function ShowSlotContextMenu(key, btn)
    local db = BigNoteBoxDB
    if not db then return end
    local charKey = key:match("^char:(.+)$")
    if not charKey then return end  -- All and Global have no context menu

    local rec = db.knownChars and db.knownChars[charKey]
    if not rec then return end

    -- Reuse a single DropdownButton parented to UIParent (invisible, 1x1)
    if not SB._ctxDD then
        local dd = CreateFrame("DropdownButton", "BNBSidebarContextDD", UIParent,
            "WowStyle1DropdownTemplate")
        dd:SetSize(1, 1)
        dd:SetAlpha(0)
        dd:SetToplevel(true)
        SB._ctxDD = dd
    end
    local dd = SB._ctxDD
    dd:ClearAllPoints()
    dd:SetPoint("TOPLEFT", btn, "BOTTOMLEFT", 0, 0)

    dd:SetupMenu(function(_, root)
        -- Pin / Unpin
        root:CreateButton(
            rec.slotPinned and "Unpin" or "Pin to top",
            function()
                if rec.slotPinned then
                    rec.slotPinned  = false
                    rec.pinnedOrder = nil
                else
                    local used = {}
                    for _, r in pairs(db.knownChars) do
                        if r.slotPinned and r.pinnedOrder then
                            used[r.pinnedOrder] = true
                        end
                    end
                    local order = 1
                    while used[order] and order <= MAX_PINNED do order = order + 1 end
                    if order > MAX_PINNED then
                        print("|cffffcc00BigNoteBox:|r Maximum of " .. MAX_PINNED
                            .. " pinned characters reached.")
                        return
                    end
                    rec.slotPinned  = true
                    rec.pinnedOrder = order
                end
                SB.Refresh()
            end)

        -- Hide
        root:CreateButton("Hide from sidebar", function()
            rec.slotHidden = true
            if _activeKey == key then SB.SetActive("all") end
            SB.Refresh()
        end)

        -- Change icon
        root:CreateButton("Change icon", function()
            ShowSidebarIconPicker(charKey, btn)
        end)

        -- Reset icon (only shown if a custom icon is set)
        if rec.slotIcon then
            root:CreateButton("Reset icon", function()
                rec.slotIcon = nil
                SB.Refresh()
                if BNB.RefreshNoteList then BNB.RefreshNoteList() end
            end)
        end
    end)

    dd:OpenMenu()
end

--------------------------------------------------------------------------------
-- SetActive — change the active filter
--------------------------------------------------------------------------------
function SB.SetActive(key)
    _activeKey = key
    local db = BigNoteBoxDB
    if db then db.sidebarActiveKey = key end

    -- Update button visuals
    for i, k in ipairs(_builtKeys) do
        local w = _btnPool[i]
        if w then
            ApplyActiveState(w, k == _activeKey)
        end
    end

    -- Trigger note list refresh
    if BNB.RefreshNoteList then BNB.RefreshNoteList() end

    -- Update WYSIWYG copy/move button visibility
    if BNB.SyncSidebarWysiwygBtns then BNB.SyncSidebarWysiwygBtns() end
end

--------------------------------------------------------------------------------
-- UpdateCounts — refresh badge numbers on all visible buttons
--------------------------------------------------------------------------------
function SB.UpdateCounts()
    for i, key in ipairs(_builtKeys) do
        local w = _btnPool[i]
        if w then
            local n = CountForKey(key)
            if n > 0 then
                w.badge:SetText(tostring(n))
                w.badge:Show()
            else
                w.badge:Hide()
            end
        end
    end
end

--------------------------------------------------------------------------------
-- Refresh — rebuild visible slot buttons from current DB state
--------------------------------------------------------------------------------
function SB.Refresh()
    if not _strip then return end

    -- Show/hide strip based on feature toggle and collapsed state
    if not IsEnabled() or (BigNoteBoxDB and BigNoteBoxDB.sidebarCollapsed) then
        _strip:Hide()
        return
    end

    -- Re-anchor the strip based on current side setting
    local db   = BigNoteBoxDB
    local side = (db and db.sidebarSide) or "right"
    local parent = _strip:GetParent()
    _strip:ClearAllPoints()
    _strip:SetWidth(BTN_SZ)  -- will be narrowed below if small icons
    if side == "left" then
        _strip:SetPoint("TOPRIGHT",    parent, "TOPLEFT",    2,  0)
        _strip:SetPoint("BOTTOMRIGHT", parent, "BOTTOMLEFT", 2,  0)
    else
        _strip:SetPoint("TOPLEFT",    parent, "TOPRIGHT",    -2,  0)
        _strip:SetPoint("BOTTOMLEFT", parent, "BOTTOMRIGHT", -2,  0)
    end

    _strip:Show()

    local sz, isz, ix, iy, _, top, step = GetLayoutVars()
    _strip:SetWidth(sz)

    -- Available height = main window height minus phantom slot (title bar area)
    local mainH   = BNB.mainFrame and BNB.mainFrame:GetHeight() or 640
    local availH  = mainH - top
    local keys    = GetVisibleKeys(availH)
    _builtKeys    = keys

    -- Determine where slots start (top or bottom of strip)
    local atTop = not (db and db.sidebarAtBottom == true)

    -- Hide all pooled buttons first
    for _, w in ipairs(_btnPool) do
        w.btn:Hide()
        w.btn:ClearAllPoints()
    end

    -- Position and configure each visible slot
    for i, key in ipairs(keys) do
        local w = GetPooledBtn(i, _strip)
        ApplyBtnLayout(w, sz, isz, ix, iy)

        w.btn:ClearAllPoints()
        if atTop then
            local yOff = -(top + (i - 1) * step)
            w.btn:SetPoint("TOP", _strip, "TOP", 0, yOff)
        else
            local yOff = (top + (i - 1) * step)
            w.btn:SetPoint("BOTTOM", _strip, "BOTTOM", 0, yOff)
        end
        w.btn:Show()

        -- Icon
        local iconPath = IconForKey(key)
        w.iconTex:SetTexture(iconPath)

        -- Active state
        ApplyActiveState(w, key == _activeKey)

        -- Badge
        local n = CountForKey(key)
        if n > 0 then
            w.badge:SetText(tostring(n))
            w.badge:Show()
        else
            w.badge:Hide()
        end

        -- Tooltip
        local slotKey = key  -- capture for closure
        w.btn:SetScript("OnEnter", function(self)
            local title, sub = TooltipForKey(slotKey)
            GameTooltip:SetOwner(self, "ANCHOR_LEFT")
            GameTooltip:AddLine(title, 1, 1, 1)
            if sub and sub ~= "" then
                GameTooltip:AddLine(sub, 0.8, 0.8, 0.8, true)
            end
            local cnt = CountForKey(slotKey)
            if cnt > 0 then
                GameTooltip:AddLine(cnt .. " note" .. (cnt == 1 and "" or "s"), 0.6, 0.9, 0.6)
            end
            GameTooltip:Show()
        end)
        w.btn:SetScript("OnLeave", function() GameTooltip:Hide() end)

        -- Click handlers
        w.btn:SetScript("OnClick", function(self, mouseBtn)
            if mouseBtn == "RightButton" then
                ShowSlotContextMenu(slotKey, self)
            else
                SB.SetActive(slotKey)
            end
        end)
        w.btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    end

    -- If active key is no longer in the visible list, reset to "all"
    local activeVisible = false
    for _, k in ipairs(keys) do
        if k == _activeKey then activeVisible = true; break end
    end
    if not activeVisible then
        SB.SetActive("all")
    end
end

--------------------------------------------------------------------------------
-- Build — called once from CreateMainWindow
--------------------------------------------------------------------------------
-- Toggle the sidebar visibility without affecting the feature-enabled setting.
-- Called by the topbar sidebar button.
function SB.ToggleCollapsed()
    local db = BigNoteBoxDB
    if not db then return end
    db.sidebarCollapsed = not db.sidebarCollapsed
    SB.Refresh()
    if BNB.RefreshSidebarToggleBtn then BNB.RefreshSidebarToggleBtn() end
end

function SB.Build(parent)
    if _strip then return end

    -- The strip is a child of mainFrame. Initial anchor is placeholder;
    -- SB.Refresh() re-anchors based on db.sidebarSide every time it runs.
    _strip = CreateFrame("Frame", "BigNoteBoxSidebarStrip", parent)
    _strip:SetWidth(BTN_SZ)
    _strip:SetPoint("TOPLEFT",    parent, "TOPRIGHT",    -2,  0)
    _strip:SetPoint("BOTTOMLEFT", parent, "BOTTOMRIGHT", -2,  0)
    -- Initially hidden — Refresh() will show if enabled
    _strip:Hide()

    -- Track parent height changes to recalculate slot visibility
    parent:HookScript("OnSizeChanged", function()
        -- Defer one tick so GetHeight() returns the settled value
        C_Timer.After(0, function()
            if IsEnabled() then SB.Refresh() end
        end)
    end)

    -- When the main window is raised (clicked/dragged), companion windows
    -- (preview, RefBox, etc.) must be re-raised so the sidebar strip —
    -- which is a child of mainFrame — does not visually overlap them.
    local function RaiseCompanions()
        if not _strip or not _strip:IsShown() then return end
        local lvl = parent:GetFrameLevel() + 10
        local companions = {
            _G["BigNoteBoxRichPreviewFrame"],
            _G["BigNoteBoxReferenceBoxFrame"],
        }
        for _, cf in ipairs(companions) do
            if cf and cf:IsShown() then
                cf:SetFrameLevel(lvl)
            end
        end
    end
    parent:HookScript("OnMouseDown", RaiseCompanions)

    -- Register a live-refresh for sidebar button borders so they track the
    -- current preset and brightness. ApplyMainWindowSkin iterates the
    -- RegisterSkinButton list on preset / brightness change; this callback
    -- walks the pool and re-tints each existing border texture.
    if BNB.RegisterSkinButton then
        BNB.RegisterSkinButton(function()
            local skinOn = BigNoteBoxDB and BigNoteBoxDB.skinMode
            local p = skinOn and BNB.GetSkinPreset and BNB.GetSkinPreset()
            local br, bg_, bb
            if p then
                br, bg_, bb = BNB.SkinBorderOf(p)
            else
                br, bg_, bb = ACTIVE_R, ACTIVE_G, ACTIVE_B
            end
            for _, w in pairs(_btnPool) do
                if w then
                    if w.borderTex and w.borderTex.SetVertexColor and skinOn then
                        w.borderTex:SetVertexColor(br, bg_, bb, 1)
                    end
                    if w.activeTex and w.activeTex.SetVertexColor then
                        if skinOn then
                            w.activeTex:SetVertexColor(math.min(1, br * ACTIVE_GLOW_MULT), math.min(1, bg_ * ACTIVE_GLOW_MULT), math.min(1, bb * ACTIVE_GLOW_MULT), 1)
                        else
                            w.activeTex:SetVertexColor(ACTIVE_R, ACTIVE_G, ACTIVE_B, 1)
                        end
                    end
                end
            end
        end)
    end

    SB.Refresh()
end

--------------------------------------------------------------------------------
-- Copy/Move popup
--------------------------------------------------------------------------------
-- Small popup window letting the user pick destination scopes.
-- mode = "copy" or "move". noteID = the note to act on.

local _cmPopup = nil

local function BuildCopyMovePopup()
    if _cmPopup then return _cmPopup end

    local PW, PH_BASE = 260, 280
    local PAD = 12

    local skinMode = BigNoteBoxDB and BigNoteBoxDB.skinMode
    local SK_CM_TITLE_H = 28
    local cmTitleH = skinMode and SK_CM_TITLE_H or 32
    local BTN_H    = 26
    local f

    if skinMode then
        f = BNB.CreateSkinFrame(UIParent, false, "BigNoteBoxCopyMoveFrame", false)
        _G["BigNoteBoxCopyMoveFrame"] = f
        f:SetSize(PW, PH_BASE)
        f:SetFrameStrata("TOOLTIP")
        f:SetToplevel(true)
        f:SetClampedToScreen(true)
        f:SetMovable(true)
        f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", function(s) s:StartMoving() end)
        f:SetScript("OnDragStop",  function(s) s:StopMovingOrSizing() end)

        local titleBar = BNB.CreateSkinStrip(f, true, false)
        titleBar:SetPoint("TOPLEFT",  f, "TOPLEFT",  0, 0)
        titleBar:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
        titleBar:SetHeight(SK_CM_TITLE_H)
        titleBar:EnableMouse(true)
        titleBar:RegisterForDrag("LeftButton")
        titleBar:SetScript("OnDragStart", function() f:StartMoving() end)
        titleBar:SetScript("OnDragStop",  function() f:StopMovingOrSizing() end)

        local titleLbl = titleBar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        titleLbl:SetPoint("CENTER", titleBar, "CENTER", -12, 0)
        titleLbl:SetTextColor(1, 0.82, 0)
        titleLbl:SetText("Copy / Move Note")
        f._titleLbl = titleLbl

        local closeBtn = BNB.CreateSkinCloseButton(titleBar, function() f:Hide() end)
        closeBtn:SetPoint("RIGHT", titleBar, "RIGHT", -3, 0)

        f:SetScript("OnShow", function()
            if BNB.ApplyMainWindowSkin then BNB.ApplyMainWindowSkin() end
        end)
    else
        f = CreateFrame("Frame", "BigNoteBoxCopyMoveFrame", UIParent,
            "ButtonFrameTemplate")
        f:SetSize(PW, PH_BASE)
        f:SetFrameStrata("TOOLTIP")
        f:SetToplevel(true)
        f:SetClampedToScreen(true)
        f:SetMovable(true)
        f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", function(s) s:StartMoving() end)
        f:SetScript("OnDragStop",  function(s) s:StopMovingOrSizing() end)
        ButtonFrameTemplate_HidePortrait(f)
        ButtonFrameTemplate_HideButtonBar(f)
        if f.Inset then f.Inset:Hide() end
        if f.CloseButton then
            f.CloseButton:SetScript("OnClick", function() f:Hide() end)
        end
    end
    tinsert(UISpecialFrames, "BigNoteBoxCopyMoveFrame")

    local sf = CreateFrame("ScrollFrame", nil, f, "ScrollFrameTemplate")
    sf:SetPoint("TOPLEFT",     f, "TOPLEFT",      PAD, -(cmTitleH + 4))
    sf:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT",  -28, BTN_H + PAD + 8)
    if sf.ScrollBar then sf.ScrollBar:SetAlpha(0)
        sf:HookScript("OnScrollRangeChanged", function(_, _, r)
            sf.ScrollBar:SetAlpha((r or 0) > 1 and 1 or 0)
        end)
    end
    local sc = CreateFrame("Frame", nil, sf)
    sc:SetWidth(PW - PAD * 2 - 30)
    sc:SetHeight(1)
    sf:SetScrollChild(sc)
    f._scrollChild = sc
    f._scrollFrame = sf

    local btnW = (PW - PAD * 2 - 4) / 2
    local copyBtn = BNB.CreateButton(nil, f, "Copy", btnW, BTN_H)
    local moveBtn = BNB.CreateButton(nil, f, "Move", btnW, BTN_H)
    copyBtn:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", PAD, 8)
    moveBtn:SetPoint("LEFT", copyBtn, "RIGHT", 4, 0)
    f._copyBtn = copyBtn
    f._moveBtn = moveBtn

    f:Hide()
    _cmPopup = f
    return f
end

function BNB.OpenCopyMovePopup(noteID, mode)
    if not IsEnabled() then return end
    local db  = BigNoteBoxDB
    local ndb = BigNoteBoxNotesDB
    if not db or not ndb or not ndb.notes then return end
    local note = ndb.notes[noteID]
    if not note then return end

    local f = BuildCopyMovePopup()
    if f.SetTitle then
        f:SetTitle("Copy / Move Note")
    elseif f._titleLbl then
        f._titleLbl:SetText("Copy / Move Note")
    end

    local sc = f._scrollChild
    for i = 1, sc._rowCount or 0 do
        local row = sc["_row" .. i]
        if row then row:Hide() end
    end
    sc._rowCount = 0

    local dests = {}
    local noteScope = note.scope or "global"
    if noteScope ~= "global" then
        dests[#dests + 1] = { key = "global", label = "Global Notes" }
    end
    for charKey, rec in pairs(db.knownChars or {}) do
        local slotKey = "char:" .. charKey
        if slotKey ~= noteScope then
            dests[#dests + 1] = { key = slotKey, label = rec.name or charKey }
        end
    end
    table.sort(dests, function(a, b) return a.label < b.label end)

    if #dests == 0 then
        f:Hide()
        BNB:Print("|cffffcc00BigNoteBox:|r No other destinations available.")
        return
    end

    local ROW_H  = 26
    local checks = {}
    for i, dest in ipairs(dests) do
        local row = sc["_row" .. i] or CreateFrame("CheckButton", nil, sc,
            "UICheckButtonTemplate")
        sc["_row" .. i] = row
        row:SetSize(24, 24)
        row:SetPoint("TOPLEFT", sc, "TOPLEFT", -2, -(i - 1) * ROW_H + 2)
        row:SetChecked(false)
        local lbl = row._lbl
        if not lbl then
            lbl = sc:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            lbl:SetPoint("LEFT",  row, "RIGHT",  4, 0)
            lbl:SetPoint("RIGHT", sc,  "RIGHT", -4, 0)
            lbl:SetJustifyH("LEFT"); lbl:SetHeight(ROW_H)
            row._lbl = lbl
        end
        lbl:SetText(dest.label)
        row._destKey = dest.key
        row:Show()
        checks[#checks + 1] = row
    end
    sc._rowCount = #dests
    sc:SetHeight(math.max(#dests * ROW_H, 1))

    local function UpdateButtons()
        local anyChecked = false
        for _, cb in ipairs(checks) do
            if cb:GetChecked() then anyChecked = true; break end
        end
        f._copyBtn:SetEnabled(anyChecked)
        f._moveBtn:SetEnabled(anyChecked)
    end
    f._copyBtn:SetEnabled(false)
    f._moveBtn:SetEnabled(false)
    for _, cb in ipairs(checks) do
        cb:SetScript("OnClick", UpdateButtons)
    end

    local function GetSelected()
        local selected = {}
        for _, cb in ipairs(checks) do
            if cb:GetChecked() then selected[#selected + 1] = cb._destKey end
        end
        return selected
    end

    local function CopyNoteToScope(destScope)
        local newID = BNB.CreateNote(note.title, note.body)
        BNB.UpdateNote(newID, {
            scope          = destScope,
            tags           = note.tags,
            icon           = note.icon,
            titleColor     = note.titleColor,
            fontOverride   = note.fontOverride,
            context        = note.context,
            contextDisplay = note.contextDisplay,
            contextLeave   = note.contextLeave,
            pinned         = note.pinned,
            locked         = note.locked,
            borderOverride = note.borderOverride,
            borderScale    = note.borderScale,
            borderOffset   = note.borderOffset,
            lineHeight     = note.lineHeight,
            waypoint       = note.waypoint,
            wpClearOnLeave = note.wpClearOnLeave,
        })
        if note.favorited then BNB.UpdateNote(newID, { favorited = true }) end
    end

    f._copyBtn:SetScript("OnClick", function()
        local selected = GetSelected()
        if #selected == 0 then return end
        for _, destScope in ipairs(selected) do CopyNoteToScope(destScope) end
        f:Hide(); SB.Refresh()
        if BNB.RefreshNoteList then BNB.RefreshNoteList() end
    end)

    f._moveBtn:SetScript("OnClick", function()
        local selected = GetSelected()
        if #selected == 0 then return end
        BNB.UpdateNote(noteID, { scope = selected[1] })
        for i = 2, #selected do CopyNoteToScope(selected[i]) end
        f:Hide(); SB.Refresh()
        if BNB.RefreshNoteList then BNB.RefreshNoteList() end
    end)

    f:ClearAllPoints()
    local cx, cy = GetCursorPosition()
    local s = UIParent:GetEffectiveScale()
    f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", cx / s, cy / s + f:GetHeight())
    f:Show(); f:Raise()
end

--------------------------------------------------------------------------------
-- Register with ESC chain
-- Register with ESC chain
--------------------------------------------------------------------------------
-- Done via MainWindow.lua UISpecialFrames insertion (see MainWindow changes).
-- Multi-note Copy/Move: called from BNB.CopyMoveMultiSelected in NoteList.lua.
-- Reuses the same popup but operates on a list of noteIDs.
function BNB.OpenCopyMovePopupMulti(noteIDs)
    if not noteIDs or #noteIDs == 0 then return end
    local db  = BigNoteBoxDB
    local ndb = BigNoteBoxNotesDB
    if not db or not ndb or not ndb.notes then return end

    local f = BuildCopyMovePopup()
    local cmTitle = "Copy / Move " .. #noteIDs .. " Note" .. (#noteIDs > 1 and "s" or "")
    if f.SetTitle then
        f:SetTitle(cmTitle)
    elseif f._titleLbl then
        f._titleLbl:SetText(cmTitle)
    end

    -- Rebuild scroll child
    local sc = f._scrollChild
    for i = 1, sc._rowCount or 0 do
        local row = sc["_row" .. i]
        if row then row:Hide() end
    end
    sc._rowCount = 0

    -- Collect all unique scopes across the selected notes
    local scopeSet = {}
    for _, id in ipairs(noteIDs) do
        local note = ndb.notes[id]
        if note then scopeSet[note.scope or "global"] = true end
    end

    -- Build destination list: exclude scopes all selected notes are already in
    local dests = {}
    if not scopeSet["global"] then
        dests[#dests + 1] = { key = "global", label = "Global Notes" }
    end
    for charKey, rec in pairs(db.knownChars or {}) do
        local slotKey = "char:" .. charKey
        if not scopeSet[slotKey] then
            dests[#dests + 1] = { key = slotKey, label = rec.name or charKey }
        end
    end
    table.sort(dests, function(a, b) return a.label < b.label end)

    if #dests == 0 then
        f:Hide()
        BNB:Print("|cffffcc00BigNoteBox:|r No other destinations available.")
        return
    end

    local ROW_H  = 26
    local checks = {}
    for i, dest in ipairs(dests) do
        local row = sc["_row" .. i] or CreateFrame("CheckButton", nil, sc,
            "UICheckButtonTemplate")
        sc["_row" .. i] = row
        row:SetSize(24, 24)
        row:SetPoint("TOPLEFT", sc, "TOPLEFT", -2, -(i - 1) * ROW_H + 2)
        row:SetChecked(false)
        local lbl = row._lbl
        if not lbl then
            lbl = sc:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            lbl:SetPoint("LEFT",  row, "RIGHT",  4, 0)
            lbl:SetPoint("RIGHT", sc,  "RIGHT", -4, 0)
            lbl:SetJustifyH("LEFT"); lbl:SetHeight(ROW_H)
            row._lbl = lbl
        end
        lbl:SetText(dest.label)
        row._destKey = dest.key
        row:Show()
        checks[#checks + 1] = row
    end
    sc._rowCount = #dests
    sc:SetHeight(math.max(#dests * ROW_H, 1))

    local function UpdateButtons()
        local anyChecked = false
        for _, cb in ipairs(checks) do
            if cb:GetChecked() then anyChecked = true; break end
        end
        f._copyBtn:SetEnabled(anyChecked)
        f._moveBtn:SetEnabled(anyChecked)
    end
    f._copyBtn:SetEnabled(false)
    f._moveBtn:SetEnabled(false)
    for _, cb in ipairs(checks) do
        cb:SetScript("OnClick", UpdateButtons)
    end

    local function GetSelected()
        local selected = {}
        for _, cb in ipairs(checks) do
            if cb:GetChecked() then selected[#selected + 1] = cb._destKey end
        end
        return selected
    end

    local function CopyNoteToScope(note, destScope)
        local newID = BNB.CreateNote(note.title, note.body)
        BNB.UpdateNote(newID, {
            scope          = destScope,
            tags           = note.tags,
            icon           = note.icon,
            titleColor     = note.titleColor,
            fontOverride   = note.fontOverride,
            context        = note.context,
            contextDisplay = note.contextDisplay,
            contextLeave   = note.contextLeave,
            pinned         = note.pinned,
            locked         = note.locked,
            borderOverride = note.borderOverride,
            borderScale    = note.borderScale,
            borderOffset   = note.borderOffset,
            lineHeight     = note.lineHeight,
            waypoint       = note.waypoint,
            wpClearOnLeave = note.wpClearOnLeave,
        })
        if note.favorited then BNB.UpdateNote(newID, { favorited = true }) end
    end

    f._copyBtn:SetScript("OnClick", function()
        local selected = GetSelected()
        if #selected == 0 then return end
        for _, id in ipairs(noteIDs) do
            local note = ndb.notes[id]
            if note then
                for _, destScope in ipairs(selected) do
                    CopyNoteToScope(note, destScope)
                end
            end
        end
        f:Hide()
        SB.Refresh()
        if BNB.SetMultiMode  then BNB.SetMultiMode(false) end
        if BNB.RefreshNoteList then BNB.RefreshNoteList() end
    end)

    f._moveBtn:SetScript("OnClick", function()
        local selected = GetSelected()
        if #selected == 0 then return end
        for _, id in ipairs(noteIDs) do
            local note = ndb.notes[id]
            if note then
                BNB.UpdateNote(id, { scope = selected[1] })
                for i = 2, #selected do
                    CopyNoteToScope(note, selected[i])
                end
            end
        end
        f:Hide()
        SB.Refresh()
        if BNB.SetMultiMode  then BNB.SetMultiMode(false) end
        if BNB.RefreshNoteList then BNB.RefreshNoteList() end
    end)

    -- Anchor to mouse
    f:ClearAllPoints()
    local cx, cy = GetCursorPosition()
    local s = UIParent:GetEffectiveScale()
    f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", cx / s, cy / s + f:GetHeight())

    f:Show()
    f:Raise()
end

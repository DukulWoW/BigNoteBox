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
--   BNB.Sidebar.IsEnabled()
--
-- sidebarSide = "top" draws the same slots as long tabs on top of the main
-- window instead (UI/SidebarTabs.lua, ALL-248); it reads the helpers below
-- through SB._kit.

local BNB = BigNoteBox
local L   = BNB.L
BNB.Sidebar = BNB.Sidebar or {}
local SB = BNB.Sidebar

--------------------------------------------------------------------------------
-- Constants
--------------------------------------------------------------------------------
local ASSETS        = "Interface\\AddOns\\BigNoteBox\\Assets\\"
local ICON_PATH     = "Interface\\Icons\\"   -- class icons are the game's own (ALL-238)
local BTN_SZ        = 64     -- button frame size (matches sidebar-border.tga)

-- FOR-15: strip offset against the main window, per client/mode. Forever and
-- Retail normal mode are tuned (Retail left from Dukul's screenshots
-- 2026-10-03: the strip sat 5 units clear of the window border); skin mode
-- uses the defaults in Refresh (left 2, right -2), which look right.
local SIDE_OFFSET = {
    forever_normal = { left = 7, right = -2 },
    retail_normal  = { left = 7, right = -2 },
}

local ICON_SZ       = 48     -- icon texture size: fills the border's inner frame opening (full size)
local ICON_X        = 5     -- icon left offset (inner frame starts at 13px from left)
local ICON_Y        = -8     -- icon top offset  (inner frame starts at 8px from top)
local GAP           = 1      -- gap between slots

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
    local ndb = BNB.NotesDB()
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
        return L["SB_ALL_NOTES"], L["SB_ALL_NOTES_TIP"]
    elseif key == "global" then
        return L["SB_GLOBAL_NOTES"], L["SB_GLOBAL_NOTES_TIP"]
    else
        local charKey = key:match("^char:(.+)$")
        if charKey then
            local db  = BigNoteBoxDB
            local rec = db and db.knownChars and db.knownChars[charKey]
            if rec then
                local title = rec.name or charKey
                local lines = {}
                if rec.level then
                    lines[#lines + 1] = string.format(L["SB_LEVEL_FMT"], rec.level)
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
    -- Active slot always wins over a lingering hover (e.g. clicked while hovered).
    if isActive and widgets.hoverTex then
        widgets.hoverTex:Hide()
    end
end

--------------------------------------------------------------------------------
-- Build ordered slot key list from DB state + available height
--------------------------------------------------------------------------------
-- maxTotal: slot cap (the top tabs pass math.huge and fit by width themselves);
-- nil = as many as availH holds
local function GetVisibleKeys(availH, maxTotal)
    local db = BigNoteBoxDB
    if not db then return { "all", "global" } end

    local _, _, _, _, _, _, step = GetLayoutVars()

    -- Fixed slots
    local keys = { "all", "global" }
    local slotsUsed = 2

    -- Collect known chars
    local chars = db.knownChars or {}

    -- Separate pinned (sorted by pinnedOrder) and unpinned (most recent first:
    -- the later of the last login, lastSeen, and the last pick on the top tabs,
    -- tabPicked, which moves a character to the front, ALL-248)
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
    -- The unpinned order follows db.sidebarSort (ALL-298; nil = newest first);
    -- pinned characters stay in front whatever the order (Dukul, 2026-10-05).
    -- Ties fall back to newest first, then the key, so the order is stable.
    local function Newest(r) return math.max(r.rec.lastSeen or 0, r.rec.tabPicked or 0) end
    local function ByNewest(a, b)
        local at, bt = Newest(a), Newest(b)
        if at ~= bt then return at > bt end
        return a.key < b.key
    end
    local mode = db.sidebarSort
    local cmp = ByNewest
    if mode == "name" then
        for _, r in ipairs(recent) do r.sk = r.key:lower() end
        cmp = function(a, b)
            if a.sk ~= b.sk then return a.sk < b.sk end
            return ByNewest(a, b)
        end
    elseif mode == "class" then
        local names = LOCALIZED_CLASS_NAMES_MALE or {}
        for _, r in ipairs(recent) do
            local cls = r.rec.class
            r.sk = cls and (names[cls] or cls):lower() or "~"
            r.sk2 = r.key:lower()
        end
        cmp = function(a, b)
            if a.sk ~= b.sk then return a.sk < b.sk end
            if a.sk2 ~= b.sk2 then return a.sk2 < b.sk2 end
            return ByNewest(a, b)
        end
    elseif mode == "notes" then
        for _, r in ipairs(recent) do r.sk = CountForKey(r.key) end
        cmp = function(a, b)
            if a.sk ~= b.sk then return a.sk > b.sk end
            return ByNewest(a, b)
        end
    end
    table.sort(recent, cmp)

    -- Cap pinned at MAX_PINNED
    for i = 1, math.min(#pinned, MAX_PINNED) do
        keys[#keys + 1] = pinned[i].key
        slotsUsed = slotsUsed + 1
    end

    -- Fit as many recent as available height allows
    maxTotal = maxTotal or math.floor(availH / step)
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
        borderTex:SetTexture(ASSETS .. (BNB.IsForever and "Sidebar\\sb-border-forever" or "Sidebar\\sb-border"))
        -- Tint border to match skin preset in skin mode.
        if BigNoteBoxDB and BigNoteBoxDB.skinMode and BNB.GetSkinPreset then
            local p = BNB.GetSkinPreset()
            local br, bg_, bb, ba = BNB.SkinBorderOf(p)
            borderTex:SetVertexColor(br, bg_, bb, ba)
        end

        -- Icon texture (offset inside border; resized in ApplyBtnLayout)
        local iconTex = btn:CreateTexture(nil, "ARTWORK")
        iconTex:SetSize(ICON_SZ, ICON_SZ)
        iconTex:SetPoint("TOPLEFT", btn, "TOPLEFT", ICON_X, ICON_Y)

        -- Hover overlay (sb-hover.tga) — shown on mouseover of an inactive slot.
        local hoverTex = btn:CreateTexture(nil, "OVERLAY", nil, -2)
        hoverTex:SetAllPoints(btn)
        hoverTex:SetTexture(ASSETS .. "Sidebar\\sb-hover")
        hoverTex:Hide()

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
        local badge = btn:CreateFontString(nil, "OVERLAY", "BNBFontNormalSmall")
        badge:SetPoint("BOTTOMRIGHT", iconTex, "BOTTOMRIGHT", 0, 0)
        badge:SetJustifyH("RIGHT")
        BNB.SetTextWhite(badge)
        badge:Hide()

        _btnPool[idx] = { btn = btn, borderTex = borderTex, iconTex = iconTex, hoverTex = hoverTex, activeTex = activeTex, badge = badge }
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
    -- Left side: the border is mirrored, so the icon moves right by 5, or by
    -- half that (2) for small icons (Dukul 2026-10-03: 5 put it too far right)
    local xOff = ix
    if db and db.sidebarSide == "left" then xOff = ix + (sz < BTN_SZ and 2 or 5) end
    w.iconTex:SetPoint("TOPLEFT", w.btn, "TOPLEFT", xOff, iy)
    local ulx,uly,urx,ury,llx,lly,lrx,lry = SidebarTexCoord()
    w.borderTex:SetTexCoord(ulx,uly,urx,ury,llx,lly,lrx,lry)
    w.activeTex:SetTexCoord(ulx,uly,urx,ury,llx,lly,lrx,lry)
    w.hoverTex:SetTexCoord(ulx,uly,urx,ury,llx,lly,lrx,lry)
end

--------------------------------------------------------------------------------
-- ── Sidebar icon picker ───────────────────────────────────────────────────────
-- The shared icon picker (UI/IconPicker.lua, ALL-243), every category: opens
-- on the custom icon's category, or Classes while the slot shows its class
-- icon. Use Default goes back to the class icon. Clicking Change icon again
-- for the same character closes it.
local function ShowSidebarIconPicker(charKey)
    local db  = BigNoteBoxDB
    local rec = db and db.knownChars and db.knownChars[charKey]
    if not (rec and BNB.IconPicker) then return end
    BNB.IconPicker.Open("sidebar:" .. charKey, BNB.mainFrame, {
        owner       = "sidebar",
        startSide   = "classes",
        defaultNone = true,
        get = function() return rec.slotIcon end,
        set = function(icon)
            rec.slotIcon = icon
            SB.Refresh()
            if BNB.RefreshNoteList then BNB.RefreshNoteList() end
        end,
    })
end


-- Right-click context menu for character slots
--------------------------------------------------------------------------------
-- The character entries on `root` (a menu or a sub-menu row; the top tabs'
-- "..." menu adds them under each character, ALL-248). Returns false for All /
-- Global or an unknown character, which have no entries.
local function AddSlotMenuEntries(root, key)
    local db = BigNoteBoxDB
    if not db then return false end
    local charKey = key:match("^char:(.+)$")
    if not charKey then return false end  -- All and Global have no context menu

    local rec = db.knownChars and db.knownChars[charKey]
    if not rec then return false end

    do
        -- Pin / Unpin
        root:CreateButton(
            -- The top tabs pin to the front, not the top (ALL-248)
            rec.slotPinned and L["SB_UNPIN"] or L[db.sidebarSide == "top" and "SB_PIN_TO_FRONT" or "SB_PIN_TO_TOP"],
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
                        print(string.format(L["SB_MAX_PINNED_FMT"], MAX_PINNED))
                        return
                    end
                    rec.slotPinned  = true
                    rec.pinnedOrder = order
                end
                SB.Refresh()
            end)

        -- Hide
        root:CreateButton(L["SB_HIDE_FROM_SIDEBAR"], function()
            rec.slotHidden = true
            if _activeKey == key then SB.SetActive("all") end
            SB.Refresh()
            -- Settings > Modules > Character sidebar's list, if built (ALL-211)
            if BNB.RefreshHiddenCharList then BNB.RefreshHiddenCharList() end
        end)

        -- Change icon
        root:CreateButton(L["SB_CHANGE_ICON"], function()
            ShowSidebarIconPicker(charKey)
        end)

        -- Reset icon (only shown if a custom icon is set)
        if rec.slotIcon then
            root:CreateButton(L["SB_RESET_ICON"], function()
                rec.slotIcon = nil
                SB.Refresh()
                if BNB.RefreshNoteList then BNB.RefreshNoteList() end
            end)
        end

        -- Remove (ALL-249): asks where the notes go; never the character you are on
        if charKey ~= BNB.currentChar and BNB.CharacterRemove then
            root:CreateButton(L["SB_REMOVE_CHAR"], function()
                BNB.CharacterRemove.Open(charKey)
            end, { danger = true })
        end
    end
    return true
end

local function ShowSlotContextMenu(key, btn)
    local ck = key:match("^char:(.+)$")
    local db = BigNoteBoxDB
    if not (ck and db and db.knownChars and db.knownChars[ck]) then return end
    BNB.ContextMenu.Open(btn, function(root)   -- ALL-148
        AddSlotMenuEntries(root, key)
    end)
end

-- Shared with the top tabs (UI/SidebarTabs.lua, ALL-248)
SB._kit = {
    CountForKey = CountForKey, TooltipForKey = TooltipForKey,
    GetVisibleKeys = GetVisibleKeys, ShowSlotContextMenu = ShowSlotContextMenu,
    AddSlotMenuEntries = AddSlotMenuEntries,
}

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
    if SB.PaintTop then SB.PaintTop() end

    -- Trigger note list refresh
    if BNB.RefreshNoteList then BNB.RefreshNoteList() end

    -- Update WYSIWYG copy/move button visibility
    if BNB.SyncSidebarWysiwygBtns then BNB.SyncSidebarWysiwygBtns() end
end


--------------------------------------------------------------------------------
-- Refresh — rebuild visible slot buttons from current DB state
--------------------------------------------------------------------------------
-- If active key is no longer in the visible list, reset to "all"
local function EnsureActiveVisible(keys)
    for _, k in ipairs(keys) do
        if k == _activeKey then return end
    end
    SB.SetActive("all")
end

function SB.Refresh()
    if not _strip then return end

    -- Show/hide strip based on feature toggle and collapsed state
    if not IsEnabled() or (BigNoteBoxDB and BigNoteBoxDB.sidebarCollapsed) then
        _strip:Hide()
        if SB.HideTop then SB.HideTop() end
        return
    end

    -- Re-anchor the strip based on current side setting
    local db   = BigNoteBoxDB
    local side = (db and db.sidebarSide) or BNB.DEFAULTS.sidebarSide
    local parent = _strip:GetParent()

    -- Top: long tabs on the main window instead of this strip (ALL-248)
    if side == "top" and SB.RefreshTop then
        _strip:Hide()
        _builtKeys = {}
        EnsureActiveVisible(SB.RefreshTop(parent))
        return
    end
    if SB.HideTop then SB.HideTop() end

    -- FOR-15: Forever normal mode gets its own measured offsets and draws
    -- below the main window so its border overlaps the strip cleanly.
    local normal = not (db and db.skinMode)
    local off = normal and (BNB.IsForever and SIDE_OFFSET.forever_normal or SIDE_OFFSET.retail_normal)
    local forNormal = normal and BNB.IsForever
    local leftOff, rightOff = 2, -2
    if off then
        leftOff, rightOff = off.left, off.right
    end

    _strip:ClearAllPoints()
    _strip:SetWidth(BTN_SZ)  -- will be narrowed below if small icons
    if side == "left" then
        _strip:SetPoint("TOPRIGHT",    parent, "TOPLEFT",    leftOff,  0)
        _strip:SetPoint("BOTTOMRIGHT", parent, "BOTTOMLEFT", leftOff,  0)
    else
        _strip:SetPoint("TOPLEFT",    parent, "TOPRIGHT",    rightOff,  0)
        _strip:SetPoint("BOTTOMLEFT", parent, "BOTTOMRIGHT", rightOff,  0)
    end

    if forNormal and side ~= "left" then
        -- Right side draws below the main window so its border overlaps the
        -- strip: kept in the band just under it by the window stack
        -- (UI/WindowStack.lua, ALL-564), clear of the window behind
        _strip:SetFrameLevel(math.max(0, parent:GetFrameLevel() - 1))
        BNB.StackUnder(parent, _strip)
    else
        BNB.StackUnder(parent, nil)
        _strip:SetFrameLevel(parent:GetFrameLevel() + 1)
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

        -- Tooltip + hover overlay
        local slotKey = key  -- capture for closure
        w.btn:SetScript("OnEnter", function(self)
            if slotKey ~= _activeKey then
                if w.hoverTex then w.hoverTex:Show() end
                if w.iconTex then
                    w.iconTex:SetDesaturated(false)
                    w.iconTex:SetVertexColor(1, 1, 1, 1)
                end
            end

            local title, sub = TooltipForKey(slotKey)
            GameTooltip:SetOwner(self, "ANCHOR_LEFT")
            GameTooltip:AddLine(title, 1, 1, 1)
            if sub and sub ~= "" then
                GameTooltip:AddLine(sub, 0.8, 0.8, 0.8, true)
            end
            local cnt = CountForKey(slotKey)
            if cnt > 0 then
                GameTooltip:AddLine(cnt == 1 and L["SB_NOTE_COUNT_ONE"] or string.format(L["SB_NOTE_COUNT_N_FMT"], cnt), 0.6, 0.9, 0.6)
            end
            GameTooltip:Show()
        end)
        w.btn:SetScript("OnLeave", function()
            if w.hoverTex then w.hoverTex:Hide() end
            if slotKey ~= _activeKey and w.iconTex then
                w.iconTex:SetDesaturated(INACTIVE_SAT)
                w.iconTex:SetVertexColor(INACTIVE_V, INACTIVE_V, INACTIVE_V, 1)
            end
            GameTooltip:Hide()
        end)

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

    EnsureActiveVisible(keys)
end

--------------------------------------------------------------------------------
-- Build — called once from CreateMainWindow
--------------------------------------------------------------------------------
-- Toggle the sidebar visibility without affecting the feature-enabled setting.
-- Called by the top bar menu's sidebar entry (ALL-112).
function SB.ToggleCollapsed()
    local db = BigNoteBoxDB
    if not db then return end
    db.sidebarCollapsed = not db.sidebarCollapsed
    SB.Refresh()
end

function SB.Build(parent)
    if _strip then return end

    -- The strip is a child of mainFrame. Initial anchor is placeholder;
    -- SB.Refresh() re-anchors based on db.sidebarSide every time it runs.
    _strip = CreateFrame("Frame", nil, parent)
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


    -- Register a live-refresh for sidebar button borders so they track the
    -- current preset and brightness. ApplyMainWindowSkin iterates the
    -- RegisterSkinButton list on preset / brightness change; this callback
    -- walks the pool and re-tints each existing border texture.
    if BNB.RegisterSkinButton then
        BNB.RegisterSkinButton(function()
            local skinOn = BigNoteBoxDB and BigNoteBoxDB.skinMode
            local p = skinOn and BNB.GetSkinPreset and BNB.GetSkinPreset()
            local br, bg_, bb, ba
            if p then
                br, bg_, bb, ba = BNB.SkinBorderOf(p)
            else
                br, bg_, bb, ba = ACTIVE_R, ACTIVE_G, ACTIVE_B, 1
            end
            for _, w in pairs(_btnPool) do
                if w then
                    if w.borderTex and w.borderTex.SetVertexColor and skinOn then
                        w.borderTex:SetVertexColor(br, bg_, bb, ba)
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

-- Copy/Move destinations: every character not hidden from the sidebar
-- (ALL-249), the realm added where two share a name. skip(slotKey) -> true
-- leaves one out.
local function AddCharDests(dests, skip)
    local db = BigNoteBoxDB
    local chars, names = {}, {}
    for charKey, rec in pairs(db and db.knownChars or {}) do
        local slotKey = "char:" .. charKey
        if not rec.slotHidden and not skip(slotKey) then
            local name = rec.name or charKey
            chars[#chars + 1] = { key = slotKey, name = name, realm = rec.realm }
            names[name] = (names[name] or 0) + 1
        end
    end
    for _, c in ipairs(chars) do
        local label = c.name
        if names[c.name] > 1 and c.realm and c.realm ~= "" then label = label .. " - " .. c.realm end
        dests[#dests + 1] = { key = c.key, label = label }
    end
end

local function BuildCopyMovePopup()
    if _cmPopup then return _cmPopup end

    local PW, PH_BASE = 260, 320
    local PAD = 12

    local BTN_H = 26
    local f = BNB.CreateToolWindow({   -- shared chrome (CMP-02)
        name = "BigNoteBoxCopyMoveFrame", w = PW, h = PH_BASE,
        title = L["SB_COPY_MOVE_TITLE"], strata = "TOOLTIP",
        toplevel = true, escClose = true,
    })
    local cmTitleH = f._isSkin and BNB.TOOL_SKIN_TITLE_H or 32

    local sf = BNB.CreateScrollFrame(nil, f)
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
    local copyBtn = BNB.CreateButton(nil, f, L["REFBOX_PICKER_COPY"], btnW, BTN_H)
    local moveBtn = BNB.CreateButton(nil, f, L["REFBOX_PICKER_MOVE"], btnW, BTN_H)
    copyBtn:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", PAD, 8)
    moveBtn:SetPoint("LEFT", copyBtn, "RIGHT", 4, 0)
    f._copyBtn = copyBtn
    f._moveBtn = moveBtn

    f:Hide()
    _cmPopup = f
    return f
end

-- ── Rows ─────────────────────────────────────────────────────────────────────
-- Character checkboxes (sc._row1..), then, while there are folders, a Folder
-- part (ALL-510, Dukul 2026-10-19: "Copy / move should also allow to copy /
-- move notes into a folder"): Keep its folder / No folder / each folder, one
-- picked (sc._frow1..). Rows are reused; each label is its row's own child,
-- so it hides with the row: on sc it stayed when the list got shorter, a
-- name with no checkbox (ALL-309)
local CM_ROW_H = 26
local KEEP, NONE = "__keep", "__none"

local function CheckRow(sc, key, y)
    local row = sc[key] or CreateFrame("CheckButton", nil, sc, "UICheckButtonTemplate")
    sc[key] = row
    row:SetSize(24, 24)
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", sc, "TOPLEFT", -2, y + 2)
    row:SetChecked(false)
    if not row._lbl then
        local lbl = row:CreateFontString(nil, "OVERLAY", "BNBFontNormal")
        lbl:SetPoint("LEFT",  row, "RIGHT",  4, 0)
        lbl:SetPoint("RIGHT", sc,  "RIGHT", -4, 0)
        lbl:SetJustifyH("LEFT"); lbl:SetHeight(CM_ROW_H)
        row._lbl = lbl
    end
    row:Show()
    return row
end

local function PartLabel(sc, key, text, y)
    local fs = sc[key]
    if not fs then
        fs = sc:CreateFontString(nil, "OVERLAY", "BNBFontNormalSmall")
        fs:SetJustifyH("LEFT")
        sc[key] = fs
    end
    fs:ClearAllPoints()
    fs:SetPoint("TOPLEFT", sc, "TOPLEFT", 0, y - 4)
    fs:SetText(text)
    BNB.SetHeaderColor(fs)
    fs:Show()
end

-- noteIDs = the notes; dests = { { key = scope, label } }; multi = Select
-- mode, which ends after a copy or move
local function ShowCopyMove(f, noteIDs, dests, multi)
    local ndb = BNB.NotesDB()
    local FD  = BNB.Folders
    local folders = FD and BNB.FoldersEnabled() and FD.List() or {}   -- no folder part while the module is off (ALL-514)
    if #dests == 0 and #folders == 0 then
        f:Hide()
        BNB:Print(L["SB_NO_DESTINATIONS"])
        return
    end

    local sc = f._scrollChild
    for i = 1, sc._rowCount or 0 do
        local row = sc["_row" .. i]
        if row then row:Hide() end
    end
    for i = 1, sc._fRowCount or 0 do
        local row = sc["_frow" .. i]
        if row then row:Hide() end
    end
    if sc._partChars  then sc._partChars:Hide()  end
    if sc._partFolder then sc._partFolder:Hide() end

    local y = 0
    if #folders > 0 and #dests > 0 then
        PartLabel(sc, "_partChars", L["CM_PART_CHARS"], y)
        y = y - 20
    end
    local checks = {}
    for i, dest in ipairs(dests) do
        local row = CheckRow(sc, "_row" .. i, y)
        row._lbl:SetText(dest.label)
        BNB.LabelHit(row, row._lbl)   -- the tooltip and click reach over its label too
        BNB.CheckTip(row, L["SB_COPY_MOVE_DEST_TIP"])
        row._destKey = dest.key
        checks[#checks + 1] = row
        y = y - CM_ROW_H
    end
    sc._rowCount = #dests

    local choices = {}
    if #folders > 0 then
        if #dests > 0 then y = y - 6 end
        PartLabel(sc, "_partFolder", L["CM_PART_FOLDER"], y)
        y = y - 20
        local opts = { { key = KEEP, label = L["CM_FOLDER_KEEP"] },
                       { key = NONE, label = L["FOLDER_CM_NO_FOLDER"] } }
        for _, fo in ipairs(folders) do opts[#opts + 1] = { key = fo.id, label = FD.Text(fo.id) } end
        for i, o in ipairs(opts) do
            local row = CheckRow(sc, "_frow" .. i, y)
            row._lbl:SetText(o.label)
            BNB.LabelHit(row, row._lbl)
            BNB.CheckTip(row, L["CM_FOLDER_TIP"])
            row._folderKey = o.key
            row:SetChecked(o.key == KEEP)
            choices[#choices + 1] = row
            y = y - CM_ROW_H
        end
    end
    sc._fRowCount = #choices
    sc:SetHeight(math.max(-y, 1))

    local function Selected()
        local selected = {}
        for _, cb in ipairs(checks) do
            if cb:GetChecked() then selected[#selected + 1] = cb._destKey end
        end
        return selected
    end
    local function Folder()
        for _, cb in ipairs(choices) do
            if cb:GetChecked() then return cb._folderKey end
        end
        return KEEP
    end
    local function UpdateButtons()
        local any = #Selected() > 0 or Folder() ~= KEEP
        f._copyBtn:SetEnabled(any)
        f._moveBtn:SetEnabled(any)
    end
    for _, cb in ipairs(checks) do cb:SetScript("OnClick", UpdateButtons) end
    for _, cb in ipairs(choices) do
        cb:SetScript("OnClick", function(self)   -- one picked, a click never unpicks
            for _, o in ipairs(choices) do o:SetChecked(o == self) end
            UpdateButtons()
        end)
    end
    UpdateButtons()

    -- The folder part of what a copy or move writes. A copy keeps the
    -- source's folder unless told otherwise (BNB.CopyNote)
    local function WithFolder(fields)
        local fk = Folder()
        if fk == NONE then fields._clear = { "folder" }
        elseif fk ~= KEEP then fields.folder = fk end
        return fields
    end
    local function Finish()
        local fk = Folder()
        if fk ~= KEEP and fk ~= NONE and FD then FD.SetOpen(fk, true) end
        f:Hide()
        SB.Refresh()
        if multi and BNB.SetMultiMode then BNB.SetMultiMode(false) end
    end

    -- Full copy (rich mode, tasks, attachments...): see BNB.CopyNote. No
    -- character ticked = a copy beside the note, in the picked folder
    f._copyBtn:SetScript("OnClick", function()
        local selected = Selected()
        for _, id in ipairs(noteIDs) do
            if ndb.notes[id] then
                if #selected == 0 then
                    BNB.CopyNote(id, WithFolder({}))
                else
                    for _, destScope in ipairs(selected) do
                        BNB.CopyNote(id, WithFolder({ scope = destScope }))
                    end
                end
            end
        end
        Finish()
    end)

    -- No character ticked = only the folder changes (filing, not editing)
    f._moveBtn:SetScript("OnClick", function()
        local selected = Selected()
        local fk = Folder()
        for _, id in ipairs(noteIDs) do
            if ndb.notes[id] then
                if #selected == 0 then
                    if FD then FD.Move({ id }, fk ~= NONE and fk or nil) end
                else
                    BNB.UpdateNote(id, WithFolder({ scope = selected[1] }))
                    for i = 2, #selected do
                        BNB.CopyNote(id, WithFolder({ scope = selected[i] }))
                    end
                end
            end
        end
        Finish()
    end)

    BNB.SeatWindow(f, f._strata)   -- also over Focus mode (a note link's menu, ALL-506)
    f:ClearAllPoints()
    local cx, cy = GetCursorPosition()
    local s = UIParent:GetEffectiveScale()
    f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", cx / s, cy / s)   -- top-left on the pointer (ALL-130); clamped to screen by the builder
    f:Show(); f:Raise()
end

-- Opens with the sidebar off too: Copy/Move is the only way to change a
-- note's scope since ALL-265, and returning here opened nothing (ALL-281)
function BNB.OpenCopyMovePopup(noteID, mode)
    local db  = BigNoteBoxDB
    local ndb = BNB.NotesDB()
    if not db or not ndb or not ndb.notes then return end
    local note = ndb.notes[noteID]
    if not note then return end

    local f = BuildCopyMovePopup()
    f:SetWindowTitle(L["SB_COPY_MOVE_TITLE"])

    local dests = {}
    local noteScope = note.scope or "global"
    if noteScope ~= "global" then
        dests[#dests + 1] = { key = "global", label = L["SB_GLOBAL_NOTES"] }
    end
    AddCharDests(dests, function(slotKey) return slotKey == noteScope end)
    table.sort(dests, function(a, b) return a.label < b.label end)

    ShowCopyMove(f, { noteID }, dests, false)
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
    local ndb = BNB.NotesDB()
    if not db or not ndb or not ndb.notes then return end

    local f = BuildCopyMovePopup()
    local cmTitle = #noteIDs > 1
        and string.format(L["SB_COPY_MOVE_MULTI_N_FMT"], #noteIDs)
        or  string.format(L["SB_COPY_MOVE_MULTI_ONE_FMT"], #noteIDs)
    f:SetWindowTitle(cmTitle)

    -- Collect all unique scopes across the selected notes
    local scopeSet = {}
    for _, id in ipairs(noteIDs) do
        local note = ndb.notes[id]
        if note then scopeSet[note.scope or "global"] = true end
    end

    -- Build destination list: exclude scopes all selected notes are already in
    local dests = {}
    if not scopeSet["global"] then
        dests[#dests + 1] = { key = "global", label = L["SB_GLOBAL_NOTES"] }
    end
    AddCharDests(dests, function(slotKey) return scopeSet[slotKey] end)
    table.sort(dests, function(a, b) return a.label < b.label end)

    ShowCopyMove(f, noteIDs, dests, true)
end

-- A note created, deleted, restored or moved to another character changes
-- the (N) counts, and the "By notes" order (ALL-298), so the strip / tabs are
-- redrawn once per burst (ALL-310: the counts only followed with "By notes")
do
    local function Resort() SB.Refresh() end
    local function Soon() BNB.Debounce("sidebarResort", 0.3, Resort) end
    BNB.RegisterMessage("Sidebar", "NoteCreated", Soon)
    BNB.RegisterMessage("Sidebar", "NoteDeleted", Soon)
    BNB.RegisterMessage("Sidebar", "NoteRestored", Soon)
    BNB.RegisterMessage("Sidebar", "NoteChanged", function(_, _, fields)
        if fields and fields.scope ~= nil then Soon() end
    end)
end

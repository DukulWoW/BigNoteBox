-- BigNoteBox UI/NoteList.lua — Left pane note list
-- Supports a collapsible icon-only mode toggled by the << / >> button.

local BNB = BigNoteBox
local L   = BNB.L

local ENTRY_H      = 52
local ICON_SIZE    = 32
local SEARCH_H     = 28
local NEWBTN_H     = 26
local PAD_L        = 8
local PAD_TOP      = 4
local PAD_BOT      = 4

local ENTRY_H_NORMAL   = 52
local ENTRY_H_COMPACT  = 26
local ENTRY_H_SPACIOUS = 65
local ICON_SIZE_NORMAL   = 32
local ICON_SIZE_COMPACT  = 16
local ICON_SIZE_SPACIOUS = 42
local ENTRY_H    = ENTRY_H_NORMAL
local ICON_SIZE  = ICON_SIZE_NORMAL

-- Collapsed mode width — sized for the largest icon (spacious = 42px) so icons
-- are never clipped regardless of list display mode. Must match COLLAPSED_W in MainWindow.lua.
local COLLAPSED_W  = PAD_L + ICON_SIZE_SPACIOUS + PAD_L + 22 + 2   -- 82px

local DEFAULT_ICON = "Interface\\Icons\\INV_Misc_Note_06"
local ICON_BORDER  = "Interface\\Common\\WhiteIconFrame"

local COL_GOLD   = { 1,    0.82, 0,    1 }
local COL_WHITE  = { 1,    1,    1,    1 }
local COL_GREY   = { 0.58, 0.58, 0.58, 1 }
local COL_SEL_BG = { 1,    0.82, 0,    0.12 }

local listEntries   = {}
BNB._listEntries    = listEntries   -- shared with TagTree.lua
local currentFilter = ""
local currentTagFilter = nil   -- tag string being filtered, or nil
local debounceTimer = nil

-- Expose filter state for TagTree.lua
function BNB.GetCurrentFilter()    return currentFilter    end
function BNB.GetCurrentTagFilter() return currentTagFilter end

-- Drag-reorder state
local _dragNoteID   = nil   -- noteID being dragged
local _dragGhost    = nil   -- semi-transparent overlay frame
local _dragInsertAt = nil   -- target insert index in noteOrder
local _dragTimer    = nil   -- hold-to-drag delay timer

-- Multi-select state
local _multiMode    = false          -- checkbox mode active
local _multiSel     = {}             -- { [noteID]=true }

-- Module-level refs set in BuildNoteList, used by collapse toggle
local _newBtn, _qBtn, _collapseBtn, _searchBar, _sf = nil,nil,nil,nil,nil
local _searchEb = nil   -- the search EditBox, stored for FilterByTag

-- Public: filter note list by a tag (called from NoteEditor tag chip click)
function BNB.FilterByTag(tag)
    if currentTagFilter == tag then
        -- Toggle off
        currentTagFilter = nil
        currentFilter    = ""
    else
        currentTagFilter = tag
        currentFilter    = ""   -- tag filter is separate from text filter
    end
    -- Sync search bar text to show active tag filter
    if _searchEb then
        if currentTagFilter then
            _searchEb._showingPlaceholder = false
            _searchEb:SetText("#" .. currentTagFilter)
            pcall(function() _searchEb:SetTextColor(1, 0.82, 0, 1) end)
        else
            _searchEb:SetText("")
            BNB.AddPlaceholder(_searchEb, L["SEARCH_PLACEHOLDER"], 0.40, 0.40, 0.40)
        end
    end
    BNB.RefreshNoteList()
end

-- ── Apply list display mode ────────────────────────────────────────────────────
-- Three modes: normal (32px icon), compact (16px, no preview), spacious (42px, 3 preview lines)
local function GetListMode()
    local db = BigNoteBoxDB
    local v  = db and db.listEntryHeight or "normal"
    if v == "compact"  then return "compact"
    elseif v == "spacious" then return "spacious"
    else return "normal" end
end

-- Pin/situation overlay size scales proportionally with icon
local function OverlaySize(iconSz)
    return math.max(10, math.floor(iconSz * 0.38))
end

local function ApplyListMode()
    local mode     = GetListMode()
    local compact  = (mode == "compact")
    local spacious = (mode == "spacious")
    if compact then
        ENTRY_H   = ENTRY_H_COMPACT
        ICON_SIZE = ICON_SIZE_COMPACT
    elseif spacious then
        ENTRY_H   = ENTRY_H_SPACIOUS
        ICON_SIZE = ICON_SIZE_SPACIOUS
    else
        ENTRY_H   = ENTRY_H_NORMAL
        ICON_SIZE = ICON_SIZE_NORMAL
    end
    local ovSz     = OverlaySize(ICON_SIZE)
    local textLeft = PAD_L + ICON_SIZE + 10

    for _, btn in ipairs(listEntries) do
        btn:SetHeight(ENTRY_H)
        if btn._icon then
            btn._icon:SetSize(ICON_SIZE, ICON_SIZE)
            if btn._iconBorder then
                btn._iconBorder:SetSize(ICON_SIZE + 2, ICON_SIZE + 2)
            end
            -- Re-anchor icon: vertically centred in all modes
            btn._icon:ClearAllPoints()
            btn._icon:SetPoint("LEFT", btn, "LEFT", PAD_L, 0)
            if btn._iconGlowFrame then
                btn._iconGlowFrame:SetSize(ICON_SIZE, ICON_SIZE)
                btn._iconGlowFrame:ClearAllPoints()
                btn._iconGlowFrame:SetPoint("LEFT", btn, "LEFT", PAD_L, 0)
            end

            if btn._alarmTex then
                btn._alarmTex:SetSize(ovSz, ovSz)
                btn._alarmTex:ClearAllPoints()
                btn._alarmTex:SetPoint("BOTTOMRIGHT", btn._icon, "BOTTOMRIGHT", 2, -2)
            end
            if btn._favTex then
                btn._favTex:SetSize(ovSz, ovSz)
                btn._favTex:ClearAllPoints()
                btn._favTex:SetPoint("TOPLEFT", btn._icon, "TOPLEFT", -2, 2)
            end
            if btn._situTex then
                btn._situTex:SetSize(ovSz, ovSz)
                btn._situTex:ClearAllPoints()
                btn._situTex:SetPoint("TOPRIGHT", btn._icon, "TOPRIGHT", 2, 2)
            end
            if btn._scopeTex then
                btn._scopeTex:SetSize(ovSz, ovSz)
                btn._scopeTex:ClearAllPoints()
                btn._scopeTex:SetPoint("BOTTOMLEFT", btn._icon, "BOTTOMLEFT", -2, -2)
            end
            -- Title offset: align top of text with top of icon so they read as a unit.
            -- For compact mode: vertically centred (no y offset). For normal/spacious:
            -- offset = -(entry height - icon height) / 2 so title starts at icon top.
            local titleY = compact and 0
                or -math.floor((ENTRY_H - ICON_SIZE) / 2)
            if btn._titleLbl then
                btn._titleLbl:ClearAllPoints()
                if compact then
                    btn._titleLbl:SetPoint("LEFT",  btn, "LEFT",  textLeft, 0)
                    btn._titleLbl:SetPoint("RIGHT", btn, "RIGHT", -6, 0)
                else
                    btn._titleLbl:SetPoint("TOPLEFT",  btn, "TOPLEFT",  textLeft, titleY)
                    btn._titleLbl:SetPoint("TOPRIGHT", btn, "TOPRIGHT", -6, titleY)
                end
            end
            if btn._previewLbl then
                if compact then
                    btn._previewLbl:Hide()
                else
                    btn._previewLbl:ClearAllPoints()
                    btn._previewLbl:SetPoint("TOPLEFT",  btn, "TOPLEFT",  textLeft, titleY - 16)
                    btn._previewLbl:SetPoint("TOPRIGHT", btn, "TOPRIGHT", -6, titleY - 16)
                    btn._previewLbl:SetPoint("BOTTOM",   btn, "BOTTOM",    0, 4)
                    btn._previewLbl:SetMaxLines(spacious and 3 or 2)
                    btn._previewLbl:Show()
                end
            end
        end
    end
end
BNB.ApplyListMode = ApplyListMode



--------------------------------------------------------------------------------
-- QUICK NOTE — lowest available gap in the sequence
-- If "Quick Note", "Quick Note 2", "Quick Note 3" exist but "Quick Note 4"
-- was deleted, the next one is "Quick Note 4" — not "Quick Note 5".
-- Rule: base title = "Quick Note" (no number), then 2, 3, 4, …
-- (WoW convention: first is unnumbered, subsequent get a number from 2 up.)
--------------------------------------------------------------------------------
local function GetNextQuickNoteTitle()
    local base = "Quick Note"
    local taken = {}
    for _, note in pairs(BigNoteBoxNotesDB.notes or {}) do
        local t = note.title or ""
        if t == base then
            taken[1] = true
        else
            local n = t:match("^Quick Note (%d+)$")
            if n then taken[tonumber(n)] = true end
        end
    end
    if not taken[1] then return base end
    local i = 2
    while taken[i] do i = i + 1 end
    return base .. " " .. i
end

--------------------------------------------------------------------------------
-- COLLAPSE / EXPAND LIST PANE
-- Stores state in BNB._listCollapsed and BigNoteBoxDB.listCollapsed.
-- Notifies MainWindow to adjust the split position.
--------------------------------------------------------------------------------
function BNB.SetListCollapsed(collapsed)
    BNB._listCollapsed = collapsed
    BigNoteBoxDB.listCollapsed = collapsed

    -- Update collapse button arrow texture
    if _collapseBtn and _collapseBtn._tx then
        _collapseBtn._tx:SetTexture("Interface\\AddOns\\BigNoteBox\\Assets\\" .. (collapsed and "UI\\ui-arrow-right" or "UI\\ui-arrow-left"))
    end

    -- Show/hide expanded-only elements
    if _searchBar then
        if collapsed then _searchBar:Hide() else _searchBar:Show() end
    end
    if BNB._favBtn then
        if collapsed then BNB._favBtn:Hide() else BNB._favBtn:Show() end
    end
    if BNB._taskFilterBtn then
        if collapsed then BNB._taskFilterBtn:Hide() else BNB._taskFilterBtn:Show() end
    end
    if BNB._tagTreeBtn then
        if collapsed then BNB._tagTreeBtn:Hide() else BNB._tagTreeBtn:Show() end
    end
    if BNB._searchOuterClear then
        if collapsed then BNB._searchOuterClear:Hide() else BNB._searchOuterClear:Show() end
    end
    if _newBtn then
        if collapsed then _newBtn:Hide() else _newBtn:Show() end
    end
    if _qBtn then
        if collapsed then _qBtn:Hide() else _qBtn:Show() end
    end

    -- Re-anchor scroll frame:
    --   Expanded: left-pad PAD_L, right -22 for scrollbar, top below search bar
    --   Collapsed: span full pane width, no top offset for search (hidden)
    if _sf then
        _sf:ClearAllPoints()
        local BTNS_H = NEWBTN_H + PAD_BOT + 2
        if collapsed then
            _sf:SetPoint("TOPLEFT",     _sf:GetParent(), "TOPLEFT",     PAD_L, -4)
            _sf:SetPoint("BOTTOMRIGHT", _sf:GetParent(), "BOTTOMRIGHT", -22,   BTNS_H)
        else
            _sf:SetPoint("TOPLEFT",     _sf:GetParent(), "TOPLEFT",     PAD_L, -(SEARCH_H + PAD_TOP + 4))
            _sf:SetPoint("BOTTOMRIGHT", _sf:GetParent(), "BOTTOMRIGHT", -22,   BTNS_H)
        end
    end

    -- Show/hide text labels and adjust icon centering on all entries
    local compact  = (GetListMode() == "compact")
    local entryH   = collapsed and (ICON_SIZE + 12) or ENTRY_H
    for _, btn in ipairs(listEntries) do
        btn:SetHeight(entryH)
        if btn._titleLbl then
            if collapsed then btn._titleLbl:Hide() else btn._titleLbl:Show() end
        end
        if btn._previewLbl then
            if collapsed or compact then btn._previewLbl:Hide() else btn._previewLbl:Show() end
        end
        -- In collapsed mode centre the icon; in expanded restore left anchor
        if btn._icon then
            btn._icon:ClearAllPoints()
            if collapsed then
                btn._icon:SetPoint("CENTER", btn, "CENTER", 0, 0)
            else
                btn._icon:SetPoint("LEFT", btn, "LEFT", PAD_L, 0)
            end
        end
        if btn._iconBorder then
            btn._iconBorder:ClearAllPoints()
            btn._iconBorder:SetPoint("CENTER", btn._icon, "CENTER", 0, 0)
        end
    end

    -- Tell MainWindow to adjust split width and disable/enable splitter
    if BNB._applyListCollapse then
        BNB._applyListCollapse(collapsed, COLLAPSED_W)
    end

    -- Refresh button labels after collapse state change
    if not collapsed and BNB._updateButtonLabels then
        C_Timer.After(0.1, BNB._updateButtonLabels)
    end

    BNB.RefreshNoteList()
end

--------------------------------------------------------------------------------
-- SEARCH BAR  (with # tag autocomplete)
--------------------------------------------------------------------------------
-- Collect all unique tags across all notes
local function GetAllTags()
    local seen, list = {}, {}
    local notes = BigNoteBoxNotesDB and BigNoteBoxNotesDB.notes or {}
    for _, note in pairs(notes) do
        for _, tag in ipairs(note.tags or {}) do
            local lo = tag:lower()
            if not seen[lo] then seen[lo] = true; list[#list + 1] = tag end
        end
    end
    table.sort(list)
    return list
end

local _favFilterActive  = false   -- module-level; reset on window close
local _taskFilterActive = false   -- module-level; show only notes with tasks

local function SetFavFilter(active, favBtn, outerClear)
    _favFilterActive = active
    BNB._favFilterActive = active
    if favBtn then
        favBtn:SetAlpha(active and 1.0 or 0.35)
        pcall(function() favBtn._tx:SetDesaturated(not active) end)
    end
    if BNB._applyOuterClearState then BNB._applyOuterClearState() end
    BNB.RefreshNoteList()
end

local function BuildSearchBar(parent)
    -- Layout (left → right):
    --   [# tagTreeBtn] [bar: search text ... innerX ] [★ favBtn] [outerX]
    -- bar shrinks left to leave room for the tag tree button, and right for fav/reset.
    local OUTER_BTN  = 18   -- size of each outside button (fav, tasks, reset)
    local OUTER_GAP  = 4    -- gap between bar, star, tasks, outerX
    local OUTER_ROOM = OUTER_BTN + OUTER_GAP + OUTER_BTN + OUTER_GAP + OUTER_BTN + OUTER_GAP  -- 66px
    local TREE_BTN   = 18   -- tag tree button size
    local TREE_GAP   = 4    -- gap between tag tree button and bar left edge

    -- ── Tag tree toggle button (left of search bar) ───────────────────────────
    -- Built before bar so we can anchor bar relative to it, but parented to
    -- parent at a raised frame level so it sits above the bar backdrop.
    local ASSETS = "Interface\\AddOns\\BigNoteBox\\Assets\\"
    local treeBtn = CreateFrame("Button", nil, parent)
    treeBtn:SetSize(TREE_BTN, TREE_BTN)
    treeBtn:SetFrameLevel(parent:GetFrameLevel() + 10)
    local treeTx = treeBtn:CreateTexture(nil, "ARTWORK")
    treeTx:SetAllPoints()
    treeTx:SetTexture(ASSETS .. "UI\\ui-treeview")
    treeBtn._tx = treeTx
    local _treeActive = BigNoteBoxDB and BigNoteBoxDB.tagTreeMode or false
    local function ApplyTreeBtnState()
        treeBtn:SetAlpha(_treeActive and 1.0 or 0.35)
        pcall(function() treeTx:SetDesaturated(not _treeActive) end)
    end
    ApplyTreeBtnState()
    treeBtn:SetScript("OnClick", function()
        _treeActive = not _treeActive
        ApplyTreeBtnState()
        if BNB.SetTagTreeMode then BNB.SetTagTreeMode(_treeActive) end
    end)
    treeBtn:SetScript("OnEnter", function(self)
        self:SetAlpha(1.0)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(_treeActive and L["TAGTREE_TOGGLE_TIP_OFF"] or L["TAGTREE_TOGGLE_TIP_ON"], 1, 1, 1)
        GameTooltip:Show()
    end)
    treeBtn:SetScript("OnLeave", function()
        ApplyTreeBtnState()
        GameTooltip:Hide()
    end)
    BNB._tagTreeBtn        = treeBtn
    BNB._applyTreeBtnState = ApplyTreeBtnState
    -- Called by SetTagTreeMode to sync the button visual with a programmatic change
    BNB._setTagTreeBtnActive = function(active)
        _treeActive = active
        ApplyTreeBtnState()
    end

    local bar = BNB.CreateBackdropFrame("Frame", nil, parent)
    bar:SetPoint("TOPLEFT",  parent, "TOPLEFT",  PAD_L + TREE_BTN + TREE_GAP + 2, -2)
    bar:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -(2 + OUTER_ROOM), -2)
    bar:SetHeight(SEARCH_H)

    -- Anchor tree button to left of bar, vertically centred to bar height
    treeBtn:SetPoint("RIGHT", bar, "LEFT", -TREE_GAP, 0)

    -- Search bar backdrop: skin-aware or plain dark
    local function ApplySearchBarSkin()
        local db = BigNoteBoxDB
        if db and db.skinMode and BNB.GetSkinPreset then
            local p = BNB.GetSkinPreset()
            local r = math.min(1, p.r + p.lift * 1.5)
            local g = math.min(1, p.g + p.lift * 1.5)
            local b = math.min(1, p.b + p.lift * 1.5)
            local br, bg_, bb = BNB.SkinBorderOf(p)
            BNB.SetBackdrop(bar, r, g, b, 0.92, br, bg_, bb, 1)
        else
            BNB.SetBackdropDark(bar)
        end
    end
    ApplySearchBarSkin()
    if BigNoteBoxDB and BigNoteBoxDB.skinMode then
        BNB.RegisterSkinBackdrop(ApplySearchBarSkin)
    end

    local eb = CreateFrame("EditBox", nil, bar)
    eb:SetPoint("TOPLEFT",     bar, "TOPLEFT",     6,   0)
    eb:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", -22, 0)
    eb:SetFontObject("GameFontNormal")
    eb:SetAutoFocus(false)
    eb:SetMaxLetters(200)
    BNB.AddPlaceholder(eb, L["SEARCH_PLACEHOLDER"], 0.40, 0.40, 0.40)
    _searchEb = eb

    -- Inner X: resets only the editbox + tag filter (stays inside bar)
    local innerClear = CreateFrame("Button", nil, bar)
    innerClear:SetSize(18, 18)
    innerClear:SetPoint("RIGHT", bar, "RIGHT", -2, 0)
    local iClbl = innerClear:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    iClbl:SetAllPoints(); iClbl:SetText("x"); iClbl:SetTextColor(0.65, 0.65, 0.65)
    innerClear:Hide()
    innerClear:SetScript("OnEnter", function() iClbl:SetTextColor(1, 0.4, 0.4) end)
    innerClear:SetScript("OnLeave", function() iClbl:SetTextColor(0.65, 0.65, 0.65) end)
    innerClear:SetScript("OnClick", function()
        eb:SetText(""); eb._showingPlaceholder = false
        BNB.AddPlaceholder(eb, L["SEARCH_PLACEHOLDER"], 0.40, 0.40, 0.40)
        currentFilter = ""; currentTagFilter = nil
        innerClear:Hide()
        if _tagAC then _tagAC:Hide() end
        BNB.RefreshNoteList()
    end)

    -- ── Favourite filter button (star icon, outside bar) ─────────────────────
    local ASSETS = "Interface\\AddOns\\BigNoteBox\\Assets\\"
    local favBtn = CreateFrame("Button", nil, parent)
    favBtn:SetSize(OUTER_BTN, OUTER_BTN)
    favBtn:SetPoint("LEFT", bar, "RIGHT", OUTER_GAP, 0)
    local favTx = favBtn:CreateTexture(nil, "ARTWORK")
    favTx:SetAllPoints()
    favTx:SetTexture(ASSETS .. "Overlay\\ov-favorite")
    favBtn._tx = favTx
    -- Start inactive
    favBtn:SetAlpha(0.35)
    pcall(function() favTx:SetDesaturated(true) end)
    favBtn:SetScript("OnClick", function()
        SetFavFilter(not _favFilterActive, favBtn, nil)
    end)
    favBtn:SetScript("OnEnter", function(self)
        self:SetAlpha(1.0)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(_favFilterActive and "Show all notes" or "Show favourites only", 1, 1, 1)
        if currentFilter ~= "" then
            GameTooltip:AddLine("Active with current search filter", 0.78, 0.78, 0.78)
        end
        GameTooltip:Show()
    end)
    favBtn:SetScript("OnLeave", function(self)
        self:SetAlpha(_favFilterActive and 1.0 or 0.35)
        GameTooltip:Hide()
    end)
    BNB._favBtn = favBtn   -- stored so MainWindow OnHide and collapse can reset it

    -- ── Task filter button (notes with tasks only) ─────────────────
    local taskFilterBtn = CreateFrame("Button", nil, parent)
    taskFilterBtn:SetSize(OUTER_BTN, OUTER_BTN)
    taskFilterBtn:SetPoint("LEFT", favBtn, "RIGHT", OUTER_GAP, 0)
    local taskFilterTx = taskFilterBtn:CreateTexture(nil, "ARTWORK")
    taskFilterTx:SetAllPoints()
    taskFilterTx:SetTexture(ASSETS .. "UI\\ui-tasks")
    taskFilterBtn._tx = taskFilterTx
    taskFilterBtn:SetAlpha(0.35)
    pcall(function() taskFilterTx:SetDesaturated(true) end)
    local function SetTaskFilter(active)
        _taskFilterActive = active
        BNB._taskFilterActive = active
        taskFilterBtn:SetAlpha(active and 1.0 or 0.35)
        pcall(function() taskFilterTx:SetDesaturated(not active) end)
        if BNB._applyOuterClearState then BNB._applyOuterClearState() end
        BNB.RefreshNoteList()
    end
    taskFilterBtn:SetScript("OnClick", function()
        SetTaskFilter(not _taskFilterActive)
    end)
    taskFilterBtn:SetScript("OnEnter", function(self)
        self:SetAlpha(1.0)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(_taskFilterActive and "Show all notes" or "Show notes with tasks only", 1, 1, 1)
        GameTooltip:Show()
    end)
    taskFilterBtn:SetScript("OnLeave", function(self)
        self:SetAlpha(_taskFilterActive and 1.0 or 0.35)
        GameTooltip:Hide()
    end)
    BNB._taskFilterBtn = taskFilterBtn
    BNB._setTaskFilter = SetTaskFilter

    -- ── Outer reset: resets everything (editbox + tag filter + fav filter) ─────
    local outerClear = CreateFrame("Button", nil, parent)
    outerClear:SetSize(OUTER_BTN, OUTER_BTN)
    outerClear:SetPoint("LEFT", taskFilterBtn, "RIGHT", OUTER_GAP, 0)
    local oTex = outerClear:CreateTexture(nil, "ARTWORK")
    oTex:SetAllPoints()
    oTex:SetTexture("Interface\\AddOns\\BigNoteBox\\Assets\\UI\\ui-reset")

    -- Active (lit) only when something is actually filtering; grey otherwise.
    local function ApplyOuterClearState()
        local active = _favFilterActive or _taskFilterActive or (currentFilter ~= "")
        outerClear:SetAlpha(active and 1.0 or 0.40)
        pcall(function() oTex:SetDesaturated(not active) end)
    end
    ApplyOuterClearState()

    outerClear:SetScript("OnEnter", function(self)
        local active = _favFilterActive or _taskFilterActive or (currentFilter ~= "")
        if active then self:SetAlpha(1.0) end
        pcall(function() oTex:SetDesaturated(false) end)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Reset all filters", 1, 1, 1)
        GameTooltip:Show()
    end)
    outerClear:SetScript("OnLeave", function(self)
        ApplyOuterClearState()
        GameTooltip:Hide()
    end)
    outerClear:SetScript("OnClick", function()
        eb:SetText(""); eb._showingPlaceholder = false
        BNB.AddPlaceholder(eb, L["SEARCH_PLACEHOLDER"], 0.40, 0.40, 0.40)
        currentFilter = ""; currentTagFilter = nil
        innerClear:Hide()
        if _tagAC then _tagAC:Hide() end
        SetFavFilter(false, favBtn, nil)
        if BNB._setTaskFilter then BNB._setTaskFilter(false) end
        ApplyOuterClearState()
        BNB.RefreshNoteList()
    end)

    -- Store for collapse hiding (must be after outerClear is defined)
    BNB._searchOuterClear = outerClear
    BNB._applyOuterClearState = ApplyOuterClearState

    -- Update reset button state whenever search text changes
    eb:HookScript("OnTextChanged", function()
        ApplyOuterClearState()
    end)

    -- ── Tag autocomplete dropdown ─────────────────────────────────────────────
    -- Appears below the search bar when user types "#" + 3 or more characters.
    local _tagAC = CreateFrame("Frame", nil, parent)
    BNB.SetBackdrop(_tagAC, 0.08, 0.08, 0.10, 0.97, 0.40, 0.40, 0.42, 1)
    _tagAC:SetFrameLevel(bar:GetFrameLevel() + 20)
    _tagAC:SetPoint("TOPLEFT",  bar, "BOTTOMLEFT",  0, -2)
    _tagAC:SetPoint("TOPRIGHT", bar, "BOTTOMRIGHT", 0, -2)
    _tagAC:Hide()

    local _tagACRows = {}

    local function HideTagAC()
        _tagAC:Hide()
    end

    local function ShowTagAC(prefix)
        local lower = prefix:lower()
        local allTags = GetAllTags()
        local matches = {}
        for _, tag in ipairs(allTags) do
            if tag:lower():find(lower, 1, true) == 1 then
                matches[#matches + 1] = tag
            end
        end
        if #matches == 0 then HideTagAC(); return end

        local ROW_H_AC = 22
        local maxRows  = math.min(#matches, 6)
        _tagAC:SetHeight(maxRows * ROW_H_AC + 4)

        for i = 1, maxRows do
            if not _tagACRows[i] then
                local row = CreateFrame("Button", nil, _tagAC)
                row:SetHeight(ROW_H_AC)
                row:SetPoint("TOPLEFT",  _tagAC, "TOPLEFT",  4, -2 - (i-1)*ROW_H_AC)
                row:SetPoint("TOPRIGHT", _tagAC, "TOPRIGHT", -4, -2 - (i-1)*ROW_H_AC)
                local rowLbl = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                rowLbl:SetPoint("LEFT", row, "LEFT", 4, 0)
                rowLbl:SetJustifyH("LEFT")
                rowLbl:SetTextColor(1, 0.82, 0, 1)
                row._lbl = rowLbl
                local rowHi = row:CreateTexture(nil, "HIGHLIGHT")
                rowHi:SetAllPoints(); rowHi:SetColorTexture(1, 1, 1, 0.08)
                _tagACRows[i] = row
            end
            local row = _tagACRows[i]
            row:SetPoint("TOPLEFT",  _tagAC, "TOPLEFT",  4, -2 - (i-1)*ROW_H_AC)
            row:SetPoint("TOPRIGHT", _tagAC, "TOPRIGHT", -4, -2 - (i-1)*ROW_H_AC)
            local tag = matches[i]
            row._lbl:SetText("#" .. tag)
            row:SetScript("OnClick", function()
                currentTagFilter = tag
                currentFilter    = ""
                eb._showingPlaceholder = false
                eb:SetText("#" .. tag)
                pcall(function() eb:SetTextColor(1, 0.82, 0, 1) end)
                innerClear:Show()
                HideTagAC()
                BNB.RefreshNoteList()
            end)
            row:Show()
        end
        for i = maxRows + 1, #_tagACRows do _tagACRows[i]:Hide() end
        _tagAC:Show()
    end

    eb:SetScript("OnTextChanged", function(self, userInput)
        if not userInput then return end
        local text = eb._showingPlaceholder and "" or (self:GetText() or "")
        if text ~= "" then innerClear:Show() else innerClear:Hide() end
        if debounceTimer then debounceTimer:Cancel() end

        -- Show tag autocomplete when "#" + 3 or more chars typed (no debounce)
        local rawPrefix = text:match("^#(.*)$")
        if rawPrefix ~= nil and #rawPrefix >= 3 then
            ShowTagAC(rawPrefix)
        else
            HideTagAC()
        end

        debounceTimer = C_Timer.NewTimer(0.15, function()
            local tag = text:match("^#(.+)$")
            if tag and tag ~= "" then
                currentTagFilter = tag
                currentFilter    = ""
                pcall(function() eb:SetTextColor(1, 0.82, 0, 1) end)
            else
                currentTagFilter = nil
                currentFilter    = text
                pcall(function()
                    if not eb._showingPlaceholder then
                        eb:SetTextColor(1, 1, 1, 1)
                    end
                end)
            end
            BNB.RefreshNoteList()
        end)
    end)
    eb:SetScript("OnEscapePressed", function(self)
        if _tagAC:IsShown() then
            HideTagAC()
        else
            self:ClearFocus()
        end
    end)
    eb:SetScript("OnEditFocusLost", function()
        C_Timer.After(0.15, function()
            if _tagAC:IsShown() then HideTagAC() end
        end)
        local text = eb._showingPlaceholder and "" or (eb:GetText() or "")
        if text == "" then
            BNB.AddPlaceholder(eb, L["SEARCH_PLACEHOLDER"], 0.40, 0.40, 0.40)
        end
    end)

    return bar
end

--------------------------------------------------------------------------------
-- RIGHT-CLICK CONTEXT MENU
-- Uses WowStyle1DropdownTemplate (retail Midnight only).
--
-- Menu items:
--   Open / Select       — left-click equivalent
--   Duplicate           — clones title+body+tags into a new note
--   ── divider ──
--   Delete              — shows BNB_DELETE_NOTE popup
--------------------------------------------------------------------------------
local _ctxDropdown = nil   -- reused WowStyle1DropdownTemplate button

local function DuplicateNote(id)
    local src = BNB.GetNote(id)
    if not src then return end
    BNB.SaveCurrentNote()
    local newID = BNB.CreateNote(src.title ~= "" and (src.title .. " (copy)") or "")
    local fields = { body = src.body, tags = src.tags or {} }
    -- Preserve appearance: icon and border settings
    if src.icon             then fields.icon             = src.icon             end
    if src.borderOverride   then fields.borderOverride   = src.borderOverride   end
    if src.borderScale      then fields.borderScale      = src.borderScale      end
    if src.borderOffset     then fields.borderOffset     = src.borderOffset     end
    if src.borderBrightness then fields.borderBrightness = src.borderBrightness end
    BNB.UpdateNote(newID, fields)
    if BNB.RefreshNoteList then BNB.RefreshNoteList() end
    if BNB.SelectNote      then BNB.SelectNote(newID) end
end

local function ShowNoteContextMenu(btn, noteID)
    local note = BNB.GetNote(noteID)
    if not note then return end
    local title = (note.title ~= "") and note.title or L["UNTITLED"]

    -- Shared helpers
    local function DoTrash()
        if BigNoteBoxDB and BigNoteBoxDB.warnBeforeDelete ~= false then
            local popup = StaticPopup_Show("BNB_DELETE_NOTE_TRASH", title)
            if popup then popup.data = noteID end
        else
            if BNB.DeleteNote then BNB.DeleteNote(noteID) end
        end
    end
    local function DoDeletePerm()
        if BigNoteBoxDB and BigNoteBoxDB.warnBeforeDelete ~= false then
            local popup = StaticPopup_Show("BNB_DELETE_NOTE", title)
            if popup then popup.data = noteID end
        else
            if BNB.DeleteNote then BNB.DeleteNote(noteID) end
        end
    end
    local function CopyBody()
        local n = BNB.GetNote(noteID)
        if not n then return end
        local content = (n.title and n.title ~= "" and (n.title .. "\n") or "")
                     .. (n.body or "")
        BNB:Print(L["BTN_COPY_NOTE_CLASSIC"] or "Note selected — press Ctrl+C to copy.")
        if BNB.ShowClipboardHint then BNB.ShowClipboardHint(content) end
    end

    if not _ctxDropdown then
            _ctxDropdown = CreateFrame("DropdownButton", "BNBNoteContextDropdown",
                UIParent, "WowStyle1DropdownTemplate")
            _ctxDropdown:SetSize(1, 1); _ctxDropdown:SetAlpha(0)
        end
        _ctxDropdown:ClearAllPoints()
        _ctxDropdown:SetPoint("TOPLEFT", btn, "TOPRIGHT", 0, 0)

        _ctxDropdown:SetupMenu(function(_, root)
            root:CreateTitle(title)

            -- Open
            root:CreateButton("Open note", function()
                BNB.SaveCurrentNote(); BNB.SelectNote(noteID)
            end)
            root:CreateButton("Open note settings", function()
                if BNB.OpenNoteConfig then BNB.OpenNoteConfig(noteID) end
            end)
            root:CreateButton("Open as sticky note", function()
                if BNB.Sticky and BNB.Sticky.Open then
                    -- Ensure this opens as a normal world sticky.
                    -- Write explicit false so global stickyEscDefault doesn't re-apply.
                    local db = BigNoteBoxDB
                    if db then
                        db.postits = db.postits or {}
                        db.postits[noteID] = db.postits[noteID] or {}
                        db.postits[noteID].cfg = db.postits[noteID].cfg or {}
                        db.postits[noteID].cfg.escOnly = false
                    end
                    if BNB.Sticky.IsOpen(noteID) then BNB.Sticky.Close(noteID) end
                    BNB.Sticky.Open(noteID)
                end
            end)
            root:CreateButton("Open as ESC sticky note", function()
                if BNB.Sticky and BNB.Sticky.Open then
                    -- Force ESC-only mode then open — SN.Open will show the ESC menu.
                    local db = BigNoteBoxDB
                    if db then
                        db.postits = db.postits or {}
                        db.postits[noteID] = db.postits[noteID] or {}
                        db.postits[noteID].cfg = db.postits[noteID].cfg or {}
                        db.postits[noteID].cfg.escOnly = true
                    end
                    -- Close the note first if already open as world sticky, so
                    -- SN.Open rebuilds it with the correct strata.
                    if BNB.Sticky.IsOpen(noteID) then BNB.Sticky.Close(noteID) end
                    BNB.Sticky.Open(noteID)
                end
            end)
            do
                local n3 = BNB.GetNote(noteID)
                local hasAlarm = n3 and n3.alarm ~= nil
                local alarmLabel = hasAlarm and "Edit alarm" or "Create alarm"
                root:CreateButton(alarmLabel, function()
                    if BNB.SelectNote then BNB.SelectNote(noteID) end
                    C_Timer.After(0.05, function()
                        if BNB.AlarmWindow and BNB.AlarmWindow.OpenLeftOfMain then
                            BNB.AlarmWindow.OpenLeftOfMain(noteID)
                        end
                    end)
                end)
                if hasAlarm then
                    root:CreateButton("|cffff4444Remove alarm|r", function()
                        if BNB.Alarm and BNB.Alarm.ClearAlarm then
                            BNB.Alarm.ClearAlarm(noteID)
                        end
                        if BNB.RefreshNoteList then BNB.RefreshNoteList() end
                    end)
                end
            end
            do
                local hasTasks = BNB.Task and BNB.Task.HasTasks(noteID)
                local taskLabel = hasTasks and "Add task" or "Create task"
                root:CreateButton(taskLabel, function()
                    if BNB.SelectNote then BNB.SelectNote(noteID) end
                    C_Timer.After(0.05, function()
                        if not BNB._currentNoteID then return end
                        local taskID = BNB.Task and BNB.Task.AddTask(noteID, "")
                        if taskID then
                            if BNB.OpenReferenceBox then BNB.OpenReferenceBox(noteID) end
                            C_Timer.After(0.05, function()
                                if BNB.FocusTaskEditBox then
                                    BNB.FocusTaskEditBox(taskID)
                                end
                            end)
                        end
                    end)
                end)
            end

            root:CreateDivider()

            -- Pin / Unpin
            local n = BNB.GetNote(noteID)
            if n then
                if n.pinned then
                    root:CreateButton("Unpin from top", function()
                        BNB.UpdateNote(noteID, { pinned = false })
                        if BNB.RefreshNoteList then BNB.RefreshNoteList() end
                    end)
                else
                    root:CreateButton("Pin to top", function()
                        BNB.UpdateNote(noteID, { pinned = true })
                        if BNB.RefreshNoteList then BNB.RefreshNoteList() end
                    end)
                end
                -- Favorite / Unfavorite
                if n.favorited then
                    root:CreateButton("Remove from favorites", function()
                        BNB.UpdateNote(noteID, { _clear = {"favorited"} })
                        if BNB.RefreshNoteList then BNB.RefreshNoteList() end
                    end)
                else
                    root:CreateButton("Add to favorites", function()
                        BNB.UpdateNote(noteID, { favorited = true })
                        if BNB.RefreshNoteList then BNB.RefreshNoteList() end
                    end)
                end
            end

            -- Lock / Unlock
            local n2 = BNB.GetNote(noteID)
            if n2 then
                local isLocked = (n2.locked == true)
                    or (n2.locked == nil and BigNoteBoxDB.lockNotes == true)
                if isLocked then
                    root:CreateButton("Unlock note", function()
                        BNB.UpdateNote(noteID, { locked = false })
                        if BNB.RefreshNoteList    then BNB.RefreshNoteList()    end
                        if BNB.LoadNoteInEditor   then BNB.LoadNoteInEditor(BNB._currentNoteID) end
                        if BNB.RefreshReferenceBox then BNB.RefreshReferenceBox() end
                    end)
                else
                    root:CreateButton("Lock note", function()
                        BNB.UpdateNote(noteID, { locked = true })
                        if BNB.RefreshNoteList    then BNB.RefreshNoteList()    end
                        if BNB.LoadNoteInEditor   then BNB.LoadNoteInEditor(BNB._currentNoteID) end
                        if BNB.RefreshReferenceBox then BNB.RefreshReferenceBox() end
                    end)
                end
            end

            root:CreateButton("Duplicate", function() DuplicateNote(noteID) end)

            -- Copy/Move to character (sidebar feature)
            if BNB.Sidebar and BNB.Sidebar.IsEnabled() then
                root:CreateButton("Copy / Move to...", function()
                    if BNB.OpenCopyMovePopup then
                        BNB.OpenCopyMovePopup(noteID, "copy")
                    end
                end)
            end

            -- Convert rich <-> regular
            if BNB.AdvancedMode then
                local isRich = BNB.AdvancedMode.IsRich(note)
                if isRich then
                    root:CreateButton("Convert to regular note", function()
                        BNB.AdvancedMode.ConvertToPlain(noteID)
                    end)
                else
                    root:CreateButton("Convert to rich note", function()
                        BNB.AdvancedMode.ConvertToRich(noteID)
                    end)
                end
            end

            -- History actions
            root:CreateButton(L["HISTORY_CTX_CREATE"], function()
                if not BNB.HistoryGetSlots then return end
                -- Save unsaved edits first if this is the currently open note
                if BNB._currentNoteID == noteID and BNB._dirty and BNB.SaveCurrentNote then
                    BNB.SaveCurrentNote()
                end
                local slots = BNB.HistoryGetSlots(noteID)
                if slots.manual then
                    StaticPopup_Show("BNB_HISTORY_OVERRIDE_MANUAL", noteID)
                else
                    BNB.HistoryCreateManual(noteID)
                    BNB:Print(L["HISTORY_MANUAL_SAVED"])
                end
            end)
            root:CreateButton(L["HISTORY_CTX_VIEW"], function()
                if BNB.OpenNoteHistoryPanel then
                    BNB.OpenNoteHistoryPanel(noteID)
                end
            end)

            root:CreateDivider()

            -- Share / Export / copy
            root:CreateButton("Share note", function()
                if BNB.OpenShareWindow then BNB.OpenShareWindow(noteID) end
            end)
            root:CreateButton("Export note (JSON)", function()
                if BNB.ExportNoteJSON then BNB.ExportNoteJSON(noteID) end
            end)
            root:CreateButton("Export note (MD)", function()
                if BNB.ExportNoteMD then BNB.ExportNoteMD(noteID) end
            end)
            root:CreateButton("Export note (HTML)", function()
                if BNB.ExportNoteHTML then BNB.ExportNoteHTML(noteID) end
            end)
            root:CreateButton("Copy to clipboard", CopyBody)

            root:CreateDivider()

            -- Trash / delete
            if BNB.TrashEnabled and BNB.TrashEnabled() then
                root:CreateButton("Move to trash", DoTrash)
            end
            root:CreateButton("|cffff4444Delete permanently|r", DoDeletePerm)
        end)
        _ctxDropdown:OpenMenu()
end

--------------------------------------------------------------------------------
-- DRAG-REORDER HELPERS
-- Drag only works when sort=creation (manual order) and list is not filtered.
-- When other sort modes are active the drag handle is hidden.
--------------------------------------------------------------------------------
local function CanDragReorder()
    local db = BigNoteBoxDB
    return (db.sortBy == "custom")
        and (currentFilter == "")
        and (currentTagFilter == nil)
end

local function GetOrCreateDragGhost()
    if _dragGhost then return _dragGhost end
    local g = CreateFrame("Frame", nil, UIParent)
    g:SetFrameStrata("TOOLTIP")
    g:SetSize(200, ENTRY_H_NORMAL)
    BNB.SetBackdrop(g, 0.15, 0.15, 0.20, 0.85, 0.55, 0.55, 0.60, 1)
    local lbl = g:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    lbl:SetPoint("LEFT", g, "LEFT", 8, 0)
    lbl:SetPoint("RIGHT", g, "RIGHT", -8, 0)
    lbl:SetJustifyH("LEFT")
    lbl:SetTextColor(1, 0.82, 0, 1)
    g._lbl = lbl
    g:Hide()
    _dragGhost = g
    return g
end

-- Drop-indicator line (1px horizontal rule shown between entries)
local _dropLine = nil
local function GetOrCreateDropLine()
    if _dropLine then return _dropLine end
    local l = BNB._listScrollChild and
              BNB._listScrollChild:CreateTexture(nil, "OVERLAY") or
              UIParent:CreateTexture(nil, "OVERLAY")
    l:SetHeight(2)
    l:SetColorTexture(1, 0.82, 0, 0.9)
    l:Hide()
    _dropLine = l
    return l
end

local function EndDrag(commit)
    _dragTimer = nil
    local ghost = _dragGhost
    if ghost then ghost:Hide() end
    local dl = _dropLine; if dl then dl:Hide() end

    if commit and _dragNoteID and _dragInsertAt then
        -- Reorder noteOrder: move the dragged ID to _dragInsertAt
        local order = BigNoteBoxNotesDB and BigNoteBoxNotesDB.noteOrder
        if order then
            local fromIdx = nil
            for i, id in ipairs(order) do
                if id == _dragNoteID then fromIdx = i; break end
            end
            if fromIdx then
                table.remove(order, fromIdx)
                -- Adjust insert index after removal
                local insertIdx = _dragInsertAt
                if insertIdx > fromIdx then insertIdx = insertIdx - 1 end
                insertIdx = math.max(1, math.min(#order + 1, insertIdx))
                table.insert(order, insertIdx, _dragNoteID)
                if BNB.RefreshNoteList then BNB.RefreshNoteList() end
            end
        end
    end

    _dragNoteID   = nil
    _dragInsertAt = nil
end

--------------------------------------------------------------------------------
-- MULTI-SELECT HELPERS
--------------------------------------------------------------------------------
local function IsMultiSelected(noteID)
    return _multiMode and _multiSel[noteID] == true
end

local function UpdateMultiActionBtns(n)
    local label = n > 0 and ("(" .. n .. ")") or "(0)"
    local en    = n > 0
    if BNB._multiDeleteBtn then
        BNB._multiDeleteBtn:SetText("Delete " .. label)
        BNB._multiDeleteBtn:SetEnabled(en)
    end
    if BNB._multiCopyMoveBtn then
        BNB._multiCopyMoveBtn:SetText("Copy / Move " .. label)
        BNB._multiCopyMoveBtn:SetEnabled(en)
    end
    if BNB._multiExportBtn then
        BNB._multiExportBtn:SetText("Export " .. label)
        BNB._multiExportBtn:SetEnabled(en)
    end
end

local function ToggleMultiSelect(noteID)
    if _multiSel[noteID] then
        _multiSel[noteID] = nil
    else
        _multiSel[noteID] = true
    end
    if BNB.RefreshNoteList then BNB.RefreshNoteList() end
    local n = 0; for _ in pairs(_multiSel) do n = n + 1 end
    UpdateMultiActionBtns(n)
end

function BNB.SetMultiMode(enabled)
    _multiMode = enabled
    _multiSel  = {}
    local function ShowBtn(btn)
        if btn then btn:SetShown(enabled); btn:SetEnabled(false); end
    end
    ShowBtn(BNB._multiDeleteBtn)
    ShowBtn(BNB._multiCopyMoveBtn)
    ShowBtn(BNB._multiExportBtn)
    if enabled then UpdateMultiActionBtns(0) end
    if BNB._multiSelectAllBtn then
        BNB._multiSelectAllBtn:SetShown(enabled)
    end
    if BNB._multiSelBtn then
        BNB._multiSelBtn:SetText(enabled and "Cancel" or "Select")
    end
    -- Show/hide right-side toolbar icons to avoid overlap with action buttons
    if BNB._setToolbarMultiMode then BNB._setToolbarMultiMode(enabled) end
    if BNB.RefreshNoteList then BNB.RefreshNoteList() end
end

-- Returns an array of currently selected note IDs (for export etc.)
function BNB._multiGetSelected()
    local ids = {}
    for id in pairs(_multiSel) do ids[#ids + 1] = id end
    return ids
end

function BNB.DeleteMultiSelected()
    local ids = {}
    for id in pairs(_multiSel) do ids[#ids+1] = id end
    if #ids == 0 then return end
    local warn = BigNoteBoxDB and BigNoteBoxDB.warnBeforeDelete ~= false
    if BNB.TrashEnabled and BNB.TrashEnabled() then
        if warn then
            local popup = StaticPopup_Show("BNB_DELETE_MULTI_TRASH", tostring(#ids))
            if popup then popup.data = ids end
        else
            for _, id in ipairs(ids) do
                if BNB.DeleteNote then BNB.DeleteNote(id) end
            end
            if BNB.SetMultiMode then BNB.SetMultiMode(false) end
        end
    else
        if warn then
            local popup = StaticPopup_Show("BNB_DELETE_MULTI", tostring(#ids))
            if popup then popup.data = ids end
        else
            for _, id in ipairs(ids) do
                if BNB.DeleteNote then BNB.DeleteNote(id) end
            end
            if BNB.SetMultiMode then BNB.SetMultiMode(false) end
        end
    end
end

function BNB.SelectAll()
    if not _multiMode then return end
    local notes = BNB.GetOrderedNotes(nil, nil, false)
    _multiSel = {}
    for _, note in ipairs(notes) do
        _multiSel[note.id] = true
    end
    UpdateMultiActionBtns(#notes)
    if BNB.RefreshNoteList then BNB.RefreshNoteList() end
end

-- Opens the Copy/Move popup pre-loaded with all selected note IDs.
-- mode is "copy" or "move". The popup handles each ID sequentially.
function BNB.CopyMoveMultiSelected()
    local ids = {}
    for id in pairs(_multiSel) do ids[#ids + 1] = id end
    if #ids == 0 then return end
    if BNB.OpenCopyMovePopupMulti then
        BNB.OpenCopyMovePopupMulti(ids)
    end
end

--------------------------------------------------------------------------------
-- LIST ENTRY
--------------------------------------------------------------------------------
local function CreateListEntry(parent)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetHeight(ENTRY_H)
    btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    local _lastClick, _lastClickID  -- double-click detection state
    local _deselectTimer            -- pending deselect timer handle

    -- Selection highlight: ARTWORK layer so OVERLAY text draws on top of it
    local selBg = btn:CreateTexture(nil, "ARTWORK", nil, 1)
    selBg:SetAllPoints(); selBg:SetColorTexture(unpack(COL_SEL_BG)); selBg:Hide()
    btn._selBg = selBg

    -- Multi-select highlight (blue tint)
    local multiSelBg = btn:CreateTexture(nil, "ARTWORK", nil, 2)
    multiSelBg:SetAllPoints()
    multiSelBg:SetColorTexture(0.20, 0.45, 0.90, 0.18)
    multiSelBg:Hide()
    btn._multiSelBg = multiSelBg

    local hiBg = btn:CreateTexture(nil, "HIGHLIGHT")
    hiBg:SetAllPoints(); hiBg:SetColorTexture(1, 1, 1, 0.05)

    local icon = btn:CreateTexture(nil, "ARTWORK")
    icon:SetSize(ICON_SIZE, ICON_SIZE)
    icon:SetPoint("LEFT", btn, "LEFT", PAD_L, 0)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    btn._icon = icon

    -- Transparent frame over the icon used as the glow target for alarm animations.
    -- Sized to match the icon; re-anchored in ApplyListMode alongside _icon.
    local iconGlowFrame = CreateFrame("Frame", nil, btn)
    iconGlowFrame:SetSize(ICON_SIZE, ICON_SIZE)
    iconGlowFrame:SetPoint("LEFT", btn, "LEFT", PAD_L, 0)
    -- Frame level high enough to render glow above the note border frame
    iconGlowFrame:SetFrameLevel(btn:GetFrameLevel() + 10)
    iconGlowFrame:EnableMouse(false)
    btn._iconGlowFrame = iconGlowFrame

    -- Icon border (hidden by default — toggled by showIconBorders setting)
    local iconBorder = btn:CreateTexture(nil, "OVERLAY")
    iconBorder:SetSize(ICON_SIZE + 2, ICON_SIZE + 2)
    iconBorder:SetPoint("CENTER", icon, "CENTER", 0, 0)
    iconBorder:SetTexture(ICON_BORDER)
    iconBorder:Hide()
    btn._iconBorder = iconBorder

    -- Per-note LSM border sub-frame (frameLevel+2, below overlays)
    btn._borderFrame = nil

    -- Overlay container — sits above the border frame so pin/situ are always on top
    local overlayHost = CreateFrame("Frame", nil, btn)
    overlayHost:SetAllPoints(icon)
    overlayHost:SetFrameLevel(btn:GetFrameLevel() + 4)
    overlayHost:EnableMouse(false)
    btn._overlayHost = overlayHost

    -- Alarm indicator -- bottom-right of icon (replaces pin overlay; pinned notes
    -- already live in their own pinned section so the pin badge is redundant).
    local ovSz = OverlaySize(ICON_SIZE)
    local alarmOverlay = overlayHost:CreateTexture(nil, "OVERLAY", nil, 1)
    alarmOverlay:SetSize(ovSz, ovSz)
    alarmOverlay:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", 2, -2)
    alarmOverlay:SetTexture("Interface\\AddOns\\BigNoteBox\\Assets\\Topbar\\tp-alarm")
    alarmOverlay:Hide()
    btn._alarmTex = alarmOverlay

    -- Favorite star overlay — top-left of icon (opposite corner to pin)
    local favOverlay = overlayHost:CreateTexture(nil, "OVERLAY", nil, 1)
    favOverlay:SetSize(ovSz, ovSz)
    favOverlay:SetPoint("TOPLEFT", icon, "TOPLEFT", -2, 2)
    favOverlay:SetTexture("Interface\\AddOns\\BigNoteBox\\Assets\\Overlay\\ov-favorite")
    favOverlay:Hide()
    btn._favTex = favOverlay

    -- Situation marker — child of overlayHost, always above border frame
    local situOverlay = overlayHost:CreateTexture(nil, "OVERLAY", nil, 1)
    situOverlay:SetSize(ovSz, ovSz)
    situOverlay:SetPoint("TOPRIGHT", icon, "TOPRIGHT", 2, 2)
    situOverlay:SetTexture("Interface\\AddOns\\BigNoteBox\\Assets\\Overlay\\ov-situation")
    situOverlay:Hide()
    btn._situTex = situOverlay

    -- Scope badge — bottom-left of icon; shows the class icon of the owning
    -- character when the note is character-scoped.
    local scopeOverlay = overlayHost:CreateTexture(nil, "OVERLAY", nil, 1)
    scopeOverlay:SetSize(ovSz, ovSz)
    scopeOverlay:SetPoint("BOTTOMLEFT", icon, "BOTTOMLEFT", -2, -2)
    scopeOverlay:SetTexCoord(0, 1, 0, 1)
    scopeOverlay:Hide()
    btn._scopeTex = scopeOverlay

    -- Attachment count badge — small gold number right-middle inside icon.
    -- Right-middle avoids the pin (bottom-right), scope (bottom-left),
    -- favorite (top-left), and situation (top-right) overlays.
    -- Uses a FontString with drop shadow directly on overlayHost.
    -- Width 22px fits two-digit counts (10+) without truncation at font size 9.
    local badgeHost = CreateFrame("Frame", nil, overlayHost)
    badgeHost:SetSize(22, 12)
    badgeHost:SetPoint("RIGHT", icon, "RIGHT", 0, 0)
    badgeHost:SetFrameLevel(overlayHost:GetFrameLevel() + 2)

    local badgeLbl = badgeHost:CreateFontString(nil, "OVERLAY")
    badgeLbl:SetAllPoints()
    badgeLbl:SetFont("Fonts\\FRIZQT__.TTF", 9, "OUTLINE")
    badgeLbl:SetJustifyH("RIGHT")
    badgeLbl:SetJustifyV("MIDDLE")
    badgeLbl:SetTextColor(1, 0.82, 0, 1)
    badgeLbl:SetShadowColor(0, 0, 0, 1)
    badgeLbl:SetShadowOffset(1, -1)
    badgeHost:Hide()
    btn._attBadge    = badgeHost
    btn._attBadgeLbl = badgeLbl

    local textLeft = PAD_L + ICON_SIZE + 10

    -- Lock icon — small lock.tga to the left of the title, shown when note is locked.
    -- 12×12px, sits at the same Y as the title label, 4px right of textLeft.
    local lockIcon = btn:CreateTexture(nil, "OVERLAY")
    lockIcon:SetSize(12, 12)
    lockIcon:SetPoint("TOPLEFT", btn, "TOPLEFT", textLeft, -8)
    lockIcon:SetTexture("Interface\\AddOns\\BigNoteBox\\Assets\\Actionbar\\ab-lock")
    lockIcon:SetAlpha(0.65)
    lockIcon:Hide()
    btn._lockIcon = lockIcon

    -- Task icon: small ui-tasks.tga shown when note has tasks.
    -- Sits to the left of the lock icon (or title if no lock). Shown/hidden in refresh.
    local taskIcon = btn:CreateTexture(nil, "OVERLAY")
    taskIcon:SetSize(11, 11)
    taskIcon:SetPoint("TOPLEFT", btn, "TOPLEFT", textLeft, -8)
    taskIcon:SetTexture("Interface\\AddOns\\BigNoteBox\\Assets\\UI\\ui-tasks")
    taskIcon:SetAlpha(0.7)
    taskIcon:Hide()
    btn._taskIcon = taskIcon

    local titleLbl = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    -- Title left anchor shifts right by 13px per shown prefix icon (task/lock).
    titleLbl:SetPoint("TOPLEFT",  btn, "TOPLEFT",  textLeft, -6)
    titleLbl:SetPoint("TOPRIGHT", btn, "TOPRIGHT", -20, -6)
    titleLbl:SetJustifyH("LEFT")
    titleLbl:SetTextColor(unpack(COL_WHITE))
    titleLbl:SetMaxLines(1)
    titleLbl:SetWordWrap(false)
    btn._titleLbl = titleLbl

    local previewLbl = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    previewLbl:SetPoint("TOPLEFT",  btn, "TOPLEFT",  textLeft, -22)
    previewLbl:SetPoint("TOPRIGHT", btn, "TOPRIGHT", -20, -22)
    previewLbl:SetPoint("BOTTOM",   btn, "BOTTOM",    0,  4)
    previewLbl:SetJustifyH("LEFT")
    previewLbl:SetJustifyV("TOP")
    previewLbl:SetTextColor(unpack(COL_GREY))
    previewLbl:SetMaxLines(2)
    previewLbl:SetWordWrap(true)
    btn._previewLbl = previewLbl

    -- Double-click → open note settings
    btn:SetScript("OnClick", function(self, mouseBtn)
        if mouseBtn == "RightButton" then
            ShowNoteContextMenu(self, self._noteID)
            return
        end

        -- Multi-select mode: toggle checkbox AND still load the note for preview
        if _multiMode then
            ToggleMultiSelect(self._noteID)
            BNB.SaveCurrentNote(); BNB.SelectNote(self._noteID)
            return
        end

        -- Double-click detection (250ms window)
        local now = GetTime()
        if self._noteID == _lastClickID and (now - (_lastClick or 0)) < 0.50 then
            _lastClick, _lastClickID = 0, nil
            -- Cancel any pending deselect from the first click
            if _deselectTimer then
                _deselectTimer:Cancel()
                _deselectTimer = nil
            end
            if BNB.OpenNoteConfig then BNB.OpenNoteConfig(self._noteID) end
            return
        end
        _lastClick   = now
        _lastClickID = self._noteID

        -- Single-click on the already-selected note → deselect after double-click
        -- window expires, so a double-click can cancel it before it fires.
        if BNB._currentNoteID == self._noteID then
            local clickedID = self._noteID
            _deselectTimer = C_Timer.NewTimer(0.26, function()
                _deselectTimer = nil
                -- Guard: note may have changed by the time the timer fires
                if BNB._currentNoteID ~= clickedID then return end
                BNB.SaveCurrentNote()
                BNB._currentNoteID = nil
                if BigNoteBoxDB then BigNoteBoxDB.selectedNoteID = nil end
                if BNB.LoadNoteInEditor then BNB.LoadNoteInEditor(nil) end
                if BNB.RefreshNoteList  then BNB.RefreshNoteList() end
            end)
            return
        end

        BNB.SaveCurrentNote(); BNB.SelectNote(self._noteID)
    end)

    -- Whole-entry hold-to-drag: 150ms hold activates drag mode
    local _holdTimer = nil
    btn:SetScript("OnMouseDown", function(self, mouseBtn)
        if mouseBtn ~= "LeftButton" then return end
        if not CanDragReorder() then return end
        local noteID = self._noteID; if not noteID then return end
        local noteCheck = BNB.GetNote(noteID)
        if noteCheck and noteCheck.pinned then return end  -- pinned notes not draggable
        _holdTimer = C_Timer.NewTimer(0.15, function()
            _holdTimer = nil
            _dragNoteID = noteID
            local note  = BNB.GetNote(noteID)
            local ghost = GetOrCreateDragGhost()
            if ghost._lbl then ghost._lbl:SetText(note and note.title or "") end
            ghost:SetSize(BNB._listScrollFrame and BNB._listScrollFrame:GetWidth() or 200, ENTRY_H)
            local mx, my = GetCursorPosition()
            local sc = UIParent:GetEffectiveScale()
            ghost:ClearAllPoints()
            ghost:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", mx/sc - 10, my/sc + ENTRY_H/2)
            ghost:Show()
            ghost:SetScript("OnUpdate", function()
                if not _dragNoteID then ghost:SetScript("OnUpdate", nil); return end
                local cx, cy = GetCursorPosition()
                local s2 = UIParent:GetEffectiveScale()
                ghost:ClearAllPoints()
                ghost:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", cx/s2 - 10, cy/s2 + ENTRY_H/2)

                local child = BNB._listScrollChild
                if not child then return end
                local childTopY = child:GetTop()
                if not childTopY then return end

                -- flat list in exact noteOrder sequence (noFloat=true, no sort)
                local flatNotes = BNB.GetOrderedNotes("", nil, true)
                local n = #flatNotes
                if n == 0 then return end

                -- Count pinned notes — they sit at the top and are NOT draggable.
                -- Drag only operates on the regular (non-pinned) entries.
                local eH = ENTRY_H
                local pinnedCount = 0
                for _, note in ipairs(flatNotes) do
                    if note.pinned then pinnedCount = pinnedCount + 1 end
                end
                local regularCount = n - pinnedCount
                if regularCount == 0 then return end

                -- Build pixel offsets for the TOP of each regular entry.
                -- Layout (pixels from child top):
                --   [18px — PINNED — header if any pinned]
                --   [pinnedCount * eH  pinned entries]
                --   [8px divider + 18px — Notes (X) — header  (always shown)]
                --   [18px — Notes (X) — header  (no pinned section)]
                --   [regular entries]
                local regularStartY = 18  -- always: "— Notes (X) —" header
                if pinnedCount > 0 then
                    regularStartY = 18 + pinnedCount * eH + 8 + 18
                end

                -- entryTops[i] = pixel offset of the TOP of regular entry i (1-based)
                local entryTops = {}
                for i = 1, regularCount do
                    entryTops[i] = regularStartY + (i - 1) * eH
                end

                -- Snap points sit at MIDPOINTS between entries, plus sentinels at
                -- the very top and very bottom of the regular section.
                -- snapY[k] is the Y where we draw the drop line if insertAt == k.
                --   k = 1  → line above first regular entry  (insertAt = 1)
                --   k = i  → line between entry i-1 and i    (insertAt = i)
                --   k = regularCount+1 → line below last entry
                --
                -- The cursor snaps to slot k when it is closer to the midpoint
                -- between entry k-1 and entry k than to any other midpoint.
                -- Midpoint between entry k-1 and entry k = entryTops[k] - eH/2
                -- (for k=1 the sentinel midpoint is above the first entry).

                -- snapLineY[k] = pixel Y (from child top) where the drop line draws
                local snapLineY = {}
                snapLineY[1] = regularStartY  -- above first entry
                for k = 2, regularCount do
                    snapLineY[k] = entryTops[k]  -- top of entry k = bottom of entry k-1
                end
                snapLineY[regularCount + 1] = regularStartY + regularCount * eH  -- below last

                -- midpoints used for snapping: midpoint[k] decides boundary between
                -- slot k and slot k+1
                -- cursor snaps to slot k if it's between midpoint[k-1] and midpoint[k]
                local function snapSlot(cursorY)
                    -- cursorY in pixels from child top (positive downward)
                    -- slot 1: above midpoint between slot1 and slot2
                    -- slot k: between mid[k-1] and mid[k]
                    local best = 1
                    local bestDist = math.huge
                    for k = 1, regularCount + 1 do
                        local dist = math.abs(cursorY - snapLineY[k])
                        if dist < bestDist then
                            bestDist = dist
                            best     = k
                        end
                    end
                    return best
                end

                local cursorFromTop = childTopY - (cy / s2)
                local slot = snapSlot(cursorFromTop)
                -- _dragInsertAt is an index into the FULL noteOrder, offset by pinnedCount
                _dragInsertAt = pinnedCount + slot

                local dl = GetOrCreateDropLine()
                dl:ClearAllPoints()
                local lineY = -(snapLineY[slot])
                dl:SetPoint("TOPLEFT",  child, "TOPLEFT",  0, lineY)
                dl:SetPoint("TOPRIGHT", child, "TOPRIGHT", 0, lineY)
                dl:Show()
            end)
        end)
    end)
    btn:SetScript("OnMouseUp", function(self, mouseBtn)
        if mouseBtn ~= "LeftButton" then return end
        if _holdTimer then _holdTimer:Cancel(); _holdTimer = nil end
        if _dragGhost then _dragGhost:SetScript("OnUpdate", nil) end
        if _dragNoteID then EndDrag(true) end
    end)

    return btn
end

-- TruncStr is kept for tooltip use only (not for FontString display)
local function TruncStr(s, max)
    if not s or s == "" then return "" end
    s = s:gsub("\n", " "):gsub("%s+", " ")
    if #s <= max then return s end
    return s:sub(1, max - 3) .. "..."
end

BNB._createListEntry = function(parent) return CreateListEntry(parent) end

local function PopulateEntry(btn, note, selected, collapsed)
    btn._noteID = note.id
    local iconPath = (note.icon and note.icon ~= "") and note.icon or DEFAULT_ICON
    btn._icon:SetTexture(iconPath)

    -- Live portrait: if this is a target note and the stored target is currently
    -- targeted, replace the creature-type icon with the actual unit portrait.
    -- SetPortraitTexture renders the live unit face/model into the texture widget.
    -- Falls back silently to the stored iconPath if the unit is not targeted.
    if note.source == "target" and UnitExists("target") then
        local matched = false
        if note.targetNpcID then
            -- NPC match: compare stored creature ID against current target GUID
            local guid = UnitGUID("target")
            local curID = guid and (
                guid:match("^Creature%-0%-%d+%-%d+%-%d+%-(%d+)") or
                guid:match("^Vehicle%-0%-%d+%-%d+%-%d+%-(%d+)") or
                guid:match("^Pet%-0%-%d+%-%d+%-%d+%-(%d+)")
            )
            matched = (curID == note.targetNpcID)
        elseif note.targetPlayerKey then
            -- Player match: compare stored key against current target name+realm
            local name, realm = UnitName("target")
            realm = (realm and realm ~= "") and realm or
                    GetNormalizedRealmName() or ""
            local curKey = "player:" .. (name or "") .. (realm ~= "" and ("-" .. realm) or "")
            matched = (curKey == note.targetPlayerKey)
        end
        if matched then
            pcall(SetPortraitTexture, btn._icon, "target")
        end
    end

    -- Icon border always hidden (user sets per-note border via LSM; WhiteIconFrame removed)
    if btn._iconBorder then btn._iconBorder:Hide() end

    -- Per-note LSM border — rendered on a separate overlay Frame around the icon.
    -- edgeSize controls thickness; the overlay grows outward so the border never
    -- eats into the icon texture.
    local bord = note.borderOverride
    local bordScale = note.borderScale or 100
    local bordOffset = note.borderOffset or 2
    local bordBright = (note.borderBrightness or 100) / 100
    if bord and bord ~= "" then
        local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
        local path = LSM and LSM:Fetch("border", bord)
        if path then
            if not btn._borderFrame then
                local bf = BNB.CreateBackdropFrame("Frame", nil, btn)
                bf:SetFrameLevel(btn:GetFrameLevel() + 2)
                bf:EnableMouse(false)
                btn._borderFrame = bf
            end
            local bf = btn._borderFrame
            local es = math.max(1, math.floor(12 * bordScale / 100 + 0.5))
            bf:ClearAllPoints()
            bf:SetPoint("TOPLEFT",     btn._icon, "TOPLEFT",     -bordOffset,  bordOffset)
            bf:SetPoint("BOTTOMRIGHT", btn._icon, "BOTTOMRIGHT",  bordOffset, -bordOffset)
            pcall(function()
                bf:SetBackdrop({
                    edgeFile = path, edgeSize = es,
                    insets = { left = 0, right = 0, top = 0, bottom = 0 },
                })
                bf:SetBackdropColor(0, 0, 0, 0)
                bf:SetBackdropBorderColor(
                    math.min(1, 0.70 * bordBright),
                    math.min(1, 0.70 * bordBright),
                    math.min(1, 0.75 * bordBright),
                    0.85)
            end)
            bf:Show()
        end
    else
        -- No custom border: show the Blizzard tooltip border as default
        if not btn._borderFrame then
            local bf = BNB.CreateBackdropFrame("Frame", nil, btn)
            bf:SetFrameLevel(btn:GetFrameLevel() + 2)
            bf:EnableMouse(false)
            btn._borderFrame = bf
        end
        local bf = btn._borderFrame
        bf:ClearAllPoints()
        bf:SetPoint("TOPLEFT",     btn._icon, "TOPLEFT",     -2,  2)
        bf:SetPoint("BOTTOMRIGHT", btn._icon, "BOTTOMRIGHT",  2, -2)
        pcall(function()
            bf:SetBackdrop({
                edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                edgeSize = 12,
                insets = { left = 0, right = 0, top = 0, bottom = 0 },
            })
            bf:SetBackdropColor(0, 0, 0, 0)
            bf:SetBackdropBorderColor(0.35, 0.35, 0.38, 0.75)
        end)
        bf:Show()
    end

    -- Multi-select highlight
    if btn._multiSelBg then
        btn._multiSelBg:SetShown(_multiMode and _multiSel[note.id] == true)
    end

    if collapsed then
        btn._icon:SetPoint("CENTER", btn, "CENTER", 0, 0)
    else
        btn._icon:SetPoint("LEFT", btn, "LEFT", PAD_L, 0)
    end

    -- Alarm indicator: colour when pending, desaturated when fired, hidden while actively firing
    if btn._alarmTex then
        local alarm = note.alarm
        if not alarm then
            btn._alarmTex:Hide()
        else
            local active = BNB.Alarm and BNB.Alarm.IsAlarmActive and BNB.Alarm.IsAlarmActive(noteID)
            if active then
                btn._alarmTex:Hide()
            elseif alarm.fired then
                btn._alarmTex:SetDesaturated(true)
                btn._alarmTex:SetVertexColor(0.5, 0.5, 0.5)
                btn._alarmTex:Show()
            else
                btn._alarmTex:SetDesaturated(false)
                btn._alarmTex:SetVertexColor(1, 1, 1)
                btn._alarmTex:Show()
            end
        end
    end

    -- Register/unregister glow target based on whether note has an alarm
    if btn._iconGlowFrame and BNB.Alarm then
        if note.alarm then
            if BNB.Alarm.RegisterGlowTarget then
                BNB.Alarm.RegisterGlowTarget(noteID, btn._iconGlowFrame)
            end
        else
            if BNB.Alarm.UnregisterGlowTarget then
                BNB.Alarm.UnregisterGlowTarget(noteID, btn._iconGlowFrame)
            end
        end
    end

    -- Favorite overlay
    if btn._favTex then
        if note.favorited then btn._favTex:Show() else btn._favTex:Hide() end
    end

    -- Situation marker: show ! on notes that have a context binding
    if btn._situTex then
        if note.context and note.context ~= "" then
            btn._situTex:Show()
        else
            btn._situTex:Hide()
        end
    end

    -- Attachment count badge: gold number at bottom-left of icon
    if btn._attBadge then
        local attCount = note.attachments and #note.attachments or 0
        if attCount > 0 then
            btn._attBadgeLbl:SetText(tostring(attCount))
            btn._attBadge:Show()
        else
            btn._attBadge:Hide()
        end
    end

    -- Lock icon: small lock.tga to the left of the title when note is locked.
    -- Shifts the title label right by 16px to avoid overlap.
    local textLeft = PAD_L + ICON_SIZE + 10
    local isNoteLocked = (note.locked == true)
        or (note.locked == nil and BigNoteBoxDB.lockNotes == true)
    -- Task icon and lock icon: each shifts the title right by 13px.
    local hasTasks = BNB.Task and BNB.Task.HasTasks(note.id) or false
    local showTaskIcon = hasTasks and not collapsed
    local showLockIcon = isNoteLocked and not collapsed
    local iconOffset = textLeft
    if btn._taskIcon then
        if showTaskIcon then
            btn._taskIcon:SetPoint("TOPLEFT", btn, "TOPLEFT", iconOffset, -8)
            btn._taskIcon:Show()
            iconOffset = iconOffset + 13
        else
            btn._taskIcon:Hide()
        end
    end
    if btn._lockIcon then
        if showLockIcon then
            btn._lockIcon:SetPoint("TOPLEFT", btn, "TOPLEFT", iconOffset, -8)
            btn._lockIcon:Show()
            iconOffset = iconOffset + 13
        else
            btn._lockIcon:Hide()
        end
    end
    if btn._titleLbl then
        btn._titleLbl:ClearAllPoints()
        btn._titleLbl:SetPoint("TOPLEFT",  btn, "TOPLEFT",  iconOffset, -6)
        btn._titleLbl:SetPoint("TOPRIGHT", btn, "TOPRIGHT", -20, -6)
    end

    -- Scope badge: class icon of the owning character on character-scoped notes
    if btn._scopeTex then
        local sc = note.scope
        if sc and sc:match("^char:") then
            local iconPath = BNB.Sidebar and BNB.Sidebar.IconForKey
                and BNB.Sidebar.IconForKey(sc)
            if iconPath then
                btn._scopeTex:SetTexture(iconPath)
                btn._scopeTex:SetVertexColor(1, 1, 1)
                btn._scopeTex:Show()
            else
                btn._scopeTex:Hide()
            end
        else
            btn._scopeTex:Hide()
        end
    end

    local mode     = GetListMode()
    local compact  = (mode == "compact")
    local spacious = (mode == "spacious")
    local hasTitle = note.title and note.title ~= ""
    if btn._titleLbl then
        btn._titleLbl:SetText(hasTitle and note.title or L["UNTITLED"])
        if collapsed then btn._titleLbl:Hide() else btn._titleLbl:Show() end
    end
    if btn._previewLbl then
        if collapsed or compact then
            btn._previewLbl:Hide()
        else
            local body = (note.body or ""):match("^%s*(.-)%s*$")
            -- Strip rich note markup tags so preview shows plain text only
            if note.richMode then
                -- For inspect/target notes, skip the first {h1} block (player/target
                -- name) since it duplicates the note title shown above the preview.
                if note.source == "inspect" or note.source == "target" then
                    body = body:gsub("^%s*{h1[^}]*}.-{/h1}%s*", "", 1)
                end
                body = body:gsub("{/?h%d+:?[cr]?}", "")
                body = body:gsub("{/?p:?[cr]?}", "")
                body = body:gsub("{img:[^}]+}", "")
                body = body:gsub("{icon:[^}]+}", "")
                body = body:gsub("{col:%x%x%x%x%x%x}", "")
                body = body:gsub("{/col}", "")
                body = body:gsub("{br}", "")
                body = body:gsub("{link%*[^*}]+%*([^}]*)}", "%1")
                -- Collapse runs of blank lines so they don't eat the line budget
                body = body:gsub("\n%s*\n+", "\n")
                body = body:match("^%s*(.-)%s*$") or body
            end
            btn._previewLbl:SetText(body)
            btn._previewLbl:SetMaxLines(spacious and 3 or 2)
            btn._previewLbl:Show()
        end
    end

    -- Title color logic:
    -- Unselected: use note.titleColor if set, else white (or dim for untitled)
    -- Selected:   use note.titleColor if set (brightened slightly), else gold
    -- The selection background (COL_SEL_BG) is drawn at ARTWORK layer;
    -- text is at OVERLAY, so there is no layer conflict.
    local tc = note.titleColor
    if selected then
        btn._selBg:Show()
        if btn._titleLbl then
            if tc then
                btn._titleLbl:SetTextColor(
                    math.min(1, tc.r * 1.15 + 0.05),
                    math.min(1, tc.g * 1.10 + 0.05),
                    math.min(1, tc.b * 1.10 + 0.05), 1)
            else
                btn._titleLbl:SetTextColor(unpack(COL_GOLD))
            end
        end
    else
        btn._selBg:Hide()
        if btn._titleLbl then
            if tc then
                btn._titleLbl:SetTextColor(tc.r, tc.g, tc.b, 1)
            else
                btn._titleLbl:SetTextColor(
                    hasTitle and 1 or 0.5,
                    hasTitle and 1 or 0.5,
                    hasTitle and 1 or 0.5)
            end
        end
    end
end

--------------------------------------------------------------------------------
-- REFRESH NOTE LIST
--------------------------------------------------------------------------------
-- Expose PopulateEntry for TagTree.lua (must be after PopulateEntry is defined)
function BNB.PopulateListEntry(btn, note, selected, collapsed)
    PopulateEntry(btn, note, selected, collapsed)
end

function BNB.RefreshNoteList()
    if not BNB._listScrollChild then return end
    -- Delegate to tag tree when that mode is active
    if BigNoteBoxDB and BigNoteBoxDB.tagTreeMode and BNB.RefreshTagTree then
        BNB.RefreshTagTree()
        return
    end

    ApplyListMode()

    local notes    = BNB.GetOrderedNotes(currentFilter, currentTagFilter)
    local selID    = BNB._currentNoteID
    local child    = BNB._listScrollChild
    local collapsed = BNB._listCollapsed
    local entryH   = collapsed and (ICON_SIZE + 12) or ENTRY_H
    local totalH   = 0

    -- Always split pinned vs regular. In non-custom modes pinned notes are
    -- sorted A-Z among themselves; regular notes follow the active sort.
    local isCustom = (BigNoteBoxDB and BigNoteBoxDB.sortBy == "custom")
    local pinned, regular = {}, {}
    for _, note in ipairs(notes) do
        if note.pinned then pinned[#pinned + 1] = note
        else                regular[#regular + 1] = note end
    end
    -- Pinned notes always A-Z by title regardless of sort mode
    if not isCustom and #pinned > 1 then
        local LAST = "\255"
        table.sort(pinned, function(a, b)
            local at = (a.title and a.title ~= "") and a.title:lower() or LAST
            local bt = (b.title and b.title ~= "") and b.title:lower() or LAST
            if at ~= bt then return at < bt end
            return (a.id or "") < (b.id or "")
        end)
    end

    for _, btn in ipairs(listEntries) do btn:Hide(); btn:ClearAllPoints() end

    -- ── Section header helper ────────────────────────────────────────────────
    -- Reuse pre-built header FontStrings stored on child to avoid leaking.
    local function GetSectionHeader(key, labelText)
        if not child[key] then
            local hdr = child:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            hdr:SetHeight(16)
            hdr:SetJustifyH("LEFT")
            hdr:SetTextColor(0.55, 0.55, 0.55)
            child[key] = hdr
        end
        child[key]:SetText(labelText)
        child[key]:ClearAllPoints()
        return child[key]
    end

    -- ── Pinned section ────────────────────────────────────────────────────────
    local entryIdx = 0
    if #pinned > 0 then
        if not collapsed then
            local hdr = GetSectionHeader("_pinnedHdr", "|cffFFD700— PINNED —|r")
            hdr:SetPoint("TOPLEFT",  child, "TOPLEFT",  PAD_L, -totalH)
            hdr:SetPoint("TOPRIGHT", child, "TOPRIGHT", -4,    -totalH)
            hdr:Show()
            totalH = totalH + 18
        else
            if child._pinnedHdr then child._pinnedHdr:Hide() end
        end

        for _, note in ipairs(pinned) do
            entryIdx = entryIdx + 1
            if not listEntries[entryIdx] then
                listEntries[entryIdx] = CreateListEntry(child)
            end
            local btn = listEntries[entryIdx]
            btn:SetHeight(entryH)
            btn:SetPoint("TOPLEFT",  child, "TOPLEFT",  0, -totalH)
            btn:SetPoint("TOPRIGHT", child, "TOPRIGHT", 0, -totalH)
            PopulateEntry(btn, note, note.id == selID, collapsed)
            btn:Show()
            totalH = totalH + entryH
        end

        -- Divider between pinned and regular (expanded mode only)
        if not collapsed then
            if not child._pinnedDiv then
                local div = child:CreateTexture(nil, "ARTWORK")
                div:SetHeight(1)
                div:SetColorTexture(0.35, 0.35, 0.38, 0.7)
                child._pinnedDiv = div
            end
            child._pinnedDiv:ClearAllPoints()
            child._pinnedDiv:SetPoint("TOPLEFT",  child, "TOPLEFT",  PAD_L, -(totalH + 3))
            child._pinnedDiv:SetPoint("TOPRIGHT", child, "TOPRIGHT", -4,    -(totalH + 3))
            child._pinnedDiv:Show()
            totalH = totalH + 8
        else
            if child._pinnedDiv then child._pinnedDiv:Hide() end
        end
    else
        if child._pinnedHdr then child._pinnedHdr:Hide() end
        if child._pinnedDiv  then child._pinnedDiv:Hide() end
    end

    -- ── Regular section ───────────────────────────────────────────────────────
    -- Always show "— Notes (X) —" header
    if not collapsed then
        local hdr2 = GetSectionHeader("_regularHdr",
            "|cff888888— Notes (" .. #regular .. ") —|r")
        hdr2:SetPoint("TOPLEFT",  child, "TOPLEFT",  PAD_L, -totalH)
        hdr2:SetPoint("TOPRIGHT", child, "TOPRIGHT", -4,    -totalH)
        hdr2:Show()
        totalH = totalH + 18
    else
        if child._regularHdr then child._regularHdr:Hide() end
    end

    for _, note in ipairs(regular) do
        entryIdx = entryIdx + 1
        if not listEntries[entryIdx] then
            listEntries[entryIdx] = CreateListEntry(child)
        end
        local btn = listEntries[entryIdx]
        btn:SetHeight(entryH)
        btn:SetPoint("TOPLEFT",  child, "TOPLEFT",  0, -totalH)
        btn:SetPoint("TOPRIGHT", child, "TOPRIGHT", 0, -totalH)
        PopulateEntry(btn, note, note.id == selID, collapsed)
        btn:Show()
        totalH = totalH + entryH
    end

    -- Empty state
    if #notes == 0 then
        if not BNB._listEmptyLabel then
            local lbl = child:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            lbl:SetPoint("TOP", child, "TOP", 0, -24)
            lbl:SetWidth(200); lbl:SetJustifyH("CENTER"); lbl:SetWordWrap(true)
            lbl:SetTextColor(0.38, 0.38, 0.38)
            BNB._listEmptyLabel = lbl
        end
        BNB._listEmptyLabel:SetText(
            currentFilter ~= "" and "No matches." or L["NOTE_LIST_EMPTY"])
        BNB._listEmptyLabel:Show()
        totalH = 80
    else
        if BNB._listEmptyLabel then BNB._listEmptyLabel:Hide() end
    end

    local sfH = _sf and _sf:GetHeight() or 100
    child:SetHeight(math.max(totalH, sfH))
    if _sf and _sf.UpdateScrollbar then _sf:UpdateScrollbar() end
end

--------------------------------------------------------------------------------
-- SELECT NOTE
--------------------------------------------------------------------------------
function BNB.SelectNote(id)
    -- If switching away from a pending new note (no title yet), clear the flag.
    -- The discard popup handles the actual deletion if needed.
    if BNB._pendingNewNoteID and BNB._currentNoteID ~= id then
        if BNB._pendingNewNoteID == BNB._currentNoteID then
            BNB._pendingNewNoteID = nil
        end
    end
    -- Validate: if the current note has no title, block switching away
    if BNB._currentNoteID and BNB._currentNoteID ~= id then
        local cur = BNB.GetNote(BNB._currentNoteID)
        if cur then
            local liveTitle = BNB._editorTitle and
                (BNB._editorTitle._showingPlaceholder and "" or BNB._editorTitle:GetText()) or cur.title
            if (not liveTitle or liveTitle == "") then
                BNB:Print("|cffff6666Notes must have a title.|r Please add a title before switching notes.")
                if BNB._editorTitle then BNB._editorTitle:SetFocus() end
                return
            end
        end
    end

    BNB._currentNoteID = id; BigNoteBoxDB.selectedNoteID = id
    local collapsed = BNB._listCollapsed
    for _, btn in ipairs(listEntries) do
        if btn:IsShown() then
            if btn._noteID == id then
                local note = BNB.GetNote(id)
                local tc   = note and note.titleColor
                if btn._titleLbl then
                    if tc then
                        btn._titleLbl:SetTextColor(
                            math.min(1, tc.r * 1.15 + 0.05),
                            math.min(1, tc.g * 1.10 + 0.05),
                            math.min(1, tc.b * 1.10 + 0.05), 1)
                    else
                        btn._titleLbl:SetTextColor(unpack(COL_GOLD))
                    end
                end
                btn._selBg:Show()
            else
                local note = BNB.GetNote(btn._noteID)
                local ht   = note and note.title and note.title ~= ""
                local tc   = note and note.titleColor
                if btn._titleLbl then
                    if tc then
                        btn._titleLbl:SetTextColor(tc.r, tc.g, tc.b, 1)
                    else
                        btn._titleLbl:SetTextColor(ht and 1 or 0.5, ht and 1 or 0.5, ht and 1 or 0.5)
                    end
                end
                btn._selBg:Hide()
            end
        end
    end
    if BNB.LoadNoteInEditor then BNB.LoadNoteInEditor(id) end
    if BNB.SyncNoteConfig   then BNB.SyncNoteConfig(id)  end
    if BNB.SyncReferenceBox then BNB.SyncReferenceBox(id) end
    -- If the per-note history panel is open, switch it to the newly selected note
    local nhp = _G["BigNoteBoxNoteHistoryFrame"]
    if nhp and nhp:IsShown() and BNB.OpenNoteHistoryPanel then
        BNB.OpenNoteHistoryPanel(id)
    end
end

--------------------------------------------------------------------------------
-- BUILD NOTE LIST
--------------------------------------------------------------------------------
function BNB.BuildNoteList()
    local pane = BNB.listPane
    if not pane then return end

    -- Restore collapse and display mode from DB
    BNB._listCollapsed = BigNoteBoxDB.listCollapsed or false
    ApplyListMode()

    local searchBar = BuildSearchBar(pane)
    _searchBar = searchBar

    local BTNS_H = NEWBTN_H + PAD_BOT + 2
    local sf = CreateFrame("ScrollFrame", "BigNoteBoxListScroll", pane, "ScrollFrameTemplate")
    -- In expanded mode: leave -22px right gap for scrollbar.
    -- In collapsed mode: span full width (scrollbar hidden, no gap needed).
    -- We update BOTTOMRIGHT in SetListCollapsed.
    sf:SetPoint("TOPLEFT",     pane, "TOPLEFT",     PAD_L, -(SEARCH_H + PAD_TOP + 4))
    sf:SetPoint("BOTTOMRIGHT", pane, "BOTTOMRIGHT", -22,   BTNS_H)
    _sf = sf
    BNB._listScrollFrame = sf

    local scrollBar = sf.ScrollBar
    if scrollBar then scrollBar:SetAlpha(0) end
    local child = CreateFrame("Frame", nil, sf)
    child:SetWidth(sf:GetWidth()); child:SetHeight(1)
    sf:SetScrollChild(child)
    BNB._listScrollChild = child
    sf:SetScript("OnSizeChanged", function(self) child:SetWidth(self:GetWidth()) end)
    if scrollBar then
        sf:HookScript("OnScrollRangeChanged", function(_, _, yRange)
            scrollBar:SetAlpha((yRange or 0) > 1 and 1 or 0)
        end)
    end
    function sf:UpdateScrollbar()
        C_Timer.After(0.05, function()
            if not sf:IsVisible() then return end
            if scrollBar then
                scrollBar:SetAlpha(child:GetHeight() > sf:GetHeight() + 2 and 1 or 0)
            end
        end)
    end

    -- ── Button row (bottom of pane) ──────────────────────────────────────────
    -- Layout: [+ New Note — left half] [Quick Note — right half] [<< — fixed]
    -- All three sit at the same Y. newBtn and qBtn each get half the available
    -- space by chaining: newBtn left→pane, right→qBtn left; qBtn right→colBtn left.
    -- The equal split is enforced by OnSizeChanged which sets both widths to half.
    local btnY      = PAD_BOT + 2
    local btnH      = NEWBTN_H
    local collapseW = 30

    -- Collapse button (rightmost, always fixed) — uses arrow-left/right TGA textures
    local colBtn = CreateFrame("Button", nil, pane)
    colBtn:SetSize(collapseW, btnH)
    colBtn:SetPoint("BOTTOMRIGHT", pane, "BOTTOMRIGHT", -2, btnY)
    local colTex = colBtn:CreateTexture(nil, "ARTWORK")
    colTex:SetAllPoints()
    colTex:SetTexture("Interface\\AddOns\\BigNoteBox\\Assets\\" .. (BNB._listCollapsed and "UI\\ui-arrow-right" or "UI\\ui-arrow-left"))
    colBtn._tx = colTex
    colBtn:SetScript("OnClick", function()
        BNB.SetListCollapsed(not BNB._listCollapsed)
    end)
    colBtn:SetScript("OnEnter", function(self)
        self:SetAlpha(0.85)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(
            BNB._listCollapsed and "Expand note list" or "Collapse to icons only",
            1, 1, 1)
        GameTooltip:Show()
    end)
    colBtn:SetScript("OnLeave", function(self)
        self:SetAlpha(1.0)
        GameTooltip:Hide()
    end)
    _collapseBtn = colBtn

    -- + New Note (left button)
    local newBtn = BNB.CreateButton(nil, pane, L["BTN_NEW_NOTE"], 80, btnH)
    newBtn:SetPoint("BOTTOMLEFT", pane, "BOTTOMLEFT", PAD_L, btnY)
    newBtn:SetScript("OnClick", function() BNB.CreateNewNote() end)
    newBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("New Note", 1, 1, 1)
        GameTooltip:AddLine("Create a new note and open it in the editor.", 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)
    newBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    _newBtn = newBtn

    -- Quick Note (right button, anchored between newBtn and colBtn)
    local qBtn = BNB.CreateButton(nil, pane, "Quick Note", 80, btnH)
    qBtn:SetPoint("BOTTOMLEFT",  newBtn, "BOTTOMRIGHT", 4,  0)
    qBtn:SetPoint("BOTTOMRIGHT", colBtn, "BOTTOMLEFT",  -4, 0)
    qBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Quick Note", 1, 1, 1)
        GameTooltip:AddLine("Creates a titled note and opens it for editing.\nTitle is auto-generated (Quick Note, Quick Note 2, ...).", 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)
    qBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    qBtn:SetScript("OnClick", function()
        if InCombatLockdown() then BNB:Print(L["COMBAT_BLOCKED"]); return end
        BNB.SaveCurrentNote()
        local title = GetNextQuickNoteTitle()
        local id    = BNB.CreateNote(title)
        BNB.UpdateNote(id, { icon = "Interface\\Icons\\INV_Misc_Note_04" })
        if not BNB.mainFrame then BNB.CreateMainWindow() end
        if not BNB.mainFrame:IsShown() then BNB.mainFrame:Show() end
        if BNB.RefreshNoteList then BNB.RefreshNoteList() end
        if BNB.SelectNote      then BNB.SelectNote(id)   end
        C_Timer.After(0.05, function()
            if BNB._editorBody then BNB._editorBody:SetFocus() end
        end)
    end)
    _qBtn = qBtn

    -- Keep both buttons equal width as the pane resizes.
    -- qBtn is anchor-driven (fills newBtn right → colBtn left) so we only need
    -- to set newBtn width = half the available space.
    local function UpdateButtonLabels()
        if not _newBtn or not _qBtn or not pane:GetWidth() then return end
        local paneW     = pane:GetWidth()
        local available = paneW - PAD_L - collapseW - 12  -- gaps between buttons
        local halfW     = math.max(20, math.floor(available / 2))
        _newBtn:SetWidth(halfW)
        -- Label tiers based on half width
        if halfW >= 70 then
            _newBtn:SetText(L["BTN_NEW_NOTE"])
            _qBtn:SetText("Quick Note")
        elseif halfW >= 28 then
            _newBtn:SetText("+NN")
            _qBtn:SetText("QN")
        else
            _newBtn:SetText("+")
            _qBtn:SetText("Q")
        end
    end
    pane:SetScript("OnSizeChanged", function() UpdateButtonLabels() end)
    C_Timer.After(0.1, UpdateButtonLabels)
    BNB._updateButtonLabels = UpdateButtonLabels

    -- Apply initial collapse state (hides search/buttons, reanchors sf if collapsed)
    if BNB._listCollapsed then
        searchBar:Hide()
        _newBtn:Hide()
        _qBtn:Hide()
        sf:ClearAllPoints()
        sf:SetPoint("TOPLEFT",     pane, "TOPLEFT",     PAD_L, -4)
        sf:SetPoint("BOTTOMRIGHT", pane, "BOTTOMRIGHT", -22,   NEWBTN_H + PAD_BOT + 2)
    end
end

-- Refresh note list icons when target changes so target note portraits update live.
-- Only fires RefreshNoteList if the main window is visible — no-op otherwise.
BNB.RegisterEvent("PLAYER_TARGET_CHANGED", function()
    if BNB.mainFrame and BNB.mainFrame:IsShown() then
        if BNB.RefreshNoteList then BNB.RefreshNoteList() end
    end
end)

-- Refresh the note list when tasks change so the task icon (ui-tasks) in the
-- note list row appears/disappears as tasks are added or removed.
C_Timer.After(0, function()
    if BNB.Task and BNB.Task.RegisterCallback then
        BNB.Task.RegisterCallback("TasksChanged", function()
            if BNB.mainFrame and BNB.mainFrame:IsShown() then
                if BNB.RefreshNoteList then BNB.RefreshNoteList() end
            end
        end)
    end
end)

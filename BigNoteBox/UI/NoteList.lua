-- BigNoteBox UI/NoteList.lua — Left pane note list
-- Supports a collapsible icon-only mode toggled by the << / >> button.

local BNB = BigNoteBox
local L   = BNB.L

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
-- The row is ICON_SIZE_SPACIOUS + 12 + 6 wide, so the square row art around
-- the largest icon fits with room on both sides (2026-10-05, was 82).
local COLLAPSED_W  = PAD_L + ICON_SIZE_SPACIOUS + 12 + 6 + 22   -- 90px

local DEFAULT_ICON = "Interface\\Icons\\INV_Misc_Note_06"
local ICON_BORDER  = "Interface\\Common\\WhiteIconFrame"

local COL_WHITE  = { 1,    1,    1,    1 }
local COL_GREY   = { 0.58, 0.58, 0.58, 1 }
local COL_SEL_BG = { 0.40, 0.85, 0.40, 0.12 }   -- BNB green, Sidebar ACTIVE_R/G/B (ALL-98)
local HDR_RULE_A = 0.35   -- Pinned / Notes headers: the rule's alpha (ALL-328); colour = BNB.HeaderColor()
-- Normal mode row art, a test (Dukul 2026-10-03): stretched over the whole row.
-- Skin mode keeps the colour fills above and below.
local ROW_SEL_TEX   = "Interface\\AddOns\\BigNoteBox\\Assets\\UI\\ui-note-list-selection"
local ROW_HOVER_TEX = "Interface\\AddOns\\BigNoteBox\\Assets\\UI\\ui-note-list-hover"
local ROW_MULTI_TEX = "Interface\\AddOns\\BigNoteBox\\Assets\\UI\\ui-note-list-multi-selection"
-- Collapsed (icon-only) list: square versions drawn around the icon instead
-- of stretched over the row, which skewed and cut them (Dukul 2026-10-05)
local ROW_SEL_SQ   = "Interface\\AddOns\\BigNoteBox\\Assets\\UI\\ui-note-list-collapsed-selection"
local ROW_HOVER_SQ = "Interface\\AddOns\\BigNoteBox\\Assets\\UI\\ui-note-list-collapsed-hover"
local ROW_MULTI_SQ = "Interface\\AddOns\\BigNoteBox\\Assets\\UI\\ui-note-list-collapsed-multi-selection"
-- Player-note rows: the faction crest, subdued, at the row's right (ALL-305)
local FACTION_ART = {
    Horde    = "Interface\\AddOns\\BigNoteBox\\Assets\\UI\\ui-bg-model-horde",
    Alliance = "Interface\\AddOns\\BigNoteBox\\Assets\\UI\\ui-bg-model-alliance",
}
local FACTION_ALPHA = 1   -- the art is already subdued; 1 as a test (Dukul 2026-10-05), was 0.18 (invisible)
-- The three row pictures are greyscale and take the BNB green here (Dukul,
-- 2026-10-03): one colour for all, the art keeps its shading and alpha
local function TintRowArt(tex)
    tex:SetVertexColor(COL_SEL_BG[1], COL_SEL_BG[2], COL_SEL_BG[3])
end

local listEntries   = {}
BNB._listEntries    = listEntries   -- shared with TagTree.lua
local currentFilter = ""
local currentTagFilter = nil   -- tag string being filtered, or nil
local debounceTimer = nil

-- Expose filter state for TagTree.lua
function BNB.GetCurrentFilter()    return currentFilter    end
function BNB.GetCurrentTagFilter() return currentTagFilter end
-- Any search text, tag, favourite or task filter on (the explorer view's
-- flat search results, ALL-414)
function BNB.IsListFiltering()
    return currentFilter ~= "" or currentTagFilter ~= nil
        or BNB._favFilterActive == true or BNB._taskFilterActive == true
end

-- Drag-reorder state
local _dragNoteID   = nil   -- noteID being dragged
local _dragGhost    = nil   -- semi-transparent overlay frame
local _dragTargetID = nil   -- drop goes before this note id (after it when _dragAfter)
local _dragAfter    = false
-- Folders (ALL-510 S3): the drop on a header, and the section of the row the
-- drop line sits at (a folder id or "notes": a Custom-sort drop files it there)
local _dragFolder   = nil   -- a folder id, false = the Notes header (out of folders), nil = no header
local _dragHeader   = nil   -- the header lit as the drop target
local _dragSection  = nil
local _dragIDs      = nil   -- the notes carried: the dragged one, or Select mode's picks
local _dropAt       = nil   -- GetTime() of the last drop: the row's own click that follows is not a pick

-- Multi-select state
local _multiMode    = false          -- checkbox mode active
local _multiSel     = {}             -- { [noteID]=true }

-- Module-level refs set in BuildNoteList, used by collapse toggle
local _newBtn, _qBtn, _collapseBtn, _searchBar, _sf = nil,nil,nil,nil,nil
-- The search row lent to the explorer view's tool row (BNB.DockListSearch):
-- nil = in the list; else { host, width }
local _searchDock = nil
local _searchParts = nil   -- { bar, ac, parent, place } once the row is built

-- The collapse button's arrow: right while collapsed, left while open, with
-- Dukul's -hover art under the pointer (2026-09-28).
local function PaintCollapseArrow(btn, hover)
    local name = BNB._listCollapsed and "ui-arrow-right" or "ui-arrow-left"
    btn._tx:SetTexture("Interface\\AddOns\\BigNoteBox\\Assets\\UI\\" .. name .. (hover and "-hover" or ""))
end
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
            pcall(function() BNB.SetHeaderColor(_searchEb) end)
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
    local v  = db and db.listEntryHeight or BNB.DEFAULTS.listEntryHeight
    if v == "compact"  then return "compact"
    elseif v == "spacious" then return "spacious"
    else return "normal" end
end

-- Pin/situation overlay size scales proportionally with icon
-- Normal mode's layered markers are drawn larger (Dukul, 2026-10-08); skin
-- mode keeps 0.38. Skin mode changes reload, so read once per call is fine
local function OverlaySize(iconSz)
    local f = (BigNoteBoxDB and BigNoteBoxDB.skinMode) and 0.38 or 0.5
    return math.max(10, math.floor(iconSz * f))
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
                btn._favTex:SetPoint("TOPRIGHT", btn._icon, "TOPRIGHT", 2, 2)
            end
            if btn._situTex then
                btn._situTex:SetSize(ovSz, ovSz)
                btn._situTex:ClearAllPoints()
                btn._situTex:SetPoint("TOPLEFT", btn._icon, "TOPLEFT", -2, 2)
            end
            if btn._scopeTex then
                btn._scopeTex:SetSize(ovSz, ovSz)
                btn._scopeTex:ClearAllPoints()
                btn._scopeTex:SetPoint("BOTTOMLEFT", btn._icon, "BOTTOMLEFT", -2, -2)
            end
            if btn._locTex then
                btn._locTex:SetSize(ovSz, ovSz)
                btn._locTex:ClearAllPoints()
                btn._locTex:SetPoint("LEFT", btn._icon, "LEFT", -2, 0)
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
-- COLLAPSE / EXPAND LIST PANE
-- Stores state in BNB._listCollapsed and BigNoteBoxDB.listCollapsed.
-- Notifies MainWindow to adjust the split position.
--------------------------------------------------------------------------------
-- Room kept above the scrolling rows (expanded list only): the tag tree /
-- folder view's Collapse all / Expand all row stays there while the rows
-- scroll (Dukul, 2026-10-20). Set by Features/TagTree.lua, 0 = none
local _sfTopExtra = 0
function BNB.SetListTopInset(px)
    px = px or 0
    if px == _sfTopExtra then return end
    _sfTopExtra = px
    if _sf and not BNB._listCollapsed then
        local pane = _sf:GetParent()
        local BTNS_H = NEWBTN_H + PAD_BOT + 2
        _sf:ClearAllPoints()
        _sf:SetPoint("TOPLEFT",     pane, "TOPLEFT",     PAD_L, -(SEARCH_H + PAD_TOP + 4 + px))
        _sf:SetPoint("BOTTOMRIGHT", pane, "BOTTOMRIGHT", -22,   BTNS_H)
    end
end

-- Clears the search text and the tag, favourite and task filters when any is
-- on (the reset button's own action): the explorer view's search field on close
function BNB.ResetListFilters()
    local oc = BNB._searchOuterClear
    local reset = BNB.IsListFiltering() and oc and oc:GetScript("OnClick")
    if reset then reset(oc) end
end

-- The explorer view borrows the list's search row (ALL-414 S2): one search,
-- one set of filters, the same text in both views. host = the frame it fills
-- (the filter buttons at its right end), onEscape = what Esc in the box does
-- there; nil gives it back to the list, where a collapsed list hides it and
-- clears what it was filtering.
function BNB.DockListSearch(host, onEscape)
    local P = _searchParts
    if not P then return end
    local parts = { P.bar, BNB._favBtn, BNB._taskFilterBtn, BNB._searchOuterClear, P.ac }
    if host then
        local moved = not _searchDock
        _searchDock = { host = host, onEscape = onEscape }
        if moved then
            for _, fr in ipairs(parts) do if fr then fr:SetParent(host) end end
            P.ac:SetFrameLevel(host:GetFrameLevel() + 100)   -- the tag list over the tiles
        end
        P.bar:Show(); BNB._favBtn:Show(); BNB._searchOuterClear:Show()
        BNB.ApplyTaskFilterButton()
        return
    end
    if not _searchDock then return end
    _searchDock = nil
    for _, fr in ipairs(parts) do if fr then fr:SetParent(P.parent) end end
    P.ac:SetFrameLevel(P.bar:GetFrameLevel() + 20)
    P.bar:ClearAllPoints()
    P.bar:SetHeight(SEARCH_H)
    P.place()
    BNB.ApplyTaskFilterButton()
    -- The list's own rules again: collapsed hides the row and clears it
    BNB.SetListCollapsed(BNB._listCollapsed and true or false)
end

-- Puts the cursor in the search box (the explorer view's search icon)
function BNB.FocusListSearch()
    local eb = _searchParts and _searchParts.eb
    if eb and eb:IsVisible() then eb:SetFocus() end
end

function BNB.SetListCollapsed(collapsed)
    BNB._listCollapsed = collapsed
    BigNoteBoxDB.listCollapsed = collapsed

    -- Update collapse button arrow texture
    if _collapseBtn and _collapseBtn._tx then
        PaintCollapseArrow(_collapseBtn, _collapseBtn:IsMouseOver())
    end

    -- Show/hide expanded-only elements (not while the explorer view has the
    -- search row: it stays in its tool row)
    if _searchBar and not _searchDock then
        if collapsed then _searchBar:Hide() else _searchBar:Show() end
    end
    if BNB._favBtn and not _searchDock then
        if collapsed then BNB._favBtn:Hide() else BNB._favBtn:Show() end
    end
    if BNB._taskFilterBtn and not _searchDock then
        -- Stays hidden while the Tasks module is off (ALL-102)
        local show = not collapsed and BNB.TasksEnabled()
        if show then BNB._taskFilterBtn:Show() else BNB._taskFilterBtn:Hide() end
    end
    if BNB._tagTreeBtn then
        if collapsed then BNB._tagTreeBtn:Hide() else BNB._tagTreeBtn:Show() end
    end
    if BNB._folderTreeBtn then   -- ALL-510 S4; hidden while the Folders module is off (ALL-514)
        if collapsed or not BNB.FoldersEnabled() then BNB._folderTreeBtn:Hide() else BNB._folderTreeBtn:Show() end
    end
    if BNB._searchOuterClear and not _searchDock then
        if collapsed then BNB._searchOuterClear:Hide() else BNB._searchOuterClear:Show() end
    end
    -- New Note stays in both modes: collapsed it is a narrow "NN" left of the arrow
    -- (Dukul, 2026-10-02); its width and label come from UpdateButtonLabels
    if _newBtn then _newBtn:Show() end
    if _qBtn then
        if collapsed then _qBtn:Hide() else _qBtn:Show() end
    end
    -- Collapsing hides the search row, so a search or filter left on would be
    -- stuck until the list is opened again: collapsing resets them, as the
    -- reset button does (Dukul, 2026-10-20)
    if collapsed and not _searchDock then
        local filtering = currentFilter ~= "" or currentTagFilter ~= nil
            or BNB._favFilterActive == true or BNB._taskFilterActive == true
        local oc = BNB._searchOuterClear
        local reset = filtering and oc and oc:GetScript("OnClick")
        if reset then reset(oc) end
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
            _sf:SetPoint("TOPLEFT",     _sf:GetParent(), "TOPLEFT",     PAD_L, -(SEARCH_H + PAD_TOP + 4 + _sfTopExtra))
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

    -- Refresh button labels after collapse state change (both ways: collapsed = "NN")
    if BNB._updateButtonLabels then
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
    local notes = (BNB.NotesDB() or {}).notes or {}
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
        favBtn:SetAlpha(active and 1.0 or BNB.DimAlpha(0.35))
        pcall(function() favBtn._tx:SetDesaturated(not active) end)
    end
    if BNB._applyOuterClearState then BNB._applyOuterClearState() end
    BNB.RefreshNoteList()
end

local function BuildSearchBar(parent)
    -- Layout (left → right):
    --   [folderBtn] [# tagTreeBtn] [bar: search text ... innerX ] [★ favBtn] [outerX]
    -- bar shrinks left to leave room for the two tree buttons, and right for fav/reset.
    local OUTER_BTN  = 18   -- size of each outside button (fav, tasks, reset)
    local OUTER_GAP  = 4    -- gap between bar, star, tasks, outerX
    local OUTER_ROOM = OUTER_BTN + OUTER_GAP + OUTER_BTN + OUTER_GAP + OUTER_BTN + OUTER_GAP  -- 66px
    local TREE_BTN   = 18   -- tag tree / folder view button size
    local TREE_GAP   = 4    -- gap between the tree buttons and the bar left edge

    -- ── Tree view buttons (left of search bar) ────────────────────────────────
    -- The tag tree and the folder view (ALL-510 S4) are one view with two
    -- sources (Features/TagTree.lua): a button is lit while its source is
    -- shown, a click shows it or goes back to the list. Built before bar so we
    -- can anchor bar relative to them, but parented to parent at a raised
    -- frame level so they sit above the bar backdrop.
    local ASSETS = "Interface\\AddOns\\BigNoteBox\\Assets\\"
    local function TreeOn(source)
        local db = BigNoteBoxDB
        if not (db and db.tagTreeMode) then return false end
        if source == "folders" then return db.treeSource == "folders" end
        return db.treeSource ~= "folders"
    end
    local function ApplyLit(btn, tx, on)
        btn:SetAlpha(on and 1.0 or BNB.DimAlpha(0.35))
        pcall(function() tx:SetDesaturated(not on) end)
    end
    -- tint = the search row's white art (gold / skin accent). texOn = the
    -- picture while its source is shown (the folder button shows the list
    -- view icon in the folder view, Dukul 2026-10-19, ALL-514)
    local function TreeButton(tex, source, tint, tipOn, tipOff, texOn)
        local tb = CreateFrame("Button", nil, parent)
        tb:SetSize(TREE_BTN, TREE_BTN)
        tb:SetFrameLevel(parent:GetFrameLevel() + 10)
        local tx = tb:CreateTexture(nil, "ARTWORK")
        tx:SetAllPoints()
        tx:SetTexture(tex)
        -- The four search-row icons are white art, bare (no button border): gold
        -- in normal mode, the skin accent in skin mode, ui-hover-64 on hover
        -- (Dukul, 2026-10-08)
        if tint then BNB.TintUIIcon(tx) end
        BNB.AddUIIconHover(tb, tx)
        tb._tx = tx
        tb._apply = function()
            local on = TreeOn(source)
            if texOn then tx:SetTexture(on and texOn or tex) end
            ApplyLit(tb, tx, on)
        end
        tb._apply()
        tb:SetScript("OnClick", function()
            if BNB.SetTagTreeMode then BNB.SetTagTreeMode(not TreeOn(source), source) end
        end)
        tb:SetScript("OnEnter", function(self)
            self:SetAlpha(1.0)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:AddLine(TreeOn(source) and L[tipOff] or L[tipOn], 1, 1, 1)
            GameTooltip:Show()
        end)
        tb:SetScript("OnLeave", function()
            tb._apply()
            GameTooltip:Hide()
        end)
        return tb
    end
    -- Both tree buttons show the list view icon while their view is on
    -- (Dukul, 2026-10-19, ALL-514)
    local treeBtn = TreeButton(ASSETS .. "UI\\ui-treeview", nil, true,
        "TAGTREE_TOGGLE_TIP_ON", "TAGTREE_TOGGLE_TIP_OFF", ASSETS .. "UI\\ui-list-view")
    -- Dukul's white folder / list view icons (ALL-514), tinted like the rest
    local folderBtn = TreeButton(ASSETS .. "UI\\ui-folder", "folders", true,
        "FOLDER_TREE_TIP_ON", "FOLDER_TREE_TIP_OFF", ASSETS .. "UI\\ui-list-view")
    BNB._tagTreeBtn    = treeBtn
    BNB._folderTreeBtn = folderBtn
    -- Called by SetTagTreeMode / InitTagTree to sync both buttons with the saved state
    BNB._syncTreeBtns = function()
        treeBtn._apply(); folderBtn._apply()
    end

    local bar = BNB.CreateBackdropFrame("Frame", nil, parent)
    bar:SetPoint("TOPLEFT",  parent, "TOPLEFT",  PAD_L + 2 * (TREE_BTN + TREE_GAP) + 2, -2)
    bar:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -(2 + OUTER_ROOM), -2)
    bar:SetHeight(SEARCH_H)

    -- Anchor the tree buttons left of the bar, vertically centred to bar height
    treeBtn:SetPoint("RIGHT", bar, "LEFT", -TREE_GAP, 0)
    folderBtn:SetPoint("RIGHT", treeBtn, "LEFT", -TREE_GAP, 0)
    -- Folders module off (ALL-514): no folder button, the bar one button wider
    local function PlaceFolderBtn()
        local on = BNB.FoldersEnabled()
        local n = on and 2 or 1
        if not _searchDock then
            bar:SetPoint("TOPLEFT", parent, "TOPLEFT", PAD_L + n * (TREE_BTN + TREE_GAP) + 2, -2)
        end
        if on and not BNB._listCollapsed then folderBtn:Show() else folderBtn:Hide() end
        folderBtn._apply()
    end
    PlaceFolderBtn()
    BNB.RegisterMessage("NoteListFolderBtn", "FoldersModule", PlaceFolderBtn)

    -- Search bar backdrop: skin-aware or plain dark
    local function ApplySearchBarSkin()
        local db = BigNoteBoxDB
        if db and db.skinMode and BNB.GetSkinPreset then
            local p = BNB.GetSkinPreset()
            local r, g, b = BNB.SkinButtonOf(p)
            local br, bg_, bb, ba = BNB.SkinBorderOf(p)
            BNB.SetBackdrop(bar, r, g, b, 0.92, br, bg_, bb, ba)
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
    eb:SetFontObject("BNBFontNormal")
    eb:SetAutoFocus(false)
    eb:SetMaxLetters(200)
    BNB.AddPlaceholder(eb, L["SEARCH_PLACEHOLDER"], 0.40, 0.40, 0.40)
    _searchEb = eb

    local _tagAC   -- tag autocomplete dropdown, built further down; the clear buttons hide it

    -- Inner X: resets only the editbox + tag filter (stays inside bar)
    local innerClear = CreateFrame("Button", nil, bar)
    innerClear:SetSize(18, 18)
    innerClear:SetPoint("RIGHT", bar, "RIGHT", -2, 0)
    local iClbl = innerClear:CreateFontString(nil, "OVERLAY", "BNBFontNormal")
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
    local favBtn = CreateFrame("Button", nil, parent)
    favBtn:SetSize(OUTER_BTN, OUTER_BTN)
    favBtn:SetPoint("LEFT", bar, "RIGHT", OUTER_GAP, 0)
    local favTx = favBtn:CreateTexture(nil, "ARTWORK")
    favTx:SetAllPoints()
    favTx:SetTexture(ASSETS .. "UI\\ui-favorite")
    BNB.TintUIIcon(favTx)
    BNB.AddUIIconHover(favBtn, favTx)
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
        GameTooltip:AddLine(_favFilterActive and L["NL_FAV_SHOW_ALL"] or L["NL_FAV_SHOW_FAV_ONLY"], 1, 1, 1)
        if currentFilter ~= "" then
            GameTooltip:AddLine(L["NL_FAV_ACTIVE_WITH_FILTER"], 0.78, 0.78, 0.78)
        end
        GameTooltip:Show()
    end)
    favBtn:SetScript("OnLeave", function(self)
        self:SetAlpha(_favFilterActive and 1.0 or BNB.DimAlpha(0.35))
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
    BNB.TintUIIcon(taskFilterTx)
    BNB.AddUIIconHover(taskFilterBtn, taskFilterTx)
    taskFilterBtn._tx = taskFilterTx
    taskFilterBtn:SetAlpha(0.35)
    pcall(function() taskFilterTx:SetDesaturated(true) end)
    local function SetTaskFilter(active)
        _taskFilterActive = active
        BNB._taskFilterActive = active
        taskFilterBtn:SetAlpha(active and 1.0 or BNB.DimAlpha(0.35))
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
        GameTooltip:AddLine(_taskFilterActive and L["NL_FAV_SHOW_ALL"] or L["NL_TASK_SHOW_TASKS_ONLY"], 1, 1, 1)
        GameTooltip:Show()
    end)
    taskFilterBtn:SetScript("OnLeave", function(self)
        self:SetAlpha(_taskFilterActive and 1.0 or BNB.DimAlpha(0.35))
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
    BNB.TintUIIcon(oTex)
    BNB.AddUIIconHover(outerClear, oTex)

    -- Active (lit) only when something is actually filtering; grey otherwise.
    local function ApplyOuterClearState()
        local active = _favFilterActive or _taskFilterActive or (currentFilter ~= "")
            or (currentTagFilter ~= nil)
        outerClear:SetAlpha(active and 1.0 or BNB.DimAlpha(0.40))
        pcall(function() oTex:SetDesaturated(not active) end)
    end
    ApplyOuterClearState()

    outerClear:SetScript("OnEnter", function(self)
        local active = _favFilterActive or _taskFilterActive or (currentFilter ~= "")
            or (currentTagFilter ~= nil)
        if active then self:SetAlpha(1.0) end
        pcall(function() oTex:SetDesaturated(false) end)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(L["NL_RESET_FILTERS_TIP"], 1, 1, 1)
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

    -- Tasks module off (ALL-102): no task filter button, its filter cleared,
    -- and the reset button and search bar close the gap it leaves.
    function BNB.ApplyTaskFilterButton()
        local on = BNB.TasksEnabled()
        if not on and _taskFilterActive then SetTaskFilter(false) end
        taskFilterBtn:SetShown(on and (_searchDock ~= nil or not BNB._listCollapsed))
        outerClear:ClearAllPoints()
        outerClear:SetPoint("LEFT", on and taskFilterBtn or favBtn, "RIGHT", OUTER_GAP, 0)
        local room = OUTER_ROOM - (on and 0 or (OUTER_BTN + OUTER_GAP))
        if _searchDock then
            -- Lent to the explorer view: its search field, the filter
            -- buttons at the right end
            local host = _searchDock.host
            bar:ClearAllPoints()
            bar:SetPoint("LEFT", host, "LEFT", 0, 0)
            bar:SetPoint("RIGHT", host, "RIGHT", -(2 + room), 0)
            bar:SetHeight(host:GetHeight())
        else
            bar:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -(2 + room), -2)
        end
    end
    BNB.ApplyTaskFilterButton()

    -- Update reset button state whenever search text changes
    eb:HookScript("OnTextChanged", function()
        ApplyOuterClearState()
    end)

    -- ── Tag autocomplete dropdown ─────────────────────────────────────────────
    -- Appears below the search bar when user types "#" + 3 or more characters.
    _tagAC = CreateFrame("Frame", nil, parent)
    BNB.SetBackdrop(_tagAC, 0.08, 0.08, 0.10, 0.97, 0.40, 0.40, 0.42, 1)
    _tagAC:SetFrameLevel(bar:GetFrameLevel() + 20)
    _tagAC:SetPoint("TOPLEFT",  bar, "BOTTOMLEFT",  0, -2)
    _tagAC:SetPoint("TOPRIGHT", bar, "BOTTOMRIGHT", 0, -2)
    _tagAC:Hide()
    -- What BNB.DockListSearch moves (the explorer view's tool row, ALL-414)
    _searchParts = { bar = bar, ac = _tagAC, parent = parent, place = PlaceFolderBtn, eb = eb }

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
                -- The tag's colour swatch (ALL-106), shown only for a coloured tag
                local sw = row:CreateTexture(nil, "ARTWORK")
                sw:SetSize(12, 12)
                sw:SetPoint("LEFT", row, "LEFT", 4, 0)
                sw:Hide()
                row._sw = sw
                local rowLbl = row:CreateFontString(nil, "OVERLAY", "BNBFontNormal")
                rowLbl:SetPoint("LEFT", row, "LEFT", 4, 0)
                rowLbl:SetJustifyH("LEFT")
                BNB.SetHeaderColor(rowLbl)
                row._lbl = rowLbl
                local rowHi = row:CreateTexture(nil, "HIGHLIGHT")
                rowHi:SetAllPoints(); rowHi:SetColorTexture(1, 1, 1, 0.08)
                _tagACRows[i] = row
            end
            local row = _tagACRows[i]
            row:SetPoint("TOPLEFT",  _tagAC, "TOPLEFT",  4, -2 - (i-1)*ROW_H_AC)
            row:SetPoint("TOPRIGHT", _tagAC, "TOPRIGHT", -4, -2 - (i-1)*ROW_H_AC)
            local tag = matches[i]
            local hasSw = BNB.TagColors and BNB.TagColors.Swatch(row._sw, tag)
            if not hasSw then row._sw:Hide() end
            row._lbl:ClearAllPoints()
            row._lbl:SetPoint("LEFT", row, "LEFT", hasSw and 20 or 4, 0)
            row._lbl:SetText("#" .. tag)
            row:SetScript("OnClick", function()
                currentTagFilter = tag
                currentFilter    = ""
                eb._showingPlaceholder = false
                eb:SetText("#" .. tag)
                pcall(function() BNB.SetHeaderColor(eb) end)
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
                pcall(function() BNB.SetHeaderColor(eb) end)
            else
                currentTagFilter = nil
                currentFilter    = text
                pcall(function()
                    if not eb._showingPlaceholder then
                        BNB.SetTextWhite(eb)
                    end
                end)
            end
            BNB.RefreshNoteList()
        end)
    end)
    -- Arrow keys over the tag list; Enter takes a highlighted tag (ALL-427)
    local tagNav = BNB.AttachListKeys(eb, _tagAC, _tagACRows)
    eb:SetScript("OnEnterPressed", function() tagNav:Take() end)
    eb:SetScript("OnEscapePressed", function(self)
        if _tagAC:IsShown() then
            HideTagAC()
        elseif _searchDock and _searchDock.onEscape then
            -- Lent to the explorer view: Esc closes its search field
            self:ClearFocus()
            _searchDock.onEscape()
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
-- The menu itself is UI/NoteContextMenu.lua (ALL-148); the helpers it uses
-- from here go over through BNB._NoteListKit.
--------------------------------------------------------------------------------

local function DuplicateNote(id)
    local src = BNB.GetNote(id)
    if not src then return end
    BNB.SaveCurrentNote()
    -- Full copy (rich mode, tasks, attachments...): see BNB.CopyNote
    local newID = BNB.CopyNote(id, {
        title = src.title ~= "" and (src.title .. " (copy)") or "" })
    if not newID then return end
    if BNB.SelectNote      then BNB.SelectNote(newID) end
end

--------------------------------------------------------------------------------
-- NOTE ACTIONS
-- One body per action, shared by the right-click menu and the list's
-- double-click setting (BigNoteBoxDB.listDoubleClick, nil = "settings",
-- ALL-100). Toggles flip the note's current state.
--------------------------------------------------------------------------------
local function NoteIsLocked(n)
    return (n.locked == true) or (n.locked == nil and BigNoteBoxDB.lockNotes == true)
end

-- "esc" / "world" when the note is open as a sticky of that kind, else nil.
-- An ESC sticky counts as open while the ESC menu is closed (SN.IsOpen).
local function StickyOpenKind(noteID)
    if not (BNB.Sticky and BNB.Sticky.IsOpen and BNB.Sticky.IsOpen(noteID)) then return nil end
    local rec = BigNoteBoxDB and BigNoteBoxDB.postits and BigNoteBoxDB.postits[noteID]
    return (rec and rec.cfg and rec.cfg.escOnly == true) and "esc" or "world"
end

-- A toggle: the same kind already open closes (as its X does); the other
-- kind moves over; not open opens (Dukul, 2026-09-28).
local function OpenAsSticky(noteID, escOnly)
    if not (BNB.Sticky and BNB.Sticky.Open) then return end
    if StickyOpenKind(noteID) == (escOnly and "esc" or "world") then
        BNB.Sticky.Close(noteID); return
    end
    -- Close it first if already open, so SN.Open rebuilds it with the right
    -- strata. Before writing escOnly: closing an ESC sticky resets escOnly to
    -- false (the X "back to normal" gesture), which undid an ESC open every
    -- second time, and the reset was saved across reloads.
    if BNB.Sticky.IsOpen(noteID) then BNB.Sticky.Close(noteID) end
    -- Write an explicit escOnly so the global stickyEscDefault doesn't re-apply.
    local db = BigNoteBoxDB
    if db then
        db.postits = db.postits or {}
        db.postits[noteID] = db.postits[noteID] or {}
        db.postits[noteID].cfg = db.postits[noteID].cfg or {}
        db.postits[noteID].cfg.escOnly = escOnly
    end
    BNB.Sticky.Open(noteID)   -- ESC-only mode shows the ESC menu
end

local NOTE_ACTIONS = {}
NOTE_ACTIONS.open      = function(noteID)
    -- From the Oracle's menu the main window may be closed (as OpenInMain, UI/Oracle.lua)
    if not (BNB.mainFrame and BNB.mainFrame:IsShown()) then
        if InCombatLockdown() then BNB:Print(L["COMBAT_BLOCKED"]); return end
        BNB.OpenMainWindow()
    end
    BNB.SaveCurrentNote()
    -- From outside the list (Oracle results) the note may be filtered out
    if BNB.RevealNoteInList then BNB.RevealNoteInList(noteID) end
    BNB.SelectNote(noteID)
end
-- The one way to open a note in the main window from outside the list
-- (situation toasts): opens the window, shows the note if a filter hides it
BNB.OpenNoteInMain = NOTE_ACTIONS.open
NOTE_ACTIONS.settings  = function(noteID)
    if BNB.OpenNoteConfig then BNB.OpenNoteConfig(noteID) end
end
-- Sticky Notes off (ALL-343): a double-click set to a sticky just opens the note
NOTE_ACTIONS.sticky    = function(noteID)
    if not BNB.StickiesEnabled() then NOTE_ACTIONS.open(noteID); return end
    OpenAsSticky(noteID, false)
end
NOTE_ACTIONS.escSticky = function(noteID)
    if not BNB.StickiesEnabled() then NOTE_ACTIONS.open(noteID); return end
    OpenAsSticky(noteID, true)
end
NOTE_ACTIONS.alarm     = function(noteID)
    -- Alarms off (ALL-343): a double-click set to "Set alarm" just opens the note
    if not BNB.AlarmsEnabled() then NOTE_ACTIONS.open(noteID); return end
    if BNB.SelectNote then BNB.SelectNote(noteID) end
    C_Timer.After(0.05, function()
        if BNB.AlarmWindow and BNB.AlarmWindow.OpenLeftOfMain then
            BNB.AlarmWindow.OpenLeftOfMain(noteID)
        end
    end)
end
NOTE_ACTIONS.task      = function(noteID)
    -- Tasks off (ALL-102): a double-click set to "Add task" just opens the note
    if not BNB.TasksEnabled() then NOTE_ACTIONS.open(noteID); return end
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
end
-- OpenFocusMode refuses a locked note itself (FOCUS_LOCKED)
NOTE_ACTIONS.focus     = function(noteID)
    -- Focus Mode off (ALL-343): a double-click set to Focus mode just opens the note
    if not BNB.FocusEnabled() then NOTE_ACTIONS.open(noteID); return end
    BNB.SaveCurrentNote(); BNB.SelectNote(noteID)
    if BNB._currentNoteID == noteID and BNB.OpenFocusMode then BNB.OpenFocusMode() end
end
NOTE_ACTIONS.pin       = function(noteID)
    local n = BNB.GetNote(noteID); if not n then return end
    BNB.UpdateNote(noteID, { pinned = not n.pinned })
end
NOTE_ACTIONS.fav       = function(noteID)
    local n = BNB.GetNote(noteID); if not n then return end
    if n.favorited then
        BNB.UpdateNote(noteID, { _clear = {"favorited"} })
    else
        BNB.UpdateNote(noteID, { favorited = true })
    end
end
NOTE_ACTIONS.lock      = function(noteID)
    local n = BNB.GetNote(noteID); if not n then return end
    BNB.UpdateNote(noteID, { locked = not NoteIsLocked(n) })
    if BNB.Sticky and BNB.Sticky.RefreshLockIcons then BNB.Sticky.RefreshLockIcons(noteID) end
    if BNB.LoadNoteInEditor   then BNB.LoadNoteInEditor(BNB._currentNoteID) end
    if BNB.RefreshReferenceBox then BNB.RefreshReferenceBox() end
end

-- Settings > Notes lists these, in this order (UI/Config/Notes.lua)
BNB.LIST_DOUBLE_CLICK_ACTIONS = {
    { value = "settings",  key = "NL_CTX_OPEN_SETTINGS" },
    { value = "open",      key = "CFG_DBL_NONE" },
    { value = "sticky",    key = "NL_CTX_OPEN_STICKY" },
    { value = "escSticky", key = "NL_CTX_OPEN_ESC_STICKY" },
    { value = "focus",     key = "CFG_DBL_FOCUS" },
    { value = "alarm",     key = "CFG_DBL_ALARM" },
    { value = "task",      key = "NL_CTX_ADD_TASK" },
    { value = "lock",      key = "CFG_DBL_LOCK" },
    { value = "fav",       key = "CFG_DBL_FAV" },
    { value = "pin",       key = "CFG_DBL_PIN" },
}

-- The right-click menu itself is UI/NoteContextMenu.lua (ALL-148); it reaches
-- these through the kit, so the double-click and the menu share one body.
BNB._NoteListKit = {
    NOTE_ACTIONS   = NOTE_ACTIONS,
    NoteIsLocked   = NoteIsLocked,
    StickyOpenKind = StickyOpenKind,
    DuplicateNote  = DuplicateNote,
    OpenAsSticky   = OpenAsSticky,   -- a toggle: callers check StickyOpenKind first
}

--------------------------------------------------------------------------------
-- DRAG HELPERS
-- Reordering (a drop between rows) needs Custom sort and an unfiltered list.
-- A drop on a folder header (into it) or the Notes header (out of folders)
-- works in every sort mode (ALL-510 S3, Dukul 2026-10-19). The folder view
-- takes drops on its folder headers and No folder only, no reordering (its
-- notes are A-Z); the tag tree has no drag (Dukul, 2026-10-19: a drag there
-- reordered the list and filed by a list row's old section).
--------------------------------------------------------------------------------
local function FolderView()
    local db = BigNoteBoxDB
    return db and db.tagTreeMode and db.treeSource == "folders" or false
end

local function CanDragReorder()
    local db = BigNoteBoxDB
    return (db.sortBy == "custom")
        and not db.tagTreeMode
        and (currentFilter == "")
        and (currentTagFilter == nil)
end

local function CanDragToFolder()
    local db = BigNoteBoxDB
    if db and db.tagTreeMode and not FolderView() then return false end
    return BNB.Folders ~= nil and BNB.FoldersEnabled() and BNB.Folders.Any()
end

-- Ghost and drop line in BNB green, the Sidebar's ACTIVE_R/G/B (ALL-98)
local DRAG_R, DRAG_G, DRAG_B = 0.40, 0.85, 0.40

local function GetOrCreateDragGhost()
    if _dragGhost then return _dragGhost end
    local g = CreateFrame("Frame", nil, UIParent)
    g:SetFrameStrata("TOOLTIP")
    g:SetSize(200, ENTRY_H_NORMAL)
    BNB.SetBackdrop(g, 0.15, 0.15, 0.20, 0.85, DRAG_R, DRAG_G, DRAG_B, 1)
    local lbl = g:CreateFontString(nil, "OVERLAY", "BNBFontNormal")
    lbl:SetPoint("LEFT", g, "LEFT", 8, 0)
    lbl:SetPoint("RIGHT", g, "RIGHT", -8, 0)
    lbl:SetJustifyH("LEFT")
    lbl:SetTextColor(DRAG_R, DRAG_G, DRAG_B, 1)
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
    l:SetColorTexture(DRAG_R, DRAG_G, DRAG_B, 0.9)
    l:Hide()
    _dropLine = l
    return l
end

-- The header the carried notes would drop on, lit in the drag green
local function LightHeader(hdr)
    if _dragHeader == hdr then return end
    if _dragHeader and _dragHeader._dropHL then _dragHeader._dropHL:Hide() end
    _dragHeader = hdr
    if not hdr then return end
    local t = hdr._dropHL
    if not t then
        t = hdr:CreateTexture(nil, "BACKGROUND")
        t:SetAllPoints()
        t:SetColorTexture(DRAG_R, DRAG_G, DRAG_B, 0.22)
        hdr._dropHL = t
    end
    t:Show()
end

-- The header under the pointer: a folder's (its id) or the Notes header
-- (false); only inside the list's visible part
local function HeaderUnderCursor()
    local child, sf = BNB._listScrollChild, BNB._listScrollFrame
    if not child or (sf and not sf:IsMouseOver()) then return nil end
    -- The folder view: its own headers (Features/TagTree.lua)
    if FolderView() then
        if BNB.TagTreeDropHeader then return BNB.TagTreeDropHeader() end
        return nil
    end
    for _, hdr in ipairs(child._folderHdrs or {}) do
        if hdr:IsShown() and hdr._folderID and hdr:IsMouseOver() then return hdr, hdr._folderID end
    end
    local nh = child._regularHdr
    if nh and nh:IsShown() and nh:IsMouseOver() then return nh, false end
end

local _dragScroll = nil   -- the list's scroll before a folder view drag closed every header

-- The custom order: carried (note ids, in the order carried) go as one block
-- before targetID, or after it when after is true. Placed by id, not index:
-- noteOrder also holds pinned notes and notes the sidebar / favourite / task
-- filters hide, anywhere in the sequence (ALL-98). Shared with the explorer
-- view's tile drag (ALL-414). Changes noteOrder only, redraws nothing.
function BNB.MoveNotesInOrder(carried, targetID, after)
    local order = (BNB.NotesDB() or {}).noteOrder
    if not (order and carried and targetID) then return end
    local isCarried = {}
    for _, id in ipairs(carried) do isCarried[id] = true end
    if isCarried[targetID] then return end
    local kept, fromIdx = {}, nil
    for _, id in ipairs(order) do
        if isCarried[id] then fromIdx = fromIdx or (#kept + 1)
        else kept[#kept + 1] = id end
    end
    if not fromIdx then return end
    local toIdx = nil
    for i, id in ipairs(kept) do
        if id == targetID then toIdx = i; break end
    end
    if toIdx then
        if after then toIdx = toIdx + 1 end
    else
        toIdx = fromIdx   -- target gone: put them back
    end
    local block = {}
    for _, id in ipairs(carried) do
        if (BNB.NotesDB().notes or {})[id] then block[#block + 1] = id end
    end
    -- Rebuilt in place: noteOrder is the saved table itself
    local out = {}
    for i = 1, toIdx - 1 do out[#out + 1] = kept[i] end
    for _, id in ipairs(block) do out[#out + 1] = id end
    for i = toIdx, #kept do out[#out + 1] = kept[i] end
    for i = #order, 1, -1 do order[i] = nil end
    for i, id in ipairs(out) do order[i] = id end
end

local function EndDrag(commit)
    BNB.ClearCursor()   -- ALL-95
    local ghost = _dragGhost
    if ghost then ghost:Hide(); ghost:SetScript("OnUpdate", nil) end
    local dl = _dropLine; if dl then dl:Hide() end
    local folder, ids = _dragFolder, _dragIDs
    LightHeader(nil)
    local FD = BNB.Folders

    if commit and _dragNoteID and folder ~= nil and FD and ids then
        -- Onto a header: into that folder (it opens), or out of folders
        FD.Move(ids, folder or nil)
        if folder then FD.SetOpen(folder, true) end

    -- Reorder noteOrder: move the dragged id next to the target row's id.
    -- Placed by id, not index: noteOrder also holds pinned notes and notes the
    -- sidebar / favourite / task filters hide, anywhere in the sequence (ALL-98).
    elseif commit and _dragNoteID and _dragTargetID and _dragTargetID ~= _dragNoteID then
        local order = (BNB.NotesDB() or {}).noteOrder
        -- Every carried note goes, as one block in the order carried: Select
        -- mode's picks too, not only the grabbed one (Dukul, 2026-10-20, IS9:
        -- three carried into a folder's rows, one moved; the header drop
        -- above already took all)
        local carried = ids or { _dragNoteID }
        BNB.MoveNotesInOrder(carried, _dragTargetID, _dragAfter)
        if order then
            -- Dropped among a folder's rows or the Notes rows: filed there
            -- too, so they stay where they were dropped (ALL-510 S3)
            if FD and _dragSection ~= nil and _dragSection ~= "pinned" then
                local want = (_dragSection ~= "notes") and _dragSection or nil
                local move = {}
                for _, id in ipairs(carried) do
                    local n = BNB.GetNote(id)
                    if n and FD.Of(n) ~= want then move[#move + 1] = id end
                end
                if #move > 0 then FD.Move(move, want) end
            end
            if BNB.RefreshNoteList then BNB.RefreshNoteList() end
        end
    end

    _dragNoteID   = nil
    _dragTargetID = nil
    _dragAfter    = false
    _dragFolder   = nil
    _dragSection  = nil
    _dragIDs      = nil
    -- A folder view drag: headers back as they were (the target folder was
    -- opened by the move), then the scroll where it was
    if _dragScroll then
        local sc = _dragScroll
        _dragScroll = nil
        if BNB.TagTreeDragCollapse then BNB.TagTreeDragCollapse(false) end
        local sf = BNB._listScrollFrame
        if sf then
            C_Timer.After(0, function()
                local max = sf:GetVerticalScrollRange() or 0
                sf:SetVerticalScroll(math.min(sc, max))
            end)
        end
    end
end

--------------------------------------------------------------------------------
-- MULTI-SELECT HELPERS
--------------------------------------------------------------------------------
local function UpdateMultiActionBtns(n)
    local label = n > 0 and ("(" .. n .. ")") or "(0)"
    local en    = n > 0
    if BNB._multiDeleteBtn then
        BNB._multiDeleteBtn:SetText(string.format(L["MULTI_DELETE_FMT"], label))
        BNB._multiDeleteBtn:SetEnabled(en)
    end
    if BNB._multiCopyMoveBtn then
        BNB._multiCopyMoveBtn:SetText(string.format(L["MULTI_COPYMOVE_FMT"], label))
        BNB._multiCopyMoveBtn:SetEnabled(en)
    end
    if BNB._multiExportBtn then
        BNB._multiExportBtn:SetText(string.format(L["MULTI_EXPORT_FMT"], label))
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

-- Select mode ends on a press anywhere but the note list, the Select mode
-- buttons, the right-click menu or a confirm popup (Dukul, 2026-10-03).
-- GLOBAL_MOUSE_DOWN is listened to only while Select mode is on.
local _multiWatch
local function MouseOnPopup()
    for i = 1, 4 do   -- StaticPopup1..4 on every client (no STATICPOPUP_NUMDIALOGS any more)
        local p = _G["StaticPopup" .. i]
        if p and p:IsShown() and p:IsMouseOver() then return true end
    end
    return false
end
local function MouseInMultiArea()
    if BNB.listPane and BNB.listPane:IsVisible() and BNB.listPane:IsMouseOver() then return true end
    -- The top bar menu icon too: it holds the actions a narrow window has no room for (ALL-464)
    for _, b in ipairs({ BNB._multiSelBtn, BNB._multiSelectAllBtn, BNB._multiDeleteBtn,
                         BNB._multiCopyMoveBtn, BNB._multiExportBtn, BNB._toolbarMenuBtn }) do
        if b and b:IsVisible() and b:IsMouseOver() then return true end
    end
    if BNB.ContextMenu and BNB.ContextMenu.IsMouseOver() then return true end
    return MouseOnPopup()
end
local function WatchMultiClicks(on)
    if not _multiWatch then
        _multiWatch = CreateFrame("Frame")
        _multiWatch:SetScript("OnEvent", function()
            if _multiMode and not MouseInMultiArea() then BNB.SetMultiMode(false) end
        end)
    end
    if on then pcall(_multiWatch.RegisterEvent, _multiWatch, "GLOBAL_MOUSE_DOWN")
    else _multiWatch:UnregisterEvent("GLOBAL_MOUSE_DOWN") end
end

function BNB.SetMultiMode(enabled)
    _multiMode = enabled
    _multiSel  = {}
    WatchMultiClicks(enabled)
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
        BNB._multiSelBtn:SetText(enabled and L["CANCEL"] or L["MW_SELECT_BTN"])
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

-- Confirm text for a bulk delete (ALL-58): the first few titles in list order,
-- then "...and N more", plus a red warning when the selection is every note.
-- Titles are shortened and "|" is doubled so a title cannot break the popup.
local MULTI_TITLES_SHOWN = 3
local MULTI_TITLE_MAX    = 40
local function MultiDeleteSummary(ids)
    local lines = {}
    for i = 1, math.min(#ids, MULTI_TITLES_SHOWN) do
        local note  = BNB.GetNote(ids[i])
        local title = note and note.title ~= "" and note.title or L["UNTITLED"]
        if #title > MULTI_TITLE_MAX then
            -- Cut on a UTF-8 lead byte so a CJK title is never split mid-character
            local cut = MULTI_TITLE_MAX
            while cut > 1 and title:byte(cut + 1) and title:byte(cut + 1) >= 0x80
                and title:byte(cut + 1) < 0xC0 do
                cut = cut - 1
            end
            title = title:sub(1, cut) .. "..."
        end
        lines[#lines + 1] = "|cffffd100" .. title:gsub("|", "||") .. "|r"
    end
    if #ids > MULTI_TITLES_SHOWN then
        lines[#lines + 1] = string.format(L["POPUP_MULTI_MORE"], #ids - MULTI_TITLES_SHOWN)
    end
    local live = 0
    for _ in pairs(BNB.NotesDB().notes) do live = live + 1 end
    if #ids >= live then
        lines[#lines + 1] = "\n|cffff5555" .. L["POPUP_MULTI_ALL_WARN"] .. "|r"
    end
    return table.concat(lines, "\n")
end

-- The selected notes in list order, live notes only
function BNB.GetMultiSelectedOrdered()
    local ids = {}
    for _, id in ipairs(BNB.NotesDB().noteOrder) do
        if _multiSel[id] and BNB.GetNote(id) then ids[#ids + 1] = id end
    end
    return ids
end

-- permanent = true skips the trash even while it is on (the Select mode
-- right-click menu's "Delete permanently", ALL-234)
function BNB.DeleteMultiSelected(permanent)
    -- Selected ids in note order (so the confirm lists them as the list does)
    BNB.ConfirmDeleteNotes(BNB.GetMultiSelectedOrdered(), permanent)
end

-- The bulk delete with its confirm, for any ids in display order (Select
-- mode, the explorer view's Delete button, ALL-414)
function BNB.ConfirmDeleteNotes(ids, permanent)
    if not ids or #ids == 0 then return end
    local warn = BigNoteBoxDB and BigNoteBoxDB.warnBeforeDelete ~= false
    -- A single note follows "Warn before delete"; two or more always confirm
    if #ids == 1 and not warn then
        if BNB.DeleteNotes then BNB.DeleteNotes(ids, permanent) end
        if BNB.SetMultiMode then BNB.SetMultiMode(false) end
        return
    end
    local which = (not permanent and BNB.TrashEnabled and BNB.TrashEnabled())
        and "BNB_DELETE_MULTI_TRASH" or "BNB_DELETE_MULTI"
    local popup = StaticPopup_Show(which, tostring(#ids), MultiDeleteSummary(ids), ids)
    if popup then popup.data = ids end
end

-- Returns true while the list is in multi-select mode (the Select button reads
-- this instead of keeping its own flag, which went stale on exit: ALL-58)
function BNB.IsMultiMode()
    return _multiMode
end

-- Selects exactly the notes the list is showing: search text, tag filter and
-- collapsed tag-tree groups all apply. Hidden notes are never selected (ALL-58:
-- Select All used to select every note behind an active search).
function BNB.SelectAll()
    if not _multiMode then return end
    _multiSel = {}
    local n = 0
    -- Every note the view holds, closed folders and tag headers included
    -- (Dukul, 2026-10-20: it picked only the rows drawn); system notes are
    -- never in these lists, so they are never picked
    local db = BigNoteBoxDB
    if db and db.tagTreeMode and BNB.TagTreeNoteSet then
        for id in pairs((BNB.TagTreeNoteSet())) do _multiSel[id] = true; n = n + 1 end
    else
        for _, note in ipairs(BNB.GetOrderedNotes(currentFilter, currentTagFilter)) do
            if not _multiSel[note.id] then _multiSel[note.id] = true; n = n + 1 end
        end
    end
    UpdateMultiActionBtns(n)
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
-- The normal-mode row art starts ROW_ART_L in from the list's left edge, so
-- its rounded end is not squashed against it (ALL-254); skin fills stay full
local ROW_ART_L = 3
local function ArtPoints(tex, rowArt)
    if not rowArt then tex:SetAllPoints(); return end
    local btn = tex:GetParent()
    tex:SetPoint("TOPLEFT",     btn, "TOPLEFT",     ROW_ART_L, 0)
    tex:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 0, 0)
end

local function CreateListEntry(parent)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetHeight(ENTRY_H)
    btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    local _lastClick, _lastClickID  -- double-click detection state
    local _deselectTimer            -- pending deselect timer handle

    -- Normal mode draws the row art; skin mode the flat colour fills
    local rowArt = not (BigNoteBoxDB and BigNoteBoxDB.skinMode)
    btn._rowArt = rowArt

    -- Faction crest of a player note (ALL-305): icon-high, subdued, at the
    -- right edge, under the row art, the icon and the text
    local factionTex = btn:CreateTexture(nil, "BACKGROUND", nil, 0)
    factionTex:SetTexCoord(6/128, 122/128, 6/128, 122/128)   -- the art's empty rim
    factionTex:SetAlpha(FACTION_ALPHA)
    factionTex:Hide()
    btn._factionTex = factionTex

    -- Selection highlight: ARTWORK layer so OVERLAY text draws on top of it.
    -- The normal-mode art goes on BACKGROUND, under the icon (ARTWORK) too
    -- (Dukul 2026-10-03); skin mode's faint fill stays where it was.
    local selBg = btn:CreateTexture(nil, rowArt and "BACKGROUND" or "ARTWORK", nil, 1)
    ArtPoints(selBg, rowArt)
    if rowArt then selBg:SetTexture(ROW_SEL_TEX); TintRowArt(selBg)
    else selBg:SetColorTexture(unpack(COL_SEL_BG)) end
    selBg:Hide()
    btn._selBg = selBg

    -- Multi-select highlight. Normal mode: Dukul's row art (2026-10-03), on
    -- BACKGROUND over the selection and under the hover; skin mode: blue tint
    local multiSelBg = btn:CreateTexture(nil, rowArt and "BACKGROUND" or "ARTWORK", nil, 2)
    ArtPoints(multiSelBg, rowArt)
    if rowArt then multiSelBg:SetTexture(ROW_MULTI_TEX); TintRowArt(multiSelBg)
    else multiSelBg:SetColorTexture(0.20, 0.45, 0.90, 0.18) end
    multiSelBg:Hide()
    btn._multiSelBg = multiSelBg

    -- Hover. Skin mode: the HIGHLIGHT layer, which draws over everything.
    -- Normal mode: the row art under the icon and text like the selection,
    -- so it is a BACKGROUND texture shown while the row is hovered (Dukul 2026-10-03)
    if rowArt then
        local hiBg = btn:CreateTexture(nil, "BACKGROUND", nil, 3)   -- over the multi-select art
        ArtPoints(hiBg, true)
        hiBg:SetTexture(ROW_HOVER_TEX); TintRowArt(hiBg)
        hiBg:Hide()
        btn._hiBg = hiBg
        btn:HookScript("OnEnter", function() hiBg:Show() end)
        btn:HookScript("OnLeave", function() hiBg:Hide() end)
        btn:HookScript("OnHide",  function() hiBg:Hide() end)   -- a row reused under the pointer
    else
        local hiBg = btn:CreateTexture(nil, "HIGHLIGHT")
        hiBg:SetAllPoints()
        hiBg:SetColorTexture(1, 1, 1, 0.05)
    end

    -- Hover: the compact note tooltip (ALL-372 S3, UI/NoteTooltip.lua): tl;dr,
    -- alarm, situations, waypoints; the collapsed list puts the title on top
    -- (ALL-428, Dukul 2026-10-10). Not while a note is being dragged
    btn:HookScript("OnEnter", function(self)
        if _dragNoteID or not self._noteID then return end
        BNB.ShowNoteListTooltip(self, self._noteID, BNB._listCollapsed)
    end)
    local function HideTip(self)
        if GameTooltip:IsOwned(self) then GameTooltip:Hide() end
    end
    btn:HookScript("OnLeave", HideTip)
    btn:HookScript("OnHide",  HideTip)

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
    -- Markers: layered art in normal mode, the single pictures tinted to the
    -- skin in skin mode (BNB.CreateIconMarker, UI/Widgets.lua)
    local alarmOverlay = BNB.CreateIconMarker(overlayHost, "alarm")
    alarmOverlay:SetSize(ovSz, ovSz)
    alarmOverlay:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", 2, -2)
    btn._alarmTex = alarmOverlay

    -- Favorite star overlay — top-right of icon (Dukul 2026-10-08: swapped with situation)
    local favOverlay = BNB.CreateIconMarker(overlayHost, "favorite")
    favOverlay:SetSize(ovSz, ovSz)
    favOverlay:SetPoint("TOPRIGHT", icon, "TOPRIGHT", 2, 2)
    btn._favTex = favOverlay

    -- Situation marker — top-left, child of overlayHost, always above border frame
    local situOverlay = BNB.CreateIconMarker(overlayHost, "situation")
    situOverlay:SetSize(ovSz, ovSz)
    situOverlay:SetPoint("TOPLEFT", icon, "TOPLEFT", -2, 2)
    btn._situTex = situOverlay

    -- Scope badge — bottom-left of icon; shows the class icon of the owning
    -- character when the note is character-scoped.
    local scopeOverlay = BNB.CreateClassMarker(overlayHost)   -- round + ring in normal mode
    scopeOverlay:SetSize(ovSz, ovSz)
    scopeOverlay:SetPoint("BOTTOMLEFT", icon, "BOTTOMLEFT", -2, -2)
    btn._scopeTex = scopeOverlay

    -- Location marker: the note places a waypoint when its situation matches
    -- (BNB.HasActiveWaypoint). Left side, middle (Dukul, 2026-10-08)
    local locOverlay = BNB.CreateIconMarker(overlayHost, "location")
    locOverlay:SetSize(ovSz, ovSz)
    locOverlay:SetPoint("LEFT", icon, "LEFT", -2, 0)
    btn._locTex = locOverlay

    -- Attachment count badge — small gold number right-middle inside icon.
    -- Right-middle avoids the pin (bottom-right), scope (bottom-left),
    -- situation (top-left), and favorite (top-right) overlays.
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
    BNB.SetHeaderColor(badgeLbl)
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
    lockIcon:SetTexture("Interface\\AddOns\\BigNoteBox\\Assets\\" .. BNB.AbIcon("lock"))
    BNB.TintAbIcon(lockIcon)
    lockIcon:SetAlpha(0.65)
    lockIcon:Hide()
    btn._lockIcon = lockIcon

    -- Task icon: small ui-tasks.tga shown when note has tasks.
    -- Sits to the left of the lock icon (or title if no lock). Shown/hidden in refresh.
    local taskIcon = btn:CreateTexture(nil, "OVERLAY")
    taskIcon:SetSize(11, 11)
    taskIcon:SetPoint("TOPLEFT", btn, "TOPLEFT", textLeft, -8)
    taskIcon:SetTexture("Interface\\AddOns\\BigNoteBox\\Assets\\UI\\ui-tasks")
    BNB.TintUIIcon(taskIcon)   -- white art: gold / skin accent
    taskIcon:SetAlpha(0.7)
    taskIcon:Hide()
    btn._taskIcon = taskIcon

    local titleLbl = btn:CreateFontString(nil, "OVERLAY", "BNBFontNormal")
    -- Title left anchor shifts right by 13px per shown prefix icon (task/lock).
    titleLbl:SetPoint("TOPLEFT",  btn, "TOPLEFT",  textLeft, -6)
    titleLbl:SetPoint("TOPRIGHT", btn, "TOPRIGHT", -20, -6)
    titleLbl:SetJustifyH("LEFT")
    titleLbl:SetTextColor(unpack(COL_WHITE))
    titleLbl:SetMaxLines(1)
    titleLbl:SetWordWrap(false)
    btn._titleLbl = titleLbl

    local previewLbl = btn:CreateFontString(nil, "OVERLAY", "BNBFontNormalSmall")
    previewLbl:SetPoint("TOPLEFT",  btn, "TOPLEFT",  textLeft, -22)
    previewLbl:SetPoint("TOPRIGHT", btn, "TOPRIGHT", -20, -22)
    previewLbl:SetPoint("BOTTOM",   btn, "BOTTOM",    0,  4)
    previewLbl:SetJustifyH("LEFT")
    previewLbl:SetJustifyV("TOP")
    previewLbl:SetTextColor(unpack(COL_GREY))
    previewLbl:SetMaxLines(2)
    previewLbl:SetWordWrap(true)
    btn._previewLbl = previewLbl

    -- Double-click -> the action picked in Settings > Notes (ALL-100)
    btn:SetScript("OnClick", function(self, mouseBtn)
        -- A system note (ALL-511): opened to read, never picked in Select
        -- mode, no double-click action; right-click is its own short menu
        if self._sys then
            if mouseBtn == "RightButton" then
                if BNB.ShowSystemNoteMenu then BNB.ShowSystemNoteMenu(self, self._noteID) end
            elseif BNB._currentNoteID ~= self._noteID then
                BNB.SaveCurrentNote(); BNB.SelectNote(self._noteID)
            end
            return
        end
        if mouseBtn == "RightButton" then
            -- Select mode: the menu for the whole selection (ALL-234); a row
            -- not yet picked is added first, so the menu covers what you clicked
            if _multiMode and BNB.ShowMultiNoteContextMenu then
                if not _multiSel[self._noteID] then ToggleMultiSelect(self._noteID) end
                BNB.ShowMultiNoteContextMenu(self, BNB.GetMultiSelectedOrdered())
                return
            end
            BNB.ShowNoteContextMenu(self, self._noteID)
            return
        end

        -- Shift+click starts Select mode (Dukul, 2026-10-04): the clicked note
        -- is picked, and the note open in the editor too while the list shows
        -- it; from then on clicks pick as in Select mode
        if not _multiMode and IsShiftKeyDown() then
            local openID = BNB._currentNoteID
            BNB.SetMultiMode(true)
            if openID and openID ~= self._noteID then
                for _, n in ipairs(BNB.GetOrderedNotes(currentFilter, currentTagFilter)) do
                    if n.id == openID then _multiSel[openID] = true; break end
                end
            end
            ToggleMultiSelect(self._noteID)   -- picks it, redraws, counts the buttons
            BNB.SaveCurrentNote(); BNB.SelectNote(self._noteID)
            return
        end

        -- Multi-select mode: toggle checkbox AND still load the note for preview
        if _multiMode then
            -- The release that ended a drag is not a click on the row: it
            -- would unpick the note just carried (ALL-510 S3)
            if _dropAt and GetTime() - _dropAt < 0.1 then return end
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
            local act = NOTE_ACTIONS[BigNoteBoxDB.listDoubleClick or "settings"]
                     or NOTE_ACTIONS.settings
            act(self._noteID)
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
                BNB.Editor.SetCurrent(nil)
                if BigNoteBoxDB then BigNoteBoxDB.selectedNoteID = nil end
                if BNB.LoadNoteInEditor then BNB.LoadNoteInEditor(nil) end
                if BNB.RefreshNoteList  then BNB.RefreshNoteList() end
            end)
            return
        end

        BNB.SaveCurrentNote(); BNB.SelectNote(self._noteID)
    end)

    -- Whole-entry hold-to-drag: 150ms hold activates drag mode. Reordering
    -- needs Custom sort; onto a folder works in every sort (ALL-510 S3)
    local _holdTimer = nil
    btn:SetScript("OnMouseDown", function(self, mouseBtn)
        HideTip(self)   -- out of the way of a drag or the right-click menu
        if mouseBtn ~= "LeftButton" then return end
        local noteID = self._noteID; if not noteID or self._sys then return end
        local noteCheck = BNB.GetNote(noteID)
        -- Pinned notes are not reordered (they sort A-Z), but can be filed
        local reorder  = CanDragReorder() and not (noteCheck and noteCheck.pinned)
        local toFolder = CanDragToFolder()
        if not reorder and not toFolder then return end
        -- ALL-95: holding hand once the note is carried (no open hand while
        -- held first: Dukul, 2026-09-27, "Looks weird")
        _holdTimer = C_Timer.NewTimer(0.15, function()
            _holdTimer = nil
            _dragNoteID = noteID
            -- Select mode: a picked row carries every pick into a folder
            -- (reordering still moves the one row)
            if _multiMode and _multiSel[noteID] then
                _dragIDs = BNB.GetMultiSelectedOrdered()
            else
                _dragIDs = { noteID }
            end
            -- The folder all of them are in (false when they differ), and
            -- whether any is in one: a header that would change nothing is
            -- not a target
            local FD = BNB.Folders
            local same, anyIn
            for i, id in ipairs(_dragIDs) do
                local fid = FD and FD.Of(BNB.GetNote(id))
                if fid then anyIn = true end
                if i == 1 then same = fid or false elseif same ~= (fid or false) then same = nil end
            end
            BNB.ShowCursor("hold")
            -- Folder view: every header closes while the note is carried, so
            -- the folders fit as targets (Dukul, 2026-10-19); EndDrag reopens
            if FolderView() and BNB.TagTreeDragCollapse then
                local sf = BNB._listScrollFrame
                _dragScroll = sf and sf:GetVerticalScroll() or 0
                BNB.TagTreeDragCollapse(true)
                if sf then sf:SetVerticalScroll(0) end
            end
            local note  = BNB.GetNote(noteID)
            local ghost = GetOrCreateDragGhost()
            if ghost._lbl then
                if #_dragIDs > 1 then
                    ghost._lbl:SetText(string.format(L["FOLDER_DRAG_N_FMT"], #_dragIDs))
                else
                    ghost._lbl:SetText(note and note.title or "")
                end
            end
            ghost:SetSize(BNB._listScrollFrame and BNB._listScrollFrame:GetWidth() or 200, ENTRY_H)
            local mx, my = GetCursorPosition()
            local sc = UIParent:GetEffectiveScale()
            ghost:ClearAllPoints()
            ghost:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", mx/sc - 10, my/sc + ENTRY_H/2)
            ghost:Show()
            ghost:SetScript("OnUpdate", function()
                if not _dragNoteID then ghost:SetScript("OnUpdate", nil); return end
                -- Released where the row's own OnMouseUp cannot see it (the
                -- row was hidden by a redraw, e.g. the folder view closing
                -- its headers): the drop happens here
                if not IsMouseButtonDown("LeftButton") then
                    _dropAt = GetTime()
                    EndDrag(true)
                    return
                end
                local cx, cy = GetCursorPosition()
                local s2 = UIParent:GetEffectiveScale()
                ghost:ClearAllPoints()
                ghost:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", cx/s2 - 10, cy/s2 + ENTRY_H/2)

                local child = BNB._listScrollChild
                if not child then return end
                local childTopY = child:GetTop()
                if not childTopY then return end

                -- A header under the pointer wins over the rows
                local hdr, fid
                if toFolder then hdr, fid = HeaderUnderCursor() end
                if hdr and fid and same == fid then hdr = nil end          -- already in it
                if hdr and fid == false and not anyIn then hdr = nil end   -- none in a folder
                LightHeader(hdr)
                if hdr then
                    _dragFolder, _dragTargetID, _dragSection = fid, nil, nil
                    if _dropLine then _dropLine:Hide() end
                    return
                end
                _dragFolder = nil
                if not reorder then
                    _dragTargetID, _dragSection = nil, nil
                    if _dropLine then _dropLine:Hide() end
                    return
                end

                -- ALL-98: snap to the rows as drawn, not a modelled layout. The
                -- old model counted every note (the list may be filtered by the
                -- sidebar, favourites or tasks), assumed ENTRY_H rows with headers
                -- (collapsed mode has neither) and measured the cursor in UIParent
                -- scale while the rows live in the main window's scale.
                -- Pinned rows are not targets.
                local rows = {}
                for _, b in ipairs(listEntries) do
                    if b:IsShown() and b._noteID and not b._sys and b:GetTop() then
                        local nt = BNB.GetNote(b._noteID)
                        if nt and not nt.pinned then rows[#rows + 1] = b end
                    end
                end
                local nRows = #rows
                if nRows == 0 then return end
                -- Top to bottom on screen (TagTree.lua reuses these rows in its own order)
                table.sort(rows, function(a, b) return a:GetTop() > b:GetTop() end)

                -- Boundary k (1..nRows) = top of row k; nRows+1 = bottom of the last.
                -- All in the rows' own coordinates, cursor converted to match.
                local cursorY = cy / child:GetEffectiveScale()
                local best, bestDist, bestY = 1, math.huge, rows[1]:GetTop()
                for k = 1, nRows + 1 do
                    local y = (k <= nRows) and rows[k]:GetTop() or rows[nRows]:GetBottom()
                    local dist = math.abs(cursorY - y)
                    if dist < bestDist then best, bestDist, bestY = k, dist, y end
                end
                if best <= nRows then
                    _dragTargetID, _dragAfter = rows[best]._noteID, false
                    _dragSection = rows[best]._section
                else
                    _dragTargetID, _dragAfter = rows[nRows]._noteID, true
                    _dragSection = rows[nRows]._section
                end

                local dl = GetOrCreateDropLine()
                dl:ClearAllPoints()
                local lineY = bestY - childTopY + 1   -- 2 px line centred on the boundary
                dl:SetPoint("TOPLEFT",  child, "TOPLEFT",  0, lineY)
                dl:SetPoint("TOPRIGHT", child, "TOPRIGHT", 0, lineY)
                dl:Show()
            end)
        end)
    end)
    btn:SetScript("OnMouseUp", function(self, mouseBtn)
        if mouseBtn ~= "LeftButton" then return end
        if _holdTimer then _holdTimer:Cancel(); _holdTimer = nil end
        BNB.ClearCursor()   -- ALL-95
        if _dragGhost then _dragGhost:SetScript("OnUpdate", nil) end
        if _dragNoteID then _dropAt = GetTime(); EndDrag(true) end
    end)

    return btn
end

BNB._createListEntry = function(parent) return CreateListEntry(parent) end

-- Row icon border (PERF-01): the backdrop is set only when its file or size
-- changed, since every list refresh re-populates every row.
local ROW_BORDER_INSETS = { left = 0, right = 0, top = 0, bottom = 0 }
-- bright: the note's border brightness, 0..200 % (nil = 100; ALL-142)
local function SetRowBorder(bf, edgeFile, edgeSize, r, g, b, a, bright)
    local sig = edgeFile .. "|" .. edgeSize
    if bf._sig ~= sig then
        local ok = pcall(bf.SetBackdrop, bf, {
            edgeFile = edgeFile, edgeSize = edgeSize, insets = ROW_BORDER_INSETS,
        })
        bf._sig = ok and sig or nil
        if not ok then return end
        bf:SetBackdropColor(0, 0, 0, 0)
    end
    BNB.BorderBright.SetBackdropBorder(bf, bright, r, g, b, a)
end

-- Preview text per note (PERF-01), kept until the body, rich mode or source
-- changes. Lua strings are interned, so comparing the body is one pointer
-- compare. Only the start of the body is cleaned: two or three lines show.
local PREVIEW_CHARS = 1000
local _previewCache = setmetatable({}, { __mode = "k" })
local function PreviewText(note)
    local c = _previewCache[note]
    local raw = note.body or ""
    local rich = BNB.AdvancedMode.IsRich(note)   -- Rich Notes off: markup shows (ALL-343)
    if c and c.body == raw and c.rich == rich and c.src == note.source then
        return c.text
    end
    local body = raw:sub(1, PREVIEW_CHARS):match("^%s*(.-)%s*$")
    -- Strip rich note markup tags so preview shows plain text only
    if rich then
        -- For inspect/target notes, skip the first {h1} block (player/target
        -- name) since it duplicates the note title shown above the preview.
        if note.source == "inspect" or note.source == "target" then
            body = body:gsub("^%s*{h1[^}]*}.-{/h1}%s*", "", 1)
        end
        body = body:gsub("{/?h%d+:?[cr]?}", "")
        body = body:gsub("{/?p:?[clr]?}", "")
        body = body:gsub("{img:[^}]+}", "")
        body = body:gsub("{icon:[^}]+}", "")
        body = body:gsub("{atlas:[^}]+}", "")
        body = body:gsub("{col:%x%x%x%x%x%x}", "")
        body = body:gsub("{/col}", "")
        body = body:gsub("{br}", "")
        body = body:gsub("{link%*[^*}]+%*([^}]*)}", "%1")
        -- Collapse runs of blank lines so they don't eat the line budget
        body = body:gsub("\n%s*\n+", "\n")
        body = body:match("^%s*(.-)%s*$") or body
    end
    _previewCache[note] = { body = raw, rich = rich, src = note.source, text = body }
    return body
end

-- Normal-mode row art: stretched over the row under the icon, or in the
-- collapsed list the square pictures, ICON_SIZE + 12 on a side, centred on
-- the icon and drawn over it (Dukul 2026-10-05); the badges sit on their
-- own frame above both
local function ShapeRowArt(btn, collapsed)
    if not btn._rowArt then return end
    local sq = ICON_SIZE + 12
    local function Shape(tex, wide, square, sub)
        if not tex then return end
        tex:ClearAllPoints()
        if collapsed then
            tex:SetTexture(square)
            tex:SetDrawLayer("OVERLAY", sub + 1)   -- over the icon border (OVERLAY 0)
            tex:SetSize(sq, sq)
            tex:SetPoint("CENTER", btn._icon, "CENTER", 0, 0)
        else
            tex:SetTexture(wide)
            tex:SetDrawLayer("BACKGROUND", sub)
            ArtPoints(tex, true)
        end
    end
    if btn._artCollapsed ~= collapsed then
        btn._artCollapsed = collapsed
        Shape(btn._selBg,      ROW_SEL_TEX,   ROW_SEL_SQ,   1)
        Shape(btn._multiSelBg, ROW_MULTI_TEX, ROW_MULTI_SQ, 2)
        Shape(btn._hiBg,       ROW_HOVER_TEX, ROW_HOVER_SQ, 3)
    elseif collapsed then
        -- Same shape, but the list mode (icon size) may have changed
        btn._selBg:SetSize(sq, sq); btn._multiSelBg:SetSize(sq, sq)
        if btn._hiBg then btn._hiBg:SetSize(sq, sq) end
    end
end

-- "Horde" / "Alliance" for a note about a player, nil otherwise (ALL-305).
-- The saved token first, then the faction tag (notes from before the field).
local function PlayerNoteFaction(note)
    local player = note.source == "inspect"
        or (note.source == "target" and note.targetPlayerKey ~= nil)
    if not player then return nil end
    local f = note.inspectFaction or note.targetFaction
    if FACTION_ART[f] then return f end
    for _, t in ipairs(note.tags or {}) do
        if FACTION_ART[t] then return t end
    end
    return nil
end

-- A note's icon as the list draws it: its picture (NPC face, live target
-- portrait), then its icon frame or LSM edge border, else the default
-- tooltip edge. host owns the border frame (host._borderFrame); size = the
-- icon's size for the icon frame (nil = its width). The explorer view's
-- tiles use it too (ALL-414), so a tile looks like the row.
local function PaintNoteIcon(host, icon, note, size)
    local noteIcon = BNB.NpcNoteIcon and BNB.NpcNoteIcon(note) or note.icon
    local iconPath = (noteIcon and noteIcon ~= "") and noteIcon or DEFAULT_ICON
    icon:SetTexture(iconPath)
    -- NPC notes: the NPC's face from its saved display ID, no target needed
    -- (ALL-46, Features/TargetNote.lua). Falls back to iconPath until resolved.
    if BNB.SetNpcNotePortrait then BNB.SetNpcNotePortrait(icon, note) end

    -- Live portrait: if this is a target or inspect note and that unit is
    -- currently targeted, replace the icon with the actual unit portrait.
    -- SetPortraitTexture renders the live unit face/model into the texture widget.
    -- Players only get this live: a saved ID cannot carry their customizations.
    if BNB.NoteMatchesTarget(note) then
        pcall(SetPortraitTexture, icon, "target")
    end

    -- Icon frame (ALL-127) takes over from the LSM edge border below when set
    local hasIconFrame = BNB.ApplyIconFrame and BNB.ApplyIconFrame(icon, note, size)

    -- Per-note LSM border — rendered on a separate overlay Frame around the icon.
    -- edgeSize controls thickness; the overlay grows outward so the border never
    -- eats into the icon texture.
    local bord = not hasIconFrame and note.borderOverride
    local bordScale = note.borderScale or 100
    local bordOffset = note.borderOffset or 2
    if hasIconFrame then
        if host._borderFrame then host._borderFrame:Hide() end
    elseif bord and bord ~= "" then
        local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
        local path = LSM and LSM:Fetch("border", bord)
        if path then
            if not host._borderFrame then
                local bf = BNB.CreateBackdropFrame("Frame", nil, host)
                bf:SetFrameLevel(host:GetFrameLevel() + 2)
                bf:EnableMouse(false)
                host._borderFrame = bf
            end
            local bf = host._borderFrame
            local es = math.max(1, math.floor(12 * bordScale / 100 + 0.5))
            bf:ClearAllPoints()
            bf:SetPoint("TOPLEFT",     icon, "TOPLEFT",     -bordOffset,  bordOffset)
            bf:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT",  bordOffset, -bordOffset)
            SetRowBorder(bf, path, es, 0.70, 0.70, 0.75, 0.85, note.borderBrightness)
            bf:Show()
        end
    else
        -- No custom border: show the Blizzard tooltip border as default
        if not host._borderFrame then
            local bf = BNB.CreateBackdropFrame("Frame", nil, host)
            bf:SetFrameLevel(host:GetFrameLevel() + 2)
            bf:EnableMouse(false)
            host._borderFrame = bf
        end
        local bf = host._borderFrame
        bf:ClearAllPoints()
        bf:SetPoint("TOPLEFT",     icon, "TOPLEFT",     -2,  2)
        bf:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT",  2, -2)
        SetRowBorder(bf, "Interface\\Tooltips\\UI-Tooltip-Border", 12, 0.35, 0.35, 0.38, 0.75)
        bf:Show()
    end
end
BNB.PaintNoteIcon = PaintNoteIcon

local function PopulateEntry(btn, note, selected, collapsed)
    btn._noteID = note.id
    btn._title  = note.title   -- RefreshNoteListEntry: did a save change it?
    -- Icon border always hidden (user sets per-note border via LSM; WhiteIconFrame removed)
    if btn._iconBorder then btn._iconBorder:Hide() end

    PaintNoteIcon(btn, btn._icon, note)

    -- Multi-select highlight
    if btn._multiSelBg then
        btn._multiSelBg:SetShown(_multiMode and _multiSel[note.id] == true)
    end

    -- Clear first: a row built while collapsed still had CreateListEntry's
    -- LEFT point, and CENTER on top of it pulled the icon off centre
    btn._icon:ClearAllPoints()
    if collapsed then
        btn._icon:SetPoint("CENTER", btn, "CENTER", 0, 0)
    else
        btn._icon:SetPoint("LEFT", btn, "LEFT", PAD_L, 0)
    end
    if btn._iconGlowFrame then
        btn._iconGlowFrame:ClearAllPoints()
        btn._iconGlowFrame:SetPoint("CENTER", btn._icon, "CENTER", 0, 0)
    end
    ShapeRowArt(btn, collapsed)

    -- Faction crest of a player note (ALL-305); none in the collapsed list
    if btn._factionTex then
        local fac = not collapsed and PlayerNoteFaction(note)
        if fac then
            local ft = btn._factionTex
            ft:SetTexture(FACTION_ART[fac])
            ft:SetSize(ICON_SIZE, ICON_SIZE)
            ft:ClearAllPoints()
            ft:SetPoint("RIGHT", btn, "RIGHT", -6, 0)
            ft:Show()
        else
            btn._factionTex:Hide()
        end
    end

    -- Alarm indicator: colour when pending, desaturated when fired, hidden while actively firing
    if btn._alarmTex then
        local alarm = BNB.AlarmsEnabled() and note.alarm   -- none while the module is off (ALL-343)
        if not alarm then
            btn._alarmTex:Hide()
        else
            local active = BNB.Alarm and BNB.Alarm.IsAlarmActive and BNB.Alarm.IsAlarmActive(note.id)
            if active then
                btn._alarmTex:Hide()
            elseif alarm.fired then
                btn._alarmTex:SetMuted(true)
                btn._alarmTex:Show()
            else
                btn._alarmTex:SetMuted(false)
                btn._alarmTex:Show()
            end
        end
    end

    -- Register/unregister glow target based on whether note has an alarm
    if btn._iconGlowFrame and BNB.Alarm then
        -- Rows are pooled: a row that showed another note drops that note's registration
        -- and any glow still running on it, or the old note's alarm would glow here.
        local gf   = btn._iconGlowFrame
        local prev = gf._bnbGlowNoteID
        if prev and prev ~= note.id then
            if BNB.Alarm.UnregisterGlowTarget then BNB.Alarm.UnregisterGlowTarget(prev, gf) end
            if BNB.Alarm._LCGStop then BNB.Alarm._LCGStop(gf) end
            gf._bnbGlowNoteID = nil
        end
        if note.alarm then
            if BNB.Alarm.RegisterGlowTarget then
                BNB.Alarm.RegisterGlowTarget(note.id, gf)
            end
        else
            if BNB.Alarm.UnregisterGlowTarget then
                BNB.Alarm.UnregisterGlowTarget(note.id, gf)
            end
        end
    end

    -- Favorite overlay
    if btn._favTex then
        if note.favorited then btn._favTex:Show() else btn._favTex:Hide() end
    end

    -- Situation marker: show ! on notes that have a situation, while the
    -- Situations module is on (ALL-375)
    if btn._situTex then
        if BNB.SituationsEnabled() and BNB.HasSituation(note) then
            btn._situTex:Show()
        else
            btn._situTex:Hide()
        end
    end

    -- Location marker: a waypoint is placed when the situation matches
    if btn._locTex then
        if BNB.SituationsEnabled() and BNB.HasSituation(note) and BNB.HasActiveWaypoint(note) then
            btn._locTex:Show()
        else
            btn._locTex:Hide()
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
    local hasTasks = BNB.Task and BNB.Task.Shows(note.id) or false
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
            btn._previewLbl:SetText(PreviewText(note))
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
    -- In multi-select mode only the blue tint marks a selection; the gold
    -- open-note highlight made a just-deselected note look selected (ALL-58)
    if selected and not _multiMode then
        btn._selBg:Show()
        if btn._titleLbl then
            if tc then
                btn._titleLbl:SetTextColor(
                    math.min(1, tc.r * 1.15 + 0.05),
                    math.min(1, tc.g * 1.10 + 0.05),
                    math.min(1, tc.b * 1.10 + 0.05), 1)
            else
                BNB.SetHeaderColor(btn._titleLbl)
            end
        end
    else
        btn._selBg:Hide()
        if btn._titleLbl then
            if tc then
                btn._titleLbl:SetTextColor(tc.r, tc.g, tc.b, 1)
            else
                btn._titleLbl:SetTextColor(BNB.TextWhite(hasTitle and 1 or 0.5))
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

-- ── Folder headers (ALL-510) ─────────────────────────────────────────────────
-- One per shown folder, pooled on the scroll child (`_folderHdrs`). Expanded
-- list: folder picture (Dukul's art, BNB.Folders.Art: closed / full / empty,
-- never tinted), "Name (N)" and a rule, like the Pinned / Notes headers but
-- in the folder's colour; left-click opens / closes, right-click
-- is the folder menu (BNB.ShowFolderMenu, UI/FolderMenus.lua). Icon-only
-- list: one row of the note row's height with the picture in the middle,
-- name and count on hover.
local FOLDER_HDR_H  = 22
local FOLDER_ICON   = 20
local FOLDER_INDENT = 10   -- notes inside a folder, expanded list

local function FitFolderLabel(hdr)
    local fs, w = hdr._text, hdr:GetWidth()
    if not (fs and w and w > 0) then return end
    local sw = fs.GetUnboundedStringWidth and fs:GetUnboundedStringWidth() or fs:GetStringWidth()
    fs:SetWidth(math.max(1, math.min(sw + 2, w - FOLDER_ICON - 4 - 24)))
end

local function GetFolderHeader(child, i)
    child._folderHdrs = child._folderHdrs or {}
    local hdr = child._folderHdrs[i]
    if hdr then return hdr end
    hdr = CreateFrame("Button", nil, child)
    hdr:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    local hl = hdr:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints(); hl:SetColorTexture(1, 1, 1, 0.05)
    hdr._icon = hdr:CreateTexture(nil, "ARTWORK")
    local fs = hdr:CreateFontString(nil, "OVERLAY", "BNBFontNormalSmall")
    fs:SetJustifyH("LEFT"); fs:SetWordWrap(false)
    hdr._text = fs
    local rule = hdr:CreateTexture(nil, "ARTWORK")
    if rule.SetSnapToPixelGrid then   -- one exact pixel (ALL-246)
        rule:SetSnapToPixelGrid(false)
        rule:SetTexelSnappingBias(0)
    end
    if PixelUtil and PixelUtil.SetHeight then PixelUtil.SetHeight(rule, 1, 1)
    else rule:SetHeight(1) end
    hdr._rule = rule
    hdr:HookScript("OnSizeChanged", FitFolderLabel)
    hdr:SetScript("OnClick", function(self, button)
        local sys = self._sysKey   -- a system folder (ALL-511): no drops, its own menu
        if sys then
            if button == "RightButton" then
                if BNB.ShowSystemFolderMenu then BNB.ShowSystemFolderMenu(self, sys) end
            elseif not self._forcedOpen then
                BNB.SystemNotes.SetOpen(sys, not BNB.SystemNotes.IsOpen(sys))
            end
            return
        end
        local id = self._folderID
        if not id then return end
        if button == "RightButton" then
            if BNB.ShowFolderMenu then BNB.ShowFolderMenu(self, id) end
        elseif not self._forcedOpen then
            BNB.Folders.SetOpen(id, not BNB.Folders.IsOpen(id))
        end
    end)
    hdr:SetScript("OnEnter", function(self)
        if not self._iconRow or _dragNoteID then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        local name = self._sysKey and self._sysName or BNB.Folders.Text(self._folderID)
        GameTooltip:AddLine(name .. " (" .. (self._count or 0) .. ")")
        GameTooltip:AddLine(L["FOLDER_ROW_TIP"], 0.85, 0.85, 0.85, true)
        GameTooltip:Show()
    end)
    hdr:SetScript("OnLeave", function() GameTooltip:Hide() end)
    child._folderHdrs[i] = hdr
    return hdr
end

-- f = a BNB.Folders.List() entry; n = its notes on this tab; forced = drawn
-- open by a search or filter, whatever its saved state. A system folder
-- (ALL-511) is f = { sys = key, name, r, g, b }: no _folderID, so it is never
-- a drop target (HeaderUnderCursor)
local function LayoutFolderHeader(hdr, f, n, open, forced, iconRow, rowH)
    local FD = BNB.Folders
    hdr._folderID, hdr._count, hdr._forcedOpen, hdr._iconRow = f.id, n, forced, iconRow
    hdr._sysKey, hdr._sysName = f.sys, f.sys and f.name or nil
    local hr, hg, hb = BNB.HeaderColor()
    local r, g, b
    if f.sys then r, g, b = f.r, f.g, f.b else r, g, b = FD.Color(f.id) end
    r, g, b = r or hr, g or hg, b or hb
    FD.PaintArt(hdr._icon, open, n > 0, r, g, b, f.sys)   -- skin mode: tinted like the name
    hdr._icon:ClearAllPoints(); hdr._text:ClearAllPoints(); hdr._rule:ClearAllPoints()
    if iconRow then
        hdr:SetHeight(rowH)
        hdr._icon:SetSize(ICON_SIZE, ICON_SIZE)
        hdr._icon:SetPoint("CENTER", hdr, "CENTER", 0, 0)
        hdr._text:Hide(); hdr._rule:Hide()
        return
    end
    hdr:SetHeight(FOLDER_HDR_H)
    hdr._icon:SetSize(FOLDER_ICON, FOLDER_ICON)
    hdr._icon:SetPoint("LEFT", hdr, "LEFT", 0, 0)
    hdr._text:SetPoint("LEFT", hdr._icon, "RIGHT", 4, 0)
    hdr._text:SetText(f.name .. " (" .. n .. ")")
    hdr._text:SetTextColor(r, g, b)
    hdr._text:Show()
    FitFolderLabel(hdr)
    hdr._rule:SetPoint("LEFT",  hdr._text, "RIGHT", 6, 0)
    hdr._rule:SetPoint("RIGHT", hdr, "RIGHT", 0, 0)
    hdr._rule:SetColorTexture(r, g, b, HDR_RULE_A)
    hdr._rule:Show()
end

local function RefreshNoteList()
    if not BNB._listScrollChild then return end
    -- The collapsed list's section dividers: drawn again below when collapsed
    for _, d in ipairs(BNB._listScrollChild._colDivs or {}) do d:Hide() end
    -- Every filter change ends here, typing included (ALL-194: the reset
    -- icon only lit up for the favourite and task buttons)
    if BNB._applyOuterClearState then BNB._applyOuterClearState() end
    -- A folder view saved while the Folders module is now off (a profile, the
    -- setup wizard): back to the list (ALL-514)
    local db = BigNoteBoxDB
    if db and db.tagTreeMode and db.treeSource == "folders" and not BNB.FoldersEnabled()
       and BNB.SetTagTreeMode then
        BNB.SetTagTreeMode(false)   -- redraws the list itself
        return
    end
    -- Delegate to tag tree when that mode is active
    if BigNoteBoxDB and BigNoteBoxDB.tagTreeMode and BNB.RefreshTagTree then
        BNB.RefreshTagTree()
        return
    end

    ApplyListMode()

    -- noFloat: the list splits Pinned off itself below, so pinned notes are
    -- not floated and sorted A-Z first; they follow the chosen sort as every
    -- other section does (Dukul, 2026-10-20: the sort left Pinned alone)
    local notes    = BNB.GetOrderedNotes(currentFilter, currentTagFilter, true)
    local selID    = BNB._currentNoteID
    local child    = BNB._listScrollChild
    local collapsed = BNB._listCollapsed
    local entryH   = collapsed and (ICON_SIZE + 12) or ENTRY_H
    local totalH   = 0

    -- Always split pinned vs regular. Every section keeps the active sort's
    -- order (pinned A-Z only until 2026-10-20; never sort a second time
    -- here, PERF-07).
    -- Folders (ALL-510): a note in a folder is drawn under its folder, after
    -- Pinned and before the regular notes; a pinned one shows under Pinned and
    -- in its folder too, as the folder view does (Dukul, 2026-10-19: the folder
    -- counted it but opened empty)
    -- Folders module off (ALL-514): no folder sections, every note under Notes
    local FD = BNB.FoldersEnabled() and BNB.Folders or nil
    local pinned, regular, inFolder, folderN = {}, {}, {}, {}
    for _, note in ipairs(notes) do
        local fid = FD and FD.Of(note)
        if fid then folderN[fid] = (folderN[fid] or 0) + 1 end
        if note.pinned then pinned[#pinned + 1] = note end
        if fid then
            local t = inFolder[fid]
            if not t then t = {}; inFolder[fid] = t end
            t[#t + 1] = note
        elseif not note.pinned then regular[#regular + 1] = note end
    end
    -- Which folders show: one holding a note on this tab, and an empty one on
    -- every tab so it can be filled. A search or filter shows only folders
    -- with matches, drawn open whatever their saved state.
    local filtering = currentFilter ~= "" or currentTagFilter ~= nil
        or BNB._favFilterActive == true or BNB._taskFilterActive == true
    local folders = {}
    if FD then
        local total = FD.Counts()
        for _, f in ipairs(FD.List()) do
            if folderN[f.id] or (not filtering and not total[f.id]) then
                folders[#folders + 1] = f
            end
        end
    end

    for _, btn in ipairs(listEntries) do btn:Hide(); btn:ClearAllPoints() end
    for _, hdr in ipairs(child._folderHdrs or {}) do hdr:Hide() end

    -- ── Section header helper ────────────────────────────────────────────────
    -- Reuse pre-built headers stored on child to avoid leaking. A header is a
    -- frame holding the label and a rule in the header colour running from its right to the
    -- edge, as the Reference Box "Done (N)" title (ALL-328, Dukul 2026-10-06);
    -- hiding the frame hides both (TagTree hides them by these keys).
    -- A picture left of the label as the folder headers have (Dukul,
    -- 2026-10-20): art = "pinned" / "notes", ui-note-list-<art> in colour,
    -- -skin in skin mode, white art tinted in the header colour
    -- iconRow = the collapsed list: one row of the list's row height with
    -- only the picture in the middle, the label in its tooltip, as a folder
    -- header there (Dukul, 2026-10-20)
    local function GetSectionHeader(key, labelText, art, iconRow)
        local hdr = child[key]
        if not hdr then
            hdr = CreateFrame("Frame", nil, child)
            hdr:SetHeight(FOLDER_HDR_H)
            local pic = hdr:CreateTexture(nil, "ARTWORK")
            pic:SetSize(FOLDER_ICON, FOLDER_ICON)
            pic:SetPoint("LEFT", hdr, "LEFT", 0, 0)
            hdr._pic = pic
            local fs = hdr:CreateFontString(nil, "OVERLAY", "BNBFontNormalSmall")
            fs:SetPoint("LEFT", pic, "RIGHT", 4, 0)
            fs:SetJustifyH("LEFT")
            local rule = hdr:CreateTexture(nil, "ARTWORK")
            if rule.SetSnapToPixelGrid then   -- one exact pixel (ALL-246)
                rule:SetSnapToPixelGrid(false)
                rule:SetTexelSnappingBias(0)
            end
            if PixelUtil and PixelUtil.SetHeight then PixelUtil.SetHeight(rule, 1, 1)
            else rule:SetHeight(1) end
            rule:SetPoint("LEFT",  fs,  "RIGHT", 6, 0)
            rule:SetPoint("RIGHT", hdr, "RIGHT", 0, 0)
            hdr._text, hdr._rule = fs, rule
            hdr:EnableMouse(true)   -- the collapsed row's tooltip
            hdr:SetScript("OnEnter", function(self)
                if not self._iconRow then return end
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:AddLine(self._text:GetText() or "")
                GameTooltip:Show()
            end)
            hdr:SetScript("OnLeave", function() GameTooltip:Hide() end)
            child[key] = hdr
        end
        hdr._text:SetText(labelText)
        hdr._iconRow = iconRow
        hdr._pic:ClearAllPoints()
        if iconRow then
            hdr:SetHeight(entryH)
            hdr._pic:SetSize(ICON_SIZE, ICON_SIZE)
            hdr._pic:SetPoint("CENTER", hdr, "CENTER", 0, 0)
            hdr._text:Hide(); hdr._rule:Hide()
        else
            hdr:SetHeight(FOLDER_HDR_H)
            hdr._pic:SetSize(FOLDER_ICON, FOLDER_ICON)
            hdr._pic:SetPoint("LEFT", hdr, "LEFT", 0, 0)
            hdr._text:Show(); hdr._rule:Show()
        end
        -- Text follows the BNBFontNormalSmall colour; the rule is set on every
        -- layout so it follows a preset change too (ALL-402)
        local hr, hg, hb = BNB.HeaderColor()
        hdr._rule:SetColorTexture(hr, hg, hb, HDR_RULE_A)
        BNB.Folders.PaintSectionArt(hdr._pic, art, hr, hg, hb)
        hdr:ClearAllPoints()
        return hdr
    end

    -- A thin line between the sections in the collapsed list only: Pinned,
    -- the folders, Notes, the system folders (Dukul, 2026-10-20). Nothing
    -- before the first section drawn
    local divIdx = 0
    local function SectionDivider()
        if not collapsed or totalH <= 0 then return end
        divIdx = divIdx + 1
        child._colDivs = child._colDivs or {}
        local d = child._colDivs[divIdx]
        if not d then
            d = child:CreateTexture(nil, "ARTWORK")
            if d.SetSnapToPixelGrid then d:SetSnapToPixelGrid(false); d:SetTexelSnappingBias(0) end
            if PixelUtil and PixelUtil.SetHeight then PixelUtil.SetHeight(d, 1, 1) else d:SetHeight(1) end
            child._colDivs[divIdx] = d
        end
        local hr, hg, hb = BNB.HeaderColor()
        d:SetColorTexture(hr, hg, hb, HDR_RULE_A)
        d:ClearAllPoints()
        d:SetPoint("TOPLEFT",  child, "TOPLEFT",  6, -(totalH + 2))
        d:SetPoint("TOPRIGHT", child, "TOPRIGHT", -6, -(totalH + 2))
        d:Show()
        totalH = totalH + 5
    end

    -- One note row; section = "pinned", a folder id or "notes" (the "edited"
    -- sort's row-only redraw compares rows within one section)
    local entryIdx = 0
    local function AddRow(note, indent, section)
        entryIdx = entryIdx + 1
        if not listEntries[entryIdx] then
            listEntries[entryIdx] = CreateListEntry(child)
        end
        local btn = listEntries[entryIdx]
        btn:SetHeight(entryH)
        btn:SetPoint("TOPLEFT",  child, "TOPLEFT",  indent, -totalH)
        btn:SetPoint("TOPRIGHT", child, "TOPRIGHT", 0, -totalH)
        btn._section = section
        btn._sys = note.system   -- a system note (ALL-511): read only, never dragged or picked
        PopulateEntry(btn, note, note.id == selID, collapsed)
        btn:Show()
        totalH = totalH + entryH
    end

    -- ── Pinned section ────────────────────────────────────────────────────────
    if #pinned > 0 then
        local hdr = GetSectionHeader("_pinnedHdr",
            string.format(L["NL_HDR_PINNED_FMT"], #pinned), "pinned", collapsed)
        hdr:SetPoint("TOPLEFT",  child, "TOPLEFT",  collapsed and 0 or PAD_L, -totalH)
        hdr:SetPoint("TOPRIGHT", child, "TOPRIGHT", collapsed and 0 or -4,    -totalH)
        hdr:Show()
        totalH = totalH + hdr:GetHeight()

        for _, note in ipairs(pinned) do AddRow(note, 0, "pinned") end

        -- No divider between pinned and regular any more: the Notes header
        -- carries its own rule (ALL-328), only a small gap above it
        if not collapsed then totalH = totalH + 4 end
    else
        if child._pinnedHdr then child._pinnedHdr:Hide() end
    end

    -- ── Folders (ALL-510) ─────────────────────────────────────────────────────
    for i, f in ipairs(folders) do
        if i == 1 then SectionDivider() end
        local open = filtering or f.open
        local hdr = GetFolderHeader(child, i)
        LayoutFolderHeader(hdr, f, folderN[f.id] or 0, open, filtering, collapsed, entryH)
        local x = collapsed and 0 or PAD_L
        hdr:SetPoint("TOPLEFT",  child, "TOPLEFT",  x, -totalH)
        hdr:SetPoint("TOPRIGHT", child, "TOPRIGHT", collapsed and 0 or -4, -totalH)
        hdr:Show()
        totalH = totalH + hdr:GetHeight()
        if open then
            for _, note in ipairs(inFolder[f.id] or {}) do
                AddRow(note, collapsed and 0 or FOLDER_INDENT, f.id)
            end
        end
        if not collapsed then totalH = totalH + 2 end
    end
    if #folders > 0 and not collapsed then totalH = totalH + 2 end

    -- ── Regular section ───────────────────────────────────────────────────────
    -- Always show the "Notes (X)" header; the collapsed list only when
    -- Pinned or a folder is above, to tell these notes apart from theirs
    if not collapsed or #pinned > 0 or #folders > 0 then
        SectionDivider()
        local hdr2 = GetSectionHeader("_regularHdr",
            string.format(L["NL_HDR_REGULAR_FMT"], #regular), "notes", collapsed)
        hdr2:SetPoint("TOPLEFT",  child, "TOPLEFT",  collapsed and 0 or PAD_L, -totalH)
        hdr2:SetPoint("TOPRIGHT", child, "TOPRIGHT", collapsed and 0 or -4,    -totalH)
        hdr2:Show()
        -- Right-click: New folder (ALL-510)
        if not hdr2._folderMenu then
            hdr2._folderMenu = true
            hdr2:EnableMouse(true)
            hdr2:SetScript("OnMouseUp", function(self, button)
                if button == "RightButton" and BNB.ShowNotesHeaderMenu then BNB.ShowNotesHeaderMenu(self) end
            end)
        end
        totalH = totalH + hdr2:GetHeight()
    else
        if child._regularHdr then child._regularHdr:Hide() end
    end

    for _, note in ipairs(regular) do AddRow(note, 0, "notes") end

    -- ── System folders (ALL-511) ──────────────────────────────────────────────
    -- After the Notes, every tab. Their notes are not in GetOrderedNotes: the
    -- search text is matched here (title and text, as GetOrderedNotes does),
    -- a folder with matches drawn open. Tag, favourite and task filters hide
    -- them (a system note has none of those).
    local SYS = BNB.SystemNotes
    local sysShown = 0
    local otherFilter = currentTagFilter ~= nil or BNB._favFilterActive == true
        or BNB._taskFilterActive == true
    if SYS and not otherFilter then
        local lower = currentFilter ~= "" and currentFilter:lower() or nil
        if #regular > 0 and not collapsed then totalH = totalH + 4 end
        for _, p in ipairs(SYS.Folders()) do
            local sysNotes = SYS.Search(p.key, lower)
            if #sysNotes > 0 then
                if sysShown == 0 then SectionDivider() end
                sysShown = sysShown + 1
                local open = lower ~= nil or SYS.IsOpen(p.key)
                local hdr = GetFolderHeader(child, #folders + sysShown)
                LayoutFolderHeader(hdr, { sys = p.key, name = L[p.name], r = p.r, g = p.g, b = p.b },
                    #sysNotes, open, lower ~= nil, collapsed, entryH)
                hdr:SetPoint("TOPLEFT",  child, "TOPLEFT",  collapsed and 0 or PAD_L, -totalH)
                hdr:SetPoint("TOPRIGHT", child, "TOPRIGHT", collapsed and 0 or -4, -totalH)
                hdr:Show()
                totalH = totalH + hdr:GetHeight()
                if open then
                    for _, note in ipairs(sysNotes) do
                        AddRow(note, collapsed and 0 or FOLDER_INDENT, "sys:" .. p.key)
                    end
                end
                if not collapsed then totalH = totalH + 2 end
            end
        end
    end

    -- Empty state (empty folders on show are not "no notes" to look at)
    if #notes == 0 and #folders == 0 and sysShown == 0 then
        if not BNB._listEmptyLabel then
            local lbl = child:CreateFontString(nil, "OVERLAY", "BNBFontNormal")
            lbl:SetPoint("TOP", child, "TOP", 0, -24)
            lbl:SetWidth(200); lbl:SetJustifyH("CENTER"); lbl:SetWordWrap(true)
            lbl:SetTextColor(0.38, 0.38, 0.38)
            BNB._listEmptyLabel = lbl
        end
        BNB._listEmptyLabel:SetText(
            currentFilter ~= "" and L["NL_NO_MATCHES"] or L["NOTE_LIST_EMPTY"])
        BNB._listEmptyLabel:Show()
        totalH = 80
    else
        if BNB._listEmptyLabel then BNB._listEmptyLabel:Hide() end
    end

    local sfH = _sf and _sf:GetHeight() or 100
    child:SetHeight(math.max(totalH, sfH))
    if _sf and _sf.UpdateScrollbar then _sf:UpdateScrollbar() end
end

-- ── Following the note data (ARCH-02) ────────────────────────────────────────
-- The list redraws itself from NoteCreated / NoteChanged / NoteDeleted /
-- NoteRestored (Core/NoteManager.lua), so code that changes a note does not
-- call RefreshNoteList. Messages are collected and handled once, on the next
-- frame: an import of 150 notes is one redraw, not 300. Every message and
-- every redraw takes a number from _seq; a message is skipped when a redraw
-- after it already covered it (a full redraw, or that note's row), so a
-- refresh still called by hand costs nothing extra.
local _seq, _lastFull = 0, 0
local _rowAt          = {}    -- note id -> _seq of its last row redraw
local _pendingRows    = {}    -- note id -> _seq of its newest NoteChanged
local _pendingFull          -- _seq of the newest create / delete / restore
local FLUSH_KEY       = "noteListMessages"

-- Sends NoteListRefreshed after every redraw, flat list or tag tree (the
-- Welcome panel's icon rows follow it; a hooksecurefunc until ARCH-02)
function BNB.RefreshNoteList()
    _seq = _seq + 1; _lastFull = _seq
    RefreshNoteList()
    BNB.SendMessage("NoteListRefreshed")
end

-- The shown flat-list row for a note, or nil.
local function ShownRow(id)
    for _, btn in ipairs(listEntries) do
        if btn:IsShown() and btn._noteID == id then return btn end
    end
end

-- Is btn the first (newest first) or last (oldest first) unpinned row of its
-- section (a folder or the Notes part, ALL-510)? In the "edited" sort that is
-- where a saved note goes, so it does not move.
local function AtEditedEdge(btn, asc)
    local edge
    for _, b in ipairs(listEntries) do
        if b:IsShown() and b._section == btn._section then
            local n = BNB.GetNote(b._noteID)
            if n and not n.pinned then
                if not asc then return b == btn end
                edge = b
            end
        end
    end
    return edge == btn
end

-- Redraw one note's row (PERF-01). For a change that cannot alter which notes
-- the list shows or their order: autosave of title/body, task changes, target
-- portraits. Anything that might falls back to the full RefreshNoteList, so
-- callers never need to know. opts.tasks: the note's tasks changed.
function BNB.RefreshNoteListEntry(id, opts)
    local note = id and BNB.GetNote(id)
    local db   = BigNoteBoxDB
    local btn  = note and not (db and db.tagTreeMode) and ShownRow(id)
    if not btn or currentFilter ~= "" or currentTagFilter
        or (opts and opts.tasks and BNB._taskFilterActive) then
        return BNB.RefreshNoteList()
    end
    local sortBy = db and db.sortBy or BNB.DEFAULTS.sortBy
    if btn._title ~= note.title and (sortBy == "alpha" or note.pinned) then
        return BNB.RefreshNoteList()
    end
    if sortBy == "edited" and not note.pinned and not AtEditedEdge(btn, db and db.sortAsc) then
        BNB.RefreshNoteList()
        -- The note you are typing in just moved to the top (or the bottom,
        -- oldest first): the list follows it there (ALL-207)
        if id == BNB._currentNoteID then BNB.ScrollNoteListTo(id) end
        return
    end
    _seq = _seq + 1; _rowAt[id] = _seq
    -- A pinned note in a folder has two rows (Pinned and its folder)
    for _, b in ipairs(listEntries) do
        if b:IsShown() and b._noteID == id then
            PopulateEntry(b, note, note.id == BNB._currentNoteID, BNB._listCollapsed)
        end
    end
end

-- Fields that only change how a note's own row looks. A change to anything
-- else (pinned, favourite, scope, tags, situation, a field added later) can
-- move the note in or out of the list or change its place: full redraw.
-- An in-place change (UpdateNote(id, {}): Reference Box items) is row-only.
local ROW_ONLY = {}
for _, k in ipairs({ "title", "body", "richMode", "icon", "iconSource", "iconFrame",
    "titleColor", "borderOverride", "borderScale", "borderOffset", "borderBrightness",
    "locked", "alarm", "attachments", "fontOverride", "fontSize", "fontOutline",
    "lineHeight", "textAlign", "waypoints", "wpCreatedOn", "wpClearOnLeave", "wpNoTrack", "contextDisplay",
    "contextLeave", "contextTrigger", "contextFreq", "lastOpened", "toastStyle", "toastHold" }) do ROW_ONLY[k] = true end

local function RowOnly(fields)
    if not fields then return false end
    for k in pairs(fields) do
        if k == "_clear" then
            for _, c in ipairs(fields._clear) do
                if not ROW_ONLY[c] then return false end
            end
        elseif not ROW_ONLY[k] then
            return false
        end
    end
    return true
end

-- Handles the collected messages now. SelectNote and ScrollNoteListTo call it
-- first, so a note created or changed just before is already in the list.
-- While the main window is closed the work is dropped: its OnShow redraws.
local function FlushListWork()
    BNB.CancelDebounce(FLUSH_KEY)
    local full, rows = _pendingFull, _pendingRows
    if not full and not next(rows) then return end
    _pendingFull, _pendingRows = nil, {}
    if not (BNB.mainFrame and BNB.mainFrame:IsShown()) then return end
    if full and full > _lastFull then return BNB.RefreshNoteList() end
    for id, at in pairs(rows) do
        -- RefreshNoteListEntry may fall back to a full redraw, which raises
        -- _lastFull and so covers the rest
        if at > _lastFull and (_rowAt[id] or 0) < at then
            BNB.RefreshNoteListEntry(id)
        end
    end
end
BNB.FlushNoteList = FlushListWork

local function QueueFull()
    _seq = _seq + 1; _pendingFull = _seq
    BNB.Debounce(FLUSH_KEY, 0, FlushListWork)
end

BNB.RegisterMessage("NoteList", "NoteCreated",  QueueFull)
BNB.RegisterMessage("NoteList", "NoteDeleted",  QueueFull)
BNB.RegisterMessage("NoteList", "NoteRestored", QueueFull)
BNB.RegisterMessage("NoteList", "FoldersChanged", QueueFull)   -- ALL-510
BNB.RegisterMessage("NoteList", "SystemNotesChanged", QueueFull)   -- ALL-511
BNB.RegisterMessage("NoteList", "SkinChanged", QueueFull)   -- the folder art follows the look
BNB.RegisterMessage("NoteList", "NoteChanged", function(_, id, fields)
    if not RowOnly(fields) then return QueueFull() end
    _seq = _seq + 1; _pendingRows[id] = _seq
    BNB.Debounce(FLUSH_KEY, 0, FlushListWork)
end)

--------------------------------------------------------------------------------
-- REVEAL NOTE
-- Oracle search (ALL-69) opens any note, including one the list is hiding.
-- When id is not in the filtered list: sidebar to "All", and the search box,
-- tag, favourite and task filters cleared (the reset button's own action).
--------------------------------------------------------------------------------
function BNB.RevealNoteInList(id)
    -- A system note (ALL-511): its folder opens; a search or filter hides
    -- the system folders, so it is cleared
    local SYS = BNB.SystemNotes
    if SYS and SYS.IsSystem(id) then
        local key = SYS.FolderOf(id)
        if key then SYS.SetOpen(key, true) end
        -- Tag, favourite and task filters hide the system folders; so may a
        -- search, so it is cleared too
        local filtering = currentFilter ~= "" or currentTagFilter ~= nil
            or BNB._favFilterActive == true or BNB._taskFilterActive == true
        local oc = BNB._searchOuterClear
        local reset = filtering and oc and oc:GetScript("OnClick")
        if reset then reset(oc) end
        return
    end
    -- A note in a closed folder: the folder opens (ALL-510)
    if BNB.Folders then BNB.Folders.OpenFor(id) end
    for _, n in ipairs(BNB.GetOrderedNotes(currentFilter, currentTagFilter)) do
        if n.id == id then return end
    end
    local SB = BNB.Sidebar
    if SB and SB.GetActive and SB.GetActive() ~= "all" and SB.SetActive then SB.SetActive("all") end
    local oc = BNB._searchOuterClear
    local reset = oc and oc:GetScript("OnClick")
    if reset then reset(oc) end
end

--------------------------------------------------------------------------------
-- SELECT NOTE
--------------------------------------------------------------------------------
-- Quick notes made in the main window follow the sticky rule (ALL-199, Dukul
-- 2026-10-02): the first time you move off one (another note, closing the
-- window, logout) with its body still empty, it is removed outright, no
-- trash. Typed in once, it stays like any note. Mark AFTER SelectNote(id).
function BNB.MarkQuickNew(id) BNB._quickNewID = id end

-- Opens a just-created quick note in the main window, marked quick-new, with
-- the cursor in the body. Used by the Quick Note button and the quick note key.
function BNB.ShowQuickNote(id)
    BNB.OpenMainWindow()
    BNB.SelectNote(id)
    BNB.MarkQuickNew(id)   -- empty = removed (ALL-199)
    C_Timer.After(0.05, function()
        if BNB._editorBody then BNB._editorBody:SetFocus() end
    end)
end

function BNB.DropEmptyQuickNote(nextID)
    local id = BNB._quickNewID
    if not id or id == nextID then return end
    -- Focus mode writes the note from its own box; the main editor may not
    -- have that text yet, so never judge "empty" while it is open
    if BNB.IsFocusModeOpen and BNB.IsFocusModeOpen() then return end
    BNB._quickNewID = nil
    local note = BNB.GetNote(id)
    if not note then return end
    local body = note.body or ""
    if BNB._currentNoteID == id and BNB._editorBody then
        local eb = BNB._editorBody
        body = eb._showingPlaceholder and "" or (eb:GetText() or "")
    end
    if not body:match("^%s*$") then return end
    BNB.PurgeNote(id)
    if BNB._currentNoteID == id then BNB.Editor.SetCurrent(nil) end
    if BigNoteBoxDB and BigNoteBoxDB.selectedNoteID == id then BigNoteBoxDB.selectedNoteID = nil end
    -- The list follows PurgeNote's NoteDeleted on the next frame (ARCH-02)
end
BNB.RegisterEvent("PLAYER_LOGOUT", function() BNB.DropEmptyQuickNote(nil) end)

function BNB.SelectNote(id)
    FlushListWork()   -- a note created just before has its row (ARCH-02)
    BNB.DropEmptyQuickNote(id)
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

    -- Leaving a rich note: its markup repairs are written into it (ALL-277)
    local prevID = BNB._currentNoteID
    if prevID and prevID ~= id and BNB.AdvancedMode.RepairOnLeave then
        xpcall(BNB.AdvancedMode.RepairOnLeave, geterrorhandler(), prevID)
    end

    BNB.Editor.SetCurrent(id); BigNoteBoxDB.selectedNoteID = id
    BNB.StampOpened(id)
    for _, btn in ipairs(listEntries) do
        if btn:IsShown() then
            if btn._noteID == id and not _multiMode then   -- see PopulateEntry (ALL-58)
                local note = BNB.GetNote(id)
                local tc   = note and note.titleColor
                if btn._titleLbl then
                    if tc then
                        btn._titleLbl:SetTextColor(
                            math.min(1, tc.r * 1.15 + 0.05),
                            math.min(1, tc.g * 1.10 + 0.05),
                            math.min(1, tc.b * 1.10 + 0.05), 1)
                    else
                        BNB.SetHeaderColor(btn._titleLbl)
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
    -- Note Settings, the Reference Box and the history panel follow (ARCH-02)
    BNB.SendMessage("NoteSelected", id)
    BNB.ScrollNoteListTo(id)
end

-- Scrolls the note list just far enough to show the note's row (a note
-- opened from a menu, the Oracle or elsewhere stayed out of view). Next
-- frame, so a list refreshed or a window shown in the same call has its
-- layout and scroll range. Flat list and tag tree alike: both use
-- listEntries; a note with no shown row (filtered, folded tag) is left be.
function BNB.ScrollNoteListTo(id)
    C_Timer.After(0, function()
        FlushListWork()
        local sf, child = _sf, BNB._listScrollChild
        if not (id and sf and child and sf:IsVisible()) then return end
        local row
        for _, btn in ipairs(listEntries) do
            if btn:IsShown() and btn._noteID == id then row = btn; break end
        end
        local cTop, rTop = child:GetTop(), row and row:GetTop()
        if not (cTop and rTop) then return end
        local top    = cTop - rTop
        local bottom = top + row:GetHeight()
        local cur, view = sf:GetVerticalScroll(), sf:GetHeight()
        local to
        if top < cur then to = top
        elseif bottom > cur + view then to = bottom - view end
        if to then
            sf:SetVerticalScroll(math.max(0, math.min(sf:GetVerticalScrollRange(), to)))
        end
    end)
end

--------------------------------------------------------------------------------
-- BUILD NOTE LIST
--------------------------------------------------------------------------------
function BNB.BuildNoteList()
    local pane = BNB.listPane
    if not pane then return end

    -- Restore collapse and display mode from DB
    BNB._listCollapsed = BigNoteBoxDB.listCollapsed or BNB.DEFAULTS.listCollapsed
    ApplyListMode()

    local searchBar = BuildSearchBar(pane)
    _searchBar = searchBar

    local BTNS_H = NEWBTN_H + PAD_BOT + 2
    local sf = BNB.CreateScrollFrame("BigNoteBoxListScroll", pane)
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
    colBtn._tx = colTex
    BNB.TintUIIcon(colTex)   -- white arrows (2026-10-08): gold / skin accent
    PaintCollapseArrow(colBtn, false)
    colBtn:SetScript("OnClick", function()
        BigNoteBoxDB.listAutoCollapsed = false   -- by hand now: widening leaves it (ALL-115)
        BNB.SetListCollapsed(not BNB._listCollapsed)
    end)
    colBtn:SetScript("OnEnter", function(self)
        PaintCollapseArrow(self, true)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(
            BNB._listCollapsed and L["NL_COLLAPSE_EXPAND_TIP"] or L["NL_COLLAPSE_TIP"],
            1, 1, 1)
        GameTooltip:Show()
    end)
    colBtn:SetScript("OnLeave", function(self)
        PaintCollapseArrow(self, false)
        GameTooltip:Hide()
    end)
    _collapseBtn = colBtn

    -- + New Note (left button)
    local newBtn = BNB.CreateButton(nil, pane, L["BTN_NEW_NOTE"], 80, btnH)
    newBtn:SetPoint("BOTTOMLEFT", pane, "BOTTOMLEFT", PAD_L, btnY)
    newBtn:SetScript("OnClick", function() BNB.CreateNewNote() end)
    newBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(L["NL_NEW_NOTE_TIP"], 1, 1, 1)
        GameTooltip:AddLine(L["NL_NEW_NOTE_TIP_SUB"], 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)
    newBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    _newBtn = newBtn

    -- Quick Note (right button, anchored between newBtn and colBtn)
    local qBtn = BNB.CreateButton(nil, pane, L["NL_QUICK_NOTE_BTN"], 80, btnH)
    qBtn:SetPoint("BOTTOMLEFT",  newBtn, "BOTTOMRIGHT", 4,  0)
    qBtn:SetPoint("BOTTOMRIGHT", colBtn, "BOTTOMLEFT",  -4, 0)
    qBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(L["NL_QUICK_NOTE_BTN"], 1, 1, 1)
        GameTooltip:AddLine(L["NL_QUICK_NOTE_TIP_SUB"], 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)
    qBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    qBtn:SetScript("OnClick", function()
        if InCombatLockdown() then BNB:Print(L["COMBAT_BLOCKED"]); return end
        BNB.SaveCurrentNote()
        local id = BNB.CreateQuickNote()
        if id then BNB.ShowQuickNote(id) end
    end)
    _qBtn = qBtn

    -- Keep both buttons equal width as the pane resizes.
    -- qBtn is anchor-driven (fills newBtn right → colBtn left) so we only need
    -- to set newBtn width = half the available space.
    local function UpdateButtonLabels()
        if not _newBtn or not _qBtn or not pane:GetWidth() then return end
        local paneW     = pane:GetWidth()
        if BNB._listCollapsed then
            -- Icons only: one button fills the space left of the arrow (2 px edge + 4 px gap)
            _newBtn:SetWidth(math.max(20, paneW - PAD_L - collapseW - 6))
            _newBtn:SetText("NN")
            return
        end
        local available = paneW - PAD_L - collapseW - 12  -- gaps between buttons
        local halfW     = math.max(20, math.floor(available / 2))
        _newBtn:SetWidth(halfW)
        -- Label tiers based on half width
        if halfW >= 70 then
            _newBtn:SetText(L["BTN_NEW_NOTE"])
            _qBtn:SetText(L["NL_QUICK_NOTE_BTN"])
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
        _qBtn:Hide()
        -- The buttons beside the search bar too: they sit on the pane, not
        -- the bar, and were left over the collapsed list (Dukul, 2026-10-20)
        for _, b in ipairs({ BNB._favBtn, BNB._taskFilterBtn, BNB._tagTreeBtn,
                             BNB._folderTreeBtn, BNB._searchOuterClear }) do
            if b then b:Hide() end
        end
        sf:ClearAllPoints()
        sf:SetPoint("TOPLEFT",     pane, "TOPLEFT",     PAD_L, -4)
        sf:SetPoint("BOTTOMRIGHT", pane, "BOTTOMRIGHT", -22,   NEWBTN_H + PAD_BOT + 2)
    end
end

-- True when note is a target or inspect note about the unit targeted now.
-- The note list row and the sticky badge (ALL-208) draw its live portrait then.
-- NoteMatchesUnit is the same test for any unit token (the Target / Focus
-- frame badge, ALL-389).
function BNB.NoteMatchesTarget(note) return BNB.NoteMatchesUnit(note, "target") end

function BNB.NoteMatchesUnit(note, unit)
    if not BNB.UnitNotesEnabled() then return false end   -- Player & NPC Notes off (ALL-343)
    if not note or not (note.source == "target" or note.source == "inspect")
            or not UnitExists(unit) then
        return false
    end
    if note.source == "inspect" then
        if UnitIsPlayer(unit) and note.inspectName then
            local name, realm = BNB.UnitNameRealm(unit)
            return (name == note.inspectName) and
                (not note.inspectRealm or note.inspectRealm == "" or realm == note.inspectRealm)
        end
    elseif note.targetNpcID then
        -- NPC match: compare stored creature ID against current target GUID
        local guid = UnitGUID(unit)
        local curID = guid and (
            guid:match("^Creature%-0%-%d+%-%d+%-%d+%-(%d+)") or
            guid:match("^Vehicle%-0%-%d+%-%d+%-%d+%-(%d+)") or
            guid:match("^Pet%-0%-%d+%-%d+%-%d+%-(%d+)")
        )
        return curID == tostring(note.targetNpcID)
    elseif note.targetPlayerKey then
        -- Player match: compare stored key against current target name+realm
        local name, realm = BNB.UnitNameRealm(unit)
        realm = (realm and realm ~= "") and realm or
                GetNormalizedRealmName() or ""
        local curKey = "player:" .. (name or "") .. (realm ~= "" and ("-" .. realm) or "")
        return curKey == note.targetPlayerKey
    end
    return false
end

-- Refresh note list icons when target changes so target note portraits update live.
-- Only fires RefreshNoteList if the main window is visible — no-op otherwise.
-- Only target and inspect notes show the live portrait, so only their rows are
-- redrawn (PERF-01: tab-targeting rebuilt the whole list on every target).
BNB.RegisterEvent("PLAYER_TARGET_CHANGED", function()
    if not (BNB.mainFrame and BNB.mainFrame:IsShown()) then return end
    if BigNoteBoxDB and BigNoteBoxDB.tagTreeMode then
        if BNB.RefreshNoteList then BNB.RefreshNoteList() end
        return
    end
    for _, btn in ipairs(listEntries) do
        local note = btn:IsShown() and BNB.GetNote(btn._noteID)
        if note and (note.source == "target" or note.source == "inspect") then
            PopulateEntry(btn, note, note.id == BNB._currentNoteID, BNB._listCollapsed)
        end
    end
end)

-- Refresh the note list when tasks change so the task icon (ui-tasks) in the
-- note list row appears/disappears as tasks are added or removed.
BNB.RegisterMessage("NoteList", "TasksChanged", function(_, noteID)
    if BNB.mainFrame and BNB.mainFrame:IsShown() then
        BNB.RefreshNoteListEntry(noteID, { tasks = true })
    end
end)

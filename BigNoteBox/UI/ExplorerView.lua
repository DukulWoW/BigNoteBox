-- BigNoteBox UI/ExplorerView.lua -- Explorer note view (ALL-414)
--
-- Notes as a grid of icons that takes over the main window, as Windows
-- Explorer (Dukul, inbox 2026-10-09; scoped 2026-10-20). The note list pane
-- and the splitter are hidden; this file's pane fills the space instead.
-- The tool buttons and the search sit in the main window's toolbar strip
-- (UI/ExplorerToolbar.lua). The strip's first button is always the view
-- switch, or the back arrow in its place inside a folder or a note (Dukul,
-- 2026-10-20). A folder's header reads "Notes > Folder (N)", "Notes" going up.
--
-- The grid: Pinned (every pinned note, as the list's Pinned part), then under
-- Notes the folder tiles (A-Z), the notes in no folder, then the system
-- folders (Patch notes, Help). A folder tile opens that folder as its own
-- grid; back goes up a level. Pinned and Notes close and open with a click
-- on their header (remembered). Every part follows the sort (GetOrderedNotes
-- with noFloat, as the list), and the custom order is the list's own. A
-- search or filter shows one flat set of matching notes, no folders.
--
-- Picking (S2, as Windows Explorer): a click picks a note, Ctrl+click adds or
-- removes one, Shift+click picks every note between the last click and this
-- one (display order), a drag from empty space draws a box that picks what
-- it touches (Ctrl / Shift keep the old picks), a click on empty space clears
-- them. Double-click opens a note (one click for a Patch notes / Help note,
-- which cannot be picked). Folder tiles open on one click and are never
-- picked (Dukul, 2026-10-20: notes only). Holding a note tile drags it (or
-- every pick): onto a folder tile = into it, onto the back arrow or the
-- "Notes" part of a folder's header = out of folders, between tiles in Custom
-- sort = the custom order.
--
-- Saved: BigNoteBoxDB.explorerView (the view is on), explorerTile (tile size
-- "small" / "medium" / "large"), explorerPinnedClosed / explorerNotesClosed
-- (the two top-level headers closed). Which folder is open, the picks and whether
-- a note is open are per session; the window always opens on the grid,
-- except back from Focus mode.
--
-- PUBLIC API (BNB.Explorer):
--   EX.IsActive()           the view is on (and the notes are available)
--   EX.Mode()               nil (list view), "grid" or "note"
--   EX.SetActive(on)        switch views (the toolbar strip button)
--   EX.Back()               one step back; false when there is none (Esc)
--   EX.BuildHeader(f, sortDD, dirDD, selBtn)   MainWindow.lua's toolbar strip
--   EX.AddLeftFrames(list)  the strip's left-hand frames (BNB.ApplyToolbarIcons)
--   EX.SyncPane()           MainWindow's ApplySplit: the grid pane follows the mode
--   EX.OnWindowShow() / EX.OnWindowHide(f)   called by MainWindow's own OnShow /
--                           OnHide scripts (a HookScript made before their
--                           SetScript was thrown away: the empty window, 2026-10-20)
--   EX.State()              one line of state for a /run check
-- The tool row file reaches the grid through BNB._ExplorerKit (K below).
--------------------------------------------------------------------------------

local BNB = BigNoteBox
local L   = BNB.L

local EX = {}
BNB.Explorer = EX
local K = {}
BNB._ExplorerKit = K

local ART        = "Interface\\AddOns\\BigNoteBox\\Assets\\Explorer\\"
local VIEW_TEX   = ART .. "ex-explorer-mode"   -- Dukul's art (2026-10-20)
local LIST_TEX   = ART .. "ex-list-mode"
local DEFAULT_ICON_SIZE = "medium"
local TILE_ICON  = { small = 40, medium = 56, large = 72 }
local TILE_EXTRA = 36    -- tile width = icon + this: room for the name
local LABEL_H    = 26    -- two lines of the name under the icon
local PAD        = 10    -- the grid's inner margin
local GAP        = 6     -- between tiles
local HDR_H      = 22    -- section header row
local HDR_ICON   = 20
local HDR_RULE_A = 0.35  -- the note list's header rule alpha (ALL-328)
local HDR_ARROW  = 12    -- Pinned / Notes: the open / closed arrow
local UI_ART     = "Interface\\AddOns\\BigNoteBox\\Assets\\UI\\"
local VIEW_BTN   = 18    -- the switch, as the list's tree buttons
local BACK_BTN   = 22
local SCROLL_W   = 22    -- room for the scroll bar (it draws outside its frame)
local BOX_START  = 4     -- px the pointer moves before the picking box shows
                         -- or a pressed tile is carried
local GHOST      = 36    -- the carried tile's picture

local REFRESH_KEY = "explorerRefresh"

local _main, _sortDD, _dirDD, _selBtn, _viewBtn, _viewTx, _backBtn
local _path               -- "Notes > Folder > Note" right of the back arrow in a note
local PATH_TITLE_MAX = 320
local _pane, _sf, _child, _emptyLbl
local _crumbHdr           -- the open folder's header (its "Notes" part is a drop target)
local _tiles, _hdrs = {}, {}
local _mode   = "grid"    -- "grid" | "note", only while the view is on
local _folder             -- nil = top level, a folder id, or "sys:<key>"
local _keepNote           -- Focus mode hid the window while a note was open

-- Picks: _pick[id] = true; _order = the pickable notes as drawn; _shown =
-- their tiles; _anchor = the last plain / Ctrl click (Shift+click range)
local _pick, _order, _orderIdx, _shown = {}, {}, {}, {}
local _anchor
local _box, _boxState     -- the picking box and its drag
local _drag, _ghost, _dropLine, _dropAt   -- carrying tiles
-- Clicks are ignored until then: just after a drop, and just after a folder
-- opened (a Windows-style double-click on a folder must not open the note
-- that is now under the pointer)
local QUIET = 0.35
local function Quiet() return _dropAt and GetTime() - _dropAt < QUIET end

-- ── State ───────────────────────────────────────────────────────────────────
function EX.IsActive()
    return BNB._notesAvailable and BigNoteBoxDB and BigNoteBoxDB.explorerView == true
        and _main ~= nil or false
end

function EX.Mode()
    if not EX.IsActive() then return nil end
    return _mode
end

local function TileIcon()
    local db = BigNoteBoxDB
    return TILE_ICON[db and db.explorerTile or DEFAULT_ICON_SIZE] or TILE_ICON[DEFAULT_ICON_SIZE]
end

local function SysKey(folder)
    return type(folder) == "string" and folder:match("^sys:(.+)$") or nil
end

local function FoldersOn() return BNB.FoldersEnabled() and BNB.Folders or nil end

local function Filtering() return BNB.IsListFiltering and BNB.IsListFiltering() or false end

-- ── Header controls (toolbar strip) ─────────────────────────────────────────
-- The first button is always the switch (list view: then sort, order,
-- Select; the explorer grid: then the tool buttons). Inside a folder or a
-- note the back arrow takes the switch's place (Dukul, 2026-10-20)
local function UpdateHeader()
    local on = EX.IsActive()
    if _viewTx then _viewTx:SetTexture(on and LIST_TEX or VIEW_TEX) end
    local back = on and (_mode == "note" or _folder ~= nil)
    if _backBtn then _backBtn:SetShown(back) end
    if _viewBtn then _viewBtn:SetShown(not back) end
    if _path then _path.Update(on and _mode == "note") end
    if _sortDD then
        _sortDD:SetShown(not on)
        _dirDD:SetShown(not on)
        _selBtn:SetShown(not on)
    end
    if K.LayoutToolRow then K.LayoutToolRow() end
    if K.UpdateToolRow then K.UpdateToolRow() end
    if BNB.ApplyToolbarIcons then BNB.ApplyToolbarIcons() end
end

-- ── Picks ───────────────────────────────────────────────────────────────────
local Refresh   -- forward: tiles and the pane call it

local function Queue() BNB.Debounce(REFRESH_KEY, 0, function() Refresh() end) end

local function PaintPicks()
    for _, t in ipairs(_shown) do t._sel:SetShown(_pick[t._noteID] == true) end
    if K.OnPicks then K.OnPicks() end
end

local function ClearPicks()
    wipe(_pick); _anchor = nil
end

-- The picked notes in display order
function K.Picked()
    local ids = {}
    for _, id in ipairs(_order) do
        if _pick[id] then ids[#ids + 1] = id end
    end
    return ids
end

function K.CanPick() return #_order > 0 end

function K.SelectAll()
    for _, id in ipairs(_order) do _pick[id] = true end
    PaintPicks()
end

function K.Folder() return _folder end

-- The open user folder's id (nil at the top level or in a system folder)
function K.UserFolder()
    local FD = FoldersOn()
    return _folder and not SysKey(_folder) and FD and FD.Get(_folder) and _folder or nil
end

-- Open a folder (nil = the top level)
function K.OpenFolder(key)
    GameTooltip:Hide()
    _dropAt = GetTime()
    _folder = key
    ClearPicks()
    if _sf then _sf:SetVerticalScroll(0) end
    UpdateHeader()
    Refresh()
end

-- ── Menus shared with the tool row ──────────────────────────────────────────
function K.NewNoteHere()
    local NND = BNB.NewNoteDialog
    if not (NND and NND.Open) then return end
    -- Inside a folder the note goes in it (a system folder takes none)
    local inFolder = K.UserFolder()
    NND.Open(inFolder and { folder = inFolder } or nil)
end

function K.NewFolder() BNB.PromptFolderName({ mode = "new" }) end

-- The five sorts, a line, then Descending / Ascending (greyed in Custom)
function K.FillSortMenu(menu)
    if not (BNB.SetNoteSort and BNB.NOTE_SORT_MODES) then return end
    local function Sort() return BigNoteBoxDB.sortBy or BNB.DEFAULTS.sortBy end
    for _, m in ipairs(BNB.NOTE_SORT_MODES) do
        local key = m.key
        menu:CreateRadio(m.label, function() return Sort() == key end,
            function() BNB.SetNoteSort(key, nil) end)
    end
    menu:CreateDivider()
    local custom = Sort() == "custom"
    menu:CreateRadio(L["DIR_MODE_DESC"], function() return not BigNoteBoxDB.sortAsc end,
        function() BNB.SetNoteSort(nil, false) end, { disabled = custom })
    menu:CreateRadio(L["DIR_MODE_ASC"], function() return BigNoteBoxDB.sortAsc == true end,
        function() BNB.SetNoteSort(nil, true) end, { disabled = custom })
end

-- Tile size radios, a line, back to the list view
function K.FillViewMenu(menu)
    for _, s in ipairs({ { "small", "EXPLORER_TILE_SMALL" }, { "medium", "EXPLORER_TILE_MEDIUM" },
                         { "large", "EXPLORER_TILE_LARGE" } }) do
        local k = s[1]
        menu:CreateRadio(L[s[2]],
            function() return (BigNoteBoxDB.explorerTile or DEFAULT_ICON_SIZE) == k end,
            function() BigNoteBoxDB.explorerTile = k; Refresh() end)
    end
    menu:CreateDivider()
    menu:CreateButton(L["FOLDER_TREE_TIP_OFF"], function() EX.SetActive(false) end)
end

local function ShowEmptyMenu(owner)
    local FD = FoldersOn()
    BNB.ContextMenu.Open(owner, function(root)
        root:CreateButton(L["FOLDER_CM_NEW_NOTE"], K.NewNoteHere, { icon = "create" })
        if FD then
            root:CreateButton(L["FOLDER_CM_NEW_FOLDER"], K.NewFolder, { icon = "folder-add" })
        end
        root:CreateDivider()
        root:CreateButton(L["MW_SELECT_ALL_BTN"], K.SelectAll, { disabled = not K.CanPick() })
        root:CreateDivider()
        -- Sort by: the toolbar strip's two dropdowns in one sub-menu (Dukul,
        -- 2026-10-20); the order means nothing in Custom, so it is greyed there
        K.FillSortMenu(root:CreateButton(L["EXPLORER_CM_SORT_BY"]))
        local sub = root:CreateButton(L["EXPLORER_CM_TILE_SIZE"])
        for _, s in ipairs({ { "small", "EXPLORER_TILE_SMALL" }, { "medium", "EXPLORER_TILE_MEDIUM" },
                             { "large", "EXPLORER_TILE_LARGE" } }) do
            local k = s[1]
            sub:CreateRadio(L[s[2]],
                function() return (BigNoteBoxDB.explorerTile or DEFAULT_ICON_SIZE) == k end,
                function() BigNoteBoxDB.explorerTile = k; Refresh() end)
        end
        root:CreateDivider()
        root:CreateButton(L["FOLDER_TREE_TIP_OFF"], function() EX.SetActive(false) end)
    end)
end

-- ── The picking box ─────────────────────────────────────────────────────────
-- Pointer position in the scroll child's own units: x from its left edge, y
-- down from its top (both stay put while the grid scrolls)
local function ChildPoint()
    local s = _child:GetEffectiveScale()
    local cx, cy = GetCursorPosition()
    cx, cy = cx / s, cy / s
    return cx - (_child:GetLeft() or 0), (_child:GetTop() or 0) - cy, cy
end

local function FinishBox()
    local st = _boxState
    _boxState = nil
    if _pane then _pane:SetScript("OnUpdate", nil) end
    if _box then _box:Hide() end
    -- A click on empty space (no box drawn) clears the picks, as Windows
    if st and not st.moved and not st.add then
        ClearPicks()
        PaintPicks()
    end
end

local function BoxUpdate(_, elapsed)
    local st = _boxState
    if not st then FinishBox(); return end
    if not IsMouseButtonDown("LeftButton") then FinishBox(); return end
    local x, y, cy = ChildPoint()

    -- Near the top or bottom edge the grid scrolls, faster further out
    local range = _sf:GetVerticalScrollRange() or 0
    if range > 0 then
        local top, bottom = _sf:GetTop(), _sf:GetBottom()
        local d = 0
        if top and cy > top - 4 then d = -(cy - top + 24) * 8 * elapsed
        elseif bottom and cy < bottom + 4 then d = (bottom - cy + 24) * 8 * elapsed end
        if d ~= 0 then
            local cur = _sf:GetVerticalScroll() or 0
            _sf:SetVerticalScroll(math.max(0, math.min(range, cur + d)))
            x, y = ChildPoint()
        end
    end

    if not st.moved then
        if math.abs(x - st.x) < BOX_START and math.abs(y - st.y) < BOX_START then return end
        st.moved = true
    end
    local cw, ch = _child:GetWidth() or 0, _child:GetHeight() or 0
    x = math.max(0, math.min(cw, x)); y = math.max(0, math.min(ch, y))
    local x1, x2 = math.min(st.x, x), math.max(st.x, x)
    local y1, y2 = math.min(st.y, y), math.max(st.y, y)
    _box:ClearAllPoints()
    _box:SetPoint("TOPLEFT", _child, "TOPLEFT", x1, -y1)
    _box:SetSize(math.max(1, x2 - x1), math.max(1, y2 - y1))
    _box:Show()

    -- Picks = the old ones (Ctrl / Shift held at the start) plus every note
    -- tile the box touches
    local cl, ct = _child:GetLeft() or 0, _child:GetTop() or 0
    local changed = false
    for _, t in ipairs(_shown) do
        local l, r, tt, bb = t:GetLeft(), t:GetRight(), t:GetTop(), t:GetBottom()
        local hit = false
        if l and r and tt and bb then
            l, r, tt, bb = l - cl, r - cl, ct - tt, ct - bb
            hit = r >= x1 and l <= x2 and bb >= y1 and tt <= y2
        end
        local want = hit or (st.add and st.base[t._noteID]) or nil
        if (_pick[t._noteID] or nil) ~= want then
            _pick[t._noteID] = want
            changed = true
        end
    end
    if changed then PaintPicks() end
end

-- The picks stay as they are until the pointer moves: a plain box then picks
-- only what it touches, with Ctrl / Shift held the old picks stay too
local function StartBox()
    if _drag then return end
    local x, y = ChildPoint()
    local base = {}
    for id in pairs(_pick) do base[id] = true end
    _boxState = { x = x, y = y, moved = false, add = IsControlKeyDown() or IsShiftKeyDown(), base = base }
    _pane:SetScript("OnUpdate", BoxUpdate)
end

-- ── Carrying tiles ──────────────────────────────────────────────────────────
local function GetGhost()
    if _ghost then return _ghost end
    local g = CreateFrame("Frame", nil, UIParent)
    g:SetFrameStrata("TOOLTIP")
    g:SetSize(GHOST, GHOST)
    g:EnableMouse(false)
    g:SetAlpha(0.85)
    g._icon = g:CreateTexture(nil, "ARTWORK")
    g._icon:SetSize(GHOST, GHOST)
    g._icon:SetPoint("CENTER")
    local n = g:CreateFontString(nil, "OVERLAY", "BNBFontNormal")
    n:SetPoint("BOTTOMRIGHT", g, "BOTTOMRIGHT", 6, -6)
    g._count = n
    g:Hide()
    _ghost = g
    return g
end

local function GetDropLine()
    if _dropLine then return _dropLine end
    local l = _child:CreateTexture(nil, "OVERLAY", nil, 7)
    l:SetWidth(2)
    _dropLine = l
    return l
end

local function LightTarget(d, tile, out)
    if d.lit and d.lit ~= tile then d.lit._sel:Hide() end
    d.lit = tile
    if tile then tile._sel:Show() end
    if K.LightDropOut then K.LightDropOut(out) end
end

local function EndDrag(commit)
    local d = _drag
    _drag = nil
    BNB.ClearCursor()   -- ALL-95
    if _ghost then _ghost:Hide(); _ghost:SetScript("OnUpdate", nil) end
    if _dropLine then _dropLine:Hide() end
    if not d then return end
    LightTarget(d, nil, false)
    _dropAt = GetTime()
    if not commit then PaintPicks(); return end
    local FD = BNB.Folders
    if d.folder ~= nil and FD then
        FD.Move(d.ids, d.folder or nil)   -- false = out of folders
    elseif d.target then
        BNB.MoveNotesInOrder(d.ids, d.target, d.after)
        if BNB.RefreshNoteList then BNB.RefreshNoteList() end
    end
    PaintPicks()
end

local function DragUpdate()
    local d = _drag
    if not d then return end
    if not IsMouseButtonDown("LeftButton") then EndDrag(true); return end
    local s = UIParent:GetEffectiveScale()
    local mx, my = GetCursorPosition()
    _ghost:ClearAllPoints()
    _ghost:SetPoint("CENTER", UIParent, "BOTTOMLEFT", mx / s + GHOST / 2 + 6, my / s - GHOST / 2 - 6)

    d.folder, d.target = nil, nil
    -- A folder tile under the pointer: into it (not the one they are all in)
    for _, t in ipairs(_tiles) do
        if t:IsShown() and t._folderKey and not SysKey(t._folderKey) and t:IsMouseOver()
           and d.same ~= t._folderKey then
            d.folder = t._folderKey
            LightTarget(d, t, false)
            if _dropLine then _dropLine:Hide() end
            return
        end
    end
    -- The back arrow or the path's "Notes": out of folders
    if d.anyIn and K.OverDropOut and K.OverDropOut() then
        d.folder = false
        LightTarget(d, nil, true)
        if _dropLine then _dropLine:Hide() end
        return
    end
    LightTarget(d, nil, false)

    -- Custom sort: between tiles; the nearest tile in the pointer's row
    if not d.reorder then
        if _dropLine then _dropLine:Hide() end
        return
    end
    local cs = _child:GetEffectiveScale()
    local cx, cy = mx / cs, my / cs
    local best, bestDist
    for _, t in ipairs(_shown) do
        if t._section ~= "pinned" and not d.carried[t._noteID] then
            local tt, bb = t:GetTop(), t:GetBottom()
            if tt and bb and cy <= tt + GAP / 2 and cy >= bb - GAP / 2 then
                local mid = (t:GetLeft() + t:GetRight()) / 2
                local dist = math.abs(cx - mid)
                if not bestDist or dist < bestDist then best, bestDist = t, dist end
            end
        end
    end
    if not best then
        if _dropLine then _dropLine:Hide() end
        return
    end
    local after = cx > (best:GetLeft() + best:GetRight()) / 2
    d.target, d.after = best._noteID, after
    local line = GetDropLine()
    line:SetColorTexture(BNB.HeaderColor())
    line:ClearAllPoints()
    local cl, ct = _child:GetLeft(), _child:GetTop()
    local x = (after and best:GetRight() + GAP / 2 or best:GetLeft() - GAP / 2) - cl - 1
    line:SetPoint("TOPLEFT", _child, "TOPLEFT", x, -(ct - best:GetTop()))
    line:SetHeight(best:GetHeight())
    line:Show()
end

local function StartDrag(t)
    local id = t._noteID
    if not id or t._sys then return end
    if not _pick[id] then
        ClearPicks()
        _pick[id] = true; _anchor = id
        PaintPicks()
    end
    local ids = K.Picked()
    local carried = {}
    for _, nid in ipairs(ids) do carried[nid] = true end
    -- The folder every carried note is in (nil when they differ), any in one
    local FD = FoldersOn()
    local same, anyIn
    for i, nid in ipairs(ids) do
        local fid = FD and FD.Of(BNB.GetNote(nid)) or false
        if fid then anyIn = true end
        if i == 1 then same = fid elseif same ~= fid then same = nil end
    end
    local custom = (BigNoteBoxDB.sortBy or BNB.DEFAULTS.sortBy) == "custom"
    _drag = { ids = ids, carried = carried, same = same, anyIn = anyIn,
              reorder = custom and not Filtering() and t._section ~= "pinned" }
    if not FD and not _drag.reorder then _drag = nil; return end
    GameTooltip:Hide()
    BNB.ShowCursor("hold")
    local g = GetGhost()
    local note = BNB.GetNote(id)
    if note then BNB.PaintNoteIcon(g, g._icon, note, GHOST) end
    g._count:SetText(#ids > 1 and tostring(#ids) or "")
    g:SetScript("OnUpdate", DragUpdate)
    g:Show()
    DragUpdate()
end

-- ── Grid pane ───────────────────────────────────────────────────────────────
local function EnsurePane()
    if _pane or not _main then return end
    local pane = CreateFrame("Frame", nil, _main)
    pane:SetPoint("TOPLEFT", BNB.listPane, "TOPLEFT", 0, 0)
    pane:SetPoint("BOTTOMRIGHT", _main, "BOTTOMRIGHT", 0, 0)
    pane:Hide()
    if _main._stylePane then _main._stylePane(pane) end   -- the list pane's look (Forever glow)
    _pane = pane

    local sf = BNB.CreateScrollFrame(nil, pane)
    sf:SetPoint("TOPLEFT", pane, "TOPLEFT", PAD, -PAD)
    sf:SetPoint("BOTTOMRIGHT", pane, "BOTTOMRIGHT", -SCROLL_W, PAD)
    _sf = sf
    local bar = sf.ScrollBar
    if bar then bar:SetAlpha(0) end
    local child = CreateFrame("Frame", nil, sf)
    child:SetWidth(1); child:SetHeight(1)
    sf:SetScrollChild(child)
    _child = child
    sf:SetScript("OnSizeChanged", function(self, w)
        child:SetWidth(w or self:GetWidth())
        Queue()   -- columns follow the width
    end)
    if bar then
        sf:HookScript("OnScrollRangeChanged", function(_, _, yRange)
            bar:SetAlpha((yRange or 0) > 1 and 1 or 0)
        end)
    end
    -- Empty space: left press = the picking box, right-click = the grid's menu
    child:EnableMouse(true)
    child:SetScript("OnMouseDown", function(_, button)
        if button == "LeftButton" then StartBox() end
    end)
    child:SetScript("OnMouseUp", function(self, button)
        if button == "RightButton" then ShowEmptyMenu(self) end
    end)

    local box = BNB.CreateBackdropFrame("Frame", nil, child)
    box:EnableMouse(false)
    box:SetFrameLevel(child:GetFrameLevel() + 30)
    local r, g, b = BNB.HeaderColor()
    BNB.SetBackdrop(box, r, g, b, 0.15, r, g, b, 0.8)
    box:Hide()
    _box = box

    local lbl = child:CreateFontString(nil, "OVERLAY", "BNBFontNormal")
    lbl:SetPoint("TOP", child, "TOP", 0, -24)
    lbl:SetWidth(240); lbl:SetJustifyH("CENTER"); lbl:SetWordWrap(true)
    lbl:SetTextColor(0.38, 0.38, 0.38)
    lbl:Hide()
    _emptyLbl = lbl
end

-- Section header: picture, label, a rule to the right edge (the note list's
-- Pinned / Notes / folder headers). art = "pinned" / "notes" (section art) or
-- a folder: { folder = true, hasNotes, r, g, b }. opts.crumb = an open
-- folder's header, "Notes > Name (N)" ("Notes" goes up, and takes dropped
-- notes out of folders); opts.toggle = the saved key a click flips (Pinned /
-- Notes), with an arrow at the rule's right end: down open, up closed
local function PaintCrumb(hdr, lit)
    local hr, hg, hb = BNB.HeaderColor()
    if lit then hdr._crumbFs:SetTextColor(1, 1, 1) else hdr._crumbFs:SetTextColor(hr, hg, hb) end
end

local function PaintArrow(hdr, hover)
    local name = hdr._closed and "ui-arrow-up" or "ui-arrow-down"
    hdr._arrow:SetTexture(UI_ART .. name .. (hover and "-hover" or ""))
end

local function GetHeader(i)
    local hdr = _hdrs[i]
    if hdr then return hdr end
    hdr = CreateFrame("Button", nil, _child)
    hdr:SetHeight(HDR_H)
    hdr:RegisterForClicks("LeftButtonUp")
    local pic = hdr:CreateTexture(nil, "ARTWORK")
    pic:SetSize(HDR_ICON, HDR_ICON)
    pic:SetPoint("LEFT", hdr, "LEFT", 0, 0)
    -- "Notes >" in front of an open folder's name
    local crumb = CreateFrame("Button", nil, hdr)
    crumb:SetHeight(HDR_H)
    crumb:SetPoint("LEFT", pic, "RIGHT", 2, 0)
    local cfs = crumb:CreateFontString(nil, "OVERLAY", "BNBFontNormalSmall")
    cfs:SetPoint("LEFT", crumb, "LEFT", 2, 0)
    cfs:SetText(L["EXPLORER_PATH_ROOT"])
    hdr._crumbFs = cfs
    crumb:SetScript("OnClick", function() K.OpenFolder(nil) end)
    crumb:SetScript("OnEnter", function(self)
        PaintCrumb(hdr, true)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:AddLine(L["EXPLORER_PATH_ROOT"], 1, 1, 1)
        GameTooltip:AddLine(L["EXPLORER_PATH_ROOT_TIP"], 0.85, 0.85, 0.85, true)
        GameTooltip:Show()
    end)
    crumb:SetScript("OnLeave", function(self)
        PaintCrumb(hdr, false)
        if GameTooltip:IsOwned(self) then GameTooltip:Hide() end
    end)
    crumb:Hide()
    hdr._crumb = crumb
    local sep = hdr:CreateFontString(nil, "OVERLAY", "BNBFontNormalSmall")
    sep:SetPoint("LEFT", crumb, "RIGHT", 2, 0)
    sep:SetText(">")
    sep:SetTextColor(0.55, 0.55, 0.55)
    sep:Hide()
    hdr._sep = sep
    local fs = hdr:CreateFontString(nil, "OVERLAY", "BNBFontNormalSmall")
    fs:SetJustifyH("LEFT"); fs:SetWordWrap(false)
    local arrow = hdr:CreateTexture(nil, "ARTWORK")
    arrow:SetSize(HDR_ARROW, HDR_ARROW)
    arrow:SetPoint("RIGHT", hdr, "RIGHT", 0, 0)
    arrow:Hide()
    hdr._arrow = arrow
    local rule = hdr:CreateTexture(nil, "ARTWORK")
    if rule.SetSnapToPixelGrid then rule:SetSnapToPixelGrid(false); rule:SetTexelSnappingBias(0) end
    if PixelUtil and PixelUtil.SetHeight then PixelUtil.SetHeight(rule, 1, 1) else rule:SetHeight(1) end
    hdr._pic, hdr._text, hdr._rule = pic, fs, rule
    -- Pinned / Notes: a click closes or opens the part (remembered)
    hdr:SetScript("OnClick", function(self)
        if not self._toggle or not BigNoteBoxDB then return end
        BigNoteBoxDB[self._toggle] = not BigNoteBoxDB[self._toggle] or nil
        Refresh()
    end)
    hdr:SetScript("OnEnter", function(self) if self._toggle then PaintArrow(self, true) end end)
    hdr:SetScript("OnLeave", function(self) if self._toggle then PaintArrow(self, false) end end)
    _hdrs[i] = hdr
    return hdr
end

local function PaintHeader(hdr, text, art, r, g, b, opts)
    opts = opts or {}
    local hr, hg, hb = BNB.HeaderColor()
    r, g, b = r or hr, g or hg, b or hb
    if type(art) == "table" then
        BNB.Folders.PaintArt(hdr._pic, true, art.hasNotes, r, g, b)
    else
        BNB.Folders.PaintSectionArt(hdr._pic, art, hr, hg, hb)
    end
    -- The path in front of a folder's name
    hdr._crumb:SetShown(opts.crumb and true or false)
    hdr._sep:SetShown(opts.crumb and true or false)
    hdr._text:ClearAllPoints()
    if opts.crumb then
        hdr._crumb:SetWidth(math.ceil(hdr._crumbFs:GetStringWidth() or 0) + 4)
        PaintCrumb(hdr, false)
        hdr._text:SetPoint("LEFT", hdr._sep, "RIGHT", 4, 0)
        _crumbHdr = hdr
    else
        hdr._text:SetPoint("LEFT", hdr._pic, "RIGHT", 4, 0)
    end
    hdr._text:SetText(text)
    hdr._text:SetTextColor(r, g, b)
    -- Pinned / Notes: clickable, the arrow at the rule's end
    hdr._toggle = opts.toggle
    hdr._closed = opts.closed and true or false
    hdr:EnableMouse(opts.toggle ~= nil)   -- else the picking box starts over it
    hdr._rule:ClearAllPoints()
    hdr._rule:SetPoint("LEFT", hdr._text, "RIGHT", 6, 0)
    if opts.toggle then
        PaintArrow(hdr, hdr:IsMouseOver())   -- the list's collapse arrow art, untinted
        hdr._arrow:Show()
        hdr._rule:SetPoint("RIGHT", hdr._arrow, "LEFT", -4, 0)
    else
        hdr._arrow:Hide()
        hdr._rule:SetPoint("RIGHT", hdr, "RIGHT", 0, 0)
    end
    hdr._rule:SetColorTexture(r, g, b, HDR_RULE_A)
end

-- Dropping carried notes on the back arrow or a folder header's "Notes":
-- out of folders
function K.OverDropOut()
    if _backBtn and _backBtn:IsVisible() and _backBtn:IsMouseOver() then return true end
    local c = _crumbHdr and _crumbHdr._crumb
    return c and c:IsVisible() and c:IsMouseOver() or false
end

function K.LightDropOut(on)
    if _crumbHdr and _crumbHdr._crumb:IsVisible() then PaintCrumb(_crumbHdr, on) end
end

-- ── Tiles ───────────────────────────────────────────────────────────────────
local function OpenNote(id)
    GameTooltip:Hide()
    if BNB._currentNoteID == id then
        _mode = "note"
        EX.Apply()
    else
        BNB.SaveCurrentNote()
        BNB.SelectNote(id)   -- NoteSelected switches to the note
    end
end

local function PickClick(id)
    if IsShiftKeyDown() and _anchor and _orderIdx[_anchor] then
        -- Every note between the last click and this one; Ctrl keeps the rest
        if not IsControlKeyDown() then wipe(_pick) end
        local a, b = _orderIdx[_anchor], _orderIdx[id]
        if a > b then a, b = b, a end
        for i = a, b do _pick[_order[i]] = true end
    elseif IsControlKeyDown() then
        _pick[id] = (not _pick[id]) or nil
        _anchor = id
    else
        wipe(_pick)
        _pick[id] = true
        _anchor = id
    end
    PaintPicks()
end

local function TileClick(self, button)
    if self._folderKey then
        if Quiet() then return end
        if button == "RightButton" then
            local sys = SysKey(self._folderKey)
            if sys then
                if BNB.ShowSystemFolderMenu then BNB.ShowSystemFolderMenu(self, sys) end
            elseif BNB.ShowFolderMenu then
                BNB.ShowFolderMenu(self, self._folderKey)
            end
            return
        end
        K.OpenFolder(self._folderKey)
        return
    end
    local id = self._noteID
    if not id then return end
    if button == "RightButton" then
        if self._sys then
            if BNB.ShowSystemNoteMenu then BNB.ShowSystemNoteMenu(self, id) end
            return
        end
        -- On a pick with others picked: the menu for all of them; else this
        -- note alone is picked (Windows)
        local ids = K.Picked()
        if _pick[id] and #ids > 1 then
            BNB.ShowMultiNoteContextMenu(self, ids)
        else
            wipe(_pick); _pick[id] = true; _anchor = id
            PaintPicks()
            BNB.ShowNoteContextMenu(self, id)
        end
        return
    end
    if Quiet() then return end   -- the end of a carry, a folder just opened
    if self._sys then OpenNote(id); return end
    PickClick(id)
end

local function TileDoubleClick(self, button)
    if button ~= "LeftButton" or not self._noteID or self._sys then return end
    if Quiet() then return end
    OpenNote(self._noteID)
end

local function TileEnter(self)
    if _drag or _boxState then return end
    if self._noteID then
        BNB.ShowNoteListTooltip(self, self._noteID, true)   -- title on top: names wrap
        return
    end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine((self._folderName or "") .. " (" .. (self._count or 0) .. ")")
    GameTooltip:AddLine(L["EXPLORER_FOLDER_TIP"], 0.85, 0.85, 0.85, true)
    GameTooltip:Show()
end

local function TileLeave(self)
    if GameTooltip:IsOwned(self) then GameTooltip:Hide() end
end

-- A pressed note tile is carried once the pointer moves a few px (Windows):
-- no hold time, so a slow click stays a click
local function TileMouseDown(self, button)
    if button ~= "LeftButton" or not self._noteID or self._sys then return end
    local sx, sy = GetCursorPosition()
    self:SetScript("OnUpdate", function(s)
        if not IsMouseButtonDown("LeftButton") or not s:IsVisible() then
            s:SetScript("OnUpdate", nil); return
        end
        local cx, cy = GetCursorPosition()
        local sc = s:GetEffectiveScale()
        if math.abs(cx - sx) / sc > BOX_START or math.abs(cy - sy) / sc > BOX_START then
            s:SetScript("OnUpdate", nil)
            StartDrag(s)
        end
    end)
end

local function TileMouseUp(self, button)
    if button ~= "LeftButton" then return end
    self:SetScript("OnUpdate", nil)
    if _drag then EndDrag(true) end
end

-- Status markers on the icon's corners, the list rows' pictures: favourite
-- top right, alarm bottom right, situation top left, location left, lock
-- bottom left
local MARKERS = {
    { "_mFav",  "favorite",  "TOPRIGHT",    2,  2 },
    { "_mAlarm", "alarm",    "BOTTOMRIGHT", 2, -2 },
    { "_mSitu", "situation", "TOPLEFT",    -2,  2 },
    { "_mLoc",  "location",  "LEFT",       -2,  0 },
}

-- Hover and pick art. Normal look: the collapsed note list's square pictures
-- (icon + 12 px on a side, centred on the icon, drawn over its border, BNB
-- green), not the wide row art (Dukul, 2026-10-20). Skin mode: the list's
-- flat fills over the whole tile. sub = the OVERLAY sub-level, as the list
local SQ_ART  = "Interface\\AddOns\\BigNoteBox\\Assets\\UI\\ui-note-list-collapsed-"
local SQ_GROW = 12
local function TileArt(t, kind, sub, fill)
    if BigNoteBoxDB and BigNoteBoxDB.skinMode then
        return BNB.CreateListRowArt(t, kind, fill)
    end
    local tex = t:CreateTexture(nil, "OVERLAY", nil, sub)
    tex:SetTexture(SQ_ART .. kind)
    tex:SetVertexColor(0.40, 0.85, 0.40)   -- NoteList COL_SEL_BG
    tex:SetPoint("CENTER", t._icon, "CENTER", 0, 0)
    tex._square = true
    tex:Hide()
    return tex
end

local function GetTile(i)
    local t = _tiles[i]
    if t then return t end
    t = CreateFrame("Button", nil, _child)
    t:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    t._icon = t:CreateTexture(nil, "ARTWORK")
    t._folderTex = t:CreateTexture(nil, "ARTWORK")
    t._sel   = TileArt(t, "selection", 2, { 0.40, 0.85, 0.40, 0.18 })
    t._hover = TileArt(t, "hover", 4, { 1, 1, 1, 0.06 })
    t:HookScript("OnEnter", function(self) self._hover:Show() end)
    t:HookScript("OnLeave", function(self) self._hover:Hide() end)
    t:HookScript("OnHide",  function(self) self._hover:Hide() end)
    local fs = t:CreateFontString(nil, "OVERLAY", "BNBFontHighlightSmall")
    fs:SetJustifyH("CENTER"); fs:SetJustifyV("TOP")
    fs:SetWordWrap(true)
    if fs.SetMaxLines then fs:SetMaxLines(2) end
    t._label = fs
    -- Markers above the icon's frame / border art
    local ov = CreateFrame("Frame", nil, t)
    ov:SetAllPoints(t._icon)
    ov:SetFrameLevel(t:GetFrameLevel() + 10)
    ov:EnableMouse(false)
    t._ov = ov
    for _, m in ipairs(MARKERS) do
        local mk = BNB.CreateIconMarker(ov, m[2])
        mk:SetPoint(m[3], ov, m[3], m[4], m[5])
        t[m[1]] = mk
    end
    local lock = ov:CreateTexture(nil, "OVERLAY")
    lock:SetTexture("Interface\\AddOns\\BigNoteBox\\Assets\\" .. BNB.AbIcon("lock"))
    lock:SetPoint("BOTTOMLEFT", ov, "BOTTOMLEFT", -2, -2)
    lock:Hide()
    t._mLock = lock
    t:SetScript("OnClick", TileClick)
    t:SetScript("OnDoubleClick", TileDoubleClick)
    t:SetScript("OnEnter", TileEnter)
    t:SetScript("OnLeave", TileLeave)
    t:SetScript("OnMouseDown", TileMouseDown)
    t:SetScript("OnMouseUp", TileMouseUp)
    _tiles[i] = t
    return t
end

local function ShapeTile(t, size)
    local w = size + TILE_EXTRA
    t:SetSize(w, 6 + size + 4 + LABEL_H + 4)
    for _, tex in ipairs({ t._icon, t._folderTex }) do
        tex:SetSize(size, size)
        tex:ClearAllPoints()
        tex:SetPoint("TOP", t, "TOP", 0, -6)
    end
    t._label:ClearAllPoints()
    t._label:SetPoint("TOP", t._icon, "BOTTOM", 0, -4)
    t._label:SetWidth(w - 6)
    t._label:SetHeight(LABEL_H)
    for _, tex in ipairs({ t._sel, t._hover }) do
        if tex._square then tex:SetSize(size + SQ_GROW, size + SQ_GROW) end
    end
    local ms = math.max(12, math.floor(size * 0.36))
    for _, m in ipairs(MARKERS) do t[m[1]]:SetSize(ms, ms) end
    t._mLock:SetSize(math.floor(ms * 0.8), math.floor(ms * 0.8))
end

local function HideMarkers(t)
    for _, m in ipairs(MARKERS) do t[m[1]]:Hide() end
    t._mLock:Hide()
end

local function FillNoteTile(t, note, size, section)
    t._noteID, t._sys, t._folderKey, t._folderName = note.id, note.system, nil, nil
    t._section = section
    t._folderTex:Hide()
    t._icon:Show()
    BNB.PaintNoteIcon(t, t._icon, note, size)
    local hasTitle = note.title and note.title ~= ""
    t._label:SetText(hasTitle and note.title or L["UNTITLED"])
    local tc = note.titleColor
    if tc then t._label:SetTextColor(tc.r, tc.g, tc.b, 1)
    else t._label:SetTextColor(BNB.TextWhite(hasTitle and 1 or 0.5)) end
    t._sel:SetShown(_pick[note.id] == true)
    if note.system then HideMarkers(t); return end
    local situ = BNB.SituationsEnabled() and BNB.HasSituation(note)
    t._mFav:SetShown(note.favorited and true or false)
    t._mAlarm:SetShown(BNB.AlarmsEnabled() and note.alarm ~= nil)
    t._mSitu:SetShown(situ and true or false)
    t._mLoc:SetShown(situ and BNB.HasActiveWaypoint(note) and true or false)
    local NK = BNB._NoteListKit
    t._mLock:SetShown(NK and NK.NoteIsLocked and NK.NoteIsLocked(note) and true or false)
end

-- key = a folder id or "sys:<key>"; name already plain text; r, g, b = its colour
local function FillFolderTile(t, key, name, n, r, g, b)
    t._noteID, t._sys, t._folderKey, t._folderName, t._count = nil, nil, key, name, n
    t._section = nil
    t._icon:Hide()
    BNB.ApplyIconFrame(t._icon, nil)   -- a note's frame art left on a reused tile
    if t._borderFrame then t._borderFrame:Hide() end
    HideMarkers(t)
    local hr, hg, hb = BNB.HeaderColor()
    BNB.Folders.PaintArt(t._folderTex, false, n > 0, r or hr, g or hg, b or hb)
    t._folderTex:Show()
    t._label:SetText(name .. " (" .. n .. ")")
    t._label:SetTextColor(r or hr, g or hg, b or hb)
    t._sel:Hide()
end

-- ── Drawing ─────────────────────────────────────────────────────────────────
-- Redraw trace for EX.State (the empty window after a reload, 2026-10-20):
-- calls, finished draws, why the last call drew nothing, the last error
local _trace = { calls = 0, drawn = 0 }
local Draw

Refresh = function()
    _trace.calls = _trace.calls + 1
    local skip
    if not EX.IsActive() then skip = "inactive"
    elseif _mode ~= "grid" then skip = "mode"
    elseif not _pane then skip = "nopane"
    elseif not _pane:IsVisible() then skip = "hidden"
    elseif _drag then skip = "drag" end   -- a redraw under a carried tile; EndDrag redraws
    _trace.skip = skip
    if skip then return end
    local ok, err = xpcall(Draw, function(msg)
        return tostring(msg) .. " | " .. tostring(debugstack and debugstack(2, 3, 0) or "")
    end)
    if ok then
        _trace.drawn = _trace.drawn + 1
    else
        _trace.err = err
        geterrorhandler()(err)
    end
end

Draw = function()
    BNB.CancelDebounce(REFRESH_KEY)
    local FD  = FoldersOn()
    local SYS = BNB.SystemNotes
    local size = TileIcon()
    local tileW = size + TILE_EXTRA
    local tileH = 6 + size + 4 + LABEL_H + 4
    local width = _child:GetWidth()
    if not width or width < tileW then width = tileW end
    local cols = math.max(1, math.floor((width + GAP) / (tileW + GAP)))

    for _, t in ipairs(_tiles) do t:Hide() end
    for _, h in ipairs(_hdrs) do h:Hide() end
    _emptyLbl:Hide()
    wipe(_order); wipe(_orderIdx); wipe(_shown)
    _crumbHdr = nil

    -- An open folder that is gone (deleted, module or setting off): top level
    local sys = SysKey(_folder)
    if _folder and not sys and not (FD and FD.Get(_folder)) then _folder = nil end
    if sys then
        local found
        for _, p in ipairs(SYS and SYS.Folders() or {}) do
            if p.key == sys then found = true; break end
        end
        if not found then _folder, sys = nil, nil end
    end
    UpdateHeader()

    local y, ti, hi = 0, 0, 0
    local function Header(text, art, r, g, b, opts)
        hi = hi + 1
        local hdr = GetHeader(hi)
        PaintHeader(hdr, text, art, r, g, b, opts)
        hdr:ClearAllPoints()
        hdr:SetPoint("TOPLEFT", _child, "TOPLEFT", 0, -y)
        hdr:SetPoint("TOPRIGHT", _child, "TOPRIGHT", -4, -y)
        hdr:Show()
        y = y + HDR_H + 4
    end
    -- Tiles flow left to right; col carries on across Flow calls in one part
    local col = 0
    local function Place(t)
        ShapeTile(t, size)
        t:ClearAllPoints()
        t:SetPoint("TOPLEFT", _child, "TOPLEFT", col * (tileW + GAP), -y)
        t:Show()
        col = col + 1
        if col >= cols then col = 0; y = y + tileH + GAP end
    end
    local function EndRow()
        if col > 0 then col = 0; y = y + tileH + GAP end
    end
    local function NoteTile(note, section)
        ti = ti + 1
        local t = GetTile(ti)
        if not note.system and not _orderIdx[note.id] then
            _order[#_order + 1] = note.id
            _orderIdx[note.id] = #_order
            _shown[#_shown + 1] = t
        end
        FillNoteTile(t, note, size, section)
        Place(t)
    end
    local function FolderTile(key, name, n, r, g, b)
        ti = ti + 1
        local t = GetTile(ti)
        FillFolderTile(t, key, name, n, r, g, b)
        Place(t)
    end
    local function Empty(key)
        _emptyLbl:SetText(L[key]); _emptyLbl:Show()
    end

    local filtering = Filtering()
    local filterText = BNB.GetCurrentFilter and BNB.GetCurrentFilter() or ""
    local notes = BNB.GetOrderedNotes(filterText, BNB.GetCurrentTagFilter and BNB.GetCurrentTagFilter(), true)
    -- System notes match the search text only: a tag, favourite or task
    -- filter hides them (they have none of those), as in the list
    local lower = filterText ~= "" and filterText:lower() or nil
    local sysOK = not filtering or (lower ~= nil and not BNB.GetCurrentTagFilter()
        and not BNB._favFilterActive and not BNB._taskFilterActive)
    local function SysList(key)
        if not sysOK then return {} end
        if filtering then return SYS.Search(key, lower) end
        return SYS.Notes(key)
    end

    if sys then
        -- ── A system folder ─────────────────────────────────────────────────
        local p = SYS.Provider(sys)
        local list = SysList(sys)
        Header(L[p.name] .. " (" .. #list .. ")", { hasNotes = #list > 0 }, p.r, p.g, p.b, { crumb = true })
        for _, n in ipairs(list) do NoteTile(n, "sys") end
        EndRow()
        if #list == 0 then Empty(filtering and "NL_NO_MATCHES" or "EXPLORER_FOLDER_EMPTY") end
    elseif _folder then
        -- ── A folder: its notes, pinned ones too ────────────────────────────
        local list = {}
        for _, n in ipairs(notes) do
            if FD.Of(n) == _folder then list[#list + 1] = n end
        end
        local r, g, b = FD.Color(_folder)
        local rec = FD.Get(_folder)
        Header((rec.name or "") .. " (" .. #list .. ")", { hasNotes = #list > 0 }, r, g, b, { crumb = true })
        for _, n in ipairs(list) do NoteTile(n, _folder) end
        EndRow()
        if #list == 0 then Empty(filtering and "NL_NO_MATCHES" or "EXPLORER_FOLDER_EMPTY") end
    elseif filtering then
        -- ── A search or filter: one flat set, no folders (Dukul, 2026-10-20)
        local sysHits = {}
        for _, p in ipairs(SYS and SYS.Folders() or {}) do
            for _, n in ipairs(SysList(p.key)) do sysHits[#sysHits + 1] = n end
        end
        Header(string.format(L["EXPLORER_HDR_RESULTS_FMT"], #notes + #sysHits), "notes")
        for _, n in ipairs(notes) do NoteTile(n, "results") end
        for _, n in ipairs(sysHits) do NoteTile(n, "sys") end
        EndRow()
        if #notes + #sysHits == 0 then Empty("NL_NO_MATCHES") end
    else
        -- ── Top level: Pinned, then Notes (folders, notes, system folders) ──
        local pinned, regular, folderN = {}, {}, {}
        for _, n in ipairs(notes) do
            local fid = FD and FD.Of(n)
            if fid then folderN[fid] = (folderN[fid] or 0) + 1 end
            if n.pinned then pinned[#pinned + 1] = n
            elseif not fid then regular[#regular + 1] = n end
        end
        -- A folder shows when it holds a note on this tab; an empty one on
        -- every tab, so it can be filled (as the list)
        local folders = {}
        if FD then
            local total = FD.Counts()
            for _, f in ipairs(FD.List()) do
                if folderN[f.id] or not total[f.id] then folders[#folders + 1] = f end
            end
        end
        local sysFolders = {}
        for _, p in ipairs(SYS and SYS.Folders() or {}) do
            local n = #SYS.Notes(p.key)
            if n > 0 then sysFolders[#sysFolders + 1] = { p = p, n = n } end
        end

        local db = BigNoteBoxDB
        if #pinned > 0 then
            local closed = db.explorerPinnedClosed == true
            Header(string.format(L["NL_HDR_PINNED_FMT"], #pinned), "pinned", nil, nil, nil,
                { toggle = "explorerPinnedClosed", closed = closed })
            if not closed then
                for _, n in ipairs(pinned) do NoteTile(n, "pinned") end
                EndRow()
            end
            y = y + 4
        end
        local notesClosed = false
        if #pinned > 0 or #folders > 0 or #regular > 0 then
            notesClosed = db.explorerNotesClosed == true
            Header(string.format(L["NL_HDR_REGULAR_FMT"], #regular), "notes", nil, nil, nil,
                { toggle = "explorerNotesClosed", closed = notesClosed })
        end
        if not notesClosed then
            -- Folder tiles, Patch notes / Help with them (Dukul, 2026-10-20:
            -- alone at the bottom they looked odd), then the notes
            for _, f in ipairs(folders) do
                local r, g, b = FD.Color(f.id)
                FolderTile(f.id, f.name, folderN[f.id] or 0, r, g, b)
            end
            for _, s in ipairs(sysFolders) do
                FolderTile("sys:" .. s.p.key, L[s.p.name], s.n, s.p.r, s.p.g, s.p.b)
            end
            for _, n in ipairs(regular) do NoteTile(n, "notes") end
            EndRow()
        end
        if #notes == 0 and #folders == 0 and #sysFolders == 0 then
            Empty("NOTE_LIST_EMPTY")
            y = 80
        end
    end

    -- Picks no longer drawn (deleted, filtered out) are dropped
    for id in pairs(_pick) do
        if not _orderIdx[id] then _pick[id] = nil end
    end
    if _anchor and not _orderIdx[_anchor] then _anchor = nil end
    PaintPicks()

    _child:SetHeight(math.max(y, _sf:GetHeight() or 1))
end

function K.Refresh() Refresh() end

-- ── Switching ───────────────────────────────────────────────────────────────
-- The grid pane follows the mode; MainWindow's ApplySplit calls it on every
-- layout. At login the view becomes active after EX.Apply first ran (the
-- notes load later): without this the list and editor were hidden and no
-- grid shown, an empty window (Dukul, 2026-10-20)
function EX.SyncPane()
    local grid = EX.Mode() == "grid"
    if grid then EnsurePane() end
    if not _pane then return end
    local was = _pane:IsShown()
    _pane:SetShown(grid)
    if grid and not was then UpdateHeader() end
    if grid then Queue() end
end

function EX.State()
    local shown = 0
    for _, t in ipairs(_tiles) do if t:IsShown() then shown = shown + 1 end end
    local function Size(fr)
        if not fr then return "-" end
        return string.format("%dx%d", fr:GetWidth() or -1, fr:GetHeight() or -1)
    end
    return string.format("active=%s mode=%s folder=%s pane=%s/%s list=%s editor=%s main=%s"
        .. " | calls=%d drawn=%d skip=%s tiles=%d/%d pane=%s sf=%s child=%s err=%s",
        tostring(EX.IsActive()), tostring(_mode), tostring(_folder),
        tostring(_pane and _pane:IsShown()), tostring(_pane and _pane:IsVisible()),
        tostring(BNB.listPane and BNB.listPane:IsShown()), tostring(BNB.editorPane and BNB.editorPane:IsShown()),
        tostring(_main and _main:IsShown()),
        _trace.calls, _trace.drawn, tostring(_trace.skip), shown, #_tiles,
        Size(_pane), Size(_sf), Size(_child), tostring(_trace.err and _trace.err:sub(1, 300)))
end

-- Lays the window out for the current view and mode
function EX.Apply()
    local active = EX.IsActive()
    if active then EnsurePane() end
    if _pane then _pane:SetShown(active and _mode == "grid") end
    if BNB._applyMainSplit then BNB._applyMainSplit() end
    UpdateHeader()
    if active and _mode == "grid" then
        if K.LayoutToolRow then K.LayoutToolRow() end   -- takes the search row
        Refresh()
    end
end

function EX.SetActive(on)
    on = on and true or false
    if not (BigNoteBoxDB and _main) or on == EX.IsActive() then return end
    if _boxState then FinishBox() end
    if _drag then EndDrag(false) end
    BNB.SaveCurrentNote()
    BigNoteBoxDB.explorerView = on
    if on then
        -- The list's Select mode has no meaning here; the search and filters
        -- carry over (the grid shows them, the tool row has the search row)
        if BNB.IsMultiMode and BNB.IsMultiMode() then BNB.SetMultiMode(false) end
        _mode, _folder = "grid", nil
        ClearPicks()
    end
    EX.Apply()
    if not on then
        if BNB.DockListSearch then BNB.DockListSearch(nil) end
        if BNB.RefreshNoteList then BNB.RefreshNoteList() end
        if BNB._currentNoteID and BNB.ScrollNoteListTo then BNB.ScrollNoteListTo(BNB._currentNoteID) end
    end
end

function EX.Back()
    if not EX.IsActive() then return false end
    -- Esc closes the open search field first (it clears the search)
    if _mode == "grid" and K.CloseSearch and K.CloseSearch() then return true end
    if _mode == "note" then
        BNB.SaveCurrentNote()
        _mode = "grid"
        -- The note just read stays picked, as Windows keeps it selected
        local cur = BNB._currentNoteID
        ClearPicks()
        if cur then _pick[cur] = true; _anchor = cur end
    elseif _folder then
        _folder = nil
        ClearPicks()
        if _sf then _sf:SetVerticalScroll(0) end
    else
        return false
    end
    EX.Apply()
    return true
end

-- ── Toolbar strip: the switch and the back arrow ────────────────────────────
function EX.BuildHeader(f, sortDD, dirDD, selBtn)
    _main, _sortDD, _dirDD, _selBtn = f, sortDD, dirDD, selBtn

    -- The switch and the back arrow sit where the sort dropdown was, which
    -- moves right of the switch (Dukul, 2026-10-20: the switch is always first)
    local lead = CreateFrame("Frame", nil, f)
    local p, rel, rp, x, y = sortDD:GetPoint(1)
    lead:SetPoint(p, rel, rp, x, y)
    lead:SetSize(VIEW_BTN, sortDD:GetHeight())
    if f._liftFrames then f._liftFrames[#f._liftFrames + 1] = lead end   -- /bnb topbar lift

    -- The switch: Dukul's art tinted like the search row's tree buttons
    local vb = CreateFrame("Button", nil, f)
    vb:SetSize(VIEW_BTN, VIEW_BTN)
    vb:SetPoint("LEFT", lead, "LEFT", 0, 0)
    sortDD:ClearAllPoints()
    sortDD:SetPoint("LEFT", vb, "RIGHT", 6, 0)
    local tx = vb:CreateTexture(nil, "ARTWORK")
    tx:SetAllPoints()
    BNB.TintUIIcon(tx)
    BNB.AddUIIconHover(vb, tx)
    _viewTx, _viewBtn = tx, vb
    vb:SetScript("OnClick", function() EX.SetActive(not EX.IsActive()) end)
    vb:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        if EX.IsActive() then
            GameTooltip:AddLine(L["FOLDER_TREE_TIP_OFF"], 1, 1, 1)
        else
            GameTooltip:AddLine(L["EXPLORER_TIP_ON"], 1, 1, 1)
            GameTooltip:AddLine(L["EXPLORER_TIP_SUB"], 0.85, 0.85, 0.85, true)
        end
        GameTooltip:Show()
    end)
    vb:SetScript("OnLeave", function() GameTooltip:Hide() end)
    selBtn:SetPoint("LEFT", dirDD, "RIGHT", 6, 0)

    -- Back from a note or a folder: the Settings sub-page arrow
    -- (ConfigWindow.lua NewSubPage), in the switch's place
    local back = BNB.CreateIconButton(f, BACK_BTN, "left", {
        onClick = function() EX.Back() end,
        tip = L["CFG_SUBPAGE_BACK"], tipAnchor = "ANCHOR_RIGHT" })
    back:SetPoint("LEFT", lead, "LEFT", -2, 0)
    back:Hide()
    _backBtn = back

    -- The tool buttons and the search icon (UI/ExplorerToolbar.lua)
    if K.BuildStrip then K.BuildStrip(f, lead) end
    f:HookScript("OnSizeChanged", function()
        if K.LayoutToolRow then K.LayoutToolRow() end
    end)

    -- In a note: "Notes > Folder > Note name" right of the back arrow (Dukul,
    -- 2026-10-20); Notes and the folder take you there
    _path = EX.BuildPath(f, back)
    UpdateHeader()
end

-- Leaving the open note for the grid, at the top or in a folder
local function GoToGrid(folder)
    BNB.SaveCurrentNote()
    _mode, _folder = "grid", folder
    local cur = BNB._currentNoteID
    ClearPicks()
    if cur then _pick[cur] = true; _anchor = cur end
    if _sf then _sf:SetVerticalScroll(0) end
    EX.Apply()
end

function EX.BuildPath(f, back)
    local P = CreateFrame("Frame", nil, f)
    P:SetHeight(BACK_BTN)
    P:SetPoint("LEFT", back, "RIGHT", 6, 0)
    P:Hide()
    local function Crumb(onClick)
        local b = CreateFrame("Button", nil, P)
        b:SetHeight(BACK_BTN)
        local fs = b:CreateFontString(nil, "OVERLAY", "BNBFontNormal")
        fs:SetPoint("LEFT", b, "LEFT", 0, 0)
        fs:SetWordWrap(false)
        b._fs = fs
        b:SetScript("OnEnter", function(self) self._fs:SetTextColor(1, 1, 1) end)
        b:SetScript("OnLeave", function(self) self._fs:SetTextColor(self._r, self._g, self._b) end)
        b:SetScript("OnClick", onClick)
        return b
    end
    local function Sep()
        local s = P:CreateFontString(nil, "OVERLAY", "BNBFontNormal")
        s:SetText(">")
        s:SetTextColor(0.55, 0.55, 0.55)
        return s
    end
    local rootC = Crumb(function() GoToGrid(nil) end)
    rootC._fs:SetText(L["EXPLORER_PATH_ROOT"])
    local sep1, sep2 = Sep(), Sep()
    local folderC = Crumb(function(self) GoToGrid(self._key) end)
    local title = P:CreateFontString(nil, "OVERLAY", "BNBFontNormal")
    title:SetJustifyH("LEFT")
    title:SetWordWrap(false)
    local function Width(fs) return math.ceil(fs:GetStringWidth() or 0) end

    function P.Update(show)
        P:SetShown(show and true or false)
        if not show then return end
        local hr, hg, hb = BNB.HeaderColor()
        rootC._r, rootC._g, rootC._b = hr, hg, hb
        rootC._fs:SetTextColor(hr, hg, hb)
        rootC:SetWidth(Width(rootC._fs))
        rootC:ClearAllPoints()
        rootC:SetPoint("LEFT", P, "LEFT", 0, 0)
        sep1:ClearAllPoints()
        sep1:SetPoint("LEFT", rootC, "RIGHT", 6, 0)
        -- The folder the note was opened from (back goes there)
        local name, r, g, b
        local sys = SysKey(_folder)
        if sys then
            local pr = BNB.SystemNotes and BNB.SystemNotes.Provider(sys)
            if pr then name, r, g, b = L[pr.name], pr.r, pr.g, pr.b end
        elseif _folder and BNB.Folders and BNB.Folders.Get(_folder) then
            name = BNB.Folders.Get(_folder).name
            r, g, b = BNB.Folders.Color(_folder)
        end
        local after = sep1
        local w = rootC:GetWidth() + 6 + Width(sep1) + 6
        if name then
            folderC._key = _folder
            folderC._r, folderC._g, folderC._b = r or hr, g or hg, b or hb
            folderC._fs:SetText(name)
            folderC._fs:SetTextColor(folderC._r, folderC._g, folderC._b)
            folderC:SetWidth(Width(folderC._fs))
            folderC:ClearAllPoints()
            folderC:SetPoint("LEFT", sep1, "RIGHT", 6, 0)
            folderC:Show()
            sep2:ClearAllPoints()
            sep2:SetPoint("LEFT", folderC, "RIGHT", 6, 0)
            sep2:Show()
            after = sep2
            w = w + folderC:GetWidth() + 6 + Width(sep2) + 6
        else
            folderC:Hide()
            sep2:Hide()
        end
        local note = BNB._currentNoteID and BNB.GetNote(BNB._currentNoteID)
        local t = note and note.title ~= "" and note.title or L["UNTITLED"]
        title:SetText(t)
        local tc = note and note.titleColor
        if tc then title:SetTextColor(tc.r, tc.g, tc.b) else title:SetTextColor(BNB.TextWhite(1)) end
        local tw = math.min(Width(title) + 2, PATH_TITLE_MAX)
        title:SetWidth(tw)
        title:ClearAllPoints()
        title:SetPoint("LEFT", after, "RIGHT", 6, 0)
        P:SetWidth(w + tw)   -- the right-hand icons stop before it
    end
    return P
end

-- MainWindow's OnShow, after it selected the last note again: the window
-- opens on the grid, except back from Focus mode (it hides the window with
-- _focusHide set and shows it again)
function EX.OnWindowShow()
    -- The strip has no screen position until laid out (as MainWindow's icons)
    C_Timer.After(0, function()
        if K.LayoutToolRow then K.LayoutToolRow() end
        if _path and _path:IsShown() then _path.Update(true) end
        if BNB.ApplyToolbarIcons then BNB.ApplyToolbarIcons() end
    end)
    if not EX.IsActive() then UpdateHeader(); return end
    if not _keepNote then _mode = "grid" end
    _keepNote = nil
    EX.Apply()
end

-- MainWindow's OnHide (a real close and Focus mode's hide)
function EX.OnWindowHide(f)
    _keepNote = f._focusHide and _mode == "note" or nil
    if _boxState then FinishBox() end
    if _drag then EndDrag(false) end
end

function EX.AddLeftFrames(list)
    if _viewBtn then list[#list + 1] = _viewBtn end
    if _backBtn then list[#list + 1] = _backBtn end
    if _path then list[#list + 1] = _path end
    local s = K.SearchButton and K.SearchButton()
    if s then list[#list + 1] = s end
end

-- ── Following the notes ─────────────────────────────────────────────────────
-- The grid redraws after every note list redraw (sort, tab, search, create,
-- delete, folders, system folders, skin) and on any note change (title,
-- icon, pin), one redraw per frame
BNB.RegisterMessage("Explorer", "NoteListRefreshed", Queue)
BNB.RegisterMessage("Explorer", "NoteChanged", function(_, id)
    Queue()
    if _path and _mode == "note" and id == BNB._currentNoteID and EX.IsActive() then _path.Update(true) end
end)

-- A note selected anywhere (a double-click, New note, the Oracle, a toast)
-- opens it; nothing selected (the open note deleted) goes back to the grid
BNB.RegisterMessage("Explorer", "NoteSelected", function(_, id)
    if not EX.IsActive() then return end
    local want = id and "note" or "grid"
    if want ~= _mode then
        _mode = want
        EX.Apply()
    else
        UpdateHeader()   -- another note: the path follows
    end
end)

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
-- Saved: BigNoteBoxDB.explorerView (the view is on), explorerTile (the view:
-- "small" / "medium" / "large" tiles or "list"), explorerPinnedClosed / explorerNotesClosed
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
local TILE_ICON  = { small = 40, medium = 56, large = 72, list = 20, details = 16, flat = 16 }
-- List (Dukul, 2026-10-21): a small icon and the title on one line, in rows of
-- columns as wide as fit (never narrower than LIST_MIN_W), markers at the end
local LIST_MIN_W = 190
local LIST_H     = 26
local LIST_GAP   = 2     -- between list rows
-- The View menu's choices; each has its own picture (Assets/Explorer/ex-view-<key>)
local VIEWS = { { "small", "EXPLORER_TILE_SMALL" }, { "medium", "EXPLORER_TILE_MEDIUM" },
                { "large", "EXPLORER_TILE_LARGE" }, { "list", "EXPLORER_VIEW_LIST" },
                { "details", "EXPLORER_VIEW_DETAILS" }, { "flat", "EXPLORER_VIEW_FLAT" } }
-- Flat (Dukul, 2026-10-21): the Details rows, every note in one run, no
-- folder tiles to open (the Folder column says where each one lives)
-- Details (Dukul, 2026-10-21): one row per note with columns, as Windows
-- Explorer's. Fixed widths (Name takes the rest, never under NAME_MIN);
-- columns drop off from the right when the window is narrow. sort = the
-- note sort a header click picks (a second click flips the order).
local DETAILS_H  = 22
local COLHDR_H   = 20
local NAME_MIN   = 180
local COL_GAP    = 8
local COLUMNS = {
    { key = "name",     title = "EXPLORER_COL_NAME",     sort = "alpha" },
    { key = "modified", title = "EXPLORER_COL_MODIFIED", sort = "edited",   w = 120 },
    { key = "created",  title = "EXPLORER_COL_CREATED",  sort = "creation", w = 120 },
    { key = "size",     title = "EXPLORER_COL_SIZE",     sort = "size",   w = 64, right = true },
    { key = "type",     title = "EXPLORER_COL_TYPE",     sort = "type",   w = 90 },
    { key = "folder",   title = "EXPLORER_COL_FOLDER",   sort = "folder", w = 100 },
    { key = "tags",     title = "EXPLORER_COL_TAGS",     w = 130 },
}
local TILE_EXTRA = 36    -- tile width = icon + this: room for the name
local LABEL_H    = 26    -- two lines of the name under the icon
local PAD        = 10    -- the grid's inner margin
local GAP        = 6     -- between tiles
local HDR_H      = 22    -- section header row
local HDR_ICON   = 20
local HDR_RULE_A = 0.35  -- the note list's header rule alpha (ALL-328)
local HDR_ARROW  = 12    -- Pinned / Notes: the open / closed arrow
local VIEW_BTN   = 18    -- the switch, as the list's tree buttons
local BACK_BTN   = 22
local SCROLL_W   = 22    -- room for the scroll bar (it draws outside its frame)
local STATUS_H      = BNB.STATUS_H        -- the status bar under the grid (Dukul, 2026-10-21; BNB.CreateStatusBar)
local STATUS_GRIP_W = BNB.STATUS_GRIP_W   -- the window's resize grip in the bottom right corner
local BOX_START  = 4     -- px the pointer moves before the picking box shows
                         -- or a pressed tile is carried
local GHOST      = 36    -- the carried tile's picture

local REFRESH_KEY = "explorerRefresh"

local _main, _sortDD, _dirDD, _selBtn, _viewBtn, _viewTx, _backBtn
local _lead, _sortAnchor   -- the switch's place; whether the sort dropdown hangs off the switch
local _path               -- "Notes > Folder > Note" right of the back arrow in a note
local PATH_TITLE_MAX = 320
local _pane, _sf, _child, _emptyLbl
local _status, _statusFs           -- the status bar under the grid
local _sbDetails, _sbTiles         -- its two view buttons (Windows 11)
local _colHdr, _colLayout          -- Details: the column header row, the columns that fit
local _sfDetails                   -- the scroll frame's top is set for Details
local LayoutColumns, ShapeDetailsTile, SyncDetailsHeader   -- Details, defined with the tile shapes
local _count = { notes = 0, folders = 0 }   -- what the last draw listed
local _crumbHdr           -- the open folder's header (its "Notes" part is a drop target)
local _tiles, _hdrs = {}, {}
local _mode   = "grid"    -- "grid" | "note", only while the view is on
local _folder             -- nil = top level, a folder id, or "sys:<key>"
local _rbAway             -- the grid hid the Reference Box; a note brings it back
local _rbPickID           -- the pick the Reference Box last followed on the grid (false = none)
local _applying           -- EX.Apply is running: it syncs the Reference Box itself
local _keepNote           -- Focus mode hid the window while a note was open

-- Picks: _pick[key] = true; key = a note id or "folder:<id>" (Dukul,
-- 2026-10-21: folders are picked like notes, double-click opens); _kind[key]
-- = "note" / "folder"; _order = the pickable keys as drawn; _shown = their
-- tiles; _anchor = the last plain / Ctrl click (Shift+click range). A system
-- tile (Patch notes / Help folder or note) is only lit, alone: _sysPick
local _pick, _order, _orderIdx, _shown, _kind = {}, {}, {}, {}, {}
local _anchor, _sysPick
local _box, _boxState     -- the picking box and its drag
local _drag, _ghost, _dropLine, _dropAt   -- carrying tiles
-- Clicks are ignored until then: just after a drop, and just after a folder
-- opened (a Windows-style double-click on a folder must not open the note
-- that is now under the pointer)
local QUIET = 0.35
local function Quiet() return _dropAt and GetTime() - _dropAt < QUIET end

-- ── State ───────────────────────────────────────────────────────────────────
-- The Explorer module (Dukul, 2026-10-21): off = no switch button, the main
-- window is always the note list; the tile view is kept
function BNB.ExplorerEnabled()
    return not BigNoteBoxDB or BigNoteBoxDB.explorerEnabled ~= false
end

function EX.IsActive()
    return BNB._notesAvailable and BigNoteBoxDB and BigNoteBoxDB.explorerView == true
        and BNB.ExplorerEnabled() and _main ~= nil or false
end

function EX.Mode()
    if not EX.IsActive() then return nil end
    return _mode
end

local function ViewKey()
    local db = BigNoteBoxDB
    local k = db and db.explorerTile or DEFAULT_ICON_SIZE
    return TILE_ICON[k] and k or DEFAULT_ICON_SIZE
end
local function TileIcon() return TILE_ICON[ViewKey()] end
local function IsList() return ViewKey() == "list" end
local function IsDetails() return ViewKey() == "details" end
local function IsFlat() return ViewKey() == "flat" end
local TILE_VIEW = { small = true, medium = true, large = true }   -- the tile sizes
-- The View button's picture: the view in use
function K.ViewIcon() return "ex-view-" .. ViewKey() end

local function SysKey(folder)
    return type(folder) == "string" and folder:match("^sys:(.+)$") or nil
end

local function FoldersOn() return BNB.FoldersEnabled() and BNB.Folders or nil end

local function Filtering() return BNB.IsListFiltering and BNB.IsListFiltering() or false end

-- Favorites first (View menu, Dukul 2026-10-22, off by default): the
-- favourite notes of a list moved to its top, each part keeping the sort.
-- No section of their own; used at the top level and inside a folder
local function FavFirst(list)
    if not (BigNoteBoxDB and BigNoteBoxDB.explorerFavFirst == true) then return list end
    local fav, rest = {}, {}
    for _, n in ipairs(list) do
        if n.favorited then fav[#fav + 1] = n else rest[#rest + 1] = n end
    end
    for _, n in ipairs(rest) do fav[#fav + 1] = n end
    return fav
end

-- ── Header controls (toolbar strip) ─────────────────────────────────────────
-- The first button is always the switch (list view: then sort, order,
-- Select; the explorer grid: then the tool buttons). Inside a folder or a
-- note the back arrow takes the switch's place (Dukul, 2026-10-20)
local function UpdateHeader()
    local on = EX.IsActive()
    if _viewTx then _viewTx:SetTexture(on and LIST_TEX or VIEW_TEX) end
    local back = on and (_mode == "note" or _folder ~= nil)
    local modOn = BNB.ExplorerEnabled()
    if _backBtn then _backBtn:SetShown(back) end
    if _viewBtn then _viewBtn:SetShown(modOn and not back) end
    -- Module off: no switch, the sort dropdown takes its place
    if _sortDD and _lead and _sortAnchor ~= modOn then
        _sortAnchor = modOn
        _sortDD:ClearAllPoints()
        if modOn then _sortDD:SetPoint("LEFT", _viewBtn, "RIGHT", 6, 0)
        else _sortDD:SetPoint("LEFT", _lead, "LEFT", 0, 0) end
    end
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

-- -- Status bar ----------------------------------------------------------------
-- As Windows Explorer's (Dukul, 2026-10-21): "4 notes   3 folders   3 notes
-- selected (1 rich note, 2 normal notes)   4.2 KB". The selection part only
-- while notes are picked; rich / normal only while Rich Notes is on.
local function Plural(n, one, many)
    if n == 1 then return L[one] end
    return string.format(L[many], n)
end

-- Same units as Settings > Backup's data summary
local function SizeText(bytes)
    if bytes >= 1024 * 1024 then return string.format(L["CFG_SIZE_MB_FMT"], bytes / (1024 * 1024)) end
    if bytes >= 1024 then return string.format(L["CFG_SIZE_KB_FMT"], bytes / 1024) end
    return string.format(L["CFG_SIZE_B_FMT"], bytes)
end

local STATUS_SEP = "     "

-- The status bar's view buttons (Windows 11, Dukul 2026-10-21): Details, and
-- tiles at the last tile size; the one in use full, the other dimmed (both
-- dimmed in List)
local function LastTile()
    local k = BigNoteBoxDB and BigNoteBoxDB.explorerLastTile
    return (k and TILE_VIEW[k]) and k or DEFAULT_ICON_SIZE
end
local function PaintViewButtons()
    if not _sbDetails then return end
    _sbTiles._tx:SetTexture(ART .. "ex-view-" .. LastTile())
    _sbDetails:SetAlpha(IsDetails() and 1 or 0.45)
    _sbTiles:SetAlpha(TILE_VIEW[ViewKey()] and 1 or 0.45)
end

local function UpdateStatus()
    if not _statusFs then return end
    PaintViewButtons()
    local parts = { Plural(_count.notes, "EXPLORER_SB_NOTE_1", "EXPLORER_SB_NOTES_FMT") }
    if _count.folders > 0 then
        parts[#parts + 1] = Plural(_count.folders, "EXPLORER_SB_FOLDER_1", "EXPLORER_SB_FOLDERS_FMT")
    end
    local n, nf, rich, bytes = 0, 0, 0, 0
    local AM = BNB.AdvancedMode
    for _, key in ipairs(_order) do
        if _pick[key] then
            if _kind[key] == "folder" then
                nf = nf + 1
            else
                local note = BNB.GetNote(key)
                if note then
                    n = n + 1
                    if AM and AM.IsRich and AM.IsRich(note) then rich = rich + 1 end
                    bytes = bytes + #(note.title or "") + #(note.body or "")
                end
            end
        end
    end
    if n > 0 or nf > 0 then
        local sel
        if nf == 0 then
            sel = Plural(n, "EXPLORER_SB_SEL_1", "EXPLORER_SB_SEL_FMT")
        elseif n == 0 then
            sel = Plural(nf, "EXPLORER_SB_SELF_1", "EXPLORER_SB_SELF_FMT")
        else
            sel = string.format(L["EXPLORER_SB_SEL_BOTH_FMT"],
                Plural(n, "EXPLORER_SB_NOTE_1", "EXPLORER_SB_NOTES_FMT"),
                Plural(nf, "EXPLORER_SB_FOLDER_1", "EXPLORER_SB_FOLDERS_FMT"))
        end
        if n > 0 and BNB.RichEnabled and BNB.RichEnabled() then
            -- Only the kinds picked: no "0 rich notes" (Dukul, 2026-10-22)
            local kinds = {}
            if rich > 0 then
                kinds[#kinds + 1] = Plural(rich, "EXPLORER_SB_RICH_1", "EXPLORER_SB_RICH_FMT")
            end
            if n - rich > 0 then
                kinds[#kinds + 1] = Plural(n - rich, "EXPLORER_SB_NORMAL_1", "EXPLORER_SB_NORMAL_FMT")
            end
            sel = sel .. " (" .. table.concat(kinds, ", ") .. ")"
        end
        parts[#parts + 1] = sel
        if n > 0 then parts[#parts + 1] = SizeText(bytes) end   -- the notes' size only
    end
    _statusFs:SetText(table.concat(parts, STATUS_SEP))
end

-- ALL-616 (Dukul, 2026-10-29): with the Reference Box's auto-open on, the
-- grid's one picked note gets the box as an opened note does in the list:
-- open on a note with something for it, closed on one with nothing, on a
-- folder or on several picks. Only on a change, so a box closed by hand
-- stays closed until the pick moves.
local function SyncRefBoxPick()
    if _applying or not (EX.IsActive() and _mode == "grid") then return end
    if not (BigNoteBoxDB.refboxAutoOpen and BNB.SyncReferenceBox) then return end
    local notes = K.Picked()
    local id = (#notes == 1 and not _sysPick and #K.PickedFolders() == 0) and notes[1] or false
    if id == _rbPickID then return end
    _rbPickID = id
    _rbAway = true   -- leaving the grid puts the open note's box back
    if id then
        BNB.SyncReferenceBox(id)
    elseif BNB.IsReferenceBoxShown and BNB.IsReferenceBoxShown() then
        BNB.CloseReferenceBox()
    end
end

local function PaintPicks()
    for _, t in ipairs(_tiles) do
        if t:IsShown() then
            t._sel:SetShown((t._pickKey ~= nil and _pick[t._pickKey] == true)
                or (t._sysKey ~= nil and t._sysKey == _sysPick))
        end
    end
    UpdateStatus()
    if K.OnPicks then K.OnPicks() end
    if BNB.RefreshFocusButton then BNB.RefreshFocusButton() end   -- ALL-569: a picked note
    SyncRefBoxPick()
end

local function ClearPicks()
    wipe(_pick); _anchor, _sysPick = nil, nil
end

-- The picked notes in display order
-- The picked notes (never folders), in display order
function K.Picked()
    local ids = {}
    for _, key in ipairs(_order) do
        if _pick[key] and _kind[key] == "note" then ids[#ids + 1] = key end
    end
    return ids
end

-- The picked folders' ids, in display order
function K.PickedFolders()
    local ids = {}
    for _, key in ipairs(_order) do
        if _pick[key] and _kind[key] == "folder" then ids[#ids + 1] = key:sub(8) end
    end
    return ids
end

-- Share / Export: the picked notes, then the notes in the picked folders
-- (list order), each once (Dukul, 2026-10-21: like copying a folder)
function K.PickedNotesDeep()
    local ids, seen = K.Picked(), {}
    for _, id in ipairs(ids) do seen[id] = true end
    local fids = K.PickedFolders()
    local FD = FoldersOn()
    if #fids == 0 or not FD then return ids end
    local want = {}
    for _, fid in ipairs(fids) do want[fid] = true end
    for _, n in ipairs(BNB.GetOrderedNotes("", nil, true)) do
        if not seen[n.id] and want[FD.Of(n) or ""] then
            seen[n.id] = true
            ids[#ids + 1] = n.id
        end
    end
    return ids
end

function K.CanPick() return #_order > 0 end

-- Every note shown is picked
function K.AllPicked()
    if #_order == 0 then return false end
    for _, id in ipairs(_order) do
        if not _pick[id] then return false end
    end
    return true
end

-- Select all; with everything picked already it clears the picks (Dukul, 2026-10-21)
function K.SelectAll()
    if K.AllPicked() then ClearPicks()
    else for _, id in ipairs(_order) do _pick[id] = true end end
    PaintPicks()
end
function K.SelectAllText()
    return L[K.AllPicked() and "EXPLORER_DESELECT_ALL" or "MW_SELECT_ALL_BTN"]
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
-- A new folder with the picked notes moved into it (the New menu, Dukul
-- 2026-10-22); the ids are taken when the name popup opens
function K.NewFolderWithPicks()
    local ids = K.Picked()
    if not ids[1] then return end
    BNB.PromptFolderName({ mode = "new", after = function(id)
        if id and BNB.Folders then BNB.Folders.Move(ids, id) end
    end })
end

-- The five sorts, a line, then Descending / Ascending (greyed in Custom)
-- Each sort's picture (Dukul's art, 2026-10-21): Assets/Explorer/ex-sort-<name>
local SORT_ICON = { custom = "custom", creation = "created", edited = "edited",
                    alpha = "az", location = "location", size = "size", type = "type",
                    folder = "folder" }
local function SortKey() return BigNoteBoxDB.sortBy or BNB.DEFAULTS.sortBy end
-- The Sort button's picture: the sort in use
function K.SortIcon() return "ex-sort-" .. (SORT_ICON[SortKey()] or "custom") end

function K.FillSortMenu(menu)
    if not (BNB.SetNoteSort and BNB.NOTE_SORT_MODES) then return end
    for _, m in ipairs(BNB.NOTE_SORT_MODES) do
        local key = m.key
        menu:CreateRadio(m.label, function() return SortKey() == key end,
            function() BNB.SetNoteSort(key, nil) end,
            { iconGold = true, iconTex = ART .. "ex-sort-" .. (SORT_ICON[key] or "custom") })
    end
    menu:CreateDivider()
    local custom = SortKey() == "custom"
    menu:CreateRadio(L["DIR_MODE_DESC"], function() return not BigNoteBoxDB.sortAsc end,
        function() BNB.SetNoteSort(nil, false) end,
        { disabled = custom, iconGold = true, iconTex = ART .. "ex-sort-descending" })
    menu:CreateRadio(L["DIR_MODE_ASC"], function() return BigNoteBoxDB.sortAsc == true end,
        function() BNB.SetNoteSort(nil, true) end,
        { disabled = custom, iconGold = true, iconTex = ART .. "ex-sort-ascending" })
    if BNB.AddSortDefaultItems then BNB.AddSortDefaultItems(menu) end   -- ALL-535
end

-- View radios, each with its picture: the toolbar's View menu and the
-- empty-space menu's View sub-menu. No Switch to list view here: the switch
-- button at the far left does it (Dukul, 2026-10-21)
function K.FillViewMenu(menu)
    for _, s in ipairs(VIEWS) do
        local k = s[1]
        menu:CreateRadio(L[s[2]],
            function() return ViewKey() == k end,
            function()
                BigNoteBoxDB.explorerTile = k
                if TILE_VIEW[k] then BigNoteBoxDB.explorerLastTile = k end
                Refresh()
            end,
            { iconGold = true, iconTex = ART .. "ex-view-" .. k })
    end
    -- No Pinned / Notes sections (Dukul, 2026-10-22), under its own divider
    menu:CreateDivider()
    menu:CreateCheckbox(L["EXPLORER_PINNED_FIRST"],
        function() return BigNoteBoxDB.explorerPinnedFirst == true end,
        function()
            BigNoteBoxDB.explorerPinnedFirst = BigNoteBoxDB.explorerPinnedFirst ~= true
            Refresh()
        end,
        { keepOpen = true, iconGold = true, iconTex = ART .. "ex-pin",   -- the toolbar's Pin icon
          tip = L["EXPLORER_PINNED_FIRST"], tipSub = L["EXPLORER_PINNED_FIRST_TIP"] })
    menu:CreateCheckbox(L["EXPLORER_FAV_FIRST"],
        function() return BigNoteBoxDB.explorerFavFirst == true end,
        function()
            BigNoteBoxDB.explorerFavFirst = BigNoteBoxDB.explorerFavFirst ~= true
            Refresh()
        end,
        { keepOpen = true, iconGold = true, iconTex = ART .. "ex-favorite",   -- the toolbar's Favorite icon
          tip = L["EXPLORER_FAV_FIRST"], tipSub = L["EXPLORER_FAV_FIRST_TIP"] })
end

local function ShowEmptyMenu(owner)
    local FD = FoldersOn()
    BNB.ContextMenu.Open(owner, function(root)
        -- The toolbar's pictures on each row (Dukul, 2026-10-22)
        root:CreateButton(L["EXPLORER_TB_NEW_NOTE"], K.NewNoteHere,
            { iconTex = ART .. "ex-new-note", iconGold = true })
        if FD then
            root:CreateButton(L["FOLDER_CM_NEW_FOLDER"], K.NewFolder,
                { iconTex = ART .. "ex-new-folder", iconGold = true })
        end
        root:CreateDivider()
        root:CreateButton(K.SelectAllText(), K.SelectAll,
            { disabled = not K.CanPick(), iconTex = ART .. "ex-select-all", iconGold = true })
        root:CreateDivider()
        -- Sort by: the toolbar strip's two dropdowns in one sub-menu (Dukul,
        -- 2026-10-20); the order means nothing in Custom, so it is greyed there
        K.FillSortMenu(root:CreateButton(L["EXPLORER_CM_SORT_BY"], nil,
            { iconTex = ART .. "ex-sort", iconGold = true }))
        K.FillViewMenu(root:CreateButton(L["EXPLORER_TB_VIEW"], nil,
            { iconTex = ART .. "ex-view", iconGold = true }))
        root:CreateDivider()
        root:CreateButton(L["FOLDER_TREE_TIP_OFF"], function() EX.SetActive(false) end,
            { iconTex = ART .. "ex-list-mode", iconGold = true })
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
        _sysPick = nil
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
        local key = t._pickKey
        local want = hit or (st.add and st.base[key]) or nil
        if (_pick[key] or nil) ~= want then
            _pick[key] = want
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
        if t._noteID and t._section ~= "pinned" and not d.carried[t._noteID] then
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
    -- A size change while hidden (a note open, the window closed) skipped its
    -- redraw: draw again the frame after it shows, with the size it has then
    pane:HookScript("OnShow", Queue)

    local sf = BNB.CreateScrollFrame(nil, pane)
    sf:SetPoint("TOPLEFT", pane, "TOPLEFT", PAD, -PAD)
    sf:SetPoint("BOTTOMRIGHT", pane, "BOTTOMRIGHT", -SCROLL_W, STATUS_H + 4)
    _sf = sf

    -- The status bar: a thin rule over it (the headers' rule); skin mode adds
    -- a darker band like the toolbar strip's. Shared with the note editor
    -- since 2026-10-25 (BNB.CreateStatusBar, UI/Widgets.lua)
    local st = BNB.CreateStatusBar(pane, PAD)
    -- Two view buttons at the right end, as Windows 11's status bar
    local function ViewBtn(onClick, tipKey)
        local b = CreateFrame("Button", nil, st)
        b:SetSize(16, 16)
        local tx = b:CreateTexture(nil, "ARTWORK")
        tx:SetAllPoints()
        BNB.TintUIIcon(tx)
        BNB.AddUIIconHover(b, tx)
        b._tx = tx
        b:SetScript("OnClick", onClick)
        b:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:AddLine(L[tipKey()], 1, 1, 1)
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        return b
    end
    local function SetView(k)
        BigNoteBoxDB.explorerTile = k
        Refresh()
    end
    _sbTiles = ViewBtn(function() SetView(LastTile()) end, function()
        for _, v in ipairs(VIEWS) do if v[1] == LastTile() then return v[2] end end
        return "EXPLORER_TILE_MEDIUM"
    end)
    _sbTiles:SetPoint("RIGHT", st, "RIGHT", -(PAD + STATUS_GRIP_W), 0)   -- clear of the resize grip
    _sbDetails = ViewBtn(function() SetView("details") end, function() return "EXPLORER_VIEW_DETAILS" end)
    _sbDetails._tx:SetTexture(ART .. "ex-view-details")
    _sbDetails:SetPoint("RIGHT", _sbTiles, "LEFT", -6, 0)

    local sfs = st:CreateFontString(nil, "OVERLAY", "BNBFontNormalSmall")
    sfs:SetPoint("LEFT", st, "LEFT", PAD, 0)
    sfs:SetPoint("RIGHT", _sbDetails, "LEFT", -8, 0)
    sfs:SetJustifyH("LEFT"); sfs:SetWordWrap(false)
    sfs:SetTextColor(BNB.TextWhite(0.75))
    _status, _statusFs = st, sfs
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
    -- Dukul's chevrons (2026-10-21), the toolbar menus' arrow; white on hover
    hdr._arrow:SetTexture(ART .. (hdr._closed and "ex-chevron-up" or "ex-chevron-down"))
    if hover then hdr._arrow:SetVertexColor(1, 1, 1) else BNB.TintUIIcon(hdr._arrow) end
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
        BNB.Folders.PaintArt(hdr._pic, true, art.hasNotes, r, g, b, art.sys)
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
        PaintArrow(hdr, hdr:IsMouseOver())
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
    _sysPick = nil
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

-- A system tile is lit alone: nothing else stays picked
local function SysClick(key)
    wipe(_pick); _anchor = nil
    _sysPick = key
    PaintPicks()
end

-- Right-click on a pick when other things are picked too: the notes' menu
-- (Dukul, 2026-10-21: a mixed pick gets the menu for its notes)
local function PickMenu(self, key)
    if not _pick[key] then return false end
    local notes = K.Picked()
    if #notes > 1 then BNB.ShowMultiNoteContextMenu(self, notes); return true end
    if #notes == 1 and #K.PickedFolders() > 0 then BNB.ShowNoteContextMenu(self, notes[1]); return true end
    return false
end

-- One click picks (Ctrl / Shift as for files), a double-click opens: notes,
-- folders and the system tiles alike (Dukul, 2026-10-21)
local function TileClick(self, button)
    if self._folderKey then
        if Quiet() then return end
        local sys = SysKey(self._folderKey)
        if button == "RightButton" then
            if sys then
                if BNB.ShowSystemFolderMenu then BNB.ShowSystemFolderMenu(self, sys) end
            elseif not PickMenu(self, self._pickKey) then
                if not _pick[self._pickKey] then
                    wipe(_pick); _pick[self._pickKey] = true; _anchor = self._pickKey; _sysPick = nil
                    PaintPicks()
                end
                if BNB.ShowFolderMenu then BNB.ShowFolderMenu(self, self._folderKey) end
            end
            return
        end
        if sys then SysClick(self._sysKey) else PickClick(self._pickKey) end
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
        if not PickMenu(self, id) then
            wipe(_pick); _pick[id] = true; _anchor = id; _sysPick = nil
            PaintPicks()
            BNB.ShowNoteContextMenu(self, id)
        end
        return
    end
    if Quiet() then return end   -- the end of a carry, a folder just opened
    if self._sys then SysClick(self._sysKey); return end
    PickClick(id)
end

local function TileDoubleClick(self, button)
    if button ~= "LeftButton" or Quiet() then return end
    if self._folderKey then K.OpenFolder(self._folderKey); return end
    if self._noteID then OpenNote(self._noteID) end
end

-- List / Details / Flat rows run the width of the window, so a tooltip right
-- of the row lands outside it: under the row at the pointer instead (ALL-533,
-- Dukul 2026-10-21), moved left so it ends inside the row
local function RowTipX(self)
    local left = self:GetLeft()
    if not left then return 0 end
    return GetCursorPosition() / self:GetEffectiveScale() - left
end
local function PlaceRowTip(self)
    if TILE_VIEW[ViewKey()] then return nil end
    return function(tip)
        tip:SetOwner(self, "ANCHOR_NONE")
        tip:SetPoint("TOPLEFT", self, "BOTTOMLEFT", RowTipX(self), -2)
    end
end
-- After Show, when the tooltip's width is known
local function FitRowTip(self)
    if not GameTooltip:IsShown() or GameTooltip:GetOwner() ~= self then return end
    local x = RowTipX(self)
    local over = x + GameTooltip:GetWidth() - self:GetWidth()
    if over > 0 then
        GameTooltip:ClearAllPoints()
        GameTooltip:SetPoint("TOPLEFT", self, "BOTTOMLEFT", math.max(0, x - over), -2)
    end
end

local function TileEnter(self)
    if _drag or _boxState then return end
    local place = PlaceRowTip(self)
    if self._noteID then
        BNB.ShowNoteListTooltip(self, self._noteID, true, place)   -- title on top: names wrap
        if place then FitRowTip(self) end
        return
    end
    if place then place(GameTooltip) else GameTooltip:SetOwner(self, "ANCHOR_RIGHT") end
    GameTooltip:AddLine((self._folderName or "") .. " (" .. (self._count or 0) .. ")")
    GameTooltip:AddLine(L["EXPLORER_FOLDER_TIP"], 0.85, 0.85, 0.85, true)
    GameTooltip:Show()
    if place then FitRowTip(self) end
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
-- MARK_OUT = how far the markers sit out past the icon's edge (Dukul,
-- 2026-10-22: a little further out and smaller, MARK_SCALE of the icon)
local MARK_OUT, MARK_SCALE = 5, 0.30
local MARKERS = {
    { "_mFav",  "favorite",  "TOPRIGHT",     MARK_OUT,  MARK_OUT },
    { "_mAlarm", "alarm",    "BOTTOMRIGHT",  MARK_OUT, -MARK_OUT },
    { "_mSitu", "situation", "TOPLEFT",     -MARK_OUT,  MARK_OUT },
    { "_mLoc",  "location",  "LEFT",        -MARK_OUT,  0 },
    -- Pinned, where the Pinned section does not already say so: top middle,
    -- between the situation and favourite markers (Dukul, 2026-10-22)
    { "_mPin",  "pin",       "TOP",          0,         MARK_OUT },
}

-- Hover and pick art. Normal look: the collapsed note list's square pictures
-- (icon + 12 px on a side, centred on the icon, drawn over its border, BNB
-- green), not the wide row art (Dukul, 2026-10-20). Skin mode: the list's
-- flat fills over the whole tile. sub = the OVERLAY sub-level, as the list
local SQ_ART  = "Interface\\AddOns\\BigNoteBox\\Assets\\UI\\ui-note-list-collapsed-"
local SQ_GROW = 12
local FOLDER_GLOW = "Interface\\AddOns\\BigNoteBox\\Assets\\UI\\ui-folder-glow"
local FOLDER_GLOW_TOP = "Interface\\AddOns\\BigNoteBox\\Assets\\UI\\ui-folder-glow-top"
local HOVER_SOFT = "Interface\\AddOns\\BigNoteBox\\Assets\\UI\\ui-hover-soft"
local function TileArt(t, kind, sub, fill)
    if BigNoteBoxDB and BigNoteBoxDB.skinMode then
        -- Skin mode's hover: the toolbar buttons' glow (ui-hover-64, skin
        -- accent) behind the whole tile, icon and name, not a flat block
        -- (Dukul, 2026-10-22, ALL-550). List / Details rows keep the fill
        if kind == "hover" then
            -- ui-hover-soft = ui-hover-64 with its edges faded to clear: the
            -- 64 px art keeps a little alpha at its edge, which showed as a
            -- cut on the sides of a big tile (Dukul, 2026-10-23)
            local tex = t:CreateTexture(nil, "BACKGROUND", nil, 3)
            tex:SetAllPoints()
            tex:SetTexture(HOVER_SOFT)
            BNB.TintUIIcon(tex)
            tex._glow = true
            tex:Hide()
            return tex
        end
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
    -- Normal look only: a glow behind the folder in its colour, so it stands
    -- out beyond the coloured name (Dukul, 2026-10-22). White art, tinted;
    -- same size as the folder art, so it follows it in every view
    t._folderGlow = t:CreateTexture(nil, "ARTWORK", nil, -1)
    t._folderGlow:SetTexture(FOLDER_GLOW)
    t._folderGlow:SetAllPoints(t._folderTex)
    t._folderGlow:Hide()
    -- Normal look only: the folder's small mark drawn over the picture in its
    -- colour (Dukul, 2026-10-22, a test)
    t._folderTop = t:CreateTexture(nil, "ARTWORK", nil, 1)
    t._folderTop:SetTexture(FOLDER_GLOW_TOP)
    t._folderTop:SetAllPoints(t._folderTex)
    t._folderTop:Hide()
    local selFill, hoverFill = { 0.40, 0.85, 0.40, 0.18 }, { 1, 1, 1, 0.06 }
    t._selT   = TileArt(t, "selection", 2, selFill)
    t._hoverT = TileArt(t, "hover", 4, hoverFill)
    -- List view: the note list's row art over the whole row (skin mode's tile
    -- art already is)
    if t._selT._square then
        t._selL   = BNB.CreateListRowArt(t, "selection", selFill)
        t._hoverL = BNB.CreateListRowArt(t, "hover", hoverFill)
    else
        t._selL, t._hoverL = t._selT, BNB.CreateListRowArt(t, "hover", hoverFill)
    end
    t._sel, t._hover = t._selT, t._hoverT   -- the pair in use, set by ShapeTile
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
    BNB.TintAbIcon(lock)
    lock:SetPoint("BOTTOMLEFT", ov, "BOTTOMLEFT", -MARK_OUT, -MARK_OUT)
    lock:Hide()
    t._mLock = lock
    t:SetScript("OnClick", TileClick)
    t:SetScript("OnDoubleClick", TileDoubleClick)
    t:SetScript("OnEnter", TileEnter)
    t:SetScript("OnLeave", TileLeave)
    t:SetScript("OnMouseDown", TileMouseDown)
    t:SetScript("OnMouseUp", TileMouseUp)
    -- Hover art: hooked after the SetScripts above, which drop any hook made
    -- before them (the hover never showed, ALL-534)
    t:HookScript("OnEnter", function(self) self._hover:Show() end)
    t:HookScript("OnLeave", function(self) self._hover:Hide() end)
    t:HookScript("OnHide",  function(self) self._hover:Hide() end)
    _tiles[i] = t
    return t
end

-- The hover / pick pair for this view; the pick is shown again on a swap
local function UseArt(t, sel, hover)
    if t._sel == sel and t._hover == hover then return end   -- skin mode: same pick, other hover
    t._sel:Hide(); t._hover:Hide()
    t._sel, t._hover = sel, hover
    t._sel:SetShown((t._pickKey ~= nil and _pick[t._pickKey] == true)
        or (t._sysKey ~= nil and t._sysKey == _sysPick))
    if t:IsMouseOver() then t._hover:Show() end
end

-- List view: icon left, title after it, the shown markers in a row at the
-- right end (lock first from the right), the title stopping before them.
-- Called after the tile was filled, so the markers' shown state is known.
local LIST_MARKERS = { "_mLock", "_mPin", "_mFav", "_mAlarm", "_mSitu", "_mLoc" }
local function HideCells(t)
    if t._cells then for _, fs in pairs(t._cells) do fs:Hide() end end
    if t._langFlag then t._langFlag:Hide() end
end

-- Details / Flat: a small flag at the right end of the Name column for a note
-- with Korean, Chinese or Japanese text (Dukul, 2026-10-30: an indicator;
-- the editor's title row has the shield). Flags, not shields
local LANG_FLAG = { ko = "flag-ko", cn = "flag-cn", ja = "flag-ja", ua = "flag-ua", gr = "flag-gr" }
local FLAG_ART  = "Interface\\AddOns\\BigNoteBox\\Assets\\Flags\\"

-- h = the row height (List / Details); edge = room kept at the right for the
-- Details columns, so the markers end the Name column
local function ShapeListTile(t, size, w, h, edge)
    h, edge = h or LIST_H, edge or 0
    UseArt(t, t._selL, t._hoverL)
    t:SetSize(w, h)
    if edge == 0 then HideCells(t) end
    for _, tex in ipairs({ t._icon, t._folderTex }) do
        tex:SetSize(size, size)
        tex:ClearAllPoints()
        tex:SetPoint("LEFT", t, "LEFT", 4, 0)
    end
    local x = -4 - edge
    -- Normal mode's marker art is hard to read at 12 px (Dukul, 2026-10-21)
    local skin = BigNoteBoxDB and BigNoteBoxDB.skinMode
    local big = skin and 12 or math.min(16, h - 6)
    local code = edge > 0 and t._note and BNB.TextShield and BNB.TextShield(t._note.body)
    if code then
        if not t._langFlag then t._langFlag = t:CreateTexture(nil, "OVERLAY") end
        local fl = t._langFlag
        fl:SetTexture(FLAG_ART .. LANG_FLAG[code])
        fl:SetSize(big, big)
        fl:ClearAllPoints()
        fl:SetPoint("RIGHT", t, "RIGHT", x, 0)
        fl:Show()
        x = x - big - 2
    elseif t._langFlag then
        t._langFlag:Hide()
    end
    for _, key in ipairs(LIST_MARKERS) do
        local mk = t[key]
        local ms = key == "_mLock" and big - 2 or big
        mk:SetSize(ms, ms)
        mk:ClearAllPoints()
        if mk:IsShown() then
            mk:SetPoint("RIGHT", t, "RIGHT", x, 0)
            x = x - ms - 2
        end
    end
    local fs = t._label
    fs:ClearAllPoints()
    fs:SetPoint("LEFT", t._icon, "RIGHT", 6, 0)
    fs:SetPoint("RIGHT", t, "RIGHT", x - 2, 0)
    fs:SetHeight(h)
    fs:SetJustifyH("LEFT"); fs:SetJustifyV("MIDDLE")
    fs:SetWordWrap(false)
    if fs.SetMaxLines then fs:SetMaxLines(1) end
end

local function ShapeTile(t, size)
    UseArt(t, t._selT, t._hoverT)
    HideCells(t)
    local w = size + TILE_EXTRA
    t:SetSize(w, 6 + size + 4 + LABEL_H + 4)
    for _, tex in ipairs({ t._icon, t._folderTex }) do
        tex:SetSize(size, size)
        tex:ClearAllPoints()
        tex:SetPoint("TOP", t, "TOP", 0, -6)
    end
    local fs = t._label
    fs:ClearAllPoints()
    fs:SetPoint("TOP", t._icon, "BOTTOM", 0, -4)
    fs:SetWidth(w - 6)
    fs:SetHeight(LABEL_H)
    fs:SetJustifyH("CENTER"); fs:SetJustifyV("TOP")
    fs:SetWordWrap(true)
    if fs.SetMaxLines then fs:SetMaxLines(2) end
    for _, tex in ipairs({ t._sel, t._hover }) do
        if tex._square then tex:SetSize(size + SQ_GROW, size + SQ_GROW) end
    end
    local ms = math.max(12, math.floor(size * MARK_SCALE))
    for _, m in ipairs(MARKERS) do
        local mk = t[m[1]]
        mk:SetSize(ms, ms)
        mk:ClearAllPoints()   -- a list row moved it to the row's end
        mk:SetPoint(m[3], t._ov, m[3], m[4], m[5])
    end
    t._mLock:SetSize(math.floor(ms * 0.8), math.floor(ms * 0.8))
    t._mLock:ClearAllPoints()
    t._mLock:SetPoint("BOTTOMLEFT", t._ov, "BOTTOMLEFT", -MARK_OUT, -MARK_OUT)
end

-- -- Details view ----------------------------------------------------------------
-- The columns that fit in width: Name first (the rest of the room), then
-- each column while Name keeps NAME_MIN. _colLayout = { { col, x, w }, ... }
LayoutColumns = function(width)
    local used, keep = 0, {}
    for i = 2, #COLUMNS do
        local c = COLUMNS[i]
        if width - (used + c.w + COL_GAP) < NAME_MIN then break end
        used = used + c.w + COL_GAP
        keep[#keep + 1] = c
    end
    local layout = { { col = COLUMNS[1], x = 0, w = width - used } }
    local x = width - used
    for _, c in ipairs(keep) do
        layout[#layout + 1] = { col = c, x = x + COL_GAP, w = c.w }
        x = x + COL_GAP + c.w
    end
    _colLayout = layout
    if _colHdr then _colHdr.Layout(layout) end
end

local function FolderName(note)
    local FD = FoldersOn()
    local fid = FD and FD.Of(note)
    local rec = fid and FD.Get(fid)
    return rec and rec.name or ""
end

-- One column's text for a row (a note tile, or a folder tile: note = nil)
local function CellText(t, key)
    local note = t._note
    if key == "type" then
        if not note then return L["EXPLORER_TYPE_FOLDER"] end
        local AM = BNB.AdvancedMode
        return L[(AM and AM.IsRich and AM.IsRich(note)) and "EXPLORER_TYPE_RICH" or "EXPLORER_TYPE_NORMAL"]
    end
    if not note then return "" end
    if key == "modified" then return BNB.FmtTime and BNB.FmtTime(note.updated) or "" end
    if key == "created"  then return BNB.FmtTime and BNB.FmtTime(note.created) or "" end
    if key == "size"     then return SizeText(#(note.title or "") + #(note.body or "")) end
    if key == "folder"   then return FolderName(note) end
    if key == "tags" and type(note.tags) == "table" then return table.concat(note.tags, ", ") end
    return ""
end

ShapeDetailsTile = function(t, size, w)
    local layout = _colLayout or { { col = COLUMNS[1], x = 0, w = w } }
    ShapeListTile(t, size, w, DETAILS_H, w - layout[1].w)
    t._cells = t._cells or {}
    local shown = {}
    for i = 2, #layout do
        local c = layout[i]
        local key = c.col.key
        local fs = t._cells[key]
        if not fs then
            fs = t:CreateFontString(nil, "OVERLAY", "BNBFontHighlightSmall")
            fs:SetWordWrap(false)
            t._cells[key] = fs
        end
        fs:ClearAllPoints()
        fs:SetPoint("LEFT", t, "LEFT", c.x, 0)
        fs:SetWidth(c.w)
        fs:SetHeight(DETAILS_H)
        fs:SetJustifyH(c.col.right and "RIGHT" or "LEFT")
        fs:SetTextColor(BNB.TextWhite(0.7))
        fs:SetText(CellText(t, key))
        fs:Show()
        shown[key] = true
    end
    for key, fs in pairs(t._cells) do
        if not shown[key] then fs:Hide() end
    end
end

-- The header row over the grid: one button per column, the sort arrow on the
-- column whose sort is in use (Windows); a click sorts, again flips the order
local function BuildColumnHeader()
    local hdr = CreateFrame("Frame", nil, _pane)
    hdr:SetPoint("TOPLEFT", _pane, "TOPLEFT", PAD, -PAD)
    hdr:SetPoint("TOPRIGHT", _pane, "TOPRIGHT", -SCROLL_W, -PAD)
    hdr:SetHeight(COLHDR_H)
    hdr:Hide()
    local rule = hdr:CreateTexture(nil, "ARTWORK")
    if rule.SetSnapToPixelGrid then rule:SetSnapToPixelGrid(false); rule:SetTexelSnappingBias(0) end
    rule:SetPoint("BOTTOMLEFT", hdr, "BOTTOMLEFT", 0, 0)
    rule:SetPoint("BOTTOMRIGHT", hdr, "BOTTOMRIGHT", 0, 0)
    if PixelUtil and PixelUtil.SetHeight then PixelUtil.SetHeight(rule, 1, 1) else rule:SetHeight(1) end
    hdr._rule = rule
    local btns = {}
    for _, c in ipairs(COLUMNS) do
        local b = CreateFrame("Button", nil, hdr)
        b:SetHeight(COLHDR_H)
        local hl = b:CreateTexture(nil, "BACKGROUND")
        hl:SetAllPoints(); hl:Hide()
        if BigNoteBoxDB and BigNoteBoxDB.skinMode then   -- the toolbar glow (ALL-550)
            hl:SetTexture(BNB.UI_HOVER_TEX); BNB.TintUIIcon(hl)
        else
            hl:SetColorTexture(1, 1, 1, 0.06)
        end
        local fs = b:CreateFontString(nil, "OVERLAY", "BNBFontNormalSmall")
        fs:SetWordWrap(false)
        fs:SetText(L[c.title])
        b._fs = fs
        local ar = b:CreateTexture(nil, "ARTWORK")
        ar:SetSize(10, 10)
        BNB.TintUIIcon(ar)
        ar:Hide()
        b._ar = ar
        b._col = c
        if c.sort then
            b:SetScript("OnClick", function()
                local db = BigNoteBoxDB
                if (db.sortBy or BNB.DEFAULTS.sortBy) == c.sort then BNB.SetNoteSort(nil, not db.sortAsc)
                else BNB.SetNoteSort(c.sort, nil) end
            end)
            b:SetScript("OnEnter", function() hl:Show() end)
            b:SetScript("OnLeave", function() hl:Hide() end)
        end
        btns[c.key] = b
    end
    function hdr.Layout(layout)
        local hr, hg, hb = BNB.HeaderColor()
        rule:SetColorTexture(hr, hg, hb, HDR_RULE_A)
        local db = BigNoteBoxDB
        local sortBy = db.sortBy or BNB.DEFAULTS.sortBy
        local shown = {}
        for _, e in ipairs(layout) do
            local b = btns[e.col.key]
            shown[e.col.key] = true
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", hdr, "TOPLEFT", e.x, 0)
            b:SetWidth(e.w)
            b._fs:ClearAllPoints()
            -- Name starts over the titles (after the row icon), the rest over their text
            local lx = e.col.key == "name" and (4 + TILE_ICON.details + 6) or 0
            if e.col.right then
                b._fs:SetPoint("RIGHT", b, "RIGHT", 0, 0); b._fs:SetJustifyH("RIGHT")
            else
                b._fs:SetPoint("LEFT", b, "LEFT", lx, 0); b._fs:SetJustifyH("LEFT")
            end
            b._fs:SetTextColor(hr, hg, hb)
            local on = e.col.sort ~= nil and e.col.sort == sortBy
            b._ar:ClearAllPoints()
            if on then
                b._ar:SetTexture(ART .. (db.sortAsc and "ex-chevron-up" or "ex-chevron-down"))
                b._ar:SetPoint("LEFT", b._fs, "RIGHT", 4, 0)
            end
            b._ar:SetShown(on)
            b:Show()
        end
        for key, b in pairs(btns) do
            if not shown[key] then b:Hide() end
        end
    end
    _colHdr = hdr
end

-- Details on: the header shows and the grid starts under it; off: back
SyncDetailsHeader = function(on)
    if not _pane then return end
    if on and not _colHdr then BuildColumnHeader() end
    if _colHdr then _colHdr:SetShown(on) end
    if _sfDetails == on then return end
    _sfDetails = on
    _sf:ClearAllPoints()
    _sf:SetPoint("TOPLEFT", _pane, "TOPLEFT", PAD, on and -(PAD + COLHDR_H + 4) or -PAD)
    _sf:SetPoint("BOTTOMRIGHT", _pane, "BOTTOMRIGHT", -SCROLL_W, STATUS_H + 4)
end

local function HideMarkers(t)
    for _, m in ipairs(MARKERS) do t[m[1]]:Hide() end
    t._mLock:Hide()
end

local function FillNoteTile(t, note, size, section)
    t._noteID, t._sys, t._folderKey, t._folderName = note.id, note.system, nil, nil
    t._pickKey = (not note.system) and note.id or nil
    t._note = note
    t._sysKey = note.system and ("sysnote:" .. note.id) or nil
    t._section = section
    t._folderTex:Hide()
    t._folderGlow:Hide()
    t._folderTop:Hide()
    t._icon:Show()
    t._iconSize = size   -- repainted on a target change
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
    -- Not on a tile under the Pinned header, which says it already
    local pinFirst = BigNoteBoxDB and BigNoteBoxDB.explorerPinnedFirst == true
    t._mPin:SetShown(note.pinned and (pinFirst or section ~= "pinned") and true or false)
    local NK = BNB._NoteListKit
    t._mLock:SetShown(NK and NK.NoteIsLocked and NK.NoteIsLocked(note) and true or false)
end

-- key = a folder id or "sys:<key>"; name already plain text; r, g, b = its colour
local function FillFolderTile(t, key, name, n, r, g, b)
    t._noteID, t._sys, t._folderKey, t._folderName, t._count = nil, nil, key, name, n
    local sys = SysKey(key) ~= nil
    t._pickKey = (not sys) and ("folder:" .. key) or nil
    t._note = nil
    t._sysKey = sys and key or nil
    t._section = nil
    t._icon:Hide()
    BNB.ApplyIconFrame(t._icon, nil)   -- a note's frame art left on a reused tile
    if t._borderFrame then t._borderFrame:Hide() end
    HideMarkers(t)
    local hr, hg, hb = BNB.HeaderColor()
    local skin = BigNoteBoxDB and BigNoteBoxDB.skinMode
    -- The Patch notes folder has Dukul's own BNB picture (2026-10-22, drawn
    -- by PaintArt): it keeps the glow but gets no top layer
    local sysKey = SysKey(key)
    local bnb = sysKey == "patchnotes"
    BNB.Folders.PaintArt(t._folderTex, false, n > 0, r or hr, g or hg, b or hb, sysKey)
    t._folderTex:Show()
    if skin then
        t._folderGlow:Hide()
        t._folderTop:Hide()
    else
        t._folderGlow:SetVertexColor(r or hr, g or hg, b or hb)
        t._folderGlow:Show()
        t._folderTop:SetVertexColor(r or hr, g or hg, b or hb)
        t._folderTop:SetShown(not bnb)
    end
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
    local flat = IsFlat()
    local details = IsDetails() or flat   -- Flat draws Details rows
    local list = IsList()
    SyncDetailsHeader(details)
    local tileW = list and LIST_MIN_W or size + TILE_EXTRA
    local tileH = list and LIST_H or 6 + size + 4 + LABEL_H + 4
    local rowGap = list and LIST_GAP or GAP
    local width = _child:GetWidth()
    if not width or width < tileW then width = tileW end
    local cols = math.max(1, math.floor((width + GAP) / (tileW + GAP)))
    -- List rows share the width out, so the columns fill it
    if list then tileW = math.floor((width - (cols - 1) * GAP) / cols) end
    if details then
        cols, tileW, tileH, rowGap = 1, width, DETAILS_H, 0
        LayoutColumns(width)
    end

    for _, t in ipairs(_tiles) do t:Hide() end
    for _, h in ipairs(_hdrs) do h:Hide() end
    _emptyLbl:Hide()
    wipe(_order); wipe(_orderIdx); wipe(_shown); wipe(_kind)
    local sysSeen = {}
    _crumbHdr = nil

    -- Flat has no folders to be in; an open folder that is gone (deleted,
    -- module or setting off): top level
    if flat then _folder = nil end
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
    _count.notes, _count.folders = 0, 0
    if _status then _status:PaintRule() end   -- the header colour may have changed (skin preset)
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
        if details then ShapeDetailsTile(t, size, tileW)
        elseif list then ShapeListTile(t, size, tileW)
        else ShapeTile(t, size) end
        t:ClearAllPoints()
        t:SetPoint("TOPLEFT", _child, "TOPLEFT", col * (tileW + GAP), -y)
        t:Show()
        col = col + 1
        if col >= cols then col = 0; y = y + tileH + rowGap end
    end
    local function EndRow()
        if col > 0 then col = 0; y = y + tileH + rowGap end
    end
    local function NoteTile(note, section)
        ti = ti + 1
        local t = GetTile(ti)
        if not note.system and not _orderIdx[note.id] then
            _order[#_order + 1] = note.id
            _orderIdx[note.id] = #_order
            _kind[note.id] = "note"
            _shown[#_shown + 1] = t
        end
        FillNoteTile(t, note, size, section)
        if t._sysKey then sysSeen[t._sysKey] = true end
        Place(t)
        _count.notes = _count.notes + 1
    end
    local function FolderTile(key, name, n, r, g, b)
        ti = ti + 1
        local t = GetTile(ti)
        FillFolderTile(t, key, name, n, r, g, b)
        local pk = t._pickKey
        if pk and not _orderIdx[pk] then
            _order[#_order + 1] = pk
            _orderIdx[pk] = #_order
            _kind[pk] = "folder"
            _shown[#_shown + 1] = t
        end
        if t._sysKey then sysSeen[t._sysKey] = true end
        Place(t)
        _count.folders = _count.folders + 1
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

    if flat and not filtering then
        -- ── Flat: every note in the sort, pinned ones too, no folders and
        -- no section headers: the column row on top, the notes under it
        -- (Dukul, 2026-10-21)
        for _, n in ipairs(notes) do NoteTile(n, "results") end
        EndRow()
        if #notes == 0 then Empty("NOTE_LIST_EMPTY"); y = 80 end
    elseif sys then
        -- ── A system folder ─────────────────────────────────────────────────
        local p = SYS.Provider(sys)
        local list = SysList(sys)
        Header(L[p.name] .. " (" .. #list .. ")", { hasNotes = #list > 0, sys = p.key }, p.r, p.g, p.b, { crumb = true })
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
        for _, n in ipairs(FavFirst(list)) do NoteTile(n, _folder) end
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
        -- Pinned notes first, no sections (View menu, Dukul 2026-10-22): no
        -- headers, nothing closed; folders, then the pinned notes that are in
        -- no folder (a pinned note in a folder stays in its folder), then the rest
        local pinFirst = db.explorerPinnedFirst == true
        if pinFirst then
            for _, f in ipairs(folders) do
                local r, g, b = FD.Color(f.id)
                FolderTile(f.id, f.name, folderN[f.id] or 0, r, g, b)
            end
            for _, s in ipairs(sysFolders) do
                FolderTile("sys:" .. s.p.key, L[s.p.name], s.n, s.p.r, s.p.g, s.p.b)
            end
            for _, n in ipairs(pinned) do
                if not (FD and FD.Of(n)) then NoteTile(n, "pinned") end
            end
            for _, n in ipairs(FavFirst(regular)) do NoteTile(n, "notes") end
            EndRow()
        end
        if not pinFirst and #pinned > 0 then
            local closed = db.explorerPinnedClosed == true
            Header(string.format(L["NL_HDR_PINNED_FMT"], #pinned), "pinned", nil, nil, nil,
                { toggle = "explorerPinnedClosed", closed = closed })
            if not closed then
                for _, n in ipairs(pinned) do NoteTile(n, "pinned") end
                EndRow()
            else
                _count.notes = _count.notes + #pinned   -- a closed part still counts
            end
            y = y + 4
        end
        local notesClosed = pinFirst   -- drawn above already
        if not pinFirst and (#pinned > 0 or #folders > 0 or #regular > 0) then
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
            for _, n in ipairs(FavFirst(regular)) do NoteTile(n, "notes") end
            EndRow()
        elseif not pinFirst then
            _count.notes = _count.notes + #regular
            _count.folders = _count.folders + #folders + #sysFolders
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
    if _sysPick and not sysSeen[_sysPick] then _sysPick = nil end
    PaintPicks()

    local sfH = _sf:GetHeight() or 1
    _child:SetHeight(math.max(y, sfH))
    -- The bar follows what was drawn, not only OnScrollRangeChanged: going back
    -- from a long folder (or a resize while a note was open) could leave the old
    -- range, and the bar, up over a grid that fits (Dukul, 2026-10-22)
    _sf:UpdateScrollChildRect()
    local bar = _sf.ScrollBar
    if y <= sfH + 1 then
        _sf:SetVerticalScroll(0)
        if bar then bar:SetAlpha(0) end
    elseif bar then
        bar:SetAlpha(1)
    end
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

-- The live preview belongs to the editor: the grid hides it (the note stays
-- current, so nothing else closed it, Dukul, 2026-10-22) and leaving the grid
-- shows it again, only when the grid was what hid it
local _previewHidden = false
local function SyncPreview(grid)
    local RP = BNB.RichPreview
    if not RP then return end
    if grid then
        if RP.IsOpen() then RP.Close(); _previewHidden = true end
    elseif _previewHidden or RP._wantOpen then   -- _wantOpen: asked for while on the grid
        _previewHidden, RP._wantOpen = false, nil
        local note = BNB._currentNoteID and BNB.GetNote(BNB._currentNoteID)
        if note and _main and _main:IsShown() then RP.OnNoteSelected(note) end
    end
end

-- Lays the window out for the current view and mode
function EX.Apply()
    _applying = true
    local active = EX.IsActive()
    if active then EnsurePane() end
    if _pane then _pane:SetShown(active and _mode == "grid") end
    SyncPreview(active and _mode == "grid")
    if BNB._applyMainSplit then BNB._applyMainSplit() end
    if BNB.AM_RefreshTabs then BNB.AM_RefreshTabs() end   -- the Markup / Note tabs
    UpdateHeader()
    if active and _mode == "grid" then
        if K.LayoutToolRow then K.LayoutToolRow() end   -- takes the search row
        Refresh()
    end
    if BNB.RefreshFocusButton then BNB.RefreshFocusButton() end   -- ALL-569: grid or note
    -- The Reference Box belongs to the open note: the grid hides it, and the
    -- next note opened (or the list view) shows it again, closed there if
    -- that note has nothing for it, as a note switch in the list does
    -- (Dukul, 2026-10-27: it stayed open after leaving the note)
    -- ALL-616: on the grid it then follows the picked note (SyncRefBoxPick),
    -- so the way back re-syncs an open box to the open note as well
    _applying = nil
    if active and _mode == "grid" then
        -- Note Settings belongs to the note too: leaving it closes the window
        -- (Dukul, 2026-10-30: one opened for a new note stayed open, ALL-622)
        if BNB.SyncNoteConfig then BNB.SyncNoteConfig(nil) end
        if BNB.IsReferenceBoxShown and BNB.IsReferenceBoxShown() then
            _rbAway = true
            BNB.CloseReferenceBox()
        end
        _rbPickID = nil
        SyncRefBoxPick()
    elseif _rbAway then
        _rbAway, _rbPickID = nil, nil
        local id = BNB._currentNoteID
        if id and _main and _main:IsShown() and BNB.OpenReferenceBox then
            if not BNB.IsReferenceBoxShown() then BNB.OpenReferenceBox(id) end
            if BNB.SyncReferenceBox then BNB.SyncReferenceBox(id) end
        end
    end
end

-- After the module switch changed (Settings > Modules, the setup wizard):
-- off leaves the explorer for the note list; on shows the switch only
function BNB.ApplyExplorerModule(on)
    local db = BigNoteBoxDB
    if not (db and _main) then return end
    if not on and db.explorerView then
        if _boxState then FinishBox() end
        if _drag then EndDrag(false) end
        BNB.SaveCurrentNote()
        db.explorerView = false
        EX.Apply()
        if BNB.DockListSearch then BNB.DockListSearch(nil) end
        if BNB.RefreshNoteList then BNB.RefreshNoteList() end
    else
        UpdateHeader()
    end
end

function EX.SetActive(on)
    on = on and true or false
    if on and not BNB.ExplorerEnabled() then return end
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
-- The switch icon (the welcome's callout points at it, ALL-543)
function EX.ViewButton() return _viewBtn end

function EX.BuildHeader(f, sortDD, dirDD, selBtn)
    _main, _sortDD, _dirDD, _selBtn = f, sortDD, dirDD, selBtn
    -- A closed window forgets the hidden Reference Box (it closes with it)
    f:HookScript("OnHide", function() _rbAway, _rbPickID = nil, nil end)
    -- Built once per session: the window opens on the default view (Dukul,
    -- 2026-10-21); the switch changes it until the next login or reload
    local db = BigNoteBoxDB
    if db then db.explorerView = BNB.ExplorerEnabled() and db.explorerDefault ~= "list" end

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
    _lead, _sortAnchor = lead, true
    local tx = vb:CreateTexture(nil, "ARTWORK")
    tx:SetAllPoints()
    BNB.TintUIIcon(tx)
    BNB.AddUIIconHover(vb, tx)
    _viewTx, _viewBtn = tx, vb
    vb._tx = tx   -- the welcome's lit copy reads it (UI/ExplorerIntro.lua)
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
    -- "closed": kept by the Remember the open note setting; that note may be
    -- gone since (deleted from a sticky, the Oracle)
    local closed = _keepNote == "closed"
    local note = _keepNote and BNB._currentNoteID and BNB.GetNote(BNB._currentNoteID)
    if not note then _mode = "grid" end
    _keepNote = nil
    EX.Apply()
    -- The window's close took the live preview with it (Focus mode brings
    -- its own back); OnNoteSelected opens it when Auto show is on
    if closed and note and BNB.RichPreview then BNB.RichPreview.OnNoteSelected(note) end
end

-- MainWindow's OnHide (a real close and Focus mode's hide). Esc steps out of
-- a note first (EX.Back), so a close from a note is X, a key or a command
function EX.OnWindowHide(f)
    if _mode ~= "note" then _keepNote = nil
    elseif f._focusHide then _keepNote = "focus"
    elseif BigNoteBoxDB and BigNoteBoxDB.explorerKeepNote then _keepNote = "closed"
    else _keepNote = nil end
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
-- A player / NPC note shows the live portrait while its unit is targeted:
-- repaint just those tiles when the target changes, as the note list does
-- (UI/NoteList.lua; the grid kept the round portrait after the target went)
BNB.RegisterEvent("PLAYER_TARGET_CHANGED", function()
    if not (EX.IsActive() and BNB.mainFrame and BNB.mainFrame:IsShown()) then return end
    for _, t in ipairs(_tiles) do
        local note = t:IsShown() and t._noteID and BNB.GetNote(t._noteID)
        if note and (note.source == "target" or note.source == "inspect") then
            BNB.PaintNoteIcon(t, t._icon, note, t._iconSize)
        end
    end
end)
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

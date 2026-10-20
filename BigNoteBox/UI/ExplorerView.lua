-- BigNoteBox UI/ExplorerView.lua -- Explorer note view (ALL-414)
--
-- Notes as a grid of icons that takes over the main window, as Windows
-- Explorer (Dukul, inbox 2026-10-09; scoped 2026-10-20). The note list pane
-- and the splitter are hidden; this file's pane fills the space instead.
-- Clicking a note opens it in the normal editor at full width, and the back
-- arrow left of the sort dropdown (or Esc) returns to the grid.
--
-- The grid: Pinned (every pinned note, as the list's Pinned part), then under
-- Notes the folder tiles (A-Z), the notes in no folder, then the system
-- folders (Patch notes, Help). A folder tile opens that folder as its own
-- grid; back goes up a level. Every part follows the sort and order dropdowns
-- (GetOrderedNotes with noFloat, as the list), and the custom order is the
-- list's own.
--
-- Saved: BigNoteBoxDB.explorerView (the view is on), explorerTile (tile size
-- "small" / "medium" / "large"). Which folder is open and whether a note is
-- open are per session; the window always opens on the grid, except back
-- from Focus mode.
--
-- PUBLIC API (BNB.Explorer):
--   EX.IsActive()           the view is on (and the notes are available)
--   EX.Mode()               nil (list view), "grid" or "note"
--   EX.SetActive(on)        switch views (the toolbar strip button)
--   EX.Back()               one step back; false when there is none (Esc)
--   EX.BuildHeader(f, sortDD, dirDD, selBtn)   MainWindow.lua's toolbar strip
--
-- Stage 1 (this build): grid, folders, sort, tile sizes, open / back, the
-- empty-space menu. Stage 2: search bar + filters, Select mode, dragging,
-- status markers on the tiles.
--------------------------------------------------------------------------------

local BNB = BigNoteBox
local L   = BNB.L

local EX = {}
BNB.Explorer = EX

local ASSETS     = "Interface\\AddOns\\BigNoteBox\\Assets\\UI\\"
local VIEW_TEX   = ASSETS .. "ui-explorer-view"   -- placeholder art, Dukul redraws
local LIST_TEX   = ASSETS .. "ui-list-view"
local DEFAULT_ICON_SIZE = "medium"
local TILE_ICON  = { small = 40, medium = 56, large = 72 }
local TILE_EXTRA = 36    -- tile width = icon + this: room for the name
local LABEL_H    = 26    -- two lines of the name under the icon
local PAD        = 10    -- the grid's inner margin
local GAP        = 6     -- between tiles
local HDR_H      = 22    -- section header row
local HDR_ICON   = 20
local HDR_RULE_A = 0.35  -- the note list's header rule alpha (ALL-328)
local VIEW_BTN   = 18    -- the switch, as the list's tree buttons
local BACK_BTN   = 22
local SCROLL_W   = 22    -- room for the scroll bar (it draws outside its frame)

local REFRESH_KEY = "explorerRefresh"

local _main, _sortDD, _selBtn, _viewTx, _backBtn
local _sortX              -- the sort dropdown's own x, before the back arrow moves it
local _pane, _sf, _child, _emptyLbl
local _tiles, _hdrs = {}, {}
local _mode   = "grid"    -- "grid" | "note", only while the view is on
local _folder             -- nil = top level, a folder id, or "sys:<key>"
local _keepNote           -- Focus mode hid the window while a note was open

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

-- ── Header controls (toolbar strip) ─────────────────────────────────────────
local function UpdateHeader()
    local on = EX.IsActive()
    if _viewTx then _viewTx:SetTexture(on and LIST_TEX or VIEW_TEX) end
    local back = on and (_mode == "note" or _folder ~= nil)
    if _backBtn then _backBtn:SetShown(back) end
    if _sortDD and _sortX then
        local pt, rel, relPt, _, y = _sortDD:GetPoint(1)
        if pt then
            _sortDD:SetPoint(pt, rel, relPt, _sortX + (back and (BACK_BTN + 4) or 0), y)
        end
    end
    -- Select mode works on the list only until stage 2
    if _selBtn then
        _selBtn:SetEnabled(not on)
        _selBtn:SetAlpha(on and 0.4 or 1)
    end
    if BNB.ApplyToolbarIcons then BNB.ApplyToolbarIcons() end
end

-- ── Grid pane ───────────────────────────────────────────────────────────────
local Refresh   -- forward: tiles and the pane call it

local function Queue() BNB.Debounce(REFRESH_KEY, 0, function() Refresh() end) end

local function ShowEmptyMenu(owner)
    local FD = BNB.FoldersEnabled() and BNB.Folders or nil
    BNB.ContextMenu.Open(owner, function(root)
        root:CreateButton(L["FOLDER_CM_NEW_NOTE"], function()
            local NND = BNB.NewNoteDialog
            if not (NND and NND.Open) then return end
            -- Inside a folder the note goes in it (a system folder takes none)
            local inFolder = _folder and not SysKey(_folder) and FD and FD.Get(_folder) and _folder
            NND.Open(inFolder and { folder = inFolder } or nil)
        end, { icon = "create" })
        if FD then
            root:CreateButton(L["FOLDER_CM_NEW_FOLDER"], function()
                BNB.PromptFolderName({ mode = "new" })
            end, { icon = "folder-add" })
        end
        root:CreateDivider()
        -- Sort by: the toolbar strip's two dropdowns in one sub-menu (Dukul,
        -- 2026-10-20); the order means nothing in Custom, so it is greyed there
        if BNB.SetNoteSort and BNB.NOTE_SORT_MODES then
            local sortSub = root:CreateButton(L["EXPLORER_CM_SORT_BY"])
            local function Sort() return BigNoteBoxDB.sortBy or BNB.DEFAULTS.sortBy end
            for _, m in ipairs(BNB.NOTE_SORT_MODES) do
                local key = m.key
                sortSub:CreateRadio(m.label, function() return Sort() == key end,
                    function() BNB.SetNoteSort(key, nil) end)
            end
            sortSub:CreateDivider()
            local custom = Sort() == "custom"
            sortSub:CreateRadio(L["DIR_MODE_DESC"], function() return not BigNoteBoxDB.sortAsc end,
                function() BNB.SetNoteSort(nil, false) end, { disabled = custom })
            sortSub:CreateRadio(L["DIR_MODE_ASC"], function() return BigNoteBoxDB.sortAsc == true end,
                function() BNB.SetNoteSort(nil, true) end, { disabled = custom })
        end
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
    -- Right-click on empty space: the grid's own menu
    child:EnableMouse(true)
    child:SetScript("OnMouseUp", function(self, button)
        if button == "RightButton" then ShowEmptyMenu(self) end
    end)

    local lbl = child:CreateFontString(nil, "OVERLAY", "BNBFontNormal")
    lbl:SetPoint("TOP", child, "TOP", 0, -24)
    lbl:SetWidth(240); lbl:SetJustifyH("CENTER"); lbl:SetWordWrap(true)
    lbl:SetTextColor(0.38, 0.38, 0.38)
    lbl:Hide()
    _emptyLbl = lbl
end

-- Section header: picture, label, a rule to the right edge (the note list's
-- Pinned / Notes / folder headers). art = "pinned" / "notes" (section art) or
-- a folder: { folder = true, hasNotes, r, g, b }
local function GetHeader(i)
    local hdr = _hdrs[i]
    if hdr then return hdr end
    hdr = CreateFrame("Frame", nil, _child)
    hdr:SetHeight(HDR_H)
    local pic = hdr:CreateTexture(nil, "ARTWORK")
    pic:SetSize(HDR_ICON, HDR_ICON)
    pic:SetPoint("LEFT", hdr, "LEFT", 0, 0)
    local fs = hdr:CreateFontString(nil, "OVERLAY", "BNBFontNormalSmall")
    fs:SetPoint("LEFT", pic, "RIGHT", 4, 0)
    fs:SetJustifyH("LEFT"); fs:SetWordWrap(false)
    local rule = hdr:CreateTexture(nil, "ARTWORK")
    if rule.SetSnapToPixelGrid then rule:SetSnapToPixelGrid(false); rule:SetTexelSnappingBias(0) end
    if PixelUtil and PixelUtil.SetHeight then PixelUtil.SetHeight(rule, 1, 1) else rule:SetHeight(1) end
    rule:SetPoint("LEFT", fs, "RIGHT", 6, 0)
    rule:SetPoint("RIGHT", hdr, "RIGHT", 0, 0)
    hdr._pic, hdr._text, hdr._rule = pic, fs, rule
    _hdrs[i] = hdr
    return hdr
end

local function PaintHeader(hdr, text, art, r, g, b)
    local hr, hg, hb = BNB.HeaderColor()
    r, g, b = r or hr, g or hg, b or hb
    if type(art) == "table" then
        BNB.Folders.PaintArt(hdr._pic, true, art.hasNotes, r, g, b)
    else
        BNB.Folders.PaintSectionArt(hdr._pic, art, hr, hg, hb)
    end
    hdr._text:SetText(text)
    hdr._text:SetTextColor(r, g, b)
    hdr._rule:SetColorTexture(r, g, b, HDR_RULE_A)
end

-- ── Tiles ───────────────────────────────────────────────────────────────────
local function TileClick(self, button)
    if self._folderKey then
        if button == "RightButton" then
            local sys = SysKey(self._folderKey)
            if sys then
                if BNB.ShowSystemFolderMenu then BNB.ShowSystemFolderMenu(self, sys) end
            elseif BNB.ShowFolderMenu then
                BNB.ShowFolderMenu(self, self._folderKey)
            end
            return
        end
        GameTooltip:Hide()
        _folder = self._folderKey
        if _sf then _sf:SetVerticalScroll(0) end
        UpdateHeader()
        Refresh()
        return
    end
    local id = self._noteID
    if not id then return end
    if button == "RightButton" then
        if self._sys then
            if BNB.ShowSystemNoteMenu then BNB.ShowSystemNoteMenu(self, id) end
        else
            BNB.ShowNoteContextMenu(self, id)
        end
        return
    end
    GameTooltip:Hide()
    if BNB._currentNoteID == id then
        _mode = "note"
        EX.Apply()
    else
        BNB.SaveCurrentNote()
        BNB.SelectNote(id)   -- NoteSelected switches to the note
    end
end

local function TileEnter(self)
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

local function GetTile(i)
    local t = _tiles[i]
    if t then return t end
    t = CreateFrame("Button", nil, _child)
    t:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    -- Hover and the open note: the list window rows' art (green in the normal
    -- look, flat fills in skin mode)
    t._hover = BNB.CreateListRowArt(t, "hover", { 1, 1, 1, 0.06 })
    t._sel   = BNB.CreateListRowArt(t, "selection", { 0.40, 0.85, 0.40, 0.18 })
    t:HookScript("OnEnter", function(self) self._hover:Show() end)
    t:HookScript("OnLeave", function(self) self._hover:Hide() end)
    t:HookScript("OnHide",  function(self) self._hover:Hide() end)
    t._icon = t:CreateTexture(nil, "ARTWORK")
    t._folderTex = t:CreateTexture(nil, "ARTWORK")
    local fs = t:CreateFontString(nil, "OVERLAY", "BNBFontHighlightSmall")
    fs:SetJustifyH("CENTER"); fs:SetJustifyV("TOP")
    fs:SetWordWrap(true)
    if fs.SetMaxLines then fs:SetMaxLines(2) end
    t._label = fs
    t:SetScript("OnClick", TileClick)
    t:SetScript("OnEnter", TileEnter)
    t:SetScript("OnLeave", TileLeave)
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
end

local function FillNoteTile(t, note, size)
    t._noteID, t._sys, t._folderKey, t._folderName = note.id, note.system, nil, nil
    t._folderTex:Hide()
    t._icon:Show()
    BNB.PaintNoteIcon(t, t._icon, note, size)
    local hasTitle = note.title and note.title ~= ""
    t._label:SetText(hasTitle and note.title or L["UNTITLED"])
    local tc = note.titleColor
    if tc then t._label:SetTextColor(tc.r, tc.g, tc.b, 1)
    else t._label:SetTextColor(BNB.TextWhite(hasTitle and 1 or 0.5)) end
    t._sel:SetShown(note.id == BNB._currentNoteID)
end

-- key = a folder id or "sys:<key>"; name already plain text; r, g, b = its colour
local function FillFolderTile(t, key, name, n, r, g, b)
    t._noteID, t._sys, t._folderKey, t._folderName, t._count = nil, nil, key, name, n
    t._icon:Hide()
    BNB.ApplyIconFrame(t._icon, nil)   -- a note's frame art left on a reused tile
    if t._borderFrame then t._borderFrame:Hide() end
    local hr, hg, hb = BNB.HeaderColor()
    BNB.Folders.PaintArt(t._folderTex, false, n > 0, r or hr, g or hg, b or hb)
    t._folderTex:Show()
    t._label:SetText(name .. " (" .. n .. ")")
    t._label:SetTextColor(r or hr, g or hg, b or hb)
    t._sel:Hide()
end

-- ── Drawing ─────────────────────────────────────────────────────────────────
Refresh = function()
    if not (EX.IsActive() and _mode == "grid" and _pane and _pane:IsVisible()) then return end
    BNB.CancelDebounce(REFRESH_KEY)
    local FD  = BNB.FoldersEnabled() and BNB.Folders or nil
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
    local function Header(text, art, r, g, b)
        hi = hi + 1
        local hdr = GetHeader(hi)
        PaintHeader(hdr, text, art, r, g, b)
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
    local function NoteTile(note)
        ti = ti + 1
        local t = GetTile(ti)
        FillNoteTile(t, note, size)
        Place(t)
    end
    local function FolderTile(key, name, n, r, g, b)
        ti = ti + 1
        local t = GetTile(ti)
        FillFolderTile(t, key, name, n, r, g, b)
        Place(t)
    end

    local notes = BNB.GetOrderedNotes("", nil, true)

    if sys then
        -- ── A system folder ─────────────────────────────────────────────────
        local p = SYS.Provider(sys)
        local list = SYS.Notes(sys)
        Header(L[p.name] .. " (" .. #list .. ")", { hasNotes = #list > 0 }, p.r, p.g, p.b)
        for _, n in ipairs(list) do NoteTile(n) end
        EndRow()
        if #list == 0 then
            _emptyLbl:SetText(L["EXPLORER_FOLDER_EMPTY"]); _emptyLbl:Show()
        end
    elseif _folder then
        -- ── A folder: its notes, pinned ones too ────────────────────────────
        local list = {}
        for _, n in ipairs(notes) do
            if FD.Of(n) == _folder then list[#list + 1] = n end
        end
        local r, g, b = FD.Color(_folder)
        local rec = FD.Get(_folder)
        Header((rec.name or "") .. " (" .. #list .. ")", { hasNotes = #list > 0 }, r, g, b)
        for _, n in ipairs(list) do NoteTile(n) end
        EndRow()
        if #list == 0 then
            _emptyLbl:SetText(L["EXPLORER_FOLDER_EMPTY"]); _emptyLbl:Show()
        end
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

        if #pinned > 0 then
            Header(string.format(L["NL_HDR_PINNED_FMT"], #pinned), "pinned")
            for _, n in ipairs(pinned) do NoteTile(n) end
            EndRow()
            y = y + 4
        end
        if #pinned > 0 or #folders > 0 or #regular > 0 then
            Header(string.format(L["NL_HDR_REGULAR_FMT"], #regular), "notes")
        end
        for _, f in ipairs(folders) do
            local r, g, b = FD.Color(f.id)
            FolderTile(f.id, f.name, folderN[f.id] or 0, r, g, b)
        end
        for _, n in ipairs(regular) do NoteTile(n) end
        EndRow()
        -- The system folders on a row of their own, after a small gap
        if #sysFolders > 0 then
            y = y + 4
            for _, s in ipairs(sysFolders) do
                FolderTile("sys:" .. s.p.key, L[s.p.name], s.n, s.p.r, s.p.g, s.p.b)
            end
            EndRow()
        end
        if #notes == 0 and #folders == 0 and #sysFolders == 0 then
            _emptyLbl:SetText(L["NOTE_LIST_EMPTY"]); _emptyLbl:Show()
            y = 80
        end
    end

    _child:SetHeight(math.max(y, _sf:GetHeight() or 1))
end

-- ── Switching ───────────────────────────────────────────────────────────────
-- Lays the window out for the current view and mode
function EX.Apply()
    local active = EX.IsActive()
    if active then EnsurePane() end
    if _pane then _pane:SetShown(active and _mode == "grid") end
    if BNB._applyMainSplit then BNB._applyMainSplit() end
    UpdateHeader()
    if active and _mode == "grid" then Refresh() end
end

function EX.SetActive(on)
    on = on and true or false
    if not (BigNoteBoxDB and _main) or on == EX.IsActive() then return end
    BNB.SaveCurrentNote()
    BigNoteBoxDB.explorerView = on
    if on then
        -- The grid has no search row or Select mode yet (stage 2): both reset
        if BNB.IsMultiMode and BNB.IsMultiMode() then BNB.SetMultiMode(false) end
        if BNB.ResetListFilters then BNB.ResetListFilters() end
        _mode, _folder = "grid", nil
    end
    EX.Apply()
    if not on then
        if BNB.RefreshNoteList then BNB.RefreshNoteList() end
        if BNB._currentNoteID and BNB.ScrollNoteListTo then BNB.ScrollNoteListTo(BNB._currentNoteID) end
    end
end

function EX.Back()
    if not EX.IsActive() then return false end
    if _mode == "note" then
        BNB.SaveCurrentNote()
        _mode = "grid"
    elseif _folder then
        _folder = nil
        if _sf then _sf:SetVerticalScroll(0) end
    else
        return false
    end
    EX.Apply()
    return true
end

-- ── Toolbar strip: the switch and the back arrow ────────────────────────────
function EX.BuildHeader(f, sortDD, dirDD, selBtn)
    _main, _sortDD, _selBtn = f, sortDD, selBtn
    local _, _, _, x = sortDD:GetPoint(1)
    _sortX = x

    -- The switch: bare white art tinted like the search row's tree buttons
    local vb = CreateFrame("Button", nil, f)
    vb:SetSize(VIEW_BTN, VIEW_BTN)
    vb:SetPoint("LEFT", dirDD, "RIGHT", 6, 0)
    local tx = vb:CreateTexture(nil, "ARTWORK")
    tx:SetAllPoints()
    BNB.TintUIIcon(tx)
    BNB.AddUIIconHover(vb, tx)
    _viewTx = tx
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
    selBtn:SetPoint("LEFT", vb, "RIGHT", 6, 0)

    -- Back: the Settings sub-page arrow (ConfigWindow.lua NewSubPage)
    local back = BNB.CreateIconButton(f, BACK_BTN, "left", {
        onClick = function() EX.Back() end,
        tip = L["CFG_SUBPAGE_BACK"], tipAnchor = "ANCHOR_RIGHT" })
    back:SetPoint("RIGHT", sortDD, "LEFT", -4, 0)
    back:Hide()
    _backBtn = back

    -- The window opens on the grid, except back from Focus mode (it hides
    -- the window with _focusHide set and shows it again)
    f:HookScript("OnHide", function(self)
        _keepNote = self._focusHide and _mode == "note" or nil
    end)
    f:HookScript("OnShow", function()
        if not EX.IsActive() then UpdateHeader(); return end
        if not _keepNote then _mode = "grid" end
        _keepNote = nil
        EX.Apply()
    end)
    UpdateHeader()
end

-- ── Following the notes ─────────────────────────────────────────────────────
-- The grid redraws after every note list redraw (sort, tab, create, delete,
-- folders, system folders, skin) and on any note change (title, icon), one
-- redraw per frame
BNB.RegisterMessage("Explorer", "NoteListRefreshed", Queue)
BNB.RegisterMessage("Explorer", "NoteChanged", Queue)

-- A note selected anywhere (a tile, New note, the Oracle, a toast) opens it;
-- nothing selected (the open note deleted) goes back to the grid
BNB.RegisterMessage("Explorer", "NoteSelected", function(_, id)
    if not EX.IsActive() then return end
    local want = id and "note" or "grid"
    if want ~= _mode then
        _mode = want
        EX.Apply()
    end
end)

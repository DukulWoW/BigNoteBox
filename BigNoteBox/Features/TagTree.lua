-- BigNoteBox Features/TagTree.lua
-- Tree view: groups notes under headers in the note list scroll area, by tag
-- (the tag tree) or by folder (the folder view, ALL-510 S4). One view, two
-- sources: BigNoteBoxDB.tagTreeMode = a tree is shown, BigNoteBoxDB.treeSource
-- = nil (tags) or "folders". Opened from the two buttons left of the search
-- bar (UI/NoteList.lua); BNB.SetTagTreeMode(enabled, source).
-- Shares the scroll frame / scroll child / listEntries pool with NoteList.lua.
--
-- Tags: every tag A-Z, then Untagged; open / closed is per session
-- (tagTreeStartExpanded). Folders: every folder A-Z, then No folder; a folder's
-- open / closed is its saved state (BNB.Folders, the same as in the list),
-- No folder per session. Notes A-Z by title inside a header, every tab.

local BNB = BigNoteBox
local L   = BNB.L

--------------------------------------------------------------------------------
-- Module state
--------------------------------------------------------------------------------
local _expandedTags  = {}   -- { [tagName] = true } when that header is expanded
local _tagHeaders    = {}   -- reused header frames { btn, arrow, label, count }
local _dragCollapsed = false   -- a note carried in the folder view: every header drawn closed
local _collapseAllBtn, _expandAllBtn  -- pinned control buttons inside scroll child
local UNTAGGED  = "__untagged__"
local NO_FOLDER = "__nofolder__"
local _noFolderOpen = nil   -- the folder view's No folder header (nil = start state)

local HEADER_H   = 24
local ENTRY_INDENT = 8      -- px left indent for notes under a tag header
local PAD_L      = 8
local BTN_SZ     = 18   -- arrow button size, matches AlarmWindow calendar nav buttons
local FOLDER_PIC = 18   -- the folder picture in a folder view header

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------
local function DB()  return BigNoteBoxDB          end

local function FolderView()
    local db = DB()
    return db and db.treeSource == "folders" and BNB.Folders ~= nil and BNB.FoldersEnabled()   -- ALL-514
end

local function ByTitle(a, b)
    return BNB.NoteTitleKey(a) < BNB.NoteTitleKey(b)
end

-- The notes the view shows: the text filter and favourite filter, every tab
local function FilteredSet()
    local textFilter = BNB.GetCurrentFilter and BNB.GetCurrentFilter() or ""
    local filtered = BNB.GetOrderedNotes(textFilter, nil, false, true)
    local filteredSet = {}
    for _, note in ipairs(filtered) do
        filteredSet[note.id] = note
    end
    -- Apply fav filter on top if active
    if BNB._favFilterActive then
        for id, note in pairs(filteredSet) do
            if not note.favorited then filteredSet[id] = nil end
        end
    end
    return filteredSet, textFilter ~= "" or BNB._favFilterActive == true
end

-- Returns ordered list of { key, label, notes[] } sorted A-Z, and the
-- leftover bucket (Untagged / No folder) as { key, label, notes[] }.
local function BuildTagBuckets()
    local tagIndex = BNB.TagIndex()
    local filteredSet = FilteredSet()

    -- Collect all known tags A-Z
    local tagList = BNB.GetAllTags()  -- { {tag, count} } already sorted A-Z
    local TC = BNB.TagColors   -- the tag's colour (ALL-106)

    local buckets  = {}
    local untagged = {}

    for _, entry in ipairs(tagList) do
        local tag  = entry.tag
        local ids  = tagIndex[tag] or {}
        local notes = {}
        for id in pairs(ids) do
            local note = filteredSet[id]
            if note then notes[#notes + 1] = note end
        end
        -- Sort notes within bucket A-Z by title
        table.sort(notes, ByTitle)
        if #notes > 0 then
            buckets[#buckets + 1] = { key = tag, notes = notes,
                label = TC and TC.Text(tag) or tag }
        end
    end

    -- Untagged bucket
    for _, note in pairs(filteredSet) do
        if not note.tags or #note.tags == 0 then
            untagged[#untagged + 1] = note
        end
    end
    table.sort(untagged, ByTitle)

    return buckets, { key = UNTAGGED, notes = untagged,
        label = "|cff888888" .. L["TAGTREE_UNTAGGED"] .. "|r" }
end

-- Folders A-Z: one with a shown note, and an empty one while nothing is
-- filtered (as in the list, so it can be found); then No folder
local function BuildFolderBuckets()
    local FD = BNB.Folders
    local filteredSet, filtering = FilteredSet()
    local byFolder, loose = {}, {}
    for _, note in pairs(filteredSet) do
        local fid = FD.Of(note)
        if fid then
            local t = byFolder[fid]
            if not t then t = {}; byFolder[fid] = t end
            t[#t + 1] = note
        else
            loose[#loose + 1] = note
        end
    end
    local total = FD.Counts()
    local buckets = {}
    for _, f in ipairs(FD.List()) do
        local notes = byFolder[f.id]
        if notes or (not filtering and not total[f.id]) then
            notes = notes or {}
            table.sort(notes, ByTitle)
            buckets[#buckets + 1] = { key = f.id, folder = true, notes = notes,
                label = FD.Text(f.id) }
        end
    end
    table.sort(loose, ByTitle)
    return buckets, { key = NO_FOLDER, notes = loose,
        label = "|cff888888" .. L["FOLDER_TREE_NONE"] .. "|r" }
end

-- The system folders (ALL-511), after No folder: their notes newest first,
-- matched to the search text; the favourite filter hides them
local function BuildSystemBuckets()
    local SYS, out = BNB.SystemNotes, {}
    if not SYS or BNB._favFilterActive then return out end
    local text = BNB.GetCurrentFilter and BNB.GetCurrentFilter() or ""
    local lower = text ~= "" and text:lower() or nil
    for _, p in ipairs(SYS.Folders()) do
        local notes = SYS.Search(p.key, lower)
        if #notes > 0 then
            local label = L[p.name]
            if p.r then label = string.format("|cff%02x%02x%02x%s|r", p.r * 255, p.g * 255, p.b * 255, label) end
            out[#out + 1] = { key = p.key, sys = true, notes = notes, label = label, forced = lower ~= nil }
        end
    end
    return out
end

-- Open / closed of a header, and the change
local function IsExpanded(b)
    if _dragCollapsed then return false end   -- while a note is carried (BNB.TagTreeDragCollapse)
    if b.folder then return BNB.Folders.IsOpen(b.key) end
    if b.sys then return b.forced or BNB.SystemNotes.IsOpen(b.key) end
    if b.key == NO_FOLDER then
        if _noFolderOpen == nil then
            local db = DB()
            _noFolderOpen = db and db.tagTreeStartExpanded == true or false
        end
        return _noFolderOpen
    end
    return _expandedTags[b.key] or false
end

local function SetExpanded(b, on)
    if b.folder then BNB.Folders.SetOpen(b.key, on)   -- FoldersChanged redraws
    elseif b.sys then BNB.SystemNotes.SetOpen(b.key, on)   -- SystemNotesChanged redraws
    elseif b.key == NO_FOLDER then _noFolderOpen = on
    elseif on then _expandedTags[b.key] = true
    else _expandedTags[b.key] = nil end
end

--------------------------------------------------------------------------------
-- Tag header widget pool
--------------------------------------------------------------------------------
local function GetOrCreateTagHeader(child, idx)
    if _tagHeaders[idx] then return _tagHeaders[idx] end

    local btn = CreateFrame("Button", nil, child)
    btn:SetHeight(HEADER_H)
    btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    local hiBg = btn:CreateTexture(nil, "HIGHLIGHT")
    hiBg:SetAllPoints(); hiBg:SetColorTexture(1, 1, 1, 0.05)

    -- Arrow: icon button ("right" = collapsed, "down" = expanded), 18x18 like
    -- the AlarmWindow calendar arrows. Clicks go to the parent header button.
    local arrowBtn = BNB.CreateIconButton(btn, BTN_SZ, "right",
        { onClick = function() btn:Click() end })
    arrowBtn:SetPoint("LEFT", btn, "LEFT", PAD_L, 0)
    btn._arrowBtn  = arrowBtn

    -- The folder view's picture (Dukul's art, never tinted), between arrow and name
    local pic = btn:CreateTexture(nil, "ARTWORK")
    pic:SetSize(FOLDER_PIC, FOLDER_PIC)
    pic:SetPoint("LEFT", arrowBtn, "RIGHT", 2, 0)
    pic:Hide()
    btn._pic = pic

    local lbl = btn:CreateFontString(nil, "OVERLAY", "BNBFontNormal")
    lbl:SetPoint("RIGHT", btn, "RIGHT", -40, 0)
    lbl:SetJustifyH("LEFT")
    BNB.SetTextWhite(lbl)
    btn._lbl = lbl

    local countLbl = btn:CreateFontString(nil, "OVERLAY", "BNBFontNormalSmall")
    countLbl:SetPoint("RIGHT", btn, "RIGHT", -PAD_L, 0)
    countLbl:SetJustifyH("RIGHT")
    countLbl:SetTextColor(0.55, 0.55, 0.55, 1)
    btn._count = countLbl

    -- Thin divider at bottom of header
    local div = btn:CreateTexture(nil, "ARTWORK")
    div:SetHeight(1)
    div:SetPoint("BOTTOMLEFT",  btn, "BOTTOMLEFT",  PAD_L, 0)
    div:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -PAD_L, 0)
    div:SetColorTexture(0.30, 0.30, 0.33, 0.6)

    _tagHeaders[idx] = btn
    return btn
end

--------------------------------------------------------------------------------
-- Collapse All / Expand All controls
--------------------------------------------------------------------------------
local CTRL_H = 22   -- matches Select button height in the topbar

local function GetOrCreateCollapseControls(child)
    if _collapseAllBtn and _expandAllBtn then
        return _collapseAllBtn, _expandAllBtn
    end

    -- Two equal-width buttons filling the full width of the scroll child.
    -- A thin container row is sized to child width via OnSizeChanged so both
    -- buttons always split 50/50 regardless of pane resize.
    local ctrlRow = CreateFrame("Frame", nil, child)
    ctrlRow:SetHeight(CTRL_H)
    ctrlRow:SetPoint("TOPLEFT",  child, "TOPLEFT",  0, -4)
    ctrlRow:SetPoint("TOPRIGHT", child, "TOPRIGHT", 0, -4)

    _collapseAllBtn = BNB.CreateButton(nil, ctrlRow, L["TAGTREE_COLLAPSE_ALL"], 80, CTRL_H)
    _collapseAllBtn:SetPoint("TOPLEFT",  ctrlRow, "TOPLEFT",  0, 0)
    _collapseAllBtn:SetPoint("TOPRIGHT", ctrlRow, "TOP",      -2, 0)

    _expandAllBtn = BNB.CreateButton(nil, ctrlRow, L["TAGTREE_EXPAND_ALL"], 80, CTRL_H)
    _expandAllBtn:SetPoint("TOPLEFT",  ctrlRow, "TOP",      2,  0)
    _expandAllBtn:SetPoint("TOPRIGHT", ctrlRow, "TOPRIGHT", 0,  0)

    return _collapseAllBtn, _expandAllBtn
end

--------------------------------------------------------------------------------
-- Main refresh
--------------------------------------------------------------------------------
function BNB.RefreshTagTree()
    local child   = BNB._listScrollChild
    local entries = BNB._listEntries
    if not child or not entries then return end

    -- Hide list-mode persistent section headers (pinned, regular, divider)
    -- These are header frames stored on child by RefreshNoteList; they are not
    -- cleared when we delegate to RefreshTagTree, so we hide them explicitly.
    if child._pinnedHdr  then child._pinnedHdr:Hide()  end
    -- (_pinnedDiv is gone since ALL-328: the headers carry their own rule)
    if child._regularHdr then child._regularHdr:Hide()  end
    for _, hdr in ipairs(child._folderHdrs or {}) do hdr:Hide() end   -- ALL-510

    -- Hide all existing list entries first
    for _, btn in ipairs(entries) do
        btn:Hide(); btn:ClearAllPoints()
    end

    -- Hide any leftover tag headers beyond what we'll use
    for _, hdr in ipairs(_tagHeaders) do
        hdr:Hide()
    end

    local db        = DB()
    local selID     = BNB._currentNoteID
    local collapsed = BNB._listCollapsed

    -- In collapsed (icon-only) mode just fall through to normal list
    if collapsed then
        -- Delegate back — temporarily disable tag tree so RefreshNoteList works
        local prev = db.tagTreeMode
        db.tagTreeMode = false
        BNB.RefreshNoteList()
        db.tagTreeMode = prev
        return
    end

    local ENTRY_H = 52  -- normal entry height; TagTree always uses normal mode
    local folderView = FolderView()
    local buckets, rest
    if folderView then buckets, rest = BuildFolderBuckets()
    else buckets, rest = BuildTagBuckets() end
    local all = {}
    for _, b in ipairs(buckets) do all[#all + 1] = b end
    if #rest.notes > 0 then all[#all + 1] = rest end
    if folderView then
        for _, b in ipairs(BuildSystemBuckets()) do all[#all + 1] = b end
    end

    -- Collapse/expand controls
    local colBtn, expBtn = GetOrCreateCollapseControls(child)
    colBtn:Show(); expBtn:Show()
    colBtn:SetScript("OnClick", function()
        for _, b in ipairs(all) do SetExpanded(b, false) end
        BNB.RefreshTagTree()
    end)
    expBtn:SetScript("OnClick", function()
        for _, b in ipairs(all) do SetExpanded(b, true) end
        BNB.RefreshTagTree()
    end)

    local totalH   = CTRL_H + 8   -- room for collapse/expand controls row (height + top pad + gap)
    local entryIdx = 0
    local hdrIdx   = 0

    local function RenderBucket(b)
        local expanded = IsExpanded(b)
        local notes = b.notes
        hdrIdx = hdrIdx + 1
        local hdr = GetOrCreateTagHeader(child, hdrIdx)
        hdr:SetPoint("TOPLEFT",  child, "TOPLEFT",  0, -totalH)
        hdr:SetPoint("TOPRIGHT", child, "TOPRIGHT", 0, -totalH)
        -- Arrow symbol: down when expanded, right when collapsed
        if hdr._arrowBtn then hdr._arrowBtn:SetSymbol(expanded and "down" or "right") end
        hdr._lbl:ClearAllPoints()
        hdr._lbl:SetPoint("RIGHT", hdr, "RIGHT", -40, 0)
        if folderView then
            hdr._pic:SetTexture(BNB.Folders.Art(expanded, #notes > 0))
            hdr._pic:Show()
            hdr._lbl:SetPoint("LEFT", hdr._pic, "RIGHT", 4, 0)
        else
            hdr._pic:Hide()
            hdr._lbl:SetPoint("LEFT", hdr._arrowBtn, "RIGHT", 4, 0)
        end
        hdr._lbl:SetText(b.label)
        hdr._count:SetText("(" .. #notes .. ")")
        -- A drop target in the folder view (UI/NoteList.lua HeaderUnderCursor):
        -- a folder's id, false = No folder (out of folders), nil = none
        if folderView and b.folder then hdr._dropFolder = b.key
        elseif folderView and b.key == NO_FOLDER then hdr._dropFolder = false
        else hdr._dropFolder = nil end
        hdr:SetScript("OnClick", function(_, button)
            -- A folder's right-click is its menu, as in the list
            if button == "RightButton" then
                if b.folder and BNB.ShowFolderMenu then BNB.ShowFolderMenu(hdr, b.key) end
                if b.sys and BNB.ShowSystemFolderMenu then BNB.ShowSystemFolderMenu(hdr, b.key) end
                return
            end
            SetExpanded(b, not expanded)
            BNB.RefreshTagTree()
        end)
        hdr:Show()
        totalH = totalH + HEADER_H

        if expanded then
            for _, note in ipairs(notes) do
                entryIdx = entryIdx + 1
                if not entries[entryIdx] then
                    entries[entryIdx] = BNB._createListEntry(child)
                end
                local btn = entries[entryIdx]
                btn:SetHeight(ENTRY_H)
                btn:SetPoint("TOPLEFT",  child, "TOPLEFT",  ENTRY_INDENT, -totalH)
                btn:SetPoint("TOPRIGHT", child, "TOPRIGHT", 0,            -totalH)
                btn._sys = note.system   -- a system note's row (ALL-511): no drag, its own menu
                btn._section = nil       -- not a list section: never filed by a drop between rows
                BNB.PopulateListEntry(btn, note, note.id == selID, false)
                -- Override OnClick to respect tagTreeStayOpen setting
                -- Hook left-click for tagTreeStayOpen behaviour — once per entry.
                -- The original OnClick set by CreateListEntry handles right-click,
                -- multi-select, double-click etc. — SetScript would break all that.
                if not db.tagTreeStayOpen and not btn._tagTreeHooked then
                    btn._tagTreeHooked = true
                    btn:HookScript("OnClick", function(self, mouseBtn)
                        if mouseBtn == "LeftButton" and not DB().tagTreeStayOpen then
                            BNB.SetTagTreeMode(false)
                        end
                    end)
                end
                btn:Show()
                totalH = totalH + ENTRY_H
            end
        end
    end

    for _, b in ipairs(all) do RenderBucket(b) end

    -- Hide any unused headers
    for i = hdrIdx + 1, #_tagHeaders do
        _tagHeaders[i]:Hide()
    end

    child:SetHeight(math.max(totalH, 1))
    if BNB._listScrollFrame and BNB._listScrollFrame.UpdateScrollbar then
        BNB._listScrollFrame:UpdateScrollbar()
    end
end

-- Dragging notes in the folder view (Dukul, 2026-10-19): every header is
-- drawn closed while a note is carried, so the folders fit on screen as
-- targets; the saved open / closed states are untouched and come back on drop
function BNB.TagTreeDragCollapse(on)
    on = on and true or false
    if _dragCollapsed == on then return end
    _dragCollapsed = on
    BNB.RefreshTagTree()
end

-- The shown folder view header under the pointer and its drop value (a
-- folder id, or false = No folder), or nil
function BNB.TagTreeDropHeader()
    for _, hdr in ipairs(_tagHeaders) do
        if hdr:IsShown() and hdr._dropFolder ~= nil and hdr:IsMouseOver() then
            return hdr, hdr._dropFolder
        end
    end
end

--------------------------------------------------------------------------------
-- Mode toggle
--------------------------------------------------------------------------------
-- source = "folders" for the folder view, nil for the tag tree (ALL-510 S4);
-- only read when switching on
function BNB.SetTagTreeMode(enabled, source)
    local db = DB()
    if not db then return end
    -- No folder view while the Folders module is off (ALL-514)
    if enabled and source == "folders" and not BNB.FoldersEnabled() then return end

    db.tagTreeMode = enabled
    if enabled then db.treeSource = (source == "folders") and "folders" or nil end

    -- Sync both buttons' look
    if BNB._syncTreeBtns then BNB._syncTreeBtns() end

    -- Disable/enable sort dropdown
    if BNB.SetSortEnabled then
        BNB.SetSortEnabled(not enabled)
    end

    if enabled then
        -- Apply start-expanded preference (tags and No folder; a folder
        -- keeps its own saved state)
        _noFolderOpen = nil
        if db.tagTreeStartExpanded then
            _expandedTags = {}
            local tagList = BNB.GetAllTags()
            for _, entry in ipairs(tagList) do
                _expandedTags[entry.tag] = true
            end
            _expandedTags[UNTAGGED] = true
        else
            _expandedTags = {}
        end
        BNB.RefreshTagTree()
    else
        -- Hide tag headers and controls before switching back to list
        for _, hdr in ipairs(_tagHeaders) do hdr:Hide() end
        if _collapseAllBtn then _collapseAllBtn:Hide() end
        if _expandAllBtn   then _expandAllBtn:Hide()   end
        BNB.RefreshNoteList()
    end
end

-- On addon load: restore sort enabled state to match saved tagTreeMode
-- (called from Initialize.lua after DB is ready)
function BNB.InitTagTree()
    local db = DB()
    if not db then return end
    if db.tagTreeMode then
        if BNB._syncTreeBtns then BNB._syncTreeBtns() end
        if BNB.SetSortEnabled then BNB.SetSortEnabled(false) end
    end
end

-- A tag's colour changed (ALL-106): the headers take it
BNB.RegisterMessage("TagTree", "TagColorChanged", function()
    local db = DB()
    if db and db.tagTreeMode and not BNB._listCollapsed then
        BNB.Debounce("tagTreeColour", 0, BNB.RefreshTagTree)
    end
end)

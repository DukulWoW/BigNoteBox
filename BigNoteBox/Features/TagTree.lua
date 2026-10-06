-- BigNoteBox Features/TagTree.lua
-- Tag tree view: groups notes by tag in the note list scroll area.
-- Activated via the tag tree button left of the search bar.
-- Shares the scroll frame / scroll child / listEntries pool with NoteList.lua.

local BNB = BigNoteBox
local L   = BNB.L

--------------------------------------------------------------------------------
-- Module state
--------------------------------------------------------------------------------
local _expandedTags  = {}   -- { [tagName] = true } when that header is expanded
local _tagHeaders    = {}   -- reused header frames { btn, arrow, label, count }
local _collapseAllBtn, _expandAllBtn  -- pinned control buttons inside scroll child

local HEADER_H   = 24
local ENTRY_INDENT = 8      -- px left indent for notes under a tag header
local PAD_L      = 8
local BTN_SZ     = 18   -- arrow button size, matches AlarmWindow calendar nav buttons

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------
local function DB()  return BigNoteBoxDB          end

-- Returns ordered list of { tag, notes[] } sorted A-Z.
-- "notes" is the filtered set for that tag (respects text + fav filter).
-- Also returns a separate list of untagged notes.
local function BuildTagBuckets()
    local tagIndex = BNB.TagIndex()

    -- Get filtered notes using NoteList current filter state
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

    -- Collect all known tags A-Z
    local tagList = BNB.GetAllTags()  -- { {tag, count} } already sorted A-Z

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
        table.sort(notes, function(a, b)
            return BNB.NoteTitleKey(a) < BNB.NoteTitleKey(b)
        end)
        if #notes > 0 then
            buckets[#buckets + 1] = { tag = tag, notes = notes }
        end
    end

    -- Untagged bucket
    for _, note in pairs(filteredSet) do
        if not note.tags or #note.tags == 0 then
            untagged[#untagged + 1] = note
        end
    end
    table.sort(untagged, function(a, b)
        return BNB.NoteTitleKey(a) < BNB.NoteTitleKey(b)
    end)

    return buckets, untagged
end

--------------------------------------------------------------------------------
-- Tag header widget pool
--------------------------------------------------------------------------------
local function GetOrCreateTagHeader(child, idx)
    if _tagHeaders[idx] then return _tagHeaders[idx] end

    local btn = CreateFrame("Button", nil, child)
    btn:SetHeight(HEADER_H)
    btn:RegisterForClicks("LeftButtonUp")

    local hiBg = btn:CreateTexture(nil, "HIGHLIGHT")
    hiBg:SetAllPoints(); hiBg:SetColorTexture(1, 1, 1, 0.05)

    -- Arrow: icon button ("right" = collapsed, "down" = expanded), 18x18 like
    -- the AlarmWindow calendar arrows. Clicks go to the parent header button.
    local arrowBtn = BNB.CreateIconButton(btn, BTN_SZ, "right",
        { onClick = function() btn:Click() end })
    arrowBtn:SetPoint("LEFT", btn, "LEFT", PAD_L, 0)
    btn._arrowBtn  = arrowBtn

    local lbl = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    lbl:SetPoint("LEFT", arrowBtn, "RIGHT", 4, 0)
    lbl:SetPoint("RIGHT", btn, "RIGHT", -40, 0)
    lbl:SetJustifyH("LEFT")
    lbl:SetTextColor(1, 1, 1, 1)
    btn._lbl = lbl

    local countLbl = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
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
    local buckets, untagged = BuildTagBuckets()

    -- Collapse/expand controls
    local colBtn, expBtn = GetOrCreateCollapseControls(child)
    colBtn:Show(); expBtn:Show()
    colBtn:SetScript("OnClick", function()
        _expandedTags = {}
        BNB.RefreshTagTree()
    end)
    expBtn:SetScript("OnClick", function()
        for _, b in ipairs(buckets) do _expandedTags[b.tag] = true end
        _expandedTags["__untagged__"] = true
        BNB.RefreshTagTree()
    end)

    local totalH   = CTRL_H + 8   -- room for collapse/expand controls row (height + top pad + gap)
    local entryIdx = 0
    local hdrIdx   = 0

    local function RenderBucket(tag, notes, isUntagged)
        local expanded = _expandedTags[tag] or false
        hdrIdx = hdrIdx + 1
        local hdr = GetOrCreateTagHeader(child, hdrIdx)
        hdr:SetPoint("TOPLEFT",  child, "TOPLEFT",  0, -totalH)
        hdr:SetPoint("TOPRIGHT", child, "TOPRIGHT", 0, -totalH)
        -- Arrow symbol: down when expanded, right when collapsed
        if hdr._arrowBtn then hdr._arrowBtn:SetSymbol(expanded and "down" or "right") end
        hdr._lbl:SetText(isUntagged and ("|cff888888" .. L["TAGTREE_UNTAGGED"] .. "|r") or tag)
        hdr._count:SetText("(" .. #notes .. ")")
        hdr:SetScript("OnClick", function()
            if expanded then
                _expandedTags[tag] = nil
            else
                _expandedTags[tag] = true
            end
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

    for _, bucket in ipairs(buckets) do
        RenderBucket(bucket.tag, bucket.notes, false)
    end

    if #untagged > 0 then
        RenderBucket("__untagged__", untagged, true)
    end

    -- Hide any unused headers
    for i = hdrIdx + 1, #_tagHeaders do
        _tagHeaders[i]:Hide()
    end

    child:SetHeight(math.max(totalH, 1))
    if BNB._listScrollFrame and BNB._listScrollFrame.UpdateScrollbar then
        BNB._listScrollFrame:UpdateScrollbar()
    end
end

--------------------------------------------------------------------------------
-- Mode toggle
--------------------------------------------------------------------------------
function BNB.SetTagTreeMode(enabled)
    local db = DB()
    if not db then return end

    db.tagTreeMode = enabled

    -- Sync button visual (uses the setter that also updates the closure local)
    if BNB._setTagTreeBtnActive then BNB._setTagTreeBtnActive(enabled) end

    -- Disable/enable sort dropdown
    if BNB.SetSortEnabled then
        BNB.SetSortEnabled(not enabled)
    end

    if enabled then
        -- Apply start-expanded preference
        if db.tagTreeStartExpanded then
            _expandedTags = {}
            local tagList = BNB.GetAllTags()
            for _, entry in ipairs(tagList) do
                _expandedTags[entry.tag] = true
            end
            _expandedTags["__untagged__"] = true
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
        if BNB._setTagTreeBtnActive then BNB._setTagTreeBtnActive(true) end
        if BNB.SetSortEnabled then BNB.SetSortEnabled(false) end
    end
end

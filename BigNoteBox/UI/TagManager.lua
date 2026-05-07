-- BigNoteBox UI/TagManager.lua — Tag Manager
--
-- Opens to the right of the main window.
-- Accordion: click a tag header to expand/collapse its notes.
-- Only one tag open at a time; clicking the open tag closes it.
-- Per-tag: Rename (inline) | Delete All.

local BNB = BigNoteBox
local L   = BNB.L

local TM_W        = 380
local PAD         = 14
local SCROLL_PAD  = PAD + 20   -- right inset: scrollbar clears the border
local SCROLL_LPAD = PAD + 4    -- left inset: tiny air gap on left
local TAG_ROW_H   = 30
local NOTE_ROW_H  = 24
local ROW_GAP     = 2
local ARROW_W     = 16
local BTN_W       = 70         -- wider buttons for breathing room
local BTN_H       = 20

local _tmFrame     = nil
local _scrollChild = nil
local _scrollFrame = nil
local _emptyLbl    = nil
local _openTag     = nil

local _tagPool  = {}
local _notePool = {}

-- Multi-select state
local _multiMode   = false
local _multiSel    = {}   -- { [tag] = true }
local _selectBtn   = nil
local _selAllBtn   = nil
local _delSelBtn   = nil

-- Content width inside the scroll child (for hitBtn sizing)
local function ContentW()
    if _scrollFrame then return _scrollFrame:GetWidth() end
    return TM_W - SCROLL_LPAD - SCROLL_PAD
end

--------------------------------------------------------------------------------
-- TAG HEADER ROW POOL
-- hitBtn covers only the left "clickable" region (arrow+name+count).
-- Rename/Delete sit to the right and are NOT covered by hitBtn.
--------------------------------------------------------------------------------
local function GetTagRow(idx)
    if _tagPool[idx] then return _tagPool[idx] end

    local f = CreateFrame("Frame", nil, _scrollChild)
    f:SetHeight(TAG_ROW_H)

    -- Rename button (right-most of the two action btns)
    local renBtn = BNB.CreateButton(nil, f, L["TAG_MGR_RENAME"], BTN_W, BTN_H)
    renBtn:SetPoint("RIGHT", f, "RIGHT", 0, 0)

    -- Delete button (left of rename)
    local delBtn = BNB.CreateButton(nil, f, L["TAG_MGR_DELETE"], BTN_W, BTN_H)
    delBtn:SetPoint("RIGHT", renBtn, "LEFT", -4, 0)

    -- hitBtn covers everything LEFT of the delete button — so the action
    -- buttons are never occluded by it and will receive their own clicks.
    local hitBtn = CreateFrame("Button", nil, f)
    hitBtn:SetPoint("TOPLEFT",    f,      "TOPLEFT",    0, 0)
    hitBtn:SetPoint("BOTTOMRIGHT",delBtn, "BOTTOMLEFT", -2, 0)
    local hiTx = hitBtn:CreateTexture(nil, "HIGHLIGHT")
    hiTx:SetAllPoints()
    hiTx:SetColorTexture(1, 1, 1, 0.06)

    -- Selection highlight (shown when row is ticked in multi-select mode)
    local selHi = f:CreateTexture(nil, "BACKGROUND")
    selHi:SetAllPoints()
    selHi:SetColorTexture(0.2, 0.5, 0.8, 0.25)
    selHi:Hide()

    -- Arrow
    local arrowLbl = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    arrowLbl:SetPoint("LEFT", f, "LEFT", 2, 0)
    arrowLbl:SetWidth(ARROW_W)
    arrowLbl:SetJustifyH("LEFT")
    arrowLbl:SetTextColor(0.7, 0.7, 0.7)

    -- Tag name
    local nameLbl = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    nameLbl:SetPoint("LEFT", f, "LEFT", ARROW_W, 0)
    nameLbl:SetPoint("RIGHT", delBtn, "LEFT", -8, 0)
    nameLbl:SetJustifyH("LEFT")
    nameLbl:SetTextColor(1, 0.82, 0)
    nameLbl:SetWordWrap(false)

    -- Count — sits to the right of the name, capped before the buttons
    local countLbl = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    countLbl:SetPoint("RIGHT", delBtn, "LEFT", -8, 0)
    countLbl:SetJustifyH("RIGHT")
    countLbl:SetTextColor(0.5, 0.5, 0.5)

    -- OK / Cancel sit at the far right (same position as Rename/Delete)
    -- so clicking Rename → buttons stay in the same spot.
    local okBtn = BNB.CreateButton(nil, f, "OK", 38, BTN_H)
    okBtn:SetPoint("RIGHT", f, "RIGHT", 0, 0)
    okBtn:Hide()

    local cancelBtn = BNB.CreateButton(nil, f, L["CANCEL"], 50, BTN_H)
    cancelBtn:SetPoint("RIGHT", okBtn, "LEFT", -4, 0)
    cancelBtn:Hide()

    -- Inline rename input — styled like the "Search icons..." bar in NoteConfig.
    -- Container uses BackdropDark; EditBox is inset 4px inside it.
    local ebBg = BNB.CreateBackdropFrame("Frame", nil, f)
    BNB.SetBackdropDark(ebBg)
    ebBg:SetPoint("LEFT",  f,        "LEFT",       ARROW_W, 0)
    ebBg:SetPoint("RIGHT", cancelBtn, "LEFT",      -6,      0)
    ebBg:SetHeight(22)
    ebBg:Hide()

    local eb = CreateFrame("EditBox", nil, ebBg)
    eb:SetPoint("TOPLEFT",     ebBg, "TOPLEFT",     4,  0)
    eb:SetPoint("BOTTOMRIGHT", ebBg, "BOTTOMRIGHT", -4, 0)
    eb:SetFontObject("GameFontNormal")
    eb:SetAutoFocus(false)
    eb:SetMaxLetters(20)
    BNB.AddPlaceholder(eb, L["TAG_MGR_RENAME_HINT"], 0.4, 0.4, 0.4)
    eb:Hide()

    local row = {
        frame = f, hitBtn = hitBtn, arrowLbl = arrowLbl, selHi = selHi,
        nameLbl = nameLbl, countLbl = countLbl,
        renBtn = renBtn, delBtn = delBtn,
        ebBg = ebBg, eb = eb, okBtn = okBtn, cancelBtn = cancelBtn,
    }
    _tagPool[idx] = row
    return row
end

--------------------------------------------------------------------------------
-- NOTE SUB-ROW POOL
--------------------------------------------------------------------------------
local DEFAULT_ICON = "Interface\\Icons\\INV_Misc_Note_06"

local function GetNoteRow(idx)
    if _notePool[idx] then return _notePool[idx] end

    local f = CreateFrame("Frame", nil, _scrollChild)
    f:SetHeight(NOTE_ROW_H)

    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0.15)

    -- Small note icon
    local iconTex = f:CreateTexture(nil, "ARTWORK")
    iconTex:SetSize(16, 16)
    iconTex:SetPoint("LEFT", f, "LEFT", ARROW_W + 6, 0)
    iconTex:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    -- Note title
    local titleLbl = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    titleLbl:SetPoint("LEFT",  f, "LEFT",  ARROW_W + 6 + 16 + 5, 0)
    titleLbl:SetPoint("RIGHT", f, "RIGHT", 62, 0)
    titleLbl:SetJustifyH("LEFT")
    titleLbl:SetWordWrap(false)

    -- Go to button
    local goBtn = BNB.CreateButton(nil, f, "Go to", 54, 18)
    goBtn:SetPoint("RIGHT", f, "RIGHT", 0, 0)

    local row = { frame = f, iconTex = iconTex, titleLbl = titleLbl, goBtn = goBtn }
    _notePool[idx] = row
    return row
end

--------------------------------------------------------------------------------
-- POPULATE
--------------------------------------------------------------------------------
local UpdateDelSelBtn
local SetMultiMode
local PopulateTagManager

UpdateDelSelBtn = function()
    if not _delSelBtn then return end
    local n = 0
    for _ in pairs(_multiSel) do n = n + 1 end
    _delSelBtn:SetEnabled(n > 0)
end

SetMultiMode = function(enabled)
    _multiMode = enabled
    _multiSel  = {}
    if _selectBtn then
        _selectBtn:SetText(enabled and "Cancel" or "Select")
        _selectBtn:SetScript("OnClick", function()
            SetMultiMode(not enabled)
        end)
    end
    if _selAllBtn then _selAllBtn:SetShown(enabled)                              end
    if _delSelBtn then _delSelBtn:SetShown(enabled); _delSelBtn:SetEnabled(false) end
    PopulateTagManager()
end

PopulateTagManager = function()
    if not _tmFrame or not _scrollChild then return end

    for _, r in ipairs(_tagPool)  do r.frame:Hide() end
    for _, r in ipairs(_notePool) do r.frame:Hide() end

    local tags = BNB.GetAllTags()
    if _emptyLbl then _emptyLbl:SetShown(#tags == 0) end

    local yOffset = 0
    local tagIdx  = 0
    local noteIdx = 0

    for _, entry in ipairs(tags) do
        local tag       = entry.tag
        local count     = entry.count
        local isOpen    = (_openTag == tag)
        local capturedTag = tag   -- stable upvalue for all closures in this iteration

        tagIdx = tagIdx + 1
        local row = GetTagRow(tagIdx)

        row.frame:ClearAllPoints()
        row.frame:SetPoint("TOPLEFT",  _scrollChild, "TOPLEFT",  0, -yOffset)
        row.frame:SetPoint("TOPRIGHT", _scrollChild, "TOPRIGHT", 0, -yOffset)
        row.frame:Show()
        yOffset = yOffset + TAG_ROW_H + ROW_GAP

        -- Reset rename UI
        row.eb:Hide(); row.ebBg:Hide(); row.okBtn:Hide(); row.cancelBtn:Hide()
        row.nameLbl:Show(); row.countLbl:Show()
        row.renBtn:Show(); row.delBtn:Show(); row.hitBtn:Show()

        row.arrowLbl:SetText(isOpen
            and "|TInterface\\Buttons\\Arrow-Down-Up:12:12|t"
            or  "|TInterface\\Buttons\\Arrow-Right-Up:12:12|t")
        row.nameLbl:SetText(tag)
        row.countLbl:SetText(string.format(L["TAG_MGR_COUNT"], count))

        -- Selection highlight
        row.selHi:SetShown(_multiMode and _multiSel[tag] == true)

        -- Expand / collapse (normal) or toggle selection (multi-select)
        row.hitBtn:SetScript("OnClick", function()
            if _multiMode then
                if _multiSel[tag] then _multiSel[tag] = nil
                else                   _multiSel[tag] = true end
                row.selHi:SetShown(_multiSel[tag] == true)
                UpdateDelSelBtn()
            else
                _openTag = (_openTag == capturedTag) and nil or capturedTag
                PopulateTagManager()
            end
        end)

        -- Rename
        row.renBtn:SetScript("OnClick", function()
            row.nameLbl:Hide(); row.countLbl:Hide()
            row.renBtn:Hide(); row.delBtn:Hide(); row.hitBtn:Hide()
            row.ebBg:Show(); row.eb:Show(); row.okBtn:Show(); row.cancelBtn:Show()
            row.eb:SetText("")
            BNB.AddPlaceholder(row.eb, L["TAG_MGR_RENAME_HINT"], 0.4, 0.4, 0.4)
            row.eb:SetFocus()
        end)

        local function CancelRename()
            row.eb:Hide(); row.ebBg:Hide(); row.okBtn:Hide(); row.cancelBtn:Hide()
            row.nameLbl:Show(); row.countLbl:Show()
            row.renBtn:Show(); row.delBtn:Show(); row.hitBtn:Show()
            row.eb:ClearFocus()
        end

        local function CommitRename()
            local newTag = row.eb._showingPlaceholder and ""
                or (row.eb:GetText():match("^%s*(.-)%s*$") or "")
            if newTag == "" or newTag == capturedTag then CancelRename(); return end
            if _openTag == capturedTag then _openTag = newTag end
            BNB.RenameTag(capturedTag, newTag)
            CancelRename()
            PopulateTagManager()
            if BNB.RefreshNoteList then BNB.RefreshNoteList() end
            if BNB.RefreshTagStrip then BNB.RefreshTagStrip() end
        end

        row.okBtn:SetScript("OnClick",          CommitRename)
        row.eb:SetScript("OnEnterPressed",       CommitRename)
        row.eb:SetScript("OnTabPressed",         CommitRename)
        row.eb:SetScript("OnEscapePressed", function() CancelRename() end)
        row.cancelBtn:SetScript("OnClick",  function() CancelRename() end)

        -- Delete All
        row.delBtn:SetScript("OnClick", function()
            if _openTag == capturedTag then _openTag = nil end
            StaticPopupDialogs["BNB_DELETE_TAG"] = {
                text           = string.format(L["TAG_MGR_DELETE_CONFIRM"], capturedTag, count),
                button1        = L["DELETE"],
                button2        = L["CANCEL"],
                OnAccept       = function()
                    BNB.DeleteTag(capturedTag)
                    PopulateTagManager()
                    if BNB.RefreshNoteList then BNB.RefreshNoteList() end
                    if BNB.RefreshTagStrip then BNB.RefreshTagStrip() end
                end,
                timeout        = 0,
                whileDead      = true,
                hideOnEscape   = true,
                preferredIndex = 3,
            }
            StaticPopup_Show("BNB_DELETE_TAG")
        end)

        -- Note sub-rows (accordion body)
        if isOpen then
            local tidx = BigNoteBoxDB and BigNoteBoxDB.tagIndex
            local noteIDs = {}
            if tidx and tidx[tag] then
                for id in pairs(tidx[tag]) do noteIDs[#noteIDs + 1] = id end
            end
            table.sort(noteIDs, function(a, b)
                local na = BNB.GetNote(a); local nb = BNB.GetNote(b)
                local ta = (na and na.title ~= "" and na.title) or L["UNTITLED"]
                local tb = (nb and nb.title ~= "" and nb.title) or L["UNTITLED"]
                return ta:lower() < tb:lower()
            end)
            for _, noteID in ipairs(noteIDs) do
                local note = BNB.GetNote(noteID)
                if note then
                    noteIdx = noteIdx + 1
                    local nrow = GetNoteRow(noteIdx)
                    nrow.frame:ClearAllPoints()
                    nrow.frame:SetPoint("TOPLEFT",  _scrollChild, "TOPLEFT",  0, -yOffset)
                    nrow.frame:SetPoint("TOPRIGHT", _scrollChild, "TOPRIGHT", 0, -yOffset)
                    nrow.frame:Show()
                    yOffset = yOffset + NOTE_ROW_H + ROW_GAP

                    -- Icon
                    local iconPath = (note.icon and note.icon ~= "") and note.icon or DEFAULT_ICON
                    nrow.iconTex:SetTexture(iconPath)

                    -- Title with note's title colour
                    local title = (note.title ~= "" and note.title) or L["UNTITLED"]
                    nrow.titleLbl:SetText(title)
                    local tc = note.titleColor
                    if tc then
                        nrow.titleLbl:SetTextColor(tc.r or tc[1] or 0.85, tc.g or tc[2] or 0.85, tc.b or tc[3] or 0.85)
                    else
                        nrow.titleLbl:SetTextColor(0.85, 0.85, 0.85)
                    end

                    local capturedID = noteID
                    nrow.goBtn:SetScript("OnClick", function()
                        if BNB.mainFrame then
                            BNB.mainFrame:Show()
                            if BNB.RefreshNoteList then BNB.RefreshNoteList() end
                            if BNB.SelectNote      then BNB.SelectNote(capturedID) end
                        end
                    end)
                end
            end
        end
    end

    _scrollChild:SetHeight(math.max(1, yOffset))
    if _scrollFrame and _scrollFrame.UpdateScrollbar then
        _scrollFrame:UpdateScrollbar()
    end
end

--------------------------------------------------------------------------------
-- BUILD WINDOW
--------------------------------------------------------------------------------
local function BuildTagManager()
    if _tmFrame then return _tmFrame end

    local f = CreateFrame("Frame", "BigNoteBoxTagManagerFrame", UIParent, "ButtonFrameTemplate")
    f:SetSize(TM_W, 460)
    f:SetFrameStrata("DIALOG")
    f:SetToplevel(true)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:SetClampedToScreen(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) self:StartMoving() end)
    f:SetScript("OnDragStop",  function(self) self:StopMovingOrSizing() end)

    ButtonFrameTemplate_HidePortrait(f)
    ButtonFrameTemplate_HideButtonBar(f)
    if f.Inset then f.Inset:Hide() end
    f:SetTitle(L["TAG_MGR_TITLE"])

    if f.CloseButton then
        f.CloseButton:SetScript("OnClick", function() f:Hide() end)
    end

    local tipLbl = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    tipLbl:SetPoint("TOPLEFT",  f, "TOPLEFT",  PAD,  -76)
    tipLbl:SetPoint("TOPRIGHT", f, "TOPRIGHT", -PAD, -76)
    tipLbl:SetJustifyH("LEFT")
    tipLbl:SetTextColor(0.5, 0.5, 0.5)
    tipLbl:SetText(L["TAG_MGR_MERGE_NOTE"])
    tipLbl:SetWordWrap(true)

    -- ── Select strip (between title bar and tip) ──────────────────────────────
    local selectBtn = BNB.CreateButton(nil, f, "Select", 68, 22)
    selectBtn:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, -43)
    selectBtn:SetScript("OnClick", function() SetMultiMode(true) end)
    _selectBtn = selectBtn

    local selAllBtn = BNB.CreateButton(nil, f, "Select all", 80, 22)
    selAllBtn:SetPoint("LEFT", selectBtn, "RIGHT", 6, 0)
    selAllBtn:SetScript("OnClick", function()
        local tags = BNB.GetAllTags()
        for _, entry in ipairs(tags) do
            _multiSel[entry.tag] = true
        end
        UpdateDelSelBtn()
        PopulateTagManager()
    end)
    selAllBtn:Hide()
    _selAllBtn = selAllBtn

    local delSelBtn = BNB.CreateButton(nil, f, "|cffff4444Delete|r", 68, 22)
    delSelBtn:SetPoint("LEFT", selAllBtn, "RIGHT", 6, 0)
    delSelBtn:SetEnabled(false)
    delSelBtn:SetScript("OnClick", function()
        local selTags = {}
        for tag in pairs(_multiSel) do selTags[#selTags + 1] = tag end
        local n = #selTags
        if n == 0 then return end
        StaticPopupDialogs["BNB_DELETE_SEL_TAGS"] = {
            text           = string.format("Remove %d tag(s) from all notes? This cannot be undone.", n),
            button1        = L["DELETE"],
            button2        = L["CANCEL"],
            OnAccept       = function()
                for _, tag in ipairs(selTags) do
                    BNB.DeleteTag(tag)
                end
                SetMultiMode(false)
                if BNB.RefreshNoteList then BNB.RefreshNoteList() end
                if BNB.RefreshTagStrip then BNB.RefreshTagStrip() end
            end,
            timeout        = 0,
            whileDead      = true,
            hideOnEscape   = true,
            preferredIndex = 3,
        }
        StaticPopup_Show("BNB_DELETE_SEL_TAGS")
    end)
    delSelBtn:Hide()
    _delSelBtn = delSelBtn

    local sf, child = BNB.CreateSmartScrollFrame("BigNoteBoxTagManagerScroll", f)
    sf:SetPoint("TOPLEFT",     f, "TOPLEFT",     SCROLL_LPAD,  -96)
    sf:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -SCROLL_PAD,   PAD)
    _scrollFrame = sf
    _scrollChild = child

    sf:SetScript("OnSizeChanged", function(self)
        child:SetWidth(self:GetWidth())
    end)

    local emptyLbl = child:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    emptyLbl:SetPoint("TOP", child, "TOP", 0, -40)
    emptyLbl:SetJustifyH("CENTER")
    emptyLbl:SetText(L["TAG_MGR_EMPTY"])
    emptyLbl:Hide()
    _emptyLbl = emptyLbl

    _tmFrame = f
    f:Hide()
    tinsert(UISpecialFrames, "BigNoteBoxTagManagerFrame")
    return f
end

local SK_TM_TITLE_H = 28

local function BuildTagManagerSkin()
    if _tmFrame then return _tmFrame end

    local f = BNB.CreateSkinFrame(UIParent, false, "BigNoteBoxTagManagerFrame", false)
    _G["BigNoteBoxTagManagerFrame"] = f
    f:SetSize(TM_W, 460)
    f:SetFrameStrata("DIALOG")
    f:SetToplevel(true)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:SetClampedToScreen(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) self:StartMoving() end)
    f:SetScript("OnDragStop",  function(self) self:StopMovingOrSizing() end)

    -- Title strip
    local titleBar = BNB.CreateSkinStrip(f, true, false)
    titleBar:SetPoint("TOPLEFT",  f, "TOPLEFT",  0, 0)
    titleBar:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
    titleBar:SetHeight(SK_TM_TITLE_H)
    titleBar:EnableMouse(true)
    titleBar:RegisterForDrag("LeftButton")
    titleBar:SetScript("OnDragStart", function() f:StartMoving() end)
    titleBar:SetScript("OnDragStop",  function() f:StopMovingOrSizing() end)

    local titleLbl = titleBar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    titleLbl:SetPoint("CENTER", titleBar, "CENTER", -12, 0)
    titleLbl:SetTextColor(1, 0.82, 0)
    titleLbl:SetText(L["TAG_MGR_TITLE"])

    local closeBtn = BNB.CreateSkinCloseButton(titleBar, function() f:Hide() end)
    closeBtn:SetPoint("RIGHT", titleBar, "RIGHT", -3, 0)

    -- Select strip (just below title bar)
    local SK_SEL_Y = -(SK_TM_TITLE_H + 8)

    local selectBtn = BNB.CreateButton(nil, f, "Select", 68, 22)
    selectBtn:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, SK_SEL_Y)
    selectBtn:SetScript("OnClick", function() SetMultiMode(true) end)
    _selectBtn = selectBtn

    local selAllBtn = BNB.CreateButton(nil, f, "Select all", 80, 22)
    selAllBtn:SetPoint("LEFT", selectBtn, "RIGHT", 6, 0)
    selAllBtn:SetScript("OnClick", function()
        local tags = BNB.GetAllTags()
        for _, entry in ipairs(tags) do
            _multiSel[entry.tag] = true
        end
        UpdateDelSelBtn()
        PopulateTagManager()
    end)
    selAllBtn:Hide()
    _selAllBtn = selAllBtn

    local delSelBtn = BNB.CreateButton(nil, f, "|cffff4444Delete|r", 68, 22)
    delSelBtn:SetPoint("LEFT", selAllBtn, "RIGHT", 6, 0)
    delSelBtn:SetEnabled(false)
    delSelBtn:SetScript("OnClick", function()
        local selTags = {}
        for tag in pairs(_multiSel) do selTags[#selTags + 1] = tag end
        local n = #selTags
        if n == 0 then return end
        StaticPopupDialogs["BNB_DELETE_SEL_TAGS"] = {
            text           = string.format("Remove %d tag(s) from all notes? This cannot be undone.", n),
            button1        = L["DELETE"],
            button2        = L["CANCEL"],
            OnAccept       = function()
                for _, tag in ipairs(selTags) do
                    BNB.DeleteTag(tag)
                end
                SetMultiMode(false)
                if BNB.RefreshNoteList then BNB.RefreshNoteList() end
                if BNB.RefreshTagStrip then BNB.RefreshTagStrip() end
            end,
            timeout        = 0,
            whileDead      = true,
            hideOnEscape   = true,
            preferredIndex = 3,
        }
        StaticPopup_Show("BNB_DELETE_SEL_TAGS")
    end)
    delSelBtn:Hide()
    _delSelBtn = delSelBtn

    -- Tip label (below select strip)
    local SK_TIP_Y = SK_SEL_Y - 26 - 4
    local tipLbl = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    tipLbl:SetPoint("TOPLEFT",  f, "TOPLEFT",  PAD,  SK_TIP_Y)
    tipLbl:SetPoint("TOPRIGHT", f, "TOPRIGHT", -PAD, SK_TIP_Y)
    tipLbl:SetJustifyH("LEFT")
    tipLbl:SetTextColor(0.5, 0.5, 0.5)
    tipLbl:SetText(L["TAG_MGR_MERGE_NOTE"])
    tipLbl:SetWordWrap(true)

    -- Scroll frame (below tip label)
    local SK_SCROLL_Y = SK_TIP_Y - 18 - 4
    local sf, child = BNB.CreateSmartScrollFrame("BigNoteBoxTagManagerScroll", f)
    sf:SetPoint("TOPLEFT",     f, "TOPLEFT",     SCROLL_LPAD,  SK_SCROLL_Y)
    sf:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -SCROLL_PAD,  PAD)
    _scrollFrame = sf
    _scrollChild = child

    sf:SetScript("OnSizeChanged", function(self)
        child:SetWidth(self:GetWidth())
    end)

    local emptyLbl = child:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    emptyLbl:SetPoint("TOP", child, "TOP", 0, -40)
    emptyLbl:SetJustifyH("CENTER")
    emptyLbl:SetText(L["TAG_MGR_EMPTY"])
    emptyLbl:Hide()
    _emptyLbl = emptyLbl

    f:SetScript("OnShow", function()
        if BNB.ApplyMainWindowSkin then BNB.ApplyMainWindowSkin() end
    end)

    _tmFrame = f
    f:Hide()
    tinsert(UISpecialFrames, "BigNoteBoxTagManagerFrame")
    return f
end

--------------------------------------------------------------------------------
-- PUBLIC API
--------------------------------------------------------------------------------
function BNB.ToggleTagManager()
    local f
    if BigNoteBoxDB and BigNoteBoxDB.skinMode then
        f = BuildTagManagerSkin()
    else
        f = BuildTagManager()
    end
    if f:IsShown() then
        f:Hide()
    else
        f:ClearAllPoints()
        if BNB.mainFrame then
            f:SetPoint("TOPLEFT", BNB.mainFrame, "TOPRIGHT", 8, 0)
        else
            f:SetPoint("CENTER", UIParent, "CENTER", 200, 0)
        end
        _openTag   = nil
        SetMultiMode(false)
        PopulateTagManager()
        f:Show()
        f:Raise()
    end
end

function BNB.RefreshTagManager()
    if _tmFrame and _tmFrame:IsShown() then
        PopulateTagManager()
    end
end

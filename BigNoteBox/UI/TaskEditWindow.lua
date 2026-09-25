-- BigNoteBox UI/TaskEditWindow.lua
-- Per-task configuration window.  ButtonFrameTemplate (normal) or skin frame.
-- Single scroll area -- no tabs.  Fields: text, reset type, situation.
--
-- Public API:
--   BNB.TaskEditWindow.Open(noteID, taskID, anchorFrame)
--   BNB.TaskEditWindow.Close()

local BNB = BigNoteBox
if not BNB then return end
local L = BNB.L

BNB.TaskEditWindow = BNB.TaskEditWindow or {}
local TW = BNB.TaskEditWindow

-- ---------------------------------------------------------------------------
-- LAYOUT
-- ---------------------------------------------------------------------------
local TW_W       = 264
local TW_H       = 340
local TW_PAD     = 12
local TW_CW      = 224   -- content width  (TW_W - 2*TW_PAD - scrollbar pad)
local TW_TOP_Y   = 32    -- below title bar (ButtonFrameTemplate, and the 28px skin strip + 4)
local TW_FOOT_H  = 38    -- static footer height (Save / Cancel)
local TW_ROW     = 22
local TW_GAP     = 8
local TW_LBL     = 14
local TW_SECT_GAP = 12

local ASSETS = "Interface/AddOns/BigNoteBox/Assets/"

-- ---------------------------------------------------------------------------
-- STATE
-- ---------------------------------------------------------------------------
local _frame        = nil
local _noteID       = nil
local _taskID       = nil
local _isDirty      = false
local _isPopulating = false
local _isGlobal     = false  -- true when editing note-level task defaults

-- Widget refs
local _textEB, _resetDD, _sitTypeDD, _sitValueRow, _sitValueEb
local _sitUseCurBtn, _sitBrowseBtn, _sitClearBtn
local _saveBtn

-- Situation state
local _selSitType = "none"
local _pendingText = ""  -- backing store for task text label/editbox

-- ---------------------------------------------------------------------------
-- HELPERS
-- ---------------------------------------------------------------------------
local function MarkDirty()
    if _isPopulating then return end
    _isDirty = true
    if _saveBtn then _saveBtn:SetEnabled(true) end
end

-- Layout adapters over the shared pieces in UI/Widgets.lua (ALL-65.8)
local function MakeDD(parent, entries, initial, onChange, width)
    return BNB.CreateValueDropdown(parent, entries, initial, onChange, width or TW_CW, TW_ROW, MarkDirty)
end
local function SectionHdr(parent, text, y) return BNB.CreateSectionHeader(parent, text, y, TW_CW) end
local function SmallLbl(parent, text, y)   return BNB.CreateSmallLabel(parent, text, y, TW_CW) end

-- ---------------------------------------------------------------------------
-- SITUATION helpers
-- ---------------------------------------------------------------------------
local SIT_TYPES  = { "none", "zone", "subzone", "instance", "player" }
local SIT_LABELS = { L["TEW_SIT_NONE_GLOBAL"], L["TEW_SIT_ZONE"], L["TEW_SIT_SUBZONE"], L["TEW_SIT_INSTANCE"], L["TEW_SIT_PLAYER"] }

local function ParseSituation(raw)
    if not raw or raw == "" then return "none", "" end
    local t, v = raw:match("^([^:]+):(.+)$")
    if not t then return "none", "" end
    return t, v
end

-- ---------------------------------------------------------------------------
-- BUILD CONTENT (shared by normal and skin builders)
-- Receives the scroll content frame (ct) and save button.
-- ---------------------------------------------------------------------------
local function BuildContent(f, ct, saveBtn)
    local y = -4

    -- Section: Task text -- shows as a plain label; click to enter edit mode.
    -- Hidden in global mode (editing note-level defaults has no task text).
    local textSection = CreateFrame("Frame", nil, ct)
    textSection:SetPoint("TOPLEFT",  ct, "TOPLEFT",  0, y)
    textSection:SetPoint("TOPRIGHT", ct, "TOPRIGHT", 0, y)
    textSection:SetHeight(TW_LBL + 2 + TW_ROW + TW_SECT_GAP)
    SectionHdr(textSection, L["TEW_TASK_TEXT_HDR"], 0)

    local textLbl = textSection:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    textLbl:SetPoint("TOPLEFT",  textSection, "TOPLEFT",  6, -(TW_LBL + 2))
    textLbl:SetPoint("TOPRIGHT", textSection, "TOPRIGHT", -6, -(TW_LBL + 2))
    textLbl:SetHeight(TW_ROW)
    textLbl:SetJustifyH("LEFT")
    textLbl:SetWordWrap(false)
    textLbl:SetTextColor(0.9, 0.9, 0.9)

    local textEB = BNB.CreateBackdropFrame("EditBox", nil, textSection)
    textEB:SetSize(TW_CW, TW_ROW)
    textEB:SetPoint("TOPLEFT", textSection, "TOPLEFT", 0, -(TW_LBL + 2))
    textEB:SetAutoFocus(false); textEB:SetMaxLetters(500)
    textEB:SetFontObject("GameFontNormalSmall")
    textEB:SetScript("OnEnterPressed", function(self)
        local t = self:GetText()
        _pendingText = t
        textLbl:SetText(t ~= "" and t or L["TEW_EMPTY_TEXT"])
        self:Hide(); textLbl:Show()
        self:ClearFocus()
        MarkDirty()
    end)
    textEB:SetScript("OnEscapePressed", function(self)
        self:SetText(_pendingText)
        self:Hide(); textLbl:Show()
        self:ClearFocus()
    end)
    textEB:SetScript("OnEditFocusLost", function(self)
        if self:IsShown() then
            local t = self:GetText()
            _pendingText = t
            textLbl:SetText(t ~= "" and t or L["TEW_EMPTY_TEXT"])
            self:Hide(); textLbl:Show()
            MarkDirty()
        end
    end)
    textEB:Hide()
    _textEB = textEB
    _textEB._lbl = textLbl

    textLbl:SetScript("OnMouseDown", function()
        textLbl:Hide()
        textEB:SetText(_pendingText)
        textEB:Show()
        textEB:SetFocus()
    end)

    y = y - (TW_LBL + 2 + TW_ROW + TW_SECT_GAP)

    -- Section: Reset
    SectionHdr(ct, L["TEW_RESET_HDR"], y); y = y - TW_LBL - 2
    SmallLbl(ct, L["TEW_RESET_DESC"], y)
    y = y - TW_LBL - 4

    local resetEntriesTask = {
        { label = L["TEW_RESET_GLOBAL_OPT"],     value = "global" },
        { label = L["TASK_CTX_RESET_NONE"],      value = "none"   },
        { label = L["TASK_CTX_RESET_DAILY"],     value = "daily"  },
        { label = L["TASK_CTX_RESET_WEEKLY"],    value = "weekly" },
    }
    local resetEntriesGlobal = {
        { label = L["TASK_CTX_RESET_NONE"],   value = "none"   },
        { label = L["TASK_CTX_RESET_DAILY"],  value = "daily"  },
        { label = L["TASK_CTX_RESET_WEEKLY"], value = "weekly" },
    }
    local resetDD = MakeDD(ct, resetEntriesTask, "global", nil, TW_CW)
    resetDD:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
    resetDD:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(L["TEW_RESET_TIP_TITLE"], 1, 1, 1)
        GameTooltip:AddLine(L["TEW_RESET_TIP_GLOBAL"], 0.8, 0.8, 0.8, true)
        GameTooltip:AddLine(L["TEW_RESET_TIP_NONE"], 0.8, 0.8, 0.8, true)
        GameTooltip:AddLine(L["TEW_RESET_TIP_DAILY"], 0.8, 0.8, 0.8, true)
        GameTooltip:AddLine(L["TEW_RESET_TIP_WEEKLY"], 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    resetDD:SetScript("OnLeave", function() GameTooltip:Hide() end)
    _resetDD = resetDD
    resetDD._entriesTask   = resetEntriesTask
    resetDD._entriesGlobal = resetEntriesGlobal
    y = y - TW_ROW - TW_SECT_GAP

    -- Section: Situation
    SectionHdr(ct, L["TEW_SITUATION_HDR"], y); y = y - TW_LBL - 2
    SmallLbl(ct, L["TEW_SITUATION_DESC"], y)
    y = y - TW_LBL - 4

    local sitEntriesTask = {}
    for i, label in ipairs(SIT_LABELS) do
        sitEntriesTask[i] = { label = label, value = SIT_TYPES[i] }
    end
    local sitEntriesGlobal = {}
    for i = 1, #SIT_TYPES do
        local lbl2 = (i == 1) and L["TEW_SIT_NONE"] or SIT_LABELS[i]
        sitEntriesGlobal[i] = { label = lbl2, value = SIT_TYPES[i] }
    end

    local function OnSitTypeChanged(v)
        _selSitType = v
        if v == "none" then
            if _sitValueRow then _sitValueRow:Hide() end
        else
            if _sitValueRow then
                _sitValueRow:Show()
                local labelStr = L["TEW_VAL_LBL_ZONE"]
                if v == "subzone"  then labelStr = L["TEW_VAL_LBL_SUBZONE"]
                elseif v == "instance" then labelStr = L["TEW_VAL_LBL_INSTANCE"]
                elseif v == "player"   then labelStr = L["TEW_VAL_LBL_PLAYER"] end
                _sitValueRow._lbl:SetText(labelStr)
                if v == "player" then
                    if _sitBrowseBtn then _sitBrowseBtn:Hide() end
                else
                    if _sitBrowseBtn then _sitBrowseBtn:Show() end
                end
            end
        end
    end

    local sitTypeDD = MakeDD(ct, sitEntriesTask, "none", OnSitTypeChanged, TW_CW)
    sitTypeDD:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
    sitTypeDD._entriesTask   = sitEntriesTask
    sitTypeDD._entriesGlobal = sitEntriesGlobal
    _sitTypeDD = sitTypeDD
    y = y - TW_ROW - TW_GAP

    local valueRow = CreateFrame("Frame", nil, ct)
    valueRow:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
    valueRow:SetWidth(TW_CW); valueRow:SetHeight(TW_ROW); valueRow:Hide()
    _sitValueRow = valueRow

    local valueLbl = valueRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    valueLbl:SetPoint("LEFT", valueRow, "LEFT", 0, 0)
    valueLbl:SetWidth(44); valueLbl:SetJustifyH("LEFT")
    valueLbl:SetText(L["TEW_VAL_LBL_ZONE"]); valueLbl:SetHeight(TW_ROW)
    valueRow._lbl = valueLbl

    local valueEb = BNB.CreateBackdropFrame("EditBox", nil, valueRow)
    valueEb:SetPoint("LEFT",  valueRow, "LEFT",  46, 0)
    valueEb:SetPoint("RIGHT", valueRow, "RIGHT", -28, 0)
    valueEb:SetHeight(TW_ROW - 4)
    valueEb:SetAutoFocus(false); valueEb:SetMaxLetters(200)
    valueEb:SetFontObject("GameFontNormalSmall")
    valueEb:SetTextInsets(4, 4, 0, 0)
    valueEb:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    valueEb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    valueEb:HookScript("OnTextChanged", function() MarkDirty() end)
    _sitValueEb = valueEb

    local browseBtn = CreateFrame("Button", nil, valueRow)
    browseBtn:SetSize(20, 20)
    browseBtn:SetPoint("RIGHT", valueRow, "RIGHT", 0, 0)
    local browseTx = browseBtn:CreateTexture(nil, "ARTWORK")
    browseTx:SetAllPoints()
    browseTx:SetTexture(ASSETS .. "Overlay/ov-situation")
    browseBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(L["TEW_BROWSE_TIP"], 1, 1, 1)
        GameTooltip:Show()
    end)
    browseBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    browseBtn:SetScript("OnClick", function()
        if BNB.ZonePicker and BNB.ZonePicker.Open then
            BNB.ZonePicker.Open(function(name)
                valueEb:SetText(name or "")
                MarkDirty()
            end, browseBtn)
        end
    end)
    _sitBrowseBtn = browseBtn
    y = y - TW_ROW - TW_GAP

    local useCurBtn = BNB.CreateButton(nil, ct, L["TEW_USE_CURRENT_BTN"], 90, 20)
    useCurBtn:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
    useCurBtn:SetScript("OnClick", function()
        local val = ""
        if _selSitType == "zone" then
            val = GetZoneText() or ""
        elseif _selSitType == "subzone" then
            val = GetSubZoneText and GetSubZoneText() or ""
        elseif _selSitType == "instance" then
            val = (GetInstanceInfo and select(1, GetInstanceInfo())) or GetRealZoneText() or ""
        elseif _selSitType == "player" then
            val = (BNB.UnitNameRealm("target")) or ""
        end
        if _sitValueEb then _sitValueEb:SetText(val) end
        MarkDirty()
    end)
    _sitUseCurBtn = useCurBtn

    local clrCurBtn = BNB.CreateButton(nil, ct, L["TEW_CLEAR_BTN"], 60, 20)
    clrCurBtn:SetPoint("LEFT", useCurBtn, "RIGHT", 6, 0)
    clrCurBtn:SetScript("OnClick", function()
        if _sitValueEb then _sitValueEb:SetText("") end
        if _sitTypeDD  then _sitTypeDD:SetSelected("none") end
        _selSitType = "none"
        if _sitValueRow then _sitValueRow:Hide() end
        MarkDirty()
    end)
    clrCurBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(L["TEW_CLEAR_TIP"], 1, 1, 1)
        GameTooltip:AddLine(L["TEW_CLEAR_TIP_SUB"], 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    clrCurBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    local function UpdateClrCur()
        local hasVal = _sitValueEb and _sitValueEb:GetText() ~= ""
        local hasSit = _selSitType and _selSitType ~= "none"
        clrCurBtn:SetEnabled(hasVal or hasSit)
    end
    if _sitValueEb then
        _sitValueEb:HookScript("OnTextChanged", function() UpdateClrCur() end)
    end
    clrCurBtn:SetEnabled(false)
    _sitClearBtn = clrCurBtn
    y = y - 24 - TW_GAP

    ct._contentH   = math.abs(y) + 8
    ct._textSection = textSection

    -- ── SAVE HANDLER ─────────────────────────────────────────────────────────
    saveBtn:SetScript("OnClick", function()
        local T = BNB.Task
        if not T or not _noteID then TW.Close(); return end

        if _isGlobal then
            local note = BNB.GetNote(_noteID)
            if not note then TW.Close(); return end
            -- Build changes table and use T.UpdateList so TasksChanged fires,
            -- keeping all subscribers (sticky note footer, etc.) in sync.
            local rv = _resetDD and _resetDD:GetSelected() or "none"
            local sv = _sitValueEb and _sitValueEb:GetText() or ""
            sv = sv:match("^%s*(.-)%s*$") or ""
            local changes = {}
            local clear   = {}
            if rv == "none" then
                clear[#clear+1] = "resetType"
                clear[#clear+1] = "resetEvery"
            else
                changes.resetType = rv
            end
            if _selSitType == "none" or sv == "" then
                clear[#clear+1] = "situation"
            else
                changes.situation = _selSitType .. ":" .. sv
            end
            if #clear > 0 then changes._clear = clear end
            T.UpdateList(_noteID, changes)
            if BNB.RefreshReferenceBox then BNB.RefreshReferenceBox() end
            TW.Close()
            return
        end

        if not _taskID then TW.Close(); return end
        local task = T.FindTask(_noteID, _taskID)
        if not task then TW.Close(); return end

        local newText = _pendingText or ""
        local changes = { text = newText }
        local clears  = {}

        local rv = _resetDD and _resetDD:GetSelected() or "global"
        if rv == "global" then
            clears[#clears + 1] = "resetType"
            clears[#clears + 1] = "resetEvery"
            clears[#clears + 1] = "lastReset"
        elseif rv == "none" then
            changes.resetType = "none"
            clears[#clears + 1] = "resetEvery"
            clears[#clears + 1] = "lastReset"
        else
            changes.resetType = rv
            clears[#clears + 1] = "lastReset"
        end

        local sv = _sitValueEb and _sitValueEb:GetText() or ""
        sv = sv:match("^%s*(.-)%s*$") or ""
        if _selSitType == "none" or sv == "" then
            clears[#clears + 1] = "situation"
        else
            changes.situation = _selSitType .. ":" .. sv
        end

        if #clears > 0 then changes._clear = clears end
        T.UpdateTask(_noteID, _taskID, changes)
        TW.Close()
    end)
end

-- ---------------------------------------------------------------------------
-- BUILD WINDOW -- chrome from BNB.CreateToolWindow (UI/ToolWindow.lua),
-- ButtonFrameTemplate or skin frame
-- ---------------------------------------------------------------------------
local function BuildWindow()
    if _frame then return _frame end

    local f, saveBtn, cancelBtn = BNB.CreateToolWindow({
        name = "BNBTaskEditWindow", w = TW_W, h = TW_H, title = L["TEW_TITLE"],
        pad = TW_PAD, cw = TW_CW, footH = TW_FOOT_H,
        btn1 = L["SAVE"], btn2 = L["CANCEL"],
        onClose = function() TW.Close() end,
        onHide  = function()
            _noteID = nil; _taskID = nil; _isDirty = false; _isPopulating = false
        end,
    })
    saveBtn:SetEnabled(false)
    _saveBtn = saveBtn
    cancelBtn:SetScript("OnClick", function() TW.Close() end)

    -- Scroll panel
    local sf, ct = BNB.CreateAutoScrollPanel(f, TW_CW, TW_CW + 20)
    sf:SetPoint("TOPLEFT",     f, "TOPLEFT",     TW_PAD, -TW_TOP_Y)
    sf:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -24,     TW_FOOT_H + 6)

    -- Content
    BuildContent(f, ct, saveBtn)
    f._ct = ct

    -- ESC handled by MainWindow.lua OnKeyDown
    _frame = f
    return f
end

-- ---------------------------------------------------------------------------
-- POPULATE
-- ---------------------------------------------------------------------------
local function PopulateGlobal(noteID)
    _isPopulating = true
    _isGlobal = true

    -- Swap dropdowns to global entries (no "None (Global)" option)
    if _resetDD and _resetDD._entriesGlobal then
        _resetDD:SetSelected("none")  -- will be overwritten below
        -- Rebuild MakeDD isn't possible post-build, but we can update _selected
        -- and the display. We stored entries on the dd object.
        if _resetDD._dd then
            _resetDD._dd._selected = "none"
        end
    end
    if _sitTypeDD and _sitTypeDD._entriesGlobal then
        _sitTypeDD:SetSelected("none")
    end

    -- Read note.taskList
    local note = BNB.GetNote(noteID)
    local tl = note and note.taskList

    -- Reset
    local rv = (tl and tl.resetType) or "none"
    if _resetDD then _resetDD:SetSelected(rv) end

    -- Situation
    local sitType, sitVal = ParseSituation(tl and tl.situation)
    _selSitType = sitType
    if _sitTypeDD then _sitTypeDD:SetSelected(sitType) end
    if _sitValueEb then _sitValueEb:SetText(sitVal) end

    -- Hide text section
    local ct = _frame and _frame._ct
    if ct and ct._textSection then
        ct._textSection:Hide()
    end

    -- Show/hide value row
    if sitType == "none" then
        if _sitValueRow then _sitValueRow:Hide() end
    else
        if _sitValueRow then
            _sitValueRow:Show()
            local labelStr = sitType == "zone" and L["TEW_VAL_LBL_ZONE"]
                or sitType == "subzone" and L["TEW_VAL_LBL_SUBZONE"]
                or sitType == "instance" and L["TEW_VAL_LBL_INSTANCE"]
                or L["TEW_VAL_LBL_PLAYER"]
            _sitValueRow._lbl:SetText(labelStr)
            if sitType == "player" then
                if _sitBrowseBtn then _sitBrowseBtn:Hide() end
            else
                if _sitBrowseBtn then _sitBrowseBtn:Show() end
            end
        end
    end

    if _sitClearBtn then
        _sitClearBtn:SetEnabled(sitType ~= "none" or sitVal ~= "")
    end

    _isDirty = false
    if _saveBtn then _saveBtn:SetEnabled(true) end  -- always editable in global mode
    _isPopulating = false
end

local function Populate(noteID, taskID)
    local T = BNB.Task; if not T then return end
    local task = T.FindTask(noteID, taskID)
    if not task then return end

    _isPopulating = true
    _isGlobal = false

    -- Show text section (may have been hidden by a previous global open)
    local ct = _frame and _frame._ct
    if ct and ct._textSection then ct._textSection:Show() end

    -- Swap reset dropdown back to per-task entries
    if _resetDD then
        local rv = task.resetType
        -- nil resetType means "global" (inheriting note defaults)
        _resetDD:SetSelected(rv or "global")
    end

    -- Text
    if _textEB then
        local txt = task.text or ""
        _pendingText = txt
        _textEB:SetText(txt)
        _textEB:Hide()
        if _textEB._lbl then
            _textEB._lbl:SetText(txt ~= "" and txt or L["TEW_EMPTY_TEXT"])
            _textEB._lbl:Show()
        end
    end

    -- Situation
    local sitType, sitVal = ParseSituation(task.situation)
    _selSitType = sitType
    if _sitTypeDD then _sitTypeDD:SetSelected(sitType) end
    if _sitValueEb then _sitValueEb:SetText(sitVal) end

    if sitType == "none" then
        if _sitValueRow then _sitValueRow:Hide() end
    else
        if _sitValueRow then
            _sitValueRow:Show()
            local labelStr = sitType == "zone" and L["TEW_VAL_LBL_ZONE"]
                or sitType == "subzone" and L["TEW_VAL_LBL_SUBZONE"]
                or sitType == "instance" and L["TEW_VAL_LBL_INSTANCE"]
                or L["TEW_VAL_LBL_PLAYER"]
            _sitValueRow._lbl:SetText(labelStr)
            if sitType == "player" then
                if _sitBrowseBtn then _sitBrowseBtn:Hide() end
            else
                if _sitBrowseBtn then _sitBrowseBtn:Show() end
            end
        end
    end

    if _sitClearBtn then
        _sitClearBtn:SetEnabled(sitType ~= "none" or sitVal ~= "")
    end

    _isDirty = false
    if _saveBtn then _saveBtn:SetEnabled(false) end
    _isPopulating = false
end

-- ---------------------------------------------------------------------------
-- OPEN / CLOSE
-- ---------------------------------------------------------------------------
-- taskID nil = the note-level task defaults ("global")
local function DoOpen(noteID, taskID, anchorFrame)
    if not _frame then BuildWindow() end
    local f = _frame

    _noteID = noteID; _taskID = taskID
    if taskID then
        Populate(noteID, taskID)
        f:SetWindowTitle(L["TEW_TITLE"])
    else
        PopulateGlobal(noteID)
        f:SetWindowTitle(L["TEW_TITLE_GLOBAL"])
    end
    f:Show(); f:Raise()
    if BigNoteBoxDB and BigNoteBoxDB.skinMode and BNB.ApplyMainWindowSkin then
        BNB.ApplyMainWindowSkin()
    end
    BNB.PlaceBeside(f, anchorFrame, TW_W)
end

function TW.Open(noteID, taskID, anchorFrame)
    if not noteID or not taskID then return end
    DoOpen(noteID, taskID, anchorFrame)
end

function TW.OpenGlobal(noteID, anchorFrame)
    if not noteID then return end
    DoOpen(noteID, nil, anchorFrame)
end

function TW.Close()
    if _frame then _frame:Hide() end
    if BNB.ZonePicker and BNB.ZonePicker.Close then BNB.ZonePicker.Close() end
    _noteID = nil; _taskID = nil; _isDirty = false; _pendingText = ""
end

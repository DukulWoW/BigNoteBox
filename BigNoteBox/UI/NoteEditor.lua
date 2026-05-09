-- BigNoteBox UI/NoteEditor.lua — Right pane note editor

local BNB = BigNoteBox
local L   = BNB.L

BNB._coordWaypoint = nil  -- TomTom UID of the current BNB coord waypoint, or nil

local TOOLBAR_H   = 36
local WYSIWYG_H   = 28   -- height of the WYSIWYG formatting toolbar
local MARKUP_H    = 24   -- height of the rich note markup toolbar
local PAD         = 8
local TSTAMP_H    = 16   -- height of the timestamp strip below title
local CHIP_ROW_H  = 22   -- height of one row of tag chips
local TAG_STRIP_H = CHIP_ROW_H  -- kept for legacy references; strip grows dynamically

local COL_GOLD = { 1, 0.82, 0, 1 }
local COL_GREY = { 0.50, 0.50, 0.50, 1 }

local saveBtn  -- forward ref

-- Debounce timers for undo snapshots, keyed by noteID
local _undoTimers  = {}
-- Forced-interval timers — fire every 3s regardless of typing speed
local _undoForced  = {}

--------------------------------------------------------------------------------
-- LOCK HELPERS
-- A note is locked when:
--   note.locked == true                  (explicit per-note lock)
--   note.locked == nil AND db.lockNotes  (follows global setting)
-- It is explicitly unlocked when:
--   note.locked == false                 (explicit per-note override)
--------------------------------------------------------------------------------
local function NoteIsLocked(note)
    if not note then return false end
    if note.locked == true  then return true  end
    if note.locked == false then return false end
    return BigNoteBoxDB.lockNotes == true
end

--------------------------------------------------------------------------------
-- SAVE BUTTON STATE
--------------------------------------------------------------------------------
function BNB.UpdateSaveButtonState()
    if not saveBtn then return end
    local enabled = BNB._dirty == true
    saveBtn:SetEnabled(enabled)
    saveBtn:SetAlpha(enabled and 1.0 or 0.4)
    pcall(function() saveBtn._tx:SetDesaturated(not enabled) end)
    -- Keep focus button in sync: disabled when no note is selected
    local hasNote = BNB._currentNoteID ~= nil
    if BNB._focusModeBtn then
        BNB._focusModeBtn:SetEnabled(hasNote)
        BNB._focusModeBtn:SetAlpha(hasNote and 1.0 or 0.35)
        pcall(function() BNB._focusModeBtn._n:SetDesaturated(not hasNote) end)
    end
    -- Share button: enabled whenever a note is selected
    if BNB._wysiwygShareBtn then
        BNB._wysiwygShareBtn:SetIconEnabled(hasNote)
    end
end

local _baseMarkDirty = BNB.MarkDirty
BNB.MarkDirty = function()
    BNB._dirty = true
    BNB.UpdateSaveButtonState()
end

--------------------------------------------------------------------------------
-- TIMESTAMP FORMATTING
-- Respects BigNoteBoxDB.dateFormat and BigNoteBoxDB.use24Hour.
-- Relative format uses coarse buckets (< 1m, < 1h, < 1d, < 7d, < 30d, etc.)
--------------------------------------------------------------------------------
local function FmtTime(ts)
    if not ts or ts == 0 then return "" end
    local db       = BigNoteBoxDB
    local fmt      = db and db.dateFormat or "YYYY-MM-DD"
    local use24    = db == nil or db.use24Hour ~= false

    if fmt == "relative" then
        local diff = time() - ts
        if diff < 60         then return "just now"
        elseif diff < 3600   then return math.floor(diff/60) .. "m ago"
        elseif diff < 86400  then return math.floor(diff/3600) .. "h ago"
        elseif diff < 604800 then return math.floor(diff/86400) .. "d ago"
        elseif diff < 2592000 then return math.floor(diff/604800) .. " weeks ago"
        elseif diff < 31536000 then return math.floor(diff/2592000) .. " months ago"
        else return math.floor(diff/31536000) .. " years ago" end
    end

    -- Build date part
    local datePart
    if fmt == "DD-MM-YYYY" then
        datePart = date("%d-%m-%Y", ts)
    elseif fmt == "MM-DD-YYYY" then
        datePart = date("%m-%d-%Y", ts)
    else  -- YYYY-MM-DD (default)
        datePart = date("%Y-%m-%d", ts)
    end

    -- Build time part
    local timePart
    if use24 then
        timePart = date("%H:%M", ts)
    else
        local h = tonumber(date("%H", ts))
        local m = date("%M", ts)
        local ampm = h >= 12 and "pm" or "am"
        h = h % 12; if h == 0 then h = 12 end
        timePart = h .. ":" .. m .. " " .. ampm
    end

    return datePart .. " " .. timePart
end

--------------------------------------------------------------------------------
-- WELCOME PANEL HELPERS
--------------------------------------------------------------------------------

-- Returns the greeting prefix ("Good morning" etc.) for the current hour.
local function GetGreeting()
    local h = tonumber(date("%H"))
    if h >= 5  and h < 12 then return L["WELCOME_MORNING"]
    elseif h >= 12 and h < 17 then return L["WELCOME_AFTERNOON"]
    else return L["WELCOME_EVENING"] end
end

-- Returns the time-of-day icon texture path for the current hour.
-- dawn 05-08, day 08-18, dusk 18-21, night 21-05
local function GetTimeIcon()
    local h = tonumber(date("%H"))
    local BASE = "Interface\\AddOns\\BigNoteBox\\Assets\\UI\\"
    if     h >= 5  and h < 8  then return BASE .. "ui-dawn.tga"
    elseif h >= 8  and h < 18 then return BASE .. "ui-day.tga"
    elseif h >= 18 and h < 21 then return BASE .. "ui-dusk.tga"
    else                           return BASE .. "ui-night.tga"
    end
end

-- Returns formatted clock string respecting use24Hour DB setting.
local function GetClockString()
    local use24 = BigNoteBoxDB == nil or BigNoteBoxDB.use24Hour ~= false
    if use24 then
        return date("%H:%M")
    else
        local h = tonumber(date("%H"))
        local m = date("%M")
        local ampm = h >= 12 and "PM" or "AM"
        h = h % 12; if h == 0 then h = 12 end
        return h .. ":" .. m .. " " .. ampm
    end
end

-- Returns a full named date string e.g. "Monday, April 13, 2026".
local function GetDateString()
    local weekdays = L["WELCOME_WEEKDAYS"]
    local months   = L["WELCOME_MONTHS"]
    -- date("%w") = 0 (Sunday) .. 6 (Saturday); our table is 1-indexed Sun=1
    local wday  = tonumber(date("%w")) + 1
    local day   = tonumber(date("%d"))
    local month = tonumber(date("%m"))
    local year  = date("%Y")
    local dayName   = weekdays and weekdays[wday]   or date("%A")
    local monthName = months   and months[month]    or date("%B")
    return dayName .. ", " .. monthName .. " " .. day .. ", " .. year
end

-- Collect up to `max` notes whose context matches the current zone/instance.
-- Uses the same matching logic as ContextNotes.lua.
local function GetLocationNotes(max)
    if not BigNoteBoxNotesDB or not BigNoteBoxNotesDB.notes then return {} end
    local inInst, instType = IsInInstance()
    local curKind, curVal
    if inInst and instType ~= "none" then
        curKind = "instance"
        curVal  = (GetInstanceInfo and select(1, GetInstanceInfo()) or GetRealZoneText() or ""):lower()
    else
        curKind = "zone"
        curVal  = (GetZoneText() or ""):lower()
    end
    if curVal == "" then return {} end

    local results = {}
    for id, note in pairs(BigNoteBoxNotesDB.notes) do
        if note.context then
            local kind, value = note.context:match("^(%w+):(.+)$")
            if kind and value and kind == curKind and value:lower() == curVal then
                results[#results + 1] = { id = id, note = note }
                if #results >= max then break end
            end
        end
    end
    return results
end

-- Collect up to `max` favorited notes.
local function GetFavoriteNotes(max)
    if not BigNoteBoxNotesDB or not BigNoteBoxNotesDB.notes then return {} end
    local results = {}
    for id, note in pairs(BigNoteBoxNotesDB.notes) do
        if note.favorited then
            results[#results + 1] = { id = id, note = note }
            if #results >= max then break end
        end
    end
    return results
end

local ICON_BTN_SIZE = 40
local ICON_BTN_PAD  = 8

local function BuildNoteIconRow(parent, noteItems, yOffset)
    if not noteItems or #noteItems == 0 then return 0 end

    -- Container frame for this row (used for orphan-on-rebuild cleanup)
    local row = CreateFrame("Frame", nil, parent)
    row:SetPoint("TOPLEFT",  parent, "TOPLEFT",  0, yOffset)
    row:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, yOffset)
    row:SetHeight(ICON_BTN_SIZE)

    local count   = math.min(#noteItems, 10)
    local totalW  = count * ICON_BTN_SIZE + (count - 1) * ICON_BTN_PAD
    local startX  = 0  -- centred via SetPoint offset calculated at layout

    for i = 1, count do
        local entry  = noteItems[i]
        local noteID = entry.id
        local note   = entry.note

        local btn = CreateFrame("Button", nil, row)
        btn:SetSize(ICON_BTN_SIZE, ICON_BTN_SIZE)

        -- Centre the whole row: offset = -(totalW/2) + (i-1)*(size+pad)
        local xOff = -(totalW / 2) + (i - 1) * (ICON_BTN_SIZE + ICON_BTN_PAD)
        btn:SetPoint("LEFT", row, "CENTER", xOff, 0)

        -- Icon texture
        local iconPath = (note.icon and note.icon ~= "") and note.icon
                         or "Interface\\Icons\\INV_Misc_Note_06"
        local iconTex = btn:CreateTexture(nil, "ARTWORK")
        iconTex:SetAllPoints()
        iconTex:SetTexture(iconPath)
        btn._iconTex = iconTex

        -- Default border — matches NoteList style (UI-Tooltip-Border, no custom LSM)
        local bf = BNB.CreateBackdropFrame("Frame", nil, btn)
        bf:SetFrameLevel(btn:GetFrameLevel() + 2)
        bf:EnableMouse(false)
        bf:SetPoint("TOPLEFT",     btn, "TOPLEFT",     -2,  2)
        bf:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT",  2, -2)
        pcall(function()
            bf:SetBackdrop({
                edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                edgeSize = 12,
                insets   = { left = 0, right = 0, top = 0, bottom = 0 },
            })
            bf:SetBackdropColor(0, 0, 0, 0)
            bf:SetBackdropBorderColor(0.35, 0.35, 0.38, 0.75)
        end)

        -- Clicks
        btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        btn:SetScript("OnClick", function(self, mouseBtn)
            if mouseBtn == "RightButton" then
                if BNB.Sticky and BNB.Sticky.Open then
                    BNB.Sticky.Open(noteID)
                end
            else
                if BNB.mainFrame and not BNB.mainFrame:IsShown() then
                    BNB.mainFrame:Show()
                end
                if BNB.SelectNote then BNB.SelectNote(noteID) end
            end
        end)

        -- Tooltip
        btn:SetScript("OnEnter", function(self)
            self._iconTex:SetVertexColor(1.1, 1.1, 1.1)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:AddLine(note.title or "Untitled", 1, 1, 1)
            GameTooltip:AddLine("Click to open  |  Right-click for sticky", 0.7, 0.7, 0.7)
            GameTooltip:Show()
        end)
        btn:SetScript("OnLeave", function(self)
            self._iconTex:SetVertexColor(1, 1, 1)
            GameTooltip:Hide()
        end)
    end

    return ICON_BTN_SIZE
end

-- ── Import popup window ───────────────────────────────────────────────────────
-- Built once, reused. Parented to UIParent at DIALOG strata.
local _importFrame

local function GetImportFrame()
    if _importFrame then return _importFrame end

    local skinMode = BigNoteBoxDB and BigNoteBoxDB.skinMode

    -- Outer frame: skin-aware or plain dark backdrop
    local f
    if skinMode and BNB.CreateSkinFrame then
        f = BNB.CreateSkinFrame(UIParent, false, "BNBImportNotesFrame", false)
    else
        f = BNB.CreateBackdropFrame("Frame", "BNBImportNotesFrame", UIParent)
        BNB.SetBackdrop(f, 0.08, 0.08, 0.10, 0.97, 0.30, 0.30, 0.32, 1)
    end
    f:SetSize(520, 320)
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
    f:SetToplevel(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) self:StartMoving() end)
    f:SetScript("OnDragStop",  function(self) self:StopMovingOrSizing() end)
    f:SetFrameStrata("DIALOG")
    tinsert(UISpecialFrames, "BNBImportNotesFrame")

    -- Title bar: skin-aware strip or plain dark backdrop
    local titleBar
    if skinMode and BNB.CreateSkinStrip then
        titleBar = BNB.CreateSkinStrip(f, true, false)
    else
        titleBar = BNB.CreateBackdropFrame("Frame", nil, f)
        BNB.SetBackdrop(titleBar, 0.12, 0.12, 0.15, 1, 0.30, 0.30, 0.32, 0)
    end
    titleBar:SetPoint("TOPLEFT",  f, "TOPLEFT",  0,  0)
    titleBar:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0,  0)
    titleBar:SetHeight(28)
    titleBar:EnableMouse(true)
    titleBar:RegisterForDrag("LeftButton")
    titleBar:SetScript("OnDragStart", function() f:StartMoving() end)
    titleBar:SetScript("OnDragStop",  function() f:StopMovingOrSizing() end)

    local titleLbl = titleBar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    titleLbl:SetPoint("CENTER", titleBar, "CENTER", -10, 0)
    titleLbl:SetText(L["IMPORT_POPUP_TITLE"])
    titleLbl:SetTextColor(1, 0.82, 0)

    -- Close button: bt-close asset set, same style as all other BNB windows
    local closeBtn = BNB.CreateSkinCloseButton(titleBar, function() f:Hide() end)
    closeBtn:SetPoint("RIGHT", titleBar, "RIGHT", -3, 0)

    -- Live-update skin colours when preset changes
    f:SetScript("OnShow", function()
        if BNB.ApplyMainWindowSkin then BNB.ApplyMainWindowSkin() end
    end)

    -- Description label
    local desc = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    desc:SetPoint("TOPLEFT",  f, "TOPLEFT",  16, -36)
    desc:SetPoint("TOPRIGHT", f, "TOPRIGHT", -16, -36)
    desc:SetJustifyH("LEFT")
    desc:SetTextColor(0.85, 0.85, 0.85)
    desc:SetText(L["IMPORT_POPUP_DESC"])

    -- Scroll frame + editbox
    local sf = CreateFrame("ScrollFrame", nil, f, "ScrollFrameTemplate")
    sf:SetPoint("TOPLEFT",     f, "TOPLEFT",      16, -58)
    sf:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -28, 50)

    local eb = CreateFrame("EditBox", nil, sf)
    eb:SetMultiLine(true)
    eb:SetAutoFocus(false)
    eb:SetFontObject("ChatFontNormal")
    eb:SetWidth(sf:GetWidth())
    eb:SetHeight(1)
    eb:SetScript("OnEscapePressed", function() f:Hide() end)
    eb:SetScript("OnTextChanged", function(self)
        local lineH = select(2, self:GetFont()) or 14
        local ok, lines = pcall(function() return self:GetNumLines() end)
        lines = math.max(1, (ok and lines) or 1)
        self:SetHeight(lines * lineH + 8)
        sf:UpdateScrollChildRect()
    end)
    sf:SetScrollChild(eb)
    f._importEB = eb

    -- Backdrop for the editbox area
    local ebBg = BNB.CreateBackdropFrame("Frame", nil, f)
    ebBg:SetPoint("TOPLEFT",     sf, "TOPLEFT",     -4,  4)
    ebBg:SetPoint("BOTTOMRIGHT", sf, "BOTTOMRIGHT",  4, -4)
    BNB.SetBackdrop(ebBg, 0.04, 0.04, 0.06, 1, 0.25, 0.25, 0.28, 0.8)
    ebBg:SetFrameLevel(sf:GetFrameLevel() - 1)

    -- Cancel button
    local cancelBtn = BNB.CreateButton(nil, f, L["IMPORT_POPUP_CANCEL"], 110, 28)
    cancelBtn:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -16, 14)
    cancelBtn:SetScript("OnClick", function() f:Hide() end)

    -- Import button
    local importBtn = BNB.CreateButton(nil, f, L["IMPORT_POPUP_BTN"], 110, 28)
    importBtn:SetPoint("RIGHT", cancelBtn, "LEFT", -8, 0)
    importBtn:SetScript("OnClick", function()
        local text = eb:GetText() or ""
        text = text:match("^%s*(.-)%s*$")
        if text == "" or not text:find("\"export_version\"") or not text:find("\"notes\"") then
            BNB:Print(L["IMPORT_ERR_JSON"])
            return
        end
        if not BNB._ParseJsonNotes then
            BNB:Print("|cffff4444Import not available: ConfigWindow not loaded yet.|r")
            return
        end
        local noteList = BNB._ParseJsonNotes(text)
        if not noteList or #noteList == 0 then
            BNB:Print(L["IMPORT_ERR_JSON"])
            return
        end
        local hasChar = false
        for _, n in ipairs(noteList) do
            if n.scope and n.scope:find("^char:") then hasChar = true; break end
        end
        if hasChar then
            BNB._pendingImportNotes = noteList
            StaticPopup_Show("BNB_IMPORT_SCOPE_REMAP")
        else
            local count = BNB._DoImport(noteList, false)
            BNB:Print(string.format(L["IMPORT_SUCCESS"], count or 0))
        end
        f:Hide()
    end)

    _importFrame = f
    return f
end

--------------------------------------------------------------------------------
-- IMG TAG DIALOG
-- Opened by the Img button in both the main markup bar and the focus markup bar.
-- Caller passes insertFn (either InsertTag or FocusInsertTag) so the dialog
-- stays editor-agnostic.
-- Skin-aware: follows the same pattern as GetImportFrame.
--------------------------------------------------------------------------------
local _imgDialog
local _lnkDialog
local _icoDialog
local USER_IMG_PREFIX_DIALOG = "Interface\\AddOns\\BigNoteBox\\UserImages\\"

local ALIGN_OPTS   = { "center", "left", "right" }
local ALIGN_LABELS = { "Center", "Left", "Right" }

local function ResolvePath(raw)
    local s = raw and raw:match("^%s*(.-)%s*$") or ""
    if s == "" then return nil end
    if s:sub(1, 9):lower() == "interface" then return s end
    return USER_IMG_PREFIX_DIALOG .. s:gsub("/", "\\")
end

function BNB.OpenImgDialog(insertFn)
    if not insertFn then return end

    -- ── Build frame lazily ────────────────────────────────────────────────────
    if not _imgDialog then
        local skinMode = BigNoteBoxDB and BigNoteBoxDB.skinMode
        local DW    = 320
        local DPAD  = 14
        local TITLE_H = 28

        -- All Y values are negative offsets from the frame top.
        -- We accumulate curY top-down, then set DH from the final curY.
        local curY = -(TITLE_H + 10)  -- start just below title bar

        local f
        if skinMode and BNB.CreateSkinFrame then
            f = BNB.CreateSkinFrame(UIParent, false, "BNBImgTagDialog", false)
        else
            f = CreateFrame("Frame", "BNBImgTagDialog", UIParent, "ButtonFrameTemplate")
            ButtonFrameTemplate_HidePortrait(f)
            ButtonFrameTemplate_HideButtonBar(f)
            if f.Inset then f.Inset:Hide() end
        end
        -- Size set after layout is computed
        f:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
        f:SetToplevel(true)
        f:SetMovable(true)
        f:EnableMouse(true)
        f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", function(self) self:StartMoving() end)
        f:SetScript("OnDragStop",  function(self) self:StopMovingOrSizing() end)
        f:SetFrameStrata("DIALOG")
        f:SetClampedToScreen(true)
        tinsert(UISpecialFrames, "BNBImgTagDialog")

        -- Title bar (skin mode: custom strip; normal mode: ButtonFrameTemplate provides it)
        if skinMode and BNB.CreateSkinStrip then
            local titleBar = BNB.CreateSkinStrip(f, true, false)
            titleBar:SetPoint("TOPLEFT",  f, "TOPLEFT",  0, 0)
            titleBar:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
            titleBar:SetHeight(TITLE_H)
            titleBar:EnableMouse(true)
            titleBar:RegisterForDrag("LeftButton")
            titleBar:SetScript("OnDragStart", function() f:StartMoving() end)
            titleBar:SetScript("OnDragStop",  function() f:StopMovingOrSizing() end)
            local titleLbl = titleBar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            titleLbl:SetPoint("CENTER", titleBar, "CENTER", -10, 0)
            titleLbl:SetText("Insert Image"); titleLbl:SetTextColor(1, 0.82, 0)
            local closeBtn = BNB.CreateSkinCloseButton(titleBar, function() f:Hide() end)
            closeBtn:SetPoint("RIGHT", titleBar, "RIGHT", -3, 0)
        else
            f:SetTitle("Insert Image")
            if f.CloseButton then
                f.CloseButton:SetScript("OnClick", function() f:Hide() end)
            end
        end

        f:SetScript("OnShow", function()
            if BNB.ApplyMainWindowSkin then BNB.ApplyMainWindowSkin() end
        end)
        f:SetScript("OnKeyDown", function(_, key)
            if key == "ESCAPE" then f:Hide() end
            f:SetPropagateKeyboardInput(key ~= "ESCAPE")
        end)
        f:EnableKeyboard(true)

        -- ── Layout helpers ────────────────────────────────────────────────────
        local INNER_W = DW - DPAD * 2  -- usable width between left/right padding

        local function Lbl(text)
            local l = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            l:SetPoint("TOPLEFT", f, "TOPLEFT", DPAD, curY)
            l:SetTextColor(0.78, 0.78, 0.78)
            l:SetText(text)
            curY = curY - 16
            return l
        end

        local function FieldEB(width, numeric)
            local eb = CreateFrame("EditBox", nil, f,
                "BackdropTemplate")
            BNB.EnsureBackdrop(eb)
            BNB.SetBackdropDark(eb)
            eb:SetPoint("TOPLEFT", f, "TOPLEFT", DPAD, curY)
            eb:SetSize(width, 22)
            eb:SetFontObject("GameFontNormal")
            eb:SetAutoFocus(false)
            eb:SetMaxLetters(256)
            eb:SetTextInsets(4, 4, 0, 0)
            eb:SetScript("OnEscapePressed", function() f:Hide() end)
            if numeric then eb:SetNumeric(false) end
            curY = curY - 28
            return eb
        end

        -- ── UserImages dropdown (only if manifest has entries) ─────────────────
        local userImages = BNB.AdvancedMode and BNB.AdvancedMode.GetUserImages() or {}
        local useNativeDD = C_XMLUtil and C_XMLUtil.GetTemplateInfo
            and C_XMLUtil.GetTemplateInfo("WowStyle1DropdownTemplate")

        local pickerDD, pickerCycle
        local selImage = 0  -- 0 = nothing selected

        -- Extract the short display name from a full path
        local function ShortName(fullPath)
            local prefix = USER_IMG_PREFIX_DIALOG:gsub("\\", "\\\\")
            local short = fullPath:match(prefix .. "(.+)$")
                       or fullPath:match("[/\\]([^/\\]+)$")
                       or fullPath
            return short:gsub("\\", "/")
        end

        local pickLabels = {}
        for i, p in ipairs(userImages) do
            pickLabels[i] = ShortName(p)
        end

        -- fileEb and RefreshPreview are forward-declared; defined after this block
        local fileEb
        local RefreshPreview

        if #userImages > 0 then
            Lbl("Pick from UserImages")
            if useNativeDD then
                pickerDD = CreateFrame("DropdownButton", nil, f, "WowStyle1DropdownTemplate")
                pickerDD:SetPoint("TOPLEFT", f, "TOPLEFT", DPAD, curY)
                pickerDD:SetWidth(INNER_W)
                pickerDD:SetupMenu(function(_, root)
                    for i, label in ipairs(pickLabels) do
                        local idx = i
                        root:CreateRadio(label,
                            function() return selImage == idx end,
                            function()
                                selImage = idx
                                pickerDD:GenerateMenu()
                                if fileEb then
                                    fileEb:SetText(label)
                                    if RefreshPreview then RefreshPreview() end
                                end
                            end)
                    end
                end)
                curY = curY - 32
            else
                pickerCycle = BNB.CreateButton(nil, f,
                    selImage > 0 and pickLabels[selImage] or "-- select image --",
                    INNER_W, 22)
                pickerCycle:SetPoint("TOPLEFT", f, "TOPLEFT", DPAD, curY)
                pickerCycle:SetScript("OnClick", function(self)
                    selImage = (selImage % #userImages) + 1
                    self:SetText(pickLabels[selImage])
                    if fileEb then
                        fileEb:SetText(pickLabels[selImage])
                        if RefreshPreview then RefreshPreview() end
                    end
                end)
                curY = curY - 28
            end
            curY = curY - 6  -- gap before filename label
        end

        -- ── Filename ──────────────────────────────────────────────────────────
        local fileLblText = #userImages > 0
            and "Or type a filename  (e.g. mymap.tga)"
            or  "Filename  (e.g. mymap.tga or Horde/map.tga)"
        Lbl(fileLblText)
        fileEb = FieldEB(INNER_W, false)
        f._fileEb = fileEb
        curY = curY - 4  -- gap before alignment

        -- ── Alignment ─────────────────────────────────────────────────────────
        Lbl("Alignment")

        local selAlign = 1  -- index into ALIGN_OPTS
        local alignDD, alignCycle
        local function GetAlignLabel() return ALIGN_LABELS[selAlign] end

        if useNativeDD then
            alignDD = CreateFrame("DropdownButton", nil, f, "WowStyle1DropdownTemplate")
            alignDD:SetPoint("TOPLEFT", f, "TOPLEFT", DPAD, curY)
            alignDD:SetWidth(INNER_W)
            alignDD:SetupMenu(function(_, root)
                for i, label in ipairs(ALIGN_LABELS) do
                    local idx = i
                    root:CreateRadio(label,
                        function() return selAlign == idx end,
                        function()
                            selAlign = idx
                            alignDD:GenerateMenu()
                        end)
                end
            end)
            curY = curY - 32
        else
            alignCycle = BNB.CreateButton(nil, f, GetAlignLabel(), INNER_W, 22)
            alignCycle:SetPoint("TOPLEFT", f, "TOPLEFT", DPAD, curY)
            alignCycle:SetScript("OnClick", function(self)
                selAlign = (selAlign % #ALIGN_OPTS) + 1
                self:SetText(GetAlignLabel())
            end)
            curY = curY - 28
        end
        curY = curY - 6  -- gap before width/height

        -- ── Width / Height (50/50 across full inner width) ────────────────────
        local NUM_GAP  = 8
        local NUM_W    = math.floor((INNER_W - NUM_GAP) / 2)
        local wLbl = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        wLbl:SetPoint("TOPLEFT", f, "TOPLEFT", DPAD, curY)
        wLbl:SetTextColor(0.78, 0.78, 0.78); wLbl:SetText("Width")
        local hLbl = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        hLbl:SetPoint("TOPLEFT", f, "TOPLEFT", DPAD + NUM_W + NUM_GAP, curY)
        hLbl:SetTextColor(0.78, 0.78, 0.78); hLbl:SetText("Height")
        curY = curY - 16

        local widthEb = FieldEB(NUM_W, true)
        widthEb:SetText("256")
        f._widthEb = widthEb

        -- Height editbox: manual placement at same row as widthEb (FieldEB advanced curY)
        local heightEbY = curY + 28  -- curY was advanced by FieldEB, step back one row
        local heightEb = CreateFrame("EditBox", nil, f,
            "BackdropTemplate")
        BNB.EnsureBackdrop(heightEb); BNB.SetBackdropDark(heightEb)
        heightEb:SetPoint("TOPLEFT", f, "TOPLEFT", DPAD + NUM_W + NUM_GAP, heightEbY)
        heightEb:SetSize(NUM_W, 22)
        heightEb:SetFontObject("GameFontNormal"); heightEb:SetAutoFocus(false)
        heightEb:SetMaxLetters(6); heightEb:SetTextInsets(4, 4, 0, 0)
        heightEb:SetNumeric(false); heightEb:SetText("256")
        heightEb:SetScript("OnEscapePressed", function() f:Hide() end)
        f._heightEb = heightEb
        curY = curY - 6  -- gap before preview

        -- ── Preview thumbnail (hidden until texture resolves) ─────────────────
        -- Anchored via curY like all other widgets so DH calculation is exact.
        local PREV_SIZE = 80
        local prevBg = BNB.CreateBackdropFrame("Frame", nil, f)
        prevBg:SetSize(PREV_SIZE, PREV_SIZE)
        -- Centre horizontally: left edge = (DW - PREV_SIZE) / 2
        prevBg:SetPoint("TOPLEFT", f, "TOPLEFT", (DW - PREV_SIZE) / 2, curY)
        BNB.SetBackdrop(prevBg, 0.04, 0.04, 0.06, 1, 0.25, 0.25, 0.28, 1)
        prevBg:Hide()  -- hidden until a texture is loaded

        local prevTex = prevBg:CreateTexture(nil, "ARTWORK")
        prevTex:SetPoint("TOPLEFT",     prevBg, "TOPLEFT",     3,  -3)
        prevTex:SetPoint("BOTTOMRIGHT", prevBg, "BOTTOMRIGHT", -3,  3)
        prevTex:SetTexture(nil)
        f._prevTex = prevTex
        f._prevBg  = prevBg

        curY = curY - PREV_SIZE - 8  -- advance past preview + small gap

        RefreshPreview = function()
            local path = ResolvePath(fileEb:GetText())
            local ok = false
            if path then
                ok = pcall(function() prevTex:SetTexture(path) end)
            end
            if ok and path then
                prevBg:Show()
            else
                prevTex:SetTexture(nil)
                prevBg:Hide()
            end
        end
        fileEb:SetScript("OnTextChanged", function() RefreshPreview() end)

        -- ── Buttons (anchored to bottom-centre) ───────────────────────────────
        -- Frame height is computed from content; buttons sit at a fixed inset
        -- from the bottom so they never overlap anything above them.
        local BTN_H    = 26
        local BTN_ROW  = BTN_H + DPAD * 2  -- total bottom reserved area
        local DH = math.abs(curY) + BTN_ROW
        f:SetSize(DW, DH)

        local cancelBtn = BNB.CreateButton(nil, f, "Cancel", 90, BTN_H)
        cancelBtn:SetPoint("BOTTOM", f, "BOTTOM", 53, DPAD)
        cancelBtn:SetScript("OnClick", function() f:Hide() end)

        local insertBtn = BNB.CreateButton(nil, f, "Insert", 90, BTN_H)
        insertBtn:SetPoint("BOTTOM", f, "BOTTOM", -53, DPAD)

        -- ── Stored state ──────────────────────────────────────────────────────
        f._insertBtn    = insertBtn
        f._selAlign     = function() return selAlign end
        f._resetAlign   = function()
            selAlign = 1
            if alignDD and alignDD.GenerateMenu then alignDD:GenerateMenu() end
            if alignCycle then alignCycle:SetText(GetAlignLabel()) end
        end
        f._resetPicker  = function()
            selImage = 0
            if pickerDD and pickerDD.GenerateMenu then pickerDD:GenerateMenu() end
            if pickerCycle then
                pickerCycle:SetText("-- select image --")
            end
        end
        f._refreshPreview = RefreshPreview

        _imgDialog = f
    end  -- end lazy build

    -- ── Wire insert callback for this call ────────────────────────────────────
    _imgDialog._insertBtn:SetScript("OnClick", function()
        local raw  = _imgDialog._fileEb:GetText()
        local path = ResolvePath(raw)
        if not path or path == "" then
            _imgDialog._fileEb:SetFocus()
            return
        end
        local w = math.abs(tonumber(_imgDialog._widthEb:GetText())  or 256)
        local h = math.abs(tonumber(_imgDialog._heightEb:GetText()) or 256)
        w = math.max(1, math.min(w, 4096))
        h = math.max(1, math.min(h, 4096))
        local align = ALIGN_OPTS[_imgDialog._selAlign()]
        local tag = string.format("{img:%s:%d:%d:%s}", path, w, h, align)
        _imgDialog:Hide()
        insertFn(tag)
    end)

    -- ── Reset fields and show ─────────────────────────────────────────────────
    _imgDialog._fileEb:SetText("")
    _imgDialog._widthEb:SetText("256")
    _imgDialog._heightEb:SetText("256")
    _imgDialog._resetAlign()
    _imgDialog._resetPicker()
    _imgDialog._prevTex:SetTexture(nil)
    _imgDialog._prevBg:Hide()
    _imgDialog:Show()
    _imgDialog._fileEb:SetFocus()
end

--------------------------------------------------------------------------------
-- LNK TAG DIALOG
-- Opened by the Lnk button in both markup bars.
--------------------------------------------------------------------------------
function BNB.OpenLnkDialog(insertFn)
    if not insertFn then return end

    if not _lnkDialog then
        local skinMode = BigNoteBoxDB and BigNoteBoxDB.skinMode
        local DW, DH = 320, 180
        local DPAD    = 14
        local TITLE_H = 28

        local f
        if skinMode and BNB.CreateSkinFrame then
            f = BNB.CreateSkinFrame(UIParent, false, "BNBLnkTagDialog", false)
        else
            f = CreateFrame("Frame", "BNBLnkTagDialog", UIParent, "ButtonFrameTemplate")
            ButtonFrameTemplate_HidePortrait(f)
            ButtonFrameTemplate_HideButtonBar(f)
            if f.Inset then f.Inset:Hide() end
        end
        f:SetSize(DW, DH)
        f:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
        f:SetToplevel(true); f:SetMovable(true); f:EnableMouse(true)
        f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", function(self) self:StartMoving() end)
        f:SetScript("OnDragStop",  function(self) self:StopMovingOrSizing() end)
        f:SetFrameStrata("DIALOG"); f:SetClampedToScreen(true)
        tinsert(UISpecialFrames, "BNBLnkTagDialog")

        if skinMode and BNB.CreateSkinStrip then
            local titleBar = BNB.CreateSkinStrip(f, true, false)
            titleBar:SetPoint("TOPLEFT",  f, "TOPLEFT",  0, 0)
            titleBar:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
            titleBar:SetHeight(TITLE_H)
            titleBar:EnableMouse(true); titleBar:RegisterForDrag("LeftButton")
            titleBar:SetScript("OnDragStart", function() f:StartMoving() end)
            titleBar:SetScript("OnDragStop",  function() f:StopMovingOrSizing() end)
            local titleLbl = titleBar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            titleLbl:SetPoint("CENTER", titleBar, "CENTER", -10, 0)
            titleLbl:SetText("Insert Link"); titleLbl:SetTextColor(1, 0.82, 0)
            local closeBtn = BNB.CreateSkinCloseButton(titleBar, function() f:Hide() end)
            closeBtn:SetPoint("RIGHT", titleBar, "RIGHT", -3, 0)
        else
            f:SetTitle("Insert Link")
            if f.CloseButton then
                f.CloseButton:SetScript("OnClick", function() f:Hide() end)
            end
        end

        f:SetScript("OnShow", function()
            if BNB.ApplyMainWindowSkin then BNB.ApplyMainWindowSkin() end
        end)
        f:SetScript("OnKeyDown", function(_, key)
            if key == "ESCAPE" then f:Hide() end
            f:SetPropagateKeyboardInput(key ~= "ESCAPE")
        end)
        f:EnableKeyboard(true)

        local INNER_W = DW - DPAD * 2
        local curY = -(TITLE_H + 10)

        local function Lbl(text)
            local l = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            l:SetPoint("TOPLEFT", f, "TOPLEFT", DPAD, curY)
            l:SetTextColor(0.78, 0.78, 0.78); l:SetText(text)
            curY = curY - 16
        end

        local function FieldEB(width)
            local eb = CreateFrame("EditBox", nil, f,
                "BackdropTemplate")
            BNB.EnsureBackdrop(eb); BNB.SetBackdropDark(eb)
            eb:SetPoint("TOPLEFT", f, "TOPLEFT", DPAD, curY)
            eb:SetSize(width, 22)
            eb:SetFontObject("GameFontNormal"); eb:SetAutoFocus(false)
            eb:SetMaxLetters(512); eb:SetTextInsets(4, 4, 0, 0)
            eb:SetScript("OnEscapePressed", function() f:Hide() end)
            curY = curY - 28
            return eb
        end

        Lbl("URL")
        local urlEb = FieldEB(INNER_W)
        f._urlEb = urlEb

        curY = curY - 2
        Lbl("Link text  (leave blank to use the URL)")
        local textEb = FieldEB(INNER_W)
        f._textEb = textEb

        -- Tab between fields
        urlEb:SetScript("OnEnterPressed", function() textEb:SetFocus() end)
        textEb:SetScript("OnEnterPressed", function()
            if f._insertBtn then f._insertBtn:Click() end
        end)

        local BTN_H = 26
        local DH_final = math.abs(curY) + BTN_H + DPAD * 2
        f:SetSize(DW, DH_final)

        local cancelBtn = BNB.CreateButton(nil, f, "Cancel", 90, BTN_H)
        cancelBtn:SetPoint("BOTTOM", f, "BOTTOM", 53, DPAD)
        cancelBtn:SetScript("OnClick", function() f:Hide() end)

        local insertBtn = BNB.CreateButton(nil, f, "Insert", 90, BTN_H)
        insertBtn:SetPoint("BOTTOM", f, "BOTTOM", -53, DPAD)
        f._insertBtn = insertBtn

        _lnkDialog = f
    end

    _lnkDialog._insertBtn:SetScript("OnClick", function()
        local url  = (_lnkDialog._urlEb:GetText()  or ""):match("^%s*(.-)%s*$")
        local txt  = (_lnkDialog._textEb:GetText() or ""):match("^%s*(.-)%s*$")
        if url == "" then _lnkDialog._urlEb:SetFocus(); return end
        if txt == "" then txt = url end
        local tag = string.format("{link*%s*%s}", url, txt)
        _lnkDialog:Hide()
        insertFn(tag)
    end)

    _lnkDialog._urlEb:SetText("")
    _lnkDialog._textEb:SetText("")
    _lnkDialog:Show()
    _lnkDialog._urlEb:SetFocus()
end

--------------------------------------------------------------------------------
-- ICO TAG DIALOG
-- Two tabs: "BNB Icons" (manifest grid + search) and "Blizzard Icon" (name field).
-- Both tabs share a size field, live preview, and Insert/Cancel.
--------------------------------------------------------------------------------
function BNB.OpenIcoDialog(insertFn)
    if not insertFn then return end

    if not _icoDialog then
        local skinMode = BigNoteBoxDB and BigNoteBoxDB.skinMode
        local DW      = 320
        local DPAD    = 12
        local TITLE_H = 28
        local TAB_H   = skinMode and 24 or 28
        local CONTENT_TOP = TITLE_H + TAB_H + 4  -- y offset where tab panels start

        -- Grid constants
        local CELL     = 30
        local CELL_PAD = 3
        local INNER_W  = DW - DPAD * 2
        local GRID_COLS = math.floor(INNER_W / (CELL + CELL_PAD))

        -- Size field sits in the search row — no dedicated size row needed
        local SIZE_EB_W  = 70   -- width of the size editbox
        local SIZE_GAP   = 6    -- gap between search and size fields
        local SEARCH_W   = INNER_W - SIZE_EB_W - SIZE_GAP

        -- Bottom section: preview + buttons only (size moved to search row)
        local PREV_SIZE  = 48
        local BTN_H      = 26
        local ALIGN_H    = 36   -- alignment label (14) + dropdown (22)
        local BOTTOM_H   = ALIGN_H + PREV_SIZE + 10 + BTN_H + DPAD * 2
        local DH         = CONTENT_TOP + 200 + 10 + BOTTOM_H  -- 200px grid area

        local f
        if skinMode and BNB.CreateSkinFrame then
            f = BNB.CreateSkinFrame(UIParent, false, "BNBIcoTagDialog", false)
        else
            f = CreateFrame("Frame", "BNBIcoTagDialog", UIParent, "ButtonFrameTemplate")
            ButtonFrameTemplate_HidePortrait(f)
            ButtonFrameTemplate_HideButtonBar(f)
            if f.Inset then f.Inset:Hide() end
        end
        f:SetSize(DW, DH)
        f:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
        f:SetToplevel(true); f:SetMovable(true); f:EnableMouse(true)
        f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", function(self) self:StartMoving() end)
        f:SetScript("OnDragStop",  function(self) self:StopMovingOrSizing() end)
        f:SetFrameStrata("DIALOG"); f:SetClampedToScreen(true)
        tinsert(UISpecialFrames, "BNBIcoTagDialog")

        -- Title bar
        local titleBar
        if skinMode and BNB.CreateSkinStrip then
            titleBar = BNB.CreateSkinStrip(f, true, false)
            titleBar:SetPoint("TOPLEFT",  f, "TOPLEFT",  0, 0)
            titleBar:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
            titleBar:SetHeight(TITLE_H)
            titleBar:EnableMouse(true); titleBar:RegisterForDrag("LeftButton")
            titleBar:SetScript("OnDragStart", function() f:StartMoving() end)
            titleBar:SetScript("OnDragStop",  function() f:StopMovingOrSizing() end)

            local titleLbl = titleBar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            titleLbl:SetPoint("CENTER", titleBar, "CENTER", -10, 0)
            titleLbl:SetText("Insert Icon"); titleLbl:SetTextColor(1, 0.82, 0)

            local closeBtn = BNB.CreateSkinCloseButton(titleBar, function() f:Hide() end)
            closeBtn:SetPoint("RIGHT", titleBar, "RIGHT", -3, 0)
        else
            -- Normal mode: use ButtonFrameTemplate's built-in title and close button
            if f.TitleText then
                f.TitleText:SetText("Insert Icon")
            end
            if f.CloseButton then
                f.CloseButton:SetScript("OnClick", function() f:Hide() end)
            end
        end

        f:SetScript("OnShow", function()
            if BNB.ApplyMainWindowSkin then BNB.ApplyMainWindowSkin() end
        end)
        f:SetScript("OnKeyDown", function(_, key)
            if key == "ESCAPE" then f:Hide() end
            f:SetPropagateKeyboardInput(key ~= "ESCAPE")
        end)
        f:EnableKeyboard(true)

        -- ── Tabs ─────────────────────────────────────────────────────────────
        local TAB_LABELS = { "BNB Icons", "Blizzard Icon" }
        local tabPanels  = {}

        local function SelectIcoTab(idx)
            for i = 1, 2 do
                if tabPanels[i] then
                    if i == idx then tabPanels[i]:Show()
                    else             tabPanels[i]:Hide() end
                end
            end
            f._activeTab = idx
        end

        local tabCtrl
        if skinMode and BNB.CreateSkinTabs then
            tabCtrl = BNB.CreateSkinTabs(f, TAB_LABELS, function(idx)
                SelectIcoTab(idx)
            end)
            tabCtrl.frame:SetPoint("TOPLEFT",  f, "TOPLEFT",  0, -TITLE_H)
            tabCtrl.frame:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, -TITLE_H)
        else
            local tpl = (C_XMLUtil and C_XMLUtil.GetTemplateInfo
                and C_XMLUtil.GetTemplateInfo("PanelTopTabButtonTemplate"))
                and "PanelTopTabButtonTemplate" or "PanelTabButtonTemplate"
            local lastBtn = nil
            local tabBtns = {}
            for i, label in ipairs(TAB_LABELS) do
                local btn = CreateFrame("Button", "BNBIcoDialogTab"..i, f, tpl)
                btn:SetText(label)
                pcall(function()
                    if tpl == "PanelTopTabButtonTemplate" then
                        PanelTemplates_TabResize(btn, 15, nil, 80)
                    else PanelTemplates_TabResize(btn, 0) end
                end)
                btn:SetID(i)
                if lastBtn then btn:SetPoint("LEFT", lastBtn, "RIGHT", 5, 0)
                else             btn:SetPoint("TOPLEFT", f, "TOPLEFT", 7, -TITLE_H + 4) end
                btn:SetScript("OnClick", function(self)
                    local idx = self:GetID()
                    SelectIcoTab(idx)
                    for j = 1, 2 do
                        if tabBtns[j] then
                            if j == idx then PanelTemplates_SelectTab(tabBtns[j])
                            else             PanelTemplates_DeselectTab(tabBtns[j]) end
                        end
                    end
                end)
                tabBtns[i] = btn
                lastBtn = btn
            end
            PanelTemplates_SetNumTabs(f, 2); f.numTabs = 2
            f._tabBtns = tabBtns
        end

        -- ── Shared state ──────────────────────────────────────────────────────
        local selIconPath = nil  -- full icon path currently selected
        local selSize     = 25

        -- Forward declarations used across tab panels and shared bottom section
        local prevTex, prevBg, sizeEb
        local function RefreshIcoPreview(path)
            selIconPath = path
            if path and path ~= "" then
                pcall(function() prevTex:SetTexture(path) end)
                prevBg:Show()
            else
                prevTex:SetTexture(nil)
                prevBg:Hide()
            end
        end

        -- ── TAB 1: BNB Icons (manifest grid + search) ─────────────────────────
        local panel1 = CreateFrame("Frame", nil, f)
        panel1:SetPoint("TOPLEFT",     f, "TOPLEFT",  0,     -CONTENT_TOP)
        panel1:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0,  BOTTOM_H)
        tabPanels[1] = panel1

        -- Search field (left ~70% of the row)
        local searchEb = CreateFrame("EditBox", nil, panel1,
            "BackdropTemplate")
        BNB.EnsureBackdrop(searchEb); BNB.SetBackdropDark(searchEb)
        searchEb:SetPoint("TOPLEFT", panel1, "TOPLEFT", DPAD, -4)
        searchEb:SetSize(SEARCH_W, 22)
        searchEb:SetFontObject("GameFontNormal"); searchEb:SetAutoFocus(false)
        searchEb:SetMaxLetters(64); searchEb:SetTextInsets(4, 4, 0, 0)
        searchEb:SetScript("OnEscapePressed", function() f:Hide() end)
        BNB.AddPlaceholder(searchEb, "Search icons...", 0.40, 0.40, 0.40)

        -- Size field (right ~30% of the same row, shared across tabs)
        sizeEb = CreateFrame("EditBox", nil, panel1,
            "BackdropTemplate")
        BNB.EnsureBackdrop(sizeEb); BNB.SetBackdropDark(sizeEb)
        sizeEb:SetPoint("TOPLEFT", panel1, "TOPLEFT",
            DPAD + SEARCH_W + SIZE_GAP, -4)
        sizeEb:SetSize(SIZE_EB_W, 22)
        sizeEb:SetFontObject("GameFontNormal"); sizeEb:SetAutoFocus(false)
        sizeEb:SetMaxLetters(4); sizeEb:SetTextInsets(4, 4, 0, 0)
        sizeEb:SetNumeric(false); sizeEb:SetText("25")
        sizeEb:SetScript("OnEscapePressed", function() f:Hide() end)
        BNB.AddPlaceholder(sizeEb, "Size", 0.40, 0.40, 0.40)
        f._sizeEb = sizeEb

        -- Scroll frame for icon grid — fills all space below the search row
        local gridSF = CreateFrame("ScrollFrame", nil, panel1, "ScrollFrameTemplate")
        gridSF:SetPoint("TOPLEFT",     panel1, "TOPLEFT",  DPAD,  -30)
        gridSF:SetPoint("BOTTOMRIGHT", panel1, "BOTTOMRIGHT", -22, 0)
        if gridSF.ScrollBar then
            gridSF.ScrollBar:SetAlpha(0)
            gridSF:HookScript("OnScrollRangeChanged", function(_, _, yRange)
                gridSF.ScrollBar:SetAlpha((yRange or 0) > 1 and 1.0 or 0)
            end)
        end

        local gridCt = CreateFrame("Frame", nil, gridSF)
        gridCt:SetWidth(INNER_W - 22)
        gridCt:SetHeight(1)
        gridSF:SetScrollChild(gridCt)

        -- Build icon buttons (reuse pattern from NewNoteDialog)
        local icons   = BNB.ICON_MANIFEST or {}
        local icoBtns = {}

        local function ShortIconName(path)
            return (path or ""):match("([^\\/]+)$") or path or ""
        end

        local function LayoutGrid(list)
            -- Show/hide and reposition buttons based on filtered list
            local col, row = 0, 0
            for i, btn in ipairs(icoBtns) do
                local entry = list[i]
                if entry then
                    btn._path = entry
                    btn._tex:SetTexture(entry)
                    btn:ClearAllPoints()
                    btn:SetPoint("TOPLEFT", gridCt, "TOPLEFT",
                        CELL_PAD + col * (CELL + CELL_PAD),
                        -(CELL_PAD + row * (CELL + CELL_PAD)))
                    if btn._sel then btn._sel:SetShown(entry == selIconPath) end
                    btn:Show()
                    col = col + 1
                    if col >= GRID_COLS then col = 0; row = row + 1 end
                else
                    btn:Hide()
                end
            end
            local totalRows = math.max(1, math.ceil(#list / GRID_COLS))
            gridCt:SetHeight(totalRows * (CELL + CELL_PAD) + CELL_PAD)
            gridSF:SetVerticalScroll(0)
        end

        -- Pre-build one button per manifest entry (reused across filter calls)
        for i = 1, #icons do
            local btn = CreateFrame("Button", nil, gridCt)
            btn:SetSize(CELL, CELL)
            local tex = btn:CreateTexture(nil, "ARTWORK")
            tex:SetAllPoints(); tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            btn._tex = tex
            local selTx = btn:CreateTexture(nil, "OVERLAY")
            selTx:SetPoint("TOPLEFT",     btn, "TOPLEFT",     -2,  2)
            selTx:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT",  2, -2)
            selTx:SetColorTexture(0.2, 0.9, 0.2, 0.55); selTx:Hide()
            btn._sel = selTx
            local hi = btn:CreateTexture(nil, "HIGHLIGHT")
            hi:SetAllPoints(); hi:SetColorTexture(1, 1, 1, 0.25)
            btn:SetScript("OnEnter", function(s)
                GameTooltip:SetOwner(s, "ANCHOR_RIGHT")
                GameTooltip:AddLine(ShortIconName(s._path), 1, 1, 1)
                GameTooltip:Show()
            end)
            btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
            btn:SetScript("OnClick", function(s)
                RefreshIcoPreview(s._path)
                -- Update selection highlight
                for _, b in ipairs(icoBtns) do
                    if b._sel then b._sel:SetShown(b._path == selIconPath) end
                end
            end)
            icoBtns[i] = btn
        end

        local function FilterGrid(query)
            local q = query and query:lower() or ""
            if q == "" then
                LayoutGrid(icons)
            else
                local filtered = {}
                for _, path in ipairs(icons) do
                    if ShortIconName(path):lower():find(q, 1, true) then
                        filtered[#filtered + 1] = path
                    end
                end
                LayoutGrid(filtered)
            end
        end

        searchEb:SetScript("OnTextChanged", function(self, userInput)
            if not userInput then return end
            local text = self._showingPlaceholder and "" or (self:GetText() or "")
            FilterGrid(text)
        end)

        -- ── TAB 2: Blizzard Icon (manual name entry) ──────────────────────────
        local panel2 = CreateFrame("Frame", nil, f)
        panel2:SetPoint("TOPLEFT",     f, "TOPLEFT",  0,    -CONTENT_TOP)
        panel2:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0,  BOTTOM_H)
        tabPanels[2] = panel2

        -- Labels above fields
        local searchLbl2 = panel2:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        searchLbl2:SetPoint("TOPLEFT", panel2, "TOPLEFT", DPAD, -8)
        searchLbl2:SetTextColor(0.65, 0.65, 0.65)
        searchLbl2:SetText("Icon name")

        local sizeLbl2 = panel2:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        sizeLbl2:SetPoint("TOPLEFT", panel2, "TOPLEFT", DPAD + SEARCH_W + SIZE_GAP, -8)
        sizeLbl2:SetTextColor(0.65, 0.65, 0.65)
        sizeLbl2:SetText("Size")

        local descLbl = panel2:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        descLbl:SetPoint("TOPLEFT",  panel2, "TOPLEFT",  DPAD, -56)
        descLbl:SetPoint("TOPRIGHT", panel2, "TOPRIGHT", -DPAD, -56)
        descLbl:SetJustifyH("LEFT"); descLbl:SetWordWrap(true)
        descLbl:SetTextColor(0.65, 0.65, 0.65)
        descLbl:SetText("Type any WoW icon name, e.g.  INV_Misc_Note_01")

        -- Wowhead link line
        local whLbl = panel2:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        whLbl:SetPoint("TOPLEFT",  panel2, "TOPLEFT",  DPAD, -70)
        whLbl:SetPoint("TOPRIGHT", panel2, "TOPRIGHT", -DPAD, -70)
        whLbl:SetJustifyH("LEFT")
        whLbl:SetTextColor(0.40, 0.70, 1.0)
        whLbl:SetText("For icon names: www.wowhead.com/icons")
        -- Make the wowhead line clickable to copy the URL
        local whBtn = CreateFrame("Button", nil, panel2)
        whBtn:SetAllPoints(whLbl)
        whBtn:SetScript("OnClick", function()
            BNB.ShowClipboardHint("www.wowhead.com/icons", whBtn)
        end)
        whBtn:SetScript("OnEnter", function()
            GameTooltip:SetOwner(whBtn, "ANCHOR_TOP")
            GameTooltip:AddLine("Click to copy URL", 1, 1, 1)
            GameTooltip:Show()
        end)
        whBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

        -- Name field (same SEARCH_W width) + size label reuses sizeEb from tab 1
        -- sizeEb is parented to panel1; on tab 2 we show a second size field
        local nameEb = CreateFrame("EditBox", nil, panel2,
            "BackdropTemplate")
        BNB.EnsureBackdrop(nameEb); BNB.SetBackdropDark(nameEb)
        nameEb:SetPoint("TOPLEFT", panel2, "TOPLEFT", DPAD, -32)
        nameEb:SetSize(SEARCH_W, 22)
        nameEb:SetFontObject("GameFontNormal"); nameEb:SetAutoFocus(false)
        nameEb:SetMaxLetters(256); nameEb:SetTextInsets(4, 4, 0, 0)
        nameEb:SetScript("OnEscapePressed", function() f:Hide() end)
        nameEb:SetScript("OnEnterPressed", function()
            if f._insertBtn then f._insertBtn:Click() end
        end)
        nameEb:SetScript("OnTextChanged", function(self, userInput)
            if not userInput then return end
            local raw = self:GetText() or ""
            raw = raw:match("^%s*(.-)%s*$")
            if raw ~= "" then
                local path = "Interface\\Icons\\" .. raw
                RefreshIcoPreview(path)
            else
                RefreshIcoPreview(nil)
            end
        end)

        -- Size field on tab 2 (same position as tab 1, parented to panel2)
        -- Writes through to f._sizeEb2; Insert reads whichever tab is active.
        local sizeEb2 = CreateFrame("EditBox", nil, panel2,
            "BackdropTemplate")
        BNB.EnsureBackdrop(sizeEb2); BNB.SetBackdropDark(sizeEb2)
        sizeEb2:SetPoint("TOPLEFT", panel2, "TOPLEFT",
            DPAD + SEARCH_W + SIZE_GAP, -32)
        sizeEb2:SetSize(SIZE_EB_W, 22)
        sizeEb2:SetFontObject("GameFontNormal"); sizeEb2:SetAutoFocus(false)
        sizeEb2:SetMaxLetters(4); sizeEb2:SetTextInsets(4, 4, 0, 0)
        sizeEb2:SetNumeric(false); sizeEb2:SetText("25")
        sizeEb2:SetScript("OnEscapePressed", function() f:Hide() end)
        BNB.AddPlaceholder(sizeEb2, "Size", 0.40, 0.40, 0.40)
        f._sizeEb2 = sizeEb2

        -- ── Shared bottom section: preview + buttons ──────────────────────────
        -- Size field is now in the search row of each tab panel.

        -- Alignment dropdown (shared — applies to both BNB icons and Blizzard icons)
        local ICO_ALIGN_ITEMS = {
            { key = "",   label = "Inline (default)" },
            { key = ":l", label = "Left"             },
            { key = ":c", label = "Centre"           },
            { key = ":r", label = "Right"            },
        }
        local _icoAlign = ""
        local alignLbl = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        alignLbl:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", DPAD, BTN_H + DPAD * 2 + PREV_SIZE + 14)
        alignLbl:SetTextColor(0.65, 0.65, 0.65)
        alignLbl:SetText("Alignment")
        local alignDD = CreateFrame("DropdownButton", nil, f, "WowStyle1DropdownTemplate")
        alignDD:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", DPAD, BTN_H + DPAD * 2 + PREV_SIZE + 2)
        alignDD:SetWidth(INNER_W)
        alignDD:SetupMenu(function(_, root)
            for _, item in ipairs(ICO_ALIGN_ITEMS) do
                root:CreateRadio(item.label,
                    function() return _icoAlign == item.key end,
                    function()
                        _icoAlign = item.key
                        alignDD:GenerateMenu()
                    end)
            end
        end)
        f._getAlign   = function() return _icoAlign end
        f._resetAlign = function() _icoAlign = ""; alignDD:GenerateMenu() end

        -- Preview (centred, hidden until a texture resolves)
        prevBg = BNB.CreateBackdropFrame("Frame", nil, f)
        prevBg:SetSize(PREV_SIZE, PREV_SIZE)
        prevBg:SetPoint("BOTTOM", f, "BOTTOM", 0, BTN_H + DPAD * 2 + 4)
        BNB.SetBackdrop(prevBg, 0.04, 0.04, 0.06, 1, 0.25, 0.25, 0.28, 1)
        prevBg:Hide()
        prevTex = prevBg:CreateTexture(nil, "ARTWORK")
        prevTex:SetPoint("TOPLEFT",     prevBg, "TOPLEFT",     3,  -3)
        prevTex:SetPoint("BOTTOMRIGHT", prevBg, "BOTTOMRIGHT", -3,  3)
        prevTex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        prevTex:SetTexture(nil)
        f._prevTex = prevTex; f._prevBg = prevBg

        -- Buttons
        local cancelBtn = BNB.CreateButton(nil, f, "Cancel", 90, BTN_H)
        cancelBtn:SetPoint("BOTTOM", f, "BOTTOM", 53, DPAD)
        cancelBtn:SetScript("OnClick", function() f:Hide() end)

        local insertBtn = BNB.CreateButton(nil, f, "Insert", 90, BTN_H)
        insertBtn:SetPoint("BOTTOM", f, "BOTTOM", -53, DPAD)
        f._insertBtn = insertBtn

        -- ── Stored helpers ────────────────────────────────────────────────────
        f._filterGrid   = FilterGrid
        f._nameEb       = nameEb
        f._searchEb     = searchEb
        f._selectTab    = SelectIcoTab
        f._tabCtrl      = tabCtrl
        f._tabBtns2     = f._tabBtns  -- save ref for normal-mode tab highlight
        f._getPath      = function() return selIconPath end
        f._resetState   = function()
            selIconPath = nil
            prevTex:SetTexture(nil); prevBg:Hide()
            sizeEb:SetText("25")
            sizeEb2:SetText("25")
            searchEb:SetText("")
            BNB.AddPlaceholder(searchEb, "Search icons...", 0.40, 0.40, 0.40)
            nameEb:SetText("")
            FilterGrid("")
            -- Clear grid selection highlights
            for _, b in ipairs(icoBtns) do
                if b._sel then b._sel:Hide() end
            end
            -- Reset alignment dropdown
            if f._resetAlign  then f._resetAlign()  end
        end

        _icoDialog = f

        -- Default to tab 1
        SelectIcoTab(1)
        if tabCtrl and tabCtrl.Select then tabCtrl.Select(1) end
        if f._tabBtns then
            PanelTemplates_SelectTab(f._tabBtns[1])
            PanelTemplates_DeselectTab(f._tabBtns[2])
        end
    end  -- end lazy build

    -- Wire insert callback
    _icoDialog._insertBtn:SetScript("OnClick", function()
        local path = _icoDialog._getPath()
        -- Tab 2 may have a typed name not yet in selIconPath — check nameEb
        if _icoDialog._activeTab == 2 then
            local raw = (_icoDialog._nameEb:GetText() or ""):match("^%s*(.-)%s*$")
            if raw ~= "" then path = "Interface\\Icons\\" .. raw end
        end
        if not path or path == "" then return end
        local sz
        if _icoDialog._activeTab == 2 and _icoDialog._sizeEb2 then
            sz = math.abs(tonumber(_icoDialog._sizeEb2:GetText()) or 25)
        else
            sz = math.abs(tonumber(_icoDialog._sizeEb:GetText()) or 25)
        end
        sz = math.max(1, math.min(sz, 256))
        -- Strip the Interface\Icons\ prefix — {icon} tag uses bare icon names
        local iconName = path:match("[^\\/]+$") or path
        -- Alignment suffix (shared across both tabs)
        local alignSuffix = (_icoDialog._getAlign and _icoDialog._getAlign()) or ""
        local tag = string.format("{icon:%s:%d%s}", iconName, sz, alignSuffix)
        _icoDialog:Hide()
        insertFn(tag)
    end)

    -- Reset and show
    _icoDialog._resetState()
    _icoDialog:Show()
    -- Default to tab 1 on every open
    _icoDialog._selectTab(1)
    if _icoDialog._tabCtrl and _icoDialog._tabCtrl.Select then
        _icoDialog._tabCtrl.Select(1)
    end
    if _icoDialog._tabBtns2 then
        PanelTemplates_SelectTab(_icoDialog._tabBtns2[1])
        PanelTemplates_DeselectTab(_icoDialog._tabBtns2[2])
    end
    -- Focus search on tab 1
    C_Timer.After(0, function()
        if _icoDialog and _icoDialog:IsShown()
           and _icoDialog._searchEb then
            _icoDialog._searchEb:SetFocus()
        end
    end)
end

--------------------------------------------------------------------------------
-- EMPTY STATE  (Welcome panel — shown when no note is selected)
--------------------------------------------------------------------------------
local function BuildEmptyState(parent)
    local f = CreateFrame("Frame", nil, parent)
    f:SetAllPoints()

    -- ── Static layout constants ──────────────────────────────────────────────
    local PAD_TOP   = 14
    local LINE_PAD  = 6

    -- ── Greeting ─────────────────────────────────────────────────────────────
    local greetLbl = f:CreateFontString(nil, "OVERLAY")
    greetLbl:SetPoint("TOP", f, "TOP", 0, -PAD_TOP)
    greetLbl:SetJustifyH("CENTER")
    pcall(function()
        local boldPath = BNB.GetBoldFont and BNB.GetBoldFont()
        if boldPath then greetLbl:SetFont(boldPath, 15, "")
        else greetLbl:SetFontObject("GameFontNormal") end
    end)
    greetLbl:SetTextColor(0.9, 0.9, 0.9)

    -- ── Clock ─────────────────────────────────────────────────────────────────
    local clockLbl = f:CreateFontString(nil, "OVERLAY")
    clockLbl:SetPoint("TOP", greetLbl, "BOTTOM", 0, -(LINE_PAD + 4))
    clockLbl:SetJustifyH("CENTER")
    pcall(function()
        local boldPath = BNB.GetBoldFont and BNB.GetBoldFont()
        if boldPath then clockLbl:SetFont(boldPath, 34, "")
        else clockLbl:SetFontObject("GameFontNormalHuge") end
    end)
    clockLbl:SetTextColor(1, 1, 1)

    -- ── Date ─────────────────────────────────────────────────────────────────
    local dateLbl = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    dateLbl:SetPoint("TOP", clockLbl, "BOTTOM", 0, -LINE_PAD)
    dateLbl:SetJustifyH("CENTER")
    dateLbl:SetTextColor(0.75, 0.75, 0.75)

    -- ── Day / night icon ─────────────────────────────────────────────────────
    local timeIcon = f:CreateTexture(nil, "ARTWORK")
    timeIcon:SetSize(80, 80)
    timeIcon:SetPoint("TOP", dateLbl, "BOTTOM", 0, -(LINE_PAD + 2))

    -- ── Random quote ─────────────────────────────────────────────────────────
    local quoteLbl = f:CreateFontString(nil, "OVERLAY")
    quoteLbl:SetPoint("TOP", timeIcon, "BOTTOM", 0, -(LINE_PAD + 2))
    quoteLbl:SetWidth(math.floor((parent:GetWidth() or 500) * 0.70))
    quoteLbl:SetJustifyH("CENTER")
    pcall(function()
        local bodyPath = BNB.GetBodyFont and select(1, BNB.GetBodyFont())
        if bodyPath then quoteLbl:SetFont(bodyPath, 12, "")
        else quoteLbl:SetFontObject("GameFontNormalSmall") end
    end)
    quoteLbl:SetTextColor(0.65, 0.65, 0.65)

    -- Update quote width when panel resizes
    f:SetScript("OnSizeChanged", function(self, w)
        quoteLbl:SetWidth(math.floor(w * 0.70))
    end)

    -- ── "Select a note" hint ─────────────────────────────────────────────────
    local hintLbl = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    hintLbl:SetPoint("TOP", quoteLbl, "BOTTOM", 0, -(LINE_PAD + 28))
    hintLbl:SetJustifyH("CENTER")
    hintLbl:SetTextColor(unpack(COL_GREY))
    hintLbl:SetText("Select a note or create a new one")

    -- ── Create a new note button ─────────────────────────────────────────────
    -- In skin mode use a backdrop-based skin button (avoids NineSlice tint issues).
    -- In normal mode use the fancy large WoW template.
    local newBtn
    local skinMode = BigNoteBoxDB and BigNoteBoxDB.skinMode
    if skinMode then
        newBtn = BNB.CreateSkinButton(nil, f, "Create a new note", 200, 40, 16)
    else
        local tpl = "SharedButtonLargeTemplate"
        if not (C_XMLUtil and C_XMLUtil.GetTemplateInfo
                and C_XMLUtil.GetTemplateInfo(tpl)) then
            tpl = "UIPanelDynamicResizeButtonTemplate"
        end
        if not (C_XMLUtil and C_XMLUtil.GetTemplateInfo
                and C_XMLUtil.GetTemplateInfo(tpl)) then
            tpl = "UIPanelButtonTemplate"
        end
        newBtn = CreateFrame("Button", nil, f, tpl)
        newBtn:SetSize(200, 40)
        pcall(function() DynamicResizeButton_Resize(newBtn) end)
        newBtn:SetText("Create a new note")
        local bfs = newBtn:GetFontString()
        if bfs then pcall(function() bfs:SetFont("Fonts\\FRIZQT__.TTF", 16, "") end) end
    end
    newBtn:SetPoint("TOP", hintLbl, "BOTTOM", 0, -14)
    newBtn:SetScript("OnClick", function()
        if BNB.CreateNewNote then BNB.CreateNewNote() end
    end)

    -- ── Dynamic sections container ────────────────────────────────────────────
    -- Location notes header
    local locHeader = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    locHeader:SetJustifyH("CENTER")
    locHeader:SetTextColor(0.9, 0.82, 0.5)
    -- Text is set dynamically in RefreshIconRows with the current zone name.
    locHeader:Hide()

    -- Favorite notes header
    local favHeader = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    favHeader:SetJustifyH("CENTER")
    favHeader:SetTextColor(0.9, 0.82, 0.5)
    favHeader:SetText(L["WELCOME_FAV_NOTES"])
    favHeader:Hide()

    -- Containers for icon rows (rebuilt on each show via orphan pattern)
    -- We store them on the frame for cleanup access.
    f._locRowFrame = nil
    f._favRowFrame = nil

    -- Hide row frames when the welcome panel itself hides (e.g. window close),
    -- so they don't linger on screen as parentless frames.
    f:SetScript("OnHide", function()
        if f._locRowFrame then f._locRowFrame:Hide() end
        if f._favRowFrame then f._favRowFrame:Hide() end
    end)

    -- ── Footer buttons ────────────────────────────────────────────────────────
    local importBtn = BNB.CreateButton(nil, f, L["WELCOME_IMPORT_BTN"], 140, 28)
    importBtn:SetPoint("BOTTOM", f, "BOTTOM", -80, 4)
    importBtn:SetScript("OnClick", function()
        local win = GetImportFrame()
        win:Show()
        if win._importEB then
            win._importEB:SetText("")
            win._importEB:SetFocus()
        end
    end)
    importBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Import Notes", 1, 1, 1)
        GameTooltip:AddLine("Paste a BigNoteBox JSON export to import notes.", 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)
    importBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    local configBtn = BNB.CreateButton(nil, f, L["WELCOME_CONFIG_BTN"], 140, 28)
    configBtn:SetPoint("BOTTOM", f, "BOTTOM", 80, 4)
    configBtn:SetScript("OnClick", function()
        if BNB.OpenConfig then BNB.OpenConfig() end
        -- Refresh label immediately after the toggle so it reflects the new state.
        -- Also installs the config frame hooks on first open (lazy singleton).
        C_Timer.After(0, function() configBtn:RefreshLabel() end)
    end)
    configBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        local cfgOpen = _G["BigNoteBoxConfigFrame"] and _G["BigNoteBoxConfigFrame"]:IsShown()
        GameTooltip:AddLine(cfgOpen and "Close Config" or "Open Config", 1, 1, 1)
        GameTooltip:AddLine("Open the BigNoteBox settings window.", 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)
    configBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    -- Refreshes the button label to reflect whether config is currently open.
    -- Called by RefreshWelcomePanel so it updates each time the panel shows.
    function configBtn:RefreshLabel()
        local cfgOpen = _G["BigNoteBoxConfigFrame"] and _G["BigNoteBoxConfigFrame"]:IsShown()
        self:SetText(cfgOpen and L["WELCOME_CLOSE_CONFIG_BTN"] or L["WELCOME_CONFIG_BTN"])
    end

    -- Skin buttons handle their own colour via OnShow — no extra tint pass needed.

    -- ── Refresh functions ─────────────────────────────────────────────────────
    -- Forward-declared so RefreshWelcomePanel can call RefreshIconRows before
    -- its body is defined below.
    local RefreshIconRows
    local function RefreshWelcomePanel()
        -- Greeting with class-colored name
        local playerName  = UnitName("player") or "Adventurer"
        local classFile   = select(2, UnitClass("player"))
        local classColors = RAID_CLASS_COLORS
        local nameColor   = classColors and classFile and classColors[classFile]
        local r, g, b     = 1, 0.82, 0
        if nameColor then r, g, b = nameColor.r, nameColor.g, nameColor.b end
        local coloredName = string.format("|cff%02x%02x%02x%s|r",
            math.floor(r * 255), math.floor(g * 255), math.floor(b * 255), playerName)
        greetLbl:SetText(GetGreeting() .. ", " .. coloredName .. "!")

        -- Clock + date + icon
        clockLbl:SetText(GetClockString())
        dateLbl:SetText(GetDateString())
        timeIcon:SetTexture(GetTimeIcon())

        -- Quote (session-stable; set once at login via RandomQuotes.lua)
        local q = BNB._sessionQuote or ""
        quoteLbl:SetText(q ~= "" and q or "")

        -- Sync config button label with config window open state
        configBtn:RefreshLabel()

        -- ── Destroy old dynamic icon rows (orphan pattern) ──────────────────
        RefreshIconRows()
    end

    -- Rebuilds only the location/favorite icon sections. Called by both
    -- RefreshWelcomePanel and the RefreshNoteList hook below.
    RefreshIconRows = function()
        if f._locRowFrame then
            f._locRowFrame:Hide()
            f._locRowFrame:SetParent(nil)
            f._locRowFrame = nil
        end
        if f._favRowFrame then
            f._favRowFrame:Hide()
            f._favRowFrame:SetParent(nil)
            f._favRowFrame = nil
        end

        -- ── Location notes ────────────────────────────────────────────────────
        -- Sections anchor upward from above the footer buttons so they always
        -- float just above Import/Open Config regardless of content height.
        -- Footer buttons are at y=4, height=28 => top of buttons ~y=36.
        -- We start the stack at y=48 above the frame bottom.
        local locNotes = GetLocationNotes(10)
        local favNotes = GetFavoriteNotes(10)

        -- Build the location header label from the current zone/instance name.
        local inInst, instType = IsInInstance()
        local zoneName
        if inInst and instType ~= "none" then
            zoneName = GetInstanceInfo and select(1, GetInstanceInfo()) or GetRealZoneText()
        else
            zoneName = GetZoneText()
        end
        locHeader:SetText("Notes for " .. (zoneName or "this area"))

        -- Calculate how many rows we have to stack, then anchor bottom-up.
        -- favRowContainer bottom = f bottom + 48
        -- favHeader       bottom = favRowContainer top + 6  (or skip if no favs)
        -- locRowContainer bottom = favHeader top + 14       (or favRowContainer top + 14 if no favs)
        -- locHeader       bottom = locRowContainer top + 6  (or skip if no loc)

        local STACK_BASE = 48   -- px above frame bottom where the stack starts

        if #favNotes > 0 then
            favHeader:Show()
            local favRow = CreateFrame("Frame", nil, f)
            favRow:SetPoint("BOTTOMLEFT",  f, "BOTTOMLEFT",  0, STACK_BASE)
            favRow:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, STACK_BASE)
            favRow:SetHeight(ICON_BTN_SIZE)
            BuildNoteIconRow(favRow, favNotes, 0)
            f._favRowFrame = favRow

            favHeader:ClearAllPoints()
            favHeader:SetPoint("BOTTOM", favRow, "TOP", 0, 6)

            if #locNotes > 0 then
                locHeader:Show()
                local locRow = CreateFrame("Frame", nil, f)
                locRow:SetPoint("BOTTOM", favHeader, "TOP", 0, 14)
                locRow:SetPoint("LEFT",   f, "LEFT",  0, 0)
                locRow:SetPoint("RIGHT",  f, "RIGHT", 0, 0)
                locRow:SetHeight(ICON_BTN_SIZE)
                BuildNoteIconRow(locRow, locNotes, 0)
                f._locRowFrame = locRow

                locHeader:ClearAllPoints()
                locHeader:SetPoint("BOTTOM", locRow, "TOP", 0, 6)
            else
                locHeader:Hide()
            end
        elseif #locNotes > 0 then
            favHeader:Hide()
            locHeader:Show()
            local locRow = CreateFrame("Frame", nil, f)
            locRow:SetPoint("BOTTOMLEFT",  f, "BOTTOMLEFT",  0, STACK_BASE)
            locRow:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, STACK_BASE)
            locRow:SetHeight(ICON_BTN_SIZE)
            BuildNoteIconRow(locRow, locNotes, 0)
            f._locRowFrame = locRow

            locHeader:ClearAllPoints()
            locHeader:SetPoint("BOTTOM", locRow, "TOP", 0, 6)
        else
            locHeader:Hide()
            favHeader:Hide()
        end
    end

    -- Store refresh function so it can be called externally if needed
    f.Refresh = RefreshWelcomePanel

    -- Lightweight refresh: just the time-sensitive display fields.
    -- Called by the 30-second ticker; avoids rebuilding icon rows on every tick.
    local function RefreshClock()
        if not f:IsShown() then return end
        clockLbl:SetText(GetClockString())
        dateLbl:SetText(GetDateString())
        timeIcon:SetTexture(GetTimeIcon())
        -- Re-run greeting in case hour boundary crossed (morning -> afternoon etc.)
        local playerName  = UnitName("player") or "Adventurer"
        local classFile   = select(2, UnitClass("player"))
        local classColors = RAID_CLASS_COLORS
        local nameColor   = classColors and classFile and classColors[classFile]
        local r, g, b     = 1, 0.82, 0
        if nameColor then r, g, b = nameColor.r, nameColor.g, nameColor.b end
        local coloredName = string.format("|cff%02x%02x%02x%s|r",
            math.floor(r * 255), math.floor(g * 255), math.floor(b * 255), playerName)
        greetLbl:SetText(GetGreeting() .. ", " .. coloredName .. "!")
    end

    -- Run full refresh every time the panel becomes visible, and keep a
    -- 30-second repeating ticker running while it is shown so the clock
    -- stays current without rebuilding the icon rows each time.
    local _clockTicker
    f:SetScript("OnShow", function()
        RefreshWelcomePanel()
        if _clockTicker then _clockTicker:Cancel() end
        _clockTicker = C_Timer.NewTicker(30, RefreshClock)
    end)
    f:HookScript("OnHide", function()
        if _clockTicker then _clockTicker:Cancel(); _clockTicker = nil end
    end)

    -- When config is opened or closed via any path, refresh the label.
    -- hooksecurefunc covers the toolbar/slash/welcome-button toggle paths.
    -- The OnHide hook on the config frame covers closing via its own X button.
    hooksecurefunc(BNB, "OpenConfig", function()
        if f:IsShown() then
            C_Timer.After(0, function()
                if f:IsShown() then configBtn:RefreshLabel() end
            end)
        end
        -- Install the OnHide hook now that the config frame exists (lazy singleton).
        local cf = _G["BigNoteBoxConfigFrame"]
        if cf and not cf._bnbWelcomeLabelHooked then
            cf._bnbWelcomeLabelHooked = true
            cf:HookScript("OnHide", function()
                if f:IsShown() then configBtn:RefreshLabel() end
            end)
        end
    end)

    -- When any note changes (favorite toggle, context set, create, delete),
    -- RefreshNoteList fires. If the welcome panel is visible at that moment,
    -- rebuild the icon rows immediately so the user sees the change without
    -- having to close and reopen the panel.
    hooksecurefunc(BNB, "RefreshNoteList", function()
        if f:IsShown() and RefreshIconRows then
            RefreshIconRows()
        end
    end)

    return f
end

--------------------------------------------------------------------------------
-- TITLE FIELD
-- AddPlaceholder called ONCE at build time.
--------------------------------------------------------------------------------
local function BuildTitleField(parent)
    local bg = BNB.CreateBackdropFrame("Frame", nil, parent)
    bg:SetPoint("TOPLEFT",  parent, "TOPLEFT",  PAD,  -PAD)
    bg:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -PAD, -PAD)
    bg:SetHeight(36)
    BNB.SetBackdrop(bg, 0.06, 0.06, 0.09, 0, 0.30, 0.30, 0.32, 0)

    local eb = CreateFrame("EditBox", nil, bg)
    eb:SetPoint("TOPLEFT",    bg, "TOPLEFT",    6, 0)
    eb:SetPoint("BOTTOMRIGHT",bg, "BOTTOMRIGHT",-6, 0)
    local boldPath = BNB.GetBoldFont and BNB.GetBoldFont()
    if boldPath then
        pcall(function() eb:SetFont(boldPath, 20, "") end)
    else
        local font, _, flags = GameFontNormalHuge:GetFont()
        if font then eb:SetFont(font, 20, flags or "")
        else eb:SetFontObject("GameFontNormalLarge") end
    end
    eb:SetAutoFocus(false)
    eb:SetMaxLetters(200)
    eb:SetTextInsets(2, 2, 2, 2)

    -- Underline (always visible)
    local underline = parent:CreateTexture(nil, "ARTWORK")
    underline:SetHeight(1)
    underline:SetPoint("TOPLEFT",  bg, "BOTTOMLEFT",  0, -1)
    underline:SetPoint("TOPRIGHT", bg, "BOTTOMRIGHT", 0, -1)
    underline:SetColorTexture(0.16, 0.16, 0.18, 1)

    -- Timestamp strip anchored below the underline
    local tsStrip = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    tsStrip:SetPoint("TOPLEFT",  underline, "BOTTOMLEFT",  2, -2)
    tsStrip:SetPoint("TOPRIGHT", underline, "BOTTOMRIGHT", -2, -2)
    tsStrip:SetHeight(TSTAMP_H)
    tsStrip:SetJustifyH("LEFT")
    tsStrip:SetText("")
    if BigNoteBoxDB and BigNoteBoxDB.skinMode and BNB.GetSkinPreset then
        local p = BNB.GetSkinPreset()
        local br, bg_, bb = BNB.SkinBorderOf(p)
        tsStrip:SetTextColor(br * 0.90, bg_ * 0.90, bb * 0.90)
        BNB.RegisterSkinLabel(tsStrip, 0.90)
    else
        tsStrip:SetTextColor(0.55, 0.55, 0.55)
    end

    -- Invisible hover frame over the timestamp strip.
    -- Always shows full detail tooltip: absolute dates, zone, and coords.
    local tsHover = CreateFrame("Frame", nil, parent)
    tsHover:SetPoint("TOPLEFT",  underline, "BOTTOMLEFT",  0, -1)
    tsHover:SetPoint("TOPRIGHT", underline, "BOTTOMRIGHT", 0, -1)
    tsHover:SetHeight(TSTAMP_H + 2)
    tsHover:EnableMouse(true)
    tsHover:SetScript("OnEnter", function(self)
        local note = BNB._currentNoteID and BNB.GetNote(BNB._currentNoteID)
        if not note then return end
        local db    = BigNoteBoxDB
        local use24 = db == nil or db.use24Hour ~= false
        local function AbsTime(ts)
            if not ts or ts == 0 then return nil end
            local d = date("%Y-%m-%d", ts)
            local t
            if use24 then
                t = date("%H:%M", ts)
            else
                local h = tonumber(date("%H", ts))
                local ampm = h >= 12 and "pm" or "am"
                h = h % 12; if h == 0 then h = 12 end
                t = h .. ":" .. date("%M", ts) .. " " .. ampm
            end
            return d .. " " .. t
        end
        local created = note.created and AbsTime(note.created)
        local updated = note.updated and AbsTime(note.updated)
        if not created and not updated then return end
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        if created then GameTooltip:AddLine("Created " .. created, 0.7, 0.7, 0.7) end
        if updated then GameTooltip:AddLine("Edited "  .. updated, 0.7, 0.7, 0.7) end
        local zone = note.coordZone or "Unknown"
        GameTooltip:AddLine("Zone: " .. zone, 0.7, 0.7, 0.7)
        if note.coordX and note.coordY then
            GameTooltip:AddLine(string.format("Coords: %.2f %.2f", note.coordX, note.coordY), 0.7, 0.7, 0.7)
        end
        GameTooltip:Show()
    end)
    tsHover:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Word/char count label (M) — right-aligned in the same strip
    local statsStrip = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    statsStrip:SetPoint("TOPRIGHT",  underline, "BOTTOMRIGHT", -2, -2)
    statsStrip:SetPoint("TOPLEFT",   underline, "BOTTOMLEFT",  2,  -2)
    statsStrip:SetHeight(TSTAMP_H)
    statsStrip:SetJustifyH("RIGHT")
    statsStrip:SetText("")
    if BigNoteBoxDB and BigNoteBoxDB.skinMode and BNB.GetSkinPreset then
        local p = BNB.GetSkinPreset()
        local br, bg_, bb = BNB.SkinBorderOf(p)
        statsStrip:SetTextColor(br * 0.90, bg_ * 0.90, bb * 0.90)
        BNB.RegisterSkinLabel(statsStrip, 0.90)
    else
        statsStrip:SetTextColor(0.55, 0.55, 0.55)
    end

    local phFocusGained, phFocusLost

    eb:SetScript("OnEditFocusGained", function(self)
        if bg.SetBackdropColor then
            bg:SetBackdropColor(0.06, 0.06, 0.09, 0.85)
            bg:SetBackdropBorderColor(0.35, 0.35, 0.38, 1)
        end
        if phFocusGained then phFocusGained(self) end
    end)
    eb:SetScript("OnEditFocusLost", function(self)
        if bg.SetBackdropColor then
            bg:SetBackdropColor(0.06, 0.06, 0.09, 0)
            bg:SetBackdropBorderColor(0.30, 0.30, 0.32, 0)
        end
        if phFocusLost then phFocusLost(self) end
    end)

    BNB.AddPlaceholder(eb, L["NOTE_TITLE_HINT"], 0.35, 0.35, 0.35)

    phFocusGained = eb:GetScript("OnEditFocusGained")
    phFocusLost   = eb:GetScript("OnEditFocusLost")
    eb:SetScript("OnEditFocusGained", function(self)
        if bg.SetBackdropColor then
            bg:SetBackdropColor(0.06, 0.06, 0.09, 0.85)
            bg:SetBackdropBorderColor(0.35, 0.35, 0.38, 1)
        end
        if phFocusGained then phFocusGained(self) end
    end)
    -- Cancel an unsaved new note: if the title is empty when focus leaves the
    -- title box, check whether this is a "pending new note" (_pendingNewNoteID).
    -- If it is pending AND focus didn't move to the body or NoteConfig, show a
    -- discard confirmation popup. If the title has text, clear the pending flag
    -- (note is now named — clicking away just saves normally).
    local function MaybeCancelNewNote()
        local id = BNB._currentNoteID
        if not id then return end
        local note = BNB.GetNote(id)
        if not note then return end
        local liveTitle = eb._showingPlaceholder and "" or (eb:GetText() or "")

        -- If title now has text, this note is no longer "pending" — nothing to do.
        if liveTitle ~= "" then
            if BNB._pendingNewNoteID == id then BNB._pendingNewNoteID = nil end
            return
        end

        -- Only act on pending new notes (notes created via CreateNewNote with no title yet).
        if BNB._pendingNewNoteID ~= id then return end

        -- Check where focus went. If it went to the body or to NoteConfig, leave
        -- the note alive — the user is still working on it.
        local kf = GetCurrentKeyboardFocus and GetCurrentKeyboardFocus()
        if kf == BNB._editorBody then return end
        local nc = _G["BigNoteBoxNoteConfigFrame"]
        if nc and nc:IsShown() then return end

        -- Focus went elsewhere — show the discard popup.
        StaticPopup_Show("BNB_DISCARD_NEW_NOTE")
    end

    -- Register the discard confirmation popup (once, idempotent).
    if not StaticPopupDialogs["BNB_DISCARD_NEW_NOTE"] then
        StaticPopupDialogs["BNB_DISCARD_NEW_NOTE"] = {
            text      = "This note has no title. Discard it?",
            button1   = "Discard",
            button2   = "Keep Editing",
            OnAccept  = function()
                local id = BNB._pendingNewNoteID
                BNB._pendingNewNoteID = nil
                if not id then return end
                BNB._currentNoteID = nil
                if BNB.PurgeNote        then BNB.PurgeNote(id) end
                if BNB.RefreshNoteList  then BNB.RefreshNoteList() end
                if BNB.LoadNoteInEditor then BNB.LoadNoteInEditor(nil) end
                -- Close NoteConfig if it was open for this note
                local nc = _G["BigNoteBoxNoteConfigFrame"]
                if nc and nc:IsShown() then nc:Hide() end
            end,
            OnCancel  = function()
                -- "Keep Editing" — re-focus the title field
                C_Timer.After(0.05, function()
                    if BNB._editorTitle then BNB._editorTitle:SetFocus() end
                end)
            end,
            timeout = 0, whileDead = true, hideOnEscape = false,
        }
    end

    eb:SetScript("OnEditFocusLost", function(self)
        if bg.SetBackdropColor then
            bg:SetBackdropColor(0.06, 0.06, 0.09, 0)
            bg:SetBackdropBorderColor(0.30, 0.30, 0.32, 0)
        end
        if phFocusLost then phFocusLost(self) end
        -- Defer so a click on the body editbox or NoteConfig registers first
        C_Timer.After(0.1, MaybeCancelNewNote)
    end)

    eb:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
        MaybeCancelNewNote()
    end)
    eb:SetScript("OnEnterPressed",  function(self)
        self:ClearFocus()
        if BNB._editorBody then BNB._editorBody:SetFocus() end
    end)
    eb:SetScript("OnTextChanged", function(self, userInput)
        if userInput and not self._showingPlaceholder then
            BNB.MarkDirty()
            -- Once the user has typed a title, the note is no longer "pending"
            local liveTitle = self._showingPlaceholder and "" or (self:GetText() or "")
            if liveTitle ~= "" and BNB._pendingNewNoteID == BNB._currentNoteID then
                BNB._pendingNewNoteID = nil
            end
            -- Live-sync NoteConfig title bar as the user types
            if BNB._syncNoteConfigTitle then BNB._syncNoteConfigTitle() end
        end
    end)

    return bg, eb, underline, tsStrip, statsStrip
end

--------------------------------------------------------------------------------
-- STATS STRIP (M) — "1,234 chars  •  187 words"
-- Right-aligned FontString in the timestamp strip row.
-- Updated on every body OnTextChanged and on note load.
--------------------------------------------------------------------------------
local function UpdateStatsStrip(text)
    local strip = BNB._editorStatsStrip
    if not strip then return end
    if not text or text == "" then
        strip:SetText("0 chars  •  0 words")
        return
    end
    local chars = #text
    local words = 0
    for _ in text:gmatch("%S+") do words = words + 1 end
    local function fmt(n)
        local s      = tostring(n)
        local result = ""
        local len    = #s
        for i = 1, len do
            if i > 1 and (len - i + 1) % 3 == 0 then result = result .. "," end
            result = result .. s:sub(i, i)
        end
        return result
    end
    strip:SetText(fmt(chars) .. " chars  •  " .. fmt(words) .. " words")
end

--------------------------------------------------------------------------------
-- BODY SCROLL EDITBOX
-- AddPlaceholder called ONCE at build time.
-- topAnchor: the frame to anchor TOPLEFT to (WYSIWYG bar, or tsStrip if bar
-- is hidden). BNB.UpdateBodyTopAnchor() re-anchors live on bar toggle.
--------------------------------------------------------------------------------
local function BuildBodyField(parent, topAnchor)
    local bodyPath, bodySize
    if BNB.GetBodyFont then
        bodyPath, bodySize = BNB.GetBodyFont()
    end
    bodySize = bodySize or (BigNoteBoxDB and BigNoteBoxDB.fontSize) or 12

    local sf, eb = BNB.CreateScrolledEditBox("BigNoteBoxBodyScroll", parent, bodySize)
    if bodyPath then
        pcall(function() eb:SetFont(bodyPath, bodySize, "") end)
    end

    sf:SetPoint("TOPLEFT",     topAnchor, "BOTTOMLEFT",  PAD, -4)
    sf:SetPoint("BOTTOMRIGHT", parent,    "BOTTOMRIGHT", -22,  TOOLBAR_H + TAG_STRIP_H + PAD)

    BNB.AddPlaceholder(eb, L["NOTE_BODY_HINT"], 0.35, 0.35, 0.35)

    -- Drag-and-drop + Insert Info right-click menu
    if BNB.WireDropTarget       then BNB.WireDropTarget(eb)       end
    if BNB.WireInsertInfoTarget  then BNB.WireInsertInfoTarget(eb) end

    eb:SetScript("OnTextChanged", function(self, userInput)
        if not self._showingPlaceholder then
            if userInput then
                BNB.MarkDirty()
                -- Notify live preview directly (hooksecurefunc on MarkDirty is
                -- unreliable for plain Lua closures — call directly instead)
                if BNB.RichPreview then BNB.RichPreview.ScheduleRender() end
                if BNB._editorBodyScroll and BNB._editorBodyScroll.UpdateScrollbar then
                    BNB._editorBodyScroll:UpdateScrollbar()
                end
                -- Undo snapshot — hybrid debounce + forced interval.
                -- Both timings are user-configurable in Config > Editor.
                local id = BNB._currentNoteID
                if id and not BNB._undoActive then
                    local idleDelay = (BigNoteBoxDB and BigNoteBoxDB.undoIdleDelay)    or 0.8
                    local forcedInt = (BigNoteBoxDB and BigNoteBoxDB.undoForcedInterval) or 3.0
                    -- First snapshot for this note: push immediately so Undo
                    -- always has a "before" state to return to.
                    if not BNB._undoSnap[id] or BNB._undoStack[id] == nil then
                        BNB.UndoPush(id, self:GetText() or "", self:GetCursorPosition() or 0)
                        if BNB._refreshUndoButtons then BNB._refreshUndoButtons() end
                    else
                        -- Reset idle debounce
                        if _undoTimers[id] then
                            _undoTimers[id]:Cancel()
                            _undoTimers[id] = nil
                        end
                        _undoTimers[id] = C_Timer.NewTimer(idleDelay, function()
                            _undoTimers[id] = nil
                            -- Also cancel any forced-interval timer -- idle won
                            if _undoForced and _undoForced[id] then
                                _undoForced[id]:Cancel()
                                _undoForced[id] = nil
                            end
                            if not BNB._undoActive then
                                BNB.UndoPush(id, self:GetText() or "", self:GetCursorPosition() or 0)
                                if BNB._refreshUndoButtons then BNB._refreshUndoButtons() end
                            end
                        end)
                        -- Start forced-interval timer only if not already running
                        if not _undoForced then _undoForced = {} end
                        if not _undoForced[id] then
                            _undoForced[id] = C_Timer.NewTimer(forcedInt, function()
                                _undoForced[id] = nil
                                -- Cancel the idle debounce -- forced wins
                                if _undoTimers[id] then
                                    _undoTimers[id]:Cancel()
                                    _undoTimers[id] = nil
                                end
                                if not BNB._undoActive then
                                    BNB.UndoPush(id, self:GetText() or "", self:GetCursorPosition() or 0)
                                    if BNB._refreshUndoButtons then BNB._refreshUndoButtons() end
                                end
                            end)
                        end
                    end
                end
            end
            UpdateStatsStrip(self:GetText())
        end
    end)

    -- Ctrl+Z = undo, Ctrl+Shift+Z or Ctrl+Y = redo.
    -- We only call SetPropagateKeyboardInput(false) for keys we consume.
    -- EditBox absorbs all other input natively — no else branch needed.
    eb:SetScript("OnKeyDown", function(self, key)
        local ctrl  = IsControlKeyDown()
        local shift = IsShiftKeyDown()

        if ctrl and key == "Z" and not shift then
            -- Undo
            self:SetPropagateKeyboardInput(false)
            local id = BNB._currentNoteID
            if id and BNB.UndoCanUndo(id) and not BNB._editorLocked then
                -- Cancel pending debounce and forced-interval timer
                if _undoTimers[id] then _undoTimers[id]:Cancel(); _undoTimers[id] = nil end
                if _undoForced[id]  then _undoForced[id]:Cancel();  _undoForced[id]  = nil end
                BNB._undoActive = true
                local text, cursor = BNB.UndoStep(id)
                if text then
                    self:SetText(text)
                    C_Timer.After(0, function() self:SetCursorPosition(cursor or 0) end)
                    BNB.MarkDirty()
                end
                BNB._undoActive = false
                if BNB._refreshUndoButtons then BNB._refreshUndoButtons() end
            end

        elseif ctrl and ((key == "Z" and shift) or key == "Y") then
            -- Redo
            self:SetPropagateKeyboardInput(false)
            local id = BNB._currentNoteID
            if id and BNB.UndoCanRedo(id) and not BNB._editorLocked then
                if _undoTimers[id] then _undoTimers[id]:Cancel(); _undoTimers[id] = nil end
                if _undoForced[id]  then _undoForced[id]:Cancel();  _undoForced[id]  = nil end
                BNB._undoActive = true
                local text, cursor = BNB.RedoStep(id)
                if text then
                    self:SetText(text)
                    C_Timer.After(0, function() self:SetCursorPosition(cursor or 0) end)
                    BNB.MarkDirty()
                end
                BNB._undoActive = false
                if BNB._refreshUndoButtons then BNB._refreshUndoButtons() end
            end
        end
    end)

    return sf, eb
end

--------------------------------------------------------------------------------
-- WYSIWYG FORMATTING TOOLBAR
-- Sits between the timestamp strip and the body scroll frame.
-- Toggle via BigNoteBoxDB.wysiwygBarVisible (persisted).
--
-- Left  (left-anchored):  Undo | Redo | divider | FontType | Dec | Inc | FontSize
-- Right (right-anchored): Restore | History | divider | CopyMove | Waypoint
--
-- BNB._editorWysiwygBar   — the bar frame (shown/hidden on toggle)
-- BNB._refreshUndoButtons — public function, refreshes undo/redo btn states
-- BNB._refreshWysiwygFont — public function, refreshes font controls on note switch
--------------------------------------------------------------------------------
local ASSETS_WY = "Interface\\AddOns\\BigNoteBox\\Assets\\Toolbar\\"

-- Font size preset list shown in the size dropdown quick-pick.
-- +/- buttons step 1pt at a time regardless of this list.
local WY_SIZE_PRESETS = { 8, 9, 10, 11, 12, 13, 14, 16, 18, 20, 24, 28, 32 }

local function BuildWysiwygBar(parent, tsStrip)
    local db = BigNoteBoxDB

    local bar = CreateFrame("Frame", "BigNoteBoxWysiwygBar", parent)
    bar:SetPoint("TOPLEFT",  tsStrip, "BOTTOMLEFT",  0, -2)
    bar:SetPoint("TOPRIGHT", tsStrip, "BOTTOMRIGHT",  0, -2)
    bar:SetHeight(WYSIWYG_H)

    -- Top edge line
    local sepT = bar:CreateTexture(nil, "ARTWORK")
    sepT:SetHeight(1)
    sepT:SetPoint("TOPLEFT",  bar, "TOPLEFT",  0, 0)
    sepT:SetPoint("TOPRIGHT", bar, "TOPRIGHT", 0, 0)
    if BigNoteBoxDB and BigNoteBoxDB.skinMode and BNB.GetSkinPreset then
        local p = BNB.GetSkinPreset()
        local br, bg_, bb = BNB.SkinBorderOf(p)
        sepT:SetColorTexture(br, bg_, bb, 0.20)
        BNB.RegisterSkinRule(sepT, 0.20)
    else
        sepT:SetColorTexture(0.22, 0.22, 0.24, 1)
    end

    -- Bottom edge line
    local sepB = bar:CreateTexture(nil, "ARTWORK")
    sepB:SetHeight(1)
    sepB:SetPoint("BOTTOMLEFT",  bar, "BOTTOMLEFT",  0, 0)
    sepB:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 0, 0)
    if BigNoteBoxDB and BigNoteBoxDB.skinMode and BNB.GetSkinPreset then
        local p = BNB.GetSkinPreset()
        local br, bg_, bb = BNB.SkinBorderOf(p)
        sepB:SetColorTexture(br, bg_, bb, 0.20)
        BNB.RegisterSkinRule(sepB, 0.20)
    else
        sepB:SetColorTexture(0.22, 0.22, 0.24, 1)
    end

    -- ── Shared helpers ────────────────────────────────────────────────────────

    -- Divider — consistent size/color used everywhere in this bar
    local function MakeDiv(anchorFrame, anchorPoint)
        local d = bar:CreateTexture(nil, "ARTWORK")
        d:SetSize(1, 16)
        d:SetPoint("LEFT", anchorFrame, anchorPoint or "RIGHT", 6, 0)
        if BigNoteBoxDB and BigNoteBoxDB.skinMode and BNB.GetSkinPreset then
            local p = BNB.GetSkinPreset()
            local br, bg_, bb = BNB.SkinBorderOf(p)
            d:SetColorTexture(br, bg_, bb, 0.25)
            BNB.RegisterSkinRule(d, 0.25)
        else
            d:SetColorTexture(0.16, 0.16, 0.18, 1)
        end
        return d
    end

    -- Icon button (20x20)
    local function WyBtn(icon, tip)
        local btn = CreateFrame("Button", nil, bar)
        btn:SetSize(20, 20)
        local tx = btn:CreateTexture(nil, "ARTWORK")
        tx:SetAllPoints()
        tx:SetTexture(ASSETS_WY .. icon)
        if BigNoteBoxDB and BigNoteBoxDB.skinMode and BNB.GetSkinPreset then
            local p  = BNB.GetSkinPreset()
            local br, bg_, bb = BNB.SkinBorderOf(p)
            tx:SetVertexColor(math.min(1, br * 2.2), math.min(1, bg_ * 2.2), math.min(1, bb * 2.2))
            BNB.RegisterSkinIconTex(tx, 2.2)
        end
        local hi = btn:CreateTexture(nil, "HIGHLIGHT")
        hi:SetAllPoints()
        hi:SetColorTexture(1, 1, 1, 0.18)
        btn._tx = tx
        btn.SetIconEnabled = function(self, en)
            self:SetEnabled(en)
            self:SetAlpha(en and 1.0 or 0.30)
            pcall(function() tx:SetDesaturated(not en) end)
        end
        btn:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:AddLine(tip, 1, 1, 1)
            GameTooltip:Show()
        end)
        btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
        btn:SetIconEnabled(false)
        return btn
    end

    -- ── LEFT SIDE ─────────────────────────────────────────────────────────────

    -- Undo / Redo
    local undoBtn = WyBtn("tb-undo", "Undo  (Ctrl+Z)")
    undoBtn:SetPoint("LEFT", bar, "LEFT", 6, 0)

    local redoBtn = WyBtn("tb-redo", "Redo  (Ctrl+Shift+Z / Ctrl+Y)")
    redoBtn:SetPoint("LEFT", undoBtn, "RIGHT", 4, 0)

    -- Wire undo
    undoBtn:SetScript("OnClick", function()
        local id = BNB._currentNoteID
        if not id or BNB._editorLocked then return end
        local eb = BNB._editorBody; if not eb then return end
        if _undoTimers[id] then _undoTimers[id]:Cancel(); _undoTimers[id] = nil end
        if _undoForced[id] then _undoForced[id]:Cancel(); _undoForced[id] = nil end
        BNB._undoActive = true
        local text, cursor = BNB.UndoStep(id)
        if text then
            eb:SetText(text)
            C_Timer.After(0, function() eb:SetCursorPosition(cursor or 0) end)
            BNB.MarkDirty()
        end
        BNB._undoActive = false
        if BNB._refreshUndoButtons then BNB._refreshUndoButtons() end
    end)

    -- Wire redo
    redoBtn:SetScript("OnClick", function()
        local id = BNB._currentNoteID
        if not id or BNB._editorLocked then return end
        local eb = BNB._editorBody; if not eb then return end
        if _undoTimers[id] then _undoTimers[id]:Cancel(); _undoTimers[id] = nil end
        if _undoForced[id] then _undoForced[id]:Cancel(); _undoForced[id] = nil end
        BNB._undoActive = true
        local text, cursor = BNB.RedoStep(id)
        if text then
            eb:SetText(text)
            C_Timer.After(0, function() eb:SetCursorPosition(cursor or 0) end)
            BNB.MarkDirty()
        end
        BNB._undoActive = false
        if BNB._refreshUndoButtons then BNB._refreshUndoButtons() end
    end)

    BNB._refreshUndoButtons = function()
        local id     = BNB._currentNoteID
        local locked = BNB._editorLocked
        undoBtn:SetIconEnabled(not locked and BNB.UndoCanUndo(id))
        redoBtn:SetIconEnabled(not locked and BNB.UndoCanRedo(id))
    end

    bar._undoBtn = undoBtn
    bar._redoBtn = redoBtn

    -- Divider: undo/redo | font controls
    local divFont = MakeDiv(redoBtn)

    -- ── Font type dropdown ────────────────────────────────────────────────────
    -- Truncated label button that opens a WowStyle1 menu listing all fonts.
    -- Width chosen to fit truncated font names (~90px) without crowding.
    local FONT_DD_W = 90
    local FONT_BTN_H = 20

    local fontDDBg = BNB.CreateBackdropFrame("Frame", nil, bar)
    fontDDBg:SetSize(FONT_DD_W, FONT_BTN_H)
    fontDDBg:SetPoint("LEFT", divFont, "RIGHT", 6, 0)
    local function ApplyFontDDBgSkin()
        local p  = BNB.GetSkinPreset and BNB.GetSkinPreset()
        if not p then return end
        local r  = math.min(1, p.r + p.lift * 1.5)
        local g  = math.min(1, p.g + p.lift * 1.5)
        local b  = math.min(1, p.b + p.lift * 1.5)
        local br, bg_, bb = BNB.SkinBorderOf(p)
        BNB.SetBackdrop(fontDDBg, r, g, b, 0.92, br, bg_, bb, 1)
    end
    if BigNoteBoxDB and BigNoteBoxDB.skinMode and BNB.GetSkinPreset then
        ApplyFontDDBgSkin()
        BNB.RegisterSkinBackdrop(ApplyFontDDBgSkin)
    else
        BNB.SetBackdrop(fontDDBg, 0.08, 0.08, 0.10, 0.90, 0.28, 0.28, 0.30, 1)
    end

    local fontDDLabel = fontDDBg:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    fontDDLabel:SetPoint("LEFT",  fontDDBg, "LEFT",  5, 0)
    fontDDLabel:SetPoint("RIGHT", fontDDBg, "RIGHT", -14, 0)
    fontDDLabel:SetJustifyH("LEFT")
    fontDDLabel:SetMaxLines(1)
    fontDDLabel:SetTextColor(0.85, 0.85, 0.85)

    local fontDDArrow = fontDDBg:CreateTexture(nil, "ARTWORK")
    fontDDArrow:SetSize(10, 10)
    fontDDArrow:SetPoint("RIGHT", fontDDBg, "RIGHT", -3, 0)
    fontDDArrow:SetTexture("Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Up")

    local fontDDBtn = CreateFrame("Button", nil, fontDDBg)
    fontDDBtn:SetAllPoints()

    -- Helper: get current note's effective font label
    local function GetCurrentFontLabel()
        local note = BNB._currentNoteID and BNB.GetNote(BNB._currentNoteID)
        local fid  = note and note.fontOverride
        if fid and BNB.GetFontDef then
            local def = BNB.GetFontDef(fid)
            if def then return def.label end
        end
        -- Fall back to global font choice label
        local globalID = BigNoteBoxDB and BigNoteBoxDB.fontChoice or "notoserif"
        if BNB.GetFontDef then
            local def = BNB.GetFontDef(globalID)
            if def then return def.label end
        end
        return "Default"
    end

    local function RefreshFontDDLabel()
        local lbl = GetCurrentFontLabel()
        -- Truncate to fit; approximate 7px per character at small font
        if #lbl > 12 then lbl = lbl:sub(1, 11) .. "..." end
        fontDDLabel:SetText(lbl)
    end

    local function ApplyFontOverride(fontID)
        local id = BNB._currentNoteID; if not id then return end
        if fontID == nil then
            BNB.UpdateNote(id, {_clear = {"fontOverride"}})
        else
            BNB.UpdateNote(id, {fontOverride = fontID})
        end
        if BNB.RefreshNoteList then BNB.RefreshNoteList() end
        if BNB.NoteConfig and BNB.SyncNoteConfig then BNB.SyncNoteConfig(id) end
        -- Apply to editor body live
        local eb = BNB._editorBody; if not eb then return end
        local note = BNB.GetNote(id); if not note then return end
        local sz = (note.fontSize) or (BigNoteBoxDB and BigNoteBoxDB.fontSize) or 12
        local def = fontID and BNB.GetFontDef and BNB.GetFontDef(fontID)
        if def then
            pcall(function() eb:SetFont(def.regular, sz, "") end)
        elseif BNB.ApplyFont then
            BNB.ApplyFont()
        end
        RefreshFontDDLabel()
    end

    -- Open font picker menu
    local useNativeFontDD = C_XMLUtil and C_XMLUtil.GetTemplateInfo
        and C_XMLUtil.GetTemplateInfo("WowStyle1DropdownTemplate")

    local _fontMenuDD  -- reusable invisible DropdownButton
    fontDDBtn:SetScript("OnClick", function()
        if useNativeFontDD then
            if not _fontMenuDD then
                _fontMenuDD = CreateFrame("DropdownButton", "BNBWysiFontDD", UIParent,
                    "WowStyle1DropdownTemplate")
                _fontMenuDD:SetSize(1, 1); _fontMenuDD:SetAlpha(0)
                _fontMenuDD:SetToplevel(true)
            end
            _fontMenuDD:ClearAllPoints()
            _fontMenuDD:SetPoint("TOPLEFT", fontDDBg, "BOTTOMLEFT", 0, 0)
            _fontMenuDD:SetupMenu(function(_, root)
                -- "Default" entry clears per-note override
                local curID = (function()
                    local n = BNB._currentNoteID and BNB.GetNote(BNB._currentNoteID)
                    return n and n.fontOverride
                end)()
                root:CreateRadio("Default (global setting)",
                    function() return curID == nil end,
                    function() ApplyFontOverride(nil); _fontMenuDD:GenerateMenu() end)
                -- Bundled fonts (non-LSM)
                for _, def in ipairs(BNB.FONTS or {}) do
                    if not def._isLSM then
                        local fid = def.id; local lbl = def.label
                        root:CreateRadio(lbl,
                            function() return curID == fid end,
                            function() ApplyFontOverride(fid); _fontMenuDD:GenerateMenu() end)
                    end
                end
                -- LSM fonts: only shown when db.lsmFonts is on and entries exist
                local db = BigNoteBoxDB
                if db and db.lsmFonts then
                    local hasLSM = false
                    for _, def in ipairs(BNB.FONTS or {}) do
                        if def._isLSM then hasLSM = true; break end
                    end
                    if hasLSM then
                        root:CreateDivider()
                        for _, def in ipairs(BNB.FONTS or {}) do
                            if def._isLSM then
                                local fid = def.id; local lbl = def.label
                                root:CreateRadio(lbl,
                                    function() return curID == fid end,
                                    function() ApplyFontOverride(fid); _fontMenuDD:GenerateMenu() end)
                            end
                        end
                    end
                end
            end)
            _fontMenuDD:OpenMenu()
        else
            -- Fallback: cycle through fonts on click
            local note  = BNB._currentNoteID and BNB.GetNote(BNB._currentNoteID)
            local curID = note and note.fontOverride
            local fonts = BNB.FONTS or {}
            local idx   = 0
            for i, def in ipairs(fonts) do if def.id == curID then idx = i; break end end
            idx = idx % #fonts + 1
            ApplyFontOverride(fonts[idx] and fonts[idx].id)
        end
    end)
    fontDDBtn:SetScript("OnEnter", function()
        GameTooltip:SetOwner(fontDDBg, "ANCHOR_TOP")
        GameTooltip:AddLine("Font type", 1, 1, 1)
        GameTooltip:AddLine("Click to change the font for this note.", 0.7, 0.7, 0.7, true)
        GameTooltip:Show()
    end)
    fontDDBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- ── Font size: decrease / increase / dropdown ─────────────────────────────
    local decBtn = WyBtn("tb-decreasesize", "Decrease font size")
    decBtn:SetPoint("LEFT", fontDDBg, "RIGHT", 4, 0)
    decBtn:SetIconEnabled(true)

    local incBtn = WyBtn("tb-increasesize", "Increase font size")
    incBtn:SetPoint("LEFT", decBtn, "RIGHT", 2, 0)
    incBtn:SetIconEnabled(true)

    -- Size display button — shows current pt value, opens preset quick-pick menu
    local SIZE_BTN_W = 38
    local sizeBg = BNB.CreateBackdropFrame("Frame", nil, bar)
    sizeBg:SetSize(SIZE_BTN_W, FONT_BTN_H)
    sizeBg:SetPoint("LEFT", incBtn, "RIGHT", 4, 0)
    local function ApplySizeBgSkin()
        local p  = BNB.GetSkinPreset and BNB.GetSkinPreset()
        if not p then return end
        local r  = math.min(1, p.r + p.lift * 1.5)
        local g  = math.min(1, p.g + p.lift * 1.5)
        local b  = math.min(1, p.b + p.lift * 1.5)
        local br, bg_, bb = BNB.SkinBorderOf(p)
        BNB.SetBackdrop(sizeBg, r, g, b, 0.92, br, bg_, bb, 1)
    end
    if BigNoteBoxDB and BigNoteBoxDB.skinMode and BNB.GetSkinPreset then
        ApplySizeBgSkin()
        BNB.RegisterSkinBackdrop(ApplySizeBgSkin)
    else
        BNB.SetBackdrop(sizeBg, 0.08, 0.08, 0.10, 0.90, 0.28, 0.28, 0.30, 1)
    end

    local sizeLbl = sizeBg:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    sizeLbl:SetPoint("LEFT",  sizeBg, "LEFT",  4, 0)
    sizeLbl:SetPoint("RIGHT", sizeBg, "RIGHT", -3, 0)
    sizeLbl:SetJustifyH("CENTER")
    sizeLbl:SetTextColor(0.85, 0.85, 0.85)

    local sizeArrow = sizeBg:CreateTexture(nil, "ARTWORK")
    sizeArrow:SetSize(8, 8)
    sizeArrow:SetPoint("RIGHT", sizeBg, "RIGHT", -2, 0)
    sizeArrow:SetTexture("Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Up")

    local sizeDDBtn = CreateFrame("Button", nil, sizeBg)
    sizeDDBtn:SetAllPoints()

    local function GetCurrentFontSize()
        local note = BNB._currentNoteID and BNB.GetNote(BNB._currentNoteID)
        return (note and note.fontSize) or (BigNoteBoxDB and BigNoteBoxDB.fontSize) or 12
    end

    local function RefreshSizeLbl()
        sizeLbl:SetText(GetCurrentFontSize() .. "pt")
    end

    local function ApplyFontSize(sz)
        sz = math.max(8, math.min(32, math.floor(sz)))
        local id = BNB._currentNoteID; if not id then return end
        BNB.UpdateNote(id, {fontSize = sz})
        if BNB.RefreshNoteList then BNB.RefreshNoteList() end
        if BNB.SyncNoteConfig  then BNB.SyncNoteConfig(id) end
        local eb = BNB._editorBody
        if eb then
            local path = select(1, eb:GetFont())
            if path then pcall(function() eb:SetFont(path, sz, "") end) end
        end
        RefreshSizeLbl()
    end

    decBtn:SetScript("OnClick", function()
        ApplyFontSize(GetCurrentFontSize() - 1)
    end)
    incBtn:SetScript("OnClick", function()
        ApplyFontSize(GetCurrentFontSize() + 1)
    end)

    local _sizeMenuDD
    sizeDDBtn:SetScript("OnClick", function()
        if useNativeFontDD then
            if not _sizeMenuDD then
                _sizeMenuDD = CreateFrame("DropdownButton", "BNBWysiSizeDD", UIParent,
                    "WowStyle1DropdownTemplate")
                _sizeMenuDD:SetSize(1, 1); _sizeMenuDD:SetAlpha(0)
                _sizeMenuDD:SetToplevel(true)
            end
            _sizeMenuDD:ClearAllPoints()
            _sizeMenuDD:SetPoint("TOPLEFT", sizeBg, "BOTTOMLEFT", 0, 0)
            _sizeMenuDD:SetupMenu(function(_, root)
                local curSz = GetCurrentFontSize()
                for _, sz in ipairs(WY_SIZE_PRESETS) do
                    local s = sz
                    root:CreateRadio(s .. "pt",
                        function() return curSz == s end,
                        function() ApplyFontSize(s); _sizeMenuDD:GenerateMenu() end)
                end
            end)
            _sizeMenuDD:OpenMenu()
        else
            -- Fallback: cycle to next preset
            local cur = GetCurrentFontSize()
            local next = WY_SIZE_PRESETS[1]
            for i, s in ipairs(WY_SIZE_PRESETS) do
                if s > cur then next = s; break end
            end
            ApplyFontSize(next)
        end
    end)
    sizeDDBtn:SetScript("OnEnter", function()
        GameTooltip:SetOwner(sizeBg, "ANCHOR_TOP")
        GameTooltip:AddLine("Font size", 1, 1, 1)
        GameTooltip:AddLine("Click to pick a preset size.", 0.7, 0.7, 0.7, true)
        GameTooltip:Show()
    end)
    sizeDDBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- tb-bulletlist: insert "  · " at the start of the cursor's current line
    local bulletBtn = WyBtn("tb-bulletlist", "Insert bullet point at start of current line")
    bulletBtn:SetPoint("LEFT", sizeBg, "RIGHT", 6, 0)
    bulletBtn:SetIconEnabled(true)
    bulletBtn:SetScript("OnClick", function()
        local eb = BNB._editorBody
        if not eb or BNB._editorLocked then return end
        local id = BNB._currentNoteID; if not id then return end
        local text   = eb:GetText() or ""
        local cursor = eb:GetCursorPosition() or 0
        -- Find the byte index of the start of the current line
        local lineStart = 0
        for i = cursor, 1, -1 do
            if text:sub(i, i) == "\n" then
                lineStart = i  -- insert after this \n
                break
            end
        end
        local BULLET = "  · "  -- two spaces + middle dot (U+00B7) + space
        local newText   = text:sub(1, lineStart) .. BULLET .. text:sub(lineStart + 1)
        local newCursor = cursor + #BULLET
        -- Seed snap with pre-bullet state if not yet initialised (note never typed in).
        if not BNB._undoSnap[id] then
            BNB._undoSnap[id]  = { text = text, cursor = cursor }
            BNB._undoStack[id] = {}
            BNB._redoStack[id] = {}
        end
        -- Suppress OnTextChanged undo push during SetText, then push manually.
        BNB._undoActive = true
        eb:SetText(newText)
        BNB._undoActive = false
        -- UndoPush: snap=old→pushed onto stack, snap updated to newText. Undo recovers old.
        BNB.UndoPush(id, newText, newCursor)
        if BNB._refreshUndoButtons then BNB._refreshUndoButtons() end
        C_Timer.After(0, function() eb:SetCursorPosition(newCursor) end)
        BNB.MarkDirty()
    end)

    -- ── RIGHT SIDE (right-anchored) ───────────────────────────────────────────
    -- Anchored from RIGHT inward so they always hug the right edge.

    -- tb-notemap: waypoint at note creation coords (rightmost)
    local mapBtn = WyBtn("tb-notemap", "Open waypoint at note location")
    mapBtn:SetPoint("RIGHT", bar, "RIGHT", -6, 0)
    mapBtn:SetScript("OnEnter", function(self)
        local note = BNB._currentNoteID and BNB.GetNote(BNB._currentNoteID)
        if not note or not note.coordX then return end
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Open waypoint at note location", 1, 1, 1)
        local zone = note.coordZone or "Unknown"
        GameTooltip:AddLine(string.format("%s (%.2f %.2f)", zone, note.coordX, note.coordY), 0.7, 0.7, 0.7)
        if not (TomTom and TomTom.AddWaypoint) then
            GameTooltip:AddLine("Replaces current waypoint.", 0.5, 0.5, 0.5)
        end
        GameTooltip:Show()
    end)
    mapBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    mapBtn:SetScript("OnClick", function()
        local note = BNB._currentNoteID and BNB.GetNote(BNB._currentNoteID)
        if not note or not note.coordX or not note.coordMapID then return end
        local mapID = note.coordMapID
        local x, y = note.coordX / 100, note.coordY / 100
        local noteTitle = (note.title and note.title ~= "") and note.title or nil
        local label = note.coordZone
            and string.format("%s (%.2f %.2f)", note.coordZone, note.coordX, note.coordY)
            or  string.format("%.2f %.2f", note.coordX, note.coordY)
        if noteTitle then label = noteTitle .. " - " .. label end
        if TomTom and TomTom.AddWaypoint and TomTom.RemoveWaypoint then
            if BNB._coordWaypoint then
                pcall(function() TomTom:RemoveWaypoint(BNB._coordWaypoint) end)
                BNB._coordWaypoint = nil
            end
            local ok, uid = pcall(function()
                return TomTom:AddWaypoint(mapID, x, y, {
                    title = label, persistent = false, minimap = true, world = true,
                })
            end)
            if ok and uid then BNB._coordWaypoint = uid end
        elseif C_Map and C_Map.SetUserWaypoint then
            local pt = UiMapPoint.CreateFromCoordinates(mapID, x, y)
            pcall(function() C_Map.SetUserWaypoint(pt) end)
            if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then
                pcall(function() C_SuperTrack.SetSuperTrackedUserWaypoint(true) end)
            end
        end
        if OpenWorldMap then pcall(function() OpenWorldMap(mapID) end) end
    end)
    BNB._wysiwygMapBtn = mapBtn

    -- Divider: share | waypoint
    local shareDiv = bar:CreateTexture(nil, "ARTWORK")
    shareDiv:SetSize(1, 16)
    shareDiv:SetPoint("RIGHT", mapBtn, "LEFT", -6, 0)
    if BigNoteBoxDB and BigNoteBoxDB.skinMode and BNB.GetSkinPreset then
        local p = BNB.GetSkinPreset()
        local br, bg_, bb = BNB.SkinBorderOf(p)
        shareDiv:SetColorTexture(br, bg_, bb, 0.40)
        BNB.RegisterSkinRule(shareDiv, 0.40)
    else
        shareDiv:SetColorTexture(0.16, 0.16, 0.18, 1)
    end

    -- tb-share (left of divider)
    local shareBtn = WyBtn("tb-share", "Share this note")
    shareBtn:SetPoint("RIGHT", shareDiv, "LEFT", -6, 0)
    shareBtn:SetScript("OnClick", function()
        local id = BNB._currentNoteID
        if id and BNB.OpenShareWindow then BNB.OpenShareWindow(id) end
    end)
    shareBtn:SetIconEnabled(false)
    BNB._wysiwygShareBtn = shareBtn
    -- tb-copymove (left of share button)
    local copyMoveBtn = WyBtn("tb-copymove", "Copy or move note to another character or scope")
    copyMoveBtn:SetPoint("RIGHT", shareBtn, "LEFT", -4, 0)
    copyMoveBtn:SetScript("OnClick", function()
        local id = BNB._currentNoteID
        if id and BNB.OpenCopyMovePopup then BNB.OpenCopyMovePopup(id) end
    end)
    BNB._wysiwygCopyMoveBtn = copyMoveBtn

    -- tb-alarm (left of copy/move)
    local alarmBtn = WyBtn("tb-alarm", "Set alarm for this note")
    alarmBtn:SetPoint("RIGHT", copyMoveBtn, "LEFT", -4, 0)
    alarmBtn:SetScript("OnClick", function()
        local id = BNB._currentNoteID
        if not id then return end
        if BNB.AlarmWindow then
            if BNB.AlarmWindow.IsOpen and BNB.AlarmWindow.IsOpen()
               and BNB.AlarmWindow.GetNoteID and BNB.AlarmWindow.GetNoteID() == id then
                BNB.AlarmWindow.Close()
            else
                if BNB.AlarmWindow.OpenLeftOfMain then
                    BNB.AlarmWindow.OpenLeftOfMain(id)
                end
            end
        end
    end)
    BNB._wysiwygAlarmBtn = alarmBtn

    -- Divider: history | alarm
    local cmDiv = bar:CreateTexture(nil, "ARTWORK")
    cmDiv:SetSize(1, 16)
    cmDiv:SetPoint("RIGHT", alarmBtn, "LEFT", -6, 0)
    if BigNoteBoxDB and BigNoteBoxDB.skinMode and BNB.GetSkinPreset then
        local p = BNB.GetSkinPreset()
        local br, bg_, bb = BNB.SkinBorderOf(p)
        cmDiv:SetColorTexture(br, bg_, bb, 0.40)
        BNB.RegisterSkinRule(cmDiv, 0.40)
    else
        cmDiv:SetColorTexture(0.16, 0.16, 0.18, 1)
    end

    -- tb-history (left of divider)
    local histBtn = WyBtn("tb-history", L["HISTORY_VIEW_BTN_TIP"])
    histBtn:SetPoint("RIGHT", cmDiv, "LEFT", -6, 0)
    histBtn:SetScript("OnClick", function()
        local id = BNB._currentNoteID
        if id and BNB.OpenNoteHistoryPanel then BNB.OpenNoteHistoryPanel(id) end
    end)
    histBtn:SetIconEnabled(false)
    BNB._wysiwygHistoryBtn = histBtn

    -- tb-restore (left of history)
    local restoreBtn = WyBtn("tb-restore", L["HISTORY_RESTORE_BTN_TIP"])
    restoreBtn:SetPoint("RIGHT", histBtn, "LEFT", -4, 0)
    restoreBtn:SetScript("OnClick", function()
        local id = BNB._currentNoteID; if not id then return end
        if BNB._dirty and BNB.SaveCurrentNote then BNB.SaveCurrentNote() end
        local slots = BNB.HistoryGetSlots(id)
        if slots.manual then
            StaticPopup_Show("BNB_HISTORY_OVERRIDE_MANUAL", id)
        else
            BNB.HistoryCreateManual(id)
            BNB:Print(L["HISTORY_MANUAL_SAVED"])
        end
    end)
    BNB._wysiwygRestoreBtn = restoreBtn

    -- ── Public refresh callbacks ──────────────────────────────────────────────

    -- Called by LoadNoteInEditor and NoteConfig when the note changes
    BNB._refreshWysiwygFont = function()
        RefreshFontDDLabel()
        RefreshSizeLbl()
        -- Enable/disable dec/inc at bounds
        local sz = GetCurrentFontSize()
        decBtn:SetIconEnabled(sz > 8)
        incBtn:SetIconEnabled(sz < 32)
        -- Highlight alarm button when current note has an active alarm
        if BNB._wysiwygAlarmBtn then
            local id    = BNB._currentNoteID
            local note  = id and BNB.GetNote and BNB.GetNote(id)
            local alarm = note and note.alarm
            local hasAlarm = alarm ~= nil and not alarm.fired
            BNB._wysiwygAlarmBtn:SetIconEnabled(hasAlarm)
        end
    end

    -- Sync sidebar copy/move button visibility
    function BNB.SyncSidebarWysiwygBtns()
        local enabled = BNB.Sidebar and BNB.Sidebar.IsEnabled()
        if BNB._wysiwygCopyMoveBtn then BNB._wysiwygCopyMoveBtn:SetShown(enabled) end
        if cmDiv                   then cmDiv:SetShown(enabled)                   end
    end
    BNB.SyncSidebarWysiwygBtns()

    -- StaticPopup for manual restore override warning.
    -- WoW StaticPopup 3-button layout:
    --   button1 = "Override"  -> OnAccept
    --   button2 = "Compare"   -> OnCancel  (middle button)
    --   button3 = "Cancel"    -> OnAlt
    -- OnCancel fires for both the X/ESC dismiss AND button2, so we guard with
    -- a flag to distinguish button2 clicks from ESC/X dismissal.
    if not StaticPopupDialogs["BNB_HISTORY_OVERRIDE_MANUAL"] then
        StaticPopupDialogs["BNB_HISTORY_OVERRIDE_MANUAL"] = {
            text           = L["HISTORY_OVERRIDE_TEXT"],
            button1        = L["HISTORY_OVERRIDE_OVERRIDE"],
            button2        = L["HISTORY_OVERRIDE_COMPARE"],
            button3        = L["HISTORY_OVERRIDE_CANCEL"],
            OnAccept       = function(self, noteID)
                if noteID and BNB.HistoryCreateManual then
                    BNB.HistoryCreateManual(noteID)
                    BNB:Print(L["HISTORY_MANUAL_UPDATED"])
                end
            end,
            OnCancel       = function(self, noteID, reason)
                -- button2 = "Compare" fires OnCancel with reason == "override"
                -- ESC / X fires OnCancel with reason == "clicked" or nil
                -- We only open compare when the button was explicitly clicked.
                if reason == "override" then
                    if noteID then
                        local slots = BNB.HistoryGetSlots(noteID)
                        if slots.manual and BNB.OpenHistoryCompare then
                            BNB.OpenHistoryCompare(noteID, slots.manual)
                        end
                    end
                end
                -- reason nil/other = ESC dismiss, do nothing
            end,
            OnAlt          = function(self, noteID)
                -- button3 = "Cancel" — just dismiss, no action needed
            end,
            timeout        = 0,
            whileDead      = true,
            hideOnEscape   = true,
            preferredIndex = 3,
        }
    end

    -- Respect initial visibility setting
    if db and db.wysiwygBarVisible == false then
        bar:Hide()
    end

    return bar
end

--------------------------------------------------------------------------------
-- PUBLIC: re-anchor body scroll top when wysiwyg bar is shown/hidden.
-- Also handles markup bar (rich notes) and render frame (view mode).
-- Called by ToggleWysiwygBar and rich mode enter/exit.
--------------------------------------------------------------------------------
function BNB.UpdateBodyTopAnchor()
    local sf   = BNB._editorBodyScroll
    local rsf  = BNB._editorRenderScroll
    local bar  = BNB._editorWysiwygBar
    local mbar = BNB._editorMarkupBar
    local ts   = BNB._editorTimestamp
    if not ts then return end

    -- Build anchor chain: tsStrip -> wysiwygBar (if shown) -> markupBar (if shown)
    local topAnchor = ts
    if bar  and bar:IsShown()  then topAnchor = bar  end
    if mbar and mbar:IsShown() then topAnchor = mbar end

    local bottomOffset = TOOLBAR_H
        + (BNB._editorTagStrip and BNB._editorTagStrip:GetHeight() or TAG_STRIP_H)
        + PAD

    if sf then
        sf:ClearAllPoints()
        sf:SetPoint("TOPLEFT",     topAnchor,      "BOTTOMLEFT",  PAD, -4)
        sf:SetPoint("BOTTOMRIGHT", BNB.editorPane, "BOTTOMRIGHT", -22, bottomOffset)
    end
    if rsf then
        rsf:ClearAllPoints()
        rsf:SetPoint("TOPLEFT",     topAnchor,      "BOTTOMLEFT",  PAD, -4)
        rsf:SetPoint("BOTTOMRIGHT", BNB.editorPane, "BOTTOMRIGHT", -22, bottomOffset)
    end
end

--------------------------------------------------------------------------------
-- PUBLIC: toggle WYSIWYG bar visibility (called from Config checkbox)
--------------------------------------------------------------------------------
function BNB.ToggleWysiwygBar(shown)
    local bar = BNB._editorWysiwygBar
    if not bar then return end
    local db = BigNoteBoxDB
    if shown == nil then
        shown = not bar:IsShown()
    end
    if shown then bar:Show() else bar:Hide() end
    if db then db.wysiwygBarVisible = shown end
    BNB.UpdateBodyTopAnchor()
end

--------------------------------------------------------------------------------
-- TOOLBAR
-- Layout (left -> right): Save | Delete | Duplicate | Edit(locked) | Pin
-- Right side: Send | [tag chips + add-tag input]
--------------------------------------------------------------------------------
local function BuildToolbar(parent)
    local bar = CreateFrame("Frame", nil, parent)
    bar:SetPoint("BOTTOMLEFT",  parent, "BOTTOMLEFT",  0, 0)
    bar:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, 0)
    bar:SetHeight(TOOLBAR_H)

    local sep = BNB.CreateDivider(parent, "HORIZONTAL", 0.16, 0.16, 0.18, 0.20)
    sep:SetPoint("BOTTOMLEFT",  parent, "BOTTOMLEFT",  0, TOOLBAR_H)
    sep:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -1, TOOLBAR_H)

    -- Icon button helper — 26×26, texture from Assets/
    -- Returns btn, tx. Calling btn:SetIconEnabled(bool) sets alpha + desaturation.
    -- Hover: button grows to 30×30 and restores to 26×26 on leave (no colour flash).
    local ASSETS = "Interface\\AddOns\\BigNoteBox\\Assets\\"
    local BTN_NORMAL = 26
    local BTN_HOVER  = 30
    local function MakeIconBtn(parent, texName, tip, w, h)
        local btn = CreateFrame("Button", nil, parent)
        local bw = w or BTN_NORMAL
        local bh = h or BTN_NORMAL
        btn:SetSize(bw, bh)
        local tx = btn:CreateTexture(nil, "ARTWORK")
        tx:SetAllPoints()
        tx:SetTexture(ASSETS .. texName)
        btn:SetScript("OnEnter", function(self)
            self:SetSize(bw + 4, bh + 4)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:AddLine(tip, 1, 1, 1)
            GameTooltip:Show()
        end)
        btn:SetScript("OnLeave", function(self)
            self:SetSize(bw, bh)
            GameTooltip:Hide()
        end)
        btn._tx = tx
        -- Helper: set enabled + visual state (alpha + desaturation)
        btn.SetIconEnabled = function(self, enabled)
            self:SetEnabled(enabled)
            self:SetAlpha(enabled and 1.0 or 0.4)
            pcall(function() tx:SetDesaturated(not enabled) end)
        end
        return btn, tx
    end

    -- Save
    saveBtn, _ = MakeIconBtn(bar, "Actionbar\\ab-save", L["BTN_SAVE_NOTE"])
    saveBtn:SetPoint("LEFT", bar, "LEFT", 6, 0)
    saveBtn:SetEnabled(false)
    saveBtn:SetAlpha(0.4)
    pcall(function() saveBtn._tx:SetDesaturated(true) end)
    saveBtn:SetScript("OnClick", function()
        BNB.SaveCurrentNote()
        BNB.UpdateSaveButtonState()
    end)

    -- Reference Box toggle
    do
        local refboxBtn, _ = MakeIconBtn(bar, "Actionbar\\ab-refbox", "Toggle Reference Box (item/spell attachments)")
        refboxBtn:SetPoint("LEFT", bar, "LEFT", 38, 0)
        refboxBtn:SetScript("OnClick", function()
            if BNB.ToggleReferenceBox then BNB.ToggleReferenceBox() end
        end)
        bar._refboxBtn = refboxBtn
        BNB._editorRefBoxBtn = refboxBtn
    end

    -- Tasks button — adds a task to the current note (same as + button in RefBox)
    do
        local tasksBtn, _ = MakeIconBtn(bar, "Actionbar\\ab-tasks", "Add task to this note")
        tasksBtn:SetPoint("LEFT", bar, "LEFT", 70, 0)
        tasksBtn:SetScript("OnClick", function()
            local id = BNB._currentNoteID; if not id then return end
            local taskID = BNB.Task and BNB.Task.AddTask(id, "")
            if taskID then
                if BNB.OpenReferenceBox then BNB.OpenReferenceBox(id) end
                C_Timer.After(0.05, function()
                    if BNB.FocusTaskEditBox then BNB.FocusTaskEditBox(taskID) end
                end)
            end
        end)
        bar._tasksBtn = tasksBtn
    end

    -- Delete
    local delBtn = MakeIconBtn(bar, "Actionbar\\ab-delete", L["BTN_DELETE_NOTE"])
    delBtn:SetPoint("LEFT", bar, "LEFT", 102, 0)
    delBtn:SetScript("OnClick", function()
        local id = BNB._currentNoteID; if not id then return end
        local note = BNB.GetNote(id);  if not note then return end
        local title = (note.title ~= "" and note.title) or L["UNTITLED"]
        local warn = BigNoteBoxDB and BigNoteBoxDB.warnBeforeDelete ~= false
        if BNB.TrashEnabled and BNB.TrashEnabled() then
            if warn then
                local popup = StaticPopup_Show("BNB_DELETE_NOTE_TRASH", title)
                if popup then popup.data = id end
            else
                if BNB.DeleteNote then BNB.DeleteNote(id) end
            end
        else
            if warn then
                local popup = StaticPopup_Show("BNB_DELETE_NOTE", title)
                if popup then popup.data = id end
            else
                if BNB.DeleteNote then BNB.DeleteNote(id) end
            end
        end
    end)

    -- Duplicate
    local dupBtn = MakeIconBtn(bar, "Actionbar\\ab-duplicate", "Duplicate this note")
    dupBtn:SetPoint("LEFT", bar, "LEFT", 134, 0)
    dupBtn:SetScript("OnClick", function()
        local id = BNB._currentNoteID; if not id then return end
        local src = BNB.GetNote(id);   if not src then return end
        BNB.SaveCurrentNote()
        local newID = BNB.CreateNote(src.title ~= "" and (src.title .. " (copy)") or "")
        -- Deep-copy attachments so the duplicate has its own independent list
        local attCopy = {}
        if src.attachments then
            for _, att in ipairs(src.attachments) do
                local a = {}
                for k, v in pairs(att) do a[k] = v end
                table.insert(attCopy, a)
            end
        end
        BNB.UpdateNote(newID, { body = src.body, tags = src.tags or {}, attachments = #attCopy > 0 and attCopy or nil })
        if BNB.RefreshNoteList then BNB.RefreshNoteList() end
        if BNB.SelectNote      then BNB.SelectNote(newID) end
    end)

    -- Copy to clipboard — copies title + body silently via editbox trick
    local copyBtn = MakeIconBtn(bar, "Actionbar\\ab-copy", L["BTN_COPY_NOTE"])
    copyBtn:SetPoint("LEFT", bar, "LEFT", 166, 0)
    copyBtn:SetScript("OnClick", function()
        local id = BNB._currentNoteID; if not id then return end
        local note = BNB.GetNote(id);  if not note then return end
        BNB.SaveCurrentNote()
        local content = (note.title ~= "" and (note.title .. "\n") or "")
                     .. (note.body or "")
        -- Always use the hint path — C_System.SetClipboard is restricted in
        -- modern WoW and cannot write to the OS clipboard from addon code.
        BNB:Print(L["BTN_COPY_NOTE_CLASSIC"])
        if BNB.ShowClipboardHint then BNB.ShowClipboardHint(content) end
    end)

    -- Lock / Unlock icon button — always visible in the toolbar.
    -- lock.tga   = note is unlocked → click to lock it persistently.
    -- unlock.tga = note is locked   → click to unlock it persistently.
    local lockBtn, lockTx = MakeIconBtn(bar, "Actionbar\\ab-lock", "")   -- tip set dynamically below
    lockBtn:SetPoint("LEFT", bar, "LEFT", 228, 0)
    lockBtn:Hide()
    lockBtn:SetScript("OnClick", function()
        local id = BNB._currentNoteID; if not id then return end
        local note = BNB.GetNote(id); if not note then return end
        local isLocked = NoteIsLocked(note)
        if isLocked then
            -- Unlock persistently (same as right-click "Unlock note")
            BNB.UpdateNote(id, { locked = false })
        else
            -- Lock persistently (same as right-click "Lock note")
            BNB.UpdateNote(id, { locked = true })
        end
        if BNB.RefreshNoteList    then BNB.RefreshNoteList()    end
        BNB.LoadNoteInEditor(id)
    end)
    -- OnEnter/OnLeave include grow (BTN_NORMAL/BTN_HOVER from MakeIconBtn closure)
    -- and also show the dynamic tooltip. We re-set both scripts here so they
    -- replace the static-tip ones set inside MakeIconBtn.
    lockBtn:SetScript("OnEnter", function(self)
        self:SetSize(BTN_HOVER, BTN_HOVER)
        local id   = BNB._currentNoteID
        local note = id and BNB.GetNote(id)
        local isLocked = note and NoteIsLocked(note)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(isLocked and "Click to unlock this note"
                                      or "Click to lock this note", 1, 1, 1)
        GameTooltip:Show()
    end)
    lockBtn:SetScript("OnLeave", function(self)
        self:SetSize(BTN_NORMAL, BTN_NORMAL)
        GameTooltip:Hide()
    end)
    bar._lockBtn = lockBtn
    bar._lockTx  = lockTx

    -- Sticky Note pin button — offset 132, always visible
    local pinBtn = CreateFrame("Button", nil, bar)
    pinBtn:SetSize(24, 24)
    pinBtn:SetPoint("LEFT", bar, "LEFT", 198, 0)
    local pinTx = pinBtn:CreateTexture(nil, "ARTWORK")
    pinTx:SetAllPoints()
    pinTx:SetTexture("Interface\\AddOns\\BigNoteBox\\Assets\\Actionbar\\ab-stickynote")
    pinBtn:SetScript("OnClick", function()
        local id = BNB._currentNoteID; if not id then return end
        if InCombatLockdown() then BNB:Print(L["STICKY_COMBAT"]); return end
        if BNB.Sticky then BNB.Sticky.Toggle(id) end
        C_Timer.After(0, function()
            if pinBtn:IsMouseOver() then
                GameTooltip:ClearLines()
                local open = BNB.Sticky and BNB.Sticky.IsOpen(id)
                GameTooltip:AddLine(open and L["STICKY_UNPIN_TIP"] or L["STICKY_PIN_TIP"], 1, 1, 1)
                GameTooltip:Show()
            end
        end)
    end)
    pinBtn:SetScript("OnEnter", function(self)
        self:SetSize(28, 28)
        local id   = BNB._currentNoteID
        local open = id and BNB.Sticky and BNB.Sticky.IsOpen(id)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(open and L["STICKY_UNPIN_TIP"] or L["STICKY_PIN_TIP"], 1, 1, 1)
        GameTooltip:Show()
    end)
    pinBtn:SetScript("OnLeave", function(self)
        self:SetSize(24, 24)
        GameTooltip:Hide()
    end)
    bar._pinBtn = pinBtn

    -- Send to Chat button (right side) — icon-only using send.tga
    local sendBtn, _ = MakeIconBtn(bar, "Actionbar\\ab-send", L["SEND_TITLE"], 28, 28)
    sendBtn:SetPoint("RIGHT", bar, "RIGHT", -10, 0)
    -- Override OnEnter to add the sub-line tooltip
    sendBtn:SetScript("OnEnter", function(self)
        self:SetSize(32, 32)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(L["SEND_TITLE"], 1, 1, 1)
        GameTooltip:AddLine("Send note lines to a chat channel", 0.78, 0.78, 0.78)
        GameTooltip:Show()
    end)
    sendBtn:SetScript("OnLeave", function(self)
        self:SetSize(28, 28)
        GameTooltip:Hide()
    end)
    sendBtn:SetScript("OnClick", function()
        local id = BNB._currentNoteID; if not id then return end
        if BNB.OpenSendToChat then BNB.OpenSendToChat(id) end
    end)
    bar._sendBtn = sendBtn

    bar._saveBtn = saveBtn
    bar._delBtn  = delBtn
    bar._dupBtn  = dupBtn
    bar._copyBtn = copyBtn
    return bar
end

--------------------------------------------------------------------------------
-- INLINE TAG EDITOR
-- Displayed as a second strip just above the toolbar.
-- Shows existing tags as removable chips + an "Add tag..." input.
-- Height: 22px. Anchored above the toolbar divider.
-- MAX_TAGS = 24, MAX_TAG_LEN = 20
--------------------------------------------------------------------------------
local MAX_TAGS     = 24
local MAX_TAG_LEN  = 20

local tagChips        = {}     -- active chip frames
local tagStripFrame   = nil    -- the strip frame (module-level so LoadNote can refresh)
local _tagStripCollapsed = false
local ASSETS_TAG      = "Interface\\AddOns\\BigNoteBox\\Assets\\"

local function RebuildTagChips(strip, tags)
    for _, c in ipairs(tagChips) do c:Hide(); c:SetParent(nil) end
    tagChips = {}

    local stripW   = strip:GetWidth()
    if not stripW or stripW <= 0 then stripW = 400 end
    local CHIP_PAD = 3
    local ROW_PAD  = 3
    local x        = 4
    local row      = 1

    for _, tag in ipairs(tags or {}) do
        local chip = BNB.CreateBackdropFrame("Frame", nil, strip)
        chip:SetHeight(16)
        -- Chip backdrop: skin lifted colour + border when in skin mode, dark otherwise
        if BigNoteBoxDB and BigNoteBoxDB.skinMode and BNB.GetSkinPreset then
            local p = BNB.GetSkinPreset()
            local r = math.min(1, p.r + p.lift * 1.5)
            local g = math.min(1, p.g + p.lift * 1.5)
            local b = math.min(1, p.b + p.lift * 1.5)
            local br, bg_, bb = BNB.SkinBorderOf(p)
            BNB.SetBackdrop(chip, r, g, b, 0.92, br, bg_, bb, 1)
        else
            BNB.SetBackdrop(chip, 0.15, 0.15, 0.20, 1, 0.35, 0.35, 0.40, 1)
        end

        local lblBtn = CreateFrame("Button", nil, chip)
        lblBtn:SetHeight(16)
        local lbl = lblBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        lbl:SetPoint("LEFT",  lblBtn, "LEFT",  4, 0)
        lbl:SetPoint("RIGHT", lblBtn, "RIGHT", 0, 0)
        -- White text in skin mode, gold otherwise
        if BigNoteBoxDB and BigNoteBoxDB.skinMode then
            lbl:SetTextColor(1, 1, 1, 1)
        else
            lbl:SetTextColor(1, 0.82, 0, 1)
        end
        lbl:SetText(tag)
        lbl:SetWordWrap(false)
        local capturedTag = tag
        lblBtn:SetScript("OnEnter", function(self)
            lbl:SetTextColor(1, 1, 0.4)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:AddLine("Filter notes by tag: " .. capturedTag, 1, 1, 1)
            GameTooltip:AddLine("Click again to clear filter", 0.6, 0.6, 0.6)
            GameTooltip:Show()
        end)
        lblBtn:SetScript("OnLeave", function()
            lbl:SetTextColor(1, 0.82, 0, 1)
            GameTooltip:Hide()
        end)
        lblBtn:SetScript("OnClick", function()
            if BNB.FilterByTag then BNB.FilterByTag(capturedTag) end
        end)

        local closeChip = CreateFrame("Button", nil, chip)
        closeChip:SetSize(14, 14)
        closeChip:SetPoint("LEFT", lblBtn, "RIGHT", 2, 0)
        local closeLbl = closeChip:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        closeLbl:SetAllPoints(); closeLbl:SetText("×"); closeLbl:SetTextColor(0.65, 0.65, 0.65)
        closeChip:SetScript("OnEnter", function() closeLbl:SetTextColor(1, 0.3, 0.3) end)
        closeChip:SetScript("OnLeave", function() closeLbl:SetTextColor(0.65, 0.65, 0.65) end)
        closeChip:SetScript("OnClick", function()
            local id = BNB._currentNoteID; if not id then return end
            local note = BNB.GetNote(id);   if not note then return end
            local newTags = {}
            for _, t in ipairs(note.tags or {}) do
                if t ~= capturedTag then newTags[#newTags + 1] = t end
            end
            BNB.UpdateNote(id, { tags = newTags })
            if BNB._editorTagStrip then BNB.RefreshTagStrip() end
            if BNB.RefreshNoteList  then BNB.RefreshNoteList()  end
        end)

        -- GetStringWidth() can return 0 before layout — use string length as floor
        local strW = math.max(lbl:GetStringWidth(), #tag * 6)
        local chipW = strW + 14 + 18
        chip:SetWidth(chipW)
        lblBtn:SetWidth(strW + 4)
        lblBtn:SetPoint("LEFT", chip, "LEFT", 0, 0)

        -- On row 1, reserve 54px on the right for the collapse-toggle button and
        -- its hidden-count badge so chips can never overlap them.
        local rowLimit = (row == 1) and (stripW - 54) or (stripW - 4)
        if x + chipW > rowLimit and x > 4 then
            x   = 4
            row = row + 1
        end

        local rowY = (row - 1) * CHIP_ROW_H
        chip:SetPoint("LEFT",   strip, "LEFT",   x, 0)
        chip:SetPoint("BOTTOM", strip, "BOTTOM", 0, ROW_PAD + rowY)
        chip._row = row   -- store so ToggleTagStrip can hide/show by row
        chip:Show()
        tagChips[#tagChips + 1] = chip
        x = x + chipW + CHIP_PAD
    end

    local numRows = math.max(1, row)
    local newH    = numRows * CHIP_ROW_H
    strip:SetHeight(newH)
    strip._numRows   = numRows  -- total rows, used by ToggleTagStrip
    strip._inputRow  = nil      -- cleared; set below if input is placed

    if strip._addInput then
        if #(tags or {}) >= MAX_TAGS then
            strip._addInput:Hide()
        else
            local inputMinW = 60
            if x + inputMinW > stripW - 4 and x > 4 then
                row  = row + 1
                x    = 4
                newH = row * CHIP_ROW_H
                strip:SetHeight(newH)
            end
            strip._numRows  = math.max(1, row)
            strip._inputRow = row   -- remember which row the input is on
            local rowY = (row - 1) * CHIP_ROW_H
            strip._addInput:ClearAllPoints()
            strip._addInput:SetPoint("LEFT",   strip, "LEFT",   x,  0)
            strip._addInput:SetPoint("RIGHT",  strip, "RIGHT",  -4, 0)
            strip._addInput:SetPoint("BOTTOM", strip, "BOTTOM", 0,  ROW_PAD + rowY)
            strip._addInput:Show()
        end
    end

    -- Show the collapse toggle only when chips span more than one row.
    -- Hides itself when everything fits on one line; reappears when the window
    -- is resized narrow enough to wrap chips onto a second row.
    if strip._toggleBtn then
        if (strip._numRows or 1) > 1 then
            strip._toggleBtn:Show()
        else
            strip._toggleBtn:Hide()
            -- Also clear the badge and reset collapsed state so a single-row
            -- strip never gets stuck in a visually collapsed state.
            if strip._hiddenLbl then strip._hiddenLbl:Hide() end
            if _tagStripCollapsed then
                _tagStripCollapsed = false
                if strip._toggleTx then
                    strip._toggleTx:SetTexture(ASSETS_TAG .. "UI\\ui-tags-open")
                end
                -- Ensure all chips visible and strip at full height
                for _, chip in ipairs(tagChips) do chip:Show() end
                strip:SetHeight((strip._numRows or 1) * CHIP_ROW_H)
            end
        end
    end
end

local function BuildTagStrip(parent, toolbarFrame)
    local strip = CreateFrame("Frame", nil, parent)
    strip:SetHeight(TAG_STRIP_H)
    strip:SetPoint("BOTTOMLEFT",  parent, "BOTTOMLEFT",  0, TOOLBAR_H)
    strip:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -1, TOOLBAR_H)

    -- Sep anchors to the strip's top so it moves up as the strip grows
    local sep = BNB.CreateDivider(parent, "HORIZONTAL", 0.14, 0.14, 0.16, 0.18)
    sep:SetPoint("BOTTOMLEFT",  strip, "TOPLEFT",  0, 0)
    sep:SetPoint("BOTTOMRIGHT", strip, "TOPRIGHT", 0, 0)

    -- OnSizeChanged fires for both width and height changes.
    -- When WIDTH changes (window resize), re-wrap chips so they don't overflow.
    -- When HEIGHT changes (rows added/removed), reanchor the body scroll.
    -- Debounce width-driven rebuilds so we don't rebuild every pixel of a drag.
    local _lastStripW = 0
    local _resizeTimer = nil
    strip:SetScript("OnSizeChanged", function(self, w, h)
        -- Always reanchor body scroll to match current strip height
        local bs = BNB._editorBodyScroll
        if bs then
            bs:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -22,
                TOOLBAR_H + self:GetHeight() + PAD)
        end
        -- If width changed, debounce a chip rebuild
        if w and math.abs(w - _lastStripW) > 2 then
            _lastStripW = w
            if _resizeTimer then _resizeTimer:Cancel() end
            _resizeTimer = C_Timer.NewTimer(0.05, function()
                _resizeTimer = nil
                if BNB.RefreshTagStrip then BNB.RefreshTagStrip() end
            end)
        end
    end)

    -- Add-tag EditBox
    local addEb = CreateFrame("EditBox", nil, strip)
    addEb:SetPoint("LEFT",  strip, "LEFT", 4, 0)
    addEb:SetPoint("RIGHT", strip, "RIGHT", -4, 0)
    addEb:SetPoint("BOTTOM", strip, "BOTTOM", 0, 3)
    addEb:SetHeight(16)
    addEb:SetFontObject("GameFontNormalSmall")
    addEb:SetAutoFocus(false)
    addEb:SetMaxLetters(MAX_TAG_LEN)
    BNB.AddPlaceholder(addEb, L["TAG_ADD_HINT"], 0.35, 0.35, 0.35)

    addEb:SetScript("OnEnterPressed", function(self)
        local id = BNB._currentNoteID; if not id then return end
        local note = BNB.GetNote(id);   if not note then return end
        local text = self._showingPlaceholder and "" or (self:GetText():match("^%s*(.-)%s*$") or "")
        if text == "" then self:ClearFocus(); return end
        if #text > MAX_TAG_LEN then
            BNB:Print(L["TAG_TOO_LONG"]); return
        end
        text = BNB.NormalizeTag and BNB.NormalizeTag(text) or text
        local tags = note.tags or {}
        if #tags >= MAX_TAGS then BNB:Print(L["TAG_MAX"]); return end
        -- Deduplicate (case-insensitive — normalized form is canonical)
        for _, t in ipairs(tags) do
            if t:lower() == text:lower() then
                self:SetRealText(""); self:ClearFocus(); return
            end
        end
        tags[#tags + 1] = text
        BNB.UpdateNote(id, { tags = tags })
        -- Reset to placeholder without re-calling AddPlaceholder (which would
        -- overwrite the OnEditFocusLost hook set by AttachTagAutocomplete)
        self:SetRealText("")
        if BNB._editorTagStrip then BNB.RefreshTagStrip() end
        if BNB.RefreshNoteList  then BNB.RefreshNoteList()  end
        -- Re-open autocomplete showing updated tag list
        if BNB._tagAC then BNB._tagAC:ShowFor(self, "") end
    end)
    addEb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    -- Attach tag autocomplete (suggests existing tags as the user types)
    if BNB.AttachTagAutocomplete then BNB.AttachTagAutocomplete(addEb) end
    strip._addInput = addEb

    -- ── Collapse toggle ───────────────────────────────────────────────────────
    -- TGA icon button on the right edge of the tag bar.
    -- tags-open.tga  = tags are visible  (click to collapse to one row)
    -- tags-close.tga = tags are collapsed (click to expand)
    -- A small "+N" badge to the left of the button shows how many chips are
    -- hidden when collapsed.
    local ASSETS = "Interface\\AddOns\\BigNoteBox\\Assets\\"
    local toggleBtn = CreateFrame("Button", nil, parent)
    toggleBtn:SetSize(18, 18)
    toggleBtn:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -24, TOOLBAR_H + 2)

    local toggleTx = toggleBtn:CreateTexture(nil, "ARTWORK")
    toggleTx:SetAllPoints()
    toggleTx:SetTexture(ASSETS .. "UI\\ui-tags-open")
    toggleBtn._tx = toggleTx

    local hiTx = toggleBtn:CreateTexture(nil, "HIGHLIGHT")
    hiTx:SetAllPoints()
    hiTx:SetColorTexture(1, 1, 1, 0.25)

    -- Hidden-count badge: "+N" label that appears to the left of the toggle button
    local hiddenLbl = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hiddenLbl:SetPoint("RIGHT", toggleBtn, "LEFT", -2, 0)
    hiddenLbl:SetTextColor(0.60, 0.60, 0.65)
    hiddenLbl:Hide()
    strip._hiddenLbl = hiddenLbl

    toggleBtn:SetScript("OnEnter", function()
        GameTooltip:SetOwner(toggleBtn, "ANCHOR_TOP")
        GameTooltip:AddLine(_tagStripCollapsed and "Expand tags" or "Collapse tags", 1, 1, 1)
        GameTooltip:Show()
    end)
    toggleBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    toggleBtn:SetScript("OnClick", function()
        if BNB.ToggleTagStrip then BNB.ToggleTagStrip() end
    end)
    strip._toggleBtn = toggleBtn
    strip._toggleTx  = toggleTx

    tagStripFrame = strip

    -- Register chip rebuild as a skin backdrop callback so chips recolour
    -- immediately when the user changes preset or brightness in config.
    if BigNoteBoxDB and BigNoteBoxDB.skinMode and BNB.RegisterSkinBackdrop then
        BNB.RegisterSkinBackdrop(function()
            if BNB.RefreshTagStrip then BNB.RefreshTagStrip() end
        end)
    end

    return strip, sep
end

-- Public: toggle tag strip between full height and one-row-collapsed height.
-- Collapsed = first row only remains visible; chips on rows 2+ are hidden.
-- The toggle TGA swaps between open/close icons.
local function ApplyTagStripCollapse(strip, collapsed)
    if not strip then return end
    if collapsed then
        -- Hide all chips on row 2+ and count them
        local hiddenCount = 0
        for _, chip in ipairs(tagChips) do
            if chip._row and chip._row > 1 then
                chip:Hide()
                hiddenCount = hiddenCount + 1
            else
                chip:Show()
            end
        end
        -- Hide add-input if it landed on row 2+
        if strip._addInput then
            if (strip._inputRow or 1) > 1 then
                strip._addInput:Hide()
            end
        end
        strip:SetHeight(CHIP_ROW_H)
        -- Show badge if any chips are hidden
        if strip._hiddenLbl then
            if hiddenCount > 0 then
                strip._hiddenLbl:SetText("+" .. hiddenCount)
                strip._hiddenLbl:Show()
            else
                strip._hiddenLbl:Hide()
            end
        end
    else
        -- Show everything
        for _, chip in ipairs(tagChips) do chip:Show() end
        if strip._addInput and (strip._numRows or 1) < (MAX_TAGS) then
            strip._addInput:Show()
        end
        strip:SetHeight((strip._numRows or 1) * CHIP_ROW_H)
        -- Hide badge when expanded
        if strip._hiddenLbl then strip._hiddenLbl:Hide() end
    end
end

function BNB.ToggleTagStrip()
    local strip = tagStripFrame
    if not strip then return end
    _tagStripCollapsed = not _tagStripCollapsed
    local sep = BNB._editorTagStripSep

    ApplyTagStripCollapse(strip, _tagStripCollapsed)

    if sep then sep:Show() end
    local bs = BNB._editorBodyScroll
    if bs then
        bs:SetPoint("BOTTOMRIGHT", BNB.editorPane, "BOTTOMRIGHT", -22,
            TOOLBAR_H + strip:GetHeight() + PAD)
    end
    if strip._toggleTx then
        strip._toggleTx:SetTexture(ASSETS_TAG ..
            (_tagStripCollapsed and "UI\\ui-tags-close" or "UI\\ui-tags-open"))
    end
end

-- Public: rebuild chips for current note
function BNB.RefreshTagStrip()
    if not tagStripFrame then return end
    local id   = BNB._currentNoteID
    local note = id and BNB.GetNote(id)
    RebuildTagChips(tagStripFrame, note and note.tags or {})
    -- Reapply collapsed state so chips on rows 2+ stay hidden if toggled
    if _tagStripCollapsed then
        ApplyTagStripCollapse(tagStripFrame, true)
        local bs = BNB._editorBodyScroll
        if bs then
            bs:SetPoint("BOTTOMRIGHT", BNB.editorPane, "BOTTOMRIGHT", -22,
                TOOLBAR_H + CHIP_ROW_H + PAD)
        end
    else
        local bs = BNB._editorBodyScroll
        if bs then
            bs:SetPoint("BOTTOMRIGHT", BNB.editorPane, "BOTTOMRIGHT", -22,
                TOOLBAR_H + tagStripFrame:GetHeight() + PAD)
        end
    end
end

--------------------------------------------------------------------------------
-- SET EDITOR LOCKED STATE
-- locked = true  → editboxes disabled, Edit button shown, Save hidden
-- locked = false → editboxes enabled,  Edit button hidden, Save shown
--------------------------------------------------------------------------------
local function SetEditorLocked(locked)
    BNB._editorLocked = locked

    if BNB._editorTitle then
        BNB._editorTitle:SetEnabled(not locked)
    end
    if BNB._editorBody then
        BNB._editorBody:SetEnabled(not locked)
        local a = locked and 0.55 or 1
        pcall(function() BNB._editorBody:SetAlpha(a) end)
    end

    local toolbar = BNB._editorToolbar
    if toolbar then
        -- Lock button: always visible.
        -- lock.tga   = note is unlocked  → click to lock
        -- unlock.tga = note is locked    → click to unlock
        local id2      = BNB._currentNoteID
        local note2    = id2 and BNB.GetNote(id2)
        local noteLocked = note2 and NoteIsLocked(note2)
        if toolbar._lockBtn then
            toolbar._lockBtn:SetShown(true)
            if toolbar._lockTx then
                local ASSETS = "Interface\\AddOns\\BigNoteBox\\Assets\\"
                toolbar._lockTx:SetTexture(ASSETS .. (noteLocked and "Actionbar\\ab-unlock" or "Actionbar\\ab-lock"))
            end
        end
        -- Pin button: always visible (lock state does not hide it)
        -- (no change needed — pinBtn has no SetShown call here)

        -- Only save and delete are greyed when locked
        if toolbar._saveBtn then
            saveBtn:SetEnabled(not locked and BNB._dirty == true)
            saveBtn:SetAlpha((not locked and BNB._dirty == true) and 1.0 or 0.4)
            pcall(function() saveBtn._tx:SetDesaturated(locked or not BNB._dirty) end)
        end
        if toolbar._delBtn then toolbar._delBtn:SetIconEnabled(not locked) end
        -- dup, copy, pin, send -- always active regardless of lock state
    end
    -- Undo/redo buttons must also dim when the note is locked
    if BNB._refreshUndoButtons then BNB._refreshUndoButtons() end
end

--------------------------------------------------------------------------------
-- LOAD NOTE IN EDITOR
--------------------------------------------------------------------------------
function BNB.LoadNoteInEditor(id)
    local note       = id and BNB.GetNote(id)
    local emptyState = BNB._editorEmptyState
    local titleBg    = BNB._editorTitleBg
    local titleEb    = BNB._editorTitle
    local bodyEb     = BNB._editorBody
    local toolbar    = BNB._editorToolbar
    local titleUl    = BNB._editorTitleUnderline
    local tsStrip    = BNB._editorTimestamp

    if not note then
        if emptyState then emptyState:Show() end
        if titleBg    then titleBg:Hide()    end
        if titleUl    then titleUl:Hide()    end
        if tsStrip    then tsStrip:Hide()    end

        if BNB._editorStatsStrip  then BNB._editorStatsStrip:Hide()  end
        if BNB._editorBodyScroll  then BNB._editorBodyScroll:Hide()  end
        if BNB._editorRenderScroll then BNB._editorRenderScroll:Hide() end
        if BNB._editorRenderFrame  then BNB._editorRenderFrame:Hide()  end
        if BNB._editorMarkupBar    then BNB._editorMarkupBar:Hide()    end
        if BNB._editorRichTabs     then BNB._editorRichTabs:Hide()     end
        BNB._editorInViewMode = false
        BNB._viewModeGen = (BNB._viewModeGen or 0) + 1
        if BNB._editorTagStrip    then BNB._editorTagStrip:Hide()    end
        if BNB._editorTagStripSep then BNB._editorTagStripSep:Hide() end
        if BNB._editorTagStrip and BNB._editorTagStrip._toggleBtn then
            BNB._editorTagStrip._toggleBtn:Hide()
            if BNB._editorTagStrip._hiddenLbl then
                BNB._editorTagStrip._hiddenLbl:Hide()
            end
        end
        if toolbar    then toolbar:Hide()    end
        if BNB._editorWysiwygBar then BNB._editorWysiwygBar:Hide() end
        BNB._currentNoteID = nil
        BNB._dirty = false
        if BNB._sessionUnlocked and id then BNB._sessionUnlocked[id] = nil end
        BNB.UpdateSaveButtonState()
        if BNB.RichPreview then BNB.RichPreview.OnNoteCleared() end
        return
    end

    if emptyState then emptyState:Hide() end
    if titleBg    then titleBg:Show()    end
    if titleUl    then titleUl:Show()    end
    if BNB._editorBodyScroll  then BNB._editorBodyScroll:Show()  end
    -- Respect collapsed state; always show the toggle button
    if BNB._editorTagStrip then
        if _tagStripCollapsed then
            BNB._editorTagStrip:Hide()
            if BNB._editorTagStripSep then BNB._editorTagStripSep:Hide() end
        else
            BNB._editorTagStrip:Show()
            if BNB._editorTagStripSep then BNB._editorTagStripSep:Show() end
        end
        if BNB._editorTagStrip._toggleBtn then
            BNB._editorTagStrip._toggleBtn:Show()
        end
    end
    if toolbar    then toolbar:Show()    end

    -- Show/hide wysiwyg bar per persisted setting
    local wyBar = BNB._editorWysiwygBar
    if wyBar then
        local db2 = BigNoteBoxDB
        if db2 and db2.wysiwygBarVisible ~= false then
            wyBar:Show()
        else
            wyBar:Hide()
        end
    end

    BNB._dirty = false

    -- Cancel any pending snapshot timers for the previous note before resetting.
    local prevID = BNB._currentNoteID  -- still the old ID at this point in LoadNoteInEditor
    if prevID then
        if _undoTimers[prevID] then _undoTimers[prevID]:Cancel(); _undoTimers[prevID] = nil end
        if _undoForced[prevID] then _undoForced[prevID]:Cancel(); _undoForced[prevID] = nil end
    end

    -- Reset undo/redo stacks for the newly loaded note.
    -- We pass the body text so UndoPush has a clean starting snapshot.
    BNB.UndoReset(id, note.body or "")
    if BNB._refreshUndoButtons    then BNB._refreshUndoButtons()    end
    if BNB._refreshWysiwygFont    then BNB._refreshWysiwygFont()    end
    if BNB.SyncHistoryNoteBtnState then BNB.SyncHistoryNoteBtnState() end
    if BNB._wysiwygRestoreBtn  then BNB._wysiwygRestoreBtn:SetIconEnabled(true)  end
    if BNB._wysiwygCopyMoveBtn then BNB._wysiwygCopyMoveBtn:SetIconEnabled(true) end

    -- Timestamps + creation coordinates
    if tsStrip then
        local db  = BigNoteBoxDB
        local fmt = db and db.dateFormat or "YYYY-MM-DD"
        local isRelative = (fmt == "relative")

        local createdStr, updatedStr
        if isRelative then
            createdStr = note.created and ("Created " .. FmtTime(note.created)) or ""
            updatedStr = note.updated and ("  •  Edited " .. FmtTime(note.updated)) or ""
        else
            createdStr = note.created and ("C: " .. FmtTime(note.created)) or ""
            updatedStr = note.updated and ("  •  E: " .. FmtTime(note.updated)) or ""
        end

        local coords
        if note.coordX and note.coordY then
            coords = string.format("  •  %.2f %.2f", note.coordX, note.coordY)
        else
            coords = "  •  Unknown"
        end
        tsStrip:SetText(createdStr .. updatedStr .. coords)
        tsStrip:Show()
    end
    -- Enable map button only when the note has coord data
    if BNB._wysiwygMapBtn then
        BNB._wysiwygMapBtn:SetIconEnabled(note.coordX ~= nil and note.coordMapID ~= nil)
    end
    if BNB._editorStatsStrip then BNB._editorStatsStrip:Show() end

    -- Per-note font override
    local fontOverride = note.fontOverride
    local appliedOverride = false
    if fontOverride and BNB.GetFontDef then
        local def = BNB.GetFontDef(fontOverride)
        if def then
            local sz = (note.fontSize) or (BigNoteBoxDB and BigNoteBoxDB.fontSize) or 12
            if BNB._editorBody  then pcall(function() BNB._editorBody:SetFont(def.regular, sz, "") end) end
            if BNB._editorTitle then pcall(function() BNB._editorTitle:SetFont(def.bold, 20, "") end) end
            appliedOverride = true
        end
    end
    if not appliedOverride then
        if BNB.ApplyFont then BNB.ApplyFont() end
    end
    -- Apply per-note font size override regardless of font override
    if note.fontSize and BNB._editorBody then
        local path = select(1, BNB._editorBody:GetFont())
        if path then pcall(function() BNB._editorBody:SetFont(path, note.fontSize, "") end) end
    end
    if BNB._editorBody then
        pcall(function() BNB._editorBody:SetJustifyH(note.textAlign or "LEFT") end)
        local outline = note.fontOutline or "None"
        local flags = ""
        if     outline == "Outline"            then flags = "OUTLINE"
        elseif outline == "Thick Outline"      then flags = "THICKOUTLINE"
        elseif outline == "Monochrome Outline" then flags = "MONOCHROME,OUTLINE"
        elseif outline == "SLUG"               then flags = "SLUG"
        elseif outline == "SLUG Outline"       then flags = "OUTLINE, SLUG"
        elseif outline == "SLUG Thick Outline" then flags = "THICKOUTLINE, SLUG" end
        local ox, oy, sr, sg, sb, sa = 0, 0, 0, 0, 0, 0
        if     outline == "Drop Shadow"           then ox,oy,sr,sg,sb,sa = 1,-1,0,0,0,0.8
        elseif outline == "Strong Drop Shadow"    then ox,oy,sr,sg,sb,sa = 2,-2,0,0,0,1.0
        elseif outline == "Strongest Drop Shadow" then ox,oy,sr,sg,sb,sa = 3,-3,0,0,0,1.0 end
        local path, sz2 = BNB._editorBody:GetFont()
        if path then pcall(function() BNB._editorBody:SetFont(path, sz2, flags) end) end
        pcall(function() BNB._editorBody:SetShadowOffset(ox, oy) end)
        pcall(function() BNB._editorBody:SetShadowColor(sr, sg, sb, sa) end)
    end

    if titleEb then titleEb:SetRealText(note.title or "") end
    if bodyEb  then
        bodyEb:SetRealText(note.body or "")
        if BNB._editorBodyScroll then
            BNB._editorBodyScroll:SetVerticalScroll(0)
            if BNB._editorBodyScroll.UpdateScrollbar then
                BNB._editorBodyScroll:UpdateScrollbar()
            end
        end
        UpdateStatsStrip(bodyEb:GetRealText())
    end

    if toolbar then BNB.RefreshTagStrip() end

    BNB._dirty = false
    BNB.UpdateSaveButtonState()

    -- Apply lock state (session unlock overrides)
    local sessionUnlocked = BNB._sessionUnlocked and BNB._sessionUnlocked[id]
    local locked = (not sessionUnlocked) and NoteIsLocked(note)
    SetEditorLocked(locked)
    -- Sync note list lock icon and RefBox desaturation whenever editor state changes
    if BNB.RefreshNoteList     then BNB.RefreshNoteList()     end
    if BNB.RefreshReferenceBox then BNB.RefreshReferenceBox() end

    -- Rich note: default to View mode unless config says otherwise.
    -- New notes (just created this session) always open in Editor so the user
    -- can start typing immediately.
    local isRich = BNB.AdvancedMode and BNB.AdvancedMode.IsRich(note)
    if isRich then
        local openInEditor = BNB._justCreatedNoteID == id
            or (BigNoteBoxDB and BigNoteBoxDB.richOpenInEditor)
        BNB._justCreatedNoteID = nil

        if openInEditor then
            if BNB._editorMarkupBar then BNB._editorMarkupBar:Show() end
            if BNB._editorRenderScroll then BNB._editorRenderScroll:Hide() end
            if BNB._editorRenderFrame  then BNB._editorRenderFrame:Hide()  end
            if BNB._editorBodyScroll   then BNB._editorBodyScroll:Show()   end
            BNB._editorInViewMode = false
            BNB.AM_RefreshTabs()
            BNB.UpdateBodyTopAnchor()
        else
            if BNB._editorMarkupBar then BNB._editorMarkupBar:Hide() end
            BNB.AM_RefreshTabs()
            BNB.UpdateBodyTopAnchor()
            BNB.AM_EnterViewMode(id)
        end
    else
        if BNB._editorMarkupBar    then BNB._editorMarkupBar:Hide()    end
        if BNB._editorRenderScroll then BNB._editorRenderScroll:Hide() end
        if BNB._editorRenderFrame  then BNB._editorRenderFrame:Hide()  end
        if BNB._editorBodyScroll   then BNB._editorBodyScroll:Show()   end
        BNB.AM_RefreshTabs()
        BNB.UpdateBodyTopAnchor()
    end

    -- Notify live preview of note selection (rich or not)
    if BNB.RichPreview then
        BNB.RichPreview.OnNoteSelected(note)
    end
end

--------------------------------------------------------------------------------
-- PUBLIC: refresh lock state for current note (called when global lock changes)
--------------------------------------------------------------------------------
function BNB.RefreshEditorLock()
    local id   = BNB._currentNoteID
    local note = id and BNB.GetNote(id)
    if not note then return end
    local sessionUnlocked = BNB._sessionUnlocked and BNB._sessionUnlocked[id]
    SetEditorLocked((not sessionUnlocked) and NoteIsLocked(note))
    if BNB.RefreshNoteList     then BNB.RefreshNoteList()     end
    if BNB.RefreshReferenceBox then BNB.RefreshReferenceBox() end
end

--------------------------------------------------------------------------------
-- MARKUP BAR (rich notes only)
-- Sits between WYSIWYG bar and body. Shown only when a rich note is loaded.
-- Buttons insert rich-note markup tag pairs at the cursor position.
--------------------------------------------------------------------------------
local MARKUP_ASSETS = "Interface\\AddOns\\BigNoteBox\\Assets\\Toolbar\\"

local function InsertTagPair(open, close)
    local eb = BNB._editorBody
    if not eb then return end
    eb:SetFocus()

    local fullText = eb:GetText() or ""
    local curEnd   = eb:GetCursorPosition() or #fullText

    -- Detect selection: Insert("") collapses it and deletes selected text.
    -- Compare text before/after to find what was selected.
    local before = fullText
    eb:Insert("")
    local after  = eb:GetText() or ""
    local curStart = eb:GetCursorPosition() or 0

    if #after < #before then
        -- Text was selected: selected = before[curStart+1 .. curStart+(#before-#after)]
        local selected = before:sub(curStart + 1, curStart + (#before - #after))
        eb:Insert(open .. selected .. close)
        -- Place cursor after the close tag
        eb:SetCursorPosition(curStart + #open + #selected + #close)
    else
        -- No selection: insert pair and place cursor between tags
        eb:Insert(open .. close)
        eb:SetCursorPosition(curStart + #open)
    end

    BNB.MarkDirty()
end

local function InsertTag(tag)
    local eb = BNB._editorBody
    if not eb then return end
    eb:SetFocus()

    -- If text is selected, replace it; otherwise insert at cursor
    local before = eb:GetText() or ""
    eb:Insert("")
    local after = eb:GetText() or ""
    local cursor = eb:GetCursorPosition() or 0

    eb:Insert(tag)
    eb:SetCursorPosition(cursor + #tag)
    BNB.MarkDirty()
end

local function BuildMarkupBar(parent, wysiwygBar)
    local bar = CreateFrame("Frame", "BigNoteBoxMarkupBar", parent)
    bar:SetPoint("TOPLEFT",  wysiwygBar, "BOTTOMLEFT",  0, 0)
    bar:SetPoint("TOPRIGHT", wysiwygBar, "BOTTOMRIGHT", 0, 0)
    bar:SetHeight(MARKUP_H)

    -- Top separator
    local sep = bar:CreateTexture(nil, "ARTWORK")
    sep:SetHeight(1)
    sep:SetPoint("TOPLEFT",  bar, "TOPLEFT",  0, 0)
    sep:SetPoint("TOPRIGHT", bar, "TOPRIGHT", 0, 0)
    if BigNoteBoxDB and BigNoteBoxDB.skinMode and BNB.GetSkinPreset then
        local p = BNB.GetSkinPreset()
        local br, bg_, bb = BNB.SkinBorderOf(p)
        sep:SetColorTexture(br, bg_, bb, 0.20)
        BNB.RegisterSkinRule(sep, 0.20)
    else
        sep:SetColorTexture(0.22, 0.22, 0.24, 1)
    end

    -- Bottom separator (between markup bar and note body)
    local sepB = bar:CreateTexture(nil, "ARTWORK")
    sepB:SetHeight(1)
    sepB:SetPoint("BOTTOMLEFT",  bar, "BOTTOMLEFT",  0, 0)
    sepB:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 0, 0)
    if BigNoteBoxDB and BigNoteBoxDB.skinMode and BNB.GetSkinPreset then
        local p = BNB.GetSkinPreset()
        local br, bg_, bb = BNB.SkinBorderOf(p)
        sepB:SetColorTexture(br, bg_, bb, 0.20)
        BNB.RegisterSkinRule(sepB, 0.20)
    else
        sepB:SetColorTexture(0.22, 0.22, 0.24, 1)
    end

    -- Button helper
    local btnX = PAD
    local function MkBtn(label, tip, onClick)
        local btn = CreateFrame("Button", nil, bar, "UIPanelButtonTemplate")
        btn:SetSize(28, 18)
        btn:SetPoint("LEFT", bar, "LEFT", btnX, 0)
        btn:SetText(label)
        local fs = btn:GetFontString()
        if fs then pcall(function() fs:SetFont(fs:GetFont(), 10, "") end) end
        btn:SetScript("OnClick", onClick)
        btn:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:AddLine(tip, 1, 1, 1)
            GameTooltip:Show()
        end)
        btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
        btnX = btnX + 30
        return btn
    end

    local function Divider()
        local d = bar:CreateTexture(nil, "ARTWORK")
        d:SetSize(1, 14)
        d:SetPoint("LEFT", bar, "LEFT", btnX, 0)
        d:SetColorTexture(0.35, 0.35, 0.38, 1)
        btnX = btnX + 6
    end

    MkBtn("H1", "Insert H1 header: {h1}...{/h1}",
        function() InsertTagPair("{h1}", "{/h1}") end)
    MkBtn("H2", "Insert H2 header: {h2}...{/h2}",
        function() InsertTagPair("{h2}", "{/h2}") end)
    MkBtn("H3", "Insert H3 header: {h3}...{/h3}",
        function() InsertTagPair("{h3}", "{/h3}") end)
    Divider()
    MkBtn("P",  "Insert paragraph: {p}...{/p}",
        function() InsertTagPair("{p}", "{/p}") end)
    MkBtn("Pc", "Insert centered paragraph: {p:c}...{/p}",
        function() InsertTagPair("{p:c}", "{/p}") end)
    MkBtn("Pr", "Insert right-aligned paragraph: {p:r}...{/p}",
        function() InsertTagPair("{p:r}", "{/p}") end)
    MkBtn("Br", "Insert line break: {br}",
        function() InsertTag("{br}") end)
    Divider()
    -- Color picker state for Col button (shared across clicks)
    local _colPickerActive = false
    local _colPickerCancelled = false
    local _colPickerR, _colPickerG, _colPickerB = 1, 1, 1
    local _colPickerHooked = false

    MkBtn("Col", "Pick a colour, then insert {col:rrggbb}...{/col}",
        function()
            local eb = BNB._editorBody
            if not eb then return end
            _colPickerActive = true
            _colPickerCancelled = false
            _colPickerR, _colPickerG, _colPickerB = 1, 1, 1
            if ColorPickerFrame.SetupColorPickerAndShow then
                ColorPickerFrame:SetupColorPickerAndShow({
                    swatchFunc = function()
                        _colPickerR, _colPickerG, _colPickerB = ColorPickerFrame:GetColorRGB()
                    end,
                    cancelFunc = function() _colPickerCancelled = true end,
                    hasOpacity = false, r = 1, g = 1, b = 1,
                })
                if not _colPickerHooked then
                    _colPickerHooked = true
                    ColorPickerFrame:HookScript("OnHide", function()
                        if not _colPickerActive then return end
                        _colPickerActive = false
                        if _colPickerCancelled then return end
                        local hex = string.format("%02x%02x%02x",
                            math.floor(_colPickerR * 255 + 0.5),
                            math.floor(_colPickerG * 255 + 0.5),
                            math.floor(_colPickerB * 255 + 0.5))
                        InsertTagPair("{col:" .. hex .. "}", "{/col}")
                    end)
                end
            end
        end)
    MkBtn("Lnk", "Insert link — opens dialog",
        function() BNB.OpenLnkDialog(InsertTag) end)
    MkBtn("Ico", "Insert icon — opens picker",
        function() BNB.OpenIcoDialog(InsertTag) end)
    MkBtn("Img", "Insert image tag with filename and size",
        function() BNB.OpenImgDialog(InsertTag) end)

    -- "Live Preview" toggle — right-aligned, does not advance btnX
    local previewBtn = CreateFrame("Button", nil, bar, "UIPanelButtonTemplate")
    previewBtn:SetSize(72, 18)
    previewBtn:SetPoint("RIGHT", bar, "RIGHT", -PAD, 0)
    previewBtn:SetText(L["MARKUP_PREVIEW_BTN"])
    local pfs = previewBtn:GetFontString()
    if pfs then pcall(function() pfs:SetFont(pfs:GetFont(), 10, "") end) end
    previewBtn:SetAlpha(0.45)   -- dim until a preview window is open
    previewBtn:SetScript("OnClick", function()
        if BNB.RichPreview then BNB.RichPreview.Toggle() end
    end)
    previewBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(L["MARKUP_PREVIEW_TIP"], 1, 1, 1)
        GameTooltip:Show()
    end)
    previewBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    BNB._markupPreviewBtn = previewBtn

    bar:Hide()
    return bar
end

--------------------------------------------------------------------------------
-- RICH NOTE: Editor/View tab strip
-- Children of mainFrame, anchored below the editorPane right half.
-- Only visible when a rich note is loaded.
--------------------------------------------------------------------------------
local TAB_H        = 32   -- height of the Editor/View icon button strip
local _richTabStrip = nil

local function BuildRichTabStrip()
    if _richTabStrip then return _richTabStrip end
    local mf = BNB.mainFrame
    if not mf then return nil end

    local strip = CreateFrame("Frame", "BigNoteBoxRichTabStrip", mf)
    strip:SetHeight(TAB_H)
    -- Anchored below editorPane right portion; left edge at list/editor split
    local function ReAnchor()
        local lw = BNB._listPaneW or 256
        strip:ClearAllPoints()
        strip:SetPoint("TOPLEFT",    mf, "BOTTOMLEFT",  lw + 1, 0)
        strip:SetPoint("TOPRIGHT",   mf, "BOTTOMRIGHT", 0,      0)
    end
    ReAnchor()
    mf:HookScript("OnSizeChanged", function() ReAnchor() end)

    -- Tab buttons
    local BTN_PATH = "Interface\\AddOns\\BigNoteBox\\Assets\\Buttons\\"

    -- Creates a textured icon button for the Editor/View toggle.
    -- normal/hover/press are bare asset names (no path prefix needed).
    -- active = true  -> full alpha (this is the current mode)
    -- active = false -> dimmed alpha (the other mode)
    local function MakeRichBtn(assetBase, tip, xOff)
        local btn = CreateFrame("Button", nil, strip)
        btn:SetSize(32, 32)
        btn:SetPoint("TOPLEFT", strip, "TOPLEFT", xOff, -(TAB_H - 32) / 2)
        btn:SetHighlightTexture("")
        btn:SetPushedTexture("")

        local n = btn:CreateTexture(nil, "ARTWORK"); n:SetAllPoints()
        n:SetTexture(BTN_PATH .. assetBase .. "-normal")
        local h = btn:CreateTexture(nil, "ARTWORK"); h:SetAllPoints()
        h:SetTexture(BTN_PATH .. assetBase .. "-hover"); h:Hide()
        local p = btn:CreateTexture(nil, "ARTWORK"); p:SetAllPoints()
        p:SetTexture(BTN_PATH .. assetBase .. "-press"); p:Hide()

        btn._n, btn._h, btn._p = n, h, p

        btn:SetScript("OnMouseDown", function(self)
            p:Show(); n:Hide(); h:Hide()
        end)
        btn:SetScript("OnMouseUp", function(self)
            p:Hide(); h:Show(); n:Hide()
        end)
        btn:SetScript("OnEnter", function(self)
            n:Hide(); h:Show()
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:AddLine(tip, 1, 1, 1)
            GameTooltip:Show()
        end)
        btn:SetScript("OnLeave", function()
            p:Hide(); h:Hide(); n:Show()
            GameTooltip:Hide()
        end)
        return btn
    end

    local editorTab = MakeRichBtn("bt-editor", "Editor mode — edit the rich note markup", 0)
    local viewTab   = MakeRichBtn("bt-view",   "View mode — render the rich note",        36)

    strip._editorTab = editorTab
    strip._viewTab   = viewTab
    strip:Hide()

    editorTab:SetScript("OnClick", function()
        if BNB.AM_EnterEditMode then BNB.AM_EnterEditMode() end
    end)
    viewTab:SetScript("OnClick", function()
        -- Save unsaved changes so View mode renders the latest content
        if BNB._dirty and BNB.SaveCurrentNote then BNB.SaveCurrentNote() end
        if BNB.AM_EnterViewMode then BNB.AM_EnterViewMode(BNB._currentNoteID) end
    end)

    _richTabStrip = strip
    BNB._editorRichTabs = strip
    return strip
end

--------------------------------------------------------------------------------
-- PUBLIC: Rich mode enter/exit
--------------------------------------------------------------------------------
function BNB.AM_RefreshTabs()
    local strip = BNB._editorRichTabs or _richTabStrip
    if not strip then return end
    local note  = BNB._currentNoteID and BNB.GetNote(BNB._currentNoteID)
    if not (note and note.richMode) then
        strip:Hide()
        return
    end
    strip:Show()
    -- Active button: full alpha. Inactive: dimmed (transparency only, per design).
    local inView = BNB._editorInViewMode == true
    local ACTIVE_ALPHA   = 1.0
    local INACTIVE_ALPHA = 0.40
    if strip._editorTab then strip._editorTab:SetAlpha(inView and INACTIVE_ALPHA or ACTIVE_ALPHA) end
    if strip._viewTab   then strip._viewTab:SetAlpha(inView and ACTIVE_ALPHA or INACTIVE_ALPHA)   end
end

function BNB.AM_EnterViewMode(id)
    BNB._editorInViewMode = true
    local note = id and BNB.GetNote(id)
    if not note then return end

    -- Build render scroll frame + render frame lazily
    if not BNB._editorRenderScroll then
        local rsf = CreateFrame("ScrollFrame", "BigNoteBoxRenderScroll",
                                BNB.editorPane, "ScrollFrameTemplate")
        BNB._editorRenderScroll = rsf

        local scrollBar = rsf.ScrollBar
        if scrollBar then
            scrollBar:SetAlpha(0)
            rsf:HookScript("OnScrollRangeChanged", function(_, _, yRange)
                scrollBar:SetAlpha((yRange or 0) > 1 and 1.0 or 0)
            end)
        end

        local rf = BNB.AdvancedMode.CreateRenderFrame(
            "BigNoteBoxRenderFrame", rsf)
        BNB._editorRenderFrame = rf
        rf:SetWidth(rsf:GetWidth() > 0 and rsf:GetWidth() or 400)
        rf:SetHeight(1)
        rsf:SetScrollChild(rf)

        -- Keep render frame width in sync with scroll frame.
        -- Also re-renders on resize (window drag) so content reflows at new width.
        rsf:SetScript("OnSizeChanged", function(self)
            local w = self:GetWidth()
            if not w or w <= 0 then return end
            rf:SetWidth(w)
            -- Re-render if view mode is currently active
            if BNB._editorInViewMode and BNB._currentNoteID then
                local rn = BNB.GetNote(BNB._currentNoteID)
                if rn then
                    local bs = rn.fontSize or (BigNoteBoxDB and BigNoteBoxDB.fontSize) or 12
                    local fs = BNB.AdvancedMode.OutlineFlagStr(rn.fontOutline)
                    BNB.AdvancedMode.ApplyFontsToRenderFrame(rf, bs, fs)
                    local rawST = getmetatable(rf).__index.SetText
                    rawST(rf, BNB.AdvancedMode.ToHTML(rn.body or "", bs))
                    rf:SetHeight(rf:GetContentHeight())
                end
            end
        end)

        rsf:Hide()
    end

    if BNB._editorBodyScroll then BNB._editorBodyScroll:Hide() end
    if BNB._editorMarkupBar  then BNB._editorMarkupBar:Hide()  end

    local rsf = BNB._editorRenderScroll
    local rf  = BNB._editorRenderFrame
    BNB.UpdateBodyTopAnchor()
    rf:Show()
    rsf:Show()
    rsf:SetVerticalScroll(0)

    -- Generation counter: stale deferred ticks from previous note switches
    -- must not overwrite the current note's content.
    BNB._viewModeGen = (BNB._viewModeGen or 0) + 1
    local gen = BNB._viewModeGen

    -- Defer content rendering by one frame so the layout engine resolves
    -- editorPane width. On the same tick the window is first shown, GetWidth()
    -- returns 0, which leaves the SimpleHTML with no reflow width -> blank.
    C_Timer.After(0, function()
        -- Stale tick from a previous note switch or mode change
        if BNB._viewModeGen ~= gen then return end
        if not BNB._editorInViewMode then return end
        if not rsf:IsShown() then return end

        local paneW = BNB.editorPane:GetWidth()
        if paneW and paneW > 0 then
            rf:SetWidth(paneW - PAD - 22)
        end

        -- Re-read note in case it was saved between the call and the tick
        local freshNote = id and BNB.GetNote(id)
        if not freshNote then return end

        local bodySize = freshNote.fontSize or (BigNoteBoxDB and BigNoteBoxDB.fontSize) or 12
        local flagStr  = BNB.AdvancedMode.OutlineFlagStr(freshNote.fontOutline)
        BNB.AdvancedMode.ApplyFontsToRenderFrame(rf, bodySize, flagStr)

        local html = BNB.AdvancedMode.ToHTML(freshNote.body or "", bodySize)
        local rawST = getmetatable(rf).__index.SetText
        rawST(rf, html)
        rf:SetHeight(rf:GetContentHeight())

        -- Scroll to top
        rsf:SetVerticalScroll(0)
    end)

    BNB.AM_RefreshTabs()
end

function BNB.AM_EnterEditMode()
    BNB._editorInViewMode = false
    BNB._viewModeGen = (BNB._viewModeGen or 0) + 1  -- invalidate pending deferred ticks
    if BNB._editorRenderScroll then BNB._editorRenderScroll:Hide() end
    if BNB._editorRenderFrame  then BNB._editorRenderFrame:Hide()  end
    if BNB._editorBodyScroll   then BNB._editorBodyScroll:Show()   end

    local note = BNB._currentNoteID and BNB.GetNote(BNB._currentNoteID)
    if note and note.richMode and BNB._editorMarkupBar then
        BNB._editorMarkupBar:Show()
    end

    BNB.UpdateBodyTopAnchor()
    BNB.AM_RefreshTabs()
end

-- Toggle between view and editor mode for the currently loaded rich note.
-- No-op if no note is selected or the selected note is not a rich note.
-- Called by the keybind (BNB_KeybindToggleRichView) and can also be used
-- by other systems that want to flip modes programmatically.
function BNB.ToggleRichViewEdit()
    local note = BNB._currentNoteID and BNB.GetNote(BNB._currentNoteID)
    if not note or not note.richMode then return end
    if BNB._editorInViewMode then
        if BNB.AM_EnterEditMode then BNB.AM_EnterEditMode() end
    else
        if BNB.AM_EnterViewMode then BNB.AM_EnterViewMode(BNB._currentNoteID) end
    end
end

--------------------------------------------------------------------------------
-- BUILD NOTE EDITOR
--------------------------------------------------------------------------------
function BNB.BuildNoteEditor()
    local pane = BNB.editorPane
    if not pane then return end

    local emptyState = BuildEmptyState(pane)
    BNB._editorEmptyState = emptyState

    local titleBg, titleEb, titleUl, tsStrip, statsStrip = BuildTitleField(pane)
    BNB._editorTitleBg        = titleBg
    BNB._editorTitle          = titleEb
    BNB._editorTitleUnderline = titleUl
    BNB._editorTimestamp      = tsStrip
    BNB._editorStatsStrip     = statsStrip

    -- Invisible button overlaid on the right half of the timestamp strip.
    -- Becomes clickable only when the current note has coord data.
    local toolbar = BuildToolbar(pane)
    BNB._editorToolbar = toolbar

    -- Tag strip sits between body and toolbar — build after toolbar so we know TOOLBAR_H
    local tagStrip, tagStripSep = BuildTagStrip(pane, toolbar)
    BNB._editorTagStrip    = tagStrip
    BNB._editorTagStripSep = tagStripSep

    -- WYSIWYG bar sits between timestamp strip and body.
    -- topAnchor is the bar when visible, tsStrip when hidden.
    local wysiwygBar = BuildWysiwygBar(pane, tsStrip)
    BNB._editorWysiwygBar = wysiwygBar

    -- Markup bar sits between WYSIWYG bar and body (rich notes only).
    local markupBar = BuildMarkupBar(pane, wysiwygBar)
    BNB._editorMarkupBar = markupBar

    local topAnchor  = (BigNoteBoxDB and BigNoteBoxDB.wysiwygBarVisible ~= false)
                       and wysiwygBar or tsStrip
    local bodyScroll, bodyEb = BuildBodyField(pane, topAnchor)
    BNB._editorBodyScroll = bodyScroll
    BNB._editorBody       = bodyEb

    -- When focus enters the body, the user is still working on the new note —
    -- dismiss any open discard popup so it doesn't fire while they type.
    bodyEb:HookScript("OnEditFocusGained", function()
        if BNB._pendingNewNoteID == BNB._currentNoteID then
            StaticPopup_Hide("BNB_DISCARD_NEW_NOTE")
        end
    end)

    titleBg:Hide()
    titleUl:Hide()
    tsStrip:Hide()
    statsStrip:Hide()
    bodyScroll:Hide()
    tagStrip:Hide()
    tagStripSep:Hide()
    if tagStrip._toggleBtn then tagStrip._toggleBtn:Hide() end
    if tagStrip._hiddenLbl then tagStrip._hiddenLbl:Hide() end
    toolbar:Hide()
    wysiwygBar:Hide()
    markupBar:Hide()
    emptyState:Show()

    -- Build rich tab strip (deferred one tick so mainFrame exists and is sized)
    C_Timer.After(0, function() BuildRichTabStrip() end)
end


-- BigNoteBox UI/WelcomePanel.lua - Editor welcome panel (shown when no note is selected)
-- Greeting, clock, location and favorite note rows, quick actions and the import window.
-- Split out of NoteEditor.lua (ALL-65.10); built by BNB.BuildNoteEditor.

local BNB = BigNoteBox
local L   = BNB.L

local COL_GREY = { 0.50, 0.50, 0.50, 1 }

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
            GameTooltip:AddLine(L["NE_CLICK_OPEN_STICKY_TIP"], 0.7, 0.7, 0.7)
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
        local boldPath = BNB.GetUIBoldFont and BNB.GetUIBoldFont()
        if boldPath then greetLbl:SetFont(boldPath, 15, "")
        else greetLbl:SetFontObject("GameFontNormal") end
    end)
    greetLbl:SetTextColor(0.9, 0.9, 0.9)

    -- ── Clock ─────────────────────────────────────────────────────────────────
    local clockLbl = f:CreateFontString(nil, "OVERLAY")
    clockLbl:SetPoint("TOP", greetLbl, "BOTTOM", 0, -(LINE_PAD + 4))
    clockLbl:SetJustifyH("CENTER")
    pcall(function()
        local boldPath = BNB.GetUIBoldFont and BNB.GetUIBoldFont()
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
        local bodyPath = BNB.GetUIFont and BNB.GetUIFont()
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
    hintLbl:SetText(L["NE_SELECT_OR_CREATE_HINT"])

    -- ── Create a new note button ─────────────────────────────────────────────
    -- In skin mode use a backdrop-based skin button (avoids NineSlice tint issues).
    -- In normal mode use the fancy large WoW template.
    local newBtn
    local skinMode = BigNoteBoxDB and BigNoteBoxDB.skinMode
    if skinMode then
        newBtn = BNB.CreateSkinButton(nil, f, L["NE_CREATE_NEW_NOTE_BTN"], 200, 40, 16)
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
        newBtn:SetText(L["NE_CREATE_NEW_NOTE_BTN"])
        local bfs = newBtn:GetFontString()
        if bfs then pcall(function() bfs:SetFont(BNB.GetLocaleFont(), 16, "") end) end
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
        GameTooltip:AddLine(L["NE_IMPORT_NOTES_TIP_TITLE"], 1, 1, 1)
        GameTooltip:AddLine(L["NE_IMPORT_NOTES_TIP_BODY"], 0.7, 0.7, 0.7)
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
        GameTooltip:AddLine(cfgOpen and L["NE_CLOSE_CONFIG_TIP"] or L["NE_OPEN_CONFIG_TIP"], 1, 1, 1)
        GameTooltip:AddLine(L["NE_OPEN_CONFIG_TIP_BODY"], 0.7, 0.7, 0.7)
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
        locHeader:SetText(string.format(L["NE_NOTES_FOR_FMT"], zoneName or L["NE_THIS_AREA"]))

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

BNB._BuildEditorEmptyState = BuildEmptyState

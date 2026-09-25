-- BigNoteBox UI/TagDialogs.lua - Img / Lnk / Ico tag dialogs
-- Opened from the markup bars in NoteEditor.lua and FocusEditor.lua.
-- Split out of NoteEditor.lua (ALL-65.10).

local BNB = BigNoteBox
local L   = BNB.L

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
local ALIGN_LABELS = { L["STICKY_ALIGN_CENTER"], L["STICKY_ALIGN_LEFT"], L["STICKY_ALIGN_RIGHT"] }

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
            BNB.SeatChrome(f)   -- FOR-05: Forever border offset (UI/Chrome.lua)
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
            titleLbl:SetText(L["NE_INSERT_IMAGE_TITLE"]); titleLbl:SetTextColor(1, 0.82, 0)
            local closeBtn = BNB.CreateSkinCloseButton(titleBar, function() f:Hide() end)
            closeBtn:SetPoint("RIGHT", titleBar, "RIGHT", -3, 0)
        else
            f:SetTitle(L["NE_INSERT_IMAGE_TITLE"])
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
            Lbl(L["NE_PICK_USERIMAGES"])
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
                    selImage > 0 and pickLabels[selImage] or L["NE_SELECT_IMAGE_PLACEHOLDER"],
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
        Lbl(L["NE_ALIGNMENT_LABEL"])

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
        wLbl:SetTextColor(0.78, 0.78, 0.78); wLbl:SetText(L["NE_WIDTH_LABEL"])
        local hLbl = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        hLbl:SetPoint("TOPLEFT", f, "TOPLEFT", DPAD + NUM_W + NUM_GAP, curY)
        hLbl:SetTextColor(0.78, 0.78, 0.78); hLbl:SetText(L["NE_HEIGHT_LABEL"])
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

        local cancelBtn = BNB.CreateButton(nil, f, L["CANCEL"], 90, BTN_H)
        cancelBtn:SetPoint("BOTTOM", f, "BOTTOM", 53, DPAD)
        cancelBtn:SetScript("OnClick", function() f:Hide() end)

        local insertBtn = BNB.CreateButton(nil, f, L["NE_INSERT_BTN"], 90, BTN_H)
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
            BNB.SeatChrome(f)   -- FOR-05: Forever border offset (UI/Chrome.lua)
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
            titleLbl:SetText(L["NE_INSERT_LINK_TITLE"]); titleLbl:SetTextColor(1, 0.82, 0)
            local closeBtn = BNB.CreateSkinCloseButton(titleBar, function() f:Hide() end)
            closeBtn:SetPoint("RIGHT", titleBar, "RIGHT", -3, 0)
        else
            f:SetTitle(L["NE_INSERT_LINK_TITLE"])
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

        Lbl(L["NE_URL_LABEL"])
        local urlEb = FieldEB(INNER_W)
        f._urlEb = urlEb

        curY = curY - 2
        Lbl(L["NE_LINK_TEXT_LABEL"])
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

        local cancelBtn = BNB.CreateButton(nil, f, L["CANCEL"], 90, BTN_H)
        cancelBtn:SetPoint("BOTTOM", f, "BOTTOM", 53, DPAD)
        cancelBtn:SetScript("OnClick", function() f:Hide() end)

        local insertBtn = BNB.CreateButton(nil, f, L["NE_INSERT_BTN"], 90, BTN_H)
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
            BNB.SeatChrome(f)   -- FOR-05: Forever border offset (UI/Chrome.lua)
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
            titleLbl:SetText(L["NE_INSERT_ICON_TITLE"]); titleLbl:SetTextColor(1, 0.82, 0)

            local closeBtn = BNB.CreateSkinCloseButton(titleBar, function() f:Hide() end)
            closeBtn:SetPoint("RIGHT", titleBar, "RIGHT", -3, 0)
        else
            -- Normal mode: use ButtonFrameTemplate's built-in title and close button
            if f.TitleText then
                f.TitleText:SetText(L["NE_INSERT_ICON_TITLE"])
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
        local TAB_LABELS = { L["NC_TAB_BNB_ICONS"], L["NC_TAB_BLIZZARD_ICON"] }
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
        BNB.AddPlaceholder(searchEb, L["NC_SEARCH_ICONS_PLACEHOLDER"], 0.40, 0.40, 0.40)

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
        BNB.AddPlaceholder(sizeEb, L["NE_SIZE_LABEL"], 0.40, 0.40, 0.40)
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
        searchLbl2:SetText(L["NE_ICON_NAME_LABEL2"])

        local sizeLbl2 = panel2:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        sizeLbl2:SetPoint("TOPLEFT", panel2, "TOPLEFT", DPAD + SEARCH_W + SIZE_GAP, -8)
        sizeLbl2:SetTextColor(0.65, 0.65, 0.65)
        sizeLbl2:SetText(L["NE_SIZE_LABEL"])

        local descLbl = panel2:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        descLbl:SetPoint("TOPLEFT",  panel2, "TOPLEFT",  DPAD, -56)
        descLbl:SetPoint("TOPRIGHT", panel2, "TOPRIGHT", -DPAD, -56)
        descLbl:SetJustifyH("LEFT"); descLbl:SetWordWrap(true)
        descLbl:SetTextColor(0.65, 0.65, 0.65)
        descLbl:SetText(L["NE_ICON_NAME_DESC"])

        -- Wowhead link line
        local whLbl = panel2:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        whLbl:SetPoint("TOPLEFT",  panel2, "TOPLEFT",  DPAD, -70)
        whLbl:SetPoint("TOPRIGHT", panel2, "TOPRIGHT", -DPAD, -70)
        whLbl:SetJustifyH("LEFT")
        whLbl:SetTextColor(0.40, 0.70, 1.0)
        whLbl:SetText(L["NE_WOWHEAD_HINT"])
        -- Make the wowhead line clickable to copy the URL
        local whBtn = CreateFrame("Button", nil, panel2)
        whBtn:SetAllPoints(whLbl)
        whBtn:SetScript("OnClick", function()
            BNB.ShowClipboardHint("www.wowhead.com/icons", whBtn)
        end)
        whBtn:SetScript("OnEnter", function()
            GameTooltip:SetOwner(whBtn, "ANCHOR_TOP")
            GameTooltip:AddLine(L["NC_WP_COPY_URL_TIP"], 1, 1, 1)
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

        -- Icon autocomplete (only active when db.blizzardIconComplete is on)
        if BNB.AttachIconAutocomplete then
            BNB.AttachIconAutocomplete(nameEb, function(name)
                -- onSelect: refresh the shared preview panel.
                RefreshIcoPreview("Interface\\Icons\\" .. name)
            end)
        end

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
        BNB.AddPlaceholder(sizeEb2, L["NE_SIZE_LABEL"], 0.40, 0.40, 0.40)
        f._sizeEb2 = sizeEb2

        -- ── Shared bottom section: preview + buttons ──────────────────────────
        -- Size field is now in the search row of each tab panel.

        -- Alignment dropdown (shared — applies to both BNB icons and Blizzard icons)
        local ICO_ALIGN_ITEMS = {
            { key = "",   label = L["NE_ICO_ALIGN_INLINE"] },
            { key = ":l", label = L["STICKY_ALIGN_LEFT"]             },
            { key = ":c", label = L["NE_ICO_ALIGN_CENTRE"]           },
            { key = ":r", label = L["STICKY_ALIGN_RIGHT"]            },
        }
        local _icoAlign = ""
        local alignLbl = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        alignLbl:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", DPAD, BTN_H + DPAD * 2 + PREV_SIZE + 14)
        alignLbl:SetTextColor(0.65, 0.65, 0.65)
        alignLbl:SetText(L["NE_ALIGNMENT_LABEL"])
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
        local cancelBtn = BNB.CreateButton(nil, f, L["CANCEL"], 90, BTN_H)
        cancelBtn:SetPoint("BOTTOM", f, "BOTTOM", 53, DPAD)
        cancelBtn:SetScript("OnClick", function() f:Hide() end)

        local insertBtn = BNB.CreateButton(nil, f, L["NE_INSERT_BTN"], 90, BTN_H)
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
            BNB.AddPlaceholder(searchEb, L["NC_SEARCH_ICONS_PLACEHOLDER"], 0.40, 0.40, 0.40)
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

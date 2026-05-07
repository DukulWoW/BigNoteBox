-- BigNoteBox UI/NewNoteDialog.lua
-- "New Note" creation dialog.
-- Opens when BigNoteBoxDB.newNoteBehaviour == "prompt" (or nil, the default).
-- Parented to BNB.mainFrame on first open so it moves with it and sits centred
-- on it. The main window is dimmed with a black overlay while the dialog is open.
-- ESC / Cancel closes without creating. Create is disabled until a title is typed.
--
-- Public API:
--   BNB.NewNoteDialog.Open()
--   BNB.NewNoteDialog.Close()

local BNB = BigNoteBox
if not BNB then return end

BNB.NewNoteDialog = BNB.NewNoteDialog or {}
local NND = BNB.NewNoteDialog

-- ---------------------------------------------------------------------------
-- LAYOUT CONSTANTS
-- ---------------------------------------------------------------------------
local DLG_W    = 360
local DLG_PAD  = 12
local DLG_FOOT = 42
local DLG_CW   = DLG_W - DLG_PAD * 2   -- 336

local COL_GAP  = 8
local COL_L_W  = 148
local COL_R_W  = DLG_CW - COL_L_W - COL_GAP

local ICON_SZ  = 40
local CARD_H   = 38
local CARD_GAP = 4

-- ---------------------------------------------------------------------------
-- MODULE STATE
-- ---------------------------------------------------------------------------
local _frame       = nil
local _overlay     = nil   -- black dimmer over mainFrame
local _iconPickerF = nil
local _iconBtns    = {}

local _selIcon  = nil
local _selFont  = nil
local _selColor = nil
local _selSize  = 12
local _selRich  = false  -- whether "Rich note" checkbox is ticked

local _iconBtn    = nil
local _titleEB    = nil
local _fontBtns   = {}
local _swatchBtns = {}
local _sizeSlider     = nil
local _sizePreviewLbl = nil
local _createBtn      = nil
local _richCheck      = nil

-- ---------------------------------------------------------------------------
-- RANDOM NOTE ICON
-- ---------------------------------------------------------------------------
local NOTE_ICONS = {
    "Interface\\Icons\\INV_Misc_Note_01",
    "Interface\\Icons\\INV_Misc_Note_02",
    "Interface\\Icons\\INV_Misc_Note_03",
    "Interface\\Icons\\INV_Misc_Note_05",
    "Interface\\Icons\\INV_Misc_Note_06",
}
local function RandomNoteIcon()
    return NOTE_ICONS[math.random(#NOTE_ICONS)]
end

-- ---------------------------------------------------------------------------
-- MAIN WINDOW OVERLAY (dim + block clicks while dialog is open)
-- ---------------------------------------------------------------------------
local function ShowMainOverlay(show)
    local mf = BNB.mainFrame
    if not mf then return end
    if not _overlay or _overlay:GetParent() ~= mf then
        local ov = CreateFrame("Frame", nil, mf)
        ov:SetAllPoints()
        ov:SetFrameStrata("FULLSCREEN_DIALOG")
        ov:SetFrameLevel((mf:GetFrameLevel() or 0) + 50)
        ov:EnableMouse(true)
        local bg = ov:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0, 0, 0, 0.55)
        ov:Hide()
        _overlay = ov
    end
    if show then _overlay:Show() else _overlay:Hide() end
end

-- ---------------------------------------------------------------------------
-- ICON PICKER POPUP
-- ---------------------------------------------------------------------------
local function BuildIconPicker()
    if _iconPickerF then return _iconPickerF end

    local PICKER_W  = 280
    local PICKER_H  = 340
    local CELL      = 32
    local CELL_PAD  = 3
    local GRID_COLS = math.floor((PICKER_W - CELL_PAD * 2) / (CELL + CELL_PAD))

    local f = BNB.CreateBackdropFrame("Frame", "BNBNewNoteIconPicker", UIParent)
    BNB.SetBackdrop(f, 0.06, 0.06, 0.09, 0.97, 0.35, 0.35, 0.38, 1)
    f:SetSize(PICKER_W, PICKER_H)
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:SetToplevel(true)
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:Hide()

    local titleLbl = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    titleLbl:SetPoint("TOPLEFT",  f, "TOPLEFT",  CELL_PAD, -6)
    titleLbl:SetPoint("TOPRIGHT", f, "TOPRIGHT", -CELL_PAD, -6)
    titleLbl:SetJustifyH("CENTER")
    titleLbl:SetText("Choose Icon")

    local closeBtn = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    closeBtn:SetSize(20, 20)
    closeBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", 2, 2)
    closeBtn:SetScript("OnClick", function() f:Hide() end)

    local TOP_OFF = 24
    local sf = CreateFrame("ScrollFrame", nil, f, "ScrollFrameTemplate")
    sf:SetPoint("TOPLEFT",     f, "TOPLEFT",     CELL_PAD, -TOP_OFF)
    sf:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -24, CELL_PAD)
    if sf.ScrollBar then
        sf.ScrollBar:SetAlpha(0)
        sf:HookScript("OnScrollRangeChanged", function(_, _, yRange)
            sf.ScrollBar:SetAlpha((yRange or 0) > 1 and 1.0 or 0)
        end)
    end

    local ct = CreateFrame("Frame", nil, sf)
    ct:SetWidth(PICKER_W - CELL_PAD * 2 - 24)
    ct:SetHeight(1)
    sf:SetScrollChild(ct)

    local icons = BNB.ICON_MANIFEST or {}
    local rows  = math.max(1, math.ceil(#icons / GRID_COLS))
    ct:SetHeight(rows * (CELL + CELL_PAD) + CELL_PAD)

    for i, path in ipairs(icons) do
        local btn = _iconBtns[i]
        if not btn then
            btn = CreateFrame("Button", nil, ct)
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
                local name = (s._path or ""):match("([^\\/]+)$") or ""
                GameTooltip:AddLine(name, 1, 1, 1); GameTooltip:Show()
            end)
            btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
            _iconBtns[i] = btn
        end

        local col = (i - 1) % GRID_COLS
        local row = math.floor((i - 1) / GRID_COLS)
        btn:ClearAllPoints()
        btn:SetPoint("TOPLEFT", ct, "TOPLEFT",
            CELL_PAD + col * (CELL + CELL_PAD),
            -(CELL_PAD + row * (CELL + CELL_PAD)))
        btn._path = path
        btn._tex:SetTexture(path)
        btn:Show()

        btn:SetScript("OnClick", function(s)
            _selIcon = s._path
            for _, ib in ipairs(_iconBtns) do
                if ib._sel then ib._sel:SetShown(ib._path == _selIcon) end
            end
            if _iconBtn then _iconBtn._tex:SetTexture(_selIcon) end
            f:Hide()
        end)
    end

    _iconPickerF = f
    return f
end

-- ---------------------------------------------------------------------------
-- HIGHLIGHT HELPERS
-- ---------------------------------------------------------------------------
local function RefreshFontHighlight()
    for _, e in ipairs(_fontBtns) do
        local sel = (e.id == _selFont)
        if e.btn.SetBackdropColor then
            if sel then
                e.btn:SetBackdropColor(0.12, 0.18, 0.12, 0.95)
                e.btn:SetBackdropBorderColor(0.4, 0.8, 0.4, 1)
            else
                e.btn:SetBackdropColor(0.06, 0.06, 0.08, 0.95)
                e.btn:SetBackdropBorderColor(0.28, 0.28, 0.30, 1)
            end
        end
        if e.nameLbl then
            e.nameLbl:SetTextColor(sel and 1 or 0.85, sel and 0.82 or 0.85, sel and 0 or 0.85, 1)
        end
    end
end

local function RefreshColorHighlight()
    for _, sw in ipairs(_swatchBtns) do
        local match = _selColor and
            sw._r == _selColor.r and sw._g == _selColor.g and sw._b == _selColor.b
        if sw._ring then sw._ring:SetShown(match == true) end
    end
end

-- Apply selected font bold at 20pt to title editbox (mirrors NoteEditor title field)
local function ApplyTitleFont()
    if not _titleEB then return end
    if _selFont then
        local fonts = BNB.FONTS or {}
        for _, def in ipairs(fonts) do
            if def.id == _selFont and def.bold and def.bold ~= "" then
                pcall(function() _titleEB:SetFont(def.bold, 20, "") end)
                return
            end
        end
    end
    -- Default: use BNB bold font or WoW's large font
    local boldPath = BNB.GetBoldFont and BNB.GetBoldFont()
    if boldPath then
        pcall(function() _titleEB:SetFont(boldPath, 20, "") end)
    else
        local font, _, flags = GameFontNormalHuge:GetFont()
        if font then pcall(function() _titleEB:SetFont(font, 20, flags or "") end)
        else _titleEB:SetFontObject("GameFontNormalLarge") end
    end
end

-- ---------------------------------------------------------------------------
-- BUILD DIALOG (once; re-parented to mainFrame on first Open)
-- ---------------------------------------------------------------------------
local SK_NND_TITLE_H = 28

local function BuildDialog()
    if _frame then return _frame end

    local skinMode = BigNoteBoxDB and BigNoteBoxDB.skinMode
    local f

    if skinMode then
        f = BNB.CreateSkinFrame(UIParent, false, "BNBNewNoteDialogFrame", false)
        _G["BNBNewNoteDialogFrame"] = f
        f:SetSize(DLG_W, 10)
        f:SetFrameStrata("DIALOG")
        f:SetToplevel(true)
        f:SetClampedToScreen(true)
        f:EnableMouse(true)

        local titleBar = BNB.CreateSkinStrip(f, true, false)
        titleBar:SetPoint("TOPLEFT",  f, "TOPLEFT",  0, 0)
        titleBar:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
        titleBar:SetHeight(SK_NND_TITLE_H)

        local titleLbl = titleBar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        titleLbl:SetPoint("CENTER", titleBar, "CENTER", -12, 0)
        titleLbl:SetTextColor(1, 0.82, 0)
        titleLbl:SetText("New Note")

        local closeBtn = BNB.CreateSkinCloseButton(titleBar, function() NND.Close() end)
        closeBtn:SetPoint("RIGHT", titleBar, "RIGHT", -3, 0)

        f:SetScript("OnShow", function()
            if BNB.ApplyMainWindowSkin then BNB.ApplyMainWindowSkin() end
        end)
    else
        f = CreateFrame("Frame", "BNBNewNoteDialogFrame", UIParent, "ButtonFrameTemplate")
        f:SetSize(DLG_W, 10)
        f:SetFrameStrata("DIALOG")
        f:SetToplevel(true)
        f:SetClampedToScreen(true)
        f:EnableMouse(true)
        -- Not movable — anchored to and moves with mainFrame

        ButtonFrameTemplate_HidePortrait(f)
        ButtonFrameTemplate_HideButtonBar(f)
        if f.Inset then f.Inset:Hide() end
        f:SetTitle("New Note")
        if f.CloseButton then
            f.CloseButton:SetScript("OnClick", function() NND.Close() end)
        end
    end

    tinsert(UISpecialFrames, "BNBNewNoteDialogFrame")

    f:HookScript("OnHide", function()
        ShowMainOverlay(false)
        if _iconPickerF then _iconPickerF:Hide() end
    end)

    -- ── TOP ROW: icon + title editbox ────────────────────────────────────────
    local topY = skinMode and -(SK_NND_TITLE_H + 8) or -36

    local iconBtn = BNB.CreateBackdropFrame("Button", nil, f)
    BNB.SetBackdrop(iconBtn, 0.06, 0.06, 0.09, 0.95, 0.35, 0.35, 0.38, 1)
    iconBtn:SetSize(ICON_SZ, ICON_SZ)
    iconBtn:SetPoint("TOPLEFT", f, "TOPLEFT", DLG_PAD, topY)
    iconBtn:EnableMouse(true)
    local iconTex = iconBtn:CreateTexture(nil, "ARTWORK")
    iconTex:SetPoint("TOPLEFT",     iconBtn, "TOPLEFT",      3,  -3)
    iconTex:SetPoint("BOTTOMRIGHT", iconBtn, "BOTTOMRIGHT", -3,   3)
    iconTex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    iconBtn._tex = iconTex
    local iconHi = iconBtn:CreateTexture(nil, "HIGHLIGHT")
    iconHi:SetAllPoints(); iconHi:SetColorTexture(1, 1, 1, 0.15)
    iconBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Click to choose icon", 1, 1, 1)
        GameTooltip:Show()
    end)
    iconBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    iconBtn:SetScript("OnClick", function(self)
        local picker = BuildIconPicker()
        for _, ib in ipairs(_iconBtns) do
            if ib._sel then ib._sel:SetShown(ib._path == _selIcon) end
        end
        picker:ClearAllPoints()
        picker:SetPoint("TOPLEFT", self, "TOPRIGHT", 4, 0)
        picker:Show(); picker:Raise()
    end)
    _iconBtn = iconBtn

    -- Title editbox — 20pt bold, same as the main note editor title
    local titleBg = BNB.CreateBackdropFrame("Frame", nil, f)
    BNB.SetBackdrop(titleBg, 0.06, 0.06, 0.09, 0.85, 0.35, 0.35, 0.38, 1)
    titleBg:SetPoint("TOPLEFT",  iconBtn, "TOPRIGHT",  6, 0)
    titleBg:SetPoint("TOPRIGHT", f,       "TOPRIGHT", -DLG_PAD, 0)
    titleBg:SetHeight(ICON_SZ)

    local titleEB = CreateFrame("EditBox", nil, titleBg)
    titleEB:SetPoint("TOPLEFT",     titleBg, "TOPLEFT",      6, -4)
    titleEB:SetPoint("BOTTOMRIGHT", titleBg, "BOTTOMRIGHT", -6,  4)
    titleEB:SetAutoFocus(false)
    titleEB:SetMaxLetters(128)
    titleEB:SetTextInsets(2, 2, 2, 2)
    titleEB:SetTextColor(1, 1, 1, 1)
    -- Font set in ApplyTitleFont() called from Open()

    titleEB:SetScript("OnEnterPressed", function() NND.Confirm() end)
    titleEB:SetScript("OnEscapePressed", function() NND.Close() end)
    titleEB:SetScript("OnTextChanged", function(self, userInput)
        if not userInput then return end
        local text = self._showingPlaceholder and "" or (self:GetText() or "")
        if _createBtn then _createBtn:SetEnabled(text ~= "") end
    end)

    BNB.AddPlaceholder(titleEB, "Note title...", 0.40, 0.40, 0.40)
    _titleEB = titleEB

    -- ── COLUMN ANCHORS ───────────────────────────────────────────────────────
    local contentY = topY - ICON_SZ - 10

    local colL = CreateFrame("Frame", nil, f)
    colL:SetSize(COL_L_W, 1)
    colL:SetPoint("TOPLEFT", f, "TOPLEFT", DLG_PAD, contentY)

    local colR = CreateFrame("Frame", nil, f)
    colR:SetSize(COL_R_W, 1)
    colR:SetPoint("TOPLEFT", f, "TOPLEFT", DLG_PAD + COL_L_W + COL_GAP, contentY)

    -- ── LEFT COLUMN: font cards ───────────────────────────────────────────────
    local fontHdr = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    fontHdr:SetPoint("TOPLEFT", colL, "TOPLEFT", 0, 0)
    fontHdr:SetWidth(COL_L_W); fontHdr:SetJustifyH("LEFT")
    fontHdr:SetText("Font")
    fontHdr:SetTextColor(0.8, 0.8, 0.8, 1)

    local leftY  = -18
    _fontBtns    = {}
    local fonts  = BNB.FONTS or {}
    local cardW  = math.floor((COL_L_W - CARD_GAP) / 2)

    for i, def in ipairs(fonts) do
        local col  = (i - 1) % 2
        local grow = math.floor((i - 1) / 2)
        local xOff = col * (cardW + CARD_GAP)
        local yOff = leftY - grow * (CARD_H + CARD_GAP)

        local btn = BNB.CreateBackdropFrame("Button", nil, f)
        BNB.SetBackdrop(btn, 0.06, 0.06, 0.08, 0.95, 0.28, 0.28, 0.30, 1)
        btn:SetSize(cardW, CARD_H)
        btn:SetPoint("TOPLEFT", colL, "TOPLEFT", xOff, yOff)
        btn:EnableMouse(true)

        local nameLbl = btn:CreateFontString(nil, "OVERLAY")
        nameLbl:SetPoint("TOPLEFT",  btn, "TOPLEFT",  4, -4)
        nameLbl:SetPoint("TOPRIGHT", btn, "TOPRIGHT", -4, -4)
        nameLbl:SetJustifyH("LEFT"); nameLbl:SetHeight(16)
        if def.bold and def.bold ~= "" then
            pcall(function() nameLbl:SetFont(def.bold, 11, "") end)
        else
            nameLbl:SetFontObject("GameFontNormal")
        end
        nameLbl:SetText(def.label)

        local prevLbl = btn:CreateFontString(nil, "OVERLAY")
        prevLbl:SetPoint("BOTTOMLEFT",  btn, "BOTTOMLEFT",  4, 4)
        prevLbl:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -4, 4)
        prevLbl:SetJustifyH("LEFT"); prevLbl:SetHeight(11)
        if def.regular and def.regular ~= "" then
            pcall(function() prevLbl:SetFont(def.regular, 9, "") end)
        else
            prevLbl:SetFontObject("GameFontNormalSmall")
        end
        prevLbl:SetTextColor(0.55, 0.55, 0.55)
        prevLbl:SetText(def.preview or "")

        local defId = def.id
        btn:SetScript("OnEnter", function(s)
            if defId ~= _selFont then
                s:SetBackdropColor(0.10, 0.12, 0.10, 0.95)
                s:SetBackdropBorderColor(0.35, 0.55, 0.35, 1)
            end
        end)
        btn:SetScript("OnLeave", RefreshFontHighlight)
        btn:SetScript("OnClick", function()
            _selFont = defId
            RefreshFontHighlight()
            ApplyTitleFont()
            -- Update size preview to use the newly selected font
            if _sizePreviewLbl then
                pcall(function()
                    for _, d in ipairs(BNB.FONTS or {}) do
                        if d.id == _selFont and d.bold and d.bold ~= "" then
                            _sizePreviewLbl:SetFont(d.bold, _selSize, "")
                            return
                        end
                    end
                    local boldPath = BNB.GetBoldFont and BNB.GetBoldFont()
                    if boldPath and boldPath ~= "" then
                        _sizePreviewLbl:SetFont(boldPath, _selSize, "")
                    end
                end)
            end
        end)
        _fontBtns[#_fontBtns + 1] = { btn = btn, id = def.id, nameLbl = nameLbl }
    end

    local fontGridRows = math.ceil(#fonts / 2)
    local leftColH = 18 + fontGridRows * (CARD_H + CARD_GAP) - CARD_GAP

    -- ── RIGHT COLUMN: title colour + font size ───────────────────────────────
    local rightY = 0

    local colorHdr = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    colorHdr:SetPoint("TOPLEFT", colR, "TOPLEFT", 0, rightY)
    colorHdr:SetWidth(COL_R_W); colorHdr:SetJustifyH("LEFT")
    colorHdr:SetText("Title colour")
    colorHdr:SetTextColor(0.8, 0.8, 0.8, 1)
    rightY = rightY - 18

    -- Colour swatches (manual build for ring highlight refs)
    _swatchBtns = {}
    do
        local COLS = 8
        local GAP  = 3
        local SZ   = math.floor((COL_R_W - (COLS - 1) * GAP) / COLS)
        local pal  = BNB.COLOR_PALETTE or {}
        for i, c in ipairs(pal) do
            local col = (i - 1) % COLS
            local row = math.floor((i - 1) / COLS)
            local sw  = CreateFrame("Button", nil, f)
            sw:SetSize(SZ, SZ)
            sw:SetPoint("TOPLEFT", colR, "TOPLEFT",
                col * (SZ + GAP),
                rightY - row * (SZ + GAP))

            local tx = sw:CreateTexture(nil, "ARTWORK")
            tx:SetAllPoints(); tx:SetColorTexture(c.r, c.g, c.b)

            local hi = sw:CreateTexture(nil, "HIGHLIGHT")
            hi:SetAllPoints(); hi:SetColorTexture(1, 1, 1, 0.35)

            local ring = sw:CreateTexture(nil, "OVERLAY")
            ring:SetPoint("TOPLEFT",     sw, "TOPLEFT",     -2,  2)
            ring:SetPoint("BOTTOMRIGHT", sw, "BOTTOMRIGHT",  2, -2)
            ring:SetColorTexture(1, 1, 1, 0.7); ring:Hide()
            sw._ring = ring

            local bdr = BNB.CreateBackdropFrame("Frame", nil, sw)
            bdr:SetAllPoints(); bdr:SetFrameLevel(sw:GetFrameLevel() - 1)
            BNB.SetBackdrop(bdr, 0, 0, 0, 0, 0.30, 0.30, 0.32, 0.9)
            bdr:EnableMouse(false)

            local cr, cg, cb, lbl = c.r, c.g, c.b, c.label
            sw._r = cr; sw._g = cg; sw._b = cb
            sw:SetScript("OnClick", function()
                _selColor = { r = cr, g = cg, b = cb }
                RefreshColorHighlight()
            end)
            sw:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_TOP")
                GameTooltip:AddLine(string.format("%s (R:%d G:%d B:%d)",
                    lbl,
                    math.floor(cr * 255 + 0.5),
                    math.floor(cg * 255 + 0.5),
                    math.floor(cb * 255 + 0.5)), cr, cg, cb)
                GameTooltip:Show()
            end)
            sw:SetScript("OnLeave", function() GameTooltip:Hide() end)
            _swatchBtns[#_swatchBtns + 1] = sw
        end
        local ROWS = math.ceil(#pal / COLS)
        rightY = rightY - ROWS * (SZ + GAP) - 10
    end

    -- Font size — header label above, slider below, filling full column width
    local sizeHdr = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    sizeHdr:SetPoint("TOPLEFT", colR, "TOPLEFT", 0, rightY)
    sizeHdr:SetWidth(COL_R_W); sizeHdr:SetJustifyH("LEFT")
    sizeHdr:SetText("Font size")
    sizeHdr:SetTextColor(0.8, 0.8, 0.8, 1)
    rightY = rightY - 18

    local defaultSize = (BigNoteBoxDB and BigNoteBoxDB.fontSize) or 12
    local szWidget
    if MinimalSliderWithSteppersMixin then
        local sl = CreateFrame("Slider", nil, f, "MinimalSliderWithSteppersTemplate")
        sl:SetPoint("TOPLEFT",  colR, "TOPLEFT",   0, rightY)
        sl:SetPoint("TOPRIGHT", colR, "TOPRIGHT", -36, rightY)
        sl:SetHeight(20)
        sl:Init(defaultSize, 8, 32, 24, {
            [MinimalSliderWithSteppersMixin.Label.Right] =
                CreateMinimalSliderFormatter(
                    MinimalSliderWithSteppersMixin.Label.Right,
                    function(v)
                        return WHITE_FONT_COLOR:WrapTextInColorCode(
                            tostring(math.floor(v)) .. "pt")
                    end),
        })
        sl:RegisterCallback(MinimalSliderWithSteppersMixin.Event.OnValueChanged,
            function(_, v)
                _selSize = math.floor(v)
                if _sizePreviewLbl then
                    pcall(function()
                        local boldPath = (_selFont and (function()
                            for _, d in ipairs(BNB.FONTS or {}) do
                                if d.id == _selFont then return d.bold end
                            end
                        end)()) or (BNB.GetBoldFont and BNB.GetBoldFont())
                        if boldPath and boldPath ~= "" then
                            _sizePreviewLbl:SetFont(boldPath, _selSize, "")
                        else
                            -- GameFontNormal is always valid; size override handles the rest
                            _sizePreviewLbl:SetFontObject(GameFontNormal)
                            _sizePreviewLbl:SetFont(GameFontNormal:GetFont(), _selSize, "")
                        end
                    end)
                end
            end)
        szWidget = sl
    else
        szWidget = BNB.CreateSlider(f, "", 8, 32, defaultSize, nil,
            function(v) _selSize = v end,
            function(v) return tostring(v) .. "pt" end)
        szWidget:SetPoint("TOPLEFT",  colR, "TOPLEFT",  0, rightY)
        szWidget:SetPoint("TOPRIGHT", colR, "TOPRIGHT", 0, rightY)
    end
    rightY = rightY - 28
    _sizeSlider = szWidget

    -- Font size preview label — live sample text at current size
    local sampleHdr = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    sampleHdr:SetPoint("TOPLEFT", colR, "TOPLEFT", 0, rightY)
    sampleHdr:SetWidth(COL_R_W); sampleHdr:SetJustifyH("LEFT")
    sampleHdr:SetText("Sample size")
    sampleHdr:SetTextColor(0.8, 0.8, 0.8, 1)
    rightY = rightY - 18

    local previewLbl = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    previewLbl:SetPoint("TOPLEFT",  colR, "TOPLEFT",  0, rightY)
    previewLbl:SetPoint("TOPRIGHT", colR, "TOPRIGHT", 0, rightY)
    previewLbl:SetJustifyH("CENTER")
    previewLbl:SetTextColor(0.65, 0.65, 0.65, 1)
    -- Set a valid font first so SetText never fires without one, then
    -- attempt to override with the BNB bold font at the correct size.
    pcall(function()
        local boldPath = BNB.GetBoldFont and BNB.GetBoldFont()
        if boldPath and boldPath ~= "" then
            previewLbl:SetFont(boldPath, defaultSize, "")
        end
    end)
    previewLbl:SetText("Azeroth awaits!")
    _sizePreviewLbl = previewLbl
    rightY = rightY - 28

    -- Rich note checkbox (full width, below both columns)
    local richCheck = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
    richCheck:SetSize(20, 20)
    richCheck:SetPoint("TOPLEFT", f, "TOPLEFT", DLG_PAD,
        -(chromeTopH or 36) - ICON_SZ - 10 - math.max(math.abs(leftColH or 0), math.abs(rightY)) - 4)
    local richLbl = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    richLbl:SetPoint("LEFT",  richCheck, "RIGHT",  4, 0)
    richLbl:SetPoint("RIGHT", f,         "RIGHT", -DLG_PAD, 0)
    richLbl:SetJustifyH("LEFT")
    richLbl:SetText("Rich note (supports headers, images, formatting)")
    richLbl:SetTextColor(0.8, 0.8, 0.8, 1)
    richCheck:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Rich note", 1, 1, 1)
        GameTooltip:AddLine(
            "Rich notes support {h1} headers, {img} images,\n{col} colours, {icon} icons and {link} links.\nUse the markup toolbar in the editor to insert tags.",
            0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    richCheck:SetScript("OnLeave", function() GameTooltip:Hide() end)
    richCheck:SetScript("OnClick", function(self)
        _selRich = self:GetChecked() == true
    end)
    -- Default from DB
    local richDefault = BigNoteBoxDB and BigNoteBoxDB.newNotesRichByDefault == true
    richCheck:SetChecked(richDefault)
    _selRich = richDefault
    _richCheck = richCheck

    -- Adjust dialog height to fit the extra checkbox row
    local RICH_ROW_H = 24
    local rightColH = math.abs(rightY) + RICH_ROW_H

    -- ── FOOTER ───────────────────────────────────────────────────────────────
    local totalContentH = math.max(leftColH, rightColH)
    local chromeTopH    = skinMode and (SK_NND_TITLE_H + 8) or 36
    local dlgH = chromeTopH + ICON_SZ + 10 + totalContentH + DLG_FOOT + 8
    f:SetHeight(dlgH)

    if skinMode then
        local footHost = CreateFrame("Frame", nil, f)
        footHost:SetHeight(1)
        footHost:SetPoint("BOTTOMLEFT",  f, "BOTTOMLEFT",  DLG_PAD,  DLG_FOOT)
        footHost:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -DLG_PAD, DLG_FOOT)
        local footDiv = BNB.CreateDivider(footHost, "HORIZONTAL", 0.28, 0.28, 0.30, 1)
        footDiv:SetPoint("TOPLEFT",  footHost, "TOPLEFT",  0, 0)
        footDiv:SetPoint("TOPRIGHT", footHost, "TOPRIGHT", 0, 0)
    else
        local footDiv = f:CreateTexture(nil, "ARTWORK")
        footDiv:SetHeight(1)
        footDiv:SetPoint("BOTTOMLEFT",  f, "BOTTOMLEFT",  DLG_PAD, DLG_FOOT)
        footDiv:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -DLG_PAD, DLG_FOOT)
        footDiv:SetColorTexture(0.28, 0.28, 0.30, 1)
    end

    local bW = math.floor(DLG_CW / 2) - 4
    local createBtn = BNB.CreateButton(nil, f, "Create", bW, 26)
    createBtn:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", DLG_PAD, 8)
    createBtn:SetScript("OnClick", function() NND.Confirm() end)
    createBtn:SetEnabled(false)   -- disabled until user types a title
    _createBtn = createBtn

    local cancelBtn = BNB.CreateButton(nil, f, "Cancel", bW, 26)
    cancelBtn:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", DLG_PAD + bW + 8, 8)
    cancelBtn:SetScript("OnClick", function() NND.Close() end)

    f:Hide()
    _frame = f
    return f
end

-- ---------------------------------------------------------------------------
-- PUBLIC API
-- ---------------------------------------------------------------------------
function NND.Open()
    local f = BuildDialog()

    local mf = BNB.mainFrame

    -- Seed selections
    _selIcon  = RandomNoteIcon()
    _selFont  = nil
    _selColor = nil
    _selSize  = (BigNoteBoxDB and BigNoteBoxDB.fontSize) or 12
    _selRich  = (BigNoteBoxDB and BigNoteBoxDB.newNotesRichByDefault) == true
    if _richCheck then _richCheck:SetChecked(_selRich) end

    -- Apply icon
    if _iconBtn then _iconBtn._tex:SetTexture(_selIcon) end

    -- Reset title field and disable Create
    if _titleEB then
        _titleEB:SetText("")
        BNB.AddPlaceholder(_titleEB, "Note title...", 0.40, 0.40, 0.40)
    end
    if _createBtn then _createBtn:SetEnabled(false) end

    -- Apply default title font (no font override selected yet)
    ApplyTitleFont()

    -- Reset size preview to default font + current size
    if _sizePreviewLbl then
        pcall(function()
            local boldPath = BNB.GetBoldFont and BNB.GetBoldFont()
            if boldPath and boldPath ~= "" then
                _sizePreviewLbl:SetFont(boldPath, _selSize, "")
            else
                _sizePreviewLbl:SetFont(GameFontNormalLarge:GetFont(), _selSize, "")
            end
        end)
    end

    RefreshFontHighlight()
    RefreshColorHighlight()

    -- Reset slider to global font size
    if _sizeSlider then
        if _sizeSlider.SetValue then
            _sizeSlider:SetValue(_selSize)
        end
    end

    -- Centre on main window. Dialog stays parented to UIParent so DIALOG strata
    -- is respected. Re-anchor on every Open() and after main window is dragged.
    f:ClearAllPoints()
    if mf and mf:IsShown() then
        f:SetPoint("CENTER", mf, "CENTER", 0, 20)
    else
        f:SetPoint("CENTER", UIParent, "CENTER", 0, 20)
    end

    -- Hook mainFrame OnDragStop once so dialog re-centres after a drag
    if mf and not mf._nndDragHooked then
        mf._nndDragHooked = true
        mf:HookScript("OnDragStop", function()
            if _frame and _frame:IsShown() then
                _frame:ClearAllPoints()
                _frame:SetPoint("CENTER", mf, "CENTER", 0, 20)
            end
        end)
    end

    ShowMainOverlay(true)
    f:Show()
    f:Raise()

    C_Timer.After(0.05, function()
        if _titleEB and f:IsShown() then _titleEB:SetFocus() end
    end)
end

function NND.Close()
    if _frame then _frame:Hide() end
    ShowMainOverlay(false)
    if _iconPickerF then _iconPickerF:Hide() end
end

function NND.Confirm()
    if not _frame or not _frame:IsShown() then return end
    if _createBtn and not _createBtn:IsEnabled() then return end

    local rawTitle = (_titleEB and not _titleEB._showingPlaceholder)
                     and (_titleEB:GetText() or "") or ""
    if rawTitle == "" then return end

    NND.Close()

    local id = BNB.CreateNote(rawTitle)
    if not id then return end
    BNB._justCreatedNoteID = id    -- tells LoadNoteInEditor to open in Editor mode

    local updates = { icon = _selIcon }
    if _selFont  then updates.fontOverride = _selFont  end
    if _selColor then updates.titleColor   = _selColor end
    local defaultSize = (BigNoteBoxDB and BigNoteBoxDB.fontSize) or 12
    if _selSize ~= defaultSize then updates.fontSize = _selSize end
    if _selRich then updates.richMode = true end
    BNB.UpdateNote(id, updates)

    if not BNB.mainFrame then BNB.CreateMainWindow() end
    if not BNB.mainFrame:IsShown() then BNB.mainFrame:Show() end
    if BNB.RefreshNoteList then BNB.RefreshNoteList() end
    if BNB.SelectNote      then BNB.SelectNote(id)    end
    C_Timer.After(0.05, function()
        if BNB.OpenNoteConfig then BNB.OpenNoteConfig(id) end
        C_Timer.After(0.05, function()
            if BNB._editorBody then BNB._editorBody:SetFocus() end
        end)
    end)
end

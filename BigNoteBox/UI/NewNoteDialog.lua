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
local L = BNB.L

BNB.NewNoteDialog = BNB.NewNoteDialog or {}
local NND = BNB.NewNoteDialog

-- ---------------------------------------------------------------------------
-- LAYOUT CONSTANTS
-- ---------------------------------------------------------------------------
local DLG_W    = 420   -- 360 until ALL-267: wider font cards, room for the character dropdown
local DLG_PAD  = 12
local DLG_FOOT = 42
local DLG_CW   = DLG_W - DLG_PAD * 2   -- 396

local COL_GAP  = 8
local COL_L_W  = 196
local COL_R_W  = DLG_CW - COL_L_W - COL_GAP

local ICON_SZ  = 40
local SCOPE_W  = 130   -- character dropdown right of the title (ALL-267)
local CARD_H   = 38
local CARD_GAP = 4

-- ---------------------------------------------------------------------------
-- MODULE STATE
-- ---------------------------------------------------------------------------
local _frame       = nil
local _overlay     = nil   -- black dimmer over mainFrame
local PICKER_KEY   = "newNote"   -- BNB.IconPicker key + owner (ALL-238)

local _selIcon  = nil
local _selFont  = nil
local _selColor = nil
-- Icon frame / LSM edge border picked with a right-click on the icon
-- (ALL-350); written to the note on Create, as Note Settings would
local _selFrame, _selBorder = nil, nil
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
local _scopeDD        = nil   -- which character the note belongs to (ALL-267)
local _scopeEntries   = {}    -- filled on every Open (knownChars can change)
local _wowCheck        = nil
local _refreshLSM      = nil   -- LSM font dropdown closed-state refresh (ALL-41)

-- Font preview in the picked font at the picked size. One resolver for every
-- pick (card, LSM, WoW Default, none), so "Use WoW's default font" shows too:
-- it only ever updated the preview from the card loops, never from its
-- checkbox (ALL-216).
local function UpdateSizePreview()
    if not _sizePreviewLbl then return end
    pcall(function()
        local def  = BNB.ResolveFontDef and BNB.ResolveFontDef(_selFont)
        local path = def and def.bold
        if not path or path == "" then path = BNB.GetBoldFont and BNB.GetBoldFont() end
        local size = _selSize or (BigNoteBoxDB and BigNoteBoxDB.fontSize) or BNB.DEFAULTS.fontSize
        if path and path ~= "" then
            _sizePreviewLbl:SetFont(path, BNB.FontPx(path, size), "")
        else
            _sizePreviewLbl:SetFontObject("BNBFontNormal")
        end
    end)
end

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
-- ICON PICKER (BNB.IconPicker beside the dialog, ALL-238)
-- ---------------------------------------------------------------------------
local function ShowSelIcon()
    if _iconBtn then
        _iconBtn._tex:SetTexture(_selIcon or "Interface\\Icons\\INV_Misc_Note_06")
    end
end

-- The picked icon frame drawn on the icon button (ALL-350)
local function ShowSelFrame()
    if _iconBtn and BNB.ApplyIconFrame then
        BNB.ApplyIconFrame(_iconBtn._tex, { iconFrame = _selFrame }, ICON_SZ - 6)
    end
end

local function FramePickHandlers()
    return {
        getFrame  = function() return _selFrame or "none" end,
        setFrame  = function(k) _selFrame = (k ~= "none") and k or nil; ShowSelFrame() end,
        getBorder = function() return _selBorder or "None" end,
        setBorder = function(k) _selBorder = (k ~= "None" and k ~= "") and k or nil end,
        getIcon   = function() return _selIcon end,
        -- Over the main window's FULLSCREEN_DIALOG dimmer, as the icon picker
        strata    = "FULLSCREEN_DIALOG",
    }
end

local function IconPickHandlers()
    return {
        owner  = PICKER_KEY,
        -- Over the main window's FULLSCREEN_DIALOG dimmer (ShowMainOverlay)
        strata = "FULLSCREEN_DIALOG",
        get    = function() return _selIcon end,
        set    = function(icon) _selIcon = icon; ShowSelIcon() end,
    }
end

-- ---------------------------------------------------------------------------
-- CHARACTER DROPDOWN (ALL-267)
-- Global, this character, then every other known character by name in its
-- class colour (realm added when two share a name). Filled in place: the
-- dropdown keeps a reference to this table and builds its menu on open.
-- ---------------------------------------------------------------------------
local function FillScopeEntries()
    wipe(_scopeEntries)
    local cur = BNB.currentChar
    _scopeEntries[#_scopeEntries + 1] = { value = "global", label = L["SCOPE_GLOBAL"] }
    if cur then
        _scopeEntries[#_scopeEntries + 1] = { value = "char:" .. cur, label = L["SCOPE_THIS_CHAR"] }
    end
    local others, names = {}, {}
    for key, rec in pairs(BigNoteBoxDB and BigNoteBoxDB.knownChars or {}) do
        if key ~= cur then
            local name = rec.name or key
            others[#others + 1] = { key = key, name = name, realm = rec.realm, class = rec.class }
            names[name] = (names[name] or 0) + 1
        end
    end
    table.sort(others, function(a, b) return a.name < b.name end)
    for _, c in ipairs(others) do
        local clr = RAID_CLASS_COLORS and c.class and RAID_CLASS_COLORS[c.class]
        local label = c.name
        if clr then
            label = string.format("|cff%02x%02x%02x%s|r", clr.r * 255, clr.g * 255, clr.b * 255, c.name)
        end
        if names[c.name] > 1 and c.realm and c.realm ~= "" then
            label = label .. " |cff888888" .. c.realm .. "|r"
        end
        _scopeEntries[#_scopeEntries + 1] = { value = "char:" .. c.key, label = label }
    end
end

-- ---------------------------------------------------------------------------
-- HIGHLIGHT HELPERS
-- ---------------------------------------------------------------------------
local function RefreshFontHighlight()
    -- No override (WoW Default unticked, nothing else picked) always shows Noto Serif
    -- highlighted, regardless of what was selected before WoW Default was ticked.
    -- Under another font set (ALL-14) that is the set's default card instead.
    local hlFont = _selFont or BNB.GetFontSetDefault()
    if _refreshLSM then _refreshLSM() end
    for _, e in ipairs(_fontBtns) do
        local sel = (e.id == hlFont)
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
            if sel then BNB.SetHeaderColor(e.nameLbl) else BNB.SetTextWhite(e.nameLbl, 0.85) end
        end
    end
end

local function RefreshColorHighlight()
    local any = false
    for _, sw in ipairs(_swatchBtns) do
        local match = _selColor and
            sw._r == _selColor.r and sw._g == _selColor.g and sw._b == _selColor.b
        if match then any = true end
        if sw._ring then sw._ring:SetShown(match == true) end
    end
    -- A colour from the picker tile rings the tile
    local tile = _swatchBtns.tile
    if tile and tile._ring then tile._ring:SetShown(_selColor ~= nil and not any) end
    -- The title is typed in the picked colour (ALL-349)
    if _titleEB and _titleEB.SetRealColor then _titleEB:SetRealColor(_selColor) end
end

-- Apply selected font bold at 20pt to title editbox (mirrors NoteEditor title field)
local function ApplyTitleFont()
    if not _titleEB then return end
    if _selFont then
        local fonts = BNB.FONTS or {}
        for _, def in ipairs(fonts) do
            if def.id == _selFont and def.bold and def.bold ~= "" then
                pcall(function() _titleEB:SetFont(def.bold, BNB.FontPx(def.bold, 20), "") end)
                return
            end
        end
    end
    -- Default: use BNB bold font or WoW's large font
    local boldPath = BNB.GetBoldFont and BNB.GetBoldFont()
    if boldPath then
        pcall(function() _titleEB:SetFont(boldPath, BNB.FontPx(boldPath, 20), "") end)
    else
        local font, _, flags = GameFontNormalHuge:GetFont()
        if font then pcall(function() _titleEB:SetFont(font, 20, flags or "") end)
        else _titleEB:SetFontObject("BNBFontNormalLarge") end
    end
end

-- ---------------------------------------------------------------------------
-- BUILD DIALOG (once; re-parented to mainFrame on first Open)
-- ---------------------------------------------------------------------------
local function BuildDialog()
    if _frame then return _frame end

    -- Chrome for both modes (CMP-02 S3). Not movable: it stays centred on the
    -- main window (NND.Open re-anchors it after a main window drag)
    local f, createBtn, cancelBtn = BNB.CreateToolWindow({
        name = "BNBNewNoteDialogFrame", w = DLG_W, h = 10,   -- height set below
        title = L["NND_TITLE"], toplevel = true, escClose = true, noDrag = true,
        pad = DLG_PAD, cw = DLG_CW, footH = DLG_FOOT,
        btn1 = L["NND_CREATE_BTN"], btn2 = L["CANCEL"],
        onClose = function() NND.Close() end,
    })
    local skinMode = f._isSkin

    f:HookScript("OnHide", function()
        ShowMainOverlay(false)
        BNB.IconPicker.Close(PICKER_KEY)
        if BNB.IconFramePicker and BNB.IconFramePicker.IsOpenFor(PICKER_KEY) then
            BNB.IconFramePicker.Close()
        end
    end)

    -- ── TOP ROW: icon + title editbox ────────────────────────────────────────
    local topY = skinMode and -(BNB.TOOL_SKIN_TITLE_H + 8) or -36

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
        GameTooltip:AddLine(L["NND_ICON_TIP"], 1, 1, 1)
        GameTooltip:AddLine(L["NND_ICON_FRAME_TIP"], 0.8, 0.8, 0.8)
        GameTooltip:Show()
    end)
    iconBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    -- Toggles the picker, top aligned beside the dialog
    -- Right-click: the icon frame picker (ALL-350)
    iconBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    iconBtn:SetScript("OnClick", function(_, btn)
        if btn == "RightButton" then
            if BNB.IconFramePicker then
                BNB.IconPicker.Close(PICKER_KEY)
                BNB.IconFramePicker.Open(PICKER_KEY, f, FramePickHandlers())
            end
            return
        end
        if BNB.IconFramePicker and BNB.IconFramePicker.IsOpenFor(PICKER_KEY) then
            BNB.IconFramePicker.Close()
        end
        BNB.IconPicker.Open(PICKER_KEY, f, IconPickHandlers())
    end)
    _iconBtn = iconBtn

    -- Character dropdown at the right end of the title row (ALL-267)
    FillScopeEntries()
    local scopeDD = BNB.CreateValueDropdown(f, _scopeEntries, "global", nil, SCOPE_W, 26)
    scopeDD:SetPoint("TOPRIGHT", f, "TOPRIGHT", -DLG_PAD, topY - (ICON_SZ - 26) / 2)
    local scopeTipOwner = scopeDD._dd or scopeDD
    scopeTipOwner:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(L["NND_SCOPE_TIP"], 1, 1, 1)
        GameTooltip:AddLine(L["NND_SCOPE_TIP_SUB"], 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    scopeTipOwner:HookScript("OnLeave", function() GameTooltip:Hide() end)
    _scopeDD = scopeDD

    -- Title editbox — 20pt bold, same as the main note editor title
    local titleBg = BNB.CreateBackdropFrame("Frame", nil, f)
    BNB.SetBackdrop(titleBg, 0.06, 0.06, 0.09, 0.85, 0.35, 0.35, 0.38, 1)
    titleBg:SetPoint("TOPLEFT",  iconBtn, "TOPRIGHT",  6, 0)
    titleBg:SetPoint("TOPRIGHT", scopeDD, "TOPLEFT",  -6, (ICON_SZ - 26) / 2)
    titleBg:SetHeight(ICON_SZ)

    local titleEB = CreateFrame("EditBox", nil, titleBg)
    titleEB:SetPoint("TOPLEFT",     titleBg, "TOPLEFT",      6, -4)
    titleEB:SetPoint("BOTTOMRIGHT", titleBg, "BOTTOMRIGHT", -6,  4)
    titleEB:SetAutoFocus(false)
    titleEB:SetMaxLetters(128)
    titleEB:SetTextInsets(2, 2, 2, 2)
    BNB.SetTextWhite(titleEB)
    -- Font set in ApplyTitleFont() called from Open()

    titleEB:SetScript("OnEnterPressed", function() NND.Confirm() end)
    titleEB:SetScript("OnEscapePressed", function() NND.Close() end)
    titleEB:SetScript("OnTextChanged", function(self, userInput)
        if not userInput then return end
        local text = self._showingPlaceholder and "" or (self:GetText() or "")
        if _createBtn then _createBtn:SetEnabled(text ~= "") end
    end)

    BNB.AddPlaceholder(titleEB, L["NND_TITLE_PLACEHOLDER"], 0.40, 0.40, 0.40)
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
    local fontHdr = f:CreateFontString(nil, "OVERLAY", "BNBFontNormal")
    fontHdr:SetPoint("TOPLEFT", colL, "TOPLEFT", 0, 0)
    fontHdr:SetWidth(COL_L_W); fontHdr:SetJustifyH("LEFT")
    fontHdr:SetText(L["NND_FONT_HDR"])
    fontHdr:SetTextColor(0.8, 0.8, 0.8, 1)

    local leftY  = -18
    _fontBtns    = {}
    -- WoW Default is offered via its own checkbox below the grid, not as a card,
    -- and LSM fonts in a dropdown below that (ALL-41). Cards are the active
    -- language's font set (ALL-14).
    local fonts = BNB.GetPickerFonts()
    local cardW  = math.floor((COL_L_W - CARD_GAP) / 2)

    -- A card click and an LSM dropdown pick do the same thing.
    local function SelectFont(id)
        _selFont = id
        if _wowCheck then _wowCheck:SetChecked(false) end
        RefreshFontHighlight()
        ApplyTitleFont()
        UpdateSizePreview()
    end

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
        BNB.SetFontSafe(nameLbl, def.bold, 11, "BNBFontNormal")
        nameLbl:SetText(def.label)

        local prevLbl = btn:CreateFontString(nil, "OVERLAY")
        prevLbl:SetPoint("BOTTOMLEFT",  btn, "BOTTOMLEFT",  4, 4)
        prevLbl:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -4, 4)
        prevLbl:SetJustifyH("LEFT"); prevLbl:SetHeight(11)
        BNB.SetFontSafe(prevLbl, def.regular, 9, "BNBFontNormalSmall")
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
        btn:SetScript("OnClick", function() SelectFont(defId) end)
        _fontBtns[#_fontBtns + 1] = { btn = btn, id = def.id, nameLbl = nameLbl }
    end

    -- The grid always reserves its 4 rows; free rows carry the font pack hint.
    local usedRows     = math.ceil(#fonts / 2)
    local fontGridRows = math.max(BNB.FONT_GRID_ROWS, usedRows)
    BNB.AddFontPackHint(f, colL, 0, leftY - usedRows * (CARD_H + CARD_GAP),
        COL_L_W, (fontGridRows - usedRows) * (CARD_H + CARD_GAP) - CARD_GAP)
    local WOW_CHECK_H  = 22
    local leftColH = 18 + fontGridRows * (CARD_H + CARD_GAP) - CARD_GAP + WOW_CHECK_H

    -- WoW Default checkbox, below the grid instead of a 9th card. Latin set only;
    -- its row is kept either way so the dialog does not change size.
    local wowCheck = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
    BNB.LabelHit(wowCheck)   -- the tooltip and click reach over its label too
    wowCheck:SetShown(BNB.ShowWoWFontCheckbox())
    wowCheck:SetSize(18, 18)
    wowCheck:SetPoint("TOPLEFT", colL, "TOPLEFT", 0,
        leftY - fontGridRows * (CARD_H + CARD_GAP) + CARD_GAP - 2)
    local wowLbl = f:CreateFontString(nil, "OVERLAY", "BNBFontNormalSmall")
    wowLbl:SetPoint("LEFT",  wowCheck, "RIGHT", 4, 0)
    wowLbl:SetPoint("RIGHT", colL,     "RIGHT", 0, 0)
    wowLbl:SetJustifyH("LEFT")
    wowLbl:SetText(L["FONT_USE_WOW_DEFAULT"])
    wowLbl:SetTextColor(0.8, 0.8, 0.8, 1)
    if not BNB.ShowWoWFontCheckbox() then wowLbl:Hide() end
    wowCheck:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(L["FONT_USE_WOW_DEFAULT_TIP"], 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    wowCheck:SetScript("OnLeave", function() GameTooltip:Hide() end)
    wowCheck:SetScript("OnClick", function(self)
        if self:GetChecked() then
            _selFont = "wow"
            RefreshFontHighlight()
        else
            _selFont = nil
            RefreshFontHighlight()
        end
        ApplyTitleFont()
        UpdateSizePreview()
    end)
    wowCheck:SetChecked(_selFont == "wow")
    _wowCheck = wowCheck

    -- LSM font dropdown (ALL-41), below the checkbox; only built when lsmFonts is on
    -- and LSM has fonts. leftColH grows by its height so the columns stay in step.
    if BNB._BuildLSMFontDropdown then
        local y, refresh = BNB._BuildLSMFontDropdown(colL, -leftColH - 4,
            function()
                local def = _selFont and BNB.GetFontDef(_selFont)
                return (def and def._isLSM and _selFont == def.id) and _selFont or nil
            end,
            SelectFont,
            COL_L_W)
        if refresh then
            leftColH   = -y
            _refreshLSM = refresh
        end
    end

    -- ── RIGHT COLUMN: title colour + font size ───────────────────────────────
    local rightY = 0

    local colorHdr = f:CreateFontString(nil, "OVERLAY", "BNBFontNormal")
    colorHdr:SetPoint("TOPLEFT", colR, "TOPLEFT", 0, rightY)
    colorHdr:SetWidth(COL_R_W); colorHdr:SetJustifyH("LEFT")
    colorHdr:SetText(L["NND_TITLE_COLOR_HDR"])
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

            -- The same selected mark as every colour grid (ALL-330), not a fill
            BNB.AddColorSelRing(sw)
            sw._ring = sw._selRing

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
        -- The colour picker tile in the last slot, as every colour grid (Dukul 2026-10-06)
        local n = #pal
        local tile = BNB.CreateColorPickerTile(f, SZ, function()
            if _selColor then return _selColor.r, _selColor.g, _selColor.b end
        end, function(r, g, b, cancelled)
            if cancelled and not _selColor then return end
            _selColor = { r = r, g = g, b = b }
            RefreshColorHighlight()
        end)
        tile:SetPoint("TOPLEFT", colR, "TOPLEFT",
            (n % COLS) * (SZ + GAP), rightY - math.floor(n / COLS) * (SZ + GAP))
        BNB.AddColorSelRing(tile)
        tile._ring = tile._selRing
        _swatchBtns.tile = tile
        local ROWS = math.ceil((#pal + 1) / COLS)
        rightY = rightY - ROWS * (SZ + GAP) - 10
    end

    -- Font size — header label above, slider below, filling full column width
    local sizeHdr = f:CreateFontString(nil, "OVERLAY", "BNBFontNormal")
    sizeHdr:SetPoint("TOPLEFT", colR, "TOPLEFT", 0, rightY)
    sizeHdr:SetWidth(COL_R_W); sizeHdr:SetJustifyH("LEFT")
    sizeHdr:SetText(L["NND_FONT_SIZE_HDR"])
    sizeHdr:SetTextColor(0.8, 0.8, 0.8, 1)
    rightY = rightY - 18

    local defaultSize = (BigNoteBoxDB and BigNoteBoxDB.fontSize) or BNB.DEFAULTS.fontSize
    -- Stacked slider with Reset (ALL-121); the header above is its label
    local szWidget = BNB.CreateStackedSlider(f, COL_R_W, {
        label = "", min = 8, max = 32, value = defaultSize, default = defaultSize,
        fmt = function(v) return string.format(L["NND_PT_SUFFIX_FMT"], v) end,
        onChange = function(v)
            _selSize = v
            UpdateSizePreview()
        end,
    })
    szWidget:SetPoint("TOPLEFT", colR, "TOPLEFT", 0, rightY)
    rightY = rightY - (BNB.STACKED_SLIDER_H + 4)
    _sizeSlider = szWidget

    -- Font size preview label — live sample text at current size
    local sampleHdr = f:CreateFontString(nil, "OVERLAY", "BNBFontNormal")
    sampleHdr:SetPoint("TOPLEFT", colR, "TOPLEFT", 0, rightY)
    sampleHdr:SetWidth(COL_R_W); sampleHdr:SetJustifyH("LEFT")
    sampleHdr:SetText(L["NND_SAMPLE_SIZE_HDR"])
    sampleHdr:SetTextColor(0.8, 0.8, 0.8, 1)
    rightY = rightY - 18

    local previewLbl = f:CreateFontString(nil, "OVERLAY", "BNBFontNormal")
    previewLbl:SetPoint("TOPLEFT",  colR, "TOPLEFT",  0, rightY)
    previewLbl:SetPoint("TOPRIGHT", colR, "TOPRIGHT", 0, rightY)
    previewLbl:SetJustifyH("CENTER")
    previewLbl:SetTextColor(0.65, 0.65, 0.65, 1)
    -- Set a valid font first so SetText never fires without one, then
    -- attempt to override with the BNB bold font at the correct size.
    pcall(function()
        local boldPath = BNB.GetBoldFont and BNB.GetBoldFont()
        if boldPath and boldPath ~= "" then
            previewLbl:SetFont(boldPath, BNB.FontPx(boldPath, defaultSize), "")
        end
    end)
    previewLbl:SetText(L["NND_PREVIEW_SAMPLE"])
    _sizePreviewLbl = previewLbl
    rightY = rightY - 28

    -- Rich note checkbox (full width, below both columns)
    -- Both columns must agree on where "below both columns" is -- leftColH is a plain
    -- height, rightY is a running y-cursor, so take the taller of the two ONCE and use
    -- that same value both to place the checkbox and to size the dialog below it
    -- (ALL-29 fix: the two used to disagree, so the checkbox overlapped the footer).
    local colMaxH = math.max(math.abs(leftColH or 0), math.abs(rightY))
    local chromeTopH = skinMode and (BNB.TOOL_SKIN_TITLE_H + 8) or 36
    local richCheck = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
    BNB.LabelHit(richCheck)   -- the tooltip and click reach over its label too
    richCheck:SetSize(20, 20)
    richCheck:SetPoint("TOPLEFT", f, "TOPLEFT", DLG_PAD,
        -chromeTopH - ICON_SZ - 10 - colMaxH - 4)
    local richLbl = f:CreateFontString(nil, "OVERLAY", "BNBFontNormalSmall")
    richLbl:SetPoint("LEFT",  richCheck, "RIGHT",  4, 0)
    richLbl:SetPoint("RIGHT", f,         "RIGHT", -DLG_PAD, 0)
    richLbl:SetJustifyH("LEFT")
    richLbl:SetText(L["NND_RICH_CHECK_LBL"])
    richLbl:SetTextColor(0.8, 0.8, 0.8, 1)
    richCheck:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(L["NND_RICH_TIP"], 1, 1, 1)
        GameTooltip:AddLine(
            L["NND_RICH_TIP_SUB"],
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
    richCheck._lbl = richLbl

    -- Adjust dialog height to fit the extra checkbox row (+8px cushion, Dukul 2026-09-23:
    -- "the window needs to be made a tiny bit taller (20px or so)" -- the real fix is
    -- colMaxH above; this cushion covers font-metric rounding on top of that).
    local RICH_ROW_H = 24 + 8

    -- ── FOOTER ───────────────────────────────────────────────────────────────
    local totalContentH = colMaxH + RICH_ROW_H
    local dlgH = chromeTopH + ICON_SZ + 10 + totalContentH + DLG_FOOT + 8
    f:SetHeight(dlgH)

    createBtn:SetScript("OnClick", function() NND.Confirm() end)
    createBtn:SetEnabled(false)   -- disabled until user types a title
    _createBtn = createBtn
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
    _selFrame, _selBorder = nil, nil
    _selSize  = (BigNoteBoxDB and BigNoteBoxDB.fontSize) or BNB.DEFAULTS.fontSize
    _selRich  = (BigNoteBoxDB and BigNoteBoxDB.newNotesRichByDefault) == true
    if _richCheck then _richCheck:SetChecked(_selRich) end
    -- Rich Notes off (ALL-343): no rich choice, every new note is plain
    if _richCheck then _richCheck:SetShown(BNB.RichEnabled()); _richCheck._lbl:SetShown(BNB.RichEnabled()) end
    if not BNB.RichEnabled() then _selRich = false end
    if _wowCheck  then _wowCheck:SetChecked(false) end
    -- Character: starts on "New notes belong to" (Settings > Notes, ALL-267)
    if _scopeDD then
        FillScopeEntries()
        _scopeDD:SetSelected(BNB.NewNoteScope())
    end

    -- Apply icon
    ShowSelIcon()
    ShowSelFrame()

    -- Reset title field and disable Create
    if _titleEB then
        -- SetRealText, never AddPlaceholder again on a live box (it
        -- SetScripts the focus handlers)
        _titleEB:SetRealText("")
        _titleEB:SetRealColor(nil)
    end
    if _createBtn then _createBtn:SetEnabled(false) end

    -- Apply default title font (no font override selected yet)
    ApplyTitleFont()

    -- Reset size preview to default font + current size
    UpdateSizePreview()

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
    BNB.IconPicker.Close(PICKER_KEY)
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
    if _selFrame  then updates.iconFrame      = _selFrame  end   -- ALL-350
    if _selBorder then updates.borderOverride = _selBorder end
    local defaultSize = (BigNoteBoxDB and BigNoteBoxDB.fontSize) or BNB.DEFAULTS.fontSize
    if _selSize ~= defaultSize then updates.fontSize = _selSize end
    if _selRich then updates.richMode = true end
    local scope = _scopeDD and _scopeDD:GetSelected()
    if scope then updates.scope = scope end   -- ALL-267
    BNB.UpdateNote(id, updates)

    if not BNB.mainFrame then BNB.CreateMainWindow() end
    if not BNB.mainFrame:IsShown() then BNB.mainFrame:Show() end
    -- Another character's note is not in the selected tab: show All
    if BNB.RevealNoteInList then BNB.RevealNoteInList(id) end
    if BNB.SelectNote      then BNB.SelectNote(id)    end
    C_Timer.After(0.05, function()
        if BNB.OpenConfigOnNew() and BNB.OpenNoteConfig then BNB.OpenNoteConfig(id) end
        C_Timer.After(0.05, function()
            if BNB._editorBody then BNB._editorBody:SetFocus() end
        end)
    end)
end

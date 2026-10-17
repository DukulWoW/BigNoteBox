-- BigNoteBox UI/NewNoteDialog.lua
-- "New Note" creation dialog.
-- Opens when BigNoteBoxDB.newNoteBehaviour == "prompt" (or nil, the default).
-- Parented to BNB.mainFrame on first open so it moves with it and sits centred
-- on it. The main window is dimmed with a black overlay while the dialog is open.
-- ESC / Cancel closes without creating. Create is disabled until a title is typed.
-- Template cards under the title (ALL-68): Blank, Boss, Weekly, Journal, More;
-- More opens a second page in the dialog (f:AddPage "more") with the rest:
-- the player's own templates on top, a line, then the built-ins (S2; the
-- rows are refilled on every Open).
-- Templates themselves: Features/NoteTemplates.lua.
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

-- Template cards under the title row (ALL-68): Blank, three templates, More.
-- Art is 64x64 (Assets/Templates/tmp-<art>.tga, Dukul's): normal mode draws
-- its -hover glow behind the card (white on hover, BNB green while picked);
-- skin mode tints the white tmp-skin-<art> card (skin text colour, accent
-- while picked) and draws the one tmp-skin-hover behind it on hover
-- (Dukul, 2026-10-17).
local TPL_N      = 5
local TPL_GAP    = 4
local TPL_CARD_W = math.floor((DLG_CW - TPL_GAP * (TPL_N - 1)) / TPL_N)   -- 76
local TPL_ART    = 64
local TPL_LBL_H  = 14
local TPL_CARD_H = TPL_ART + 2 + TPL_LBL_H
local TPL_LINE_H = 14
local TPL_BLOCK_H = TPL_CARD_H + 4 + TPL_LINE_H + 8
local TPL_ART_PATH = "Interface\\AddOns\\BigNoteBox\\Assets\\Templates\\tmp-"
local TPL_GREEN  = { 0.40, 0.85, 0.40 }   -- BNB green (NoteList COL_SEL_BG)
local TPL_ROW_H  = 36   -- More page rows

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

-- Templates (ALL-68): the picked one (nil = Blank), its cards, the line
-- under them, the More page rows, and the title a template last filled in
-- (replaced by the next pick, left alone once the player typed their own)
local _selTpl    = nil
local _tplCards  = {}
local _tplLine   = nil
local _tplRows   = {}   -- the rows in use, rebuilt on every Open (the player's templates change)
local _tplPool   = {}   -- every row ever made, reused
local _tplMore   = nil  -- the More page's scroll frame, content and divider
local _tplTitle  = nil
local _tplSkin   = false

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
        BNB.PaintSelectCard(e.btn, e.id == hlFont and "sel" or nil, e.nameLbl)
    end
end
BNB.RegisterMessage("NewNoteDialog.FontCards", "SkinChanged", function() RefreshFontHighlight() end)

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
-- TEMPLATES (ALL-68)
-- ---------------------------------------------------------------------------
local function IsQuick(key)
    for _, k in ipairs(BNB.Templates.QUICK) do if k == key then return true end end
    return false
end

-- Skin hover hue (Dukul, 2026-10-17: "based on the lightest part of the
-- skin"): the border colour, the lightest of a preset's own colours, at the
-- brightest shade of its hue. A border with no colour (OLED flat) = the text grey.
local function SkinHoverOf(p)
    local r, g, b = BNB.SkinBorderOf(p)
    local mx = math.max(r, g, b)
    if mx <= 0 then return BNB.SkinTextOf(p) end
    return r / mx, g / mx, b / mx
end

-- Card states: picked = Blank with nothing picked, More with a More page
-- template, or the card's own template
local function PaintTplCards()
    local skin = _tplSkin   -- the art was picked for the mode the dialog was built in
    local p = skin and BNB.GetSkinPreset()
    local hr, hg, hb
    if skin then hr, hg, hb = SkinHoverOf(p) end
    for _, c in ipairs(_tplCards) do
        local picked = (c.key == "blank" and _selTpl == nil)
            or (c.key == "more" and _selTpl ~= nil and not IsQuick(_selTpl))
            or (c.key == _selTpl)
        if skin then
            if picked then c.art:SetVertexColor(BNB.SkinAccentOf(p))
            else c.art:SetVertexColor(BNB.SkinTextOf(p)) end
            c.glow:SetVertexColor(hr, hg, hb)
            c.glow:SetShown(c._hover == true)
        else
            c.glow:SetShown(picked or c._hover == true)
            if picked then c.glow:SetVertexColor(TPL_GREEN[1], TPL_GREEN[2], TPL_GREEN[3])
            else c.glow:SetVertexColor(1, 1, 1) end
        end
        if picked then BNB.SetHeaderColor(c.lbl) else BNB.SetTextWhite(c.lbl, 0.85) end
    end
    for _, r in ipairs(_tplRows) do
        BNB.PaintSelectCard(r, r.key == _selTpl and "sel" or (r._hover and "hover") or nil, r.nameLbl)
    end
    if _tplLine then
        local tpl = BNB.Templates.Get(_selTpl)
        _tplLine:SetText(string.format(L["NND_TPL_LINE_FMT"],
            BNB.Templates.Name(tpl), BNB.Templates.Desc(tpl)))
    end
end
BNB.RegisterMessage("NewNoteDialog.TplCards", "SkinChanged", function() PaintTplCards() end)

local function CurrentTitle()
    if not _titleEB or _titleEB._showingPlaceholder then return "" end
    return _titleEB:GetText() or ""
end

-- A pick fills the dialog (Dukul, 2026-10-17): icon, title colour, Rich, and
-- a suggested title while the box is empty or still holds the last
-- template's. Everything stays editable; Blank puts the defaults back.
local function PickTemplate(key)
    local tpl = BNB.Templates.Get(key)
    _selTpl = tpl and tpl.key or nil
    local title = CurrentTitle()
    local ownTitle = title ~= "" and title ~= _tplTitle
    if tpl then
        -- A player's template saved without its look has no icon
        _selIcon  = tpl.icon or RandomNoteIcon()
        _selColor = tpl.color and { r = tpl.color.r, g = tpl.color.g, b = tpl.color.b } or nil
        _selRich  = BNB.Templates.Rich(tpl)
        if not ownTitle then
            _tplTitle = BNB.Templates.Title(tpl)
            _titleEB:SetRealText(_tplTitle)
        end
    else
        _selIcon  = RandomNoteIcon()
        _selColor = nil
        _selRich  = BNB.RichEnabled() and (BigNoteBoxDB and BigNoteBoxDB.newNotesRichByDefault) == true
        if not ownTitle then
            _tplTitle = nil
            _titleEB:SetRealText("")
        end
    end
    if _richCheck then _richCheck:SetChecked(_selRich) end
    if _createBtn then _createBtn:SetEnabled(CurrentTitle() ~= "") end
    ShowSelIcon()
    RefreshColorHighlight()
    PaintTplCards()
end

local function TplTooltip(owner, name, desc)
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:AddLine(name, 1, 1, 1)
    GameTooltip:AddLine(desc, 0.8, 0.8, 0.8, true)
    GameTooltip:Show()
end

-- The five cards in one row at y (from the page top), and the line under them
local function BuildTplCards(f, body, y, skinMode)
    _tplCards = {}
    _tplSkin = skinMode and true or false
    for i, key in ipairs(BNB.Templates.QUICK) do
        local tpl = BNB.Templates.Get(key)
        local art = tpl and tpl.art or key
        local btn = CreateFrame("Button", nil, body)
        btn:SetSize(TPL_CARD_W, TPL_CARD_H)
        btn:SetPoint("TOPLEFT", f, "TOPLEFT", DLG_PAD + (i - 1) * (TPL_CARD_W + TPL_GAP), y)

        local glow = btn:CreateTexture(nil, "BACKGROUND")
        glow:SetSize(TPL_ART, TPL_ART)
        glow:SetPoint("TOP", btn, "TOP", 0, 0)
        glow:SetTexture(TPL_ART_PATH .. (skinMode and "skin-hover" or (art .. "-hover")))
        glow:Hide()

        local tex = btn:CreateTexture(nil, "ARTWORK")
        tex:SetSize(TPL_ART, TPL_ART)
        tex:SetPoint("TOP", btn, "TOP", 0, 0)
        tex:SetTexture(TPL_ART_PATH .. (skinMode and ("skin-" .. art) or art))

        local lbl = body:CreateFontString(nil, "OVERLAY", "BNBFontNormalSmall")
        lbl:SetPoint("TOPLEFT",  btn, "TOPLEFT",  0, -(TPL_ART + 2))
        lbl:SetPoint("TOPRIGHT", btn, "TOPRIGHT", 0, -(TPL_ART + 2))
        lbl:SetHeight(TPL_LBL_H); lbl:SetJustifyH("CENTER"); lbl:SetWordWrap(false)
        lbl:SetText(L["TPL_CARD_" .. key:upper()])

        local c = { key = key, btn = btn, art = tex, glow = glow, lbl = lbl }
        btn:SetScript("OnEnter", function(self)
            c._hover = true; PaintTplCards()
            if tpl then BNB.TemplateTooltip(self, tpl)
            else TplTooltip(self, L["TPL_" .. key:upper() .. "_NAME"], L["TPL_" .. key:upper() .. "_DESC"]) end
        end)
        btn:SetScript("OnLeave", function()
            c._hover = false; PaintTplCards(); GameTooltip:Hide()
        end)
        btn:SetScript("OnHide", function() c._hover = false end)
        btn:SetScript("OnClick", function()
            if key == "more" then f:ShowPage("more")
            elseif key == "blank" then PickTemplate(nil)
            else PickTemplate(key) end
        end)
        _tplCards[#_tplCards + 1] = c
    end

    local line = body:CreateFontString(nil, "OVERLAY", "BNBFontNormalSmall")
    line:SetPoint("TOPLEFT", f, "TOPLEFT", DLG_PAD, y - TPL_CARD_H - 4)
    line:SetPoint("TOPRIGHT", f, "TOPRIGHT", -DLG_PAD, y - TPL_CARD_H - 4)
    line:SetHeight(TPL_LINE_H); line:SetJustifyH("LEFT"); line:SetWordWrap(false)
    line:SetTextColor(0.65, 0.65, 0.65, 1)
    _tplLine = line
end

-- The More page: every template not on a card, one row each. A pick goes
-- back to the main page with it picked.
local function BuildMorePage(f, top)
    local page = f:AddPage("more", { top = top, pad = DLG_PAD })
    page:SetHeading(L["NND_TPL_MORE_TITLE"])

    local hint = page:CreateFontString(nil, "OVERLAY", "BNBFontNormalSmall")
    hint:SetPoint("TOPLEFT",  page, "TOPLEFT",  DLG_PAD, -(page.top + 2))
    hint:SetPoint("TOPRIGHT", page, "TOPRIGHT", -DLG_PAD, -(page.top + 2))
    hint:SetJustifyH("LEFT")
    hint:SetTextColor(0.65, 0.65, 0.65, 1)
    hint:SetText(L["NND_TPL_MORE_HINT"])

    local sf, ct = BNB.CreateAutoScrollPanel(page, DLG_CW - 24, DLG_CW)
    sf:SetPoint("TOPLEFT", page, "TOPLEFT", DLG_PAD, -(page.top + 20))
    sf:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", -DLG_PAD, DLG_FOOT + 2)
    -- Two headings, shown only once the player has templates of their own
    -- (Dukul, 2026-10-17: a rule alone read as one list); the Settings
    -- Templates page's words
    local function Hdr(key)
        local h = ct:CreateFontString(nil, "OVERLAY", "BNBFontNormal")
        h:SetJustifyH("LEFT")
        BNB.SetHeaderColor(h)
        h:SetText(L[key])
        return h
    end
    _tplMore = { f = f, sf = sf, ct = ct,
                 userHdr = Hdr("CFG_TPL_HDR_USER"), builtHdr = Hdr("CFG_TPL_HDR_BUILTIN") }
end

local MORE_ICON = "Interface\\Icons\\INV_Misc_Note_01"   -- a player's template with no icon

local function MoreRow(i)
    local row = _tplPool[i]
    if row then return row end
    local ct = _tplMore.ct
    row = BNB.CreateBackdropFrame("Button", nil, ct)
    BNB.SetBackdrop(row, 0.06, 0.06, 0.08, 0.95, 0.28, 0.28, 0.30, 1)
    row:SetHeight(TPL_ROW_H)

    local icon = row:CreateTexture(nil, "ARTWORK")
    icon:SetSize(TPL_ROW_H - 8, TPL_ROW_H - 8)
    icon:SetPoint("LEFT", row, "LEFT", 4, 0)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    local nameLbl = row:CreateFontString(nil, "OVERLAY", "BNBFontNormal")
    nameLbl:SetPoint("TOPLEFT",  icon, "TOPRIGHT", 8, -1)
    nameLbl:SetPoint("RIGHT", row, "RIGHT", -6, 0)
    nameLbl:SetJustifyH("LEFT"); nameLbl:SetWordWrap(false)

    local descLbl = row:CreateFontString(nil, "OVERLAY", "BNBFontNormalSmall")
    descLbl:SetPoint("BOTTOMLEFT", icon, "BOTTOMRIGHT", 8, 1)
    descLbl:SetPoint("RIGHT", row, "RIGHT", -6, 0)
    descLbl:SetJustifyH("LEFT"); descLbl:SetWordWrap(false)
    descLbl:SetTextColor(0.65, 0.65, 0.65, 1)

    row.icon, row.nameLbl, row.descLbl = icon, nameLbl, descLbl
    row:SetScript("OnEnter", function(self)
        self._hover = true; PaintTplCards()
        BNB.TemplateTooltip(self, BNB.Templates.Get(self.key), L["TPL_ROW_RIGHT_HINT"])
    end)
    row:SetScript("OnLeave", function(self)
        self._hover = false; PaintTplCards(); GameTooltip:Hide()
    end)
    row:SetScript("OnHide", function(self) self._hover = false end)
    -- Right-click: the template menu, the Settings page's (Dukul, 2026-10-17)
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    row:SetScript("OnClick", function(self, btn)
        if btn == "RightButton" then
            local f = _tplMore.f
            BNB.ContextMenu.Open(self, function(root)
                BNB.TemplateMenu(root, self.key, {
                    row = self, window = f,
                    onUse = function(key) PickTemplate(key); f:PageBack() end,
                    manage = function()
                        NND.Close()
                        BNB.OpenSettingsPage("notes", "templates")
                    end })
            end)
            return
        end
        PickTemplate(self.key)
        _tplMore.f:PageBack()
    end)
    _tplPool[i] = row
    return row
end

-- The More page rows: the player's own templates on top, then the built-ins
-- not on a card, each under its heading while the player has any (Dukul,
-- 2026-10-17). Rebuilt on every Open.
local function FillMoreRows()
    if not _tplMore then return end
    local ct, TP = _tplMore.ct, BNB.Templates
    local user, more = TP.User(), TP.More()
    _tplRows = {}
    local y, n = 0, 0
    local function Add(tpl)
        n = n + 1
        local row = MoreRow(n)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT",  ct, "TOPLEFT",  0, y)
        row:SetPoint("TOPRIGHT", ct, "TOPRIGHT", 0, y)
        row.key = tpl.key
        row.icon:SetTexture(tpl.icon or MORE_ICON)
        row.nameLbl:SetText(TP.Name(tpl))
        row.descLbl:SetText(TP.Desc(tpl))
        row:Show()
        _tplRows[n] = row
        y = y - TPL_ROW_H - 2
    end
    local function Heading(h, gap)
        h:ClearAllPoints()
        h:SetPoint("TOPLEFT", ct, "TOPLEFT", 2, y - gap)
        h:Show()
        y = y - gap - 20
    end
    local headed = #user > 0
    if headed then Heading(_tplMore.userHdr, 0) else _tplMore.userHdr:Hide() end
    for _, tpl in ipairs(user) do Add(tpl) end
    if headed then Heading(_tplMore.builtHdr, 8) else _tplMore.builtHdr:Hide() end
    for _, tpl in ipairs(more) do Add(tpl) end
    for i = n + 1, #_tplPool do _tplPool[i]:Hide() end
    _tplMore.sf:FinaliseHeight(-y)
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
    -- Two pages (ALL-68): the dialog, and the More templates page
    local body = f:AddPage("main")

    f:HookScript("OnHide", function()
        ShowMainOverlay(false)
        BNB.IconPicker.Close(PICKER_KEY)
        if BNB.IconFramePicker and BNB.IconFramePicker.IsOpenFor(PICKER_KEY) then
            BNB.IconFramePicker.Close()
        end
    end)

    -- ── TOP ROW: icon + title editbox ────────────────────────────────────────
    local topY = skinMode and -(BNB.TOOL_SKIN_TITLE_H + 8) or -36

    local iconBtn = BNB.CreateBackdropFrame("Button", nil, body)
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
    local scopeDD = BNB.CreateValueDropdown(body, _scopeEntries, "global", nil, SCOPE_W, 26)
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
    local titleBg = BNB.CreateBackdropFrame("Frame", nil, body)
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
    -- Template cards between the title row and the columns (ALL-68)
    BuildTplCards(f, body, topY - ICON_SZ - 8, skinMode)
    local contentY = topY - ICON_SZ - 10 - TPL_BLOCK_H

    local colL = CreateFrame("Frame", nil, body)
    colL:SetSize(COL_L_W, 1)
    colL:SetPoint("TOPLEFT", f, "TOPLEFT", DLG_PAD, contentY)

    local colR = CreateFrame("Frame", nil, body)
    colR:SetSize(COL_R_W, 1)
    colR:SetPoint("TOPLEFT", f, "TOPLEFT", DLG_PAD + COL_L_W + COL_GAP, contentY)

    -- ── LEFT COLUMN: font cards ───────────────────────────────────────────────
    local fontHdr = body:CreateFontString(nil, "OVERLAY", "BNBFontNormal")
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

        local btn = BNB.CreateBackdropFrame("Button", nil, body)
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
            if defId ~= _selFont then BNB.PaintSelectCard(s, "hover") end
        end)
        btn:SetScript("OnLeave", RefreshFontHighlight)
        btn:SetScript("OnClick", function() SelectFont(defId) end)
        _fontBtns[#_fontBtns + 1] = { btn = btn, id = def.id, nameLbl = nameLbl }
    end

    -- The grid always reserves its 4 rows; free rows carry the font pack hint.
    local usedRows     = math.ceil(#fonts / 2)
    local fontGridRows = math.max(BNB.FONT_GRID_ROWS, usedRows)
    BNB.AddFontPackHint(body, colL, 0, leftY - usedRows * (CARD_H + CARD_GAP),
        COL_L_W, (fontGridRows - usedRows) * (CARD_H + CARD_GAP) - CARD_GAP)
    local WOW_CHECK_H  = 22
    local leftColH = 18 + fontGridRows * (CARD_H + CARD_GAP) - CARD_GAP + WOW_CHECK_H

    -- WoW Default checkbox, below the grid instead of a 9th card. Latin set only;
    -- its row is kept either way so the dialog does not change size.
    local wowCheck = CreateFrame("CheckButton", nil, body, "UICheckButtonTemplate")
    BNB.LabelHit(wowCheck)   -- the tooltip and click reach over its label too
    wowCheck:SetShown(BNB.ShowWoWFontCheckbox())
    wowCheck:SetSize(18, 18)
    wowCheck:SetPoint("TOPLEFT", colL, "TOPLEFT", 0,
        leftY - fontGridRows * (CARD_H + CARD_GAP) + CARD_GAP - 2)
    local wowLbl = body:CreateFontString(nil, "OVERLAY", "BNBFontNormalSmall")
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

    local colorHdr = body:CreateFontString(nil, "OVERLAY", "BNBFontNormal")
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
            local sw  = CreateFrame("Button", nil, body)
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
        local tile = BNB.CreateColorPickerTile(body, SZ, function()
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
    local sizeHdr = body:CreateFontString(nil, "OVERLAY", "BNBFontNormal")
    sizeHdr:SetPoint("TOPLEFT", colR, "TOPLEFT", 0, rightY)
    sizeHdr:SetWidth(COL_R_W); sizeHdr:SetJustifyH("LEFT")
    sizeHdr:SetText(L["NND_FONT_SIZE_HDR"])
    sizeHdr:SetTextColor(0.8, 0.8, 0.8, 1)
    rightY = rightY - 18

    local defaultSize = (BigNoteBoxDB and BigNoteBoxDB.fontSize) or BNB.DEFAULTS.fontSize
    -- Stacked slider with Reset (ALL-121); the header above is its label
    local szWidget = BNB.CreateStackedSlider(body, COL_R_W, {
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
    local sampleHdr = body:CreateFontString(nil, "OVERLAY", "BNBFontNormal")
    sampleHdr:SetPoint("TOPLEFT", colR, "TOPLEFT", 0, rightY)
    sampleHdr:SetWidth(COL_R_W); sampleHdr:SetJustifyH("LEFT")
    sampleHdr:SetText(L["NND_SAMPLE_SIZE_HDR"])
    sampleHdr:SetTextColor(0.8, 0.8, 0.8, 1)
    rightY = rightY - 18

    local previewLbl = body:CreateFontString(nil, "OVERLAY", "BNBFontNormal")
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
    local richCheck = CreateFrame("CheckButton", nil, body, "UICheckButtonTemplate")
    BNB.LabelHit(richCheck)   -- the tooltip and click reach over its label too
    richCheck:SetSize(20, 20)
    richCheck:SetPoint("TOPLEFT", f, "TOPLEFT", DLG_PAD,
        -chromeTopH - ICON_SZ - 10 - TPL_BLOCK_H - colMaxH - 4)
    local richLbl = body:CreateFontString(nil, "OVERLAY", "BNBFontNormalSmall")
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
    local dlgH = chromeTopH + ICON_SZ + 10 + TPL_BLOCK_H + totalContentH + DLG_FOOT + 8
    f:SetHeight(dlgH)
    BuildMorePage(f, chromeTopH - 8)

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

    -- Blank picked, the main page shown (ALL-68)
    _selTpl, _tplTitle = nil, nil
    f:ShowPage("main")
    FillMoreRows()
    PaintTplCards()

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

-- The dialog with a template already picked (Settings > Templates > Use)
function NND.OpenWithTemplate(key)
    NND.Open()
    if _frame and _frame:IsShown() then PickTemplate(key) end
end

-- A template renamed, re-iconed, added or deleted while the dialog is open
-- (the More page menu): rows refilled, a deleted pick falls back to Blank
BNB.RegisterMessage("NewNoteDialog.Templates", "TemplatesChanged", function()
    if not (_frame and _frame:IsShown()) then return end
    if _selTpl and not BNB.Templates.Get(_selTpl) then PickTemplate(nil) end
    FillMoreRows()
    PaintTplCards()
end)

function NND.Close()
    if _frame then _frame:Hide() end
    ShowMainOverlay(false)
    BNB.IconPicker.Close(PICKER_KEY)
    BNB.IconPicker.Close("templateIcon")   -- a More page row's Change icon
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
    -- Body, tags, tasks and situation from the picked template (ALL-68); a
    -- player's template also brings the rest of its look, except what the
    -- dialog just wrote
    local tpl = BNB.Templates.Get(_selTpl)
    if tpl then BNB.Templates.Fill(id, tpl, _selRich, updates) end

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

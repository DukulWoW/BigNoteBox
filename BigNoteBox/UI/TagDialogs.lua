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

-- Icon / image size fields: the list's entries, and the largest value that
-- can be typed (ALL-261, Dukul 2026-10-05)
local SIZE_CHOICES = { 12, 16, 24, 32, 48, 64, 96, 128 }
local SIZE_MAX     = 256
local IMG_SIZE_MAX = 1024   -- images can be wider than a note's icons (Dukul)
local IMG_SIZE_CHOICES = { 12, 16, 24, 32, 48, 64, 96, 128, 256 }   -- 256 = the default

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
        local DW    = 320
        local DPAD  = 14
        local TITLE_H = 28

        -- All Y values are negative offsets from the frame top.
        -- We accumulate curY top-down, then set DH from the final curY.
        local curY = -(TITLE_H + 10)  -- start just below title bar

        -- Chrome from the shared builder (CMP-02); size set after layout is computed
        local f = BNB.CreateToolWindow({
            name = "BNBImgTagDialog", w = DW, h = 1, title = L["NE_INSERT_IMAGE_TITLE"],
            toplevel = true, escClose = true, keyEsc = true,
        })
        f:SetPoint("CENTER", UIParent, "CENTER", 0, 40)

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

        local pickerDD
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
        local alignDD

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

        -- Typeable value lists, like the alarm's hour / minute (ALL-261).
        -- Keep ratio: height follows width at the ratio they had when it was
        -- ticked, and is greyed while it is on.
        local keepRatio, ratio = true, 1
        local widthBox, heightBox
        local function FollowWidth()
            if keepRatio then
                heightBox:SetValue(math.floor(widthBox:GetValue() * ratio + 0.5))
            end
        end
        widthBox = BNB.CreateNumberCombo(f, 1, IMG_SIZE_MAX, 256, NUM_W, 22, {
            values = IMG_SIZE_CHOICES, fmt = "%d", digits = 4, onDirty = FollowWidth,
        })
        widthBox:SetPoint("TOPLEFT", f, "TOPLEFT", DPAD, curY)
        heightBox = BNB.CreateNumberCombo(f, 1, IMG_SIZE_MAX, 256, NUM_W, 22, {
            values = IMG_SIZE_CHOICES, fmt = "%d", digits = 4,
        })
        heightBox:SetPoint("TOPLEFT", f, "TOPLEFT", DPAD + NUM_W + NUM_GAP, curY)
        widthBox.eb:SetScript("OnEscapePressed", function() f:Hide() end)
        heightBox.eb:SetScript("OnEscapePressed", function() f:Hide() end)
        curY = curY - 28

        local ratioCb = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
        ratioCb:SetSize(22, 22)
        ratioCb:SetPoint("TOPLEFT", f, "TOPLEFT", DPAD - 3, curY)
        local ratioLbl = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        ratioLbl:SetPoint("LEFT", ratioCb, "RIGHT", 2, 0)
        ratioLbl:SetTextColor(0.78, 0.78, 0.78); ratioLbl:SetText(L["NE_KEEP_RATIO"])
        local function SetKeepRatio(on)
            keepRatio = on and true or false
            ratioCb:SetChecked(keepRatio)
            if keepRatio then
                ratio = heightBox:GetValue() / math.max(1, widthBox:GetValue())
            end
            heightBox:SetEnabled(not keepRatio)
        end
        ratioCb:SetScript("OnClick", function(self) SetKeepRatio(self:GetChecked()) end)
        ratioCb:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(L["NE_KEEP_RATIO"], 1, 0.82, 0)
            GameTooltip:AddLine(L["NE_KEEP_RATIO_TIP"], 0.85, 0.85, 0.85, true)
            GameTooltip:Show()
        end)
        ratioCb:SetScript("OnLeave", function() GameTooltip:Hide() end)
        curY = curY - 26
        f._widthBox, f._heightBox = widthBox, heightBox
        f._resetSize = function()
            widthBox:SetValue(256); heightBox:SetValue(256)
            SetKeepRatio(true)
        end
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
        end
        f._resetPicker  = function()
            selImage = 0
            if pickerDD and pickerDD.GenerateMenu then pickerDD:GenerateMenu() end
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
        local w = _imgDialog._widthBox:GetValue()
        local h = _imgDialog._heightBox:GetValue()
        local align = ALIGN_OPTS[_imgDialog._selAlign()]
        local tag = string.format("{img:%s:%d:%d:%s}", path, w, h, align)
        _imgDialog:Hide()
        insertFn(tag)
    end)

    -- ── Reset fields and show ─────────────────────────────────────────────────
    _imgDialog._fileEb:SetText("")
    _imgDialog._resetSize()
    _imgDialog._resetAlign()
    _imgDialog._resetPicker()
    _imgDialog._prevTex:SetTexture(nil)
    _imgDialog._prevBg:Hide()
    BNB.SeatWindow(_imgDialog, _imgDialog._strata)   -- also from Focus mode (ALL-251)
    _imgDialog:Show()
    _imgDialog:Raise()
    _imgDialog._fileEb:SetFocus()
end

--------------------------------------------------------------------------------
-- LNK TAG DIALOG
-- Opened by the Lnk button in both markup bars. selText: the text highlighted
-- in the editor (BNB.PeekSelection), filled in as the link text, so Insert
-- wraps the link around it instead of deleting it (ALL-253).
--------------------------------------------------------------------------------
function BNB.OpenLnkDialog(insertFn, selText)
    if not insertFn then return end

    if not _lnkDialog then
        local DW, DH = 320, 180
        local DPAD    = 14
        local TITLE_H = 28

        local f = BNB.CreateToolWindow({   -- shared chrome (CMP-02)
            name = "BNBLnkTagDialog", w = DW, h = DH, title = L["NE_INSERT_LINK_TITLE"],
            toplevel = true, escClose = true, keyEsc = true,
        })
        f:SetPoint("CENTER", UIParent, "CENTER", 0, 40)

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

        -- Enter: URL -> link text -> Insert; Tab / Shift+Tab between the two (ALL-255)
        BNB.TabChain({ urlEb, textEb })
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
    _lnkDialog._textEb:SetText(selText or "")
    BNB.SeatWindow(_lnkDialog, _lnkDialog._strata)   -- also from Focus mode (ALL-251)
    _lnkDialog:Show()
    _lnkDialog:Raise()
    _lnkDialog._urlEb:SetFocus()
end

--------------------------------------------------------------------------------
-- ICO TAG DIALOG
-- The icon comes from BNB.IconPicker, opened beside the dialog (ALL-238,
-- Dukul 2026-10-04: no tabs; a full game icon name or file id typed into the
-- picker's search + Enter replaces the old Blizzard Icon tab). The picker is
-- game-only here: {icon} markup reads names under Interface\Icons, so the
-- bundled race portraits would draw nothing. The dialog keeps the preview,
-- size, alignment and Insert / Cancel.
--------------------------------------------------------------------------------
local ICO_PICKER_KEY = "insertIcon"   -- BNB.IconPicker key + owner

function BNB.OpenIcoDialog(insertFn)
    if not insertFn then return end

    if not _icoDialog then
        local DW        = 320
        local DPAD      = 12
        local TITLE_H   = 28
        local TOP       = TITLE_H + 6   -- content top, under the title
        local INNER_W   = DW - DPAD * 2
        local PICK_H    = 22
        local PREV_SIZE = 48
        local SIZE_EB_W = 90
        local ROW_H     = 22
        local BTN_H     = 26
        local ALIGN_H   = 36   -- alignment label (14) + dropdown (22)
        local DH = TOP + PICK_H + 10 + PREV_SIZE + 12 + ROW_H + 10 + ALIGN_H + 12
            + BTN_H + DPAD

        local f = BNB.CreateToolWindow({   -- shared chrome (CMP-02)
            name = "BNBIcoTagDialog", w = DW, h = DH, title = L["NE_INSERT_ICON_TITLE"],
            toplevel = true, escClose = true, keyEsc = true,
            -- The picker belongs to this dialog while it is open
            onHide = function() BNB.IconPicker.Close(ICO_PICKER_KEY) end,
        })
        f:SetPoint("CENTER", UIParent, "CENTER", 0, 40)

        -- ── Shared state ──────────────────────────────────────────────────────
        local selIcon = nil   -- the picked icon: game path or file id

        -- Choose icon: toggles the picker beside the dialog
        local pickBtn = BNB.CreateButton(nil, f, L["NND_CHOOSE_ICON"], INNER_W, PICK_H)
        BNB.TruncateButtonText(pickBtn)   -- icon names can be long
        pickBtn:SetPoint("TOPLEFT", f, "TOPLEFT", DPAD, -TOP)

        -- Preview (centred, hidden until an icon is picked)
        local prevBg = BNB.CreateBackdropFrame("Frame", nil, f)
        prevBg:SetSize(PREV_SIZE, PREV_SIZE)
        prevBg:SetPoint("TOP", f, "TOP", 0, -(TOP + PICK_H + 10))
        BNB.SetBackdrop(prevBg, 0.04, 0.04, 0.06, 1, 0.25, 0.25, 0.28, 1)
        prevBg:Hide()
        local prevTex = prevBg:CreateTexture(nil, "ARTWORK")
        prevTex:SetPoint("TOPLEFT",     prevBg, "TOPLEFT",     3,  -3)
        prevTex:SetPoint("BOTTOMRIGHT", prevBg, "BOTTOMRIGHT", -3,  3)
        prevTex:SetTexCoord(0.08, 0.92, 0.08, 0.92)

        local function SetIcon(icon)
            selIcon = icon
            if icon then
                pcall(function() prevTex:SetTexture(icon) end)
                prevBg:Show()
                pickBtn:SetText(L["NC_ICON_PICK_BTN"] .. ": " .. BNB.IconPicker.IconName(icon))
            else
                prevTex:SetTexture(nil)
                prevBg:Hide()
                pickBtn:SetText(L["NND_CHOOSE_ICON"])
            end
            if f._insertBtn then f._insertBtn:SetEnabled(icon ~= nil) end
        end

        local function PickHandlers()
            return {
                owner    = ICO_PICKER_KEY,
                gameOnly = true,
                strata   = f:GetFrameStrata(),   -- level with the dialog
                get      = function() return selIcon end,
                set      = function(icon) SetIcon(icon) end,
            }
        end
        f._openPicker = function()
            if BNB.IconPicker.IsOpenFor(ICO_PICKER_KEY) then
                BNB.IconPicker.Rebind(ICO_PICKER_KEY, PickHandlers())
            else
                BNB.IconPicker.Open(ICO_PICKER_KEY, f, PickHandlers())
            end
        end
        pickBtn:SetScript("OnClick", function()
            BNB.IconPicker.Open(ICO_PICKER_KEY, f, PickHandlers())
        end)

        -- Size row: label + number field
        local sizeY = -(TOP + PICK_H + 10 + PREV_SIZE + 12)
        local sizeLbl = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        sizeLbl:SetPoint("TOPLEFT", f, "TOPLEFT", DPAD, sizeY - 4)
        sizeLbl:SetTextColor(0.65, 0.65, 0.65)
        sizeLbl:SetText(L["NE_SIZE_LABEL"])
        -- Typeable value list, like the alarm's hour / minute (ALL-261)
        local sizeBox = BNB.CreateNumberCombo(f, 1, SIZE_MAX, 24, SIZE_EB_W, ROW_H, {
            values = SIZE_CHOICES, fmt = "%d", digits = 3,
            onEnter = function()
                if f._insertBtn and f._insertBtn:IsEnabled() then f._insertBtn:Click() end
            end,
        })
        sizeBox:SetPoint("TOPRIGHT", f, "TOPRIGHT", -DPAD, sizeY)
        sizeBox.eb:SetScript("OnEscapePressed", function() f:Hide() end)

        -- Alignment dropdown
        local ICO_ALIGN_ITEMS = {
            { key = "",   label = L["NE_ICO_ALIGN_INLINE"] },
            { key = ":l", label = L["STICKY_ALIGN_LEFT"]             },
            { key = ":c", label = L["NE_ICO_ALIGN_CENTRE"]           },
            { key = ":r", label = L["STICKY_ALIGN_RIGHT"]            },
        }
        local _icoAlign = ""
        local alignLbl = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        alignLbl:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", DPAD, BTN_H + DPAD + 12 + 22 + 2)
        alignLbl:SetTextColor(0.65, 0.65, 0.65)
        alignLbl:SetText(L["NE_ALIGNMENT_LABEL"])
        local alignDD = CreateFrame("DropdownButton", nil, f, "WowStyle1DropdownTemplate")
        alignDD:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", DPAD, BTN_H + DPAD + 12)
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

        -- Buttons
        local cancelBtn = BNB.CreateButton(nil, f, L["CANCEL"], 90, BTN_H)
        cancelBtn:SetPoint("BOTTOM", f, "BOTTOM", 53, DPAD)
        cancelBtn:SetScript("OnClick", function() f:Hide() end)

        local insertBtn = BNB.CreateButton(nil, f, L["NE_INSERT_BTN"], 90, BTN_H)
        insertBtn:SetPoint("BOTTOM", f, "BOTTOM", -53, DPAD)
        f._insertBtn = insertBtn

        -- ── Stored helpers ────────────────────────────────────────────────────
        f._getIcon  = function() return selIcon end
        f._getSize  = function() return sizeBox:GetValue() end
        f._getAlign = function() return _icoAlign end
        f._resetState = function()
            SetIcon(nil)
            sizeBox:SetValue(24)
            _icoAlign = ""; alignDD:GenerateMenu()
        end

        _icoDialog = f
    end  -- end lazy build

    -- Wire insert callback
    _icoDialog._insertBtn:SetScript("OnClick", function()
        local icon = _icoDialog._getIcon()
        if not icon then return end
        -- {icon} takes a bare name (Interface\Icons is implied) or a file id
        local iconName = type(icon) == "number" and tostring(icon)
            or icon:match("[^\\/]+$") or icon
        local tag = string.format("{icon:%s:%d%s}", iconName,
            _icoDialog._getSize(), _icoDialog._getAlign() or "")
        _icoDialog:Hide()
        insertFn(tag)
    end)

    -- Reset and show, with the picker beside it
    _icoDialog._resetState()
    BNB.SeatWindow(_icoDialog, _icoDialog._strata)   -- also from Focus mode (ALL-251)
    _icoDialog:Show()
    _icoDialog:Raise()
    _icoDialog:Raise()
    _icoDialog._openPicker()
end

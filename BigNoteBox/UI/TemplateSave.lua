-- BigNoteBox UI/TemplateSave.lua
-- Save as template (ALL-68 S2): the note right-click menu's Actions > Save as
-- template opens this window. A name (the note's title to start with), an
-- optional one-line description, the template's icon (the note's to start
-- with, any other through the icon picker), and the Share window's group checkboxes
-- without Unit data (Dukul, 2026-10-17). Title, text and Rich mode always go;
-- Situation starts unticked, the rest ticked. The template itself is written
-- by BNB.Templates.SaveFromNote (Features/NoteTemplates.lua).
--
-- Public API:
--   BNB.OpenSaveTemplate(noteID)

local BNB = BigNoteBox
if not BNB then return end
local L = BNB.L

local W, PAD, FOOT_H = 340, 14, 40
local EB_H, ROW_H, COLS = 22, 24, 2

local ICON_SZ    = 38                    -- the name label and box beside it
local PICKER_KEY = "saveTemplate"        -- BNB.IconPicker key + owner
local NO_ICON    = "Interface\\Icons\\INV_Misc_Note_06"

local _f, _nameEB, _descEB, _saveBtn, _iconBtn
local _cbs = {}
local _noteID, _icon

local function ShowIcon()
    if _iconBtn then _iconBtn._tex:SetTexture(_icon or NO_ICON) end
end

local function FieldEB(f, y, maxLetters, x)
    x = x or 0
    local eb = CreateFrame("EditBox", nil, f, "BackdropTemplate")
    BNB.EnsureBackdrop(eb)
    BNB.SetBackdropDark(eb)
    eb:SetPoint("TOPLEFT", f, "TOPLEFT", PAD + x, y)
    eb:SetSize(W - 2 * PAD - x, EB_H)
    eb:SetFontObject("BNBFontNormal")
    eb:SetAutoFocus(false)
    eb:SetMaxLetters(maxLetters)
    eb:SetTextInsets(4, 4, 0, 0)
    eb:SetScript("OnEscapePressed", function() f:Hide() end)
    return eb
end

local function Label(f, y, text)
    local l = f:CreateFontString(nil, "OVERLAY", "BNBFontNormalSmall")
    l:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, y)
    l:SetWidth(W - 2 * PAD); l:SetJustifyH("LEFT")
    l:SetTextColor(0.78, 0.78, 0.78)
    l:SetText(text)
    return l
end

local function NameText()
    return (_nameEB:GetText() or ""):match("^%s*(.-)%s*$")
end

local function RefreshSave()
    if _saveBtn then _saveBtn:SetEnabled(NameText() ~= "") end
end

local function DoSave()
    if not (_noteID and NameText() ~= "") then return end
    local groups = {}
    for key, cb in pairs(_cbs) do groups[key] = cb:GetChecked() and true or nil end
    local name = NameText()
    local id = BNB.Templates.SaveFromNote(_noteID, name, _descEB:GetText(), groups, _icon)
    _f:Hide()
    if id then BNB:Print(string.format(L["TPL_SAVED_FMT"], name)) end
end

local function Build()
    if _f then return end
    local f, saveBtn, cancelBtn = BNB.CreateToolWindow({
        name = "BNBSaveTemplateFrame", w = W, h = 200, title = L["TPL_SAVE_TITLE"],
        pad = PAD, cw = W - 2 * PAD, footH = FOOT_H,
        btn1 = L["TPL_SAVE_BTN"], btn2 = L["CANCEL"],
        strata = "DIALOG", toplevel = true, escClose = true, keyEsc = true,
        onHide = function()
            _noteID = nil
            BNB.IconPicker.Close(PICKER_KEY)
        end,
    })
    _f, _saveBtn = f, saveBtn
    local y = -((f._isSkin and BNB.TOOL_SKIN_TITLE_H or 28) + 12)

    -- The template's icon (Dukul, 2026-10-17), as the New Note dialog's
    -- icon button: a click toggles the icon picker beside the window
    local iconBtn = BNB.CreateBackdropFrame("Button", nil, f)
    BNB.SetBackdrop(iconBtn, 0.06, 0.06, 0.09, 0.95, 0.35, 0.35, 0.38, 1)
    iconBtn:SetSize(ICON_SZ, ICON_SZ)
    iconBtn:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, y)
    local iconTex = iconBtn:CreateTexture(nil, "ARTWORK")
    iconTex:SetPoint("TOPLEFT",     iconBtn, "TOPLEFT",      3,  -3)
    iconTex:SetPoint("BOTTOMRIGHT", iconBtn, "BOTTOMRIGHT", -3,   3)
    iconTex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    iconBtn._tex = iconTex
    local iconHi = iconBtn:CreateTexture(nil, "HIGHLIGHT")
    iconHi:SetAllPoints(); iconHi:SetColorTexture(1, 1, 1, 0.15)
    iconBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(L["TPL_SAVE_ICON"], 1, 1, 1)
        GameTooltip:AddLine(L["TPL_SAVE_ICON_TIP"], 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    iconBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    iconBtn:SetScript("OnClick", function()
        BNB.IconPicker.Open(PICKER_KEY, f, {
            owner  = PICKER_KEY,
            -- Over this DIALOG-strata window, which raises itself on clicks
            strata = "FULLSCREEN_DIALOG",
            get    = function() return _icon end,
            set    = function(icon) _icon = icon; ShowIcon() end,
        })
    end)
    _iconBtn = iconBtn

    local nameX = ICON_SZ + 8
    local nameLbl = Label(f, y, L["TPL_SAVE_NAME"])
    nameLbl:SetPoint("TOPLEFT", f, "TOPLEFT", PAD + nameX, y)
    nameLbl:SetWidth(W - 2 * PAD - nameX)
    y = y - 16
    _nameEB = FieldEB(f, y, 60, nameX); y = y - EB_H - 10
    _nameEB:SetScript("OnTextChanged", RefreshSave)
    _nameEB:SetScript("OnEnterPressed", DoSave)
    _nameEB:SetScript("OnTabPressed", function() _descEB:SetFocus() end)

    Label(f, y, L["TPL_SAVE_DESC"]); y = y - 16
    _descEB = FieldEB(f, y, 80); y = y - EB_H - 12
    _descEB:SetScript("OnEnterPressed", DoSave)
    _descEB:SetScript("OnTabPressed", function() _nameEB:SetFocus() end)

    Label(f, y, L["TPL_SAVE_INCLUDE"]); y = y - 16
    local hint = Label(f, y, L["TPL_SAVE_ALWAYS"])
    hint:SetTextColor(0.6, 0.6, 0.6)
    hint:SetWordWrap(true)
    y = y - math.max(14, math.ceil(hint:GetStringHeight())) - 4

    -- One checkbox per group, two columns; the label is part of the button
    local colW = (W - 2 * PAD) / COLS
    local groups = BNB.Templates.SAVE_GROUPS
    for i, g in ipairs(groups) do
        local col, row = (i - 1) % COLS, math.floor((i - 1) / COLS)
        local cb = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
        cb:SetSize(24, 24)
        cb:SetPoint("TOPLEFT", f, "TOPLEFT", PAD - 2 + col * colW, y - row * ROW_H + 2)
        cb:SetHitRectInsets(0, -(colW - 30), 0, 0)
        local lbl = f:CreateFontString(nil, "OVERLAY", "BNBFontHighlightSmall")
        lbl:SetPoint("LEFT", cb, "RIGHT", 2, 0)
        lbl:SetWidth(colW - 30); lbl:SetJustifyH("LEFT"); lbl:SetWordWrap(false)
        lbl:SetText(L[g.label])
        cb:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            local r, gg, b = BNB.HeaderColor()
            GameTooltip:AddLine(L[g.label], r, gg, b)
            GameTooltip:AddLine(L[g.tip], 0.8, 0.8, 0.8, true)
            GameTooltip:Show()
        end)
        cb:SetScript("OnLeave", function() GameTooltip:Hide() end)
        _cbs[g.key] = cb
    end
    y = y - math.ceil(#groups / COLS) * ROW_H - 8

    f:SetHeight(-y + FOOT_H)
    saveBtn:SetScript("OnClick", DoSave)
    cancelBtn:SetScript("OnClick", function() f:Hide() end)
end

function BNB.OpenSaveTemplate(noteID)
    local note = noteID and BNB.GetNote(noteID)
    if not note then return end
    -- Unsaved edits in the editor go into the template too
    if BNB.SaveCurrentNote and BNB._currentNoteID == noteID then BNB.SaveCurrentNote() end
    Build()
    _noteID = noteID
    _nameEB:SetText(note.title or "")
    _descEB:SetText("")
    _icon = note.icon
    ShowIcon()
    for key, cb in pairs(_cbs) do cb:SetChecked(key ~= "situation") end
    RefreshSave()
    _f:ClearAllPoints()
    _f:SetPoint("CENTER", UIParent, "CENTER", 0, 80)
    _f:Show()
    _f:Raise()
    _nameEB:SetFocus()
    _nameEB:HighlightText()
end

--------------------------------------------------------------------------------
-- THE TEMPLATE MENU (ALL-68 S2/S3)
-- One menu for a template row, on the New Note dialog's More page and on
-- Settings > Notes > Templates (Dukul, 2026-10-17), so the two never differ.
-- Yours: Use, Rename, Edit description, Change icon, Duplicate, Replace from
-- current note, Share, Delete. Built-ins: Use, Duplicate, Share.
--   BNB.TemplateMenu(root, key, opts)  root = a BNB.ContextMenu builder
--     opts.row     the row (the share code's copy box sits by it)
--     opts.window  the window the icon picker opens beside
--     opts.onUse   what Use does
--     opts.manage  fn: adds Manage templates... at the bottom (More page)
--------------------------------------------------------------------------------
local ICON_KEY = "templateIcon"   -- BNB.IconPicker key + owner for Change icon

local function PopupEditBox(self) return self.editBox or self.EditBox end

-- Popups opened from the New Note dialog must sit over its FULLSCREEN_DIALOG
-- dimmer: lifted while shown, back to DIALOG on hide (StaticPopup frames are
-- shared with the game, so the hook flag is kept here, not on the frame)
local _lifted = {}
local function Popup(which, text, data)
    local d = StaticPopup_Show(which, text, nil, data)
    if not d then return end
    d:SetFrameStrata("FULLSCREEN_DIALOG")
    d:Raise()
    if not _lifted[d] then
        _lifted[d] = true
        d:HookScript("OnHide", function(self) self:SetFrameStrata("DIALOG") end)
    end
end

local function EditAccept(id, field, text)
    if field == "desc" then BNB.Templates.SetDesc(id, text)
    else BNB.Templates.Rename(id, text) end
end

StaticPopupDialogs["BNB_TPL_EDIT"] = {
    preferredIndex = 3,
    text = "%s", hasEditBox = true, maxLetters = 80,
    button1 = L["SAVE"], button2 = L["CANCEL"],
    OnShow = function(self, data)
        local eb = PopupEditBox(self)
        if eb and data then eb:SetText(data.value or ""); eb:HighlightText() end
    end,
    OnAccept = function(self, data)
        local eb = PopupEditBox(self)
        if data and eb then EditAccept(data.id, data.field, eb:GetText()) end
    end,
    EditBoxOnEnterPressed = function(eb)
        local p = eb:GetParent()
        if p.data then EditAccept(p.data.id, p.data.field, eb:GetText()) end
        p:Hide()
    end,
    EditBoxOnEscapePressed = function(eb) eb:GetParent():Hide() end,
    timeout = 0, whileDead = true, hideOnEscape = true,
}

-- Delete and Replace from current note cannot be undone: one confirm each,
-- the work as data (the text arrives ready-made)
StaticPopupDialogs["BNB_TPL_CONFIRM"] = {
    preferredIndex = 3,
    text = "%s", button1 = ACCEPT, button2 = L["CANCEL"],
    OnAccept = function(_, run) if type(run) == "function" then run() end end,
    timeout = 0, whileDead = true, hideOnEscape = true, showAlert = true,
}

local function EditPopup(tpl, field)
    local rec = tpl.rec
    local prompt, value = L["CFG_TPL_RENAME_PROMPT"], rec.name
    if field == "desc" then prompt, value = L["CFG_TPL_DESC_PROMPT"], rec.desc end
    Popup("BNB_TPL_EDIT", string.format(prompt, rec.name or ""),
        { id = tpl.key, field = field, value = value })
end

local function Share(tpl, row)
    local str, err = BNB.Templates.Encode(tpl.key)
    if str then BNB.ShowClipboardHint(str, row, true)
    else BNB:Print("|cffff4444" .. (err or L["TPL_SHARE_ERR"]) .. "|r") end
end

local function ChangeIcon(tpl, window)
    local id = tpl.key
    BNB.IconPicker.Open(ICON_KEY, window, {
        owner  = ICON_KEY,
        strata = "FULLSCREEN_DIALOG",
        get    = function()
            local t = BNB.Templates.Get(id)
            return t and t.icon
        end,
        set    = function(icon) BNB.Templates.SetIcon(id, icon) end,
    })
end

function BNB.TemplateMenu(root, key, opts)
    local TP = BNB.Templates
    local tpl = TP.Get(key)
    if not tpl then return end
    opts = opts or {}
    root:CreateTitle(TP.Name(tpl))
    if opts.onUse then
        root:CreateButton(L["TPL_MENU_USE"], function() opts.onUse(key) end, { icon = "create" })
    end
    if tpl.user then
        root:CreateButton(L["CFG_TPL_RENAME"], function() EditPopup(tpl, "name") end, { icon = "note-settings" })
        root:CreateButton(L["CFG_TPL_EDIT_DESC"], function() EditPopup(tpl, "desc") end, { icon = "editor" })
        if opts.window then
            root:CreateButton(L["TPL_MENU_CHANGE_ICON"], function() ChangeIcon(tpl, opts.window) end,
                { icon = "note" })
        end
    end
    root:CreateButton(L["NL_CTX_DUPLICATE"], function() TP.Duplicate(key) end, { icon = "duplicate" })
    if tpl.user then
        local noteID = BNB._currentNoteID
        local note = noteID and BNB.GetNote(noteID)
        root:CreateButton(L["CFG_TPL_REPLACE"], function()
            Popup("BNB_TPL_CONFIRM",
                string.format(L["CFG_TPL_REPLACE_CONFIRM"], TP.Name(tpl), note.title or ""),
                function()
                    if BNB.SaveCurrentNote then BNB.SaveCurrentNote() end
                    TP.ReplaceFromNote(key, noteID)
                end)
        end, { icon = "save-template", disabled = not note,
               tip = note and string.format(L["CFG_TPL_REPLACE_TIP"], note.title or "")
                     or L["CFG_TPL_REPLACE_NONE"] })
    end
    root:CreateButton(L["TPL_MENU_SHARE"], function() Share(tpl, opts.row) end,
        { icon = "share", tip = L["TPL_MENU_SHARE_TIP"] })
    if tpl.user then
        root:CreateDivider()
        root:CreateButton(L["DELETE"], function()
            Popup("BNB_TPL_CONFIRM", string.format(L["CFG_TPL_DELETE_CONFIRM"], TP.Name(tpl)),
                function() TP.Delete(key) end)
        end, { icon = "trash", danger = true })
    end
    if opts.manage then
        root:CreateDivider()
        root:CreateButton(L["TPL_MENU_MANAGE"], opts.manage, { icon = "note-settings" })
    end
end

-- Tooltip for a template: name, description, then a short preview
function BNB.TemplateTooltip(owner, tpl, hint)
    local TP = BNB.Templates
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:AddLine(TP.Name(tpl), 1, 1, 1)
    GameTooltip:AddLine(TP.Desc(tpl), 0.8, 0.8, 0.8, true)
    local lines = TP.Preview(tpl)
    if #lines > 0 then
        GameTooltip:AddLine(" ")
        for _, line in ipairs(lines) do GameTooltip:AddLine(line, 0.6, 0.6, 0.6, true) end
    end
    if hint then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(hint, 0.4, 0.85, 0.4, true)
    end
    GameTooltip:Show()
end

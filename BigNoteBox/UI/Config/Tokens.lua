-- BigNoteBox UI/Config/Tokens.lua - Settings > Notes > Note tokens (ALL-481 S4)
-- The player's own tokens: a name and a line of text that may use the
-- built-in tokens and other custom ones (Features/Tokens.lua). A row shows
-- {{name}}, its text and what it gives right now; a click opens Edit /
-- Delete. Add token and Edit open a small window (name, text, live preview).
-- Rows are rebuilt on CustomTokensChanged and whenever the page shows.
-- Built by UI/Config/Notes.lua through K.BuildTokensPage. The toolbar's token
-- button lists the same tokens under My tokens and opens this page.
--
-- Public API:
--   BNB.OpenTokenEdit(name)   nil = a new token

local BNB = BigNoteBox
local L   = BNB.L

local K = BNB._ConfigKit
local CONTENT_W = K.CONTENT_W

local ROW_H   = 40
local ROW_GAP = 2

--------------------------------------------------------------------------------
-- EDIT WINDOW
--------------------------------------------------------------------------------
local W, PAD, FOOT_H, EB_H = 380, 14, 40, 22
local _ed, _nameEB, _textEB, _preview, _err, _saveBtn
local _oldName

local function Field(f, y, maxLetters)
    local eb = CreateFrame("EditBox", nil, f, "BackdropTemplate")
    BNB.EnsureBackdrop(eb)
    BNB.SetBackdropDark(eb)
    eb:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, y)
    eb:SetSize(W - 2 * PAD, EB_H)
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

local function UpdatePreview()
    local text = _textEB:GetText() or ""
    local now = BNB.Tokens.CustomPreview(text)
    if now == "" then now = "|cff888888-|r" end
    _preview:SetText(string.format(L["TOKEN_TIP_NOW"], "|cffffffff" .. now .. "|r"))
    _err:SetText("")
    local name = (_nameEB:GetText() or ""):gsub("[{}%s]", "")
    _saveBtn:SetEnabled(name ~= "" and not text:match("^%s*$"))
end

local function DoSave()
    if not _saveBtn:IsEnabled() then return end
    local ok, err = BNB.Tokens.SetCustom(_nameEB:GetText(), _textEB:GetText(), _oldName)
    if ok then _ed:Hide() else _err:SetText(err or "") end
end

local function BuildEdit()
    if _ed then return end
    local f, saveBtn, cancelBtn = BNB.CreateToolWindow({
        name = "BNBTokenEditFrame", w = W, h = 200, title = L["TOKEN_EDIT_TITLE"],
        pad = PAD, cw = W - 2 * PAD, footH = FOOT_H,
        btn1 = L["SAVE"], btn2 = L["CANCEL"],
        strata = "DIALOG", toplevel = true, escClose = true, keyEsc = true,
        onHide = function() _oldName = nil end,
    })
    _ed, _saveBtn = f, saveBtn
    local y = -((f._isSkin and BNB.TOOL_SKIN_TITLE_H or 28) + 12)

    Label(f, y, L["TOKEN_EDIT_NAME"]); y = y - 16
    _nameEB = Field(f, y, 30); y = y - EB_H - 4
    local nameHint = Label(f, y, L["TOKEN_EDIT_NAME_HINT"])
    nameHint:SetTextColor(0.55, 0.55, 0.55)
    y = y - 16 - 8

    Label(f, y, L["TOKEN_EDIT_TEXT"]); y = y - 16
    _textEB = Field(f, y, 255); y = y - EB_H - 4
    local textHint = Label(f, y, L["TOKEN_EDIT_TEXT_HINT"])
    textHint:SetTextColor(0.55, 0.55, 0.55)
    textHint:SetWordWrap(true)
    y = y - math.max(16, math.ceil(textHint:GetStringHeight())) - 8

    _preview = Label(f, y, "")
    _preview:SetWordWrap(true)
    y = y - 32
    _err = Label(f, y, "")
    _err:SetTextColor(1, 0.35, 0.35)
    y = y - 18

    f:SetHeight(-y + FOOT_H)
    _nameEB:SetScript("OnTextChanged", UpdatePreview)
    _nameEB:SetScript("OnEnterPressed", DoSave)
    _nameEB:SetScript("OnTabPressed", function() _textEB:SetFocus() end)
    _textEB:SetScript("OnTextChanged", UpdatePreview)
    _textEB:SetScript("OnEnterPressed", DoSave)
    -- Typing {{ in the text lists the tokens it can use (after the box's
    -- own scripts); Tab there picks from that list
    BNB.Tokens.WireAutocomplete(_textEB)
    saveBtn:SetScript("OnClick", DoSave)
    cancelBtn:SetScript("OnClick", function() f:Hide() end)
end

function BNB.OpenTokenEdit(name)
    if not BNB.Tokens then return end
    BuildEdit()
    local rec = name and BNB.Tokens.GetCustom(name)
    _oldName = rec and rec.name or nil
    local title = L["TOKEN_NEW_TITLE"]
    if rec then title = L["TOKEN_EDIT_TITLE"] end
    _ed:SetWindowTitle(title)
    _nameEB:SetText(rec and rec.name or "")
    _textEB:SetText(rec and rec.text or "")
    UpdatePreview()
    -- Can open from Focus mode's token button (UIParent hidden there)
    if BNB.SeatWindow then BNB.SeatWindow(_ed, _ed._strata) end
    _ed:ClearAllPoints()
    _ed:SetPoint("CENTER", _ed:GetParent() or UIParent, "CENTER", 0, 80)
    _ed:Show()
    _ed:Raise()
    if rec then _textEB:SetFocus() else _nameEB:SetFocus() end
end

StaticPopupDialogs["BNB_TOKEN_DELETE"] = {
    preferredIndex = 3,
    text = "%s", button1 = L["DELETE"], button2 = L["CANCEL"],
    OnAccept = function(_, name) if name then BNB.Tokens.DeleteCustom(name) end end,
    timeout = 0, whileDead = true, hideOnEscape = true, showAlert = true,
}

-- Edit / Delete, shared by the page's rows and the toolbar's My tokens list
function BNB.CustomTokenMenu(root, name)
    root:CreateTitle("{{" .. name .. "}}")
    root:CreateButton(L["TOKEN_MENU_EDIT"], function() BNB.OpenTokenEdit(name) end, { icon = "editor" })
    root:CreateButton(L["DELETE"], function()
        StaticPopup_Show("BNB_TOKEN_DELETE", string.format(L["TOKEN_DELETE_CONFIRM"], name), nil, name)
    end, { icon = "trash", danger = true })
end

--------------------------------------------------------------------------------
-- THE PAGE
--------------------------------------------------------------------------------
function K.BuildTokensPage(sf, ct, y)
    local desc = ct:CreateFontString(nil, "OVERLAY", "BNBFontHighlightSmall")
    desc:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
    desc:SetWidth(CONTENT_W); desc:SetJustifyH("LEFT"); desc:SetWordWrap(true)
    desc:SetTextColor(0.8, 0.8, 0.8)
    desc:SetText(L["CFG_TOKENS_PAGE_DESC"])
    y = y - math.ceil(desc:GetStringHeight()) - 10

    local addBtn = BNB.CreateButton(nil, ct, L["TOKEN_ADD_BTN"], 140, 22)
    addBtn:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
    addBtn:SetScript("OnClick", function() BNB.OpenTokenEdit(nil) end)
    local top = y - 22 - 12

    local empty = BNB.CreateSmallLabel(ct, L["CFG_TOKENS_NONE"], 0, CONTENT_W)
    empty:SetWordWrap(true)

    local pool = {}
    local function Row(i)
        if pool[i] then return pool[i] end
        local row = BNB.CreateBackdropFrame("Button", nil, ct)
        BNB.SetBackdrop(row, 0.06, 0.06, 0.08, 0.95, 0.28, 0.28, 0.30, 1)
        row:SetHeight(ROW_H)
        row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        local name = row:CreateFontString(nil, "OVERLAY", "BNBFontNormal")
        name:SetPoint("TOPLEFT", row, "TOPLEFT", 8, -5)
        name:SetPoint("RIGHT", row, "RIGHT", -6, 0)
        name:SetJustifyH("LEFT"); name:SetWordWrap(false)
        local d = row:CreateFontString(nil, "OVERLAY", "BNBFontNormalSmall")
        d:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 8, 5)
        d:SetPoint("RIGHT", row, "RIGHT", -6, 0)
        d:SetJustifyH("LEFT"); d:SetWordWrap(false)
        d:SetTextColor(0.65, 0.65, 0.65, 1)
        row.nameLbl, row.descLbl = name, d
        row:SetScript("OnClick", function(self)
            BNB.ContextMenu.Open(self, function(root) BNB.CustomTokenMenu(root, self.key) end)
        end)
        row:SetScript("OnEnter", function(self)
            BNB.PaintSelectCard(self, "hover", self.nameLbl)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine("{{" .. self.key .. "}}", 1, 1, 1)
            GameTooltip:AddLine(self.text or "", 0.8, 0.8, 0.8, true)
            local now = BNB.Tokens.CustomPreview(self.text or "")
            GameTooltip:AddLine(string.format(L["TOKEN_TIP_NOW"], "|cffffffff" .. now .. "|r"), 0.6, 0.6, 0.6, true)
            GameTooltip:AddLine(L["CFG_TOKENS_ROW_TIP"], 0.4, 0.85, 0.4, true)
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function(self)
            BNB.PaintSelectCard(self, nil, self.nameLbl)
            GameTooltip:Hide()
        end)
        pool[i] = row
        return row
    end

    local function Layout()
        local list = BNB.Tokens and BNB.Tokens.Custom() or {}
        local yy = top
        empty:ClearAllPoints()
        empty:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, yy)
        empty:SetShown(#list == 0)
        if #list == 0 then yy = yy - math.ceil(empty:GetStringHeight()) - 6 end
        for i, e in ipairs(list) do
            local row = Row(i)
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT",  ct, "TOPLEFT",  0, yy)
            row:SetPoint("TOPRIGHT", ct, "TOPRIGHT", 0, yy)
            row.key, row.text = e.name, e.text
            row.nameLbl:SetText("{{" .. e.name .. "}}  |cff888888" .. e.text .. "|r")
            row.descLbl:SetText(string.format(L["TOKEN_TIP_NOW"], BNB.Tokens.CustomPreview(e.text)))
            BNB.PaintSelectCard(row, nil, row.nameLbl)
            row:Show()
            yy = yy - ROW_H - ROW_GAP
        end
        for i = #list + 1, #pool do pool[i]:Hide() end
        sf:FinaliseHeight(-yy + 8)
    end

    Layout()
    sf:HookScript("OnShow", Layout)
    BNB.RegisterMessage("ConfigTokens", "CustomTokensChanged", function()
        if sf:IsVisible() then Layout() end
    end)
end

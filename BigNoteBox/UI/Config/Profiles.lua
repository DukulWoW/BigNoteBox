-- BigNoteBox UI/Config/Profiles.lua - the Profiles row on Settings > Advanced (ALL-496)
-- Profiles [dropdown] [Import] [Export] [Delete], first on the tab (Dukul,
-- 2026-10-18). The logic is Core/Profiles.lua. Picking a profile, a blank
-- profile, an import and deleting the one in use end in a reload, always from
-- a popup button's own click (C_UI.Reload is protected).

local BNB = BigNoteBox
local L   = BNB.L

local K = BNB._ConfigKit
local CONTENT_W = K.CONTENT_W
local AddHeader = K.AddHeader

local P = BNB.Profiles
local _refresh   -- redraws the row after a rename / clone / delete

local function PopupEditBox(self) return (self.GetEditBox and self:GetEditBox()) or self.editBox or self.EditBox end

local function Refresh() if _refresh then _refresh() end end

local function Err(msg) BNB:Print("|cffff5555" .. msg .. "|r") end

-- ── Popups ───────────────────────────────────────────────────────────────────
-- Use name on this character from the next load: the reload is this click
local function UseAndReload(_, name)
    if not name then return end
    P.UseOnThisChar(name)
    C_UI.Reload()
end

StaticPopupDialogs["BNB_PROFILE_SWITCH"] = {
    preferredIndex = 3,
    text = L["PROFILE_SWITCH_TEXT"],
    button1 = L["CFG_RELOAD_NOW_BTN"], button2 = CANCEL,
    OnAccept = UseAndReload,
    timeout = 0, whileDead = true, hideOnEscape = true,
}

-- After a blank profile or an import: Later keeps it in the dropdown, unused
StaticPopupDialogs["BNB_PROFILE_USE_NEW"] = {
    preferredIndex = 3,
    text = "%s",
    button1 = L["CFG_RELOAD_NOW_BTN"], button2 = L["CFG_LATER_BTN"],
    OnAccept = UseAndReload,
    timeout = 0, whileDead = true, hideOnEscape = true,
}

local ShowName   -- below: the name popup reopens itself after a bad name

-- data = { mode = "clone" | "blank" | "rename" | "import", old, payload }
local function SubmitName(text, data)
    if not data then return end
    local name, err = P.CheckName(text, data.mode == "rename" and data.old or nil)
    if not name then
        Err(err)
        C_Timer.After(0.1, function() ShowName(data, text) end)
        return
    end
    if data.mode == "clone" then
        local from = P.Active()
        P.Clone(name)
        BNB:Print(string.format(L["PROFILE_CLONED"], name, P.DisplayName(from)))
    elseif data.mode == "rename" then
        P.Rename(data.old, name)
        BNB:Print(string.format(L["PROFILE_RENAMED"], data.old, name))
    elseif data.mode == "blank" then
        P.CreateBlank(name)
        C_Timer.After(0.1, function()
            StaticPopup_Show("BNB_PROFILE_USE_NEW", string.format(L["PROFILE_BLANK_READY"], name), nil, name)
        end)
    elseif data.mode == "import" and data.payload then
        P.AddImported(name, data.payload)
        C_Timer.After(0.1, function()
            StaticPopup_Show("BNB_PROFILE_USE_NEW", string.format(L["PROFILE_IMPORT_READY"], name), nil, name)
        end)
    end
    Refresh()
end

StaticPopupDialogs["BNB_PROFILE_NAME"] = {
    preferredIndex = 3,
    text = "%s", hasEditBox = true, maxLetters = P.MAX_NAME,
    button1 = OKAY, button2 = CANCEL,
    OnShow = function(self, data)
        local eb = PopupEditBox(self)
        if eb then eb:SetText(data and data.text or ""); eb:HighlightText(); eb:SetFocus() end
    end,
    OnAccept = function(self, data)
        local eb = PopupEditBox(self)
        SubmitName(eb and eb:GetText(), data)
    end,
    EditBoxOnEnterPressed = function(eb)
        local p = eb:GetParent()
        local data = p.data
        p:Hide()
        SubmitName(eb:GetText(), data)
    end,
    EditBoxOnEscapePressed = function(eb) eb:GetParent():Hide() end,
    timeout = 0, whileDead = true, hideOnEscape = true,
}

ShowName = function(data, text)
    local prompt
    if data.mode == "clone" then
        prompt = string.format(L["PROFILE_NAME_CLONE"], P.DisplayName(P.Active()))
    elseif data.mode == "blank" then
        prompt = L["PROFILE_NAME_BLANK"]
    elseif data.mode == "rename" then
        prompt = string.format(L["PROFILE_NAME_RENAME"], data.old)
    else
        prompt = L["PROFILE_NAME_IMPORT"]
    end
    data.text = text
    StaticPopup_Show("BNB_PROFILE_NAME", prompt, nil, data)
end

StaticPopupDialogs["BNB_PROFILE_DELETE"] = {
    preferredIndex = 3,
    text = "%s",
    button1 = DELETE, button2 = CANCEL,
    OnAccept = function(_, name)
        if not name then return end
        if P.Delete(name) then C_UI.Reload(); return end
        BNB:Print(string.format(L["PROFILE_DELETED"], name))
        Refresh()
    end,
    timeout = 0, whileDead = true, hideOnEscape = true,
}

local function TryImport(text)
    local payload = P.Decode(text)
    if not payload then Err(L["PROFILE_IMPORT_BAD"]); return end
    -- Name it next frame: this popup is still closing
    C_Timer.After(0.1, function()
        ShowName({ mode = "import", payload = payload }, P.FreeName(payload.name))
    end)
end

-- A profile code pasted into Settings > Backup > Import (ALL-507): the same
-- name prompt as the row's Import. False when it is not a valid code.
function BNB.ImportProfileCode(text)
    local payload = P.Decode(text)
    if not payload then return false end
    ShowName({ mode = "import", payload = payload }, P.FreeName(payload.name))
    return true
end

StaticPopupDialogs["BNB_PROFILE_IMPORT"] = {
    preferredIndex = 3,
    text = L["PROFILE_IMPORT_TEXT"], hasEditBox = true, editBoxWidth = 350, maxLetters = 0,
    button1 = L["PROFILE_IMPORT_BTN"], button2 = CANCEL,
    OnShow = function(self) local eb = PopupEditBox(self); if eb then eb:SetText(""); eb:SetFocus() end end,
    OnAccept = function(self) local eb = PopupEditBox(self); TryImport(eb and eb:GetText()) end,
    EditBoxOnEnterPressed = function(eb) eb:GetParent():Hide(); TryImport(eb:GetText()) end,
    EditBoxOnEscapePressed = function(eb) eb:GetParent():Hide() end,
    timeout = 0, whileDead = true, hideOnEscape = true,
}

-- ── The row ──────────────────────────────────────────────────────────────────
local function Tip(btn, title, body)
    btn:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(title, 1, 1, 1)
        GameTooltip:AddLine(type(body) == "function" and body() or body, 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    btn:HookScript("OnLeave", function() GameTooltip:Hide() end)
end

local function Deletable()
    local list = {}
    for _, n in ipairs(P.List()) do
        if n ~= P.DEFAULT then list[#list + 1] = n end
    end
    return list
end

-- Header, a grey line, then the row. Returns the new y.
function K.AddProfileRow(ct, y)
    y = AddHeader(ct, y, L["CFG_HDR_PROFILES"])

    local desc = ct:CreateFontString(nil, "OVERLAY", "BNBFontNormalSmall")
    desc:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
    desc:SetWidth(CONTENT_W); desc:SetJustifyH("LEFT"); desc:SetWordWrap(true)
    desc:SetTextColor(0.6, 0.6, 0.6)
    desc:SetText(L["CFG_PROFILES_DESC"])
    y = y - math.ceil(desc:GetStringHeight()) - 8

    local BTN_W, GAP = 70, 6
    local dd = BNB.SkinDropdown(CreateFrame("DropdownButton", nil, ct, "WowStyle1DropdownTemplate"))
    dd:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
    dd:SetWidth(CONTENT_W - 3 * (BTN_W + GAP))
    dd:SetupMenu(function(_, root)
        local active = P.Active()
        for _, n in ipairs(P.List()) do
            root:CreateRadio(P.DisplayName(n),
                function() return n == active end,
                function()
                    if n == P.Active() then return end
                    StaticPopup_Show("BNB_PROFILE_SWITCH", P.DisplayName(n), nil, n)
                end)
        end
        root:CreateDivider()
        root:CreateButton(L["PROFILE_NEW_CLONE"], function() ShowName({ mode = "clone" }) end)
        root:CreateButton(L["PROFILE_NEW_BLANK"], function() ShowName({ mode = "blank" }) end)
        local ren = root:CreateButton(L["PROFILE_RENAME"], function()
            ShowName({ mode = "rename", old = P.Active() }, P.Active())
        end)
        if active == P.DEFAULT then ren:SetEnabled(false) end
    end)
    dd:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(L["CFG_HDR_PROFILES"], 1, 1, 1)
        GameTooltip:AddLine(L["PROFILE_DD_TIP"], 0.8, 0.8, 0.8, true)
        local chars = P.CharsUsing(P.Active())
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(string.format(L["PROFILE_USED_BY"], table.concat(chars, ", ")), 0.6, 0.85, 0.6, true)
        GameTooltip:Show()
    end)
    dd:SetScript("OnLeave", function() GameTooltip:Hide() end)

    local impBtn = BNB.CreateButton(nil, ct, L["PROFILE_IMPORT_BTN"], BTN_W, 24)
    impBtn:SetPoint("LEFT", dd, "RIGHT", GAP, 0)
    impBtn:SetScript("OnClick", function() StaticPopup_Show("BNB_PROFILE_IMPORT") end)
    Tip(impBtn, L["PROFILE_IMPORT_BTN"], L["PROFILE_IMPORT_TIP"])

    local expBtn = BNB.CreateButton(nil, ct, L["PROFILE_EXPORT_BTN"], BTN_W, 24)
    expBtn:SetPoint("LEFT", impBtn, "RIGHT", GAP, 0)
    -- Our copy popup (Ctrl+C), as share codes (Dukul, 2026-10-18)
    expBtn:SetScript("OnClick", function(self)
        local code = P.Export()
        if not code then Err(L["PROFILE_ERR_GENERATE"]); return end
        BNB.ShowClipboardHint(code, self, true)
    end)
    Tip(expBtn, L["PROFILE_EXPORT_BTN"], L["PROFILE_EXPORT_TIP"])

    -- A menu of the profiles that can go (all but Default)
    local delBtn = BNB.CreateButton(nil, ct, L["PROFILE_DELETE_BTN"], BTN_W, 24)
    delBtn:SetPoint("LEFT", expBtn, "RIGHT", GAP, 0)
    delBtn:SetMotionScriptsWhileDisabled(true)   -- the tooltip says why
    delBtn:SetScript("OnClick", function(self)
        local list = Deletable()
        if #list == 0 then return end
        MenuUtil.CreateContextMenu(self, function(_, root)
            for _, n in ipairs(list) do
                local label, key = n, "PROFILE_DELETE_TEXT"
                if n == P.Active() then
                    label, key = string.format(L["PROFILE_IN_USE"], n), "PROFILE_DELETE_ACTIVE"
                end
                root:CreateButton(label, function()
                    StaticPopup_Show("BNB_PROFILE_DELETE", string.format(L[key], n), nil, n)
                end)
            end
        end)
    end)
    Tip(delBtn, L["PROFILE_DELETE_BTN"], function()
        if #Deletable() == 0 then return L["PROFILE_DELETE_NONE_TIP"] end
        return L["PROFILE_DELETE_TIP"]
    end)

    _refresh = function()
        if dd.GenerateMenu then dd:GenerateMenu() end
        delBtn:SetEnabled(#Deletable() > 0)
    end
    _refresh()
    ct:HookScript("OnShow", _refresh)

    return y - 34
end

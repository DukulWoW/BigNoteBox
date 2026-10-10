-- BigNoteBox UI/Config/Advanced.lua - Settings Advanced tab
-- Split out of ConfigWindow.lua (ALL-65.10).

local BNB = BigNoteBox
local L   = BNB.L

local K = BNB._ConfigKit
local CONTENT_W = K.CONTENT_W
local AddRule, AddHeader, AddCheck = K.AddRule, K.AddHeader, K.AddCheck

-- ─────────────────────────────────────────────────────────────────────────────
-- TAB 4 — ADVANCED
-- ─────────────────────────────────────────────────────────────────────────────
local function BuildAdvancedTab(sf, ct)
    local db = BigNoteBoxDB
    local y  = -8

    -- ── Addon integrations (ALL-315), first on the tab (Dukul, 2026-10-10): a
    -- 2x2 grid of the addons BNB works with, logo, name and whether it is active. Not active: a button that copies
    -- the CurseForge link. EasyFind joins as the fourth card with ALL-306.
    y = AddHeader(ct, y, L["CFG_HDR_INTEGRATIONS"])
    do
        local ASSET   = "Interface\\AddOns\\BigNoteBox\\Assets\\BCB\\"
        local INTEG = {
            { name = "BigChatBox", logo = "bcb-logo", desc = L["CFG_BCB_DESC"],
              url = "https://www.curseforge.com/wow/addons/bigchatbox",
              addon = "BigChatBox" },
            { name = "TomTom", logo = "addon-tomtom", desc = L["CFG_INTEG_TOMTOM_DESC"],
              url = "https://www.curseforge.com/wow/addons/tomtom",
              addon = "TomTom" },
            { name = "WaypointUI", logo = "addon-waypointui", desc = L["CFG_INTEG_WPUI_DESC"],
              url = "https://www.curseforge.com/wow/addons/waypointui",
              addon = "WaypointUI" },
        }
        local GAP, CARD_H, LOGO = 12, 60, 44
        local cardW = math.floor((CONTENT_W - GAP) / 2)
        local cards = {}
        for i, a in ipairs(INTEG) do
            local col, row = (i - 1) % 2, math.floor((i - 1) / 2)
            local card = BNB.CreateBackdropFrame("Frame", nil, ct)
            card:SetSize(cardW, CARD_H)
            card:SetPoint("TOPLEFT", ct, "TOPLEFT", col * (cardW + GAP), y - row * (CARD_H + GAP))
            BNB.PaintSelectCard(card, nil)
            cards[#cards + 1] = card
            -- The addon itself loaded, by folder name: a global like TomTom can
            -- come from another addon (MapPinEnhanced makes one; a disabled
            -- TomTom showed as Active, Dukul 2026-10-10)
            local on = C_AddOns.IsAddOnLoaded(a.addon) and true or false
            local logo = card:CreateTexture(nil, "ARTWORK")
            logo:SetSize(LOGO, LOGO)
            logo:SetPoint("LEFT", card, "LEFT", 8, 0)
            logo:SetTexture(ASSET .. a.logo)
            if not on then logo:SetDesaturated(true); logo:SetAlpha(0.6) end
            local nameLbl = card:CreateFontString(nil, "OVERLAY", "BNBFontNormal")
            nameLbl:SetPoint("TOPLEFT", logo, "TOPRIGHT", 10, -4)
            nameLbl:SetPoint("RIGHT", card, "RIGHT", -8, 0)
            nameLbl:SetJustifyH("LEFT"); nameLbl:SetWordWrap(false)
            nameLbl:SetText(a.name)
            BNB.SetHeaderColor(nameLbl)
            if on then
                local st = card:CreateFontString(nil, "OVERLAY", "BNBFontNormalSmall")
                st:SetPoint("BOTTOMLEFT", logo, "BOTTOMRIGHT", 10, 4)
                st:SetText("|cff66bb6a" .. L["CFG_INTEG_ACTIVE"] .. "|r")
            else
                local get = BNB.CreateButton(nil, card, L["CFG_INTEG_GET_BTN"], 110, 20)
                get:SetPoint("BOTTOMLEFT", logo, "BOTTOMRIGHT", 10, 0)
                get:SetScript("OnClick", function(self) BNB.ShowClipboardHint(a.url, self, true, true) end)
                get:HookScript("OnEnter", function(self)
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:AddLine(a.name, 1, 1, 1)
                    GameTooltip:AddLine(L["CFG_INTEG_GET_TIP"], 0.8, 0.8, 0.8, true)
                    GameTooltip:AddLine(a.url, 0.6, 0.6, 0.6)
                    GameTooltip:Show()
                end)
                get:HookScript("OnLeave", function() GameTooltip:Hide() end)
            end
            -- What BNB does with it, on the card
            card:EnableMouse(true)
            card:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:AddLine(a.name, 1, 1, 1)
                GameTooltip:AddLine(a.desc, 0.8, 0.8, 0.8, true)
                GameTooltip:AddLine(on and L["CFG_INTEG_ACTIVE"] or L["CFG_INTEG_INACTIVE"],
                    on and 0.4 or 0.6, on and 0.73 or 0.6, on and 0.42 or 0.6)
                GameTooltip:Show()
            end)
            card:SetScript("OnLeave", function() GameTooltip:Hide() end)
        end
        BNB.RegisterMessage("Config.IntegCards", "SkinChanged", function()
            for _, c in ipairs(cards) do BNB.PaintSelectCard(c, nil) end
        end)
        local rows = math.ceil(#INTEG / 2)
        y = y - rows * CARD_H - (rows - 1) * GAP - 12
    end

    AddRule(ct, y); y = y - 18
    y = AddHeader(ct, y, L["CFG_HDR_BEHAVIOR"])

    -- Both checkboxes on one row, so the tab fits without scrolling (Dukul,
    -- 2026-10-10): the second moves to the right half, the first label stops
    -- short of it
    local HALF = math.floor(CONTENT_W / 2)
    local rowY = y
    local minimapCb, loginCb
    y, minimapCb = AddCheck(ct, y, L["CONFIG_SHOW_MINIMAP"],
        function() return not (db.minimapIcon and db.minimapIcon.hide) end,
        function(v) BNB.SetMinimapButtonShown(v) end,
        L["CONFIG_SHOW_MINIMAP_TIP"])

    local _
    _, loginCb = AddCheck(ct, rowY, L["CONFIG_HIDE_LOGIN_MSG"],
        function() return db.hideLoginMessage == true end,
        function(v) db.hideLoginMessage = v end,
        "Suppress the \"BigNoteBox v... loaded\" chat message on login.")
    loginCb:ClearAllPoints()
    loginCb:SetPoint("TOPLEFT", ct, "TOPLEFT", HALF - 2, rowY + 2)
    minimapCb._lbl:SetPoint("RIGHT", ct, "LEFT", HALF - 8, 0)

    -- ── Developer section ───────────────────────────────────────────────────
    AddRule(ct, y); y = y - 18
    y = AddHeader(ct, y, L["CFG_HDR_DEVELOPER"])

    local devDesc2 = ct:CreateFontString(nil, "OVERLAY", "BNBFontNormalSmall")
    devDesc2:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
    devDesc2:SetWidth(CONTENT_W); devDesc2:SetJustifyH("LEFT")
    devDesc2:SetWordWrap(true); devDesc2:SetHeight(20)
    devDesc2:SetTextColor(0.50, 0.50, 0.50)
    devDesc2:SetText(L["CFG_DEV_DESC"])
    y = y - 24

    -- Debug mode works without the dev addon, for this session only (ALL-395).
    -- In dev mode it is always on: checked and greyed.
    local devMode = BNB.IsDevMode()
    local dbgCb
    y, dbgCb = AddCheck(ct, y, L["CFG_DEBUG_MODE_LABEL"],
        function() return BNB.IsDebugMode() end,
        function(v)
            if not BNB.SetDebugMode(v) then dbgCb:SetChecked(BNB.IsDebugMode()) end
        end,
        devMode and L["CFG_DEBUG_MODE_DEV_TIP"] or L["CFG_DEBUG_MODE_TIP"])
    K.ReadOnShow(dbgCb, function() return BNB.IsDebugMode() end)
    if devMode then
        dbgCb:SetEnabled(false); dbgCb._lbl:SetAlpha(0.6)
        dbgCb:SetMotionScriptsWhileDisabled(true)   -- the tooltip says why
    end

    -- Pseudo-locale stays here, not on the dev page, so translators can use it
    -- without the dev addon (Dukul, 2026-10-08). Not tied to debug mode: it
    -- takes a reload, and debug mode is cleared on every load.
    y = AddCheck(ct, y, L["CFG_DEV_PSEUDOLOC_LABEL"],
        function() return BigNoteBoxDB.debugPseudoLocale == true end,
        function(v) BigNoteBoxDB.debugPseudoLocale = v or nil end,
        L["CFG_DEV_PSEUDOLOC_TIP_BODY"])
    y = y - 6

    -- The tools are a sub-page (UI/Config/DevTools.lua, also /bnb debug), only
    -- while the dev addon is loaded; without it a second button gives the link.
    local devPage = K.NewSubPage(L["DEV_WIN_TITLE"], K.BuildDevToolsPage, "devtools")
    local devOpenBtn = BNB.CreateButton(nil, ct, L["CFG_DEV_OPEN_BTN"], 180, 24)
    devOpenBtn:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y + 2)
    devOpenBtn:SetScript("OnClick", devPage.Open)
    if not devMode then
        devOpenBtn:SetEnabled(false)
        devOpenBtn:SetMotionScriptsWhileDisabled(true)
        devOpenBtn:HookScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(L["CFG_DEV_OPEN_BTN"], 1, 1, 1)
            GameTooltip:AddLine(L["CFG_DEVADDON_NEEDS_ADDON_TIP"], 0.8, 0.8, 0.8, true)
            GameTooltip:Show()
        end)
        devOpenBtn:HookScript("OnLeave", function() GameTooltip:Hide() end)

        local getBtn = BNB.CreateButton(nil, ct, L["CFG_DEVADDON_GET_BTN"], 180, 24)
        getBtn:SetPoint("LEFT", devOpenBtn, "RIGHT", 8, 0)
        getBtn:SetScript("OnClick", function(self) BNB.ShowClipboardHint(BNB.DEVTOOL_URL, self, true, true) end)
        getBtn:HookScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(L["CFG_DEVADDON_GET_BTN"], 1, 1, 1)
            GameTooltip:AddLine(L["CFG_DEVADDON_GET_TIP"], 0.8, 0.8, 0.8, true)
            GameTooltip:AddLine(BNB.DEVTOOL_URL, 0.6, 0.6, 0.6)
            GameTooltip:Show()
        end)
        getBtn:HookScript("OnLeave", function() GameTooltip:Hide() end)
    end
    y = y - 34

    -- ── Danger Zone (last on the tab, Dukul 2026-09-26) ────────────────────────
    AddRule(ct, y); y = y - 18
    y = AddHeader(ct, y, L["CFG_DANGERZONE_TIP_TITLE"])

    local dzDesc = ct:CreateFontString(nil, "OVERLAY", "BNBFontNormalSmall")
    dzDesc:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
    dzDesc:SetWidth(CONTENT_W); dzDesc:SetJustifyH("LEFT"); dzDesc:SetWordWrap(true)
    dzDesc:SetTextColor(0.75, 0.40, 0.40)
    dzDesc:SetText(L["CFG_DANGERZONE_DESC"])
    local dzDescH = 32
    dzDesc:SetHeight(dzDescH)
    y = y - (dzDescH + 6)

    local dzBtn = BNB.CreateButton(nil, ct, L["CFG_DANGERZONE_BTN"], CONTENT_W, 28)
    dzBtn:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
    if dzBtn.SetBackdropColor then
        dzBtn:SetBackdropColor(0.25, 0.04, 0.04, 0.95)
        dzBtn:SetBackdropBorderColor(0.65, 0.10, 0.10, 1)
    end
    dzBtn:SetScript("OnEnter", function(self)
        if self.SetBackdropColor then self:SetBackdropColor(0.35, 0.06, 0.06, 0.95) end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(L["CFG_DANGERZONE_TIP_TITLE"], 1, 0.3, 0.3)
        GameTooltip:AddLine(L["CFG_DANGERZONE_TIP_BODY"], 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    dzBtn:SetScript("OnLeave", function(self)
        if self.SetBackdropColor then self:SetBackdropColor(0.25, 0.04, 0.04, 0.95) end
        GameTooltip:Hide()
    end)
    dzBtn:SetScript("OnClick", function()
        if BNB.DangerZone and BNB.DangerZone.Open then BNB.DangerZone.Open() end
    end)
    y = y - 34

    sf:FinaliseHeight(math.abs(y) + 20)
end

K.BUILDERS.advanced = BuildAdvancedTab

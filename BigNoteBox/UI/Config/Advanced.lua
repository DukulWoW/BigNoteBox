-- BigNoteBox UI/Config/Advanced.lua - Settings Advanced tab
-- Split out of ConfigWindow.lua (ALL-65.10).

local BNB = BigNoteBox
local L   = BNB.L

local K = BNB._ConfigKit
local CONTENT_W = K.CONTENT_W
local AddRule, AddHeader, AddCheck = K.AddRule, K.AddHeader, K.AddCheck

-- ── Addon integrations page (ALL-422) ───────────────────────────────────────
-- The addons BNB works with, one section each (Dukul, 2026-10-10): logo, name
-- and state centred, then what BNB does with it. The Advanced tab shows how
-- many are active and opens this page. A new addon is one more INTEG entry.
local ASSET = "Interface\\AddOns\\BigNoteBox\\Assets\\BCB\\"
-- addon = the folder name: a global like TomTom can come from another addon
-- (MapPinEnhanced makes one; a disabled TomTom showed as Active, Dukul
-- 2026-10-10). ready = loaded but too old to work with ("Needs update")
local INTEG = {
    { name = "BigChatBox", logo = "bcb-logo", desc = "CFG_INTEG_BCB_DESC",
      url = "https://www.curseforge.com/wow/addons/bigchatbox", addon = "BigChatBox" },
    { name = "TomTom", logo = "addon-tomtom", desc = "CFG_INTEG_TOMTOM_DESC",
      url = "https://www.curseforge.com/wow/addons/tomtom", addon = "TomTom" },
    { name = "WaypointUI", logo = "addon-waypointui", desc = "CFG_INTEG_WPUI_DESC",
      url = "https://www.curseforge.com/wow/addons/waypointui", addon = "WaypointUI", noClassic = true,
      descOther = "CFG_INTEG_WPUI_DESC_TOMTOM" },   -- off Retail: no MapPinEnhanced to name
    -- 3.x has no pin groups (ALL-421)
    { name = "MapPinEnhanced", logo = "addon-mpe", desc = "CFG_INTEG_MPE_DESC",
      url = "https://www.curseforge.com/wow/addons/mappinenhanced", addon = "MapPinEnhanced",
      ready = function() return BNB.HasMPEGroups() end, oldTip = "CFG_INTEG_MPE_UPDATE_TIP", noClassic = true, noForever = true },
}
-- noClassic / noForever: no build for that client (CurseForge, checked
-- 2026-10-10: WaypointUI is Retail + Forever, MapPinEnhanced Retail only), so
-- it is not listed there (ALL-430)
for i = #INTEG, 1, -1 do
    local a = INTEG[i]
    if (BNB.IsClassic and a.noClassic) or (BNB.IsForever and a.noForever) then table.remove(INTEG, i) end
end

-- 0 = not loaded, 1 = loaded but needs an update, 2 = active
local function IntegState(a)
    if not C_AddOns.IsAddOnLoaded(a.addon) then return 0 end
    if a.ready and not a.ready() then return 1 end
    return 2
end

local function BuildIntegrationsPage(sf, ct, y)
    local MID, LOGO = math.floor(CONTENT_W / 2), 64

    local intro = ct:CreateFontString(nil, "OVERLAY", "BNBFontNormal")
    intro:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
    intro:SetWidth(CONTENT_W); intro:SetJustifyH("LEFT"); intro:SetWordWrap(true)
    intro:SetTextColor(0.8, 0.8, 0.8)
    intro:SetText(L["CFG_INTEG_PAGE_INTRO"])
    y = y - math.ceil(intro:GetStringHeight()) - 12

    for _, a in ipairs(INTEG) do
        local state = IntegState(a)
        y = AddRule(ct, y) - 6

        local logo = ct:CreateTexture(nil, "ARTWORK")
        logo:SetSize(LOGO, LOGO)
        logo:SetPoint("TOP", ct, "TOPLEFT", MID, y)
        logo:SetTexture(ASSET .. a.logo)
        if state == 0 then logo:SetDesaturated(true); logo:SetAlpha(0.6) end
        y = y - LOGO - 4

        local nameLbl = ct:CreateFontString(nil, "OVERLAY", "BNBFontNormalLarge")
        nameLbl:SetPoint("TOP", ct, "TOPLEFT", MID, y)
        BNB.SetHeaderColor(nameLbl)
        nameLbl:SetText(a.name)
        y = y - 20

        if state > 0 then
            local st = ct:CreateFontString(nil, "OVERLAY", "BNBFontNormal")
            st:SetPoint("TOP", ct, "TOPLEFT", MID, y)
            st:SetText(state == 2 and ("|cff66bb6a" .. L["CFG_INTEG_ACTIVE"] .. "|r")
                or ("|cffffaa00" .. L["CFG_INTEG_NEEDS_UPDATE"] .. "|r"))
            y = y - 18
        end
        -- Not active, or too old: a button that copies the CurseForge link
        if state < 2 then
            local get = BNB.CreateButton(nil, ct, L["CFG_INTEG_GET_BTN"], 130, 22)
            get:SetPoint("TOP", ct, "TOPLEFT", MID, y)
            get:SetScript("OnClick", function(self) BNB.ShowClipboardHint(a.url, self, true, true) end)
            get:HookScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:AddLine(a.name, 1, 1, 1)
                GameTooltip:AddLine(L["CFG_INTEG_GET_TIP"], 0.8, 0.8, 0.8, true)
                GameTooltip:AddLine(a.url, 0.6, 0.6, 0.6)
                GameTooltip:Show()
            end)
            get:HookScript("OnLeave", function() GameTooltip:Hide() end)
            y = y - 28
        end
        y = y - 4

        local desc = ct:CreateFontString(nil, "OVERLAY", "BNBFontNormal")
        desc:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
        desc:SetWidth(CONTENT_W); desc:SetJustifyH("LEFT"); desc:SetWordWrap(true)
        desc:SetTextColor(0.8, 0.8, 0.8)
        desc:SetText(L[((BNB.IsForever or BNB.IsClassic) and a.descOther) or a.desc])
        y = y - math.ceil(desc:GetStringHeight()) - 6
        if state == 1 and a.oldTip then
            local why = ct:CreateFontString(nil, "OVERLAY", "BNBFontNormalSmall")
            why:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
            why:SetWidth(CONTENT_W); why:SetJustifyH("LEFT"); why:SetWordWrap(true)
            why:SetTextColor(1, 0.67, 0)
            why:SetText(L[a.oldTip])
            y = y - math.ceil(why:GetStringHeight()) - 6
        end
        y = y - 8
    end
    sf:FinaliseHeight(math.abs(y) + 20)
end

-- ─────────────────────────────────────────────────────────────────────────────
-- TAB 4 — ADVANCED
-- ─────────────────────────────────────────────────────────────────────────────
local function BuildAdvancedTab(sf, ct)
    local db = BigNoteBoxDB
    local y  = -8

    -- ── Addon integrations (ALL-315), first on the tab (Dukul, 2026-10-10):
    -- how many are active, and a button to the page that lists them (ALL-422)
    y = AddHeader(ct, y, L["CFG_HDR_INTEGRATIONS"])
    do
        local page = K.NewSubPage(L["CFG_HDR_INTEGRATIONS"], BuildIntegrationsPage, "integrations")
        local active = 0
        for _, a in ipairs(INTEG) do
            if IntegState(a) == 2 then active = active + 1 end
        end
        local cnt = ct:CreateFontString(nil, "OVERLAY", "BNBFontNormal")
        cnt:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
        cnt:SetTextColor(0.8, 0.8, 0.8)
        cnt:SetText(string.format(L["CFG_INTEG_COUNT_FMT"], active, #INTEG))
        y = y - 22
        local open = BNB.CreateButton(nil, ct, L["CFG_INTEG_OPEN_BTN"], 180, 24)
        open:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y + 2)
        open:SetScript("OnClick", page.Open)
        y = y - 34
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

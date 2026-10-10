-- BigNoteBox UI/Config/General.lua - Settings General tab
-- Split out of ConfigWindow.lua (ALL-65.10).

local BNB = BigNoteBox
local L   = BNB.L

local K = BNB._ConfigKit
local CONTENT_W, ASSET, ROW_H, ROW_GAP = K.CONTENT_W, K.ASSET, K.ROW_H, K.ROW_GAP
local AddRule, AddHeader, AddCheck, MakeKeybindPair = K.AddRule, K.AddHeader, K.AddCheck, K.MakeKeybindPair

-- ─────────────────────────────────────────────────────────────────────────────
-- TAB 1 — GENERAL
-- Logo, version, by-line, Language + More Features, Window, Keybindings, solidarity line
-- ─────────────────────────────────────────────────────────────────────────────
local function BuildGeneralTab(sf, ct)
    local y = -8

    -- ── Header row: logo left, identity stacked beside it, pack-status icons
    -- (installed/missing font & icon packs, ALL-14) on the right.
    local HEADER_H  = 64
    local LOGO_SZ   = 56
    local TEXT_X    = LOGO_SZ + 10

    local logo = ct:CreateTexture(nil, "ARTWORK")
    logo:SetSize(LOGO_SZ, LOGO_SZ)
    logo:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
    logo:SetTexture(ASSET .. "logo")

    -- Title
    local title = ct:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge3")
    title:SetPoint("TOPLEFT", ct, "TOPLEFT", TEXT_X, y - 2)
    title:SetJustifyH("LEFT")
    title:SetText("|cff66bb6a" .. L["ADDON_NAME"] .. "|r")

    -- Version button — skin button style on both modes so it reads as clickable.
    -- Opens the What's New window without the overlay.
    local verText = "v" .. (BNB.ADDON_VERSION or "1.0.0")
    local ver = BNB.CreateButton(nil, ct, verText, 80, 20)
    ver:SetPoint("TOPLEFT", ct, "TOPLEFT", TEXT_X, y - 30)
    ver:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetText(L["WHATS_NEW_VERSION_TIP"], nil, nil, nil, nil, true)
        GameTooltip:Show()
    end)
    ver:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    ver:SetScript("OnClick", function()
        if BNB.WhatsNew and BNB.WhatsNew.Open then
            BNB.WhatsNew.Open(false)
        end
    end)

    -- By-line: a button that copies the link to dukul.net (Dukul, 2026-10-08)
    local byBtn = BNB.CreateButton(nil, ct, L["AUTHOR"], 90, 20)
    byBtn:SetPoint("LEFT", ver, "RIGHT", 8, 0)
    local byFs = byBtn:GetFontString() or byBtn._lbl
    if byFs and byFs.GetStringWidth then
        byBtn:SetWidth(math.max(90, math.ceil(byFs:GetStringWidth()) + 24))
    end
    byBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetText(L["CFG_AUTHOR_TIP"], nil, nil, nil, nil, true)
        GameTooltip:Show()
    end)
    byBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    byBtn:SetScript("OnClick", function(self)
        BNB.ShowClipboardHint("https://dukul.net", self, true, true)
    end)

    -- ── Pack status icons (ALL-14), right side of the header, right to left.
    -- Installed: full colour, tooltip "Installed, vX.Y.Z", no click. Missing: grey,
    -- click copies the download link. Tooltips are in the pack's own language.
    do
        local PACK_SZ, PACK_GAP = 32, 6
        local n = 0
        for _, pack in ipairs(BNB.KNOWN_PACKS or {}) do
            if BNB.IsPackRelevant(pack) then
                local installed, ver = BNB.GetPackStatus(pack)
                local b = CreateFrame("Button", nil, ct)
                b:SetSize(PACK_SZ, PACK_SZ)
                b:SetPoint("TOPRIGHT", ct, "TOPRIGHT", -n * (PACK_SZ + PACK_GAP), y - 4)
                local tex = b:CreateTexture(nil, "ARTWORK")
                tex:SetAllPoints()
                tex:SetTexture(pack.icon)
                if pack.iconCrop then tex:SetTexCoord(0.08, 0.92, 0.08, 0.92) end
                if not installed then
                    tex:SetDesaturated(true); tex:SetAlpha(0.55)
                    local hl = b:CreateTexture(nil, "HIGHLIGHT")
                    hl:SetAllPoints(); hl:SetColorTexture(1, 1, 1, 0.15)
                    b:SetScript("OnClick", function(self)
                        if BNB.ShowClipboardHint then BNB.ShowClipboardHint(pack.url, self, true, true) end
                    end)
                end
                b:SetScript("OnEnter", function(self)
                    GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT")
                    GameTooltip:SetText(pack.tipTitle, 1, 0.82, 0)
                    if installed then
                        GameTooltip:AddLine(string.format(pack.tipInstalled, ver or "?"), 0.4, 0.8, 0.4)
                    else
                        GameTooltip:AddLine(pack.tipMissing, 0.9, 0.9, 0.9, true)
                        GameTooltip:AddLine(pack.tipClick, 0.6, 0.6, 0.6, true)
                    end
                    GameTooltip:Show()
                end)
                b:SetScript("OnLeave", function() GameTooltip:Hide() end)
                n = n + 1
            end
        end
    end

    y = y - HEADER_H

    -- ── Language section (ALL-14) — Retail and Forever, mirrors BigChatBox's selector ──
    -- Text and dropdown in the left column, More Features right of it (ALL-315)
    local langTopY
    local LANG_W = math.floor((CONTENT_W - 12) / 2)
    if not BNB.IsClassic then   -- Classic TOCs lack BigNoteBoxLocale (ALL-168); Forever has it (FOR-32)
        y = AddRule(ct, y) - 4
        langTopY = y
        y = AddHeader(ct, y, L["CFG_HDR_LANGUAGE"])

        local langDesc = ct:CreateFontString(nil, "OVERLAY", "BNBFontNormalSmall")
        langDesc:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
        langDesc:SetWidth(LANG_W); langDesc:SetJustifyH("LEFT")
        langDesc:SetTextColor(0.7, 0.7, 0.7)
        langDesc:SetWordWrap(true)
        langDesc:SetText(L["CFG_LANGUAGE_DESC"])
        -- Half width now: the text can take two lines
        y = y - math.max(18, math.ceil(langDesc:GetStringHeight()) + 6)

        local FLAG = ASSET .. "Flags\\"
        -- { code, label, flag, available }  available=false -> greyed "(Coming soon)"
        local LANG_LIST = {
            { code = "client", label = L["LANGUAGE_CLIENT"], flag = nil,               available = true  },
            { code = "enUS",   label = "English",            flag = FLAG.."flag-en",   available = true  },
            { code = "zhCN",   label = "简体中文",             flag = FLAG.."flag-cn",   available = true  },
            { code = "deDE",   label = "Deutsch",             flag = FLAG.."flag-de",   available = false },
            { code = "frFR",   label = "Français",            flag = FLAG.."flag-fr",   available = false },
            { code = "esES",   label = "Español",             flag = FLAG.."flag-es",   available = false },
            { code = "ptBR",   label = "Português",           flag = FLAG.."flag-br",   available = false },
            { code = "itIT",   label = "Italiano",            flag = FLAG.."flag-it",   available = false },
            { code = "jaJP",   label = "日本語",               flag = FLAG.."flag-ja",   available = false },
            { code = "koKR",   label = "한국어",               flag = FLAG.."flag-ko",   available = false },
            { code = "zhTW",   label = "繁體中文",             flag = FLAG.."flag-tw",   available = false },
        }

        local COMING_SOON = L["LANGUAGE_COMING_SOON"]
        local GREY        = "|cff888888"

        -- entry.label for "client" is L["LANGUAGE_CLIENT"], already translated into whatever
        -- language is active -- so on a forced-Chinese UI it reads "客户端语言" alone, with no
        -- clue that it means "Client Language" (Dukul, 2026-09-23, after seeing that on an
        -- English client with Chinese selected). Always show the hardcoded English name too,
        -- whenever the ACTIVE language isn't English -- forced or natural, doesn't matter.
        local MakeLangLabel = BNB.MakeLangLabel

        local curLangCode = (BigNoteBoxLocale and BigNoteBoxLocale ~= "") and BigNoteBoxLocale or "client"

        local langDD = BNB.SkinDropdown(CreateFrame("DropdownButton", nil, ct, "WowStyle1DropdownTemplate"))
        langDD:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
        langDD:SetWidth(LANG_W)
        langDD:SetupMenu(function(_, root)
            for _, entry in ipairs(LANG_LIST) do
                local lbl = MakeLangLabel(entry)
                if entry.available then
                    root:CreateRadio(lbl,
                        function() return curLangCode == entry.code end,
                        function()
                            if entry.code == curLangCode then return end
                            BNB._pendingLangCode = entry.code
                            StaticPopup_Show("BNB_CHANGE_LANGUAGE")
                        end)
                else
                    local greyLbl = GREY .. (entry.flag and ("|T" .. entry.flag .. ":14:20:0:0:32:32|t ") or "")
                        .. entry.label .. "|r  " .. COMING_SOON
                    local dummy = root:CreateRadio(greyLbl, function() return false end, function() end)
                    dummy:AddInitializer(function(button)
                        if button.fontString then button.fontString:SetTextColor(0.5, 0.5, 0.5) end
                        button:SetEnabled(false)
                        if button.highlight then button.highlight:SetAlpha(0) end
                    end)
                end
            end
            root:SetScrollMode(30 * 20)
        end)
        y = y - 32
        y = y - 6
    end

    if not StaticPopupDialogs["BNB_CHANGE_LANGUAGE"] then
        StaticPopupDialogs["BNB_CHANGE_LANGUAGE"] = {
            text = L["CFG_LANG_RELOAD_CONFIRM"],
            button1 = L["CFG_RELOAD_NOW_BTN"],
            button2 = L["CFG_LATER_BTN"],
            timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
            OnAccept = function()
                BigNoteBoxLocale = (BNB._pendingLangCode == "client") and nil or BNB._pendingLangCode
                BNB._pendingLangCode = nil
                C_UI.Reload()
            end,
            OnCancel = function() BNB._pendingLangCode = nil end,
        }
    end

    -- More Features: a normal-height button right of the Language text (the
    -- BCB box went to Advanced > Addon integrations, ALL-315); without the
    -- Language section (Forever, Classic) on a row of its own. The four feature
    -- boxes that used to sit here went when the Modules tab arrived (Dukul,
    -- 2026-09-26).
    local moreBtn = BNB.CreateButton(nil, ct, L["CFG_MORE_FEATURES_BTN"], 160, 26)
    local moreFs = moreBtn:GetFontString() or moreBtn._lbl
    if moreFs and moreFs.GetStringWidth then
        moreBtn:SetWidth(math.max(160, math.ceil(moreFs:GetStringWidth()) + 40))
    end
    -- Under it, a button per download site that copies its link (ALL-431)
    local LINK_SZ, LINK_GAP = 28, 6
    local LINKS_H = 6 + LINK_SZ
    if langTopY then
        -- More Features + the links centred on the Language section, header to dropdown
        moreBtn:SetPoint("RIGHT", ct, "TOPRIGHT", 0, math.floor((langTopY + y) / 2) + math.floor(LINKS_H / 2))
    else
        y = AddRule(ct, y) - 4
        moreBtn:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
        y = y - 26 - LINKS_H - 10
    end
    do
        local SITES = BNB.SITE_LINKS
        local rowW = #SITES * LINK_SZ + (#SITES - 1) * LINK_GAP
        for i, site in ipairs(SITES) do
            local url = site.url
            local b = BNB.CreateIconButton(ct, LINK_SZ, site.key, {
                tip = site.name, tipSub = string.format(L["CFG_SITE_LINK_TIP"], site.name), tipWrap = true,
                onClick = function(self) BNB.ShowClipboardHint(url, self, true, true) end,
            })
            b:SetPoint("TOPLEFT", moreBtn, "BOTTOM", -math.floor(rowW / 2) + (i - 1) * (LINK_SZ + LINK_GAP), -6)
        end
    end
    moreBtn:SetScript("OnClick", function()
        if BNB.FeatureList then BNB.FeatureList.Open() end
    end)
    moreBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(L["CFG_FEATURES_TIP_TITLE"], 1, 0.82, 0)
        GameTooltip:AddLine(L["CFG_FEATURES_TIP_BODY"], 0.78, 0.78, 0.78)
        GameTooltip:Show()
    end)
    moreBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- ── Window (moved from the Features tab, ALL-84) ───────────────────────────
    local db = BigNoteBoxDB
    y = AddRule(ct, y) - 4
    y = AddHeader(ct, y, L["CFG_HDR_WINDOW"])

    y = AddCheck(ct, y, L["CFG_CHK_OPEN_LOGIN_LABEL"],
        function() return db.openOnLogin == true end,
        function(v) db.openOnLogin = v end,
        L["CFG_CHK_OPEN_LOGIN_TIP"])

    -- The two "reset main window placement on load" checkboxes live only on
    -- Modules > Window placement (ALL-270, moved there by Dukul 2026-10-06)

    y = AddCheck(ct, y, L["CFG_CHK_CONFIRM_CLOSE_LABEL"],
        function() return db.confirmClose == true end,
        function(v) db.confirmClose = v end,
        L["CFG_CHK_CONFIRM_CLOSE_TIP"])

    -- Combat action dropdown
    do
        local combatLbl = ct:CreateFontString(nil, "OVERLAY", "BNBFontNormal")
        combatLbl:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
        combatLbl:SetHeight(ROW_H); combatLbl:SetJustifyH("LEFT")
        combatLbl:SetText(L["CFG_COMBAT_LABEL"])
        y = y - (ROW_H + 2)

        local COMBAT_ITEMS = {
            { key = "nothing",            label = L["CFG_COMBAT_ITEM_NOTHING"] },
            { key = "hide_no_stickies",   label = L["CFG_COMBAT_ITEM_HIDE_EXCEPT_STICKY"] },
            { key = "hide_minimize",      label = L["CFG_COMBAT_ITEM_HIDE_MINIMIZE"] },
            { key = "hide_all",           label = L["CFG_COMBAT_ITEM_HIDE_ALL"] },
        }
        local curCombat = db.combatAction or BNB.DEFAULTS.combatAction
        local combatDD = BNB.SkinDropdown(CreateFrame("DropdownButton", nil, ct, "WowStyle1DropdownTemplate"))
        combatDD:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
        combatDD:SetWidth(CONTENT_W)
        combatDD:SetupMenu(function(_, root)
            for _, item in ipairs(COMBAT_ITEMS) do
                root:CreateRadio(item.label,
                    function() return curCombat == item.key end,
                    function()
                        curCombat = item.key
                        db.combatAction = item.key
                        combatDD:GenerateMenu()
                    end)
            end
        end)
        combatDD:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(L["CFG_COMBAT_LABEL"], 1, 1, 1)
            GameTooltip:AddLine(L["CFG_COMBAT_NOTHING"], 0.8, 0.8, 0.8, true)
            GameTooltip:AddLine(L["CFG_COMBAT_HIDE_EXCEPT_STICKY"], 0.8, 0.8, 0.8, true)
            GameTooltip:AddLine(L["CFG_COMBAT_HIDE_MINIMIZE"], 0.8, 0.8, 0.8, true)
            GameTooltip:AddLine(L["CFG_COMBAT_HIDE_ALL"], 0.8, 0.8, 0.8, true)
            GameTooltip:AddLine(L["CFG_COMBAT_REOPEN"], 0.8, 0.8, 0.8, true)
            GameTooltip:Show()
        end)
        combatDD:SetScript("OnLeave", function() GameTooltip:Hide() end)
        y = y - (32 + ROW_GAP)
    end

    -- ── Keybindings section ───────────────────────────────────────────────────
    y = AddRule(ct, y) - 4
    y = AddHeader(ct, y, L["CFG_HDR_KEYBINDINGS"])

    -- Two per row, label above button (ALL-69): the default key is in the tooltip.
    y = MakeKeybindPair(ct, y, {
        { label = L["CFG_KB_DESC_OPEN_BNB"], action = "BIGNOTEBOXOPEN",
          defaultKey = "CTRL-N", verb = L["CFG_KB_DESC_OPEN_BNB"] },
        { label = L["CFG_KB_ORACLE"], action = "BIGNOTEBOXORACLE",
          defaultKey = "CTRL-SPACE", verb = L["CFG_KB_DESC_ORACLE"] },
    })

    -- Data Summary moved to the bottom of the Backup tab (ALL-14).

    -- Content ends here. Solidarity line + rule go at the very bottom of the
    -- scroll area, anchored to the BOTTOM of the content frame so they stay
    -- at the foot of the scrollable region regardless of window height.
    local SOL_H = 36   -- rule(1) + gap(8) + text(~18) + padding

    -- Finalise the scroll height based on the content above
    local contentH = math.abs(y) + SOL_H + 12
    sf:FinaliseHeight(contentH)

    -- Now anchor solidarity items to the BOTTOM of the content frame
    local rule = ct:CreateTexture(nil, "ARTWORK")
    rule:SetHeight(1)
    if BigNoteBoxDB and BigNoteBoxDB.skinMode and BNB.GetSkinPreset then
        local p = BNB.GetSkinPreset()
        local br, bg_, bb = BNB.SkinRuleOf(p)
        rule:SetColorTexture(br, bg_, bb, 0.9)
        if BNB.RegisterSkinRule then BNB.RegisterSkinRule(rule, 0.9) end
    else
        rule:SetColorTexture(0.25, 0.25, 0.28, 1)
    end
    rule:SetPoint("BOTTOMLEFT",  ct, "BOTTOMLEFT",  0, SOL_H - 1)
    rule:SetPoint("BOTTOMRIGHT", ct, "BOTTOMRIGHT", 0, SOL_H - 1)

    local sol = ct:CreateFontString(nil, "ARTWORK", "BNBFontHighlightSmall")
    sol:SetPoint("BOTTOM", ct, "BOTTOM", 0, 8)
    sol:SetWidth(CONTENT_W); sol:SetJustifyH("CENTER")
    sol:SetTextColor(0.85, 0.85, 0.85)
    sol:SetText(
        "LGBTQIA+ |T" .. ASSET .. "Flags\\flag-pride:14:20|t Pride  \226\128\148" ..
        "  Trans |T" .. ASSET .. "Flags\\flag-trans:14:20|t Rights  \226\128\148" ..
        "  Slava |T" .. ASSET .. "Flags\\flag-ua:14:20|t Ukraini  \226\128\148" ..
        "  Free |T" .. ASSET .. "Flags\\flag-ps:14:20|t Palestine"
    )
end

K.BUILDERS.general = BuildGeneralTab

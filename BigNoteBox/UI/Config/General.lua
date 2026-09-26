-- BigNoteBox UI/Config/General.lua - Settings General tab
-- Split out of ConfigWindow.lua (ALL-65.10).

local BNB = BigNoteBox
local L   = BNB.L

local K = BNB._ConfigKit
local CONTENT_W, ASSET, ROW_H, ROW_GAP = K.CONTENT_W, K.ASSET, K.ROW_H, K.ROW_GAP
local AddRule, AddHeader, AddCheck, MakeKeybindRow = K.AddRule, K.AddHeader, K.AddCheck, K.MakeKeybindRow

-- ─────────────────────────────────────────────────────────────────────────────
-- TAB 1 — GENERAL
-- Logo, version, by-line, Language, BCB box + More Features, Window, Keybindings, solidarity line
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

    -- By-line
    local byLine = ct:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    byLine:SetPoint("LEFT", ver, "RIGHT", 8, 0)
    byLine:SetText(L["AUTHOR"])
    byLine:SetTextColor(0.55, 0.55, 0.55)

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
                tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                if not installed then
                    tex:SetDesaturated(true); tex:SetAlpha(0.55)
                    local hl = b:CreateTexture(nil, "HIGHLIGHT")
                    hl:SetAllPoints(); hl:SetColorTexture(1, 1, 1, 0.15)
                    b:SetScript("OnClick", function(self)
                        if BNB.ShowClipboardHint then BNB.ShowClipboardHint(pack.url, self, true) end
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

    -- ── Language section (ALL-14) — retail only, mirrors BigChatBox's selector ──
    if not BNB.IsForever then
        y = AddRule(ct, y) - 4
        y = AddHeader(ct, y, L["CFG_HDR_LANGUAGE"])

        local langDesc = ct:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        langDesc:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
        langDesc:SetWidth(CONTENT_W); langDesc:SetJustifyH("LEFT")
        langDesc:SetTextColor(0.7, 0.7, 0.7)
        langDesc:SetText(L["CFG_LANGUAGE_DESC"])
        y = y - 18

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

        local useNativeLangDrop = C_XMLUtil and C_XMLUtil.GetTemplateInfo
            and C_XMLUtil.GetTemplateInfo("WowStyle1DropdownTemplate")

        if useNativeLangDrop then
            local langDD = CreateFrame("DropdownButton", nil, ct, "WowStyle1DropdownTemplate")
            langDD:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
            langDD:SetWidth(CONTENT_W)
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
        else
            -- Fallback: only the available entries, as plain stacked buttons.
            for _, entry in ipairs(LANG_LIST) do
                if entry.available then
                    local lb = BNB.CreateButton(nil, ct, MakeLangLabel(entry), CONTENT_W, 22)
                    lb:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
                    lb:SetScript("OnClick", function()
                        if entry.code == curLangCode then return end
                        BNB._pendingLangCode = entry.code
                        StaticPopup_Show("BNB_CHANGE_LANGUAGE")
                    end)
                    y = y - 26
                end
            end
        end
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

    -- BCB box + More Features button, one row, ruled off from Language (or the
    -- header on Forever) like the sections below it. The four feature boxes
    -- that used to sit here went when the Modules tab arrived: it lists the
    -- same features, and they pushed General into scrolling (Dukul, 2026-09-26).
    y = AddRule(ct, y) - 4
    local rowY = y
    local h3
    local cellGap = 12
    local cellW   = math.floor((CONTENT_W - cellGap) / 2)
    local cellX2  = cellW + cellGap

    local function Cell(xOff, yOff, hdr, desc)
        local h = ct:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        h:SetPoint("TOPLEFT", ct, "TOPLEFT", xOff, yOff)
        h:SetWidth(cellW); h:SetJustifyH("LEFT")
        h:SetTextColor(1, 0.82, 0, 1); h:SetText(hdr)

        local d = ct:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
        d:SetPoint("TOPLEFT", ct, "TOPLEFT", xOff, yOff - 18)
        d:SetWidth(cellW); d:SetJustifyH("LEFT")
        d:SetWordWrap(true); d:SetSpacing(2)
        d:SetTextColor(0.75, 0.75, 0.75); d:SetText(desc)
        return d:GetStringHeight() + 22
    end

    local bcbLabel = L["CFG_BCB_HEADER"]
    if BigChatBox and BigChatBox.SendDirect then
        bcbLabel = bcbLabel .. " |cff66bb6a(INSTALLED)|r"
        h3 = Cell(0, y, bcbLabel, L["CFG_BCB_DESC"])
    else
        -- BCB not installed: draw the header manually so we can add a clickable badge
        local hdr = ct:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        hdr:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
        hdr:SetWidth(cellW); hdr:SetJustifyH("LEFT")
        hdr:SetTextColor(1, 0.82, 0, 1); hdr:SetText(bcbLabel)

        -- (NOT INSTALLED) button — small, blue, sits right of the header text
        local notInstBtn = CreateFrame("Button", nil, ct)
        notInstBtn:SetSize(96, 16)
        notInstBtn:SetPoint("LEFT", hdr, "LEFT", hdr:GetStringWidth() + 6, 0)
        local notInstLbl = notInstBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        notInstLbl:SetAllPoints()
        notInstLbl:SetJustifyH("LEFT")
        notInstLbl:SetText("|cff4fc3f7" .. L["CFG_NOT_INSTALLED"] .. "|r")
        notInstBtn:SetScript("OnClick", function()
            if BNB.ShowBCBPromo then BNB.ShowBCBPromo() end
        end)
        notInstBtn:SetScript("OnEnter", function(self)
            notInstLbl:SetText("|cff81d4fa" .. L["CFG_NOT_INSTALLED"] .. "|r")
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:AddLine(L["CFG_BCB_TIP_TITLE"], 1, 1, 1)
            GameTooltip:AddLine(L["CFG_BCB_TIP_BODY"], 0.78, 0.78, 0.78)
            GameTooltip:Show()
        end)
        notInstBtn:SetScript("OnLeave", function()
            notInstLbl:SetText("|cff4fc3f7" .. L["CFG_NOT_INSTALLED"] .. "|r")
            GameTooltip:Hide()
        end)

        local desc3 = ct:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
        desc3:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y - 18)
        desc3:SetWidth(cellW); desc3:SetJustifyH("LEFT")
        desc3:SetWordWrap(true); desc3:SetSpacing(2)
        desc3:SetTextColor(0.75, 0.75, 0.75)
        desc3:SetText(L["CFG_BCB_DESC"])
        h3 = desc3:GetStringHeight() + 22
    end

    -- More Features button (right of the BCB box)
    -- The button matches the height of the left cell. Since GetStringHeight()
    -- returns 0 at build time, we use a deferred resize via C_Timer.After(0).
    -- More Features button — same template trychain as OptionsPanel and WhatsNew OK button
    local moreTpl = "SharedButtonLargeTemplate"
    if not (C_XMLUtil and C_XMLUtil.GetTemplateInfo and C_XMLUtil.GetTemplateInfo(moreTpl)) then
        moreTpl = "UIPanelDynamicResizeButtonTemplate"
    end
    if not (C_XMLUtil and C_XMLUtil.GetTemplateInfo and C_XMLUtil.GetTemplateInfo(moreTpl)) then
        moreTpl = "UIPanelButtonTemplate"
    end
    local moreBtn
    if BigNoteBoxDB and BigNoteBoxDB.skinMode then
        moreBtn = BNB.CreateSkinButton(nil, ct, L["CFG_MORE_FEATURES_BTN"], cellW, 38)
    else
        moreBtn = CreateFrame("Button", nil, ct, moreTpl)
        moreBtn:SetWidth(cellW)
        pcall(function() DynamicResizeButton_Resize(moreBtn) end)
        moreBtn:SetText(L["CFG_MORE_FEATURES_BTN"])
    end
    moreBtn:SetPoint("TOPLEFT", ct, "TOPLEFT", cellX2, rowY)
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

    -- In skin mode, defer height match to the left cell after layout resolves.
    -- In normal mode the template height is natural and should not be overridden.
    if BigNoteBoxDB and BigNoteBoxDB.skinMode then
        C_Timer.After(0, function()
            if not ct or not moreBtn then return end
            local targetH = math.max(h3, 38)
            moreBtn:SetHeight(targetH)
        end)
    end

    y = rowY - math.max(h3, 38) - 10

    -- ── Window (moved from the Features tab, ALL-84) ───────────────────────────
    local db = BigNoteBoxDB
    y = AddRule(ct, y) - 4
    y = AddHeader(ct, y, L["CFG_HDR_WINDOW"])

    y = AddCheck(ct, y, L["CFG_CHK_OPEN_LOGIN_LABEL"],
        function() return db.openOnLogin == true end,
        function(v) db.openOnLogin = v end,
        L["CFG_CHK_OPEN_LOGIN_TIP"])

    y = AddCheck(ct, y, L["CFG_CHK_CONFIRM_CLOSE_LABEL"],
        function() return db.confirmClose == true end,
        function(v) db.confirmClose = v end,
        L["CFG_CHK_CONFIRM_CLOSE_TIP"])

    -- Combat action dropdown
    do
        local combatLbl = ct:CreateFontString(nil, "OVERLAY", "GameFontNormal")
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
        local curCombat = db.combatAction or "nothing"
        local combatDD = CreateFrame("DropdownButton", nil, ct, "WowStyle1DropdownTemplate")
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

    y = MakeKeybindRow(ct, y, L["CFG_KB_OPEN_BNB"], "BIGNOTEBOXOPEN", L["CFG_KB_HINT_CTRL_N"], L["CFG_KB_DESC_OPEN_BNB"])

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
        local br, bg_, bb = BNB.SkinBorderOf(p)
        rule:SetColorTexture(br, bg_, bb, 0.9)
        if BNB.RegisterSkinRule then BNB.RegisterSkinRule(rule, 0.9) end
    else
        rule:SetColorTexture(0.25, 0.25, 0.28, 1)
    end
    rule:SetPoint("BOTTOMLEFT",  ct, "BOTTOMLEFT",  0, SOL_H - 1)
    rule:SetPoint("BOTTOMRIGHT", ct, "BOTTOMRIGHT", 0, SOL_H - 1)

    local sol = ct:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
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

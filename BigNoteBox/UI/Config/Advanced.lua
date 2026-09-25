-- BigNoteBox UI/Config/Advanced.lua - Settings Advanced tab
-- Split out of ConfigWindow.lua (ALL-65.10).

local BNB = BigNoteBox
local L   = BNB.L

local K = BNB._ConfigKit
local CONTENT_W, ROW_H, ROW_GAP = K.CONTENT_W, K.ROW_H, K.ROW_GAP
local AddRule, AddHeader, AddCheck, MakeKeybindRow = K.AddRule, K.AddHeader, K.AddCheck, K.MakeKeybindRow

-- ─────────────────────────────────────────────────────────────────────────────
-- TAB 4 — ADVANCED
-- ─────────────────────────────────────────────────────────────────────────────
local function BuildAdvancedTab(sf, ct)
    local db = BigNoteBoxDB
    local y  = -8

    y = AddHeader(ct, y, L["CFG_HDR_BEHAVIOR"])

    y = AddCheck(ct, y, L["CONFIG_SHOW_MINIMAP"],
        function() return not (db.minimapIcon and db.minimapIcon.hide) end,
        function(v) BNB.SetMinimapButtonShown(v) end,
        "Show the BigNoteBox button on the minimap.")

    y = AddCheck(ct, y, L["CONFIG_HIDE_LOGIN_MSG"],
        function() return db.hideLoginMessage == true end,
        function(v) db.hideLoginMessage = v end,
        "Suppress the \"BigNoteBox v... loaded\" chat message on login.")

    AddRule(ct, y); y = y - 18
    y = AddHeader(ct, y, L["CFG_HDR_ICONS"])

    y = AddCheck(ct, y, L["CFG_CHK_BLZICON_LABEL"],
        function() return db.blizzardIconComplete == true end,
        function(v)
            db.blizzardIconComplete = v
            if v then
                -- Enable: load BigNoteBox_Icons now so the autocomplete works
                -- without a reload; says in chat why if it cannot (ALL-62).
                if BNB.InitBlizzardIconList then BNB.InitBlizzardIconList(true) end
            else
                -- Disable: stop using the list at once. It stays in memory
                -- until a reload, which unloads BigNoteBox_Icons.
                BNB.BlizzardIconList = nil
                StaticPopup_Show("BNB_BLZICON_AC_DISABLE")
            end
        end,
        L["CFG_CHK_BLZICON_TIP"])

    -- ── Migrate section (only shown if any supported addon is installed) ─────────
    if BNB.Migration and BNB.Migration.HasAny() then
        AddRule(ct, y); y = y - 18
        y = AddHeader(ct, y, L["CFG_HDR_MIGRATE"])

        local migDesc = ct:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        migDesc:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
        migDesc:SetWidth(CONTENT_W); migDesc:SetJustifyH("LEFT")
        migDesc:SetWordWrap(true)
        migDesc:SetTextColor(0.60, 0.60, 0.60)
        migDesc:SetText(L["CFG_IMPORT_DESC"])
        y = y - 36

        -- Use the Migration module's own key/name tables so this list stays
        -- in sync automatically whenever new addons are added to MigrateNotes.lua.
        local M = BNB.Migration
        for _, k in ipairs(M.ADDON_KEYS) do
            if M.IsAddonAvailable(k) then
                local displayName = M.ADDON_NAMES[k] or k
                local isDone = db.migrationDone and db.migrationDone[k]

                -- Row: label + status badge + button
                local rowLbl = ct:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                rowLbl:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
                rowLbl:SetText(displayName)

                local statusLbl = ct:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                statusLbl:SetPoint("LEFT", rowLbl, "RIGHT", 8, 0)
                if isDone then
                    statusLbl:SetText("|cff66bb6a" .. L["CFG_DONE_BADGE"] .. "|r")
                else
                    statusLbl:SetText("|cff888888" .. L["CFG_NOT_YET_BADGE"] .. "|r")
                end

                local migrateRowBtn = BNB.CreateButton(nil, ct, isDone and L["CFG_MIGRATE_AGAIN_BTN"] or L["CFG_MIGRATE_BTN"], 110, 22)
                migrateRowBtn:SetPoint("TOPRIGHT", ct, "TOPRIGHT", 0, y)
                migrateRowBtn:SetScript("OnClick", function()
                    if M.ShowAddonPopup then
                        M.ShowAddonPopup(k)
                    end
                end)

                y = y - (ROW_H + ROW_GAP)
            end
        end
    end

    -- ── Fonts section ───────────────────────────────────────────────────────────
    AddRule(ct, y); y = y - 18
    y = AddHeader(ct, y, L["CFG_HDR_FONTS"])

    local lsmAvail = LibStub and LibStub("LibSharedMedia-3.0", true) ~= nil
    if lsmAvail then
        local lsmWasOn = db.lsmFonts == true
        local lsmReloadLbl  -- shown after toggle
        y = AddCheck(ct, y, L["CFG_LSM_FONTS"],
            function() return db.lsmFonts == true end,
            function(v)
                db.lsmFonts = v
                if lsmReloadLbl then lsmReloadLbl:SetShown(v ~= lsmWasOn) end
            end,
            L["CFG_LSM_FONTS_TIP"])

        -- Inline "Reload required" label + button, hidden until the value changes
        lsmReloadLbl = ct:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        lsmReloadLbl:SetPoint("TOPLEFT", ct, "TOPLEFT", 22, y + 2)
        lsmReloadLbl:SetTextColor(1, 0.82, 0, 1)
        lsmReloadLbl:SetText(L["CFG_LSM_FONTS_RELOAD"])
        lsmReloadLbl:Hide()

        local lsmReloadBtn = BNB.CreateButton(nil, ct, L["CFG_RELOAD_UI_BTN"], 90, 20)
        lsmReloadBtn:SetPoint("LEFT", lsmReloadLbl, "RIGHT", 8, 0)
        lsmReloadBtn:SetScript("OnClick", function()
            C_UI.Reload()
        end)
        lsmReloadBtn:Hide()

        -- Wire both to show together
        hooksecurefunc(lsmReloadLbl, "SetShown", function(_, shown)
            lsmReloadBtn:SetShown(shown)
        end)

        y = y - 26
    else
        -- LSM not present: show a greyed notice so the user knows why there's no checkbox
        local lsmMissingLbl = ct:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        lsmMissingLbl:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
        lsmMissingLbl:SetWidth(CONTENT_W)
        lsmMissingLbl:SetJustifyH("LEFT")
        lsmMissingLbl:SetTextColor(0.45, 0.45, 0.45)
        lsmMissingLbl:SetText(L["CFG_LSM_FONTS_MISSING"] .. " -- install an addon that provides LibSharedMedia-3.0 to enable this option.")
        y = y - 28
    end

    -- ── Keybindings section ───────────────────────────────────────────────────
    AddRule(ct, y); y = y - 18
    y = AddHeader(ct, y, L["CFG_HDR_KEYBINDINGS"])

    y = MakeKeybindRow(ct, y, L["CFG_KB_NEW_NOTE"],
        "BIGNOTEBOXNEWNOTE",   L["CFG_KB_HINT_UNBOUND"], L["CFG_KB_DESC_NEW_NOTE"])
    y = MakeKeybindRow(ct, y, L["CFG_KB_QUICK_NOTE"],
        "BIGNOTEBOXQUICKNOTE", L["CFG_KB_HINT_UNBOUND"], L["CFG_KB_DESC_QUICK_NOTE"])

    -- ── Danger Zone ──────────────────────────────────────────────────────────
    AddRule(ct, y); y = y - 18
    y = AddHeader(ct, y, L["CFG_DANGERZONE_TIP_TITLE"])

    local dzDesc = ct:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
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

        -- ── Developer section (below Danger Zone) ────────────────────────────────
    AddRule(ct, y); y = y - 18
    y = AddHeader(ct, y, L["CFG_HDR_DEVELOPER"])

    local devDesc2 = ct:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    devDesc2:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
    devDesc2:SetWidth(CONTENT_W); devDesc2:SetJustifyH("LEFT")
    devDesc2:SetWordWrap(true); devDesc2:SetHeight(20)
    devDesc2:SetTextColor(0.50, 0.50, 0.50)
    devDesc2:SetText(L["CFG_DEV_DESC"])
    y = y - 24

    -- ALL-30: the tools live in their own window (UI/DebugWindow.lua), also /bnb debug.
    local devOpenBtn = BNB.CreateButton(nil, ct, L["CFG_DEV_OPEN_BTN"], 180, 24)
    devOpenBtn:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y + 2)
    devOpenBtn:SetScript("OnClick", function()
        if BNB.DebugWindow and BNB.DebugWindow.Open then BNB.DebugWindow.Open() end
    end)
    y = y - 34

    sf:FinaliseHeight(math.abs(y) + 20)
end

K.BUILDERS.advanced = BuildAdvancedTab

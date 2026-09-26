-- BigNoteBox UI/Config/Modules.lua - Settings Modules tab (was Features, ALL-84)
-- Split out of ConfigWindow.lua (ALL-65.10). One overview row per feature,
-- each feature's settings on its own sub-page.

local BNB = BigNoteBox
local L   = BNB.L

local K = BNB._ConfigKit
local CONTENT_W, ROW_H, ROW_GAP, SLIDER_H = K.CONTENT_W, K.ROW_H, K.ROW_GAP, K.SLIDER_H
local AddRule, AddHeader, AddCheck, AddSlider, MakeKeybindRow = K.AddRule, K.AddHeader, K.AddCheck, K.AddSlider, K.MakeKeybindRow


-- ─────────────────────────────────────────────────────────────────────────────
-- SUB-PAGES (ALL-84) - the larger Features sections, one page each, opened
-- from the Modules tab rows. Built by K.NewSubPage; y starts under the page title.
-- ─────────────────────────────────────────────────────────────────────────────
local function BuildQuickNotePage(sf, ct, y, page)
    local db = BigNoteBoxDB
    -- ── Quick Note ────────────────────────────────────────────────────────────
    -- Inject a small icon button into quest, gossip, and item-text frames so the
    -- player can create a note directly from those game windows.
    do
        -- Collect sub-widgets for greying when the master toggle is off
        local qnWidgets = {}

        local qnEnableCb = CreateFrame("CheckButton", nil, ct, "UICheckButtonTemplate")
        qnEnableCb:SetSize(24, 24)
        qnEnableCb:SetPoint("TOPLEFT", ct, "TOPLEFT", -2, y + 2)
        qnEnableCb:SetChecked(db.quickNoteEnabled ~= false)
        qnEnableCb:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(L["CFG_QN_ENABLE_TIP_TITLE"], 1, 1, 1)
            GameTooltip:AddLine(L["CFG_QN_ENABLE_TOOLTIP_BODY"], 0.8, 0.8, 0.8, true)
            GameTooltip:Show()
        end)
        qnEnableCb:SetScript("OnLeave", function() GameTooltip:Hide() end)
        page.enableCb = qnEnableCb   -- twin on the Features overview row

        local qnEnableLbl = ct:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        qnEnableLbl:SetPoint("LEFT",  qnEnableCb, "RIGHT", 4, 0)
        qnEnableLbl:SetPoint("RIGHT", ct, "RIGHT", 0, 0)
        qnEnableLbl:SetJustifyH("LEFT"); qnEnableLbl:SetHeight(ROW_H)
        qnEnableLbl:SetText(L["CFG_QN_ENABLE_LABEL"])
        y = y - (ROW_H + ROW_GAP)

        -- On-create action dropdown (matches combat dropdown style)
        y = AddCheck(ct, y,
            L["CFG_CHK_QUEST_REWARDS_LABEL"],
            function() return db.saveQuestRewards ~= false end,
            function(v) db.saveQuestRewards = v end,
            L["CFG_CHK_QUEST_REWARDS_TIP"])

        local qnLbl = ct:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        qnLbl:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
        qnLbl:SetHeight(ROW_H); qnLbl:SetJustifyH("LEFT")
        qnLbl:SetText(L["CFG_QN_CREATE_MODE_LABEL"])
        table.insert(qnWidgets, qnLbl)
        y = y - (ROW_H + 2)

        local QN_ITEMS = {
            { key = "silent",  label = L["CFG_QN_ITEM_SILENT"] },
            { key = "open",    label = L["CFG_QN_ITEM_OPEN"] },
            { key = "confirm", label = L["CFG_QN_ITEM_CONFIRM"] },
        }
        local curQN = db.quickNoteAction or "silent"
        local qnDD = CreateFrame("DropdownButton", nil, ct, "WowStyle1DropdownTemplate")
        qnDD:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
        qnDD:SetWidth(CONTENT_W)
        qnDD:SetupMenu(function(_, root)
            for _, item in ipairs(QN_ITEMS) do
                root:CreateRadio(item.label,
                    function() return curQN == item.key end,
                    function()
                        curQN = item.key
                        db.quickNoteAction = item.key
                        qnDD:GenerateMenu()
                    end)
            end
        end)
        qnDD:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(L["CFG_QN_CREATE_MODE_LABEL"], 1, 1, 1)
            GameTooltip:AddLine(L["CFG_QN_MODE_SILENT"], 0.8, 0.8, 0.8, true)
            GameTooltip:AddLine(L["CFG_QN_MODE_OPEN"], 0.8, 0.8, 0.8, true)
            GameTooltip:AddLine(L["CFG_QN_MODE_CONFIRM"], 0.8, 0.8, 0.8, true)
            GameTooltip:Show()
        end)
        qnDD:SetScript("OnLeave", function() GameTooltip:Hide() end)
        table.insert(qnWidgets, qnDD)
        y = y - (32 + ROW_GAP)

        -- Grey / enable sub-widgets based on master toggle
        local function ApplyQNSection(enabled)
            local a = enabled and 1 or 0.35
            for _, w in ipairs(qnWidgets) do
                w:SetAlpha(a)
                if w.SetEnabled then w:SetEnabled(enabled) end
            end
        end

        -- ── DialogueUI subsection (only shown when DialogueUI is installed) ──────
        if C_AddOns.IsAddOnLoaded("DialogueUI") then
            local duiHdr = ct:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            duiHdr:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
            duiHdr:SetTextColor(1, 0.82, 0)
            duiHdr:SetText(L["CFG_DUI_HEADER"])
            table.insert(qnWidgets, duiHdr)
            y = y - (16 + 2)

            y = AddCheck(ct, y,
                L["CFG_CHK_DUI_AUTONOTE_LABEL"],
                function() return db.duiAutoNote == true end,
                function(v)
                    db.duiAutoNote = v
                    if BNB.ApplyDUIAutoNote then BNB.ApplyDUIAutoNote() end
                end,
                L["CFG_CHK_DUI_AUTONOTE_TIP"])
        end

        -- ── Immersion subsection (only shown when Immersion is installed) ─────────
        if C_AddOns.IsAddOnLoaded("Immersion") then
            local immHdr = ct:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            immHdr:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
            immHdr:SetTextColor(1, 0.82, 0)
            immHdr:SetText(L["CFG_IMMERSION_HEADER"])
            table.insert(qnWidgets, immHdr)
            y = y - (16 + 2)

            -- Show the floating BNB button while Immersion is active
            y = AddCheck(ct, y,
                "Show Quick Note button during Immersion dialogues",
                function() return db.quickNoteImmersionBtn ~= false end,
                function(v)
                    db.quickNoteImmersionBtn = v
                    -- Hide or show the existing button immediately if it exists
                    local btn = _G["BNBQuickNoteImmersionBtn"]
                    if btn and not v then btn:Hide() end
                end,
                "Shows a draggable icon button while Immersion is active\n"
                .. "so you can create a note from the current dialogue.\n"
                .. "The button can be dragged to any position on screen.")

            -- "Reset button position" button
            local immResetBtn = BNB.CreateButton(nil, ct, L["CFG_IMM_RESET_BTN"], 160, 22)
            immResetBtn:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
            immResetBtn:SetScript("OnClick", function()
                if BNB.ResetImmersionBtnPos then BNB.ResetImmersionBtnPos() end
            end)
            immResetBtn:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:AddLine(L["CFG_IMM_RESET_TIP1"], 1, 1, 1)
                GameTooltip:AddLine(L["CFG_IMM_RESET_TIP2"], 0.78, 0.78, 0.78)
                GameTooltip:Show()
            end)
            immResetBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
            table.insert(qnWidgets, immResetBtn)
            y = y - (22 + ROW_GAP)
        end

        qnEnableCb:SetScript("OnClick", function(self)
            db.quickNoteEnabled = self:GetChecked() and true or false
            ApplyQNSection(db.quickNoteEnabled)
        end)

        ApplyQNSection(db.quickNoteEnabled ~= false)
    end

    -- Moved from Advanced > Keybindings (ALL-84): the key belongs to this module.
    y = MakeKeybindRow(ct, y, L["CFG_KB_QUICK_NOTE"],
        "BIGNOTEBOXQUICKNOTE", L["CFG_KB_HINT_UNBOUND"], L["CFG_KB_DESC_QUICK_NOTE"])
    sf:FinaliseHeight(math.abs(y) + 12)
end

local function BuildPlayerNpcPage(sf, ct, y)
    local db = BigNoteBoxDB
    -- ── Inspect Note ──────────────────────────────────────────────────────────
    do
        y = AddHeader(ct, y, L["CFG_HDR_INSPECT_NOTE"])

        -- Creation mode dropdown
        local insModeLbl = ct:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        insModeLbl:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
        insModeLbl:SetHeight(ROW_H); insModeLbl:SetJustifyH("LEFT")
        insModeLbl:SetText(L["CFG_INS_MODE_LABEL"])
        y = y - (ROW_H + 2)

        local INS_MODES = {
            { key = "manual",      label = L["CFG_INS_ITEM_MANUAL"] },
            { key = "auto_rich",   label = L["CFG_ITEM_AUTO_RICH"] },
            { key = "auto_normal", label = L["CFG_ITEM_AUTO_NORMAL"] },
        }
        local curInsMode = db.inspectNoteMode or "manual"
        local insModeDD = CreateFrame("DropdownButton", nil, ct, "WowStyle1DropdownTemplate")
        insModeDD:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
        insModeDD:SetWidth(CONTENT_W)

        -- Note type dropdown (below)
        local insTypeLbl = ct:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        local insTypeDD

        local function RefreshInsTypeState()
            local isAuto = curInsMode ~= "manual"
            if insTypeDD then
                insTypeDD:SetEnabled(not isAuto)
                insTypeDD:SetAlpha(isAuto and 0.4 or 1.0)
            end
            if insTypeLbl then
                insTypeLbl:SetAlpha(isAuto and 0.4 or 1.0)
            end
        end

        insModeDD:SetupMenu(function(_, root)
            for _, item in ipairs(INS_MODES) do
                root:CreateRadio(item.label,
                    function() return curInsMode == item.key end,
                    function()
                        curInsMode = item.key
                        db.inspectNoteMode = item.key
                        insModeDD:GenerateMenu()
                        RefreshInsTypeState()
                    end)
            end
        end)
        insModeDD:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(L["CFG_INS_MODE_TIP_TITLE"], 1, 1, 1)
            GameTooltip:AddLine(L["CFG_INS_MODE_MANUAL"], 0.8, 0.8, 0.8, true)
            GameTooltip:AddLine(L["CFG_INS_MODE_AUTO"], 0.8, 0.8, 0.8, true)
            GameTooltip:Show()
        end)
        insModeDD:SetScript("OnLeave", function() GameTooltip:Hide() end)
        y = y - (ROW_H + ROW_GAP)

        -- Note type on click dropdown
        insTypeLbl:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
        insTypeLbl:SetHeight(ROW_H); insTypeLbl:SetJustifyH("LEFT")
        insTypeLbl:SetText(L["CFG_INS_TYPE_LABEL"])
        y = y - (ROW_H + 2)

        local INS_TYPES = {
            { key = "choose",        label = L["CFG_ITEM_CHOOSE_CLICK"] },
            { key = "always_rich",   label = L["CFG_ITEM_ALWAYS_RICH"] },
            { key = "always_normal", label = L["CFG_ITEM_ALWAYS_NORMAL"] },
        }
        local curInsType = db.inspectNoteType or "choose"
        insTypeDD = CreateFrame("DropdownButton", nil, ct, "WowStyle1DropdownTemplate")
        insTypeDD:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
        insTypeDD:SetWidth(CONTENT_W)
        insTypeDD:SetupMenu(function(_, root)
            for _, item in ipairs(INS_TYPES) do
                root:CreateRadio(item.label,
                    function() return curInsType == item.key end,
                    function()
                        curInsType = item.key
                        db.inspectNoteType = item.key
                        insTypeDD:GenerateMenu()
                    end)
            end
        end)
        insTypeDD:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(L["CFG_INS_TYPE_TIP_TITLE"], 1, 1, 1)
            GameTooltip:AddLine(L["CFG_TYPE_CHOOSE"], 0.8, 0.8, 0.8, true)
            GameTooltip:AddLine(L["CFG_TYPE_ALWAYS"], 0.8, 0.8, 0.8, true)
            GameTooltip:AddLine(L["CFG_INS_TYPE_DISABLED"], 0.8, 0.8, 0.8, true)
            GameTooltip:Show()
        end)
        insTypeDD:SetScript("OnLeave", function() GameTooltip:Hide() end)
        y = y - (ROW_H + ROW_GAP)

        RefreshInsTypeState()

        -- Add player situation checkbox
        y = AddCheck(ct, y,
            L["CFG_CHK_SITUATION_LABEL"],
            function() return BigNoteBoxDB and BigNoteBoxDB.inspectNoteAddSituation == true end,
            function(v)
                if BigNoteBoxDB then BigNoteBoxDB.inspectNoteAddSituation = v end
            end,
            L["CFG_CHK_SITUATION_TIP"])

        -- Gear to show dropdown
        local gearShowLbl = ct:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        gearShowLbl:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
        gearShowLbl:SetHeight(ROW_H); gearShowLbl:SetJustifyH("LEFT")
        gearShowLbl:SetText(L["CFG_INS_GEAR_SHOW"])
        y = y - (ROW_H + 2)

        local GEAR_SHOW_OPTS = {
            { key = "both",     label = L["CFG_INS_GEAR_BOTH"]    },
            { key = "regular",  label = L["CFG_INS_GEAR_REGULAR"] },
            { key = "transmog", label = L["CFG_INS_GEAR_TRANSMOG"]},
        }
        local curGearShow = db.inspectNoteGearShow or "both"
        local gearShowDD = CreateFrame("DropdownButton", nil, ct, "WowStyle1DropdownTemplate")
        gearShowDD:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
        gearShowDD:SetWidth(CONTENT_W)
        gearShowDD:SetupMenu(function(_, root)
            for _, item in ipairs(GEAR_SHOW_OPTS) do
                root:CreateRadio(item.label,
                    function() return curGearShow == item.key end,
                    function()
                        curGearShow = item.key
                        db.inspectNoteGearShow = item.key
                        gearShowDD:GenerateMenu()
                    end)
            end
        end)
        gearShowDD:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(L["CFG_INS_GEAR_SHOW"], 1, 1, 1)
            GameTooltip:AddLine(L["CFG_INS_GEAR_SHOW_TIP"], 0.8, 0.8, 0.8, true)
            GameTooltip:Show()
        end)
        gearShowDD:SetScript("OnLeave", function() GameTooltip:Hide() end)
        y = y - (ROW_H + ROW_GAP)
    end

    -- ── Target Note ───────────────────────────────────────────────────────────
    do
        y = AddRule(ct, y) - 4
        y = AddHeader(ct, y, L["CFG_HDR_TARGET_NOTE"])

        -- Note type dropdown
        local tnTypeLbl = ct:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        tnTypeLbl:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
        tnTypeLbl:SetHeight(ROW_H)
        tnTypeLbl:SetJustifyH("LEFT")
        tnTypeLbl:SetText(L["CFG_TN_TYPE_LABEL"])
        y = y - (ROW_H + 2)

        local TN_TYPES = {
            { key = "choose",        label = L["CFG_ITEM_CHOOSE_CLICK"] },
            { key = "always_rich",   label = L["CFG_ITEM_ALWAYS_RICH"] },
            { key = "always_normal", label = L["CFG_ITEM_ALWAYS_NORMAL"] },
        }
        local curTNType = db.targetNoteType or "choose"
        local tnTypeDD = CreateFrame("DropdownButton", nil, ct, "WowStyle1DropdownTemplate")
        tnTypeDD:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
        tnTypeDD:SetWidth(CONTENT_W)
        tnTypeDD:SetupMenu(function(_, root)
            for _, item in ipairs(TN_TYPES) do
                root:CreateRadio(item.label,
                    function() return curTNType == item.key end,
                    function()
                        curTNType = item.key
                        db.targetNoteType = item.key
                        tnTypeDD:GenerateMenu()
                    end)
            end
        end)
        tnTypeDD:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(L["CFG_TN_TYPE_TIP_TITLE"], 1, 1, 1)
            GameTooltip:AddLine(L["CFG_TYPE_CHOOSE"], 0.8, 0.8, 0.8, true)
            GameTooltip:AddLine(L["CFG_TYPE_ALWAYS"], 0.8, 0.8, 0.8, true)
            GameTooltip:Show()
        end)
        tnTypeDD:SetScript("OnLeave", function() GameTooltip:Hide() end)
        y = y - (ROW_H + ROW_GAP)

        -- Tag checklist header
        local tagHeaderLbl = ct:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        tagHeaderLbl:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
        tagHeaderLbl:SetHeight(ROW_H)
        tagHeaderLbl:SetJustifyH("LEFT")
        tagHeaderLbl:SetText(L["CFG_TN_TAGS_HEADER"])
        y = y - (ROW_H + 2)

        local subLbl = ct:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        subLbl:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
        subLbl:SetWidth(CONTENT_W)
        subLbl:SetHeight(ROW_H - 4)
        subLbl:SetJustifyH("LEFT")
        subLbl:SetWordWrap(true)
        subLbl:SetText(L["CFG_TN_SUBLABEL"])
        subLbl:SetTextColor(0.65, 0.65, 0.65)
        y = y - (ROW_H + ROW_GAP - 2)

        -- Individual tag toggles
        y = AddCheck(ct, y, L["CFG_CHK_TAG_TYPE_LABEL"],
            function() local v = BigNoteBoxDB and BigNoteBoxDB.targetNoteTagCreatureType; return v == nil or v == true end,
            function(v) if BigNoteBoxDB then BigNoteBoxDB.targetNoteTagCreatureType = v end end,
            L["CFG_CHK_TAG_TYPE_TIP"])

        y = AddCheck(ct, y, L["CFG_CHK_TAG_FAMILY_LABEL"],
            function() return BigNoteBoxDB and BigNoteBoxDB.targetNoteTagFamily == true end,
            function(v) if BigNoteBoxDB then BigNoteBoxDB.targetNoteTagFamily = v end end,
            L["CFG_CHK_TAG_FAMILY_TIP"])

        y = AddCheck(ct, y, L["CFG_CHK_TAG_CLASS_LABEL"],
            function() local v = BigNoteBoxDB and BigNoteBoxDB.targetNoteTagClassification; return v == nil or v == true end,
            function(v) if BigNoteBoxDB then BigNoteBoxDB.targetNoteTagClassification = v end end,
            L["CFG_CHK_TAG_CLASS_TIP"])

        y = AddCheck(ct, y, L["CFG_CHK_TAG_FACTION_LABEL"],
            function() local v = BigNoteBoxDB and BigNoteBoxDB.targetNoteTagFaction; return v == nil or v == true end,
            function(v) if BigNoteBoxDB then BigNoteBoxDB.targetNoteTagFaction = v end end,
            L["CFG_CHK_TAG_FACTION_TIP"])

        y = AddCheck(ct, y, L["CFG_CHK_TAG_ZONE_LABEL"],
            function() local v = BigNoteBoxDB and BigNoteBoxDB.targetNoteTagZone; return v == nil or v == true end,
            function(v) if BigNoteBoxDB then BigNoteBoxDB.targetNoteTagZone = v end end,
            L["CFG_CHK_TAG_ZONE_TIP"])

        y = AddCheck(ct, y, L["CFG_CHK_TAG_BOSS_LABEL"],
            function() local v = BigNoteBoxDB and BigNoteBoxDB.targetNoteTagBoss; return v == nil or v == true end,
            function(v) if BigNoteBoxDB then BigNoteBoxDB.targetNoteTagBoss = v end end,
            L["CFG_CHK_TAG_BOSS_TIP"])
    end
    sf:FinaliseHeight(math.abs(y) + 12)
end

local function BuildTasksPage(sf, ct, y)
    -- ── Tasks ────────────────────────────────────────────────────────────────────
    y = AddCheck(ct, y, L["CFG_CHK_TASK_REMOVE_LABEL"],
        function() return BigNoteBoxDB and BigNoteBoxDB.taskRemoveOnComplete == true end,
        function(v)
            if BigNoteBoxDB then BigNoteBoxDB.taskRemoveOnComplete = v end
        end,
        L["CFG_CHK_TASK_REMOVE_TIP"])

    -- Completed tasks position dropdown
    do
        local cpLbl = ct:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        cpLbl:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
        cpLbl:SetText(L["CFG_TASK_COMPLETED_POS_LABEL"])
        cpLbl:SetHeight(ROW_H)
        y = y - ROW_H - 2

        local CP_ITEMS = {
            { key = "bottom", label = L["CFG_TASK_POS_BOTTOM_SHORT"] },
            { key = "inline", label = L["CFG_TASK_POS_KEEP_SHORT"]  },
        }

        local useDD = C_XMLUtil and C_XMLUtil.GetTemplateInfo
            and C_XMLUtil.GetTemplateInfo("WowStyle1DropdownTemplate")

        if useDD then
            local cpDD = CreateFrame("DropdownButton", nil, ct, "WowStyle1DropdownTemplate")
            cpDD:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
            cpDD:SetWidth(CONTENT_W)
            cpDD:SetupMenu(function(_, root)
                for _, item in ipairs(CP_ITEMS) do
                    local iv = item.key
                    root:CreateRadio(item.label,
                        function()
                            return (BigNoteBoxDB and BigNoteBoxDB.taskCompletedPosition or "bottom") == iv
                        end,
                        function()
                            if BigNoteBoxDB then BigNoteBoxDB.taskCompletedPosition = iv end
                            cpDD:GenerateMenu()
                            if BNB.RefreshReferenceBox then BNB.RefreshReferenceBox() end
                        end)
                end
            end)
            cpDD:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:AddLine(L["CFG_TASK_COMPLETED_POS_TIP_TITLE"], 1, 1, 1)
                GameTooltip:AddLine(L["CFG_TASK_POS_BOTTOM"], 0.8, 0.8, 0.8, true)
                GameTooltip:AddLine(L["CFG_TASK_POS_KEEP"], 0.8, 0.8, 0.8, true)
                GameTooltip:Show()
            end)
            cpDD:SetScript("OnLeave", function() GameTooltip:Hide() end)
            y = y - 32
        else
            -- Fallback: cycling button
            local function GetCpLabel()
                local v = BigNoteBoxDB and BigNoteBoxDB.taskCompletedPosition or "bottom"
                for _, item in ipairs(CP_ITEMS) do if item.key == v then return item.label end end
                return CP_ITEMS[1].label
            end
            local cpBtn = BNB.CreateButton(nil, ct, GetCpLabel(), CONTENT_W, 24)
            cpBtn:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
            cpBtn:SetScript("OnClick", function(self)
                local cur = BigNoteBoxDB and BigNoteBoxDB.taskCompletedPosition or "bottom"
                local next = cur == "bottom" and "inline" or "bottom"
                if BigNoteBoxDB then BigNoteBoxDB.taskCompletedPosition = next end
                local lbl = next == "bottom" and L["CFG_TASK_POS_BOTTOM_SHORT"] or L["CFG_TASK_POS_KEEP_SHORT"]
                self:SetText(lbl)
                if BNB.RefreshReferenceBox then BNB.RefreshReferenceBox() end
            end)
            y = y - 30
        end
    end

    -- Task row spacing dropdown
    do
        local spLbl = ct:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        spLbl:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
        spLbl:SetText(L["CFG_TASK_SPACING_LABEL"])
        spLbl:SetHeight(ROW_H)
        y = y - ROW_H - 2

        local SP_ITEMS = {
            { key = "compact",  label = L["CFG_SPACING_LABEL_COMPACT"]  },
            { key = "normal",   label = L["CFG_SPACING_LABEL_NORMAL"]   },
            { key = "spacious", label = L["CFG_SPACING_LABEL_SPACIOUS"] },
        }

        local function OnSpacingChanged()
            if BNB.RefreshReferenceBox then BNB.RefreshReferenceBox() end
            -- Refresh any open sticky note task views
            if BNB.Sticky and BNB._stickyFrames then
                for noteID, f in pairs(BNB._stickyFrames) do
                    if f._taskViewActive then
                        local SN = BNB.Sticky
                        if SN.RefreshTaskView then SN.RefreshTaskView(noteID)
                        elseif SN.RefreshNote  then SN.RefreshNote(noteID) end
                    end
                end
            end
        end

        local useDD = C_XMLUtil and C_XMLUtil.GetTemplateInfo
            and C_XMLUtil.GetTemplateInfo("WowStyle1DropdownTemplate")
        if useDD then
            local spDD = CreateFrame("DropdownButton", nil, ct, "WowStyle1DropdownTemplate")
            spDD:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
            spDD:SetWidth(CONTENT_W)
            spDD:SetupMenu(function(_, root)
                for _, item in ipairs(SP_ITEMS) do
                    local iv = item.key
                    root:CreateRadio(item.label,
                        function()
                            return (BigNoteBoxDB and BigNoteBoxDB.taskSpacing or "normal") == iv
                        end,
                        function()
                            if BigNoteBoxDB then BigNoteBoxDB.taskSpacing = iv end
                            spDD:GenerateMenu()
                            OnSpacingChanged()
                        end)
                end
            end)
            spDD:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:AddLine(L["CFG_TASK_SPACING_TIP_TITLE"], 1, 1, 1)
                GameTooltip:AddLine(L["CFG_TASK_SPACING_COMPACT"], 0.8, 0.8, 0.8, true)
                GameTooltip:AddLine(L["CFG_TASK_SPACING_NORMAL"], 0.8, 0.8, 0.8, true)
                GameTooltip:AddLine(L["CFG_TASK_SPACING_SPACIOUS"], 0.8, 0.8, 0.8, true)
                GameTooltip:Show()
            end)
            spDD:SetScript("OnLeave", function() GameTooltip:Hide() end)
            y = y - 32
        else
            local function GetSpLabel()
                local v = BigNoteBoxDB and BigNoteBoxDB.taskSpacing or "normal"
                for _, item in ipairs(SP_ITEMS) do if item.key == v then return item.label end end
                return L["CFG_SPACING_LABEL_NORMAL"]
            end
            local spBtn = BNB.CreateButton(nil, ct, GetSpLabel(), CONTENT_W, 24)
            spBtn:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
            spBtn:SetScript("OnClick", function(self)
                local cur = BigNoteBoxDB and BigNoteBoxDB.taskSpacing or "normal"
                local idx = 1
                for i, item in ipairs(SP_ITEMS) do if item.key == cur then idx = i; break end end
                idx = (idx % #SP_ITEMS) + 1
                if BigNoteBoxDB then BigNoteBoxDB.taskSpacing = SP_ITEMS[idx].key end
                self:SetText(SP_ITEMS[idx].label)
                OnSpacingChanged()
            end)
            y = y - 30
        end
    end

    -- Default sticky view for notes with tasks
    y = AddCheck(ct, y, L["CFG_CHK_STICKY_TASKVIEW_LABEL"],
        function() return (BigNoteBoxDB and BigNoteBoxDB.taskStickyDefault or "tasks") == "tasks" end,
        function(v)
            if BigNoteBoxDB then
                BigNoteBoxDB.taskStickyDefault = v and "tasks" or "note"
            end
        end,
        L["CFG_CHK_STICKY_TASKVIEW_TIP"])
    sf:FinaliseHeight(math.abs(y) + 12)
end

local function BuildRefBoxPage(sf, ct, y, page)
    local db = BigNoteBoxDB
    -- ── Reference Box ─────────────────────────────────────────────────────────
    do
        -- Collect widgets for greying when disabled
        local rbWidgets = {}

        local rbEnableCb = CreateFrame("CheckButton", nil, ct, "UICheckButtonTemplate")
        rbEnableCb:SetSize(24, 24)
        rbEnableCb:SetPoint("TOPLEFT", ct, "TOPLEFT", -2, y + 2)
        rbEnableCb:SetChecked(db.referenceBoxEnabled ~= false)
        rbEnableCb:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(L["CFG_REFBOX_ENABLE_TIP"], 0.8, 0.8, 0.8, true)
            GameTooltip:Show()
        end)
        rbEnableCb:SetScript("OnLeave", function() GameTooltip:Hide() end)
        page.enableCb = rbEnableCb   -- twin on the Features overview row
        local rbEnableLbl = ct:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        rbEnableLbl:SetPoint("LEFT", rbEnableCb, "RIGHT", 4, 0)
        rbEnableLbl:SetPoint("RIGHT", ct, "RIGHT", 0, 0)
        rbEnableLbl:SetJustifyH("LEFT"); rbEnableLbl:SetHeight(ROW_H)
        rbEnableLbl:SetText(L["CFG_REFBOX_ENABLE_LABEL"])
        y = y - (ROW_H + ROW_GAP)

        -- Side: Left / Right dropdown
        local sideDD = CreateFrame("DropdownButton", nil, ct, "WowStyle1DropdownTemplate")
        sideDD:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
        sideDD:SetWidth(CONTENT_W)
        sideDD:SetHeight(22)
        table.insert(rbWidgets, sideDD)

        local SIDE_OPTIONS = {
            { key = "left",  label = L["CFG_REFBOX_SIDE_LEFT"] },
            { key = "right", label = L["CFG_REFBOX_SIDE_RIGHT"] },
        }
        local function RebuildSideMenu()
            sideDD:SetupMenu(function(_, root)
                for _, opt in ipairs(SIDE_OPTIONS) do
                    local key = opt.key
                    root:CreateRadio(opt.label,
                        function() return (db.refboxSide or "left") == key end,
                        function()
                            db.refboxSide = key
                            sideDD:GenerateMenu()
                            if BNB.RefreshReferenceBox then BNB.RefreshReferenceBox() end
                            -- Re-position the open refbox immediately
                            local rbf = _G["BigNoteBoxReferenceBoxFrame"]
                            if rbf and rbf:IsShown() and BNB.OpenReferenceBox then
                                BNB.OpenReferenceBox(db.selectedNoteID)
                            end
                        end)
                end
            end)
        end
        RebuildSideMenu()
        y = y - (22 + ROW_GAP)

        -- Display style dropdown
        local styleDD = CreateFrame("DropdownButton", nil, ct, "WowStyle1DropdownTemplate")
        styleDD:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
        styleDD:SetWidth(CONTENT_W)
        styleDD:SetHeight(22)
        table.insert(rbWidgets, styleDD)

        local STYLE_OPTIONS = {
            { key = "normal",  label = L["CFG_REFBOX_STYLE_NORMAL"] },
            { key = "compact", label = L["CFG_REFBOX_STYLE_COMPACT"] },
        }
        local function RebuildStyleMenu()
            styleDD:SetupMenu(function(_, root)
                for _, opt in ipairs(STYLE_OPTIONS) do
                    local key = opt.key
                    root:CreateRadio(opt.label,
                        function() return (db.refboxDisplayStyle or "normal") == key end,
                        function()
                            db.refboxDisplayStyle = key
                            styleDD:GenerateMenu()
                            if BNB.RefreshReferenceBox then BNB.RefreshReferenceBox() end
                        end)
                end
            end)
        end
        RebuildStyleMenu()
        y = y - (22 + ROW_GAP)

        -- Max attachments slider
        local rbMaxSlider = BNB.CreateSlider(ct, L["CFG_REFBOX_MAX_SLIDER"], 1, 100,
            db.refboxMaxItems or 50, nil,
            function(v) db.refboxMaxItems = v end)
        rbMaxSlider:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
        rbMaxSlider:SetWidth(CONTENT_W)
        rbMaxSlider:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(L["CFG_REFBOX_MAX_TIP"], 0.8, 0.8, 0.8, true)
            GameTooltip:Show()
        end)
        rbMaxSlider:SetScript("OnLeave", function() GameTooltip:Hide() end)
        table.insert(rbWidgets, rbMaxSlider)
        y = y - (SLIDER_H + ROW_GAP)

        -- Auto-open when note has attachments
        y = AddCheck(ct, y, L["CFG_CHK_REFBOX_AUTOOPEN_LABEL"],
            function() return db.refboxAutoOpen ~= false end,
            function(v) db.refboxAutoOpen = v end,
            L["CFG_CHK_REFBOX_AUTOOPEN_TIP"])

        -- Show ItemID / SpellID / QuestID in the game's native tooltip
        y = AddCheck(ct, y, L["CFG_CHK_REFBOX_IDS_LABEL"],
            function() return db.refboxShowIDs == true end,
            function(v)
                db.refboxShowIDs = v
            end,
            L["CFG_CHK_REFBOX_IDS_TIP"])

        -- Apply enabled/disabled state
        local function ApplyRBSection(enabled)
            local a = enabled and 1 or 0.35
            for _, w in ipairs(rbWidgets) do
                w:SetAlpha(a)
                if w.SetEnabled then w:SetEnabled(enabled) end
            end
            if BNB._editorRefBoxBtn then
                BNB._editorRefBoxBtn:SetEnabled(enabled)
                BNB._editorRefBoxBtn:SetAlpha(enabled and 1.0 or 0.4)
            end
            if not enabled and BNB.CloseReferenceBox then
                BNB.CloseReferenceBox()
            end
        end

        rbEnableCb:SetScript("OnClick", function(self)
            db.referenceBoxEnabled = self:GetChecked() and true or false
            ApplyRBSection(db.referenceBoxEnabled)
        end)

        ApplyRBSection(db.referenceBoxEnabled ~= false)
    end
    sf:FinaliseHeight(math.abs(y) + 12)
end

local function BuildSidebarPage(sf, ct, y, page)
    local db = BigNoteBoxDB
    -- Sidebar
    -- Master enable checkbox (manual build to retain widget ref for greying)
    local sidebarEnableCb = CreateFrame("CheckButton", nil, ct, "UICheckButtonTemplate")
    sidebarEnableCb:SetSize(24, 24)
    sidebarEnableCb:SetPoint("TOPLEFT", ct, "TOPLEFT", -2, y + 2)
    sidebarEnableCb:SetChecked(db.sidebarEnabled == true)
    page.enableCb = sidebarEnableCb   -- twin on the Features overview row
    local sidebarEnableLbl = ct:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    sidebarEnableLbl:SetPoint("LEFT",  sidebarEnableCb, "RIGHT", 4, 0)
    sidebarEnableLbl:SetPoint("RIGHT", ct, "RIGHT", 0, 0)
    sidebarEnableLbl:SetJustifyH("LEFT"); sidebarEnableLbl:SetHeight(ROW_H)
    sidebarEnableLbl:SetText(L["CFG_SIDEBAR_ENABLE_LABEL"])
    y = y - (ROW_H + ROW_GAP)

    -- Sub-frame: groups all dependent controls so alpha-greying works as one unit.
    local sidebarSub = CreateFrame("Frame", nil, ct)
    sidebarSub:SetPoint("TOPLEFT",  ct, "TOPLEFT",  0, y)
    sidebarSub:SetPoint("TOPRIGHT", ct, "TOPRIGHT", 0, y)
    sidebarSub:SetHeight(200)  -- resized by RebuildHiddenList
    local subTop = y           -- the list is last on the page: it sets the page height
    local subY = 0

    -- Auto-switch checkbox
    local autoSwCb = CreateFrame("CheckButton", nil, sidebarSub, "UICheckButtonTemplate")
    autoSwCb:SetSize(24, 24)
    autoSwCb:SetPoint("TOPLEFT", sidebarSub, "TOPLEFT", -2, subY + 2)
    autoSwCb:SetChecked(db.sidebarAutoSwitch == true)
    autoSwCb:SetScript("OnClick", function(self)
        db.sidebarAutoSwitch = self:GetChecked() and true or false
    end)
    autoSwCb:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(L["CFG_SIDEBAR_AUTOSWITCH_TIP"], 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    autoSwCb:SetScript("OnLeave", function() GameTooltip:Hide() end)
    local autoSwLbl = sidebarSub:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    autoSwLbl:SetPoint("LEFT",  autoSwCb, "RIGHT", 4, 0)
    autoSwLbl:SetPoint("RIGHT", sidebarSub, "RIGHT", 0, 0)
    autoSwLbl:SetJustifyH("LEFT"); autoSwLbl:SetHeight(ROW_H)
    autoSwLbl:SetText(L["CFG_SIDEBAR_AUTOSWITCH_LABEL"])
    subY = subY - (ROW_H + ROW_GAP)

    -- Side dropdown (Left / Right)
    do
        local sideLbl = sidebarSub:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        sideLbl:SetPoint("TOPLEFT", sidebarSub, "TOPLEFT", 0, subY)
        sideLbl:SetHeight(ROW_H); sideLbl:SetJustifyH("LEFT")
        sideLbl:SetText(L["CFG_SIDEBAR_SIDE_LABEL"])
        subY = subY - (ROW_H + 2)

        local SIDE_ITEMS = {
            { key = "right", label = L["CFG_SIDEBAR_SIDE_RIGHT"] },
            { key = "left",  label = L["CFG_SIDEBAR_SIDE_LEFT"] },
        }
        local curSide = db.sidebarSide or "right"
        local sideDD = CreateFrame("DropdownButton", nil, sidebarSub, "WowStyle1DropdownTemplate")
        sideDD:SetPoint("TOPLEFT", sidebarSub, "TOPLEFT", 0, subY)
        sideDD:SetWidth(CONTENT_W)
        sideDD:SetupMenu(function(_, root)
            for _, item in ipairs(SIDE_ITEMS) do
                root:CreateRadio(item.label,
                    function() return curSide == item.key end,
                    function()
                        curSide = item.key
                        db.sidebarSide = item.key
                        sideDD:GenerateMenu()
                        if BNB.Sidebar and BNB.Sidebar.Refresh then BNB.Sidebar.Refresh() end
                    end)
            end
        end)
        sideDD:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(L["CFG_SIDEBAR_SIDE_LABEL"], 1, 1, 1)
            GameTooltip:AddLine(L["CFG_SIDEBAR_SIDE_TIP"], 0.8, 0.8, 0.8, true)
            GameTooltip:Show()
        end)
        sideDD:SetScript("OnLeave", function() GameTooltip:Hide() end)
        subY = subY - (32 + ROW_GAP)
    end

    -- Position dropdown (Top / Bottom)
    do
        local posLbl = sidebarSub:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        posLbl:SetPoint("TOPLEFT", sidebarSub, "TOPLEFT", 0, subY)
        posLbl:SetHeight(ROW_H); posLbl:SetJustifyH("LEFT")
        posLbl:SetText(L["CFG_SIDEBAR_STARTPOS_LABEL"])
        subY = subY - (ROW_H + 2)

        local POS_ITEMS = {
            { key = false, label = L["CFG_SIDEBAR_POS_TOP"] },
            { key = true,  label = L["CFG_SIDEBAR_POS_BOTTOM"] },
        }
        local curBottom = db.sidebarAtBottom == true
        local posDD = CreateFrame("DropdownButton", nil, sidebarSub, "WowStyle1DropdownTemplate")
        posDD:SetPoint("TOPLEFT", sidebarSub, "TOPLEFT", 0, subY)
        posDD:SetWidth(CONTENT_W)
        posDD:SetupMenu(function(_, root)
            for _, item in ipairs(POS_ITEMS) do
                root:CreateRadio(item.label,
                    function() return curBottom == item.key end,
                    function()
                        curBottom = item.key
                        db.sidebarAtBottom = item.key
                        posDD:GenerateMenu()
                        if BNB.Sidebar and BNB.Sidebar.Refresh then BNB.Sidebar.Refresh() end
                    end)
            end
        end)
        posDD:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(L["CFG_SIDEBAR_STARTPOS_LABEL"], 1, 1, 1)
            GameTooltip:AddLine(L["CFG_SIDEBAR_STARTPOS_TIP"], 0.8, 0.8, 0.8, true)
            GameTooltip:Show()
        end)
        posDD:SetScript("OnLeave", function() GameTooltip:Hide() end)
        subY = subY - (32 + ROW_GAP)
    end

    -- Small icons toggle
    do
        local smallCb = CreateFrame("CheckButton", nil, sidebarSub, "UICheckButtonTemplate")
        smallCb:SetSize(24, 24)
        smallCb:SetPoint("TOPLEFT", sidebarSub, "TOPLEFT", -2, subY + 2)
        smallCb:SetChecked(db.sidebarSmallIcons == true)
        smallCb:SetScript("OnClick", function(self)
            db.sidebarSmallIcons = self:GetChecked() and true or false
            if BNB.Sidebar and BNB.Sidebar.Refresh then BNB.Sidebar.Refresh() end
        end)
        smallCb:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(L["CFG_SIDEBAR_SMALLICONS_TIP"], 0.8, 0.8, 0.8, true)
            GameTooltip:Show()
        end)
        smallCb:SetScript("OnLeave", function() GameTooltip:Hide() end)
        local smallLbl = sidebarSub:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        smallLbl:SetPoint("LEFT",  smallCb, "RIGHT", 4, 0)
        smallLbl:SetPoint("RIGHT", sidebarSub, "RIGHT", 0, 0)
        smallLbl:SetJustifyH("LEFT"); smallLbl:SetHeight(ROW_H)
        smallLbl:SetText(L["CFG_SIDEBAR_SMALLICONS_LABEL"])
        subY = subY - (ROW_H + ROW_GAP)
    end

    -- Description text
    local descLbl = sidebarSub:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    descLbl:SetPoint("TOPLEFT", sidebarSub, "TOPLEFT", 0, subY)
    descLbl:SetWidth(CONTENT_W); descLbl:SetJustifyH("LEFT")
    descLbl:SetWordWrap(true); descLbl:SetHeight(36)
    descLbl:SetTextColor(0.65, 0.65, 0.65)
    descLbl:SetText(L["CFG_SIDEBAR_DESC"])
    subY = subY - 42

    -- Hidden characters header
    local hiddenHdr = sidebarSub:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    hiddenHdr:SetPoint("TOPLEFT", sidebarSub, "TOPLEFT", 0, subY)
    hiddenHdr:SetHeight(ROW_H); hiddenHdr:SetJustifyH("LEFT")
    hiddenHdr:SetText(L["CFG_SIDEBAR_HIDDEN_HEADER"])
    subY = subY - (ROW_H + 2)

    -- Hidden characters dynamic list.
    -- Rows are Frames; old ones are orphaned (SetParent nil) on each rebuild
    -- so their CreateTexture/CreateFontString children don't accumulate.
    local hiddenListY = subY
    local _hiddenRowPool = {}
    local _hiddenRowCount = 0

    local function RebuildHiddenList()
        for i = 1, _hiddenRowCount do
            if _hiddenRowPool[i] then
                _hiddenRowPool[i]:Hide()
                _hiddenRowPool[i]:SetParent(nil)
                _hiddenRowPool[i] = nil
            end
        end
        _hiddenRowCount = 0

        local chars = db.knownChars or {}
        local hidden = {}
        for charKey, rec in pairs(chars) do
            if rec.slotHidden then
                hidden[#hidden + 1] = { key = charKey, rec = rec }
            end
        end
        table.sort(hidden, function(a, b)
            return (a.rec.name or a.key) < (b.rec.name or b.key)
        end)

        local rowY = hiddenListY
        for _, h in ipairs(hidden) do
            _hiddenRowCount = _hiddenRowCount + 1
            local row = CreateFrame("Frame", nil, sidebarSub)
            row:SetHeight(26)
            row:SetPoint("TOPLEFT",  sidebarSub, "TOPLEFT",  0, rowY)
            row:SetPoint("TOPRIGHT", sidebarSub, "TOPRIGHT", 0, rowY)
            local lbl = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            lbl:SetPoint("LEFT",  row, "LEFT",  0,   0)
            lbl:SetPoint("RIGHT", row, "RIGHT", -90, 0)
            lbl:SetJustifyH("LEFT"); lbl:SetHeight(26)
            lbl:SetText((h.rec.name or h.key)
                .. "  |cff888888(" .. (h.rec.realm or "") .. ")|r")
            local showBtn = BNB.CreateButton(nil, row, L["CFG_SIDEBAR_SHOW_BTN"], 80, 22)
            showBtn:SetPoint("RIGHT", row, "RIGHT", 0, 0)
            local capturedKey = h.key
            showBtn:SetScript("OnClick", function()
                if db.knownChars[capturedKey] then
                    db.knownChars[capturedKey].slotHidden = false
                end
                if BNB.Sidebar and BNB.Sidebar.Refresh then BNB.Sidebar.Refresh() end
                RebuildHiddenList()
            end)
            _hiddenRowPool[_hiddenRowCount] = row
            rowY = rowY - 30
        end

        if #hidden == 0 then
            _hiddenRowCount = 1
            local row = CreateFrame("Frame", nil, sidebarSub)
            row:SetHeight(20)
            row:SetPoint("TOPLEFT", sidebarSub, "TOPLEFT", 0, hiddenListY)
            local nl = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            nl:SetAllPoints(row); nl:SetJustifyH("LEFT")
            nl:SetTextColor(0.45, 0.45, 0.45); nl:SetText(L["CFG_SIDEBAR_HIDDEN_NONE"])
            _hiddenRowPool[1] = row
            rowY = hiddenListY - 24
        end

        local subH = math.abs(rowY) + 8
        sidebarSub:SetHeight(subH)
        sf:FinaliseHeight(math.abs(subTop) + subH + 12)
    end

    sf:HookScript("OnShow", RebuildHiddenList)
    RebuildHiddenList()

    -- y must advance past the sub-frame; GetHeight() is now set by RebuildHiddenList
    y = y - sidebarSub:GetHeight()

    local function ApplySidebarSection(enabled)
        sidebarSub:SetAlpha(enabled and 1 or 0.35)
        autoSwCb:SetEnabled(enabled)
        -- Reset filter to "All notes" when sidebar is disabled so the note
        -- list doesn't stay locked to the previously selected character.
        if not enabled and BNB.Sidebar and BNB.Sidebar.SetActive then
            BNB.Sidebar.SetActive("all")
        end
        if BNB.Sidebar and BNB.Sidebar.Refresh then BNB.Sidebar.Refresh() end
        if BNB.SyncSidebarWysiwygBtns then BNB.SyncSidebarWysiwygBtns() end
    end

    sidebarEnableCb:SetScript("OnClick", function(self)
        db.sidebarEnabled = self:GetChecked() and true or false
        ApplySidebarSection(db.sidebarEnabled)
    end)

    ApplySidebarSection(db.sidebarEnabled == true)
    sf:FinaliseHeight(math.abs(y) + 12)
end

-- ─────────────────────────────────────────────────────────────────────────────
-- TAB 4 — MODULES
-- ─────────────────────────────────────────────────────────────────────────────
local function BuildStickyPage(sf, ct, y)
    local db = BigNoteBoxDB
    do
        local desc = ct:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        desc:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
        desc:SetWidth(CONTENT_W); desc:SetJustifyH("LEFT"); desc:SetWordWrap(true)
        desc:SetTextColor(0.60, 0.60, 0.60)
        desc:SetText(L["CFG_ALARM_DESC"])
        local h = desc:GetStringHeight() + 6
        desc:SetHeight(h)
        y = y - h - 6
    end

    y = AddSlider(ct, y, L["CFG_SLIDER_MAX_STICKIES"], 1, 50,
        function() return db.stickyMaxCount or 20 end,
        function(v) db.stickyMaxCount = v end,
        L["CFG_SLIDER_MAX_STICKIES_TIP"])

    y = AddCheck(ct, y, L["CFG_STICKY_HIDE_PERSIST"],
        function() return db.stickiesHiddenPersist == true end,
        function(v) db.stickiesHiddenPersist = v end,
        L["CFG_STICKY_HIDE_PERSIST_TIP"])

    y = AddCheck(ct, y, L["CFG_CHK_ESC_DEFAULT_LABEL"],
        function() return db.stickyEscDefault == true end,
        function(v) db.stickyEscDefault = v or nil end,
        L["CFG_CHK_ESC_DEFAULT_TIP"])

    y = AddCheck(ct, y, L["CFG_CHK_ESC_DIM_LABEL"],
        function() return db.stickyEscOverlay ~= false end,
        -- nil = on, false = off. Not `v and nil or false`: that is always false.
        function(v) if v then db.stickyEscOverlay = nil else db.stickyEscOverlay = false end end,
        L["CFG_CHK_ESC_DIM_TIP"])

    -- On by default: nil = on, explicit false = off.
    y = AddCheck(ct, y, L["CFG_CHK_STICKY_INLINE_EDIT_LABEL"],
        function() return db.stickyInlineEdit ~= false end,
        function(v) if v then db.stickyInlineEdit = nil else db.stickyInlineEdit = false end end,
        L["CFG_CHK_STICKY_INLINE_EDIT_TIP"])

    -- ── Keybind capture button — Show/Hide all sticky notes ───────────────────
    y = MakeKeybindRow(ct, y, L["CFG_STICKY_KEYBIND_LABEL"],
        "BIGNOTEBOXHIDESTICKIES", L["CFG_KB_HINT_CTRL_H"], L["CFG_KB_DESC_HIDE_STICKIES"])
    sf:FinaliseHeight(math.abs(y) + 12)
end

local function BuildFocusPage(sf, ct, y)
    -- Hide entire WoW UI
    y = AddCheck(ct, y,
        L["CFG_CHK_FOCUS_HIDEUI_LABEL"],
        function() local db = BigNoteBoxDB; return db == nil or db.focusHideUI ~= false end,
        function(v)
            if BigNoteBoxDB then BigNoteBoxDB.focusHideUI = v end
        end,
        L["CFG_CHK_FOCUS_HIDEUI_TIP"])

    -- Master orbit toggle
    local orbitCheckY = y
    y = AddCheck(ct, y, L["CFG_FOCUS_ORBIT_ENABLE"],
        function() local db = BigNoteBoxDB; return db == nil or db.focusOrbitEnabled ~= false end,
        function(v)
            if BigNoteBoxDB then BigNoteBoxDB.focusOrbitEnabled = v end
            if BNB.FocusOrbit then
                if v then BNB.FocusOrbit.Start() else BNB.FocusOrbit.Stop() end
            end
            if BNB.UpdateFocusSpinBtn then BNB.UpdateFocusSpinBtn(v) end
            if BNB._focusOrbitRefreshUI then BNB._focusOrbitRefreshUI() end
        end,
        L["CFG_FOCUS_ORBIT_ENABLE_TIP"])

    -- Speed slider (greyed when orbit off)
    local speedSl = BNB.CreateFloatSlider(ct, L["CFG_FOCUS_ORBIT_SPEED"], 0.001, 0.020,
        (BigNoteBoxDB and BigNoteBoxDB.focusOrbitSpeed) or 0.004,
        0.001, 0.004,
        function(v)
            if BigNoteBoxDB then BigNoteBoxDB.focusOrbitSpeed = v end
        end,
        function(v) return string.format("%.3f", v) end)
    speedSl:SetPoint("TOPLEFT", ct, "TOPLEFT", 14, y)
    speedSl:SetWidth(CONTENT_W - 14)
    y = y - (SLIDER_H + ROW_GAP)

    -- Resume-after-movement slider (greyed when orbit off)
    local resumeSl = BNB.CreateFloatSlider(ct, L["CFG_FOCUS_ORBIT_RESUME"], 0, 10,
        (BigNoteBoxDB and BigNoteBoxDB.focusOrbitResumeDelay) or 3.0,
        0.5, 3.0,
        function(v)
            if BigNoteBoxDB then BigNoteBoxDB.focusOrbitResumeDelay = v end
        end,
        function(v)
            if v <= 0 then return "Off" end
            return string.format("%.1f s", v)
        end)
    resumeSl:SetPoint("TOPLEFT", ct, "TOPLEFT", 14, y)
    resumeSl:SetWidth(CONTENT_W - 14)
    y = y - (SLIDER_H + ROW_GAP)

    -- Overlay darkness slider (always active — not tied to orbit toggle)
    y = y - 4
    local overlaySl = BNB.CreateFloatSlider(ct, L["CFG_FOCUS_OVERLAY_ALPHA"], 0.0, 1.0,
        (BigNoteBoxDB and BigNoteBoxDB.focusOverlayAlpha) or 0.6,
        0.05, 0.6,
        function(v)
            if BigNoteBoxDB then BigNoteBoxDB.focusOverlayAlpha = v end
        end,
        function(v) return string.format("%.2f", v) end)
    overlaySl:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
    overlaySl:SetWidth(CONTENT_W)
    y = y - (SLIDER_H + ROW_GAP)

    -- Skin color tint checkbox (only meaningful in skin mode, but always shown)
    y = AddCheck(ct, y, L["CFG_FOCUS_OVERLAY_SKIN_COLOR"],
        function()
            local db = BigNoteBoxDB
            return db ~= nil and db.focusOverlayUseSkinColor == true
        end,
        function(v)
            if BigNoteBoxDB then BigNoteBoxDB.focusOverlayUseSkinColor = v end
        end,
        L["CFG_FOCUS_OVERLAY_SKIN_COLOR_TIP"])

    -- Grey/ungrey orbit-specific sub-controls based on master toggle
    local function RefreshOrbitUI()
        local db = BigNoteBoxDB
        local on = db == nil or db.focusOrbitEnabled ~= false
        local alpha = on and 1.0 or 0.4
        speedSl:SetAlpha(alpha);  speedSl:EnableMouse(on)
        resumeSl:SetAlpha(alpha); resumeSl:EnableMouse(on)
    end
    RefreshOrbitUI()
    BNB._focusOrbitRefreshUI = RefreshOrbitUI
    sf:FinaliseHeight(math.abs(y) + 12)
end

local function BuildContextPopupPage(sf, ct, y, page)
    local db = BigNoteBoxDB
    local cb
    y, cb = AddCheck(ct, y, L["CONFIG_CONTEXT_SURFACE"],
        function() return db.contextSurface ~= false end,
        function(v) db.contextSurface = v end,
        L["CFG_CHK_CONTEXT_SURFACE_TIP"])

    -- "Set Popup Position" button
    local anchorBtn = BNB.CreateButton(nil, ct, L["CFG_TOAST_ANCHOR_BTN"], 150, 22)
    anchorBtn:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
    anchorBtn:SetScript("OnClick", function()
        if BNB.TogglePopupAnchor then BNB.TogglePopupAnchor() end
    end)
    anchorBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(L["CFG_TOAST_ANCHOR_TIP"], 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    anchorBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    y = y - (22 + 6)

    -- Popup hold time slider
    y = AddSlider(ct, y, L["CFG_SLIDER_ALERT_SECONDS"], 0, 60,
        function() return db.popupHoldTime or 5 end,
        function(v) db.popupHoldTime = v end,
        L["CFG_SLIDER_ALERT_SECONDS_TIP"])
    page.enableCb = cb   -- twin on the Features overview row
    sf:FinaliseHeight(math.abs(y) + 12)
end

local function BuildModulesTab(sf, ct)
    local db = BigNoteBoxDB
    local y  = -8

    local MODULES = {
        { L["CFG_CELL_STICKY_HDR"],    L["CFG_SUB_STICKY_DESC"],     BuildStickyPage       },
        { L["CFG_HDR_TASKS"],          L["CFG_SUB_TASKS_DESC"],      BuildTasksPage        },
        { L["CFG_HDR_REFBOX"],         L["CFG_SUB_REFBOX_DESC"],     BuildRefBoxPage       },
        { L["CFG_HDR_SIDEBAR"],        L["CFG_SUB_SIDEBAR_DESC"],    BuildSidebarPage      },
        { L["CFG_FOCUS_ORBIT_HEADER"], L["CFG_SUB_FOCUS_DESC"],      BuildFocusPage        },
        { L["CFG_HDR_QUICK_NOTE"],     L["CFG_SUB_QN_DESC"],         BuildQuickNotePage    },
        { L["CFG_SUB_PLAYER_NPC"],     L["CFG_SUB_PLAYER_NPC_DESC"], BuildPlayerNpcPage    },
        { L["CFG_HDR_CONTEXT_POPUP"],  L["CFG_SUB_CONTEXT_DESC"],    BuildContextPopupPage },
    }
    for _, m in ipairs(MODULES) do
        local page = K.NewSubPage(m[1], m[3])
        y = K.AddOverviewRow(ct, sf, y, page, m[1], m[2])
    end

    -- Toggle-only module, no settings page: the Blizzard icon list lives in its
    -- own load-on-demand addon, BigNoteBox_Icons (ALL-62). Moved from Advanced (ALL-84).
    y = K.AddOverviewRow(ct, sf, y, {
        get = function() return db.blizzardIconComplete == true end,
        set = function(v)
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
        tip = L["CFG_CHK_BLZICON_TIP"],
    }, L["CFG_HDR_ICONS"], L["CFG_SUB_ICONS_DESC"])


    sf:FinaliseHeight(math.abs(y) + 12)
end

K.BUILDERS.modules = BuildModulesTab

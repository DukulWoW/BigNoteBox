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
        BNB.LabelHit(qnEnableCb)   -- the tooltip and click reach over its label too
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
        local curQN = db.quickNoteAction or BNB.DEFAULTS.quickNoteAction
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
                L["CFG_IMM_BTN_LABEL"],
                function() return db.quickNoteImmersionBtn ~= false end,
                function(v)
                    db.quickNoteImmersionBtn = v
                    -- Hide or show the existing button immediately if it exists
                    local btn = _G["BNBQuickNoteImmersionBtn"]
                    if btn and not v then btn:Hide() end
                end,
                L["CFG_IMM_BTN_TIP"])

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

    -- Moved from Advanced > Keybindings (ALL-84). Its own header since the
    -- module became Note Capture (ALL-386): the F7 quick note is not a capture.
    y = AddHeader(ct, y - 6, L["CFG_HDR_QUICK_NOTE_KEY"])
    y = MakeKeybindRow(ct, y, L["CFG_KB_QUICK_NOTE"],
        "BIGNOTEBOXQUICKNOTE", "(" .. string.format(L["SW_KB_DEFAULT_FMT"], "F7") .. ")", L["CFG_KB_DESC_QUICK_NOTE"])

    -- Where the quick-note key puts the new note; nil = main window
    do
        local lbl = ct:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        lbl:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
        lbl:SetHeight(ROW_H); lbl:SetJustifyH("LEFT")
        lbl:SetText(L["CFG_QN_KEY_MODE_LABEL"])
        y = y - (ROW_H + 2)

        local entries = {
            { label = L["CFG_QN_KEY_MODE_MAIN"],   value = "main" },
            { label = L["CFG_QN_KEY_MODE_STICKY"], value = "sticky" },
        }
        -- nil = sticky, the default since 2026-10-02 (Dukul); "main" is saved
        local dd = BNB.CreateValueDropdown(ct, entries, db.quickNoteKeyMode or "sticky",
            function(v) db.quickNoteKeyMode = (v == "main") and v or nil end,
            CONTENT_W, 26)
        dd:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
        local tipOwner = dd._dd or dd
        tipOwner:HookScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(L["CFG_QN_KEY_MODE_LABEL"], 1, 1, 1)
            GameTooltip:AddLine(L["CFG_QN_KEY_MODE_TIP"], 0.8, 0.8, 0.8, true)
            GameTooltip:Show()
        end)
        tipOwner:HookScript("OnLeave", function() GameTooltip:Hide() end)
        -- Sticky Notes off (ALL-343): the key always uses the main window
        if dd._dd then K.GreyWhileOff(dd._dd, BNB.StickiesEnabled, lbl) end
        y = y - (32 + ROW_GAP)
    end
    sf:FinaliseHeight(math.abs(y) + 12)
end

local function BuildPlayerNpcPage(sf, ct, y, page)
    local db = BigNoteBoxDB

    -- Module switch (ALL-343). Applies live: off keeps every player / NPC note
    -- as an ordinary note and hides every way to make or update one.
    local enableCb
    y, enableCb = AddCheck(ct, y, L["CFG_UNIT_ENABLE_LABEL"],
        function() return BNB.UnitNotesEnabled() end,
        function(v)
            if not BigNoteBoxDB then return end
            BigNoteBoxDB.unitNotesEnabled = v
            if BNB.ApplyUnitNotesModule then BNB.ApplyUnitNotesModule(v) end
        end,
        L["CFG_UNIT_ENABLE_TIP"])
    page.enableCb = enableCb   -- twin on the Modules overview row
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
        local curInsMode = db.inspectNoteMode or BNB.DEFAULTS.inspectNoteMode
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
        local curInsType = db.inspectNoteType or BNB.DEFAULTS.inspectNoteType
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
        local curGearShow = db.inspectNoteGearShow or BNB.DEFAULTS.inspectNoteGearShow
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
        local curTNType = db.targetNoteType or BNB.DEFAULTS.targetNoteType
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

local function BuildTasksPage(sf, ct, y, page)
    -- ── Tasks ────────────────────────────────────────────────────────────────────
    -- Module switch (ALL-102). Applies live: off hides every way in (editor
    -- bar, Reference Box panel, note list, stickies) and keeps the task data.
    local enableCb
    y, enableCb = AddCheck(ct, y, L["CFG_TASKS_ENABLE_LABEL"],
        function() return BNB.TasksEnabled() end,
        function(v) BNB.ApplyTasksModule(v) end,   -- Features/TaskManager.lua
        L["CFG_TASKS_ENABLE_TIP"])
    page.enableCb = enableCb   -- twin on the Modules overview row

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

        local cpDD = CreateFrame("DropdownButton", nil, ct, "WowStyle1DropdownTemplate")
        cpDD:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
        cpDD:SetWidth(CONTENT_W)
        cpDD:SetupMenu(function(_, root)
            for _, item in ipairs(CP_ITEMS) do
                local iv = item.key
                root:CreateRadio(item.label,
                    function()
                        return (BigNoteBoxDB and BigNoteBoxDB.taskCompletedPosition or BNB.DEFAULTS.taskCompletedPosition) == iv
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

        local spDD = CreateFrame("DropdownButton", nil, ct, "WowStyle1DropdownTemplate")
        spDD:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
        spDD:SetWidth(CONTENT_W)
        spDD:SetupMenu(function(_, root)
            for _, item in ipairs(SP_ITEMS) do
                local iv = item.key
                root:CreateRadio(item.label,
                    function()
                        return (BigNoteBoxDB and BigNoteBoxDB.taskSpacing or BNB.DEFAULTS.taskSpacing) == iv
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
    end

    -- Default sticky view for notes with tasks
    y = AddCheck(ct, y, L["CFG_CHK_STICKY_TASKVIEW_LABEL"],
        function() return (BigNoteBoxDB and BigNoteBoxDB.taskStickyDefault or BNB.DEFAULTS.taskStickyDefault) == "tasks" end,
        function(v)
            if BigNoteBoxDB then
                BigNoteBoxDB.taskStickyDefault = v and "tasks" or "note"
            end
        end,
        L["CFG_CHK_STICKY_TASKVIEW_TIP"])
    sf:FinaliseHeight(math.abs(y) + 12)
end

-- After a Reference Box side change, here or on Window placement (ALL-291)
function K.ApplyRefboxSide()
    if BNB.RefreshReferenceBox then BNB.RefreshReferenceBox() end
    -- Re-position the open refbox immediately
    local rbf = _G["BigNoteBoxReferenceBoxFrame"]
    if rbf and rbf:IsShown() and BNB.OpenReferenceBox then
        BNB.OpenReferenceBox(BigNoteBoxDB.selectedNoteID)
    end
end

local function BuildRefBoxPage(sf, ct, y, page)
    local db = BigNoteBoxDB
    -- ── Reference Box ─────────────────────────────────────────────────────────
    do
        -- Collect widgets for greying when disabled
        local rbWidgets = {}

        local rbEnableCb = CreateFrame("CheckButton", nil, ct, "UICheckButtonTemplate")
        BNB.LabelHit(rbEnableCb)   -- the tooltip and click reach over its label too
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
                        function() return (db.refboxSide or BNB.DEFAULTS.refboxSide) == key end,
                        function()
                            db.refboxSide = key
                            sideDD:GenerateMenu()
                            K.ApplyRefboxSide()
                        end)
                end
            end)
        end
        RebuildSideMenu()
        -- Also on Modules > Window placement (ALL-291): re-read on show
        sideDD:HookScript("OnShow", function(self) self:GenerateMenu() end)
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
                        function() return (db.refboxDisplayStyle or BNB.DEFAULTS.refboxDisplayStyle) == key end,
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
        local rbMaxSlider = BNB.CreateStackedSlider(ct, CONTENT_W, {
            label = L["CFG_REFBOX_MAX_SLIDER"], min = 1, max = 100,
            value = db.refboxMaxItems or BNB.DEFAULTS.refboxMaxItems, default = BNB.DEFAULTS.refboxMaxItems,
            onChange = function(v) db.refboxMaxItems = v end,
            tip = L["CFG_REFBOX_MAX_TIP"],
        })
        rbMaxSlider:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
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
        end

        rbEnableCb:SetScript("OnClick", function(self)
            db.referenceBoxEnabled = self:GetChecked() and true or false
            ApplyRBSection(db.referenceBoxEnabled)
            -- Hide the editor bar button and close its gap (NoteEditor.lua)
            if BNB.ApplySaveMode then BNB.ApplySaveMode() end
            -- An open window switches to or from the tasks-only layout, or
            -- closes when it has nothing left to show (ALL-102)
            if BNB.ApplyRefBoxModules then BNB.ApplyRefBoxModules() end
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
    BNB.LabelHit(sidebarEnableCb)   -- the tooltip and click reach over its label too
    sidebarEnableCb:SetSize(24, 24)
    sidebarEnableCb:SetPoint("TOPLEFT", ct, "TOPLEFT", -2, y + 2)
    sidebarEnableCb:SetChecked(db.sidebarEnabled == true)
    page.enableCb = sidebarEnableCb   -- twin on the Features overview row
    local sidebarEnableLbl = ct:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    sidebarEnableLbl:SetPoint("LEFT",  sidebarEnableCb, "RIGHT", 4, 0)
    sidebarEnableLbl:SetPoint("RIGHT", ct, "RIGHT", 0, 0)
    sidebarEnableLbl:SetJustifyH("LEFT"); sidebarEnableLbl:SetHeight(ROW_H)
    sidebarEnableLbl:SetText(L["CFG_SIDEBAR_ENABLE_LABEL"])
    BNB.CheckTip(sidebarEnableCb, L["CFG_SIDEBAR_ENABLE_TIP"])
    y = y - (ROW_H + ROW_GAP)

    -- Sub-frame: groups all dependent controls so alpha-greying works as one unit.
    local sidebarSub = CreateFrame("Frame", nil, ct)
    sidebarSub:SetPoint("TOPLEFT",  ct, "TOPLEFT",  0, y)
    sidebarSub:SetPoint("TOPRIGHT", ct, "TOPRIGHT", 0, y)
    sidebarSub:SetHeight(200)  -- resized by RebuildCharList
    local subTop = y           -- the list is last on the page: it sets the page height
    local subY = 0

    -- Auto-switch checkbox
    local autoSwCb = CreateFrame("CheckButton", nil, sidebarSub, "UICheckButtonTemplate")
    BNB.LabelHit(autoSwCb)   -- the tooltip and click reach over its label too
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

    -- Start position and small icons mean nothing for the top tabs: greyed
    -- while Top is chosen (Dukul, ALL-248)
    -- "Tabs fill the width" is the other way round: top tabs only
    local posDD, posLbl, smallCb, smallLbl, fillCb, fillLbl
    local function SyncTopGrey()
        local top = (db.sidebarSide or BNB.DEFAULTS.sidebarSide) == "top"
        local v = top and 0.5 or 1
        if posDD then posDD:SetEnabled(not top) end
        if smallCb then smallCb:SetEnabled(not top) end
        if posLbl then posLbl:SetAlpha(v) end
        if smallLbl then smallLbl:SetAlpha(v) end
        if fillCb then fillCb:SetEnabled(top) end
        if fillLbl then fillLbl:SetAlpha(top and 1 or 0.5) end
    end

    -- Side dropdown (Top / Right / Left)
    do
        local sideLbl = sidebarSub:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        sideLbl:SetPoint("TOPLEFT", sidebarSub, "TOPLEFT", 0, subY)
        sideLbl:SetHeight(ROW_H); sideLbl:SetJustifyH("LEFT")
        sideLbl:SetText(L["CFG_SIDEBAR_SIDE_LABEL"])
        subY = subY - (ROW_H + 2)

        local SIDE_ITEMS = {
            { key = "top",   label = L["CFG_SIDEBAR_SIDE_TOP"] },
            { key = "right", label = L["CFG_SIDEBAR_SIDE_RIGHT"] },
            { key = "left",  label = L["CFG_SIDEBAR_SIDE_LEFT"] },
        }
        local curSide = db.sidebarSide or BNB.DEFAULTS.sidebarSide
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
                        SyncTopGrey()
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

    -- Sort order of the character icons, both side strip and top tabs
    -- (ALL-298): nil = newest first; pinned characters stay in front
    do
        local sortLbl = sidebarSub:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        sortLbl:SetPoint("TOPLEFT", sidebarSub, "TOPLEFT", 0, subY)
        sortLbl:SetHeight(ROW_H); sortLbl:SetJustifyH("LEFT")
        sortLbl:SetText(L["CFG_SIDEBAR_SORT_LABEL"])
        subY = subY - (ROW_H + 2)

        local entries = {
            { label = L["CFG_SIDEBAR_SORT_NEWEST"], value = "newest" },
            { label = L["CFG_SIDEBAR_SORT_NAME"],   value = "name" },
            { label = L["CFG_SIDEBAR_SORT_CLASS"],  value = "class" },
            { label = L["CFG_SIDEBAR_SORT_NOTES"],  value = "notes" },
        }
        local dd = BNB.CreateValueDropdown(sidebarSub, entries, db.sidebarSort or "newest",
            function(v)
                db.sidebarSort = (v ~= "newest") and v or nil
                if BNB.Sidebar and BNB.Sidebar.Refresh then BNB.Sidebar.Refresh() end
            end, CONTENT_W, 26)
        dd:SetPoint("TOPLEFT", sidebarSub, "TOPLEFT", 0, subY)
        local tipOwner = dd._dd or dd
        tipOwner:HookScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(L["CFG_SIDEBAR_SORT_LABEL"], 1, 1, 1)
            GameTooltip:AddLine(L["CFG_SIDEBAR_SORT_TIP"], 0.8, 0.8, 0.8, true)
            GameTooltip:Show()
        end)
        tipOwner:HookScript("OnLeave", function() GameTooltip:Hide() end)
        subY = subY - (32 + ROW_GAP)
    end

    -- Top tabs share the whole width of the main window, normal and skin
    -- (ALL-333, Dukul 2026-10-06): nil = on
    do
        fillCb = CreateFrame("CheckButton", nil, sidebarSub, "UICheckButtonTemplate")
        BNB.LabelHit(fillCb)   -- the tooltip and click reach over its label too
        fillCb:SetSize(24, 24)
        fillCb:SetPoint("TOPLEFT", sidebarSub, "TOPLEFT", -2, subY + 2)
        fillCb:SetChecked(db.sidebarTabsFill ~= false)
        fillCb:SetScript("OnClick", function(self)
            -- Explicit if: "x and false or nil" is always nil in Lua
            if self:GetChecked() then db.sidebarTabsFill = nil else db.sidebarTabsFill = false end
            if BNB.Sidebar and BNB.Sidebar.Refresh then BNB.Sidebar.Refresh() end
        end)
        fillCb:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(L["CFG_SIDEBAR_TABFILL_LABEL"], 1, 1, 1)
            GameTooltip:AddLine(L["CFG_SIDEBAR_TABFILL_TIP"], 0.8, 0.8, 0.8, true)
            GameTooltip:Show()
        end)
        fillCb:SetScript("OnLeave", function() GameTooltip:Hide() end)
        fillLbl = sidebarSub:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        fillLbl:SetPoint("LEFT",  fillCb, "RIGHT", 4, 0)
        fillLbl:SetPoint("RIGHT", sidebarSub, "RIGHT", 0, 0)
        fillLbl:SetJustifyH("LEFT"); fillLbl:SetHeight(ROW_H)
        fillLbl:SetText(L["CFG_SIDEBAR_TABFILL_LABEL"])
        subY = subY - (ROW_H + ROW_GAP)
    end

    -- Position dropdown (Top / Bottom)
    do
        posLbl = sidebarSub:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        posLbl:SetPoint("TOPLEFT", sidebarSub, "TOPLEFT", 0, subY)
        posLbl:SetHeight(ROW_H); posLbl:SetJustifyH("LEFT")
        posLbl:SetText(L["CFG_SIDEBAR_STARTPOS_LABEL"])
        subY = subY - (ROW_H + 2)

        local POS_ITEMS = {
            { key = false, label = L["CFG_SIDEBAR_POS_TOP"] },
            { key = true,  label = L["CFG_SIDEBAR_POS_BOTTOM"] },
        }
        local curBottom = db.sidebarAtBottom == true
        posDD = CreateFrame("DropdownButton", nil, sidebarSub, "WowStyle1DropdownTemplate")
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
        smallCb = CreateFrame("CheckButton", nil, sidebarSub, "UICheckButtonTemplate")
        BNB.LabelHit(smallCb)   -- the tooltip and click reach over its label too
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
        smallLbl = sidebarSub:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        smallLbl:SetPoint("LEFT",  smallCb, "RIGHT", 4, 0)
        smallLbl:SetPoint("RIGHT", sidebarSub, "RIGHT", 0, 0)
        smallLbl:SetJustifyH("LEFT"); smallLbl:SetHeight(ROW_H)
        smallLbl:SetText(L["CFG_SIDEBAR_SMALLICONS_LABEL"])
        subY = subY - (ROW_H + ROW_GAP)
    end
    SyncTopGrey()

    -- Description text
    local descLbl = sidebarSub:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    descLbl:SetPoint("TOPLEFT", sidebarSub, "TOPLEFT", 0, subY)
    descLbl:SetWidth(CONTENT_W); descLbl:SetJustifyH("LEFT")
    descLbl:SetWordWrap(true); descLbl:SetHeight(36)
    descLbl:SetTextColor(0.65, 0.65, 0.65)
    descLbl:SetText(L["CFG_SIDEBAR_DESC"])
    subY = subY - 42

    -- Characters header
    local charsHdr = sidebarSub:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    charsHdr:SetPoint("TOPLEFT", sidebarSub, "TOPLEFT", 0, subY)
    charsHdr:SetHeight(ROW_H); charsHdr:SetJustifyH("LEFT")
    charsHdr:SetText(L["CFG_SIDEBAR_CHARS_HEADER"])
    subY = subY - (ROW_H + 2)

    -- Every character BigNoteBox knows (ALL-249; was the hidden ones only,
    -- ALL-211): name, realm, note count, "not seen for N days" after
    -- CharacterRemove.STALE_DAYS, Hide / Show and Remove (not for the
    -- character you are on). Rows are built once and reused (PERF-10): the
    -- list is rebuilt on every show of this page. A row's buttons read the
    -- character from row._charKey.
    local charListY = subY
    local _charRowPool = {}
    local RebuildCharList   -- the row buttons call it
    local CR = BNB.CharacterRemove

    local function CharRow(i)
        local row = _charRowPool[i]
        if row then return row end
        row = CreateFrame("Frame", nil, sidebarSub)
        row:SetHeight(26)
        local lbl = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        lbl:SetPoint("LEFT",  row, "LEFT",  0,    0)
        lbl:SetPoint("RIGHT", row, "RIGHT", -156, 0)
        lbl:SetJustifyH("LEFT"); lbl:SetHeight(26); lbl:SetWordWrap(false)
        row._lbl = lbl
        local removeBtn = BNB.CreateButton(nil, row, L["CFG_SIDEBAR_REMOVE_BTN"], 72, 22)
        removeBtn:SetPoint("RIGHT", row, "RIGHT", 0, 0)
        removeBtn:SetScript("OnClick", function()
            if row._charKey and CR then CR.Open(row._charKey) end
        end)
        removeBtn:HookScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(L["CFG_SIDEBAR_REMOVE_BTN"], 1, 1, 1)
            GameTooltip:AddLine(L["CFG_SIDEBAR_REMOVE_TIP"], 1, 0.82, 0, true)
            GameTooltip:Show()
        end)
        removeBtn:HookScript("OnLeave", function() GameTooltip:Hide() end)
        row._removeBtn = removeBtn
        local hideBtn = BNB.CreateButton(nil, row, L["CFG_SIDEBAR_SHOW_BTN"], 72, 22)
        hideBtn:SetPoint("RIGHT", removeBtn, "LEFT", -6, 0)
        hideBtn:SetScript("OnClick", function()
            local key = row._charKey
            local rec = key and db.knownChars[key]
            if not rec then return end
            rec.slotHidden = not rec.slotHidden
            -- As the sidebar's own "Hide from sidebar": leave the hidden tab
            local SB = BNB.Sidebar
            if rec.slotHidden and SB and SB.GetActive and SB.GetActive() == "char:" .. key then
                SB.SetActive("all")
            end
            if SB and SB.Refresh then SB.Refresh() end
            RebuildCharList()
        end)
        row._hideBtn = hideBtn
        _charRowPool[i] = row
        return row
    end

    RebuildCharList = function()
        for _, row in ipairs(_charRowPool) do row:Hide() end

        local list = {}
        for charKey, rec in pairs(db.knownChars or {}) do
            list[#list + 1] = { key = charKey, rec = rec }
        end
        table.sort(list, function(a, b)
            return (a.rec.name or a.key):lower() < (b.rec.name or b.key):lower()
        end)

        local rowY = charListY
        for i, c in ipairs(list) do
            local row = CharRow(i)
            row._charKey = c.key
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT",  sidebarSub, "TOPLEFT",  0, rowY)
            row:SetPoint("TOPRIGHT", sidebarSub, "TOPRIGHT", 0, rowY)
            local isMe = c.key == BNB.currentChar
            local extra = {}
            if c.rec.realm and c.rec.realm ~= "" then extra[#extra + 1] = c.rec.realm end
            local n = CR and CR.NoteCount(c.key) or 0
            extra[#extra + 1] = n == 1 and L["SB_NOTE_COUNT_ONE"] or string.format(L["SB_NOTE_COUNT_N_FMT"], n)
            if isMe then
                extra[#extra + 1] = L["CFG_SIDEBAR_THIS_CHAR"]
            else
                local days = CR and CR.DaysUnseen(c.key)
                if days and days >= CR.STALE_DAYS then
                    extra[#extra + 1] = string.format(L["CFG_SIDEBAR_STALE_FMT"], days)
                end
            end
            row._lbl:SetText((c.rec.name or c.key) .. "  |cff888888" .. table.concat(extra, ", ") .. "|r")
            -- A hidden character's name is dimmed; its button says Show
            row._lbl:SetAlpha(c.rec.slotHidden and 0.55 or 1)
            row._hideBtn:SetText(L[c.rec.slotHidden and "CFG_SIDEBAR_SHOW_BTN" or "CFG_SIDEBAR_HIDE_BTN"])
            row._removeBtn:SetShown(not isMe)
            row:Show()
            rowY = rowY - 30
        end

        local subH = math.abs(rowY) + 8
        sidebarSub:SetHeight(subH)
        sf:FinaliseHeight(math.abs(subTop) + subH + 12)
    end

    sf:HookScript("OnShow", RebuildCharList)
    RebuildCharList()
    -- The sidebar's "Hide from sidebar" and CharacterRemove call this, so an
    -- open page follows (ALL-211, ALL-249)
    BNB.RefreshHiddenCharList = RebuildCharList
    -- The note counts follow note changes while the page is open: a new,
    -- deleted, restored or moved (scope) note; one rebuild per frame
    local function CharListFollow(msg, _, fields)
        if not sf:IsVisible() then return end
        if msg == "NoteChanged" and not (fields and fields.scope ~= nil) then return end
        BNB.Debounce("cfgCharList", 0, RebuildCharList)
    end
    for _, msg in ipairs({ "NoteCreated", "NoteChanged", "NoteDeleted", "NoteRestored" }) do
        BNB.RegisterMessage("ConfigCharList", msg, CharListFollow)
    end

    -- y must advance past the sub-frame; GetHeight() is now set by RebuildCharList
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
local function BuildStickyPage(sf, ct, y, page)
    local db = BigNoteBoxDB
    -- Module switch (ALL-343). Applies live: off closes every sticky (they
    -- reopen when it is switched back on) and hides every way to open one.
    local enableCb
    y, enableCb = AddCheck(ct, y, L["CFG_STICKY_ENABLE_LABEL"],
        function() return BNB.StickiesEnabled() end,
        function(v)
            if not BigNoteBoxDB then return end
            BigNoteBoxDB.stickiesEnabled = v
            if BNB.Sticky and BNB.Sticky.ApplyModule then BNB.Sticky.ApplyModule(v) end
        end,
        L["CFG_STICKY_ENABLE_TIP"])
    page.enableCb = enableCb   -- twin on the Modules overview row
    do
        local desc = ct:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        desc:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
        desc:SetWidth(CONTENT_W); desc:SetJustifyH("LEFT"); desc:SetWordWrap(true)
        desc:SetTextColor(0.60, 0.60, 0.60)
        desc:SetText(L["CFG_SUB_STICKY_DESC"])   -- was the alarm page's text
        local h = desc:GetStringHeight() + 6
        desc:SetHeight(h)
        y = y - h - 6
    end

    y = AddSlider(ct, y, L["CFG_SLIDER_MAX_STICKIES"], 1, 50,
        function() return db.stickyMaxCount or BNB.DEFAULTS.stickyMaxCount end,
        function(v) db.stickyMaxCount = v end,
        L["CFG_SLIDER_MAX_STICKIES_TIP"], BNB.DEFAULTS.stickyMaxCount)

    -- nil = off: stickies act like windows, the one clicked last comes to the
    -- front (Ctrl+J brings them all forward); on = always over the main window
    -- (UI/StickyNote.lua SN.Strata)
    y = AddCheck(ct, y, L["CFG_STICKY_ON_TOP"],
        function() return db.stickiesOnTop == true end,
        function(v)
            if v then db.stickiesOnTop = true else db.stickiesOnTop = nil end
            if BNB.Sticky and BNB.Sticky.ApplyStrata then BNB.Sticky.ApplyStrata() end
        end,
        L["CFG_STICKY_ON_TOP_TIP"])

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
        function(v)
            if v then db.stickyEscOverlay = nil else db.stickyEscOverlay = false end
            if BNB.Sticky and BNB.Sticky.ApplyEscOverlay then BNB.Sticky.ApplyEscOverlay() end
        end,
        L["CFG_CHK_ESC_DIM_TIP"])

    -- On by default: nil = on, explicit false = off.
    y = AddCheck(ct, y, L["CFG_CHK_STICKY_INLINE_EDIT_LABEL"],
        function() return db.stickyInlineEdit ~= false end,
        function(v) if v then db.stickyInlineEdit = nil else db.stickyInlineEdit = false end end,
        L["CFG_CHK_STICKY_INLINE_EDIT_TIP"])

    -- ── Keybind capture button — Show/Hide all sticky notes ───────────────────
    y = MakeKeybindRow(ct, y, L["CFG_STICKY_KEYBIND_LABEL"],
        "BIGNOTEBOXHIDESTICKIES", L["CFG_KB_HINT_CTRL_H"], L["CFG_KB_DESC_HIDE_STICKIES"])

    -- ── Hover buttons (ALL-266) ───────────────────────────────────────────────
    -- stickyHideBtn[key] = true hides that header button (UI/StickyNote.lua
    -- SN.HdrBtnHidden); nil = shown. The right-click menu keeps them all.
    y = AddRule(ct, y)
    y = AddHeader(ct, y, L["CFG_HDR_STICKY_HOVER_BTNS"])
    for _, b in ipairs({
        { "tasks",    "CFG_STICKY_BTN_TASKS"    },
        { "alarm",    "CFG_STICKY_BTN_ALARM"    },
        { "edit",     "CFG_STICKY_BTN_EDIT"     },
        { "settings", "CFG_STICKY_BTN_SETTINGS" },
        { "minimize", "CFG_STICKY_BTN_MINIMIZE" },   -- ALL-357
        { "view",     "CFG_STICKY_BTN_VIEW"     },
    }) do
        local key = b[1]
        local cb
        y, cb = AddCheck(ct, y, L[b[2]],
            function() return not (BNB.Sticky and BNB.Sticky.HdrBtnHidden(key)) end,
            function(v)
                local h = db.stickyHideBtn or {}
                h[key] = (not v) or nil
                db.stickyHideBtn = next(h) and h or nil
                if BNB.Sticky and BNB.Sticky.ApplyHeaderButtons then BNB.Sticky.ApplyHeaderButtons() end
            end,
            L["CFG_STICKY_BTN_TIP"])
        -- Greyed while its module is off (ALL-343)
        if key == "alarm" then K.GreyWhileOff(cb, BNB.AlarmsEnabled) end
        if key == "tasks" then K.GreyWhileOff(cb, BNB.TasksEnabled) end
    end
    sf:FinaliseHeight(math.abs(y) + 12)
end

local function BuildFocusPage(sf, ct, y, page)
    -- Module switch (ALL-343). Applies live: off hides every way in and
    -- closes Focus mode if it is open.
    local enableCb
    y, enableCb = AddCheck(ct, y, L["CFG_FOCUS_ENABLE_LABEL"],
        function() return BNB.FocusEnabled() end,
        function(v)
            if not BigNoteBoxDB then return end
            BigNoteBoxDB.focusEnabled = v
            if BNB.ApplyFocusModule then BNB.ApplyFocusModule(v) end
        end,
        L["CFG_FOCUS_ENABLE_TIP"])
    page.enableCb = enableCb   -- twin on the Modules overview row

    -- Hide entire WoW UI
    y = AddCheck(ct, y,
        L["CFG_CHK_FOCUS_HIDEUI_LABEL"],
        function() local db = BigNoteBoxDB; return db == nil or db.focusHideUI ~= false end,
        function(v)
            if BigNoteBoxDB then BigNoteBoxDB.focusHideUI = v end
        end,
        L["CFG_CHK_FOCUS_HIDEUI_TIP"])

    -- Master orbit toggle
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
    local speedSl = BNB.CreateStackedSlider(ct, CONTENT_W - 14, {
        label = L["CFG_FOCUS_ORBIT_SPEED"], min = 0.001, max = 0.020, step = 0.001,
        value = (BigNoteBoxDB and BigNoteBoxDB.focusOrbitSpeed) or BNB.DEFAULTS.focusOrbitSpeed, default = BNB.DEFAULTS.focusOrbitSpeed,
        fmt = function(v) return string.format("%.3f", v) end,
        onChange = function(v)
            if BigNoteBoxDB then BigNoteBoxDB.focusOrbitSpeed = v end
        end,
    })
    speedSl:SetPoint("TOPLEFT", ct, "TOPLEFT", 14, y)
    y = y - (SLIDER_H + ROW_GAP)

    -- Resume-after-movement slider (greyed when orbit off)
    local resumeSl = BNB.CreateStackedSlider(ct, CONTENT_W - 14, {
        label = L["CFG_FOCUS_ORBIT_RESUME"], min = 0, max = 10, step = 0.5,
        value = (BigNoteBoxDB and BigNoteBoxDB.focusOrbitResumeDelay) or BNB.DEFAULTS.focusOrbitResumeDelay, default = BNB.DEFAULTS.focusOrbitResumeDelay,
        fmt = function(v)
            if v <= 0 then return L["CFG_FOCUS_ORBIT_OFF"] end
            return string.format("%.1f s", v)
        end,
        onChange = function(v)
            if BigNoteBoxDB then BigNoteBoxDB.focusOrbitResumeDelay = v end
        end,
    })
    resumeSl:SetPoint("TOPLEFT", ct, "TOPLEFT", 14, y)
    y = y - (SLIDER_H + ROW_GAP)

    -- Overlay darkness slider (always active — not tied to orbit toggle)
    y = y - 4
    local overlaySl = BNB.CreateStackedSlider(ct, CONTENT_W, {
        label = L["CFG_FOCUS_OVERLAY_ALPHA"], min = 0.0, max = 1.0, step = 0.05,
        value = (BigNoteBoxDB and BigNoteBoxDB.focusOverlayAlpha) or BNB.DEFAULTS.focusOverlayAlpha, default = BNB.DEFAULTS.focusOverlayAlpha,
        onChange = function(v)
            if BigNoteBoxDB then BigNoteBoxDB.focusOverlayAlpha = v end
        end,
    })
    overlaySl:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
    y = y - (SLIDER_H + ROW_GAP)

    -- Skin color tint checkbox (only meaningful in skin mode, but always shown;
    -- greyed and inactive in normal mode, ALL-24)
    local tintCb
    y, tintCb = AddCheck(ct, y, L["CFG_FOCUS_OVERLAY_SKIN_COLOR"],
        function()
            local db = BigNoteBoxDB
            return db ~= nil and db.focusOverlayUseSkinColor == true
        end,
        function(v)
            if BigNoteBoxDB then BigNoteBoxDB.focusOverlayUseSkinColor = v end
        end,
        L["CFG_FOCUS_OVERLAY_SKIN_COLOR_TIP"])
    local function RefreshTintUI()
        local skin = BigNoteBoxDB and BigNoteBoxDB.skinMode and true or false
        tintCb:SetEnabled(skin)
        tintCb._lbl:SetAlpha(skin and 1 or 0.4)
    end
    RefreshTintUI()
    -- Skin mode can be switched while Settings is open (it waits for a reload)
    sf:HookScript("OnShow", RefreshTintUI)

    -- Grey/ungrey orbit-specific sub-controls based on master toggle
    local function RefreshOrbitUI()
        local db = BigNoteBoxDB
        local on = db == nil or db.focusOrbitEnabled ~= false
        local alpha = on and 1.0 or 0.4
        speedSl:SetAlpha(alpha);  speedSl:SetEnabled(on)
        resumeSl:SetAlpha(alpha); resumeSl:SetEnabled(on)
    end
    RefreshOrbitUI()
    BNB._focusOrbitRefreshUI = RefreshOrbitUI
    sf:FinaliseHeight(math.abs(y) + 12)
end

-- The Situations module (ALL-375; was Context Popup, same saved switch
-- `contextSurface`). Applies live. Its toasts are set on the Toasts page
-- (ALL-384), linked from here.
local function BuildContextPopupPage(sf, ct, y, page)
    local db = BigNoteBoxDB
    local cb
    y, cb = AddCheck(ct, y, L["CONFIG_CONTEXT_SURFACE"],
        function() return BNB.SituationsEnabled() end,
        function(v)
            db.contextSurface = v
            if BNB.ApplySituationsModule then BNB.ApplySituationsModule(v) end
        end,
        L["CFG_CHK_CONTEXT_SURFACE_TIP"])

    -- How situation notes look when they show: the Toasts page
    y = y - 6
    local toastsBtn = BNB.CreateButton(nil, ct, L["CFG_TOAST_SETTINGS_BTN"], 150, 22)
    toastsBtn:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
    toastsBtn:SetScript("OnClick", function() BNB.OpenSettingsPage("modules", "toasts") end)
    toastsBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(L["CFG_TOAST_SETTINGS_BTN"], 1, 1, 1)
        GameTooltip:AddLine(L["CFG_TOAST_SETTINGS_TIP"], 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    toastsBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    y = y - (22 + 10)

    page.enableCb = cb   -- twin on the Features overview row
    sf:FinaliseHeight(math.abs(y) + 12)
end

-- The Toasts module (ALL-384): the toast engine's switch (`toastsEnabled`),
-- a checkbox per sender (`toastSources`) and every toast setting (UI/Toast.lua,
-- ALL-376). Applies live; the settings grey while it is off.
local function BuildToastsPage(sf, ct, y, page)
    local db = BigNoteBoxDB
    local cb
    local offWidgets, offLabels = {}, {}
    local srcBoxes = {}
    local function GreyOff()
        local on = BNB.ToastsEnabled()
        for _, w in ipairs(offWidgets) do w:SetEnabled(on); w:SetAlpha(on and 1 or 0.35) end
        for _, l in ipairs(offLabels) do l:SetAlpha(on and 1 or 0.35) end
        -- A sender's box also needs its own module(s) on
        for _, s in ipairs(srcBoxes) do
            local ok = on and s.need()
            s.cb:SetEnabled(ok); s.cb:SetAlpha(ok and 1 or 0.35)
            if s.cb._lbl then s.cb._lbl:SetAlpha(ok and 1 or 0.35) end
        end
    end
    local function ToastChanged()
        BNB.Toast.Relayout()
        BNB.Toast.RefreshAnchor()
    end
    local function Tip(owner, title, tip)
        owner:HookScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(title, 1, 1, 1)
            GameTooltip:AddLine(tip, 0.8, 0.8, 0.8, true)
            GameTooltip:Show()
        end)
        owner:HookScript("OnLeave", function() GameTooltip:Hide() end)
    end
    -- Label above a full-width value dropdown (as Quick Note's key mode)
    local function AddDrop(labelKey, tipKey, entries, key, apply)
        local lbl = ct:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        lbl:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
        lbl:SetHeight(ROW_H); lbl:SetJustifyH("LEFT")
        lbl:SetText(L[labelKey])
        y = y - (ROW_H + 2)
        local dd = BNB.CreateValueDropdown(ct, entries, db[key] or BNB.DEFAULTS[key],
            function(v) db[key] = v; if apply then apply() end end, CONTENT_W, 26)
        dd:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
        Tip(dd._dd or dd, L[labelKey], L[tipKey])
        offWidgets[#offWidgets + 1] = dd._dd or dd
        offLabels[#offLabels + 1]   = lbl
        y = y - (32 + ROW_GAP)
    end
    y, cb = AddCheck(ct, y, L["CFG_CHK_TOASTS"],
        function() return BNB.ToastsEnabled() end,
        function(v)
            db.toastsEnabled = v
            if BNB.ApplyToastsModule then BNB.ApplyToastsModule(v) end
            GreyOff()
        end,
        L["CFG_CHK_TOASTS_TIP"])

    -- Who may show a toast
    y = AddHeader(ct, y - 6, L["CFG_TOAST_SOURCES_HDR"])
    for _, src in ipairs({
        { "situation", "CFG_TOAST_SRC_SITUATION", "CFG_TOAST_SRC_SITUATION_TIP",
          function() return BNB.SituationsEnabled() end },
        { "tasks", "CFG_TOAST_SRC_TASKS", "CFG_TOAST_SRC_TASKS_TIP",
          function() return BNB.SituationsEnabled() and BNB.TasksEnabled() end },
        -- Alarm toasts (ALL-385): off = alarms use the alarm window
        { "alarms", "CFG_TOAST_SRC_ALARMS", "CFG_TOAST_SRC_ALARMS_TIP",
          function() return BNB.AlarmsEnabled() end },
    }) do
        local key = src[1]
        local box
        y, box = AddCheck(ct, y, L[src[2]],
            function() return BNB.ToastSourceOn(key) end,
            function(v)
                db.toastSources = db.toastSources or {}
                db.toastSources[key] = v
                if BNB.ApplyToastSource then BNB.ApplyToastSource(key, v) end
            end,
            L[src[3]])
        srcBoxes[#srcBoxes + 1] = { cb = box, need = src[4] }
    end

    y = AddHeader(ct, y - 6, L["CFG_TOAST_HDR"])

    -- Position + Test, side by side
    local anchorBtn = BNB.CreateButton(nil, ct, L["CFG_TOAST_ANCHOR_BTN"], 150, 22)
    anchorBtn:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
    anchorBtn:SetScript("OnClick", function() BNB.Toast.ToggleAnchor() end)
    Tip(anchorBtn, L["CFG_TOAST_ANCHOR_BTN"], L["CFG_TOAST_ANCHOR_TIP"])
    local testBtn = BNB.CreateButton(nil, ct, L["CFG_TOAST_TEST_BTN"], 80, 22)
    testBtn:SetPoint("LEFT", anchorBtn, "RIGHT", 6, 0)
    testBtn:SetScript("OnClick", function()
        if BNB.TestSituationToasts then BNB.TestSituationToasts() end
    end)
    Tip(testBtn, L["CFG_TOAST_TEST_BTN"], L["CFG_TOAST_TEST_TIP"])
    offWidgets[#offWidgets + 1] = anchorBtn
    offWidgets[#offWidgets + 1] = testBtn
    y = y - (22 + 10)

    -- Style (ALL-376 S2): the faction loot toast by default (toastStyle nil);
    -- unticked, the dropdown picks one. Skin colour only while skin mode is on.
    local TS = BNB.ToastStyles
    local styleEntries = {}
    local function FillStyles()
        wipe(styleEntries)
        for _, e in ipairs(TS.List()) do
            if e.key ~= "faction" then styleEntries[#styleEntries + 1] = { label = e.label, value = e.key } end
        end
    end
    FillStyles()
    local styleDd
    local facCb
    y, facCb = AddCheck(ct, y, L["CFG_TOAST_FACTION"],
        function() return db.toastStyle == nil or db.toastStyle == "faction" end,
        function(v)
            if v then
                db.toastStyle = nil
            else
                -- Off: start from the toast this character sees now
                local cur = TS.Resolve(nil)
                db.toastStyle = cur and cur.key or "plain"
            end
            if styleDd then
                styleDd:SetSelected(db.toastStyle or TS.Resolve(nil).key)
                if styleDd._dd then styleDd._dd:SetEnabled(not v) end
            end
            BNB.Toast.Restyle()
        end,
        L["CFG_TOAST_FACTION_TIP"])
    offWidgets[#offWidgets + 1] = facCb
    offLabels[#offLabels + 1]   = facCb._lbl
    do
        local lbl = ct:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        lbl:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
        lbl:SetHeight(ROW_H); lbl:SetJustifyH("LEFT")
        lbl:SetText(L["CFG_TOAST_STYLE"])
        y = y - (ROW_H + 2)
        styleDd = BNB.CreateValueDropdown(ct, styleEntries, db.toastStyle or TS.Resolve(nil).key,
            function(v) db.toastStyle = v; BNB.Toast.Restyle() end, CONTENT_W, 26)
        styleDd:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
        Tip(styleDd._dd or styleDd, L["CFG_TOAST_STYLE"], L["CFG_TOAST_STYLE_TIP"])
        offLabels[#offLabels + 1] = lbl
        y = y - (32 + ROW_GAP)
        -- Skin mode may have changed since: the list and the greying follow
        sf:HookScript("OnShow", function()
            FillStyles()
            local follow = db.toastStyle == nil or db.toastStyle == "faction"
            styleDd:SetSelected(db.toastStyle or TS.Resolve(nil).key)
            if styleDd._dd then styleDd._dd:SetEnabled(follow == false and BNB.ToastsEnabled()) end
        end)
    end

    local scaleSl
    y, scaleSl = AddSlider(ct, y, L["CFG_TOAST_SCALE"], 50, 150,
        function() return math.floor((db.toastScale or BNB.DEFAULTS.toastScale) * 100 + 0.5) end,
        function(v) db.toastScale = v / 100; BNB.Toast.Restyle() end,
        L["CFG_TOAST_SCALE_TIP"], BNB.DEFAULTS.toastScale * 100,
        function(v) return string.format("%d%%", v) end)
    offWidgets[#offWidgets + 1] = scaleSl

    AddDrop("CFG_TOAST_LAYOUT", "CFG_TOAST_LAYOUT_TIP", {
        { label = L["CFG_TOAST_LAYOUT_EACH"],  value = "each" },
        { label = L["CFG_TOAST_LAYOUT_GROUP"], value = "group" },
    }, "toastLayout", function() BNB.Toast.DismissAll("test") end)
    AddDrop("CFG_TOAST_GROW", "CFG_TOAST_GROW_TIP", {
        { label = L["CFG_TOAST_GROW_DOWN"],  value = "down" },
        { label = L["CFG_TOAST_GROW_UP"],    value = "up" },
        { label = L["CFG_TOAST_GROW_LEFT"],  value = "left" },
        { label = L["CFG_TOAST_GROW_RIGHT"], value = "right" },
    }, "toastGrow", ToastChanged)
    AddDrop("CFG_TOAST_COMBAT", "CFG_TOAST_COMBAT_TIP", {
        { label = L["CFG_TOAST_COMBAT_SHOW"], value = "show" },
        { label = L["CFG_TOAST_COMBAT_WAIT"], value = "wait" },
        { label = L["CFG_TOAST_COMBAT_DROP"], value = "drop" },
    }, "toastCombat")

    local maxSl
    y, maxSl = AddSlider(ct, y, L["CFG_TOAST_MAX"], 1, 10,
        function() return db.toastMax or BNB.DEFAULTS.toastMax end,
        function(v) db.toastMax = v; ToastChanged() end,
        L["CFG_TOAST_MAX_TIP"], BNB.DEFAULTS.toastMax)
    offWidgets[#offWidgets + 1] = maxSl

    -- Hold time slider
    local holdSl
    y, holdSl = AddSlider(ct, y, L["CFG_SLIDER_ALERT_SECONDS"], 0, 60,
        function() return db.popupHoldTime or BNB.DEFAULTS.popupHoldTime end,
        function(v) db.popupHoldTime = v end,
        L["CFG_SLIDER_ALERT_SECONDS_TIP"], BNB.DEFAULTS.popupHoldTime)
    offWidgets[#offWidgets + 1] = holdSl

    local slideCb
    y, slideCb = AddCheck(ct, y, L["CFG_TOAST_SLIDE"],
        function() return db.toastSlide ~= false end,
        function(v) db.toastSlide = v; ToastChanged() end,
        L["CFG_TOAST_SLIDE_TIP"])
    offWidgets[#offWidgets + 1] = slideCb
    offLabels[#offLabels + 1]   = slideCb._lbl

    -- Sound (S3): nil = none; the alarm sounds, played once per burst
    do
        local entries = {
            { label = L["AW_SND_SILENT"],      value = "silent" },
            { label = L["AW_SND_DEFAULT"],     value = "default" },
            { label = L["AW_SND_DOUBLE_HIT"],  value = "sound01" },
            { label = L["AW_SND_LONG_POP"],    value = "sound02" },
            { label = L["AW_SND_MAGIC"],       value = "sound03" },
            { label = L["AW_SND_SCREAM"],      value = "sound04" },
            { label = L["AW_SND_YELL"],        value = "sound05" },
            { label = L["AW_SND_TRIPLE_HIT"],  value = "sound06" },
            { label = L["AW_SND_DRUM_DING"],   value = "sound07" },
            { label = L["AW_SND_XYLOPHONE"],   value = "sound08" },
            { label = L["AW_SND_TADA"],        value = "sound09" },
            { label = L["AW_SND_SOFT_DINGS"],  value = "sound10" },
        }
        local lbl = ct:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        lbl:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
        lbl:SetHeight(ROW_H); lbl:SetJustifyH("LEFT")
        lbl:SetText(L["CFG_TOAST_SOUND"])
        y = y - (ROW_H + 2)
        local ddW = CONTENT_W - 66
        local dd = BNB.CreateValueDropdown(ct, entries, db.toastSound or "silent",
            function(v) db.toastSound = (v ~= "silent") and v or nil end, ddW, 26)
        dd:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
        Tip(dd._dd or dd, L["CFG_TOAST_SOUND"], L["CFG_TOAST_SOUND_TIP"])
        local play = BNB.CreateButton(nil, ct, L["CFG_TOAST_SOUND_TEST"], 60, 24)
        play:SetPoint("LEFT", dd, "RIGHT", 6, 0)
        play:SetScript("OnClick", function()
            local key = dd:GetSelected()
            local path = key ~= "silent" and BNB.Alarm and BNB.Alarm.SoundPath(key)
            if path then PlaySoundFile(path, "Master") end
        end)
        offWidgets[#offWidgets + 1] = dd._dd or dd
        offWidgets[#offWidgets + 1] = play
        offLabels[#offLabels + 1]   = lbl
        y = y - (32 + ROW_GAP)
    end

    -- What each note toast shows (S3)
    do
        local hdr = ct:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        hdr:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
        hdr:SetHeight(ROW_H); hdr:SetJustifyH("LEFT")
        hdr:SetText(L["CFG_TOAST_SHOW_HDR"])
        offLabels[#offLabels + 1] = hdr
        y = y - (ROW_H + 2)
        for _, part in ipairs({
            { "toastShowIcon",    L["CFG_TOAST_SHOW_ICON"],    L["CFG_TOAST_SHOW_ICON_TIP"] },
            { "toastShowWhy",     L["CFG_TOAST_SHOW_WHY"],     L["CFG_TOAST_SHOW_WHY_TIP"] },
            { "toastShowSummary", L["CFG_TOAST_SHOW_SUMMARY"], L["CFG_TOAST_SHOW_SUMMARY_TIP"] },
            { "toastShowPin",     L["CFG_TOAST_SHOW_PIN"],     L["CFG_TOAST_SHOW_PIN_TIP"] },
        }) do
            local key = part[1]
            local cb
            y, cb = AddCheck(ct, y, part[2],
                function() return db[key] ~= false end,
                function(v) db[key] = v end,
                part[3])
            offWidgets[#offWidgets + 1] = cb
            offLabels[#offLabels + 1]   = cb._lbl
        end
    end
    GreyOff()
    sf:HookScript("OnShow", GreyOff)   -- switched from the overview row or a mode badge
    page.enableCb = cb   -- twin on the Features overview row
    sf:FinaliseHeight(math.abs(y) + 12)
end

local function BuildModulesTab(sf, ct)
    local y  = -8

    -- Optional 4th field: the page's key for BNB.OpenSettingsPage. 5th: the
    -- module switch's key in BNB.ModuleUsage.list (UI/SetupWizard.lua), for the
    -- mode badges at the top (ALL-358).
    local MODULES = {
        { L["CFG_HDR_ORACLE"],         L["CFG_SUB_ORACLE_DESC"],     K.BuildOraclePage, "oracle", "oracle" },   -- UI/Config/OracleSettings.lua
        { L["CFG_CELL_STICKY_HDR"],    L["CFG_SUB_STICKY_DESC"],     BuildStickyPage,   nil, "stickies"  },
        { L["CFG_HDR_TASKS"],          L["CFG_SUB_TASKS_DESC"],      BuildTasksPage,    nil, "tasks"     },
        { L["CFG_HDR_REFBOX"],         L["CFG_SUB_REFBOX_DESC"],     BuildRefBoxPage,   nil, "refBox"    },
        { L["CFG_HDR_SIDEBAR"],        L["CFG_SUB_SIDEBAR_DESC"],    BuildSidebarPage,  nil, "sidebar"   },
        { L["CFG_FOCUS_ORBIT_HEADER"], L["CFG_SUB_FOCUS_DESC"],      BuildFocusPage,    nil, "focus"     },
        -- UI/Config/NotePages.lua (ALL-290)
        { L["CFG_RICH_SIZES_HEADER"],  L["CFG_SUB_RICH_DESC"],       K.BuildRichNotesPage, "richNotes", "rich"    },
        { L["CFG_HDR_NOTE_HISTORY"],   L["CFG_SUB_HISTORY_DESC"],    K.BuildHistoryPage,   "history",   "history" },
        { L["CFG_HDR_TRASH"],          L["CFG_SUB_TRASH_DESC"],      K.BuildTrashPage,     "trash",     "trash"   },
        { L["CFG_HDR_ALARMS"],         L["CFG_SUB_ALARMS_DESC"],     K.BuildAlarmsPage,    "alarms",    "alarms"  },
        { L["CFG_HDR_QUICK_NOTE"],     L["CFG_SUB_QN_DESC"],         BuildQuickNotePage,    nil, "quickNote" },
        { L["CFG_SUB_PLAYER_NPC"],     L["CFG_SUB_PLAYER_NPC_DESC"], BuildPlayerNpcPage,    nil, "unitNotes" },
        { L["CFG_HDR_CONTEXT_POPUP"],  L["CFG_SUB_CONTEXT_DESC"],    BuildContextPopupPage, "situations", "context" },
        { L["CFG_HDR_TOASTS"],         L["CFG_SUB_TOASTS_DESC"],     BuildToastsPage,       "toasts",     "toasts"  },
        { L["CFG_HDR_CONTEXT_MENU"],   L["CFG_SUB_CONTEXT_MENU_DESC"], K.BuildContextMenuPage, "contextMenu" },   -- UI/Config/ContextMenuSettings.lua
        { L["CFG_HDR_PLACEMENT"],      L["CFG_SUB_PLACEMENT_DESC"],  K.BuildPlacementPage, "placement" },   -- UI/Config/NotePages.lua (ALL-291)
    }
    -- Alphabetical by the shown title, in the active language (Dukul 2026-10-06,
    -- ALL-331); colour codes left out of the compare
    local function SortKey(t)
        return ((t or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")):lower()
    end
    -- Modules with an on/off switch first; pages with settings only (no
    -- switch: Right-click menu, Window placement) after them under their own
    -- heading (Dukul 2026-10-07)
    table.sort(MODULES, function(a, b)
        if (a[5] ~= nil) ~= (b[5] ~= nil) then return a[5] ~= nil end
        return SortKey(a[1]) < SortKey(b[1])
    end)
    -- Mode badges (ALL-358): Minimal / Full / Custom, the set the module
    -- switches match now; Custom = neither. Built first, filled after the rows.
    local MU = BNB.ModuleUsage
    local pages, badges = {}, {}
    local function RefreshModes()
        local cur = MU.Match() or "custom"
        for _, b in ipairs(badges) do b:SetSelected(b._mode == cur) end
    end
    -- A preset presses each changed module's own checkbox, so its page greys
    -- and applies exactly as a click there would
    local function ApplyPreset(mode)
        local want = MU.Wants(mode)
        for _, m in ipairs(MU.list) do
            local page = pages[m.key]
            local cb = page and page.enableCb
            if m.get() ~= want[m.key] then
                if cb then
                    cb:SetChecked(want[m.key])
                    local fn = cb:GetScript("OnClick")
                    if fn then fn(cb, "LeftButton") end
                    if page._ov then page._ov:SetChecked(want[m.key]) end
                else
                    m.set(want[m.key])
                end
            end
        end
        RefreshModes()
    end
    local BADGE, BADGE_GAP = 96, 28
    local bx = math.floor((CONTENT_W - BADGE * 3 - BADGE_GAP * 2) / 2)
    for i, mode in ipairs({ "minimal", "everything", "custom" }) do
        local extra
        if mode == "custom" then
            extra = L["CFG_MODE_CUSTOM_TIP"]
        else
            extra = function()
                return (MU.Match() == mode) and L["CFG_MODE_CURRENT_TIP"] or L["CFG_MODE_CLICK_TIP"]
            end
        end
        local b = MU.CreateBadge(ct, BADGE, mode, extra)
        b:SetPoint("TOPLEFT", ct, "TOPLEFT", bx + (i - 1) * (BADGE + BADGE_GAP), y)
        if mode ~= "custom" then
            b:SetScript("OnClick", function()
                if MU.Match() == mode then return end
                local n = 0
                local want = MU.Wants(mode)
                for _, m in ipairs(MU.list) do if m.get() ~= want[m.key] then n = n + 1 end end
                StaticPopup_Show("BNB_MULTI_CONFIRM",
                    string.format(L["CFG_MODE_CONFIRM_FMT"], L[MU.TitleKey[mode]], n), nil,
                    function() ApplyPreset(mode) end)
            end)
        end
        badges[#badges + 1] = b
    end
    y = AddRule(ct, y - BADGE - 10) - 4

    local otherHdr = false
    for _, m in ipairs(MODULES) do
        if not m[5] and not otherHdr then
            otherHdr = true
            y = AddRule(ct, y - 4) - 6
            y = AddHeader(ct, y, L["CFG_MODULES_OTHER_HDR"])
        end
        local page = K.NewSubPage(m[1], m[3], m[4])
        y = K.AddOverviewRow(ct, sf, y, page, m[1], m[2])
        if m[5] then
            pages[m[5]] = page
            -- Any switch by hand moves the selected badge
            if page.enableCb then page.enableCb:HookScript("OnClick", RefreshModes) end
            if page._ov then page._ov:HookScript("OnClick", RefreshModes) end
        end
    end
    sf:HookScript("OnShow", RefreshModes)
    RefreshModes()

    -- The "Icons" row (all game icons on / off) went (ALL-331): the icon
    -- picker's "All game icons" box sets the same blizzardIconComplete.

    sf:FinaliseHeight(math.abs(y) + 12)
end

K.BUILDERS.modules = BuildModulesTab

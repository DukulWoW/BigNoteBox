-- BigNoteBox UI/Config/OracleSettings.lua - Settings > Modules > Oracle search (ALL-69.4)
-- The Oracle bar's sub-page: on/off, keybinding, Look (theme, results shown),
-- Position (move / preview, reset), Behaviour (open mode, close after
-- opening, ranking weights). Built by UI/Config/Modules.lua through
-- K.BuildOraclePage; opened from outside with BNB.OpenSettingsPage("modules", "oracle")
-- (a right-click on the bar). The settings keys are listed in UI/Oracle.lua.

local BNB = BigNoteBox
local L   = BNB.L

local K = BNB._ConfigKit
local CONTENT_W, ROW_H, ROW_GAP, SLIDER_H = K.CONTENT_W, K.ROW_H, K.ROW_GAP, K.SLIDER_H
local AddRule, AddHeader, AddCheck = K.AddRule, K.AddHeader, K.AddCheck

-- Built-in theme names are translated; a theme from another addon shows its own name.
local THEME_NAME_KEY = {
    kilrogg  = "SEARCH_THEME_KILROGG",
    alliance = "SEARCH_THEME_ALLIANCE",
    horde    = "SEARCH_THEME_HORDE",
    ["the-eye"] = "SEARCH_THEME_THE_EYE",
}
local function ThemeName(id)
    local t = BNB.GetSearchTheme(id)
    if not t then return "" end
    local key = THEME_NAME_KEY[t.id]
    return key and L[key] or t.name
end

-- Ranking rows, in the order shown; keys are OracleSearch.WEIGHT_DEFAULTS'.
local WEIGHTS = {
    { key = "target", label = "CFG_ORACLE_W_TARGET" },
    { key = "char",   label = "CFG_ORACLE_W_CHAR"   },
    { key = "zone",   label = "CFG_ORACLE_W_ZONE"   },
    { key = "fav",    label = "CFG_ORACLE_W_FAV"    },
    { key = "opened", label = "CFG_ORACLE_W_OPENED" },
    { key = "edited", label = "CFG_ORACLE_W_EDITED" },
    { key = "alarm",  label = "CFG_ORACLE_W_ALARM"  },
}
local LEVEL_KEY = {
    off = "CFG_ORACLE_LVL_OFF", low = "CFG_ORACLE_LVL_LOW",
    normal = "CFG_ORACLE_LVL_NORMAL", high = "CFG_ORACLE_LVL_HIGH",
}

local DD_H     = 22
local WEIGHT_W = 130   -- level dropdown width

local function Tip(w, text)
    w:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(text, 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    w:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

local function Label(ct, y, text)
    local fs = ct:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    fs:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
    fs:SetHeight(ROW_H); fs:SetJustifyH("LEFT")
    fs:SetText(text)
    return fs
end

local function BuildOraclePage(sf, ct, y, page)
    local db = BigNoteBoxDB
    local Oracle = BNB.Oracle
    local OS = BNB.OracleSearch
    local widgets = {}   -- greyed while the module is off

    -- ── On / off ──────────────────────────────────────────────────────────────
    local enableCb = CreateFrame("CheckButton", nil, ct, "UICheckButtonTemplate")
    enableCb:SetSize(24, 24)
    enableCb:SetPoint("TOPLEFT", ct, "TOPLEFT", -2, y + 2)
    enableCb:SetChecked(db.oracleEnabled ~= false)
    Tip(enableCb, L["CFG_ORACLE_ENABLE_TIP"])
    page.enableCb = enableCb   -- twin on the Modules overview row
    local enableLbl = ct:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    enableLbl:SetPoint("LEFT", enableCb, "RIGHT", 4, 0)
    enableLbl:SetPoint("RIGHT", ct, "RIGHT", 0, 0)
    enableLbl:SetJustifyH("LEFT"); enableLbl:SetHeight(ROW_H)
    enableLbl:SetText(L["CFG_ORACLE_ENABLE_LABEL"])
    y = y - (ROW_H + ROW_GAP)

    local rcHint = BNB.CreateSmallLabel(ct, L["CFG_ORACLE_RIGHTCLICK_HINT"], y, CONTENT_W)
    y = y - rcHint:GetStringHeight() - 10

    y = K.MakeKeybindPair(ct, y, {
        { label = L["CFG_KB_ORACLE"], action = "BIGNOTEBOXORACLE",
          defaultKey = "CTRL-SPACE", verb = L["CFG_KB_DESC_ORACLE"] },
    })

    -- ── Look ──────────────────────────────────────────────────────────────────
    y = AddRule(ct, y) - 4
    y = AddHeader(ct, y, L["CFG_ORACLE_HDR_LOOK"])

    Label(ct, y, L["CFG_ORACLE_THEME_LABEL"])
    y = y - (ROW_H - 4)
    -- "" = follow the character's faction (oracleTheme nil)
    local themes = { { label = string.format(L["CFG_ORACLE_THEME_FACTION_FMT"],
        ThemeName(Oracle.FactionTheme())), value = "" } }
    for _, id in ipairs(BNB.SEARCH_THEME_ORDER) do
        if not BNB.SEARCH_THEMES[id].hidden then
            themes[#themes + 1] = { label = ThemeName(id), value = id }
        end
    end
    local themeDD = BNB.CreateValueDropdown(ct, themes, db.oracleTheme or "", function(v)
        db.oracleTheme = (v ~= "") and v or nil
        Oracle.RefreshPreview()
    end, CONTENT_W, DD_H)
    themeDD:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
    widgets[#widgets + 1] = themeDD
    y = y - (DD_H + ROW_GAP + 4)

    local maxSl = BNB.CreateSlider(ct, L["CFG_ORACLE_MAX_ROWS"], 1, Oracle.MAX_ROWS,
        db.oracleMaxResults or Oracle.MAX_ROWS, nil, function(v)
            db.oracleMaxResults = v
            Oracle.RefreshPreview()
        end)
    maxSl:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
    maxSl:SetWidth(CONTENT_W)
    Tip(maxSl, L["CFG_ORACLE_MAX_ROWS_TIP"])
    widgets[#widgets + 1] = maxSl
    y = y - (SLIDER_H + ROW_GAP)

    -- ── Position ──────────────────────────────────────────────────────────────
    y = AddRule(ct, y) - 4
    y = AddHeader(ct, y, L["CFG_ORACLE_HDR_POSITION"])

    local moveBtn = BNB.CreateButton(nil, ct, L["CFG_ORACLE_MOVE_BTN"], 150, DD_H)
    moveBtn:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
    moveBtn:SetScript("OnClick", function()
        if Oracle.IsPreviewing() then Oracle.EndPreview() else Oracle.StartPreview() end
    end)
    Tip(moveBtn, L["CFG_ORACLE_MOVE_TIP"])
    widgets[#widgets + 1] = moveBtn

    local resetBtn = BNB.CreateButton(nil, ct, L["CFG_ORACLE_RESET_BTN"], 150, DD_H)
    resetBtn:SetPoint("LEFT", moveBtn, "RIGHT", 8, 0)
    resetBtn:SetScript("OnClick", function() Oracle.ResetPosition() end)
    Tip(resetBtn, L["CFG_ORACLE_RESET_TIP"])
    widgets[#widgets + 1] = resetBtn
    y = y - (DD_H + ROW_GAP + 4)

    -- The preview never outlives the page (back, another tab, window closed).
    sf:HookScript("OnHide", function() Oracle.EndPreview() end)

    -- ── Behaviour ─────────────────────────────────────────────────────────────
    y = AddRule(ct, y) - 4
    y = AddHeader(ct, y, L["CFG_ORACLE_HDR_BEHAVIOUR"])

    Label(ct, y, L["CFG_ORACLE_OPEN_MODE_LABEL"])
    y = y - (ROW_H - 4)
    local modeDD = BNB.CreateValueDropdown(ct, {
        { label = L["CFG_ORACLE_OPEN_JUST"],  value = "open"  },
        { label = L["CFG_ORACLE_OPEN_PLAIN"], value = "plain" },
        { label = L["CFG_ORACLE_OPEN_ALL"],   value = "all"   },
    }, db.oracleOpenMode or "plain", function(v)
        db.oracleOpenMode = (v ~= "plain") and v or nil
    end, CONTENT_W, DD_H)
    modeDD:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
    Tip(modeDD._dd or modeDD, L["CFG_ORACLE_OPEN_MODE_TIP"])
    widgets[#widgets + 1] = modeDD
    y = y - (DD_H + ROW_GAP + 4)

    local closeCb
    y, closeCb = AddCheck(ct, y, L["CFG_ORACLE_CLOSE_AFTER"],
        function() return db.oracleKeepOpen ~= true end,
        function(v) db.oracleKeepOpen = (not v) or nil end,
        L["CFG_ORACLE_CLOSE_AFTER_TIP"])
    widgets[#widgets + 1] = closeCb

    -- Ranking: one level per boost, nil = OracleSearch's default.
    y = y - 4
    local rankHdr = BNB.CreateSectionHeader(ct, L["CFG_ORACLE_HDR_RANKING"], y, CONTENT_W)
    y = y - rankHdr:GetStringHeight() - 4
    local rankDesc = BNB.CreateSmallLabel(ct, L["CFG_ORACLE_RANKING_DESC"], y, CONTENT_W)
    rankDesc:SetWordWrap(true)
    y = y - rankDesc:GetStringHeight() - 8

    local levels = {}
    for _, lvl in ipairs(OS.WEIGHT_LEVELS) do
        levels[#levels + 1] = { label = L[LEVEL_KEY[lvl]], value = lvl }
    end
    local weightDDs = {}
    for _, w in ipairs(WEIGHTS) do
        local key = w.key
        local lbl = ct:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        lbl:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y - 4)
        lbl:SetWidth(CONTENT_W - WEIGHT_W - 8); lbl:SetJustifyH("LEFT")
        lbl:SetWordWrap(false)
        lbl:SetText(L[w.label])
        local cur = (db.oracleWeights and db.oracleWeights[key]) or OS.WEIGHT_DEFAULTS[key]
        local dd = BNB.CreateValueDropdown(ct, levels, cur, function(v)
            local def = OS.WEIGHT_DEFAULTS[key]
            db.oracleWeights = db.oracleWeights or {}
            db.oracleWeights[key] = (v ~= def) and v or nil
            if next(db.oracleWeights) == nil then db.oracleWeights = nil end
        end, WEIGHT_W, DD_H)
        dd:SetPoint("TOPLEFT", ct, "TOPLEFT", CONTENT_W - WEIGHT_W, y)
        widgets[#widgets + 1] = dd
        weightDDs[key] = dd
        y = y - (DD_H + 4)
    end
    y = y - 4

    local resetW = BNB.CreateButton(nil, ct, L["CFG_ORACLE_RESET_WEIGHTS"], 150, DD_H)
    resetW:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
    resetW:SetScript("OnClick", function()
        db.oracleWeights = nil
        for key, dd in pairs(weightDDs) do dd:SetSelected(OS.WEIGHT_DEFAULTS[key]) end
    end)
    widgets[#widgets + 1] = resetW
    y = y - (DD_H + ROW_GAP)

    -- ── Enable state ──────────────────────────────────────────────────────────
    local function ApplyEnabled(on)
        for _, w in ipairs(widgets) do
            w:SetAlpha(on and 1 or 0.35)
            local t = w._dd or w.Slider or w   -- value dropdown, slider, button
            if t.SetEnabled then t:SetEnabled(on) end
        end
    end
    enableCb:SetScript("OnClick", function(self)
        if self:GetChecked() then
            db.oracleEnabled = nil
        else
            db.oracleEnabled = false
            Oracle.EndPreview()
            Oracle.Close()
        end
        ApplyEnabled(db.oracleEnabled ~= false)
    end)
    ApplyEnabled(db.oracleEnabled ~= false)

    sf:FinaliseHeight(math.abs(y) + 12)
end

K.BuildOraclePage = BuildOraclePage

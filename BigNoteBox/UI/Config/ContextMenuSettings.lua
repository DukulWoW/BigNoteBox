-- BigNoteBox UI/Config/ContextMenuSettings.lua - Settings > Modules > Right-click menu (ALL-148)
-- The note right-click menu's sub-page: what a click on each main item does
-- (Open note / Create / Actions / History: one of its sub-menu entries, or
-- only open the sub-menu) and the hover delay before a sub-menu opens, with
-- a sample menu to try it. No off switch: the menu is always there (Dukul).
-- Built by UI/Config/Modules.lua through K.BuildContextMenuPage. The choices
-- come from BNB.NOTE_MENU_CLICKS (UI/NoteContextMenu.lua), the saved keys are
-- BigNoteBoxDB.contextMenuClick / contextMenuDelay (BNB.DEFAULTS).

local BNB = BigNoteBox
local L   = BNB.L

local K = BNB._ConfigKit
local CONTENT_W, ROW_H, ROW_GAP, SLIDER_H = K.CONTENT_W, K.ROW_H, K.ROW_GAP, K.SLIDER_H
local AddRule, AddHeader = K.AddRule, K.AddHeader

local DD_H = 26

local function Plain(s)
    return (s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
end

local function Desc(ct, y, text)
    local fs = ct:CreateFontString(nil, "OVERLAY", "BNBFontHighlightSmall")
    fs:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
    fs:SetWidth(CONTENT_W)
    fs:SetJustifyH("LEFT")
    fs:SetText(text)
    return y - fs:GetStringHeight() - 8
end

function K.BuildContextMenuPage(sf, ct, y)
    local db = BigNoteBoxDB

    -- ── Click on a main item ─────────────────────────────────────────────────
    y = AddHeader(ct, y, L["CFG_CM_HDR_CLICK"])
    y = Desc(ct, y, L["CFG_CM_CLICK_DESC"])

    db.contextMenuClick = db.contextMenuClick or CopyTable(BNB.DEFAULTS.contextMenuClick)
    for _, m in ipairs(BNB.NOTE_MENU_CLICKS) do
        local item = m[1]
        local lbl = ct:CreateFontString(nil, "OVERLAY", "BNBFontNormal")
        lbl:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
        lbl:SetHeight(ROW_H); lbl:SetJustifyH("LEFT")
        lbl:SetText(L[m[2]])
        y = y - (ROW_H + 2)

        local entries = { { label = L["CFG_CM_CLICK_MENU"], value = "menu" } }
        for _, e in ipairs(m[4]) do
            entries[#entries + 1] = { label = Plain(L[e[2]]), value = e[1] }
        end
        local cur = db.contextMenuClick[item] or BNB.DEFAULTS.contextMenuClick[item]
        local dd = BNB.CreateValueDropdown(ct, entries, cur,
            function(v) db.contextMenuClick[item] = v end, CONTENT_W, DD_H)
        dd:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
        y = y - (DD_H + ROW_GAP + 4)
    end

    -- ── Sub-menus ────────────────────────────────────────────────────────────
    y = AddRule(ct, y - 4)
    y = AddHeader(ct, y, L["CFG_CM_HDR_SUBMENUS"])

    local sl = BNB.CreateStackedSlider(ct, CONTENT_W, {
        label = L["CFG_CM_DELAY"], min = 0, max = 0.5, step = 0.05,
        value = db.contextMenuDelay or BNB.DEFAULTS.contextMenuDelay,
        default = BNB.DEFAULTS.contextMenuDelay,
        fmt = function(v) return string.format("%.2f s", v) end,
        onChange = function(v) db.contextMenuDelay = v end,
        tip = L["CFG_CM_DELAY_TIP"],
    })
    sl:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
    y = y - (SLIDER_H + ROW_GAP)

    -- Try it: a sample menu with the settings above, at the pointer (Dukul, L3)
    local tryBtn = BNB.CreateButton(nil, ct, L["CFG_CM_TRY"], 150, 22)
    tryBtn:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
    tryBtn:SetScript("OnClick", function(self) BNB.ShowSampleNoteMenu(self) end)
    tryBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(L["CFG_CM_TRY"], 1, 1, 1)
        GameTooltip:AddLine(L["CFG_CM_TRY_TIP"], 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    tryBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    y = y - (22 + ROW_GAP)

    sf:FinaliseHeight(math.abs(y) + 12)
end

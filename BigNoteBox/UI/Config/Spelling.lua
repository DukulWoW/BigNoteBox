-- BigNoteBox UI/Config/Spelling.lua - Settings > Modules > Spelling (ALL-559)
--
-- The spellchecker's page: the module switch, the language, when to check,
-- and whether capitalized words count as names. A line under the switch says
-- whether the word lists (BigNoteBox_Spell) are there. The checker itself is
-- Features/Spellcheck.lua.

local BNB = BigNoteBox
local L   = BNB.L

local K = BNB._ConfigKit
local ROW_H = K.ROW_H
local AddCheck = K.AddCheck

-- A label and a dropdown under it, as the Explorer view page. choices =
-- { { value, locale key }, ... }; -> y, dropdown, label
local function AddChoice(ct, y, label, tip, choices, get, set)
    local lbl = ct:CreateFontString(nil, "OVERLAY", "BNBFontNormal")
    lbl:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
    lbl:SetHeight(ROW_H); lbl:SetJustifyH("LEFT")
    lbl:SetText(label)
    y = y - (ROW_H + 2)
    local dd = BNB.SkinDropdown(CreateFrame("DropdownButton", nil, ct, "WowStyle1DropdownTemplate"))
    dd:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
    dd:SetWidth(260)
    dd:SetupMenu(function(_, root)
        for _, c in ipairs(choices) do
            local v = c[1]
            root:CreateRadio(L[c[2]], function() return get() == v end, function() set(v) end)
        end
    end)
    dd:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(label, 1, 1, 1)
        GameTooltip:AddLine(tip, 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    dd:HookScript("OnLeave", function() GameTooltip:Hide() end)
    lbl._searchTip = tip
    return y - 32, dd, lbl
end

function K.BuildSpellPage(sf, ct, y, page)
    local db = BigNoteBoxDB
    local SP = BNB.Spell
    local greyed = {}   -- { widget, label } greyed while the module is off
    local status

    local function Sync()
        local on = BNB.SpellEnabled()
        for _, g in ipairs(greyed) do
            g[1]:SetEnabled(on); g[1]:SetAlpha(on and 1 or 0.35)
            if g[2] then g[2]:SetAlpha(on and 1 or 0.35) end
        end
        if not status then return end
        if not on then
            status:SetText(L["CFG_SPELL_STATUS_OFF"])
        elseif SP and SP.EnsureLoaded() then
            status:SetText(string.format(L["CFG_SPELL_STATUS_FMT"], SP.WordCount()))
        else
            status:SetText(L["CFG_SPELL_STATUS_MISSING"])
        end
    end
    local function Changed()
        if SP then SP.Reset() end
        Sync()
    end

    -- ── Module switch ───────────────────────────────────────────────────────
    local enableCb
    y, enableCb = AddCheck(ct, y, L["CFG_SPELL_ENABLE_LABEL"],
        function() return BNB.SpellEnabled() end,
        function(v)
            db.spellEnabled = v
            BNB.ApplySpellModule(v)
            Sync()
        end,
        L["CFG_SPELL_ENABLE_TIP"])
    page.enableCb = enableCb   -- twin on the Modules overview row

    -- Are the word lists there (loaded once the module is on)
    status = ct:CreateFontString(nil, "OVERLAY", "BNBFontHighlightSmall")
    status:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y + 2)
    status:SetWidth(K.CONTENT_W); status:SetJustifyH("LEFT"); status:SetWordWrap(true)
    status:SetTextColor(0.65, 0.65, 0.65)
    y = y - 22

    local dd, lbl
    y, dd, lbl = AddChoice(ct, y, L["CFG_SPELL_LANG"], L["CFG_SPELL_LANG_TIP"],
        { { "enUS", "CFG_SPELL_LANG_US" }, { "enGB", "CFG_SPELL_LANG_UK" } },
        function() return SP and SP.Lang() or "enUS" end,
        function(v) db.spellLang = v; Changed() end)
    greyed[#greyed + 1] = { dd, lbl }

    y, dd, lbl = AddChoice(ct, y, L["CFG_SPELL_MODE"],
        string.format(L["CFG_SPELL_MODE_TIP_FMT"], SP and SP.LONG_BYTES or 20000),
        { { "type", "CFG_SPELL_MODE_TYPE" }, { "click", "CFG_SPELL_MODE_CLICK" } },
        function() return db.spellMode == "click" and "click" or "type" end,
        function(v) db.spellMode = v; Changed() end)
    greyed[#greyed + 1] = { dd, lbl }

    local capsCb
    y, capsCb = AddCheck(ct, y, L["CFG_SPELL_SKIP_CAPS"],
        function() return db.spellSkipCaps ~= false end,
        function(v) db.spellSkipCaps = v and true or false; Changed() end,
        L["CFG_SPELL_SKIP_CAPS_TIP"])
    greyed[#greyed + 1] = { capsCb, capsCb._lbl }

    -- What is never checked, in one line
    local note = ct:CreateFontString(nil, "OVERLAY", "BNBFontHighlightSmall")
    note:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y - 4)
    note:SetWidth(K.CONTENT_W); note:SetJustifyH("LEFT"); note:SetWordWrap(true)
    note:SetTextColor(0.65, 0.65, 0.65)
    note:SetText(L["CFG_SPELL_SKIPPED_DESC"])
    local nh = math.ceil(note:GetStringHeight())
    note:SetHeight(nh)
    y = y - nh - 14

    Sync()
    sf:HookScript("OnShow", Sync)
    sf:FinaliseHeight(math.abs(y) + 12)
end

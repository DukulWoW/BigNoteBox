-- BigNoteBox UI/Config/Spelling.lua - Settings > Modules > Spelling (ALL-559)
--
-- The spellchecker's page: the module switch, the language, when to check,
-- the key, what is checked (names, capitals, numbers, repeated words) and
-- your own words as a list. A line under the switch says whether the word
-- lists (BigNoteBox_Spell) are there. The checker itself is
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
            if not g[3] then g[1]:SetEnabled(on) end   -- g[3]: a frame, greyed only
            g[1]:SetAlpha(on and 1 or 0.35)
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

    -- Check spelling key (ALL-567): the same as the toolbar button
    y = K.MakeKeybindRow(ct, y, L["CFG_KB_SPELLCHECK"], "BIGNOTEBOXSPELLCHECK",
        "(" .. string.format(L["SW_KB_DEFAULT_FMT"], "F9") .. ")", L["CFG_KB_SPELLCHECK_TIP"])

    -- ── What is checked (Dukul, 2026-10-25) ─────────────────────────────────
    y = K.AddHeader(ct, y - 4, L["CFG_SPELL_RULES_HDR"])
    local function Rule(label, tip, key, default)
        local cb
        y, cb = AddCheck(ct, y, label,
            function() if db[key] == nil then return default end return db[key] == true end,
            function(v) db[key] = v and true or false; Changed() end,
            tip)
        greyed[#greyed + 1] = { cb, cb._lbl }
    end
    Rule(L["CFG_SPELL_SKIP_CAPS"],   L["CFG_SPELL_SKIP_CAPS_TIP"],   "spellSkipCaps",   true)
    Rule(L["CFG_SPELL_SKIP_UPPER"],  L["CFG_SPELL_SKIP_UPPER_TIP"],  "spellSkipUpper",  false)
    Rule(L["CFG_SPELL_SKIP_DIGITS"], L["CFG_SPELL_SKIP_DIGITS_TIP"], "spellSkipDigits", true)
    Rule(L["CFG_SPELL_REPEATS"],     L["CFG_SPELL_REPEATS_TIP"],     "spellRepeats",    true)

    -- What is never checked, in one line
    local note = ct:CreateFontString(nil, "OVERLAY", "BNBFontHighlightSmall")
    note:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y - 4)
    note:SetWidth(K.CONTENT_W); note:SetJustifyH("LEFT"); note:SetWordWrap(true)
    note:SetTextColor(0.65, 0.65, 0.65)
    note:SetText(L["CFG_SPELL_SKIPPED_DESC"])
    local nh = math.ceil(note:GetStringHeight())
    note:SetHeight(nh)
    y = y - nh - 14

    -- ── Your words (stage 2; a list since 2026-10-25) ────────────────────────
    -- One row per word: hover highlight, click to edit in place (Enter saves,
    -- Esc cancels), X removes it. New words from the field above the list,
    -- Add to dictionary in the editor, the Correct spelling window.
    y = K.AddHeader(ct, y, L["CFG_SPELL_WORDS_HDR"])
    local wdesc = ct:CreateFontString(nil, "OVERLAY", "BNBFontHighlightSmall")
    wdesc:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
    wdesc:SetWidth(K.CONTENT_W); wdesc:SetJustifyH("LEFT"); wdesc:SetWordWrap(true)
    wdesc:SetTextColor(0.65, 0.65, 0.65)
    wdesc:SetText(L["CFG_SPELL_WORDS_DESC"])
    local dh = math.ceil(wdesc:GetStringHeight())
    wdesc:SetHeight(dh)
    y = y - dh - 6

    -- Add a word
    local ADD_W = 90
    local addBg = BNB.CreateBackdropFrame("Frame", nil, ct)
    BNB.SetBackdropDark(addBg)
    addBg:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
    addBg:SetSize(K.CONTENT_W - ADD_W - 8, 24)
    local addEb = CreateFrame("EditBox", nil, addBg)
    addEb:SetPoint("TOPLEFT", addBg, "TOPLEFT", 6, 0)
    addEb:SetPoint("BOTTOMRIGHT", addBg, "BOTTOMRIGHT", -6, 0)
    addEb:SetFontObject("BNBFontNormal")
    addEb:SetAutoFocus(false)
    addEb:SetMaxLetters(60)
    BNB.AddPlaceholder(addEb, L["CFG_SPELL_WORDS_ADD_PH"], 0.4, 0.4, 0.4)
    local addBtn = BNB.CreateButton(nil, ct, L["CFG_SPELL_WORDS_ADD"], ADD_W, 24)
    addBtn:SetPoint("LEFT", addBg, "RIGHT", 8, 0)
    local function AddTyped()
        if not SP then return end
        local w = addEb:GetRealText() or ""
        if not w:match("%S") then return end
        if SP.AddWord(w, true) then
            addEb:SetRealText("")
        elseif w:find("%S%s+%S") or w:find("[|{}]") then
            BNB:Print(L["SPELL_ADD_NOT_WORD"])
        else
            BNB:Print(string.format(L["SPELL_ADD_ALREADY_FMT"], (w:match("^%s*(.-)%s*$"))))
        end
    end
    addBtn:SetScript("OnClick", AddTyped)
    addEb:SetScript("OnEnterPressed", AddTyped)
    addEb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    greyed[#greyed + 1] = { addEb }
    greyed[#greyed + 1] = { addBtn }
    y = y - 24 - 6

    -- The list
    local ROW, VISIBLE = 22, 8
    local LIST_H = ROW * VISIBLE + 8
    local box = BNB.CreateBackdropFrame("Frame", nil, ct)
    BNB.SetBackdropDark(box)
    box:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
    box:SetSize(K.CONTENT_W, LIST_H)
    local lsf = BNB.CreateScrollFrame(nil, box)
    lsf:SetPoint("TOPLEFT", box, "TOPLEFT", 4, -4)
    lsf:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -24, 4)
    local childW = K.CONTENT_W - 28
    local child = CreateFrame("Frame", nil, lsf)
    child:SetSize(childW, 1)
    lsf:SetScrollChild(child)
    local empty = box:CreateFontString(nil, "OVERLAY", "BNBFontNormalSmall")
    empty:SetPoint("TOPLEFT", box, "TOPLEFT", 10, -10)
    empty:SetTextColor(0.45, 0.45, 0.45)
    empty:SetText(L["CFG_SPELL_WORDS_PH"])
    y = y - LIST_H - 4

    local count = ct:CreateFontString(nil, "OVERLAY", "BNBFontHighlightSmall")
    count:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
    count:SetWidth(K.CONTENT_W); count:SetJustifyH("LEFT")
    count:SetTextColor(0.65, 0.65, 0.65)
    y = y - 18

    -- One edit box for the row being edited, laid over that row
    local editEb = CreateFrame("EditBox", nil, child, "BackdropTemplate")
    BNB.EnsureBackdrop(editEb)
    BNB.SetBackdropDark(editEb)
    editEb:SetFontObject("BNBFontNormal")
    editEb:SetAutoFocus(false)
    editEb:SetMaxLetters(60)
    editEb:SetTextInsets(5, 5, 0, 0)
    editEb:Hide()
    local editRow, editOld
    local rows = {}
    local FillWords   -- below

    local function EndEdit(save)
        if not editRow then return end
        local row, old = editRow, editOld
        editRow, editOld = nil, nil
        local new = editEb:GetText() or ""
        editEb:Hide()
        editEb:ClearFocus()
        row._lbl:Show()
        if save and SP and new ~= old then
            if not SP.RenameWord(old, new) then
                BNB:Print(string.format(L["CFG_SPELL_WORDS_RENAME_FAIL_FMT"], (new:match("^%s*(.-)%s*$"))))
            end
        end
        FillWords()
    end
    editEb:SetScript("OnEnterPressed", function() EndEdit(true) end)
    editEb:SetScript("OnEscapePressed", function() EndEdit(false) end)
    editEb:SetScript("OnEditFocusLost", function() EndEdit(true) end)

    local function StartEdit(row)
        if not BNB.SpellEnabled() then return end
        if editRow then EndEdit(true) end
        editRow, editOld = row, row._word
        row._lbl:Hide()
        editEb:ClearAllPoints()
        editEb:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
        editEb:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -26, 0)
        editEb:SetFrameLevel(row:GetFrameLevel() + 5)
        editEb:SetText(row._word)
        editEb:Show()
        editEb:SetFocus()
        editEb:HighlightText()
    end

    local function GetRow(i)
        local row = rows[i]
        if row then return row end
        row = CreateFrame("Button", nil, child)
        row:SetSize(childW, ROW)
        row:SetPoint("TOPLEFT", child, "TOPLEFT", 0, -(i - 1) * ROW)
        row._hover = BNB.CreateListRowArt(row, "hover", { 1, 1, 1, 0.08 })
        local lbl = row:CreateFontString(nil, "OVERLAY", "BNBFontNormal")
        lbl:SetPoint("LEFT", row, "LEFT", 8, 0)
        lbl:SetPoint("RIGHT", row, "RIGHT", -30, 0)
        lbl:SetJustifyH("LEFT"); lbl:SetWordWrap(false)
        BNB.SetTextWhite(lbl, 0.9)
        row._lbl = lbl
        local x = BNB.CreateIconButton(row, 18, "close", { skin = false,
            tip = L["CFG_SPELL_WORDS_REMOVE"], tipAnchor = "ANCHOR_RIGHT",
            onClick = function()
                if SP and row._word and BNB.SpellEnabled() then SP.RemoveWord(row._word) end
            end })
        x:SetPoint("RIGHT", row, "RIGHT", -4, 0)
        row._x = x
        -- The highlight stays while the pointer is on the X too
        local function Hover() row._hover:SetShown(row:IsMouseOver() and BNB.SpellEnabled()) end
        row:SetScript("OnEnter", Hover)
        row:SetScript("OnLeave", Hover)
        x:HookScript("OnEnter", Hover)
        x:HookScript("OnLeave", Hover)
        row:SetScript("OnClick", function() StartEdit(row) end)
        rows[i] = row
        return row
    end

    FillWords = function()
        if not SP then return end
        if editRow then return end   -- never under the writer's hands
        local list = SP.WordList()
        count:SetText(string.format(L["CFG_SPELL_WORDS_COUNT_FMT"], #list))
        for i, w in ipairs(list) do
            local row = GetRow(i)
            row._word = w
            row._lbl:SetText((w:gsub("|", "||")))
            row._hover:Hide()
            row:Show()
        end
        for i = #list + 1, #rows do rows[i]:Hide() end
        child:SetHeight(math.max(1, #list * ROW))
        empty:SetShown(#list == 0)
    end

    sf:HookScript("OnHide", function()
        if editRow then EndEdit(true) end
        if addEb:HasFocus() then addEb:ClearFocus() end
    end)
    sf:HookScript("OnShow", FillWords)
    BNB.RegisterMessage("SpellingPage", "SpellWordsChanged", function()
        if sf:IsVisible() then FillWords() end
    end)
    greyed[#greyed + 1] = { box, nil, true }
    FillWords()

    Sync()
    sf:HookScript("OnShow", Sync)
    sf:FinaliseHeight(math.abs(y) + 12)
end

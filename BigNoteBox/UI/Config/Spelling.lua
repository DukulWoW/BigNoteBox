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

-- ── Text shortcuts (stage 4, Features/TextShortcuts.lua) ─────────────────
-- The switch, an Add row (shortcut + its text) and one row per shortcut:
-- hover highlight, click to edit both in place (Enter saves, Esc cancels,
-- Tab moves between them), X removes it. -> y
local function BuildShortcuts(sf, ct, y, greyed)
    local db = BigNoteBoxDB
    local TS = BNB.TextShortcuts
    if not TS then return y end
    local NAME_W, ADD_W = 110, 90

    y = K.AddHeader(ct, y, L["CFG_SHORTCUTS_HDR"])
    local cb, bang
    local y0 = y
    y, cb = AddCheck(ct, y, L["CFG_SHORTCUTS_ENABLE"],
        function() return db.spellShortcuts ~= false end,
        function(v) db.spellShortcuts = v and true or false end,
        L["CFG_SHORTCUTS_ENABLE_TIP"])
    greyed[#greyed + 1] = { cb, cb._lbl }
    -- "Only with !" on the same row, to the right (ALL-574, Dukul 2026-10-26)
    local BANG_X = 260
    local _
    _, bang = AddCheck(ct, y0, L["CFG_SHORTCUTS_BANG"],
        function() return TS.BangOnly() end,
        function(v)
            db.spellShortcutsBang = v and true or false
            if BNB.Spell then BNB.Spell.Reset() end   -- the names stop / start being known words
        end,
        L["CFG_SHORTCUTS_BANG_TIP"])
    bang:ClearAllPoints()
    bang:SetPoint("TOPLEFT", ct, "TOPLEFT", BANG_X, y0 + 2)
    -- Anchored to the page, never to bang: LabelHit takes the first label
    -- anchored to a checkbox as its label, and bang took this one (its hit
    -- area shrank to nothing, Dukul 2026-11-01)
    cb._lbl:SetPoint("RIGHT", ct, "LEFT", BANG_X - 8, 0)
    greyed[#greyed + 1] = { bang, bang._lbl }

    local desc = ct:CreateFontString(nil, "OVERLAY", "BNBFontHighlightSmall")
    desc:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
    desc:SetWidth(K.CONTENT_W); desc:SetJustifyH("LEFT"); desc:SetWordWrap(true)
    desc:SetTextColor(0.65, 0.65, 0.65)
    desc:SetText(L["CFG_SHORTCUTS_DESC"])
    local dh = math.ceil(desc:GetStringHeight())
    desc:SetHeight(dh)
    y = y - dh - 6

    -- A dark box with an edit box in it
    local function Field(w)
        local bg = BNB.CreateBackdropFrame("Frame", nil, ct)
        BNB.SetBackdropDark(bg)
        bg:SetSize(w, 24)
        local eb = CreateFrame("EditBox", nil, bg)
        eb:SetPoint("TOPLEFT", bg, "TOPLEFT", 6, 0)
        eb:SetPoint("BOTTOMRIGHT", bg, "BOTTOMRIGHT", -6, 0)
        eb:SetFontObject("BNBFontNormal")
        eb:SetAutoFocus(false)
        return bg, eb
    end

    -- Add a shortcut
    local nameBg, nameEb = Field(NAME_W)
    nameBg:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
    nameEb:SetMaxLetters(TS.MAX_NAME)
    BNB.AddPlaceholder(nameEb, L["CFG_SHORTCUTS_NAME_PH"], 0.4, 0.4, 0.4)
    local textBg, textEb = Field(K.CONTENT_W - NAME_W - ADD_W - 16)
    textBg:SetPoint("LEFT", nameBg, "RIGHT", 8, 0)
    textEb:SetMaxLetters(TS.MAX_TEXT)
    BNB.AddPlaceholder(textEb, L["CFG_SHORTCUTS_TEXT_PH"], 0.4, 0.4, 0.4)
    local addBtn = BNB.CreateButton(nil, ct, L["CFG_SPELL_WORDS_ADD"], ADD_W, 24)
    addBtn:SetPoint("LEFT", textBg, "RIGHT", 8, 0)
    local function AddTyped()
        local n, t = nameEb:GetRealText() or "", textEb:GetRealText() or ""
        if not (n:match("%S") or t:match("%S")) then return end
        local ok, err = TS.Set(n, t)
        if ok then
            nameEb:SetRealText(""); textEb:SetRealText("")
            nameEb:ClearFocus(); textEb:ClearFocus()
        else
            BNB:Print(err)
        end
    end
    addBtn:SetScript("OnClick", AddTyped)
    for _, eb in ipairs({ nameEb, textEb }) do
        eb:SetScript("OnEnterPressed", AddTyped)
        eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
        greyed[#greyed + 1] = { eb }
    end
    nameEb:SetScript("OnTabPressed", function() textEb:SetFocus() end)
    textEb:SetScript("OnTabPressed", function() nameEb:SetFocus() end)
    greyed[#greyed + 1] = { addBtn }
    y = y - 24 - 6

    -- The list
    local ROW, VISIBLE = 22, 6
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
    empty:SetText(L["CFG_SHORTCUTS_EMPTY"])
    y = y - LIST_H - 4

    local count = ct:CreateFontString(nil, "OVERLAY", "BNBFontHighlightSmall")
    count:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
    count:SetWidth(K.CONTENT_W); count:SetJustifyH("LEFT")
    count:SetTextColor(0.65, 0.65, 0.65)
    y = y - 18

    -- Two edit boxes for the row being edited, laid over that row
    local function RowEdit(w)
        local eb = CreateFrame("EditBox", nil, child, "BackdropTemplate")
        BNB.EnsureBackdrop(eb)
        BNB.SetBackdropDark(eb)
        eb:SetFontObject("BNBFontNormal")
        eb:SetAutoFocus(false)
        eb:SetTextInsets(5, 5, 0, 0)
        eb:SetHeight(ROW)
        if w then eb:SetWidth(w) end
        eb:Hide()
        return eb
    end
    local editName = RowEdit(NAME_W)
    editName:SetMaxLetters(TS.MAX_NAME)
    local editText = RowEdit()
    editText:SetMaxLetters(TS.MAX_TEXT)
    local editRow
    local rows = {}
    local Fill   -- below

    local function EndEdit(save)
        if not editRow then return end
        local row = editRow
        editRow = nil
        local n, t = editName:GetText() or "", editText:GetText() or ""
        editName:Hide(); editText:Hide()
        editName:ClearFocus(); editText:ClearFocus()
        row._name:Show(); row._text:Show()
        if save and (n ~= row._rec.name or t ~= row._rec.text) then
            local ok, err = TS.Set(n, t, row._rec.name)
            if not ok then BNB:Print(err) end
        end
        Fill()
    end
    -- Saved when the keyboard leaves both boxes (Tab moves between them)
    local function FocusLeft()
        C_Timer.After(0, function()
            if editRow and not (editName:HasFocus() or editText:HasFocus()) then EndEdit(true) end
        end)
    end
    for _, eb in ipairs({ editName, editText }) do
        eb:SetScript("OnEnterPressed", function() EndEdit(true) end)
        eb:SetScript("OnEscapePressed", function() EndEdit(false) end)
        eb:SetScript("OnEditFocusLost", FocusLeft)
    end
    editName:SetScript("OnTabPressed", function() editText:SetFocus() end)
    editText:SetScript("OnTabPressed", function() editName:SetFocus() end)

    local function StartEdit(row)
        if not BNB.SpellEnabled() then return end
        if editRow then EndEdit(true) end
        editRow = row
        row._name:Hide(); row._text:Hide()
        editName:ClearAllPoints()
        editName:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
        editText:ClearAllPoints()
        editText:SetPoint("TOPLEFT", editName, "TOPRIGHT", 4, 0)
        editText:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -26, 0)
        for _, eb in ipairs({ editName, editText }) do
            eb:SetFrameLevel(row:GetFrameLevel() + 5)
            eb:Show()
        end
        editName:SetText(row._rec.name)
        editText:SetText(row._rec.text)
        editText:SetFocus()
        editText:HighlightText()
    end

    local function GetRow(i)
        local row = rows[i]
        if row then return row end
        row = CreateFrame("Button", nil, child)
        row:SetSize(childW, ROW)
        row:SetPoint("TOPLEFT", child, "TOPLEFT", 0, -(i - 1) * ROW)
        row._hover = BNB.CreateListRowArt(row, "hover", { 1, 1, 1, 0.08 })
        local name = row:CreateFontString(nil, "OVERLAY", "BNBFontNormal")
        name:SetPoint("LEFT", row, "LEFT", 8, 0)
        name:SetWidth(NAME_W - 8)
        name:SetJustifyH("LEFT"); name:SetWordWrap(false)
        BNB.SetTextWhite(name, 0.95)
        row._name = name
        local text = row:CreateFontString(nil, "OVERLAY", "BNBFontNormal")
        text:SetPoint("LEFT", row, "LEFT", NAME_W + 4, 0)
        text:SetPoint("RIGHT", row, "RIGHT", -30, 0)
        text:SetJustifyH("LEFT"); text:SetWordWrap(false)
        text:SetTextColor(0.7, 0.7, 0.7)
        row._text = text
        local x = BNB.CreateIconButton(row, 18, "close", { skin = false,
            tip = L["CFG_SHORTCUTS_REMOVE"], tipAnchor = "ANCHOR_RIGHT",
            onClick = function()
                if row._rec and BNB.SpellEnabled() then TS.Delete(row._rec.name) end
            end })
        x:SetPoint("RIGHT", row, "RIGHT", -4, 0)
        x:Hide()
        row._x = x
        -- The X shows only on hover, with the highlight (ALL-577)
        local function Hover()
            local on = row:IsMouseOver() and BNB.SpellEnabled()
            row._hover:SetShown(on); x:SetShown(on)
        end
        row:SetScript("OnEnter", Hover)
        row:SetScript("OnLeave", Hover)
        x:HookScript("OnEnter", Hover)
        x:HookScript("OnLeave", Hover)
        row:SetScript("OnClick", function() StartEdit(row) end)
        rows[i] = row
        return row
    end

    Fill = function()
        if editRow then return end   -- never under the writer's hands
        local list = TS.List()
        count:SetText(string.format(L["CFG_SHORTCUTS_COUNT_FMT"], #list))
        for i, r in ipairs(list) do
            local row = GetRow(i)
            row._rec = r
            row._name:SetText(r.name)
            row._text:SetText(r.text)
            row:Show()
            -- a row that slid under the pointer (one removed above) shows its X at once
            local on = row:IsMouseOver() and BNB.SpellEnabled()
            row._hover:SetShown(on); row._x:SetShown(on)
        end
        for i = #list + 1, #rows do rows[i]:Hide() end
        child:SetHeight(math.max(1, #list * ROW))
        empty:SetShown(#list == 0)
    end

    sf:HookScript("OnHide", function()
        if editRow then EndEdit(true) end
        nameEb:ClearFocus(); textEb:ClearFocus()
    end)
    sf:HookScript("OnShow", Fill)
    BNB.RegisterMessage("SpellingShortcuts", "SpellShortcutsChanged", function()
        if sf:IsVisible() then Fill() end
    end)
    greyed[#greyed + 1] = { box, nil, true }
    Fill()
    return y
end

function K.BuildSpellPage(sf, ct, y, page)
    local db = BigNoteBoxDB
    local SP = BNB.Spell
    local greyed = {}   -- { widget, label } greyed while the module is off
    local status
    local PaintShields   -- the dictionary shields, set below

    local function Sync()
        local on = BNB.SpellEnabled()
        if PaintShields then PaintShields() end
        for _, g in ipairs(greyed) do
            if not g[3] then g[1]:SetEnabled(on) end   -- g[3]: a frame, greyed only
            g[1]:SetAlpha(on and 1 or 0.35)
            if g[2] then g[2]:SetAlpha(on and 1 or 0.35) end
        end
        if not status then return end
        if not on then
            status:SetText(L["CFG_SPELL_STATUS_OFF"])
        elseif SP and SP.EnsureLoaded(SP.DefaultLang()) then
            status:SetText(string.format(L["CFG_SPELL_STATUS_FMT"], SP.WordCount(SP.DefaultLang())))
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

    -- ── Dictionary shields (Dukul, 2026-11-01) ──────────────────────────────
    -- A centred row of flags: every installed dictionary in full colour, the
    -- rest greyed (Dukul, 2026-11-01: "show colored ... if the dictionary is
    -- installed", so US and UK always are). French from the extra download
    -- (ALL-559 S5); German and Spanish are coming. The row is the language
    -- picker (Dukul, 2026-11-01: no dropdown): a click on an installed flag
    -- makes it the default; the default has the note list's hover plate
    -- (ui-note-list-collapsed-hover) behind it, green in normal mode, the
    -- skin accent in skin mode.
    local SHIELD, SHIELD_GAP, PLATE = 32, 12, 48
    local PLATE_ART = "Interface\\AddOns\\BigNoteBox\\Assets\\UI\\ui-note-list-collapsed-hover"
    local FLAGS = "Interface\\AddOns\\BigNoteBox\\Assets\\Flags\\shield-"
    local SHIELDS = {
        { "us", "CFG_SPELL_LANG_US", lang = "enUS" },
        { "uk", "CFG_SPELL_LANG_UK", lang = "enGB" },
        -- native = the language's own name, never translated (byte escapes:
        -- ASCII-only literals, the game's fonts draw the accented letters)
        { "fr", "CFG_SPELL_LANG_FR", native = "Fran\195\167ais", lang = "frFR" },
        { "de", "CFG_SPELL_LANG_DE", native = "Deutsch" },
        { "es", "CFG_SPELL_LANG_ES", native = "Espa\195\177ol" },
    }
    local rowW = #SHIELDS * SHIELD + (#SHIELDS - 1) * SHIELD_GAP
    local shieldRow = CreateFrame("Frame", nil, ct)
    shieldRow:SetSize(rowW, PLATE)
    shieldRow:SetPoint("TOP", ct, "TOPLEFT", K.CONTENT_W / 2, y)
    BNB.RegisterMessage("SpellShields" .. tostring(shieldRow), "SkinChanged", function()
        if shieldRow:IsVisible() and PaintShields then PaintShields() end
    end)
    local shields = {}
    -- The default language (the plate behind it), whether the module is on or not
    local function ShieldDefault(s)
        return s.lang and SP and SP.DefaultLang() == s.lang or false
    end
    -- In use: the module on, its language the default and its list loaded
    local function ShieldActive(s)
        return s.lang and BNB.SpellEnabled() and SP and SP.DefaultLang() == s.lang
            and SP.EnsureLoaded(s.lang) and true or false
    end
    local function ShieldInstalled(s)
        return s.lang and SP and SP.Installed(s.lang) and true or false
    end
    PaintShields = function()
        for _, b in ipairs(shields) do
            local on = ShieldInstalled(b._def)
            local def = ShieldDefault(b._def)
            if def then
                if BigNoteBoxDB and BigNoteBoxDB.skinMode then
                    b._plate:SetVertexColor(BNB.SkinAccentOf(BNB.GetSkinPreset()))
                else
                    b._plate:SetVertexColor(0.40, 0.85, 0.40)   -- BNB green (the note list's)
                end
                b._plate:Show()
            else
                b._plate:Hide()
            end
            b._tx:SetDesaturated(not on)
            b._tx:SetAlpha(on and 1 or 0.4)
        end
    end
    for i, s in ipairs(SHIELDS) do
        local b = CreateFrame("Button", nil, shieldRow)
        b:SetSize(SHIELD, SHIELD)
        b:SetPoint("LEFT", shieldRow, "LEFT", (i - 1) * (SHIELD + SHIELD_GAP), 0)
        b._def = s
        b._plate = b:CreateTexture(nil, "BACKGROUND")
        b._plate:SetSize(PLATE, PLATE)
        b._plate:SetPoint("CENTER")
        b._plate:SetTexture(PLATE_ART)
        b._plate:Hide()
        b:SetScript("OnClick", function()
            if not ShieldInstalled(s) or ShieldDefault(s) then return end
            db.spellLang = s.lang
            Changed()
            if b:IsMouseOver() and b:GetScript("OnEnter") then b:GetScript("OnEnter")(b) end
        end)
        b._tx = b:CreateTexture(nil, "ARTWORK")
        b._tx:SetAllPoints()
        b._tx:SetTexture(FLAGS .. s[1])
        b:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
            GameTooltip:AddLine(L[s[2]], 1, 1, 1)
            if s.native and s.native ~= L[s[2]] then GameTooltip:AddLine(s.native, 0.6, 0.6, 0.6) end
            local line
            if not s.lang then line = L["CFG_SPELL_SHIELD_SOON"]
            elseif not ShieldInstalled(s) then line = L["CFG_SPELL_SHIELD_MISSING"]
            elseif ShieldActive(s) then line = string.format(L["CFG_SPELL_SHIELD_ACTIVE_FMT"], SP.WordCount(s.lang))
            elseif not BNB.SpellEnabled() then line = L["CFG_SPELL_STATUS_OFF"]
            elseif SP.DefaultLang() ~= s.lang then line = L["CFG_SPELL_SHIELD_INSTALLED"]
            else line = L["CFG_SPELL_STATUS_MISSING"] end
            GameTooltip:AddLine(line, 0.8, 0.8, 0.8, true)
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        shields[i] = b
    end
    y = y - PLATE - 6

    local dd, lbl

    y, dd, lbl = AddChoice(ct, y, L["CFG_SPELL_MODE"],
        string.format(L["CFG_SPELL_MODE_TIP_FMT"], SP and SP.LONG_BYTES or 20000),
        { { "type", "CFG_SPELL_MODE_TYPE" }, { "click", "CFG_SPELL_MODE_CLICK" } },
        function() return db.spellMode == "click" and "click" or "type" end,
        function(v) db.spellMode = v; Changed() end)
    greyed[#greyed + 1] = { dd, lbl }

    -- Check spelling key (ALL-567): the same as the toolbar button
    y = K.MakeKeybindRow(ct, y, L["CFG_KB_SPELLCHECK"], "BIGNOTEBOXSPELLCHECK",
        "(" .. string.format(L["SW_KB_DEFAULT_FMT"], "F9") .. ")", L["CFG_KB_SPELLCHECK_TIP"])
    -- Correct spelling key (ALL-568): the same as the Correct spelling button
    y = K.MakeKeybindRow(ct, y, L["CFG_KB_SPELLCORRECT"], "BIGNOTEBOXSPELLCORRECT",
        "(" .. string.format(L["SW_KB_DEFAULT_FMT"], "F10") .. ")", L["CFG_KB_SPELLCORRECT_TIP"])

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
        x:Hide()
        row._x = x
        -- The highlight stays while the pointer is on the X too; the X shows
        -- only on hover (ALL-577)
        local function Hover()
            local on = row:IsMouseOver() and BNB.SpellEnabled()
            row._hover:SetShown(on); x:SetShown(on)
        end
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
            row:Show()
            -- a row that slid under the pointer (one removed above) shows its X at once
            local on = row:IsMouseOver() and BNB.SpellEnabled()
            row._hover:SetShown(on); row._x:SetShown(on)
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

    y = BuildShortcuts(sf, ct, y - 6, greyed)

    Sync()
    sf:HookScript("OnShow", Sync)
    sf:FinaliseHeight(math.abs(y) + 12)
end

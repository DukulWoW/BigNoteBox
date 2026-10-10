-- BigNoteBox UI/Config/Tldr.lua - Settings > Modules > tl;dr (ALL-372)
--
-- The tl;dr module's page: the module switch, where the tl;dr shows, the note
-- list hover details (a switch of its own that works with the module off,
-- Dukul 2026-10-10) and the snippet list the editor's tl;dr box offers
-- (add / change / move / remove, Reset to defaults). The module itself is
-- Features/Tldr.lua.

local BNB = BigNoteBox
local L   = BNB.L

local K = BNB._ConfigKit
local CONTENT_W = K.CONTENT_W
local AddRule, AddHeader, AddCheck = K.AddRule, K.AddHeader, K.AddCheck

local ROW_H   = 24     -- one snippet row
local ROW_GAP = 4
local BTN     = 20     -- the row's icon buttons
local OFF_ALPHA = 0.35 -- as K.GreyWhileOff

local function Tip(w, title, body)
    w:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(title, 1, 1, 1)
        if body then GameTooltip:AddLine(body, 0.8, 0.8, 0.8, true) end
        GameTooltip:Show()
    end)
    w:HookScript("OnLeave", function() GameTooltip:Hide() end)
end

-- An edit box in a dark box, as the Tag Manager's rename box
local function MakeBox(parent, w)
    local bg = BNB.CreateBackdropFrame("Frame", nil, parent)
    BNB.SetBackdropDark(bg)
    bg:SetSize(w, ROW_H - 2)
    local eb = CreateFrame("EditBox", nil, bg)
    eb:SetPoint("TOPLEFT", bg, "TOPLEFT", 6, 0)
    eb:SetPoint("BOTTOMRIGHT", bg, "BOTTOMRIGHT", -6, 0)
    eb:SetFontObject("BNBFontNormal")
    eb:SetAutoFocus(false)
    eb:SetMaxLetters(BNB.TLDR_MAX)
    bg.eb = eb
    return bg
end

function K.BuildTldrPage(sf, ct, y, page)
    local db = BigNoteBoxDB
    local Sync   -- greys the page while the module is off; defined below

    -- ── Module switch ───────────────────────────────────────────────────────
    local enableCb
    y, enableCb = AddCheck(ct, y, L["CFG_TLDR_ENABLE_LABEL"],
        function() return BNB.TldrEnabled() end,
        function(v)
            db.tldrEnabled = v
            BNB.ApplyTldrModule(v)
            Sync()
        end,
        L["CFG_TLDR_ENABLE_TIP"])
    page.enableCb = enableCb   -- twin on the Modules overview row

    -- ── Where it shows: two columns, row by row ─────────────────────────────
    local showLbl = ct:CreateFontString(nil, "OVERLAY", "BNBFontNormal")
    showLbl:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y - 4)
    showLbl:SetTextColor(0.75, 0.75, 0.75)
    showLbl:SetText(L["CFG_TLDR_SHOW_LBL"])
    y = y - 24

    local COL_GAP = 8
    local colW = math.floor((CONTENT_W - COL_GAP) / 2)
    local cols = {}
    for i = 1, 2 do
        cols[i] = CreateFrame("Frame", nil, ct)
        cols[i]:SetPoint("TOPLEFT", ct, "TOPLEFT", (i - 1) * (colW + COL_GAP), y)
        cols[i]:SetSize(colW, 10)
    end
    local colY, slot = { 0, 0 }, 0
    local showCbs = {}
    for _, s in ipairs({
        { "tldrUnderTitle",  "CFG_TLDR_TITLE_LABEL", "CFG_TLDR_TITLE_TIP" },
        { "tldrUnitTooltip", "CFG_TLDR_UNIT_LABEL",  "CFG_TLDR_UNIT_TIP"  },
        { "tldrToast",       "CFG_TLDR_TOAST_LABEL", "CFG_TLDR_TOAST_TIP" },
    }) do
        local key = s[1]
        slot = slot % 2 + 1
        local cb
        colY[slot], cb = AddCheck(cols[slot], colY[slot], L[s[2]],
            function() return db[key] ~= false end,
            function(v) db[key] = v; BNB.ApplyTldrModule(BNB.TldrEnabled()) end,
            L[s[3]])
        cb._key = key
        showCbs[#showCbs + 1] = cb
    end
    y = y + math.min(colY[1], colY[2])

    -- ── Note list hover details: works with the module off ──────────────────
    y = AddRule(ct, y - 4) - 4
    y = AddCheck(ct, y, L["CFG_HOVER_DETAILS_LABEL"],
        function() return db.noteHoverDetails ~= false end,
        function(v) db.noteHoverDetails = v end,
        L["CFG_HOVER_DETAILS_TIP"])

    -- ── Snippets ────────────────────────────────────────────────────────────
    y = AddRule(ct, y - 4) - 4
    y = AddHeader(ct, y, L["CFG_TLDR_SNIP_HDR"])
    local desc = ct:CreateFontString(nil, "OVERLAY", "BNBFontHighlightSmall")
    desc:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
    desc:SetWidth(CONTENT_W); desc:SetJustifyH("LEFT"); desc:SetWordWrap(true)
    desc:SetTextColor(0.65, 0.65, 0.65)
    desc:SetText(L["CFG_TLDR_SNIP_DESC"])
    local dh = math.ceil(desc:GetStringHeight())
    desc:SetHeight(dh)
    y = y - dh - 10

    -- Rows, the add row and Reset live in one frame from here down, so the
    -- list can grow and shrink without moving anything above it
    local list = CreateFrame("Frame", nil, ct)
    list:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
    list:SetSize(CONTENT_W, 10)
    local listTop = y

    local rows = {}
    local boxW = CONTENT_W - 3 * (BTN + 4)
    local snippets   -- the list as shown; every change saves it whole

    local Layout
    local function Save()
        BNB.SetTldrSnippets(snippets)
        snippets = BNB.TldrSnippets()   -- cleaned and de-duplicated
        Layout()
    end

    local function GetRow(i)
        if rows[i] then return rows[i] end
        local r = {}
        r.box = MakeBox(list, boxW)
        local eb = r.box.eb
        -- Enter keeps the change, Esc puts the old text back; an emptied
        -- snippet comes back (removing is the X)
        eb:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
        eb:SetScript("OnEscapePressed", function(self)
            self:SetText(snippets[r.idx] or ""); self:ClearFocus()
        end)
        eb:SetScript("OnEditFocusLost", function(self)
            local v = BNB.CleanTldr(self:GetText())
            if v and v ~= snippets[r.idx] then
                snippets[r.idx] = v; Save()
            else
                self:SetText(snippets[r.idx] or "")
            end
            self:SetCursorPosition(0)
        end)
        r.up = BNB.CreateIconButton(list, BTN, "up", { tip = L["CFG_TLDR_SNIP_UP"],
            onClick = function()
                local i2 = r.idx
                if i2 > 1 then snippets[i2], snippets[i2 - 1] = snippets[i2 - 1], snippets[i2]; Save() end
            end })
        r.down = BNB.CreateIconButton(list, BTN, "down", { tip = L["CFG_TLDR_SNIP_DOWN"],
            onClick = function()
                local i2 = r.idx
                if i2 < #snippets then snippets[i2], snippets[i2 + 1] = snippets[i2 + 1], snippets[i2]; Save() end
            end })
        r.del = BNB.CreateIconButton(list, BTN, "close", { tip = L["CFG_TLDR_SNIP_REMOVE"],
            onClick = function() table.remove(snippets, r.idx); Save() end })
        r.up:SetPoint("LEFT", r.box, "RIGHT", 4, 0)
        r.down:SetPoint("LEFT", r.up, "RIGHT", 4, 0)
        r.del:SetPoint("LEFT", r.down, "RIGHT", 4, 0)
        rows[i] = r
        return r
    end

    -- The add row
    local add = MakeBox(list, boxW)
    local addEb = add.eb
    BNB.AddPlaceholder(addEb, L["CFG_TLDR_SNIP_ADD_HINT"], 0.4, 0.4, 0.4)
    local function AddOne()
        local v = BNB.CleanTldr(addEb:GetRealText())
        if v and #snippets < BNB.TLDR_SNIPPETS_MAX then
            snippets[#snippets + 1] = v
            addEb:SetRealText("")
            Save()
            addEb:SetFocus()   -- ready for the next one
        end
    end
    addEb:SetScript("OnEnterPressed", AddOne)
    addEb:SetScript("OnEscapePressed", function(self) self:SetRealText(""); self:ClearFocus() end)
    local addBtn = BNB.CreateIconButton(list, BTN, "plus", {
        tip = function()
            if #snippets >= BNB.TLDR_SNIPPETS_MAX then
                return L["CFG_TLDR_SNIP_ADD_TIP"], string.format(L["CFG_TLDR_SNIP_FULL_FMT"], BNB.TLDR_SNIPPETS_MAX)
            end
            return L["CFG_TLDR_SNIP_ADD_TIP"]
        end,
        onClick = AddOne })
    addBtn:SetPoint("LEFT", add, "RIGHT", 4, 0)

    local resetBtn = BNB.CreateButton(nil, list, L["CFG_TLDR_SNIP_RESET"], 160, 22)
    resetBtn:SetScript("OnClick", function()
        StaticPopup_Show("BNB_MULTI_CONFIRM", L["CFG_TLDR_SNIP_RESET_CONFIRM"], nil, function()
            BNB.SetTldrSnippets(nil)
            snippets = BNB.TldrSnippets()
            Layout()
        end)
    end)
    Tip(resetBtn, L["CFG_TLDR_SNIP_RESET"], L["CFG_TLDR_SNIP_RESET_TIP"])

    Layout = function()
        local ly = 0
        for i, s in ipairs(snippets) do
            local r = GetRow(i)
            r.idx = i
            r.box:ClearAllPoints()
            r.box:SetPoint("TOPLEFT", list, "TOPLEFT", 0, ly)
            if not r.box.eb:HasFocus() then
                r.box.eb:SetText(s); r.box.eb:SetCursorPosition(0)
            end
            r.box:Show(); r.up:Show(); r.down:Show(); r.del:Show()
            r.up:SetEnabled(i > 1)
            r.down:SetEnabled(i < #snippets)
            ly = ly - (ROW_H + ROW_GAP)
        end
        for i = #snippets + 1, #rows do
            local r = rows[i]
            r.box:Hide(); r.up:Hide(); r.down:Hide(); r.del:Hide()
        end
        local full = #snippets >= BNB.TLDR_SNIPPETS_MAX
        add:ClearAllPoints()
        add:SetPoint("TOPLEFT", list, "TOPLEFT", 0, ly - 4)
        addBtn:SetDim(full)
        ly = ly - 4 - (ROW_H + ROW_GAP) - 6
        resetBtn:ClearAllPoints()
        resetBtn:SetPoint("TOPLEFT", list, "TOPLEFT", 0, ly)
        resetBtn:SetEnabled(BNB.TldrSnippetsCustom())
        ly = ly - 22
        Sync()
        sf:FinaliseHeight(math.abs(listTop + ly) + 20)
    end

    -- Everything but the switch and the hover details greys while the module
    -- is off (ALL-343). Re-run on every page show: the module may have been
    -- switched on the Modules tab or in the setup wizard.
    Sync = function()
        local on = BNB.TldrEnabled()
        local a = on and 1 or OFF_ALPHA
        showLbl:SetAlpha(a)
        for _, cb in ipairs(showCbs) do
            cb:SetEnabled(on); cb:SetAlpha(a)
            if cb._lbl then cb._lbl:SetAlpha(a) end
        end
        -- The buttons grey through SetEnabled (their own disabled look, never
        -- an alpha on top); the boxes and texts take the alpha
        desc:SetAlpha(a)
        add:SetAlpha(a)
        for i = 1, #snippets do
            local r = rows[i]
            if r then
                r.box:SetAlpha(a)
                r.box.eb:EnableMouse(on)
                if not on then r.box.eb:ClearFocus() end
                r.del:SetEnabled(on)
                r.up:SetEnabled(on and i > 1)
                r.down:SetEnabled(on and i < #snippets)
            end
        end
        addEb:EnableMouse(on)
        if not on then addEb:ClearFocus() end
        addBtn:SetEnabled(on)
        resetBtn:SetEnabled(on and BNB.TldrSnippetsCustom())
    end

    snippets = BNB.TldrSnippets()
    Layout()
    sf:HookScript("OnShow", function()
        for _, cb in ipairs(showCbs) do cb:SetChecked(db[cb._key] ~= false) end
        Sync()
    end)
end

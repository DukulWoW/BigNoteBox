-- BigNoteBox UI/Config/BackupPages.lua - the two sub-pages of Settings >
-- Backup (ALL-507):
--   Selective backup  the format (JSON / Markdown) and what goes in: notes
--                     picked from a list (filter by scope or tag, search,
--                     Select all / none), templates, tokens, tag colours,
--                     profiles. Markdown is notes only (Dukul, 2026-10-18).
--   Import backup     shown when a pasted backup holds more than notes: what
--                     it holds, each part (and each profile) with a checkbox.
--                     Its Import button is the confirm step.
-- Built by UI/Config/Backup.lua through K.BuildSelectiveBackupPage and
-- K.BuildImportPickerPage; the backups themselves are Features/NoteExport.lua.
-- Rows live in a holder that hides with the page, so the settings search
-- never finds note titles or profile names here.

local BNB = BigNoteBox
local L   = BNB.L

local K = BNB._ConfigKit
local CONTENT_W, ROW_GAP = K.CONTENT_W, K.ROW_GAP
local AddHeader = K.AddHeader

local LIST_ROW_H = 22
local GREY = 0.35   -- alpha of a greyed part

-- A checkbox with its label, at x / y of ct. Returns the box; box._lbl.
local function MakeCheck(ct, x, y, tip)
    local cb = CreateFrame("CheckButton", nil, ct, "UICheckButtonTemplate")
    cb:SetSize(24, 24)
    cb:SetPoint("TOPLEFT", ct, "TOPLEFT", x - 2, y + 2)
    local lbl = ct:CreateFontString(nil, "OVERLAY", "BNBFontNormal")
    lbl:SetPoint("LEFT", cb, "RIGHT", 4, 0)
    lbl:SetJustifyH("LEFT")
    cb._lbl = lbl
    BNB.LabelHit(cb, lbl)
    if tip then BNB.CheckTip(cb, tip) end
    return cb
end

-- Greyed (and read as off) or not
local function SetCheckUsable(cb, on)
    cb:SetEnabled(on)
    cb:SetAlpha(on and 1 or GREY)
    cb._lbl:SetAlpha(on and 1 or GREY)
end

local function Count(t)
    local n = 0
    for _ in pairs(t or {}) do n = n + 1 end
    return n
end

local function ProfileCount()
    local P, n = BNB.Profiles, 0
    if not P then return 0 end
    for _, name in ipairs(P.List()) do
        if P.Exists(name) then n = n + 1 end
    end
    return n
end

local function ScopeLabel(scope)
    local key = type(scope) == "string" and scope:match("^char:(.+)$")
    if not key then return L["SCOPE_GLOBAL"] end
    local rec = BigNoteBoxDB and BigNoteBoxDB.knownChars and BigNoteBoxDB.knownChars[key]
    return (type(rec) == "table" and rec.name) or key:match("^(.-)%-") or key
end

local function SmallText(ct, text)
    local fs = ct:CreateFontString(nil, "OVERLAY", "BNBFontNormalSmall")
    fs:SetJustifyH("LEFT"); fs:SetWordWrap(true)
    fs:SetTextColor(0.78, 0.78, 0.78)
    fs:SetText(text or "")
    return fs
end

local function StatusText(ct)
    local fs = ct:CreateFontString(nil, "OVERLAY", "BNBFontNormalSmall")
    fs:SetJustifyH("LEFT"); fs:SetWordWrap(false)
    fs:SetHeight(26)
    function fs:Say(text, ok)
        if ok == nil then self:SetTextColor(0.78, 0.78, 0.78)
        elseif ok then self:SetTextColor(0.55, 0.82, 0.55)
        else self:SetTextColor(0.82, 0.55, 0.55) end
        self:SetText(text or "")
    end
    return fs
end

--------------------------------------------------------------------------------
-- SELECTIVE BACKUP
--------------------------------------------------------------------------------

-- The notes in list order (any not in the order last), as list entries
local function NoteEntries()
    local ndb, out, seen = BNB.NotesDB(), {}, {}
    local notes = ndb and ndb.notes or {}
    local function Add(id, note)
        if seen[id] or type(note) ~= "table" then return end
        seen[id] = true
        local tags = {}
        for _, t in ipairs(note.tags or {}) do tags[t] = true end
        local title = note.title or ""
        out[#out + 1] = { id = id, title = title, low = title:lower(),
                          scope = note.scope or "global", tags = tags }
    end
    for _, id in ipairs(ndb and ndb.noteOrder or {}) do Add(id, notes[id]) end
    for id, note in pairs(notes) do Add(id, note) end
    return out
end

-- Characters that have notes, for the filter: { key, label } by name
local function CharsWithNotes(entries)
    local keys, out = {}, {}
    for _, e in ipairs(entries) do
        local key = e.scope:match("^char:(.+)$")
        if key then keys[key] = true end
    end
    for key in pairs(keys) do
        local label = ScopeLabel("char:" .. key)
        if key == BNB.currentChar then label = label .. " (" .. L["SCOPE_THIS_CHAR"] .. ")" end
        out[#out + 1] = { key = key, label = label }
    end
    table.sort(out, function(a, b) return a.label:lower() < b.label:lower() end)
    return out
end

function K.BuildSelectiveBackupPage(sf, ct, y)
    local desc = SmallText(ct, L["BACKUP_SEL_DESC"])
    desc:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
    desc:SetWidth(CONTENT_W)
    y = y - math.ceil(desc:GetStringHeight()) - 10

    -- ── Format ──────────────────────────────────────────────────────────────
    local isMd = false
    local UpdateParts, UpdateCount   -- below
    y = AddHeader(ct, y, L["BACKUP_SEL_HDR_FORMAT"])
    local rbJson = MakeCheck(ct, 0, y, L["BACKUP_FMT_DESC_JSON"])
    rbJson._lbl:SetText(L["BACKUP_FORMAT_JSON"])
    local rbMd = MakeCheck(ct, CONTENT_W / 2, y, L["BACKUP_FMT_DESC_MARKDOWN"])
    rbMd._lbl:SetText(L["BACKUP_FORMAT_MARKDOWN"])
    local function SetFormat(md)
        isMd = md
        rbJson:SetChecked(not md); rbMd:SetChecked(md)
        UpdateParts()
    end
    rbJson:SetScript("OnClick", function() SetFormat(false) end)
    rbMd:SetScript("OnClick", function() SetFormat(true) end)
    y = y - 26 - ROW_GAP

    -- ── Also include (JSON only) ────────────────────────────────────────────
    y = AddHeader(ct, y - 4, L["BACKUP_SEL_HDR_PARTS"])
    local PARTS = {
        { key = "templates", fmt = "BACKUP_SEL_TEMPLATES", tip = "BACKUP_SEL_TEMPLATES_TIP",
          count = function() return #(BNB.Templates and BNB.Templates.BackupList() or {}) end },
        { key = "tokens",    fmt = "BACKUP_SEL_TOKENS", tip = "BACKUP_SEL_TOKENS_TIP",
          count = function() return #(BNB.Tokens and BNB.Tokens.BackupList() or {}) end },
        { key = "tagColors", fmt = "BACKUP_SEL_TAGCOLORS", tip = "BACKUP_SEL_TAGCOLORS_TIP",
          count = function() return Count(BNB.TagColors and BNB.TagColors.BackupMap()) end },
        { key = "profiles",  fmt = "BACKUP_SEL_PROFILES", tip = "BACKUP_SEL_PROFILES_TIP",
          count = ProfileCount },
    }
    for i, part in ipairs(PARTS) do
        local col, row = (i - 1) % 2, math.floor((i - 1) / 2)
        part.cb = MakeCheck(ct, col * CONTENT_W / 2, y - row * (26 + ROW_GAP), function()
            if isMd then return L["BACKUP_SEL_MD_TIP"] end
            return L[part.tip]
        end)
        part.cb:SetChecked(true)
    end
    y = y - 2 * (26 + ROW_GAP)

    function UpdateParts()
        for _, part in ipairs(PARTS) do
            local n = part.count()
            part.n = n
            part.cb._lbl:SetText(string.format(L[part.fmt], n))
            SetCheckUsable(part.cb, not isMd and n > 0)
        end
    end

    -- ── Copy ────────────────────────────────────────────────────────────────
    local copyBtn = BNB.CreateButton(nil, ct, L["BACKUP_SEL_COPY"], 160, 26)
    copyBtn:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y - 4)
    local status = StatusText(ct)
    status:SetPoint("LEFT", copyBtn, "RIGHT", 10, 0)
    status:SetPoint("RIGHT", ct, "TOPRIGHT", 0, y - 17)
    y = y - 4 - 26 - 14

    -- ── Notes ───────────────────────────────────────────────────────────────
    y = AddHeader(ct, y, L["BACKUP_SEL_HDR_NOTES"])
    local entries, picked = {}, {}
    local filter, filterLabel, search = "all", L["BACKUP_SEL_FILTER_ALL"], ""
    local Layout   -- below

    local dd = BNB.SkinDropdown(CreateFrame("DropdownButton", nil, ct, "WowStyle1DropdownTemplate"))
    dd:SetToplevel(true); dd:SetWidth(200); dd:SetHeight(24)
    dd:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
    local function SetFilter(val, label)
        filter, filterLabel = val, label
        dd:SetText(label)
        Layout()
    end
    dd:SetupMenu(function(_, root)
        local function Radio(menu, label, val)
            menu:CreateRadio(label, function() return filter == val end,
                function() SetFilter(val, label) end)
        end
        Radio(root, L["BACKUP_SEL_FILTER_ALL"], "all")
        Radio(root, L["SCOPE_GLOBAL"], "global")
        for _, c in ipairs(CharsWithNotes(entries)) do Radio(root, c.label, "char:" .. c.key) end
        local tags = BNB.GetAllTags and BNB.GetAllTags() or {}
        if #tags > 0 then
            local sub = root:CreateButton(L["BACKUP_SEL_FILTER_TAG"])
            for _, t in ipairs(tags) do Radio(sub, t.tag, "tag:" .. t.tag) end
            -- Long tag lists scroll; guarded, as no other sub-menu uses it yet
            if #tags > 20 and sub.SetScrollMode then pcall(sub.SetScrollMode, sub, 20 * 20) end
        end
    end)
    dd:SetText(filterLabel)

    local boxBg = BNB.CreateBackdropFrame("Frame", nil, ct)
    BNB.SetBackdropDark(boxBg)
    boxBg:SetPoint("TOPLEFT", ct, "TOPLEFT", 210, y)
    boxBg:SetPoint("TOPRIGHT", ct, "TOPLEFT", CONTENT_W, y)
    boxBg:SetHeight(24)
    local searchEb = CreateFrame("EditBox", nil, boxBg)
    searchEb:SetPoint("TOPLEFT", boxBg, "TOPLEFT", 6, 0)
    searchEb:SetPoint("BOTTOMRIGHT", boxBg, "BOTTOMRIGHT", -6, 0)
    searchEb:SetFontObject("BNBFontNormal")
    searchEb:SetAutoFocus(false)
    searchEb:SetMaxLetters(60)
    BNB.AddPlaceholder(searchEb, L["BACKUP_SEL_SEARCH"], 0.4, 0.4, 0.4)
    searchEb:HookScript("OnTextChanged", function(self)
        local s = (self:GetRealText() or ""):lower()
        if s ~= search then search = s; Layout() end
    end)
    searchEb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    searchEb:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    y = y - 24 - 8

    local allBtn  = BNB.CreateButton(nil, ct, L["BACKUP_SEL_ALL"], 100, 22)
    allBtn:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
    local noneBtn = BNB.CreateButton(nil, ct, L["BACKUP_SEL_NONE"], 100, 22)
    noneBtn:SetPoint("LEFT", allBtn, "RIGHT", 8, 0)
    local countLbl = ct:CreateFontString(nil, "OVERLAY", "BNBFontNormalSmall")
    countLbl:SetPoint("LEFT", noneBtn, "RIGHT", 10, 0)
    countLbl:SetPoint("RIGHT", ct, "TOPRIGHT", 0, y - 11)
    countLbl:SetJustifyH("LEFT"); countLbl:SetWordWrap(false)
    countLbl:SetTextColor(0.65, 0.65, 0.65)
    y = y - 22 - 8

    local listTop = y
    local holder = CreateFrame("Frame", nil, ct)
    holder:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, listTop)
    holder:SetPoint("TOPRIGHT", ct, "TOPLEFT", CONTENT_W, listTop)
    holder:SetHeight(1)
    local emptyLbl = holder:CreateFontString(nil, "OVERLAY", "BNBFontNormalSmall")
    emptyLbl:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, -4)
    emptyLbl:SetTextColor(0.55, 0.55, 0.55)
    emptyLbl:SetText(L["BACKUP_SEL_NO_MATCH"])

    local shown, pool = {}, {}
    local function Matches(e)
        if filter == "global" then
            if e.scope ~= "global" then return false end
        elseif filter:find("^char:") then
            if e.scope ~= filter then return false end
        elseif filter:find("^tag:") then
            if not e.tags[filter:sub(5)] then return false end
        end
        return search == "" or e.low:find(search, 1, true) ~= nil
    end

    -- Only the notes in the list count and go into the backup: a note the
    -- filter or search hides is left out, ticked or not (Dukul, 2026-10-18)
    function UpdateCount()
        local n = 0
        for _, e in ipairs(shown) do if picked[e.id] then n = n + 1 end end
        countLbl:SetText(string.format(L["BACKUP_SEL_COUNT"], n, #entries))
        return n
    end

    local function Row(i)
        if pool[i] then return pool[i] end
        local row = CreateFrame("Frame", nil, holder)
        row:SetHeight(LIST_ROW_H)
        local cb = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
        cb:SetSize(22, 22)
        cb:SetPoint("LEFT", row, "LEFT", -2, 0)
        local where = row:CreateFontString(nil, "OVERLAY", "BNBFontNormalSmall")
        where:SetPoint("RIGHT", row, "RIGHT", -2, 0)
        where:SetJustifyH("RIGHT"); where:SetWordWrap(false)
        where:SetTextColor(0.55, 0.55, 0.55)
        local title = row:CreateFontString(nil, "OVERLAY", "BNBFontNormal")
        title:SetPoint("LEFT", cb, "RIGHT", 2, 0)
        title:SetPoint("RIGHT", where, "LEFT", -8, 0)
        title:SetJustifyH("LEFT"); title:SetWordWrap(false)
        cb:SetScript("OnClick", function(self)
            if row.id then picked[row.id] = self:GetChecked() and true or nil end
            UpdateCount()
        end)
        BNB.LabelHit(cb, title)
        row.cb, row.title, row.where = cb, title, where
        pool[i] = row
        return row
    end

    function Layout()
        wipe(shown)
        for _, e in ipairs(entries) do
            if Matches(e) then shown[#shown + 1] = e end
        end
        for i, e in ipairs(shown) do
            local row = Row(i)
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, -(i - 1) * LIST_ROW_H)
            row:SetPoint("TOPRIGHT", holder, "TOPRIGHT", 0, -(i - 1) * LIST_ROW_H)
            row.id = e.id
            row.title:SetText(e.title ~= "" and e.title or "-")
            row.where:SetText(ScopeLabel(e.scope))
            row.cb:SetChecked(picked[e.id] == true)
            BNB.LabelHit(row.cb, row.title)
            row:Show()
        end
        for i = #shown + 1, #pool do pool[i]:Hide(); pool[i].id = nil end
        if #shown == 0 then emptyLbl:Show() else emptyLbl:Hide() end
        UpdateCount()
        local listH = math.max(#shown * LIST_ROW_H, 24)
        sf:FinaliseHeight(-listTop + listH + 12)
    end

    local function PickShown(on)
        for _, e in ipairs(shown) do picked[e.id] = on or nil end
        Layout()
    end
    allBtn:SetScript("OnClick", function() PickShown(true) end)
    noneBtn:SetScript("OnClick", function() PickShown(false) end)

    copyBtn:SetScript("OnClick", function()
        local ids = {}
        for _, e in ipairs(shown) do if picked[e.id] then ids[#ids + 1] = e.id end end
        local opts = { ids = ids, fmt = isMd and BNB.NoteExport.FMT_MARKDOWN or BNB.NoteExport.FMT_JSON }
        local anyPart = false
        if not isMd then
            for _, part in ipairs(PARTS) do
                if part.cb:IsEnabled() and part.cb:GetChecked() then
                    opts[part.key] = true; anyPart = true
                end
            end
        end
        if #ids == 0 and not anyPart then
            local key = "BACKUP_SEL_EMPTY"
            if isMd then key = "BACKUP_SEL_MD_NONE" end
            status:Say(L[key], false)
            return
        end
        local text = BNB.NoteExport.BuildBackup(opts)
        if not text then return end
        BNB.ShowClipboardHint(text, copyBtn)
        status:Say(L["BACKUP_BTN_COPY_FALLBACK"])
    end)

    -- Fresh on every open: every note picked, no filter, no search
    sf:HookScript("OnShow", function()
        entries = NoteEntries()
        wipe(picked)
        for _, e in ipairs(entries) do picked[e.id] = true end
        filter, filterLabel, search = "all", L["BACKUP_SEL_FILTER_ALL"], ""
        dd:SetText(filterLabel)
        searchEb:SetRealText("")
        status:Say("")
        SetFormat(false)
        holder:Show()
        Layout()
    end)
    sf:HookScript("OnHide", function()
        holder:Hide()
        searchEb:ClearFocus()
    end)
    holder:Hide()
    sf:FinaliseHeight(-listTop + 36)
end

--------------------------------------------------------------------------------
-- IMPORT PICKER
--------------------------------------------------------------------------------

-- page.SetData(parsed, onImport): parsed is a backup from ParseJsonNotes;
-- onImport(filtered) gets a copy holding only what is ticked. The caller
-- opens the page (page.Open) after SetData.
function K.BuildImportPickerPage(sf, ct, y, page)
    local desc = SmallText(ct, L["BACKUP_PICK_DESC"])
    desc:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
    desc:SetWidth(CONTENT_W)
    y = y - math.ceil(desc:GetStringHeight()) - 12

    local data, onImport
    local PARTS = {
        { key = "notes",     fmt = "BACKUP_PICK_NOTES",    tip = "BACKUP_PICK_NOTES_TIP" },
        { key = "templates", fmt = "BACKUP_SEL_TEMPLATES", tip = "BACKUP_PICK_TEMPLATES_TIP" },
        { key = "tokens",    fmt = "BACKUP_SEL_TOKENS",    tip = "BACKUP_PICK_TOKENS_TIP" },
        { key = "tagColors", fmt = "BACKUP_SEL_TAGCOLORS", tip = "BACKUP_PICK_TAGCOLORS_TIP" },
    }
    for i, part in ipairs(PARTS) do
        local col, row = (i - 1) % 2, math.floor((i - 1) / 2)
        part.cb = MakeCheck(ct, col * CONTENT_W / 2, y - row * (26 + ROW_GAP), L[part.tip])
    end
    y = y - 2 * (26 + ROW_GAP) - 4

    local profHdrY = y
    local profHdr = ct:CreateFontString(nil, "OVERLAY", "BNBFontNormalLarge")
    profHdr:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, profHdrY)
    BNB.SetHeaderColor(profHdr)
    profHdr:SetText(L["BACKUP_PICK_HDR_PROFILES"])
    local holder = CreateFrame("Frame", nil, ct)
    holder:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, profHdrY - 26)
    holder:SetPoint("TOPRIGHT", ct, "TOPLEFT", CONTENT_W, profHdrY - 26)
    holder:SetHeight(1)

    local importBtn = BNB.CreateButton(nil, ct, L["BACKUP_BTN_IMPORT"], 120, 26)
    local cancelBtn = BNB.CreateButton(nil, ct, L["CANCEL"], 80, 26)
    cancelBtn:SetPoint("LEFT", importBtn, "RIGHT", 8, 0)
    local status = StatusText(ct)
    status:SetPoint("LEFT", cancelBtn, "RIGHT", 10, 0)
    status:SetWidth(CONTENT_W - 120 - 8 - 80 - 10)

    -- One row per profile code: { code, name, as, taken, cb }. A name taken
    -- here gets a dropdown: replace the one here, or add as "Name (1)" (ALL-509)
    local profs, pool = {}, {}
    local DD_X = 200
    local function ProfRow(i)
        if pool[i] then return pool[i] end
        local cb = CreateFrame("CheckButton", nil, holder, "UICheckButtonTemplate")
        cb:SetSize(24, 24)
        local lbl = holder:CreateFontString(nil, "OVERLAY", "BNBFontNormal")
        lbl:SetPoint("LEFT", cb, "RIGHT", 4, 0)
        lbl:SetJustifyH("LEFT")
        lbl:SetWordWrap(false)
        cb._lbl = lbl
        BNB.LabelHit(cb, lbl)
        BNB.CheckTip(cb, function() return cb._tip end)
        cb._ddEntries = {}   -- refilled per backup; the menu reads it when opened
        cb._dd = BNB.CreateValueDropdown(holder, cb._ddEntries, "copy", nil,
                                         math.min(260, CONTENT_W - DD_X), 24)
        cb._dd:SetPoint("LEFT", cb, "LEFT", DD_X, 0)
        pool[i] = cb
        return cb
    end

    local function Layout()
        local P = BNB.Profiles
        wipe(profs)
        -- A name already here gets a free one, "Default (1)" (Dukul,
        -- 2026-10-18); used keeps two rows of this backup from sharing one
        local used = {}
        for _, code in ipairs(type(data.profiles) == "table" and data.profiles or {}) do
            local payload = type(code) == "string" and P and P.Decode(code)
            if payload and payload.name then
                local as = P.FreeName(payload.name, used)
                used[as:lower()] = true
                profs[#profs + 1] = { code = code, name = payload.name, as = as,
                                      taken = P.TakenBy(payload.name) }
            end
        end
        for _, part in ipairs(PARTS) do
            local n
            if part.key == "tagColors" then n = Count(data.tagColors)
            elseif part.key == "notes" then n = #data
            else n = #(type(data[part.key]) == "table" and data[part.key] or {}) end
            part.cb._lbl:SetText(string.format(L[part.fmt], n))
            part.cb:SetChecked(n > 0)
            SetCheckUsable(part.cb, n > 0)
        end
        local yy = 0
        for i, p in ipairs(profs) do
            local cb = ProfRow(i)
            cb:ClearAllPoints()
            cb:SetPoint("TOPLEFT", holder, "TOPLEFT", -2, yy + 2)
            cb._lbl:SetText(P.DisplayName(p.name))
            wipe(cb._ddEntries)
            if p.taken then
                -- Default comes back as Default; other names as a copy (Dukul, 2026-10-19)
                cb._lbl:SetWidth(DD_X - 32)
                cb._tip = L["BACKUP_PICK_TAKEN_TIP"]
                cb._ddEntries[1] = { value = "replace",
                    label = string.format(L["BACKUP_PICK_REPLACE"], P.DisplayName(p.taken)) }
                cb._ddEntries[2] = { value = "copy",
                    label = string.format(L["BACKUP_PICK_ADD_AS"], p.as) }
                cb._dd:SetSelected(p.taken == P.DEFAULT and "replace" or "copy")
                cb._dd:Show()
            else
                cb._lbl:SetWidth(CONTENT_W - 32)
                cb._tip = L["BACKUP_PICK_PROFILE_TIP"]
                cb._dd:Hide()
            end
            cb:SetChecked(true)
            cb:SetEnabled(true)
            cb:SetAlpha(1); cb._lbl:SetAlpha(1)
            p.cb = cb
            cb:Show(); cb._lbl:Show()
            BNB.LabelHit(cb, cb._lbl)
            yy = yy - (26 + ROW_GAP)
        end
        for i = #profs + 1, #pool do pool[i]:Hide(); pool[i]._lbl:Hide(); pool[i]._dd:Hide() end
        local any = #profs > 0
        if any then profHdr:Show() else profHdr:Hide() end
        local bottom = any and (profHdrY - 26 + yy - 8) or profHdrY
        importBtn:ClearAllPoints()
        importBtn:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, bottom)
        status:Say("")
        sf:FinaliseHeight(-bottom + 26 + 16)
    end

    function page.SetData(parsed, fn)
        data, onImport = parsed, fn
    end

    importBtn:SetScript("OnClick", function()
        if not data then return end
        local out, any = {}, false
        local function On(key)
            for _, part in ipairs(PARTS) do
                if part.key == key then return part.cb:IsEnabled() and part.cb:GetChecked() end
            end
        end
        if On("notes") then
            for i, note in ipairs(data) do out[i] = note end
            out.folders = data.folders   -- the notes' folders come with them (ALL-510 S2)
            any = any or #out > 0
        end
        for _, key in ipairs({ "templates", "tokens", "tagColors" }) do
            if On(key) then out[key] = data[key]; any = true end
        end
        local codes, names, replace = {}, {}, {}
        for _, p in ipairs(profs) do
            if p.cb and p.cb:GetChecked() then
                codes[#codes + 1] = p.code
                names[#codes] = p.as
                replace[#codes] = (p.taken and p.cb._dd:GetSelected() == "replace") or nil
            end
        end
        if #codes > 0 then
            out.profiles, out.profileNames, out.profileReplace = codes, names, replace
            any = true
        end
        if not any then status:Say(L["BACKUP_PICK_NOTHING"], false); return end
        local fn = onImport
        data, onImport = nil, nil
        if fn then fn(out) end
    end)
    cancelBtn:SetScript("OnClick", function()
        data, onImport = nil, nil
        BNB.ConfigSubPageBack()
    end)

    sf:HookScript("OnShow", function()
        if not data then BNB.ConfigSubPageBack(); return end
        holder:Show()
        Layout()
    end)
    sf:HookScript("OnHide", function() holder:Hide() end)
    holder:Hide()
    importBtn:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, profHdrY)
    sf:FinaliseHeight(-profHdrY + 26 + 16)
end

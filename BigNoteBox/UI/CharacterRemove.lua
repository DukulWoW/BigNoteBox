-- BigNoteBox UI/CharacterRemove.lua
-- Removing a character BigNoteBox remembers (ALL-249). An addon cannot ask the
-- game which characters are on the account, so a deleted character stays in
-- BigNoteBoxDB.knownChars until it is removed here, from the sidebar's
-- right-click menu or Settings > Modules > Character sidebar. Its notes move
-- first, to another character or to Global (Dukul, 2026-10-04); logging in on
-- it again simply adds it back. The character you are on cannot be removed.
--
--   CR.Label(charKey)       "Name - Realm"
--   CR.NoteCount(charKey)   live notes on that character
--   CR.DaysUnseen(charKey)  whole days since its last login, nil if never stamped
--   CR.STALE_DAYS           from here on, Settings shows "not seen for N days"
--   CR.Open(charKey)        the remove window

local BNB = BigNoteBox
if not BNB then return end
local L = BNB.L

local CR = {}
BNB.CharacterRemove = CR
CR.STALE_DAYS = 90

local W, PAD, FOOT_H, DD_H = 320, 14, 38, 24

local function Rec(charKey)
    local db = BigNoteBoxDB
    return db and db.knownChars and db.knownChars[charKey]
end

function CR.Label(charKey)
    local rec = Rec(charKey)
    local name, realm = rec and rec.name or charKey, rec and rec.realm
    if realm and realm ~= "" then return name .. " - " .. realm end
    return name
end

function CR.NoteCount(charKey)
    local ndb, scope, n = BNB.NotesDB(), "char:" .. charKey, 0
    for _, note in pairs(ndb and ndb.notes or {}) do
        if note.scope == scope then n = n + 1 end
    end
    return n
end

function CR.DaysUnseen(charKey)
    local rec = Rec(charKey)
    if not (rec and rec.lastSeen) then return nil end
    return math.floor((time() - rec.lastSeen) / 86400)
end

local function CountText(n)
    return n == 1 and L["SB_NOTE_COUNT_ONE"] or string.format(L["SB_NOTE_COUNT_N_FMT"], n)
end

-- Moves the character's notes (live and trashed) to dest, forgets its
-- per-character situation counters and its record, and redraws what shows it
local function DoRemove(charKey, dest)
    local db = BigNoteBoxDB
    if not (db and db.knownChars and db.knownChars[charKey]) then return end
    local label, scope, n = CR.Label(charKey), "char:" .. charKey, 0
    local ndb = BNB.NotesDB()
    for id, note in pairs(ndb and ndb.notes or {}) do
        if note.scope == scope then
            BNB.UpdateNote(id, { scope = dest })
            n = n + 1
        end
        -- Runtime state, not an edit (CLAUDE.md Situations): written straight on
        if note.contextSeen then note.contextSeen[charKey] = nil end
    end
    BNB.RescopeTrash(scope, dest, charKey)
    db.knownChars[charKey] = nil

    local SB = BNB.Sidebar
    if SB then
        if SB.GetActive and SB.GetActive() == scope then SB.SetActive("all") end
        if SB.Refresh then SB.Refresh() end
    end
    if BNB.RefreshHiddenCharList then BNB.RefreshHiddenCharList() end
    if n > 0 then
        local destLabel = dest == "global" and L["SB_GLOBAL_NOTES"] or CR.Label(dest:match("^char:(.+)$") or dest)
        BNB:Print(string.format(L["CHAR_REMOVED_MOVED_FMT"], label, CountText(n), destLabel))
    else
        BNB:Print(string.format(L["CHAR_REMOVED_FMT"], label))
    end
end

local _f, _text, _dd, _hint
local _key
local _entries = {}   -- the dropdown reads this table on every open: refilled in place

local function Build()
    if _f then return end
    local f, removeBtn, cancelBtn = BNB.CreateToolWindow({
        name = "BNBCharRemoveFrame", w = W, h = 200, title = L["CHAR_REMOVE_TITLE"],
        pad = PAD, cw = W - 2 * PAD, footH = FOOT_H,
        btn1 = L["CHAR_REMOVE_BTN"], btn2 = L["CANCEL"],
        -- Settings' strata, raised over it on open: at FULLSCREEN_DIALOG the
        -- game's dropdown menu opened under the window (ALL-308)
        strata = "DIALOG", toplevel = true, escClose = true, keyEsc = true,
        onHide = function() _key = nil end,
    })
    _f = f
    local top = (f._isSkin and BNB.TOOL_SKIN_TITLE_H or 28) + 12
    f._top = top

    _text = f:CreateFontString(nil, "OVERLAY", "BNBFontHighlight")
    _text:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, -top)
    _text:SetWidth(W - 2 * PAD)
    _text:SetJustifyH("LEFT"); _text:SetWordWrap(true)

    _dd = BNB.CreateValueDropdown(f, _entries, "global", nil, W - 2 * PAD, DD_H)
    _dd:SetPoint("TOPLEFT", _text, "BOTTOMLEFT", 0, -8)

    _hint = f:CreateFontString(nil, "OVERLAY", "BNBFontNormalSmall")
    _hint:SetWidth(W - 2 * PAD)
    _hint:SetJustifyH("LEFT"); _hint:SetWordWrap(true)
    _hint:SetTextColor(0.6, 0.6, 0.6)
    _hint:SetText(L["CHAR_REMOVE_BACK"])

    removeBtn:SetScript("OnClick", function()
        local key = _key
        local dest = _dd:GetSelected() or "global"
        f:Hide()
        if key then DoRemove(key, dest) end
    end)
    cancelBtn:SetScript("OnClick", function() f:Hide() end)
end

function CR.Open(charKey)
    if not Rec(charKey) or charKey == BNB.currentChar then return end
    Build()
    _key = charKey
    local n = CR.NoteCount(charKey)

    -- Global first, then every other character by name
    wipe(_entries)
    local chars = {}
    for key in pairs(BigNoteBoxDB.knownChars) do
        if key ~= charKey then chars[#chars + 1] = { label = CR.Label(key), value = "char:" .. key } end
    end
    table.sort(chars, function(a, b) return a.label:lower() < b.label:lower() end)
    _entries[1] = { label = L["SB_GLOBAL_NOTES"], value = "global" }
    for _, e in ipairs(chars) do _entries[#_entries + 1] = e end
    _dd:SetSelected("global")

    local label = CR.Label(charKey)
    _hint:ClearAllPoints()
    if n > 0 then
        _text:SetText(string.format(L["CHAR_REMOVE_NOTES_FMT"], label, CountText(n)))
        _dd:Show()
        _hint:SetPoint("TOPLEFT", _dd, "BOTTOMLEFT", 0, -10)
    else
        _text:SetText(string.format(L["CHAR_REMOVE_NONE_FMT"], label))
        _dd:Hide()
        _hint:SetPoint("TOPLEFT", _text, "BOTTOMLEFT", 0, -10)
    end
    local h = _f._top + _text:GetStringHeight() + (n > 0 and (8 + DD_H) or 0)
        + 10 + _hint:GetStringHeight() + 14 + FOOT_H
    _f:SetHeight(math.ceil(h))
    _f:ClearAllPoints()
    _f:SetPoint("CENTER", UIParent, "CENTER", 0, 80)
    _f:Show()
    _f:Raise()
end

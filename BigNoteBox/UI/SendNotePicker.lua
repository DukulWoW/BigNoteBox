-- BigNoteBox UI/SendNotePicker.lua - the top bar's Send button (ALL-426)
--
-- A note search under the button: type a few letters, Up / Down (or the
-- mouse) picks a note, Enter or a click sends it to the Send to Chat window
-- (BNB.OpenSendToChat), so no note has to be opened first. The search is the
-- Oracle's own (BNB.OracleSearch) without its prefixes; an empty box lists
-- the open note first, then the most recently edited (Dukul, 2026-10-10).
-- Esc, a click elsewhere or the button again closes it. The Oracle's `m`
-- prefix sends the same way (UI/Oracle.lua).
--
-- Public API:
--   BNB.ToggleSendNotePicker(anchor)

local BNB = BigNoteBox
local L   = BNB.L

local W, PAD, EB_H, ROW_H, MAX_ROWS = 260, 6, 22, 20, 8
local DEFAULT_ICON = "Interface\\Icons\\INV_Misc_Note_06"   -- as the Oracle's rows

local picker, eb, placeholder, list, emptyFS, nav
local rows = {}
local _anchor

local function AllNotes()
    local ndb = BNB.NotesDB()
    local out = {}
    if not (ndb and ndb.notes) then return out end
    for _, id in ipairs(ndb.noteOrder or {}) do
        local n = ndb.notes[id]
        if n then out[#out + 1] = n end
    end
    return out
end

-- The notes to list for the text typed, best first
local function Results(text)
    local notes = AllNotes()
    if not text:find("%S") then
        local cur = BNB._currentNoteID
        table.sort(notes, function(a, b)
            if (a.id == cur) ~= (b.id == cur) then return a.id == cur end
            return (a.updated or 0) > (b.updated or 0)
        end)
        local out = {}
        for i = 1, math.min(MAX_ROWS, #notes) do out[i] = notes[i] end
        return out, #notes
    end
    local OS = BNB.OracleSearch
    local parsed = OS.ParseQuery(text, { prefixes = {} })
    if parsed.help then return {}, #notes end
    local hits = OS.SearchParsed(notes, parsed, { max = MAX_ROWS, ctx = {
        charScope = "char:" .. (BNB.currentChar or ""), now = time(),
        itemName = function(itemID) return (C_Item.GetItemInfo(itemID)) end,
    } })
    local out = {}
    for i, h in ipairs(hits) do out[i] = h.note end
    return out, #notes
end

local function Close()
    if picker then picker:Hide() end
end

local function Send(id)
    Close()
    if BNB.OpenSendToChat then BNB.OpenSendToChat(id) end
end

local function Row(i)
    local r = rows[i]
    if r then return r end
    r = CreateFrame("Button", nil, list)
    r:SetHeight(ROW_H)
    r:SetPoint("TOPLEFT",  list, "TOPLEFT",  0, -(i - 1) * ROW_H)
    r:SetPoint("TOPRIGHT", list, "TOPRIGHT", 0, -(i - 1) * ROW_H)
    local hl = r:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints(); hl:SetColorTexture(1, 1, 1, 0.10)
    r._icon = r:CreateTexture(nil, "ARTWORK")
    r._icon:SetSize(ROW_H - 4, ROW_H - 4)
    r._icon:SetPoint("LEFT", r, "LEFT", 2, 0)
    r._title = r:CreateFontString(nil, "OVERLAY", "BNBFontNormalSmall")
    r._title:SetPoint("LEFT",  r._icon, "RIGHT", 5, 0)
    r._title:SetPoint("RIGHT", r, "RIGHT", -4, 0)
    r._title:SetJustifyH("LEFT"); r._title:SetWordWrap(false)
    r:SetScript("OnClick", function(self) if self._id then Send(self._id) end end)
    rows[i] = r
    return r
end

local function Refresh()
    local text = eb:GetText() or ""
    if text == "" then placeholder:Show() else placeholder:Hide() end
    local notes, total = Results(text)
    for i, note in ipairs(notes) do
        local r = Row(i)
        r._id = note.id
        local icon = BNB.NpcNoteIcon and BNB.NpcNoteIcon(note) or note.icon
        r._icon:SetTexture((icon and icon ~= "") and icon or DEFAULT_ICON)
        r._title:SetText((note.title and note.title ~= "") and note.title or L["UNTITLED"])
        local tc = note.titleColor
        if tc then r._title:SetTextColor(tc.r, tc.g, tc.b) else BNB.SetTextWhite(r._title) end
        r:Show()
    end
    for i = #notes + 1, #rows do rows[i]:Hide() end
    if #notes == 0 then
        if total == 0 then emptyFS:SetText(L["SEND_PICK_NO_NOTES"]) else emptyFS:SetText(L["SEND_PICK_EMPTY"]) end
        emptyFS:Show()
    else
        emptyFS:Hide()
    end
    local n = math.max(1, #notes)
    list:SetHeight(n * ROW_H)
    picker:SetHeight(PAD + EB_H + 4 + n * ROW_H + PAD)
end

local function Build()
    if picker then return end
    picker = BNB.CreateBackdropFrame("Frame", "BNBSendNotePicker", UIParent)
    BNB.SetBackdrop(picker, 0.08, 0.08, 0.10, 0.97, 0.35, 0.35, 0.38, 1)
    picker:SetWidth(W)
    picker:SetFrameStrata("DIALOG")
    picker:SetToplevel(true)
    picker:SetClampedToScreen(true)
    picker:EnableMouse(true)
    picker:Hide()

    local ebBg = BNB.CreateBackdropFrame("Frame", nil, picker)
    BNB.SetBackdropDark(ebBg)
    ebBg:SetPoint("TOPLEFT",  picker, "TOPLEFT",  PAD, -PAD)
    ebBg:SetPoint("TOPRIGHT", picker, "TOPRIGHT", -PAD, -PAD)
    ebBg:SetHeight(EB_H)
    eb = CreateFrame("EditBox", nil, ebBg)
    eb:SetAllPoints(ebBg)
    eb:SetTextInsets(6, 6, 0, 0)
    eb:SetFontObject("BNBFontNormalSmall")
    eb:SetAutoFocus(false)
    eb:SetMaxLetters(80)
    BNB.SetTextWhite(eb)
    placeholder = ebBg:CreateFontString(nil, "OVERLAY", "BNBFontNormalSmall")
    placeholder:SetPoint("LEFT", ebBg, "LEFT", 6, 0)
    placeholder:SetTextColor(0.45, 0.45, 0.45)
    placeholder:SetText(L["SEND_PICK_PLACEHOLDER"])

    list = CreateFrame("Frame", nil, picker)
    list:SetPoint("TOPLEFT",  ebBg, "BOTTOMLEFT",  0, -4)
    list:SetPoint("TOPRIGHT", ebBg, "BOTTOMRIGHT", 0, -4)
    list:SetHeight(ROW_H)
    emptyFS = list:CreateFontString(nil, "OVERLAY", "BNBFontNormalSmall")
    emptyFS:SetPoint("LEFT", list, "LEFT", 4, 0)
    emptyFS:SetTextColor(0.50, 0.50, 0.50)

    eb:SetScript("OnTextChanged", function() Refresh() end)
    -- Up / Down / Tab over the rows (ALL-427); Enter sends the highlighted
    -- note, or the first one
    nav = BNB.AttachListKeys(eb, list, rows)
    eb:SetScript("OnEnterPressed", function()
        if nav:Take() then return end
        local r = rows[1]
        if r and r:IsShown() then r:Click() end
    end)
    eb:SetScript("OnEscapePressed", Close)

    -- A click anywhere else closes it; the button's own click toggles
    picker:SetScript("OnEvent", function(self)
        if self:IsMouseOver() or (_anchor and _anchor:IsMouseOver()) then return end
        Close()
    end)
    picker:SetScript("OnShow", function(self) self:RegisterEvent("GLOBAL_MOUSE_DOWN") end)
    picker:SetScript("OnHide", function(self)
        self:UnregisterEvent("GLOBAL_MOUSE_DOWN")
        eb:ClearFocus()
    end)
end

function BNB.ToggleSendNotePicker(anchor)
    Build()
    if picker:IsShown() then Close(); return end
    if _anchor ~= anchor then
        _anchor = anchor
        -- The button hides with the main window: the search goes with it
        anchor:HookScript("OnHide", Close)
    end
    picker:ClearAllPoints()
    picker:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -4)
    eb:SetText("")
    Refresh()
    picker:Show()
    picker:Raise()
    eb:SetFocus()
end

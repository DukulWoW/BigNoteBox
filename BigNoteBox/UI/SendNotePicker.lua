-- BigNoteBox UI/SendNotePicker.lua - the top bar's Send button (ALL-426)
--
-- A note search under the button: type a few letters, Up / Down (or the
-- mouse) picks a note, Enter or a click sends it to the Send to Chat window
-- (BNB.OpenSendToChat), so no note has to be opened first. The search is the
-- Oracle's own (BNB.OracleSearch) without its prefixes; an empty box lists
-- the open note first, then the most recently edited (Dukul, 2026-10-10).
-- Esc, a click elsewhere or the button again closes it. The Oracle's `m`
-- prefix sends the same way (UI/Oracle.lua).
-- The same search picks a note for a note link and for "From another note"
-- in the waypoint link popup (ALL-478): BNB.ToggleNotePicker with opts.
--
-- The note link button also lists the places a UI link can open (ALL-513,
-- Features/UILinks.lua): opts.onPlace turns on a Notes / BigNoteBox switch
-- under the search box.
--
-- Public API:
--   BNB.ToggleSendNotePicker(anchor)
--   BNB.ToggleNotePicker(anchor, opts)   opts: onPick(id), filter(note) -> bool,
--       exclude = id, placeholder, noneText (no note passes the filter),
--       onPlace(key) = also list BigNoteBox places, placesPlaceholder
--   BNB.NotePickerShown()

local BNB = BigNoteBox
local L   = BNB.L

local W, PAD, EB_H, ROW_H, MAX_ROWS = 260, 6, 22, 20, 8
local TAB_H, MAX_PLACES = 18, 12
local DEFAULT_ICON = "Interface\\Icons\\INV_Misc_Note_06"   -- as the Oracle's rows

local picker, eb, placeholder, list, emptyFS, nav
local rows = {}
local _anchor
local _opts = {}   -- the open picker's options (empty = Send)
local _mode = "notes"   -- "places" = the BigNoteBox list (opts.onPlace)
local tabRow, tabBtns

local function AllNotes()
    local ndb = BNB.NotesDB()
    local out = {}
    if not (ndb and ndb.notes) then return out end
    for _, id in ipairs(ndb.noteOrder or {}) do
        local n = ndb.notes[id]
        if n and id ~= _opts.exclude and not (_opts.filter and not _opts.filter(n)) then
            out[#out + 1] = n
        end
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

-- The places matching the text: label or key holds it (any case)
local function PlaceResults(text)
    local UL = BNB.UILinks
    local all = UL and UL.List() or {}
    local want = text:lower():match("^%s*(.-)%s*$")
    local out = {}
    for _, p in ipairs(all) do
        if want == "" or p.label:lower():find(want, 1, true) or p.key:lower():find(want, 1, true) then
            out[#out + 1] = p
            if #out == MAX_PLACES then break end
        end
    end
    return out, #all
end

local function Close()
    if picker then picker:Hide() end
end

local function Send(id)
    local onPick = _opts.onPick
    Close()
    if onPick then onPick(id)
    elseif BNB.OpenSendToChat then BNB.OpenSendToChat(id) end
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
    r:SetScript("OnClick", function(self)
        if self._place then
            local onPlace = _opts.onPlace
            Close()
            if onPlace then onPlace(self._place) end
        elseif self._id then
            Send(self._id)
        end
    end)
    rows[i] = r
    return r
end

local function RefreshPlaces(text)
    local places = PlaceResults(text)
    local UL = BNB.UILinks
    for i, p in ipairs(places) do
        local r = Row(i)
        r._id, r._place = nil, p.key
        r._icon:SetTexture(p.icon or DEFAULT_ICON)
        r._title:SetText(p.label)
        if UL and UL.State(p.key) then BNB.SetTextWhite(r._title) else r._title:SetTextColor(0.5, 0.5, 0.5) end
        r:Show()
    end
    for i = #places + 1, #rows do rows[i]:Hide() end
    if #places == 0 then
        emptyFS:SetText(L["SEND_PICK_EMPTY"])
        emptyFS:Show()
    else
        emptyFS:Hide()
    end
    return #places
end

local function Refresh()
    local text = eb:GetText() or ""
    if text == "" then placeholder:Show() else placeholder:Hide() end
    local tabsH = (tabRow and tabRow:IsShown()) and (TAB_H + 4) or 0
    if _mode == "places" then
        local n = math.max(1, RefreshPlaces(text))
        list:SetHeight(n * ROW_H)
        picker:SetHeight(PAD + EB_H + 4 + tabsH + n * ROW_H + PAD)
        return
    end
    local notes, total = Results(text)
    for i, note in ipairs(notes) do
        local r = Row(i)
        r._id, r._place = note.id, nil
        local icon = BNB.NpcNoteIcon and BNB.NpcNoteIcon(note) or note.icon
        r._icon:SetTexture((icon and icon ~= "") and icon or DEFAULT_ICON)
        r._title:SetText((note.title and note.title ~= "") and note.title or L["UNTITLED"])
        local tc = note.titleColor
        if tc then r._title:SetTextColor(tc.r, tc.g, tc.b) else BNB.SetTextWhite(r._title) end
        r:Show()
    end
    for i = #notes + 1, #rows do rows[i]:Hide() end
    if #notes == 0 then
        if total == 0 then emptyFS:SetText(_opts.noneText or L["SEND_PICK_NO_NOTES"])
        else emptyFS:SetText(L["SEND_PICK_EMPTY"]) end
        emptyFS:Show()
    else
        emptyFS:Hide()
    end
    local n = math.max(1, #notes)
    list:SetHeight(n * ROW_H)
    picker:SetHeight(PAD + EB_H + 4 + tabsH + n * ROW_H + PAD)
end

-- The Notes / BigNoteBox switch (opts.onPlace): the picked one gold, the
-- other grey; the placeholder follows
local function SetMode(mode)
    _mode = mode
    local hr, hg, hb = BNB.HeaderColor()   -- gold, the skin's header colour in skin mode
    for key, b in pairs(tabBtns or {}) do
        if key == mode then
            b._fs:SetTextColor(hr, hg, hb)
            b._line:SetVertexColor(hr, hg, hb)
            b._line:Show()
        else
            b._fs:SetTextColor(0.55, 0.55, 0.55)
            b._line:Hide()
        end
    end
    placeholder:SetText(mode == "places" and (_opts.placesPlaceholder or L["UILINK_PICK_PH"])
        or (_opts.placeholder or L["SEND_PICK_PLACEHOLDER"]))
    if picker:IsShown() then Refresh() end
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

    -- Notes / BigNoteBox (ALL-513), shown only for a picker with onPlace
    tabRow = CreateFrame("Frame", nil, picker)
    tabRow:SetPoint("TOPLEFT",  ebBg, "BOTTOMLEFT",  0, -4)
    tabRow:SetPoint("TOPRIGHT", ebBg, "BOTTOMRIGHT", 0, -4)
    tabRow:SetHeight(TAB_H)
    tabRow:Hide()
    tabBtns = {}
    local prev
    for _, t in ipairs({ { "notes", "UILINK_PICK_NOTES" }, { "places", "UILINK_PICK_PLACES" } }) do
        local b = CreateFrame("Button", nil, tabRow)
        b._fs = b:CreateFontString(nil, "OVERLAY", "BNBFontNormalSmall")
        b._fs:SetPoint("CENTER")
        b._fs:SetText(L[t[2]])
        b:SetSize(math.ceil(b._fs:GetStringWidth()) + 16, TAB_H)
        b._line = b:CreateTexture(nil, "ARTWORK")
        b._line:SetColorTexture(1, 1, 1, 0.8)   -- tinted to the header colour in SetMode
        b._line:SetHeight(1)
        b._line:SetPoint("BOTTOMLEFT", 4, 0); b._line:SetPoint("BOTTOMRIGHT", -4, 0)
        if prev then b:SetPoint("LEFT", prev, "RIGHT", 4, 0) else b:SetPoint("LEFT", tabRow, "LEFT", 0, 0) end
        local mode = t[1]
        b:SetScript("OnClick", function() SetMode(mode); eb:SetFocus() end)
        tabBtns[mode] = b
        prev = b
    end

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
    BNB.ToggleNotePicker(anchor, nil)
end

function BNB.NotePickerShown()
    return picker ~= nil and picker:IsShown()
end

function BNB.ToggleNotePicker(anchor, opts)
    Build()
    if picker:IsShown() then
        local same = anchor == _anchor
        Close()
        if same then return end
    end
    _anchor = anchor
    _opts = opts or {}
    -- The Notes / BigNoteBox switch: the list moves down under it
    tabRow:SetShown(_opts.onPlace ~= nil)
    list:ClearAllPoints()
    local over = _opts.onPlace and tabRow or eb:GetParent()
    list:SetPoint("TOPLEFT",  over, "BOTTOMLEFT",  0, -4)
    list:SetPoint("TOPRIGHT", over, "BOTTOMRIGHT", 0, -4)
    SetMode("notes")
    if not anchor._bnbSendPickHooked then
        anchor._bnbSendPickHooked = true
        -- The button hides with the main window: the search goes with it
        anchor:HookScript("OnHide", Close)
    end
    picker:ClearAllPoints()
    if anchor == BNB._toolbarMenuBtn then   -- top bar menu (ALL-112): the right-most icon
        picker:SetPoint("TOPRIGHT", anchor, "BOTTOMRIGHT", 0, -4)
    else
        picker:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -4)
    end
    eb:SetText("")
    Refresh()
    -- Over Focus mode too (the editor toolbar's link button, ALL-478)
    BNB.SeatWindow(picker, "DIALOG")
    picker:Show()
    picker:Raise()
    eb:SetFocus()
end

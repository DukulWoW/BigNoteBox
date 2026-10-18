-- BigNoteBox UI/NoteTags.lua -- Tags for one note (2026-10-17)
--
-- A small window, the size of Save as template, opened from the note
-- right-click menu (Add tags / Edit tags) and the tag chip menu. It only adds
-- and removes tags on that one note (Dukul: "an easy tag manager for one note
-- only ... no deleting tag from all other notes"); renaming or deleting a tag
-- everywhere stays in the Tag Manager. Top: an add box (Enter adds, commas
-- add several, Tab completes to the first tag in the list). Middle: the
-- note's tags as chips with an x. Bottom: every tag in use with a tick box,
-- filtered by what is typed. Changes save at once. Opens over the middle of
-- the main window, as the New Note dialog does.
--
-- A tag's colour (ALL-106, Core/TagColors.lua) is set from the right-click
-- menu of a chip or a list row, here and on the editor's chips.
--
-- Public API:
--   BNB.OpenNoteTags(noteID)
--   BNB.NoteTagMenu(root, noteID, tag, opts)   tag menu on a ContextMenu builder
--     opts.filter   adds Filter notes by this tag (the editor's chips)
--     opts.edit     adds Edit tags... (opens this window)

local BNB = BigNoteBox
if not BNB then return end
local L = BNB.L

local W, PAD, FOOT_H = 340, 14, 40
local EB_H       = 22
local CHIP_H     = 20   -- under 20 the border corners overlap (Dukul, 2026-10-17)
local SWATCH_W, SWATCH_H = 46, 11   -- Dukul's 93 x 22 swatch, as in the colour menu
local NAME_MAX   = W - 2 * PAD - 24 - 24 - SWATCH_W - 12 - 40   -- check box, swatch, count
local CHIP_GAP   = 4
local ROW_H      = 22
local LIST_ROWS  = 7
-- As the editor's tag strip (UI/NoteEditor.lua MAX_TAGS / MAX_TAG_LEN)
local MAX_TAGS, MAX_TAG_LEN = 24, 20

local _f, _addEB, _chipArea, _noneLbl, _listLbl, _sf, _ct, _emptyLbl, _closeBtn
local _noteID
local _chips, _rows = {}, {}
local _shown = {}   -- the list's tags in row order (Tab completes to the first)

local function NoteLocked(note)
    local K = BNB._NoteListKit
    return note and K and K.NoteIsLocked and K.NoteIsLocked(note) or false
end

local function CopyTags(note)
    local t = {}
    for _, tag in ipairs(note and note.tags or {}) do t[#t + 1] = tag end
    return t
end

local function HasTag(tags, tag)
    local low = tag:lower()
    for i, t in ipairs(tags) do
        if t:lower() == low then return i end
    end
end

--------------------------------------------------------------------------------
-- WRITES (always a fresh table through UpdateNote, so the tag index follows)
--------------------------------------------------------------------------------
-- raw may hold several tags split by commas; returns true when one was added
local function AddTags(id, raw)
    local note = id and BNB.GetNote(id); if not note then return false end
    local tags, added = CopyTags(note), false
    for part in tostring(raw or ""):gmatch("[^,]+") do
        local text = part:match("^%s*(.-)%s*$") or ""
        if text ~= "" then
            if #text > MAX_TAG_LEN then BNB:Print(L["TAG_TOO_LONG"])
            elseif #tags >= MAX_TAGS then BNB:Print(L["TAG_MAX"]); break
            else
                text = BNB.NormalizeTag(text)
                if not HasTag(tags, text) then tags[#tags + 1] = text; added = true end
            end
        end
    end
    if added then BNB.UpdateNote(id, { tags = tags }) end
    return added
end

local function RemoveTag(id, tag)
    local note = id and BNB.GetNote(id); if not note then return end
    local tags = CopyTags(note)
    local i = HasTag(tags, tag); if not i then return end
    table.remove(tags, i)
    BNB.UpdateNote(id, { tags = tags })
end

-- Rename on this note only: the old tag's place in the list is kept
local function RenameOnNote(id, old, new)
    local note = id and BNB.GetNote(id); if not note then return end
    new = (new or ""):match("^%s*(.-)%s*$") or ""
    if new == "" then return end
    if #new > MAX_TAG_LEN then BNB:Print(L["TAG_TOO_LONG"]); return end
    new = BNB.NormalizeTag(new)
    local tags = CopyTags(note)
    local i = HasTag(tags, old); if not i then return end
    if new == tags[i] then return end
    local dup = HasTag(tags, new)
    if dup and dup ~= i then table.remove(tags, i) else tags[i] = new end
    BNB.UpdateNote(id, { tags = tags })
end

local function PopupEditBox(self) return self.editBox or self.EditBox end

StaticPopupDialogs["BNB_NOTE_TAG_RENAME"] = {
    preferredIndex = 3,
    text = "%s", hasEditBox = true, maxLetters = MAX_TAG_LEN,
    button1 = L["SAVE"], button2 = L["CANCEL"],
    OnShow = function(self, data)
        local eb = PopupEditBox(self)
        if eb and data then eb:SetText(data.tag or ""); eb:HighlightText() end
    end,
    OnAccept = function(self, data)
        local eb = PopupEditBox(self)
        if data and eb then RenameOnNote(data.id, data.tag, eb:GetText()) end
    end,
    EditBoxOnEnterPressed = function(eb)
        local p = eb:GetParent()
        if p.data then RenameOnNote(p.data.id, p.data.tag, eb:GetText()) end
        p:Hide()
    end,
    EditBoxOnEscapePressed = function(eb) eb:GetParent():Hide() end,
    timeout = 0, whileDead = true, hideOnEscape = true,
}

--------------------------------------------------------------------------------
-- THE TAG MENU (editor chips, this window's chips and list rows)
--------------------------------------------------------------------------------
function BNB.NoteTagMenu(root, noteID, tag, opts)
    opts = opts or {}
    local note = noteID and BNB.GetNote(noteID)
    if not note then return end
    local locked = NoteLocked(note)
    local onNote = HasTag(note.tags or {}, tag) ~= nil
    local TC = BNB.TagColors
    root:CreateTitle(TC and TC.Text(tag) or tag)
    if opts.filter and onNote and BNB.FilterByTag then
        root:CreateButton(L["NT_MENU_FILTER"], function() BNB.FilterByTag(tag) end, { icon = "filter" })
    end
    if onNote then
        root:CreateButton(L["NT_MENU_RENAME"], function()
            local d = StaticPopup_Show("BNB_NOTE_TAG_RENAME",
                string.format(L["NT_RENAME_PROMPT"], tag), nil, { id = noteID, tag = tag })
            if d and _f and _f:IsShown() then d:Raise() end
        end, { icon = "rename", disabled = locked, tip = L["NT_MENU_RENAME"], tipSub = L["NT_MENU_RENAME_TIP"] })
        root:CreateButton(L["NT_MENU_REMOVE"], function() RemoveTag(noteID, tag) end,
            { icon = "clear-note-history", danger = true, disabled = locked })
    else
        root:CreateButton(L["NT_MENU_ADD"], function() AddTags(noteID, tag) end,
            { icon = "tags-add", disabled = locked })
    end
    if TC then TC.AddMenu(root, tag) end
    if opts.edit then
        root:CreateDivider()
        root:CreateButton(L["NT_MENU_EDIT"], function() BNB.OpenNoteTags(noteID) end,
            { icon = "tags-edit", disabled = locked })
    end
end

--------------------------------------------------------------------------------
-- CHIPS (the note's tags)
--------------------------------------------------------------------------------
local function PaintChip(chip, tag)
    local TC = BNB.TagColors
    if TC and TC.PaintChip(chip, tag) then return end
    -- No colour: the editor's chip look
    if BigNoteBoxDB and BigNoteBoxDB.skinMode and BNB.GetSkinPreset then
        local p = BNB.GetSkinPreset()
        local r, g, b = BNB.SkinButtonOf(p)
        local br, bg_, bb, ba = BNB.SkinBorderOf(p)
        BNB.SetBackdrop(chip, r, g, b, 0.92, br, bg_, bb, ba)
    else
        BNB.SetBackdrop(chip, 0.15, 0.15, 0.20, 1, 0.35, 0.35, 0.40, 1)
    end
end

local function GetChip(i)
    local chip = _chips[i]
    if chip then return chip end
    chip = BNB.CreateBackdropFrame("Button", nil, _chipArea)
    chip:SetHeight(CHIP_H)
    chip:RegisterForClicks("RightButtonUp")
    local lbl = chip:CreateFontString(nil, "OVERLAY", "BNBFontNormalSmall")
    lbl:SetPoint("LEFT", chip, "LEFT", 8, 0)   -- room from the edge (Dukul, 2026-10-17)
    lbl:SetWordWrap(false)
    BNB.SetTextWhite(lbl)
    chip._lbl = lbl
    local x = CreateFrame("Button", nil, chip)
    x:SetSize(14, 14)
    x:SetPoint("RIGHT", chip, "RIGHT", -2, 0)
    -- Shown only while the pointer is on the chip (Dukul, 2026-10-17)
    x:SetAlpha(0)
    local xl = x:CreateFontString(nil, "OVERLAY", "BNBFontNormalSmall")
    xl:SetAllPoints(); xl:SetText("x"); xl:SetTextColor(0.75, 0.75, 0.75)
    x:SetScript("OnEnter", function(self)
        self:SetAlpha(1)
        xl:SetTextColor(1, 0.3, 0.3)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(L["NT_REMOVE_TIP"], 1, 1, 1)
        GameTooltip:Show()
    end)
    x:SetScript("OnLeave", function()
        xl:SetTextColor(0.75, 0.75, 0.75); GameTooltip:Hide()
    end)
    x:SetScript("OnClick", function() if chip._tag then RemoveTag(_noteID, chip._tag) end end)
    chip._x = x
    -- The x shows while the pointer is on the chip: a watcher hides it once
    -- it is off (a leave can come while IsMouseOver still says yes)
    local function Watch(self)
        if not self:IsMouseOver() then
            self._x:SetAlpha(0)
            self:SetScript("OnUpdate", nil)
        end
    end
    chip:SetScript("OnEnter", function(self)
        self._x:SetAlpha(1)
        self:SetScript("OnUpdate", Watch)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(self._tag or "", 1, 1, 1)
        GameTooltip:AddLine(L["NT_CHIP_TIP"], 0.6, 0.6, 0.6, true)
        GameTooltip:Show()
    end)
    chip:SetScript("OnLeave", function() GameTooltip:Hide() end)
    chip:SetScript("OnClick", function(self)
        local tag = self._tag; if not tag then return end
        BNB.ContextMenu.Open(self, function(root) BNB.NoteTagMenu(root, _noteID, tag) end)
    end)
    _chips[i] = chip
    return chip
end

-- Lays the chips out in rows; returns the area's height
local function LayoutChips(tags)
    local areaW = W - 2 * PAD
    local x, row = 0, 0
    for i, tag in ipairs(tags) do
        local chip = GetChip(i)
        chip._tag = tag
        chip._lbl:SetText(tag)
        PaintChip(chip, tag)
        local w = math.max(chip._lbl:GetStringWidth(), #tag * 6) + 8 + 4 + 16
        w = math.min(w, areaW)
        chip:SetWidth(w)
        if x > 0 and x + w > areaW then x, row = 0, row + 1 end
        chip:ClearAllPoints()
        chip:SetPoint("TOPLEFT", _chipArea, "TOPLEFT", x, -row * (CHIP_H + CHIP_GAP))
        chip:Show()
        x = x + w + CHIP_GAP
    end
    for i = #tags + 1, #_chips do _chips[i]:Hide(); _chips[i]._tag = nil end
    _noneLbl:SetShown(#tags == 0)
    if #tags == 0 then return CHIP_H end
    return (row + 1) * CHIP_H + row * CHIP_GAP
end

--------------------------------------------------------------------------------
-- THE LIST (every tag in use, ticked when on the note)
--------------------------------------------------------------------------------
local function GetRow(i)
    local row = _rows[i]
    if row then return row end
    row = CreateFrame("Button", nil, _ct)
    row:SetHeight(ROW_H)
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    local hl = row:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints(); hl:SetColorTexture(1, 1, 1, 0.08)
    local cb = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
    cb:SetSize(22, 22)
    cb:SetPoint("LEFT", row, "LEFT", -2, 0)
    cb:EnableMouse(false)   -- the row takes the click
    row._cb = cb
    local name = row:CreateFontString(nil, "OVERLAY", "BNBFontHighlightSmall")
    name:SetPoint("LEFT", cb, "RIGHT", 2, 0)
    name:SetJustifyH("LEFT"); name:SetWordWrap(false)
    row._name = name
    -- The tag's colour after its name, the colour menu's wide swatch
    -- (Dukul, 2026-10-17: "[ ] Alliance <color swatch> (X)")
    local sw = row:CreateTexture(nil, "ARTWORK")
    sw:SetSize(SWATCH_W, SWATCH_H)
    sw:SetPoint("LEFT", name, "RIGHT", 6, 0)
    row._sw = sw
    local count = row:CreateFontString(nil, "OVERLAY", "BNBFontNormalSmall")
    count:SetPoint("RIGHT", row, "RIGHT", -4, 0)
    count:SetTextColor(0.5, 0.5, 0.5)
    row._count = count
    row:SetScript("OnClick", function(self, btn)
        local tag = self._tag; if not tag then return end
        if btn == "RightButton" then
            BNB.ContextMenu.Open(self, function(root) BNB.NoteTagMenu(root, _noteID, tag) end)
            return
        end
        if self._on then RemoveTag(_noteID, tag) else AddTags(_noteID, tag) end
    end)
    row:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(self._tag or "", 1, 1, 1)
        local tip = L["NT_ROW_TIP_OFF"]
        if self._on then tip = L["NT_ROW_TIP_ON"] end
        GameTooltip:AddLine(tip, 0.6, 0.6, 0.6, true)
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    _rows[i] = row
    return row
end

local function FillList(note)
    local filter = (_addEB:GetRealText() or ""):match("^%s*(.-)%s*$"):lower()
    -- After a comma only the last part filters ("raid, bo" -> "bo")
    filter = filter:match("([^,]*)$"):match("^%s*(.-)%s*$")
    local tags = note and note.tags or {}
    local TC = BNB.TagColors
    wipe(_shown)
    local n = 0
    for _, e in ipairs(BNB.GetAllTags()) do
        if filter == "" or e._key:find(filter, 1, true) then
            n = n + 1
            local row = GetRow(n)
            row._tag = e.tag
            row._on = HasTag(tags, e.tag) ~= nil
            row._cb:SetChecked(row._on)
            if TC then TC.Swatch(row._sw, e.tag, true) end
            -- The name as wide as its text (capped), so the swatch follows it
            row._name:SetWidth(0)
            row._name:SetText(e.tag)
            row._name:SetWidth(math.min(math.ceil(row._name:GetStringWidth()) + 2, NAME_MAX))
            row._count:SetText("(" .. e.count .. ")")
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT",  _ct, "TOPLEFT",  0, -(n - 1) * ROW_H)
            row:SetPoint("TOPRIGHT", _ct, "TOPRIGHT", 0, -(n - 1) * ROW_H)
            row:Show()
            if not row._on then _shown[#_shown + 1] = e.tag end
        end
    end
    for i = n + 1, #_rows do _rows[i]:Hide(); _rows[i]._tag = nil end
    local empty = L["NT_LIST_EMPTY"]
    if filter ~= "" then empty = L["NT_LIST_NO_MATCH"] end
    _emptyLbl:SetText(empty)
    _emptyLbl:SetShown(n == 0)
    _sf:FinaliseHeight(n * ROW_H)
end

--------------------------------------------------------------------------------
-- WINDOW
--------------------------------------------------------------------------------
local function Label(f, text)
    local l = f:CreateFontString(nil, "OVERLAY", "BNBFontNormalSmall")
    l:SetJustifyH("LEFT")
    l:SetTextColor(0.78, 0.78, 0.78)
    l:SetText(text)
    return l
end

local _topY, _chipsLbl
local function Layout()
    local note = _noteID and BNB.GetNote(_noteID)
    if not note then return end
    _f:SetWindowTitle(string.format(L["NT_TITLE_FMT"], note.title or ""))
    local y = _topY - EB_H - 12
    _chipsLbl:ClearAllPoints()
    _chipsLbl:SetPoint("TOPLEFT", _f, "TOPLEFT", PAD, y)
    y = y - 16
    _chipArea:ClearAllPoints()
    _chipArea:SetPoint("TOPLEFT", _f, "TOPLEFT", PAD, y)
    local h = LayoutChips(note.tags or {})
    _chipArea:SetHeight(h)
    y = y - h - 12
    _listLbl:ClearAllPoints()
    _listLbl:SetPoint("TOPLEFT", _f, "TOPLEFT", PAD, y)
    y = y - 16
    _sf:ClearAllPoints()
    _sf:SetPoint("TOPLEFT", _f, "TOPLEFT", PAD, y)
    _sf:SetSize(W - 2 * PAD - 20, LIST_ROWS * ROW_H)
    y = y - LIST_ROWS * ROW_H - 10
    _f:SetHeight(-y + FOOT_H)
    FillList(note)
end

local function Build()
    if _f then return end
    local f = BNB.CreateToolWindow({
        name = "BNBNoteTagsFrame", w = W, h = 300, title = L["NT_TITLE"],
        pad = PAD, cw = W - 2 * PAD, footH = FOOT_H,
        strata = "DIALOG", toplevel = true, escClose = true, keyEsc = true,
        onHide = function() _noteID = nil end,
    })
    _f = f
    _topY = -((f._isSkin and BNB.TOOL_SKIN_TITLE_H or 28) + 12)

    local eb = CreateFrame("EditBox", nil, f, "BackdropTemplate")
    BNB.EnsureBackdrop(eb)
    BNB.SetBackdropDark(eb)
    eb:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, _topY)
    eb:SetSize(W - 2 * PAD, EB_H)
    eb:SetFontObject("BNBFontNormal")
    eb:SetAutoFocus(false)
    eb:SetMaxLetters(200)   -- several tags split by commas
    eb:SetTextInsets(4, 4, 0, 0)
    BNB.AddPlaceholder(eb, L["NT_ADD_HINT"], 0.55, 0.55, 0.55)
    eb:SetScript("OnEscapePressed", function(self) self:ClearFocus(); f:Hide() end)
    eb:SetScript("OnEnterPressed", function(self)
        local text = self:GetRealText() or ""
        if text:match("^%s*$") then self:ClearFocus(); return end
        AddTags(_noteID, text)
        self:SetRealText("")
        self:SetFocus()
        local note = _noteID and BNB.GetNote(_noteID)
        if note then FillList(note) end
    end)
    -- Tab: the typed part after the last comma becomes the first tag the
    -- list shows that the note does not have yet
    eb:SetScript("OnTabPressed", function(self)
        local first = _shown[1]; if not first then return end
        local text = self:GetRealText() or ""
        local head = text:match("^(.*,)%s*[^,]*$") or ""
        self:SetRealText(head .. (head ~= "" and " " or "") .. first)
        self:SetCursorPosition(#self:GetText())
    end)
    eb:SetScript("OnTextChanged", function(_, userInput)
        if not userInput then return end
        local note = _noteID and BNB.GetNote(_noteID)
        if note then FillList(note) end
    end)
    eb:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(L["NT_ADD_HINT"], 1, 1, 1)
        GameTooltip:AddLine(L["NT_ADD_TIP"], 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    eb:SetScript("OnLeave", function() GameTooltip:Hide() end)
    _addEB = eb

    _chipsLbl = Label(f, L["NT_ON_NOTE"])
    _chipArea = CreateFrame("Frame", nil, f)
    _chipArea:SetWidth(W - 2 * PAD)
    _noneLbl = _chipArea:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    _noneLbl:SetPoint("LEFT", _chipArea, "LEFT", 0, 0)
    _noneLbl:SetText(L["NT_NONE"])

    _listLbl = Label(f, L["NT_ALL_TAGS"])
    local cw = W - 2 * PAD - 24
    _sf, _ct = BNB.CreateAutoScrollPanel(f, cw, W - 2 * PAD - 20)
    _emptyLbl = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    _emptyLbl:SetPoint("TOPLEFT", _sf, "TOPLEFT", 2, -4)

    _closeBtn = BNB.CreateButton(nil, f, L["CLOSE"], 90, 26)
    _closeBtn:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -PAD, 6)
    _closeBtn:SetScript("OnClick", function() f:Hide() end)
end

local function Place()
    _f:ClearAllPoints()
    local mf = BNB.mainFrame
    if mf and mf:IsShown() then _f:SetPoint("CENTER", mf, "CENTER", 0, 20)
    else _f:SetPoint("CENTER", UIParent, "CENTER", 0, 80) end
end

function BNB.OpenNoteTags(noteID)
    local note = noteID and BNB.GetNote(noteID)
    if not note then return end
    Build()
    _noteID = noteID
    _addEB:SetRealText("")
    Layout()
    Place()
    _f:Show()
    _f:Raise()
    _addEB:SetFocus()
end

-- Live: this note's tags, any tag count, a colour, the note gone
local function Refresh()
    if _f and _f:IsShown() and _noteID then
        if BNB.GetNote(_noteID) then Layout() else _f:Hide() end
    end
end
BNB.RegisterMessage("NoteTags", "NoteChanged", function(_, id, fields)
    if id == _noteID or (fields and (fields.tags or fields._clear)) then Refresh() end
end)
BNB.RegisterMessage("NoteTags", "NoteDeleted", Refresh)
BNB.RegisterMessage("NoteTags", "NoteRestored", Refresh)
BNB.RegisterMessage("NoteTags", "TagColorChanged", Refresh)

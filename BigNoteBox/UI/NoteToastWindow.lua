-- BigNoteBox UI/NoteToastWindow.lua
-- A note's own toast (ALL-383): style and time on screen, opened by the
-- Toast... button on the Situation tab (Note Settings and sticky settings,
-- both through BNB.CreateSituationEditor). The same two fields the toast's
-- right-click menu sets (Features/ContextNotes.lua NoteMenu): note.toastStyle
-- and note.toastHold, nil = as in Settings, toastHold 0 = until clicked.
--
-- Public API:
--   BNB.NoteToastWindow.Open(noteID, host)   beside host; a second open re-points it
--   BNB.NoteToastWindow.Close(host)          only while opened from host (nil = any)
--   BNB.NoteToastWindow.Rebind(noteID, host) the host switched note: follow it
-- The style is a [<] [name] [>] row (ALL-401): the name opens the style
-- picker (UI/ToastStylePicker.lua), the arrows step through As in Settings
-- and the styles.

local BNB = BigNoteBox
if not BNB then return end
local L = BNB.L

local NTW = {}
BNB.NoteToastWindow = NTW

local W, H, PAD = 300, 196, 16
local DEFAULT = "default"   -- the dropdowns' value for nil (as in Settings)

local _f, _noteID, _host
local _styleBtn, _holdDd
local _holdEntries = {}
local PICK_KEY = "noteToast"   -- the style picker's owner key

local function FillHolds()
    wipe(_holdEntries)
    _holdEntries[1] = { label = L["TOAST_CM_DEFAULT"], value = DEFAULT }
    for _, secs in ipairs(BNB.TOAST_HOLD_CHOICES or { 5, 10, 30, 60 }) do
        _holdEntries[#_holdEntries + 1] = { label = string.format(L["TOAST_CM_SECONDS"], secs), value = secs }
    end
    _holdEntries[#_holdEntries + 1] = { label = L["TOAST_CM_UNTIL_CLICKED"], value = 0 }
end

-- Shows the note's saved choice; a style this client cannot draw reads as
-- As in Settings on the button, the saved key is kept
local function StyleName(note)
    local TS = BNB.ToastStyles
    local def = note.toastStyle and TS.Get(note.toastStyle)
    if def and TS.Usable(def) then return TS.Label(def) end
    return L["TOAST_CM_DEFAULT"]
end

local function Refresh()
    local note = _noteID and BNB.GetNote(_noteID)
    if not (_f and note) then return end
    _styleBtn:SetText(StyleName(note))
    BNB.TruncateButtonText(_styleBtn)
    _holdDd:SetSelected(note.toastHold or DEFAULT)
    local title = note.title
    if not title or title == "" then title = L["TOAST_CM_STYLE"] end
    _f._noteLbl:SetText(title)
end

local function Save(field, v)
    if not (_noteID and BNB.GetNote(_noteID)) then return end
    if v == DEFAULT then
        BNB.UpdateNote(_noteID, { _clear = { field } })
    else
        BNB.UpdateNote(_noteID, { [field] = v })
    end
end

-- The style picker's handlers for the note shown (nil = As in Settings)
local function StyleHandlers()
    local id = _noteID
    return {
        noteID = id,
        get = function()
            local n = BNB.GetNote(id)
            return n and n.toastStyle
        end,
        set = function(k) Save("toastStyle", k or DEFAULT) end,
        follow = "TOAST_CM_DEFAULT", followTip = "TOAST_PICKER_DEFAULT_TIP",
        following = function() return BNB.ToastStyles.Current() end,
    }
end

local function Label(parent, text, anchor, y)
    local l = parent:CreateFontString(nil, "OVERLAY", "BNBFontNormalSmall")
    l:SetPoint("TOPLEFT", anchor, "TOPLEFT", 0, y)
    l:SetText(text)
    l:SetTextColor(0.78, 0.78, 0.78)
    return l
end

local function Build()
    local f = BNB.CreateToolWindow({
        name = "BigNoteBoxNoteToastFrame", w = W, h = H, title = L["NOTE_TOAST_TITLE"],
        escClose = true, toplevel = true,
    })
    local top = f._isSkin and BNB.TOOL_SKIN_TITLE_H or 32
    local cw = W - 2 * PAD

    local host = CreateFrame("Frame", nil, f)
    host:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, -(top + 8))
    host:SetSize(cw, 1)

    -- Which note this is: the window can stay open across a note switch
    local noteLbl = f:CreateFontString(nil, "OVERLAY", "BNBFontHighlight")
    noteLbl:SetPoint("TOPLEFT", host, "TOPLEFT", 0, 0)
    noteLbl:SetWidth(cw); noteLbl:SetJustifyH("LEFT"); noteLbl:SetWordWrap(false)
    f._noteLbl = noteLbl

    Label(f, L["NOTE_TOAST_STYLE"], host, -26)
    local TSP = BNB.ToastStylePicker
    local ARW = 22
    local prev = BNB.CreateButton(nil, f, "<", ARW, 22)
    _styleBtn  = BNB.CreateButton(nil, f, "", cw - 2 * (ARW + 4), 22)
    local nxt  = BNB.CreateButton(nil, f, ">", ARW, 22)
    prev:SetPoint("TOPLEFT", host, "TOPLEFT", 0, -43)
    _styleBtn:SetPoint("LEFT", prev, "RIGHT", 4, 0)
    nxt:SetPoint("LEFT", _styleBtn, "RIGHT", 4, 0)
    prev:SetScript("OnClick", function() if _noteID and TSP then TSP.Step(StyleHandlers(), -1, true) end end)
    nxt:SetScript("OnClick", function() if _noteID and TSP then TSP.Step(StyleHandlers(), 1, true) end end)
    _styleBtn:SetScript("OnClick", function()
        if _noteID and TSP then TSP.Open(PICK_KEY, f, StyleHandlers()) end
    end)
    for btn, key in pairs({ [prev] = "TOAST_STYLE_PREV", [_styleBtn] = "TOAST_STYLE_BROWSE_TIP",
                            [nxt] = "TOAST_STYLE_NEXT" }) do
        local text = L[key]
        btn:HookScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(text, 1, 1, 1)
            GameTooltip:Show()
        end)
        btn:HookScript("OnLeave", function() GameTooltip:Hide() end)
    end

    Label(f, L["NOTE_TOAST_HOLD"], host, -76)
    FillHolds()
    _holdDd = BNB.CreateValueDropdown(f, _holdEntries, DEFAULT,
        function(v) Save("toastHold", v) end, cw, 26)
    _holdDd:SetPoint("TOPLEFT", host, "TOPLEFT", 0, -91)

    local testBtn = BNB.CreateButton(nil, f, L["CFG_TOAST_TEST_BTN"], 90, 22)
    testBtn:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", PAD, 14)
    testBtn:SetScript("OnClick", function()
        if _noteID and BNB.TestNoteToast then BNB.TestNoteToast(_noteID) end
    end)
    testBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(L["CFG_TOAST_TEST_BTN"], 1, 1, 1)
        GameTooltip:AddLine(L["NOTE_TOAST_TEST_TIP"], 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    testBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- The toast's right-click menu or the other editor changed the note
    BNB.RegisterMessage("NoteToastWindow", "NoteChanged", function(_, id)
        if id == _noteID and f:IsShown() then Refresh() end
    end)
    BNB.RegisterMessage("NoteToastWindow", "NoteDeleted", function(_, id)
        if id == _noteID then f:Hide() end
    end)
    f:HookScript("OnHide", function()
        _noteID, _host = nil, nil
        if TSP then TSP.Close(PICK_KEY) end
    end)
    return f
end

function NTW.Open(noteID, host)
    if not (noteID and BNB.GetNote(noteID)) then return end
    _f = _f or Build()
    _noteID, _host = noteID, host
    BNB.PlaceBeside(_f, host, W)
    Refresh()
    -- Re-pointed at another note: an open style picker follows it
    if BNB.ToastStylePicker then BNB.ToastStylePicker.Rebind(PICK_KEY, StyleHandlers()) end
    BNB.SeatWindow(_f, _f._strata)
    _f:Show(); _f:Raise()
end

-- The Situation tab's toast button: a second click closes it (Dukul, 2026-10-08)
function NTW.Toggle(noteID, host)
    if _f and _f:IsShown() and host == _host and noteID == _noteID then
        _f:Hide()
    else
        NTW.Open(noteID, host)
    end
end

function NTW.Close(host)
    if _f and _f:IsShown() and (host == nil or host == _host) then _f:Hide() end
end

function NTW.Rebind(noteID, host)
    if not (_f and _f:IsShown() and host == _host) then return end
    if not (noteID and BNB.GetNote(noteID)) then _f:Hide(); return end
    _noteID = noteID
    Refresh()
    if BNB.ToastStylePicker then BNB.ToastStylePicker.Rebind(PICK_KEY, StyleHandlers()) end
end

-- BigNoteBox UI/FindReplace.lua - find and replace inside a note (ALL-582)
--
-- Opened from the formatting toolbar's tb-search-replace button (right of
-- Add to dictionary, Dukul's art) or Ctrl+F in the note body, in the main
-- editor and in Focus mode. A row of its own under the toolbars, there only
-- while open: the note body moves down for it, so nothing covers the text
-- (Dukul, 2026-10-26; the first build was a window over the note).
--   line 1: Find box | Match case | Whole word | "3 of 5" | up | down | X
--   line 2: Replace box | Replace | Replace all
-- The checkbox labels go (the boxes keep their tooltips) when the row is
-- too narrow for them.
--
--   * Plain text, never a Lua pattern. Without Match case only A-Z fold
--     (never lower() on player text: WoW's changes UTF-8 lead bytes).
--   * Hidden text is never found: link codes (the whole link), textures,
--     atlases and colour codes (a hit there would break the link).
--   * Every hit is tinted, the current one stronger (UI/TextLines.lua, kind
--     "f" / "F"); up / down scroll it into view and put the text cursor
--     after it. The row keeps the keyboard.
--   * Replace and Replace all go through BNB.ReplaceInEditor: one undo step
--     each, the note marked changed, nothing on a locked note. When nothing
--     is left to replace the row says so ("Done: 18 replaced").
--   * Edit mode only: the main editor's rich View mode switches to Edit;
--     the row closes when its note box goes away (View mode, Focus mode
--     opening or closing, no note) or another note is opened (ALL-602).
--   * Stays open while you edit the note (the hits follow the text); Esc in
--     its boxes, its X or the button again closes it.
--
-- The editors place the row: BNB.UpdateBodyTopAnchor (UI/NoteEditor.lua)
-- and LayoutFocusBars (UI/FocusEditor.lua) put FR.RowOf(kind) under their
-- last bar while it is shown.
--
-- Public API:
--   BNB.FindReplace.Toggle(kind, eb, parent)  kind "main" / "focus"
--   BNB.FindReplace.Open(kind, eb, parent)    (Ctrl+F: open, or focus Find)
--   BNB.FindReplace.RowOf(kind)               the row frame, or nil
--   BNB.FindReplace.Close()

local BNB = BigNoteBox
local L   = BNB.L

local FR = {}
BNB.FindReplace = FR

local PAD, EB_H, LINE_GAP = 4, 22, 4
local ROW_H     = PAD + EB_H + LINE_GAP + EB_H + PAD + 1   -- + the rule under it
local STATUS_W  = 110
local MIN_BOX   = 120    -- narrower than this: the checkbox labels go
local MAX_HITS  = 5000   -- counted
local MAX_DRAWN = 100    -- tinted; above that only the current one

local _rows = {}         -- kind -> row (built on first open)
local R                  -- the open row, or nil
local _eb                -- its note box
local _noteID            -- the note it was opened in (ALL-602)
local _hits, _hitText, _cur = {}, nil, 0
local _msg, _msgR, _msgG, _msgB          -- "Done: 18 replaced" until the next search input
local _lastFind = ""
local _matchCase, _wholeWord = false, false   -- for the session
local _ctls, _hooked = {}, {}

-- ── Searching ────────────────────────────────────────────────────────────────

local FOLD = {}
for c = 65, 90 do FOLD[string.char(c)] = string.char(c + 32) end
local function Fold(s) return (s:gsub("[A-Z]", FOLD)) end

-- A letter, digit or _ ; any byte of a non-ASCII character counts as a letter
local function WordByte(b)
    return b and (b >= 128 or b == 95 or (b >= 48 and b <= 57) or (b >= 65 and b <= 90) or (b >= 97 and b <= 122))
end

-- The hidden parts of the text as { first, last } in order: a whole link
-- (|H data |h text |h), a texture, an atlas, a colour code, |r. A typed
-- pipe is "||"
local function Hidden(text)
    local out = {}
    if not text:find("|", 1, true) then return out end
    local i = 1
    while true do
        local p = text:find("|", i, true)
        if not p then break end
        local c, e = text:sub(p + 1, p + 1), nil
        if c == "|" then
            i = p + 2
        else
            if c == "c" then
                if text:find("^%x%x%x%x%x%x%x%x", p + 2) then e = p + 9 end
            elseif c == "r" or c == "n" then
                e = p + 1
            elseif c == "H" then
                local _, e2 = text:find("|h.-|h", p + 2); e = e2
            elseif c == "T" then
                local _, e2 = text:find("|t", p + 2, true); e = e2
            elseif c == "A" then
                local _, e2 = text:find("|a", p + 2, true); e = e2
            end
            if e then out[#out + 1] = { p, e }; i = e + 1 else i = p + 1 end
        end
    end
    return out
end

-- Every hit of needle in text -> a list of { first, last }
local function FindAll(text, needle, matchCase, wholeWord)
    local hits = {}
    if needle == "" or text == "" then return hits end
    local hay, nd = text, needle
    if not matchCase then hay, nd = Fold(text), Fold(needle) end
    local hidden, h = Hidden(text), 1
    local wordStart = WordByte(nd:byte(1))
    local wordEnd   = WordByte(nd:byte(#nd))
    local pos = 1
    while #hits < MAX_HITS do
        local s = hay:find(nd, pos, true)
        if not s then break end
        local e = s + #nd - 1
        local ok = true
        -- hidden[h] = the first hidden part that ends at s - 1 or later
        while hidden[h] and hidden[h][2] < s - 1 do h = h + 1 end
        local cur = hidden[h]
        -- A hidden part right before the hit (a colour code) is no letter
        local afterHidden = cur and cur[2] == s - 1
        if afterHidden then cur = hidden[h + 1] end
        if cur and cur[1] <= e then ok = false end   -- inside a hidden part
        if ok and wholeWord then
            if wordStart and not afterHidden and WordByte(hay:byte(s - 1)) then ok = false end
            if wordEnd and WordByte(hay:byte(e + 1)) then ok = false end
        end
        if ok then
            hits[#hits + 1] = { s, e }
            pos = e + 1
        else
            pos = s + 1
        end
    end
    return hits
end
FR._FindAll = FindAll   -- offline tests

local function BodyText(eb)
    if not eb or eb._showingPlaceholder then return "" end
    return eb:GetText() or ""
end

local function Redraw()
    local ctl = _eb and _ctls[_eb]
    if ctl then ctl.Recolor() end
end

local function Locked() return BNB._editorLocked end

local function FindText() return R and R.findEb:GetText() or "" end

local function ShowStatus()
    if not R then return end
    local n, status = #_hits, R.status
    if _msg then
        status:SetText(_msg); status:SetTextColor(_msgR, _msgG, _msgB)
    elseif FindText() == "" then
        status:SetText("")
    elseif n == 0 then
        status:SetText(L["FIND_NONE"]); status:SetTextColor(1, 0.45, 0.45)
    else
        local fmt = L["FIND_COUNT_FMT"]
        if n >= MAX_HITS then fmt = L["FIND_COUNT_MANY_FMT"] end
        status:SetText(string.format(fmt, _cur, n)); status:SetTextColor(0.85, 0.85, 0.85)
    end
    local any, edit = n > 0, n > 0 and not Locked()
    R.prevBtn:SetEnabled(any); R.nextBtn:SetEnabled(any)
    R.replBtn:SetEnabled(edit); R.allBtn:SetEnabled(edit)
end

-- The hits again for the box's text; the current one = the first at or
-- after byte from (wrapping to the first)
local function Search(from)
    if not (R and _eb) then return end
    local text = BodyText(_eb)
    _hits = FindAll(text, FindText(), _matchCase, _wholeWord)
    _hitText = text
    _cur = #_hits > 0 and 1 or 0
    for i, h in ipairs(_hits) do
        if h[1] >= (from or 1) then _cur = i; break end
    end
    ShowStatus()
    Redraw()
end

-- The current hit into view, the text cursor after it
local function ShowCur()
    local h = _hits[_cur]
    if not (h and _eb and _eb:IsVisible() and _hitText == BodyText(_eb)) then return end
    _eb:SetCursorPosition(h[2])
    -- After the caret follow's own scroll (it runs on the cursor change)
    C_Timer.After(0, function()
        if not (_eb and _hits[_cur] == h) then return end
        local sf = _eb:GetParent()
        local top, lineH = BNB.TextLines.LineTop(_eb, h[1])
        if not (top and sf and sf.GetVerticalScroll) then return end
        local off, viewH = sf:GetVerticalScroll(), sf:GetHeight()
        if top >= off and top + lineH <= off + viewH then return end
        local range = sf:GetVerticalScrollRange() or 0
        sf:SetVerticalScroll(math.max(0, math.min(top - viewH / 3, range)))
    end)
end

local function Step(dir)
    _msg = nil
    if _hitText ~= BodyText(_eb) then
        local h = _hits[_cur]
        Search(h and h[1] or 1)
    end
    local n = #_hits
    if n == 0 then ShowStatus(); return end
    _cur = ((_cur - 1 + dir) % n) + 1
    ShowStatus()
    Redraw()
    ShowCur()
end

-- The main editor's rich View mode has no box: Edit mode first, then fn
local function InEdit(fn)
    if _eb == BNB._editorBody and BNB._editorInViewMode and BNB.AM_EnterEditMode then
        BNB.AM_EnterEditMode()
        C_Timer.After(0, function() if R and not BNB._editorInViewMode then fn() end end)
        return
    end
    fn()
end

local RED, GREEN = { 1, 0.45, 0.45 }, { 0.45, 0.85, 0.45 }
local function SetMsg(text, c)
    _msg, _msgR, _msgG, _msgB = text, c[1], c[2], c[3]
end

local function ReplaceOne()
    InEdit(function()
        if Locked() then SetMsg(L["FIND_LOCKED"], RED); ShowStatus(); return end
        local cur = _hits[_cur]
        Search(cur and cur[1] or 1)   -- the text may have moved since
        local h = _hits[_cur]
        if not h then return end
        local rep = R.replEb:GetText() or ""
        if not BNB.ReplaceInEditor(_eb, h[1], h[2], rep, true) then
            SetMsg(L["FIND_FAILED"], RED); ShowStatus(); return
        end
        _msg = nil
        Search(h[1] + #rep)   -- the next one after what went in
        if #_hits == 0 then SetMsg(L["FIND_DONE_NONE_LEFT"], GREEN); ShowStatus() end
        -- After ReplaceInEditor's own cursor move (next frame)
        C_Timer.After(0, ShowCur)
    end)
end

local function ReplaceAll()
    InEdit(function()
        if Locked() then SetMsg(L["FIND_LOCKED"], RED); ShowStatus(); return end
        Search(1)
        local n = #_hits
        if n == 0 then return end
        local text, rep = BodyText(_eb), R.replEb:GetText() or ""
        local parts, prev = {}, _hits[1][1]
        for _, h in ipairs(_hits) do
            parts[#parts + 1] = text:sub(prev, h[1] - 1)
            parts[#parts + 1] = rep
            prev = h[2] + 1
        end
        -- One range from the first hit to the last: one undo step
        if not BNB.ReplaceInEditor(_eb, _hits[1][1], _hits[n][2], table.concat(parts), true) then
            SetMsg(L["FIND_FAILED"], RED); ShowStatus(); return
        end
        -- Said plainly: the buttons grey out with nothing left, which read
        -- as stuck (Dukul, 2026-10-26)
        SetMsg(string.format(L["FIND_DONE_FMT"], n), GREEN)
        Search(1)
    end)
end

-- ── Placing the row ──────────────────────────────────────────────────────────

-- The editor of that kind places its rows again (the row in or out)
local function Relayout(kind)
    if kind == "main" then
        if BNB.UpdateBodyTopAnchor then BNB.UpdateBodyTopAnchor() end
    elseif BNB.ApplyFocusWysiwygBar then
        BNB.ApplyFocusWysiwygBar()
    end
end

function FR.Close(giveBack)
    if not R then return end
    local row, eb = R, _eb
    row.frame:Hide()   -- OnHide clears the state
    Relayout(row.kind)
    if giveBack and eb and eb:IsVisible() then eb:SetFocus() end
end

-- ── The box's hits drawn and kept up to date ─────────────────────────────────

local function Wire(eb)
    if _hooked[eb] then return end
    _hooked[eb] = true
    local sf = eb:GetParent()
    if BNB.TextLines and sf then
        _ctls[eb] = BNB.TextLines.Attach(eb, sf, function(text)
            if not (R and _eb == eb) then return nil end
            if text ~= _hitText or #_hits == 0 then return nil end
            if #_hits > MAX_DRAWN then
                local h = _hits[_cur]
                return h and { { h[1], h[2], "F" } } or nil
            end
            local list = {}
            for i, h in ipairs(_hits) do list[i] = { h[1], h[2], i == _cur and "F" or "f" } end
            return list
        end)
    end
    -- Typing in the note or another note shown: the hits follow the text
    eb:HookScript("OnTextChanged", function(self)
        if not (R and _eb == self) then return end
        BNB.Debounce("bnbFindReplace", 0.2, function()
            if not (R and _eb == self) then return end
            local h = _hits[_cur]
            Search(h and h[1] or 1)
        end)
    end)
    -- The box gone (rich View mode, Focus mode in or out, no note): the row
    -- goes with it, on the next frame (never inside the hide itself)
    eb:HookScript("OnHide", function(self)
        C_Timer.After(0, function()
            if R and _eb == self and not self:IsVisible() then FR.Close() end
        end)
    end)
end

-- ── Build ────────────────────────────────────────────────────────────────────

local function Box(row, hint)
    local bg = BNB.CreateBackdropFrame("Frame", nil, row.frame)
    BNB.SetBackdropDark(bg)
    bg:SetHeight(EB_H)
    local e = CreateFrame("EditBox", nil, bg)
    e:SetAllPoints(bg)
    e:SetTextInsets(6, 6, 0, 0)
    e:SetFontObject("BNBFontNormalSmall")
    e:SetAutoFocus(false)
    e:SetMaxLetters(200)
    BNB.SetTextWhite(e)
    e:SetScript("OnEscapePressed", function() FR.Close(true) end)
    -- A grey hint while empty (not BNB.AddPlaceholder: its text would be
    -- searched for)
    local ph = bg:CreateFontString(nil, "OVERLAY", "BNBFontNormalSmall")
    ph:SetPoint("LEFT", bg, "LEFT", 6, 0)
    ph:SetTextColor(0.5, 0.5, 0.5)
    ph:SetText(hint)
    local function Hint() if (e:GetText() or "") == "" then ph:Show() else ph:Hide() end end
    e:HookScript("OnTextChanged", Hint)
    return bg, e, Hint
end

local function Check(row, text, tip, onClick)
    local cb = CreateFrame("CheckButton", nil, row.frame, "UICheckButtonTemplate")
    cb:SetSize(22, 22)
    local lbl = row.frame:CreateFontString(nil, "OVERLAY", "BNBFontNormalSmall")
    lbl:SetPoint("LEFT", cb, "RIGHT", 1, 0)
    lbl:SetText(text)
    lbl:SetTextColor(0.85, 0.85, 0.85, 1)
    BNB.LabelHit(cb, lbl)
    BNB.CheckTip(cb, tip)
    cb:SetScript("OnClick", function(self) onClick(self:GetChecked() and true or false) end)
    return cb, lbl
end

-- Line 1 from the right edge in; the labels only while the Find box keeps
-- MIN_BOX
local function Fit(row)
    local w = row.frame:GetWidth()
    if not w or w <= 0 then return end
    local labels = row.caseLbl:GetStringWidth() + row.wordLbl:GetStringWidth() + 2 * 12
    local tail = 20 + 4 + 20 + 4 + 20 + 6 + STATUS_W + 6 + 22 + 4 + 22 + 6
    local compact = w - PAD * 2 - tail - labels < MIN_BOX
    row.wordCb:ClearAllPoints(); row.caseCb:ClearAllPoints()
    if compact then
        row.caseLbl:Hide(); row.wordLbl:Hide()
        row.wordCb:SetPoint("RIGHT", row.status, "LEFT", -6, 0)
        row.caseCb:SetPoint("RIGHT", row.wordCb, "LEFT", -4, 0)
    else
        row.caseLbl:Show(); row.wordLbl:Show()
        row.wordCb:SetPoint("RIGHT", row.status, "LEFT", -(row.wordLbl:GetStringWidth() + 12), 0)
        row.caseCb:SetPoint("RIGHT", row.wordCb, "LEFT", -(row.caseLbl:GetStringWidth() + 12), 0)
    end
end

local function Build(kind, parent)
    if _rows[kind] then return _rows[kind] end
    local row = { kind = kind }
    local f = CreateFrame("Frame", nil, parent)
    f:SetHeight(ROW_H)
    f:Hide()
    row.frame = f

    -- The rule under it, as the toolbars have
    local rule = BNB.CreateNoteRule(f)
    rule:SetPoint("BOTTOMLEFT",  f, "BOTTOMLEFT",  0, 0)
    rule:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)

    local y1, y2 = -PAD, -(PAD + EB_H + LINE_GAP)

    -- Line 1, right to left: X, down (Next), up (Previous), status
    local closeBtn = BNB.CreateIconButton(f, 20, "close", { tip = L["FIND_CLOSE_TIP"],
        onClick = function() FR.Close(true) end })
    closeBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -PAD, y1 - 1)
    row.nextBtn = BNB.CreateIconButton(f, 20, "down", { tip = L["FIND_NEXT"], tipSub = L["FIND_NEXT_TIP"],
        onClick = function() Step(1) end })
    row.nextBtn:SetPoint("RIGHT", closeBtn, "LEFT", -8, 0)
    row.prevBtn = BNB.CreateIconButton(f, 20, "up", { tip = L["FIND_PREV"], tipSub = L["FIND_PREV_TIP"],
        onClick = function() Step(-1) end })
    row.prevBtn:SetPoint("RIGHT", row.nextBtn, "LEFT", -4, 0)

    row.status = f:CreateFontString(nil, "OVERLAY", "BNBFontNormalSmall")
    row.status:SetPoint("RIGHT", row.prevBtn, "LEFT", -6, 0)
    row.status:SetWidth(STATUS_W)
    row.status:SetJustifyH("RIGHT"); row.status:SetWordWrap(false)

    row.caseCb, row.caseLbl = Check(row, L["FIND_MATCH_CASE"], L["FIND_MATCH_CASE_TIP"], function(on)
        _matchCase = on; _msg = nil; Search(_hits[_cur] and _hits[_cur][1] or 1)
    end)
    row.wordCb, row.wordLbl = Check(row, L["FIND_WHOLE_WORD"], L["FIND_WHOLE_WORD_TIP"], function(on)
        _wholeWord = on; _msg = nil; Search(_hits[_cur] and _hits[_cur][1] or 1)
    end)

    local findBg, replBg
    findBg, row.findEb, row.findHint = Box(row, L["FIND_LABEL"])
    findBg:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, y1)
    findBg:SetPoint("RIGHT", row.caseCb, "LEFT", -6, 0)

    -- Line 2: Replace box | Replace | Replace all
    row.allBtn = BNB.CreateButton(nil, f, L["FIND_REPLACE_ALL"], 90, EB_H)
    row.allBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -PAD, y2)
    row.allBtn:SetScript("OnClick", ReplaceAll)
    row.replBtn = BNB.CreateButton(nil, f, L["FIND_REPLACE"], 76, EB_H)
    row.replBtn:SetPoint("RIGHT", row.allBtn, "LEFT", -4, 0)
    row.replBtn:SetScript("OnClick", ReplaceOne)
    replBg, row.replEb, row.replHint = Box(row, L["FIND_REPLACE_PH"])
    replBg:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, y2)
    replBg:SetPoint("RIGHT", row.replBtn, "LEFT", -6, 0)

    -- Typing in Find: the hits now, the first one after the text cursor shown
    row.findEb:HookScript("OnTextChanged", function(self, userInput)
        if not userInput then return end
        _msg = nil
        _lastFind = self:GetText() or ""
        BNB.Debounce("bnbFindTyped", 0.15, function()
            if not (R == row and _eb) then return end
            local h = _hits[_cur]
            -- Keep going from the hit shown, else from the text cursor
            Search(h and h[1] or ((_eb:GetCursorPosition() or 0) + 1))
            ShowCur()
        end)
    end)
    -- Enter = Next, Shift+Enter = Previous; Enter in Replace with = Replace
    row.findEb:SetScript("OnEnterPressed", function() Step(IsShiftKeyDown() and -1 or 1) end)
    row.replEb:SetScript("OnEnterPressed", ReplaceOne)
    BNB.TabChain({ row.findEb, row.replEb })

    f:SetScript("OnSizeChanged", function()
        BNB.Debounce("bnbFindFit" .. kind, 0, function() Fit(row) end)
    end)
    f:SetScript("OnHide", function()
        row.findEb:ClearFocus(); row.replEb:ClearFocus()
        if R ~= row then return end
        -- Hidden with its window (not by Close): hidden for real too, or it
        -- comes back with the window as a dead row over the next note
        -- (ALL-602), and the body moves back up
        C_Timer.After(0, function()
            if R == row then return end
            if f:IsShown() then f:Hide() end
            Relayout(kind)
        end)
        local eb = _eb
        R, _eb, _noteID, _hits, _hitText, _cur, _msg = nil, nil, nil, {}, nil, 0, nil
        local ctl = eb and _ctls[eb]
        if ctl then ctl.Recolor() end
    end)
    _rows[kind] = row
    return row
end

function FR.RowOf(kind)
    local row = _rows[kind]
    return row and row.frame or nil
end

function FR.Open(kind, eb, parent)
    if not (kind and eb and parent) then return end
    local row = Build(kind, parent)
    Wire(eb)
    if R == row and _eb == eb then
        row.findEb:SetFocus(); row.findEb:HighlightText()
        return
    end
    if R then FR.Close() end
    R, _eb, _noteID = row, eb, BNB._currentNoteID
    row.caseCb:SetChecked(_matchCase); row.wordCb:SetChecked(_wholeWord)
    row.findEb:SetText(_lastFind); row.findHint()
    row.frame:Show()
    Relayout(kind)
    Fit(row)
    row.findEb:SetFocus(); row.findEb:HighlightText()
    InEdit(function()
        if _eb ~= eb then return end
        Search((eb:GetCursorPosition() or 0) + 1)
        ShowCur()
    end)
end

function FR.Toggle(kind, eb, parent)
    if R and R.kind == kind then FR.Close(true); return end
    FR.Open(kind, eb, parent)
end

function FR.IsOpen() return R ~= nil end

-- Another note (or none) in the editor: the row closes, the next note starts
-- without it (ALL-602; BNB.Editor.SetCurrent, Core/NoteManager.lua)
function FR.NoteChanged(id)
    if R and id ~= _noteID then FR.Close() end
end

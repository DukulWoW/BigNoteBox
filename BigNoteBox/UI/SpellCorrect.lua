--------------------------------------------------------------------------------
-- SpellCorrect.lua -- the Correct spelling window (ALL-559, Dukul 2026-10-25)
--
-- Goes through the marked words of the note in the main editor one by one:
-- the wrong word and the sentence it is in on the left, "Consider" and the
-- suggestions on the right, Change / Ignore this / Ignore all / Add to
-- dictionary under them. It starts at the marked word at the text cursor
-- (or the one right-clicked), runs to the end of the note, then from the top
-- back to where it started. A repeated word ("the the") shows Delete instead
-- of Change. While it is open the main window is dimmed and takes no clicks,
-- as for the New note dialog (Dukul's choice).
--
-- Opened by the toolbar's Correct spelling button (UI/WysiwygBar.lua) and
-- the body's right-click menu (Features/Spellcheck.lua, SP.AddMenuActions).
-- Ignore this skips the word for this pass only: it stays marked in the note.
--
-- Focus mode (ALL-559 S3): the same pass on Focus mode's body, Focus mode
-- dimmed instead, the window seated over it (BNB.SeatWindow). Stickies have
-- no Correct spelling window.
--
-- Public API:
--   BNB.SpellCorrect.Open(startAt, eb)   startAt = a byte position, eb = the
--                                        body (both optional)
--   BNB.SpellCorrect.Close()
--   BNB.SpellCorrect.IsOpen()
--   BNB.SpellCorrect.AskAdd(word)        Add to dictionary's question in Focus mode
--------------------------------------------------------------------------------
local BNB = BigNoteBox
local L   = BNB.L

local SC = {}
BNB.SpellCorrect = SC

local W, H, PAD    = 500, 262, 14
local LEFT_W       = 220
local GAP          = 16
local ROW_H        = 20
local ROWS         = 6                    -- Spellcheck's MAX_SUGGEST
local FOOT_H       = 40
local CTX_BYTES    = 90                   -- the most of the sentence shown each side
local RED          = "|cffff5050"

local _f, _ov
local _wordLbl, _kindLbl, _ctxLbl, _changeEb, _changeLbl, _none
local _rows = {}
local _changeBtn, _addBtn
local _eb, _noteID, _hit
local _stopAt, _wrapped                   -- where the pass started; past the end once
local _sel                                -- the picked suggestion row
local _host                               -- the window dimmed: main window or Focus mode
local _ovs = {}                           -- host -> its dimming overlay
local _af, _afEb                          -- Focus mode's Add to dictionary window (SC.AskAdd)

local function Spell() return BNB.Spell end
-- One of two strings (never `c and L[a] or L[b]`: the banned-pattern check)
local function Either(c, a, b) if c then return a end return b end

-- The highest frame level inside a window, skipping this file's own frames
-- (skip): Focus mode's border and other pieces sit well above the window's
-- own level, so +50 was not enough (its border drew through, 2026-10-25)
local function TopLevel(frame, skip)
    local top = frame:GetFrameLevel() or 0
    for _, c in ipairs({ frame:GetChildren() }) do
        if not skip[c] then
            local l = TopLevel(c, skip)
            if l > top then top = l end
        end
    end
    return top
end
local function AboveAll(host)
    local skip = {}
    if _f then skip[_f] = true end
    if _af then skip[_af] = true end
    for _, ov in pairs(_ovs) do skip[ov] = true end
    return math.min(TopLevel(host, skip) + 1, 9000)
end

-- ── The note's window (main window or Focus mode), dimmed and closed to clicks
local function ShowOverlay(show)
    if not show then
        if _ov then _ov:Hide() end
        return
    end
    local host = _host
    if not host then return end
    if _ov and _ov ~= _ovs[host] then _ov:Hide() end
    _ov = _ovs[host]
    if not _ov then
        local ov = CreateFrame("Frame", nil, host)
        ov:SetAllPoints()
        ov:SetFrameStrata("FULLSCREEN_DIALOG")
        ov:EnableMouse(true)
        local bg = ov:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0, 0, 0, 0.55)
        ov:Hide()
        _ovs[host], _ov = ov, ov
    end
    _ov:SetFrameLevel(AboveAll(host))
    _ov:Show()
end

function SC.IsOpen() return _f ~= nil and _f:IsShown() end

function SC.Close()
    if _f then _f:Hide() end
    ShowOverlay(false)
end

-- ── The sentence around the word, the word in red ────────────────────────────
local function Escape(s) return (s:gsub("|", "||"):gsub("[\r\n\t]+", " ")) end

local function Context(text, first, last)
    local a = first
    while a > 1 and first - a < CTX_BYTES do
        local c = text:sub(a - 1, a - 1)
        if c == "\n" or ((c == "." or c == "!" or c == "?") and a < first - 1) then break end
        a = a - 1
    end
    local b = last
    while b < #text and b - last < CTX_BYTES do
        local c = text:sub(b + 1, b + 1)
        if c == "\n" then break end
        b = b + 1
        if c == "." or c == "!" or c == "?" then break end
    end
    -- Never start or end inside a UTF-8 letter
    while a < first and (text:byte(a) or 0) >= 128 and (text:byte(a) or 0) < 192 do a = a + 1 end
    while b > last and (text:byte(b + 1) or 0) >= 128 and (text:byte(b + 1) or 0) < 192 do b = b - 1 end
    local before = text:sub(a, first - 1):gsub("^%s+", "")
    local after  = text:sub(last + 1, b):gsub("%s+$", "")
    return (a > 1 and "..." or "") .. Escape(before) .. RED .. Escape(text:sub(first, last)) .. "|r"
        .. Escape(after) .. (b < #text and "..." or "")
end

-- ── Suggestion rows ──────────────────────────────────────────────────────────
local function Pick(row)
    _sel = row
    for _, r in ipairs(_rows) do r._selArt:SetShown(r == row) end
    if row then
        _changeEb:SetText(row._word)
        _changeEb:SetCursorPosition(#row._word)
    end
end

local function ChangeText()
    return ((_changeEb:GetText() or ""):match("^%s*(.-)%s*$"))
end

local function SyncButtons()
    local rep = _hit and _hit.rep
    if rep then
        _changeBtn:SetEnabled(true)
    else
        local t = ChangeText()
        _changeBtn:SetEnabled(t ~= "" and _hit ~= nil and t ~= _hit.word)
    end
    _addBtn:SetEnabled(_hit ~= nil and not rep)
end

-- ── Going through the note ───────────────────────────────────────────────────
local Next   -- below

-- Still the note this pass is for, shown and not locked
local function StillHere()
    return _eb and _eb:IsVisible() and _eb:IsEnabled() and BNB._currentNoteID == _noteID
end

local function Finish(found)
    SC.Close()
    BNB:Print(Either(found, L["SPELL_CORRECT_DONE"], L["SPELL_NONE_FOUND"]))
end

local function ShowHit(r)
    local SP = Spell()
    _hit = SP._Hit(_eb, r)
    local text = _eb:GetText() or ""
    local word = _hit.word:gsub("\226\128\153", "'")
    _kindLbl:SetText(Either(_hit.rep, L["SPELL_CORRECT_REPEATED"], L["SPELL_CORRECT_NOT_FOUND"]))
    _wordLbl:SetText(Escape(word))
    _ctxLbl:SetText(Context(text, _hit.first, _hit.last))
    -- The note scrolls to the word (a frame later: after a change the editor
    -- puts its cursor after the new word first)
    local eb, last = _eb, _hit.last
    C_Timer.After(0, function() if eb:IsVisible() then eb:SetCursorPosition(last) end end)

    local list = _hit.rep and {} or SP.Suggest(word)
    for i, row in ipairs(_rows) do
        local s = list[i]
        row._word = s
        if s then row._lbl:SetText(Escape(s)); row:Show() else row:Hide() end
    end
    _none:SetText(Either(_hit.rep, L["SPELL_CORRECT_REPEAT_HINT"], L["SPELL_MENU_NONE"]))
    _none:SetShown(#list == 0)
    _changeBtn:SetText(Either(_hit.rep, L["SPELL_CORRECT_DELETE"], L["SPELL_CORRECT_CHANGE"]))
    _changeLbl:SetShown(not _hit.rep)
    _changeEb:SetShown(not _hit.rep)
    _sel = nil
    if list[1] then Pick(_rows[1]) else
        for _, row in ipairs(_rows) do row._selArt:Hide() end
        _changeEb:SetText(word)
    end
    if not _hit.rep then
        _changeEb:SetFocus()
        _changeEb:HighlightText()
    else
        _changeEb:ClearFocus()
    end
    SyncButtons()
end

-- The next marked word at or after pos; past the end, from the top up to
-- where the pass started
Next = function(pos)
    if not StillHere() then SC.Close(); return end
    local list = Spell().Mistakes(_eb:GetText() or "")
    local function From(p, stop)
        for _, r in ipairs(list) do
            if r[1] >= p and (not stop or r[1] < stop) then return r end
        end
    end
    local r
    if not _wrapped then
        r = From(pos)
        if not r then _wrapped = true; r = From(1, _stopAt) end
    else
        r = From(pos, _stopAt)
    end
    if r then ShowHit(r) else Finish(true) end
end

-- A change moved the text after it: the stop point too, once wrapped (the
-- change is then before it)
local function Moved(first, delta)
    if _wrapped and _stopAt and first < _stopAt then _stopAt = _stopAt + delta end
end

local function DoChange()
    if not (_hit and StillHere()) then return end
    local SP = Spell()
    local h = _hit
    if h.rep then
        if not SP.Replace(_eb, h, "", true) then Next(h.last + 1); return end
        Moved(h.rep, -(h.last - h.rep + 1))
        Next(h.rep)
    else
        local new = ChangeText()
        if new == "" or new == h.word then return end
        if not SP.Replace(_eb, h, new, true) then Next(h.last + 1); return end
        Moved(h.first, #new - (h.last - h.first + 1))
        Next(h.first + #new)
    end
end

local function DoIgnoreThis()
    if not _hit then return end
    Next(_hit.last + 1)
end

local function DoIgnoreAll()
    if not _hit then return end
    local SP = Spell()
    local word = _hit.word:gsub("\226\128\153", "'")
    if _hit.rep then SP.IgnoreRepeat(word) else SP.Ignore(word) end
    Next(_hit.first)
end

local function DoAdd()
    if not (_hit and not _hit.rep) then return end
    local word = _hit.word:gsub("\226\128\153", "'")
    Spell().AddWord(word)
    Next(_hit.first)
end

-- ── The window ───────────────────────────────────────────────────────────────
-- Where a window of this file sits. Over Focus mode it is a CHILD of the
-- Focus window: that window is top level in the same strata, so the game
-- lifts it to the front on every click on it (the dimming overlay is its
-- child) and a window beside it went behind (Dukul, 2026-10-25). As a
-- child it moves up with it. Elsewhere BNB.SeatWindow, as before
local function Seat(f, focusHost)
    if focusHost then
        if f:GetParent() ~= focusHost then f:SetParent(focusHost) end
        f:SetScale(1)
        f:SetFrameStrata("FULLSCREEN_DIALOG")
    else
        BNB.SeatWindow(f, "FULLSCREEN_DIALOG")
    end
end

local function OverFocus() return _host ~= nil and _host ~= BNB.mainFrame end

local function SavePos()
    if not (_f and BigNoteBoxDB) or OverFocus() then return end
    BigNoteBoxDB.spellCorrectPos = { x = math.floor(_f:GetLeft() + 0.5), y = math.floor(_f:GetTop() + 0.5) }
end

local function Place()
    _f:ClearAllPoints()
    local pos = BigNoteBoxDB and BigNoteBoxDB.spellCorrectPos
    -- Over Focus mode: centered on it (the saved place is the main window's)
    if OverFocus() then pos = nil end
    if type(pos) == "table" and pos.x and pos.y then
        _f:SetPoint("TOPLEFT", _f:GetParent(), "BOTTOMLEFT", pos.x, pos.y)
    elseif _host and _host:IsShown() then
        _f:SetPoint("CENTER", _host, "CENTER", 0, 20)
    else
        _f:SetPoint("CENTER", _f:GetParent(), "CENTER", 0, 20)
    end
end

local function Build()
    if _f then return end
    local cw = W - 2 * PAD
    local f = BNB.CreateToolWindow({
        name = "BNBSpellCorrectFrame", w = W, h = H,
        title = L["SPELL_CORRECT_TITLE"], strata = "FULLSCREEN_DIALOG",
        pad = PAD, cw = cw, footH = FOOT_H, keyEsc = true,
        onClose = function() SC.Close() end,
        onDragStop = SavePos,
    })
    f:HookScript("OnHide", function()
        ShowOverlay(false)
        _hit, _eb = nil, nil
    end)
    _f = f
    local top = f._isSkin and -(BNB.TOOL_SKIN_TITLE_H + 10) or -34

    -- Left: the word, its sentence, Change to
    _kindLbl = f:CreateFontString(nil, "OVERLAY", "BNBFontNormalSmall")
    _kindLbl:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, top)
    _kindLbl:SetWidth(LEFT_W); _kindLbl:SetJustifyH("LEFT")
    _kindLbl:SetTextColor(0.7, 0.7, 0.7)

    _wordLbl = f:CreateFontString(nil, "OVERLAY", "BNBFontNormalLarge")
    _wordLbl:SetPoint("TOPLEFT", _kindLbl, "BOTTOMLEFT", 0, -4)
    _wordLbl:SetWidth(LEFT_W); _wordLbl:SetJustifyH("LEFT"); _wordLbl:SetWordWrap(false)
    _wordLbl:SetTextColor(1, 0.31, 0.31)

    _ctxLbl = f:CreateFontString(nil, "OVERLAY", "BNBFontHighlightSmall")
    _ctxLbl:SetPoint("TOPLEFT", _wordLbl, "BOTTOMLEFT", 0, -8)
    _ctxLbl:SetSize(LEFT_W, 70)
    _ctxLbl:SetJustifyH("LEFT"); _ctxLbl:SetJustifyV("TOP"); _ctxLbl:SetWordWrap(true)
    _ctxLbl:SetTextColor(0.85, 0.85, 0.85)

    _changeLbl = f:CreateFontString(nil, "OVERLAY", "BNBFontNormalSmall")
    _changeLbl:SetPoint("TOPLEFT", _ctxLbl, "BOTTOMLEFT", 0, -6)
    _changeLbl:SetWidth(LEFT_W); _changeLbl:SetJustifyH("LEFT")
    _changeLbl:SetTextColor(0.7, 0.7, 0.7)
    _changeLbl:SetText(L["SPELL_CORRECT_CHANGE_TO"])

    _changeEb = CreateFrame("EditBox", nil, f, "BackdropTemplate")
    BNB.EnsureBackdrop(_changeEb)
    BNB.SetBackdropDark(_changeEb)
    _changeEb:SetPoint("TOPLEFT", _changeLbl, "BOTTOMLEFT", 0, -4)
    _changeEb:SetSize(LEFT_W, 22)
    _changeEb:SetFontObject("BNBFontNormal")
    _changeEb:SetAutoFocus(false)
    _changeEb:SetMaxLetters(60)
    _changeEb:SetTextInsets(5, 5, 0, 0)
    _changeEb:SetScript("OnEscapePressed", function() SC.Close() end)
    _changeEb:SetScript("OnEnterPressed", DoChange)
    _changeEb:SetScript("OnTextChanged", function(_, user)
        if user and _sel then
            _sel = nil
            for _, r in ipairs(_rows) do r._selArt:Hide() end
        end
        if _changeBtn then SyncButtons() end
    end)

    -- Right: Consider and the suggestions
    local rx = PAD + LEFT_W + GAP
    local rw = W - rx - PAD
    local head = f:CreateFontString(nil, "OVERLAY", "BNBFontNormal")
    head:SetPoint("TOPLEFT", f, "TOPLEFT", rx, top)
    head:SetJustifyH("LEFT")
    BNB.SetHeaderColor(head)
    head:SetText(L["SPELL_CORRECT_CONSIDER"])

    local box = BNB.CreateBackdropFrame("Frame", nil, f)
    BNB.SetBackdropDark(box)
    box:SetPoint("TOPLEFT", head, "BOTTOMLEFT", 0, -6)
    box:SetSize(rw, ROWS * ROW_H + 8)
    for i = 1, ROWS do
        local row = CreateFrame("Button", nil, box)
        row:SetPoint("TOPLEFT", box, "TOPLEFT", 4, -4 - (i - 1) * ROW_H)
        row:SetSize(rw - 8, ROW_H)
        row._hover  = BNB.CreateListRowArt(row, "hover", { 1, 1, 1, 0.08 })
        row._selArt = BNB.CreateListRowArt(row, "selection", { 0.4, 0.7, 0.4, 0.22 })
        local lbl = row:CreateFontString(nil, "OVERLAY", "BNBFontNormal")
        lbl:SetPoint("LEFT", row, "LEFT", 6, 0)
        lbl:SetPoint("RIGHT", row, "RIGHT", -6, 0)
        lbl:SetJustifyH("LEFT"); lbl:SetWordWrap(false)
        BNB.SetTextWhite(lbl, 0.9)
        row._lbl = lbl
        row:SetScript("OnEnter", function(self) self._hover:Show() end)
        row:SetScript("OnLeave", function(self) self._hover:Hide() end)
        row:SetScript("OnClick", function(self) Pick(self) end)
        row:SetScript("OnDoubleClick", function(self) Pick(self); DoChange() end)
        row:Hide()
        _rows[i] = row
    end
    _none = box:CreateFontString(nil, "OVERLAY", "BNBFontNormalSmall")
    _none:SetPoint("TOPLEFT", box, "TOPLEFT", 10, -10)
    _none:SetPoint("RIGHT", box, "RIGHT", -10, 0)
    _none:SetJustifyH("LEFT"); _none:SetWordWrap(true)
    _none:SetTextColor(0.6, 0.6, 0.6)

    -- The four buttons
    local bw = math.floor((cw - 3 * 6) / 4)
    local function Btn(i, text, fn, tip)
        local b = BNB.CreateButton(nil, f, text, bw, 26)
        b:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", PAD + (i - 1) * (bw + 6), 8)
        b:SetScript("OnClick", fn)
        if tip then
            b:HookScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_TOP")
                GameTooltip:AddLine(text, 1, 1, 1)
                GameTooltip:AddLine(tip, 0.8, 0.8, 0.8, true)
                GameTooltip:Show()
            end)
            b:HookScript("OnLeave", function() GameTooltip:Hide() end)
        end
        return b
    end
    _changeBtn    = Btn(1, L["SPELL_CORRECT_CHANGE"], DoChange)
    Btn(2, L["SPELL_CORRECT_IGNORE_THIS"], DoIgnoreThis, L["SPELL_CORRECT_IGNORE_THIS_TIP"])
    Btn(3, L["SPELL_CORRECT_IGNORE_ALL"], DoIgnoreAll, L["SPELL_MENU_IGNORE_TIP"])
    _addBtn       = Btn(4, L["SPELL_CORRECT_ADD"], DoAdd, L["SPELL_MENU_ADD_TIP"])
end

-- The note's window going away ends the pass (hooked once per window, in Open)
local _hooked = {}
local function HookHost(host)
    if _hooked[host] then return end
    _hooked[host] = true
    host:HookScript("OnHide", function() if SC.IsOpen() and _host == host then SC.Close() end end)
end

-- startAt: the byte to start from (a right-clicked word); nil = the marked
-- word at the text cursor, else the cursor. eb: the body (main editor or
-- Focus mode, ALL-559 S3); nil = Focus mode while it is open, else the main
-- editor. Never a sticky (no window for those)
function SC.Open(startAt, eb)
    local SP = Spell()
    local id = BNB._currentNoteID
    if not (SP and BNB.SpellEnabled() and id) then return end
    if tostring(id):find("^sys%-") then return end
    local ed = SP.ActiveEditor()
    if eb and SP.EditorKind(eb) ~= (ed and ed.kind) then return end   -- not the box in front
    if not ed or ed.kind == "sticky" then return end
    local focus = ed.kind == "focus"
    local host
    if focus then host = BNB.GetFocusFrame and BNB.GetFocusFrame() else host = BNB.mainFrame end
    if not (host and host:IsVisible()) then return end
    if not SP.EnsureLoaded() then SP.Announce(); return end
    -- Rich View mode has no box: Edit mode first, then here again
    if not focus and BNB._editorInViewMode and BNB.AM_EnterEditMode then
        BNB.AM_EnterEditMode()
        C_Timer.After(0, function() if not BNB._editorInViewMode then SC.Open(startAt) end end)
        return
    end
    eb = ed.eb
    if not (eb and eb:IsVisible()) then return end
    if not eb:IsEnabled() then BNB:Print(L["SPELL_CORRECT_LOCKED"]); return end
    if #SP.Mistakes(eb:GetText() or "") == 0 then BNB:Print(L["SPELL_NONE_FOUND"]); return end

    if not startAt then
        local h = SP.HitAtCursor(eb)
        startAt = h and h.first or ((eb:GetCursorPosition() or 0) + 1)
    end
    eb:ClearFocus()
    Build()
    if _f:IsShown() then _f:Hide() end   -- a pass in the other window ends first
    _eb, _noteID, _host = eb, id, host
    HookHost(host)
    _stopAt, _wrapped = startAt, false
    -- Over Focus mode, and on WorldFrame while its UI is hidden (ALL-506)
    Seat(_f, focus and host)
    Place()
    ShowOverlay(true)
    _f:Show()
    _f:SetFrameLevel(_ov:GetFrameLevel() + 10)
    _f:Raise()
    Next(startAt)
end

-- ── Add to dictionary in Focus mode (ALL-559 S3) ─────────────────────────────
-- The toolbar's Add to dictionary asks first (SP.AskAddWord). Outside Focus
-- mode that is a game popup (BNB_SPELL_ADD_WORD, Features/Spellcheck.lua),
-- which would sit under the Focus window or be hidden with the UI: the same
-- question, word editable, in a window of our own here.
local AW, AH = 340, 132

local function AskAccept()
    if not _af then return end
    local w = _afEb:GetText()
    _af:Hide()
    local SP = Spell()
    if SP and SP.TryAdd then SP.TryAdd(w) end
end

local function BuildAsk()
    if _af then return end
    local cw = AW - 2 * PAD
    local f, ok, cancel = BNB.CreateToolWindow({
        name = "BNBSpellAddFrame", w = AW, h = AH,
        title = L["SPELL_MENU_ADD"], strata = "FULLSCREEN_DIALOG",
        pad = PAD, cw = cw, footH = FOOT_H, keyEsc = true,
        btn1 = L["SPELL_ADD_POPUP_BTN"], btn2 = CANCEL,
        onClose = function() _af:Hide() end,
    })
    _af = f
    local top = f._isSkin and -(BNB.TOOL_SKIN_TITLE_H + 12) or -36
    local msg = f:CreateFontString(nil, "OVERLAY", "BNBFontHighlightSmall")
    msg:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, top)
    msg:SetWidth(cw); msg:SetJustifyH("LEFT")
    msg:SetText(L["SPELL_ADD_POPUP"])

    _afEb = CreateFrame("EditBox", nil, f, "BackdropTemplate")
    BNB.EnsureBackdrop(_afEb)
    BNB.SetBackdropDark(_afEb)
    _afEb:SetPoint("TOPLEFT", msg, "BOTTOMLEFT", 0, -8)
    _afEb:SetSize(cw, 22)
    _afEb:SetFontObject("BNBFontNormal")
    _afEb:SetAutoFocus(false)
    _afEb:SetMaxLetters(Spell().MAX_WORD or 60)
    _afEb:SetTextInsets(5, 5, 0, 0)
    _afEb:SetScript("OnEscapePressed", function() _af:Hide() end)
    _afEb:SetScript("OnEnterPressed", AskAccept)

    ok:SetScript("OnClick", AskAccept)
    cancel:SetScript("OnClick", function() _af:Hide() end)
end

-- word: filled in, editable
function SC.AskAdd(word)
    BuildAsk()
    local host = BNB.GetFocusFrame and BNB.GetFocusFrame()
    Seat(_af, host and host:IsShown() and host)
    _af:ClearAllPoints()
    if host and host:IsShown() then _af:SetPoint("CENTER", host, "CENTER", 0, 40)
    else _af:SetPoint("CENTER", _af:GetParent(), "CENTER", 0, 40) end
    _af:Show()
    if host then _af:SetFrameLevel(AboveAll(host) + 10) end
    _af:Raise()
    _afEb:SetText(word or "")
    _afEb:SetFocus()
    _afEb:HighlightText()
end

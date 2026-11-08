-- BigNoteBox UI/Dialog.lua
-- Our own small dialog (ALL-572; its first use is Rename, ALL-571), in place
-- of the game's StaticPopup where that one does not fit the addon. Built on
-- BNB.CreateToolWindow, so it has the look of every other BigNoteBox window:
-- the skin frame in skin mode, the game's window frame in normal mode (Dukul,
-- 2026-10-26: "Skin mode gets a skinned dialog, normal mode get's a dialog
-- that works with wow (not just a black box)"). One frame per look, built the
-- first time it is needed in that look; Prompt and Confirm share it (the edit
-- box is hidden for a Confirm).
--
-- The game's popup stays for: Danger Zone, anything that ends in a reload
-- (C_UI.Reload is proven from a StaticPopup's OnAccept, ALL-252), the
-- migration flow and the login notices.
--
-- Public API:
--   BNB.Dialog.Prompt(o)   ask for a line of text
--     o.title        window title
--     o.text         the question above the box (word wrapped), optional
--     o.value        the box's first text (highlighted)
--     o.maxLetters   default 200
--     o.okLabel      default L["OK"]
--     o.allowEmpty   OK works on an empty box (else OK is greyed)
--     o.onAccept(text)  the typed text, spaces trimmed from both ends
--     o.host         optional window the dialog belongs to (Dukul, 2026-10-26:
--                    "attach the rename dialog to the window like we do the
--                    new note window"): centred on it, the window dimmed and
--                    closed to clicks while the dialog is open, the dialog
--                    closed when the window hides. Not shown = screen centre
--                    and nothing dimmed. Not every dialog wants this
--     o.strata       optional, default DIALOG (FULLSCREEN_DIALOG with a host):
--                    FULLSCREEN_DIALOG over the New Note dialog's dimmer
--     o.cancelLabel  default L["CANCEL"] (Confirm too)
--   BNB.Dialog.Confirm(o)  ask yes / no (S1 of ALL-572, 2026-11-08)
--     o.title        window title, default "BigNoteBox"
--     o.text         the question, ready-made (word wrapped)
--     o.okLabel      default L["OK"]; o.cancelLabel default L["CANCEL"]
--     o.alert        the game's alert icon beside the text (StaticPopup's
--                    showAlert)
--     o.host, o.strata  as Prompt's
--     o.onAccept()   OK; o.onCancel() Cancel, Esc, or the host closing
--     o.key          optional: a dialog with the same key already open or
--                    waiting is not asked again (default: text .. okLabel),
--                    as the game's popup did for a repeated name
--   BNB.Dialog.IsMouseOver()  the pointer is on the open dialog
--
-- One dialog at a time: a second one waits in a queue and opens when the
-- first closes (Dukul, 2026-11-08: "Queue it").
--
-- Keys: Prompt = the box's own Enter / Esc (in combat too). Confirm = Enter /
-- Esc through the frame's key handler, which takes no keys in combat (BUG-05),
-- so a Confirm in combat is the game's popup instead (Dukul, 2026-11-08: "WoW
-- popup in combat"): asked for in combat, or still open when combat starts.
--------------------------------------------------------------------------------

local BNB = BigNoteBox
if not BNB then return end
local L = BNB.L

local D = {}
BNB.Dialog = D

local W, PAD, EB_H, FOOT_H, ICON = 340, 14, 24, 38, 36
local ALERT_TEX = "Interface\\DialogFrame\\UI-Dialog-Icon-AlertNew"
local FALLBACK = "BNB_DIALOG_COMBAT"

local _built = {}   -- [true] = the skin build, [false] = the normal build
local _f, _o        -- the frame in use, the open dialog's options
local _kind         -- "prompt" / "confirm" while one is open
local _queue = {}   -- { kind, o } waiting
local _fbOpen       -- the options shown in the combat fallback popup
local _done         -- the open dialog was answered (OK), so no onCancel
local _moving       -- hiding ours only to show it as the fallback

local _ovs, _ov = {}, nil   -- host -> its dimming overlay; the one shown
local _hooked = {}          -- hosts whose OnHide closes the dialog

local Show   -- forward: opens the next dialog

local function Trim(s) return (s or ""):match("^%s*(.-)%s*$") end
local function KeyOf(o) return o.key or ((o.text or "") .. "\1" .. (o.okLabel or "")) end

-- The highest frame level inside a window, our overlays left out: pieces of
-- a window can sit well above its own level (as UI/SpellCorrect.lua)
local function TopLevel(frame)
    local top = frame:GetFrameLevel() or 0
    for _, c in ipairs({ frame:GetChildren() }) do
        local skip = false
        for _, ov in pairs(_ovs) do if ov == c then skip = true end end
        if not skip then
            local l = TopLevel(c)
            if l > top then top = l end
        end
    end
    return top
end

-- The host dimmed and closed to clicks (nil = none), as the New Note dialog
local function Dim(host)
    if _ov then _ov:Hide(); _ov = nil end
    if not host then return end
    local ov = _ovs[host]
    if not ov then
        ov = CreateFrame("Frame", nil, host)
        ov:SetAllPoints()
        ov:SetFrameStrata("FULLSCREEN_DIALOG")
        ov:EnableMouse(true)
        local bg = ov:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0, 0, 0, 0.55)
        _ovs[host] = ov
    end
    ov:SetFrameLevel(math.min(TopLevel(host) + 1, 9000))
    ov:Show()
    _ov = ov
end

local function Busy() return (_f and _f:IsShown()) or _fbOpen ~= nil end

-- The next waiting dialog, on the next frame (after the closing one's work)
local function Next()
    C_Timer.After(0, function()
        if Busy() or #_queue == 0 then return end
        local q = table.remove(_queue, 1)
        Show(q[1], q[2])
    end)
end

local function Refresh()
    local f, o = _f, _o
    if f and o and _kind == "prompt" then
        f._ok:SetEnabled(o.allowEmpty or Trim(f._eb:GetText()) ~= "")
    end
end

local function Accept()
    local f, o = _f, _o
    if not (f and o and f:IsShown()) then return end
    if _kind == "prompt" then
        local text = Trim(f._eb:GetText())
        if text == "" and not o.allowEmpty then return end
        _done = true
        f:Hide()   -- clears _o
        if o.onAccept then xpcall(o.onAccept, geterrorhandler(), text) end
    else
        _done = true
        f:Hide()
        if o.onAccept then xpcall(o.onAccept, geterrorhandler()) end
    end
end

local function OnHide()
    local o, answered, moving = _o, _done, _moving
    _o, _kind, _done = nil, nil, nil
    Dim(nil)
    if moving then return end
    if o and not answered and o.onCancel then xpcall(o.onCancel, geterrorhandler()) end
    Next()
end

-- Enter = OK on a Confirm (a Prompt's box has its own); Esc = Cancel through
-- BNB.AttachEscClose. In combat the keys go to the game (BUG-05); the Confirm
-- is the game's popup there anyway.
local function OnKey(_, key)
    if (key == "ENTER" or key == "NUMPADENTER") and _kind == "confirm" then
        Accept(); return true
    end
end

local function Build(skin)
    local f, ok, cancel = BNB.CreateToolWindow({
        w = W, h = 120, title = "", pad = PAD, cw = W - 2 * PAD, footH = FOOT_H,
        btn1 = L["OK"], btn2 = L["CANCEL"],
        strata = "DIALOG", toplevel = true,
        onHide = OnHide,
    })
    local top = (f._isSkin and BNB.TOOL_SKIN_TITLE_H or 28) + 12
    BNB.AttachEscClose(f, function(self) self:Hide() end, nil, OnKey)

    local icon = f:CreateTexture(nil, "ARTWORK")
    icon:SetSize(ICON, ICON)
    icon:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, -top)
    icon:SetTexture(ALERT_TEX)

    local msg = f:CreateFontString(nil, "OVERLAY", "BNBFontHighlight")
    msg:SetJustifyH("LEFT")
    msg:SetWordWrap(true)

    local eb = CreateFrame("EditBox", nil, f, "BackdropTemplate")
    BNB.EnsureBackdrop(eb)
    BNB.SetBackdropDark(eb)
    eb:SetSize(W - 2 * PAD, EB_H)
    eb:SetFontObject("BNBFontNormal")
    eb:SetAutoFocus(false)
    eb:SetTextInsets(4, 4, 0, 0)
    eb:SetScript("OnEnterPressed", Accept)
    eb:SetScript("OnEscapePressed", function() f:Hide() end)
    eb:SetScript("OnTextChanged", Refresh)

    ok:SetScript("OnClick", Accept)
    cancel:SetScript("OnClick", function() f:Hide() end)
    f._msg, f._eb, f._ok, f._cancel, f._icon, f._top = msg, eb, ok, cancel, icon, top
    _built[skin] = f
    return f
end

-- The game's popup for a Confirm in combat. Its texts are set per show; the
-- text goes in as the %s argument, so a "%" in a note title is safe
local function ShowFallback(o)
    if not StaticPopupDialogs[FALLBACK] then
        StaticPopupDialogs[FALLBACK] = {
            text = "%s", button1 = L["OK"], button2 = L["CANCEL"],
            OnAccept = function(_, data)
                if data and data.onAccept then xpcall(data.onAccept, geterrorhandler()) end
                if data then data._bnbDone = true end
            end,
            OnCancel = function(_, data)
                if data and not data._bnbDone and data.onCancel then
                    data._bnbDone = true
                    xpcall(data.onCancel, geterrorhandler())
                end
            end,
            OnHide = function() _fbOpen = nil; Next() end,
            timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
        }
    end
    local d = StaticPopupDialogs[FALLBACK]
    d.button1 = o.okLabel or L["OK"]
    d.button2 = o.cancelLabel or L["CANCEL"]
    d.showAlert = o.alert and true or nil
    o._bnbDone = nil
    _fbOpen = o
    local popup = StaticPopup_Show(FALLBACK, o.text or "", nil, o)
    if popup then popup.data = o else _fbOpen = nil end
end

local function Open(kind, o)
    if kind == "confirm" and InCombatLockdown() then ShowFallback(o); return end
    local skin = BigNoteBoxDB and BigNoteBoxDB.skinMode and true or false
    _f = _built[skin] or Build(skin)
    local f = _f
    local prompt = kind == "prompt"
    f:SetWindowTitle(o.title or (prompt and "" or "BigNoteBox"))
    f._ok:SetText(o.okLabel or L["OK"])
    f._cancel:SetText(o.cancelLabel or L["CANCEL"])
    f._ok:SetEnabled(true)

    local alert = (not prompt) and o.alert
    local textX = alert and (ICON + 10) or 0
    if alert then f._icon:Show() else f._icon:Hide() end
    f._msg:ClearAllPoints()
    f._msg:SetPoint("TOPLEFT", f, "TOPLEFT", PAD + textX, -f._top)
    f._msg:SetWidth(W - 2 * PAD - textX)
    f._msg:SetText(o.text or "")
    local textH = 0
    if o.text and o.text ~= "" then textH = math.ceil(f._msg:GetStringHeight()) + 8 end
    if alert and textH < ICON + 4 then textH = ICON + 4 end

    if prompt then
        f._eb:Show()
        f._eb:ClearAllPoints()
        f._eb:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, -(f._top + textH))
        f._eb:SetMaxLetters(o.maxLetters or 200)
        f:SetHeight(f._top + textH + EB_H + 14 + FOOT_H)
    else
        f._eb:Hide()
        f:SetHeight(f._top + math.max(textH, 20) + 6 + FOOT_H)
    end

    local host = o.host
    if host and not host:IsVisible() then host = nil end
    -- Over Focus mode too (it hides UIParent, ALL-163); over the host's
    -- FULLSCREEN_DIALOG dimmer when there is one
    BNB.SeatWindow(f, o.strata or (host and "FULLSCREEN_DIALOG" or "DIALOG"))
    f:ClearAllPoints()
    if host then
        f:SetPoint("CENTER", host, "CENTER", 0, 20)
        if not _hooked[host] then
            _hooked[host] = true
            host:HookScript("OnHide", function()
                if _f and _f:IsShown() and _o and _o.host == host then _f:Hide() end
            end)
        end
    else
        f:SetPoint("CENTER", UIParent, "CENTER", 0, 120)
    end
    _o, _kind, _done = o, kind, nil
    Dim(host)
    if prompt then f._eb:SetText(o.value or "") end
    f:Show()
    if _ov then f:SetFrameLevel(_ov:GetFrameLevel() + 10) end
    f:Raise()
    if prompt then
        f._eb:SetFocus()
        f._eb:HighlightText()
        Refresh()
    end
end

Show = function(kind, o)
    if Busy() then
        local k = KeyOf(o)
        if (_o and KeyOf(_o) == k) or (_fbOpen and KeyOf(_fbOpen) == k) then return end
        for _, q in ipairs(_queue) do if KeyOf(q[2]) == k then return end end
        _queue[#_queue + 1] = { kind, o }
        return
    end
    Open(kind, o)
end

function D.Prompt(o) Show("prompt", o) end
function D.Confirm(o) Show("confirm", o) end

-- True while the pointer is on our open dialog: Select mode treats a press
-- there as a press on a confirm popup and stays on (UI/NoteList.lua)
function D.IsMouseOver()
    return (_f and _f:IsShown() and _f:IsMouseOver()) and true or false
end

-- Combat starts with a Confirm open: it moves to the game's popup, whose
-- keys still work (the Prompt keeps its box's keys and stays)
BNB.RegisterEvent("PLAYER_REGEN_DISABLED", function()
    if not (_f and _f:IsShown() and _kind == "confirm" and _o) then return end
    local o = _o
    _moving = true
    _f:Hide()
    _moving = nil
    ShowFallback(o)
end)

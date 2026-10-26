-- BigNoteBox UI/Dialog.lua
-- Our own small dialog (ALL-572; its first use is Rename, ALL-571), in place
-- of the game's StaticPopup where that one does not fit the addon. Built on
-- BNB.CreateToolWindow, so it has the look of every other BigNoteBox window:
-- the skin frame in skin mode, the game's window frame in normal mode (Dukul,
-- 2026-10-26: "Skin mode gets a skinned dialog, normal mode get's a dialog
-- that works with wow (not just a black box)"). One frame per look, built the
-- first time it is needed in that look.
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
-- Enter = OK, Esc = Cancel while the box has the focus (in combat too: the
-- box's own keys); Esc without the focus goes through BNB.AttachEscClose,
-- which leaves the key to the game in combat (BUG-05).
--------------------------------------------------------------------------------

local BNB = BigNoteBox
if not BNB then return end
local L = BNB.L

local D = {}
BNB.Dialog = D

local W, PAD, EB_H, FOOT_H = 340, 14, 24, 38

local _built = {}   -- [true] = the skin build, [false] = the normal build
local _f, _o        -- the frame in use, the open dialog's options

local _ovs, _ov = {}, nil   -- host -> its dimming overlay; the one shown
local _hooked = {}          -- hosts whose OnHide closes the dialog

local function Trim(s) return (s or ""):match("^%s*(.-)%s*$") end

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

local function Refresh()
    local f, o = _f, _o
    if f and o then f._ok:SetEnabled(o.allowEmpty or Trim(f._eb:GetText()) ~= "") end
end

local function Accept()
    local f, o = _f, _o
    if not (f and o and f:IsShown()) then return end
    local text = Trim(f._eb:GetText())
    if text == "" and not o.allowEmpty then return end
    f:Hide()   -- clears _o
    if o.onAccept then xpcall(o.onAccept, geterrorhandler(), text) end
end

local function Build(skin)
    local f, ok, cancel = BNB.CreateToolWindow({
        w = W, h = 120, title = "", pad = PAD, cw = W - 2 * PAD, footH = FOOT_H,
        btn1 = L["OK"], btn2 = L["CANCEL"],
        strata = "DIALOG", toplevel = true, keyEsc = true,
        onHide = function() _o = nil; Dim(nil) end,
    })
    local top = (f._isSkin and BNB.TOOL_SKIN_TITLE_H or 28) + 12

    local msg = f:CreateFontString(nil, "OVERLAY", "BNBFontHighlight")
    msg:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, -top)
    msg:SetWidth(W - 2 * PAD)
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
    f._msg, f._eb, f._ok, f._top = msg, eb, ok, top
    _built[skin] = f
    return f
end

function D.Prompt(o)
    if _f and _f:IsShown() then _f:Hide() end
    local skin = BigNoteBoxDB and BigNoteBoxDB.skinMode and true or false
    _f = _built[skin] or Build(skin)
    local f = _f
    f:SetWindowTitle(o.title or "")
    f._ok:SetText(o.okLabel or L["OK"])
    f._msg:SetText(o.text or "")
    local textH = 0
    if o.text and o.text ~= "" then textH = math.ceil(f._msg:GetStringHeight()) + 8 end
    f._eb:ClearAllPoints()
    f._eb:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, -(f._top + textH))
    f._eb:SetMaxLetters(o.maxLetters or 200)
    f:SetHeight(f._top + textH + EB_H + 14 + FOOT_H)
    local host = o.host
    if host and not host:IsVisible() then host = nil end
    -- Over Focus mode too (it hides UIParent, ALL-163); over the host's
    -- FULLSCREEN_DIALOG dimmer when there is one
    BNB.SeatWindow(f, host and "FULLSCREEN_DIALOG" or "DIALOG")
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
    _o = o
    Dim(host)
    f._eb:SetText(o.value or "")
    f:Show()
    if _ov then f:SetFrameLevel(_ov:GetFrameLevel() + 10) end
    f:Raise()
    f._eb:SetFocus()
    f._eb:HighlightText()
    Refresh()
end

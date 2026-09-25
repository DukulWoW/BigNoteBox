-- BigNoteBox UI/BugReport.lua
-- "Report a bug" (ALL-73): a button outside a window's top-right corner that
-- opens a window with links to the issue tracker and the three download sites,
-- GitHub first. Forever (beta): beside the main window, with a red glow.
-- Retail: beside the Settings window, so only while Settings is open (ALL-77). The same link buttons sit on the Forever login notice
-- (Core/Events.lua). Link buttons open the copy box (BNB.ShowClipboardHint).
--
-- Public API:
--   BNB.ShowBugReport()              open the window
--   BNB.CreateBugLinkButtons(parent) frame with the link buttons, see below
--   BNB.AttachBugButton()            called from Initialize once mainFrame exists
--   BNB.AttachSettingsBugButton(f)   called from OpenConfig once the Settings frame exists

local BNB = BigNoteBox
local L   = BNB.L

local BTN_PATH = "Interface\\AddOns\\BigNoteBox\\Assets\\Buttons\\"

BNB.BUG_LINKS = {
    github     = "https://github.com/DukulWoW/BigNoteBox/issues/new/choose",
    curseforge = "https://www.curseforge.com/wow/addons/bignotebox",
    wago       = "https://addons.wago.io/addons/bignotebox",
    wowi       = "https://www.wowinterface.com/downloads/info27121-BigNoteBox.html",
}

--------------------------------------------------------------------------------
-- LINK BUTTONS: GitHub full width on top, the three sites in a row below.
-- Returns a frame of the given width; its height is fixed (BUG_LINKS_H).
--------------------------------------------------------------------------------
local BTN_H, ROW_GAP = 24, 6
BNB.BUG_LINKS_H = BTN_H * 2 + ROW_GAP

function BNB.CreateBugLinkButtons(parent, width)
    local box = CreateFrame("Frame", nil, parent)
    box:SetSize(width, BNB.BUG_LINKS_H)

    local function LinkBtn(text, url)
        local b = CreateFrame("Button", nil, box, BNB.PanelButtonTemplate())
        b:SetHeight(BTN_H)
        b:SetText(text)
        b:SetScript("OnClick", function(self) BNB.ShowClipboardHint(url, self, true) end)
        b:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:AddLine(L["BUG_LINK_TIP"], 1, 1, 1)
            GameTooltip:AddLine(url, 0.6, 0.6, 0.6)
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        return b
    end

    local gh = LinkBtn(L["BUG_BTN_GITHUB"], BNB.BUG_LINKS.github)
    gh:SetPoint("TOPLEFT", box, "TOPLEFT", 0, 0)
    gh:SetPoint("TOPRIGHT", box, "TOPRIGHT", 0, 0)

    local GAP = 6
    local w = (width - GAP * 2) / 3
    local prev
    for _, site in ipairs({
        { "CurseForge",   BNB.BUG_LINKS.curseforge },
        { "Wago",         BNB.BUG_LINKS.wago },
        { "WoWInterface", BNB.BUG_LINKS.wowi },
    }) do
        local b = LinkBtn(site[1], site[2])
        b:SetWidth(w)
        if prev then
            b:SetPoint("LEFT", prev, "RIGHT", GAP, 0)
        else
            b:SetPoint("TOPLEFT", gh, "BOTTOMLEFT", 0, -ROW_GAP)
        end
        prev = b
    end
    return box
end

--------------------------------------------------------------------------------
-- WINDOW
--------------------------------------------------------------------------------
local GLOW_KEY = "bnb_bugreport"
local _win

function BNB.ShowBugReport()
    local f = _win
    if not f then
        local W, PAD = 400, 20
        f = CreateFrame("Frame", "BNBBugReportFrame", UIParent, "ButtonFrameTemplate")
        f:SetWidth(W)
        f:SetPoint("CENTER", UIParent, "CENTER", 0, 120)
        f:SetFrameStrata("DIALOG")
        f:SetToplevel(true)
        f:SetClampedToScreen(true)
        f:EnableMouse(true)
        f:SetMovable(true)
        f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", f.StartMoving)
        f:SetScript("OnDragStop", f.StopMovingOrSizing)
        ButtonFrameTemplate_HidePortrait(f)
        ButtonFrameTemplate_HideButtonBar(f)
        if f.Inset then f.Inset:Hide() end
        BNB.SeatChrome(f)
        BNB.AddForeverGlow(f, f.Bg)
        f:SetTitle(L["BUG_TITLE"])
        tinsert(UISpecialFrames, "BNBBugReportFrame")

        local body = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        body:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, -40)
        body:SetWidth(W - PAD * 2)
        body:SetJustifyH("LEFT")
        body:SetSpacing(2)
        body:SetText(L["BUG_BODY"])

        local links = BNB.CreateBugLinkButtons(f, W - PAD * 2)
        links:SetPoint("TOPLEFT", body, "BOTTOMLEFT", 0, -16)

        local close = CreateFrame("Button", nil, f, BNB.PanelButtonTemplate())
        close:SetSize(120, 26)
        close:SetPoint("BOTTOM", f, "BOTTOM", 0, 16)
        close:SetText(CLOSE or "Close")
        close:SetScript("OnClick", function() f:Hide() end)

        -- Created shown, so size it here (an OnShow set now would not fire)
        f:SetHeight(40 + body:GetStringHeight() + 16 + BNB.BUG_LINKS_H + 20 + 26 + 16)

        f:HookScript("OnShow", function(self)
            if BNB.StartWindowGlow then BNB.StartWindowGlow(self, GLOW_KEY) end
        end)
        f:HookScript("OnHide", function(self)
            if BNB.StopWindowGlow then BNB.StopWindowGlow(self, GLOW_KEY) end
        end)
        _win = f
        if BNB.StartWindowGlow then BNB.StartWindowGlow(f, GLOW_KEY) end
    end
    f:Show()
    f:Raise()
end

--------------------------------------------------------------------------------
-- BUTTON outside a window's top-right corner (same look as the rich-note
-- editor/view buttons, NoteEditor.lua MakeRichBtn)
--------------------------------------------------------------------------------
local BUG_BTN_SZ   = 32
local BUG_BTN_X    = 6     -- gap from the window's right edge
local BUG_BTN_Y    = -24   -- down from the window's top edge

-- Where the button lives (Dukul, 2026-09-25): Settings on Retail, the main
-- window on Forever during the beta. At Forever launch, Forever moves to
-- Settings too (and loses the glow): make this true on both clients.
local BUG_BTN_ON_SETTINGS = not BNB.IsForever

-- host: the window the button sits beside, and its parent (hidden with it).
-- glow: the red pixel glow that gets the button noticed during the beta.
local function MakeBugButton(host, glow)
    if not host or host._bugBtn then return end

    local btn = CreateFrame("Button", nil, host)
    btn:SetSize(BUG_BTN_SZ, BUG_BTN_SZ)
    local d = BNB.IsForever and BNB.CHROME_DELTA or nil
    btn:SetPoint("TOPLEFT", host, "TOPRIGHT", BUG_BTN_X + (d and d.r or 0), BUG_BTN_Y)

    local n = btn:CreateTexture(nil, "ARTWORK"); n:SetAllPoints()
    n:SetTexture(BTN_PATH .. "bt-bugs-normal")
    local h = btn:CreateTexture(nil, "ARTWORK"); h:SetAllPoints()
    h:SetTexture(BTN_PATH .. "bt-bugs-hover"); h:Hide()
    local p = btn:CreateTexture(nil, "ARTWORK"); p:SetAllPoints()
    p:SetTexture(BTN_PATH .. "bt-bugs-press"); p:Hide()
    btn._n, btn._h, btn._p = n, h, p

    btn:SetScript("OnMouseDown", function() p:Show(); n:Hide(); h:Hide() end)
    btn:SetScript("OnMouseUp",   function() p:Hide(); h:Show(); n:Hide() end)
    btn:SetScript("OnEnter", function(self)
        n:Hide(); h:Show()
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(L["BUG_BTN_TIP"], 1, 1, 1)
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function()
        p:Hide(); h:Hide(); n:Show()
        GameTooltip:Hide()
    end)
    btn:SetScript("OnClick", function() BNB.ShowBugReport() end)
    host._bugBtn = btn

    -- Pixel glow so the button is noticed during the beta (Dukul, 2026-09-25):
    -- red, lines 6, frequency 0.10, length 8. Runs while the
    -- button is shown; the library's glow frame is a child of the button.
    local LCG = glow and LibStub and LibStub("LibCustomGlow-1.0", true)
    if LCG and LCG.PixelGlow_Start then
        pcall(LCG.PixelGlow_Start, btn, { 1, 0.15, 0.15, 1 }, 6, 0.10, 8, nil, nil, nil, nil, "bnb_bugbtn")
    end
end

function BNB.AttachBugButton()
    if BUG_BTN_ON_SETTINGS then return end
    MakeBugButton(BNB.mainFrame, true)
end

function BNB.AttachSettingsBugButton(cfgFrame)
    if not BUG_BTN_ON_SETTINGS then return end
    MakeBugButton(cfgFrame, false)
end

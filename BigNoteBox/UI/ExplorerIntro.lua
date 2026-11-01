-- BigNoteBox UI/ExplorerIntro.lua -- The release welcome (ALL-543 Explorer
-- welcome, made the 2.0 welcome by ALL-617)
--
-- Once per account per big release (welcomeSeen = WELCOME_RELEASE, shared by
-- every profile), the main window opens under a dimmed overlay: a welcome box
-- with the release's biggest new things, one row each with an icon, and a
-- row with the Settings NEW badge. For a later big release: change
-- WELCOME_RELEASE and the ROWS; a release without one keeps the old value, so
-- nothing shows.
-- Everyone sees it: players updating and new installs (after the setup
-- wizard; its Finish reloads, its Quit calls BNB.ShowExplorerIntroIfDue).
--
-- Three buttons: Patch notes (this release's page in the Help book), Let's go
-- (gold, closes the box) and Open help (the Help book's cover). There is no
-- note list button: players are steered to the Explorer view, and the
-- callout on the switch icon shows how to change (Dukul, 2026-11-01).
-- With the Explorer module on, the window opens on the explorer grid and a
-- callout arrow points at the switch icon at the top left; Explorer off: the
-- note list, no callout, no footer. Esc and the X keep what is showing. A
-- second callout points at the Help button on the top right, with the module
-- on or off (ALL-554: the Help book never opens by itself, Dukul 2026-10-30).
--
-- Until it is answered, toasts wait (BNB.Toast holds them through
-- BNB.ExplorerIntroHolding) and so does the Forever / Classic notice; both
-- come when it closes. Closing the main window without answering keeps it
-- for the next time the window shows. In combat it waits for combat to end.
--
-- The box is as tall as its rows; on a main window shorter than that it is
-- scaled down to fit.
--
-- Developer tools > Release welcome clears the flag and reloads.
--------------------------------------------------------------------------------

local BNB = BigNoteBox
local L   = BNB.L
local EX  = BNB.Explorer

local WELCOME_RELEASE = "2.0"     -- the release this welcome is for
local WELCOME_PATCH   = "2.0.0"   -- the Patch notes page the link opens

local ARROW   = "Interface\\AddOns\\BigNoteBox\\Assets\\UI\\ui-new-arrow"
local ART     = "Interface\\AddOns\\BigNoteBox\\Assets\\"
local BOX_W   = 600
local PAD     = 24
local BTN_W   = 180
local BTN_H   = 28
local GOLD_H  = 34         -- the gold Let's go button, a little taller than its neighbours
local BTN_GAP = 12
local ROW_ICON = 20
local ROW_TEXT_X = 56      -- text column: room for the NEW badge (46 x 24)
local CALLOUT_W = 240      -- widest; narrower when the welcome box is close
local CALLOUT_MIN = 130
local FIT_GAP = 16         -- kept free above and below the box

-- The rows: icon (under Assets\), locale key; tint = false keeps the art's
-- own colours; skin = a white file used (tinted) in skin mode instead;
-- explorer = only while the Explorer module is on
local ROWS = {
    { "Explorer/ex-explorer-mode",     "WELCOME_ROW_EXPLORER", explorer = true },
    { "Explorer/ex-new-folder",        "WELCOME_ROW_FOLDERS" },   -- white, full size (cm-folder is gold and small)
    { "Topbar/Normal/tp-help-normal",  "WELCOME_ROW_HELP", tint = false, skin = "Topbar/tp-help" },
    { "Toolbar/tb-spellcheck",         "WELCOME_ROW_SPELLING" },
    { "Toolbar/tb-search-replace",     "WELCOME_ROW_FIND" },
    { "Toolbar/tb-rich-divider",       "WELCOME_ROW_RICH" },
    { "UI/ui-welcome-motion",          "WELCOME_ROW_MOTION" },   -- placeholder art
    { "NEW",                           "WELCOME_ROW_NEW" },      -- the Settings NEW badge
}

local _ov            -- the overlay over the main window
local _open = false  -- shown and not answered yet
local _waitCombat = false

-- Show / Hide (FontStrings have no SetShown here)
local function Vis(r, on) if on then r:Show() else r:Hide() end end

local function Skin() return BigNoteBoxDB and BigNoteBoxDB.skinMode end
local function ExplorerOn() return BNB.ExplorerEnabled and BNB.ExplorerEnabled() and true or false end

-- Due: setup done, this release's welcome not seen on this account
function BNB.ExplorerIntroDue()
    local db = BigNoteBoxDB
    if not db or db.setupComplete ~= true then return false end
    return db.welcomeSeen ~= WELCOME_RELEASE
end

-- Toasts and the Forever notice wait while this is true
function BNB.ExplorerIntroHolding()
    return _open or BNB.ExplorerIntroDue()
end

local function SetFontSize(fs, size)
    pcall(function() fs:SetFont(BNB.GetLocaleFont(), size, "") end)
end

-- ── Build ───────────────────────────────────────────────────────────────────
local Finish

local function NewText(parent, obj, size)
    local fs = parent:CreateFontString(nil, "OVERLAY", obj or "BNBFontHighlight")
    if size then SetFontSize(fs, size) end
    fs:SetJustifyH("LEFT")
    fs:SetJustifyV("TOP")
    fs:SetWordWrap(true)
    return fs
end

local BOX_ALPHA = 0.88   -- the middle box lets a little of the grid through (Dukul, 2026-10-22)

-- The gold button (interface/buttons/128goldredbutton, Dukul 2026-11-01): a
-- left cap, a stretched middle and a right cap from the game's atlas, scaled
-- to the button's height. Skin mode gets the large skin button (every button
-- in a skin window is a skin button); a client without the atlas a normal one.
local GOLD = { l = "128-GoldRedButton-Left", r = "128-GoldRedButton-Right",
               c = "_128-GoldRedButton-Center", hl = "128-GoldRedButton-Highlight" }
local GOLD_L_W, GOLD_R_W, GOLD_ART_H = 114, 292, 128   -- atlas sizes

local function HasAtlas(name)
    return C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(name) and true or false
end

local function CreateGoldButton(parent, text, w, h)
    if Skin() then
        -- Label in the skin accent, not white: it stands out as the gold one
        -- does in normal mode (follows preset changes; Dukul, 2026-11-01)
        local b = BNB.CreateSkinButton(nil, parent, text, w, h, 16)
        if b._lbl and BNB.SetHeaderColor then BNB.SetHeaderColor(b._lbl) end
        return b
    end
    if not (HasAtlas(GOLD.l) and HasAtlas(GOLD.r) and HasAtlas(GOLD.c)) then
        return BNB.CreateButton(nil, parent, text, w, h)
    end
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(w, h)
    local l = b:CreateTexture(nil, "BACKGROUND")
    local r = b:CreateTexture(nil, "BACKGROUND")
    local c = b:CreateTexture(nil, "BACKGROUND")
    l:SetPoint("TOPLEFT"); l:SetPoint("BOTTOMLEFT")
    r:SetPoint("TOPRIGHT"); r:SetPoint("BOTTOMRIGHT")
    c:SetPoint("TOPLEFT", l, "TOPRIGHT"); c:SetPoint("BOTTOMRIGHT", r, "BOTTOMLEFT")
    local function Art(suffix)
        l:SetAtlas(GOLD.l .. suffix); r:SetAtlas(GOLD.r .. suffix); c:SetAtlas(GOLD.c .. suffix)
    end
    Art("")
    if HasAtlas(GOLD.hl) then
        local hl = b:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAtlas(GOLD.hl)
        hl:SetAllPoints()
        hl:SetBlendMode("ADD")
    end
    local fs = b:CreateFontString(nil, "OVERLAY", "BNBFontHighlight")
    SetFontSize(fs, 14)
    BNB.SetTextWhite(fs)
    fs:SetText(text or "")
    local function Up() Art(""); fs:ClearAllPoints(); fs:SetPoint("CENTER", b, "CENTER", 0, 1) end
    Up()
    -- The caps keep the art's shape; on a narrow button both shrink to fit
    function b:FitArt()
        local bh, bw = self:GetHeight() or h, self:GetWidth() or w
        local lw, rw = bh * GOLD_L_W / GOLD_ART_H, bh * GOLD_R_W / GOLD_ART_H
        local sc = math.min(1, (bw - 2) / (lw + rw))
        l:SetWidth(math.max(1, math.floor(lw * sc)))
        r:SetWidth(math.max(1, math.floor(rw * sc)))
    end
    b:FitArt()
    b:SetScript("OnMouseDown", function()
        Art("-Pressed"); fs:ClearAllPoints(); fs:SetPoint("CENTER", b, "CENTER", 1, 0)
    end)
    b:SetScript("OnMouseUp", Up)
    b:SetScript("OnHide", Up)
    return b
end

local function OpenPatchNotes()
    Finish()
    if BNB.HelpBook and BNB.HelpBook.OpenPatchNotes then BNB.HelpBook.OpenPatchNotes(WELCOME_PATCH) end
end

local function OpenHelpBook()
    Finish()
    if BNB.HelpBook and BNB.HelpBook.Open then BNB.HelpBook.Open() end
end

local function BuildBox(ov)
    local box
    if Skin() then
        box = BNB.CreateSkinFrame(ov, true)
        -- The skin repaints its colour on preset changes: keep it a little see-through
        hooksecurefunc(box, "SetBackdropColor", function(self, r, g, b, a)
            if self._bnbAlphaLock then return end
            self._bnbAlphaLock = true
            self:SetBackdropColor(r, g, b, (a or 1) * BOX_ALPHA)
            self._bnbAlphaLock = nil
        end)
        box:SetBackdropColor(box:GetBackdropColor())
    else
        box = BNB.CreateBackdropFrame("Frame", nil, ov)
        BNB.SetBackdrop(box, 0.06, 0.06, 0.07, BOX_ALPHA, 0.85, 0.68, 0.25, 1)
    end
    box:SetPoint("CENTER", ov, "CENTER", 0, 0)
    box:EnableMouse(true)

    local hr, hg, hb = BNB.HeaderColor()
    box._welcome = NewText(box, "BNBFontHighlight", 18)
    box._welcome:SetJustifyH("CENTER")
    box._welcome:SetText(L["WELCOME_HELLO"])
    box._title = NewText(box, "BNBFontNormalHuge", 40)
    box._title:SetJustifyH("CENTER")
    box._title:SetTextColor(hr, hg, hb)
    box._title:SetText(string.format(L["WELCOME_TITLE"], WELCOME_RELEASE))
    box._lead = NewText(box, "BNBFontHighlight", 14)
    box._lead:SetText(L["WELCOME_LEAD"])

    box._rows = {}
    for i, p in ipairs(ROWS) do
        local ic
        if p[1] == "NEW" then
            ic = BNB.NewBadgeTexture and BNB.NewBadgeTexture(box, 24)
            if not ic then   -- a client without the badge art: the word in its green
                ic = NewText(box, "BNBFontNormal", 13)
                ic:SetTextColor(hr, hg, hb)
                ic:SetText("NEW")
            end
        else
            ic = box:CreateTexture(nil, "ARTWORK")
            ic:SetSize(ROW_ICON, ROW_ICON)
            -- skin = the white skin-mode file, tinted like the rest
            local skinArt = Skin() and p.skin
            ic:SetTexture(ART .. (skinArt or p[1]))
            if skinArt or p.tint ~= false then BNB.TintUIIcon(ic) end
            -- The top bar's skin art is flat: black copies under it, a little
            -- larger and centred, give the even dark glow the other row icons
            -- have in their art (an offset shadow looked off, Dukul 2026-11-01)
            if skinArt then
                for _, g in ipairs({ { 4, 0.35 }, { 2, 0.6 } }) do
                    local sh = box:CreateTexture(nil, "BORDER")
                    sh:SetTexture(ART .. skinArt)
                    sh:SetVertexColor(0, 0, 0, g[2])
                    sh:SetSize(ROW_ICON + g[1], ROW_ICON + g[1])
                    sh:SetPoint("CENTER", ic, "CENTER")
                end
            end
        end
        local fs = NewText(box, "BNBFontHighlight", 13)
        fs:SetText(L[p[2]])
        box._rows[i] = { ic = ic, fs = fs, explorer = p.explorer, badge = p[1] == "NEW" }
    end

    box._foot = NewText(box, "BNBFontHighlightSmall", 12)
    box._foot:SetTextColor(0.75, 0.75, 0.75)
    box._foot:SetText(L["EXPLORER_INTRO_FOOT"])

    box._patch = BNB.CreateButton(nil, box, L["WELCOME_BTN_PATCH"], BTN_W, BTN_H)
    box._patch:SetScript("OnClick", OpenPatchNotes)
    box._go = CreateGoldButton(box, L["WELCOME_BTN_GO"], BTN_W, GOLD_H)
    box._go:SetScript("OnClick", function() Finish() end)
    box._help = BNB.CreateButton(nil, box, L["WELCOME_BTN_HELP"], BTN_W, BTN_H)
    box._help:SetScript("OnClick", OpenHelpBook)

    local x = BNB.CreateIconButton(box, 22, "close", { skin = Skin() and true or false,
        onClick = function() Finish() end })
    x:SetPoint("TOPRIGHT", box, "TOPRIGHT", -6, -6)
    return box
end

-- A top bar icon lit above the dim, an arrow under it and the callout text
local function BuildCallout(ov, textKey)
    local c = {}
    c.glow = ov:CreateTexture(nil, "ARTWORK", nil, 1)
    c.glow:SetTexture(BNB.UI_HOVER_TEX)
    BNB.TintUIIcon(c.glow)
    c.icon = ov:CreateTexture(nil, "ARTWORK", nil, 2)
    c.arrow = ov:CreateTexture(nil, "ARTWORK", nil, 2)
    c.arrow:SetSize(48, 48)
    c.arrow:SetTexture(ARROW)
    BNB.TintUIIcon(c.arrow)

    local box
    if Skin() then
        box = BNB.CreateSkinFrame(ov, true)
    else
        box = BNB.CreateBackdropFrame("Frame", nil, ov)
        BNB.SetBackdrop(box, 0.06, 0.06, 0.07, 0.97, 0.85, 0.68, 0.25, 1)
    end
    box:SetWidth(CALLOUT_W)
    local fs = NewText(box, "BNBFontHighlight", 13)
    fs:SetPoint("TOPLEFT", box, "TOPLEFT", 12, -10)
    fs:SetWidth(CALLOUT_W - 24)
    fs:SetText(L[textKey])
    c.box, c.text = box, fs
    return c
end

-- A callout on its button, or hidden when the button does not show (the
-- Help icon moves into the top bar menu on a narrow window). right = the
-- text box to the left of the arrow, for a button at the right edge
local function PlaceCallout(c, btn, right, room)
    local show = btn and btn:IsVisible()
    for _, r in ipairs({ c.glow, c.icon, c.arrow }) do r:SetShown(show and true or false) end
    c.box:SetShown(show and true or false)
    if not show then return end
    local s = btn:GetWidth()
    c.icon:ClearAllPoints()
    c.icon:SetAllPoints(btn)
    if btn._tx then
        c.icon:SetTexture(btn._tx:GetTexture())
        c.icon:SetVertexColor(btn._tx:GetVertexColor())
    end
    c.glow:ClearAllPoints()
    c.glow:SetPoint("CENTER", btn, "CENTER")
    c.glow:SetSize(s + 18, s + 18)
    c.arrow:ClearAllPoints()
    c.arrow:SetPoint("TOP", btn, "BOTTOM", right and -2 or 2, -4)
    -- The art curves to the right: mirrored for the right-hand callout
    if right then c.arrow:SetTexCoord(1, 0, 0, 1) else c.arrow:SetTexCoord(0, 1, 0, 1) end
    -- As wide as the room beside the welcome box allows (Dukul, 2026-10-30)
    local cw = math.floor(math.max(CALLOUT_MIN, math.min(CALLOUT_W, room or CALLOUT_W)))
    c.box:SetWidth(cw)
    c.text:SetWidth(cw - 24)
    c.box:ClearAllPoints()
    if right then
        c.box:SetPoint("TOPRIGHT", c.arrow, "BOTTOMLEFT", 14, 12)
    else
        c.box:SetPoint("TOPLEFT", c.arrow, "BOTTOMRIGHT", -14, 12)
    end
    c.box:SetHeight(math.ceil(c.text:GetStringHeight() or 0) + 20)
end

-- Sizes from the measured text; run again a little later, as a bundled font
-- can measure 0 until it has loaded (ALL-16)
local function Layout()
    if not _ov then return end
    local mf = BNB.mainFrame
    local box = _ov._box
    local exOn = ExplorerOn() and EX.IsActive and EX.IsActive()
    box:SetScale(1)
    local w = math.min(BOX_W, math.max(380, (mf:GetWidth() or BOX_W) - 80))
    box:SetWidth(w)
    local inner = w - PAD * 2
    local y = -PAD
    local function Put(fs, x, width, gap)
        fs:ClearAllPoints()
        fs:SetPoint("TOPLEFT", box, "TOPLEFT", PAD + x, y)
        fs:SetWidth(width)
        y = y - math.ceil(fs:GetStringHeight() or 0) - gap
    end
    Put(box._welcome, 0, inner, 0)
    Put(box._title, 0, inner, 14)
    Put(box._lead, 0, inner, 14)
    for _, r in ipairs(box._rows) do
        local show = exOn or not r.explorer
        Vis(r.ic, show); Vis(r.fs, show)
        if show then
            local top = y
            Put(r.fs, ROW_TEXT_X, inner - ROW_TEXT_X, 10)
            -- Icon centred in the icon column, level with the first line
            local iw = r.ic.GetStringWidth and math.ceil(r.ic:GetStringWidth() or 0) or r.ic:GetWidth()
            local ih = r.ic.GetStringHeight and 13 or r.ic:GetHeight()
            r.ic:ClearAllPoints()
            r.ic:SetPoint("TOPLEFT", box, "TOPLEFT", PAD + math.floor((ROW_TEXT_X - 10 - iw) / 2),
                top + math.floor((ih - 15) / 2))
        end
    end
    y = y - 4
    Vis(box._foot, exOn)
    if exOn then Put(box._foot, 0, inner, 18) else y = y - 4 end
    -- [ Patch notes ] [ Let's go ] [ Open help ], Let's go in the middle
    local bw = math.min(BTN_W, math.floor((inner - BTN_GAP * 2) / 3))
    box._patch:SetWidth(bw); box._go:SetWidth(bw); box._help:SetWidth(bw)
    if box._go.FitArt then box._go:FitArt() end
    box._go:ClearAllPoints()
    box._go:SetPoint("TOP", box, "TOP", 0, y)
    box._patch:ClearAllPoints()
    box._patch:SetPoint("RIGHT", box._go, "LEFT", -BTN_GAP, 0)
    box._help:ClearAllPoints()
    box._help:SetPoint("LEFT", box._go, "RIGHT", BTN_GAP, 0)
    y = y - GOLD_H - PAD
    box:SetHeight(-y)

    -- Taller than the window: scaled down to fit (CENTER anchor keeps it centred)
    local room = (mf:GetHeight() or -y) - FIT_GAP * 2
    local sc = 1
    if -y > room and room > 0 then sc = math.max(0.5, room / -y) end
    box:SetScale(sc)
    box:ClearAllPoints()
    box:SetPoint("CENTER", _ov, "CENTER", 0, 0)

    -- The callouts: the switch icon (top left, Explorer on) and the Help
    -- button (top right), each as wide as the room between its button and
    -- the welcome box. A callout's box starts 12 px past its button's centre
    -- (the arrow's tip); the welcome box is centred, w * sc wide
    local half = w * sc / 2
    local cx = (_ov:GetLeft() or 0) + (_ov:GetWidth() or 0) / 2
    local function Room(btn, right)
        local bx = btn and btn:IsVisible() and btn:GetCenter()
        if not bx then return nil end
        if right then return (bx - 12) - (cx + half) - FIT_GAP end
        return (cx - half) - (bx + 12) - FIT_GAP
    end
    local vb = exOn and EX.ViewButton and EX.ViewButton()
    local hb = BNB._toolbarHelpBtn
    PlaceCallout(_ov._callout, vb, false, Room(vb, false))
    PlaceCallout(_ov._helpCallout, hb, true, Room(hb, true))
end

local function Build()
    local mf = BNB.mainFrame
    local ov = CreateFrame("Frame", nil, mf)
    ov:SetAllPoints(mf)
    -- One strata over the window: a raised level loses to its children
    ov:SetFrameStrata("HIGH")
    ov:EnableMouse(true)          -- the window under it takes no clicks
    ov:EnableMouseWheel(true)
    ov:SetScript("OnMouseWheel", function() end)
    local dim = ov:CreateTexture(nil, "BACKGROUND")
    dim:SetAllPoints()
    dim:SetColorTexture(0, 0, 0, 0.72)
    ov._box = BuildBox(ov)
    ov._callout = BuildCallout(ov, "EXPLORER_INTRO_CALLOUT")
    ov._helpCallout = BuildCallout(ov, "WELCOME_HELP_CALLOUT")
    BNB.AttachEscClose(ov, function() Finish() end)
    ov:SetScript("OnShow", function() Layout() end)
    -- Next frame: Layout sets text widths, never inside OnSizeChanged's pass
    mf:HookScript("OnSizeChanged", function()
        if _ov and _ov:IsShown() then BNB.Debounce("bnbWelcomeLayout", 0, Layout) end
    end)
    ov:Hide()
    return ov
end

-- ── Show / answer ───────────────────────────────────────────────────────────
Finish = function()
    if not _open then return end
    _open = false
    local db = BigNoteBoxDB
    if db then
        db.welcomeSeen = WELCOME_RELEASE
        db.explorerIntroSeen = nil   -- the 2.0 beta's flag, before ALL-617
    end
    if _ov then
        local ov = _ov
        BNB.FadeTo(ov, ov:GetAlpha(), 0, 0.2, function() ov:Hide(); ov:SetAlpha(1) end)
    end
    -- What waited for it
    if BNB.Toast and BNB.Toast.ReleaseHeld then BNB.Toast.ReleaseHeld() end
    if BNB.ShowForeverNoticeIfDue then BNB.ShowForeverNoticeIfDue() end
end

function BNB.ShowExplorerIntroIfDue()
    if _open or not BNB.ExplorerIntroDue() then return end
    if InCombatLockdown() then _waitCombat = true; return end
    if BNB.OpenMainWindow then BNB.OpenMainWindow() end
    if not BNB.mainFrame then return end
    -- The explorer at the top of its grid, so the switch icon shows (a note
    -- or a folder puts the back arrow in its place)
    if ExplorerOn() and EX.SetActive then
        if EX.IsActive() then EX.SetActive(false) end
        EX.SetActive(true)
    end
    _ov = _ov or Build()
    _open = true
    _ov:SetAlpha(1)
    _ov:Show()
    Layout()
    C_Timer.After(0.1, Layout)
    C_Timer.After(0.6, Layout)
end

BNB.RegisterEvent("PLAYER_REGEN_ENABLED", function()
    if not _waitCombat then return end
    _waitCombat = false
    C_Timer.After(0.5, BNB.ShowExplorerIntroIfDue)
end)

-- BigNoteBox UI/ExplorerIntro.lua -- The release welcome (ALL-543 Explorer
-- welcome, made the 2.0 welcome by ALL-617)
--
-- Once per account per big release (welcomeSeen = WELCOME_RELEASE, shared by
-- every profile), the main window opens under a dimmed overlay: a welcome box
-- with the release's biggest new things, one row each with an icon, a link to
-- that release's page in the Help book's Patch notes tab, and a row with the
-- Settings NEW badge. For a later big release: change WELCOME_RELEASE and the
-- ROWS; a release without one keeps the old value, so nothing shows.
-- Everyone sees it: players updating and new installs (after the setup
-- wizard; its Finish reloads, its Quit calls BNB.ShowExplorerIntroIfDue).
--
-- With the Explorer module on, the window opens on the explorer grid, a
-- callout arrow points at the switch icon at the top left, and the two buttons
-- keep the explorer or go back to the note list (which then becomes the view
-- the window opens on). Explorer off: the note list, no callout, one OK
-- button. Esc and the X keep what is showing.
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
local BTN_W   = 200
local BTN_H   = 28
local ROW_ICON = 20
local ROW_TEXT_X = 56      -- text column: room for the NEW badge (46 x 24)
local CALLOUT_W = 240
local FIT_GAP = 16         -- kept free above and below the box

-- The rows: icon (under Assets\), locale key; tint = false keeps the art's
-- own colours; explorer = only while the Explorer module is on
local ROWS = {
    { "Explorer/ex-explorer-mode",     "WELCOME_ROW_EXPLORER", explorer = true },
    { "ContextMenu/Symbols/cm-folder", "WELCOME_ROW_FOLDERS" },
    { "Topbar/Normal/tp-help-normal",  "WELCOME_ROW_HELP", tint = false },
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

-- "See everything else..." under the rows: opens this release's patch notes
local function BuildMoreLink(box)
    local b = CreateFrame("Button", nil, box)
    local fs = NewText(b, "BNBFontHighlight", 13)
    fs:SetPoint("TOPLEFT")
    fs:SetText(L["WELCOME_MORE"])
    local function Paint(hover)
        if hover then fs:SetTextColor(1, 0.93, 0.6) else fs:SetTextColor(1, 0.8, 0.2) end
    end
    Paint(false)
    b:SetScript("OnEnter", function() Paint(true) end)
    b:SetScript("OnLeave", function() Paint(false) end)
    b:SetScript("OnClick", function()
        Finish(false)
        if BNB.HelpBook and BNB.HelpBook.OpenPatchNotes then BNB.HelpBook.OpenPatchNotes(WELCOME_PATCH) end
    end)
    b._fs = fs
    return b
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
            ic:SetTexture(ART .. p[1])
            if p.tint ~= false then BNB.TintUIIcon(ic) end
        end
        local fs = NewText(box, "BNBFontHighlight", 13)
        fs:SetText(L[p[2]])
        box._rows[i] = { ic = ic, fs = fs, explorer = p.explorer, badge = p[1] == "NEW" }
    end

    box._more = BuildMoreLink(box)

    box._foot = NewText(box, "BNBFontHighlightSmall", 12)
    box._foot:SetTextColor(0.75, 0.75, 0.75)
    box._foot:SetText(L["EXPLORER_INTRO_FOOT"])

    box._list = BNB.CreateButton(nil, box, L["EXPLORER_INTRO_LIST"], BTN_W, BTN_H)
    box._list:SetScript("OnClick", function() Finish(true) end)
    box._keep = BNB.CreateButton(nil, box, L["EXPLORER_INTRO_KEEP"], BTN_W, BTN_H)
    box._keep:SetScript("OnClick", function() Finish(false) end)
    box._ok = BNB.CreateButton(nil, box, L["WELCOME_OK"], BTN_W, BTN_H)
    box._ok:SetScript("OnClick", function() Finish(false) end)

    local x = BNB.CreateIconButton(box, 22, "close", { skin = Skin() and true or false,
        onClick = function() Finish(false) end })
    x:SetPoint("TOPRIGHT", box, "TOPRIGHT", -6, -6)
    return box
end

-- The switch icon lit above the dim, an arrow under it and the callout
local function BuildCallout(ov)
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
    fs:SetText(L["EXPLORER_INTRO_CALLOUT"])
    c.box, c.text = box, fs
    return c
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
    box._more._fs:SetWidth(inner)
    local mh = math.ceil(box._more._fs:GetStringHeight() or 0)
    box._more:SetSize(math.min(inner, math.ceil(box._more._fs:GetStringWidth() or 0) + 2), mh)
    box._more:ClearAllPoints()
    box._more:SetPoint("TOPLEFT", box, "TOPLEFT", PAD, y)
    y = y - mh - 14
    Vis(box._foot, exOn)
    if exOn then Put(box._foot, 0, inner, 18) else y = y - 4 end
    box._list:SetShown(exOn and true or false)
    box._keep:SetShown(exOn and true or false)
    box._ok:SetShown(not exOn)
    local bw = math.min(BTN_W, math.floor((inner - 12) / 2))
    box._list:SetWidth(bw); box._keep:SetWidth(bw); box._ok:SetWidth(bw)
    box._list:ClearAllPoints()
    box._list:SetPoint("TOPRIGHT", box, "TOP", -6, y)
    box._keep:ClearAllPoints()
    box._keep:SetPoint("TOPLEFT", box, "TOP", 6, y)
    box._ok:ClearAllPoints()
    box._ok:SetPoint("TOP", box, "TOP", 0, y)
    y = y - BTN_H - PAD
    box:SetHeight(-y)
    -- Taller than the window: scaled down to fit (CENTER anchor keeps it centred)
    local room = (mf:GetHeight() or -y) - FIT_GAP * 2
    if -y > room and room > 0 then box:SetScale(math.max(0.5, room / -y)) end

    -- The callout: on the switch icon when it shows
    local c = _ov._callout
    local vb = exOn and EX.ViewButton and EX.ViewButton()
    local show = vb and vb:IsShown()
    for _, r in ipairs({ c.glow, c.icon, c.arrow }) do r:SetShown(show and true or false) end
    c.box:SetShown(show and true or false)
    if not show then return end
    local s = vb:GetWidth()
    c.icon:ClearAllPoints()
    c.icon:SetAllPoints(vb)
    if vb._tx then
        c.icon:SetTexture(vb._tx:GetTexture())
        c.icon:SetVertexColor(vb._tx:GetVertexColor())
    end
    c.glow:ClearAllPoints()
    c.glow:SetPoint("CENTER", vb, "CENTER")
    c.glow:SetSize(s + 18, s + 18)
    c.arrow:ClearAllPoints()
    c.arrow:SetPoint("TOP", vb, "BOTTOM", 2, -4)
    c.box:ClearAllPoints()
    c.box:SetPoint("TOPLEFT", c.arrow, "BOTTOMRIGHT", -14, 12)
    c.box:SetHeight(math.ceil(c.text:GetStringHeight() or 0) + 20)
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
    ov._callout = BuildCallout(ov)
    BNB.AttachEscClose(ov, function() Finish(false) end)
    ov:SetScript("OnShow", function() Layout() end)
    -- Next frame: Layout sets text widths, never inside OnSizeChanged's pass
    mf:HookScript("OnSizeChanged", function()
        if _ov and _ov:IsShown() then BNB.Debounce("bnbWelcomeLayout", 0, Layout) end
    end)
    ov:Hide()
    return ov
end

-- ── Show / answer ───────────────────────────────────────────────────────────
Finish = function(useList)
    if not _open then return end
    _open = false
    local db = BigNoteBoxDB
    if db then
        db.welcomeSeen = WELCOME_RELEASE
        db.explorerIntroSeen = nil   -- the 2.0 beta's flag, before ALL-617
        -- The list becomes the view the window opens on (Settings > Modules)
        if useList then db.explorerDefault = "list" end
    end
    if useList and EX.SetActive then EX.SetActive(false) end
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

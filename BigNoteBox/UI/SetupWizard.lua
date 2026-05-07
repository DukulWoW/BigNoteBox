-- BigNoteBox UI/SetupWizard.lua
-- First-time setup wizard. 6 pages:
--   1: Welcome
--   2: Skin mode choice (normal vs skin) — may reload into page 3
--   3: Skin colour / brightness (skin mode only)
--   4: Notes behaviour (font, list mode, sidebar, combat, LSM)
--   5: Keybinds
--   6: Done
--
-- DB flags:
--   BigNoteBoxDB.setupComplete  (bool)   — wizard has been finished
--   BigNoteBoxDB.setupPage      (number) — resume page after reload
--
-- Entry point: BNB.ShowSetupWizard()
-- Called from Initialize.lua after all systems are built.

local BNB = BigNoteBox
local L   = BNB.L

--------------------------------------------------------------------------------
-- CONSTANTS
--------------------------------------------------------------------------------
local ASSETS    = "Interface\\AddOns\\BigNoteBox\\Assets\\"
local BTNS      = ASSETS .. "Buttons\\"
local WIN_W     = 480
local WIN_H     = 500
local PAD       = 20
local CW        = WIN_W - PAD * 2        -- content width
local TITLE_H   = 28
local NAV_H     = 44                     -- bottom nav bar height
local BNB_URL   = "https://www.curseforge.com/wow/addons/bignotebox"

local NUM_PAGES = 7

-- Whether any migratable note addons are installed (evaluated once at build time)
local _hasMigration = false
local GLOW_KEY  = "bnb_setup_wizard"

-- ── Setup wizard glow tuning ─────────────────────────────────────────────────
-- AutoCastGlow_Start(frame, color, N, frequency, scale, xOff, yOff, key, level)
--   N         : number of particles orbiting the frame border
--   frequency : animation speed — LOWER = slower rotation (0.1 = very slow)
--   scale     : size of each particle — HIGHER = bigger dots
local GLOW_N         = 12    -- particles around the border
local GLOW_FREQUENCY = 0.03  -- slow, stately rotation
local GLOW_SCALE     = 1.3   -- larger dots

--------------------------------------------------------------------------------
-- MODULE STATE
--------------------------------------------------------------------------------
local _frame       = nil
local _overlay     = nil
local _pages       = {}
local _curPage     = 1
local _lcg         = nil
local _skinChoice  = nil   -- "normal" or "skin", set on page 2
local _pageTitle   = nil
local _pageCounter = nil
local _prevBtn     = nil
local _nextBtn     = nil

local function GetLCG()
    if not _lcg then
        _lcg = LibStub and LibStub("LibCustomGlow-1.0", true)
    end
    return _lcg
end

--------------------------------------------------------------------------------
-- FADE HELPER
--------------------------------------------------------------------------------
local function FadeTo(target, fromAlpha, toAlpha, duration, onDone)
    local elapsed = 0
    target:SetAlpha(fromAlpha)
    target:SetScript("OnUpdate", function(self, dt)
        elapsed = elapsed + dt
        local t = math.min(elapsed / duration, 1)
        self:SetAlpha(fromAlpha + (toAlpha - fromAlpha) * t)
        if t >= 1 then
            self:SetScript("OnUpdate", nil)
            if onDone then onDone() end
        end
    end)
end

--------------------------------------------------------------------------------
-- LARGE BUTTON FACTORY  (matches OptionsPanel.lua's SharedButtonLargeTemplate)
-- Used for primary CTA buttons: Get Started, Finish, Finish & Open.
--------------------------------------------------------------------------------
local _largeBtnTpl
local function GetLargeBtnTpl()
    if _largeBtnTpl then return _largeBtnTpl end
    local candidates = {
        "SharedButtonLargeTemplate",
        "UIPanelDynamicResizeButtonTemplate",
        "UIPanelButtonTemplate",
    }
    for _, tpl in ipairs(candidates) do
        if not C_XMLUtil or not C_XMLUtil.GetTemplateInfo
                or C_XMLUtil.GetTemplateInfo(tpl) then
            _largeBtnTpl = tpl
            return tpl
        end
    end
    _largeBtnTpl = "UIPanelButtonTemplate"
    return _largeBtnTpl
end

local function MakeLargeButton(parent, text, w, h)
    local btn = CreateFrame("Button", nil, parent, GetLargeBtnTpl())
    btn:SetSize(w or 220, h or 50)
    btn:SetText(text or "")
    pcall(function() DynamicResizeButton_Resize(btn) end)
    if btn.GetFontString then
        local bfs = btn:GetFontString()
        if bfs then pcall(function() bfs:SetFont("Fonts\\FRIZQT__.TTF", 16, "") end) end
    end
    return btn
end
--------------------------------------------------------------------------------
local function GetOverlayColor()
    local db = BigNoteBoxDB
    if db and db.skinMode and BNB.GetSkinPreset and BNB.SkinColourOf then
        local p = BNB.GetSkinPreset()
        local r, g, b = BNB.SkinColourOf(p, false)
        return r, g, b, 0.82
    end
    return 0, 0, 0, 0.82
end

local function GetOverlay()
    if _overlay then return _overlay end
    local ov = CreateFrame("Frame", nil, WorldFrame)
    ov:SetAllPoints(UIParent)
    ov:SetFrameStrata("FULLSCREEN")
    ov:SetFrameLevel(1)
    ov:EnableMouse(false)
    local tex = ov:CreateTexture(nil, "BACKGROUND")
    tex:SetAllPoints()
    local r, g, b, a = GetOverlayColor()
    tex:SetColorTexture(r, g, b, a)
    ov._tex = tex
    ov:SetAlpha(0)
    ov:Hide()
    -- Combat: hide overlay immediately
    local ef = CreateFrame("Frame")
    ef:RegisterEvent("PLAYER_REGEN_DISABLED")
    ef:SetScript("OnEvent", function()
        if ov:IsShown() then ov:Hide() end
    end)
    _overlay = ov
    return ov
end

local function RefreshOverlayColor()
    if not _overlay then return end
    local r, g, b, a = GetOverlayColor()
    _overlay._tex:SetColorTexture(r, g, b, a)
end

local function ShowOverlay()
    local ov = GetOverlay()
    RefreshOverlayColor()
    ov:Show()
    FadeTo(ov, 0, 1, 0.5)
end

local function HideOverlay()
    if not _overlay or not _overlay:IsShown() then return end
    local ov = _overlay
    FadeTo(ov, ov:GetAlpha(), 0, 0.4, function() ov:Hide() end)
end

--------------------------------------------------------------------------------
-- GLOW
--------------------------------------------------------------------------------
local function StartGlow()
    local lcg = GetLCG()
    if not lcg or not _frame then return end
    local r, g, b = 1, 1, 1
    local db = BigNoteBoxDB
    if db and db.skinMode and BNB.GetSkinPreset and BNB.SkinBorderOf then
        local p = BNB.GetSkinPreset()
        r, g, b = BNB.SkinBorderOf(p)
    end
    pcall(lcg.AutoCastGlow_Start, _frame, {r, g, b, 0.85}, GLOW_N, GLOW_FREQUENCY, GLOW_SCALE,
          nil, nil, GLOW_KEY)
end

local function StopGlow()
    local lcg = GetLCG()
    if not lcg or not _frame then return end
    pcall(lcg.AutoCastGlow_Stop, _frame, GLOW_KEY)
end

local function RefreshGlow()
    StopGlow()
    StartGlow()
end

--------------------------------------------------------------------------------
-- CAMERA
--------------------------------------------------------------------------------
local function StartCamera()
    if BNB.FocusOrbit and BNB.FocusOrbit.StartForSetup then
        BNB.FocusOrbit.StartForSetup()
    end
end

local function StopCamera()
    if BNB.FocusOrbit and BNB.FocusOrbit.StopForSetup then
        BNB.FocusOrbit.StopForSetup()
    end
end

--------------------------------------------------------------------------------
-- QUIT DIALOG
--------------------------------------------------------------------------------
local function RegisterQuitDialog()
    if StaticPopupDialogs["BNB_QUIT_SETUP"] then return end
    StaticPopupDialogs["BNB_QUIT_SETUP"] = {
        text    = "Are you sure you want to quit setup?\n\nBigNoteBox will use its default settings.",
        button1 = "Quit setup",
        button2 = "Keep going",
        timeout = 0, whileDead = true, hideOnEscape = true,
        OnAccept = function()
            local db = BigNoteBoxDB
            if db then db.setupComplete = true; db.setupPage = nil end
            if _frame then
                _frame._quitting = true
                _frame:Hide()
            end
            HideOverlay()
            StopCamera()
            StopGlow()
        end,
    }
end

--------------------------------------------------------------------------------
-- NAVIGATION
--------------------------------------------------------------------------------
local PAGE_TITLES = {
    "Welcome to BigNoteBox!",
    "Choose your style",
    "Choose your theme",
    "Notes & behaviour",
    "Keybindings",
    "Bring your notes along",
    "All done!",
}

local function UpdateNavigation()
    if not _frame then return end
    _pageTitle:SetText(PAGE_TITLES[_curPage] or "")

    -- Effective total: skip page 6 if no migration addons
    local effectiveTotal = _hasMigration and NUM_PAGES or (NUM_PAGES - 1)
    -- Effective current: pages after skipped page 6 count one less for display
    local effectiveCur = _curPage
    if not _hasMigration and _curPage >= 6 then
        effectiveCur = _curPage - 1
    end
    _pageCounter:SetText(effectiveCur .. " / " .. effectiveTotal)

    for i, pg in ipairs(_pages) do
        if i == _curPage then pg:Show() else pg:Hide() end
    end

    -- Page 1: hide prev/next, show Get Started button instead
    _prevBtn:SetShown(_curPage > 1)
    _nextBtn:SetShown(_curPage > 1 and _curPage < NUM_PAGES)
end

local function GoToPage(n)
    _curPage = math.max(1, math.min(n, NUM_PAGES))
    UpdateNavigation()
end

--------------------------------------------------------------------------------
-- SHARED HELPERS
--------------------------------------------------------------------------------
local function MakeLabel(parent, y, text, fontSize, r, g, b)
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    fs:SetPoint("TOPLEFT",  parent, "TOPLEFT",  0, y)
    fs:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, y)
    fs:SetJustifyH("LEFT")
    fs:SetWordWrap(true)
    if fontSize then pcall(function() fs:SetFont(STANDARD_TEXT_FONT, fontSize, "") end) end
    fs:SetTextColor(r or 0.88, g or 0.88, b or 0.88)
    fs:SetText(text)
    fs:SetHeight(fs:GetStringHeight() + 4)
    return fs, y - (fs:GetStringHeight() + 8)
end

local function MakeRule(parent, y)
    local t = parent:CreateTexture(nil, "ARTWORK")
    t:SetHeight(1)
    t:SetColorTexture(0.28, 0.28, 0.30, 1)
    t:SetPoint("TOPLEFT",  parent, "TOPLEFT",  0, y)
    t:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, y)
    return y - 10
end

local function MakeHeader(parent, y, text)
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    fs:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, y)
    fs:SetTextColor(1, 0.82, 0)
    fs:SetText(text)
    return y - 24
end

-- Dropdown helper (WowStyle1DropdownTemplate)
local function MakeDropdown(parent, y, w, setupMenu)
    local dd = CreateFrame("DropdownButton", nil, parent, "WowStyle1DropdownTemplate")
    dd:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, y)
    dd:SetWidth(w or CW)
    dd:SetToplevel(true)
    dd:SetupMenu(setupMenu)
    return dd, y - 36
end

-- Checkbox helper
local function MakeCheck(parent, y, text, getter, setter)
    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cb:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, y)
    cb:SetChecked(getter())
    cb.text = cb.text or cb:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    cb.text:SetPoint("LEFT", cb, "RIGHT", 2, 0)
    cb.text:SetText(text)
    cb:SetScript("OnClick", function(self) setter(self:GetChecked()) end)
    return cb, y - 30
end

-- Slim scroll frame for pages with lots of content
local function MakeScrollContent(parent)
    local sf = CreateFrame("ScrollFrame", nil, parent, "ScrollFrameTemplate")
    sf:SetPoint("TOPLEFT",     parent, "TOPLEFT",     0, 0)
    sf:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -16, 0)
    local bar = sf.ScrollBar
    if bar then bar:SetAlpha(0) end
    sf:HookScript("OnScrollRangeChanged", function(_, _, yRange)
        if bar then bar:SetAlpha((yRange or 0) > 2 and 1 or 0) end
    end)
    local ct = CreateFrame("Frame", nil, sf)
    ct:SetWidth(sf:GetWidth() > 0 and sf:GetWidth() or (CW - 16))
    ct:SetHeight(1)
    sf:SetScrollChild(ct)
    sf:HookScript("OnSizeChanged", function(self)
        local w = self:GetWidth()
        if w and w > 20 then ct:SetWidth(w) end
    end)
    return sf, ct
end

--------------------------------------------------------------------------------
-- PAGE 1 — WELCOME
--------------------------------------------------------------------------------
local function BuildPage1(content)
    local f = CreateFrame("Frame", nil, content)
    f:SetAllPoints()
    f:Hide()

    -- Logo
    local logo = f:CreateTexture(nil, "ARTWORK")
    logo:SetSize(96, 96)
    logo:SetPoint("TOP", f, "TOP", 0, -10)
    logo:SetTexture(ASSETS .. "logo-256")

    -- Addon name
    local name = f:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    name:SetPoint("TOP", logo, "BOTTOM", 0, -10)
    name:SetText("|cff66bb6aBigNoteBox|r")

    -- Version
    local ver = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    ver:SetPoint("TOP", name, "BOTTOM", 0, -4)
    ver:SetText("v" .. BNB.ADDON_VERSION)
    ver:SetTextColor(0.55, 0.55, 0.55)

    -- By Dukul
    local by = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    by:SetPoint("TOP", ver, "BOTTOM", 0, -2)
    by:SetText("by Dukul")
    by:SetTextColor(0.65, 0.65, 0.65)

    -- Welcome text
    local txt = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    txt:SetPoint("TOP", by, "BOTTOM", 0, -24)
    txt:SetWidth(CW - 20)
    txt:SetJustifyH("CENTER")
    txt:SetSpacing(3)
    txt:SetText(
        "Welcome! This quick setup will help you get BigNoteBox configured "..
        "just the way you like it.\n\nYou can always re-run this setup at any time "..
        "from the |cffff0000Danger Zone|r in \"Main Config > Advanced\".\n\n"..
        "If you don't complete setup, default values will be used.")
    txt:SetTextColor(0.88, 0.88, 0.88)

    -- Get Started button
    local startBtn = MakeLargeButton(f, "Get Started", 220, 50)
    startBtn:SetPoint("BOTTOM", f, "BOTTOM", 0, 30)
    startBtn:SetScript("OnClick", function() GoToPage(2) end)

    return f
end

--------------------------------------------------------------------------------
-- PAGE 2 — SKIN MODE CHOICE
--------------------------------------------------------------------------------
local function BuildPage2(content)
    local f = CreateFrame("Frame", nil, content)
    f:SetAllPoints()
    f:Hide()

    local y = -4
    local _, ny = MakeLabel(f, y,
        "Choose how BigNoteBox looks. You can change this later in Settings.",
        nil, 0.75, 0.75, 0.75)
    y = ny - 4

    -- Two image buttons side by side
    local IMG_W, IMG_H = 200, 125
    local GAP = CW - IMG_W * 2
    local _selected = (BigNoteBoxDB and BigNoteBoxDB.skinMode) and "skin" or "normal"

    local function MakeImageChoice(label, texPath, choiceKey, xOff)
        local btn = BNB.CreateBackdropFrame("Button", nil, f)
        btn:SetSize(IMG_W, IMG_H + 28)
        btn:SetPoint("TOPLEFT", f, "TOPLEFT", xOff, y)
        BNB.SetBackdrop(btn, 0.06, 0.06, 0.08, 0.95, 0.28, 0.28, 0.30, 1)
        btn:EnableMouse(true)

        local img = btn:CreateTexture(nil, "ARTWORK")
        img:SetPoint("TOPLEFT",  btn, "TOPLEFT",  2, -2)
        img:SetPoint("TOPRIGHT", btn, "TOPRIGHT", -2, -2)
        img:SetHeight(IMG_H)
        img:SetTexture(ASSETS .. "UI\\" .. texPath)

        local lbl = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        lbl:SetPoint("BOTTOM", btn, "BOTTOM", 0, 7)
        lbl:SetText(label)

        local function Highlight()
            if _selected == choiceKey then
                btn:SetBackdropColor(0.08, 0.18, 0.08, 0.95)
                btn:SetBackdropBorderColor(0.35, 0.80, 0.35, 1)
                lbl:SetTextColor(1, 0.82, 0)
            else
                btn:SetBackdropColor(0.06, 0.06, 0.08, 0.95)
                btn:SetBackdropBorderColor(0.28, 0.28, 0.30, 1)
                lbl:SetTextColor(0.85, 0.85, 0.85)
            end
        end
        Highlight()

        btn:SetScript("OnEnter", function()
            if _selected ~= choiceKey then
                btn:SetBackdropBorderColor(0.45, 0.65, 0.45, 1)
            end
        end)
        btn:SetScript("OnLeave", Highlight)
        btn:SetScript("OnClick", function()
            _selected = choiceKey
            f._normalBtn._hl()
            f._skinBtn._hl()
        end)
        btn._hl = Highlight
        return btn
    end

    local normalBtn = MakeImageChoice("Normal Mode",  "setup-normal", "normal", 0)
    local skinBtn   = MakeImageChoice("Skin Mode",    "setup-skin",   "skin",   IMG_W + GAP)
    f._normalBtn = normalBtn
    f._skinBtn   = skinBtn
    y = y - (IMG_H + 28 + 12)

    -- Explanation text
    local desc = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    desc:SetPoint("TOPLEFT",  f, "TOPLEFT",  0, y)
    desc:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, y)
    desc:SetJustifyH("LEFT"); desc:SetWordWrap(true); desc:SetSpacing(2)
    desc:SetText(
        "|cffffd100Normal Mode:|r Classic WoW window style that fits perfectly with the default UI.\n\n"..
        "|cffffd100Skin Mode:|r A custom themed skin with coloured accents and its own style. Allows you to choose a color and brightness.")
    desc:SetTextColor(0.75, 0.75, 0.75)

    -- Store getter for Next handler
    f.GetChoice = function() return _selected end

    -- Wire Next button override: page 2 may reload
    f.OnNext = function()
        local db = BigNoteBoxDB
        if not db then return end
        local choice = _selected
        if choice == "skin" then
            db.skinMode  = true
            db.setupPage = 3
            db.setupComplete = false
            C_UI.Reload()
        else
            db.skinMode  = false
            db.setupPage = 4
            -- No reload — jump straight to page 4
            GoToPage(4)
        end
    end

    return f
end

--------------------------------------------------------------------------------
-- PAGE 3 — SKIN COLOUR / BRIGHTNESS  (skin mode only)
--------------------------------------------------------------------------------
local function BuildPage3(content)
    local f = CreateFrame("Frame", nil, content)
    f:SetAllPoints()
    f:Hide()

    local sf, ct = MakeScrollContent(f)
    local y = -4

    y = MakeHeader(ct, y, "Theme colour")
    local _, ny = MakeLabel(ct, y,
        "Choose a colour preset for the skin. You can change this at any time in Settings > Appearance.",
        nil, 0.65, 0.65, 0.65)
    y = ny

    -- Preset dropdown
    local PRESET_ORDER = {
        "obsidian", "void", "dragonfire", "arcane", "fel",
        "titan", "icecrown", "holy", "azshara", "ragnaros",
        "earthen", "argent", "oled",
    }
    local PRESET_LABELS = {
        obsidian   = "Obsidian",   void     = "Void",       dragonfire = "Dragonfire",
        arcane     = "Arcane",     fel      = "Fel",         titan      = "Titan",
        icecrown   = "Icecrown",   holy     = "Holy",        azshara    = "Azshara",
        ragnaros   = "Ragnaros",   earthen  = "Earthen",    argent     = "Argent",
        oled       = "OLED (pure black)",
    }
    local dd, ddy = MakeDropdown(ct, y, CW - 16, function(_, root)
        local cur = (BigNoteBoxDB and BigNoteBoxDB.skinPreset) or "obsidian"
        for _, key in ipairs(PRESET_ORDER) do
            local k = key
            root:CreateRadio(PRESET_LABELS[k] or k,
                function() return cur == k end,
                function()
                    cur = k
                    if BigNoteBoxDB then BigNoteBoxDB.skinPreset = k end
                    if BNB.ApplyMainWindowSkin then BNB.ApplyMainWindowSkin() end
                    RefreshOverlayColor()
                    RefreshGlow()
                    if dd and dd.GenerateMenu then dd:GenerateMenu() end
                end)
        end
    end)
    y = ddy - 4

    y = MakeRule(ct, y)
    y = MakeHeader(ct, y, "Brightness")
    local _, ny2 = MakeLabel(ct, y,
        "Adjusts how bright or dark the skin appears.",
        nil, 0.65, 0.65, 0.65)
    y = ny2

    -- Brightness slider — float 0.5–3.0, step 0.05, default 1.0
    -- Matches main config → Appearance → Skins → Skin brightness exactly.
    local curBrt = (BigNoteBoxDB and BigNoteBoxDB.skinBrightness) or 1.0
    local sl = BNB.CreateFloatSlider(ct, "Brightness", 0.5, 3.0, curBrt, 0.05, 1.0,
        function(v)
            if BigNoteBoxDB then BigNoteBoxDB.skinBrightness = v end
            if BNB.ApplyMainWindowSkin then BNB.ApplyMainWindowSkin() end
            RefreshOverlayColor()
        end,
        function(v) return string.format("%.2f", v) end)
    sl:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
    sl:SetWidth(CW - 36)
    y = y - 44

    y = MakeRule(ct, y)
    y = MakeHeader(ct, y, "Random theme")

    local _, cb = MakeCheck(ct, y,
        "Randomize theme on login / reload",
        function() return BigNoteBoxDB and BigNoteBoxDB.skinRandomize == true end,
        function(v) if BigNoteBoxDB then BigNoteBoxDB.skinRandomize = v end end)
    y = y - 32

    local _, ny3 = MakeLabel(ct, y,
        "Picks a random colour preset each time you log in or reload.",
        nil, 0.55, 0.55, 0.55)
    y = ny3

    ct:SetHeight(math.abs(y) + PAD)
    return f
end

--------------------------------------------------------------------------------
-- PAGE 4 — NOTES BEHAVIOUR
--------------------------------------------------------------------------------
local function BuildPage4(content)
    local f = CreateFrame("Frame", nil, content)
    f:SetAllPoints()
    f:Hide()

    local sf, ct = MakeScrollContent(f)
    local y = -4

    -- ── Font picker ──────────────────────────────────────────────────────────
    y = MakeHeader(ct, y, "Note font")
    local _, ny = MakeLabel(ct, y,
        "Applies to the note editor and normal note display.",
        nil, 0.65, 0.65, 0.65)
    y = ny

    -- Upvalue: live preview label, shared by font cards and size slider
    local _p4PreviewLbl = nil

    do
        local PICKER_H = 48
        local GAP_V    = 4
        local COL_GAP  = 6
        local CARD_W   = math.floor((CW - 16 - COL_GAP) / 2)
        local _allFonts = BNB.FONTS or {}
        local fonts = {}
        for _, def in ipairs(_allFonts) do
            if not def._isLSM then fonts[#fonts + 1] = def end
        end
        local _cards = {}

        local function HighlightCards()
            local cur = BigNoteBoxDB and BigNoteBoxDB.fontChoice or "notoserif"
            for _, e in ipairs(_cards) do
                if e.id == cur then
                    e.btn:SetBackdropColor(0.08, 0.18, 0.08, 0.95)
                    e.btn:SetBackdropBorderColor(0.35, 0.75, 0.35, 1)
                    if e.nameLbl then e.nameLbl:SetTextColor(1, 0.82, 0, 1) end
                else
                    e.btn:SetBackdropColor(0.06, 0.06, 0.08, 0.95)
                    e.btn:SetBackdropBorderColor(0.28, 0.28, 0.30, 1)
                    if e.nameLbl then e.nameLbl:SetTextColor(0.85, 0.85, 0.85, 1) end
                end
            end
        end

        for i, def in ipairs(fonts) do
            local col     = (i - 1) % 2
            local gridRow = math.floor((i - 1) / 2)
            local xOff    = col * (CARD_W + COL_GAP)
            local yOff    = y - gridRow * (PICKER_H + GAP_V)

            local btn = BNB.CreateBackdropFrame("Button", nil, ct)
            BNB.SetBackdrop(btn, 0.06, 0.06, 0.08, 0.95, 0.28, 0.28, 0.30, 1)
            btn:SetSize(CARD_W, PICKER_H)
            btn:SetPoint("TOPLEFT", ct, "TOPLEFT", xOff, yOff)
            btn:EnableMouse(true)

            local d = def
            btn:SetScript("OnEnter", function(self)
                local cur = BigNoteBoxDB and BigNoteBoxDB.fontChoice or "notoserif"
                if cur ~= d.id then
                    self:SetBackdropBorderColor(0.35, 0.55, 0.35, 1)
                end
            end)
            btn:SetScript("OnLeave", HighlightCards)
            btn:SetScript("OnClick", function()
                BNB.ApplyFont(d.id, nil)
                HighlightCards()
                -- Update preview to selected font
                if _p4PreviewLbl then
                    local sz = (BigNoteBoxDB and BigNoteBoxDB.fontSize) or 13
                    if d.bold and d.bold ~= "" then
                        pcall(function() _p4PreviewLbl:SetFont(d.bold, sz, "") end)
                    elseif d.regular and d.regular ~= "" then
                        pcall(function() _p4PreviewLbl:SetFont(d.regular, sz, "") end)
                    end
                end
            end)

            local nameLbl = btn:CreateFontString(nil, "OVERLAY")
            nameLbl:SetPoint("TOPLEFT",  btn, "TOPLEFT",  7, -7)
            nameLbl:SetPoint("TOPRIGHT", btn, "TOPRIGHT", -7, -7)
            nameLbl:SetJustifyH("LEFT"); nameLbl:SetHeight(18)
            if def.bold and def.bold ~= "" then
                pcall(function() nameLbl:SetFont(def.bold, 13, "") end)
            else nameLbl:SetFontObject("GameFontNormal") end
            nameLbl:SetText(def.label)

            local prevLbl = btn:CreateFontString(nil, "OVERLAY")
            prevLbl:SetPoint("BOTTOMLEFT",  btn, "BOTTOMLEFT",  7, 7)
            prevLbl:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -7, 7)
            prevLbl:SetJustifyH("LEFT"); prevLbl:SetHeight(14)
            if def.regular and def.regular ~= "" then
                pcall(function() prevLbl:SetFont(def.regular, 11, "") end)
            else prevLbl:SetFontObject("GameFontNormalSmall") end
            prevLbl:SetTextColor(0.62, 0.62, 0.62)
            prevLbl:SetText(def.preview or "")

            _cards[#_cards + 1] = { btn=btn, id=def.id, nameLbl=nameLbl, prevLbl=prevLbl }
        end

        local gridRows = math.ceil(#fonts / 2)
        y = y - gridRows * (PICKER_H + GAP_V) - 8
        -- Deferred highlight (fonts may not be initialised yet on first frame)
        C_Timer.After(0.05, HighlightCards)
    end

    -- Font size slider
    local fssl = BNB.CreateSlider(ct, "Font size", 9, 22,
        (BigNoteBoxDB and BigNoteBoxDB.fontSize) or 13,
        13,
        function(v)
            BNB.ApplyFont(nil, math.floor(v))
            -- Update preview size in real time
            if _p4PreviewLbl then
                local sz       = math.floor(v)
                local boldPath = BNB.GetBoldFont and BNB.GetBoldFont()
                if boldPath and boldPath ~= "" then
                    pcall(function() _p4PreviewLbl:SetFont(boldPath, sz, "") end)
                end
            end
        end,
        function(v) return math.floor(v) .. "pt" end)
    fssl:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
    fssl:SetWidth(CW - 36)
    y = y - 44

    -- Font preview box — "Azeroth awaits!" rendered live in selected font + size
    local previewBox = BNB.CreateBackdropFrame("Frame", nil, ct)
    previewBox:SetSize(CW - 16, 38)
    previewBox:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
    BNB.SetBackdrop(previewBox, 0.04, 0.04, 0.06, 0.95, 0.22, 0.22, 0.25, 1)

    local previewLbl = previewBox:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    previewLbl:SetPoint("LEFT",  previewBox, "LEFT",  10, 0)
    previewLbl:SetPoint("RIGHT", previewBox, "RIGHT", -10, 0)
    previewLbl:SetJustifyH("CENTER")
    previewLbl:SetTextColor(0.75, 0.75, 0.75, 1)
    previewLbl:SetText("Azeroth awaits!")
    -- Initialise font once BNB fonts are ready
    C_Timer.After(0.05, function()
        local sz       = (BigNoteBoxDB and BigNoteBoxDB.fontSize) or 13
        local boldPath = BNB.GetBoldFont and BNB.GetBoldFont()
        if boldPath and boldPath ~= "" then
            pcall(function() previewLbl:SetFont(boldPath, sz, "") end)
        end
    end)
    _p4PreviewLbl = previewLbl
    y = y - 46

    -- ── List display mode ────────────────────────────────────────────────────
    y = MakeRule(ct, y)
    y = MakeHeader(ct, y, "Note list display")

    local _, ny3 = MakeLabel(ct, y,
        "Controls how notes appear in the list.",
        nil, 0.65, 0.65, 0.65)
    y = ny3

    local MODE_ITEMS = {
        { key="normal",   label="Normal",   icon=32, preview="2 preview lines" },
        { key="compact",  label="Compact",  icon=16, preview="No preview" },
        { key="spacious", label="Spacious", icon=42, preview="3 preview lines" },
    }
    local MODE_BTN_W = math.floor((CW - 16 - 8) / 3)
    local _modeBtns  = {}

    local function HighlightModes()
        local cur = (BigNoteBoxDB and BigNoteBoxDB.listEntryHeight) or "normal"
        for _, e in ipairs(_modeBtns) do
            if e.key == cur then
                e.btn:SetBackdropColor(0.08, 0.18, 0.08, 0.95)
                e.btn:SetBackdropBorderColor(0.35, 0.75, 0.35, 1)
                if e.lbl then e.lbl:SetTextColor(1, 0.82, 0, 1) end
            else
                e.btn:SetBackdropColor(0.06, 0.06, 0.08, 0.95)
                e.btn:SetBackdropBorderColor(0.28, 0.28, 0.30, 1)
                if e.lbl then e.lbl:SetTextColor(0.85, 0.85, 0.85, 1) end
            end
        end
    end

    local MODE_BTN_H = 52
    for mi, m in ipairs(MODE_ITEMS) do
        local xOff = (mi - 1) * (MODE_BTN_W + 4)
        local btn = BNB.CreateBackdropFrame("Button", nil, ct)
        btn:SetSize(MODE_BTN_W, MODE_BTN_H)
        btn:SetPoint("TOPLEFT", ct, "TOPLEFT", xOff, y)
        BNB.SetBackdrop(btn, 0.06, 0.06, 0.08, 0.95, 0.28, 0.28, 0.30, 1)
        btn:EnableMouse(true)

        -- Mock icon
        local iconSz = m.icon
        local iconTex = btn:CreateTexture(nil, "ARTWORK")
        iconTex:SetSize(iconSz, iconSz)
        iconTex:SetPoint("LEFT", btn, "LEFT", 8, 0)
        iconTex:SetTexture(ASSETS .. "Icons\\Notes\\INV_Misc_Note_01")
        iconTex:SetTexCoord(0, 1, 0, 1)

        -- Label
        local lbl = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        lbl:SetPoint("TOPLEFT",  btn, "TOPLEFT",  8 + iconSz + 6, -8)
        lbl:SetPoint("TOPRIGHT", btn, "TOPRIGHT", -4, -8)
        lbl:SetJustifyH("LEFT")
        lbl:SetText(m.label)

        local sub = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        sub:SetPoint("TOPLEFT", lbl, "BOTTOMLEFT", 0, -2)
        sub:SetPoint("TOPRIGHT", btn, "TOPRIGHT", -4, 0)
        sub:SetJustifyH("LEFT")
        sub:SetText(m.preview)
        sub:SetTextColor(0.55, 0.55, 0.55)

        local mk = m.key
        btn:SetScript("OnEnter", function(self)
            local cur = (BigNoteBoxDB and BigNoteBoxDB.listEntryHeight) or "normal"
            if cur ~= mk then self:SetBackdropBorderColor(0.45, 0.65, 0.45, 1) end
        end)
        btn:SetScript("OnLeave", HighlightModes)
        btn:SetScript("OnClick", function()
            if BigNoteBoxDB then BigNoteBoxDB.listEntryHeight = mk end
            if BNB.ApplyListMode   then BNB.ApplyListMode()   end
            if BNB.RefreshNoteList then BNB.RefreshNoteList() end
            HighlightModes()
        end)

        _modeBtns[#_modeBtns + 1] = { btn=btn, key=mk, lbl=lbl }
    end
    y = y - (MODE_BTN_H + 10)
    C_Timer.After(0.05, HighlightModes)

    -- ── Sidebar placement ────────────────────────────────────────────────────
    y = MakeRule(ct, y)
    y = MakeHeader(ct, y, "Character sidebar placement")

    local sideDD, sideY = MakeDropdown(ct, y, CW - 16, function(_, root)
        local cur = (BigNoteBoxDB and BigNoteBoxDB.sidebarSide) or "right"
        local items = {
            { key="right", label="Right (default)" },
            { key="left",  label="Left" },
        }
        for _, item in ipairs(items) do
            local k = item.key
            root:CreateRadio(item.label,
                function() return cur == k end,
                function()
                    cur = k
                    if BigNoteBoxDB then BigNoteBoxDB.sidebarSide = k end
                    if BNB.Sidebar and BNB.Sidebar.Refresh then BNB.Sidebar.Refresh() end
                    if sideDD and sideDD.GenerateMenu then sideDD:GenerateMenu() end
                end)
        end
    end)
    y = sideY - 4

    -- ── Combat behaviour ────────────────────────────────────────────────────
    y = MakeRule(ct, y)
    y = MakeHeader(ct, y, "When entering combat")

    local combatDD, combatY = MakeDropdown(ct, y, CW - 16, function(_, root)
        local cur = (BigNoteBoxDB and BigNoteBoxDB.combatAction) or "nothing"
        local items = {
            { key="nothing",          label="Do nothing" },
            { key="hide_no_stickies", label="Hide everything except sticky notes" },
            { key="hide_minimize",    label="Hide everything, minimize sticky notes" },
            { key="hide_all",         label="Hide everything" },
        }
        for _, item in ipairs(items) do
            local k = item.key
            root:CreateRadio(item.label,
                function() return cur == k end,
                function()
                    cur = k
                    if BigNoteBoxDB then BigNoteBoxDB.combatAction = k end
                    if combatDD and combatDD.GenerateMenu then combatDD:GenerateMenu() end
                end)
        end
    end)
    y = combatY - 4

    -- ── LSM fonts ───────────────────────────────────────────────────────────
    local lsmAvail = LibStub and LibStub("LibSharedMedia-3.0", true) ~= nil
    if lsmAvail then
        y = MakeRule(ct, y)
        y = MakeHeader(ct, y, "LibSharedMedia fonts")

        local _, ny4 = MakeLabel(ct, y,
            "Enable access to fonts registered by other addons via LibSharedMedia-3.0. "..
            "This will take effect after setup completes and the UI reloads.",
            nil, 0.65, 0.65, 0.65)
        y = ny4

        local _, cb = MakeCheck(ct, y,
            "Enable LibSharedMedia fonts",
            function() return BigNoteBoxDB and BigNoteBoxDB.lsmFonts == true end,
            function(v) if BigNoteBoxDB then BigNoteBoxDB.lsmFonts = v end end)
        y = y - 32
    end

    ct:SetHeight(math.abs(y) + PAD)
    return f
end

--------------------------------------------------------------------------------
-- PAGE 5 — KEYBINDS
--------------------------------------------------------------------------------
local function BuildPage5(content)
    local f = CreateFrame("Frame", nil, content)
    f:SetAllPoints()
    f:Hide()

    local sf, ct = MakeScrollContent(f)
    local y = -4

    local _, ny = MakeLabel(ct, y,
        "Set your keybindings for BigNoteBox. Left-click a button to capture a key. "..
        "Right-click to unbind.",
        nil, 0.75, 0.75, 0.75)
    y = ny - 4

    local _KB_MODS = {
        LSHIFT=true, RSHIFT=true, LCTRL=true, RCTRL=true, LALT=true, RALT=true,
    }
    local KEYBINDS = {
        { action="BIGNOTEBOXOPEN",         label="Open BigNoteBox",         hint="Default: CTRL-N" },
        { action="BIGNOTEBOXQUICKNOTE",    label="Create quick note",        hint="Default: none" },
        { action="BIGNOTEBOXNEWNOTE",      label="Create new note",          hint="Default: none" },
        { action="BIGNOTEBOXHIDESTICKIES", label="Show / hide sticky notes", hint="Default: CTRL-H" },
        { action="BIGNOTEBOXTOGGLERV",     label="Open rich note editor",    hint="Default: none" },
    }

    -- Register conflict popup once
    if not StaticPopupDialogs["BNB_KEYBIND_CONFLICT"] then
        StaticPopupDialogs["BNB_KEYBIND_CONFLICT"] = {
            text = "%s", button1 = YES, button2 = NO,
            timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
            OnAccept = function(_, data)
                if data and data.applyFn then data.applyFn(data.fullKey) end
            end,
        }
    end

    local _updateFns = {}

    local function MakeKBRow(parent, yp, entry)
        local ROW_H  = 28
        local BTN_W  = 140
        local HINT_W = 110
        local LBL_W  = CW - 16 - BTN_W - HINT_W - 8   -- remaining left side

        local lbl = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        lbl:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, yp)
        lbl:SetWidth(LBL_W)
        lbl:SetJustifyH("LEFT")
        lbl:SetText(entry.label)

        local kbBtn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
        kbBtn:SetSize(BTN_W, 22)
        kbBtn:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, yp)
        kbBtn:RegisterForClicks("AnyUp")

        local hint = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        hint:SetPoint("RIGHT", kbBtn, "LEFT", -6, 0)
        hint:SetWidth(HINT_W)
        hint:SetJustifyH("RIGHT")
        hint:SetTextColor(0.5, 0.5, 0.5)
        hint:SetText(entry.hint)

        local function UpdateText()
            local key = GetBindingKey(entry.action)
            kbBtn:SetText(key and GetBindingText(key) or L["KEYBIND_NOT_BOUND"])
        end
        UpdateText()
        _updateFns[#_updateFns + 1] = UpdateText

        local function StopCapture(btn)
            btn:EnableKeyboard(false)
            btn:SetScript("OnKeyDown", nil)
            btn:SetPropagateKeyboardInput(true)
            UpdateText()
        end

        local function ApplyBind(fullKey)
            local k1, k2 = GetBindingKey(entry.action)
            if k1 then SetBinding(k1, nil) end
            if k2 then SetBinding(k2, nil) end
            SetBinding(fullKey, entry.action)
            SaveBindings(GetCurrentBindingSet())
            UpdateText()
        end

        local function OnKeyCaptured(btn, key)
            if _KB_MODS[key] then return end
            btn:SetPropagateKeyboardInput(false)
            if key == "ESCAPE" or InCombatLockdown() then StopCapture(btn); return end
            local mods = {}
            if IsAltKeyDown()     then mods[#mods+1] = "ALT"   end
            if IsControlKeyDown() then mods[#mods+1] = "CTRL"  end
            if IsShiftKeyDown()   then mods[#mods+1] = "SHIFT" end
            mods[#mods+1] = key
            local fullKey = table.concat(mods, "-")
            StopCapture(btn)
            local existing = GetBindingAction(fullKey)
            if existing and existing ~= "" and existing ~= entry.action then
                local msg = string.format(L["KEYBIND_CONFLICT"],
                    GetBindingText(fullKey), GetBindingName(existing))
                StaticPopup_Show("BNB_KEYBIND_CONFLICT", msg, nil,
                    { fullKey=fullKey, applyFn=ApplyBind })
                return
            end
            ApplyBind(fullKey)
        end

        kbBtn:SetScript("OnClick", function(btn, button)
            if button == "RightButton" then
                local k1, k2 = GetBindingKey(entry.action)
                if k1 then SetBinding(k1, nil) end
                if k2 then SetBinding(k2, nil) end
                if k1 or k2 then SaveBindings(GetCurrentBindingSet()) end
                UpdateText()
            else
                btn:SetText(L["KEYBIND_PRESS_KEY"])
                btn:EnableKeyboard(true)
                btn:SetPropagateKeyboardInput(false)
                btn:SetScript("OnKeyDown", OnKeyCaptured)
            end
        end)

        kbBtn:SetScript("OnEnter", function(btn)
            GameTooltip:SetOwner(btn, "ANCHOR_RIGHT")
            local key = GetBindingKey(entry.action)
            if key then
                GameTooltip:AddLine(GetBindingText(key), 1, 1, 1)
                GameTooltip:AddLine(L["KEYBIND_TOOLTIP_UNBIND"], 0.6, 0.6, 0.6)
            else
                GameTooltip:AddLine(L["KEYBIND_TOOLTIP_SET"], 1, 1, 1)
            end
            GameTooltip:Show()
        end)
        kbBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

        return yp - (ROW_H + 4)
    end

    for _, entry in ipairs(KEYBINDS) do
        y = MakeKBRow(ct, y, entry)
        local t = ct:CreateTexture(nil, "ARTWORK")
        t:SetHeight(1); t:SetColorTexture(0.22, 0.22, 0.24, 1)
        t:SetPoint("TOPLEFT",  ct, "TOPLEFT",  0, y + 2)
        t:SetPoint("TOPRIGHT", ct, "TOPRIGHT", 0, y + 2)
        y = y - 6
    end

    -- Register for UPDATE_BINDINGS
    ct:RegisterEvent("UPDATE_BINDINGS")
    ct:SetScript("OnEvent", function(_, event)
        if event == "UPDATE_BINDINGS" then
            for _, fn in ipairs(_updateFns) do fn() end
        end
    end)

    ct:SetHeight(math.abs(y) + PAD)
    return f
end

--------------------------------------------------------------------------------
-- PAGE 6 — MIGRATION NOTICE (conditional — only shown when migratable addons detected)
--------------------------------------------------------------------------------
local function BuildPage6(content)
    local f = CreateFrame("Frame", nil, content)
    f:SetAllPoints()
    f:Hide()

    local y = -8

    -- Detect which addons are present (use HasAny for existence, DetectAvailable for names)
    local detected = {}
    if BNB.Migration and BNB.Migration.ADDON_KEYS and BNB.Migration.ADDON_LOAD_NAME then
        for _, k in ipairs(BNB.Migration.ADDON_KEYS) do
            if C_AddOns.IsAddOnLoaded(BNB.Migration.ADDON_LOAD_NAME[k] or k) then
                detected[#detected + 1] = BNB.Migration.ADDON_NAMES[k] or k
            end
        end
    end

    local _, ny = MakeLabel(f, y,
        "BigNoteBox noticed you have other note addons installed:",
        nil, 0.88, 0.88, 0.88)
    y = ny - 2

    -- List detected addons
    for _, name in ipairs(detected) do
        local _, ay = MakeLabel(f, y, "|cff66bb6a* " .. name .. "|r", nil, 1, 1, 1)
        y = ay - 0
    end
    y = y - 10

    y = MakeRule(f, y)

    local _, ny2 = MakeLabel(f, y,
        "Once you finish setup, BigNoteBox will offer to bring your existing notes across. "..
        "It is a |cffffd100copy|r, not a move — your notes in other addons are never touched.",
        nil, 0.80, 0.80, 0.80)
    y = ny2 - 8

    local _, ny3 = MakeLabel(f, y,
        "You can also trigger migration at any time from |cffffd100Settings > Advanced > Migration|r.",
        nil, 0.60, 0.60, 0.60)
    y = ny3

    return f
end

--------------------------------------------------------------------------------
-- PAGE 7 — DONE
--------------------------------------------------------------------------------
local function BuildPage7(content)
    local f = CreateFrame("Frame", nil, content)
    f:SetAllPoints()
    f:Hide()

    local y = -10

    local thanks = f:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    thanks:SetPoint("TOP", f, "TOP", 0, y)
    thanks:SetWidth(CW); thanks:SetJustifyH("CENTER")
    thanks:SetText("|cff66bb6aThanks for installing BigNoteBox!|r")
    y = y - 40

    local tips = {
        "|cffffd100/bnb|r — open settings at any time.",
        "Right-click the minimap button for quick options.",
        "Drag items, spells, or quests onto a note to attach them.",
        "Found a bug or have a suggestion? Leave a comment on CurseForge!",
    }
    for _, tip in ipairs(tips) do
        local _, ny = MakeLabel(f, y, "|cff888888-|r " .. tip, nil, 0.80, 0.80, 0.80)
        y = ny - 2
    end

    y = y - 10
    -- CurseForge link
    local urlLbl = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    urlLbl:SetPoint("TOPLEFT",  f, "TOPLEFT",  0, y)
    urlLbl:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, y)
    urlLbl:SetJustifyH("CENTER")
    urlLbl:SetTextColor(0.50, 0.50, 0.50)
    urlLbl:SetText("CurseForge page — click the button below to copy the URL:")
    y = y - 20

    local cfBtn = BNB.CreateButton(nil, f, "Copy CurseForge URL", 200, 24)
    cfBtn:SetPoint("TOPLEFT", f, "TOPLEFT", math.floor((CW - 200) / 2), y)
    cfBtn:SetScript("OnClick", function()
        if BNB.ShowClipboardHint then
            BNB.ShowClipboardHint(BNB_URL, cfBtn, true)
        end
    end)
    y = y - 32

    -- Dukul.net link
    local siteLbl = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    siteLbl:SetPoint("TOPLEFT",  f, "TOPLEFT",  0, y)
    siteLbl:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, y)
    siteLbl:SetJustifyH("CENTER")
    siteLbl:SetTextColor(0.50, 0.50, 0.50)
    siteLbl:SetText("Check out my other addons at dukul.net:")
    y = y - 20

    local siteBtn = BNB.CreateButton(nil, f, "Copy dukul.net", 200, 24)
    siteBtn:SetPoint("TOPLEFT", f, "TOPLEFT", math.floor((CW - 200) / 2), y)
    siteBtn:SetScript("OnClick", function()
        if BNB.ShowClipboardHint then
            BNB.ShowClipboardHint("https://dukul.net", siteBtn, true)
        end
    end)
    y = y - 40

    -- Reload note
    local rnote = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    rnote:SetPoint("BOTTOMLEFT",  f, "BOTTOMLEFT",  0, 114)
    rnote:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 114)
    rnote:SetJustifyH("CENTER")
    rnote:SetTextColor(0.5, 0.5, 0.5)
    rnote:SetText("A reload is required to apply your settings.")

    -- Finish & Open BigNoteBox (top button)
    local foBtn = MakeLargeButton(f, "Finish & Open BigNoteBox", CW, 50)
    foBtn:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, 58)
    foBtn:SetScript("OnClick", function()
        local db = BigNoteBoxDB
        if db then
            db.setupComplete       = true
            db.setupPage           = nil
            db._openOnceAfterSetup = true
        end
        StopCamera(); StopGlow(); HideOverlay()
        C_UI.Reload()
    end)

    -- Finish (bottom button)
    local finBtn = MakeLargeButton(f, "Finish", CW, 50)
    finBtn:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, 4)
    finBtn:SetScript("OnClick", function()
        local db = BigNoteBoxDB
        if db then
            db.setupComplete = true
            db.setupPage     = nil
        end
        StopCamera(); StopGlow(); HideOverlay()
        C_UI.Reload()
    end)

    return f
end

--------------------------------------------------------------------------------
-- FRAME CONSTRUCTION
--------------------------------------------------------------------------------
local function BuildWizardFrame()
    if _frame then return _frame end

    local db      = BigNoteBoxDB
    local skinMode = db and db.skinMode

    local f
    if skinMode and BNB.CreateSkinFrame then
        f = BNB.CreateSkinFrame(WorldFrame, false, "BigNoteBoxSetupWizard", false)
    else
        -- Normal mode: use ButtonFrameTemplate to match the main window chrome
        f = CreateFrame("Frame", "BigNoteBoxSetupWizard", UIParent, "ButtonFrameTemplate")
        ButtonFrameTemplate_HidePortrait(f)
        ButtonFrameTemplate_HideButtonBar(f)
        if f.Inset then f.Inset:Hide() end
        f:SetAlpha(0.95)
        -- Wire the template's built-in close button to our quit dialog
        if f.CloseButton then
            f.CloseButton:SetScript("OnClick", function()
                StaticPopup_Show("BNB_QUIT_SETUP")
            end)
        end
    end

    f:SetSize(WIN_W, WIN_H)
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:SetFrameLevel(100)
    f:SetToplevel(true)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:SetClampedToScreen(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) self:StartMoving() end)
    f:SetScript("OnDragStop",  function(self) self:StopMovingOrSizing() end)
    tinsert(UISpecialFrames, "BigNoteBoxSetupWizard")

    -- Title / page counter
    -- Normal mode: ButtonFrameTemplate provides its own title bar and close button.
    -- We use f:SetTitle() for the page title and overlay the page counter on the
    -- template's title region. Skin mode: we build our own strip.
    local contentTopInset   -- how far below the frame top the content starts
    local contentBotInset   -- how far above the frame bottom the content ends

    if skinMode then
        local titleStrip = BNB.CreateBackdropFrame("Frame", nil, f)
        titleStrip:SetHeight(TITLE_H + 6)
        titleStrip:SetPoint("TOPLEFT",  f, "TOPLEFT",  0, 0)
        titleStrip:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
        titleStrip:EnableMouse(true)
        titleStrip:RegisterForDrag("LeftButton")
        titleStrip:SetScript("OnDragStart", function() f:StartMoving() end)
        titleStrip:SetScript("OnDragStop",  function() f:StopMovingOrSizing() end)

        _pageTitle = titleStrip:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        _pageTitle:SetPoint("LEFT",  titleStrip, "LEFT",  12, 0)
        _pageTitle:SetPoint("RIGHT", titleStrip, "RIGHT", -36, 0)
        _pageTitle:SetJustifyH("LEFT")
        _pageTitle:SetTextColor(1, 0.82, 0)

        if BNB.CreateSkinCloseButton then
            local cb = BNB.CreateSkinCloseButton(titleStrip, function()
                StaticPopup_Show("BNB_QUIT_SETUP")
            end)
            cb:SetPoint("RIGHT", titleStrip, "RIGHT", -4, 0)
        end

        _pageCounter = titleStrip:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        _pageCounter:SetPoint("BOTTOMRIGHT", titleStrip, "BOTTOMRIGHT", -36, 4)
        _pageCounter:SetTextColor(0.55, 0.55, 0.55)

        contentTopInset = -(TITLE_H + 14)
    else
        -- ButtonFrameTemplate: use SetTitle for the page title text.
        -- _pageTitle is a shim that proxies SetText to f:SetTitle().
        _pageTitle = {}
        setmetatable(_pageTitle, { __index = function(_, k)
            if k == "SetText" then
                return function(_, txt) f:SetTitle(txt or "") end
            end
        end })

        -- Page counter sits in the top-right of the template title bar area.
        _pageCounter = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        _pageCounter:SetPoint("TOPRIGHT", f, "TOPRIGHT", -36, -8)
        _pageCounter:SetTextColor(0.55, 0.55, 0.55)

        contentTopInset = -36   -- ButtonFrameTemplate title bar is ~32px tall
    end

    -- Nav area
    local navStrip = BNB.CreateBackdropFrame("Frame", nil, f)
    navStrip:SetHeight(NAV_H)
    navStrip:SetPoint("BOTTOMLEFT",  f, "BOTTOMLEFT",  0, 0)
    navStrip:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
    if not skinMode then
        BNB.SetBackdrop(navStrip, 0.08, 0.08, 0.10, 0.50, 0.28, 0.28, 0.30, 0)
    end

    _prevBtn = BNB.CreateButton(nil, navStrip, "< Previous", 120, 28)
    _prevBtn:SetPoint("LEFT", navStrip, "LEFT", 12, 0)
    _prevBtn:SetScript("OnClick", function()
        local target = _curPage - 1
        -- Skip page 3 (skin colour) when in normal mode
        if target == 3 and not (BigNoteBoxDB and BigNoteBoxDB.skinMode) then
            target = 2
        end
        -- Skip page 6 (migration notice) when no migratable addons detected
        if target == 6 and not _hasMigration then
            target = 5
        end
        GoToPage(target)
    end)

    _nextBtn = BNB.CreateButton(nil, navStrip, "Next >", 120, 28)
    _nextBtn:SetPoint("RIGHT", navStrip, "RIGHT", -12, 0)
    _nextBtn:SetScript("OnClick", function()
        local pg = _pages[_curPage]
        if pg and pg.OnNext then
            pg.OnNext()
        else
            local target = _curPage + 1
            -- Skip page 3 (skin colour) when in normal mode
            if target == 3 and not (BigNoteBoxDB and BigNoteBoxDB.skinMode) then
                target = 4
            end
            -- Skip page 6 (migration notice) when no migratable addons detected
            if target == 6 and not _hasMigration then
                target = 7
            end
            GoToPage(target)
        end
    end)

    -- Content area
    local content = CreateFrame("Frame", nil, f)
    content:SetPoint("TOPLEFT",     f, "TOPLEFT",     PAD, contentTopInset - 6)
    content:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -PAD, NAV_H + 8)

    -- Detect migration availability once at build time
    _hasMigration = BNB.Migration and BNB.Migration.HasAny and BNB.Migration.HasAny() or false

    -- Build pages
    _pages = {
        BuildPage1(content),
        BuildPage2(content),
        BuildPage3(content),
        BuildPage4(content),
        BuildPage5(content),
        BuildPage6(content),   -- migration notice (skipped if _hasMigration == false)
        BuildPage7(content),   -- done
    }

    -- Combat: hide wizard
    f:RegisterEvent("PLAYER_REGEN_DISABLED")
    f:SetScript("OnEvent", function(self, event)
        if event == "PLAYER_REGEN_DISABLED" and self:IsShown() then
            self._hiding = true; self:Hide(); self._hiding = false
            HideOverlay(); StopCamera()
            BNB:Print("|cffff9900Setup wizard hidden during combat. It will reappear when combat ends.|r")
        end
    end)

    -- Prevent accidental close
    f:SetScript("OnHide", function(self)
        if self._quitting or self._hiding then return end
        -- Suppress hide, re-show after a tick, prompt
        self._hiding = true
        C_Timer.After(0.05, function()
            if not (BigNoteBoxDB and BigNoteBoxDB.setupComplete) then
                self:Show(); self:Raise()
            end
            self._hiding = false
        end)
    end)

    f:Hide()
    _frame = f
    return f
end

--------------------------------------------------------------------------------
-- PUBLIC API
--------------------------------------------------------------------------------
function BNB.ShowSetupWizard()
    RegisterQuitDialog()
    local f = BuildWizardFrame()

    -- Close all open BNB windows so setup has a clean slate
    pcall(function()
        if BNB.mainFrame and BNB.mainFrame:IsShown() then BNB.mainFrame:Hide() end
        local cfg = BigNoteBoxConfigFrame
        if cfg and cfg:IsShown() then cfg:Hide() end
        if BNB.DangerZone and BNB.DangerZone.Close then BNB.DangerZone.Close() end
        if BNB.RichPreview and BNB.RichPreview.Hide then BNB.RichPreview.Hide() end
        if BNB.ShareNote and BNB.ShareNote.Close then BNB.ShareNote.Close() end
        if BNB.AlarmManager and BNB.AlarmManager.CloseWindow then BNB.AlarmManager.CloseWindow() end
        if BNB.HistoryWindow and BNB.HistoryWindow:IsShown() then BNB.HistoryWindow:Hide() end
        -- Sticky notes: hide all open ones
        if BNB._stickyFrames then
            for _, sf in pairs(BNB._stickyFrames) do
                if sf and sf:IsShown() then sf:Hide() end
            end
        end
        -- RefBox
        local rbf = BigNoteBoxRefBox
        if rbf and rbf:IsShown() then rbf:Hide() end
        -- Inspect note window
        local inf = BigNoteBoxInspectFrame
        if inf and inf:IsShown() then inf:Hide() end
    end)

    -- Resume page from a reload (e.g. after skin mode choice on page 2)
    local db = BigNoteBoxDB
    local resumePage = db and db.setupPage
    if resumePage and resumePage >= 1 and resumePage <= NUM_PAGES then
        _curPage = resumePage
        db.setupPage = nil  -- consume the resume flag
    else
        _curPage = 1
    end

    UpdateNavigation()
    f._quitting = false
    f._hiding   = false
    f:Show()
    f:Raise()

    -- Overlay, camera, glow
    ShowOverlay()
    StartCamera()
    -- Defer glow one tick so LCG is guaranteed available post-login
    C_Timer.After(0.1, StartGlow)
end

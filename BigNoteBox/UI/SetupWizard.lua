-- BigNoteBox UI/SetupWizard.lua
-- First-time setup wizard. 9 pages (P_* below):
--   1: Welcome
--   2: How do you want to use BNB: Minimal / Everything / Custom (ALL-358)
--   3: Custom module picks (only after Custom)
--   4: Skin mode choice (normal vs skin) — may reload into page 5
--   5: Skin colour / brightness (skin mode only)
--   6: Notes behaviour (font, list mode, sidebar, combat, LSM)
--   7: Keybinds
--   8: Migration notice (only when migratable addons are installed)
--   9: Done
--
-- DB flags:
--   BigNoteBoxDB.setupComplete  (bool)   — wizard has been finished
--   BigNoteBoxDB.setupPage      (number) — resume page after reload
--   BigNoteBoxDB.setupUsage     (string) — page 2's pick, so a reload mid-wizard keeps Custom
--
-- Entry point: BNB.ShowSetupWizard()
-- Called from Initialize.lua after all systems are built.

local BNB = BigNoteBox
local L   = BNB.L

--------------------------------------------------------------------------------
-- CONSTANTS
--------------------------------------------------------------------------------
local ASSETS    = "Interface\\AddOns\\BigNoteBox\\Assets\\"
local WIN_W     = 480
local WIN_H     = 500
local PAD       = 20
local CW        = WIN_W - PAD * 2        -- content width
local TITLE_H   = 28
local NAV_H     = 44                     -- bottom nav bar height
local BNB_URL   = "https://www.curseforge.com/wow/addons/bignotebox"

local NUM_PAGES = 9
-- Pages referred to by number (the full list is in the header)
local P_USAGE, P_MODULES, P_THEME, P_NOTES, P_MIGRATE = 2, 3, 5, 6, 8

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
local _pageTitle   = nil
local _pageCounter = nil
local _prevBtn     = nil
local _nextBtn     = nil
local _getStartedBtn = nil
local _usage       = nil   -- page 2's pick: "minimal" / "everything" / "custom"

-- FadeTo and the LibCustomGlow lookup are shared with WhatsNew/FeatureList/
-- DangerZone/FocusEditor in UI/GlowOverlay.lua (ALL-65.4).
local FadeTo = BNB.FadeTo

--------------------------------------------------------------------------------
-- LARGE BUTTON FACTORY  (matches OptionsPanel.lua's SharedButtonLargeTemplate)
-- Used for primary CTA buttons: Get Started, Finish, Finish & Open.
-- Skin mode: a 16pt skin button instead (ALL-79). Choosing skin mode on page 4
-- reloads, so the mode read at build time is always current.
--------------------------------------------------------------------------------
local function MakeLargeButton(parent, text, w, h)
    if BigNoteBoxDB and BigNoteBoxDB.skinMode then
        return BNB.CreateSkinButton(nil, parent, text, w or 220, h or 50, 16)
    end
    local btn = CreateFrame("Button", nil, parent, "SharedButtonLargeTemplate")
    btn:SetSize(w or 220, h or 50)
    btn:SetText(text or "")
    pcall(function() DynamicResizeButton_Resize(btn) end)
    if btn.GetFontString then
        local bfs = btn:GetFontString()
        if bfs then pcall(function() bfs:SetFont(BNB.GetLocaleFont(), 16, "") end) end
    end
    return btn
end
--------------------------------------------------------------------------------
local function GetOverlayColor()
    -- 0.82 read as solid black on both Forever and retail (FOR-14)
    local a = 0.5
    local db = BigNoteBoxDB
    if db and db.skinMode and BNB.GetSkinPreset and BNB.SkinColourOf then
        local p = BNB.GetSkinPreset()
        local r, g, b = BNB.SkinColourOf(p, false)
        return r, g, b, a
    end
    return 0, 0, 0, a
end

local function GetOverlay()
    if _overlay then return _overlay end
    local ov = CreateFrame("Frame", nil, WorldFrame)
    ov:SetAllPoints(UIParent)
    -- DIALOG, not FULLSCREEN: keeps overlay + wizard below Blizzard's FULLSCREEN_DIALOG dropdown
    -- popups, which otherwise drew behind the wizard (FOR-03)
    ov:SetFrameStrata("DIALOG")
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
    if not _frame then return end
    local r, g, b = 0.400, 0.733, 0.416   -- BNB green
    local db = BigNoteBoxDB
    if db and db.skinMode and BNB.GetSkinPreset and BNB.SkinBorderOf then
        local p = BNB.GetSkinPreset()
        r, g, b = BNB.SkinBorderOf(p)
    end
    BNB.StartWindowGlow(_frame, GLOW_KEY, nil, { r, g, b, 0.85 }, GLOW_N, GLOW_FREQUENCY, GLOW_SCALE)
end

local function StopGlow()
    BNB.StopWindowGlow(_frame, GLOW_KEY)
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
        preferredIndex = 3,
        text    = L["SW_QUIT_CONFIRM_TEXT"],
        button1 = L["SW_QUIT_BTN"],
        button2 = L["SW_KEEP_GOING_BTN"],
        timeout = 0, whileDead = true, hideOnEscape = true,
        OnAccept = function()
            local db = BigNoteBoxDB
            if db then db.setupComplete = true; db.setupPage = nil; db.setupUsage = nil end
            if _frame then
                _frame._quitting = true
                _frame:Hide()
            end
            HideOverlay()
            StopCamera()
            StopGlow()
            -- Held back while the wizard was pending (Core/Events.lua)
            if BNB.ShowForeverNoticeIfDue then BNB.ShowForeverNoticeIfDue() end
        end,
    }
end

--------------------------------------------------------------------------------
-- LANGUAGE CHANGE DIALOG (ALL-14)
--------------------------------------------------------------------------------
local function RegisterLangChangeDialog()
    if StaticPopupDialogs["BNB_WIZARD_CHANGE_LANGUAGE"] then return end
    StaticPopupDialogs["BNB_WIZARD_CHANGE_LANGUAGE"] = {
        preferredIndex = 3,
        text    = L["SW_POPUP_WIZARD_CHANGE_LANGUAGE"],
        button1 = L["CFG_RELOAD_NOW_BTN"],
        button2 = L["CANCEL"],
        timeout = 0, whileDead = true, hideOnEscape = true,
        OnAccept = function()
            local db = BigNoteBoxDB
            if db then db.setupPage = 1 end
            BigNoteBoxLocale = (BNB._pendingLangCode == "client") and nil or BNB._pendingLangCode
            BNB._pendingLangCode = nil
            C_UI.Reload()
        end,
        OnCancel = function() BNB._pendingLangCode = nil end,
    }
end

--------------------------------------------------------------------------------
-- NAVIGATION
--------------------------------------------------------------------------------
-- Keys, not resolved strings: this table is built at file load, before
-- BigNoteBoxDB (and debugPseudoLocale) is restored, so caching L[...] results
-- here would freeze them at their pre-SavedVariables value forever. Resolve
-- each key through L at display time instead (UpdateNavigation).
local PAGE_TITLE_KEYS = {
    "SW_PAGE_TITLE_1",
    "SW_PAGE_TITLE_USAGE",
    "SW_PAGE_TITLE_MODULES",
    "SW_PAGE_TITLE_2",
    "SW_PAGE_TITLE_3",
    "SW_PAGE_TITLE_4",
    "SW_PAGE_TITLE_5",
    "SW_PAGE_TITLE_6",
    "SW_PAGE_TITLE_7",
}

-- The pages Prev / Next step over: module picks unless Custom, the skin
-- colour page in normal mode, the migration notice without migratable addons
local function PageSkipped(n)
    if n == P_MODULES then return _usage ~= "custom" end
    if n == P_THEME   then return not (BigNoteBoxDB and BigNoteBoxDB.skinMode) end
    if n == P_MIGRATE then return not _hasMigration end
    return false
end

local function StepFrom(n, dir)
    local t = n + dir
    while t > 1 and t < NUM_PAGES and PageSkipped(t) do t = t + dir end
    return t
end

local function UpdateNavigation()
    if not _frame then return end
    local key = PAGE_TITLE_KEYS[_curPage]
    _pageTitle:SetText((key and L[key]) or "")

    -- Counter over the pages that are not skipped
    local total, cur = 0, 0
    for i = 1, NUM_PAGES do
        if not PageSkipped(i) then
            total = total + 1
            if i <= _curPage then cur = total end
        end
    end
    _pageCounter:SetText(string.format(L["SW_PAGE_COUNTER_FMT"], cur, total))

    for i, pg in ipairs(_pages) do
        if i == _curPage then pg:Show() else pg:Hide() end
    end

    -- Page 1: hide prev/next, show Get Started button instead
    _prevBtn:SetShown(_curPage > 1)
    _nextBtn:SetShown(_curPage > 1 and _curPage < NUM_PAGES)
    if _getStartedBtn then _getStartedBtn:SetShown(_curPage == 1) end
end

local function GoToPage(n)
    _curPage = math.max(1, math.min(n, NUM_PAGES))
    UpdateNavigation()
end

--------------------------------------------------------------------------------
-- SHARED HELPERS
--------------------------------------------------------------------------------
local function MakeLabel(parent, y, text, fontSize, r, g, b)
    local fs = parent:CreateFontString(nil, "OVERLAY", "BNBFontNormal")
    fs:SetPoint("TOPLEFT",  parent, "TOPLEFT",  0, y)
    fs:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, y)
    fs:SetJustifyH("LEFT")
    fs:SetWordWrap(true)
    if fontSize then pcall(function() fs:SetFont(BNB.GetLocaleFont(), fontSize, "") end) end
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
    local fs = parent:CreateFontString(nil, "OVERLAY", "BNBFontNormalLarge")
    fs:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, y)
    BNB.SetHeaderColor(fs)
    fs:SetText(text)
    return y - 24
end

-- Dropdown helper (WowStyle1DropdownTemplate)
local function MakeDropdown(parent, y, w, setupMenu)
    local dd = BNB.SkinDropdown(CreateFrame("DropdownButton", nil, parent, "WowStyle1DropdownTemplate"))
    dd:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, y)
    dd:SetWidth(w or CW)
    dd:SetToplevel(true)
    dd:SetupMenu(setupMenu)
    return dd, y - 36
end

-- Checkbox helper
local function MakeCheck(parent, y, text, getter, setter, tip)
    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    BNB.LabelHit(cb)   -- the tooltip and click reach over its label too
    cb:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, y)
    cb:SetChecked(getter())
    cb.text = cb.text or cb:CreateFontString(nil, "OVERLAY", "BNBFontNormal")
    cb.text:SetPoint("LEFT", cb, "RIGHT", 2, 0)
    cb.text:SetText(text)
    cb:SetScript("OnClick", function(self) setter(self:GetChecked()) end)
    if tip then BNB.CheckTip(cb, tip) end
    return cb, y - 30
end

-- Slim scroll frame for pages with lots of content
local function MakeScrollContent(parent)
    local sf = BNB.CreateScrollFrame(nil, parent)
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

    -- ALL-14 fix, Dukul 2026-09-23: Get Started now lives in the wizard's nav strip
    -- (BuildWizardFrame, like Prev/Next on every other page) instead of floating inside
    -- this page's own content, so it never competes with the language selector for
    -- space and the nav strip is never left looking empty underneath it. That gives
    -- page 1 the same full content area every other page gets; still wrapped in a
    -- scroll region (matches MakeScrollContent elsewhere in this file) as a safety net
    -- for long translations, not because it is expected to be needed.
    local sf, ct = MakeScrollContent(f)

    -- Numeric y-cursor (matches the MakeScrollContent pages elsewhere in this file) so
    -- ct's final height can be set exactly, whatever the welcome text wraps to.
    local y = -10

    -- Logo
    local logo = ct:CreateTexture(nil, "ARTWORK")
    logo:SetSize(96, 96)
    logo:SetPoint("TOP", ct, "TOP", 0, y)
    logo:SetTexture(ASSETS .. "logo")
    y = y - 96 - 10

    -- Addon name
    local name = ct:CreateFontString(nil, "OVERLAY", "BNBFontNormalHuge")
    name:SetPoint("TOP", ct, "TOP", 0, y)
    name:SetText(L["OPT_TITLE"])
    y = y - (name:GetStringHeight() or 20) - 4

    -- Version
    local ver = ct:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    ver:SetPoint("TOP", ct, "TOP", 0, y)
    ver:SetText(string.format(L["SW_VERSION_FMT"], BNB.ADDON_VERSION))
    ver:SetTextColor(0.55, 0.55, 0.55)
    y = y - (ver:GetStringHeight() or 12) - 2

    -- By Dukul
    local by = ct:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    by:SetPoint("TOP", ct, "TOP", 0, y)
    by:SetText(L["AUTHOR"])
    by:SetTextColor(0.65, 0.65, 0.65)
    y = y - (by:GetStringHeight() or 12) - 24

    -- Welcome text
    local txt = ct:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    txt:SetPoint("TOP", ct, "TOP", 0, y)
    txt:SetWidth(CW - 36)
    txt:SetJustifyH("CENTER")
    txt:SetSpacing(3)
    txt:SetText(L["SW_WELCOME_TEXT"])
    txt:SetTextColor(0.88, 0.88, 0.88)
    y = y - (txt:GetStringHeight() or 60) - 16

    -- Language selector (ALL-14): pinned to the bottom of the page, right
    -- above Get started, out of the scrolling text (ALL-268). Selecting a
    -- language asks, then reloads into page 1. Not on Forever (FOR-32, Dukul
    -- 2026-10-06): its TOC has no BigNoteBoxLocale / LoadSavedVariablesFirst,
    -- so the pick cannot survive the reload; back after FOR-08. Without the
    -- box the text keeps MakeScrollContent's full-height anchors.
    if not (BNB.IsForever or BNB.IsClassic) then   -- Classic the same (ALL-168)
        local LANG_BOX_H = 56
        local lb = CreateFrame("Frame", nil, f)
        lb:SetPoint("BOTTOMLEFT",  f, "BOTTOMLEFT",  0, 0)
        lb:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
        lb:SetHeight(LANG_BOX_H)
        sf:SetPoint("BOTTOMRIGHT", lb, "TOPRIGHT", -16, 4)
        local ly = 0

        local lgLbl = lb:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        lgLbl:SetPoint("TOP", lb, "TOP", 0, ly)
        lgLbl:SetText(L["SW_WELCOME_LANG_LBL"])
        ly = ly - (lgLbl:GetStringHeight() or 14) - 6

        local FLAG = ASSETS .. "Flags\\"
        -- { code, label, flag, available }  available=false -> greyed "(Coming soon)"
        local LANG_LIST = {
            { code = "client", label = L["LANGUAGE_CLIENT"], flag = nil,               available = true  },
            { code = "enUS",   label = "English",            flag = FLAG.."flag-en",   available = true  },
            { code = "zhCN",   label = "简体中文",             flag = FLAG.."flag-cn",   available = true  },
            { code = "deDE",   label = "Deutsch",             flag = FLAG.."flag-de",   available = false },
            { code = "frFR",   label = "Français",            flag = FLAG.."flag-fr",   available = false },
            { code = "esES",   label = "Español",             flag = FLAG.."flag-es",   available = false },
            { code = "ptBR",   label = "Português",           flag = FLAG.."flag-br",   available = false },
            { code = "itIT",   label = "Italiano",            flag = FLAG.."flag-it",   available = false },
            { code = "jaJP",   label = "日本語",               flag = FLAG.."flag-ja",   available = false },
            { code = "koKR",   label = "한국어",               flag = FLAG.."flag-ko",   available = false },
            { code = "zhTW",   label = "繁體中文",             flag = FLAG.."flag-tw",   available = false },
        }

        local COMING_SOON = L["LANGUAGE_COMING_SOON"]
        local GREY        = "|cff888888"

        -- entry.label for "client" is L["LANGUAGE_CLIENT"], already translated into whatever
        -- language is active -- so on a forced-Chinese UI it reads "客户端语言" alone, with no
        -- clue that it means "Client Language" (Dukul, 2026-09-23). Always show the hardcoded
        -- English name too, whenever the ACTIVE language isn't English -- forced or natural.
        local MakeLangLabel = BNB.MakeLangLabel

        local curLangCode = (BigNoteBoxLocale and BigNoteBoxLocale ~= "") and BigNoteBoxLocale or "client"

        local langDD = BNB.SkinDropdown(CreateFrame("DropdownButton", nil, lb, "WowStyle1DropdownTemplate"))
        langDD:SetPoint("TOP", lb, "TOP", 0, ly)
        langDD:SetWidth(CW - 40)
        langDD:SetupMenu(function(_, root)
            for _, entry in ipairs(LANG_LIST) do
                local lbl = MakeLangLabel(entry)
                if entry.available then
                    root:CreateRadio(lbl,
                        function() return curLangCode == entry.code end,
                        function()
                            if entry.code == curLangCode then return end
                            BNB._pendingLangCode = entry.code
                            StaticPopup_Show("BNB_WIZARD_CHANGE_LANGUAGE", entry.label)
                        end)
                else
                    local greyLbl = GREY .. (entry.flag and ("|T" .. entry.flag .. ":14:20:0:0:32:32|t ") or "")
                        .. entry.label .. "|r  " .. COMING_SOON
                    local dummy = root:CreateRadio(greyLbl, function() return false end, function() end)
                    dummy:AddInitializer(function(button)
                        if button.fontString then button.fontString:SetTextColor(0.5, 0.5, 0.5) end
                        button:SetEnabled(false)
                        if button.highlight then button.highlight:SetAlpha(0) end
                    end)
                end
            end
        end)
    end

    ct:SetHeight(math.abs(y) + 16)

    -- Get Started lives in the nav strip now (see BuildWizardFrame / _getStartedBtn).

    return f
end

--------------------------------------------------------------------------------
-- MODULE SWITCHES (ALL-358) — what pages 2 and 3 turn on and off
--------------------------------------------------------------------------------
-- One entry per switchable module, the same switch as its Settings > Modules
-- checkbox: label = that page's title, tip = what the module is and does
-- (the Custom page's tooltip, written for a new player), get reads
-- the saved switch, set saves it and applies it live (Finish reloads anyway,
-- but Quit does not).
local function SetDB(key, v) if BigNoteBoxDB then BigNoteBoxDB[key] = v end end

local MODULES = {
    { key = "alarms", label = "CFG_HDR_ALARMS", tip = "SW_MOD_ALARMS_TIP",
      get = function() return BNB.AlarmsEnabled() end,
      set = function(v)
          SetDB("alarmsEnabled", v)
          if BNB.Alarm and BNB.Alarm.ApplyModule then BNB.Alarm.ApplyModule(v) end
      end },
    { key = "sidebar", label = "CFG_HDR_SIDEBAR", tip = "SW_MOD_SIDEBAR_TIP",
      get = function() return BigNoteBoxDB and BigNoteBoxDB.sidebarEnabled == true end,
      set = function(v)
          SetDB("sidebarEnabled", v)
          local SB = BNB.Sidebar
          if not v and SB and SB.SetActive then SB.SetActive("all") end
          if SB and SB.Refresh then SB.Refresh() end
          if BNB.SyncSidebarWysiwygBtns then BNB.SyncSidebarWysiwygBtns() end
          if BNB.ApplyToolbarIcons then BNB.ApplyToolbarIcons() end
      end },
    { key = "context", label = "CFG_HDR_CONTEXT_POPUP", tip = "SW_MOD_CONTEXT_TIP",
      get = function() return BNB.SituationsEnabled() end,
      set = function(v)
          SetDB("contextSurface", v)
          if BNB.ApplySituationsModule then BNB.ApplySituationsModule(v) end
      end },
    { key = "focus", label = "CFG_FOCUS_ORBIT_HEADER", tip = "SW_MOD_FOCUS_TIP",
      get = function() return BNB.FocusEnabled() end,
      set = function(v)
          SetDB("focusEnabled", v)
          if BNB.ApplyFocusModule then BNB.ApplyFocusModule(v) end
      end },
    { key = "history", label = "CFG_HDR_NOTE_HISTORY", tip = "SW_MOD_HISTORY_TIP",
      get = function() return BNB.HistoryEnabled() end,
      set = function(v)
          SetDB("historyEnabled", v)
          if BNB.ApplyHistoryModule then BNB.ApplyHistoryModule(v) end
      end },
    { key = "oracle", label = "CFG_HDR_ORACLE", tip = "SW_MOD_ORACLE_TIP",
      get = function() return not BigNoteBoxDB or BigNoteBoxDB.oracleEnabled ~= false end,
      set = function(v)
          if v then SetDB("oracleEnabled", nil)   -- nil = on (UI/Oracle.lua)
          else
              SetDB("oracleEnabled", false)
              if BNB.Oracle and BNB.Oracle.Close then BNB.Oracle.Close() end
          end
      end },
    { key = "unitNotes", label = "CFG_SUB_PLAYER_NPC", tip = "SW_MOD_UNIT_TIP",
      get = function() return BNB.UnitNotesEnabled() end,
      set = function(v)
          SetDB("unitNotesEnabled", v)
          if BNB.ApplyUnitNotesModule then BNB.ApplyUnitNotesModule(v) end
      end },
    { key = "quickNote", label = "CFG_HDR_QUICK_NOTE", tip = "SW_MOD_QN_TIP",
      get = function() return not BigNoteBoxDB or BigNoteBoxDB.quickNoteEnabled ~= false end,
      set = function(v) SetDB("quickNoteEnabled", v) end },
    { key = "refBox", label = "CFG_HDR_REFBOX", tip = "SW_MOD_REFBOX_TIP",
      get = function() return not BigNoteBoxDB or BigNoteBoxDB.referenceBoxEnabled ~= false end,
      set = function(v)
          SetDB("referenceBoxEnabled", v)
          if BNB.ApplySaveMode      then BNB.ApplySaveMode()      end   -- editor bar button
          if BNB.ApplyRefBoxModules then BNB.ApplyRefBoxModules() end
      end },
    { key = "rich", label = "CFG_RICH_SIZES_HEADER", tip = "SW_MOD_RICH_TIP",
      get = function() return BNB.RichEnabled() end,
      set = function(v)
          SetDB("richEnabled", v)
          if BNB.ApplyRichModule then BNB.ApplyRichModule(v) end
      end },
    { key = "stickies", label = "CFG_CELL_STICKY_HDR", tip = "SW_MOD_STICKY_TIP",
      get = function() return BNB.StickiesEnabled() end,
      set = function(v)
          SetDB("stickiesEnabled", v)
          if BNB.Sticky and BNB.Sticky.ApplyModule then BNB.Sticky.ApplyModule(v) end
      end },
    { key = "tasks", label = "CFG_HDR_TASKS", tip = "SW_MOD_TASKS_TIP",
      get = function() return BNB.TasksEnabled() end,
      set = function(v) BNB.ApplyTasksModule(v) end },
    { key = "toasts", label = "CFG_HDR_TOASTS", tip = "SW_MOD_TOASTS_TIP",
      get = function() return BNB.ToastsEnabled() end,
      set = function(v)
          SetDB("toastsEnabled", v)
          if BNB.ApplyToastsModule then BNB.ApplyToastsModule(v) end
      end },
    { key = "trash", label = "CFG_HDR_TRASH", tip = "SW_MOD_TRASH_TIP",
      get = function() return not BigNoteBoxDB or BigNoteBoxDB.trashFeature ~= false end,
      set = function(v)
          SetDB("trashFeature", v)
          if BNB.ApplyToolbarIcons then BNB.ApplyToolbarIcons() end
          local tf = _G["BigNoteBoxTrashFrame"]
          if not v and tf and tf:IsShown() then tf:Hide() end
      end },
}

-- Minimal = only what writing notes needs (Dukul, 2026-10-07)
local MINIMAL_ON = { trash = true, quickNote = true, context = true,    -- Situations on (Dukul 2026-10-07, ALL-375)
                     toasts = true }                                     -- and their toasts (ALL-384)

local function PresetWants(usage)
    local want = {}
    for _, m in ipairs(MODULES) do
        want[m.key] = usage == "everything" or (usage == "minimal" and MINIMAL_ON[m.key] == true)
    end
    return want
end

local function ApplyModules(want)
    for _, m in ipairs(MODULES) do
        local v = want[m.key] == true
        if m.get() ~= v then xpcall(m.set, geterrorhandler(), v) end
    end
end

-- The preset the saved switches match exactly, or nil
local function MatchUsage()
    local all, min = true, true
    for _, m in ipairs(MODULES) do
        local on = m.get() == true
        if not on then all = false end
        if on ~= (MINIMAL_ON[m.key] == true) then min = false end
    end
    return (all and "everything") or (min and "minimal") or nil
end

-- Where page 2 starts: Custom kept across a reload mid-wizard, else the
-- preset the switches match; a first run starts on Everything, a re-run
-- that matches neither on Custom with the switches as they are
local function InitialUsage()
    local db = BigNoteBoxDB or {}
    if db.setupUsage == "custom" and not db.setupComplete then return "custom" end
    return MatchUsage() or (not db.setupComplete and "everything") or "custom"
end

-- Mode badges (Dukul's art, Assets/UI/ui-mode-*.tga): the picture,
-- desaturated while not selected, a tooltip with what the mode means;
-- extraTip is a line under it (nil = none). The caller sets OnClick.
local MODE_ART   = { minimal = "ui-mode-minimal", everything = "ui-mode-full", custom = "ui-mode-custom" }
local MODE_TITLE = { minimal = "SW_USAGE_MINIMAL", everything = "SW_USAGE_EVERYTHING", custom = "SW_USAGE_CUSTOM" }
local MODE_TIP   = { minimal = "MODE_TIP_MINIMAL", everything = "MODE_TIP_FULL", custom = "MODE_TIP_CUSTOM" }

local function CreateModeBadge(parent, size, mode, extraTip)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(size, size)
    local t = b:CreateTexture(nil, "ARTWORK")
    t:SetAllPoints()
    t:SetTexture(ASSETS .. "UI\\" .. MODE_ART[mode])
    b._mode = mode
    function b:SetSelected(on) t:SetDesaturated(not on) end
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(L[MODE_TITLE[mode]], 1, 1, 1)
        GameTooltip:AddLine(L[MODE_TIP[mode]], 0.8, 0.8, 0.8, true)
        local extra = type(extraTip) == "function" and extraTip() or extraTip
        if extra then GameTooltip:AddLine(extra, 0.4, 0.8, 0.4, true) end
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return b
end

-- Shared with Settings > Modules (UI/Config/Modules.lua): the switches, the
-- presets and the badges, so both places use one list
BNB.ModuleUsage = {
    list        = MODULES,
    Match       = MatchUsage,     -- "minimal" / "everything" / nil
    Wants       = PresetWants,    -- usage -> { [key] = bool }
    CreateBadge = CreateModeBadge,
    TitleKey    = MODE_TITLE,
}

--------------------------------------------------------------------------------
-- PAGE 2 — HOW DO YOU WANT TO USE BNB (ALL-358)
--------------------------------------------------------------------------------
local USAGE_CHOICES = {
    { key = "minimal",    title = "SW_USAGE_MINIMAL",    desc = "SW_USAGE_MINIMAL_DESC"    },
    { key = "everything", title = "SW_USAGE_EVERYTHING", desc = "SW_USAGE_EVERYTHING_DESC" },
    { key = "custom",     title = "SW_USAGE_CUSTOM",     desc = "SW_USAGE_CUSTOM_DESC"     },
}

local function BuildUsagePage(content)
    local f = CreateFrame("Frame", nil, content)
    f:SetAllPoints()
    f:Hide()

    local _, y = MakeLabel(f, -4, L["SW_USAGE_LBL"], nil, 0.75, 0.75, 0.75)
    y = y - 4

    -- The mode badges stacked down the left, one per card (Settings shows
    -- them in a row); the one not picked is desaturated
    local BADGE, CARD_GAP = 96, 8
    local CARD_H = BADGE + 8
    local cards = {}
    local function Highlight()
        for _, c in ipairs(cards) do
            c._badge:SetSelected(_usage == c._key)
            if _usage == c._key then
                c:SetBackdropColor(0.08, 0.18, 0.08, 0.95)
                c:SetBackdropBorderColor(0.35, 0.80, 0.35, 1)
                BNB.SetHeaderColor(c._title)
            else
                c:SetBackdropColor(0.06, 0.06, 0.08, 0.95)
                c:SetBackdropBorderColor(0.28, 0.28, 0.30, 1)
                c._title:SetTextColor(0.85, 0.85, 0.85)
            end
        end
    end

    for _, ch in ipairs(USAGE_CHOICES) do
        local c = BNB.CreateBackdropFrame("Button", nil, f)
        c:SetPoint("TOPLEFT",  f, "TOPLEFT",  0, y)
        c:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, y)
        c:SetHeight(CARD_H)
        BNB.SetBackdrop(c, 0.06, 0.06, 0.08, 0.95, 0.28, 0.28, 0.30, 1)
        c._key = ch.key

        c._badge = CreateModeBadge(c, BADGE, ch.key)
        c._badge:SetPoint("LEFT", c, "LEFT", 4, 0)
        c._badge:SetScript("OnClick", function() c:Click() end)

        c._title = c:CreateFontString(nil, "OVERLAY", "BNBFontNormalLarge")
        c._title:SetPoint("TOPLEFT", c._badge, "TOPRIGHT", 10, -14)
        c._title:SetText(L[ch.title])

        local d = c:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        d:SetPoint("TOPLEFT",  c._badge, "TOPRIGHT", 10, -38)
        d:SetPoint("RIGHT",    c, "RIGHT", -14, 0)
        d:SetJustifyH("LEFT"); d:SetJustifyV("TOP"); d:SetWordWrap(true); d:SetSpacing(2)
        d:SetTextColor(0.75, 0.75, 0.75)
        d:SetText(L[ch.desc])

        c:SetScript("OnEnter", function(self)
            if _usage ~= self._key then self:SetBackdropBorderColor(0.45, 0.65, 0.45, 1) end
        end)
        c:SetScript("OnLeave", Highlight)
        c:SetScript("OnClick", function(self)
            _usage = self._key
            Highlight()
            UpdateNavigation()   -- the counter gains or loses the Custom page
        end)
        cards[#cards + 1] = c
        y = y - CARD_H - CARD_GAP
    end

    f:SetScript("OnShow", Highlight)

    -- Minimal / Everything apply here; Custom applies on its own page's Next
    f.OnNext = function()
        if BigNoteBoxDB then BigNoteBoxDB.setupUsage = _usage end
        if _usage ~= "custom" then ApplyModules(PresetWants(_usage)) end
        GoToPage(StepFrom(P_USAGE, 1))
    end

    return f
end

--------------------------------------------------------------------------------
-- PAGE 3 — CUSTOM MODULE PICKS (only after Custom; ALL-358)
--------------------------------------------------------------------------------
local function BuildModulesPage(content)
    local f = CreateFrame("Frame", nil, content)
    f:SetAllPoints()
    f:Hide()

    local _, y = MakeLabel(f, -4, L["SW_MODULES_LBL"], nil, 0.75, 0.75, 0.75)
    y = y - 2

    -- Two columns, alphabetical by the shown name, down the left column first
    local list = {}
    for _, m in ipairs(MODULES) do list[#list + 1] = m end
    table.sort(list, function(a, b) return L[a.label]:lower() < L[b.label]:lower() end)

    local ROW_H = 30
    local COL_W = CW / 2
    local perCol = math.ceil(#list / 2)
    local _pick = {}
    local boxes = {}

    for i, m in ipairs(list) do
        local col, row = (i > perCol) and 1 or 0, (i - 1) % perCol
        local cb = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
        BNB.LabelHit(cb)   -- the tooltip and click reach over its label too
        cb:SetPoint("TOPLEFT", f, "TOPLEFT", col * COL_W - 2, y - row * ROW_H)
        cb.text = cb.text or cb:CreateFontString(nil, "OVERLAY", "BNBFontNormal")
        cb.text:SetPoint("LEFT", cb, "RIGHT", 2, 0)
        cb.text:SetWidth(COL_W - 34)
        cb.text:SetJustifyH("LEFT"); cb.text:SetWordWrap(false)
        cb.text:SetText(L[m.label])
        cb:SetScript("OnClick", function(self) _pick[m.key] = self:GetChecked() and true or false end)
        cb:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(L[m.label], 1, 1, 1)
            GameTooltip:AddLine(L[m.tip], 0.8, 0.8, 0.8, true)
            GameTooltip:Show()
        end)
        cb:SetScript("OnLeave", function() GameTooltip:Hide() end)
        cb._key = m.key
        boxes[#boxes + 1] = cb
    end
    y = y - perCol * ROW_H - 10

    local function Sync()
        for _, cb in ipairs(boxes) do cb:SetChecked(_pick[cb._key] == true) end
    end
    local function SetAll(on)
        for _, m in ipairs(MODULES) do _pick[m.key] = on end
        Sync()
    end

    local allOn = BNB.CreateButton(nil, f, L["SW_MODULES_ALL_ON"], 120, 24)
    allOn:SetPoint("TOPLEFT", f, "TOPLEFT", 0, y)
    allOn:SetScript("OnClick", function() SetAll(true) end)
    local allOff = BNB.CreateButton(nil, f, L["SW_MODULES_ALL_OFF"], 120, 24)
    allOff:SetPoint("LEFT", allOn, "RIGHT", 8, 0)
    allOff:SetScript("OnClick", function() SetAll(false) end)
    y = y - 24 - 14

    MakeLabel(f, y, L["SW_MODULES_LATER"], nil, 0.55, 0.55, 0.55)

    -- Every show starts from the saved switches, so Prev and back never
    -- shows picks that were not applied
    f:SetScript("OnShow", function()
        for _, m in ipairs(MODULES) do _pick[m.key] = m.get() == true end
        Sync()
    end)

    f.OnNext = function()
        ApplyModules(_pick)
        GoToPage(StepFrom(P_MODULES, 1))
    end

    return f
end

--------------------------------------------------------------------------------
-- PAGE 4 — SKIN MODE CHOICE (BuildPage2: the builders keep their old numbers)
--------------------------------------------------------------------------------
local function BuildPage2(content)
    local f = CreateFrame("Frame", nil, content)
    f:SetAllPoints()
    f:Hide()

    local y = -4
    local _, ny = MakeLabel(f, y,
        L["SW_SKIN_CHOICE_LBL"],
        nil, 0.75, 0.75, 0.75)
    y = ny - 4

    -- Two image buttons side by side. The art is 256x128 (ALL-154): the
    -- picture inside the 2 px border keeps that 2:1 shape.
    local IMG_W = 200
    local IMG_H = (IMG_W - 4) / 2
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

        local lbl = btn:CreateFontString(nil, "OVERLAY", "BNBFontNormal")
        lbl:SetPoint("BOTTOM", btn, "BOTTOM", 0, 7)
        lbl:SetText(label)

        local function Highlight()
            if _selected == choiceKey then
                btn:SetBackdropColor(0.08, 0.18, 0.08, 0.95)
                btn:SetBackdropBorderColor(0.35, 0.80, 0.35, 1)
                BNB.SetHeaderColor(lbl)
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
            if f._themeRow then f._themeRow:SetShown(_selected == "skin") end
        end)
        btn._hl = Highlight
        return btn
    end

    -- Forever's normal mode draws wood grain (UI/Chrome.lua), so its preview does too
    local normalImg = BNB.IsForever and "setup-normal-forever" or "setup-normal"
    local normalBtn = MakeImageChoice(L["SW_NORMAL_MODE"],  normalImg,      "normal", 0)
    local skinBtn   = MakeImageChoice(L["SW_SKIN_MODE"],    "setup-skin",   "skin",   IMG_W + GAP)
    f._normalBtn = normalBtn
    f._skinBtn   = skinBtn
    y = y - (IMG_H + 28 + 12)

    -- Skin theme, shown while skin mode is picked (ALL-223). Saved on Next,
    -- which reloads into page 5 already in that theme.
    local _theme = (BigNoteBoxDB and BigNoteBoxDB.skinPreset) or "obsidian"
    do
        local row = CreateFrame("Frame", nil, f)
        row:SetPoint("TOPLEFT",  f, "TOPLEFT",  0, y)
        row:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, y)
        row:SetHeight(28)
        local lbl = row:CreateFontString(nil, "OVERLAY", "BNBFontNormal")
        lbl:SetPoint("LEFT", row, "LEFT", 0, 0)
        lbl:SetText(L["SW_THEME_COLOR_HDR"])
        local entries = {}
        for _, key in ipairs(BNB.SKIN_PRESET_ORDER) do
            entries[#entries + 1] = { label = BNB.SkinPresetLabel(key, true), value = key }
        end
        local dd = BNB.CreateValueDropdown(row, entries, _theme,
            function(v) _theme = v end, IMG_W, 26)
        dd:SetPoint("RIGHT", row, "RIGHT", 0, 0)
        row:SetShown(_selected == "skin")
        f._themeRow = row
    end
    y = y - 28 - 10

    -- Explanation text
    local desc = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    desc:SetPoint("TOPLEFT",  f, "TOPLEFT",  0, y)
    desc:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, y)
    desc:SetJustifyH("LEFT"); desc:SetWordWrap(true); desc:SetSpacing(2)
    desc:SetText(BNB.AccentMarkup(L["SW_SKIN_CHOICE_DESC"]))
    desc:SetTextColor(0.75, 0.75, 0.75)

    -- Store getter for Next handler
    f.GetChoice = function() return _selected end

    -- Wire Next button override: the skin choice may reload
    f.OnNext = function()
        local db = BigNoteBoxDB
        if not db then return end
        local choice = _selected
        if choice == "skin" then
            db.skinMode  = true
            db.skinPreset = _theme   -- the skin page theme dropdown (ALL-223)
            db.setupPage = P_THEME
            db.setupComplete = false
            C_UI.Reload()
        else
            db.skinMode  = false
            db.setupPage = P_NOTES
            -- No reload — straight on, past the skin colour page
            GoToPage(P_NOTES)
        end
    end

    return f
end

--------------------------------------------------------------------------------
-- PAGE 5 — SKIN COLOUR / BRIGHTNESS  (skin mode only; BuildPage3)
--------------------------------------------------------------------------------
local function BuildPage3(content)
    local f = CreateFrame("Frame", nil, content)
    f:SetAllPoints()
    f:Hide()

    local _, ct = MakeScrollContent(f)
    local y = -4

    y = MakeHeader(ct, y, L["SW_THEME_COLOR_HDR"])
    local _, ny = MakeLabel(ct, y,
        L["SW_THEME_COLOR_DESC"],
        nil, 0.65, 0.65, 0.65)
    y = ny

    -- Preset dropdown
    -- Order and short labels from BNB.SKIN_PRESET_ORDER (UI/SkinSystem.lua)
    local PRESET_ORDER = BNB.SKIN_PRESET_ORDER
    local dd, ddy   -- declared first: the menu callback below regenerates dd
    dd, ddy = MakeDropdown(ct, y, CW - 16, function(_, root)
        local cur = (BigNoteBoxDB and BigNoteBoxDB.skinPreset) or "obsidian"
        for _, key in ipairs(PRESET_ORDER) do
            local k = key
            root:CreateRadio(BNB.SkinPresetLabel(k, true),
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
    y = MakeHeader(ct, y, L["SW_BRIGHTNESS_HDR"])
    local _, ny2 = MakeLabel(ct, y,
        L["SW_BRIGHTNESS_DESC"],
        nil, 0.65, 0.65, 0.65)
    y = ny2

    -- Brightness slider — float 0.5–3.0, step 0.05, default BNB.DEFAULTS.skinBrightness (1.5)
    -- Matches main config → Appearance → Skins → Skin brightness exactly.
    local curBrt = (BigNoteBoxDB and BigNoteBoxDB.skinBrightness) or BNB.DEFAULTS.skinBrightness
    local sl = BNB.CreateStackedSlider(ct, CW - 36, {
        label = L["SW_BRIGHTNESS_SLIDER"], min = 0.5, max = 3.0, step = 0.05,
        value = curBrt, default = BNB.DEFAULTS.skinBrightness,
        onChange = function(v)
            if BigNoteBoxDB then BigNoteBoxDB.skinBrightness = v end
            if BNB.ApplyMainWindowSkin then BNB.ApplyMainWindowSkin() end
            RefreshOverlayColor()
        end,
    })
    sl:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
    y = y - (BNB.STACKED_SLIDER_H + 8)

    y = MakeRule(ct, y)
    y = MakeHeader(ct, y, L["SW_RANDOM_THEME_HDR"])

    MakeCheck(ct, y,
        L["SW_RANDOMIZE_CHECK"],
        function() return BigNoteBoxDB and BigNoteBoxDB.skinRandomize == true end,
        function(v) if BigNoteBoxDB then BigNoteBoxDB.skinRandomize = v end end,
        L["CFG_SKIN_RANDOMIZE_TIP"])
    y = y - 32

    local _, ny3 = MakeLabel(ct, y,
        L["SW_RANDOMIZE_DESC"],
        nil, 0.55, 0.55, 0.55)
    y = ny3

    ct:SetHeight(math.abs(y) + PAD)
    return f
end

--------------------------------------------------------------------------------
-- PAGE 6 — NOTES BEHAVIOUR (BuildPage4)
--------------------------------------------------------------------------------
local function BuildPage4(content)
    local f = CreateFrame("Frame", nil, content)
    f:SetAllPoints()
    f:Hide()

    local _, ct = MakeScrollContent(f)
    local y = -4

    -- ── Font picker ──────────────────────────────────────────────────────────
    y = MakeHeader(ct, y, L["SW_NOTE_FONT_HDR"])
    local _, ny = MakeLabel(ct, y,
        L["SW_NOTE_FONT_DESC"],
        nil, 0.65, 0.65, 0.65)
    y = ny

    -- Upvalue: live preview label, shared by font cards and size slider
    local _p4PreviewLbl = nil

    do
        local PICKER_H = 48
        local GAP_V    = 4
        local COL_GAP  = 6
        local CARD_W   = math.floor((CW - 16 - COL_GAP) / 2)
        -- WoW Default has its own checkbox below the grid, like LSM fonts below it.
        -- The grid shows the active language's font set (ALL-14).
        local fonts = BNB.GetPickerFonts()
        local _cards = {}
        local _wowCb

        local function HighlightCards()
            local cur = BNB.GetEffectiveFontID()
            for _, e in ipairs(_cards) do
                if e.id == cur then
                    e.btn:SetBackdropColor(0.08, 0.18, 0.08, 0.95)
                    e.btn:SetBackdropBorderColor(0.35, 0.75, 0.35, 1)
                    if e.nameLbl then BNB.SetHeaderColor(e.nameLbl) end
                else
                    e.btn:SetBackdropColor(0.06, 0.06, 0.08, 0.95)
                    e.btn:SetBackdropBorderColor(0.28, 0.28, 0.30, 1)
                    if e.nameLbl then e.nameLbl:SetTextColor(0.85, 0.85, 0.85, 1) end
                end
            end
            if _wowCb then _wowCb:SetChecked(cur == "wow") end
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
                local cur = BNB.GetEffectiveFontID()
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
                    local sz = (BigNoteBoxDB and BigNoteBoxDB.fontSize) or BNB.DEFAULTS.fontSize
                    local p = (d.bold and d.bold ~= "") and d.bold or d.regular
                    BNB.SetFontSafe(_p4PreviewLbl, p, sz, "BNBFontNormal")
                end
            end)

            local nameLbl = btn:CreateFontString(nil, "OVERLAY")
            nameLbl:SetPoint("TOPLEFT",  btn, "TOPLEFT",  7, -7)
            nameLbl:SetPoint("TOPRIGHT", btn, "TOPRIGHT", -7, -7)
            nameLbl:SetJustifyH("LEFT"); nameLbl:SetHeight(18)
            BNB.SetFontSafe(nameLbl, def.bold, 13, "BNBFontNormal")
            nameLbl:SetText(def.label)

            local prevLbl = btn:CreateFontString(nil, "OVERLAY")
            prevLbl:SetPoint("BOTTOMLEFT",  btn, "BOTTOMLEFT",  7, 7)
            prevLbl:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -7, 7)
            prevLbl:SetJustifyH("LEFT"); prevLbl:SetHeight(14)
            BNB.SetFontSafe(prevLbl, def.regular, 11, "BNBFontNormalSmall")
            prevLbl:SetTextColor(0.62, 0.62, 0.62)
            prevLbl:SetText(def.preview or "")

            _cards[#_cards + 1] = { btn=btn, id=def.id, nameLbl=nameLbl, prevLbl=prevLbl }
        end

        -- The grid always reserves its 4 rows; free rows carry the font pack hint.
        local usedRows = math.ceil(#fonts / 2)
        local gridRows = math.max(BNB.FONT_GRID_ROWS, usedRows)
        BNB.AddFontPackHint(ct, ct, 0, y - usedRows * (PICKER_H + GAP_V),
            CW - 16, (gridRows - usedRows) * (PICKER_H + GAP_V) - GAP_V)
        y = y - gridRows * (PICKER_H + GAP_V) - 8

        -- WoW Default checkbox, below the grid instead of a 9th card. Latin set
        -- only; the row is kept either way so the page layout does not shift.
        local wowCb = CreateFrame("CheckButton", nil, ct, "UICheckButtonTemplate")
        BNB.LabelHit(wowCb)   -- the tooltip and click reach over its label too
        wowCb:SetShown(BNB.ShowWoWFontCheckbox())
        wowCb:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
        wowCb.text = wowCb.text or wowCb:CreateFontString(nil, "OVERLAY", "BNBFontNormal")
        wowCb.text:SetPoint("LEFT", wowCb, "RIGHT", 2, 0)
        wowCb.text:SetText(L["FONT_USE_WOW_DEFAULT"])
        wowCb:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(L["FONT_USE_WOW_DEFAULT_TIP"], 0.8, 0.8, 0.8, true)
            GameTooltip:Show()
        end)
        wowCb:SetScript("OnLeave", function() GameTooltip:Hide() end)
        wowCb:SetScript("OnClick", function(self)
            BNB.ApplyFont(self:GetChecked() and "wow" or "notoserif", nil)
            HighlightCards()
            if _p4PreviewLbl then
                local sz       = (BigNoteBoxDB and BigNoteBoxDB.fontSize) or BNB.DEFAULTS.fontSize
                local boldPath = BNB.GetBoldFont and BNB.GetBoldFont()
                if boldPath and boldPath ~= "" then
                    BNB.SetFontSafe(_p4PreviewLbl, boldPath, sz, "BNBFontNormal")
                end
            end
        end)
        _wowCb = wowCb
        y = y - 30

        -- Deferred highlight (fonts may not be initialised yet on first frame)
        C_Timer.After(0.05, HighlightCards)
    end

    -- Font size slider
    local fssl = BNB.CreateStackedSlider(ct, CW - 36, {
        label = L["SW_FONT_SIZE_SLIDER"], min = 9, max = 22,
        value = (BigNoteBoxDB and BigNoteBoxDB.fontSize) or BNB.DEFAULTS.fontSize, default = BNB.DEFAULTS.fontSize,
        fmt = function(v) return string.format(L["NND_PT_SUFFIX_FMT"], v) end,
        onChange = function(v)
            BNB.ApplyFont(nil, math.floor(v))
            -- Update preview size in real time
            if _p4PreviewLbl then
                local sz       = math.floor(v)
                local boldPath = BNB.GetBoldFont and BNB.GetBoldFont()
                if boldPath and boldPath ~= "" then
                    pcall(function() _p4PreviewLbl:SetFont(boldPath, BNB.FontPx(boldPath, sz), "") end)
                end
            end
        end,
    })
    fssl:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
    y = y - (BNB.STACKED_SLIDER_H + 8)

    -- Font preview box — "Azeroth awaits!" rendered live in selected font + size
    local previewBox = BNB.CreateBackdropFrame("Frame", nil, ct)
    previewBox:SetSize(CW - 16, 38)
    previewBox:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
    BNB.SetBackdrop(previewBox, 0.04, 0.04, 0.06, 0.95, 0.22, 0.22, 0.25, 1)

    local previewLbl = previewBox:CreateFontString(nil, "OVERLAY", "BNBFontNormal")
    previewLbl:SetPoint("LEFT",  previewBox, "LEFT",  10, 0)
    previewLbl:SetPoint("RIGHT", previewBox, "RIGHT", -10, 0)
    previewLbl:SetJustifyH("CENTER")
    previewLbl:SetTextColor(0.75, 0.75, 0.75, 1)
    previewLbl:SetText(L["NND_PREVIEW_SAMPLE"])
    -- Initialise font once BNB fonts are ready
    C_Timer.After(0.05, function()
        local sz       = (BigNoteBoxDB and BigNoteBoxDB.fontSize) or BNB.DEFAULTS.fontSize
        local boldPath = BNB.GetBoldFont and BNB.GetBoldFont()
        BNB.SetFontSafe(previewLbl, boldPath, sz, "BNBFontNormal")
    end)
    _p4PreviewLbl = previewLbl
    y = y - 46

    -- ── List display mode ────────────────────────────────────────────────────
    y = MakeRule(ct, y)
    y = MakeHeader(ct, y, L["SW_LIST_DISPLAY_HDR"])

    local _, ny3 = MakeLabel(ct, y,
        L["SW_LIST_DISPLAY_DESC"],
        nil, 0.65, 0.65, 0.65)
    y = ny3

    local MODE_ITEMS = {
        { key="normal",   label=L["SW_MODE_NORMAL"],   icon=32, preview=L["SW_MODE_NORMAL_PREVIEW"] },
        { key="compact",  label=L["SW_MODE_COMPACT"],  icon=16, preview=L["SW_MODE_COMPACT_PREVIEW"] },
        { key="spacious", label=L["SW_MODE_SPACIOUS"], icon=42, preview=L["SW_MODE_SPACIOUS_PREVIEW"] },
    }
    local MODE_BTN_W = math.floor((CW - 16 - 8) / 3)
    local _modeBtns  = {}

    local function HighlightModes()
        local cur = (BigNoteBoxDB and BigNoteBoxDB.listEntryHeight) or BNB.DEFAULTS.listEntryHeight
        for _, e in ipairs(_modeBtns) do
            if e.key == cur then
                e.btn:SetBackdropColor(0.08, 0.18, 0.08, 0.95)
                e.btn:SetBackdropBorderColor(0.35, 0.75, 0.35, 1)
                if e.lbl then BNB.SetHeaderColor(e.lbl) end
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
        iconTex:SetTexture("Interface\\Icons\\INV_Misc_Note_01")
        iconTex:SetTexCoord(0, 1, 0, 1)

        -- Label
        local lbl = btn:CreateFontString(nil, "OVERLAY", "BNBFontNormal")
        lbl:SetPoint("TOPLEFT",  btn, "TOPLEFT",  8 + iconSz + 6, -8)
        lbl:SetPoint("TOPRIGHT", btn, "TOPRIGHT", -4, -8)
        lbl:SetJustifyH("LEFT")
        lbl:SetText(m.label)

        local sub = btn:CreateFontString(nil, "OVERLAY", "BNBFontNormalSmall")
        sub:SetPoint("TOPLEFT", lbl, "BOTTOMLEFT", 0, -2)
        sub:SetPoint("TOPRIGHT", btn, "TOPRIGHT", -4, 0)
        sub:SetJustifyH("LEFT")
        sub:SetText(m.preview)
        sub:SetTextColor(0.55, 0.55, 0.55)

        local mk = m.key
        btn:SetScript("OnEnter", function(self)
            local cur = (BigNoteBoxDB and BigNoteBoxDB.listEntryHeight) or BNB.DEFAULTS.listEntryHeight
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
    y = MakeHeader(ct, y, L["SW_SIDEBAR_PLACEMENT_HDR"])

    local sideDD, sideY
    sideDD, sideY = MakeDropdown(ct, y, CW - 16, function(_, root)
        local cur = (BigNoteBoxDB and BigNoteBoxDB.sidebarSide) or BNB.DEFAULTS.sidebarSide
        local items = {
            { key="top",   label=L["SW_SIDEBAR_TOP"] },
            { key="right", label=L["SW_SIDEBAR_RIGHT"] },
            { key="left",  label=L["SW_SIDEBAR_LEFT"] },
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
    y = MakeHeader(ct, y, L["SW_COMBAT_HDR"])

    local combatDD, combatY
    combatDD, combatY = MakeDropdown(ct, y, CW - 16, function(_, root)
        local cur = (BigNoteBoxDB and BigNoteBoxDB.combatAction) or BNB.DEFAULTS.combatAction
        local items = {
            { key="nothing",          label=L["SW_COMBAT_NOTHING"] },
            { key="hide_no_stickies", label=L["SW_COMBAT_HIDE_NO_STICKIES"] },
            { key="hide_minimize",    label=L["SW_COMBAT_HIDE_MINIMIZE"] },
            { key="hide_all",         label=L["SW_COMBAT_HIDE_ALL"] },
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

    -- ── LSM fonts (LSM is embedded in libs/, so always there) ──────────────
    y = MakeRule(ct, y)
    y = MakeHeader(ct, y, L["SW_LSM_HDR"])

    local _, ny4 = MakeLabel(ct, y,
        L["SW_LSM_DESC"],
        nil, 0.65, 0.65, 0.65)
    y = ny4

    MakeCheck(ct, y,
        L["SW_LSM_CHECK"],
        function() return BigNoteBoxDB and BigNoteBoxDB.lsmFonts == true end,
        function(v) if BigNoteBoxDB then BigNoteBoxDB.lsmFonts = v end end,
        L["CFG_LSM_FONTS_TIP"])
    y = y - 32

    ct:SetHeight(math.abs(y) + PAD)
    return f
end

--------------------------------------------------------------------------------
-- PAGE 7 — KEYBINDS (BuildPage5)
--------------------------------------------------------------------------------
local function BuildPage5(content)
    local f = CreateFrame("Frame", nil, content)
    f:SetAllPoints()
    f:Hide()

    local _, ct = MakeScrollContent(f)
    local y = -4

    local _, ny = MakeLabel(ct, y,
        L["SW_KEYBINDS_DESC"],
        nil, 0.75, 0.75, 0.75)
    y = ny - 4

    local KEYBINDS = {
        { action="BIGNOTEBOXOPEN",         label=L["SW_KB_OPEN"],         hint=string.format(L["SW_KB_DEFAULT_FMT"], "CTRL-N") },
        { action="BIGNOTEBOXQUICKNOTE",    label=L["SW_KB_QUICKNOTE"],        hint=string.format(L["SW_KB_DEFAULT_FMT"], "F7") },
        { action="BIGNOTEBOXNEWNOTE",      label=L["SW_KB_NEWNOTE"],          hint=string.format(L["SW_KB_DEFAULT_FMT"], "F8") },
        { action="BIGNOTEBOXHIDESTICKIES", label=L["SW_KB_HIDESTICKIES"], hint=string.format(L["SW_KB_DEFAULT_FMT"], "CTRL-H") },
        { action="BIGNOTEBOXTOGGLERV",     label=L["SW_KB_RICHEDITOR"],    hint=string.format(L["SW_KB_DEFAULT_FMT"], L["SW_KB_NONE"]) },
        { action="BIGNOTEBOXNOTEONTARGET", label=L["SW_KB_TARGETNOTE"],    hint=string.format(L["SW_KB_DEFAULT_FMT"], "F6") },
        { action="BIGNOTEBOXORACLE",       label=L["SW_KB_ORACLE"],        hint=string.format(L["SW_KB_DEFAULT_FMT"], "CTRL-SPACE") },
    }

    local _updateFns = {}

    local function MakeKBRow(parent, yp, entry)
        local ROW_H  = 28
        local BTN_W  = 140
        local HINT_W = 110
        local LBL_W  = CW - 16 - BTN_W - HINT_W - 8   -- remaining left side

        local lbl = parent:CreateFontString(nil, "OVERLAY", "BNBFontNormal")
        lbl:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, yp)
        lbl:SetWidth(LBL_W)
        lbl:SetJustifyH("LEFT")
        lbl:SetText(entry.label)

        local kbBtn = BNB.CreateButton(nil, parent, "", BTN_W, 22)
        kbBtn:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, yp)
        kbBtn:RegisterForClicks("AnyUp")

        local hint = parent:CreateFontString(nil, "OVERLAY", "BNBFontNormalSmall")
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

        BNB.WireKeybindCapture(kbBtn, entry.action, UpdateText, L["KEYBIND_PRESS_KEY"])

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
-- PAGE 8 — MIGRATION NOTICE (conditional — only shown when migratable addons detected; BuildPage6)
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
        L["SW_MIGRATION_INTRO"],
        nil, 0.88, 0.88, 0.88)
    y = ny - 2

    -- List detected addons
    for _, name in ipairs(detected) do
        local _, ay = MakeLabel(f, y, string.format(L["SW_MIGRATION_BULLET_FMT"], name), nil, 1, 1, 1)
        y = ay - 0
    end
    y = y - 10

    y = MakeRule(f, y)

    local _, ny2 = MakeLabel(f, y,
        BNB.AccentMarkup(L["SW_MIGRATION_COPY_NOTE"]),
        nil, 0.80, 0.80, 0.80)
    y = ny2 - 8

    local _, ny3 = MakeLabel(f, y,
        BNB.AccentMarkup(L["SW_MIGRATION_LATER_NOTE"]),
        nil, 0.60, 0.60, 0.60)
    y = ny3

    return f
end

--------------------------------------------------------------------------------
-- PAGE 9 — DONE (BuildPage7)
--------------------------------------------------------------------------------
local function BuildPage7(content)
    local f = CreateFrame("Frame", nil, content)
    f:SetAllPoints()
    f:Hide()

    local y = -10

    local thanks = f:CreateFontString(nil, "OVERLAY", "BNBFontNormalHuge")
    thanks:SetPoint("TOP", f, "TOP", 0, y)
    thanks:SetWidth(CW); thanks:SetJustifyH("CENTER")
    thanks:SetText(L["SW_THANKS"])
    y = y - 40

    local tips = {
        L["SW_TIP_1"],
        L["SW_TIP_2"],
        L["SW_TIP_3"],
        L["SW_TIP_4"],
    }
    for _, tip in ipairs(tips) do
        local _, ny = MakeLabel(f, y, BNB.AccentMarkup(string.format(L["SW_TIP_BULLET_FMT"], tip)), nil, 0.80, 0.80, 0.80)
        y = ny - 2
    end

    y = y - 10
    -- CurseForge link
    local urlLbl = f:CreateFontString(nil, "OVERLAY", "BNBFontNormalSmall")
    urlLbl:SetPoint("TOPLEFT",  f, "TOPLEFT",  0, y)
    urlLbl:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, y)
    urlLbl:SetJustifyH("CENTER")
    urlLbl:SetTextColor(0.50, 0.50, 0.50)
    urlLbl:SetText(L["SW_CF_URL_LBL"])
    y = y - 20

    -- One row, Wago.io | CurseForge | WoWInterface (ALL-218, Dukul's order),
    -- each opens the Ctrl+C copy box; links from BNB.BUG_LINKS (UI/BugReport.lua)
    local LINK_GAP = 8
    local linkW = math.min(140, math.floor((CW - 2 * LINK_GAP) / 3))
    local linkX = math.floor((CW - (3 * linkW + 2 * LINK_GAP)) / 2)
    local links = BNB.BUG_LINKS or {}
    for i, def in ipairs({
        { L["SW_LINK_WAGO_BTN"],       links.wago },
        { L["SW_COPY_CF_URL_BTN"],     links.curseforge or BNB_URL },
        { L["SW_LINK_WOWI_BTN"],       links.wowi },
    }) do
        local btn = BNB.CreateButton(nil, f, def[1], linkW, 24)
        btn:SetPoint("TOPLEFT", f, "TOPLEFT", linkX + (i - 1) * (linkW + LINK_GAP), y)
        local url = def[2]
        btn:SetScript("OnClick", function()
            if url and BNB.ShowClipboardHint then
                BNB.ShowClipboardHint(url, btn, true)
            end
        end)
    end
    y = y - 32

    -- Dukul.net link
    local siteLbl = f:CreateFontString(nil, "OVERLAY", "BNBFontNormalSmall")
    siteLbl:SetPoint("TOPLEFT",  f, "TOPLEFT",  0, y)
    siteLbl:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, y)
    siteLbl:SetJustifyH("CENTER")
    siteLbl:SetTextColor(0.50, 0.50, 0.50)
    siteLbl:SetText(L["SW_SITE_LBL"])
    y = y - 20

    local siteBtn = BNB.CreateButton(nil, f, L["SW_COPY_SITE_BTN"], 200, 24)
    siteBtn:SetPoint("TOPLEFT", f, "TOPLEFT", math.floor((CW - 200) / 2), y)
    siteBtn:SetScript("OnClick", function()
        if BNB.ShowClipboardHint then
            BNB.ShowClipboardHint("https://dukul.net", siteBtn, true)
        end
    end)
    y = y - 40

    -- Reload note
    local rnote = f:CreateFontString(nil, "OVERLAY", "BNBFontNormalSmall")
    rnote:SetPoint("BOTTOMLEFT",  f, "BOTTOMLEFT",  0, 114)
    rnote:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 114)
    rnote:SetJustifyH("CENTER")
    rnote:SetTextColor(0.5, 0.5, 0.5)
    rnote:SetText(L["SW_RELOAD_NOTE"])

    -- Finish & Open BigNoteBox (top button)
    local foBtn = MakeLargeButton(f, L["SW_FINISH_OPEN_BTN"], CW, 50)
    foBtn:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, 58)
    foBtn:SetScript("OnClick", function()
        local db = BigNoteBoxDB
        if db then
            db.setupComplete       = true
            db.setupPage           = nil
            db.setupUsage          = nil
            db._openOnceAfterSetup = true
        end
        StopCamera(); StopGlow(); HideOverlay()
        C_UI.Reload()
    end)

    -- Finish (bottom button)
    local finBtn = MakeLargeButton(f, L["SW_FINISH_BTN"], CW, 50)
    finBtn:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, 4)
    finBtn:SetScript("OnClick", function()
        local db = BigNoteBoxDB
        if db then
            db.setupComplete = true
            db.setupPage     = nil
            db.setupUsage    = nil
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

    -- Shared shell for both modes (UI/ToolWindow.lua, CMP-02): title, close
    -- (to our quit dialog), drag, Forever glow. Both modes on UIParent now
    -- (skin mode was on WorldFrame). Esc reaches OnHide below, which asks too.
    local f = BNB.CreateToolWindow({
        name = "BigNoteBoxSetupWizard", w = WIN_W, h = WIN_H, pad = PAD,
        title = "", toplevel = true, escClose = true,
        onClose = function() StaticPopup_Show("BNB_QUIT_SETUP") end,
    })
    local skinMode = f._isSkin
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    -- DIALOG (the builder's default): above the DIALOG lvl 1 overlay, below
    -- dropdown popups (FOR-03)
    f:SetFrameLevel(100)

    -- Page title = the window title; the page counter sits right of it, left
    -- of the close button
    local contentTopInset   -- how far below the frame top the content starts
    _pageTitle = { SetText = function(_, txt) f:SetWindowTitle(txt or "") end }
    _pageCounter = f:CreateFontString(nil, "OVERLAY", "BNBFontNormalSmall")
    _pageCounter:SetTextColor(0.55, 0.55, 0.55)
    _pageCounter:SetPoint("TOPRIGHT", f, "TOPRIGHT", -36, -8)
    -- ButtonFrameTemplate title bar is ~32px tall; skin mode keeps its old inset
    contentTopInset = skinMode and -(TITLE_H + 14) or -36

    -- Nav area
    local navStrip = BNB.CreateBackdropFrame("Frame", nil, f)
    navStrip:SetHeight(NAV_H)
    navStrip:SetPoint("BOTTOMLEFT",  f, "BOTTOMLEFT",  0, 0)
    navStrip:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
    if not skinMode then
        BNB.SetBackdrop(navStrip, 0.08, 0.08, 0.10, 0.50, 0.28, 0.28, 0.30, 0)
    end

    _prevBtn = BNB.CreateButton(nil, navStrip, L["SW_PREV_BTN"], 120, 28)
    _prevBtn:SetPoint("LEFT", navStrip, "LEFT", 12, 0)
    _prevBtn:SetScript("OnClick", function() GoToPage(StepFrom(_curPage, -1)) end)

    _nextBtn = BNB.CreateButton(nil, navStrip, L["SW_NEXT_BTN"], 120, 28)
    _nextBtn:SetPoint("RIGHT", navStrip, "RIGHT", -12, 0)
    _nextBtn:SetScript("OnClick", function()
        local pg = _pages[_curPage]
        if pg and pg.OnNext then
            pg.OnNext()
        else
            GoToPage(StepFrom(_curPage, 1))
        end
    end)

    -- Get Started (page 1 only) -- lives in the nav strip like Prev/Next rather than
    -- floating inside page 1's own content, so it never has to compete with page 1's
    -- content for vertical space (ALL-14 fix, Dukul 2026-09-23: the language selector
    -- pushed page 1's content into the button and left the nav strip looking empty
    -- and untextured underneath it).
    _getStartedBtn = MakeLargeButton(navStrip, L["SW_GET_STARTED_BTN"], 200, NAV_H - 8)
    _getStartedBtn:SetPoint("CENTER", navStrip, "CENTER", 0, 0)
    _getStartedBtn:SetScript("OnClick", function() GoToPage(P_USAGE) end)

    -- Content area
    local content = CreateFrame("Frame", nil, f)
    content:SetPoint("TOPLEFT",     f, "TOPLEFT",     PAD, contentTopInset - 6)
    content:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -PAD, NAV_H + 8)

    -- Detect migration availability once at build time
    _hasMigration = BNB.Migration and BNB.Migration.HasAny and BNB.Migration.HasAny() or false

    -- Build pages
    _pages = {
        BuildPage1(content),
        BuildUsagePage(content),     -- Minimal / Everything / Custom (ALL-358)
        BuildModulesPage(content),   -- Custom picks (skipped unless Custom)
        BuildPage2(content),         -- skin mode choice
        BuildPage3(content),         -- skin colour (skin mode only)
        BuildPage4(content),         -- notes behaviour
        BuildPage5(content),         -- keybinds
        BuildPage6(content),         -- migration notice (skipped if _hasMigration == false)
        BuildPage7(content),         -- done
    }

    -- Combat: hide wizard
    f:RegisterEvent("PLAYER_REGEN_DISABLED")
    f:SetScript("OnEvent", function(self, event)
        if event == "PLAYER_REGEN_DISABLED" and self:IsShown() then
            self._hiding = true; self:Hide(); self._hiding = false
            HideOverlay(); StopCamera()
            BNB:Print(L["SW_COMBAT_HIDDEN"])
        end
    end)

    -- Prevent accidental close
    f:SetScript("OnHide", function(self)
        if self._quitting or self._hiding then return end
        -- Suppress hide, re-show after a tick, prompt
        self._hiding = true
        -- Always ask, same as the X button: Esc (UISpecialFrames) lands here. The quit dialog's
        -- OnAccept is the only path that tears down overlay/camera/glow (ALL-17)
        C_Timer.After(0.05, function()
            if not self:IsShown() then
                self:Show(); self:Raise()
                StaticPopup_Show("BNB_QUIT_SETUP")
            end
            self._hiding = false
        end)
    end)

    -- Guarded: this initial hide fires OnHide, whose timer would otherwise tear down the
    -- overlay that ShowSetupWizard puts up right after the frame is built
    f._hiding = true; f:Hide(); f._hiding = false
    _frame = f
    return f
end

--------------------------------------------------------------------------------
-- PUBLIC API
--------------------------------------------------------------------------------
function BNB.ShowSetupWizard()
    RegisterQuitDialog()
    RegisterLangChangeDialog()
    local f = BuildWizardFrame()

    -- Close all open BNB windows so setup has a clean slate
    pcall(function()
        if BNB.mainFrame and BNB.mainFrame:IsShown() then BNB.mainFrame:Hide() end
        local cfg = BigNoteBoxConfigFrame
        if cfg and cfg:IsShown() then cfg:Hide() end
        if BNB.DangerZone and BNB.DangerZone.Close then BNB.DangerZone.Close() end
        if BNB.RichPreview and BNB.RichPreview.Close then BNB.RichPreview.Close() end
        if BNB.RichPreviewFocus and BNB.RichPreviewFocus.Close then BNB.RichPreviewFocus.Close() end
        if BNB.CloseShareWindow then BNB.CloseShareWindow() end
        if BNB.AlarmWindow and BNB.AlarmWindow.Close then BNB.AlarmWindow.Close() end
        if BNB.CloseHistoryWindow then BNB.CloseHistoryWindow() end
        -- Sticky notes: hide all open ones
        if BNB._stickyFrames then
            for _, sf in pairs(BNB._stickyFrames) do
                if sf and sf:IsShown() then sf:Hide() end
            end
        end
        -- Reference Box (it read the frame names BigNoteBoxRefBox and
        -- BigNoteBoxInspectFrame, which no window has had for a long time)
        if BNB.CloseReferenceBox then BNB.CloseReferenceBox() end
    end)

    -- Resume page from a reload (e.g. after skin mode choice on page 4)
    local db = BigNoteBoxDB
    local resumePage = db and db.setupPage
    _usage = InitialUsage()
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

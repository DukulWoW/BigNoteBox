-- BigNoteBox UI/ConfigWindow.lua -- Settings window
--
-- Six tabs: General | Notes | Appearance | Modules | Backup | Advanced
-- (Notes was Editor, Modules was Features; reordered in ALL-84)
-- Each tab is built by its own file, UI/Config/<Tab>.lua; the export codec
-- is Features/NoteExport.lua. This file keeps the window, the scroll panels
-- and the row builders the tabs share (BNB._ConfigKit).
-- Advanced tab contains the former Reset tab content in a clearly marked
-- danger zone section at the bottom.
-- Matches BCB's ConfigMain.lua pattern:
--   * ButtonFrameTemplate window
--   * PanelTopTabButtonTemplate / PanelTabButtonTemplate
--   * Each tab has a scrollable content area -- scrollbar shown only when needed
--   * Window height tracks the main note window at all times
--
-- Scroll layout rule (mirrors BCB Config.CreateSmartScrollFrame):
--   ScrollFrame always anchored BOTTOMRIGHT -24 to leave room for the bar track.
--   Content frame uses fixed pixel width, not a RIGHT anchor.
--   When bar is not needed: bar hidden, content width slightly wider.
--   This prevents widgets bleeding outside the window on either side.

local BNB = BigNoteBox
local L   = BNB.L

-- ── Constants ─────────────────────────────────────────────────────────────────
local CFG_W      = 480
local TITLE_H    = 60
local TAB_BAR_H  = 32
local PAD        = 16
local CONTENT_W  = CFG_W - PAD * 2 - 30   -- leave extra room so slider value clears bar
local CONTENT_W2 = CFG_W - PAD * 2 - 10   -- bar hidden
local ROW_H      = 28
local ROW_GAP    = 6
local SLIDER_H   = 36

local ASSET = "Interface\\AddOns\\BigNoteBox\\Assets\\"

-- ── Tab definitions ───────────────────────────────────────────────────────────
local TABS = {
    { key = "general",    label = function() return L["CFG_TAB_GENERAL"]    end },
    { key = "notes",      label = function() return L["CFG_TAB_NOTES"]      end },
    { key = "appearance", label = function() return L["CFG_TAB_APPEARANCE"] end },
    { key = "modules",    label = function() return L["CFG_TAB_MODULES"]    end },
    { key = "backup",     label = function() return L["CFG_TAB_BACKUP"]     end },
    { key = "advanced",   label = function() return L["CFG_TAB_ADVANCED"]   end },
}
local NUM_TABS = #TABS

-- Exposed for MainConfigSkin.lua — the skin chrome reads this to build its
-- tab row labels. Do not rely on it outside the skin code path.
BNB._configTabs = TABS

-- ── Module state ──────────────────────────────────────────────────────────────
local cfgFrame     = nil
local tabBtns      = {}
local tabPanels    = {}   -- scroll frames
local tabContent   = {}   -- content frames (scroll children)

-- ── Smart scroll panel ────────────────────────────────────────────────────────
-- Mirrors BCB: scrollFrame always -24 on right, bar hidden when not needed,
-- content frame has fixed pixel width (not RIGHT anchor) to prevent bleed.
-- topOffset: positive pixel distance from the top of the parent frame to the
-- top of the scroll frame. Defaults to the classic chrome height (title bar +
-- tab bar) for ButtonFrameTemplate. Skin mode passes its own smaller value.
local function MakeScrollPanel(parent, topOffset)
    topOffset = topOffset or (TITLE_H + TAB_BAR_H)
    local sf, ct = BNB.CreateAutoScrollPanel(parent, CONTENT_W, CONTENT_W2)
    -- Always leave 24px on the right for the scrollbar track.
    sf:SetPoint("TOPLEFT",     parent, "TOPLEFT",      PAD,  -topOffset)
    sf:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -24,   4)
    sf:Hide()
    return sf, ct
end

-- ── Sub-page state (ALL-84) ───────────────────────────────────────────────────
-- A sub-page is one more scroll panel over a tab's area, opened from a button
-- on that tab. The tab stays highlighted; selecting any tab (the same one
-- included), the back button or closing the window returns to the tab.
local activeSub  = nil   -- the open page, or nil
local buildOwner = nil   -- { parent, topOffset, idx } while _BuildConfigTabPanels runs

local function CloseSubPage()
    if not activeSub then return end
    activeSub.sf:Hide()
    activeSub = nil
end
-- MainConfigSkin.lua's own tab select calls this too.
BNB._CloseConfigSubPage = CloseSubPage

-- ── Tab selector ──────────────────────────────────────────────────────────────
local function SelectTab(idx)
    CloseSubPage()
    for i = 1, NUM_TABS do
        if tabBtns[i] then
            if i == idx then PanelTemplates_SelectTab(tabBtns[i])
            else             PanelTemplates_DeselectTab(tabBtns[i]) end
        end
        if tabPanels[i] then
            if i == idx then tabPanels[i]:Show()
            else             tabPanels[i]:Hide() end
        end
    end
    if cfgFrame then cfgFrame._activeTab = idx end
end

-- ── Layout helpers ────────────────────────────────────────────────────────────
local function AddRule(ct, y)
    local t = ct:CreateTexture(nil, "ARTWORK")
    t:SetHeight(1)
    if BigNoteBoxDB and BigNoteBoxDB.skinMode and BNB.GetSkinPreset then
        -- In skin mode, use the preset border colour so the rule reads on every
        -- theme (the fixed grey 0.25,0.25,0.28 disappears on lighter presets).
        -- Register so the rule recolours live on preset / brightness change.
        local p = BNB.GetSkinPreset()
        local br, bg_, bb = BNB.SkinBorderOf(p)
        t:SetColorTexture(br, bg_, bb, 0.9)
        if BNB.RegisterSkinRule then BNB.RegisterSkinRule(t, 0.9) end
    else
        t:SetColorTexture(0.25, 0.25, 0.28, 1)
    end
    t:SetPoint("TOPLEFT",  ct, "TOPLEFT",  0, y)
    t:SetPoint("TOPRIGHT", ct, "TOPRIGHT", 0, y)
    return y - 10
end

local function AddHeader(ct, y, text, r, g, b)
    local lbl = ct:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    lbl:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
    lbl:SetTextColor(r or 1, g or 0.82, b or 0)
    lbl:SetText(text)
    return y - 26
end

local function AddCheck(ct, y, text, getter, setter, tip)
    local cb = CreateFrame("CheckButton", nil, ct, "UICheckButtonTemplate")
    cb:SetSize(24, 24)
    cb:SetPoint("TOPLEFT", ct, "TOPLEFT", -2, y + 2)
    cb:SetChecked(getter())
    cb:SetScript("OnClick", function(self) setter(self:GetChecked() and true or false) end)
    if tip then
        cb:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(tip, 0.8, 0.8, 0.8, true); GameTooltip:Show()
        end)
        cb:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end
    local lbl = ct:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    lbl:SetPoint("LEFT",  cb,  "RIGHT", 4, 0)
    lbl:SetPoint("RIGHT", ct,  "RIGHT", 0, 0)
    lbl:SetJustifyH("LEFT"); lbl:SetHeight(ROW_H); lbl:SetText(text)
    return y - (ROW_H + ROW_GAP), cb   -- cb: for an overview-row twin (ALL-84)
end

-- Slider using BNB.CreateSlider.
-- Width is set explicitly to CONTENT_W so the value label never escapes.
-- We subtract an extra 4px to ensure it clears the scrollbar track even when
-- the bar is hidden (the 24px gap is in the scroll frame anchor, but the
-- content frame width CONTENT_W2 expands when bar hidden — so we use the
-- smaller CONTENT_W here unconditionally to be safe on both states).
local function AddSlider(ct, y, label, mn, mx, getter, setter, tip)
    local sl = BNB.CreateSlider(ct, label, mn, mx, getter(), nil, setter)
    sl:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
    sl:SetWidth(CONTENT_W)
    if tip then
        sl:EnableMouse(true)
        sl:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(tip, 0.8, 0.8, 0.8, true); GameTooltip:Show()
        end)
        sl:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end
    return y - (SLIDER_H + ROW_GAP)
end

-- ── Sub-pages (ALL-84) ────────────────────────────────────────────────────────
-- Runs the chrome's own tab select, which closes the sub-page.
local function ReselectTab(idx)
    if cfgFrame and cfgFrame._skinTabCtrl then cfgFrame._skinTabCtrl.Select(idx)
    else SelectTab(idx) end
end

local function OpenSubPage(page)
    CloseSubPage()
    if tabPanels[page.idx] then tabPanels[page.idx]:Hide() end
    page.sf:SetVerticalScroll(0)
    page.sf:Show()
    activeSub = page
    -- Both chromes disable the selected tab button; enable it so a click on
    -- the highlighted tab comes back. The next tab select disables it again.
    local ctrl = cfgFrame and cfgFrame._skinTabCtrl
    local btn  = (ctrl and ctrl.buttons[page.idx]) or tabBtns[page.idx]
    if btn then btn:SetEnabled(true) end
end

-- Only valid inside a tab builder: the page belongs to the tab being built.
-- title is the page heading, beside the back button. build(sf, ct, y, page)
-- fills it from y down and ends with sf:FinaliseHeight, like a tab builder;
-- a page with a master checkbox stores it as page.enableCb (see AddOverviewRow).
-- Returns the page; page.Open() shows it.
local function NewSubPage(title, build)
    local o = buildOwner
    local sf, ct = MakeScrollPanel(o.parent, o.topOffset)
    local page = { sf = sf, ct = ct, idx = o.idx }
    function page.Open() OpenSubPage(page) end

    -- Textured back arrow, same build as BNB.CreateSkinCloseButton; used in
    -- both chromes (the art is not skin-tinted).
    local back = CreateFrame("Button", nil, ct)
    back:SetSize(22, 22)
    back:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, -8)
    local n = back:CreateTexture(nil, "ARTWORK"); n:SetAllPoints()
    n:SetTexture(ASSET .. "Buttons\\bt-left-normal")
    local h = back:CreateTexture(nil, "ARTWORK"); h:SetAllPoints()
    h:SetTexture(ASSET .. "Buttons\\bt-left-hover"); h:Hide()
    local p = back:CreateTexture(nil, "ARTWORK"); p:SetAllPoints()
    p:SetTexture(ASSET .. "Buttons\\bt-left-press"); p:Hide()
    back:SetScript("OnClick",     function() ReselectTab(page.idx) end)
    back:SetScript("OnMouseDown", function() p:Show(); n:Hide(); h:Hide() end)
    back:SetScript("OnMouseUp",   function() p:Hide(); h:Show() end)
    back:SetScript("OnEnter", function(self)
        n:Hide(); h:Show()
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(L["CFG_SUBPAGE_BACK"], 1, 1, 1)
        GameTooltip:Show()
    end)
    back:SetScript("OnLeave", function() p:Hide(); h:Hide(); n:Show(); GameTooltip:Hide() end)
    -- The click hides the page under the pointer, so OnLeave may never come.
    sf:HookScript("OnShow", function() p:Hide(); h:Hide(); n:Show() end)

    local lbl = ct:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    lbl:SetPoint("LEFT", back, "RIGHT", 8, 0)
    lbl:SetTextColor(1, 0.82, 0)
    lbl:SetText(title)

    build(sf, ct, AddRule(ct, -38) - 4, page)
    return page
end

-- One overview row for a sub-page: [x] Title ... [Settings], a grey line
-- under it. When the page has an enableCb, the row gets a twin checkbox that
-- runs the page checkbox's own OnClick, so the two can never disagree.
-- sf is the tab's scroll panel (the twin re-reads its state on show).
-- A toggle-only module passes { get, set, tip } instead of a page: the row
-- gets a plain checkbox and no Settings button.
local function AddOverviewRow(ct, sf, y, page, title, desc)
    local TEXT_X = 26
    local cb = page.enableCb
    if page.get then
        local tg = CreateFrame("CheckButton", nil, ct, "UICheckButtonTemplate")
        tg:SetSize(24, 24)
        tg:SetPoint("TOPLEFT", ct, "TOPLEFT", -2, y + 2)
        tg:SetChecked(page.get())
        tg:SetScript("OnClick", function(self) page.set(self:GetChecked() and true or false) end)
        if page.tip then
            tg:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:AddLine(page.tip, 0.8, 0.8, 0.8, true); GameTooltip:Show()
            end)
            tg:SetScript("OnLeave", function() GameTooltip:Hide() end)
        end
    elseif cb then
        local ov = CreateFrame("CheckButton", nil, ct, "UICheckButtonTemplate")
        ov:SetSize(24, 24)
        ov:SetPoint("TOPLEFT", ct, "TOPLEFT", -2, y + 2)
        ov:SetChecked(cb:GetChecked())
        ov:SetScript("OnClick", function(self)
            cb:SetChecked(self:GetChecked())
            local fn = cb:GetScript("OnClick")
            if fn then fn(cb, "LeftButton") end
        end)
        ov:SetScript("OnEnter", cb:GetScript("OnEnter"))
        ov:SetScript("OnLeave", cb:GetScript("OnLeave"))
        sf:HookScript("OnShow", function() ov:SetChecked(cb:GetChecked()) end)
    end

    local open
    if page.Open then
        open = BNB.CreateButton(nil, ct, L["CFG_SUBPAGE_OPEN"], 90, 22)
        open:SetPoint("TOPRIGHT", ct, "TOPRIGHT", 0, y)
        open:SetScript("OnClick", page.Open)
    end

    local lbl = ct:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    lbl:SetPoint("LEFT",  ct,   "TOPLEFT", TEXT_X, y - 10)
    if open then lbl:SetPoint("RIGHT", open, "LEFT", -8, 0)
    else         lbl:SetPoint("RIGHT", ct,   "TOPRIGHT", 0, y - 10) end
    lbl:SetJustifyH("LEFT")
    lbl:SetText(title)

    local d = ct:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    d:SetPoint("TOPLEFT", ct, "TOPLEFT", TEXT_X, y - 24)
    d:SetWidth(CONTENT_W - TEXT_X); d:SetJustifyH("LEFT"); d:SetWordWrap(true)
    d:SetTextColor(0.65, 0.65, 0.65)
    d:SetText(desc)
    local h = d:GetStringHeight()
    d:SetHeight(h)
    return y - 24 - h - ROW_GAP - 6
end

-- ─────────────────────────────────────────────────────────────────────────────
-- FONT PICKER
-- ─────────────────────────────────────────────────────────────────────────────
-- ── LSM FONT DROPDOWN (Appearance tab + NoteConfig) ───────────────────────────
-- Builds a "Other Installed Fonts" header + WowStyle1DropdownTemplate dropdown.
-- parent     : the scroll content frame to attach to
-- y          : current y offset (top of next widget)
-- getChoice  : function() -> current font id/path or nil
-- setChoice  : function(idOrNil) -> applies the selection
-- Returns new y offset, a refresh function for the closed-state text, and the
-- header and control widgets (all three nil when nothing was built). The refresh
-- is returned, not stored, so each picker keeps its own (ALL-41): NoteConfig, the
-- sticky config and the New Note dialog build one too.

local function BuildLSMFontDropdown(parent, y, getChoice, setChoice, overrideW)
    local db = BigNoteBoxDB
    if not (db and db.lsmFonts) then return y end
    local W = overrideW or CONTENT_W

    -- Gather LSM entries from BNB.FONTS (populated by InitFonts if lsmFonts=true)
    local lsmFonts = {}
    for _, def in ipairs(BNB.FONTS or {}) do
        if def._isLSM then lsmFonts[#lsmFonts + 1] = def end
    end
    if #lsmFonts == 0 then return y end

    -- Section header
    local hdr = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hdr:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, y)
    hdr:SetTextColor(0.55, 0.55, 0.55)
    hdr:SetText(L["CFG_LSM_FONTS_OTHER"])
    y = y - 18

    local useDD = C_XMLUtil and C_XMLUtil.GetTemplateInfo
        and C_XMLUtil.GetTemplateInfo("WowStyle1DropdownTemplate")

    if useDD then
        local dd = CreateFrame("DropdownButton", nil, parent, "WowStyle1DropdownTemplate")
        dd:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, y)
        dd:SetWidth(W)
        dd:SetupMenu(function(_, root)
            local cur = getChoice()
            -- Reset option: clears any LSM override back to the bundled card selection
            root:CreateRadio(L["CFG_LSM_FONTS_NONE"],
                function()
                    local choice = getChoice()
                    if not choice then return true end
                    local def = BNB.GetFontDef and BNB.GetFontDef(choice)
                    return not (def and def._isLSM)
                end,
                function() setChoice(nil); dd:GenerateMenu() end)
            root:CreateDivider()
            for _, def in ipairs(lsmFonts) do
                local path = def.id
                root:CreateRadio(def.label,
                    function() return getChoice() == path end,
                    function() setChoice(path); dd:GenerateMenu() end)
            end
        end)
        return y - 28, function() dd:GenerateMenu() end, hdr, dd
    else
        -- Fallback: show current LSM selection as plain text with a cycle button
        local cur = getChoice()
        local curDef = cur and BNB.GetFontDef and BNB.GetFontDef(cur)
        local curLbl = (curDef and curDef._isLSM and curDef.label) or L["CFG_LSM_FONTS_NONE"]
        local cycleBtn = BNB.CreateButton(nil, parent, curLbl, W, 22)
        cycleBtn:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, y)
        cycleBtn:SetScript("OnClick", function()
            local curChoice = getChoice()
            local idx = 0
            for i, def in ipairs(lsmFonts) do
                if def.id == curChoice then idx = i; break end
            end
            local next = lsmFonts[(idx % #lsmFonts) + 1]
            if next then setChoice(next.id); cycleBtn:SetText(next.label) end
        end)
        local function refresh()
            local c  = getChoice()
            local cd = c and BNB.GetFontDef and BNB.GetFontDef(c)
            cycleBtn:SetText((cd and cd._isLSM and cd.label) or L["CFG_LSM_FONTS_NONE"])
        end
        return y - 28, refresh, hdr, cycleBtn
    end
end

-- Expose for NoteConfig.lua (local functions cannot cross file boundaries)
BNB._BuildLSMFontDropdown = BuildLSMFontDropdown

-- ─────────────────────────────────────────────────────────────────────────────
-- SHARED KEYBIND CAPTURE ROW
-- Used in General tab (Open BNB) and Advanced tab (New Note, Quick Note).
-- Left-click enters capture mode; right-click clears the binding.
-- Registers BNB_KEYBIND_CONFLICT StaticPopup once (guarded).
-- Returns the new y offset after the row.
-- ─────────────────────────────────────────────────────────────────────────────
local function MakeKeybindRow(parent, y, labelText, kbAction, defaultHint, tooltipVerb)
    local kbLabel = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    kbLabel:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, y + 2)
    kbLabel:SetText(labelText)

    local kbBtn = BNB.CreateButton(nil, parent, "", 130, 22)
    kbBtn:SetPoint("LEFT", kbLabel, "RIGHT", 8, 0)
    kbBtn:RegisterForClicks("AnyUp")

    local kbHint = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    kbHint:SetPoint("LEFT", kbBtn, "RIGHT", 8, 0)
    kbHint:SetTextColor(0.5, 0.5, 0.5)
    kbHint:SetText(defaultHint)

    local function UpdateText()
        local key = GetBindingKey(kbAction)
        kbBtn:SetText(key and GetBindingText(key) or L["KEYBIND_NOT_BOUND"])
    end
    UpdateText()

    parent:RegisterEvent("UPDATE_BINDINGS")
    parent:HookScript("OnEvent", function(_, event)
        if event == "UPDATE_BINDINGS" then UpdateText() end
    end)

    if not StaticPopupDialogs["BNB_SKIN_MODE_TOGGLE"] then
        StaticPopupDialogs["BNB_SKIN_MODE_TOGGLE"] = {
            text = "%s",
            button1 = L["CFG_RELOAD_NOW_BTN"],
            button2 = L["CFG_LATER_BTN"],
            timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
            OnAccept = function() C_UI.Reload() end,
        }
    end

    if not StaticPopupDialogs["BNB_BLZICON_AC_DISABLE"] then
        StaticPopupDialogs["BNB_BLZICON_AC_DISABLE"] = {
            text = L["CFG_BLZICON_DISABLED_MSG"],
            button1 = L["CFG_RELOAD_NOW_BTN"],
            button2 = L["CFG_LATER_BTN"],
            timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
            OnAccept = function() C_UI.Reload() end,
        }
    end

    BNB.WireKeybindCapture(kbBtn, kbAction, UpdateText, L["KEYBIND_PRESS_KEY"])

    kbBtn:SetScript("OnEnter", function(btn)
        GameTooltip:SetOwner(btn, "ANCHOR_RIGHT")
        local key = GetBindingKey(kbAction)
        if key then
            GameTooltip:AddLine(string.format("%s (%s)", tooltipVerb, GetBindingText(key)), 1,1,1)
            GameTooltip:AddLine(L["KEYBIND_TOOLTIP_UNBIND"], 0.6, 0.6, 0.6)
        else
            GameTooltip:AddLine(L["KEYBIND_TOOLTIP_SET"], 1, 1, 1)
        end
        GameTooltip:Show()
    end)
    kbBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    return y - (ROW_H + ROW_GAP)
end

-- ─────────────────────────────────────────────────────────────────────────────
-- CREATE WINDOW
-- ─────────────────────────────────────────────────────────────────────────────
-- Tab key -> builder(sf, ct). Empty here: every tab lives in its own file
-- under UI/Config/ (ALL-65.10), which loads after this one and adds itself.
-- Only read when the window is built.
local BUILDERS = {}

-- Shared with the tab files under UI/Config/.
local K = {
    CONTENT_W            = CONTENT_W,
    ROW_H                = ROW_H,
    ROW_GAP              = ROW_GAP,
    SLIDER_H             = SLIDER_H,
    ASSET                = ASSET,
    AddRule              = AddRule,
    AddHeader            = AddHeader,
    AddCheck             = AddCheck,
    AddSlider            = AddSlider,
    MakeKeybindRow       = MakeKeybindRow,
    BuildLSMFontDropdown = BuildLSMFontDropdown,
    NewSubPage           = NewSubPage,
    AddOverviewRow       = AddOverviewRow,
    BUILDERS             = BUILDERS,
    -- RefreshFontPicker: set by UI/Config/Appearance.lua
}
BNB._ConfigKit = K

local function GetTargetHeight()
    -- Track the main note window height exactly (same min/max as main window).
    -- Fall back to 75% of screen when main window isn't available.
    if BNB.mainFrame then
        local h = BNB.mainFrame:GetHeight()
        -- GetHeight() returns 0 before layout; use saved value or screen fallback
        if h and h > 100 then
            return math.min(h, 900)
        end
    end
    return math.min(math.max(math.floor(UIParent:GetHeight() * 0.75), 400), 900)
end

-- Exposed for MainConfigSkin.lua
BNB._GetConfigTargetHeight = GetTargetHeight

-- Font refresh helper — called on window show (both chrome variants) and on
-- Appearance tab show. The deferred second pass covers the case where WoW's
-- font renderer hasn't yet cached the .ttf files on the current frame.
local function RefreshConfigFonts()
    local refresh = K.RefreshFontPicker
    if not refresh then return end
    refresh()
    C_Timer.After(0.1, refresh)
end
BNB._RefreshConfigFonts = RefreshConfigFonts

--------------------------------------------------------------------------------
-- SHARED TAB PANEL BUILDER
-- Builds the six scroll panels, runs each tab's builder, wires the Appearance
-- tab's font refresh hook. Called by both CreateConfigWindow (classic chrome)
-- and BNB.CreateConfigWindowSkin (skin chrome in MainConfigSkin.lua).
--
-- parent    : window frame to parent panels to
-- topOffset : distance from top of parent to top of scroll frames (pixels)
--
-- Returns (panels, contents) arrays — callers store these locally.
-- Also populates module-level tabPanels/tabContent so legacy code and the
-- SelectTab helper keep working for the classic chrome.
--------------------------------------------------------------------------------
function BNB._BuildConfigTabPanels(parent, topOffset)
    local panels   = {}
    local contents = {}
    for i, tab in ipairs(TABS) do
        local sf, ct = MakeScrollPanel(parent, topOffset)
        panels[i]   = sf
        contents[i] = ct
        -- Mirror into module-level tables so the classic SelectTab still works.
        tabPanels[i]  = sf
        tabContent[i] = ct
        local builder = BUILDERS[tab.key]
        buildOwner = { parent = parent, topOffset = topOffset, idx = i }
        if builder then builder(sf, ct) end
    end
    buildOwner = nil

    -- Re-apply font TTF paths whenever the Appearance tab is shown.
    -- The picker labels are built at BuildAppearanceTab time; if the renderer
    -- hasn't registered the .ttf files yet (first session, fast login) they
    -- render blank. Hooking OnShow guarantees the paths are re-set when the
    -- tab becomes visible, by which point PLAYER_LOGIN + InitFonts have run.
    for i, tab in ipairs(TABS) do
        if tab.key == "appearance" then panels[i]:HookScript("OnShow", RefreshConfigFonts) end
    end

    return panels, contents
end

local function CreateConfigWindow()
    local cfgH = GetTargetHeight()

    local f = CreateFrame("Frame", "BigNoteBoxConfigFrame", UIParent, "ButtonFrameTemplate")
    f:SetSize(CFG_W, cfgH)
    f:SetPoint("CENTER")
    f:SetToplevel(true); f:EnableMouse(true); f:SetMovable(true); f:SetClampedToScreen(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) self:StartMoving() end)
    f:SetScript("OnDragStop",  function(self) self:StopMovingOrSizing() end)

    ButtonFrameTemplate_HidePortrait(f)
    ButtonFrameTemplate_HideButtonBar(f)
    if f.Inset then f.Inset:Hide() end
    BNB.SeatChrome(f)   -- FOR-05: Forever border offset (UI/Chrome.lua)
    f._forGlow = BNB.AddForeverGlow(f, f.Bg)   -- Forever: glow over the wood grain
    f:SetAlpha(0.95)
    f:SetTitle(L["CONFIG_TITLE"])
    if f.CloseButton then
        f.CloseButton:SetScript("OnClick", function() f:Hide() end)
    end
    -- ESC is handled by the main window's OnKeyDown chain — do not add to UISpecialFrames

    -- ── Tabs ──────────────────────────────────────────────────────────────────
    local tpl = (C_XMLUtil and C_XMLUtil.GetTemplateInfo
        and C_XMLUtil.GetTemplateInfo("PanelTopTabButtonTemplate"))
        and "PanelTopTabButtonTemplate"
        or  "PanelTabButtonTemplate"

    local lastBtn = nil
    for i, tab in ipairs(TABS) do
        local btn = CreateFrame("Button", "BigNoteBoxCfgTab"..i, f, tpl)
        btn:SetText(tab.label())
        pcall(function()
            if tpl == "PanelTopTabButtonTemplate" then
                PanelTemplates_TabResize(btn, 15, nil, 70)
            else
                PanelTemplates_TabResize(btn, 0)
            end
        end)
        btn:SetID(i)
        if lastBtn then btn:SetPoint("LEFT", lastBtn, "RIGHT", 5, 0)
        else             btn:SetPoint("TOPLEFT", f, "TOPLEFT", 7, -25) end
        btn:SetScript("OnClick", function(self) SelectTab(self:GetID()) end)
        tabBtns[i] = btn
        lastBtn    = btn
    end

    -- Build the six scroll panels and their content (shared with skin chrome)
    BNB._BuildConfigTabPanels(f, TITLE_H + TAB_BAR_H)

    PanelTemplates_SetNumTabs(f, NUM_TABS)
    f.numTabs = NUM_TABS

    f:Hide()
    return f
end

-- ── Height tracking — follow the main window ──────────────────────────────────
local function SyncConfigHeight()
    if not cfgFrame or not cfgFrame:IsShown() then return end
    local h = GetTargetHeight()
    if math.abs(cfgFrame:GetHeight() - h) > 2 then
        cfgFrame:SetHeight(h)
    end
end

-- Hook called after main window is built (from OpenConfig or externally)
function BNB.HookConfigHeightTracking()
    if BNB._configHeightHooked then return end
    BNB._configHeightHooked = true
    if BNB.mainFrame then
        BNB.mainFrame:HookScript("OnSizeChanged", SyncConfigHeight)
        BNB.mainFrame:HookScript("OnShow",        SyncConfigHeight)
    end
end

-- ─────────────────────────────────────────────────────────────────────────────
-- PUBLIC API
-- ─────────────────────────────────────────────────────────────────────────────
function BNB.OpenConfig()
    if InCombatLockdown() then BNB:Print(L["COMBAT_BLOCKED"]); return end

    if not cfgFrame then
        -- Chrome is chosen once per session — toggling skinMode requires a reload,
        -- so there's no need to re-create the frame if the setting changes mid-run.
        if BigNoteBoxDB and BigNoteBoxDB.skinMode and BNB.CreateConfigWindowSkin then
            cfgFrame = BNB.CreateConfigWindowSkin()
        else
            cfgFrame = CreateConfigWindow()
        end
        BNB.HookConfigHeightTracking()
        -- A sub-page never outlives the window (ALL-84); reopening shows its tab.
        cfgFrame:HookScript("OnHide", CloseSubPage)
        -- Report-a-bug button beside Settings (Retail; ALL-77)
        if BNB.AttachSettingsBugButton then pcall(BNB.AttachSettingsBugButton, cfgFrame) end
    end

    if cfgFrame:IsShown() then cfgFrame:Hide(); return end

    -- Sync height to main window before showing
    cfgFrame:SetHeight(GetTargetHeight())

    RefreshConfigFonts()

    -- Tab selection — skin chrome uses its own CreateSkinTabs controller,
    -- classic chrome uses the PanelTemplates SelectTab flow.
    local activeIdx = cfgFrame._activeTab or 1
    if cfgFrame._skinTabCtrl then
        cfgFrame._skinTabCtrl.Select(activeIdx)
    else
        SelectTab(activeIdx)
    end

    cfgFrame:Show()

    -- Position next to main window if visible, else centre
    if BNB.mainFrame and BNB.mainFrame:IsShown() then
        cfgFrame:ClearAllPoints()
        cfgFrame:SetPoint("TOPLEFT", BNB.mainFrame, "TOPRIGHT", 8, 0)
    end
end

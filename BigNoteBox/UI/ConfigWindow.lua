-- BigNoteBox UI/ConfigWindow.lua -- Settings window
--
-- Six tabs: General | Appearance | Features | Editor | Backup | Advanced
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
    { key = "appearance", label = function() return L["CFG_TAB_APPEARANCE"] end },
    { key = "features",   label = function() return L["CFG_TAB_FEATURES"]   end },
    { key = "editor",     label = function() return L["CFG_TAB_EDITOR"]     end },
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
    local sf  = CreateFrame("ScrollFrame", nil, parent, "ScrollFrameTemplate")
    local bar = sf.ScrollBar
    if bar then bar:SetAlpha(0) end

    -- Always leave 24px on the right for the scrollbar track.
    sf:SetPoint("TOPLEFT",     parent, "TOPLEFT",      PAD,  -topOffset)
    sf:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -24,   4)

    local ct = CreateFrame("Frame", nil, sf)
    ct:SetWidth(CONTENT_W)
    ct:SetHeight(1)
    sf:SetScrollChild(ct)

    -- Stored content height so we can re-evaluate on resize / show
    local _contentH = 0

    local function ApplyScrollbar()
        local sfH = sf:GetHeight()
        -- GetHeight() returns 0 before the frame is laid out; skip until ready
        if sfH < 4 then return end
        ct:SetHeight(math.max(_contentH, sfH))
        if _contentH <= sfH + 2 then
            if bar then bar:SetAlpha(0) end
            ct:SetWidth(CONTENT_W2)
        else
            if bar then bar:SetAlpha(1) end
            ct:SetWidth(CONTENT_W)
        end
    end

    -- Re-evaluate whenever the scroll frame is resized (window resize / height sync)
    sf:SetScript("OnSizeChanged", function() ApplyScrollbar() end)
    -- Re-evaluate when shown (first open, tab switch)
    sf:HookScript("OnShow", function() C_Timer.After(0.05, ApplyScrollbar) end)

    function sf:FinaliseHeight(contentH)
        _contentH = contentH
        -- Defer one frame so the scroll frame has been laid out and GetHeight() is valid
        C_Timer.After(0.05, ApplyScrollbar)
    end

    sf:Hide()
    return sf, ct
end

-- ── Tab selector ──────────────────────────────────────────────────────────────
local function SelectTab(idx)
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
    return y - (ROW_H + ROW_GAP)
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

-- ─────────────────────────────────────────────────────────────────────────────
-- FONT PICKER
-- ─────────────────────────────────────────────────────────────────────────────
local fontPickerBtns = {}

-- ── LSM FONT DROPDOWN (Appearance tab + NoteConfig) ───────────────────────────
-- Builds a "Other Installed Fonts" header + WowStyle1DropdownTemplate dropdown.
-- parent     : the scroll content frame to attach to
-- y          : current y offset (top of next widget)
-- getChoice  : function() -> current font id/path or nil
-- setChoice  : function(idOrNil) -> applies the selection
-- Returns new y offset.
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
        y = y - 28
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
        y = y - 28
    end

    return y
end

-- Expose for NoteConfig.lua (local functions cannot cross file boundaries)
BNB._BuildLSMFontDropdown = BuildLSMFontDropdown

local _refreshFontHL     = nil
local _refreshFontLabels = nil   -- re-applies TTF paths after renderer is ready

local function BuildFontPicker(ct, y)
    local PICKER_H = 48
    local GAP      = 4    -- vertical gap between rows
    local COL_GAP  = 6    -- horizontal gap between columns
    local CARD_W   = math.floor((CONTENT_W - COL_GAP) / 2)
    -- LSM fonts are shown in the dropdown below; exclude them from the card grid.
    local _allFonts = BNB.FONTS or {}
    local fonts = {}
    for _, def in ipairs(_allFonts) do
        if not def._isLSM then fonts[#fonts + 1] = def end
    end
    fontPickerBtns = {}

    local function Highlight()
        local cur = BigNoteBoxDB and BigNoteBoxDB.fontChoice or "notoserif"
        for _, e in ipairs(fontPickerBtns) do
            if e.id == cur then
                e.btn:SetBackdropColor(0.12, 0.18, 0.12, 0.95)
                e.btn:SetBackdropBorderColor(0.4, 0.8, 0.4, 1)
                if e.nameLbl then e.nameLbl:SetTextColor(1, 0.82, 0, 1) end
            else
                e.btn:SetBackdropColor(0.06, 0.06, 0.08, 0.95)
                e.btn:SetBackdropBorderColor(0.28, 0.28, 0.30, 1)
                if e.nameLbl then e.nameLbl:SetTextColor(0.85, 0.85, 0.85, 1) end
            end
        end
    end
    _refreshFontHL = Highlight

    -- Re-applies TTF paths to all picker label FontStrings.
    -- Called on Appearance tab OnShow so the renderer is guaranteed ready.
    local function RefreshFontLabels()
        for _, e in ipairs(fontPickerBtns) do
            if e.def then
                if e.nameLbl then
                    if e.def.bold and e.def.bold ~= "" then
                        pcall(function() e.nameLbl:SetFont(e.def.bold, 13, "") end)
                    end
                end
                if e.prevLbl then
                    if e.def.regular and e.def.regular ~= "" then
                        pcall(function() e.prevLbl:SetFont(e.def.regular, 11, "") end)
                    end
                end
            end
        end
    end
    _refreshFontLabels = RefreshFontLabels

    for i, def in ipairs(fonts) do
        local col     = (i - 1) % 2
        local gridRow = math.floor((i - 1) / 2)
        local xOff    = col * (CARD_W + COL_GAP)
        local yOff    = y - gridRow * (PICKER_H + GAP)

        local btn = BNB.CreateBackdropFrame("Button", nil, ct)
        BNB.SetBackdrop(btn, 0.06, 0.06, 0.08, 0.95, 0.28, 0.28, 0.30, 1)
        btn:SetSize(CARD_W, PICKER_H)
        btn:SetPoint("TOPLEFT", ct, "TOPLEFT", xOff, yOff)
        btn:EnableMouse(true)

        btn:SetScript("OnEnter", function(self)
            if (BigNoteBoxDB and BigNoteBoxDB.fontChoice or "notoserif") ~= def.id then
                self:SetBackdropColor(0.10, 0.12, 0.10, 0.95)
                self:SetBackdropBorderColor(0.35, 0.55, 0.35, 1)
            end
        end)
        btn:SetScript("OnLeave", Highlight)
        btn:SetScript("OnClick", function() BNB.ApplyFont(def.id, nil); Highlight() end)

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
        prevLbl:SetTextColor(0.62, 0.62, 0.62); prevLbl:SetText(def.preview or "")

        fontPickerBtns[#fontPickerBtns + 1] = { btn=btn, id=def.id, nameLbl=nameLbl, prevLbl=prevLbl, def=def }
    end

    -- Advance y past the full grid
    local gridRows = math.ceil(#fonts / 2)
    Highlight()
    return y - gridRows * (PICKER_H + GAP) - 4
end

-- ─────────────────────────────────────────────────────────────────────────────
-- SHARED KEYBIND CAPTURE ROW
-- Used in General tab (Open BNB) and Advanced tab (New Note, Quick Note).
-- Left-click enters capture mode; right-click clears the binding.
-- Registers BNB_KEYBIND_CONFLICT StaticPopup once (guarded).
-- Returns the new y offset after the row.
-- ─────────────────────────────────────────────────────────────────────────────
local _KB_MODIFIER_KEYS = {
    LSHIFT=true, RSHIFT=true, LCTRL=true, RCTRL=true, LALT=true, RALT=true,
}
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

    local function StopCapture(btn)
        btn:EnableKeyboard(false); btn:SetScript("OnKeyDown", nil); UpdateText()
    end

    local function ApplyBind(fullKey)
        local k1, k2 = GetBindingKey(kbAction)
        if k1 then SetBinding(k1, nil) end
        if k2 then SetBinding(k2, nil) end
        SetBinding(fullKey, kbAction)
        SaveBindings(GetCurrentBindingSet())
        UpdateText()
    end

    if not StaticPopupDialogs["BNB_KEYBIND_CONFLICT"] then
        StaticPopupDialogs["BNB_KEYBIND_CONFLICT"] = {
            text = "%s", button1 = YES, button2 = NO,
            timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
            OnAccept = function(_, data) if data then ApplyBind(data.fullKey) end end,
        }
    end

    if not StaticPopupDialogs["BNB_SKIN_MODE_TOGGLE"] then
        StaticPopupDialogs["BNB_SKIN_MODE_TOGGLE"] = {
            text = "%s",
            button1 = "Reload Now",
            button2 = "Later",
            timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
            OnAccept = function() C_UI.Reload() end,
        }
    end

    local function OnKeyCaptured(btn, key)
        if _KB_MODIFIER_KEYS[key] then return end
        if key == "ESCAPE" or InCombatLockdown() then StopCapture(btn); return end
        local mods = {}
        if IsAltKeyDown()     then mods[#mods+1] = "ALT"   end
        if IsControlKeyDown() then mods[#mods+1] = "CTRL"  end
        if IsShiftKeyDown()   then mods[#mods+1] = "SHIFT" end
        mods[#mods+1] = key
        local fullKey = table.concat(mods, "-")
        StopCapture(btn)
        local existing = GetBindingAction(fullKey)
        if existing and existing ~= "" and existing ~= kbAction then
            local msg = string.format(L["KEYBIND_CONFLICT"],
                GetBindingText(fullKey), GetBindingName(existing))
            StaticPopup_Show("BNB_KEYBIND_CONFLICT", msg, nil, { fullKey = fullKey })
            return
        end
        ApplyBind(fullKey)
    end

    kbBtn:SetScript("OnClick", function(btn, button)
        if button == "RightButton" then
            local k1, k2 = GetBindingKey(kbAction)
            if k1 then SetBinding(k1, nil) end
            if k2 then SetBinding(k2, nil) end
            if k1 or k2 then SaveBindings(GetCurrentBindingSet()) end
            UpdateText(); GameTooltip:Hide()
        else
            btn:SetText(L["KEYBIND_PRESS_KEY"])
            btn:EnableKeyboard(true)
            btn:SetScript("OnKeyDown", OnKeyCaptured)
        end
    end)
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
-- TAB 1 — GENERAL
-- Logo, version, by-line, 2×2 feature grid, solidarity line
-- ─────────────────────────────────────────────────────────────────────────────
local function BuildGeneralTab(sf, ct)
    local y = -8

    -- Logo
    local logo = ct:CreateTexture(nil, "ARTWORK")
    logo:SetSize(80, 80)
    logo:SetPoint("TOP", ct, "TOP", 0, y)
    logo:SetTexture(ASSET .. "logo")
    y = y - 88

    -- Title
    local title = ct:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge3")
    title:SetPoint("TOP", ct, "TOP", 0, y)
    title:SetText("|cff66bb6aBigNoteBox|r")
    y = y - 26

    -- Version button — skin button style on both modes so it reads as clickable.
    -- Opens the What's New window without the overlay.
    local verText = "v" .. (BNB.ADDON_VERSION or "1.0.0")
    local ver = BNB.CreateButton(nil, ct, verText, 100, 22)
    ver:SetPoint("TOP", ct, "TOP", 0, y)
    ver:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetText(L["WHATS_NEW_VERSION_TIP"], nil, nil, nil, nil, true)
        GameTooltip:Show()
    end)
    ver:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    ver:SetScript("OnClick", function()
        if BNB.WhatsNew and BNB.WhatsNew.Open then
            BNB.WhatsNew.Open(false)
        end
    end)
    y = y - 28

    -- By-line
    local byLine = ct:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    byLine:SetPoint("TOP", ct, "TOP", 0, y)
    byLine:SetText("by Dukul")
    byLine:SetTextColor(0.55, 0.55, 0.55)
    y = y - 28

    -- 2×2 feature grid
    local cellGap = 12
    local cellW   = math.floor((CONTENT_W - cellGap) / 2)
    local cellX2  = cellW + cellGap

    local function Cell(xOff, yOff, hdr, desc)
        local h = ct:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        h:SetPoint("TOPLEFT", ct, "TOPLEFT", xOff, yOff)
        h:SetWidth(cellW); h:SetJustifyH("LEFT")
        h:SetTextColor(1, 0.82, 0, 1); h:SetText(hdr)

        local d = ct:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
        d:SetPoint("TOPLEFT", ct, "TOPLEFT", xOff, yOff - 18)
        d:SetWidth(cellW); d:SetJustifyH("LEFT")
        d:SetWordWrap(true); d:SetSpacing(2)
        d:SetTextColor(0.75, 0.75, 0.75); d:SetText(desc)
        return d:GetStringHeight() + 22
    end

    local h1 = Cell(0,      y, "Notes & Organization", "Create, search, tag and organize notes.\nPin, favourite, drag-reorder and sort.")
    local h2 = Cell(cellX2, y, "Tags & Trash",          "Tag notes for instant filtering.\nDeleted notes go to Trash, restored any time.")
    y = y - math.max(h1, h2) - 10

    local bcbLabel = "BCB Integration"
    if BigChatBox and BigChatBox.SendDirect then
        bcbLabel = bcbLabel .. " |cff66bb6a(INSTALLED)|r"
        local h3 = Cell(0, y, bcbLabel, "Send notes line-by-line via BigChatBox.\nCapture chat input as new notes.")
        local h4 = Cell(cellX2, y, "Contextual Surfacing",  "Notes surface automatically by zone,\ninstance or player name.")
        y = y - math.max(h3, h4) - 10
    else
        -- BCB not installed: draw the header manually so we can add a clickable badge
        local hdr = ct:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        hdr:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
        hdr:SetWidth(cellW); hdr:SetJustifyH("LEFT")
        hdr:SetTextColor(1, 0.82, 0, 1); hdr:SetText(bcbLabel)

        -- (NOT INSTALLED) button — small, blue, sits right of the header text
        local notInstBtn = CreateFrame("Button", nil, ct)
        notInstBtn:SetSize(96, 16)
        notInstBtn:SetPoint("LEFT", hdr, "LEFT", hdr:GetStringWidth() + 6, 0)
        local notInstLbl = notInstBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        notInstLbl:SetAllPoints()
        notInstLbl:SetJustifyH("LEFT")
        notInstLbl:SetText("|cff4fc3f7(NOT INSTALLED)|r")
        notInstBtn:SetScript("OnClick", function()
            if BNB.ShowBCBPromo then BNB.ShowBCBPromo() end
        end)
        notInstBtn:SetScript("OnEnter", function(self)
            notInstLbl:SetText("|cff81d4fa(NOT INSTALLED)|r")
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:AddLine("Get BigChatBox", 1, 1, 1)
            GameTooltip:AddLine("Click to find out more.", 0.78, 0.78, 0.78)
            GameTooltip:Show()
        end)
        notInstBtn:SetScript("OnLeave", function()
            notInstLbl:SetText("|cff4fc3f7(NOT INSTALLED)|r")
            GameTooltip:Hide()
        end)

        local desc3 = ct:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
        desc3:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y - 18)
        desc3:SetWidth(cellW); desc3:SetJustifyH("LEFT")
        desc3:SetWordWrap(true); desc3:SetSpacing(2)
        desc3:SetTextColor(0.75, 0.75, 0.75)
        desc3:SetText("Send notes line-by-line via BigChatBox.\nCapture chat input as new notes.")
        local h3 = desc3:GetStringHeight() + 22

        local h4 = Cell(cellX2, y, "Contextual Surfacing", "Notes surface automatically by zone,\ninstance or player name.")
        y = y - math.max(h3, h4) - 10
    end

    -- Row 3: Sticky Notes (left) + More Features button (right)
    -- The button matches the height of the left cell. Since GetStringHeight()
    -- returns 0 at build time, we use a deferred resize via C_Timer.After(0).
    local h5 = Cell(0, y, "Sticky Notes",
        "Float notes anywhere on screen.\nPer-note font, color, size and border.\nSet time-based alarms on any note.")

    -- More Features button — same template trychain as OptionsPanel and WhatsNew OK button
    local moreTpl = "SharedButtonLargeTemplate"
    if not (C_XMLUtil and C_XMLUtil.GetTemplateInfo and C_XMLUtil.GetTemplateInfo(moreTpl)) then
        moreTpl = "UIPanelDynamicResizeButtonTemplate"
    end
    if not (C_XMLUtil and C_XMLUtil.GetTemplateInfo and C_XMLUtil.GetTemplateInfo(moreTpl)) then
        moreTpl = "UIPanelButtonTemplate"
    end
    local moreBtn
    if BigNoteBoxDB and BigNoteBoxDB.skinMode then
        moreBtn = BNB.CreateSkinButton(nil, ct, "More Features", cellW, 38)
    else
        moreBtn = CreateFrame("Button", nil, ct, moreTpl)
        moreBtn:SetWidth(cellW)
        pcall(function() DynamicResizeButton_Resize(moreBtn) end)
        moreBtn:SetText("More Features")
    end
    moreBtn:SetPoint("TOPLEFT", ct, "TOPLEFT", cellX2, y)
    moreBtn:SetScript("OnClick", function()
        if BNB.FeatureList then BNB.FeatureList.Open() end
    end)
    moreBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Features in BigNoteBox", 1, 0.82, 0)
        GameTooltip:AddLine("See everything BigNoteBox can do.", 0.78, 0.78, 0.78)
        GameTooltip:Show()
    end)
    moreBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- In skin mode, defer height match to the left cell after layout resolves.
    -- In normal mode the template height is natural and should not be overridden.
    if BigNoteBoxDB and BigNoteBoxDB.skinMode then
        C_Timer.After(0, function()
            if not ct or not moreBtn then return end
            local targetH = math.max(h5, 38)
            moreBtn:SetHeight(targetH)
        end)
    end

    y = y - math.max(h5, 38) - 10

    -- ── Keybindings section ───────────────────────────────────────────────────
    y = AddRule(ct, y) - 4
    y = AddHeader(ct, y, "Keybindings")

    y = MakeKeybindRow(ct, y, L["CFG_KB_OPEN_BNB"], "BIGNOTEBOXOPEN", "(Default: Ctrl+N)", "Open / close BigNoteBox")

    -- ── Data Summary section ──────────────────────────────────────────────────
    y = AddRule(ct, y) - 4
    y = AddHeader(ct, y, "Data Summary")

    -- Compute stats from live notes DB
    local noteCount    = 0
    local totalBytes   = 0
    local largestBytes = 0
    local trashCount   = 0
    local ndb = BigNoteBoxNotesDB
    if ndb then
        if ndb.notes then
            for _, note in pairs(ndb.notes) do
                noteCount = noteCount + 1
                local sz  = #(note.title or "") + #(note.body or "")
                totalBytes = totalBytes + sz
                if sz > largestBytes then largestBytes = sz end
            end
        end
        if ndb.trash then
            for _ in pairs(ndb.trash) do trashCount = trashCount + 1 end
        end
    end

    local function fmtSize(bytes)
        if bytes >= 1024 * 1024 then
            return string.format("%.1f MB", bytes / (1024 * 1024))
        elseif bytes >= 1024 then
            return string.format("%.1f KB", bytes / 1024)
        else
            return bytes .. " B"
        end
    end

    local avgBytes  = noteCount > 0 and (totalBytes / noteCount) or 0
    local histBytes = BNB.HistoryTotalSize and BNB.HistoryTotalSize() or 0

    local GREEN = "|cff66bb6a"
    local GREY  = "|cffaaaaaa"
    local RESET = "|r"
    local SZ    = 14   -- inline icon size

    local ICO_N = ASSET .. "Icons\\Notes\\INV_Misc_Note_01"  -- note count
    local ICO_S = "Interface\\Icons\\INV_Misc_Coin_01"       -- total size
    local ICO_A = "Interface\\Icons\\Trade_Engineering"      -- average
    local ICO_L = "Interface\\Icons\\INV_Scroll_06"          -- largest
    local ICO_T = "Interface\\Icons\\inv_misc_1h_bucket_b_01"-- trash
    local ICO_H = "Interface\\Icons\\ability_spy"            -- history

    -- 3-column grid, 2 rows — compact single-line-height rows with no row gap
    local NCOLS = 3
    local COL   = math.floor(CONTENT_W / NCOLS)
    local STAT_H = 18  -- single row height, no extra gap between rows

    local stats = {
        { icon = ICO_N, label = "Notes",        value = noteCount .. " notes" },
        { icon = ICO_S, label = "Total size",   value = fmtSize(totalBytes) },
        { icon = ICO_A, label = "Average size", value = fmtSize(avgBytes) },
        { icon = ICO_L, label = "Largest note", value = fmtSize(largestBytes) },
        { icon = ICO_T, label = "In trash",     value = trashCount .. " notes" },
        { icon = ICO_H, label = "History size", value = fmtSize(histBytes) },
    }

    for i, s in ipairs(stats) do
        local col  = (i - 1) % NCOLS
        local row  = math.floor((i - 1) / NCOLS)
        local xOff = col * COL
        local yOff = y - row * STAT_H

        local lbl = ct:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        lbl:SetPoint("TOPLEFT", ct, "TOPLEFT", xOff, yOff)
        lbl:SetWidth(COL - 4)
        lbl:SetJustifyH("LEFT")
        lbl:SetText(
            "|T" .. s.icon .. ":" .. SZ .. "|t " ..
            GREY .. s.label .. ": " .. RESET ..
            GREEN .. s.value .. RESET
        )
    end

    local numRows = math.ceil(#stats / NCOLS)
    y = y - numRows * STAT_H

    -- Content ends here. Solidarity line + rule go at the very bottom of the
    -- scroll area, anchored to the BOTTOM of the content frame so they stay
    -- at the foot of the scrollable region regardless of window height.
    local SOL_H = 36   -- rule(1) + gap(8) + text(~18) + padding

    -- Finalise the scroll height based on the content above
    local contentH = math.abs(y) + SOL_H + 12
    sf:FinaliseHeight(contentH)

    -- Now anchor solidarity items to the BOTTOM of the content frame
    local rule = ct:CreateTexture(nil, "ARTWORK")
    rule:SetHeight(1)
    if BigNoteBoxDB and BigNoteBoxDB.skinMode and BNB.GetSkinPreset then
        local p = BNB.GetSkinPreset()
        local br, bg_, bb = BNB.SkinBorderOf(p)
        rule:SetColorTexture(br, bg_, bb, 0.9)
        if BNB.RegisterSkinRule then BNB.RegisterSkinRule(rule, 0.9) end
    else
        rule:SetColorTexture(0.25, 0.25, 0.28, 1)
    end
    rule:SetPoint("BOTTOMLEFT",  ct, "BOTTOMLEFT",  0, SOL_H - 1)
    rule:SetPoint("BOTTOMRIGHT", ct, "BOTTOMRIGHT", 0, SOL_H - 1)

    local sol = ct:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    sol:SetPoint("BOTTOM", ct, "BOTTOM", 0, 8)
    sol:SetWidth(CONTENT_W); sol:SetJustifyH("CENTER")
    sol:SetTextColor(0.85, 0.85, 0.85)
    sol:SetText(
        "LGBTQIA+ |T" .. ASSET .. "Flags\\flag-pride:14:20|t Pride  \226\128\148" ..
        "  Trans |T" .. ASSET .. "Flags\\flag-trans:14:20|t Rights  \226\128\148" ..
        "  Slava |T" .. ASSET .. "Flags\\flag-ua:14:20|t Ukraini  \226\128\148" ..
        "  Free |T" .. ASSET .. "Flags\\flag-ps:14:20|t Palestine"
    )
end

-- ─────────────────────────────────────────────────────────────────────────────
-- TAB 2 — APPEARANCE
-- ─────────────────────────────────────────────────────────────────────────────
local function BuildAppearanceTab(sf, ct)
    local db = BigNoteBoxDB
    local y  = -8

    -- ── Skins ─────────────────────────────────────────────────────────────────
    y = AddHeader(ct, y, "Skins")

    local skinDesc = ct:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    skinDesc:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
    skinDesc:SetWidth(CONTENT_W); skinDesc:SetJustifyH("LEFT")
    skinDesc:SetWordWrap(true); skinDesc:SetHeight(28)
    skinDesc:SetTextColor(0.60, 0.60, 0.60)
    skinDesc:SetText("Replaces the default window with a fully custom dark-themed frame. Requires a reload to activate or deactivate.")
    y = y - 32

    -- Enable skin mode checkbox
    local skinCb = CreateFrame("CheckButton", nil, ct, "UICheckButtonTemplate")
    skinCb:SetSize(24, 24)
    skinCb:SetPoint("TOPLEFT", ct, "TOPLEFT", -2, y + 2)
    skinCb:SetChecked(db.skinMode == true)

    local skinCbLbl = ct:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    skinCbLbl:SetPoint("LEFT", skinCb, "RIGHT", 4, 0)
    skinCbLbl:SetJustifyH("LEFT"); skinCbLbl:SetHeight(ROW_H)
    skinCbLbl:SetText("Enable skin mode")

    skinCb:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Enable skin mode", 1, 1, 1)
        GameTooltip:AddLine("Switches the main window to a custom backdrop frame.\nA reload is required to take effect.", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    skinCb:SetScript("OnLeave", function() GameTooltip:Hide() end)

    y = y - (ROW_H + ROW_GAP)

    -- Preset dropdown (only active when skin mode is enabled)
    local SKIN_PRESETS = {
        { key = "obsidian",   label = "Obsidian  (neutral dark)"  },
        { key = "void",       label = "Void  (purple)"            },
        { key = "dragonfire", label = "Dragonfire  (red)"         },
        { key = "arcane",     label = "Arcane  (pink)"            },
        { key = "fel",        label = "Fel  (green)"              },
        { key = "titan",      label = "Titan  (gold)"             },
        { key = "icecrown",   label = "Icecrown  (blue)"          },
        { key = "holy",       label = "Holy  (warm yellow)"       },
        { key = "azshara",    label = "Azshara  (teal)"           },
        { key = "ragnaros",   label = "Ragnaros  (orange)"        },
        { key = "earthen",    label = "Earthen  (brown)"          },
        { key = "argent",     label = "Argent  (silver)"          },
        { key = "oled",       label = "OLED  (pure black)"        },
    }

    local function CurrentPresetLabel()
        local cur = db.skinPreset or "obsidian"
        for _, p in ipairs(SKIN_PRESETS) do
            if p.key == cur then return p.label end
        end
        return SKIN_PRESETS[1].label
    end

    local skinPresetLbl = ct:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    skinPresetLbl:SetPoint("TOPLEFT", ct, "TOPLEFT", 18, y)
    skinPresetLbl:SetHeight(ROW_H); skinPresetLbl:SetJustifyH("LEFT")
    skinPresetLbl:SetText("Skin preset")
    y = y - (ROW_H + 2)

    local useNativeSkinDrop = C_XMLUtil and C_XMLUtil.GetTemplateInfo
        and C_XMLUtil.GetTemplateInfo("WowStyle1DropdownTemplate")

    local skinPresetDD, skinPresetCycleBtn

    if useNativeSkinDrop then
        skinPresetDD = CreateFrame("DropdownButton", nil, ct, "WowStyle1DropdownTemplate")
        skinPresetDD:SetPoint("TOPLEFT", ct, "TOPLEFT", 18, y)
        skinPresetDD:SetWidth(CONTENT_W - 18)
        local function RebuildSkinMenu()
            skinPresetDD:SetupMenu(function(_, root)
                for _, p in ipairs(SKIN_PRESETS) do
                    local key = p.key
                    root:CreateRadio(p.label,
                        function() return (db.skinPreset or "obsidian") == key end,
                        function()
                            db.skinPreset = key
                            skinPresetDD:GenerateMenu()
                            if RefreshBrightnessVisibility then RefreshBrightnessVisibility() end
                            if db.skinMode and BNB.ApplyMainWindowSkin then
                                BNB.ApplyMainWindowSkin()
                            end
                        end)
                end
            end)
        end
        RebuildSkinMenu()
        y = y - 32
    else
        skinPresetCycleBtn = BNB.CreateButton(nil, ct, CurrentPresetLabel(), CONTENT_W - 18, 24)
        skinPresetCycleBtn:SetPoint("TOPLEFT", ct, "TOPLEFT", 18, y)
        skinPresetCycleBtn:SetScript("OnClick", function(self)
            local cur = db.skinPreset or "obsidian"
            local idx = 1
            for i, p in ipairs(SKIN_PRESETS) do if p.key == cur then idx = i; break end end
            idx = (idx % #SKIN_PRESETS) + 1
            db.skinPreset = SKIN_PRESETS[idx].key
            self:SetText(CurrentPresetLabel())
            if RefreshBrightnessVisibility then RefreshBrightnessVisibility() end
            if db.skinMode and BNB.ApplyMainWindowSkin then
                BNB.ApplyMainWindowSkin()
            end
        end)
        y = y - 30
    end

    -- Forward declaration so preset callbacks above can call it before it's defined
    local RefreshBrightnessVisibility

    -- Brightness slider (float 0.5–2.0, step 0.05)
    -- Hidden when OLED preset is selected (brightness is meaningless on pure black)
    local skinBrightnessLbl = ct:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    skinBrightnessLbl:SetPoint("TOPLEFT", ct, "TOPLEFT", 18, y)
    skinBrightnessLbl:SetHeight(ROW_H); skinBrightnessLbl:SetJustifyH("LEFT")
    skinBrightnessLbl:SetText("Skin brightness")
    y = y - (ROW_H + 2)

    local skinBrightnessSl = BNB.CreateFloatSlider(ct,
        nil, 0.5, 3.0, db.skinBrightness or 1.0, 0.05, 1.0,
        function(v)
            db.skinBrightness = v
            if db.skinMode and BNB.ApplyMainWindowSkin then
                BNB.ApplyMainWindowSkin()
            end
        end)
    skinBrightnessSl:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
    skinBrightnessSl:SetWidth(CONTENT_W)
    y = y - (36 + ROW_GAP)

    local skinBrightnessReset = BNB.CreateButton(nil, ct, "Reset", 52, 20)
    skinBrightnessReset:SetPoint("TOPLEFT", ct, "TOPLEFT", 18, y)
    skinBrightnessReset:SetScript("OnClick", function()
        db.skinBrightness = nil
        skinBrightnessSl:SetValue(1.0)
        if db.skinMode and BNB.ApplyMainWindowSkin then
            BNB.ApplyMainWindowSkin()
        end
    end)
    y = y - (22 + ROW_GAP)

    -- Window opacity slider (0.0 - 1.0, step 0.05, default 0.97)
    local skinOpacityLbl = ct:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    skinOpacityLbl:SetPoint("TOPLEFT", ct, "TOPLEFT", 18, y)
    skinOpacityLbl:SetHeight(ROW_H); skinOpacityLbl:SetJustifyH("LEFT")
    skinOpacityLbl:SetText("Window opacity")
    y = y - (ROW_H + 2)

    local skinOpacitySl = BNB.CreateFloatSlider(ct,
        nil, 0.0, 1.0, db.skinBgAlpha or 0.97, 0.01, 0.97,
        function(v)
            db.skinBgAlpha = v
            if db.skinMode and BNB.ApplyMainWindowSkin then
                BNB.ApplyMainWindowSkin()
            end
        end)
    skinOpacitySl:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
    skinOpacitySl:SetWidth(CONTENT_W)
    y = y - (36 + ROW_GAP)

    local skinOpacityReset = BNB.CreateButton(nil, ct, "Reset", 52, 20)
    skinOpacityReset:SetPoint("TOPLEFT", ct, "TOPLEFT", 18, y)
    skinOpacityReset:SetScript("OnClick", function()
        db.skinBgAlpha = nil
        skinOpacitySl:SetValue(0.97)
        if db.skinMode and BNB.ApplyMainWindowSkin then
            BNB.ApplyMainWindowSkin()
        end
    end)
    y = y - (22 + ROW_GAP)
    local skinRandomizeCb = CreateFrame("CheckButton", nil, ct, "UICheckButtonTemplate")
    skinRandomizeCb:SetPoint("TOPLEFT", ct, "TOPLEFT", 14, y)
    skinRandomizeCb.text = skinRandomizeCb.text or skinRandomizeCb:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    skinRandomizeCb.text:SetPoint("LEFT", skinRandomizeCb, "RIGHT", 2, 0)
    skinRandomizeCb.text:SetText(L["CFG_SKIN_RANDOMIZE"] or "Randomize theme on login/reload")
    skinRandomizeCb:SetChecked(db.skinRandomize == true)
    -- Forward-declared so skinRandomizeCb's OnClick can reference it
    local skinRandomizeBrightnessCb

    skinRandomizeCb:SetScript("OnClick", function(self)
        db.skinRandomize = self:GetChecked() == true
        -- Enable/disable the nested brightness checkbox to match
        local on = db.skinRandomize
        skinRandomizeBrightnessCb:SetEnabled(on)
        skinRandomizeBrightnessCb:SetAlpha(on and 1.0 or 0.4)
    end)
    skinRandomizeCb:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:ClearLines()
        GameTooltip:AddLine(L["CFG_SKIN_RANDOMIZE"] or "Randomize theme on login/reload", 1, 0.82, 0)
        GameTooltip:AddLine(L["CFG_SKIN_RANDOMIZE_TIP"] or "Randomly picks a different skin preset each time you log in or reload. Brightness is not affected.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    skinRandomizeCb:SetScript("OnLeave", GameTooltip_Hide)
    y = y - (ROW_H + ROW_GAP)

    -- Nested: randomize brightness too
    skinRandomizeBrightnessCb = CreateFrame("CheckButton", nil, ct, "UICheckButtonTemplate")
    skinRandomizeBrightnessCb:SetPoint("TOPLEFT", ct, "TOPLEFT", 30, y)
    skinRandomizeBrightnessCb.text = skinRandomizeBrightnessCb.text
        or skinRandomizeBrightnessCb:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    skinRandomizeBrightnessCb.text:SetPoint("LEFT", skinRandomizeBrightnessCb, "RIGHT", 2, 0)
    skinRandomizeBrightnessCb.text:SetText("Randomize brightness too")
    skinRandomizeBrightnessCb:SetChecked(db.skinRandomizeBrightness == true)
    local rbEnabled = db.skinRandomize == true
    skinRandomizeBrightnessCb:SetEnabled(rbEnabled)
    skinRandomizeBrightnessCb:SetAlpha(rbEnabled and 1.0 or 0.4)
    skinRandomizeBrightnessCb:SetScript("OnClick", function(self)
        db.skinRandomizeBrightness = self:GetChecked() == true
    end)
    skinRandomizeBrightnessCb:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:ClearLines()
        GameTooltip:AddLine("Randomize brightness too", 1, 0.82, 0)
        GameTooltip:AddLine("Also picks a random brightness (0.5-2.0) when randomizing the skin. Skipped for OLED preset.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    skinRandomizeBrightnessCb:SetScript("OnLeave", GameTooltip_Hide)
    y = y - (ROW_H + ROW_GAP)

    -- Single source of truth for the brightness controls' enabled/alpha state.
    -- Disables the slider if EITHER skin mode is off OR OLED preset is selected.
    -- Disables mouse on both the outer frame and the inner Slider child so that
    -- the retail MinimalSliderWithSteppersTemplate's thumb-drag also stops.
    RefreshBrightnessVisibility = function()
        local skinOn = db.skinMode == true
        local isOled = (db.skinPreset or "obsidian") == "oled"
        local enabled = skinOn and not isOled
        local alpha   = enabled and 1.0 or 0.35

        skinBrightnessLbl:SetAlpha(alpha)
        skinBrightnessSl:SetAlpha(alpha)
        skinBrightnessSl:EnableMouse(enabled)
        if skinBrightnessSl.Slider then
            skinBrightnessSl.Slider:EnableMouse(enabled)
        end
        if skinBrightnessSl.MinusBtn then skinBrightnessSl.MinusBtn:SetEnabled(enabled) end
        if skinBrightnessSl.PlusBtn  then skinBrightnessSl.PlusBtn:SetEnabled(enabled)  end
        skinBrightnessReset:SetEnabled(enabled)
        skinBrightnessReset:SetAlpha(alpha)

        -- Opacity slider follows same enabled state as brightness
        skinOpacityLbl:SetAlpha(alpha)
        skinOpacitySl:SetAlpha(alpha)
        skinOpacitySl:EnableMouse(enabled)
        if skinOpacitySl.Slider then
            skinOpacitySl.Slider:EnableMouse(enabled)
        end
        if skinOpacitySl.MinusBtn then skinOpacitySl.MinusBtn:SetEnabled(enabled) end
        if skinOpacitySl.PlusBtn  then skinOpacitySl.PlusBtn:SetEnabled(enabled)  end
        skinOpacityReset:SetEnabled(enabled)
        skinOpacityReset:SetAlpha(alpha)
    end
    RefreshBrightnessVisibility()

    -- Grey out preset controls when skin mode is off. Brightness is owned
    -- entirely by RefreshBrightnessVisibility above — don't touch those fields
    -- here or the two functions will fight each other.
    local function RefreshSkinControls()
        local on = db.skinMode == true
        local alpha = on and 1.0 or 0.4
        skinPresetLbl:SetTextColor(on and 1 or 0.45, on and 0.82 or 0.45, on and 0 or 0.45)
        if skinPresetDD        then skinPresetDD:SetEnabled(on);        skinPresetDD:SetAlpha(alpha)        end
        if skinPresetCycleBtn  then skinPresetCycleBtn:SetEnabled(on);  skinPresetCycleBtn:SetAlpha(alpha)  end
        skinRandomizeCb:SetEnabled(on)
        skinRandomizeCb:SetAlpha(alpha)
        -- Nested brightness checkbox: only enabled when skin mode on AND parent randomize on
        local rbOn = on and db.skinRandomize == true
        skinRandomizeBrightnessCb:SetEnabled(rbOn)
        skinRandomizeBrightnessCb:SetAlpha(rbOn and 1.0 or 0.4)
        RefreshBrightnessVisibility()
    end
    RefreshSkinControls()

    -- External refresh callback — lets the skin randomise button in the title bar
    -- update the config window's preset dropdown and brightness slider in real time.
    BNB._refreshSkinConfig = function()
        if skinPresetDD then skinPresetDD:GenerateMenu() end
        if skinPresetCycleBtn then skinPresetCycleBtn:SetText(CurrentPresetLabel()) end
        if skinBrightnessSl then skinBrightnessSl:SetValue(db.skinBrightness or 1.0) end
        if skinOpacitySl    then skinOpacitySl:SetValue(db.skinBgAlpha or 0.97) end
        RefreshBrightnessVisibility()
    end

    skinCb:SetScript("OnClick", function(self)
        local newVal = self:GetChecked() and true or nil
        db.skinMode = newVal
        RefreshSkinControls()
        local msg = newVal
            and "Skin mode enabled. You must reload UI for changes to take effect."
            or  "Skin mode disabled. You must reload UI for changes to take effect."
        StaticPopup_Show("BNB_SKIN_MODE_TOGGLE", msg)
    end)

    AddRule(ct, y); y = y - 18

    y = AddHeader(ct, y, L["CONFIG_FONT_FAMILY"])
    y = BuildFontPicker(ct, y)
    y = y - 4

    -- LSM font dropdown: appears below the bundled card grid when lsmFonts is on
    y = BuildLSMFontDropdown(ct, y,
        -- getter: returns the current global font choice if it is an LSM font, else nil
        function()
            local choice = db and db.fontChoice
            local def = choice and BNB.GetFontDef and BNB.GetFontDef(choice)
            return (def and def._isLSM) and choice or nil
        end,
        -- setter: nil resets to notoserif (bundled cards take over); path picks LSM font
        function(path)
            if path then
                if BNB.ApplyFont then BNB.ApplyFont(path, nil) end
            else
                if BNB.ApplyFont then BNB.ApplyFont("notoserif", nil) end
            end
            if _refreshFontHL then _refreshFontHL() end
        end)
    y = y - 4

    y = AddSlider(ct, y, L["CONFIG_FONT_SIZE"], 9, 22,
        function() return db.fontSize or 13 end,
        function(v) BNB.ApplyFont(nil, v) end,
        "Font size used in the note body editor.")

    y = AddRule(ct, y) - 4

    -- Note list display mode — WowStyle1DropdownTemplate or cycling button fallback
    y = AddHeader(ct, y, "Note list display mode")

    local MODE_ITEMS = {
        { key = "normal",   label = "Normal  (32px icons, 2 preview lines)" },
        { key = "compact",  label = "Compact  (16px icons, no preview)" },
        { key = "spacious", label = "Spacious  (42px icons, 3 preview lines)" },
    }

    local useNativeDrop2 = C_XMLUtil and C_XMLUtil.GetTemplateInfo
        and C_XMLUtil.GetTemplateInfo("WowStyle1DropdownTemplate")

    if useNativeDrop2 then
        local curMode = db.listEntryHeight or "normal"
        local modeDD2 = CreateFrame("DropdownButton", nil, ct, "WowStyle1DropdownTemplate")
        modeDD2:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
        modeDD2:SetWidth(CONTENT_W)
        modeDD2:SetupMenu(function(_, root)
            for _, m in ipairs(MODE_ITEMS) do
                root:CreateRadio(m.label,
                    function() return curMode == m.key end,
                    function()
                        curMode = m.key
                        db.listEntryHeight = m.key
                        modeDD2:GenerateMenu()
                        if BNB.ApplyListMode   then BNB.ApplyListMode()   end
                        if BNB.RefreshNoteList then BNB.RefreshNoteList() end
                    end)
            end
        end)
        modeDD2:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine("Note list row height", 1, 1, 1)
            GameTooltip:AddLine("Normal: balanced layout, icon and preview.", 0.8, 0.8, 0.8, true)
            GameTooltip:AddLine("Compact: minimal height, no preview.", 0.8, 0.8, 0.8, true)
            GameTooltip:AddLine("Spacious: larger icons and 3 preview lines.", 0.8, 0.8, 0.8, true)
            GameTooltip:Show()
        end)
        modeDD2:SetScript("OnLeave", function() GameTooltip:Hide() end)
        y = y - 32
    else
        -- Fallback: cycling button
        local function GetModeLabel()
            local v = db.listEntryHeight or "normal"
            for _, m in ipairs(MODE_ITEMS) do if m.key == v then return m.label end end
            return MODE_ITEMS[1].label
        end
        local modeBtn = BNB.CreateButton(nil, ct, GetModeLabel(), CONTENT_W, 24)
        modeBtn:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
        modeBtn:SetScript("OnClick", function(self)
            local cur = db.listEntryHeight or "normal"
            local idx = 1
            for i, m in ipairs(MODE_ITEMS) do if m.key == cur then idx = i; break end end
            idx = (idx % #MODE_ITEMS) + 1
            db.listEntryHeight = MODE_ITEMS[idx].key
            self:SetText(GetModeLabel())
            if BNB.ApplyListMode   then BNB.ApplyListMode()   end
            if BNB.RefreshNoteList then BNB.RefreshNoteList() end
        end)
        y = y - 30
    end

    y = AddRule(ct, y) - 4

    -- Timestamp format dropdown (Relative at top, default)
    y = AddHeader(ct, y, "Timestamp format")

    local DATE_FORMATS = {
        { key = "relative",   label = "Relative  (2 days ago)" },
        { key = "YYYY-MM-DD", label = "YYYY-MM-DD  (2026-03-19)" },
        { key = "DD-MM-YYYY", label = "DD-MM-YYYY  (19-03-2026)" },
        { key = "MM-DD-YYYY", label = "MM-DD-YYYY  (03-19-2026)" },
    }
    local function GetFmtLabel()
        local cur = db.dateFormat or "relative"
        for _, f in ipairs(DATE_FORMATS) do
            if f.key == cur then return f.label end
        end
        return DATE_FORMATS[1].label
    end

    -- Use WowStyle1DropdownTemplate, with simple button fallback
    local useNativeDrop = C_XMLUtil and C_XMLUtil.GetTemplateInfo
        and C_XMLUtil.GetTemplateInfo("WowStyle1DropdownTemplate")

    if useNativeDrop then
        local dd = CreateFrame("DropdownButton", nil, ct, "WowStyle1DropdownTemplate")
        dd:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
        dd:SetWidth(CONTENT_W)
        local curFmt = db.dateFormat or "relative"
        dd:SetupMenu(function(_, root)
            for _, fmtEntry in ipairs(DATE_FORMATS) do
                root:CreateRadio(fmtEntry.label,
                    function() return curFmt == fmtEntry.key end,
                    function()
                        curFmt = fmtEntry.key
                        db.dateFormat = fmtEntry.key
                        dd:GenerateMenu()
                        if BNB._currentNoteID and BNB.LoadNoteInEditor then
                            BNB.LoadNoteInEditor(BNB._currentNoteID)
                        end
                    end)
            end
        end)
        y = y - 32
    else
        -- Fallback: simple cycling button
        local fmtBtn = BNB.CreateButton(nil, ct, GetFmtLabel(), CONTENT_W, 24)
        fmtBtn:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
        fmtBtn:SetScript("OnClick", function(self)
            local cur = db.dateFormat or "relative"
            local idx = 1
            for i, f in ipairs(DATE_FORMATS) do if f.key == cur then idx = i; break end end
            idx = (idx % #DATE_FORMATS) + 1
            db.dateFormat = DATE_FORMATS[idx].key
            self:SetText(GetFmtLabel())
            if BNB._currentNoteID and BNB.LoadNoteInEditor then
                BNB.LoadNoteInEditor(BNB._currentNoteID)
            end
        end)
        y = y - 30
    end

    y = y - 4
    y = AddCheck(ct, y, "24-hour clock  (14:30 vs 2:30 pm)",
        function() return db.use24Hour ~= false end,
        function(v)
            db.use24Hour = v
            if BNB._currentNoteID and BNB.LoadNoteInEditor then
                BNB.LoadNoteInEditor(BNB._currentNoteID)
            end
        end,
        "Show timestamps in 24-hour format. Uncheck for 12-hour (AM/PM).")

    sf:FinaliseHeight(math.abs(y) + 12)
end

-- ─────────────────────────────────────────────────────────────────────────────
-- TAB 3 — FEATURES
-- ─────────────────────────────────────────────────────────────────────────────
local function BuildFeaturesTab(sf, ct)
    local db = BigNoteBoxDB
    local y  = -8

    y = AddHeader(ct, y, "Notes")

    -- New note behaviour dropdown
    do
        local lbl = ct:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        lbl:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
        lbl:SetHeight(ROW_H); lbl:SetJustifyH("LEFT")
        lbl:SetText("New note behaviour")
        y = y - (ROW_H + 2)

        local NEW_NOTE_ITEMS = {
            { key = "prompt",    label = "Prompt for title (recommended)" },
            { key = "immediate", label = "Create immediately"             },
        }
        local curBehaviour = db.newNoteBehaviour or "prompt"
        local nnDD = CreateFrame("DropdownButton", nil, ct, "WowStyle1DropdownTemplate")
        nnDD:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
        nnDD:SetWidth(CONTENT_W)
        nnDD:SetupMenu(function(_, root)
            for _, item in ipairs(NEW_NOTE_ITEMS) do
                root:CreateRadio(item.label,
                    function() return curBehaviour == item.key end,
                    function()
                        curBehaviour = item.key
                        db.newNoteBehaviour = item.key
                        nnDD:GenerateMenu()
                    end)
            end
        end)
        nnDD:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine("New note behaviour", 1, 1, 1)
            GameTooltip:AddLine("Prompt for title: opens a creation dialog to set title, icon, font and colour before creating.", 0.8, 0.8, 0.8, true)
            GameTooltip:AddLine("Create immediately: creates an empty note stub and opens it directly in the editor.", 0.8, 0.8, 0.8, true)
            GameTooltip:Show()
        end)
        nnDD:SetScript("OnLeave", function() GameTooltip:Hide() end)
        y = y - (32 + ROW_GAP)
    end

    y = AddCheck(ct, y, "Open main window on login / reload",
        function() return db.openOnLogin == true end,
        function(v) db.openOnLogin = v end,
        "Automatically open the BigNoteBox window when you log in or reload the UI.\nOff by default.")

    y = AddCheck(ct, y, "Lock notes by default",
        function() return db.lockNotes == true end,
        function(v)
            db.lockNotes = v
            -- Refresh the editor lock state for the currently open note
            if BNB.RefreshEditorLock then BNB.RefreshEditorLock() end
        end,
        "When enabled, notes open in read-only mode. Click the Edit button to modify a note.\n"
        .. "Individual notes can override this in Note Settings (right-click a note).")

    y = AddCheck(ct, y, "Ask before closing the note window",
        function() return db.confirmClose == true end,
        function(v) db.confirmClose = v end,
        "Show a confirmation popup before closing the main note window (off by default).")

    -- Combat action dropdown
    do
        local combatLbl = ct:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        combatLbl:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
        combatLbl:SetHeight(ROW_H); combatLbl:SetJustifyH("LEFT")
        combatLbl:SetText("When entering combat")
        y = y - (ROW_H + 2)

        local COMBAT_ITEMS = {
            { key = "nothing",            label = "Do nothing" },
            { key = "hide_no_stickies",   label = "Hide everything except sticky notes" },
            { key = "hide_minimize",      label = "Hide everything, minimize sticky notes" },
            { key = "hide_all",           label = "Hide everything" },
        }
        local curCombat = db.combatAction or "nothing"
        local combatDD = CreateFrame("DropdownButton", nil, ct, "WowStyle1DropdownTemplate")
        combatDD:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
        combatDD:SetWidth(CONTENT_W)
        combatDD:SetupMenu(function(_, root)
            for _, item in ipairs(COMBAT_ITEMS) do
                root:CreateRadio(item.label,
                    function() return curCombat == item.key end,
                    function()
                        curCombat = item.key
                        db.combatAction = item.key
                        combatDD:GenerateMenu()
                    end)
            end
        end)
        combatDD:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine("When entering combat", 1, 1, 1)
            GameTooltip:AddLine("Do nothing: windows stay open during combat.", 0.8, 0.8, 0.8, true)
            GameTooltip:AddLine("Hide everything except sticky notes: closes the main window and companions, sticky notes stay.", 0.8, 0.8, 0.8, true)
            GameTooltip:AddLine("Hide everything, minimize sticky notes: closes all BNB windows and collapses sticky notes to icons.", 0.8, 0.8, 0.8, true)
            GameTooltip:AddLine("Hide everything: closes all BNB windows including sticky notes.", 0.8, 0.8, 0.8, true)
            GameTooltip:AddLine("Windows reopen automatically when combat ends.", 0.8, 0.8, 0.8, true)
            GameTooltip:Show()
        end)
        combatDD:SetScript("OnLeave", function() GameTooltip:Hide() end)
        y = y - (32 + ROW_GAP)
    end

    -- ── Quick Note ────────────────────────────────────────────────────────────
    -- Inject a small icon button into quest, gossip, and item-text frames so the
    -- player can create a note directly from those game windows.
    do
        y = AddRule(ct, y) - 4
        y = AddHeader(ct, y, "Quick Note")

        -- Collect sub-widgets for greying when the master toggle is off
        local qnWidgets = {}

        local qnEnableCb = CreateFrame("CheckButton", nil, ct, "UICheckButtonTemplate")
        qnEnableCb:SetSize(24, 24)
        qnEnableCb:SetPoint("TOPLEFT", ct, "TOPLEFT", -2, y + 2)
        qnEnableCb:SetChecked(db.quickNoteEnabled ~= false)
        qnEnableCb:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine("Enable Quick Note buttons", 1, 1, 1)
            GameTooltip:AddLine(
                "Adds a small icon to quest windows, gossip frames, books, and letters\n"
                .. "so you can create a note directly from the source.", 0.8, 0.8, 0.8, true)
            GameTooltip:Show()
        end)
        qnEnableCb:SetScript("OnLeave", function() GameTooltip:Hide() end)

        local qnEnableLbl = ct:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        qnEnableLbl:SetPoint("LEFT",  qnEnableCb, "RIGHT", 4, 0)
        qnEnableLbl:SetPoint("RIGHT", ct, "RIGHT", 0, 0)
        qnEnableLbl:SetJustifyH("LEFT"); qnEnableLbl:SetHeight(ROW_H)
        qnEnableLbl:SetText("Enable Quick Note (quest, gossip, books, letters)")
        y = y - (ROW_H + ROW_GAP)

        -- On-create action dropdown (matches combat dropdown style)
        y = AddCheck(ct, y,
            "Save rewards to note (money, XP, honor, currencies, reputation)",
            function() return db.saveQuestRewards ~= false end,
            function(v) db.saveQuestRewards = v end,
            "When creating a note from a quest frame, appends any\n"
            .. "rewards (gold, XP, honor, currencies, reputation) to\n"
            .. "the note body below a separator line.")

        local qnLbl = ct:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        qnLbl:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
        qnLbl:SetHeight(ROW_H); qnLbl:SetJustifyH("LEFT")
        qnLbl:SetText("When creating a note from game content")
        table.insert(qnWidgets, qnLbl)
        y = y - (ROW_H + 2)

        local QN_ITEMS = {
            { key = "silent",  label = "Create silently in background" },
            { key = "open",    label = "Create and open BigNoteBox on it" },
            { key = "confirm", label = "Ask to confirm / edit title first" },
        }
        local curQN = db.quickNoteAction or "silent"
        local qnDD = CreateFrame("DropdownButton", nil, ct, "WowStyle1DropdownTemplate")
        qnDD:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
        qnDD:SetWidth(CONTENT_W)
        qnDD:SetupMenu(function(_, root)
            for _, item in ipairs(QN_ITEMS) do
                root:CreateRadio(item.label,
                    function() return curQN == item.key end,
                    function()
                        curQN = item.key
                        db.quickNoteAction = item.key
                        qnDD:GenerateMenu()
                    end)
            end
        end)
        qnDD:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine("When creating a note from game content", 1, 1, 1)
            GameTooltip:AddLine("Silent: note appears in your list with no interruption.", 0.8, 0.8, 0.8, true)
            GameTooltip:AddLine("Open: BigNoteBox opens and selects the new note immediately.", 0.8, 0.8, 0.8, true)
            GameTooltip:AddLine("Confirm: a small popup lets you edit the title before saving.", 0.8, 0.8, 0.8, true)
            GameTooltip:Show()
        end)
        qnDD:SetScript("OnLeave", function() GameTooltip:Hide() end)
        table.insert(qnWidgets, qnDD)
        y = y - (32 + ROW_GAP)

        -- Grey / enable sub-widgets based on master toggle
        local function ApplyQNSection(enabled)
            local a = enabled and 1 or 0.35
            for _, w in ipairs(qnWidgets) do
                w:SetAlpha(a)
                if w.SetEnabled then w:SetEnabled(enabled) end
            end
        end

        -- ── DialogueUI subsection (only shown when DialogueUI is installed) ──────
        if C_AddOns.IsAddOnLoaded("DialogueUI") then
            local duiHdr = ct:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            duiHdr:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
            duiHdr:SetTextColor(1, 0.82, 0)
            duiHdr:SetText("Dialogue UI")
            table.insert(qnWidgets, duiHdr)
            y = y - (16 + 2)

            y = AddCheck(ct, y,
                "Auto-create note when clicking DUI's Copy Text button",
                function() return db.duiAutoNote == true end,
                function(v)
                    db.duiAutoNote = v
                    if BNB.ApplyDUIAutoNote then BNB.ApplyDUIAutoNote() end
                end,
                "Whenever you click the Copy Text button in Dialogue UI, BigNoteBox\n"
                .. "automatically creates a note with the full NPC / quest text.\n"
                .. "Uses the same action setting above (silent / open / confirm).")
        end

        -- ── Immersion subsection (only shown when Immersion is installed) ─────────
        if C_AddOns.IsAddOnLoaded("Immersion") then
            local immHdr = ct:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            immHdr:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
            immHdr:SetTextColor(1, 0.82, 0)
            immHdr:SetText("Immersion")
            table.insert(qnWidgets, immHdr)
            y = y - (16 + 2)

            -- Show the floating BNB button while Immersion is active
            y = AddCheck(ct, y,
                "Show Quick Note button during Immersion dialogues",
                function() return db.quickNoteImmersionBtn ~= false end,
                function(v)
                    db.quickNoteImmersionBtn = v
                    -- Hide or show the existing button immediately if it exists
                    local btn = _G["BNBQuickNoteImmersionBtn"]
                    if btn and not v then btn:Hide() end
                end,
                "Shows a draggable icon button while Immersion is active\n"
                .. "so you can create a note from the current dialogue.\n"
                .. "The button can be dragged to any position on screen.")

            -- "Reset button position" button
            local immResetBtn = BNB.CreateButton(nil, ct, "Reset button position", 160, 22)
            immResetBtn:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
            immResetBtn:SetScript("OnClick", function()
                if BNB.ResetImmersionBtnPos then BNB.ResetImmersionBtnPos() end
            end)
            immResetBtn:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:AddLine("Moves the Immersion quick note button", 1, 1, 1)
                GameTooltip:AddLine("back to its default position.", 0.78, 0.78, 0.78)
                GameTooltip:Show()
            end)
            immResetBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
            table.insert(qnWidgets, immResetBtn)
            y = y - (22 + ROW_GAP)
        end

        qnEnableCb:SetScript("OnClick", function(self)
            db.quickNoteEnabled = self:GetChecked() and true or false
            ApplyQNSection(db.quickNoteEnabled)
        end)

        ApplyQNSection(db.quickNoteEnabled ~= false)
    end

    -- ── Inspect Note ──────────────────────────────────────────────────────────
    do
        y = AddRule(ct, y) - 4
        y = AddHeader(ct, y, "Inspect Note")

        -- Creation mode dropdown
        local insModeLbl = ct:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        insModeLbl:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
        insModeLbl:SetHeight(ROW_H); insModeLbl:SetJustifyH("LEFT")
        insModeLbl:SetText("When opening the inspect window")
        y = y - (ROW_H + 2)

        local INS_MODES = {
            { key = "manual",      label = "Manual (click button to create)" },
            { key = "auto_rich",   label = "Automatically create a Rich note" },
            { key = "auto_normal", label = "Automatically create a Normal note" },
        }
        local curInsMode = db.inspectNoteMode or "manual"
        local insModeDD = CreateFrame("DropdownButton", nil, ct, "WowStyle1DropdownTemplate")
        insModeDD:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
        insModeDD:SetWidth(CONTENT_W)

        -- Note type dropdown (below)
        local insTypeLbl = ct:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        local insTypeDD

        local function RefreshInsTypeState()
            local isAuto = curInsMode ~= "manual"
            if insTypeDD then
                insTypeDD:SetEnabled(not isAuto)
                insTypeDD:SetAlpha(isAuto and 0.4 or 1.0)
            end
            if insTypeLbl then
                insTypeLbl:SetAlpha(isAuto and 0.4 or 1.0)
            end
        end

        insModeDD:SetupMenu(function(_, root)
            for _, item in ipairs(INS_MODES) do
                root:CreateRadio(item.label,
                    function() return curInsMode == item.key end,
                    function()
                        curInsMode = item.key
                        db.inspectNoteMode = item.key
                        insModeDD:GenerateMenu()
                        RefreshInsTypeState()
                    end)
            end
        end)
        insModeDD:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine("Inspect note creation mode", 1, 1, 1)
            GameTooltip:AddLine("Manual: a button appears on the inspect window. Click it to create a note.", 0.8, 0.8, 0.8, true)
            GameTooltip:AddLine("Automatic: a note is created every time you inspect a player.", 0.8, 0.8, 0.8, true)
            GameTooltip:Show()
        end)
        insModeDD:SetScript("OnLeave", function() GameTooltip:Hide() end)
        y = y - (ROW_H + ROW_GAP)

        -- Note type on click dropdown
        insTypeLbl:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
        insTypeLbl:SetHeight(ROW_H); insTypeLbl:SetJustifyH("LEFT")
        insTypeLbl:SetText("When clicking the create note button")
        y = y - (ROW_H + 2)

        local INS_TYPES = {
            { key = "choose",        label = "Choose on click (Normal or Rich)" },
            { key = "always_rich",   label = "Always create a Rich note" },
            { key = "always_normal", label = "Always create a Normal note" },
        }
        local curInsType = db.inspectNoteType or "choose"
        insTypeDD = CreateFrame("DropdownButton", nil, ct, "WowStyle1DropdownTemplate")
        insTypeDD:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
        insTypeDD:SetWidth(CONTENT_W)
        insTypeDD:SetupMenu(function(_, root)
            for _, item in ipairs(INS_TYPES) do
                root:CreateRadio(item.label,
                    function() return curInsType == item.key end,
                    function()
                        curInsType = item.key
                        db.inspectNoteType = item.key
                        insTypeDD:GenerateMenu()
                    end)
            end
        end)
        insTypeDD:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine("Note type when clicking the button", 1, 1, 1)
            GameTooltip:AddLine("Choose: a popup asks you to pick Normal or Rich.", 0.8, 0.8, 0.8, true)
            GameTooltip:AddLine("Always Rich/Normal: skips the popup and creates that type directly.", 0.8, 0.8, 0.8, true)
            GameTooltip:AddLine("Disabled when creation mode is set to automatic.", 0.8, 0.8, 0.8, true)
            GameTooltip:Show()
        end)
        insTypeDD:SetScript("OnLeave", function() GameTooltip:Hide() end)
        y = y - (ROW_H + ROW_GAP)

        RefreshInsTypeState()

        -- Add player situation checkbox
        y = AddCheck(ct, y,
            "Add a player situation to inspect notes",
            function() return BigNoteBoxDB and BigNoteBoxDB.inspectNoteAddSituation == true end,
            function(v)
                if BigNoteBoxDB then BigNoteBoxDB.inspectNoteAddSituation = v end
            end,
            "When enabled, inspect notes will automatically have a player situation set,\n"
            .. "so contextual features (popup, sticky note) can trigger when you target that player again.")

        -- Gear to show dropdown
        local gearShowLbl = ct:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        gearShowLbl:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
        gearShowLbl:SetHeight(ROW_H); gearShowLbl:SetJustifyH("LEFT")
        gearShowLbl:SetText(L["CFG_INS_GEAR_SHOW"])
        y = y - (ROW_H + 2)

        local GEAR_SHOW_OPTS = {
            { key = "both",     label = L["CFG_INS_GEAR_BOTH"]    },
            { key = "regular",  label = L["CFG_INS_GEAR_REGULAR"] },
            { key = "transmog", label = L["CFG_INS_GEAR_TRANSMOG"]},
        }
        local curGearShow = db.inspectNoteGearShow or "both"
        local gearShowDD = CreateFrame("DropdownButton", nil, ct, "WowStyle1DropdownTemplate")
        gearShowDD:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
        gearShowDD:SetWidth(CONTENT_W)
        gearShowDD:SetupMenu(function(_, root)
            for _, item in ipairs(GEAR_SHOW_OPTS) do
                root:CreateRadio(item.label,
                    function() return curGearShow == item.key end,
                    function()
                        curGearShow = item.key
                        db.inspectNoteGearShow = item.key
                        gearShowDD:GenerateMenu()
                    end)
            end
        end)
        gearShowDD:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(L["CFG_INS_GEAR_SHOW"], 1, 1, 1)
            GameTooltip:AddLine(L["CFG_INS_GEAR_SHOW_TIP"], 0.8, 0.8, 0.8, true)
            GameTooltip:Show()
        end)
        gearShowDD:SetScript("OnLeave", function() GameTooltip:Hide() end)
        y = y - (ROW_H + ROW_GAP)
    end

    -- ── Target Note ───────────────────────────────────────────────────────────
    do
        y = AddRule(ct, y) - 4
        y = AddHeader(ct, y, "Target Note")

        -- Note type dropdown
        local tnTypeLbl = ct:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        tnTypeLbl:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
        tnTypeLbl:SetHeight(ROW_H)
        tnTypeLbl:SetJustifyH("LEFT")
        tnTypeLbl:SetText("When creating a target note")
        y = y - (ROW_H + 2)

        local TN_TYPES = {
            { key = "choose",        label = "Choose on click (Normal or Rich)" },
            { key = "always_rich",   label = "Always create a Rich note" },
            { key = "always_normal", label = "Always create a Normal note" },
        }
        local curTNType = db.targetNoteType or "choose"
        local tnTypeDD = CreateFrame("DropdownButton", nil, ct, "WowStyle1DropdownTemplate")
        tnTypeDD:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
        tnTypeDD:SetWidth(CONTENT_W)
        tnTypeDD:SetupMenu(function(_, root)
            for _, item in ipairs(TN_TYPES) do
                root:CreateRadio(item.label,
                    function() return curTNType == item.key end,
                    function()
                        curTNType = item.key
                        db.targetNoteType = item.key
                        tnTypeDD:GenerateMenu()
                    end)
            end
        end)
        tnTypeDD:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine("Target note type", 1, 1, 1)
            GameTooltip:AddLine("Choose: a popup asks you to pick Normal or Rich.", 0.8, 0.8, 0.8, true)
            GameTooltip:AddLine("Always Rich/Normal: skips the popup and creates that type directly.", 0.8, 0.8, 0.8, true)
            GameTooltip:Show()
        end)
        tnTypeDD:SetScript("OnLeave", function() GameTooltip:Hide() end)
        y = y - (ROW_H + ROW_GAP)

        -- Tag checklist header
        local tagHeaderLbl = ct:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        tagHeaderLbl:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
        tagHeaderLbl:SetHeight(ROW_H)
        tagHeaderLbl:SetJustifyH("LEFT")
        tagHeaderLbl:SetText("Tags to add to target notes")
        y = y - (ROW_H + 2)

        local subLbl = ct:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        subLbl:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
        subLbl:SetWidth(CONTENT_W)
        subLbl:SetHeight(ROW_H - 4)
        subLbl:SetJustifyH("LEFT")
        subLbl:SetWordWrap(true)
        subLbl:SetText("\"Target Note\" is always added. Enable any additional tags below.")
        subLbl:SetTextColor(0.65, 0.65, 0.65)
        y = y - (ROW_H + ROW_GAP - 2)

        -- Individual tag toggles
        y = AddCheck(ct, y, "Creature Type  (e.g. Humanoid, Beast, Undead)",
            function() local v = BigNoteBoxDB and BigNoteBoxDB.targetNoteTagCreatureType; return v == nil or v == true end,
            function(v) if BigNoteBoxDB then BigNoteBoxDB.targetNoteTagCreatureType = v end end,
            "Adds the creature's type as a tag (e.g. \"Humanoid\", \"Beast\", \"Undead\").\nApplies to NPC/mob/boss targets only.")

        y = AddCheck(ct, y, "Creature Family  (e.g. Wolf, Spider)",
            function() return BigNoteBoxDB and BigNoteBoxDB.targetNoteTagFamily == true end,
            function(v) if BigNoteBoxDB then BigNoteBoxDB.targetNoteTagFamily = v end end,
            "Adds the creature's family as a tag (e.g. \"Wolf\", \"Spider\").\nOnly available for Beast-type creatures. Off by default.")

        y = AddCheck(ct, y, "Classification  (e.g. Elite, Rare, World Boss)",
            function() local v = BigNoteBoxDB and BigNoteBoxDB.targetNoteTagClassification; return v == nil or v == true end,
            function(v) if BigNoteBoxDB then BigNoteBoxDB.targetNoteTagClassification = v end end,
            "Adds the creature's classification as a tag (e.g. \"Elite\", \"Rare Elite\", \"World Boss\").\nNormal enemies have no classification label and add no tag.")

        y = AddCheck(ct, y, "Faction  (e.g. Alliance, Horde)",
            function() local v = BigNoteBoxDB and BigNoteBoxDB.targetNoteTagFaction; return v == nil or v == true end,
            function(v) if BigNoteBoxDB then BigNoteBoxDB.targetNoteTagFaction = v end end,
            "Adds the target's faction as a tag (e.g. \"Alliance\", \"Horde\").\nApplies to both player and NPC targets.")

        y = AddCheck(ct, y, "Zone  (where the note was created)",
            function() local v = BigNoteBoxDB and BigNoteBoxDB.targetNoteTagZone; return v == nil or v == true end,
            function(v) if BigNoteBoxDB then BigNoteBoxDB.targetNoteTagZone = v end end,
            "Adds the current zone name as a tag when the note is created.\nUseful for tracking where you encountered a mob or rare.")

        y = AddCheck(ct, y, "Boss  (for world bosses and skull-level targets)",
            function() local v = BigNoteBoxDB and BigNoteBoxDB.targetNoteTagBoss; return v == nil or v == true end,
            function(v) if BigNoteBoxDB then BigNoteBoxDB.targetNoteTagBoss = v end end,
            "Adds a \"Boss\" tag for world bosses and skull-level (level ??) targets.")
    end

    -- ── Tasks ────────────────────────────────────────────────────────────────────
    y = AddRule(ct, y) - 4
    y = AddHeader(ct, y, "Tasks")

    y = AddCheck(ct, y, "Remove completed tasks immediately",
        function() return BigNoteBoxDB and BigNoteBoxDB.taskRemoveOnComplete == true end,
        function(v)
            if BigNoteBoxDB then BigNoteBoxDB.taskRemoveOnComplete = v end
        end,
        "When checked, completing a task is permanent -- it is removed from the list right away. When unchecked, completed tasks are greyed out and stay in the list until you clear them manually.")

    -- Completed tasks position dropdown
    do
        local cpLbl = ct:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        cpLbl:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
        cpLbl:SetText("Completed tasks position:")
        cpLbl:SetHeight(ROW_H)
        y = y - ROW_H - 2

        local CP_ITEMS = {
            { key = "bottom", label = "Move to bottom" },
            { key = "inline", label = "Keep in place"  },
        }

        local useDD = C_XMLUtil and C_XMLUtil.GetTemplateInfo
            and C_XMLUtil.GetTemplateInfo("WowStyle1DropdownTemplate")

        if useDD then
            local cpDD = CreateFrame("DropdownButton", nil, ct, "WowStyle1DropdownTemplate")
            cpDD:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
            cpDD:SetWidth(CONTENT_W)
            cpDD:SetupMenu(function(_, root)
                for _, item in ipairs(CP_ITEMS) do
                    local iv = item.key
                    root:CreateRadio(item.label,
                        function()
                            return (BigNoteBoxDB and BigNoteBoxDB.taskCompletedPosition or "bottom") == iv
                        end,
                        function()
                            if BigNoteBoxDB then BigNoteBoxDB.taskCompletedPosition = iv end
                            cpDD:GenerateMenu()
                            if BNB.RefreshReferenceBox then BNB.RefreshReferenceBox() end
                        end)
                end
            end)
            cpDD:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:AddLine("Completed tasks position", 1, 1, 1)
                GameTooltip:AddLine("Move to bottom: completed tasks sink to the bottom of the list.", 0.8, 0.8, 0.8, true)
                GameTooltip:AddLine("Keep in place: completed tasks stay where they are and are greyed out.", 0.8, 0.8, 0.8, true)
                GameTooltip:Show()
            end)
            cpDD:SetScript("OnLeave", function() GameTooltip:Hide() end)
            y = y - 32
        else
            -- Fallback: cycling button
            local function GetCpLabel()
                local v = BigNoteBoxDB and BigNoteBoxDB.taskCompletedPosition or "bottom"
                for _, item in ipairs(CP_ITEMS) do if item.key == v then return item.label end end
                return CP_ITEMS[1].label
            end
            local cpBtn = BNB.CreateButton(nil, ct, GetCpLabel(), CONTENT_W, 24)
            cpBtn:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
            cpBtn:SetScript("OnClick", function(self)
                local cur = BigNoteBoxDB and BigNoteBoxDB.taskCompletedPosition or "bottom"
                local next = cur == "bottom" and "inline" or "bottom"
                if BigNoteBoxDB then BigNoteBoxDB.taskCompletedPosition = next end
                local lbl = next == "bottom" and "Move to bottom" or "Keep in place"
                self:SetText(lbl)
                if BNB.RefreshReferenceBox then BNB.RefreshReferenceBox() end
            end)
            y = y - 30
        end
    end

    y = AddRule(ct, y) - 4
    y = AddHeader(ct, y, L["CFG_FOCUS_ORBIT_HEADER"])

    -- Hide entire WoW UI
    y = AddCheck(ct, y,
        "Hide entire WoW UI in focus mode",
        function() local db = BigNoteBoxDB; return db == nil or db.focusHideUI ~= false end,
        function(v)
            if BigNoteBoxDB then BigNoteBoxDB.focusHideUI = v end
        end,
        "When enabled, the entire WoW UI is hidden while focus mode is active,\\n"
        .. "leaving only the note editor visible. The UI is always restored on exit.")

    -- Master orbit toggle
    local orbitCheckY = y
    y = AddCheck(ct, y, L["CFG_FOCUS_ORBIT_ENABLE"],
        function() local db = BigNoteBoxDB; return db == nil or db.focusOrbitEnabled ~= false end,
        function(v)
            if BigNoteBoxDB then BigNoteBoxDB.focusOrbitEnabled = v end
            if BNB.FocusOrbit then
                if v then BNB.FocusOrbit.Start() else BNB.FocusOrbit.Stop() end
            end
            if BNB.UpdateFocusSpinBtn then BNB.UpdateFocusSpinBtn(v) end
            if BNB._focusOrbitRefreshUI then BNB._focusOrbitRefreshUI() end
        end,
        L["CFG_FOCUS_ORBIT_ENABLE_TIP"])

    -- Speed slider (greyed when orbit off)
    local speedSl = BNB.CreateFloatSlider(ct, L["CFG_FOCUS_ORBIT_SPEED"], 0.001, 0.020,
        (BigNoteBoxDB and BigNoteBoxDB.focusOrbitSpeed) or 0.004,
        0.001, 0.004,
        function(v)
            if BigNoteBoxDB then BigNoteBoxDB.focusOrbitSpeed = v end
        end,
        function(v) return string.format("%.3f", v) end)
    speedSl:SetPoint("TOPLEFT", ct, "TOPLEFT", 14, y)
    speedSl:SetWidth(CONTENT_W - 14)
    y = y - (SLIDER_H + ROW_GAP)

    -- Resume-after-movement slider (greyed when orbit off)
    local resumeSl = BNB.CreateFloatSlider(ct, L["CFG_FOCUS_ORBIT_RESUME"], 0, 10,
        (BigNoteBoxDB and BigNoteBoxDB.focusOrbitResumeDelay) or 3.0,
        0.5, 3.0,
        function(v)
            if BigNoteBoxDB then BigNoteBoxDB.focusOrbitResumeDelay = v end
        end,
        function(v)
            if v <= 0 then return "Off" end
            return string.format("%.1f s", v)
        end)
    resumeSl:SetPoint("TOPLEFT", ct, "TOPLEFT", 14, y)
    resumeSl:SetWidth(CONTENT_W - 14)
    y = y - (SLIDER_H + ROW_GAP)

    -- Overlay darkness slider (always active — not tied to orbit toggle)
    y = y - 4
    local overlaySl = BNB.CreateFloatSlider(ct, L["CFG_FOCUS_OVERLAY_ALPHA"], 0.0, 1.0,
        (BigNoteBoxDB and BigNoteBoxDB.focusOverlayAlpha) or 0.6,
        0.05, 0.6,
        function(v)
            if BigNoteBoxDB then BigNoteBoxDB.focusOverlayAlpha = v end
        end,
        function(v) return string.format("%.2f", v) end)
    overlaySl:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
    overlaySl:SetWidth(CONTENT_W)
    y = y - (SLIDER_H + ROW_GAP)

    -- Skin color tint checkbox (only meaningful in skin mode, but always shown)
    y = AddCheck(ct, y, L["CFG_FOCUS_OVERLAY_SKIN_COLOR"],
        function()
            local db = BigNoteBoxDB
            return db ~= nil and db.focusOverlayUseSkinColor == true
        end,
        function(v)
            if BigNoteBoxDB then BigNoteBoxDB.focusOverlayUseSkinColor = v end
        end,
        L["CFG_FOCUS_OVERLAY_SKIN_COLOR_TIP"])

    -- Grey/ungrey orbit-specific sub-controls based on master toggle
    local function RefreshOrbitUI()
        local db = BigNoteBoxDB
        local on = db == nil or db.focusOrbitEnabled ~= false
        local alpha = on and 1.0 or 0.4
        speedSl:SetAlpha(alpha);  speedSl:EnableMouse(on)
        resumeSl:SetAlpha(alpha); resumeSl:EnableMouse(on)
    end
    RefreshOrbitUI()
    BNB._focusOrbitRefreshUI = RefreshOrbitUI

    y = AddRule(ct, y) - 4
    y = AddHeader(ct, y, "Context Popup")

    y = AddCheck(ct, y, L["CONFIG_CONTEXT_SURFACE"],
        function() return db.contextSurface ~= false end,
        function(v) db.contextSurface = v end,
        "Surface notes matching your current zone, instance or player target.")

    -- "Set Popup Position" button
    local anchorBtn = BNB.CreateButton(nil, ct, "Set Popup Position", 150, 22)
    anchorBtn:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
    anchorBtn:SetScript("OnClick", function()
        if BNB.TogglePopupAnchor then BNB.TogglePopupAnchor() end
    end)
    anchorBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Opens a draggable anchor to position where context\npopup notifications appear on screen.", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    anchorBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    y = y - (22 + 6)

    -- Popup hold time slider
    y = AddSlider(ct, y, "Show alert for (seconds)", 0, 60,
        function() return db.popupHoldTime or 5 end,
        function(v) db.popupHoldTime = v end,
        "How long the context popup stays on screen before fading out.\n0 = stay until manually closed (right-click to dismiss).")

    y = AddRule(ct, y) - 4
    y = AddHeader(ct, y, "Trash")

    -- ── Trash enable/disable checkbox ─────────────────────────────────────────
    -- Capture all child widget refs so we can grey them out when disabled.
    local trashEnableCb = CreateFrame("CheckButton", nil, ct, "UICheckButtonTemplate")
    trashEnableCb:SetSize(24, 24)
    trashEnableCb:SetPoint("TOPLEFT", ct, "TOPLEFT", -2, y + 2)
    trashEnableCb:SetChecked(db.trashFeature ~= false)
    local trashEnableLbl = ct:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    trashEnableLbl:SetPoint("LEFT",  trashEnableCb, "RIGHT", 4, 0)
    trashEnableLbl:SetPoint("RIGHT", ct, "RIGHT", 0, 0)
    trashEnableLbl:SetJustifyH("LEFT"); trashEnableLbl:SetHeight(ROW_H)
    trashEnableLbl:SetText("Enable Trash (recover deleted notes)")
    y = y - (ROW_H + ROW_GAP)

    -- ── Warn before deleting checkbox ─────────────────────────────────────────
    local warnCb = CreateFrame("CheckButton", nil, ct, "UICheckButtonTemplate")
    warnCb:SetSize(24, 24)
    warnCb:SetPoint("TOPLEFT", ct, "TOPLEFT", -2, y + 2)
    warnCb:SetChecked(db.warnBeforeDelete ~= false)
    warnCb:SetScript("OnClick", function(self)
        db.warnBeforeDelete = self:GetChecked() and true or false
    end)
    warnCb:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(
            "Show a confirmation before moving a note to Trash (or permanently deleting it when trash is disabled).\n"
            .. "Turn off for instant deletion without any prompt.", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    warnCb:SetScript("OnLeave", function() GameTooltip:Hide() end)
    local warnLbl = ct:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    warnLbl:SetPoint("LEFT",  warnCb, "RIGHT", 4, 0)
    warnLbl:SetPoint("RIGHT", ct, "RIGHT", 0, 0)
    warnLbl:SetJustifyH("LEFT"); warnLbl:SetHeight(ROW_H)
    warnLbl:SetText("Warn before deleting")
    y = y - (ROW_H + ROW_GAP)

    -- ── Retention slider ───────────────────────────────────────────────────────
    local retainSlider = BNB.CreateSlider(ct, "Keep deleted notes for (days)", 0, 90,
        db.trashRetainDays ~= nil and db.trashRetainDays or 30, nil,
        function(v) db.trashRetainDays = v end)
    retainSlider:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
    retainSlider:SetWidth(CONTENT_W)
    retainSlider:EnableMouse(true)
    retainSlider:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(
            "How long deleted notes are kept in the Trash before being permanently removed.\n"
            .. "0 = trash disabled, deletes are permanent (no recovery).\n"
            .. "Maximum: 90 days.", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    retainSlider:SetScript("OnLeave", function() GameTooltip:Hide() end)
    y = y - (SLIDER_H + ROW_GAP)

    -- ── Apply greying / trash button visibility ────────────────────────────────
    local function ApplyTrashSection(enabled)
        local a = enabled and 1 or 0.35
        warnCb:SetEnabled(enabled)
        warnCb:SetAlpha(a)
        warnLbl:SetAlpha(a)
        retainSlider:SetAlpha(a)
        retainSlider:EnableMouse(enabled)
        -- Show/hide the trashcan icon in the main window toolbar
        if BNB._toolbarTrashBtn then
            BNB._toolbarTrashBtn:SetShown(enabled)
        end
        -- Close the trash window if it's open and we're disabling
        if not enabled and BNB.ToggleTrashWindow then
            local tf = _G["BigNoteBoxTrashFrame"]
            if tf and tf:IsShown() then tf:Hide() end
        end
    end

    trashEnableCb:SetScript("OnClick", function(self)
        local v = self:GetChecked() and true or false
        db.trashFeature = v
        ApplyTrashSection(v)
    end)

    -- Apply immediately (handles saved state on config open)
    ApplyTrashSection(db.trashFeature ~= false)

    y = AddRule(ct, y) - 4
    y = AddHeader(ct, y, "Sticky Notes")

    do
        local desc = ct:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        desc:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
        desc:SetWidth(CONTENT_W); desc:SetJustifyH("LEFT"); desc:SetWordWrap(true)
        desc:SetTextColor(0.60, 0.60, 0.60)
        desc:SetText("Alarms are set per-note via the alarm button in the editor toolbar or the note list right-click menu. Alarm settings, glow animation and snooze options are configured in the Set Alarm window.")
        local h = desc:GetStringHeight() + 6
        desc:SetHeight(h)
        y = y - h - 6
    end

    y = AddSlider(ct, y, "Max open sticky notes", 1, 50,
        function() return db.stickyMaxCount or 10 end,
        function(v) db.stickyMaxCount = v end,
        "Maximum number of sticky notes that can be open at the same time (default: 10).")

    y = AddCheck(ct, y, L["CFG_STICKY_HIDE_PERSIST"],
        function() return db.stickiesHiddenPersist == true end,
        function(v) db.stickiesHiddenPersist = v end,
        L["CFG_STICKY_HIDE_PERSIST_TIP"])

    -- ── Keybind capture button — Show/Hide all sticky notes ───────────────────
    y = MakeKeybindRow(ct, y, L["CFG_STICKY_KEYBIND_LABEL"],
        "BIGNOTEBOXHIDESTICKIES", "(Default: Ctrl+H)", "Show/Hide all sticky notes")

    -- ── Reference Box ─────────────────────────────────────────────────────────
    do
        y = AddRule(ct, y) - 4
        y = AddHeader(ct, y, "Reference Box")

        -- Collect widgets for greying when disabled
        local rbWidgets = {}

        local rbEnableCb = CreateFrame("CheckButton", nil, ct, "UICheckButtonTemplate")
        rbEnableCb:SetSize(24, 24)
        rbEnableCb:SetPoint("TOPLEFT", ct, "TOPLEFT", -2, y + 2)
        rbEnableCb:SetChecked(db.referenceBoxEnabled ~= false)
        rbEnableCb:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine("Show the Reference Box panel.\nAttach items and spells to your notes for quick lookup.", 0.8, 0.8, 0.8, true)
            GameTooltip:Show()
        end)
        rbEnableCb:SetScript("OnLeave", function() GameTooltip:Hide() end)
        local rbEnableLbl = ct:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        rbEnableLbl:SetPoint("LEFT", rbEnableCb, "RIGHT", 4, 0)
        rbEnableLbl:SetPoint("RIGHT", ct, "RIGHT", 0, 0)
        rbEnableLbl:SetJustifyH("LEFT"); rbEnableLbl:SetHeight(ROW_H)
        rbEnableLbl:SetText("Enable Reference Box")
        y = y - (ROW_H + ROW_GAP)

        -- Side: Left / Right dropdown
        local sideDD = CreateFrame("DropdownButton", nil, ct, "WowStyle1DropdownTemplate")
        sideDD:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
        sideDD:SetWidth(CONTENT_W)
        sideDD:SetHeight(22)
        table.insert(rbWidgets, sideDD)

        local SIDE_OPTIONS = {
            { key = "left",  label = "Left  - anchor to the left of the main window" },
            { key = "right", label = "Right - anchor to the right of the main window" },
        }
        local function RebuildSideMenu()
            sideDD:SetupMenu(function(_, root)
                for _, opt in ipairs(SIDE_OPTIONS) do
                    local key = opt.key
                    root:CreateRadio(opt.label,
                        function() return (db.refboxSide or "left") == key end,
                        function()
                            db.refboxSide = key
                            sideDD:GenerateMenu()
                            if BNB.RefreshReferenceBox then BNB.RefreshReferenceBox() end
                            -- Re-position the open refbox immediately
                            local rbf = _G["BigNoteBoxReferenceBoxFrame"]
                            if rbf and rbf:IsShown() and BNB.OpenReferenceBox then
                                BNB.OpenReferenceBox(db.selectedNoteID)
                            end
                        end)
                end
            end)
        end
        RebuildSideMenu()
        y = y - (22 + ROW_GAP)

        -- Display style dropdown
        local styleDD = CreateFrame("DropdownButton", nil, ct, "WowStyle1DropdownTemplate")
        styleDD:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
        styleDD:SetWidth(CONTENT_W)
        styleDD:SetHeight(22)
        table.insert(rbWidgets, styleDD)

        local STYLE_OPTIONS = {
            { key = "normal",  label = "Normal  \226\128\148 large icon, type label, quality-coloured name" },
            { key = "compact", label = "Compact \226\128\148 slim single-row with small icon" },
        }
        local function RebuildStyleMenu()
            styleDD:SetupMenu(function(_, root)
                for _, opt in ipairs(STYLE_OPTIONS) do
                    local key = opt.key
                    root:CreateRadio(opt.label,
                        function() return (db.refboxDisplayStyle or "normal") == key end,
                        function()
                            db.refboxDisplayStyle = key
                            styleDD:GenerateMenu()
                            if BNB.RefreshReferenceBox then BNB.RefreshReferenceBox() end
                        end)
                end
            end)
        end
        RebuildStyleMenu()
        y = y - (22 + ROW_GAP)

        -- Max attachments slider
        local rbMaxSlider = BNB.CreateSlider(ct, "Max attachments per note", 1, 100,
            db.refboxMaxItems or 50, nil,
            function(v) db.refboxMaxItems = v end)
        rbMaxSlider:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
        rbMaxSlider:SetWidth(CONTENT_W)
        rbMaxSlider:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine("Maximum number of items and spells that can be attached to a single note (default: 50).", 0.8, 0.8, 0.8, true)
            GameTooltip:Show()
        end)
        rbMaxSlider:SetScript("OnLeave", function() GameTooltip:Hide() end)
        table.insert(rbWidgets, rbMaxSlider)
        y = y - (SLIDER_H + ROW_GAP)

        -- Auto-open when note has attachments
        y = AddCheck(ct, y, "Auto-open when selecting a note with attachments",
            function() return db.refboxAutoOpen ~= false end,
            function(v) db.refboxAutoOpen = v end,
            "Automatically opens the Reference Box when you switch to a note that has attachments.\n"
            .. "Does not auto-close when switching to a note with no attachments.")

        -- Show ItemID / SpellID / QuestID in the game's native tooltip
        y = AddCheck(ct, y, "Show Item/Spell/Quest IDs in tooltips (BNB: <id>)",
            function() return db.refboxShowIDs == true end,
            function(v)
                db.refboxShowIDs = v
            end,
            "Adds a \"BNB: <id>\" line in green at the bottom of item, spell and quest tooltips.\n"
            .. "Useful if you don't have a dedicated tooltip ID addon.\n"
            .. "Off by default.")

        -- Apply enabled/disabled state
        local function ApplyRBSection(enabled)
            local a = enabled and 1 or 0.35
            for _, w in ipairs(rbWidgets) do
                w:SetAlpha(a)
                if w.SetEnabled then w:SetEnabled(enabled) end
            end
            if BNB._editorRefBoxBtn then
                BNB._editorRefBoxBtn:SetEnabled(enabled)
                BNB._editorRefBoxBtn:SetAlpha(enabled and 1.0 or 0.4)
            end
            if not enabled and BNB.CloseReferenceBox then
                BNB.CloseReferenceBox()
            end
        end

        rbEnableCb:SetScript("OnClick", function(self)
            db.referenceBoxEnabled = self:GetChecked() and true or false
            ApplyRBSection(db.referenceBoxEnabled)
        end)

        ApplyRBSection(db.referenceBoxEnabled ~= false)
    end

    -- Sidebar
    y = AddRule(ct, y) - 4
    y = AddHeader(ct, y, "Character Sidebar")

    -- Master enable checkbox (manual build to retain widget ref for greying)
    local sidebarEnableCb = CreateFrame("CheckButton", nil, ct, "UICheckButtonTemplate")
    sidebarEnableCb:SetSize(24, 24)
    sidebarEnableCb:SetPoint("TOPLEFT", ct, "TOPLEFT", -2, y + 2)
    sidebarEnableCb:SetChecked(db.sidebarEnabled == true)
    local sidebarEnableLbl = ct:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    sidebarEnableLbl:SetPoint("LEFT",  sidebarEnableCb, "RIGHT", 4, 0)
    sidebarEnableLbl:SetPoint("RIGHT", ct, "RIGHT", 0, 0)
    sidebarEnableLbl:SetJustifyH("LEFT"); sidebarEnableLbl:SetHeight(ROW_H)
    sidebarEnableLbl:SetText("Enable character sidebar")
    y = y - (ROW_H + ROW_GAP)

    -- Sub-frame: groups all dependent controls so alpha-greying works as one unit.
    local sidebarSub = CreateFrame("Frame", nil, ct)
    sidebarSub:SetPoint("TOPLEFT",  ct, "TOPLEFT",  0, y)
    sidebarSub:SetPoint("TOPRIGHT", ct, "TOPRIGHT", 0, y)
    sidebarSub:SetHeight(200)  -- resized by RebuildHiddenList
    local subY = 0

    -- Auto-switch checkbox
    local autoSwCb = CreateFrame("CheckButton", nil, sidebarSub, "UICheckButtonTemplate")
    autoSwCb:SetSize(24, 24)
    autoSwCb:SetPoint("TOPLEFT", sidebarSub, "TOPLEFT", -2, subY + 2)
    autoSwCb:SetChecked(db.sidebarAutoSwitch == true)
    autoSwCb:SetScript("OnClick", function(self)
        db.sidebarAutoSwitch = self:GetChecked() and true or false
    end)
    autoSwCb:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Automatically activates the sidebar slot for the character you log in with.", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    autoSwCb:SetScript("OnLeave", function() GameTooltip:Hide() end)
    local autoSwLbl = sidebarSub:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    autoSwLbl:SetPoint("LEFT",  autoSwCb, "RIGHT", 4, 0)
    autoSwLbl:SetPoint("RIGHT", sidebarSub, "RIGHT", 0, 0)
    autoSwLbl:SetJustifyH("LEFT"); autoSwLbl:SetHeight(ROW_H)
    autoSwLbl:SetText("Auto-switch to character tab on login")
    subY = subY - (ROW_H + ROW_GAP)

    -- Side dropdown (Left / Right)
    do
        local sideLbl = sidebarSub:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        sideLbl:SetPoint("TOPLEFT", sidebarSub, "TOPLEFT", 0, subY)
        sideLbl:SetHeight(ROW_H); sideLbl:SetJustifyH("LEFT")
        sideLbl:SetText("Sidebar side")
        subY = subY - (ROW_H + 2)

        local SIDE_ITEMS = {
            { key = "right", label = "Right (default)" },
            { key = "left",  label = "Left" },
        }
        local curSide = db.sidebarSide or "right"
        local sideDD = CreateFrame("DropdownButton", nil, sidebarSub, "WowStyle1DropdownTemplate")
        sideDD:SetPoint("TOPLEFT", sidebarSub, "TOPLEFT", 0, subY)
        sideDD:SetWidth(CONTENT_W)
        sideDD:SetupMenu(function(_, root)
            for _, item in ipairs(SIDE_ITEMS) do
                root:CreateRadio(item.label,
                    function() return curSide == item.key end,
                    function()
                        curSide = item.key
                        db.sidebarSide = item.key
                        sideDD:GenerateMenu()
                        if BNB.Sidebar and BNB.Sidebar.Refresh then BNB.Sidebar.Refresh() end
                    end)
            end
        end)
        sideDD:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine("Sidebar side", 1, 1, 1)
            GameTooltip:AddLine("Place the sidebar on the left or right edge of the main window.", 0.8, 0.8, 0.8, true)
            GameTooltip:Show()
        end)
        sideDD:SetScript("OnLeave", function() GameTooltip:Hide() end)
        subY = subY - (32 + ROW_GAP)
    end

    -- Position dropdown (Top / Bottom)
    do
        local posLbl = sidebarSub:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        posLbl:SetPoint("TOPLEFT", sidebarSub, "TOPLEFT", 0, subY)
        posLbl:SetHeight(ROW_H); posLbl:SetJustifyH("LEFT")
        posLbl:SetText("Button start position")
        subY = subY - (ROW_H + 2)

        local POS_ITEMS = {
            { key = false, label = "Top (default)" },
            { key = true,  label = "Bottom" },
        }
        local curBottom = db.sidebarAtBottom == true
        local posDD = CreateFrame("DropdownButton", nil, sidebarSub, "WowStyle1DropdownTemplate")
        posDD:SetPoint("TOPLEFT", sidebarSub, "TOPLEFT", 0, subY)
        posDD:SetWidth(CONTENT_W)
        posDD:SetupMenu(function(_, root)
            for _, item in ipairs(POS_ITEMS) do
                root:CreateRadio(item.label,
                    function() return curBottom == item.key end,
                    function()
                        curBottom = item.key
                        db.sidebarAtBottom = item.key
                        posDD:GenerateMenu()
                        if BNB.Sidebar and BNB.Sidebar.Refresh then BNB.Sidebar.Refresh() end
                    end)
            end
        end)
        posDD:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine("Button start position", 1, 1, 1)
            GameTooltip:AddLine("Stack buttons from the top or bottom of the sidebar strip.", 0.8, 0.8, 0.8, true)
            GameTooltip:Show()
        end)
        posDD:SetScript("OnLeave", function() GameTooltip:Hide() end)
        subY = subY - (32 + ROW_GAP)
    end

    -- Small icons toggle
    do
        local smallCb = CreateFrame("CheckButton", nil, sidebarSub, "UICheckButtonTemplate")
        smallCb:SetSize(24, 24)
        smallCb:SetPoint("TOPLEFT", sidebarSub, "TOPLEFT", -2, subY + 2)
        smallCb:SetChecked(db.sidebarSmallIcons == true)
        smallCb:SetScript("OnClick", function(self)
            db.sidebarSmallIcons = self:GetChecked() and true or false
            if BNB.Sidebar and BNB.Sidebar.Refresh then BNB.Sidebar.Refresh() end
        end)
        smallCb:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine("Use smaller icons (half-size buttons).", 0.8, 0.8, 0.8, true)
            GameTooltip:Show()
        end)
        smallCb:SetScript("OnLeave", function() GameTooltip:Hide() end)
        local smallLbl = sidebarSub:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        smallLbl:SetPoint("LEFT",  smallCb, "RIGHT", 4, 0)
        smallLbl:SetPoint("RIGHT", sidebarSub, "RIGHT", 0, 0)
        smallLbl:SetJustifyH("LEFT"); smallLbl:SetHeight(ROW_H)
        smallLbl:SetText("Use small icons (half size)")
        subY = subY - (ROW_H + ROW_GAP)
    end

    -- Description text
    local descLbl = sidebarSub:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    descLbl:SetPoint("TOPLEFT", sidebarSub, "TOPLEFT", 0, subY)
    descLbl:SetWidth(CONTENT_W); descLbl:SetJustifyH("LEFT")
    descLbl:SetWordWrap(true); descLbl:SetHeight(36)
    descLbl:SetTextColor(0.65, 0.65, 0.65)
    descLbl:SetText("Right-click a character icon in the sidebar to pin or hide it. Pinned characters appear at the top (max 5).")
    subY = subY - 42

    -- Hidden characters header
    local hiddenHdr = sidebarSub:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    hiddenHdr:SetPoint("TOPLEFT", sidebarSub, "TOPLEFT", 0, subY)
    hiddenHdr:SetHeight(ROW_H); hiddenHdr:SetJustifyH("LEFT")
    hiddenHdr:SetText("Hidden characters:")
    subY = subY - (ROW_H + 2)

    -- Hidden characters dynamic list.
    -- Rows are Frames; old ones are orphaned (SetParent nil) on each rebuild
    -- so their CreateTexture/CreateFontString children don't accumulate.
    local hiddenListY = subY
    local _hiddenRowPool = {}
    local _hiddenRowCount = 0

    local function RebuildHiddenList()
        for i = 1, _hiddenRowCount do
            if _hiddenRowPool[i] then
                _hiddenRowPool[i]:Hide()
                _hiddenRowPool[i]:SetParent(nil)
                _hiddenRowPool[i] = nil
            end
        end
        _hiddenRowCount = 0

        local chars = db.knownChars or {}
        local hidden = {}
        for charKey, rec in pairs(chars) do
            if rec.slotHidden then
                hidden[#hidden + 1] = { key = charKey, rec = rec }
            end
        end
        table.sort(hidden, function(a, b)
            return (a.rec.name or a.key) < (b.rec.name or b.key)
        end)

        local rowY = hiddenListY
        for _, h in ipairs(hidden) do
            _hiddenRowCount = _hiddenRowCount + 1
            local row = CreateFrame("Frame", nil, sidebarSub)
            row:SetHeight(26)
            row:SetPoint("TOPLEFT",  sidebarSub, "TOPLEFT",  0, rowY)
            row:SetPoint("TOPRIGHT", sidebarSub, "TOPRIGHT", 0, rowY)
            local lbl = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            lbl:SetPoint("LEFT",  row, "LEFT",  0,   0)
            lbl:SetPoint("RIGHT", row, "RIGHT", -90, 0)
            lbl:SetJustifyH("LEFT"); lbl:SetHeight(26)
            lbl:SetText((h.rec.name or h.key)
                .. "  |cff888888(" .. (h.rec.realm or "") .. ")|r")
            local showBtn = BNB.CreateButton(nil, row, "Show", 80, 22)
            showBtn:SetPoint("RIGHT", row, "RIGHT", 0, 0)
            local capturedKey = h.key
            showBtn:SetScript("OnClick", function()
                if db.knownChars[capturedKey] then
                    db.knownChars[capturedKey].slotHidden = false
                end
                if BNB.Sidebar and BNB.Sidebar.Refresh then BNB.Sidebar.Refresh() end
                RebuildHiddenList()
            end)
            _hiddenRowPool[_hiddenRowCount] = row
            rowY = rowY - 30
        end

        if #hidden == 0 then
            _hiddenRowCount = 1
            local row = CreateFrame("Frame", nil, sidebarSub)
            row:SetHeight(20)
            row:SetPoint("TOPLEFT", sidebarSub, "TOPLEFT", 0, hiddenListY)
            local nl = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            nl:SetAllPoints(row); nl:SetJustifyH("LEFT")
            nl:SetTextColor(0.45, 0.45, 0.45); nl:SetText("None")
            _hiddenRowPool[1] = row
            rowY = hiddenListY - 24
        end

        local subH = math.abs(rowY) + 8
        sidebarSub:SetHeight(subH)
    end

    sf:HookScript("OnShow", RebuildHiddenList)
    RebuildHiddenList()

    -- y must advance past the sub-frame; GetHeight() is now set by RebuildHiddenList
    y = y - sidebarSub:GetHeight()

    local function ApplySidebarSection(enabled)
        sidebarSub:SetAlpha(enabled and 1 or 0.35)
        autoSwCb:SetEnabled(enabled)
        -- Reset filter to "All notes" when sidebar is disabled so the note
        -- list doesn't stay locked to the previously selected character.
        if not enabled and BNB.Sidebar and BNB.Sidebar.SetActive then
            BNB.Sidebar.SetActive("all")
        end
        if BNB.Sidebar and BNB.Sidebar.Refresh then BNB.Sidebar.Refresh() end
        if BNB.SyncSidebarWysiwygBtns then BNB.SyncSidebarWysiwygBtns() end
    end

    sidebarEnableCb:SetScript("OnClick", function(self)
        db.sidebarEnabled = self:GetChecked() and true or false
        ApplySidebarSection(db.sidebarEnabled)
    end)

    ApplySidebarSection(db.sidebarEnabled == true)

    -- ── Tag Tree ──────────────────────────────────────────────────────────────
    AddRule(ct, y); y = y - 18
    y = AddHeader(ct, y - 8, L["CFG_TAGTREE_HEADER"])

    y = AddCheck(ct, y, L["CFG_TAGTREE_STAY_OPEN"],
        function() return db.tagTreeStayOpen ~= false end,
        function(v) db.tagTreeStayOpen = v end,
        L["CFG_TAGTREE_STAY_OPEN_TIP"])

    y = AddCheck(ct, y, L["CFG_TAGTREE_START_EXPANDED"],
        function() return db.tagTreeStartExpanded == true end,
        function(v) db.tagTreeStartExpanded = v end,
        L["CFG_TAGTREE_START_EXPANDED_TIP"])

    sf:FinaliseHeight(math.abs(y) + 12)
end

-- ─────────────────────────────────────────────────────────────────────────────
-- TAB 4 — ADVANCED
-- ─────────────────────────────────────────────────────────────────────────────
local function BuildAdvancedTab(sf, ct)
    local db = BigNoteBoxDB
    local y  = -8

    y = AddHeader(ct, y, "Behavior")

    y = AddCheck(ct, y, L["CONFIG_SHOW_MINIMAP"],
        function() return not (db.minimapIcon and db.minimapIcon.hide) end,
        function(v) BNB.SetMinimapButtonShown(v) end,
        "Show the BigNoteBox button on the minimap.")

    y = AddCheck(ct, y, L["CONFIG_HIDE_LOGIN_MSG"],
        function() return db.hideLoginMessage == true end,
        function(v) db.hideLoginMessage = v end,
        "Suppress the \"BigNoteBox v... loaded\" chat message on login.")

    -- ── Migrate section (only shown if any supported addon is installed) ─────────
    if BNB.Migration and BNB.Migration.HasAny() then
        AddRule(ct, y); y = y - 18
        y = AddHeader(ct, y, "Migrate")

        local migDesc = ct:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        migDesc:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
        migDesc:SetWidth(CONTENT_W); migDesc:SetJustifyH("LEFT")
        migDesc:SetWordWrap(true)
        migDesc:SetTextColor(0.60, 0.60, 0.60)
        migDesc:SetText("Import notes from other note-taking addons. Your notes in those addons are not affected.")
        y = y - 36

        -- Use the Migration module's own key/name tables so this list stays
        -- in sync automatically whenever new addons are added to MigrateNotes.lua.
        local M = BNB.Migration
        for _, k in ipairs(M.ADDON_KEYS) do
            if C_AddOns.IsAddOnLoaded(M.ADDON_LOAD_NAME[k] or k) then
                local displayName = M.ADDON_NAMES[k] or k
                local isDone = db.migrationDone and db.migrationDone[k]

                -- Row: label + status badge + button
                local rowLbl = ct:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                rowLbl:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
                rowLbl:SetText(displayName)

                local statusLbl = ct:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                statusLbl:SetPoint("LEFT", rowLbl, "RIGHT", 8, 0)
                if isDone then
                    statusLbl:SetText("|cff66bb6aDone|r")
                else
                    statusLbl:SetText("|cff888888Not yet|r")
                end

                local migrateRowBtn = BNB.CreateButton(nil, ct, isDone and "Migrate Again" or "Migrate", 110, 22)
                migrateRowBtn:SetPoint("TOPRIGHT", ct, "TOPRIGHT", 0, y)
                migrateRowBtn:SetScript("OnClick", function()
                    if M.ShowAddonPopup then
                        M.ShowAddonPopup(k)
                    end
                end)

                y = y - (ROW_H + ROW_GAP)
            end
        end
    end

    -- ── Fonts section ───────────────────────────────────────────────────────────
    AddRule(ct, y); y = y - 18
    y = AddHeader(ct, y, "Fonts")

    local lsmAvail = LibStub and LibStub("LibSharedMedia-3.0", true) ~= nil
    if lsmAvail then
        local lsmWasOn = db.lsmFonts == true
        local lsmReloadLbl  -- shown after toggle
        y = AddCheck(ct, y, L["CFG_LSM_FONTS"],
            function() return db.lsmFonts == true end,
            function(v)
                db.lsmFonts = v
                if lsmReloadLbl then lsmReloadLbl:SetShown(v ~= lsmWasOn) end
            end,
            L["CFG_LSM_FONTS_TIP"])

        -- Inline "Reload required" label + button, hidden until the value changes
        lsmReloadLbl = ct:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        lsmReloadLbl:SetPoint("TOPLEFT", ct, "TOPLEFT", 22, y + 2)
        lsmReloadLbl:SetTextColor(1, 0.82, 0, 1)
        lsmReloadLbl:SetText(L["CFG_LSM_FONTS_RELOAD"])
        lsmReloadLbl:Hide()

        local lsmReloadBtn = BNB.CreateButton(nil, ct, "Reload UI", 90, 20)
        lsmReloadBtn:SetPoint("LEFT", lsmReloadLbl, "RIGHT", 8, 0)
        lsmReloadBtn:SetScript("OnClick", function()
            C_UI.Reload()
        end)
        lsmReloadBtn:Hide()

        -- Wire both to show together
        hooksecurefunc(lsmReloadLbl, "SetShown", function(_, shown)
            lsmReloadBtn:SetShown(shown)
        end)

        y = y - 26
    else
        -- LSM not present: show a greyed notice so the user knows why there's no checkbox
        local lsmMissingLbl = ct:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        lsmMissingLbl:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
        lsmMissingLbl:SetWidth(CONTENT_W)
        lsmMissingLbl:SetJustifyH("LEFT")
        lsmMissingLbl:SetTextColor(0.45, 0.45, 0.45)
        lsmMissingLbl:SetText(L["CFG_LSM_FONTS_MISSING"] .. " -- install an addon that provides LibSharedMedia-3.0 to enable this option.")
        y = y - 28
    end

    -- ── Keybindings section ───────────────────────────────────────────────────
    AddRule(ct, y); y = y - 18
    y = AddHeader(ct, y, "Keybindings")

    y = MakeKeybindRow(ct, y, L["CFG_KB_NEW_NOTE"],
        "BIGNOTEBOXNEWNOTE",   "(Default: unbound)", "Create new note")
    y = MakeKeybindRow(ct, y, L["CFG_KB_QUICK_NOTE"],
        "BIGNOTEBOXQUICKNOTE", "(Default: unbound)", "Create quick note")

    -- ── Danger Zone ──────────────────────────────────────────────────────────
    AddRule(ct, y); y = y - 18
    y = AddHeader(ct, y, "Danger Zone")

    local dzDesc = ct:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    dzDesc:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
    dzDesc:SetWidth(CONTENT_W); dzDesc:SetJustifyH("LEFT"); dzDesc:SetWordWrap(true)
    dzDesc:SetTextColor(0.75, 0.40, 0.40)
    dzDesc:SetText("Destructive and irreversible actions: reset settings, clear history, delete notes, and more.")
    local dzDescH = 32
    dzDesc:SetHeight(dzDescH)
    y = y - (dzDescH + 6)

    local dzBtn = BNB.CreateButton(nil, ct, "Danger Zone!", CONTENT_W, 28)
    dzBtn:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
    if dzBtn.SetBackdropColor then
        dzBtn:SetBackdropColor(0.25, 0.04, 0.04, 0.95)
        dzBtn:SetBackdropBorderColor(0.65, 0.10, 0.10, 1)
    end
    dzBtn:SetScript("OnEnter", function(self)
        if self.SetBackdropColor then self:SetBackdropColor(0.35, 0.06, 0.06, 0.95) end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Danger Zone", 1, 0.3, 0.3)
        GameTooltip:AddLine("Opens the Danger Zone window with destructive reset options.", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    dzBtn:SetScript("OnLeave", function(self)
        if self.SetBackdropColor then self:SetBackdropColor(0.25, 0.04, 0.04, 0.95) end
        GameTooltip:Hide()
    end)
    dzBtn:SetScript("OnClick", function()
        if BNB.DangerZone and BNB.DangerZone.Open then BNB.DangerZone.Open() end
    end)
    y = y - 34

        -- ── Developer section (below Danger Zone) ────────────────────────────────
    AddRule(ct, y); y = y - 18
    y = AddHeader(ct, y, "Developer")

    local devDesc2 = ct:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    devDesc2:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
    devDesc2:SetWidth(CONTENT_W); devDesc2:SetJustifyH("LEFT")
    devDesc2:SetWordWrap(true); devDesc2:SetHeight(20)
    devDesc2:SetTextColor(0.50, 0.50, 0.50)
    devDesc2:SetText("Debug and testing tools. Not required for normal use.")
    y = y - 24

    local devWidgets2 = {}

    local debugCb2 = CreateFrame("CheckButton", nil, ct, "UICheckButtonTemplate")
    debugCb2:SetSize(24, 24)
    debugCb2:SetPoint("TOPLEFT", ct, "TOPLEFT", -2, y + 2)
    debugCb2:SetChecked(db.debugMode == true)
    local debugLbl2 = ct:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    debugLbl2:SetPoint("LEFT", debugCb2, "RIGHT", 4, 0)
    debugLbl2:SetJustifyH("LEFT"); debugLbl2:SetHeight(ROW_H)
    debugLbl2:SetText("Activate Debug mode")
    debugCb2:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Enables debug and testing tools below.\nPrints extra info to chat when tests are active.", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    debugCb2:SetScript("OnLeave", function() GameTooltip:Hide() end)
    y = y - (ROW_H + ROW_GAP)

    local function RefreshDevState2()
        local on = db.debugMode == true
        for _, w in ipairs(devWidgets2) do
            if w.cb then w.cb:SetEnabled(on); w.cb:SetAlpha(on and 1.0 or 0.4) end
            if w.lbl then w.lbl:SetTextColor(on and 1 or 0.45, on and 0.82 or 0.45, on and 0 or 0.45) end
        end
    end

    debugCb2:SetScript("OnClick", function(self)
        db.debugMode = self:GetChecked() and true or nil
        BNB._debugMode = db.debugMode
        if db.debugMode then BNB:Print("|cff88bbffDebug mode enabled.|r")
        else
            BNB:Print("|cff88bbffDebug mode disabled.|r")
            db.debugWaypoint = nil; BNB._debugWaypoint = nil
        end
        RefreshDevState2()
    end)

    local wpTestCb2 = CreateFrame("CheckButton", nil, ct, "UICheckButtonTemplate")
    wpTestCb2:SetSize(24, 24)
    wpTestCb2:SetPoint("TOPLEFT", ct, "TOPLEFT", 18, y + 2)
    wpTestCb2:SetChecked(db.debugWaypoint == true)
    local wpTestLbl2 = ct:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    wpTestLbl2:SetPoint("LEFT", wpTestCb2, "RIGHT", 4, 0)
    wpTestLbl2:SetJustifyH("LEFT"); wpTestLbl2:SetHeight(ROW_H)
    wpTestLbl2:SetText("Test waypoint system")
    wpTestCb2:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("When enabled, prints waypoint debug info to chat:", 0.8, 0.8, 0.8, true)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("/bnb testwp status — shows current note's waypoint data", 0.55, 0.85, 1)
        GameTooltip:AddLine("/bnb testwp fire — simulates zone-enter (places waypoints)", 0.55, 0.85, 1)
        GameTooltip:AddLine("/bnb testwp leave — simulates zone-leave (clears waypoints)", 0.55, 0.85, 1)
        GameTooltip:AddLine("/bnb testwp auto — shows auto-placed waypoint tracking", 0.55, 0.85, 1)
        GameTooltip:Show()
    end)
    wpTestCb2:SetScript("OnLeave", function() GameTooltip:Hide() end)
    wpTestCb2:SetScript("OnClick", function(self)
        local on = self:GetChecked() and true or nil
        db.debugWaypoint = on; BNB._debugWaypoint = on
        if on then BNB:Print("|cff88bbffWaypoint debug ON.|r Use |cffffff00/bnb testwp status|fire|leave|auto|r")
        else BNB:Print("|cff88bbffWaypoint debug OFF.|r") end
    end)
    devWidgets2[#devWidgets2 + 1] = { cb = wpTestCb2, lbl = wpTestLbl2 }
    y = y - (ROW_H + ROW_GAP)

    local toastTestBtn2 = BNB.CreateButton(nil, ct, "Fire Test Toast", 140, 22)
    toastTestBtn2:SetPoint("TOPLEFT", ct, "TOPLEFT", 18, y + 2)
    toastTestBtn2:SetScript("OnClick", function()
        if not (db.debugMode == true) then return end
        BNB:Print("|cff88bbffFiring test toast...|r")
        BNB._contextMatches = {}
        if BNB.CheckContextualNotes then BNB.CheckContextualNotes() end
        local matches = BNB._contextMatches or {}
        if #matches == 0 then
            BNB:Print("|cffff9900No notes match your current zone. Bind a note to your current zone first.|r")
        else
            BNB:Print(string.format("|cff88bbff%d note(s) matched — toast should appear.|r", #matches))
        end
    end)
    toastTestBtn2:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Fire a test context toast", 1, 1, 1)
        GameTooltip:AddLine("Triggers CheckContextualNotes as if you just entered your current zone.", 0.78, 0.78, 0.78, true)
        GameTooltip:Show()
    end)
    toastTestBtn2:SetScript("OnLeave", function() GameTooltip:Hide() end)
    devWidgets2[#devWidgets2 + 1] = { cb = toastTestBtn2, lbl = nil }
    y = y - (ROW_H + ROW_GAP)

    local immDbgCb2 = CreateFrame("CheckButton", nil, ct, "UICheckButtonTemplate")
    immDbgCb2:SetSize(24, 24)
    immDbgCb2:SetPoint("TOPLEFT", ct, "TOPLEFT", 18, y + 2)
    immDbgCb2:SetChecked(false)
    local immDbgLbl2 = ct:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    immDbgLbl2:SetPoint("LEFT", immDbgCb2, "RIGHT", 4, 0)
    immDbgLbl2:SetJustifyH("LEFT"); immDbgLbl2:SetHeight(ROW_H)
    immDbgLbl2:SetText("Debug Immersion button position")
    immDbgCb2:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Debug Immersion button position", 1, 1, 1)
        GameTooltip:AddLine("When enabled, prints the saved X/Y offset to chat every time you shift-drag and release the button.", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    immDbgCb2:SetScript("OnLeave", function() GameTooltip:Hide() end)
    immDbgCb2:SetScript("OnClick", function(self)
        BNB._debugImmersionPos = self:GetChecked() and true or nil
        if BNB._debugImmersionPos then
            BNB:Print("|cff88bbff[BNB] Immersion position debug ON. Shift-drag the button to see coords.|r")
        else
            BNB:Print("|cff88bbff[BNB] Immersion position debug OFF.|r")
        end
    end)
    devWidgets2[#devWidgets2 + 1] = { cb = immDbgCb2, lbl = immDbgLbl2 }
    y = y - (ROW_H + ROW_GAP)

    RefreshDevState2()

    sf:FinaliseHeight(math.abs(y) + 20)
end

-- ─────────────────────────────────────────────────────────────────────────────
-- TAB 4 (new) -- EDITOR
-- Undo/redo depth + WYSIWYG toolbar toggle.
-- ─────────────────────────────────────────────────────────────────────────────
local function BuildEditorTab(sf, ct)
    local db = BigNoteBoxDB
    local y  = -8

    -- ── Formatting Toolbar ────────────────────────────────────────────────────
    y = AddHeader(ct, y, "Formatting Toolbar")

    local tbDesc = ct:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    tbDesc:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
    tbDesc:SetWidth(CONTENT_W); tbDesc:SetJustifyH("LEFT")
    tbDesc:SetWordWrap(true); tbDesc:SetHeight(28)
    tbDesc:SetTextColor(0.60, 0.60, 0.60)
    tbDesc:SetText("A small toolbar between the timestamp and note body. Contains Undo/Redo and future formatting buttons.")
    y = y - 32

    y = AddCheck(ct, y, "Show formatting toolbar in editor",
        function() return BigNoteBoxDB and BigNoteBoxDB.wysiwygBarVisible ~= false end,
        function(v)
            if BigNoteBoxDB then BigNoteBoxDB.wysiwygBarVisible = v end
            if BNB.ToggleWysiwygBar then BNB.ToggleWysiwygBar(v) end
        end,
        "Toggle the WYSIWYG formatting toolbar (Undo, Redo, and future buttons).\nCan also be toggled with the button above the toolbar in the editor.")

    -- ── Rich Notes ───────────────────────────────────────────────────────────
    AddRule(ct, y); y = y - 18
    y = AddHeader(ct, y, L["CFG_RICH_SIZES_HEADER"])

    -- Moved from Features tab: new-note default + open-in-editor behaviours
    y = AddCheck(ct, y, L["CFG_RICH_NOTES_DEFAULT"],
        function() return db.newNotesRichByDefault == true end,
        function(v) db.newNotesRichByDefault = v end,
        L["CFG_RICH_NOTES_DEFAULT_TIP"])

    y = AddCheck(ct, y, L["CFG_RICH_OPEN_EDITOR"],
        function() return db.richOpenInEditor == true end,
        function(v) db.richOpenInEditor = v end,
        L["CFG_RICH_OPEN_EDITOR_TIP"])

    y = MakeKeybindRow(ct, y, L["CFG_KB_TOGGLE_RV"], "BIGNOTEBOXTOGGLERV", "(No default)", L["CFG_KB_TOGGLE_RV_TIP"])

    -- ── Heading sizes ─────────────────────────────────────────────────────────
    -- Helper: trigger a live re-render of the currently open rich note preview.
    local function TriggerRichRerender()
        if BNB.RichPreview and BNB.RichPreview.ScheduleRender then
            BNB.RichPreview.ScheduleRender()
        end
        if BNB.RichPreviewFocus and BNB.RichPreviewFocus.ScheduleRefresh then
            BNB.RichPreviewFocus.ScheduleRefresh()
        end
    end

    -- Helper: what each size would be in multiplier mode (used for greyed display).
    local function MultiplierSize(mult)
        local base = (db and db.fontSize) or 13
        return math.floor(base * mult + 0.5)
    end

    local indepActive = db and db.richIndependentSizes == true
    local sizeSliders = {}

    local function SetSlidersEnabled(enabled)
        for _, sl in ipairs(sizeSliders) do
            sl:SetAlpha(enabled and 1.0 or 0.4)
            sl:EnableMouse(enabled)
            if sl.Slider then sl.Slider:SetEnabled(enabled) end
        end
    end

    -- Checkbox first so it sits above the sliders in the layout flow.
    local indepCb = CreateFrame("CheckButton", nil, ct, "UICheckButtonTemplate")
    indepCb:SetSize(24, 24)
    indepCb:SetPoint("TOPLEFT", ct, "TOPLEFT", -2, y + 2)
    indepCb:SetChecked(indepActive)
    local indepLbl = ct:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    indepLbl:SetPoint("LEFT",  indepCb, "RIGHT", 4, 0)
    indepLbl:SetPoint("RIGHT", ct,      "RIGHT", 0, 0)
    indepLbl:SetJustifyH("LEFT"); indepLbl:SetHeight(ROW_H)
    indepLbl:SetText(L["CFG_RICH_SIZES_INDEPENDENT"])
    indepCb:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(L["CFG_RICH_SIZES_IND_TIP"], 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    indepCb:SetScript("OnLeave", function() GameTooltip:Hide() end)
    y = y - (ROW_H + ROW_GAP)

    -- Four size sliders — built after checkbox so indepCb is in scope for OnClick.
    local h1sl, h2sl, h3sl, psl

    local function MakeSizeSlider(label, dbKey, default, mult)
        -- In multiplier mode show the derived value so the user sees what they'd take over.
        local initVal = indepActive
            and (db and db[dbKey] or default)
            or  MultiplierSize(mult)
        local sl = BNB.CreateSlider(ct, label, 6, 72, initVal, default,
            function(v)
                if not (db and db.richIndependentSizes) then return end
                if db then db[dbKey] = math.floor(v + 0.5) end
                TriggerRichRerender()
            end)
        sl:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
        sl:SetWidth(CONTENT_W)
        sizeSliders[#sizeSliders + 1] = sl
        return sl
    end

    h1sl = MakeSizeSlider(L["CFG_RICH_SIZE_H1"], "richH1Size",   25, 2.0); y = y - (SLIDER_H + ROW_GAP)
    h2sl = MakeSizeSlider(L["CFG_RICH_SIZE_H2"], "richH2Size",   20, 1.6); y = y - (SLIDER_H + ROW_GAP)
    h3sl = MakeSizeSlider(L["CFG_RICH_SIZE_H3"], "richH3Size",   16, 1.3); y = y - (SLIDER_H + ROW_GAP)
    psl  = MakeSizeSlider(L["CFG_RICH_SIZE_P"],  "richBodySize", 12, 1.0); y = y - (SLIDER_H + ROW_GAP)

    -- Wire checkbox OnClick now that all slider locals are defined.
    indepCb:SetScript("OnClick", function(self)
        local on = self:GetChecked() and true or false
        if db then db.richIndependentSizes = on end
        SetSlidersEnabled(on)
        if on then
            -- Snap to stored DB values (or defaults) when switching on
            h1sl:SetValue(db and db.richH1Size   or 25)
            h2sl:SetValue(db and db.richH2Size   or 20)
            h3sl:SetValue(db and db.richH3Size   or 16)
            psl:SetValue( db and db.richBodySize or 12)
        else
            -- Show multiplier ghost values when switching off
            h1sl:SetValue(MultiplierSize(2.0))
            h2sl:SetValue(MultiplierSize(1.6))
            h3sl:SetValue(MultiplierSize(1.3))
            psl:SetValue( MultiplierSize(1.0))
            TriggerRichRerender()
        end
    end)

    SetSlidersEnabled(indepActive)

    -- ── Live Preview ─────────────────────────────────────────────────────────
    AddRule(ct, y); y = y - 18
    y = AddHeader(ct, y, "Live Preview")

    do
        local lpDesc = ct:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        lpDesc:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
        lpDesc:SetWidth(CONTENT_W); lpDesc:SetJustifyH("LEFT")
        lpDesc:SetWordWrap(true); lpDesc:SetHeight(28)
        lpDesc:SetTextColor(0.60, 0.60, 0.60)
        lpDesc:SetText("Controls for the rich note live preview window that renders markup in real-time as you type.")
        y = y - 32
    end

    y = AddCheck(ct, y, L["CFG_RICH_PREVIEW_AUTO"],
        function() return db.richPreviewAutoShow ~= false end,
        function(v) db.richPreviewAutoShow = v end,
        L["CFG_RICH_PREVIEW_AUTO_TIP"])

    y = AddCheck(ct, y, L["CFG_FOCUS_PREVIEW_ALWAYS"],
        function() return db.focusPreviewAlwaysShow ~= false end,
        function(v)
            if BigNoteBoxDB then BigNoteBoxDB.focusPreviewAlwaysShow = v end
        end,
        L["CFG_FOCUS_PREVIEW_ALWAYS_TIP"])

    do
        local dlDesc = ct:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        dlDesc:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
        dlDesc:SetWidth(CONTENT_W); dlDesc:SetJustifyH("LEFT")
        dlDesc:SetWordWrap(true)
        dlDesc:SetTextColor(0.55, 0.55, 0.55)
        dlDesc:SetText("Update delay: how long after your last keystroke before the preview re-renders. Lower values feel snappier but may cause hitching on very long notes.")
        local h = dlDesc:GetStringHeight() + 4
        dlDesc:SetHeight(h); y = y - h - 2
    end

    local SLIDER_W = CONTENT_W - 20
    local curDebounce = db and db.previewDebounce or 0.3
    local debounceSlider = BNB.CreateSlider(ct, "Update delay (seconds)", 1, 10,
        math.floor(curDebounce * 10 + 0.5), 3,
        function(v)
            local val = v / 10
            if BigNoteBoxDB then BigNoteBoxDB.previewDebounce = val end
        end,
        function(v) return string.format("%.1f", v / 10) end)
    debounceSlider:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
    debounceSlider:SetWidth(SLIDER_W)
    debounceSlider:EnableMouse(true)
    debounceSlider:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Preview update delay", 1, 1, 1)
        GameTooltip:AddLine("How long after your last keystroke before the live preview re-renders.", 0.8, 0.8, 0.8, true)
        GameTooltip:AddLine("Lower = more responsive. Default: 0.3s.", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    debounceSlider:SetScript("OnLeave", function() GameTooltip:Hide() end)
    y = y - (SLIDER_H + ROW_GAP)

    -- ── Undo / Redo ───────────────────────────────────────────────────────────
    AddRule(ct, y); y = y - 18
    y = AddHeader(ct, y, "Undo / Redo")

    local undoDesc = ct:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    undoDesc:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
    undoDesc:SetWidth(CONTENT_W); undoDesc:SetJustifyH("LEFT")
    undoDesc:SetWordWrap(true); undoDesc:SetHeight(28)
    undoDesc:SetTextColor(0.60, 0.60, 0.60)
    undoDesc:SetText("History is per-note and per-session only. Stacks are cleared on reload or logout.")
    y = y - 32

    -- Warning label declared before slider so the onChange closure can reference it.
    -- Anchored relative to where the slider will sit (y - SLIDER_H - ROW_GAP).
    local warnLbl = ct:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    warnLbl:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y - (SLIDER_H + ROW_GAP))
    warnLbl:SetWidth(CONTENT_W); warnLbl:SetJustifyH("LEFT")
    warnLbl:SetWordWrap(true); warnLbl:SetHeight(28)
    warnLbl:SetTextColor(0.90, 0.30, 0.30)
    warnLbl:SetText("High depth uses more memory. Keep at 50 or below if you edit many notes simultaneously in the same session.")
    local curDepth = db and db.undoDepth or 50
    warnLbl:SetShown(curDepth > 50)

    -- Slider width: subtract extra 20px so the 3-digit value label is never clipped.
    local SLIDER_W = CONTENT_W - 20
    local depthSlider = BNB.CreateSlider(ct, "History depth", 10, 200,
        curDepth, 50,
        function(v)
            local val = math.floor(v + 0.5)
            if BigNoteBoxDB then BigNoteBoxDB.undoDepth = val end
            warnLbl:SetShown(val > 50)
        end)
    depthSlider:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
    depthSlider:SetWidth(SLIDER_W)
    depthSlider:EnableMouse(true)
    depthSlider:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("How many undo steps to keep per note.", 0.8, 0.8, 0.8, true)
        GameTooltip:AddLine("Default: 50. Higher values use more RAM per note.", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    depthSlider:SetScript("OnLeave", function() GameTooltip:Hide() end)
    y = y - (SLIDER_H + ROW_GAP)

    -- Always reserve warning label height so layout stays stable
    y = y - 34

    -- Idle delay slider (0.3 – 3.0 s, step 0.1, default 0.8)
    -- Stored as a float; displayed with one decimal place.
    do
        local lbl = ct:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        lbl:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
        lbl:SetWidth(CONTENT_W); lbl:SetJustifyH("LEFT"); lbl:SetWordWrap(true)
        lbl:SetTextColor(0.55, 0.55, 0.55)
        lbl:SetText("Idle delay: how long after your last keystroke before a snapshot is saved. Lower = more frequent saves.")
        local h = lbl:GetStringHeight() + 4
        lbl:SetHeight(h); y = y - h - 2
    end
    local curIdle = db and db.undoIdleDelay or 0.8
    local idleSlider = BNB.CreateSlider(ct, "Idle delay (seconds)", 3, 30,
        math.floor(curIdle * 10 + 0.5), 8,
        function(v)
            local val = v / 10
            if BigNoteBoxDB then BigNoteBoxDB.undoIdleDelay = val end
        end,
        function(v) return string.format("%.1f", v / 10) end)
    idleSlider:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
    idleSlider:SetWidth(SLIDER_W)
    idleSlider:EnableMouse(true)
    idleSlider:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Idle delay", 1, 1, 1)
        GameTooltip:AddLine("How long after your last keystroke before a snapshot is saved.", 0.8, 0.8, 0.8, true)
        GameTooltip:AddLine("Lower = more frequent snapshots. Default: 0.8s.", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    idleSlider:SetScript("OnLeave", function() GameTooltip:Hide() end)
    y = y - (SLIDER_H + ROW_GAP)

    -- Forced interval slider (1 – 10 s, whole seconds, default 3)
    -- Fires even if you never stop typing, capping continuous-typing chunk size.
    do
        local lbl = ct:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        lbl:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
        lbl:SetWidth(CONTENT_W); lbl:SetJustifyH("LEFT"); lbl:SetWordWrap(true)
        lbl:SetTextColor(0.55, 0.55, 0.55)
        lbl:SetText("Forced interval: maximum time between snapshots while typing without pausing. A snapshot fires every N seconds even if you never stop.")
        local h = lbl:GetStringHeight() + 4
        lbl:SetHeight(h); y = y - h - 2
    end
    local curForced = db and db.undoForcedInterval or 3
    local forcedSlider = BNB.CreateSlider(ct, "Forced interval (seconds)", 1, 10,
        curForced, 3,
        function(v)
            local val = math.floor(v + 0.5)
            if BigNoteBoxDB then BigNoteBoxDB.undoForcedInterval = val end
        end)
    forcedSlider:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
    forcedSlider:SetWidth(SLIDER_W)
    forcedSlider:EnableMouse(true)
    forcedSlider:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Forced interval", 1, 1, 1)
        GameTooltip:AddLine("Maximum time between snapshots while typing continuously.", 0.8, 0.8, 0.8, true)
        GameTooltip:AddLine("Even if you never pause, a snapshot fires every N seconds.", 0.8, 0.8, 0.8, true)
        GameTooltip:AddLine("Lower = finer granularity. Default: 3s.", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    forcedSlider:SetScript("OnLeave", function() GameTooltip:Hide() end)
    y = y - (SLIDER_H + ROW_GAP)

    -- ── Session History ───────────────────────────────────────────────────────
    AddRule(ct, y); y = y - 18
    y = AddHeader(ct, y, "Session History")

    local histDesc = ct:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    histDesc:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
    histDesc:SetWidth(CONTENT_W); histDesc:SetJustifyH("LEFT")
    histDesc:SetWordWrap(true); histDesc:SetHeight(28)
    histDesc:SetTextColor(0.60, 0.60, 0.60)
    histDesc:SetText("Auto-snapshots are saved per note on each logout or reload. History only grows when notes change.")
    y = y - 32

    -- History slots slider
    local curSlots = BigNoteBoxDB and BigNoteBoxDB.historyMaxSlots or 5
    local slotsSlider = BNB.CreateSlider(ct, "Auto-save slots per note", 1, 20,
        curSlots, 5,
        function(v)
            local val = math.floor(v + 0.5)
            if BigNoteBoxDB then BigNoteBoxDB.historyMaxSlots = val end
        end)
    slotsSlider:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
    slotsSlider:SetWidth(SLIDER_W)
    slotsSlider:EnableMouse(true)
    slotsSlider:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Auto-save slots per note", 1, 1, 1)
        GameTooltip:AddLine("How many auto-snapshots to keep per note.", 0.8, 0.8, 0.8, true)
        GameTooltip:AddLine("Older entries are dropped when the limit is reached.", 0.8, 0.8, 0.8, true)
        GameTooltip:AddLine("Default: 5.", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    slotsSlider:SetScript("OnLeave", function() GameTooltip:Hide() end)
    y = y - (SLIDER_H + ROW_GAP)

    -- Size readout — computed when the tab is shown
    local histSizeLbl = ct:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    histSizeLbl:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
    histSizeLbl:SetWidth(CONTENT_W); histSizeLbl:SetJustifyH("LEFT")
    histSizeLbl:SetHeight(20)
    histSizeLbl:SetTextColor(0.45, 0.45, 0.45)
    histSizeLbl:SetText("History size: calculating...")
    y = y - 24

    -- Refresh size label when the Editor tab becomes visible
    sf:HookScript("OnShow", function()
        if BNB.HistoryTotalSize then
            local bytes = BNB.HistoryTotalSize()
            local ndb   = BigNoteBoxNotesDB
            local noteCount = 0
            if ndb and ndb.notes then
                for id in pairs(ndb.notes) do
                    if BNB.HistoryNoteHasAny and BNB.HistoryNoteHasAny(id) then
                        noteCount = noteCount + 1
                    end
                end
            end
            local sizeStr = BNB.HistoryFormatSize and BNB.HistoryFormatSize(bytes)
                or (math.floor(bytes / 1024) .. " KB")
            histSizeLbl:SetText(string.format(
                "History size: %s across %d note(s)",
                sizeStr, noteCount))
        end
    end)

    sf:FinaliseHeight(math.abs(y) + 12)
end

-- ─────────────────────────────────────────────────────────────────────────────
-- TAB 5 -- BACKUP  (Export / Import)
-- ─────────────────────────────────────────────────────────────────────────────

-- ── Export version — bump when the serialized format changes ─────────────────
local EXPORT_VERSION = 1

-- ── Format constants ──────────────────────────────────────────────────────────
local FMT_MARKDOWN = "markdown"
local FMT_JSON     = "json"

-- ── Minimal JSON helpers (no library required) ────────────────────────────────
-- Handles only the types present in our note schema:
--   string, number, boolean, nil, array-of-strings, {r,g,b} color table.
-- Does NOT handle arbitrary nested tables — intentional.

local function JsonEscapeStr(s)
    s = tostring(s)
    s = s:gsub("\\", "\\\\")
    s = s:gsub("\"", "\\\"")
    s = s:gsub("\n", "\\n")
    s = s:gsub("\r", "\\r")
    s = s:gsub("\t", "\\t")
    return "\"" .. s .. "\""
end

local function JsonEncodeNote(note)
    -- Encode tags array
    local tagParts = {}
    for _, t in ipairs(note.tags or {}) do
        tagParts[#tagParts + 1] = JsonEscapeStr(t)
    end
    local tagsJson = "[" .. table.concat(tagParts, ",") .. "]"

    -- Encode titleColor table or null
    local colorJson
    if note.titleColor then
        colorJson = string.format("{\"r\":%.4f,\"g\":%.4f,\"b\":%.4f}",
            note.titleColor.r or 1, note.titleColor.g or 1, note.titleColor.b or 1)
    else
        colorJson = "null"
    end

    -- Encode attachments array or null
    local attJson
    if note.attachments and #note.attachments > 0 then
        local attParts = {}
        for _, att in ipairs(note.attachments) do
            if att.type == "item" or att.type == "spell" then
                attParts[#attParts + 1] = string.format("{\"type\":\"%s\",\"id\":%d}", att.type, att.id)
            end
        end
        attJson = "[" .. table.concat(attParts, ",") .. "]"
    else
        attJson = "null"
    end

    -- Encode inspectGearItems array or null: [{id,slot,slotIdx}, ...]
    local gearJson
    if note.inspectGearItems and #note.inspectGearItems > 0 then
        local gp = {}
        for _, g in ipairs(note.inspectGearItems) do
            gp[#gp + 1] = string.format("{\"id\":%d,\"slot\":%s,\"slotIdx\":%d}",
                g.id or 0, JsonEscapeStr(g.slot or ""), g.slotIdx or 0)
        end
        gearJson = "[" .. table.concat(gp, ",") .. "]"
    else
        gearJson = "null"
    end

    -- Encode inspectTransmogItems array or null: [{id,slot,slotIdx,appearanceID}, ...]
    local tmogJson
    if note.inspectTransmogItems and #note.inspectTransmogItems > 0 then
        local tp = {}
        for _, t in ipairs(note.inspectTransmogItems) do
            tp[#tp + 1] = string.format("{\"id\":%d,\"slot\":%s,\"slotIdx\":%d,\"appearanceID\":%d}",
                t.id or 0, JsonEscapeStr(t.slot or ""), t.slotIdx or 0, t.appearanceID or 0)
        end
        tmogJson = "[" .. table.concat(tp, ",") .. "]"
    else
        tmogJson = "null"
    end

    -- Encode inspectTransmogAppearances object or null: {"slotIdx":appearanceID, ...}
    local tmogAppJson
    if note.inspectTransmogAppearances and next(note.inspectTransmogAppearances) then
        local ap = {}
        for slotIdx, appID in pairs(note.inspectTransmogAppearances) do
            ap[#ap + 1] = string.format("\"%d\":%d", slotIdx, appID)
        end
        tmogAppJson = "{" .. table.concat(ap, ",") .. "}"
    else
        tmogAppJson = "null"
    end

    -- Encode alarm sub-object or null
    local alarmJson
    if note.alarm then
        local a = note.alarm
        local gc = a.glowColor
        local glowColorJson = gc
            and string.format("[%.4f,%.4f,%.4f,%.4f]", gc[1] or 0, gc[2] or 0, gc[3] or 0, gc[4] or 1)
            or "null"
        local function abool(v) if v == nil then return "null" end return v and "true" or "false" end
        local function anum(v)  if v == nil then return "null" end return tostring(v) end
        local function astr(v)  if v == nil then return "null" end return JsonEscapeStr(tostring(v)) end
        -- recurDays is an array of booleans [{1=bool,...,7=bool}]
        local recurDaysJson = "null"
        if a.recurDays then
            local dp = {}
            for i = 1, 7 do dp[i] = a.recurDays[i] and "true" or "false" end
            recurDaysJson = "[" .. table.concat(dp, ",") .. "]"
        end
        alarmJson = string.format(
            "{\"time\":%s,\"timeType\":%s,\"fired\":%s,\"snoozedUntil\":%s," ..
            "\"recur\":%s,\"recurDays\":%s,\"recurEvery\":%s," ..
            "\"label\":%s,\"sound\":%s,\"fireMode\":%s," ..
            "\"combatMode\":%s,\"combatPost\":%s," ..
            "\"snoozeEnabled\":%s,\"snoozeDefault\":%s,\"igTime\":%s," ..
            "\"glowType\":%s,\"glowMode\":%s,\"glowColor\":%s," ..
            "\"glowLines\":%s,\"glowFrequency\":%s,\"glowLength\":%s," ..
            "\"glowParticles\":%s,\"glowScale\":%s,\"glowDuration\":%s}",
            anum(a.time),        astr(a.timeType),    abool(a.fired),      anum(a.snoozedUntil),
            astr(a.recur),       recurDaysJson,        anum(a.recurEvery),
            astr(a.label),       astr(a.sound),        astr(a.fireMode),
            astr(a.combatMode),  abool(a.combatPost),
            abool(a.snoozeEnabled), anum(a.snoozeDefault), anum(a.igTime),
            anum(a.glowType),    astr(a.glowMode),     glowColorJson,
            anum(a.glowLines),   anum(a.glowFrequency), anum(a.glowLength),
            anum(a.glowParticles), anum(a.glowScale),  anum(a.glowDuration))
    else
        alarmJson = "null"
    end

    local function field(k, v)
        if v == nil then return "\"" .. k .. "\":null" end
        if type(v) == "boolean" then return "\"" .. k .. "\":" .. (v and "true" or "false") end
        if type(v) == "number"  then return "\"" .. k .. "\":" .. tostring(v) end
        return "\"" .. k .. "\":" .. JsonEscapeStr(v)
    end

    local parts = {
        field("title",         note.title),
        field("body",          note.body),
        "\"tags\":"            .. tagsJson,
        field("context",       note.context),
        field("contextDisplay",note.contextDisplay),
        field("contextLeave",  note.contextLeave),
        field("pinned",        note.pinned or false),
        field("favorited",     note.favorited),
        field("locked",        note.locked),
        field("icon",          note.icon),
        "\"titleColor\":"      .. colorJson,
        field("fontOverride",  note.fontOverride),
        field("textAlign",     note.textAlign),
        field("fontOutline",   note.fontOutline),
        field("borderOverride",note.borderOverride),
        field("borderScale",   note.borderScale),
        field("borderOffset",  note.borderOffset),
        field("borderBrightness", note.borderBrightness),
        field("lineHeight",    note.lineHeight),
        field("scope",         note.scope),
        -- Waypoint: {mapID, x, y, label} table or null
        "\"waypoint\":"        .. (note.waypoint and string.format(
            "{\"mapID\":%d,\"x\":%.6f,\"y\":%.6f,\"label\":%s}",
            note.waypoint.mapID or 0,
            note.waypoint.x     or 0,
            note.waypoint.y     or 0,
            JsonEscapeStr(note.waypoint.label or "")) or "null"),
        field("wpClearOnLeave",note.wpClearOnLeave),
        field("richMode",      note.richMode),
        field("iconSource",    note.iconSource),
        field("source",        note.source),
        field("targetNpcID",       note.targetNpcID),
        field("targetPlayerKey",   note.targetPlayerKey),
        field("targetIsPet",       note.targetIsPet),
        field("inspectRaceID",     note.inspectRaceID),
        field("inspectSexID",      note.inspectSexID),
        field("created",       note.created),
        field("updated",       note.updated),
        "\"attachments\":"              .. attJson,
        "\"inspectGearItems\":"         .. gearJson,
        "\"inspectTransmogItems\":"     .. tmogJson,
        "\"inspectTransmogAppearances\":" .. tmogAppJson,
        "\"alarm\":"                    .. alarmJson,
    }
    return "  {" .. table.concat(parts, ",") .. "}"
end

local function JsonDecodeStr(s)
    -- Unescape a JSON string value (content between outer quotes already stripped)
    s = s:gsub("\\n",  "\n")
    s = s:gsub("\\r",  "\r")
    s = s:gsub("\\t",  "\t")
    s = s:gsub("\\\"", "\"")
    s = s:gsub("\\\\", "\\")
    return s
end

-- ── Markdown helpers ──────────────────────────────────────────────────────────

local function MdEscapeBody(body)
    -- The body goes between frontmatter and the next note separator (===).
    -- The only sequence that needs escaping is a line that is exactly "==="
    -- (our record separator). We prefix it with a zero-width space substitute
    -- — a single backslash, which is idiomatic in Markdown and easy to strip.
    body = body:gsub("\n===\n", "\n\\===\n")
    -- Also handle === at start or end of body
    if body:sub(1, 3) == "===" then body = "\\" .. body end
    return body
end

local function MdUnescapeBody(body)
    body = body:gsub("\n\\===\n", "\n===\n")
    if body:sub(1, 4) == "\\===" then body = body:sub(2) end
    return body
end

local function MdEncodeNote(note)
    local lines = {}
    lines[#lines + 1] = "title: " .. (note.title or "")
    if note.tags and #note.tags > 0 then
        lines[#lines + 1] = "tags: " .. table.concat(note.tags, ", ")
    end
    if note.context       then lines[#lines + 1] = "context: "        .. note.context        end
    if note.contextDisplay then lines[#lines + 1] = "contextDisplay: " .. note.contextDisplay end
    if note.contextLeave   then lines[#lines + 1] = "contextLeave: "   .. note.contextLeave   end
    if note.pinned         then lines[#lines + 1] = "pinned: true"                            end
    if note.favorited      then lines[#lines + 1] = "favorited: true"                         end
    if note.richMode       then lines[#lines + 1] = "richMode: true"                          end
    if note.locked ~= nil  then lines[#lines + 1] = "locked: " .. (note.locked and "true" or "false") end
    if note.icon           then lines[#lines + 1] = "icon: "           .. tostring(note.icon) end
    if note.titleColor     then
        lines[#lines + 1] = string.format("titleColor: %.4f,%.4f,%.4f",
            note.titleColor.r or 1, note.titleColor.g or 1, note.titleColor.b or 1)
    end
    if note.fontOverride   then lines[#lines + 1] = "fontOverride: "   .. note.fontOverride   end
    if note.textAlign      then lines[#lines + 1] = "textAlign: "      .. note.textAlign      end
    if note.fontOutline    then lines[#lines + 1] = "fontOutline: "    .. note.fontOutline    end
    if note.borderOverride then lines[#lines + 1] = "borderOverride: " .. note.borderOverride end
    if note.borderScale    then lines[#lines + 1] = "borderScale: "    .. tostring(note.borderScale)  end
    if note.borderOffset   then lines[#lines + 1] = "borderOffset: "   .. tostring(note.borderOffset) end
    if note.lineHeight     then lines[#lines + 1] = "lineHeight: "     .. note.lineHeight     end
    if note.created        then lines[#lines + 1] = "created: "        .. tostring(note.created)      end
    if note.updated        then lines[#lines + 1] = "updated: "        .. tostring(note.updated)      end
    if note.iconSource     then lines[#lines + 1] = "iconSource: "     .. note.iconSource             end
    if note.source         then lines[#lines + 1] = "source: "         .. note.source                 end
    if note.targetNpcID    then lines[#lines + 1] = "targetNpcID: "    .. tostring(note.targetNpcID)  end
    if note.targetPlayerKey then lines[#lines + 1] = "targetPlayerKey: " .. note.targetPlayerKey      end
    if note.targetIsPet    then lines[#lines + 1] = "targetIsPet: true"                               end
    if note.inspectRaceID  then lines[#lines + 1] = "inspectRaceID: "  .. tostring(note.inspectRaceID) end
    if note.inspectSexID ~= nil then lines[#lines + 1] = "inspectSexID: " .. tostring(note.inspectSexID) end
    if note.attachments and #note.attachments > 0 then
        local attParts = {}
        for _, att in ipairs(note.attachments) do
            if att.type and att.id then
                attParts[#attParts + 1] = att.type .. ":" .. att.id
            end
        end
        if #attParts > 0 then
            lines[#lines + 1] = "attachments: " .. table.concat(attParts, ",")
        end
    end

    lines[#lines + 1] = ""   -- blank line between frontmatter and body
    lines[#lines + 1] = MdEscapeBody(note.body or "")
    return table.concat(lines, "\n")
end

-- ── HTML export (three modes: note-only, plain, stylized) ─────────────────────

local HTML_ICON_CDN = "https://wow.zamimg.com/images/wow/icons/large/"
local HTML_IMG_DIR  = "img/"
local BNB_URL       = "https://www.curseforge.com/wow/addons/bignotebox"

-- Google Fonts import URL for each BNB built-in font ID.
-- LSM fonts have no web equivalent and fall back to Noto Serif.
local GOOGLE_FONT_MAP = {
    notoserif        = { import = "Noto+Serif:ital,wght@0,400;0,700;1,400",  family = "'Noto Serif', Georgia, serif" },
    ebgaramond       = { import = "EB+Garamond:ital,wght@0,400;0,700;1,400", family = "'EB Garamond', Georgia, serif" },
    notosans         = { import = "Noto+Sans:ital,wght@0,400;0,700;1,400",   family = "'Noto Sans', Arial, sans-serif" },
    jetbrains        = { import = "JetBrains+Mono:wght@400;700",             family = "'JetBrains Mono', monospace" },
    gloriahallelujah = { import = "Gloria+Hallelujah",                       family = "'Gloria Hallelujah', cursive" },
    opendyslexic     = { import = "Open+Sans:wght@400;700",                  family = "'Open Sans', sans-serif" }, -- OpenDyslexic not on GFonts; fallback
    fredoka          = { import = "Fredoka:wght@400;700",                    family = "'Fredoka', sans-serif" },
    playwrite        = { import = "Playwrite+IE",                            family = "'Playwrite IE', cursive" },
}
local DEFAULT_FONT = GOOGLE_FONT_MAP.notoserif

local function HtmlEsc(s)
    s = s:gsub("&", "&amp;")
    s = s:gsub("<", "&lt;")
    s = s:gsub(">", "&gt;")
    s = s:gsub("\"", "&quot;")
    return s
end

-- Resolve the Google Font for a note based on its fontOverride or global setting.
local function ResolveFont(note)
    local id = note.fontOverride
    if not id then
        local db = BigNoteBoxDB
        id = db and db.fontChoice or "notoserif"
    end
    return GOOGLE_FONT_MAP[id] or DEFAULT_FONT
end

-- Convert rich note markup body to browser HTML.
local function ConvertRichBody(body)
    if not body or body == "" then return "", false end
    local hasImages = body:find("{img:") ~= nil

    local lines = {}
    for line in (body .. "\n"):gmatch("([^\n]*)\n") do
        lines[#lines + 1] = line
    end

    local out = {}
    local inBlock = false

    local STRUCT_O = {
        ["{h1}"]   = "<h1>",       ["{h1:c}"] = '<h1 style="text-align:center;">',
        ["{h1:r}"] = '<h1 style="text-align:right;">',
        ["{h2}"]   = "<h2>",       ["{h2:c}"] = '<h2 style="text-align:center;">',
        ["{h2:r}"] = '<h2 style="text-align:right;">',
        ["{h3}"]   = "<h3>",       ["{h3:c}"] = '<h3 style="text-align:center;">',
        ["{h3:r}"] = '<h3 style="text-align:right;">',
        ["{p}"]    = "<p>",        ["{p:c}"]  = '<p style="text-align:center;">',
        ["{p:r}"]  = '<p style="text-align:right;">',
    }
    local STRUCT_C = {
        ["{/h1}"] = "</h1>", ["{/h2}"] = "</h2>",
        ["{/h3}"] = "</h3>", ["{/p}"]  = "</p>",
    }

    for _, rawLine in ipairs(lines) do
        local line = HtmlEsc(rawLine)

        -- {img:path:w:h[:align]}
        line = line:gsub("{img:([^:}]+):([^:}]+):([^:}]+):?([^:}]*)}", function(src, w, h, align)
            local a = align ~= "" and align or "center"
            if a == "c" then a = "center" elseif a == "l" then a = "left" elseif a == "r" then a = "right" end
            w = math.abs(tonumber(w) or 128); h = math.abs(tonumber(h) or 128)
            local filename = src:match("([^/\\]+)$") or src
            local st = a == "center" and ' style="display:block;margin:0.5em auto;"'
                    or a == "right"  and ' style="display:block;margin:0.5em 0 0.5em auto;"'
                    or ' style="display:block;margin:0.5em 0;"'
            return string.format('<img src="%s%s" width="%d" height="%d" alt="%s"%s/>',
                HTML_IMG_DIR, filename, w, h, filename, st)
        end)

        -- {icon:name:size[:align]}
        line = line:gsub("{icon:([^:}]+):(%d+):([lcr])}", function(name, size, align)
            size = tonumber(size) or 25; local lname = name:lower()
            local a = (align == "c") and "center" or (align == "r") and "right" or "left"
            local st = a == "center" and ' style="display:block;margin:0.5em auto;"'
                    or a == "right"  and ' style="display:block;margin:0.5em 0 0.5em auto;"' or ""
            return string.format('<img src="%s%s.jpg" width="%d" height="%d" alt="%s"%s/>',
                HTML_ICON_CDN, lname, size, size, name, st)
        end)
        line = line:gsub("{icon:([^:}]+):(%d+)}", function(name, size)
            size = tonumber(size) or 25; local lname = name:lower()
            return string.format('<img src="%s%s.jpg" width="%d" height="%d" alt="%s" style="vertical-align:middle;"/>',
                HTML_ICON_CDN, lname, size, size, name)
        end)

        -- {col:rrggbb}/{/col}
        line = line:gsub("{col:(%x%x%x%x%x%x)}", function(hex) return '<span style="color:#' .. hex .. ';">' end)
        line = line:gsub("{/col}", "</span>")

        -- {link*url*text}
        line = line:gsub("{link%*([^*}]+)%*([^}]*)}", function(url, lt) if lt == "" then lt = url end return '<a href="' .. url .. '">' .. lt .. '</a>' end)

        -- {br}
        line = line:gsub("{br}", "<br>")

        -- Structure tags
        for tag, html in pairs(STRUCT_O) do
            if line:find(tag, 1, true) then
                line = line:gsub(tag:gsub("[%(%)%.%%%+%-%*%?%[%]%^%$]", "%%%1"), html); inBlock = true
            end
        end
        for tag, html in pairs(STRUCT_C) do
            if line:find(tag, 1, true) then
                line = line:gsub(tag:gsub("[%(%)%.%%%+%-%*%?%[%]%^%$]", "%%%1"), html); inBlock = false
            end
        end

        -- Bare lines -> <p>
        if not inBlock and line ~= "" then
            local hasBlock = line:match("<h%d") or line:match("<p") or line:match("<img ")
            if not hasBlock then line = "<p>" .. line .. "</p>" end
        end

        out[#out + 1] = line
    end

    return table.concat(out, "\n"), hasImages
end

-- Convert plain note body to browser HTML preserving line structure.
-- Double newline = new <p>, single newline = <br>.
local function ConvertPlainBody(body)
    if not body or body == "" then return "" end
    -- Split on double newlines to get paragraphs
    local paragraphs = {}
    local current = {}
    for line in (body .. "\n"):gmatch("([^\n]*)\n") do
        if line == "" then
            if #current > 0 then
                paragraphs[#paragraphs + 1] = table.concat(current, "<br>\n")
                current = {}
            end
        else
            current[#current + 1] = HtmlEsc(line)
        end
    end
    if #current > 0 then
        paragraphs[#paragraphs + 1] = table.concat(current, "<br>\n")
    end
    local parts = {}
    for _, p in ipairs(paragraphs) do
        parts[#parts + 1] = "<p>" .. p .. "</p>"
    end
    return table.concat(parts, "\n")
end

-- Build the refbox HTML sidebar for a note's attachments.
-- WoW item quality hex colours (index matches Enum.ItemQuality)
local QUALITY_COLORS = {
    [0] = "#9d9d9d",  -- Poor (grey)
    [1] = "#ffffff",  -- Common (white)
    [2] = "#1eff00",  -- Uncommon (green)
    [3] = "#0070dd",  -- Rare (blue)
    [4] = "#a335ee",  -- Epic (purple)
    [5] = "#ff8000",  -- Legendary (orange)
    [6] = "#e6cc80",  -- Artifact (warm gold)
    [7] = "#00ccff",  -- Heirloom (cyan)
    [8] = "#00ccff",  -- WoW Token (cyan)
}

local function BuildRefboxHtml(note)
    local atts = note.attachments
    if not atts or #atts == 0 then return "" end
    local cards = {}
    for _, a in ipairs(atts) do
        local label, url, typeLabel, qualityHex
        if a.type == "item" then
            local name, _, quality = GetItemInfo(a.id)
            label     = name or ("Item " .. a.id)
            url       = "https://www.wowhead.com/item=" .. a.id
            typeLabel = "Item"
            qualityHex = QUALITY_COLORS[quality or 1] or QUALITY_COLORS[1]
        elseif a.type == "spell" then
            local si = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(a.id)
            label     = (si and si.name) or ("Spell " .. a.id)
            url       = "https://www.wowhead.com/spell=" .. a.id
            typeLabel = "Spell"
            qualityHex = "#4db8ff"
        elseif a.type == "quest" then
            local title = C_QuestLog and C_QuestLog.GetTitleForQuestID
                and C_QuestLog.GetTitleForQuestID(a.id)
            label     = (title and title ~= "") and title
                or (a.title and a.title ~= "") and a.title
                or ("Quest " .. a.id)
            url       = "https://www.wowhead.com/quest=" .. a.id
            typeLabel = "Quest"
            qualityHex = "#ffd100"
        else
            label     = (a.type or "?") .. " " .. (a.id or "?")
            url       = nil
            typeLabel = a.type or "Unknown"
            qualityHex = QUALITY_COLORS[1]
        end

        -- Build the icon <img> via Wowhead tooltip integration:
        -- Wowhead's tooltip.js will enhance <a> tags with data-wowhead attributes,
        -- but for a static icon we use the Wowhead icon endpoint.
        -- Format: https://wow.zamimg.com/images/wow/icons/medium/ICONNAME.jpg
        -- Since we can't resolve FileID->iconName in-game, we use a placeholder
        -- icon div that Wowhead's script will populate via the link.
        local iconHtml = string.format(
            '<img class="rb-icon" src="%swow_store.jpg" width="36" height="36" alt="icon"/>',
            HTML_ICON_CDN)
        local nameHtml
        if url then
            nameHtml = string.format('<a href="%s" style="color:%s;">%s</a>',
                url, qualityHex, HtmlEsc(label))
        else
            nameHtml = string.format('<span style="color:%s;">%s</span>',
                qualityHex, HtmlEsc(label))
        end

        cards[#cards + 1] = '<div class="rb-card">'
            .. iconHtml
            .. '<div class="rb-info">'
            .. '<span class="rb-type">' .. HtmlEsc(typeLabel) .. '</span>'
            .. '<span class="rb-name">' .. nameHtml .. '</span>'
            .. '</div></div>'
    end
    if #cards == 0 then return "" end
    return '<div class="refbox"><h3>Reference Box</h3>'
        .. table.concat(cards, "\n") .. "</div>"
end

-- Build metadata HTML block.
local function BuildMetaHtml(note)
    local parts = {}
    if note.tags and #note.tags > 0 then
        parts[#parts + 1] = "<strong>Tags:</strong> " .. HtmlEsc(table.concat(note.tags, ", "))
    end
    if note.context and note.context ~= "" then
        parts[#parts + 1] = "<strong>Context:</strong> " .. HtmlEsc(note.context)
    end
    if note.created then
        parts[#parts + 1] = "<strong>Created:</strong> " .. date("%Y-%m-%d %H:%M", note.created)
    end
    if note.updated then
        parts[#parts + 1] = "<strong>Updated:</strong> " .. date("%Y-%m-%d %H:%M", note.updated)
    end
    if #parts == 0 then return "" end
    return '<div class="meta">' .. table.concat(parts, " &middot; ") .. "</div>"
end

-- Build <head> meta tags for Plain and Stylized modes.
local function BuildHeadMeta(note, isStylized)
    local title = (note.title and note.title ~= "") and HtmlEsc(note.title) or "Untitled"
    local author = UnitName("player") or "Unknown"
    local desc = "Note exported from BigNoteBox, a World of Warcraft addon"
    local m = {}
    m[#m + 1] = '<meta name="description" content="' .. desc .. '">'
    m[#m + 1] = '<meta name="author" content="' .. HtmlEsc(author) .. '">'
    m[#m + 1] = '<meta name="generator" content="BigNoteBox (World of Warcraft addon)">'
    m[#m + 1] = '<link rel="canonical" href="' .. BNB_URL .. '">'
    -- Open Graph
    m[#m + 1] = '<meta property="og:title" content="' .. title .. '">'
    m[#m + 1] = '<meta property="og:description" content="' .. desc .. '">'
    m[#m + 1] = '<meta property="og:type" content="article">'
    m[#m + 1] = '<meta property="og:site_name" content="BigNoteBox">'
    -- Copyright
    if isStylized then
        m[#m + 1] = '<meta name="copyright" content="Note by ' .. HtmlEsc(author) .. '. Template design by BigNoteBox.">'
    else
        m[#m + 1] = '<meta name="copyright" content="' .. HtmlEsc(author) .. '">'
    end
    return table.concat(m, "\n")
end

-- Get the title HTML with optional colour styling.
local function BuildTitleHtml(note)
    local title = (note.title and note.title ~= "") and HtmlEsc(note.title) or "Untitled"
    if note.titleColor then
        local r = math.floor((note.titleColor.r or 1) * 255 + 0.5)
        local g = math.floor((note.titleColor.g or 1) * 255 + 0.5)
        local b = math.floor((note.titleColor.b or 1) * 255 + 0.5)
        return string.format('<h1 style="color:rgb(%d,%d,%d);">%s</h1>', r, g, b, title)
    end
    return "<h1>" .. title .. "</h1>"
end

-- Convert the note body (dispatches to rich or plain converter).
local function ConvertBody(note)
    if note.richMode then
        return ConvertRichBody(note.body)
    else
        return ConvertPlainBody(note.body), (note.body or ""):find("{img:") ~= nil
    end
end

--------------------------------------------------------------------------------
-- MODE 1: NOTE ONLY
-- Fragment: title + body + refbox + meta, wrapped in START/END comments.
--------------------------------------------------------------------------------
local function HtmlExportNoteOnly(note)
    local bodyHtml, hasImages = ConvertBody(note)
    local refbox  = BuildRefboxHtml(note)
    local meta    = BuildMetaHtml(note)
    local parts   = {}
    parts[#parts + 1] = "<!-- START Exported from BigNoteBox - " .. BNB_URL .. " -->"
    parts[#parts + 1] = BuildTitleHtml(note)
    parts[#parts + 1] = bodyHtml
    if refbox ~= "" then parts[#parts + 1] = refbox end
    if meta   ~= "" then parts[#parts + 1] = meta end
    parts[#parts + 1] = "<!-- END Exported from BigNoteBox - " .. BNB_URL .. " -->"
    return table.concat(parts, "\n"), hasImages
end

--------------------------------------------------------------------------------
-- MODE 2: PLAIN HTML
-- Full document with skin-aware theming, refbox sidebar, metadata footer.
--------------------------------------------------------------------------------
local function HtmlExportPlain(note)
    local bodyHtml, hasImages = ConvertBody(note)
    local font    = ResolveFont(note)
    local title   = (note.title and note.title ~= "") and HtmlEsc(note.title) or "Untitled"
    local headMeta = BuildHeadMeta(note, false)
    local refbox  = BuildRefboxHtml(note)
    local meta    = BuildMetaHtml(note)

    -- Skin-aware colours
    local bgR, bgG, bgB       = 0.10, 0.10, 0.12
    local borderR, borderG, borderB = 0.28, 0.28, 0.28
    local textR, textG, textB = 0.88, 0.88, 0.88
    local linkR, linkG, linkB = 0.40, 0.85, 0.40

    if BigNoteBoxDB and BigNoteBoxDB.skinMode and BNB.GetSkinPreset then
        local p   = BNB.GetSkinPreset()
        local brt = BNB.GetSkinBrightness and BNB.GetSkinBrightness() or 1.0
        bgR = math.min(1, p.r * brt)
        bgG = math.min(1, p.g * brt)
        bgB = math.min(1, p.b * brt)
        borderR = math.min(1, p.br * brt)
        borderG = math.min(1, p.bg_ * brt)
        borderB = math.min(1, p.bb * brt)
        -- Lighten border colour for links
        linkR = math.min(1, borderR * 2.5)
        linkG = math.min(1, borderG * 2.5)
        linkB = math.min(1, borderB * 2.5)
    end

    local function css255(r, g, b) return math.floor(r*255+0.5), math.floor(g*255+0.5), math.floor(b*255+0.5) end
    local bR, bG, bB = css255(bgR, bgG, bgB)
    local brR, brG, brB = css255(borderR, borderG, borderB)
    local lR, lG, lB = css255(linkR, linkG, linkB)
    local tR, tG, tB = css255(textR, textG, textB)

    -- Slightly lighter bg for the refbox sidebar
    local rbR = math.min(255, bR + 12)
    local rbG = math.min(255, bG + 12)
    local rbB = math.min(255, bB + 12)

    local css = string.format(
        "@import url('https://fonts.googleapis.com/css2?family=%s&display=swap');\n", font.import)
        .. "* { box-sizing: border-box; }\n"
        .. string.format("body { font-family: %s; max-width: 900px; margin: 2em auto; padding: 0 1em; color: rgb(%d,%d,%d); background: rgb(%d,%d,%d); line-height: 1.6; font-size: 16px; }\n",
            font.family, tR, tG, tB, bR, bG, bB)
        .. string.format(".page { display: flex; gap: 1.5em; border: 1px solid rgb(%d,%d,%d); border-radius: 4px; padding: 2em; }\n", brR, brG, brB)
        .. ".page-body { flex: 1; min-width: 0; }\n"
        .. string.format(".refbox { width: 240px; flex-shrink: 0; background: rgb(%d,%d,%d); border: 1px solid rgb(%d,%d,%d); border-radius: 4px; padding: 1em; font-size: 0.9em; align-self: flex-start; }\n",
            rbR, rbG, rbB, brR, brG, brB)
        .. ".refbox h3 { margin: 0 0 0.8em; font-size: 1em; }\n"
        .. string.format(".rb-card { display: flex; gap: 0.6em; align-items: center; border: 1px solid rgb(%d,%d,%d); border-radius: 3px; padding: 0.5em; margin-bottom: 0.5em; background: rgba(%d,%d,%d,0.4); }\n",
            brR, brG, brB, rbR, rbG, rbB)
        .. ".rb-icon { width: 36px; height: 36px; flex-shrink: 0; background: #222; border-radius: 3px; }\n"
        .. ".rb-info { display: flex; flex-direction: column; min-width: 0; }\n"
        .. string.format(".rb-type { font-size: 0.75em; color: rgb(%d,%d,%d); text-transform: uppercase; letter-spacing: 0.05em; }\n",
            math.min(255, tR - 40), math.min(255, tG - 40), math.min(255, tB - 40))
        .. ".rb-name { font-size: 0.9em; font-weight: bold; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }\n"
        .. ".rb-name a { text-decoration: none; }\n"
        .. ".rb-name a:hover { text-decoration: underline; }\n"
        .. "h1 { font-size: 2em; margin: 0 0 0.5em; }\n"
        .. "h2 { font-size: 1.6em; margin: 0.8em 0 0.4em; }\n"
        .. "h3 { font-size: 1.3em; margin: 0.6em 0 0.3em; }\n"
        .. "p { margin: 0.4em 0; }\n"
        .. string.format("a { color: rgb(%d,%d,%d); }\n", lR, lG, lB)
        .. "img { max-width: 100%; height: auto; }\n"
        .. string.format(".meta { font-size: 0.85em; color: rgb(%d,%d,%d); border-top: 1px solid rgb(%d,%d,%d); padding-top: 0.5em; margin-top: 2em; }\n",
            math.min(255, tR - 60), math.min(255, tG - 60), math.min(255, tB - 60), brR, brG, brB)
        .. string.format(".footer { font-size: 0.8em; color: rgb(%d,%d,%d); margin-top: 1em; }\n",
            math.min(255, tR - 100), math.min(255, tG - 100), math.min(255, tB - 100))
        .. ".footer a { font-size: inherit; }\n"
        .. string.format(".font-controls { position: fixed; bottom: 1em; right: 1em; display: flex; gap: 0.3em; background: rgb(%d,%d,%d); border: 1px solid rgb(%d,%d,%d); border-radius: 4px; padding: 0.3em; }\n",
            bR, bG, bB, brR, brG, brB)
        .. string.format(".font-controls button { width: 2em; height: 2em; border: 1px solid rgb(%d,%d,%d); border-radius: 3px; background: rgb(%d,%d,%d); color: rgb(%d,%d,%d); font-size: 1em; cursor: pointer; font-weight: bold; }\n",
            brR, brG, brB, rbR, rbG, rbB, tR, tG, tB)
        .. ".font-controls button:hover { opacity: 0.8; }\n"

    local fontSizeJS = '<script>'
        .. 'var fs=16;'
        .. 'function bnbFS(d){fs=Math.max(10,Math.min(28,fs+d));document.body.style.fontSize=fs+"px";}'
        .. '</script>\n'

    local html = "<!DOCTYPE html>\n<html lang=\"en\">\n<head>\n"
        .. '<meta charset="utf-8">\n'
        .. '<meta name="viewport" content="width=device-width, initial-scale=1">\n'
        .. "<title>" .. title .. "</title>\n"
        .. headMeta .. "\n"
        .. "<style>\n" .. css .. "</style>\n"
        .. "</head>\n<body>\n"
        .. '<div class="font-controls"><button onclick="bnbFS(-2)" title="Decrease font size">-</button><button onclick="bnbFS(2)" title="Increase font size">+</button></div>\n'
        .. '<div class="page">\n'
        .. '<div class="page-body">\n'
        .. BuildTitleHtml(note) .. "\n"
        .. bodyHtml .. "\n"
        .. (meta ~= "" and (meta .. "\n") or "")
        .. '<div class="footer">Exported from <a href="' .. BNB_URL .. '">BigNoteBox</a></div>\n'
        .. "</div>\n"
        .. (refbox ~= "" and (refbox .. "\n") or "")
        .. "</div>\n"
        .. fontSizeJS
        .. '<script src="https://wow.zamimg.com/js/tooltips.js"></script>\n'
        .. "</body>\n</html>"

    return html, hasImages
end

--------------------------------------------------------------------------------
-- MODE 3: STYLIZED
-- Uses the book/tome template from HtmlTemplate.lua with content injected.
--------------------------------------------------------------------------------
local function HtmlExportStylized(note)
    local tpl = BNB.HtmlTemplate and BNB.HtmlTemplate.Get and BNB.HtmlTemplate.Get()
    if not tpl then return "<!-- Error: HtmlTemplate not loaded -->", false end

    local bodyHtml, hasImages = ConvertBody(note)
    local title   = (note.title and note.title ~= "") and HtmlEsc(note.title) or "Untitled"
    local headMeta = BuildHeadMeta(note, true)
    local refbox  = BuildRefboxHtml(note)
    local meta    = BuildMetaHtml(note)

    -- Build the title HTML (with optional colour)
    local titleHtml = title
    if note.titleColor then
        local r = math.floor((note.titleColor.r or 1) * 255 + 0.5)
        local g = math.floor((note.titleColor.g or 1) * 255 + 0.5)
        local b = math.floor((note.titleColor.b or 1) * 255 + 0.5)
        titleHtml = string.format('<span style="color:rgb(%d,%d,%d);">%s</span>', r, g, b, title)
    end

    -- Extra CSS for refbox cards and font controls (injected via %%META%%)
    local extraCSS = "<style>\n"
        .. ".rb-card { display: flex; gap: 0.6em; align-items: center; border: 1px solid rgba(180,160,120,0.3); border-radius: 3px; padding: 0.5em; margin-bottom: 0.5em; background: rgba(0,0,0,0.2); }\n"
        .. ".rb-icon { width: 36px; height: 36px; flex-shrink: 0; background: #222; border-radius: 3px; }\n"
        .. ".rb-info { display: flex; flex-direction: column; min-width: 0; }\n"
        .. ".rb-type { font-size: 0.75em; color: rgba(200,180,140,0.7); text-transform: uppercase; letter-spacing: 0.05em; }\n"
        .. ".rb-name { font-size: 0.9em; font-weight: bold; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }\n"
        .. ".rb-name a { text-decoration: none; }\n"
        .. ".rb-name a:hover { text-decoration: underline; }\n"
        .. ".refbox { margin-top: 1.5em; padding: 0.8em; border: 1px solid rgba(180,160,120,0.3); border-radius: 4px; background: rgba(0,0,0,0.15); }\n"
        .. ".refbox h3 { margin: 0 0 0.8em; font-size: 1em; }\n"
        .. ".meta { font-size: 0.85em; color: rgba(200,180,140,0.6); border-top: 1px solid rgba(180,160,120,0.2); padding-top: 0.5em; margin-top: 1.5em; }\n"
        .. "</style>"

    headMeta = headMeta .. "\n" .. extraCSS

    -- Build the body with refbox, meta, font controls, and Wowhead tooltips
    local fullBody = bodyHtml
    if refbox ~= "" then fullBody = fullBody .. "\n" .. refbox end
    if meta   ~= "" then fullBody = fullBody .. "\n" .. meta end

    -- Font size controls are intentionally omitted from stylized export —
    -- the tome/book template has its own fixed layout. Controls are available
    -- in the Plain HTML export mode only.
    local beforeBody = '\n<script src="https://wow.zamimg.com/js/tooltips.js"></script>\n'

    -- Replace placeholders in the template
    -- gsub treats % as special in replacements, so escape them
    local function safeReplace(s, pattern, repl)
        return s:gsub(pattern, function() return repl end)
    end
    local html = tpl
    html = safeReplace(html, "%%%%TITLE%%%%", title)
    html = safeReplace(html, "%%%%META%%%%", headMeta)
    html = safeReplace(html, "%%%%NOTE_TITLE%%%%", titleHtml)
    html = safeReplace(html, "%%%%NOTE_BODY%%%%", fullBody)
    -- Inject controls and scripts before </body>
    html = safeReplace(html, "</body>", beforeBody .. "</body>")

    return html, hasImages
end

-- Master dispatcher. mode: "noteonly", "plain", "stylized"
local _htmlExportMode = "plain"

local function HtmlEncodeNote(note, mode)
    mode = mode or _htmlExportMode or "plain"
    if mode == "noteonly" then
        return HtmlExportNoteOnly(note)
    elseif mode == "stylized" then
        return HtmlExportStylized(note)
    else
        return HtmlExportPlain(note)
    end
end

-- ── Serialize all notes ───────────────────────────────────────────────────────

local function SerializeNotes(fmt)
    local ndb   = BigNoteBoxNotesDB
    local order = ndb and ndb.noteOrder or {}
    local notes = ndb and ndb.notes     or {}
    local count = 0
    for _ in pairs(notes) do count = count + 1 end

    if fmt == FMT_JSON then
        local noteParts = {}
        for _, id in ipairs(order) do
            local note = notes[id]
            if note then noteParts[#noteParts + 1] = JsonEncodeNote(note) end
        end
        -- Also include any notes not in noteOrder (shouldn't happen, but safe)
        local seen = {}
        for _, id in ipairs(order) do seen[id] = true end
        for id, note in pairs(notes) do
            if not seen[id] then noteParts[#noteParts + 1] = JsonEncodeNote(note) end
        end

        local header = string.format(
            "{\"export_version\":%d,\"addon_version\":%s,\"note_count\":%d,\"notes\":[\n",
            EXPORT_VERSION,
            JsonEscapeStr(BNB.ADDON_VERSION or "1.0.0"),
            #noteParts)
        return header .. table.concat(noteParts, ",\n") .. "\n]}", #noteParts

    else  -- Markdown
        local chunks = {}
        local hdr = string.format(
            "# BigNoteBox Export v%d | %s | %d note(s)\n",
            EXPORT_VERSION,
            date("%Y-%m-%d %H:%M"),
            count)
        chunks[#chunks + 1] = hdr

        for _, id in ipairs(order) do
            local note = notes[id]
            if note then
                chunks[#chunks + 1] = "===\n" .. MdEncodeNote(note)
            end
        end
        local seen = {}
        for _, id in ipairs(order) do seen[id] = true end
        for id, note in pairs(notes) do
            if not seen[id] then
                chunks[#chunks + 1] = "===\n" .. MdEncodeNote(note)
            end
        end

        return table.concat(chunks, "\n"), count
    end
end

-- ── Deserialize — JSON ────────────────────────────────────────────────────────
-- Returns array of raw note tables, or nil on failure.

local function ParseJsonNotes(text)
    -- Quick sanity: must look like our envelope
    if not text:find("\"export_version\"") then return nil end
    if not text:find("\"notes\"") then return nil end

    -- Check version
    local expVer = tonumber(text:match("\"export_version\"%s*:%s*(%d+)"))
    if not expVer then return nil end
    if expVer > EXPORT_VERSION then
        BNB:Print(string.format(L["BACKUP_IMPORT_VERSION_WARN"], expVer, EXPORT_VERSION))
    end

    local parsed = {}

    -- Extract each note object {...} from the notes array.
    -- We use a simple brace-matching scan rather than a full recursive parser,
    -- which is safe because our values never contain unescaped { or }.
    local noteArray = text:match("\"notes\"%s*:%s*%[(.-)%]%s*}%s*$")
    if not noteArray then return nil end

    -- Split on top-level commas between objects
    local depth, start = 0, 1
    local objects = {}
    for i = 1, #noteArray do
        local c = noteArray:sub(i, i)
        if     c == "{" then depth = depth + 1; if depth == 1 then start = i end
        elseif c == "}" then
            depth = depth - 1
            if depth == 0 then objects[#objects + 1] = noteArray:sub(start, i) end
        end
    end

    for _, obj in ipairs(objects) do
        local note = {}

        -- Extract string fields
        for key, val in obj:gmatch("\"([^\"]+)\"%s*:%s*\"(.-[^\\])\"") do
            note[key] = JsonDecodeStr(val)
        end
        -- Also catch empty strings
        for key in obj:gmatch("\"([^\"]+)\"%s*:%s*\"\"") do
            note[key] = ""
        end
        -- Extract number fields
        for key, val in obj:gmatch("\"([^\"]+)\"%s*:%s*(%-?%d+%.?%d*)") do
            if not note[key] then  -- don't overwrite string already captured
                note[key] = tonumber(val)
            end
        end
        -- Extract boolean fields
        for key, val in obj:gmatch("\"([^\"]+)\"%s*:%s*(true|false)") do
            note[key] = (val == "true")
        end
        -- Extract titleColor sub-object
        local cr, cg, cb = obj:match("\"titleColor\"%s*:%s*{[^}]*\"r\"%s*:%s*(%-?[%d.]+)[^}]*\"g\"%s*:%s*(%-?[%d.]+)[^}]*\"b\"%s*:%s*(%-?[%d.]+)")
        if cr then
            note.titleColor = { r = tonumber(cr), g = tonumber(cg), b = tonumber(cb) }
        end
        -- Extract waypoint sub-object {mapID, x, y, label}
        local wpRaw = obj:match("\"waypoint\"%s*:%s*({[^}]*})")
        if wpRaw then
            local mid  = tonumber(wpRaw:match("\"mapID\"%s*:%s*(%d+)"))
            local wx   = tonumber(wpRaw:match("\"x\"%s*:%s*(%-?[%d.]+)"))
            local wy   = tonumber(wpRaw:match("\"y\"%s*:%s*(%-?[%d.]+)"))
            local wlbl = wpRaw:match("\"label\"%s*:%s*\"(.-[^\\])\"") or ""
            if mid then
                note.waypoint = { mapID = mid, x = wx or 0, y = wy or 0, label = JsonDecodeStr(wlbl) }
            end
        end
        -- Fix tags: re-parse as array from raw object text
        local tagsRaw = obj:match("\"tags\"%s*:%s*(%b[])")
        if tagsRaw then
            note.tags = {}
            for tv in tagsRaw:gmatch("\"(.-[^\\])\"") do
                note.tags[#note.tags + 1] = JsonDecodeStr(tv)
            end
        else
            note.tags = {}
        end
        -- Null fields become nil (already nil in Lua — just ensure booleans aren't set)
        for key in obj:gmatch("\"([^\"]+)\"%s*:%s*null") do
            note[key] = nil
        end
        -- Extract attachments array: [{type,id}, ...]
        -- Must be parsed explicitly; the generic string/number regexes would only
        -- extract the last "type" and "id" values as spurious top-level fields.
        local attRaw = obj:match("\"attachments\"%s*:%s*(%b[])")
        if attRaw then
            note.attachments = {}
            -- Each sub-object is {...}; extract type+id from each one.
            for attObj in attRaw:gmatch("{([^}]+)}") do
                local atype = attObj:match("\"type\"%s*:%s*\"([^\"]+)\"")
                local aid   = tonumber(attObj:match("\"id\"%s*:%s*(%d+)"))
                if atype and aid then
                    note.attachments[#note.attachments + 1] = { type = atype, id = aid }
                end
            end
            if #note.attachments == 0 then note.attachments = nil end
        end
        -- Extract inspectGearItems array: [{id,slot,slotIdx}, ...]
        local gearRaw = obj:match("\"inspectGearItems\"%s*:%s*(%b[])")
        if gearRaw then
            note.inspectGearItems = {}
            for gObj in gearRaw:gmatch("{([^}]+)}") do
                local gid  = tonumber(gObj:match("\"id\"%s*:%s*(%d+)"))
                local gsl  = gObj:match("\"slot\"%s*:%s*\"([^\"]*)\"")
                local gsli = tonumber(gObj:match("\"slotIdx\"%s*:%s*(%d+)"))
                if gid then
                    note.inspectGearItems[#note.inspectGearItems + 1] =
                        { id = gid, slot = gsl or "", slotIdx = gsli or 0 }
                end
            end
            if #note.inspectGearItems == 0 then note.inspectGearItems = nil end
        end
        -- Extract inspectTransmogItems array: [{id,slot,slotIdx,appearanceID}, ...]
        local tmogRaw = obj:match("\"inspectTransmogItems\"%s*:%s*(%b[])")
        if tmogRaw then
            note.inspectTransmogItems = {}
            for tObj in tmogRaw:gmatch("{([^}]+)}") do
                local tid  = tonumber(tObj:match("\"id\"%s*:%s*(%d+)"))
                local tsl  = tObj:match("\"slot\"%s*:%s*\"([^\"]*)\"")
                local tsli = tonumber(tObj:match("\"slotIdx\"%s*:%s*(%d+)"))
                local tapp = tonumber(tObj:match("\"appearanceID\"%s*:%s*(%d+)"))
                if tid then
                    note.inspectTransmogItems[#note.inspectTransmogItems + 1] =
                        { id = tid, slot = tsl or "", slotIdx = tsli or 0, appearanceID = tapp or 0 }
                end
            end
            if #note.inspectTransmogItems == 0 then note.inspectTransmogItems = nil end
        end
        -- Extract inspectTransmogAppearances object: {"slotIdx":appearanceID, ...}
        local tmogAppRaw = obj:match("\"inspectTransmogAppearances\"%s*:%s*({[^}]*})")
        if tmogAppRaw and tmogAppRaw ~= "{}" then
            note.inspectTransmogAppearances = {}
            for k, v in tmogAppRaw:gmatch("\"(%d+)\"%s*:%s*(%d+)") do
                note.inspectTransmogAppearances[tonumber(k)] = tonumber(v)
            end
            if not next(note.inspectTransmogAppearances) then
                note.inspectTransmogAppearances = nil
            end
        end
        -- Extract alarm sub-object
        local alarmRaw = obj:match("\"alarm\"%s*:%s*({.-})")
        if alarmRaw then
            local a = {}
            -- Scalar fields via generic pass
            for k, v in alarmRaw:gmatch("\"([^\"]+)\"%s*:%s*\"(.-[^\\])\"") do a[k] = JsonDecodeStr(v) end
            for k in alarmRaw:gmatch("\"([^\"]+)\"%s*:%s*\"\"") do a[k] = "" end
            for k, v in alarmRaw:gmatch("\"([^\"]+)\"%s*:%s*(%-?%d+%.?%d*)") do
                if not a[k] then a[k] = tonumber(v) end
            end
            for k, v in alarmRaw:gmatch("\"([^\"]+)\"%s*:%s*(true|false)") do
                if a[k] == nil then a[k] = (v == "true") end
            end
            -- glowColor array [r,g,b,a]
            local gcRaw = alarmRaw:match("\"glowColor\"%s*:%s*(%b[])")
            if gcRaw then
                local vals = {}
                for n in gcRaw:gmatch("(%-?[%d.]+)") do vals[#vals+1] = tonumber(n) end
                if #vals >= 3 then
                    a.glowColor = { vals[1], vals[2], vals[3], vals[4] or 1 }
                end
            end
            -- recurDays boolean array
            local rdRaw = alarmRaw:match("\"recurDays\"%s*:%s*(%b[])")
            if rdRaw then
                a.recurDays = {}
                local i = 1
                for v in rdRaw:gmatch("(true|false)") do
                    a.recurDays[i] = (v == "true"); i = i + 1
                end
            end
            -- null cleanup for alarm
            for k in alarmRaw:gmatch("\"([^\"]+)\"%s*:%s*null") do a[k] = nil end
            if next(a) then note.alarm = a end
        end
        -- Clean up spurious top-level keys that leaked from sub-object parsing
        note.type = nil; note.id = nil
        note.r = nil; note.g = nil; note.b = nil
        note.mapID = nil; note.x = nil; note.y = nil; note.label = nil
        note.slot = nil; note.slotIdx = nil; note.appearanceID = nil

        if note.title then parsed[#parsed + 1] = note end
    end

    return #parsed > 0 and parsed or nil
end

-- ── Deserialize — Markdown ────────────────────────────────────────────────────

local function ParseMarkdownNotes(text)
    -- Must start with our header line
    if not text:find("^# BigNoteBox Export v") then return nil end

    local expVer = tonumber(text:match("^# BigNoteBox Export v(%d+)"))
    if not expVer then return nil end
    if expVer > EXPORT_VERSION then
        BNB:Print(string.format(L["BACKUP_IMPORT_VERSION_WARN"], expVer, EXPORT_VERSION))
    end

    local parsed = {}

    -- Split into records on lines that are exactly "==="
    local records = {}
    local cur = {}
    for line in (text .. "\n"):gmatch("([^\n]*)\n") do
        if line == "===" then
            if #cur > 0 then records[#records + 1] = table.concat(cur, "\n") end
            cur = {}
        else
            cur[#cur + 1] = line
        end
    end
    if #cur > 0 then records[#records + 1] = table.concat(cur, "\n") end

    for _, rec in ipairs(records) do
        if rec ~= "" and not rec:find("^# BigNoteBox Export") then
            local note  = { tags = {} }
            local lines = {}
            for l in (rec .. "\n"):gmatch("([^\n]*)\n") do lines[#lines + 1] = l end

            -- Separate frontmatter (key: value lines) from body (after blank line)
            local bodyStart = #lines + 1
            for i, l in ipairs(lines) do
                if l == "" then bodyStart = i + 1; break end
            end

            for i = 1, bodyStart - 2 do
                local key, val = lines[i]:match("^([%w]+):%s*(.-)%s*$")
                if key and val then
                    if     key == "title"          then note.title          = val
                    elseif key == "context"        then note.context        = val
                    elseif key == "contextDisplay" then note.contextDisplay = val
                    elseif key == "contextLeave"   then note.contextLeave   = val
                    elseif key == "fontOverride"   then note.fontOverride   = val
                    elseif key == "textAlign"      then note.textAlign      = val
                    elseif key == "fontOutline"    then note.fontOutline    = val
                    elseif key == "borderOverride" then note.borderOverride = val
                    elseif key == "lineHeight"     then note.lineHeight     = val
                    elseif key == "icon"           then note.icon           = tonumber(val) or val
                    elseif key == "borderScale"      then note.borderScale      = tonumber(val)
                    elseif key == "borderOffset"     then note.borderOffset     = tonumber(val)
                    elseif key == "borderBrightness" then note.borderBrightness = tonumber(val)
                    elseif key == "scope"            then note.scope            = val
                    elseif key == "wpClearOnLeave"   then note.wpClearOnLeave   = (val == "true") or nil
                    elseif key == "waypoint" and val ~= "" and val ~= "null" then
                        -- Format: mapID:x:y:label
                        local mid, wx, wy, wlbl = val:match("^(%d+):(%-?[%d.]+):(%-?[%d.]+):(.*)$")
                        if mid then
                            note.waypoint = {
                                mapID = tonumber(mid),
                                x     = tonumber(wx),
                                y     = tonumber(wy),
                                label = wlbl or "",
                            }
                        end
                    elseif key == "iconSource"      then note.iconSource      = val
                    elseif key == "source"          then note.source          = val
                    elseif key == "targetNpcID"     then note.targetNpcID     = tonumber(val)
                    elseif key == "targetPlayerKey" then note.targetPlayerKey = val
                    elseif key == "targetIsPet"     then note.targetIsPet     = (val == "true") or nil
                    elseif key == "inspectRaceID"   then note.inspectRaceID   = tonumber(val)
                    elseif key == "inspectSexID"    then note.inspectSexID    = tonumber(val)
                    elseif key == "created"        then note.created        = tonumber(val)
                    elseif key == "updated"        then note.updated        = tonumber(val)
                    elseif key == "pinned"         then note.pinned         = (val == "true")
                    elseif key == "favorited"      then note.favorited      = (val == "true") or nil
                    elseif key == "richMode"       then note.richMode       = (val == "true") or nil
                    elseif key == "locked"         then note.locked         = (val == "true")
                    elseif key == "titleColor"     then
                        local r, g, b = val:match("(%-?[%d.]+),(%-?[%d.]+),(%-?[%d.]+)")
                        if r then note.titleColor = {r=tonumber(r),g=tonumber(g),b=tonumber(b)} end
                    elseif key == "tags" and val ~= "" then
                        for tag in val:gmatch("[^,]+") do
                            local t = tag:match("^%s*(.-)%s*$")
                            if t ~= "" then note.tags[#note.tags + 1] = t end
                        end
                    elseif key == "attachments" and val ~= "" and val ~= "null" then
                        -- Format: type:id,type:id,...
                        note.attachments = {}
                        for entry in val:gmatch("[^,]+") do
                            local atype, aid = entry:match("^([^:]+):(%d+)$")
                            if atype and aid then
                                note.attachments[#note.attachments + 1] = {
                                    type = atype, id = tonumber(aid)
                                }
                            end
                        end
                        if #note.attachments == 0 then note.attachments = nil end
                    end
                end
            end

            -- Body: everything from bodyStart to end, unescape separator
            local bodyLines = {}
            for i = bodyStart, #lines do bodyLines[#bodyLines + 1] = lines[i] end
            -- Trim trailing blank lines
            while #bodyLines > 0 and bodyLines[#bodyLines] == "" do
                table.remove(bodyLines)
            end
            note.body = MdUnescapeBody(table.concat(bodyLines, "\n"))

            if note.title then parsed[#parsed + 1] = note end
        end
    end

    return #parsed > 0 and parsed or nil
end

-- ── Import notes into NoteManager ────────────────────────────────────────────

local function ImportNotes(noteList, remapScope)
    -- remapScope: if true, any note with scope "char:X" is rewritten to current char.
    if not noteList or #noteList == 0 then return 0 end
    local now = time()
    local count = 0
    for _, src in ipairs(noteList) do
        if src.title and src.title ~= "" then
            local id = BNB.CreateNote(src.title, src.body or "")
            -- Resolve scope: remap char-scoped notes to current char if requested
            local resolvedScope = src.scope
            if remapScope and resolvedScope and resolvedScope:find("^char:") then
                resolvedScope = "char:" .. (BNB.currentChar or resolvedScope:sub(6))
            end
            local fields = {
                tags             = src.tags or {},
                context          = src.context,
                contextDisplay   = src.contextDisplay,
                contextLeave     = src.contextLeave,
                pinned           = src.pinned or false,
                locked           = src.locked,
                icon             = src.icon,
                titleColor       = src.titleColor,
                fontOverride     = src.fontOverride,
                textAlign        = src.textAlign,
                fontOutline      = src.fontOutline,
                borderOverride   = src.borderOverride,
                borderScale      = src.borderScale,
                borderOffset     = src.borderOffset,
                borderBrightness = src.borderBrightness,
                lineHeight       = src.lineHeight,
                scope            = resolvedScope,
                waypoint         = src.waypoint,
                wpClearOnLeave   = src.wpClearOnLeave,
                iconSource       = src.iconSource,
                source           = src.source,
                targetNpcID      = src.targetNpcID,
                targetPlayerKey  = src.targetPlayerKey,
                targetIsPet      = src.targetIsPet,
                inspectRaceID    = src.inspectRaceID,
                inspectSexID     = src.inspectSexID,
                inspectGearItems          = src.inspectGearItems,
                inspectTransmogItems      = src.inspectTransmogItems,
                inspectTransmogAppearances = src.inspectTransmogAppearances,
                alarm            = src.alarm,
                created          = src.created or now,
                updated          = src.updated or now,
            }
            -- favorited: only set if truthy (nil-safe)
            if src.favorited then fields.favorited = true end
            -- attachments: only set if non-empty
            if src.attachments and #src.attachments > 0 then
                fields.attachments = src.attachments
            end
            BNB.UpdateNote(id, fields)
            count = count + 1
        end
    end
    if BNB.RefreshNoteList then BNB.RefreshNoteList() end
    return count
end

-- Public wrapper so the BNB_IMPORT_SCOPE_REMAP popup callback (defined in
-- SlashCommands.lua, which loads before ConfigWindow.lua) can call ImportNotes.
-- Set after the local is defined so the closure captures the correct function.
BNB._DoImport       = ImportNotes
BNB._ParseJsonNotes = ParseJsonNotes

-- ── Build the tab ─────────────────────────────────────────────────────────────

-- ── Build the tab ─────────────────────────────────────────────────────────────

local function BuildBackupTab(sf, ct)
    local y = -8

    -- ── Export section ────────────────────────────────────────────────────────
    y = AddHeader(ct, y, L["BACKUP_EXPORT_HEADER"])

    local desc = ct:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    desc:SetPoint("TOPLEFT",  ct, "TOPLEFT",  0, y)
    desc:SetWidth(CONTENT_W); desc:SetJustifyH("LEFT")
    desc:SetWordWrap(true); desc:SetHeight(32)
    desc:SetTextColor(0.78, 0.78, 0.78)
    desc:SetText(L["BACKUP_EXPORT_DESC"])
    y = y - 38

    -- Format radio buttons
    local _exportFmt = FMT_MARKDOWN   -- local state for this tab instance

    local function MakeRadio(label, fmt, xOff)
        local rb = CreateFrame("CheckButton", nil, ct, "UICheckButtonTemplate")
        rb:SetSize(20, 20)
        rb:SetPoint("TOPLEFT", ct, "TOPLEFT", xOff, y + 2)
        rb:SetChecked(_exportFmt == fmt)
        local lbl = ct:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        lbl:SetPoint("LEFT", rb, "RIGHT", 4, 0)
        lbl:SetText(label)
        return rb
    end

    local rbMd   = MakeRadio(L["BACKUP_FORMAT_MARKDOWN"], FMT_MARKDOWN, 0)
    local rbJson = MakeRadio(L["BACKUP_FORMAT_JSON"],     FMT_JSON,     CONTENT_W / 2)
    -- Explicitly sync state after both buttons exist so neither is stuck visually checked
    rbMd:SetChecked(true); rbJson:SetChecked(false)

    -- Format description (single label, swaps text with the radio selection)
    y = y - 26
    local fmtDesc = ct:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    fmtDesc:SetPoint("TOPLEFT",  ct, "TOPLEFT",  0, y)
    fmtDesc:SetPoint("TOPRIGHT", ct, "TOPRIGHT", 0, y)
    fmtDesc:SetJustifyH("LEFT")
    fmtDesc:SetWordWrap(true)
    fmtDesc:SetHeight(32)   -- two wrapped lines at GameFontNormalSmall ≈ 13px each + gap
    fmtDesc:SetTextColor(0.60, 0.60, 0.60)
    fmtDesc:SetText(L["BACKUP_FMT_DESC_MARKDOWN"])
    y = y - 38

    rbMd:SetScript("OnClick", function()
        _exportFmt = FMT_MARKDOWN
        rbMd:SetChecked(true); rbJson:SetChecked(false)
        fmtDesc:SetText(L["BACKUP_FMT_DESC_MARKDOWN"])
    end)
    rbJson:SetScript("OnClick", function()
        _exportFmt = FMT_JSON
        rbJson:SetChecked(true); rbMd:SetChecked(false)
        fmtDesc:SetText(L["BACKUP_FMT_DESC_JSON"])
    end)

    -- Export button + status label
    local exportBtn = BNB.CreateButton(nil, ct, L["BACKUP_BTN_EXPORT"], 180, 26)
    exportBtn:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)

    local exportStatus = ct:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    exportStatus:SetPoint("LEFT", exportBtn, "RIGHT", 10, 0)
    exportStatus:SetPoint("RIGHT", ct, "RIGHT", 0, 0)
    exportStatus:SetJustifyH("LEFT")
    exportStatus:SetHeight(26)
    exportStatus:SetTextColor(0.55, 0.82, 0.55)
    exportStatus:SetText("")

    exportBtn:SetScript("OnClick", function()
        local text, n = SerializeNotes(_exportFmt)
        if not text or n == 0 then
            exportStatus:SetTextColor(0.82, 0.55, 0.55)
            exportStatus:SetText(L["BACKUP_IMPORT_NONE"])
            return
        end
        -- Try clipboard first; if text is very long, fall back to editbox
        local ok = pcall(function()
            if C_System and C_System.SetClipboard then
                C_System.SetClipboard(text)
            else
                error("no clipboard")
            end
        end)
        if ok then
            exportStatus:SetTextColor(0.55, 0.82, 0.55)
            exportStatus:SetText(string.format(L["BACKUP_BTN_COPY_DONE"], n))
        else
            -- Fallback: open a scrollable editbox window
            BNB.OpenExportWindow(text)
            exportStatus:SetTextColor(0.78, 0.78, 0.78)
            exportStatus:SetText(L["BACKUP_BTN_COPY_FALLBACK"])
        end
    end)
    y = y - 40

    y = AddRule(ct, y) - 4

    -- ── Import section ────────────────────────────────────────────────────────
    y = AddHeader(ct, y, L["BACKUP_IMPORT_HEADER"])

    local desc2 = ct:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    desc2:SetPoint("TOPLEFT",  ct, "TOPLEFT",  0, y)
    desc2:SetWidth(CONTENT_W); desc2:SetJustifyH("LEFT")
    desc2:SetWordWrap(true); desc2:SetHeight(42)
    desc2:SetTextColor(0.78, 0.78, 0.78)
    desc2:SetText(L["BACKUP_IMPORT_DESC"])
    y = y - 48

    -- Paste target editbox (scrollable, fixed height)
    local PASTE_H = 140
    local pasteFrame = BNB.CreateBackdropFrame("Frame", nil, ct)
    BNB.SetBackdropDark(pasteFrame)
    pasteFrame:SetPoint("TOPLEFT",  ct, "TOPLEFT",  0, y)
    pasteFrame:SetWidth(CONTENT_W)
    pasteFrame:SetHeight(PASTE_H)

    local pasteSF = CreateFrame("ScrollFrame", nil, pasteFrame, "ScrollFrameTemplate")
    pasteSF:SetPoint("TOPLEFT",     pasteFrame, "TOPLEFT",      4,  -4)
    pasteSF:SetPoint("BOTTOMRIGHT", pasteFrame, "BOTTOMRIGHT", -24,  4)
    if pasteSF.ScrollBar then
        pasteSF.ScrollBar:SetAlpha(0)
        pasteSF:HookScript("OnScrollRangeChanged", function(_, _, yRange)
            pasteSF.ScrollBar:SetAlpha((yRange or 0) > 1 and 1.0 or 0)
        end)
    end

    local pasteChild = CreateFrame("Frame", nil, pasteSF)
    pasteChild:SetSize(CONTENT_W - 32, PASTE_H - 8)
    pasteSF:SetScrollChild(pasteChild)

    local pasteEb = CreateFrame("EditBox", nil, pasteChild)
    pasteEb:SetPoint("TOPLEFT",     pasteChild, "TOPLEFT",      0,  0)
    pasteEb:SetPoint("BOTTOMRIGHT", pasteChild, "BOTTOMRIGHT",  0,  0)
    pasteEb:SetFontObject("GameFontNormalSmall")
    pasteEb:SetMultiLine(true)
    pasteEb:SetAutoFocus(false)
    pasteEb:SetMaxLetters(0)   -- unlimited
    BNB.AddPlaceholder(pasteEb, L["BACKUP_PASTE_HINT"], 0.38, 0.38, 0.38)

    -- The scroll frame handles overflow; pasteChild just needs a stable minimum.
    -- EditBox does not expose GetStringHeight -- height expansion is not needed here.

    y = y - PASTE_H - 6

    -- Import button + status label
    local importBtn = BNB.CreateButton(nil, ct, L["BACKUP_BTN_IMPORT"], 120, 26)
    importBtn:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)

    local clearBtn = BNB.CreateButton(nil, ct, L["CANCEL"], 80, 26)
    clearBtn:SetPoint("LEFT", importBtn, "RIGHT", 8, 0)

    local importStatus = ct:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    importStatus:SetPoint("LEFT", clearBtn, "RIGHT", 10, 0)
    importStatus:SetPoint("RIGHT", ct, "RIGHT", 0, 0)
    importStatus:SetJustifyH("LEFT")
    importStatus:SetHeight(26)
    importStatus:SetText("")

    -- Enable/disable Import + Cancel based on whether the paste box has content.
    local function UpdateImportBtns()
        local hasContent = not pasteEb._showingPlaceholder
            and not pasteEb:GetText():match("^%s*$")
        importBtn:SetEnabled(hasContent)
        clearBtn:SetEnabled(hasContent)
    end
    importBtn:SetEnabled(false)
    clearBtn:SetEnabled(false)
    pasteEb:HookScript("OnTextChanged", UpdateImportBtns)

    clearBtn:SetScript("OnClick", function()
        pasteEb:SetRealText("")
        importStatus:SetText("")
    end)

    importBtn:SetScript("OnClick", function()
        local raw = pasteEb._showingPlaceholder and "" or pasteEb:GetText()
        if not raw or raw:match("^%s*$") then
            importStatus:SetTextColor(0.82, 0.55, 0.55)
            importStatus:SetText(L["BACKUP_IMPORT_NONE"])
            return
        end

        local notes = ParseJsonNotes(raw) or ParseMarkdownNotes(raw)
        if not notes then
            importStatus:SetTextColor(0.82, 0.55, 0.55)
            importStatus:SetText(L["BACKUP_IMPORT_ERR"])
            return
        end

        -- Check if any notes are scoped to a different character
        local foreignChar = nil
        for _, note in ipairs(notes) do
            if note.scope and note.scope:find("^char:") then
                local charPart = note.scope:sub(6)
                if charPart ~= (BNB.currentChar or "") then
                    foreignChar = charPart
                    break
                end
            end
        end

        if foreignChar and BNB.currentChar and foreignChar ~= BNB.currentChar then
            -- Store pending data for the popup callbacks
            BNB._pendingImport = { notes = notes, status = importStatus, paste = pasteEb }
            BNB._pendingImportForeign = foreignChar
            StaticPopup_Show("BNB_IMPORT_SCOPE_REMAP", foreignChar, BNB.currentChar)
        else
            -- Same-character or scope-less path — confirm count before importing
            BNB._pendingImport = { notes = notes, status = importStatus, paste = pasteEb }
            StaticPopup_Show("BNB_IMPORT_CONFIRM", #notes)
        end
    end)
    y = y - 40

    sf:FinaliseHeight(math.abs(y) + 12)
end

-- ── Fallback export window (clipboard unavailable or oversized payload) ───────
-- A simple resizable frame with a scrollable read-only editbox.
-- User selects all with Ctrl+A and copies manually.

local _exportWin = nil
local SK_EXP_TITLE_H = 28

function BNB.OpenExportWindow(text, warningText, htmlNoteID)
    if not _exportWin then
        local f
        if BigNoteBoxDB and BigNoteBoxDB.skinMode then
            f = BNB.CreateSkinFrame(UIParent, false, "BigNoteBoxExportFrame", false)
            _G["BigNoteBoxExportFrame"] = f
            f:SetSize(520, 440)
            f:SetPoint("CENTER")
            f:SetFrameStrata("DIALOG")
            f:SetToplevel(true); f:EnableMouse(true); f:SetMovable(true); f:SetClampedToScreen(true)
            f:RegisterForDrag("LeftButton")
            f:SetScript("OnDragStart", function(self) self:StartMoving() end)
            f:SetScript("OnDragStop",  function(self) self:StopMovingOrSizing() end)

            local titleBar = BNB.CreateSkinStrip(f, true, false)
            titleBar:SetPoint("TOPLEFT",  f, "TOPLEFT",  0, 0)
            titleBar:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
            titleBar:SetHeight(SK_EXP_TITLE_H)
            titleBar:EnableMouse(true)
            titleBar:RegisterForDrag("LeftButton")
            titleBar:SetScript("OnDragStart", function() f:StartMoving() end)
            titleBar:SetScript("OnDragStop",  function() f:StopMovingOrSizing() end)

            local titleLbl = titleBar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            titleLbl:SetPoint("CENTER", titleBar, "CENTER", -12, 0)
            titleLbl:SetTextColor(1, 0.82, 0)
            titleLbl:SetText("BigNoteBox -- Export")

            local closeBtn = BNB.CreateSkinCloseButton(titleBar, function() f:Hide() end)
            closeBtn:SetPoint("RIGHT", titleBar, "RIGHT", -3, 0)

            local copyBtn = BNB.CreateButton(nil, f, "Copy to Clipboard", 140, 24)
            copyBtn:SetPoint("TOP", f, "TOP", 0, -(SK_EXP_TITLE_H + 8))
            copyBtn:SetScript("OnClick", function() BNB.ShowClipboardHint(f._eb:GetText()) end)
            f._copyBtn = copyBtn

            local sf = CreateFrame("ScrollFrame", nil, f, "ScrollFrameTemplate")
            sf:SetPoint("TOPLEFT",     f, "TOPLEFT",     16, -(SK_EXP_TITLE_H + 8 + 24 + 6))
            sf:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -24, 16)
            if sf.ScrollBar then
                sf.ScrollBar:SetAlpha(0)
                sf:HookScript("OnScrollRangeChanged", function(_, _, yRange)
                    sf.ScrollBar:SetAlpha((yRange or 0) > 1 and 1.0 or 0)
                end)
            end

            local child = CreateFrame("Frame", nil, sf)
            child:SetSize(460, 1)
            sf:SetScrollChild(child)

            local eb = CreateFrame("EditBox", nil, child)
            eb:SetPoint("TOPLEFT",     child, "TOPLEFT",     0, 0)
            eb:SetPoint("BOTTOMRIGHT", child, "BOTTOMRIGHT", 0, 0)
            eb:SetFontObject("GameFontNormalSmall")
            eb:SetMultiLine(true); eb:SetAutoFocus(true)
            eb:SetMaxLetters(0)
            eb:SetScript("OnEscapePressed", function() f:Hide() end)

            f._eb = eb; f._child = child; f._sf = sf

            f:SetScript("OnShow", function()
                if BNB.ApplyMainWindowSkin then BNB.ApplyMainWindowSkin() end
            end)
            f:Hide()
        else
            f = CreateFrame("Frame", "BigNoteBoxExportFrame", UIParent, "ButtonFrameTemplate")
            f:SetSize(520, 440)
            f:SetPoint("CENTER")
            f:SetFrameStrata("DIALOG")
            f:SetToplevel(true); f:EnableMouse(true); f:SetMovable(true); f:SetClampedToScreen(true)
            f:RegisterForDrag("LeftButton")
            f:SetScript("OnDragStart", function(self) self:StartMoving() end)
            f:SetScript("OnDragStop",  function(self) self:StopMovingOrSizing() end)
            ButtonFrameTemplate_HidePortrait(f)
            ButtonFrameTemplate_HideButtonBar(f)
            if f.Inset then f.Inset:Hide() end
            f:SetTitle("BigNoteBox -- Export")
            if f.CloseButton then
                f.CloseButton:SetScript("OnClick", function() f:Hide() end)
            end

            local copyBtn = BNB.CreateButton(nil, f, "Copy to Clipboard", 140, 24)
            copyBtn:SetPoint("TOP", f, "TOP", 0, -58)
            copyBtn:SetScript("OnClick", function()
                BNB.ShowClipboardHint(f._eb:GetText())
            end)
            f._copyBtn = copyBtn

            local sf = CreateFrame("ScrollFrame", nil, f, "ScrollFrameTemplate")
            sf:SetPoint("TOPLEFT",     f, "TOPLEFT",    16, -90)
            sf:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT",-24,  16)
            if sf.ScrollBar then
                sf.ScrollBar:SetAlpha(0)
                sf:HookScript("OnScrollRangeChanged", function(_, _, yRange)
                    sf.ScrollBar:SetAlpha((yRange or 0) > 1 and 1.0 or 0)
                end)
            end

            local child = CreateFrame("Frame", nil, sf)
            child:SetSize(460, 1)
            sf:SetScrollChild(child)

            local eb = CreateFrame("EditBox", nil, child)
            eb:SetPoint("TOPLEFT",     child, "TOPLEFT",      0,  0)
            eb:SetPoint("BOTTOMRIGHT", child, "BOTTOMRIGHT",  0,  0)
            eb:SetFontObject("GameFontNormalSmall")
            eb:SetMultiLine(true); eb:SetAutoFocus(true)
            eb:SetMaxLetters(0)
            eb:SetScript("OnEscapePressed", function() f:Hide() end)

            f._eb    = eb
            f._child = child
            f._sf    = sf
            f:Hide()
        end
        tinsert(UISpecialFrames, "BigNoteBoxExportFrame")
        _exportWin = f
    end

    -- Lazy-create the warning label (anchored above the copy button)
    if not _exportWin._warnLbl then
        local wl = _exportWin:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        wl:SetPoint("BOTTOMLEFT",  _exportWin._copyBtn, "TOPLEFT",  0, 4)
        wl:SetPoint("BOTTOMRIGHT", _exportWin._copyBtn, "TOPRIGHT", 0, 4)
        wl:SetJustifyH("CENTER")
        wl:SetWordWrap(true)
        wl:SetTextColor(1, 0.75, 0.25)
        wl:Hide()
        _exportWin._warnLbl = wl
    end

    -- Lazy-create the HTML mode dropdown (anchored to the right of the copy button)
    if not _exportWin._htmlDD then
        local HTML_MODES = {
            { key = "noteonly",  label = "Note only" },
            { key = "plain",    label = "Plain HTML" },
            { key = "stylized", label = "Stylized" },
        }
        local dd = CreateFrame("DropdownButton", nil, _exportWin, "WowStyle1DropdownTemplate")
        dd:SetPoint("LEFT", _exportWin._copyBtn, "RIGHT", 8, 0)
        dd:SetWidth(150)
        dd:SetHeight(24)
        local function SetupHtmlDD()
            dd:SetupMenu(function(_, root)
                for _, opt in ipairs(HTML_MODES) do
                    root:CreateRadio(opt.label,
                        function() return _htmlExportMode == opt.key end,
                        function()
                            _htmlExportMode = opt.key
                            dd:GenerateMenu()
                            -- Regenerate with the new mode
                            if _exportWin._htmlNoteID then
                                local note = BNB.GetNote(_exportWin._htmlNoteID)
                                if note then
                                    local html, hasImages = HtmlEncodeNote(note, _htmlExportMode)
                                    _exportWin._eb:SetText(html)
                                    if hasImages then
                                        _exportWin._warnLbl:SetText("This note contains images. Place your image files in an 'img' folder next to the HTML file.")
                                        _exportWin._warnLbl:Show()
                                    else
                                        _exportWin._warnLbl:SetText("")
                                        _exportWin._warnLbl:Hide()
                                    end
                                    C_Timer.After(0.05, function()
                                        if _exportWin then
                                            _exportWin._child:SetHeight(math.max(_exportWin._eb:GetHeight() + 20, 400))
                                        end
                                    end)
                                end
                            end
                        end)
                end
            end)
        end
        SetupHtmlDD()
        dd:Hide()
        _exportWin._htmlDD = dd
        _exportWin._setupHtmlDD = SetupHtmlDD
    end

    -- Show or hide the HTML mode dropdown
    _exportWin._htmlNoteID = htmlNoteID
    if htmlNoteID then
        if _exportWin._setupHtmlDD then _exportWin._setupHtmlDD() end
        _exportWin._htmlDD:Show()
    else
        _exportWin._htmlDD:Hide()
    end

    -- Show or hide the warning
    if warningText and warningText ~= "" then
        _exportWin._warnLbl:SetText(warningText)
        _exportWin._warnLbl:Show()
    else
        _exportWin._warnLbl:SetText("")
        _exportWin._warnLbl:Hide()
    end

    _exportWin._eb:SetText(text or "")
    -- Size child to content -- use a generous fixed height; scroll handles the rest
    C_Timer.After(0.05, function()
        if not _exportWin then return end
        _exportWin._child:SetHeight(math.max(_exportWin._eb:GetHeight() + 20, 400))
    end)
    _exportWin:Show()
    _exportWin._eb:SetFocus()
    _exportWin._eb:HighlightText()
end

-- ─────────────────────────────────────────────────────────────────────────────
-- CREATE WINDOW
-- ─────────────────────────────────────────────────────────────────────────────
local BUILDERS = {
    general    = BuildGeneralTab,
    appearance = BuildAppearanceTab,
    features   = BuildFeaturesTab,
    editor     = BuildEditorTab,
    backup     = BuildBackupTab,
    advanced   = BuildAdvancedTab,
}

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
    if _refreshFontLabels then _refreshFontLabels() end
    if _refreshFontHL     then _refreshFontHL()     end
    C_Timer.After(0.1, function()
        if _refreshFontLabels then _refreshFontLabels() end
        if _refreshFontHL     then _refreshFontHL()     end
    end)
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
        if builder then builder(sf, ct) end
    end

    -- Re-apply font TTF paths whenever the Appearance tab is shown.
    -- The picker labels are built at BuildAppearanceTab time; if the renderer
    -- hasn't registered the .ttf files yet (first session, fast login) they
    -- render blank. Hooking OnShow guarantees the paths are re-set when the
    -- tab becomes visible, by which point PLAYER_LOGIN + InitFonts have run.
    local appearanceIdx = 2   -- "appearance" is the second tab in TABS
    if panels[appearanceIdx] then
        panels[appearanceIdx]:HookScript("OnShow", RefreshConfigFonts)
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

-- ── Per-note export helpers (called from the note context menu) ───────────────
-- C_System.SetClipboard is restricted on retail — always use the export window
-- with ShowClipboardHint for the Ctrl+C copy flow.

function BNB.ExportNoteJSON(noteID)
    local note = BNB.GetNote(noteID)
    if not note then return end
    BNB.OpenExportWindow(JsonEncodeNote(note))
end

function BNB.ExportNoteMD(noteID)
    local note = BNB.GetNote(noteID)
    if not note then return end
    BNB.OpenExportWindow(MdEncodeNote(note))
end

function BNB.ExportNoteHTML(noteID)
    local note = BNB.GetNote(noteID)
    if not note then return end
    _htmlExportMode = _htmlExportMode or "plain"
    local html, hasImages = HtmlEncodeNote(note, _htmlExportMode)
    local warn = hasImages
        and "This note contains images. Place your image files in an 'img' folder next to the HTML file."
        or nil
    BNB.OpenExportWindow(html, warn, noteID)
end

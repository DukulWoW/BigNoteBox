-- BigNoteBox UI/StickySettings.lua - Detached sticky note settings window
-- Opened by the "=" header button on a sticky (UI/StickyNote.lua).
-- Split out of StickyNote.lua (ALL-65.10).

local BNB = BigNoteBox
local L   = BNB.L

local SN = BNB.Sticky
local K  = SN._kit
local openFrames            = K.openFrames
local EnsureESCHook         = K.EnsureESCHook
local GetCfg                = K.GetCfg
local SaveCfg               = K.SaveCfg
local BG_TEXTURES           = K.BG_TEXTURES
local BgTextureLabel        = K.BgTextureLabel
local OUTLINE_OPTIONS       = K.OUTLINE_OPTIONS
local ApplyOutlineToEditBox = K.ApplyOutlineToEditBox
local ApplyBgAlpha          = K.ApplyBgAlpha
local ApplyConfig           = K.ApplyConfig
local FadeFrame             = K.FadeFrame

-- ── Settings face ─────────────────────────────────────────────────────────────
-- Lives INSIDE the note frame, covering the same area as the front face.
-- Styled to match the config window: COL_HEADER title bar, COL_BG background,
-- gold title, "< Back" button.
-- The note root frame already has RegisterForDrag, so dragging still works.
-- Opening/closing crossfades front↔settings in-place (no size change).
-- ── Detached sticky note settings window ──────────────────────────────────────
-- A standalone ButtonFrameTemplate window (same look as the main BNB window)
-- that fades in (FadeFrame) when the user clicks "=" on a sticky.

local SETTINGS_W = 264   -- matches NoteConfig NCW
-- Content starts just below the tab button bottoms (~y=-45 from frame top) + small pad
local SETTINGS_TAB_CONTENT_Y = 62
local SETTINGS_PAD = 12  -- matches NoteConfig PAD
local SETTINGS_CW = 224  -- matches NoteConfig CW_SCROLL (NCW - PAD - 28)

local _stickySettingsFrame = nil   -- single reusable settings window
local _stickySettingsNoteID = nil  -- noteID it's currently editing

local function GetBorderList()
    local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
    local seen = { ["Default"] = true, ["None"] = true }
    local list = { "None", "Default" }
    if LSM then
        for _, v in ipairs(LSM:List("border")) do
            if not seen[v] then seen[v] = true; list[#list+1] = v end
        end
    end
    return list
end

local OpenColorPicker = BNB.OpenColorPicker   -- UI/Widgets.lua

-- Close the detached settings window and restore the sticky note
local function CloseStickySettings()
    local noteID = _stickySettingsNoteID
    local f      = _stickySettingsFrame
    if not f or not f:IsShown() then return end

    local stickyFrame = noteID and openFrames[noteID]

    -- Apply config before restoring the sticky
    if stickyFrame and noteID then ApplyConfig(stickyFrame, noteID) end

    FadeFrame(f, f:GetAlpha(), 0, 0.2, function()
        f:Hide()
        if stickyFrame then stickyFrame:SetAlpha(1.0) end
    end)
end

local SK_SS_TITLE_H   = 28
local SK_SS_CONTENT_Y = 58   -- SK_SS_TITLE_H(28) + SK_TAB_H(24) + 6px gap

-- Registered here (after CloseStickySettings is declared) so the OnHide hook
-- in EnsureESCHook can reach it via SN._OnESCHide().
SN._OnESCHide = function()
    if _stickySettingsFrame and _stickySettingsFrame:IsShown() then
        local noteID = _stickySettingsNoteID
        if noteID then
            local sf = openFrames[noteID]
            if sf and sf._escOnly then
                CloseStickySettings()
            end
        end
    end
end

local function BuildStickySettingsWindow()
    if _stickySettingsFrame then return _stickySettingsFrame end

    local skinMode = BigNoteBoxDB and BigNoteBoxDB.skinMode
    local f
    local tabContentY  -- used by MakeScrollPanel / MakePlainPanel below

    if skinMode then
        f = BNB.CreateSkinFrame(UIParent, false, "BigNoteBoxStickySettingsFrame", false)
        _G["BigNoteBoxStickySettingsFrame"] = f
        f:SetSize(SETTINGS_W, 640)
        f:SetFrameStrata("DIALOG")
        f:SetToplevel(true); f:EnableMouse(true); f:SetMovable(true); f:SetClampedToScreen(true)
        f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", function(self) self:StartMoving() end)
        f:SetScript("OnDragStop",  function(self)
            self:StopMovingOrSizing()
            -- Settings detaches freely when dragged — sticky stays where it is.
        end)

        local titleBar = BNB.CreateSkinStrip(f, true, false)
        titleBar:SetPoint("TOPLEFT",  f, "TOPLEFT",  0, 0)
        titleBar:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
        titleBar:SetHeight(SK_SS_TITLE_H)
        titleBar:EnableMouse(true)
        titleBar:RegisterForDrag("LeftButton")
        titleBar:SetScript("OnDragStart", function() f:StartMoving() end)
        titleBar:SetScript("OnDragStop",  function()
            f:StopMovingOrSizing()
        end)

        local titleLbl = titleBar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        titleLbl:SetPoint("CENTER", titleBar, "CENTER", -12, 0)
        titleLbl:SetTextColor(1, 0.82, 0)
        titleLbl:SetText(L["STICKY_SETTINGS_TITLE"])
        f._titleLbl = titleLbl

        local closeBtn = BNB.CreateSkinCloseButton(titleBar, function() CloseStickySettings() end)
        closeBtn:SetPoint("RIGHT", titleBar, "RIGHT", -3, 0)

        f:SetScript("OnShow", function()
            if BNB.ApplyMainWindowSkin then BNB.ApplyMainWindowSkin() end
        end)
        tabContentY = SK_SS_CONTENT_Y
    else
        f = CreateFrame("Frame", "BigNoteBoxStickySettingsFrame", UIParent, "ButtonFrameTemplate")
        f:SetSize(SETTINGS_W, 640)
        f:SetFrameStrata("DIALOG")
        f:SetToplevel(true); f:EnableMouse(true); f:SetMovable(true); f:SetClampedToScreen(true)
        f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", function(self)
            self:StartMoving()
        end)
        f:SetScript("OnDragStop", function(self)
            self:StopMovingOrSizing()
            -- Settings detaches freely when dragged — sticky stays where it is.
            -- The anchor to the sticky is broken by StartMoving(); that is intentional.
        end)

        ButtonFrameTemplate_HidePortrait(f)
        ButtonFrameTemplate_HideButtonBar(f)
        if f.Inset then f.Inset:Hide() end
        BNB.SeatChrome(f)   -- FOR-05: Forever border offset (UI/Chrome.lua)
        f._forGlow = BNB.AddForeverGlow(f, f.Bg)   -- Forever: glow over the wood grain
        f:SetAlpha(0.95)
        f:SetTitle(L["STICKY_SETTINGS_TITLE"])
        if f.CloseButton then
            f.CloseButton:SetScript("OnClick", function() CloseStickySettings() end)
        end
        tabContentY = SETTINGS_TAB_CONTENT_Y
    end
    tinsert(UISpecialFrames, "BigNoteBoxStickySettingsFrame")

    -- The waypoint info popup is parented to UIParent, so it would outlive this window
    f:HookScript("OnHide", function()
        if BNBStickyWaypointInfoPopup then BNBStickyWaypointInfoPopup:Hide() end
    end)

    -- ── Tab buttons ───────────────────────────────────────────────────────────
    local sTabBtns   = {}
    local sTabPanels = {}
    local TAB_LABELS = { L["CFG_TAB_GENERAL"], L["CFG_TAB_APPEARANCE"], L["NC_TAB_SITUATION"] }

    local function SelectStickyTab(idx)
        for i = 1, 3 do
            if sTabBtns[i] and not skinMode then
                if i == idx then PanelTemplates_SelectTab(sTabBtns[i])
                else             PanelTemplates_DeselectTab(sTabBtns[i]) end
            end
            if sTabPanels[i] then
                if i == idx then sTabPanels[i]:Show()
                else             sTabPanels[i]:Hide() end
            end
        end
        f._activeTab = idx
    end

    if skinMode then
        local tabCtrl = BNB.CreateSkinTabs(f, TAB_LABELS, function(idx)
            SelectStickyTab(idx)
        end)
        tabCtrl.frame:SetPoint("TOPLEFT",  f, "TOPLEFT",  0, -SK_SS_TITLE_H)
        tabCtrl.frame:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, -SK_SS_TITLE_H)
        f._skinTabCtrl = tabCtrl
    else
        local tpl = (C_XMLUtil and C_XMLUtil.GetTemplateInfo
            and C_XMLUtil.GetTemplateInfo("PanelTopTabButtonTemplate"))
            and "PanelTopTabButtonTemplate"
            or  "PanelTabButtonTemplate"

        local lastBtn = nil
        for i, label in ipairs(TAB_LABELS) do
            local btn = CreateFrame("Button", "BigNoteBoxStickySettingsTab"..i, f, tpl)
            btn:SetText(label)
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
            btn:SetScript("OnClick", function(self) SelectStickyTab(self:GetID()) end)
            sTabBtns[i] = btn
            lastBtn = btn
        end
        PanelTemplates_SetNumTabs(f, 3)
        f.numTabs = 3
    end

    -- ── Two scroll panels (one per tab) ───────────────────────────────────────
    local function MakeScrollPanel()
        local sf, ct = BNB.CreateAutoScrollPanel(f, SETTINGS_CW, SETTINGS_CW + 20)
        sf:SetPoint("TOPLEFT",     f, "TOPLEFT",      SETTINGS_PAD, -tabContentY)
        sf:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -24, 4)
        return sf, ct
    end

    -- Plain (non-scrolling) panel — used for Situation tab which has
    -- anchor-relative content that doesn't need a scroll child.
    local function MakePlainPanel()
        local p = CreateFrame("Frame", nil, f)
        p:SetPoint("TOPLEFT",     f, "TOPLEFT",      SETTINGS_PAD, -tabContentY)
        p:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -SETTINGS_PAD, 4)
        p:Hide()
        -- ct and sf are the same frame for a plain panel
        return p, p
    end

    local sf1, ct1 = MakeScrollPanel()
    local sf2, ct2 = MakeScrollPanel()
    local sf3, ct3 = MakePlainPanel()
    sTabPanels[1] = sf1
    sTabPanels[2] = sf2
    sTabPanels[3] = sf3

    f._sTabBtns   = sTabBtns
    f._sTabPanels = sTabPanels
    f._selectTab  = SelectStickyTab
    f._ct1 = ct1   -- General
    f._ct2 = ct2   -- Appearance
    f._ct3 = ct3   -- Situation

    f:Hide()
    _stickySettingsFrame = f
    return f
end

-- Populate settings content for a specific noteID
-- Destroys and recreates content children each time (simple, no stale state)
local function PopulateStickySettings(noteID)
    local f   = _stickySettingsFrame
    local ct1 = f._ct1   -- General tab content
    local ct2 = f._ct2   -- Appearance tab content
    local ct3 = f._ct3   -- Situation tab content
    local sf1 = f._sTabPanels[1]
    local sf2 = f._sTabPanels[2]
    local sf3 = f._sTabPanels[3]

    -- Destroy old content children in all panels
    for _, ct in ipairs({ct1, ct2, ct3}) do
        for _, child in ipairs({ct:GetChildren()}) do child:Hide(); child:SetParent(nil) end
        for _, region in ipairs({ct:GetRegions()}) do region:Hide(); region:SetParent(nil) end
    end

    local stickyFrame = openFrames[noteID]
    local cfg = GetCfg(noteID)
    local skinMode = BigNoteBoxDB and BigNoteBoxDB.skinMode

    -- ── Shared layout helpers (take ct as param) ──────────────────────────────
    local function Sec(ct, txt)
        local y = ct._y or -8
        local l = ct:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        l:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
        l:SetTextColor(1, 0.82, 0, 1); l:SetText(txt)
        ct._y = y - 22
    end

    local function SubLbl(ct, txt)
        local y = ct._y or -8
        local l = ct:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        l:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
        l:SetTextColor(0.60, 0.60, 0.60); l:SetText(txt)
        ct._y = y - 16
    end

    local function Hdr(ct, txt)
        local y = ct._y or -8
        local l = ct:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        l:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
        l:SetTextColor(0.75, 0.75, 0.75); l:SetText(txt)
        ct._y = y - 18
    end

    local function Rule(ct)
        local y = ct._y or -8
        BNB.CreateRule(ct, y)
        ct._y = y - 10
    end

    local function MakeSlider(ct, label, minV, maxV, initV, onChange)
        local y = ct._y or -8
        local sl = BNB.CreateSlider(ct, label, minV, maxV, initV, nil,
            function(v) onChange(v) end)
        sl:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
        -- Pull right edge in so the MinimalSlider's value label (rendered
        -- outside the slider frame to the right) doesn't clip the scrollbar.
        sl:SetWidth(SETTINGS_CW - 30)
        sl:EnableMouseWheel(false)
        ct._y = y - 44
        return sl
    end

    local function ColorBtn(ct, r, g, b, labelTxt, onPick)
        local y = ct._y or -8
        local sw = CreateFrame("Button", nil, ct)
        sw:SetSize(26, 26)
        sw:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
        local tx = sw:CreateTexture(nil, "ARTWORK"); tx:SetAllPoints()
        tx:SetColorTexture(r, g, b)
        local hi = sw:CreateTexture(nil, "HIGHLIGHT"); hi:SetAllPoints()
        hi:SetColorTexture(1, 1, 1, 0.25)
        local bdr = BNB.CreateBackdropFrame("Frame", nil, sw)
        bdr:SetAllPoints(); bdr:SetFrameLevel(sw:GetFrameLevel() - 1)
        BNB.SetBackdrop(bdr, 0,0,0,0, 0.45, 0.45, 0.48, 1)
        bdr:EnableMouse(false)
        local ll = ct:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        ll:SetPoint("LEFT", sw, "RIGHT", 6, 0)
        ll:SetTextColor(0.78, 0.78, 0.78); ll:SetText(labelTxt)
        sw._tx = tx
        local cR, cG, cB = r, g, b
        sw:SetScript("OnClick", function()
            local oR, oG, oB = cR, cG, cB
            OpenColorPicker(cR, cG, cB, function(nr, ng, nb)
                cR, cG, cB = nr, ng, nb
                sw._tx:SetColorTexture(nr, ng, nb)
                onPick(nr, ng, nb)
            end)
        end)
        ct._y = y - 34
        return sw
    end

    local function ColorGrid(ct, swatchOnPick)
        ct._y = BNB.BuildColorGrid(ct, ct._y or -8, SETTINGS_CW, swatchOnPick)
    end

    local function FinalisePanel(ct, sf)
        local contentH = math.abs(ct._y or -8) + 12
        ct._contentH = contentH
        ct:SetHeight(math.max(contentH, sf:GetHeight()))
        C_Timer.After(0.05, function()
            if sf._applyScrollbar then sf._applyScrollbar() end
        end)
    end

    -- ══════════════════════════════════════════════════════════════════════════
    -- TAB 1 — GENERAL
    -- ══════════════════════════════════════════════════════════════════════════
    ct1._y = -8

    -- ── Focus mode toggle ─────────────────────────────────────────────────────
    -- Hides title, icon and border (fade in on hover). Compact content padding.
    -- Rich notes render as plain text. Task view uses compact row spacing.
    do
        local focusChk = CreateFrame("CheckButton", nil, ct1, "UICheckButtonTemplate")
        focusChk:SetSize(24, 24)
        focusChk:SetPoint("TOPLEFT", ct1, "TOPLEFT", -4, ct1._y)
        focusChk:SetChecked(cfg.focusMode == true)
        focusChk:SetScript("OnClick", function(self)
            cfg.focusMode = self:GetChecked() and true or nil
            SaveCfg(noteID, cfg)
            if stickyFrame then
                ApplyConfig(stickyFrame, noteID)
            end
        end)
        local focusLbl = ct1:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        focusLbl:SetPoint("LEFT", focusChk, "RIGHT", 4, 0)
        focusLbl:SetText(L["STICKY_FOCUS_MODE_LABEL"])
        focusChk:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(L["STICKY_FOCUS_MODE_LABEL"], 1, 1, 1)
            GameTooltip:AddLine(L["STICKY_FOCUS_MODE_TIP"], 0.8, 0.8, 0.8, true)
            GameTooltip:Show()
        end)
        focusChk:SetScript("OnLeave", function() GameTooltip:Hide() end)
        ct1._y = ct1._y - 30
    end

    -- ── Pin to ESC screen toggle ───────────────────────────────────────────────
    -- When on, this sticky is hidden in the game world and only appears when the
    -- ESC menu is open.  It is mutually exclusive with being shown in the world.
    do
        local escChk = CreateFrame("CheckButton", nil, ct1, "UICheckButtonTemplate")
        escChk:SetSize(24, 24)
        escChk:SetPoint("TOPLEFT", ct1, "TOPLEFT", -4, ct1._y)
        escChk:SetChecked(cfg.escOnly == true)
        escChk:SetScript("OnClick", function(self)
            -- Tri-state: nil=unset, true=ESC-only, false=explicitly normal.
            -- Write false (not nil) when unchecking so global default doesn't re-apply.
            local checked = self:GetChecked() and true or false
            cfg.escOnly = checked
            SaveCfg(noteID, cfg)
            local f = openFrames[noteID]
            if f then
                f._escOnly = checked and true or false
                EnsureESCHook()
                if checked then
                    -- Switching to ESC-only: hide from world, set correct strata.
                    f:SetFrameStrata("FULLSCREEN_DIALOG")
                    if not (GameMenuFrame and GameMenuFrame:IsShown()) then
                        f:Hide()
                        if f._miniTile then f._miniTile:Hide() end
                    end
                else
                    -- Switching back to normal: restore strata and show in world.
                    f:SetFrameStrata("HIGH")
                    if not f._minimized then
                        f:Show(); f:Raise()
                    end
                end
            end
        end)
        local escLbl = ct1:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        escLbl:SetPoint("LEFT", escChk, "RIGHT", 4, 0)
        escLbl:SetText(L["STICKY_ESC_PIN_LABEL"])
        escChk:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(L["STICKY_ESC_PIN_LABEL"], 1, 1, 1)
            GameTooltip:AddLine(L["STICKY_ESC_PIN_TIP"], 0.8, 0.8, 0.8, true)
            GameTooltip:Show()
        end)
        escChk:SetScript("OnLeave", function() GameTooltip:Hide() end)
        ct1._y = ct1._y - 30
    end
    -- Hidden entirely for plain notes. When on, the sticky renders raw text
    -- instead of the SimpleHTML view, and text color/style controls become active.
    local note         = BNB.GetNote(noteID)
    local noteIsRich   = BNB.AdvancedMode and BNB.AdvancedMode.IsRich(note)
    local richPlainChk, richPlainChkLbl

    if noteIsRich then
        richPlainChk = CreateFrame("CheckButton", nil, ct1, "UICheckButtonTemplate")
        richPlainChk:SetSize(24, 24)
        richPlainChk:SetPoint("TOPLEFT", ct1, "TOPLEFT", -4, ct1._y)
        richPlainChk:SetChecked(cfg.richPlainText == true)

        richPlainChkLbl = ct1:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        richPlainChkLbl:SetPoint("LEFT", richPlainChk, "RIGHT", 2, 0)
        richPlainChkLbl:SetText(L["STICKY_RICH_PLAIN_LABEL"])
        richPlainChkLbl:SetTextColor(0.9, 0.9, 0.9)

        ct1._y = ct1._y - 30
        Rule(ct1)
        ct1._y = ct1._y - 4
    end

    -- ── Text color ────────────────────────────────────────────────────────────
    -- Greyed out when the note is rich AND "show as plain text" is off,
    -- because the color has no effect on SimpleHTML rendering in that state.
    Sec(ct1, L["STICKY_TEXT_COLOR"])

    local textColorWidgets = {}  -- collect for alpha/mouse toggling
    local plainOnlyWidgets = {}  -- font, font-size, text-style, text-opacity: inactive for rich notes

    local tcBtn = ColorBtn(ct1, cfg.textR or 0.88, cfg.textG or 0.88, cfg.textB or 0.88,
        L["STICKY_CLICK_PICK_COLOR"], function(r, g, b)
            cfg.textR, cfg.textG, cfg.textB = r, g, b
            SaveCfg(noteID, cfg)
            if stickyFrame and stickyFrame._bodyEb then
                pcall(function() stickyFrame._bodyEb:SetTextColor(r, g, b) end)
            end
        end)
    textColorWidgets[#textColorWidgets+1] = tcBtn

    SubLbl(ct1, L["STICKY_QUICK_PICK_LABEL"])
    -- Snapshot children before ColorGrid so we can collect only what it adds
    local beforeChildren = {}
    for _, c in ipairs({ct1:GetChildren()}) do beforeChildren[c] = true end

    ColorGrid(ct1, function(r, g, b)
        cfg.textR, cfg.textG, cfg.textB = r, g, b
        SaveCfg(noteID, cfg)
        if stickyFrame and stickyFrame._bodyEb then
            pcall(function() stickyFrame._bodyEb:SetTextColor(r, g, b) end)
        end
    end)

    -- Collect everything ColorGrid added into textColorWidgets
    for _, c in ipairs({ct1:GetChildren()}) do
        if not beforeChildren[c] then
            textColorWidgets[#textColorWidgets + 1] = c
        end
    end

    -- Shared greying helper: dims controls that have no effect on a rich note
    -- rendered as SimpleHTML. Covers text color, font, font-size, text-style,
    -- and text-opacity. Called at build time and when the plain-text checkbox toggles.
    local function SyncPlainOnlyControls()
        local isPlain = (not noteIsRich) or (cfg.richPlainText == true)
        local a = isPlain and 1.0 or 0.4
        for _, w in ipairs(textColorWidgets) do
            pcall(function()
                w:SetAlpha(a)
                if w.EnableMouse then w:EnableMouse(isPlain) end
            end)
        end
        for _, w in ipairs(plainOnlyWidgets) do
            pcall(function()
                w:SetAlpha(a)
                if w.EnableMouse then w:EnableMouse(isPlain) end
            end)
        end
    end

    -- Wire the richPlainText checkbox now that SyncPlainOnlyControls is defined
    if richPlainChk then
        richPlainChk:SetScript("OnClick", function(self)
            cfg.richPlainText = self:GetChecked() and true or nil
            SaveCfg(noteID, cfg)
            SyncPlainOnlyControls()
            -- Re-render the sticky with the new mode
            if BNB.Sticky and BNB.Sticky.RefreshNote then
                BNB.Sticky.RefreshNote(noteID)
            end
        end)
        richPlainChk:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:AddLine(L["STICKY_RICH_PLAIN_LABEL"], 1, 1, 1)
            GameTooltip:AddLine(L["STICKY_RICH_PLAIN_TIP"], 0.78, 0.78, 0.78, true)
            GameTooltip:Show()
        end)
        richPlainChk:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end

    Rule(ct1)
    Sec(ct1, "Font")

    -- Font card picker — 2-column × 3-row grid layout
    -- Card dimensions: full height for readability, half width minus gap
    local PH_FONT  = 38   -- card height
    local PG_FONT  = 4    -- vertical gap between rows
    local COL_GAP  = 4    -- horizontal gap between columns
    local CARD_W   = math.floor((SETTINGS_CW - COL_GAP) / 2)
    local fontPickerBtns = {}
    local _wowCb_sn
    local _refreshLSM_sn   -- LSM dropdown closed-state refresh (ALL-41)

    local function HLStickyFonts()
        -- No override (WoW Default unticked, nothing else picked) always shows Noto
        -- Serif highlighted, regardless of what was selected before. Under another
        -- font set (ALL-14) a font from a different set counts as none.
        local cur = BNB.ResolveFontID(cfg.fontID) or BNB.GetFontSetDefault()
        for _, e in ipairs(fontPickerBtns) do
            local sel = (e.id == cur)
            if e.btn.SetBackdropColor then
                if sel then e.btn:SetBackdropColor(0.12,0.18,0.12,0.95); e.btn:SetBackdropBorderColor(0.4,0.8,0.4,1)
                else        e.btn:SetBackdropColor(0.06,0.06,0.08,0.95); e.btn:SetBackdropBorderColor(0.28,0.28,0.30,1) end
            end
            if e.nameLbl then e.nameLbl:SetTextColor(sel and 1 or 0.85, sel and 0.82 or 0.85, sel and 0 or 0.85, 1) end
        end
        if _wowCb_sn then _wowCb_sn:SetChecked(cur == "wow") end
        if _refreshLSM_sn then _refreshLSM_sn() end
    end

    -- WoW Default has its own checkbox below the grid, not a 9th card, and LSM
    -- fonts are in a dropdown below that (ALL-41), as on the Appearance tab. Cards
    -- are the active language's font set (ALL-14).
    local fonts = BNB.GetPickerFonts()
    for i, def in ipairs(fonts) do
        local fid  = def.id
        local col  = (i - 1) % 2          -- 0 = left, 1 = right
        local gridRow = math.floor((i - 1) / 2)
        local xOff = col * (CARD_W + COL_GAP)
        local yOff = ct1._y - gridRow * (PH_FONT + PG_FONT)

        local btn = BNB.CreateBackdropFrame("Button", nil, ct1)
        BNB.SetBackdrop(btn, 0.06,0.06,0.08,0.95, 0.28,0.28,0.30,1)
        btn:SetSize(CARD_W, PH_FONT)
        btn:SetPoint("TOPLEFT", ct1, "TOPLEFT", xOff, yOff)
        btn:EnableMouse(true)
        btn:SetScript("OnEnter", function(s)
            if cfg.fontID ~= fid then
                s:SetBackdropColor(0.10,0.12,0.10,0.95); s:SetBackdropBorderColor(0.35,0.55,0.35,1)
            end
        end)
        btn:SetScript("OnLeave", HLStickyFonts)
        btn:SetScript("OnClick", function()
            cfg.fontID = fid; SaveCfg(noteID, cfg)
            if stickyFrame then ApplyConfig(stickyFrame, noteID) end
            HLStickyFonts()
        end)
        local nameLbl = btn:CreateFontString(nil, "OVERLAY")
        nameLbl:SetPoint("TOPLEFT",  btn, "TOPLEFT",  5, -5)
        nameLbl:SetPoint("TOPRIGHT", btn, "TOPRIGHT", -5, -5)
        nameLbl:SetJustifyH("LEFT"); nameLbl:SetHeight(16)
        BNB.SetFontSafe(nameLbl, def.bold, 11, "GameFontNormal")
        nameLbl:SetText(def.label)
        local prevLbl = btn:CreateFontString(nil, "OVERLAY")
        prevLbl:SetPoint("BOTTOMLEFT",  btn, "BOTTOMLEFT",  5, 5)
        prevLbl:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -5, 5)
        prevLbl:SetJustifyH("LEFT"); prevLbl:SetHeight(12)
        BNB.SetFontSafe(prevLbl, def.regular, 10, "GameFontNormalSmall")
        prevLbl:SetTextColor(0.55, 0.55, 0.55); prevLbl:SetText(def.preview or "")
        fontPickerBtns[#fontPickerBtns+1] = {btn=btn, id=fid, nameLbl=nameLbl, prevLbl=prevLbl, def=def}
        plainOnlyWidgets[#plainOnlyWidgets+1] = btn
    end
    -- Advance _y past the grid (ceil rows, since fonts may be odd count). It always
    -- reserves its 4 rows; free rows carry the font pack hint.
    local usedRows = math.ceil(#fonts / 2)
    local gridRows = math.max(BNB.FONT_GRID_ROWS, usedRows)
    local packHint = BNB.AddFontPackHint(ct1, ct1, 0, ct1._y - usedRows * (PH_FONT + PG_FONT),
        SETTINGS_CW, (gridRows - usedRows) * (PH_FONT + PG_FONT) - PG_FONT)
    if packHint then plainOnlyWidgets[#plainOnlyWidgets + 1] = packHint end
    ct1._y = ct1._y - gridRows * (PH_FONT + PG_FONT) + PG_FONT

    -- WoW Default checkbox, below the grid instead of a 9th card. Latin set only;
    -- its row is kept either way.
    do
        local wowCb = CreateFrame("CheckButton", nil, ct1, "UICheckButtonTemplate")
        wowCb:SetSize(20, 20)
        wowCb:SetPoint("TOPLEFT", ct1, "TOPLEFT", -2, ct1._y)
        local wowLbl = ct1:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        wowLbl:SetPoint("LEFT",  wowCb, "RIGHT", 4, 0)
        wowLbl:SetPoint("RIGHT", ct1,   "RIGHT", 0, 0)
        wowLbl:SetJustifyH("LEFT")
        wowLbl:SetText(L["FONT_USE_WOW_DEFAULT"])
        wowCb:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(L["FONT_USE_WOW_DEFAULT_TIP"], 0.8, 0.8, 0.8, true)
            GameTooltip:Show()
        end)
        wowCb:SetScript("OnLeave", function() GameTooltip:Hide() end)
        wowCb:SetScript("OnClick", function(self)
            cfg.fontID = self:GetChecked() and "wow" or nil
            SaveCfg(noteID, cfg)
            if stickyFrame then ApplyConfig(stickyFrame, noteID) end
            HLStickyFonts()
        end)
        _wowCb_sn = wowCb
        if not BNB.ShowWoWFontCheckbox() then wowCb:Hide(); wowLbl:Hide() end
        plainOnlyWidgets[#plainOnlyWidgets + 1] = wowCb
        plainOnlyWidgets[#plainOnlyWidgets + 1] = wowLbl
        ct1._y = ct1._y - 24
    end

    -- LSM font dropdown (ALL-41): only built when lsmFonts is on and LSM has fonts.
    if BNB._BuildLSMFontDropdown then
        local y, refresh, hdr, ctrl = BNB._BuildLSMFontDropdown(ct1, ct1._y,
            function()
                local def = cfg.fontID and BNB.GetFontDef(cfg.fontID)
                return (def and def._isLSM and cfg.fontID == def.id) and cfg.fontID or nil
            end,
            function(path)
                cfg.fontID = path; SaveCfg(noteID, cfg)
                if stickyFrame then ApplyConfig(stickyFrame, noteID) end
                HLStickyFonts()
            end,
            SETTINGS_CW)
        if ctrl then
            ct1._y = y - 4
            _refreshLSM_sn = refresh
            plainOnlyWidgets[#plainOnlyWidgets + 1] = hdr
            plainOnlyWidgets[#plainOnlyWidgets + 1] = ctrl
        end
    end

    HLStickyFonts()

    local fontSizeSl = MakeSlider(ct1, L["STICKY_FONT_SIZE"], 8, 24,
        cfg.fontSize or (BigNoteBoxDB and BigNoteBoxDB.fontSize) or 13,
        function(v)
            cfg.fontSize = v; SaveCfg(noteID, cfg)
            if stickyFrame and stickyFrame._bodyEb then
                local path = select(1, stickyFrame._bodyEb:GetFont())
                if path then pcall(function() stickyFrame._bodyEb:SetFont(path, v, "") end) end
            end
        end)
    plainOnlyWidgets[#plainOnlyWidgets+1] = fontSizeSl

    Rule(ct1)
    Hdr(ct1, L["STICKY_TEXT_STYLE"])

    -- Line height
    local LH_STICKY = {
        {key="1.0",label="1.0 (default)"},{key="1.25",label="1.25"},
        {key="1.5",label="1.5"},{key="1.75",label="1.75"},{key="2.0",label="2.0"},
    }
    local function StickyLHLabel()
        local cur = cfg.lineHeight or "1.0"
        for _,m in ipairs(LH_STICKY) do if m.key==cur then return m.label end end
        return LH_STICKY[1].label
    end
    local function ApplyStickyLH(val)
        cfg.lineHeight = val; SaveCfg(noteID, cfg)
    end

    SubLbl(ct1, L["STICKY_LINE_HEIGHT_LABEL"])
    local useNativeLH = C_XMLUtil and C_XMLUtil.GetTemplateInfo
        and C_XMLUtil.GetTemplateInfo("WowStyle1DropdownTemplate")
    if useNativeLH then
        local lhSDD = CreateFrame("DropdownButton", nil, ct1, "WowStyle1DropdownTemplate")
        lhSDD:SetPoint("TOPLEFT", ct1, "TOPLEFT", 0, ct1._y)
        lhSDD:SetWidth(SETTINGS_CW)
        lhSDD:SetupMenu(function(_, root)
            for _, m in ipairs(LH_STICKY) do
                local key = m.key
                root:CreateRadio(m.label,
                    function() return (cfg.lineHeight or "1.0") == key end,
                    function()
                        lhSDD:GenerateMenu()
                        ApplyStickyLH(key)
                    end)
            end
        end)
        ct1._y = ct1._y - 36
        plainOnlyWidgets[#plainOnlyWidgets+1] = lhSDD
    else
        local lhSBtn = BNB.CreateButton(nil, ct1, StickyLHLabel(), SETTINGS_CW, 22)
        lhSBtn:SetPoint("TOPLEFT", ct1, "TOPLEFT", 0, ct1._y)
        lhSBtn:SetScript("OnClick", function(self)
            local cur = cfg.lineHeight or "1.0"
            local idx = 1
            for i, m in ipairs(LH_STICKY) do if m.key==cur then idx=i;break end end
            idx = (idx % #LH_STICKY) + 1
            ApplyStickyLH(LH_STICKY[idx].key)
            self:SetText(StickyLHLabel())
        end)
        ct1._y = ct1._y - 28
        plainOnlyWidgets[#plainOnlyWidgets+1] = lhSBtn
    end

    -- Text alignment
    SubLbl(ct1, L["STICKY_TEXT_ALIGN_LABEL"])
    -- ALIGN_KEYS holds the WoW native justify constants that cfg.textAlign is actually
    -- saved as (unaffected by locale); ALIGN_LABELS is the translatable display text,
    -- looked up by that same key. Keeping these separate (unlike the old single
    -- display-string-doubles-as-key array) means a translated label can never break
    -- the saved value or the ALIGN_MAP lookup.
    local ALIGN_KEYS   = { "LEFT", "CENTER", "RIGHT" }
    local ALIGN_LABELS = { LEFT = L["STICKY_ALIGN_LEFT"], CENTER = L["STICKY_ALIGN_CENTER"], RIGHT = L["STICKY_ALIGN_RIGHT"] }
    local function GetAlignLabel() return ALIGN_LABELS[cfg.textAlign or "LEFT"] or ALIGN_LABELS.LEFT end
    local useNativeAlign = useNativeLH
    if useNativeAlign then
        local alignDD = CreateFrame("DropdownButton", nil, ct1, "WowStyle1DropdownTemplate")
        alignDD:SetPoint("TOPLEFT", ct1, "TOPLEFT", 0, ct1._y)
        alignDD:SetWidth(SETTINGS_CW)
        alignDD:SetupMenu(function(_, root)
            for _, key in ipairs(ALIGN_KEYS) do
                local k = key
                root:CreateRadio(ALIGN_LABELS[k],
                    function() return (cfg.textAlign or "LEFT") == k end,
                    function()
                        cfg.textAlign = k; SaveCfg(noteID, cfg)
                        alignDD:GenerateMenu()
                        if stickyFrame and stickyFrame._bodyEb then
                            pcall(function() stickyFrame._bodyEb:SetJustifyH(k) end)
                        end
                    end)
            end
        end)
        ct1._y = ct1._y - 36
        plainOnlyWidgets[#plainOnlyWidgets+1] = alignDD
    else
        local alignBtn = BNB.CreateButton(nil, ct1, GetAlignLabel(), SETTINGS_CW, 22)
        alignBtn:SetPoint("TOPLEFT", ct1, "TOPLEFT", 0, ct1._y)
        alignBtn:SetScript("OnClick", function(self)
            local cur = cfg.textAlign or "LEFT"
            local idx = 1
            for i, k in ipairs(ALIGN_KEYS) do if k == cur then idx = i; break end end
            idx = (idx % #ALIGN_KEYS) + 1
            local key = ALIGN_KEYS[idx]
            cfg.textAlign = key; SaveCfg(noteID, cfg)
            self:SetText(ALIGN_LABELS[key])
            if stickyFrame and stickyFrame._bodyEb then
                pcall(function() stickyFrame._bodyEb:SetJustifyH(key) end)
            end
        end)
        ct1._y = ct1._y - 28
        plainOnlyWidgets[#plainOnlyWidgets+1] = alignBtn
    end

    -- Font outline
    SubLbl(ct1, L["STICKY_FONT_OUTLINE_LABEL"])
    local function GetOutlineLabel() return cfg.fontOutline or "None" end
    local useNativeOutline = useNativeLH
    if useNativeOutline then
        local outlineDD = CreateFrame("DropdownButton", nil, ct1, "WowStyle1DropdownTemplate")
        outlineDD:SetPoint("TOPLEFT", ct1, "TOPLEFT", 0, ct1._y)
        outlineDD:SetWidth(SETTINGS_CW)
        outlineDD:SetupMenu(function(_, root)
            for _, opt in ipairs(OUTLINE_OPTIONS) do
                local o = opt
                root:CreateRadio(BNB.AdvancedMode.OutlineLabel(o),
                    function() return GetOutlineLabel() == o end,
                    function()
                        cfg.fontOutline = o; SaveCfg(noteID, cfg)
                        outlineDD:GenerateMenu()
                        if stickyFrame then ApplyOutlineToEditBox(stickyFrame._bodyEb, o) end
                    end)
            end
        end)
        ct1._y = ct1._y - 36
        plainOnlyWidgets[#plainOnlyWidgets+1] = outlineDD
    else
        local outlineBtn = BNB.CreateButton(nil, ct1,
            BNB.AdvancedMode.OutlineLabel(GetOutlineLabel()), SETTINGS_CW, 22)
        outlineBtn:SetPoint("TOPLEFT", ct1, "TOPLEFT", 0, ct1._y)
        outlineBtn:SetScript("OnClick", function(self)
            local cur = GetOutlineLabel()
            local idx = 1
            for i, o in ipairs(OUTLINE_OPTIONS) do if o == cur then idx = i; break end end
            idx = (idx % #OUTLINE_OPTIONS) + 1
            local opt = OUTLINE_OPTIONS[idx]
            cfg.fontOutline = opt; SaveCfg(noteID, cfg)
            self:SetText(BNB.AdvancedMode.OutlineLabel(opt))
            if stickyFrame then ApplyOutlineToEditBox(stickyFrame._bodyEb, opt) end
        end)
        ct1._y = ct1._y - 28
        plainOnlyWidgets[#plainOnlyWidgets+1] = outlineBtn
    end

    FinalisePanel(ct1, sf1)

    -- ══════════════════════════════════════════════════════════════════════════
    -- TAB 2 — APPEARANCE
    -- ══════════════════════════════════════════════════════════════════════════
    ct2._y = -8

    -- ── Randomize colors ─────────────────────────────────────────────────────
    -- Picks a random background from a curated palette of warm/cool note colors,
    -- then picks a contrasting text color (light on dark bg, dark on light bg).
    local BG_PALETTE = {
        {0.96, 0.91, 0.68},  -- parchment yellow
        {0.72, 0.85, 0.72},  -- sage green
        {0.70, 0.82, 0.92},  -- sky blue
        {0.90, 0.75, 0.82},  -- dusty rose
        {0.82, 0.78, 0.92},  -- lavender
        {0.92, 0.78, 0.68},  -- terracotta
        {0.68, 0.82, 0.85},  -- seafoam
        {0.95, 0.88, 0.75},  -- warm cream
        {0.75, 0.88, 0.95},  -- ice blue
        {0.88, 0.95, 0.78},  -- lime cream
        {0.20, 0.22, 0.28},  -- dark slate
        {0.14, 0.20, 0.14},  -- dark forest
        {0.18, 0.14, 0.22},  -- dark purple
        {0.22, 0.16, 0.12},  -- dark espresso
    }

    local randBtn = BNB.CreateButton(nil, ct2,
        L["STICKY_RANDOMIZE_COLORS_BTN"], SETTINGS_CW, 26)
    randBtn:SetPoint("TOPLEFT", ct2, "TOPLEFT", 0, ct2._y)
    randBtn:SetScript("OnClick", function()
        local bg = BG_PALETTE[math.random(#BG_PALETTE)]
        local br, bg2, bb = bg[1], bg[2], bg[3]
        -- Luminance check: pick contrasting text
        local lum = 0.299 * br + 0.587 * bg2 + 0.114 * bb
        local tr, tg, tb
        if lum > 0.5 then
            -- Light bg: dark warm text
            tr = math.random(5, 25) / 100
            tg = math.random(5, 20) / 100
            tb = math.random(5, 15) / 100
        else
            -- Dark bg: light warm text
            tr = math.random(75, 95) / 100
            tg = math.random(70, 90) / 100
            tb = math.random(60, 80) / 100
        end
        cfg.bgR, cfg.bgG, cfg.bgB = br, bg2, bb
        cfg.textR, cfg.textG, cfg.textB = tr, tg, tb
        SaveCfg(noteID, cfg)
        if stickyFrame then
            ApplyConfig(stickyFrame, noteID)
            if stickyFrame._bodyEb then
                pcall(function() stickyFrame._bodyEb:SetTextColor(tr, tg, tb) end)
            end
        end
        -- Repopulate so the color swatches update to reflect new values
        PopulateStickySettings(noteID)
        if f._selectTab then f._selectTab(2) end  -- stay on Appearance tab
    end)
    ct2._y = ct2._y - 32

    Rule(ct2)
    Sec(ct2, "Background")
    local bgSwatch = ColorBtn(ct2, cfg.bgR, cfg.bgG, cfg.bgB, L["STICKY_CLICK_PICK_COLOR"], function(r,g,b)
        cfg.bgR, cfg.bgG, cfg.bgB = r, g, b
        SaveCfg(noteID, cfg)
        if stickyFrame then ApplyConfig(stickyFrame, noteID) end
    end)
    SubLbl(ct2, L["STICKY_QUICK_PICK_LABEL"])
    ColorGrid(ct2, function(r,g,b)
        cfg.bgR, cfg.bgG, cfg.bgB = r, g, b
        SaveCfg(noteID, cfg)
        if stickyFrame then ApplyConfig(stickyFrame, noteID) end
        if bgSwatch and bgSwatch._tx then bgSwatch._tx:SetColorTexture(r, g, b) end
    end)

    -- ── Background texture picker ─────────────────────────────────────────────
    -- Forward-declared so the dropdown/button closure can reference it before
    -- the slider is built (same Lua 5.1 upvalue pattern as SyncBorderSliders).
    local SyncColorizeSlider

    SubLbl(ct2, L["STICKY_BG_TEXTURE_LABEL"])
    local curTexKey   = cfg.bgTexture or "none"
    local curTexLabel = BgTextureLabel(curTexKey)

    local useNativeTexDrop = C_XMLUtil and C_XMLUtil.GetTemplateInfo
        and C_XMLUtil.GetTemplateInfo("WowStyle1DropdownTemplate")
    if useNativeTexDrop then
        local texDrop = CreateFrame("DropdownButton", nil, ct2, "WowStyle1DropdownTemplate")
        texDrop:SetPoint("TOPLEFT", ct2, "TOPLEFT", 0, ct2._y)
        texDrop:SetWidth(SETTINGS_CW)
        texDrop:SetupMenu(function(_, root)
            for _, t in ipairs(BG_TEXTURES) do
                local entry = t
                root:CreateRadio(entry.label,
                    function() return curTexKey == entry.key end,
                    function()
                        curTexKey   = entry.key
                        curTexLabel = entry.label
                        cfg.bgTexture = curTexKey
                        SaveCfg(noteID, cfg)
                        texDrop:GenerateMenu()
                        if stickyFrame then ApplyConfig(stickyFrame, noteID) end
                        SyncColorizeSlider(curTexKey)
                    end)
            end
        end)
        ct2._y = ct2._y - 36
    else
        -- Fallback: cycle button
        local texBtn = BNB.CreateButton(nil, ct2, curTexLabel, SETTINGS_CW, 22)
        texBtn:SetPoint("TOPLEFT", ct2, "TOPLEFT", 0, ct2._y)
        texBtn:SetScript("OnClick", function(self)
            local idx = 1
            for i, t in ipairs(BG_TEXTURES) do
                if t.key == curTexKey then idx = i; break end
            end
            idx = (idx % #BG_TEXTURES) + 1
            curTexKey   = BG_TEXTURES[idx].key
            curTexLabel = BG_TEXTURES[idx].label
            self:SetText(curTexLabel)
            cfg.bgTexture = curTexKey
            SaveCfg(noteID, cfg)
            if stickyFrame then ApplyConfig(stickyFrame, noteID) end
            SyncColorizeSlider(curTexKey)
        end)
        ct2._y = ct2._y - 28
    end

    -- "Colorize texture %" — lerps the backdrop tint between raw paper (0%, white
    -- tint) and the full chosen colour (100%). Greyed out when texture is "None".
    local slColorize = MakeSlider(ct2, L["STICKY_COLORIZE_TEXTURE_PCT"], 0, 100,
        math.floor((cfg.bgColorOpacity or 1.0) * 100),
        function(v)
            cfg.bgColorOpacity = v / 100
            SaveCfg(noteID, cfg)
            if stickyFrame then ApplyConfig(stickyFrame, noteID) end
        end)

    SyncColorizeSlider = function(texKey)
        local disabled = (not texKey or texKey == "none")
        pcall(function() slColorize:SetAlpha(disabled and 0.4 or 1.0) end)
        if slColorize.SetEnabled then
            pcall(function() slColorize:SetEnabled(not disabled) end)
        end
    end
    SyncColorizeSlider(curTexKey)

    Rule(ct2)
    Sec(ct2, L["STICKY_OPACITY_SECTION"])
    local textOpacitySl = MakeSlider(ct2, L["STICKY_TEXT_OPACITY_PCT"], 10, 100,
        math.floor((cfg.textAlpha or 1.0) * 100),
        function(v)
            cfg.textAlpha = v/100; SaveCfg(noteID, cfg)
            if stickyFrame and stickyFrame._bodyEb then
                pcall(function() stickyFrame._bodyEb:SetAlpha(cfg.textAlpha) end)
            end
        end)
    plainOnlyWidgets[#plainOnlyWidgets+1] = textOpacitySl
    MakeSlider(ct2, L["STICKY_BG_OPACITY_PCT"], 0, 100,
        math.floor((cfg.alpha or 0.96) * 100),
        function(v)
            cfg.alpha = v/100; SaveCfg(noteID, cfg)
            if stickyFrame then ApplyBgAlpha(stickyFrame, cfg.alpha) end
        end)

    Rule(ct2)
    Sec(ct2, "Border")
    -- Forward declaration so the dropdown/button closures below can reference it
    -- before the function body is assigned (Lua 5.1 upvalue capture fix).
    local SyncBorderSliders
    local useNativeDrop = C_XMLUtil and C_XMLUtil.GetTemplateInfo
        and C_XMLUtil.GetTemplateInfo("WowStyle1DropdownTemplate")
    if useNativeDrop then
        local curBorder = cfg.borderName or "None"
        local bdd = CreateFrame("DropdownButton", nil, ct2, "WowStyle1DropdownTemplate")
        bdd:SetPoint("TOPLEFT", ct2, "TOPLEFT", 0, ct2._y)
        bdd:SetWidth(SETTINGS_CW)
        bdd:SetupMenu(function(_, root)
            for _, name in ipairs(GetBorderList()) do
                local n = name
                root:CreateRadio(n,
                    function() return curBorder == n end,
                    function()
                        curBorder = n
                        cfg.borderName = n
                        SaveCfg(noteID, cfg)
                        bdd:GenerateMenu()
                        if stickyFrame then ApplyConfig(stickyFrame, noteID) end
                        SyncBorderSliders(n)
                    end)
            end
        end)
        ct2._y = ct2._y - 36
    else
        local curBorder = cfg.borderName or "None"
        local bBtn = BNB.CreateButton(nil, ct2, curBorder, SETTINGS_CW, 22)
        bBtn:SetPoint("TOPLEFT", ct2, "TOPLEFT", 0, ct2._y)
        bBtn:SetScript("OnClick", function(self)
            local borders = GetBorderList()
            local idx2 = 1
            for i2, v2 in ipairs(borders) do if v2 == curBorder then idx2 = i2; break end end
            idx2 = (idx2 % #borders) + 1
            curBorder = borders[idx2]
            self:SetText(curBorder)
            cfg.borderName = curBorder
            SaveCfg(noteID, cfg)
            if stickyFrame then ApplyConfig(stickyFrame, noteID) end
            SyncBorderSliders(curBorder)
        end)
        ct2._y = ct2._y - 28
    end

    -- Border Thickness slider
    local slThickness = MakeSlider(ct2, L["STICKY_BORDER_THICKNESS_PCT"], 1, 200, cfg.borderScale or 100,
        function(v)
            cfg.borderScale = math.floor(v)
            SaveCfg(noteID, cfg)
            if stickyFrame then ApplyConfig(stickyFrame, noteID) end
        end)

    -- Border Offset slider
    local slOffset = MakeSlider(ct2, L["STICKY_BORDER_OFFSET_PX"], 0, 12, cfg.borderOffset or 2,
        function(v)
            cfg.borderOffset = math.floor(v)
            SaveCfg(noteID, cfg)
            if stickyFrame then ApplyConfig(stickyFrame, noteID) end
        end)

    -- Border Brightness slider
    local slBrightness = MakeSlider(ct2, "Border brightness %", 10, 500, cfg.borderBrightness or 100,
        function(v)
            cfg.borderBrightness = math.floor(v)
            SaveCfg(noteID, cfg)
            if stickyFrame then ApplyConfig(stickyFrame, noteID) end
        end)

    -- Grey out the three sliders when border is "None" (they have no effect).
    -- Assigned here (after sliders exist) but captured by the closures above
    -- via the forward declaration at the top of the Border section.
    SyncBorderSliders = function(borderName)
        local disabled = (not borderName or borderName == "None")
        local a = disabled and 0.35 or 1.0
        for _, sl in ipairs({ slThickness, slOffset, slBrightness }) do
            if sl then
                sl:SetAlpha(a)
                sl:EnableMouse(not disabled)
                sl:EnableMouseWheel(not disabled)
            end
        end
    end
    SyncBorderSliders(cfg.borderName)

    FinalisePanel(ct2, sf2)

    -- Apply greying to all plain-only controls now that both tabs are fully built.
    -- (Must run after tab 2 so textOpacitySl is in plainOnlyWidgets.)
    SyncPlainOnlyControls()

    -- ══════════════════════════════════════════════════════════════════════════
    -- TAB 3 — SITUATION
    -- Mirror of NoteConfig TAB 3. Reads/writes the same note fields.
    -- Cross-sync: any save here calls BNB.SyncNoteConfig(noteID) so the
    -- NoteConfig Situation tab (if open for the same note) refreshes too.
    -- ══════════════════════════════════════════════════════════════════════════
    ct3._y = -8

    local SIT_PAD = 0   -- content already offset by scroll panel SETTINGS_PAD
    local SIT_CW  = SETTINGS_CW

    -- ── Layout helpers (local to Situation tab) ───────────────────────────────
    local function SitHdr(txt)
        local y = ct3._y
        local l = ct3:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        l:SetPoint("TOPLEFT", ct3, "TOPLEFT", SIT_PAD, y)
        l:SetTextColor(1, 0.82, 0, 1); l:SetText(txt)
        ct3._y = y - 20
    end
    local function SitRule()
        local y = ct3._y
        local t = ct3:CreateTexture(nil, "ARTWORK")
        t:SetHeight(1)
        t:SetPoint("TOPLEFT",  ct3, "TOPLEFT",  SIT_PAD, y)
        t:SetPoint("TOPRIGHT", ct3, "TOPRIGHT", 0, y)
        if skinMode and BNB.GetSkinPreset then
            local p = BNB.GetSkinPreset()
            local br, bg_, bb = BNB.SkinBorderOf(p)
            t:SetColorTexture(br, bg_, bb, 0.8)
            BNB.RegisterSkinRule(t, 0.8)
        else
            t:SetColorTexture(0.28, 0.28, 0.30, 0.8)
        end
        ct3._y = y - 8
    end

    -- Forward-declare so closures below can capture it before assignment
    local SitSelectType
    local SitHideAC
    local SitRefreshCurBind
    local SitRefreshWaypointDisplay

    -- ── Header ────────────────────────────────────────────────────────────────
    SitHdr(L["STICKY_CONTEXTUAL_BINDING_HDR"])
    local sitDesc = ct3:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    sitDesc:SetPoint("TOPLEFT",  ct3, "TOPLEFT",  SIT_PAD, ct3._y)
    sitDesc:SetPoint("TOPRIGHT", ct3, "TOPRIGHT", 0, ct3._y)
    sitDesc:SetTextColor(0.60, 0.60, 0.60)
    sitDesc:SetText(L["STICKY_SIT_DESC"])
    sitDesc:SetJustifyH("LEFT"); sitDesc:SetWordWrap(true)
    ct3._y = ct3._y - 36
    SitRule()

    -- ── Helpers ───────────────────────────────────────────────────────────────
    local function SitSave(fields)
        BNB.UpdateNote(noteID, fields)
        if BNB.RefreshNoteList then BNB.RefreshNoteList() end
        if BNB.Sticky and BNB.Sticky.RefreshNote then BNB.Sticky.RefreshNote(noteID) end
        -- Cross-sync: refresh NoteConfig Situation tab if open for same note
        if BNB.SyncNoteConfig then BNB.SyncNoteConfig(noteID) end
    end

    -- ── Bind-type dropdown ────────────────────────────────────────────────────
    local SIT_TYPES       = { "none", "zone", "subzone", "instance", "player" }
    local SIT_TYPE_LABELS = { L["TASK_CTX_SIT_NONE"], L["STICKY_KIND_ZONE"], L["STICKY_KIND_SUBZONE"], L["STICKY_KIND_INSTANCE"], L["STICKY_KIND_PLAYER"] }
    local sitSelType      = "none"

    local function SitGetTypeLabel(t)
        for i, k in ipairs(SIT_TYPES) do if k == t then return SIT_TYPE_LABELS[i] end end
        return SIT_TYPE_LABELS[1]
    end

    local sitTypeDropdown
    local sitTypeCycleBtn

    local function SitSetTypeText(label)
        if sitTypeDropdown and sitTypeDropdown.Text then sitTypeDropdown.Text:SetText(label) end
        if sitTypeCycleBtn then sitTypeCycleBtn:SetText(label) end
    end

    local useNativeSit3 = C_XMLUtil and C_XMLUtil.GetTemplateInfo
        and C_XMLUtil.GetTemplateInfo("WowStyle1DropdownTemplate")

    if useNativeSit3 then
        sitTypeDropdown = CreateFrame("DropdownButton", "BNBStickySetSituTypeDD", ct3,
            "WowStyle1DropdownTemplate")
        sitTypeDropdown:SetPoint("TOPLEFT",  ct3, "TOPLEFT",  SIT_PAD, ct3._y)
        sitTypeDropdown:SetPoint("TOPRIGHT", ct3, "TOPRIGHT", 0, ct3._y)
        sitTypeDropdown:SetHeight(24)
        local function RebuildSitTypeMenu()
            sitTypeDropdown:SetupMenu(function(_, root)
                for i, label in ipairs(SIT_TYPE_LABELS) do
                    local key = SIT_TYPES[i]
                    root:CreateRadio(label,
                        function() return sitSelType == key end,
                        function()
                            sitSelType = key
                            sitTypeDropdown:GenerateMenu()
                            SitSelectType(key)
                        end)
                end
            end)
        end
        RebuildSitTypeMenu()
        ct3._sitRebuildTypeMenu = RebuildSitTypeMenu
    else
        sitTypeCycleBtn = BNB.CreateButton(nil, ct3, SitGetTypeLabel(sitSelType), SIT_CW, 24)
        sitTypeCycleBtn:SetPoint("TOPLEFT", ct3, "TOPLEFT", SIT_PAD, ct3._y)
        sitTypeCycleBtn:SetScript("OnClick", function(self)
            local idx = 1
            for i, k in ipairs(SIT_TYPES) do if k == sitSelType then idx = i; break end end
            idx = (idx % #SIT_TYPES) + 1
            sitSelType = SIT_TYPES[idx]
            self:SetText(SIT_TYPE_LABELS[idx])
            SitSelectType(sitSelType)
        end)
    end
    ct3._y = ct3._y - 30

    -- ── Value row ─────────────────────────────────────────────────────────────
    local sitValueRow = CreateFrame("Frame", nil, ct3)
    sitValueRow:SetPoint("TOPLEFT",  ct3, "TOPLEFT",  SIT_PAD, ct3._y)
    sitValueRow:SetPoint("TOPRIGHT", ct3, "TOPRIGHT", 0, ct3._y)
    sitValueRow:SetHeight(28); sitValueRow:Hide()

    local sitValueLbl = sitValueRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    sitValueLbl:SetPoint("LEFT", sitValueRow, "LEFT", 0, 0)
    sitValueLbl:SetWidth(65); sitValueLbl:SetJustifyH("LEFT")
    sitValueLbl:SetTextColor(0.78, 0.78, 0.78); sitValueLbl:SetText(L["STICKY_SIT_VALUE_LABEL"])

    local sitValueEb = CreateFrame("EditBox", nil, sitValueRow,
        "BackdropTemplate")
    BNB.EnsureBackdrop(sitValueEb)
    sitValueEb:SetPoint("LEFT",  sitValueLbl, "RIGHT", 6, 0)
    sitValueEb:SetPoint("RIGHT", sitValueRow, "RIGHT", -26, 0)
    sitValueEb:SetHeight(20); sitValueEb:SetFontObject("GameFontNormal")
    sitValueEb:SetAutoFocus(false); sitValueEb:SetMaxLetters(128)
    sitValueEb:SetTextInsets(4, 4, 0, 0); sitValueEb:SetTextColor(1, 1, 1)
    BNB.SetBackdropDark(sitValueEb)
    sitValueEb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

    local ASSETS3 = "Interface\\AddOns\\BigNoteBox\\Assets\\"
    local sitBrowseBtn = CreateFrame("Button", nil, sitValueRow)
    sitBrowseBtn:SetSize(20, 20)
    sitBrowseBtn:SetPoint("RIGHT", sitValueRow, "RIGHT", 0, 0)
    local sitBrowseTx = sitBrowseBtn:CreateTexture(nil, "ARTWORK")
    sitBrowseTx:SetAllPoints(); sitBrowseTx:SetTexture(ASSETS3 .. "Overlay\\ov-situation")
    sitBrowseBtn:SetScript("OnEnter", function(self)
        self:SetAlpha(1.0)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(L["STICKY_SIT_BROWSE_TIP_TITLE"], 1, 1, 1)
        GameTooltip:AddLine(L["STICKY_SIT_BROWSE_TIP_BODY"], 0.78, 0.78, 0.78)
        GameTooltip:Show()
    end)
    sitBrowseBtn:SetScript("OnLeave", function(self)
        self:SetAlpha(0.7); GameTooltip:Hide()
    end)
    sitBrowseBtn:SetAlpha(0.7); sitBrowseBtn:Hide()

    -- ── Autocomplete ──────────────────────────────────────────────────────────
    local sitAcFrame = BNB.CreateBackdropFrame("Frame", nil, ct3)
    BNB.SetBackdrop(sitAcFrame, 0.08, 0.08, 0.10, 0.97, 0.35, 0.35, 0.38, 1)
    sitAcFrame:SetPoint("TOPLEFT",  sitValueRow, "BOTTOMLEFT",  0, -2)
    sitAcFrame:SetPoint("TOPRIGHT", sitValueRow, "BOTTOMRIGHT", 0, -2)
    sitAcFrame:SetFrameLevel(ct3:GetFrameLevel() + 30)
    sitAcFrame:Hide()

    local _sitAcRows  = {}
    local _sitAcTimer = nil

    SitHideAC = function()
        sitAcFrame:Hide()
        if _sitAcTimer then _sitAcTimer:Cancel(); _sitAcTimer = nil end
    end

    local function SitShowAC(matches)
        if #matches == 0 then SitHideAC(); return end
        local ROW_H_AC = 22
        local maxRows  = math.min(#matches, 7)
        sitAcFrame:SetHeight(maxRows * ROW_H_AC + 4)
        for i = 1, maxRows do
            if not _sitAcRows[i] then
                local row = CreateFrame("Button", nil, sitAcFrame)
                row:SetHeight(ROW_H_AC)
                row:SetPoint("TOPLEFT",  sitAcFrame, "TOPLEFT",  4, -2 - (i-1)*ROW_H_AC)
                row:SetPoint("TOPRIGHT", sitAcFrame, "TOPRIGHT", -4, -2 - (i-1)*ROW_H_AC)
                local hi = row:CreateTexture(nil, "HIGHLIGHT")
                hi:SetAllPoints(); hi:SetColorTexture(1, 1, 1, 0.08)
                local nameLbl = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                nameLbl:SetPoint("LEFT",  row, "LEFT",  4, 0)
                nameLbl:SetPoint("RIGHT", row, "RIGHT", -80, 0)
                nameLbl:SetJustifyH("LEFT"); nameLbl:SetMaxLines(1)
                nameLbl:SetTextColor(1, 1, 1)
                row._nameLbl = nameLbl
                local contLbl = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                contLbl:SetPoint("RIGHT", row, "RIGHT", -4, 0)
                contLbl:SetWidth(76); contLbl:SetJustifyH("RIGHT"); contLbl:SetMaxLines(1)
                contLbl:SetTextColor(0.50, 0.50, 0.50)
                row._contLbl = contLbl
                _sitAcRows[i] = row
            end
            local row = _sitAcRows[i]; local m = matches[i]
            row._nameLbl:SetText(m.name); row._contLbl:SetText(m.continent or "")
            row:SetPoint("TOPLEFT",  sitAcFrame, "TOPLEFT",  4, -2 - (i-1)*ROW_H_AC)
            row:SetPoint("TOPRIGHT", sitAcFrame, "TOPRIGHT", -4, -2 - (i-1)*ROW_H_AC)
            local capName = m.name
            row:SetScript("OnClick", function() sitValueEb:SetText(capName); SitHideAC(); sitValueEb:SetFocus() end)
            row:Show()
        end
        for i = maxRows + 1, #_sitAcRows do _sitAcRows[i]:Hide() end
        sitAcFrame:Show()
    end

    sitValueEb:SetScript("OnTextChanged", function(self, userInput)
        if not userInput then return end
        local text = self:GetText() or ""
        if #text < 2 then SitHideAC(); return end
        if BNB.ZonePicker and BNB.ZonePicker.IsShown and BNB.ZonePicker.IsShown() then
            BNB.ZonePicker.Close()
        end
        if _sitAcTimer then _sitAcTimer:Cancel() end
        _sitAcTimer = C_Timer.NewTimer(0.15, function()
            if BNB.ZonePicker and BNB.ZonePicker.GetMatches then
                local matches = BNB.ZonePicker.GetMatches(text, sitSelType, 7)
                SitShowAC(matches)
            end
        end)
    end)
    sitValueEb:HookScript("OnEditFocusLost", function()
        C_Timer.After(0.2, function()
            if not sitAcFrame:IsMouseOver() then SitHideAC() end
        end)
    end)

    sitBrowseBtn:SetScript("OnClick", function()
        SitHideAC()
        if BNB.ZonePicker then
            if BNB.ZonePicker.IsShown and BNB.ZonePicker.IsShown() then
                BNB.ZonePicker.Close()
            else
                BNB.ZonePicker.Open(sitValueRow, function(name, kind)
                    sitValueEb:SetText(name)
                end, sitSelType)
            end
        end
    end)

    -- ── Use Current / Apply / Clear ───────────────────────────────────────────
    local sitUseCurrentBtn = BNB.CreateButton(nil, ct3, L["STICKY_SIT_USE_CURRENT_BTN"], 90, 20)
    sitUseCurrentBtn:SetPoint("TOPLEFT", sitValueRow, "BOTTOMLEFT", 0, -4)
    sitUseCurrentBtn:Hide()

    local sitSaveCtxBtn = BNB.CreateButton(nil, ct3, L["STICKY_SIT_APPLY_BTN"], 60, 22)
    sitSaveCtxBtn:SetPoint("TOPLEFT", sitUseCurrentBtn, "TOPRIGHT", 8, 0)
    sitSaveCtxBtn:Hide()

    local sitClearCtxBtn = BNB.CreateButton(nil, ct3, L["STICKY_SIT_CLEAR_BTN"], 52, 22)
    sitClearCtxBtn:SetPoint("TOPLEFT", sitSaveCtxBtn, "TOPRIGHT", 6, 0)
    sitClearCtxBtn:Hide()

    -- ── Current binding display ───────────────────────────────────────────────
    local sitCurBindValue = ct3:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge3")
    sitCurBindValue:SetPoint("BOTTOMLEFT",  ct3, "BOTTOMLEFT",  SIT_PAD, SIT_PAD + 6)
    sitCurBindValue:SetPoint("BOTTOMRIGHT", ct3, "BOTTOMRIGHT", 0, SIT_PAD + 6)
    sitCurBindValue:SetJustifyH("CENTER"); sitCurBindValue:SetWordWrap(false)
    sitCurBindValue:SetMaxLines(1); sitCurBindValue:SetTextColor(1, 1, 1); sitCurBindValue:SetText("")

    local sitCurBindHeader = ct3:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    sitCurBindHeader:SetPoint("BOTTOMLEFT",  sitCurBindValue, "TOPLEFT",  0, 4)
    sitCurBindHeader:SetPoint("BOTTOMRIGHT", sitCurBindValue, "TOPRIGHT", 0, 4)
    sitCurBindHeader:SetJustifyH("CENTER"); sitCurBindHeader:SetWordWrap(false)
    sitCurBindHeader:SetMaxLines(1); sitCurBindHeader:SetTextColor(0.55, 0.55, 0.55); sitCurBindHeader:SetText("")

    -- ── Display mode dropdown ─────────────────────────────────────────────────
    local SIT_DISPLAY_MODES  = { "popup", "sticky", "both" }
    local SIT_DISPLAY_LABELS = { L["STICKY_DISP_POPUP"], L["STICKY_DISP_STICKY"], L["STICKY_DISP_BOTH"] }
    local sitSelDisplay = "popup"

    local SIT_LEAVE_MODES  = { "keep", "bt-minimize", "hide" }
    local SIT_LEAVE_LABELS = { L["STICKY_LEAVE_KEEP"], L["STICKY_LEAVE_MINIMIZE"], L["STICKY_LEAVE_HIDE"] }
    local sitSelLeave = "keep"

    local sitDispDiv = ct3:CreateTexture(nil, "ARTWORK")
    sitDispDiv:SetHeight(1)
    sitDispDiv:SetPoint("TOPLEFT",  sitUseCurrentBtn, "BOTTOMLEFT",   0, -26)
    sitDispDiv:SetPoint("TOPRIGHT", ct3,              "TOPRIGHT",     0, 0)
    if skinMode and BNB.GetSkinPreset then
        local p = BNB.GetSkinPreset()
        local br, bg_, bb = BNB.SkinBorderOf(p)
        sitDispDiv:SetColorTexture(br, bg_, bb, 0.8)
        BNB.RegisterSkinRule(sitDispDiv, 0.8)
    else
        sitDispDiv:SetColorTexture(0.28, 0.28, 0.30, 0.8)
    end
    sitDispDiv:Hide()

    local sitDispLabel = ct3:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    sitDispLabel:SetPoint("TOPLEFT", sitDispDiv, "BOTTOMLEFT", 0, -6)
    sitDispLabel:SetText(L["STICKY_SIT_DISPLAY_LABEL"])
    sitDispLabel:SetTextColor(0.78, 0.78, 0.78); sitDispLabel:Hide()

    local function SitGetDispLabel(m)
        for i, k in ipairs(SIT_DISPLAY_MODES) do if k == m then return SIT_DISPLAY_LABELS[i] end end
        return SIT_DISPLAY_LABELS[1]
    end
    local function SitSetDispText(label)
        if sitDispDropdown and sitDispDropdown.Text then sitDispDropdown.Text:SetText(label) end
        if sitDispCycleBtn then sitDispCycleBtn:SetText(label) end
    end
    local function SitOnDispChanged(mode)
        sitSelDisplay = mode
        if mode == "sticky" or mode == "both" then
            SitSave({ contextDisplay = mode })
        else
            BNB.UpdateNote(noteID, { _clear = {"contextDisplay"} })
            if BNB.RefreshNoteList then BNB.RefreshNoteList() end
            if BNB.SyncNoteConfig  then BNB.SyncNoteConfig(noteID) end
        end
    end

    local useNativeDisp3 = useNativeSit3
    local sitDispDropdown
    local sitDispCycleBtn

    if useNativeDisp3 then
        sitDispDropdown = CreateFrame("DropdownButton", "BNBStickySetDispDD", ct3,
            "WowStyle1DropdownTemplate")
        sitDispDropdown:SetPoint("TOPLEFT",  sitDispLabel, "BOTTOMLEFT",  0, -4)
        sitDispDropdown:SetPoint("TOPRIGHT", ct3,          "TOPRIGHT",    0, 0)
        sitDispDropdown:SetHeight(24)
        local function RebuildDispMenu3()
            sitDispDropdown:SetupMenu(function(_, root)
                for i, label in ipairs(SIT_DISPLAY_LABELS) do
                    local key = SIT_DISPLAY_MODES[i]
                    root:CreateRadio(label,
                        function() return sitSelDisplay == key end,
                        function()
                            sitSelDisplay = key
                            sitDispDropdown:GenerateMenu()
                            SitOnDispChanged(key)
                        end)
                end
            end)
        end
        RebuildDispMenu3()
        sitDispDropdown:Hide()
        ct3._sitRebuildDispMenu = RebuildDispMenu3
    else
        sitDispCycleBtn = BNB.CreateButton(nil, ct3, SitGetDispLabel(sitSelDisplay), SIT_CW, 24)
        sitDispCycleBtn:SetPoint("TOPLEFT", sitDispLabel, "BOTTOMLEFT", 0, -4)
        sitDispCycleBtn:SetScript("OnClick", function(self)
            local idx = 1
            for i, k in ipairs(SIT_DISPLAY_MODES) do if k == sitSelDisplay then idx = i; break end end
            idx = (idx % #SIT_DISPLAY_MODES) + 1
            sitSelDisplay = SIT_DISPLAY_MODES[idx]
            self:SetText(SIT_DISPLAY_LABELS[idx])
            SitOnDispChanged(sitSelDisplay)
        end)
        sitDispCycleBtn:Hide()
    end

    -- ── Leave action dropdown ─────────────────────────────────────────────────
    local function SitGetLeaveLabel(m)
        for i, k in ipairs(SIT_LEAVE_MODES) do if k == m then return SIT_LEAVE_LABELS[i] end end
        return SIT_LEAVE_LABELS[1]
    end
    local function SitSetLeaveText(label)
        if sitLeaveDropdown and sitLeaveDropdown.Text then sitLeaveDropdown.Text:SetText(label) end
        if sitLeaveCycleBtn then sitLeaveCycleBtn:SetText(label) end
    end
    local function SitOnLeaveChanged(mode)
        sitSelLeave = mode
        if mode == "keep" then
            BNB.UpdateNote(noteID, { _clear = {"contextLeave"} })
        else
            SitSave({ contextLeave = mode })
            return  -- SitSave already calls SyncNoteConfig
        end
        if BNB.RefreshNoteList then BNB.RefreshNoteList() end
        if BNB.SyncNoteConfig  then BNB.SyncNoteConfig(noteID) end
    end

    local sitLeaveDiv = ct3:CreateTexture(nil, "ARTWORK")
    sitLeaveDiv:SetHeight(1)
    sitLeaveDiv:SetPoint("TOPLEFT",  sitDispDiv, "TOPLEFT",  0, -52)
    sitLeaveDiv:SetPoint("TOPRIGHT", ct3,        "TOPRIGHT", 0, 0)
    if skinMode and BNB.GetSkinPreset then
        local p = BNB.GetSkinPreset()
        local br, bg_, bb = BNB.SkinBorderOf(p)
        sitLeaveDiv:SetColorTexture(br, bg_, bb, 0.8)
        BNB.RegisterSkinRule(sitLeaveDiv, 0.8)
    else
        sitLeaveDiv:SetColorTexture(0.28, 0.28, 0.30, 0.8)
    end
    sitLeaveDiv:Hide()

    local sitLeaveLabel = ct3:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    sitLeaveLabel:SetPoint("TOPLEFT", sitLeaveDiv, "BOTTOMLEFT", 0, -6)
    sitLeaveLabel:SetText(L["STICKY_SIT_LEAVE_LABEL"])
    sitLeaveLabel:SetTextColor(0.78, 0.78, 0.78); sitLeaveLabel:Hide()

    local useNativeLeave3 = useNativeDisp3
    local sitLeaveDropdown
    local sitLeaveCycleBtn

    if useNativeLeave3 then
        sitLeaveDropdown = CreateFrame("DropdownButton", "BNBStickySetLeaveDD", ct3,
            "WowStyle1DropdownTemplate")
        sitLeaveDropdown:SetPoint("TOPLEFT",  sitLeaveLabel, "BOTTOMLEFT",  0, -4)
        sitLeaveDropdown:SetPoint("TOPRIGHT", ct3,           "TOPRIGHT",    0, 0)
        sitLeaveDropdown:SetHeight(24)
        local function RebuildLeaveMenu3()
            sitLeaveDropdown:SetupMenu(function(_, root)
                for i, label in ipairs(SIT_LEAVE_LABELS) do
                    local key = SIT_LEAVE_MODES[i]
                    root:CreateRadio(label,
                        function() return sitSelLeave == key end,
                        function()
                            sitSelLeave = key
                            sitLeaveDropdown:GenerateMenu()
                            SitOnLeaveChanged(key)
                        end)
                end
            end)
        end
        RebuildLeaveMenu3()
        sitLeaveDropdown:Hide()
        ct3._sitRebuildLeaveMenu = RebuildLeaveMenu3
    else
        sitLeaveCycleBtn = BNB.CreateButton(nil, ct3, SitGetLeaveLabel(sitSelLeave), SIT_CW, 24)
        sitLeaveCycleBtn:SetPoint("TOPLEFT", sitLeaveLabel, "BOTTOMLEFT", 0, -4)
        sitLeaveCycleBtn:SetScript("OnClick", function(self)
            local idx = 1
            for i, k in ipairs(SIT_LEAVE_MODES) do if k == sitSelLeave then idx = i; break end end
            idx = (idx % #SIT_LEAVE_MODES) + 1
            sitSelLeave = SIT_LEAVE_MODES[idx]
            self:SetText(SIT_LEAVE_LABELS[idx])
            SitOnLeaveChanged(sitSelLeave)
        end)
        sitLeaveCycleBtn:Hide()
    end

    local function SitShowDispControls(show)
        if show then
            sitDispDiv:Show(); sitDispLabel:Show()
            if sitDispDropdown  then sitDispDropdown:Show()  end
            if sitDispCycleBtn  then sitDispCycleBtn:Show()  end
            sitLeaveDiv:Show(); sitLeaveLabel:Show()
            if sitLeaveDropdown then sitLeaveDropdown:Show() end
            if sitLeaveCycleBtn then sitLeaveCycleBtn:Show() end
        else
            sitDispDiv:Hide(); sitDispLabel:Hide()
            if sitDispDropdown  then sitDispDropdown:Hide()  end
            if sitDispCycleBtn  then sitDispCycleBtn:Hide()  end
            sitLeaveDiv:Hide(); sitLeaveLabel:Hide()
            if sitLeaveDropdown then sitLeaveDropdown:Hide() end
            if sitLeaveCycleBtn then sitLeaveCycleBtn:Hide() end
        end
    end

    -- ── Refresh current-binding label ─────────────────────────────────────────
    local SIT_KIND_LABELS = { zone=L["STICKY_KIND_ZONE"], subzone=L["STICKY_KIND_SUBZONE"], instance=L["STICKY_KIND_INSTANCE"], player=L["STICKY_KIND_PLAYER"] }
    local SIT_BIND_MAX_W  = SETTINGS_CW - SIT_PAD * 2
    local SIT_BIND_DEF_SZ = 20
    local SIT_BIND_MIN_SZ = 11

    SitRefreshCurBind = function()
        local n3  = BNB.GetNote(noteID)
        local ctx = n3 and n3.context
        if ctx and ctx ~= "" then
            local kind, value
            if BNB.DecodeContext then kind, value = BNB.DecodeContext(ctx) end
            local kindLabel = SIT_KIND_LABELS[kind] or kind or "?"
            sitCurBindHeader:SetText(string.format(L["STICKY_SIT_BOUND_TO_FMT"], kindLabel))
            sitCurBindValue:SetText(value or "?")
            local path = sitCurBindValue:GetFont()
            if path then
                pcall(function() sitCurBindValue:SetFont(path, SIT_BIND_DEF_SZ, "") end)
                local sw = sitCurBindValue:GetStringWidth() or 0
                if sw > SIT_BIND_MAX_W then
                    local sz = math.max(SIT_BIND_MIN_SZ, math.floor(SIT_BIND_DEF_SZ * SIT_BIND_MAX_W / sw))
                    pcall(function() sitCurBindValue:SetFont(path, sz, "") end)
                end
            end
        else
            sitCurBindHeader:SetText("|cff666666" .. L["NC_NO_BINDING"] .. "|r")
            local path = sitCurBindValue:GetFont()
            if path then pcall(function() sitCurBindValue:SetFont(path, SIT_BIND_DEF_SZ, "") end) end
            sitCurBindValue:SetText("|cff666666" .. L["NC_NOTE_GLOBAL"] .. "|r")
        end
    end

    -- ── SelectType ────────────────────────────────────────────────────────────
    SitSelectType = function(t)
        sitSelType = t
        local needsValue = (t ~= "none")
        sitValueRow:SetShown(needsValue)
        sitUseCurrentBtn:SetShown(needsValue)
        sitSaveCtxBtn:SetShown(needsValue)
        sitClearCtxBtn:SetShown(true)
        SitShowDispControls(needsValue)
        local canBrowse = (t == "zone" or t == "instance")
        sitBrowseBtn:SetShown(needsValue and canBrowse)
        SitHideAC()
        if BNB.ZonePicker and BNB.ZonePicker.Close then BNB.ZonePicker.Close() end
        if t == "zone"     then sitValueLbl:SetText(L["STICKY_SIT_ZONE_LABEL"])
        elseif t == "subzone"  then sitValueLbl:SetText(L["STICKY_SIT_SUBZONE_LABEL"])
        elseif t == "instance" then sitValueLbl:SetText(L["STICKY_SIT_INSTANCE_LABEL"])
        elseif t == "player"   then sitValueLbl:SetText(L["STICKY_SIT_PLAYER_LABEL"])
        end
    end

    -- ── Use Current ───────────────────────────────────────────────────────────
    sitUseCurrentBtn:SetScript("OnClick", function()
        local val = ""
        if sitSelType == "zone" then
            val = GetZoneText() or ""
        elseif sitSelType == "subzone" then
            val = GetSubZoneText and GetSubZoneText() or ""
        elseif sitSelType == "instance" then
            val = (GetInstanceInfo and select(1, GetInstanceInfo())) or GetRealZoneText() or ""
        elseif sitSelType == "player" then
            val = (BNB.UnitNameRealm("target")) or ""
        end
        if sitValueEb then sitValueEb:SetText(val) end
    end)

    -- ── Apply ─────────────────────────────────────────────────────────────────
    sitSaveCtxBtn:SetScript("OnClick", function()
        local val = sitValueEb and sitValueEb:GetText() or ""
        val = val:match("^%s*(.-)%s*$") or ""
        if sitSelType == "none" or val == "" then
            BNB.UpdateNote(noteID, { _clear = {"context"} })
        else
            BNB.UpdateNote(noteID, { context = sitSelType .. ":" .. val })
        end
        SitRefreshCurBind()
        if BNB.RefreshNoteList     then BNB.RefreshNoteList()     end
        if BNB.CheckContextualNotes then BNB.CheckContextualNotes() end
        if BNB.SyncNoteConfig      then BNB.SyncNoteConfig(noteID) end
        SN.RefreshMarkers(noteID)
        BNB:Print(L["STICKY_CONTEXT_BINDING_SAVED"])
    end)

    -- ── Clear ─────────────────────────────────────────────────────────────────
    sitClearCtxBtn:SetScript("OnClick", function()
        BNB.UpdateNote(noteID, { _clear = {"context", "contextDisplay", "contextLeave"} })
        SN.RefreshMarkers(noteID)
        if sitValueEb then sitValueEb:SetText("") end
        sitSelType = "none"; sitSelDisplay = "popup"; sitSelLeave = "keep"
        SitSetTypeText(SIT_TYPE_LABELS[1])
        SitSetDispText(SitGetDispLabel("popup"))
        SitSetLeaveText(SitGetLeaveLabel("keep"))
        if sitTypeDropdown  and sitTypeDropdown.GenerateMenu  then sitTypeDropdown:GenerateMenu()  end
        if sitDispDropdown  and sitDispDropdown.GenerateMenu  then sitDispDropdown:GenerateMenu()  end
        if sitLeaveDropdown and sitLeaveDropdown.GenerateMenu then sitLeaveDropdown:GenerateMenu() end
        SitSelectType("none")
        sitClearCtxBtn:Hide()
        SitRefreshCurBind()
        -- Remove any active waypoint for this note
        local uid = BNB._autoWaypoints and BNB._autoWaypoints[noteID]
        if uid then
            if TomTom and TomTom.RemoveWaypoint and type(uid) == "table" then
                pcall(function() TomTom:RemoveWaypoint(uid) end)
            elseif uid == true and C_Map and C_Map.ClearUserWaypoint then
                pcall(function() C_Map.ClearUserWaypoint() end)
            end
            BNB._autoWaypoints[noteID] = nil
        end
        if BNB.RefreshNoteList     then BNB.RefreshNoteList()     end
        if BNB.CheckContextualNotes then BNB.CheckContextualNotes() end
        if BNB.SyncNoteConfig      then BNB.SyncNoteConfig(noteID) end
    end)

    -- ── Waypoint section ──────────────────────────────────────────────────────
    local function SitHasWPAddon()   return TomTom and TomTom.AddWaypoint end
    local function SitHasRetailPin() return C_Map and C_Map.SetUserWaypoint end
    local function SitWPAvailable()  return SitHasWPAddon() or SitHasRetailPin() end

    local sitWpDiv = ct3:CreateTexture(nil, "ARTWORK")
    sitWpDiv:SetHeight(1)
    sitWpDiv:SetPoint("TOPLEFT",  sitLeaveDiv, "TOPLEFT",  0, -90)
    sitWpDiv:SetPoint("TOPRIGHT", ct3,         "TOPRIGHT", 0, 0)
    if skinMode and BNB.GetSkinPreset then
        local p = BNB.GetSkinPreset()
        local br, bg_, bb = BNB.SkinBorderOf(p)
        sitWpDiv:SetColorTexture(br, bg_, bb, 0.8)
        BNB.RegisterSkinRule(sitWpDiv, 0.8)
    else
        sitWpDiv:SetColorTexture(0.28, 0.28, 0.30, 0.8)
    end
    sitWpDiv:Hide()

    local sitWpHdr = ct3:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    sitWpHdr:SetPoint("TOPLEFT", sitWpDiv, "BOTTOMLEFT", 0, -6)
    sitWpHdr:SetTextColor(1, 0.82, 0, 1); sitWpHdr:SetText(L["STICKY_WP_HEADER"]); sitWpHdr:Hide()

    local sitWpStatusTag = ct3:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    sitWpStatusTag:SetPoint("LEFT", sitWpHdr, "RIGHT", 6, 0); sitWpStatusTag:Hide()

    local function SitRefreshWPStatusTag()
        if SitHasWPAddon() then
            sitWpStatusTag:SetText(SitHasRetailPin() and L["STICKY_WP_TAG_ENHANCED"] or L["STICKY_WP_TAG_ADDON"])
            sitWpStatusTag:SetTextColor(0.4, 1, 0.4)
        elseif SitHasRetailPin() then
            sitWpStatusTag:SetText(L["STICKY_WP_TAG_BASIC"]); sitWpStatusTag:SetTextColor(0.85, 0.70, 0.2)
        else
            sitWpStatusTag:SetText(L["STICKY_WP_TAG_REQUIRED"]); sitWpStatusTag:SetTextColor(0.85, 0.30, 0.25)
        end
    end

    local sitWpInfoLbl = ct3:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    sitWpInfoLbl:SetPoint("LEFT", sitWpStatusTag, "RIGHT", 4, 0)
    sitWpInfoLbl:SetText("|cff88bbff?|r"); sitWpInfoLbl:Hide()

    -- Waypoint info popup (reuse same popup anchor pattern as NoteConfig)
    local sitWpInfoPopup = nil
    local function SitShowWPInfoPopup()
        if sitWpInfoPopup then
            if sitWpInfoPopup:IsShown() then sitWpInfoPopup:Hide(); return end
        end
        if not sitWpInfoPopup then
            local fp = BNB.CreateBackdropFrame("Frame", "BNBStickyWaypointInfoPopup", UIParent)
            fp:SetSize(310, 230); fp:SetFrameStrata("DIALOG"); fp:SetClampedToScreen(true)
            fp:EnableMouse(true); fp:SetMovable(true)
            fp:RegisterForDrag("LeftButton")
            fp:SetScript("OnDragStart", fp.StartMoving); fp:SetScript("OnDragStop", fp.StopMovingOrSizing)
            BNB.SetBackdrop(fp, 0.08, 0.08, 0.11, 0.96, 0.35, 0.35, 0.38, 1)
            local ptitle = fp:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
            ptitle:SetPoint("TOPLEFT", fp, "TOPLEFT", 14, -12)
            ptitle:SetTextColor(1, 0.82, 0); ptitle:SetText(L["STICKY_WP_SUPPORT_TITLE"])
            local pclose = CreateFrame("Button", nil, fp); pclose:SetSize(20, 20)
            pclose:SetPoint("TOPRIGHT", fp, "TOPRIGHT", -6, -6)
            local pcloseLbl = pclose:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            pcloseLbl:SetAllPoints(); pcloseLbl:SetText("|cffaaaaaax|r")
            pclose:SetScript("OnClick", function() fp:Hide() end)
            pclose:SetScript("OnEnter", function() pcloseLbl:SetText("|cffff4444x|r") end)
            pclose:SetScript("OnLeave", function() pcloseLbl:SetText("|cffaaaaaax|r") end)
            fp._statusLbl = fp:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            fp._statusLbl:SetPoint("TOPLEFT", ptitle, "BOTTOMLEFT", 0, -10)
            fp._statusLbl:SetWidth(280); fp._statusLbl:SetJustifyH("LEFT")
            fp._descLbl = fp:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            fp._descLbl:SetPoint("TOPLEFT", fp._statusLbl, "BOTTOMLEFT", 0, -6)
            fp._descLbl:SetWidth(280); fp._descLbl:SetJustifyH("LEFT"); fp._descLbl:SetWordWrap(true)
            fp._descLbl:SetTextColor(0.78, 0.78, 0.78)
            local linksHdr = fp:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            linksHdr:SetPoint("TOPLEFT", fp._descLbl, "BOTTOMLEFT", 0, -14)
            linksHdr:SetText(L["STICKY_WP_RECOMMENDED_ADDONS"]); linksHdr:SetTextColor(1, 1, 1)
            local wpuiBtn = BNB.CreateButton(nil, fp, L["STICKY_WP_BTN_WAYPOINTUI"], 200, 22)
            wpuiBtn:SetPoint("TOPLEFT", linksHdr, "BOTTOMLEFT", 0, -6)
            wpuiBtn:SetScript("OnClick", function()
                BNB.ShowClipboardHint("https://www.curseforge.com/wow/addons/waypointui", wpuiBtn)
            end)
            wpuiBtn:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_TOP")
                GameTooltip:AddLine(L["NC_WP_COPY_URL_TIP"], 0.55, 0.85, 1)
                GameTooltip:Show()
            end)
            wpuiBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
            local ttBtn2 = BNB.CreateButton(nil, fp, L["STICKY_WP_BTN_TOMTOM"], 200, 22)
            ttBtn2:SetPoint("TOPLEFT", wpuiBtn, "BOTTOMLEFT", 0, -4)
            ttBtn2:SetScript("OnClick", function()
                BNB.ShowClipboardHint("https://www.curseforge.com/wow/addons/tomtom", ttBtn2)
            end)
            ttBtn2:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_TOP")
                GameTooltip:AddLine(L["NC_WP_COPY_URL_TIP"], 0.55, 0.85, 1)
                GameTooltip:Show()
            end)
            ttBtn2:SetScript("OnLeave", function() GameTooltip:Hide() end)

            -- ESC closes one window at a time: copy box, then this popup, then
            -- the settings window via UISpecialFrames (ALL-21). A keyboard-enabled frame gets
            -- keys before the copy box's focused editbox, so close the box here
            -- first, the same way MainWindow's ESC chain does
            fp:EnableKeyboard(true)
            fp:SetScript("OnKeyDown", function(self, key)
                if key ~= "ESCAPE" then self:SetPropagateKeyboardInput(true); return end
                self:SetPropagateKeyboardInput(false)
                local ch = BNB._clipboardHint
                if ch and ch:IsShown() and ch._dismiss then
                    ch._dismiss()
                else
                    self:Hide()
                end
            end)

            sitWpInfoPopup = fp
        end
        local fp = sitWpInfoPopup
        if SitHasWPAddon() then
            fp._statusLbl:SetText("|cff66ff66" .. L["STICKY_WP_STATUS_ADDON"] .. "|r")
            fp._descLbl:SetText(L["STICKY_WP_FULL_SUPPORT"])
        elseif SitHasRetailPin() then
            fp._statusLbl:SetText("|cffffaa00" .. L["STICKY_WP_STATUS_BASIC"] .. "|r")
            fp._descLbl:SetText(L["STICKY_WP_INSTALL_FOR_FULL"])
        else
            fp._statusLbl:SetText("|cffff5555" .. L["STICKY_WP_STATUS_NONE"] .. "|r")
            fp._descLbl:SetText(L["STICKY_WP_INSTALL_TO_ENABLE"])
        end
        fp:ClearAllPoints()
        if _stickySettingsFrame then
            fp:SetPoint("TOPLEFT", _stickySettingsFrame, "TOPRIGHT", 4, 0)
        else
            fp:SetPoint("CENTER", UIParent, "CENTER", 0, 100)
        end
        fp:Show()
    end

    local sitWpInfoHit = CreateFrame("Button", nil, ct3)
    sitWpInfoHit:SetPoint("LEFT",  sitWpStatusTag, "LEFT",  -2, 0)
    sitWpInfoHit:SetPoint("RIGHT", sitWpInfoLbl,   "RIGHT",  4, 0)
    sitWpInfoHit:SetHeight(18); sitWpInfoHit:Hide()
    sitWpInfoHit:SetScript("OnClick", SitShowWPInfoPopup)
    sitWpInfoHit:SetScript("OnEnter", function(self)
        sitWpInfoLbl:SetText("|cffbbddff?|r")
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(L["STICKY_WP_INFO_TIP"], 0.55, 0.85, 1); GameTooltip:Show()
    end)
    sitWpInfoHit:SetScript("OnLeave", function()
        sitWpInfoLbl:SetText("|cff88bbff?|r"); GameTooltip:Hide()
    end)

    local sitWpDesc = ct3:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    sitWpDesc:SetPoint("TOPLEFT",  sitWpHdr,  "BOTTOMLEFT",  0, -4)
    sitWpDesc:SetPoint("TOPRIGHT", ct3,       "TOPRIGHT",    0, 0)
    sitWpDesc:SetJustifyH("LEFT"); sitWpDesc:SetWordWrap(true)
    sitWpDesc:SetTextColor(0.60, 0.60, 0.60)
    sitWpDesc:SetText(L["STICKY_WP_DESC"])
    sitWpDesc:Hide()

    local SIT_BTN_W = 72; local SIT_BTN_H = 22; local SIT_BTN_GAP = 6
    local sitWpPinBtn   = BNB.CreateButton(nil, ct3, L["STICKY_WP_BTN_PIN_HERE"], SIT_BTN_W, SIT_BTN_H)
    sitWpPinBtn:SetPoint("TOPLEFT", sitWpDesc, "BOTTOMLEFT", 0, -6); sitWpPinBtn:Hide()
    local sitWpNavBtn   = BNB.CreateButton(nil, ct3, L["STICKY_WP_BTN_NAVIGATE"], SIT_BTN_W, SIT_BTN_H)
    sitWpNavBtn:SetPoint("LEFT", sitWpPinBtn, "RIGHT", SIT_BTN_GAP, 0); sitWpNavBtn:Hide()
    local sitWpClearBtn = BNB.CreateButton(nil, ct3, L["STICKY_WP_BTN_CLEAR"],  SIT_BTN_W, SIT_BTN_H)
    sitWpClearBtn:SetPoint("TOPLEFT", sitWpPinBtn, "BOTTOMLEFT", 0, -SIT_BTN_GAP); sitWpClearBtn:Hide()
    local sitWpManualBtn = BNB.CreateButton(nil, ct3, L["STICKY_WP_BTN_MANUAL"], SIT_BTN_W, SIT_BTN_H)
    sitWpManualBtn:SetPoint("LEFT", sitWpClearBtn, "RIGHT", SIT_BTN_GAP, 0); sitWpManualBtn:Hide()

    -- Manual coord row
    local sitWpManualRow = CreateFrame("Frame", nil, ct3)
    sitWpManualRow:SetHeight(22)
    sitWpManualRow:SetPoint("TOPLEFT",  sitWpClearBtn, "BOTTOMLEFT", 0, -6)
    sitWpManualRow:SetPoint("TOPRIGHT", ct3,           "TOPRIGHT",   0, 0)
    sitWpManualRow:Hide()

    local sitWpXLbl = sitWpManualRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    sitWpXLbl:SetPoint("LEFT", sitWpManualRow, "LEFT", 0, 0)
    sitWpXLbl:SetText(L["STICKY_WP_X_LABEL"]); sitWpXLbl:SetTextColor(0.78, 0.78, 0.78); sitWpXLbl:SetWidth(14)
    local sitWpXEb = CreateFrame("EditBox", nil, sitWpManualRow, "BackdropTemplate")
    BNB.EnsureBackdrop(sitWpXEb); BNB.SetBackdropDark(sitWpXEb)
    sitWpXEb:SetPoint("LEFT", sitWpXLbl, "RIGHT", 2, 0); sitWpXEb:SetSize(52, 20)
    sitWpXEb:SetFontObject("GameFontNormalSmall"); sitWpXEb:SetAutoFocus(false)
    sitWpXEb:SetMaxLetters(8); sitWpXEb:SetNumeric(false); sitWpXEb:SetTextInsets(3,3,0,0)
    local sitWpYLbl = sitWpManualRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    sitWpYLbl:SetPoint("LEFT", sitWpXEb, "RIGHT", 6, 0)
    sitWpYLbl:SetText(L["STICKY_WP_Y_LABEL"]); sitWpYLbl:SetTextColor(0.78, 0.78, 0.78); sitWpYLbl:SetWidth(14)
    local sitWpYEb = CreateFrame("EditBox", nil, sitWpManualRow, "BackdropTemplate")
    BNB.EnsureBackdrop(sitWpYEb); BNB.SetBackdropDark(sitWpYEb)
    sitWpYEb:SetPoint("LEFT", sitWpYLbl, "RIGHT", 2, 0); sitWpYEb:SetSize(52, 20)
    sitWpYEb:SetFontObject("GameFontNormalSmall"); sitWpYEb:SetAutoFocus(false)
    sitWpYEb:SetMaxLetters(8); sitWpYEb:SetNumeric(false); sitWpYEb:SetTextInsets(3,3,0,0)
    local sitWpSaveManualBtn = BNB.CreateButton(nil, sitWpManualRow, L["STICKY_WP_BTN_SET"], 38, 20)
    sitWpSaveManualBtn:SetPoint("LEFT", sitWpYEb, "RIGHT", 4, 0)

    -- WP status label
    local sitWpStatusLbl = ct3:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    sitWpStatusLbl:SetPoint("BOTTOMLEFT",  sitCurBindHeader, "TOPLEFT",  0, 6)
    sitWpStatusLbl:SetPoint("BOTTOMRIGHT", sitCurBindHeader, "TOPRIGHT", 0, 6)
    sitWpStatusLbl:SetJustifyH("CENTER"); sitWpStatusLbl:SetTextColor(0.55, 0.85, 1, 1)
    sitWpStatusLbl:SetText(""); sitWpStatusLbl:Hide()

    SitRefreshWaypointDisplay = function()
        local n3  = BNB.GetNote(noteID)
        local wp  = n3 and n3.waypoint
        if wp and wp.x and wp.y then
            local title = wp.title or wp.label or ""
            local coordStr = string.format("%.1f, %.1f", wp.x, wp.y)
            sitWpStatusLbl:SetText(L["STICKY_WP_STATUS_LABEL"] .. "\n" .. (title ~= "" and title .. "\n" or "") .. coordStr)
            sitWpStatusLbl:Show()
        else
            sitWpStatusLbl:SetText(""); sitWpStatusLbl:Hide()
        end
    end

    -- WP leave checkbox
    local sitWpLeaveChk = CreateFrame("CheckButton", nil, ct3, "UICheckButtonTemplate")
    sitWpLeaveChk:SetSize(24, 24)
    sitWpLeaveChk:SetPoint("TOPLEFT", sitWpClearBtn, "BOTTOMLEFT", -4, -8); sitWpLeaveChk:Hide()
    local sitWpLeaveChkLbl = sitWpLeaveChk:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    sitWpLeaveChkLbl:SetPoint("LEFT", sitWpLeaveChk, "RIGHT", 2, 0)
    sitWpLeaveChkLbl:SetText(L["STICKY_WP_LEAVE_REMOVE_LABEL"])
    sitWpLeaveChkLbl:SetTextColor(0.78, 0.78, 0.78)
    sitWpLeaveChk:SetScript("OnClick", function(self)
        if self:GetChecked() then
            BNB.UpdateNote(noteID, {wpClearOnLeave = true})
        else
            BNB.UpdateNote(noteID, {_clear = {"wpClearOnLeave"}})
        end
        if BNB.SyncNoteConfig then BNB.SyncNoteConfig(noteID) end
    end)
    sitWpLeaveChk:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(L["STICKY_WP_LEAVE_REMOVE_TIP"], 0.85, 0.85, 0.85, true)
        GameTooltip:Show()
    end)
    sitWpLeaveChk:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- ShowDispControls extended with waypoint section (mirrors NoteConfig pattern)
    local _sitOrigShowDisp = SitShowDispControls
    SitShowDispControls = function(show)
        _sitOrigShowDisp(show)
        if show then
            sitWpDiv:Show(); sitWpHdr:Show(); sitWpDesc:Show()
            sitWpStatusTag:Show(); sitWpInfoLbl:Show(); sitWpInfoHit:Show()
            SitRefreshWPStatusTag()
            sitWpPinBtn:Show(); sitWpNavBtn:Show()
            sitWpClearBtn:Show(); sitWpManualBtn:Show()
            sitWpLeaveChk:Show()
            local n3 = BNB.GetNote(noteID)
            sitWpLeaveChk:SetChecked(n3 and n3.wpClearOnLeave == true)
            local avail = SitWPAvailable()
            sitWpPinBtn:SetEnabled(avail); sitWpNavBtn:SetEnabled(avail)
            sitWpClearBtn:SetEnabled(avail); sitWpManualBtn:SetEnabled(avail)
            sitWpLeaveChk:SetEnabled(avail)
            if avail then
                sitWpDesc:SetText(L["STICKY_WP_DESC"])
                sitWpDesc:SetTextColor(0.60, 0.60, 0.60)
            else
                sitWpDesc:SetText(L["STICKY_WP_INSTALL_ADDON_FEATURE"])
                sitWpDesc:SetTextColor(0.65, 0.40, 0.35)
            end
        else
            sitWpDiv:Hide(); sitWpHdr:Hide(); sitWpDesc:Hide()
            sitWpStatusTag:Hide(); sitWpInfoLbl:Hide(); sitWpInfoHit:Hide()
            sitWpPinBtn:Hide(); sitWpNavBtn:Hide()
            sitWpClearBtn:Hide(); sitWpManualBtn:Hide()
            sitWpManualRow:Hide(); sitWpLeaveChk:Hide()
        end
    end

    -- Manual coord commit
    local function SitCommitManualCoords()
        local n3 = BNB.GetNote(noteID); if not n3 then return end
        local xs = sitWpXEb:GetText():match("^%s*(.-)%s*$") or ""
        local ys = sitWpYEb:GetText():match("^%s*(.-)%s*$") or ""
        local x, y = tonumber(xs), tonumber(ys)
        if not x or not y then BNB:Print("|cffff6666Invalid coordinates.|r"); return end
        x = math.max(0, math.min(100, x)); y = math.max(0, math.min(100, y))
        local zone  = GetRealZoneText() or GetZoneText() or ""
        local title = (n3.title and n3.title ~= "") and n3.title or zone
        local mapID = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
        local existWP = n3.waypoint
        BNB.UpdateNote(noteID, { waypoint = {
            mapID = mapID or (existWP and existWP.mapID),
            x = x, y = y, label = zone, title = title,
        }})
        SitRefreshWaypointDisplay(); sitWpManualRow:Hide()
        BNB:Print(string.format("Waypoint set manually: %s (%.1f, %.1f)", title, x, y))
        if BNB.SyncNoteConfig then BNB.SyncNoteConfig(noteID) end
    end

    sitWpManualBtn:SetScript("OnClick", function()
        if sitWpManualRow:IsShown() then sitWpManualRow:Hide(); return end
        local n3 = BNB.GetNote(noteID); local wp = n3 and n3.waypoint
        if wp and wp.x then sitWpXEb:SetText(string.format("%.1f", wp.x)) end
        if wp and wp.y then sitWpYEb:SetText(string.format("%.1f", wp.y)) end
        sitWpManualRow:Show(); sitWpXEb:SetFocus()
    end)
    sitWpManualBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(L["STICKY_WP_MANUAL_TIP"], 1, 1, 1); GameTooltip:Show()
    end)
    sitWpManualBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    sitWpSaveManualBtn:SetScript("OnClick", SitCommitManualCoords)
    sitWpXEb:SetScript("OnEnterPressed", function() sitWpYEb:SetFocus() end)
    sitWpYEb:SetScript("OnEnterPressed", SitCommitManualCoords)
    sitWpXEb:SetScript("OnEscapePressed", function() sitWpManualRow:Hide() end)
    sitWpYEb:SetScript("OnEscapePressed", function() sitWpManualRow:Hide() end)

    sitWpPinBtn:SetScript("OnClick", function()
        local n3 = BNB.GetNote(noteID); if not n3 then return end
        local mapID = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
        if not mapID then BNB:Print("|cffff6666Cannot get map position.|r"); return end
        local pos = C_Map and C_Map.GetPlayerMapPosition and C_Map.GetPlayerMapPosition(mapID, "player")
        if not pos then BNB:Print("|cffff6666Cannot get map position.|r"); return end
        local px, py = pos:GetXY()
        local x = math.floor(px * 1000 + 0.5) / 10
        local y = math.floor(py * 1000 + 0.5) / 10
        local zone  = GetRealZoneText() or GetZoneText() or ""
        local title = (n3.title and n3.title ~= "") and n3.title or zone
        BNB.UpdateNote(noteID, { waypoint = { mapID=mapID, x=x, y=y, label=zone, title=title } })
        SitRefreshWaypointDisplay()
        BNB:Print(string.format("Waypoint pinned: %s %.1f, %.1f", title, x, y))
        if BNB.SyncNoteConfig then BNB.SyncNoteConfig(noteID) end
    end)
    sitWpPinBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(L["STICKY_WP_PIN_TIP_TITLE"], 1, 1, 1)
        GameTooltip:AddLine(L["STICKY_WP_PIN_TIP_BODY"], 0.78, 0.78, 0.78, true)
        GameTooltip:Show()
    end)
    sitWpPinBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    sitWpNavBtn:SetScript("OnClick", function()
        local n3 = BNB.GetNote(noteID); if not n3 then return end
        local wp = n3.waypoint
        if not (wp and wp.x and wp.y and wp.mapID) then
            BNB:Print("|cffff6666No waypoint set on this note.|r"); return
        end
        local wpTitle = wp.title or wp.label or "BigNoteBox"
        local handled = false
        if TomTom and TomTom.AddWaypoint then
            pcall(function() TomTom:AddWaypoint(wp.mapID, wp.x/100, wp.y/100, {title=wpTitle, from="BigNoteBox"}) end)
            handled = true
            BNB:Print(string.format("TomTom waypoint: %s (%.1f, %.1f)", wpTitle, wp.x, wp.y))
        end
        if not handled and C_Map and C_Map.SetUserWaypoint then
            local ok = pcall(function()
                local pt = UiMapPoint.CreateFromCoordinates(wp.mapID, wp.x/100, wp.y/100)
                C_Map.SetUserWaypoint(pt)
                if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then
                    C_SuperTrack.SetSuperTrackedUserWaypoint(true)
                end
            end)
            if ok then
                handled = true
                BNB:Print(string.format("Map pin set: %s (%.1f, %.1f)", wpTitle, wp.x, wp.y))
            end
        end
        if not handled then
            local wayStr = string.format("/way %s %.1f %.1f %s",
                wp.label or GetRealZoneText() or "", wp.x, wp.y, wpTitle)
            BNB:Print(string.format(L["STICKY_WP_NO_ADDON_COPY_FMT"], wayStr))
        end
    end)
    sitWpNavBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(L["STICKY_WP_NAV_TIP_TITLE"], 1, 1, 1)
        GameTooltip:AddLine(L["STICKY_WP_NAV_TIP_BODY"], 0.78, 0.78, 0.78, true)
        GameTooltip:Show()
    end)
    sitWpNavBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    sitWpClearBtn:SetScript("OnClick", function()
        BNB.UpdateNote(noteID, { _clear = {"waypoint"} })
        SitRefreshWaypointDisplay()
        if BNB.SyncNoteConfig then BNB.SyncNoteConfig(noteID) end
    end)
    sitWpClearBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(L["STICKY_WP_REMOVE_TIP"], 1, 1, 1); GameTooltip:Show()
    end)
    sitWpClearBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- ── Load current note binding (_loadCtx equivalent) ───────────────────────
    local function SitLoadCtx()
        local n3  = BNB.GetNote(noteID)
        local ctx = n3 and n3.context
        local cd  = n3 and n3.contextDisplay
        if cd == "sticky" or cd == "both" then sitSelDisplay = cd else sitSelDisplay = "popup" end
        SitSetDispText(SitGetDispLabel(sitSelDisplay))
        if sitDispDropdown and sitDispDropdown.GenerateMenu then sitDispDropdown:GenerateMenu() end
        local lv = n3 and n3.contextLeave
        sitSelLeave = (lv == "bt-minimize" or lv == "hide") and lv or "keep"
        SitSetLeaveText(SitGetLeaveLabel(sitSelLeave))
        if sitLeaveDropdown and sitLeaveDropdown.GenerateMenu then sitLeaveDropdown:GenerateMenu() end

        if ctx and ctx ~= "" then
            local kind, value
            if BNB.DecodeContext then kind, value = BNB.DecodeContext(ctx) end
            if kind then
                local dropLabel = SIT_TYPE_LABELS[1]
                for i, k in ipairs(SIT_TYPES) do if k == kind then dropLabel = SIT_TYPE_LABELS[i]; break end end
                sitSelType = kind
                SitSetTypeText(dropLabel)
                if sitTypeDropdown and sitTypeDropdown.GenerateMenu then sitTypeDropdown:GenerateMenu() end
                SitSelectType(kind)
                if sitValueEb then sitValueEb:SetText(value or "") end
                sitClearCtxBtn:Show()
            else
                sitSelType = "none"
                SitSetTypeText(SIT_TYPE_LABELS[1])
                if sitTypeDropdown and sitTypeDropdown.GenerateMenu then sitTypeDropdown:GenerateMenu() end
                SitSelectType("none"); sitClearCtxBtn:Hide()
            end
        else
            sitSelType = "none"
            SitSetTypeText(SIT_TYPE_LABELS[1])
            if sitTypeDropdown and sitTypeDropdown.GenerateMenu then sitTypeDropdown:GenerateMenu() end
            SitSelectType("none"); sitClearCtxBtn:Hide()
        end
        SitRefreshCurBind()
        SitRefreshWaypointDisplay()
        local n3b = BNB.GetNote(noteID)
        sitWpLeaveChk:SetChecked(n3b and n3b.wpClearOnLeave == true)
    end

    -- Expose so OpenStickySettings can refresh the Situation tab when the
    -- settings window is already open (cross-sync from NoteConfig saves).
    f._loadSituation = SitLoadCtx

    SitLoadCtx()
    FinalisePanel(ct3, sf3)
    local note = BNB.GetNote(noteID)
    local noteName = (note and note.title ~= "") and note.title or L["UNTITLED"]
    if f._titleLbl then
        f._titleLbl:SetText(string.format(L["STICKY_SETTINGS_TITLE_FMT"], noteName))
    elseif f.SetTitle then
        f:SetTitle(string.format(L["STICKY_SETTINGS_TITLE_FMT"], noteName))
    end
end

-- Open the detached settings window for a sticky note
local function OpenStickySettings(stickyFrame, noteID)
    if not stickyFrame or not noteID then return end

    -- Close alarm window if it's open (mutual exclusion for same note)
    if BNB.AlarmWindow and BNB.AlarmWindow.IsOpen and BNB.AlarmWindow.IsOpen() then
        BNB.AlarmWindow.Close()
    end

    local f = BuildStickySettingsWindow()
    _stickySettingsNoteID = noteID

    -- Populate content
    PopulateStickySettings(noteID)

    -- Select remembered tab (or default to General)
    if f._selectTab then f._selectTab(f._activeTab or 1) end

    -- ── Anchor settings window to the sticky ─────────────────────────────────
    -- Anchoring to stickyFrame means WoW moves settings for free when the sticky
    -- is dragged — exactly like Config anchors to BNB.mainFrame.
    -- Dragging the settings window calls StartMoving() which breaks the anchor;
    -- after that it floats freely (detached), and the sticky stays put.
    -- Rule: open to the right of the sticky if it fits, otherwise to the left.
    BNB.PlaceBeside(f, stickyFrame, SETTINGS_W)

    -- Sticky stays at normal alpha — we want to see our changes live
    stickyFrame:SetAlpha(1.0)

    -- Show settings with fade-in.
    -- Raise() ensures the settings panel sits above GameMenuFrame when the
    -- ESC menu is open — both are DIALOG strata; last-raised wins.
    f:Show()
    f:Raise()
    FadeFrame(f, 0, BNB.WindowAlpha(f), 0.25)
end

-- ── Public / StickyNote.lua entry points ──────────────────────────────────────
-- Close the sticky settings panel (called by ESC handler in MainWindow)
function SN.CloseSettings()
    CloseStickySettings()
end

-- Refresh the Situation tab of the sticky settings window if it is currently
-- open for the given noteID. Called by NoteConfig whenever it saves a
-- situation-related field so both windows stay in sync.
function SN.RefreshSettingsSituation(noteID)
    if not _stickySettingsFrame or not _stickySettingsFrame:IsShown() then return end
    if _stickySettingsNoteID ~= noteID then return end
    if _stickySettingsFrame._loadSituation then
        _stickySettingsFrame._loadSituation()
    end
end

-- True while the window is shown and editing this note.
function SN._IsSettingsOpenFor(noteID)
    local f = _stickySettingsFrame
    return f and f:IsShown() and _stickySettingsNoteID == noteID
end

-- Instant hide, no fade and no ApplyConfig: used when the sticky itself is
-- minimized or closed.
function SN._HideSettingsFor(noteID)
    if SN._IsSettingsOpenFor(noteID) then _stickySettingsFrame:Hide() end
end

SN._OpenSettings = OpenStickySettings

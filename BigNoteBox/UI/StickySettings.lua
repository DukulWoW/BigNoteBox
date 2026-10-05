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

local SETTINGS_W = 290   -- matches NoteConfig NCW (the Reference Box width)
-- Content starts just below the tab button bottoms (~y=-45 from frame top) + small pad
local SETTINGS_TAB_CONTENT_Y = 62
local SETTINGS_PAD = 12  -- matches NoteConfig PAD
local SETTINGS_CW = SETTINGS_W - SETTINGS_PAD - 28  -- matches NoteConfig CW_SCROLL (NCW - PAD - 28)

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

local SK_SS_TAB_GAP = 30   -- skin tab strip (24) + 6px gap below the title strip

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

    -- Shared shell (UI/ToolWindow.lua, CMP-02). Settings detaches freely when
    -- dragged (the drag re-anchors it to UIParent); the sticky stays put.
    local f = BNB.CreateToolWindow({
        name = "BigNoteBoxStickySettingsFrame", w = SETTINGS_W, h = 640,
        pad = SETTINGS_PAD, title = L["STICKY_SETTINGS_TITLE"],
        toplevel = true, escClose = true,
        onClose = function() CloseStickySettings() end,
    })
    local skinMode = f._isSkin
    local SK_SS_TITLE_H = BNB.TOOL_SKIN_TITLE_H
    -- used by MakeScrollPanel / MakePlainPanel below
    local tabContentY = skinMode and (SK_SS_TITLE_H + SK_SS_TAB_GAP) or SETTINGS_TAB_CONTENT_Y

    -- The Situation editor closes its own waypoint info popup
    f:HookScript("OnHide", function()
        if BNB.StickyBgPicker then BNB.StickyBgPicker.Close() end   -- ALL-110
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
    -- The Situation tab is the shared editor (UI/SituationEditor.lua, CMP-03),
    -- built once; PopulateStickySettings only loads the note into it
    f._sitEditor = BNB.CreateSituationEditor(ct3, {
        padL = 0, padR = 0, ddR = 0, top = -8, bottom = 6,
        width = SETTINGS_CW, host = f,
    })

    _stickySettingsFrame = f
    return f
end

-- Populate settings content for a specific noteID
-- Destroys and recreates content children each time (simple, no stale state)
local function PopulateStickySettings(noteID)
    local f   = _stickySettingsFrame
    local ct1 = f._ct1   -- General tab content
    local ct2 = f._ct2   -- Appearance tab content
    local sf1 = f._sTabPanels[1]
    local sf2 = f._sTabPanels[2]

    -- Destroy old content children (General, Appearance; Situation is built once)
    for _, ct in ipairs({ct1, ct2}) do
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

    -- The stacked slider with Reset used everywhere (ALL-121): label and
    -- value on one line, slider at full width under them. default = what
    -- Reset puts back, fmt = the value text (unit included), onReset = Reset
    -- clears a saved value instead. SetAlpha / SetEnabled on the result.
    local PCT = function(v) return v .. "%" end
    local function MakeSlider(ct, label, minV, maxV, initV, onChange, default, fmt, onReset)
        local y = ct._y or -8
        local sl = BNB.CreateStackedSlider(ct, SETTINGS_CW, {
            label = label, min = minV, max = maxV, value = initV, default = default,
            fmt = fmt, onChange = onChange, onReset = onReset,
        })
        sl:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
        ct._y = y - (BNB.STACKED_SLIDER_H + 6)
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

    -- Minimal sticky / ESC pin / plain text / lock: state buttons, the label
    -- says what a click does (ALL-257, same grid as Note Settings ALL-256).
    -- Plain text applies to rich notes only (greyed for a plain note).
    local note         = BNB.GetNote(noteID)
    local noteIsRich   = BNB.AdvancedMode and BNB.AdvancedMode.IsRich(note)
    local SyncPlainOnlyControls   -- defined below, with the controls it greys

    local function SetEscOnly(checked)
        -- Tri-state: nil=unset, true=ESC-only, false=explicitly normal.
        -- Write false (not nil) when turning off so global default doesn't re-apply.
        cfg.escOnly = checked
        SaveCfg(noteID, cfg)
        local sf = openFrames[noteID]
        if sf then
            sf._escOnly = checked and true or false
            EnsureESCHook()
            if checked then
                -- Switching to ESC-only: hide from world, set correct strata.
                sf:SetFrameStrata("FULLSCREEN_DIALOG")
                if not (GameMenuFrame and GameMenuFrame:IsShown()) then
                    sf:Hide()
                    if sf._miniTile then sf._miniTile:Hide() end
                end
            else
                -- Switching back to normal: restore strata and show in world.
                sf:SetFrameStrata(BNB.Sticky.Strata())
                if not sf._minimized then
                    sf:Show(); sf:Raise()
                end
            end
        end
        -- An ESC-screen sticky is not one Hide all hides (ALL-237)
        if BNB.RefreshStickyEyeBtn then BNB.RefreshStickyEyeBtn() end
    end

    -- The sticky's right-click Lock / Unlock writes into this same cfg table
    -- and refreshes the labels (SN.SetLocked, ALL-257)
    f._cfg = cfg
    ct1._y, f._refreshStates = BNB.CreateStateButtonGrid(ct1, ct1._y, SETTINGS_CW, {
        -- Minimal sticky (saved as focusMode): hides title, icon and border
        -- (fade in on hover), compact padding, rich notes as plain text,
        -- compact task rows
        { text = function()
              return cfg.focusMode and L["STICKY_STATE_NORMAL"] or L["STICKY_STATE_MINIMAL"] end,
          tip  = function() return L["STICKY_FOCUS_MODE_LABEL"], L["STICKY_FOCUS_MODE_TIP"] end,
          onClick = function()
              cfg.focusMode = (not cfg.focusMode) and true or nil
              SaveCfg(noteID, cfg)
              if stickyFrame then ApplyConfig(stickyFrame, noteID) end
          end },
        -- ESC pin: hidden in the game world, shown only while the ESC menu is open
        { text = function()
              return cfg.escOnly and L["STICKY_STATE_ESC_UNPIN"] or L["STICKY_STATE_ESC_PIN"] end,
          tip  = function() return L["STICKY_ESC_PIN_LABEL"], L["STICKY_ESC_PIN_TIP"] end,
          onClick = function() SetEscOnly(not cfg.escOnly) end },
        -- Plain text: the sticky renders the raw text instead of the
        -- SimpleHTML view, and text color/style controls become active
        { text = function()
              return cfg.richPlainText and L["NC_STATE_RICH"] or L["NC_STATE_NORMAL"] end,
          tip  = function()
              return L["STICKY_RICH_PLAIN_LABEL"],
                  noteIsRich and L["STICKY_RICH_PLAIN_TIP"] or L["STICKY_RICH_PLAIN_RICH_ONLY"]
          end,
          enabled = function() return noteIsRich end,
          onClick = function()
              cfg.richPlainText = (not cfg.richPlainText) and true or nil
              SaveCfg(noteID, cfg)
              SyncPlainOnlyControls()
              -- Re-render the sticky with the new mode
              if BNB.Sticky and BNB.Sticky.RefreshNote then
                  BNB.Sticky.RefreshNote(noteID)
              end
          end },
        -- Lock sticky: position and size stay put (UI/StickyNote.lua StickyLocked)
        { text = function()
              return cfg.locked and L["NC_LOCK_UNLOCK_BTN"] or L["NC_LOCK_LOCK_BTN"] end,
          tip  = function() return L["STICKY_LOCK_LABEL"], L["STICKY_LOCK_TIP"] end,
          onClick = function() SN.SetLocked(noteID, not cfg.locked) end },
    })
    ct1._y = ct1._y - 8
    Rule(ct1)
    ct1._y = ct1._y - 4

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
    function SyncPlainOnlyControls()
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
                if w._slider then w:SetEnabled(isPlain)   -- stacked slider
                elseif w.EnableMouse then w:EnableMouse(isPlain) end
            end)
        end
    end

    Rule(ct1)
    Sec(ct1, L["NC_HDR_FONT"])

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

    -- Reset clears the note's own size, so it follows the global one again
    local globalFontSize = (BigNoteBoxDB and BigNoteBoxDB.fontSize) or BNB.DEFAULTS.fontSize
    local function ApplyStickyFontSize(v)
        if stickyFrame and stickyFrame._bodyEb then
            local path = select(1, stickyFrame._bodyEb:GetFont())
            if path then pcall(function() stickyFrame._bodyEb:SetFont(path, BNB.FontPx(path, v), "") end) end
        end
    end
    local fontSizeSl = MakeSlider(ct1, L["STICKY_FONT_SIZE"], 8, 24,
        cfg.fontSize or globalFontSize,
        function(v)
            cfg.fontSize = v; SaveCfg(noteID, cfg)
            ApplyStickyFontSize(v)
        end, globalFontSize, nil,
        function()
            cfg.fontSize = nil; SaveCfg(noteID, cfg)
            ApplyStickyFontSize(globalFontSize)
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
    Sec(ct2, L["STICKY_HDR_BACKGROUND"])
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
    BNB.StickyBG.LoadClassic()   -- lists BigNoteBox_BGs' old TGAs too (ALL-110)
    local curTexKey   = cfg.bgTexture or "none"
    local SBP = BNB.StickyBgPicker

    -- [<] [name] [>] (ALL-110 part 2b, Dukul 2026-09-27): the name opens the
    -- thumbnail grid (UI/StickyBgPicker.lua), the arrows step through the
    -- whole list and wrap. A saved key whose texture is unavailable
    -- (BigNoteBox_BGs missing) reads "None"; the key stays saved until
    -- another is picked.
    local TEX_ARW = 22
    local texPrev = BNB.CreateButton(nil, ct2, "<", TEX_ARW, 22)
    local texBtn  = BNB.CreateButton(nil, ct2, BgTextureLabel(curTexKey),
        SETTINGS_CW - 2 * (TEX_ARW + 4), 22)
    local texNext = BNB.CreateButton(nil, ct2, ">", TEX_ARW, 22)
    texPrev:SetPoint("TOPLEFT", ct2, "TOPLEFT", 0, ct2._y)
    texBtn:SetPoint("LEFT", texPrev, "RIGHT", 4, 0)
    texNext:SetPoint("LEFT", texBtn, "RIGHT", 4, 0)
    ct2._y = ct2._y - 30

    local function SetTexKey(key)
        -- Plain colour -> a texture: Colorize starts at 0 %, the art in its
        -- own colours. At 100 % a dark note colour tinted every texture
        -- near black and the addon looked broken (Dukul 2026-10-02). The
        -- note colour is kept (base under the art, and None again). Texture
        -- to texture keeps the player's Colorize.
        if not BNB.StickyBG.Get(curTexKey).file and BNB.StickyBG.Get(key).file then
            cfg.bgColorOpacity = 0
        end
        curTexKey = key
        cfg.bgTexture = key
        SaveCfg(noteID, cfg)
        SN.SetBgOverride(nil)   -- ends a Background Lab trial (ALL-110)
        texBtn:SetText(BgTextureLabel(key))
        if stickyFrame then ApplyConfig(stickyFrame, noteID) end
        SyncColorizeSlider(key)
    end
    local function StepTex(d)
        local cur, idx = BNB.StickyBG.Get(curTexKey).key, 1
        for i, t in ipairs(BG_TEXTURES) do
            if t.key == cur then idx = i; break end
        end
        SetTexKey(BG_TEXTURES[(idx - 1 + d) % #BG_TEXTURES + 1].key)
        if SBP then SBP.Refresh() end
    end
    local texHandlers = {
        cfg = function() return cfg end,
        get = function() return curTexKey end,
        set = SetTexKey,
    }
    texPrev:SetScript("OnClick", function() StepTex(-1) end)
    texNext:SetScript("OnClick", function() StepTex(1) end)
    texBtn:SetScript("OnClick", function()
        if SBP then SBP.Open(noteID, _stickySettingsFrame, texHandlers) end
    end)
    for btn, tip in pairs({ [texPrev] = "STICKY_BG_PREV", [texBtn] = "STICKY_BG_BROWSE_TIP",
                            [texNext] = "STICKY_BG_NEXT" }) do
        local text = L[tip]
        btn:HookScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(text, 1, 1, 1)
            GameTooltip:Show()
        end)
        btn:HookScript("OnLeave", function() GameTooltip:Hide() end)
    end
    -- Settings rebuilt (Randomize, another note): an open grid follows the
    -- new row, or closes when it belongs to another note
    if SBP then
        if SBP.IsOpenFor(noteID) then SBP.Rebind(noteID, texHandlers) else SBP.Close() end
    end

    -- "Colorize texture %" — lerps the backdrop tint between raw paper (0%, white
    -- tint) and the full chosen colour (100%). Greyed out when texture is "None".
    local slColorize = MakeSlider(ct2, L["STICKY_COLORIZE_TEXTURE"], 0, 100,
        math.floor((cfg.bgColorOpacity or 1.0) * 100),
        function(v)
            cfg.bgColorOpacity = v / 100
            SaveCfg(noteID, cfg)
            if stickyFrame then ApplyConfig(stickyFrame, noteID) end
        end, 0, PCT)

    -- "Texture brightness %" (ALL-110, Dukul 2026-09-27): -100..100, 0 = the
    -- art as it is. Below 0 darkens it, above 0 adds an ADD-blend copy on top
    -- (BNB.BgLayer.SetColors). Greyed with Colorize.
    local slBright = MakeSlider(ct2, L["STICKY_TEX_BRIGHTNESS"], -100, 100,
        math.floor((cfg.bgBrightness or 0) * 100 + 0.5),
        function(v)
            cfg.bgBrightness = (v ~= 0) and v / 100 or nil
            SaveCfg(noteID, cfg)
            if stickyFrame then ApplyConfig(stickyFrame, noteID) end
        end, 0, PCT)

    -- Greyed while the note draws no texture: None, or a saved key that is
    -- unavailable here (BigNoteBox_BGs missing, art of the other client)
    SyncColorizeSlider = function(texKey)
        local disabled = not BNB.StickyBG.Get(texKey).file
        -- SetTexKey may have reset Colorize; silent, so nothing is saved twice
        pcall(function() slColorize:SetValue(math.floor((cfg.bgColorOpacity or 1.0) * 100), true) end)
        for _, sl in ipairs({ slColorize, slBright }) do
            pcall(function() sl:SetAlpha(disabled and 0.4 or 1.0) end)
            if sl.SetEnabled then
                pcall(function() sl:SetEnabled(not disabled) end)
            end
        end
    end
    SyncColorizeSlider(curTexKey)

    Rule(ct2)
    Sec(ct2, L["STICKY_OPACITY_SECTION"])
    local textOpacitySl = MakeSlider(ct2, L["STICKY_TEXT_OPACITY"], 10, 100,
        math.floor((cfg.textAlpha or 1.0) * 100),
        function(v)
            cfg.textAlpha = v/100; SaveCfg(noteID, cfg)
            if stickyFrame and stickyFrame._bodyEb then
                pcall(function() stickyFrame._bodyEb:SetAlpha(cfg.textAlpha) end)
            end
        end, 100, PCT)
    plainOnlyWidgets[#plainOnlyWidgets+1] = textOpacitySl
    MakeSlider(ct2, L["STICKY_BG_OPACITY"], 0, 100,
        math.floor((cfg.alpha or 0.96) * 100),
        function(v)
            cfg.alpha = v/100; SaveCfg(noteID, cfg)
            if stickyFrame then ApplyBgAlpha(stickyFrame, cfg.alpha) end
        end, 96, PCT)

    Rule(ct2)
    Sec(ct2, L["NC_HDR_BORDER"])
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
    local slThickness = MakeSlider(ct2, L["STICKY_BORDER_THICKNESS"], 1, 200, cfg.borderScale or 100,
        function(v)
            cfg.borderScale = math.floor(v)
            SaveCfg(noteID, cfg)
            if stickyFrame then ApplyConfig(stickyFrame, noteID) end
        end, 100, PCT)

    -- Border Offset slider
    local slOffset = MakeSlider(ct2, L["STICKY_BORDER_OFFSET"], 0, 12, cfg.borderOffset or 2,
        function(v)
            cfg.borderOffset = math.floor(v)
            SaveCfg(noteID, cfg)
            if stickyFrame then ApplyConfig(stickyFrame, noteID) end
        end, 2, function(v) return v .. " px" end)

    -- Border Brightness slider
    local slBrightness = MakeSlider(ct2, L["STICKY_BORDER_BRIGHTNESS"], 10, 500, cfg.borderBrightness or 100,
        function(v)
            cfg.borderBrightness = math.floor(v)
            SaveCfg(noteID, cfg)
            if stickyFrame then ApplyConfig(stickyFrame, noteID) end
        end, 100, PCT)

    -- Grey out the three sliders when border is "None" (they have no effect).
    -- Assigned here (after sliders exist) but captured by the closures above
    -- via the forward declaration at the top of the Border section.
    SyncBorderSliders = function(borderName)
        local disabled = (not borderName or borderName == "None")
        local a = disabled and 0.35 or 1.0
        for _, sl in ipairs({ slThickness, slOffset, slBrightness }) do
            if sl then
                sl:SetAlpha(a)
                sl:SetEnabled(not disabled)
            end
        end
    end
    SyncBorderSliders(cfg.borderName)

    FinalisePanel(ct2, sf2)

    -- Apply greying to all plain-only controls now that both tabs are fully built.
    -- (Must run after tab 2 so textOpacitySl is in plainOnlyWidgets.)
    SyncPlainOnlyControls()

    -- TAB 3: Situation (built once in BuildStickySettingsWindow)
    f._sitEditor:Load(noteID)
    local note = BNB.GetNote(noteID)
    local noteName = (note and note.title ~= "") and note.title or L["UNTITLED"]
    f:SetWindowTitle(string.format(L["STICKY_SETTINGS_TITLE_FMT"], noteName))
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

-- The cfg table the open settings window edits for this note, so a change
-- made from elsewhere lands in it instead of being overwritten by its next
-- save; and a refresh of its state button labels (ALL-257)
function SN._SettingsCfg(noteID)
    if SN._IsSettingsOpenFor(noteID) then return _stickySettingsFrame._cfg end
end
function SN._RefreshSettingsStates(noteID)
    local f = _stickySettingsFrame
    if SN._IsSettingsOpenFor(noteID) and f._refreshStates then f._refreshStates() end
end

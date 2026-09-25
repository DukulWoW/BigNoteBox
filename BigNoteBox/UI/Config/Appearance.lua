-- BigNoteBox UI/Config/Appearance.lua - Settings Appearance tab
-- Split out of ConfigWindow.lua (ALL-65.10).

local BNB = BigNoteBox
local L   = BNB.L

local K = BNB._ConfigKit
local CONTENT_W, ROW_H, ROW_GAP = K.CONTENT_W, K.ROW_H, K.ROW_GAP
local AddRule, AddHeader, AddCheck, AddSlider, BuildLSMFontDropdown = K.AddRule, K.AddHeader, K.AddCheck, K.AddSlider, K.BuildLSMFontDropdown

-- ─────────────────────────────────────────────────────────────────────────────
-- FONT PICKER  (bundled font cards + WoW Default checkbox)
-- ─────────────────────────────────────────────────────────────────────────────
local fontPickerBtns = {}
local _refreshLSMDropdown = nil   -- this window's dropdown refresh (ALL-29 fix)

local _refreshFontHL     = nil
local _refreshFontLabels = nil   -- re-applies TTF paths after renderer is ready

local function BuildFontPicker(ct, y)
    local PICKER_H = 48
    local GAP      = 4    -- vertical gap between rows
    local COL_GAP  = 6    -- horizontal gap between columns
    local CARD_W   = math.floor((CONTENT_W - COL_GAP) / 2)
    -- LSM fonts are shown in the dropdown below; WoW Default has its own checkbox
    -- below the grid. Both are excluded from the card grid, which shows the
    -- active language's font set (ALL-14).
    local fonts = BNB.GetPickerFonts()
    fontPickerBtns = {}
    local _wowCb

    local function Highlight()
        local cur = BNB.GetEffectiveFontID()
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
        if _wowCb then _wowCb:SetChecked(cur == "wow") end
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
            if BNB.GetEffectiveFontID() ~= def.id then
                self:SetBackdropColor(0.10, 0.12, 0.10, 0.95)
                self:SetBackdropBorderColor(0.35, 0.55, 0.35, 1)
            end
        end)
        btn:SetScript("OnLeave", Highlight)
        btn:SetScript("OnClick", function()
            BNB.ApplyFont(def.id, nil)
            Highlight()
            if _refreshLSMDropdown then _refreshLSMDropdown() end
        end)

        local nameLbl = btn:CreateFontString(nil, "OVERLAY")
        nameLbl:SetPoint("TOPLEFT",  btn, "TOPLEFT",  7, -7)
        nameLbl:SetPoint("TOPRIGHT", btn, "TOPRIGHT", -7, -7)
        nameLbl:SetJustifyH("LEFT"); nameLbl:SetHeight(18)
        BNB.SetFontSafe(nameLbl, def.bold, 13, "GameFontNormal")
        nameLbl:SetText(def.label)

        local prevLbl = btn:CreateFontString(nil, "OVERLAY")
        prevLbl:SetPoint("BOTTOMLEFT",  btn, "BOTTOMLEFT",  7, 7)
        prevLbl:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -7, 7)
        prevLbl:SetJustifyH("LEFT"); prevLbl:SetHeight(14)
        BNB.SetFontSafe(prevLbl, def.regular, 11, "GameFontNormalSmall")
        prevLbl:SetTextColor(0.62, 0.62, 0.62); prevLbl:SetText(def.preview or "")

        fontPickerBtns[#fontPickerBtns + 1] = { btn=btn, id=def.id, nameLbl=nameLbl, prevLbl=prevLbl, def=def }
    end

    -- Advance y past the full grid. The grid always reserves its 4 rows so a
    -- smaller font set keeps the layout; free rows carry the font pack hint.
    local usedRows = math.ceil(#fonts / 2)
    local gridRows = math.max(BNB.FONT_GRID_ROWS, usedRows)
    BNB.AddFontPackHint(ct, ct, 0, y - usedRows * (PICKER_H + GAP),
        CONTENT_W, (gridRows - usedRows) * (PICKER_H + GAP) - GAP)
    y = y - gridRows * (PICKER_H + GAP) - 4

    -- WoW Default checkbox, below the grid instead of a 9th card. Latin set only:
    -- the other sets' cards are WoW's own fonts. The row is kept either way.
    if not BNB.ShowWoWFontCheckbox() then
        y = y - (ROW_H + ROW_GAP)
        Highlight()
        return y
    end
    local wowCb = CreateFrame("CheckButton", nil, ct, "UICheckButtonTemplate")
    wowCb:SetSize(24, 24)
    wowCb:SetPoint("TOPLEFT", ct, "TOPLEFT", -2, y + 2)
    wowCb:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(L["FONT_USE_WOW_DEFAULT_TIP"], 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    wowCb:SetScript("OnLeave", function() GameTooltip:Hide() end)
    wowCb:SetScript("OnClick", function(self)
        BNB.ApplyFont(self:GetChecked() and "wow" or "notoserif", nil)
        Highlight()
        if _refreshLSMDropdown then _refreshLSMDropdown() end
    end)
    local wowLbl = ct:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    wowLbl:SetPoint("LEFT",  wowCb, "RIGHT", 4, 0)
    wowLbl:SetPoint("RIGHT", ct,    "RIGHT", 0, 0)
    wowLbl:SetJustifyH("LEFT"); wowLbl:SetHeight(ROW_H); wowLbl:SetText(L["FONT_USE_WOW_DEFAULT"])
    _wowCb = wowCb
    y = y - (ROW_H + ROW_GAP)

    Highlight()
    return y
end

-- ─────────────────────────────────────────────────────────────────────────────
-- TAB 2 — APPEARANCE
-- ─────────────────────────────────────────────────────────────────────────────
local function BuildAppearanceTab(sf, ct)
    local db = BigNoteBoxDB
    local y  = -8

    -- ── Skins ─────────────────────────────────────────────────────────────────
    y = AddHeader(ct, y, L["CFG_HDR_SKINS"])

    local skinDesc = ct:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    skinDesc:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
    skinDesc:SetWidth(CONTENT_W); skinDesc:SetJustifyH("LEFT")
    skinDesc:SetWordWrap(true); skinDesc:SetHeight(28)
    skinDesc:SetTextColor(0.60, 0.60, 0.60)
    skinDesc:SetText(L["CFG_SKIN_DESC"])
    y = y - 32

    -- Enable skin mode checkbox
    local skinCb = CreateFrame("CheckButton", nil, ct, "UICheckButtonTemplate")
    skinCb:SetSize(24, 24)
    skinCb:SetPoint("TOPLEFT", ct, "TOPLEFT", -2, y + 2)
    skinCb:SetChecked(db.skinMode == true)

    local skinCbLbl = ct:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    skinCbLbl:SetPoint("LEFT", skinCb, "RIGHT", 4, 0)
    skinCbLbl:SetJustifyH("LEFT"); skinCbLbl:SetHeight(ROW_H)
    skinCbLbl:SetText(L["CFG_SKIN_ENABLE"])

    skinCb:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(L["CFG_SKIN_ENABLE"], 1, 1, 1)
        GameTooltip:AddLine(L["CFG_SKIN_ENABLE_TIP"], 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    skinCb:SetScript("OnLeave", function() GameTooltip:Hide() end)

    y = y - (ROW_H + ROW_GAP)

    -- Preset dropdown (only active when skin mode is enabled)
    local SKIN_PRESETS = {
        { key = "obsidian",   label = L["CFG_SKIN_PRESET_OBSIDIAN"]  },
        { key = "void",       label = L["CFG_SKIN_PRESET_VOID"]            },
        { key = "dragonfire", label = L["CFG_SKIN_PRESET_DRAGONFIRE"]         },
        { key = "arcane",     label = L["CFG_SKIN_PRESET_ARCANE"]            },
        { key = "fel",        label = L["CFG_SKIN_PRESET_FEL"]              },
        { key = "titan",      label = L["CFG_SKIN_PRESET_TITAN"]             },
        { key = "icecrown",   label = L["CFG_SKIN_PRESET_ICECROWN"]          },
        { key = "holy",       label = L["CFG_SKIN_PRESET_HOLY"]             },
        { key = "azshara",    label = L["CFG_SKIN_PRESET_AZSHARA"]          },
        { key = "ragnaros",   label = L["CFG_SKIN_PRESET_RAGNAROS"]         },
        { key = "earthen",    label = L["CFG_SKIN_PRESET_EARTHEN"]          },
        { key = "argent",     label = L["CFG_SKIN_PRESET_ARGENT"]           },
        { key = "oled",       label = L["CFG_SKIN_PRESET_OLED"]             },
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
    skinPresetLbl:SetText(L["CFG_SKIN_PRESET"])
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
    skinBrightnessLbl:SetText(L["CFG_SKIN_BRIGHTNESS"])
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

    local skinBrightnessReset = BNB.CreateButton(nil, ct, L["RESET"], 52, 20)
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
    skinOpacityLbl:SetText(L["CFG_SKIN_OPACITY"])
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

    local skinOpacityReset = BNB.CreateButton(nil, ct, L["RESET"], 52, 20)
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
    skinRandomizeBrightnessCb.text:SetText(L["CFG_SKIN_RAND_BRIGHTNESS"])
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
        GameTooltip:AddLine(L["CFG_SKIN_RAND_BRIGHTNESS"], 1, 0.82, 0)
        GameTooltip:AddLine(L["CFG_SKIN_RAND_BRIGHTNESS_TIP"], 1, 1, 1, true)
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
            and L["CFG_SKIN_MODE_ON_MSG"]
            or  L["CFG_SKIN_MODE_OFF_MSG"]
        StaticPopup_Show("BNB_SKIN_MODE_TOGGLE", msg)
    end)

    AddRule(ct, y); y = y - 18

    y = AddHeader(ct, y, L["CONFIG_FONT_FAMILY"])
    y = BuildFontPicker(ct, y)
    y = y - 4

    -- CJK clients (ALL-22): the bundled fonts have no CJK glyphs, so say which one does.
    -- Only while the Latin set shows; a CJK font set (ALL-14) has its own cards.
    if BNB.IsCJKClient and BNB.IsCJKClient() and BNB.GetActiveFontSet() == "latin" then
        local hint = ct:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        hint:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
        hint:SetWidth(CONTENT_W)
        hint:SetJustifyH("LEFT")
        hint:SetTextColor(0.65, 0.65, 0.65)
        hint:SetText(L["CFG_FONT_CJK_HINT"])
        y = y - math.ceil(hint:GetStringHeight() or 12) - 8
    end

    -- LSM font dropdown: appears below the bundled card grid when lsmFonts is on
    y, _refreshLSMDropdown = BuildLSMFontDropdown(ct, y,
        -- getter: returns the current global font choice if it is an LSM font, else nil
        function()
            local choice = BNB.GetFontChoice()
            local def = choice and BNB.GetFontDef and BNB.GetFontDef(choice)
            return (def and def._isLSM and choice == def.id) and choice or nil
        end,
        -- setter: nil resets to the set default (bundled cards take over); path picks LSM font
        function(path)
            if path then
                if BNB.ApplyFont then BNB.ApplyFont(path, nil) end
            else
                if BNB.ApplyFont then BNB.ApplyFont(BNB.GetFontSetDefault(), nil) end
            end
            if _refreshFontHL then _refreshFontHL() end
        end)
    y = y - 4

    y = AddSlider(ct, y, L["CONFIG_FONT_SIZE"], 9, 22,
        function() return db.fontSize or 13 end,
        function(v) BNB.ApplyFont(nil, v) end,
        L["CFG_FONTSIZE_TIP"])

    y = AddRule(ct, y) - 4

    -- Note list display mode — WowStyle1DropdownTemplate or cycling button fallback
    y = AddHeader(ct, y, L["CFG_HDR_LIST_DISPLAY_MODE"])

    local MODE_ITEMS = {
        { key = "normal",   label = L["CFG_LISTMODE_NORMAL"] },
        { key = "compact",  label = L["CFG_LISTMODE_COMPACT"] },
        { key = "spacious", label = L["CFG_LISTMODE_SPACIOUS"] },
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
            GameTooltip:AddLine(L["CFG_ROWHEIGHT_TIP_TITLE"], 1, 1, 1)
            GameTooltip:AddLine(L["CFG_ROWHEIGHT_NORMAL"], 0.8, 0.8, 0.8, true)
            GameTooltip:AddLine(L["CFG_ROWHEIGHT_COMPACT"], 0.8, 0.8, 0.8, true)
            GameTooltip:AddLine(L["CFG_ROWHEIGHT_SPACIOUS"], 0.8, 0.8, 0.8, true)
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
    y = AddHeader(ct, y, L["CFG_HDR_TIMESTAMP_FORMAT"])

    local DATE_FORMATS = {
        { key = "relative",   label = L["CFG_DATEFMT_RELATIVE"] },
        { key = "YYYY-MM-DD", label = L["CFG_DATEFMT_YMD"] },
        { key = "DD-MM-YYYY", label = L["CFG_DATEFMT_DMY"] },
        { key = "MM-DD-YYYY", label = L["CFG_DATEFMT_MDY"] },
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
    y = AddCheck(ct, y, L["CFG_CHK_24H_LABEL"],
        function() return db.use24Hour ~= false end,
        function(v)
            db.use24Hour = v
            if BNB._currentNoteID and BNB.LoadNoteInEditor then
                BNB.LoadNoteInEditor(BNB._currentNoteID)
            end
        end,
        L["CFG_CHK_24H_TIP"])

    sf:FinaliseHeight(math.abs(y) + 12)
end

-- Called by RefreshConfigFonts in ConfigWindow.lua (window show, Appearance
-- tab show): re-applies the card TTF paths and the highlight.
function K.RefreshFontPicker()
    if _refreshFontLabels then _refreshFontLabels() end
    if _refreshFontHL     then _refreshFontHL()     end
end

K.BUILDERS.appearance = BuildAppearanceTab

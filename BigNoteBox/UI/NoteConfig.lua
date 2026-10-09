-- BigNoteBox UI/NoteConfig.lua — Per-note configuration window
--
-- Three tabs: General | Appearance | Situation
-- Title: "Editing: <note name>"  — updates live as user types
-- Opens to the left of the main window.
-- ESC closes this before the main window.
--
-- ICONS: 180 curated icons covering notes, books, quests, professions,
-- raids, dungeons, battlegrounds, locations, combat, and misc.
-- Uses standard Interface\Icons paths that work on all WoW clients.

local BNB = BigNoteBox
local L   = BNB.L

-- ── Constants ─────────────────────────────────────────────────────────────────
local NCW     = 290   -- same width as the Reference Box (Dukul 2026-10-01)
-- Tab buttons (PanelTopTabButtonTemplate) sit at y=-25, are ~20px tall, ending ~y=-45.
-- TAB_CONTENT_Y = distance from frame top to content start.
-- 60 (TITLE_H) - 25 (tab y-offset from top) + 20 (tab height) + 8 (padding) = 63
local TAB_CONTENT_Y = 63
local PAD     = 12
-- Width: window minus left pad minus right margin (no tab scrolls, ALL-318)
local CW      = NCW - PAD - 8

-- ── Module state ──────────────────────────────────────────────────────────────
local ncFrame   = nil
local _noteID   = nil
local tabBtns   = {}
local tabPanels = {}
local NUM_TABS  = 3
local TAB_GEN   = 1
local TAB_APP   = 2
local TAB_SIT   = 3

-- ── Helpers ───────────────────────────────────────────────────────────────────
local function GetNote()  return _noteID and BNB.GetNote(_noteID) end
local function Save(fields)
    if not _noteID then return end
    BNB.UpdateNote(_noteID, fields)
    if BNB.Sticky and BNB.Sticky.RefreshNote then BNB.Sticky.RefreshNote(_noteID) end
end

local function RefreshTitle()
    if not ncFrame then return end
    local liveTitle = nil
    if BNB._currentNoteID == _noteID and BNB._editorTitle then
        local t
        if BNB._editorTitle.GetRealText then
            t = BNB._editorTitle:GetRealText()
        else
            t = BNB._editorTitle:GetText()
        end
        if t and t ~= "" then liveTitle = t end
    end
    local note = GetNote()
    local name = liveTitle
        or (note and note.title ~= "" and note.title)
        or L["UNTITLED"]
    -- Truncate long titles so they don't overflow the window titlebar
    if #name > 23 then name = name:sub(1, 20) .. "..." end
    ncFrame:SetWindowTitle(name)
end

-- Register sync callback so editor pushes live title updates
BNB._syncNoteConfigTitle = function()
    if ncFrame and ncFrame:IsShown() then RefreshTitle() end
end

-- ── Plain (non-scrolling) tab panel ──────────────────────────────────────────
-- Most tabs don't need a scrollbar. Use a plain Frame for those.
local function MakePlainPanel(parent, tabContentY)
    tabContentY = tabContentY or TAB_CONTENT_Y
    local p = CreateFrame("Frame", nil, parent)
    p:SetPoint("TOPLEFT",     parent, "TOPLEFT",  PAD, -tabContentY)
    p:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -PAD, 4)
    p:Hide()
    return p
end

-- Layout micro-helpers
local function Hdr(parent, y, text)
    local l = parent:CreateFontString(nil, "OVERLAY", "BNBFontNormal")
    l:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, y)
    BNB.SetHeaderColor(l); l:SetText(text)
    return y - 20
end
local function Rule(parent, y)
    BNB.CreateRule(parent, y)
    return y - 10
end

-- ─────────────────────────────────────────────────────────────────────────────
-- TAB 1 — GENERAL
-- ─────────────────────────────────────────────────────────────────────────────
local function BuildGeneralTab(panel)
    local y = -4

    -- Pin / Favorite / Lock / Rich note: state buttons, the label says what a
    -- click does (ALL-256). Pin, favorite and lock go through the list's
    -- NOTE_ACTIONS, so they act exactly as the right-click menu does.
    local function Act(key)
        if not _noteID then return end
        local K = BNB._NoteListKit
        if K and K.NOTE_ACTIONS[key] then K.NOTE_ACTIONS[key](_noteID) end
        if BNB.Sticky and BNB.Sticky.RefreshNote then BNB.Sticky.RefreshNote(_noteID) end
    end
    local function IsLocked()
        local n, K = GetNote(), BNB._NoteListKit
        return n and K and K.NoteIsLocked(n) or false
    end
    local _refreshStates
    y, _refreshStates = BNB.CreateStateButtonGrid(panel, y, CW, {
        { text = function() local n = GetNote()
              return (n and n.pinned) and L["NC_STATE_UNPIN"] or L["NC_STATE_PIN"] end,
          tip  = function() return L["NC_PIN_TOP_LABEL"], L["NC_PIN_TOP_TIP"] end,
          onClick = function() Act("pin") end },
        { text = function() local n = GetNote()
              return (n and n.favorited) and L["NC_STATE_UNFAV"] or L["NC_STATE_FAV"] end,
          tip  = function() return L["NC_FAVORITE_LABEL"], L["NC_FAVORITE_TIP"] end,
          onClick = function() Act("fav") end },
        { text = function() return IsLocked() and L["NC_LOCK_UNLOCK_BTN"] or L["NC_LOCK_LOCK_BTN"] end,
          tip  = function()
              return L["NC_HDR_LOCK"], IsLocked() and L["NC_LOCK_CLICK_UNLOCK_TIP"] or L["NC_LOCK_CLICK_LOCK_TIP"]
          end,
          onClick = function()
              Act("lock")
              if BNB.RefreshEditorLock then BNB.RefreshEditorLock() end
          end },
        { text = function() local n = GetNote()
              return (n and n.richMode) and L["NC_STATE_NORMAL"] or L["NC_STATE_RICH"] end,
          tip  = function() return L["NC_RICH_NOTE_LABEL"], L["NC_RICH_NOTE_TIP"] end,
          enabled = function() return BNB.RichEnabled() end,   -- Rich Notes module (ALL-343)
          onClick = function()
              local n = GetNote(); if not n then return end
              if not n.richMode then
                  Save({richMode = true})
                  if BNB.LoadNoteInEditor and BNB._currentNoteID == _noteID then
                      BNB.LoadNoteInEditor(_noteID)
                  end
              elseif BNB.AdvancedMode then
                  -- Confirms before stripping tags; the label follows NoteChanged
                  BNB.AdvancedMode.ConvertToPlain(_noteID)
              else
                  Save({richMode = false})
                  if BNB.LoadNoteInEditor and BNB._currentNoteID == _noteID then
                      BNB.LoadNoteInEditor(_noteID)
                  end
              end
          end },
    })
    -- Labels follow changes made anywhere else (list menu, editor, sticky)
    BNB.RegisterMessage("NoteConfigStates", "NoteChanged", function(_, id)
        if id == _noteID and ncFrame and ncFrame:IsShown() then
            _refreshStates()
        end
    end)
    y = y - 8
    y = Rule(panel, y) - 4
    y = Hdr(panel, y, L["NC_HDR_TITLE_COLOR"])

    -- The grid's last tile opens the colour picker; the Custom color and Reset
    -- buttons went (Dukul 2026-10-06)
    y = BNB.BuildColorGrid(panel, y, CW, function(r, g, b)
        Save({titleColor = {r=r, g=g, b=b}})
    end, function()
        local c = GetNote() and GetNote().titleColor
        if c then return c.r, c.g, c.b end
    end)

    -- Font ─────────────────────────────────────────────────────────────────────
    y = Rule(panel,y) - 4
    y = Hdr(panel,y,L["NC_HDR_FONT"])

    -- Font card picker — 2-column grid (matches sticky note settings layout)
    local PH     = 38    -- card height
    local PG     = 4     -- vertical gap between rows
    local COL_GAP_F = 4  -- horizontal gap between columns
    local CARD_W_F  = math.floor((CW - COL_GAP_F) / 2)
    local fontPickerBtns = {}
    local _wowCb_nc

    local function HLFonts()
        local note    = GetNote()
        -- No override (WoW Default unticked, nothing else picked) always shows Noto
        -- Serif highlighted, regardless of what was selected before. Under another
        -- font set (ALL-14) an override from a different set counts as none.
        local current = BNB.ResolveFontID(note and note.fontOverride) or BNB.GetFontSetDefault()
        for _,e in ipairs(fontPickerBtns) do
            BNB.PaintSelectCard(e.btn, e.id == current and "sel" or nil, e.nameLbl)
        end
        if _wowCb_nc then _wowCb_nc:SetChecked(current == "wow") end
    end
    -- A skin preset change re-paints the cards (ALL-410)
    BNB.RegisterMessage("NoteConfig.FontCards", "SkinChanged", function() HLFonts() end)

    -- LSM fonts appear in the dropdown below; WoW Default has its own checkbox
    -- below the grid. Both are excluded from the card grid, which shows the
    -- active language's font set (ALL-14).
    local fonts_nc = BNB.GetPickerFonts()
    for i, def in ipairs(fonts_nc) do
        local col     = (i - 1) % 2
        local gridRow = math.floor((i - 1) / 2)
        local xOff    = col * (CARD_W_F + COL_GAP_F)
        local yOff    = y - gridRow * (PH + PG)

        local btn = BNB.CreateBackdropFrame("Button", nil, panel)
        BNB.SetBackdrop(btn, 0.06,0.06,0.08,0.95, 0.28,0.28,0.30,1)
        btn:SetSize(CARD_W_F, PH)
        btn:SetPoint("TOPLEFT", panel, "TOPLEFT", xOff, yOff)
        btn:EnableMouse(true)
        btn:SetScript("OnEnter", function(s)
            local note = GetNote()
            if (note and note.fontOverride or nil) ~= def.id then BNB.PaintSelectCard(s, "hover") end
        end)
        btn:SetScript("OnLeave", HLFonts)
        btn:SetScript("OnClick", function()
            Save({fontOverride = def.id})
            local sz = BigNoteBoxDB and BigNoteBoxDB.fontSize or BNB.DEFAULTS.fontSize
            if BNB._editorBody  then pcall(function() BNB._editorBody:SetFont(def.regular, BNB.FontPx(def.regular, sz), "") end) end
            if BNB._editorTitle then pcall(function() BNB._editorTitle:SetFont(def.bold, BNB.FontPx(def.bold, 20), "") end) end
            HLFonts()
            if BNB._refreshWysiwygFont then BNB._refreshWysiwygFont() end
        end)
        local nameLbl = btn:CreateFontString(nil, "OVERLAY")
        nameLbl:SetPoint("TOPLEFT",  btn, "TOPLEFT",  5, -5)
        nameLbl:SetPoint("TOPRIGHT", btn, "TOPRIGHT", -5, -5)
        nameLbl:SetJustifyH("LEFT"); nameLbl:SetHeight(16)
        BNB.SetFontSafe(nameLbl, def.bold, 11, "BNBFontNormal")
        nameLbl:SetText(def.label)
        local prevLbl = btn:CreateFontString(nil, "OVERLAY")
        prevLbl:SetPoint("BOTTOMLEFT",  btn, "BOTTOMLEFT",  5, 5)
        prevLbl:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -5, 5)
        prevLbl:SetJustifyH("LEFT"); prevLbl:SetHeight(12)
        BNB.SetFontSafe(prevLbl, def.regular, 10, "BNBFontNormalSmall")
        prevLbl:SetTextColor(0.55, 0.55, 0.55); prevLbl:SetText(def.preview or "")
        fontPickerBtns[#fontPickerBtns+1] = {btn=btn, id=def.id, nameLbl=nameLbl, prevLbl=prevLbl, def=def}
    end
    -- Advance y past the grid. It always reserves its 4 rows; free rows carry the
    -- font pack hint.
    local usedRows_nc = math.ceil(#fonts_nc / 2)
    local gridRows_nc = math.max(BNB.FONT_GRID_ROWS, usedRows_nc)
    BNB.AddFontPackHint(panel, panel, 0, y - usedRows_nc * (PH + PG),
        CW, (gridRows_nc - usedRows_nc) * (PH + PG) - PG)
    y = y - gridRows_nc * (PH + PG) + PG

    -- LSM font dropdown, full width under the grid when lsmFonts is on, then the
    -- WoW Default checkbox on its own row (Dukul 2026-10-06; the colour grid
    -- lost its button row, so both fit again). Shared BuildLSMFontDropdown
    -- helper from ConfigWindow.lua; it builds nothing with the setting off or
    -- no LSM fonts installed. Without it the checkbox gets its own 8 px gap
    -- under the grid, or it sat on the cards (Dukul 2026-10-08).
    local lsmBuilt = false
    if BigNoteBoxDB and BigNoteBoxDB.lsmFonts
       and BNB._BuildLSMFontDropdown then
        -- 10 px gap above its header, under the grid (Dukul 2026-10-06)
        local lsmY, _, _, dd = BNB._BuildLSMFontDropdown(panel, y - 10,
            -- getter: current per-note fontOverride if it is an LSM font
            function()
                local note = GetNote()
                local choice = note and note.fontOverride
                local def = choice and BNB.GetFontDef and BNB.GetFontDef(choice)
                return (def and def._isLSM) and choice or nil
            end,
            -- setter: nil clears the LSM override (bundled card takes effect);
            --         path sets per-note override to this LSM font
            function(path)
                if path then
                    Save({fontOverride = path})
                else
                    -- Use _clear to actually remove the key from the note table.
                    -- Save({fontOverride = nil}) would leave a nil entry; _clear removes it.
                    local id = _noteID; if id then
                        BNB.UpdateNote(id, {_clear = {"fontOverride"}})
                    end
                end
                -- Apply live to the open editor if this note is loaded
                local note = GetNote()
                local sz = (note and note.fontSize)
                    or (BigNoteBoxDB and BigNoteBoxDB.fontSize) or BNB.DEFAULTS.fontSize
                local eb = BNB._editorBody
                if eb and BNB._currentNoteID == _noteID then
                    local def = path and BNB.GetFontDef and BNB.GetFontDef(path)
                    if def then
                        pcall(function() eb:SetFont(def.regular, BNB.FontPx(def.regular, sz), "") end)
                    elseif BNB.ApplyFont then
                        BNB.ApplyFont()
                    end
                end
                HLFonts()
                if BNB._refreshWysiwygFont then BNB._refreshWysiwygFont() end
            end,
            CW)
        if dd then y = lsmY - 4; lsmBuilt = true end
    end
    if not lsmBuilt then y = y - 8 end

    -- WoW Default checkbox, below the grid (and the LSM dropdown) instead of a
    -- 9th card. Latin set only; its row is kept either way.
    do
        local wowCb = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
        BNB.LabelHit(wowCb)   -- the tooltip and click reach over its label too
        wowCb:SetSize(20, 20)
        wowCb:SetPoint("TOPLEFT", panel, "TOPLEFT", -2, y)
        wowCb:SetShown(BNB.ShowWoWFontCheckbox())
        local wowLbl = panel:CreateFontString(nil, "OVERLAY", "BNBFontNormalSmall")
        wowLbl:SetPoint("LEFT",  wowCb,  "RIGHT", 4, 0)
        wowLbl:SetPoint("RIGHT", panel,  "RIGHT", 0, 0)
        wowLbl:SetJustifyH("LEFT")
        wowLbl:SetText(L["FONT_USE_WOW_DEFAULT"])
        if not BNB.ShowWoWFontCheckbox() then wowLbl:Hide() end
        wowCb:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(L["FONT_USE_WOW_DEFAULT_TIP"], 0.8, 0.8, 0.8, true)
            GameTooltip:Show()
        end)
        wowCb:SetScript("OnLeave", function() GameTooltip:Hide() end)
        wowCb:SetScript("OnClick", function(self)
            if self:GetChecked() then
                Save({fontOverride = "wow"})
            else
                local id = _noteID
                if id then BNB.UpdateNote(id, {_clear = {"fontOverride"}}) end
            end
            -- Apply live to the open editor if this note is loaded
            local note = GetNote()
            local sz = (note and note.fontSize)
                or (BigNoteBoxDB and BigNoteBoxDB.fontSize) or BNB.DEFAULTS.fontSize
            local eb = BNB._editorBody
            if eb and BNB._currentNoteID == _noteID then
                local ov = note and note.fontOverride
                local def = ov and BNB.ResolveFontDef and BNB.ResolveFontDef(ov)
                if def then
                    pcall(function() eb:SetFont(def.regular, BNB.FontPx(def.regular, sz), "") end)
                elseif BNB.ApplyFont then
                    BNB.ApplyFont()
                end
            end
            HLFonts()
            if BNB._refreshWysiwygFont then BNB._refreshWysiwygFont() end
        end)
        _wowCb_nc = wowCb
        y = y - 24
    end

    -- Re-apply fonts one frame after the panel first becomes visible.
    local function ReapplyFontPreviews()
        for _,e in ipairs(fontPickerBtns) do
            local def = e.def
            BNB.SetFontSafe(e.nameLbl, def.bold,    12, "BNBFontNormal")
            BNB.SetFontSafe(e.prevLbl, def.regular, 10, "BNBFontNormalSmall")
            e.nameLbl:SetText(def.label)
            e.prevLbl:SetText(def.preview or "")
        end
    end
    panel._reapplyFontPreviews = ReapplyFontPreviews

    -- Font size slider
    y = Rule(panel,y) - 4
    y = Hdr(panel,y,L["STICKY_FONT_SIZE"])

    local function GetNoteFontSize()
        local n = GetNote()
        return (n and n.fontSize) or (BigNoteBoxDB and BigNoteBoxDB.fontSize) or BNB.DEFAULTS.fontSize
    end

    -- Stacked slider (ALL-121). Reset clears the note's own size, so it
    -- follows the global one again.
    local function ApplyEditorSize(sz)
        if BNB._editorBody and BNB._currentNoteID == _noteID then
            local path = select(1, BNB._editorBody:GetFont())
            if path then pcall(function() BNB._editorBody:SetFont(path, BNB.FontPx(path, sz), "") end) end
        end
        if BNB._refreshWysiwygFont then BNB._refreshWysiwygFont() end
    end
    local fsSl = BNB.CreateStackedSlider(panel, CW, {
        label = "", min = 8, max = 32, value = GetNoteFontSize(),
        default = (BigNoteBoxDB and BigNoteBoxDB.fontSize) or BNB.DEFAULTS.fontSize,
        fmt = function(v) return v .. "pt" end,
        onChange = function(sz)
            Save({fontSize = sz})
            ApplyEditorSize(sz)
        end,
        onReset = function()
            if not _noteID then return end
            BNB.UpdateNote(_noteID, {_clear = {"fontSize"}})
            ApplyEditorSize((BigNoteBoxDB and BigNoteBoxDB.fontSize) or BNB.DEFAULTS.fontSize)
        end,
    })
    fsSl:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, y)
    y = y - (BNB.STACKED_SLIDER_H + 6)

    -- Refresh callback for note switching (silent: switching saves nothing)
    panel._refreshFontSize = function()
        fsSl:SetValue(GetNoteFontSize(), true)
    end

    -- (panel is the tab's own plain frame since ALL-318, no scroll frame;
    -- _reapplyFontPreviews is set above, after ReapplyFontPreviews)
    panel._hlFonts    = HLFonts
    -- Refresh the state button labels when switching notes
    -- (on the panel: the refresh reads tabPanels[TAB_GEN]; the old
    -- checkboxes hung it on ct and never refreshed)
    panel._refreshChecks = _refreshStates
end

-- ─────────────────────────────────────────────────────────────────────────────
-- TAB 2 — APPEARANCE
-- ─────────────────────────────────────────────────────────────────────────────
local function BuildAppearanceTab(panel)
    local y = -4

    -- Text alignment (applies to main editor body), moved from General (Dukul, 2026-10-04)
    y = Hdr(panel,y,L["NC_HDR_TEXT_ALIGNMENT"])

    -- ALIGN_KEYS_NC holds the WoW native justify constants that note.textAlign is
    -- actually saved as (unaffected by locale); ALIGN_LABELS_NC is the translatable
    -- display text, looked up by that same key. See StickyNote.lua's identical fix
    -- (ALL-08) for why the old display-string-doubles-as-key shape is unsafe.
    local ALIGN_KEYS_NC   = { "LEFT", "CENTER", "RIGHT" }
    local ALIGN_LABELS_NC = { LEFT = L["STICKY_ALIGN_LEFT"], CENTER = L["STICKY_ALIGN_CENTER"], RIGHT = L["STICKY_ALIGN_RIGHT"] }

    local function ApplyNoteAlign(align)
        Save({textAlign = align})
        if BNB._editorBody then
            pcall(function() BNB._editorBody:SetJustifyH(align) end)
        end
    end

    local alignDD = BNB.SkinDropdown(CreateFrame("DropdownButton", nil, panel,
        "WowStyle1DropdownTemplate"))
    alignDD:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, y)
    alignDD:SetWidth(CW)
    alignDD:SetupMenu(function(_, root)
        for _, key in ipairs(ALIGN_KEYS_NC) do
            local k = key
            root:CreateRadio(ALIGN_LABELS_NC[k],
                function()
                    local note = GetNote()
                    return ((note and note.textAlign) or "LEFT") == k
                end,
                function()
                    ApplyNoteAlign(k)
                    alignDD:GenerateMenu()
                end)
        end
    end)
    y = y - 36

    -- F — Font outline (applies to main editor body)
    y = Rule(panel,y) - 4
    y = Hdr(panel,y,L["NC_HDR_FONT_OUTLINE"])

    local OUTLINE_OPTIONS_NC = {
        "None", "Outline", "Thick Outline", "Monochrome Outline",
        "SLUG", "SLUG Outline", "SLUG Thick Outline",
        "Drop Shadow", "Strong Drop Shadow", "Strongest Drop Shadow",
    }
    local function GetNoteOutlineLabel()
        local note = GetNote()
        return (note and note.fontOutline) or "None"
    end
    local function ApplyNoteOutline(outline)
        Save({fontOutline = outline})
        if BNB._editorBody then
            local flags, ox, oy, sr, sg, sb, sa
            if     outline == "Outline"           then flags = "OUTLINE"
            elseif outline == "Thick Outline"     then flags = "THICKOUTLINE"
            elseif outline == "Monochrome Outline" then flags = "MONOCHROME,OUTLINE"
            elseif outline == "SLUG"              then flags = "SLUG"
            elseif outline == "SLUG Outline"      then flags = "OUTLINE, SLUG"
            elseif outline == "SLUG Thick Outline" then flags = "THICKOUTLINE, SLUG"
            else flags = "" end
            if     outline == "Drop Shadow"           then ox,oy,sr,sg,sb,sa = 1,-1,0,0,0,0.8
            elseif outline == "Strong Drop Shadow"    then ox,oy,sr,sg,sb,sa = 2,-2,0,0,0,1.0
            elseif outline == "Strongest Drop Shadow" then ox,oy,sr,sg,sb,sa = 3,-3,0,0,0,1.0
            else ox,oy,sr,sg,sb,sa = 0,0,0,0,0,0 end
            local path, sz = BNB._editorBody:GetFont()
            if path then pcall(function() BNB._editorBody:SetFont(path, sz, flags) end) end
            pcall(function() BNB._editorBody:SetShadowOffset(ox, oy) end)
            pcall(function() BNB._editorBody:SetShadowColor(sr, sg, sb, sa) end)
        end
    end

    local outlineDD = BNB.SkinDropdown(CreateFrame("DropdownButton", nil, panel,
        "WowStyle1DropdownTemplate"))
    outlineDD:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, y)
    outlineDD:SetWidth(CW)
    outlineDD:SetupMenu(function(_, root)
        for _, opt in ipairs(OUTLINE_OPTIONS_NC) do
            local o = opt
            root:CreateRadio(BNB.AdvancedMode.OutlineLabel(o),
                function() return GetNoteOutlineLabel() == o end,
                function()
                    ApplyNoteOutline(o)
                    outlineDD:GenerateMenu()
                end)
        end
    end)
    y = y - 36

    -- Icon frame / edge border picker (ALL-127: replaces the old LSM border
    -- dropdown; a game-art frame and an LSM edge border are mutually
    -- exclusive, the picker's two tabs enforce that)
    y = Rule(panel, y) - 4
    y = Hdr(panel, y, L["NC_HDR_BORDER"])
    local function CurIconFrameLabel()
        local n = GetNote()
        if n and n.iconFrame and n.iconFrame ~= "" and n.iconFrame ~= "none" then
            return BNB.IconFrames.Label(n.iconFrame) or n.iconFrame
        end
        if n and n.borderOverride and n.borderOverride ~= "" and n.borderOverride ~= "None" then
            return n.borderOverride
        end
        return L["STICKY_BG_NONE"]
    end
    -- [<] [name] [>] as the sticky background row (ALL-147): the arrows step
    -- through None, the frames and the edge borders, the name opens the grid
    local IF_ARW = 22
    local ifPrev = BNB.CreateButton(nil, panel, "<", IF_ARW, 22)
    local ifBtn  = BNB.CreateButton(nil, panel, L["NC_ICON_FRAME_BTN"], CW - 2 * (IF_ARW + 4), 22)
    local ifNext = BNB.CreateButton(nil, panel, ">", IF_ARW, 22)
    BNB.TruncateButtonText(ifBtn)   -- LSM border names can be long
    local function RefreshIconFrameBtn()
        ifBtn:SetText(L["NC_ICON_FRAME_BTN"] .. ": " .. CurIconFrameLabel())
        if ifBtn._syncOffset then ifBtn._syncOffset() end
    end
    RefreshIconFrameBtn()
    ifPrev:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, y)
    ifBtn:SetPoint("LEFT", ifPrev, "RIGHT", 4, 0)
    ifNext:SetPoint("LEFT", ifBtn, "RIGHT", 4, 0)
    local function IconFrameHandlers()
        return {
            getFrame = function() local n = GetNote(); return (n and n.iconFrame) or "none" end,
            setFrame = function(key)
                if key == "none" then BNB.UpdateNote(_noteID, {_clear = {"iconFrame"}})
                else BNB.UpdateNote(_noteID, {iconFrame = key}) end
                RefreshIconFrameBtn()
                if BNB.Sticky and BNB.Sticky.RefreshNote then BNB.Sticky.RefreshNote(_noteID) end
            end,
            getBorder = function() local n = GetNote(); return (n and n.borderOverride) or "None" end,
            setBorder = function(name)
                if name == "None" then BNB.UpdateNote(_noteID, {_clear = {"borderOverride"}})
                else BNB.UpdateNote(_noteID, {borderOverride = name}) end
                RefreshIconFrameBtn()
                if BNB.Sticky and BNB.Sticky.RefreshNote then BNB.Sticky.RefreshNote(_noteID) end
            end,
            getBright = function()
                local n = GetNote(); return BNB.BorderBright.Clamp(n and n.borderBrightness) / 100
            end,
            getIcon = function()
                local n = GetNote()
                return n and (BNB.NpcNoteIcon and BNB.NpcNoteIcon(n) or n.icon)
            end,
        }
    end
    ifBtn:SetScript("OnClick", function(self)
        BNB.IconFramePicker.Open(_noteID, ncFrame or self, IconFrameHandlers())
    end)
    ifPrev:SetScript("OnClick", function() if _noteID then BNB.IconFramePicker.Step(IconFrameHandlers(), -1) end end)
    ifNext:SetScript("OnClick", function() if _noteID then BNB.IconFramePicker.Step(IconFrameHandlers(), 1) end end)
    for btn, tip in pairs({ [ifPrev] = "ICON_FRAME_PREV", [ifBtn] = "ICON_FRAME_BROWSE_TIP",
                            [ifNext] = "ICON_FRAME_NEXT" }) do
        local text = L[tip]
        btn:HookScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(text, 1, 1, 1)
            GameTooltip:Show()
        end)
        btn:HookScript("OnLeave", function() GameTooltip:Hide() end)
    end
    y = y - 28

    -- Border sliders: stacked, with Reset (ALL-121)
    local function GetBorderScale()
        local n = GetNote(); return (n and n.borderScale) or 100
    end
    local function GetBorderOffset()
        local n = GetNote(); return (n and n.borderOffset) or 2
    end
    local function GetBorderBrightness()
        local n = GetNote(); return BNB.BorderBright.Clamp(n and n.borderBrightness)
    end
    local function BorderSlider(label, mn, mx, value, default, field, unit)
        local sl = BNB.CreateStackedSlider(panel, CW, {
            label = label, min = mn, max = mx, value = value, default = default,
            fmt = function(v) return v .. unit end,
            onChange = function(v)
                Save({[field] = v})
                if BNB.Sticky and BNB.Sticky.RefreshNote then BNB.Sticky.RefreshNote(_noteID) end
            end,
        })
        sl:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, y)
        y = y - (BNB.STACKED_SLIDER_H + 6)
        return sl
    end
    local bsSl = BorderSlider(L["NC_BORDER_THICKNESS_LABEL"], 1, 200, GetBorderScale(), 100, "borderScale", "%")
    local boSl = BorderSlider(L["NC_BORDER_OFFSET_LABEL"], 0, 12, GetBorderOffset(), 2, "borderOffset", "px")
    local bbSl = BorderSlider(L["NC_BORDER_BRIGHTNESS_LABEL"], BNB.BorderBright.MIN, BNB.BorderBright.MAX,
        GetBorderBrightness(), BNB.BorderBright.DEFAULT, "borderBrightness", "%")
    -- An icon frame ignores the offset (only scale and brightness apply), so
    -- the slider is greyed while one is set
    ifBtn._syncOffset = function()
        local n = GetNote()
        boSl:SetEnabled(not (n and BNB.IconFrames.Get(n.iconFrame)))
    end
    ifBtn._syncOffset()

    -- Icon: the current icon and a button that opens the icon picker beside
    -- the window (ALL-238, UI/IconPicker.lua); the old grid / Blizzard tabs
    y = Rule(panel, y) - 4
    y = Hdr(panel, y, L["NC_HDR_ICON"])

    local iconBtn = BNB.CreateButton(nil, panel, L["NC_ICON_PICK_BTN"], CW, 22)
    BNB.TruncateButtonText(iconBtn)   -- icon names can be long
    iconBtn:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, y)
    y = y - 28

    -- Preview section at the bottom: the icon as the note list draws it, with
    -- the icon frame or edge border and the Border sliders (Dukul, 2026-10-04).
    -- Room above and below for a frame's art, which reaches past the icon.
    y = Rule(panel, y) - 4
    y = Hdr(panel, y, L["NC_HDR_PREVIEW"])
    local PREV = 64
    local prevHost = CreateFrame("Frame", nil, panel)
    prevHost:SetSize(PREV, PREV)
    prevHost:SetPoint("TOP", panel, "TOPLEFT", CW / 2, y - 16)
    local iconTex = prevHost:CreateTexture(nil, "ARTWORK")
    iconTex:SetAllPoints()
    iconTex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    local prevBorder = BNB.CreateBackdropFrame("Frame", nil, prevHost)
    prevBorder:SetFrameLevel(prevHost:GetFrameLevel() + 2)
    prevBorder:EnableMouse(false)
    prevBorder:Hide()
    -- Random: a random icon and a random icon frame (Dukul, 2026-10-04); its
    -- click is set after IconPickHandlers below
    local rndLookBtn = BNB.CreateButton(nil, panel, L["NC_RANDOM_BTN"], CW, 22)
    rndLookBtn:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, y - 16 - PREV - 22)

    local function PaintPreviewBorder(n)
        prevBorder:Hide()
        if BNB.ApplyIconFrame(iconTex, n, PREV) then return end
        -- Same maths as the note list's LSM edge border (UI/NoteList.lua)
        local bord = n and n.borderOverride
        if not bord or bord == "" or bord == "None" then return end
        local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
        local path = LSM and LSM:Fetch("border", bord)
        if not path then return end
        local off    = n.borderOffset or 2
        local es = math.max(1, math.floor(12 * (n.borderScale or 100) / 100 + 0.5))
        prevBorder:ClearAllPoints()
        prevBorder:SetPoint("TOPLEFT",     iconTex, "TOPLEFT",     -off,  off)
        prevBorder:SetPoint("BOTTOMRIGHT", iconTex, "BOTTOMRIGHT",  off, -off)
        pcall(function()
            prevBorder:SetBackdrop({ edgeFile = path, edgeSize = es })
            BNB.BorderBright.SetBackdropBorder(prevBorder, n.borderBrightness, 0.70, 0.70, 0.75, 0.85)
        end)
        prevBorder:Show()
    end

    local function RefreshIconRow()
        local n = GetNote()
        local shown = n and (BNB.NpcNoteIcon and BNB.NpcNoteIcon(n) or n.icon)
        iconTex:SetTexture((shown and shown ~= "") and shown or "Interface\\Icons\\INV_Misc_Note_06")
        if n and BNB.SetNpcNotePortrait then BNB.SetNpcNotePortrait(iconTex, n) end
        PaintPreviewBorder(n)
        local name = (n and n.icon and n.icon ~= "") and BNB.IconPicker.IconName(n.icon)
            or L["NC_ICON_PICK_NONE"]
        iconBtn:SetText(L["NC_ICON_PICK_BTN"] .. ": " .. name)
    end
    local function IconPickHandlers()
        local n0 = GetNote()
        local isNpc = n0 and n0.source == "target" and n0.targetNpcID and not n0.targetIsPet
        return {
            owner     = "noteConfig",
            get       = function() local n = GetNote(); return n and n.icon end,
            getSource = function() local n = GetNote(); return n and n.iconSource end,
            -- NPC target notes: the picker's "NPC portrait" button (Dukul, 2026-10-04)
            portraitOn  = isNpc and function() local n = GetNote(); return n and not n.iconSource end or nil,
            usePortrait = isNpc and function()
                if not _noteID then return end
                BNB.UpdateNote(_noteID, {_clear = {"iconSource"}})
                if BNB.Sticky and BNB.Sticky.RefreshNote then BNB.Sticky.RefreshNote(_noteID) end
                RefreshIconRow()
            end or nil,
            set = function(icon, source)
                if not _noteID then return end
                if icon == nil then BNB.UpdateNote(_noteID, {_clear = {"icon", "iconSource"}})
                elseif source then BNB.UpdateNote(_noteID, {icon = icon, iconSource = source})
                else
                    -- No source (Revert to a note that had none): an NPC note
                    -- shows its portrait again (BNB.SetNpcNotePortrait)
                    BNB.UpdateNote(_noteID, {icon = icon, _clear = {"iconSource"}})
                end
                if BNB.Sticky and BNB.Sticky.RefreshNote then BNB.Sticky.RefreshNote(_noteID) end
                RefreshIconRow()
                -- The frame picker's tiles wear the note's icon
                if BNB.IconFramePicker.IsOpenFor(_noteID) then
                    BNB.IconFramePicker.Rebind(_noteID, IconFrameHandlers())
                end
            end,
        }
    end
    -- Both pickers open in the same spot beside the window: one at a time
    iconBtn:SetScript("OnClick", function(self)
        BNB.IconFramePicker.Close()
        BNB.IconPicker.Open(_noteID, ncFrame or self, IconPickHandlers())
    end)
    ifBtn:HookScript("OnClick", function() BNB.IconPicker.Close("noteConfig") end)
    rndLookBtn:SetScript("OnClick", function()
        if not _noteID then return end
        local icons = BNB.ICON_MANIFEST or {}
        if #icons > 0 then IconPickHandlers().set(icons[math.random(#icons)], "curated") end
        local frames = BNB.IconFrames and BNB.IconFrames.LIST or {}
        if #frames > 0 then
            local h = IconFrameHandlers()
            h.setFrame(frames[math.random(#frames)].key)
            local b = h.getBorder()
            if b and b ~= "" and b ~= "None" then h.setBorder("None") end
        end
        BNB.IconPicker.Refresh()
        if BNB.IconFramePicker.IsOpenFor(_noteID) then
            BNB.IconFramePicker.Rebind(_noteID, IconFrameHandlers())
        end
    end)
    rndLookBtn:SetScript("OnEnter", function(self)
        -- Below the button: above it would cover the preview (Dukul, 2026-10-04)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetText(L["NC_RANDOM_BTN"], 1, 1, 1)
        GameTooltip:AddLine(L["NC_RANDOM_LOOK_TIP"], 1, 0.82, 0, true)
        GameTooltip:Show()
    end)
    rndLookBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- An icon set somewhere else (editor, sticky) while this window is open
    BNB.RegisterMessage("NoteConfigIcon", "NoteChanged", function(_, id)
        if id == _noteID and ncFrame and ncFrame:IsShown() then RefreshIconRow() end
    end)

    -- Refresh all border controls when switching notes (called by OpenNoteConfig/SyncNoteConfig)
    panel._refreshAppearance = function()
        local n    = GetNote()
        RefreshIconFrameBtn()
        if BNB.IconFramePicker.IsOpenFor(_noteID) then
            BNB.IconFramePicker.Rebind(_noteID, IconFrameHandlers())
        end

        local bs = (n and n.borderScale)      or 100
        local bo = (n and n.borderOffset)     or 2
        local bb = BNB.BorderBright.Clamp(n and n.borderBrightness)
        -- silent: switching notes saves nothing
        bsSl:SetValue(bs, true)
        boSl:SetValue(bo, true)
        bbSl:SetValue(bb, true)

        RefreshIconRow()
        BNB.IconPicker.Rebind(_noteID, IconPickHandlers())
    end
end

--------------------------------------------------------------------------------
-- TAB 3: SITUATION
-- The shared Situation editor (UI/SituationEditor.lua, CMP-03); sticky
-- settings shows the same one. panel._loadCtx is what OpenNoteConfig and
-- SyncNoteConfig call on a note switch.
--------------------------------------------------------------------------------
local function BuildSituationTab(panel)
    local ed = BNB.CreateSituationEditor(panel, {
        -- The panel is already PAD in from the window (MakePlainPanel): no
        -- second pad. Rules end at the panel edge and dropdowns 4 px past it,
        -- top at -4, as on General / Appearance (Dukul 2026-10-06)
        padL = 0, padR = 0, ddR = -4, top = -4,
        host = panel:GetParent(),
    })
    panel._loadCtx = function() ed:Load(_noteID) end
end

-- ── Build window ──────────────────────────────────────────────────────────────
local SK_TAB_GAP = 30   -- skin tab strip (24) + 6px gap below the title strip

local function CreateNoteConfigWindow()
    -- Same strata as the Reference Box (DIALOG, the builder's default), which
    -- drew over this window from MEDIUM whatever was clicked (Dukul,
    -- 2026-10-04). Raised on open, and BNB.RaiseBNBWindows raises it after the
    -- Reference Box (WINDOWS order). Shared shell: UI/ToolWindow.lua (CMP-02)
    local f = BNB.CreateToolWindow({
        name = "BigNoteBoxNoteConfigFrame", w = NCW, h = 640, pad = PAD,
        title = L["STICKY_NOTE_SETTINGS_TIP"], toplevel = true, escClose = true,
    })
    f:SetPoint("CENTER")
    local skinMode = f._isSkin
    local SK_NC_TITLE_H = BNB.TOOL_SKIN_TITLE_H
    local tabContentY = skinMode and (SK_NC_TITLE_H + SK_TAB_GAP) or TAB_CONTENT_Y

    -- Close ZonePicker whenever NoteConfig hides (any path: close btn, ESC, main
    -- window close); the Situation editor closes its waypoint info popup itself
    f:HookScript("OnHide", function()
        if BNB.ZonePicker and BNB.ZonePicker.Close then BNB.ZonePicker.Close() end
        -- The icon frame picker belongs to this window (ALL-127)
        if BNB.IconFramePicker then BNB.IconFramePicker.Close() end
        if BNB.IconPicker then BNB.IconPicker.Close("noteConfig") end
    end)

    local tabDefs = {
        { label=L["CFG_TAB_GENERAL"],    builder=BuildGeneralTab    },
        { label=L["CFG_TAB_APPEARANCE"], builder=BuildAppearanceTab },
        { label=L["NC_TAB_SITUATION"],  builder=BuildSituationTab  },
    }

    if skinMode then
        local tabCtrl = BNB.CreateSkinTabs(f, {L["CFG_TAB_GENERAL"], L["CFG_TAB_APPEARANCE"], L["NC_TAB_SITUATION"]},
            function(idx) BNB._NoteConfigSelectTab(idx) end)
        -- ALL-313: in from both edges like Settings' skin tabs (ALL-229)
        tabCtrl.frame:SetPoint("TOPLEFT",  f, "TOPLEFT",  8, -SK_NC_TITLE_H)
        tabCtrl.frame:SetPoint("TOPRIGHT", f, "TOPRIGHT", -8, -SK_NC_TITLE_H)
        f._skinTabCtrl = tabCtrl
    else
        local tpl = "PanelTopTabButtonTemplate"

        local lastBtn = nil
        for i, def in ipairs(tabDefs) do
            local btn = CreateFrame("Button", "BNBNoteConfigTab"..i, f, tpl)
            btn:SetText(def.label)
            pcall(function()
                PanelTemplates_TabResize(btn, 15, nil, 70)
            end)
            btn:SetID(i)
            if lastBtn then btn:SetPoint("LEFT", lastBtn, "RIGHT", 5, 0)
            else             btn:SetPoint("TOPLEFT", f, "TOPLEFT", 7, -25) end
            btn:SetScript("OnClick", function(s) BNB._NoteConfigSelectTab(s:GetID()) end)
            tabBtns[i] = btn; lastBtn = btn
        end
        PanelTemplates_SetNumTabs(f, NUM_TABS); f.numTabs = NUM_TABS
        -- Keep the row inside the window (ALL-170: Classic tabs ran outside)
        BNB.FitTabRow(f, tabBtns, 7, 5)
    end

    for i, def in ipairs(tabDefs) do
        local p = MakePlainPanel(f, tabContentY)
        tabPanels[i] = p
        def.builder(p)
    end

    return f
end

function BNB._NoteConfigSelectTab(idx)
    for i = 1, NUM_TABS do
        if tabBtns[i] then
            if i == idx then PanelTemplates_SelectTab(tabBtns[i])
            else              PanelTemplates_DeselectTab(tabBtns[i]) end
        end
        if tabPanels[i] then
            if i == idx then tabPanels[i]:Show() else tabPanels[i]:Hide() end
        end
    end
    if ncFrame then
        ncFrame._activeTab = idx
        -- Sync skin tab controller visual if present
        if ncFrame._skinTabCtrl and ncFrame._skinTabCtrl.SetVisual then
            ncFrame._skinTabCtrl.SetVisual(idx)
        end
    end
end

-- ── Public API ────────────────────────────────────────────────────────────────
-- tab, optional: "situation" opens on that tab, and only switches to it when
-- the window is already open for this note (no toggle). Context menu, ALL-148.
local TAB_KEYS = { situation = TAB_SIT }

function BNB.NoteConfigOpenFor(noteID)
    return ncFrame and ncFrame:IsShown() and _noteID == noteID or false
end

function BNB.OpenNoteConfig(noteID, tab)
    if InCombatLockdown() then BNB:Print(L["COMBAT_BLOCKED"]); return end
    local note=noteID and BNB.GetNote(noteID)
    if not note then BNB:Print(L["NC_NO_NOTE_SELECTED"]); return end
    local tabIdx = tab and TAB_KEYS[tab]

    if ncFrame and ncFrame:IsShown() and _noteID==noteID then
        if tabIdx then BNB._NoteConfigSelectTab(tabIdx) else ncFrame:Hide() end
        return
    end
    _noteID=noteID

    if not ncFrame then ncFrame=CreateNoteConfigWindow() end

    RefreshTitle()
    local gPanel = tabPanels[TAB_GEN]
    if gPanel and gPanel._hlFonts         then gPanel._hlFonts()         end
    if gPanel and gPanel._refreshChecks   then gPanel._refreshChecks()   end
    if gPanel and gPanel._refreshFontSize then gPanel._refreshFontSize() end

    -- Refresh font previews (deferred one tick so the renderer
    -- has processed the .ttf paths before we read back the glyphs)
    if gPanel and gPanel._reapplyFontPreviews then
        C_Timer.After(0, gPanel._reapplyFontPreviews)
    end

    -- Refresh appearance tab (border dropdown + sliders)
    local aPanel = tabPanels[TAB_APP]
    if aPanel and aPanel._refreshAppearance then aPanel._refreshAppearance() end

    -- Refresh Situation panel
    local sPanel = tabPanels[TAB_SIT]
    if sPanel and sPanel._loadCtx then sPanel._loadCtx() end

    BNB._NoteConfigSelectTab(tabIdx or ncFrame._activeTab or TAB_GEN)

    ncFrame:ClearAllPoints()
    if BNB.mainFrame and BNB.mainFrame:IsShown() then
        ncFrame:SetPoint("TOPRIGHT",BNB.mainFrame,"TOPLEFT",-8,0)
    else
        ncFrame:SetPoint("CENTER")
    end
    ncFrame:Show()
    ncFrame:Raise()
end

-- Refreshes NoteConfig content when the selected note changes, but only if the
-- window is already open. No toggle, no reposition — called from SelectNote.
BNB.RegisterMessage("NoteConfig", "NoteSelected", function(_, id) BNB.SyncNoteConfig(id) end)

function BNB.SyncNoteConfig(noteID)
    if not ncFrame or not ncFrame:IsShown() then return end
    if not noteID then ncFrame:Hide(); return end
    local note = BNB.GetNote(noteID)
    if not note then ncFrame:Hide(); return end

    _noteID = noteID
    RefreshTitle()

    local gPanel = tabPanels[TAB_GEN]
    if gPanel and gPanel._hlFonts         then gPanel._hlFonts()         end
    if gPanel and gPanel._refreshChecks   then gPanel._refreshChecks()   end
    if gPanel and gPanel._refreshFontSize then gPanel._refreshFontSize() end
    if gPanel and gPanel._reapplyFontPreviews then
        C_Timer.After(0, gPanel._reapplyFontPreviews)
    end

    -- Refresh appearance tab (border dropdown + sliders)
    local aPanel = tabPanels[TAB_APP]
    if aPanel and aPanel._refreshAppearance then aPanel._refreshAppearance() end

    local sPanel = tabPanels[TAB_SIT]
    if sPanel and sPanel._loadCtx then sPanel._loadCtx() end

    -- Stay on the current tab -- don't reset to General
    BNB._NoteConfigSelectTab(ncFrame._activeTab or TAB_GEN)

    -- Back on top of a Reference Box this note switch opened or synced
    -- (Dukul, 2026-10-04): next frame, after its own NoteSelected handler,
    -- with the pickers that sit beside this window above it
    C_Timer.After(0, function()
        if not (ncFrame and ncFrame:IsShown()) then return end
        ncFrame:Raise()
        for _, name in ipairs({ "BigNoteBoxIconFramePicker", "BigNoteBoxIconPicker" }) do
            local w = _G[name]
            if w and w:IsShown() then w:Raise() end
        end
    end)
end

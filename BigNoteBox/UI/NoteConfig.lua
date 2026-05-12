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
local NCW     = 264
local TITLE_H = 60
-- Tab buttons (PanelTopTabButtonTemplate) sit at y=-25, are ~20px tall, ending ~y=-45.
-- TAB_CONTENT_Y = distance from frame top to content start.
-- 60 (TITLE_H) - 25 (tab y-offset from top) + 20 (tab height) + 8 (padding) = 63
local TAB_CONTENT_Y = 63
local PAD     = 12
-- Width: window minus left pad minus right margin (no scrollbar on most panels)
local CW      = NCW - PAD - 8
local CW_SCROLL = NCW - PAD - 28  -- used only where a scrollbar IS present
local ROW_H   = 28
local ROW_GAP = 4
local ASSETS  = "Interface\\AddOns\\BigNoteBox\\Assets\\"

-- ── LSM helpers ───────────────────────────────────────────────────────────────
local function GetLSM() return LibStub and LibStub("LibSharedMedia-3.0", true) end
local function LSMBorderList()
    -- De-duplicate: LSM sometimes includes "None" as an entry
    local l = GetLSM()
    local seen = { ["None"] = true }
    local r = { "None" }
    if l then
        for _, v in ipairs(l:List("border")) do
            if not seen[v] then seen[v] = true; r[#r+1] = v end
        end
    end
    return r
end

-- ── Module state ──────────────────────────────────────────────────────────────
local ncFrame   = nil
local _noteID   = nil
local tabBtns   = {}
local tabPanels = {}
local NUM_TABS  = 3
local TAB_GEN   = 1
local TAB_APP   = 2
local TAB_SIT   = 3

-- Icon grid state
local GRID_COLS  = 6
local CELL       = 32
local CELL_PAD   = 3
local iconBtns   = {}
local _filter    = ""

-- ── Icon list — sourced from Assets/Icons/IconManifest.lua ───────────────────
-- Add/remove icons by editing Assets/Icons/ subfolders and re-running
-- Tools/gen_icon_manifest.py; no changes needed in this file.
local ICON_LIST = BNB.ICON_MANIFEST or {}
-- Synonym table: each entry maps a full keyword to a list of additional search terms.
-- Partial-match lookup: if the typed text is a prefix of a key, its synonyms are included.
local ICON_SYNONYMS = {
    ["race"]       = {"character", "achievement_character"},
    ["character"]  = {"race",      "achievement_character"},
    ["class"]      = {"classicon"},
    ["dungeon"]    = {"instance",  "achievement_dungeon"},
    ["raid"]       = {"achievement_raid"},
    ["zone"]       = {"achievement_zone", "teleport"},
    ["profession"] = {"trade", "inv_misc_profession"},
    ["spell"]      = {"ability"},
    ["note"]       = {"inv_misc_note", "inv_misc_notescript"},
}

local function GetFilteredIcons(filter)
    if not filter or filter == "" then return ICON_LIST end
    local lower = filter:lower()
    -- Build the set of search terms: start with the typed text, then add synonyms
    -- for any ICON_SYNONYMS key that the typed text is a prefix of.
    local terms = {lower}
    local seen  = {[lower] = true}
    for key, syns in pairs(ICON_SYNONYMS) do
        if key:sub(1, #lower) == lower then   -- typed text is a prefix of this key
            for _, syn in ipairs(syns) do
                if not seen[syn] then
                    terms[#terms+1] = syn
                    seen[syn] = true
                end
            end
        end
    end
    local result = {}
    for _, path in ipairs(ICON_LIST) do
        local name = (path:match("([^\\/:]+)$") or path):lower()
        for _, term in ipairs(terms) do
            if name:find(term, 1, true) then
                result[#result+1] = path
                break
            end
        end
    end
    return result
end

-- ── Helpers ───────────────────────────────────────────────────────────────────
local function GetNote()  return _noteID and BNB.GetNote(_noteID) end
local function Save(fields)
    if not _noteID then return end
    BNB.UpdateNote(_noteID, fields)
    if BNB.RefreshNoteList then BNB.RefreshNoteList() end
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
        or (L and L["UNTITLED"] or "Untitled")
    -- Truncate long titles so they don't overflow the window titlebar
    if #name > 23 then name = name:sub(1, 20) .. "..." end
    if ncFrame.SetTitle then
        ncFrame:SetTitle(name)
    elseif ncFrame._titleLbl then
        ncFrame._titleLbl:SetText(name)
    end
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

-- Scrolling panel (General tab needs scrolling for its long content)
local function MakeScrollPanel(parent, tabContentY)
    tabContentY = tabContentY or TAB_CONTENT_Y
    local sf  = CreateFrame("ScrollFrame", nil, parent, "ScrollFrameTemplate")
    local bar = sf.ScrollBar
    sf:SetPoint("TOPLEFT",     parent, "TOPLEFT",      PAD, -tabContentY)
    sf:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -24,   4)

    local ct = CreateFrame("Frame", nil, sf)
    ct:SetWidth(CW_SCROLL); ct:SetHeight(1)
    sf:SetScrollChild(ct)

    local _contentH = 0
    local function Apply()
        local sfH = sf:GetHeight()
        if sfH < 4 then return end
        ct:SetHeight(math.max(_contentH, sfH))
        if _contentH <= sfH + 2 then
            if bar then bar:Hide() end
        else
            if bar then bar:Show() end
        end
    end
    sf:SetScript("OnSizeChanged", Apply)
    sf:HookScript("OnShow", function() C_Timer.After(0.05, Apply) end)
    function sf:FinaliseHeight(h) _contentH = h; C_Timer.After(0.05, Apply) end
    sf:Hide()
    return sf, ct
end

-- Layout micro-helpers
local function Hdr(parent, y, text)
    local l = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    l:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, y)
    l:SetTextColor(1, 0.82, 0, 1); l:SetText(text)
    return y - 20
end
local function Rule(parent, y)
    local t = parent:CreateTexture(nil, "ARTWORK")
    t:SetHeight(1)
    t:SetPoint("TOPLEFT",  parent, "TOPLEFT",  0, y)
    t:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, y)
    if BigNoteBoxDB and BigNoteBoxDB.skinMode and BNB.GetSkinPreset then
        local p = BNB.GetSkinPreset()
        local br, bg_, bb = BNB.SkinBorderOf(p)
        t:SetColorTexture(br, bg_, bb, 0.9)
        BNB.RegisterSkinRule(t, 0.9)
    else
        t:SetColorTexture(0.25, 0.25, 0.28, 1)
    end
    return y - 10
end
local function Check(parent, y, text, getter, setter, tip)
    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cb:SetSize(24, 24); cb:SetPoint("TOPLEFT", parent, "TOPLEFT", -2, y + 2)
    cb:SetChecked(getter())
    cb._getter = getter   -- stored for refresh
    cb:SetScript("OnClick", function(s) setter(s:GetChecked() and true or false) end)
    if tip then
        cb:SetScript("OnEnter", function(s)
            GameTooltip:SetOwner(s, "ANCHOR_RIGHT")
            GameTooltip:AddLine(tip, 0.8, 0.8, 0.8, true); GameTooltip:Show()
        end)
        cb:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end
    local lbl = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    lbl:SetPoint("LEFT", cb, "RIGHT", 4, 0); lbl:SetPoint("RIGHT", parent, "RIGHT", 0, 0)
    lbl:SetJustifyH("LEFT"); lbl:SetHeight(ROW_H); lbl:SetText(text)
    return y - (ROW_H + ROW_GAP), cb
end

-- ── Dropdown helper (WowStyle1 with cycling button fallback) ────────────────────────────
local function CreateDropdown(parent, labelText, getEntries, selected, onChange)
    local c = CreateFrame("Frame", nil, parent); c:SetHeight(44)
    local lb = c:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    lb:SetPoint("TOPLEFT", c, "TOPLEFT", 0, 0); lb:SetText(labelText)

    local useNative = C_XMLUtil and C_XMLUtil.GetTemplateInfo
        and C_XMLUtil.GetTemplateInfo("WowStyle1DropdownTemplate")

    if useNative then
        local dd = CreateFrame("DropdownButton", nil, c, "WowStyle1DropdownTemplate")
        dd:SetPoint("TOPLEFT", c, "TOPLEFT", 0, -18); dd:SetPoint("RIGHT", c, "RIGHT", 0, 0)
        local curSel = selected or "None"
        dd:SetupMenu(function(_, root)
            local items = getEntries and getEntries() or {}
            for _, name in ipairs(items) do
                root:CreateRadio(name,
                    function() return curSel == name end,
                    function() curSel = name; dd:GenerateMenu(); if onChange then onChange(name) end end)
            end
            root:SetScrollMode(30 * 20)
        end)
        c.dropdown = dd
        c.SetSelected = function(self, n)
            curSel = n; dd:GenerateMenu()
            if dd.Text then dd.Text:SetText((n or "None"):gsub("|c%x%x%x%x%x%x%x%x",""):gsub("|r","")) end
        end
    else
        local btn = BNB.CreateBackdropFrame("Button", nil, c)
        btn:SetHeight(22); btn:SetPoint("TOPLEFT",c,"TOPLEFT",0,-18); btn:SetPoint("RIGHT",c,"RIGHT",0,0)
        if btn.SetBackdrop then
            btn:SetBackdrop({bgFile="Interface\\Buttons\\White8x8",edgeFile="Interface\\Tooltips\\UI-Tooltip-Border",edgeSize=10,insets={left=2,right=2,top=2,bottom=2}})
            btn:SetBackdropColor(0.08,0.08,0.10,0.95); btn:SetBackdropBorderColor(0.35,0.35,0.35,1)
        end
        local st = btn:CreateFontString(nil,"ARTWORK","GameFontNormalSmall")
        st:SetPoint("LEFT",6,0); st:SetPoint("RIGHT",-20,0); st:SetJustifyH("LEFT"); st:SetText(selected or "None")
        local ar = btn:CreateTexture(nil,"ARTWORK"); ar:SetSize(12,12); ar:SetPoint("RIGHT",-3,0)
        ar:SetTexture("Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Up")
        local pp = CreateFrame("Frame",nil,btn,"BackdropTemplate"); pp:SetFrameStrata("FULLSCREEN_DIALOG"); pp:SetFrameLevel(500); pp:SetClampedToScreen(true)
        if pp.SetBackdrop then pp:SetBackdrop({bgFile="Interface\\Buttons\\White8x8",edgeFile="Interface\\Tooltips\\UI-Tooltip-Border",edgeSize=10,insets={left=2,right=2,top=2,bottom=2}}); pp:SetBackdropColor(0.06,0.06,0.06,0.97); pp:SetBackdropBorderColor(0.5,0.5,0.5,1) end
        pp:Hide(); pp:EnableMouse(true)
        local psf=CreateFrame("ScrollFrame",nil,pp,"ScrollFrameTemplate"); psf:SetPoint("TOPLEFT",4,-4); psf:SetPoint("BOTTOMRIGHT",-4,4)
        local psc=CreateFrame("Frame",nil,psf); psf:SetScrollChild(psc)
        local function Pop()
            for _,ch in ipairs({psc:GetChildren()}) do ch:Hide(); ch:SetParent(nil) end
            local items=getEntries and getEntries() or {}; local rH,tH=20,0; psc:SetWidth(pp:GetWidth()-10)
            for _,nm in ipairs(items) do
                local row=CreateFrame("Button",nil,psc); row:SetHeight(rH); row:SetPoint("TOPLEFT",0,-tH); row:SetPoint("RIGHT")
                local hl=row:CreateTexture(nil,"HIGHLIGHT"); hl:SetAllPoints(); hl:SetColorTexture(0.3,0.5,0.8,0.3)
                local fs=row:CreateFontString(nil,"ARTWORK","GameFontNormalSmall"); fs:SetPoint("LEFT",6,0); fs:SetText(nm)
                row:SetScript("OnClick",function() st:SetText(nm); pp:Hide(); if onChange then onChange(nm) end end)
                tH=tH+rH
            end
            psc:SetHeight(math.max(tH,1)); pp:SetHeight(math.min(tH+10,260))
        end
        btn:SetScript("OnClick",function() if pp:IsShown() then pp:Hide(); return end; pp:SetWidth(btn:GetWidth()); Pop(); pp:ClearAllPoints()
            if (btn:GetBottom() or 0)-260<0 then pp:SetPoint("BOTTOMLEFT",btn,"TOPLEFT",0,2) else pp:SetPoint("TOPLEFT",btn,"BOTTOMLEFT",0,-2) end; pp:Show() end)
        c.SetSelected = function(self,n) st:SetText(n or "None") end
    end
    return c
end

-- ── Color picker ──────────────────────────────────────────────────────────────
local function OpenColorPicker(r, g, b, onDone)
    if ColorPickerFrame.SetupColorPickerAndShow then
        ColorPickerFrame:SetupColorPickerAndShow({
            swatchFunc = function() local nr,ng,nb=ColorPickerFrame:GetColorRGB(); onDone(nr,ng,nb) end,
            cancelFunc = function() end, hasOpacity=false, r=r, g=g, b=b })
    else
        ColorPickerFrame.func       = function() local nr,ng,nb=ColorPickerFrame:GetColorRGB(); onDone(nr,ng,nb) end
        ColorPickerFrame.cancelFunc = function() end
        ColorPickerFrame.hasOpacity = false
        ColorPickerFrame:SetColorRGB(r,g,b); ShowUIPanel(ColorPickerFrame)
    end
end

-- ─────────────────────────────────────────────────────────────────────────────
-- TAB 1 — GENERAL
-- ─────────────────────────────────────────────────────────────────────────────
local _hlFonts    -- forward ref, set inside BuildGeneralTab

local function BuildGeneralTab(sf, ct)
    -- sf = ScrollFrame, ct = scroll child (content frame)
    -- Use ct as the parent for all content; finalise scroll height at end.
    local panel = ct   -- alias so existing code is unchanged
    local y = -4
    local _cbPinned, _cbFavorited

    y, _cbPinned = Check(panel, y, "Pin to top of note list",
        function() local n=GetNote(); return n and n.pinned==true end,
        function(v) Save({pinned=v}); if BNB.RefreshNoteList then BNB.RefreshNoteList() end end,
        "Pinned notes always appear at the top of the list regardless of sort order.")
    y = y - 2

    -- Favorite ─────────────────────────────────────────────────────────────────
    y, _cbFavorited = Check(panel, y, "Mark as favorite",
        function() local n=GetNote(); return n and n.favorited==true end,
        function(v)
            if v then
                Save({favorited = true})
            else
                if not _noteID then return end
                BNB.UpdateNote(_noteID, {_clear = {"favorited"}})
                if BNB.RefreshNoteList then BNB.RefreshNoteList() end
                if BNB.Sticky and BNB.Sticky.RefreshNote then BNB.Sticky.RefreshNote(_noteID) end
            end
        end,
        "Favorite notes show a star overlay and can be sorted to the top.")
    y = y - 4

    -- Rich note ────────────────────────────────────────────────────────────────
    y = Rule(panel, y) - 4
    y = Hdr(panel, y, "Note type")

    local _cbRich
    y, _cbRich = Check(panel, y, "Rich note (markup formatting)",
        function() local n=GetNote(); return n and n.richMode==true end,
        function(v)
            if not _noteID then return end
            if v then
                Save({richMode = true})
                if BNB.LoadNoteInEditor and BNB._currentNoteID == _noteID then
                    BNB.LoadNoteInEditor(_noteID)
                end
            else
                -- Confirm before stripping tags
                if BNB.AdvancedMode then
                    BNB.AdvancedMode.ConvertToPlain(_noteID, function(confirmed)
                        if not confirmed then
                            -- User cancelled — revert checkbox
                            if _cbRich then _cbRich:SetChecked(true) end
                        end
                    end)
                else
                    Save({richMode = false})
                    if BNB.LoadNoteInEditor and BNB._currentNoteID == _noteID then
                        BNB.LoadNoteInEditor(_noteID)
                    end
                end
            end
        end,
        "Rich notes support formatted markup: {h1} headers, {img} images,\n{icon} icons, {col} colours and {link} links.\n\nDisabling will remove all formatting tags from the note body.")
    y = y - 4
    y = Rule(panel, y) - 4
    y = Hdr(panel, y, "Title color")

    y = BNB.BuildColorGrid(panel, y, CW_SCROLL, function(r, g, b)
        Save({titleColor = {r=r, g=g, b=b}})
    end)

    local cpBtn = BNB.CreateButton(nil, panel, "Custom color", 96, 22)
    cpBtn:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, y)
    cpBtn:SetScript("OnClick", function()
        local note = GetNote()
        local cr = (note and note.titleColor and note.titleColor.r) or 1
        local cg = (note and note.titleColor and note.titleColor.g) or 1
        local cb = (note and note.titleColor and note.titleColor.b) or 1
        OpenColorPicker(cr, cg, cb, function(r, g, b) Save({titleColor = {r=r, g=g, b=b}}) end)
    end)
    local resetClr = BNB.CreateButton(nil, panel, "Reset", 60, 22)
    resetClr:SetPoint("LEFT", cpBtn, "RIGHT", 6, 0)
    resetClr:SetScript("OnClick", function()
        if not _noteID then return end
        BNB.UpdateNote(_noteID, {_clear = {"titleColor"}})
        if BNB.RefreshNoteList then BNB.RefreshNoteList() end
        if BNB.Sticky and BNB.Sticky.RefreshNote then BNB.Sticky.RefreshNote(_noteID) end
    end)
    y = y - 30

    -- Font ─────────────────────────────────────────────────────────────────────
    y = Rule(panel,y) - 4
    y = Hdr(panel,y,"Font")

    -- Font card picker — 2-column grid (matches sticky note settings layout)
    local PH     = 38    -- card height
    local PG     = 4     -- vertical gap between rows
    local COL_GAP_F = 4  -- horizontal gap between columns
    local CARD_W_F  = math.floor((CW_SCROLL - COL_GAP_F) / 2)
    local fontPickerBtns = {}

    local function HLFonts()
        local note    = GetNote()
        local current = note and note.fontOverride or nil
        for _,e in ipairs(fontPickerBtns) do
            local sel = (e.id == current)
            if e.btn.SetBackdropColor then
                if sel then e.btn:SetBackdropColor(0.12,0.18,0.12,0.95); e.btn:SetBackdropBorderColor(0.4,0.8,0.4,1)
                else        e.btn:SetBackdropColor(0.06,0.06,0.08,0.95); e.btn:SetBackdropBorderColor(0.28,0.28,0.30,1) end
            end
            if e.nameLbl then e.nameLbl:SetTextColor(sel and 1 or 0.85, sel and 0.82 or 0.85, sel and 0 or 0.85, 1) end
        end
    end
    _hlFonts = HLFonts

    -- LSM fonts appear in the dropdown below; exclude from the card grid.
    local _allFonts_nc = BNB.FONTS or {}
    local fonts_nc = {}
    for _, def in ipairs(_allFonts_nc) do
        if not def._isLSM then fonts_nc[#fonts_nc + 1] = def end
    end
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
            if (note and note.fontOverride or nil) ~= def.id then
                s:SetBackdropColor(0.10,0.12,0.10,0.95); s:SetBackdropBorderColor(0.35,0.55,0.35,1)
            end
        end)
        btn:SetScript("OnLeave", HLFonts)
        btn:SetScript("OnClick", function()
            Save({fontOverride = def.id})
            local sz = BigNoteBoxDB and BigNoteBoxDB.fontSize or 13
            if BNB._editorBody  then pcall(function() BNB._editorBody:SetFont(def.regular, sz, "") end) end
            if BNB._editorTitle then pcall(function() BNB._editorTitle:SetFont(def.bold, 20, "") end) end
            HLFonts()
            if BNB._refreshWysiwygFont then BNB._refreshWysiwygFont() end
        end)
        local nameLbl = btn:CreateFontString(nil, "OVERLAY")
        nameLbl:SetPoint("TOPLEFT",  btn, "TOPLEFT",  5, -5)
        nameLbl:SetPoint("TOPRIGHT", btn, "TOPRIGHT", -5, -5)
        nameLbl:SetJustifyH("LEFT"); nameLbl:SetHeight(16)
        if def.bold and def.bold ~= "" then pcall(function() nameLbl:SetFont(def.bold, 11, "") end)
        else nameLbl:SetFontObject("GameFontNormal") end
        nameLbl:SetText(def.label)
        local prevLbl = btn:CreateFontString(nil, "OVERLAY")
        prevLbl:SetPoint("BOTTOMLEFT",  btn, "BOTTOMLEFT",  5, 5)
        prevLbl:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -5, 5)
        prevLbl:SetJustifyH("LEFT"); prevLbl:SetHeight(12)
        if def.regular and def.regular ~= "" then pcall(function() prevLbl:SetFont(def.regular, 10, "") end)
        else prevLbl:SetFontObject("GameFontNormalSmall") end
        prevLbl:SetTextColor(0.55, 0.55, 0.55); prevLbl:SetText(def.preview or "")
        fontPickerBtns[#fontPickerBtns+1] = {btn=btn, id=def.id, nameLbl=nameLbl, prevLbl=prevLbl, def=def}
    end
    -- Advance y past the grid
    local gridRows_nc = math.ceil(#fonts_nc / 2)
    y = y - gridRows_nc * (PH + PG) + PG

    -- LSM font dropdown: appears below the bundled card grid when lsmFonts is on.
    -- Uses the shared BuildLSMFontDropdown helper from ConfigWindow.lua.
    -- CW_SCROLL (224px) used instead of CONTENT_W to match NoteConfig panel width.
    if BigNoteBoxDB and BigNoteBoxDB.lsmFonts
       and BNB._BuildLSMFontDropdown then
        y = BNB._BuildLSMFontDropdown(panel, y,
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
                    or (BigNoteBoxDB and BigNoteBoxDB.fontSize) or 13
                local eb = BNB._editorBody
                if eb and BNB._currentNoteID == _noteID then
                    local def = path and BNB.GetFontDef and BNB.GetFontDef(path)
                    if def then
                        pcall(function() eb:SetFont(def.regular, sz, "") end)
                    elseif BNB.ApplyFont then
                        BNB.ApplyFont()
                    end
                end
                HLFonts()
                if BNB._refreshWysiwygFont then BNB._refreshWysiwygFont() end
            end,
            CW_SCROLL)
        y = y - 4
    end

    -- Re-apply fonts one frame after the panel first becomes visible.
    local function ReapplyFontPreviews()
        for _,e in ipairs(fontPickerBtns) do
            local def = e.def
            if def.bold    and def.bold    ~= "" then pcall(function() e.nameLbl:SetFont(def.bold,    12, "") end) end
            if def.regular and def.regular ~= "" then pcall(function() e.prevLbl:SetFont(def.regular, 10, "") end) end
            e.nameLbl:SetText(def.label)
            e.prevLbl:SetText(def.preview or "")
        end
    end
    panel._reapplyFontPreviews = ReapplyFontPreviews

    -- Font size slider
    y = Rule(panel,y) - 4
    y = Hdr(panel,y,"Font size")

    local function GetNoteFontSize()
        local n = GetNote(); return (n and n.fontSize) or 12
    end

    local fsVal = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    fsVal:SetPoint("TOPRIGHT", panel, "TOPLEFT", CW_SCROLL, y + 14)
    fsVal:SetTextColor(0.60, 0.60, 0.60)
    fsVal:SetText(GetNoteFontSize() .. "pt")

    local useNativeFS = C_XMLUtil and C_XMLUtil.GetTemplateInfo
        and C_XMLUtil.GetTemplateInfo("MinimalSliderWithSteppersTemplate")
        and MinimalSliderWithSteppersMixin

    local fsSl  -- outer ref for refresh closure
    if useNativeFS then
        fsSl = CreateFrame("Slider", nil, panel, "MinimalSliderWithSteppersTemplate")
        fsSl:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, y)
        fsSl:SetPoint("RIGHT",   panel, "TOPLEFT", CW_SCROLL, 0)
        fsSl:SetHeight(20)
        fsSl:Init(GetNoteFontSize(), 8, 32, 24)
        fsSl:RegisterCallback(MinimalSliderWithSteppersMixin.Event.OnValueChanged, function(_, v)
            local sz = math.floor(v)
            fsVal:SetText(sz .. "pt")
            Save({fontSize = sz})
            if BNB._editorBody and BNB._currentNoteID == _noteID then
                local path = select(1, BNB._editorBody:GetFont())
                if path then pcall(function() BNB._editorBody:SetFont(path, sz, "") end) end
            end
            if BNB._refreshWysiwygFont then BNB._refreshWysiwygFont() end
        end)
        y = y - 26
    else
        fsSl = BNB.CreateSlider(panel, "", 8, 32, GetNoteFontSize(), nil,
            function(v)
                fsVal:SetText(v .. "pt")
                Save({fontSize = v})
                if BNB._editorBody and BNB._currentNoteID == _noteID then
                    local path = select(1, BNB._editorBody:GetFont())
                    if path then pcall(function() BNB._editorBody:SetFont(path, v, "") end) end
                end
                if BNB._refreshWysiwygFont then BNB._refreshWysiwygFont() end
            end,
            function(v) return math.floor(v) .. "pt" end)
        fsSl:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, y)
        fsSl:SetWidth(CW_SCROLL)
        y = y - 38
    end

    -- Reset to default button
    local fsResetBtn = BNB.CreateButton(nil, panel, "Reset to default", 110, 20)
    fsResetBtn:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, y)
    fsResetBtn:SetScript("OnClick", function()
        if not _noteID then return end
        BNB.UpdateNote(_noteID, {_clear = {"fontSize"}})
        local globalSz = (BigNoteBoxDB and BigNoteBoxDB.fontSize) or 12
        fsVal:SetText(globalSz .. "pt")
        if fsSl and fsSl.SetValue then pcall(fsSl.SetValue, fsSl, globalSz) end
        if BNB._editorBody and BNB._currentNoteID == _noteID then
            local path = select(1, BNB._editorBody:GetFont())
            if path then pcall(function() BNB._editorBody:SetFont(path, globalSz, "") end) end
        end
        if BNB.RefreshNoteList then BNB.RefreshNoteList() end
    end)
    y = y - 28

    -- Refresh callback for note switching
    panel._refreshFontSize = function()
        local sz = GetNoteFontSize()
        fsVal:SetText(sz .. "pt")
        if fsSl and fsSl.SetValue then pcall(fsSl.SetValue, fsSl, sz) end
    end

    -- E — Text alignment (applies to main editor body)
    y = Rule(panel,y) - 4
    y = Hdr(panel,y,"Text alignment")

    local ALIGN_OPTIONS_NC = { "Left", "Center", "Right" }
    local ALIGN_MAP_NC     = { Left="LEFT", Center="CENTER", Right="RIGHT" }
    local ALIGN_RMAP_NC    = { LEFT="Left", CENTER="Center", RIGHT="Right" }

    local function GetNoteAlignLabel()
        local note = GetNote()
        return ALIGN_RMAP_NC[(note and note.textAlign) or "LEFT"] or "Left"
    end
    local function ApplyNoteAlign(align)
        Save({textAlign = align})
        if BNB._editorBody then
            pcall(function() BNB._editorBody:SetJustifyH(align) end)
        end
    end

    local useNativeAlignNC = C_XMLUtil and C_XMLUtil.GetTemplateInfo
        and C_XMLUtil.GetTemplateInfo("WowStyle1DropdownTemplate")
    if useNativeAlignNC then
        local alignDD = CreateFrame("DropdownButton", "BNBNoteAlignDD", panel,
            "WowStyle1DropdownTemplate")
        alignDD:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, y)
        alignDD:SetWidth(CW_SCROLL)
        alignDD:SetupMenu(function(_, root)
            for _, opt in ipairs(ALIGN_OPTIONS_NC) do
                local o = opt
                root:CreateRadio(o,
                    function() return GetNoteAlignLabel() == o end,
                    function()
                        ApplyNoteAlign(ALIGN_MAP_NC[o])
                        alignDD:GenerateMenu()
                    end)
            end
        end)
        y = y - 36
    else
        local alignBtn = BNB.CreateButton(nil, panel, GetNoteAlignLabel(), CW_SCROLL, 22)
        alignBtn:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, y)
        alignBtn:SetScript("OnClick", function(self)
            local cur = GetNoteAlignLabel()
            local idx = 1
            for i, o in ipairs(ALIGN_OPTIONS_NC) do if o == cur then idx = i; break end end
            idx = (idx % #ALIGN_OPTIONS_NC) + 1
            local opt = ALIGN_OPTIONS_NC[idx]
            ApplyNoteAlign(ALIGN_MAP_NC[opt])
            self:SetText(opt)
        end)
        y = y - 28
    end

    -- F — Font outline (applies to main editor body)
    y = Rule(panel,y) - 4
    y = Hdr(panel,y,"Font outline")

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

    local useNativeOutlineNC = useNativeAlignNC
    if useNativeOutlineNC then
        local outlineDD = CreateFrame("DropdownButton", "BNBNoteOutlineDD", panel,
            "WowStyle1DropdownTemplate")
        outlineDD:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, y)
        outlineDD:SetWidth(CW_SCROLL)
        outlineDD:SetupMenu(function(_, root)
            for _, opt in ipairs(OUTLINE_OPTIONS_NC) do
                local o = opt
                root:CreateRadio(o,
                    function() return GetNoteOutlineLabel() == o end,
                    function()
                        ApplyNoteOutline(o)
                        outlineDD:GenerateMenu()
                    end)
            end
        end)
        y = y - 36
    else
        local outlineBtn = BNB.CreateButton(nil, panel, GetNoteOutlineLabel(), CW_SCROLL, 22)
        outlineBtn:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, y)
        outlineBtn:SetScript("OnClick", function(self)
            local cur = GetNoteOutlineLabel()
            local idx = 1
            for i, o in ipairs(OUTLINE_OPTIONS_NC) do if o == cur then idx = i; break end end
            idx = (idx % #OUTLINE_OPTIONS_NC) + 1
            local opt = OUTLINE_OPTIONS_NC[idx]
            ApplyNoteOutline(opt)
            self:SetText(opt)
        end)
        y = y - 28
    end

    y = Hdr(panel,y,"Lock")

    local lockBtns = {}
    local BTN_W = 110

    -- Default button — clears per-note override, follows global setting
    local defaultBtn = BNB.CreateButton(nil, panel, "Default", BTN_W, 22)
    defaultBtn:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, y)
    defaultBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        local globalLocked = BigNoteBoxDB and BigNoteBoxDB.lockNotes == true
        GameTooltip:AddLine("Follow the global lock setting (Config → Features).\n"
            .. "Currently global is: "
            .. (globalLocked and "|cffff9900Locked|r" or "|cff66bb6aUnlocked|r"),
            0.85, 0.85, 0.85, true)
        GameTooltip:Show()
    end)
    defaultBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    lockBtns[#lockBtns+1] = { btn = defaultBtn, val = nil }

    -- Single Lock / Unlock toggle button — label changes based on current state
    local toggleBtn = BNB.CreateButton(nil, panel, "Lock", BTN_W, 22)
    toggleBtn:SetPoint("TOPLEFT", panel, "TOPLEFT", BTN_W + 6, y)
    toggleBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        local note = GetNote()
        local cur  = note and note.locked
        if cur == true then
            GameTooltip:AddLine("Click to unlock this note.\nIt will open in edit mode regardless of the global setting.", 0.85, 0.85, 0.85, true)
        else
            GameTooltip:AddLine("Click to lock this note.\nIt will open in read-only mode regardless of the global setting.", 0.85, 0.85, 0.85, true)
        end
        GameTooltip:Show()
    end)
    toggleBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    lockBtns[#lockBtns+1] = { btn = toggleBtn, val = "toggle" }

    local function HLLockBtns()
        local note = GetNote()
        local cur  = note and note.locked
        -- Default button is disabled when note is already in default state
        defaultBtn:SetEnabled(cur ~= nil)
        -- Toggle button label reflects what clicking it will DO next
        if cur == true then
            toggleBtn:SetText("Unlock")
        else
            toggleBtn:SetText("Lock")
        end
    end

    defaultBtn:SetScript("OnClick", function()
        Save({_clear = {"locked"}})
        if BNB.RefreshEditorLock then BNB.RefreshEditorLock() end
        if _noteID == BNB._currentNoteID and BNB.LoadNoteInEditor then
            BNB.LoadNoteInEditor(_noteID)
        end
        HLLockBtns()
    end)
    toggleBtn:SetScript("OnClick", function()
        local note = GetNote()
        local cur  = note and note.locked
        local newVal
        if cur == true then
            newVal = false   -- was locked → unlock explicitly
        else
            newVal = true    -- was nil/false → lock explicitly
        end
        Save({locked = newVal})
        if BNB.RefreshEditorLock then BNB.RefreshEditorLock() end
        if _noteID == BNB._currentNoteID and BNB.LoadNoteInEditor then
            BNB.LoadNoteInEditor(_noteID)
        end
        HLLockBtns()
    end)

    y = y - 30

    y = Rule(panel,y) - 4
    -- ── Scope (Global / This character) ───────────────────────────────────────
    y = Hdr(panel, y, "Note visibility")

    -- Two-button toggle: [Global]  [This character ▾]
    -- Below them: Send to Alt dropdown (only shown when scope is character-scoped)
    local scopeBtnW = math.floor(CW_SCROLL / 2) - 2

    local scopeGlobalBtn = BNB.CreateButton(nil, panel, L["SCOPE_GLOBAL"], scopeBtnW, 24)
    scopeGlobalBtn:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, y)

    local scopeCharBtn = BNB.CreateButton(nil, panel, L["SCOPE_THIS_CHAR"], scopeBtnW, 24)
    scopeCharBtn:SetPoint("LEFT", scopeGlobalBtn, "RIGHT", 4, 0)

    y = y - 28

    -- "Send to Alt" row — only visible when note is character-scoped
    local sendRow = CreateFrame("Frame", nil, panel)
    sendRow:SetHeight(26)
    sendRow:SetPoint("TOPLEFT",  panel, "TOPLEFT",  0, y)
    sendRow:SetPoint("TOPRIGHT", panel, "TOPRIGHT", 0, y)
    sendRow:Hide()

    local sendLbl = sendRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    sendLbl:SetPoint("LEFT", sendRow, "LEFT", 0, 0)
    sendLbl:SetTextColor(0.65, 0.65, 0.65)
    sendLbl:SetText(L["SCOPE_SEND_LABEL"])

    local sendBtn = BNB.CreateButton(nil, sendRow, L["SCOPE_SEND_BTN"], 160, 22)
    sendBtn:SetPoint("LEFT", sendLbl, "RIGHT", 8, 0)

    -- Send-to dropdown (WowStyle1DropdownTemplate)
    local sendDrop = nil
    local function GetKnownChars()
        local list = {}
        local db = BigNoteBoxDB
        if db and db.knownChars then
            for key, info in pairs(db.knownChars) do
                if key ~= BNB.currentChar then
                    list[#list + 1] = { key = key, name = info.name, realm = info.realm, class = info.class }
                end
            end
            table.sort(list, function(a, b) return (a.name or "") < (b.name or "") end)
        end
        return list
    end

    local function DoSendToChar(charKey)
        if not _noteID then return end
        BNB.UpdateNote(_noteID, { scope = "char:" .. charKey })
        if BNB.RefreshNoteList then BNB.RefreshNoteList() end
        -- Close NoteConfig — the note is no longer visible to this character
        if ncFrame then ncFrame:Hide() end
    end

    sendBtn:SetScript("OnClick", function()
        local chars = GetKnownChars()
        if #chars == 0 then
            BNB:Print(L["SCOPE_NO_ALTS"])
            return
        end
        -- Build dropdown
        if not sendDrop then
            sendDrop = CreateFrame("DropdownButton", "BNBScopeSendDrop", UIParent,
                "WowStyle1DropdownTemplate")
            sendDrop:SetSize(1, 1)
            sendDrop:SetAlpha(0)
        end
        sendDrop:ClearAllPoints()
        sendDrop:SetPoint("TOPLEFT", sendBtn, "TOPRIGHT", 0, 0)
        sendDrop:SetupMenu(function(_, root)
            for _, c in ipairs(chars) do
                local clr = RAID_CLASS_COLORS and c.class and RAID_CLASS_COLORS[c.class]
                local hex = clr and string.format("|cff%02x%02x%02x", clr.r*255, clr.g*255, clr.b*255) or "|cffffffff"
                local label = hex .. (c.name or c.key) .. "|r  |cff888888" .. (c.realm or "") .. "|r"
                local key = c.key
                root:CreateButton(label, function() DoSendToChar(key) end)
            end
        end)
        sendDrop:OpenMenu()
    end)

    y = y - 30

    -- Highlight helper for the two toggle buttons
    local function RefreshScopeBtns()
        local note = GetNote()
        local sc   = note and note.scope or "global"
        local isChar = sc and sc:match("^char:") ~= nil

        -- Global button: gold-tinted when active
        if scopeGlobalBtn._fs then
            scopeGlobalBtn._fs:SetTextColor(
                isChar and 0.6 or 1,
                isChar and 0.55 or 0.82,
                isChar and 0.45 or 0)
        end
        -- Char button: amber when active
        if scopeCharBtn._fs then
            if isChar then
                -- Show short char name inside the button
                local charName = (sc:match("^char:(.-)%-") or BNB.currentChar or ""):sub(1, 12)
                scopeCharBtn._fs:SetText("|cffffaa00" .. charName .. "|r")
            else
                scopeCharBtn._fs:SetText(L["SCOPE_THIS_CHAR"])
                scopeCharBtn._fs:SetTextColor(0.6, 0.6, 0.6)
            end
        end
        -- Send row: only shown when note is scoped to a character
        if isChar then sendRow:Show() else sendRow:Hide() end
    end

    -- Capture FontStrings on the toggle buttons (UIPanelButtonTemplate exposes
    -- the label via GetFontString()). Deferred one tick so layout finishes first.
    C_Timer.After(0, function()
        scopeGlobalBtn._fs = scopeGlobalBtn._fs
            or (scopeGlobalBtn.GetFontString and scopeGlobalBtn:GetFontString())
        scopeCharBtn._fs  = scopeCharBtn._fs
            or (scopeCharBtn.GetFontString  and scopeCharBtn:GetFontString())
        RefreshScopeBtns()
    end)

    scopeGlobalBtn:SetScript("OnClick", function()
        if not _noteID then return end
        BNB.UpdateNote(_noteID, { scope = "global" })
        if BNB.RefreshNoteList then BNB.RefreshNoteList() end
        RefreshScopeBtns()
    end)
    scopeCharBtn:SetScript("OnClick", function()
        if not _noteID then return end
        local cur = BNB.currentChar or "Unknown"
        BNB.UpdateNote(_noteID, { scope = "char:" .. cur })
        if BNB.RefreshNoteList then BNB.RefreshNoteList() end
        RefreshScopeBtns()
    end)

    -- Store refresh callback so OpenNoteConfig can call it when switching notes
    sf._refreshScope = RefreshScopeBtns
    panel._hlFonts    = HLFonts
    panel._hlLockBtns = HLLockBtns
    sf._hlFonts       = HLFonts
    sf._hlLockBtns    = HLLockBtns
    sf._reapplyFontPreviews = ReapplyFontPreviews
    sf._refreshFontSize     = panel._refreshFontSize
    -- Refresh pinned/favorited checkboxes when switching notes
    panel._refreshChecks = function()
        if _cbPinned   then _cbPinned:SetChecked(_cbPinned._getter())     end
        if _cbFavorited then _cbFavorited:SetChecked(_cbFavorited._getter()) end
    end
    -- Finalise scroll content height
    sf:FinaliseHeight(math.abs(y) + 12)
end

-- ─────────────────────────────────────────────────────────────────────────────
-- TAB 2 — APPEARANCE
-- Uses a scrollable panel because the icon grid can be tall
-- ─────────────────────────────────────────────────────────────────────────────
local iconScrollChild
local iconGridSF   -- scroll frame, stored so RefreshIconGrid can sync scrollbar alpha

local function RefreshIconGrid(scrollToSelected)
    if not iconScrollChild then return end
    local note    = GetNote()
    local current = note and note.icon or ""
    local icons   = GetFilteredIcons(_filter)

    local rows   = math.max(1, math.ceil(#icons / GRID_COLS))
    local totalH = rows * (CELL + CELL_PAD) + CELL_PAD
    iconScrollChild:SetHeight(totalH)

    local selectedRow = nil   -- 0-based row of the selected icon (for scroll)

    for i, path in ipairs(icons) do
        if not iconBtns[i] then
            local btn = CreateFrame("Button", nil, iconScrollChild)
            btn:SetSize(CELL, CELL)
            local tex = btn:CreateTexture(nil, "ARTWORK")
            tex:SetAllPoints(); tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            btn._tex = tex
            -- Stronger selection highlight: solid green border overlay
            local sel = btn:CreateTexture(nil, "OVERLAY")
            sel:SetPoint("TOPLEFT",     btn, "TOPLEFT",     -2, 2)
            sel:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT",  2, -2)
            sel:SetColorTexture(0.2, 0.9, 0.2, 0.55)
            sel:Hide()
            btn._sel = sel
            local hi = btn:CreateTexture(nil, "HIGHLIGHT")
            hi:SetAllPoints(); hi:SetColorTexture(1, 1, 1, 0.25)
            btn:SetScript("OnEnter", function(s)
                GameTooltip:SetOwner(s, "ANCHOR_RIGHT")
                local name = (s._path or ""):match("([^\\/:]+)$") or ""
                GameTooltip:AddLine(name, 1, 1, 1)
                GameTooltip:Show()
            end)
            btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
            btn:SetScript("OnClick", function(s)
                Save({icon = s._path}); RefreshIconGrid()
            end)
            iconBtns[i] = btn
        end
        local btn = iconBtns[i]
        local col = (i - 1) % GRID_COLS
        local row = math.floor((i - 1) / GRID_COLS)
        btn:ClearAllPoints()
        btn:SetPoint("TOPLEFT", iconScrollChild, "TOPLEFT",
            CELL_PAD + col * (CELL + CELL_PAD),
            -(CELL_PAD + row * (CELL + CELL_PAD)))
        btn._path = path
        btn._tex:SetTexture(path)
        local isSel = (path == current)
        btn._sel:SetShown(isSel)
        if isSel then selectedRow = row end
        btn:Show()
    end
    for i = #icons + 1, #iconBtns do iconBtns[i]:Hide() end

    -- Scroll to show the selected icon when requested (on open or icon change)
    if scrollToSelected and selectedRow and iconGridSF then
        C_Timer.After(0, function()
            if not iconGridSF then return end
            local sfH    = iconGridSF:GetHeight()
            local rowTop = selectedRow * (CELL + CELL_PAD)
            local rowBot = rowTop + CELL + CELL_PAD
            local cur    = iconGridSF:GetVerticalScroll()
            if rowTop < cur then
                iconGridSF:SetVerticalScroll(math.max(0, rowTop - CELL_PAD))
            elseif rowBot > cur + sfH then
                iconGridSF:SetVerticalScroll(rowTop - CELL_PAD)
            end
        end)
    end

    -- Sync scrollbar visibility. sf.ScrollBar may be nil on some retail builds;
    -- fall back to searching for a Slider child on the scroll frame itself.
    -- Then set alpha on it plus all its own children and regions so
    -- (which doesn't propagate parent alpha) also shows/hides correctly.
    local function SyncIconScrollbar()
        local sf = iconGridSF
        if not sf then return end
        -- Find the scrollbar widget
        local bar = sf.ScrollBar
        if not bar then
            for _, child in ipairs({sf:GetChildren()}) do
                if child.IsObjectType and child:IsObjectType("Slider") then
                    bar = child; break
                end
            end
        end
        if not bar then return end
        local ch       = sf:GetScrollChild()
        local overflow = ch and (ch:GetHeight() > sf:GetHeight() + 2)
        local a = overflow and 1.0 or 0.0
        bar:SetAlpha(a)
        for _, child in ipairs({bar:GetChildren()}) do
            pcall(function() child:SetAlpha(a) end)
        end
        for _, region in ipairs({bar:GetRegions()}) do
            pcall(function() region:SetAlpha(a) end)
        end
    end
    C_Timer.After(0, SyncIconScrollbar)
end

local function BuildAppearanceTab(panel)
    local y = -4

    -- Border dropdown
    y = Hdr(panel, y, "Border")
    local note0   = GetNote()
    local curBord = (note0 and note0.borderOverride) or "None"
    local bDrop = CreateDropdown(panel, "Border style",
        LSMBorderList, curBord,
        function(name)
            if name == "None" then
                BNB.UpdateNote(_noteID, {_clear = {"borderOverride"}})
            else
                BNB.UpdateNote(_noteID, {borderOverride = name})
            end
            if BNB.RefreshNoteList then BNB.RefreshNoteList() end
            if BNB.Sticky and BNB.Sticky.RefreshNote then BNB.Sticky.RefreshNote(_noteID) end
        end,
        nil)
    bDrop:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, y); bDrop:SetWidth(CW)
    y = y - 50

    -- Border thickness slider (label above, full-width slider with value)
    local function GetBorderScale()
        local n = GetNote(); return (n and n.borderScale) or 100
    end

    local bsLbl = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    bsLbl:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, y)
    bsLbl:SetTextColor(0.78, 0.78, 0.78); bsLbl:SetText("Border Thickness")
    y = y - 14

    local bsVal = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    bsVal:SetPoint("TOPRIGHT", panel, "TOPLEFT", CW, y + 14)
    bsVal:SetTextColor(0.60, 0.60, 0.60)
    bsVal:SetText(GetBorderScale() .. "%")

    local useNativeBS = C_XMLUtil and C_XMLUtil.GetTemplateInfo
        and C_XMLUtil.GetTemplateInfo("MinimalSliderWithSteppersTemplate")
        and MinimalSliderWithSteppersMixin

    local bsSl  -- outer ref for refresh closure
    if useNativeBS then
        bsSl = CreateFrame("Slider", nil, panel, "MinimalSliderWithSteppersTemplate")
        bsSl:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, y)
        bsSl:SetPoint("RIGHT", panel, "TOPLEFT", CW, 0)
        bsSl:SetHeight(20)
        bsSl:Init(GetBorderScale(), 1, 200, 199)
        local bsTracked = GetBorderScale()
        bsSl:RegisterCallback(MinimalSliderWithSteppersMixin.Event.OnValueChanged, function(_, v)
            bsTracked = math.floor(v)
            bsVal:SetText(bsTracked .. "%")
            Save({borderScale = bsTracked})
            if BNB.RefreshNoteList then BNB.RefreshNoteList() end
            if BNB.Sticky and BNB.Sticky.RefreshNote then BNB.Sticky.RefreshNote(_noteID) end
        end)
        y = y - 26
    else
        bsSl = BNB.CreateSlider(panel, "", 1, 200, GetBorderScale(), nil,
            function(v)
                bsVal:SetText(v .. "%")
                Save({borderScale = v})
                if BNB.RefreshNoteList then BNB.RefreshNoteList() end
                if BNB.Sticky and BNB.Sticky.RefreshNote then BNB.Sticky.RefreshNote(_noteID) end
            end,
            function(v) return math.floor(v) .. "%" end)
        bsSl:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, y)
        bsSl:SetWidth(CW)
        y = y - 38
    end

    -- Border offset slider (controls gap between icon and border)
    local function GetBorderOffset()
        local n = GetNote(); return (n and n.borderOffset) or 2
    end

    local boLbl = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    boLbl:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, y)
    boLbl:SetTextColor(0.78, 0.78, 0.78); boLbl:SetText("Border Offset")
    y = y - 14

    local boVal = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    boVal:SetPoint("TOPRIGHT", panel, "TOPLEFT", CW, y + 14)
    boVal:SetTextColor(0.60, 0.60, 0.60)
    boVal:SetText(GetBorderOffset() .. "px")

    local boSl  -- outer ref for refresh closure
    if useNativeBS then
        boSl = CreateFrame("Slider", nil, panel, "MinimalSliderWithSteppersTemplate")
        boSl:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, y)
        boSl:SetPoint("RIGHT", panel, "TOPLEFT", CW, 0)
        boSl:SetHeight(20)
        boSl:Init(GetBorderOffset(), 0, 12, 12)
        local boTracked = GetBorderOffset()
        boSl:RegisterCallback(MinimalSliderWithSteppersMixin.Event.OnValueChanged, function(_, v)
            boTracked = math.floor(v)
            boVal:SetText(boTracked .. "px")
            Save({borderOffset = boTracked})
            if BNB.RefreshNoteList then BNB.RefreshNoteList() end
            if BNB.Sticky and BNB.Sticky.RefreshNote then BNB.Sticky.RefreshNote(_noteID) end
        end)
        y = y - 26
    else
        boSl = BNB.CreateSlider(panel, "", 0, 12, GetBorderOffset(), nil,
            function(v)
                boVal:SetText(v .. "px")
                Save({borderOffset = v})
                if BNB.RefreshNoteList then BNB.RefreshNoteList() end
                if BNB.Sticky and BNB.Sticky.RefreshNote then BNB.Sticky.RefreshNote(_noteID) end
            end,
            function(v) return math.floor(v) .. "px" end)
        boSl:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, y)
        boSl:SetWidth(CW)
        y = y - 38
    end

    -- Border brightness slider
    local function GetBorderBrightness()
        local n = GetNote(); return (n and n.borderBrightness) or 100
    end

    local bbLbl = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    bbLbl:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, y)
    bbLbl:SetTextColor(0.78, 0.78, 0.78); bbLbl:SetText("Border Brightness")
    y = y - 14

    local bbVal = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    bbVal:SetPoint("TOPRIGHT", panel, "TOPLEFT", CW, y + 14)
    bbVal:SetTextColor(0.60, 0.60, 0.60)
    bbVal:SetText(GetBorderBrightness() .. "%")

    local bbSl  -- outer ref for refresh closure
    if useNativeBS then
        bbSl = CreateFrame("Slider", nil, panel, "MinimalSliderWithSteppersTemplate")
        bbSl:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, y)
        bbSl:SetPoint("RIGHT", panel, "TOPLEFT", CW, 0)
        bbSl:SetHeight(20)
        bbSl:Init(GetBorderBrightness(), 10, 200, 190)
        local bbTracked = GetBorderBrightness()
        bbSl:RegisterCallback(MinimalSliderWithSteppersMixin.Event.OnValueChanged, function(_, v)
            bbTracked = math.floor(v)
            bbVal:SetText(bbTracked .. "%")
            Save({borderBrightness = bbTracked})
            if BNB.RefreshNoteList then BNB.RefreshNoteList() end
            if BNB.Sticky and BNB.Sticky.RefreshNote then BNB.Sticky.RefreshNote(_noteID) end
        end)
        y = y - 26
    else
        bbSl = BNB.CreateSlider(panel, "", 10, 200, GetBorderBrightness(), nil,
            function(v)
                bbVal:SetText(v .. "%")
                Save({borderBrightness = v})
                if BNB.RefreshNoteList then BNB.RefreshNoteList() end
                if BNB.Sticky and BNB.Sticky.RefreshNote then BNB.Sticky.RefreshNote(_noteID) end
            end,
            function(v) return math.floor(v) .. "%" end)
        bbSl:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, y)
        bbSl:SetWidth(CW)
        y = y - 38
    end

    -- Icon section with BNB Icons / Blizzard Icon tabs
    y = Rule(panel, y) - 4
    y = Hdr(panel, y, "Icon")

    -- ── Tab buttons ──────────────────────────────────────────────────────────
    local TAB_W  = math.floor((CW - 4) / 2)
    local TAB_H  = 22
    local tabBNB = BNB.CreateButton(nil, panel, "BNB Icons",     TAB_W, TAB_H)
    local tabBLZ = BNB.CreateButton(nil, panel, "Blizzard Icon", TAB_W, TAB_H)
    tabBNB:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, y)
    tabBLZ:SetPoint("TOPLEFT", panel, "TOPLEFT", TAB_W + 4, y)
    y = y - TAB_H - 6

    -- Containers for each tab's content — both anchored to same y, one shown at a time
    local bnbPane = CreateFrame("Frame", nil, panel)
    bnbPane:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, y)
    bnbPane:SetWidth(CW)

    local blzPane = CreateFrame("Frame", nil, panel)
    blzPane:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, y)
    blzPane:SetWidth(CW)

    -- ── BNB Icons tab content ────────────────────────────────────────────────
    -- Search bar
    local sBg = BNB.CreateBackdropFrame("Frame", nil, bnbPane); BNB.SetBackdropDark(sBg)
    sBg:SetPoint("TOPLEFT", bnbPane, "TOPLEFT", 0, 0); sBg:SetWidth(CW); sBg:SetHeight(22)
    local sEb = CreateFrame("EditBox", nil, sBg)
    sEb:SetPoint("TOPLEFT", sBg, "TOPLEFT", 4, 0)
    sEb:SetPoint("BOTTOMRIGHT", sBg, "BOTTOMRIGHT", -24, 0)
    sEb:SetFontObject("GameFontNormal"); sEb:SetAutoFocus(false); sEb:SetMaxLetters(60)
    BNB.AddPlaceholder(sEb, "Search icons...", 0.4, 0.4, 0.4)

    -- Clear (X) button
    local sClear = CreateFrame("Button", nil, sBg)
    sClear:SetSize(18, 18)
    sClear:SetPoint("RIGHT", sBg, "RIGHT", -2, 0)
    local sClearLbl = sClear:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    sClearLbl:SetAllPoints(); sClearLbl:SetText("x")
    sClearLbl:SetTextColor(0.65, 0.65, 0.65)
    sClear:Hide()
    sClear:SetScript("OnEnter", function() sClearLbl:SetTextColor(1, 0.4, 0.4) end)
    sClear:SetScript("OnLeave", function() sClearLbl:SetTextColor(0.65, 0.65, 0.65) end)
    sClear:SetScript("OnClick", function()
        sEb:SetText(""); sEb._showingPlaceholder = false
        BNB.AddPlaceholder(sEb, "Search icons...", 0.4, 0.4, 0.4)
        _filter = ""; sClear:Hide()
        RefreshIconGrid()
    end)
    sEb:SetScript("OnTextChanged", function(self, u)
        if not u then return end
        _filter = self._showingPlaceholder and "" or (self:GetText() or "")
        if _filter ~= "" then sClear:Show() else sClear:Hide() end
        RefreshIconGrid()
    end)
    sEb:SetScript("OnEscapePressed", function(s) s:ClearFocus() end)

    -- Grid — 8 full rows of 32px icons, scrollbar on left
    local AREA_H = 8 * (CELL + CELL_PAD) + CELL_PAD   -- 283px
    local SBAR_W = 20
    local iSF = CreateFrame("ScrollFrame", nil, bnbPane, "ScrollFrameTemplate")
    iconGridSF = iSF
    iSF:SetPoint("TOPLEFT",  bnbPane, "TOPLEFT",  SBAR_W, -28)
    iSF:SetPoint("TOPRIGHT", bnbPane, "TOPRIGHT", 0, -28)
    iSF:SetHeight(AREA_H)

    local _iconBar
    local function SetIconBarAlpha(a)
        if not _iconBar then
            _iconBar = iSF.ScrollBar
            if not _iconBar then
                for _, child in ipairs({iSF:GetChildren()}) do
                    if child.IsObjectType and child:IsObjectType("Slider") then
                        _iconBar = child; break
                    end
                end
            end
        end
        if not _iconBar then return end
        _iconBar:ClearAllPoints()
        _iconBar:SetPoint("TOPLEFT",    iSF, "TOPLEFT",    -SBAR_W, 0)
        _iconBar:SetPoint("BOTTOMLEFT", iSF, "BOTTOMLEFT", -SBAR_W, 0)
        _iconBar:SetAlpha(a)
        for _, child in ipairs({_iconBar:GetChildren()}) do
            pcall(function() child:SetAlpha(a) end)
        end
        for _, region in ipairs({_iconBar:GetRegions()}) do
            pcall(function() region:SetAlpha(a) end)
        end
    end
    SetIconBarAlpha(0)
    iSF:HookScript("OnScrollRangeChanged", function(_, _, yRange)
        SetIconBarAlpha((yRange or 0) > 1 and 1.0 or 0)
    end)
    iconScrollChild = CreateFrame("Frame", nil, iSF)
    iconScrollChild:SetWidth(iSF:GetWidth() - 20)
    iconScrollChild:SetHeight(10)
    iSF:SetScrollChild(iconScrollChild)
    iSF:SetScript("OnSizeChanged", function(s)
        iconScrollChild:SetWidth(s:GetWidth() - 20)
    end)

    -- Use Default / Random buttons
    local btnW = math.floor((CW - 4) / 2)
    local clrBtn = BNB.CreateButton(nil, bnbPane, "Use Default", btnW, 22)
    clrBtn:SetPoint("TOPLEFT", bnbPane, "TOPLEFT", 0, -(28 + AREA_H + 4))
    clrBtn:SetScript("OnClick", function()
        if not _noteID then return end
        -- Pick a random icon from the Notes subfolder
        local noteIcons = {}
        for _, path in ipairs(ICON_LIST) do
            if path:find("\\Notes\\", 1, true) then
                noteIcons[#noteIcons + 1] = path
            end
        end
        if #noteIcons == 0 then return end
        local pick = noteIcons[math.random(#noteIcons)]
        BNB.UpdateNote(_noteID, {icon = pick, iconSource = "curated"})
        if BNB.RefreshNoteList then BNB.RefreshNoteList() end
        if BNB.Sticky and BNB.Sticky.RefreshNote then BNB.Sticky.RefreshNote(_noteID) end
        RefreshIconGrid(true)
    end)

    local rndBtn = BNB.CreateButton(nil, bnbPane, "Random", btnW, 22)
    rndBtn:SetPoint("TOPLEFT", bnbPane, "TOPLEFT", btnW + 4, -(28 + AREA_H + 4))
    rndBtn:SetScript("OnClick", function()
        if not _noteID then return end
        local icons = GetFilteredIcons("")
        if #icons == 0 then return end
        local pick = icons[math.random(#icons)]
        BNB.UpdateNote(_noteID, {icon = pick, iconSource = "curated"})
        if BNB.RefreshNoteList then BNB.RefreshNoteList() end
        if BNB.Sticky and BNB.Sticky.RefreshNote then BNB.Sticky.RefreshNote(_noteID) end
        RefreshIconGrid()
    end)

    -- Total height consumed by bnbPane content
    local BNB_PANE_H = 28 + AREA_H + 4 + 22   -- search + grid + gap + buttons

    bnbPane:SetHeight(BNB_PANE_H)

    -- ── Blizzard Icon tab content ────────────────────────────────────────────
    -- Input label
    local blzLbl = blzPane:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    blzLbl:SetPoint("TOPLEFT", blzPane, "TOPLEFT", 0, 0)
    blzLbl:SetTextColor(0.78, 0.78, 0.78)
    blzLbl:SetText("Icon name (e.g. INV_Sword_01)")

    -- Name input
    local blzBg = BNB.CreateBackdropFrame("Frame", nil, blzPane); BNB.SetBackdropDark(blzBg)
    blzBg:SetPoint("TOPLEFT", blzPane, "TOPLEFT", 0, -16); blzBg:SetWidth(CW); blzBg:SetHeight(24)
    local blzEb = CreateFrame("EditBox", nil, blzBg, "InputBoxTemplate")
    blzEb:SetPoint("TOPLEFT",     blzBg, "TOPLEFT",     6, -2)
    blzEb:SetPoint("BOTTOMRIGHT", blzBg, "BOTTOMRIGHT", -6,  2)
    blzEb:SetFontObject("GameFontNormal"); blzEb:SetAutoFocus(false); blzEb:SetMaxLetters(128)
    BNB.AddPlaceholder(blzEb, "Icon name...", 0.4, 0.4, 0.4)

    -- Preview icon (64x64)
    local PREV_SZ   = 64
    local PREV_PAD  = 8
    local blzPreviewBg = BNB.CreateBackdropFrame("Frame", nil, blzPane); BNB.SetBackdropDark(blzPreviewBg)
    blzPreviewBg:SetSize(PREV_SZ + 4, PREV_SZ + 4)
    blzPreviewBg:SetPoint("TOPLEFT", blzPane, "TOPLEFT", 0, -(16 + 24 + PREV_PAD))
    local blzPreviewTex = blzPreviewBg:CreateTexture(nil, "ARTWORK")
    blzPreviewTex:SetPoint("TOPLEFT",     blzPreviewBg, "TOPLEFT",     2, -2)
    blzPreviewTex:SetPoint("BOTTOMRIGHT", blzPreviewBg, "BOTTOMRIGHT", -2,  2)
    blzPreviewTex:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    -- Info label below preview
    local blzInfo = blzPane:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    blzInfo:SetPoint("TOPLEFT",  blzPane, "TOPLEFT",  PREV_SZ + 4 + 8, -(16 + 24 + PREV_PAD))
    blzInfo:SetPoint("TOPRIGHT", blzPane, "TOPRIGHT", 0, -(16 + 24 + PREV_PAD))
    blzInfo:SetTextColor(0.55, 0.55, 0.55)
    blzInfo:SetJustifyH("LEFT"); blzInfo:SetWordWrap(true)
    blzInfo:SetText("Type an icon name and press Enter.\n\nFor icon names:\n|cff66bb6awowhead.com/icons|r")

    -- Apply / Clear buttons for Blizzard tab
    local BLZ_BTN_Y = -(16 + 24 + PREV_PAD + PREV_SZ + 4 + 6)
    local blzApply = BNB.CreateButton(nil, blzPane, "Apply", btnW, 22)
    blzApply:SetPoint("TOPLEFT", blzPane, "TOPLEFT", 0, BLZ_BTN_Y)
    blzApply:SetEnabled(false)
    blzApply:SetAlpha(0.4)

    local blzClear = BNB.CreateButton(nil, blzPane, "Use Default", btnW, 22)
    blzClear:SetPoint("TOPLEFT", blzPane, "TOPLEFT", btnW + 4, BLZ_BTN_Y)
    blzClear:SetEnabled(false)
    blzClear:SetAlpha(0.4)

    local BLZ_PANE_H = 16 + 24 + PREV_PAD + PREV_SZ + 4 + 6 + 22

    blzPane:SetHeight(BLZ_PANE_H)

    -- Live preview update — sets texture and dynamic name label
    local function ApplyBlzName(name)
        if not name or name == "" then
            blzPreviewTex:SetTexture(nil)
            return false
        end
        local path = "Interface\\Icons\\" .. name
        blzPreviewTex:SetTexture(path)
        return true
    end

    local function CommitBlzIcon(name)
        if not _noteID or not name or name == "" then return end
        local path = "Interface\\Icons\\" .. name
        BNB.UpdateNote(_noteID, {icon = path, iconSource = "blizzard"})
        if BNB.RefreshNoteList then BNB.RefreshNoteList() end
        if BNB.Sticky and BNB.Sticky.RefreshNote then BNB.Sticky.RefreshNote(_noteID) end
    end

    blzEb:SetScript("OnTextChanged", function(self, u)
        if not u then return end
        if self._showingPlaceholder then return end
        local name = self:GetText() or ""
        local hasText = name ~= ""
        blzApply:SetEnabled(hasText); blzApply:SetAlpha(hasText and 1.0 or 0.4)
        ApplyBlzName(name)
    end)
    blzEb:SetScript("OnEnterPressed", function(self)
        local name = self._showingPlaceholder and "" or (self:GetText() or "")
        if ApplyBlzName(name) then CommitBlzIcon(name) end
        self:ClearFocus()
    end)
    blzEb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

    blzApply:SetScript("OnClick", function()
        local name = blzEb._showingPlaceholder and "" or (blzEb:GetText() or "")
        if ApplyBlzName(name) then CommitBlzIcon(name) end
    end)

    -- Forward-declared so blzClear:SetScript closure can reference it before the definition below
    local SetIconTab

    blzClear:SetScript("OnClick", function()
        if not _noteID then return end
        -- Pick a random icon from the Notes subfolder and switch to BNB Icons tab
        local noteIcons = {}
        for _, path in ipairs(ICON_LIST) do
            if path:find("\\Notes\\", 1, true) then
                noteIcons[#noteIcons + 1] = path
            end
        end
        if #noteIcons == 0 then return end
        local pick = noteIcons[math.random(#noteIcons)]
        BNB.UpdateNote(_noteID, {icon = pick, iconSource = "curated"})
        if BNB.RefreshNoteList then BNB.RefreshNoteList() end
        if BNB.Sticky and BNB.Sticky.RefreshNote then BNB.Sticky.RefreshNote(_noteID) end
        blzEb:SetText(""); blzEb._showingPlaceholder = false
        BNB.AddPlaceholder(blzEb, "Icon name...", 0.4, 0.4, 0.4)
        blzPreviewTex:SetTexture(nil)
        SetIconTab("bnb")
        RefreshIconGrid(true)
    end)

    -- ── Tab switching ────────────────────────────────────────────────────────
    local _activeIconTab = "bnb"  -- "bnb" or "blizzard"

    SetIconTab = function(which)
        _activeIconTab = which
        if which == "blizzard" then
            bnbPane:Hide(); blzPane:Show()
        else
            blzPane:Hide(); bnbPane:Show()
        end
    end

    tabBNB:SetScript("OnClick", function() SetIconTab("bnb") end)
    tabBLZ:SetScript("OnClick", function() SetIconTab("blizzard") end)

    -- ── Sync on note open ────────────────────────────────────────────────────
    -- Called from panel._refreshAppearance whenever a new note is loaded.
    local function SyncIconTab()
        local n = GetNote()
        if n and n.iconSource == "blizzard" then
            SetIconTab("blizzard")
            blzClear:SetEnabled(true); blzClear:SetAlpha(1.0)
            -- Populate input + preview with the stored icon name
            local stored = n.icon or ""
            -- Strip "Interface\Icons\" prefix to get bare name for the editbox
            local name = stored:match("[^\\/]+$") or stored
            blzEb:SetText(name)
            blzEb._showingPlaceholder = (name == "")
            if name == "" then
                BNB.AddPlaceholder(blzEb, "Icon name...", 0.4, 0.4, 0.4)
            end
            ApplyBlzName(name)
            local hasText = name ~= ""
            blzApply:SetEnabled(hasText); blzApply:SetAlpha(hasText and 1.0 or 0.4)
        else
            SetIconTab("bnb")
            blzClear:SetEnabled(false); blzClear:SetAlpha(0.4)
            blzApply:SetEnabled(false); blzApply:SetAlpha(0.4)
        end
        RefreshIconGrid()
    end

    -- Advance y past whichever pane is taller (they share the same y anchor)
    local ICON_SECTION_H = math.max(BNB_PANE_H, BLZ_PANE_H)
    y = y - ICON_SECTION_H - 4

    -- Icon autocomplete — attached here, AFTER all SetScript/AddPlaceholder calls
    -- above, so repeated AddPlaceholder calls in SyncIconTab and the Use Default
    -- handler cannot overwrite our hooks (SetScript clears HookScript handlers).
    if BNB.AttachIconAutocomplete then
        BNB.AttachIconAutocomplete(blzEb, function(name)
            ApplyBlzName(name)
            blzApply:SetEnabled(true); blzApply:SetAlpha(1.0)
        end)
    end

    -- Refresh all border controls when switching notes (called by OpenNoteConfig/SyncNoteConfig)
    panel._refreshAppearance = function()
        local n    = GetNote()
        local bord = (n and n.borderOverride) or "None"
        bDrop:SetSelected(bord)

        local bs = (n and n.borderScale)      or 100
        local bo = (n and n.borderOffset)     or 2
        local bb = (n and n.borderBrightness) or 100
        bsVal:SetText(bs .. "%")
        boVal:SetText(bo .. "px")
        bbVal:SetText(bb .. "%")
        if bsSl and bsSl.SetValue then pcall(bsSl.SetValue, bsSl, bs) end
        if boSl and boSl.SetValue then pcall(boSl.SetValue, boSl, bo) end
        if bbSl and bbSl.SetValue then pcall(bbSl.SetValue, bbSl, bb) end

        SyncIconTab()
    end

    panel:HookScript("OnShow", function()
        C_Timer.After(0.1, SyncIconTab)
    end)
end

-- ─────────────────────────────────────────────────────────────────────────────
-- TAB 3 — SITUATION
-- Allows the note to be bound to a zone, instance, or player name.
-- Stored as: note.context = "zone:Elwynn Forest" / "instance:Molten Core" / "player:Thrall" / nil
-- ─────────────────────────────────────────────────────────────────────────────
local function BuildSituationTab(panel)
    local function Row(p, y) return y - ROW_H - ROW_GAP end
    local y = -PAD

    -- Header label
    local hdr = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    hdr:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD, y)
    hdr:SetTextColor(1, 0.82, 0, 1)
    hdr:SetText("Contextual Binding")
    y = y - 20

    local desc = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    desc:SetPoint("TOPLEFT",  panel, "TOPLEFT",  PAD, y)
    desc:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -PAD, y)
    desc:SetTextColor(0.60, 0.60, 0.60)
    desc:SetText("This note will surface when you enter\nthe matching zone, instance, or area.")
    desc:SetJustifyH("LEFT")
    desc:SetWordWrap(true)
    y = y - 36

    -- Divider
    local div = panel:CreateTexture(nil, "ARTWORK")
    div:SetHeight(1)
    div:SetPoint("TOPLEFT",  panel, "TOPLEFT",  PAD, y)
    div:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -PAD, y)
    if BigNoteBoxDB and BigNoteBoxDB.skinMode and BNB.GetSkinPreset then
        local p = BNB.GetSkinPreset()
        local br, bg_, bb = BNB.SkinBorderOf(p)
        div:SetColorTexture(br, bg_, bb, 0.8)
        BNB.RegisterSkinRule(div, 0.8)
    else
        div:SetColorTexture(0.28, 0.28, 0.30, 0.8)
    end
    y = y - 8

    -- Bind-type dropdown — WowStyle1 or cycling button fallback
    local TYPES       = { "none", "zone", "subzone", "instance", "player" }
    local TYPE_LABELS = { "None (global)", "Zone", "Sub-zone", "Instance", "Player" }
    local selType     = "none"
    local SelectType  -- forward-declared below

    local useNativeSit = C_XMLUtil and C_XMLUtil.GetTemplateInfo
        and C_XMLUtil.GetTemplateInfo("WowStyle1DropdownTemplate")

    local typeDropdown    -- WowStyle1 DropdownButton (retail)
    local typeCycleBtn    -- cycling button fallback
    local ddW = CW  -- CW = NCW - PAD - 8, stays inside panel chrome

    local function GetTypeLabel(t)
        for i, k in ipairs(TYPES) do if k == t then return TYPE_LABELS[i] end end
        return TYPE_LABELS[1]
    end

    local function SetSituDropdownText(label)
        if typeDropdown and typeDropdown.Text then
            typeDropdown.Text:SetText(label)
        end
        if typeCycleBtn then
            typeCycleBtn:SetText(label)
        end
    end

    if useNativeSit then
        typeDropdown = CreateFrame("DropdownButton", "BNBSituationTypeDD", panel,
            "WowStyle1DropdownTemplate")
        typeDropdown:SetPoint("TOPLEFT",  panel, "TOPLEFT",  PAD, y)
        typeDropdown:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -8,  y)
        typeDropdown:SetHeight(24)
        local function RebuildSitMenu()
            typeDropdown:SetupMenu(function(_, root)
                for i, label in ipairs(TYPE_LABELS) do
                    local key = TYPES[i]
                    root:CreateRadio(label,
                        function() return selType == key end,
                        function()
                            selType = key
                            typeDropdown:GenerateMenu()
                            SelectType(key)
                        end)
                end
            end)
        end
        RebuildSitMenu()
        panel._rebuildSitMenu = RebuildSitMenu
    else
        typeCycleBtn = BNB.CreateButton(nil, panel, GetTypeLabel(selType), ddW, 24)
        typeCycleBtn:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD, y)
        typeCycleBtn:SetScript("OnClick", function(self)
            local idx = 1
            for i, k in ipairs(TYPES) do if k == selType then idx = i; break end end
            idx = (idx % #TYPES) + 1
            selType = TYPES[idx]
            self:SetText(TYPE_LABELS[idx])
            SelectType(selType)
        end)
    end
    y = y - 30

    -- Value input (shown for zone/instance/player)
    local valueRow = CreateFrame("Frame", nil, panel)
    valueRow:SetPoint("TOPLEFT",  panel, "TOPLEFT",  PAD,  y)
    valueRow:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -PAD, y)
    valueRow:SetHeight(ROW_H)
    valueRow:Hide()

    local valueLbl = valueRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    valueLbl:SetPoint("LEFT", valueRow, "LEFT", 0, 0)
    valueLbl:SetWidth(65)
    valueLbl:SetJustifyH("LEFT")
    valueLbl:SetTextColor(0.78, 0.78, 0.78)
    valueLbl:SetText("Value:")

    local valueEb = CreateFrame("EditBox", nil, valueRow,
        "BackdropTemplate")
    BNB.EnsureBackdrop(valueEb)
    valueEb:SetPoint("LEFT",  valueLbl, "RIGHT", 6, 0)
    valueEb:SetPoint("RIGHT", valueRow, "RIGHT", -26, 0)   -- leave room for browse btn
    valueEb:SetHeight(20)
    valueEb:SetFontObject("GameFontNormal")
    valueEb:SetAutoFocus(false)
    valueEb:SetMaxLetters(128)
    valueEb:SetTextInsets(4, 4, 0, 0)
    valueEb:SetTextColor(1, 1, 1)
    BNB.SetBackdropDark(valueEb)
    valueEb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

    -- Browse button — location icon, shown only for zone/instance types
    -- NOTE: replace "Overlay\\ov-situation" with "location" once location.tga is on disk.
    local browseBtn = CreateFrame("Button", nil, valueRow)
    browseBtn:SetSize(20, 20)
    browseBtn:SetPoint("RIGHT", valueRow, "RIGHT", 0, 0)
    local browseTx = browseBtn:CreateTexture(nil, "ARTWORK")
    browseTx:SetAllPoints()
    browseTx:SetTexture(ASSETS .. "Overlay\\ov-situation")
    browseBtn:SetScript("OnEnter", function(self)
        self:SetAlpha(1.0)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Browse zones and instances", 1, 1, 1)
        GameTooltip:AddLine("Click to open the zone browser", 0.78, 0.78, 0.78)
        GameTooltip:Show()
    end)
    browseBtn:SetScript("OnLeave", function(self)
        self:SetAlpha(0.7)
        GameTooltip:Hide()
    end)
    browseBtn:SetAlpha(0.7)
    browseBtn:Hide()   -- shown/hidden by SelectType

    -- ── Autocomplete dropdown (zone / instance / player) ─────────────────────
    -- Appears below valueRow when user types 2+ chars. Clicking a row fills
    -- valueEb and closes the dropdown. ESC or focus-loss closes it.
    local acFrame = BNB.CreateBackdropFrame("Frame", nil, panel)
    BNB.SetBackdrop(acFrame, 0.08, 0.08, 0.10, 0.97, 0.35, 0.35, 0.38, 1)
    acFrame:SetPoint("TOPLEFT",  valueRow, "BOTTOMLEFT",  0, -2)
    acFrame:SetPoint("TOPRIGHT", valueRow, "BOTTOMRIGHT", 0, -2)
    acFrame:SetFrameLevel(panel:GetFrameLevel() + 30)
    acFrame:Hide()

    local _acRows   = {}
    local _acTimer  = nil

    local function HideAC()
        acFrame:Hide()
        if _acTimer then _acTimer:Cancel(); _acTimer = nil end
    end

    local function ShowAC(matches)
        if #matches == 0 then HideAC(); return end
        local ROW_H_AC = 22
        local maxRows  = math.min(#matches, 7)
        acFrame:SetHeight(maxRows * ROW_H_AC + 4)

        for i = 1, maxRows do
            if not _acRows[i] then
                local row = CreateFrame("Button", nil, acFrame)
                row:SetHeight(ROW_H_AC)
                row:SetPoint("TOPLEFT",  acFrame, "TOPLEFT",  4, -2 - (i-1)*ROW_H_AC)
                row:SetPoint("TOPRIGHT", acFrame, "TOPRIGHT", -4, -2 - (i-1)*ROW_H_AC)

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

                _acRows[i] = row
            end

            local row    = _acRows[i]
            local m      = matches[i]
            row._nameLbl:SetText(m.name)
            row._contLbl:SetText(m.continent or "")
            row:SetPoint("TOPLEFT",  acFrame, "TOPLEFT",  4, -2 - (i-1)*ROW_H_AC)
            row:SetPoint("TOPRIGHT", acFrame, "TOPRIGHT", -4, -2 - (i-1)*ROW_H_AC)
            local capName = m.name
            row:SetScript("OnClick", function()
                valueEb:SetText(capName)
                HideAC()
                valueEb:SetFocus()
            end)
            row:Show()
        end
        for i = maxRows + 1, #_acRows do _acRows[i]:Hide() end
        acFrame:Show()
    end

    -- Wire valueEb OnTextChanged → autocomplete
    valueEb:SetScript("OnTextChanged", function(self, userInput)
        if not userInput then return end
        local text = self:GetText() or ""
        if #text < 2 then HideAC(); return end
        -- Close the full picker if open (autocomplete takes over)
        if BNB.ZonePicker and BNB.ZonePicker.IsShown and BNB.ZonePicker.IsShown() then
            BNB.ZonePicker.Close()
        end
        if _acTimer then _acTimer:Cancel() end
        _acTimer = C_Timer.NewTimer(0.15, function()
            if BNB.ZonePicker and BNB.ZonePicker.GetMatches then
                local matches = BNB.ZonePicker.GetMatches(text, selType, 7)
                ShowAC(matches)
            end
        end)
    end)

    valueEb:HookScript("OnEditFocusLost", function()
        -- Tiny delay so row clicks register before hide
        C_Timer.After(0.2, function()
            if not acFrame:IsMouseOver() then HideAC() end
        end)
    end)

    -- Wire browse button
    browseBtn:SetScript("OnClick", function()
        HideAC()
        if BNB.ZonePicker then
            if BNB.ZonePicker.IsShown and BNB.ZonePicker.IsShown() then
                BNB.ZonePicker.Close()
            else
                BNB.ZonePicker.Open(valueRow, function(name, kind)
                    valueEb:SetText(name)
                end, selType)
            end
        end
    end)

    -- "Use current" button — fills in value from player's current environment
    local useCurrentBtn = BNB.CreateButton(nil, panel, "Use Current", 90, 20)
    useCurrentBtn:SetPoint("TOPLEFT",  valueRow, "BOTTOMLEFT", 0, -4)
    useCurrentBtn:Hide()

    -- Save button
    local saveCtxBtn = BNB.CreateButton(nil, panel, "Apply", 60, 22)
    saveCtxBtn:SetPoint("TOPLEFT", useCurrentBtn, "TOPRIGHT", 8, 0)
    saveCtxBtn:Hide()

    -- Clear button
    local clearCtxBtn = BNB.CreateButton(nil, panel, "Clear", 52, 22)
    clearCtxBtn:SetPoint("TOPLEFT", saveCtxBtn, "TOPRIGHT", 6, 0)
    clearCtxBtn:Hide()

    -- Current binding display (bottom of panel, two lines)
    local curBindValue = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge3")
    curBindValue:SetPoint("BOTTOMLEFT",  panel, "BOTTOMLEFT",  PAD, PAD + 6)
    curBindValue:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -PAD, PAD + 6)
    curBindValue:SetJustifyH("CENTER")
    curBindValue:SetWordWrap(false)
    curBindValue:SetMaxLines(1)
    curBindValue:SetTextColor(1, 1, 1)
    curBindValue:SetText("")

    local curBindHeader = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    curBindHeader:SetPoint("BOTTOMLEFT",  curBindValue, "TOPLEFT",  0, 4)
    curBindHeader:SetPoint("BOTTOMRIGHT", curBindValue, "TOPRIGHT", 0, 4)
    curBindHeader:SetJustifyH("CENTER")
    curBindHeader:SetWordWrap(false)
    curBindHeader:SetMaxLines(1)
    curBindHeader:SetTextColor(0.55, 0.55, 0.55)
    curBindHeader:SetText("")

    panel._curBindHeader = curBindHeader
    panel._curBindValue  = curBindValue

    -- ── Display mode dropdown (popup vs sticky) ──────────────────────────────
    -- Shown only when a situation type other than "none" is selected.
    local DISPLAY_MODES  = { "popup", "sticky", "both" }
    local DISPLAY_LABELS = { "Show popup notification", "Show as sticky note", "Both — popup and sticky" }
    local selDisplay = "popup"

    local LEAVE_MODES  = { "keep", "minimize", "hide" }
    local LEAVE_LABELS = { "Keep open", "Minimize", "Hide" }
    local selLeave = "keep"

    local dispDiv = panel:CreateTexture(nil, "ARTWORK")
    dispDiv:SetHeight(1)
    dispDiv:SetPoint("TOPLEFT",  useCurrentBtn, "BOTTOMLEFT",   0, -26)
    dispDiv:SetPoint("TOPRIGHT", panel,         "TOPRIGHT",   -PAD, 0)
    if BigNoteBoxDB and BigNoteBoxDB.skinMode and BNB.GetSkinPreset then
        local p = BNB.GetSkinPreset()
        local br, bg_, bb = BNB.SkinBorderOf(p)
        dispDiv:SetColorTexture(br, bg_, bb, 0.8)
        BNB.RegisterSkinRule(dispDiv, 0.8)
    else
        dispDiv:SetColorTexture(0.28, 0.28, 0.30, 0.8)
    end
    dispDiv:Hide()

    local dispLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    dispLabel:SetPoint("TOPLEFT", dispDiv, "BOTTOMLEFT", 0, -6)
    dispLabel:SetText("When triggered, show as:")
    dispLabel:SetTextColor(0.78, 0.78, 0.78)
    dispLabel:Hide()

    local useNativeDisp = C_XMLUtil and C_XMLUtil.GetTemplateInfo
        and C_XMLUtil.GetTemplateInfo("WowStyle1DropdownTemplate")

    local dispDropdown   -- retail
    local dispCycleBtn   -- cycling button fallback

    local function GetDispLabel(m)
        for i, k in ipairs(DISPLAY_MODES) do if k == m then return DISPLAY_LABELS[i] end end
        return DISPLAY_LABELS[1]
    end

    local function SetDispDropdownText(label)
        if dispDropdown and dispDropdown.Text then dispDropdown.Text:SetText(label) end
        if dispCycleBtn then dispCycleBtn:SetText(label) end
    end

    local function OnDispChanged(mode)
        selDisplay = mode
        local id = _noteID; if not id then return end
        if mode == "sticky" or mode == "both" then
            BNB.UpdateNote(id, { contextDisplay = mode })
        else
            BNB.UpdateNote(id, { _clear = {"contextDisplay"} })
        end
    end

    if useNativeDisp then
        dispDropdown = CreateFrame("DropdownButton", "BNBContextDispDD", panel,
            "WowStyle1DropdownTemplate")
        dispDropdown:SetPoint("TOPLEFT",  dispLabel, "BOTTOMLEFT",  0, -4)
        dispDropdown:SetPoint("TOPRIGHT", panel,     "TOPRIGHT",   -8,  0)
        dispDropdown:SetHeight(24)
        local function RebuildDispMenu()
            dispDropdown:SetupMenu(function(_, root)
                for i, label in ipairs(DISPLAY_LABELS) do
                    local key = DISPLAY_MODES[i]
                    root:CreateRadio(label,
                        function() return selDisplay == key end,
                        function()
                            selDisplay = key
                            dispDropdown:GenerateMenu()
                            OnDispChanged(key)
                        end)
                end
            end)
        end
        RebuildDispMenu()
        dispDropdown:Hide()
        panel._rebuildDispMenu = RebuildDispMenu
    else
        dispCycleBtn = BNB.CreateButton(nil, panel, GetDispLabel(selDisplay), CW, 24)
        dispCycleBtn:SetPoint("TOPLEFT", dispLabel, "BOTTOMLEFT", 0, -4)
        dispCycleBtn:SetScript("OnClick", function(self)
            local idx = 1
            for i, k in ipairs(DISPLAY_MODES) do if k == selDisplay then idx = i; break end end
            idx = (idx % #DISPLAY_MODES) + 1
            selDisplay = DISPLAY_MODES[idx]
            self:SetText(DISPLAY_LABELS[idx])
            OnDispChanged(selDisplay)
        end)
        dispCycleBtn:Hide()
    end

    -- ── Leave action dropdown ─────────────────────────────────────────────────
    -- What happens to open sticky notes when you leave the bound zone/instance.
    -- Anchors below the display controls (whichever is visible).
    -- Uses dispDropdown or dispCycleBtn as the anchor reference frame.
    local function GetLeaveLabel(m)
        for i, k in ipairs(LEAVE_MODES) do if k == m then return LEAVE_LABELS[i] end end
        return LEAVE_LABELS[1]
    end

    local function OnLeaveChanged(mode)
        selLeave = mode
        local id = _noteID; if not id then return end
        if mode == "keep" then
            BNB.UpdateNote(id, { _clear = {"contextLeave"} })
        else
            BNB.UpdateNote(id, { contextLeave = mode })
        end
    end

    local leaveDiv = panel:CreateTexture(nil, "ARTWORK")
    leaveDiv:SetHeight(1)
    -- Anchored below the display section. We use dispDiv as relative anchor,
    -- with enough offset to clear the display dropdown (≈52px below dispDiv top).
    leaveDiv:SetPoint("TOPLEFT",  dispDiv, "TOPLEFT",  0, -52)
    leaveDiv:SetPoint("TOPRIGHT", panel,  "TOPRIGHT", -PAD, 0)
    if BigNoteBoxDB and BigNoteBoxDB.skinMode and BNB.GetSkinPreset then
        local p = BNB.GetSkinPreset()
        local br, bg_, bb = BNB.SkinBorderOf(p)
        leaveDiv:SetColorTexture(br, bg_, bb, 0.8)
        BNB.RegisterSkinRule(leaveDiv, 0.8)
    else
        leaveDiv:SetColorTexture(0.28, 0.28, 0.30, 0.8)
    end
    leaveDiv:Hide()

    local leaveLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    leaveLabel:SetPoint("TOPLEFT", leaveDiv, "BOTTOMLEFT", 0, -6)
    leaveLabel:SetText("When you leave the area:")
    leaveLabel:SetTextColor(0.78, 0.78, 0.78)
    leaveLabel:Hide()

    local SetLeaveDropdownText

    local useNativeLeave = useNativeDisp  -- same version check
    local leaveDropdown
    local leaveCycleBtn

    if useNativeLeave then
        leaveDropdown = CreateFrame("DropdownButton", "BNBContextLeaveDD", panel,
            "WowStyle1DropdownTemplate")
        leaveDropdown:SetPoint("TOPLEFT",  leaveLabel, "BOTTOMLEFT",  0, -4)
        leaveDropdown:SetPoint("TOPRIGHT", panel,      "TOPRIGHT",   -8,  0)
        leaveDropdown:SetHeight(24)
        local function RebuildLeaveMenu()
            leaveDropdown:SetupMenu(function(_, root)
                for i, label in ipairs(LEAVE_LABELS) do
                    local key = LEAVE_MODES[i]
                    root:CreateRadio(label,
                        function() return selLeave == key end,
                        function()
                            selLeave = key
                            leaveDropdown:GenerateMenu()
                            OnLeaveChanged(key)
                        end)
                end
            end)
        end
        RebuildLeaveMenu()
        leaveDropdown:Hide()
        panel._rebuildLeaveMenu = RebuildLeaveMenu
        SetLeaveDropdownText = function(label)
            if leaveDropdown and leaveDropdown.Text then leaveDropdown.Text:SetText(label) end
        end
    else
        leaveCycleBtn = BNB.CreateButton(nil, panel, GetLeaveLabel(selLeave), CW, 24)
        leaveCycleBtn:SetPoint("TOPLEFT", leaveLabel, "BOTTOMLEFT", 0, -4)
        leaveCycleBtn:SetScript("OnClick", function(self)
            local idx = 1
            for i, k in ipairs(LEAVE_MODES) do if k == selLeave then idx = i; break end end
            idx = (idx % #LEAVE_MODES) + 1
            selLeave = LEAVE_MODES[idx]
            self:SetText(LEAVE_LABELS[idx])
            OnLeaveChanged(selLeave)
        end)
        leaveCycleBtn:Hide()
        SetLeaveDropdownText = function(label)
            if leaveCycleBtn then leaveCycleBtn:SetText(label) end
        end
    end

    local function ShowDispControls(show)
        if show then
            dispDiv:Show(); dispLabel:Show()
            if dispDropdown then dispDropdown:Show() end
            if dispCycleBtn then dispCycleBtn:Show() end
            leaveDiv:Show(); leaveLabel:Show()
            if leaveDropdown then leaveDropdown:Show() end
            if leaveCycleBtn then leaveCycleBtn:Show() end
        else
            dispDiv:Hide(); dispLabel:Hide()
            if dispDropdown then dispDropdown:Hide() end
            if dispCycleBtn then dispCycleBtn:Hide() end
            leaveDiv:Hide(); leaveLabel:Hide()
            if leaveDropdown then leaveDropdown:Hide() end
            if leaveCycleBtn then leaveCycleBtn:Hide() end
        end
    end

    -- ── Helper: refresh current-binding label ────────────────────────────────
    local KIND_LABELS = { zone = "Zone", subzone = "Sub-zone", instance = "Instance", player = "Player" }
    local BIND_MAX_W  = NCW - PAD * 2 - 8  -- available width for the value text
    local BIND_DEF_SZ = 20                  -- GameFontNormalHuge3 default size
    local BIND_MIN_SZ = 11                  -- smallest we'll shrink to

    local function RefreshCurBind()
        local note = _noteID and BNB.GetNote(_noteID)
        local ctx  = note and note.context
        if ctx and ctx ~= "" then
            local kind, value
            if BNB.DecodeContext then kind, value = BNB.DecodeContext(ctx) end
            local kindLabel = KIND_LABELS[kind] or kind or "?"
            curBindHeader:SetText("Currently bound to " .. kindLabel .. ":")
            local txt = value or "?"
            curBindValue:SetText(txt)
            -- Reset to default size, then shrink if too wide
            local path = curBindValue:GetFont()
            if path then
                pcall(function() curBindValue:SetFont(path, BIND_DEF_SZ, "") end)
                local sw = curBindValue:GetStringWidth() or 0
                if sw > BIND_MAX_W then
                    local sz = math.max(BIND_MIN_SZ, math.floor(BIND_DEF_SZ * BIND_MAX_W / sw))
                    pcall(function() curBindValue:SetFont(path, sz, "") end)
                end
            end
        else
            curBindHeader:SetText("|cff666666No binding|r")
            local path = curBindValue:GetFont()
            if path then pcall(function() curBindValue:SetFont(path, BIND_DEF_SZ, "") end) end
            curBindValue:SetText("|cff666666Note is global.|r")
        end
    end
    panel._refreshCurBind = RefreshCurBind

    -- ── SelectType — updates dropdown text + shows/hides value row ──────────
    SelectType = function(t)
        selType = t
        local needsValue = (t ~= "none")
        valueRow:SetShown(needsValue)
        useCurrentBtn:SetShown(needsValue)
        saveCtxBtn:SetShown(needsValue)
        clearCtxBtn:SetShown(true)
        ShowDispControls(needsValue)

        -- Browse button only makes sense for zone/instance (LibTourist covers those)
        local canBrowse = (t == "zone" or t == "instance")
        browseBtn:SetShown(needsValue and canBrowse)

        -- Close autocomplete and picker when switching type
        HideAC()
        if BNB.ZonePicker and BNB.ZonePicker.Close then BNB.ZonePicker.Close() end

        if t == "zone" then
            valueLbl:SetText("Zone:")
        elseif t == "subzone" then
            valueLbl:SetText("Sub-zone:")
        elseif t == "instance" then
            valueLbl:SetText("Instance:")
        elseif t == "player" then
            valueLbl:SetText("Player:")
        end
    end

    -- ── Use Current button handler ────────────────────────────────────────────
    useCurrentBtn:SetScript("OnClick", function()
        local val = ""
        if selType == "zone" then
            val = GetZoneText() or ""
        elseif selType == "subzone" then
            val = GetSubZoneText and GetSubZoneText() or ""
        elseif selType == "instance" then
            val = (GetInstanceInfo and select(1, GetInstanceInfo())) or GetRealZoneText() or ""
        elseif selType == "player" then
            val = UnitName("target") or ""
        end
        if valueEb then valueEb:SetText(val) end
    end)

    -- ── Save / Apply ──────────────────────────────────────────────────────────
    saveCtxBtn:SetScript("OnClick", function()
        local id = _noteID; if not id then return end
        local val = valueEb and valueEb:GetText() or ""
        val = val:match("^%s*(.-)%s*$") or ""
        if selType == "none" or val == "" then
            BNB.UpdateNote(id, { _clear = {"context"} })
        else
            BNB.UpdateNote(id, { context = selType .. ":" .. val })
        end
        RefreshCurBind()
        if BNB.RefreshNoteList    then BNB.RefreshNoteList()    end
        if BNB.CheckContextualNotes then BNB.CheckContextualNotes() end
        if BNB.Sticky and BNB.Sticky.RefreshSettingsSituation then BNB.Sticky.RefreshSettingsSituation(id) end
        BNB:Print("Context binding saved.")
    end)

    -- ── Clear ─────────────────────────────────────────────────────────────────
    clearCtxBtn:SetScript("OnClick", function()
        local id = _noteID; if not id then return end
        BNB.UpdateNote(id, { _clear = {"context", "contextDisplay", "contextLeave"} })
        if valueEb then valueEb:SetText("") end
        selType = "none"
        selDisplay = "popup"
        selLeave = "keep"
        SetSituDropdownText(TYPE_LABELS[1])
        SetDispDropdownText(GetDispLabel("popup"))
        SetLeaveDropdownText(GetLeaveLabel("keep"))
        if typeDropdown  and typeDropdown.GenerateMenu  then typeDropdown:GenerateMenu()  end
        if dispDropdown  and dispDropdown.GenerateMenu  then dispDropdown:GenerateMenu()  end
        if leaveDropdown and leaveDropdown.GenerateMenu then leaveDropdown:GenerateMenu() end
        SelectType("none")
        clearCtxBtn:Hide()
        RefreshCurBind()
        -- Also remove any active waypoint for this note
        local uid = BNB._autoWaypoints and BNB._autoWaypoints[id]
        if uid then
            if TomTom and TomTom.RemoveWaypoint and type(uid) == "table" then
                pcall(function() TomTom:RemoveWaypoint(uid) end)
            elseif uid == true and C_Map and C_Map.ClearUserWaypoint then
                pcall(function() C_Map.ClearUserWaypoint() end)
            end
            BNB._autoWaypoints[id] = nil
        end
        if BNB.RefreshNoteList    then BNB.RefreshNoteList()    end
        if BNB.CheckContextualNotes then BNB.CheckContextualNotes() end
        if BNB.Sticky and BNB.Sticky.RefreshSettingsSituation then BNB.Sticky.RefreshSettingsSituation(id) end
    end)
    -- Anchored below the "When you leave the area" section (leaveDiv).
    -- leaveDiv is at dispDiv-52; leave label+dropdown ≈ 34px → add 90px total offset.
    -- The section is only shown when a situation type other than "none" is active.
    -- Stores note.waypoint = { mapID, x, y, label }.
    -- Works with TomTom (TomTom:AddWaypoint) and the retail built-in map pin
    -- (C_Map.SetUserWaypoint, DF+). Both are tried if available.

    -- Detect waypoint support
    local function HasWPAddon() return TomTom and TomTom.AddWaypoint end
    local function HasRetailPin() return C_Map and C_Map.SetUserWaypoint end
    local function WPAvailable() return HasWPAddon() or HasRetailPin() end

    local wpDiv = panel:CreateTexture(nil, "ARTWORK")
    wpDiv:SetHeight(1)
    wpDiv:SetPoint("TOPLEFT",  leaveDiv, "TOPLEFT",  0, -90)
    wpDiv:SetPoint("TOPRIGHT", panel,    "TOPRIGHT", -PAD, 0)
    if BigNoteBoxDB and BigNoteBoxDB.skinMode and BNB.GetSkinPreset then
        local p = BNB.GetSkinPreset()
        local br, bg_, bb = BNB.SkinBorderOf(p)
        wpDiv:SetColorTexture(br, bg_, bb, 0.8)
        BNB.RegisterSkinRule(wpDiv, 0.8)
    else
        wpDiv:SetColorTexture(0.28, 0.28, 0.30, 0.8)
    end
    wpDiv:Hide()

    local wpHdr = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    wpHdr:SetPoint("TOPLEFT", wpDiv, "BOTTOMLEFT", 0, -6)
    wpHdr:SetTextColor(1, 0.82, 0, 1)
    wpHdr:SetText("Waypoint")
    wpHdr:Hide()

    -- Status label: "(Addon installed)" / "(Enhanced)" / "(Basic)" / "(Addon required)"
    local wpStatusTag = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    wpStatusTag:SetPoint("LEFT", wpHdr, "RIGHT", 6, 0)
    wpStatusTag:Hide()

    local function RefreshWPStatusTag()
        if HasWPAddon() then
            if HasRetailPin() then
                wpStatusTag:SetText("(Enhanced)")
            else
                wpStatusTag:SetText("(Addon installed)")
            end
            wpStatusTag:SetTextColor(0.4, 1, 0.4)
        elseif HasRetailPin() then
            wpStatusTag:SetText("(Basic)")
            wpStatusTag:SetTextColor(0.85, 0.70, 0.2)
        else
            wpStatusTag:SetText("(Addon required)")
            wpStatusTag:SetTextColor(0.85, 0.30, 0.25)
        end
    end

    -- "?" label (visual only — the clickable area is the hit frame below)
    local wpInfoLbl = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    wpInfoLbl:SetPoint("LEFT", wpStatusTag, "RIGHT", 4, 0)
    wpInfoLbl:SetText("|cff88bbff?|r")
    wpInfoLbl:Hide()

    -- ── Waypoint info popup (detached frame, created once) ────────────────────
    local wpInfoPopup = nil
    local function ShowWPInfoPopup()
        if wpInfoPopup then
            if wpInfoPopup:IsShown() then wpInfoPopup:Hide(); return end
        end
        if not wpInfoPopup then
            local f = BNB.CreateBackdropFrame("Frame", "BNBWaypointInfoPopup", UIParent)
            f:SetSize(310, 230)
            f:SetFrameStrata("DIALOG")
            f:SetClampedToScreen(true)
            f:EnableMouse(true); f:SetMovable(true)
            f:RegisterForDrag("LeftButton")
            f:SetScript("OnDragStart", f.StartMoving)
            f:SetScript("OnDragStop", f.StopMovingOrSizing)
            BNB.SetBackdrop(f, 0.08, 0.08, 0.11, 0.96, 0.35, 0.35, 0.38, 1)

            -- Title
            local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
            title:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -12)
            title:SetTextColor(1, 0.82, 0)
            title:SetText("Waypoint Support")

            -- Close button
            local closeBtn = CreateFrame("Button", nil, f)
            closeBtn:SetSize(20, 20)
            closeBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -6, -6)
            local closeLbl = closeBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            closeLbl:SetAllPoints(); closeLbl:SetText("|cffaaaaaa×|r")
            closeBtn:SetScript("OnClick", function() f:Hide() end)
            closeBtn:SetScript("OnEnter", function() closeLbl:SetText("|cffff4444×|r") end)
            closeBtn:SetScript("OnLeave", function() closeLbl:SetText("|cffaaaaaa×|r") end)

            -- Status line (dynamic)
            f._statusLbl = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            f._statusLbl:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -10)
            f._statusLbl:SetWidth(280); f._statusLbl:SetJustifyH("LEFT")

            -- Description (dynamic)
            f._descLbl = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            f._descLbl:SetPoint("TOPLEFT", f._statusLbl, "BOTTOMLEFT", 0, -6)
            f._descLbl:SetWidth(280); f._descLbl:SetJustifyH("LEFT"); f._descLbl:SetWordWrap(true)
            f._descLbl:SetTextColor(0.78, 0.78, 0.78)

            -- Addon links header
            local linksHdr = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            linksHdr:SetPoint("TOPLEFT", f._descLbl, "BOTTOMLEFT", 0, -14)
            linksHdr:SetText("Recommended addons:")
            linksHdr:SetTextColor(1, 1, 1)
            f._linksHdr = linksHdr

            -- WaypointUI link button
            local wpuiBtn = BNB.CreateButton(nil, f, "WaypointUI (CurseForge)", 200, 22)
            wpuiBtn:SetPoint("TOPLEFT", linksHdr, "BOTTOMLEFT", 0, -6)
            wpuiBtn:SetScript("OnClick", function()
                local url = "https://www.curseforge.com/wow/addons/waypointui"
                if C_System and C_System.SetClipboard then
                    C_System.SetClipboard(url)
                    BNB:Print("URL copied: |cffffff00" .. url .. "|r")
                else
                    BNB:Print("Get WaypointUI: |cffffff00" .. url .. "|r")
                end
            end)
            wpuiBtn:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_TOP")
                GameTooltip:AddLine("Click to copy URL", 0.55, 0.85, 1)
                GameTooltip:Show()
            end)
            wpuiBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

            -- TomTom link button
            local ttBtn = BNB.CreateButton(nil, f, "TomTom (CurseForge)", 200, 22)
            ttBtn:SetPoint("TOPLEFT", wpuiBtn, "BOTTOMLEFT", 0, -4)
            ttBtn:SetScript("OnClick", function()
                local url = "https://www.curseforge.com/wow/addons/tomtom"
                if C_System and C_System.SetClipboard then
                    C_System.SetClipboard(url)
                    BNB:Print("URL copied: |cffffff00" .. url .. "|r")
                else
                    BNB:Print("Get TomTom: |cffffff00" .. url .. "|r")
                end
            end)
            ttBtn:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_TOP")
                GameTooltip:AddLine("Click to copy URL", 0.55, 0.85, 1)
                GameTooltip:Show()
            end)
            ttBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

            wpInfoPopup = f
        end

        -- Update dynamic content
        local f = wpInfoPopup
        if HasWPAddon() then
            f._statusLbl:SetText("|cff66ff66Waypoint addon detected.|r")
            f._descLbl:SetText("Full waypoint support is available:\n• Arrow navigation to your destination\n• Auto-waypoints when entering a bound zone\n• Multiple waypoints (TomTom)")
        elseif HasRetailPin() then
            f._statusLbl:SetText("|cffffaa00Using built-in map pin (basic).|r")
            f._descLbl:SetText("The game's built-in map pin works but has limitations:\n• Only one waypoint at a time\n• No directional arrow on-screen\n\nInstall an addon below for the full experience.")
        else
            f._statusLbl:SetText("|cffff5555No waypoint support detected.|r")
            f._descLbl:SetText("Your WoW client has no built-in waypoint system.\nInstall one of the addons below to enable waypoints,\narrow navigation, and auto-waypoints on zone entry.")
        end

        -- Position near the NoteConfig window
        f:ClearAllPoints()
        if ncFrame then
            f:SetPoint("TOPLEFT", ncFrame, "TOPRIGHT", 4, 0)
        else
            f:SetPoint("CENTER", UIParent, "CENTER", 0, 100)
        end
        f:Show()
    end

    -- Clickable hit frame covering status tag + ? label
    local wpInfoHit = CreateFrame("Button", nil, panel)
    wpInfoHit:SetPoint("LEFT", wpStatusTag, "LEFT", -2, 0)
    wpInfoHit:SetPoint("RIGHT", wpInfoLbl, "RIGHT", 4, 0)
    wpInfoHit:SetHeight(18)
    wpInfoHit:Hide()
    wpInfoHit:SetScript("OnClick", ShowWPInfoPopup)
    wpInfoHit:SetScript("OnEnter", function(self)
        wpInfoLbl:SetText("|cffbbddff?|r")
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Click for waypoint addon info", 0.55, 0.85, 1)
        GameTooltip:Show()
    end)
    wpInfoHit:SetScript("OnLeave", function()
        wpInfoLbl:SetText("|cff88bbff?|r")
        GameTooltip:Hide()
    end)

    local wpDesc = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    wpDesc:SetPoint("TOPLEFT",  wpHdr,  "BOTTOMLEFT",  0, -4)
    wpDesc:SetPoint("TOPRIGHT", panel,  "TOPRIGHT",   -PAD, 0)
    wpDesc:SetJustifyH("LEFT"); wpDesc:SetWordWrap(true)
    wpDesc:SetTextColor(0.60, 0.60, 0.60)
    wpDesc:SetText("Pin your current map position to this note.\nUse Navigate to send it to TomTom or the map.")
    wpDesc:Hide()

    -- 2×2 button grid:
    --   [Pin Here]  [Navigate]
    --   [Clear WP]  [Manual]
    local BTN_W = 72
    local BTN_H = 22
    local BTN_GAP = 6

    local wpPinBtn = BNB.CreateButton(nil, panel, "Pin Here", BTN_W, BTN_H)
    wpPinBtn:SetPoint("TOPLEFT", wpDesc, "BOTTOMLEFT", 0, -6)
    wpPinBtn:Hide()

    local wpNavBtn = BNB.CreateButton(nil, panel, "Navigate", BTN_W, BTN_H)
    wpNavBtn:SetPoint("LEFT", wpPinBtn, "RIGHT", BTN_GAP, 0)
    wpNavBtn:Hide()

    local wpClearBtn = BNB.CreateButton(nil, panel, "Clear WP", BTN_W, BTN_H)
    wpClearBtn:SetPoint("TOPLEFT", wpPinBtn, "BOTTOMLEFT", 0, -(BTN_GAP))
    wpClearBtn:Hide()

    local wpManualBtn = BNB.CreateButton(nil, panel, "Manual", BTN_W, BTN_H)
    wpManualBtn:SetPoint("LEFT", wpClearBtn, "RIGHT", BTN_GAP, 0)
    wpManualBtn:Hide()

    -- Manual coord entry row (hidden until Manual is clicked)
    local wpManualRow = CreateFrame("Frame", nil, panel)
    wpManualRow:SetHeight(22)
    wpManualRow:SetPoint("TOPLEFT",  wpClearBtn, "BOTTOMLEFT", 0, -6)
    wpManualRow:SetPoint("TOPRIGHT", panel,      "TOPRIGHT",  -PAD, 0)
    wpManualRow:Hide()

    local wpXLbl = wpManualRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    wpXLbl:SetPoint("LEFT", wpManualRow, "LEFT", 0, 0)
    wpXLbl:SetText("X:")
    wpXLbl:SetTextColor(0.78, 0.78, 0.78)
    wpXLbl:SetWidth(14)

    local wpXEb = CreateFrame("EditBox", nil, wpManualRow, "BackdropTemplate")
    BNB.EnsureBackdrop(wpXEb)
    BNB.SetBackdropDark(wpXEb)
    wpXEb:SetPoint("LEFT", wpXLbl, "RIGHT", 2, 0)
    wpXEb:SetSize(52, 20)
    wpXEb:SetFontObject("GameFontNormalSmall")
    wpXEb:SetAutoFocus(false); wpXEb:SetMaxLetters(8)
    wpXEb:SetNumeric(false); wpXEb:SetTextInsets(3,3,0,0)

    local wpYLbl = wpManualRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    wpYLbl:SetPoint("LEFT", wpXEb, "RIGHT", 6, 0)
    wpYLbl:SetText("Y:")
    wpYLbl:SetTextColor(0.78, 0.78, 0.78)
    wpYLbl:SetWidth(14)

    local wpYEb = CreateFrame("EditBox", nil, wpManualRow, "BackdropTemplate")
    BNB.EnsureBackdrop(wpYEb)
    BNB.SetBackdropDark(wpYEb)
    wpYEb:SetPoint("LEFT", wpYLbl, "RIGHT", 2, 0)
    wpYEb:SetSize(52, 20)
    wpYEb:SetFontObject("GameFontNormalSmall")
    wpYEb:SetAutoFocus(false); wpYEb:SetMaxLetters(8)
    wpYEb:SetNumeric(false); wpYEb:SetTextInsets(3,3,0,0)

    local wpSaveManualBtn = BNB.CreateButton(nil, wpManualRow, "Set", 38, 20)
    wpSaveManualBtn:SetPoint("LEFT", wpYEb, "RIGHT", 4, 0)

    wpManualBtn:SetScript("OnClick", function()
        if wpManualRow:IsShown() then
            wpManualRow:Hide()
        else
            -- Pre-fill with existing values if any
            local note = _noteID and BNB.GetNote(_noteID)
            local wp   = note and note.waypoint
            if wp and wp.x then wpXEb:SetText(string.format("%.1f", wp.x)) end
            if wp and wp.y then wpYEb:SetText(string.format("%.1f", wp.y)) end
            wpManualRow:Show()
            wpXEb:SetFocus()
        end
    end)
    wpManualBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Enter coordinates manually", 1, 1, 1)
        GameTooltip:Show()
    end)
    wpManualBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Forward declaration — defined below after wpStatusLbl is created,
    -- but called from CommitManualCoords which is defined first.
    local RefreshWaypointDisplay

    local function CommitManualCoords()
        local id   = _noteID; if not id then return end
        local note = BNB.GetNote(id); if not note then return end
        local xs = wpXEb:GetText():match("^%s*(.-)%s*$") or ""
        local ys = wpYEb:GetText():match("^%s*(.-)%s*$") or ""
        local x = tonumber(xs)
        local y = tonumber(ys)
        if not x or not y then
            BNB:Print("|cffff6666Invalid coordinates. Enter numbers like 54.3|r"); return
        end
        x = math.max(0, math.min(100, x))
        y = math.max(0, math.min(100, y))
        local zone  = GetRealZoneText() or GetZoneText() or ""
        local title = (note.title and note.title ~= "") and note.title or zone
        local mapID = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
        local existWP = note.waypoint
        BNB.UpdateNote(id, { waypoint = {
            mapID = mapID or (existWP and existWP.mapID),
            x     = x,
            y     = y,
            label = zone,
            title = title,
        }})
        RefreshWaypointDisplay()
        wpManualRow:Hide()
        BNB:Print(string.format("Waypoint set manually: %s (%.1f, %.1f)", title, x, y))
        if BNB.Sticky and BNB.Sticky.RefreshSettingsSituation then BNB.Sticky.RefreshSettingsSituation(_noteID) end
    end

    wpSaveManualBtn:SetScript("OnClick", CommitManualCoords)
    wpXEb:SetScript("OnEnterPressed", function() wpYEb:SetFocus() end)
    wpYEb:SetScript("OnEnterPressed", CommitManualCoords)
    wpXEb:SetScript("OnEscapePressed", function() wpManualRow:Hide() end)
    wpYEb:SetScript("OnEscapePressed", function() wpManualRow:Hide() end)

    -- "Remove waypoint on zone leave" checkbox
    local wpLeaveChk = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
    wpLeaveChk:SetSize(24, 24)
    wpLeaveChk:SetPoint("TOPLEFT", wpClearBtn, "BOTTOMLEFT", -4, -8)
    wpLeaveChk:Hide()
    local wpLeaveChkLbl = wpLeaveChk:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    wpLeaveChkLbl:SetPoint("LEFT", wpLeaveChk, "RIGHT", 2, 0)
    wpLeaveChkLbl:SetText("Remove waypoint on zone leave")
    wpLeaveChkLbl:SetTextColor(0.78, 0.78, 0.78)
    wpLeaveChk:SetScript("OnClick", function(self)
        if not _noteID then return end
        if self:GetChecked() then
            Save({wpClearOnLeave = true})
        else
            BNB.UpdateNote(_noteID, {_clear = {"wpClearOnLeave"}})
        end
    end)
    wpLeaveChk:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("When you leave the zone this note is bound to,\nautomatically remove the waypoint from the map.", 0.85, 0.85, 0.85, true)
        GameTooltip:Show()
    end)
    wpLeaveChk:SetScript("OnLeave", function() GameTooltip:Hide() end)
    local function RefreshWPLeaveChk()
        local note = _noteID and BNB.GetNote(_noteID)
        wpLeaveChk:SetChecked(note and note.wpClearOnLeave == true)
    end
    panel._refreshWPLeaveChk = RefreshWPLeaveChk

    -- Status label above the "Currently bound to" display at the panel bottom
    local wpStatusLbl = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    wpStatusLbl:SetPoint("BOTTOMLEFT",  panel._curBindHeader or panel, "TOPLEFT",  0, 6)
    wpStatusLbl:SetPoint("BOTTOMRIGHT", panel._curBindHeader or panel, "TOPRIGHT", 0, 6)
    wpStatusLbl:SetJustifyH("CENTER")
    wpStatusLbl:SetTextColor(0.55, 0.85, 1, 1)
    wpStatusLbl:SetText("")
    wpStatusLbl:Hide()

    RefreshWaypointDisplay = function()
        local note = _noteID and BNB.GetNote(_noteID)
        local wp   = note and note.waypoint
        if wp and wp.x and wp.y then
            local title = wp.title or wp.label or ""
            local coordStr = string.format("%.1f, %.1f", wp.x, wp.y)
            if title ~= "" then
                wpStatusLbl:SetText("Waypoint:\n" .. title .. "\n" .. coordStr)
            else
                wpStatusLbl:SetText("Waypoint:\n" .. coordStr)
            end
            wpStatusLbl:Show()
        else
            wpStatusLbl:SetText("")
            wpStatusLbl:Hide()
        end
    end

    -- Show/hide the waypoint section together with the display controls
    local _origShowDispControls = ShowDispControls
    ShowDispControls = function(show)
        _origShowDispControls(show)
        if show then
            wpDiv:Show(); wpHdr:Show(); wpDesc:Show()
            wpStatusTag:Show(); wpInfoLbl:Show(); wpInfoHit:Show()
            RefreshWPStatusTag()
            wpPinBtn:Show(); wpNavBtn:Show()
            wpClearBtn:Show(); wpManualBtn:Show()
            wpLeaveChk:Show(); RefreshWPLeaveChk()
            -- Grey out buttons if no waypoint support available
            local avail = WPAvailable()
            wpPinBtn:SetEnabled(avail)
            wpNavBtn:SetEnabled(avail)
            wpClearBtn:SetEnabled(avail)
            wpManualBtn:SetEnabled(avail)
            wpLeaveChk:SetEnabled(avail)
            if avail then
                wpDesc:SetText("Pin your current map position to this note.\nUse Navigate to send it to TomTom or the map.")
                wpDesc:SetTextColor(0.60, 0.60, 0.60)
            else
                wpDesc:SetText("Install a waypoint addon to enable this feature.\nWe recommend WaypointUI or TomTom (click ? for links).")
                wpDesc:SetTextColor(0.65, 0.40, 0.35)
            end
        else
            wpDiv:Hide(); wpHdr:Hide(); wpDesc:Hide()
            wpStatusTag:Hide(); wpInfoLbl:Hide(); wpInfoHit:Hide()
            wpPinBtn:Hide(); wpNavBtn:Hide()
            wpClearBtn:Hide(); wpManualBtn:Hide()
            wpManualRow:Hide(); wpLeaveChk:Hide()
        end
    end

    wpPinBtn:SetScript("OnClick", function()
        local id = _noteID; if not id then return end
        local note = BNB.GetNote(id); if not note then return end
        local mapID = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
        if not mapID then BNB:Print("|cffff6666Cannot get map position.|r"); return end
        local pos = C_Map and C_Map.GetPlayerMapPosition and C_Map.GetPlayerMapPosition(mapID, "player")
        if not pos then BNB:Print("|cffff6666Cannot get map position.|r"); return end
        local px, py = pos:GetXY()
        local x = math.floor(px * 1000 + 0.5) / 10
        local y = math.floor(py * 1000 + 0.5) / 10
        local zone  = GetRealZoneText() or GetZoneText() or ""
        local title = (note.title and note.title ~= "") and note.title or zone
        BNB.UpdateNote(id, { waypoint = { mapID = mapID, x = x, y = y, label = zone, title = title } })
        RefreshWaypointDisplay()
        BNB:Print(string.format("Waypoint pinned: %s %.1f, %.1f", title, x, y))
        if BNB.Sticky and BNB.Sticky.RefreshSettingsSituation then BNB.Sticky.RefreshSettingsSituation(id) end
    end)
    wpPinBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Pin current location", 1, 1, 1)
        GameTooltip:AddLine("Saves your current map coordinates to this note.", 0.78, 0.78, 0.78, true)
        GameTooltip:Show()
    end)
    wpPinBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    wpNavBtn:SetScript("OnClick", function()
        local id   = _noteID; if not id then return end
        local note = BNB.GetNote(id); if not note then return end
        local wp   = note.waypoint
        if not (wp and wp.x and wp.y and wp.mapID) then
            BNB:Print("|cffff6666No waypoint set on this note.|r"); return
        end
        local wpTitle = wp.title or wp.label or "BigNoteBox"
        local handled = false

        -- TomTom (any version with AddWaypoint)
        if TomTom and TomTom.AddWaypoint then
            pcall(function()
                TomTom:AddWaypoint(wp.mapID, wp.x / 100, wp.y / 100, {
                    title = wpTitle,
                    from  = "BigNoteBox",
                })
            end)
            handled = true
            BNB:Print(string.format("TomTom waypoint: %s (%.1f, %.1f)", wpTitle, wp.x, wp.y))
        end

        -- Retail built-in map pin (Dragonflight+)
        if not handled and C_Map and C_Map.SetUserWaypoint then
            local ok = pcall(function()
                -- UiMapPoint.CreateFromCoordinates exists on DF+
                local pt = UiMapPoint.CreateFromCoordinates(wp.mapID, wp.x / 100, wp.y / 100)
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

        -- Fallback: print a /way string the user can copy-paste into TomTom
        if not handled then
            local wayStr = string.format("/way %s %.1f %.1f %s",
                wp.label or GetRealZoneText() or "", wp.x, wp.y, wpTitle)
            BNB:Print("|cffff6666No waypoint addon detected.|r Copy: |cffffff00" .. wayStr .. "|r")
        end
    end)
    wpNavBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Navigate to waypoint", 1, 1, 1)
        GameTooltip:AddLine("Send the stored waypoint to your map or waypoint addon.", 0.78, 0.78, 0.78, true)
        GameTooltip:Show()
    end)
    wpNavBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    wpClearBtn:SetScript("OnClick", function()
        local id = _noteID; if not id then return end
        BNB.UpdateNote(id, { _clear = {"waypoint"} })
        RefreshWaypointDisplay()
        if BNB.Sticky and BNB.Sticky.RefreshSettingsSituation then BNB.Sticky.RefreshSettingsSituation(id) end
    end)
    wpClearBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Remove waypoint from this note", 1, 1, 1)
        GameTooltip:Show()
    end)
    wpClearBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- ── Load current note binding on open ─────────────────────────────────────
    panel._loadCtx = function()
        local note = _noteID and BNB.GetNote(_noteID)
        local ctx  = note and note.context
        local cd = note and note.contextDisplay
        if cd == "sticky" or cd == "both" then selDisplay = cd
        else selDisplay = "popup" end
        SetDispDropdownText(GetDispLabel(selDisplay))
        if dispDropdown and dispDropdown.GenerateMenu then dispDropdown:GenerateMenu() end
        local lv = note and note.contextLeave
        selLeave = (lv == "minimize" or lv == "hide") and lv or "keep"
        SetLeaveDropdownText(GetLeaveLabel(selLeave))
        if leaveDropdown and leaveDropdown.GenerateMenu then leaveDropdown:GenerateMenu() end

        if ctx and ctx ~= "" then
            local kind, value
            if BNB.DecodeContext then kind, value = BNB.DecodeContext(ctx) end
            if kind then
                local dropLabel = TYPE_LABELS[1]
                for i, k in ipairs(TYPES) do
                    if k == kind then dropLabel = TYPE_LABELS[i]; break end
                end
                selType = kind
                SetSituDropdownText(dropLabel)
                if typeDropdown and typeDropdown.GenerateMenu then typeDropdown:GenerateMenu() end
                SelectType(kind)
                if valueEb then valueEb:SetText(value or "") end
                clearCtxBtn:Show()
            else
                selType = "none"
                SetSituDropdownText(TYPE_LABELS[1])
                if typeDropdown and typeDropdown.GenerateMenu then typeDropdown:GenerateMenu() end
                SelectType("none")
                clearCtxBtn:Hide()
            end
        else
            selType = "none"
            SetSituDropdownText(TYPE_LABELS[1])
            if typeDropdown and typeDropdown.GenerateMenu then typeDropdown:GenerateMenu() end
            SelectType("none")
            clearCtxBtn:Hide()
        end
        RefreshCurBind()
        RefreshWaypointDisplay()
    end
end

-- ── Build window ──────────────────────────────────────────────────────────────
local SK_NC_TITLE_H   = 28
local SK_NC_CONTENT_Y = 58   -- SK_NC_TITLE_H(28) + SK_TAB_H(24) + 6px gap

local function CreateNoteConfigWindow()
    local skinMode = BigNoteBoxDB and BigNoteBoxDB.skinMode
    local tabContentY = skinMode and SK_NC_CONTENT_Y or TAB_CONTENT_Y
    local f

    if skinMode then
        f = BNB.CreateSkinFrame(UIParent, false, "BigNoteBoxNoteConfigFrame", false)
        _G["BigNoteBoxNoteConfigFrame"] = f
        f:SetSize(NCW, 640); f:SetPoint("CENTER")
        f:SetToplevel(true); f:EnableMouse(true); f:SetMovable(true); f:SetClampedToScreen(true)
        f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", function(s) s:StartMoving() end)
        f:SetScript("OnDragStop",  function(s) s:StopMovingOrSizing() end)

        local titleBar = BNB.CreateSkinStrip(f, true, false)
        titleBar:SetPoint("TOPLEFT",  f, "TOPLEFT",  0, 0)
        titleBar:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
        titleBar:SetHeight(SK_NC_TITLE_H)
        titleBar:EnableMouse(true)
        titleBar:RegisterForDrag("LeftButton")
        titleBar:SetScript("OnDragStart", function() f:StartMoving() end)
        titleBar:SetScript("OnDragStop",  function() f:StopMovingOrSizing() end)

        local titleLbl = titleBar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        titleLbl:SetPoint("CENTER", titleBar, "CENTER", -12, 0)
        titleLbl:SetTextColor(1, 0.82, 0)
        titleLbl:SetText("Note Settings")
        f._titleLbl = titleLbl

        local closeBtn = BNB.CreateSkinCloseButton(titleBar, function() f:Hide() end)
        closeBtn:SetPoint("RIGHT", titleBar, "RIGHT", -3, 0)

        f:SetScript("OnShow", function()
            if BNB.ApplyMainWindowSkin then BNB.ApplyMainWindowSkin() end
        end)
    else
        f = CreateFrame("Frame", "BigNoteBoxNoteConfigFrame", UIParent, "ButtonFrameTemplate")
        f:SetSize(NCW, 640); f:SetPoint("CENTER")
        f:SetToplevel(true); f:EnableMouse(true); f:SetMovable(true); f:SetClampedToScreen(true)
        f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", function(s) s:StartMoving() end)
        f:SetScript("OnDragStop",  function(s) s:StopMovingOrSizing() end)
        ButtonFrameTemplate_HidePortrait(f); ButtonFrameTemplate_HideButtonBar(f)
        if f.Inset then f.Inset:Hide() end
        f:SetAlpha(0.95)
        f:SetTitle("Note Settings")
        if f.CloseButton then f.CloseButton:SetScript("OnClick", function() f:Hide() end) end
    end
    tinsert(UISpecialFrames, "BigNoteBoxNoteConfigFrame")

    -- Close ZonePicker whenever NoteConfig hides (any path: close btn, ESC, main window close)
    f:HookScript("OnHide", function()
        if BNB.ZonePicker and BNB.ZonePicker.Close then BNB.ZonePicker.Close() end
    end)

    local tabDefs = {
        { label="General",    useScroll=true,  builder=BuildGeneralTab    },
        { label="Appearance", useScroll=false, builder=BuildAppearanceTab },
        { label="Situation",  useScroll=false, builder=BuildSituationTab  },
    }

    if skinMode then
        local tabCtrl = BNB.CreateSkinTabs(f, {"General", "Appearance", "Situation"},
            function(idx) BNB._NoteConfigSelectTab(idx) end)
        tabCtrl.frame:SetPoint("TOPLEFT",  f, "TOPLEFT",  0, -SK_NC_TITLE_H)
        tabCtrl.frame:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, -SK_NC_TITLE_H)
        f._skinTabCtrl = tabCtrl
    else
        local tpl = (C_XMLUtil and C_XMLUtil.GetTemplateInfo
            and C_XMLUtil.GetTemplateInfo("PanelTopTabButtonTemplate"))
            and "PanelTopTabButtonTemplate" or "PanelTabButtonTemplate"

        local lastBtn = nil
        for i, def in ipairs(tabDefs) do
            local btn = CreateFrame("Button", "BNBNoteConfigTab"..i, f, tpl)
            btn:SetText(def.label)
            pcall(function()
                if tpl == "PanelTopTabButtonTemplate" then PanelTemplates_TabResize(btn, 15, nil, 70)
                else PanelTemplates_TabResize(btn, 0) end
            end)
            btn:SetID(i)
            if lastBtn then btn:SetPoint("LEFT", lastBtn, "RIGHT", 5, 0)
            else             btn:SetPoint("TOPLEFT", f, "TOPLEFT", 7, -25) end
            btn:SetScript("OnClick", function(s) BNB._NoteConfigSelectTab(s:GetID()) end)
            tabBtns[i] = btn; lastBtn = btn
        end
        PanelTemplates_SetNumTabs(f, NUM_TABS); f.numTabs = NUM_TABS
    end

    for i, def in ipairs(tabDefs) do
        if def.useScroll then
            local sf, ct = MakeScrollPanel(f, tabContentY)
            tabPanels[i] = sf
            def.builder(sf, ct)
        else
            local p = MakePlainPanel(f, tabContentY)
            tabPanels[i] = p
            def.builder(p)
        end
    end

    f:Hide()
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
function BNB.OpenNoteConfig(noteID)
    if InCombatLockdown() then BNB:Print(L["COMBAT_BLOCKED"]); return end
    local note=noteID and BNB.GetNote(noteID)
    if not note then BNB:Print("No note selected."); return end

    if ncFrame and ncFrame:IsShown() and _noteID==noteID then ncFrame:Hide(); return end
    _noteID=noteID

    if not ncFrame then ncFrame=CreateNoteConfigWindow() end

    RefreshTitle()
    RefreshIconGrid(true)   -- scroll to show the currently selected icon on open
    local gPanel = tabPanels[TAB_GEN]
    if gPanel and gPanel._refreshScope    then gPanel._refreshScope()    end
    if gPanel and gPanel._hlFonts         then gPanel._hlFonts()         end
    if gPanel and gPanel._hlLockBtns      then gPanel._hlLockBtns()      end
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

    BNB._NoteConfigSelectTab(ncFrame._activeTab or TAB_GEN)

    ncFrame:ClearAllPoints()
    if BNB.mainFrame and BNB.mainFrame:IsShown() then
        ncFrame:SetPoint("TOPRIGHT",BNB.mainFrame,"TOPLEFT",-8,0)
    else
        ncFrame:SetPoint("CENTER")
    end
    ncFrame:Show()
end

-- Refreshes NoteConfig content when the selected note changes, but only if the
-- window is already open. No toggle, no reposition — called from SelectNote.
function BNB.SyncNoteConfig(noteID)
    if not ncFrame or not ncFrame:IsShown() then return end
    if not noteID then ncFrame:Hide(); return end
    local note = BNB.GetNote(noteID)
    if not note then ncFrame:Hide(); return end

    _noteID = noteID
    RefreshTitle()
    RefreshIconGrid(true)   -- scroll to selected icon when syncing to a new note

    local gPanel = tabPanels[TAB_GEN]
    if gPanel and gPanel._refreshScope    then gPanel._refreshScope()    end
    if gPanel and gPanel._hlFonts         then gPanel._hlFonts()         end
    if gPanel and gPanel._hlLockBtns      then gPanel._hlLockBtns()      end
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
end

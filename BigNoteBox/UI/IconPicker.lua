-- BigNoteBox UI/IconPicker.lua
-- Note icon picker (ALL-238, 2026-10-04): the icon catalog
-- (Assets/Icons/IconManifest.lua) as a thumbnail grid, a side list of
-- categories, search on top. Same window family as the Icon Frame and sticky
-- background pickers. The whole game list (~32k names, the load-on-demand
-- addon BigNoteBox_Icons) is opt-in: the checkbox under the side list is the
-- same saved setting as Settings' Blizzard icon autocomplete
-- (db.blizzardIconComplete), and "Game (all)" shows only while it is on.
--
-- The grid draws only the rows on screen from a small tile pool, so a long
-- list costs no more than a short one (WoW never frees a frame).
--
--   IP.Open(key, anchor, h)   key = what the pick is for (a note id, or a
--                             dialog's own key); toggles.
--                             anchor = the window to sit beside, top aligned
--                             (as IconFramePicker). h = {
--                               owner = "noteConfig" / "newNote" / "insertIcon" /
--                                     "sidebar": the window that opened the picker,
--                               get = fn() -> current icon path / file id or nil,
--                               set = fn(icon, source)  icon nil = no icon;
--                                     source "curated" (catalog) / "blizzard",
--                               gameOnly = true: game icons only, the bundled
--                                     race portraits are left out ({icon} markup
--                                     reads names under Interface\Icons),
--                               strata = frame strata, nil = "DIALOG",
--                               startSide = side list id to open on while the
--                                     current icon is in no catalog category,
--                               defaultNone = true: Use Default clears the icon
--                                     (the owner draws its own default; the
--                                     sidebar's class icon, ALL-243), nil = a
--                                     random note icon,
--                             }
--   IP.Rebind(key, h)         another note in the same window; does nothing
--                             while the picker belongs to another owner
--   IP.Close(owner)           owner nil = whoever has it; else only that owner's
--   IP.IsOpenFor(key)

local BNB = BigNoteBox
if not BNB then return end
local L = BNB.L

local IP = {}
BNB.IconPicker = IP

local W, H       = 500, 500
local PAD        = 14
local SEARCH_Y   = 34      -- search box top, under the title
local CONTENT_Y  = 64      -- side list and grid top
local FOOT_H     = 38
local SIDE_W     = 112
local SIDE_ROW_H = 20
local GAP        = 4
-- The selection outline reaches this far past a tile; the grid keeps it as a
-- margin, or the scroll frame clips the outline on the outer rows / columns
local SEL_PAD    = 2
local SBAR_W     = 20
local GRID_X     = PAD + SIDE_W + 10
local AREA_W     = W - GRID_X - PAD - SBAR_W   -- room for the grid
local SIZE_BTN_W = 96
-- Icon sizes, cycled by the size button (Dukul, 2026-10-04); saved in
-- BigNoteBoxDB.iconPickerSize, nil = 2 (medium, the first size)
local SIZES = {
    { cell = 28, label = "ICON_PICKER_SIZE_SMALL" },
    { cell = 36, label = "ICON_PICKER_SIZE_MEDIUM" },
    { cell = 48, label = "ICON_PICKER_SIZE_LARGE" },
}
-- Set by ApplySize from the saved size
local CELL, STEP, COLS
local function SizeIndex()
    local i = BigNoteBoxDB and BigNoteBoxDB.iconPickerSize
    return SIZES[i] and i or 2
end
local function ApplySize()
    CELL = SIZES[SizeIndex()].cell
    STEP = CELL + GAP
    COLS = math.floor((AREA_W - 2 * SEL_PAD + GAP) / STEP)
end
ApplySize()
local GRID_W     = AREA_W
local WHITE      = "Interface\\Buttons\\White8x8"
local GAME       = "Interface\\Icons\\"
local SEL_R, SEL_G, SEL_B = 0.40, 0.85, 0.40

-- Side list, top to bottom. "cats" = catalog keys shown together; "all" =
-- every catalog icon; "game" = the full game list (only while it is loaded)
local SIDES = {
    { id = "all",         label = "ICON_PICKER_CAT_ALL" },
    { id = "notes",       label = "ICON_PICKER_CAT_NOTES",       cats = { "notes" } },
    { id = "books",       label = "ICON_PICKER_CAT_BOOKS",       cats = { "books" } },
    { id = "classes",     label = "ICON_PICKER_CAT_CLASSES",     cats = { "classes" } },
    { id = "races",       label = "ICON_PICKER_CAT_RACES",       cats = { "races" }, bundled = true },
    { id = "factions",    label = "ICON_PICKER_CAT_FACTIONS",    cats = { "factions" } },
    { id = "professions", label = "ICON_PICKER_CAT_PROFESSIONS", cats = { "professions" } },
    { id = "zones",       label = "ICON_PICKER_CAT_ZONES",       cats = { "zones" } },
    { id = "instances",   label = "ICON_PICKER_CAT_INSTANCES",   cats = { "instances" } },
    { id = "misc",        label = "ICON_PICKER_CAT_MISC",        cats = { "random", "storage" } },
    { id = "game",        label = "ICON_PICKER_CAT_GAME",        game = true },
}

-- Typing one of these (or the start of one) also finds the listed terms
local SYNONYMS = {
    ["race"]       = { "character", "achievement_character" },
    ["character"]  = { "race", "achievement_character" },
    ["class"]      = { "classicon" },
    ["dungeon"]    = { "instance", "achievement_dungeon" },
    ["raid"]       = { "achievement_raid" },
    ["zone"]       = { "achievement_zone", "teleport" },
    ["profession"] = { "trade", "inv_misc_profession" },
    ["spell"]      = { "ability" },
    ["note"]       = { "inv_misc_note", "inv_misc_notescript" },
}

local _f, _sf, _ct, _search, _allCb, _revertBtn, _portBtn
local _sideBtns = {}
local _tiles = {}
local _side = "all"           -- remembered for the session
local _list = {}              -- what the grid shows: paths, or bare names for "game"
local _listIsNames = false
local _key, _h, _orig, _origSource
local Render, Fill

local function GameListOn()
    return BigNoteBoxDB and BigNoteBoxDB.blizzardIconComplete == true and BNB.BlizzardIconList ~= nil
end

local function SideDef(id)
    for _, s in ipairs(SIDES) do if s.id == id then return s end end
end

-- Bundled catalog categories (race portraits, Assets/Icons/Races) are left out
-- for a game-only pick
local function CatShown(key)
    return not (_h and _h.gameOnly and key == "races")
end

local function SideShown(s)
    if s.game then return GameListOn() end
    return not (s.bundled and _h and _h.gameOnly)
end

local function IconName(icon)
    if type(icon) == "number" then return "#" .. icon end
    return type(icon) == "string" and (icon:match("([^\\/]+)$") or icon) or ""
end
IP.IconName = IconName

local function SearchText()
    if not _search or _search._showingPlaceholder then return "" end
    return (_search:GetText() or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
end

local function Terms(text)
    local terms, seen = { text }, { [text] = true }
    for key, syns in pairs(SYNONYMS) do
        if key:sub(1, #text) == text then
            for _, s in ipairs(syns) do
                if not seen[s] then terms[#terms + 1] = s; seen[s] = true end
            end
        end
    end
    return terms
end

local function Matches(name, terms)
    name = name:lower()
    for _, t in ipairs(terms) do
        if name:find(t, 1, true) then return true end
    end
    return false
end

-- Rebuilds _list from the side entry and the search text
local function BuildList()
    local s = SideDef(_side) or SIDES[1]
    local text = SearchText()
    local terms = text ~= "" and Terms(text)
    local out = {}
    if s.game then
        _listIsNames = true
        for _, name in ipairs(BNB.BlizzardIconList or {}) do
            if not terms or Matches(name, terms) then out[#out + 1] = name end
        end
    else
        _listIsNames = false
        local cats = s.cats
        for _, c in ipairs(BNB.ICON_CATALOG or {}) do
            local wanted = not cats
            if cats then
                for _, k in ipairs(cats) do if k == c.key then wanted = true end end
            end
            if wanted and CatShown(c.key) then
                for _, path in ipairs(c.list) do
                    if not terms or Matches(IconName(path), terms) then out[#out + 1] = path end
                end
            end
        end
    end
    _list = out
end

local function EntryIcon(i)
    local e = _list[i]
    if e and _listIsNames then return GAME .. e end
    return e
end

local function SameIcon(a, b)
    if a == nil or b == nil then return a == b end   -- no icon = no icon (Revert)
    if type(a) == "string" and type(b) == "string" then return a:lower() == b:lower() end
    return a == b
end

-- "NPC portrait": shown for NPC target notes, greyed while the portrait shows
local function PaintPortraitBtn()
    if not _portBtn then return end
    local npc = _h and _h.usePortrait ~= nil
    _portBtn:SetShown(npc)
    if npc then _portBtn:SetEnabled(not _h.portraitOn()) end
end

local function Pick(icon, source)
    if not _h then return end
    _h.set(icon, source)
    Fill()
    -- Revert also counts a source change (an NPC note's portrait coming back)
    if _revertBtn then
        _revertBtn:SetEnabled(not SameIcon(_h.get(), _orig)
            or (_h.getSource and _h.getSource()) ~= _origSource)
    end
    PaintPortraitBtn()
end

-- A full game icon name or file id typed into the search box (Enter)
local function PickTyped()
    local raw = _search and not _search._showingPlaceholder and (_search:GetText() or "") or ""
    raw = raw:gsub("^%s+", ""):gsub("%s+$", "")
    if raw == "" then return end
    local id = tonumber(raw)
    if id then Pick(id, "blizzard"); return end
    local name = raw:match("([^\\/]+)$") or raw
    local fid = GetFileIDFromPath and GetFileIDFromPath(GAME .. name)
    if fid then
        -- The catalog's own spelling when it is one of ours (races are bundled)
        for _, c in ipairs(BNB.ICON_CATALOG or {}) do
            for _, path in ipairs(CatShown(c.key) and c.list or {}) do
                if IconName(path):lower() == name:lower() then Pick(path, "curated"); return end
            end
        end
        Pick(GAME .. name, "blizzard")
    elseif #_list == 1 then
        Pick(EntryIcon(1), _listIsNames and "blizzard" or "curated")
    end
end

local function MakeTile()
    local t = CreateFrame("Button", nil, _ct)
    t:SetSize(CELL, CELL)
    t.icon = t:CreateTexture(nil, "ARTWORK")
    t.icon:SetAllPoints()
    t.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    t.sel = CreateFrame("Frame", nil, t, "BackdropTemplate")
    t.sel:SetPoint("TOPLEFT", -SEL_PAD, SEL_PAD); t.sel:SetPoint("BOTTOMRIGHT", SEL_PAD, -SEL_PAD)
    t.sel:SetBackdrop({ edgeFile = WHITE, edgeSize = 2 })
    t.sel:SetBackdropBorderColor(SEL_R, SEL_G, SEL_B, 1)
    t.sel:EnableMouse(false)
    t.sel:Hide()
    local hi = t:CreateTexture(nil, "HIGHLIGHT")
    hi:SetAllPoints(); hi:SetColorTexture(1, 1, 1, 0.25)
    t:SetScript("OnClick", function(self)
        Pick(self._icon, _listIsNames and "blizzard" or "curated")
    end)
    -- Double-click = pick and close, as the frame / background pickers (ALL-141)
    t:SetScript("OnDoubleClick", function(self)
        Pick(self._icon, _listIsNames and "blizzard" or "curated")
        IP.Close()
    end)
    t:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(IconName(self._icon), 1, 1, 1)
        GameTooltip:Show()
    end)
    t:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return t
end

-- Places the pooled tiles on the rows in view
Fill = function()
    if not (_f and _h) then return end
    local offset = _sf:GetVerticalScroll() or 0
    local first = math.floor(offset / STEP)
    local rows = math.ceil((_sf:GetHeight() or 0) / STEP) + 1
    local need = rows * COLS
    for i = #_tiles + 1, need do _tiles[i] = MakeTile() end
    local cur = _h.get()
    for i, t in ipairs(_tiles) do
        local idx = first * COLS + i
        local icon = i <= need and EntryIcon(idx)
        if icon then
            local r = math.floor((idx - 1) / COLS)
            t:ClearAllPoints()
            t:SetPoint("TOPLEFT", _ct, "TOPLEFT",
                SEL_PAD + ((idx - 1) % COLS) * STEP, -SEL_PAD - r * STEP)
            t._icon = icon
            t.icon:SetTexture(icon)
            t.sel:SetShown(SameIcon(icon, cur))
            t:Show()
        else
            t:Hide()
        end
    end
end

local function PaintSide()
    for _, b in ipairs(_sideBtns) do
        local on = b._id == _side
        b.lbl:SetTextColor(on and SEL_R or 0.85, on and SEL_G or 0.85, on and SEL_B or 0.85)
        b.bg:SetShown(on)
        b:SetShown(SideShown(SideDef(b._id)))
    end
end

Render = function(keepScroll)
    if not (_f and _h) then return end
    if not SideShown(SideDef(_side) or SIDES[1]) then _side = "all" end
    BuildList()
    PaintSide()
    local rows = math.ceil(#_list / COLS)
    _sf:FinaliseHeight(rows * STEP - GAP + 2 * SEL_PAD)
    if not keepScroll then _sf:SetVerticalScroll(0) end
    Fill()
    if _revertBtn then
        _revertBtn:SetEnabled(not SameIcon(_h.get(), _orig)
            or (_h.getSource and _h.getSource()) ~= _origSource)
    end
    _f._empty:SetShown(#_list == 0)
    PaintPortraitBtn()
end

-- Redraws the list shown and scrolls the current icon into view
local function ScrollToCurrent()
    local cur = _h and _h.get()
    Render()
    for i = 1, #_list do
        if SameIcon(EntryIcon(i), cur) then
            local y = math.floor((i - 1) / COLS) * STEP
            C_Timer.After(0.06, function()
                if _f and _f:IsShown() then
                    local maxY = _sf:GetVerticalScrollRange() or 0
                    _sf:SetVerticalScroll(math.min(maxY, math.max(0, y - STEP)))
                    Fill()
                end
            end)
            break
        end
    end
end

-- Opens on the category holding the current icon, scrolled to it; else on
-- h.startSide when given, else on the side last used
local function ShowCurrent()
    local cur = _h and _h.get()
    local cat = type(cur) == "string" and BNB.ICON_CATEGORY and BNB.ICON_CATEGORY[cur]
    if cat and CatShown(cat) then
        for _, s in ipairs(SIDES) do
            for _, k in ipairs(s.cats or {}) do if k == cat then _side = s.id end end
        end
    elseif _h and _h.startSide and SideDef(_h.startSide) then
        _side = _h.startSide
    end
    ScrollToCurrent()
end

local function SetGameList(on)
    local db = BigNoteBoxDB
    if not db then return end
    db.blizzardIconComplete = on
    if on then
        if BNB.InitBlizzardIconList then BNB.InitBlizzardIconList(true) end
        if GameListOn() then _side = "game" end
    else
        -- Same as Settings > Modules: stop using the list now, memory is freed
        -- by a reload (the popup says so)
        BNB.BlizzardIconList = nil
        StaticPopup_Show("BNB_BLZICON_AC_DISABLE")
    end
    if _allCb then _allCb:SetChecked(db.blizzardIconComplete == true) end
    Render()
end

local function Build()
    if _f then return end
    local f, revertBtn, closeBtn = BNB.CreateToolWindow({
        name = "BigNoteBoxIconPicker", w = W, h = H, title = L["ICON_PICKER_TITLE"],
        pad = PAD, cw = W - 2 * PAD, footH = FOOT_H,
        btn1 = L["STICKY_BGP_REVERT"], btn2 = L["CLOSE"],
        toplevel = true, escClose = true,
        onClose = function() IP.Close() end,
        onHide  = function()
            _key, _h, _orig, _origSource = nil, nil, nil, nil
            GameTooltip:Hide()
        end,
    })
    _f, _revertBtn = f, revertBtn

    -- Footer: Use Default / Random on the left, Revert / Close on the right
    local bW = math.floor((W - 2 * PAD - 3 * 8) / 4)
    local defBtn = BNB.CreateButton(nil, f, L["NC_USE_DEFAULT_BTN"], bW, 26)
    local rndBtn = BNB.CreateButton(nil, f, L["NC_RANDOM_BTN"], bW, 26)
    for i, b in ipairs({ defBtn, rndBtn, revertBtn, closeBtn }) do
        b:SetSize(bW, 26)
        b:ClearAllPoints()
        b:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", PAD + (i - 1) * (bW + 8), 6)
    end
    -- Use Default: a random note icon, as Note Settings always did; no icon
    -- for an owner with its own default (h.defaultNone)
    defBtn:SetScript("OnClick", function()
        if _h and _h.defaultNone then Pick(nil); return end
        local notes = BNB.IconsIn("notes")
        if #notes > 0 then Pick(notes[math.random(#notes)], "curated") end
    end)
    -- Random: any icon of the list on screen
    rndBtn:SetScript("OnClick", function()
        if #_list > 0 then
            Pick(EntryIcon(math.random(#_list)), _listIsNames and "blizzard" or "curated")
        end
    end)
    revertBtn:SetScript("OnClick", function()
        if _h then Pick(_orig, _origSource) end
    end)
    closeBtn:SetScript("OnClick", function() IP.Close() end)

    -- Icon size: Small / Medium / Large, right of the search box
    local sizeBtn = BNB.CreateButton(nil, f, "", SIZE_BTN_W, 22)
    sizeBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -PAD, -SEARCH_Y)
    local function SizeLabel() sizeBtn:SetText(L[SIZES[SizeIndex()].label]) end
    SizeLabel()
    f._sizeLabel = SizeLabel
    sizeBtn:SetScript("OnClick", function()
        if not BigNoteBoxDB then return end
        local i = SizeIndex() % #SIZES + 1
        BigNoteBoxDB.iconPickerSize = (i ~= 2) and i or nil
        ApplySize()
        SizeLabel()
        for _, t in ipairs(_tiles) do t:SetSize(CELL, CELL) end
        ScrollToCurrent()   -- same category, current icon kept in view
    end)
    sizeBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetText(L["ICON_PICKER_SIZE_TIP"], 1, 1, 1)
        GameTooltip:Show()
    end)
    sizeBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Search: filters the category; Enter takes a full game icon name or id
    local sBg = BNB.CreateBackdropFrame("Frame", nil, f); BNB.SetBackdropDark(sBg)
    sBg:SetPoint("TOPLEFT",  f, "TOPLEFT",  PAD,  -SEARCH_Y)
    sBg:SetPoint("TOPRIGHT", sizeBtn, "TOPLEFT", -6, 0)
    sBg:SetHeight(22)
    -- The edit box stops short of the x: covering it, it took the x's clicks
    local eb = CreateFrame("EditBox", nil, sBg)
    eb:SetPoint("TOPLEFT", sBg, "TOPLEFT", 0, 0)
    eb:SetPoint("BOTTOMRIGHT", sBg, "BOTTOMRIGHT", -22, 0)
    eb:SetTextInsets(6, 4, 0, 0)
    eb:SetFontObject("GameFontNormal"); eb:SetAutoFocus(false); eb:SetMaxLetters(128)
    BNB.AddPlaceholder(eb, L["ICON_PICKER_SEARCH"], 0.4, 0.4, 0.4)
    _search = eb
    local clr = CreateFrame("Button", nil, sBg)
    clr:SetSize(18, 18); clr:SetPoint("RIGHT", sBg, "RIGHT", -2, 0)
    clr:SetFrameLevel(eb:GetFrameLevel() + 2)
    local clrLbl = clr:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    clrLbl:SetAllPoints(); clrLbl:SetText(L["NC_CLEAR_X"]); clrLbl:SetTextColor(0.65, 0.65, 0.65)
    clr:SetScript("OnEnter", function() clrLbl:SetTextColor(1, 0.4, 0.4) end)
    clr:SetScript("OnLeave", function() clrLbl:SetTextColor(0.65, 0.65, 0.65) end)
    clr:Hide()
    clr:SetScript("OnClick", function()
        eb:ClearFocus()
        eb:SetRealText("")
        clr:Hide()
        BNB.CancelDebounce("iconPickerSearch")
        Render()
    end)
    eb:SetScript("OnTextChanged", function(self, user)
        if not user then return end
        clr:SetShown(SearchText() ~= "")
        BNB.Debounce("iconPickerSearch", 0.15, Render)
    end)
    eb:SetScript("OnEnterPressed", function(self) PickTyped(); self:ClearFocus() end)
    eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

    -- Side list
    local y = -CONTENT_Y
    for _, s in ipairs(SIDES) do
        local b = CreateFrame("Button", nil, f)
        b:SetSize(SIDE_W, SIDE_ROW_H)
        b:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, y)
        b._id = s.id
        b.bg = b:CreateTexture(nil, "BACKGROUND")
        b.bg:SetAllPoints(); b.bg:SetColorTexture(SEL_R, SEL_G, SEL_B, 0.15)
        local hi = b:CreateTexture(nil, "HIGHLIGHT")
        hi:SetAllPoints(); hi:SetColorTexture(1, 1, 1, 0.08)
        b.lbl = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        b.lbl:SetPoint("LEFT", b, "LEFT", 6, 0)
        b.lbl:SetPoint("RIGHT", b, "RIGHT", -4, 0)
        b.lbl:SetJustifyH("LEFT"); b.lbl:SetWordWrap(false)
        b.lbl:SetText(L[s.label])
        b:SetScript("OnClick", function(self) _side = self._id; Render() end)
        _sideBtns[#_sideBtns + 1] = b
        y = y - SIDE_ROW_H - 2
    end

    -- The opt-in to the whole game list, under the side list
    local cb = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
    cb:SetSize(22, 22)
    cb:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", PAD - 2, FOOT_H + 8)
    local cbLbl = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    cbLbl:SetPoint("LEFT", cb, "RIGHT", 2, 0)
    cbLbl:SetWidth(SIDE_W - 22); cbLbl:SetJustifyH("LEFT")
    cbLbl:SetText(L["ICON_PICKER_ALL_GAME"])
    cb:SetScript("OnClick", function(self) SetGameList(self:GetChecked() and true or false) end)
    cb:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(L["ICON_PICKER_ALL_GAME"], 1, 1, 1)
        GameTooltip:AddLine(L["ICON_PICKER_ALL_GAME_TIP"], 1, 0.82, 0, true)
        GameTooltip:AddLine(L["ICON_PICKER_ALL_GAME_WARN"], 1, 0.4, 0.4, true)
        GameTooltip:Show()
    end)
    cb:SetScript("OnLeave", function() GameTooltip:Hide() end)
    _allCb = cb

    -- NPC target notes only (h.usePortrait): back to the creature's portrait,
    -- which an icon picked here replaces (BNB.SetNpcNotePortrait)
    local pb = BNB.CreateButton(nil, f, L["ICON_PICKER_PORTRAIT"], SIDE_W, 22)
    pb:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", PAD, FOOT_H + 8 + 28)
    pb:SetScript("OnClick", function()
        if _h and _h.usePortrait then _h.usePortrait(); Render(true) end
    end)
    pb:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(L["ICON_PICKER_PORTRAIT"], 1, 1, 1)
        GameTooltip:AddLine(L["ICON_PICKER_PORTRAIT_TIP"], 1, 0.82, 0, true)
        GameTooltip:Show()
    end)
    pb:SetScript("OnLeave", function() GameTooltip:Hide() end)
    pb:Hide()
    _portBtn = pb

    -- Grid
    _sf, _ct = BNB.CreateAutoScrollPanel(f, GRID_W, GRID_W)
    _sf:SetPoint("TOPLEFT",     f, "TOPLEFT",     GRID_X, -CONTENT_Y)
    _sf:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -PAD - SBAR_W, FOOT_H + 6)
    _sf:HookScript("OnVerticalScroll", function() Fill() end)
    _sf:HookScript("OnSizeChanged", function() Fill() end)

    f._empty = f:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    f._empty:SetPoint("TOP", _sf, "TOP", 0, -20)
    f._empty:SetText(L["ICON_PICKER_EMPTY"])
    f._empty:Hide()
end

function IP.IsOpenFor(key)
    return _f and _f:IsShown() and _key == key or false
end

function IP.Open(key, anchor, h)
    if IP.IsOpenFor(key) then IP.Close(); return end
    -- The saved size: SavedVariables are not there yet when this file loads
    ApplySize()
    Build()
    _f._sizeLabel()
    for _, t in ipairs(_tiles) do t:SetSize(CELL, CELL) end
    _key, _h = key, h
    _orig = h.get()
    _origSource = h.getSource and h.getSource() or nil
    _allCb:SetChecked(BigNoteBoxDB and BigNoteBoxDB.blizzardIconComplete == true)
    -- The New note dialog dims the main window with a FULLSCREEN_DIALOG overlay;
    -- from Focus mode (the Ico dialog) it goes over the Focus window (ALL-251)
    BNB.SeatWindow(_f, h.strata or "DIALOG")
    -- Top-aligned beside the window, as the Icon Frame picker
    _f:ClearAllPoints()
    if anchor and anchor.GetRight then
        local ar = anchor:GetRight() or 0
        if ar + 8 + W <= UIParent:GetWidth() then
            _f:SetPoint("TOPLEFT", anchor, "TOPRIGHT", 8, 0)
        else
            _f:SetPoint("TOPRIGHT", anchor, "TOPLEFT", -8, 0)
        end
    else
        _f:SetPoint("CENTER", UIParent, "CENTER", 0, 60)
    end
    _f:SetAlpha(BNB.WindowAlpha(_f))
    _f:Show()
    _f:Raise()
    ShowCurrent()
end

function IP.Rebind(key, h)
    if not (_f and _f:IsShown() and _h) or _h.owner ~= h.owner then return end
    _key, _h = key, h
    _orig = h.get()
    _origSource = h.getSource and h.getSource() or nil
    ShowCurrent()
end

-- The note's icon changed from outside (Note Settings' Random): redraw the
-- outline, keep the category, scroll and Revert target
function IP.Refresh()
    if _f and _f:IsShown() and _h then Render(true) end
end

function IP.Close(owner)
    if owner and not (_h and _h.owner == owner) then return end
    if _f and _f:IsShown() then _f:Hide() end
end

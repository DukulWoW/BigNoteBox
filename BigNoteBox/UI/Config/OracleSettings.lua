-- BigNoteBox UI/Config/OracleSettings.lua - Settings > Modules > Oracle search (ALL-69.4)
-- The Oracle bar's sub-page: on/off, keybinding, Look (theme, results shown),
-- Position (move / preview, reset), Behaviour (open mode, close after
-- opening, ranking weights). Built by UI/Config/Modules.lua through
-- K.BuildOraclePage; opened from outside with BNB.OpenSettingsPage("modules", "oracle")
-- (a right-click on the bar). The settings keys are listed in UI/Oracle.lua.

local BNB = BigNoteBox
local L   = BNB.L

local K = BNB._ConfigKit
local CONTENT_W, ROW_H, ROW_GAP = K.CONTENT_W, K.ROW_H, K.ROW_GAP
local AddRule, AddHeader, AddCheck = K.AddRule, K.AddHeader, K.AddCheck

-- Built-in theme names are translated; a theme from another addon shows its own name.
local THEME_NAME_KEY = {
    kilrogg  = "SEARCH_THEME_KILROGG",
    alliance = "SEARCH_THEME_ALLIANCE",
    horde    = "SEARCH_THEME_HORDE",
    ["the-eye"] = "SEARCH_THEME_THE_EYE",
    ["molten-core"] = "SEARCH_THEME_MOLTEN_CORE",
    custom   = "SEARCH_THEME_CUSTOM",
}
local function ThemeName(id)
    local t = BNB.GetSearchTheme(id)
    if not t then return "" end
    local key = THEME_NAME_KEY[t.id]
    return key and L[key] or t.name
end

-- Ranking rows, in the order shown; keys are OracleSearch.WEIGHT_DEFAULTS'.
local WEIGHTS = {
    { key = "target", label = "CFG_ORACLE_W_TARGET" },
    { key = "char",   label = "CFG_ORACLE_W_CHAR"   },
    { key = "zone",   label = "CFG_ORACLE_W_ZONE"   },
    { key = "fav",    label = "CFG_ORACLE_W_FAV"    },
    { key = "opened", label = "CFG_ORACLE_W_OPENED" },
    { key = "edited", label = "CFG_ORACLE_W_EDITED" },
    { key = "alarm",  label = "CFG_ORACLE_W_ALARM"  },
}
local LEVEL_KEY = {
    off = "CFG_ORACLE_LVL_OFF", low = "CFG_ORACLE_LVL_LOW",
    normal = "CFG_ORACLE_LVL_NORMAL", high = "CFG_ORACLE_LVL_HIGH",
}

local DD_H     = 22
local WEIGHT_W = 130   -- level dropdown width

local function Tip(w, text)
    w:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(text, 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    w:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

local function Label(ct, y, text)
    local fs = ct:CreateFontString(nil, "OVERLAY", "BNBFontNormal")
    fs:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
    fs:SetHeight(ROW_H); fs:SetJustifyH("LEFT")
    fs:SetText(text)
    return fs
end

-- A colour square with its label; click = the colour picker with opacity.
-- get() -> { r, g, b, a }; set(r, g, b, a). noAlpha: no opacity slider in
-- the picker. Returns the button; :Update() redraws it from get().
local SWATCH = 22
local function ColourSwatch(parent, x, y, text, get, set, noAlpha)
    local sw = CreateFrame("Button", nil, parent)
    sw:SetSize(SWATCH, SWATCH)
    sw:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    -- Checker-free: a dark square under the colour shows its opacity.
    local under = sw:CreateTexture(nil, "BACKGROUND")
    under:SetAllPoints(); under:SetColorTexture(0.1, 0.1, 0.1, 1)
    local tx = sw:CreateTexture(nil, "ARTWORK"); tx:SetAllPoints()
    local hi = sw:CreateTexture(nil, "HIGHLIGHT"); hi:SetAllPoints()
    hi:SetColorTexture(1, 1, 1, 0.25)
    local bdr = BNB.CreateBackdropFrame("Frame", nil, sw)
    bdr:SetAllPoints(); bdr:SetFrameLevel(sw:GetFrameLevel() + 1)
    BNB.SetBackdrop(bdr, 0, 0, 0, 0, 0.45, 0.45, 0.48, 1)
    bdr:EnableMouse(false)
    local lbl = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    lbl:SetPoint("LEFT", sw, "RIGHT", 6, 0)
    lbl:SetText(text)
    sw._lbl = lbl
    function sw:Update()
        local c = get()
        tx:SetColorTexture(c[1], c[2], c[3], c[4] or 1)
    end
    sw:SetScript("OnClick", function()
        local c = get()
        local old = { c[1], c[2], c[3], c[4] or 1 }
        BNB.OpenColorPicker(old[1], old[2], old[3], function(r, g, b, a)
            set(r, g, b, a or old[4]); sw:Update()
        end, function()
            set(old[1], old[2], old[3], old[4]); sw:Update()
        end, (not noAlpha) and old[4] or nil)
    end)
    Tip(sw, L["CFG_ORACLE_SWATCH_TIP"])
    sw:Update()
    return sw
end

-- LibSharedMedia names of one kind, sorted; empty without the library.
local function LSMList(kind)
    local lsm = LibStub and LibStub("LibSharedMedia-3.0", true)
    local out = {}
    if lsm then
        for _, name in ipairs(lsm:List(kind) or {}) do out[#out + 1] = { label = name, value = name } end
    end
    return out
end

-- Font entries: WoW's own, BigNoteBox's cards for the active language,
-- then LibSharedMedia's (values as BNB.SearchFontPath reads them).
local function FontEntries()
    local out = { { label = L["CFG_ORACLE_FONT_WOW"], value = "" } }
    for _, def in ipairs(BNB.GetPickerFonts(false)) do
        out[#out + 1] = { label = def.label, value = "bnb:" .. def.id }
    end
    for _, e in ipairs(LSMList("font")) do
        out[#out + 1] = { label = e.label, value = "lsm:" .. e.value }
    end
    return out
end

-- ── Saved styles: popups (ALL-69.5, like BigChatBox's) ────────────────────────
-- styleUI: the open page's refresh (style list + every knob), set by
-- BuildCustomBlock; the popups call it after they change anything.
local styleUI

local function PopupEditBox(self)
    return (self.GetEditBox and self:GetEditBox()) or self.EditBox or self.editBox
end

-- Saves under name: the current look, or data (an imported style).
local function SaveAs(name, data)
    BNB.SaveSearchStyle(name, data)
    BNB:Print(string.format(L["ORACLE_STYLE_SAVED"], name))
    if styleUI then styleUI() end
end

local function TrySave(name, data)
    name = (name or ""):match("^%s*(.-)%s*$")
    if name == "" then return end
    local existing = BigNoteBoxDB.oracleStyles and BigNoteBoxDB.oracleStyles[name]
    if existing then
        StaticPopup_Show("BNB_ORACLE_OVERWRITE_STYLE", name, nil, { name = name, style = data })
    else
        SaveAs(name, data)
    end
end

StaticPopupDialogs["BNB_ORACLE_SAVE_STYLE"] = {
    preferredIndex = 3,
    text = L["ORACLE_STYLE_SAVE_TEXT"], hasEditBox = true, maxLetters = 40,
    button1 = SAVE, button2 = CANCEL,
    OnShow = function(self, data)
        local eb = PopupEditBox(self)
        local cur = BNB.GetSearchStyleID():match("^user:(.+)$")
        if eb then eb:SetText((not (data and data.imported)) and cur or ""); eb:HighlightText() end
    end,
    OnAccept = function(self, data)
        local eb = PopupEditBox(self)
        TrySave(eb and eb:GetText(), data and data.style)
    end,
    EditBoxOnEnterPressed = function(eb)
        local p = eb:GetParent()
        TrySave(eb:GetText(), p.data and p.data.style)
        p:Hide()
    end,
    EditBoxOnEscapePressed = function(eb) eb:GetParent():Hide() end,
    timeout = 0, whileDead = true, hideOnEscape = true,
}

StaticPopupDialogs["BNB_ORACLE_OVERWRITE_STYLE"] = {
    preferredIndex = 3,
    text = L["ORACLE_STYLE_OVERWRITE"], button1 = YES, button2 = NO,
    OnAccept = function(self, data) if data then SaveAs(data.name, data.style) end end,
    timeout = 0, whileDead = true, hideOnEscape = true,
}

StaticPopupDialogs["BNB_ORACLE_DELETE_STYLE"] = {
    preferredIndex = 3,
    text = L["ORACLE_STYLE_DELETE"], button1 = DELETE, button2 = CANCEL,
    OnAccept = function(self, data)
        if not data then return end
        BNB.DeleteSearchStyle(data)
        BNB:Print(string.format(L["ORACLE_STYLE_DELETED"], data))
        if styleUI then styleUI() end
    end,
    timeout = 0, whileDead = true, hideOnEscape = true,
}

StaticPopupDialogs["BNB_ORACLE_EXPORT_STYLE"] = {
    preferredIndex = 3,
    -- maxLetters = 0: no limit; the default cut the string short (Dukul, 2026-09-28)
    text = L["ORACLE_STYLE_EXPORT_TEXT"], hasEditBox = true, editBoxWidth = 350, maxLetters = 0,
    button1 = CLOSE,
    OnShow = function(self, data)
        local eb = PopupEditBox(self)
        if eb then eb:SetText(data or ""); eb:HighlightText(); eb:SetFocus() end
    end,
    EditBoxOnEscapePressed = function(eb) eb:GetParent():Hide() end,
    timeout = 0, whileDead = true, hideOnEscape = true,
}

local function TryImport(text)
    local style = BNB.ImportSearchStyle(text)
    if not style then BNB:Print(L["ORACLE_STYLE_IMPORT_BAD"]); return end
    -- Name it next frame: this popup is still closing.
    C_Timer.After(0.1, function()
        StaticPopup_Show("BNB_ORACLE_SAVE_STYLE", nil, nil, { style = style, imported = true })
    end)
end

StaticPopupDialogs["BNB_ORACLE_IMPORT_STYLE"] = {
    preferredIndex = 3,
    text = L["ORACLE_STYLE_IMPORT_TEXT"], hasEditBox = true, editBoxWidth = 350, maxLetters = 0,
    button1 = L["ORACLE_STYLE_IMPORT"], button2 = CANCEL,
    OnShow = function(self) local eb = PopupEditBox(self); if eb then eb:SetText("") end end,
    OnAccept = function(self) local eb = PopupEditBox(self); TryImport(eb and eb:GetText()) end,
    EditBoxOnEnterPressed = function(eb) TryImport(eb:GetText()); eb:GetParent():Hide() end,
    EditBoxOnEscapePressed = function(eb) eb:GetParent():Hide() end,
    timeout = 0, whileDead = true, hideOnEscape = true,
}

-- The Custom border knobs (ALL-69.5), on their own frame so the page can
-- hide them while another theme is picked. Returns the frame, its height
-- and the widgets to grey out while the module is off. The knobs are the
-- sticky settings' own (UI/StickySettings.lua). blk.ApplyWindow(on) greys
-- the ones that do nothing right now, as sticky settings do (on = the module
-- is on; off, the page has greyed everything already).
local function BuildCustomBlock(ct)
    local db = BigNoteBoxDB
    local Oracle = BNB.Oracle
    local id = BNB.SEARCH_CUSTOM_THEME
    local D = BNB.SEARCH_BACKDROP_DEFAULTS
    local blk = CreateFrame("Frame", nil, ct)
    local widgets, refresh = {}, {}
    local function Style() return BNB.GetSearchBackdrop(id) end
    local function Live()
        if Oracle.IsPreviewing() then Oracle.RefreshPreview() else Oracle.StartPreview() end
    end
    -- Every change redraws the bar, showing the preview if it is not up.
    local quiet = false   -- a refresh re-sets the sliders, which fire onChange
    local function Set(key, v)
        if quiet then return end
        if v == "" then v = nil end   -- the font list's "WoW default"
        db.oracleCustom = db.oracleCustom or {}
        db.oracleCustom[key] = v
        BNB.SearchStyleChanged()
        Live()
    end
    local y = 0

    local hdr = BNB.CreateSectionHeader(blk, L["CFG_ORACLE_HDR_CUSTOM"], y, CONTENT_W)
    y = y - hdr:GetStringHeight() - 4
    local desc = BNB.CreateSmallLabel(blk, L["CFG_ORACLE_CUSTOM_DESC"], y, CONTENT_W)
    desc:SetWordWrap(true)
    y = y - desc:GetStringHeight() - 8

    -- ── Styles ────────────────────────────────────────────────────────────────
    Label(blk, y, L["CFG_ORACLE_STYLE"])
    y = y - (ROW_H - 4)
    local styleEntries = {}   -- filled in place: the dropdown reads it on open
    local function FillStyles()
        wipe(styleEntries)
        for _, b in ipairs(BNB.SEARCH_BUILTIN_STYLES) do
            styleEntries[#styleEntries + 1] = { label = L[b.label], value = "builtin:" .. b.key }
        end
        for _, name in ipairs(BNB.GetSearchStyleNames()) do
            styleEntries[#styleEntries + 1] = { label = name, value = "user:" .. name }
        end
    end
    FillStyles()
    local RefreshAll   -- below
    local styleDD = BNB.CreateValueDropdown(blk, styleEntries, BNB.GetSearchStyleID(), function(v)
        if BNB.LoadSearchStyle(v) then RefreshAll(); Live() end
    end, CONTENT_W, DD_H)
    styleDD:SetPoint("TOPLEFT", blk, "TOPLEFT", 0, y)
    Tip(styleDD._dd or styleDD, L["CFG_ORACLE_STYLE_TIP"])
    widgets[#widgets + 1] = styleDD
    y = y - (DD_H + 6)

    local BTN_GAP = 6
    local btnW = math.floor((CONTENT_W - 3 * BTN_GAP) / 4)
    local delBtn
    local function StyleBtn(i, text, tip, fn)
        local b = BNB.CreateButton(nil, blk, text, btnW, DD_H)
        b:SetPoint("TOPLEFT", blk, "TOPLEFT", (i - 1) * (btnW + BTN_GAP), y)
        b:SetScript("OnClick", fn)
        Tip(b, tip)
        widgets[#widgets + 1] = b
        return b
    end
    StyleBtn(1, L["ORACLE_STYLE_BTN_SAVE"], L["ORACLE_STYLE_BTN_SAVE_TIP"], function()
        StaticPopup_Show("BNB_ORACLE_SAVE_STYLE")
    end)
    delBtn = StyleBtn(2, L["ORACLE_STYLE_BTN_DELETE"], L["ORACLE_STYLE_BTN_DELETE_TIP"], function()
        local name = BNB.GetSearchStyleID():match("^user:(.+)$")
        if name then StaticPopup_Show("BNB_ORACLE_DELETE_STYLE", name, nil, name) end
    end)
    StyleBtn(3, L["ORACLE_STYLE_BTN_EXPORT"], L["ORACLE_STYLE_BTN_EXPORT_TIP"], function()
        local str = BNB.ExportSearchStyle()
        if str then StaticPopup_Show("BNB_ORACLE_EXPORT_STYLE", nil, nil, str) end
    end)
    StyleBtn(4, L["ORACLE_STYLE_BTN_IMPORT"], L["ORACLE_STYLE_BTN_IMPORT_TIP"], function()
        StaticPopup_Show("BNB_ORACLE_IMPORT_STYLE")
    end)
    y = y - (DD_H + ROW_GAP + 10)

    -- ── Knobs: the sticky notes' own settings (Dukul, 2026-09-28) ───────────
    -- Several keys at once (the colour grid), one redraw.
    local function SetMany(t)
        if quiet then return end
        db.oracleCustom = db.oracleCustom or {}
        for k, v in pairs(t) do db.oracleCustom[k] = v end
        BNB.SearchStyleChanged()
        Live()
    end
    local greyTex, greyBorder = {}, {}   -- greyed: no texture / no border
    local function Header(text)
        y = y - 6
        local h = BNB.CreateSectionHeader(blk, text, y, CONTENT_W)
        y = y - h:GetStringHeight() - 6
    end
    local function Dropdown(label, entries, key, def, tip)
        local lbl = Label(blk, y, label)
        y = y - (ROW_H - 4)
        local dd = BNB.CreateValueDropdown(blk, entries, Style()[key] or def, function(v)
            Set(key, v)
            if key == "border" then blk.ApplyWindow(blk._on ~= false) end
        end, CONTENT_W, DD_H)
        dd:SetPoint("TOPLEFT", blk, "TOPLEFT", 0, y)
        if tip then Tip(dd._dd or dd, tip) end
        widgets[#widgets + 1] = dd
        refresh[#refresh + 1] = function() dd:SetSelected(Style()[key] or def) end
        y = y - (DD_H + ROW_GAP + 4)
        return dd, lbl
    end
    -- scale: the slider shows stored * scale (a 0..1 value as 0..100).
    -- unit: after the value ("%", " px"). Stacked layout with Reset.
    -- shift: added to the saved value for display (border brightness is saved
    -- -100..100 and shown 0..200 %, the one scale of ALL-123)
    local function Slider(label, mn, mx, key, scale, list, unit, shift)
        scale = scale or 1
        shift = shift or 0
        local function Shown() return math.floor(Style()[key] * scale + 0.5) + shift end
        local sl = BNB.CreateStackedSlider(blk, CONTENT_W, {
            label = label, min = mn, max = mx, value = Shown(),
            default = math.floor(D[key] * scale + 0.5) + shift,
            fmt = function(v) return v .. (unit or "") end,
            onChange = function(v) Set(key, (v - shift) / scale) end,
        })
        sl:SetPoint("TOPLEFT", blk, "TOPLEFT", 0, y)
        widgets[#widgets + 1] = sl
        if list then list[#list + 1] = sl end
        refresh[#refresh + 1] = function() sl:SetValue(Shown()) end
        y = y - (BNB.STACKED_SLIDER_H + ROW_GAP + 2)
        return sl
    end

    -- ── Background ────────────────────────────────────────────────────────────
    Header(L["CFG_ORACLE_BACKGROUND"])
    -- Palette + the colour picker tile in its last slot (the swatch above the
    -- grid went, Dukul 2026-10-06)
    y = BNB.BuildColorGrid(blk, y, CONTENT_W, function(r, g, b)
        SetMany({ bgR = r, bgG = g, bgB = b })
    end, function()
        local s = Style()
        return s.bgR, s.bgG, s.bgB
    end)
    y = y - 6

    -- Texture: [<] [name] [>], the name opens the sticky thumbnail grid.
    Label(blk, y, L["STICKY_BG_TEXTURE_LABEL"])
    y = y - (ROW_H - 4)
    local SBG, SBP = BNB.StickyBG, BNB.StickyBgPicker
    local ARW = 22
    local texPrev = BNB.CreateButton(nil, blk, "<", ARW, DD_H)
    local texBtn  = BNB.CreateButton(nil, blk, "", CONTENT_W - 2 * (ARW + 4), DD_H)
    local texNext = BNB.CreateButton(nil, blk, ">", ARW, DD_H)
    texPrev:SetPoint("TOPLEFT", blk, "TOPLEFT", 0, y)
    texBtn:SetPoint("LEFT", texPrev, "RIGHT", 4, 0)
    texNext:SetPoint("LEFT", texBtn, "RIGHT", 4, 0)
    for _, b in ipairs({ texPrev, texBtn, texNext }) do widgets[#widgets + 1] = b end
    y = y - (DD_H + ROW_GAP + 4)
    local SyncTex   -- below: greys Colorize / brightness without a texture
    local function TexKey() return SBG.Get(Style().bgTexture).key end
    local function SetTex(key)
        Set("bgTexture", key)
        texBtn:SetText(SBG.Label(key))
        SyncTex()
    end
    local function StepTex(d)
        local list, cur, idx = SBG.LIST, TexKey(), 1
        for i, e in ipairs(list) do if e.key == cur then idx = i; break end end
        SetTex(list[(idx - 1 + d) % #list + 1].key)
        if SBP then SBP.Refresh() end
    end
    -- What the grid's tiles copy: the bar with its results, as drawn now.
    local texHandlers = {
        cfg = Style,
        get = function() return Style().bgTexture end,
        set = SetTex,
        state = function()
            if not blk:IsVisible() then return nil end
            local s = Style()
            local edge = BNB.GetSearchEdgeFile(s)
            return { w = 500, h = 260, inset = s.borderOffset,
                     backdrop = { bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = edge,
                                  edgeSize = edge and s.edge or nil },
                     br = 1, bg = 1, bb = 1, ba = edge and 1 or 0 }
        end,
    }
    texPrev:SetScript("OnClick", function() StepTex(-1) end)
    texNext:SetScript("OnClick", function() StepTex(1) end)
    texBtn:SetScript("OnClick", function()
        if SBP then SBP.Open("oracle", _G["BigNoteBoxConfigFrame"] or blk, texHandlers) end
    end)
    -- Hooked, not set: the buttons keep their own hover look.
    for btn, key in pairs({ [texPrev] = "STICKY_BG_PREV", [texBtn] = "STICKY_BG_BROWSE_TIP",
                            [texNext] = "STICKY_BG_NEXT" }) do
        local text = L[key]
        btn:HookScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(text, 1, 1, 1)
            GameTooltip:Show()
        end)
        btn:HookScript("OnLeave", function() GameTooltip:Hide() end)
    end
    refresh[#refresh + 1] = function() texBtn:SetText(SBG.Label(Style().bgTexture)) end
    blk:HookScript("OnHide", function() if SBP and SBP.IsOpenFor("oracle") then SBP.Close() end end)

    Slider(L["CFG_ORACLE_COLORIZE"], 0, 100, "bgColorOpacity", 100, greyTex, "%")
    Slider(L["CFG_ORACLE_TEX_BRIGHT"], -100, 100, "bgBrightness", 100, greyTex, "%")
    Slider(L["CFG_ORACLE_BG_OPACITY"], 0, 100, "alpha", 100, nil, "%")

    -- ── Border ────────────────────────────────────────────────────────────────
    Header(L["CFG_ORACLE_BORDER"])
    local borders = {
        { label = L["CFG_ORACLE_BORDER_NONE"], value = "None" },
        { label = L["CFG_ORACLE_BORDER_DEFAULT"], value = "Default" },
    }
    for _, e in ipairs(LSMList("border")) do
        if e.value ~= "None" then borders[#borders + 1] = e end
    end
    Dropdown(L["CFG_ORACLE_BORDER_STYLE"], borders, "border", D.border)
    Slider(L["CFG_ORACLE_BORDER_THICK"], 1, 200, "borderScale", 1, greyBorder, "%")
    Slider(L["CFG_ORACLE_BORDER_OFFSET"], 0, 12, "borderOffset", 1, nil, " px")
    Slider(L["CFG_ORACLE_BORDER_BRIGHT"], BNB.BorderBright.MIN, BNB.BorderBright.MAX, "borderLight", 1, greyBorder, "%", 100)

    -- ── Text and results ──────────────────────────────────────────────────────
    Header(L["CFG_ORACLE_HDR_TEXT"])
    local hlSw = ColourSwatch(blk, 0, y, L["CFG_ORACLE_COL_HL"], function()
        return Style().highlight or { BNB.GetSearchHighlight(id) }
    end, function(r, g, b, a)
        Set("highlight", { r, g, b, a })
    end)
    widgets[#widgets + 1] = hlSw
    refresh[#refresh + 1] = function() hlSw:Update() end
    y = y - (SWATCH + ROW_GAP + 8)
    Dropdown(L["CFG_ORACLE_FONT"], FontEntries(), "font", "", L["CFG_ORACLE_FONT_TIP"])
    Slider(L["CFG_ORACLE_FONT_SIZE"], 10, 24, "fontSize", 1)

    local reset = BNB.CreateButton(nil, blk, L["CFG_ORACLE_RESET_CUSTOM"], 150, DD_H)
    reset:SetPoint("TOPLEFT", blk, "TOPLEFT", 0, y)
    Tip(reset, L["CFG_ORACLE_RESET_CUSTOM_TIP"])
    reset:SetScript("OnClick", function()
        BNB.LoadSearchStyle("builtin:default")
        RefreshAll()
        Live()
    end)
    widgets[#widgets + 1] = reset
    y = y - (DD_H + ROW_GAP + 6)

    -- Greyed like sticky settings: Colorize and texture brightness without a
    -- texture, thickness and brightness without a border; Delete only for
    -- your own styles. on = the module is on (off, the page greyed it all).
    local function Grey(list, off)
        for _, w in ipairs(list) do
            w:SetAlpha(off and 0.35 or 1)
            local t = w._dd or w.Slider or w
            if t.SetEnabled then t:SetEnabled(not off) end
        end
    end
    function SyncTex()
        if blk._on == false then return end
        Grey(greyTex, not SBG.Get(Style().bgTexture).file)
    end
    function blk.ApplyWindow(on)
        blk._on = on
        if not on then return end
        SyncTex()
        Grey(greyBorder, Style().border == "None")
        local own = BNB.GetSearchStyleID():match("^user:") ~= nil
        delBtn:SetEnabled(own)
        delBtn:SetAlpha(own and 1 or 0.35)
    end

    function RefreshAll()
        FillStyles()
        styleDD:SetSelected(BNB.GetSearchStyleID())
        quiet = true
        for _, fn in ipairs(refresh) do pcall(fn) end
        quiet = false
        blk.ApplyWindow(blk._on ~= false)
    end
    styleUI = RefreshAll
    blk:HookScript("OnShow", RefreshAll)

    blk:SetHeight(-y)
    return blk, -y, widgets
end

local function BuildOraclePage(sf, ct, y, page)
    local db = BigNoteBoxDB
    local Oracle = BNB.Oracle
    local OS = BNB.OracleSearch
    local widgets = {}   -- greyed while the module is off

    -- ── On / off ──────────────────────────────────────────────────────────────
    local enableCb = CreateFrame("CheckButton", nil, ct, "UICheckButtonTemplate")
    BNB.LabelHit(enableCb)   -- the tooltip and click reach over its label too
    enableCb:SetSize(24, 24)
    enableCb:SetPoint("TOPLEFT", ct, "TOPLEFT", -2, y + 2)
    enableCb:SetChecked(db.oracleEnabled ~= false)
    Tip(enableCb, L["CFG_ORACLE_ENABLE_TIP"])
    page.enableCb = enableCb   -- twin on the Modules overview row
    local enableLbl = ct:CreateFontString(nil, "OVERLAY", "BNBFontNormal")
    enableLbl:SetPoint("LEFT", enableCb, "RIGHT", 4, 0)
    enableLbl:SetPoint("RIGHT", ct, "RIGHT", 0, 0)
    enableLbl:SetJustifyH("LEFT"); enableLbl:SetHeight(ROW_H)
    enableLbl:SetText(L["CFG_ORACLE_ENABLE_LABEL"])
    y = y - (ROW_H + ROW_GAP)

    local rcHint = BNB.CreateSmallLabel(ct, L["CFG_ORACLE_RIGHTCLICK_HINT"], y, CONTENT_W)
    y = y - rcHint:GetStringHeight() - 10

    y = K.MakeKeybindPair(ct, y, {
        { label = L["CFG_KB_ORACLE"], action = "BIGNOTEBOXORACLE",
          defaultKey = "CTRL-SPACE", verb = L["CFG_KB_DESC_ORACLE"] },
    })

    -- ── Look ──────────────────────────────────────────────────────────────────
    y = AddRule(ct, y) - 4
    y = AddHeader(ct, y, L["CFG_ORACLE_HDR_LOOK"])

    Label(ct, y, L["CFG_ORACLE_THEME_LABEL"])
    y = y - (ROW_H - 4)
    -- "" = follow the character's faction (oracleTheme nil). The Custom
    -- border theme comes last (ALL-69.5).
    local CUSTOM = BNB.SEARCH_CUSTOM_THEME
    local themes = { { label = string.format(L["CFG_ORACLE_THEME_FACTION_FMT"],
        ThemeName(Oracle.FactionTheme())), value = "" } }
    for _, id in ipairs(BNB.SEARCH_THEME_ORDER) do
        if not BNB.SEARCH_THEMES[id].hidden and id ~= CUSTOM then
            themes[#themes + 1] = { label = ThemeName(id), value = id }
        end
    end
    if BNB.SEARCH_THEMES[CUSTOM] then themes[#themes + 1] = { label = ThemeName(CUSTOM), value = CUSTOM } end
    local Relayout   -- set below: shows the custom block for the Custom theme
    local themeDD = BNB.CreateValueDropdown(ct, themes, db.oracleTheme or "", function(v)
        db.oracleTheme = (v ~= "") and v or nil
        Oracle.RefreshPreview()
        Relayout()
    end, CONTENT_W, DD_H)
    themeDD:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
    widgets[#widgets + 1] = themeDD
    y = y - (DD_H + ROW_GAP + 4)

    -- The custom knobs sit here, and the rest of the page on a frame of its
    -- own under them that moves up while they are hidden.
    local top = ct
    local customY = y
    local custom, customH, customWidgets = BuildCustomBlock(top)
    custom:SetPoint("TOPLEFT", top, "TOPLEFT", 0, customY)
    custom:SetPoint("TOPRIGHT", top, "TOPRIGHT", 0, customY)
    for _, w in ipairs(customWidgets) do widgets[#widgets + 1] = w end
    local lower = CreateFrame("Frame", nil, top)
    lower:SetPoint("TOPRIGHT", top, "TOPRIGHT", 0, 0)
    ct, y = lower, 0

    -- ── Results (ALL-69.6, every theme) ───────────────────────────────────────
    y = AddRule(ct, y) - 4
    y = AddHeader(ct, y, L["CFG_ORACLE_HDR_RESULTS"])

    local maxSl = BNB.CreateStackedSlider(ct, CONTENT_W, {
        label = L["CFG_ORACLE_MAX_ROWS"], min = 1, max = Oracle.MAX_ROWS,
        value = db.oracleMaxResults or Oracle.MAX_ROWS, default = Oracle.MAX_ROWS,
        onChange = function(v)
            db.oracleMaxResults = (v ~= Oracle.MAX_ROWS) and v or nil
            Oracle.RefreshPreview()
        end,
    })
    maxSl:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
    widgets[#widgets + 1] = maxSl
    y = y - (BNB.STACKED_SLIDER_H + ROW_GAP + 2)

    -- Sizes: nil saved at the default. A size slider is greyed while its
    -- Show box is off (SyncResults, also after the module switch).
    local RS = Oracle.RESULT_SIZES
    local function SizeSlider(s, label)
        local sl = BNB.CreateStackedSlider(ct, CONTENT_W, {
            label = label, min = s.min, max = s.max, default = s.def,
            value = db[s.key] or s.def, fmt = function(v) return v .. " px" end,
            onChange = function(v)
                db[s.key] = (v ~= s.def) and v or nil
                Oracle.RefreshPreview()
            end,
        })
        sl:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
        widgets[#widgets + 1] = sl
        y = y - (BNB.STACKED_SLIDER_H + ROW_GAP + 2)
        return sl
    end
    SizeSlider(RS.title, L["CFG_ORACLE_TITLE_SIZE"])
    SizeSlider(RS.small, L["CFG_ORACLE_PREVIEW_SIZE"])

    local SyncResults
    local function ShowCheck(s, label, tip)
        local cb
        y, cb = AddCheck(ct, y, label,
            function() return db[s.show] ~= false end,
            function(v)
                -- Explicit if: "x and false or nil" is always nil in Lua (ALL-334)
                if v then db[s.show] = nil else db[s.show] = false end
                SyncResults()
                Oracle.RefreshPreview()
            end, tip)
        widgets[#widgets + 1] = cb
    end
    ShowCheck(RS.icon, L["CFG_ORACLE_SHOW_ICONS"], L["CFG_ORACLE_SHOW_ICONS_TIP"])
    local iconSl = SizeSlider(RS.icon, L["CFG_ORACLE_ICON_SIZE"])
    ShowCheck(RS.badge, L["CFG_ORACLE_SHOW_BADGES"], L["CFG_ORACLE_SHOW_BADGES_TIP"])
    local badgeSl = SizeSlider(RS.badge, L["CFG_ORACLE_BADGE_SIZE"])

    function SyncResults()
        local moduleOn = db.oracleEnabled ~= false
        for _, pair in ipairs({ { iconSl, RS.icon }, { badgeSl, RS.badge } }) do
            local on = moduleOn and db[pair[2].show] ~= false
            local w = pair[1]
            w:SetAlpha(on and 1 or 0.35)
            local t = w.Slider or w
            if t.SetEnabled then t:SetEnabled(on) end
        end
    end

    -- ── Position ──────────────────────────────────────────────────────────────
    y = AddRule(ct, y) - 4
    y = AddHeader(ct, y, L["CFG_ORACLE_HDR_POSITION"])

    local moveHint = BNB.CreateSmallLabel(ct, L["CFG_ORACLE_MOVE_HINT"], y, CONTENT_W)
    moveHint:SetWordWrap(true)
    y = y - moveHint:GetStringHeight() - 6

    local resetBtn = BNB.CreateButton(nil, ct, L["CFG_ORACLE_RESET_BTN"], 150, DD_H)
    resetBtn:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
    resetBtn:SetScript("OnClick", function() Oracle.ResetPosition() end)
    Tip(resetBtn, L["CFG_ORACLE_RESET_TIP"])
    widgets[#widgets + 1] = resetBtn
    y = y - (DD_H + ROW_GAP + 4)

    -- The page shows the bar in the main window's place (Dukul, 2026-09-28):
    -- opening it hides the main window (Settings stays) and starts the
    -- preview; leaving it (back, Esc, another tab, Settings closed) ends the
    -- preview and brings the main window back if the page hid it.
    -- BNB._keepSettingsOpen: while this page is open, a main window close
    -- never takes Settings with it (CloseCompanionWindows, MainWindow.lua).
    local hidMain = false
    sf:HookScript("OnShow", function()
        BNB._keepSettingsOpen = true
        hidMain = BNB.HideMainWindowKeepSettings() or hidMain
        Oracle.StartPreview()
    end)
    -- Leaving by Esc left the preview up while the back button did not
    -- (Dukul, 2026-09-28): the main window came back inside the same key
    -- press. So the main window reopens a frame later, and the preview is
    -- checked again then.
    sf:HookScript("OnHide", function()
        BNB._keepSettingsOpen = nil
        Oracle.EndPreview()
        local reopen = hidMain
        hidMain = false
        C_Timer.After(0, function()
            if sf:IsVisible() then return end   -- back on the page already
            Oracle.EndPreview()
            if reopen then BNB.OpenMainWindow() end
        end)
    end)

    -- ── Behaviour ─────────────────────────────────────────────────────────────
    y = AddRule(ct, y) - 4
    y = AddHeader(ct, y, L["CFG_ORACLE_HDR_BEHAVIOUR"])

    Label(ct, y, L["CFG_ORACLE_OPEN_MODE_LABEL"])
    y = y - (ROW_H - 4)
    local modeDD = BNB.CreateValueDropdown(ct, {
        { label = L["CFG_ORACLE_OPEN_JUST"],  value = "open"  },
        { label = L["CFG_ORACLE_OPEN_PLAIN"], value = "plain" },
        { label = L["CFG_ORACLE_OPEN_ALL"],   value = "all"   },
    }, db.oracleOpenMode or "plain", function(v)
        db.oracleOpenMode = (v ~= "plain") and v or nil
    end, CONTENT_W, DD_H)
    modeDD:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
    Tip(modeDD._dd or modeDD, L["CFG_ORACLE_OPEN_MODE_TIP"])
    widgets[#widgets + 1] = modeDD
    y = y - (DD_H + ROW_GAP + 4)

    local closeCb
    y, closeCb = AddCheck(ct, y, L["CFG_ORACLE_CLOSE_AFTER"],
        function() return db.oracleKeepOpen ~= true end,
        function(v) db.oracleKeepOpen = (not v) or nil end,
        L["CFG_ORACLE_CLOSE_AFTER_TIP"])
    widgets[#widgets + 1] = closeCb

    -- Ranking: one level per boost, nil = OracleSearch's default.
    y = y - 4
    local rankHdr = BNB.CreateSectionHeader(ct, L["CFG_ORACLE_HDR_RANKING"], y, CONTENT_W)
    y = y - rankHdr:GetStringHeight() - 4
    local rankDesc = BNB.CreateSmallLabel(ct, L["CFG_ORACLE_RANKING_DESC"], y, CONTENT_W)
    rankDesc:SetWordWrap(true)
    y = y - rankDesc:GetStringHeight() - 8

    local levels = {}
    for _, lvl in ipairs(OS.WEIGHT_LEVELS) do
        levels[#levels + 1] = { label = L[LEVEL_KEY[lvl]], value = lvl }
    end
    local weightDDs = {}
    local alarmRow   -- { dd, lbl }: greyed while the Alarms module is off
    for _, w in ipairs(WEIGHTS) do
        local key = w.key
        local lbl = ct:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        lbl:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y - 4)
        lbl:SetWidth(CONTENT_W - WEIGHT_W - 8); lbl:SetJustifyH("LEFT")
        lbl:SetWordWrap(false)
        lbl:SetText(L[w.label])
        local cur = (db.oracleWeights and db.oracleWeights[key]) or OS.WEIGHT_DEFAULTS[key]
        local dd = BNB.CreateValueDropdown(ct, levels, cur, function(v)
            local def = OS.WEIGHT_DEFAULTS[key]
            db.oracleWeights = db.oracleWeights or {}
            db.oracleWeights[key] = (v ~= def) and v or nil
            if next(db.oracleWeights) == nil then db.oracleWeights = nil end
        end, WEIGHT_W, DD_H)
        dd:SetPoint("TOPLEFT", ct, "TOPLEFT", CONTENT_W - WEIGHT_W, y)
        widgets[#widgets + 1] = dd
        weightDDs[key] = dd
        if key == "alarm" then   -- no effect while the Alarms module is off (ALL-343)
            alarmRow = { dd = dd, lbl = lbl }
        end
        y = y - (DD_H + 4)
    end
    y = y - 4

    local resetW = BNB.CreateButton(nil, ct, L["CFG_ORACLE_RESET_WEIGHTS"], 150, DD_H)
    resetW:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
    resetW:SetScript("OnClick", function()
        db.oracleWeights = nil
        for key, dd in pairs(weightDDs) do dd:SetSelected(OS.WEIGHT_DEFAULTS[key]) end
    end)
    widgets[#widgets + 1] = resetW
    y = y - (DD_H + ROW_GAP)

    -- ── Enable state ──────────────────────────────────────────────────────────
    local function ApplyEnabled(on)
        for _, w in ipairs(widgets) do
            w:SetAlpha(on and 1 or 0.35)
            local t = w._dd or w.Slider or w   -- value dropdown, slider, button
            if t.SetEnabled then t:SetEnabled(on) end
        end
        if alarmRow then
            local aOn = on and BNB.AlarmsEnabled()
            alarmRow.dd:SetAlpha(aOn and 1 or 0.35); alarmRow.lbl:SetAlpha(aOn and 1 or 0.35)
            local t = alarmRow.dd._dd or alarmRow.dd
            if t.SetEnabled then t:SetEnabled(aOn) end
        end
        SyncResults()
    end
    -- The Alarms switch may have changed on its own page since
    sf:HookScript("OnShow", function() ApplyEnabled(db.oracleEnabled ~= false) end)
    enableCb:SetScript("OnClick", function(self)
        if self:GetChecked() then
            db.oracleEnabled = nil
        else
            db.oracleEnabled = false
            -- The page's preview stays up (it works with the module off).
            if not Oracle.IsPreviewing() then Oracle.Close() end
        end
        ApplyEnabled(db.oracleEnabled ~= false)
        custom.ApplyWindow(db.oracleEnabled ~= false)
    end)
    ApplyEnabled(db.oracleEnabled ~= false)
    custom.ApplyWindow(db.oracleEnabled ~= false)

    local lowerH = math.abs(y)
    lower:SetHeight(lowerH)
    function Relayout()
        local on = db.oracleTheme == CUSTOM
        custom:SetShown(on)
        local yLower = customY - (on and customH or 0)
        lower:ClearAllPoints()
        lower:SetPoint("TOPLEFT", top, "TOPLEFT", 0, yLower)
        lower:SetPoint("TOPRIGHT", top, "TOPRIGHT", 0, yLower)
        sf:FinaliseHeight(math.abs(yLower) + lowerH + 12)
    end
    Relayout()
end

K.BuildOraclePage = BuildOraclePage

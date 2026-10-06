-- SidebarTopTest.lua
-- Test for ALL-248: the character sidebar as long tabs along the top of the main
-- window (Dukul, 2026-10-04). /bnbtabs toggles it. Dev only, never packaged.
--
-- While the panel is open, a test strip hangs on top of the real main window
-- (open it first), built from the real sidebar data: All, Global, pinned and
-- recent characters, note counts, icons. Nothing in BigNoteBox is changed.
--
-- Normal look, bottom to top (Dukul): tab art (retail/forever), icon with a plain
-- border + "Name (X)", active glow (active tab only), hover (inactive tabs only).
-- Skin look: the rich-note bottom tabs' box (UI/NoteEditor.lua MakeSkinTab)
-- turned upside down: no bottom border, tucked down under the window.
--
-- Every number is a slider; values are saved per client + look in
-- BigNoteBoxDevDB.topTabs. Export puts the current set in a copy box.

local ART = "Interface\\AddOns\\BigNoteBox_Dev\\Test-Graphics\\Sidebar\\sb-top-tab-"
local AW = 256      -- art canvas width (all four files are 256x64)
local AH = 64
-- 5-slice cuts in art px: both caps and the bottom-centre ornament keep their
-- shape, the two runs between them stretch
local CAP, ORN_L, ORN_R = 24, 114, 142
local GREEN = { 0.40, 0.85, 0.40 }   -- the sidebar's active colour (UI/Sidebar.lua)

local DEFAULTS = {
    tabH = 32, tabW = 170, minW = 90, gap = 0, x = 8, y = -4,
    iconSz = 18, iconX = 13, iconY = -0.5, border = 1, textGap = 5, textY = -0.5,
    rightPad = 14, activeA = 1, hoverA = 0.5, dim = 0.6, skinH = 30, skinTuck = 6,
    slice = true, fill = false, under = false, hoverAdd = false,
    borderCol = 1, font = 1, count = 1, tint = 2,   -- tint 2 = BNB green on active and hover (Dukul)
}

-- Cycled choices: { label, value }
local BORDER_COLS = {
    { "black", { 0, 0, 0 } }, { "grey", { 0.35, 0.35, 0.35 } },
    { "gold", { 0.72, 0.58, 0.25 } }, { "class", "class" },
}
local FONTS = {
    { "small white", "GameFontHighlightSmall" }, { "white", "GameFontHighlight" },
    { "small gold", "GameFontNormalSmall" }, { "gold", "GameFontNormal" },
}
local COUNTS = { { "(12)", "short" }, { "(12 notes)", "long" }, { "none", "none" } }
local TINTS  = { { "white", { 1, 1, 1 } }, { "green", GREEN }, { "class", "class" } }
local ARTS   = { { "auto", nil }, { "retail", "retail" }, { "forever", "forever" } }
local MODES  = { { "follow skin mode", nil }, { "normal", "normal" }, { "skin", "skin" } }

local SKIN_BOX = { bgFile = "Interface\\Buttons\\White8x8",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 14,
    insets = { left = 3, right = 3, top = 3, bottom = 3 } }
local STRATA_BELOW = { MEDIUM = "LOW", HIGH = "MEDIUM", DIALOG = "HIGH",
    FULLSCREEN = "DIALOG", FULLSCREEN_DIALOG = "FULLSCREEN", TOOLTIP = "FULLSCREEN_DIALOG" }

local panel, strip
local artIdx, modeIdx = 1, 1          -- session-only overrides (not saved)
local longName = false
local activeKey = "all"
local liveTabs, previewTabs = {}, {}
local sliders = {}
local statusFs

local function BNB() return BigNoteBox end
local function L(k) return BigNoteBox.L[k] or k end

local function Mode()
    local m = MODES[modeIdx][2]
    if m then return m end
    return (BigNoteBoxDB and BigNoteBoxDB.skinMode) and "skin" or "normal"
end
local function ArtName()
    return ARTS[artIdx][2] or (BNB().IsForever and "forever" or "retail")
end
-- The saved set for this client + look
local function P()
    BigNoteBoxDevDB = BigNoteBoxDevDB or {}
    BigNoteBoxDevDB.topTabs = BigNoteBoxDevDB.topTabs or {}
    local key = (BNB().IsForever and "forever" or "retail") .. "_" .. Mode()
    local p = BigNoteBoxDevDB.topTabs[key]
    if not p then p = {}; BigNoteBoxDevDB.topTabs[key] = p end
    for k, v in pairs(DEFAULTS) do if p[k] == nil then p[k] = v end end
    return p, key
end

--------------------------------------------------------------------------------
-- Data: the same keys, icons, counts and tooltip as UI/Sidebar.lua
--------------------------------------------------------------------------------
local function CharRec(key)
    if key == "char:__long" then
        return { name = "Thalassiandreamweaver", level = 80, class = "DEMONHUNTER", guild = "Very Long Guild Name" }
    end
    local ck = key:match("^char:(.+)$")
    return ck and BigNoteBoxDB and BigNoteBoxDB.knownChars and BigNoteBoxDB.knownChars[ck], ck
end

local function VisibleKeys()
    local keys = { "all", "global" }
    if longName then keys[#keys + 1] = "char:__long" end
    local pinned, recent = {}, {}
    for ck, rec in pairs(BigNoteBoxDB and BigNoteBoxDB.knownChars or {}) do
        if not rec.slotHidden then
            local t = rec.slotPinned and pinned or recent
            t[#t + 1] = { key = "char:" .. ck, rec = rec }
        end
    end
    table.sort(pinned, function(a, b) return (a.rec.pinnedOrder or 99) < (b.rec.pinnedOrder or 99) end)
    table.sort(recent, function(a, b) return (a.rec.lastSeen or 0) > (b.rec.lastSeen or 0) end)
    for i = 1, math.min(#pinned, 5) do keys[#keys + 1] = pinned[i].key end
    for _, r in ipairs(recent) do keys[#keys + 1] = r.key end
    return keys
end

local function CountFor(key)
    if key == "char:__long" then return 1234 end
    local ndb = BNB().NotesDB and BNB().NotesDB()
    local n = 0
    for _, note in pairs(ndb and ndb.notes or {}) do
        if key == "all" or (key == "global" and (note.scope == "global" or note.scope == nil))
            or note.scope == key then n = n + 1 end
    end
    return n
end

local function NameFor(key)
    if key == "all" then return L("SB_ALL_NOTES") end
    if key == "global" then return L("SB_GLOBAL_NOTES") end
    local rec, ck = CharRec(key)
    return rec and rec.name or ck or key
end

local function IconFor(key)
    if key == "char:__long" then return "Interface\\Icons\\ClassIcon_DemonHunter" end
    return BNB().Sidebar.IconForKey(key)
end

local function ClassColor(key)
    local rec = key:find("^char:") and CharRec(key)
    local cls = rec and rec.class and rec.class:upper():gsub(" ", "")
    local c = cls and RAID_CLASS_COLORS and RAID_CLASS_COLORS[cls]
    if c then return { c.r, c.g, c.b } end
    return { 1, 1, 1 }
end

local function ShowTip(btn, key)
    GameTooltip:SetOwner(btn, "ANCHOR_TOP")
    if key == "all" or key == "global" then
        GameTooltip:AddLine(NameFor(key), 1, 1, 1)
        GameTooltip:AddLine(L(key == "all" and "SB_ALL_NOTES_TIP" or "SB_GLOBAL_NOTES_TIP"), 0.8, 0.8, 0.8, true)
    else
        local rec, ck = CharRec(key)
        local c = ClassColor(key)
        GameTooltip:AddLine(rec and rec.name or ck, c[1], c[2], c[3])
        local lines = {}
        if rec and rec.level then lines[#lines + 1] = string.format(L("SB_LEVEL_FMT"), rec.level) end
        if rec and rec.class then lines[#lines + 1] = rec.class:sub(1, 1):upper() .. rec.class:sub(2):lower() end
        if rec and rec.guild then lines[#lines + 1] = "<" .. rec.guild .. ">" end
        if #lines > 0 then GameTooltip:AddLine(table.concat(lines, "  |  "), 0.8, 0.8, 0.8, true) end
        if ck and ck ~= (rec and rec.name) then GameTooltip:AddLine(ck, 0.6, 0.6, 0.6) end
    end
    local n = CountFor(key)
    if n > 0 then
        GameTooltip:AddLine(n == 1 and L("SB_NOTE_COUNT_ONE") or string.format(L("SB_NOTE_COUNT_N_FMT"), n), 0.6, 0.9, 0.6)
    end
    GameTooltip:Show()
end

-- Stand-in for the sidebar's right-click menu (ShowSlotContextMenu is local to
-- UI/Sidebar.lua): same entries, a chat line instead of the action
local function ShowMenu(btn, key)
    local rec = CharRec(key)
    if not rec then return end
    local function Say(what) return function() print("|cffff9900[top tabs test]|r " .. what .. ": " .. NameFor(key)) end end
    BNB().ContextMenu.Open(btn, function(root)
        local pin = rec.slotPinned and L("SB_UNPIN") or L("SB_PIN_TO_TOP")
        root:CreateButton(pin, Say(pin))
        root:CreateButton(L("SB_HIDE_FROM_SIDEBAR"), Say(L("SB_HIDE_FROM_SIDEBAR")))
        root:CreateButton(L("SB_CHANGE_ICON"), Say(L("SB_CHANGE_ICON")))
        if rec.slotIcon then root:CreateButton(L("SB_RESET_ICON"), Say(L("SB_RESET_ICON"))) end
    end)
end

--------------------------------------------------------------------------------
-- One tab
--------------------------------------------------------------------------------
-- Five textures for one art file (caps, runs, ornament), placed by LayoutSlices
local function NewSlices(btn, layer, sub)
    local t = {}
    for i = 1, 5 do t[i] = btn:CreateTexture(nil, layer, nil, sub) end
    return t
end

local function LayoutSlices(set, btn, file, w, h, slice)
    local k = h / AH
    local capW, ornW = CAP * k, (ORN_R - ORN_L) * k
    local runW = (w - 2 * capW - ornW) / 2
    for _, t in ipairs(set) do t:SetTexture(file); t:ClearAllPoints() end
    if not slice or runW < 1 then
        set[1]:SetPoint("TOPLEFT", btn, "TOPLEFT", 0, 0)
        set[1]:SetSize(w, h); set[1]:SetTexCoord(0, 1, 0, 1); set[1]:Show()
        for i = 2, 5 do set[i]:Hide() end
        return
    end
    -- { art x0, art x1, drawn width }
    local cuts = { { 0, CAP, capW }, { CAP, ORN_L, runW }, { ORN_L, ORN_R, ornW },
                   { ORN_R, AW - CAP, runW }, { AW - CAP, AW, capW } }
    local x = 0
    for i, c in ipairs(cuts) do
        local t = set[i]
        t:SetTexCoord(c[1] / AW, c[2] / AW, 0, 1)
        t:SetPoint("TOPLEFT", btn, "TOPLEFT", x, 0)
        t:SetSize(c[3], h)
        t:Show()
        x = x + c[3]
    end
end

local function SetSlicesShown(set, on, r, g, b, a)
    for _, t in ipairs(set) do
        if on and t:GetTexture() then t:SetVertexColor(r or 1, g or 1, b or 1, a or 1) end
        t:SetAlpha(on and 1 or 0)
    end
end

-- Full width of a FontString's text, whatever width it was given
local function TextW(fs)
    if fs.GetUnboundedStringWidth then return math.ceil(fs:GetUnboundedStringWidth()) end
    fs:SetWidth(0)
    return math.ceil(fs:GetStringWidth())
end

local function MakeTab(parent)
    local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
    btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    btn.base   = NewSlices(btn, "BACKGROUND", 0)
    btn.active = NewSlices(btn, "OVERLAY", 0)   -- over icon and name (Dukul)
    btn.hover  = NewSlices(btn, "OVERLAY", 1)
    btn.edge = btn:CreateTexture(nil, "ARTWORK", nil, 0)   -- the icon's plain border
    btn.icon = btn:CreateTexture(nil, "ARTWORK", nil, 1)
    btn.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    btn.name = btn:CreateFontString(nil, "ARTWORK")
    btn.name:SetDrawLayer("ARTWORK", 3)
    btn.name:SetWordWrap(false)
    btn.name:SetJustifyH("LEFT")
    btn.cnt = btn:CreateFontString(nil, "ARTWORK")
    btn.cnt:SetDrawLayer("ARTWORK", 3)
    btn.cnt:SetWordWrap(false)
    btn.hl = btn:CreateTexture(nil, "ARTWORK", nil, 2)   -- skin hover
    btn.hl:SetColorTexture(1, 1, 1, 0.10)
    btn:SetScript("OnEnter", function(self)
        self._hover = true; self:Paint()
        if self._key then ShowTip(self, self._key) end
    end)
    btn:SetScript("OnLeave", function(self)
        self._hover = false; self:Paint()
        GameTooltip:Hide()
    end)
    btn:SetScript("OnClick", function(self, mb)
        if not self._key or self._force then return end
        if mb == "RightButton" then ShowMenu(self, self._key); return end
        activeKey = self._key
        local SB = BNB().Sidebar
        if SB and SB.IsEnabled() and not self._key:find("__long") then SB.SetActive(self._key) end
        for _, t in ipairs(liveTabs) do t:Paint() end
    end)

    function btn:IsActive()
        if self._force then return self._force == "active" end
        return self._key == activeKey
    end
    function btn:IsHover()
        if self._force then return self._force == "hover" end
        return self._hover
    end

    function btn:Paint()
        local p = P()
        local act, hov = self:IsActive(), self:IsHover() and not self:IsActive()
        local c = ClassColor(self._key or "")
        if self._mode == "skin" then
            local pr = BNB().GetSkinPreset()
            local br, bg_, bb = BNB().SkinBorderOf(pr)
            local m = act and 1 or 0.6
            self:SetBackdropColor(math.min(1, pr.r + pr.lift * 1.5) * m, math.min(1, pr.g + pr.lift * 1.5) * m,
                math.min(1, pr.b + pr.lift * 1.5) * m, 0.97)
            self:SetBackdropBorderColor(br, bg_, bb, 1)
            self.hl:SetShown(hov)
        else
            self.hl:Hide()
            SetSlicesShown(self.base, true)
            local tint = TINTS[p.tint][2]
            tint = tint == "class" and c or tint
            SetSlicesShown(self.active, act, tint[1], tint[2], tint[3], p.activeA)
            for _, t in ipairs(self.hover) do t:SetBlendMode(p.hoverAdd and "ADD" or "BLEND") end
            SetSlicesShown(self.hover, hov, tint[1], tint[2], tint[3], p.hoverA)
        end
        -- Inactive: icon desaturated and the text dimmed, as the sidebar does
        local lit = act or hov
        local v = lit and 1 or p.dim
        self.icon:SetDesaturated(not lit)
        self.icon:SetVertexColor(v, v, v)
        local bc = BORDER_COLS[p.borderCol][2]
        bc = bc == "class" and c or bc
        self.edge:SetColorTexture(bc[1] * v, bc[2] * v, bc[3] * v, 1)
        self.name:SetAlpha(lit and 1 or math.max(0.35, p.dim))
        self.cnt:SetAlpha(lit and 1 or math.max(0.35, p.dim))
    end

    -- Size and fill for a key at width w in mode ("normal"/"skin")
    function btn:Fill(key, w, mode)
        local p = P()
        self._key, self._mode = key, mode
        local h = mode == "skin" and p.skinH or p.tabH
        self:SetSize(w, h)
        if mode == "skin" then
            for _, set in ipairs({ self.base, self.active, self.hover }) do SetSlicesShown(set, false) end
            if not self._hasBox then
                self:SetBackdrop(SKIN_BOX)
                -- No bottom border: the tab runs down under the window
                for _, k in ipairs({ "BottomEdge", "BottomLeftCorner", "BottomRightCorner" }) do
                    if self[k] then self[k]:Hide() end
                end
                if self.LeftEdge and self.RightEdge then
                    self.LeftEdge:SetPoint("BOTTOMLEFT", self, "BOTTOMLEFT")
                    self.RightEdge:SetPoint("BOTTOMRIGHT", self, "BOTTOMRIGHT")
                end
                self._hasBox = true
            end
            self.hl:ClearAllPoints()
            self.hl:SetPoint("TOPLEFT", 3, -3); self.hl:SetPoint("BOTTOMRIGHT", -3, 3)
        else
            if self._hasBox then self:ClearBackdrop(); self._hasBox = false end
            local file = ART .. ArtName()
            LayoutSlices(self.base, self, file, w, h, p.slice)
            LayoutSlices(self.active, self, ART .. "active", w, h, p.slice)
            LayoutSlices(self.hover, self, ART .. "hover", w, h, p.slice)
        end
        -- Icon + plain border; skin centres it in the part below... above the tuck
        local yMid = mode == "skin" and (p.skinTuck / 2) or 0
        local bd = p.border
        self.edge:ClearAllPoints()
        self.edge:SetSize(p.iconSz + 2 * bd, p.iconSz + 2 * bd)
        self.edge:SetPoint("LEFT", self, "LEFT", p.iconX, p.iconY + yMid)
        self.edge:SetShown(bd > 0)
        self.icon:ClearAllPoints()
        self.icon:SetSize(p.iconSz, p.iconSz)
        self.icon:SetPoint("CENTER", self.edge, "CENTER")
        self.icon:SetTexture(IconFor(key))
        -- Name, truncated with "..." so the count always shows
        local font = FONTS[p.font][2]
        self.name:SetFontObject(font); self.cnt:SetFontObject(font)
        local n = CountFor(key)
        local cm = COUNTS[p.count][2]
        local ctext = cm == "none" and "" or cm == "long"
            and " (" .. (n == 1 and L("SB_NOTE_COUNT_ONE") or string.format(L("SB_NOTE_COUNT_N_FMT"), n)) .. ")"
            or  " (" .. n .. ")"
        self.cnt:SetText(ctext)
        self.name:SetText(NameFor(key))
        local left = p.iconX + p.iconSz + 2 * bd + p.textGap
        local avail = w - left - p.rightPad
        local cw = ctext == "" and 0 or TextW(self.cnt)
        local nw = TextW(self.name)
        local fit = math.max(1, math.min(nw, avail - cw))
        self.name:SetWidth(fit)
        self._truncated = nw > fit
        self.name:ClearAllPoints()
        self.name:SetPoint("LEFT", self, "LEFT", left, p.textY + yMid)
        self.cnt:ClearAllPoints()
        self.cnt:SetPoint("LEFT", self.name, "RIGHT", 0, 0)
        self:Paint()
    end
    return btn
end

--------------------------------------------------------------------------------
-- The strip on the main window
--------------------------------------------------------------------------------
local function LayoutStrip()
    local mf = BNB().mainFrame
    if not strip or not mf then return end
    local p = P()
    local mode = Mode()
    local skin = mode == "skin"
    -- Skin tabs (and normal ones with "under" on) draw in the strata below the
    -- window, so its top border covers their lower end
    local mfStrata = mf:GetFrameStrata()
    if skin or p.under then
        strip:SetFrameStrata(STRATA_BELOW[mfStrata] or "LOW")
    else
        strip:SetFrameStrata(mfStrata)
        strip:SetFrameLevel(mf:GetFrameLevel() + 20)
    end
    strip:ClearAllPoints()
    local yOff = skin and -p.skinTuck or p.y
    strip:SetPoint("BOTTOMLEFT", mf, "TOPLEFT", 0, yOff)
    strip:SetPoint("BOTTOMRIGHT", mf, "TOPRIGHT", 0, yOff)
    strip:SetHeight(skin and p.skinH or p.tabH)

    local keys = VisibleKeys()
    local avail = mf:GetWidth() - 2 * p.x
    local n = #keys
    local w
    if p.fill then
        w = math.max(p.minW, (avail - (n - 1) * p.gap) / n)
    else
        w = p.tabW
        if n * w + (n - 1) * p.gap > avail then
            w = math.max(p.minW, (avail - (n - 1) * p.gap) / n)
        end
    end
    local fit = math.max(1, math.floor((avail + p.gap) / (w + p.gap) + 0.001))
    w = math.floor(w)
    for i, t in ipairs(liveTabs) do t:Hide() end
    local shown = math.min(n, fit)
    for i = 1, shown do
        local t = liveTabs[i] or MakeTab(strip)
        liveTabs[i] = t
        t:ClearAllPoints()
        t:SetPoint("BOTTOMLEFT", strip, "BOTTOMLEFT", p.x + (i - 1) * (w + p.gap), 0)
        t:Fill(keys[i], w, mode)
        t:Show()
    end
    if statusFs then
        statusFs:SetText(string.format("%s, %s art | %d tabs at %d wide, %d left out | window %d wide",
            mode, mode == "skin" and "-" or ArtName(), shown, w, n - shown, math.floor(mf:GetWidth())))
    end
end

local function LayoutPreview()
    local mode = Mode()
    local w = P().tabW
    for _, t in ipairs(previewTabs) do
        t:Fill(t._previewKey, w, mode)
    end
end

local function Relayout()
    LayoutStrip()
    LayoutPreview()
end

local function EnsureStrip()
    local mf = BNB().mainFrame
    if not mf then return false end
    if not strip then
        strip = CreateFrame("Frame", "BigNoteBoxDevTopTabStrip", mf)
        mf:HookScript("OnSizeChanged", function()
            if strip:IsShown() then C_Timer.After(0, LayoutStrip) end
        end)
    end
    strip:Show()
    return true
end

--------------------------------------------------------------------------------
-- The panel
--------------------------------------------------------------------------------
local PAD, COLW, SL_W = 14, 200, 186

local SLIDERS = {
    { "tabH",     "Tab height (art 64)",  16, 64 },
    { "tabW",     "Tab width",            60, 320 },
    { "minW",     "Min width (shrink to)", 40, 240 },
    { "gap",      "Gap between tabs",    -24, 24 },
    { "x",        "First tab inset",     -20, 80 },
    { "y",        "Normal: up/down on window", -40, 30, 0.5 },
    { "iconSz",   "Icon size",            8, 40 },
    { "iconX",    "Icon left",            0, 48 },
    { "iconY",    "Icon up/down",        -12, 12, 0.5 },
    { "border",   "Icon border",          0, 4 },
    { "textGap",  "Text gap",             0, 20 },
    { "textY",    "Text up/down",        -8, 8, 0.5 },
    { "rightPad", "Text right pad",       0, 40 },
    { "activeA",  "Active alpha",         0, 1, 0.05 },
    { "hoverA",   "Hover alpha",          0, 1, 0.05 },
    { "dim",      "Inactive brightness",  0.2, 1, 0.05 },
    { "skinH",    "Skin: tab height",     16, 48 },
    { "skinTuck", "Skin: tucked under",   0, 20 },
}

local function SyncSliders()
    local p = P()
    for k, s in pairs(sliders) do s:SetValue(p[k], true) end
end

local cycleBtns = {}
local function SyncButtons()
    for _, b in ipairs(cycleBtns) do b:SetText(b._label()) end
end

local function Export()
    local p, key = P()
    local keys = {}
    for k in pairs(DEFAULTS) do keys[#keys + 1] = k end
    table.sort(keys)
    local parts = {}
    for _, k in ipairs(keys) do parts[#parts + 1] = k .. " = " .. tostring(p[k]) end
    local s = key .. " = { " .. table.concat(parts, ", ") .. " }"
    print("|cffff9900[top tabs test]|r " .. s)
    if BNB().ShowClipboardHint then BNB().ShowClipboardHint(s, panel, true) end
end

local function Build()
    panel = CreateFrame("Frame", "BigNoteBoxDevTopTabTest", UIParent, "BasicFrameTemplateWithInset")
    panel:SetFrameStrata("DIALOG")
    panel:SetMovable(true)
    panel:EnableMouse(true)
    panel:RegisterForDrag("LeftButton")
    panel:SetScript("OnDragStart", panel.StartMoving)
    panel:SetScript("OnDragStop", panel.StopMovingOrSizing)
    panel:SetClampedToScreen(true)
    if panel.TitleText then panel.TitleText:SetText("ALL-248 top tabs test") end
    tinsert(UISpecialFrames, panel:GetName())

    local W = PAD * 2 + 3 * COLW
    -- Still preview: normal / hover / active, the current art
    local pv = CreateFrame("Frame", nil, panel)
    pv:SetPoint("TOPLEFT", PAD, -32)
    pv:SetSize(W - 2 * PAD, 76)
    local states = { "normal", "hover", "active" }
    local keys = VisibleKeys()
    local sampleKey = keys[3] or "all"
    for i, st in ipairs(states) do
        local lbl = pv:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        lbl:SetPoint("TOPLEFT", (i - 1) * COLW, 0)
        lbl:SetText(st)
        local t = MakeTab(pv)
        t._force = st ~= "normal" and st or "normal"
        t._previewKey = sampleKey
        t:SetPoint("BOTTOMLEFT", pv, "BOTTOMLEFT", (i - 1) * COLW, 0)
        previewTabs[i] = t
    end

    -- Toggles and cycles
    local tpl = BNB().PanelButtonTemplate and BNB().PanelButtonTemplate() or "UIPanelButtonTemplate"
    local bx, by = PAD, -118
    local function Btn(w, label, onClick)
        local b = CreateFrame("Button", nil, panel, tpl)
        b:SetSize(w, 22)
        if bx + w > W - PAD then bx = PAD; by = by - 26 end
        b:SetPoint("TOPLEFT", bx, by)
        bx = bx + w + 4
        b._label = label
        b:SetText(label())
        b:SetScript("OnClick", function() onClick(); SyncButtons(); Relayout() end)
        cycleBtns[#cycleBtns + 1] = b
        return b
    end
    local function Cycle(list, field)
        local p = P()
        p[field] = p[field] % #list + 1
    end
    Btn(150, function() return "Look: " .. MODES[modeIdx][1] end, function()
        modeIdx = modeIdx % #MODES + 1
        SyncSliders()
    end)
    Btn(110, function() return "Art: " .. ARTS[artIdx][1] end, function() artIdx = artIdx % #ARTS + 1 end)
    Btn(118, function() return "Border: " .. BORDER_COLS[P().borderCol][1] end, function() Cycle(BORDER_COLS, "borderCol") end)
    Btn(150, function() return "Font: " .. FONTS[P().font][1] end, function() Cycle(FONTS, "font") end)
    Btn(130, function() return "Count: " .. COUNTS[P().count][1] end, function() Cycle(COUNTS, "count") end)
    Btn(110, function() return "Tint: " .. TINTS[P().tint][1] end, function() Cycle(TINTS, "tint") end)
    Btn(120, function() return "Hover: " .. (P().hoverAdd and "add" or "blend") end, function() P().hoverAdd = not P().hoverAdd end)
    Btn(120, function() return "Slices: " .. (P().slice and "5" or "stretch") end, function() P().slice = not P().slice end)
    Btn(110, function() return "Width: " .. (P().fill and "fill" or "fixed") end, function() P().fill = not P().fill end)
    Btn(130, function() return "Under window: " .. (P().under and "yes" or "no") end, function() P().under = not P().under end)
    Btn(130, function() return "Long name: " .. (longName and "on" or "off") end, function() longName = not longName end)
    Btn(80, function() return "Export" end, Export)
    Btn(90, function() return "Defaults" end, function()
        local p = P()
        for k, v in pairs(DEFAULTS) do p[k] = v end
        SyncSliders()
    end)

    -- Sliders, three columns
    local sy = by - 34
    local perCol = math.ceil(#SLIDERS / 3)
    for i, d in ipairs(SLIDERS) do
        local col = math.floor((i - 1) / perCol)
        local r = (i - 1) % perCol
        local key = d[1]
        local s = BNB().CreateStackedSlider(panel, SL_W, {
            label = d[2], min = d[3], max = d[4], step = d[5] or 1,
            value = P()[key], default = DEFAULTS[key],
            onChange = function(v) P()[key] = v; Relayout() end,
        })
        s:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD + col * COLW, sy - r * (BNB().STACKED_SLIDER_H + 6))
        sliders[key] = s
    end
    local bottom = -sy + perCol * (BNB().STACKED_SLIDER_H + 6)

    statusFs = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    statusFs:SetPoint("TOPLEFT", PAD, -(bottom + 4))
    statusFs:SetPoint("RIGHT", panel, "RIGHT", -PAD, 0)
    statusFs:SetJustifyH("LEFT")

    panel:SetSize(W, bottom + 28)
    panel:SetPoint("TOP", UIParent, "TOP", 0, -60)

    panel:SetScript("OnShow", function()
        if not EnsureStrip() then
            print("|cffff9900[top tabs test]|r open the BigNoteBox main window, then /bnbtabs again")
        end
        activeKey = BNB().Sidebar.GetActive() or "all"
        SyncSliders(); SyncButtons(); Relayout()
    end)
    panel:SetScript("OnHide", function() if strip then strip:Hide() end end)
    if BNB().RegisterMessage then
        local function Redo() if panel:IsShown() then C_Timer.After(0, Relayout) end end
        for _, m in ipairs({ "NoteCreated", "NoteDeleted", "NoteChanged", "NoteRestored" }) do
            BNB().RegisterMessage("BNBDevTopTabs", m, Redo)
        end
    end
end

SLASH_BNBTOPTABS1 = "/bnbtabs"
SlashCmdList.BNBTOPTABS = function()
    if not BigNoteBox or not BigNoteBox.Sidebar then return end
    if not panel then Build(); panel:Hide(); panel:Show(); return end
    panel:SetShown(not panel:IsShown())
end

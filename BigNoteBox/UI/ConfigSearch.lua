-- BigNoteBox UI/ConfigSearch.lua - search in Settings (ALL-480)
--
-- A search box on its own row under the Settings tabs, in both chromes (made
-- by BNB._BuildConfigTabPanels, UI/ConfigWindow.lua). Typing lists up to
-- MAX_ROWS settings under it: the setting's text and where it is (Tab > Page).
-- A click, or Up / Down + Enter, opens that tab or page, scrolls the setting
-- into view and flashes its row.
--
-- The index is the built window itself: every FontString on every tab and
-- sub-page (labels, headers, descriptions, button texts), walked on the first
-- search after Settings opened, so a new setting is found with no extra work.
-- Text is read at search time, so a label that changes is always current.
-- Tooltips: every widget with an OnEnter script is probed once per walk. Its
-- OnEnter and OnLeave run (ExecuteFrameScript, hooks included) while secure
-- hooks on GameTooltip record the lines, so a tooltip written by hand on any
-- page is found with no tagging; the global GameTooltip is never replaced
-- (that would taint it). The lines join the widget's label (_searchLabel,
-- LabelHit's _hitLbl, AddCheck's _lbl, .Text or the button's text), or, with
-- no label, the first line is the result's text. Helpers also tag tips
-- (fs._searchTip / a widget's _searchTip: string, list or function), read on
-- every search. fs._searchText stands in for a label's shown text (a slider
-- label carries its default), fs._searchOf points a description at its row's
-- title (overview rows).
-- A row hidden on this client or in this mode (it, or a parent up to its page,
-- hidden) is not found, nor is a page whose page.noSearch (true or a function
-- returning true) says it cannot be opened now (Developer tools without the
-- dev addon).
--
-- Public API:
--   BNB.CreateConfigSearchRow(parent, topOffset, pad)
--       -> { rowH, SetSources(sources, show) }
--   sources: { { idx, ct, sf, page?, path } ... }; show(src) opens that tab / page
--   BNB.SearchSettings(text, max) -> { { text, path, entry } ... } or nil (combat)
--   BNB.OpenSettingsResult(entry) -> true when Settings opened there

local BNB = BigNoteBox
local L   = BNB.L

local BOX_H, ROW_SPACE   = 22, 30      -- the box, and the room the row takes
local ROW_H, MAX_ROWS    = 32, 8
local LIST_PAD           = 4
local MIN_CHARS          = 2
local DESC_CUT           = 70          -- longer text shows cut, as a description

local sources, showFn
local index, dirty = nil, true
local eb, placeholder, clearBtn, list, emptyFS, nav, flash
local rows = {}
local SKIP

-- ── Text ──────────────────────────────────────────────────────────────────────
local function Clean(t)
    if type(t) ~= "string" or t == "" then return "" end
    t = t:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", ""):gsub("|A.-|a", "")
    t = t:gsub("|H.-|h(.-)|h", "%1"):gsub("|n", " "):gsub("\n", " "):gsub("%s+", " ")
    return (t:match("^%s*(.-)%s*$"))
end

local function TipText(tip)
    if type(tip) == "function" then
        local ok, v = pcall(tip)
        tip = ok and v or nil
    end
    if type(tip) == "table" then return table.concat(tip, " ") end
    return type(tip) == "string" and tip or ""
end

-- Cut at a character boundary (UTF-8 continuation bytes are 128-191)
local function Cut(s, n)
    if #s <= n then return s end
    local i = n
    while i > 1 do
        local b = s:byte(i + 1)
        if not b or b < 128 or b > 191 then break end
        i = i - 1
    end
    return s:sub(1, i) .. "..."
end

-- ── Index ─────────────────────────────────────────────────────────────────────
-- A dropdown's own text is the chosen value, not a setting: its tooltip is
-- probed, its insides are not walked
local function Walk(f, found, tipFrames)
    for _, r in ipairs({ f:GetRegions() }) do
        if r:GetObjectType() == "FontString" then found[#found + 1] = r end
    end
    for _, c in ipairs({ f:GetChildren() }) do
        if c._searchTip or c:GetScript("OnEnter") then tipFrames[#tipFrames + 1] = c end
        if not c.SetupMenu then Walk(c, found, tipFrames) end
    end
end

-- Tooltip probe: GameTooltip's text setters, hooked once, record while probing
local probing, rec, hooked = false, nil, false
local function Rec(_, a, b)
    if not probing then return end
    if type(a) == "string" then rec[#rec + 1] = a end
    if type(b) == "string" then rec[#rec + 1] = b end
end
local function Probe(f)
    if not hooked then
        hooked = true
        hooksecurefunc(GameTooltip, "AddLine", Rec)
        hooksecurefunc(GameTooltip, "AddDoubleLine", Rec)
        hooksecurefunc(GameTooltip, "SetText", Rec)
    end
    rec, probing = {}, true
    pcall(ExecuteFrameScript, f, "OnEnter", true)
    pcall(ExecuteFrameScript, f, "OnLeave", true)
    probing = false
    local lines = {}
    for _, t in ipairs(rec) do
        t = Clean(t)
        if t ~= "" then lines[#lines + 1] = t end
    end
    return lines
end

local function LabelOf(f)
    local l = f._searchLabel or f._hitLbl or f._lbl or f.Text
    if not l and f.GetFontString then l = f:GetFontString() end
    return l
end

local function IsHeader(fs)
    if fs:GetObjectType() ~= "FontString" then return false end
    local fo = fs:GetFontObject()
    local name = fo and fo.GetName and fo:GetName()
    return name == "BNBFontNormalLarge" or name == "BNBFontNormalHuge"
end

local function BuildIndex()
    index = {}
    local order = 0
    local function Add(fs, src)
        order = order + 1
        local e = { fs = fs, src = src, order = order, header = IsHeader(fs) }
        index[#index + 1] = e
        return e
    end
    for _, src in ipairs(sources or {}) do
        local found, tipFrames, byFs, owned = {}, {}, {}, {}
        Walk(src.ct, found, tipFrames)
        for _, fs in ipairs(found) do
            if fs._searchOf then owned[#owned + 1] = fs
            else byFs[fs] = Add(fs, src) end
        end
        -- A description joins its title's entry; a lone one is its own
        for _, fs in ipairs(owned) do
            local e = byFs[fs._searchOf]
            if e then
                e.descs = e.descs or {}
                e.descs[#e.descs + 1] = fs
            else
                byFs[fs] = Add(fs, src)
            end
        end
        for _, f in ipairs(tipFrames) do
            local lines = f:GetScript("OnEnter") and Probe(f) or {}
            local lbl = LabelOf(f)
            local e = lbl and byFs[lbl]
            if e then
                e.tipFrames = e.tipFrames or {}
                e.tipFrames[#e.tipFrames + 1] = f
                if #lines > 0 then
                    e.probed = (e.probed and e.probed .. " " or "") .. table.concat(lines, " ")
                end
            elseif #lines > 0 then
                -- No label of its own (an icon button, a dropdown beside a
                -- label): the tooltip's first line is the result
                local ne = Add(f, src)
                ne.fixedText = lines[1]
                ne.probed = table.concat(lines, " ", 2)
                ne.tipFrames = { f }
            end
        end
    end
    -- A probe can leave the tooltip up on a hidden page
    if GameTooltip:IsShown() then GameTooltip:Hide() end
    dirty = false
end

-- Shown, and every parent up to its page shown
local function Visible(fs, ct)
    if not fs:IsShown() then return false end
    local p = fs:GetParent()
    while p and p ~= ct do
        if not p:IsShown() then return false end
        p = p:GetParent()
    end
    return true
end

-- ── Search ────────────────────────────────────────────────────────────────────
-- Every word must be found. In the text: 10, +4 at a word start; only in the
-- tooltip or description: 3. The whole query starting the text +8, a header
-- +2, a long text (a description shown on its own) -4. Ties keep page order.
local function Score(e, text, words, q)
    local hay = text:lower()
    local extra
    local s = 0
    for _, w in ipairs(words) do
        local p = hay:find(w, 1, true)
        if p then
            s = s + 10
            if p == 1 or hay:sub(p - 1, p - 1):find("[%s%p]") then s = s + 4 end
        else
            if not extra then
                local parts = { Clean(TipText(e.fs._searchTip)), e.probed or "" }
                for _, f in ipairs(e.tipFrames or {}) do parts[#parts + 1] = Clean(TipText(f._searchTip)) end
                for _, d in ipairs(e.descs or {}) do parts[#parts + 1] = Clean(d:GetText()) end
                extra = table.concat(parts, " "):lower()
            end
            if not extra:find(w, 1, true) then return nil end
            s = s + 3
        end
    end
    if hay:sub(1, #q) == q then s = s + 8 end
    if e.header then s = s + 2 end
    if #text > DESC_CUT then s = s - 4 end
    return s
end

local function Search(q)
    if dirty or not index then BuildIndex() end
    if not SKIP then SKIP = { [L["RESET"]] = true, [L["CFG_SUBPAGE_OPEN"]] = true } end
    local words = {}
    for w in q:gmatch("%S+") do words[#words + 1] = w end
    local hits, seen = {}, {}
    for _, e in ipairs(index) do
        local pg = e.src.page
        local off = pg and pg.noSearch and (pg.noSearch == true or pg.noSearch())
        if not off and Visible(e.fs, e.src.ct) then
            local text = e.fixedText or Clean(e.fs._searchText or e.fs:GetText())
            -- A letter in any script (bytes 128+ start a non-ASCII character)
            if text ~= "" and not SKIP[text] and text:find("[%a\128-\255]") then
                local s = Score(e, text, words, q)
                local key = text:lower() .. ">>" .. e.src.path
                if s and not seen[key] then
                    seen[key] = true
                    hits[#hits + 1] = { e = e, text = text, s = s }
                end
            end
        end
    end
    table.sort(hits, function(a, b)
        if a.s ~= b.s then return a.s > b.s end
        return a.e.order < b.e.order
    end)
    return hits
end

-- ── Jump + flash ──────────────────────────────────────────────────────────────
local function FlashColor()
    if BigNoteBoxDB and BigNoteBoxDB.skinMode and BNB.SkinAccentOf and BNB.GetSkinPreset then
        return BNB.SkinAccentOf(BNB.GetSkinPreset())
    end
    return 0.40, 0.73, 0.42   -- BNB green #66bb6a
end

local function Flash(ct, fs, dy)
    if not flash then
        flash = CreateFrame("Frame")
        flash._fill = flash:CreateTexture(nil, "OVERLAY")
        flash._fill:SetAllPoints()
        flash._bar = flash:CreateTexture(nil, "OVERLAY", nil, 1)
        flash._bar:SetPoint("TOPLEFT"); flash._bar:SetPoint("BOTTOMLEFT")
        flash._bar:SetWidth(3)
        local ag = flash:CreateAnimationGroup()
        local function Step(order, from, to, dur)
            local a = ag:CreateAnimation("Alpha")
            a:SetOrder(order); a:SetFromAlpha(from); a:SetToAlpha(to); a:SetDuration(dur)
        end
        Step(1, 0, 1, 0.15)   -- in
        Step(2, 1, 1, 0.70)   -- hold
        Step(3, 1, 0, 0.90)   -- out
        ag:SetScript("OnFinished", function() flash:Hide() end)
        flash._ag = ag
    end
    local r, g, b = FlashColor()
    flash._fill:SetColorTexture(r, g, b, 0.22)
    flash._bar:SetColorTexture(r, g, b, 0.9)
    flash:SetParent(ct)
    flash:SetFrameStrata(ct:GetFrameStrata())
    flash:SetFrameLevel(ct:GetFrameLevel() + 40)
    flash:ClearAllPoints()
    flash:SetPoint("TOPLEFT", ct, "TOPLEFT", -6, -(dy - 4))
    flash:SetSize(ct:GetWidth() + 10, math.max(fs:GetHeight() or 0, 16) + 8)
    flash._ag:Stop()
    flash:SetAlpha(0)
    flash:Show()
    flash._ag:Play()
end

local function ScrollTo(e)
    local ct, sf, fs = e.src.ct, e.src.sf, e.fs
    if not (sf:IsShown() and fs:IsVisible()) then return end
    local top, ft = ct:GetTop(), fs:GetTop()
    if not (top and ft) then return end
    local dy = top - ft
    local range = sf:GetVerticalScrollRange() or 0
    sf:SetVerticalScroll(math.max(0, math.min(range, dy - 40)))
    Flash(ct, fs, dy)
end

local function Jump(e)
    list:Hide()
    eb:ClearFocus()
    if showFn then showFn(e.src) end
    -- The page sets its content height 0.05 s after it shows (CreateAutoScrollPanel)
    C_Timer.After(0.1, function() ScrollTo(e) end)
end

-- ── Results list ──────────────────────────────────────────────────────────────
local function Row(i)
    local r = rows[i]
    if r then return r end
    r = CreateFrame("Button", nil, list)
    r:SetHeight(ROW_H)
    r:SetPoint("TOPLEFT",  list, "TOPLEFT",  LIST_PAD, -LIST_PAD - (i - 1) * ROW_H)
    r:SetPoint("TOPRIGHT", list, "TOPRIGHT", -LIST_PAD, -LIST_PAD - (i - 1) * ROW_H)
    local hl = r:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints(); hl:SetColorTexture(1, 1, 1, 0.10)
    r._title = r:CreateFontString(nil, "OVERLAY", "BNBFontNormalSmall")
    r._title:SetPoint("TOPLEFT",  r, "TOPLEFT",  6, -3)
    r._title:SetPoint("TOPRIGHT", r, "TOPRIGHT", -6, -3)
    r._title:SetJustifyH("LEFT"); r._title:SetWordWrap(false)
    BNB.SetTextWhite(r._title)
    r._path = r:CreateFontString(nil, "OVERLAY", "BNBFontHighlightSmall")
    r._path:SetPoint("TOPLEFT",  r._title, "BOTTOMLEFT",  0, -2)
    r._path:SetPoint("TOPRIGHT", r._title, "BOTTOMRIGHT", 0, -2)
    r._path:SetJustifyH("LEFT"); r._path:SetWordWrap(false)
    r._path:SetTextColor(0.55, 0.55, 0.55)
    r:SetScript("OnClick", function(self) if self._e then Jump(self._e) end end)
    rows[i] = r
    return r
end

local function Refresh()
    local q = Clean(eb:GetText() or ""):lower()
    if #q < MIN_CHARS then list:Hide(); return end
    local hits = Search(q)
    local n = math.min(#hits, MAX_ROWS)
    for i = 1, n do
        local r, h = Row(i), hits[i]
        r._e = h.e
        r._title:SetText(Cut(h.text, DESC_CUT))
        r._path:SetText(h.e.src.path)
        r:Show()
    end
    for i = n + 1, #rows do rows[i]:Hide(); rows[i]._e = nil end
    if n == 0 then emptyFS:Show() else emptyFS:Hide() end
    list:SetHeight(LIST_PAD * 2 + math.max(n, 1) * ROW_H)
    list:Show()
end

-- ── For the Oracle's `o` prefix ───────────────────────────────────────────────
-- The settings matching text, best first, at most max: { text, path, entry },
-- entry handed back to BNB.OpenSettingsResult. Builds Settings hidden the
-- first time; nil in combat (it cannot be built or opened then).
function BNB.SearchSettings(text, max)
    if not sources and not (BNB.BuildConfigHidden and BNB.BuildConfigHidden()) then return nil end
    if InCombatLockdown() then return nil end
    local q = Clean(text or ""):lower()
    if #q < MIN_CHARS then return {} end
    local out = {}
    for i, h in ipairs(Search(q)) do
        if i > (max or MAX_ROWS) then break end
        out[i] = { text = Cut(h.text, DESC_CUT), path = h.e.src.path, entry = h.e }
    end
    return out
end

-- Opens Settings (if closed) at a result's tab or page, scrolled to it and
-- flashing. False when Settings could not open (combat).
function BNB.OpenSettingsResult(e)
    if not e then return false end
    if not BNB.ConfigShown() then BNB.OpenConfig() end
    if not BNB.ConfigShown() then return false end
    Jump(e)
    return true
end

-- ── Build ─────────────────────────────────────────────────────────────────────
function BNB.CreateConfigSearchRow(parent, topOffset, pad)
    local box = BNB.CreateBackdropFrame("Frame", nil, parent)
    box:SetPoint("TOPLEFT",  parent, "TOPLEFT",  pad,  -topOffset)
    box:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -pad, -topOffset)
    box:SetHeight(BOX_H)

    local icon = box:CreateTexture(nil, "OVERLAY")
    icon:SetTexture("Interface\\Common\\UI-Searchbox-Icon")
    icon:SetSize(14, 14)
    icon:SetPoint("LEFT", box, "LEFT", 6, -1)
    icon:SetVertexColor(0.6, 0.6, 0.6)

    eb = CreateFrame("EditBox", nil, box)
    eb:SetAllPoints(box)
    eb:SetTextInsets(24, 26, 0, 0)
    eb:SetFontObject("BNBFontNormalSmall")
    eb:SetAutoFocus(false)
    eb:SetMaxLetters(60)
    BNB.SetTextWhite(eb)

    placeholder = box:CreateFontString(nil, "OVERLAY", "BNBFontNormalSmall")
    placeholder:SetPoint("LEFT", box, "LEFT", 24, 0)
    placeholder:SetTextColor(0.45, 0.45, 0.45)
    placeholder:SetText(L["CFG_SEARCH_PLACEHOLDER"])

    clearBtn = BNB.CreateIconButton(box, 16, "close", {
        tip = L["CFG_SEARCH_CLEAR"],
        onClick = function() eb:SetText(""); eb:ClearFocus() end,
    })
    clearBtn:SetPoint("RIGHT", box, "RIGHT", -4, 0)
    clearBtn:SetFrameLevel(eb:GetFrameLevel() + 2)
    clearBtn:Hide()

    -- One strata up, so the list draws over every page of the window
    list = BNB.CreateBackdropFrame("Frame", nil, box)
    list:SetFrameStrata("FULLSCREEN")

    -- Skin mode: the preset's button fill and border, as the main window's
    -- search bar (UI/NoteList.lua ApplySearchBarSkin), re-applied on a preset
    -- change; normal mode: the plain dark box and panel
    local function ApplySkin()
        if BigNoteBoxDB and BigNoteBoxDB.skinMode and BNB.GetSkinPreset then
            local p = BNB.GetSkinPreset()
            local r, g, b = BNB.SkinButtonOf(p)
            local br, bg_, bb, ba = BNB.SkinBorderOf(p)
            BNB.SetBackdrop(box,  r, g, b, 0.92, br, bg_, bb, ba)
            BNB.SetBackdrop(list, r, g, b, 0.97, br, bg_, bb, ba)
        else
            BNB.SetBackdropDark(box)
            BNB.SetBackdrop(list, 0.08, 0.08, 0.10, 0.97, 0.35, 0.35, 0.38, 1)
        end
    end
    ApplySkin()
    if BigNoteBoxDB and BigNoteBoxDB.skinMode then BNB.RegisterSkinBackdrop(ApplySkin) end
    list:SetPoint("TOPLEFT",  box, "BOTTOMLEFT",  0, -2)
    list:SetPoint("TOPRIGHT", box, "BOTTOMRIGHT", 0, -2)
    list:EnableMouse(true)
    list:Hide()
    emptyFS = list:CreateFontString(nil, "OVERLAY", "BNBFontNormalSmall")
    emptyFS:SetPoint("LEFT", list, "LEFT", LIST_PAD + 6, 0)
    emptyFS:SetTextColor(0.50, 0.50, 0.50)
    emptyFS:SetText(L["CFG_SEARCH_NONE"])

    eb:SetScript("OnTextChanged", function(self)
        local has = (self:GetText() or "") ~= ""
        if has then placeholder:Hide() else placeholder:Show() end
        clearBtn:SetShown(has)
        Refresh()
    end)
    -- Up / Down / Tab over the results (ALL-427); Enter opens the highlighted
    -- one, or the first
    nav = BNB.AttachListKeys(eb, list, rows)
    eb:SetScript("OnEnterPressed", function()
        if nav:Take() then return end
        local r = rows[1]
        if list:IsShown() and r and r:IsShown() then r:Click() end
    end)
    -- Esc closes the list first, then clears the box
    eb:SetScript("OnEscapePressed", function(self)
        if nav:Close() then return end
        self:SetText("")
        self:ClearFocus()
    end)
    eb:SetScript("OnEditFocusGained", function() Refresh() end)

    -- A click anywhere else closes the list (the text stays)
    list:SetScript("OnEvent", function(self)
        if self:IsMouseOver() or box:IsMouseOver() then return end
        self:Hide()
    end)
    list:SetScript("OnShow", function(self) self:RegisterEvent("GLOBAL_MOUSE_DOWN") end)
    list:SetScript("OnHide", function(self) self:UnregisterEvent("GLOBAL_MOUSE_DOWN") end)

    -- Walked again on the first search after each open: pages fill or hide
    -- rows as settings change
    parent:HookScript("OnShow", function() dirty = true end)
    parent:HookScript("OnHide", function() eb:SetText(""); eb:ClearFocus() end)

    return {
        rowH = ROW_SPACE,
        SetSources = function(src, show) sources, showFn, dirty = src, show, true end,
    }
end

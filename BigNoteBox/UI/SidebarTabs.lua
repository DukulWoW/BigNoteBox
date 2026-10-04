-- BigNoteBox UI/SidebarTabs.lua
--
-- The character sidebar as long tabs along the top of the main window
-- (sidebarSide = "top", ALL-248). Same slots, counts, tooltip and right-click
-- menu as the vertical strip in UI/Sidebar.lua, shared through SB._kit. Every
-- number below was tuned in the dev addon's /bnbtabs test (Dukul, 2026-10-04).
--
-- Normal look, bottom to top (Dukul): the tab art (retail / forever), the icon in
-- a plain border + "Name (12)", the active glow (active tab only), the hover
-- (inactive tabs only). Border and both glows take the class colour on
-- character tabs, BNB green on All / Global (Dukul, 2026-10-04).
-- Skin look: the rich-note bottom tabs' box (NoteEditor.lua MakeSkinTab) turned
-- upside down: no bottom border, tucked under the window's top border.
--
-- Too many tabs: they shrink (MIN_SCALE), and below minW the rest go into a
-- "More..." tab on the right whose menu picks one of them. Order (Dukul,
-- 2026-10-04): All > Global > pinned > the last clicked > the one before... >
-- More...: every pick, from a tab or the menu, moves the character to the
-- front of the unpinned ones.
--
-- Called by Sidebar.lua: SB.RefreshTop(parent) -> every key (tabs + menu),
-- SB.HideTop(), SB.PaintTop() (active tab changed).

local BNB = BigNoteBox
local SB  = BNB.Sidebar

local ART = "Interface\\AddOns\\BigNoteBox\\Assets\\Sidebar\\sb-top-tab-"
local AW, AH = 256, 64   -- art canvas (all four files)
-- 5-slice cuts in art px: both caps and the bottom-centre ornament keep their
-- shape at any width, the two runs between them stretch
local CAP, ORN_L, ORN_R = 24, 114, 142

-- Dukul's Export from the test; the same on both clients except y, only the art
-- differs. y = tab bottom against the window top (negative = overlaps it);
-- Forever's taller chrome needs 6 (Dukul, 2026-10-04).
local NORMAL = { h = 32, w = 150, minW = 80, gap = 0, x = 8, y = BNB.IsForever and 6 or -4,
    iconSz = 18, iconX = 20, iconY = -0.5, border = 1, textGap = 5, textY = -1.5,
    rightPad = 14, activeA = 1, hoverA = 0.5, dim = 0.5, font = "GameFontNormal",
    pinSz = 14, pinX = -16, pinY = -6 }
-- Skin: icon and text centred on the whole tab, the tucked part included
-- (the test's -4 offsets + half the tuck)
local SKIN = { h = 30, tuck = 8, w = 150, minW = 80, gap = 0, x = 8,
    iconSz = 18, iconX = 13, iconY = 0, border = 1, textGap = 5, textY = 0,
    rightPad = 14, dim = 0.5, font = "GameFontHighlight",
    pinSz = 14, pinX = -7, pinY = -6 }
-- Forever skin (Dukul's /bnbtabs Export, 2026-10-04): taller, wider tabs with
-- a gap between them, a smaller icon and small text. The test adds half the
-- tuck to iconY / textY; these are the results (-2.5 + 3, -3 + 3)
if BNB.IsForever then
    for k, v in pairs({ h = 32, tuck = 6, w = 190, minW = 90, gap = 5,
        iconSz = 16, iconY = 0.5, textY = 0, font = "GameFontHighlightSmall" }) do
        SKIN[k] = v
    end
end
-- More tabs than fit at w: they share the width, and icon, spacing and text
-- shrink with it (Dukul, 2026-10-04): icon and spacing by w / S.w down to
-- MIN_SCALE, the text down to MIN_TEXT_SCALE. Below minW the last tabs drop out.
local MIN_SCALE, MIN_TEXT_SCALE = 0.6, 0.75
-- Pinned characters: sb-top-tab-pinned in the tab's top-right corner, inside
-- the frame, under the active / hover glows (Dukul). pinSz/pinX/pinY above; the
-- name keeps clear of it (FillTab adds its width to the right pad).
local PIN_ART = "Interface\\AddOns\\BigNoteBox\\Assets\\Sidebar\\sb-top-tab-pinned"
local MORE_MIN_W, MORE_PAD = 48, 14   -- the "More..." tab: text width + pad each side
local GREEN = { 0.40, 0.85, 0.40 }   -- All / Global: BNB green, Sidebar.lua ACTIVE_R/G/B

local SKIN_BOX = { bgFile = "Interface\\Buttons\\White8x8",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 14,
    insets = { left = 3, right = 3, top = 3, bottom = 3 } }
local STRATA_BELOW = { MEDIUM = "LOW", HIGH = "MEDIUM", DIALOG = "HIGH",
    FULLSCREEN = "DIALOG", FULLSCREEN_DIALOG = "FULLSCREEN", TOOLTIP = "FULLSCREEN_DIALOG" }

local _strip       -- child of the main window
local _tabs = {}   -- pooled tab buttons
local _more        -- the "More..." tab (its own button, never a slot)

local function IsSkin() return BigNoteBoxDB and BigNoteBoxDB.skinMode end

local function ClassColor(key)
    local ck = key and key:match("^char:(.+)$")
    local rec = ck and BigNoteBoxDB and BigNoteBoxDB.knownChars and BigNoteBoxDB.knownChars[ck]
    local cls = rec and rec.class and rec.class:upper():gsub(" ", "")
    local c = cls and RAID_CLASS_COLORS and RAID_CLASS_COLORS[cls]
    if c then return { c.r, c.g, c.b } end
    return GREEN
end

local function NameFor(key)
    -- Short on the tabs (Dukul); the tooltip keeps "All Notes" / "Global Notes"
    if key == "all" then return BNB.L["SB_TAB_ALL"] end
    if key == "global" then return BNB.L["SB_TAB_GLOBAL"] end
    return (SB._kit.TooltipForKey(key))   -- title = the character's name
end

-- Full width of a FontString's text, whatever width it was given
local function TextW(fs)
    if fs.GetUnboundedStringWidth then return math.ceil(fs:GetUnboundedStringWidth()) end
    fs:SetWidth(0)
    return math.ceil(fs:GetStringWidth())
end

--------------------------------------------------------------------------------
-- Art slices
--------------------------------------------------------------------------------
local function NewSlices(btn, layer, sub, file)
    local t = {}
    for i = 1, 5 do
        t[i] = btn:CreateTexture(nil, layer, nil, sub)
        t[i]:SetTexture(file)
    end
    return t
end

local function LayoutSlices(set, btn, w, h)
    local k = h / AH
    local capW, ornW = CAP * k, (ORN_R - ORN_L) * k
    local runW = (w - 2 * capW - ornW) / 2
    -- { art x0, art x1, drawn width }; too narrow for the slices = one stretched piece
    local cuts = runW >= 1
        and { { 0, CAP, capW }, { CAP, ORN_L, runW }, { ORN_L, ORN_R, ornW },
              { ORN_R, AW - CAP, runW }, { AW - CAP, AW, capW } }
        or  { { 0, AW, w } }
    local x = 0
    for i, t in ipairs(set) do
        local c = cuts[i]
        t:ClearAllPoints()
        if c then
            t:SetTexCoord(c[1] / AW, c[2] / AW, 0, 1)
            t:SetPoint("TOPLEFT", btn, "TOPLEFT", x, 0)
            t:SetSize(c[3], h)
            x = x + c[3]
        end
        t._used = c and true or false
    end
end

local function ShowSlices(set, on, c, a)
    for _, t in ipairs(set) do
        t:SetShown(on and t._used)
        if c then t:SetVertexColor(c[1], c[2], c[3], a or 1) end
    end
end

-- A "More..." menu row: icon, name in its class colour, note count
-- Select a slot from the tabs. A character is stamped tabPicked (Sidebar.lua's
-- GetVisibleKeys sorts the unpinned by it, newest first) and the tabs are
-- redrawn in the new order. The stamp is time(), or one more than the newest
-- stamp, so two picks in the same second still keep their order.
local function Pick(key)
    local ck = key:match("^char:(.+)$")
    local chars = BigNoteBoxDB and BigNoteBoxDB.knownChars
    local rec = ck and chars and chars[ck]
    if rec then
        local newest = 0
        for _, r in pairs(chars) do newest = math.max(newest, r.tabPicked or 0) end
        rec.tabPicked = math.max(time(), newest + 1)
    end
    SB.SetActive(key)
    if rec then SB.Refresh() end
end

local function MenuLabel(key)
    local c = ClassColor(key)
    return string.format("|T%s:16:16:0:0:64:64:5:59:5:59|t |cff%02x%02x%02x%s|r (%d)",
        SB.IconForKey(key), math.floor(c[1] * 255), math.floor(c[2] * 255), math.floor(c[3] * 255), NameFor(key),
        SB._kit.CountForKey(key))
end

--------------------------------------------------------------------------------
-- One tab
--------------------------------------------------------------------------------
local function Paint(btn)
    local key = btn._key
    if not key then return end
    local act = key == SB.GetActive()
    if btn._moreKeys then
        act = false
        for _, k in ipairs(btn._moreKeys) do
            if k == SB.GetActive() then act = true; break end
        end
    end
    local hov = btn._hover and not act
    local c = ClassColor(key)
    local S = btn._skin and SKIN or NORMAL
    if btn._skin then
        local p = BNB.GetSkinPreset()
        local br, bg_, bb = BNB.SkinBorderOf(p)
        local m = act and 1 or 0.6
        btn:SetBackdropColor(math.min(1, p.r + p.lift * 1.5) * m, math.min(1, p.g + p.lift * 1.5) * m,
            math.min(1, p.b + p.lift * 1.5) * m, 0.97)
        btn:SetBackdropBorderColor(br, bg_, bb, 1)
        btn.hl:SetShown(hov)
    else
        btn.hl:Hide()
        ShowSlices(btn.active, act, c, S.activeA)
        ShowSlices(btn.hover, hov, c, S.hoverA)
    end
    -- Inactive: icon desaturated and darkened, text dimmed, as the sidebar does
    local lit = act or hov
    local v = lit and 1 or S.dim
    btn.icon:SetDesaturated(not lit)
    btn.icon:SetVertexColor(v, v, v)
    btn.pin:SetVertexColor(v, v, v)
    btn.edge:SetColorTexture(c[1] * v, c[2] * v, c[3] * v, 1)
    local a = lit and 1 or math.max(0.35, S.dim)
    btn.name:SetAlpha(a); btn.cnt:SetAlpha(a)
end

local function MakeTab(parent)
    local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
    btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    btn.base   = NewSlices(btn, "BACKGROUND", 0, ART .. (BNB.IsForever and "forever" or "retail"))
    btn.active = NewSlices(btn, "OVERLAY", 0, ART .. "active")   -- over icon and name (Dukul)
    btn.hover  = NewSlices(btn, "OVERLAY", 1, ART .. "hover")
    btn.edge = btn:CreateTexture(nil, "ARTWORK", nil, 0)   -- the icon's plain border
    btn.icon = btn:CreateTexture(nil, "ARTWORK", nil, 1)
    btn.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    btn.icon:SetPoint("CENTER", btn.edge, "CENTER")
    btn.hl = btn:CreateTexture(nil, "ARTWORK", nil, 2)      -- skin hover
    btn.hl:SetColorTexture(1, 1, 1, 0.10)
    btn.hl:SetPoint("TOPLEFT", 3, -3); btn.hl:SetPoint("BOTTOMRIGHT", -3, 3)
    btn.hl:Hide()
    btn.pin = btn:CreateTexture(nil, "ARTWORK", nil, 4)   -- under the OVERLAY glows
    btn.pin:SetTexture(PIN_ART)
    btn.pin:Hide()
    btn.name = btn:CreateFontString(nil, "ARTWORK")
    btn.name:SetDrawLayer("ARTWORK", 3)
    btn.name:SetWordWrap(false)
    btn.name:SetJustifyH("LEFT")
    btn.cnt = btn:CreateFontString(nil, "ARTWORK")
    btn.cnt:SetDrawLayer("ARTWORK", 3)
    btn.cnt:SetWordWrap(false)
    btn.cnt:SetPoint("LEFT", btn.name, "RIGHT", 0, 0)

    btn:SetScript("OnEnter", function(self)
        self._hover = true; Paint(self)
        if self._moreKeys then
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:AddLine(BNB.L["SB_MORE_TABS"], 1, 1, 1)
            for _, k in ipairs(self._moreKeys) do
                local c = ClassColor(k)
                GameTooltip:AddLine(NameFor(k) .. " (" .. SB._kit.CountForKey(k) .. ")", c[1], c[2], c[3])
            end
            GameTooltip:Show()
            return
        end
        local title, sub = SB._kit.TooltipForKey(self._key)
        local c = self._key:find("^char:") and ClassColor(self._key) or { 1, 1, 1 }
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(title, c[1], c[2], c[3])
        if sub and sub ~= "" then GameTooltip:AddLine(sub, 0.8, 0.8, 0.8, true) end
        local n = SB._kit.CountForKey(self._key)
        if n > 0 then
            GameTooltip:AddLine(n == 1 and BNB.L["SB_NOTE_COUNT_ONE"]
                or string.format(BNB.L["SB_NOTE_COUNT_N_FMT"], n), 0.6, 0.9, 0.6)
        end
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function(self)
        self._hover = false; Paint(self)
        GameTooltip:Hide()
    end)
    btn:SetScript("OnClick", function(self, mouseBtn)
        if self._moreKeys then
            GameTooltip:Hide()
            BNB.ContextMenu.Open(self, function(root)
                -- Click = pick, and the character moves to the front of the
                -- tabs (tabPicked, read by Sidebar.lua's GetVisibleKeys), so no
                -- tick is needed; hover = the tab's own right-click entries (Dukul)
                for _, k in ipairs(self._moreKeys) do
                    local row = root:CreateButton(MenuLabel(k), function() Pick(k) end)
                    SB._kit.AddSlotMenuEntries(row, k)
                end
            end)
        elseif mouseBtn == "RightButton" then
            SB._kit.ShowSlotContextMenu(self._key, self)   -- All / Global: none
        else
            Pick(self._key)
        end
    end)
    return btn
end

-- Size and art (normal) or box (skin) at width w
local function SetLook(btn, w, skin)
    local S = skin and SKIN or NORMAL
    btn._skin = skin
    btn:SetSize(w, S.h)
    if skin then
        if not btn._hasBox then
            btn:SetBackdrop(SKIN_BOX)
            -- No bottom border: the tab runs down under the window
            for _, k in ipairs({ "BottomEdge", "BottomLeftCorner", "BottomRightCorner" }) do
                if btn[k] then btn[k]:Hide() end
            end
            if btn.LeftEdge and btn.RightEdge then
                btn.LeftEdge:SetPoint("BOTTOMLEFT", btn, "BOTTOMLEFT")
                btn.RightEdge:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT")
            end
            btn._hasBox = true
        end
        ShowSlices(btn.base, false); ShowSlices(btn.active, false); ShowSlices(btn.hover, false)
    else
        if btn._hasBox then btn:ClearBackdrop(); btn._hasBox = false end
        LayoutSlices(btn.base, btn, w, S.h)
        LayoutSlices(btn.active, btn, w, S.h)
        LayoutSlices(btn.hover, btn, w, S.h)
        ShowSlices(btn.base, true)
    end
end

-- Size, look and text for one slot key at width w; k = shrink factor (1 = full size)
local function FillTab(btn, key, w, skin, k)
    local S = skin and SKIN or NORMAL
    btn._key = key
    SetLook(btn, w, skin)

    local bd = S.border
    local isz = math.floor(S.iconSz * k + 0.5)
    local ix = S.iconX * k
    btn.edge:ClearAllPoints()
    btn.edge:SetSize(isz + 2 * bd, isz + 2 * bd)
    btn.edge:SetPoint("LEFT", btn, "LEFT", ix, S.iconY)
    btn.icon:SetSize(isz, isz)
    btn.icon:SetTexture(SB.IconForKey(key))

    -- "Name (12)": only the name is cut short ("..."), so the count always shows
    btn.name:SetFontObject(S.font); btn.cnt:SetFontObject(S.font)
    if btn.name.SetTextScale then   -- the font object keeps WoW's per-alphabet fallback
        local ts = math.max(MIN_TEXT_SCALE, k)
        btn.name:SetTextScale(ts); btn.cnt:SetTextScale(ts)
    end
    btn.cnt:SetText(" (" .. SB._kit.CountForKey(key) .. ")")
    btn.name:SetText(NameFor(key))
    local ck = key:match("^char:(.+)$")
    local rec = ck and BigNoteBoxDB and BigNoteBoxDB.knownChars and BigNoteBoxDB.knownChars[ck]
    local pinned = rec and rec.slotPinned and true or false
    local psz = math.floor(S.pinSz * k + 0.5)
    btn.pin:ClearAllPoints()
    btn.pin:SetSize(psz, psz)
    btn.pin:SetPoint("TOPRIGHT", btn, "TOPRIGHT", S.pinX * k, S.pinY)
    btn.pin:SetShown(pinned)

    local left = ix + isz + 2 * bd + S.textGap * k
    local nw, cw = TextW(btn.name), TextW(btn.cnt)
    local pad = S.rightPad * k + (pinned and psz or 0)
    btn.name:SetWidth(math.max(1, math.min(nw, w - left - pad - cw)))
    btn.name:ClearAllPoints()
    btn.name:SetPoint("LEFT", btn, "LEFT", left, S.textY)
    Paint(btn)
end

-- The "More..." tab's label, set up for measuring. It only shows when the tabs
-- are at minW, where the text is always at MIN_TEXT_SCALE. Returns its width.
local function SetMoreText(btn, skin)
    local S = skin and SKIN or NORMAL
    btn.name:SetFontObject(S.font)
    if btn.name.SetTextScale then btn.name:SetTextScale(MIN_TEXT_SCALE) end
    btn.name:SetText(BNB.L["SB_TAB_MORE"])
    return math.max(MORE_MIN_W, TextW(btn.name) + 2 * MORE_PAD)
end

-- The "More..." tab: no icon, the label centred; keys = the slots in its menu
local function FillMore(btn, keys, skin, moreW)
    local S = skin and SKIN or NORMAL
    btn._key, btn._moreKeys = "more", keys
    SetLook(btn, moreW, skin)
    btn.edge:Hide(); btn.icon:Hide(); btn.pin:Hide()
    SetMoreText(btn, skin)
    btn.name:SetWidth(moreW)
    btn.name:SetJustifyH("CENTER")
    btn.name:ClearAllPoints()
    btn.name:SetPoint("CENTER", btn, "CENTER", 0, S.textY)
    btn.cnt:Hide()   -- never given a font: SetText on it errors ("Font not set")
    Paint(btn)
end

--------------------------------------------------------------------------------
-- The strip
--------------------------------------------------------------------------------
local function PaintAll()
    for _, t in ipairs(_tabs) do if t:IsShown() then Paint(t) end end
    if _more and _more:IsShown() then Paint(_more) end
end
SB.PaintTop = PaintAll

-- The main window's clamp counts the part of the tabs above it, so they cannot
-- be dragged off the top of the screen (BNB.StartDragMoving reads it too)
local function SetClampTop(parent, above)
    if parent and parent.SetClampRectInsets then parent:SetClampRectInsets(0, 0, above, 0) end
end

function SB.HideTop()
    if _strip and _strip:IsShown() then
        _strip:Hide()
        SetClampTop(_strip:GetParent(), 0)
    end
end

-- Lays the tabs out on top of parent (the main window); returns the keys shown.
-- Tabs share the width down to minW, shrinking their contents (MIN_SCALE); the
-- ones that still do not fit go into the "More..." tab's menu.
function SB.RefreshTop(parent)
    local skin = IsSkin() and true or false
    local S = skin and SKIN or NORMAL
    if not _strip then
        _strip = CreateFrame("Frame", "BigNoteBoxSidebarTopStrip", parent)
        if BNB.RegisterSkinButton then BNB.RegisterSkinButton(PaintAll) end
    end
    -- Skin tabs draw in the strata below the window, so its top border covers
    -- their lower end; normal tabs stand on the border
    local strata = parent:GetFrameStrata()
    if skin then
        _strip:SetFrameStrata(STRATA_BELOW[strata] or "LOW")
    else
        _strip:SetFrameStrata(strata)
        _strip:SetFrameLevel(parent:GetFrameLevel() + 20)
    end
    local yOff = skin and -S.tuck or S.y
    _strip:ClearAllPoints()
    _strip:SetPoint("BOTTOMLEFT", parent, "TOPLEFT", 0, yOff)
    _strip:SetPoint("BOTTOMRIGHT", parent, "TOPRIGHT", 0, yOff)
    _strip:SetHeight(S.h)
    _strip:Show()
    SetClampTop(parent, S.h + yOff)

    local keys = SB._kit.GetVisibleKeys(0, math.huge)
    local avail = parent:GetWidth() - 2 * S.x
    local n = #keys
    local w, shown, rest, moreW = S.w, n, nil, nil
    if n * w + (n - 1) * S.gap > avail then
        w = (avail - (n - 1) * S.gap) / n
        if w < S.minW then
            -- As many as fit at minW beside the "More..." tab, sharing that room
            _more = _more or MakeTab(_strip)
            moreW = SetMoreText(_more, skin)
            local room = avail - moreW - S.gap
            shown = math.max(1, math.floor((room + S.gap) / (S.minW + S.gap)))
            w = (room - (shown - 1) * S.gap) / shown
            rest = {}
            for i = shown + 1, n do rest[#rest + 1] = keys[i] end
        end
    end
    w = math.floor(w)
    local k = math.max(MIN_SCALE, math.min(1, w / S.w))

    for _, t in ipairs(_tabs) do t:Hide() end
    if _more then _more:Hide() end
    for i = 1, shown do
        local key = keys[i]
        local t = _tabs[i] or MakeTab(_strip)
        _tabs[i] = t
        t:ClearAllPoints()
        t:SetPoint("BOTTOMLEFT", _strip, "BOTTOMLEFT", S.x + (i - 1) * (w + S.gap), 0)
        FillTab(t, key, w, skin, k)
        t:Show()
    end
    if rest then
        _more:ClearAllPoints()
        _more:SetPoint("BOTTOMLEFT", _strip, "BOTTOMLEFT", S.x + shown * (w + S.gap), 0)
        FillMore(_more, rest, skin, moreW)
        _more:Show()
    end
    return keys   -- all of them: a slot in the menu is still a valid active key
end

-- BigNoteBox UI/ContextMenu.lua
-- Our own right-click menu (ALL-148), in place of Blizzard's Menu system, so
-- the look can follow normal mode, skin mode and later themes. It knows
-- nothing about notes: the note list's layout is UI/NoteContextMenu.lua.
--
-- Sub-menus open on hover beside their row, Windows 11 style, and flip to
-- the other side at the screen edge. Moving the pointer diagonally across a
-- sibling row on the way into an open sub-menu does not close it: the switch
-- waits SWITCH_DELAY and is cancelled when the pointer reaches the sub-menu.
--
-- Public API:
--   BNB.ContextMenu.Open(owner, build, after)
--     owner : the frame right-clicked (the menu closes when it hides)
--     build : function(root), fills the menu through the methods below
--     after : optional function, runs after any item's click (the Oracle
--             bar closes itself with it)
--   BNB.ContextMenu.Close()
--   BNB.ContextMenu.IsOpen()
--   BNB.ContextMenu.IsMouseOver()   pointer over any open level
--   owner._cmToggle = true: a button that opens and closes its menu itself
--     (a press on it does not count as a click outside)
--   owner._cmDropLeft = true: the menu opens under the owner, right edges
--     lined up, and its sub-menus open to the left
--   owner._cmDropDown = true: the menu opens under the owner, left edges
--     lined up, down and to the right (a dropdown button)
--   opts.keepOpen = true (a radio): the click leaves the menu open and the
--     marks are read again, for lists where several get ticked in one go
--   root:CreateButton(text, fn, { iconTex = path }): a picture instead of a
--     cm- symbol, no plate (tinted in the skin look); iconColor = { r, g, b }
--     draws it in that colour in both looks (the tag colour swatch, ALL-106);
--     iconGold = true: white art drawn in the toolbar icons' gold in the
--     normal look (skin look: tinted as always);
--     iconW / iconH = its size (default the row icon's), iconCoord = { l, r,
--     t, b } a part of it; a wider one moves the text of every row in the level
--
-- Building (names follow Blizzard's MenuUtil, so a menu moves over with few
-- changes, e.g. the Tag Manager's extraTop):
--   root:CreateTitle(text, opts)          header row
--     opts.icon      texture path or file id; opts.iconSetup(tex, badge) draws
--                    it instead (portraits); opts.crop = false keeps the icon edge
--     opts.badge     the icon as the sticky's badge: bordered, over the corner
--     opts.color     { r, g, b } text colour (a note's titleColor), nil = gold
--   item opts.danger = red label (automatic for the "danger" icon)
--   root:CreateButton(text, onClick, opts) -> item
--     onClick nil on a parent = a click opens its sub-menu
--     opts.icon      "note", "create"... = Assets\ContextMenu\Symbols\cm-<icon>
--                    on a Layers\cm-background-* plate (normal look only)
--     opts.disabled  greyed, no click, no sub-menu
--     opts.tip, opts.tipSub   tooltip
--   item:CreateButton(...) / item:CreateDivider()   makes item a sub-menu
--   root:CreateRadio(text, isSelected, onSelect, opts) -> item
--     a choice with a round mark, filled while isSelected() returns true;
--     a click runs onSelect and closes the menu (the task Reset / Situation);
--     opts.iconTex = a picture after the mark (the explorer's View menu;
--     iconGold = true draws white art gold in the normal look, as on buttons),
--     every row's text in that level moves over to make room
--   root:CreateCheckbox(text, isSelected, onSelect, opts) -> item
--     a radio with a check mark: an on / off setting (onSelect flips it)
--   root:CreateDivider()
--   root:CreateIconRow() -> row        icons side by side, Windows 11 style
--     row:AddIcon(icon, onClick, opts)  (the note menu's Favorite ... Delete
--     permanently, ALL-571): the cm-<icon> symbol alone, no plate; opts.tip /
--     tipSub = tooltip, opts.disabled, opts.danger = red tooltip, opts.gap =
--     the first icon of the right-hand group: icons before it sit on the left
--     edge, it and the rest on the right edge, a thin line between (one gap)
--
-- Closes on: a click on an item, a click outside every open level, ESC
-- (deepest level first), the owner hiding. In combat ESC goes to the game
-- (BNB.AttachEscClose).
--------------------------------------------------------------------------------

local BNB = BigNoteBox

local CM = {}
BNB.ContextMenu = CM

local ART     = "Interface\\AddOns\\BigNoteBox\\Assets\\ContextMenu\\"
local LAYERS  = ART .. "Layers\\"    -- cm-background-inactive/-active/-warning, -highlight
local SYMBOLS = ART .. "Symbols\\"   -- cm-<icon>, 64x64 on the plate's canvas
local ARROW   = "Interface\\ChatFrame\\ChatFrameExpandArrow"
local RADIO   = "Interface\\Common\\UI-DropDownRadioChecks"   -- top half: on 0-.5, off .5-1
local WARNING  = { danger = true }   -- red plate on hover (Delete permanently)
local UNTINTED = { danger = true }   -- skin look keeps the red

local ROW_H, TITLE_H, DIV_H = 20, 24, 9
local IROW_H, IBTN, ISYM = 30, 26, 20   -- icon row: row height, button, symbol
local IBTN_SP, IROW_GAP  = 4, 12        -- space between icons, extra before a gap (holds a line)
local PAD      = 4      -- frame edge to rows
local ICON     = 18     -- row icon size
local TITLE_IC = 20     -- header icon size
local ARROW_W  = 12
local MIN_W, MAX_W = 140, 320   -- row width limits (text truncates past MAX)
-- A long title (a note's name) widens the menu this far at most and is cut
-- with "..." past it; the entries still size the menu (Dukul, 2026-10-03)
local TITLE_MAX_W = 220
-- Hover on a parent before its sub-menu opens: BigNoteBoxDB.contextMenuDelay,
-- default 0.10 (L3: 0.15 felt long), set on the Modules page
local function OpenDelay()
    local v = BigNoteBoxDB and BigNoteBoxDB.contextMenuDelay
    return v or BNB.DEFAULTS.contextMenuDelay
end
local SWITCH_DELAY = 0.30       -- grace while crossing a sibling diagonally
local OVERLAP  = 2              -- a sub-menu overlaps its parent by this
local STRATA   = "FULLSCREEN_DIALOG"
local SKIN_SYM_MULT = 1         -- skin icon tint = the preset border, as the dividers (Dukul, L18)
local SKIN_HOVER_LIFT = 0.5     -- skin look on hover: icon and arrow this far toward white (Dukul)
local DANGER_TEXT = { 1, 0.32, 0.32 }   -- label of a WARNING row, like its red symbol (L18)
-- Header badge, as the sticky's icon badge: overhangs the top-left corner
local BADGE, BADGE_INSET, BADGE_PAD = 36, 6, 2
local BADGE_TITLE_H = 26

local BACKDROP = {
    bgFile   = "Interface\\Buttons\\White8x8",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = false, tileSize = 0, edgeSize = 14,
    insets = { left = 3, right = 3, top = 3, bottom = 3 },
}

--------------------------------------------------------------------------------
-- DESCRIPTIONS (what the build function fills)
--------------------------------------------------------------------------------
local Desc = {}
Desc.__index = Desc

local function NewDesc(kind, text, fn, opts)
    return setmetatable({ kind = kind, text = text, fn = fn, opts = opts or {}, items = {} }, Desc)
end

function Desc:CreateButton(text, onClick, opts)
    local d = NewDesc("button", text, onClick, opts)
    self.items[#self.items + 1] = d
    return d
end

function Desc:CreateTitle(text, opts)
    local d = NewDesc("title", text, nil, opts)
    self.items[#self.items + 1] = d
    return d
end

function Desc:CreateRadio(text, isSelected, onSelect, opts)
    local d = NewDesc("radio", text, onSelect, opts)
    d.isSelected = isSelected
    self.items[#self.items + 1] = d
    return d
end

-- A radio with a check mark (the bottom half of RADIO) instead of the round
-- one: an on / off setting (the explorer's Pinned notes first, 2026-10-22)
function Desc:CreateCheckbox(text, isSelected, onSelect, opts)
    local d = self:CreateRadio(text, isSelected, onSelect, opts)
    d.check = true
    return d
end

-- The radio / check mark, on or off
local function SetMark(mark, it, on)
    local t0 = it.check and 0.5 or 0
    mark:SetTexCoord(on and 0 or 0.5, on and 0.5 or 1, t0, t0 + 0.5)
end

function Desc:CreateDivider()
    local d = NewDesc("divider")
    self.items[#self.items + 1] = d
    return d
end

-- A row of icons (ALL-571): one menu row, each icon a button of its own
function Desc:CreateIconRow()
    local d = NewDesc("iconrow")
    d.icons = {}
    self.items[#self.items + 1] = d
    return d
end

function Desc:AddIcon(icon, onClick, opts)
    local d = { icon = icon, fn = onClick, opts = opts or {} }
    self.icons[#self.icons + 1] = d
    return d
end

-- A sub-menu with only dividers would open empty
local function HasSub(d)
    for _, it in ipairs(d.items) do
        if it.kind ~= "divider" then return true end
    end
    return false
end

--------------------------------------------------------------------------------
-- STATE
--------------------------------------------------------------------------------
local _levels = {}   -- [i] = level frame, reused
local _open   = 0    -- deepest open level, 0 = closed
local _owner        -- frame the menu belongs to
local _skin   = false
local _timer        -- pending open/switch
local _watch        -- GLOBAL_MOUSE_DOWN listener
local _after        -- runs after an item's click (CM.Open's third argument)
-- Owners that have our OnHide hook. A table, not a field on the owner: one of
-- them is BigChatBox's edit box (ChatCapture), another addon's frame
local _hideHooked = setmetatable({}, { __mode = "k" })

local function Cancel()
    if _timer then _timer:Cancel(); _timer = nil end
end

local function Schedule(delay, fn)
    Cancel()
    _timer = C_Timer.NewTimer(delay, function() _timer = nil; fn() end)
end

local function SkinColours()
    local p = BNB.GetSkinPreset()
    local fr, fg, fb = BNB.SkinColourOf(p, false)
    local br, bg_, bb, ba = BNB.SkinBorderOf(p)
    return fr, fg, fb, br, bg_, bb, ba
end

--------------------------------------------------------------------------------
-- ROW LOOK
--------------------------------------------------------------------------------
-- Normal look: plate (rest / hover, the red warning plate on hover for WARNING
-- icons) + symbol. Skin look: the symbol alone, tinted to the preset like the
-- skin icon buttons; UNTINTED symbols keep their colours (Dukul's art, 2026-10-03)
-- Skin look: tex desaturated and tinted to the preset border, lighter on hover
local function SkinTint(tex, active)
    local _, _, _, br, bg_, bb = SkinColours()
    local m, lift = SKIN_SYM_MULT, active and SKIN_HOVER_LIFT or 0
    local function c(v) v = math.min(1, v * m); return v + (1 - v) * lift end
    tex:SetDesaturated(true)
    tex:SetVertexColor(c(br), c(bg_), c(bb))
end

-- The sub-menu arrow: Blizzard's art in the normal look, tinted in the skin look
local function DrawArrow(row, active)
    local a = row._arrow
    if _skin then SkinTint(a, active)
    else a:SetDesaturated(false); a:SetVertexColor(1, 1, 1) end
end

local function DrawIcon(row, active)
    local key = row._iconKey
    if not key then return end
    -- A picture of its own (opts.iconTex, the top bar menu's icons): no plate,
    -- tinted like the symbols in the skin look, greyed when disabled
    if row._iconTex then
        local sym = row._icon
        row._plate:Hide()
        sym:SetTexture(row._iconTex)
        if row._iconCoord then sym:SetTexCoord(unpack(row._iconCoord)) end
        local col = row._iconColor
        if row._disabled then
            sym:SetDesaturated(true); sym:SetVertexColor(0.45, 0.45, 0.45)
        elseif col then   -- a colour swatch keeps its colour in both looks
            sym:SetDesaturated(false); sym:SetVertexColor(col[1], col[2], col[3])
        elseif _skin then
            SkinTint(sym, active)
        elseif row._iconGold then   -- white art in the toolbar icons' gold
            local g = BNB.ICON_GOLD
            sym:SetDesaturated(false); sym:SetVertexColor(g[1], g[2], g[3])
        else
            sym:SetDesaturated(false); sym:SetVertexColor(1, 1, 1)
        end
        return
    end
    local plate, sym = row._plate, row._icon
    sym:SetTexture(SYMBOLS .. "cm-" .. key)
    plate:SetShown(not _skin)
    if not _skin then
        plate:SetTexture(LAYERS .. "cm-background-"
            .. (active and (WARNING[key] and "warning" or "active") or "inactive"))
    end
    local dim = row._disabled
    plate:SetDesaturated(dim)
    plate:SetVertexColor(dim and 0.5 or 1, dim and 0.5 or 1, dim and 0.5 or 1)
    if dim then
        sym:SetDesaturated(true)
        sym:SetVertexColor(0.45, 0.45, 0.45)
    elseif _skin and not UNTINTED[key] then
        SkinTint(sym, active)
    else
        sym:SetDesaturated(false)
        sym:SetVertexColor(1, 1, 1)
    end
end

-- Hovered, or the parent of the open sub-menu
local function SetRowActive(row, on)
    if row._active == on then return end
    row._active = on
    row._hl:SetShown(on)
    DrawIcon(row, on)
    if row._hasSub then DrawArrow(row, on) end
end

local function ApplyRowLook(row)
    local hl = row._hl
    if _skin then
        local _, _, _, br, bg_, bb = SkinColours()
        hl:SetColorTexture(br, bg_, bb, 0.25)
        row._div:SetColorTexture(br, bg_, bb, 0.6 * BNB.SkinRuleAlphaOf(BNB.GetSkinPreset()))
    else
        hl:SetTexture(LAYERS .. "cm-background-highlight")
        hl:SetTexCoord(0, 1, 0, 1)
        hl:SetVertexColor(1, 1, 1, 1)
        row._div:SetColorTexture(0.45, 0.45, 0.45, 0.6)
    end
end

--------------------------------------------------------------------------------
-- LEVELS
--------------------------------------------------------------------------------
local CloseFrom, ShowLevel

local function RowParentOf(level)
    local f = _levels[level]
    return f and f:IsShown() and f._parentRow or nil
end

local function ShowTip(row)
    local o = row._desc and row._desc.opts
    if not (o and o.tip) then return end
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    GameTooltip:AddLine(o.tip, 1, 1, 1)
    if o.tipSub then GameTooltip:AddLine(o.tipSub, 0.78, 0.78, 0.78, true) end
    GameTooltip:Show()
end

local function RowEnter(row)
    local i = row:GetParent()._level
    ShowTip(row)
    if row._disabled then
        -- A disabled row still ends a sub-menu the pointer has left behind
        if _open > i then
            Schedule(SWITCH_DELAY, function() if row:IsMouseOver() then CloseFrom(i + 1) end end)
        else
            Cancel()
        end
        return
    end
    SetRowActive(row, true)
    if _open > i and RowParentOf(i + 1) == row then Cancel(); return end   -- its own sub-menu
    if row._hasSub then
        Schedule(_open > i and SWITCH_DELAY or OpenDelay(), function()
            if row:IsMouseOver() then ShowLevel(i + 1, row._desc, row) end
        end)
    elseif _open > i then
        Schedule(SWITCH_DELAY, function() if row:IsMouseOver() then CloseFrom(i + 1) end end)
    else
        Cancel()   -- also ends a switch pending from the level above
    end
end

local function RowLeave(row)
    if GameTooltip:IsOwned(row) then GameTooltip:Hide() end
    local i = row:GetParent()._level
    if not (_open > i and RowParentOf(i + 1) == row) then SetRowActive(row, false) end
end

-- Round marks of every open level, read again (after a keepOpen click)
local function RefreshMarks()
    for k = 1, _open do
        for _, r in ipairs(_levels[k] and _levels[k]._rows or {}) do
            local it = r:IsShown() and r._desc
            if it and it.kind == "radio" then
                SetMark(r._mark, it, it.isSelected and it.isSelected() and true or false)
            end
        end
    end
end

local function RowClick(row)
    local d = row._desc
    if row._disabled or not d then return end
    if d.fn and d.opts.keepOpen then
        -- Several to tick in one go (the top bar's Show on top bar, ALL-112)
        xpcall(d.fn, geterrorhandler())
        RefreshMarks()
    elseif d.fn then
        local after = _after
        CM.Close()
        xpcall(d.fn, geterrorhandler())
        if after then xpcall(after, geterrorhandler()) end
    elseif row._hasSub then
        local i = row:GetParent()._level
        if RowParentOf(i + 1) ~= row then Cancel(); ShowLevel(i + 1, d, row) end
    end
end

-- ICON ROW BUTTONS (ALL-571) ------------------------------------------------
-- The symbol alone (Dukul: "without the button layer part"); hover = the
-- row highlight behind it. Skin look: tinted like the row symbols
local function DrawIconBtn(b, active)
    local ic, sym, hl = b._desc, b._sym, b._hl
    sym:SetTexture(SYMBOLS .. "cm-" .. ic.icon)
    if _skin then
        local _, _, _, br, bg_, bb = SkinColours()
        hl:SetColorTexture(br, bg_, bb, 0.25)
    else
        hl:SetTexture(LAYERS .. "cm-background-highlight")
        hl:SetVertexColor(1, 1, 1, 1)
    end
    hl:SetShown(active and not b._disabled)
    if b._disabled then
        sym:SetDesaturated(true); sym:SetVertexColor(0.45, 0.45, 0.45)
    elseif _skin and not UNTINTED[ic.icon] then
        SkinTint(sym, active)
    else
        sym:SetDesaturated(false); sym:SetVertexColor(1, 1, 1)
    end
end

local function IconBtnEnter(b)
    local ic = b._desc
    local i = b:GetParent():GetParent()._level
    if ic.opts.tip then
        GameTooltip:SetOwner(b, "ANCHOR_TOP")
        if ic.opts.danger or WARNING[ic.icon] then
            GameTooltip:AddLine(ic.opts.tip, DANGER_TEXT[1], DANGER_TEXT[2], DANGER_TEXT[3])
        else
            GameTooltip:AddLine(ic.opts.tip, 1, 1, 1)
        end
        if ic.opts.tipSub then GameTooltip:AddLine(ic.opts.tipSub, 0.78, 0.78, 0.78, true) end
        GameTooltip:Show()
    end
    DrawIconBtn(b, true)
    -- As a row without a sub-menu: an open sub-menu closes after the grace
    if _open > i then
        Schedule(SWITCH_DELAY, function() if b:IsMouseOver() then CloseFrom(i + 1) end end)
    else
        Cancel()
    end
end

local function IconBtnLeave(b)
    if GameTooltip:IsOwned(b) then GameTooltip:Hide() end
    DrawIconBtn(b, false)
end

local function IconBtnClick(b)
    local ic = b._desc
    if b._disabled or not (ic and ic.fn) then return end
    local after = _after
    CM.Close()
    xpcall(ic.fn, geterrorhandler())
    if after then xpcall(after, geterrorhandler()) end
end

local function IconBtn(r, k)
    r._ib = r._ib or {}
    local b = r._ib[k]
    if b then return b end
    b = CreateFrame("Button", nil, r)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:SetSize(IBTN, IBTN)
    b._hl = b:CreateTexture(nil, "BACKGROUND")
    b._hl:SetAllPoints()
    b._hl:Hide()
    b._sym = b:CreateTexture(nil, "ARTWORK")
    b._sym:SetSize(ISYM, ISYM)
    b._sym:SetPoint("CENTER")
    b:SetScript("OnEnter", IconBtnEnter)
    b:SetScript("OnLeave", IconBtnLeave)
    b:SetScript("OnClick", IconBtnClick)
    r._ib[k] = b
    return b
end

local function NewRow(f)
    local r = CreateFrame("Button", nil, f)
    r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    r:SetHeight(ROW_H)
    r._hl = r:CreateTexture(nil, "BACKGROUND")
    r._hl:SetAllPoints()
    r._hl:Hide()
    r._plate = r:CreateTexture(nil, "ARTWORK", nil, 0)
    r._plate:SetSize(ICON, ICON)
    r._plate:SetPoint("LEFT", 4, 0)
    r._icon = r:CreateTexture(nil, "ARTWORK", nil, 1)
    r._mark = r:CreateTexture(nil, "ARTWORK", nil, 1)   -- radio mark
    r._mark:SetTexture(RADIO)
    r._mark:SetSize(16, 16)
    r._mark:SetPoint("LEFT", 5, 0)
    r._text = r:CreateFontString(nil, "OVERLAY", "BNBFontHighlight")
    r._text:SetJustifyH("LEFT")
    r._text:SetWordWrap(false)
    r._arrow = r:CreateTexture(nil, "ARTWORK")
    r._arrow:SetTexture(ARROW)
    r._arrow:SetSize(ARROW_W, ARROW_W)
    r._arrow:SetPoint("RIGHT", -4, 0)
    r._div = r:CreateTexture(nil, "ARTWORK")
    r._div:SetHeight(1)
    r._div:SetPoint("LEFT", 6, 0)
    r._div:SetPoint("RIGHT", -6, 0)
    r:SetScript("OnEnter", RowEnter)
    r:SetScript("OnLeave", RowLeave)
    r:SetScript("OnClick", RowClick)
    return r
end

local function NewLevel(i)
    local f = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    f:SetFrameStrata(STRATA)
    f:SetToplevel(true)
    f:SetClampedToScreen(true)
    f:EnableMouse(true)   -- clicks on the padding do not fall through
    f:Hide()
    f._level, f._rows = i, {}
    if i == 1 then
        BNB.AttachEscClose(f, function()
            if _open > 1 then CloseFrom(_open) else CM.Close() end
        end)
    end
    return f
end

local function TextWidth(fs)
    return fs.GetUnboundedStringWidth and fs:GetUnboundedStringWidth() or fs:GetStringWidth()
end

-- The level frame and the header badge share one box
local function Paint(f)
    f:SetBackdrop(BACKDROP)
    if _skin then
        local fr, fg, fb, br, bg_, bb, ba = SkinColours()
        f:SetBackdropColor(fr, fg, fb, math.max(0.9, BNB.GetSkinBgAlpha()))
        f:SetBackdropBorderColor(br, bg_, bb, ba)
    else
        f:SetBackdropColor(0.06, 0.06, 0.06, 0.97)
        f:SetBackdropBorderColor(0.40, 0.40, 0.40, 1)
    end
end

local function Badge(f)
    local b = f._badge
    if not b then
        b = CreateFrame("Frame", nil, f, "BackdropTemplate")
        b:SetSize(BADGE, BADGE)
        b:SetPoint("TOPLEFT", f, "TOPLEFT", -BADGE_INSET, BADGE_INSET)
        b:EnableMouse(true)   -- a click on it is a click on the menu
        b._tex = b:CreateTexture(nil, "ARTWORK")
        b._tex:SetPoint("TOPLEFT", BADGE_PAD, -BADGE_PAD)
        b._tex:SetPoint("BOTTOMRIGHT", -BADGE_PAD, BADGE_PAD)
        b._tex._size = BADGE - 2 * BADGE_PAD   -- two-anchor sized (ApplyIconFrame)
        f._badge = b
    end
    b:SetFrameLevel(f:GetFrameLevel() + 10)
    return b
end

-- Fills level f from description d; returns its size
local function Fill(f, d)
    local hasIcons, iconCol, radioPic = false, ICON, false
    for _, it in ipairs(d.items) do
        if (it.kind == "button" and (it.opts.icon or it.opts.iconTex)) or it.kind == "radio" then hasIcons = true end
        -- A wider picture (the tag colour swatches) moves every row's text
        if it.kind == "button" and it.opts.iconTex and it.opts.iconW then iconCol = math.max(iconCol, it.opts.iconW) end
        if it.kind == "radio" and it.opts.iconTex then radioPic = true end
    end
    local textX = hasIcons and (4 + iconCol + 6) or 10
    local radioPicX = textX   -- a radio's picture sits where the text would start
    if radioPic then textX = textX + ICON + 6 end
    if f._badge then f._badge:Hide() end

    -- First pass: rows set up and measured
    local w = MIN_W
    for n, it in ipairs(d.items) do
        local r = f._rows[n] or NewRow(f)
        f._rows[n] = r
        r._desc, r._active, r._iconKey, r._iconTex, r._iconColor = it, nil, nil, nil, nil
        r._iconGold = it.opts and it.opts.iconGold or nil
        r._iconCoord = nil
        r._disabled, r._hasSub = false, false
        r._hl:Hide()
        r._div:Hide(); r._arrow:Hide(); r._icon:Hide(); r._plate:Hide(); r._text:Hide(); r._mark:Hide()
        if r._ib then for _, b in ipairs(r._ib) do b:Hide() end end
        if r._gapHost then r._gapHost:Hide(); r._gapHost._ln:Hide() end
        r._icon:SetDesaturated(false); r._icon:SetVertexColor(1, 1, 1); r._icon:SetTexCoord(0, 1, 0, 1)
        r._text:ClearAllPoints()
        ApplyRowLook(r)
        if it.kind == "divider" then
            r:SetHeight(DIV_H); r:EnableMouse(false)
            r._div:Show()
        elseif it.kind == "iconrow" then
            -- The row takes no mouse: its icons are the buttons (ALL-571)
            r:SetHeight(IROW_H); r:EnableMouse(false)
            -- Icons before the first gap stick to the left edge, the gap and
            -- the rest to the right edge, the line centred between the two
            -- groups (Dukul, 2026-10-26: no empty space on the right). The
            -- row only knows its width after every row is measured, so the
            -- right group is anchored to the row's right edge
            local split
            for k, ic in ipairs(it.icons) do
                if ic.opts.gap and k > 1 then split = k; break end
            end
            local nLeft = (split or (#it.icons + 1)) - 1
            local x, lastLeft, firstRight = 4, nil, nil
            for k, ic in ipairs(it.icons) do
                local b = IconBtn(r, k)
                b._desc, b._disabled = ic, ic.opts.disabled and true or false
                b:ClearAllPoints()
                if k <= nLeft then
                    b:SetPoint("LEFT", r, "LEFT", x, 0)
                    lastLeft = b
                else
                    local fromRight = 4 + (#it.icons - k) * (IBTN + IBTN_SP)
                    b:SetPoint("RIGHT", r, "RIGHT", -fromRight, 0)
                    firstRight = firstRight or b
                end
                DrawIconBtn(b, false)
                b:Show()
                x = x + IBTN + IBTN_SP
            end
            if split then
                x = x + IROW_GAP
                if lastLeft and firstRight then
                    -- A thin upright line in the middle of the gap (Dukul, 2026-10-26)
                    local host = r._gapHost
                    if not host then
                        host = CreateFrame("Frame", nil, r)
                        host:SetHeight(1)
                        host._ln = r:CreateTexture(nil, "ARTWORK")
                        host._ln:SetSize(1, IBTN - 8)
                        host._ln:SetPoint("CENTER", host, "CENTER", 0, 0)
                        r._gapHost = host
                    end
                    local ln = host._ln
                    if _skin then
                        local _, _, _, br, bg_, bb = SkinColours()
                        ln:SetColorTexture(br, bg_, bb, 0.6 * BNB.SkinRuleAlphaOf(BNB.GetSkinPreset()))
                    else
                        ln:SetColorTexture(0.45, 0.45, 0.45, 0.6)   -- as the divider rows
                    end
                    host:ClearAllPoints()
                    host:SetPoint("LEFT", lastLeft, "RIGHT", 0, 0)
                    host:SetPoint("RIGHT", firstRight, "LEFT", 0, 0)
                    host:Show(); ln:Show()
                end
            end
            w = math.max(w, x - IBTN_SP + 4)
        elseif it.kind == "title" then
            r:SetHeight(TITLE_H); r:EnableMouse(false)
            r._text:SetFontObject("BNBFontNormal")
            local tc = it.opts.color   -- { r, g, b }, e.g. the note's titleColor
            if tc then r._text:SetTextColor(tc.r, tc.g, tc.b)
            else BNB.SetHeaderColor(r._text) end
            r._text:SetText(it.text or "")
            r._text:Show()
            local o, x = it.opts, 8
            if o.badge and (o.icon or o.iconSetup) then
                local b = Badge(f)
                local tex = b._tex
                tex:SetTexCoord(0, 1, 0, 1); tex:SetDesaturated(false); tex:SetVertexColor(1, 1, 1)
                Paint(b)
                if o.iconSetup then
                    o.iconSetup(tex, b)   -- b: room for a note's icon frame or border
                else
                    -- The badge is reused: drop a note's icon frame / edge border
                    if BNB.ApplyIconFrame then BNB.ApplyIconFrame(tex, nil) end
                    if b._borderOverlay then b._borderOverlay:Hide() end
                    tex:SetTexture(o.icon)
                    if o.crop ~= false then tex:SetTexCoord(0.07, 0.93, 0.07, 0.93) end
                end
                b:Show()
                r:SetHeight(BADGE_TITLE_H)
                x = BADGE - BADGE_INSET - PAD + 6
            elseif o.icon or o.iconSetup then
                r._icon:SetSize(TITLE_IC, TITLE_IC)
                r._icon:ClearAllPoints()
                r._icon:SetPoint("LEFT", 6, 0)
                if o.iconSetup then
                    o.iconSetup(r._icon)
                else
                    r._icon:SetTexture(o.icon)
                    if o.crop ~= false then r._icon:SetTexCoord(0.07, 0.93, 0.07, 0.93) end
                end
                r._icon:Show()
                x = 6 + TITLE_IC + 6
            end
            r._text:SetPoint("LEFT", x, 0)
            r._text:SetPoint("RIGHT", -8, 0)
            w = math.max(w, math.min(TITLE_MAX_W, x + TextWidth(r._text) + 8))
        else
            r:SetHeight(ROW_H); r:EnableMouse(true)
            r._disabled = it.opts.disabled and true or false
            r._hasSub = HasSub(it) and not r._disabled
            r._text:SetFontObject(r._disabled and "GameFontDisable" or "BNBFontHighlight")
            if r._disabled then
                r._text:SetTextColor(0.5, 0.5, 0.5)
            elseif it.opts.danger or WARNING[it.opts.icon or ""] then
                r._text:SetTextColor(DANGER_TEXT[1], DANGER_TEXT[2], DANGER_TEXT[3])
            else
                BNB.SetTextWhite(r._text)
            end
            r._text:SetText(it.text or "")
            r._text:Show()
            if it.kind == "radio" then
                SetMark(r._mark, it, it.isSelected and it.isSelected() and true or false)
                if _skin then   -- tinted like the dividers
                    local _, _, _, br, bg_, bb = SkinColours()
                    r._mark:SetDesaturated(true); r._mark:SetVertexColor(br, bg_, bb)
                else
                    r._mark:SetDesaturated(false); r._mark:SetVertexColor(1, 1, 1)
                end
                r._mark:Show()
                if it.opts.iconTex then
                    r._iconKey, r._iconTex = "tex", it.opts.iconTex
                    r._icon:SetSize(ICON, ICON)
                    r._icon:ClearAllPoints()
                    r._icon:SetPoint("LEFT", radioPicX, 0)
                    r._icon:Show()
                    DrawIcon(r, false)
                end
            elseif it.opts.icon or it.opts.iconTex then
                r._iconKey = it.opts.icon or "tex"
                r._iconTex = it.opts.iconTex
                r._iconColor = it.opts.iconTex and it.opts.iconColor or nil
                local o = it.opts
                if o.iconTex then
                    r._icon:SetSize(o.iconW or ICON, o.iconH or ICON)
                else
                    r._icon:SetSize(ICON, ICON)
                end
                r._icon:ClearAllPoints()
                -- Among radios with pictures (the explorer's Sort menu), a
                -- button's picture lines up with theirs, not with the marks
                local picCol = radioPic and o.iconTex and not o.iconW
                r._icon:SetPoint("LEFT", picCol and radioPicX or 4, 0)
                r._icon:Show()
                r._iconCoord = o.iconTex and o.iconCoord or nil
                DrawIcon(r, false)   -- shows the plate in the normal look
            end
            local right = r._hasSub and (4 + ARROW_W + 4) or 10
            r._arrow:SetShown(r._hasSub)
            if r._hasSub then DrawArrow(r, false) end
            r._text:SetPoint("LEFT", textX, 0)
            r._text:SetPoint("RIGHT", -right, 0)
            w = math.max(w, textX + TextWidth(r._text) + right)
        end
    end
    for n = #d.items + 1, #f._rows do f._rows[n]:Hide() end

    -- Second pass: stack them
    w = math.min(MAX_W, math.ceil(w))
    local y = -PAD
    for n = 1, #d.items do
        local r = f._rows[n]
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", PAD, y)
        r:SetWidth(w)
        r:Show()
        y = y - r:GetHeight()
    end
    return w + PAD * 2, -y + PAD
end

-- Level 1 at the pointer, a sub-menu beside its row; both kept on screen
local function Place(f, w, h, row)
    local sw, sh = UIParent:GetWidth(), UIParent:GetHeight()
    local left, top
    local dropLeft = _owner and _owner._cmDropLeft
    local dropDown = _owner and _owner._cmDropDown
    if not row and dropDown and _owner:GetLeft() then
        -- Under its owner, left edges lined up, opening down and to the right
        -- (the explorer's tool buttons, Dukul 2026-10-21); kept on screen
        local k = _owner:GetEffectiveScale() / f:GetEffectiveScale()
        left, top = _owner:GetLeft() * k, _owner:GetBottom() * k - 2
        if left + w > sw then left = sw - w end
    elseif not row and dropLeft and _owner:GetRight() then
        -- Under its owner, right edges lined up, so it opens down and to the
        -- left, into the window (the top bar menu, ALL-112)
        local k = _owner:GetEffectiveScale() / f:GetEffectiveScale()
        left, top = _owner:GetRight() * k - w, _owner:GetBottom() * k - 2
        if left < 0 then left = 0 end
    elseif not row then
        local cx, cy = GetCursorPosition()
        local sc = f:GetEffectiveScale()
        left, top = cx / sc, cy / sc
        if left + w > sw then left = left - w end
        if top - h < 0 then top = top + h end   -- opens upward from the pointer
    else
        local pf = row:GetParent()
        if dropLeft then   -- sub-menus open to the left too, flipping at the screen edge
            left = pf:GetLeft() - w + OVERLAP
            if left < 0 then left = pf:GetRight() - OVERLAP end
        else
            left = pf:GetRight() - OVERLAP
            if left + w > sw then left = pf:GetLeft() - w + OVERLAP end
        end
        top = row:GetTop() + PAD
    end
    -- The header badge sticks out past the top-left corner: keep it on screen too
    local m = (f._badge and f._badge:IsShown()) and BADGE_INSET or 0
    if top - h < 0 then top = h end
    if top > sh - m then top = sh - m end
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", math.max(m, left), top)
end

function CloseFrom(i)
    for k = _open, i, -1 do
        local f = _levels[k]
        if f then
            f:Hide()
            local pr = f._parentRow
            f._parentRow = nil
            if pr and not pr:IsMouseOver() then SetRowActive(pr, false) end
        end
    end
    if _open >= i then _open = i - 1 end
end

function ShowLevel(i, d, row)
    CloseFrom(i)
    local f = _levels[i] or NewLevel(i)
    _levels[i] = f
    -- On WorldFrame while Focus mode hides UIParent (ALL-163), before Place
    -- reads the scale
    BNB.SeatWindow(f, STRATA)
    f._parentRow = row
    Paint(f)
    local w, h = Fill(f, d)
    f:SetSize(w, h)
    Place(f, w, h, row)
    f:Show()
    f:Raise()
    _open = i
    if row then SetRowActive(row, true) end
end

--------------------------------------------------------------------------------
-- PUBLIC
--------------------------------------------------------------------------------
function CM.IsOpen()
    return _open > 0
end

-- Pointer over the menu (header badge included): a click there is ours, so
-- a host that closes on outside clicks (the Oracle bar) leaves it alone
function CM.IsMouseOver()
    for k = 1, _open do
        local f = _levels[k]
        if f:IsMouseOver() or (f._badge and f._badge:IsShown() and f._badge:IsMouseOver()) then
            return true
        end
    end
    return false
end

function CM.Close()
    Cancel()
    CloseFrom(1)
    _owner, _after = nil, nil
    if _watch then _watch:UnregisterEvent("GLOBAL_MOUSE_DOWN") end
end

local function Watch()
    if not _watch then
        _watch = CreateFrame("Frame")
        _watch:SetScript("OnEvent", function()
            -- An owner marked _cmToggle (the top bar menu button, ALL-112)
            -- closes the menu with its own click, so a press on it is left alone
            if CM.IsMouseOver() then return end
            if _owner and _owner._cmToggle and _owner:IsMouseOver() then return end
            CM.Close()
        end)
    end
    -- Next frame, so the click that opened the menu cannot close it
    C_Timer.After(0, function()
        if _open > 0 then pcall(_watch.RegisterEvent, _watch, "GLOBAL_MOUSE_DOWN") end
    end)
end

function CM.Open(owner, build, after)
    CM.Close()
    local root = NewDesc("root")
    build(root)
    if not HasSub(root) then return end
    _skin = BigNoteBoxDB and BigNoteBoxDB.skinMode and true or false
    _owner, _after = owner, after
    -- The owner's hover tooltip sits in a higher strata and would cover the
    -- menu (Reference Box entries, Dukul, 2026-10-18)
    if owner and GameTooltip:IsOwned(owner) then GameTooltip:Hide() end
    if owner and owner.HookScript and not _hideHooked[owner] then
        _hideHooked[owner] = true
        owner:HookScript("OnHide", function(self)
            if _owner == self then CM.Close() end
        end)
    end
    ShowLevel(1, root, nil)
    Watch()
end

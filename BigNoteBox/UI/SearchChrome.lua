-- BigNoteBox UI/SearchChrome.lua -- Search bar themes (ALL-69) and their layout tool
--
-- The Oracle search bar comes in themes the player picks from. A theme is a
-- folder of art: a 9-slice (four corners, four edges, a background) plus an
-- ornament, a decoration drawn on top of the borders (Eye of Kilrogg: the eye
-- over the top-left corner). Every piece is placed by two points relative to
-- the bar frame: its TOPLEFT goes to frame point a1 + (x1, y1) and its
-- BOTTOMRIGHT to frame point a2 + (x2, y2). Corners hang off one frame corner
-- and keep their size; edges and the background hang off two and stretch
-- with the bar.
--
-- Themes are registered in Assets\Search\SearchThemes.lua (loads after this
-- file) through BigNoteBox.RegisterSearchTheme, the same call another addon
-- can make. BNB.ApplySearchChrome(f, themeID) draws a theme on any frame; the
-- real search bar will call it. /bnb searchlayout (debug mode) opens a
-- preview where each piece can be moved and resized; Export hands back a
-- ready RegisterSearchTheme call.

local BNB = BigNoteBox

local ASSETS = "Interface\\AddOns\\BigNoteBox\\Assets\\Search\\"

-- Draw order: first in the list is drawn lowest.
-- A piece the theme's layout leaves out is not drawn. That is how the
-- optional ones work: a theme with a middle piece on its top edge
-- (topornament) splits the edge around it, `top` running from the left
-- corner to the middle piece and `top2` (same art as `top`) from the middle
-- piece to the right corner; bottom likewise. A theme without them draws
-- `top` corner to corner and leaves top2 / topornament out. Pieces with
-- `same` use that piece's art, including a theme's files override for it.
local PIECES = {
    { key = "bg",             file = "s-bg",              layer = "BACKGROUND", sub = 0 },
    { key = "top",            file = "s-top",             layer = "BORDER",     sub = 0 },
    { key = "top2",           file = "s-top",             layer = "BORDER",     sub = 0, same = "top" },
    { key = "bottom",         file = "s-bottom",          layer = "BORDER",     sub = 0 },
    { key = "bottom2",        file = "s-bottom",          layer = "BORDER",     sub = 0, same = "bottom" },
    { key = "left",           file = "s-left",            layer = "BORDER",     sub = 0 },
    { key = "right",          file = "s-right",           layer = "BORDER",     sub = 0 },
    { key = "topleft",        file = "s-top-left",        layer = "BORDER",     sub = 1 },
    { key = "topright",       file = "s-top-right",       layer = "BORDER",     sub = 1 },
    { key = "bottomleft",     file = "s-bottom-left",     layer = "BORDER",     sub = 1 },
    { key = "bottomright",    file = "s-bottom-right",    layer = "BORDER",     sub = 1 },
    { key = "topornament",    file = "s-top-ornament",    layer = "BORDER",     sub = 2 },
    { key = "bottomornament", file = "s-bottom-ornament", layer = "BORDER",     sub = 2 },
    { key = "ornament",       file = "s-ornament",        layer = "ARTWORK",    sub = 0 },
    { key = "text",           file = nil,                 layer = "ARTWORK",    sub = 1 },
}

-- Layouts are in native art pixels (32): every x offset is multiplied by
-- size.border / 32 and every y offset by size.borderY / 32, so a smaller
-- borderY makes corners and the top and bottom edges shorter without
-- touching their width. size.w / size.h are the bar itself. "text" is the
-- region the input field fills.
BNB.SEARCH_THEMES = {}
BNB.SEARCH_THEME_ORDER = {}
BNB.SEARCH_DEFAULT_THEME = "kilrogg"

-- BigNoteBox.RegisterSearchTheme(def) -> true, or false + reason
--   def.name    shown in the theme picker (required)
--   def.folder  folder under BigNoteBox\Assets\Search\, or
--   def.path    full texture path ending in "\\" (a theme shipped in another addon)
--   def.id      optional; defaults to the folder name in lower case
--   def.layout, def.size  optional; left out = the default theme's, which fits
--               any art drawn on the same 32 px grid
--   def.files   optional file name per piece; false = the theme has no such piece
--   def.highlight  optional { r, g, b, a } for the selected Oracle result;
--               left out = BNB gold
--   def.panelBg optional file name of a background for the Oracle results
--               panel only, tiled (never stretched), so a power-of-two
--               size; the Forever highlight glow is drawn over it. Left out
--               = the panel uses s-bg like the bar
-- Registering an id again replaces it and keeps its place in the list.
function BNB.RegisterSearchTheme(def)
    if type(def) ~= "table" or type(def.name) ~= "string" then return false, "name missing" end
    local art = def.path or (def.folder and (ASSETS .. def.folder .. "\\"))
    if not art then return false, "folder or path missing" end
    local id = def.id or (def.folder and def.folder:lower())
    if not id then return false, "id missing" end
    if not BNB.SEARCH_THEMES[id] then
        BNB.SEARCH_THEME_ORDER[#BNB.SEARCH_THEME_ORDER + 1] = id
    end
    BNB.SEARCH_THEMES[id] = {
        id = id, name = def.name, folder = def.folder, art = art,
        files = def.files, layout = def.layout, size = def.size,
        highlight = def.highlight, panelBg = def.panelBg,
    }
    return true
end

-- A missing or removed theme id falls back to the default, then to the first.
-- Ids are lower case; a saved "Horde" still finds "horde".
function BNB.GetSearchTheme(id)
    id = type(id) == "string" and id:lower() or ""
    return BNB.SEARCH_THEMES[id] or BNB.SEARCH_THEMES[BNB.SEARCH_DEFAULT_THEME]
        or BNB.SEARCH_THEMES[BNB.SEARCH_THEME_ORDER[1] or ""]
end

-- Selected-result colour of a theme: its own, else BNB gold.
local DEFAULT_HIGHLIGHT = { 1, 0.82, 0, 0.14 }
function BNB.GetSearchHighlight(id)
    local d = BNB.GetSearchTheme(id)
    local h = d and d.highlight
    if type(h) ~= "table" then h = DEFAULT_HIGHLIGHT end
    return h[1] or 1, h[2] or 0.82, h[3] or 0, h[4] or 0.14
end

-- A theme's layout and size, falling back to the default theme's.
local function ThemeLayout(d)
    local def = BNB.SEARCH_THEMES[BNB.SEARCH_DEFAULT_THEME] or d
    return d.layout or def.layout, d.size or def.size
end

local NATIVE = 32

local function PlacePiece(tex, f, p, kx, ky)
    kx = kx or 1
    ky = ky or kx
    tex:ClearAllPoints()
    tex:SetPoint("TOPLEFT", f, p.a1, p.x1 * kx, p.y1 * ky)
    tex:SetPoint("BOTTOMRIGHT", f, p.a2, p.x2 * kx, p.y2 * ky)
end

-- Draws (or re-draws) a theme on f and sizes f to it. layout / size override
-- the theme's own (the layout tool passes its working copy). The "text" piece
-- gets no texture: f._searchPieces.text is a bare region marker the caller
-- anchors its EditBox to. Switching theme on a live frame is fine.
-- opts.panel: the 9-slice only, for a frame the caller sizes itself (the
-- Oracle results panel): no ornament, no text region, no SetSize.
-- Returns the size table used, so a caller can pad by size.border.
function BNB.ApplySearchChrome(f, themeID, layout, size, opts)
    local d = BNB.GetSearchTheme(themeID)
    if not d then return end
    local tl, ts = ThemeLayout(d)
    layout, size = layout or tl, size or ts
    local panel = opts and opts.panel
    local kx, ky = size.border / NATIVE, (size.borderY or size.border) / NATIVE
    if not panel then f:SetSize(size.w, size.h) end
    f._searchPieces = f._searchPieces or {}
    for _, def in ipairs(PIECES) do
        local tex = f._searchPieces[def.key]
        if not tex then
            tex = f:CreateTexture(nil, def.layer, nil, def.sub)
            f._searchPieces[def.key] = tex
        end
        local file = def.file
        local fk = def.same or def.key
        if d.files and d.files[fk] ~= nil then file = d.files[fk] end
        -- The results panel's own background tiles instead of stretching.
        local tiled = panel and def.key == "bg" and d.panelBg ~= nil
        if tiled then file = d.panelBg end
        if file then
            if tiled then tex:SetTexture(d.art .. file, "REPEAT", "REPEAT")
            else tex:SetTexture(d.art .. file) end
            tex:SetHorizTile(tiled)
            tex:SetVertTile(tiled)
        end
        if def.file then tex:SetShown(file and true or false) end
        local p = layout[def.key]
        if panel and (def.key == "ornament" or def.key == "text") then p = nil end
        if p then PlacePiece(tex, f, p, kx, ky) else tex:Hide() end
    end
    -- The Forever background glow over a tiled results background, on
    -- both clients, above the background and below the border.
    local glow = f._searchPieces.panelglow
    if panel and d.panelBg then
        if not glow then
            glow = f:CreateTexture(nil, "BACKGROUND", nil, 7)
            glow:SetTexture(BNB.FOREVER_GLOW_TEXTURE)
            f._searchPieces.panelglow = glow
        end
        glow:ClearAllPoints()
        glow:SetAllPoints(f._searchPieces.bg)
        glow:SetShown(f._searchPieces.bg:IsShown())
    elseif glow then
        glow:Hide()
    end
    return size
end
BigNoteBox.RegisterSearchTheme = BNB.RegisterSearchTheme

--------------------------------------------------------------------------------
-- LAYOUT TOOL (debug mode only)
--------------------------------------------------------------------------------
local tool

local function CopyLayout(src)
    local out = {}
    for k, p in pairs(src) do
        out[k] = { a1 = p.a1, x1 = p.x1, y1 = p.y1, a2 = p.a2, x2 = p.x2, y2 = p.y2 }
    end
    return out
end

-- The working copy lives in BigNoteBoxDB, one per theme, so a /reload
-- keeps it. It starts as a copy of the theme's built-in layout.
local function WorkLayout()
    local db = BigNoteBoxDB
    db.devSearchLayout, db.devSearchSize = nil, nil   -- pre-theme keys (never shipped)
    db.devSearch = db.devSearch or {}
    local d = BNB.GetSearchTheme(tool.theme)
    local tl, ts = ThemeLayout(d)
    local w = db.devSearch[tool.theme]
    if not w then
        w = { layout = CopyLayout(tl),
              size = { w = ts.w, h = ts.h, border = ts.border, borderY = ts.borderY } }
        db.devSearch[tool.theme] = w
    end
    for k, p in pairs(tl) do   -- a piece added later
        if not w.layout[k] then w.layout[k] = CopyLayout({ [k] = p })[k] end
    end
    w.size.borderY = w.size.borderY or w.size.border
    return w.layout, w.size
end

-- Whole numbers print bare, anything else with two decimals.
local function Num(n)
    if n == math.floor(n) then return string.format("%d", n) end
    return string.format("%.2f", n)
end

-- Pieces that share a size when "Same for matching pieces" is ticked.
local GROUPS = {
    top = "tb", bottom = "tb", top2 = "tb", bottom2 = "tb", left = "lr", right = "lr",
    topleft = "c", topright = "c", bottomleft = "c", bottomright = "c",
    topornament = "mid", bottomornament = "mid",
}

-- The selected piece, moved to the first one the theme uses when the
-- current one is not in its layout (a theme switch).
local function ValidSel(layout)
    if layout[tool.sel] then return end
    for _, def in ipairs(PIECES) do
        if layout[def.key] then tool.sel = def.key; return end
    end
end

-- Which edge of a piece stays put when its size is typed in: the side both
-- of its points hang off. nil = the piece stretches with the bar on that axis.
local function FixedSide(p, axis)
    if p.a1 == p.a2 then return (axis == "h") and "TOP" or "LEFT" end
    local A, B = (axis == "h") and "TOP" or "LEFT", (axis == "h") and "BOTTOM" or "RIGHT"
    if p.a1:find(A) and p.a2:find(A) then return A end
    if p.a1:find(B) and p.a2:find(B) then return B end
end

-- Size of a piece on screen in px, or nil on a stretching axis.
local function PieceSize(p, axis, k)
    if not FixedSide(p, axis) then return nil end
    if axis == "h" then return (p.y1 - p.y2) * k end
    return (p.x2 - p.x1) * k
end

local function SetPieceSize(p, axis, px, k)
    local v, side = px / k, FixedSide(p, axis)
    if side == "TOP" then p.y2 = p.y1 - v
    elseif side == "BOTTOM" then p.y1 = p.y2 + v
    elseif side == "LEFT" then p.x2 = p.x1 + v
    elseif side == "RIGHT" then p.x1 = p.x2 - v end
end

local function ExportText()
    local layout, size = WorkLayout()
    local d = BNB.GetSearchTheme(tool.theme)
    local lines = { "Register({",
        string.format("    name   = %q,", d.name),
        d.folder and string.format("    folder = %q,", d.folder) or string.format("    path   = %q,", d.art),
        "    layout = {" }
    for _, def in ipairs(PIECES) do
        local p = layout[def.key]   -- nil: a piece this theme does not use
        if p then
            lines[#lines + 1] = string.format(
                "        %-14s = { a1 = %q, x1 = %s, y1 = %s, a2 = %q, x2 = %s, y2 = %s },",
                def.key, p.a1, Num(p.x1), Num(p.y1), p.a2, Num(p.x2), Num(p.y2))
        end
    end
    lines[#lines + 1] = "    },"
    lines[#lines + 1] = string.format("    size = { w = %d, h = %d, border = %d, borderY = %d },",
        size.w, size.h, size.border, size.borderY)
    local h = d.highlight
    if type(h) == "table" then
        lines[#lines + 1] = string.format("    highlight = { %s, %s, %s, %s },",
            Num(h[1] or 1), Num(h[2] or 0.82), Num(h[3] or 0), Num(h[4] or 0.14))
    end
    lines[#lines + 1] = "})"
    return table.concat(lines, "\n")
end

local function Refresh()
    local layout, size = WorkLayout()
    local bar = tool.bar
    BNB.ApplySearchChrome(bar, tool.theme, layout, size)
    tool.title:SetText("Search bar layout (ALL-69):  |cffffffff" .. BNB.GetSearchTheme(tool.theme).name .. "|r")
    ValidSel(layout)
    local p = layout[tool.sel]
    PlacePiece(tool.hl, bar, p, size.border / NATIVE, size.borderY / NATIVE)
    tool.hl:SetShown(tool.showHL)
    -- Buttons only for the pieces this theme uses, packed in order.
    local n = 0
    for _, b in ipairs(tool.pieceBtns) do
        if layout[b.key] then
            local row, col = math.floor(n / 6), n % 6
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", 10 + col * 102, -28 - row * 24)
            b:Show()
            n = n + 1
        else
            b:Hide()
        end
        b.sel:SetShown(b.key == tool.sel)
    end
    for axis, eb in pairs(tool.sizeBoxes) do
        local v = PieceSize(p, axis, ((axis == "h") and size.borderY or size.border) / NATIVE)
        if not eb:HasFocus() then eb:SetText(v and Num(v) or "stretch") end
        eb:SetEnabled(v ~= nil)
        eb:SetTextColor(v and 1 or 0.5, v and 1 or 0.5, v and 1 or 0.5)
    end
    for key, eb in pairs(tool.barBoxes) do
        if not eb:HasFocus() then eb:SetText(Num(size[key])) end
    end
    tool.info:SetText(string.format(
        "|cffffd100%s|r   TOPLEFT -> %s %s, %s   BOTTOMRIGHT -> %s %s, %s\n"
        .. "Bar %dx%d   border %dx%d px   zoom %dx   (offsets are in art pixels, scaled by border / 32 on screen)",
        tool.sel, p.a1, Num(p.x1), Num(p.y1), p.a2, Num(p.x2), Num(p.y2),
        size.w, size.h, size.border, size.borderY, tool.zoom))
end

-- mode: nil = move both points, "p1" = top-left only, "p2" = bottom-right only
local function Nudge(dx, dy, mode)
    local p = WorkLayout()[tool.sel]
    if mode ~= "p2" then p.x1 = p.x1 + dx; p.y1 = p.y1 + dy end
    if mode ~= "p1" then p.x2 = p.x2 + dx; p.y2 = p.y2 + dy end
    Refresh()
end

local function ModMode()
    if IsAltKeyDown() then return "p1" end
    if IsControlKeyDown() then return "p2" end
    return nil
end

local function BuildTool()
    local f = CreateFrame("Frame", "BNBSearchLayoutTool", UIParent, "BackdropTemplate")
    f:SetSize(660, 274)
    f:SetPoint("CENTER", 0, -160)
    f:SetFrameStrata("DIALOG")
    f:SetToplevel(true)
    f:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1,
    })
    f:SetBackdropColor(0.05, 0.05, 0.07, 0.92)
    f:SetBackdropBorderColor(0.4, 0.4, 0.45, 1)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetClampedToScreen(true)
    tool = f
    f.sel, f.zoom, f.showHL = "topleft", 1, true
    f.theme = BNB.SEARCH_DEFAULT_THEME

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", 10, -8)
    f.title = title

    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", 2, 2)
    close:SetScript("OnClick", function() f:Hide() end)

    -- The preview bar floats above the panel and moves with it.
    local bar = CreateFrame("Frame", nil, f)
    bar:SetPoint("BOTTOM", f, "TOP", 0, 60)
    bar:EnableMouse(true)
    f.bar = bar

    local hl = bar:CreateTexture(nil, "OVERLAY", nil, 7)
    hl:SetColorTexture(1, 0.82, 0, 0.25)
    f.hl = hl

    -- Mouse drag on the bar moves the selected piece (Alt/Ctrl as the arrows).
    bar:SetScript("OnMouseDown", function(self, btn)
        if btn ~= "LeftButton" then return end
        local s = self:GetEffectiveScale()
        local cx, cy = GetCursorPosition()
        self._drag = { x = cx / s, y = cy / s, mode = ModMode(), dx = 0, dy = 0 }
    end)
    bar:SetScript("OnMouseUp", function(self) self._drag = nil end)
    bar:SetScript("OnUpdate", function(self)
        local d = self._drag
        if not d then return end
        local s = self:GetEffectiveScale()
        local cx, cy = GetCursorPosition()
        local tx = math.floor(cx / s - d.x + 0.5)
        local ty = math.floor(cy / s - d.y + 0.5)
        if tx ~= d.dx or ty ~= d.dy then
            Nudge(tx - d.dx, ty - d.dy, d.mode)
            d.dx, d.dy = tx, ty
        end
    end)

    -- Piece buttons, up to three rows of six; Refresh() places them.
    f.pieceBtns = {}
    for _, def in ipairs(PIECES) do
        local b = CreateFrame("Button", nil, f, BNB.PanelButtonTemplate())
        b:SetSize(96, 20)
        b:SetText(def.key)
        b.key = def.key
        b.sel = b:CreateTexture(nil, "OVERLAY")
        b.sel:SetPoint("TOPLEFT", -2, 2)
        b.sel:SetPoint("BOTTOMRIGHT", 2, -2)
        b.sel:SetColorTexture(1, 0.82, 0, 0.35)
        b:SetScript("OnClick", function() f.sel = def.key; Refresh() end)
        f.pieceBtns[#f.pieceBtns + 1] = b
    end

    local info = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    info:SetPoint("TOPLEFT", 10, -160)
    info:SetJustifyH("LEFT")
    info:SetWidth(640)
    f.info = info

    -- Number boxes: Enter applies a positive number, Esc puts the value back.
    local function NumBox(anchor, x, apply)
        local bg = CreateFrame("Frame", nil, f, "BackdropTemplate")
        bg:SetSize(56, 20)
        bg:SetPoint("LEFT", anchor, "RIGHT", x, 0)
        BNB.SetBackdropDark(bg)
        local eb = CreateFrame("EditBox", nil, bg)
        eb:SetAllPoints()
        eb:SetFontObject("GameFontHighlightSmall")
        eb:SetTextInsets(6, 6, 0, 0)
        eb:SetAutoFocus(false)
        eb:SetScript("OnEscapePressed", function(self) self:ClearFocus(); Refresh() end)
        eb:SetScript("OnEditFocusLost", function() Refresh() end)
        eb:SetScript("OnEnterPressed", function(self)
            local n = tonumber(self:GetText())
            self:ClearFocus()
            if n and n > 0 then apply(n) end
            Refresh()
        end)
        return eb, bg
    end
    local function Label(text, anchor, x, font)
        local fs = f:CreateFontString(nil, "OVERLAY", font or "GameFontNormalSmall")
        if anchor then fs:SetPoint("LEFT", anchor, "RIGHT", x, 0) else fs:SetPoint("TOPLEFT", 10, x) end
        fs:SetText(text)
        return fs
    end

    -- Row 1: the whole bar, and how big the art draws across (border) and
    -- down (borderY). Border - / + change both.
    f.barBoxes = {}
    local function SizeKey(key, lo)
        return function(n) local _, size = WorkLayout(); size[key] = math.max(lo, math.floor(n + 0.5)) end
    end
    local r1 = Label("Bar:   Width", nil, -108)
    local e, bg = NumBox(r1, 6, SizeKey("w", 64));        f.barBoxes.w = e
    local l = Label("Height", bg, 12)
    e, bg = NumBox(l, 6, SizeKey("h", 16));               f.barBoxes.h = e
    l = Label("Border:   Width", bg, 30)
    e, bg = NumBox(l, 6, SizeKey("border", 4));           f.barBoxes.border = e
    l = Label("Height", bg, 12)
    e, bg = NumBox(l, 6, SizeKey("borderY", 4));          f.barBoxes.borderY = e

    -- Row 2: size of the selected piece in screen pixels. The edge that
    -- hangs off the bar stays put; a stretching axis shows "stretch" and is
    -- locked.
    f.sizeBoxes, f.linkSizes = {}, true
    local function PieceApply(axis)
        return function(px)
            local layout, size = WorkLayout()
            local k = ((axis == "h") and size.borderY or size.border) / NATIVE
            -- The ornament with Keep square: both sides take px and it grows from
            -- its centre, so it stays put while it changes size.
            local ep = layout[f.sel]
            if f.sel == "ornament" and f.keepSquare and FixedSide(ep, "w") and FixedSide(ep, "h") then
                local kx, ky = size.border / NATIVE, size.borderY / NATIVE
                local cx, cy = (ep.x1 + ep.x2) / 2, (ep.y1 + ep.y2) / 2
                local hw, hh = px / kx / 2, px / ky / 2
                ep.x1, ep.x2, ep.y1, ep.y2 = cx - hw, cx + hw, cy + hh, cy - hh
                return
            end
            local grp = GROUPS[f.sel]
            for key, pp in pairs(layout) do
                if key == f.sel or (f.linkSizes and grp and GROUPS[key] == grp) then
                    if FixedSide(pp, axis) then SetPieceSize(pp, axis, px, k) end
                end
            end
        end
    end
    local sizeLbl = Label("Piece:  Width", nil, -134)
    local wBox
    f.sizeBoxes.w, wBox = NumBox(sizeLbl, 6, PieceApply("w"))
    local hLbl = Label("Height", wBox, 12)
    local hBox
    f.sizeBoxes.h, hBox = NumBox(hLbl, 6, PieceApply("h"))
    local link = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
    link:SetSize(22, 22)
    link:SetPoint("LEFT", hBox, "RIGHT", 12, 0)
    link:SetChecked(true)
    link:SetScript("OnClick", function(self) f.linkSizes = self:GetChecked() and true or false end)
    local linkLbl = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    linkLbl:SetPoint("LEFT", link, "RIGHT", 2, 0)
    linkLbl:SetText("Same for matching pieces")
    f.keepSquare = true
    local sq = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
    sq:SetSize(22, 22)
    sq:SetPoint("LEFT", linkLbl, "RIGHT", 12, 0)
    sq:SetChecked(true)
    sq:SetScript("OnClick", function(self) f.keepSquare = self:GetChecked() and true or false end)
    local sqLbl = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    sqLbl:SetPoint("LEFT", sq, "RIGHT", 2, 0)
    sqLbl:SetText("Ornament: keep square")

    local help = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    help:SetPoint("TOPLEFT", 10, -186)
    help:SetJustifyH("LEFT")
    help:SetWidth(640)
    help:SetText("Arrows / drag: move.  Alt: top-left point only.  Ctrl: bottom-right point only (resize).  "
        .. "Shift: 5 px.\nTab: next piece.  Bar size: Home / End = width, Page Up / Page Down = height.  "
        .. "Number boxes: Enter applies, Esc cancels.\nPiece sizes: matching pieces = top + bottom, left + right, all four corners.")

    local function Btn(label, x, fn)
        local b = CreateFrame("Button", nil, f, BNB.PanelButtonTemplate())
        b:SetSize(84, 20)
        b:SetPoint("BOTTOMRIGHT", x, 8)
        b:SetText(label)
        b:SetScript("OnClick", fn)
        return b
    end
    Btn("Export", -10, function() BNB.ShowClipboardHint(ExportText(), f, true) end)
    Btn("Reset", -98, function()
        if BigNoteBoxDB.devSearch then BigNoteBoxDB.devSearch[f.theme] = nil end
        Refresh()
    end)
    Btn("Zoom", -186, function()
        f.zoom = (f.zoom % 3) + 1
        bar:SetScale(f.zoom)
        Refresh()
    end)
    Btn("Highlight", -274, function() f.showHL = not f.showHL; Refresh() end)
    -- Border thickness: 2 px a click, 1 px with Shift.
    local function Border(dir)
        local _, size = WorkLayout()
        local d = dir * (IsShiftKeyDown() and 1 or 2)
        size.border = math.max(4, math.min(64, size.border + d))
        size.borderY = math.max(4, math.min(64, size.borderY + d))
        Refresh()
    end
    Btn("Border +", -362, function() Border(1) end)
    Btn("Border -", -450, function() Border(-1) end)
    -- Theme: steps through BNB.SEARCH_THEME_ORDER; each keeps its own copy.
    local themeBtn = Btn("Theme", -538, function()
        local order = BNB.SEARCH_THEME_ORDER
        for i, id in ipairs(order) do
            if id == f.theme then f.theme = order[i % #order + 1]; break end
        end
        Refresh()
    end)
    themeBtn:SetEnabled(#BNB.SEARCH_THEME_ORDER > 1)

    -- Keys: handled ones are swallowed, the rest propagate.
    f:EnableKeyboard(true)
    f:SetScript("OnKeyDown", function(self, key)
        local step = IsShiftKeyDown() and 5 or 1
        local mode = ModMode()
        local _, size = WorkLayout()
        local handled = true
        if key == "LEFT" then Nudge(-step, 0, mode)
        elseif key == "RIGHT" then Nudge(step, 0, mode)
        elseif key == "UP" then Nudge(0, step, mode)
        elseif key == "DOWN" then Nudge(0, -step, mode)
        elseif key == "TAB" then
            -- Next (Shift: previous) piece this theme uses.
            local layout = WorkLayout()
            local used = {}
            for _, def in ipairs(PIECES) do
                if layout[def.key] then used[#used + 1] = def.key end
            end
            for i, k in ipairs(used) do
                if k == f.sel then
                    local n = IsShiftKeyDown() and (i - 2) % #used + 1 or i % #used + 1
                    f.sel = used[n]
                    break
                end
            end
            Refresh()
        elseif key == "HOME" then size.w = math.max(64, size.w - step * 10); Refresh()
        elseif key == "END" then size.w = size.w + step * 10; Refresh()
        elseif key == "PAGEDOWN" then size.h = math.max(32, size.h - step); Refresh()
        elseif key == "PAGEUP" then size.h = size.h + step; Refresh()
        elseif key == "ESCAPE" then f:Hide()
        else handled = false end
        self:SetPropagateKeyboardInput(not handled)
    end)

    -- Sample text in the input region, so its placement can be judged too.
    local sample = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    sample:SetJustifyH("LEFT")
    sample:SetText("Search notes...")
    local layout0, size0 = WorkLayout()
    BNB.ApplySearchChrome(bar, f.theme, layout0, size0)
    sample:SetPoint("LEFT", bar._searchPieces.text, "LEFT", 0, 0)
    sample:SetPoint("RIGHT", bar._searchPieces.text, "RIGHT", 0, 0)

    f:SetScript("OnShow", Refresh)
    f:Hide()   -- so the first Show runs OnShow
end

function BNB.ToggleSearchLayoutTool()
    if not tool then
        BuildTool()
        tool:Show()
        return
    end
    tool:SetShown(not tool:IsShown())
end

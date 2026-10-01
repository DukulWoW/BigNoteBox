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
-- Each theme is registered by the theme.lua in its own folder under
-- Assets\Search\ (loads after this file; Assets\Search\README.txt) through
-- BigNoteBox.RegisterSearchTheme, the same call another addon can make.
-- BNB.ApplySearchChrome(f, themeID) draws a theme on any frame; the real
-- search bar calls it. /bnb searchlayout (debug mode) opens a
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
-- barOnly pieces are never drawn on the Oracle results panel; panelOnly
-- ones (pornament1-4, decorations around the results) only there. The bar
-- and the results panel each have a layout of their own (layout and
-- panelLayout), so moving a bar piece never moves the panel's.
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
    { key = "ornament",       file = "s-ornament",        layer = "ARTWORK",    sub = 0, barOnly = true },
    { key = "text",           file = nil,                 layer = "ARTWORK",    sub = 1, barOnly = true },
    { key = "pornament1",     file = "s-panel-ornament-1", layer = "ARTWORK",   sub = 2, panelOnly = true },
    { key = "pornament2",     file = "s-panel-ornament-2", layer = "ARTWORK",   sub = 2, panelOnly = true },
    { key = "pornament3",     file = "s-panel-ornament-3", layer = "ARTWORK",   sub = 2, panelOnly = true },
    { key = "pornament4",     file = "s-panel-ornament-4", layer = "ARTWORK",   sub = 2, panelOnly = true },
}

-- Ornaments can be drawn at another depth than their own, set per piece in
-- the layout: layer = "back" puts it behind every border piece (over the
-- background), layer = "top" over everything, including the other frame
-- (a panel ornament over the search bar, the bar's ornament over the
-- results) and the text and rows. Left out = the piece's own layer above.
local ORNAMENTS = {
    ornament = true, topornament = true, bottomornament = true,
    pornament1 = true, pornament2 = true, pornament3 = true, pornament4 = true,
}
-- "top" pieces live on a child frame this many levels above their own
-- frame: above the other frame and every child of either.
local TOP_LIFT = 30

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
--   def.panelPos optional { left, right, gap } in screen px: where the
--               results panel sits under the bar. left / right move its
--               edges in from the bar's (negative = wider than the bar),
--               gap is the space below the bar (negative = overlap).
--               under = false draws the panel over the bar where they
--               overlap; left out or true, under it.
--               Left out = { left = 0, right = 0, gap = 2, under = true }
--   def.panelLayout optional layout of the results panel's own pieces
--               (9-slice, middle pieces, pornament1-4), relative to the
--               panel. Left out = a copy of the bar's 9-slice
--   def.panelSize optional { border, borderY } for the panel's art; left
--               out = the bar's
--   def.panelPad optional { left, right, top, bottom } in screen px: where
--               the results (rows, hint line, "?" help) sit inside the
--               panel art. Left out = 0.6 x the panel's border on each side
--   def.hidden  optional; true keeps an unfinished theme out of the Oracle
--               settings picker (the layout tool still lists it)
--   def.panelFiles optional file name per piece for the panel only (false =
--               none); left out = the same art as the bar
--   def.type    optional; "backdrop" = no art of its own: the bar and the
--               results panel get a plain backdrop (ALL-69.5) built from
--               def.backdrop (see BACKDROP_DEFAULTS below; LibSharedMedia
--               names or texture paths), and folder / path / layout / files
--               are not used. id is then required. highlight and panelPos
--               still apply.
-- Registering an id again replaces it and keeps its place in the list.
function BNB.RegisterSearchTheme(def)
    if type(def) ~= "table" or type(def.name) ~= "string" then return false, "name missing" end
    local backdrop = def.type == "backdrop"
    local art = def.path or (def.folder and (ASSETS .. def.folder .. "\\"))
    if not art and not backdrop then return false, "folder or path missing" end
    local id = def.id or (def.folder and def.folder:lower())
    if not id then return false, "id missing" end
    id = id:lower()
    if not BNB.SEARCH_THEMES[id] then
        BNB.SEARCH_THEME_ORDER[#BNB.SEARCH_THEME_ORDER + 1] = id
    end
    BNB.SEARCH_THEMES[id] = {
        id = id, name = def.name, folder = def.folder, art = art,
        files = def.files, layout = def.layout, size = def.size,
        highlight = def.highlight, panelBg = def.panelBg, panelPos = def.panelPos,
        panelLayout = def.panelLayout, panelSize = def.panelSize, panelFiles = def.panelFiles,
        hidden = def.hidden, panelPad = def.panelPad,
        type = backdrop and "backdrop" or nil, backdrop = def.backdrop, custom = def.custom,
    }
    return true
end

--------------------------------------------------------------------------------
-- BACKDROP THEMES (ALL-69.5)
--------------------------------------------------------------------------------
-- A backdrop theme has no art of its own: a border (Blizzard's window
-- border, an LSM border or none) around a background from the sticky note
-- list (UI/StickyBackgrounds.lua, drawn by UI/BgLayer.lua) or a plain
-- colour. Its settings are the sticky notes' own (UI/StickySettings.lua;
-- Dukul, 2026-09-28), in a style table:
--   border          "Default" = Blizzard's window border (the Dialog
--                   nine-slice), "None", or an LSM border name / path
--   borderScale     border thickness % (1-200)
--   borderOffset    px from the frame edge to the background (0-12)
--   borderLight     border brightness -100..100: 0 = as drawn, below
--                   darkens, above adds a lighter copy on top
--   bgR, bgG, bgB   background colour; alpha = its opacity (0-1)
--   bgTexture       StickyBG key; "none" = plain colour
--   bgColorOpacity  Colorize: how much the colour tints the texture (0-1)
--   bgBrightness    texture brightness -1..1 (the sticky's own unit)
--   highlight       { r, g, b, a } of the selected result; nil = BNB gold
--   font            nil = WoW's font; "bnb:<id>" a BigNoteBox font card,
--                   "lsm:<name>" a LibSharedMedia font
--   fontSize        size of the typed text (result rows keep their sizes)
-- Every field falls back to BACKDROP_DEFAULTS (the Default style). The
-- built-in "custom" theme (custom = true) takes its style from
-- BigNoteBoxDB.oracleCustom, which the Oracle settings page writes; a theme
-- from another addon passes backdrop.
BNB.SEARCH_CUSTOM_THEME = "custom"
local BACKDROP_DEFAULTS = {
    border = "Default", borderScale = 100, borderOffset = 7, borderLight = 0,
    bgR = 0.07, bgG = 0.07, bgB = 0.09, alpha = 0.96,
    bgTexture = "windowbg", bgColorOpacity = 1, bgBrightness = 0,
    fontSize = 16,
}
BNB.SEARCH_BACKDROP_DEFAULTS = BACKDROP_DEFAULTS

-- Bumped whenever the custom style changes, so the Oracle knows to redraw.
BNB.SEARCH_STYLE_REV = 0
function BNB.SearchStyleChanged()
    BNB.SEARCH_STYLE_REV = BNB.SEARCH_STYLE_REV + 1
end

local function IsBackdrop(d) return d and d.type == "backdrop" end

-- The style of a backdrop theme, every field filled in; nil for drawn ones.
function BNB.GetSearchBackdrop(id)
    local d = BNB.GetSearchTheme(id)
    if not IsBackdrop(d) then return nil end
    local src = d.custom and BigNoteBoxDB and BigNoteBoxDB.oracleCustom or d.backdrop
    if type(src) ~= "table" then src = {} end
    local s = {}
    for k, v in pairs(BACKDROP_DEFAULTS) do s[k] = v end
    for k, v in pairs(src) do s[k] = v end
    local function Clamp(v, lo, hi, def) return math.max(lo, math.min(hi, tonumber(v) or def)) end
    s.borderScale    = Clamp(s.borderScale, 1, 200, 100)
    s.borderOffset   = Clamp(s.borderOffset, 0, 12, 7)
    s.borderLight    = Clamp(s.borderLight, -100, 100, 0)
    s.bgR, s.bgG, s.bgB = Clamp(s.bgR, 0, 1, 0.07), Clamp(s.bgG, 0, 1, 0.07), Clamp(s.bgB, 0, 1, 0.09)
    s.alpha          = Clamp(s.alpha, 0, 1, 0.96)
    s.bgColorOpacity = Clamp(s.bgColorOpacity, 0, 1, 1)
    s.bgBrightness   = Clamp(s.bgBrightness, -1, 1, 0)
    s.fontSize       = Clamp(s.fontSize, 8, 32, 16)
    if type(s.border) ~= "string" or s.border == "" then s.border = "None" end
    s.edge = math.max(1, math.floor(16 * s.borderScale / 100 + 0.5))   -- LSM border px
    return s
end

local function LSM()
    return LibStub and LibStub("LibSharedMedia-3.0", true)
end

-- An LSM name or a texture path to a path; nil when there is none.
local function Media(kind, key)
    if type(key) ~= "string" or key == "" then return nil end
    if key:find("\\", 1, true) or key:find("/", 1, true) then return key end
    local lsm = LSM()
    local path = lsm and lsm:Fetch(kind, key, true)
    if type(path) ~= "string" or path == "" then return nil end
    return path
end

-- The font file of a style's font value; nil = WoW's own font objects
-- (which keep the per-alphabet fallback). A font that is gone (pack or
-- addon removed) is nil too; the saved value is never rewritten.
function BNB.SearchFontPath(value)
    if type(value) ~= "string" then return nil end
    local kind, key = value:match("^(%a+):(.+)$")
    if kind == "bnb" then
        for _, def in ipairs(BNB.FONTS or {}) do
            if def.id == key and not def._isLSM then return def.regular end
        end
    elseif kind == "lsm" then
        return Media("font", key)
    end
    return nil
end

-- Font file and typed-text size of a theme; nil for drawn themes and for
-- a backdrop theme on WoW's font (size is then still returned second).
function BNB.GetSearchFont(id)
    local s = BNB.GetSearchBackdrop(id)
    if not s then return nil end
    return BNB.SearchFontPath(s.font), s.fontSize
end

-- border = "Default": Blizzard's window border, on each client its own art
-- (a Blizzard nine-slice, which Forever draws in its style). With the
-- "windowbg" background (the main window's rock on Retail, wood grain plus
-- glow on Forever) it is the built-in Default style (Dukul, 2026-09-28).
-- Layout: "Dialog", picked by Dukul on both clients 2026-09-28. The main
-- window's own ButtonFrameTemplateNoPortrait draws its title band on a
-- 50 px bar; InsetFrameTemplate, SimplePanelTemplate and GenericMetal did
-- not work.
-- Tuning in game: /run BigNoteBox.SEARCH_WINDOW.pad = 14 (or layout)
-- BigNoteBox.SearchStyleChanged() BigNoteBox.Oracle.RefreshPreview()
local WINDOW = "Default"
BNB.SEARCH_WINDOW = { layout = "Dialog", pad = 14 }
function BNB.IsWindowStyle(s) return type(s) == "table" and s.border == WINDOW end

-- The LSM edge file of a style, or nil (Default, None, unknown name).
local function EdgeFile(s)
    if s.border == WINDOW or s.border == "None" then return nil end
    return Media("border", s.border)
end

BNB.GetSearchEdgeFile = EdgeFile   -- the background picker's tiles

-- Inner padding of a backdrop theme: where the text and the results sit.
local function BackdropPad(s)
    local k = math.max(1, s.borderScale / 100)
    if s.border == WINDOW then
        return math.floor(BNB.SEARCH_WINDOW.pad * k + 0.5)
    end
    local edge = EdgeFile(s) and s.edge * 0.6 or 0
    return math.floor(math.max(8, edge, s.borderOffset + 4) + 0.5)
end

--------------------------------------------------------------------------------
-- SAVED STYLES (ALL-69.5, like BigChatBox's Designer styles)
--------------------------------------------------------------------------------
-- The Custom border theme's knobs write BigNoteBoxDB.oracleCustom. A style
-- is a named copy of it: built-in (below, never changed) or the player's own
-- in BigNoteBoxDB.oracleStyles[name] (account-wide). BigNoteBoxDB.oracleStyle
-- is the one last picked or saved: "builtin:<key>" / "user:<name>"; nil =
-- builtin:default. Picking a style copies it into oracleCustom; changing a
-- knob afterwards changes only oracleCustom until the player saves.
BNB.SEARCH_BUILTIN_STYLES = {
    { key = "default", label = "SEARCH_STYLE_DEFAULT", style = {} },
    { key = "plain",   label = "SEARCH_STYLE_PLAIN",
      style = { border = "Blizzard Tooltip", borderOffset = 3, bgTexture = "none" } },
}
-- Built-in keys that were renamed (the Default style was "window" in testing).
local BUILTIN_ALIAS = { window = "default" }

-- What a style may hold, and of which kind. Anything else is dropped, so an
-- imported string can only ever set these.
local STYLE_KEYS = {
    border = "string", bgTexture = "string", font = "string",
    borderScale = "number", borderOffset = "number", borderLight = "number",
    bgR = "number", bgG = "number", bgB = "number", alpha = "number",
    bgColorOpacity = "number", bgBrightness = "number", fontSize = "number",
    highlight = "colour",
}

local function CleanStyle(t)
    if type(t) ~= "table" then return nil end
    local out = {}
    for k, kind in pairs(STYLE_KEYS) do
        local v = t[k]
        if kind == "string" and type(v) == "string" and #v <= 256 then
            out[k] = v
        elseif kind == "number" and type(v) == "number" and v == v then
            out[k] = v
        elseif kind == "colour" and type(v) == "table" then
            local c = {}
            for i = 1, 4 do
                local n = tonumber(v[i]) or (i == 4 and 1) or 0
                c[i] = math.max(0, math.min(1, n))
            end
            out[k] = c
        end
    end
    return out
end
BNB.CleanSearchStyle = CleanStyle

function BNB.GetSearchStyleID()
    local id = (BigNoteBoxDB and BigNoteBoxDB.oracleStyle) or "builtin:default"
    local key = id:match("^builtin:(.+)$")
    if key and BUILTIN_ALIAS[key] then id = "builtin:" .. BUILTIN_ALIAS[key] end
    return id
end

-- The saved style of an id, or nil when it is gone.
function BNB.GetSearchStyle(id)
    if type(id) ~= "string" then return nil end
    local kind, key = id:match("^(%a+):(.+)$")
    if kind == "builtin" then
        key = BUILTIN_ALIAS[key] or key
        for _, b in ipairs(BNB.SEARCH_BUILTIN_STYLES) do
            if b.key == key then return b.style end
        end
    elseif kind == "user" then
        local t = BigNoteBoxDB and BigNoteBoxDB.oracleStyles
        return t and t[key]
    end
    return nil
end

-- The player's saved style names, sorted.
function BNB.GetSearchStyleNames()
    local out = {}
    for name in pairs((BigNoteBoxDB and BigNoteBoxDB.oracleStyles) or {}) do out[#out + 1] = name end
    table.sort(out, function(a, b) return a:lower() < b:lower() end)
    return out
end

-- Copies a style into the Custom border theme. Returns true when it exists.
function BNB.LoadSearchStyle(id)
    local s = CleanStyle(BNB.GetSearchStyle(id))
    if not s then return false end
    BigNoteBoxDB.oracleCustom = next(s) and s or nil
    BigNoteBoxDB.oracleStyle = id
    BNB.SearchStyleChanged()
    return true
end

-- Saves style (default: the current Custom border look) under name.
function BNB.SaveSearchStyle(name, style)
    local db = BigNoteBoxDB
    db.oracleStyles = db.oracleStyles or {}
    db.oracleStyles[name] = CleanStyle(style or db.oracleCustom or {})
    db.oracleStyle = "user:" .. name
    if style then
        db.oracleCustom = CleanStyle(style)
        BNB.SearchStyleChanged()
    end
end

function BNB.DeleteSearchStyle(name)
    local db = BigNoteBoxDB
    if db.oracleStyles then db.oracleStyles[name] = nil end
    if db.oracleStyles and next(db.oracleStyles) == nil then db.oracleStyles = nil end
    if db.oracleStyle == "user:" .. name then db.oracleStyle = nil end
end

-- Export / import strings: "BNBOS1:" + LibSerialize + LibDeflate, the same
-- libraries as note sharing (Features/ShareNote.lua).
local STYLE_PREFIX = "BNBOS1:"
function BNB.ExportSearchStyle(style)
    local ls = LibStub and LibStub("LibSerialize", true)
    local ld = LibStub and LibStub("LibDeflate", true)
    if not (ls and ld) then return nil end
    local data = ls:Serialize(CleanStyle(style or BigNoteBoxDB.oracleCustom or {}))
    return STYLE_PREFIX .. ld:EncodeForPrint(ld:CompressDeflate(data))
end

-- Returns a clean style table, or nil.
function BNB.ImportSearchStyle(str)
    if type(str) ~= "string" then return nil end
    str = str:match("^%s*(.-)%s*$")
    if str:sub(1, #STYLE_PREFIX) ~= STYLE_PREFIX then return nil end
    local ls = LibStub and LibStub("LibSerialize", true)
    local ld = LibStub and LibStub("LibDeflate", true)
    if not (ls and ld) then return nil end
    local ok, style = pcall(function()
        local c = ld:DecodeForPrint(str:sub(#STYLE_PREFIX + 1))
        local raw = c and ld:DecompressDeflate(c)
        if not raw then return nil end
        local good, t = ls:Deserialize(raw)
        return good and t or nil
    end)
    return ok and CleanStyle(style) or nil
end

-- The built-in "Custom border" theme: the player's own style. Listed last
-- in the settings picker (UI/Config/OracleSettings.lua), never in the
-- layout tool (it has no pieces to place).
BNB.RegisterSearchTheme({
    id = BNB.SEARCH_CUSTOM_THEME, name = "Custom border", type = "backdrop", custom = true,
})

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
    if IsBackdrop(d) then h = BNB.GetSearchBackdrop(id).highlight or h end
    if type(h) ~= "table" then h = DEFAULT_HIGHLIGHT end
    return h[1] or 1, h[2] or 0.82, h[3] or 0, h[4] or 0.14
end

-- Where a theme's results panel sits under the bar (see panelPos above).
local DEFAULT_PANEL_POS = { left = 0, right = 0, gap = 2 }
function BNB.GetSearchPanelPos(id)
    local d = BNB.GetSearchTheme(id)
    local p = d and type(d.panelPos) == "table" and d.panelPos or DEFAULT_PANEL_POS
    return { left = p.left or 0, right = p.right or 0, gap = p.gap or DEFAULT_PANEL_POS.gap,
             under = p.under ~= false }
end

-- Sets f's frame level and keeps every child one above its parent, so rows
-- built while the panel was over the bar follow it under the bar too.
local function SetLevelTree(f, lvl)
    f:SetFrameLevel(lvl)
    for _, child in ipairs({ f:GetChildren() }) do
        if child == f._searchOver then child:SetFrameLevel(lvl + TOP_LIFT)
        elseif child == f._searchNine then child:SetFrameLevel(lvl)   -- Window border
        elseif child == f._searchBgLayer then child:SetFrameLevel(math.max(0, lvl - 1))   -- background art
        else SetLevelTree(child, lvl + 1) end
    end
end

-- Frame level a search bar is given when it is created, before its
-- children: leaves room below it for a results panel drawn under the bar.
BNB.SEARCH_BAR_LEVEL = 20

-- Anchors the results panel under the bar by the theme's panelPos (pos
-- overrides it: the layout tool's working copy) and puts it under or over
-- the bar. The caller sets the height. Call it again after the bar is
-- raised: raising lifts the panel with it.
function BNB.PlaceSearchPanel(panel, bar, id, pos)
    pos = pos or BNB.GetSearchPanelPos(id)
    panel:ClearAllPoints()
    panel:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", pos.left, -pos.gap)
    panel:SetPoint("TOPRIGHT", bar, "BOTTOMRIGHT", -pos.right, -pos.gap)
    local lvl = bar:GetFrameLevel()
    SetLevelTree(panel, (pos.under ~= false) and math.max(0, lvl - 10) or lvl + 1)
    if bar._searchOver then bar._searchOver:SetFrameLevel(lvl + TOP_LIFT) end
end

-- A theme's layout and size, falling back to the default theme's.
local function ThemeLayout(d)
    local def = BNB.SEARCH_THEMES[BNB.SEARCH_DEFAULT_THEME] or d
    return d.layout or def.layout, d.size or def.size
end

-- A theme's results panel layout and border size. Left out, the panel is
-- a copy of the bar's 9-slice at the bar's border size, so a theme without
-- panel art of its own still gets a matching frame.
local function ThemePanel(d)
    local tl, ts = ThemeLayout(d)
    local layout = d.panelLayout
    if not layout then
        layout = {}
        for _, def in ipairs(PIECES) do
            if not def.barOnly and not def.panelOnly and tl[def.key] then layout[def.key] = tl[def.key] end
        end
    end
    local ps = d.panelSize or {}
    return layout, { border = ps.border or ts.border,
                     borderY = ps.borderY or ps.border or ts.borderY or ts.border }
end

local NATIVE = 32

-- The content inset of a theme's results panel (def.panelPad), in screen
-- px. size: the panel's { border, borderY }, for the default inset; left
-- out = the theme's own.
function BNB.GetSearchPanelPad(id, size)
    local d = BNB.GetSearchTheme(id)
    if IsBackdrop(d) then
        local pad = BackdropPad(BNB.GetSearchBackdrop(id))
        return { left = pad, right = pad, top = pad, bottom = pad }
    end
    local p = d and type(d.panelPad) == "table" and d.panelPad
    if p then
        return { left = p.left or 0, right = p.right or 0, top = p.top or 0, bottom = p.bottom or 0 }
    end
    if not size and d then size = select(2, ThemePanel(d)) end
    size = size or { border = 24, borderY = 24 }
    local px = math.floor(size.border * 0.6 + 0.5)
    local py = math.floor((size.borderY or size.border) * 0.6 + 0.5)
    return { left = px, right = px, top = py, bottom = py }
end

local function PlacePiece(tex, f, p, kx, ky)
    kx = kx or 1
    ky = ky or kx
    tex:ClearAllPoints()
    tex:SetPoint("TOPLEFT", f, p.a1, p.x1 * kx, p.y1 * ky)
    tex:SetPoint("BOTTOMRIGHT", f, p.a2, p.x2 * kx, p.y2 * ky)
end

--------------------------------------------------------------------------------
-- BACKDROP DRAWING (ALL-69.5)
--------------------------------------------------------------------------------
-- A backdrop theme: every art piece hidden and either an LSM box on the
-- frame itself (its textures sit under every child, so the text and the rows
-- draw over it) or the Window chrome; the text region is inset by the pad.

-- ── Brightness (-100..100, the sticky backgrounds' way, UI/BgLayer.lua) ──────
-- Below 0 darkens the pieces toward black (their colour times 1 + k).
-- Above 0 draws an ADD copy of each piece over it at k times its colour,
-- so light parts get brighter and dark lines stay dark (Dukul, 2026-09-28).
-- A copy lives on the piece's own frame, one sublevel up in the same draw
-- layer, and is re-synced on every draw and size change (tiled edges change
-- their texture coordinates with the size).
local BOX_BORDER = { "TopLeftCorner", "TopRightCorner", "BottomLeftCorner", "BottomRightCorner",
                     "TopEdge", "BottomEdge", "LeftEdge", "RightEdge" }

local function SyncCopy(add, src)
    local ht, vt = src:GetHorizTile(), src:GetVertTile()
    add:SetTexture(src:GetTexture(), ht and "REPEAT" or nil, vt and "REPEAT" or nil)
    add:SetTexCoord(src:GetTexCoord())
    add:SetHorizTile(ht)
    add:SetVertTile(vt)
    add:ClearAllPoints()
    add:SetAllPoints(src)
end

-- The ADD copies of sources (a list of regions) under f._searchAdds[key]:
-- shown at k (0..1) times r, g, b while k > 0 and the source is shown.
local function SetAddCopies(f, key, sources, k, r, g, b)
    f._searchAdds = f._searchAdds or {}
    local list = f._searchAdds[key] or {}
    f._searchAdds[key] = list
    list.k, list.r, list.g, list.b = k, r, g, b
    for i, src in ipairs(sources) do
        local add = list[i]
        if not add or add._src ~= src then
            if add then add:Hide() end
            local layer, sub = src:GetDrawLayer()
            add = src:GetParent():CreateTexture(nil, layer, nil, math.min(7, (sub or 0) + 1))
            add:SetBlendMode("ADD")
            add._src = src
            list[i] = add
        end
        if k > 0 and src:IsShown() then
            SyncCopy(add, src)
            add:SetVertexColor(r * k, g * k, b * k, 1)
            add:Show()
        else
            add:Hide()
        end
    end
    for i = #sources + 1, #list do list[i]:Hide() end
end

local function HideAddCopies(f, key)
    local list = f._searchAdds and f._searchAdds[key]
    if list then for _, add in ipairs(list) do add:Hide() end end
end

-- Re-sync every shown copy (after a size change).
local function ResyncAddCopies(f)
    for _, list in pairs(f._searchAdds or {}) do
        for _, add in ipairs(list) do
            if add:IsShown() and add._src then SyncCopy(add, add._src) end
        end
    end
end

local function Pieces(owner, names)
    local out = {}
    for _, n in ipairs(names) do
        local r = owner and owner[n]
        if r and r.GetTexture then out[#out + 1] = r end
    end
    return out
end

-- Brightness as (multiplier for the base colour, ADD strength).
local function Bright(v)
    local k = (v or 0) / 100
    if k < 0 then return 1 + k, 0 end
    return 1, k
end

-- Size changes: the backdrop's tiled edges, then the ADD copies.
local function HookSize(f)
    if f._searchBdHooked then return end
    f._searchBdHooked = true
    f:HookScript("OnSizeChanged", function(self)
        if self._searchBackdrop and self.OnBackdropSizeChanged then
            pcall(self.OnBackdropSizeChanged, self)
        end
        ResyncAddCopies(self)
    end)
end

-- The tint on a texture: the sticky's Colorize (UI/StickyNote.lua), so a
-- background looks the same on the bar as on a note.
local function Tinted(s)
    local K = BNB.Sticky and BNB.Sticky._kit
    if K and K.TintedBgColor then return K.TintedBgColor(s) end
    return 1, 1, 1
end

-- The background texture on a BgLayer under the host, inset by the border
-- offset. Returns true when a texture shows (the host's centre goes clear).
local function ApplyBgTexture(f, s)
    local SBG = BNB.StickyBG
    local def = SBG and SBG.Get(s.bgTexture)
    if not (def and def.file) then
        if f._searchBgLayer then BNB.BgLayer.Set(f._searchBgLayer, nil) end
        return false
    end
    f._searchBgLayer = f._searchBgLayer or BNB.BgLayer.Create(f)
    local layer = f._searchBgLayer
    BNB.BgLayer.Set(layer, def, s.borderOffset)
    local tr, tg, tb = Tinted(s)
    BNB.BgLayer.SetColors(layer, s.bgR, s.bgG, s.bgB, tr, tg, tb, s.bgBrightness)
    BNB.BgLayer.SetAlpha(layer, s.alpha)
    return true
end

-- The host's own backdrop: plain colour (clear under a texture) inside the
-- border offset, and an LSM border's edge. Border brightness as above.
local function ApplyHostBackdrop(f, s, texShown)
    BNB.EnsureBackdrop(f)
    HookSize(f)
    local edgeFile = EdgeFile(s)
    local ins = s.borderOffset
    f._searchBackdrop = true
    f:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = edgeFile, edgeSize = edgeFile and s.edge or nil,
        insets = { left = ins, right = ins, top = ins, bottom = ins },
    })
    if texShown then f:SetBackdropColor(0, 0, 0, 0)
    else f:SetBackdropColor(s.bgR, s.bgG, s.bgB, s.alpha) end
    local m, a = Bright(s.borderLight)
    f:SetBackdropBorderColor(m, m, m, edgeFile and 1 or 0)
    SetAddCopies(f, "boxBorder", edgeFile and Pieces(f, BOX_BORDER) or {}, a, 1, 1, 1)
end

-- The Default border: Blizzard's nine-slice on a child frame at the host's
-- own level (SetLevelTree keeps it there, under the text and the rows).
local function ShowNine(f, s)
    local W = BNB.SEARCH_WINDOW
    local nine = f._searchNine
    if not nine then
        local ok, fr = pcall(CreateFrame, "Frame", nil, f, "NineSlicePanelTemplate")
        nine = ok and fr or CreateFrame("Frame", nil, f)
        nine:EnableMouse(false)
        f._searchNine = nine
    end
    nine:SetFrameLevel(f:GetFrameLevel())
    -- Thickness scales the border art; SetAllPoints keeps its outer edge on
    -- the host at any scale.
    nine:SetScale(s.borderScale / 100)
    nine:ClearAllPoints()
    nine:SetAllPoints(f)
    if nine._layout ~= W.layout and NineSliceUtil and NineSliceUtil.ApplyLayoutByName then
        if pcall(NineSliceUtil.ApplyLayoutByName, nine, W.layout) then nine._layout = W.layout end
    end
    nine:Show()
    local m, a = Bright(s.borderLight)
    local pieces = Pieces(nine, BOX_BORDER)
    for _, r in ipairs(pieces) do r:SetVertexColor(m, m, m) end
    SetAddCopies(f, "nineBorder", pieces, a, 1, 1, 1)
end

local function HideNine(f)
    if f._searchNine then f._searchNine:Hide() end
    HideAddCopies(f, "nineBorder")
end

-- Forever: the main window's glow over its wood grain, when that is the
-- background (UI/Chrome.lua AddForeverGlow).
local function ShowGlow(f, s, on)
    local glow = f._searchWinGlow
    if not on then if glow then glow:Hide() end return end
    if not glow then
        glow = f:CreateTexture(nil, "BACKGROUND", nil, -6)
        glow:SetTexture(BNB.FOREVER_GLOW_TEXTURE)
        f._searchWinGlow = glow
    end
    local ins = s.borderOffset
    glow:ClearAllPoints()
    glow:SetPoint("TOPLEFT", f, "TOPLEFT", ins, -ins)
    glow:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -ins, ins)
    glow:SetAlpha(s.alpha)
    glow:Show()
end

-- Takes everything a backdrop theme drew off a frame (a drawn theme next).
local function ClearBox(f)
    HideAddCopies(f, "boxBorder")
    HideNine(f)
    ShowGlow(f, nil, false)
    if f._searchBgLayer then BNB.BgLayer.Set(f._searchBgLayer, nil) end
    if f._searchBackdrop then
        f._searchBackdrop = nil
        if f.ClearBackdrop then f:ClearBackdrop() else f:SetBackdrop(nil) end
    end
end

local BAR_W = 500
local function ApplyBackdrop(f, d, panel)
    local s = BNB.GetSearchBackdrop(d.id)
    local pad = BackdropPad(s)
    f._searchPieces = f._searchPieces or {}
    for key, tex in pairs(f._searchPieces) do
        if key ~= "text" then tex:Hide() end
    end
    local texShown = ApplyBgTexture(f, s)
    ApplyHostBackdrop(f, s, texShown)
    if s.border == WINDOW then ShowNine(f, s) else HideNine(f) end
    ShowGlow(f, s, BNB.IsForever and texShown and s.bgTexture == "windowbg")
    local size = { border = pad, borderY = pad }
    if not panel then
        -- Tall enough for the typed text at its size.
        size.w = BAR_W
        size.h = math.floor(s.fontSize + 2 * pad + 12)
        f:SetSize(size.w, size.h)
        local text = f._searchPieces.text
        if not text then
            text = f:CreateTexture(nil, "ARTWORK", nil, 1)
            f._searchPieces.text = text
        end
        text:ClearAllPoints()
        text:SetPoint("TOPLEFT", f, "TOPLEFT", pad + 4, -pad)
        text:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -(pad + 4), pad)
        text:Hide()
    end
    return size
end

-- Draws (or re-draws) a theme on f and sizes f to it. layout / size override
-- the theme's own (the layout tool passes its working copy). The "text" piece
-- gets no texture: f._searchPieces.text is a bare region marker the caller
-- anchors its EditBox to. Switching theme on a live frame is fine.
-- opts.panel: for a frame the caller sizes itself (the Oracle results
-- panel): the theme's panelLayout / panelSize / panelFiles (layout and size
-- then mean the panel's), the panel's own ornaments, no bar ornament, no
-- text region, no SetSize.
-- Returns the size table used, so a caller can pad by size.border.
function BNB.ApplySearchChrome(f, themeID, layout, size, opts)
    local d = BNB.GetSearchTheme(themeID)
    if not d then return end
    local panel = opts and opts.panel
    if IsBackdrop(d) then return ApplyBackdrop(f, d, panel) end
    ClearBox(f)
    local tl, ts
    if panel then tl, ts = ThemePanel(d) else tl, ts = ThemeLayout(d) end
    layout, size = layout or tl, size or ts
    local kx, ky = size.border / NATIVE, (size.borderY or size.border) / NATIVE
    if not panel then f:SetSize(size.w, size.h) end
    f._searchPieces = f._searchPieces or {}
    for _, def in ipairs(PIECES) do
        local tex = f._searchPieces[def.key]
        if not tex then
            tex = f:CreateTexture(nil, def.layer, nil, def.sub)
            f._searchPieces[def.key] = tex
        end
        -- Depth (ORNAMENTS above): moved to the over frame for "top".
        local lp = layout[def.key]
        local depth = ORNAMENTS[def.key] and lp and lp.layer
        if depth == "top" then
            if not f._searchOver then
                f._searchOver = CreateFrame("Frame", nil, f)
                f._searchOver:SetAllPoints(f)
            end
            f._searchOver:SetFrameLevel(f:GetFrameLevel() + TOP_LIFT)
            tex:SetParent(f._searchOver)
            tex:SetDrawLayer("OVERLAY", 6)
        else
            tex:SetParent(f)
            if depth == "back" then tex:SetDrawLayer("BORDER", -1)
            else tex:SetDrawLayer(def.layer, def.sub) end
        end
        local file = def.file
        local fk = def.same or def.key
        if d.files and d.files[fk] ~= nil then file = d.files[fk] end
        if panel and d.panelFiles and d.panelFiles[fk] ~= nil then file = d.panelFiles[fk] end
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
        if (panel and def.barOnly) or (not panel and def.panelOnly) then p = nil end
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
-- A tall panel on the left of the screen, grouped: the search bar's pieces,
-- the results panel's pieces (its own copy, placed apart from the bar's),
-- the selected piece, and the tool buttons. The preview is the whole Oracle
-- in the middle of the screen: the bar plus a results panel with fake rows
-- (UI/Oracle.lua DrawPreview), so a theme is judged on what players see.
-- The Move anchor drags the whole preview (right-click: back to the centre).
local tool

local TOOL_W, TOOL_H = 300, 824
local TOOL_PAD = 10
local WHITE = "Interface\\Buttons\\WHITE8x8"

-- The results panel's placement under the bar (panelPos) is not art; it is
-- selected and moved like a piece of the panel.
local PLACE = "placement"
-- Where the results sit inside the panel (panelPad): selected and moved
-- like the placement. Neither is a piece of art.
local CONTENT = "content"
local function Special(sel) return sel == PLACE or sel == CONTENT end

-- Short button labels where the key is long.
local LABEL = {
    topornament = "top mid", bottomornament = "bottom mid",
    pornament1 = "ornament 1", pornament2 = "ornament 2",
    pornament3 = "ornament 3", pornament4 = "ornament 4",
}

-- Where a piece goes when it is added to a theme that does not use it yet.
-- Anything else starts from the bar's own piece (on the panel) or the
-- default theme's layout (on the bar).
local ADD_DEFAULT = {
    top2           = { a1 = "TOP",         x1 =  32, y1 =  0, a2 = "TOPRIGHT",    x2 = -32, y2 = -32 },
    bottom2        = { a1 = "BOTTOM",      x1 =  32, y1 = 32, a2 = "BOTTOMRIGHT", x2 = -32, y2 =   0 },
    topornament    = { a1 = "TOP",         x1 = -32, y1 =  0, a2 = "TOP",         x2 =  32, y2 = -32 },
    bottomornament = { a1 = "BOTTOM",      x1 = -32, y1 = 32, a2 = "BOTTOM",      x2 =  32, y2 =   0 },
    pornament1     = { a1 = "TOPLEFT",     x1 = -16, y1 = 16, a2 = "TOPLEFT",     x2 =  16, y2 = -16 },
    pornament2     = { a1 = "TOPRIGHT",    x1 = -16, y1 = 16, a2 = "TOPRIGHT",    x2 =  16, y2 = -16 },
    pornament3     = { a1 = "BOTTOMLEFT",  x1 = -16, y1 = 16, a2 = "BOTTOMLEFT",  x2 =  16, y2 = -16 },
    pornament4     = { a1 = "BOTTOMRIGHT", x1 = -16, y1 = 16, a2 = "BOTTOMRIGHT", x2 =  16, y2 = -16 },
}
-- Pieces that can never be removed.
local KEEP = { bg = true, text = true }

-- Which pieces belong on which side.
local function OnSide(side, def)
    if side == "panel" then return not def.barOnly end
    return not def.panelOnly
end

local function CopyPiece(p)
    return { a1 = p.a1, x1 = p.x1, y1 = p.y1, a2 = p.a2, x2 = p.x2, y2 = p.y2, layer = p.layer }
end

local function CopyLayout(src)
    local out = {}
    for k, p in pairs(src) do out[k] = CopyPiece(p) end
    return out
end

-- The working copy lives in BNB.LabDB(), one per theme, so a /reload
-- keeps it. It starts as a copy of the theme's built-in layouts. removed /
-- panelRemoved list pieces taken out in the tool, so built-in ones stay out.
local function Work()
    local db = BNB.LabDB()
    db.devSearchLayout, db.devSearchSize = nil, nil   -- pre-theme keys (never shipped)
    db.devSearch = db.devSearch or {}
    local d = BNB.GetSearchTheme(tool.theme)
    local tl, ts = ThemeLayout(d)
    local pl, ps = ThemePanel(d)
    local w = db.devSearch[tool.theme]
    if not w then
        w = { layout = CopyLayout(tl),
              size = { w = ts.w, h = ts.h, border = ts.border, borderY = ts.borderY } }
        db.devSearch[tool.theme] = w
    end
    w.removed, w.panelRemoved = w.removed or {}, w.panelRemoved or {}
    if not w.panelLayout then
        w.panelLayout = CopyLayout(pl)
        w.panelSize = { border = ps.border, borderY = ps.borderY }
    end
    for k, p in pairs(tl) do   -- a piece added to the theme later
        if not w.layout[k] and not w.removed[k] then w.layout[k] = CopyPiece(p) end
    end
    for k, p in pairs(pl) do
        if not w.panelLayout[k] and not w.panelRemoved[k] then w.panelLayout[k] = CopyPiece(p) end
    end
    w.size.borderY = w.size.borderY or w.size.border
    w.panelSize.borderY = w.panelSize.borderY or w.panelSize.border
    -- A theme with a panelPad of its own starts from it; otherwise
    -- panelPad stays nil until the content is moved, so it keeps following
    -- the panel border until then (WorkPad).
    if w.panelPad == nil and type(BNB.GetSearchTheme(tool.theme).panelPad) == "table" then
        w.panelPad = BNB.GetSearchPanelPad(tool.theme)
    end
    if not w.panelPos then
        local pp = BNB.GetSearchPanelPos(tool.theme)
        w.panelPos = { left = pp.left, right = pp.right, gap = pp.gap, under = pp.under }
    end
    return w
end

-- The content inset in use: the working copy's, else the default for the
-- working panel border. edit = true makes it the working copy's own.
local function WorkPad(w, edit)
    if w.panelPad then return w.panelPad end
    local d = BNB.GetSearchPanelPad(nil, w.panelSize)
    if edit then w.panelPad = d end
    return d
end

-- The selected-result colour in use: the working copy's (set with the
-- tool's Highlight swatch), else the theme's own. edit = true makes it the
-- working copy's own.
local function WorkHL(w, edit)
    if w.highlight then return w.highlight end
    local r, g, b, a = BNB.GetSearchHighlight(tool.theme)
    local h = { r, g, b, a }
    if edit then w.highlight = h end
    return h
end

-- layout, size and removed list of one side of the working copy.
local function Side(side)
    local w = Work()
    if side == "panel" then return w.panelLayout, w.panelSize, w.panelRemoved, w end
    return w.layout, w.size, w.removed, w
end

-- Whole numbers print bare, anything else with two decimals.
local function Num(n)
    if n == math.floor(n) then return string.format("%d", n) end
    return string.format("%.2f", n)
end

-- Pieces that share a size when "Same size for matching pieces" is ticked
-- (on the same side only).
local GROUPS = {
    top = "tb", bottom = "tb", top2 = "tb", bottom2 = "tb", left = "lr", right = "lr",
    topleft = "c", topright = "c", bottomleft = "c", bottomright = "c",
    topornament = "mid", bottomornament = "mid",
    pornament1 = "po", pornament2 = "po", pornament3 = "po", pornament4 = "po",
}

local function PieceDef(key)
    for _, def in ipairs(PIECES) do
        if def.key == key then return def end
    end
end

-- Every used piece as { side, key }, bar first, then the panel and its
-- placement: Tab walks these.
local function UsedList()
    local out = {}
    for _, side in ipairs({ "bar", "panel" }) do
        local layout = Side(side)
        for _, def in ipairs(PIECES) do
            if OnSide(side, def) and layout[def.key] then out[#out + 1] = { side, def.key } end
        end
    end
    out[#out + 1] = { "panel", PLACE }
    out[#out + 1] = { "panel", CONTENT }
    return out
end

-- The selection, moved to the first used piece when the current one is not
-- used (a theme switch, or the piece was removed).
local function ValidSel()
    if Special(tool.sel) then return end
    if Side(tool.side)[tool.sel] then return end
    local first = UsedList()[1]
    tool.side, tool.sel = first[1], first[2]
end

-- Which edge of a piece stays put when its size is typed in: the side both
-- of its points hang off. nil = the piece stretches with its frame on that axis.
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

-- Where frame point pt sits, from the frame's top-left, in screen px.
local function PointXY(pt, w, h)
    local x = pt:find("LEFT") and 0 or pt:find("RIGHT") and w or w / 2
    local y = pt:find("TOP") and 0 or pt:find("BOTTOM") and -h or -h / 2
    return x, y
end

-- Size on screen, in px, of a piece that stretches on axis: where its two
-- points land on host at the host's current size.
local function StretchSize(p, axis, k, host)
    local w, h = host:GetSize()
    local x1, y1 = PointXY(p.a1, w, h)
    local x2, y2 = PointXY(p.a2, w, h)
    if axis == "h" then return (y1 + p.y1 * k) - (y2 + p.y2 * k) end
    return (x2 + p.x2 * k) - (x1 + p.x1 * k)
end

-- Grows or shrinks a stretching piece to px on axis, evenly on both sides
-- so it stays centred. It still hangs off both points, so it keeps
-- following its frame (Dukul, 2026-09-27).
local function SetStretchSize(p, axis, px, k, host)
    local d = (px - StretchSize(p, axis, k, host)) / k / 2
    if axis == "h" then p.y1 = p.y1 + d; p.y2 = p.y2 - d
    else p.x1 = p.x1 - d; p.x2 = p.x2 + d end
end

local function SetPieceSize(p, axis, px, k)
    local v, side = px / k, FixedSide(p, axis)
    if side == "TOP" then p.y2 = p.y1 - v
    elseif side == "BOTTOM" then p.y1 = p.y2 + v
    elseif side == "LEFT" then p.x2 = p.x1 + v
    elseif side == "RIGHT" then p.x1 = p.x2 - v end
end

-- A files override as Lua source, one piece per entry.
local function FilesText(files)
    local keys = {}
    for k in pairs(files) do keys[#keys + 1] = k end
    table.sort(keys)
    local parts = {}
    for _, k in ipairs(keys) do
        local v = files[k]
        parts[#parts + 1] = string.format("%s = %s", k, v == false and "false" or string.format("%q", tostring(v)))
    end
    return "{ " .. table.concat(parts, ", ") .. " }"
end

-- The whole Register call: both layouts, sizes and the panel placement from
-- the working copy, everything else (files, panelFiles, panelBg, highlight)
-- as registered.
local function ExportText()
    local w = Work()
    local d = BNB.GetSearchTheme(tool.theme)
    local lines = { "Register({",
        string.format("    name   = %q,", d.name),
        d.folder and string.format("    folder = %q,", d.folder) or string.format("    path   = %q,", d.art) }
    local function LayoutLines(name, side, layout)
        lines[#lines + 1] = "    " .. name .. " = {"
        for _, def in ipairs(PIECES) do
            local p = OnSide(side, def) and layout[def.key]   -- nil: not used
            if p then
                lines[#lines + 1] = string.format(
                    "        %-14s = { a1 = %q, x1 = %s, y1 = %s, a2 = %q, x2 = %s, y2 = %s%s },",
                    def.key, p.a1, Num(p.x1), Num(p.y1), p.a2, Num(p.x2), Num(p.y2),
                    p.layer and string.format(", layer = %q", p.layer) or "")
            end
        end
        lines[#lines + 1] = "    },"
    end
    LayoutLines("layout", "bar", w.layout)
    lines[#lines + 1] = string.format("    size = { w = %d, h = %d, border = %d, borderY = %d },",
        w.size.w, w.size.h, w.size.border, w.size.borderY)
    LayoutLines("panelLayout", "panel", w.panelLayout)
    lines[#lines + 1] = string.format("    panelSize = { border = %d, borderY = %d },",
        w.panelSize.border, w.panelSize.borderY)
    lines[#lines + 1] = string.format("    panelPos = { left = %s, right = %s, gap = %s, under = %s },",
        Num(w.panelPos.left), Num(w.panelPos.right), Num(w.panelPos.gap), tostring(w.panelPos.under ~= false))
    if w.panelPad then
        lines[#lines + 1] = string.format("    panelPad = { left = %s, right = %s, top = %s, bottom = %s },",
            Num(w.panelPad.left), Num(w.panelPad.right), Num(w.panelPad.top), Num(w.panelPad.bottom))
    end
    if type(d.files) == "table" and next(d.files) then
        lines[#lines + 1] = "    files = " .. FilesText(d.files) .. ","
    end
    if type(d.panelFiles) == "table" and next(d.panelFiles) then
        lines[#lines + 1] = "    panelFiles = " .. FilesText(d.panelFiles) .. ","
    end
    if d.panelBg then lines[#lines + 1] = string.format("    panelBg = %q,", d.panelBg) end
    local h = w.highlight or d.highlight
    if type(h) == "table" then
        lines[#lines + 1] = string.format("    highlight = { %s, %s, %s, %s },",
            Num(h[1] or 1), Num(h[2] or 0.82), Num(h[3] or 0), Num(h[4] or 0.14))
    end
    lines[#lines + 1] = "})"
    return table.concat(lines, "\n")
end

-- Moves the highlight over the selected piece, or over the whole results
-- panel when its placement is selected.
local function PlaceHighlight()
    local hl = tool.hl
    local host = (tool.side == "panel") and tool.panel or tool.bar
    hl:SetParent(host)
    hl:ClearAllPoints()
    if tool.sel == PLACE then
        hl:SetAllPoints(host)
    elseif tool.sel == CONTENT then
        local pad = WorkPad(Work())
        hl:SetPoint("TOPLEFT", host, "TOPLEFT", pad.left, -pad.top)
        hl:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", -pad.right, pad.bottom)
    else
        local layout, size = Side(tool.side)
        local p = layout[tool.sel]
        -- Over a "top" ornament too, which sits on the over frame.
        if ORNAMENTS[tool.sel] and p.layer == "top" and host._searchOver then hl:SetParent(host._searchOver) end
        PlacePiece(hl, host, p, size.border / NATIVE, size.borderY / NATIVE)
    end
    hl:SetDrawLayer("OVERLAY", 7)
    hl:SetShown(tool.showHL)
end

-- Ornament depth: the button steps through these (see ORNAMENTS).
local DEPTHS = { "own", "back", "top" }
local DEPTH_NAME = { own = "Over borders", back = "Behind borders", top = "Over everything" }

-- A results-panel piece hung from TOP points whose middle sits in the
-- panel's lower half: it keeps its distance from the top, so it drifts into
-- the results as they grow (Horde 2026-09-26, Molten Core 2026-09-27).
local function HangsWrong(p)
    if tool.side ~= "panel" or not p or Special(tool.sel) then return false end
    if not (p.a1:find("TOP") and p.a2:find("TOP")) then return false end
    local _, size = Side("panel")
    local ky = size.borderY / NATIVE
    local w, h = tool.panel:GetSize()
    local _, y1 = PointXY(p.a1, w, h)
    local _, y2 = PointXY(p.a2, w, h)
    return ((y1 + p.y1 * ky) + (y2 + p.y2 * ky)) / 2 < -h / 2
end

local function Refresh()
    local w = Work()
    ValidSel()
    local bar, panel = tool.bar, tool.panel
    BNB.ApplySearchChrome(bar, tool.theme, w.layout, w.size)
    panel._size = BNB.ApplySearchChrome(panel, tool.theme, w.panelLayout, w.panelSize, { panel = true })
    BNB.PlaceSearchPanel(panel, bar, tool.theme, w.panelPos)
    panel._pad = WorkPad(w)
    panel._hl = WorkHL(w)
    if BNB.Oracle and BNB.Oracle.DrawPreview then BNB.Oracle.DrawPreview(panel, tool.theme, tool.rows) end
    tool.title:SetText("Search bar layout (ALL-69)\n|cffffffff" .. BNB.GetSearchTheme(tool.theme).name .. "|r")
    PlaceHighlight()
    tool.anchor:SetShown(tool.showAnchor)

    -- Every piece has a button; one the theme does not use is dimmed, and
    -- clicking it adds the piece.
    for _, b in ipairs(tool.pieceBtns) do
        local used = Special(b.key) or Side(b.side)[b.key] ~= nil
        b:SetAlpha(used and 1 or 0.4)
        b.sel:SetShown(b.side == tool.side and b.key == tool.sel)
    end
    tool.removeBtn:SetEnabled(not Special(tool.sel) and not KEEP[tool.sel])
    local orn = ORNAMENTS[tool.sel] and Side(tool.side)[tool.sel]
    tool.depthBtn:SetEnabled(orn and true or false)
    tool.depthBtn:SetText("Depth: " .. (orn and DEPTH_NAME[orn.layer or "own"] or "-"))
    local ap = not Special(tool.sel) and Side(tool.side)[tool.sel]
    local fixed = ap and ap.a1 == ap.a2
    tool.anchorBtn:SetEnabled(fixed and true or false)
    local warn = HangsWrong(ap)
    tool.anchorBtn:SetText(fixed and ((warn and "|cffff4040" or "") .. ap.a1 .. (warn and "|r" or ""))
        or "Anchor: 2 points")

    local layout, size = Side(tool.side)
    local p = layout[tool.sel]
    for axis, eb in pairs(tool.sizeBoxes) do
        local v
        if tool.sel == PLACE then
            v = (axis == "w") and (w.size.w - w.panelPos.left - w.panelPos.right) or nil
        elseif tool.sel == CONTENT then
            local pad = WorkPad(w)
            v = (axis == "w") and (panel:GetWidth() - pad.left - pad.right) or nil
        else
            local k = ((axis == "h") and size.borderY or size.border) / NATIVE
            v = PieceSize(p, axis, k)
                or (p and StretchSize(p, axis, k, (tool.side == "panel") and panel or bar))
        end
        if not eb:HasFocus() then eb:SetText(v and Num(v) or (Special(tool.sel) and "auto" or "stretch")) end
        eb:SetEnabled(v ~= nil)
        eb:SetTextColor(v and 1 or 0.5, v and 1 or 0.5, v and 1 or 0.5)
    end
    for _, box in ipairs(tool.valueBoxes) do
        if not box.eb:HasFocus() then box.eb:SetText(Num(box.get())) end
    end
    tool.underCb:SetChecked(w.panelPos.under ~= false)
    tool.hlSwatch:SetColorTexture(WorkHL(w)[1], WorkHL(w)[2], WorkHL(w)[3], 1)

    local where = (tool.side == "panel") and "Results panel" or "Search bar"
    if tool.sel == PLACE then
        tool.info:SetText(string.format(
            "|cffffd100%s: placement|r\nLeft %s   Right %s   Gap %s   Width %s\n"
            .. "Left / Right: in from the bar's edges (negative = wider).\nGap: space under the bar (negative = overlap).",
            where, Num(w.panelPos.left), Num(w.panelPos.right), Num(w.panelPos.gap),
            Num(w.size.w - w.panelPos.left - w.panelPos.right)))
    elseif tool.sel == CONTENT then
        local pad = WorkPad(w)
        tool.info:SetText(string.format(
            "|cffffd100%s: content|r\nLeft %s   Right %s   Top %s   Bottom %s\n"
            .. "Where the result rows sit inside the panel art, in from its edges.\n"
            .. "Arrows move them, Alt: top-left edges, Ctrl: bottom-right edges.",
            where, Num(pad.left), Num(pad.right), Num(pad.top), Num(pad.bottom)))
    else
        tool.info:SetText(string.format(
            "|cffffd100%s: %s|r\nTOPLEFT -> %s %s, %s\nBOTTOMRIGHT -> %s %s, %s\n%s",
            where, tool.sel, p.a1, Num(p.x1), Num(p.y1), p.a2, Num(p.x2), Num(p.y2),
            HangsWrong(p)
                and "|cffff4040Hangs from TOP but sits low: will not follow the results. Anchor it to a BOTTOM point.|r"
                or string.format("Art px x border / 32.  Zoom %dx", tool.zoom)))
    end
end

-- mode: nil = move both points, "p1" = top-left only, "p2" = bottom-right only.
-- Placement: both edges, left only (p1) or right only (p2); up / down = gap.
local function Nudge(dx, dy, mode)
    if tool.sel == PLACE then
        local pos = Work().panelPos
        if mode ~= "p2" then pos.left = pos.left + dx end
        if mode ~= "p1" then pos.right = pos.right - dx end
        pos.gap = pos.gap - dy
    elseif tool.sel == CONTENT then
        local pad = WorkPad(Work(), true)
        if mode ~= "p2" then pad.left = pad.left + dx; pad.top = pad.top - dy end
        if mode ~= "p1" then pad.right = pad.right - dx; pad.bottom = pad.bottom + dy end
    else
        local p = Side(tool.side)[tool.sel]
        if mode ~= "p2" then p.x1 = p.x1 + dx; p.y1 = p.y1 + dy end
        if mode ~= "p1" then p.x2 = p.x2 + dx; p.y2 = p.y2 + dy end
    end
    Refresh()
end

local function ModMode()
    if IsAltKeyDown() then return "p1" end
    if IsControlKeyDown() then return "p2" end
    return nil
end

-- Click on a piece button: select it, adding it first when that side does
-- not use it yet.
local function SelectOrAdd(side, key)
    if not Special(key) then
        local layout, _, removed, w = Side(side)
        if not layout[key] then
            local def = BNB.SEARCH_THEMES[BNB.SEARCH_DEFAULT_THEME]
            local src = ADD_DEFAULT[key]
                or (side == "panel" and w.layout[key])
                or (def and def.layout and def.layout[key])
                or { a1 = "CENTER", x1 = -16, y1 = 16, a2 = "CENTER", x2 = 16, y2 = -16 }
            layout[key] = CopyPiece(src)
            removed[key] = nil
        end
    end
    tool.side, tool.sel = side, key
    Refresh()
end

local function CycleDepth()
    local p = ORNAMENTS[tool.sel] and Side(tool.side)[tool.sel]
    if not p then return end
    local cur = p.layer or "own"
    for i, d in ipairs(DEPTHS) do
        if d == cur then cur = DEPTHS[i % #DEPTHS + 1]; break end
    end
    p.layer = (cur ~= "own") and cur or nil
    Refresh()
end

-- Hangs the selected fixed-size piece (both points on one frame point)
-- from the next frame point, with its offsets changed so it stays put.
local ANCHORS = { "TOPLEFT", "TOP", "TOPRIGHT", "RIGHT", "BOTTOMRIGHT", "BOTTOM", "BOTTOMLEFT", "LEFT", "CENTER" }
local function CycleAnchor()
    if Special(tool.sel) then return end
    local layout, size = Side(tool.side)
    local p = layout[tool.sel]
    if not p or p.a1 ~= p.a2 then return end
    local nxt = ANCHORS[1]
    for i, a in ipairs(ANCHORS) do
        if a == p.a1 then nxt = ANCHORS[i % #ANCHORS + 1]; break end
    end
    local host = (tool.side == "panel") and tool.panel or tool.bar
    local w, h = host:GetSize()
    local ox, oy = PointXY(p.a1, w, h)
    local nx, ny = PointXY(nxt, w, h)
    local kx, ky = size.border / NATIVE, size.borderY / NATIVE
    local dx, dy = (ox - nx) / kx, (oy - ny) / ky
    p.x1, p.x2, p.y1, p.y2 = p.x1 + dx, p.x2 + dx, p.y1 + dy, p.y2 + dy
    p.a1, p.a2 = nxt, nxt
    Refresh()
end

local function RemoveSelected()
    if Special(tool.sel) or KEEP[tool.sel] then return end
    local layout, _, removed = Side(tool.side)
    layout[tool.sel] = nil
    removed[tool.sel] = true
    Refresh()
end

-- Border thickness of one side: 2 px a click, 1 px with Shift.
local function Border(side, dir)
    local _, size = Side(side)
    local d = dir * (IsShiftKeyDown() and 1 or 2)
    size.border = math.max(4, math.min(64, size.border + d))
    size.borderY = math.max(4, math.min(64, size.borderY + d))
    Refresh()
end

-- Mouse drag on the bar or the results panel moves the selected piece
-- (Alt/Ctrl as the arrows).
local function HookDrag(frame)
    frame:EnableMouse(true)
    frame:SetScript("OnMouseDown", function(self, btn)
        if btn ~= "LeftButton" then return end
        local s = self:GetEffectiveScale()
        local cx, cy = GetCursorPosition()
        self._drag = { x = cx / s, y = cy / s, mode = ModMode(), dx = 0, dy = 0 }
    end)
    frame:SetScript("OnMouseUp", function(self) self._drag = nil end)
    frame:SetScript("OnUpdate", function(self)
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
end

local function BuildTool()
    local f = CreateFrame("Frame", "BNBSearchLayoutTool", UIParent, "BackdropTemplate")
    f:SetSize(TOOL_W, TOOL_H)
    f:SetPoint("LEFT", UIParent, "LEFT", 20, 0)
    f:SetFrameStrata("DIALOG")
    f:SetToplevel(true)
    f:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
    f:SetBackdropColor(0.05, 0.05, 0.07, 0.92)
    f:SetBackdropBorderColor(0.4, 0.4, 0.45, 1)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetClampedToScreen(true)
    tool = f
    f.side, f.sel, f.zoom, f.showHL, f.showAnchor = "bar", "topleft", 1, true, false
    f.theme = BNB.SEARCH_DEFAULT_THEME
    -- Preview result count: 8 is what the Oracle shows on an empty box.
    f.rows = 8

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", TOOL_PAD, -8)
    title:SetWidth(TOOL_W - TOOL_PAD * 2 - 20)
    title:SetJustifyH("LEFT")
    f.title = title

    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", 2, 2)
    close:SetScript("OnClick", function() f:Hide() end)

    -- The preview: the bar where the Oracle opens, the results panel under
    -- it. Shown and hidden with the tool.
    local bar = CreateFrame("Frame", nil, UIParent)
    bar:SetFrameStrata("DIALOG")
    -- Room below the bar, so the panel can draw under it (panelPos.under).
    bar:SetFrameLevel(BNB.SEARCH_BAR_LEVEL)
    bar:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    bar:SetMovable(true)
    bar:Hide()
    f.bar = bar
    local panel = CreateFrame("Frame", nil, bar)
    f.panel = panel
    HookDrag(bar)
    HookDrag(panel)

    local hl = bar:CreateTexture(nil, "OVERLAY", nil, 7)
    hl:SetColorTexture(1, 0.82, 0, 0.25)
    f.hl = hl

    -- Move anchor above the bar: drags the whole preview, right-click puts
    -- it back in the centre. Toggled with the Move button.
    local anchor = CreateFrame("Button", nil, bar, "BackdropTemplate")
    anchor:SetSize(24, 24)
    anchor:SetPoint("BOTTOM", bar, "TOP", 0, 8)
    anchor:SetFrameLevel(bar:GetFrameLevel() + 20)
    anchor:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
    anchor:SetBackdropColor(0, 0, 0, 0.7)
    anchor:SetBackdropBorderColor(1, 0.82, 0, 1)
    local aIcon = anchor:CreateTexture(nil, "ARTWORK")
    aIcon:SetPoint("TOPLEFT", 3, -3)
    aIcon:SetPoint("BOTTOMRIGHT", -3, 3)
    aIcon:SetTexture("Interface\\CURSOR\\UI-Cursor-Move")
    anchor:RegisterForDrag("LeftButton")
    anchor:RegisterForClicks("RightButtonUp")
    anchor:SetScript("OnDragStart", function() bar:StartMoving() end)
    anchor:SetScript("OnDragStop", function() bar:StopMovingOrSizing() end)
    anchor:SetScript("OnClick", function(_, btn)
        if btn ~= "RightButton" then return end
        bar:ClearAllPoints()
        bar:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    end)
    anchor:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Move the preview", 1, 1, 1)
        GameTooltip:AddLine("Drag: move bar and results together.\nRight-click: back to the centre.", 0.8, 0.8, 0.8)
        GameTooltip:Show()
    end)
    anchor:SetScript("OnLeave", function() GameTooltip:Hide() end)
    anchor:Hide()
    f.anchor = anchor

    ------------------------------------------------------------------ layout
    local y = -44
    local INNER_W = TOOL_W - TOOL_PAD * 2

    -- A titled box around a group of controls. Returns a function that
    -- closes the box at the current y.
    local function Group(text)
        local box = CreateFrame("Frame", nil, f, "BackdropTemplate")
        box:SetPoint("TOPLEFT", f, "TOPLEFT", TOOL_PAD - 4, y + 4)
        box:SetWidth(INNER_W + 8)
        box:SetFrameLevel(f:GetFrameLevel())
        box:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
        box:SetBackdropColor(1, 1, 1, 0.03)
        box:SetBackdropBorderColor(0.35, 0.35, 0.42, 0.9)
        local fs = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        fs:SetPoint("TOPLEFT", TOOL_PAD, y - 1)
        fs:SetText(text)
        local top = y + 4
        y = y - 20
        return function()
            y = y - 2
            box:SetHeight(top - y)
            y = y - 10
        end
    end

    -- Piece buttons, three to a row.
    local BTN_W = math.floor((INNER_W - 8) / 3)
    f.pieceBtns = {}
    local function PieceButtons(side, keys)
        for n, key in ipairs(keys) do
            local b = CreateFrame("Button", nil, f, BNB.PanelButtonTemplate())
            b:SetSize(BTN_W, 18)
            b:SetPoint("TOPLEFT", TOOL_PAD + ((n - 1) % 3) * (BTN_W + 4), y - math.floor((n - 1) / 3) * 20)
            b:SetNormalFontObject("GameFontHighlightSmall")
            b:SetHighlightFontObject("GameFontHighlightSmall")
            b:SetText(LABEL[key] or key)
            b.side, b.key = side, key
            b.sel = b:CreateTexture(nil, "OVERLAY")
            b.sel:SetPoint("TOPLEFT", -2, 2)
            b.sel:SetPoint("BOTTOMRIGHT", 2, -2)
            b.sel:SetColorTexture(1, 0.82, 0, 0.35)
            b:SetScript("OnClick", function() SelectOrAdd(side, key) end)
            f.pieceBtns[#f.pieceBtns + 1] = b
        end
        y = y - math.ceil(#keys / 3) * 20 - 4
    end

    -- Number boxes: Enter applies a number, Esc puts the value back.
    -- allowNeg: placement offsets may be negative.
    f.valueBoxes = {}
    local function NumBox(anchorTo, x, apply, allowNeg)
        local bg = CreateFrame("Frame", nil, f, "BackdropTemplate")
        bg:SetSize(44, 20)
        bg:SetPoint("LEFT", anchorTo, "RIGHT", x, 0)
        BNB.SetBackdropDark(bg)
        local eb = CreateFrame("EditBox", nil, bg)
        eb:SetAllPoints()
        eb:SetFontObject("GameFontHighlightSmall")
        eb:SetTextInsets(5, 5, 0, 0)
        eb:SetAutoFocus(false)
        eb:SetScript("OnEscapePressed", function(self) self:ClearFocus(); Refresh() end)
        eb:SetScript("OnEditFocusLost", function() Refresh() end)
        eb:SetScript("OnEnterPressed", function(self)
            local v = tonumber(self:GetText())
            self:ClearFocus()
            if v and (allowNeg or v > 0) then apply(v) end
            Refresh()
        end)
        return eb, bg
    end
    -- A box showing get() and setting it with set(v).
    local function ValueBox(anchorTo, x, get, set, allowNeg)
        local eb, bg = NumBox(anchorTo, x, set, allowNeg)
        f.valueBoxes[#f.valueBoxes + 1] = { eb = eb, get = get }
        return bg
    end
    local function Label(text, anchorTo, x)
        local fs = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        if anchorTo then fs:SetPoint("LEFT", anchorTo, "RIGHT", x, 0)
        else fs:SetPoint("TOPLEFT", TOOL_PAD + 2, y - 4) end
        fs:SetText(text)
        return fs
    end
    local function SmallBtn(text, anchorTo, x, fn)
        local b = CreateFrame("Button", nil, f, BNB.PanelButtonTemplate())
        b:SetSize(22, 20)
        b:SetPoint("LEFT", anchorTo, "RIGHT", x, 0)
        b:SetText(text)
        b:SetScript("OnClick", fn)
        return b
    end
    local function Row() y = y - 24 end
    local function SizeField(side, key, lo)
        return function() local _, size = Side(side); return size[key] end,
               function(v) local _, size = Side(side); size[key] = math.max(lo, math.floor(v + 0.5)) end
    end
    -- Border W / H of one side, with - and +.
    local function BorderRow(side)
        local l = Label("Border W")
        local g, s = SizeField(side, "border", 4)
        local bx = ValueBox(l, 6, g, s)
        l = Label("H", bx, 8)
        g, s = SizeField(side, "borderY", 4)
        bx = ValueBox(l, 6, g, s)
        local minus = SmallBtn("-", bx, 8, function() Border(side, -1) end)
        SmallBtn("+", minus, 2, function() Border(side, 1) end)
        Row()
    end

    local function Check(text, checked, onClick)
        local cb = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
        cb:SetSize(22, 22)
        cb:SetPoint("TOPLEFT", TOOL_PAD, y)
        cb:SetChecked(checked)
        cb:SetScript("OnClick", function(self) onClick(self:GetChecked() and true or false) end)
        local fs = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        fs:SetPoint("LEFT", cb, "RIGHT", 2, 0)
        fs:SetText(text)
        y = y - 22
        return cb
    end

    -- Group: the search bar.
    local close1 = Group("Search bar")
    local barKeys = {}
    for _, def in ipairs(PIECES) do
        if OnSide("bar", def) then barKeys[#barKeys + 1] = def.key end
    end
    PieceButtons("bar", barKeys)
    local l = Label("Size     W")
    local g, s = SizeField("bar", "w", 64)
    local bx = ValueBox(l, 6, g, s)
    l = Label("H", bx, 8)
    g, s = SizeField("bar", "h", 16)
    ValueBox(l, 6, g, s)
    Row()
    BorderRow("bar")
    close1()

    -- Group: the results panel, its own pieces and where it sits.
    local close2 = Group("Results panel")
    local panelKeys = { PLACE, CONTENT }
    for _, def in ipairs(PIECES) do
        if OnSide("panel", def) then panelKeys[#panelKeys + 1] = def.key end
    end
    PieceButtons("panel", panelKeys)
    BorderRow("panel")
    local function PosField(key)
        return function() return Work().panelPos[key] end,
               function(v) Work().panelPos[key] = v end
    end
    l = Label("Place   L")
    g, s = PosField("left")
    bx = ValueBox(l, 4, g, s, true)
    l = Label("R", bx, 6)
    g, s = PosField("right")
    bx = ValueBox(l, 4, g, s, true)
    l = Label("Gap", bx, 6)
    g, s = PosField("gap")
    ValueBox(l, 4, g, s, true)
    Row()
    local function PadField(key)
        return function() return WorkPad(Work())[key] end,
               function(v) WorkPad(Work(), true)[key] = v end
    end
    l = Label("Content L")
    g, s = PadField("left")
    bx = ValueBox(l, 4, g, s, true)
    l = Label("R", bx, 6)
    g, s = PadField("right")
    bx = ValueBox(l, 4, g, s, true)
    l = Label("T", bx, 6)
    g, s = PadField("top")
    bx = ValueBox(l, 4, g, s, true)
    l = Label("B", bx, 6)
    g, s = PadField("bottom")
    ValueBox(l, 4, g, s, true)
    Row()
    f.underCb = Check("Results under the search bar where they overlap", true, function(v)
        Work().panelPos.under = v
        Refresh()
    end)
    -- Selected-result colour (the theme's highlight): swatch for the
    -- colour, box for its alpha (0-1). Shown on the preview's first row.
    l = Label("Highlight")
    local sw = CreateFrame("Button", nil, f, "BackdropTemplate")
    sw:SetSize(44, 18)
    sw:SetPoint("LEFT", l, "RIGHT", 6, 0)
    sw:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
    sw:SetBackdropColor(0, 0, 0, 1)
    sw:SetBackdropBorderColor(0.6, 0.6, 0.6, 1)
    f.hlSwatch = sw:CreateTexture(nil, "ARTWORK")
    f.hlSwatch:SetPoint("TOPLEFT", 2, -2)
    f.hlSwatch:SetPoint("BOTTOMRIGHT", -2, 2)
    sw:SetScript("OnClick", function()
        local h = WorkHL(Work(), true)
        local old = { h[1], h[2], h[3] }
        BNB.OpenColorPicker(h[1], h[2], h[3],
            function(r, g, b) h[1], h[2], h[3] = r, g, b; Refresh() end,
            function() h[1], h[2], h[3] = old[1], old[2], old[3]; Refresh() end)
    end)
    l = Label("Alpha", sw, 10)
    ValueBox(l, 4, function() return WorkHL(Work())[4] end,
        function(v) WorkHL(Work(), true)[4] = math.max(0, math.min(1, v)) end)
    Row()
    close2()

    -- Group: the selected piece.
    local close3 = Group("Selected piece")
    local info = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    info:SetPoint("TOPLEFT", TOOL_PAD + 2, y)
    info:SetWidth(INNER_W - 4)
    info:SetHeight(56)
    info:SetJustifyH("LEFT")
    info:SetJustifyV("TOP")
    f.info = info
    y = y - 60

    -- Size in screen pixels. The edge that hangs off the frame stays put; on
    -- a stretching axis the piece grows from its centre and keeps stretching. Placement: the panel's
    -- width (its right edge moves), height is automatic.
    f.sizeBoxes, f.linkSizes = {}, true
    local function PieceApply(axis)
        return function(px)
            if tool.sel == PLACE then
                local w = Work()
                if axis == "w" then w.panelPos.right = w.size.w - w.panelPos.left - px end
                return
            end
            -- Content: the width, evenly from both sides.
            if tool.sel == CONTENT then
                if axis == "w" then
                    local pad = WorkPad(Work(), true)
                    local d = (tool.panel:GetWidth() - pad.left - pad.right - px) / 2
                    pad.left, pad.right = pad.left + d, pad.right + d
                end
                return
            end
            local layout, size = Side(tool.side)
            local k = ((axis == "h") and size.borderY or size.border) / NATIVE
            -- An ornament with Keep square: both sides take px and it grows
            -- from its centre, so it stays put while it changes size.
            local ep = layout[tool.sel]
            local def = PieceDef(tool.sel)
            local isOrnament = tool.sel == "ornament" or (def and def.panelOnly)
            if isOrnament and f.keepSquare and FixedSide(ep, "w") and FixedSide(ep, "h") then
                local kx, ky = size.border / NATIVE, size.borderY / NATIVE
                local cx, cy = (ep.x1 + ep.x2) / 2, (ep.y1 + ep.y2) / 2
                local hw, hh = px / kx / 2, px / ky / 2
                ep.x1, ep.x2, ep.y1, ep.y2 = cx - hw, cx + hw, cy + hh, cy - hh
                return
            end
            -- A stretching piece (the background, an edge along its
            -- length): only this one, from its centre.
            if not FixedSide(ep, axis) then
                SetStretchSize(ep, axis, px, k, (tool.side == "panel") and tool.panel or tool.bar)
                return
            end
            local grp = GROUPS[tool.sel]
            for key, pp in pairs(layout) do
                if key == tool.sel or (f.linkSizes and grp and GROUPS[key] == grp) then
                    if FixedSide(pp, axis) then SetPieceSize(pp, axis, px, k) end
                end
            end
        end
    end
    l = Label("Size     W")
    local e
    e, bx = NumBox(l, 6, PieceApply("w"));    f.sizeBoxes.w = e
    l = Label("H", bx, 8)
    e, bx = NumBox(l, 6, PieceApply("h"));    f.sizeBoxes.h = e
    local rm = CreateFrame("Button", nil, f, BNB.PanelButtonTemplate())
    rm:SetSize(64, 20)
    rm:SetPoint("LEFT", bx, "RIGHT", 8, 0)
    rm:SetText("Remove")
    rm:SetScript("OnClick", RemoveSelected)
    f.removeBtn = rm
    Row()
    -- Two half-width buttons: the ornament's depth and the point a piece
    -- hangs from.
    local HALF = math.floor((INNER_W - 4) / 2)
    local function HalfBtn(x, fn, tipTitle, tip)
        local b = CreateFrame("Button", nil, f, BNB.PanelButtonTemplate())
        b:SetSize(HALF, 20)
        b:SetPoint("TOPLEFT", TOOL_PAD + x, y)
        b:SetNormalFontObject("GameFontHighlightSmall")
        b:SetHighlightFontObject("GameFontHighlightSmall")
        b:SetDisabledFontObject("GameFontDisableSmall")
        b:SetScript("OnClick", fn)
        b:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(tipTitle, 1, 1, 1)
            GameTooltip:AddLine(tip, 0.8, 0.8, 0.8, true)
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        return b
    end
    f.depthBtn = HalfBtn(0, CycleDepth, "Ornament depth",
        "Over borders: the piece's own place.\nBehind borders: over the background only."
        .. "\nOver everything: over the other frame, the text and the rows too.")
    f.anchorBtn = HalfBtn(HALF + 4, CycleAnchor, "Anchor",
        "The frame point the piece hangs from. It stays where it is when you change it. "
        .. "Hang a piece from the edge it should follow: a results ornament near the bottom "
        .. "from a BOTTOM point, or it moves as the results grow and shrink.")
    Row()

    Check("Same size for matching pieces", true, function(v) f.linkSizes = v end)
    f.keepSquare = true
    Check("Ornaments: keep square", true, function(v) f.keepSquare = v end)
    close3()

    local help = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    help:SetPoint("TOPLEFT", TOOL_PAD, y)
    help:SetWidth(INNER_W)
    help:SetJustifyH("LEFT")
    help:SetText("Arrows / drag: move.  Alt: top-left point only, Ctrl: bottom-right point "
        .. "only (resize).  Shift: 5 px.  Tab: next piece.  Dimmed button: not used, click to add.  "
        .. "Placement: arrows move the panel, Alt / Ctrl one edge, up / down the gap.  "
        .. "Content: where the rows sit inside the panel; W sets their width.  "
        .. "Rows: check that results pieces follow the panel as it grows.")

    -- Tool buttons, four to a row from the bottom up.
    local BW = math.floor((INNER_W - 12) / 4)
    local btnN = 0
    local function Btn(label, fn)
        local b = CreateFrame("Button", nil, f, BNB.PanelButtonTemplate())
        b:SetSize(BW, 20)
        local row, col = math.floor(btnN / 4), btnN % 4
        b:SetPoint("BOTTOMLEFT", TOOL_PAD + col * (BW + 4), 8 + (1 - row) * 24)
        b:SetText(label)
        b:SetScript("OnClick", fn)
        btnN = btnN + 1
        return b
    end
    -- Theme: steps through BNB.SEARCH_THEME_ORDER; each keeps its own copy.
    -- Backdrop themes have no pieces to place and are skipped (ALL-69.5).
    local function DrawnThemes()
        local order = {}
        for _, id in ipairs(BNB.SEARCH_THEME_ORDER) do
            if not IsBackdrop(BNB.SEARCH_THEMES[id]) then order[#order + 1] = id end
        end
        return order
    end
    local themeBtn = Btn("Theme", function()
        local order = DrawnThemes()
        for i, id in ipairs(order) do
            if id == f.theme then f.theme = order[i % #order + 1]; break end
        end
        Refresh()
    end)
    themeBtn:SetEnabled(#DrawnThemes() > 1)
    Btn("Zoom", function()
        f.zoom = (f.zoom % 3) + 1
        bar:SetScale(f.zoom)
        Refresh()
    end)
    Btn("Highlight", function() f.showHL = not f.showHL; Refresh() end)
    Btn("Move", function() f.showAnchor = not f.showAnchor; Refresh() end)
    local ROW_STEPS = { 8, 5, 3, 1 }
    local rowsBtn
    rowsBtn = Btn("Rows: 8", function()
        for i, n in ipairs(ROW_STEPS) do
            if n == f.rows then f.rows = ROW_STEPS[i % #ROW_STEPS + 1]; break end
        end
        rowsBtn:SetText("Rows: " .. f.rows)
        Refresh()
    end)
    Btn("Reset", function()
        local db = BNB.LabDB()
        if db.devSearch then db.devSearch[f.theme] = nil end
        Refresh()
    end)
    Btn("Export", function() BNB.ShowClipboardHint(ExportText(), f, true) end)

    -- Keys: handled ones are swallowed, the rest propagate.
    BNB.RegisterKeyboardFrame(f)
    f:EnableKeyboard(true)
    f:SetScript("OnKeyDown", function(self, key)
        if InCombatLockdown() then return end
        local step = IsShiftKeyDown() and 5 or 1
        local mode = ModMode()
        local _, size = Side("bar")
        local handled = true
        if key == "LEFT" then Nudge(-step, 0, mode)
        elseif key == "RIGHT" then Nudge(step, 0, mode)
        elseif key == "UP" then Nudge(0, step, mode)
        elseif key == "DOWN" then Nudge(0, -step, mode)
        elseif key == "TAB" then
            -- Next (Shift: previous) used piece: the bar's, then the panel's.
            local used = UsedList()
            for i, it in ipairs(used) do
                if it[1] == f.side and it[2] == f.sel then
                    local nx = used[IsShiftKeyDown() and (i - 2) % #used + 1 or i % #used + 1]
                    f.side, f.sel = nx[1], nx[2]
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
    local w0 = Work()
    BNB.ApplySearchChrome(bar, f.theme, w0.layout, w0.size)
    sample:SetPoint("LEFT", bar._searchPieces.text, "LEFT", 0, 0)
    sample:SetPoint("RIGHT", bar._searchPieces.text, "RIGHT", 0, 0)

    f:SetScript("OnShow", function() bar:Show(); Refresh() end)
    f:SetScript("OnHide", function() bar:Hide() end)
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

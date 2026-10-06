-- BigNoteBox UI/SearchChrome.lua -- Search bar themes (ALL-69); their layout tool is
-- in BigNoteBox_Dev (Labs/SearchLayoutTool.lua, ARCH-04)
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

-- What the search layout tool (BigNoteBox_Dev Labs/SearchLayoutTool.lua,
-- ARCH-04) reads of this file's private pieces.
BNB._SearchKit = {
    PIECES = PIECES, ORNAMENTS = ORNAMENTS, NATIVE = NATIVE,
    IsBackdrop = IsBackdrop, PlacePiece = PlacePiece,
    ThemeLayout = ThemeLayout, ThemePanel = ThemePanel,
}

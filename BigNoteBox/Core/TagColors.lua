-- BigNoteBox Core/TagColors.lua -- A colour per tag (ALL-106)
--
-- One colour for a tag on every note, picked from a short curated list
-- (Dukul, 2026-10-17: "our curated colors only, so no color picker at all.
-- The default is no color at all"). Saved in BigNoteBoxNotesDB.tagColors keyed by
-- the tag in lower case, the value a palette key, so the palette can be tuned
-- later without touching saved data. A key no longer in the palette reads as
-- no colour.
--
-- Game colours (Dukul, 2026-10-17: "have tags called "Alliance" "Horde"
-- "Priest" "Shaman" etc. etc. their actual colors (ofc let people change it
-- if they want", "And make these the default color for those"): a tag named
-- after a class (the client's names, both genders, or the class token such
-- as "Deathknight") or a faction starts in the game's colour for it
-- (RAID_CLASS_COLORS, PLAYER_FACTION_COLORS, on every client). Picking a
-- palette colour replaces it; "No colour" is then saved as "none"; "Game
-- colour" in the menu goes back to it.
--
-- Shown on: tag chips (tinted fill and border, white text), tag tree headers
-- and Tag Manager rows (name in the colour), the tag autocompletes and the
-- colour menu (Dukul's white swatch Assets/UI/ui-color-swatch, tinted).
--
-- PUBLIC API (BNB.TagColors):
--   TC.LIST                  { { key, r, g, b, label }, ... } in menu order
--   TC.Key(tag)              palette key or nil
--   TC.Get(tag)              r, g, b or nil (the player's pick, else the game's)
--   TC.Game(tag)             r, g, b, label of its game colour, or nil
--   TC.Set(tag, key)         key = a palette key, "none", or nil = the default
--                            (game colour or none); sends "TagColorChanged"(tag)
--   TC.Move(old, new)        carries a colour to a renamed tag (RenameTag)
--   TC.Drop(tag)             forgets it (DeleteTag)
--   TC.Text(tag, text)       text (default the tag) wrapped in its colour
--   TC.Swatch(tex, tag)      tex = the swatch in the tag's colour, hidden
--                            without one; returns true when shown
--   TC.PaintChip(chip, tag)  chip backdrop tinted; false = no colour (the
--                            caller draws its own look)
--   TC.AddMenu(root, tag)    "Colour" sub-menu on a BNB.ContextMenu builder
--   TC.SWATCH                the swatch texture path
--------------------------------------------------------------------------------

local BNB = BigNoteBox
local L   = BNB.L

local TC = {}
BNB.TagColors = TC

TC.SWATCH = "Interface\\AddOns\\BigNoteBox\\Assets\\UI\\ui-color-swatch"
-- Dukul's swatch is 93 x 22: drawn at that ratio inside the colour menu, as
-- a square from its middle where it marks a tag in a row (autocompletes,
-- the tag window); the Colour entry itself is the drop
TC.DROP = "Interface\\AddOns\\BigNoteBox\\Assets\\UI\\ui-color-drop"
local SW_W, SW_H = 46, 11
local SQUARE = { 0.5 - 11 / 93, 0.5 + 11 / 93, 0, 1 }
TC.SQUARE = SQUARE

TC.LIST = {
    { key = "red",    r = 0.86, g = 0.24, b = 0.24, label = "TAGCOL_RED" },
    { key = "orange", r = 0.95, g = 0.55, b = 0.15, label = "TAGCOL_ORANGE" },
    { key = "yellow", r = 0.95, g = 0.82, b = 0.20, label = "TAGCOL_YELLOW" },
    { key = "lime",   r = 0.62, g = 0.86, b = 0.25, label = "TAGCOL_LIME" },
    { key = "green",  r = 0.25, g = 0.72, b = 0.35, label = "TAGCOL_GREEN" },
    { key = "teal",   r = 0.20, g = 0.72, b = 0.68, label = "TAGCOL_TEAL" },
    { key = "blue",   r = 0.25, g = 0.52, b = 0.92, label = "TAGCOL_BLUE" },
    { key = "indigo", r = 0.40, g = 0.40, b = 0.88, label = "TAGCOL_INDIGO" },
    { key = "purple", r = 0.65, g = 0.38, b = 0.88, label = "TAGCOL_PURPLE" },
    { key = "pink",   r = 0.92, g = 0.42, b = 0.70, label = "TAGCOL_PINK" },
    { key = "brown",  r = 0.65, g = 0.45, b = 0.28, label = "TAGCOL_BROWN" },
    { key = "grey",   r = 0.62, g = 0.62, b = 0.64, label = "TAGCOL_GREY" },
}
local BY_KEY = {}
for _, c in ipairs(TC.LIST) do BY_KEY[c.key] = c end

-- With the notes (BigNoteBoxNotesDB.tagColors), so the JSON full backup
-- carries them (Dukul, 2026-10-17). The first builds kept them in settings
-- (BigNoteBoxDB.tagColors): moved over once, a colour already set here wins.
local function Store(create)
    local ndb = BNB.NotesDB and BNB.NotesDB()
    if not ndb then return nil end
    local old = BigNoteBoxDB and BigNoteBoxDB.tagColors
    if type(old) == "table" then
        if next(old) then
            ndb.tagColors = ndb.tagColors or {}
            for k, v in pairs(old) do
                if ndb.tagColors[k] == nil then ndb.tagColors[k] = v end
            end
        end
        BigNoteBoxDB.tagColors = nil
    end
    if not ndb.tagColors and create then ndb.tagColors = {} end
    return ndb.tagColors
end

-- The JSON full backup (Features/NoteExport.lua): tag -> palette key / "none"
function TC.BackupMap()
    local s = Store(false)
    if not (s and next(s)) then return nil end
    local out = {}
    for k, v in pairs(s) do out[k] = v end
    return out
end

-- Colours from a backup for tags that have none here; returns how many
function TC.ImportMap(map)
    if type(map) ~= "table" then return 0 end
    local s, n = Store(true), 0
    if not s then return 0 end
    for k, v in pairs(map) do
        if type(k) == "string" and type(v) == "string" and s[k:lower()] == nil
           and (v == "none" or BY_KEY[v]) then
            s[k:lower()] = v
            n = n + 1
        end
    end
    if n > 0 then BNB.SendMessage("TagColorChanged") end
    return n
end

local function Norm(tag) return type(tag) == "string" and tag:lower() or nil end

local NONE = "none"   -- saved: no colour, also over a game colour

-- Lower-case name -> { r, g, b, label }, built on first use
local _game
local function GameColours()
    if _game then return _game end
    _game = {}
    local function Add(name, c, label)
        if type(name) == "string" and name ~= "" and type(c) == "table" and c.r then
            _game[name:lower()] = { r = c.r, g = c.g, b = c.b, label = label }
        end
    end
    local male, female = LOCALIZED_CLASS_NAMES_MALE or {}, LOCALIZED_CLASS_NAMES_FEMALE or {}
    for file, c in pairs(RAID_CLASS_COLORS or {}) do
        local label = male[file] or file
        Add(male[file], c, label)
        Add(female[file], c, label)
        Add(file, c, label)
    end
    local fc = PLAYER_FACTION_COLORS
    if type(fc) == "table" then
        Add(FACTION_HORDE, fc[0], FACTION_HORDE)
        Add("Horde", fc[0], FACTION_HORDE)
        Add(FACTION_ALLIANCE, fc[1], FACTION_ALLIANCE)
        Add("Alliance", fc[1], FACTION_ALLIANCE)
    end
    return _game
end

local function Raw(tag)
    local s, k = Store(false), Norm(tag)
    return s and k and s[k] or nil
end

function TC.Key(tag)
    local v = Raw(tag)
    return (v and BY_KEY[v]) and v or nil
end

function TC.Game(tag)
    local k = Norm(tag)
    local c = k and GameColours()[k]
    if c then return c.r, c.g, c.b, c.label end
end

function TC.Get(tag)
    local v = Raw(tag)
    if v == NONE then return nil end
    local c = BY_KEY[v or ""]
    if c then return c.r, c.g, c.b end
    local r, g, b = TC.Game(tag)
    return r, g, b
end

function TC.Set(tag, key)
    local k = Norm(tag); if not k then return end
    if key and key ~= NONE and not BY_KEY[key] then return end
    local s = Store(key ~= nil); if not s then return end
    if s[k] == key then return end
    s[k] = key
    BNB.SendMessage("TagColorChanged", tag)
end

function TC.Move(old, new)
    local s = Store(false)
    local ko, kn = Norm(old), Norm(new)
    if not (s and ko and kn) or ko == kn or not s[ko] then return end
    -- The tag renamed onto keeps its own colour when it has one
    if not s[kn] then s[kn] = s[ko] end
    s[ko] = nil
end

function TC.Drop(tag)
    local s, k = Store(false), Norm(tag)
    if s and k then s[k] = nil end
end

function TC.Text(tag, text)
    text = text or tag or ""
    local r, g, b = TC.Get(tag)
    if not r then return text end
    return string.format("|cff%02x%02x%02x%s|r", r * 255, g * 255, b * 255, text)
end

-- wide = the whole swatch at its own ratio (the tag window's list), else a
-- square from its middle (the autocompletes)
function TC.Swatch(tex, tag, wide)
    if not tex then return false end
    local r, g, b = TC.Get(tag)
    if not r then tex:Hide(); return false end
    tex:SetTexture(TC.SWATCH)
    if wide then tex:SetTexCoord(0, 1, 0, 1) else tex:SetTexCoord(unpack(SQUARE)) end
    tex:SetVertexColor(r, g, b)
    tex:Show()
    return true
end

function TC.PaintChip(chip, tag)
    local r, g, b = TC.Get(tag)
    if not r then return false end
    BNB.SetBackdrop(chip, r * 0.35, g * 0.35, b * 0.35, 0.95, r, g, b, 1)
    return true
end

-- The colour sub-menu: the game colour (a class or faction name), No
-- colour, then the palette, each with the swatch in its colour; the current
-- choice is named so (Dukul, 2026-10-17)
function TC.AddMenu(root, tag, opts)
    local raw = Raw(tag)
    local cur = TC.Key(tag)
    local r, g, b = TC.Get(tag)
    local gr, gg, gb, glabel = TC.Game(tag)
    local sub = root:CreateButton(L["TAGCOL_MENU"], nil, {
        -- The Colour entry: Dukul's drop in the tag's colour (2026-10-17)
        iconTex = TC.DROP, iconColor = r and { r, g, b } or { 0.35, 0.35, 0.35 },
        disabled = opts and opts.disabled,
        tip = L["TAGCOL_MENU"], tipSub = L["TAGCOL_MENU_TIP"],
    })
    local function Label(text, on)
        if on then return string.format(L["TAGCOL_CURRENT_FMT"], text) end
        return text
    end
    if gr then
        sub:CreateButton(Label(string.format(L["TAGCOL_GAME_FMT"], glabel or tag), raw == nil),
            function() TC.Set(tag, nil) end,
            { iconTex = TC.SWATCH, iconColor = { gr, gg, gb }, iconW = SW_W, iconH = SW_H,
              tip = string.format(L["TAGCOL_GAME_FMT"], glabel or tag), tipSub = L["TAGCOL_GAME_TIP"] })
        sub:CreateButton(Label(L["TAGCOL_NONE"], raw == NONE), function() TC.Set(tag, NONE) end,
            { iconTex = TC.SWATCH, iconColor = { 0.30, 0.30, 0.30 }, iconW = SW_W, iconH = SW_H })
    else
        sub:CreateButton(Label(L["TAGCOL_NONE"], cur == nil), function() TC.Set(tag, nil) end,
            { iconTex = TC.SWATCH, iconColor = { 0.30, 0.30, 0.30 }, iconW = SW_W, iconH = SW_H })
    end
    sub:CreateDivider()
    for _, c in ipairs(TC.LIST) do
        local key = c.key
        sub:CreateButton(Label(L[c.label], cur == key), function() TC.Set(tag, key) end,
            { iconTex = TC.SWATCH, iconColor = { c.r, c.g, c.b }, iconW = SW_W, iconH = SW_H })
    end
    return sub
end

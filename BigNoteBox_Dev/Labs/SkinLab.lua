-- BigNoteBox_Dev Labs/SkinLab.lua
-- Developer Tools > Skin Lab (/bnb skinlab, debug mode). ALL-403 S2 + S3.
-- Tunes the skin mode presets (UI/SkinSystem.lua BNB.SKIN_PRESETS): pick a
-- preset, set its seven colours by hex or the colour wheel, and try them at
-- any brightness / window opacity. While the lab is open its preset,
-- brightness and opacity are the skin colours of every open BNB window
-- (BNB.SetSkinOverride); closing the lab puts the saved ones back. Nothing
-- here changes a setting: Export hands back the SKIN_PRESETS lines of every
-- preset with edits, to paste into SkinSystem.lua.
-- The seven rows (the preset's fields, see the comment above SKIN_PRESETS):
--   Body    r, g, b            Border  br, bg_, bb
--   Lifted  lifted (strips)    Button  button (skin button fill)
--   Accent  accent             Header  header (headings)
--   Text    text (white text)
-- Accent and header are the colours at the default brightness (1.50); the
-- slider scales them as the game does. A row without an edit shows what the
-- preset draws today (worked out for accent, lifted...); its first edit
-- turns that into an exact colour. Reset drops the row's edit, Revert all of
-- the preset's. Edits are kept in BNB.LabDB().devSkinLab across reloads.
--
-- S3 (2026-10-08, Dukul's picks): the window is 980 x 700 (fits a 1080p
-- screen at UI scale 1). Right side, top to bottom:
--   * all-presets strip: one tile per preset (fill, border, accent dot; a
--     green corner = edited), click to show that preset
--   * the specimen, built with the real builders (skin frame + title strip,
--     tabs, top bar and toolbar icons, heading / labels / body / metadata
--     text, a skin button row and an icon button row frozen in Normal |
--     Hover | Pressed | Disabled, dropdown, checkbox, slider, real note list
--     rows with markers in a scroll frame, Show a toast, Open Settings for
--     the font cards). Skin mode only: the builders pick their look when
--     built, so with skin mode off the area says so.
--   * the grey-art checker: one white picture tinted the way the game tints
--     it (accent / icon button / marker) on every preset; < > picks the
--     picture, any texture path can be typed in.
-- Left side, under the colour rows: the contrast readout (WCAG ratios of
-- the drawn colours, opaque), hue-turn suggestions for the accent (click =
-- Accent, right-click = Header; they only suggest), and Freeze (Live /
-- Hover / Pressed / Disabled for the specimen's tabs, icons, dropdown,
-- checkbox, slider and list rows). New from this copies the shown preset
-- under a typed name; Rename / Delete work on those lab-made presets only
-- (shipped keys are saved in players' settings). Export writes a new
-- preset's SKIN_PRESETS line plus its SKIN_PRESET_ORDER entry and locale
-- lines as comments.
-- Dev tools only; nothing here is translated.

-- Queued for BigNoteBox's Core/DevTools.lua, which runs it once BigNoteBox
-- has loaded (this addon loads first, ARCH-04). The body is not indented.
BigNoteBoxDevLabs = BigNoteBoxDevLabs or {}
BigNoteBoxDevLabs[#BigNoteBoxDevLabs + 1] = function()

local BNB = BigNoteBox
if not BNB then return end

local K = BNB._LabKit
if not (K and BNB.SetSkinOverride and BNB.SKIN_PRESETS) then return end

local W, PAD     = 980, 16
local H          = 700            -- capped at the screen when built
local COL_W      = 380            -- the controls column
local COL_GAP    = 24
local ROW_H      = 28
local STRIP_H    = 24             -- all-presets strip
local ART_H      = 92             -- grey-art checker
local ASSETS     = "Interface\\AddOns\\BigNoteBox\\Assets\\"
local WHITE      = "Interface\\Buttons\\WHITE8x8"

-- ── Rows ────────────────────────────────────────────────────────────────────
-- field = the preset field an edit writes; body / border are split into the
-- three plain fields, the rest are { r, g, b } tables
local ROWS = {
    { key = "body",   label = "Body" },
    { key = "lifted", label = "Lifted" },
    { key = "button", label = "Button" },
    { key = "border", label = "Border" },
    { key = "accent", label = "Accent" },
    { key = "header", label = "Header" },
    { key = "text",   label = "Text" },
}

-- ── Saved state ──────────────────────────────────────────────────────────────
-- s.edits[presetKey][rowKey] = { r, g, b }; s.key = preset shown;
-- s.brightness / s.alpha = the lab's sliders (nil = the saved settings);
-- s.custom[key] = { label, from, preset } = a lab-made preset (New from this);
-- s.freeze, s.freeHue, s.art, s.artPath, s.artMode = the S3 controls
local function Store()
    local db = BNB.LabDB()
    db.devSkinLab = db.devSkinLab or {}
    local s = db.devSkinLab
    s.edits = s.edits or {}
    s.custom = s.custom or {}
    return s
end

local function Def() return BNB.DEFAULTS.skinBrightness or 1.5 end

local function IsCustom(key)
    return (key and not BNB.SKIN_PRESETS[key] and Store().custom[key] ~= nil) and true or false
end
local function Exists(key)
    return (key and (BNB.SKIN_PRESETS[key] or Store().custom[key])) and true or false
end

-- The preset a key starts from: shipped, or the lab-made copy
local function Base(key)
    if BNB.SKIN_PRESETS[key] then return BNB.SKIN_PRESETS[key] end
    local c = Store().custom[key]
    return (c and c.preset) or BNB.SKIN_PRESETS.obsidian
end

local function Copy(src)
    local p = {}
    for k, v in pairs(src) do p[k] = type(v) == "table" and { v[1], v[2], v[3] } or v end
    return p
end

-- The preset as the lab shows it: the shipped (or lab-made) one with the
-- edits on top
local function Build(key)
    local p = Copy(Base(key))
    local e = Store().edits[key]
    if e then
        if e.body   then p.r, p.g, p.b = e.body[1], e.body[2], e.body[3] end
        if e.border then p.br, p.bg_, p.bb = e.border[1], e.border[2], e.border[3] end
        for _, f in ipairs({ "lifted", "button", "accent", "header", "text" }) do
            if e[f] then p[f] = { e[f][1], e[f][2], e[f][3] } end
        end
    end
    return p
end

-- Presets in dropdown / strip order: shipped first, then the lab-made ones
local function Order()
    local out = {}
    for _, key in ipairs(BNB.SKIN_PRESET_ORDER) do out[#out + 1] = key end
    local extra = {}
    for key in pairs(Store().custom) do
        if not BNB.SKIN_PRESETS[key] then extra[#extra + 1] = key end
    end
    table.sort(extra)
    for _, key in ipairs(extra) do out[#out + 1] = key end
    return out
end

local function Label(key)
    if IsCustom(key) then return (Store().custom[key].label or key) .. " (new)" end
    return BNB.SkinPresetLabel(key)
end

local _ovr   -- the override table handed to BNB.SetSkinOverride while open

-- Run a colour getter as if preset p were the active one (its noBright and
-- brightness rule apply), without touching what is on screen
local function WithPreset(p, fn, ...)
    if not _ovr then return fn(p, ...) end
    local keep = _ovr.preset
    _ovr.preset = p
    local a, b, c = fn(p, ...)
    _ovr.preset = keep
    return a, b, c
end

-- A row's colour on preset p, before brightness (accent / header: at the
-- default brightness). Works out what the game draws when there is no
-- exact colour, so the first edit starts from what is on screen.
local function RowColour(p, rowKey)
    if rowKey == "body"   then return p.r, p.g, p.b end
    if rowKey == "border" then return p.br, p.bg_, p.bb end
    if rowKey == "lifted" then return BNB.SkinLiftedOf(p) end
    if rowKey == "button" then return BNB.SkinButtonOf(p) end
    if rowKey == "text"   then return BNB.SkinTextOf(p) end
    -- accent / header read the brightness: ask at the default
    local keep = _ovr and _ovr.brightness
    if _ovr then _ovr.brightness = Def() end
    local r, g, b
    if rowKey == "accent" then r, g, b = WithPreset(p, BNB.SkinAccentOf)
    else r, g, b = WithPreset(p, BNB.SkinHeaderOf) end
    if _ovr then _ovr.brightness = keep end
    return r, g, b
end

-- Where a row's colour comes from: "edited", "exact" (shipped / copied) or
-- "worked out"
local function RowSource(key, rowKey)
    local e = Store().edits[key]
    if e and e[rowKey] then return "edited" end
    if rowKey == "body" or rowKey == "border" then return "exact" end
    return Base(key)[rowKey] ~= nil and "exact" or "worked out"
end

local function Hex(r, g, b)
    local function c(v) return math.floor(math.max(0, math.min(1, v)) * 255 + 0.5) end
    return string.format("%02X%02X%02X", c(r), c(g), c(b))
end
local function ParseHex(t)
    t = (t or ""):gsub("^%s*#?", ""):gsub("%s+$", "")
    if not t:match("^%x%x%x%x%x%x$") then return nil end
    return tonumber(t:sub(1, 2), 16) / 255, tonumber(t:sub(3, 4), 16) / 255, tonumber(t:sub(5, 6), 16) / 255
end

-- HSV (SkinSystem's own are file locals)
local function RGBtoHSV(r, g, b)
    local mx, mn = math.max(r, g, b), math.min(r, g, b)
    local d = mx - mn
    local h = 0
    if d > 0 then
        if mx == r then h = ((g - b) / d) % 6
        elseif mx == g then h = (b - r) / d + 2
        else h = (r - g) / d + 4 end
        h = h / 6
    end
    return h, (mx > 0) and d / mx or 0, mx
end
local function HSVtoRGB(h, s, v)
    h = h % 1
    local i = math.floor(h * 6) % 6
    local f = h * 6 - math.floor(h * 6)
    local p, q, t = v * (1 - s), v * (1 - f * s), v * (1 - (1 - f) * s)
    if i == 0 then return v, t, p elseif i == 1 then return q, v, p
    elseif i == 2 then return p, v, t elseif i == 3 then return p, q, v
    elseif i == 4 then return t, p, v end
    return v, p, q
end

-- ── Export ───────────────────────────────────────────────────────────────────
local function N(v) return string.format("%.3f", v) end
local function C3(c) return string.format("{ %s, %s, %s }", N(c[1]), N(c[2]), N(c[3])) end

local function PresetLine(key)
    local p = Build(key)
    local parts = {
        string.format("r=%s, g=%s, b=%s, lift=%s", N(p.r), N(p.g), N(p.b), string.format("%.2f", p.lift or 0)),
        string.format("br=%s, bg_=%s, bb=%s", string.format("%.2f", p.br), string.format("%.2f", p.bg_), string.format("%.2f", p.bb)),
    }
    for _, f in ipairs({ "lifted", "button", "accent", "header" }) do
        if p[f] then parts[#parts + 1] = f .. "=" .. C3(p[f]) end
    end
    local t = p.text
    if type(t) == "number" then parts[#parts + 1] = "text=" .. string.format("%.2f", t)
    elseif type(t) == "table" then
        if math.abs(t[1] - t[2]) < 0.002 and math.abs(t[1] - t[3]) < 0.002 then
            parts[#parts + 1] = "text=" .. string.format("%.2f", t[1])
        else
            parts[#parts + 1] = "text=" .. C3(t)
        end
    end
    if p.noBright then parts[#parts + 1] = "noBright=true" end
    return string.format("    %-10s = { %s },", key, table.concat(parts, ", "))
end

local function ExportText()
    local out = { "-- Skin Lab export (UI/SkinSystem.lua BNB.SKIN_PRESETS), " .. date("%Y-%m-%d %H:%M") }
    local edits = Store().edits
    local any = false
    for _, key in ipairs(Order()) do
        if IsCustom(key) then
            local c = Store().custom[key]
            local name = (c.label or key):gsub('"', "'")
            local up = key:upper()
            out[#out + 1] = string.format('-- New preset "%s" (from %s): add "%s" to BNB.SKIN_PRESET_ORDER, and to Locales/enUS.lua:', name, c.from or "?", key)
            out[#out + 1] = string.format('--   L["CFG_SKIN_PRESET_%s"] = "%s"', up, name)
            out[#out + 1] = string.format('--   L["SW_PRESET_%s"] = "%s"', up, name)
            out[#out + 1] = PresetLine(key)
            any = true
        elseif edits[key] and next(edits[key]) then
            out[#out + 1] = PresetLine(key)
            any = true
        end
    end
    if not any then out[#out + 1] = "-- (no preset has edits)" end
    return table.concat(out, "\n")
end

-- ── Contrast ─────────────────────────────────────────────────────────────────
-- WCAG 2 contrast of the colours as drawn (the window taken as opaque).
-- need = the ratio that reads well: 4.5 for text, 3 for icons and edges
local function Lum(r, g, b)
    local function c(v) return v <= 0.03928 and v / 12.92 or ((v + 0.055) / 1.055) ^ 2.4 end
    return 0.2126 * c(r) + 0.7152 * c(g) + 0.0722 * c(b)
end
local function Ratio(r1, g1, b1, r2, g2, b2)
    local a, b = Lum(r1, g1, b1), Lum(r2, g2, b2)
    if a < b then a, b = b, a end
    return (a + 0.05) / (b + 0.05)
end
local function Body(p) return BNB.SkinColourOf(p) end
local function Strip(p) return BNB.SkinColourOf(p, true) end
local PAIRS = {
    { "Text / body",    BNB.SkinTextOf,   Body,             4.5 },
    { "Heading / body", BNB.SkinHeaderOf, Body,             4.5 },
    { "Accent / strip", BNB.SkinAccentOf, Strip,            3 },
    { "Text / button",  BNB.SkinTextOf,   BNB.SkinButtonOf, 4.5 },
    { "Border / body",  BNB.SkinBorderOf, Body,             3 },
}

-- ── Hue suggestions ─────────────────────────────────────────────────────────
-- Turns of the preset's own hue (the border's; the accent's when the border
-- has next to no colour), at the accent's saturation and value. nil = the
-- Free turn slider
local TURNS = {
    { -30, "Analogous -30" }, { 30, "Analogous +30" },
    { 150, "Split complement +150" }, { 210, "Split complement +210" },
    { 120, "Triadic +120" }, { 240, "Triadic +240" },
    { 180, "Complement +180" }, { nil, "Free turn (slider below)" },
}

local function Suggestion(p, turn)
    local ar, ag, ab = RowColour(p, "accent")
    local ah, as, av = RGBtoHSV(ar, ag, ab)
    local bh, bs = RGBtoHSV(p.br, p.bg_, p.bb)
    local base = (bs >= 0.15) and bh or ah
    return HSVtoRGB(base + turn / 360, as, av)
end

-- ── Grey-art checker ─────────────────────────────────────────────────────────
-- mode = how the game tints the picture: "accent" (top bar, toolbar),
-- "plate" (top bar hover plate, accent x 0.6), "icon" (icon button symbols,
-- border x 2.2 per channel), "marker" (note icon markers, border x 2.2 with
-- one factor capped at the brightest channel). bg = what it sits on
local ART = {
    { "Top bar: settings",     "Topbar\\tp-settings",    "accent", "lifted" },
    { "Top bar: trash",        "Topbar\\tp-trash",       "accent", "lifted" },
    { "Top bar: alarms",       "Topbar\\tp-alarms",      "accent", "lifted" },
    { "Top bar: hover plate",  "UI\\ui-hover-64",        "plate",  "lifted" },
    { "Toolbar: undo",         "Toolbar\\tb-undo",       "accent", "body" },
    { "Toolbar: share",        "Toolbar\\tb-share",      "accent", "body" },
    { "Toolbar: hover",        "UI\\ui-hover-64",        "accent", "body" },
    { "Note list: tag tree",   "UI\\ui-treeview",        "accent", "body" },
    { "Note list: favourites", "UI\\ui-favorite",        "accent", "body" },
    { "Note list: tasks",      "UI\\ui-tasks",           "accent", "body" },
    { "Note list: reset",      "UI\\ui-reset",           "accent", "body" },
    { "Note list: collapse",   "UI\\ui-arrow-left",      "accent", "body" },
    { "Marker: alarm",         "Overlay\\ov-alarm",      "marker", "body" },
    { "Marker: favourite",     "Overlay\\ov-favorite",   "marker", "body" },
    { "Marker: situation",     "Overlay\\ov-situation",  "marker", "body" },
    { "Marker: location",      "Overlay\\ov-location",   "marker", "body" },
    { "Icon button: settings", "Buttons\\Symbols\\bt-settings-normal", "icon", "button" },
    { "Icon button: close",    "Buttons\\Symbols\\bt-close-normal",    "icon", "button" },
}
local MODES = { "accent", "plate", "icon", "marker" }

local function ArtTint(p, mode)
    if mode == "accent" or mode == "plate" then
        local r, g, b = BNB.SkinAccentOf(p)
        local k = (mode == "plate") and 0.6 or 1
        return r * k, g * k, b * k
    end
    local br, bg_, bb = BNB.SkinBorderOf(p)
    if mode == "marker" then
        local m = math.min(2.2, 1 / math.max(br, bg_, bb, 0.001))
        return br * m, bg_ * m, bb * m
    end
    return math.min(1, br * 2.2), math.min(1, bg_ * 2.2), math.min(1, bb * 2.2)
end

-- The picture shown: a typed path, or an ART entry
local function CurArt()
    local s = Store()
    if s.artPath and s.artPath ~= "" then
        return "Typed: " .. s.artPath, s.artPath, s.artMode or "accent", "body"
    end
    local e = ART[s.art or 1] or ART[1]
    return e[1], ASSETS .. e[2], s.artMode or e[3], e[4]
end

-- ── Window ───────────────────────────────────────────────────────────────────
local _f
local _rows = {}
local _presetDD, _presetEntries, _brtSl, _alphaSl, _skinNote
local _newBtn, _renameBtn, _deleteBtn, _nameRow, _nameBox, _nameMode
local _delArmed
local _tiles = {}        -- all-presets strip
local _contrast = {}     -- readout lines
local _hue = {}          -- suggestion swatches
local _art = {}          -- grey-art checker pieces
local _sp                -- specimen pieces (nil while skin mode is off)

local function SavedKey()
    local k = BigNoteBoxDB and BigNoteBoxDB.skinPreset
    return (k and BNB.SKIN_PRESETS[k]) and k or "obsidian"
end
local function CurKey()
    local k = Store().key
    if Exists(k) then return k end
    return SavedKey()
end

local function SavedBrightness()
    return (BigNoteBoxDB and BigNoteBoxDB.skinBrightness) or Def()
end
local function SavedAlpha()
    return (BigNoteBoxDB and BigNoteBoxDB.skinBgAlpha) or 0.97
end

local Refresh   -- defined below

-- Hand the lab's preset to every skin colour and re-apply the open windows
local function ApplyOverride()
    local s = Store()
    _ovr = _ovr or {}
    _ovr.key        = CurKey()
    _ovr.preset     = Build(_ovr.key)
    _ovr.brightness = s.brightness or SavedBrightness()
    _ovr.alpha      = s.alpha or SavedAlpha()
    BNB.SetSkinOverride(_ovr)
    if BigNoteBoxDB and BigNoteBoxDB.skinMode and BNB.ApplyMainWindowSkin then
        BNB.ApplyMainWindowSkin()
    end
end

local function SetEdit(rowKey, r, g, b)
    local edits = Store().edits
    local key = CurKey()
    edits[key] = edits[key] or {}
    edits[key][rowKey] = { r, g, b }
    ApplyOverride(); Refresh()
end

local function ClearEdit(rowKey)
    local edits = Store().edits
    local key = CurKey()
    if edits[key] then
        edits[key][rowKey] = nil
        if not next(edits[key]) then edits[key] = nil end
    end
    ApplyOverride(); Refresh()
end

local function ShowPreset(key)
    Store().key = key
    _delArmed = nil
    ApplyOverride(); Refresh()
end

-- A small tooltip on any frame
local function Tip(frame, fn)
    frame:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        fn(self)
        GameTooltip:Show()
    end)
    frame:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

-- A flat colour tile: fill + 1 px edge (the lab's own, not a skin piece)
local function Tile(parent, w, h)
    local t = CreateFrame("Button", nil, parent, "BackdropTemplate")
    t:SetSize(w, h)
    t:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
    t:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
    return t
end

-- ── Specimen ─────────────────────────────────────────────────────────────────
-- Fake notes for the real list rows (never saved; ids no note can have)
-- The specimen's note list (Dukul, 2026-10-08): the top note carries every
-- marker, the bottom one nothing, the ones between are random (title colour,
-- icon, icon frame or LSM edge border, markers); Shuffle draws new ones
local RANDOM_ROWS = 6
local RANDOM_TITLES = { "Raid night plan", "Gold farming route", "Mount collection",
    "Profession cooldowns", "Guild bank list", "Transmog wishlist", "Quest chain notes",
    "Rare spawn timers", "Achievement hunt", "Alt checklist", "Dungeon tactics", "Fishing spots" }

local function Pick(t) if t and #t > 0 then return t[math.random(#t)] end end

-- A known character key with a class, for the class marker (current first)
local function CharScope(random)
    local kc = BigNoteBoxDB and BigNoteBoxDB.knownChars or {}
    local keys = {}
    for k, v in pairs(kc) do if type(v) == "table" and v.class then keys[#keys + 1] = k end end
    local k = (random and Pick(keys)) or BNB.currentChar or keys[1]
    return k and ("char:" .. k) or nil
end

local function RandomNote(i)
    local n = { id = "skinlab:r" .. i, title = Pick(RANDOM_TITLES), body = "Random look: Shuffle for another.",
        icon = Pick(BNB.ICON_MANIFEST) or "Interface\\Icons\\INV_Misc_Note_01" }
    if math.random() < 0.7 then
        n.titleColor = { r = 0.3 + math.random() * 0.7, g = 0.3 + math.random() * 0.7, b = 0.3 + math.random() * 0.7 }
    end
    local look = math.random(3)
    if look == 1 then
        local e = Pick(BNB.IconFrames and BNB.IconFrames.LIST)
        n.iconFrame = e and e.key
    elseif look == 2 then
        local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
        local list = LSM and LSM:List("border")
        local b = Pick(list)
        if b and b ~= "None" then n.borderOverride = b; n.borderScale = 60 + math.random(80) end
    end
    if math.random() < 0.5 then n.favorited = true end
    if math.random() < 0.4 then
        local fired = math.random() < 0.3
        n.alarm = { time = time() + (fired and -60 or 86400), fired = fired or nil }
    end
    if math.random() < 0.4 then n.situations = { "zone:Orgrimmar" } end
    if math.random() < 0.3 then n.waypoints = { { mapID = 85, x = 50, y = 50, on = true } } end
    if math.random() < 0.4 then n.scope = CharScope(true) end
    return n
end

local function FakeNotes()
    local list = {
        { id = "skinlab:1", title = "Selected note", body = "The open note, with every marker on its icon.",
          icon = "Interface\\Icons\\INV_Misc_Note_01", favorited = true, alarm = { time = time() + 86400 },
          situations = { "zone:Orgrimmar" }, waypoints = { { mapID = 85, x = 50, y = 50, on = true } },
          scope = CharScope(false) },
    }
    for i = 1, RANDOM_ROWS do list[#list + 1] = RandomNote(i) end
    list[#list + 1] = { id = "skinlab:plain", title = "Plain note", body = "Nothing on the icon.",
        icon = "Interface\\Icons\\INV_Scroll_03" }
    return list
end

-- Fill the specimen's list rows with a fresh set of fake notes
local function FillFakeRows(sp)
    if not (sp and sp.rows and BNB.PopulateListEntry) then return end
    for i, note in ipairs(FakeNotes()) do
        local row = sp.rows[i]
        if row then
            pcall(BNB.PopulateListEntry, row, note, i == 1, false)
            -- No alarm glow for a note that does not exist
            if BNB.Alarm and BNB.Alarm.UnregisterGlowTarget and row._iconGlowFrame then
                BNB.Alarm.UnregisterGlowTarget(note.id, row._iconGlowFrame)
                row._iconGlowFrame._bnbGlowNoteID = nil
            end
        end
    end
end

-- The formatting toolbar's icon button (UI/WysiwygBar.lua WyBtn, skin look)
local function ToolbarIcon(parent, file, tip)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(20, 20)
    local tx = btn:CreateTexture(nil, "ARTWORK")
    tx:SetAllPoints()
    tx:SetTexture(ASSETS .. "Toolbar\\" .. file)
    local hi = btn:CreateTexture(nil, "HIGHLIGHT")
    hi:SetAllPoints(tx)
    hi:SetTexture(ASSETS .. "UI\\ui-hover-64")
    BNB.RegisterSkinAccentTex(tx)
    BNB.RegisterSkinAccentTex(hi)
    btn._tx = tx
    function btn:Press(on)
        tx:ClearAllPoints()
        if on then
            tx:SetPoint("TOPLEFT", btn, "TOPLEFT", 1, -1)
            tx:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 1, -1)
        else
            tx:SetAllPoints()
        end
    end
    btn:SetScript("OnMouseDown", function(self) if self:IsEnabled() then self:Press(true) end end)
    btn:SetScript("OnMouseUp", function(self) self:Press(false) end)
    Tip(btn, function() GameTooltip:AddLine(tip, 1, 1, 1) end)
    return btn
end

-- The main window's top bar icon (UI/MainWindow.lua, skin look: white icon
-- in the accent, ui-hover-64 plate under it at 0.6)
local function TopBarIcon(parent, file, tip)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(20, 20)
    local plate = btn:CreateTexture(nil, "BACKGROUND")
    plate:SetSize(24, 24)
    plate:SetPoint("CENTER")
    plate:SetTexture(ASSETS .. "UI\\ui-hover-64")
    BNB.RegisterSkinAccentTex(plate, 0.6)
    plate:Hide()
    local tx = btn:CreateTexture(nil, "ARTWORK")
    tx:SetPoint("TOPLEFT", btn, "TOPLEFT", 2, -2)
    tx:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -2, 2)
    tx:SetTexture(ASSETS .. "Topbar\\" .. file)
    BNB.RegisterSkinAccentTex(tx)
    btn._tx, btn._plate = tx, plate
    btn:SetScript("OnEnter", function(self)
        plate:Show()
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(tip, 1, 1, 1)
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function(self)
        if not self._frozen then plate:Hide() end
        GameTooltip:Hide()
    end)
    return btn
end

local function ShowTestToast()
    if not (BNB.Toast and BNB.Toast.Show) then return end
    if not BNB.ToastsEnabled() then
        BNB:Print("Skin Lab: the Toasts module is off (Settings > Modules > Toasts).")
        return
    end
    BNB.Toast.Show({ key = "skinlab", source = "test", force = true,
        title = "Skin Lab", text = "A toast in your toast style" })
end

local STATES = { "Normal", "Hover", "Pressed", "Disabled" }

local function BuildSpecimen(parent, x, y, w, h)
    local sp = { tbIcons = {}, tpIcons = {}, fixedBtns = {}, fixedIcons = {}, rows = {} }
    local TITLE_H = BNB.TOOL_SKIN_TITLE_H or 24
    local fr = BNB.CreateSkinFrame(parent, false)
    fr:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    fr:SetSize(w, h)
    fr:SetFrameLevel(parent:GetFrameLevel() + 2)
    sp.frame = fr
    local ix, iw = 12, w - 24

    -- Title strip + close X
    local title = BNB.CreateSkinStrip(fr, true)
    title:SetPoint("TOPLEFT", fr, "TOPLEFT", 0, 0)
    title:SetPoint("TOPRIGHT", fr, "TOPRIGHT", 0, 0)
    title:SetHeight(TITLE_H)
    local tl = title:CreateFontString(nil, "OVERLAY", "BNBFontNormal")
    tl:SetPoint("LEFT", title, "LEFT", 8, 0)
    tl:SetPoint("RIGHT", title, "RIGHT", -38, 0)
    tl:SetJustifyH("CENTER")
    BNB.SetHeaderColor(tl)
    tl:SetText("Window title")
    BNB.CreateSkinCloseButton(title, nil):SetPoint("RIGHT", title, "RIGHT", -3, 0)
    local yy = -(TITLE_H + 10)

    -- Tabs
    local tabs = BNB.CreateSkinTabs(fr, { "General", "Appearance", "Advanced" })
    tabs.frame:SetPoint("TOPLEFT", fr, "TOPLEFT", ix, yy)
    tabs.frame:SetPoint("TOPRIGHT", fr, "TOPRIGHT", -ix, yy)
    sp.tabs = tabs
    yy = yy - 24 - 10

    -- Toolbar strip: formatting icons left, top bar icons right
    local strip = BNB.CreateSkinStrip(fr, true)
    strip:SetPoint("TOPLEFT", fr, "TOPLEFT", 1, yy)
    strip:SetPoint("TOPRIGHT", fr, "TOPRIGHT", -1, yy)
    strip:SetHeight(30)
    for i, e in ipairs({ { "tb-undo.tga", "Undo" }, { "tb-redo.tga", "Redo" }, { "tb-timestamp.tga", "Timestamp" },
                         { "tb-bulletlist.tga", "Bullet list" }, { "tb-share.tga", "Share" } }) do
        local b = ToolbarIcon(strip, e[1], "Formatting toolbar: " .. e[2])
        b:SetPoint("LEFT", strip, "LEFT", ix - 1 + (i - 1) * 26, 0)
        sp.tbIcons[i] = b
    end
    local tps = { { "tp-notehistory.tga", "Note history" }, { "tp-tagmanager.tga", "Tag manager" },
                  { "tp-alarms.tga", "Alarms" }, { "tp-trash.tga", "Trash" }, { "tp-settings.tga", "Settings" } }
    for i, e in ipairs(tps) do
        local b = TopBarIcon(strip, e[1], "Top bar: " .. e[2])
        b:SetPoint("RIGHT", strip, "RIGHT", -(ix - 1) - (#tps - i) * 26, 0)
        sp.tpIcons[i] = b
    end
    yy = yy - 30 - 12

    -- Heading + rule, section header, body, small label, metadata
    local head = fr:CreateFontString(nil, "OVERLAY", "BNBFontNormalLarge")
    head:SetPoint("TOPLEFT", fr, "TOPLEFT", ix, yy)
    head:SetText("Section heading")
    local rule = BNB.CreateNoteRule(fr)
    rule:SetPoint("TOPLEFT", fr, "TOPLEFT", ix, yy - 22)
    rule:SetPoint("TOPRIGHT", fr, "TOPRIGHT", -ix, yy - 22)
    yy = yy - 32
    local sh = BNB.CreateSectionHeader(fr, "Settings section header", 0, iw)
    sh:ClearAllPoints(); sh:SetPoint("TOPLEFT", fr, "TOPLEFT", ix, yy)
    local body = fr:CreateFontString(nil, "OVERLAY", "BNBFontHighlight")
    body:SetPoint("TOPLEFT", fr, "TOPLEFT", ix, yy - 18)
    body:SetWidth(iw); body:SetJustifyH("LEFT")
    body:SetText("Body text in the preset's white: labels, checkbox labels, setting names and note text. Only headings and important text take the accent.")
    local small = BNB.CreateSmallLabel(fr, "Small grey label (hints)", 0, 200)
    small:ClearAllPoints(); small:SetPoint("TOPLEFT", fr, "TOPLEFT", ix, yy - 52)
    local meta = fr:CreateFontString(nil, "OVERLAY", "BNBFontHighlightSmall")
    meta:SetPoint("TOPLEFT", fr, "TOPLEFT", ix + 210, yy - 52)
    meta:SetText("Metadata strip: edited 5 min ago, 124 words")
    BNB.RegisterSkinLabel(meta, 0.90)
    yy = yy - 74

    -- Fixed state rows: skin buttons, icon buttons (mouse off, they never change)
    local LBL_W, COLW = 78, 104
    local function RowLabel(text, ly)
        local fs = fr:CreateFontString(nil, "OVERLAY", "BNBFontHighlightSmall")
        fs:SetPoint("TOPLEFT", fr, "TOPLEFT", ix, ly - 5)
        fs:SetText(text)
        BNB.SetTextWhite(fs, 0.7)
    end
    RowLabel("Buttons", yy)
    for i, s in ipairs(STATES) do
        local b = BNB.CreateSkinButton(nil, fr, s, 96, 22)
        b:SetPoint("TOPLEFT", fr, "TOPLEFT", ix + LBL_W + (i - 1) * COLW, yy)
        b:EnableMouse(false)
        sp.fixedBtns[i] = b
    end
    yy = yy - 30
    RowLabel("Icon buttons", yy)
    for i = 1, #STATES do
        local group = {}
        for j, sym in ipairs({ "settings", "close", "plus" }) do
            local ib = BNB.CreateIconButton(fr, 22, sym, { skin = true })
            ib:SetPoint("TOPLEFT", fr, "TOPLEFT", ix + LBL_W + (i - 1) * COLW + 11 + (j - 1) * 26, yy)
            ib:EnableMouse(false)
            group[j] = ib
        end
        sp.fixedIcons[i] = group
    end
    yy = yy - 34

    -- Left: dropdown, checkbox, slider, two working buttons
    local LW = 230
    local dd = BNB.CreateValueDropdown(fr, {
        { label = "Dropdown choice", value = 1 }, { label = "Another choice", value = 2 },
        { label = "A third choice", value = 3 } }, 1, nil, LW, 24)
    dd:SetPoint("TOPLEFT", fr, "TOPLEFT", ix, yy)
    sp.dd = dd._dd
    local cb = CreateFrame("CheckButton", nil, fr, "UICheckButtonTemplate")
    cb:SetSize(24, 24)
    cb:SetPoint("TOPLEFT", fr, "TOPLEFT", ix - 2, yy - 32)
    if cb.Text then cb.Text:SetText("Checkbox label") end
    BNB.LabelHit(cb)
    BNB.CheckTip(cb, "A checkbox with its label, as on the Settings pages")
    cb:SetChecked(true)
    sp.cb = cb
    local sl = BNB.CreateStackedSlider(fr, LW, { label = "Slider", min = 0, max = 100, step = 1,
        value = 40, default = 50, onChange = function() end })
    sl:SetPoint("TOPLEFT", fr, "TOPLEFT", ix, yy - 64)
    sp.sl = sl
    local toastBtn = BNB.CreateSkinButton(nil, fr, "Show a toast", 112, 22)
    toastBtn:SetPoint("TOPLEFT", fr, "TOPLEFT", ix, yy - 64 - BNB.STACKED_SLIDER_H - 10)
    toastBtn:SetScript("OnClick", ShowTestToast)
    local setBtn = BNB.CreateSkinButton(nil, fr, "Open Settings", 112, 22)
    setBtn:SetPoint("LEFT", toastBtn, "RIGHT", 6, 0)
    setBtn:SetScript("OnClick", function()
        if BNB.OpenSettingsPage then BNB.OpenSettingsPage("appearance") end
    end)
    Tip(setBtn, function()
        GameTooltip:AddLine("Settings > Appearance", 1, 1, 1)
        GameTooltip:AddLine("The font cards and every other window follow the lab while it is open.", 0.8, 0.8, 0.8, true)
    end)

    -- Right: real note list rows in a scroll frame (fake notes, mouse off)
    local lx = ix + LW + 20
    local lw = iw - LW - 20 - 22   -- room for the scrollbar
    local lh = math.max(60, h + yy - 12)
    local sf = BNB.CreateScrollFrame(nil, fr)
    sf:SetPoint("TOPLEFT", fr, "TOPLEFT", lx, yy)
    sf:SetSize(lw, lh)
    local child = CreateFrame("Frame", nil, sf)
    child:SetWidth(lw)
    sf:SetScrollChild(child)
    local ry = 0
    if BNB._createListEntry and BNB.PopulateListEntry then
        for i = 1, RANDOM_ROWS + 2 do
            local row = BNB._createListEntry(child)
            row:SetPoint("TOPLEFT", child, "TOPLEFT", 0, -ry)
            row:SetWidth(lw)
            row:EnableMouse(false)
            sp.rows[i] = row
        end
        FillFakeRows(sp)
        for _, row in ipairs(sp.rows) do ry = ry + math.max(26, row:GetHeight()) end
    end
    child:SetHeight(math.max(1, ry))
    local shufBtn = BNB.CreateSkinButton(nil, fr, "Shuffle notes", 112, 22)
    shufBtn:SetPoint("TOPLEFT", toastBtn, "BOTTOMLEFT", 0, -6)
    shufBtn:SetScript("OnClick", function() FillFakeRows(sp) end)
    Tip(shufBtn, function()
        GameTooltip:AddLine("Shuffle notes", 1, 1, 1)
        GameTooltip:AddLine("New random title colours, icons, frames, borders and markers for the notes between the top and bottom one.", 0.8, 0.8, 0.8, true)
    end)
    return sp
end

-- Hover / pressed / disabled of the fixed rows; re-applied after every
-- preset change (a skin button's re-skin resets its pressed colour)
local function ApplyFixed()
    if not _sp then return end
    for i, b in ipairs(_sp.fixedBtns) do
        if i == 2 then b:LockHighlight() end
        if i == 3 then
            local fn = b:GetScript("OnMouseDown")
            if fn then fn(b) end
        end
        if i == 4 then b:SetEnabled(false) end
    end
    for i, group in ipairs(_sp.fixedIcons) do
        for _, ib in ipairs(group) do
            ib._over = (i == 2) or nil
            ib._down = (i == 3) or nil
            if i == 4 then ib:SetEnabled(false) end
            ib:RefreshLook()
        end
    end
end

-- Freeze: Live / Hover / Pressed / Disabled for the rest of the specimen.
-- Scripts that run on a change of state (dropdown enter / leave, press /
-- release) only on a change; the rest is re-applied every time.
local _lastFreeze = "live"
local function ApplyFreeze()
    if not _sp then return end
    local st = Store().freeze or "live"
    local hover, press, off = st == "hover", st == "pressed", st == "disabled"
    -- ExecuteFrameScript runs the hooks too (SkinDropdown's look is hooked on)
    local function Run(f, script) if f then pcall(ExecuteFrameScript, f, script) end end

    -- Tabs: the unselected ones as hovered
    local sel = _sp.tabs._selected or 1
    for i, b in ipairs(_sp.tabs.buttons) do
        if i ~= sel then b:SetAlpha(hover and 0.85 or 0.55) end
    end
    -- Toolbar and top bar icons
    for _, b in ipairs(_sp.tbIcons) do
        if hover then b:LockHighlight() else b:UnlockHighlight() end
        b:Press(press)
        b:SetEnabled(not off)
        b:SetAlpha(off and 0.30 or 1)
        b._tx:SetDesaturated(off)
    end
    for _, b in ipairs(_sp.tpIcons) do
        b._frozen = hover or nil
        b._plate:SetShown(hover)
        b:SetEnabled(not off)
        b:SetAlpha(off and 0.4 or 1)
        b._tx:SetDesaturated(off)
    end
    -- Dropdown: hover and disabled only (a press opens its menu; the fixed
    -- button row shows the pressed box, which is the same skin button)
    local dd = _sp.dd
    if st ~= _lastFreeze then
        if _lastFreeze == "hover" then Run(dd, "OnLeave") end
        dd:SetEnabled(not off)
        if hover then Run(dd, "OnEnter") end
        _lastFreeze = st
    end
    -- Checkbox, slider, list rows
    local cb = _sp.cb
    cb:SetEnabled(not off)
    if not off then cb:SetButtonState(press and "PUSHED" or "NORMAL", press) end
    if hover then cb:LockHighlight() else cb:UnlockHighlight() end
    _sp.sl:SetEnabled(not off)
    for i, row in ipairs(_sp.rows) do
        if i > 1 and hover then row:LockHighlight() else row:UnlockHighlight() end
    end
end

-- ── Refresh ──────────────────────────────────────────────────────────────────
local function RefreshStrip()
    local order = Order()
    local cur = CurKey()
    local edits = Store().edits
    for i, key in ipairs(order) do
        local t = _tiles[i]
        if t then
            local p = Build(key)
            local r, g, b = WithPreset(p, BNB.SkinColourOf)
            local br, bg_, bb = WithPreset(p, BNB.SkinBorderOf)
            local ar, ag, ab = WithPreset(p, BNB.SkinAccentOf)
            t:SetBackdropColor(r, g, b, 1)
            t:SetBackdropBorderColor(br, bg_, bb, 1)
            t._dot:SetVertexColor(ar, ag, ab, 1)
            t._ed:SetShown(((edits[key] and next(edits[key])) or IsCustom(key)) and true or false)
            t._key = key
            t:Show()
            if key == cur then K.PutRing(_tiles.ring, t) end
        end
    end
    for i = #order + 1, #_tiles do _tiles[i]:Hide() end
end

local function RefreshContrast(p)
    for i, pair in ipairs(PAIRS) do
        local fs = _contrast[i]
        if fs then
            local r1, g1, b1 = WithPreset(p, pair[2])
            local r2, g2, b2 = WithPreset(p, pair[3])
            local v = Ratio(r1, g1, b1, r2, g2, b2)
            local col = (v >= pair[4] and "66bb6a") or (v >= pair[4] * 0.66 and "ffaa33") or "ff5555"
            fs:SetText(string.format("%s  |cff%s%.1f|r", pair[1], col, v))
        end
    end
end

local function RefreshHue(p)
    for i, sw in ipairs(_hue) do
        local turn = TURNS[i][1] or (Store().freeHue or 90)
        local r, g, b = Suggestion(p, turn)
        sw._tex:SetVertexColor(r, g, b, 1)
        sw._rgb = { r, g, b }
        sw._turn = turn
    end
end

local function RefreshArt()
    if not _art.tiles then return end
    local name, path, mode, bgKind = CurArt()
    _art.name:SetText(name)
    _art.mode:SetText("Tint: " .. mode)
    for i, key in ipairs(Order()) do
        local t = _art.tiles[i]
        if t then
            local p = Build(key)
            local r, g, b
            if bgKind == "lifted" then r, g, b = WithPreset(p, BNB.SkinColourOf, true)
            elseif bgKind == "button" then r, g, b = BNB.SkinButtonOf(p)
            else r, g, b = WithPreset(p, BNB.SkinColourOf) end
            local br, bg_, bb = WithPreset(p, BNB.SkinBorderOf)
            t:SetBackdropColor(r, g, b, 1)
            t:SetBackdropBorderColor(br, bg_, bb, 1)
            t._tex:SetTexture(path)
            t._tex:SetVertexColor(WithPreset(p, ArtTint, mode))
            t._key = key
            t:Show()
        end
    end
    for i = #Order() + 1, #_art.tiles do _art.tiles[i]:Hide() end
end

local function RefreshPresetRow()
    if not _presetDD then return end
    wipe(_presetEntries)
    for _, key in ipairs(Order()) do
        _presetEntries[#_presetEntries + 1] = { label = Label(key), value = key }
    end
    _presetDD:SetSelected(CurKey())
    local custom = IsCustom(CurKey())
    _renameBtn:SetEnabled(custom)
    _deleteBtn:SetEnabled(custom)
    _deleteBtn:SetText(_delArmed == CurKey() and "Sure?" or "Delete")
end

Refresh = function()
    if not _f then return end
    local key = CurKey()
    local p = Build(key)
    for _, row in ipairs(_rows) do
        local r, g, b = RowColour(p, row.key)
        row.swatch._tex:SetVertexColor(r, g, b, 1)
        if not row.hex.eb:HasFocus() then row.hex.eb:SetText(Hex(r, g, b)) end
        local src = RowSource(key, row.key)
        row.src:SetText(src == "edited" and "|cff66bb6aedited|r"
            or (src == "exact" and (IsCustom(key) and "|cffaaaaaacopied|r" or "|cffaaaaaashipped|r")
            or "|cff888888worked out|r"))
        row.reset:SetEnabled(src == "edited")
    end
    RefreshPresetRow()
    _brtSl:SetEnabled(not p.noBright)
    _skinNote:SetShown(not (BigNoteBoxDB and BigNoteBoxDB.skinMode))
    RefreshStrip()
    RefreshContrast(p)
    RefreshHue(p)
    RefreshArt()
    ApplyFixed()
    ApplyFreeze()
end

-- ── Controls ─────────────────────────────────────────────────────────────────
local function BuildRow(parent, row, y)
    local lbl = parent:CreateFontString(nil, "OVERLAY", "BNBFontHighlight")
    lbl:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, y - 5)
    lbl:SetWidth(60); lbl:SetJustifyH("LEFT")
    lbl:SetText(row.label)

    -- Swatch: opens the colour wheel on the row's colour; Cancel puts it back
    local sw = CreateFrame("Button", nil, parent, "BackdropTemplate")
    sw:SetSize(36, 20)
    sw:SetPoint("TOPLEFT", parent, "TOPLEFT", 64, y)
    sw:SetBackdrop({ edgeFile = WHITE, edgeSize = 1 })
    sw:SetBackdropBorderColor(0.5, 0.5, 0.5, 1)
    local tex = sw:CreateTexture(nil, "ARTWORK")
    tex:SetPoint("TOPLEFT", 1, -1); tex:SetPoint("BOTTOMRIGHT", -1, 1)
    tex:SetTexture(WHITE)
    sw._tex = tex
    sw:SetScript("OnClick", function()
        local key = CurKey()
        local had = Store().edits[key] and Store().edits[key][row.key]
        local before = had and { had[1], had[2], had[3] }
        local r, g, b = RowColour(Build(key), row.key)
        BNB.OpenColorPicker(r, g, b, function(nr, ng, nb) SetEdit(row.key, nr, ng, nb) end,
            function()
                if before then SetEdit(row.key, before[1], before[2], before[3])
                else ClearEdit(row.key) end
            end)
    end)

    -- Hex: Enter or leaving the box applies a valid 6-digit colour
    local hex = K.PlainBox(parent, 76, 20)
    hex:SetPoint("TOPLEFT", parent, "TOPLEFT", 108, y)
    hex.eb:SetMaxLetters(7)
    local function Apply(self)
        local r, g, b = ParseHex(self:GetText())
        if r then
            local cr, cg, cb = RowColour(Build(CurKey()), row.key)
            if Hex(r, g, b) ~= Hex(cr, cg, cb) then SetEdit(row.key, r, g, b) return end
        end
        Refresh()
    end
    hex.eb:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    hex.eb:SetScript("OnEditFocusLost", Apply)
    hex.eb:SetScript("OnEscapePressed", function(self) self:SetText(""); self:ClearFocus() end)

    local reset = K.SmallBtn(parent, "Reset", 56, function() ClearEdit(row.key) end)
    reset:SetPoint("TOPLEFT", parent, "TOPLEFT", 192, y)

    local src = parent:CreateFontString(nil, "OVERLAY", "BNBFontHighlightSmall")
    src:SetPoint("TOPLEFT", parent, "TOPLEFT", 256, y - 5)

    row.swatch, row.hex, row.reset, row.src = sw, hex, reset, src
    return row
end

-- New from this / Rename: the name row stands in for the preset row
local function KeyFromName(name)
    local key = (name or ""):lower():gsub("[^%w]", "")
    if key:match("^%d") then key = "p" .. key end   -- a Lua name for the export
    return key
end

local function ShowNameRow(mode)
    _nameMode = mode
    _nameRow:Show()
    local cur = CurKey()
    _nameBox.eb:SetText(mode == "rename" and (Store().custom[cur].label or cur) or "")
    _nameBox.eb:SetFocus()
    _nameBox.eb:HighlightText()
end

local function HideNameRow()
    _nameMode = nil
    _nameRow:Hide()
    _nameBox.eb:ClearFocus()
end

local function CommitName()
    local name = strtrim(_nameBox.eb:GetText() or "")
    local key = KeyFromName(name)
    local s = Store()
    local cur = CurKey()
    if key == "" then BNB:Print("Skin Lab: type a name with letters or digits."); return end
    if _nameMode == "new" then
        if Exists(key) then BNB:Print("Skin Lab: a preset called '" .. key .. "' already exists."); return end
        s.custom[key] = { label = name, from = cur, preset = Build(cur) }
        s.key = key
    elseif _nameMode == "rename" and IsCustom(cur) then
        if key ~= cur then
            if Exists(key) then BNB:Print("Skin Lab: a preset called '" .. key .. "' already exists."); return end
            s.custom[key], s.custom[cur] = s.custom[cur], nil
            s.edits[key], s.edits[cur] = s.edits[cur], nil
            s.key = key
        end
        s.custom[key].label = name
    end
    HideNameRow()
    ApplyOverride(); Refresh()
end

local function DeleteCurrent()
    local cur = CurKey()
    if not IsCustom(cur) then return end
    if _delArmed ~= cur then
        _delArmed = cur
        RefreshPresetRow()
        C_Timer.After(3, function()
            if _delArmed == cur then _delArmed = nil; RefreshPresetRow() end
        end)
        return
    end
    local s = Store()
    local from = s.custom[cur].from
    s.custom[cur], s.edits[cur] = nil, nil
    s.key = Exists(from) and from or nil
    _delArmed = nil
    ApplyOverride(); Refresh()
end

local function Close()
    BNB.SetSkinOverride(nil)
    _ovr = nil
    if _nameRow then HideNameRow() end
    if BigNoteBoxDB and BigNoteBoxDB.skinMode and BNB.ApplyMainWindowSkin then
        BNB.ApplyMainWindowSkin()
    end
end

local function BuildPresetStrip(f, x, y, w)
    local n = math.max(#Order(), 16)
    local tw = math.min(36, math.floor((w - (n - 1) * 4) / n))
    _tiles.ring = K.Ring(f)
    for i = 1, n do
        local t = Tile(f, tw, STRIP_H)
        t:SetPoint("TOPLEFT", f, "TOPLEFT", x + (i - 1) * (tw + 4), y)
        local dot = t:CreateTexture(nil, "ARTWORK")
        dot:SetSize(8, 8)
        dot:SetPoint("CENTER")
        dot:SetTexture(WHITE)
        t._dot = dot
        local ed = t:CreateTexture(nil, "OVERLAY")
        ed:SetSize(5, 5)
        ed:SetPoint("TOPRIGHT", -2, -2)
        ed:SetColorTexture(0.40, 0.73, 0.42, 1)
        t._ed = ed
        t:SetScript("OnClick", function(self) if self._key then ShowPreset(self._key) end end)
        Tip(t, function(self)
            GameTooltip:AddLine(self._key and Label(self._key) or "", 1, 1, 1)
            GameTooltip:AddLine("Fill = body, edge = border, dot = accent. A green corner = edited.", 0.8, 0.8, 0.8, true)
        end)
        t:Hide()
        _tiles[i] = t
    end
end

local function BuildArtChecker(f, x, y, w)
    local hdr = BNB.CreateSectionHeader(f, "White art on every preset", 0, 200)
    hdr:ClearAllPoints(); hdr:SetPoint("TOPLEFT", f, "TOPLEFT", x, y)
    y = y - 22
    local function Step(d)
        local s = Store()
        s.artPath, s.artMode = nil, nil
        s.art = ((s.art or 1) - 1 + d) % #ART + 1
        if _art.path then _art.path.eb:SetRealText("") end
        RefreshArt()
    end
    local prev = K.SmallBtn(f, "<", 22, function() Step(-1) end)
    prev:SetPoint("TOPLEFT", f, "TOPLEFT", x, y)
    local name = f:CreateFontString(nil, "OVERLAY", "BNBFontHighlightSmall")
    name:SetPoint("LEFT", prev, "RIGHT", 6, 0)
    name:SetWidth(156); name:SetJustifyH("CENTER"); name:SetWordWrap(false)
    local nxt = K.SmallBtn(f, ">", 22, function() Step(1) end)
    nxt:SetPoint("LEFT", name, "RIGHT", 6, 0)
    local mode = K.SmallBtn(f, "Tint", 112, function()
        local s = Store()
        local _, _, cur = CurArt()
        local idx = 1
        for i, m in ipairs(MODES) do if m == cur then idx = i end end
        s.artMode = MODES[idx % #MODES + 1]
        RefreshArt()
    end)
    mode:SetPoint("LEFT", nxt, "RIGHT", 8, 0)
    Tip(mode, function()
        GameTooltip:AddLine("How the game tints it", 1, 1, 1)
        GameTooltip:AddLine("accent = top bar / toolbar icons, plate = accent x 0.6 (top bar hover), icon = border x 2.2 (icon buttons), marker = border x 2.2 capped (note icon markers). Click to cycle.", 0.8, 0.8, 0.8, true)
    end)
    local path = K.PlainBox(f, w - (22 + 6 + 156 + 6 + 22 + 8 + 112 + 8), 20)
    path:SetPoint("LEFT", mode, "RIGHT", 8, 0)
    BNB.AddPlaceholder(path.eb, "Any texture path + Enter")
    path.eb:SetScript("OnEnterPressed", function(self)
        local t = strtrim(self:GetRealText() or "")
        local s = Store()
        s.artPath = (t ~= "") and t or nil
        s.artMode = nil
        self:ClearFocus()
        RefreshArt()
    end)
    _art.name, _art.mode, _art.path = name, mode, path
    y = y - 28
    local n = math.max(#Order(), 16)
    local tw = math.min(38, math.floor((w - (n - 1) * 4) / n))
    _art.tiles = {}
    for i = 1, n do
        local t = Tile(f, tw, tw)
        t:SetPoint("TOPLEFT", f, "TOPLEFT", x + (i - 1) * (tw + 4), y)
        local tex = t:CreateTexture(nil, "ARTWORK")
        tex:SetPoint("TOPLEFT", 3, -3); tex:SetPoint("BOTTOMRIGHT", -3, 3)
        t._tex = tex
        t:SetScript("OnClick", function(self) if self._key then ShowPreset(self._key) end end)
        Tip(t, function(self) GameTooltip:AddLine(self._key and Label(self._key) or "", 1, 1, 1) end)
        t:Hide()
        _art.tiles[i] = t
    end
end

local function BuildWindow()
    H = math.min(H, math.floor(UIParent:GetHeight()) - 20)
    local f, exportBtn, revertBtn = BNB.CreateToolWindow({
        name = "BigNoteBoxSkinLab", w = W, h = H, title = "Skin Lab",
        pad = PAD, cw = COL_W, footH = 40,
        btn1 = "Export", btn2 = "Revert preset",
        toplevel = true, escClose = true,
    })
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    f:HookScript("OnHide", Close)
    exportBtn:SetScript("OnClick", function() BNB.ShowClipboardHint(ExportText(), f, true) end)
    revertBtn:SetScript("OnClick", function()
        local s = Store()
        s.edits[CurKey()] = nil
        s.brightness, s.alpha = nil, nil
        _brtSl:SetValue(SavedBrightness(), true)
        _alphaSl:SetValue(SavedAlpha(), true)
        ApplyOverride(); Refresh()
    end)
    _f = f

    local top = f._isSkin and BNB.TOOL_SKIN_TITLE_H or 30
    local ct = CreateFrame("Frame", nil, f)
    ct:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, -(top + 12))
    ct:SetSize(COL_W, H - top - 70)

    -- Preset row: dropdown + New from this / Rename / Delete
    local y = 0
    _presetEntries = {}
    _presetDD = BNB.CreateValueDropdown(ct, _presetEntries, CurKey(), function(key) ShowPreset(key) end, 184, 24)
    _presetDD:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
    _newBtn = K.SmallBtn(ct, "New", 60, function() ShowNameRow("new") end)
    _newBtn:SetPoint("TOPLEFT", ct, "TOPLEFT", 190, y - 2)
    Tip(_newBtn, function()
        GameTooltip:AddLine("New from this", 1, 1, 1)
        GameTooltip:AddLine("A new preset, a copy of the one shown (edits included). Export writes it as a new SKIN_PRESETS line.", 0.8, 0.8, 0.8, true)
    end)
    _renameBtn = K.SmallBtn(ct, "Rename", 64, function() ShowNameRow("rename") end)
    _renameBtn:SetPoint("TOPLEFT", ct, "TOPLEFT", 254, y - 2)
    _deleteBtn = K.SmallBtn(ct, "Delete", 58, DeleteCurrent)
    _deleteBtn:SetPoint("TOPLEFT", ct, "TOPLEFT", 322, y - 2)
    Tip(_deleteBtn, function()
        GameTooltip:AddLine("Rename / Delete", 1, 1, 1)
        GameTooltip:AddLine("Lab-made presets only: a shipped preset's key is saved in players' settings. Delete takes two clicks.", 0.8, 0.8, 0.8, true)
    end)
    _nameRow = CreateFrame("Frame", nil, ct)
    _nameRow:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
    _nameRow:SetSize(COL_W, 24)
    _nameRow:SetFrameLevel(_presetDD:GetFrameLevel() + 20)
    _nameRow:EnableMouse(true)
    local shade = _nameRow:CreateTexture(nil, "BACKGROUND")
    shade:SetAllPoints(); shade:SetColorTexture(0, 0, 0, 1)
    _nameBox = K.PlainBox(_nameRow, 248, 22)
    _nameBox:SetPoint("LEFT", _nameRow, "LEFT", 0, 0)
    _nameBox.eb:SetMaxLetters(24)
    _nameBox.eb:SetScript("OnEnterPressed", CommitName)
    _nameBox.eb:SetScript("OnEscapePressed", HideNameRow)
    local ok = K.SmallBtn(_nameRow, "OK", 60, CommitName)
    ok:SetPoint("LEFT", _nameBox, "RIGHT", 6, 0)
    local cancel = K.SmallBtn(_nameRow, "Cancel", 60, HideNameRow)
    cancel:SetPoint("LEFT", ok, "RIGHT", 6, 0)
    _nameRow:Hide()
    y = y - 34

    BNB.CreateSectionHeader(ct, "Colours", y, COL_W)
    y = y - 24
    for _, def in ipairs(ROWS) do
        _rows[#_rows + 1] = BuildRow(ct, { key = def.key, label = def.label }, y)
        y = y - ROW_H
    end
    local hosts = {}
    for _, row in ipairs(_rows) do hosts[#hosts + 1] = row.hex end
    K.TabChain(hosts)

    -- Contrast readout: two columns
    y = y - 4
    for i = 1, #PAIRS do
        local fs = ct:CreateFontString(nil, "OVERLAY", "BNBFontHighlightSmall")
        local col, line = (i - 1) % 2, math.floor((i - 1) / 2)
        fs:SetPoint("TOPLEFT", ct, "TOPLEFT", col * 190, y - line * 16)
        _contrast[i] = fs
    end
    local cHit = CreateFrame("Frame", nil, ct)
    cHit:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
    cHit:SetSize(COL_W, 48)
    Tip(cHit, function()
        GameTooltip:AddLine("Contrast (WCAG)", 1, 1, 1)
        GameTooltip:AddLine("Of the colours as drawn at this brightness, the window taken as opaque. Green = reads well (4.5 for text, 3 for icons and edges), orange = weak, red = poor.", 0.8, 0.8, 0.8, true)
    end)
    y = y - 54

    BNB.CreateSectionHeader(ct, "Try at (lab only, not saved)", y, COL_W)
    y = y - 22
    _brtSl = BNB.CreateStackedSlider(ct, COL_W, {
        label = "Brightness", min = 0.5, max = 3.0, step = 0.05,
        value = Store().brightness or SavedBrightness(), default = Def(),
        onChange = function(v) Store().brightness = v; ApplyOverride(); Refresh() end,
    })
    _brtSl:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
    y = y - BNB.STACKED_SLIDER_H - 6
    _alphaSl = BNB.CreateStackedSlider(ct, COL_W, {
        label = "Window opacity", min = 0, max = 1, step = 0.01,
        value = Store().alpha or SavedAlpha(), default = 0.97,
        fmt = function(v) return string.format("%d%%", math.floor(v * 100 + 0.5)) end,
        onChange = function(v) Store().alpha = v; ApplyOverride(); Refresh() end,
    })
    _alphaSl:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
    y = y - BNB.STACKED_SLIDER_H - 10

    -- Hue suggestions
    BNB.CreateSectionHeader(ct, "Accent suggestions", y, COL_W)
    y = y - 22
    for i, t in ipairs(TURNS) do
        local sw = Tile(ct, 40, 22)
        sw:SetPoint("TOPLEFT", ct, "TOPLEFT", (i - 1) * 46, y)
        sw:SetBackdropColor(0, 0, 0, 0)
        local tex = sw:CreateTexture(nil, "ARTWORK")
        tex:SetPoint("TOPLEFT", 1, -1); tex:SetPoint("BOTTOMRIGHT", -1, 1)
        tex:SetTexture(WHITE)
        sw._tex = tex
        sw:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        sw:SetScript("OnClick", function(self, btn)
            local c = self._rgb
            if c then SetEdit(btn == "RightButton" and "header" or "accent", c[1], c[2], c[3]) end
        end)
        Tip(sw, function(self)
            local c = self._rgb or { 0, 0, 0 }
            GameTooltip:AddLine(t[2] .. "  #" .. Hex(c[1], c[2], c[3]), 1, 1, 1)
            GameTooltip:AddLine("Turns of the preset's own hue (the border's; the accent's on a grey preset) at the accent's strength. Click: use as Accent. Right-click: use as Header.", 0.8, 0.8, 0.8, true)
        end)
        _hue[i] = sw
    end
    y = y - 30
    local freeSl = BNB.CreateStackedSlider(ct, COL_W, {
        label = "Free turn", min = 0, max = 359, step = 1,
        value = Store().freeHue or 90, default = 90,
        fmt = function(v) return v .. " deg" end,
        onChange = function(v) Store().freeHue = v; RefreshHue(Build(CurKey())) end,
    })
    freeSl:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
    y = y - BNB.STACKED_SLIDER_H - 10

    -- Freeze
    local flbl = ct:CreateFontString(nil, "OVERLAY", "BNBFontHighlight")
    flbl:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y - 5)
    flbl:SetText("Freeze")
    local freeze = BNB.CreateValueDropdown(ct, {
        { label = "Live (follow the mouse)", value = "live" }, { label = "Hover", value = "hover" },
        { label = "Pressed", value = "pressed" }, { label = "Disabled", value = "disabled" },
    }, Store().freeze or "live", function(v) Store().freeze = v; ApplyFreeze() end, 200, 24)
    freeze:SetPoint("TOPLEFT", ct, "TOPLEFT", 64, y)
    local fhelp = ct:CreateFontString(nil, "OVERLAY", "BNBFontHighlightSmall")
    fhelp:SetPoint("LEFT", freeze, "RIGHT", 8, 0)
    fhelp:SetWidth(COL_W - 64 - 200 - 8); fhelp:SetJustifyH("LEFT")
    fhelp:SetText("|cff888888the specimen's tabs, icons, dropdown, checkbox, slider, rows|r")
    y = y - 32

    _skinNote = ct:CreateFontString(nil, "OVERLAY", "BNBFontHighlightSmall")
    _skinNote:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
    _skinNote:SetWidth(COL_W); _skinNote:SetJustifyH("LEFT")
    _skinNote:SetText("|cffff9900Skin mode is off: the open windows keep their normal look.|r")

    -- Right side: presets strip, specimen, grey-art checker
    local rx = PAD + COL_W + COL_GAP
    local rw = W - rx - PAD
    local ry = -(top + 12)
    BuildPresetStrip(f, rx, ry, rw)
    ry = ry - STRIP_H - 10
    local specH = H - top - 12 - STRIP_H - 10 - ART_H - 56
    if BigNoteBoxDB and BigNoteBoxDB.skinMode then
        local ok2, sp = pcall(BuildSpecimen, f, rx, ry, rw, specH)
        if ok2 then _sp = sp else geterrorhandler()(sp) end
    else
        local box = Tile(f, rw, specH)
        box:SetPoint("TOPLEFT", f, "TOPLEFT", rx, ry)
        box:SetBackdropColor(0, 0, 0, 0.35)
        box:EnableMouse(false)
        local msg = box:CreateFontString(nil, "OVERLAY", "BNBFontHighlight")
        msg:SetPoint("CENTER")
        msg:SetWidth(rw - 60)
        msg:SetText("The specimen is drawn with the real skin builders, which take their look from skin mode when they are built.\n\nTurn on skin mode (Settings > Appearance) to see it. The colour rows, the presets strip, the white-art row and Export work without it.")
    end
    BuildArtChecker(f, rx, ry - specH - 10, rw)
    return f
end

function BNB.OpenSkinLab()
    if not BigNoteBoxDB then return end
    if not _f then BuildWindow() end
    if _f:IsShown() then _f:Raise(); return end
    ApplyOverride()
    _brtSl:SetValue(Store().brightness or SavedBrightness(), true)
    _alphaSl:SetValue(Store().alpha or SavedAlpha(), true)
    _f:Show(); _f:Raise()
    Refresh()
end

end

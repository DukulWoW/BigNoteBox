-- BigNoteBox_Dev Labs/SkinLab.lua
-- Developer Tools > Skin Lab (/bnb skinlab, debug mode). ALL-403 S2.
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
-- S3 adds the specimen panel (the real builders), the all-presets strip,
-- freeze toggles, contrast readout, grey-art checker and hue suggestions.
-- Dev tools only; nothing here is translated.

-- Queued for BigNoteBox's Core/DevTools.lua, which runs it once BigNoteBox
-- has loaded (this addon loads first, ARCH-04). The body is not indented.
BigNoteBoxDevLabs = BigNoteBoxDevLabs or {}
BigNoteBoxDevLabs[#BigNoteBoxDevLabs + 1] = function()

local BNB = BigNoteBox
if not BNB then return end

local K = BNB._LabKit
if not (K and BNB.SetSkinOverride and BNB.SKIN_PRESETS) then return end

local W, H, PAD = 820, 640, 16
local COL_W     = 380            -- the controls column
local ROW_H     = 28

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
-- s.brightness / s.alpha = the lab's sliders (nil = the saved settings)
local function Store()
    local db = BNB.LabDB()
    db.devSkinLab = db.devSkinLab or {}
    local s = db.devSkinLab
    s.edits = s.edits or {}
    return s
end

local function Def() return BNB.DEFAULTS.skinBrightness or 1.5 end

-- The preset as the lab shows it: the shipped one with the edits on top
local function Build(key)
    local src = BNB.SKIN_PRESETS[key] or BNB.SKIN_PRESETS.obsidian
    local p = {}
    for k, v in pairs(src) do p[k] = type(v) == "table" and { v[1], v[2], v[3] } or v end
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

local _ovr   -- the override table handed to BNB.SetSkinOverride while open

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
    if rowKey == "accent" then r, g, b = BNB.SkinAccentOf(p)
    else r, g, b = BNB.SkinHeaderOf(p) end
    if _ovr then _ovr.brightness = keep end
    return r, g, b
end

-- Where a row's colour comes from: "edited", "exact" (shipped) or "worked out"
local function RowSource(key, rowKey)
    local e = Store().edits[key]
    if e and e[rowKey] then return "edited" end
    local src = BNB.SKIN_PRESETS[key] or {}
    if rowKey == "body" or rowKey == "border" then return "exact" end
    return src[rowKey] ~= nil and "exact" or "worked out"
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
    for _, key in ipairs(BNB.SKIN_PRESET_ORDER) do
        if edits[key] and next(edits[key]) then out[#out + 1] = PresetLine(key) end
    end
    if #out == 1 then out[#out + 1] = "-- (no preset has edits)" end
    return table.concat(out, "\n")
end

-- ── Window ───────────────────────────────────────────────────────────────────
local _f
local _rows = {}
local _presetDD, _brtSl, _alphaSl, _skinNote
local _pv = {}       -- preview pieces

local function CurKey() return Store().key or BNB.GetSkinPresetKey() or "obsidian" end

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

-- The preview (S2 stand-in for S3's specimen panel): a small window drawn
-- with flat colours from the same getters the real UI reads
local function BuildPreview(parent, x, y, w, h)
    local box = BNB.CreateBackdropFrame("Frame", nil, parent)
    box:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    box:SetSize(w, h)
    box:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
    _pv.box = box

    local strip = box:CreateTexture(nil, "ARTWORK")
    strip:SetPoint("TOPLEFT", box, "TOPLEFT", 1, -1)
    strip:SetPoint("TOPRIGHT", box, "TOPRIGHT", -1, -1)
    strip:SetHeight(26)
    strip:SetTexture("Interface\\Buttons\\WHITE8x8")
    _pv.strip = strip

    local title = box:CreateFontString(nil, "OVERLAY", "BNBFontHighlight")
    title:SetPoint("LEFT", strip, "LEFT", 10, 0)
    title:SetText("Window title")
    _pv.title = title

    local head = box:CreateFontString(nil, "OVERLAY", "BNBFontNormalLarge")
    head:SetPoint("TOPLEFT", box, "TOPLEFT", 14, -42)
    head:SetText("Section heading")
    _pv.head = head

    local rule = box:CreateTexture(nil, "ARTWORK")
    rule:SetPoint("TOPLEFT", head, "BOTTOMLEFT", 0, -6)
    rule:SetPoint("RIGHT", box, "RIGHT", -14, 0)
    rule:SetHeight(1)
    rule:SetTexture("Interface\\Buttons\\WHITE8x8")
    _pv.rule = rule

    local body = box:CreateFontString(nil, "OVERLAY", "BNBFontHighlight")
    body:SetPoint("TOPLEFT", rule, "BOTTOMLEFT", 0, -10)
    body:SetPoint("RIGHT", box, "RIGHT", -14, 0)
    body:SetJustifyH("LEFT")
    body:SetText("Body text in the preset's white. Labels, checkbox labels and setting names use it; only headings and important text take the accent.")
    _pv.body = body

    local acc = box:CreateFontString(nil, "OVERLAY", "BNBFontHighlight")
    acc:SetPoint("TOPLEFT", body, "BOTTOMLEFT", 0, -12)
    acc:SetText("Accent text")
    _pv.acc = acc
    local accSq = box:CreateTexture(nil, "ARTWORK")
    accSq:SetSize(18, 18)
    accSq:SetPoint("LEFT", acc, "RIGHT", 10, 0)
    accSq:SetTexture("Interface\\Buttons\\WHITE8x8")
    _pv.accSq = accSq

    -- Two buttons drawn as the skin button: fill + border, label in white
    _pv.btns = {}
    for i, text in ipairs({ "Button", "Another" }) do
        local b = BNB.CreateBackdropFrame("Frame", nil, box)
        b:SetSize(96, 24)
        b:SetPoint("TOPLEFT", acc, "BOTTOMLEFT", (i - 1) * 106, -18)
        b:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
        local fs = b:CreateFontString(nil, "OVERLAY", "BNBFontHighlightSmall")
        fs:SetPoint("CENTER")
        fs:SetText(text)
        b._fs = fs
        _pv.btns[i] = b
    end

    local foot = box:CreateTexture(nil, "ARTWORK")
    foot:SetPoint("BOTTOMLEFT", box, "BOTTOMLEFT", 1, 1)
    foot:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -1, 1)
    foot:SetHeight(30)
    foot:SetTexture("Interface\\Buttons\\WHITE8x8")
    _pv.foot = foot

    local hint = box:CreateFontString(nil, "OVERLAY", "BNBFontHighlightSmall")
    hint:SetPoint("BOTTOMLEFT", box, "BOTTOMLEFT", 14, 40)
    hint:SetPoint("RIGHT", box, "RIGHT", -14, 0)
    hint:SetJustifyH("LEFT")
    hint:SetText("|cff888888A flat stand-in: the specimen panel with the real builders comes in S3. Every open BNB window shows the lab's colours too.|r")
end

local function RefreshPreview()
    local p = Build(CurKey())
    local alpha = (Store().alpha or SavedAlpha())
    local r, g, b = BNB.SkinColourOf(p)
    local lr, lg, lb = BNB.SkinColourOf(p, true)
    local br, bg_, bb = BNB.SkinBorderOf(p)
    _pv.box:SetBackdropColor(r, g, b, alpha)
    _pv.box:SetBackdropBorderColor(br, bg_, bb, 1)
    _pv.strip:SetVertexColor(lr, lg, lb, 1)
    _pv.foot:SetVertexColor(lr, lg, lb, 1)
    local rr, rg, rb = BNB.SkinRuleOf(p)
    _pv.rule:SetVertexColor(rr, rg, rb, 1)
    local tr, tg, tb = BNB.SkinTextOf(p)
    _pv.title:SetTextColor(tr, tg, tb)
    _pv.body:SetTextColor(tr, tg, tb)
    local hr, hg, hb = BNB.SkinHeaderOf(p)
    _pv.head:SetTextColor(hr, hg, hb)
    local ar, ag, ab = BNB.SkinAccentOf(p)
    _pv.acc:SetTextColor(ar, ag, ab)
    _pv.accSq:SetVertexColor(ar, ag, ab, 1)
    local fr, fg, fb = BNB.SkinButtonOf(p)
    for _, btn in ipairs(_pv.btns) do
        btn:SetBackdropColor(fr, fg, fb, 0.92)
        btn:SetBackdropBorderColor(br, bg_, bb, 1)
        btn._fs:SetTextColor(tr, tg, tb)
    end
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
            or (src == "exact" and "|cffaaaaaashipped|r" or "|cff888888worked out|r"))
        row.reset:SetEnabled(src == "edited")
    end
    if _presetDD then _presetDD:SetSelected(key) end
    local nb = p.noBright
    _brtSl:SetEnabled(not nb)
    _skinNote:SetShown(not (BigNoteBoxDB and BigNoteBoxDB.skinMode))
    RefreshPreview()
end

local function BuildRow(parent, row, y)
    local lbl = parent:CreateFontString(nil, "OVERLAY", "BNBFontHighlight")
    lbl:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, y - 5)
    lbl:SetWidth(60); lbl:SetJustifyH("LEFT")
    lbl:SetText(row.label)

    -- Swatch: opens the colour wheel on the row's colour; Cancel puts it back
    local sw = CreateFrame("Button", nil, parent, "BackdropTemplate")
    sw:SetSize(36, 20)
    sw:SetPoint("TOPLEFT", parent, "TOPLEFT", 64, y)
    sw:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
    sw:SetBackdropBorderColor(0.5, 0.5, 0.5, 1)
    local tex = sw:CreateTexture(nil, "ARTWORK")
    tex:SetPoint("TOPLEFT", 1, -1); tex:SetPoint("BOTTOMRIGHT", -1, 1)
    tex:SetTexture("Interface\\Buttons\\WHITE8x8")
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

local function Close()
    BNB.SetSkinOverride(nil)
    _ovr = nil
    if BigNoteBoxDB and BigNoteBoxDB.skinMode and BNB.ApplyMainWindowSkin then
        BNB.ApplyMainWindowSkin()
    end
end

local function BuildWindow()
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

    local y = 0
    local plbl = ct:CreateFontString(nil, "OVERLAY", "BNBFontHighlight")
    plbl:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y - 6)
    plbl:SetText("Preset")
    local entries = {}
    for _, key in ipairs(BNB.SKIN_PRESET_ORDER) do
        entries[#entries + 1] = { label = BNB.SkinPresetLabel(key), value = key }
    end
    _presetDD = BNB.CreateValueDropdown(ct, entries, CurKey(), function(key)
        Store().key = key
        ApplyOverride(); Refresh()
    end, COL_W - 64, 24)
    _presetDD:SetPoint("TOPLEFT", ct, "TOPLEFT", 64, y)
    y = y - 40

    local hdr = BNB.CreateSectionHeader(ct, "Colours", y, COL_W)
    hdr:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
    y = y - 24
    for _, def in ipairs(ROWS) do
        _rows[#_rows + 1] = BuildRow(ct, { key = def.key, label = def.label }, y)
        y = y - ROW_H
    end
    local hosts = {}
    for _, row in ipairs(_rows) do hosts[#hosts + 1] = row.hex end
    K.TabChain(hosts)

    y = y - 12
    BNB.CreateSectionHeader(ct, "Try at (lab only, not saved)", y, COL_W)
    y = y - 26
    _brtSl = BNB.CreateStackedSlider(ct, COL_W, {
        label = "Brightness", min = 0.5, max = 3.0, step = 0.05,
        value = Store().brightness or SavedBrightness(), default = Def(),
        onChange = function(v) Store().brightness = v; ApplyOverride(); Refresh() end,
    })
    _brtSl:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
    y = y - BNB.STACKED_SLIDER_H - 8
    _alphaSl = BNB.CreateStackedSlider(ct, COL_W, {
        label = "Window opacity", min = 0, max = 1, step = 0.01,
        value = Store().alpha or SavedAlpha(), default = 0.97,
        fmt = function(v) return string.format("%d%%", math.floor(v * 100 + 0.5)) end,
        onChange = function(v) Store().alpha = v; ApplyOverride(); Refresh() end,
    })
    _alphaSl:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
    y = y - BNB.STACKED_SLIDER_H - 8

    _skinNote = ct:CreateFontString(nil, "OVERLAY", "BNBFontHighlightSmall")
    _skinNote:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, y)
    _skinNote:SetWidth(COL_W); _skinNote:SetJustifyH("LEFT")
    _skinNote:SetText("|cffff9900Skin mode is off: only the preview on the right shows the lab's colours.|r")

    local px = PAD + COL_W + 24
    BuildPreview(f, px, -(top + 12), W - px - PAD, H - top - 70)
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

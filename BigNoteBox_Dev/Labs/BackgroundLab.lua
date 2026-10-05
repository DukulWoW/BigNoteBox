-- BigNoteBox_Dev Labs/BackgroundLab.lua
-- Developer Tools > Background Lab (/bnb bglab, debug mode). ALL-110.
-- Previews the game's own background textures in a resizable, sticky-like
-- window so each can be given a name, a fill mode and an anchor before it is
-- added to the sticky background list. Export hands back one Lua line per
-- entry. Work in progress is kept in BNB.LabDB().devBgLab across reloads.
-- Three windows (2026-10-02, like the Icon Lab):
--   control - picks the entry, name, fill, anchor, scale, exact numbers, Add
--   sheet   - the file with the picture area (gold) and its atlas regions;
--             draw the area by dragging, drag its edges, zoom, pan, aspect
--             lock (Labs/LabSheet.lua, shared with the Icon Lab later)
--   preview - sticky-like, shows what a sticky would
--
-- Fill modes and their maths live in UI/BgLayer.lua, shared with the
-- sticky notes, so this preview is what a sticky shows. "Try on stickies"
-- puts the current entry on every open sticky (not saved).
-- Mode and anchor names are dev-only and not translated.

-- Queued for BigNoteBox's Core/DevTools.lua, which runs it once BigNoteBox
-- has loaded (this addon loads first, ARCH-04). The body is not indented.
BigNoteBoxDevLabs = BigNoteBoxDevLabs or {}
BigNoteBoxDevLabs[#BigNoteBoxDevLabs + 1] = function()

local BNB = BigNoteBox
if not BNB then return end
local L = BNB.L
local K = BNB._LabKit   -- shared with the Icon Lab (Labs/LabKit.lua, ALL-126)

-- ── The candidates (Dukul, 2026-09-27, picked in wow.export) ─────────────────
-- g = the group Dukul sorted them into; it sets the starting mode/anchor.
local GROUPS = {
    tile    = { label = "Tile",                    mode = "tile",    anchor = "TOPLEFT" },
    fit     = { label = "Scale and fit",           mode = "cover",   anchor = "CENTER" },
    prof    = { label = "Bottom left, keep aspect", mode = "cover",  anchor = "BOTTOMLEFT" },
    strip   = { label = "Bottom, tile across",     mode = "tileX",   anchor = "BOTTOM" },
    stretch = { label = "Stretch",                 mode = "stretch", anchor = "CENTER" },
    menu    = { label = "Menu art (Forever, ALL-111)", mode = "stretch", anchor = "CENTER" },
}
GROUPS.batch2 = { label = "Second batch (added in game)", mode = "tile", anchor = "TOPLEFT" }
GROUPS.added = { label = "Added in game", mode = "tile", anchor = "TOPLEFT" }
local GROUP_ORDER = { "tile", "fit", "prof", "strip", "stretch", "menu", "batch2", "added" }

local LIST = {
    { g = "tile", id = 8198947, path = "interface/framegeneral/uicommonbackgrounds.blp" },
    { g = "tile", id = 8118796, path = "interface/bankframe/bankframebackgroundc60.blp" },
    { g = "tile", id = 7976009, path = "interface/credits/creditsscreenbackground0wowc60.blp" },
    { g = "tile", id = 7318373, path = "interface/framegeneral/uiframemidnightbackground.blp" },
    { g = "tile", id = 7242873, path = "interface/credits/creditsscreenbackground11midnight.blp" },
    { g = "tile", id = 7163692, path = "interface/gamepad/gamepadmapbackgroundtile.blp" },
    { g = "tile", id = 5874260, path = "interface/framegeneral/uiframethewarwithinbackground.blp" },
    { g = "tile", id = 5782252, path = "interface/bankframe/bankframebackground.blp" },
    { g = "tile", id = 4699279, path = "interface/framegeneral/uiframedragonflightbackground.blp" },
    { g = "tile", id = 4547578, path = "interface/credits/creditsscreenbackground9dragonflight.blp" },
    { g = "tile", id = 3775278, path = "interface/glues/characterselect/glueannouncementpopupbackground.blp" },
    { g = "tile", id = 3634724, path = "interface/framegeneral/uiframenecrolordbackground.blp" },
    { g = "tile", id = 3634718, path = "interface/framegeneral/uiframeventhyrbackground.blp" },
    { g = "tile", id = 3634712, path = "interface/framegeneral/uiframenightfaebackground.blp" },
    { g = "tile", id = 3550882, path = "interface/framegeneral/uiframekyrianbackground.blp" },
    { g = "tile", id = 3507722, path = "interface/framegeneral/uiframeoribosbackground.blp" },
    { g = "tile", id = 3025300, path = "interface/framegeneral/uiframemechagonbackground.blp" },
    { g = "tile", id = 2921659, path = "interface/framegeneral/uiframemarinebackground.blp" },
    { g = "tile", id = 2447133, path = "interface/framegeneral/ui-background-testwatermarkbackground.blp" },
    { g = "tile", id = 2142322, path = "interface/framegeneral/uiframeneutralbackground.blp" },
    { g = "tile", id = 2142253, path = "interface/framegeneral/uiframealliancebackground.blp" },
    { g = "tile", id = 2139059, path = "interface/framegeneral/uiframehordebackground.blp" },
    { g = "tile", id = 1450462, path = "interface/garrison/classhallbackground.blp" },

    { g = "fit", id = 7486949, path = "interface/journeys/journeysframebackground2x.blp" },
    { g = "fit", id = 7193900, path = "interface/housing/housingbasicpanelstonebackground2x.blp" },
    { g = "fit", id = 1970360, path = "environments/stars/8xp_burningteldrassil_backgroundgradient.blp" },

    { g = "prof", id = 7744229, path = "interface/professions/professionspecializationbackgroundartfirstaid.blp" },
    { g = "prof", id = 7744227, path = "interface/professions/professionspecializationbackgroundartpoisons.blp" },
    { g = "prof", id = 4723364, path = "interface/professions/professionspecializationbackgroundartmining.blp" },
    { g = "prof", id = 4723361, path = "interface/professions/professionspecializationbackgroundarttailoring.blp" },
    { g = "prof", id = 4723358, path = "interface/professions/professionspecializationbackgroundartskinning.blp" },
    { g = "prof", id = 4723355, path = "interface/professions/professionspecializationbackgroundartleatherworking.blp" },
    { g = "prof", id = 4723352, path = "interface/professions/professionspecializationbackgroundartjewelcrafting.blp" },
    { g = "prof", id = 4723349, path = "interface/professions/professionspecializationbackgroundartinscription.blp" },
    { g = "prof", id = 4723346, path = "interface/professions/professionspecializationbackgroundartherbalism.blp" },
    { g = "prof", id = 4723343, path = "interface/professions/professionspecializationbackgroundartfishing.blp" },
    { g = "prof", id = 4723340, path = "interface/professions/professionspecializationbackgroundartengineering.blp" },
    { g = "prof", id = 4723337, path = "interface/professions/professionspecializationbackgroundartenchanting.blp" },
    { g = "prof", id = 4723334, path = "interface/professions/professionspecializationbackgroundartcooking.blp" },
    { g = "prof", id = 4723331, path = "interface/professions/professionspecializationbackgroundartalchemy.blp" },
    { g = "prof", id = 4723325, path = "interface/professions/professionspecializationbackgroundartblacksmithing.blp" },
    { g = "prof", id = 4723320, path = "interface/professions/professionbackgroundartenchanting.blp" },
    { g = "prof", id = 4723316, path = "interface/professions/professionbackgroundartfishing.blp" },
    { g = "prof", id = 4723308, path = "interface/professions/professionbackgroundartskinning.blp" },
    { g = "prof", id = 4723189, path = "interface/professions/professionbackgroundartmining.blp" },
    { g = "prof", id = 4723159, path = "interface/professions/professionbackgroundartherbalism.blp" },
    { g = "prof", id = 4723154, path = "interface/professions/professionbackgroundartleatherworking.blp" },
    { g = "prof", id = 4723119, path = "interface/professions/professionbackgroundartinscription.blp" },
    { g = "prof", id = 4723112, path = "interface/professions/professionbackgroundartjewelcrafting.blp" },
    { g = "prof", id = 4722478, path = "interface/professions/professionbackgroundartengineering.blp" },
    { g = "prof", id = 4627497, path = "interface/professions/professionbackgroundarttailoring.blp" },
    { g = "prof", id = 4625450, path = "interface/professions/professionbackgroundartalchemy.blp" },
    { g = "prof", id = 4625448, path = "interface/professions/professionbackgroundartblacksmithing.blp" },

    { g = "strip", id = 1693869, path = "world/environment/doodad/7.0/argus/matte painting/texture/7arg_argus_floatingislebackground03.blp" },
    { g = "strip", id = 1693866, path = "world/environment/doodad/7.0/argus/matte painting/texture/7arg_argus_floatingislebackground02.blp" },

    { g = "stretch", id = 5582795, path = "interface/glues/models/ui_pirate/kultiran_background_02.blp" },
    { g = "stretch", id = 4659666, path = "interface/professions/professionbackgroundart.blp" },

    { g = "menu", id = 1575078, path = "interface/encounterjournal/loottab-item-background.blp" },

    -- Dukul's second batch, first added in game on Forever (ALL-110); listed
    -- here so the Lab on the other client checks them too. No paths known.
    { g = "batch2", id = 191123,  path = "" },
    { g = "batch2", id = 235412,  path = "" },
    { g = "batch2", id = 457640,  path = "" },
    { g = "batch2", id = 609607,  path = "" },
    { g = "batch2", id = 644000,  path = "" },
    { g = "batch2", id = 650623,  path = "" },
    { g = "batch2", id = 839173,  path = "" },
    { g = "batch2", id = 1119242, path = "" },
    { g = "batch2", id = 1260093, path = "" },
    { g = "batch2", id = 4671747, path = "" },
    { g = "batch2", id = 5703596, path = "" },
    { g = "batch2", id = 7486947, path = "" },
}
for _, e in ipairs(LIST) do
    e.key = e.path:match("([^/]+)%.blp$") or ("file" .. e.id)
end

local BL      = BNB.BgLayer
local MODES   = BL.MODES
local ANCHORS = BL.ANCHORS

local DEF_BASE = { 0.07, 0.07, 0.09 }   -- sticky COL_BG (UI/StickyNote.lua)
local INSET    = 3                        -- sticky "Default" border inset
local C_W, C_H = 360, 756
local C_PAD    = 16
local COL_CROP = { 1, 0.82, 0, 1 }

-- Aspect lock for the picture area on the sheet, cycled with its button.
-- preview = the preview window's shape, which is what Cover shows on a
-- sticky of that shape; file = the file's own shape.
local ASPECTS = {
    { nil,      "Aspect: off" },
    { "preview", "Aspect: preview" },
    { "file",    "Aspect: file" },
    { "square",  "Aspect: 1:1" },
}

local _ctl, _pv, _sheet
local _idx = 1
local _trying   -- "Try on stickies" is on

local function R(v) return math.floor(v + 0.5) end

-- ── Saved state ──────────────────────────────────────────────────────────────
local function Store()
    local db = BNB.LabDB()
    db.devBgLab = db.devBgLab or { e = {} }
    return db.devBgLab
end

-- The saved settings for entry i, created from its group defaults on first use.
local function State(i)
    local e = LIST[i]
    local s = Store().e
    local st = s[e.key]
    if not st then
        local g = GROUPS[e.g]
        st = { mode = g.mode, anchor = g.anchor, scale = 1 }
        s[e.key] = st
    end
    return st
end

-- The sheet's own view options (Labs/LabSheet.lua)
local function SheetView()
    local s = Store()
    s.sheet = s.sheet or {}
    return s.sheet
end

-- ── Native size (Labs/LabKit.lua probe) ────────────────────────────────────────
-- Sizes are saved once probed (Store().sizes), so Export and the list know
-- them for entries not opened this session. A failed probe is not saved: the
-- file may load another time. A manual W/H in the panel wins over both.
local _prober = K.NewProber()
local _sizes  = _prober.sizes   -- [id] = { w, h } or false (did not load)

local function FileSize(id)
    local sz = _sizes[id]
    if sz == nil then sz = Store().sizes and Store().sizes[id] end
    return sz
end

local function RememberSize(id)
    local sz = _sizes[id]
    if type(sz) == "table" then
        local s = Store()
        s.sizes = s.sizes or {}
        s.sizes[id] = { sz[1], sz[2] }
    end
end

local function NativeSize(i)
    local st, sz = State(i), FileSize(LIST[i].id)
    local w = st.w or (type(sz) == "table" and sz[1] or nil)
    local h = st.h or (type(sz) == "table" and sz[2] or nil)
    return w, h
end

-- Picture area (crop, UI/BgLayer.lua): x / y / w / h in file pixels, set
-- when the art fills only part of its file. nil until W and H are both set.
local function Crop(st)
    if st.cw and st.ch then return { st.cx or 0, st.cy or 0, st.cw, st.ch } end
end

local function Flip(st)
    if st.flipH and st.flipV then return "hv" end
    return (st.flipH and "h") or (st.flipV and "v") or nil
end

-- The current entry as a BgLayer def (UI/BgLayer.lua)
local function LabDef(i)
    local st = State(i)
    local nw, nh = NativeSize(i)
    return { file = LIST[i].id, mode = st.mode, anchor = st.anchor, scale = st.scale or 1, w = nw, h = nh,
             crop = Crop(st), flip = Flip(st), bright = st.bright }
end

-- ── The picture area as a sheet box ──────────────────────────────────────────
local function Box()
    local st = State(_idx)
    if st.cw and st.ch then return st.cx or 0, st.cy or 0, st.cw, st.ch end
end

local function FileRect()
    local W, H = NativeSize(_idx)
    if W and H then return 0, 0, W, H end
end

-- The box the tools start from: the saved one, else the whole file
local function ToolBox()
    local x, y, w, h = Box()
    if x then return x, y, w, h end
    return FileRect()
end

-- Stores the picture area on whole pixels inside the file; nil x clears it
local function SetBox(x, y, w, h)
    local st = State(_idx)
    if not x then st.cx, st.cy, st.cw, st.ch = nil, nil, nil, nil; return end
    x, y, w, h = R(x), R(y), math.max(1, R(w)), math.max(1, R(h))
    local W, H = NativeSize(_idx)
    if W and H then
        x, y = math.max(0, math.min(x, W - 1)), math.max(0, math.min(y, H - 1))
        w, h = math.min(w, W - x), math.min(h, H - y)
    end
    st.cx, st.cy, st.cw, st.ch = x, y, w, h
end

local function LayoutPreview()
    if not (_pv and _pv:IsShown()) then return end
    local e, st = LIST[_idx], State(_idx)
    local area, tex = _pv.area, _pv.tex
    local W, H = area:GetSize()
    local b = st.base or DEF_BASE
    _pv.base:SetColorTexture(b[1], b[2], b[3], 1)
    _pv.title:SetText((st.name and st.name ~= "") and st.name or e.key)

    local nw, nh = NativeSize(_idx)
    if not (W > 1 and H > 1) then return end
    if not (nw and nh and nw > 0 and nh > 0) then
        BL.Draw(tex, area, nil); BL.Draw(_pv.add, area, nil)   -- hides tiled copies too
        _pv.warn:SetText(FileSize(e.id) == false and "Texture did not load on this client"
            or "Native size unknown: type W and H in the panel")
        _pv.warn:Show()
        return
    end
    _pv.warn:Hide()

    -- Curated brightness as a sticky draws it (BgLayer.ApplyTint): darker =
    -- vertex colour, lighter = an ADD copy on top
    local def = LabDef(_idx)
    local k = BL.Brightness(0, def)
    local m = k < 0 and (1 + k) or 1
    tex:SetVertexColor(m, m, m, 1)
    _pv.add:SetVertexColor(k, k, k, 1)   -- before Draw: tiled copies take it then
    if not (BL.Draw(tex, area, def) and k > 0 and BL.Draw(_pv.add, area, def)) then
        BL.Draw(_pv.add, area, nil)   -- hides it and its tiled copies
    end
end

-- ── Preview window (sticky-like) ─────────────────────────────────────────────
local function BuildPreview()
    local f = BNB.CreateBackdropFrame("Frame", "BigNoteBoxBgLabPreview", UIParent)
    f:SetSize(360, 260)
    f:SetFrameStrata("MEDIUM")
    f:SetClampedToScreen(true)
    f:SetMovable(true); f:SetResizable(true)
    f:SetResizeBounds(120, 80, 1600, 1000)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetBackdrop({
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 14,
        insets = { left = INSET, right = INSET, top = INSET, bottom = INSET },
    })
    f:SetBackdropBorderColor(0.6, 0.6, 0.65, 1)
    if BNB.SetMoveCursor then BNB.SetMoveCursor(f) end

    local area = CreateFrame("Frame", nil, f)
    area:SetPoint("TOPLEFT", f, "TOPLEFT", INSET, -INSET)
    area:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -INSET, INSET)
    area:SetFrameLevel(math.max(0, f:GetFrameLevel() - 1))
    f.area = area
    f.base = area:CreateTexture(nil, "BACKGROUND", nil, -8)
    f.base:SetAllPoints()
    f.tex = area:CreateTexture(nil, "BACKGROUND", nil, 0)
    f.add = area:CreateTexture(nil, "BACKGROUND", nil, 1)
    f.add:SetBlendMode("ADD")
    f.add:Hide()

    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.title:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -8)
    f.title:SetPoint("TOPRIGHT", f, "TOPRIGHT", -10, -8)
    f.title:SetJustifyH("LEFT")

    f.sample = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    f.sample:SetPoint("TOPLEFT", f.title, "BOTTOMLEFT", 0, -8)
    f.sample:SetPoint("RIGHT", f, "RIGHT", -12, 0)
    f.sample:SetJustifyH("LEFT"); f.sample:SetJustifyV("TOP")
    f.sample:SetWordWrap(true)
    f.sample:SetText(L["DEV_WIN_BGLAB_SAMPLE"])

    f.warn = f:CreateFontString(nil, "OVERLAY", "GameFontRedSmall")
    f.warn:SetPoint("CENTER")

    BNB.CreateResizeGrip(f, {   -- UI/Widgets.lua (ALL-263)
        onStop = function() local s = Store(); s.pw, s.ph = f:GetSize() end,
    })

    f:SetScript("OnSizeChanged", LayoutPreview)
    f:HookScript("OnShow", LayoutPreview)
    local s = Store()
    if s.pw and s.ph then f:SetSize(s.pw, s.ph) end
    f:Hide()
    return f
end

-- ── Export ───────────────────────────────────────────────────────────────────
local function Q(s) return string.format("%q", s) end

-- Only named entries go out, and not Done (already in the registry) or
-- Skip (rejected), the same rule as the Icon Lab (Dukul 2026-10-02)
local function ExportText()
    local out, n, done, skipped, unnamed = {}, 0, 0, 0, 0
    for i, e in ipairs(LIST) do
        local st = Store().e[e.key]
        if not st then
            -- never looked at
        elseif st.done then
            done = done + 1
        elseif st.skip then
            skipped = skipped + 1
        elseif not (st.name and st.name ~= "") then
            unnamed = unnamed + 1
        else
            n = n + 1
            local nw, nh = NativeSize(i)
            local b = st.base
            local line = string.format(
                "{ key = %s, name = %s, file = %d, path = %s, w = %s, h = %s, mode = %s, anchor = %s, scale = %s%s%s%s%s%s%s },",
                Q(e.key), Q(st.name or ""), e.id, Q(e.path), tostring(nw or "nil"), tostring(nh or "nil"),
                Q(st.mode), Q(st.anchor), tostring(st.scale or 1),
                e.atlas and (", atlas = " .. Q(e.atlas)) or "",
                Crop(st) and string.format(", crop = { %d, %d, %d, %d }", unpack(Crop(st))) or "",
                Flip(st) and (", flip = " .. Q(Flip(st))) or "",
                st.bright and string.format(", bright = %.2f", st.bright) or "",
                b and string.format(", base = { %.2f, %.2f, %.2f }", b[1], b[2], b[3]) or "",
                FileSize(e.id) == false and ", loaded = false" or "")
            out[#out + 1] = line
        end
    end
    table.insert(out, 1, string.format(
        "-- Background Lab export: %d named of %d, left out: %d done, %d skipped, %d not named yet. Client %s",
        n, #LIST, done, skipped, unnamed, BNB.IsForever and "Forever" or "Retail"))
    return table.concat(out, "\n")
end

-- ── Control window ───────────────────────────────────────────────────────────
local Refresh

local SmallBtn, Ring, PutRing = K.SmallBtn, K.Ring, K.PutRing
local function NumBox(parent, w, onSet) return K.NumBox(parent, w, onSet, function() Refresh() end) end

-- ── Textures added in game (listfile lines, file IDs or atlas names) ────────
-- Kept in devBgLab.custom as { id, path, atlas } and appended to LIST as
-- group "added", so new finds from wow.export can be tried without a code
-- change. An atlas entry is its file plus a Picture area taken from the
-- atlas coordinates (ALL-120); one file can hold several atlases, so an entry
-- is one file + atlas pair.
local CustomKey = K.EntryKey

local function SameEntry(e, id, atlas)
    return e.id == id and (e.atlas or "") == (atlas or "")
end

local function AppendCustom(c)
    for i, e in ipairs(LIST) do
        if SameEntry(e, c.id, c.atlas) then return i end
    end
    LIST[#LIST + 1] = { g = "added", id = c.id, path = c.path or "", atlas = c.atlas,
                        key = CustomKey(c.id, c.path or "", c.atlas) }
    return #LIST
end

local ValidID = K.ValidID

-- Entries without a usable file ID are dropped from the saved list (one
-- saved as { path = "" } on Forever 2026-09-27 broke opening the Lab)
local _customLoaded
local function LoadCustom()
    if _customLoaded then return end
    _customLoaded = true
    local s = Store()
    local kept = {}
    for _, c in ipairs(s.custom or {}) do
        if type(c) == "table" and ValidID(c.id) then
            kept[#kept + 1] = c
            AppendCustom(c)
        end
    end
    if s.custom then s.custom = kept end
end

local function AddCustom(id, path, atlas)
    if not ValidID(id) then return nil end
    path = (path or ""):gsub("\\", "/"):lower():gsub("^%s+", ""):gsub("%s+$", "")
    local s = Store()
    s.custom = s.custom or {}
    for i, e in ipairs(LIST) do
        if SameEntry(e, id, atlas) then return i end   -- already in the list: just go there
    end
    s.custom[#s.custom + 1] = { id = id, path = path, atlas = atlas }
    return AppendCustom(s.custom[#s.custom])
end

-- The path of a file as the list knows it (an atlas entry has none of its own)
local function FilePath(id)
    for _, e in ipairs(LIST) do
        if e.id == id and e.path ~= "" then return e.path end
    end
    return ""
end

-- Adds every line of the paste box: listfile lines (path;fileID), bare file
-- IDs and atlas names. Returns how many were added and the last index.
local function AddLines(text)
    local added, bad, last = 0, 0, nil
    for line in (text or ""):gmatch("[^\r\n]+") do
        line = line:gsub("^%s+", ""):gsub("%s+$", "")
        if line ~= "" then
            local id, path = K.ParseListfileLine(line)
            local i
            if id then
                i = AddCustom(id, path)
            else
                local aid = not line:find("[/\\;]") and K.ResolveAtlas(line)
                if aid then i = AddCustom(aid, FilePath(aid), line) end
            end
            if i then added, last = added + 1, i else bad = bad + 1 end
        end
    end
    return added, bad, last
end

local function RemoveCustom(i)
    local e = LIST[i]
    if not (e and e.g == "added") then return end
    local s = Store()
    for n = #(s.custom or {}), 1, -1 do
        if SameEntry(s.custom[n], e.id, e.atlas) then table.remove(s.custom, n) end
    end
    s.e[e.key] = nil
    table.remove(LIST, i)
end

-- ── Atlas regions (Labs/IconLabAtlas.lua, dev builds) ──────────────────────────
local RegionRect = K.NewRegionRects()

-- The regions of entry e's file, looked up once per entry
local function Regions(e)
    e = e or LIST[_idx]
    if not e then return nil end
    if e._regs == nil then
        e._regs = K.AtlasRegions(e.id, e.path ~= "" and e.path or FilePath(e.id)) or false
    end
    return e._regs or nil
end

-- Fills an atlas entry's Picture area from the atlas coordinates x the file's
-- size, once the size is known, and only while no Picture area is set (a
-- hand-tuned one survives later visits). This client's own atlas wins; the
-- generated coordinates stand in when it has none.
local function ApplyAtlasCrop(i)
    local e = LIST[i]
    if not (e and e.atlas) then return end
    local st = State(i)
    local W, H = NativeSize(i)   -- a manual W/H wins over the probe
    if st.cw or not (W and H) then return end
    local reg = { e.atlas }
    for _, r in ipairs(Regions(e) or {}) do
        if r[1] == e.atlas then reg = r; break end
    end
    local x, y, w, h = RegionRect(e.id, reg, W, H)
    if x then st.cx, st.cy, st.cw, st.ch = x, y, w, h end
end

-- Hidden by the Hide done filter: done, skipped, or the file did not load here
local function FilteredOut(i)
    if not Store().hideOut or i == _idx then return false end
    local e = LIST[i]
    local st = Store().e[e.key]
    return (st and (st.done or st.skip)) or FileSize(e.id) == false
end

local function Go(i)
    _idx = ((i - 1) % #LIST) + 1
    Store().idx = _idx
    State(_idx)
    if _ctl and _ctl.nameEb then _ctl.nameEb._pending = nil end   -- a new entry shows its saved name
    if _sheet then _sheet.SetHoverRegion(nil) end
    Refresh()
    local e = LIST[_idx]
    _prober:Probe(_ctl, e.id, function()
        RememberSize(e.id)
        if LIST[_idx] == e then ApplyAtlasCrop(_idx); Refresh() end
    end)
end

-- < > step over filtered entries
local function Step(d)
    local i = _idx
    for _ = 1, #LIST do
        i = ((i + d - 1) % #LIST) + 1
        if not FilteredOut(i) then break end
    end
    Go(i)
end

-- A region picked on the sheet: an entry of its own (file + atlas pair)
local function PickRegion(name)
    local e = LIST[_idx]
    local i = AddCustom(e.id, e.path ~= "" and e.path or FilePath(e.id), name)
    if i then Go(i) end
end

-- Measures every listed file with no saved size, one at a time, on its own
-- prober (the entry prober drops a probe when you move on). Files that do
-- not load on this client show red in the list.
local _bgProber = K.NewProber()
local function ProbeAllSizes()
    local queue, seen = {}, {}
    for _, e in ipairs(LIST) do
        if not seen[e.id] and type(FileSize(e.id)) ~= "table" then
            seen[e.id] = true
            queue[#queue + 1] = e.id
        end
    end
    local n = 0
    local function NextOne()
        n = n + 1
        local id = queue[n]
        if not id then return end
        _bgProber:Probe(_ctl, id, function()
            if _sizes[id] == nil then   -- a table, or false: did not load here
                _sizes[id] = _bgProber.sizes[id]
                RememberSize(id)
                if LIST[_idx] and LIST[_idx].id == id then Refresh() end
            end
            NextOne()
        end)
    end
    NextOne()
end

local function AspectRatio()
    local a = Store().aspect
    if a == "preview" and _pv then
        local w, h = _pv.area:GetSize()
        if w > 1 and h > 1 then return w / h end
    elseif a == "file" then
        local W, H = NativeSize(_idx)
        if W and H then return W / H end
    elseif a == "square" then
        return 1
    end
end

local function BuildSheet()
    _sheet = K.NewSheet({
        name = "BigNoteBoxBgLabSheet", minW = 600,
        View = SheetView,
        File = function()
            local e = LIST[_idx]
            if not e then return nil end
            local W, H = NativeSize(_idx)
            return e.id, W, H, e.atlas or (e.path ~= "" and e.path) or ("file " .. e.id), FileSize(e.id) == false
        end,
        boxes = { { key = "area", label = "Area", col = COL_CROP } },
        Active = function() return "area" end,
        Box = function() return Box() end,
        ToolBox = function() return ToolBox() end,
        Bounds = function() return FileRect() end,
        SetBox = function(_, x, y, w, h) SetBox(x, y, w, h) end,
        Changed = function() Refresh() end,
        Regions = function() return Regions() end,
        RegionRect = function(reg, W, H) return RegionRect(LIST[_idx].id, reg, W, H) end,
        PickRegion = PickRegion,
        Aspect = AspectRatio,
        AddTools = function(f, last, S)
            local asp = SmallBtn(f, ASPECTS[1][2], 104, function()
                local cur, s = 1, Store()
                for n, a in ipairs(ASPECTS) do if a[1] == s.aspect then cur = n end end
                s.aspect = ASPECTS[cur % #ASPECTS + 1][1]
                Refresh()
            end)
            asp:SetPoint("LEFT", last, "RIGHT", 10, 0)
            asp:HookScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_TOP")
                GameTooltip:AddLine("Aspect lock", 1, 1, 1)
                GameTooltip:AddLine("Holds the picture area to this shape while you draw, drag an edge or resize. Preview = the preview window's shape, which is what Cover shows on a sticky that shape. Match fits the current box to it.", 0.8, 0.8, 0.8, true)
                GameTooltip:Show()
            end)
            asp:HookScript("OnLeave", function() GameTooltip:Hide() end)
            f.aspBtn = asp
            local match = SmallBtn(f, "Match", 56, S.MatchAspect)
            match:SetPoint("LEFT", asp, "RIGHT", 6, 0)
            f.matchBtn = match
            local whole = SmallBtn(f, "Whole file", 76, function() SetBox(nil); Refresh() end)
            whole:SetPoint("LEFT", match, "RIGHT", 6, 0)
        end,
    })
    return _sheet.Build()
end

local function BuildControl()
    local f, exportBtn, closeBtn = BNB.CreateToolWindow({
        name = "BigNoteBoxBgLab", w = C_W, h = C_H,
        title = L["DEV_WIN_BGLAB_TITLE"], pad = C_PAD, cw = C_W - C_PAD * 2, footH = 40,
        btn1 = L["DEV_WIN_BGLAB_EXPORT"], btn2 = L["CLOSE"],
        onClose = function() _ctl:Hide() end,
        toplevel = true, escClose = true,
    })
    f:SetPoint("CENTER", UIParent, "CENTER", 120, 0)   -- sheet to the left, preview to the right
    closeBtn:SetScript("OnClick", function() f:Hide() end)
    exportBtn:SetScript("OnClick", function() BNB.ShowClipboardHint(ExportText(), f, true) end)
    f:HookScript("OnHide", function()
        if _sheet and _sheet.frame then _sheet.frame:Hide() end
        if _pv then _pv:Hide() end
    end)
    _ctl = f

    local cw = C_W - C_PAD * 2
    local body = CreateFrame("Frame", nil, f)
    body:SetPoint("TOPLEFT", f, "TOPLEFT", C_PAD, -34)
    body:SetSize(cw, C_H - 80)
    local y = 0

    local function Check(label, x, yy, onClick)
        local cb = CreateFrame("CheckButton", nil, body, "UICheckButtonTemplate")
        cb:SetSize(24, 24)
        cb:SetPoint("TOPLEFT", body, "TOPLEFT", x - 4, yy)
        cb.text = cb.text or cb:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        cb.text:ClearAllPoints()
        cb.text:SetPoint("LEFT", cb, "RIGHT", 2, 0)
        cb.text:SetFontObject("GameFontHighlightSmall")
        cb.text:SetText(label)
        cb:SetScript("OnClick", onClick)
        return cb
    end

    -- Navigation: < jump list >, and the list filter
    local prev = SmallBtn(body, "<", 30, function() Step(-1) end)
    prev:SetPoint("TOPLEFT", body, "TOPLEFT", 0, y)
    local hideCb = Check(L["DEV_WIN_ICONLAB_HIDE_DONE"], 0, y + 2, function(self)
        Store().hideOut = self:GetChecked() or nil
    end)
    hideCb:ClearAllPoints()
    hideCb:SetPoint("TOPLEFT", body, "TOPLEFT", cw - hideCb.text:GetStringWidth() - 22, y + 2)
    hideCb:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(L["DEV_WIN_BGLAB_HIDE_OUT_TIP"], 1, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    hideCb:SetScript("OnLeave", function() GameTooltip:Hide() end)
    f.hideOutCb = hideCb
    local nextB = SmallBtn(body, ">", 30, function() Step(1) end)
    nextB:SetPoint("TOPRIGHT", hideCb, "TOPLEFT", -4, -2)
    local dd = CreateFrame("DropdownButton", nil, body, "WowStyle1DropdownTemplate")
    dd:SetPoint("LEFT", prev, "RIGHT", 6, 0)
    dd:SetPoint("RIGHT", nextB, "LEFT", -6, 0)
    -- Green = named, grey = done or skipped, red = the file did not load here
    dd:SetupMenu(function(_, root)
        pcall(function() root:SetScrollMode(500) end)
        for _, gk in ipairs(GROUP_ORDER) do
            local titled
            for i, e in ipairs(LIST) do
                if e.g == gk and not FilteredOut(i) then
                    if not titled then root:CreateTitle(GROUPS[gk].label); titled = true end
                    local st = Store().e[e.key]
                    local lbl = (st and st.name and st.name ~= "") and st.name or (e.atlas or e.key)
                    if FileSize(e.id) == false then lbl = "|cffff5555" .. lbl .. " (did not load)|r"
                    elseif st and st.done then lbl = "|cff888888" .. lbl .. " (done)|r"
                    elseif st and st.skip then lbl = "|cff888888" .. lbl .. " (skip)|r"
                    elseif st and st.name and st.name ~= "" then lbl = "|cff66bb6a" .. lbl .. "|r" end
                    root:CreateRadio(lbl, function() return _idx == i end, function() Go(i) end)
                end
            end
        end
    end)
    f.dd = dd
    y = y - 28

    local info = body:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    info:SetPoint("TOPLEFT", body, "TOPLEFT", 0, y)
    info:SetWidth(cw); info:SetJustifyH("LEFT"); info:SetWordWrap(true)
    f.info = info
    y = y - 44

    -- Name, as in the Icon Lab: saved only when accepted (Tab, Enter or OK).
    -- A named entry is green in the list and goes into Export; Esc puts the
    -- saved name back. Leaving the box keeps the typed text: clicking OK
    -- takes the focus away before its OnClick. The next entry switch shows
    -- the saved name again.
    BNB.CreateSmallLabel(body, L["DEV_WIN_ICONLAB_NAME"], y, cw)
    y = y - 14
    local nameHost = K.PlainBox(body, cw - 40, 22)
    nameHost:SetPoint("TOPLEFT", body, "TOPLEFT", 0, y)
    local nameEb = nameHost.eb
    nameEb:SetFontObject("GameFontHighlight")
    nameEb:SetMaxLetters(40)
    nameEb:SetScript("OnTextChanged", function(self, user)
        if user then self._pending = true end   -- typed, not accepted yet
    end)
    local function AcceptName()
        nameEb._pending = nil
        local v = nameEb:GetText():gsub("^%s+", ""):gsub("%s+$", "")
        State(_idx).name = (v ~= "") and v or nil
        nameEb:ClearFocus()
        Refresh()
    end
    nameEb:SetScript("OnEnterPressed", AcceptName)
    nameEb:SetScript("OnTabPressed", function() AcceptName(); Step(1) end)
    nameEb:SetScript("OnEscapePressed", function(self) self._pending = nil; self:ClearFocus(); Refresh() end)
    local okBtn = SmallBtn(body, "OK", 34, AcceptName)
    okBtn:SetPoint("LEFT", nameHost, "RIGHT", 6, 0)
    f.nameEb = nameEb
    y = y - 28

    -- Done (left out of Export; Hide done keeps it out of the list) and Skip
    -- (rejected as a background)
    f.doneCb = Check(L["DEV_WIN_ICONLAB_DONE"], 0, y, function(self)
        State(_idx).done = self:GetChecked() or nil
        Refresh()
    end)
    f.skip = Check(L["DEV_WIN_BGLAB_SKIP"], 196, y, function(self)
        State(_idx).skip = self:GetChecked() or nil
        Refresh()
    end)
    y = y - 28

    -- Fill mode, 3 x 3
    BNB.CreateSectionHeader(body, L["DEV_WIN_BGLAB_FILL"], y, cw)
    y = y - 20
    local mw = math.floor((cw - 12) / 3)
    f.modeBtns = {}
    f.modeRing = Ring(body)
    for n, m in ipairs(MODES) do
        local c, r = (n - 1) % 3, math.floor((n - 1) / 3)
        local b = SmallBtn(body, m.label, mw, function()
            State(_idx).mode = m.key; Refresh()
        end)
        b:SetPoint("TOPLEFT", body, "TOPLEFT", c * (mw + 6), y - r * 26)
        f.modeBtns[m.key] = b
    end
    y = y - 3 * 26 - 6

    -- Anchor, 3 x 3
    BNB.CreateSectionHeader(body, L["DEV_WIN_BGLAB_ANCHOR"], y, cw)
    y = y - 20
    f.anchorBtns = {}
    f.anchorRing = Ring(body)
    local aw = math.floor((cw - 12) / 3)
    for n, a in ipairs(ANCHORS) do
        local c, r = (n - 1) % 3, math.floor((n - 1) / 3)
        local b = SmallBtn(body, a[1], aw, function()
            State(_idx).anchor = a[1]; Refresh()
        end)
        b:SetPoint("TOPLEFT", body, "TOPLEFT", c * (aw + 6), y - r * 26)
        f.anchorBtns[a[1]] = b
    end
    y = y - 3 * 26 - 6

    -- Scale, and Brightness: the background's own, curated here; a
    -- player's Texture brightness adds to it (UI/BgLayer.lua)
    BNB.CreateSectionHeader(body, L["DEV_WIN_BGLAB_SCALE"], y, cw)
    y = y - 22
    local function ScaleStep(d)
        local st = State(_idx)
        st.scale = math.max(0.05, math.floor(((st.scale or 1) + d) * 100 + 0.5) / 100)
        Refresh()
    end
    local sMinus = SmallBtn(body, "-", 24, function() ScaleStep(IsShiftKeyDown() and -0.25 or -0.05) end)
    sMinus:SetPoint("TOPLEFT", body, "TOPLEFT", 0, y)
    local sVal = body:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    sVal:SetPoint("LEFT", sMinus, "RIGHT", 4, 0)
    sVal:SetWidth(42)
    f.sVal = sVal
    local sPlus = SmallBtn(body, "+", 24, function() ScaleStep(IsShiftKeyDown() and 0.25 or 0.05) end)
    sPlus:SetPoint("LEFT", sVal, "RIGHT", 4, 0)
    local s1 = SmallBtn(body, "1x", 32, function() State(_idx).scale = 1; Refresh() end)
    s1:SetPoint("LEFT", sPlus, "RIGHT", 6, 0)
    local s2 = SmallBtn(body, "0.5x", 40, function() State(_idx).scale = 0.5; Refresh() end)
    s2:SetPoint("LEFT", s1, "RIGHT", 4, 0)
    local function BrightStep(d)
        local st = State(_idx)
        local v = math.max(-1, math.min(1, math.floor(((st.bright or 0) + d) * 100 + 0.5) / 100))
        st.bright = (v ~= 0) and v or nil
        Refresh()
    end
    local bPlus = SmallBtn(body, "+", 24, function() BrightStep(IsShiftKeyDown() and 0.25 or 0.05) end)
    bPlus:SetPoint("TOPRIGHT", body, "TOPRIGHT", 0, y)
    local bVal = body:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    bVal:SetPoint("RIGHT", bPlus, "LEFT", -4, 0)
    bVal:SetWidth(44)
    f.bVal = bVal
    local bMinus = SmallBtn(body, "-", 24, function() BrightStep(IsShiftKeyDown() and -0.25 or -0.05) end)
    bMinus:SetPoint("RIGHT", bVal, "LEFT", -4, 0)
    for _, btn in ipairs({ bMinus, bPlus }) do
        btn:HookScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:AddLine(L["DEV_WIN_BGLAB_BRIGHT"], 1, 1, 1)
            GameTooltip:AddLine(L["DEV_WIN_BGLAB_BRIGHT_TIP"], 0.8, 0.8, 0.8, true)
            GameTooltip:Show()
        end)
        btn:HookScript("OnLeave", function() GameTooltip:Hide() end)
    end
    y = y - 28

    -- Native size override
    BNB.CreateSmallLabel(body, L["DEV_WIN_BGLAB_SIZE"], y, cw)
    y = y - 16
    local wBox = NumBox(body, 70, function(v)
        State(_idx).w = (v and v > 0) and v or nil; Refresh()
    end)
    wBox:SetPoint("TOPLEFT", body, "TOPLEFT", 0, y)
    local xLbl = body:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    xLbl:SetPoint("LEFT", wBox, "RIGHT", 6, 0); xLbl:SetText("x")
    local hBox = NumBox(body, 70, function(v)
        State(_idx).h = (v and v > 0) and v or nil; Refresh()
    end)
    hBox:SetPoint("LEFT", xLbl, "RIGHT", 6, 0)
    f.wBox, f.hBox = wBox, hBox
    y = y - 28

    -- Picture area: the part of the file that holds the art (Dukul 2026-09-27).
    -- Drawn on the sheet; these boxes are for exact numbers.
    BNB.CreateSmallLabel(body, L["DEV_WIN_BGLAB_CROP"], y, cw)
    y = y - 16
    f.cropBoxes = {}
    local last
    for n, field in ipairs({ "cx", "cy", "cw", "ch" }) do
        local box = NumBox(body, 54, function(v)
            if not v then return end   -- an empty box left alone sets nothing
            local x, yy, w, h = ToolBox()
            if not x then return end
            local vals = { x, yy, w, h }
            if n <= 2 and v >= 0 or v > 0 then vals[n] = v end
            SetBox(vals[1], vals[2], vals[3], vals[4])
            Refresh()
        end)
        if last then box:SetPoint("LEFT", last, "RIGHT", 6, 0)
        else box:SetPoint("TOPLEFT", body, "TOPLEFT", 0, y) end
        f.cropBoxes[field], last = box, box
    end
    local clearCrop = SmallBtn(body, L["DEV_WIN_BGLAB_CROP_ALL"], cw - 4 * 60, function()
        SetBox(nil); Refresh()
    end)
    clearCrop:SetPoint("LEFT", last, "RIGHT", 6, 0)
    K.TabChain({ wBox, hBox, f.cropBoxes.cx, f.cropBoxes.cy, f.cropBoxes.cw, f.cropBoxes.ch })
    y = y - 28

    -- Base colour and skip
    local baseBtn = SmallBtn(body, L["DEV_WIN_BGLAB_BASE"], 100, function()
        local st = State(_idx)
        local b = st.base or DEF_BASE
        local old = st.base
        BNB.OpenColorPicker(b[1], b[2], b[3], function(r, g, bl)
            st.base = { r, g, bl }; Refresh()
        end, function() st.base = old; Refresh() end)
    end)
    baseBtn:SetPoint("TOPLEFT", body, "TOPLEFT", 0, y)
    local sw = body:CreateTexture(nil, "OVERLAY")
    sw:SetSize(18, 18)
    sw:SetPoint("LEFT", baseBtn, "RIGHT", 6, 0)
    f.swatch = sw
    local baseReset = SmallBtn(body, L["DEV_WIN_BGLAB_RESET"], 54, function()
        State(_idx).base = nil; Refresh()
    end)
    baseReset:SetPoint("LEFT", sw, "RIGHT", 6, 0)
    f.sampleCb = Check(L["DEV_WIN_BGLAB_SAMPLE_CB"], 196, y + 2, function(self)
        Store().noSample = not self:GetChecked() or nil
        Refresh()
    end)
    y = y - 26

    -- Flip (ALL-187)
    f.flipH = Check(L["DEV_WIN_BGLAB_FLIP_H"], 0, y, function(self)
        State(_idx).flipH = self:GetChecked() or nil; Refresh()
    end)
    f.flipV = Check(L["DEV_WIN_BGLAB_FLIP_V"], 100, y, function(self)
        State(_idx).flipV = self:GetChecked() or nil; Refresh()
    end)
    y = y - 32

    -- Add: paste listfile lines, file IDs or atlas names, one per line
    BNB.CreateSectionHeader(body, L["DEV_WIN_BGLAB_ADD_HDR"], y, cw)
    y = y - 20
    local addHost = K.PlainBox(body, cw - 66, 44)
    addHost:SetPoint("TOPLEFT", body, "TOPLEFT", 0, y)
    addHost:SetClipsChildren(true)   -- a long paste stayed drawn below the box (E12)
    local addEb = addHost.eb
    addEb:SetMultiLine(true)
    addEb:SetMaxLetters(0)
    addEb:SetTextInsets(6, 6, 4, 4)
    local hint
    local function DoAdd()
        local added, bad, i = AddLines(addEb:GetText())
        hint:SetText(string.format(L["DEV_WIN_ICONLAB_ADDED"], added, bad))
        if added > 0 then addEb:SetText("") end
        addEb:ClearFocus()
        if i then Go(i); ProbeAllSizes() end
    end
    local addBtn = SmallBtn(body, L["DEV_WIN_BGLAB_ADD"], 60, DoAdd)
    addBtn:SetPoint("TOPLEFT", addHost, "TOPRIGHT", 6, 0)
    hint = body:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("TOPLEFT", addHost, "BOTTOMLEFT", 0, -3)
    hint:SetWidth(cw); hint:SetJustifyH("LEFT")
    hint:SetText(L["DEV_WIN_ICONLAB_ADD_HINT"])
    y = y - 44 - 22

    -- Try the current entry on every open sticky (runtime only, not saved)
    local tryBtn = SmallBtn(body, L["DEV_WIN_BGLAB_TRY"], cw, function()
        _trying = not _trying or nil
        if not _trying then BNB.Sticky.SetBgOverride(nil) end
        Refresh()
    end)
    tryBtn:SetPoint("TOPLEFT", body, "TOPLEFT", 0, y)
    f.tryBtn = tryBtn
    y = y - 26

    local bw = math.floor((cw - 12) / 3)
    local removeBtn = SmallBtn(body, L["DEV_WIN_BGLAB_REMOVE"], bw, function()
        RemoveCustom(_idx)
        Go(math.min(_idx, #LIST))
    end)
    removeBtn:SetPoint("TOPLEFT", body, "TOPLEFT", 0, y)
    f.removeBtn = removeBtn
    local sheetBtn = SmallBtn(body, L["DEV_WIN_ICONLAB_SHEET"], bw, function()
        local s = _sheet.frame
        if s:IsShown() then s:Hide() else s:Show() end
    end)
    sheetBtn:SetPoint("TOPLEFT", body, "TOPLEFT", bw + 6, y)
    local pvBtn = SmallBtn(body, L["DEV_WIN_ICONLAB_PREVIEW"], bw, function()
        if _pv:IsShown() then _pv:Hide() else _pv:Show() end
    end)
    pvBtn:SetPoint("TOPLEFT", body, "TOPLEFT", (bw + 6) * 2, y)
    return f
end

Refresh = function()
    if not _ctl then return end
    local e, st = LIST[_idx], State(_idx)
    local f = _ctl
    local sz = FileSize(e.id)
    local status = (sz == nil and "loading...") or (sz == false and "|cffff5555did not load|r")
        or string.format("%dx%d", sz[1], sz[2])
    local regs = Regions(e)
    local live = ""
    if e.atlas then
        live = K.ResolveAtlas(e.atlas) == e.id and "" or "  |cffff9900atlas not on this client|r"
    end
    f.info:SetText(string.format("%d / %d  |cffffd100%s|r\n%s\nfile %d  -  %s%s%s",
        _idx, #LIST, GROUPS[e.g].label, e.atlas and ("atlas " .. e.atlas) or e.path, e.id, status,
        regs and string.format("  -  %d regions", #regs) or "", live))
    pcall(function() f.dd:OverrideText((st.name and st.name ~= "") and st.name or (e.atlas or e.key)) end)
    if not (f.nameEb:HasFocus() or f.nameEb._pending) then f.nameEb:SetText(st.name or "") end
    PutRing(f.modeRing, f.modeBtns[st.mode] or f.modeBtns.tile)
    PutRing(f.anchorRing, f.anchorBtns[st.anchor] or f.anchorBtns.CENTER)
    f.sVal:SetText(string.format("%.2fx", st.scale or 1))
    f.bVal:SetText(string.format("%+d%%", math.floor((st.bright or 0) * 100 + 0.5)))
    local nw, nh = NativeSize(_idx)
    if not f.wBox.eb:HasFocus() then f.wBox.eb:SetText(nw and tostring(nw) or "") end
    if not f.hBox.eb:HasFocus() then f.hBox.eb:SetText(nh and tostring(nh) or "") end
    for field, box in pairs(f.cropBoxes) do
        if not box.eb:HasFocus() then box.eb:SetText(st[field] and tostring(st[field]) or "") end
    end
    local b = st.base or DEF_BASE
    f.swatch:SetColorTexture(b[1], b[2], b[3], 1)
    f.skip:SetChecked(st.skip == true)
    f.doneCb:SetChecked(st.done == true)
    f.flipH:SetChecked(st.flipH == true)
    f.flipV:SetChecked(st.flipV == true)
    f.hideOutCb:SetChecked(Store().hideOut == true)
    local showSample = not Store().noSample
    f.sampleCb:SetChecked(showSample)
    f.removeBtn:SetShown(e.g == "added")
    f.tryBtn:SetText(_trying and L["DEV_WIN_BGLAB_TRY_OFF"] or L["DEV_WIN_BGLAB_TRY"])
    if _trying then BNB.Sticky.SetBgOverride(LabDef(_idx)) end
    if _pv then
        if showSample then _pv.sample:Show() else _pv.sample:Hide() end
    end
    local sh = _sheet and _sheet.frame
    if sh then
        local a = Store().aspect
        for _, o in ipairs(ASPECTS) do
            if o[1] == a then sh.aspBtn:SetText(o[2]) end
        end
        sh.matchBtn:SetEnabled(AspectRatio() ~= nil)
        _sheet.Layout()
    end
    LayoutPreview()
end

function BNB.OpenBackgroundLab()
    if not BigNoteBoxDB then return end
    LoadCustom()
    if not _ctl then BuildControl() end
    if not _sheet then BuildSheet() end
    _pv = _pv or BuildPreview()
    local sh = _sheet.frame
    if not sh:GetPoint() then sh:SetPoint("RIGHT", _ctl, "LEFT", -12, 0) end
    if not _pv:GetPoint() then _pv:SetPoint("TOPLEFT", _ctl, "TOPRIGHT", 12, 0) end
    _ctl:Show(); _ctl:Raise()
    sh:Show()
    _pv:Show()
    Go(Store().idx or _idx)
    ProbeAllSizes()
end

end

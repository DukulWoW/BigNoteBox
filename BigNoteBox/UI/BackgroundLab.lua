-- BigNoteBox UI/BackgroundLab.lua
-- Developer Tools > Background Lab (/bnb bglab, debug mode). ALL-110.
-- Previews the game's own background textures in a resizable, sticky-like
-- window so each can be given a name, a fill mode and an anchor before it is
-- added to the sticky background list. Export hands back one Lua line per
-- entry. Work in progress is kept in BigNoteBoxDB.devBgLab across reloads.
--
-- Fill modes and their maths live in UI/BgLayer.lua, shared with the
-- sticky notes, so this preview is what a sticky shows. "Try on stickies"
-- puts the current entry on every open sticky (not saved).
-- Mode and anchor names are dev-only and not translated.

local BNB = BigNoteBox
if not BNB then return end
local L = BNB.L

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
local C_W, C_H = 320, 736
local C_PAD    = 16

local _ctl, _pv
local _idx = 1
local _trying   -- "Try on stickies" is on

-- ── Saved state ──────────────────────────────────────────────────────────────
local function Store()
    BigNoteBoxDB.devBgLab = BigNoteBoxDB.devBgLab or { e = {} }
    return BigNoteBoxDB.devBgLab
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

-- ── Native size probe ────────────────────────────────────────────────────────
-- A texture with one anchor and no size of its own takes the file's size once
-- it has loaded. Polled for up to 3 s; a manual W/H in the panel wins.
local _probe
local _sizes = {}   -- [id] = { w, h } or false (did not load)

local function ProbeSize(e, onDone)
    if _sizes[e.id] ~= nil then onDone(); return end
    if not _probe then
        _probe = _ctl:CreateTexture(nil, "BACKGROUND")
        _probe:SetAlpha(0)
        _probe:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", -5000, 0)
    end
    local ok = pcall(function() _probe:SetTexture(e.id) end)
    _probe._id = e.id
    local tries = 0
    local function Poll()
        -- Moved on before this one loaded: drop it, it re-probes when revisited
        if _probe._id ~= e.id then return end
        tries = tries + 1
        local w, h = _probe:GetSize()
        if ok and w and w > 1 and h and h > 1 then
            _sizes[e.id] = { math.floor(w + 0.5), math.floor(h + 0.5) }
            onDone()
        elseif tries >= 30 then
            _sizes[e.id] = false
            onDone()
        else
            C_Timer.After(0.1, Poll)
        end
    end
    Poll()
end

local function NativeSize(i)
    local st, sz = State(i), _sizes[LIST[i].id]
    local w = st.w or (sz and sz[1])
    local h = st.h or (sz and sz[2])
    return w, h
end

-- Picture area (crop, UI/BgLayer.lua): x / y / w / h in file pixels, set
-- when the art fills only part of its file. nil until W and H are both set.
local function Crop(st)
    if st.cw and st.ch then return { st.cx or 0, st.cy or 0, st.cw, st.ch } end
end

-- The current entry as a BgLayer def (UI/BgLayer.lua)
local function LabDef(i)
    local st = State(i)
    local nw, nh = NativeSize(i)
    return { file = LIST[i].id, mode = st.mode, anchor = st.anchor, scale = st.scale or 1, w = nw, h = nh,
             crop = Crop(st) }
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
        tex:Hide()
        _pv.warn:SetText(_sizes[e.id] == false and "Texture did not load on this client"
            or "Native size unknown: type W and H in the panel")
        _pv.warn:Show()
        return
    end
    _pv.warn:Hide()

    BL.Draw(tex, area, LabDef(_idx))
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

    local grip = CreateFrame("Button", nil, f)
    grip:SetSize(16, 16)
    grip:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
    grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    grip:SetScript("OnMouseDown", function(_, btn)
        if btn == "LeftButton" then BNB.StartGripSizing(f) end
    end)
    grip:SetScript("OnMouseUp", function()
        BNB.StopGripSizing(f)
        local s = Store(); s.pw, s.ph = f:GetSize()
    end)

    f:SetScript("OnSizeChanged", LayoutPreview)
    f:HookScript("OnShow", LayoutPreview)
    local s = Store()
    if s.pw and s.ph then f:SetSize(s.pw, s.ph) end
    f:Hide()
    return f
end

-- ── Export ───────────────────────────────────────────────────────────────────
local function Q(s) return string.format("%q", s) end

local function ExportText()
    local out, n, skipped = {}, 0, 0
    for i, e in ipairs(LIST) do
        local st = Store().e[e.key]
        if st then
            n = n + 1
            local nw, nh = NativeSize(i)
            local b = st.base
            local line = string.format(
                "{ key = %s, name = %s, file = %d, path = %s, w = %s, h = %s, mode = %s, anchor = %s, scale = %s%s%s%s%s%s },",
                Q(e.key), Q(st.name or ""), e.id, Q(e.path), tostring(nw or "nil"), tostring(nh or "nil"),
                Q(st.mode), Q(st.anchor), tostring(st.scale or 1),
                e.atlas and (", atlas = " .. Q(e.atlas)) or "",
                Crop(st) and string.format(", crop = { %d, %d, %d, %d }", unpack(Crop(st))) or "",
                b and string.format(", base = { %.2f, %.2f, %.2f }", b[1], b[2], b[3]) or "",
                _sizes[e.id] == false and ", loaded = false" or "",
                st.skip and ", skip = true" or "")
            if st.skip then skipped = skipped + 1 end
            out[#out + 1] = line
        end
    end
    table.insert(out, 1, string.format("-- Background Lab export: %d of %d looked at, %d skipped, client %s",
        n, #LIST, skipped, BNB.IsForever and "Forever" or "Retail"))
    return table.concat(out, "\n")
end

-- ── Control window ───────────────────────────────────────────────────────────
local Refresh

local function SmallBtn(parent, text, w, onClick)
    local b = BNB.CreateButton(nil, parent, text, w, 20)
    b:SetScript("OnClick", onClick)
    return b
end

-- Gold ring shown around the selected button of a group
local function Ring(parent)
    local r = BNB.CreateBackdropFrame("Frame", nil, parent)
    r:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 2 })
    r:SetBackdropBorderColor(1, 0.82, 0, 1)
    r:EnableMouse(false)
    return r
end
local function PutRing(r, btn)
    r:ClearAllPoints()
    r:SetPoint("TOPLEFT", btn, "TOPLEFT", -2, 2)
    r:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 2, -2)
    r:SetFrameLevel(btn:GetFrameLevel() + 2)
    r:Show()
end

local function NumBox(parent, w, onSet)
    local host = BNB.CreateBackdropFrame("Frame", nil, parent)
    host:SetSize(w, 20)
    BNB.SetBackdropDark(host)
    local eb = CreateFrame("EditBox", nil, host)
    eb:SetAllPoints()
    eb:SetTextInsets(6, 6, 0, 0)
    eb:SetFontObject("GameFontHighlightSmall")
    eb:SetAutoFocus(false)
    eb:SetScript("OnEnterPressed", function(self) onSet(tonumber(self:GetText())); self:ClearFocus() end)
    eb:SetScript("OnEscapePressed", function(self) self:ClearFocus(); Refresh() end)
    eb:SetScript("OnEditFocusLost", function(self) onSet(tonumber(self:GetText())) end)
    host.eb = eb
    return host
end

-- ── Textures added in game (file ID, path optional, or an atlas name) ───────
-- Kept in devBgLab.custom as { id, path, atlas } and appended to LIST as
-- group "added", so new finds from wow.export can be tried without a code
-- change. An atlas entry is its file plus a Picture area taken from the
-- atlas coordinates (ALL-120); one file can hold several atlases, so an entry
-- is one file + atlas pair.
local function CustomKey(id, path, atlas)
    if atlas and atlas ~= "" then return atlas end
    local base = path ~= "" and path:match("([^/]+)$") or nil
    base = base and base:gsub("%.[^.]+$", "") or nil
    return (base and base ~= "") and base or ("file" .. id)
end

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

-- A usable file ID: a whole, finite, positive number
local function ValidID(id)
    return type(id) == "number" and id > 0 and id < 2^53 and id == math.floor(id)
end

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

-- An atlas name -> its file ID and atlas info, or nil. GetAtlasInfo gives the
-- file as an ID; a client that gives only a path goes through GetFileIDFromPath.
local function ResolveAtlas(name)
    if name == "" or not (C_Texture and C_Texture.GetAtlasInfo) then return nil end
    local ok, info = pcall(C_Texture.GetAtlasInfo, name)
    if not ok or type(info) ~= "table" then return nil end
    local id = info.file
    if type(id) ~= "number" and type(info.filename) == "string" and GetFileIDFromPath then
        local ok2, fid = pcall(GetFileIDFromPath, info.filename)
        if ok2 then id = fid end
    end
    if ValidID(id) then return id, info end
end

-- Fills an atlas entry's Picture area from the atlas coordinates x the file's
-- size, once the size is known, and only while no Picture area is set (a
-- hand-tuned one survives later visits)
local function ApplyAtlasCrop(i)
    local e = LIST[i]
    if not (e and e.atlas) then return end
    local st, sz = State(i), _sizes[e.id]
    if st.cw or not sz then return end
    local _, info = ResolveAtlas(e.atlas)
    if not info then return end
    local W, H = sz[1], sz[2]
    local function R(v) return math.floor(v + 0.5) end
    st.cx = R(info.leftTexCoord * W)
    st.cy = R(info.topTexCoord * H)
    st.cw = R((info.rightTexCoord - info.leftTexCoord) * W)
    st.ch = R((info.bottomTexCoord - info.topTexCoord) * H)
    if st.cw <= 0 or st.ch <= 0 then st.cx, st.cy, st.cw, st.ch = nil, nil, nil, nil end
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

local function Go(i)
    _idx = ((i - 1) % #LIST) + 1
    Store().idx = _idx
    State(_idx)
    Refresh()
    ProbeSize(LIST[_idx], function()
        if LIST[_idx] then ApplyAtlasCrop(_idx); Refresh() end
    end)
end

local function BuildControl()
    local f, exportBtn, closeBtn = BNB.CreateToolWindow({
        name = "BigNoteBoxBgLab", w = C_W, h = C_H,
        title = L["DEV_WIN_BGLAB_TITLE"], pad = C_PAD, cw = C_W - C_PAD * 2, footH = 40,
        btn1 = L["DEV_WIN_BGLAB_EXPORT"], btn2 = L["CLOSE"],
        onClose = function() _ctl:Hide() end,
        toplevel = true, escClose = true,
    })
    f:SetPoint("CENTER", UIParent, "CENTER", 220, 0)
    closeBtn:SetScript("OnClick", function() f:Hide() end)
    exportBtn:SetScript("OnClick", function() BNB.ShowClipboardHint(ExportText(), f, true) end)
    f:HookScript("OnHide", function() if _pv then _pv:Hide() end end)
    _ctl = f

    local cw = C_W - C_PAD * 2
    local body = CreateFrame("Frame", nil, f)
    body:SetPoint("TOPLEFT", f, "TOPLEFT", C_PAD, -34)
    body:SetSize(cw, C_H - 80)
    local y = 0

    -- Navigation: < jump list >
    local prev = SmallBtn(body, "<", 30, function() Go(_idx - 1) end)
    prev:SetPoint("TOPLEFT", body, "TOPLEFT", 0, y)
    local nextB = SmallBtn(body, ">", 30, function() Go(_idx + 1) end)
    nextB:SetPoint("TOPRIGHT", body, "TOPRIGHT", 0, y)
    local dd = CreateFrame("DropdownButton", nil, body, "WowStyle1DropdownTemplate")
    dd:SetPoint("LEFT", prev, "RIGHT", 6, 0)
    dd:SetPoint("RIGHT", nextB, "LEFT", -6, 0)
    dd:SetupMenu(function(_, root)
        pcall(function() root:SetScrollMode(500) end)
        for _, gk in ipairs(GROUP_ORDER) do
            root:CreateTitle(GROUPS[gk].label)
            for i, e in ipairs(LIST) do
                if e.g == gk then
                    local st = Store().e[e.key]
                    local lbl = (st and st.name and st.name ~= "") and st.name or e.key
                    if st and st.skip then lbl = "|cff888888" .. lbl .. " (skip)|r"
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

    -- Name
    BNB.CreateSmallLabel(body, L["DEV_WIN_BGLAB_NAME"], y, cw)
    y = y - 14
    local nameHost = BNB.CreateBackdropFrame("Frame", nil, body)
    nameHost:SetSize(cw, 22)
    nameHost:SetPoint("TOPLEFT", body, "TOPLEFT", 0, y)
    BNB.SetBackdropDark(nameHost)
    local nameEb = CreateFrame("EditBox", nil, nameHost)
    nameEb:SetAllPoints()
    nameEb:SetTextInsets(6, 6, 0, 0)
    nameEb:SetFontObject("GameFontHighlight")
    nameEb:SetAutoFocus(false)
    nameEb:SetMaxLetters(40)
    nameEb:SetScript("OnTextChanged", function(self, user)
        if not user then return end
        State(_idx).name = self:GetText()
        LayoutPreview()
    end)
    nameEb:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    nameEb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    nameEb:SetScript("OnTabPressed", function(self) self:ClearFocus(); Go(_idx + 1) end)
    f.nameEb = nameEb
    y = y - 32

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
    y = y - 3 * 26 - 8

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
    y = y - 3 * 26 - 8

    -- Scale
    BNB.CreateSectionHeader(body, L["DEV_WIN_BGLAB_SCALE"], y, cw)
    y = y - 22
    local function Step(d)
        local st = State(_idx)
        st.scale = math.max(0.05, math.floor(((st.scale or 1) + d) * 100 + 0.5) / 100)
        Refresh()
    end
    local sMinus = SmallBtn(body, "-", 30, function() Step(IsShiftKeyDown() and -0.25 or -0.05) end)
    sMinus:SetPoint("TOPLEFT", body, "TOPLEFT", 0, y)
    local sVal = body:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    sVal:SetPoint("LEFT", sMinus, "RIGHT", 8, 0)
    sVal:SetWidth(50)
    f.sVal = sVal
    local sPlus = SmallBtn(body, "+", 30, function() Step(IsShiftKeyDown() and 0.25 or 0.05) end)
    sPlus:SetPoint("LEFT", sVal, "RIGHT", 8, 0)
    local s1 = SmallBtn(body, "1x", 40, function() State(_idx).scale = 1; Refresh() end)
    s1:SetPoint("LEFT", sPlus, "RIGHT", 8, 0)
    local s2 = SmallBtn(body, "0.5x", 44, function() State(_idx).scale = 0.5; Refresh() end)
    s2:SetPoint("LEFT", s1, "RIGHT", 6, 0)
    y = y - 30

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
    y = y - 30

    -- Picture area: the part of the file that holds the art (Dukul 2026-09-27)
    BNB.CreateSmallLabel(body, L["DEV_WIN_BGLAB_CROP"], y, cw)
    y = y - 16
    f.cropBoxes = {}
    local last
    for n, field in ipairs({ "cx", "cy", "cw", "ch" }) do
        local box = NumBox(body, 54, function(v)
            local st = State(_idx)
            if n <= 2 then st[field] = (v and v >= 0) and v or nil
            else st[field] = (v and v > 0) and v or nil end
            Refresh()
        end)
        if last then box:SetPoint("LEFT", last, "RIGHT", 6, 0)
        else box:SetPoint("TOPLEFT", body, "TOPLEFT", 0, y) end
        f.cropBoxes[field], last = box, box
    end
    y = y - 30

    -- Base colour, skip, sample text
    local baseBtn = SmallBtn(body, L["DEV_WIN_BGLAB_BASE"], 110, function()
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
    local baseReset = SmallBtn(body, L["DEV_WIN_BGLAB_RESET"], 60, function()
        State(_idx).base = nil; Refresh()
    end)
    baseReset:SetPoint("LEFT", sw, "RIGHT", 6, 0)
    y = y - 28

    local skip = CreateFrame("CheckButton", nil, body, "UICheckButtonTemplate")
    skip:SetSize(24, 24)
    skip:SetPoint("TOPLEFT", body, "TOPLEFT", -4, y)
    skip.text = skip.text or skip:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    skip.text:SetPoint("LEFT", skip, "RIGHT", 2, 0)
    skip.text:SetFontObject("GameFontHighlightSmall")
    skip.text:SetText(L["DEV_WIN_BGLAB_SKIP"])
    skip:SetScript("OnClick", function(self) State(_idx).skip = self:GetChecked() or nil end)
    f.skip = skip

    local sample = CreateFrame("CheckButton", nil, body, "UICheckButtonTemplate")
    sample:SetSize(24, 24)
    sample:SetPoint("TOPLEFT", body, "TOPLEFT", cw / 2, y)
    sample.text = sample.text or sample:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    sample.text:SetPoint("LEFT", sample, "RIGHT", 2, 0)
    sample.text:SetFontObject("GameFontHighlightSmall")
    sample.text:SetText(L["DEV_WIN_BGLAB_SAMPLE_CB"])
    sample:SetScript("OnClick", function(self)
        Store().noSample = not self:GetChecked() or nil
        Refresh()
    end)
    f.sampleCb = sample
    y = y - 34

    -- Add a texture by file ID (path optional, only used for the key and export)
    BNB.CreateSectionHeader(body, L["DEV_WIN_BGLAB_ADD_HDR"], y, cw)
    y = y - 20
    local function PlainBox(w)
        local host = BNB.CreateBackdropFrame("Frame", nil, body)
        host:SetSize(w, 20)
        BNB.SetBackdropDark(host)
        local eb = CreateFrame("EditBox", nil, host)
        eb:SetAllPoints()
        eb:SetTextInsets(6, 6, 0, 0)
        eb:SetFontObject("GameFontHighlightSmall")
        eb:SetAutoFocus(false)
        eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
        host.eb = eb
        return host
    end
    local idBox = PlainBox(80)
    idBox:SetPoint("TOPLEFT", body, "TOPLEFT", 0, y)
    idBox.eb:SetNumeric(true)
    local pathBox = PlainBox(cw - 80 - 60 - 12)
    pathBox:SetPoint("LEFT", idBox, "RIGHT", 6, 0)
    local hint
    -- The second box takes a path or an atlas name (ALL-120). An atlas brings
    -- its own file ID, so the ID box may stay empty.
    local function DoAdd()
        local id = tonumber(idBox.eb:GetText())
        local text = pathBox.eb:GetText():gsub("^%s+", ""):gsub("%s+$", "")
        local atlasID = not text:find("[/\\]") and ResolveAtlas(text)
        local i
        if atlasID then
            i = AddCustom(atlasID, "", text)
        elseif not id or id <= 0 then
            if text ~= "" then hint:SetText(L["DEV_WIN_BGLAB_ATLAS_NONE"]) end
            return
        else
            i = AddCustom(id, text)
        end
        hint:SetText(L["DEV_WIN_BGLAB_ADD_HINT"])
        idBox.eb:SetText(""); pathBox.eb:SetText("")
        idBox.eb:ClearFocus(); pathBox.eb:ClearFocus()
        if i then Go(i) end
    end
    idBox.eb:SetScript("OnEnterPressed", DoAdd)
    idBox.eb:SetScript("OnTabPressed", function() pathBox.eb:SetFocus() end)
    pathBox.eb:SetScript("OnEnterPressed", DoAdd)
    local addBtn = SmallBtn(body, L["DEV_WIN_BGLAB_ADD"], 60, DoAdd)
    addBtn:SetPoint("LEFT", pathBox, "RIGHT", 6, 0)
    hint = body:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("TOPLEFT", idBox, "BOTTOMLEFT", 0, -3)
    hint:SetText(L["DEV_WIN_BGLAB_ADD_HINT"])
    local removeBtn = SmallBtn(body, L["DEV_WIN_BGLAB_REMOVE"], 110, function()
        RemoveCustom(_idx)
        Go(math.min(_idx, #LIST))
    end)
    removeBtn:SetPoint("TOPRIGHT", body, "TOPRIGHT", 0, y - 24)
    f.removeBtn = removeBtn
    y = y - 56

    -- Try the current entry on every open sticky (runtime only, not saved)
    local tryBtn = SmallBtn(body, L["DEV_WIN_BGLAB_TRY"], cw, function()
        _trying = not _trying or nil
        if not _trying then BNB.Sticky.SetBgOverride(nil) end
        Refresh()
    end)
    tryBtn:SetPoint("TOPLEFT", body, "TOPLEFT", 0, y)
    f.tryBtn = tryBtn
    return f
end

Refresh = function()
    if not _ctl then return end
    local e, st = LIST[_idx], State(_idx)
    local f = _ctl
    local sz = _sizes[e.id]
    local nw, nh = NativeSize(_idx)
    local status = (sz == nil and "loading...") or (sz == false and "|cffff5555did not load|r")
        or string.format("%dx%d", sz[1], sz[2])
    f.info:SetText(string.format("%d / %d  |cffffd100%s|r\n%s\nfile %d  -  %s",
        _idx, #LIST, GROUPS[e.g].label, e.atlas and ("atlas " .. e.atlas) or e.path, e.id, status))
    pcall(function() f.dd:OverrideText((st.name and st.name ~= "") and st.name or e.key) end)
    if not f.nameEb:HasFocus() then f.nameEb:SetText(st.name or "") end
    PutRing(f.modeRing, f.modeBtns[st.mode] or f.modeBtns.tile)
    PutRing(f.anchorRing, f.anchorBtns[st.anchor] or f.anchorBtns.CENTER)
    f.sVal:SetText(string.format("%.2fx", st.scale or 1))
    if not f.wBox.eb:HasFocus() then f.wBox.eb:SetText(nw and tostring(nw) or "") end
    if not f.hBox.eb:HasFocus() then f.hBox.eb:SetText(nh and tostring(nh) or "") end
    for field, box in pairs(f.cropBoxes) do
        if not box.eb:HasFocus() then box.eb:SetText(st[field] and tostring(st[field]) or "") end
    end
    local b = st.base or DEF_BASE
    f.swatch:SetColorTexture(b[1], b[2], b[3], 1)
    f.skip:SetChecked(st.skip == true)
    local showSample = not Store().noSample
    f.sampleCb:SetChecked(showSample)
    f.removeBtn:SetShown(e.g == "added")
    f.tryBtn:SetText(_trying and L["DEV_WIN_BGLAB_TRY_OFF"] or L["DEV_WIN_BGLAB_TRY"])
    if _trying then BNB.Sticky.SetBgOverride(LabDef(_idx)) end
    if _pv then
        if showSample then _pv.sample:Show() else _pv.sample:Hide() end
    end
    LayoutPreview()
end

function BNB.OpenBackgroundLab()
    if not BigNoteBoxDB then return end
    LoadCustom()
    if not _ctl then BuildControl() end
    _pv = _pv or BuildPreview()
    if not _pv:GetPoint() then _pv:SetPoint("RIGHT", _ctl, "LEFT", -12, 0) end
    _ctl:Show(); _ctl:Raise()
    _pv:Show()
    Go(Store().idx or _idx)
end

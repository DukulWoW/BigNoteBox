-- BigNoteBox_Dev Labs/ToastLab.lua
-- Developer Tools > Toast Lab (/bnb toastlab, debug mode). ALL-376 S2.
-- Makes toast styles (UI/ToastStyles.lua) from the game's toast art: pick an
-- entry, set the toast size, then drag the icon, title, text line, timer bar
-- and "+N more" into place on the preview. Export hands back one Lua entry
-- per named style for TS STYLES. Work in progress is kept in
-- BNB.LabDB().devToastLab across reloads.
-- Four windows:
--   control - the entry, name, Done / Skip, look, size, the selected part's
--             numbers (a text's font and size), Export
--   stack   - left of the control: four made-up note toasts stacked as in
--             game (the player's Toast size, the lab's own grow direction),
--             with random icons, icon frames, title colours, places and
--             tl;dr lines (Random); Fire plays them in as they arrive; Gap
--             (or the wheel) sets the style's space between toasts
--   preview - the toast at 1x / 2x / 3x, drawn by BNB.ToastStyles.Apply (what
--             a toast shows); drag a part to move it, its right or bottom
--             edge to size it; arrows nudge the selected part 1 px (Shift 10,
--             Ctrl sizes it)
--   sheet   - the file with the art area (Labs/LabSheet.lua), for art
--             without an atlas or a different crop; a click on an atlas
--             region adds that region as an entry
-- Both previews take the sheet's backgrounds (Bg). Done = finished, left out
-- of Export; Skip = rejected. A style's icon Frame / Border is the default:
-- a note with its own icon frame draws that instead (the stack shows both).
-- "Try on toasts" draws every toast and the anchor in the current entry
-- (BNB.ToastStyles.SetOverride) and fires the Test toasts; not saved.
-- Dev tools only; nothing here is translated.

-- Queued for BigNoteBox's Core/DevTools.lua, which runs it once BigNoteBox
-- has loaded (this addon loads first, ARCH-04). The body is not indented.
BigNoteBoxDevLabs = BigNoteBoxDevLabs or {}
BigNoteBoxDevLabs[#BigNoteBoxDevLabs + 1] = function()

local BNB = BigNoteBox
if not BNB then return end
local L  = BNB.L
local K  = BNB._LabKit
local TS = BNB.ToastStyles
if not (K and TS and K.NewSheet) then return end

local function R(v) return math.floor(v + 0.5) end

-- ── The candidates (Dukul, inbox 2026-10-01, ALL-160) ───────────────────────
local GROUPS = {
    built = "Built-in styles",
    atlas = "Game toasts (atlas)",
    file  = "Game files (crop on the sheet)",
    added = "Added from the sheet",
}
local GROUP_ORDER = { "built", "atlas", "file", "added" }

local SEED = {
    { g = "atlas", id = 1005293, path = "interface/lootframe/loottoastatlas", atlas = "loottoast-dragonriding" },
    { g = "atlas", id = 1005293, path = "interface/lootframe/loottoastatlas", atlas = "LootToast-Azerite" },
    { g = "atlas", id = 1005293, path = "interface/lootframe/loottoastatlas", atlas = "loottoast-nzoth" },
    { g = "atlas", id = 1005293, path = "interface/lootframe/loottoastatlas", atlas = "shop-toast" },
    { g = "atlas", id = 1005293, path = "interface/lootframe/loottoastatlas", atlas = "loottoast-oribos" },
    { g = "atlas", id = 1005293, path = "interface/lootframe/loottoastatlas", atlas = "loottoast-camp" },
    { g = "atlas", id = 1005293, path = "interface/lootframe/loottoastatlas", atlas = "loottoast-glow" },
    { g = "atlas", id = 1372870, path = "interface/lootframe/legendarytoast", atlas = "LegendaryToast-background" },
    { g = "atlas", id = 1536706, path = "interface/lootframe/pvpratedloottoast", atlas = "pvprated-loottoast-bg-horde" },
    { g = "atlas", id = 1536706, path = "interface/lootframe/pvpratedloottoast", atlas = "pvprated-loottoast-bg-alliance" },
    { g = "atlas", id = 1603845, path = "interface/lootframe/mounttoast", atlas = "MountToast-background" },
    { g = "atlas", id = 1603846, path = "interface/lootframe/pettoast", atlas = "PetToast-background" },
    { g = "atlas", id = 4235929, path = "interface/lootframe/cosmetictoast", atlas = "cosmetictoast-background" },
    { g = "atlas", id = 952639,  path = "interface/garrison/garrisontoast", atlas = "Garr_MissionToast" },
    { g = "atlas", id = 952639,  path = "interface/garrison/garrisontoast", atlas = "Garr_Toast" },
    { g = "atlas", id = 952639,  path = "interface/garrison/garrisontoast", atlas = "ShipMission_Toast" },
    { g = "atlas", id = 952639,  path = "interface/garrison/garrisontoast", atlas = "Garr_MissionToast-Blank" },
    { g = "atlas", id = 1064224, path = "interface/garrison/garrisoncachetoast", atlas = "CacheToast" },
    { g = "atlas", id = 1260227, path = "interface/transmogrify/transmogtoast", atlas = "transmog-toast-bg" },
    { g = "atlas", id = 1337565, path = "interface/lootframe/recipetoast", atlas = "recipetoast-bg" },
    { g = "atlas", id = 904010,  path = "interface/questframe/questmaplogatlas", atlas = "campaign_alliance" },
    { g = "atlas", id = 904010,  path = "interface/questframe/questmaplogatlas", atlas = "campaign_horde" },
    { g = "atlas", id = 904010,  path = "interface/questframe/questmaplogatlas", atlas = "storyheader-bg" },
    { g = "atlas", id = 921230,  path = "interface/talentframe/talentframeatlas", atlas = "Talent-Selection-Legendary" },
    { g = "atlas", id = 921230,  path = "interface/talentframe/talentframeatlas", atlas = "Talent-Selection" },
    { g = "atlas", id = 921230,  path = "interface/talentframe/talentframeatlas", atlas = "pvptalents-list-background-mouseover" },
    { g = "atlas", id = 921230,  path = "interface/talentframe/talentframeatlas", atlas = "pvptalents-list-background-selected" },
    { g = "atlas", id = 7117987, path = "interface/framegeneral/uiframedelvesnotificationframe2x", atlas = "ui-frame-delves-notification-frame-2x" },
    { g = "atlas", id = 1111217, path = "interface/questframe/talkingheads", atlas = "talkingheads-alliance-textbackground" },
    { g = "atlas", id = 1111217, path = "interface/questframe/talkingheads", atlas = "talkingheads-horde-textbackground" },
    { g = "atlas", id = 1111217, path = "interface/questframe/talkingheads", atlas = "talkingheads-neutral-textbackground" },
    { g = "atlas", id = 1111217, path = "interface/questframe/talkingheads", atlas = "talkingheads-textbackground-housing" },
    { g = "atlas", id = 1111217, path = "interface/questframe/talkingheads", atlas = "talkingheads-textbackground" },
    { g = "atlas", id = 1958313, path = "interface/guildframe/communitiesaddchat", atlas = "communities-chat-body-remove" },
    { g = "atlas", id = 1958313, path = "interface/guildframe/communitiesaddchat", atlas = "communities-chat-body-add" },
    { g = "atlas", id = 1981967, path = "interface/guildframe/communities", atlas = "communities-nav-button-green-normal" },
    { g = "atlas", id = 1981967, path = "interface/guildframe/communities", atlas = "communities-nav-button-green-pressed" },
    { g = "atlas", id = 2123218, path = "interface/pvpframe/pvpqueue", atlas = "pvpqueue-button-highlight" },
    { g = "atlas", id = 2123218, path = "interface/pvpframe/pvpqueue", atlas = "pvpqueue-button-selected" },
    { g = "atlas", id = 3884129, path = "interface/lfgframe/lfgdungeontoast", atlas = "ui-lfg-dungeontoast" },
    { g = "atlas", id = 7486942, path = "interface/journeys/journeysframe2x", atlas = "ui-journeys-delve-companion-button-x2" },
    -- Whole files: crop on the sheet, or click one of their atlas regions
    { g = "file", id = 4635671, path = "interface/questframe/questlogcampaignheadersdragonflight" },
    { g = "file", id = 3448505, path = "interface/questframe/questlogcampaignheaders" },
    { g = "file", id = 897128,  path = "interface/archeology/archeologytoast" },
    { g = "file", id = 130964,  path = "interface/classtrainerframe/ui-classtrainer-detailheaderleft" },
    { g = "file", id = 131127,  path = "interface/friendsframe/ui-friendsframe-buttonspatch" },
    { g = "file", id = 136825,  path = "interface/raidframe/ui-readycheckframe" },
    { g = "file", id = 365781,  path = "interface/auctionframe/ui-auctionframe-itemslot" },
    { g = "file", id = 516664,  path = "interface/guildframe/guildchallenges" },
    { g = "file", id = 516766,  path = "interface/helpframe/helpbuttons" },
    { g = "file", id = 517165,  path = "interface/lfgframe/ui-lfg-bluebg" },
    { g = "file", id = 575645,  path = "interface/lfgframe/lfr-texture" },
    { g = "file", id = 925997,  path = "interface/friendsframe/raf_textures" },
    { g = "file", id = 446202,  path = "interface/guildframe/guildachievements" },
    { g = "file", id = 462333,  path = "interface/unitpowerbaralt/chogall_horizontal_frame" },
    { g = "file", id = 130650,  path = "interface/achievementframe/ui-achievement-alert-background" },
    { g = "file", id = 985877,  path = "interface/lfgframe/groupfinder" },
}

-- ── Saved state ──────────────────────────────────────────────────────────────
local function Store()
    local db = BNB.LabDB()
    db.devToastLab = db.devToastLab or { e = {}, added = {} }
    local s = db.devToastLab
    s.e, s.added = s.e or {}, s.added or {}
    return s
end

local LIST, _idx = {}, 1
local _ctl, _pv, _sheet, _st
local _sel = "icon"       -- the part the tools act on
local Refresh             -- forward

-- A lab entry that has been pasted into STYLES shares its key with the
-- style: it is listed once, as the entry (atlas / file for the sheet), and
-- carries the style so a fresh lab starts from the shipped numbers
local function BuildList()
    LIST = {}
    local styleOf, entries = {}, {}
    for _, def in ipairs(TS.STYLES) do
        if not def.faction then styleOf[def.key] = def end
    end
    for _, e in ipairs(SEED) do
        e.key = e.key or K.EntryKey(e.id, e.path, e.atlas)
        entries[#entries + 1] = e
    end
    for _, a in ipairs(Store().added) do
        entries[#entries + 1] = { g = "added", id = a.id, path = a.path, atlas = a.atlas,
                                  key = K.EntryKey(a.id, a.path, a.atlas) }
    end
    local taken = {}
    for _, e in ipairs(entries) do
        e.style = styleOf[e.key]
        if e.style then taken[e.key] = true end
    end
    for _, def in ipairs(TS.STYLES) do
        if not def.faction and not taken[def.key] then
            LIST[#LIST + 1] = { g = "built", key = def.key, style = def }
        end
    end
    for _, e in ipairs(entries) do LIST[#LIST + 1] = e end
end

local function AtlasSize(name)
    local ok, info = pcall(C_Texture.GetAtlasInfo, name)
    if ok and info and info.width and info.width > 0 then return info.width, info.height end
end

local function AtlasHere(name) return AtlasSize(name) ~= nil end

-- The layout every new entry starts from: Dukul's Dragon Riding toast
-- (2026-10-07), so working through the list starts close to done
local DEFAULT_LAYOUT = {
    w = 281, h = 115,
    icon  = { x = 26, y = 36, size = 48, shape = "square" },
    title = { x = 85, y = 31, w = 174, scale = 1 },
    text  = { x = 86, y = 54, w = 167, scale = 1 },
    line2 = { x = 86, y = 71, w = 167, scale = 1 },
    bar   = { x = 20, y = 89, w = 240, h = 2 },
    more  = { x = 265, y = 100 },
}
local function DefaultLayout() return CopyTable(DEFAULT_LAYOUT) end

-- The old first layout, worked out from the art size: only used to find
-- entries that were opened but never changed, which then take the default
local function StartLayout(w, h)
    local isz = math.max(16, math.min(48, h - 16))
    local ix  = math.max(8, R(h * 0.15))
    local tx  = ix + isz + 10
    local tw  = math.max(40, w - tx - 12)
    return {
        w = w, h = h,
        icon  = { x = ix, y = R((h - isz) / 2), size = isz, shape = "square" },
        title = { x = tx, y = R(h / 2 - 22), w = tw, scale = 1 },
        text  = { x = tx, y = R(h / 2 - 6), w = tw, scale = 1 },
        line2 = { x = tx, y = R(h / 2 + 8), w = tw, scale = 1 },
        bar   = { x = tx, y = R(h / 2 + 24), w = tw, h = 2 },
        more  = { x = w - 10, y = R(h / 2 + 2) },
    }
end

local function Copy(t) return t and CopyTable(t) or nil end

local LAYOUT_PARTS = { "icon", "title", "text", "line2", "bar", "more" }

local function SameBox(a, b)
    if type(a) ~= "table" or type(b) ~= "table" then return a == b end
    for k, v in pairs(b) do if a[k] ~= v then return false end end
    for k in pairs(a) do if b[k] == nil then return false end end
    return true
end

-- An unnamed entry whose parts are still exactly the old first layout
local function UntouchedOld(st)
    if st.styleKey or (st.name and st.name ~= "") or not (st.w and st.h) then return false end
    local o = StartLayout(st.w, st.h)
    for _, p in ipairs(LAYOUT_PARTS) do
        if not SameBox(st[p], o[p]) then return false end
    end
    return true
end

-- The saved settings for entry i, made on first use
local function State(i)
    local e = LIST[i]
    local s = Store().e
    local st = s[e.key]
    if st then
        if UntouchedOld(st) then
            for k, v in pairs(DefaultLayout()) do st[k] = v end
        end
        return st
    end
    if e.style then
        local d = e.style
        st = { name = TS.Label(d), back = d.back, atlas = d.atlas, file = d.file, fw = d.fw, fh = d.fh,
               crop = Copy(d.crop), flip = d.flip, w = d.w, h = d.h, icon = Copy(d.icon),
               title = Copy(d.title), text = Copy(d.text), line2 = Copy(d.line2), bar = Copy(d.bar), more = Copy(d.more),
               gap = d.gap, styleKey = d.key }
    else
        st = DefaultLayout()
        st.atlas, st.file = e.atlas, e.id
    end
    s[e.key] = st
    return st
end

-- ── File size (the sheet and file crops need it) ─────────────────────────────
local _prober = K.NewProber()
local function FileSize(id)
    if not id then return nil end
    local sz = _prober.sizes[id]
    if sz == nil then sz = Store().sizes and Store().sizes[id] end
    return sz
end
local function RememberSize(id)
    local sz = _prober.sizes[id]
    if type(sz) == "table" then
        local s = Store()
        s.sizes = s.sizes or {}
        s.sizes[id] = { sz[1], sz[2] }
    end
end
local function NativeSize()
    local sz = FileSize(LIST[_idx].id)
    if type(sz) == "table" then return sz[1], sz[2] end
end

-- The current entry as a style def (UI/ToastStyles.lua)
local function Def(i)
    local st = State(i or _idx)
    local e  = LIST[i or _idx]
    local d = { key = st.styleKey or e.key, name = st.name, w = st.w, h = st.h, flip = st.flip, gap = st.gap,
                icon = st.icon, title = st.title, text = st.text, line2 = st.line2, bar = st.bar, more = st.more }
    if st.back then
        d.back = st.back
    elseif st.crop or not st.atlas then
        local sz = FileSize(st.file)
        d.file, d.crop = st.file, st.crop
        if type(sz) == "table" then d.fw, d.fh = sz[1], sz[2] end
    else
        d.atlas = st.atlas
    end
    return d
end

-- ── Export: one STYLES entry per named entry that is not skipped ─────────────
local function Q(v) return string.format("%q", v) end
local function Num(v) return (v == R(v)) and tostring(v) or string.format("%.2f", v) end
local function Tbl(t, order)
    if not t then return "false" end
    local parts = {}
    for _, k in ipairs(order) do
        local v = t[k]
        if v ~= nil then
            if type(v) == "number" then parts[#parts + 1] = k .. " = " .. Num(v)
            elseif type(v) == "boolean" then parts[#parts + 1] = k .. " = " .. tostring(v)
            elseif type(v) == "table" then
                parts[#parts + 1] = k .. " = { " .. (v.atlas and ("atlas = " .. Q(v.atlas)) or ("file = " .. tostring(v.file)))
                    .. ", pad = " .. Num(v.pad or 0) .. " }"
            else parts[#parts + 1] = k .. " = " .. Q(v) end
        end
    end
    return "{ " .. table.concat(parts, ", ") .. " }"
end

local TEXT_ORDER = { "x", "y", "w", "font", "size", "scale", "justify" }

local function ExportText()
    local out, n, done, skipped = {}, 0, 0, 0
    for i, e in ipairs(LIST) do
        local st = Store().e[e.key]
        if st and st.done then
            done = done + 1
        elseif st and st.skip then
            skipped = skipped + 1
        elseif st and st.name and st.name ~= "" then
            n = n + 1
            local d = Def(i)
            local src
            if d.back then src = "back = " .. Q(d.back)
            elseif d.atlas then src = "atlas = " .. Q(d.atlas)
            else
                src = "file = " .. tostring(d.file) .. ", fw = " .. tostring(d.fw) .. ", fh = " .. tostring(d.fh)
                if d.crop then src = src .. ", crop = { " .. table.concat(d.crop, ", ") .. " }" end
                if e.atlas then src = src .. ",   -- " .. e.atlas end
            end
            out[#out + 1] = string.format("    { key = %s, name = %s, %s,%s",
                Q(d.key), Q(st.name), src, d.flip and (" flip = " .. Q(d.flip) .. ",") or "")
            out[#out + 1] = string.format("      w = %s, h = %s,%s", Num(d.w), Num(d.h),
                d.gap and (" gap = " .. Num(d.gap) .. ",") or "")
            -- frame / border: the style's default, replaced by a note's own frame
            out[#out + 1] = "      icon  = " .. Tbl(d.icon, { "x", "y", "size", "shape", "frame", "border", "ownFrame" }) .. ","
            out[#out + 1] = "      title = " .. Tbl(d.title, TEXT_ORDER) .. ","
            out[#out + 1] = "      text  = " .. Tbl(d.text, TEXT_ORDER) .. ","
            out[#out + 1] = "      line2 = " .. Tbl(d.line2, TEXT_ORDER) .. ","
            out[#out + 1] = "      bar   = " .. Tbl(d.bar, { "x", "y", "w", "h" }) .. ","
            out[#out + 1] = "      more  = " .. Tbl(d.more, { "x", "y" }) .. " },"
        end
    end
    table.insert(out, 1, string.format(
        "-- Toast Lab export: %d named, left out: %d done, %d skipped. Paste into STYLES in UI/ToastStyles.lua",
        n, done, skipped))
    return table.concat(out, "\n")
end

-- ── The parts ────────────────────────────────────────────────────────────────
local PARTS = { "icon", "title", "text", "line2", "bar", "more" }
local PART_LABEL = { icon = "Icon", title = "Title", text = "Why", line2 = "Line 2", bar = "Bar", more = "+N more" }
local PART_COL = {
    icon  = { 0.35, 0.85, 1 },
    title = { 1, 0.82, 0 },
    text  = { 0.75, 0.75, 0.75 },
    line2 = { 1, 1, 1 },
    bar   = { 0.3, 1, 0.4 },
    more  = { 1, 0.4, 0.9 },
}

-- A part's box in toast pixels: x, y, w, h (nil = the part is off)
local function PartRect(st, p)
    local b = st[p]
    if not b then return nil end
    if p == "icon" then return b.x, b.y, b.size, b.size end
    if p == "bar" then return b.x, b.y, b.w, math.max(3, b.h) end
    if p == "more" then return b.x - 50, b.y, 50, 12 end
    return b.x, b.y, b.w, R(TS.TextSize(p, b) + 2)
end

-- Moves (resize false) or sizes a part by dx, dy from its start values
local function ApplyDrag(st, p, start, dx, dy, resize)
    local b = st[p]
    if not b then return end
    if not resize then
        b.x, b.y = R(start.x + dx), R(start.y + dy)
        return
    end
    if p == "icon" then
        b.size = math.max(8, R(start.size + math.max(dx, dy)))
    elseif p == "bar" then
        b.w = math.max(4, R(start.w + dx)); b.h = math.max(1, R(start.h + dy))
    elseif p == "title" or p == "text" or p == "line2" then
        b.w = math.max(10, R(start.w + dx))
    end
end

-- ── The preview ──────────────────────────────────────────────────────────────
local PV_PAD = 24
local BGS = K.SHEET_BGS   -- the sheet's backgrounds, as the Icon Lab preview

-- A lab window's Bg: a colour, or a picture over the whole window
local function DrawBg(f, key)
    local b = BGS[Store()[key] or 1] or BGS[1]
    f.base:SetColorTexture(b[1], b[2], b[3], K.DrawPictureBg(f, b) and 0 or 1)
end

local function BgLayers(f)
    f.base = f:CreateTexture(nil, "BACKGROUND", nil, 1)
    f.base:SetPoint("TOPLEFT", 4, -4)
    f.base:SetPoint("BOTTOMRIGHT", -4, 4)
    f.pic = f:CreateTexture(nil, "BACKGROUND", nil, 7)
    f.pic:SetPoint("TOPLEFT", 4, -4)
    f.pic:SetPoint("BOTTOMRIGHT", -4, 4)
    f.pic:Hide()
end

-- A movable lab window with a border and the Bg layers
local function LabWindow(name)
    local f = BNB.CreateBackdropFrame("Frame", name, UIParent)
    f:SetFrameStrata("MEDIUM")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 14,
        insets = { left = 3, right = 3, top = 3, bottom = 3 } })
    f:SetBackdropColor(0.05, 0.05, 0.06, 1)
    f:SetBackdropBorderColor(0.5, 0.5, 0.55, 1)
    BgLayers(f)
    f:Hide()
    return f
end

local LayoutStack   -- forward: the stack follows every change

local function LayoutPreview()
    if not (_pv and _pv:IsShown()) then return end
    local st, d = State(_idx), Def(_idx)
    local z = Store().zoom or 2
    local tf = _pv.toast
    _pv.holder:SetScale(z)
    TS.Apply(tf, d)
    TS.Fill(tf, { icon = "Interface\\Icons\\INV_Misc_Note_01", title = L["TOAST_TEST_1"],
                  text = "Orgrimmar", line2 = L["TOAST_TEST_BODY_1"], pin = true })
    tf._more:SetText(string.format(L["TOAST_MORE"], 2)); tf._more:Show()
    if tf._barW then tf._bar:SetWidth(tf._barW); tf._bar:Show() end
    _pv.holder:SetSize(st.w, st.h)
    _pv:SetSize(math.max(380, st.w * z + PV_PAD * 2), math.max(160, st.h * z + PV_PAD * 2 + 30))
    for _, p in ipairs(PARTS) do
        local hnd = _pv.handles[p]
        local x, y, w, h = PartRect(st, p)
        if x then
            hnd:ClearAllPoints()
            hnd:SetPoint("TOPLEFT", tf, "TOPLEFT", x, -y)
            hnd:SetSize(math.max(2, w), math.max(2, h))
            local c = PART_COL[p]
            hnd:SetBackdropBorderColor(c[1], c[2], c[3], (p == _sel) and 1 or 0.45)
            hnd:SetBackdropColor(c[1], c[2], c[3], (p == _sel) and 0.12 or 0)
            hnd:Show()
        else
            hnd:Hide()
        end
    end
    DrawBg(_pv, "pvBg")
end

-- Both previews, while a part is dragged
local function Redraw()
    LayoutPreview()
    LayoutStack()
end

local function NewHandle(parent, p)
    local h = BNB.CreateBackdropFrame("Frame", nil, parent)
    h:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
    h:SetFrameLevel(parent:GetFrameLevel() + 10)
    h:EnableMouse(true)
    h:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(PART_LABEL[p], 1, 1, 1)
        GameTooltip:AddLine("Drag to move; drag the right or bottom edge to size. Arrows nudge (Shift 10, Ctrl sizes).", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    h:SetScript("OnLeave", function() GameTooltip:Hide() end)
    h:SetScript("OnMouseDown", function(self, btn)
        if btn ~= "LeftButton" then return end
        _sel = p
        local st = State(_idx)
        local s  = self:GetEffectiveScale()
        local cx, cy = GetCursorPosition()
        cx, cy = cx / s, cy / s
        local edge = 6 / (Store().zoom or 2)
        local resize = p ~= "more" and ((cx > self:GetRight() - edge) or (cy < self:GetBottom() + edge))
        local start = CopyTable(st[p])
        self:SetScript("OnUpdate", function()
            local nx, ny = GetCursorPosition()
            ApplyDrag(st, p, start, nx / s - cx, cy - ny / s, resize)
            Redraw()
        end)
        Refresh()
    end)
    h:SetScript("OnMouseUp", function(self)
        self:SetScript("OnUpdate", nil)
        Refresh()
    end)
    return h
end

local function Nudge(key)
    local st = State(_idx)
    local b = st[_sel]
    if not b then return false end
    local step = IsShiftKeyDown() and 10 or 1
    local dx = (key == "LEFT" and -step) or (key == "RIGHT" and step) or 0
    local dy = (key == "UP" and -step) or (key == "DOWN" and step) or 0
    if dx == 0 and dy == 0 then return false end
    ApplyDrag(st, _sel, CopyTable(b), dx, dy, IsControlKeyDown() and _sel ~= "more")
    Refresh()
    return true
end

local function BuildPreview()
    local f = LabWindow("BigNoteBoxToastLabPreview")

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -8)
    title:SetText("Toast Lab preview")
    local x = -8
    for _, z in ipairs({ 3, 2, 1 }) do
        local b = K.SmallBtn(f, z .. "x", 32, function() Store().zoom = z; Refresh() end)
        b:SetPoint("TOPRIGHT", f, "TOPRIGHT", x, -6)
        x = x - 34
    end
    local bgB = K.SmallBtn(f, "Bg", 32, function()
        local s = Store(); s.pvBg = (s.pvBg or 1) % #BGS + 1; Refresh()
    end)
    bgB:SetPoint("TOPRIGHT", f, "TOPRIGHT", x, -6)

    local holder = CreateFrame("Frame", nil, f)
    holder:SetPoint("CENTER", f, "CENTER", 0, -12)
    f.holder = holder
    local tf = BNB.CreateBackdropFrame("Frame", nil, holder)
    tf:SetPoint("CENTER")
    TS.Build(tf)
    f.toast = tf
    f.handles = {}
    for _, p in ipairs(PARTS) do f.handles[p] = NewHandle(tf, p) end

    -- Arrows nudge while the pointer is over the preview
    f:SetScript("OnEnter", function(self) if not InCombatLockdown() then self:EnableKeyboard(true) end end)
    f:SetScript("OnLeave", function(self)
        if not InCombatLockdown() and not self:IsMouseOver() then self:EnableKeyboard(false) end
    end)
    f:SetScript("OnKeyDown", function(self, key)
        BNB.SetPropagate(self, not Nudge(key))
    end)
    return f
end

-- ── The stack: four made-up note toasts, as they stack in game ──────────────
-- Toasts draw the note's own icon frame and title colour, so the stack makes
-- those up (Random) to show the style with what players will put on it
local ST_PAD, ST_HEAD = 16, 84
local ZOOM_MIN, ZOOM_MAX, ZOOM_STEP = 0.5, 2, 0.25

-- The window's own zoom, on top of the Toast size (lab only, saved)
local function StackZoom()
    return math.max(ZOOM_MIN, math.min(ZOOM_MAX, Store().stZoom or 1))
end
local ST_COUNT = 4
local GROW_ORDER = { "down", "up", "left", "right" }

local FAKE_TITLES = {
    "The bank", "Flight master", "A letter for Kalia", "Dailies in Thaldraszus", "Cooking vendor",
    "Raid night", "Herbs for my alt", "Rare: Shadeisethal", "Darkmoon Faire tickets", "Fishing spot",
    "Ask Thrall about the quest", "Guild bank tab 3",
}
local FAKE_WHERE = {
    "Orgrimmar", "Stormwind City", "Valdrakken", "Dornogal", "The Waking Shores", "Silvermoon City",
    "Thrall is here", "A vendor is open", "Rested", "You left Ironforge",
}
local FAKE_LINES = {
    L["TOAST_TEST_BODY_1"], L["TOAST_TEST_BODY_2"], L["TOAST_TEST_BODY_3"],
    "Buy 20 Shimmering Clams before the weekly reset.",
    "Turn in the quest to the guard by the bridge.",
    "Bring flasks, food and a repair hammer.",
    "The portal room is up the stairs on the right.",
}
local FAKE_COLORS = {
    false, false, { r = 1, g = 1, b = 1 }, { r = 0.45, g = 0.75, b = 1 }, { r = 0.40, g = 0.90, b = 0.45 },
    { r = 1, g = 0.55, b = 0.20 }, { r = 0.95, g = 0.45, b = 0.80 }, { r = 0.70, g = 0.50, b = 1 },
}
local FAKE_ICONS = {   -- when the icon catalog is empty
    "INV_Misc_Note_01", "INV_Misc_Book_09", "INV_Misc_Map_01", "INV_Potion_54",
    "INV_Misc_Coin_01", "Ability_Mount_RidingHorse", "INV_Misc_Head_Dragon_01", "Spell_Holy_HolyBolt",
}

local _fake = {}
local function Pick(t) return t[math.random(#t)] end

-- New icons, icon frames (one in three without), titles, colours, places
local function ShuffleFake()
    local icons  = BNB.ICON_MANIFEST
    local frames = BNB.IconFrames and BNB.IconFrames.LIST or {}
    for i = 1, ST_COUNT do
        _fake[i] = {
            icon  = (icons and #icons > 0) and Pick(icons) or ("Interface\\Icons\\" .. Pick(FAKE_ICONS)),
            note  = { iconFrame = (#frames > 0 and math.random(3) > 1) and Pick(frames).key or nil },
            title = Pick(FAKE_TITLES),
            color = Pick(FAKE_COLORS) or nil,
            where = Pick(FAKE_WHERE),
            line2 = Pick(FAKE_LINES),
            pin   = math.random(3) == 1,
            frac  = 0.15 + math.random() * 0.85,
        }
    end
end

local function StackGrow()
    local k = Store().stGrow or (BigNoteBoxDB and BigNoteBoxDB.toastGrow) or "down"
    return BNB.Toast.GROW[k] and k or "down"
end

local function ToastScale()
    local v = (BigNoteBoxDB and BigNoteBoxDB.toastScale) or BNB.DEFAULTS.toastScale or 1
    return math.max(0.5, math.min(1.5, v))
end

local function PlaceStackToast(tf)
    tf:ClearAllPoints()
    tf:SetPoint("CENTER", _st.holder, "BOTTOMLEFT", tf._x, tf._y)
end

-- The timer bar's colour, as the engine draws it at that much time left
local function BarColour(bar, frac)
    if frac > 0.5 then     bar:SetColorTexture(0.3, 0.75, 0.3, 0.9)
    elseif frac > 0.2 then bar:SetColorTexture(0.85, 0.70, 0.2, 0.9)
    else                   bar:SetColorTexture(0.85, 0.25, 0.2, 0.9) end
end

LayoutStack = function()
    if not (_st and _st:IsShown() and LIST[_idx]) then return end
    if #_fake < ST_COUNT then ShuffleFake() end
    local T, d = BNB.Toast, Def(_idx)
    local ts  = ToastScale()
    local s   = ts * StackZoom()
    local dir = T.GROW[StackGrow()]
    local ext, gaps = {}, {}
    for i, tf in ipairs(_st.toasts) do
        local fk = _fake[i]
        TS.Apply(tf, d)
        TS.Fill(tf, {
            icon = fk.icon, title = fk.title, titleColor = fk.color, text = fk.where,
            line2 = fk.line2, pin = fk.pin,
            -- As ContextNotes' NoteIconSetup: only a note with a frame
            iconSetup = fk.note.iconFrame and function(tex, _, ownFrame)
                if ownFrame then return end
                return BNB.ApplyIconFrame(tex, fk.note, tex:GetWidth())
            end or nil,
        })
        if tf._barW then
            -- The last toast's bar runs (the ticker in BuildStack)
            local frac = (i == ST_COUNT) and (_st._liveFrac or 1) or fk.frac
            tf._bar:SetWidth(math.max(0.01, tf._barW * frac))
            BarColour(tf._bar, frac)
            tf._bar:Show()
        end
        if i == ST_COUNT then
            tf._more:SetText(string.format(L["TOAST_MORE"], 2)); tf._more:Show()
        else
            tf._more:Hide()
        end
        -- Toast pixels: the holder carries the Toast size, as the engine's
        -- screen units carry it
        ext[i]  = (dir[1] ~= 0) and d.w or d.h
        gaps[i] = d.gap or T.GAP
    end
    local offs = T.Offsets(ext, gaps, dir)
    local minX, maxX, minY, maxY = math.huge, -math.huge, math.huge, -math.huge
    for _, o in ipairs(offs) do
        minX, maxX = math.min(minX, o[1] - d.w / 2), math.max(maxX, o[1] + d.w / 2)
        minY, maxY = math.min(minY, o[2] - d.h / 2), math.max(maxY, o[2] + d.h / 2)
    end
    local W, H = maxX - minX, maxY - minY
    local holder = _st.holder
    holder:SetScale(s)
    holder:SetSize(math.max(1, W), math.max(1, H))
    holder:ClearAllPoints()
    holder:SetPoint("TOP", _st, "TOP", 0, -(ST_HEAD + ST_PAD) / s)
    _st:SetSize(math.max(400, W * s + ST_PAD * 2), H * s + ST_PAD * 2 + ST_HEAD)
    for i, tf in ipairs(_st.toasts) do
        tf._tx, tf._ty = offs[i][1] - minX, offs[i][2] - minY
        if not _st._firing then tf._x, tf._y = tf._tx, tf._ty end
        PlaceStackToast(tf)
    end

    local st = State(_idx)
    _st.growBtn:SetText("Grow: " .. StackGrow())
    if not _st.gapBox.eb:HasFocus() then _st.gapBox.eb:SetText(tostring(st.gap or T.GAP)) end
    _st.gapNote:SetText(st.gap and "" or "(engine default)")
    _st.title:SetText(string.format("In game  (Toast size %d%%)", R(ts * 100)))
    _st.zoomLbl:SetText(string.format("%d%%", R(StackZoom() * 100)))
    DrawBg(_st, "stBg")
end

-- Ends a Fire run: every toast in its slot and shown
local function StopFire()
    if not _st then return end
    _st._firing = nil
    _st:SetScript("OnUpdate", nil)
    for _, tf in ipairs(_st.toasts) do
        tf._at = nil
        if BNB.StopFade then BNB.StopFade(tf) end
        tf:SetAlpha(1); tf:Show()
    end
end

-- The four toasts arrive one after another and slide into their slots, as
-- the engine's Slide in does
local FIRE_STEP = 0.45
local function Fire()
    local T = BNB.Toast
    local now = GetTime()
    _st._firing = true
    for i, tf in ipairs(_st.toasts) do
        if BNB.StopFade then BNB.StopFade(tf) end
        tf:Hide(); tf:SetAlpha(0)
        tf._at = now + (i - 1) * FIRE_STEP
    end
    LayoutStack()
    _st:SetScript("OnUpdate", function(self, dt)
        local t, busy = GetTime(), false
        local k   = math.min(1, dt * T.SLIDE_RATE)
        local dir = T.GROW[StackGrow()]
        local out = T.SLIDE_PX / ToastScale()
        for _, tf in ipairs(self.toasts) do
            if tf._at then
                busy = true
                if t >= tf._at then
                    tf._at = nil
                    tf._x, tf._y = tf._tx + dir[1] * out, tf._ty + dir[2] * out
                    PlaceStackToast(tf)
                    tf:Show()
                    BNB.FadeTo(tf, 0, 1, T.FADE)
                end
            elseif tf._x ~= tf._tx or tf._y ~= tf._ty then
                busy = true
                tf._x = tf._x + (tf._tx - tf._x) * k
                tf._y = tf._y + (tf._ty - tf._y) * k
                if math.abs(tf._tx - tf._x) < 0.5 and math.abs(tf._ty - tf._y) < 0.5 then
                    tf._x, tf._y = tf._tx, tf._ty
                end
                PlaceStackToast(tf)
            end
        end
        if not busy then self._firing = nil; self:SetScript("OnUpdate", nil) end
    end)
end

local function SetGap(v)
    local st = State(_idx)
    st.gap = v and R(v) or nil
    Refresh()
end

local function BuildStack()
    local f = LabWindow("BigNoteBoxToastLabStack")
    _st = f

    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.title:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -9)
    local bgB = K.SmallBtn(f, "Bg", 32, function()
        local s = Store(); s.stBg = (s.stBg or 1) % #BGS + 1; Refresh()
    end)
    bgB:SetPoint("TOPRIGHT", f, "TOPRIGHT", -8, -6)
    f.growBtn = K.SmallBtn(f, "Grow: down", 90, function()
        local cur = 1
        for n, k in ipairs(GROW_ORDER) do if k == StackGrow() then cur = n end end
        Store().stGrow = GROW_ORDER[cur % #GROW_ORDER + 1]
        StopFire()
        Refresh()
    end)
    f.growBtn:SetPoint("RIGHT", bgB, "LEFT", -4, 0)
    local fire = K.SmallBtn(f, "Fire", 50, function() Fire() end)
    fire:SetPoint("RIGHT", f.growBtn, "LEFT", -4, 0)
    local rnd = K.SmallBtn(f, "Random", 66, function() ShuffleFake(); Refresh() end)
    rnd:SetPoint("RIGHT", fire, "LEFT", -4, 0)

    -- Gap: the style's space between toasts (nil = the engine's GAP)
    local gl = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    gl:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -38)
    gl:SetText("Gap")
    local minus = K.SmallBtn(f, "-", 22, function()
        SetGap((State(_idx).gap or BNB.Toast.GAP) - (IsShiftKeyDown() and 5 or 1))
    end)
    minus:SetPoint("LEFT", gl, "RIGHT", 8, 0)
    f.gapBox = K.NumBox(f, 44, function(v) SetGap(v) end, function() Refresh() end)
    f.gapBox:SetPoint("LEFT", minus, "RIGHT", 4, 0)
    local plus = K.SmallBtn(f, "+", 22, function()
        SetGap((State(_idx).gap or BNB.Toast.GAP) + (IsShiftKeyDown() and 5 or 1))
    end)
    plus:SetPoint("LEFT", f.gapBox, "RIGHT", 4, 0)
    local def = K.SmallBtn(f, "Default", 60, function() SetGap(nil) end)
    def:SetPoint("LEFT", plus, "RIGHT", 6, 0)
    f.gapNote = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    f.gapNote:SetPoint("LEFT", def, "RIGHT", 8, 0)
    local hint = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("TOPRIGHT", f, "TOPRIGHT", -12, -66)
    hint:SetText("Wheel: gap (Shift 5)")

    -- Zoom: the window only, on top of the Toast size
    local zl = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    zl:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -64)
    zl:SetText("Zoom")
    local function SetZoom(d)
        local z = math.max(ZOOM_MIN, math.min(ZOOM_MAX, StackZoom() + d))
        Store().stZoom = (z ~= 1) and z or nil
        Refresh()
    end
    local zMinus = K.SmallBtn(f, "-", 22, function() SetZoom(-ZOOM_STEP) end)
    zMinus:SetPoint("LEFT", zl, "RIGHT", 8, 0)
    f.zoomLbl = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.zoomLbl:SetPoint("LEFT", zMinus, "RIGHT", 4, 0)
    f.zoomLbl:SetWidth(44)
    local zPlus = K.SmallBtn(f, "+", 22, function() SetZoom(ZOOM_STEP) end)
    zPlus:SetPoint("LEFT", f.zoomLbl, "RIGHT", 4, 0)
    local z100 = K.SmallBtn(f, "100%", 50, function() Store().stZoom = nil; Refresh() end)
    z100:SetPoint("LEFT", zPlus, "RIGHT", 6, 0)

    -- The wheel over the stack sets the gap; it can go below 0 for art
    -- with empty edges
    f:EnableMouseWheel(true)
    f:SetScript("OnMouseWheel", function(_, delta)
        SetGap((State(_idx).gap or BNB.Toast.GAP) + delta * (IsShiftKeyDown() and 5 or 1))
    end)

    local holder = CreateFrame("Frame", nil, f)
    f.holder = holder
    f.toasts = {}
    for i = 1, ST_COUNT do
        local tf = BNB.CreateBackdropFrame("Frame", nil, holder)
        TS.Build(tf)
        f.toasts[i] = tf
    end
    f:HookScript("OnHide", StopFire)

    -- The last toast counts down over and over, at the player's hold time
    -- (Until clicked = 5 s here), and pauses while the pointer is on a toast,
    -- as the engine does. Its own frame: Fire owns the window's OnUpdate
    local ticker = CreateFrame("Frame", nil, f)
    local elapsed = 0
    ticker:SetScript("OnUpdate", function(_, dt)
        local tf = f.toasts[ST_COUNT]
        if not (tf and tf._barW) then return end
        for _, t in ipairs(f.toasts) do
            if t:IsShown() and t:IsMouseOver() then return end
        end
        local hold = (BigNoteBoxDB and BigNoteBoxDB.popupHoldTime) or BNB.DEFAULTS.popupHoldTime or 5
        if hold <= 0 then hold = 5 end
        elapsed = (elapsed + dt) % hold
        local frac = 1 - elapsed / hold
        f._liveFrac = frac
        tf._bar:SetWidth(math.max(0.01, tf._barW * frac))
        BarColour(tf._bar, frac)
    end)
    return f
end

-- ── The sheet (Labs/LabSheet.lua): the art area of a file entry ─────────────
local RegionRect = K.NewRegionRects()
local function Regions()
    local e = LIST[_idx]
    if e._regs == nil then e._regs = K.AtlasRegions(e.id, e.path) or false end
    return e._regs or nil
end

local function BuildSheet()
    _sheet = K.NewSheet({
        name = "BigNoteBoxToastLabSheet", minW = 560,
        View = function() local s = Store(); s.sheet = s.sheet or {}; return s.sheet end,
        File = function()
            local e = LIST[_idx]
            if not (e and e.id) then return nil end
            local W, H = NativeSize()
            return e.id, W, H, e.atlas or e.path, FileSize(e.id) == false
        end,
        boxes = { { key = "art", label = "Art", col = { 1, 0.82, 0, 1 } } },
        Active = function() return "art" end,
        Box = function()
            local c = State(_idx).crop
            if c then return c[1], c[2], c[3], c[4] end
        end,
        ToolBox = function()
            local c = State(_idx).crop
            if c then return c[1], c[2], c[3], c[4] end
            local W, H = NativeSize()
            if W then return 0, 0, W, H end
        end,
        Bounds = function()
            local W, H = NativeSize()
            if W then return 0, 0, W, H end
        end,
        SetBox = function(_, x, y, w, h)
            local st = State(_idx)
            if not x then st.crop = nil; return end
            st.crop = { R(x), R(y), math.max(1, R(w)), math.max(1, R(h)) }
        end,
        Changed = function() Refresh() end,
        Regions = Regions,
        RegionRect = function(reg, W, H) return RegionRect(LIST[_idx].id, reg, W, H) end,
        CurrentRegion = function() return LIST[_idx].atlas end,
        PickRegion = function(name)
            local e = LIST[_idx]
            for i, o in ipairs(LIST) do
                if o.atlas == name then _idx = i; Refresh(); return end
            end
            local s = Store()
            s.added[#s.added + 1] = { id = e.id, path = e.path, atlas = name }
            BuildList()
            for i, o in ipairs(LIST) do if o.atlas == name then _idx = i end end
            Refresh()
        end,
    })
    _sheet.Build()
end

-- ── The control window ───────────────────────────────────────────────────────
local C_W, C_H, C_PAD = 380, 600, 12

local function Go(i)
    _idx = ((i - 1) % #LIST) + 1
    Store().idx = _idx
    State(_idx)
    local e = LIST[_idx]
    if e.id then
        _prober:Probe(_ctl, e.id, function()
            RememberSize(e.id)
            if LIST[_idx] == e then Refresh() end
        end)
    end
    Refresh()
end

local function EntryLabel(i)
    local e  = LIST[i]
    local st = Store().e[e.key]
    local lbl = (st and st.name and st.name ~= "") and st.name or (e.atlas or e.key)
    if e.atlas and not AtlasHere(e.atlas) and e.g ~= "built" then lbl = "|cffff5555" .. lbl .. " (not on this client)|r"
    elseif st and st.done then lbl = "|cff888888" .. lbl .. " (done)|r"
    elseif st and st.skip then lbl = "|cff888888" .. lbl .. " (skip)|r"
    elseif st and st.name and st.name ~= "" and e.g ~= "built" then lbl = "|cff66bb6a" .. lbl .. "|r" end
    return lbl
end

local function BuildControl()
    local f, exportBtn, closeBtn = BNB.CreateToolWindow({
        name = "BigNoteBoxToastLab", w = C_W, h = C_H, title = "Toast Lab",
        pad = C_PAD, cw = C_W - C_PAD * 2, footH = 40,
        btn1 = "Export", btn2 = L["CLOSE"],
        toplevel = true, escClose = true,
    })
    f:SetPoint("CENTER", UIParent, "CENTER", -200, 0)
    closeBtn:SetScript("OnClick", function() f:Hide() end)
    exportBtn:SetScript("OnClick", function() BNB.ShowClipboardHint(ExportText(), f, true) end)
    f:HookScript("OnHide", function()
        if _sheet and _sheet.frame then _sheet.frame:Hide() end
        if _pv then _pv:Hide() end
        if _st then _st:Hide() end
        TS.SetOverride(nil)
    end)
    _ctl = f

    local cw = C_W - C_PAD * 2
    local body = CreateFrame("Frame", nil, f)
    body:SetPoint("TOPLEFT", f, "TOPLEFT", C_PAD, -34)
    body:SetSize(cw, C_H - 80)
    local y = 0
    local hosts = {}

    local function Label(text, x, yy)
        local fs = body:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        fs:SetPoint("TOPLEFT", body, "TOPLEFT", x, yy - 4)
        fs:SetText(text)
        return fs
    end
    local function Check(label, x, yy, onClick)
        local cb = CreateFrame("CheckButton", nil, body, "UICheckButtonTemplate")
        cb:SetSize(24, 24)
        cb:SetPoint("TOPLEFT", body, "TOPLEFT", x - 4, yy + 2)
        local fs = body:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        fs:SetPoint("LEFT", cb, "RIGHT", 2, 0)
        fs:SetText(label)
        BNB.LabelHit(cb, fs)
        cb:SetScript("OnClick", onClick)
        cb._lbl = fs   -- a body FontString: hide it with the box
        return cb
    end
    -- A number box writing st[part][field] (part nil = st itself)
    local function Num(x, yy, w, part, field)
        local host
        host = K.NumBox(body, w, function(v)
            local st = State(_idx)
            local t = part and st[part == "sel" and _sel or part] or st
            if v and t then
                t[host._field] = v
                if host._text then t.scale = nil end
            end
            Refresh()
        end, function() Refresh() end)
        host:SetPoint("TOPLEFT", body, "TOPLEFT", x, yy)
        host._part, host._field = part, field
        hosts[#hosts + 1] = host
        return host
    end

    -- Navigation. < > step over done entries while Hide done is on (as the
    -- Icon Lab); Hide done is a list filter, so it sits on this row
    local function Hidden(i)
        local st = Store().e[LIST[i].key]
        return Store().hideDone and st and st.done and i ~= _idx
    end
    local function Step(d)
        local i = _idx
        for _ = 1, #LIST do
            i = ((i + d - 1) % #LIST) + 1
            if not Hidden(i) then break end
        end
        Go(i)
    end
    local prev = K.SmallBtn(body, "<", 30, function() Step(-1) end)
    prev:SetPoint("TOPLEFT", body, "TOPLEFT", 0, y)
    local hideCb = CreateFrame("CheckButton", nil, body, "UICheckButtonTemplate")
    hideCb:SetSize(24, 24)
    local hideLbl = body:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    hideLbl:SetPoint("LEFT", hideCb, "RIGHT", 0, 0)
    hideLbl:SetText("Hide done")
    hideCb:SetPoint("TOPLEFT", body, "TOPLEFT", cw - hideLbl:GetStringWidth() - 24, y + 2)
    BNB.LabelHit(hideCb, hideLbl)
    BNB.CheckTip(hideCb, "Keeps done entries out of the list and out of < >.")
    hideCb:SetScript("OnClick", function(self) Store().hideDone = self:GetChecked() or nil end)
    f.hideDoneCb = hideCb
    local nextB = K.SmallBtn(body, ">", 30, function() Step(1) end)
    nextB:SetPoint("TOPRIGHT", hideCb, "TOPLEFT", -4, -2)
    local dd = CreateFrame("DropdownButton", nil, body, "WowStyle1DropdownTemplate")
    dd:SetPoint("LEFT", prev, "RIGHT", 6, 0)
    dd:SetPoint("RIGHT", nextB, "LEFT", -6, 0)
    dd:SetupMenu(function(_, root)
        pcall(function() root:SetScrollMode(500) end)
        for _, gk in ipairs(GROUP_ORDER) do
            local titled
            for i, e in ipairs(LIST) do
                if e.g == gk and not Hidden(i) then
                    if not titled then root:CreateTitle(GROUPS[gk]); titled = true end
                    root:CreateRadio(EntryLabel(i), function() return _idx == i end, function() Go(i) end)
                end
            end
        end
    end)
    f.dd = dd
    y = y - 28

    -- Name, Done (finished: left out of Export), Skip (rejected)
    Label("Name", 0, y)
    local name = K.PlainBox(body, 150)
    name:SetPoint("TOPLEFT", body, "TOPLEFT", 48, y)
    name.eb:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    name.eb:SetScript("OnEditFocusLost", function(self)
        local t = self:GetText()
        State(_idx).name = (t ~= "") and t or nil
        Refresh()
    end)
    hosts[#hosts + 1] = name
    f.nameEb = name.eb
    f.doneCb = Check("Done", 214, y, function(self) State(_idx).done = self:GetChecked() or nil; Refresh() end)
    BNB.CheckTip(f.doneCb, "Finished: left out of Export (Hide done keeps it out of the list).")
    f.skipCb = Check("Skip", 284, y, function(self) State(_idx).skip = self:GetChecked() or nil; Refresh() end)
    BNB.CheckTip(f.skipCb, "Rejected: not a toast style, left out of Export.")
    y = y - 26
    f.src = Label("", 0, y)
    f.src:SetWidth(cw); f.src:SetJustifyH("LEFT"); f.src:SetWordWrap(false)
    y = y - 20

    -- Look: art / plain / skin, flips
    Label("Look", 0, y)
    local LOOKS = { { nil, "Game art" }, { "plain", "Plain black" }, { "skin", "Skin colour" } }
    f.lookBtn = K.SmallBtn(body, "Game art", 96, function()
        local st, cur = State(_idx), 1
        for n, l in ipairs(LOOKS) do if l[1] == st.back then cur = n end end
        st.back = LOOKS[cur % #LOOKS + 1][1]
        Refresh()
    end)
    f.lookBtn:SetPoint("TOPLEFT", body, "TOPLEFT", 48, y)
    f.LOOKS = LOOKS
    local function SetFlip(h, v)
        local st = State(_idx)
        local fh = (h == nil) and (st.flip == "h" or st.flip == "hv") or h
        local fv = (v == nil) and (st.flip == "v" or st.flip == "hv") or v
        st.flip = (fh and fv and "hv") or (fh and "h") or (fv and "v") or nil
        Refresh()
    end
    f.flipH = Check("Flip H", 160, y, function(self) SetFlip(self:GetChecked() and true or false, nil) end)
    f.flipV = Check("Flip V", 236, y, function(self) SetFlip(nil, self:GetChecked() and true or false) end)
    y = y - 28

    -- Toast size
    Label("Size", 0, y)
    f.wBox = Num(48, y, 50, nil, "w")
    f.hBox = Num(104, y, 50, nil, "h")
    local artSize = K.SmallBtn(body, "Art size", 76, function()
        local st, e = State(_idx), LIST[_idx]
        local w, h
        if st.crop then w, h = st.crop[3], st.crop[4]
        elseif e.atlas then w, h = AtlasSize(e.atlas)
        else w, h = NativeSize() end
        if w then st.w, st.h = R(w), R(h) end
        Refresh()
    end)
    artSize:SetPoint("TOPLEFT", body, "TOPLEFT", 162, y)
    local sheetBtn = K.SmallBtn(body, "Sheet", 60, function()
        local sh = _sheet.frame
        sh:SetShown(not sh:IsShown())
        Refresh()
    end)
    sheetBtn:SetPoint("TOPLEFT", body, "TOPLEFT", 244, y)
    y = y - 32

    -- The part the tools act on
    f.ring = K.Ring(body)
    f.partBtns = {}
    local px = 0
    for _, p in ipairs(PARTS) do
        local b = K.SmallBtn(body, PART_LABEL[p], (p == "more") and 64 or 50, function() _sel = p; Refresh() end)
        b:SetPoint("TOPLEFT", body, "TOPLEFT", px, y)
        px = px + b:GetWidth() + 4
        f.partBtns[p] = b
    end
    y = y - 30
    Label("X", 0, y);      f.xBox = Num(16, y, 46, "sel", "x")
    Label("Y", 70, y);     f.yBox = Num(86, y, 46, "sel", "y")
    f.wLbl = Label("W", 140, y); f.pwBox = Num(158, y, 46, "sel", "w")
    f.hLbl = Label("H", 212, y); f.phBox = Num(228, y, 46, "sel", "h")
    f.onCb = Check("On", 290, y, function(self)
        local st = State(_idx)
        if self:GetChecked() then
            st[_sel] = st[_sel] or DefaultLayout()[_sel]
        else
            st[_sel] = (_sel == "bar") and false or nil
        end
        Refresh()
    end)
    y = y - 28

    -- Text parts: size, justify, font. Icon: shape, then its default frame
    -- and border below
    f.sizeLbl = Label("Size", 0, y)
    f.tsizeBox = Num(40, y, 46, "sel", "size")
    f.tsizeBox._text = true   -- a font size replaces the older scale
    local JUST = { "LEFT", "CENTER", "RIGHT" }
    f.justBtn = K.SmallBtn(body, "LEFT", 70, function()
        local b = State(_idx)[_sel]
        if not b then return end
        local cur = 1
        for n, j in ipairs(JUST) do if j == (b.justify or "LEFT") then cur = n end end
        b.justify = JUST[cur % #JUST + 1]
        if b.justify == "LEFT" then b.justify = nil end
        Refresh()
    end)
    f.justBtn:SetPoint("TOPLEFT", body, "TOPLEFT", 100, y)
    f.shapeBtn = K.SmallBtn(body, "Square", 70, function()
        local b = State(_idx).icon
        if b then b.shape = (b.shape == "circle") and "square" or "circle"; Refresh() end
    end)
    f.shapeBtn:SetPoint("TOPLEFT", body, "TOPLEFT", 100, y)
    -- Art with its own socket or ring: the note's icon frame stays off
    f.ownFrameCb = Check("Toast's border only", 184, y, function(self)
        local b = State(_idx).icon
        if b then b.ownFrame = self:GetChecked() or nil end
        Refresh()
    end)
    BNB.CheckTip(f.ownFrameCb, "Only this toast's own border (its Frame / Border below, or a socket in the art). A note's own icon frame is not drawn on this style.")
    y = y - 28

    -- A text's font: the game's font object (keeps its fallback for every
    -- alphabet), the game's own fonts, ours, and installed font packs
    f.fontLbl = Label("Font", 0, y)
    local fdd = CreateFrame("DropdownButton", nil, body, "WowStyle1DropdownTemplate")
    fdd:SetPoint("TOPLEFT", body, "TOPLEFT", 48, y + 2)
    fdd:SetWidth(cw - 48)
    fdd:SetupMenu(function(_, root)
        pcall(function() root:SetScrollMode(400) end)
        local function Cur() local b = State(_idx)[_sel]; return b and b.font end
        local function Set(k) local b = State(_idx)[_sel]; if b then b.font = k; Refresh() end end
        local function Radio(label, key)
            root:CreateRadio(label, function() return Cur() == key end, function() Set(key) end)
        end
        Radio("Game font (default)", nil)
        root:CreateTitle("Blizzard fonts")
        for _, g in ipairs(TS.GAME_FONTS) do Radio(g.label, g.key) end
        local ours, packs = {}, {}
        for _, def in ipairs(BNB.FONTS or {}) do
            if def._pack then packs[#packs + 1] = def
            elseif not (def._isWoW or def._isLSM) and (def.set or "latin") == "latin" then ours[#ours + 1] = def end
        end
        root:CreateTitle("BigNoteBox fonts")
        for _, def in ipairs(ours) do Radio(def.label, def.id) end
        if #packs > 0 then
            root:CreateTitle("Font packs")
            for _, def in ipairs(packs) do Radio(def.label, def.id) end
        end
    end)
    f.fontDd = fdd

    -- Icon: the style's default frame and border, drawn only for a note
    -- that has no icon frame of its own (Dukul, 2026-10-07)
    f.frameLbl = Label("Frame", 0, y)
    -- < > step through None + every frame, as the entry row does
    local function StepFrame(d)
        local b = State(_idx).icon
        if not b then return end
        local keys = { false }
        for _, e in ipairs(BNB.IconFrames and BNB.IconFrames.LIST or {}) do keys[#keys + 1] = e.key end
        local cur = 1
        for n, k in ipairs(keys) do if k == (b.frame or false) then cur = n end end
        b.frame = keys[((cur - 1 + d) % #keys) + 1] or nil
        Refresh()
    end
    f.framePrev = K.SmallBtn(body, "<", 24, function() StepFrame(-1) end)
    f.framePrev:SetPoint("TOPLEFT", body, "TOPLEFT", 48, y)
    f.frameNext = K.SmallBtn(body, ">", 24, function() StepFrame(1) end)
    f.frameNext:SetPoint("TOPRIGHT", body, "TOPRIGHT", 0, y)
    local idd = CreateFrame("DropdownButton", nil, body, "WowStyle1DropdownTemplate")
    idd:SetPoint("LEFT", f.framePrev, "RIGHT", 4, 0)
    idd:SetPoint("RIGHT", f.frameNext, "LEFT", -4, 0)
    idd:SetupMenu(function(_, root)
        pcall(function() root:SetScrollMode(400) end)
        local function Set(k) local b = State(_idx).icon; if b then b.frame = k; Refresh() end end
        root:CreateRadio("None", function() local b = State(_idx).icon; return not (b and b.frame) end, function() Set(nil) end)
        for _, e in ipairs(BNB.IconFrames and BNB.IconFrames.LIST or {}) do
            root:CreateRadio(e.label, function() local b = State(_idx).icon; return b and b.frame == e.key end,
                function() Set(e.key) end)
        end
    end)
    f.frameDd = idd
    y = y - 28
    f.borderLbl = Label("Border", 0, y)
    local bord = K.PlainBox(body, 200)
    bord:SetPoint("TOPLEFT", body, "TOPLEFT", 48, y)
    bord.eb:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    bord.eb:SetScript("OnEditFocusLost", function(self)
        local b = State(_idx).icon
        if not b then return end
        local t = self:GetText():gsub("^%s+", ""):gsub("%s+$", "")
        if t == "" then b.border = nil
        else
            local pad = b.border and b.border.pad or 0
            local id = tonumber(t)
            b.border = id and { file = id, pad = pad } or { atlas = t, pad = pad }
        end
        Refresh()
    end)
    hosts[#hosts + 1] = bord
    f.borderEb = bord.eb
    f.borderPad = K.NumBox(body, 40, function(v)
        local b = State(_idx).icon
        if b and b.border and v then b.border.pad = v end
        Refresh()
    end, function() Refresh() end)
    f.borderPad:SetPoint("TOPLEFT", body, "TOPLEFT", 256, y)
    hosts[#hosts + 1] = f.borderPad
    f.padLbl = Label("pad", 300, y)
    y = y - 22
    f.iconNote = Label("Default only: a note's own icon frame replaces both.", 0, y)
    f.iconNote:SetFontObject("GameFontDisableSmall")
    y = y - 22
    K.TabChain(hosts)

    -- Try it on the real toasts
    local try = K.SmallBtn(body, "Try on toasts", 120, function()
        TS.SetOverride(Def(_idx))
        if BNB.TestSituationToasts then BNB.TestSituationToasts() end
    end)
    try:SetPoint("TOPLEFT", body, "TOPLEFT", 0, y)
    local stop = K.SmallBtn(body, "Stop trying", 100, function() TS.SetOverride(nil) end)
    stop:SetPoint("LEFT", try, "RIGHT", 6, 0)
    y = y - 28
    local help = body:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    help:SetPoint("TOPLEFT", body, "TOPLEFT", 0, y)
    help:SetWidth(cw); help:SetJustifyH("LEFT")
    help:SetText("Export takes every named entry that is not done or skipped. Built-in styles export under their own key.")
end

-- FontStrings show with Show / Hide, never SetShown
local function Vis(fs, on)
    if on then fs:Show() else fs:Hide() end
end

local function SetBox(host, v)
    if host.eb:HasFocus() then return end
    host.eb:SetText(v ~= nil and tostring(v) or "")
end

Refresh = function()
    if not _ctl then return end
    local f, e, st = _ctl, LIST[_idx], State(_idx)
    f.dd:SetText(EntryLabel(_idx))
    if not f.nameEb:HasFocus() then f.nameEb:SetText(st.name or "") end
    f.doneCb:SetChecked(st.done and true or false)
    f.skipCb:SetChecked(st.skip and true or false)
    f.hideDoneCb:SetChecked(Store().hideDone and true or false)
    local src = e.atlas and ("atlas " .. e.atlas) or (e.path and (e.path .. " (" .. tostring(e.id) .. ")")) or ("style " .. e.key)
    if st.crop then src = src .. "  crop " .. table.concat(st.crop, ", ") end
    f.src:SetText(src)
    for _, l in ipairs(f.LOOKS) do if l[1] == st.back then f.lookBtn:SetText(l[2]) end end
    f.flipH:SetChecked(st.flip == "h" or st.flip == "hv")
    f.flipV:SetChecked(st.flip == "v" or st.flip == "hv")
    SetBox(f.wBox, st.w); SetBox(f.hBox, st.h)

    K.PutRing(f.ring, f.partBtns[_sel])
    local b = st[_sel]
    f.onCb:SetChecked(b and true or false)
    SetBox(f.xBox, b and b.x); SetBox(f.yBox, b and b.y)
    local isIcon, isText = _sel == "icon", (_sel == "title" or _sel == "text" or _sel == "line2")
    f.pwBox._field = isIcon and "size" or "w"
    f.wLbl:SetText(isIcon and "Size" or "W")
    SetBox(f.pwBox, b and (isIcon and b.size or b.w))
    local hasW = _sel ~= "more"
    f.pwBox:SetShown(hasW); Vis(f.wLbl, hasW)
    f.phBox:SetShown(_sel == "bar"); Vis(f.hLbl, _sel == "bar")
    SetBox(f.phBox, b and b.h)
    Vis(f.sizeLbl, isText); f.tsizeBox:SetShown(isText); f.justBtn:SetShown(isText)
    -- A text with only the older scale shows the px it draws at
    SetBox(f.tsizeBox, isText and b and Num(R(TS.TextSize(_sel, b) * 100) / 100) or nil)
    f.justBtn:SetText(b and b.justify or "LEFT")
    Vis(f.fontLbl, isText); f.fontDd:SetShown(isText)
    Vis(f.frameLbl, isIcon); f.frameDd:SetShown(isIcon)
    f.framePrev:SetShown(isIcon); f.frameNext:SetShown(isIcon)
    Vis(f.borderLbl, isIcon); f.borderEb:GetParent():SetShown(isIcon); f.borderPad:SetShown(isIcon)
    Vis(f.padLbl, isIcon); Vis(f.iconNote, isIcon)
    local ic = st.icon
    f.frameDd:SetText((ic and ic.frame and BNB.IconFrames.Label(ic.frame)) or "None")
    if not f.borderEb:HasFocus() then
        local bd = ic and ic.border
        f.borderEb:SetText(bd and (bd.atlas or tostring(bd.file)) or "")
    end
    SetBox(f.borderPad, ic and ic.border and ic.border.pad)
    f.fontDd:SetText((b and b.font and TS.FontLabel(b.font)) or "Game font (default)")
    f.shapeBtn:SetShown(isIcon)
    f.ownFrameCb:SetShown(isIcon); Vis(f.ownFrameCb._lbl, isIcon)
    f.iconNote:SetText((st.icon and st.icon.ownFrame)
        and "Always drawn: a note's own icon frame is left off on this style."
        or "Default only: a note's own icon frame replaces both.")
    f.ownFrameCb:SetChecked(st.icon and st.icon.ownFrame and true or false)
    f.shapeBtn:SetText((st.icon and st.icon.shape == "circle") and "Circle" or "Square")
    LayoutPreview()
    LayoutStack()
    if _sheet and _sheet.frame and _sheet.frame:IsShown() then _sheet.Layout() end
end

function BNB.OpenToastLab()
    if not BigNoteBoxDB then return end
    BuildList()
    if not _ctl then BuildControl() end
    if not _sheet then BuildSheet() end
    _pv = _pv or BuildPreview()
    if not _pv:GetPoint() then _pv:SetPoint("TOPLEFT", _ctl, "TOPRIGHT", 12, 0) end
    if not _st then BuildStack() end
    if not _st:GetPoint() then _st:SetPoint("TOPRIGHT", _ctl, "TOPLEFT", -12, 0) end
    local sh = _sheet.frame
    if not sh:GetPoint() then sh:SetPoint("TOPLEFT", _pv, "BOTTOMLEFT", 0, -12) end
    _ctl:Show(); _ctl:Raise()
    _pv:Show()
    _st:Show()
    Go(Store().idx or 1)
end

end

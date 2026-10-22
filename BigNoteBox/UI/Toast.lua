-- BigNoteBox UI/Toast.lua -- The toast engine (ALL-376)
--
-- One toast per message, stacked from a player-placed anchor in the player's
-- grow direction (down / up / left / right). Each toast has its own countdown;
-- pointing at any toast pauses them all, so the stack never moves under the
-- pointer. A message whose key is already on screen restarts its toast rather
-- than adding a second one. More toasts than Max shown wait in a queue (the
-- last toast reads "+N more") and slide in as room frees. In combat a toast
-- shows, waits for the end of combat or is dropped (toastCombat).
--
-- How a toast looks is its style (UI/ToastStyles.lua, S2): each style has its
-- own size, so the stack lines up by each toast's own size. Toast scale sizes
-- them all.
--
-- Shared: situations are the first user (Features/ContextNotes.lua); any
-- module can call it.
--
--   BNB.Toast.Show(spec)
--     spec = {
--       key        = unique per message ("note:<id>"); nil = never merged
--       source     = who sent it ("situation", "test"), for DismissAll
--       style      = a style key (nil = the player's toastStyle)
--       icon       = texture path or file id (nil = the BNB icon)
--       title      = gold line; titleColor = { r, g, b } (optional)
--       text       = grey line under the title (optional)
--       line2      = a second line, where the style has one (optional)
--       pin        = true: the waypoint pin on the icon
--       noIcon     = true: no icon; iconSetup(tex, f) = after the icon is set
--                    (see BNB.ToastStyles.Fill)
--       rows       = { { title, titleColor, tag, onClick, onRightClick(row, f) }, ... }:
--                    a list hanging under the toast (the grouped situation toast)
--       hold       = seconds on screen (nil = popupHoldTime; 0 = until clicked)
--       onClick    = function(spec): left click; the toast closes after it
--       onClose    = function(spec): the hover X was clicked; the toast closes after it
--       onRightClick = function(spec, f): right click (nil = close); a menu
--                    opened on f keeps every timer paused while it is open
--       force      = true: shows in combat whatever toastCombat says (Test)
--     }
--   BNB.Toast.Dismiss(key) / DismissAll(source) / Relayout() / Restyle()
--   BNB.Toast.AnchorPoint()  -> point, relativeTo, relativePoint, x, y
--
-- The Toasts module (ALL-384): BNB.ToastsEnabled() (toastsEnabled) and a
-- switch per sender, BNB.ToastSourceOn(source) (toastSources[source], a
-- sender not listed is always on; "test" is never listed). Show refuses while
-- either is off, so every sender is covered in one place.
--   BNB.Toast.ToggleAnchor() / LockAnchor() / ResetAnchor() / RefreshAnchor()
--
-- Settings (BNB.DEFAULTS): popupAnchorX / popupAnchorY (the first toast's
-- centre, offset from the screen centre), popupHoldTime, toastGrow, toastMax
-- (1-10), toastSlide, toastCombat ("show" / "wait" / "drop"), toastScale,
-- toastStyle (nil = the faction loot toast), toastSound (nil = none, else an
-- alarm sound key), toastLayout (read by ContextNotes: "each" = one toast per
-- note, "group" = one toast with rows).

local BNB = BigNoteBox
local L   = BNB.L

local T = {}
BNB.Toast = T

local GAP          = 6
local ROW_H        = 22
local MAX_ROWS     = 8
local FADE         = 0.35
local SLIDE_PX     = 40     -- a new toast slides in from this far out
local SLIDE_RATE   = 12     -- approach speed (fraction of the gap per second)
local ARROW        = "Interface\\AddOns\\BigNoteBox\\Assets\\Buttons\\Symbols\\bt-%s-normal"
local ROWS_PAD     = 3      -- inside the rows box, round the rows
local ROWS_GAP     = 2      -- between a toast and its rows box below it
-- A burst (toasts within BURST_WINDOW s of each other, as at login): each
-- next one slides in BURST_STAGGER s later and stays BURST_STEP s longer, so
-- they come one at a time and leave oldest first (Dukul, 2026-10-11)
local BURST_WINDOW, BURST_STAGGER, BURST_STEP = 0.5, 0.25, 1
T.GAP, T.FADE, T.SLIDE_PX, T.SLIDE_RATE = GAP, FADE, SLIDE_PX, SLIDE_RATE   -- the Toast Lab stacks with these

local GROW = {
    down  = {  0, -1 },
    up    = {  0,  1 },
    right = {  1,  0 },
    left  = { -1,  0 },
}

local _shown      = {}   -- toast frames on screen, [1] = at the anchor
local _queue      = {}   -- specs waiting for room
local _waitCombat = {}   -- specs held back until combat ends
local _waitIntro  = {}   -- specs held back until the Explorer welcome is answered (ALL-543)
local _pool       = {}   -- toast frames not in use
local _driver     = nil
local _ax, _ay    = 0, 200   -- anchor offset, cached by Relayout
local _moreBox    = nil      -- the "+N" box at the end of the line (queued toasts)
local _burstAt, _burstN = 0, 0

-- ── Settings ────────────────────────────────────────────────────────────────
local function Setting(key)
    local db = BigNoteBoxDB
    local v  = db and db[key]
    if v == nil then v = BNB.DEFAULTS[key] end
    return v
end

-- ── The Toasts module (ALL-384) ─────────────────────────────────────────────
function BNB.ToastsEnabled()
    return not BigNoteBoxDB or BigNoteBoxDB.toastsEnabled ~= false
end

function BNB.ToastSourceOn(source)
    local t = BigNoteBoxDB and BigNoteBoxDB.toastSources
    return not (source and t and t[source] == false)
end

local function MaxShown() return math.max(1, math.min(10, Setting("toastMax") or 5)) end
local function GrowDir()  return GROW[Setting("toastGrow")] or GROW.down end
local function Scale()    return math.max(0.5, math.min(1.5, Setting("toastScale") or 1)) end

local function HoldTime(spec)
    if spec.hold then return spec.hold end
    return Setting("popupHoldTime") or 5
end

local function InCombat()
    return InCombatLockdown() or UnitAffectingCombat("player")
end

-- The default anchor by screen shape (Dukul, 2026-10-22): the wider main
-- window on an ultrawide (ALL-536) covered the 16:9 spot, so there it sits
-- further left (Dukul's placement on 2293 x 960 at UI scale 0.80)
local WIDE_ANCHOR_X, WIDE_ANCHOR_Y = -696, 270
local function DefaultAnchor()
    if BNB.IsUltrawide and BNB.IsUltrawide() then return WIDE_ANCHOR_X, WIDE_ANCHOR_Y end
    return BNB.DEFAULTS.popupAnchorX, BNB.DEFAULTS.popupAnchorY
end

-- The saved anchor, or the default for this screen. One saved exactly on the
-- 16:9 default (Reset, the v21 move) counts as the default too
local function AnchorXY()
    local db = BigNoteBoxDB
    local x, y = db and db.popupAnchorX, db and db.popupAnchorY
    if x == nil or y == nil
        or (x == BNB.DEFAULTS.popupAnchorX and y == BNB.DEFAULTS.popupAnchorY) then
        return DefaultAnchor()
    end
    return x, y
end

function T.AnchorPoint()
    local x, y = AnchorXY()
    return "CENTER", UIParent, "CENTER", x, y
end

-- The size (screen units) of a toast drawn in a style
local function StyleSize(def)
    local s = Scale()
    return def.w * s, def.h * s
end

-- Along the grow direction: a toast's extent
local function Extent(w, h)
    return (GrowDir()[1] ~= 0) and w or h
end

-- The gap after a toast drawn in a style (screen units): the style's own
-- gap, else GAP, sized with the toasts
local function GapOf(def)
    return ((def and def.gap) or GAP) * Scale()
end

-- Centre offsets from the anchor for a list of extents: the first toast on
-- the anchor, each next one past the last by half of each plus the larger
-- of the two toasts' gaps (gaps nil = GAP). d = a GROW entry (nil = the
-- player's). The Toast Lab stacks its preview with this too.
local function Offsets(extents, gaps, d)
    d = d or GrowDir()
    local out, pos = {}, 0
    for i, e in ipairs(extents) do
        if i > 1 then
            local g = gaps and math.max(gaps[i - 1] or GAP, gaps[i] or GAP) or GAP
            pos = pos + extents[i - 1] / 2 + g + e / 2
        end
        out[i] = { d[1] * pos, d[2] * pos }
    end
    return out
end
T.Offsets, T.GROW = Offsets, GROW

-- ── Toast frames ────────────────────────────────────────────────────────────
-- _x / _y are screen units from the anchor; the frame is scaled, so its
-- SetPoint offsets are divided by the scale
local function Place(f)
    local s = f:GetScale()
    f:ClearAllPoints()
    -- _x / _y are the centre of the toast with its rows: the toast sits half
    -- the rows' height above it, or half their width back from the grow
    -- direction when they sit beside it (Left / Right)
    local up = (f._rowsH or 0) / 2
    local back = -GrowDir()[1] * (f._rowsW or 0) / 2
    -- Every offset is screen units, so all of it is divided by the toast's scale
    f:SetPoint("CENTER", UIParent, "CENTER", (_ax + f._x + back) / s, (_ay + f._y + up) / s)
end

local Remove   -- forward: the click handlers close the toast
local CLOSE_SZ = 18   -- the hover close X

-- Show on top of all windows (toastOnTop, ALL-396): one strata over the
-- DIALOG windows (Settings, Reference Box, Note Settings). The right-click
-- menu is FULLSCREEN_DIALOG too and raises itself when it opens
local function ToastStrata()
    return Setting("toastOnTop") and "FULLSCREEN_DIALOG" or "DIALOG"
end

local function CreateToast()
    local f = BNB.CreateBackdropFrame("Button", nil, UIParent)
    f:SetFrameStrata("DIALOG")
    f:SetClampedToScreen(true)
    f:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    f:Hide()
    BNB.ToastStyles.Build(f)

    f:SetScript("OnClick", function(self, btn)
        local spec = self._spec
        if not spec or self._leaving then return end
        if btn == "RightButton" then
            if spec.onRightClick then T._menuFor = self; spec.onRightClick(spec, self); return end
        elseif spec.onClick then
            securecallfunction(spec.onClick, spec)
        end
        Remove(self)
    end)

    -- Close X, top right, shown while the pointer is over the toast (the
    -- driver's Tick): the quick way to clear one (Dukul, 2026-10-08).
    -- spec.onClose runs first (an alarm toast dismisses its alarm)
    local x = BNB.CreateIconButton(f, CLOSE_SZ, "close", {
        onClick = function()
            local spec = f._spec
            if not spec or f._leaving then return end
            if spec.onClose then securecallfunction(spec.onClose, spec) end
            if not f._leaving then Remove(f) end
        end })
    x:SetPoint("TOPRIGHT", f, "TOPRIGHT", -2, -2)
    x:SetFrameLevel(f:GetFrameLevel() + 20)
    x:Hide()
    f._closeX = x
    return f
end

-- The rows box and the "+N" box: plain like a default sticky note in normal
-- mode, the skin preset's colours in skin mode (Dukul, 2026-10-11)
local function PaintBox(fr)
    if BigNoteBoxDB and BigNoteBoxDB.skinMode and BNB.GetSkinPreset then
        local p = BNB.GetSkinPreset()
        local r, g, b = BNB.SkinColourOf(p)
        local br, bg, bb, ba = BNB.SkinBorderOf(p)
        BNB.SetBackdrop(fr, r, g, b, BNB.GetSkinBgAlpha(), br, bg, bb, ba)
    else
        BNB.SetBackdrop(fr, 0.07, 0.07, 0.09, 0.96, 0.35, 0.35, 0.38, 1)
    end
end

-- ── Rows (the grouped toast) ────────────────────────────────────────────────
local function RowsBox(f)
    if not f._rowsBox then f._rowsBox = BNB.CreateBackdropFrame("Frame", nil, f) end
    return f._rowsBox
end

local function GetRow(f, i)
    f._rowFrames = f._rowFrames or {}
    local row = f._rowFrames[i]
    if row then return row end
    row = CreateFrame("Button", nil, RowsBox(f))
    row:SetHeight(ROW_H)
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    local hi = row:CreateTexture(nil, "ARTWORK")
    hi:SetAllPoints(); hi:SetColorTexture(0.25, 0.40, 0.25, 0.4)
    hi:Hide()
    row._hi = hi
    local tag = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    tag:SetPoint("RIGHT", row, "RIGHT", -8, 0)
    tag:SetJustifyH("RIGHT"); tag:SetWordWrap(false)
    tag:SetTextColor(0.55, 0.55, 0.55)
    row._tag = tag
    local lbl = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    lbl:SetPoint("LEFT", row, "LEFT", 8, 0)
    lbl:SetPoint("RIGHT", tag, "LEFT", -4, 0)
    lbl:SetJustifyH("LEFT"); lbl:SetWordWrap(false)
    row._lbl = lbl
    row:SetScript("OnEnter", function(self) self._hi:Show() end)
    row:SetScript("OnLeave", function(self) self._hi:Hide() end)
    row:SetScript("OnClick", function(self, btn)
        local r = self._row
        if not r or f._leaving then return end
        if btn == "RightButton" then
            if r.onRightClick then T._menuFor = f; r.onRightClick(self, f); return end
        elseif r.onClick then
            securecallfunction(r.onClick, r)
        end
        Remove(f)
    end)
    f._rowFrames[i] = row
    return row
end

-- Down / Up: the rows hang under the toast. Left / Right (ALL-438): they sit
-- beside it, on the far side in the grow direction, so the toast stays in
-- line with the others and the rows are a box of their own at the end
local function FillRows(f, rows)
    local n = rows and math.min(#rows, MAX_ROWS) or 0
    local dx = GrowDir()[1]
    local w = f:GetWidth()
    local box = RowsBox(f)
    box:ClearAllPoints()
    if dx > 0 then
        box:SetPoint("TOPLEFT", f, "TOPRIGHT", GAP, 0)
    elseif dx < 0 then
        box:SetPoint("TOPRIGHT", f, "TOPLEFT", -GAP, 0)
    else
        box:SetPoint("TOPLEFT", f, "BOTTOMLEFT", 0, -ROWS_GAP)
    end
    box:SetSize(w, n * ROW_H + 2 * ROWS_PAD)
    box:SetShown(n > 0)
    if n > 0 then PaintBox(box) end
    for i = 1, n do
        local r, row = rows[i], GetRow(f, i)
        row._row = r
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", box, "TOPLEFT", ROWS_PAD, -ROWS_PAD - (i - 1) * ROW_H)
        row:SetPoint("TOPRIGHT", box, "TOPRIGHT", -ROWS_PAD, -ROWS_PAD - (i - 1) * ROW_H)
        row._lbl:SetText(r.title or "")
        local tc = r.titleColor
        if tc then row._lbl:SetTextColor(tc.r or 1, tc.g or 1, tc.b or 1)
        else row._lbl:SetTextColor(0.85, 0.85, 0.85) end
        row._tag:SetText(r.tag or "")
        row:Show()
    end
    for i = n + 1, #(f._rowFrames or {}) do f._rowFrames[i]:Hide() end
    -- Screen units: the rows are children of the scaled toast. _rowsH = what
    -- they add below the toast, _rowsW = what they add beside it
    local s = f:GetScale()
    f._rowsH = (dx == 0 and n > 0) and (ROWS_GAP + n * ROW_H + 2 * ROWS_PAD) * s or 0
    f._rowsW = (dx ~= 0 and n > 0) and (GAP + w) * s or 0
end

-- Style and content from the spec; keepTime = a restyle, not a new message
local function Fill(f, spec, keepTime)
    local TS = BNB.ToastStyles
    f._spec = spec
    f:SetScale(Scale())
    TS.Apply(f, TS.Resolve(spec.style or TS.Current()))
    TS.Fill(f, spec)
    FillRows(f, spec.rows)
    if not keepTime then f._elapsed = 0 end
    f._hold = HoldTime(spec)
    if f._hold > 0 then f._hold = f._hold + (f._burstExtra or 0) end
    local bar = f._bar
    if f._barW and f._hold > 0 then
        local frac = 1 - math.min((f._elapsed or 0) / f._hold, 1)
        bar:SetWidth(math.max(0.01, f._barW * frac))
        bar:SetColorTexture(0.3, 0.75, 0.3, 0.9)
        bar:Show()
    else
        bar:Hide()
    end
end

-- Queued toasts: a "+N" box of its own in the next slot after the last toast
-- (Dukul, 2026-10-11, was a label on the last toast). The queue comes in one
-- toast at a time as room frees, and N counts down
local function PlaceMore()
    local box, last = _moreBox, _shown[#_shown]
    if not (box and box:IsShown() and last and last._tx) then return end
    local d, s = GrowDir(), box:GetScale()
    local ext = (d[1] ~= 0) and box:GetWidth() * s or box:GetHeight() * s
    local pos = (last._ext or 0) / 2 + GapOf(last._style) + ext / 2
    box:ClearAllPoints()
    box:SetPoint("CENTER", UIParent, "CENTER",
        (_ax + last._tx + d[1] * pos) / s, (_ay + last._ty + d[2] * pos) / s)
end

local function UpdateMore()
    for _, f in ipairs(_shown) do f._more:Hide() end
    if #_queue == 0 or #_shown == 0 then
        if _moreBox then _moreBox:Hide() end
        return
    end
    local box = _moreBox
    if not box then
        box = BNB.CreateBackdropFrame("Frame", nil, UIParent)
        box:SetClampedToScreen(true)
        box._text = box:CreateFontString(nil, "OVERLAY", "BNBFontHighlight")
        box._text:SetPoint("CENTER")
        box._text:SetTextColor(0.9, 0.9, 0.9)
        _moreBox = box
    end
    box:SetScale(Scale())
    box:SetFrameStrata(ToastStrata())
    PaintBox(box)
    box._text:SetText(string.format(L["TOAST_MORE_BOX"], #_queue))
    box:SetSize(math.max(ROW_H + 10, box._text:GetStringWidth() + 18), ROW_H + 6)
    box:Show()
    PlaceMore()
end

-- Every toast's slot; with Slide in off (or now) they jump there
local function Retarget(now)
    local ext, gaps = {}, {}
    for i, f in ipairs(_shown) do
        local w, h = f:GetWidth() * f:GetScale(), f:GetHeight() * f:GetScale()
        ext[i] = Extent(w + (f._rowsW or 0), h + (f._rowsH or 0))
        f._ext = ext[i]
        gaps[i] = GapOf(f._style)
    end
    local slide = Setting("toastSlide") and not now
    for i, o in ipairs(Offsets(ext, gaps)) do
        local f = _shown[i]
        f._tx, f._ty = o[1], o[2]
        if not slide or f._x == nil then f._x, f._y = f._tx, f._ty; Place(f) end
    end
    PlaceMore()
end

-- ── The driver: slide and countdown, one OnUpdate for every toast ──────────
local function MouseOverAny()
    if T._menuFor and BNB.ContextMenu and BNB.ContextMenu.IsOpen() then return true end
    for _, f in ipairs(_shown) do
        if not f._delay and f:IsMouseOver() then return true end
        for _, row in ipairs(f._rowFrames or {}) do
            if row:IsShown() and row:IsMouseOver() then return true end
        end
    end
    return false
end

-- One toast's frame of the driver: close X on hover, slide, countdown
local function TickOne(f, dt, k, paused)
    local x = f._closeX
    if x then
        local over = f:IsMouseOver() or (x:IsShown() and x:IsMouseOver())
        if over ~= x:IsShown() then x:SetShown(over) end
    end
    if f._x ~= f._tx or f._y ~= f._ty then
        f._x = f._x + (f._tx - f._x) * k
        f._y = f._y + (f._ty - f._y) * k
        if math.abs(f._tx - f._x) < 0.5 and math.abs(f._ty - f._y) < 0.5 then
            f._x, f._y = f._tx, f._ty
        end
        Place(f)
    end
    if not paused and f._hold > 0 then
        f._elapsed = f._elapsed + dt
        if f._barW then
            local frac = 1 - math.min(f._elapsed / f._hold, 1)
            f._bar:SetWidth(math.max(0.01, f._barW * frac))
            if frac > 0.5 then     f._bar:SetColorTexture(0.3, 0.75, 0.3, 0.9)
            elseif frac > 0.2 then f._bar:SetColorTexture(0.85, 0.70, 0.2, 0.9)
            else                   f._bar:SetColorTexture(0.85, 0.25, 0.2, 0.9) end
        end
        if f._elapsed >= f._hold then Remove(f) end
    end
end

local function Tick(self, dt)
    if #_shown == 0 then self:SetScript("OnUpdate", nil); return end
    local paused = MouseOverAny()
    local k = math.min(1, dt * SLIDE_RATE)
    -- Backwards: a toast that runs out is removed from _shown here
    for i = #_shown, 1, -1 do
        local f = _shown[i]
        -- A burst toast waiting its turn: in its slot, unseen, not counting
        if f._delay then
            f._delay = f._delay - dt
            if f._delay <= 0 then
                f._delay = nil
                BNB.FadeTo(f, 0, 1, FADE)
            end
        end
        if not f._delay then TickOne(f, dt, k, paused) end
    end
end

local function StartDriver()
    _driver = _driver or CreateFrame("Frame", nil, UIParent)
    _driver:SetScript("OnUpdate", Tick)
end

-- ── Show / remove ───────────────────────────────────────────────────────────
-- toastSound: nil / "silent" = none, else an alarm sound key. Once per burst
-- of toasts, not once per toast
local _lastSound = 0
local function PlayToastSound()
    local key = Setting("toastSound")
    if not key or key == "silent" or GetTime() - _lastSound < 1 then return end
    local path = BNB.Alarm and BNB.Alarm.SoundPath and BNB.Alarm.SoundPath(key)
    if path then
        _lastSound = GetTime()
        PlaySoundFile(path, "Master")
    end
end
T.PlaySound = PlayToastSound

local function Add(spec)
    local f = table.remove(_pool) or CreateToast()
    local now = GetTime()
    _burstN = (now - _burstAt < BURST_WINDOW) and math.min(_burstN + 1, 9) or 0
    _burstAt = now
    f._burstExtra = _burstN * BURST_STEP
    f._delay = (_burstN > 0) and _burstN * BURST_STAGGER or nil
    Fill(f, spec)
    f._x, f._y = nil, nil
    _shown[#_shown + 1] = f
    Retarget()
    -- The new toast starts out past its slot and slides in
    if Setting("toastSlide") then
        local d = GrowDir()
        f._x, f._y = f._tx + d[1] * SLIDE_PX, f._ty + d[2] * SLIDE_PX
    end
    f._leaving = nil
    Place(f)
    f:SetFrameStrata(ToastStrata())
    f:Show()
    f:Raise()
    -- A note's portrait again, now that the toast is shown (ALL-434)
    if spec.iconSetup then BNB.ToastStyles.FillIcon(f, spec) end
    if f._delay then f:SetAlpha(0) else BNB.FadeTo(f, 0, 1, FADE) end
    StartDriver()
    if not spec.silent then PlayToastSound() end
end

local function PullQueue()
    while #_shown < MaxShown() and #_queue > 0 do
        Add(table.remove(_queue, 1))
    end
    UpdateMore()
end

Remove = function(f)
    for i, s in ipairs(_shown) do
        if s == f then table.remove(_shown, i); break end
    end
    f._leaving, f._delay = true, nil
    f._more:Hide()
    if f._closeX then f._closeX:Hide() end
    BNB.FadeTo(f, f:GetAlpha(), 0, FADE, function()
        f:Hide()
        f._spec, f._leaving = nil, nil
        _pool[#_pool + 1] = f
    end)
    Retarget()
    PullQueue()
end

local function ReplaceKeyed(list, spec)
    for i, s in ipairs(list) do
        if s.key == spec.key then list[i] = spec; return true end
    end
    return false
end

function T.Show(spec)
    if not spec then return end
    if not (BNB.ToastsEnabled() and BNB.ToastSourceOn(spec.source)) then return end
    if spec.key then
        -- Already on screen: same toast, new content, timer from the start
        for _, f in ipairs(_shown) do
            if f._spec and f._spec.key == spec.key then
                Fill(f, spec); Retarget(); return
            end
        end
        if ReplaceKeyed(_queue, spec) or ReplaceKeyed(_waitCombat, spec)
            or ReplaceKeyed(_waitIntro, spec) then return end
    end
    -- Every toast waits for the Explorer welcome (Dukul, 2026-10-22)
    if not spec.force and BNB.ExplorerIntroHolding and BNB.ExplorerIntroHolding() then
        _waitIntro[#_waitIntro + 1] = spec; return
    end
    if not spec.force and InCombat() then
        local mode = Setting("toastCombat")
        if mode == "drop" then return end
        if mode ~= "show" then _waitCombat[#_waitCombat + 1] = spec; return end
    end
    _ax, _ay = AnchorXY()
    if #_shown < MaxShown() then Add(spec) else _queue[#_queue + 1] = spec end
    UpdateMore()
end

BNB.RegisterEvent("PLAYER_REGEN_ENABLED", function()
    if #_waitCombat == 0 then return end
    local list = _waitCombat
    _waitCombat = {}
    for _, spec in ipairs(list) do T.Show(spec) end
end)

-- The Explorer welcome was answered: what waited for it, in order
function T.ReleaseHeld()
    if #_waitIntro == 0 then return end
    local list = _waitIntro
    _waitIntro = {}
    for _, spec in ipairs(list) do T.Show(spec) end
end

local function Keep(list, test)
    local out = {}
    for _, s in ipairs(list) do if not test(s) then out[#out + 1] = s end end
    return out
end

function T.Dismiss(key)
    if not key then return end
    local function Match(s) return s.key == key end
    _queue, _waitCombat = Keep(_queue, Match), Keep(_waitCombat, Match)
    _waitIntro = Keep(_waitIntro, Match)
    for i = #_shown, 1, -1 do
        local f = _shown[i]
        if f._spec and f._spec.key == key then Remove(f) end
    end
    UpdateMore()
end

-- source nil = every toast
function T.DismissAll(source)
    local function Match(s) return source == nil or s.source == source end
    _queue, _waitCombat = Keep(_queue, Match), Keep(_waitCombat, Match)
    _waitIntro = Keep(_waitIntro, Match)
    for i = #_shown, 1, -1 do
        local f = _shown[i]
        if f._spec and Match(f._spec) then Remove(f) end
    end
    UpdateMore()
end

-- After a settings change (grow direction, Max shown, Slide in, position)
function T.Relayout()
    _ax, _ay = AnchorXY()
    -- Fewer allowed than on screen: the newest go back to the queue front
    while #_shown > MaxShown() do
        local f = _shown[#_shown]
        table.insert(_queue, 1, f._spec)
        Remove(f)
    end
    -- Rows go under or beside a toast by grow direction (ALL-438)
    for _, f in ipairs(_shown) do
        if f._spec then FillRows(f, f._spec.rows) end
    end
    Retarget(true)
    PullQueue()
end

-- After a style or scale change: every toast on screen redrawn in place
function T.Restyle()
    for _, f in ipairs(_shown) do
        if f._spec then Fill(f, f._spec, true) end
    end
    Retarget(true)
    UpdateMore()
    T.RefreshAnchor()
end

-- A note toast's unit face follows the target, as the note list row does
-- (ALL-434). The situation toast for a player fires the moment they are
-- targeted, before the game has their portrait, so it kept the note's own
-- icon (Dukul, 2026-10-10: a KOS toast showed the Human male race icon).
-- UNIT_PORTRAIT_UPDATE says the portrait is ready; a target change puts the
-- face on or takes it off, and once more a moment later in case the portrait
-- event does not come. Only toasts on screen whose spec draws a note icon.
local function RedrawUnitIcons()
    for _, f in ipairs(_shown) do
        local spec = f._spec
        if spec and spec.iconSetup and not f._leaving then BNB.ToastStyles.FillIcon(f, spec) end
    end
end
BNB.RegisterEvent("UNIT_PORTRAIT_UPDATE", function(_, unit)
    if unit == "target" and #_shown > 0 then RedrawUnitIcons() end
end)
BNB.RegisterEvent("PLAYER_TARGET_CHANGED", function()
    if #_shown == 0 then return end
    RedrawUnitIcons()
    C_Timer.After(0.3, RedrawUnitIcons)
end)

function T.Count() return #_shown, #_queue, #_waitCombat end

-- The skin style follows the skin preset; skin mode off falls back to plain
BNB.RegisterMessage("Toast", "SkinChanged", function() T.Restyle() end)

-- ── The anchor: where the first toast sits ──────────────────────────────────
-- The size of a toast in the player's style, drawn as a plain box exactly
-- the toast's size (normal mode: transparent black with a grey border; skin
-- mode: the preset's body and border), with ghosts of the next two slots so
-- the grow direction shows. Drag to move; Lock (in the middle)
-- or a right-click saves; Reset puts back the default.
local _anchor

-- Developer tools > "Print toast anchor position" (debug mode): the saved
-- offset after a drag, for finding a better default
local function PrintAnchorPos(x, y)
    if not (BigNoteBoxDB and BigNoteBoxDB.debugToastAnchor and BNB.IsDebugMode and BNB.IsDebugMode()) then return end
    local sw, sh = UIParent:GetSize()
    BNB:Print(string.format("|cff88bbffToast anchor:|r popupAnchorX = %d, popupAnchorY = %d  (CENTER of UIParent; screen %d x %d, UI scale %.2f)",
        x, y, math.floor(sw + 0.5), math.floor(sh + 0.5), UIParent:GetEffectiveScale()))
end

local function SaveAnchor(f)
    local cx, cy   = f:GetCenter()
    local scx, scy = UIParent:GetCenter()
    if not (cx and scx) then return end
    local x = math.floor(cx - scx + 0.5)
    local y = math.floor(cy - scy + 0.5)
    f:ClearAllPoints()
    f:SetPoint("CENTER", UIParent, "CENTER", x, y)
    if BigNoteBoxDB then
        BigNoteBoxDB.popupAnchorX = x
        BigNoteBoxDB.popupAnchorY = y
    end
    T.Relayout()
end

local function DressBox(box, alpha)
    if BigNoteBoxDB and BigNoteBoxDB.skinMode then
        local p = BNB.GetSkinPreset()
        local r, g, b    = BNB.SkinColourOf(p)
        local br, bg, bb, ba = BNB.SkinBorderOf(p)
        BNB.SetBackdrop(box, r, g, b, BNB.GetSkinBgAlpha() * alpha, br, bg, bb, ba * alpha)
    else
        BNB.SetBackdrop(box, 0, 0, 0, 0.6 * alpha, 0.55, 0.55, 0.55, alpha)
    end
end

function T.RefreshAnchor()
    for _, t in ipairs(_shown) do t:SetFrameStrata(ToastStrata()) end
    local f = _anchor
    if not f then return end
    f:SetFrameStrata(ToastStrata())
    local def  = BNB.ToastStyles.Resolve(BNB.ToastStyles.Current())
    local w, h = StyleSize(def)
    f:SetSize(w, h)
    DressBox(f, 0.9)
    local key = Setting("toastGrow")
    if not GROW[key] then key = "down" end
    f._arrow:SetTexture(string.format(ARROW, key))
    local g = GapOf(def)
    local offs = Offsets({ Extent(w, h), Extent(w, h), Extent(w, h) }, { g, g, g })
    for i, g in ipairs(f._ghosts) do
        g:SetSize(w, h)
        DressBox(g, 0.45 - i * 0.12)
        g:ClearAllPoints()
        g:SetPoint("CENTER", f, "CENTER", offs[i + 1][1], offs[i + 1][2])
    end
end

local function NewBox(parent, name)
    return BNB.CreateBackdropFrame("Frame", name, parent)
end

local function CreateAnchor()
    if _anchor then return _anchor end
    local f = NewBox(UIParent, "BigNoteBoxToastAnchor")
    f:SetFrameStrata("DIALOG")
    f:SetToplevel(true)
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:Hide()

    local arrow = f:CreateTexture(nil, "ARTWORK")
    arrow:SetSize(26, 26)
    arrow:SetPoint("LEFT", f, "LEFT", 10, 0)
    f._arrow = arrow

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("BOTTOM", f, "CENTER", 0, 12)
    title:SetText(L["TOAST_ANCHOR_TITLE"])
    BNB.SetHeaderColor(title)

    -- Lock in the middle (Dukul, ALL-160), Reset beside it
    local lock = BNB.CreateButton(nil, f, L["POPANCHOR_LOCK"], 56, 20)
    lock:SetPoint("CENTER", f, "CENTER", 0, -2)
    lock:SetScript("OnClick", function() T.LockAnchor() end)
    local reset = BNB.CreateButton(nil, f, L["TOAST_ANCHOR_RESET"], 56, 20)
    reset:SetPoint("LEFT", lock, "RIGHT", 4, 0)
    reset:SetScript("OnClick", function() T.ResetAnchor() end)

    -- Ghosts of the next two toasts: the stack grows that way
    f._ghosts = {}
    for i = 1, 2 do f._ghosts[i] = NewBox(f) end

    f:SetScript("OnDragStart", function(self) BNB.StartDragMoving(self) end)
    f:SetScript("OnDragStop", function(self)
        BNB.StopDragMoving(self)
        SaveAnchor(self)
        PrintAnchorPos(AnchorXY())
    end)
    f:SetScript("OnMouseUp", function(_, btn)
        if btn == "RightButton" then T.LockAnchor() end
    end)
    BNB.SetMoveCursor(f)   -- ALL-95

    f:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(L["TOAST_ANCHOR_TITLE"], 1, 0.82, 0)
        GameTooltip:AddLine(L["TOAST_ANCHOR_TIP"], 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    f:SetScript("OnLeave", function() GameTooltip:Hide() end)

    _anchor = f
    return f
end

function T.ToggleAnchor()
    if not BNB.ToastsEnabled() then return end
    local f = CreateAnchor()
    if f:IsShown() then T.LockAnchor(); return end
    f:ClearAllPoints()
    f:SetPoint(T.AnchorPoint())
    T.RefreshAnchor()
    f:Show()
    f:Raise()
end

function T.LockAnchor()
    if not (_anchor and _anchor:IsShown()) then return end
    SaveAnchor(_anchor)
    _anchor:Hide()
    BNB:Print(L["POPANCHOR_SAVED"])
end

function T.ResetAnchor()
    if BigNoteBoxDB then
        -- Back to the default, which follows the screen shape (AnchorXY)
        BigNoteBoxDB.popupAnchorX = nil
        BigNoteBoxDB.popupAnchorY = nil
    end
    if _anchor then
        _anchor:ClearAllPoints()
        _anchor:SetPoint(T.AnchorPoint())
    end
    T.Relayout()
end

-- Switched off: every toast goes, queued and combat-held ones too, and an
-- open anchor saves where it is and closes. On: nothing to do, the next
-- toast shows as usual
function BNB.ApplyToastsModule(on)
    if on then return end
    T.DismissAll()
    if BNB.Alarm and BNB.Alarm.ToastsOff then BNB.Alarm.ToastsOff() end   -- ALL-385
    if _anchor and _anchor:IsShown() then SaveAnchor(_anchor); _anchor:Hide() end
end

-- One sender switched (Settings > Modules > Toasts): its toasts go
function BNB.ApplyToastSource(source, on)
    if not on then T.DismissAll(source) end
    if not on and source == "alarms" and BNB.Alarm and BNB.Alarm.ToastsOff then BNB.Alarm.ToastsOff() end
end

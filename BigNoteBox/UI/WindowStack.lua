-- BigNoteBox UI/WindowStack.lua
-- One stacking order for the BigNoteBox windows that share a strata (ALL-564).
-- The main window, the big windows (Settings, Note Settings, Reference Box,
-- the side windows, Help book, ...) and the sticky notes all sit in MEDIUM,
-- and the one clicked last is in front.
--
-- On top of SetToplevel. The game orders clicked toplevel windows by a
-- raised level of its own (GetRaisedFrameLevel, 10.2.5): Raise leaves
-- GetFrameLevel as it is. Members keep SetToplevel, or every Blizzard panel
-- stays over them (LE12, 2026-10-25: probe CharacterFrame frame level 1,
-- raised 5; ours level 1, raised 0, not toplevel). But child frames still
-- draw by frame level: a window whose buttons sit +10..+100 levels up (the
-- main window's sidebar, the note list's tag list) drew through the window
-- raised over it (the rich preview, 2026-10-04; stickies, ALL-198). So the
-- shown members also get frame level bands in the same order as their raised
-- levels, each as deep as its own child frames: two windows never share a
-- level, and both orders agree on which one is in front.
--
-- Public API:
--   BNB.StackWindow(f)           make f a member: SetToplevel, a click
--                                anywhere in it or a Show brings it in front,
--                                and f:Raise() goes through the stack
--   BNB.StackUnder(owner, strip) a strip drawn just under its window (side
--                                tabs that hang outside it); strip nil = none.
--                                The strip goes into the owner's strata
--   BNB.StackRaise(f)            bring f in front of the other members
-- Members are stacked per strata: a window seated over Focus mode
-- (FULLSCREEN_DIALOG) or a "Keep above" sticky (HIGH) stacks with the others
-- in that strata. Dialogs and pickers are not members; they stay one strata
-- up (DIALOG) with SetToplevel alone.

local BNB = BigNoteBox
if not BNB then return end

local MAX_LEVEL = 9000   -- below the game's 10000 cap, with room for children

local _member = {}   -- frame -> the game's own Raise (called before the stack)
local _under  = {}   -- owner -> strip drawn just under it
local _isUnder = {}  -- strip -> true (left out of its owner's depth)
local _depth, _depthAt = {}, {}

-- How far a frame's children reach above it in its strata, hidden ones
-- included (a list that opens later must not reach the next window).
-- A depth is relative, so moving a frame keeps it. Cached for the current
-- frame: BringAllToFront raises every sticky at once.
local function TopOf(f, strata, top)
    local n = f:GetNumChildren()
    if n == 0 then return top end
    local kids = { f:GetChildren() }
    for i = 1, n do
        local c = kids[i]
        if not _isUnder[c] and c:GetFrameStrata() == strata then
            local l = c:GetFrameLevel()
            if l > top then top = l end
            top = TopOf(c, strata, top)
        end
    end
    return top
end
local function Depth(f)
    local now = GetTime()
    if _depthAt[f] ~= now then
        local lvl = f:GetFrameLevel()
        _depth[f] = TopOf(f, f:GetFrameStrata(), lvl) - lvl
        _depthAt[f] = now
    end
    return _depth[f]
end

-- The levels one member takes: its strip, then itself and its children
local function Band(f)
    local b = Depth(f) + 1
    local s = _under[f]
    if s and s:IsShown() then b = b + Depth(s) + 1 end
    return b
end

-- Strip first, then the window; returns the next free level
local function Place(f, lvl)
    local s = _under[f]
    if s and s:IsShown() then
        local sd = Depth(s)
        f:SetFrameLevel(lvl + sd + 1)
        s:SetFrameLevel(lvl)   -- after the owner: setting the owner moves its children
        lvl = lvl + sd + 1
    else
        f:SetFrameLevel(lvl)
    end
    return lvl + Depth(f) + 1
end

function BNB.StackRaise(top)
    local orig = _member[top]
    if not orig then return end
    -- The game's raise first, so the window also comes over other addons'
    -- windows in its strata; then the members are spread out under it
    pcall(orig, top)
    if not top:IsShown() then return end
    local strata = top:GetFrameStrata()
    local list = {}
    for m in pairs(_member) do
        if m ~= top and m:IsVisible() and m:GetFrameStrata() == strata then list[#list + 1] = m end
    end
    -- The game's order: raised level (last raised highest), then frame level
    table.sort(list, function(a, b)
        local ra, rb = a:GetRaisedFrameLevel(), b:GetRaisedFrameLevel()
        if ra ~= rb then return ra < rb end
        return a:GetFrameLevel() < b:GetFrameLevel()
    end)
    local need = 0
    for _, m in ipairs(list) do need = need + Band(m) end
    -- Start at the lowest frame level among them (Raise does not change a
    -- frame level), from the bottom when that runs past the cap
    local lvl = top:GetFrameLevel()
    for _, m in ipairs(list) do
        local l = m:GetFrameLevel()
        if l < lvl then lvl = l end
    end
    if lvl < 1 or lvl + need + Band(top) > MAX_LEVEL then lvl = 1 end
    for _, m in ipairs(list) do lvl = Place(m, lvl) end
    Place(top, lvl)
end

local function RaiseSelf(self) BNB.StackRaise(self) end

function BNB.StackWindow(f)
    if _member[f] then return end
    _member[f] = f.Raise   -- the frame type's own method
    f:SetToplevel(true)    -- the game's raise on a click (see the top of this file)
    f.Raise = RaiseSelf    -- every f:Raise() in the addon goes through the stack
    -- In front when shown. A child's OnShow, not the window's own: a later
    -- SetScript("OnShow") on the window would drop a hook (the main window
    -- sets its OnShow after it is stacked)
    local watch = CreateFrame("Frame", nil, f)
    watch:SetScript("OnShow", function() BNB.StackRaise(f) end)
end

function BNB.StackUnder(owner, strip)
    local old = _under[owner]
    if old == strip then
        if strip then strip:SetFrameStrata(owner:GetFrameStrata()) end
        return
    end
    if old then _isUnder[old] = nil end
    _under[owner] = strip
    if strip then
        _isUnder[strip] = true
        strip:SetFrameStrata(owner:GetFrameStrata())
        if owner:IsShown() then BNB.StackRaise(owner) end
    end
end

-- A click anywhere in a member (a button in it too): the game raises it
-- (SetToplevel); the bands follow here. On mouse down, before any OnClick
-- opens another window; StackRaise raises it itself first, so the order is
-- right whether the game's raise comes before or after this event.
local function MemberUnder()
    -- GetMouseFoci is on every client (the API dumps); GetMouseFocus is gone
    local foci = GetMouseFoci()
    local f = foci and foci[1]
    while f do
        -- A forbidden frame (the shop's buttons) errors on any method but
        -- IsForbidden, and holds none of ours (ALL-612)
        if f:IsForbidden() then return end
        if _member[f] then return f end
        f = f:GetParent()
    end
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("GLOBAL_MOUSE_DOWN")
ev:SetScript("OnEvent", function()
    local f = MemberUnder()
    if f then BNB.StackRaise(f) end
end)

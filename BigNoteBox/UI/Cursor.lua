-- BigNoteBox UI/Cursor.lua -- Game cursors on drag handles (ALL-95)
--
-- Hovering something you can drag shows what the drag does: move on title
-- bars, resize on grips, a grabbing hand while a note is carried, a lock on
-- the text of a locked note. Retail uses the silver cursors, Forever the gold
-- ones (Dukul, 2026-09-27).
--
-- SetCursor only reads the game's own files: any file in an addon folder
-- (TGA or BLP, with or without extension) draws as a black box, and so does a
-- missing game file (Retail, probed 2026-09-27). So every cursor here is a
-- game cursor. The game has two sets, each sheet holding a gold cell and a
-- silver "Unable" cell: Interface/Cursor/Crosshair/* (names ending in
-- .crosshair) and Interface/Cursor/UICursor*2x (plain names). The name to ask
-- for is the cell name from the atlas data, and some are odd: the silver
-- resize is UnableUI-Cursor-UI-Cursor-SizeRight, the silver size
-- UnableUI-Cursor_size. Dukul's TGAs in Assets/Cursor/ cannot be cursors.
--
-- SetCursor only lasts while something under the mouse holds it, so the
-- cursor is set in OnEnter and cleared in OnLeave; a bare /run SetCursor only
-- blinks.
--
-- PUBLIC API:
--   BNB.CursorPath(kind)           path for this client; kind = a CURSORS key,
--                                  a { gold, silver } table or a raw path
--   BNB.SetHoverCursor(frame, kind, heldKind)
--       Shows the cursor while the mouse is over frame, and keeps it while the
--       left button is held (a drag) until release. kind may be a function
--       (frame) -> kind or nil, checked on every enter (nil = no cursor).
--       heldKind (optional) replaces it while any mouse button is held (the
--       Reference Box model: open hand, grabbing hand while rotating).
--       Calling it again only changes the kinds. Uses HookScript: a later
--       SetScript on OnEnter / OnLeave / OnMouseDown / OnMouseUp removes it.
--   BNB.SetMoveCursor(frame)       move cursor while frame can drag (it has an
--                                  OnDragStart script and takes the mouse)
--   BNB.AddTitleMoveCursor(f)      move cursor over the title band of a window
--                                  that drags anywhere (normal-mode windows;
--                                  called by BNB.SeatChrome)
--   BNB.ShowCursor(kind) / BNB.ClearCursor()   set by code (the note drag)
--   BNB.ShowLinkCursor(frame) / BNB.HideLinkCursor(frame)
--                                  link cursor over a link in frame (ALL-489);
--                                  ShowLinkCursor(frame, link) shows the
--                                  waypoint / item / note / url cursor for
--                                  those links (ALL-492)
--   BNB.OpenCursorTest()           test window, Developer Tools (debug mode)
--------------------------------------------------------------------------------

local BNB = BigNoteBox
local L = BNB.L

local GAME = "Interface/CURSOR/"

-- Picked by Dukul in the Cursor Test window on Retail, 2026-09-27. gold =
-- Forever, silver = Retail; the hands and the lock use the gold cell on both
-- (Dukul: "use the one used in Forever on retail too"), and so does Size,
-- whose silver cell is the dark "inactive" look. Splitters use Size.
-- classic = the Classic clients (Era, Anniversary, MoP), whose cursor files
-- are the old single ones (Dukul, 2026-10-07, ALL-369): Resize left is
-- UI-Cursor-Size there, so Size uses it too; the hands are the quest ones.
local CURSORS = {
    move      = { gold = GAME .. "UI-Cursor-Move",
                  silver = GAME .. "UnableUI-Cursor-Move",
                  classic = GAME .. "UI-Cursor-Move" },
    resize    = { gold = GAME .. "UI-Cursor-SizeRight.crosshair",
                  silver = GAME .. "UnableUI-Cursor-UI-Cursor-SizeRight.crosshair",
                  classic = GAME .. "UI-Cursor-SizeRight" },
    resizeL   = { gold = GAME .. "UI-Cursor-SizeLeft",
                  silver = GAME .. "UnableUI-Cursor-SizeLeft",
                  classic = GAME .. "UI-Cursor-Size" },
    size      = { gold = GAME .. "UI-Cursor-Size.crosshair",
                  silver = GAME .. "UI-Cursor-Size.crosshair",
                  classic = GAME .. "UI-Cursor-Size" },
    grab      = { gold = GAME .. "GrabbingHand", silver = GAME .. "GrabbingHand",
                  classic = GAME .. "QuestInteract" },
    -- Plain HoldingHand, not .crosshair, as the open hand (Dukul, 2026-10-17)
    hold      = { gold = GAME .. "HoldingHand",
                  silver = GAME .. "HoldingHand",
                  classic = GAME .. "UnableQuestInteract" },
    -- Plain OpenHand, not .crosshair: that one sat off the pointer (Dukul,
    -- 2026-10-17)
    open      = { gold = GAME .. "OpenHand", silver = GAME .. "OpenHand",
                  classic = GAME .. "OpenHand" },
    lock      = { gold = GAME .. "Lock", silver = GAME .. "Lock",
                  classic = GAME .. "PickLock" },
    -- Links and objects in a note that open a tooltip or act on a click
    -- (ALL-489, 2026-10-17); none on Classic yet (false). The atlas names
    -- cursor_workorders_128 / cursor_unableworkorders_128 drew a black box:
    -- SetCursor wants the cursor's own name, as the in-world ones (Mail,
    -- Trainer). WorkOrders confirmed on Retail and Forever (Dukul, 2026-10-17)
    link      = { gold = GAME .. "WorkOrders",
                  silver = GAME .. "UnableWorkOrders",
                  classic = false },
    -- These three use the gold cell on Retail too (Dukul, 2026-10-17); the
    -- link cursor keeps its silver one.
    -- Waypoint links and waypoint rows (ALL-492, Dukul 2026-10-17:
    -- UIDirectionsCursor2x). None on Classic. Never the .crosshair cells
    -- for these: that set's hot spot is the middle of the picture, so it
    -- sat up and left of the pointer (Dukul, 2026-10-17, the Cast cursor
    -- once tried on toolbar icons and taken off again as too distracting)
    waypoint  = { gold = GAME .. "Directions",
                  silver = GAME .. "Directions",
                  classic = false },
    -- Item links in notes and item entries in the Reference Box (Dukul,
    -- 2026-10-17: UIInspectCursor2x). Name guessed as the others: the
    -- Inspect row of the Cursor Test window. None on Classic
    item      = { gold = GAME .. "Inspect",
                  silver = GAME .. "Inspect",
                  classic = false },
    -- Links to other notes (bnbnote:, Dukul 2026-10-17: Crosshair/
    -- UITrainerCrosshair2x). The plain Trainer cell, not .crosshair, for the
    -- hot spot (see icon). None on Classic
    note      = { gold = GAME .. "Trainer",
                  silver = GAME .. "Trainer",
                  classic = false },
    -- External links (web addresses) in rich notes (Dukul, 2026-10-17:
    -- UICursorMapPin2x, gold on Forever and silver on Retail, as the link
    -- cursor). MapPin drew a black box; MapPinCursor is the name (Dukul,
    -- 2026-10-17). None on Classic
    url       = { gold = GAME .. "MapPinCursor",
                  silver = GAME .. "UnableMapPinCursor",
                  classic = false },
}
BNB.CURSORS = CURSORS

function BNB.CursorPath(kind)
    if type(kind) == "string" and not CURSORS[kind] then return kind end
    local c = type(kind) == "table" and kind or CURSORS[kind]
    if not c then return nil end
    if BNB.IsForever then return c.gold end
    if BNB.IsClassic and c.classic ~= nil then return c.classic or nil end
    return c.silver
end

-- The frame whose cursor is showing. Clearing is only done by that frame,
-- so a late OnLeave cannot wipe the cursor the next frame just set.
local _owner
local guard = CreateFrame("Frame")   -- see the guard below Release
guard:Hide()

local function ShowFor(frame)
    local kind = frame._bnbCursor
    if type(kind) == "function" then kind = kind(frame) end
    local path = kind and BNB.CursorPath(kind)
    if not path then return end
    SetCursor(path)
    _owner = frame
    guard:Show()
end

local function ClearFor(frame)
    if _owner ~= frame then return end
    _owner = nil
    SetCursor(nil)
end

local function Release(frame)
    if not frame._bnbCursorHeld then return end
    frame._bnbCursorHeld = nil
    if not frame:IsMouseOver() then ClearFor(frame)
    elseif frame._bnbTitleBand then ClearFor(frame)   -- the band watcher re-checks
    else ShowFor(frame) end
end

-- Guard (Dukul 2026-10-08: the move cursor stuck after moving from the main
-- window's top bar into the window). Clearing hangs on OnLeave / OnMouseUp /
-- OnDragStop hooks, and a later SetScript on the frame wipes a hook (the main
-- window sets its own OnMouseDown / OnDragStop / OnHide after SeatChrome).
-- While one of our cursors shows, this checks every frame: a held cursor is
-- released once no mouse button is down, any other is cleared once neither
-- its frame nor one of its children is under the mouse. Not for MANUAL.
local function UnderMouse(frame)
    local foci = GetMouseFoci and GetMouseFoci()
    if not foci then return frame:IsMouseOver() end
    for _, x in ipairs(foci) do
        local depth = 0
        while x and depth < 20 do
            if x == frame then return true end
            -- a forbidden frame errors on GetParent (ALL-612, the shop)
            if x.IsForbidden and x:IsForbidden() then break end
            x = x.GetParent and x:GetParent()
            depth = depth + 1
        end
    end
    return false
end

local function AnyButtonDown()
    return IsMouseButtonDown("LeftButton") or IsMouseButtonDown("RightButton")
        or IsMouseButtonDown("MiddleButton")
end

guard:SetScript("OnUpdate", function(self)
    local o = _owner
    if type(o) ~= "table" or not o.IsVisible then self:Hide(); return end
    if o._bnbCursorHeld then
        if not AnyButtonDown() then Release(o) end
        return
    end
    if not o:IsVisible() or not UnderMouse(o) then
        o._bnbHover = nil
        ClearFor(o)
        self:Hide()
    end
end)

local function OnDown(self, btn)
    if self._bnbCursorHeldKind then
        self._bnbCursorHeld = true
        local path = BNB.CursorPath(self._bnbCursorHeldKind)
        if path then SetCursor(path); _owner = self; guard:Show() end
    elseif btn == "LeftButton" and _owner == self then
        self._bnbCursorHeld = true
    end
end

local function Hook(frame)
    if frame._bnbCursorHooked then return end
    frame._bnbCursorHooked = true
    frame:HookScript("OnMouseDown", OnDown)
    frame:HookScript("OnMouseUp", Release)
    frame:HookScript("OnDragStop", Release)
    frame:HookScript("OnHide", function(self)
        self._bnbCursorHeld = nil
        ClearFor(self)
    end)
end

function BNB.SetHoverCursor(frame, kind, heldKind)
    if not frame then return end
    frame._bnbCursor = kind
    frame._bnbCursorHeldKind = heldKind
    if frame._bnbCursorHooked then return end
    Hook(frame)
    frame:HookScript("OnEnter", function(self) ShowFor(self) end)
    frame:HookScript("OnLeave", function(self)
        if not self._bnbCursorHeld then ClearFor(self) end
    end)
end

local function CanDrag(frame)
    if frame:IsMouseEnabled() and frame:GetScript("OnDragStart") then return "move" end
end

function BNB.SetMoveCursor(frame)
    BNB.SetHoverCursor(frame, CanDrag)
end

-- Normal-mode windows drag from anywhere on the frame, and the frame is also
-- the body, so the move cursor shows only while the mouse is in the title
-- band at its top. One watcher for all: only one frame is under the mouse.
local TITLE_BAND = 24
local _watch
local watcher = CreateFrame("Frame")
watcher:Hide()

local function InBand(f)
    local top = f:GetTop()
    if not top then return false end
    local _, y = GetCursorPosition()
    y = y / f:GetEffectiveScale()
    return y <= top and y >= top - TITLE_BAND
end

watcher:SetScript("OnUpdate", function(self)
    local f = _watch
    -- _bnbHover, not IsMouseOver: that also counts child frames (the close
    -- button sits in the band)
    if not f or not f:IsVisible() or not (f._bnbHover or f._bnbCursorHeld) then
        if f then ClearFor(f) end
        _watch = nil
        self:Hide()
        return
    end
    if f._bnbCursorHeld then return end
    if InBand(f) and CanDrag(f) then
        if _owner ~= f then ShowFor(f) end
    elseif _owner == f then
        ClearFor(f)
    end
end)

function BNB.AddTitleMoveCursor(f)
    if not f or f._bnbTitleBand then return end
    f._bnbTitleBand = true
    f._bnbCursor = CanDrag
    Hook(f)
    f:HookScript("OnEnter", function(self)
        self._bnbHover = true
        _watch = self
        watcher:Show()
    end)
    f:HookScript("OnLeave", function(self)
        self._bnbHover = nil
        if not self._bnbCursorHeld then ClearFor(self) end
    end)
end

-- Set and cleared by code, for a cursor that belongs to no one frame's hover
-- (a note carried out of the list).
local MANUAL = {}
function BNB.ShowCursor(kind)
    local path = BNB.CursorPath(kind)
    if not path then return end
    SetCursor(path)
    _owner = MANUAL
end

function BNB.ClearCursor()
    ClearFor(MANUAL)
end

-- The link cursor over one link inside a text frame (ALL-489): shown from
-- OnHyperlinkEnter, taken away from OnHyperlinkLeave. The frame owns it, so
-- the guard clears it when the mouse leaves the frame without a link leave.
-- On leave the frame's own hover cursor (the lock on a locked note) returns.
-- A waypoint link (bnbwp: from NoteLinks, bnbway: a /way line) gets the
-- waypoint cursor instead (ALL-492), an item link the item cursor, a link
-- to another note the note cursor, a web address the url cursor (a rich
-- {link*url*text} link with no scheme has no "type:" at all).
local function LinkKind(link)
    if type(link) ~= "string" then return "link" end
    if link:find("^bnbwp:") or link:find("^bnbway:") then return "waypoint" end
    if link:find("^item:") then return "item" end
    if link:find("^bnbnote:") then return "note" end
    if link:find("^https?:") or not link:find("^%a+:") then return "url" end
    return "link"
end

function BNB.ShowLinkCursor(frame, link)
    local path = frame and BNB.CursorPath(LinkKind(link))
    if not path then return end
    SetCursor(path)
    _owner = frame
    guard:Show()
end

function BNB.HideLinkCursor(frame)
    if not frame or _owner ~= frame then return end
    ClearFor(frame)
    if frame._bnbCursor and frame:IsMouseOver() then ShowFor(frame) end
end

--------------------------------------------------------------------------------
-- TEST WINDOW (Developer Tools > Cursor Test)
-- One row per game cursor name, a hover box for its gold and its silver cell.
-- The column this client uses has a gold border. Row labels are the cursor
-- names themselves (dev only, not translated); ".c" = the .crosshair set.
--------------------------------------------------------------------------------
local TEST_ROWS = {
    { "Move .c",         "UI-Cursor-Move.crosshair",      "UnableUI-Cursor-Move.crosshair" },
    { "Move",            "UI-Cursor-Move",                "UnableUI-Cursor-Move" },
    { "SizeRight .c",    "UI-Cursor-SizeRight.crosshair", "UnableUI-Cursor-UI-Cursor-SizeRight.crosshair" },
    { "SizeRight",       "UI-Cursor-SizeRight",           "UnableUI-Cursor-UI-Cursor-SizeRight" },
    { "SizeLeft .c",     "UI-Cursor-SizeLeft.crosshair",  "UnableUI-Cursor-UI-Cursor-SizeLeft.crosshair" },
    { "SizeLeft",        "UI-Cursor-SizeLeft",            "UnableUI-Cursor-SizeLeft" },
    { "Size .c",         "UI-Cursor-Size.crosshair",      "UnableUI-Cursor_size.crosshair" },
    { "Size",            "UI-Cursor-Size",                "UnableUI-Cursor_size" },
    { "GrabbingHand .c", "GrabbingHand.crosshair",        "UnableGrabbingHand.crosshair" },
    { "GrabbingHand",    "GrabbingHand",                  "UnableGrabbingHand" },
    { "HoldingHand .c",  "HoldingHand.crosshair",         "UnableHoldingHand.crosshair" },
    { "OpenHand .c",     "OpenHand.crosshair",            "UnableOpenHand.crosshair" },
    { "Lock .c",         "Lock.crosshair",                "UnableLock.crosshair" },
    { "Lock",            "Lock",                          "UnableLock" },
    { "WorkOrders",      "WorkOrders",                    "UnableWorkOrders" },   -- ALL-489 link cursor
    { "Directions",      "Directions",                    "UnableDirections" },   -- ALL-492 waypoint
    { "Inspect",         "Inspect",                       "UnableInspect" },   -- item cursor
    { "Trainer",         "Trainer",                       "UnableTrainer" },   -- note link cursor
    { "OpenHand",        "OpenHand",                      "UnableOpenHand" },   -- open hand (2026-10-17)
    { "HoldingHand",     "HoldingHand",                   "UnableHoldingHand" },   -- holding hand (2026-10-17)
    { "MapPinCursor",    "MapPinCursor",                  "UnableMapPinCursor" },   -- external link cursor
}

-- Two groups side by side (Dukul, 2026-10-17: too tall as one list): the
-- first half of TEST_ROWS on the left, the rest on the right
local T_PAD      = 20
local LABEL_W    = 150
local TILE_W     = 100
local TILE_H     = 28
local TILE_GAP   = 10
local ROW_GAP    = 4
local GROUP_W    = LABEL_W + TILE_W * 2 + TILE_GAP
local GROUP_GAP  = 30
local PER_GROUP  = math.ceil(#TEST_ROWS / 2)
local T_W        = T_PAD * 2 + GROUP_W * 2 + GROUP_GAP
local T_H        = 228 + PER_GROUP * (TILE_H + ROW_GAP)

local _test

local function BuildTest()
    local f, resetBtn, closeBtn = BNB.CreateToolWindow({
        name = "BigNoteBoxCursorTest", w = T_W, h = T_H,
        title = L["DEV_WIN_CURSOR_TITLE"], pad = T_PAD, cw = T_W - T_PAD * 2, footH = 40,
        btn1 = L["DEV_WIN_CURSOR_RESET"], btn2 = L["CLOSE"],
        onClose = function() _test:Hide() end,
        toplevel = true, escClose = true,
    })
    f:SetPoint("CENTER")
    resetBtn:SetScript("OnClick", function() _owner = nil; SetCursor(nil) end)
    closeBtn:SetScript("OnClick", function() f:Hide() end)

    local y = -40
    local intro = f:CreateFontString(nil, "OVERLAY", "BNBFontHighlightSmall")
    intro:SetPoint("TOPLEFT",  f, "TOPLEFT",  T_PAD, y)
    intro:SetPoint("TOPRIGHT", f, "TOPRIGHT", -T_PAD, y)
    intro:SetJustifyH("LEFT")
    intro:SetWordWrap(true)
    intro:SetText(L["DEV_WIN_CURSOR_INTRO"])
    y = y - 50

    local cols = {
        { key = "gold",   x = LABEL_W, head = L["DEV_WIN_CURSOR_GOLD"] },
        { key = "silver", x = LABEL_W + TILE_W + TILE_GAP, head = L["DEV_WIN_CURSOR_SILVER"] },
    }
    local mine = BNB.IsForever and "gold" or "silver"
    for g = 0, 1 do
        local gx = T_PAD + g * (GROUP_W + GROUP_GAP)
        for _, c in ipairs(cols) do
            local h = f:CreateFontString(nil, "OVERLAY", "BNBFontNormalSmall")
            h:SetPoint("TOPLEFT", f, "TOPLEFT", gx + c.x, y)
            h:SetWidth(TILE_W)
            h:SetText(c.head)
        end
    end
    y = y - 20
    local top = y

    local status = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    status:SetPoint("BOTTOMLEFT",  f, "BOTTOMLEFT",  T_PAD, 50)
    status:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -T_PAD, 50)
    status:SetJustifyH("LEFT")
    status:SetWordWrap(true)

    for i, row in ipairs(TEST_ROWS) do
        local g = i > PER_GROUP and 1 or 0
        if i == PER_GROUP + 1 then y = top end
        local gx = T_PAD + g * (GROUP_W + GROUP_GAP)
        local lbl = f:CreateFontString(nil, "OVERLAY", "BNBFontHighlightSmall")
        lbl:SetPoint("LEFT", f, "TOPLEFT", gx, y - TILE_H / 2)
        lbl:SetWidth(LABEL_W - 8)
        lbl:SetJustifyH("LEFT")
        lbl:SetText(row[1])
        local set = { gold = GAME .. row[2], silver = GAME .. row[3] }
        for _, c in ipairs(cols) do
            local path = set[c.key]
            local tile = BNB.CreateBackdropFrame("Frame", nil, f)
            tile:SetSize(TILE_W, TILE_H)
            tile:SetPoint("TOPLEFT", f, "TOPLEFT", gx + c.x, y)
            BNB.SetBackdropDark(tile)
            if c.key == mine then tile:SetBackdropBorderColor(1, 0.82, 0, 1) end
            local txt = tile:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
            txt:SetPoint("CENTER")
            if path then
                tile:EnableMouse(true)
                BNB.SetHoverCursor(tile, path)
                tile:HookScript("OnEnter", function() status:SetText(path) end)
            else
                txt:SetText("-")
            end
        end
        y = y - TILE_H - ROW_GAP
    end
    f:HookScript("OnHide", function() status:SetText("") end)
    return f
end

function BNB.OpenCursorTest()
    _test = _test or BuildTest()
    _test:Show()
    _test:Raise()
end

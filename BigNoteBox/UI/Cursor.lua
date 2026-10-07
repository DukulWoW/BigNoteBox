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
    hold      = { gold = GAME .. "HoldingHand.crosshair",
                  silver = GAME .. "HoldingHand.crosshair",
                  classic = GAME .. "UnableQuestInteract" },
    open      = { gold = GAME .. "OpenHand.crosshair", silver = GAME .. "OpenHand.crosshair",
                  classic = GAME .. "OpenHand" },
    lock      = { gold = GAME .. "Lock", silver = GAME .. "Lock",
                  classic = GAME .. "PickLock" },
}
BNB.CURSORS = CURSORS

function BNB.CursorPath(kind)
    if type(kind) == "string" and not CURSORS[kind] then return kind end
    local c = type(kind) == "table" and kind or CURSORS[kind]
    if not c then return nil end
    if BNB.IsForever then return c.gold end
    if BNB.IsClassic and c.classic then return c.classic end
    return c.silver
end

-- The frame whose cursor is showing. Clearing is only done by that frame,
-- so a late OnLeave cannot wipe the cursor the next frame just set.
local _owner

local function ShowFor(frame)
    local kind = frame._bnbCursor
    if type(kind) == "function" then kind = kind(frame) end
    local path = kind and BNB.CursorPath(kind)
    if not path then return end
    SetCursor(path)
    _owner = frame
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

local function OnDown(self, btn)
    if self._bnbCursorHeldKind then
        self._bnbCursorHeld = true
        local path = BNB.CursorPath(self._bnbCursorHeldKind)
        if path then SetCursor(path); _owner = self end
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
}

local T_W, T_H   = 400, 676
local T_PAD      = 20
local LABEL_W    = 150
local TILE_W     = 100
local TILE_H     = 28
local TILE_GAP   = 10
local ROW_GAP    = 4

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
    local intro = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    intro:SetPoint("TOPLEFT",  f, "TOPLEFT",  T_PAD, y)
    intro:SetPoint("TOPRIGHT", f, "TOPRIGHT", -T_PAD, y)
    intro:SetJustifyH("LEFT")
    intro:SetWordWrap(true)
    intro:SetText(L["DEV_WIN_CURSOR_INTRO"])
    y = y - 50

    local cols = {
        { key = "gold",   x = T_PAD + LABEL_W, head = L["DEV_WIN_CURSOR_GOLD"] },
        { key = "silver", x = T_PAD + LABEL_W + TILE_W + TILE_GAP, head = L["DEV_WIN_CURSOR_SILVER"] },
    }
    local mine = BNB.IsForever and "gold" or "silver"
    for _, c in ipairs(cols) do
        local h = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        h:SetPoint("TOPLEFT", f, "TOPLEFT", c.x, y)
        h:SetWidth(TILE_W)
        h:SetText(c.head)
    end
    y = y - 20

    local status = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    status:SetPoint("BOTTOMLEFT",  f, "BOTTOMLEFT",  T_PAD, 50)
    status:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -T_PAD, 50)
    status:SetJustifyH("LEFT")
    status:SetWordWrap(true)

    for _, row in ipairs(TEST_ROWS) do
        local lbl = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        lbl:SetPoint("LEFT", f, "TOPLEFT", T_PAD, y - TILE_H / 2)
        lbl:SetWidth(LABEL_W - 8)
        lbl:SetJustifyH("LEFT")
        lbl:SetText(row[1])
        local set = { gold = GAME .. row[2], silver = GAME .. row[3] }
        for _, c in ipairs(cols) do
            local path = set[c.key]
            local tile = BNB.CreateBackdropFrame("Frame", nil, f)
            tile:SetSize(TILE_W, TILE_H)
            tile:SetPoint("TOPLEFT", f, "TOPLEFT", c.x, y)
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

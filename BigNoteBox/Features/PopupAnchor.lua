-- BigNoteBox Features/PopupAnchor.lua — Draggable anchor for context popup
--
-- A small movable frame that lets the user position where context note
-- popups appear.  Toggled from Settings > Modules > Context Popup.
-- Position is saved as CENTER-relative offsets in BigNoteBoxDB.

local BNB = BigNoteBox
local L   = BNB.L

local _anchor = nil    -- the draggable editor frame

local ANCHOR_W = 200
local ANCHOR_H = 28

--------------------------------------------------------------------------------
-- CREATE
--------------------------------------------------------------------------------
-- Saves the frame's centre as an offset from the screen centre (whole
-- pixels); with reanchor, also pins the frame there. One copy for drag stop
-- and Lock (CMP-05).
local function SaveAnchorPos(f, reanchor)
    local cx, cy = f:GetCenter()
    local scx, scy = UIParent:GetCenter()
    if not (cx and scx) then return end
    local x = math.floor(cx - scx + 0.5)
    local y = math.floor(cy - scy + 0.5)
    if reanchor then
        f:ClearAllPoints()
        f:SetPoint("CENTER", UIParent, "CENTER", x, y)
    end
    if BigNoteBoxDB then
        BigNoteBoxDB.popupAnchorX = x
        BigNoteBoxDB.popupAnchorY = y
    end
end

local function CreateAnchorEditor()
    if _anchor then return end

    local f = BNB.CreateBackdropFrame("Frame", "BigNoteBoxPopupAnchor", UIParent)
    f:SetSize(ANCHOR_W, ANCHOR_H)
    f:SetFrameStrata("DIALOG")
    f:SetToplevel(true)
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    BNB.SetBackdrop(f, 0.10, 0.10, 0.12, 0.92, 0.45, 0.70, 0.45, 1)
    f:Hide()

    -- Title text
    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("LEFT", f, "LEFT", 8, 0)
    title:SetText(L["POPANCHOR_TITLE"])
    title:SetTextColor(1, 0.82, 0, 0.9)

    -- Lock button
    local lockBtn = BNB.CreateButton(nil, f, L["POPANCHOR_LOCK"], 50, 20)
    lockBtn:SetPoint("RIGHT", f, "RIGHT", -4, 0)
    lockBtn:SetScript("OnClick", function()
        BNB.LockPopupAnchor()
    end)

    -- Drag handlers
    f:SetScript("OnDragStart", function(self) self:StartMoving() end)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        SaveAnchorPos(self, true)
    end)
    BNB.SetMoveCursor(f)   -- ALL-95

    -- Tooltip
    f:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(L["POPANCHOR_TITLE"], 1, 0.82, 0)
        GameTooltip:AddLine(L["POPANCHOR_TIP1"], 0.7, 0.7, 0.7)
        GameTooltip:AddLine(L["POPANCHOR_TIP2"], 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)
    f:SetScript("OnLeave", function() GameTooltip:Hide() end)

    _anchor = f
end

--------------------------------------------------------------------------------
-- TOGGLE / LOCK
--------------------------------------------------------------------------------
function BNB.TogglePopupAnchor()
    CreateAnchorEditor()
    if _anchor:IsShown() then
        BNB.LockPopupAnchor()
        return
    end
    -- Position at saved location or screen centre
    local db = BigNoteBoxDB
    local x  = db and db.popupAnchorX or BNB.DEFAULTS.popupAnchorX
    local y  = db and db.popupAnchorY or BNB.DEFAULTS.popupAnchorY
    _anchor:ClearAllPoints()
    _anchor:SetPoint("CENTER", UIParent, "CENTER", x, y)
    _anchor:Show()
end

function BNB.LockPopupAnchor()
    if not _anchor then return end
    SaveAnchorPos(_anchor)   -- final position
    _anchor:Hide()
    BNB:Print(L["POPANCHOR_SAVED"])
end

--------------------------------------------------------------------------------
-- GET POSITION — used by ContextNotes.lua for toast placement
-- Returns: point, relativeTo, relativePoint, x, y
--------------------------------------------------------------------------------
function BNB.GetPopupAnchorPoint()
    local db = BigNoteBoxDB
    local x  = db and db.popupAnchorX or BNB.DEFAULTS.popupAnchorX
    local y  = db and db.popupAnchorY or BNB.DEFAULTS.popupAnchorY
    return "CENTER", UIParent, "CENTER", x, y
end

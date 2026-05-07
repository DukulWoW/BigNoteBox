-- BigNoteBox Features/PopupAnchor.lua — Draggable anchor for context popup
--
-- A small movable frame that lets the user position where context note
-- popups appear.  Toggled from the Config Features tab.
-- Position is saved as CENTER-relative offsets in BigNoteBoxDB.

local BNB = BigNoteBox
local L   = BNB.L

local _anchor = nil    -- the draggable editor frame

local ANCHOR_W = 200
local ANCHOR_H = 28

--------------------------------------------------------------------------------
-- CREATE
--------------------------------------------------------------------------------
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
    title:SetText("Context Popup Anchor")
    title:SetTextColor(1, 0.82, 0, 0.9)

    -- Lock button
    local lockBtn = BNB.CreateButton(nil, f, "Lock", 50, 20)
    lockBtn:SetPoint("RIGHT", f, "RIGHT", -4, 0)
    lockBtn:SetScript("OnClick", function()
        BNB.LockPopupAnchor()
    end)

    -- Drag handlers
    f:SetScript("OnDragStart", function(self) self:StartMoving() end)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        -- Save CENTER-relative position
        local cx, cy = self:GetCenter()
        local scx, scy = UIParent:GetCenter()
        if cx and scx then
            local x = math.floor(cx - scx + 0.5)
            local y = math.floor(cy - scy + 0.5)
            self:ClearAllPoints()
            self:SetPoint("CENTER", UIParent, "CENTER", x, y)
            if BigNoteBoxDB then
                BigNoteBoxDB.popupAnchorX = x
                BigNoteBoxDB.popupAnchorY = y
            end
        end
    end)

    -- Tooltip
    f:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Context Popup Anchor", 1, 0.82, 0)
        GameTooltip:AddLine("Drag to position where context popups appear.", 0.7, 0.7, 0.7)
        GameTooltip:AddLine("Click Lock to save position.", 0.7, 0.7, 0.7)
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
    local x  = db and db.popupAnchorX or 0
    local y  = db and db.popupAnchorY or 200
    _anchor:ClearAllPoints()
    _anchor:SetPoint("CENTER", UIParent, "CENTER", x, y)
    _anchor:Show()
end

function BNB.LockPopupAnchor()
    if not _anchor then return end
    -- Save final position
    local cx, cy = _anchor:GetCenter()
    local scx, scy = UIParent:GetCenter()
    if cx and scx then
        local x = math.floor(cx - scx + 0.5)
        local y = math.floor(cy - scy + 0.5)
        if BigNoteBoxDB then
            BigNoteBoxDB.popupAnchorX = x
            BigNoteBoxDB.popupAnchorY = y
        end
    end
    _anchor:Hide()
    BNB:Print("Popup anchor position saved.")
end

function BNB.IsPopupAnchorShown()
    return _anchor and _anchor:IsShown() or false
end

--------------------------------------------------------------------------------
-- GET POSITION — used by ContextNotes.lua for toast placement
-- Returns: point, relativeTo, relativePoint, x, y
--------------------------------------------------------------------------------
function BNB.GetPopupAnchorPoint()
    local db = BigNoteBoxDB
    local x  = db and db.popupAnchorX or 0
    local y  = db and db.popupAnchorY or 200
    return "CENTER", UIParent, "CENTER", x, y
end

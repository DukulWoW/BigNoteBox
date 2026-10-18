-- BigNoteBox Features/InsertInfo.lua — Insert game info into note body
--
-- Adds a right-click context menu to the NoteEditor body EditBox (and Focus
-- Mode body) with the following insert actions:
--
--   Insert Info
--     • Set TomTom waypoint   — (shown only when TomTom is loaded)
--     • The note token groups, as the toolbar's token button
--       (BNB.BuildTokenMenu): they took over the old rows (location, name,
--       target, date, time, date and time), Dukul 2026-10-18
--   A right-click on a link opens the link menu instead (NoteLinks.lua).
--
-- Location format:
--   /way Zone XX.X YY.Y
--   This is the de-facto standard understood by TomTom and most coordinate
--   addons. BNB reads coords natively via C_Map; TomTom does not need to be
--   loaded to produce the string. If TomTom IS loaded, an extra "Set TomTom
--   waypoint" item appears that actually drops a pin rather than just
--   inserting text.
--
-- Public API:
--   BNB.WireInsertInfoTarget(eb)   — wire any body EditBox (main + Focus)

local BNB = BigNoteBox
local L   = BNB.L

-- ── Location helpers ──────────────────────────────────────────────────────────

-- Returns mapID for the player's current position.
local function GetPlayerMapID()
    if C_Map and C_Map.GetBestMapForUnit then
        return C_Map.GetBestMapForUnit("player")
    end
    return nil
end

-- Returns zone name string.
local function GetZoneName()
    -- GetRealZoneText gives the instance/zone name in all contexts.
    return GetRealZoneText() or GetZoneText() or "Unknown"
end

-- Returns x, y as 0-100 percentages (one decimal), or nil, nil.
local function GetPlayerCoords()
    local mapID = GetPlayerMapID()
    if not mapID then return nil, nil end
    if not (C_Map and C_Map.GetPlayerMapPosition) then return nil, nil end
    local pos = C_Map.GetPlayerMapPosition(mapID, "player")
    if not pos then return nil, nil end
    -- pos is a Vector2DMixin with x,y in 0-1 range
    local x, y = pos:GetXY()
    if not x or not y then return nil, nil end
    return math.floor(x * 1000 + 0.5) / 10,   -- one decimal, e.g. 42.3
           math.floor(y * 1000 + 0.5) / 10
end

-- Build the TomTom-format location string: "/way Zone XX.X YY.Y"
-- If coords are unavailable (Vanilla), falls back to "/way Zone" only.
local function BuildLocationString()
    local zone    = GetZoneName()
    local x, y   = GetPlayerCoords()
    if x and y then
        return string.format("/way %s %.1f %.1f", zone, x, y)
    else
        return string.format("/way %s", zone)
    end
end

-- The {{coords}} note token (Features/Tokens.lua, ALL-481)
BNB.PlayerWayString = BuildLocationString

-- Attempt to set a TomTom waypoint programmatically.
-- Returns true on success, false/nil on failure.
local function SetTomTomWaypoint()
    if not BNB.HasTomTom() then return false end
    local mapID = GetPlayerMapID()
    if not mapID then return false end
    local x, y = GetPlayerCoords()
    if not x or not y then return false end
    -- TomTom.AddWaypoint(mapID, x_fraction, y_fraction, opts)
    pcall(function()
        TomTom:AddWaypoint(mapID, x / 100, y / 100, {
            title = "BigNoteBox",
            from  = "BigNoteBox",
        })
    end)
    return true
end

-- ── Menu (BNB.ContextMenu, ALL-148) ──────────────────────────────────────────

local function ShowInsertInfoMenu(eb)
    BNB.ContextMenu.Open(eb, function(root)
        root:CreateTitle(L["INSERT_INFO_TITLE"])

        -- TomTom waypoint here: an action, not text (only with TomTom)
        if BNB.HasTomTom() then
            local x, y = GetPlayerCoords()
            if x and y then
                root:CreateButton(L["INSERT_TOMTOM"], function()
                    if not SetTomTomWaypoint() then BNB:Print(L["INSERT_TOMTOM_FAIL"]) end
                end, { icon = "create-situation" })
                root:CreateDivider()
            end
        end

        -- The note token groups right in this menu (Dukul, 2026-10-18): they
        -- hold what the old rows did (location = {{coords}}, name = {{me}},
        -- target, date, time, date and time) and the rest, into this editor
        -- at the cursor, a normal note getting the values (ALL-503)
        if BNB.BuildTokenMenu and BNB.Tokens and BNB._currentNoteID then
            BNB.BuildTokenMenu(root, function(snippet, back, value)
                BNB.InsertIntoEditor(snippet, back, value)
            end)
        end
    end)
end

-- A right-click on a link opens the link menu instead (Features/NoteLinks.lua
-- marks the box); both run on the same click, so this one waits a frame
local function ShowUnlessLinkMenu(eb)
    C_Timer.After(0, function()
        if eb._bnbLinkMenuT and GetTime() - eb._bnbLinkMenuT < 0.3 then return end
        ShowInsertInfoMenu(eb)
    end)
end

-- ── Wire a single EditBox ─────────────────────────────────────────────────────
-- Hooks right-click to show the Insert Info menu. HookScript, so any OnMouseUp
-- the box already has (and any hooks on it) keep running (CMP-06).
function BNB.WireInsertInfoTarget(eb)
    if not eb or eb._bnbInsertInfoWired then return end
    eb._bnbInsertInfoWired = true

    eb:HookScript("OnMouseUp", function(self, btn)
        -- Only show our menu when the editor is not locked / disabled
        if btn == "RightButton" and self:IsEnabled() then
            ShowUnlessLinkMenu(self)
        end
    end)

    -- The empty area below the last line is the scroll frame, not the box: the
    -- menu opens there too (ALL-461, Dukul 2026-10-13), as a drop does
    -- (WireDropTarget). Not typing in the box: what it inserts goes at the end
    local sf = eb:GetParent()
    if sf and sf.GetScrollChild and sf:GetScrollChild() == eb then
        sf:HookScript("OnMouseUp", function(_, btn)
            if btn ~= "RightButton" or not eb:IsEnabled() then return end
            if not eb:HasFocus() then eb:SetCursorPosition(#(eb:GetText() or "")) end
            ShowInsertInfoMenu(eb)
        end)
    end
end

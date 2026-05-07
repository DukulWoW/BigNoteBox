-- BigNoteBox Features/InsertInfo.lua — Insert game info into note body
--
-- Adds a right-click context menu to the NoteEditor body EditBox (and Focus
-- Mode body) with the following insert actions:
--
--   Insert Info ▶
--     • Current location      — zone + coords in TomTom /way format
--     • Set TomTom waypoint   — (shown only when TomTom is loaded)
--     • Character name        — "Playername-Realm"
--     • Target name           — name of current target (or "No target")
--     • Date                  — e.g. "2026-03-19"
--     • Date & time           — e.g. "2026-03-19 14:32"
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
--   BNB.SetupInsertInfo()          — called once from Initialize.lua
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

-- Attempt to set a TomTom waypoint programmatically.
-- Returns true on success, false/nil on failure.
local function SetTomTomWaypoint()
    if not (TomTom and TomTom.AddWaypoint) then return false end
    local mapID = GetPlayerMapID()
    if not mapID then return false end
    local x, y = GetPlayerCoords()
    if not x or not y then return false end
    local zone = GetZoneName()
    -- TomTom.AddWaypoint(mapID, x_fraction, y_fraction, opts)
    pcall(function()
        TomTom:AddWaypoint(mapID, x / 100, y / 100, {
            title = "BigNoteBox",
            from  = "BigNoteBox",
        })
    end)
    return true
end

-- ── Character / target helpers ────────────────────────────────────────────────

local function GetCharacterName()
    local name   = UnitName("player") or "Unknown"
    local realm  = GetNormalizedRealmName() or ""
    if realm ~= "" then
        return name .. "-" .. realm
    end
    return name
end

local function GetTargetName()
    if not UnitExists("target") then
        return L["INSERT_NO_TARGET"] or "No target"
    end
    return UnitName("target") or "Unknown"
end

-- ── Date helpers ──────────────────────────────────────────────────────────────

local function GetDateString()
    return date("%Y-%m-%d")
end

local function GetDateTimeString()
    return date("%Y-%m-%d %H:%M")
end

-- ── Insert into EditBox ───────────────────────────────────────────────────────

local function InsertIntoEditBox(eb, text)
    if not eb or not eb:IsEnabled() then return end
    eb:SetFocus()
    eb:Insert(text)
    BNB.MarkDirty()
end

-- ── Menu (WowStyle1DropdownTemplate) ─────────────────────────────────────────

local _infoDropdown = nil

local function ShowInsertInfoMenuModern(eb)
    if not _infoDropdown then
        _infoDropdown = CreateFrame("DropdownButton", "BNBInsertInfoDropdown",
            UIParent, "WowStyle1DropdownTemplate")
        _infoDropdown:SetSize(1, 1)
        _infoDropdown:SetAlpha(0)
    end
    _infoDropdown:ClearAllPoints()
    _infoDropdown:SetPoint("TOPLEFT", eb, "CENTER", 0, 0)

    _infoDropdown:SetupMenu(function(_, root)
        root:CreateTitle(L["INSERT_INFO_TITLE"] or "Insert Info")

        -- Location
        root:CreateButton(
            L["INSERT_LOCATION"] or "Current location",
            function()
                InsertIntoEditBox(eb, BuildLocationString())
            end
        )

        -- TomTom waypoint — only shown when TomTom is loaded
        if TomTom and TomTom.AddWaypoint then
            local x, y = GetPlayerCoords()
            if x and y then
                root:CreateButton(
                    L["INSERT_TOMTOM"] or "Set TomTom waypoint",
                    function()
                        if not SetTomTomWaypoint() then
                            BNB:Print(L["INSERT_TOMTOM_FAIL"] or "Could not set TomTom waypoint.")
                        end
                    end
                )
            end
        end

        root:CreateDivider()

        -- Character name
        root:CreateButton(
            L["INSERT_CHARNAME"] or "Character name",
            function()
                InsertIntoEditBox(eb, GetCharacterName())
            end
        )

        -- Target name
        root:CreateButton(
            L["INSERT_TARGET"] or "Target name",
            function()
                InsertIntoEditBox(eb, GetTargetName())
            end
        )

        root:CreateDivider()

        -- Date
        root:CreateButton(
            L["INSERT_DATE"] or "Date",
            function()
                InsertIntoEditBox(eb, GetDateString())
            end
        )

        -- Date & time
        root:CreateButton(
            L["INSERT_DATETIME"] or "Date and time",
            function()
                InsertIntoEditBox(eb, GetDateTimeString())
            end
        )
    end)

    _infoDropdown:OpenMenu()
end

-- ── Dispatch ──────────────────────────────────────────────────────────────────

local function ShowInsertInfoMenu(eb)
    ShowInsertInfoMenuModern(eb)
end

-- Called by MainWindow ESC handler to close the menu before anything else.
function BNB.CloseInsertInfoMenu()
    if _infoDropdown and _infoDropdown:IsMenuOpen() then
        _infoDropdown:CloseMenu()
        return true
    end
    return false
end

-- ── Wire a single EditBox ─────────────────────────────────────────────────────
-- Hooks right-click to show the Insert Info menu. Chains any existing
-- OnMouseUp handler (e.g. the standard WoW right-click link handler).
function BNB.WireInsertInfoTarget(eb)
    if not eb or eb._bnbInsertInfoWired then return end
    eb._bnbInsertInfoWired = true

    local prev = eb:GetScript("OnMouseUp")
    eb:SetScript("OnMouseUp", function(self, btn, ...)
        if btn == "RightButton" then
            -- Only show our menu when the editor is not locked / disabled
            if self:IsEnabled() then
                ShowInsertInfoMenu(self)
            end
            -- Still let any prior handler run (e.g. link tooltip on retail)
            if prev then pcall(prev, self, btn, ...) end
        else
            if prev then prev(self, btn, ...) end
        end
    end)
end

-- ── Setup ─────────────────────────────────────────────────────────────────────

function BNB.SetupInsertInfo()
    -- Wire the main editor body if it already exists
    if BNB._editorBody then
        BNB.WireInsertInfoTarget(BNB._editorBody)
    end
    -- Focus editor body wires itself via BNB.WireInsertInfoTarget after creation
end

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
--     • Date / Time / Date and time — in the Appearance timestamp format,
--       the same three choices as the toolbar stamp button (ALL-66)
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

-- Attempt to set a TomTom waypoint programmatically.
-- Returns true on success, false/nil on failure.
local function SetTomTomWaypoint()
    if not (TomTom and TomTom.AddWaypoint) then return false end
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
        return L["INSERT_NO_TARGET"]
    end
    return (BNB.UnitNameRealm("target")) or "Unknown"
end

-- ── Insert into EditBox ───────────────────────────────────────────────────────

local function InsertIntoEditBox(eb, text)
    if not eb or not eb:IsEnabled() then return end
    eb:SetFocus()
    eb:Insert(text)
    BNB.MarkDirty()
end

-- ── Menu (BNB.ContextMenu, ALL-148) ──────────────────────────────────────────

local function ShowInsertInfoMenu(eb)
    BNB.ContextMenu.Open(eb, function(root)
        root:CreateTitle(L["INSERT_INFO_TITLE"])

        -- Location
        root:CreateButton(
            L["INSERT_LOCATION"],
            function()
                InsertIntoEditBox(eb, BuildLocationString())
            end
        )

        -- TomTom waypoint — only shown when TomTom is loaded
        if TomTom and TomTom.AddWaypoint then
            local x, y = GetPlayerCoords()
            if x and y then
                root:CreateButton(
                    L["INSERT_TOMTOM"],
                    function()
                        if not SetTomTomWaypoint() then
                            BNB:Print(L["INSERT_TOMTOM_FAIL"])
                        end
                    end
                )
            end
        end

        root:CreateDivider()

        -- Character name
        root:CreateButton(
            L["INSERT_CHARNAME"],
            function()
                InsertIntoEditBox(eb, GetCharacterName())
            end
        )

        -- Target name
        root:CreateButton(
            L["INSERT_TARGET"],
            function()
                InsertIntoEditBox(eb, GetTargetName())
            end
        )

        root:CreateDivider()

        -- Date / Time / Date and time: same choices and format as the
        -- toolbar stamp menu (UI/WysiwygBar.lua), value previewed in grey
        local now = time()
        local d, t = BNB.FmtDate(now), BNB.FmtClock(now)
        for _, it in ipairs({
            { L["INSERT_DATE"],     d },
            { L["INSERT_TIME"],     t },
            { L["INSERT_DATETIME"], d .. " " .. t },
        }) do
            local value = it[2]
            root:CreateButton(it[1] .. "  |cff888888" .. value .. "|r",
                function() InsertIntoEditBox(eb, value) end)
        end
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
            ShowInsertInfoMenu(self)
        end
    end)
end

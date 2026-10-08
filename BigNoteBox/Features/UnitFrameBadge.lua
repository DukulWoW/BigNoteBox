-- BigNoteBox Features/UnitFrameBadge.lua
-- A note's icon on the Target and Focus frames while that unit has a player or
-- NPC note (ALL-389). The badge is our own small frame, a child of the unit
-- frame (so it hides with it) anchored to its portrait; nothing is written
-- onto Blizzard frames. A click opens the note.
-- Shown while Player & NPC Notes is on (BNB.UnitNotesEnabled) and
-- BigNoteBoxDB.unitFrameBadge (DEFAULTS true, Modules > Player & NPC Notes).
-- Party / raid frames and nameplates come later (nameplates: Midnight secret
-- values in instances and combat).
--
-- Public API:
--   BNB.UnitFrameBadgeEnabled()   module + setting
--   BNB.ApplyUnitFrameBadges()    re-check both frames (setting / module change)
--   BNB.TuneUnitBadge(x, y, s)    /bnb unitbadge (debug mode, live, not saved)

local BNB = BigNoteBox
local L   = BNB.L

local DEFAULT_ICON = "Interface\\Icons\\INV_Misc_Note_06"

-- The look of our minimap button: LibDBIcon's ring and background, with the
-- same per-client sizes (its WOW_PROJECT_ID rule), at SCALE.
local MAINLINE = WOW_PROJECT_ID == WOW_PROJECT_MAINLINE
local BTN      = 31
-- Badge centre against the portrait's TOPRIGHT corner, in badge pixels (the
-- bottom right covered the level bubble, Dukul 2026-10-08).
-- Tune live with /bnb unitbadge <x> <y> [scale].
local OFF_X, OFF_Y, SCALE = -4, -6, 0.8

local UNITS = {
    { unit = "target", frame = "TargetFrame" },
    { unit = "focus",  frame = "FocusFrame"  },
}
local _badges = {}   -- unit -> badge frame

function BNB.UnitFrameBadgeEnabled()
    return BNB.UnitNotesEnabled() and BigNoteBoxDB and BigNoteBoxDB.unitFrameBadge ~= false
end

-- ── Lookup index ─────────────────────────────────────────────────────────────
-- Candidates by NPC id and by player name, rebuilt on first use after any note
-- message; BNB.NoteMatchesUnit (UI/NoteList.lua) makes the final call, the
-- same test the note list uses for its live portrait.
local _index

local function BuildIndex()
    _index = { npcs = {}, players = {} }
    local ndb = BNB.NotesDB()
    for id, n in pairs(ndb and ndb.notes or {}) do
        local key, list
        if n.source == "target" and n.targetNpcID then
            key, list = tostring(n.targetNpcID), _index.npcs
        elseif n.source == "inspect" and n.inspectName then
            key, list = n.inspectName, _index.players
        elseif n.source == "target" and n.targetPlayerKey then
            key, list = n.targetPlayerKey:match("^player:([^%-]+)"), _index.players
        end
        if key then
            list[key] = list[key] or {}
            table.insert(list[key], id)
        end
    end
end

-- The note for a unit, newest edit first when there are more; nil = none.
-- Unit data can be a secret value on Midnight (instances, combat): any error
-- reading it is no badge.
local function NoteForUnit(unit)
    if not UnitExists(unit) then return nil end
    if not _index then BuildIndex() end
    local cands
    if UnitIsPlayer(unit) then
        local name = BNB.UnitNameRealm(unit)
        cands = name and _index.players[name]
    else
        local guid = UnitGUID(unit)
        local npcID = guid and (guid:match("^Creature%-0%-%d+%-%d+%-%d+%-(%d+)")
            or guid:match("^Vehicle%-0%-%d+%-%d+%-%d+%-(%d+)")
            or guid:match("^Pet%-0%-%d+%-%d+%-%d+%-(%d+)"))
        cands = npcID and _index.npcs[npcID]
    end
    if not cands then return nil end
    local best, bestT
    for _, id in ipairs(cands) do
        local n = BNB.GetNote(id)
        if n and BNB.NoteMatchesUnit(n, unit) then
            local t = n.updated or n.created or 0
            if not best or t > bestT then best, bestT = id, t end
        end
    end
    return best
end

-- ── Badge ────────────────────────────────────────────────────────────────────
local function Portrait(frame)
    local c = frame.TargetFrameContainer          -- Retail / Forever
    if c and c.Portrait then return c.Portrait end
    local name = frame:GetName()                  -- Classic: TargetFramePortrait
    return (name and _G[name .. "Portrait"]) or frame.portrait
end

local function PlaceBadge(b)
    b:SetScale(SCALE)
    b:ClearAllPoints()
    b:SetPoint("CENTER", b._portrait, "TOPRIGHT", OFF_X / SCALE, OFF_Y / SCALE)
end

local function MakeBadge(spec)
    local frame = _G[spec.frame]
    local portrait = frame and Portrait(frame)
    if not portrait then return nil end
    local b = CreateFrame("Button", nil, frame)
    b:SetSize(BTN, BTN)
    b:SetFrameLevel(frame:GetFrameLevel() + 20)
    b:RegisterForClicks("LeftButtonUp")
    b._portrait = portrait
    b._unit = spec.unit

    local bg = b:CreateTexture(nil, "BACKGROUND")
    bg:SetTexture(136467)   -- Interface\Minimap\UI-Minimap-Background
    local icon = b:CreateTexture(nil, "ARTWORK")
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    local border = b:CreateTexture(nil, "OVERLAY")
    border:SetTexture(136430)   -- Interface\Minimap\MiniMap-TrackingBorder
    border:SetPoint("TOPLEFT", 0, 0)
    if MAINLINE then
        border:SetSize(50, 50)
        bg:SetSize(24, 24); bg:SetPoint("CENTER", 0, 0)
        icon:SetSize(18, 18); icon:SetPoint("CENTER", 0, 0)
    else
        border:SetSize(53, 53)
        bg:SetSize(20, 20); bg:SetPoint("TOPLEFT", 7, -5)
        icon:SetSize(17, 17); icon:SetPoint("TOPLEFT", 7, -6)
    end
    -- Round icon, as a minimap button's
    pcall(function()
        local mask = b:CreateMaskTexture()
        mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask",
            "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        mask:SetAllPoints(icon)
        icon:AddMaskTexture(mask)
    end)
    b:SetHighlightTexture(136477)   -- Interface\Minimap\UI-Minimap-ZoomButton-Highlight
    b._icon = icon

    b:SetScript("OnClick", function(self)
        if self._noteID and BNB.OpenNoteInMain then BNB.OpenNoteInMain(self._noteID) end
    end)
    b:SetScript("OnEnter", function(self)
        local n = self._noteID and BNB.GetNote(self._noteID)
        if not n then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(n.title or "", 1, 1, 1)
        GameTooltip:AddLine(L["UNIT_BADGE_TIP"], 0.6, 0.6, 0.6)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    PlaceBadge(b)
    b:Hide()
    return b
end

local function Update(unit)
    local b = _badges[unit]
    if not BNB.UnitFrameBadgeEnabled() then
        if b then b:Hide() end
        return
    end
    if not b then
        for _, spec in ipairs(UNITS) do
            if spec.unit == unit then b = MakeBadge(spec) end
        end
        if not b then return end
        _badges[unit] = b
    end
    local ok, id = pcall(NoteForUnit, unit)
    local note = ok and id and BNB.GetNote(id)
    if not note then
        b._noteID = nil
        b:Hide()
        return
    end
    b._noteID = id
    local icon = BNB.NpcNoteIcon and BNB.NpcNoteIcon(note) or note.icon
    b._icon:SetTexture((icon and icon ~= "") and icon or DEFAULT_ICON)
    b:Show()
end

function BNB.ApplyUnitFrameBadges()
    for _, spec in ipairs(UNITS) do Update(spec.unit) end
end

-- /bnb unitbadge (debug mode): live placement, printed back for the constants
function BNB.TuneUnitBadge(x, y, s)
    OFF_X, OFF_Y, SCALE = x or OFF_X, y or OFF_Y, s or SCALE
    for _, b in pairs(_badges) do PlaceBadge(b) end
    return OFF_X, OFF_Y, SCALE
end

-- ── Events ───────────────────────────────────────────────────────────────────
BNB.RegisterEvent("PLAYER_TARGET_CHANGED", function() Update("target") end)
BNB.RegisterEvent("PLAYER_FOCUS_CHANGED",  function() Update("focus") end)
BNB.RegisterEvent("PLAYER_ENTERING_WORLD", function() BNB.ApplyUnitFrameBadges() end)

-- Any note change can add, remove or re-icon a badge: drop the index and
-- re-check once things settle (autosave sends NoteChanged while typing)
local function Rebuild() _index = nil; BNB.ApplyUnitFrameBadges() end
for _, msg in ipairs({ "NoteCreated", "NoteChanged", "NoteDeleted", "NoteRestored" }) do
    BNB.RegisterMessage("UnitFrameBadge", msg, function() BNB.Debounce("unitFrameBadge", 0.5, Rebuild) end)
end

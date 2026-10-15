-- BigNoteBox Features/PlayerNoteAuto.lua
-- Player notes that update themselves (ALL-474).
--
-- A player note (source "inspect") keeps what its top was built from in
-- note.unitAuto = { data, head, fp, edited, off }:
--   data    UN.PlayerSnapshot: level, guild, item level, gear ... (InspectNote)
--   head    the Notes heading line; everything under it is the player's own
--   fp      UN.Fingerprint of the top BNB last wrote. A top that no longer
--           matches (or a heading that is gone) was edited by hand: edited =
--           true, one chat line, and the text is left alone from then on
--           until "Update gear and note" in the Inspect window
--   off     this note does not update its text (Stop auto-updating, ALL-474 S2)
--   at      when the data last changed: the "Updated:" line (a date)
-- Encounters (note.unitMet / unitSeen, UN.NoteEncounters) are counted when
-- you target, inspect, group with or point at the player (Settings > Modules
-- > Player & NPC Notes), at most once per zone visit and 30 minutes apart.
-- A target or mouseover updates level, guild and title, a group member the
-- level, an inspect everything, gear too.
-- Updates are quiet: noTouch (no jump in "last edited"), no history snapshot.
-- A note open for editing (unsaved changes or the cursor in the editor,
-- Focus mode, sticky inline edit) keeps its text this time; the data is
-- saved and the text catches up on the next update.
-- Notes made before ALL-474 count encounters at once and join the text
-- updates after one "Update gear and note" (which makes a restore point).

local BNB = BigNoteBox
local L   = BNB.L
local UN  = BNB.UnitNotes

local GAP = 30 * 60   -- seconds between two counted encounters
local _visit = 0      -- zone visits this session: one count per player per visit
local _counted = {}   -- [noteID] = the _visit it was last counted in

local function DB(key)
    local db = BigNoteBoxDB
    local v = db and db[key]
    if v == nil then v = BNB.DEFAULTS[key] end
    return v
end

local function AutoOn()
    return DB("playerNoteAutoUpdate") and BNB.UnitNotesEnabled()
end

-- The note for a unit: a player note BNB made (source "inspect"). A note the
-- player made by hand with the player's situation is never changed.
local function NoteForUnit(unit)
    local id
    pcall(function()
        if not UnitIsPlayer(unit) or UnitIsUnit(unit, "player") then return end
        local name, realm = BNB.UnitNameRealm(unit)
        if not name or (issecretvalue and issecretvalue(name)) then return end   -- Midnight secret values
        realm = realm and realm ~= "" and realm or GetNormalizedRealmName() or ""
        id = UN.FindPlayerNote(name, realm)
    end)
    local note = id and BNB.GetNote(id)
    if note and note.source == "inspect" then return id, note end
end

local function BeingEdited(id)
    if BNB._currentNoteID == id then
        if BNB._dirty or (BNB._editorBody and BNB._editorBody:HasFocus())
           or (BNB.IsFocusModeOpen and BNB.IsFocusModeOpen()) then
            return true
        end
    end
    return BNB.Sticky and BNB.Sticky.IsEditing and BNB.Sticky.IsEditing(id) or false
end

-- What a unit tells without an inspect. full = target / mouseover (near you):
-- guild and title too; a group member only the level. A value the game does
-- not give right now stays nil and keeps the stored one: a guild is never
-- dropped from here.
local function UnitData(unit, full)
    local d = {}
    local lvl = UnitLevel(unit)
    if lvl and lvl > 0 then d.level = lvl end
    if full then
        local guild, rank = GetGuildInfo(unit)
        if guild and guild ~= "" then d.guild, d.guildRank = guild, rank end
        local name = BNB.UnitNameRealm(unit)
        local pvp = UnitPVPName(unit)
        if pvp and pvp ~= "" and pvp ~= name then d.displayTitle = pvp end
    end
    return d
end

local function Copy(t)
    local c = {}
    for k, v in pairs(t) do c[k] = v end
    return c
end

local function GearDiffers(a, b)
    if #a ~= #b then return true end
    for i = 1, #a do
        if a[i].linkData ~= b[i].linkData or a[i].ilvl ~= b[i].ilvl then return true end
    end
    return false
end

-- One update of one note. kind = "Target" / "Inspect" / "Group" /
-- "Mouseover" (the encounterOn<kind> setting); newData = values to merge into
-- the stored snapshot (nil = none); extra = fields to write as they are (the
-- inspect gear cards).
local function Update(id, note, kind, newData, extra)
    local fields = extra or {}
    local changed = extra ~= nil
    local now = time()

    -- Developer tools > encounters every minute (debugEncounterGap): no
    -- zone-visit rule, 60 s apart
    local quick = BigNoteBoxDB and BigNoteBoxDB.debugEncounterGap
    if DB("encounterOn" .. kind) and (quick or _counted[id] ~= _visit) then
        local enc = UN.NoteEncounters(note)
        if now - (enc.seen.at or 0) >= (quick and 60 or GAP) then
            _counted[id] = _visit
            fields.unitMet  = enc.met   -- written down once for an older note
            fields.unitSeen = { n = (enc.seen.n or 1) + 1, at = now, place = (UN.EncounteredPlace()) }
            changed = true
        end
    end

    local auto = note.unitAuto
    local snap = auto and auto.data
    if snap and newData then
        local newSnap
        for k, v in pairs(newData) do
            if k ~= "gear" and snap[k] ~= v then
                newSnap = newSnap or Copy(snap)
                newSnap[k] = v
            end
        end
        if newData.gear and #newData.gear > 0 and GearDiffers(snap.gear or {}, newData.gear) then
            newSnap = newSnap or Copy(snap)
            newSnap.gear = newData.gear
        end
        if newSnap then
            auto = Copy(auto); auto.data = newSnap; auto.at = now
            fields.unitAuto = auto
            changed = true
        end
    end

    -- The text, when something it shows changed
    if auto and auto.data and not auto.off and not auto.edited
       and (fields.unitAuto or fields.unitSeen) and not BeingEdited(id) then
        local top, rest = UN.SplitAtHead(note.body, auto.head)
        if not top or UN.Fingerprint(top) ~= auto.fp then
            auto = Copy(auto); auto.edited = true
            fields.unitAuto = auto
            changed = true
            BNB:Print(string.format(L["PNA_EDITED"], note.title or ""))
        else
            local enc = UN.NoteEncounters(note)
            enc.met  = fields.unitMet or enc.met
            enc.seen = fields.unitSeen or enc.seen
            enc.updated = auto.at
            local _, newTop = UN.BuildPlayerBody(auto.data, note.richMode, enc)
            if newTop ~= top then
                auto = Copy(auto); auto.fp = UN.Fingerprint(newTop)
                fields.unitAuto = auto
                fields.body = newTop .. rest
                changed = true
            end
        end
    end

    if not changed then return end
    BNB.UpdateNote(id, fields, { noTouch = true })
    if fields.body then UN.RefreshNoteViews(id) end
    if extra and BNB.RefreshReferenceBox then BNB.RefreshReferenceBox() end
end

local function Handle(unit, kind, full)
    if InCombatLockdown() then return end
    local id, note = NoteForUnit(unit)
    if not id then return end
    local d
    pcall(function() d = UnitData(unit, full) end)
    Update(id, note, kind, d)
end

-- Called by InspectNote when inspect data is ready (OnInspectReady)
function UN.AutoOnInspect()
    if not AutoOn() then return end
    C_Timer.After(0.2, function()
        if not (InspectFrame and InspectFrame:IsShown()) or InCombatLockdown() then return end
        local id, note = NoteForUnit(UN.InspectUnit())
        if not id then return end
        local data = UN.GatherInspectData()
        -- The gear cards, as "Update gear" does, once the gear has arrived
        local extra
        if #data.gearItems > 0 then
            extra = {
                inspectGearItems     = data.gearItems,
                inspectTransmogItems = #data.transmogItems > 0 and data.transmogItems or nil,
            }
            if next(data.transmogAppearances) then extra.inspectTransmogAppearances = data.transmogAppearances end
        end
        Update(id, note, "Inspect", UN.PlayerSnapshot(data), extra)
    end)
end

local function OnTarget() Handle("target", "Target", true) end
local function OnMouseover() Handle("mouseover", "Mouseover", true) end
local function OnGroup()
    if InCombatLockdown() then return end
    local raid = IsInRaid()
    local n = raid and GetNumGroupMembers() or GetNumSubgroupMembers()
    for i = 1, n do Handle((raid and "raid" or "party") .. i, "Group", false) end
end

BNB.RegisterEvent("ZONE_CHANGED_NEW_AREA", function() _visit = _visit + 1 end)
BNB.RegisterEvent("PLAYER_TARGET_CHANGED", function()
    if AutoOn() then BNB.Debounce("pnaTarget", 0.5, OnTarget) end
end)
BNB.RegisterEvent("UPDATE_MOUSEOVER_UNIT", function()
    if DB("encounterOnMouseover") and AutoOn() then BNB.Debounce("pnaMouseover", 0.3, OnMouseover) end
end)
BNB.RegisterEvent("GROUP_ROSTER_UPDATE", function()
    if DB("encounterOnGroup") and AutoOn() then BNB.Debounce("pnaGroup", 2, OnGroup) end
end)

-- BigNoteBox Features/TargetNote.lua
-- Creates notes from the current target (NPC, mob, boss, or player).
-- Triggered via keybind (BNB_KeybindTargetNote) or the unit right-click menu.
-- Does nothing if there is no target.
--
-- NPC notes are keyed by creature ID (from GUID) stored in note.targetNpcID.
-- Player notes are keyed by "player:<name>-<realm>" stored in note.targetPlayerKey.
-- Duplicate detection always uses these hidden fields, never the note title.
--
-- Config keys (BigNoteBoxDB):
--   targetNoteType:              "choose" (default) | "always_rich" | "always_normal"
--   targetNoteTagCreatureType:   bool (default true)  — add creature type as tag
--   targetNoteTagFamily:         bool (default false) — add creature family as tag
--   targetNoteTagClassification: bool (default true)  — add classification as tag
--   targetNoteTagFaction:        bool (default true)  — add faction as tag
--   targetNoteTagZone:           bool (default true)  — add zone as tag
--   targetNoteTagBoss:           bool (default true)  — add "Boss" tag for bosses
--
-- Public API:
--   BNB.TargetNote.Fire()   -- master entry point (keybind + menu)
--   BNB.TargetNote.Init()   -- called from Initialize; wires right-click menu hook

local BNB    = BigNoteBox
local L      = BNB.L
local UNKNOWN_STR = type(UNKNOWN) == "string" and UNKNOWN or "Unknown"
local ASSETS = "Interface\\AddOns\\BigNoteBox\\Assets\\"
local BTNS   = ASSETS .. "Buttons\\"
local ICONS  = "Interface\\Icons\\"

BNB.TargetNote = BNB.TargetNote or {}
local TN = BNB.TargetNote

--------------------------------------------------------------------------------
-- CONFIG HELPER
--------------------------------------------------------------------------------
local function GetType()
    local db = BigNoteBoxDB
    return db and db.targetNoteType or "choose"
end

-- Returns true if a tag config key is enabled (all default to true except Family).
local function TagEnabled(key, default)
    local db = BigNoteBoxDB
    if db == nil then return default end
    local v = db[key]
    if v == nil then return default end
    return v == true
end

--------------------------------------------------------------------------------
-- NUMBER FORMATTING (matches InspectNote style)
--------------------------------------------------------------------------------
local function FormatNumber(n)
    if not n then return "?" end
    -- The client's own thousands separator (ALL-72)
    if BreakUpLargeNumbers then return BreakUpLargeNumbers(math.floor(n)) end
    local s = tostring(math.floor(n))
    local pos, result = #s, ""
    while pos > 0 do
        local start = math.max(1, pos - 2)
        result = s:sub(start, pos) .. (result ~= "" and "," or "") .. result
        pos = start - 1
    end
    return result
end

--------------------------------------------------------------------------------
-- CREATURE-TYPE ICON MAPPING
-- Maps UnitCreatureType() strings to Interface\Icons texture names.
-- Used for the portrait icon in rich notes and as the note list icon.
--------------------------------------------------------------------------------
local CREATURE_TYPE_ICON = {
    -- Neutral silhouettes, not a human face: wrong on every non-human NPC. Only
    -- seen when no portrait is available (ALL-46, see NPC PORTRAITS below).
    ["Humanoid"]    = "INV_Misc_GroupNeedMore",
    ["Beast"]       = "ability_hunter_beastcall",
    ["Demon"]       = "Spell_Shadow_SummonFelHunter",
    ["Dragonkin"]   = "ability_dragonkin",
    ["Elemental"]   = "Spell_Fire_FireBolt",
    ["Giant"]       = "inv_misc_monsterhorn_08",
    ["Mechanical"]  = "Trade_Engineering",
    ["Undead"]      = "Spell_Shadow_RaiseDead",
    ["Aberration"]  = "inv_misc_slime_01",
    ["Uncategorized"] = "inv_misc_questionmark",
}

--------------------------------------------------------------------------------
-- NPC PORTRAITS (ALL-46)
-- A portrait image cannot be saved, but the creature display ID can, and
-- SetPortraitTextureFromCreatureDisplayID draws the face from it with no unit.
-- UnitDisplayID does not exist; a PlayerModel loaded with SetCreature(npcID)
-- reports the ID through GetDisplayInfo (SetUnit("target") reports 0). Probed
-- on Forever 2026-09-24: NPC 713 -> 1355, portrait drawn correctly.
-- Looked up once per NPC on first display and cached on the note as
-- targetDisplayID, so notes made before this fill in as they are shown.
-- Combat pets are skipped: their creature ID is shared (see targetIsPet).
--------------------------------------------------------------------------------
local OLD_HUMANOID_ICON = "achievement_character_human_male"
local NEUTRAL_ICON      = ICONS .. "INV_Misc_GroupNeedMore"

local _resolver         -- PlayerModel that reads display IDs
local _queue   = {}     -- npcIDs waiting, in order
local _queued  = {}     -- npcID -> true while waiting or in flight
local _failed  = {}     -- npcID -> true: gave up this session (not saved)
local _busy    = false
local _refreshPending = false

local function RefreshAfterResolve()
    if _refreshPending then return end
    _refreshPending = true
    C_Timer.After(0.2, function()
        _refreshPending = false
        if BNB.RefreshNoteList and BNB.mainFrame and BNB.mainFrame:IsShown() then
            BNB.RefreshNoteList()
        end
        if BNB.RefreshReferenceBoxTabs then BNB.RefreshReferenceBoxTabs() end
        if BNB.Sticky and BNB.Sticky.RefreshNpcPortraits then BNB.Sticky.RefreshNpcPortraits() end
    end)
end

local function StoreDisplayID(npcID, displayID)
    local ndb = BigNoteBoxNotesDB
    if not (ndb and ndb.notes) then return end
    for _, note in pairs(ndb.notes) do
        if note.source == "target" and note.targetNpcID == npcID and not note.targetIsPet then
            note.targetDisplayID = displayID
        end
    end
end

local function ProcessQueue()
    local npcID = table.remove(_queue, 1)
    if not npcID then
        _busy = false
        if _resolver then _resolver:Hide() end
        return
    end
    _busy = true
    if not _resolver then
        -- A model that is not drawn never loads: shown, 1px, bottom-left corner,
        -- under everything
        _resolver = CreateFrame("PlayerModel", nil, UIParent)
        _resolver:SetSize(1, 1)
        _resolver:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 0, 0)
        _resolver:SetFrameStrata("BACKGROUND")
    end
    _resolver:Show()
    -- Clear first so GetDisplayInfo cannot return the previous NPC's ID
    pcall(_resolver.ClearModel, _resolver)
    local ok = pcall(_resolver.SetCreature, _resolver, tonumber(npcID))
    local tries = 0
    local function Poll()
        tries = tries + 1
        local id = 0
        if ok then
            local okD, v = pcall(_resolver.GetDisplayInfo, _resolver)
            id = (okD and tonumber(v)) or 0
        end
        if id > 0 then
            StoreDisplayID(npcID, id)
            _queued[npcID] = nil
            RefreshAfterResolve()
            ProcessQueue()
        elseif not ok or tries >= 30 then   -- 3 s: creature not in the client cache
            _failed[npcID] = true
            _queued[npcID] = nil
            ProcessQueue()
        else
            C_Timer.After(0.1, Poll)
        end
    end
    C_Timer.After(0.1, Poll)
end

local function Enqueue(npcID)
    if _queued[npcID] or _failed[npcID] then return end
    _queued[npcID] = true
    _queue[#_queue + 1] = npcID
    if not _busy then ProcessQueue() end
end

-- Draws the NPC's portrait into tex for an NPC note. Returns true when drawn;
-- otherwise starts the display-ID lookup and returns false, and the caller
-- keeps the note icon (BNB.NpcNoteIcon).
function BNB.SetNpcNotePortrait(tex, note)
    if not (tex and note and note.source == "target" and note.targetNpcID)
       or note.targetIsPet then
        return false
    end
    local id = note.targetDisplayID
    if id and id > 0 and SetPortraitTextureFromCreatureDisplayID then
        return (pcall(SetPortraitTextureFromCreatureDisplayID, tex, id))
    end
    if not id then Enqueue(note.targetNpcID) end
    return false
end

-- The icon to show for a note. NPC notes made before ALL-46 stored a human
-- face for every humanoid; show the neutral icon instead (the saved note is
-- left as it is).
function BNB.NpcNoteIcon(note)
    local icon = note and note.icon
    if note and note.source == "target" and note.targetNpcID and type(icon) == "string"
       and icon:lower():find(OLD_HUMANOID_ICON, 1, true) then
        return NEUTRAL_ICON
    end
    return icon
end

-- Classification -> locale key for display and tag ("normal" is implied, not shown)
local CLASSIFICATION_KEY = {
    ["elite"]      = "TGT_CLASS_ELITE",
    ["rareelite"]  = "TGT_CLASS_RAREELITE",
    ["rare"]       = "TGT_CLASS_RARE",
    ["worldboss"]  = "TGT_CLASS_WORLDBOSS",
    ["trivial"]    = "TGT_CLASS_TRIVIAL",
}

-- Creature type id -> CREATURE_TYPE_ICON key. UnitCreatureType is translated, so on
-- a non-English client the name is mapped back through C_CreatureInfo (ALL-72).
local CREATURE_TYPE_KEY_BY_ID = {
    [1] = "Beast", [2] = "Dragonkin", [3] = "Demon", [4] = "Elemental", [5] = "Giant",
    [6] = "Undead", [7] = "Humanoid", [9] = "Mechanical", [15] = "Aberration",
}
local _ctKeyByName
local function CreatureTypeKey(locName)
    if not locName then return nil end
    if CREATURE_TYPE_ICON[locName] then return locName end   -- English client
    if not _ctKeyByName then
        _ctKeyByName = {}
        local getInfo = C_CreatureInfo and C_CreatureInfo.GetCreatureTypeInfo
        if getInfo then
            for id, key in pairs(CREATURE_TYPE_KEY_BY_ID) do
                local ok, info = pcall(getInfo, id)
                local name = ok and (type(info) == "table" and info.name or type(info) == "string" and info)
                if name then _ctKeyByName[name] = key end
            end
        end
    end
    return _ctKeyByName[locName]
end

-- English fallback only; the display name comes from _G[powerToken] (ALL-72)
local POWER_TYPE_NAME = {
    [0]  = "Mana",
    [1]  = "Rage",
    [2]  = "Focus",
    [3]  = "Energy",
    [6]  = "Runic Power",
    [7]  = "Soul Shards",
    [8]  = "Lunar Power",
    [9]  = "Holy Power",
    [11] = "Maelstrom",
    [13] = "Insanity",
    [17] = "Fury",
    [18] = "Pain",
    [26] = "Essence",
}

-- Reaction index -> colour hex (for rich note reaction line)
local REACTION_HEX = {
    [1] = "ff2020",  -- Hated
    [2] = "ff2020",  -- Hostile
    [3] = "ff6020",  -- Unfriendly
    [4] = "ffff00",  -- Neutral
    [5] = "40d040",  -- Friendly
    [6] = "40d040",  -- Honored
    [7] = "40d040",  -- Revered
    [8] = "40d040",  -- Exalted
}
-- English fallback only; the display name is FACTION_STANDING_LABEL<n> (ALL-72)
local REACTION_LABEL = {
    [1] = "Hated",
    [2] = "Hostile",
    [3] = "Unfriendly",
    [4] = "Neutral",
    [5] = "Friendly",
    [6] = "Honored",
    [7] = "Revered",
    [8] = "Exalted",
}

--------------------------------------------------------------------------------
-- GUID PARSING: extract creature ID from NPC/pet/vehicle GUID
-- Formats:
--   Creature-0-REALM-MAP-ID-CREATUREID-SPAWNUID  (NPCs, mobs, bosses)
--   Vehicle-0-REALM-MAP-ID-CREATUREID-SPAWNUID   (vehicles)
--   Pet-0-REALM-MAP-ID-CREATUREID-SPAWNUID       (combat pets: hunter pets, warlock demons, etc.)
-- Returns creature ID string, or nil if not a recognised targetable creature GUID.
-- Note: BattlePet GUIDs exist but only appear during pet battles, not normal targeting.
--------------------------------------------------------------------------------
local function GetCreatureID(guid)
    if not guid then return nil end
    return guid:match("^Creature%-0%-%d+%-%d+%-%d+%-(%d+)")
        or guid:match("^Vehicle%-0%-%d+%-%d+%-%d+%-(%d+)")
        or guid:match("^Pet%-0%-%d+%-%d+%-%d+%-(%d+)")
end

--------------------------------------------------------------------------------
-- DATA GATHERING
--------------------------------------------------------------------------------
local function GatherTargetData()
    local data = {}

    data.isPlayer = UnitIsPlayer("target")

    -- Name + realm
    local name, realm = BNB.UnitNameRealm("target")   -- FOR-23: Forever surname
    data.name  = name or UNKNOWN_STR
    data.realm = (realm and realm ~= "") and realm or
                 GetNormalizedRealmName() or ""

    -- GUID and NPC ID
    local guid = UnitGUID("target")
    data.guid = guid
    data.npcID = not data.isPlayer and GetCreatureID(guid) or nil
    -- Combat pets (hunter pets, warlock demons) share a generic creature ID across
    -- all pet instances. The name and model are per-instance, so we need a different
    -- duplicate detection key and cannot use SetCreature for the model viewer.
    data.isPet = guid and guid:match("^Pet%-") ~= nil or false

    -- Level (-1 means skull/boss)
    local lvl = UnitLevel("target")
    data.level = (lvl == -1) and "??" or lvl

    -- Display ID: UnitDisplayID does not exist on Midnight retail.
    -- Model viewer uses SetCreature(npcID) instead, which takes the creature ID
    -- from the GUID. No display ID needed.
    data.displayID = nil

    -- Faction: English token for logic (icon, model crest); factionLabel = translated
    local factionEn, factionLoc = UnitFactionGroup("target")
    data.faction      = factionEn
    data.factionLabel = factionLoc or factionEn

    -- Reaction to player
    local reactionIdx = UnitReaction("player", "target")
    data.reactionIdx   = reactionIdx
    local standing     = reactionIdx and _G["FACTION_STANDING_LABEL" .. reactionIdx]
    data.reactionLabel = type(standing) == "string" and standing
                         or (reactionIdx and REACTION_LABEL[reactionIdx]) or nil
    data.reactionHex   = reactionIdx and REACTION_HEX[reactionIdx] or nil

    -- Zone where encountered
    data.zone    = GetZoneText() or ""
    data.subZone = GetSubZoneText() or ""

    if data.isPlayer then
        -- ── Player branch ──────────────────────────────────────────────────
        local pvpName = UnitPVPName("target")
        if pvpName and pvpName ~= data.name then
            data.displayTitle = pvpName
        end

        local className, classFile = UnitClass("target")
        data.className = className or UNKNOWN_STR
        data.classFile = classFile or "WARRIOR"

        local raceName, raceFile = UnitRace("target")
        data.race     = raceName or UNKNOWN_STR
        data.raceFile = raceFile or "Human"

        local sex = UnitSex("target")
        data.gender = (sex == 3) and "Female" or "Male"

        local cc = RAID_CLASS_COLORS and RAID_CLASS_COLORS[data.classFile]
        if cc then
            data.classHex = string.format("%02x%02x%02x",
                math.floor(cc.r * 255 + 0.5),
                math.floor(cc.g * 255 + 0.5),
                math.floor(cc.b * 255 + 0.5))
        else
            data.classHex = "ffffff"
        end

        -- Class icon path (bundled asset)
        data.portraitIcon = ASSETS .. "Icons\\Classes\\ClassIcon_" .. (data.classFile or "Warrior")
    else
        -- ── NPC / mob / boss branch ────────────────────────────────────────
        local ctName, ctID  = UnitCreatureType("target")   -- translated name, type id
        data.creatureType   = ctName
        -- English key, icons only: by id first, then the name mapped back
        data.creatureTypeKey = CREATURE_TYPE_KEY_BY_ID[ctID] or CreatureTypeKey(ctName)
        data.creatureFamily = UnitCreatureFamily("target")  -- may be nil

        local classification = UnitClassification("target")
        data.classification      = classification
        local classKey = CLASSIFICATION_KEY[classification or "normal"]
        data.classificationLabel = classKey and L[classKey] or nil
        data.isBoss = (classification == "worldboss") or (data.level == "??")

        -- Max health — UnitHealthMax returns a "secret" (taint-protected) value
        -- in keybind execution contexts on retail. The comparison must also happen
        -- inside pcall — taint escapes if the secret value is compared outside it.
        pcall(function()
            local maxHP = UnitHealthMax("target")
            if maxHP and maxHP > 0 then data.maxHealth = maxHP end
        end)

        -- Power — same taint risk; entire read + comparison inside pcall.
        pcall(function()
            local powerIdx, powerToken = UnitPowerType("target")
            local maxPow = UnitPowerMax("target")
            if maxPow and maxPow > 0 then
                data.powerIdx  = powerIdx
                local g = powerToken and _G[powerToken]
                data.powerName = (type(g) == "string" and g ~= "" and g)
                              or POWER_TYPE_NAME[powerIdx]
                              or (powerToken and powerToken:gsub("_", " "):gsub("(%a)([%w]*)", function(a, b)
                                    return a:upper() .. b:lower()
                                 end))
                              or L["TGT_POWER"]
                data.maxPower = maxPow
            end
        end)

        -- NPC portrait icon: use creature-type mapped icon, fallback to note icon
        local ctIcon = CREATURE_TYPE_ICON[data.creatureTypeKey or ""] or "inv_misc_questionmark"
        data.portraitIcon = ICONS .. ctIcon

        -- Note list icon: same creature-type icon
        data.noteIcon = data.portraitIcon
    end

    return data
end

--------------------------------------------------------------------------------
-- NOTE BODY BUILDERS — NORMAL
--------------------------------------------------------------------------------
local function BuildNormalBody(data)
    local lines = {}

    if data.isPlayer then
        -- Name / title
        lines[#lines + 1] = data.displayTitle or data.name
        lines[#lines + 1] = ""

        lines[#lines + 1] = string.format(L["TGT_LEVEL_FMT"], tostring(data.level), data.race, data.className)

        if data.factionLabel then
            lines[#lines + 1] = string.format(L["TGT_LINE_FACTION"], data.factionLabel)
        end
        if data.reactionLabel then
            lines[#lines + 1] = string.format(L["TGT_LINE_REACTION"], data.reactionLabel)
        end
    else
        lines[#lines + 1] = data.name
        lines[#lines + 1] = ""

        -- Level + classification
        local classif = data.classificationLabel and (" [" .. data.classificationLabel .. "]") or ""
        lines[#lines + 1] = string.format(L["TGT_LEVEL_NPC_FMT"], tostring(data.level)) .. classif

        if data.creatureType then
            local typeStr = data.creatureType
            if data.creatureFamily then
                typeStr = typeStr .. " (" .. data.creatureFamily .. ")"
            end
            lines[#lines + 1] = string.format(L["TGT_LINE_TYPE"], typeStr)
        end

        if data.factionLabel then
            lines[#lines + 1] = string.format(L["TGT_LINE_FACTION"], data.factionLabel)
        end
        if data.reactionLabel then
            lines[#lines + 1] = string.format(L["TGT_LINE_REACTION"], data.reactionLabel)
        end

        lines[#lines + 1] = ""

        if data.maxHealth then
            lines[#lines + 1] = string.format(L["TGT_LINE_MAX_HEALTH"], FormatNumber(data.maxHealth))
        end
        if data.maxPower then
            lines[#lines + 1] = string.format(L["TGT_LINE_STAT_FMT"], data.powerName or L["TGT_POWER"], FormatNumber(data.maxPower))
        end
    end

    lines[#lines + 1] = ""
    -- Zone footer
    local zoneStr = data.zone
    if data.subZone and data.subZone ~= "" and data.subZone ~= data.zone then
        zoneStr = data.subZone .. ", " .. data.zone
    end
    if zoneStr ~= "" then
        lines[#lines + 1] = string.format(L["TGT_LINE_ENCOUNTERED"], zoneStr)
    end

    return table.concat(lines, "\n")
end

--------------------------------------------------------------------------------
-- NOTE BODY BUILDERS — RICH
-- Layout for NPC (the interesting case):
--   [centered creature-type icon 64x64]
--   {h1:c} Name {/h1}
--   {p:c} Level XX [Classification] {/p}
--   {p:c} {col:hex} Reaction {/col} {/p}
--   [rule implied by blank lines]
--   {h3} Details {/h3}
--   Type, family, faction, health, power
--   {h3} Encountered {/h3}
--   Zone
--------------------------------------------------------------------------------
local function BuildRichBody(data)
    local lines = {}

    if data.isPlayer then
        local displayName = data.displayTitle or data.name
        lines[#lines + 1] = "{h1:c}" .. displayName .. "{/h1}"
        lines[#lines + 1] = ""

        local sub = string.format(L["TGT_LEVEL_FMT"], tostring(data.level), data.race, data.className)
        lines[#lines + 1] = "{p:c}{col:" .. (data.classHex or "ffffff") .. "}" .. sub .. "{/col}{/p}"
        lines[#lines + 1] = ""

        if data.factionLabel then
            lines[#lines + 1] = "{p:c}" .. data.factionLabel .. "{/p}"
        end
        if data.reactionLabel and data.reactionHex then
            lines[#lines + 1] = "{p:c}{col:" .. data.reactionHex .. "}" .. data.reactionLabel .. "{/col}{/p}"
        end
        lines[#lines + 1] = ""
        lines[#lines + 1] = ""
    else
        -- ── NPC / mob / boss ──────────────────────────────────────────────

        -- Name as H1
        lines[#lines + 1] = "{h1:c}" .. data.name .. "{/h1}"
        lines[#lines + 1] = ""

        -- Level + classification subtitle
        local classif = data.classificationLabel and (" {col:ffcc44}[" .. data.classificationLabel .. "]{/col}") or ""
        lines[#lines + 1] = "{p:c}" .. string.format(L["TGT_LEVEL_NPC_FMT"], tostring(data.level)) .. classif .. "{/p}"
        lines[#lines + 1] = ""

        -- Reaction line (coloured)
        if data.reactionLabel and data.reactionHex then
            lines[#lines + 1] = "{p:c}{col:" .. data.reactionHex .. "}" .. data.reactionLabel .. "{/col}{/p}"
        end
        lines[#lines + 1] = ""

        -- Details section
        local hasDetails = data.creatureType or data.faction or data.maxHealth or data.maxPower
        if hasDetails then
            lines[#lines + 1] = "{h3}" .. L["TGT_HDR_DETAILS"] .. "{/h3}"
            lines[#lines + 1] = ""

            if data.creatureType then
                local typeStr = data.creatureType
                if data.creatureFamily then
                    typeStr = typeStr .. " (" .. data.creatureFamily .. ")"
                end
                -- Inline creature-type icon (18px) before the label
                local ctIcon = CREATURE_TYPE_ICON[data.creatureTypeKey or ""] or "inv_misc_questionmark"
                lines[#lines + 1] = "{p}{icon:" .. ctIcon .. ":18}  " .. string.format(L["TGT_LINE_TYPE"], typeStr) .. "{/p}"
            end

            if data.faction then
                -- Faction icon
                local factionIcon = "inv_misc_questionmark"
                if data.faction == "Alliance" then
                    factionIcon = "ui_allianceicon"
                elseif data.faction == "Horde" then
                    factionIcon = "ui_hordeicon"
                end
                lines[#lines + 1] = "{p}{icon:" .. factionIcon .. ":18}  " .. string.format(L["TGT_LINE_FACTION"], data.factionLabel or data.faction) .. "{/p}"
            end

            if data.maxHealth then
                lines[#lines + 1] = "{p}{icon:inv_elemental_mote_life01:18}  " .. string.format(L["TGT_LINE_MAX_HEALTH"], FormatNumber(data.maxHealth)) .. "{/p}"
            end

            if data.maxPower then
                -- Power icon varies by type (by index: the name is translated)
                local powerIcon = "inv_misc_questionmark"
                local pi = data.powerIdx
                if pi == 0 then                    -- Mana
                    powerIcon = "inv_elemental_mote_mana"
                elseif pi == 1 or pi == 17 then    -- Rage, Fury
                    powerIcon = "ability_racial_bloodrage"
                elseif pi == 3 or pi == 2 then     -- Energy, Focus
                    powerIcon = "ability_druid_caster"
                elseif pi == 6 then                -- Runic Power
                    powerIcon = "inv_sword_62"
                end
                lines[#lines + 1] = "{p}{icon:" .. powerIcon .. ":18}  " .. string.format(L["TGT_LINE_STAT_FMT"], data.powerName or L["TGT_POWER"], FormatNumber(data.maxPower)) .. "{/p}"
            end

            lines[#lines + 1] = ""
            lines[#lines + 1] = ""
        end

        -- Zone / encounter section
        local zoneStr = data.zone
        if data.subZone and data.subZone ~= "" and data.subZone ~= data.zone then
            zoneStr = data.subZone .. ", " .. data.zone
        end
        if zoneStr and zoneStr ~= "" then
            lines[#lines + 1] = "{h3}" .. L["TGT_HDR_ENCOUNTERED"] .. "{/h3}"
            lines[#lines + 1] = ""
            lines[#lines + 1] = "{p}{icon:achievement_zone_northrend_01:18}  " .. zoneStr .. "{/p}"
            lines[#lines + 1] = ""
            lines[#lines + 1] = ""
        end
    end

    -- Notes section: blank, for the player to fill in.
    -- A bare empty line is intentional — {p}{/p} produces an empty <P></P> in
    -- SimpleHTML which miscalculates document height and offsets the text cursor.
    lines[#lines + 1] = "{h3}" .. L["TGT_HDR_NOTES"] .. "{/h3}"
    lines[#lines + 1] = ""

    return table.concat(lines, "\n")
end

--------------------------------------------------------------------------------
-- DUPLICATE DETECTION
-- Checks note.targetNpcID (for NPCs) or note.targetPlayerKey (for players).
-- Never checks title — title can be renamed freely.
--------------------------------------------------------------------------------
local function FindExistingNote(data)
    local ndb = BigNoteBoxNotesDB
    if not ndb or not ndb.notes then return nil end

    if data.isPlayer then
        local key = "player:" .. data.name
        if data.realm and data.realm ~= "" then
            key = key .. "-" .. data.realm
        end
        for id, note in pairs(ndb.notes) do
            if note.targetPlayerKey == key then return id end
        end
    elseif data.isPet then
        -- Combat pets share a generic creature ID — match on name + npcID
        for id, note in pairs(ndb.notes) do
            if note.targetNpcID == data.npcID and note.title == data.name then return id end
        end
    else
        if data.npcID then
            for id, note in pairs(ndb.notes) do
                if note.targetNpcID == data.npcID then return id end
            end
        end
    end
    return nil
end

local function MakeUniqueTitle(baseName)
    local ndb = BigNoteBoxNotesDB
    if not ndb or not ndb.notes then return baseName end
    local exists = false
    for _, note in pairs(ndb.notes) do
        if note.title == baseName then exists = true; break end
    end
    if not exists then return baseName end
    for i = 1, 100 do
        local c = baseName .. " (" .. i .. ")"
        local found = false
        for _, note in pairs(ndb.notes) do
            if note.title == c then found = true; break end
        end
        if not found then return c end
    end
    return baseName
end

--------------------------------------------------------------------------------
-- OPEN EXISTING NOTE
--------------------------------------------------------------------------------
local function OpenExistingNote(noteID)
    if BNB.OpenMainWindow then BNB.OpenMainWindow() end
    if BNB.SelectNote then
        if BNB.SaveCurrentNote then BNB.SaveCurrentNote() end
        BNB.SelectNote(noteID)
    end
    if BNB.RefreshNoteList then BNB.RefreshNoteList() end
end

--------------------------------------------------------------------------------
-- CREATE THE NOTE
--------------------------------------------------------------------------------
local function CreateTargetNote(richMode, data)
    local title = MakeUniqueTitle(data.name)
    local body  = richMode and BuildRichBody(data) or BuildNormalBody(data)

    local noteID = BNB.CreateNote(title, body)
    if not noteID then return end

    -- Icon for the note list
    local noteIcon
    if data.isPlayer then
        -- Class icon from bundled assets
        noteIcon = ASSETS .. "Icons\\Classes\\ClassIcon_" .. (data.classFile or "Warrior")
    else
        noteIcon = data.noteIcon
    end

    -- Tags — "Target Note" is always added. All others are user-configurable.
    local tags = { L["TGT_TAG_TARGET"] }
    if data.isPlayer then
        if TagEnabled("targetNoteTagFaction", true) and data.factionLabel then
            tags[#tags + 1] = data.factionLabel
        end
        if TagEnabled("targetNoteTagZone", true) and data.zone and data.zone ~= "" then
            tags[#tags + 1] = data.zone
        end
    else
        if TagEnabled("targetNoteTagCreatureType", true) and data.creatureType then
            tags[#tags + 1] = data.creatureType
        end
        if TagEnabled("targetNoteTagFamily", false) and data.creatureFamily then
            tags[#tags + 1] = data.creatureFamily
        end
        if TagEnabled("targetNoteTagClassification", true) and data.classificationLabel then
            tags[#tags + 1] = data.classificationLabel
        end
        if TagEnabled("targetNoteTagFaction", true) and data.factionLabel then
            tags[#tags + 1] = data.factionLabel
        end
        if TagEnabled("targetNoteTagZone", true) and data.zone and data.zone ~= "" then
            tags[#tags + 1] = data.zone
        end
        if TagEnabled("targetNoteTagBoss", true) and data.isBoss then
            tags[#tags + 1] = L["TGT_TAG_BOSS"]
        end
    end

    local fields = {
        source   = "target",
        richMode = richMode or false,
        icon     = noteIcon,
        tags     = tags,
    }

    -- Faction token ("Horde"/"Alliance"; nil for neutral) for the model
    -- viewer's crest (FOR-22), independent of the faction tag setting
    fields.targetFaction = data.faction

    -- Hidden duplicate-detection keys
    if data.isPlayer then
        local key = "player:" .. data.name
        if data.realm and data.realm ~= "" then key = key .. "-" .. data.realm end
        fields.targetPlayerKey = key
        -- Title colour from class colour
        local cc = RAID_CLASS_COLORS and data.classFile and RAID_CLASS_COLORS[data.classFile]
        if cc then
            fields.titleColor = { r = cc.r, g = cc.g, b = cc.b }
        end
    else
        fields.targetNpcID = data.npcID  -- may be nil for vehicles/objects without creature ID
        if data.isPet then
            fields.targetIsPet = true  -- combat pet: SetCreature shows wrong model
        end
    end

    BNB.UpdateNote(noteID, fields)

    -- Select the note so SyncReferenceBox fires with the fully populated note
    -- (targetNpcID must be set before SelectNote, which is why we call it
    -- after UpdateNote rather than after CreateNote).
    if BNB.RefreshNoteList then BNB.RefreshNoteList() end
    if BNB.SelectNote then
        if BNB.SaveCurrentNote then BNB.SaveCurrentNote() end
        BNB.SelectNote(noteID)
    end

    return noteID
end

--------------------------------------------------------------------------------
-- TYPE DIALOG: "Normal" or "Rich" (self-contained, skin-aware)
--------------------------------------------------------------------------------
local _typeDialog = nil

local function ShowTypeDialog(data)
    if not _typeDialog then
        local f
        if BigNoteBoxDB and BigNoteBoxDB.skinMode and BNB.CreateSkinFrame then
            f = BNB.CreateSkinFrame(UIParent, false, "BNBTargetNoteTypeDialog", false)
            _G["BNBTargetNoteTypeDialog"] = f
            f:SetSize(220, 100)
            f:SetPoint("CENTER")
            f:SetFrameStrata("DIALOG")
            f:SetToplevel(true)
            f:EnableMouse(true)
            f:SetMovable(true)
            f:RegisterForDrag("LeftButton")
            f:SetScript("OnDragStart", function(self) self:StartMoving() end)
            f:SetScript("OnDragStop",  function(self) self:StopMovingOrSizing() end)

            local tb = BNB.CreateSkinStrip(f, true, false)
            tb:SetPoint("TOPLEFT",  f, "TOPLEFT",  0, 0)
            tb:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
            tb:SetHeight(26)
            tb:EnableMouse(true)
            tb:RegisterForDrag("LeftButton")
            tb:SetScript("OnDragStart", function() f:StartMoving() end)
            tb:SetScript("OnDragStop",  function() f:StopMovingOrSizing() end)

            local tl = tb:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            tl:SetPoint("CENTER", tb, "CENTER", -12, 0)
            tl:SetTextColor(1, 0.82, 0)
            tl:SetText(L["TGT_CREATE_TITLE"])

            BNB.CreateSkinCloseButton(tb, function() f:Hide() end)
                :SetPoint("RIGHT", tb, "RIGHT", -3, 0)

            local nb = BNB.CreateButton(nil, f, L["SW_MODE_NORMAL"], 85, 28)
            nb:SetPoint("BOTTOMLEFT",  f, "BOTTOMLEFT",  14, 14)
            f._normalBtn = nb

            local rb = BNB.CreateButton(nil, f, L["INS_RICH_BTN"], 85, 28)
            rb:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -14, 14)
            f._richBtn = rb

            f:SetScript("OnShow", function()
                if BNB.ApplyMainWindowSkin then BNB.ApplyMainWindowSkin() end
            end)
        else
            f = CreateFrame("Frame", "BNBTargetNoteTypeDialog", UIParent,
                            "BasicFrameTemplateWithInset")
            f:SetSize(220, 100)
            f:SetPoint("CENTER")
            f:SetFrameStrata("DIALOG")
            f:SetToplevel(true)
            f:EnableMouse(true)
            f:SetMovable(true)
            f:RegisterForDrag("LeftButton")
            f:SetScript("OnDragStart", function(self) self:StartMoving() end)
            f:SetScript("OnDragStop",  function(self) self:StopMovingOrSizing() end)
            f.TitleText:SetText(L["TGT_CREATE_TITLE"])

            local nb = BNB.CreateButton(nil, f, L["SW_MODE_NORMAL"], 85, 28)
            nb:SetPoint("BOTTOMLEFT",  f, "BOTTOMLEFT",  14, 14)
            f._normalBtn = nb

            local rb = BNB.CreateButton(nil, f, L["INS_RICH_BTN"], 85, 28)
            rb:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -14, 14)
            f._richBtn = rb
        end

        f:Hide()
        tinsert(UISpecialFrames, "BNBTargetNoteTypeDialog")
        _typeDialog = f
    end

    -- Wire buttons to the current data snapshot (captured in closure)
    _typeDialog._normalBtn:SetScript("OnClick", function()
        _typeDialog:Hide()
        CreateTargetNote(false, data)
    end)
    _typeDialog._richBtn:SetScript("OnClick", function()
        _typeDialog:Hide()
        CreateTargetNote(true, data)
    end)
    _typeDialog:Show()
end

--------------------------------------------------------------------------------
-- WARNING DIALOG: "You already have a note for [Name]"
--------------------------------------------------------------------------------
local _warnDialog = nil

local function ShowWarningDialog(existingNoteID, targetName, onDuplicate)
    if not _warnDialog then
        local f
        if BigNoteBoxDB and BigNoteBoxDB.skinMode and BNB.CreateSkinFrame then
            f = BNB.CreateSkinFrame(UIParent, false, "BNBTargetNoteWarnDialog", false)
            _G["BNBTargetNoteWarnDialog"] = f
            f:SetSize(320, 130)
            f:SetPoint("CENTER")
            f:SetFrameStrata("DIALOG")
            f:SetToplevel(true)
            f:EnableMouse(true)
            f:SetMovable(true)
            f:RegisterForDrag("LeftButton")
            f:SetScript("OnDragStart", function(self) self:StartMoving() end)
            f:SetScript("OnDragStop",  function(self) self:StopMovingOrSizing() end)

            local tb = BNB.CreateSkinStrip(f, true, false)
            tb:SetPoint("TOPLEFT",  f, "TOPLEFT",  0, 0)
            tb:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
            tb:SetHeight(26)
            tb:EnableMouse(true)
            tb:RegisterForDrag("LeftButton")
            tb:SetScript("OnDragStart", function() f:StartMoving() end)
            tb:SetScript("OnDragStop",  function() f:StopMovingOrSizing() end)

            local tl = tb:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            tl:SetPoint("CENTER", tb, "CENTER", -12, 0)
            tl:SetTextColor(1, 0.82, 0)
            tl:SetText(L["INS_NOTE_EXISTS"])

            BNB.CreateSkinCloseButton(tb, function() f:Hide() end)
                :SetPoint("RIGHT", tb, "RIGHT", -3, 0)

            local msg = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            msg:SetPoint("TOP",   f, "TOP",   0,   -38)
            msg:SetPoint("LEFT",  f, "LEFT",  16,  0)
            msg:SetPoint("RIGHT", f, "RIGHT", -16, 0)
            msg:SetJustifyH("CENTER")
            msg:SetWordWrap(true)
            f._msgLbl = msg

            f._openBtn = BNB.CreateButton(nil, f, L["AO_OPEN_NOTE_BTN"], 90, 26)
            f._openBtn:SetPoint("BOTTOMLEFT",  f, "BOTTOMLEFT",  14, 14)

            f._dupeBtn = BNB.CreateButton(nil, f, L["INS_WARN_DUPLICATE"], 110, 26)
            f._dupeBtn:SetPoint("BOTTOM",      f, "BOTTOM",       0,  14)

            local cancelBtn = BNB.CreateButton(nil, f, L["CLOSE"], 70, 26)
            cancelBtn:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -14, 14)
            cancelBtn:SetScript("OnClick", function() f:Hide() end)

            f:SetScript("OnShow", function()
                if BNB.ApplyMainWindowSkin then BNB.ApplyMainWindowSkin() end
            end)
        else
            f = CreateFrame("Frame", "BNBTargetNoteWarnDialog", UIParent,
                            "BasicFrameTemplateWithInset")
            f:SetSize(320, 130)
            f:SetPoint("CENTER")
            f:SetFrameStrata("DIALOG")
            f:SetToplevel(true)
            f:EnableMouse(true)
            f:SetMovable(true)
            f:RegisterForDrag("LeftButton")
            f:SetScript("OnDragStart", function(self) self:StartMoving() end)
            f:SetScript("OnDragStop",  function(self) self:StopMovingOrSizing() end)
            f.TitleText:SetText(L["INS_NOTE_EXISTS"])

            local msg = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            msg:SetPoint("TOP",   f, "TOP",   0,   -38)
            msg:SetPoint("LEFT",  f, "LEFT",  16,  0)
            msg:SetPoint("RIGHT", f, "RIGHT", -16, 0)
            msg:SetJustifyH("CENTER")
            msg:SetWordWrap(true)
            f._msgLbl = msg

            f._openBtn = BNB.CreateButton(nil, f, L["AO_OPEN_NOTE_BTN"], 90, 26)
            f._openBtn:SetPoint("BOTTOMLEFT",  f, "BOTTOMLEFT",  14, 14)

            f._dupeBtn = BNB.CreateButton(nil, f, L["INS_WARN_DUPLICATE"], 110, 26)
            f._dupeBtn:SetPoint("BOTTOM",      f, "BOTTOM",       0,  14)

            local cancelBtn = BNB.CreateButton(nil, f, L["CLOSE"], 70, 26)
            cancelBtn:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -14, 14)
            cancelBtn:SetScript("OnClick", function() f:Hide() end)
        end

        f:Hide()
        tinsert(UISpecialFrames, "BNBTargetNoteWarnDialog")
        _warnDialog = f
    end

    _warnDialog._msgLbl:SetText(string.format(L["INS_WARN_EXISTS_FMT"], targetName))
    _warnDialog._openBtn:SetScript("OnClick", function()
        OpenExistingNote(existingNoteID)
        _warnDialog:Hide()
    end)
    _warnDialog._dupeBtn:SetScript("OnClick", function()
        _warnDialog:Hide()
        if onDuplicate then onDuplicate() end
    end)
    _warnDialog:Show()
end

--------------------------------------------------------------------------------
-- MASTER FLOW
-- Called from both keybind and right-click menu.
-- data is optional — if nil, GatherTargetData() is called internally.
--------------------------------------------------------------------------------
local function StartTargetNoteFlow(data)
    if not UnitExists("target") then return end
    data = data or GatherTargetData()

    -- Player targets redirect to the full InspectNote system (gear, model, attachments).
    -- InspectUnit opens the Inspect frame and fires INSPECT_READY, which InspectNote
    -- picks up via the BNB._inspectAndCreate one-shot flag.
    if data.isPlayer then
        if not CanInspect or not CanInspect("target") then
            BNB:Print(L["TGT_CANNOT_INSPECT"])
            return
        end
        BNB._inspectAndCreate = true
        InspectUnit("target")
        return
    end

    local existingID = FindExistingNote(data)

    local noteType = GetType()
    local richMode = nil  -- nil = ask user

    if noteType == "always_rich" then
        richMode = true
    elseif noteType == "always_normal" then
        richMode = false
    end

    if existingID then
        ShowWarningDialog(existingID, data.name, function()
            -- On "Create Duplicate": proceed to type selection or direct create
            if richMode ~= nil then
                CreateTargetNote(richMode, data)
            else
                ShowTypeDialog(data)
            end
        end)
    else
        if richMode ~= nil then
            CreateTargetNote(richMode, data)
        else
            ShowTypeDialog(data)
        end
    end
end

-- Public entry point
function TN.Fire()
    if InCombatLockdown() then return end
    if not UnitExists("target") then return end
    StartTargetNoteFlow()
end

--------------------------------------------------------------------------------
-- RIGHT-CLICK UNIT MENU HOOK
-- On Midnight retail (12.x) the portrait right-click menu uses Menu.ModifyMenu.
-- Tags follow the pattern "MENU_UNIT_<WHICH>" where WHICH comes from
-- contextData.which (e.g. "PLAYER", "TARGET", "SELF", "FOCUS", "BOSS", ...).
-- Each Menu.ModifyMenu call needs a unique closure — if the same closure is
-- reused, later registrations silently replace earlier ones (TRP3 comment).
-- contextData.unit contains the unit token for the clicked frame.
-- GatherTargetData always reads "target", so we gate on UnitIsUnit(unit, "target").
--------------------------------------------------------------------------------

-- Tags to hook — covers all unit popup contexts where note creation makes sense.
local MENU_TAGS = {
    "PLAYER",       -- right-click a player target portrait
    "TARGET",       -- right-click an NPC/mob/boss target portrait
    "SELF",         -- right-click own portrait
    "FOCUS",        -- right-click focus frame
    "BOSS",         -- right-click boss frame
    "PARTY",        -- right-click party member frame
    "RAID",         -- right-click raid member frame
    "RAID_PLAYER",  -- alternate raid player tag
}

local function OnUnitMenuOpen(owner, rootDescription, contextData)
    local unit = contextData and contextData.unit
    if not unit then return end
    if not UnitExists(unit) then return end

    -- GatherTargetData reads "target", so only add entry when the
    -- right-clicked unit IS the current target.
    if not UnitIsUnit(unit, "target") then return end

    local data = GatherTargetData()
    local existingID = FindExistingNote(data)

    rootDescription:CreateDivider()

    if existingID then
        rootDescription:CreateButton(L["TGT_MENU_OPEN"], function()
            OpenExistingNote(existingID)
        end)
    else
        rootDescription:CreateButton(L["TGT_MENU_CREATE"], function()
            StartTargetNoteFlow(data)
        end)
    end
end

local function HookUnitPopupMenu()
    if not Menu or not Menu.ModifyMenu then return end

    for _, tag in ipairs(MENU_TAGS) do
        -- Each iteration needs a unique closure (not a shared reference)
        -- so successive registrations don't replace previous ones.
        local function MenuCallback(owner, rootDescription, contextData)
            OnUnitMenuOpen(owner, rootDescription, contextData)
        end
        Menu.ModifyMenu("MENU_UNIT_" .. tag, MenuCallback)
    end
end

--------------------------------------------------------------------------------
-- INIT (called from Initialize.lua after all systems built)
--------------------------------------------------------------------------------
function TN.Init()
    pcall(HookUnitPopupMenu)
end

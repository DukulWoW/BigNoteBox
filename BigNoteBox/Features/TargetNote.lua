-- BigNoteBox Features/TargetNote.lua
-- Creates notes from the current target (NPC, mob, boss, or player).
-- Triggered via keybind (BNB_KeybindTargetNote) or the unit right-click menu.
-- Does nothing if there is no target.
--
-- Player targets are handed to InspectNote (gear, model), so every note made
-- here is an NPC note, keyed by creature ID (from GUID) in note.targetNpcID.
-- Older player notes made here carry "player:<name>-<realm>" in
-- note.targetPlayerKey; the unit menu still finds them.
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
local ICONS  = "Interface\\Icons\\"
local UN     = BNB.UnitNotes   -- shared with InspectNote (Features/UnitNotes.lua)

BNB.TargetNote = BNB.TargetNote or {}
local TN = BNB.TargetNote

--------------------------------------------------------------------------------
-- CONFIG HELPER
--------------------------------------------------------------------------------
local function GetType()
    local db = BigNoteBoxDB
    return db and db.targetNoteType or BNB.DEFAULTS.targetNoteType
end

-- Returns true if a tag config key is enabled (all default to true except Family).
local function TagEnabled(key, default)
    local db = BigNoteBoxDB
    if db == nil then return default end
    local v = db[key]
    if v == nil then return default end
    return v == true
end

local FormatNumber = UN.FormatNumber

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
        if BNB.Oracle and BNB.Oracle.RefreshPortraits then BNB.Oracle.RefreshPortraits() end
    end)
end

-- RET-09 guard (Dukul, 2026-10-31: "hold portraits"). A creature portrait
-- loads the creature's model inside the client, and a portrait drawn while one
-- of our models loads a creature (the Reference Box viewer, the resolver below)
-- crashed Retail: a freed object read at address 0, no Lua running (four
-- times 2026-10-09, twice 2026-10-31 after a dialogue capture made the NPC
-- note). The two never overlap now: a portrait waits while a model loads, a
-- model waits while portraits load, then the waiting side is drawn again.
local PORTRAIT_HOLD = 0.5   -- s a drawn portrait counts as loading
local MODEL_HOLD    = 1.5   -- s a model load counts, unless OnModelLoaded says done
local _portraitUntil, _modelUntil = 0, 0
local _redrawPending = false
local Gate = {}
BNB.ModelGate = Gate
-- Seconds left, or nil when the other side is free
function Gate.PortraitWait()
    local w = _portraitUntil - GetTime()
    return w > 0 and w or nil
end
function Gate.ModelWait()
    local w = _modelUntil - GetTime()
    return w > 0 and w or nil
end
function Gate.ModelLoading() _modelUntil = math.max(_modelUntil, GetTime() + MODEL_HOLD) end
function Gate.ModelLoaded()  _modelUntil = math.min(_modelUntil, GetTime() + 0.1) end
-- Portraits that waited: draw them again once the model is done
local function RedrawPortraitsAfter(delay)
    if _redrawPending then return end
    _redrawPending = true
    C_Timer.After(delay + 0.05, function()
        _redrawPending = false
        RefreshAfterResolve()
    end)
end

-- Display stands (ALL-340, Dukul 2026-10-09): one creature ID with the
-- invisible model of trigger NPCs, each spawn shown as a different mount by
-- the server and named after it (NPC 185669 in Orgrimmar: "Reins of the
-- Bilebound Ur'zul" next to the Hallowed Charger). SetCreature gives the empty
-- model, so such a note is marked targetShared (duplicates are then told apart
-- by name, like combat pets) and its look comes from the mount journal: the
-- longest mount name found in the NPC's name. The mount's display is only ever
-- shown in the Reference Box viewer, never drawn as a portrait (RET-09).
BNB.INVISIBLE_NPC_DISPLAYS = { [11686] = true }

local _mountByName = {}
function BNB.MountDisplayForName(name)
    if not (name and name ~= "" and C_MountJournal and C_MountJournal.GetMountIDs) then return nil end
    if _mountByName[name] ~= nil then return _mountByName[name] or nil end
    local best, bestLen = false, 0
    for _, mountID in ipairs(C_MountJournal.GetMountIDs() or {}) do
        local mName = C_MountJournal.GetMountInfoByID(mountID)
        if mName and #mName > bestLen and name:find(mName, 1, true) then
            local disp = C_MountJournal.GetMountInfoExtraByID(mountID)
            if disp and disp > 0 then best, bestLen = disp, #mName end
        end
    end
    _mountByName[name] = best
    return best or nil
end

local function StoreDisplayID(npcID, displayID)
    local ndb = BNB.NotesDB()
    if not (ndb and ndb.notes) then return end
    local stand = BNB.INVISIBLE_NPC_DISPLAYS[displayID]
    for _, note in pairs(ndb.notes) do
        if note.source == "target" and tostring(note.targetNpcID) == tostring(npcID) and not note.targetIsPet then
            if stand then
                note.targetShared = true
                -- The mount it shows, else the empty display so it is not looked up again
                note.targetDisplayID = BNB.MountDisplayForName(note.title) or note.targetDisplayID or displayID
            else
                note.targetDisplayID = displayID
            end
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
    -- RET-09 guard: not while a portrait loads
    local wait = Gate.PortraitWait()
    if wait then
        table.insert(_queue, 1, npcID)
        C_Timer.After(wait + 0.05, ProcessQueue)
        return
    end
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
    Gate.ModelLoading()
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
            Gate.ModelLoading()   -- still loading
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
-- An icon the player picked wins over the portrait: a target note is made
-- without iconSource, and every pick sets one (Dukul, 2026-10-04: the
-- "Target note: Hogger" icon could not be changed). Revert in the icon
-- picker brings the portrait back.
-- Creature portraits (RET-09, Dukul 2026-10-09). v1.21.1 switched them off
-- after four Retail crashes to desktop (ACCESS_VIOLATION reading address 0 on a
-- torn-down object, no Lua running) while making or opening NPC notes with the
-- Reference Box open; a bisect pointed at a portrait drawn while the viewer
-- loads a creature model. Back on the same day: 33 NPC notes with portraits and
-- the viewer, and direct probes, never crashed again once the experimental
-- display-stand code (ALL-340) and the mount display it saved were gone. Kept:
-- no portrait for a display stand or the empty model of trigger NPCs (display
-- 11686). false = the one-line way back to icons if the crash returns.
local CREATURE_PORTRAITS = true
local EMPTY_DISPLAYS = BNB.INVISIBLE_NPC_DISPLAYS

function BNB.SetNpcNotePortrait(tex, note)
    if not CREATURE_PORTRAITS then return false end
    if not (tex and note and note.source == "target" and note.targetNpcID)
       or note.targetIsPet or note.iconSource then
        return false
    end
    if note.targetShared or EMPTY_DISPLAYS[note.targetDisplayID or 0] then return false end
    local id = note.targetDisplayID
    if id and id > 0 and SetPortraitTextureFromCreatureDisplayID then
        -- RET-09 guard: not while one of our models loads; drawn again after
        local wait = Gate.ModelWait()
        if wait then
            RedrawPortraitsAfter(wait)
            return false
        end
        _portraitUntil = GetTime() + PORTRAIT_HOLD
        return (pcall(SetPortraitTextureFromCreatureDisplayID, tex, id))
    end
    if not id then Enqueue(note.targetNpcID) end
    return false
end

-- The note's unit face on tex, as the note list row draws it: the NPC's saved
-- portrait, then the live one while the note's unit is targeted (a player's
-- face exists only live: a saved ID cannot carry customizations). Toasts and
-- their right-click menu headers use it; a player note's toast showed the
-- plain icon while the list showed the face (Dukul, 2026-10-10)
-- A live unit's portrait on tex (it loads the unit's model in the client too):
-- every SetPortraitTexture of ours goes through here, under the RET-09 guard.
-- Returns true when drawn; false = it waits for a model and is drawn again.
function BNB.SetLivePortrait(tex, unit)
    if not tex then return false end
    local wait = Gate.ModelWait()
    if wait then
        RedrawPortraitsAfter(wait)
        return false
    end
    _portraitUntil = GetTime() + PORTRAIT_HOLD
    return (pcall(SetPortraitTexture, tex, unit or "target"))
end

function BNB.SetNoteUnitPortrait(tex, note)
    if not (tex and note) then return false end
    local drawn = BNB.SetNpcNotePortrait(tex, note)
    if BNB.NoteMatchesTarget and BNB.NoteMatchesTarget(note) then
        drawn = BNB.SetLivePortrait(tex, "target") or drawn
    end
    return drawn
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
-- Oracle search weights the notes about the current target (ALL-69.3).
BNB.CreatureIDFromGUID = GetCreatureID

--------------------------------------------------------------------------------
-- DATA GATHERING
--------------------------------------------------------------------------------
local function GatherTargetData(unit)
    unit = unit or "target"   -- "npc": the NPC in a dialogue (ALL-631)
    local data = {}

    data.isPlayer = UnitIsPlayer(unit)

    -- Name + realm
    local name, realm = BNB.UnitNameRealm(unit)   -- FOR-23: Forever surname
    data.name  = name or UNKNOWN_STR
    data.realm = (realm and realm ~= "") and realm or
                 GetNormalizedRealmName() or ""

    -- GUID and NPC ID
    local guid = UnitGUID(unit)
    data.guid = guid
    data.npcID = not data.isPlayer and GetCreatureID(guid) or nil
    -- Combat pets (hunter pets, warlock demons) share a generic creature ID across
    -- all pet instances. The name and model are per-instance, so we need a different
    -- duplicate detection key and cannot use SetCreature for the model viewer.
    data.isPet = guid and guid:match("^Pet%-") ~= nil or false

    -- Level (-1 means skull/boss)
    local lvl = UnitLevel(unit)
    data.level = (lvl == -1) and "??" or lvl

    -- Display ID: UnitDisplayID does not exist on Midnight retail.
    -- Model viewer uses SetCreature(npcID) instead, which takes the creature ID
    -- from the GUID. No display ID needed.
    data.displayID = nil

    -- Faction: English token for logic (icon, model crest); factionLabel = translated
    local factionEn, factionLoc = UnitFactionGroup(unit)
    data.faction      = factionEn
    data.factionLabel = factionLoc or factionEn

    -- Reaction to player
    local reactionIdx = UnitReaction("player", unit)
    data.reactionIdx   = reactionIdx
    local standing     = reactionIdx and _G["FACTION_STANDING_LABEL" .. reactionIdx]
    data.reactionLabel = type(standing) == "string" and standing
                         or (reactionIdx and REACTION_LABEL[reactionIdx]) or nil
    data.reactionHex   = reactionIdx and REACTION_HEX[reactionIdx] or nil

    -- Zone where encountered
    data.zone    = GetZoneText() or ""
    data.subZone = GetSubZoneText() or ""

    -- Players stop here: StartTargetNoteFlow hands them to InspectNote, and the
    -- unit menu needs only name and realm for FindExistingNote
    if not data.isPlayer then
        -- ── NPC / mob / boss branch ────────────────────────────────────────
        local ctName, ctID  = UnitCreatureType(unit)   -- translated name, type id
        data.creatureType   = ctName
        -- English key, icons only: by id first, then the name mapped back
        data.creatureTypeKey = CREATURE_TYPE_KEY_BY_ID[ctID] or CreatureTypeKey(ctName)
        data.creatureFamily = UnitCreatureFamily(unit)  -- may be nil

        local classification = UnitClassification(unit)
        data.classification      = classification
        local classKey = CLASSIFICATION_KEY[classification or "normal"]
        data.classificationLabel = classKey and L[classKey] or nil
        data.isBoss = (classification == "worldboss") or (data.level == "??")
        -- Mob (can be attacked) or NPC, for the Oracle search badges (ALL-69)
        data.attackable = UnitCanAttack("player", unit) and true or false

        -- Max health — UnitHealthMax returns a "secret" (taint-protected) value
        -- in keybind execution contexts on retail. The comparison must also happen
        -- inside pcall — taint escapes if the secret value is compared outside it.
        pcall(function()
            local maxHP = UnitHealthMax(unit)
            if maxHP and maxHP > 0 then data.maxHealth = maxHP end
        end)

        -- Power — same taint risk; entire read + comparison inside pcall.
        pcall(function()
            local powerIdx, powerToken = UnitPowerType(unit)
            local maxPow = UnitPowerMax(unit)
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

    lines[#lines + 1] = ""
    -- Zone footer, then the /way to the spot (ALL-449)
    UN.AddPlainEncountered(lines, UN.EncounteredPlace(data.name))

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
--   Zone, /way link (ALL-449)
--------------------------------------------------------------------------------
local function BuildRichBody(data)
    local lines = {}

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

    -- Dividers between the sections (Dukul, 2026-10-27): gold ornate under
    -- the header and above Notes, gold plain between Details and Encountered.
    -- Each sits between two empty lines
    local function Divider(file)
        lines[#lines + 1] = BNB.DividerTag(file)
        lines[#lines + 1] = ""
    end
    Divider("gold-ornate")

    -- Details section
    local hasDetails = data.creatureType or data.faction or data.maxHealth or data.maxPower
    local place, way = UN.EncounteredPlace(data.name)
    local hasPlace = place ~= "" or way
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
        if hasPlace then Divider("gold-plain") end
    end

    -- Zone / encounter section: the place, then a /way link to the spot (ALL-449)
    if hasPlace then
        UN.AddRichEncountered(lines, place, way)
        -- It ends on two empty lines: one before the divider, two after
        lines[#lines] = nil
        Divider("gold-ornate")
        lines[#lines + 1] = ""
    elseif hasDetails then
        Divider("gold-ornate")
        lines[#lines + 1] = ""
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
-- Checks note.targetNpcID (for NPCs). Players (unit menu only): an older
-- target note's targetPlayerKey, then the inspect-note lookup InspectNote uses.
-- Never checks title — title can be renamed freely.
--------------------------------------------------------------------------------
-- The creature ID is a string from the GUID, but a note that went through a
-- Markdown import or an older build can hold a number (ALL-417)
local function SameNpc(a, b)
    return a ~= nil and b ~= nil and tostring(a) == tostring(b)
end

local function FindExistingNote(data)
    local ndb = BNB.NotesDB()
    if not ndb or not ndb.notes then return nil end

    if data.isPlayer then
        local key = "player:" .. data.name
        if data.realm and data.realm ~= "" then
            key = key .. "-" .. data.realm
        end
        for id, note in pairs(ndb.notes) do
            if note.targetPlayerKey == key then return id end
        end
        return UN.FindPlayerNote(data.name, data.realm)
    elseif data.isPet then
        -- Combat pets share a generic creature ID — match on name + npcID
        for id, note in pairs(ndb.notes) do
            if SameNpc(note.targetNpcID, data.npcID) and note.title == data.name then return id end
        end
    else
        if data.npcID then
            -- A display stand's ID is shared by every stand: match the name
            -- too (a renamed stand note is not found, as for combat pets).
            -- A note made before ALL-340 knows it only by its saved empty display
            local shared = false
            for _, note in pairs(ndb.notes) do
                if SameNpc(note.targetNpcID, data.npcID) and (note.targetShared
                   or BNB.INVISIBLE_NPC_DISPLAYS[note.targetDisplayID or 0]) then
                    shared = true; break
                end
            end
            for id, note in pairs(ndb.notes) do
                if SameNpc(note.targetNpcID, data.npcID) and (not shared or note.title == data.name) then return id end
            end
        end
    end
    return nil
end

--------------------------------------------------------------------------------
-- CREATE THE NOTE
--------------------------------------------------------------------------------
-- One note per press (ALL-417): the same unit asked for twice within a moment
-- (a repeated click or key event) is one note, not a second "(Duplicate)".
local _lastCreate = { guid = nil, at = 0 }

-- quiet: do not select the new note (a dialogue capture, ALL-631)
local function CreateTargetNote(richMode, data, quiet)
    local now = GetTime()
    if data.guid and _lastCreate.guid == data.guid and now - _lastCreate.at < 2 then return end
    _lastCreate.guid, _lastCreate.at = data.guid, now

    local title = UN.UniqueTitle(data.name)
    local body  = richMode and BuildRichBody(data) or BuildNormalBody(data)

    local noteID = BNB.CreateNote(title, body)
    if not noteID then return end

    -- Tags — "Target Note" is always added. All others are user-configurable.
    local tags = { L["TGT_TAG_TARGET"] }
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

    local fields = {
        source   = "target",
        richMode = richMode or false,
        icon     = data.noteIcon,
        tags     = tags,
    }
    -- The NPC situation, always (ALL-435): on or off by the setting
    if data.name and data.name ~= "" then
        UN.AddUnitSituation(fields, "npc:" .. data.name, "targetNoteAddSituation", "targetNoteSituationToast")
    end

    -- Faction token ("Horde"/"Alliance"; nil for neutral) for the model
    -- viewer's crest (FOR-22), independent of the faction tag setting
    fields.targetFaction = data.faction
    -- Kind of NPC for the Oracle search badges (ALL-69): English tokens
    -- ("elite", "rareelite", "worldboss", "normal"...) and attackable = mob.
    -- Notes made before these existed have neither and show as an NPC.
    fields.targetClassification = data.classification
    fields.targetAttackable     = data.attackable
    -- Round, a dragon on an elite / rare (ALL-591); a player target keeps
    -- InspectNote's frame (player targets go there)
    if not data.isPlayer then fields.iconFrame = UN.NpcIconFrame(data.classification) end

    -- Hidden duplicate-detection keys
    fields.targetNpcID = data.npcID  -- may be nil for vehicles/objects without creature ID
    if data.isPet then
        fields.targetIsPet = true  -- combat pet: SetCreature shows wrong model
    end
    -- Another stand of a known display-stand ID: mark it and take its mount now
    if data.npcID and not data.isPet then
        for _, note in pairs(BNB.NotesDB().notes or {}) do
            if SameNpc(note.targetNpcID, data.npcID) and (note.targetShared
               or BNB.INVISIBLE_NPC_DISPLAYS[note.targetDisplayID or 0]) then
                fields.targetShared    = true
                fields.targetDisplayID = BNB.MountDisplayForName(data.name)
                break
            end
        end
    end

    BNB.UpdateNote(noteID, fields)

    -- Select the note so SyncReferenceBox fires with the fully populated note
    -- (targetNpcID must be set before SelectNote, which is why we call it
    -- after UpdateNote rather than after CreateNote).
    if BNB.SelectNote and not quiet then
        if BNB.SaveCurrentNote then BNB.SaveCurrentNote() end
        BNB.SelectNote(noteID)
    end

    return noteID
end

--------------------------------------------------------------------------------
-- DIALOGS: Normal/Rich and "note exists" (Features/UnitNotes.lua)
--------------------------------------------------------------------------------
local _typeDialog = nil
local _warnDialog = nil
local TYPE_DIALOG_GLOW_KEY = "bnb_target_typedlg"

local function ShowTypeDialog(data)
    if not _typeDialog then
        _typeDialog = UN.TypeDialog("BNBTargetNoteTypeDialog", L["TGT_CREATE_TITLE"], TYPE_DIALOG_GLOW_KEY)
    end
    -- data is the snapshot taken when the flow started
    _typeDialog:Open(function(richMode) CreateTargetNote(richMode, data) end)
end

-- Player & NPC Notes switched off (ALL-343, Features/UnitNotes.lua)
UN._closers[#UN._closers + 1] = function()
    if _typeDialog then _typeDialog:Hide() end
    if _warnDialog then _warnDialog:Hide() end
end

local function ShowWarningDialog(existingNoteID, targetName, onDuplicate)
    if not _warnDialog then
        _warnDialog = UN.WarnDialog("BNBTargetNoteWarnDialog", 320, 130, 14, 110)
    end
    _warnDialog:Open(targetName, existingNoteID, onDuplicate)
end

--------------------------------------------------------------------------------
-- MASTER FLOW
-- Called from both keybind and right-click menu.
-- data is optional — if nil, GatherTargetData() is called internally.
--------------------------------------------------------------------------------
local function StartTargetNoteFlow(data)
    if not UnitExists("target") or not BNB.UnitNotesEnabled() then return end   -- ALL-343
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
    if not BNB.RichEnabled() then richMode = false end   -- Rich Notes off: no type choice (ALL-343)

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

-- The note of the NPC the player talks to ("npc" unit): found by creature id,
-- or made as F6 would, without its dialogs (Rich unless the setting says
-- Normal). Unsaved editor changes to it are saved first (as NoteLinks does).
-- Returns id, note, or nil (Player & NPC Notes off, no NPC, no creature id,
-- a pet). made = true when the note was made here. Shared by dialogue
-- capture and the vendor list (ALL-644).
function TN.NpcNoteForTalk()
    if not BNB.UnitNotesEnabled() or not UnitExists("npc") or UnitIsPlayer("npc") then return nil end
    local data = GatherTargetData("npc")
    if data.isPet or not data.npcID then return nil end

    local id, made = FindExistingNote(data), false
    if not id then
        local rich = BNB.RichEnabled() and GetType() ~= "always_normal"
        id = CreateTargetNote(rich, data, true)
        if not id then return nil end
        made = true
    end
    local note = BNB.GetNote(id)
    if not note then return nil end
    if BNB._currentNoteID == id and BNB._dirty and BNB.SaveCurrentNoteQuiet then
        BNB.SaveCurrentNoteQuiet()
        note = BNB.GetNote(id)
    end
    return id, note, made
end

-- A captured section (dialogue, a vendor list) into a rich NPC note, above
-- the player's own Notes part, which stays last (Dukul, 2026-11-01: "User
-- notes should probably always be at the end of the note"): before the
-- divider over the Notes heading, after a gold-plain divider of its own. No
-- Notes heading (renamed, removed): at the bottom. Plain NPC notes have no
-- Notes heading; their callers keep adding at the bottom.
function TN.AddAboveNotes(body, section)
    body = ((body or ""):gsub("\r", ""))
    local lines = {}
    for line in (body .. "\n"):gmatch("(.-)\n") do lines[#lines + 1] = line end
    local notesHdr = "{h3}" .. L["TGT_HDR_NOTES"] .. "{/h3}"
    local at
    for i, line in ipairs(lines) do
        if line:gsub("%s+$", "") == notesHdr then at = i; break end
    end
    local div = BNB.DividerTag("gold-plain")
    if not at then
        body = body:gsub("%s+$", "")
        return (body ~= "" and (body .. "\n\n" .. div .. "\n\n") or "") .. section
    end
    local j = at - 1
    while j > 0 and lines[j]:match("^%s*$") do j = j - 1 end
    if j > 0 and lines[j]:find("^{div:") then at = j end
    local before = table.concat(lines, "\n", 1, at - 1):gsub("%s+$", "")
    local after  = table.concat(lines, "\n", at, #lines)
    return (before ~= "" and (before .. "\n\n") or "") .. div .. "\n\n" .. section .. "\n\n" .. after
end

-- What an NPC says, into that NPC's own note (ALL-631, Dukul 2026-10-31):
-- the note F6 makes and finds (by creature ID), with the text at the bottom
-- under a dated header. No note yet: one is made first, as F6 would, without
-- its dialogs (Rich unless the setting says Normal). Returns the note id and
-- title, or nil when it is no case for an NPC note (Player & NPC Notes off,
-- no NPC, no creature ID, a pet): the caller then makes a note of its own.
-- open: show the note in the main window after (Note Capture set to "open");
-- otherwise nothing is opened while the player talks (fewer model loads, RET-09).
function TN.AddDialogue(text, open)
    if type(text) ~= "string" or text:match("^%s*$") then return nil end
    local id, note = TN.NpcNoteForTalk()
    if not id then return nil end

    local hdr  = string.format(L["QN_DIALOGUE_HDR_FMT"], BNB.FmtDate())
    local body = ((note.body or ""):gsub("%s+$", ""))
    text = (text:gsub("^%s+", ""):gsub("%s+$", ""))
    if note.richMode then
        body = TN.AddAboveNotes(body, "{h3}" .. hdr .. "{/h3}\n\n" .. text)
    else
        body = body .. "\n\n----- " .. hdr .. " -----\n" .. text
    end
    BNB.UpdateNote(id, { body = body })
    UN.RefreshNoteViews(id)
    if open then
        if BNB.mainFrame and not BNB.mainFrame:IsShown() then BNB.mainFrame:Show() end
        if BNB._currentNoteID ~= id and BNB.SelectNote then
            if BNB.SaveCurrentNote then BNB.SaveCurrentNote() end
            BNB.SelectNote(id)
        end
    end
    return id, note.title
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
    "ENEMY_PLAYER", -- a player of the other faction: hostile players get their own menu
    "TARGET",       -- right-click an NPC/mob/boss target portrait
    "ENEMY",        -- hostile unit menu (OneWoW hooks it for NPCs next to TARGET)
    "SELF",         -- right-click own portrait
    "FOCUS",        -- right-click focus frame
    "BOSS",         -- right-click boss frame
    "PARTY",        -- right-click party member frame
    "RAID",         -- right-click raid member frame
    "RAID_PLAYER",  -- alternate raid player tag
}

local function OnUnitMenuOpen(owner, rootDescription, contextData)
    if not BNB.UnitNotesEnabled() then return end   -- Player & NPC Notes off (ALL-343)
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
            UN.OpenNote(existingID)
        end)
        -- The same note as a sticky (ALL-204, Dukul 2026-10-02)
        if BNB.Sticky and BNB.Sticky.OpenWorld and BNB.StickiesEnabled() then   -- ALL-343
            rootDescription:CreateButton(L["TGT_MENU_OPEN_STICKY"], function()
                BNB.Sticky.OpenWorld(existingID)
            end)
        end
    end
    -- Offered even when a note exists: the flow then shows the "note exists"
    -- window, whose Create Duplicate is the menu's only way to a second note
    rootDescription:CreateButton(L["TGT_MENU_CREATE"], function()
        StartTargetNoteFlow(data)
    end)
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

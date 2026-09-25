-- BigNoteBox Features/InspectNote.lua
-- Adds a "Create BNB Note" button to the InspectFrame.
-- Supports automatic or manual creation, with Normal/Rich note type selection.
-- Creates a fully populated note from the inspected player's data:
-- name, title, level, class, spec, guild, achievement points, PvP stats.
-- Populates RefBox with all equipped gear.
--
-- Config keys (BigNoteBoxDB):
--   inspectNoteMode:  "manual" (default) | "auto_rich" | "auto_normal"
--   inspectNoteType:  "choose" (default) | "always_rich" | "always_normal"
--------------------------------------------------------------------------------

local BNB    = BigNoteBox
local L      = BNB.L
local ASSETS = "Interface\\AddOns\\BigNoteBox\\Assets\\"
local BTNS   = ASSETS .. "Buttons\\"

-- ── Button placement (adjust these to fine-tune position) ─────────────────────
local INS_X  = -24   -- pixels from TOPRIGHT of InspectFrame
local INS_Y  = 0     -- pixels down from TOPRIGHT of InspectFrame
-- Forever's InspectFrame border sits elsewhere: 1px left, 2px up (Dukul, 2026-09-24)
if BNB.IsForever then INS_X, INS_Y = INS_X - 1, INS_Y + 2 end
local INS_SZ = 24    -- button size

-- ── Race icon mapping: raceFile -> asset filename (without .tga) ──────────────
-- Uses BNB's bundled race icons in Assets\Icons\Races\
local RACE_ICONS = "Interface\\AddOns\\BigNoteBox\\Assets\\Icons\\Races\\"
local RACE_ICON_MAP = {
    Human                = "Achievement_Character_Human",
    Orc                  = "Achievement_Character_Orc",
    Dwarf                = "Achievement_Character_Dwarf",
    NightElf             = "Achievement_Character_Nightelf",
    Scourge              = "Achievement_Character_Undead",   -- raceFile="Scourge" for Undead
    Tauren               = "Achievement_Character_Tauren",
    Gnome                = "Achievement_Character_Gnome",
    Troll                = "Achievement_Character_Troll",
    BloodElf             = "Achievement_Character_Bloodelf",
    Draenei              = "Achievement_Character_Draenei",
    -- Cataclysm
    Worgen               = "race_worgen",
    Goblin               = "race_goblin",
    -- Mists
    Pandaren             = "race_pandaren",
    -- Allied races (race_ prefix)
    Nightborne           = "race_nightborne",
    HighmountainTauren   = "race_highmountaintauren",
    VoidElf              = "race_voidelf",
    LightforgedDraenei   = "race_lightforgeddraenei",
    DarkIronDwarf        = "race_darkirondwarf",
    MagharOrc            = "race_magharorc",
    ZandalariTroll       = "race_zandalaritroll",
    KulTiran             = "race_kultiran",
    Mechagnome           = "race_mechagnome",
    Vulpera              = "race_vulpera",
    -- Dragonflight+
    Dracthyr             = "race_dracthyr",
    -- Midnight
    EarthenDwarf         = "race_earthendwarf",
    Harronir             = "race_harronir",
}

-- Goblin uses a different naming convention for male/female
local RACE_ICON_OVERRIDE = {
    Goblin = { Male = "achievement_Goblinhead", Female = "achievement_FemaleGoblinhead" },
}

local function GetRaceIconPath(raceFile, gender)
    -- Check for full override (Goblin has non-standard filenames)
    local ovr = RACE_ICON_OVERRIDE[raceFile]
    if ovr and ovr[gender] then
        return RACE_ICONS .. ovr[gender]
    end
    local base = RACE_ICON_MAP[raceFile]
    if not base then base = RACE_ICON_MAP.Human end
    -- race_ assets use lowercase suffix (race_pandaren_male);
    -- Achievement_Character_ assets use title-case (Achievement_Character_Human_Male).
    local suffix = base:sub(1, 5) == "race_" and gender:lower() or gender
    return RACE_ICONS .. base .. "_" .. suffix
end

-- Race icon for a saved inspect note (the Reference box's Model tab). Notes
-- keep only inspectRaceID / inspectSexID (0 male, 1 female), so the race file
-- name comes from the client. nil when the id is unknown; the caller falls back.
function BNB.GetInspectRaceIcon(raceID, sexID)
    if not raceID or not (C_CreatureInfo and C_CreatureInfo.GetRaceInfo) then return nil end
    local info = C_CreatureInfo.GetRaceInfo(raceID)
    local raceFile = info and info.clientFileString
    if not raceFile then return nil end
    return GetRaceIconPath(raceFile, sexID == 1 and "Female" or "Male")
end
-- Slot names come from Blizzard's own translated globals (ALL-72); the English
-- word is only a fallback if a global is ever missing. num tells the two rings
-- and the two trinkets apart.
local SLOT_INFO = {
    { id =  1, g = "HEADSLOT",          en = "Head" },
    { id =  2, g = "NECKSLOT",          en = "Neck" },
    { id =  3, g = "SHOULDERSLOT",      en = "Shoulder" },
    { id =  4, g = "SHIRTSLOT",         en = "Shirt" },
    { id =  5, g = "CHESTSLOT",         en = "Chest" },
    { id =  6, g = "WAISTSLOT",         en = "Waist" },
    { id =  7, g = "LEGSSLOT",          en = "Legs" },
    { id =  8, g = "FEETSLOT",          en = "Feet" },
    { id =  9, g = "WRISTSLOT",         en = "Wrist" },
    { id = 10, g = "HANDSSLOT",         en = "Hands" },
    { id = 11, g = "FINGER0SLOT",       en = "Ring", num = 1 },
    { id = 12, g = "FINGER1SLOT",       en = "Ring", num = 2 },
    { id = 13, g = "TRINKET0SLOT",      en = "Trinket", num = 1 },
    { id = 14, g = "TRINKET1SLOT",      en = "Trinket", num = 2 },
    { id = 15, g = "BACKSLOT",          en = "Back" },
    { id = 16, g = "MAINHANDSLOT",      en = "Main Hand" },
    { id = 17, g = "SECONDARYHANDSLOT", en = "Off Hand" },
    { id = 19, g = "TABARDSLOT",        en = "Tabard" },
}
for _, s in ipairs(SLOT_INFO) do
    local g = _G[s.g]
    s.label = (type(g) == "string" and g ~= "" and g or s.en) .. (s.num and (" " .. s.num) or "")
end

-- Translated slot name for an inventory slot id. The RefBox gear cards call this
-- at draw time, so notes saved with English slot names show the client's language.
function BNB.InspectSlotLabel(slotIdx)
    for _, s in ipairs(SLOT_INFO) do
        if s.id == slotIdx then return s.label end
    end
end

local UNKNOWN_STR = type(UNKNOWN) == "string" and UNKNOWN or "Unknown"

-- WoW item quality hex colours
local QUALITY_HEX = {
    [0] = "9d9d9d",  -- Poor
    [1] = "ffffff",  -- Common
    [2] = "1eff00",  -- Uncommon
    [3] = "0070dd",  -- Rare
    [4] = "a335ee",  -- Epic
    [5] = "ff8000",  -- Legendary
    [6] = "e6cc80",  -- Artifact
    [7] = "00ccff",  -- Heirloom
    [8] = "00ccff",  -- WoW Token
}

-- ── State ─────────────────────────────────────────────────────────────────────
local _inspectBtn
local _typeDialog
local _warnDialog
local TYPE_DIALOG_GLOW_KEY = "bnb_inspect_typedlg"
local _inspectReady = false
local _autoCreatedThisInspect = false

-- ── Config helpers ────────────────────────────────────────────────────────────
local function GetMode()
    local db = BigNoteBoxDB
    return db and db.inspectNoteMode or "manual"
end

local function GetType()
    local db = BigNoteBoxDB
    return db and db.inspectNoteType or "choose"
end

--------------------------------------------------------------------------------
-- DATA GATHERING
--------------------------------------------------------------------------------
local function GatherInspectData()
    local data = {}

    local name, realm = BNB.UnitNameRealm("target")   -- FOR-23: Forever surname
    data.name  = name or UNKNOWN_STR
    data.realm = realm and realm ~= "" and realm or GetNormalizedRealmName() or ""

    local pvpName = UnitPVPName("target")
    if pvpName and pvpName ~= data.name then
        data.displayTitle = pvpName
    end

    data.level = UnitLevel("target")
    if data.level == -1 then data.level = "??" end
    local className, classFile = UnitClass("target")
    data.className = className or UNKNOWN_STR
    data.classFile = classFile or "WARRIOR"
    local raceName, raceFile, raceID = UnitRace("target")
    data.race     = raceName or UNKNOWN_STR
    data.raceFile = raceFile or "Human"

    -- UnitRace may not return raceID as 3rd value on all retail builds.
    -- Use a lookup table as fallback to guarantee a valid numeric ID.
    local RACE_FILE_TO_ID = {
        Human            = 1,
        Orc              = 2,
        Dwarf            = 3,
        NightElf         = 4,
        Scourge          = 5,
        Tauren           = 6,
        Gnome            = 7,
        Troll            = 8,
        Goblin           = 9,
        BloodElf         = 10,
        Draenei          = 11,
        Worgen           = 22,
        Pandaren         = 24,
        Nightborne       = 27,
        HighmountainTauren = 28,
        VoidElf          = 29,
        LightforgedDraenei = 30,
        ZandalariTroll   = 31,
        KulTiran         = 32,
        DarkIronDwarf    = 34,
        Vulpera          = 35,
        MagharOrc        = 36,
        Mechagnome       = 37,
        Dracthyr         = 52,
        EarthenDwarf     = 85,
        Harronir         = 86,
    }
    data.raceID = raceID or RACE_FILE_TO_ID[data.raceFile] or 1

    local sex = UnitSex("target")
    data.gender = (sex == 3) and "Female" or "Male"
    data.sexID  = (sex == 3) and 1 or 0   -- 0 = male, 1 = female for SetCustomRace

    data.raceIcon = GetRaceIconPath(data.raceFile, data.gender)

    local cc = RAID_CLASS_COLORS and RAID_CLASS_COLORS[data.classFile]
    if cc then
        data.classHex = string.format("%02x%02x%02x",
            math.floor(cc.r * 255 + 0.5),
            math.floor(cc.g * 255 + 0.5),
            math.floor(cc.b * 255 + 0.5))
    else
        data.classHex = "ffffff"
    end

    data.spec = nil
    if GetInspectSpecialization then
        local specID = GetInspectSpecialization("target")
        if specID and specID > 0 then
            local _, specName = GetSpecializationInfoByID(specID)
            -- A player without a chosen spec gets a starter spec named after the
            -- class: skip it, or the note reads "Rogue Rogue" (ALL-72)
            if specName and specName ~= "" and specName ~= data.className then
                data.spec = specName
            end
        end
    end

    local guildName, guildRankName = GetGuildInfo("target")
    data.guild     = guildName
    data.guildRank = guildRankName

    -- faction = English token for logic (model crest); factionLabel = translated, for text and tag
    local factionEn, factionLoc = UnitFactionGroup("target")
    data.faction      = factionEn
    data.factionLabel = factionLoc or factionEn

    data.achievePoints = nil
    if GetComparisonAchievementPoints then
        local pts = GetComparisonAchievementPoints()
        if pts and pts > 0 then data.achievePoints = pts end
    end

    data.honorKills = nil
    if GetInspectHonorData then
        pcall(function()
            local kills = GetInspectHonorData()
            if kills and kills > 0 then data.honorKills = kills end
        end)
    end

    data.ilvl = nil
    if C_PaperDollInfo and C_PaperDollInfo.GetInspectItemLevel then
        local ilvl = C_PaperDollInfo.GetInspectItemLevel("target")
        if ilvl and ilvl > 0 then
            data.ilvl = math.floor(ilvl + 0.5)
        end
    end

    -- Gear: equipped items per slot. Used for note body text, RefBox gear cards,
    -- and model viewer fallback (old notes).
    data.gear = {}
    -- gearItems: structured list stored on the note for RefBox gear card rendering.
    -- Kept separately from note.attachments so they don't count toward the max.
    data.gearItems = {}
    for _, slot in ipairs(SLOT_INFO) do
        local itemID = GetInventoryItemID("target", slot.id)
        if itemID then
            local itemName, _, quality, ilvl, _, _, _, _, _, iconTex = C_Item.GetItemInfo(itemID)
            local link = GetInventoryItemLink("target", slot.id)
            local actualIlvl = ilvl
            if link and C_Item.GetDetailedItemLevelInfo then
                local effIlvl = C_Item.GetDetailedItemLevelInfo(link)
                if effIlvl and effIlvl > 0 then actualIlvl = effIlvl end
            end
            local entry = {
                slot    = slot.label,
                slotIdx = slot.id,
                id      = itemID,
                name    = itemName or string.format(L["INSPECT_ITEM_FMT"], tostring(itemID)),
                quality = quality or 1,
                ilvl    = actualIlvl,
                icon    = iconTex,
            }
            data.gear[#data.gear + 1] = entry
            data.gearItems[#data.gearItems + 1] = { id = itemID, slot = slot.label, slotIdx = slot.id }
        end
    end

    -- Transmog appearance IDs — two purposes:
    --   inspectTransmogAppearances: {[slotIdx]=appearanceID} used by model viewer TryOn().
    --   transmogItems: resolved item records stored as RefBox transmog gear cards.
    data.transmogAppearances = {}
    data.transmogItems = {}
    if C_TransmogCollection and C_TransmogCollection.GetInspectItemTransmogInfoList then
        pcall(function()
            local tmogList = C_TransmogCollection.GetInspectItemTransmogInfoList()
            if tmogList then
                for slotIdx, info in ipairs(tmogList) do
                    if info.appearanceID and info.appearanceID > 0 then
                        data.transmogAppearances[slotIdx] = info.appearanceID
                        -- Resolve appearanceID to an itemID for card display.
                        local src = C_TransmogCollection.GetSourceInfo(info.appearanceID)
                        if src and src.itemID then
                            -- Find the slot label from SLOT_INFO (slotIdx is 1-based list index).
                            local slotLabel = ""
                            for _, s in ipairs(SLOT_INFO) do
                                if s.id == slotIdx then slotLabel = s.label; break end
                            end
                            data.transmogItems[#data.transmogItems + 1] = {
                                id           = src.itemID,
                                slot         = slotLabel,
                                slotIdx      = slotIdx,
                                appearanceID = info.appearanceID,
                            }
                        end
                    end
                end
            end
        end)
    end

    return data
end

--------------------------------------------------------------------------------
-- NOTE BODY BUILDERS
--------------------------------------------------------------------------------

local function FormatNumber(n)
    if not n then return "?" end
    -- The client's own thousands separator (ALL-72)
    if BreakUpLargeNumbers then return BreakUpLargeNumbers(n) end
    local s = tostring(n)
    local pos, result = #s, ""
    while pos > 0 do
        local start = math.max(1, pos - 2)
        result = s:sub(start, pos) .. (result ~= "" and "," or "") .. result
        pos = start - 1
    end
    return result
end

-- "Level 80 Dracthyr Preservation Evoker": spec is optional (ALL-72)
local function LevelLine(data)
    local classStr = data.spec and (data.spec .. " " .. data.className) or data.className
    return string.format(L["TGT_LEVEL_FMT"], tostring(data.level), data.race, classStr)
end

-- Guild line with or without the rank: key .. "_RANK" is the variant with the rank
local function GuildLine(data, key)
    if data.guildRank then
        return string.format(L[key .. "_RANK"], data.guild, data.guildRank)
    end
    return string.format(L[key], data.guild)
end

local function BuildNormalBody(data)
    local lines = {}

    -- Name (with title if set)
    lines[#lines + 1] = data.displayTitle or data.name
    lines[#lines + 1] = ""

    lines[#lines + 1] = LevelLine(data)

    if data.factionLabel then
        lines[#lines + 1] = string.format(L["TGT_LINE_FACTION"], data.factionLabel)
    end

    if data.guild then
        lines[#lines + 1] = GuildLine(data, "INSPECT_LINE_GUILD")
    end

    lines[#lines + 1] = ""

    if data.ilvl then
        lines[#lines + 1] = string.format(L["INSPECT_LINE_ILVL"], tostring(data.ilvl))
    end
    if data.achievePoints then
        lines[#lines + 1] = string.format(L["INSPECT_LINE_ACHIEVE"], FormatNumber(data.achievePoints))
    end
    if data.honorKills then
        lines[#lines + 1] = string.format(L["INSPECT_LINE_HK"], FormatNumber(data.honorKills))
    end

    lines[#lines + 1] = ""

    if #data.gear > 0 then
        lines[#lines + 1] = string.format(L["TGT_HDR_COLON_FMT"], L["INSPECT_HDR_EQUIPMENT"])
        for _, g in ipairs(data.gear) do
            local ilvlStr = g.ilvl and (" (" .. tostring(g.ilvl) .. ")") or ""
            lines[#lines + 1] = "  " .. string.format(L["TGT_LINE_STAT_FMT"], g.slot, g.name .. ilvlStr)
        end
    end

    lines[#lines + 1] = ""
    lines[#lines + 1] = string.format(L["TGT_HDR_COLON_FMT"], L["TGT_HDR_NOTES"])
    lines[#lines + 1] = ""

    return table.concat(lines, "\n")
end

local function BuildRichBody(data)
    local lines = {}

    -- Name with title as H1
    local displayName = data.displayTitle or data.name
    lines[#lines + 1] = "{h1:c}" .. displayName .. "{/h1}"
    lines[#lines + 1] = ""

    -- Class-coloured subtitle
    lines[#lines + 1] = "{p:c}{col:" .. data.classHex .. "}" .. LevelLine(data) .. "{/col}{/p}"

    if data.factionLabel then
        lines[#lines + 1] = "{p:c}" .. data.factionLabel .. "{/p}"
    end

    lines[#lines + 1] = ""
    lines[#lines + 1] = ""

    -- Guild
    if data.guild then
        lines[#lines + 1] = "{p}" .. GuildLine(data, "INSPECT_LINE_GUILD_MEMBER") .. "{/p}"
        lines[#lines + 1] = ""
        lines[#lines + 1] = ""
    end

    -- Stats
    local hasStats = data.ilvl or data.achievePoints or data.honorKills
    if hasStats then
        lines[#lines + 1] = "{h3}" .. L["INSPECT_HDR_STATS"] .. "{/h3}"
        lines[#lines + 1] = ""
        if data.ilvl then
            lines[#lines + 1] = "{p}" .. string.format(L["INSPECT_LINE_ILVL"], tostring(data.ilvl)) .. "{/p}"
        end
        if data.achievePoints then
            lines[#lines + 1] = "{p}" .. string.format(L["INSPECT_LINE_ACHIEVE"], FormatNumber(data.achievePoints)) .. "{/p}"
        end
        if data.honorKills then
            lines[#lines + 1] = "{p}" .. string.format(L["INSPECT_LINE_HK"], FormatNumber(data.honorKills)) .. "{/p}"
        end
        lines[#lines + 1] = ""
        lines[#lines + 1] = ""
    end

    -- Gear with icons and quality colours
    if #data.gear > 0 then
        lines[#lines + 1] = "{h3}" .. L["INSPECT_HDR_EQUIPMENT"] .. "{/h3}"
        lines[#lines + 1] = ""
        for _, g in ipairs(data.gear) do
            local qHex = QUALITY_HEX[g.quality] or QUALITY_HEX[1]
            local ilvlStr = g.ilvl and (" (" .. tostring(g.ilvl) .. ")") or ""
            local iconStr = ""
            if g.icon then
                iconStr = "{icon:" .. tostring(g.icon) .. ":18} "
            end
            lines[#lines + 1] = "{p}" .. iconStr .. string.format(L["TGT_LINE_STAT_FMT"], g.slot,
                "{col:" .. qHex .. "}" .. g.name .. ilvlStr .. "{/col}") .. "{/p}"
        end
    end

    lines[#lines + 1] = ""
    lines[#lines + 1] = ""
    lines[#lines + 1] = "{h3}" .. L["TGT_HDR_NOTES"] .. "{/h3}"
    lines[#lines + 1] = "{p}{/p}"

    return table.concat(lines, "\n")
end

--------------------------------------------------------------------------------
-- DUPLICATE HANDLING
--------------------------------------------------------------------------------
local function MakeUniqueTitle(baseName)
    local ndb = BigNoteBoxNotesDB
    if not ndb or not ndb.notes then return baseName end
    local exists = false
    for _, note in pairs(ndb.notes) do
        if note.title == baseName then exists = true; break end
    end
    if not exists then return baseName end

    for i = 1, 100 do
        local candidate
        if i == 1 then
            candidate = string.format(L["INSPECT_DUP_FMT"], baseName)
        else
            candidate = string.format(L["INSPECT_DUP_N_FMT"], baseName, tostring(i))
        end
        local found = false
        for _, note in pairs(ndb.notes) do
            if note.title == candidate then found = true; break end
        end
        if not found then return candidate end
    end
    return string.format(L["INSPECT_DUP_N_FMT"], baseName, tostring(time()))
end

-- Find an existing note for this player. Returns noteID or nil.
-- Matches the player context, or an inspect note's inspectName/inspectRealm
-- (the same test as NoteList and ReferenceBox). The context is only saved when
-- inspectNoteAddSituation is on (default off), so on its own it missed every
-- note made with default settings: no warning, and auto mode made a new
-- "(Duplicate)" note on every inspect.
local function FindExistingNote(playerName, realm)
    local ndb = BigNoteBoxNotesDB
    if not ndb or not ndb.notes then return nil end
    local ctx = "player:" .. playerName
    if realm and realm ~= "" then ctx = ctx .. "-" .. realm end
    for id, note in pairs(ndb.notes) do
        if note.context == ctx then return id end
        if note.source == "inspect" and note.inspectName == playerName
           and (not note.inspectRealm or note.inspectRealm == "" or note.inspectRealm == realm) then
            return id
        end
    end
    return nil
end

--------------------------------------------------------------------------------
-- CREATE THE NOTE
--------------------------------------------------------------------------------
local function CreateInspectNote(richMode, silent)
    local data = GatherInspectData()
    -- Title: character name only (no title)
    local title = MakeUniqueTitle(data.name)
    local body  = richMode and BuildRichBody(data) or BuildNormalBody(data)

    local noteID = BNB.CreateNote(title, body)
    if not noteID then return end

    local context = nil
    if BigNoteBoxDB and BigNoteBoxDB.inspectNoteAddSituation then
        context = "player:" .. data.name
        if data.realm and data.realm ~= "" then
            context = context .. "-" .. data.realm
        end
    end

    local tags = { L["INSPECT_TAG"] }
    if data.race and data.race ~= UNKNOWN_STR then tags[#tags + 1] = data.race end
    if data.className and data.className ~= UNKNOWN_STR then tags[#tags + 1] = data.className end
    if data.spec then tags[#tags + 1] = data.spec end
    if data.factionLabel then tags[#tags + 1] = data.factionLabel end

    local fields = {
        source         = "inspect",
        richMode       = richMode or false,
        icon           = data.raceIcon,
        tags           = tags,
        inspectRaceID  = data.raceID,
        inspectSexID   = data.sexID,
        inspectName    = data.name,
        inspectRealm   = data.realm,
        inspectFaction = data.faction,   -- model viewer crest (FOR-22)
    }
    -- Transmog appearance IDs for reconstructed model viewer (indexed by slot)
    if data.transmogAppearances and next(data.transmogAppearances) then
        fields.inspectTransmogAppearances = data.transmogAppearances
    end
    -- Gear card lists: stored separately from note.attachments so they do not
    -- count toward the RefBox max. RefBox renders them in dedicated sections.
    if #data.gearItems > 0 then
        fields.inspectGearItems = data.gearItems
    end
    if #data.transmogItems > 0 then
        fields.inspectTransmogItems = data.transmogItems
    end
    if context then
        fields.context = context
    end

    local cc = RAID_CLASS_COLORS and RAID_CLASS_COLORS[data.classFile]
    if cc then
        fields.titleColor = { r = cc.r, g = cc.g, b = cc.b }
    end

    BNB.UpdateNote(noteID, fields)
    BNB:Print(string.format(BNB.L["QN_NOTE_CREATED"], title))

    if not silent then
        if BNB.OpenMainWindow then BNB.OpenMainWindow() end
        if BNB.SelectNote then
            BNB.SaveCurrentNote()
            BNB.SelectNote(noteID)
        end
        if BNB.RefreshNoteList then BNB.RefreshNoteList() end
    end

    if _typeDialog then _typeDialog:Hide() end
    if _warnDialog then _warnDialog:Hide() end
end

-- Open an existing note in BNB
local function OpenExistingNote(noteID)
    if BNB.OpenMainWindow then BNB.OpenMainWindow() end
    if BNB.SelectNote then
        BNB.SaveCurrentNote()
        BNB.SelectNote(noteID)
    end
    if _warnDialog then _warnDialog:Hide() end
    if _typeDialog then _typeDialog:Hide() end
end

--------------------------------------------------------------------------------
-- UPDATE GEAR: replace gear/transmog card lists on an existing inspect note
-- without touching the note body, tags, or attachments.
-- richMode is used only by UpdateGearAndNote (passed nil for gear-only update).
--------------------------------------------------------------------------------
local function UpdateInspectGear(noteID, richMode)
    local data = GatherInspectData()
    local fields = {}
    -- Replace transmog appearance IDs (model viewer) and card lists.
    if data.transmogAppearances and next(data.transmogAppearances) then
        fields.inspectTransmogAppearances = data.transmogAppearances
    else
        fields.inspectTransmogAppearances = nil
    end
    fields.inspectGearItems    = #data.gearItems    > 0 and data.gearItems    or nil
    fields.inspectTransmogItems = #data.transmogItems > 0 and data.transmogItems or nil
    -- If caller also wants the note body updated, rebuild it.
    if richMode ~= nil then
        fields.body = richMode and BuildRichBody(data) or BuildNormalBody(data)
    end
    BNB.UpdateNote(noteID, fields)
    if BNB.RenderRefBox     then BNB.RenderRefBox() end
    if BNB.RefreshNoteList  then BNB.RefreshNoteList() end
end

--------------------------------------------------------------------------------
-- WARNING DIALOG: "You already have a note for [Name]"
-- Buttons: Open Note | Create Duplicate | Update gear | Update gear and note | Close
-- Dialog is 340x180 to fit two rows of buttons.
--------------------------------------------------------------------------------
local function BuildWarnDialogButtons(f)
    -- Row 1 (top): Open Note (left) | Create Duplicate (centre) | Close (right)
    f._openBtn = BNB.CreateButton(nil, f, L["AO_OPEN_NOTE_BTN"], 90, 26)
    f._openBtn:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 14, 48)

    f._dupeBtn = BNB.CreateButton(nil, f, L["INS_WARN_DUPLICATE"], 120, 26)
    f._dupeBtn:SetPoint("BOTTOM", f, "BOTTOM", 0, 48)

    local closeBtn = BNB.CreateButton(nil, f, L["CLOSE"], 70, 26)
    closeBtn:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -14, 48)
    closeBtn:SetScript("OnClick", function() f:Hide() end)

    -- Row 2 (bottom): Update gear (left) | Update gear and note (right)
    f._updGearBtn = BNB.CreateButton(nil, f, L["INS_WARN_UPDATE_GEAR"], 130, 26)
    f._updGearBtn:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 14, 14)

    f._updAllBtn = BNB.CreateButton(nil, f, L["INS_WARN_UPDATE_ALL"], 150, 26)
    f._updAllBtn:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -14, 14)
end

local function ShowWarningDialog(existingNoteID, playerName, onDuplicate, richMode)
    if not _warnDialog then
        local f
        if BigNoteBoxDB and BigNoteBoxDB.skinMode and BNB.CreateSkinFrame then
            f = BNB.CreateSkinFrame(UIParent, false, "BNBInspectWarnDialog", false)
            _G["BNBInspectWarnDialog"] = f
            f:SetSize(340, 180)
            f:SetPoint("CENTER")
            f:SetFrameStrata("DIALOG")
            f:SetToplevel(true); f:EnableMouse(true); f:SetMovable(true)
            f:RegisterForDrag("LeftButton")
            f:SetScript("OnDragStart", function(self) self:StartMoving() end)
            f:SetScript("OnDragStop",  function(self) self:StopMovingOrSizing() end)

            local tb = BNB.CreateSkinStrip(f, true, false)
            tb:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
            tb:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
            tb:SetHeight(26)
            tb:EnableMouse(true); tb:RegisterForDrag("LeftButton")
            tb:SetScript("OnDragStart", function() f:StartMoving() end)
            tb:SetScript("OnDragStop",  function() f:StopMovingOrSizing() end)

            local tl = tb:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            tl:SetPoint("CENTER", tb, "CENTER", -12, 0)
            tl:SetTextColor(1, 0.82, 0); tl:SetText(L["INS_NOTE_EXISTS"])

            BNB.CreateSkinCloseButton(tb, function() f:Hide() end)
                :SetPoint("RIGHT", tb, "RIGHT", -3, 0)

            local msg = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            msg:SetPoint("TOP", f, "TOP", 0, -38)
            msg:SetPoint("LEFT", f, "LEFT", 16, 0)
            msg:SetPoint("RIGHT", f, "RIGHT", -16, 0)
            msg:SetJustifyH("CENTER"); msg:SetWordWrap(true)
            f._msgLbl = msg

            BuildWarnDialogButtons(f)

            f:SetScript("OnShow", function()
                if BNB.ApplyMainWindowSkin then BNB.ApplyMainWindowSkin() end
            end)
        else
            f = CreateFrame("Frame", "BNBInspectWarnDialog", UIParent, "BasicFrameTemplateWithInset")
            f:SetSize(340, 180)
            f:SetPoint("CENTER")
            f:SetFrameStrata("DIALOG")
            f:SetToplevel(true); f:EnableMouse(true); f:SetMovable(true)
            f:RegisterForDrag("LeftButton")
            f:SetScript("OnDragStart", function(self) self:StartMoving() end)
            f:SetScript("OnDragStop",  function(self) self:StopMovingOrSizing() end)
            f.TitleText:SetText(L["INS_NOTE_EXISTS"])

            local msg = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            msg:SetPoint("TOP", f, "TOP", 0, -38)
            msg:SetPoint("LEFT", f, "LEFT", 16, 0)
            msg:SetPoint("RIGHT", f, "RIGHT", -16, 0)
            msg:SetJustifyH("CENTER"); msg:SetWordWrap(true)
            f._msgLbl = msg

            BuildWarnDialogButtons(f)
        end

        f:Hide()
        tinsert(UISpecialFrames, "BNBInspectWarnDialog")
        _warnDialog = f
    end

    _warnDialog._msgLbl:SetText(string.format(L["INS_WARN_EXISTS_FMT"], playerName))
    _warnDialog._openBtn:SetScript("OnClick", function() OpenExistingNote(existingNoteID) end)
    _warnDialog._dupeBtn:SetScript("OnClick", function()
        _warnDialog:Hide()
        if onDuplicate then onDuplicate() end
    end)
    _warnDialog._updGearBtn:SetScript("OnClick", function()
        _warnDialog:Hide()
        UpdateInspectGear(existingNoteID, nil)
        OpenExistingNote(existingNoteID)
    end)
    _warnDialog._updAllBtn:SetScript("OnClick", function()
        -- Confirm dialog: warn that the note body will be overwritten, but a
        -- restore point will be created first so the user can recover their edits.
        StaticPopupDialogs["BNB_CONFIRM_UPDATE_ALL"] = {
            text          = L["INS_WARN_UPDATE_ALL_CONFIRM"],
            button1       = L["INS_WARN_UPDATE_BTN"],
            button2       = L["CANCEL"],
            OnAccept      = function()
                -- Create restore point before overwriting the note body.
                BNB.HistoryCreateManual(existingNoteID)
                -- richMode captured from the outer ShowWarningDialog call.
                UpdateInspectGear(existingNoteID, richMode)
                OpenExistingNote(existingNoteID)
            end,
            timeout       = 0,
            whileDead     = true,
            hideOnEscape  = true,
            preferredIndex = 3,
        }
        _warnDialog:Hide()
        StaticPopup_Show("BNB_CONFIRM_UPDATE_ALL")
    end)
    _warnDialog:Show()
end

--------------------------------------------------------------------------------
-- TYPE DIALOG: "Normal" or "Rich"
--------------------------------------------------------------------------------
local function ShowTypeDialog()
    if not _typeDialog then
        local f
        if BigNoteBoxDB and BigNoteBoxDB.skinMode and BNB.CreateSkinFrame then
            f = BNB.CreateSkinFrame(UIParent, false, "BNBInspectNoteDialog", false)
            _G["BNBInspectNoteDialog"] = f
            f:SetSize(220, 100)
            f:SetPoint("CENTER")
            f:SetFrameStrata("DIALOG")
            f:SetToplevel(true); f:EnableMouse(true); f:SetMovable(true)
            f:RegisterForDrag("LeftButton")
            f:SetScript("OnDragStart", function(self) self:StartMoving() end)
            f:SetScript("OnDragStop",  function(self) self:StopMovingOrSizing() end)

            local tb = BNB.CreateSkinStrip(f, true, false)
            tb:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
            tb:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
            tb:SetHeight(26)
            tb:EnableMouse(true); tb:RegisterForDrag("LeftButton")
            tb:SetScript("OnDragStart", function() f:StartMoving() end)
            tb:SetScript("OnDragStop",  function() f:StopMovingOrSizing() end)

            local tl = tb:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            tl:SetPoint("CENTER", tb, "CENTER", -12, 0)
            tl:SetTextColor(1, 0.82, 0); tl:SetText(L["INS_CREATE_NOTE"])

            BNB.CreateSkinCloseButton(tb, function() f:Hide() end)
                :SetPoint("RIGHT", tb, "RIGHT", -3, 0)

            local nb = BNB.CreateButton(nil, f, L["SW_MODE_NORMAL"], 85, 28)
            nb:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 14, 14)
            nb:SetScript("OnClick", function() CreateInspectNote(false) end)

            local rb = BNB.CreateButton(nil, f, L["INS_RICH_BTN"], 85, 28)
            rb:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -14, 14)
            rb:SetScript("OnClick", function() CreateInspectNote(true) end)

            f:SetScript("OnShow", function()
                if BNB.ApplyMainWindowSkin then BNB.ApplyMainWindowSkin() end
            end)
        else
            f = CreateFrame("Frame", "BNBInspectNoteDialog", UIParent, "BasicFrameTemplateWithInset")
            f:SetSize(220, 100)
            f:SetPoint("CENTER")
            f:SetFrameStrata("DIALOG")
            f:SetToplevel(true); f:EnableMouse(true); f:SetMovable(true)
            f:RegisterForDrag("LeftButton")
            f:SetScript("OnDragStart", function(self) self:StartMoving() end)
            f:SetScript("OnDragStop",  function(self) self:StopMovingOrSizing() end)
            f.TitleText:SetText(L["INS_CREATE_NOTE"])

            local nb = BNB.CreateButton(nil, f, L["SW_MODE_NORMAL"], 85, 28)
            nb:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 14, 14)
            nb:SetScript("OnClick", function() CreateInspectNote(false) end)

            local rb = BNB.CreateButton(nil, f, L["INS_RICH_BTN"], 85, 28)
            rb:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -14, 14)
            rb:SetScript("OnClick", function() CreateInspectNote(true) end)
        end

        f:HookScript("OnHide", function(self)
            if BNB.StopWindowGlow then BNB.StopWindowGlow(self, TYPE_DIALOG_GLOW_KEY) end
        end)

        f:Hide()
        tinsert(UISpecialFrames, "BNBInspectNoteDialog")
        _typeDialog = f
    end
    _typeDialog:Show()
    if BNB.StartWindowGlow then BNB.StartWindowGlow(_typeDialog, TYPE_DIALOG_GLOW_KEY, BNB.BasicFrameGlowPad()) end
end

--------------------------------------------------------------------------------
-- MASTER FLOW
--------------------------------------------------------------------------------
local function StartInspectNoteFlow(isAutomatic)
    if not _inspectReady then return end

    local name, realm = BNB.UnitNameRealm("target")
    if not name then return end
    realm = realm and realm ~= "" and realm or GetNormalizedRealmName() or ""

    local existingID = FindExistingNote(name, realm)

    -- Determine note type
    local richMode = nil  -- nil = ask user
    local mode = GetMode()
    local noteType = GetType()

    if isAutomatic then
        richMode = (mode == "auto_rich")
        -- Automatic mode: create silently, skip if note already exists
        if existingID then return end
        CreateInspectNote(richMode, true)
        return
    end

    -- Manual mode
    if noteType == "always_rich" then
        richMode = true
    elseif noteType == "always_normal" then
        richMode = false
    end

    if existingID then
        -- Pass richMode so "Update gear and note" knows which body format to use.
        -- If richMode is nil (user will choose via type dialog), we pass nil and
        -- the update will use the existing note's richMode field.
        local updateRichMode = richMode
        if updateRichMode == nil then
            local existNote = BNB.GetNote(existingID)
            updateRichMode = existNote and existNote.richMode or false
        end
        ShowWarningDialog(existingID, name, function()
            if richMode ~= nil then
                CreateInspectNote(richMode, false)
            else
                ShowTypeDialog()
            end
        end, updateRichMode)
    else
        if richMode ~= nil then
            CreateInspectNote(richMode, false)
        else
            ShowTypeDialog()
        end
    end
end

--------------------------------------------------------------------------------
-- INSPECT FRAME BUTTON
--------------------------------------------------------------------------------
local function CreateInspectButton()
    if _inspectBtn then return end
    if not InspectFrame then return end

    local btn = CreateFrame("Button", "BNBInspectNoteBtn", InspectFrame)
    btn:SetSize(INS_SZ, INS_SZ)
    btn:SetPoint("TOPRIGHT", InspectFrame, "TOPRIGHT", INS_X, INS_Y)
    btn:SetFrameStrata("HIGH")
    btn:SetFrameLevel((InspectFrame:GetFrameLevel() or 0) + 10)

    local tex = btn:CreateTexture(nil, "ARTWORK"); tex:SetAllPoints()
    tex:SetTexture(BTNS .. "bt-createnote-normal")
    btn._tex = tex

    local hi = btn:CreateTexture(nil, "HIGHLIGHT"); hi:SetAllPoints()
    hi:SetTexture(BTNS .. "bt-createnote-hover")
    -- Pressed texture while held, same as the quest/gossip buttons (FOR-20)
    if BNB.AddQuickNotePressState then BNB.AddQuickNotePressState(btn, tex, hi) end

    btn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOMRIGHT")
        if not _inspectReady then
            GameTooltip:AddLine(L["QN_BTN_TIP1"], 1, 1, 1)
            GameTooltip:AddLine(L["INSPECT_TIP_WAITING"], 1, 0.5, 0.25)
        else
            local tName, tRealm = BNB.UnitNameRealm("target")
            tRealm = tRealm and tRealm ~= "" and tRealm or GetNormalizedRealmName() or ""
            local existing = tName and FindExistingNote(tName, tRealm)
            if existing then
                GameTooltip:AddLine(L["INSPECT_TIP_OPEN"], 1, 1, 1)
                GameTooltip:AddLine(string.format(L["INSPECT_TIP_EXISTS"], tName), 0.55, 0.8, 0.55)
                GameTooltip:AddLine(L["INSPECT_TIP_DUPE"], 0.78, 0.78, 0.78)
            else
                GameTooltip:AddLine(L["QN_BTN_TIP1"], 1, 1, 1)
                GameTooltip:AddLine(L["INSPECT_TIP_FROM"], 0.78, 0.78, 0.78)
            end
        end
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    btn:SetScript("OnClick", function()
        if not _inspectReady then return end
        StartInspectNoteFlow(false)
    end)

    btn:SetEnabled(false)
    btn:SetAlpha(0.35)
    pcall(function() tex:SetDesaturated(true) end)

    _inspectBtn = btn
end

local function EnableInspectBtn()
    if not _inspectBtn then return end
    _inspectReady = true
    _inspectBtn:SetEnabled(true)
    _inspectBtn:SetAlpha(1.0)
    pcall(function() _inspectBtn._tex:SetDesaturated(false) end)
end

local function DisableInspectBtn()
    if not _inspectBtn then return end
    _inspectReady = false
    _inspectBtn:SetEnabled(false)
    _inspectBtn:SetAlpha(0.35)
    pcall(function() _inspectBtn._tex:SetDesaturated(true) end)
end

--------------------------------------------------------------------------------
-- HOOKS AND EVENTS
--------------------------------------------------------------------------------
local evf = CreateFrame("Frame")
evf:RegisterEvent("ADDON_LOADED")
evf:RegisterEvent("INSPECT_READY")

-- GUID of the last INSPECT_READY. When the client already has a player's data
-- (inspected recently, or close by), INSPECT_READY can fire before InspectFrame
-- is shown; OnShow used to disable the button unconditionally after it, leaving
-- it greyed out for good on some players and not others. Now OnShow enables it
-- when the data for the shown unit has already arrived. Cleared on hide, since
-- Blizzard clears the inspect data then.
local _readyGUID = nil

local function InspectedGUID()
    local unit = InspectFrame and InspectFrame.unit or "target"
    return UnitGUID(unit)
end

local OnInspectReady   -- defined below, shared by INSPECT_READY and OnShow

local function HookInspectFrame()
    if not InspectFrame then return end
    InspectFrame:HookScript("OnShow", function()
        _autoCreatedThisInspect = false
        if _readyGUID and _readyGUID == InspectedGUID() then
            OnInspectReady()
        else
            DisableInspectBtn()
        end
    end)
    InspectFrame:HookScript("OnHide", function()
        DisableInspectBtn()
        _readyGUID = nil
        _autoCreatedThisInspect = false
        if _typeDialog then _typeDialog:Hide() end
        if _warnDialog then _warnDialog:Hide() end
    end)
end

evf:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" and arg1 == "Blizzard_InspectUI" then
        C_Timer.After(0, function()
            CreateInspectButton()
            HookInspectFrame()
        end)
    elseif event == "INSPECT_READY" then
        _readyGUID = arg1
        -- Ignore data for someone else (e.g. another addon inspecting)
        if InspectFrame and InspectFrame:IsShown()
           and (not arg1 or arg1 == InspectedGUID()) then
            OnInspectReady()
        end
    end
end)

OnInspectReady = function()
    EnableInspectBtn()
    -- One-shot flag set by TargetNote right-click "Inspect & Create Note".
    -- Takes priority over auto-create mode so the user sees the type dialog.
    if BNB._inspectAndCreate then
        BNB._inspectAndCreate = nil
        _autoCreatedThisInspect = true  -- suppress auto-create for this inspect
        C_Timer.After(0.1, function()
            if InspectFrame and InspectFrame:IsShown() and _inspectReady then
                StartInspectNoteFlow(false)  -- false = manual, shows type dialog
            end
        end)
        return
    end
    local mode = GetMode()
    if not _autoCreatedThisInspect and (mode == "auto_rich" or mode == "auto_normal") then
        _autoCreatedThisInspect = true
        C_Timer.After(0.1, function()
            if InspectFrame and InspectFrame:IsShown() and _inspectReady then
                StartInspectNoteFlow(true)
            end
        end)
    end
end

-- If Blizzard_InspectUI already loaded
if InspectFrame then
    C_Timer.After(0, function()
        CreateInspectButton()
        HookInspectFrame()
    end)
end

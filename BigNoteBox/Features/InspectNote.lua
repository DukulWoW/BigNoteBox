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
local SLOT_INFO = {
    { id =  1, label = "Head" },
    { id =  2, label = "Neck" },
    { id =  3, label = "Shoulder" },
    { id =  4, label = "Shirt" },
    { id =  5, label = "Chest" },
    { id =  6, label = "Waist" },
    { id =  7, label = "Legs" },
    { id =  8, label = "Feet" },
    { id =  9, label = "Wrist" },
    { id = 10, label = "Hands" },
    { id = 11, label = "Ring 1" },
    { id = 12, label = "Ring 2" },
    { id = 13, label = "Trinket 1" },
    { id = 14, label = "Trinket 2" },
    { id = 15, label = "Back" },
    { id = 16, label = "Main Hand" },
    { id = 17, label = "Off Hand" },
    { id = 19, label = "Tabard" },
}

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

    local name, realm = UnitName("target")
    data.name  = name or "Unknown"
    data.realm = realm and realm ~= "" and realm or GetNormalizedRealmName() or ""

    local pvpName = UnitPVPName("target")
    if pvpName and pvpName ~= data.name then
        data.displayTitle = pvpName
    end

    data.level = UnitLevel("target")
    if data.level == -1 then data.level = "??" end
    local className, classFile = UnitClass("target")
    data.className = className or "Unknown"
    data.classFile = classFile or "WARRIOR"
    local raceName, raceFile, raceID = UnitRace("target")
    data.race     = raceName or "Unknown"
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
            data.spec = specName
        end
    end

    local guildName, guildRankName = GetGuildInfo("target")
    data.guild     = guildName
    data.guildRank = guildRankName

    data.faction = UnitFactionGroup("target")

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
            local itemName, _, quality, ilvl, _, _, _, _, _, iconTex = GetItemInfo(itemID)
            local link = GetInventoryItemLink("target", slot.id)
            local actualIlvl = ilvl
            if link and GetDetailedItemLevelInfo then
                local effIlvl = GetDetailedItemLevelInfo(link)
                if effIlvl and effIlvl > 0 then actualIlvl = effIlvl end
            end
            local entry = {
                slot    = slot.label,
                slotIdx = slot.id,
                id      = itemID,
                name    = itemName or ("Item " .. itemID),
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
    local s = tostring(n)
    local pos, result = #s, ""
    while pos > 0 do
        local start = math.max(1, pos - 2)
        result = s:sub(start, pos) .. (result ~= "" and "," or "") .. result
        pos = start - 1
    end
    return result
end

local function BuildNormalBody(data)
    local lines = {}

    -- Name (with title if set)
    lines[#lines + 1] = data.displayTitle or data.name
    lines[#lines + 1] = ""

    local header = string.format("Level %s %s %s%s",
        tostring(data.level), data.race,
        data.spec and (data.spec .. " ") or "",
        data.className)
    lines[#lines + 1] = header

    if data.faction then
        lines[#lines + 1] = "Faction: " .. data.faction
    end

    if data.guild then
        local guildLine = "Guild: <" .. data.guild .. ">"
        if data.guildRank then guildLine = guildLine .. " (" .. data.guildRank .. ")" end
        lines[#lines + 1] = guildLine
    end

    lines[#lines + 1] = ""

    if data.ilvl then
        lines[#lines + 1] = "Item Level: " .. tostring(data.ilvl)
    end
    if data.achievePoints then
        lines[#lines + 1] = "Achievement Points: " .. FormatNumber(data.achievePoints)
    end
    if data.honorKills then
        lines[#lines + 1] = "Honor Kills: " .. FormatNumber(data.honorKills)
    end

    lines[#lines + 1] = ""

    if #data.gear > 0 then
        lines[#lines + 1] = "Equipment:"
        for _, g in ipairs(data.gear) do
            local ilvlStr = g.ilvl and (" (" .. tostring(g.ilvl) .. ")") or ""
            lines[#lines + 1] = "  " .. g.slot .. ": " .. g.name .. ilvlStr
        end
    end

    lines[#lines + 1] = ""
    lines[#lines + 1] = "Notes:"
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
    local subtitle = string.format("Level %s %s %s%s",
        tostring(data.level), data.race,
        data.spec and (data.spec .. " ") or "",
        data.className)
    lines[#lines + 1] = "{p:c}{col:" .. data.classHex .. "}" .. subtitle .. "{/col}{/p}"

    if data.faction then
        lines[#lines + 1] = "{p:c}" .. data.faction .. "{/p}"
    end

    lines[#lines + 1] = ""
    lines[#lines + 1] = ""

    -- Guild
    if data.guild then
        local guildStr = "Guild member of <" .. data.guild .. ">"
        if data.guildRank then guildStr = guildStr .. " (" .. data.guildRank .. ")" end
        lines[#lines + 1] = "{p}" .. guildStr .. "{/p}"
        lines[#lines + 1] = ""
        lines[#lines + 1] = ""
    end

    -- Stats
    local hasStats = data.ilvl or data.achievePoints or data.honorKills
    if hasStats then
        lines[#lines + 1] = "{h3}Stats{/h3}"
        lines[#lines + 1] = ""
        if data.ilvl then
            lines[#lines + 1] = "{p}Item Level: " .. tostring(data.ilvl) .. "{/p}"
        end
        if data.achievePoints then
            lines[#lines + 1] = "{p}Achievement Points: " .. FormatNumber(data.achievePoints) .. "{/p}"
        end
        if data.honorKills then
            lines[#lines + 1] = "{p}Honor Kills: " .. FormatNumber(data.honorKills) .. "{/p}"
        end
        lines[#lines + 1] = ""
        lines[#lines + 1] = ""
    end

    -- Gear with icons and quality colours
    if #data.gear > 0 then
        lines[#lines + 1] = "{h3}Equipment{/h3}"
        lines[#lines + 1] = ""
        for _, g in ipairs(data.gear) do
            local qHex = QUALITY_HEX[g.quality] or QUALITY_HEX[1]
            local ilvlStr = g.ilvl and (" (" .. tostring(g.ilvl) .. ")") or ""
            local iconStr = ""
            if g.icon then
                iconStr = "{icon:" .. tostring(g.icon) .. ":18} "
            end
            lines[#lines + 1] = "{p}" .. iconStr .. g.slot .. ": {col:" .. qHex .. "}" .. g.name .. ilvlStr .. "{/col}{/p}"
        end
    end

    lines[#lines + 1] = ""
    lines[#lines + 1] = ""
    lines[#lines + 1] = "{h3}Notes:{/h3}"
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
            candidate = baseName .. " (Duplicate)"
        else
            candidate = baseName .. " (Duplicate " .. i .. ")"
        end
        local found = false
        for _, note in pairs(ndb.notes) do
            if note.title == candidate then found = true; break end
        end
        if not found then return candidate end
    end
    return baseName .. " (Duplicate " .. time() .. ")"
end

-- Find existing note by player context. Returns noteID or nil.
local function FindExistingNote(playerName, realm)
    local ndb = BigNoteBoxNotesDB
    if not ndb or not ndb.notes then return nil end
    local ctx = "player:" .. playerName
    if realm and realm ~= "" then ctx = ctx .. "-" .. realm end
    for id, note in pairs(ndb.notes) do
        if note.context == ctx then return id end
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

    local tags = { "Inspected" }
    if data.race and data.race ~= "Unknown" then tags[#tags + 1] = data.race end
    if data.className and data.className ~= "Unknown" then tags[#tags + 1] = data.className end
    if data.spec then tags[#tags + 1] = data.spec end
    if data.faction then tags[#tags + 1] = data.faction end

    local fields = {
        source         = "inspect",
        richMode       = richMode or false,
        icon           = data.raceIcon,
        tags           = tags,
        inspectRaceID  = data.raceID,
        inspectSexID   = data.sexID,
        inspectName    = data.name,
        inspectRealm   = data.realm,
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
    f._openBtn = BNB.CreateButton(nil, f, "Open Note", 90, 26)
    f._openBtn:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 14, 48)

    f._dupeBtn = BNB.CreateButton(nil, f, "Create Duplicate", 120, 26)
    f._dupeBtn:SetPoint("BOTTOM", f, "BOTTOM", 0, 48)

    local closeBtn = BNB.CreateButton(nil, f, "Close", 70, 26)
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
            tl:SetTextColor(1, 0.82, 0); tl:SetText("Note Exists")

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
            f.TitleText:SetText("Note Exists")

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

    _warnDialog._msgLbl:SetText("You already have a note for " .. playerName .. ".")
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
            button1       = "Update",
            button2       = "Cancel",
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
            tl:SetTextColor(1, 0.82, 0); tl:SetText("Create Note")

            BNB.CreateSkinCloseButton(tb, function() f:Hide() end)
                :SetPoint("RIGHT", tb, "RIGHT", -3, 0)

            local nb = BNB.CreateButton(nil, f, "Normal", 85, 28)
            nb:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 14, 14)
            nb:SetScript("OnClick", function() CreateInspectNote(false) end)

            local rb = BNB.CreateButton(nil, f, "Rich", 85, 28)
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
            f.TitleText:SetText("Create Note")

            local nb = BNB.CreateButton(nil, f, "Normal", 85, 28)
            nb:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 14, 14)
            nb:SetScript("OnClick", function() CreateInspectNote(false) end)

            local rb = BNB.CreateButton(nil, f, "Rich", 85, 28)
            rb:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -14, 14)
            rb:SetScript("OnClick", function() CreateInspectNote(true) end)
        end

        f:Hide()
        tinsert(UISpecialFrames, "BNBInspectNoteDialog")
        _typeDialog = f
    end
    _typeDialog:Show()
end

--------------------------------------------------------------------------------
-- MASTER FLOW
--------------------------------------------------------------------------------
local function StartInspectNoteFlow(isAutomatic)
    if not _inspectReady then return end

    local name, realm = UnitName("target")
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

    btn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOMRIGHT")
        if not _inspectReady then
            GameTooltip:AddLine("Create a BigNoteBox note", 1, 1, 1)
            GameTooltip:AddLine("Waiting for inspect data...", 1, 0.5, 0.25)
        else
            local tName = UnitName("target")
            local tRealm = select(2, UnitName("target"))
            tRealm = tRealm and tRealm ~= "" and tRealm or GetNormalizedRealmName() or ""
            local existing = tName and FindExistingNote(tName, tRealm)
            if existing then
                GameTooltip:AddLine("Open existing note", 1, 1, 1)
                GameTooltip:AddLine("A note already exists for " .. tName .. ".", 0.55, 0.8, 0.55)
                GameTooltip:AddLine("Click to view or create a duplicate.", 0.78, 0.78, 0.78)
            else
                GameTooltip:AddLine("Create a BigNoteBox note", 1, 1, 1)
                GameTooltip:AddLine("from this player's inspect data.", 0.78, 0.78, 0.78)
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

local function HookInspectFrame()
    if not InspectFrame then return end
    InspectFrame:HookScript("OnShow", function()
        DisableInspectBtn()
        _autoCreatedThisInspect = false
    end)
    InspectFrame:HookScript("OnHide", function()
        DisableInspectBtn()
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
        if InspectFrame and InspectFrame:IsShown() then
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
    end
end)

-- If Blizzard_InspectUI already loaded
if InspectFrame then
    C_Timer.After(0, function()
        CreateInspectButton()
        HookInspectFrame()
    end)
end

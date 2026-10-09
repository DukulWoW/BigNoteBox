-- BigNoteBox UI/ReferenceBox.lua — Reference Box side panel
--
-- Anchors to the RIGHT of BNB.mainFrame, same height.
-- Shows item/spell attachments for the currently selected note.
-- Toggled from the editor bottom toolbar (right of Save button).
--
-- Input methods:
--   • Drag & drop (items, spells) onto the panel
--   • Shift-click any item/spell (Baganator-safe via hooksecurefunc)
--   • Manual entry: bare number = itemID, i:N or item:N = item, s:N or spell:N = spell
--
-- Public API:
--   BNB.ToggleReferenceBox()
--   BNB.OpenReferenceBox(noteID)
--   BNB.CloseReferenceBox()
--   BNB.SyncReferenceBox(noteID)   -- called by SelectNote; auto-opens if configured
--   BNB.RefreshReferenceBox()

local BNB = BigNoteBox
local L   = BNB.L

-- ── Constants ─────────────────────────────────────────────────────────────────
local RBW        = 290       -- wider to keep content width after scrollbar clearance
local TITLE_H    = 32        -- ButtonFrameTemplate title area
local PAD        = 10        -- outer padding between frame edges and cards
local SCROLL_PAD = 22        -- right clearance for ScrollFrameTemplate scrollbar
local CARD_PAD   = 6         -- icon left inset inside a card
local ROW_H_NORM = 52
local ROW_H_COMP = 28
local ROW_GAP    = 4
local ICON_SZ_N  = 32
local ICON_SZ_C  = 16
local MANUAL_H   = 28
local MANUAL_GAP = 4
local COUNT_H    = 20
local BOTTOM_PAD = 4

local ASSETS = "Interface\\AddOns\\BigNoteBox\\Assets\\"

-- ── Model viewer constants (inspect notes only) ──────────────────────────────
local MODEL_SPLIT_DEFAULT = 0.30   -- items get 30%, model gets 70% of scroll area
local MODEL_SPLIT_MIN_PX  = 60     -- minimum item area height in px
local MODEL_MIN_H         = 150    -- minimum model frame height in px
local MODEL_SPIN_KEY      = "refboxModelSpin"   -- BNB.Debounce key: item view spin resumes (ALL-206)
local MAX_PITCH           = 1.4    -- model viewer tilt limit, radians (about 80 degrees)
local MAX_DEPTH           = 6      -- Shift+wheel nearer / further limit, model units

-- ── Skin-mode title height (shared with UI/ReferenceBoxTasks.lua via the kit) ─
local SK_RB_TITLE_H         = 28

local QUALITY_COLORS = {
    [0]={r=0.62,g=0.62,b=0.62}, [1]={r=1.00,g=1.00,b=1.00},
    [2]={r=0.12,g=1.00,b=0.00}, [3]={r=0.00,g=0.44,b=0.87},
    [4]={r=0.64,g=0.21,b=0.93}, [5]={r=1.00,g=0.50,b=0.00},
    [6]={r=0.90,g=0.80,b=0.50}, [7]={r=0.00,g=0.80,b=1.00},
}
local function QualityColor(q) return QUALITY_COLORS[q or 1] or QUALITY_COLORS[1] end

-- ── Module state ──────────────────────────────────────────────────────────────
local rbFrame       = nil
local _noteID       = nil
local _rowPool      = {}
local _activeRows   = {}
local _pendingItems  = {}   -- itemID  → true
local _pendingSpells = {}   -- spellID → true
local _pendingQuests = {}   -- questID → true
-- _unavailable[type][id] = true when the game could not load an item's or
-- spell's data this session. Runtime only: an attachment is never deleted for
-- this (BUG-07, a retired quest or an item from the other client is still the
-- player's data). The row shows it as unavailable; the X removes it.
local _unavailable   = { item = {}, spell = {} }
local _modelHidden   = {}   -- noteID  → true (session-only, resets on /reload)
-- The entry shown in the model viewer from the list (ALL-206), or nil:
-- { noteID, att = { type, id }, spec = ModelSpec(att) }. For the open note
-- only: cleared when the Reference Box moves to another note.
local _shown         = nil
local _gearViewTmog  = {}   -- noteID  → true = showing transmog, false/nil = regular
-- Set true while SendAttachmentToChat is inserting, read by TryAddLink (shift-click hook).
-- Declared up here because SendAttachmentToChat comes first in the file.
local _suppressShiftHook = false

-- ── Mode state ────────────────────────────────────────────────────────────────
-- "attachments" = show attachments pane (default when no tasks)
-- "model"       = show model viewer (option C toggle, inspect notes only)
local _rbMode        = "attachments"

local RenderList               -- forward declaration
local SyncRefBoxHeight         -- forward declaration (defined near PositionFrame)
local EnsureSpellDataListener  -- forward declaration (defined after EnsureItemInfoListener)
local EnsureQuestDataListener  -- forward declaration
local GetQuestTitle            -- forward declaration
local UpdateModelViewer        -- forward declaration
local BuildModelViewer         -- forward declaration
local ApplyModelLayout         -- forward declaration
local UpdateDynamicTitle       -- forward declaration
local UpdateModeStrip          -- forward declaration
local PositionModeStrip        -- forward declaration (the picker's OnDragStop calls it)

-- The task panel lives in UI/ReferenceBoxTasks.lua (ALL-65.10e), which loads
-- after this file. The two meet in this kit: constants and live-state getters
-- here, helpers at the bottom of this file, and the task file adds
-- RenderTaskPanel, ApplyTaskLayout, BuildTaskPanel, RegisterTaskCallback and
-- RecompositeTaskPanel, which this file calls only at run time.
local K = {}
BNB._RefBoxKit = K
K.RBFrame = function() return rbFrame end
K.NoteID  = function() return _noteID end
K.RBMode  = function() return _rbMode end
K.RBW, K.TITLE_H, K.SK_RB_TITLE_H, K.PAD, K.SCROLL_PAD = RBW, TITLE_H, SK_RB_TITLE_H, PAD, SCROLL_PAD
K.MANUAL_H, K.MANUAL_GAP, K.COUNT_H, K.BOTTOM_PAD = MANUAL_H, MANUAL_GAP, COUNT_H, BOTTOM_PAD
K.ASSETS = ASSETS

-- ── DB helpers ────────────────────────────────────────────────────────────────
local function DB()  return BigNoteBoxDB     end
local function NDB() return BNB.NotesDB() end

local function GetAttachments(id)
    local note = id and NDB() and NDB().notes and NDB().notes[id]
    return note and note.attachments or nil
end
local function GetMaxItems() return DB().refboxMaxItems or BNB.DEFAULTS.refboxMaxItems end
local function IsCompact()   return DB().refboxDisplayStyle == "compact" end

-- This window is made of three parts, each following its own module (ALL-388,
-- after ALL-102): Reference (add strip, count, attachment list, "Show model" on
-- an entry) = the Reference Box switch, Model (the note's own player / NPC
-- model and its gear list) = Player & NPC Notes, Tasks = Tasks. It opens while
-- any part is on and has something to show. With the Reference part off the
-- window shows the model view and / or the tasks view, the side tabs switching
-- between them as before.
local function RBOn() return DB().referenceBoxEnabled ~= false end
-- The tasks view without the Reference part: the task panel fills the window
local function TasksOnly() return not RBOn() and _rbMode ~= "model" end
K.RBOn, K.TasksOnly = RBOn, TasksOnly

-- Returns true if the note has model viewer data (inspect notes or target notes with npcID).
-- The Model part follows Player & NPC Notes, not the Reference Box (ALL-388):
-- false while that module is off (ALL-343: they are ordinary notes then).
local function IsInspectNote(id)
    if not BNB.UnitNotesEnabled() then return false end
    local note = id and NDB() and NDB().notes and NDB().notes[id]
    if not note then return false end
    if note.source == "inspect" and note.inspectRaceID ~= nil then return true end
    if note.source == "target" and note.targetNpcID ~= nil and not note.targetIsPet then return true end
    return false
end
-- The entry shown from the list (ALL-206), when it belongs to this note
local function ShownFor(id)
    return _shown and id and _shown.noteID == id and RBOn() and _shown or nil
end

-- Has a model view: an inspect / NPC note, or an entry shown on demand
-- ("Show model", ALL-206). Everything that decides whether the Model tab and
-- the viewer exist asks this; IsInspectNote is the note's own model only.
local function HasModel(id)
    return IsInspectNote(id) or ShownFor(id) ~= nil
end

-- How a Reference Box entry is drawn in the model viewer (ALL-206), or nil
-- when it has none (quests, most spells, reagents and other plain items):
--   { kind = "gear",     id = itemID }      tried on a character
--   { kind = "weapon",   id = itemID }      on its own (weapons, shields, off-hands)
--   { kind = "creature", id = creatureID }  battle pet
--   { kind = "display",  id = displayID }   mount (item or spell), pet fallback
local function MountSpec(mountID)
    if not (mountID and C_MountJournal and C_MountJournal.GetMountInfoExtraByID) then return nil end
    local ok, displayID = pcall(C_MountJournal.GetMountInfoExtraByID, mountID)
    if ok and displayID and displayID ~= 0 then return { kind = "display", id = displayID } end
    return nil
end
-- An item's transmog appearance (ALL-213): appearanceID (the visual a model
-- can show on its own), sourceID. nil when it has none.
local function ItemAppearance(itemID)
    local TC = C_TransmogCollection
    if not (TC and TC.GetItemInfo) then return nil end
    local ok, appearanceID, sourceID = pcall(TC.GetItemInfo, itemID)
    if ok and sourceID then return appearanceID, sourceID end
    return nil
end

-- The camera Blizzard's Appearances tab uses for a gear piece's slot
-- (ALL-213), or nil: item -> appearance source -> UI camera. A weapon's
-- camera is made for the weapon shown on its own (SetItemAppearance), not
-- held by a character: on a character it tipped the model on its side.
local function GearCameraID(itemID, sourceID)
    local TC = C_TransmogCollection
    if not (TC and TC.GetAppearanceCameraIDBySource) then return nil end
    if not sourceID then sourceID = select(2, ItemAppearance(itemID)) end
    if not sourceID then return nil end
    local ok, cameraID = pcall(TC.GetAppearanceCameraIDBySource, sourceID)
    if ok and cameraID and cameraID ~= 0 then return cameraID end
    return nil
end

-- Shown on their own in the viewer, as in the Appearances tab
local WEAPON_LOCS = {
    INVTYPE_WEAPON = true, INVTYPE_2HWEAPON = true, INVTYPE_WEAPONMAINHAND = true,
    INVTYPE_WEAPONOFFHAND = true, INVTYPE_SHIELD = true, INVTYPE_HOLDABLE = true,
    INVTYPE_RANGED = true, INVTYPE_RANGEDRIGHT = true, INVTYPE_THROWN = true,
}
-- Armour slots seen on a character. IsDressableItemByID can answer false for
-- an item whose data has not loaded yet; the equip slot is known at once.
local WORN_LOCS = {
    INVTYPE_HEAD = true, INVTYPE_SHOULDER = true, INVTYPE_BODY = true,
    INVTYPE_CHEST = true, INVTYPE_ROBE = true, INVTYPE_WAIST = true,
    INVTYPE_LEGS = true, INVTYPE_FEET = true, INVTYPE_WRIST = true,
    INVTYPE_HAND = true, INVTYPE_CLOAK = true, INVTYPE_TABARD = true,
}

local function ModelSpec(att)
    if not (att and att.id) then return nil end
    if att.type == "item" then
        local id = att.id
        if C_MountJournal and C_MountJournal.GetMountFromItem then
            local ok, mountID = pcall(C_MountJournal.GetMountFromItem, id)
            local spec = ok and MountSpec(mountID)
            if spec then return spec end
        end
        if C_PetJournal and C_PetJournal.GetPetInfoByItemID then
            -- returns name, icon, petType, creatureID, ..., creatureDisplayID (12th)
            local ok, _, _, _, creatureID, _, _, _, _, _, _, _, displayID =
                pcall(C_PetJournal.GetPetInfoByItemID, id)
            if ok and creatureID and creatureID ~= 0 then return { kind = "creature", id = creatureID } end
            if ok and displayID and displayID ~= 0 then return { kind = "display", id = displayID } end
        end
        -- att.sourceID: a transmog gear card's appearance (inspect notes),
        -- drawn as that exact appearance, variant included
        local equipLoc = C_Item.GetItemInfoInstant and select(4, C_Item.GetItemInfoInstant(id))
        local dressable = (C_Item.IsDressableItemByID and C_Item.IsDressableItemByID(id))
            or WEAPON_LOCS[equipLoc] or WORN_LOCS[equipLoc] or att.sourceID
        if dressable then
            return { kind = WEAPON_LOCS[equipLoc] and "weapon" or "gear", id = id, sourceID = att.sourceID }
        end
    elseif att.type == "spell" and C_MountJournal and C_MountJournal.GetMountFromSpell then
        local ok, mountID = pcall(C_MountJournal.GetMountFromSpell, att.id)
        return ok and MountSpec(mountID) or nil
    end
    return nil
end

local function IsLocked(id)
    local note = id and NDB() and NDB().notes and NDB().notes[id]
    if not note then return false end
    if note.locked == true  then return true end
    if note.locked == false then return false end
    return DB().lockNotes == true
end

-- ── Attachment persistence ────────────────────────────────────────────────────
-- The attachment list is changed in place; UpdateNote(id, {}) then stamps the
-- edit (`updated`), as any other change to a note does (SV-07).
local function AddAttachment(noteID, att)
    if not noteID then return end
    if IsLocked(noteID) then
        BNB:Print(L["REFBOX_LOCKED"])
        return
    end
    local note = NDB().notes[noteID]
    if not note then return end
    if not note.attachments then note.attachments = {} end
    if #note.attachments >= GetMaxItems() then
        BNB:Print(string.format(L["REFBOX_FULL"], GetMaxItems()))
        return
    end
    for _, ex in ipairs(note.attachments) do
        if ex.type == att.type and ex.id == att.id then return end
    end
    table.insert(note.attachments, att)
    BNB.UpdateNote(noteID, {})
    if BNB.RefreshReferenceBox then BNB.RefreshReferenceBox() end
end

local function RemoveAttachment(noteID, index)
    if not noteID then return end
    local note = NDB().notes[noteID]
    if not note or not note.attachments then return end
    table.remove(note.attachments, index)
    BNB.UpdateNote(noteID, {})
    if BNB.RefreshReferenceBox then BNB.RefreshReferenceBox() end
end

local function CopyAttachment(fromNoteID, attIndex, toNoteID)
    if not fromNoteID or not toNoteID then return end
    local fromNote = NDB().notes[fromNoteID]
    if not fromNote or not fromNote.attachments then return end
    local att = fromNote.attachments[attIndex]
    if not att then return end
    -- Build a fresh copy and add to target
    local copy = {}; for k, v in pairs(att) do copy[k] = v end
    AddAttachment(toNoteID, copy)
end

local function MoveAttachment(fromNoteID, attIndex, toNoteID)
    if not fromNoteID or not toNoteID then return end
    local fromNote = NDB().notes[fromNoteID]
    if not fromNote or not fromNote.attachments then return end
    local att = fromNote.attachments[attIndex]
    if not att then return end
    -- Check dest capacity before removing from source
    local toNote = NDB().notes[toNoteID]
    if not toNote then return end
    if not toNote.attachments then toNote.attachments = {} end
    if #toNote.attachments >= GetMaxItems() then
        BNB:Print(L["REFBOX_MOVE_FULL"])
        return
    end
    table.remove(fromNote.attachments, attIndex)
    local copy = {}; for k, v in pairs(att) do copy[k] = v end
    table.insert(toNote.attachments, copy)
    BNB.UpdateNote(fromNoteID, {})
    BNB.UpdateNote(toNoteID, {})
    if BNB.RefreshReferenceBox then BNB.RefreshReferenceBox() end
end

-- ── Data resolution ───────────────────────────────────────────────────────────
-- Mark an attachment's data unavailable (flag true) or loaded again (false)
-- and redraw when that changes. Never touches the note (BUG-07).
local function SetUnavailable(kind, id, flag)
    local t = _unavailable[kind]
    if (t[id] == true) == flag then return end
    t[id] = flag or nil
    if rbFrame and rbFrame:IsShown() then RenderList() end
end

-- Row data for an attachment whose data could not be loaded: grey, with its id
local function UnavailableInfo(att, typeLabel)
    return { name = string.format(L["REFBOX_UNAVAILABLE_FMT"], tostring(att.id)),
             icon = "Interface\\Icons\\INV_Misc_QuestionMark",
             qr = 0.50, qg = 0.50, qb = 0.50, typeLabel = typeLabel, quality = -1 }
end

local function ResolveAttachment(att)
    if att.type == "item" then
        local name, _, quality, _, _, _, _, _, _, iconTex = C_Item.GetItemInfo(att.id)
        if not name then
            C_Item.RequestLoadItemDataByID(att.id)
            if _unavailable.item[att.id] then
                return UnavailableInfo(att, L["REFBOX_TYPE_GEAR"])
            end
            -- One timeout per pending id, not one per render. Still nothing
            -- after 10 s: show it as unavailable. (This used to be 1 s and
            -- deleted the attachment from whichever note was shown, BUG-07.)
            if not _pendingItems[att.id] then
                _pendingItems[att.id] = true
                local pendingID = att.id
                C_Timer.After(10, function()
                    if not _pendingItems[pendingID] then return end
                    _pendingItems[pendingID] = nil
                    SetUnavailable("item", pendingID, true)
                end)
            end
            return nil
        end
        _pendingItems[att.id] = nil
        _unavailable.item[att.id] = nil
        local qc = QualityColor(quality)
        return { name=name, icon=iconTex or "Interface\\Icons\\INV_Misc_QuestionMark",
                 qr=qc.r, qg=qc.g, qb=qc.b, typeLabel=L["REFBOX_TYPE_GEAR"], quality=quality }
    elseif att.type == "spell" then
        -- C_Spell.GetSpellInfo returns nil for spells not yet in the client cache
        -- (e.g. freshly dragged from the spellbook). We request a load and retry,
        -- mirroring the item pending pattern.
        local name, icon
        local info = C_Spell.GetSpellInfo(att.id)
        if info then name = info.name; icon = info.iconID end
        if not name then
            -- Not cached yet — request a load and mark as pending
            if C_Spell and C_Spell.RequestLoadSpellData then
                C_Spell.RequestLoadSpellData(att.id)
            end
            EnsureSpellDataListener()
            if _unavailable.spell[att.id] then
                return UnavailableInfo(att, L["REFBOX_TYPE_SPELL"])
            end
            -- Still nothing after 5 s: show it as unavailable, never delete (BUG-07)
            if not _pendingSpells[att.id] then
                _pendingSpells[att.id] = true
                local pendingID = att.id
                C_Timer.After(5, function()
                    if not _pendingSpells[pendingID] then return end
                    _pendingSpells[pendingID] = nil
                    SetUnavailable("spell", pendingID, true)
                end)
            end
            return nil
        end
        _pendingSpells[att.id] = nil
        _unavailable.spell[att.id] = nil
        -- icon from C_Spell is a fileDataID number; SetTexture accepts both paths and IDs
        return { name=name, icon=icon or "Interface\\Icons\\INV_Misc_QuestionMark",
                 qr=0.40, qg=0.70, qb=1.00, typeLabel=L["REFBOX_TYPE_SPELL"], quality=-1 }
    elseif att.type == "quest" then
        local title = GetQuestTitle(att.id)
        local unknown = not title or title == ""
        if unknown then
            -- Request async server fetch — re-render on QUEST_DATA_LOAD_RESULT
            if C_QuestLog and C_QuestLog.RequestLoadQuestByID then
                C_QuestLog.RequestLoadQuestByID(att.id)
            end
            _pendingQuests[att.id] = true
            EnsureQuestDataListener()
            -- Use stored title hint (from wowhead URL slug) if available
            title = (att.title and att.title ~= "") and att.title or nil
        end
        local questIcon = "Interface\\GossipFrame\\AvailableQuestIcon"
        local typeLabel = (unknown and not att.title)
            and string.format(L["REFBOX_TYPE_QUEST_UNKNOWN_FMT"], L["REFBOX_TYPE_QUEST"])
            or L["REFBOX_TYPE_QUEST"]
        return {
            name      = title or string.format(L["REFBOX_QUEST_FALLBACK_FMT"], att.id),
            icon      = questIcon,
            qr        = 1.00, qg = 0.82, qb = 0.00,
            typeLabel = typeLabel,
            quality   = -1,
            unknown   = unknown and not att.title,
        }
    elseif att.type == "npc" then
        -- NPC pseudo-attachment from target note creation
        local typeStr = att.creatureType or "Creature"
        if att.level then
            typeStr = "Lv " .. tostring(att.level) .. " " .. typeStr
        end
        return {
            name      = att.name or "Unknown",
            icon      = att.icon or "Interface\\Icons\\INV_Misc_QuestionMark",
            qr        = 0.75, qg = 0.60, qb = 0.40,  -- warm brown
            typeLabel = typeStr,
            quality   = -1,
            isSubject = true,  -- marks as non-deletable note subject
        }
    elseif att.type == "player" then
        -- Player pseudo-attachment from target note creation
        local typeStr = att.className or "Player"
        if att.race then typeStr = att.race .. " " .. typeStr end
        if att.level then typeStr = "Lv " .. tostring(att.level) .. " " .. typeStr end
        -- Use class colour if available
        local cc = RAID_CLASS_COLORS and att.classFile and RAID_CLASS_COLORS[att.classFile]
        local qr = cc and cc.r or 0.60
        local qg = cc and cc.g or 0.60
        local qb = cc and cc.b or 0.60
        return {
            name      = att.name or "Unknown",
            icon      = att.icon or "Interface\\Icons\\INV_Misc_QuestionMark",
            qr        = qr, qg = qg, qb = qb,
            typeLabel = typeStr,
            quality   = -1,
            isSubject = true,
        }
    end
end

-- ── GET_ITEM_INFO_RECEIVED — re-render on cache fill, mark on failure ─────────
local _itemInfoFrame
local function EnsureItemInfoListener()
    if _itemInfoFrame then return end
    _itemInfoFrame = CreateFrame("Frame")
    _itemInfoFrame:RegisterEvent("GET_ITEM_INFO_RECEIVED")
    _itemInfoFrame:SetScript("OnEvent", function(_, _, itemID, success)
        local wasUnavailable = _unavailable.item[itemID]
        if not _pendingItems[itemID] and not wasUnavailable then return end
        _pendingItems[itemID] = nil
        -- Failure marks the attachment unavailable; it is never removed (BUG-07).
        -- A late success brings an unavailable one back.
        SetUnavailable("item", itemID, not success)
        if success and not wasUnavailable and rbFrame and rbFrame:IsShown() then RenderList() end
    end)
end

-- ── SPELL_DATA_LOAD_RESULT — re-render on spell cache fill ───────────────────
local _spellDataFrame
EnsureSpellDataListener = function()
    if _spellDataFrame then return end
    _spellDataFrame = CreateFrame("Frame")
    _spellDataFrame:RegisterEvent("SPELL_DATA_LOAD_RESULT")
    _spellDataFrame:SetScript("OnEvent", function(_, _, spellID, success)
        local wasUnavailable = _unavailable.spell[spellID]
        if not _pendingSpells[spellID] and not wasUnavailable then return end
        _pendingSpells[spellID] = nil
        -- Same as items: mark, never remove (BUG-07)
        SetUnavailable("spell", spellID, not success)
        if success and not wasUnavailable and rbFrame and rbFrame:IsShown() then RenderList() end
    end)
end

-- ── Quest title lookup — with async server fetch ──────────────────────────────
-- C_QuestLog.GetTitleForQuestID (added Patch 9.0.1) works for any quest ID,
-- not just those in the log. Returns nil if data not yet cached — in that case
-- we request a server fetch and re-render when QUEST_DATA_LOAD_RESULT fires.
GetQuestTitle = function(questID)
    if C_QuestLog and C_QuestLog.GetTitleForQuestID then
        return C_QuestLog.GetTitleForQuestID(questID)
    elseif C_QuestLog and C_QuestLog.GetQuestInfo then
        return C_QuestLog.GetQuestInfo(questID)
    end
    return nil
end

-- ── QUEST_DATA_LOAD_RESULT — re-render when server returns quest data ─────────
local _questDataFrame
EnsureQuestDataListener = function()
    if _questDataFrame then return end
    _questDataFrame = CreateFrame("Frame")
    _questDataFrame:RegisterEvent("QUEST_DATA_LOAD_RESULT")
    _questDataFrame:SetScript("OnEvent", function(_, _, questID, success)
        if not _pendingQuests[questID] then return end
        _pendingQuests[questID] = nil
        -- On failure the row already reads "Quest <id>" (unknown), so it stays
        -- as it is: retired and seasonal quests fail here, and the attachment is
        -- never removed for it (BUG-07)
        if success and rbFrame and rbFrame:IsShown() then RenderList() end
    end)
end

-- Item tooltip beside the whole window, level with the hovered row, on the
-- main window's side, over the main window where there is room (Dukul
-- 2026-10-03: anchored to the row it was clamped over the Reference Box and hid
-- the list). Main window closed: the right side. The other side when the
-- screen edge is in the way. Offsets are worked out in screen pixels, so any scale works.
-- Which side PlaceItemTip put the item tooltip on, and for which row. Kept
-- here, not on GameTooltip, so nothing is written onto a Blizzard frame.
local _tipSide, _tipOwner

-- Comparison tooltips ("Equipped") go on the far side of the item tooltip,
-- away from the Reference Box. Blizzard puts them on the side with more screen
-- room, which put them over the list (Dukul 2026-10-03, I29). Runs after
-- Blizzard's anchoring (hook below) and after PlaceItemTip moves the tooltip.
local function PlaceCompareTips()
    local tt = GameTooltip
    if not (_tipSide and tt:IsShown() and tt:GetOwner() == _tipOwner) then return end
    local prev = tt
    for _, st in ipairs(tt.shoppingTooltips or {}) do
        if st:IsShown() then
            local y = 0
            if prev == tt then y = select(5, st:GetPoint(1)) or 0 end   -- keep Blizzard's drop
            st:ClearAllPoints()
            if _tipSide == "left" then
                st:SetPoint("TOPRIGHT", prev, "TOPLEFT", 0, y)
            else
                st:SetPoint("TOPLEFT", prev, "TOPRIGHT", 0, y)
            end
            prev = st
        end
    end
end
if TooltipComparisonManager and TooltipComparisonManager.AnchorShoppingTooltips then
    hooksecurefunc(TooltipComparisonManager, "AnchorShoppingTooltips", function()
        pcall(PlaceCompareTips)
    end)
end

local function PlaceItemTip(anchor)
    local rb = rbFrame
    if not (rb and rb:IsShown() and rb:GetLeft() and anchor:GetTop()) then return end
    local side = (BigNoteBoxDB and BigNoteBoxDB.refboxSide) or BNB.DEFAULTS.refboxSide
    local mainShown = BNB.mainFrame and BNB.mainFrame:IsShown()
    local goLeft = mainShown and side == "right"   -- Reference Box right of the main window
    local ts, rs, as = GameTooltip:GetEffectiveScale(), rb:GetEffectiveScale(), anchor:GetEffectiveScale()
    local tipW = GameTooltip:GetWidth() * ts
    local screenW = UIParent:GetRight() * UIParent:GetEffectiveScale()
    local GAP = 4 * rs
    if goLeft and rb:GetLeft() * rs - GAP - tipW < 0 then goLeft = false
    elseif not goLeft and rb:GetRight() * rs + GAP + tipW > screenW then goLeft = true end
    local y = (anchor:GetTop() * as - rb:GetTop() * rs) / ts
    GameTooltip:ClearAllPoints()
    if goLeft then
        GameTooltip:SetPoint("TOPRIGHT", rb, "TOPLEFT", -GAP / ts, y)
    else
        GameTooltip:SetPoint("TOPLEFT", rb, "TOPRIGHT", GAP / ts, y)
    end
    _tipSide, _tipOwner = goLeft and "left" or "right", anchor
    pcall(PlaceCompareTips)   -- they may already be up, anchored for the old position
end

local function ShowTooltip(anchor, att)
    GameTooltip:SetOwner(anchor, "ANCHOR_NONE")
    GameTooltip:SetPoint("TOPRIGHT", anchor, "TOPLEFT")   -- until PlaceItemTip moves it
    if att.type == "item" then
        GameTooltip:SetHyperlink("item:" .. att.id)
    elseif att.type == "spell" then
        GameTooltip:SetSpellByID(att.id)
    elseif att.type == "quest" then
        local title = GetQuestTitle(att.id)
        if title and title ~= "" then
            GameTooltip:SetHyperlink("quest:" .. att.id .. ":0")
        else
            -- Quest not in log — show manual info tooltip
            GameTooltip:AddLine(att.title or string.format(L["REFBOX_QUEST_FALLBACK_FMT"], att.id), 1, 0.82, 0)
            GameTooltip:AddLine(string.format(L["REFBOX_TT_QUESTID_FMT"], att.id), 0.78, 0.78, 0.78)
            GameTooltip:AddLine(L["REFBOX_TT_NOT_IN_LOG"], 0.55, 0.55, 0.55)
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine(L["REFBOX_TT_COPY_WOWHEAD"], 0.55, 0.82, 0.55)
        end
    end
    GameTooltip:Show()
    PlaceItemTip(anchor)   -- after Show: the width is known only then
end

-- ── Send attachment link to chat ──────────────────────────────────────────────
-- Gets the fully colour-coded hyperlink for an attachment.
-- For items: GetItemInfo's second return is the complete |cff...|r hyperlink.
-- For spells: construct the standard light-blue spell link manually.
local function BuildAttachmentLink(att)
    if att.type == "item" then
        local _, itemLink = C_Item.GetItemInfo(att.id)
        return itemLink
    elseif att.type == "spell" then
        local name
        local info = C_Spell.GetSpellInfo(att.id)
        name = info and info.name
        if name then
            return "|cff71d5ff|Hspell:" .. att.id .. "|h[" .. name .. "]|h|r"
        end
    elseif att.type == "quest" then
        local title = GetQuestTitle(att.id)
        title = (title and title ~= "") and title
            or (att.title and att.title ~= "") and att.title
            or ("Quest " .. att.id)
        return "|cffffff00|Hquest:" .. att.id .. ":0|h[" .. title .. "]|h|r"
    end
    return nil
end

-- Returns the Wowhead URL for an attachment (all types supported).
local function BuildWowheadURL(att)
    -- Per client (ALL-151, BNB.WowheadURL in Init.lua)
    if att.type == "item" or att.type == "spell" or att.type == "quest" then
        return BNB.WowheadURL(att.type, att.id)
    end
    return nil
end

-- Insert the attachment link at the text cursor in the active note body editor.
local function InsertAttachmentIntoNote(att, noteID)
    if IsLocked(noteID) then
        BNB:Print(L["REFBOX_LOCKED"])
        return
    end
    local link = BuildAttachmentLink(att)
    if not link then
        BNB:Print(L["REFBOX_LINK_FAIL"])
        return
    end
    local eb = nil
    if BNB._focusEditorBody and BNB._focusEditorBody:HasFocus() then
        eb = BNB._focusEditorBody
    elseif BNB._editorBody then
        eb = BNB._editorBody
    end
    if not eb then return end
    eb:Insert(link)
end

-- Insert link into chat.
-- If BCB is installed: show BCB frame + call BigChatBox.InsertLinkIntoBCB directly
-- (avoids the ChatFrame1EditBox pipeline delay that causes a one-step lag).
-- If no BCB: activate the default Blizzard editbox + ChatEdit_InsertLink.
-- (12.x moved these to ChatFrameUtil; the old globals still exist on every
-- client per the API dumps, so they are used where ChatFrameUtil is missing.)
local InsertLink   = (ChatFrameUtil and ChatFrameUtil.InsertLink) or ChatEdit_InsertLink
local ActivateChat = (ChatFrameUtil and ChatFrameUtil.ActivateChat) or ChatEdit_ActivateChat
local function SendAttachmentToChat(att)
    local link = BuildAttachmentLink(att)
    if not link then
        BNB:Print(L["REFBOX_LINK_FAIL"])
        return
    end

    if BigChatBox and BigChatBox.frame and BigChatBox.editBox then
        -- BCB present: show its frame, focus its editbox, then insert directly.
        -- BCB exposes InsertLinkIntoBCB which writes straight into its editbox
        -- without going through ChatFrame1EditBox's pipeline (avoids the one-step lag).
        BigChatBox.frame:Show()
        BigChatBox.editBox:SetFocus()
        if BigChatBox.InsertLinkIntoBCB then
            BigChatBox.InsertLinkIntoBCB(link)
        else
            -- Fallback if the function isn't exposed (future BCB version)
            _suppressShiftHook = true
            InsertLink(link)
            C_Timer.After(0.1, function() _suppressShiftHook = false end)
        end
    else
        -- No BCB: activate the standard Blizzard chat editbox and insert directly.
        local editBox = DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.editBox
        if editBox then
            ActivateChat(editBox)
        end
        _suppressShiftHook = true
        InsertLink(link)
        C_Timer.After(0.1, function() _suppressShiftHook = false end)
    end
end

-- Debug mode only: one chat line per step of showing an entry (ALL-206,
-- transmog cards that drew nothing, 2026-10-02)
local function ViewerTrace(fmt, ...)
    local db = BigNoteBoxDB
    if db and db.debugMode then
        BNB:Print("|cff88bbff[viewer]|r " .. string.format(fmt, ...))
    end
end
K.ViewerTrace = ViewerTrace

-- Dressing room for an entry: a transmog card's exact appearance (its saved
-- source) through DressUpVisual, anything else through its item link
local function DressUpEntry(att)
    if att.sourceID and DressUpVisual then
        local ok, shown = pcall(DressUpVisual, att.sourceID)
        ViewerTrace("dressing room source %s: ok=%s result=%s", tostring(att.sourceID), tostring(ok), tostring(shown))
        if ok then return end
    end
    local _, link = C_Item.GetItemInfo(att.id)
    ViewerTrace("dressing room item %s: link=%s", tostring(att.id), tostring(link ~= nil))
    if link then DressUpItemLink(link) end
end

-- ── Show an entry in the model viewer (ALL-206) ──────────────────────────────
-- Any note gets the Model tab while an entry is shown; on an inspect or NPC
-- note the entry takes the place of the player / NPC until the viewer's X.
-- Returns false when the entry has no model.
local function ShowInViewer(att)
    local spec = ModelSpec(att)
    ViewerTrace("show %s %s source=%s -> %s", tostring(att.type), tostring(att.id), tostring(att.sourceID),
        spec and (spec.kind .. " " .. tostring(spec.id) .. " source=" .. tostring(spec.sourceID)) or "no model")
    -- Showing an entry is the Reference part's (ALL-388): off = its link window
    if not (spec and _noteID and rbFrame and RBOn()) then return false end
    _shown = { noteID = _noteID, att = { type = att.type, id = att.id, sourceID = att.sourceID }, spec = spec }
    _modelHidden[_noteID] = nil
    _rbMode = "model"
    if rbFrame._modelFrame then rbFrame._modelFrame._shownKey = nil end   -- load it again
    UpdateModeStrip()
    RenderList()
    UpdateModelViewer()
    return true
end

-- The viewer's X: back to the note's own model, or no Model tab on other notes
local function ClearShownModel()
    _shown = nil
    local mdl = rbFrame and rbFrame._modelFrame
    if mdl then
        mdl._shownKey = nil
        if mdl._stopSpin then mdl._stopSpin() end
    end
    if not IsInspectNote(_noteID) then _rbMode = "attachments" end
    UpdateModeStrip()
    RenderList()
    UpdateModelViewer()
end

-- Open an entry's link the way a click on a chat link does (the item, spell or
-- quest window), for entries the viewer cannot show.
local function OpenEntryLink(att)
    local link = BuildAttachmentLink(att)
    local data = link and link:match("|H(.-)|h")
    if data and SetItemRef then pcall(SetItemRef, data, link, "LeftButton") end
end

-- Left-click on a list entry, as on a link in chat (ALL-206, Dukul
-- 2026-10-02): Shift = into the chat box, Ctrl = dressing room (items),
-- plain = shown in the model viewer, or its link window when it has no model.
local function OnEntryClick(att)
    if IsShiftKeyDown() then
        SendAttachmentToChat(att)
    elseif IsControlKeyDown() and att.type == "item" then
        DressUpEntry(att)
    elseif not ShowInViewer(att) then
        OpenEntryLink(att)
    end
end

-- ── Move/Copy picker window ───────────────────────────────────────────────────
local _pickerFrame  = nil

-- On the shared window shell (UI/ToolWindow.lua, CMP-02 S5). The title (set
-- in OpenPicker) carries the attachment's icon inline.
local function BuildPickerWindow()
    local f = BNB.CreateToolWindow({
        name = "BNBRefBoxMovePickerFrame", w = 320, h = 380, pad = 8,
        title = L["REFBOX_PICKER_TITLE"], toplevel = true, keyEsc = true,
        onDragStop = function() PositionModeStrip() end,
    })
    local top = f._isSkin and SK_RB_TITLE_H or TITLE_H

    -- Search above the list (ALL-276): filters the rows by title as you type,
    -- the rows are not rebuilt (OpenPicker's ApplyFilter only places them)
    local SEARCH_H = 22
    local sBg = BNB.CreateBackdropFrame("Frame", nil, f); BNB.SetBackdropDark(sBg)
    sBg:SetPoint("TOPLEFT",  f, "TOPLEFT",  8, -(top + 4))
    sBg:SetPoint("TOPRIGHT", f, "TOPRIGHT", -8, -(top + 4))
    sBg:SetHeight(SEARCH_H)
    local search = CreateFrame("EditBox", nil, sBg)
    search:SetAllPoints()
    search:SetTextInsets(6, 6, 0, 0)
    search:SetFontObject("BNBFontNormal"); search:SetAutoFocus(false); search:SetMaxLetters(64)
    BNB.AddPlaceholder(search, L["SEARCH_PLACEHOLDER"], 0.4, 0.4, 0.4)
    search:SetScript("OnEnterPressed",  function(self) self:ClearFocus() end)
    search:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    search:SetScript("OnTextChanged", function()
        if f._applyFilter then f._applyFilter() end
    end)
    f._search = search

    local sf = BNB.CreateScrollFrame(nil, f)
    sf:SetPoint("TOPLEFT",     f, "TOPLEFT",    1,           -(top + 4 + SEARCH_H + 6))
    sf:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -SCROLL_PAD, BOTTOM_PAD)

    if sf.ScrollBar then
        sf.ScrollBar:SetAlpha(0)
        sf:HookScript("OnScrollRangeChanged", function(_, _, yr)
            sf.ScrollBar:SetAlpha((yr or 0) > 1 and 1.0 or 0)
        end)
    end

    local sc = CreateFrame("Frame", nil, sf)
    sc:SetWidth(sf:GetWidth()); sc:SetHeight(1)
    sf:SetScrollChild(sc)
    sf:SetScript("OnSizeChanged", function(self) sc:SetWidth(self:GetWidth()) end)

    f._sf = sf; f._sc = sc
    return f
end

local function OpenPicker(anchorFrame, noteID, attIndex)
    if not _pickerFrame then _pickerFrame = BuildPickerWindow() end

    -- Update title bar: icon + name of the attachment being moved/copied
    local att = (NDB() and NDB().notes and NDB().notes[noteID]
        and NDB().notes[noteID].attachments
        and NDB().notes[noteID].attachments[attIndex])
    if att then
        -- Icon inline in the title, cropped like the old title icon (5..59 of 64)
        local data = ResolveAttachment(att)
        local icon = data and data.icon or "Interface\\Icons\\INV_Misc_QuestionMark"
        local text = data and string.format(L["REFBOX_PICKER_PREFIX"], data.name)
            or L["REFBOX_PICKER_TITLE"]
        _pickerFrame:SetWindowTitle("|T" .. tostring(icon) .. ":16:16:0:0:64:64:5:59:5:59|t " .. text)
    end

    local sc = _pickerFrame._sc
    -- Hide all old child frames
    for i = sc:GetNumChildren(), 1, -1 do
        local child = select(i, sc:GetChildren())
        if child then child:Hide() end
    end

    -- Notes sorted A-Z, excluding the current note
    local notes = BNB.GetOrderedNotes and
        BNB.GetOrderedNotes(nil, nil, false, true) or {}
    table.sort(notes, function(a, b)
        return (a.title or ""):lower() < (b.title or ""):lower()
    end)

    local ROW_H = 36
    local BTN_H = 26
    local BTN_W = 52
    local ICON_W = 20   -- note icon in each row
    local y = 0
    local rows = {}     -- { row, key = lower-case title } for the search (ALL-276)

    for _, entry in ipairs(notes) do
        if entry.id ~= noteID then
            local targetID = entry.id
            local title    = (entry.title ~= "" and entry.title) or L["HW_UNTITLED"]

            local row = CreateFrame("Frame", nil, sc)
            row:SetHeight(ROW_H)
            row:SetPoint("TOPLEFT",  sc, "TOPLEFT",  0, y)
            row:SetPoint("TOPRIGHT", sc, "TOPRIGHT", 0, y)

            -- Alternating tint, set again by ApplyFilter as rows move
            local rowBg = row:CreateTexture(nil, "BACKGROUND")
            rowBg:SetAllPoints()
            rowBg:SetColorTexture(1, 1, 1, 0.03)
            row._bg = rowBg
            rows[#rows + 1] = { row = row, key = title:lower() }

            -- Note icon
            local noteIcon = row:CreateTexture(nil, "ARTWORK")
            noteIcon:SetSize(ICON_W, ICON_W)
            noteIcon:SetPoint("LEFT",   row, "LEFT",   6, 0)
            noteIcon:SetPoint("CENTER", row, "CENTER", 0, 0)
            noteIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            if entry.icon then
                noteIcon:SetTexture(entry.icon)
            else
                noteIcon:SetTexture("Interface\\Icons\\INV_Misc_Note_01")
            end

            -- Title label
            local lbl = row:CreateFontString(nil, "OVERLAY", "BNBFontNormal")
            lbl:SetPoint("LEFT",   row, "LEFT",   ICON_W + 10, 0)
            lbl:SetPoint("RIGHT",  row, "RIGHT",  -(BTN_W * 2 + 10), 0)
            lbl:SetPoint("CENTER", row, "CENTER", 0, 0)
            lbl:SetJustifyH("LEFT")
            lbl:SetMaxLines(1); lbl:SetWordWrap(false)
            lbl:SetText(title)

            -- Move button
            local moveBtn = BNB.CreateButton(nil, row, L["REFBOX_PICKER_MOVE"], BTN_W, BTN_H)
            moveBtn:SetPoint("RIGHT",  row,     "RIGHT",  -(BTN_W + 6), 0)
            moveBtn:SetPoint("CENTER", row,     "CENTER", 0, 0)
            moveBtn:SetScript("OnClick", function()
                MoveAttachment(noteID, attIndex, targetID)
                _pickerFrame:Hide()
            end)
            moveBtn:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_TOP")
                GameTooltip:AddLine(string.format(L["REFBOX_MOVE_TO"], title), 1, 1, 1)
                GameTooltip:AddLine(L["REFBOX_MOVE_SUB"], 0.78, 0.78, 0.78)
                GameTooltip:Show()
            end)
            moveBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

            -- Copy button
            local copyBtn = BNB.CreateButton(nil, row, L["REFBOX_PICKER_COPY"], BTN_W, BTN_H)
            copyBtn:SetPoint("RIGHT",  row, "RIGHT",  -2, 0)
            copyBtn:SetPoint("CENTER", row, "CENTER",  0,  0)
            copyBtn:SetScript("OnClick", function()
                CopyAttachment(noteID, attIndex, targetID)
                _pickerFrame:Hide()
            end)
            copyBtn:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_TOP")
                GameTooltip:AddLine(string.format(L["REFBOX_COPY_TO"], title), 1, 1, 1)
                GameTooltip:AddLine(L["REFBOX_COPY_SUB"], 0.78, 0.78, 0.78)
                GameTooltip:Show()
            end)
            copyBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

            -- Row separator (hidden on the first shown row by ApplyFilter)
            local rowSep = row:CreateTexture(nil, "ARTWORK")
            rowSep:SetHeight(1); rowSep:SetColorTexture(0.20, 0.20, 0.22, 0.8)
            rowSep:SetPoint("TOPLEFT"); rowSep:SetPoint("TOPRIGHT")
            row._sep = rowSep

            y = y - ROW_H
        end
    end

    -- Places the rows whose title holds the search text, in order (ALL-276)
    local function ApplyFilter()
        local q = _pickerFrame._search and _pickerFrame._search:GetRealText() or ""
        q = q:lower():match("^%s*(.-)%s*$")
        local n = 0
        for _, r in ipairs(rows) do
            local show = q == "" or r.key:find(q, 1, true) ~= nil
            r.row:SetShown(show)
            if show then
                r.row:ClearAllPoints()
                r.row:SetPoint("TOPLEFT",  sc, "TOPLEFT",  0, -n * ROW_H)
                r.row:SetPoint("TOPRIGHT", sc, "TOPRIGHT", 0, -n * ROW_H)
                r.row._bg:SetShown(n % 2 == 1)
                r.row._sep:SetShown(n > 0)
                n = n + 1
            end
        end
        sc:SetHeight(math.max(n * ROW_H, _pickerFrame._sf:GetHeight()))
        _pickerFrame._sf:SetVerticalScroll(0)
    end
    _pickerFrame._applyFilter = ApplyFilter
    if _pickerFrame._search then _pickerFrame._search:SetRealText("") end
    ApplyFilter()

    -- Centre on the RefBox frame
    _pickerFrame:ClearAllPoints()
    if rbFrame and rbFrame:IsShown() then
        _pickerFrame:SetPoint("CENTER", rbFrame, "CENTER", 0, 0)
    else
        _pickerFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    end
    _pickerFrame:Show()
    _pickerFrame:Raise()
end

-- ── Context menu (BNB.ContextMenu, ALL-148) ──────────────────────────────────
local function OpenContextMenu(anchorRow, noteID, attIndex)
    BNB.ContextMenu.Open(anchorRow, function(root)
        root:CreateButton(L["REFBOX_CTX_SEND"], function()
            local note = NDB() and NDB().notes and NDB().notes[noteID]
            local att2 = note and note.attachments and note.attachments[attIndex]
            if att2 then SendAttachmentToChat(att2) end
        end)
        root:CreateButton(L["REFBOX_CTX_INSERT"], function()
            local note = NDB() and NDB().notes and NDB().notes[noteID]
            local att2 = note and note.attachments and note.attachments[attIndex]
            if att2 then InsertAttachmentIntoNote(att2, noteID) end
        end)
        root:CreateButton(L["REFBOX_CTX_WOWHEAD"], function()
            local note = NDB() and NDB().notes and NDB().notes[noteID]
            local att2 = note and note.attachments and note.attachments[attIndex]
            if not att2 then return end
            local url = BuildWowheadURL(att2)
            if url then BNB.ShowClipboardHint(url, nil, nil, true) end
        end)
        -- Dressing room — items only
        local noteCheck = NDB() and NDB().notes and NDB().notes[noteID]
        local attCheck  = noteCheck and noteCheck.attachments and noteCheck.attachments[attIndex]
        if attCheck and attCheck.type == "item" then
            root:CreateButton(L["REFBOX_CTX_DRESSUP"], function()
                local note2 = NDB() and NDB().notes and NDB().notes[noteID]
                local att2  = note2 and note2.attachments and note2.attachments[attIndex]
                if not att2 then return end
                local _, link = C_Item.GetItemInfo(att2.id)
                if link then DressUpItemLink(link) end
            end)
        end
        -- Show model, beside the dressing room (ALL-206): only for entries
        -- the viewer can draw
        if attCheck and ModelSpec(attCheck) then
            root:CreateButton(L["REFBOX_CTX_SHOW_MODEL"], function()
                local note2 = NDB() and NDB().notes and NDB().notes[noteID]
                local att2  = note2 and note2.attachments and note2.attachments[attIndex]
                if att2 then ShowInViewer(att2) end
            end)
        end
        root:CreateButton(L["REFBOX_CTX_MOVE_COPY"], function()
            local note = NDB() and NDB().notes and NDB().notes[noteID]
            local att2 = note and note.attachments and note.attachments[attIndex]
            if att2 then OpenPicker(anchorRow, noteID, attIndex) end
        end)
        root:CreateDivider()
        root:CreateButton(L["REFBOX_CTX_REMOVE"], function()
            RemoveAttachment(noteID, attIndex)
        end, { danger = true })   -- irreversible = red (Dukul)
    end)
end

local function OpenGearContextMenu(anchorRow, noteID, gearEntry, listRef, listIdx)
    BNB.ContextMenu.Open(anchorRow, function(root)
        -- Send to chat
        root:CreateButton(L["REFBOX_CTX_SEND"], function()
            local att = {type = "item", id = gearEntry.id}
            SendAttachmentToChat(att)
        end)

        -- Insert at text cursor — greyed out in rich note view mode
        root:CreateButton(L["REFBOX_CTX_INSERT"], function()
            local att = {type = "item", id = gearEntry.id}
            InsertAttachmentIntoNote(att, noteID)
        end, { disabled = BNB._editorInViewMode == true })

        -- Copy Wowhead URL
        root:CreateButton(L["REFBOX_CTX_WOWHEAD"], function()
            local att = {type = "item", id = gearEntry.id}
            local url = BuildWowheadURL(att)
            if url then BNB.ShowClipboardHint(url, nil, nil, true) end
        end)

        -- Show model (ALL-206) and the dressing room; a transmog card's own
        -- appearance (appearanceID there is the transmog source)
        local gearAtt = { type = "item", id = gearEntry.id, sourceID = gearEntry.appearanceID }

        -- Try in dressing room
        root:CreateButton(L["REFBOX_CTX_DRESSUP"], function()
            DressUpEntry(gearAtt)
        end)
        if ModelSpec(gearAtt) then
            root:CreateButton(L["REFBOX_CTX_SHOW_MODEL"], function()
                ShowInViewer(gearAtt)
            end)
        end

        root:CreateDivider()

        -- Remove from gear list
        root:CreateButton(L["REFBOX_CTX_REMOVE"], function()
            if listRef and listIdx then
                table.remove(listRef, listIdx)
                BNB.UpdateNote(noteID, {})
                RenderList()
            end
        end, { danger = true })
    end)
end

-- ── Shift-click hook (Baganator-safe) ────────────────────────────────────────
local _shiftHookInstalled = false
local _lastAddedLink = nil

local function TryAddLink(link)
    if _suppressShiftHook then return end
    if not rbFrame or not rbFrame:IsShown() or not RBOn() then return end
    if not IsShiftKeyDown() then return end
    if not _noteID then return end
    if not link or link == "" then return end
    if _lastAddedLink == link then return end

    local itemID  = link:match("item:(%d+)")
    local spellID = link:match("spell:(%d+)")
    local questID = link:match("quest:(%d+)")
    if itemID then
        _lastAddedLink = link
        C_Timer.After(0.1, function() _lastAddedLink = nil end)
        AddAttachment(_noteID, { type="item",  id=tonumber(itemID)  })
    elseif spellID then
        _lastAddedLink = link
        C_Timer.After(0.1, function() _lastAddedLink = nil end)
        AddAttachment(_noteID, { type="spell", id=tonumber(spellID) })
    elseif questID then
        _lastAddedLink = link
        C_Timer.After(0.1, function() _lastAddedLink = nil end)
        AddAttachment(_noteID, { type="quest", id=tonumber(questID) })
    end
end

local function InstallShiftHooks()
    if _shiftHookInstalled then return end
    _shiftHookInstalled = true
    hooksecurefunc("ChatEdit_InsertLink", function(link) TryAddLink(link) end)
    -- 12.x chat code goes through ChatFrameUtil.InsertLink (on Retail and
    -- Forever per the API dumps), which may not pass the old global (DEP-02).
    -- TryAddLink drops the same link twice in a row, so both hooks are safe.
    if ChatFrameUtil and ChatFrameUtil.InsertLink then
        hooksecurefunc(ChatFrameUtil, "InsertLink", function(link) TryAddLink(link) end)
    end
    if HandleModifiedItemClick then
        hooksecurefunc("HandleModifiedItemClick", function(link) TryAddLink(link) end)
    end
end

-- ── Manual entry — prefix syntax ──────────────────────────────────────────────
-- s:N or spell:N → spell
-- i:N or item:N  → item
-- bare number    → item (default)
-- item/spell link pasted → parsed automatically
local function ParseManualEntry(text)
    if not text or text == "" then return nil end
    text = text:match("^%s*(.-)%s*$")

    -- Wowhead URL: https://www.wowhead.com/item=2529/zweihander
    --              https://www.wowhead.com/quest=93932/legendary-prosperity
    --              https://www.wowhead.com/spell=7328/redemption
    -- Any client's path too (wowhead.com/forever/item=..., ALL-151)
    local whType, whID, whSlug = text:match("wowhead%.com/[%w%-]+/([a-z]+)=(%d+)/?([^%s]*)")
    if not whType then
        whType, whID, whSlug = text:match("wowhead%.com/([a-z]+)=(%d+)/?([^%s]*)")
    end
    if whType and whID then
        local id = tonumber(whID)
        if whType == "item"  then return "item",  id end
        if whType == "spell" then return "spell", id end
        if whType == "quest" then
            -- Extract human-readable title from slug (replace hyphens with spaces, title-case)
            local title = nil
            if whSlug and whSlug ~= "" then
                title = whSlug:gsub("-", " "):gsub("(%a)([%w_']*)", function(a, b)
                    return a:upper() .. b:lower()
                end)
            end
            return "quest", id, title  -- third return: title hint
        end
    end

    -- Hyperlink pasted (item:N:... or spell:N or quest:N)
    local itemLink  = text:match("item:(%d+)")
    local spellLink = text:match("spell:(%d+)")
    local questLink = text:match("quest:(%d+)")
    if itemLink  then return "item",  tonumber(itemLink)  end
    if spellLink then return "spell", tonumber(spellLink) end
    if questLink then return "quest", tonumber(questLink) end

    -- Prefix syntax
    local spellPfx = text:match("^[Ss]:(%d+)$") or text:match("^[Ss]pell:(%d+)$")
    if spellPfx then return "spell", tonumber(spellPfx) end
    local itemPfx  = text:match("^[Ii]:(%d+)$") or text:match("^[Ii]tem:(%d+)$")
    if itemPfx  then return "item",  tonumber(itemPfx)  end
    local questPfx = text:match("^[Qq]:(%d+)$") or text:match("^[Qq]uest:(%d+)$")
    if questPfx then return "quest", tonumber(questPfx) end

    -- Bare number → item
    local num = tonumber(text)
    if num then return "item", num end

    return nil, nil
end

local function CommitManualEntry(text)
    if not _noteID or not text or text == "" then return end
    local attType, id, titleHint = ParseManualEntry(text)
    if attType and id then
        local att = { type=attType, id=id }
        if titleHint then att.title = titleHint end
        AddAttachment(_noteID, att)
    else
        BNB:Print(string.format(L["REFBOX_RESOLVE_MANUAL"], text))
    end
end

-- ── Row pool ──────────────────────────────────────────────────────────────────
local function ReleaseAllRows()
    for _, row in ipairs(_activeRows) do
        row:Hide()
        -- Clear gear-row state so pooled rows don't carry stale flags.
        row._gearSlot  = nil
        row._gearSlotIdx = nil
        row._isGearRow = nil
        row._isTmog    = nil
        table.insert(_rowPool, row)
    end
    _activeRows = {}
    -- Hide gear section headers from previous render.
    local sc = rbFrame and rbFrame._scrollChild
    if sc and sc._activeGearHdrs then
        for _, hdr in ipairs(sc._activeGearHdrs) do
            hdr:Hide()
            sc._gearHdrs = sc._gearHdrs or {}
            table.insert(sc._gearHdrs, hdr)
        end
        sc._activeGearHdrs = {}
    end
end

local function AcquireRow(parent)
    local row = table.remove(_rowPool)
    if row then row:SetParent(parent); row:ClearAllPoints(); return row end

    row = BNB.CreateBackdropFrame("Button", nil, parent)
    row:EnableMouse(true)
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    local icon = row:CreateTexture(nil, "ARTWORK")
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    row._icon = icon

    local iconBorder = row:CreateTexture(nil, "OVERLAY")
    iconBorder:SetTexture("Interface\\Common\\WhiteIconFrame")
    row._iconBorder = iconBorder

    local typeLabel = row:CreateFontString(nil, "OVERLAY", "BNBFontNormalSmall")
    typeLabel:SetJustifyH("LEFT"); typeLabel:SetTextColor(0.55, 0.55, 0.60)
    row._typeLabel = typeLabel

    local nameLabel = row:CreateFontString(nil, "OVERLAY", "BNBFontNormal")
    nameLabel:SetJustifyH("LEFT"); nameLabel:SetWordWrap(false); nameLabel:SetMaxLines(1)
    row._nameLabel = nameLabel

    local pendingLabel = row:CreateFontString(nil, "OVERLAY", "BNBFontNormalSmall")
    pendingLabel:SetJustifyH("LEFT"); pendingLabel:SetTextColor(0.45, 0.45, 0.50)
    pendingLabel:SetText(L["REFBOX_LOADING"]); pendingLabel:Hide()
    row._pendingLabel = pendingLabel

    -- Slot label: shown on gear cards (normal mode = top-right; compact = right-aligned).
    local slotLabel = row:CreateFontString(nil, "OVERLAY", "BNBFontNormalSmall")
    slotLabel:SetJustifyH("RIGHT"); slotLabel:SetTextColor(0.55, 0.55, 0.60)
    slotLabel:Hide()
    row._slotLabel = slotLabel

    -- Transmog watermark texture: right-side, low alpha, transmog cards only.
    local wmTex = row:CreateTexture(nil, "BACKGROUND")
    wmTex:SetTexture(ASSETS .. "UI\\ui-transmog")
    wmTex:Hide()
    row._wmTex = wmTex

    -- X remove button, shown while the row is hovered. Normal mode: the
    -- UIPanelCloseButton X; skin mode: the skin close icon button, like every
    -- skin window's X (Dukul 2026-10-03). The icon button owns its OnEnter /
    -- OnLeave, so the alpha goes on with HookScript.
    local xBtn
    if BigNoteBoxDB and BigNoteBoxDB.skinMode then
        xBtn = BNB.CreateIconButton(row, 16, "close", { skin = true })
    else
        xBtn = CreateFrame("Button", nil, row, "UIPanelCloseButton")
        xBtn:SetSize(16, 16)
    end
    xBtn:SetPoint("TOPRIGHT", row, "TOPRIGHT", -2, -2)
    xBtn:SetFrameLevel(row:GetFrameLevel() + 5)
    xBtn:SetAlpha(0)
    xBtn:EnableMouse(true)
    xBtn:HookScript("OnEnter", function(self) self:SetAlpha(1) end)
    xBtn:HookScript("OnLeave", function(self)
        if not row:IsMouseOver() then self:SetAlpha(0) end
    end)
    row._xBtn = xBtn

    -- Lock in the X's place on a locked note: says why it cannot be removed
    local lockTex = row:CreateTexture(nil, "OVERLAY")
    lockTex:SetSize(12, 12)
    lockTex:SetPoint("CENTER", xBtn, "CENTER", 0, 0)
    lockTex:SetTexture(ASSETS .. BNB.AbIcon("lock"))
    lockTex:SetAlpha(0.65)
    lockTex:Hide()
    row._lockTex = lockTex

    row:SetScript("OnEnter", function(self)
        local qr = self._qr or 0; local qg = self._qg or 0; local qb = self._qb or 0
        self:SetBackdropColor(qr*0.20+0.06, qg*0.20+0.06, qb*0.20+0.08, 0.90)
        -- No X on a row that cannot be removed (it showed, but did not work)
        if not self._noX then xBtn:SetAlpha(1) end
        if self._att then ShowTooltip(self, self._att) end
    end)
    row:SetScript("OnLeave", function(self)
        local qr = self._qr or 0; local qg = self._qg or 0; local qb = self._qb or 0
        self:SetBackdropColor(qr*0.08, qg*0.08, qb*0.08, 0.55)
        xBtn:SetAlpha(0); GameTooltip:Hide()
    end)
    return row
end

local function SetupRow(row, att, data, index, compact, locked)
    row._att = att; row._index = index

    local iconSz   = compact and ICON_SZ_C or ICON_SZ_N
    local rowH     = compact and ROW_H_COMP or ROW_H_NORM
    local textLeft = CARD_PAD + iconSz + 8

    row:SetHeight(rowH)
    row._icon:SetSize(iconSz, iconSz)
    row._iconBorder:SetSize(iconSz+2, iconSz+2)
    row._icon:SetPoint("LEFT", row, "LEFT", CARD_PAD, 0)
    row._iconBorder:SetPoint("CENTER", row._icon, "CENTER", 0, 0)

    row._typeLabel:ClearAllPoints()
    row._nameLabel:ClearAllPoints()
    row._pendingLabel:ClearAllPoints()
    if row._slotLabel then row._slotLabel:ClearAllPoints() end

    -- isGearRow: gear card from inspectGearItems / inspectTransmogItems.
    local isGearRow = row._isGearRow
    local isTmog    = row._isTmog
    -- Translated name from the slot id first; notes saved before ALL-72 stored English
    local slotText  = (row._gearSlotIdx and BNB.InspectSlotLabel and BNB.InspectSlotLabel(row._gearSlotIdx))
                      or row._gearSlot or ""

    -- Compact: slot right-aligned; name constrained to avoid overlap.
    -- Normal:  type label = "Transmog: Head" or "Regular: Head"; name below.
    local SLOT_W = 50  -- reserved width for slot label in compact mode

    if compact then
        row._typeLabel:Hide()
        local vOff = -math.floor((rowH - 14) / 2)
        if isGearRow and row._slotLabel and slotText ~= "" then
            -- In compact mode the watermark sits at -5 from RIGHT (24px wide).
            -- Slot label goes to the left of it; name label stops before slot label.
            local wmClearance = isTmog and (5 + (rowH - 4) + 4) or 20
            row._slotLabel:SetPoint("RIGHT", row, "RIGHT", -wmClearance, 0)
            row._slotLabel:SetPoint("TOP",   row, "TOP",   0, vOff)
            row._slotLabel:SetText(slotText)
            row._slotLabel:Show()
            row._nameLabel:SetPoint("LEFT",  row, "LEFT",  textLeft, 0)
            row._nameLabel:SetPoint("RIGHT", row, "RIGHT", -(wmClearance + SLOT_W), 0)
            row._nameLabel:SetPoint("TOP",   row, "TOP",   0, vOff)
        else
            if row._slotLabel then row._slotLabel:Hide() end
            row._nameLabel:SetPoint("LEFT",  row, "LEFT",  textLeft, 0)
            row._nameLabel:SetPoint("RIGHT", row, "RIGHT", -20, 0)
            row._nameLabel:SetPoint("TOP",   row, "TOP",   0, vOff)
        end
        row._pendingLabel:SetPoint("LEFT", row, "LEFT", textLeft, 0)
        row._pendingLabel:SetPoint("TOP",  row, "TOP",  0, vOff)
    else
        if row._slotLabel then row._slotLabel:Hide() end
        row._typeLabel:Show()
        row._typeLabel:SetPoint("TOPLEFT",  row, "TOPLEFT",  textLeft, -8)
        row._typeLabel:SetPoint("TOPRIGHT", row, "TOPRIGHT", -20, -8)
        row._nameLabel:SetPoint("TOPLEFT",  row, "TOPLEFT",  textLeft, -22)
        row._nameLabel:SetPoint("TOPRIGHT", row, "TOPRIGHT", -20, -22)
        row._pendingLabel:SetPoint("TOPLEFT",  row, "TOPLEFT",  textLeft, -22)
        row._pendingLabel:SetPoint("TOPRIGHT", row, "TOPRIGHT", -20, -22)
    end

    -- Locked rows keep their colour: the lock icon in the X's place says it
    -- all (ALL-195, Dukul 2026-10-02). Reset, since rows are pooled.
    pcall(function() row._icon:SetDesaturated(false) end)
    row._icon:SetAlpha(1.0)
    row._iconBorder:SetAlpha(1.0)
    row._nameLabel:SetAlpha(1.0)
    row._typeLabel:SetAlpha(1.0)
    -- Locked rows: no X (can't remove), the lock icon in its place
    row._xBtn:SetAlpha(0)
    row._xBtn:EnableMouse(not locked)
    row._noX = locked or nil
    row._lockTex:SetShown(locked or false)

    if data then
        local qr, qg, qb = data.qr, data.qg, data.qb
        row._qr, row._qg, row._qb = qr, qg, qb
        row._icon:SetTexture(data.icon)
        row._iconBorder:SetVertexColor(qr, qg, qb, 1)
        BNB.SetBackdrop(row, qr*0.08, qg*0.08, qb*0.08, 0.55, qr*0.50, qg*0.50, qb*0.50, 0.85)
        row._nameLabel:SetText(data.name)
        row._nameLabel:SetTextColor(qr, qg, qb, 1)
        if not compact then
            -- Gear rows: type label = "Transmog: Slot" or "Regular: Slot"
            if isGearRow and slotText ~= "" then
                local prefix = isTmog and L["REFBOX_GEAR_TYPE_TMOG"] or L["REFBOX_GEAR_TYPE_REG"]
                row._typeLabel:SetText(prefix .. ": " .. slotText)
            else
                row._typeLabel:SetText(data.typeLabel)
            end
        end
        row._nameLabel:Show(); row._pendingLabel:Hide()
    else
        row._qr, row._qg, row._qb = 0, 0, 0
        row._icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
        row._iconBorder:SetVertexColor(0.40, 0.40, 0.40, 1)
        BNB.SetBackdrop(row, 0.07, 0.07, 0.09, 0.55, 0.22, 0.22, 0.26, 0.85)
        row._nameLabel:SetText("")
        if not compact then
            if isGearRow and slotText ~= "" then
                local prefix = isTmog and L["REFBOX_GEAR_TYPE_TMOG"] or L["REFBOX_GEAR_TYPE_REG"]
                row._typeLabel:SetText(prefix .. ": " .. slotText)
            else
                local typeLabel = att.type == "spell" and L["REFBOX_TYPE_SPELL"]
                    or att.type == "quest" and L["REFBOX_TYPE_QUEST"]
                    or L["REFBOX_TYPE_GEAR"]
                row._typeLabel:SetText(typeLabel)
            end
        end
        row._nameLabel:Hide(); row._pendingLabel:Show()
    end

    -- Watermark: show on transmog gear rows only.
    -- Size clamped to row height so it never overflows in compact mode.
    -- Right-aligned with enough clearance to avoid the slot label and X button.
    if row._wmTex then
        if isGearRow and isTmog then
            local wmSz = math.min(rowH - 4, 32)
            row._wmTex:ClearAllPoints()
            row._wmTex:SetSize(wmSz, wmSz)
            row._wmTex:SetPoint("RIGHT", row, "RIGHT", -5, 0)
            row._wmTex:SetAlpha(0.70)
            row._wmTex:Show()
        else
            row._wmTex:Hide()
        end
    end
end

-- ── Drag-and-drop ─────────────────────────────────────────────────────────────
local function WireDragDrop(frame)
    frame:SetScript("OnReceiveDrag", function()
        if not _noteID or not RBOn() then return end
        -- On retail TWW/Midnight, GetCursorInfo for a spellbook drag returns:
        --   "spell", slotIndex, bookType, spellID
        -- The 4th return is the actual spellID; arg2 is the slot index.
        local cursorType, id, _, spellIDArg = GetCursorInfo()
        if cursorType == "item" then
            ClearCursor(); AddAttachment(_noteID, {type="item",  id=id})
        elseif cursorType == "spell" then
            local spellID = spellIDArg or id
            ClearCursor(); AddAttachment(_noteID, {type="spell", id=spellID})
        end
    end)
    frame:SetScript("OnMouseDown", function(self, btn)
        if btn == "LeftButton" then
            local ct = GetCursorInfo()
            if ct and ct ~= "" then self:GetScript("OnReceiveDrag")(self) end
        end
    end)
end

-- ── Core render ───────────────────────────────────────────────────────────────
RenderList = function()
    if not rbFrame or not rbFrame:IsShown() then return end

    local sc         = rbFrame._scrollChild
    local emptyLabel = rbFrame._emptyLabel
    local countLabel = rbFrame._countLabel
    local addBtn     = rbFrame._addBtn
    local manualBox  = rbFrame._manualBox

    ReleaseAllRows()

    -- Without the Reference part only the model's gear list is drawn (ALL-388)
    local refOn       = RBOn()
    local attachments = refOn and GetAttachments(_noteID) or {}
    local count       = #attachments
    local maxItems    = GetMaxItems()
    local modelVisible = HasModel(_noteID) and not (_noteID and _modelHidden[_noteID])
    local compact     = IsCompact() or modelVisible  -- compact when model viewer is shown
    local locked      = IsLocked(_noteID)

    countLabel:SetText(string.format(L["REFBOX_COUNT"], count, maxItems))

    -- Lock state on add controls
    if addBtn then
        addBtn:SetEnabled(not locked)
        addBtn:SetAlpha(locked and 0.4 or 1.0)
        pcall(function() addBtn._tx:SetDesaturated(locked) end)
    end
    if manualBox then
        manualBox:SetEnabled(not locked)
        manualBox:SetAlpha(locked and 0.4 or 1.0)
    end

    if count == 0 and refOn then emptyLabel:Show() else emptyLabel:Hide() end

    local y = 0
    for i, att in ipairs(attachments) do
        local data = ResolveAttachment(att)
        local row  = AcquireRow(sc)
        row:SetPoint("TOPLEFT",  sc, "TOPLEFT",  PAD, y)
        row:SetPoint("TOPRIGHT", sc, "TOPRIGHT", -PAD, y)
        SetupRow(row, att, data, i, compact, locked)

        local idx  = i
        local att2 = att   -- capture for closures

        -- Subject cards (npc/player pseudo-attachments) are not interactive
        local isSubject = data and data.isSubject

        -- Left-click: model viewer or link window, Shift = chat, Ctrl = dressing
        -- room (OnEntryClick, ALL-206)
        if not isSubject then
            row:SetScript("OnClick", function(self, btn)
                if btn == "LeftButton" then OnEntryClick(att2) end
            end)
        else
            row:SetScript("OnClick", nil)
        end

        if not locked and not isSubject then
            row._xBtn:SetScript("OnClick", function() RemoveAttachment(_noteID, idx) end)
            row:SetScript("OnMouseUp", function(self, btn)
                if btn == "RightButton" then OpenContextMenu(self, _noteID, idx) end
            end)
        else
            row._xBtn:SetScript("OnClick", nil)
            row:SetScript("OnMouseUp", nil)
        end

        -- Subject cards never show the X button
        if isSubject then
            row._xBtn:SetAlpha(0)
            row._xBtn:EnableMouse(false)
            row._noX = true
            row._lockTex:Hide()
        end

        row:Show()
        table.insert(_activeRows, row)
        y = y - (compact and ROW_H_COMP or ROW_H_NORM) - ROW_GAP
    end

    -- ── Inspect gear sections (Transmog gear / Regular gear) ─────────────────
    -- These lists live on the note separately from note.attachments and do not
    -- count toward refboxMaxItems. They only appear for inspect notes.
    -- When attachments are empty the empty label sits at y=0 in the scroll child
    -- (~48px tall). Advance y to clear it so gear headers don't overlap.
    if count == 0 and refOn then y = y - 48 end
    local note = _noteID and BNB.GetNote(_noteID)
    if note and note.source == "inspect" and _rbMode == "model" then
        local gearShow    = (BigNoteBoxDB and BigNoteBoxDB.inspectNoteGearShow) or BNB.DEFAULTS.inspectNoteGearShow
        local tmogItems   = note.inspectTransmogItems
        local regItems    = note.inspectGearItems
        local showTmog    = (gearShow == "both" or gearShow == "transmog") and tmogItems and #tmogItems > 0
        local showReg     = (gearShow == "both" or gearShow == "regular")  and regItems  and #regItems  > 0
        -- No transmog on the player: every transmog card is the item worn in
        -- that slot, so the regular list alone is shown (FOR-26). The lists
        -- differ in length anyway (rings, trinkets, neck have no transmog).
        if showTmog and showReg then
            local worn = {}
            for _, g in ipairs(regItems) do worn[g.slotIdx or g.slot or 0] = g.id end
            local same = true
            for _, g in ipairs(tmogItems) do
                if worn[g.slotIdx or g.slot or 0] ~= g.id then same = false; break end
            end
            if same then showTmog = false end
        end

        -- Helper: renders a section title at current y, returns new y. A
        -- right-click copies every Wowhead link of the section (ALL-167,
        -- per client through BNB.WowheadURL); the title is the size of the
        -- Attachments line, without the "-- --" around it.
        local function RenderGearHeader(text, items)
            if not sc._gearHdrs then sc._gearHdrs = {} end
            local hdr = table.remove(sc._gearHdrs)
            if not hdr then
                hdr = CreateFrame("Button", nil, sc)
                hdr:SetHeight(20)
                hdr.fs = hdr:CreateFontString(nil, "OVERLAY", "BNBFontNormal")
                hdr.fs:SetAllPoints(); hdr.fs:SetJustifyH("LEFT")
                hdr:RegisterForClicks("RightButtonUp")
                hdr:SetScript("OnClick", function(self)
                    if self._links and self._links ~= "" then BNB.ShowClipboardHint(self._links, self) end
                end)
                hdr:SetScript("OnEnter", function(self)
                    GameTooltip:SetOwner(self, "ANCHOR_TOP")
                    GameTooltip:AddLine(L["REFBOX_GEAR_COPY_LINKS_TIP"], 1, 1, 1)
                    GameTooltip:Show()
                end)
                hdr:SetScript("OnLeave", function() GameTooltip:Hide() end)
            end
            local links = {}
            for _, g in ipairs(items or {}) do
                local url = g.id and BNB.WowheadURL("item", g.id)
                if url then links[#links + 1] = url end
            end
            hdr._links = table.concat(links, "\n")
            hdr:ClearAllPoints()
            hdr:SetPoint("TOPLEFT",  sc, "TOPLEFT",  PAD, y)
            hdr:SetPoint("TOPRIGHT", sc, "TOPRIGHT", -PAD, y)
            hdr.fs:SetText(text)
            hdr:Show()
            -- Store so ReleaseAllRows can hide them next render.
            sc._activeGearHdrs = sc._activeGearHdrs or {}
            table.insert(sc._activeGearHdrs, hdr)
            return y - 22
        end

        -- Helper: renders one gear card row. isTmog controls watermark + type label.
        local function RenderGearRow(gearEntry, listRef, listIdx, isTmog)
            -- sourceID: transmog cards show their exact appearance in the viewer
            local att = { type = "item", id = gearEntry.id, sourceID = isTmog and gearEntry.appearanceID or nil }
            local data = ResolveAttachment(att)
            local row = AcquireRow(sc)
            row:SetPoint("TOPLEFT",  sc, "TOPLEFT",  PAD, y)
            row:SetPoint("TOPRIGHT", sc, "TOPRIGHT", -PAD, y)
            -- Pass slot label and transmog flag through the row for SetupRow.
            row._gearSlot  = gearEntry.slot
            row._gearSlotIdx = gearEntry.slotIdx
            row._isGearRow = true
            row._isTmog    = isTmog
            SetupRow(row, att, data, nil, compact, false)

            local capList = listRef
            local capIdx  = listIdx

            -- Same clicks as an attachment (ALL-206): plain = this piece in the viewer
            row:SetScript("OnClick", function(self, btn)
                if btn == "LeftButton" then OnEntryClick(att) end
            end)
            row:SetScript("OnMouseUp", function(self, btn)
                if btn == "RightButton" then
                    OpenGearContextMenu(self, _noteID, gearEntry, capList, capIdx)
                end
            end)
            row._xBtn:SetScript("OnClick", function()
                if capList and capIdx then
                    table.remove(capList, capIdx)
                    -- Persist: update note directly then re-render.
                    BNB.UpdateNote(_noteID, {})  -- touch note to trigger save
                    RenderList()
                end
            end)
            row._xBtn:EnableMouse(true)

            row:Show()
            table.insert(_activeRows, row)
            return y - (compact and ROW_H_COMP or ROW_H_NORM) - ROW_GAP
        end

        if showTmog then
            y = RenderGearHeader(L["REFBOX_GEAR_HEADER_TMOG"], tmogItems)
            for i, g in ipairs(tmogItems) do
                y = RenderGearRow(g, tmogItems, i, true)
            end
        end
        if showReg then
            y = RenderGearHeader(L["REFBOX_GEAR_HEADER_REG"], regItems)
            for i, g in ipairs(regItems) do
                y = RenderGearRow(g, regItems, i, false)
            end
        end
    end

    local sf = rbFrame._scrollFrame
    -- Content height is kept so the child follows later window resizes
    -- (OnSizeChanged below): sized to the scroll frame as it was here, then
    -- left taller once the window shrank, it showed a scrollbar with nothing
    -- to scroll (ALL-138)
    sc._contentH = math.abs(y)
    sc:SetHeight(math.max(sc._contentH, sf:GetHeight()))

    -- Resize the window to fit content (clamped to main window height)
    SyncRefBoxHeight()

    -- Render task panel and reposition layout panes.
    -- Apply layout immediately so attachment rows don't overflow into the task
    -- panel, then apply again one tick later once rbFrame:GetHeight() has settled.
    if K.RenderTaskPanel then K.RenderTaskPanel() end
    K.ApplyTaskLayout(rbFrame)
    UpdateDynamicTitle()
    C_Timer.After(0, function()
        if rbFrame and rbFrame:IsShown() then
            K.ApplyTaskLayout(rbFrame)
            UpdateDynamicTitle()
            UpdateModelViewer()
        end
    end)
    -- Second delayed pass — on first open the frame geometry may not have
    -- settled after one tick, leaving the task panel transparent until the
    -- splitter is moved. This ensures the layout (and thus the opaque
    -- ButtonFrameTemplate chrome behind the task area) is correct.
    C_Timer.After(0.05, function()
        if rbFrame and rbFrame:IsShown() then
            K.ApplyTaskLayout(rbFrame)
            UpdateModelViewer()
            -- Force the task panel to re-composite so the ButtonFrameTemplate
            -- NineSlice chrome paints through its transparent background.
            -- Without this, the task panel appears transparent over attachment
            -- cards until the splitter is dragged (which triggers the same
            -- geometry pass via SetHeight).
            -- ApplyTaskLayout does the Show, and only when there are tasks to
            -- show (a bare Show re-showed a panel emptied in between, ALL-76).
            -- An inline task edit survives the Hide/Show.
            K.RecompositeTaskPanel()
        end
    end)
end

-- ── External Model/Tasks toggle strip ────────────────────────────────────────
-- Sits BELOW the RefBox frame, outside it. Only shown for inspect/target notes.
-- Mirrors the Editor/View tab strip pattern from NoteEditor.lua.
local _modeStrip = nil   -- the external strip frame

local function OnModeClick(mode)
    _rbMode = mode
    if rbFrame then
        K.RenderTaskPanel()
        K.ApplyTaskLayout(rbFrame)
        UpdateModelViewer()
        UpdateDynamicTitle()
        UpdateModeStrip()
    end
end

-- ── Model/Tasks side tabs (FOR-21) ───────────────────────────────────────────
-- Normal mode swaps the text strip for two icon tabs on the Reference
-- box's outer edge (left when docked left of the main window, right when docked
-- right), in the sidebar's border/hover/active art at 48px instead of 64.
-- Tasks sits at the bottom, its bottom edge level with the model viewer's gear
-- button (model bottom BOTTOM_PAD + that button's 4px inset); Model above it.
-- Built on Forever, extended to Retail 2026-09-24, then skin mode 2026-09-26 (ALL-88).
local TAB_SZ     = 48                          -- sidebar BTN_SZ 64, scaled 0.75
local TAB_ICON   = 36                          -- sidebar ICON_SZ 48, scaled
local TAB_ICON_X = { left = 8, right = 4 }     -- sidebar 10 / 5, scaled
local TAB_ICON_Y = -6                          -- sidebar -8, scaled
local TAB_GAP    = 1                           -- sidebar GAP
-- Edge offset against the frame, per side and client: the sidebar's values
-- (Sidebar.lua SIDE_OFFSET, FOR-15 on Forever; its 2 / -2 default on Retail),
-- scaled. On Forever the right side draws below the frame, as the sidebar does.
local TAB_OFF    = BNB.IsForever and { left = 5, right = -2 } or { left = 8, right = -4 }
-- Skin mode: the tabs sit this much further out from the frame, their inner end
-- under the window edge (Dukul 2026-10-03: "a tiny bit to the left"). Tune here.
local TAB_SKIN_OUT = 2
local TAB_BORDER = ASSETS .. (BNB.IsForever and "Sidebar\\sb-border-forever" or "Sidebar\\sb-border")
local TAB_BOTTOM = BOTTOM_PAD + 4
local TAB_TASK_ICON = "Interface\\Icons\\INV_Misc_Note_03"
local TAB_FALLBACK  = "Interface\\Icons\\INV_Misc_QuestionMark"
local ACTIVE_R, ACTIVE_G, ACTIVE_B = 0.40, 0.85, 0.40   -- Sidebar.lua ACTIVE_R/G/B
local ACTIVE_GLOW_MULT = 2.0                             -- Sidebar.lua ACTIVE_GLOW_MULT

local function UseSideTabs()
    return true
end

-- Outer edge: away from the main window, so the tabs never cover it
local function SideTabSide()
    local side = (BigNoteBoxDB and BigNoteBoxDB.refboxSide) or BNB.DEFAULTS.refboxSide
    if not (BNB.mainFrame and BNB.mainFrame:IsShown()) then side = "left" end
    return side
end

-- Same orientations as Sidebar.lua SidebarTexCoord (6 = left, 4 = right)
local function SideTabTexCoord(side)
    if side == "left" then return 1,0, 1,1, 0,0, 0,1 end
    return 0,1, 0,0, 1,1, 1,0
end

-- Model tab icon: the player's race icon for inspect notes, the note's own
-- icon for NPC (target) notes
local function ModelTabIcon()
    local note = _noteID and NDB() and NDB().notes and NDB().notes[_noteID]
    if not note then return TAB_FALLBACK end
    -- A note whose tab is only there for a shown entry: that entry's icon
    local shown = ShownFor(_noteID)
    if shown and not IsInspectNote(_noteID) then
        local data = ResolveAttachment(shown.att)
        return (data and data.icon) or TAB_FALLBACK
    end
    if note.source == "inspect" and BNB.GetInspectRaceIcon then
        local ok, path = pcall(BNB.GetInspectRaceIcon, note.inspectRaceID, note.inspectSexID)
        if ok and path then return path end
    end
    local icon = BNB.NpcNoteIcon and BNB.NpcNoteIcon(note) or note.icon
    return (icon and icon ~= "") and icon or TAB_FALLBACK
end

-- Tint a tab's border + active-glow textures to the current skin preset,
-- same formula as the sidebar's GetPooledBtn (Sidebar.lua ~320-351).
local function TintSideTab(btn)
    local skinOn = BigNoteBoxDB and BigNoteBoxDB.skinMode
    local br, bg_, bb
    if skinOn and BNB.GetSkinPreset then
        br, bg_, bb = BNB.SkinBorderOf(BNB.GetSkinPreset())
    end
    if btn._border and btn._border.SetVertexColor then
        if skinOn and br then
            btn._border:SetVertexColor(br, bg_, bb, 1)
        else
            btn._border:SetVertexColor(1, 1, 1, 1)
        end
    end
    if btn._active and btn._active.SetVertexColor then
        if skinOn and br then
            btn._active:SetVertexColor(math.min(1, br * ACTIVE_GLOW_MULT),
                math.min(1, bg_ * ACTIVE_GLOW_MULT), math.min(1, bb * ACTIVE_GLOW_MULT), 1)
        else
            btn._active:SetVertexColor(ACTIVE_R, ACTIVE_G, ACTIVE_B, 1)
        end
    end
end

local function BuildSideTabs(f)
    local strip = CreateFrame("Frame", nil, f)
    strip:SetSize(TAB_SZ, TAB_SZ * 2 + TAB_GAP)
    strip:Hide()
    strip._sideTabs = true

    local function MakeTab(mode, tipKey)
        local btn = CreateFrame("Button", nil, strip)
        btn:SetSize(TAB_SZ, TAB_SZ)
        local border = btn:CreateTexture(nil, "OVERLAY")
        border:SetAllPoints(); border:SetTexture(TAB_BORDER)
        local icon = btn:CreateTexture(nil, "ARTWORK")
        icon:SetSize(TAB_ICON, TAB_ICON)
        local hover = btn:CreateTexture(nil, "OVERLAY", nil, -2)
        hover:SetAllPoints(); hover:SetTexture(ASSETS .. "Sidebar\\sb-hover"); hover:Hide()
        local active = btn:CreateTexture(nil, "OVERLAY", nil, -1)
        active:SetAllPoints(); active:SetTexture(ASSETS .. "Sidebar\\sb-active")
        active:Hide()
        btn._border, btn._icon, btn._hover, btn._active, btn._mode = border, icon, hover, active, mode
        TintSideTab(btn)

        btn:SetScript("OnEnter", function(self)
            if _rbMode ~= mode then hover:Show() end
            GameTooltip:SetOwner(self, SideTabSide() == "left" and "ANCHOR_LEFT" or "ANCHOR_RIGHT")
            GameTooltip:AddLine(L[tipKey], 1, 1, 1)
            GameTooltip:Show()
        end)
        btn:SetScript("OnLeave", function() hover:Hide(); GameTooltip:Hide() end)
        btn:SetScript("OnClick", function()
            if _rbMode == mode then return end
            hover:Hide()
            OnModeClick(mode)
        end)
        return btn
    end

    local tasksBtn = MakeTab("attachments", "REFBOX_STRIP_TASKS")
    tasksBtn:SetPoint("BOTTOM", strip, "BOTTOM", 0, 0)
    local modelBtn = MakeTab("model", "REFBOX_STRIP_MODEL")
    modelBtn:SetPoint("BOTTOM", tasksBtn, "TOP", 0, TAB_GAP)
    tasksBtn._icon:SetTexture(TAB_TASK_ICON)

    strip._modelBtn = modelBtn
    strip._tasksBtn = tasksBtn

    -- Live-refresh on preset/brightness change (Sidebar.lua ~838-863 pattern)
    if BNB.RegisterSkinButton then
        BNB.RegisterSkinButton(function()
            TintSideTab(tasksBtn)
            TintSideTab(modelBtn)
        end)
    end

    return strip
end

-- Skin mode: always under the frame, so its edge covers the tab's inner end
-- (Dukul, 2026-09-27: they drew on top of the window). Normal mode: under the
-- frame on Forever's right side (its border overlaps the tab), above otherwise.
-- "Under" is one strata lower: a child's frame level below its parent's did not
-- hold (raising the window lifts its children back over it, Dukul 2026-10-03).
-- A child keeps its own strata and still hides with the window.
local STRATA_BELOW = { MEDIUM = "LOW", HIGH = "MEDIUM", DIALOG = "HIGH",
                       FULLSCREEN = "DIALOG", FULLSCREEN_DIALOG = "FULLSCREEN" }
local function ApplySideTabLevel()
    local strip = _modeStrip
    if not (strip and strip._sideTabs and rbFrame) then return end
    local skin   = BigNoteBoxDB and BigNoteBoxDB.skinMode
    local under  = skin or (BNB.IsForever and SideTabSide() ~= "left")
    local strata = rbFrame:GetFrameStrata()
    if under then
        strip:SetFrameStrata(STRATA_BELOW[strata] or "LOW")
    else
        strip:SetFrameStrata(strata)
        strip:SetFrameLevel(rbFrame:GetFrameLevel() + 1)
    end
end

local function PositionSideTabs()
    local strip = _modeStrip
    local side  = SideTabSide()
    local skin  = BigNoteBoxDB and BigNoteBoxDB.skinMode
    local out   = skin and TAB_SKIN_OUT or 0
    strip:ClearAllPoints()
    if side == "left" then
        strip:SetPoint("BOTTOMRIGHT", rbFrame, "BOTTOMLEFT", TAB_OFF.left - out, TAB_BOTTOM)
    else
        strip:SetPoint("BOTTOMLEFT", rbFrame, "BOTTOMRIGHT", TAB_OFF.right + out, TAB_BOTTOM)
    end
    ApplySideTabLevel()
    local c1,c2,c3,c4,c5,c6,c7,c8 = SideTabTexCoord(side)
    for _, btn in ipairs({ strip._modelBtn, strip._tasksBtn }) do
        btn._border:SetTexCoord(c1,c2,c3,c4,c5,c6,c7,c8)
        btn._hover:SetTexCoord(c1,c2,c3,c4,c5,c6,c7,c8)
        btn._active:SetTexCoord(c1,c2,c3,c4,c5,c6,c7,c8)
        btn._icon:ClearAllPoints()
        btn._icon:SetPoint("TOPLEFT", btn, "TOPLEFT", TAB_ICON_X[side], TAB_ICON_Y)
    end
end

-- NPC notes store a creature-type icon (Humanoid = a human face). While that
-- NPC is the current target, show its live portrait instead, as the note list
-- does (NoteList.lua PopulateEntry).
local function TargetMatchesNpcNote()
    if not BNB.UnitNotesEnabled() then return false end   -- ALL-343
    local note = _noteID and NDB() and NDB().notes and NDB().notes[_noteID]
    if not (note and note.source == "target" and note.targetNpcID) then return false end
    if not UnitExists("target") or UnitIsPlayer("target") then return false end
    local guid = UnitGUID("target")
    local curID = guid and (
        guid:match("^Creature%-0%-%d+%-%d+%-%d+%-(%d+)") or
        guid:match("^Vehicle%-0%-%d+%-%d+%-%d+%-(%d+)") or
        guid:match("^Pet%-0%-%d+%-%d+%-%d+%-(%d+)")
    )
    return curID ~= nil and curID == tostring(note.targetNpcID)
end

-- Inspect note whose player is the current target (live portrait, ALL-46)
local function TargetMatchesInspectNote()
    if not BNB.UnitNotesEnabled() then return false end   -- ALL-343
    local note = _noteID and NDB() and NDB().notes and NDB().notes[_noteID]
    if not (note and note.source == "inspect" and note.inspectName) then return false end
    if not (UnitExists("target") and UnitIsPlayer("target")) then return false end
    local name, realm = BNB.UnitNameRealm("target")
    return name == note.inspectName and
        (not note.inspectRealm or note.inspectRealm == "" or realm == note.inspectRealm)
end

local function UpdateSideTabs()
    local strip = _modeStrip
    local icon  = strip._modelBtn._icon
    icon:SetTexture(ModelTabIcon())
    -- Live portrait while targeted, else the NPC's saved portrait (ALL-46)
    if ShownFor(_noteID) and not IsInspectNote(_noteID) then
        -- shown entry's icon, set above
    elseif TargetMatchesNpcNote() or TargetMatchesInspectNote() then
        pcall(SetPortraitTexture, icon, "target")
    elseif BNB.SetNpcNotePortrait then
        local note = _noteID and NDB() and NDB().notes and NDB().notes[_noteID]
        BNB.SetNpcNotePortrait(icon, note)
    end
    if BNB.ApplyIconFrame then
        local note = _noteID and NDB() and NDB().notes and NDB().notes[_noteID]
        BNB.ApplyIconFrame(icon, note)
    end
    for _, btn in ipairs({ strip._modelBtn, strip._tasksBtn }) do
        local on = (_rbMode == btn._mode)
        btn._active:SetShown(on)
        if on then btn._hover:Hide() end
        btn._icon:SetDesaturated(not on)
        local v = on and 1 or 0.90   -- sidebar INACTIVE_V
        btn._icon:SetVertexColor(v, v, v)
    end
end

local function BuildExternalModeStrip()
    if _modeStrip then return _modeStrip end

    if UseSideTabs() then
        -- Needs rbFrame; the build-time call comes before it is assigned, the
        -- call in BNB.OpenReferenceBox builds it
        if not rbFrame then return nil end
        _modeStrip = BuildSideTabs(rbFrame)
        return _modeStrip
    end

    local strip = CreateFrame("Frame", nil, UIParent)
    strip:SetHeight(28)
    strip:Hide()

    local modelBtn = BNB.CreateButton(nil, strip, L["REFBOX_STRIP_MODEL"], 1, 24)
    modelBtn:SetPoint("TOPLEFT",  strip, "TOPLEFT",  0, -2)
    modelBtn:SetPoint("TOPRIGHT", strip, "TOPLEFT",  math.floor(RBW / 2) - 1, -2)
    modelBtn:SetScript("OnClick", function() OnModeClick("model") end)

    local tasksBtn = BNB.CreateButton(nil, strip, L["REFBOX_STRIP_TASKS"], 1, 24)
    tasksBtn:SetPoint("TOPLEFT",  strip, "TOPLEFT",  math.floor(RBW / 2) + 1, -2)
    tasksBtn:SetPoint("TOPRIGHT", strip, "TOPRIGHT", 0, -2)
    tasksBtn:SetScript("OnClick", function() OnModeClick("attachments") end)

    strip._modelBtn = modelBtn
    strip._tasksBtn = tasksBtn
    _modeStrip = strip
    return strip
end

-- Reposition the external strip below rbFrame (side tabs: on its outer edge).
PositionModeStrip = function()
    if not rbFrame then return end
    if not _modeStrip then BuildExternalModeStrip() end   -- side tabs: auto-open path
    if not _modeStrip then return end
    if _modeStrip._sideTabs then PositionSideTabs(); return end
    _modeStrip:ClearAllPoints()
    _modeStrip:SetPoint("TOPLEFT",  rbFrame, "BOTTOMLEFT",  0, 0)
    _modeStrip:SetPoint("TOPRIGHT", rbFrame, "BOTTOMRIGHT", 0, 0)
end

-- Update button alpha to reflect active mode.
-- Active button is fully visible; inactive button is dimmed.
function UpdateModeStrip()
    -- Side tabs need rbFrame, so the build-time call skips them; the auto-open
    -- path in BNB.SyncReferenceBox never calls the builder, so build on first use
    if not _modeStrip and rbFrame then
        BuildExternalModeStrip()
        if _modeStrip then PositionModeStrip() end
    end
    if not _modeStrip then return end
    -- The tabs switch between the model and the tasks view, so with Tasks off
    -- both go and the note stays on its model (ALL-102)
    local hasModel = HasModel(_noteID) and BNB.TasksEnabled()
    _modeStrip:SetShown(hasModel)
    if not hasModel then return end
    if _modeStrip._sideTabs then UpdateSideTabs(); return end
    local mb = _modeStrip._modelBtn
    local tb = _modeStrip._tasksBtn
    if mb then
        mb:SetEnabled(_rbMode ~= "model")
        mb:SetAlpha(_rbMode == "model" and 1.0 or 0.45)
    end
    if tb then
        tb:SetEnabled(_rbMode ~= "attachments")
        tb:SetAlpha(_rbMode == "attachments" and 1.0 or 0.45)
    end
end

-- Called by Features/TargetNote.lua when an NPC portrait ID has been looked up
function BNB.RefreshReferenceBoxTabs()
    if rbFrame and rbFrame:IsShown() then UpdateModeStrip() end
end

-- ── Build window (both modes, shared shell UI/ToolWindow.lua, CMP-02) ─────────
-- ESC is set up in EnsureFrame (its own handler that steps aside for the main
-- window), so neither escClose nor keyEsc here.
local function BuildReferenceBox()
    local f = BNB.CreateToolWindow({
        name = "BigNoteBoxReferenceBoxFrame", w = RBW, h = 640, pad = PAD,
        title = L["REFBOX_TITLE"], toplevel = true,
        onClose = function() BNB.CloseReferenceBox() end,
        onDragStop = function() PositionModeStrip() end,
    })
    f:SetAlpha(1)   -- opaque in both modes, as before CMP-02 (the model viewer)
    local titleH = f._isSkin and SK_RB_TITLE_H or TITLE_H

    -- ── Manual entry strip ───────────────────────────────────────────────────
    local manualStrip = CreateFrame("Frame", nil, f)
    manualStrip:SetPoint("TOPLEFT",  f, "TOPLEFT",  PAD, -(titleH + 4))
    manualStrip:SetPoint("TOPRIGHT", f, "TOPRIGHT", -PAD, -(titleH + 4))
    manualStrip:SetHeight(MANUAL_H)
    f._manualStrip = manualStrip   -- hidden in the tasks-only layout (ALL-102)

    local eb = CreateFrame("EditBox", nil, manualStrip, "BackdropTemplate")
    BNB.EnsureBackdrop(eb)
    BNB.SetBackdrop(eb, 0.04, 0.04, 0.06, 0.90, 0.18, 0.18, 0.22, 1)
    eb:SetPoint("TOPLEFT",  manualStrip, "TOPLEFT",  0, 0)
    eb:SetPoint("TOPRIGHT", manualStrip, "TOPRIGHT", -68, 0)
    eb:SetHeight(MANUAL_H)
    eb:SetAutoFocus(false); eb:SetMultiLine(false); eb:SetMaxLetters(256)
    eb:SetFontObject("BNBFontNormalSmall"); eb:SetTextInsets(6, 6, 2, 2)
    BNB.AddPlaceholder(eb, L["REFBOX_PLACEHOLDER"], 0.4, 0.4, 0.45)
    eb:SetScript("OnEnterPressed", function(self)
        CommitManualEntry(self:GetRealText()); self:SetRealText(""); self:ClearFocus()
    end)
    eb:SetScript("OnEscapePressed", function(self)
        self:SetRealText(""); self:ClearFocus()
    end)
    f._manualBox = eb

    local addBtn = BNB.CreateButton(nil, manualStrip, L["REFBOX_ADD_BTN"], 40, MANUAL_H)
    addBtn:SetPoint("TOPRIGHT", manualStrip, "TOPRIGHT", -24, 0)
    addBtn:SetScript("OnClick", function()
        if IsLocked(_noteID) then BNB:Print(L["REFBOX_LOCKED"]); return end
        CommitManualEntry(eb:GetRealText()); eb:SetRealText(""); eb:ClearFocus()
    end)
    f._addBtn = addBtn

    local helpBtn = CreateFrame("Button", nil, manualStrip)
    helpBtn:SetSize(20, MANUAL_H)
    helpBtn:SetPoint("TOPRIGHT", manualStrip, "TOPRIGHT", 0, 0)
    local helpTex = helpBtn:CreateTexture(nil, "ARTWORK")
    helpTex:SetSize(20, 20)
    helpTex:SetPoint("CENTER", helpBtn, "CENTER", 0, 0)
    helpTex:SetTexture(ASSETS .. "UI\\ui-info")
    helpBtn:SetAlpha(0.55)
    helpBtn:SetScript("OnEnter", function(self)
        self:SetAlpha(1.0)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine(L["REFBOX_INFO_TITLE"], 1, 0.82, 0)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(L["REFBOX_INFO_BARE"],  0.85, 0.85, 0.85)
        GameTooltip:AddLine(L["REFBOX_INFO_SPELL"], 0.85, 0.85, 0.85)
        GameTooltip:AddLine(L["REFBOX_INFO_QUEST"], 0.85, 0.85, 0.85)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(L["REFBOX_INFO_ALSO"],  1, 0.82, 0)
        GameTooltip:AddLine(L["REFBOX_INFO_DRAG"],  0.78, 0.78, 0.78)
        GameTooltip:AddLine(L["REFBOX_INFO_SHIFT"], 0.78, 0.78, 0.78)
        GameTooltip:Show()
    end)
    helpBtn:SetScript("OnLeave", function(self)
        self:SetAlpha(0.55); GameTooltip:Hide()
    end)

    local countY = -(titleH + 4 + MANUAL_H + MANUAL_GAP + 2)
    local countLabel = f:CreateFontString(nil, "OVERLAY", "BNBFontNormal")   -- bigger (ALL-167)
    countLabel:SetPoint("TOPLEFT",  f, "TOPLEFT",  PAD, countY)
    countLabel:SetPoint("TOPRIGHT", f, "TOPRIGHT", -PAD, countY)
    countLabel:SetJustifyH("LEFT"); countLabel:SetTextColor(0.50, 0.50, 0.55)
    countLabel:SetText(string.format(L["REFBOX_COUNT"], 0, 0))
    f._countLabel = countLabel

    local scrollTop = -(titleH + 4 + MANUAL_H + MANUAL_GAP + COUNT_H + 4)
    local sf = BNB.CreateScrollFrame(nil, f)
    sf:SetPoint("TOPLEFT",     f, "TOPLEFT",    0,           scrollTop)
    sf:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -SCROLL_PAD, BOTTOM_PAD)

    if sf.ScrollBar then
        sf.ScrollBar:SetAlpha(0)
        sf:HookScript("OnScrollRangeChanged", function(_, _, yr)
            sf.ScrollBar:SetAlpha((yr or 0) > 1 and 1.0 or 0)
        end)
    end

    local sc = CreateFrame("Frame", nil, sf)
    sc:SetWidth(sf:GetWidth()); sc:SetHeight(1)
    sf:SetScrollChild(sc)
    sf:SetScript("OnSizeChanged", function(self)
        sc:SetWidth(self:GetWidth())
        -- Never taller than the content needs once the frame changes (ALL-138)
        if sc._contentH then sc:SetHeight(math.max(sc._contentH, self:GetHeight())) end
    end)

    -- Empty label lives inside the scroll child so it scrolls with gear sections.
    local emptyLabel = sc:CreateFontString(nil, "OVERLAY", "BNBFontNormalSmall")
    emptyLabel:SetPoint("TOPLEFT",  sc, "TOPLEFT",  PAD, -8)
    emptyLabel:SetPoint("TOPRIGHT", sc, "TOPRIGHT", -PAD, -8)
    emptyLabel:SetJustifyH("CENTER")
    emptyLabel:SetTextColor(0.38, 0.38, 0.42)
    emptyLabel:SetText(L["REFBOX_EMPTY"])
    f._emptyLabel = emptyLabel


    WireDragDrop(f); WireDragDrop(sc)

    f._scrollFrame = sf; f._scrollChild = sc

    BuildModelViewer(f)
    K.BuildTaskPanel(f)
    BuildExternalModeStrip()

    -- HookScript: the builder hooks OnShow in skin mode (ApplyMainWindowSkin)
    f:HookScript("OnShow", function()
        EnsureItemInfoListener(); InstallShiftHooks(); RenderList()
    end)
    f:HookScript("OnHide", function()
        ReleaseAllRows()
        if _pickerFrame and _pickerFrame:IsShown() then _pickerFrame:Hide() end
        if f._manualBox then f._manualBox:SetRealText("") end
    end)

    return f
end

-- ── Position / size ───────────────────────────────────────────────────────────
-- ── Content-height calculation ─────────────────────────────────────────────────
-- Called after RenderList, on position and on main window resize; the height
-- is fixed (ALL-99), so these only restore it if something changed it.
SyncRefBoxHeight = function()
    if not rbFrame then return end

    -- Fixed height, the same as Note Config (640 = the main window's default).
    -- It used to follow the main window, so a short main window squashed the
    -- model / attachments / tasks layout (ALL-99, Dukul 2026-09-28).
    local desired = 640
    local cur = rbFrame:GetHeight()
    if cur and math.abs(cur - desired) > 2 then
        rbFrame:SetHeight(desired)
    end
end

-- ── Model Viewer (inspect notes only) ─────────────────────────────────────────
-- Creates the model frame. Called by BuildReferenceBox (both modes)
-- once, after the scroll frame is created.
-- Components are hidden by default and shown by UpdateModelViewer.

-- ── Faction crest (FOR-22) ──────────────────────────────────────────────────
local FACTION_CREST = {
    Horde    = ASSETS .. "UI\\ui-bg-model-horde",
    Alliance = ASSETS .. "UI\\ui-bg-model-alliance",
}

-- "Horde" / "Alliance" for a model note, nil for neutral or unknown. Newest
-- source first: the saved field (notes made after FOR-22), the faction tag
-- (on by default), the race for inspect notes, then the "Faction: X" body line
-- both note formats write (tag setting off, older notes).
local function NoteFaction(note)
    if not note then return nil end
    local f = note.targetFaction or note.inspectFaction
    if FACTION_CREST[f] then return f end
    for _, t in ipairs(note.tags or {}) do
        if FACTION_CREST[t] then return t end
    end
    if note.source == "inspect" and note.inspectRaceID
       and C_CreatureInfo and C_CreatureInfo.GetFactionInfo then
        local ok, info = pcall(C_CreatureInfo.GetFactionInfo, note.inspectRaceID)
        if ok and info and FACTION_CREST[info.groupTag] then return info.groupTag end
    end
    local m = type(note.body) == "string" and note.body:match("Faction: (%a+)")
    if m and FACTION_CREST[m] then return m end
    return nil
end

BuildModelViewer = function(f)
    -- DressUpModel frame (below the item list, fills bottom portion of refbox)
    local model = CreateFrame("DressUpModel", nil, f)
    model:SetFrameLevel(f:GetFrameLevel() + 2)
    model:EnableMouseWheel(true)
    model:EnableMouse(true)
    model:Hide()

    -- Parchment background texture (stretched, 70% transparent)
    local bgTex = model:CreateTexture(nil, "BACKGROUND")
    bgTex:SetAllPoints(model)
    bgTex:SetTexture(ASSETS .. "UI\\ui-bg-parchment")
    bgTex:SetAlpha(0.30)
    model._bgTex = bgTex

    -- Faction crest (FOR-22) over the parchment: top-centre, a square as wide
    -- as the model, cropped at the bottom when the model is shorter than wide.
    -- The art is already faint, so it is drawn at full alpha.
    local crest = model:CreateTexture(nil, "BACKGROUND", nil, 1)
    crest:SetPoint("TOP", model, "TOP", 0, 0)
    crest:Hide()
    model._crestTex = crest
    local function SizeCrest()
        local w, h = model:GetWidth(), model:GetHeight()
        if not (w and h) or w <= 0 or h <= 0 then return end
        local ch = math.min(w, h)
        crest:SetSize(w, ch)
        crest:SetTexCoord(0, 1, 0, ch / w)
    end
    model:HookScript("OnSizeChanged", SizeCrest)
    model._sizeCrest = SizeCrest

    -- Mouse drag: left = turn (sideways) and tilt (up / down), right = pan;
    -- wheel = zoom, Shift+wheel = nearer / further (ALL-213, Dukul
    -- 2026-10-02: "move the model freely, not just on a 2D plane"). The OnUpdate that follows
    -- the pointer runs only while a button is held (PERF-08: it ran every
    -- frame the model was shown).
    local rotating = false
    local panning  = false
    local lastX, lastY = 0, 0
    local DragUpdate   -- set below

    -- Item view (ALL-206, Dukul 2026-10-02): an entry shown from the list
    -- turns gently by itself. A drag or a zoom stops it; SPIN_IDLE seconds
    -- after the last one the view resets and it turns again. model._spin is
    -- on while an entry is shown; the player / NPC view never turns.
    local SPIN_SPEED = 0.5   -- radians per second, a full turn in about 12 s
    local SPIN_IDLE  = 3     -- Dukul 2026-10-02: 5 s was a little long
    local function SpinUpdate(self, elapsed)
        self:SetFacing((self:GetFacing() or 0) + SPIN_SPEED * elapsed)
    end

    -- Start view of a shown entry: default position, then for a gear piece
    -- the camera the Appearances tab uses for its slot (ALL-213: the head
    -- for a helm, the shoulders for shoulders), set in model._cameraID
    model._resetView = function()
        model:SetPosition(0, 0, 0)
        model:SetModelScale(1)
        model:SetFacing(0)
        pcall(model.SetPitch, model, 0)
        if model._cameraID and Model_ApplyUICamera then
            pcall(Model_ApplyUICamera, model, model._cameraID)
        end
    end
    -- Back to the model's own camera (player / NPC view, mounts, pets):
    -- Model_ApplyUICamera leaves a custom camera, pitch, roll and a frozen pose
    model._clearCamera = function()
        if not model._cameraID then return end
        model._cameraID = nil
        pcall(model.SetPitch, model, 0)
        pcall(model.SetRoll, model, 0)
        pcall(model.UseModelCenterToTransform, model, false)
        pcall(model.RefreshCamera, model)
        pcall(model.SetAnimation, model, 0)
    end
    -- A race model that loads after the camera was set: set it again
    pcall(model.HookScript, model, "OnModelLoaded", function(self)
        if self._cameraID and self._spin and not (rotating or panning) then self._resetView() end
    end)

    -- model._spinOff: the camera bar's animation button turned the turning
    -- off (session only); the view still resets after a touch
    local function ResumeSpin()
        if not (model._spin and model:IsVisible()) or rotating or panning then return end
        model._resetView()
        if not model._spinOff then model:SetScript("OnUpdate", SpinUpdate) end
    end
    -- The user moved or zoomed: the spin waits, then the view resets
    local function SpinTouched()
        if model._spin then BNB.Debounce(MODEL_SPIN_KEY, SPIN_IDLE, ResumeSpin) end
    end
    model._startSpin = function()
        model._spin = true
        BNB.CancelDebounce(MODEL_SPIN_KEY)
        if not (rotating or panning or model._spinOff) then model:SetScript("OnUpdate", SpinUpdate) end
    end
    model._stopSpin = function()
        model._spin = false
        BNB.CancelDebounce(MODEL_SPIN_KEY)
        if not (rotating or panning) then model:SetScript("OnUpdate", nil) end
    end

    model:SetScript("OnMouseDown", function(self, btn)
        local cx, cy = GetCursorPosition()
        local scale = self:GetEffectiveScale()
        cx, cy = cx / scale, cy / scale
        if btn == "LeftButton" then
            rotating = true
            lastX, lastY = cx, cy
        elseif btn == "RightButton" then
            panning = true
            lastX, lastY = cx, cy
        end
        if rotating or panning then
            BNB.CancelDebounce(MODEL_SPIN_KEY)   -- no reset in the middle of a drag
            self:SetScript("OnUpdate", DragUpdate)
        end
    end)
    model:SetScript("OnMouseUp", function(self, btn)
        if btn == "LeftButton" then rotating = false end
        if btn == "RightButton" then panning = false end
        if not (rotating or panning) then
            self:SetScript("OnUpdate", nil)
            SpinTouched()
        end
    end)
    -- A hide mid-drag gets no OnMouseUp: end the drag so the next show is idle.
    -- A shown entry loads again on the next show (UpdateModelViewer).
    model:HookScript("OnHide", function(self)
        rotating, panning = false, false
        self:SetScript("OnUpdate", nil)
        BNB.CancelDebounce(MODEL_SPIN_KEY)
        self._shownKey = nil
    end)
    -- ALL-95: open hand over the model, holding hand while rotating / panning
    BNB.SetHoverCursor(model, "open", "hold")
    DragUpdate = function(self)
        local cx, cy = GetCursorPosition()
        local scale = self:GetEffectiveScale()
        cx, cy = cx / scale, cy / scale
        if rotating then
            local dx = (cx - lastX) * 0.01
            local dy = (cy - lastY) * 0.01
            lastX, lastY = cx, cy
            local facing = self:GetFacing() or 0
            self:SetFacing(facing + dx)
            -- Tilt, kept short of straight up / down
            local ok, pitch = pcall(self.GetPitch, self)
            pitch = ok and pitch or 0
            pcall(self.SetPitch, self, math.max(-MAX_PITCH, math.min(MAX_PITCH, pitch - dy)))
        end
        if panning then
            local dx = (cx - lastX) * 0.01
            local dy = (cy - lastY) * 0.01
            lastX, lastY = cx, cy
            local px, py, pz = self:GetPosition()
            self:SetPosition(px, py + dx, pz + dy)
        end
    end

    -- Scroll wheel to zoom (stops an item view's spin, SpinTouched)
    model:SetScript("OnMouseWheel", function(self, delta)
        if self._spin and not (rotating or panning) then self:SetScript("OnUpdate", nil) end
        if IsShiftKeyDown() then
            -- Nearer / further: the model's depth, the axis the drags leave out
            local px, py, pz = self:GetPosition()
            self:SetPosition(math.max(-MAX_DEPTH, math.min(MAX_DEPTH, px + delta * 0.25)), py, pz)
            SpinTouched()
            return
        end
        local scale = self:GetModelScale() or 1
        if delta > 0 then
            scale = math.min(scale * 1.1, 4.0)
        else
            scale = math.max(scale * 0.9, 0.3)
        end
        self:SetModelScale(scale)
        SpinTouched()
    end)

    -- Placeholder label for when target is out of range
    local placeholder = model:CreateFontString(nil, "OVERLAY", "BNBFontNormal")
    placeholder:SetPoint("CENTER", model, "CENTER", 0, 0)
    placeholder:SetWidth(RBW - 40)
    placeholder:SetJustifyH("CENTER")
    placeholder:SetTextColor(0.55, 0.55, 0.60)
    placeholder:SetText(L["REFBOX_MV_PLACEHOLDER"])
    placeholder:Hide()

    -- "Live" indicator label
    local liveLabel = model:CreateFontString(nil, "OVERLAY", "BNBFontNormalSmall")
    liveLabel:SetPoint("TOPLEFT", model, "TOPLEFT", 6, -4)
    liveLabel:SetTextColor(0.3, 1.0, 0.3, 0.8)
    liveLabel:SetText(L["REFBOX_MV_LIVE"])
    liveLabel:Hide()

    -- ── Model hide/show toggle buttons ───────────────────────────────────────
    -- "Hide model" button ("down") — top-right corner of the model viewer frame.
    -- Clicking hides the model, restores scroll area to full height.
    -- All four model buttons are icon buttons (UI/IconButton.lua), skin look in
    -- skin mode (ALL-210).
    local BTN_SZ = 24
    local hideBtn = BNB.CreateIconButton(model, BTN_SZ, "down",
        { tip = L["REFBOX_MV_HIDE_TIP"], tipSub = L["REFBOX_MV_HIDE_TIP_SUB"] })
    hideBtn:SetPoint("TOPRIGHT", model, "TOPRIGHT", -4, -4)
    hideBtn:SetFrameLevel(model:GetFrameLevel() + 4)
    hideBtn:SetScript("OnClick", function()
        if _noteID then _modelHidden[_noteID] = true end
        if rbFrame then RenderList() end
    end)
    hideBtn:Hide()  -- shown by UpdateModelViewer when model is visible

    -- X in the hide button's place while an entry from the list is shown
    -- (ALL-206): back to the note's own model, or no model on other notes
    local closeBtn = BNB.CreateIconButton(model, BTN_SZ, "close",
        { tip = L["REFBOX_MV_ITEM_CLOSE_TIP"] })
    closeBtn:SetPoint("TOPRIGHT", model, "TOPRIGHT", -4, -4)
    closeBtn:SetFrameLevel(model:GetFrameLevel() + 4)
    closeBtn:SetScript("OnClick", function()
        GameTooltip:Hide()
        if K.ClearShownModel then K.ClearShownModel() end
    end)
    closeBtn:Hide()

    -- "Show model" button ("up") — bottom-right corner of the refbox scroll area.
    -- Only visible when model data exists but the user has hidden the viewer.
    -- Same distance from the right edge as the hide button: the model's right
    -- inset (ApplyModelLayout insetR: 4 normal, 2 skin) plus the hide button's 4
    local showBtn = BNB.CreateIconButton(f, BTN_SZ, "up",
        { tip = L["REFBOX_MV_SHOW_TIP"], tipSub = L["REFBOX_MV_SHOW_TIP_SUB"] })
    local showR = ((BigNoteBoxDB and BigNoteBoxDB.skinMode) and 2 or 4) + 4
    showBtn:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -showR, BOTTOM_PAD + 4)
    showBtn:SetFrameLevel(f:GetFrameLevel() + 20)
    showBtn:SetScript("OnClick", function()
        if _noteID then _modelHidden[_noteID] = nil end
        if rbFrame then RenderList() end
    end)
    showBtn:Hide()  -- shown by UpdateModelViewer when model is hidden but available

    -- ── Gear view toggle button ("gearview") ─────────────────────────────────
    -- Visible in reconstructed mode: toggles dress-up between transmog and
    -- base gear. Visible but disabled in live mode (live already shows transmog).
    local gearBtn = BNB.CreateIconButton(model, BTN_SZ, "gearview", { tipAnchor = "ANCHOR_TOP",
        tip = function(self)
            if not self:IsEnabled() then return L["REFBOX_MV_GEAR_TMOG"], L["REFBOX_MV_LIVE_GEAR_TIP"] end
            local isTmog = _noteID and (_gearViewTmog[_noteID] ~= false)
            return isTmog and L["REFBOX_MV_GEAR_TMOG"] or L["REFBOX_MV_GEAR_REG"],
                string.format(L["REFBOX_MV_SWITCH_TO_FMT"], isTmog and L["REFBOX_MV_GEAR_REG"] or L["REFBOX_MV_GEAR_TMOG"])
        end })
    gearBtn:SetPoint("BOTTOMLEFT", model, "BOTTOMLEFT", 4, 4)
    gearBtn:SetFrameLevel(model:GetFrameLevel() + 4)
    gearBtn:SetScript("OnClick", function()
        if not _noteID then return end
        -- Toggle: nil/true = transmog, false = regular.
        local wasTmog = (_gearViewTmog[_noteID] ~= false)
        _gearViewTmog[_noteID] = not wasTmog
        UpdateModelViewer()
    end)
    gearBtn:Hide()
    f._modelGearBtn = gearBtn

    -- ── Camera bar (ALL-213, Dukul 2026-10-02) ───────────────────────────────
    -- Blizzard's shop camera buttons (atlas shop-icon-camera-*, file
    -- interface/shop/catalogshopcameracontrolicons2x), shown while the pointer
    -- is anywhere over the viewer (Dukul 2026-10-02; it was the bottom band
    -- only): turn left / right (held), reset
    -- view, and in the item view the animation button = turning on / off.
    -- Not built where the atlas is missing (it may not exist on Forever).
    local CAM_ATLAS = "shop-icon-camera-"
    local hasCamAtlas = C_Texture and C_Texture.GetAtlasInfo
        and C_Texture.GetAtlasInfo(CAM_ATLAS .. "rotateleft-default") ~= nil
    if hasCamAtlas then
        local CAM_BTN, CAM_GAP = 26, 4   -- button size, gap
        local TURN_SPEED = 2.0                          -- radians per second while held
        local bar = CreateFrame("Frame", nil, model)
        bar:SetHeight(CAM_BTN)
        bar:SetPoint("BOTTOM", model, "BOTTOM", 0, 6)
        bar:SetFrameLevel(model:GetFrameLevel() + 6)
        bar:SetAlpha(0)
        bar:Hide()

        local function CamButton(name, tipKey)
            local b = CreateFrame("Button", nil, bar)
            b:SetSize(CAM_BTN, CAM_BTN)
            b:SetNormalAtlas(CAM_ATLAS .. name .. "-default")
            b:SetHighlightAtlas(CAM_ATLAS .. name .. "-hover")
            b:SetPushedAtlas(CAM_ATLAS .. name .. "-pressed")
            b._camName = name
            b:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_TOP")
                GameTooltip:AddLine(L[self._tipKey or tipKey], 1, 1, 1)
                GameTooltip:Show()
            end)
            b:SetScript("OnLeave", function() GameTooltip:Hide() end)
            return b
        end

        -- Held turn buttons: the item's own turning pauses, as for a drag
        local function HoldTurn(b, dir)
            local function Turn(_, elapsed)
                model:SetFacing((model:GetFacing() or 0) + dir * TURN_SPEED * elapsed)
            end
            b:SetScript("OnMouseDown", function(self)
                BNB.CancelDebounce(MODEL_SPIN_KEY)
                if not (rotating or panning) then model:SetScript("OnUpdate", nil) end
                self:SetScript("OnUpdate", Turn)
            end)
            b:SetScript("OnMouseUp", function(self)
                self:SetScript("OnUpdate", nil)
                SpinTouched()
            end)
            b:HookScript("OnHide", function(self) self:SetScript("OnUpdate", nil) end)
        end

        local animBtn  = CamButton("animation",   "REFBOX_MV_SPIN_STOP")
        local leftBtn  = CamButton("rotateleft",  "REFBOX_MV_TURN_LEFT")
        local rightBtn = CamButton("rotateright", "REFBOX_MV_TURN_RIGHT")
        local resetBtn = CamButton("undo",        "REFBOX_MV_RESET_VIEW")
        HoldTurn(leftBtn,  1)
        HoldTurn(rightBtn, -1)

        resetBtn:SetScript("OnClick", function()
            BNB.CancelDebounce(MODEL_SPIN_KEY)
            if model._spin then
                model._resetView()
                if not (rotating or panning or model._spinOff) then
                    model:SetScript("OnUpdate", SpinUpdate)
                end
            else
                model:SetPosition(0, 0, 0)
                model:SetModelScale(1)
                model:SetFacing(0)
                pcall(model.SetPitch, model, 0)
            end
        end)

        -- Animation: the item view's turning on / off; lit while it turns
        local function ShowAnimState()
            local on = not model._spinOff
            animBtn:SetNormalAtlas(CAM_ATLAS .. "animation-" .. (on and "pressed" or "default"))
            animBtn._tipKey = on and "REFBOX_MV_SPIN_STOP" or "REFBOX_MV_SPIN_START"
        end
        animBtn:SetScript("OnClick", function(self)
            model._spinOff = not model._spinOff or nil
            BNB.CancelDebounce(MODEL_SPIN_KEY)
            if not (rotating or panning) then
                model:SetScript("OnUpdate", (model._spin and not model._spinOff) and SpinUpdate or nil)
            end
            ShowAnimState()
            if GameTooltip:IsOwned(self) then self:GetScript("OnEnter")(self) end
        end)

        -- Left to right: [animation] turn left, turn right, reset; the
        -- animation button only while an entry from the list is shown
        local function Layout()
            local btns = model._spin and { animBtn, leftBtn, rightBtn, resetBtn }
                or { leftBtn, rightBtn, resetBtn }
            animBtn:SetShown(model._spin == true)
            for i, b in ipairs(btns) do
                b:ClearAllPoints()
                b:SetPoint("LEFT", bar, "LEFT", (i - 1) * (CAM_BTN + CAM_GAP), 0)
            end
            bar:SetWidth(#btns * CAM_BTN + (#btns - 1) * CAM_GAP)
            ShowAnimState()
        end

        -- Shown while the pointer is over the viewer (a short fade). The poll
        -- runs only from the model's OnEnter until the pointer leaves it.
        local FADE = 0.15
        local function Watch(self, elapsed)
            local overModel = model:IsVisible() and model:IsMouseOver()
            local a = bar:GetAlpha()
            if overModel then
                if not bar:IsShown() then Layout(); bar:Show() end
                bar:SetAlpha(math.min(1, a + elapsed / FADE))
            else
                a = math.max(0, a - elapsed / FADE)
                bar:SetAlpha(a)
                if a == 0 then
                    bar:Hide()
                    if not overModel then self:SetScript("OnUpdate", nil) end
                end
            end
        end
        local watcher = CreateFrame("Frame", nil, model)
        model:HookScript("OnEnter", function() watcher:SetScript("OnUpdate", Watch) end)
        model:HookScript("OnHide", function()
            watcher:SetScript("OnUpdate", nil)
            bar:SetAlpha(0); bar:Hide()
        end)
        f._modelCamBar = bar
    end

    -- Secondary label: "Transmog gear" / "Regular gear" — shown below the LIVE/RECONSTRUCTED label.
    local gearLabel = model:CreateFontString(nil, "OVERLAY", "BNBFontNormalSmall")
    gearLabel:SetPoint("TOPLEFT", liveLabel, "BOTTOMLEFT", 0, -2)
    gearLabel:SetTextColor(0.75, 0.75, 0.75, 0.8)
    gearLabel:Hide()
    f._modelGearLabel = gearLabel

    f._modelFrame        = model
    f._modelPlaceholder  = placeholder
    f._modelLiveLabel    = liveLabel
    f._modelHideBtn      = hideBtn
    f._modelCloseBtn     = closeBtn
    f._modelShowBtn      = showBtn
    f._modelGearBtn      = gearBtn
    f._modelGearLabel    = gearLabel
    f._modelSplit        = MODEL_SPLIT_DEFAULT
end

-- Apply the fixed split ratio to the scroll frame and model positions
ApplyModelLayout = function(f)
    if not f or not f._scrollFrame or not f._modelFrame then return end
    local sf  = f._scrollFrame
    local mdl = f._modelFrame

    -- Total available height = from scroll frame top to frame bottom
    local sfTop = sf:GetTop()
    local fBot  = f:GetBottom()
    if not sfTop or not fBot then return end
    local totalH = sfTop - fBot - BOTTOM_PAD
    if totalH < 1 then return end

    local split = f._modelSplit or MODEL_SPLIT_DEFAULT
    local itemH = math.max(MODEL_SPLIT_MIN_PX, math.floor(totalH * split))
    -- No Reference part and no gear list (an NPC note): the model takes it all (ALL-388)
    local sc0 = f._scrollChild
    if not RBOn() and sc0 and (sc0._contentH or 0) == 0 then itemH = 0 end
    local modelH = math.max(MODEL_MIN_H, totalH - itemH)

    -- Scroll frame: anchor top is unchanged, set bottom above the model
    sf:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -SCROLL_PAD, BOTTOM_PAD + modelH)

    -- Model: fills the bottom, inset to stay inside the frame border
    local isSkin = BigNoteBoxDB and BigNoteBoxDB.skinMode
    local insetL = isSkin and 5 or 7
    local insetR = isSkin and 2 or 4
    local insetB = isSkin and 0 or 0
    mdl:ClearAllPoints()
    mdl:SetPoint("TOPLEFT",     f, "BOTTOMLEFT",   insetL, BOTTOM_PAD + modelH)
    mdl:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -insetR, BOTTOM_PAD + insetB)

    -- Update scroll child width
    local sc = f._scrollChild
    if sc then sc:SetWidth(sf:GetWidth()) end
end

-- Show/hide model viewer based on current note; load model if needed
UpdateModelViewer = function()
    if not rbFrame then return end
    local isInspect = HasModel(_noteID)   -- own model or a shown entry (ALL-206)
    local shown     = ShownFor(_noteID)

    local mdl      = rbFrame._modelFrame
    local ph       = rbFrame._modelPlaceholder
    local ll       = rbFrame._modelLiveLabel
    local hideBtn  = rbFrame._modelHideBtn
    local showBtn  = rbFrame._modelShowBtn
    local gearBtn  = rbFrame._modelGearBtn
    local gearLbl  = rbFrame._modelGearLabel
    local closeBtn = rbFrame._modelCloseBtn

    if not mdl then return end
    if ph then ph:SetText(L["REFBOX_MV_PLACEHOLDER"]) end   -- the NPC branch may say "no visible model"
    -- Only a shown entry spins and has the X; set again below when one is shown
    if closeBtn then closeBtn:Hide() end
    if not shown then
        if mdl._spin and mdl._stopSpin then mdl._stopSpin() end
        mdl._shownKey = nil
        mdl._clearCamera()
        -- The player / NPC view resets position and facing below; tilt too
        pcall(mdl.SetPitch, mdl, 0)
    end

    -- Suppress model whenever we're in tasks/attachments mode on an inspect note
    if isInspect and _rbMode == "attachments" then
        mdl:Hide()
        if ph      then ph:Hide()      end
        if ll      then ll:Hide()      end
        if hideBtn then hideBtn:Hide() end
        if showBtn then showBtn:Hide() end
        if gearBtn then gearBtn:Hide() end
        if gearLbl then gearLbl:Hide() end
        return
    end

    -- Not an inspect/target-model note — hide everything, restore scroll frame
    if not isInspect then
        mdl:Hide()
        if ph      then ph:Hide()      end
        if ll      then ll:Hide()      end
        if hideBtn then hideBtn:Hide() end
        if showBtn then showBtn:Hide() end
        if gearBtn then gearBtn:Hide() end
        if gearLbl then gearLbl:Hide() end
        local sf = rbFrame._scrollFrame
        if sf then
            sf:SetPoint("BOTTOMRIGHT", rbFrame, "BOTTOMRIGHT", -SCROLL_PAD, BOTTOM_PAD)
        end
        return
    end

    -- Note has model data — check if the user has hidden the viewer for this note
    if _noteID and _modelHidden[_noteID] then
        mdl:Hide()
        if ph      then ph:Hide()      end
        if ll      then ll:Hide()      end
        if hideBtn then hideBtn:Hide() end
        if showBtn then showBtn:Show() end
        if gearBtn then gearBtn:Hide() end
        if gearLbl then gearLbl:Hide() end
        local sf = rbFrame._scrollFrame
        if sf then
            sf:SetPoint("BOTTOMRIGHT", rbFrame, "BOTTOMRIGHT", -SCROLL_PAD, BOTTOM_PAD)
        end
        return
    end

    -- Show model, hide the "show" button, show the "hide" button
    mdl:Show()
    if hideBtn then hideBtn:Show() end
    if showBtn then showBtn:Hide() end

    -- Apply layout
    ApplyModelLayout(rbFrame)

    -- Try live mode first: check if the inspected player is our current target
    local note = BNB.GetNote(_noteID)

    -- Faction crest (FOR-22)
    local crest = mdl._crestTex
    if crest then
        local fac = NoteFaction(note)
        if fac then
            crest:SetTexture(FACTION_CREST[fac])
            mdl._sizeCrest()
            crest:Show()
        else
            crest:Hide()
        end
    end

    -- An entry from the list (ALL-206): drawn once per show, then left alone,
    -- so a re-layout does not reset a model the user is turning
    if shown then
        if hideBtn then hideBtn:Hide() end
        if closeBtn then closeBtn:Show() end
        if gearBtn then gearBtn:Hide() end
        if gearLbl then gearLbl:Hide() end
        local key = shown.spec.kind .. ":" .. shown.spec.id .. ":" .. tostring(shown.spec.sourceID)
        if mdl._shownKey ~= key then
            mdl._shownKey = key
            local spec = shown.spec
            mdl._clearCamera()
            -- Weapons, shields and off-hands on their own with their slot
            -- camera, as the Appearances tab shows them. When that cannot be
            -- done they go on a character like armour, without the camera.
            local alone = false
            if spec.kind == "weapon" and mdl.SetItemAppearance then
                local appearanceID
                if spec.sourceID and C_TransmogCollection and C_TransmogCollection.GetSourceInfo then
                    local ok, info = pcall(C_TransmogCollection.GetSourceInfo, spec.sourceID)
                    appearanceID = ok and info and info.visualID or nil
                end
                appearanceID = appearanceID or ItemAppearance(spec.id)
                if appearanceID then
                    pcall(mdl.ClearModel, mdl)
                    alone = pcall(mdl.SetItemAppearance, mdl, appearanceID)
                    if alone then mdl._cameraID = GearCameraID(spec.id, spec.sourceID) end
                end
                ViewerTrace("alone: visual=%s ok=%s camera=%s", tostring(appearanceID), tostring(alone), tostring(mdl._cameraID))
            end
            if alone then
                -- shown above; nothing else to load
            elseif spec.kind == "gear" or spec.kind == "weapon" then
                -- On the note's player (race + sex) when it has one, else on
                -- your own character; undressed, so the piece stands out
                local raceLoaded = false
                if note and note.inspectRaceID and note.inspectSexID ~= nil then
                    pcall(function()
                        mdl:SetUnit("none")
                        mdl:SetCustomRace(note.inspectRaceID, note.inspectSexID)
                        local fileID = mdl:GetModelFileID()
                        raceLoaded = fileID ~= nil and fileID ~= 0
                    end)
                end
                if not raceLoaded then pcall(mdl.SetUnit, mdl, "player") end
                pcall(mdl.Undress, mdl)
                local okTry, tryResult = pcall(mdl.TryOn, mdl, spec.sourceID or ("item:" .. spec.id))
                if spec.kind == "gear" then mdl._cameraID = GearCameraID(spec.id, spec.sourceID) end
                ViewerTrace("worn: race=%s tryOn ok=%s result=%s camera=%s model=%s", tostring(raceLoaded),
                    tostring(okTry), tostring(tryResult), tostring(mdl._cameraID), tostring(mdl:GetModelFileID()))
            elseif spec.kind == "creature" then
                pcall(mdl.SetCreature, mdl, spec.id)
            else
                pcall(mdl.SetDisplayInfo, mdl, spec.id)
            end
            mdl._resetView()
            mdl._startSpin()
        end
        if ph then ph:Hide() end
        if ll then
            local data = ResolveAttachment(shown.att)
            ll:SetText(data and data.name or "")
            if data then ll:SetTextColor(data.qr, data.qg, data.qb, 0.9) end
            ll:Show()
        end
        return
    end
    local inspName  = note and note.inspectName
    local tgtName = (BNB.UnitNameRealm("target"))

    local isLive = false
    if tgtName and inspName and tgtName == inspName then
        if UnitIsPlayer("target") then
            isLive = true
        end
    end

    if isLive then
        -- Live mode: show the actual target model (includes transmog appearance).
        -- Gear view toggle is visible but disabled — live already shows real transmog.
        pcall(function() mdl:SetUnit("target") end)
        mdl:SetPosition(0, 0, 0)
        mdl:SetModelScale(1)
        mdl:SetFacing(0)
        if ph then ph:Hide() end
        if ll then
            ll:SetText(L["REFBOX_MV_LIVE"])
            ll:SetTextColor(0.3, 1.0, 0.3, 0.8)
            ll:Show()
        end
        if gearBtn then
            gearBtn:SetEnabled(false)
            gearBtn:Show()
        end
        if gearLbl then
            gearLbl:SetText(L["REFBOX_MV_GEAR_TMOG"])
            gearLbl:Show()
        end
    elseif note and note.inspectRaceID and note.inspectSexID ~= nil then
        -- Reconstructed mode: build model from stored race + gear.
        -- Gear view toggle switches between transmog appearances and base item IDs.
        local showTmog = (_noteID == nil) or (_gearViewTmog[_noteID] ~= false)

        -- Attempt 1: SetUnit("none") + SetCustomRace for correct race model
        local modelLoaded = false
        pcall(function()
            mdl:SetUnit("none")
            mdl:SetCustomRace(note.inspectRaceID, note.inspectSexID)
            local fileID = mdl:GetModelFileID()
            if fileID and fileID ~= 0 then modelLoaded = true end
        end)

        -- Attempt 2: if that produced nothing, fall back to player model undressed
        if not modelLoaded then
            pcall(function()
                mdl:SetUnit("player")
                mdl:Undress()
            end)
        end

        -- Dress up based on gear view toggle state.
        local tmog = note.inspectTransmogAppearances
        if showTmog and tmog and next(tmog) then
            -- Transmog view: use stored appearance IDs.
            for _, appearanceID in pairs(tmog) do
                pcall(function() mdl:TryOn(appearanceID) end)
            end
        elseif not showTmog and note.inspectGearItems and #note.inspectGearItems > 0 then
            -- Regular view: use base item IDs from inspectGearItems.
            for _, g in ipairs(note.inspectGearItems) do
                if g.id then
                    pcall(function() mdl:TryOn("item:" .. g.id) end)
                end
            end
        elseif not showTmog then
            -- Fallback for old notes: use attachments as base gear.
            local attachments = GetAttachments(_noteID) or {}
            for _, att in ipairs(attachments) do
                if att.type == "item" and att.id then
                    pcall(function() mdl:TryOn("item:" .. att.id) end)
                end
            end
        else
            -- No transmog data at all (old note captured before transmog feature).
            local attachments = GetAttachments(_noteID) or {}
            for _, att in ipairs(attachments) do
                if att.type == "item" and att.id then
                    pcall(function() mdl:TryOn("item:" .. att.id) end)
                end
            end
        end

        mdl:SetPosition(0, 0, 0)
        mdl:SetModelScale(1)
        mdl:SetFacing(0)
        if ph then ph:Hide() end
        if ll then
            if not (tmog and next(tmog)) and showTmog then
                ll:SetText(L["REFBOX_MV_RECONSTRUCTED_HINT"])
            else
                ll:SetText(L["REFBOX_MV_RECONSTRUCTED"])
            end
            ll:SetTextColor(0.75, 0.75, 0.75, 0.8)
            ll:Show()
        end
        -- Gear toggle button: enabled only when transmog data is available.
        if gearBtn then
            local hasTmog = tmog and next(tmog)
            gearBtn:SetEnabled(hasTmog ~= nil)
            gearBtn:SetDim(not hasTmog)   -- no transmog: clickable, drawn disabled
            gearBtn:Show()
        end
        if gearLbl then
            gearLbl:SetText(showTmog and L["REFBOX_MV_GEAR_TMOG"] or L["REFBOX_MV_GEAR_REG"])
            gearLbl:Show()
        end
    elseif note and note.targetNpcID then
        -- Target note: NPC / mob / boss rendered via SetCreature(npcID).
        -- npcID is the creature ID extracted from the GUID at note creation.
        -- SetCreature works offline without a live unit present.
        -- Note: combat pets are excluded by IsInspectNote (targetIsPet check).
        local creatureID = tonumber(note.targetNpcID)
        if creatureID then
            local inv    = BNB.INVISIBLE_NPC_DISPLAYS or {}
            local dispID = tonumber(note.targetDisplayID)
            mdl:SetPosition(0, 0, 0)
            mdl:SetModelScale(1)
            mdl:SetFacing(0)
            if ll then ll:Hide() end
            if note.targetShared or (dispID and inv[dispID]) then
                -- A display stand (ALL-340): NPC 185669 is one creature ID with
                -- the empty model of trigger NPCs (display 11686, probed
                -- 2026-10-09: nothing drawn in a PlayerModel or a DressUpModel),
                -- shown by the server as a different mount per spawn. One load,
                -- no SetCreature and no second model 0.3 s later (RET-09 hunt):
                -- the mount found by name, else a line saying so.
                if not note.targetShared or not dispID or inv[dispID] then
                    note.targetShared = true   -- a stand note from before ALL-340
                    local mnt = BNB.MountDisplayForName and BNB.MountDisplayForName(note.title)
                    if mnt then note.targetDisplayID = mnt; dispID = mnt end
                end
                -- Never SetUnit("target") on a stand: the live stand (its look
                -- swapped for a mount by the server) is the prime suspect for
                -- RET-09 (crash with the stand targeted and only one note,
                -- Dukul 2026-10-09)
                local drawn = false
                if dispID and dispID > 0 and not inv[dispID] then
                    drawn = pcall(mdl.SetDisplayInfo, mdl, dispID)
                end
                if drawn then
                    if ph then ph:Hide() end
                else
                    pcall(mdl.ClearModel, mdl)
                    if ph then ph:SetText(L["REFBOX_MV_INVISIBLE"]); ph:Show() end
                end
            else
                pcall(function()
                    mdl:SetCreature(creatureID)
                end)
                -- SetCreature draws nothing for a creature the client has no
                -- data for: the saved display ID, then the live unit while it
                -- is targeted, fill the viewer instead
                local noteID = note.id
                C_Timer.After(0.3, function()
                    if _noteID ~= noteID or not mdl:IsShown() then return end
                    local fid = mdl.GetModelFileID and mdl:GetModelFileID()
                    if fid and fid ~= 0 then return end
                    if BNB.NoteMatchesTarget and BNB.NoteMatchesTarget(note) then
                        pcall(mdl.SetUnit, mdl, "target")
                    elseif dispID and dispID > 0 then
                        pcall(mdl.SetDisplayInfo, mdl, dispID)
                    end
                end)
                if ph then ph:Hide() end
            end
        else
            -- Invalid creature ID — show placeholder
            mdl:SetUnit("none")
            mdl:SetFacing(0)
            if ph then ph:Show() end
            if ll then ll:Hide() end
        end
        if gearBtn then gearBtn:Hide() end
        if gearLbl then gearLbl:Hide() end
    else
        -- No model data — show placeholder
        mdl:SetUnit("none")
        mdl:SetFacing(0)
        if ph then ph:Show() end
        if ll then ll:Hide() end
        if gearBtn then gearBtn:Hide() end
        if gearLbl then gearLbl:Hide() end
    end
end
local function PositionFrame()
    if not rbFrame then return end
    rbFrame:ClearAllPoints()
    local side = (BigNoteBoxDB and BigNoteBoxDB.refboxSide) or BNB.DEFAULTS.refboxSide
    if BNB.mainFrame and BNB.mainFrame:IsShown() then
        if side == "right" then
            rbFrame:SetPoint("TOPLEFT", BNB.mainFrame, "TOPRIGHT", 8, 0)
        else
            rbFrame:SetPoint("TOPRIGHT", BNB.mainFrame, "TOPLEFT", -8, 0)
        end
    else
        rbFrame:SetPoint("CENTER", UIParent, "CENTER", -200, 0)
    end
    SyncRefBoxHeight()
    PositionModeStrip()
end

local function HookMainWindowResize()
    if not BNB.mainFrame then return end
    BNB.mainFrame:HookScript("OnSizeChanged", function(self)
        if rbFrame and rbFrame:IsShown() then SyncRefBoxHeight() end
    end)
    -- Keep the external mode strip anchored below rbFrame after any move/resize
    if rbFrame then
        rbFrame:HookScript("OnSizeChanged", function()
            PositionModeStrip()
        end)
    end
end

-- The title lists what the window shows, joined with " + " (ALL-102):
-- "Reference" whenever the Reference Box is on (its add strip and list are
-- always there), "Model" for a note with a model, "Tasks" for a note with
-- tasks. Without the Reference part the tasks view is always there while Tasks
-- is on (its Add Tasks button), so "Tasks" too (ALL-388).
UpdateDynamicTitle = function()
    if not rbFrame then return end
    local parts = {}
    if RBOn() then parts[#parts + 1] = L["REFBOX_PART_REF"] end
    if HasModel(_noteID) then parts[#parts + 1] = L["REFBOX_PART_MODEL"] end
    if (not RBOn() and BNB.TasksEnabled()) or (BNB.Task and BNB.Task.Shows(_noteID)) then
        parts[#parts + 1] = L["REFBOX_TITLE_TASKS"]
    end
    local title = table.concat(parts, " + ")

    rbFrame:SetWindowTitle(title)
end

local function SetTitle(noteID)
    -- Kept for compatibility — just delegates to UpdateDynamicTitle.
    UpdateDynamicTitle()
end

-- ── Public API ────────────────────────────────────────────────────────────────
-- The window opens while any of its three modules is on (ALL-102, ALL-388).
local function BoxUsable()
    return RBOn() or BNB.TasksEnabled() or BNB.UnitNotesEnabled()
end

-- True when the note has something this window shows: tasks (module on), its
-- own model (Player & NPC Notes on), and with the Reference Box on, attachments.
local function HasContent(noteID)
    if BNB.Task and BNB.Task.Shows(noteID) then return true end
    if IsInspectNote(noteID) then return true end
    if not RBOn() then return false end
    local atts = GetAttachments(noteID)
    return atts and #atts > 0 or false
end

-- The window can show this note at all: the Reference part is always there
-- (its add strip), else the note's model or the tasks view (ALL-388)
local function CanShow(noteID)
    return RBOn() or BNB.TasksEnabled() or IsInspectNote(noteID)
end

local function EnsureFrame()
    if rbFrame then return end
    rbFrame = BuildReferenceBox()
    HookMainWindowResize()
    K.RegisterTaskCallback()
    -- ESC normally reaches this box through the main window's key handler
    -- (MainWindow.lua OnEscapeKey), which stops the key there. Opened on
    -- its own (Oracle search, Alt) the main window is closed, so that
    -- cascade never runs. UISpecialFrames covers this on Retail, but not
    -- reliably on Forever (confirmed 2026-09-26, ALL-69.2: closes fine
    -- with X, not with ESC, on Forever only) -- so the fallback is our
    -- own key handler, which only takes over while the main window is
    -- closed (it steps aside otherwise, so MainWindow's cascade order,
    -- e.g. Task Edit Window before Reference Box, is untouched).
    -- Here, not in OpenReferenceBox: the note-switch auto-open builds the
    -- frame too, and a box built there never closed on ESC (2026-10-03)
    tinsert(UISpecialFrames, "BigNoteBoxReferenceBoxFrame")
    BNB.AttachEscClose(rbFrame, function() BNB.CloseReferenceBox() end,
        BNB.MainWindowShown)
    rbFrame:HookScript("OnHide", function()
        if _modeStrip then _modeStrip:Hide() end
    end)
end

function BNB.OpenReferenceBox(noteID, mode)
    if not BoxUsable() or not CanShow(noteID or BNB._currentNoteID) then return end
    BNB.StampOpened(noteID)
    EnsureFrame()
    _noteID = noteID or BNB._currentNoteID
    -- A shown entry (ALL-206) belongs to its note: ShownFor drops it elsewhere
    if _shown and _shown.noteID ~= _noteID then _shown = nil end
    -- Reset to model mode on every note switch for inspect notes; mode
    -- "attachments" = the list / tasks view (the Tasks bar button, ALL-388),
    -- kept only while Tasks is on: the tabs to get back to the model need it
    local listView = mode == "attachments" and BNB.TasksEnabled()
    _rbMode = (not listView and HasModel(_noteID)) and "model" or "attachments"
    SetTitle(_noteID)
    PositionFrame()
    BuildExternalModeStrip()
    PositionModeStrip()
    UpdateModeStrip()
    if not rbFrame:IsShown() then rbFrame:Show() else RenderList() end
end

function BNB.CloseReferenceBox()
    if rbFrame then rbFrame:Hide() end
    if _modeStrip then _modeStrip:Hide() end
end

function BNB.ToggleReferenceBox()
    if DB().referenceBoxEnabled == false then
        BNB:Print(L["REFBOX_DISABLED"])
        return
    end
    if rbFrame and rbFrame:IsShown() then
        BNB.CloseReferenceBox()
    else
        BNB.OpenReferenceBox(BNB._currentNoteID)
    end
end

-- The editor bar's Tasks button (ALL-102). With the Reference Box on it adds a
-- task, as it always did. As the tasks view's only way in, it opens or closes
-- the window on a note with tasks, and adds the first task otherwise. A note
-- with a model opens on its tasks view (ALL-388).
function BNB.OnTasksBarButton(id)
    if not id or not BNB.TasksEnabled() or not BNB.Task then return end
    if not RBOn() and BNB.Task.HasTasks(id) then
        if rbFrame and rbFrame:IsShown() and _noteID == id and _rbMode ~= "model" then
            BNB.CloseReferenceBox()
        else
            BNB.OpenReferenceBox(id, "attachments")
        end
        return
    end
    local taskID = BNB.Task.AddTask(id, "")
    if taskID then
        BNB.OpenReferenceBox(id, "attachments")
        C_Timer.After(0.05, function()
            if BNB.FocusTaskEditBox then BNB.FocusTaskEditBox(taskID) end
        end)
    end
end

-- Called when the Reference Box, Tasks or Player & NPC Notes switch changes
-- (UI/Config/Modules.lua, Features/UnitNotes.lua): relayout an open window for
-- its parts, or close it when it has nothing left to show.
function BNB.ApplyRefBoxModules()
    if not (rbFrame and rbFrame:IsShown()) then return end
    if not BoxUsable() or (not RBOn() and not HasContent(_noteID)) then
        BNB.CloseReferenceBox()
        return
    end
    BNB.OpenReferenceBox(_noteID, _rbMode)
end

-- Called by SelectNote on every note switch.
-- Auto-opens if configured and note has attachments. Never auto-closes.
BNB.RegisterMessage("ReferenceBox", "NoteSelected", function(_, id) BNB.SyncReferenceBox(id) end)

function BNB.SyncReferenceBox(noteID)
    if not noteID then
        if rbFrame and rbFrame:IsShown() then rbFrame:Hide() end
        return
    end
    -- Reset gear view to transmog (default) whenever the note changes.
    if _noteID ~= noteID then
        _gearViewTmog[noteID] = nil
        _shown = nil   -- the entry shown in the viewer belonged to the last note (ALL-206)
    end
    _noteID = noteID

    -- Auto-open on anything the window shows: attachments, a model (inspect
    -- notes with gear, target notes with an NPC ID) or tasks (HasContent).
    local hasContent = HasContent(noteID)

    if DB().refboxAutoOpen and BoxUsable()
       and BNB.mainFrame and BNB.mainFrame:IsShown() then
        if hasContent then
            EnsureFrame()
            if not rbFrame:IsShown() then
                _rbMode = HasModel(noteID) and "model" or "attachments"
                SetTitle(noteID)
                PositionFrame()
                rbFrame:Show()
                return   -- OnShow fires RenderList
            end
        end
    end

    -- Already open: update title + content, or close if the new note has nothing
    if rbFrame and rbFrame:IsShown() then
        if (DB().refboxAutoOpen and not hasContent) or not CanShow(noteID) then
            rbFrame:Hide()
            if _modeStrip then _modeStrip:Hide() end
            return
        end
        -- Reset mode for new note
        _rbMode = HasModel(noteID) and "model" or "attachments"
        UpdateModeStrip()
        SetTitle(noteID)
        RenderList()
    end
end

function BNB.RefreshReferenceBox()
    if not rbFrame or not rbFrame:IsShown() then return end
    RenderList()
end

-- Update model viewer when target changes (live mode toggle)
BNB.RegisterEvent("PLAYER_TARGET_CHANGED", function()
    if not rbFrame or not rbFrame:IsShown() then return end
    if IsInspectNote(_noteID) then
        -- A shown entry stays in the viewer (ALL-206); only the tab follows
        if not ShownFor(_noteID) then C_Timer.After(0.1, UpdateModelViewer) end
        UpdateModeStrip()   -- Model tab: NPC portrait follows the target
    end
end)

-- ── Kit helpers for UI/ReferenceBoxTasks.lua (see the kit above) ──────────────
K.HasModel, K.OnModeClick = HasModel, OnModeClick
K.ClearShownModel = ClearShownModel   -- the model viewer's X (built before it is defined)
K.UpdateModeStrip, K.UpdateModelViewer, K.UpdateDynamicTitle =
    UpdateModeStrip, UpdateModelViewer, UpdateDynamicTitle

--------------------------------------------------------------------------------
-- Public: add an attachment to a note from outside this module (e.g. QuickNote)
--------------------------------------------------------------------------------
function BNB.RBAddAttachment(noteID, att)
    AddAttachment(noteID, att)
end

--------------------------------------------------------------------------------
-- Feature B: show ItemID / SpellID / QuestID in the game's native tooltip.
-- Controlled by BigNoteBoxDB.refboxShowIDs (default false).
-- Adds a single "BNB: <id>" line in BNB green to the bottom of the tooltip.
-- This is a standalone QoL feature — it fires for every item/spell/quest
-- tooltip, not just those present in any note's attachments.
-- Uses TooltipDataProcessor.AddTooltipPostCall (retail API since 10.0.2).
--
-- All three callbacks use data.id (numeric) which is the canonical field
-- provided by the TooltipDataProcessor system for Item, Spell, and Quest
-- types. tooltip:Show() is called after AddDoubleLine to force the tooltip
-- to resize and display the added line.
--------------------------------------------------------------------------------
do
    local function ShouldShowIDs()
        return BigNoteBoxDB and BigNoteBoxDB.refboxShowIDs == true
    end

    local BNB_GREEN_R, BNB_GREEN_G, BNB_GREEN_B = 0.55, 0.82, 0.55

    -- Shared helper: add a blank line, then a labelled BNB ID line
    -- The blank line above gives visual separation from the game's own tooltip text.
    local _idBlockStarted = false  -- track if we've added the leading blank for this tooltip

    local function AddIDLine(tooltip, label, id)
        if not _idBlockStarted then
            tooltip:AddLine(" ")   -- blank line before first BNB line
            _idBlockStarted = true
        end
        tooltip:AddDoubleLine("BNB " .. label .. ":", tostring(id),
            BNB_GREEN_R, BNB_GREEN_G, BNB_GREEN_B,
            BNB_GREEN_R, BNB_GREEN_G, BNB_GREEN_B)
    end

    -- Refresh tooltip after all lines are added; reset block tracker
    local function Refresh(tooltip)
        tooltip:AddLine(" ")   -- blank line after last BNB line
        _idBlockStarted = false
        tooltip:Show()
    end

    -- Item tooltips: show ItemID + IconID
    local function OnItemTip(tooltip, id)
        if not ShouldShowIDs() then return end
        if not id or id <= 0 then return end
        AddIDLine(tooltip, "ItemID", id)
        local icon = C_Item.GetItemIconByID and C_Item.GetItemIconByID(id)
                  or select(10, C_Item.GetItemInfo(id))
        if icon then
            AddIDLine(tooltip, "IconID", icon)
        end
        Refresh(tooltip)
    end

    -- Spell tooltips: show SpellID + IconID
    local function OnSpellTip(tooltip, id)
        if not ShouldShowIDs() then return end
        if not id or id <= 0 then return end
        AddIDLine(tooltip, "SpellID", id)
        local icon = C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(id)
        if icon then
            AddIDLine(tooltip, "IconID", icon)
        end
        Refresh(tooltip)
    end

    local hasTDP = TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall
        and Enum and Enum.TooltipDataType
    if hasTDP then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip, data)
            OnItemTip(tooltip, data and data.id)
        end)
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Spell, function(tooltip, data)
            OnSpellTip(tooltip, data and data.id)
        end)
    else
        -- Classic Era has no TooltipDataProcessor (ERA-01): the old per-tooltip
        -- OnTooltipSetItem / OnTooltipSetSpell scripts instead
        for _, tip in ipairs({ GameTooltip, ItemRefTooltip }) do
            if tip and tip.HasScript and tip:HasScript("OnTooltipSetItem") then
                tip:HookScript("OnTooltipSetItem", function(self)
                    local _, link = self:GetItem()
                    local id = link and tonumber(link:match("item:(%d+)"))
                    OnItemTip(self, id)
                end)
            end
            if tip and tip.HasScript and tip:HasScript("OnTooltipSetSpell") then
                tip:HookScript("OnTooltipSetSpell", function(self)
                    local _, id = self:GetSpell()
                    OnSpellTip(self, id)
                end)
            end
        end
    end

    -- Quest tooltips via TooltipDataProcessor: show QuestID only (no icon)
    if hasTDP and Enum.TooltipDataType.Quest then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Quest, function(tooltip, data)
            if not ShouldShowIDs() then return end
            local id = data and data.id
            if id and id > 0 then
                AddIDLine(tooltip, "QuestID", id)
                Refresh(tooltip)
            end
        end)
    end

    -- Quest log list tooltips: built by QuestMapLogTitleButton_OnEnter which
    -- calls GameTooltip:SetText() + AddLine() directly, bypassing both
    -- TooltipDataProcessor and SetHyperlink. The button has .questID.
    -- Hook the global function and append our ID line after the tooltip is built.
    if QuestMapLogTitleButton_OnEnter then
        hooksecurefunc("QuestMapLogTitleButton_OnEnter", function(self)
            if not ShouldShowIDs() then return end
            if self and self.questID and GameTooltip:IsShown() then
                AddIDLine(GameTooltip, "QuestID", self.questID)
                Refresh(GameTooltip)
            end
        end)
    end

    -- Chat quest links go through SetHyperlink("quest:XXXXX:...").
    -- Hook both GameTooltip and ItemRefTooltip to catch those.
    -- Skip quest links when TooltipDataProcessor.Quest is available — that hook
    -- already handles them, and firing both would show the ID line twice.
    local _tdpHandlesQuest = hasTDP and Enum.TooltipDataType.Quest ~= nil
    local function OnSetHyperlink(tooltip, link)
        if not ShouldShowIDs() then return end
        if not link then return end
        local questID = link:match("^quest:(%d+)")
        if questID and not _tdpHandlesQuest then
            local id = tonumber(questID)
            if id and id > 0 then
                AddIDLine(tooltip, "QuestID", id)
                Refresh(tooltip)
            end
        end
    end
    hooksecurefunc(GameTooltip, "SetHyperlink", OnSetHyperlink)
    if ItemRefTooltip then
        hooksecurefunc(ItemRefTooltip, "SetHyperlink", OnSetHyperlink)
    end
end

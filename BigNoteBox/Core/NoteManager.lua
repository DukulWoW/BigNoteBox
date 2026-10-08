-- BigNoteBox Core/NoteManager.lua — Note CRUD and autosave
-- Notes live in BigNoteBoxNotesDB (separate SavedVariables).
-- Settings/UI state live in BigNoteBoxDB.
-- This separation means /bnb reset never touches notes.

local BNB = BigNoteBox
local L   = BNB.L

-- Convenience accessor — keeps all reads/writes in one place
local function NDB() return BNB.NotesDB() end

--------------------------------------------------------------------------------
-- TAG NORMALIZATION
-- Always stores tags in Title Case (first letter upper, rest lower).
-- "book", "BOOK", "bOoK" all become "Book".
-- Called at every tag write point so the index stays consistent.
--------------------------------------------------------------------------------
function BNB.NormalizeTag(s)
    if not s or s == "" then return s end
    return s:sub(1,1):upper() .. s:sub(2):lower()
end

--------------------------------------------------------------------------------
-- NOTE ID GENERATOR
--------------------------------------------------------------------------------
-- Seconds plus 32 random bits, drawn again until the id is free in both notes
-- and trash. A bulk import or migration creates many notes within one second,
-- and the old 16-bit suffix could hand out the same id twice (BUG-01). Ids are
-- only ever compared as strings, so the longer form mixes fine with old ones.
-- Moved from Database.lua (ARCH-06).
function BNB.GenerateID()
    local ndb   = BNB.NotesDB()
    local notes = ndb and ndb.notes or {}
    local trash = ndb and ndb.trash or {}
    local id
    repeat
        id = string.format("bnb-%08x%04x%04x", time(), math.random(0, 0xFFFF), math.random(0, 0xFFFF))
    until not notes[id] and not trash[id]
    return id
end

--------------------------------------------------------------------------------
-- TRASH ENABLED
--------------------------------------------------------------------------------
-- True when trash is active (the Trash checkbox on and trashRetainDays > 0).
-- Used by delete call sites to skip the confirmation popup — moving to trash
-- is non-destructive, so there is nothing to confirm. Moved from
-- SlashCommands.lua (ARCH-06).
function BNB.TrashEnabled()
    if not (BigNoteBoxDB and BigNoteBoxDB.trashFeature ~= false) then return false end
    local days = BigNoteBoxDB.trashRetainDays
    if days == nil then days = BNB.DEFAULTS.trashRetainDays end
    return days > 0
end

--------------------------------------------------------------------------------
-- TRASH BUTTON SYNC
-- Reads trash directly so it works whether or not TrashWindow is open.
-- Called by every function that mutates the trash (Delete, Restore, Empty)
-- and also by Initialize on login.
--------------------------------------------------------------------------------
function BNB.SyncTrashBtnState()
    local btn = BNB._toolbarTrashBtn
    if not btn then return end
    local ndb = BNB.NotesDB()
    local hasItems = ndb and ndb.trash and next(ndb.trash) ~= nil or false
    btn:SetIconEnabled(hasItems)
end

-- The toolbar's Tag Manager button is greyed while no note has a tag, like
-- Trash (ALL-273). Follows the note messages below; first call at login
-- (Core/Initialize.lua, beside SyncTrashBtnState).
function BNB.SyncTagsBtnState()
    local btn = BNB._toolbarTagsBtn
    if not btn then return end
    local hasTags = next(BNB.TagIndex()) ~= nil
    btn:SetIconEnabled(hasTags)
end
local function SyncTagsOnTagChange(_, _, fields)
    if fields == nil or fields.tags ~= nil or fields._clear then BNB.SyncTagsBtnState() end
end
BNB.RegisterMessage("TagsButton", "NoteCreated",  function() BNB.SyncTagsBtnState() end)
BNB.RegisterMessage("TagsButton", "NoteDeleted",  function() BNB.SyncTagsBtnState() end)
BNB.RegisterMessage("TagsButton", "NoteRestored", function() BNB.SyncTagsBtnState() end)
BNB.RegisterMessage("TagsButton", "NoteChanged",  SyncTagsOnTagChange)

-- The toolbar's Alarms button is greyed while no note has an alarm, like
-- Trash and Tags (ALL-352). Every alarm write is an UpdateNote of the alarm
-- field (SaveAlarm, Features/AlarmManager.lua), so NoteChanged covers it.
function BNB.SyncAlarmsBtnState()
    local btn = BNB._toolbarAlarmsBtn
    if not btn then return end
    local ndb = BNB.NotesDB()
    local has = false
    for _, n in pairs(ndb and ndb.notes or {}) do
        if n.alarm then has = true; break end
    end
    btn:SetIconEnabled(has)
end
local function SyncAlarmsOnChange(_, _, fields)
    if fields == nil or fields.alarm ~= nil or fields._clear then BNB.SyncAlarmsBtnState() end
end
BNB.RegisterMessage("AlarmsButton", "NoteCreated",  function() BNB.SyncAlarmsBtnState() end)
BNB.RegisterMessage("AlarmsButton", "NoteDeleted",  function() BNB.SyncAlarmsBtnState() end)
BNB.RegisterMessage("AlarmsButton", "NoteRestored", function() BNB.SyncAlarmsBtnState() end)
BNB.RegisterMessage("AlarmsButton", "NoteChanged",  SyncAlarmsOnChange)

--------------------------------------------------------------------------------
-- TAG INDEX HELPERS
-- BNB.TagIndex() maps tag → { [noteID] = true }.
-- All mutations go through these helpers so the index stays consistent.
-- Keys are stored in original case (as typed); lookups are case-insensitive
-- at the call site where needed (e.g. autocomplete prefix match).
-- Runtime-only (SV-05, ALL-136.8): built from the active notes set the first
-- time it is asked for, never saved. It used to live in BigNoteBoxDB, where
-- any write that skipped these helpers left it wrong across sessions and a
-- dev-mode switch kept the other notes set's index.
--------------------------------------------------------------------------------
local _tagIndex

-- The tag index, built on first use. Read-only for callers: change tags
-- through UpdateNote / RenameTag / DeleteTag / RemoveNoteTag.
function BNB.TagIndex()
    if _tagIndex then return _tagIndex end
    local ndb = BNB.NotesDB()
    -- No notes set yet (or the BigNoteBoxDB addon is missing): nothing to
    -- index, and nothing cached, so a later call still builds the real one
    if not (ndb and ndb.notes) then return {} end
    _tagIndex = {}
    for id, note in pairs(ndb.notes) do
        for _, tag in ipairs(note.tags or {}) do
            if tag ~= "" then
                if not _tagIndex[tag] then _tagIndex[tag] = {} end
                _tagIndex[tag][id] = true
            end
        end
    end
    return _tagIndex
end

local function TagDB()
    return BNB.TagIndex()
end

function BNB.TagIndexAdd(id, tag)
    if not id or not tag or tag == "" then return end
    local idx = TagDB(); if not idx then return end
    if not idx[tag] then idx[tag] = {} end
    idx[tag][id] = true
end

function BNB.TagIndexRemove(id, tag)
    if not id or not tag then return end
    local idx = TagDB(); if not idx then return end
    if idx[tag] then
        idx[tag][id] = nil
        -- Clean up empty sets
        if next(idx[tag]) == nil then idx[tag] = nil end
    end
end

-- Rebuild the entire index from live notes (after a bulk change such as
-- Delete All Notes, or as a recovery tool).
function BNB.TagIndexRebuild()
    _tagIndex = nil
    BNB.TagIndex()
end

-- A note field in lower case (PERF-07), nil for a missing or empty field.
-- Kept per note until the field changes: strings are interned, so that check
-- is one compare. Search and the sorts call this once per note or comparison,
-- where they used to lower-case the title and the whole body every time.
local _lowerCache = setmetatable({}, { __mode = "k" })
local function LowerOf(note, field)
    local s = note[field]
    if not s or s == "" then return nil end
    local c = _lowerCache[note]
    if not c then c = {}; _lowerCache[note] = c end
    local e = c[field]
    if not e or e[1] ~= s then e = { s, s:lower() }; c[field] = e end
    return e[2]
end
BNB.NoteLower = LowerOf

-- The first situation in lower case, cached the same way ("by location" sort;
-- situations are a list since ALL-232)
local function SituationLower(note)
    local s = BNB.FirstSituation(note)
    if not s then return nil end
    local c = _lowerCache[note]
    if not c then c = {}; _lowerCache[note] = c end
    local e = c._situation
    if not e or e[1] ~= s then e = { s, s:lower() }; c._situation = e end
    return e[2]
end

-- Sort key for "A-Z by title": untitled notes sort last.
function BNB.NoteTitleKey(note)
    return LowerOf(note, "title") or "\255"
end

-- Returns a sorted list of { tag, count } for all known tags.
-- count = number of live notes carrying that tag.
function BNB.GetAllTags()
    local idx = TagDB(); if not idx then return {} end
    local out = {}
    for tag, ids in pairs(idx) do
        local count = 0
        for _ in pairs(ids) do count = count + 1 end
        if count > 0 then
            out[#out + 1] = { tag = tag, count = count, _key = tag:lower() }
        end
    end
    table.sort(out, function(a, b)
        return a._key < b._key
    end)
    return out
end

-- Rename a tag across all notes that carry it.
function BNB.RenameTag(oldTag, newTag)
    newTag = newTag and newTag:match("^%s*(.-)%s*$") or ""
    if newTag == "" then return false end
    newTag = BNB.NormalizeTag(newTag)
    if newTag == oldTag then return false end
    local idx = TagDB(); if not idx then return false end
    local ids = idx[oldTag]
    if not ids then return false end
    local ndb = BNB.NotesDB()
    if not ndb or not ndb.notes then return false end
    -- Update every note that has oldTag
    for id in pairs(ids) do
        local note = ndb.notes[id]
        if note and note.tags then
            local newTags, already = {}, false
            for _, t in ipairs(note.tags) do
                if t == oldTag then
                    -- Replace with newTag — but only if newTag not already present
                    if not already then newTags[#newTags + 1] = newTag; already = true end
                elseif t == newTag then
                    already = true
                    newTags[#newTags + 1] = t
                else
                    newTags[#newTags + 1] = t
                end
            end
            note.tags = newTags
        end
        -- Update index: move id from oldTag to newTag
        BNB.TagIndexAdd(id, newTag)
    end
    -- Remove old key entirely
    idx[oldTag] = nil
    -- Written straight onto the notes (not an edit: `updated` stays), so the
    -- message is sent here (ARCH-02)
    for id in pairs(ids) do
        local note = ndb.notes[id]
        if note then BNB.SendMessage("NoteChanged", id, { tags = note.tags }) end
    end
    return true
end

-- Delete a tag from every note that carries it.
function BNB.DeleteTag(tag)
    local idx = TagDB(); if not idx then return end
    local ids = idx[tag]
    if not ids then return end
    local ndb = BNB.NotesDB()
    if not ndb or not ndb.notes then return end
    for id in pairs(ids) do
        local note = ndb.notes[id]
        if note and note.tags then
            local newTags = {}
            for _, t in ipairs(note.tags) do
                if t ~= tag then newTags[#newTags + 1] = t end
            end
            note.tags = newTags
        end
    end
    idx[tag] = nil
    for id in pairs(ids) do
        local note = ndb.notes[id]
        if note then BNB.SendMessage("NoteChanged", id, { tags = note.tags }) end
    end
end

-- Remove one tag from one note only (ALL-83 tag manager context menu).
function BNB.RemoveNoteTag(id, tag)
    local ndb = NDB(); if not ndb or not ndb.notes then return end
    local note = ndb.notes[id]; if not note or not note.tags then return end
    local newTags = {}
    for _, t in ipairs(note.tags) do
        if t ~= tag then newTags[#newTags + 1] = t end
    end
    note.tags = newTags
    BNB.TagIndexRemove(id, tag)
    BNB.SendMessage("NoteChanged", id, { tags = newTags })
end

--------------------------------------------------------------------------------
-- QUICK NOTE — lowest available gap in the sequence
-- If "Quick Note", "Quick Note 2", "Quick Note 3" exist but "Quick Note 4"
-- was deleted, the next one is "Quick Note 4" — not "Quick Note 5".
-- Rule: base title = "Quick Note" (no number), then 2, 3, 4, ...
-- (WoW convention: first is unnumbered, subsequent get a number from 2 up.)
-- One builder for the list's Quick Note button and the quick note key (CMP-05).
-- The localized base is escaped before it goes into a pattern: a translation
-- with "-" or "(" in it never matched, and every quick note came out unnumbered.
--------------------------------------------------------------------------------
function BNB.NextQuickNoteTitle()
    local base  = L["NL_QUICK_NOTE_BTN"]
    local pat   = "^" .. base:gsub("%p", "%%%0") .. " (%d+)$"
    local taken = {}
    for _, note in pairs((NDB() or {}).notes or {}) do
        local t = note.title or ""
        if t == base then
            taken[1] = true
        else
            local n = t:match(pat)
            if n then taken[tonumber(n)] = true end
        end
    end
    if not taken[1] then return base end
    local i = 2
    while taken[i] do i = i + 1 end
    return base .. " " .. i
end

-- Creates the next quick note (title + note icon) and returns its id, or nil.
-- Opening it is the caller's job: BNB.ShowQuickNote (main window) or
-- BNB.Sticky.OpenQuick.
-- The tag every quick note gets (ALL-152). Not translated, like the source
-- tags Quest / Gossip / Book / Letter: whether tags follow the language is
-- ALL-108, for all of them at once
BNB.QUICK_NOTE_TAG = "Quick Note"

function BNB.CreateQuickNote()
    local id = BNB.CreateNote(BNB.NextQuickNoteTitle())
    if not id then return nil end
    BNB.UpdateNote(id, { icon = "Interface\\Icons\\INV_Misc_Note_04", tags = { BNB.QUICK_NOTE_TAG } })
    return id
end

--------------------------------------------------------------------------------
-- CREATE
--------------------------------------------------------------------------------
-- Where a new note goes: Settings > Notes "New notes belong to"
-- (BigNoteBoxDB.newNoteScope, ALL-267). nil = the selected tab (a character
-- tab -> that character, anything else -> global), "global", or "char" = the
-- character being played. The New note dialog starts its dropdown here.
function BNB.NewNoteScope()
    local mode = BigNoteBoxDB and BigNoteBoxDB.newNoteScope
    if mode == "global" then return "global" end
    if mode == "char" and BNB.currentChar then return "char:" .. BNB.currentChar end
    local activeKey = BNB.Sidebar and BNB.Sidebar.GetActive() or "all"
    if activeKey and activeKey:find("^char:") then return activeKey end
    return "global"
end

function BNB.CreateNote(title, body)
    if not NDB() then return nil end
    local id  = BNB.GenerateID()
    local now = time()
    local newScope = BNB.NewNoteScope()
    -- Capture creation coordinates and zone via C_Map if available.
    local coordX, coordY, coordMapID, coordZone, coordSubzone
    if C_Map and C_Map.GetBestMapForUnit and C_Map.GetPlayerMapPosition then
        local mapID = C_Map.GetBestMapForUnit("player")
        if mapID then
            local pos = C_Map.GetPlayerMapPosition(mapID, "player")
            if pos then
                coordX    = math.floor(pos.x * 10000 + 0.5) / 100  -- two decimal places
                coordY    = math.floor(pos.y * 10000 + 0.5) / 100
                coordMapID = mapID
                local mapInfo = C_Map.GetMapInfo(mapID)
                coordZone = mapInfo and mapInfo.name or nil
                coordSubzone = BNB.CurrentSubzone()
            end
        end
    end
    NDB().notes[id] = {
        id           = id,
        title        = title or "",
        body         = body  or "",
        tags         = {},
        situations   = nil,   -- { "zone:Orgrimmar", ... } (ALL-232)
        scope        = newScope,
        icon         = nil,
        titleColor   = nil,   -- { r, g, b } or nil for default
        fontOverride = nil,   -- font id string or nil for global setting
        borderOverride = nil, -- LSM border name or nil for none
        lineHeight   = nil,   -- sticky-note-only line height key (not used in main editor)
        pinned       = false, -- pinned notes always sort to top
        locked       = nil,   -- nil = follow global lockNotes setting
        -- context fields: set via NoteConfig Situation tab
        -- contextDisplay: nil/"popup" = toast, "sticky" = open as sticky
        -- contextLeave:   nil/"keep" = do nothing, "minimize", "hide"
        -- contextTrigger: nil = on arriving, "leave", "both"
        -- contextFreq:    nil = every time, "session", "day", "daily", "weekly", "once"
        coordX       = coordX,    -- map X coord at creation time (0-100 scale), or nil
        coordY       = coordY,    -- map Y coord at creation time (0-100 scale), or nil
        coordMapID   = coordMapID, -- map ID at creation time, or nil
        coordZone    = coordZone,  -- zone name at creation time, or nil
        coordSubzone = coordSubzone, -- sub-zone at creation time, or nil (ALL-354)
        richMode     = false,      -- true = rich note with markup/SimpleHTML rendering
        created      = now,
        updated      = now,
    }
    table.insert(NDB().noteOrder, 1, id)
    -- Index any tags (none on new notes, but future-safe)
    for _, tag in ipairs(NDB().notes[id].tags or {}) do
        BNB.TagIndexAdd(id, tag)
    end
    BNB.SendMessage("NoteCreated", id)
    return id
end

--------------------------------------------------------------------------------
-- COPY  (Duplicate and Copy/Move share this, so a copy keeps every field)
--------------------------------------------------------------------------------
-- Fields a copy never inherits: identity and timestamps, the creation position
-- (the copy is created here and now), the source's own edit history, and the
-- alarm (one reminder would ring twice). Everything else, including richMode,
-- tasks, attachments and inspect data, is copied. The hand-written field lists
-- this replaced each missed some (a rich note duplicated as a normal one).
-- The set is the `nocopy` fields of the note schema (Core/NoteFields.lua).
local COPY_SKIP = {}
for _, def in ipairs(BNB.NOTE_FIELDS) do
    if def.nocopy then COPY_SKIP[def.key] = true end
end
-- (NoteHistory.lua used this set until SV-11; snapshots now keep their own
-- short list of content fields, SNAP_FIELDS there.)
BNB.NOTE_COPY_SKIP = COPY_SKIP

-- Full recursive copy, so the new note shares no table with the source
-- (the old copies shared the tags table: editing one note's tags changed both)
local DeepCopy = BNB.DeepCopy

-- Copies note srcID into a new note and returns the new id. The copy keeps the
-- source's scope unless overrides says otherwise; overrides (optional) replaces
-- fields after the copy, e.g. { title = "...", scope = "char:X" }.
function BNB.CopyNote(srcID, overrides)
    local src = NDB() and NDB().notes[srcID]
    if not src then return nil end
    local newID = BNB.CreateNote(src.title, src.body)
    if not newID then return nil end
    local fields = {}
    for k, v in pairs(src) do
        if not COPY_SKIP[k] then fields[k] = DeepCopy(v) end
    end
    -- nil scope means global; CreateNote would otherwise use the sidebar's
    if fields.scope == nil then fields.scope = "global" end
    if overrides then
        for k, v in pairs(overrides) do fields[k] = v end
    end
    -- UpdateNote indexes tags only when the field is present
    if fields.tags == nil then fields.tags = {} end
    BNB.UpdateNote(newID, fields)
    return newID
end

-- Marks a note as opened just now, for the Oracle's "recently opened"
-- weight (ALL-69.3). Written straight to the note: going through UpdateNote
-- would change `updated`, and opening is not editing.
function BNB.StampOpened(id)
    local note = id and NDB() and NDB().notes[id]
    if note then note.lastOpened = time() end
end

--------------------------------------------------------------------------------
-- UPDATE
-- Every change to a note goes through here: tags are deduped and indexed, and
-- `updated` is stamped. Pass opts.noTouch for runtime state that is not an
-- edit (an alarm dismissed or snoozed, a task ticked or reset; SV-08): the
-- fields are written but `updated` stays, so "Edited" sort and the Oracle's
-- recently-edited weight do not move.
--------------------------------------------------------------------------------
function BNB.UpdateNote(id, fields, opts)
    local note = NDB().notes[id]
    if not note then return end
    -- Capture old tags before mutation if tags are changing
    local oldTags = fields.tags and note.tags or nil
    -- A note never carries the same tag twice, whichever caller built the list
    if fields.tags then
        local seen, uniq = {}, {}
        for _, tag in ipairs(fields.tags) do
            if not seen[tag] then seen[tag] = true; uniq[#uniq + 1] = tag end
        end
        fields.tags = uniq
    end
    for k, v in pairs(fields) do
        if k ~= "_clear" then note[k] = v end
    end
    -- _clear: array of field names to explicitly set to nil
    if fields._clear then
        for _, k in ipairs(fields._clear) do note[k] = nil end
    end
    if not (opts and opts.noTouch) then note.updated = time() end
    -- Update tag index when tags changed
    if oldTags then
        -- Remove all old tag entries for this note
        for _, tag in ipairs(oldTags) do
            BNB.TagIndexRemove(id, tag)
        end
        -- Add all new tag entries
        for _, tag in ipairs(note.tags or {}) do
            BNB.TagIndexAdd(id, tag)
        end
    end
    BNB.SendMessage("NoteChanged", id, fields)
end

--------------------------------------------------------------------------------
-- DELETE  (moves to trash while BNB.TrashEnabled(), unless permanent is true)
--------------------------------------------------------------------------------
-- Data half of a delete: trash copy, live removal, sticky, tag index, undo.
-- No list/trash window refresh, so a bulk delete can refresh once at the end
-- (ALL-58: 48 per-note refreshes froze the game for ~3 seconds).
-- Trash follows BNB.TrashEnabled(), the same test the delete popups use, so a
-- "cannot be undone" popup really deletes. It used to check trashRetainDays
-- only, so with Trash switched off notes still went to a hidden trash.
local function RemoveNote(id, permanent)
    local note = NDB().notes[id]
    if not note then return false end

    if not permanent and BNB.TrashEnabled and BNB.TrashEnabled() then
        -- Move to trash: full copy with deletedAt timestamp
        local ndb = NDB()
        if ndb.trash == nil then ndb.trash = {} end
        local trashed = {}
        for k, v in pairs(note) do trashed[k] = v end
        trashed.deletedAt = time()
        ndb.trash[id] = trashed
        BNB.SendMessage("TrashChanged")
    end

    -- Remove from live notes and order
    local deletedTags = note.tags or {}
    NDB().notes[id] = nil
    local order = NDB().noteOrder
    for i = #order, 1, -1 do
        if order[i] == id then table.remove(order, i); break end
    end
    if BigNoteBoxDB and BigNoteBoxDB.selectedNoteID == id then
        BigNoteBoxDB.selectedNoteID = nil
    end
    -- Close any open sticky for this note
    if BNB.Sticky and BNB.Sticky.Close then BNB.Sticky.Close(id) end
    -- Remove deleted note from tag index
    for _, tag in ipairs(deletedTags) do
        BNB.TagIndexRemove(id, tag)
    end
    -- Free runtime undo/redo memory for this note
    if BNB.UndoClearNote then BNB.UndoClearNote(id) end
    return true
end

-- UI half: editor selection. The list follows NoteDeleted (UI/NoteList.lua;
-- SelectNote redraws it first), the Trash window and button TrashChanged.
local function RefreshAfterDelete()
    if BNB.mainFrame and BNB.mainFrame:IsShown() then
        if BNB.SelectNote then BNB.SelectNote(nil) end
    end
end

-- permanent = true skips the trash even while it is on ("Delete permanently")
function BNB.DeleteNote(id, permanent)
    if not RemoveNote(id, permanent) then return end
    RefreshAfterDelete()
    BNB.SendMessage("NoteDeleted", { id }, permanent)
end

-- Bulk delete: every id goes through the same path as DeleteNote, the UI
-- refreshes once. Ids that are no longer live notes are skipped. Returns the
-- number of notes actually deleted.
function BNB.DeleteNotes(ids, permanent)
    if not ids then return 0 end
    local removed = {}
    for _, id in ipairs(ids) do
        if RemoveNote(id, permanent) then removed[#removed + 1] = id end
    end
    local n = #removed
    if n > 0 then
        RefreshAfterDelete()
        BNB.SendMessage("NoteDeleted", removed, permanent)
    end
    return n
end

--------------------------------------------------------------------------------
-- PURGE  (hard-delete with no trash, no UI callbacks — used for empty-note cancel)
--------------------------------------------------------------------------------
function BNB.PurgeNote(id)
    if not id then return end
    local ndb = NDB()
    local tags = ndb.notes[id] and ndb.notes[id].tags or {}
    ndb.notes[id] = nil
    local order = ndb.noteOrder
    for i = #order, 1, -1 do
        if order[i] == id then table.remove(order, i); break end
    end
    if BigNoteBoxDB and BigNoteBoxDB.selectedNoteID == id then
        BigNoteBoxDB.selectedNoteID = nil
    end
    for _, tag in ipairs(tags) do BNB.TagIndexRemove(id, tag) end
    if BNB.Sticky and BNB.Sticky.Close then BNB.Sticky.Close(id) end
    -- Still no UI refresh here; the message is data only (permanent = true)
    BNB.SendMessage("NoteDeleted", { id }, true)
end

--------------------------------------------------------------------------------
-- RESTORE  (move a note from trash back to live notes)
--------------------------------------------------------------------------------
function BNB.RestoreNote(id)
    local ndb = NDB()
    if not ndb.trash or not ndb.trash[id] then return end

    local note = ndb.trash[id]
    ndb.trash[id] = nil

    -- Strip the trash-only field
    note.deletedAt = nil

    -- Re-insert into live notes at top of order
    ndb.notes[id] = note
    table.insert(ndb.noteOrder, 1, id)

    -- Re-index tags for the restored note
    for _, tag in ipairs(note.tags or {}) do
        BNB.TagIndexAdd(id, tag)
    end
    BNB.SendMessage("TrashChanged")
    BNB.SendMessage("NoteRestored", id)
end

--------------------------------------------------------------------------------
-- PURGE  (remove trash entries older than trashRetainDays — called on login)
--------------------------------------------------------------------------------
function BNB.PurgeTrash()
    local ndb = NDB()
    if not ndb.trash then ndb.trash = {}; return end
    local days = BigNoteBoxDB and BigNoteBoxDB.trashRetainDays
    if days == nil then days = 30 end
    if days == 0 then return end  -- trash disabled; nothing to purge
    local cutoff = time() - (days * 86400)
    local purged = false
    for id, note in pairs(ndb.trash) do
        if (note.deletedAt or 0) < cutoff then
            ndb.trash[id] = nil
            purged = true
        end
    end
    if purged then BNB.SendMessage("TrashChanged") end
end

--------------------------------------------------------------------------------
-- PURGE TRASHED  (permanently delete these trash entries; the Trash window's
-- Delete and Delete selected). Every write to the trash lives in this file
-- and sends TrashChanged (ARCH-02).
--------------------------------------------------------------------------------
function BNB.PurgeTrashed(ids)
    local trash = NDB() and NDB().trash
    if not (trash and ids) then return end
    for _, id in ipairs(ids) do trash[id] = nil end
    BNB.SendMessage("TrashChanged")
end

-- A removed character's trashed notes go where its live notes went, so a
-- restore lands on a character that still exists; its situation counters go
-- too (ALL-249, UI/CharacterRemove.lua)
function BNB.RescopeTrash(fromScope, toScope, charKey)
    local trash = NDB() and NDB().trash
    if not trash then return end
    local changed = false
    for _, note in pairs(trash) do
        if note.scope == fromScope then note.scope = toScope; changed = true end
        if charKey and note.contextSeen then note.contextSeen[charKey] = nil end
    end
    if changed then BNB.SendMessage("TrashChanged") end
end

--------------------------------------------------------------------------------
-- EMPTY TRASH  (permanently delete everything in trash)
--------------------------------------------------------------------------------
function BNB.EmptyTrash()
    local ndb = NDB()
    ndb.trash = {}
    BNB.SendMessage("TrashChanged")
end

--------------------------------------------------------------------------------
-- GET ORDERED NOTES
--------------------------------------------------------------------------------
-- noFloat: when true, pinned notes are NOT floated to top (used by drag-reorder
--          in custom mode so drag indices match the visual flat order)
-- allScopes: when true, skip scope filtering (used by export and search-all)
function BNB.GetOrderedNotes(filterText, tagFilter, noFloat, allScopes)
    if not NDB() then return {} end
    local results = {}
    local lower    = filterText and filterText ~= "" and filterText:lower() or nil
    local lowerTag = tagFilter and tagFilter:lower() or nil
    local favOnly  = BNB._favFilterActive == true
    local taskOnly = BNB._taskFilterActive == true

    -- Sidebar filter: "all" = no scope restriction,
    -- "global" = only global-scoped notes,
    -- "char:X" = only notes with that char scope.
    local sidebarKey = (not allScopes)
        and BNB.Sidebar and BNB.Sidebar.GetActive() or "all"

    for _, id in ipairs(NDB().noteOrder) do
        local note = NDB().notes[id]
        if note then
            local passScope = true
            if not allScopes then
                local sc = note.scope
                if sidebarKey == "all" then
                    -- Show all notes from all characters and global
                    passScope = true
                elseif sidebarKey == "global" then
                    -- Only global-scoped notes
                    if sc and sc ~= "global" then passScope = false end
                else
                    -- Specific character slot: exact scope match only
                    if sc ~= sidebarKey then passScope = false end
                end
            end

            local passFav  = true
            local passText = true
            local passTag  = true
            local passTask = true

            if passScope then
                if favOnly then
                    passFav = note.favorited == true
                end
                if taskOnly then
                    passTask = BNB.Task and BNB.Task.HasTasks(id) or false
                end
                if lower then
                    local lt, lb = LowerOf(note, "title"), LowerOf(note, "body")
                    local titleMatch = lt and lt:find(lower, 1, true)
                    local bodyMatch  = lb and lb:find(lower, 1, true)
                    passText = titleMatch or bodyMatch
                end
                if lowerTag then
                    passTag = false
                    for _, t in ipairs(note.tags or {}) do
                        if t:lower() == lowerTag then passTag = true; break end
                    end
                end
            end

            if passScope and passFav and passTask and passText and passTag then
                results[#results + 1] = note
            -- Always include the currently selected new (empty) note so it
            -- stays visible in the list while the user is setting it up,
            -- even if an active search filter would otherwise hide it.
            elseif id == BNB._currentNoteID then
                local liveTitle = BNB._editorTitle and
                    not BNB._editorTitle._showingPlaceholder and
                    BNB._editorTitle:GetText() or note.title
                local liveBody  = BNB._editorBody and
                    not BNB._editorBody._showingPlaceholder and
                    BNB._editorBody:GetText() or note.body
                if (not liveTitle or liveTitle == "") and (not liveBody or liveBody == "") then
                    results[#results + 1] = note
                end
            end
        end
    end

    local db     = BigNoteBoxDB
    local sortBy = db and db.sortBy or BNB.DEFAULTS.sortBy
    local asc    = db and db.sortAsc or BNB.DEFAULTS.sortAsc

    -- Custom mode: results are already in noteOrder sequence from the ipairs above.
    -- Skip sort entirely — table.sort is not stable, so even a no-op cmp can shuffle
    -- equal elements.  noFloat path (drag reorder) also skips pin-floating.
    if sortBy == "custom" then
        if noFloat then
            return results   -- flat, exact noteOrder sequence
        end
        -- Non-noFloat custom: just float pinned notes to top, preserve noteOrder otherwise.
        -- We do a stable partition rather than table.sort to avoid shuffling.
        local pinned, rest = {}, {}
        for _, note in ipairs(results) do
            if note.pinned then pinned[#pinned+1] = note
            else                rest[#rest+1]    = note end
        end
        local out = {}
        for _, n in ipairs(pinned) do out[#out+1] = n end
        for _, n in ipairs(rest)   do out[#out+1] = n end
        return out
    end

    local function cmp(a, b)
        -- Pinned always floats to top (skipped for noFloat/drag path)
        if not noFloat then
            local ap, bp = a.pinned and 1 or 0, b.pinned and 1 or 0
            if ap ~= bp then return ap > bp end
            -- Both pinned: always A-Z by title, independent of active sort mode
            if a.pinned and b.pinned then
                local at = LowerOf(a, "title") or "\255"
                local bt = LowerOf(b, "title") or "\255"
                if at ~= bt then return at < bt end
                return (a.id or "") < (b.id or "")
            end
        end
        -- (The "favorites" sort mode is gone: settings migration v3 resets it.)

        local av, bv
        if sortBy == "creation" then
            av, bv = a.created or 0, b.created or 0
        elseif sortBy == "edited" then
            av, bv = a.updated or 0, b.updated or 0
        elseif sortBy == "alpha" then
            -- Alpha: A-Z is ascending (asc=true), Z-A is descending (asc=false).
            -- Untitled notes sort to the end regardless of direction.
            av = LowerOf(a, "title") or "\255"
            bv = LowerOf(b, "title") or "\255"
        elseif sortBy == "location" then
            -- Notes with no situation sort to the end regardless of direction.
            av = SituationLower(a) or "\255"
            bv = SituationLower(b) or "\255"
        else
            av, bv = a.created or 0, b.created or 0
        end

        if av ~= bv then
            if asc then return av < bv else return av > bv end
        end
        -- Stable tiebreaker: consistent order for notes with identical sort values
        return (a.id or "") > (b.id or "")
    end

    table.sort(results, cmp)
    return results
end

--------------------------------------------------------------------------------
-- GET NOTE
--------------------------------------------------------------------------------
function BNB.GetNote(id)
    local ndb = id and NDB()
    return ndb and ndb.notes and ndb.notes[id] or nil   -- notes nil: Factory Reset before its reload (ALL-284)
end

--------------------------------------------------------------------------------
-- SAVE CURRENT NOTE
--------------------------------------------------------------------------------
function BNB.SaveCurrentNote()
    if not BNB._dirty then return end
    local id = BNB._currentNoteID
    if not id then BNB.Editor.SetDirty(false); return end
    local note = BNB.GetNote(id)
    if not note then BNB.Editor.SetDirty(false); return end

    local title = BNB._editorTitle and BNB._editorTitle:GetText() or note.title
    local body  = BNB._editorBody  and BNB._editorBody:GetText()  or note.body

    if BNB._editorTitle and BNB._editorTitle._showingPlaceholder then title = "" end
    if BNB._editorBody  and BNB._editorBody._showingPlaceholder  then body  = "" end
    if title == L["NOTE_TITLE_HINT"] then title = "" end
    if body  == L["NOTE_BODY_HINT"]  then body  = "" end

    -- Block saving a note with no title
    if title == "" then
        BNB:Print("|cffff6666Notes must have a title.|r Please add a title before saving.")
        if BNB._editorTitle then BNB._editorTitle:SetFocus() end
        return
    end

    BNB.UpdateNote(id, { title = title, body = body })
    BNB.Editor.SetDirty(false)
    if BNB.UpdateSaveButtonState then BNB.UpdateSaveButtonState() end

    -- Keep NoteConfig title in sync if open
    if BNB._syncNoteConfigTitle then BNB._syncNoteConfigTitle() end
    -- Refresh any open post-it for this note
    if BNB.Sticky and BNB.Sticky.RefreshNote then BNB.Sticky.RefreshNote(id) end
    -- Rebuild tag strip (save doesn't change tags but keeps it current)
    if BNB.RefreshTagStrip then BNB.RefreshTagStrip() end
end

--------------------------------------------------------------------------------
-- AUTOSAVE (ALL-52)
-- BigNoteBoxDB.saveMode: nil = automatic (default), "manual" = the Save button,
-- a note switch or closing the window saves, nothing else. Automatic saves on
-- the undo snapshot rhythm: undoIdleDelay after the last edit, and at least
-- every undoForcedInterval while typing without a pause. Both modes save on
-- logout, so a /reload never loses text (OnHide does not run on a reload).
--------------------------------------------------------------------------------
function BNB.IsAutoSave()
    return not (BigNoteBoxDB and BigNoteBoxDB.saveMode == "manual")
end

-- Saves the open note without SaveCurrentNote's title check: an empty title is
-- not an error here, the text is saved and the stored title kept. BNB._dirty
-- stays set while the title is empty, so the title guards on note switch and
-- window close still apply.
function BNB.SaveCurrentNoteQuiet()
    if not BNB._dirty then return end
    local id   = BNB._currentNoteID
    local note = id and BNB.GetNote(id)
    if not note then BNB.Editor.SetDirty(false); return end

    local title = BNB._editorTitle and BNB._editorTitle:GetText() or note.title
    local body  = BNB._editorBody  and BNB._editorBody:GetText()  or note.body
    if BNB._editorTitle and BNB._editorTitle._showingPlaceholder then title = "" end
    if BNB._editorBody  and BNB._editorBody._showingPlaceholder  then body  = "" end
    if title == L["NOTE_TITLE_HINT"] then title = "" end
    if body  == L["NOTE_BODY_HINT"]  then body  = "" end

    local fields = { body = body }
    if title ~= "" then fields.title = title end
    BNB.UpdateNote(id, fields)
    BNB.Editor.SetDirty(title == "")
    if BNB.UpdateSaveButtonState then BNB.UpdateSaveButtonState() end
    if BNB._syncNoteConfigTitle then BNB._syncNoteConfigTitle() end
    -- Live update: keeps the sticky's scroll, unlike RefreshNote
    if BNB.Sticky and BNB.Sticky.RefreshBodyLive then BNB.Sticky.RefreshBodyLive(id) end
end

-- Two BNB.Debounce keys (SUG-03, PERF-04): the idle one moves on every
-- keystroke, the forced one is set once and saves during non-stop typing.
local AUTO_IDLE, AUTO_FORCED = "autoSaveIdle", "autoSaveForced"
local function RunAutoSave()
    BNB.CancelDebounce(AUTO_IDLE)
    BNB.CancelDebounce(AUTO_FORCED)
    -- xpcall, not pcall: a failed save must still reach BugSack / scriptErrors,
    -- or the lost text goes unnoticed (SV-02)
    if BNB.IsAutoSave() then xpcall(BNB.SaveCurrentNoteQuiet, geterrorhandler()) end
end

-- Called from BNB.MarkDirty (UI/NoteEditor.lua) on every editor change.
function BNB.ScheduleAutoSave()
    if not BNB.IsAutoSave() then return end
    local db     = BigNoteBoxDB
    local idle   = (db and db.undoIdleDelay)      or 0.8
    local forced = (db and db.undoForcedInterval) or BNB.DEFAULTS.undoForcedInterval
    BNB.Debounce(AUTO_IDLE, idle, RunAutoSave)
    if not BNB.DebouncePending(AUTO_FORCED) then BNB.Debounce(AUTO_FORCED, forced, RunAutoSave) end
end

BNB.RegisterEvent("PLAYER_LOGOUT", function()
    xpcall(BNB.SaveCurrentNoteQuiet, geterrorhandler())
end)

--------------------------------------------------------------------------------
-- EDITOR STATE  (ARCH-02)
-- The note open in the main window and whether it has unsaved edits. Read
-- them anywhere (BNB._currentNoteID / BNB._dirty, or these getters); change
-- them only through the setters. SetCurrent does not touch
-- BigNoteBoxDB.selectedNoteID (what a reload reopens): callers that mean it
-- set that too. SelectNote sends NoteSelected(id) once the editor has loaded
-- the note; Note Settings, the Reference Box and the history panel follow it.
--------------------------------------------------------------------------------
BNB.Editor = BNB.Editor or {}
local Editor = BNB.Editor

function Editor.CurrentID() return BNB._currentNoteID end
function Editor.IsDirty()   return BNB._dirty == true end
function Editor.SetCurrent(id) BNB._currentNoteID = id end
function Editor.SetDirty(on)   BNB._dirty = on and true or false end

--------------------------------------------------------------------------------
-- MARK DIRTY
--------------------------------------------------------------------------------
function BNB.MarkDirty()
    Editor.SetDirty(true)
end


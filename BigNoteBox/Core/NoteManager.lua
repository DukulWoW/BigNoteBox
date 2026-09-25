-- BigNoteBox Core/NoteManager.lua — Note CRUD and autosave
-- Notes live in BigNoteBoxNotesDB (separate SavedVariables).
-- Settings/UI state live in BigNoteBoxDB.
-- This separation means /bnb reset never touches notes.

local BNB = BigNoteBox
local L   = BNB.L

-- Convenience accessor — keeps all reads/writes in one place
local function NDB() return BigNoteBoxNotesDB end

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
-- TRASH BUTTON SYNC
-- Reads trash directly so it works whether or not TrashWindow is open.
-- Called by every function that mutates the trash (Delete, Restore, Empty)
-- and also by Initialize on login.
--------------------------------------------------------------------------------
function BNB.SyncTrashBtnState()
    local btn = BNB._toolbarTrashBtn
    if not btn then return end
    local ndb = BigNoteBoxNotesDB
    local hasItems = false
    if ndb and ndb.trash then
        for _ in pairs(ndb.trash) do hasItems = true; break end
    end
    btn:SetEnabled(hasItems)
    btn:SetAlpha(hasItems and 1.0 or 0.4)
    pcall(function() btn._tx:SetDesaturated(not hasItems) end)
end

--------------------------------------------------------------------------------
-- TAG INDEX HELPERS
-- BigNoteBoxDB.tagIndex maps tag → { [noteID] = true }.
-- All mutations go through these helpers so the index stays consistent.
-- Keys are stored in original case (as typed); lookups are case-insensitive
-- at the call site where needed (e.g. autocomplete prefix match).
--------------------------------------------------------------------------------
local function TagDB()
    local db = BigNoteBoxDB
    if not db then return nil end
    if not db.tagIndex then db.tagIndex = {} end
    return db.tagIndex
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
        local empty = true
        for _ in pairs(idx[tag]) do empty = false; break end
        if empty then idx[tag] = nil end
    end
end

-- Rebuild the entire index from live notes. Called once on migration and
-- available as a slash-command recovery tool.
function BNB.TagIndexRebuild()
    local db = BigNoteBoxDB; if not db then return end
    db.tagIndex = {}
    local ndb = BigNoteBoxNotesDB; if not ndb or not ndb.notes then return end
    for id, note in pairs(ndb.notes) do
        for _, tag in ipairs(note.tags or {}) do
            BNB.TagIndexAdd(id, tag)
        end
    end
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
            out[#out + 1] = { tag = tag, count = count }
        end
    end
    table.sort(out, function(a, b)
        return a.tag:lower() < b.tag:lower()
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
    local ndb = BigNoteBoxNotesDB
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
    return true
end

-- Delete a tag from every note that carries it.
function BNB.DeleteTag(tag)
    local idx = TagDB(); if not idx then return end
    local ids = idx[tag]
    if not ids then return end
    local ndb = BigNoteBoxNotesDB
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
end

--------------------------------------------------------------------------------
-- CREATE
--------------------------------------------------------------------------------
function BNB.CreateNote(title, body)
    if not NDB() then return nil end
    local id  = BNB.GenerateID()
    local now = time()
    -- New note scope follows the active sidebar filter:
    -- character slot -> char-scoped, everything else -> global
    local activeKey = BNB.Sidebar and BNB.Sidebar.GetActive() or "all"
    local newScope
    if activeKey and activeKey:find("^char:") then
        newScope = activeKey
    else
        newScope = "global"
    end
    -- Capture creation coordinates and zone via C_Map if available.
    local coordX, coordY, coordMapID, coordZone
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
            end
        end
    end
    NDB().notes[id] = {
        id           = id,
        title        = title or "",
        body         = body  or "",
        tags         = {},
        context      = nil,
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
        coordX       = coordX,    -- map X coord at creation time (0-100 scale), or nil
        coordY       = coordY,    -- map Y coord at creation time (0-100 scale), or nil
        coordMapID   = coordMapID, -- map ID at creation time, or nil
        coordZone    = coordZone,  -- zone name at creation time, or nil
        richMode     = false,      -- true = rich note with markup/SimpleHTML rendering
        created      = now,
        updated      = now,
    }
    table.insert(NDB().noteOrder, 1, id)
    -- Index any tags (none on new notes, but future-safe)
    for _, tag in ipairs(NDB().notes[id].tags or {}) do
        BNB.TagIndexAdd(id, tag)
    end
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
local COPY_SKIP = {
    id = true, created = true, updated = true, updatedAt = true,
    coordX = true, coordY = true, coordMapID = true, coordZone = true,
    history = true, manualSnapshot = true, alarm = true,
}

-- Full recursive copy, so the new note shares no table with the source
-- (the old copies shared the tags table: editing one note's tags changed both)
local function DeepCopy(v)
    if type(v) ~= "table" then return v end
    local t = {}
    for k, val in pairs(v) do t[k] = DeepCopy(val) end
    return t
end

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

--------------------------------------------------------------------------------
-- UPDATE
--------------------------------------------------------------------------------
function BNB.UpdateNote(id, fields)
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
    note.updated = time()
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
        if BNB.RefreshTagManager then BNB.RefreshTagManager() end
    end
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

-- UI half: list, editor selection, trash window, trash button.
local function RefreshAfterDelete()
    if BNB.mainFrame and BNB.mainFrame:IsShown() then
        if BNB.RefreshNoteList then BNB.RefreshNoteList() end
        if BNB.SelectNote      then BNB.SelectNote(nil)   end
    end
    -- Refresh trash window if open (note may now appear there)
    if BNB.RefreshTrashWindow then BNB.RefreshTrashWindow() end
    BNB.SyncTrashBtnState()
end

-- permanent = true skips the trash even while it is on ("Delete permanently")
function BNB.DeleteNote(id, permanent)
    if not RemoveNote(id, permanent) then return end
    RefreshAfterDelete()
end

-- Bulk delete: every id goes through the same path as DeleteNote, the UI
-- refreshes once. Ids that are no longer live notes are skipped. Returns the
-- number of notes actually deleted.
function BNB.DeleteNotes(ids, permanent)
    if not ids then return 0 end
    local n = 0
    for _, id in ipairs(ids) do
        if RemoveNote(id, permanent) then n = n + 1 end
    end
    if n > 0 then RefreshAfterDelete() end
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

    if BNB.mainFrame and BNB.mainFrame:IsShown() then
        if BNB.RefreshNoteList then BNB.RefreshNoteList() end
    end
    if BNB.RefreshTrashWindow then BNB.RefreshTrashWindow() end
    -- Re-index tags for the restored note
    for _, tag in ipairs(note.tags or {}) do
        BNB.TagIndexAdd(id, tag)
    end
    BNB.SyncTrashBtnState()
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
    for id, note in pairs(ndb.trash) do
        if (note.deletedAt or 0) < cutoff then
            ndb.trash[id] = nil
        end
    end
end

--------------------------------------------------------------------------------
-- EMPTY TRASH  (permanently delete everything in trash)
--------------------------------------------------------------------------------
function BNB.EmptyTrash()
    local ndb = NDB()
    ndb.trash = {}
    if BNB.RefreshTrashWindow then BNB.RefreshTrashWindow() end
    BNB.SyncTrashBtnState()
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
    local curChar  = BNB.currentChar
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
                    local titleMatch = note.title and note.title:lower():find(lower, 1, true)
                    local bodyMatch  = note.body  and note.body:lower():find( lower, 1, true)
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
    local sortBy = db and db.sortBy or "creation"
    local asc    = db and db.sortAsc or false

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
                local LAST = "\255"
                local at = (a.title and a.title ~= "") and a.title:lower() or LAST
                local bt = (b.title and b.title ~= "") and b.title:lower() or LAST
                if at ~= bt then return at < bt end
                return (a.id or "") < (b.id or "")
            end
        end

        -- Favorites mode: favorited notes float above non-favorited,
        -- then fall back to creation date (newest first) as secondary sort.
        if sortBy == "favorites" then
            local af, bf = a.favorited and 1 or 0, b.favorited and 1 or 0
            if af ~= bf then return af > bf end
            -- secondary: newest created first
            local ac, bc = a.created or 0, b.created or 0
            if ac ~= bc then return ac > bc end
            return (a.id or "") > (b.id or "")
        end

        local av, bv
        if sortBy == "creation" then
            av, bv = a.created or 0, b.created or 0
        elseif sortBy == "edited" then
            av, bv = a.updated or 0, b.updated or 0
        elseif sortBy == "alpha" then
            -- Alpha: A-Z is ascending (asc=true), Z-A is descending (asc=false).
            -- Untitled notes sort to the end regardless of direction.
            local LAST = "\255"
            av = (a.title and a.title ~= "") and a.title:lower() or LAST
            bv = (b.title and b.title ~= "") and b.title:lower() or LAST
        elseif sortBy == "location" then
            -- Notes with no context sort to the end regardless of direction.
            av = (a.context and a.context ~= "") and a.context:lower() or "\255"
            bv = (b.context and b.context ~= "") and b.context:lower() or "\255"
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
    if not id or not NDB() then return nil end
    return NDB().notes[id]
end

--------------------------------------------------------------------------------
-- SAVE CURRENT NOTE
--------------------------------------------------------------------------------
function BNB.SaveCurrentNote()
    if not BNB._dirty then return end
    local id = BNB._currentNoteID
    if not id then BNB._dirty = false; return end
    local note = BNB.GetNote(id)
    if not note then BNB._dirty = false; return end

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
    BNB._dirty = false
    if BNB.UpdateSaveButtonState then BNB.UpdateSaveButtonState() end

    if BNB.RefreshNoteList then BNB.RefreshNoteList() end
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
    if not note then BNB._dirty = false; return end

    local title = BNB._editorTitle and BNB._editorTitle:GetText() or note.title
    local body  = BNB._editorBody  and BNB._editorBody:GetText()  or note.body
    if BNB._editorTitle and BNB._editorTitle._showingPlaceholder then title = "" end
    if BNB._editorBody  and BNB._editorBody._showingPlaceholder  then body  = "" end
    if title == L["NOTE_TITLE_HINT"] then title = "" end
    if body  == L["NOTE_BODY_HINT"]  then body  = "" end

    local fields = { body = body }
    if title ~= "" then fields.title = title end
    BNB.UpdateNote(id, fields)
    BNB._dirty = (title == "")
    if BNB.UpdateSaveButtonState then BNB.UpdateSaveButtonState() end
    if BNB.RefreshNoteList then BNB.RefreshNoteList() end
    if BNB._syncNoteConfigTitle then BNB._syncNoteConfigTitle() end
    -- Live update: keeps the sticky's scroll, unlike RefreshNote
    if BNB.Sticky and BNB.Sticky.RefreshBodyLive then BNB.Sticky.RefreshBodyLive(id) end
end

local _autoIdle, _autoForced
local function RunAutoSave()
    if _autoIdle   then _autoIdle:Cancel();   _autoIdle   = nil end
    if _autoForced then _autoForced:Cancel(); _autoForced = nil end
    if BNB.IsAutoSave() then pcall(BNB.SaveCurrentNoteQuiet) end
end

-- Called from BNB.MarkDirty (UI/NoteEditor.lua) on every editor change.
function BNB.ScheduleAutoSave()
    if not BNB.IsAutoSave() then return end
    local db     = BigNoteBoxDB
    local idle   = (db and db.undoIdleDelay)      or 0.8
    local forced = (db and db.undoForcedInterval) or 3.0
    if _autoIdle then _autoIdle:Cancel() end
    _autoIdle = C_Timer.NewTimer(idle, RunAutoSave)
    if not _autoForced then _autoForced = C_Timer.NewTimer(forced, RunAutoSave) end
end

BNB.RegisterEvent("PLAYER_LOGOUT", function()
    pcall(BNB.SaveCurrentNoteQuiet)
end)

--------------------------------------------------------------------------------
-- MARK DIRTY
--------------------------------------------------------------------------------
function BNB.MarkDirty()
    BNB._dirty = true
end

--------------------------------------------------------------------------------
-- COUNT NOTES
--------------------------------------------------------------------------------
function BNB.NoteCount()
    if not NDB() then return 0 end
    local n = 0
    for _ in pairs(NDB().notes) do n = n + 1 end
    return n
end

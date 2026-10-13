-- BigNoteBox Features/NoteHistory.lua
--
-- Session history (version history) for notes.
-- Mirrors Word's "Version History" — auto-snapshots on logout/reload,
-- plus one user-controlled manual restore point per note.
--
-- STORAGE:
--   automatic: the BigNoteBox_History file (BigNoteBoxHistoryDB.auto[set][id]
--              = { snap, snap, ... }, [1] = newest; Core/Database.lua), since
--              NOTES v13 (ALL-466). It used to be note.history.
--   manual:    note.manualSnapshot = snap or nil, on the note in the notes file
--
-- A "snap" table contains:
--   timestamp  — unix time of snapshot
--   + the SNAP_FIELDS below (title, body, richMode, tags, tasks, taskList).
--   Look and metadata (icon, colours, font, context, attachments, gear, ...)
--   are not versioned: a restore leaves them as they are (SV-11).
--
-- AUTO SLOTS:
--   Controlled by BigNoteBoxDB.historyMaxSlots (default 5, range 1-20).
--   On PLAYER_LOGOUT, each note whose updated > history[1].timestamp gets a
--   new snapshot pushed. Oldest entries are trimmed to historyMaxSlots.
--   Notes with no changes since the last snapshot are skipped.
--
-- MANUAL SLOT:
--   One per note. User-controlled via right-click or tb-restore button.
--   Never auto-overwritten. Warns user before overwriting.
--
-- PUBLIC API:
--   BNB.HistorySnapshotAll()                    Logout trigger
--   BNB.HistorySnapshotNote(id)                 Auto-push for one note
--   BNB.HistoryCreateManual(id)                 Set manual slot (warns if exists)
--   BNB.HistoryGetSlots(id)                     {auto={snap,...}, manual=snap|nil}
--   BNB.HistoryRestoreNote(id, snap, keepCurrent)  Apply snapshot to live note
--   BNB.HistoryDeleteAutoSlot(id, index)        Remove one auto entry
--   BNB.HistoryDeleteManual(id)                 Remove manual snapshot
--   BNB.HistoryDeleteAuto(id)                    Remove only auto snapshots for one note
--   BNB.HistoryNoteHasAny(id)                   bool
--   BNB.HistoryTotalSize()                       bytes across all history
--   BNB.HistoryNoteSize(id)                      bytes for one note's history
--   BNB.HistoryNewest(id)                        newest auto snapshot or nil
--   BNB.HistoryAutoCount(id)                     number of auto snapshots
--   BNB.HistoryClearAllAuto()                    every note's auto snapshots; count
--
--   BNB.HistoryAutoNoteCount()                   notes with auto snapshots in the history file
--   BNB.HistoryForget(id)                        a note deleted for good: its auto history goes
--   BNB.HistoryWipeSet()                         Factory Reset: the active set's auto history
--   BNB.HistorySaveStates()                      logout: each note's last known state (ALL-468)
--
-- ALL-466: the automatic snapshots are read and written only through
-- AutoList / SetAutoList below, and every other file goes through the public
-- functions here (never note.history). Stage 2 moved them to BigNoteBox_History
-- by changing that seam. The manual restore point stays on the note
-- (note.manualSnapshot) for good. History of a note that vanished without
-- being deleted here (a lost notes file) is kept on purpose: Rescue (stage 3)
-- rebuilds notes from it.
--   BNB.SyncHistoryBtnState()                   Update toolbar icon state
--   BNB.SyncHistoryNoteBtnState()               Update per-note WYSIWYG buttons

local BNB = BigNoteBox

--------------------------------------------------------------------------------
-- FIELDS a snapshot captures and a restore puts back (SV-11, ALL-136.8,
-- Dukul's pick). Snapshots used to copy every content field (ALL-65.6), so up
-- to 21 full copies of each note's attachments, gear and look sat in the notes
-- file, which loads at login. The text, its mode, its tags and its tasks
-- (with the list's reset settings) are what a restore needs. NOTES v8
-- (Core/Database.lua) trims older snapshots to the same list.
--------------------------------------------------------------------------------
local SNAP_FIELDS = { "title", "body", "richMode", "tags", "tasks", "taskList" }
BNB.HISTORY_SNAP_FIELDS = SNAP_FIELDS

--------------------------------------------------------------------------------
-- INTERNAL: deep-copy a value (handles tables, arrays, primitives)
-- Fully recursive. It used to stop at two levels, so a snapshot shared each
-- task, attachment and gear table with the live note: ticking a task changed
-- the snapshot too (BUG-22).
--------------------------------------------------------------------------------
local DeepCopy = BNB.DeepCopy

--------------------------------------------------------------------------------
-- INTERNAL: build a snapshot table from a live note
--------------------------------------------------------------------------------
local function MakeSnap(note)
    local snap = { timestamp = time() }
    for _, field in ipairs(SNAP_FIELDS) do
        snap[field] = DeepCopy(note[field])
    end
    return snap
end

--------------------------------------------------------------------------------
-- INTERNAL: approximate byte size of a snapshot. Walks every field, tables
-- included (it used to count title and body only, so tasks or an untrimmed
-- old snapshot did not show). Strings count their length, anything else a
-- few bytes, plus a little per key for the saved-file syntax.
--------------------------------------------------------------------------------
local function ValueSize(v)
    local t = type(v)
    if t == "string" then return #v + 2 end
    if t ~= "table" then return 8 end
    local n = 2
    for k, x in pairs(v) do
        n = n + ValueSize(k) + ValueSize(x) + 4
    end
    return n
end

local function SnapSize(snap)
    if not snap then return 0 end
    return ValueSize(snap)
end

--------------------------------------------------------------------------------
-- INTERNAL: access notes DB safely
--------------------------------------------------------------------------------
local function NDB()
    return BNB.NotesDB() or {}
end

--------------------------------------------------------------------------------
-- STORAGE SEAM (ALL-466): the only code that touches where the automatic
-- snapshots live: the history file (BNB.HistoryAutoBucket, Core/Database.lua),
-- keyed by note id, so a note in the trash keeps its list and has it back when
-- restored. AutoList(id) = the note's list, newest first, or nil.
-- SetAutoList(id, list) stores it; nil or empty removes it. History addon
-- missing = nothing stored, nothing read (Note History counts as off).
-- While the move from the notes file waits for its second load
-- (BNB.HistoryMovePending), every write is mirrored onto note.history, so the
-- notes file's copy never brings back a snapshot deleted here.
--------------------------------------------------------------------------------
local function LiveNote(id)
    local ndb = NDB()
    return id and ndb.notes and ndb.notes[id] or nil
end

local function AutoList(id)
    local bucket = id and BNB.HistoryAutoBucket()
    return bucket and bucket[id] or nil
end

local function Mirror(id, list)
    if not BNB.HistoryMovePending() then return end
    local ndb = NDB()
    local note = (ndb.notes and ndb.notes[id]) or (ndb.trash and ndb.trash[id])
    if note then note.history = list end
end

local function SetAutoList(id, list)
    local bucket = id and BNB.HistoryAutoBucket()
    if not bucket then return end
    if not (list and #list > 0) then list = nil end
    bucket[id] = list
    Mirror(id, list)
end

local function MaxSlots()
    local db = BigNoteBoxDB
    local n  = db and db.historyMaxSlots or BNB.DEFAULTS.historyMaxSlots
    if n < 1  then n = 1  end
    if n > 20 then n = 20 end
    return n
end

--------------------------------------------------------------------------------
-- HistorySnapshotNote — push one auto snapshot for a note.
-- Only pushes if the note has changed since the last auto snapshot.
-- Trims the array to MaxSlots() after pushing.
-- Returns true if a snapshot was actually pushed.
--------------------------------------------------------------------------------
function BNB.HistorySnapshotNote(id)
    local note = LiveNote(id)
    if not note or not BNB.HistoryAutoBucket() then return false end   -- no history file

    local hist = AutoList(id) or {}

    -- Skip if title and body haven't changed since last auto snapshot.
    -- Metadata-only changes (icon, tags, context, etc.) do not warrant a new entry.
    local lastSnap = hist[1]
    if lastSnap then
        if (lastSnap.title or "") == (note.title or "")
        and (lastSnap.body  or "") == (note.body  or "") then
            return false
        end
    end

    -- Skip completely empty notes (title and body both absent/empty)
    local title = note.title or ""
    local body  = note.body  or ""
    if title == "" and body == "" then return false end

    -- Push new snapshot at front
    table.insert(hist, 1, MakeSnap(note))

    -- Trim to max slots
    local max = MaxSlots()
    while #hist > max do
        table.remove(hist)
    end

    SetAutoList(id, hist)
    return true
end

--------------------------------------------------------------------------------
-- HistorySnapshotAll — called on PLAYER_LOGOUT.
-- Iterates every live note and pushes a snapshot where needed.
--------------------------------------------------------------------------------
function BNB.HistorySnapshotAll()
    local ndb = NDB()
    if not ndb.notes then return end
    for id in pairs(ndb.notes) do
        BNB.HistorySnapshotNote(id)
    end
    BNB.SyncHistoryBtnState()
    BNB.SyncHistoryNoteBtnState()
end

--------------------------------------------------------------------------------
-- HistoryCreateManual — create or overwrite the manual restore point.
-- Does NOT warn — callers (WYSIWYG button, right-click) handle the confirm UI.
--------------------------------------------------------------------------------
function BNB.HistoryCreateManual(id)
    local ndb  = NDB()
    local note = ndb.notes and ndb.notes[id]
    if not note then return false end
    note.manualSnapshot = MakeSnap(note)
    BNB.SyncHistoryBtnState()
    BNB.SyncHistoryNoteBtnState()
    BNB.RefreshHistoryWindow()
    BNB.RefreshNoteHistoryPanel()
    return true
end

--------------------------------------------------------------------------------
-- HistoryDeleteManual — remove manual restore point for a note.
--------------------------------------------------------------------------------
function BNB.HistoryDeleteManual(id)
    local ndb  = NDB()
    local note = ndb.notes and ndb.notes[id]
    if not note then return end
    note.manualSnapshot = nil
    BNB.SyncHistoryBtnState()
    BNB.SyncHistoryNoteBtnState()
    BNB.RefreshHistoryWindow()
    BNB.RefreshNoteHistoryPanel()
end

--------------------------------------------------------------------------------
-- HistoryDeleteAutoSlot — remove one entry from note.history by 1-based index.
--------------------------------------------------------------------------------
function BNB.HistoryDeleteAutoSlot(id, index)
    local hist = AutoList(id)
    if not hist then return end
    table.remove(hist, index)
    SetAutoList(id, hist)
    BNB.SyncHistoryBtnState()
    BNB.SyncHistoryNoteBtnState()
end

--------------------------------------------------------------------------------
-- HistoryDeleteAuto — wipe only auto snapshots for one note.
-- Manual restore points (note.manualSnapshot) are preserved.
--------------------------------------------------------------------------------
function BNB.HistoryDeleteAuto(id)
    if not LiveNote(id) then return end
    SetAutoList(id, nil)
    BNB.SyncHistoryBtnState()
    BNB.SyncHistoryNoteBtnState()
end


--------------------------------------------------------------------------------
-- HistoryGetSlots — returns {auto={snap,...}, manual=snap|nil} for a note.
-- auto is always a table (may be empty). manual may be nil.
--------------------------------------------------------------------------------
function BNB.HistoryGetSlots(id)
    local note = LiveNote(id)
    if not note then return { auto = {}, manual = nil } end
    return {
        auto   = AutoList(id) or {},
        manual = note.manualSnapshot or nil,
    }
end

-- Newest auto snapshot of a note, or nil
function BNB.HistoryNewest(id)
    local hist = AutoList(id)
    return hist and hist[1] or nil
end

-- How many auto snapshots a note has
function BNB.HistoryAutoCount(id)
    local hist = AutoList(id)
    return hist and #hist or 0
end

-- How many notes of the active set have auto snapshots in the history file:
-- live, trashed, and ones whose note is gone (kept for Rescue)
function BNB.HistoryAutoNoteCount()
    local n = 0
    for _ in pairs(BNB.HistoryAutoBucket() or {}) do n = n + 1 end
    return n
end

-- The active set's auto snapshots gone (Danger Zone), trashed and gone notes'
-- too; manual restore points kept. Returns how many notes had some.
function BNB.HistoryClearAllAuto()
    local ids = {}
    for id in pairs(BNB.HistoryAutoBucket() or {}) do ids[#ids + 1] = id end
    for _, id in ipairs(ids) do SetAutoList(id, nil) end
    -- The last known states go too: without versions they rescue nothing
    -- (the live notes' come back at the next logout)
    local store = BNB.HistoryDB()
    if store then store.state[BNB.HistorySetKey()] = {} end
    return #ids
end

--------------------------------------------------------------------------------
-- LAST KNOWN STATE (ALL-468, Dukul 2026-10-13: a rescued note came back with
-- its text only). One record per note in the history file, everything except
-- title and text (BNB.CleanNoteFields: the schema's non-internal fields, so a
-- new note field is kept without a change here): { t = time(), f = fields }.
-- Written at logout / reload with the snapshots, for every live note; a record
-- whose note is gone stays only while the note still has versions (a trashed
-- or lost note: Rescue rebuilds it from both). One copy per note, never per
-- version, so the file stays small.
--------------------------------------------------------------------------------
local function StateBucket()
    local store = BNB.HistoryDB()
    if not store then return nil end
    local k = BNB.HistorySetKey()
    if type(store.state[k]) ~= "table" then store.state[k] = {} end
    return store.state[k]
end

local function NotText(def) return def.key ~= "title" and def.key ~= "body" end

function BNB.HistorySaveStates()
    local states, bucket, ndb = StateBucket(), BNB.HistoryAutoBucket(), NDB()
    if not (states and bucket and ndb.notes) then return end
    local now = time()
    for id, note in pairs(ndb.notes) do
        states[id] = { t = now, f = BNB.CleanNoteFields(note, NotText) }
    end
    for id in pairs(states) do
        if not ndb.notes[id] and not bucket[id] then states[id] = nil end
    end
end

-- A note's last known fields, or nil
local function StateOf(id)
    local states = StateBucket()
    local rec = states and states[id]
    return type(rec) == "table" and type(rec.f) == "table" and rec.f or nil
end

-- A note deleted for good (Delete permanently, the trash emptied or expired,
-- Delete All Notes): its auto snapshots and last known state go with it. Not
-- on a move to the trash, and never for a note that merely went missing
-- (Rescue keeps those).
function BNB.HistoryForget(id)
    local bucket = id and BNB.HistoryAutoBucket()
    if bucket then bucket[id] = nil end
    local states = id and StateBucket()
    if states then states[id] = nil end
end

--------------------------------------------------------------------------------
-- RESCUE (ALL-466 stage 3, Dukul 2026-10-13). The history file keeps the
-- versions of a note that vanished without being deleted here (a damaged or
-- replaced notes file), so it can be rebuilt. Two kinds in one list:
--   "missing": an id in the history file that is neither a note nor in the
--              trash; Rescue = BNB.RescueNote (Core/NoteManager.lua) from its
--              newest version with text.
--   "empty":   a live note with no title and no text whose history has text;
--              Rescue = the normal restore of that version, keepCurrent, so
--              the empty state is kept as a version too.
-- Lists: Settings > Modules > Note History (K.BuildHistoryPage); a button on
-- Settings > Backup and in the History window opens it (greyed while there
-- is nothing); a login popup when the notes set is empty (Dukul's pick).
--------------------------------------------------------------------------------
local function HasText(s)
    return type(s) == "table" and ((s.title or "") ~= "" or (s.body or "") ~= "")
end

-- One rescue entry for a note's list, or nil when no version has text
local function RescueEntry(id, list, kind)
    if type(list) ~= "table" then return nil end
    local best, oldest, n = nil, nil, 0
    for _, s in ipairs(list) do   -- newest first
        if type(s) == "table" then
            n = n + 1
            if not best and HasText(s) then best = s end
            local t = s.timestamp or 0
            if not oldest or t < oldest then oldest = t end
        end
    end
    if not best then return nil end
    return { id = id, kind = kind, snap = best, title = best.title or "",
             ts = best.timestamp or 0, count = n, oldest = oldest }
end

-- { { id, kind, snap, title, ts, count, oldest }, ... }, newest first; {} when
-- the notes or the history file are not there
function BNB.HistoryRescueList()
    local out = {}
    local bucket = BNB.HistoryAutoBucket()
    if not (bucket and BNB._notesAvailable) then return out end
    local ndb = NDB()
    if not ndb.notes then return out end
    local trash = ndb.trash or {}
    for id, list in pairs(bucket) do
        local note, kind = ndb.notes[id], nil
        if not note and not trash[id] then
            kind = "missing"
        elseif note and (note.title or "") == "" and (note.body or "") == "" then
            kind = "empty"
        end
        local e = kind and RescueEntry(id, list, kind)
        if e then out[#out + 1] = e end
    end
    table.sort(out, function(a, b) return a.ts > b.ts end)
    return out
end

function BNB.HistoryRescueCount()
    return #BNB.HistoryRescueList()
end

-- "1 note can be rescued." / "N notes can be rescued." (the Rescue page and
-- Settings > Backup)
function BNB.HistoryRescueCountText(n)
    if n == 1 then return BNB.L["RESCUE_COUNT_ONE"] end
    return string.format(BNB.L["RESCUE_COUNT_FMT"], n)
end

-- Rescue one entry of HistoryRescueList. Returns true when it was done.
local function RescueOne(e)
    if e.kind == "missing" then
        return BNB.RescueNote(e.id, e.snap, e.oldest, StateOf(e.id)) ~= nil
    end
    return BNB.HistoryRestoreNote(e.id, e.snap, true)
end

-- After a rescue: buttons and lists re-count. A rescued alarm whose time
-- passed while its note was lost does not ring: caught up as after a login
-- with Alarms off (repeating = next time, one-off = fired and listed once;
-- Dukul's pick, ALL-468). With Alarms off, switching it on catches up.
local function AfterRescue(ids)
    if ids and #ids > 0 and BNB.AlarmsEnabled and BNB.AlarmsEnabled()
       and BNB.Alarm and BNB.Alarm.CatchUpNotes then
        BNB.Alarm.CatchUpNotes(ids, "AO_MISSED_RESCUE_FMT")
    end
    BNB.SyncHistoryBtnState()
    BNB.SyncHistoryNoteBtnState()
    BNB.SendMessage("HistoryRescueChanged")
end

-- One note by id (a row's Rescue). True when it was done.
function BNB.HistoryRescue(id)
    for _, e in ipairs(BNB.HistoryRescueList()) do
        if e.id == id then
            local ok = RescueOne(e)
            AfterRescue(ok and { id } or nil)
            return ok
        end
    end
    return false
end

-- Every note in the list; returns how many came back, and says so in chat
function BNB.HistoryRescueAll()
    local done = {}
    for _, e in ipairs(BNB.HistoryRescueList()) do
        if RescueOne(e) then done[#done + 1] = e.id end
    end
    local n = #done
    AfterRescue(done)
    if n > 0 then
        if n == 1 then BNB:Print(BNB.L["RESCUE_DONE_ONE"])
        else BNB:Print(string.format(BNB.L["RESCUE_DONE_FMT"], n)) end
    end
    return n
end

-- A lost note's row X: its history goes for good (it cannot be rescued then)
function BNB.HistoryRescueDiscard(id)
    BNB.HistoryForget(id)
    AfterRescue()
end

-- Factory Reset: the active notes set's auto history and the move's token
function BNB.HistoryWipeSet()
    local store = BNB.HistoryDB()
    if not store then return end
    local k = BNB.HistorySetKey()
    store.auto[k], store.moved[k], store.state[k] = {}, nil, {}
end

--------------------------------------------------------------------------------
-- HistoryNoteHasAny — true if a note has any history at all.
--------------------------------------------------------------------------------
function BNB.HistoryNoteHasAny(id)
    local note = LiveNote(id)
    if not note then return false end
    if note.manualSnapshot then return true end
    return BNB.HistoryAutoCount(id) > 0
end

--------------------------------------------------------------------------------
-- HistoryAnyExists — true if any note in the DB has history.
-- Used to enable/disable the top-right history.tga toolbar button.
--------------------------------------------------------------------------------
function BNB.HistoryAnyExists()
    local ndb = NDB()
    if not ndb.notes then return false end
    for id in pairs(ndb.notes) do
        if BNB.HistoryNoteHasAny(id) then return true end
    end
    -- Notes that can be rescued: the History window holds the way to them
    return BNB.HistoryRescueCount() > 0
end

--------------------------------------------------------------------------------
-- HistoryNoteSize — approximate byte size of all history for one note.
--------------------------------------------------------------------------------
function BNB.HistoryNoteSize(id)
    local slots = BNB.HistoryGetSlots(id)
    local n = SnapSize(slots.manual)
    for _, snap in ipairs(slots.auto) do
        n = n + SnapSize(snap)
    end
    return n
end

--------------------------------------------------------------------------------
-- HistoryTotalSize — approximate byte size of all history across all notes.
--------------------------------------------------------------------------------
function BNB.HistoryTotalSize()
    local ndb = NDB()
    if not ndb.notes then return 0 end
    local total = 0
    for id in pairs(ndb.notes) do
        total = total + BNB.HistoryNoteSize(id)
    end
    return total
end

--------------------------------------------------------------------------------
-- FormatSize — human-readable size string ("1.2 KB", "45 KB", "1.1 MB")
--------------------------------------------------------------------------------
function BNB.HistoryFormatSize(bytes)
    if bytes < 1024 then
        return bytes .. " B"
    elseif bytes < 1024 * 1024 then
        return string.format("%.1f KB", bytes / 1024)
    else
        return string.format("%.1f MB", bytes / (1024 * 1024))
    end
end

--------------------------------------------------------------------------------
-- HistoryRestoreNote — apply a snapshot to the live note.
-- If keepCurrent=true, the current note state is pushed into auto history
-- before overwriting (so the old version is recoverable).
-- keepCurrent=false just overwrites immediately.
--------------------------------------------------------------------------------
function BNB.HistoryRestoreNote(id, snap, keepCurrent)
    if not id or not snap then return false end
    local ndb  = NDB()
    local note = ndb.notes and ndb.notes[id]
    if not note then return false end

    -- Optionally preserve current state first
    if keepCurrent then
        local hist = AutoList(id) or {}
        table.insert(hist, 1, MakeSnap(note))
        local max = MaxSlots()
        while #hist > max do table.remove(hist) end
        SetAutoList(id, hist)
    end

    -- Apply the snapshot's fields to the live note: each SNAP_FIELDS entry is
    -- set from the snapshot, or cleared when the snapshot has none (tasks
    -- added after it was taken). Nothing else is touched, also when an old
    -- snapshot still carries more (SV-11). Through UpdateNote, so the tag
    -- index follows the restored tags (BUG-22); tags is always passed for
    -- that, as {} when the snapshot has none.
    local fields, clear = {}, {}
    for _, field in ipairs(SNAP_FIELDS) do
        if snap[field] ~= nil then
            fields[field] = DeepCopy(snap[field])
        elseif field ~= "tags" and note[field] ~= nil then
            clear[#clear + 1] = field
        end
    end
    if fields.tags == nil then fields.tags = {} end
    if #clear > 0 then fields._clear = clear end
    BNB.UpdateNote(id, fields)

    -- Refresh the editor if this note is currently open
    if BNB._currentNoteID == id then
        if BNB.LoadNoteInEditor then BNB.LoadNoteInEditor(id) end
    end
    if BNB.Sticky and BNB.Sticky.RefreshNote then
        BNB.Sticky.RefreshNote(id)
    end
    -- note.tasks was replaced wholesale above, so any open task display
    -- (Reference Box, sticky, note list) needs its own refresh signal.
    if BNB.Task and BNB.Task.NotifyTasksChanged then
        BNB.Task.NotifyTasksChanged(id)
    end
    BNB.SyncHistoryBtnState()
    BNB.SyncHistoryNoteBtnState()
    return true
end

--------------------------------------------------------------------------------
-- SyncHistoryBtnState — update the top-right history.tga toolbar button.
-- Active when any note has history; desaturated + disabled when none.
--------------------------------------------------------------------------------
function BNB.SyncHistoryBtnState()
    local btn = BNB._toolbarHistoryBtn
    if not btn then return end
    local has = BNB.HistoryAnyExists()
    btn:SetIconEnabled(has)
    -- Keep history window list current whenever history changes
    if BNB.RefreshHistoryWindow then BNB.RefreshHistoryWindow() end
end

--------------------------------------------------------------------------------
-- SyncHistoryNoteBtnState — update tb-restore and tb-history on the WYSIWYG bar.
-- Called when note selection changes or history mutates.
--------------------------------------------------------------------------------
function BNB.SyncHistoryNoteBtnState()
    local id = BNB._currentNoteID
    -- tb-history: active only if current note has any history
    local histBtn = BNB._wysiwygHistoryBtn
    if histBtn then
        local has = id and BNB.HistoryNoteHasAny(id) or false
        histBtn:SetIconEnabled(has)
    end
    -- tb-restore is always active when a note is loaded (creates the snapshot);
    -- just ensure it's enabled/disabled with note loading state
    local restoreBtn = BNB._wysiwygRestoreBtn
    if restoreBtn then
        restoreBtn:SetIconEnabled(id ~= nil)
    end
end

--------------------------------------------------------------------------------
-- PLAYER_LOGOUT hook — registered in Events.lua via BNB.RegisterEvent
--------------------------------------------------------------------------------
BNB.RegisterEvent("PLAYER_LOGOUT", function()
    if BNB.HistorySnapshotAll and BNB.HistoryEnabled() then
        BNB.HistorySnapshotAll()
        BNB.HistorySaveStates()   -- last known state for Rescue (ALL-468)
    end
end)

--------------------------------------------------------------------------------
-- MODULE SWITCH (Settings > Modules > Note History, ALL-343)
-- Off: no logout snapshots and every way in hidden; the snapshots already
-- taken stay where they are and come back with the module. Also off while the
-- BigNoteBox_History addon is missing or disabled (ALL-466, Dukul: "All modules
-- that require it should also be turned off automatically"); the saved switch
-- is left alone, so enabling the addon brings the module back as it was.
--------------------------------------------------------------------------------
function BNB.HistoryEnabled()
    if not BNB.HistoryAddonLoaded() then return false end
    return not BigNoteBoxDB or BigNoteBoxDB.historyEnabled ~= false
end

-- The saved switch alone (the page checkbox, the login notice)
function BNB.HistoryWanted()
    return not BigNoteBoxDB or BigNoteBoxDB.historyEnabled ~= false
end

function BNB.ApplyHistoryModule(on)
    if not on then
        if BNB.CloseHistoryCompare then BNB.CloseHistoryCompare() end
        if BNB.CloseHistoryWindow then BNB.CloseHistoryWindow() end   -- list and per-note pages
    end
    if BNB.ApplyToolbarIcons then BNB.ApplyToolbarIcons() end              -- toolbar History icon
    if BNB.ApplyWysiwygModuleBtns then BNB.ApplyWysiwygModuleBtns() end    -- history / restore buttons
end

--------------------------------------------------------------------------------
-- LOGIN NOTICE (ALL-466): BigNoteBox_History is missing or disabled while
-- something needs it (Note History on, or Keep undo between sessions on).
-- A popup to click, not a chat line (Dukul: "warn with a popup that you have
-- to click so people know that bnb was made to have this turned on by
-- default"). "Don't show again" is saved; not during first-time setup.
--------------------------------------------------------------------------------
local function ShowAddonNotice()
    local db = BigNoteBoxDB
    if BNB.HistoryAddonLoaded() or not db then return end
    if db.historyAddonNotice == false or db.setupComplete ~= true then return end
    if not (BNB.HistoryWanted() or db.undoKeep == true) then return end
    if not StaticPopupDialogs["BNB_HISTORY_ADDON_MISSING"] then
        StaticPopupDialogs["BNB_HISTORY_ADDON_MISSING"] = {
            preferredIndex = 3,
            text    = BNB.L["HISTORY_ADDON_NOTICE"],
            button1 = OKAY,
            button2 = BNB.L["HISTORY_ADDON_NOTICE_NEVER"],
            timeout = 0, whileDead = true, hideOnEscape = false,
            noCancelOnEscape = true,
            -- button2 only (Esc does not reach OnCancel, noCancelOnEscape)
            OnCancel = function(_, _, reason)
                if reason == "clicked" and BigNoteBoxDB then BigNoteBoxDB.historyAddonNotice = false end
            end,
        }
    end
    StaticPopup_Show("BNB_HISTORY_ADDON_MISSING")
end

-- The notes set is empty (no notes, nothing in the trash) but the history file
-- holds notes to rescue: offer them once per login (ALL-466 stage 3, Dukul's
-- pick: only then; otherwise they wait in the Rescue list)
local function OfferRescue()
    local ndb = BNB._notesAvailable and NDB()
    if not (ndb and ndb.notes) or next(ndb.notes) or next(ndb.trash or {}) then return end
    local n = BNB.HistoryRescueCount()
    if n == 0 then return end
    if not StaticPopupDialogs["BNB_HISTORY_RESCUE_OFFER"] then
        StaticPopupDialogs["BNB_HISTORY_RESCUE_OFFER"] = {
            preferredIndex = 3,
            text    = "%s",
            button1 = BNB.L["RESCUE_ALL_BTN"],
            button2 = BNB.L["DZ_POPUP_LATER"],
            OnAccept = function() BNB.HistoryRescueAll() end,
            timeout = 0, whileDead = true, hideOnEscape = true,
        }
    end
    StaticPopup_Show("BNB_HISTORY_RESCUE_OFFER", string.format(BNB.L["RESCUE_OFFER_FMT"], n))
end

BNB.RegisterEvent("PLAYER_LOGIN", function()
    C_Timer.After(3, ShowAddonNotice)   -- after What's New and the welcome note
    C_Timer.After(4, OfferRescue)
end)

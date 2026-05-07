-- BigNoteBox Features/NoteHistory.lua
--
-- Session history (version history) for notes.
-- Mirrors Word's "Version History" — auto-snapshots on logout/reload,
-- plus one user-controlled manual restore point per note.
--
-- STORAGE (BigNoteBoxNotesDB, on each note object):
--   note.history        = { snap, snap, ... }  -- auto slots, [1]=newest
--   note.manualSnapshot = snap or nil
--
-- A "snap" table contains:
--   timestamp  — unix time of snapshot
--   + all content fields from the note (title, body, tags, context, icon, ...)
--   NOT: id, created, updated, history, manualSnapshot (identity / recursion)
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
--   BNB.HistoryDeleteAll(id)                    Remove all history for one note
--   BNB.HistoryNoteHasAny(id)                   bool
--   BNB.HistoryTotalSize()                       bytes across all history
--   BNB.HistoryNoteSize(id)                      bytes for one note's history
--   BNB.SyncHistoryBtnState()                   Update toolbar icon state
--   BNB.SyncHistoryNoteBtnState()               Update per-note WYSIWYG buttons

local BNB = BigNoteBox

--------------------------------------------------------------------------------
-- CONTENT FIELDS to capture in a snapshot (all content, no identity/meta)
--------------------------------------------------------------------------------
local SNAP_FIELDS = {
    "title", "body", "tags", "context", "contextDisplay", "contextLeave",
    "pinned", "favorited", "locked", "icon", "titleColor",
    "fontOverride", "textAlign", "fontOutline",
    "borderOverride", "borderScale", "borderOffset", "lineHeight",
    "waypoint", "wpClearOnLeave", "attachments", "scope",
}

--------------------------------------------------------------------------------
-- INTERNAL: deep-copy a value (handles tables, arrays, primitives)
-- Only goes two levels deep — sufficient for note field types.
--------------------------------------------------------------------------------
local function DeepCopy(v)
    if type(v) ~= "table" then return v end
    local copy = {}
    for k, val in pairs(v) do
        if type(val) == "table" then
            local inner = {}
            for k2, v2 in pairs(val) do inner[k2] = v2 end
            copy[k] = inner
        else
            copy[k] = val
        end
    end
    return copy
end

--------------------------------------------------------------------------------
-- INTERNAL: build a snapshot table from a live note
--------------------------------------------------------------------------------
local function MakeSnap(note)
    local snap = { timestamp = time() }
    for _, field in ipairs(SNAP_FIELDS) do
        if note[field] ~= nil then
            snap[field] = DeepCopy(note[field])
        end
    end
    return snap
end

--------------------------------------------------------------------------------
-- INTERNAL: approximate byte size of a snapshot (title + body + overhead)
--------------------------------------------------------------------------------
local function SnapSize(snap)
    if not snap then return 0 end
    local n = 0
    if snap.title then n = n + #snap.title end
    if snap.body  then n = n + #snap.body  end
    -- rough overhead for other fields
    n = n + 64
    return n
end

--------------------------------------------------------------------------------
-- INTERNAL: access notes DB safely
--------------------------------------------------------------------------------
local function NDB()
    return BigNoteBoxNotesDB or {}
end

local function MaxSlots()
    local db = BigNoteBoxDB
    local n  = db and db.historyMaxSlots or 5
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
    local ndb  = NDB()
    local note = ndb.notes and ndb.notes[id]
    if not note then return false end

    -- Ensure history array exists
    if not note.history then note.history = {} end
    local hist = note.history

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
    local ndb  = NDB()
    local note = ndb.notes and ndb.notes[id]
    if not note or not note.history then return end
    table.remove(note.history, index)
    if #note.history == 0 then note.history = nil end
    BNB.SyncHistoryBtnState()
    BNB.SyncHistoryNoteBtnState()
end

--------------------------------------------------------------------------------
-- HistoryDeleteAuto — wipe only auto snapshots for one note.
-- Manual restore points (note.manualSnapshot) are preserved.
--------------------------------------------------------------------------------
function BNB.HistoryDeleteAuto(id)
    local ndb  = NDB()
    local note = ndb.notes and ndb.notes[id]
    if not note then return end
    note.history = nil
    BNB.SyncHistoryBtnState()
    BNB.SyncHistoryNoteBtnState()
end

--------------------------------------------------------------------------------
-- HistoryDeleteAll — wipe all history (auto + manual) for one note.
--------------------------------------------------------------------------------
function BNB.HistoryDeleteAll(id)
    local ndb  = NDB()
    local note = ndb.notes and ndb.notes[id]
    if not note then return end
    note.history        = nil
    note.manualSnapshot = nil
    BNB.SyncHistoryBtnState()
    BNB.SyncHistoryNoteBtnState()
end

--------------------------------------------------------------------------------
-- HistoryGetSlots — returns {auto={snap,...}, manual=snap|nil} for a note.
-- auto is always a table (may be empty). manual may be nil.
--------------------------------------------------------------------------------
function BNB.HistoryGetSlots(id)
    local ndb  = NDB()
    local note = ndb.notes and ndb.notes[id]
    if not note then return { auto = {}, manual = nil } end
    return {
        auto   = note.history or {},
        manual = note.manualSnapshot or nil,
    }
end

--------------------------------------------------------------------------------
-- HistoryNoteHasAny — true if a note has any history at all.
--------------------------------------------------------------------------------
function BNB.HistoryNoteHasAny(id)
    local ndb  = NDB()
    local note = ndb.notes and ndb.notes[id]
    if not note then return false end
    if note.manualSnapshot then return true end
    return note.history and #note.history > 0
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
    return false
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
        if not note.history then note.history = {} end
        table.insert(note.history, 1, MakeSnap(note))
        local max = MaxSlots()
        while #note.history > max do table.remove(note.history) end
    end

    -- Apply snapshot fields to live note
    for _, field in ipairs(SNAP_FIELDS) do
        if snap[field] ~= nil then
            note[field] = DeepCopy(snap[field])
        else
            note[field] = nil
        end
    end
    note.updated = time()

    -- Refresh the editor if this note is currently open
    if BNB._currentNoteID == id then
        if BNB.LoadNoteInEditor then BNB.LoadNoteInEditor(id) end
    end
    if BNB.RefreshNoteList     then BNB.RefreshNoteList()     end
    if BNB.Sticky and BNB.Sticky.RefreshNote then
        BNB.Sticky.RefreshNote(id)
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
    btn:SetEnabled(has)
    btn:SetAlpha(has and 1.0 or 0.4)
    pcall(function() btn._tx:SetDesaturated(not has) end)
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
    if BNB.HistorySnapshotAll then
        BNB.HistorySnapshotAll()
    end
end)

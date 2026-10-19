-- BigNoteBox Features/UndoKeep.lua
--
-- Keep undo / redo between sessions (ALL-460, Dukul 2026-10-13). Opt-in:
-- db.undoKeep. The stacks are saved in the SavedVariables of the separate
-- addon BigNoteBox_History (BigNoteBoxHistoryDB, BNB.HistoryDB), so their size
-- never touches the settings or notes files. Off, or that addon missing or
-- disabled = undo lasts for the session only, as before.
--
-- LOAD: BigNoteBox_History is always loaded since ALL-466 (it was load on
--   demand); the first use of the saved stacks in a session (a note opened in
--   the editor, an edit, the Undo / Redo page) prunes: entries older than
--   undoKeepDays, and entries of notes that no longer exist.
-- SAVE: only at PLAYER_LOGOUT (SavedVariables are written then anyway), only
--   the notes whose stacks changed this session. Each note is one entry
--   { t = time() of the save, d = LibSerialize + LibDeflate + EncodeForPrint
--   of { u = undo stack, r = redo stack, s = current snapshot } }. Before it is
--   written, the current snapshot is brought level with note.body, so on the
--   next open s.text == the note's text.
-- RESTORE: the first UndoReset of a note this session. The saved s.text must
--   equal the note's text exactly; a note changed somewhere else since (the
--   other PC, an import, the setting off while it was edited) has its saved
--   history dropped (Dukul: "Drop it"). A saved note changed this session
--   outside the editor (a sticky edit) gets that change as one step at logout,
--   as UndoReset does inside a session, so it is not dropped next time.
-- CAPS: NOTE_CAP per note (oldest half of the steps dropped until it fits),
--   TOTAL_CAP for the whole file (oldest entries dropped first).
--
-- Store layout: BigNoteBoxHistoryDB.notes = { [id] = entry }, .dev = { [id] =
-- entry } ("dev" = dev mode's own notes set, "docs" = doc mode's, ALL-512). The rest of the file is the
-- automatic note history (Core/Database.lua, ALL-466).

local BNB = BigNoteBox

local NOTE_CAP  = 1024 * 1024        -- encoded bytes per note
local TOTAL_CAP = 10 * 1024 * 1024   -- encoded bytes for the whole file

local _store    = nil     -- BigNoteBoxHistoryDB after the first use (pruned then)
local _dirty    = {}      -- [noteID] = true: stacks changed this session

-- Off while the history addon is missing or disabled (ALL-466); the saved
-- switch is left alone
function BNB.UndoKeepEnabled()
    if not BNB.HistoryAddonLoaded() then return false end
    return BigNoteBoxDB and BigNoteBoxDB.undoKeep == true or false
end

local function KeepDays()
    local d = BigNoteBoxDB and BigNoteBoxDB.undoKeepDays or BNB.DEFAULTS.undoKeepDays
    if d < 1 then d = 1 elseif d > 30 then d = 30 end
    return d
end

-- A live note or one in the trash (it can come back with its history)
local function NoteAny(id)
    local ndb = BNB.NotesDB and BNB.NotesDB()
    if not ndb then return nil end
    return (ndb.notes and ndb.notes[id]) or (ndb.trash and ndb.trash[id]) or nil
end

local function Debug(msg)
    if BNB.IsDebugMode and BNB.IsDebugMode() then BNB:Print("Undo keep: " .. msg) end
end

local function Bucket()
    if not _store then return nil end
    local k = BNB.HistorySetKey()
    if type(_store[k]) ~= "table" then _store[k] = {} end
    return _store[k]
end

--------------------------------------------------------------------------------
-- Codec
--------------------------------------------------------------------------------
local function Libs()
    return LibStub and LibStub("LibSerialize", true), LibStub and LibStub("LibDeflate", true)
end

local function Encode(u, r, s)
    local LS, LD = Libs()
    if not (LS and LD) then return nil end
    local ok, out = pcall(function()
        local c = LD:CompressDeflate(LS:Serialize({ u = u, r = r, s = s }), { level = 3 })
        return c and LD:EncodeForPrint(c)
    end)
    return ok and out or nil
end

local function Decode(d)
    local LS, LD = Libs()
    if not (LS and LD) or type(d) ~= "string" then return nil end
    local ok, t = pcall(function()
        local c = LD:DecodeForPrint(d)
        local raw = c and LD:DecompressDeflate(c)
        if not raw then return nil end
        local okDs, v = LS:Deserialize(raw)
        return okDs and v or nil
    end)
    if not (ok and type(t) == "table" and type(t.s) == "table" and type(t.s.text) == "string") then return nil end
    t.u = type(t.u) == "table" and t.u or {}
    t.r = type(t.r) == "table" and t.r or {}
    return t
end

--------------------------------------------------------------------------------
-- Load + prune
--------------------------------------------------------------------------------
local function Prune()
    local cutoff = time() - KeepDays() * 86400
    for _, k in ipairs({ "notes", "dev", "docs" }) do
        local b = _store[k]
        if type(b) == "table" then
            for id, e in pairs(b) do
                if type(e) ~= "table" or type(e.d) ~= "string" or (e.t or 0) < cutoff then b[id] = nil end
            end
        end
    end
    -- Deleted notes (gone from the trash too): only the active set can be asked
    local b, ndb = Bucket(), BNB.NotesDB and BNB.NotesDB()
    if ndb and ndb.notes then
        for id in pairs(b) do
            if not NoteAny(id) then b[id] = nil end
        end
    end
end

-- The history file (set up by BNB.InitHistoryDB at ADDON_LOADED), pruned on
-- the first use of the session. False = the history addon is not there.
local function EnsureLoaded()
    if _store then return true end
    _store = BNB.HistoryDB()
    if _store then Prune() end
    return _store ~= nil
end

--------------------------------------------------------------------------------
-- Hooks called by Features/UndoManager.lua
--------------------------------------------------------------------------------

-- First UndoReset of a note this session. True when its saved history was put
-- back (the caller then has nothing to seed).
function BNB.UndoKeepRestore(noteID, text)
    if not BNB.UndoKeepEnabled() or not EnsureLoaded() then return false end
    local b = Bucket()
    local e = b[noteID]
    if not e then return false end
    local t = Decode(e.d)
    if not t or t.s.text ~= (text or "") then
        b[noteID] = nil
        Debug(string.format("%s dropped (%s)", tostring(noteID), t and "text changed" or "unreadable"))
        return false
    end
    BNB.UndoAdopt(noteID, t.u, t.r, t.s)
    return true
end

-- A note's stacks changed: written at logout
function BNB.UndoKeepTouch(noteID)
    if not BNB.UndoKeepEnabled() then return end
    if EnsureLoaded() then _dirty[noteID] = true end
end

-- A note was deleted or moved to the trash
function BNB.UndoKeepForget(noteID)
    _dirty[noteID] = nil
    local b = Bucket()
    if b then b[noteID] = nil end
end

--------------------------------------------------------------------------------
-- Settings page (UI/Config/NotePages.lua, K.BuildUndoPage)
--------------------------------------------------------------------------------

-- Switch from the page. Off keeps what is saved. The page greys the switch
-- while the history addon is missing (ALL-466).
function BNB.UndoKeepApply(on)
    if not BigNoteBoxDB then return end
    BigNoteBoxDB.undoKeep = on and true or false
end

-- bytes, notes of the saved history (active notes set); nil = the history
-- addon is not available
function BNB.UndoKeepSize()
    if not EnsureLoaded() then return nil end
    local bytes, n = 0, 0
    for _, e in pairs(Bucket()) do bytes = bytes + #e.d; n = n + 1 end
    return bytes, n
end

-- The notes with saved or pending undo history (ALL-465), newest first:
-- { id, bytes, t, pending }. pending = changed this session, written at
-- logout (bytes / t are the last save's, nil when it was never saved).
-- nil = the history addon is not available.
function BNB.UndoKeepList()
    if not EnsureLoaded() then return nil end
    local b, list, seen = Bucket(), {}, {}
    for id, e in pairs(b) do
        if BNB.GetNote(id) then
            list[#list + 1] = { id = id, bytes = #e.d, t = e.t or 0, pending = _dirty[id] == true }
            seen[id] = true
        end
    end
    if BNB.UndoKeepEnabled() then
        for id in pairs(_dirty) do
            if not seen[id] and BNB.GetNote(id) and (BNB.UndoCanUndo(id) or BNB.UndoCanRedo(id)) then
                list[#list + 1] = { id = id, t = time(), pending = true }
            end
        end
    end
    table.sort(list, function(x, y)
        if x.pending ~= y.pending then return x.pending end
        return x.t > y.t
    end)
    return list
end

-- One note's undo history gone: saved and this session's (the X on its row)
function BNB.UndoKeepDeleteNote(noteID)
    if not noteID then return end
    BNB.UndoClearNote(noteID)   -- memory, and UndoKeepForget for the saved entry
    if BNB._refreshUndoButtons then BNB._refreshUndoButtons() end
end

-- Reset: everything saved (both notes sets) and this session's undo history.
-- activeOnly = the active notes set's saved stacks only (Factory Reset, which
-- in dev mode must not touch the real notes' history).
function BNB.UndoKeepReset(activeOnly)
    if EnsureLoaded() then
        if activeOnly then
            _store[BNB.HistorySetKey()] = {}
        else
            _store.notes, _store.dev = {}, {}
        end
    end
    wipe(_dirty)
    if BNB.UndoClearAll then BNB.UndoClearAll() end
end

--------------------------------------------------------------------------------
-- Logout: write what changed. Registered after NoteManager's logout save (TOC
-- order), so note.body already holds the last edit.
--------------------------------------------------------------------------------
local function Shrink(u, r, s)
    local d = Encode(u, r, s)
    while d and #d > NOTE_CAP and (#u > 0 or #r > 0) do
        if #r > 0 then r = {} else u = { unpack(u, math.floor(#u / 2) + 1) } end
        d = Encode(u, r, s)
    end
    if d and #d <= NOTE_CAP then return d end
    return nil
end

BNB.RegisterEvent("PLAYER_LOGOUT", function()
    if not (_store and BNB.UndoKeepEnabled()) then return end
    local b, now = Bucket(), time()

    -- Saved notes changed outside the editor this session: the change becomes
    -- one step, so the text still matches next time
    for id, e in pairs(b) do
        if not _dirty[id] and not BNB._undoSnap[id] then
            local note = BNB.GetNote(id)
            local body = note and note.body or ""
            if note and (note.updated or 0) > (e.t or 0) then
                local t = Decode(e.d)
                if t and t.s.text ~= body then
                    local depth = BNB.UndoMaxDepth and BNB.UndoMaxDepth() or 50
                    t.u[#t.u + 1] = t.s
                    while #t.u > depth do table.remove(t.u, 1) end
                    local d = Shrink(t.u, {}, { text = body, cursor = 0 })
                    if d then e.t, e.d = now, d else b[id] = nil end
                end
            end
        end
    end

    -- This session's changes
    for id in pairs(_dirty) do
        local note = NoteAny(id)   -- a note in the trash keeps its history
        if note and BNB._undoSnap[id] and BNB._undoSnap[id].text ~= (note.body or "") then
            BNB.UndoReset(id, note.body or "")   -- an unsnapped last edit becomes one step
        end
        local snap = BNB._undoSnap[id]
        local u, r = BNB._undoStack[id] or {}, BNB._redoStack[id] or {}
        if not (note and snap) or (#u == 0 and #r == 0) then
            b[id] = nil
        else
            local d = Shrink(u, r, snap)
            if d then b[id] = { t = now, d = d } else b[id] = nil end
        end
    end

    -- Whole file over its cap: oldest entries go first
    local list, total = {}, 0
    for _, k in ipairs({ "notes", "dev", "docs" }) do
        for id, e in pairs(_store[k] or {}) do
            list[#list + 1] = { k = k, id = id, t = e.t or 0, n = #e.d }
            total = total + #e.d
        end
    end
    if total > TOTAL_CAP then
        table.sort(list, function(x, y) return x.t < y.t end)
        for _, x in ipairs(list) do
            if total <= TOTAL_CAP then break end
            _store[x.k][x.id] = nil
            total = total - x.n
        end
    end
end)

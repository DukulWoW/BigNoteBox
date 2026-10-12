-- BigNoteBox Features/UndoManager.lua
--
-- Per-note undo/redo history. Runtime only — stacks are never persisted to
-- SavedVariables. History is lost on reload/logout, which is correct and
-- expected behaviour (identical to every other text editor). Within a session
-- it is kept per note across note switches and Focus mode (ALL-451), under an
-- 8 MB budget; saving it to disk was left out (Dukul, 2026-10-12: the History
-- module already covers recovery after a reload).
--
-- ARCHITECTURE:
--   Each note has its own independent stacks keyed by note ID.
--   BNB._undoStack[id]  — table of {text, cursor} snapshots, [1]=oldest
--   BNB._redoStack[id]  — same structure, populated on undo
--   BNB._undoSnap[id]   — the "current" snapshot (what typing started from)
--
-- SNAPSHOT TRIGGER:
--   NoteEditor calls BNB.UndoPush() from a debounced OnTextChanged handler
--   (0.4s). The first keystroke after loading a note pushes an immediate
--   "before" snapshot so Undo always has a clean starting point.
--
-- DEPTH:
--   Controlled by BigNoteBoxDB.undoDepth (default 50, range 10-200).
--   Read live — changing the slider takes effect on the next push.
--   When the stack is full, the oldest entry is evicted.
--
-- GUARD FLAG:
--   BNB._undoActive is set true during SetText() calls triggered by undo/redo
--   so that the OnTextChanged debounce handler does not push a spurious
--   snapshot while the text is being restored.
--
-- PUBLIC API:
--   BNB.UndoReset(noteID, text)           Called by LoadNoteInEditor: keeps, seeds or adds an outside change
--   BNB.UndoPush(noteID, text, cursor)    Called by debounced OnTextChanged
--   BNB.UndoStep(noteID)  -> text, cursor Perform undo; returns nil if empty
--   BNB.RedoStep(noteID)  -> text, cursor Perform redo; returns nil if empty
--   BNB.UndoCanUndo(noteID) -> bool
--   BNB.UndoCanRedo(noteID) -> bool
--   BNB.UndoClearNote(noteID)             Called when a note is deleted

local BNB = BigNoteBox

-- Runtime stacks (module-level, gone on reload)
BNB._undoStack  = BNB._undoStack  or {}
BNB._redoStack  = BNB._redoStack  or {}
BNB._undoSnap   = BNB._undoSnap   or {}
BNB._undoActive = false

--------------------------------------------------------------------------------
-- INTERNAL: max depth from settings (clamped to valid range)
--------------------------------------------------------------------------------
local function MaxDepth()
    local db = BigNoteBoxDB
    local d  = db and db.undoDepth or BNB.DEFAULTS.undoDepth
    if d < 10  then d = 10  end
    if d > 200 then d = 200 end
    return d
end

--------------------------------------------------------------------------------
-- INTERNAL: session memory budget (ALL-451, Dukul 2026-10-12: 8 MB). Every
-- step holds the whole text, so the history of every note edited in a session
-- adds up: over the budget, the note edited longest ago loses its stacks
-- first; a single note over it on its own loses its oldest steps.
--------------------------------------------------------------------------------
local BUDGET  = 8 * 1024 * 1024
local _bytes  = {}   -- [noteID] = text bytes held in its stacks
local _used   = {}   -- [noteID] = GetTime() of its last push / step
local _total  = 0

local function Recount(noteID)
    local n = 0
    for _, s in ipairs(BNB._undoStack[noteID] or {}) do n = n + #s.text end
    for _, s in ipairs(BNB._redoStack[noteID] or {}) do n = n + #s.text end
    _total = _total - (_bytes[noteID] or 0) + n
    _bytes[noteID] = n
end

local function Trim(noteID)
    _used[noteID] = GetTime()
    Recount(noteID)
    while _total > BUDGET do
        local oldest, at
        for id, t in pairs(_used) do
            if id ~= noteID and (_bytes[id] or 0) > 0 and (not at or t < at) then oldest, at = id, t end
        end
        if oldest then
            BNB._undoStack[oldest], BNB._redoStack[oldest] = {}, {}
            Recount(oldest)
        else
            local stack = BNB._undoStack[noteID]
            if not stack or #stack == 0 then break end
            table.remove(stack, 1)
            Recount(noteID)
        end
    end
end

--------------------------------------------------------------------------------
-- UndoReset — call when loading a note into the editor (a note switch, back
-- from Focus mode). The note's history is kept for the whole session
-- (ALL-451); only a note with none is seeded. A body changed outside the
-- editor since (sticky edit, history restore, import) becomes one undo step,
-- so Undo goes back across it and nothing is lost.
--------------------------------------------------------------------------------
function BNB.UndoReset(noteID, text)
    -- Do not clear other notes' stacks — they may have stickies open.
    if not noteID then return end
    text = text or ""
    local snap = BNB._undoSnap[noteID]
    if not snap then
        BNB._undoStack[noteID] = {}
        BNB._redoStack[noteID] = {}
        BNB._undoSnap[noteID]  = { text = text, cursor = 0 }
        return
    end
    if snap.text == text then return end
    local stack = BNB._undoStack[noteID] or {}
    BNB._undoStack[noteID] = stack
    if #stack >= MaxDepth() then table.remove(stack, 1) end
    stack[#stack + 1] = snap
    BNB._undoSnap[noteID]  = { text = text, cursor = 0 }
    BNB._redoStack[noteID] = {}
    Trim(noteID)
end

--------------------------------------------------------------------------------
-- UndoPush — called from the debounced OnTextChanged handler in NoteEditor.
-- Pushes a snapshot only when the text has actually changed from the last one.
--------------------------------------------------------------------------------
function BNB.UndoPush(noteID, text, cursor)
    if not noteID then return end
    if BNB._undoActive then return end

    local snap = BNB._undoSnap[noteID]
    -- First push for this note: initialise snapshot silently
    if not snap then
        BNB._undoSnap[noteID]  = { text = text, cursor = cursor or 0 }
        BNB._undoStack[noteID] = {}
        BNB._redoStack[noteID] = {}
        return
    end

    -- No change — skip (also guards against autosave re-triggering)
    if text == snap.text then return end

    -- Push current snapshot onto the undo stack
    local stack = BNB._undoStack[noteID] or {}
    BNB._undoStack[noteID] = stack

    local depth = MaxDepth()
    if #stack >= depth then
        table.remove(stack, 1)   -- evict oldest
    end
    stack[#stack + 1] = snap

    -- Update current snapshot to the new state
    BNB._undoSnap[noteID] = { text = text, cursor = cursor or 0 }

    -- Any new edit wipes the redo stack
    BNB._redoStack[noteID] = {}
    Trim(noteID)
end

--------------------------------------------------------------------------------
-- UndoStep — perform one undo for noteID.
-- Returns text, cursor of the restored state, or nil if stack is empty.
--------------------------------------------------------------------------------
function BNB.UndoStep(noteID)
    if not noteID then return nil end
    local stack = BNB._undoStack[noteID]
    if not stack or #stack == 0 then return nil end

    -- Push current snapshot onto redo
    local curSnap = BNB._undoSnap[noteID]
    if curSnap then
        local rstack = BNB._redoStack[noteID] or {}
        BNB._redoStack[noteID] = rstack
        rstack[#rstack + 1] = curSnap
    end

    -- Pop from undo and make it the new current snapshot
    local snap = table.remove(stack)  -- removes last (newest)
    BNB._undoSnap[noteID] = snap
    Trim(noteID)
    return snap.text, snap.cursor
end

--------------------------------------------------------------------------------
-- RedoStep — perform one redo for noteID.
-- Returns text, cursor of the restored state, or nil if stack is empty.
--------------------------------------------------------------------------------
function BNB.RedoStep(noteID)
    if not noteID then return nil end
    local rstack = BNB._redoStack[noteID]
    if not rstack or #rstack == 0 then return nil end

    -- Push current snapshot onto undo
    local curSnap = BNB._undoSnap[noteID]
    if curSnap then
        local stack = BNB._undoStack[noteID] or {}
        BNB._undoStack[noteID] = stack
        local depth = MaxDepth()
        if #stack >= depth then table.remove(stack, 1) end
        stack[#stack + 1] = curSnap
    end

    local snap = table.remove(rstack)  -- removes last (most recent undo)
    BNB._undoSnap[noteID] = snap
    Trim(noteID)
    return snap.text, snap.cursor
end

--------------------------------------------------------------------------------
-- UndoCanUndo / UndoCanRedo — used to enable/disable toolbar buttons
--------------------------------------------------------------------------------
function BNB.UndoCanUndo(noteID)
    if not noteID then return false end
    local s = BNB._undoStack[noteID]
    return s ~= nil and #s > 0
end

function BNB.UndoCanRedo(noteID)
    if not noteID then return false end
    local s = BNB._redoStack[noteID]
    return s ~= nil and #s > 0
end

--------------------------------------------------------------------------------
-- UndoClearNote — free memory when a note is deleted or moved to trash
--------------------------------------------------------------------------------
function BNB.UndoClearNote(noteID)
    if not noteID then return end
    BNB._undoStack[noteID] = nil
    BNB._redoStack[noteID] = nil
    BNB._undoSnap[noteID]  = nil
    _total = _total - (_bytes[noteID] or 0)
    _bytes[noteID], _used[noteID] = nil, nil
end

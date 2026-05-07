-- BigNoteBox Features/UndoManager.lua
--
-- Per-note undo/redo history. Runtime only — stacks are never persisted to
-- SavedVariables. History is lost on reload/logout, which is correct and
-- expected behaviour (identical to every other text editor).
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
--   BNB.UndoReset(noteID, text)           Called by LoadNoteInEditor on note switch
--   BNB.UndoPush(noteID, text, cursor)    Called by debounced OnTextChanged
--   BNB.UndoStep(noteID)  -> text, cursor Perform undo; returns nil if empty
--   BNB.RedoStep(noteID)  -> text, cursor Perform redo; returns nil if empty
--   BNB.UndoCanUndo(noteID) -> bool
--   BNB.UndoCanRedo(noteID) -> bool
--   BNB.UndoClearNote(noteID)             Called when a note is deleted
--   BNB.UndoClearAll()                    Called on factory reset / wipe

local BNB = BigNoteBox

-- Runtime stacks (module-level, cleared on UndoClearAll)
BNB._undoStack  = BNB._undoStack  or {}
BNB._redoStack  = BNB._redoStack  or {}
BNB._undoSnap   = BNB._undoSnap   or {}
BNB._undoActive = false

--------------------------------------------------------------------------------
-- INTERNAL: max depth from settings (clamped to valid range)
--------------------------------------------------------------------------------
local function MaxDepth()
    local db = BigNoteBoxDB
    local d  = db and db.undoDepth or 50
    if d < 10  then d = 10  end
    if d > 200 then d = 200 end
    return d
end

--------------------------------------------------------------------------------
-- UndoReset — call when loading a different note into the editor.
-- Clears stacks for any previous note and seeds the snapshot for the new one.
--------------------------------------------------------------------------------
function BNB.UndoReset(noteID, text)
    -- Do not clear other notes' stacks — they may have stickies open.
    if noteID then
        BNB._undoStack[noteID] = {}
        BNB._redoStack[noteID] = {}
        BNB._undoSnap[noteID]  = { text = text or "", cursor = 0 }
    end
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
end

--------------------------------------------------------------------------------
-- UndoClearAll — called on factory reset
--------------------------------------------------------------------------------
function BNB.UndoClearAll()
    BNB._undoStack  = {}
    BNB._redoStack  = {}
    BNB._undoSnap   = {}
    BNB._undoActive = false
end

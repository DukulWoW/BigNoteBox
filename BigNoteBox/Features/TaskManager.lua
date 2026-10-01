-- BigNoteBox Features/TaskManager.lua
-- Task system -- data layer, reset logic, situation hooks.
--
-- Public API (all on BNB.Task):
--   BNB.Task.GetList(noteID)                  -> taskList or nil
--   BNB.Task.GetTasks(noteID)                 -> tasks array (may be empty)
--   BNB.Task.AddTask(noteID, text, parentID)  -> taskID or nil
--   BNB.Task.UpdateTask(noteID, taskID, changes)
--   BNB.Task.DeleteTask(noteID, taskID)
--   BNB.Task.ToggleTask(noteID, taskID)
--   BNB.Task.GetCompletionCount(noteID)       -> done, total
--   BNB.Task.ClearCompleted(noteID)
--   BNB.Task.HasTasks(noteID)                 -> bool
--   BNB.Task.CheckResets()                    -> called on login + daily ticker
--   BNB.Task.OnContextChanged()               -> called by ContextNotes on zone/target change
--
-- Callbacks (register via BNB.Task.RegisterCallback):
--   "TasksChanged" (noteID)  -- fired after any mutation to a note's task list

local BNB = BigNoteBox

--------------------------------------------------------------------------------
-- NAMESPACE
--------------------------------------------------------------------------------
BNB.Task = BNB.Task or {}
local T = BNB.Task

--------------------------------------------------------------------------------
-- CONSTANTS
--------------------------------------------------------------------------------
-- Completion display colours
local COLOR_DONE   = { r = 0.45, g = 0.45, b = 0.48 }  -- greyed text
local COLOR_ACTIVE = { r = 1.00, g = 1.00, b = 1.00 }  -- normal text

-- Sub-task indent (px) -- used by ReferenceBox renderer
T.SUBTASK_INDENT = 14

--------------------------------------------------------------------------------
-- CALLBACKS
--------------------------------------------------------------------------------
local _callbacks = {}

function T.RegisterCallback(event, fn)
    _callbacks[event] = _callbacks[event] or {}
    _callbacks[event][#_callbacks[event] + 1] = fn
end

local function Fire(event, ...)
    if not _callbacks[event] then return end
    for _, fn in ipairs(_callbacks[event]) do
        pcall(fn, ...)
    end
end

-- Public: notify TasksChanged listeners (ReferenceBox, StickyNote, NoteList)
-- after a write that bypasses T's own mutation functions, e.g. a history
-- restore that replaces note.tasks wholesale (ALL-65.6).
function T.NotifyTasksChanged(noteID)
    Fire("TasksChanged", noteID)
end

--------------------------------------------------------------------------------
-- HELPERS -- note access
--------------------------------------------------------------------------------
local function GetNoteRaw(noteID)
    return BNB.GetNote and BNB.GetNote(noteID)
end

-- Returns mutable reference to note.tasks (creates if absent).
-- IMPORTANT: callers must never replace the array reference -- mutate in place
-- or call BNB.UpdateNote to persist the whole field.
local function GetOrCreateTasksTable(noteID)
    local note = GetNoteRaw(noteID)
    if not note then return nil end
    if not note.tasks then
        note.tasks = {}
    end
    return note.tasks
end

local function GetOrCreateTaskList(noteID)
    local note = GetNoteRaw(noteID)
    if not note then return nil end
    if not note.taskList then
        note.taskList = {}
    end
    return note.taskList
end

-- Persist after any direct mutation to note.tasks / note.taskList.
-- BNB.UpdateNote with the full field is the safe way; direct mutation on the
-- live reference also works because BNB stores by reference in BigNoteBoxNotesDB,
-- but we call UpdateNote with a dummy field to trigger the save/autosave path.
local function Persist(noteID)
    -- Touching updatedAt keeps history consistent.
    BNB.UpdateNote(noteID, { updatedAt = time() })
end

--------------------------------------------------------------------------------
-- ID GENERATION
--------------------------------------------------------------------------------
local function NewTaskID()
    return BNB.GenerateID and BNB.GenerateID()
        or string.format("task-%08x%04x", time(), math.random(0, 0xFFFF))
end

--------------------------------------------------------------------------------
-- QUERY
--------------------------------------------------------------------------------

-- Returns note.taskList (may be nil if never initialised -- that's fine).
function T.GetList(noteID)
    local note = GetNoteRaw(noteID)
    return note and note.taskList
end

-- Returns note.tasks array, or {} if none. Never nil.
function T.GetTasks(noteID)
    local note = GetNoteRaw(noteID)
    if not note or not note.tasks then return {} end
    return note.tasks
end

-- Returns true if note has at least one task.
function T.HasTasks(noteID)
    local note = GetNoteRaw(noteID)
    return note and note.tasks and #note.tasks > 0
end

-- The Tasks module switch (Settings > Modules > Tasks, ALL-102). Off hides
-- every way in (editor bar, Reference Box panel, note list, stickies); the
-- task data stays, so switching it back on brings every task back.
function BNB.TasksEnabled()
    return not BigNoteBoxDB or BigNoteBoxDB.tasksEnabled ~= false
end

-- HasTasks for anything that draws tasks: false while the module is off.
function T.Shows(noteID)
    return BNB.TasksEnabled() and T.HasTasks(noteID) or false
end

-- Returns done count, total count.
function T.GetCompletionCount(noteID)
    local tasks = T.GetTasks(noteID)
    local done, total = 0, 0
    for _, task in ipairs(tasks) do
        total = total + 1
        if task.completed then done = done + 1 end
    end
    return done, total
end

-- Returns colour for a task row's text.
function T.GetTaskColor(task)
    return task.completed and COLOR_DONE or COLOR_ACTIVE
end

-- Returns top-level tasks in order. Does not include sub-tasks.
function T.GetTopLevel(noteID)
    local out = {}
    for _, task in ipairs(T.GetTasks(noteID)) do
        if not task.parentID then
            out[#out + 1] = task
        end
    end
    table.sort(out, function(a, b) return (a.order or 0) < (b.order or 0) end)
    return out
end

-- Returns sub-tasks of parentID in order.
function T.GetSubTasks(noteID, parentID)
    local out = {}
    for _, task in ipairs(T.GetTasks(noteID)) do
        if task.parentID == parentID then
            out[#out + 1] = task
        end
    end
    table.sort(out, function(a, b) return (a.order or 0) < (b.order or 0) end)
    return out
end

-- Find a task by ID. Returns task table or nil.
function T.FindTask(noteID, taskID)
    for _, task in ipairs(T.GetTasks(noteID)) do
        if task.id == taskID then return task end
    end
    return nil
end

--------------------------------------------------------------------------------
-- MUTATION
--------------------------------------------------------------------------------

-- Add a new task. parentID = nil for top-level, uuid for sub-task.
-- Returns the new task ID, or nil on failure.
function T.AddTask(noteID, text, parentID)
    local tasks = GetOrCreateTasksTable(noteID)
    if not tasks then return nil end

    -- Calculate next order value within the same parent group.
    local maxOrder = 0
    for _, t in ipairs(tasks) do
        if t.parentID == parentID and (t.order or 0) > maxOrder then
            maxOrder = t.order or 0
        end
    end

    -- Inherit note-level taskList defaults for resetType (read-only, don't
    -- create taskList as a side effect -- it's only needed if the user
    -- explicitly configures list-level settings).
    local note = GetNoteRaw(noteID)
    local tl = note and note.taskList

    local task = {
        id         = NewTaskID(),
        text       = text or "",
        completed  = false,
        order      = maxOrder + 1,
        parentID   = parentID or nil,
        resetType  = tl and tl.resetType  or nil,
        resetEvery = tl and tl.resetEvery or nil,
        resetDate  = nil,
        lastReset  = nil,
        situation  = nil,
    }
    tasks[#tasks + 1] = task
    Persist(noteID)
    Fire("TasksChanged", noteID)
    return task.id
end

-- Every change to `completed` goes through these two. completedAt is when the
-- task was checked: daily/weekly resets uncheck a task done before the last
-- reset, "every N days" one done N days ago (ALL-136.3; lastReset alone made a
-- task with no reset yet uncheck within a minute of being checked).
local function SetDone(task)
    if not task.completed then
        task.completed   = true
        task.completedAt = time()
    end
end

local function SetUndone(task)
    task.completed   = false
    task.completedAt = nil
end

-- Clear a task's completed state with the ToggleTask propagation rules:
-- a parent takes its sub-tasks along, a sub-task takes its parent.
local function Uncomplete(noteID, task)
    SetUndone(task)
    if not task.parentID then
        for _, sub in ipairs(T.GetSubTasks(noteID, task.id)) do
            SetUndone(sub)
        end
    else
        local parent = T.FindTask(noteID, task.parentID)
        if parent then SetUndone(parent) end
    end
end

-- Update fields on an existing task. Supports _clear array (same as UpdateNote).
-- A new text on a completed task unchecks it (ALL-74: only when the text changed).
function T.UpdateTask(noteID, taskID, changes)
    local task = T.FindTask(noteID, taskID)
    if not task then return end
    if task.completed and changes.text ~= nil and changes.text ~= task.text then
        Uncomplete(noteID, task)
    end
    for k, v in pairs(changes) do
        if k ~= "_clear" then task[k] = v end
    end
    if changes._clear then
        for _, k in ipairs(changes._clear) do task[k] = nil end
    end
    Persist(noteID)
    Fire("TasksChanged", noteID)
end

-- Toggle completed state on a task.
-- Propagation rules:
--   Completing a parent   → completes all sub-tasks too.
--   Uncompleting a parent → uncompletes all sub-tasks too.
--   Completing a sub-task → if it is the last incomplete sibling, completes the parent.
--   Uncompleting a sub-task → uncompletes the parent (can't be done with undone children).
function T.ToggleTask(noteID, taskID)
    local task = T.FindTask(noteID, taskID)
    if not task then return end

    local db = BigNoteBoxDB
    local removeOnComplete = db and db.taskRemoveOnComplete

    if not task.completed then
        -- ── Completing ───────────────────────────────────────────────────────
        SetDone(task)

        if not task.parentID then
            -- Parent: complete all sub-tasks first
            local subs = T.GetSubTasks(noteID, taskID)
            for _, sub in ipairs(subs) do
                SetDone(sub)
            end
        end

        if removeOnComplete then
            -- DeleteTask handles the task + all descendants recursively.
            -- For a sub-task we also need to check if the parent should now
            -- be deleted, so do that check before deleting this task.
            if task.parentID then
                local allDone = true
                for _, sib in ipairs(T.GetSubTasks(noteID, task.parentID)) do
                    if not sib.completed then allDone = false; break end
                end
                if allDone then
                    -- Delete the parent (and all its descendants including this task).
                    T.DeleteTask(noteID, task.parentID)
                    return  -- DeleteTask fires callback and persists
                end
            end
            T.DeleteTask(noteID, taskID)
            return  -- DeleteTask fires callback and persists
        end

        -- Not removing: check if last sub-task just completed the parent
        if task.parentID then
            local allDone = true
            for _, sib in ipairs(T.GetSubTasks(noteID, task.parentID)) do
                if not sib.completed then allDone = false; break end
            end
            if allDone then
                local parent = T.FindTask(noteID, task.parentID)
                if parent then SetDone(parent) end
            end
        end

    else
        -- ── Uncompleting ─────────────────────────────────────────────────────
        -- Parent unchecked: uncheck all sub-tasks. Sub-task unchecked: uncheck parent too.
        Uncomplete(noteID, task)
    end

    Persist(noteID)
    Fire("TasksChanged", noteID)
end

-- Delete a task and all its descendants (recursive).
function T.DeleteTask(noteID, taskID)
    local tasks = GetOrCreateTasksTable(noteID)
    if not tasks then return end

    -- Collect IDs to remove: the task itself + all descendants.
    -- Loop until no new children are found (handles deeper nesting).
    local toRemove = { [taskID] = true }
    local found = true
    while found do
        found = false
        for _, t in ipairs(tasks) do
            if t.parentID and toRemove[t.parentID] and not toRemove[t.id] then
                toRemove[t.id] = true
                found = true
            end
        end
    end

    -- Remove in reverse to avoid index shifting issues.
    for i = #tasks, 1, -1 do
        if toRemove[tasks[i].id] then
            table.remove(tasks, i)
        end
    end

    Persist(noteID)
    Fire("TasksChanged", noteID)
end

-- Clear completed tasks. Behaviour depends on db.taskRemoveOnComplete:
--   false (default) -> uncheck all completed tasks
--   true            -> delete all completed tasks
function T.ClearCompleted(noteID)
    local tasks = GetOrCreateTasksTable(noteID)
    if not tasks then return end

    local db = BigNoteBoxDB
    local remove = db and db.taskRemoveOnComplete

    if remove then
        T.DeleteCompleted(noteID)
        return
    else
        -- Uncheck all completed tasks.
        for _, t in ipairs(tasks) do
            if t.completed then SetUndone(t) end
        end
    end

    Persist(noteID)
    Fire("TasksChanged", noteID)
end

-- Always deletes completed tasks and their descendants, regardless of
-- the taskRemoveOnComplete setting. Used by the "Delete done" button.
function T.DeleteCompleted(noteID)
    local tasks = GetOrCreateTasksTable(noteID)
    if not tasks then return end

    local toRemove = {}
    for _, t in ipairs(tasks) do
        if t.completed then toRemove[t.id] = true end
    end
    -- Also remove descendants of completed parents.
    local found = true
    while found do
        found = false
        for _, t in ipairs(tasks) do
            if t.parentID and toRemove[t.parentID] and not toRemove[t.id] then
                toRemove[t.id] = true
                found = true
            end
        end
    end
    for i = #tasks, 1, -1 do
        if toRemove[tasks[i].id] then table.remove(tasks, i) end
    end

    Persist(noteID)
    Fire("TasksChanged", noteID)
end

-- Move a task to a new order position-- Update task list-level settings (stored in note.taskList).
function T.UpdateList(noteID, changes)
    local tl = GetOrCreateTaskList(noteID)
    if not tl then return end
    for k, v in pairs(changes) do
        if k ~= "_clear" then tl[k] = v end
    end
    if changes._clear then
        for _, k in ipairs(changes._clear) do tl[k] = nil end
    end
    Persist(noteID)
    Fire("TasksChanged", noteID)
end

--------------------------------------------------------------------------------
-- RESET LOGIC
--------------------------------------------------------------------------------

-- The most recent daily / weekly reset before `now`, from the client's own
-- reset clock: the region's day and hour (BUG-09: a fixed Tuesday 07:00, read
-- as UTC fields but built as local time, matched no region). Present on every
-- client in the API dumps; nil only if the client has not got it yet.
local function LastDailyReset(now)
    local secs = C_DateAndTime and C_DateAndTime.GetSecondsUntilDailyReset
                 and C_DateAndTime.GetSecondsUntilDailyReset()
    return secs and (now + secs - 86400) or nil
end

local function LastWeeklyReset(now)
    local secs = C_DateAndTime and C_DateAndTime.GetSecondsUntilWeeklyReset
                 and C_DateAndTime.GetSecondsUntilWeeklyReset()
    return secs and (now + secs - 7 * 86400) or nil
end

-- Check and apply resets for a single task. Returns true if the task was reset.
-- resetType nil  = inherit from note.taskList.resetType ("None (Global)" in UI)
-- resetType "none" = explicit opt-out, never resets even if note has a global
local function CheckTaskReset(task, now, noteTaskList)
    -- Resolve effective reset type: task-level overrides note-level
    local effectiveReset = task.resetType
    if effectiveReset == nil then
        -- Inherit from note-level default
        effectiveReset = noteTaskList and noteTaskList.resetType or nil
    elseif effectiveReset == "none" then
        -- Explicit opt-out
        return false
    end
    if not effectiveReset or not task.completed then return false end

    local doneAt = task.completedAt
    if not doneAt then
        -- Checked before ALL-136.3, no stamp: count it as done now, so it stays
        -- done until its next reset rather than unchecking at once
        task.completedAt = now
        return false
    end

    -- Due when it was checked before the last reset
    local due = false
    if effectiveReset == "daily" then
        local r = LastDailyReset(now)
        due = r ~= nil and doneAt < r
    elseif effectiveReset == "weekly" then
        local r = LastWeeklyReset(now)
        due = r ~= nil and doneAt < r
    elseif effectiveReset == "date" then
        local rd = task.resetDate
        due = rd ~= nil and now >= rd and doneAt < rd
    elseif effectiveReset == "days" then
        -- N days after it was checked
        due = now >= doneAt + (task.resetEvery or 1) * 86400
    end
    if not due then return false end

    task.completed   = false
    task.completedAt = nil
    task.lastReset   = now
    if effectiveReset == "date" then
        -- A one-off date reset is used up
        task.resetType = nil
        task.resetDate = nil
    end
    return true
end

-- Called on PLAYER_LOGIN and by the daily ticker. Iterates all notes' tasks.
function T.CheckResets()
    local ndb = BNB.NotesDB()
    if not ndb or not ndb.notes then return end

    local now = time()
    local changed = {}

    for noteID, note in pairs(ndb.notes) do
        if note.tasks and #note.tasks > 0 then
            local dirty = false
            local tl = note.taskList  -- note-level defaults (may be nil)
            for _, task in ipairs(note.tasks) do
                if CheckTaskReset(task, now, tl) then
                    dirty = true
                end
            end
            if dirty then
                changed[#changed + 1] = noteID
                -- Touch updatedAt so history / autosave picks it up.
                note.updatedAt = now
            end
        end
    end

    for _, noteID in ipairs(changed) do
        Fire("TasksChanged", noteID)
    end
end

--------------------------------------------------------------------------------
-- SITUATION AWARENESS
--------------------------------------------------------------------------------
-- Per-task situation uses the same context string format as note.context:
--   "zone:stormwind city", "instance:mythic", "player:Arthas", "subzone:..."
--
-- Evaluation reuses ContextNotes' internal helpers via BNB._taskContextMatch
-- (set up below). If ContextNotes isn't loaded yet we fall back gracefully.

-- Called by ContextNotes after it finishes its own evaluation pass, or directly
-- when zone/target changes. Checks all tasks across all notes for situation hits.
function T.OnContextChanged()
    local ndb = BNB.NotesDB()
    if not ndb or not ndb.notes then return end

    -- Use ContextNotes' NoteMatches-equivalent if exposed, else a simple stub.
    local matchFn = BNB._taskContextMatch  -- set by ContextNotes on load
    if not matchFn then return end

    local hits = {}  -- { text, noteID }
    for noteID, note in pairs(ndb.notes) do
        if note.tasks then
            -- Note-level situation fallback context
            local noteCtx = note.context

            for _, task in ipairs(note.tasks) do
                if not task.completed then
                    local ctx = task.situation or noteCtx
                    if ctx and ctx ~= "" then
                        if matchFn(ctx) then
                            hits[#hits + 1] = { text = task.text, noteID = noteID }
                        end
                    end
                end
            end
        end
    end

    if #hits == 0 then return end

    -- Show toast for each hit (deduplicated per note -- show at most one toast
    -- row per note to avoid flooding).
    if BNB.ShowTaskToast then
        BNB.ShowTaskToast(hits)
    end
end

--------------------------------------------------------------------------------
-- DAILY TICKER
--------------------------------------------------------------------------------
-- Fires CheckResets every 60 seconds via C_Timer (zero-cost between ticks).
local function SetupTicker()
    C_Timer.NewTicker(60, function() T.CheckResets() end)
end

--------------------------------------------------------------------------------
-- INIT
--------------------------------------------------------------------------------
local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        T.CheckResets()
        SetupTicker()
        initFrame:UnregisterEvent("PLAYER_LOGIN")
    end
end)

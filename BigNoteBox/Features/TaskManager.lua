-- BigNoteBox Features/TaskManager.lua
-- Task system — data layer, reset logic, situation hooks.
--
-- Public API (all on BNB.Task):
--   BNB.Task.GetList(noteID)                  -> taskList or nil
--   BNB.Task.GetTasks(noteID)                 -> tasks array (may be empty)
--   BNB.Task.AddTask(noteID, text, parentID)  -> taskID or nil
--   BNB.Task.UpdateTask(noteID, taskID, changes)
--   BNB.Task.DeleteTask(noteID, taskID)
--   BNB.Task.ToggleTask(noteID, taskID)
--   BNB.Task.MoveTask(noteID, taskID, newOrder)
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
-- WoW weekly reset: Tuesday 07:00 UTC. Lua os.date %w: 0=Sun,1=Mon,2=Tue...
local WEEKLY_RESET_DOW  = 2      -- Tuesday (0-indexed, Sun=0)
local WEEKLY_RESET_HOUR = 7      -- 07:00 UTC
local DAILY_RESET_HOUR  = 3      -- 03:00 server time (approx)

-- Completion display colours
local COLOR_DONE   = { r = 0.45, g = 0.45, b = 0.48 }  -- greyed text
local COLOR_ACTIVE = { r = 1.00, g = 1.00, b = 1.00 }  -- normal text
local COLOR_ALL_DONE = { r = 0.40, g = 0.85, b = 0.40 } -- green badge

-- Sub-task indent (px) — used by ReferenceBox renderer
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

--------------------------------------------------------------------------------
-- HELPERS — note access
--------------------------------------------------------------------------------
local function GetNoteRaw(noteID)
    return BNB.GetNote and BNB.GetNote(noteID)
end

-- Returns mutable reference to note.tasks (creates if absent).
-- IMPORTANT: callers must never replace the array reference — mutate in place
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

-- Returns note.taskList (may be nil if never initialised — that's fine).
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

-- Returns the colour table to use for the completion badge.
function T.GetBadgeColor(noteID)
    local done, total = T.GetCompletionCount(noteID)
    if total == 0 then return COLOR_ACTIVE end
    if done == total then return COLOR_ALL_DONE end
    return COLOR_ACTIVE
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

    -- Inherit note-level taskList defaults for resetType.
    local tl = GetOrCreateTaskList(noteID)

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

-- Update fields on an existing task. Supports _clear array (same as UpdateNote).
function T.UpdateTask(noteID, taskID, changes)
    local task = T.FindTask(noteID, taskID)
    if not task then return end
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
function T.ToggleTask(noteID, taskID)
    local task = T.FindTask(noteID, taskID)
    if not task then return end

    local db = BigNoteBoxDB
    local removeOnComplete = db and db.taskRemoveOnComplete

    if not task.completed then
        -- Completing the task
        task.completed = true
        if removeOnComplete then
            -- Delete immediately
            T.DeleteTask(noteID, taskID)
            return  -- DeleteTask already fires callback and persists
        end
    else
        -- Uncompleting
        task.completed = false
    end
    Persist(noteID)
    Fire("TasksChanged", noteID)
end

-- Delete a task and all its sub-tasks.
function T.DeleteTask(noteID, taskID)
    local tasks = GetOrCreateTasksTable(noteID)
    if not tasks then return end

    -- Collect IDs to remove: the task itself + all children.
    local toRemove = { [taskID] = true }
    for _, t in ipairs(tasks) do
        if t.parentID == taskID then
            toRemove[t.id] = true
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

-- Move a task to a new order position within its parent group.
-- newOrder is the target 1-based index among siblings.
function T.MoveTask(noteID, taskID, newOrder)
    local task = T.FindTask(noteID, taskID)
    if not task then return end

    -- Collect siblings (same parent), sorted by current order.
    local siblings = task.parentID and T.GetSubTasks(noteID, task.parentID)
        or T.GetTopLevel(noteID)

    -- Remove task from its current position in the sibling list.
    local reordered = {}
    for _, s in ipairs(siblings) do
        if s.id ~= taskID then
            reordered[#reordered + 1] = s
        end
    end

    -- Clamp newOrder to valid range.
    newOrder = math.max(1, math.min(newOrder, #reordered + 1))
    table.insert(reordered, newOrder, task)

    -- Write back order values.
    for i, s in ipairs(reordered) do
        s.order = i
    end

    Persist(noteID)
    Fire("TasksChanged", noteID)
end

-- Clear completed tasks. Behaviour depends on db.taskRemoveOnComplete:
--   false (default) → uncheck all completed tasks
--   true            → delete all completed tasks
function T.ClearCompleted(noteID)
    local tasks = GetOrCreateTasksTable(noteID)
    if not tasks then return end

    local db = BigNoteBoxDB
    local remove = db and db.taskRemoveOnComplete

    if remove then
        -- Delete all completed tasks (and their children if any).
        local toRemove = {}
        for _, t in ipairs(tasks) do
            if t.completed then toRemove[t.id] = true end
        end
        -- Also remove children of completed parents.
        for _, t in ipairs(tasks) do
            if t.parentID and toRemove[t.parentID] then toRemove[t.id] = true end
        end
        for i = #tasks, 1, -1 do
            if toRemove[tasks[i].id] then table.remove(tasks, i) end
        end
    else
        -- Uncheck all completed tasks.
        for _, t in ipairs(tasks) do
            if t.completed then t.completed = false end
        end
    end

    Persist(noteID)
    Fire("TasksChanged", noteID)
end

-- Update task list-level settings (stored in note.taskList).
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

-- Returns the UTC timestamp for the most recent weekly WoW reset before `now`.
local function LastWeeklyReset(now)
    local t = date("*t", now)
    -- Walk backwards from today to find the last Tuesday 07:00 UTC.
    local dow = t.wday - 1  -- convert: Lua wday 1=Sun → 0=Sun, 2=Mon → 1, etc.
    local daysSince = (dow - WEEKLY_RESET_DOW + 7) % 7
    if daysSince == 0 and (t.hour < WEEKLY_RESET_HOUR or
        (t.hour == WEEKLY_RESET_HOUR and t.min == 0 and t.sec == 0)) then
        daysSince = 7
    end
    local resetDay = time({
        year  = t.year,
        month = t.month,
        day   = t.day - daysSince,
        hour  = WEEKLY_RESET_HOUR,
        min   = 0,
        sec   = 0,
    })
    return resetDay
end

-- Returns the UTC timestamp for the most recent daily reset before `now`.
local function LastDailyReset(now)
    local t = date("*t", now)
    local resetToday = time({
        year  = t.year,
        month = t.month,
        day   = t.day,
        hour  = DAILY_RESET_HOUR,
        min   = 0,
        sec   = 0,
    })
    if now < resetToday then
        -- Before today's reset — use yesterday's.
        return resetToday - 86400
    end
    return resetToday
end

-- Check and apply resets for a single task. Returns true if the task was reset.
local function CheckTaskReset(task, now)
    if not task.resetType then return false end
    local lastReset = task.lastReset or 0

    if task.resetType == "daily" then
        local resetTime = LastDailyReset(now)
        if lastReset < resetTime and task.completed then
            task.completed = false
            task.lastReset = now
            return true
        end

    elseif task.resetType == "weekly" then
        local resetTime = LastWeeklyReset(now)
        if lastReset < resetTime and task.completed then
            task.completed = false
            task.lastReset = now
            return true
        end

    elseif task.resetType == "date" then
        local rd = task.resetDate
        if rd and now >= rd and lastReset < rd and task.completed then
            task.completed = false
            task.lastReset = now
            -- One-time reset: clear the reset fields so it doesn't fire again.
            task.resetType = nil
            task.resetDate = nil
            return true
        end

    elseif task.resetType == "days" then
        local every = task.resetEvery or 1
        local nextReset = lastReset + (every * 86400)
        if now >= nextReset and task.completed then
            task.completed = false
            task.lastReset = now
            return true
        end
    end

    return false
end

-- Called on PLAYER_LOGIN and by the daily ticker. Iterates all notes' tasks.
function T.CheckResets()
    local ndb = BigNoteBoxNotesDB
    if not ndb or not ndb.notes then return end

    local now = time()
    local changed = {}

    for noteID, note in pairs(ndb.notes) do
        if note.tasks and #note.tasks > 0 then
            local dirty = false
            for _, task in ipairs(note.tasks) do
                if CheckTaskReset(task, now) then
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
-- Evaluation reuses ContextNotes' internal helpers via BNB._taskContextCheck
-- (set up below). If ContextNotes isn't loaded yet we fall back gracefully.

local _lastSituationNoteID = nil  -- note currently open in editor

-- Called by ContextNotes after it finishes its own evaluation pass, or directly
-- when zone/target changes. Checks all tasks across all notes for situation hits.
function T.OnContextChanged()
    local ndb = BigNoteBoxNotesDB
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

    -- Show toast for each hit (deduplicated per note — show at most one toast
    -- row per note to avoid flooding).
    if BNB.ShowTaskToast then
        BNB.ShowTaskToast(hits)
    end
end

--------------------------------------------------------------------------------
-- DAILY TICKER
--------------------------------------------------------------------------------
-- Fires CheckResets once per in-game day (checked every 60 seconds).
local _lastResetCheck = 0

local function SetupTicker()
    local ticker = CreateFrame("Frame")
    ticker:SetScript("OnUpdate", function(_, elapsed)
        local now = time()
        -- Only check once per minute, and only if a full day has passed
        -- since the last check.
        if now - _lastResetCheck >= 60 then
            _lastResetCheck = now
            T.CheckResets()
        end
    end)
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

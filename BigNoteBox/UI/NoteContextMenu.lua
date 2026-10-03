-- BigNoteBox UI/NoteContextMenu.lua
-- The note list's right-click menu (ALL-148), built on BNB.ContextMenu
-- (UI/ContextMenu.lua). Layout from Dukul's sketch (2026-10-01), with the
-- entries it left out placed in the sub-menus (scoped 2026-10-03):
--
--   [badge] Note name (in the note's title colour)
--   ----
--   Open note >      click = open / close as sticky
--   Create >         alarm, task, situation
--   ----
--   Pin, Favorite, Lock
--   Actions >        duplicate, copy/move, clipboard, convert, share, export
--   History >        restore point, history
--   ----
--   Move to trash, Delete permanently
--
-- The actions themselves live in UI/NoteList.lua (NOTE_ACTIONS, shared with
-- the list's double-click setting) and reach this file through BNB._NoteListKit.
--------------------------------------------------------------------------------

local BNB = BigNoteBox
local L   = BNB.L

-- Some older labels carry their own colour code; the menu colours rows itself
local function Plain(s)
    return (s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
end

-- What a click on each main item does: the key of one of its sub-menu
-- entries, nil = the click only opens the sub-menu. The item then carries
-- that entry's label ("Open as sticky note", not "Open note"), Dukul
-- 2026-10-03. Session 3 makes these Modules page settings.
local DEFAULT_CLICK = { open = "sticky", create = nil, actions = nil, history = nil }

local DIV = { divider = true }

-- A main item with its sub-menu. entries: { key, label, fn, opts } or DIV;
-- false (an entry left out on this note) is skipped. A disabled default
-- falls back to the plain label and a sub-menu-only click.
local function Parent(root, label, icon, defaultKey, entries)
    local def
    for _, e in ipairs(entries) do
        if e and e.key and e.key == defaultKey and not (e.opts and e.opts.disabled) then def = e end
    end
    local p = root:CreateButton(def and def.label or label, def and def.fn or nil, { icon = icon })
    for _, e in ipairs(entries) do
        if e == DIV then p:CreateDivider()
        elseif e then p:CreateButton(e.label, e.fn, e.opts) end
    end
    return p
end

-- extraTop(root), optional: lets a caller elsewhere (Tag Manager note rows)
-- put its own entries right under the header, before "Open note".
function BNB.ShowNoteContextMenu(owner, noteID, extraTop)
    local note = BNB.GetNote(noteID)
    if not note then return end
    local K = BNB._NoteListKit
    local A = K.NOTE_ACTIONS
    local title = (note.title ~= "") and note.title or L["UNTITLED"]

    local function DoTrash()
        if BigNoteBoxDB and BigNoteBoxDB.warnBeforeDelete ~= false then
            local popup = StaticPopup_Show("BNB_DELETE_NOTE_TRASH", title, nil, noteID)
            if popup then popup.data = noteID end
        elseif BNB.DeleteNote then
            BNB.DeleteNote(noteID)
        end
    end
    local function DoDeletePerm()
        if BigNoteBoxDB and BigNoteBoxDB.warnBeforeDelete ~= false then
            local popup = StaticPopup_Show("BNB_DELETE_NOTE", title, nil, noteID)
            if popup then popup.data = noteID end
        elseif BNB.DeleteNote then
            -- Skips the trash even while it is on (ALL-58 follow-up)
            BNB.DeleteNote(noteID, true)
        end
    end
    local function CopyBody()
        local n = BNB.GetNote(noteID)
        if not n then return end
        local content = (n.title and n.title ~= "" and (n.title .. "\n") or "") .. (n.body or "")
        BNB:Print(L["BTN_COPY_NOTE_CLASSIC"])
        if BNB.ShowClipboardHint then BNB.ShowClipboardHint(content) end
    end
    local function CreateRestorePoint()
        if not BNB.HistoryGetSlots then return end
        -- Save unsaved edits first if this is the currently open note
        if BNB._currentNoteID == noteID and BNB._dirty and BNB.SaveCurrentNote then
            BNB.SaveCurrentNote()
        end
        if BNB.HistoryGetSlots(noteID).manual then
            StaticPopup_Show("BNB_HISTORY_OVERRIDE_MANUAL", noteID)
        else
            BNB.HistoryCreateManual(noteID)
            BNB:Print(L["HISTORY_MANUAL_SAVED"])
        end
    end

    BNB.ContextMenu.Open(owner, function(root)
        root:CreateTitle(title, {
            badge = true,
            color = note.titleColor,
            -- As the sticky's badge: icon or NPC portrait, icon frame or edge border
            iconSetup = function(tex, badge) BNB.Sticky.DrawNoteIcon(badge, tex, note) end,
        })
        root:CreateDivider()

        if extraTop then extraTop(root) end

        local locked = K.NoteIsLocked(note)
        local kind   = K.StickyOpenKind(noteID)

        -- Open note: the click opens (or closes) the sticky (Dukul)
        local stickyLabel = kind == "world" and L["NL_CTX_CLOSE_STICKY"] or L["NL_CTX_OPEN_STICKY"]
        Parent(root, L["NL_CTX_OPEN"], "note", DEFAULT_CLICK.open, {
            { key = "editor",   label = L["NL_CM_OPEN_EDITOR"], fn = function() A.open(noteID) end },
            { key = "settings", label = BNB.NoteConfigOpenFor(noteID) and L["NL_CM_CLOSE_SETTINGS"]
                or L["NL_CTX_OPEN_SETTINGS"], fn = function() A.settings(noteID) end },
            { key = "focus",    label = L["CFG_DBL_FOCUS"], fn = function() A.focus(noteID) end,
              opts = { disabled = locked } },
            DIV,
            { key = "sticky",   label = stickyLabel, fn = function() A.sticky(noteID) end },
            { key = "escSticky", label = kind == "esc" and L["NL_CTX_CLOSE_ESC_STICKY"]
                or L["NL_CTX_OPEN_ESC_STICKY"], fn = function() A.escSticky(noteID) end },
        })

        local hasAlarm = note.alarm ~= nil
        local hasTasks = BNB.Task and BNB.Task.HasTasks(noteID)
        local hasSituation = note.context and note.context ~= ""
        Parent(root, L["NL_CM_CREATE"], "create", DEFAULT_CLICK.create, {
            { key = "alarm", label = hasAlarm and L["NL_CTX_EDIT_ALARM"] or L["NL_CTX_CREATE_ALARM"],
              fn = function() A.alarm(noteID) end },
            hasAlarm and { label = Plain(L["NL_CTX_REMOVE_ALARM"]), opts = { danger = true }, fn = function()
                if BNB.Alarm and BNB.Alarm.ClearAlarm then BNB.Alarm.ClearAlarm(noteID) end
                if BNB.RefreshNoteList then BNB.RefreshNoteList() end
            end } or false,
            BNB.TasksEnabled() and {   -- ALL-102
              key = "task", label = hasTasks and L["NL_CTX_ADD_TASK"] or L["NL_CTX_CREATE_TASK"],
              fn = function() A.task(noteID) end } or false,
            { key = "situation", label = hasSituation and L["NL_CM_EDIT_SITUATION"] or L["NL_CM_CREATE_SITUATION"],
              fn = function() BNB.OpenNoteConfig(noteID, "situation") end },
        })

        root:CreateDivider()

        root:CreateButton(note.pinned and L["NL_CTX_UNPIN"] or L["NL_CTX_PIN"],
            function() A.pin(noteID) end, { icon = "pinned" })
        root:CreateButton(note.favorited and L["NL_CTX_UNFAV"] or L["NL_CTX_FAV"],
            function() A.fav(noteID) end, { icon = "favorite" })
        root:CreateButton(locked and L["NL_CTX_UNLOCK"] or L["NL_CTX_LOCK"],
            function() A.lock(noteID) end, { icon = "locked" })

        local rich = BNB.AdvancedMode and BNB.AdvancedMode.IsRich(note)
        Parent(root, L["NL_CM_ACTIONS"], "action", DEFAULT_CLICK.actions, {
            { key = "duplicate", label = L["NL_CTX_DUPLICATE"], fn = function() K.DuplicateNote(noteID) end },
            (BNB.Sidebar and BNB.Sidebar.IsEnabled()) and {   -- Copy/Move to character
              key = "copyMove", label = L["NL_CTX_COPY_MOVE"], fn = function()
                if BNB.OpenCopyMovePopup then BNB.OpenCopyMovePopup(noteID, "copy") end
            end } or false,
            { key = "clipboard", label = L["NL_CM_COPY_CLIPBOARD"], fn = CopyBody },
            BNB.AdvancedMode and {
              key = "convert", label = rich and L["NL_CM_CONVERT_PLAIN"] or L["NL_CTX_CONVERT_RICH"],
              fn = function()
                if rich then BNB.AdvancedMode.ConvertToPlain(noteID) else BNB.AdvancedMode.ConvertToRich(noteID) end
            end } or false,
            DIV,
            { key = "share", label = L["NL_CTX_SHARE"], fn = function()
                if BNB.OpenShareWindow then BNB.OpenShareWindow(noteID) end
            end },
            { key = "exportJson", label = L["NL_CM_EXPORT_JSON"], fn = function()
                if BNB.ExportNoteJSON then BNB.ExportNoteJSON(noteID) end
            end },
            { key = "exportMd", label = L["NL_CM_EXPORT_MD"], fn = function()
                if BNB.ExportNoteMD then BNB.ExportNoteMD(noteID) end
            end },
            { key = "exportHtml", label = L["NL_CM_EXPORT_HTML"], fn = function()
                if BNB.ExportNoteHTML then BNB.ExportNoteHTML(noteID) end
            end },
        })

        Parent(root, L["NL_CM_HISTORY"], "history", DEFAULT_CLICK.history, {
            { key = "restorePoint", label = L["HISTORY_CTX_CREATE"], fn = CreateRestorePoint },
            { key = "view", label = L["HISTORY_CTX_VIEW"], fn = function()
                if BNB.OpenNoteHistoryPanel then BNB.OpenNoteHistoryPanel(noteID) end
            end },
        })

        root:CreateDivider()
        if BNB.TrashEnabled and BNB.TrashEnabled() then
            root:CreateButton(L["NL_CTX_TRASH"], DoTrash, { icon = "trash" })
        end
        root:CreateButton(Plain(L["NL_CTX_DELETE_PERM"]), DoDeletePerm, { icon = "danger" })
    end)
end

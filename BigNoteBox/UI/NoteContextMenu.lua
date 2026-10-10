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
--   History >        restore point, history, clear, restore previous >
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
-- 2026-10-03. Saved as BigNoteBoxDB.contextMenuClick, "menu" = nil here;
-- set on Settings > Modules > Right-click menu (UI/Config/ContextMenuSettings.lua).
local function ClickKey(item)
    local c = BigNoteBoxDB and BigNoteBoxDB.contextMenuClick
    local v = c and c[item]
    if v == nil then v = BNB.DEFAULTS.contextMenuClick[item] end
    if v == "menu" then return nil end
    return v
end

-- The entries a main item's click can run, for the settings page and the
-- sample menu: { item, label key, icon, { { entry key, label key, icon }, ... } }.
-- Keys match the entries built below; a choice missing on a note falls
-- back to a sub-menu-only click there.
BNB.NOTE_MENU_CLICKS = {
    { "open", "NL_CTX_OPEN", "note", {
        { "editor", "NL_CM_OPEN_EDITOR", "editor" }, { "settings", "NL_CTX_OPEN_SETTINGS", "note-settings" },
        { "focus", "CFG_DBL_FOCUS", "focus-mode" }, { "refBox", "NL_CM_OPEN_REFBOX", "reference-box" },
        { "sticky", "NL_CTX_OPEN_STICKY", "sticky-note" },
        { "escSticky", "NL_CTX_OPEN_ESC_STICKY", "esc-sticky-note" } } },
    { "create", "NL_CM_CREATE", "create", {
        { "alarm", "NL_CTX_CREATE_ALARM", "create-alarm" }, { "task", "NL_CTX_CREATE_TASK", "create-task" },
        { "situation", "NL_CM_CREATE_SITUATION", "create-situation" } } },
    { "actions", "NL_CM_ACTIONS", "action", {
        { "duplicate", "NL_CTX_DUPLICATE", "duplicate" }, { "copyMove", "NL_CTX_COPY_MOVE", "copy-move" },
        { "clipboard", "NL_CM_COPY_CLIPBOARD", "copy-clipboard" }, { "convert", "NL_CM_CONVERT", "rich-note" },
        { "share", "NL_CTX_SHARE", "share" }, { "sendChat", "SEND_TITLE", "chat" },
        { "exportJson", "NL_CM_EXPORT_JSON", "export-json" },
        { "exportMd", "NL_CM_EXPORT_MD", "export-markdown" }, { "exportHtml", "NL_CM_EXPORT_HTML", "export-html" } } },
    -- Clear note history is left out: never a one-click action
    { "history", "NL_CM_HISTORY", "history", {
        { "restorePoint", "HISTORY_CTX_CREATE", "create-restore-point" },
        { "view", "HISTORY_CTX_VIEW", "view-note-history" } } },
}

local DIV = { divider = true }
local RECENT_SNAPS = 3   -- auto snapshots listed under Restore previous

-- Create > Remove all tasks: every task and sub-task of the note, after a
-- confirm. The note id arrives as data (StaticPopup_Show arg 4)
StaticPopupDialogs["BNB_CM_REMOVE_TASKS"] = {
    text           = L["NL_CM_REMOVE_TASKS_CONFIRM"],
    button1        = L["DELETE"],
    button2        = L["CANCEL"],
    OnAccept       = function(_, noteID)
        if noteID and BNB.Task and BNB.Task.DeleteAll then BNB.Task.DeleteAll(noteID) end
    end,
    timeout        = 0,
    whileDead      = true,
    hideOnEscape   = true,
    preferredIndex = 3,
}

-- One confirm for every Select mode action that cannot be undone (ALL-234):
-- the text arrives ready-made (arg 1), the work as data (arg 4)
StaticPopupDialogs["BNB_MULTI_CONFIRM"] = {
    text           = "%s",
    button1        = ACCEPT,
    button2        = L["CANCEL"],
    OnAccept       = function(_, run) if type(run) == "function" then run() end end,
    timeout        = 0,
    whileDead      = true,
    hideOnEscape   = true,
    showAlert      = true,
    preferredIndex = 3,
}

-- History > Clear note history: auto snapshots only, the manual restore point
-- stays (Dukul's scope). The note id arrives as data (StaticPopup_Show arg 4).
StaticPopupDialogs["BNB_CM_CLEAR_HISTORY"] = {
    text           = L["NL_CM_CLEAR_HISTORY_CONFIRM"],
    button1        = L["DELETE"],
    button2        = L["CANCEL"],
    OnAccept       = function(_, noteID)
        if not noteID then return end
        BNB.HistoryDeleteAuto(noteID)
        if BNB.RefreshHistoryWindow then BNB.RefreshHistoryWindow() end
        if BNB.RefreshNoteHistoryPanel then BNB.RefreshNoteHistoryPanel() end
    end,
    timeout        = 0,
    whileDead      = true,
    hideOnEscape   = true,
    preferredIndex = 3,
}

-- A main item with its sub-menu. entries: { key, label, fn, opts } or DIV;
-- false (an entry left out on this note) is skipped. A disabled default
-- falls back to the plain label and a sub-menu-only click.
-- The Reference Box module is on, and it is open on this note (ALL-360)
local function RefBoxOn()
    return BigNoteBoxDB and BigNoteBoxDB.referenceBoxEnabled ~= false
end
-- The note's own player / NPC model (Player & NPC Notes on, ALL-388)
local function NoteHasModel(noteID)
    local K = BNB._RefBoxKit
    return K and K.HasModel and K.HasModel(noteID) or false
end
local function RefBoxShows(noteID)
    local f = _G["BigNoteBoxReferenceBoxFrame"]
    local K = BNB._RefBoxKit
    return f and f:IsShown() and K and K.NoteID and K.NoteID() == noteID or false
end

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
-- after, optional: runs after any entry's click (Oracle results close the bar).
-- extraBottom(root), optional: entries after the last one, below a divider
-- (Focus mode's Close Focus Mode, ALL-163).
function BNB.ShowNoteContextMenu(owner, noteID, extraTop, after, extraBottom)
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
            -- The id is the popup's data (arg 4): as text arg 1 it reached
            -- neither Override nor Compare
            StaticPopup_Show("BNB_HISTORY_OVERRIDE_MANUAL", nil, nil, noteID)
        else
            BNB.HistoryCreateManual(noteID)
            BNB:Print(L["HISTORY_MANUAL_SAVED"])
        end
    end
    local function Compare(snap)
        return function()
            if BNB._currentNoteID == noteID and BNB._dirty and BNB.SaveCurrentNote then
                BNB.SaveCurrentNote()
            end
            if BNB.OpenHistoryCompare then BNB.OpenHistoryCompare(noteID, snap) end
        end
    end
    local function ViewHistory()
        if BNB.OpenNoteHistoryPanel then BNB.OpenNoteHistoryPanel(noteID) end
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
        local stickiesOn = BNB.StickiesEnabled()

        -- Open note: the click opens (or closes) the sticky (Dukul)
        local stickyLabel = kind == "world" and L["NL_CTX_CLOSE_STICKY"] or L["NL_CTX_OPEN_STICKY"]
        -- The default click opens a sticky: with Sticky Notes off it opens the
        -- note in the editor instead (ALL-343)
        local openKey = ClickKey("open")
        if not stickiesOn and (openKey == "sticky" or openKey == "escSticky") then openKey = "editor" end
        Parent(root, L["NL_CTX_OPEN"], "note", openKey, {
            { key = "editor",   label = L["NL_CM_OPEN_EDITOR"], fn = function() A.open(noteID) end,
              opts = { icon = "editor" } },
            { key = "settings", label = BNB.NoteConfigOpenFor(noteID) and L["NL_CM_CLOSE_SETTINGS"]
                or L["NL_CTX_OPEN_SETTINGS"], fn = function() A.settings(noteID) end,
              opts = { icon = "note-settings" } },
            BNB.FocusEnabled() and {   -- Focus Mode module (ALL-343)
              key = "focus",    label = L["CFG_DBL_FOCUS"], fn = function() A.focus(noteID) end,
              opts = { disabled = locked, icon = "focus-mode" } } or false,
            -- Reference Box (ALL-360): while its module is on, or (ALL-388) on
            -- a player / NPC note with a model, as "Open model"; closes the
            -- window when it already shows this note
            (RefBoxOn() or NoteHasModel(noteID)) and { key = "refBox",
              label = RefBoxOn() and (RefBoxShows(noteID) and L["NL_CM_CLOSE_REFBOX"] or L["NL_CM_OPEN_REFBOX"])
                  or (RefBoxShows(noteID) and L["NL_CM_CLOSE_MODEL"] or L["NL_CM_OPEN_MODEL"]),
              fn = function()
                if RefBoxShows(noteID) then BNB.CloseReferenceBox()
                elseif BNB.OpenReferenceBox then BNB.OpenReferenceBox(noteID) end
              end, opts = { icon = "reference-box" } } or false,
            -- Sticky Notes module (ALL-343): both sticky entries and their divider
            stickiesOn and DIV or false,
            stickiesOn and { key = "sticky",   label = stickyLabel, fn = function() A.sticky(noteID) end,
              opts = { icon = "sticky-note" } } or false,
            stickiesOn and { key = "escSticky", label = kind == "esc" and L["NL_CTX_CLOSE_ESC_STICKY"]
                or L["NL_CTX_OPEN_ESC_STICKY"], fn = function() A.escSticky(noteID) end,
              opts = { icon = "esc-sticky-note" } } or false,
        })

        local alarmsOn = BNB.AlarmsEnabled()   -- ALL-343
        local hasAlarm = alarmsOn and note.alarm ~= nil
        local hasTasks = BNB.Task and BNB.Task.HasTasks(noteID)
        local sitOn = BNB.SituationsEnabled()   -- ALL-375
        local hasSituation = sitOn and BNB.HasSituation(note, true)   -- an off one is there to edit (ALL-435)
        -- "Create / Edit" once the note has something to edit here, plain
        -- "Create" only while every entry is a Create (Dukul, 2026-10-03)
        local canEdit = hasAlarm or hasSituation or (BNB.TasksEnabled() and hasTasks)
        Parent(root, canEdit and L["NL_CM_CREATE_EDIT"] or L["NL_CM_CREATE"], "create", ClickKey("create"), {
            alarmsOn and { key = "alarm", label = hasAlarm and L["NL_CTX_EDIT_ALARM"] or L["NL_CTX_CREATE_ALARM"],
              fn = function() A.alarm(noteID) end, opts = { icon = "create-alarm" } } or false,
            hasAlarm and { label = Plain(L["NL_CTX_REMOVE_ALARM"]), opts = { danger = true, icon = "remove-alarm" },
              fn = function()
                if BNB.Alarm and BNB.Alarm.ClearAlarm then BNB.Alarm.ClearAlarm(noteID) end
            end } or false,
            BNB.TasksEnabled() and {   -- ALL-102
              key = "task", label = hasTasks and L["NL_CTX_ADD_TASK"] or L["NL_CTX_CREATE_TASK"],
              fn = function() A.task(noteID) end, opts = { icon = "create-task" } } or false,
            (BNB.TasksEnabled() and hasTasks) and {
              label = L["NL_CM_REMOVE_TASKS"], opts = { danger = true, icon = "remove-task" },
              fn = function() StaticPopup_Show("BNB_CM_REMOVE_TASKS", title, nil, noteID) end } or false,
            sitOn and { key = "situation", label = hasSituation and L["NL_CM_EDIT_SITUATION"] or L["NL_CM_CREATE_SITUATION"],
              fn = function() BNB.OpenNoteConfig(noteID, "situation") end, opts = { icon = "create-situation" } } or false,
        })

        root:CreateDivider()

        root:CreateButton(note.pinned and L["NL_CTX_UNPIN"] or L["NL_CTX_PIN"],
            function() A.pin(noteID) end, { icon = note.pinned and "unpinned" or "pinned" })
        root:CreateButton(note.favorited and L["NL_CTX_UNFAV"] or L["NL_CTX_FAV"],
            function() A.fav(noteID) end, { icon = note.favorited and "unfavorite" or "favorite" })
        root:CreateButton(locked and L["NL_CTX_UNLOCK"] or L["NL_CTX_LOCK"],
            function() A.lock(noteID) end, { icon = locked and "unlocked" or "locked" })

        local rich = BNB.AdvancedMode and BNB.AdvancedMode.IsRich(note)
        Parent(root, L["NL_CM_ACTIONS"], "action", ClickKey("actions"), {
            { key = "duplicate", label = L["NL_CTX_DUPLICATE"], fn = function() K.DuplicateNote(noteID) end,
              opts = { icon = "duplicate" } },
            -- Copy/Move to character: the only way to change a note's scope
            -- since Note Settings lost Note visibility, so shown with the
            -- sidebar off too (ALL-265)
            { key = "copyMove", label = L["NL_CTX_COPY_MOVE"], fn = function()
                if BNB.OpenCopyMovePopup then BNB.OpenCopyMovePopup(noteID, "copy") end
            end, opts = { icon = "copy-move" } },
            { key = "clipboard", label = L["NL_CM_COPY_CLIPBOARD"], fn = CopyBody,
              opts = { icon = "copy-clipboard" } },
            BNB.AdvancedMode and BNB.RichEnabled() and {   -- Rich Notes module (ALL-343)
              key = "convert", label = rich and L["NL_CM_CONVERT_PLAIN"] or L["NL_CTX_CONVERT_RICH"],
              fn = function()
                if rich then BNB.AdvancedMode.ConvertToPlain(noteID) else BNB.AdvancedMode.ConvertToRich(noteID) end
            end, opts = { icon = rich and "normal-note" or "rich-note" } } or false,
            DIV,
            { key = "share", label = L["NL_CTX_SHARE"], fn = function()
                if BNB.OpenShareWindow then BNB.OpenShareWindow(noteID) end
            end, opts = { icon = "share" } },
            -- Send to Chat: the note's lines to a chat channel, no BigChatBox
            -- needed (ALL-280; the editor's bottom bar had the only way in)
            { key = "sendChat", label = L["SEND_TITLE"], fn = function()
                if BNB.OpenSendToChat then BNB.OpenSendToChat(noteID) end
            end, opts = { icon = "chat" } },
            { key = "exportJson", label = L["NL_CM_EXPORT_JSON"], fn = function()
                if BNB.ExportNoteJSON then BNB.ExportNoteJSON(noteID) end
            end, opts = { icon = "export-json" } },
            { key = "exportMd", label = L["NL_CM_EXPORT_MD"], fn = function()
                if BNB.ExportNoteMD then BNB.ExportNoteMD(noteID) end
            end, opts = { icon = "export-markdown" } },
            { key = "exportHtml", label = L["NL_CM_EXPORT_HTML"], fn = function()
                if BNB.ExportNoteHTML then BNB.ExportNoteHTML(noteID) end
            end, opts = { icon = "export-html" } },
        })

        -- History: Dukul's sketch plus the restore point on top, which reads
        -- Replace once one exists (2026-10-03). Only while the Note History
        -- module is on (ALL-343)
        if BNB.HistoryEnabled() then
        local slots = BNB.HistoryGetSlots and BNB.HistoryGetSlots(noteID) or { auto = {} }
        local hasAuto = #slots.auto > 0
        local hasAny  = hasAuto or slots.manual ~= nil
        local hist = Parent(root, L["NL_CM_HISTORY"], "history", ClickKey("history"), {
            { key = "restorePoint", label = slots.manual and L["NL_CM_REPLACE_RESTORE"]
                or L["HISTORY_CTX_CREATE"], fn = CreateRestorePoint,
              opts = { icon = slots.manual and "replace-restore-point" or "create-restore-point" } },
            { key = "view", label = L["HISTORY_CTX_VIEW"], fn = ViewHistory,
              opts = { disabled = not hasAny, icon = "view-note-history" } },
            { label = L["NL_CM_CLEAR_HISTORY"],
              opts = { danger = true, disabled = not hasAuto, icon = "clear-note-history" },
              fn = function()
                StaticPopup_Show("BNB_CM_CLEAR_HISTORY", title, nil, noteID)
            end },
            DIV,
        })
        -- Restore previous: the manual restore point, the newest auto
        -- snapshots, View all. Rows are date and time; each opens the
        -- compare window, which does the restoring
        local prev = hist:CreateButton(L["NL_CM_RESTORE_PREVIOUS"], nil,
            { disabled = not hasAny, icon = "restore-previous" })
        if slots.manual then
            prev:CreateButton(BNB.FmtTs(slots.manual.timestamp), Compare(slots.manual),
                { tip = L["HISTORY_SECTION_MANUAL"], tipSub = L["HISTORY_COMPARE_TIP"], icon = "restore-manual" })
            if hasAuto then prev:CreateDivider() end
        end
        for n = 1, math.min(RECENT_SNAPS, #slots.auto) do
            local snap = slots.auto[n]
            prev:CreateButton(BNB.FmtTs(snap.timestamp), Compare(snap),
                { tip = L["HISTORY_COMPARE_TIP"], icon = "restore-auto" })
        end
        if hasAny then
            prev:CreateDivider()
            prev:CreateButton(L["NL_CM_VIEW_ALL"], ViewHistory, { icon = "view-all" })
        end
        end   -- HistoryEnabled

        root:CreateDivider()
        if BNB.TrashEnabled and BNB.TrashEnabled() then
            root:CreateButton(L["NL_CTX_TRASH"], DoTrash, { icon = "trash" })
        end
        root:CreateButton(Plain(L["NL_CTX_DELETE_PERM"]), DoDeletePerm, { icon = "danger" })
        if extraBottom then
            root:CreateDivider()
            extraBottom(root)
        end
    end, after)
end

-- The settings page's "Try it": the menu's main items with the saved click
-- choices and hover delay, on no note. Every entry only closes the menu.
function BNB.ShowSampleNoteMenu(owner)
    local function Nop() end
    BNB.ContextMenu.Open(owner, function(root)
        root:CreateTitle(L["CFG_CM_SAMPLE_TITLE"], { badge = true, icon = "Interface\\Icons\\INV_Misc_Note_01" })
        root:CreateDivider()
        for n, m in ipairs(BNB.NOTE_MENU_CLICKS) do
            local entries = {}
            for _, e in ipairs(m[4]) do
                entries[#entries + 1] = { key = e[1], label = Plain(L[e[2]]), fn = Nop,
                                          opts = e[3] and { icon = e[3] } or nil }
            end
            local p = Parent(root, L[m[2]], m[3], ClickKey(m[1]), entries)
            if m[1] == "history" then
                p:CreateDivider()
                local prev = p:CreateButton(L["NL_CM_RESTORE_PREVIOUS"], nil, { icon = "restore-previous" })
                for d = 1, RECENT_SNAPS do
                    prev:CreateButton(BNB.FmtTs(time() - d * 86400), Nop, { icon = "restore-auto" })
                end
            end
            if n == 2 then root:CreateDivider() end
        end
        root:CreateDivider()
        root:CreateButton(L["NL_CTX_TRASH"], Nop, { icon = "trash" })
        root:CreateButton(Plain(L["NL_CTX_DELETE_PERM"]), Nop, { icon = "danger" })
    end)
end

--------------------------------------------------------------------------------
-- SELECT MODE MENU (ALL-234)
-- A right-click in Select mode: what can be done with every selected note.
-- Pin / favourite / lock show "all" and "un- all" both while the selection is
-- mixed; everything that cannot be undone is red and confirms with the count
-- of notes it changes. ids: the selection in list order.
--------------------------------------------------------------------------------
local function Confirm(key, n, run)
    StaticPopup_Show("BNB_MULTI_CONFIRM", string.format(L[key], n), nil, run)
end

function BNB.ShowMultiNoteContextMenu(owner, ids)
    if not ids or #ids == 0 then return end
    local K  = BNB._NoteListKit
    local AM = BNB.AdvancedMode

    -- What the selection holds, for the labels and the greyed entries
    local c = { pinned = 0, fav = 0, locked = 0, rich = 0, alarms = 0, tasks = 0,
                situations = 0, history = 0 }
    for _, id in ipairs(ids) do
        local n = BNB.GetNote(id)
        if n then
            if n.pinned then c.pinned = c.pinned + 1 end
            if n.favorited then c.fav = c.fav + 1 end
            if K.NoteIsLocked(n) then c.locked = c.locked + 1 end
            if AM and AM.IsRich(n) then c.rich = c.rich + 1 end
            if n.alarm then c.alarms = c.alarms + 1 end
            if BNB.Task and BNB.Task.HasTasks(id) then c.tasks = c.tasks + 1 end
            if BNB.HasSituation(n, true) then c.situations = c.situations + 1 end
            if n.history and #n.history > 0 then c.history = c.history + 1 end
        end
    end
    local total = #ids

    -- Runs fn(id, note) for every selected note that still exists
    local function Each(fn)
        for _, id in ipairs(ids) do
            local n = BNB.GetNote(id)
            if n then fn(id, n) end
        end
    end
    local function SaveOpen()
        if BNB._dirty and BNB.SaveCurrentNote then BNB.SaveCurrentNote() end
    end

    local function SetAll(field, on)
        Each(function(id)
            if on then BNB.UpdateNote(id, { [field] = true })
            else       BNB.UpdateNote(id, { _clear = { field } }) end
        end)
    end
    local function LockAll(on)
        Each(function(id)
            BNB.UpdateNote(id, { locked = on })
            if BNB.Sticky and BNB.Sticky.RefreshLockIcons then BNB.Sticky.RefreshLockIcons(id) end
        end)
        if BNB.LoadNoteInEditor then BNB.LoadNoteInEditor(BNB._currentNoteID) end
        if BNB.RefreshReferenceBox then BNB.RefreshReferenceBox() end
    end

    -- World stickies, up to the open limit; the rest are named in one line
    local function OpenStickies()
        local SN = BNB.Sticky
        if not (SN and SN.Open) then return end
        if InCombatLockdown() then BNB:Print(L["STICKY_COMBAT"]); return end
        local max = (BigNoteBoxDB and BigNoteBoxDB.stickyMaxCount) or BNB.DEFAULTS.stickyMaxCount
        local left = 0
        Each(function(id)
            if K.StickyOpenKind(id) == "world" then return end
            -- An ESC sticky moves into the world without taking a new slot
            if K.StickyOpenKind(id) ~= "esc" and SN.CountOpen() >= max then
                left = left + 1; return
            end
            K.OpenAsSticky(id, false)
        end)
        if left > 0 then BNB:Print(string.format(L["MULTI_STICKY_LIMIT"], left, max)) end
    end

    local function Duplicate()
        SaveOpen()
        Each(function(id, n)
            BNB.CopyNote(id, { title = n.title ~= "" and (n.title .. " (copy)") or "" })
        end)
    end

    local function RemoveSituations()
        Each(function(id, n)
            if BNB.HasSituation(n, true) then
                BNB.UpdateNote(id, { _clear = { "situations", "contextDisplay", "contextLeave",
                                                "contextTrigger", "contextFreq" } })
                n.contextSeen = nil
                if BNB.Sticky and BNB.Sticky.RefreshMarkers then BNB.Sticky.RefreshMarkers(id) end
            end
        end)
        if BNB.CheckContextualNotes then BNB.CheckContextualNotes() end
    end

    BNB.ContextMenu.Open(owner, function(root)
        root:CreateTitle(total == 1 and L["MULTI_CM_TITLE_ONE"] or string.format(L["MULTI_CM_TITLE"], total))
        root:CreateDivider()

        if BNB.StickiesEnabled() then   -- Sticky Notes module (ALL-343)
            root:CreateButton(L["MULTI_CM_OPEN_STICKY"], OpenStickies, { icon = "sticky-note" })
            root:CreateDivider()
        end

        if c.pinned < total then
            root:CreateButton(L["MULTI_CM_PIN_ALL"], function() SetAll("pinned", true) end, { icon = "pinned" })
        end
        if c.pinned > 0 then
            root:CreateButton(L["MULTI_CM_UNPIN_ALL"], function() SetAll("pinned", false) end, { icon = "unpinned" })
        end
        if c.fav < total then
            root:CreateButton(L["MULTI_CM_FAV_ALL"], function() SetAll("favorited", true) end, { icon = "favorite" })
        end
        if c.fav > 0 then
            root:CreateButton(L["MULTI_CM_UNFAV_ALL"], function() SetAll("favorited", false) end, { icon = "unfavorite" })
        end
        if c.locked < total then
            root:CreateButton(L["MULTI_CM_LOCK_ALL"], function() LockAll(true) end, { icon = "locked" })
        end
        if c.locked > 0 then
            root:CreateButton(L["MULTI_CM_UNLOCK_ALL"], function() LockAll(false) end, { icon = "unlocked" })
        end

        local act = root:CreateButton(L["NL_CM_ACTIONS"], nil, { icon = "action" })
        act:CreateButton(L["MULTI_CM_DUPLICATE"], Duplicate, { icon = "duplicate" })
        if BNB.OpenCopyMovePopupMulti then   -- sidebar on or off (ALL-265)
            act:CreateButton(L["NL_CTX_COPY_MOVE"], function() BNB.OpenCopyMovePopupMulti(ids) end,
                { icon = "copy-move" })
        end
        if AM and BNB.RichEnabled() then   -- Rich Notes module (ALL-343)
            if c.rich < total then
                act:CreateButton(L["MULTI_CM_TO_RICH"], function()
                    Each(function(id, n) if not AM.IsRich(n) then AM.ConvertToRich(id) end end)
                end, { icon = "rich-note" })
            end
            if c.rich > 0 then
                act:CreateButton(L["MULTI_CM_TO_PLAIN"], function()
                    Confirm("MULTI_CONFIRM_PLAIN", c.rich, function()
                        SaveOpen()
                        Each(function(id, n) if AM.IsRich(n) then AM.StripToPlain(id) end end)
                    end)
                end, { icon = "normal-note", danger = true })
            end
        end
        act:CreateDivider()
        act:CreateButton(L["NL_CM_EXPORT_JSON"], function() BNB.ExportMultiJSON(ids) end, { icon = "export-json" })
        act:CreateButton(L["NL_CM_EXPORT_MD"], function() BNB.ExportMultiMD(ids) end, { icon = "export-markdown" })
        act:CreateButton(L["NL_CM_EXPORT_HTML"], function() BNB.ExportMultiHTML(ids) end, { icon = "export-html" })

        if BNB.HistoryEnabled() then   -- ALL-343
        local hist = root:CreateButton(L["NL_CM_HISTORY"], nil, { icon = "history" })
        hist:CreateButton(L["MULTI_CM_RESTORE"], function()
            Confirm("MULTI_CONFIRM_RESTORE", total, function()
                SaveOpen()
                local made = 0
                Each(function(id) if BNB.HistoryCreateManual(id) then made = made + 1 end end)
                BNB:Print(string.format(L["MULTI_RESTORE_DONE"], made))
            end)
        end, { icon = "create-restore-point" })
        hist:CreateButton(L["NL_CM_CLEAR_HISTORY"], function()
            Confirm("MULTI_CONFIRM_CLEAR_HISTORY", c.history, function()
                Each(function(id) BNB.HistoryDeleteAuto(id) end)
                if BNB.RefreshHistoryWindow then BNB.RefreshHistoryWindow() end
                if BNB.RefreshNoteHistoryPanel then BNB.RefreshNoteHistoryPanel() end
            end)
        end, { icon = "clear-note-history", danger = true, disabled = c.history == 0 })
        end   -- HistoryEnabled

        local rem = root:CreateButton(L["MULTI_CM_REMOVE"], nil, { icon = "danger" })
        if BNB.AlarmsEnabled() then   -- ALL-343
            rem:CreateButton(L["MULTI_CM_CLEAR_ALARMS"], function()
                Confirm("MULTI_CONFIRM_CLEAR_ALARMS", c.alarms, function()
                    Each(function(id, n)
                        if n.alarm and BNB.Alarm and BNB.Alarm.ClearAlarm then BNB.Alarm.ClearAlarm(id) end
                    end)
                end)
            end, { icon = "remove-alarm", danger = true, disabled = c.alarms == 0 })
        end
        if BNB.TasksEnabled() then
            rem:CreateButton(L["NL_CM_REMOVE_TASKS"], function()
                Confirm("MULTI_CONFIRM_REMOVE_TASKS", c.tasks, function()
                    Each(function(id) BNB.Task.DeleteAll(id) end)
                end)
            end, { icon = "remove-task", danger = true, disabled = c.tasks == 0 })
        end
        rem:CreateButton(L["MULTI_CM_REMOVE_SITUATIONS"], function()
            Confirm("MULTI_CONFIRM_REMOVE_SITUATIONS", c.situations, RemoveSituations)
        end, { icon = "remove-situation", danger = true, disabled = c.situations == 0 })

        root:CreateDivider()
        if BNB.TrashEnabled and BNB.TrashEnabled() then
            root:CreateButton(L["NL_CTX_TRASH"], function() BNB.DeleteMultiSelected(false) end, { icon = "trash" })
        end
        root:CreateButton(Plain(L["NL_CTX_DELETE_PERM"]), function() BNB.DeleteMultiSelected(true) end,
            { icon = "danger" })
    end)
end

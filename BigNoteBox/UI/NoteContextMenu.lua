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
-- sample menu: { item, label key, icon, { { entry key, label key }, ... } }.
-- Keys match the entries built below; a choice missing on a note (Copy /
-- Move with the sidebar off) falls back to a sub-menu-only click there.
BNB.NOTE_MENU_CLICKS = {
    { "open", "NL_CTX_OPEN", "note", {
        { "editor", "NL_CM_OPEN_EDITOR" }, { "settings", "NL_CTX_OPEN_SETTINGS" },
        { "focus", "CFG_DBL_FOCUS" }, { "sticky", "NL_CTX_OPEN_STICKY" },
        { "escSticky", "NL_CTX_OPEN_ESC_STICKY" } } },
    { "create", "NL_CM_CREATE", "create", {
        { "alarm", "NL_CTX_CREATE_ALARM" }, { "task", "NL_CTX_CREATE_TASK" },
        { "situation", "NL_CM_CREATE_SITUATION" } } },
    { "actions", "NL_CM_ACTIONS", "action", {
        { "duplicate", "NL_CTX_DUPLICATE" }, { "copyMove", "NL_CTX_COPY_MOVE" },
        { "clipboard", "NL_CM_COPY_CLIPBOARD" }, { "convert", "NL_CM_CONVERT" },
        { "share", "NL_CTX_SHARE" }, { "exportJson", "NL_CM_EXPORT_JSON" },
        { "exportMd", "NL_CM_EXPORT_MD" }, { "exportHtml", "NL_CM_EXPORT_HTML" } } },
    -- Clear note history is left out: never a one-click action
    { "history", "NL_CM_HISTORY", "history", {
        { "restorePoint", "HISTORY_CTX_CREATE" }, { "view", "HISTORY_CTX_VIEW" } } },
}

local DIV = { divider = true }
local RECENT_SNAPS = 3   -- auto snapshots listed under Restore previous

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
function BNB.ShowNoteContextMenu(owner, noteID, extraTop, after)
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

        -- Open note: the click opens (or closes) the sticky (Dukul)
        local stickyLabel = kind == "world" and L["NL_CTX_CLOSE_STICKY"] or L["NL_CTX_OPEN_STICKY"]
        Parent(root, L["NL_CTX_OPEN"], "note", ClickKey("open"), {
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
        Parent(root, L["NL_CM_CREATE"], "create", ClickKey("create"), {
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
        Parent(root, L["NL_CM_ACTIONS"], "action", ClickKey("actions"), {
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

        -- History: Dukul's sketch plus the restore point on top, which reads
        -- Replace once one exists (2026-10-03)
        local slots = BNB.HistoryGetSlots and BNB.HistoryGetSlots(noteID) or { auto = {} }
        local hasAuto = #slots.auto > 0
        local hasAny  = hasAuto or slots.manual ~= nil
        local hist = Parent(root, L["NL_CM_HISTORY"], "history", ClickKey("history"), {
            { key = "restorePoint", label = slots.manual and L["NL_CM_REPLACE_RESTORE"]
                or L["HISTORY_CTX_CREATE"], fn = CreateRestorePoint },
            { key = "view", label = L["HISTORY_CTX_VIEW"], fn = ViewHistory,
              opts = { disabled = not hasAny } },
            { label = L["NL_CM_CLEAR_HISTORY"], opts = { danger = true, disabled = not hasAuto },
              fn = function()
                StaticPopup_Show("BNB_CM_CLEAR_HISTORY", title, nil, noteID)
            end },
            DIV,
        })
        -- Restore previous: the manual restore point, the newest auto
        -- snapshots, View all. Rows are date and time; each opens the
        -- compare window, which does the restoring
        local prev = hist:CreateButton(L["NL_CM_RESTORE_PREVIOUS"], nil, { disabled = not hasAny })
        if slots.manual then
            prev:CreateButton(BNB.FmtTs(slots.manual.timestamp), Compare(slots.manual),
                { tip = L["HISTORY_SECTION_MANUAL"], tipSub = L["HISTORY_COMPARE_TIP"] })
            if hasAuto then prev:CreateDivider() end
        end
        for n = 1, math.min(RECENT_SNAPS, #slots.auto) do
            local snap = slots.auto[n]
            prev:CreateButton(BNB.FmtTs(snap.timestamp), Compare(snap), { tip = L["HISTORY_COMPARE_TIP"] })
        end
        if hasAny then
            prev:CreateDivider()
            prev:CreateButton(L["NL_CM_VIEW_ALL"], ViewHistory)
        end

        root:CreateDivider()
        if BNB.TrashEnabled and BNB.TrashEnabled() then
            root:CreateButton(L["NL_CTX_TRASH"], DoTrash, { icon = "trash" })
        end
        root:CreateButton(Plain(L["NL_CTX_DELETE_PERM"]), DoDeletePerm, { icon = "danger" })
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
                entries[#entries + 1] = { key = e[1], label = Plain(L[e[2]]), fn = Nop }
            end
            local p = Parent(root, L[m[2]], m[3], ClickKey(m[1]), entries)
            if m[1] == "history" then
                p:CreateDivider()
                local prev = p:CreateButton(L["NL_CM_RESTORE_PREVIOUS"])
                for d = 1, RECENT_SNAPS do prev:CreateButton(BNB.FmtTs(time() - d * 86400), Nop) end
            end
            if n == 2 then root:CreateDivider() end
        end
        root:CreateDivider()
        root:CreateButton(L["NL_CTX_TRASH"], Nop, { icon = "trash" })
        root:CreateButton(Plain(L["NL_CTX_DELETE_PERM"]), Nop, { icon = "danger" })
    end)
end

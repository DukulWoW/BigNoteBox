-- BigNoteBox Core/Initialize.lua — Main startup sequence
-- Called from Core/Events.lua on PLAYER_LOGIN.
-- Wires all modules together in the correct order.
-- Non-critical features are wrapped in pcall so one failing module can't crash
-- the entire addon.

local BNB = BigNoteBox
local L = BNB.L

local function SafeCall(name, func, ...)
    local ok, err = pcall(func, ...)
    if not ok then
        BNB:Print("|cffff6666Warning:|r " .. name .. " failed to load: " .. tostring(err))
    end
    return ok
end

function BNB.Initialize()
    -- 1. Database (should already be initialized from ADDON_LOADED, but guard)
    if not BNB._addonLoaded then
        BNB.InitializeDB()
    end

    -- 1b. Purge expired trash entries (runs once per login, before UI builds)
    if BNB.PurgeTrash then BNB.PurgeTrash() end

    -- 1c-pre. Purge orphaned empty stubs — notes with no title AND no body that
    -- were left behind by an interrupted CreateNewNote (e.g. the session ended
    -- before the discard popup was answered). _pendingNewNoteID does not survive
    -- a reload, so these stubs would otherwise block SelectNote with the
    -- "must have a title" message on every login.
    do
        local ndb = BigNoteBoxNotesDB
        if ndb and ndb.notes then
            for noteID, note in pairs(ndb.notes) do
                local emptyTitle = not note.title or note.title == ""
                local emptyBody  = not note.body  or note.body  == ""
                if emptyTitle and emptyBody then
                    if BNB.PurgeNote then BNB.PurgeNote(noteID) end
                end
            end
        end
    end

    -- 1c. Rebuild tag index if migration flagged it as needed
    if BigNoteBoxDB and BigNoteBoxDB._needsTagRebuild then
        if BNB.TagIndexRebuild then BNB.TagIndexRebuild() end
        BigNoteBoxDB._needsTagRebuild = nil
    end

    -- 1d. Register this character in the known-characters registry.
    --     BNB.currentChar is used throughout for scope filtering and send-to-alt.
    do
        local name  = UnitName("player") or "Unknown"
        local realm = GetNormalizedRealmName() or "Unknown"
        BNB.currentChar = name .. "-" .. realm
        local _, classToken = UnitClass("player")
        local level   = UnitLevel("player") or 0
        local guild   = GetGuildInfo("player") or nil
        local faction = UnitFactionGroup("player") or nil  -- "Alliance" / "Horde"
        if BigNoteBoxDB and BigNoteBoxDB.knownChars then
            local existing = BigNoteBoxDB.knownChars[BNB.currentChar] or {}
            existing.name     = name
            existing.realm    = realm
            existing.class    = classToken or "WARRIOR"
            existing.level    = level
            existing.guild    = guild
            existing.faction  = faction
            existing.lastSeen = time()
            -- Preserve pinned/hidden state; only set defaults for new entries
            if existing.slotHidden == nil  then existing.slotHidden  = false end
            if existing.slotPinned == nil  then existing.slotPinned  = false end
            BigNoteBoxDB.knownChars[BNB.currentChar] = existing
        end

        -- First-login sidebar bootstrap: if sidebar has never been configured,
        -- enable it and seed the current character slot.
        if BigNoteBoxDB and not BigNoteBoxDB._sidebarBootstrapped then
            BigNoteBoxDB._sidebarBootstrapped = true
            BigNoteBoxDB.sidebarEnabled = true
            -- Active key stays "all" on first login (per spec)
        end
    end

    -- 2. Detect BigChatBox companion
    BNB.hasBCB = (BigChatBox ~= nil and BigChatBox.SendDirect ~= nil)

    -- 3. Safe SendChat reference
    if not BNB.SafeSendChat then
        BNB.SafeSendChat = C_ChatInfo.SendChatMessage
    end

    -- 4. Slash commands
    BNB.RegisterSlashCommands()

    -- 5. Minimap button (non-critical)
    if BNB.InitMinimapButton then
        SafeCall("Minimap", BNB.InitMinimapButton)
    end

    -- 6. Main window — build always, show only if openOnLogin is enabled
    if BNB.OpenMainWindow then
        SafeCall("MainWindow", function()
            -- Build the frame without showing it
            if BigNoteBoxDB and BigNoteBoxDB.skinMode then
                if not BNB.mainFrame then BNB.CreateMainWindowSkin() end
            else
                if not BNB.mainFrame then BNB.CreateMainWindow() end
            end
            local db = BigNoteBoxDB
            local openOnce = db and db._openOnceAfterSetup
            if openOnce then db._openOnceAfterSetup = nil end
            if (db and db.openOnLogin) or openOnce then
                BNB.mainFrame:Show()
            end
        end)
    elseif BNB.CreateMainWindow then
        SafeCall("MainWindow", function()
            if not BNB.mainFrame then BNB.CreateMainWindow() end
            local db = BigNoteBoxDB
            local openOnce = db and db._openOnceAfterSetup
            if openOnce then db._openOnceAfterSetup = nil end
            if (db and db.openOnLogin) or openOnce then
                BNB.mainFrame:Show()
            end
        end)
    end

    -- 6c. Character sidebar (built after main window; always built, shown only if enabled)
    if BNB.Sidebar and BNB.Sidebar.Build and BNB.mainFrame then
        SafeCall("Sidebar", BNB.Sidebar.Build, BNB.mainFrame)
        -- Restore persisted active key
        local db = BigNoteBoxDB
        local savedKey = db and db.sidebarActiveKey or "all"
        BNB.Sidebar.SetActive(savedKey)
        -- Auto-switch to this character's slot if option is enabled
        if db and db.sidebarEnabled and db.sidebarAutoSwitch then
            local charSlotKey = "char:" .. BNB.currentChar
            local rec = db.knownChars and db.knownChars[BNB.currentChar]
            if rec and not rec.slotHidden then
                BNB.Sidebar.SetActive(charSlotKey)
            end
        end
    end

    -- 6b. Initialise font objects (deferred to login so renderer is ready)
    --     then apply saved choice to all editor widgets
    if BNB.InitFonts  then SafeCall("FontInit",  BNB.InitFonts)  end
    if BNB.ApplyFont  then SafeCall("FontApply", BNB.ApplyFont)  end

    -- Restore tag tree button + sort enabled state from saved DB
    if BNB.InitTagTree then SafeCall("TagTreeInit", BNB.InitTagTree) end

    -- 7. Chat capture hooks (BCB integration)
    if BNB.SetupChatCapture then
        SafeCall("ChatCapture", BNB.SetupChatCapture)
    end

    -- 7b. Drag-and-drop support
    if BNB.SetupDragDrop then
        SafeCall("DragDrop", BNB.SetupDragDrop)
    end

    -- 7c. Insert game info (right-click menu on body)
    if BNB.SetupInsertInfo then
        SafeCall("InsertInfo", BNB.SetupInsertInfo)
    end

    -- 8. Restore open post-its from last session (non-critical)
    if BNB.Sticky and BNB.Sticky.RestoreSession then
        SafeCall("StickyRestore", BNB.Sticky.RestoreSession)
    end

    -- 8b. Alarm system init (ticker, login scan for missed alarms)
    if BNB.Alarm and BNB.Alarm.Init then
        SafeCall("AlarmInit", BNB.Alarm.Init)
    end

    -- 8c. Target note right-click menu hook
    if BNB.TargetNote and BNB.TargetNote.Init then
        SafeCall("TargetNote", BNB.TargetNote.Init)
    end

    -- 9. Initial contextual notes check (badge + toast on login)
    if BNB.CheckContextualNotes then
        C_Timer.After(2, BNB.CheckContextualNotes)
    end

    -- 10. Login message
    if not BigNoteBoxDB.hideLoginMessage then
        local bcbStatus = BNB.hasBCB and " |cff5599ff(BCB detected)|r" or ""
        print(string.format(L["LOADED_MSG"], BNB.ADDON_VERSION) .. bcbStatus)
    end

    -- 11. Wire config and trash height tracking now that main window exists
    if BNB.HookConfigHeightTracking then
        BNB.HookConfigHeightTracking()
    end
    if BNB.InitTrashWindow then
        BNB.InitTrashWindow()
    end
    if BNB.InitHistoryWindow then
        BNB.InitHistoryWindow()
    end

    -- 11b. Apply trash feature visibility (hide toolbar button if feature disabled)
    if BNB._toolbarTrashBtn then
        local enabled = not BigNoteBoxDB or BigNoteBoxDB.trashFeature ~= false
        BNB._toolbarTrashBtn:SetShown(enabled)
    end

    -- 11c. Sync trash button state (grey + disabled when trash is empty)
    if BNB.SyncTrashBtnState then BNB.SyncTrashBtnState() end

    -- 11d. Sync history button state (grey + disabled when no history exists)
    if BNB.SyncHistoryBtnState then BNB.SyncHistoryBtnState() end

    -- 12. First-time setup wizard
    -- Show if setupComplete is not true. Suppresses openOnLogin during setup
    -- so the wizard is the first thing the player sees.
    do
        local db = BigNoteBoxDB
        if db and db.setupComplete ~= true then
            if BNB.ShowSetupWizard then
                -- Suppress the normal window auto-open so setup is front and center
                if BNB.mainFrame then BNB.mainFrame:Hide() end
                C_Timer.After(0.2, function()
                    if BNB.ShowSetupWizard then BNB.ShowSetupWizard() end
                end)
            end
        end
    end

    BNB._initialized = true
end

--------------------------------------------------------------------------------
-- GLOBAL KEYBIND WRAPPERS
-- These must be plain globals (not locals) — WoW's binding system calls them
-- by name from Bindings.xml.  They are defined here rather than in
-- SlashCommands.lua so they're available immediately after Initialize runs.
--------------------------------------------------------------------------------
function BNB_KeybindToggle()
    if InCombatLockdown() then return end
    if BNB.ToggleWindow then BNB.ToggleWindow() end
end

function BNB_KeybindQuickNote()
    if InCombatLockdown() then return end
    -- Replicate Quick Note button logic: next gap-filling number
    if BNB.SaveCurrentNote then BNB.SaveCurrentNote() end
    local base   = "Quick Note"
    local taken  = {}
    for _, note in pairs(BigNoteBoxNotesDB and BigNoteBoxNotesDB.notes or {}) do
        local t = note.title or ""
        if t == base then taken[1] = true
        else local n = t:match("^Quick Note (%d+)$"); if n then taken[tonumber(n)] = true end end
    end
    local title = (not taken[1]) and base or (function()
        local i = 2; while taken[i] do i = i + 1 end; return base .. " " .. i
    end)()
    local id = BNB.CreateNote and BNB.CreateNote(title)
    if not id then return end
    BNB.UpdateNote(id, { icon = "Interface\\Icons\\INV_Misc_Note_04" })
    if not BNB.mainFrame then if BNB.OpenMainWindow then BNB.OpenMainWindow() elseif BNB.CreateMainWindow then BNB.CreateMainWindow() end end
    if BNB.mainFrame and not BNB.mainFrame:IsShown() then BNB.mainFrame:Show() end
    if BNB.RefreshNoteList then BNB.RefreshNoteList() end
    if BNB.SelectNote      then BNB.SelectNote(id)   end
    C_Timer.After(0.05, function()
        if BNB._editorBody then BNB._editorBody:SetFocus() end
    end)
end

function BNB_KeybindNewNote()
    if InCombatLockdown() then return end
    if BNB.CreateNewNote then BNB.CreateNewNote() end
end

function BNB_KeybindHideStickies()
    if InCombatLockdown() then return end
    if BNB.Sticky and BNB.Sticky.ToggleHidden then BNB.Sticky.ToggleHidden() end
end

function BNB_KeybindToggleRichView()
    if InCombatLockdown() then return end
    if BNB.ToggleRichViewEdit then BNB.ToggleRichViewEdit() end
end

function BNB_KeybindTargetNote()
    if InCombatLockdown() then return end
    if BNB.TargetNote and BNB.TargetNote.Fire then BNB.TargetNote.Fire() end
end

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

-- Forever: a knownChars record for this character under its first name alone
-- ("Dazil-Realm" next to "Dazil Dazal-Realm") is the duplicate the old bare
-- UnitName key made. Fold it into the current record: notes scoped to it move
-- to this character, the sidebar pin carries over, a sidebar selection on it
-- follows, and the stale record goes. Matched on first name + realm + class.
local function MergeBareNameRecord(db, name, realm, classToken)
    local first = name:match("^(%S+) ")
    if not first then return end
    local oldKey = first .. "-" .. realm
    local old, cur = db.knownChars[oldKey], db.knownChars[BNB.currentChar]
    if not (old and cur) or oldKey == BNB.currentChar or old.class ~= classToken then return end
    if old.slotPinned then cur.slotPinned = true end
    local oldScope, newScope = "char:" .. oldKey, "char:" .. BNB.currentChar
    -- Written straight onto the notes, not through UpdateNote: this runs at
    -- login before any search cache exists, and a moved scope is not an edit
    -- (SV-07 checked, ALL-136.8)
    local ndb = BNB.NotesDB()
    local moved = 0
    for _, list in ipairs({ ndb and ndb.notes, ndb and ndb.trash }) do
        for _, note in pairs(list or {}) do
            if note.scope == oldScope then note.scope = newScope; moved = moved + 1 end
        end
    end
    if db.sidebarActiveKey == oldScope then db.sidebarActiveKey = newScope end
    db.knownChars[oldKey] = nil
    if moved > 0 then
        BNB:Print(string.format(L["CHAR_MERGED_FMT"], moved, BNB.currentChar))
    end
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
        local ndb = BNB.NotesDB()
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

    -- 1c. (The tag index is runtime-only since SV-05: BNB.TagIndex() builds it
    --     on first use, so there is no rebuild flag to honour here.)

    -- 1c-post. Drop per-note settings whose note is gone (SV-09): a sticky's
    --     postits record and the Reference Box task split ratio outlived the
    --     note and its trash copy. Not in dev mode: settings are shared, and
    --     the other notes set's ids are not visible from here. Not with an
    --     empty notes set either (a notes file that failed to load would take
    --     every sticky's position with it).
    do
        local ndb, db = BNB.NotesDB(), BigNoteBoxDB
        if db and not BNB.IsDevMode() and ndb and ndb.notes and next(ndb.notes) then
            local trash = ndb.trash or {}
            for _, key in ipairs({ "postits", "taskSplitRatio" }) do
                local t = db[key]
                if type(t) == "table" then
                    for id in pairs(t) do
                        if not ndb.notes[id] and not trash[id] then t[id] = nil end
                    end
                end
            end
        end
    end

    -- 1d. Register this character in the known-characters registry.
    --     BNB.currentChar is used throughout for scope filtering and send-to-alt.
    do
        -- Through UnitNameRealm (FOR-23), so a Forever surname is part of the
        -- key whether UnitName hands it back joined ("Dazil Dazal", nil) or in
        -- the second slot ("Dazil", "Dazal"). Forever moved it from the first
        -- shape to the second between 2026-09-24 and 09-27, and the bare
        -- UnitName key registered the same character twice (Dukul, 2026-09-27).
        local name, realm = BNB.UnitNameRealm("player")
        name = name or "Unknown"
        if not realm or realm == "" then realm = "Unknown" end
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
            if BNB.IsForever then
                SafeCall("MergeBareName", MergeBareNameRecord, BigNoteBoxDB, name, realm, classToken)
            end
        end

        -- First-login sidebar bootstrap: if sidebar has never been configured,
        -- enable it and seed the current character slot.
        if BigNoteBoxDB and not BigNoteBoxDB._sidebarBootstrapped then
            BigNoteBoxDB._sidebarBootstrapped = true
            BigNoteBoxDB.sidebarEnabled = true
            -- Active key stays "all" on first login (per spec)
        end
    end

    -- 1e. Header / accent text colour (ALL-402): skin accent or the normal-mode
    -- colour onto the BNBFontNormal* font objects, before any window is built
    if BNB.ApplyHeaderColor then SafeCall("HeaderColor", BNB.ApplyHeaderColor) end

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

    -- 5b. Settings > General > Window (ALL-270): put the main window back in
    -- the centre and/or at its default size on every login and reload, before
    -- it is built (x = 0 = centred, see RestoreWindowPos in UI/MainWindow.lua)
    do
        local db  = BigNoteBoxDB
        local pos = db and db.windowPos
        if pos then
            if db.resetWindowPosOnLoad == true then pos.x, pos.y = 0, 0 end
            if db.resetWindowSizeOnLoad == true then
                pos.w, pos.h = BNB.DEFAULTS.windowPos.w, BNB.DEFAULTS.windowPos.h
            end
        end
    end

    -- 6. Main window — build always, show only if openOnLogin is enabled
    if BNB.CreateMainWindow then
        SafeCall("MainWindow", function()
            -- Build the frame without showing it (classic or skin chrome)
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
        local savedKey = db and db.sidebarActiveKey or BNB.DEFAULTS.sidebarActiveKey
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

    -- (Drag-and-drop and Insert game info are wired when each body EditBox is
    -- built: NoteEditor BuildBodyField and FocusEditor call WireDropTarget /
    -- WireInsertInfoTarget, so there is no setup step here.)

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
    -- Dev mode (ALL-129) always says so, whatever the login message setting:
    -- it decides which notes are on screen
    if BNB.IsDevMode() then
        if BNB._devNotesCopied then
            BNB:Print(string.format(L["CFG_DEV_MODE_COPIED_FMT"], BNB._devNotesCopied))
        else
            local n = 0
            for _ in pairs(BNB.NotesDB().notes or {}) do n = n + 1 end
            BNB:Print(string.format(L["CFG_DEV_MODE_LOGIN_FMT"], n))
        end
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
    -- The toolbar row closes up so no gap is left (UI/MainWindow.lua)
    if BNB.ApplyToolbarIcons then BNB.ApplyToolbarIcons() end

    -- 11c. Sync trash button state (grey + disabled when trash is empty)
    if BNB.SyncTrashBtnState then BNB.SyncTrashBtnState() end
    -- Tag Manager button the same way, while no note has a tag (ALL-273)
    if BNB.SyncTagsBtnState then BNB.SyncTagsBtnState() end
    -- Alarms button too, while no note has an alarm (ALL-352)
    if BNB.SyncAlarmsBtnState then BNB.SyncAlarmsBtnState() end

    -- 11d. Sync history button state (grey + disabled when no history exists)
    if BNB.SyncHistoryBtnState then BNB.SyncHistoryBtnState() end

    -- 11e. Report-a-bug button outside the main window (ALL-73)
    if BNB.AttachBugButton then pcall(BNB.AttachBugButton) end

    -- 11f. Default keys for players whose bindings predate them (once)
    pcall(BNB.ApplyDefaultKeys)

    -- 12. First-time setup wizard
    -- Show if setupComplete is not true. Suppresses openOnLogin during setup
    -- so the wizard is the first thing the player sees.
    -- (Was skipped on Forever while its client did not load SavedVariables, FOR-10;
    -- Blizzard fixed that on 2026-09-25.)
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
end

--------------------------------------------------------------------------------
-- DEFAULT KEYS FOR EXISTING PLAYERS
-- Bindings.xml defaults reach only a fresh binding set or "Reset to Default",
-- so a player with saved bindings would never get them. Once per account,
-- each key goes to its action when the action has no key and the key is
-- free; the player's own bindings are never touched. SetBinding is blocked
-- in combat, so a combat login waits for combat to end.
--------------------------------------------------------------------------------
-- Third value = the version a key arrived in: a bump applies only the newer
-- ones, so a default the player unbound on purpose is not handed back.
local DEFAULT_KEYS_VERSION = 2
local DEFAULT_KEYS = {
    { "BIGNOTEBOXNOTEONTARGET",   "F6",     1 },
    { "BIGNOTEBOXQUICKNOTE",      "F7",     1 },
    { "BIGNOTEBOXNEWNOTE",        "F8",     1 },
    { "BIGNOTEBOXSTICKIESFRONT",  "CTRL-J", 2 },   -- ALL-200
}

-- Every BigNoteBox binding and its default key, the same as Bindings.xml:
-- keep the two in step. No second value = no default key.
BNB.BINDING_DEFAULTS = {
    { "BIGNOTEBOXOPEN",         "CTRL-N" },
    { "BIGNOTEBOXQUICKNOTE",    "F7" },
    { "BIGNOTEBOXNEWNOTE",      "F8" },
    { "BIGNOTEBOXHIDESTICKIES", "CTRL-H" },
    { "BIGNOTEBOXTOGGLERV" },
    { "BIGNOTEBOXNOTEONTARGET", "F6" },
    { "BIGNOTEBOXORACLE",       "CTRL-SPACE" },
    { "BIGNOTEBOXSTICKIESFRONT", "CTRL-J" },
}

-- Danger Zone "Reset key bindings" (Dukul, 2026-10-02): every BigNoteBox
-- action loses its keys and gets its default back. A default key that the
-- game or another addon uses is left alone and comes back in `skipped`
-- ("F7 (Action name)"). Returns false in combat, where SetBinding is blocked.
function BNB.ResetKeyBindings()
    if InCombatLockdown() then return false end
    for _, d in ipairs(BNB.BINDING_DEFAULTS) do
        for _, key in ipairs({ GetBindingKey(d[1]) }) do SetBinding(key) end
    end
    local skipped = {}
    for _, d in ipairs(BNB.BINDING_DEFAULTS) do
        local action, key = d[1], d[2]
        if key then
            local cur = GetBindingAction(key)
            if cur == nil or cur == "" then
                SetBinding(key, action)
            else
                skipped[#skipped + 1] = key .. " (" .. (_G["BINDING_NAME_" .. cur] or cur) .. ")"
            end
        end
    end
    SaveBindings(GetCurrentBindingSet())
    return true, skipped
end

function BNB.ApplyDefaultKeys()
    local db = BigNoteBoxDB
    if not db or (db.defaultKeysVersion or 0) >= DEFAULT_KEYS_VERSION then return end
    if InCombatLockdown() then
        local w = CreateFrame("Frame")
        w:RegisterEvent("PLAYER_REGEN_ENABLED")
        w:SetScript("OnEvent", function(self)
            self:UnregisterAllEvents()
            pcall(BNB.ApplyDefaultKeys)
        end)
        return
    end
    local changed = false
    local have = db.defaultKeysVersion or 0
    for _, d in ipairs(DEFAULT_KEYS) do
        local action, key = d[1], d[2]
        local cur = GetBindingAction(key)
        if d[3] > have and not GetBindingKey(action) and (cur == nil or cur == "") then
            if SetBinding(key, action) then changed = true end
        end
    end
    if changed then SaveBindings(GetCurrentBindingSet()) end
    db.defaultKeysVersion = DEFAULT_KEYS_VERSION
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
    -- Same note as the list's Quick Note button (BNB.CreateQuickNote)
    if BNB.SaveCurrentNote then BNB.SaveCurrentNote() end
    local id = BNB.CreateQuickNote()
    if not id then return end
    -- Sticky mode: the note opens as a sticky to type in. When that cannot
    -- happen it opens in the main window as before; a full sticky set says so.
    local db = BigNoteBoxDB
    if db and db.quickNoteKeyMode ~= "main" and BNB.Sticky and BNB.Sticky.OpenQuick then
        local ok, why = BNB.Sticky.OpenQuick(id)
        if ok then
            return
        end
        if why == "max" then
            local msg = string.format(L["QN_KEY_STICKY_MAX"], db.stickyMaxCount or BNB.DEFAULTS.stickyMaxCount)
            if UIErrorsFrame then UIErrorsFrame:AddMessage(msg, 1.0, 0.82, 0.0, 1.0) end
            BNB:Print(msg)
        end
    end
    BNB.ShowQuickNote(id)
end

function BNB_KeybindNewNote()
    if InCombatLockdown() then return end
    if BNB.CreateNewNote then BNB.CreateNewNote() end
end

-- Every open sticky and minimized tile to the front (ALL-200, Ctrl+J)
function BNB_KeybindStickiesFront()
    if BNB.Sticky and BNB.Sticky.BringAllToFront then BNB.Sticky.BringAllToFront() end
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

-- Oracle search (ALL-69) opens in combat too: searching is harmless, and each
-- way of opening a note keeps its own combat check.
function BNB_KeybindOracle()
    if BNB.Oracle then BNB.Oracle.Toggle() end
end

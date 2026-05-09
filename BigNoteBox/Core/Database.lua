-- BigNoteBox Core/Database.lua — SavedVariables initialization
--
-- SPLIT ARCHITECTURE (v1.2.0+):
--   BigNoteBoxNotesDB  — owned by the BigNoteBoxDB companion addon.
--                        Notes and noteOrder ONLY. Never wiped by reset.
--   BigNoteBoxDB       — owned by BigNoteBox (this addon).
--                        Settings, window state, minimap, UI prefs.
--
-- BigNoteBoxDB.lua (companion) calls BNB.InitNotesDB() and BNB.MigrateNotesDB()
-- directly after WoW loads it. BigNoteBox checks BigNoteBoxNotesDB_Loaded (set
-- by the companion) to know whether notes are available.
--
-- SCHEMA VERSIONING:
--   NOTES_SCHEMA_VERSION  — bump when the note table structure changes in a way
--                           that requires transforming existing saved data.
--   SETTINGS_SCHEMA_VERSION — bump when BigNoteBoxDB needs a migration pass.
--
--   MigrateNotesDB() and MigrateSettingsDB() are the sole migration runners.
--   Each migration step is a guarded block:  if v < N then ... v = N end
--   Always update the stored dbVersion at the end of the function.
--
-- NOTE FIELD CATALOGUE (v1 — update this comment when fields are added/removed):
--   CORE:       id, title, body, tags, created, updated
--   BEHAVIOUR:  context, contextDisplay, contextLeave, pinned, favorited, locked
--   APPEARANCE: icon, titleColor, fontOverride, textAlign, fontOutline,
--               borderOverride, borderScale, borderOffset, lineHeight
--   ALARM:      alarm = { label, timeType, time, igTime, recur, recurDays,
--                         recurEvery, sound, combatMode, combatPost,
--                         snoozeDefault, glowType, glowColor, glowMode,
--                         showSticky, fired, snoozedUntil }
--   INTERNAL:   scope  ("global" | "char:Name-Realm"; not exported)
--
-- TRASH DB  (BigNoteBoxNotesDB.trash):
--   Full note copy + deletedAt (unix timestamp). Purged after trashRetainDays days.
--   trashRetainDays = 0 → trash disabled, deletes are permanent.
--
-- CONTEXT STRING FORMAT (v1):  "<kind>:<value>"
--   kind  = "zone" | "instance" | "subzone" | "player"
--   value = plain display name as returned by WoW APIs
--   Parsed by: DecodeContext(), NoteMatches() in Features/ContextNotes.lua
--   If this format ever changes, bump NOTES_SCHEMA_VERSION and add a migration.

local BNB = BigNoteBox

--------------------------------------------------------------------------------
-- SCHEMA VERSIONS  — increment when a migration step is added
--------------------------------------------------------------------------------
local NOTES_SCHEMA_VERSION    = 5   -- bump + add block to MigrateNotesDB()
local SETTINGS_SCHEMA_VERSION = 13  -- bump + add block to MigrateSettingsDB()

--------------------------------------------------------------------------------
-- DEFAULTS
--------------------------------------------------------------------------------
BNB.defaults = {
    windowPos = { x = 0, y = 0, w = 820, h = 640 },
    fontSize  = 13,
    splitX    = 240,
    settings  = {
        autosave         = true,
        contextSurface   = true,
        bcbIntegration   = true,
        sendKeybind      = nil,
        captureKeybind   = nil,
        hideLoginMessage = false,
    },
}

--------------------------------------------------------------------------------
-- UUID GENERATOR
--------------------------------------------------------------------------------
function BNB.GenerateID()
    local t = time()
    local r = math.random(0, 0xFFFF)
    return string.format("bnb-%08x%04x", t, r)
end

--------------------------------------------------------------------------------
-- INITIALIZE NOTES DB  (BigNoteBoxNotesDB)
-- Called first. Notes are precious — only ever add missing keys, never reset.
-- Public so BigNoteBoxDB.lua (the companion data addon) can call it directly.
--------------------------------------------------------------------------------
function BNB.InitNotesDB()
    BigNoteBoxNotesDB = BigNoteBoxNotesDB or {}
    local ndb = BigNoteBoxNotesDB
    if ndb.notes     == nil then ndb.notes     = {} end
    if ndb.noteOrder == nil then ndb.noteOrder = {} end
    if ndb.dbVersion == nil then ndb.dbVersion = 1  end
end

--------------------------------------------------------------------------------
-- MIGRATE NOTES DB
-- Called after InitNotesDB(). Transforms existing note data between schema
-- versions. Each block is guarded by  if v < N  so it only runs once.
-- After all migrations, the stored version is updated to the current value.
--
-- HOW TO ADD A MIGRATION:
--   1. Bump NOTES_SCHEMA_VERSION at the top of this file.
--   2. Add a block here:
--        if v < 2 then
--            -- e.g. rename note.oldField → note.newField
--            for _, note in pairs(BigNoteBoxNotesDB.notes or {}) do
--                note.newField = note.oldField
--                note.oldField = nil
--            end
--            v = 2
--        end
--------------------------------------------------------------------------------
-- Public so BigNoteBoxDB.lua can call it after owning BigNoteBoxNotesDB.
function BNB.MigrateNotesDB()
    local ndb = BigNoteBoxNotesDB
    local v   = ndb.dbVersion or 1

    -- ── v1 → v2: introduce trash table ───────────────────────────────────────
    if v < 2 then
        if ndb.trash == nil then ndb.trash = {} end
        v = 2
    end

    -- ── v2 → v3: convert raw |T...|t texture escapes to {icon} markup ────────
    -- InspectNote/TargetNote previously embedded WoW texture escapes directly
    -- in note bodies. The EditBox renders these as inline 18px images but the
    -- cursor positioning engine uses font-based line metrics, causing cumulative
    -- vertical offset over many icon lines. {icon} tags display as plain text
    -- in edit mode (no rendered icon, no height mismatch) and ToHTML() converts
    -- them to proper |T|t for SimpleHTML rendering in view mode.
    if v < 3 then
        for _, note in pairs(ndb.notes or {}) do
            if note.body and note.body:find("|T", 1, true) then
                -- Pattern 1: |TInterface\Icons\name:W:H|t  → {icon:name:W}
                note.body = note.body:gsub("|TInterface\\Icons\\([^:]+):(%d+):%d+|t", function(name, w)
                    return "{icon:" .. name .. ":" .. w .. "}"
                end)
                -- Pattern 2: |T<numericFileID>:W:H|t  → {icon:fileID:W}
                note.body = note.body:gsub("|T(%d+):(%d+):%d+|t", function(id, w)
                    return "{icon:" .. id .. ":" .. w .. "}"
                end)
            end
        end
        -- Also migrate trashed notes so restoring them doesn't reintroduce the bug
        for _, note in pairs(ndb.trash or {}) do
            if note.body and note.body:find("|T", 1, true) then
                note.body = note.body:gsub("|TInterface\\Icons\\([^:]+):(%d+):%d+|t", function(name, w)
                    return "{icon:" .. name .. ":" .. w .. "}"
                end)
                note.body = note.body:gsub("|T(%d+):(%d+):%d+|t", function(id, w)
                    return "{icon:" .. id .. ":" .. w .. "}"
                end)
            end
        end
        v = 3
    end

    -- ++ v3 -> v4: introduce note.iconSource ++++++++++++++++++++++++++++++++++++
    if v < 4 then
        -- nil is treated as "curated" at runtime; no data migration needed
        v = 4
    end

    -- ++ v4 -> v5: introduce note.tasks and note.taskList +++++++++++++++++++++
    -- Both fields default to nil at runtime (no tasks = no fields).
    -- No data migration needed — absence of the fields is the correct default.
    if v < 5 then
        v = 5
    end

    ndb.dbVersion = NOTES_SCHEMA_VERSION
end

--------------------------------------------------------------------------------
-- MIGRATE SETTINGS DB
-- Same pattern as MigrateNotesDB(). Settings are less precious but some
-- keys may need renaming or type changes between versions.
--
-- HOW TO ADD A MIGRATION:
--   1. Bump SETTINGS_SCHEMA_VERSION at the top of this file.
--   2. Add a block here following the same guarded-block pattern.
--------------------------------------------------------------------------------
local function MigrateSettingsDB()
    local db = BigNoteBoxDB
    local v  = db.dbVersion or 1

    -- ── v1 → v2: introduce tagIndex ──────────────────────────────────────────
    if v < 2 then
        -- Rebuild from scratch — TagIndexRebuild is defined in NoteManager.lua
        -- which loads after Database.lua. Defer via a flag; Initialize.lua will
        -- call BNB.TagIndexRebuild() explicitly after all modules are loaded.
        db.tagIndex = {}
        db._needsTagRebuild = true
        v = 2
    end

    -- ── v2 → v3: remove "favorites" sort mode; add stickiesHiddenPersist ─────
    if v < 3 then
        -- "favorites" was removed from the sort dropdown. Reset to "creation"
        -- so the UI doesn't show a blank/unknown sort label for existing users.
        if db.sortBy == "favorites" then
            db.sortBy = "creation"
        end
        -- New sticky hide-all persist flag — off by default (hide resets on reload).
        if db.stickiesHiddenPersist == nil then db.stickiesHiddenPersist = false end
        v = 3
    end

    -- ++ v3 -> v4: introduce alarmDefaults +++++++++++++++++++++++++++++++++++++++
    if v < 4 then
        if db.alarmDefaults == nil then
            db.alarmDefaults = {
                snoozeDefault = 5,
                glowType      = 2,   -- AutoCast
                glowColor     = { 0.400, 0.733, 0.416, 1.0 },
                glowMode      = "pulse",
            }
        end
        v = 4
    end

    -- ++ v4 -> v5: reset alarmDefaults.glowColor to BNB green (was gold) ++++++++++
    if v < 5 then
        if db.alarmDefaults then
            db.alarmDefaults.glowColor = { 0.400, 0.733, 0.416, 1.0 }
        end
        v = 5
    end

    -- ++ v5 -> v6: introduce sidebar layout settings ++++++++++++++++++++++++++++++
    if v < 6 then
        if db.sidebarSide     == nil then db.sidebarSide     = "right" end
        if db.sidebarAtBottom == nil then db.sidebarAtBottom = false   end
        if db.sidebarSmallIcons == nil then db.sidebarSmallIcons = false end
        v = 6
    end

    -- ++ v6 -> v7: rich preview auto-show + directSend defaults +++++++++++++++++++
    if v < 7 then
        if db.richPreviewAutoShow == nil then db.richPreviewAutoShow = true end
        if db.directSend == nil then db.directSend = {} end
        if db.directSend.autoReject == nil then db.directSend.autoReject = false end
        v = 7
    end

    -- ++ v7 -> v8: refbox left-side default + focus preview always-show +++++++++++
    if v < 8 then
        if db.refboxSide             == nil then db.refboxSide             = "left" end
        if db.focusPreviewAlwaysShow == nil then db.focusPreviewAlwaysShow = true   end
        v = 8
    end

    -- ++ v8 -> v9: live preview debounce delay ++++++++++++++++++++++++++++++++++++
    if v < 9 then
        if db.previewDebounce == nil then db.previewDebounce = 0.3 end
        v = 9
    end

    -- ++ v9 -> v10: What's New version tracking +++++++++++++++++++++++++++++++++++
    if v < 10 then
        -- lastSeenWhatsNewVersion: the version string last acknowledged by the user.
        -- Nil on first run or after a version bump causes the window to appear.
        -- Never set a default here; nil is intentional so the popup fires on first install.
        v = 10
    end

    -- ++ v10 -> v11: LibSharedMedia font opt-in ++++++++++++++++++++++++++++++++++++
    if v < 11 then
        -- lsmFonts: intentionally defaults to false — user must opt in via Advanced tab.
        if db.lsmFonts == nil then db.lsmFonts = false end
        v = 11
    end

    -- ++ v11 -> v12: Rich Notes independent heading sizes +++++++++++++++++++++++++
    if v < 12 then
        if db.richIndependentSizes == nil then db.richIndependentSizes = false end
        if db.richH1Size          == nil then db.richH1Size          = 25    end
        if db.richH2Size          == nil then db.richH2Size          = 20    end
        if db.richH3Size          == nil then db.richH3Size          = 16    end
        if db.richBodySize        == nil then db.richBodySize        = 12    end
        v = 12
    end

    -- ++ v12 -> v13: task system settings ++++++++++++++++++++++++++++++++++++++
    if v < 13 then
        -- "Remove on complete" vs keep dimmed. Default: keep (false = keep).
        if db.taskRemoveOnComplete   == nil then db.taskRemoveOnComplete   = false end
        -- Default sticky view for notes that have tasks. "tasks" = show tasks.
        if db.taskStickyDefault      == nil then db.taskStickyDefault      = "tasks" end
        -- Where completed tasks appear in the list. "bottom" = push to bottom.
        if db.taskCompletedPosition  == nil then db.taskCompletedPosition  = "bottom" end
        -- Row spacing in task lists. "normal" = default, "compact", "spacious".
        if db.taskSpacing            == nil then db.taskSpacing            = "normal" end
        -- Whether the task panel is expanded by default in RefBox.
        if db.taskPanelExpanded      == nil then db.taskPanelExpanded      = true  end
        -- Per-note task/attachment split ratio: { [noteID] = 0.0..1.0 }
        -- 0.5 = equal split; 1.0 = tasks take all; 0.0 = attachments take all.
        if db.taskSplitRatio         == nil then db.taskSplitRatio         = {}    end
        v = 13
    end

    db.dbVersion = SETTINGS_SCHEMA_VERSION
end

--------------------------------------------------------------------------------
-- INITIALIZE SETTINGS DB  (BigNoteBoxDB)
-- Safe to wipe on reset — contains no user-created content.
--------------------------------------------------------------------------------
local function InitSettingsDB()
    BigNoteBoxDB = BigNoteBoxDB or {}
    local db       = BigNoteBoxDB
    local defaults = BNB.defaults

    -- Window position / size
    if db.windowPos == nil then
        db.windowPos = {
            x = defaults.windowPos.x,
            y = defaults.windowPos.y,
            w = defaults.windowPos.w,
            h = defaults.windowPos.h,
        }
    end

    -- Focus mode window position / size
    if db.focusPos == nil then
        db.focusPos = { x = 0, y = 0, w = 620, h = 540 }
    end

    -- Splitter and collapse state
    if db.splitX        == nil then db.splitX        = defaults.splitX    end
    if db.listCollapsed == nil then db.listCollapsed  = false              end

    -- Currently selected note (UI state, not data)
    if db.selectedNoteID == nil then db.selectedNoteID = nil end

    -- Font / display
    if db.fontSize    == nil then db.fontSize   = defaults.fontSize end
    if db.fontChoice  == nil then db.fontChoice = "notoserif"       end
    if db.lineHeight  == nil then db.lineHeight = "1.0"             end

    -- Feature flags
    if db.autosave        == nil then db.autosave        = defaults.settings.autosave        end
    if db.contextSurface  == nil then db.contextSurface  = defaults.settings.contextSurface  end
    if db.bcbIntegration  == nil then db.bcbIntegration  = defaults.settings.bcbIntegration  end
    if db.sendKeybind     == nil then db.sendKeybind     = defaults.settings.sendKeybind      end
    if db.captureKeybind  == nil then db.captureKeybind  = defaults.settings.captureKeybind   end
    if db.hideLoginMessage== nil then db.hideLoginMessage= defaults.settings.hideLoginMessage end

    -- Minimap icon (LibDBIcon state)
    if db.minimapIcon == nil then
        db.minimapIcon = { hide = false, minimapPos = 220 }
    end

    -- Sticky note positions { [noteID] = {x,y,w,h,shown} }
    if db.postits == nil then db.postits = {} end

    -- Appearance prefs
    if db.listEntryHeight == nil then db.listEntryHeight = "normal"  end

    -- Advanced
    if db.confirmClose    == nil then db.confirmClose    = false     end

    -- Trash
    if db.trashFeature     == nil then db.trashFeature     = true      end
    if db.warnBeforeDelete == nil then db.warnBeforeDelete = true      end
    if db.trashRetainDays  == nil then db.trashRetainDays  = 30       end

    -- Features
    if db.lockNotes    == nil then db.lockNotes    = false end
    if db.openOnLogin   == nil then db.openOnLogin   = false end
    if db.setupComplete == nil then db.setupComplete = false end
    -- setupPage is transient (set before reload, consumed on next login); nil is correct default

    -- Target Note
    if db.targetNoteType              == nil then db.targetNoteType              = "choose" end
    if db.targetNoteTagCreatureType   == nil then db.targetNoteTagCreatureType   = true     end
    if db.targetNoteTagFamily         == nil then db.targetNoteTagFamily         = false    end
    if db.targetNoteTagClassification == nil then db.targetNoteTagClassification = true     end
    if db.targetNoteTagFaction        == nil then db.targetNoteTagFaction        = true     end
    if db.targetNoteTagZone           == nil then db.targetNoteTagZone           = true     end
    if db.targetNoteTagBoss           == nil then db.targetNoteTagBoss           = true     end

    -- Inspect Note
    if db.inspectNoteMode         == nil then db.inspectNoteMode         = "manual" end
    if db.inspectNoteType         == nil then db.inspectNoteType         = "choose" end
    if db.inspectNoteAddSituation == nil then db.inspectNoteAddSituation = false    end
    if db.inspectNoteGearShow     == nil then db.inspectNoteGearShow     = "both"   end

    -- Tag Tree view
    if db.tagTreeMode          == nil then db.tagTreeMode          = false end
    if db.tagTreeStartExpanded == nil then db.tagTreeStartExpanded = false end
    if db.tagTreeStayOpen      == nil then db.tagTreeStayOpen      = true  end

    -- Reference Box
    if db.referenceBoxEnabled  == nil then db.referenceBoxEnabled  = true     end
    if db.refboxDisplayStyle   == nil then db.refboxDisplayStyle   = "normal" end
    if db.refboxMaxItems       == nil then db.refboxMaxItems       = 50       end
    if db.refboxAutoOpen       == nil then db.refboxAutoOpen       = true     end
    if db.refboxSide           == nil then db.refboxSide           = "left"   end

    -- Timestamp display
    if db.dateFormat      == nil then db.dateFormat      = "relative"    end
    if db.use24Hour       == nil then db.use24Hour       = true         end

    -- Note list sort
    if db.sortBy          == nil then db.sortBy          = "creation"   end
    if db.sortAsc         == nil then db.sortAsc         = false        end

    -- Context popup anchor position (CENTER-relative)
    if db.popupAnchorX == nil then db.popupAnchorX = 0   end
    if db.popupAnchorY == nil then db.popupAnchorY = 200 end

    -- Context popup hold time (seconds; 0 = stay until manually closed)
    if db.popupHoldTime == nil then db.popupHoldTime = 5 end

    -- Known characters registry — built automatically on each login.
    -- { ["Name-Realm"] = { name, realm, class, lastSeen } }
    -- Non-precious: safe to wipe. Rebuilds as each character logs in.
    if db.knownChars == nil then db.knownChars = {} end

    -- Tag index — maps tag name → set of note IDs { [id] = true }.
    -- Rebuilt from scratch by MigrateSettingsDB if absent.
    -- Non-precious: fully derivable from notes.
    if db.tagIndex == nil then db.tagIndex = {} end

    -- Maximum number of sticky notes that can be open at once (1–20, default 10)
    if db.stickyMaxCount        == nil then db.stickyMaxCount        = 10    end
    -- When true, Ctrl+H "hide all stickies" persists across reloads and relogins.
    -- When false (default), stickies reappear automatically after a reload/relog.
    if db.stickiesHiddenPersist == nil then db.stickiesHiddenPersist = false end

    -- Undo/redo history depth per note (runtime only — never persisted to NotesDB).
    -- Range: 10-200. Values above 50 show a memory warning in Config.
    if db.undoDepth          == nil then db.undoDepth          = 50  end

    -- Undo snapshot idle delay: seconds after last keystroke before a snapshot fires.
    -- Range 0.3-3.0, default 0.8.
    if db.undoIdleDelay      == nil then db.undoIdleDelay      = 0.8 end

    -- Undo forced interval: max seconds of continuous typing before a snapshot is
    -- forced regardless of speed. Range 1-10, default 3.
    if db.undoForcedInterval == nil then db.undoForcedInterval = 3   end

    -- Session history: max auto-save slots per note (1-20, default 5).
    -- Each slot stores a full note snapshot from the previous logout/reload.
    if db.historyMaxSlots    == nil then db.historyMaxSlots    = 5   end

    -- Whether the WYSIWYG formatting toolbar is visible between timestamp and body.
    if db.wysiwygBarVisible == nil then db.wysiwygBarVisible = true end

    -- What to hide when entering combat.
    -- "nothing"        = do nothing (default)
    -- "hide_all"       = hide main window + companions + sticky notes
    -- "hide_no_stickies" = hide main window + companions, keep sticky notes visible
    if db.combatAction == nil then db.combatAction = "nothing" end

    -- QuickNote: inject button into quest/gossip/book frames to create notes from game UI
    -- quickNoteAction: what happens when the button is clicked
    --   "silent"  = create note silently in background (default)
    --   "open"    = create note and open BNB on it
    --   "confirm" = show a small popup to confirm/edit title before creating
    if db.quickNoteEnabled  == nil then db.quickNoteEnabled  = true     end
    if db.quickNoteAction   == nil then db.quickNoteAction   = "silent" end
    -- Persisted position for the Immersion floating button (nil = use built-in default)
    -- quickNoteImmersionX / quickNoteImmersionY: intentionally no default — nil means
    -- "use the built-in constant". Set by drag-stop in QuickNote.lua.
    -- DialogueUI: auto-create a note whenever the user clicks DUI's copy text button.
    -- Default true — the hook is installed unconditionally; this setting gates note creation.
    if db.duiAutoNote == nil then db.duiAutoNote = true end
    -- Immersion: show the floating Quick Note button during Immersion dialogues
    if db.quickNoteImmersionBtn == nil then db.quickNoteImmersionBtn = true end
    if db.saveQuestRewards      == nil then db.saveQuestRewards      = true end

    -- Window scale lock: when true the resize handle is hidden and the window cannot be scaled.
    if db.scaleLocked  == nil then db.scaleLocked  = false end

    -- Focus mode: hide the entire WoW UI (UIParent) when focus mode is active.
    if db.focusHideUI  == nil then db.focusHideUI  = true  end

    -- Focus Mode Orbit
    if db.focusOrbitEnabled     == nil then db.focusOrbitEnabled     = true   end
    if db.focusOrbitSpeed       == nil then db.focusOrbitSpeed       = 0.004  end  -- very slow/cinematic
    if db.focusOrbitResumeDelay == nil then db.focusOrbitResumeDelay = 3.0    end  -- seconds; 0 = never resume
    if db.focusOverlayAlpha     == nil then db.focusOverlayAlpha     = 0.6    end  -- dark overlay behind focus window
    if db.focusOverlayUseSkinColor == nil then db.focusOverlayUseSkinColor = false end  -- tint overlay with skin color

    -- Rich Notes
    if db.newNotesRichByDefault == nil then db.newNotesRichByDefault = false end
    if db.richOpenInEditor     == nil then db.richOpenInEditor     = false end
    if db.skinRandomize        == nil then db.skinRandomize        = false end
    if db.skinRandomizeBrightness == nil then db.skinRandomizeBrightness = false end

    -- Rich note live preview window
    -- richPreviewAutoShow: open the preview automatically when a rich note is selected
    if db.richPreviewAutoShow    == nil then db.richPreviewAutoShow    = true  end
    -- focusPreviewAlwaysShow: always open preview when entering focus mode (for rich notes)
    if db.focusPreviewAlwaysShow == nil then db.focusPreviewAlwaysShow = true  end
    -- previewDebounce: seconds after last keystroke before live preview re-renders
    if db.previewDebounce        == nil then db.previewDebounce        = 0.3   end
    -- lsmFonts: load LibSharedMedia fonts into the font picker (requires reload)
    if db.lsmFonts               == nil then db.lsmFonts               = false end
    -- Rich Notes independent heading/body sizes
    if db.richIndependentSizes   == nil then db.richIndependentSizes   = false end
    if db.richH1Size             == nil then db.richH1Size             = 25    end
    if db.richH2Size             == nil then db.richH2Size             = 20    end
    if db.richH3Size             == nil then db.richH3Size             = 16    end
    if db.richBodySize           == nil then db.richBodySize           = 12    end

    -- Direct Send
    if db.directSend           == nil then db.directSend           = {}    end
    if db.directSend.autoReject == nil then db.directSend.autoReject = false end

    -- Reference Box: show ItemID / SpellID in the game's native tooltip for any item or spell
    if db.refboxShowIDs == nil then db.refboxShowIDs = false end

    -- Character sidebar feature.
    -- sidebarEnabled:    master toggle (off by default until user enables it)
    -- sidebarAutoSwitch: automatically switch to the logged-in character's slot on login
    -- sidebarActiveKey:  persisted active filter key ("all", "global", "char:Name-Realm")
    if db.sidebarEnabled    == nil then db.sidebarEnabled    = false end
    if db.sidebarAutoSwitch == nil then db.sidebarAutoSwitch = false end
    if db.sidebarActiveKey  == nil then db.sidebarActiveKey  = "all" end

    -- Alarm system global defaults.
    if db.alarmDefaults == nil then
        db.alarmDefaults = {
            snoozeDefault = 5,
            glowType      = 2,   -- 1=Pixel 2=AutoCast 3=Border 4=Proc
            glowColor     = { 0.400, 0.733, 0.416, 1.0 },
            glowMode      = "pulse",  -- "continuous"|"pulse"|"once"
        }
    end

    -- What's New window: last version string acknowledged by the user.
    -- Intentionally NOT defaulted to any value — nil means "never seen",
    -- which causes the window to show on first install or after a version bump.
    -- (The migration block in MigrateSettingsDB also leaves it nil on upgrade.)
    -- db.lastSeenWhatsNewVersion is written on close by UI/WhatsNew.lua.

    -- Debug mode must never persist through a reload or relog.
    -- Always clear it here so the user has to re-enable it each session.
    db.debugMode     = nil
    db.debugWaypoint = nil
    BNB._debugMode        = nil
    BNB._debugImmersionPos = nil
end

--------------------------------------------------------------------------------
-- PUBLIC ENTRY POINT — called from Events.lua on ADDON_LOADED
--------------------------------------------------------------------------------
function BNB.InitializeDB()
    -- Settings DB must be initialised first so BigNoteBoxDB exists
    -- before any settings are read.
    InitSettingsDB()
    MigrateSettingsDB()

    -- Notes DB is owned by BigNoteBoxDB companion addon.
    -- BigNoteBoxNotesDB_Loaded is set at file-load time by BigNoteBoxDB.lua,
    -- before SavedVariables are available — but it persists into ADDON_LOADED.
    if BigNoteBoxNotesDB_Loaded then
        -- Companion addon is loaded and notes are available.
        BNB._notesAvailable = true
    else
        -- BigNoteBoxDB companion addon is not loaded — notes unavailable.
        -- Show the "install BigNoteBoxDB" warning panel instead of the note list.
        BNB._notesAvailable = false
    end

    if BNB._notesAvailable then
        BNB.InitNotesDB()
        BNB.MigrateNotesDB()
    end
end

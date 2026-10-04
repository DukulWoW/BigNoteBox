-- BigNoteBox Core/Database.lua — SavedVariables initialization
--
-- SPLIT ARCHITECTURE (v1.2.0+):
--   BigNoteBoxNotesDB  — owned by the BigNoteBoxDB companion addon.
--                        Notes and noteOrder ONLY. Never wiped by reset.
--   BigNoteBoxDB       — owned by BigNoteBox (this addon).
--                        Settings, window state, minimap, UI prefs.
--
-- BigNoteBoxDB.lua (companion) only sets BigNoteBoxNotesDB_Loaded. It loads
-- first (BigNoteBox lists it in OptionalDeps and it lists nothing back, SV-04);
-- BNB.InitializeDB() then runs InitNotesDB() / MigrateNotesDB() at BigNoteBox's
-- ADDON_LOADED. Events.lua still copes with the reverse order.
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
-- NOTE FIELDS: the one list is Core/NoteFields.lua (BNB.NOTE_FIELDS, CMP-01).
--   A new note field is one line there; copy, history, backup, share and
--   every import read it.
--
-- NOTES DB ROOT: notes, noteOrder, trash, dbVersion, migrationDone (v7)
-- History snapshots hold content fields only since v8 (SV-11).
--
-- TRASH DB  (BigNoteBoxNotesDB.trash):
--   Full note copy + deletedAt (unix timestamp). Purged after trashRetainDays days.
--   trashRetainDays = 0 → trash disabled, deletes are permanent.
--
-- SITUATION STRING FORMAT (v1):  "<kind>:<value>"
--   kind  = "zone" | "instance" | "subzone" | "player" | "npc" (npc matches as player) | "guild"
--           | "itype" | "open" | "state" (ALL-232 S4)
--   value = plain display name as returned by WoW APIs; for itype / open /
--           state a key instead (dungeon, vendor, rested: BNB.SITUATION_CHOICES)
--   Held in the list note.situations since NOTES v10 (was the one string
--   note.context, ALL-232); read through BNB.NoteSituations (NoteFields.lua).
--   Parsed by: DecodeContext(), NoteMatches() in Features/ContextNotes.lua
--   If this format ever changes, bump NOTES_SCHEMA_VERSION and add a migration.

local BNB = BigNoteBox

--------------------------------------------------------------------------------
-- SCHEMA VERSIONS  — increment when a migration step is added
--------------------------------------------------------------------------------
local NOTES_SCHEMA_VERSION    = 11  -- bump + add block to MigrateNotesDB()
local SETTINGS_SCHEMA_VERSION = 18  -- bump + add block to MigrateSettingsDB()

--------------------------------------------------------------------------------
-- DEFAULTS (SV-03, ALL-136.8)
-- The one list of settings defaults. InitSettingsDB fills every key that is
-- nil in BigNoteBoxDB from here (tables are merged key by key, a saved value
-- is never replaced). Code that needs a fallback reads BNB.DEFAULTS.<key>,
-- never its own literal, and slider Reset values come from here too.
-- Read-only: copy a table before changing it.
-- Keys whose nil means something (saveMode, oracleTheme, quickNoteKeyMode,
-- lastSeenWhatsNewVersion, ...) are left out on purpose: nil is their default.
--------------------------------------------------------------------------------
BNB.DEFAULTS = {
    -- Window position / size, main window and Focus mode
    windowPos = { x = 0, y = 0, w = 820, h = 640 },
    focusPos  = { x = 0, y = 0, w = 620, h = 540 },

    -- Splitter and collapse state
    splitX        = 240,
    listCollapsed = false,

    -- Font / display (fontChoice depends on the client language: InitSettingsDB)
    fontSize   = 13,
    lineHeight = "1.0",

    -- Feature flags
    contextSurface   = true,
    bcbIntegration   = true,
    hideLoginMessage = false,

    -- Minimap icon (LibDBIcon state)
    minimapIcon = { hide = false, minimapPos = 220 },

    -- Sticky note positions and config { [noteID] = {x,y,w,h,shown,...} }
    postits = {},

    -- Appearance prefs
    listEntryHeight = "normal",

    -- Advanced
    confirmClose = false,

    -- Trash
    trashFeature     = true,
    warnBeforeDelete = true,
    trashRetainDays  = 30,

    -- Features
    lockNotes     = false,
    openOnLogin   = false,
    setupComplete = false,
    -- setupPage is transient (set before reload, consumed on next login); nil is correct

    -- Target Note
    targetNoteType              = "choose",
    targetNoteTagCreatureType   = true,
    targetNoteTagFamily         = false,
    targetNoteTagClassification = true,
    targetNoteTagFaction        = true,
    targetNoteTagZone           = true,
    targetNoteTagBoss           = true,

    -- Inspect Note
    inspectNoteMode         = "manual",
    inspectNoteType         = "choose",
    inspectNoteAddSituation = false,
    inspectNoteGearShow     = "both",

    -- Tag Tree view
    tagTreeMode          = false,
    tagTreeStartExpanded = false,
    tagTreeStayOpen      = true,

    -- Reference Box and Tasks (ALL-102)
    referenceBoxEnabled = true,
    tasksEnabled        = true,
    refboxDisplayStyle  = "normal",
    refboxMaxItems      = 50,
    refboxAutoOpen      = true,
    refboxSide          = "left",
    -- Reference Box: show ItemID / SpellID in the game's tooltip for any item or spell
    refboxShowIDs       = false,

    -- Tasks
    taskRemoveOnComplete  = false,     -- false = keep completed tasks, dimmed
    taskStickyDefault     = "tasks",   -- default sticky view for notes with tasks
    taskCompletedPosition = "bottom",  -- where completed tasks go in the list
    taskSpacing           = "normal",  -- "compact" | "normal" | "spacious"
    taskPanelExpanded     = true,      -- task panel expanded in the Reference Box
    -- Per-note task/attachment split ratio: { [noteID] = 0.0..1.0 }
    -- 0.5 = equal split; 1.0 = tasks take all; 0.0 = attachments take all
    taskSplitRatio        = {},

    -- Timestamp display
    dateFormat = "relative",
    use24Hour  = true,

    -- Note list sort
    sortBy  = "creation",
    sortAsc = false,

    -- Context popup anchor position (CENTER-relative) and hold time
    -- (seconds; 0 = stay until manually closed)
    popupAnchorX  = 0,
    popupAnchorY  = 200,
    popupHoldTime = 5,

    -- Known characters registry, built on each login.
    -- { ["Name-Realm"] = { name, realm, class, lastSeen } }. Safe to wipe.
    knownChars = {},

    -- Maximum number of sticky notes open at once (slider 1-50, BUG-28)
    stickyMaxCount        = 20,
    -- true: Ctrl+H "hide all stickies" persists across reloads and relogins
    stickiesHiddenPersist = false,

    -- Undo/redo history depth per note (runtime only, never in the notes DB).
    -- Range 10-200; above 50 shows a memory warning in Settings.
    undoDepth          = 50,
    -- Seconds after the last keystroke before an undo snapshot (0.3-3.0)
    undoIdleDelay      = 0.8,
    -- Max seconds of continuous typing before a snapshot is forced (1-10)
    undoForcedInterval = 3,

    -- Session history: max auto slots per note (1-20)
    historyMaxSlots = 5,

    -- WYSIWYG formatting toolbar between timestamp and body
    wysiwygBarVisible = true,

    -- When entering combat: "nothing" | "hide_all" (main window, companions,
    -- stickies) | "hide_no_stickies"
    combatAction = "nothing",

    -- Quick Note button in quest/gossip/book frames.
    -- quickNoteAction: "silent" = create in the background, "open" = create
    -- and open BNB on it, "confirm" = small popup to edit the title first.
    -- quickNoteImmersionX/Y have no default: nil = the built-in position.
    quickNoteEnabled      = true,
    quickNoteAction       = "silent",
    -- DialogueUI: a note whenever the user clicks DUI's copy text button
    duiAutoNote           = true,
    -- Immersion: the floating Quick Note button during Immersion dialogues
    quickNoteImmersionBtn = true,
    saveQuestRewards      = true,

    -- Window scale lock: hides the resize handle
    scaleLocked = false,

    -- Focus mode: hide the whole WoW UI while it is open
    focusHideUI = true,

    -- Focus Mode Orbit
    focusOrbitEnabled        = true,
    focusOrbitSpeed          = 0.004,  -- very slow/cinematic
    focusOrbitResumeDelay    = 3.0,    -- seconds; 0 = never resume
    focusOverlayAlpha        = 0.6,    -- dark overlay behind the focus window
    focusOverlayUseSkinColor = false,  -- tint the overlay with the skin colour

    -- Rich Notes
    newNotesRichByDefault   = false,
    richOpenInEditor        = false,
    skinRandomize           = false,
    skinRandomizeBrightness = false,

    -- Rich note live preview: open it when a rich note is selected / always in
    -- Focus mode; seconds after the last keystroke before it re-renders
    richPreviewAutoShow    = true,
    focusPreviewAlwaysShow = true,
    previewDebounce        = 0.3,
    -- LibSharedMedia fonts in the font picker (opt-in, needs a reload)
    lsmFonts               = false,
    -- Rich Notes independent heading/body sizes
    richIndependentSizes   = false,
    richH1Size             = 25,
    richH2Size             = 20,
    richH3Size             = 16,
    richBodySize           = 12,

    -- Blizzard icon autocomplete (opt-in, Advanced tab)
    blizzardIconComplete = false,

    -- Direct Send
    directSend = { autoReject = false },

    -- Character sidebar.
    -- sidebarEnabled:    master toggle
    -- sidebarAutoSwitch: switch to the logged-in character's slot on login
    -- sidebarActiveKey:  active filter ("all", "global", "char:Name-Realm")
    sidebarEnabled    = false,
    sidebarAutoSwitch = false,
    sidebarActiveKey  = "all",
    sidebarSide       = "right",
    sidebarAtBottom   = false,
    sidebarSmallIcons = false,

    -- Note right-click menu (ALL-148, UI/NoteContextMenu.lua), Modules page.
    -- contextMenuClick: what a click on each main item does, the key of one
    -- of its sub-menu entries or "menu" (the click only opens the sub-menu).
    -- contextMenuDelay: seconds of hover before a sub-menu opens.
    contextMenuClick = { open = "sticky", create = "menu", actions = "menu", history = "menu" },
    contextMenuDelay = 0.10,

    -- Alarm system defaults for new alarms
    alarmDefaults = {
        snoozeDefault = 5,
        glowType      = 2,   -- 1=Pixel 2=AutoCast 3=Border 4=Proc
        glowColor     = { 0.400, 0.733, 0.416, 1.0 },
        glowMode      = "continuous",  -- "continuous"|"pulse"|"once"
    },
}

--------------------------------------------------------------------------------
-- DEV MODE (ALL-129)
-- The BigNoteBox_Dev addon (never packaged) is dev mode: while it is enabled,
-- notes come from its own SavedVariable BigNoteBoxDevDB.notesDB (same shape as
-- BigNoteBoxNotesDB) and the labs keep their work in BigNoteBoxDevDB too.
-- Settings stay shared. Nothing swaps tables at logout: every reader goes
-- through BNB.NotesDB() / BNB.LabDB(), so each file saves only its own set.
-- Never read the BigNoteBoxNotesDB global directly outside this file.
--------------------------------------------------------------------------------
function BNB.IsDevMode() return BNB._devMode == true end

-- The active notes set: { notes, noteOrder, trash, dbVersion }
function BNB.NotesDB()
    if BNB._devMode then return BigNoteBoxDevDB.notesDB end
    return BigNoteBoxNotesDB
end

-- Replace the active notes set (Factory Reset)
function BNB.SetNotesDB(t)
    if BNB._devMode then BigNoteBoxDevDB.notesDB = t else BigNoteBoxNotesDB = t end
end

-- Where the developer labs (Background Lab, Icon Lab, search layout tool) keep
-- their work: devBgLab, devIconLab, devSearch
function BNB.LabDB()
    if BNB._devMode then return BigNoteBoxDevDB end
    return BigNoteBoxDB
end

local DeepCopy = BNB.DeepCopy

local LAB_KEYS = { "devBgLab", "devIconLab", "devSearch" }

-- Runs at ADDON_LOADED. The first dev-mode login copies the current notes into
-- the dev set (only while the dev set does not exist yet, so never again) and,
-- once, the lab work out of the settings DB. The originals are left untouched.
local function InitDevMode()
    if not BigNoteBoxDev_Loaded then return end
    if type(BigNoteBoxDevDB) ~= "table" then BigNoteBoxDevDB = {} end
    local dev = BigNoteBoxDevDB
    BNB._devMode = true
    -- Debug mode starts on in dev mode (Dukul, 2026-10-02). InitSettingsDB clears it
    -- on every load, so this re-arms it each reload; turning it off holds until then.
    BigNoteBoxDB.debugMode = true
    BNB._debugMode = true
    if dev.notesDB == nil then
        local src = BigNoteBoxNotesDB_Loaded and BigNoteBoxNotesDB
        dev.notesDB = type(src) == "table" and DeepCopy(src) or {}
        local n = 0
        for _ in pairs(dev.notesDB.notes or {}) do n = n + 1 end
        BNB._devNotesCopied = n
    end
    if not dev.labsCopied then
        for _, k in ipairs(LAB_KEYS) do
            if dev[k] == nil and BigNoteBoxDB[k] ~= nil then dev[k] = DeepCopy(BigNoteBoxDB[k]) end
        end
        dev.labsCopied = true
    end
end

--------------------------------------------------------------------------------
-- INITIALIZE NOTES DB  (the active set: BigNoteBoxNotesDB, or the dev set)
-- Called first. Notes are precious — only ever add missing keys, never reset.
-- Public so BigNoteBoxDB.lua (the companion data addon) can call it directly.
--------------------------------------------------------------------------------
function BNB.InitNotesDB()
    if not BNB.NotesDB() then BNB.SetNotesDB({}) end
    local ndb = BNB.NotesDB()
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
    local ndb = BNB.NotesDB()
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

    -- ++ v5 -> v6: repair notes migrated from other addons (BUG-06 / SV-01) +++++
    -- MigrateNotes saved per-character notes as scope = "character" plus a
    -- character field. Everything else reads "char:Name-Realm", so those notes
    -- only ever showed under "All".
    if v < 6 then
        for _, list in ipairs({ ndb.notes or {}, ndb.trash or {} }) do
            for _, note in pairs(list) do
                if note.scope == "character" then
                    note.scope = note.character and ("char:" .. note.character) or "global"
                    note.character = nil
                end
            end
        end
        v = 6
    end

    -- ++ v6 -> v7: migrationDone moves to the notes DB (SV-06, ALL-136.5) +++++
    -- It lived in BigNoteBoxDB, so "Reset settings" wiped it and the next
    -- login offered (and imported) the same addon's notes again. The old
    -- settings copy is left in place and no longer read.
    if v < 7 then
        local old = BigNoteBoxDB and BigNoteBoxDB.migrationDone
        if type(old) == "table" then
            ndb.migrationDone = ndb.migrationDone or {}
            for k, done in pairs(old) do
                if done then ndb.migrationDone[k] = true end
            end
        end
        v = 7
    end

    -- ++ v7 -> v8: history snapshots keep only content fields (SV-11), the
    -- dummy updatedAt field goes (SV-08), ALL-136.8 ++++++++++++++++++++++++++++
    -- Snapshots copied every content field of the note, up to 21 per note.
    -- Trimmed to the list in Features/NoteHistory.lua (SNAP_FIELDS + timestamp),
    -- written out here because that file loads after this one.
    if v < 8 then
        local keep = { timestamp = true, title = true, body = true, richMode = true,
                       tags = true, tasks = true, taskList = true }
        local function Trim(snap)
            if type(snap) ~= "table" then return end
            for k in pairs(snap) do
                if not keep[k] then snap[k] = nil end
            end
        end
        for _, list in ipairs({ ndb.notes or {}, ndb.trash or {} }) do
            for _, note in pairs(list) do
                if type(note.history) == "table" then
                    for _, snap in ipairs(note.history) do Trim(snap) end
                end
                Trim(note.manualSnapshot)
                note.updatedAt = nil
            end
        end
        v = 8
    end

    -- Sticky settings saved "When you leave: Minimize" as contextLeave
    -- "bt-minimize" (v1.13.0 to v1.16.0), which nothing reads; the shared
    -- Situation editor (CMP-03) saves "minimize"
    if v < 9 then
        for _, list in ipairs({ ndb.notes or {}, ndb.trash or {} }) do
            for _, note in pairs(list) do
                if note.contextLeave == "bt-minimize" then note.contextLeave = "minimize" end
            end
        end
        v = 9
    end

    -- A note can have several situations (ALL-232): the single string
    -- note.context becomes the list note.situations = { context }
    if v < 10 then
        for _, list in ipairs({ ndb.notes or {}, ndb.trash or {} }) do
            for _, note in pairs(list) do
                local ctx = note.context
                if type(ctx) == "string" and ctx ~= "" and note.situations == nil then
                    note.situations = { ctx }
                end
                note.context = nil
            end
        end
        v = 10
    end

    -- Note icons come from the game, only the race portraits still ship
    -- (ALL-238): an old bundled path becomes the game icon of the same name,
    -- or nil (the default icon) for one this client lacks. History snapshots
    -- hold no icon (SV-11)
    if v < 11 then
        for _, list in ipairs({ ndb.notes or {}, ndb.trash or {} }) do
            for _, note in pairs(list) do
                if note.icon then note.icon = BNB.LegacyIconPath(note.icon) end
            end
        end
        v = 11
    end

    -- Never lower the stored version: running an older build must not make the
    -- next upgrade run the migrations again (SV-10)
    ndb.dbVersion = math.max(ndb.dbVersion or 1, NOTES_SCHEMA_VERSION)
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

    -- Blocks that only filled a default for a new key (v2, v3's second half,
    -- v4, v6-v14) are empty now: InitSettingsDB runs first and fills every
    -- default from BNB.DEFAULTS (SV-03, ALL-136.8). The steps stay so the
    -- version numbers keep their meaning. Blocks that change saved data stay.

    -- v1 -> v2: introduced tagIndex (runtime-only since v17, SV-05)
    if v < 2 then v = 2 end

    -- ++ v2 -> v3: remove "favorites" sort mode ++++++++++++++++++++++++++++++++++
    if v < 3 then
        -- "favorites" was removed from the sort dropdown. Reset to "creation"
        -- so the UI doesn't show a blank/unknown sort label for existing users.
        if db.sortBy == "favorites" then
            db.sortBy = "creation"
        end
        v = 3
    end

    -- v3 -> v4: introduced alarmDefaults (now a default)
    if v < 4 then v = 4 end

    -- ++ v4 -> v5: reset alarmDefaults.glowColor to BNB green (was gold) ++++++++++
    if v < 5 then
        if db.alarmDefaults then
            db.alarmDefaults.glowColor = { 0.400, 0.733, 0.416, 1.0 }
        end
        v = 5
    end

    -- v5 -> v14 introduced: sidebar layout (v6), rich preview auto-show and
    -- directSend (v7), refboxSide and focus preview (v8), preview debounce (v9),
    -- What's New tracking (v10, nil on purpose), lsmFonts (v11), rich heading
    -- sizes (v12), task settings (v13), Blizzard icon autocomplete (v14).
    -- All of them are defaults now.
    if v < 14 then v = 14 end

    -- ++ v14 -> v15: drop the dead autosave key (ALL-52) ++++++++++++++++++++++
    if v < 15 then
        -- "Autosave notes on switch" was never read by anything. Save behaviour
        -- is now db.saveMode (nil = automatic, "manual"), a new key on purpose:
        -- autosave = true was stored for users who had manual saving.
        db.autosave = nil
        v = 15
    end

    if v < 16 then
        -- Default alarm glow mode Pulse -> Continuous (ALL-136.3, Dukul). No
        -- setting ever changed alarmDefaults, so "pulse" here is the old built-in
        -- default, not a choice. Pulse picked on an alarm itself is kept.
        if db.alarmDefaults and db.alarmDefaults.glowMode == "pulse" then
            db.alarmDefaults.glowMode = "continuous"
        end
        v = 16
    end

    if v < 17 then
        -- The tag index is runtime-only now (SV-05, ALL-136.8): it is derived
        -- from the notes, and a saved copy went stale (and stayed the other
        -- notes set's after a dev-mode switch).
        db.tagIndex = nil
        db._needsTagRebuild = nil
        v = 17
    end

    if v < 18 then
        -- A character's sidebar icon could be a bundled class / faction icon;
        -- those come from the game now (ALL-238, as NOTES v11)
        for _, rec in pairs(db.knownChars or {}) do
            if type(rec) == "table" and rec.slotIcon then
                rec.slotIcon = BNB.LegacyIconPath(rec.slotIcon)
            end
        end
        v = 18
    end

    -- Never lower the stored version (SV-10, as in MigrateNotesDB)
    db.dbVersion = math.max(db.dbVersion or 1, SETTINGS_SCHEMA_VERSION)
end

--------------------------------------------------------------------------------
-- INITIALIZE SETTINGS DB  (BigNoteBoxDB)
-- Safe to wipe on reset: contains no user-created content.
--------------------------------------------------------------------------------
-- Fills every nil key of db from def. A nested table is merged key by key, so
-- a saved table keeps its own values and only gains the keys it lacks; a
-- saved value is never replaced, whatever its type.
local function ApplyDefaults(db, def)
    for k, v in pairs(def) do
        if db[k] == nil then
            db[k] = DeepCopy(v)
        elseif type(v) == "table" and type(db[k]) == "table" then
            ApplyDefaults(db[k], v)
        end
    end
end

local function InitSettingsDB()
    BigNoteBoxDB = BigNoteBoxDB or {}
    local db = BigNoteBoxDB

    ApplyDefaults(db, BNB.DEFAULTS)

    if db.fontChoice == nil then
        -- On first install, default to WoW's locale font for CJK clients so
        -- Chinese/Korean/Japanese text is immediately readable without manual setup.
        -- Uses the active (forced-or-client) language so a forced CJK language also defaults here.
        -- A language with its own font set (ALL-14: zhCN) needs nothing here: its
        -- pick lives in fontChoiceBySet and starts at the set default (WoW Hei),
        -- so fontChoice stays the Latin pick for when the language is switched.
        local locale = (BNB.GetActiveLanguage and BNB.GetActiveLanguage()) or (GetLocale and GetLocale()) or ""
        local ownSet = BNB.GetActiveFontSet and BNB.GetActiveFontSet() ~= "latin"
        if ownSet then
            db.fontChoice = "notoserif"
        elseif locale == "zhCN" or locale == "zhTW" or locale == "koKR" or locale == "jaJP" then
            db.fontChoice = "wow"
        else
            db.fontChoice = "notoserif"
        end
    end

    -- What's New window: last version string acknowledged by the user.
    -- Intentionally NOT defaulted to any value: nil means "never seen",
    -- which causes the window to show on first install or after a version bump.
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
    -- Dev mode (BigNoteBox_Dev enabled) brings its own notes set.
    InitDevMode()
    if BigNoteBoxNotesDB_Loaded or BNB._devMode then
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

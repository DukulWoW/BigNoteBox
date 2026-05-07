-- BigNoteBoxDB.lua
-- Companion data addon for BigNoteBox.
-- This addon's sole purpose is to own the BigNoteBoxNotesDB SavedVariable so
-- that notes are stored independently of the main addon's settings. This means
-- notes survive a /bnb reset, addon updates, or disabling BigNoteBox itself.
--
-- Load order: WoW loads this before BigNoteBox when both are enabled (OptionalDeps).
-- SavedVariables are NOT available at file-load time — they are injected by WoW
-- before ADDON_LOADED fires. All init work is therefore handled in Events.lua
-- when ADDON_LOADED fires for either "BigNoteBoxDB" or "BigNoteBox".

-- Signal to BigNoteBox that the notes DB addon is present and loaded.
-- This global is checked by BNB.InitializeDB() at ADDON_LOADED time.
BigNoteBoxNotesDB_Loaded = true

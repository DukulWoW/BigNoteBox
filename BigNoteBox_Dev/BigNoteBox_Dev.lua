-- BigNoteBox_Dev.lua
-- Developer mode for BigNoteBox. Enabling this addon (AddOn list + reload) is
-- dev mode; disabling it goes back to normal. Never packaged into the release
-- zip, but tracked in the repo so anyone can download it from GitHub.
--
-- While it is loaded, BigNoteBox reads and writes:
--   BigNoteBoxDevDB.notesDB  - a separate set of notes (same shape as the
--                              normal BigNoteBoxNotesDB). The first dev-mode
--                              login copies the normal notes in, once.
--   BigNoteBoxDevDB.devBgLab / devIconLab / devSearch - the labs' saved work,
--                              copied once out of the settings DB.
-- Settings (BigNoteBoxDB) stay shared. All of the logic lives in BigNoteBox
-- (Core/Database.lua, BNB.NotesDB / BNB.LabDB); this file only owns the
-- SavedVariable. BigNoteBox lists this addon in OptionalDeps, so it loads first.

-- Checked by BigNoteBox at its ADDON_LOADED
BigNoteBoxDev_Loaded = true

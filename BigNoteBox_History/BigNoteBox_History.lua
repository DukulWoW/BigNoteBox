-- BigNoteBox_History (ALL-460, ALL-466): the note history and the kept undo /
-- redo history of BigNoteBox.
--
-- This addon only owns the SavedVariables table BigNoteBoxHistoryDB, so its
-- size stays out of BigNoteBox's settings and notes files. All logic lives in
-- BigNoteBox (Features/NoteHistory.lua, Features/UndoKeep.lua, the move in
-- Core/Database.lua). Always loaded since ALL-466 and listed in BigNoteBox's
-- OptionalDeps, so it loads first and its table is in place when BigNoteBox
-- loads, like BigNoteBoxDB. Missing or disabled = BigNoteBox shows a notice
-- at login and Note History / Keep undo between sessions count as off.

BigNoteBoxHistory_Loaded = true

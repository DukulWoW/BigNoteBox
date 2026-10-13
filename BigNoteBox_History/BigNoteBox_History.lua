-- BigNoteBox_History (ALL-460): the saved undo / redo history of BigNoteBox.
--
-- This addon only owns the SavedVariables table BigNoteBoxHistoryDB, so its
-- size stays out of BigNoteBox's settings and notes files. All logic lives in
-- BigNoteBox (Features/UndoKeep.lua), which loads this addon on demand while
-- Settings > Modules > Undo / Redo > "Keep undo history between sessions" is
-- on. Never loaded = BigNoteBox keeps undo for the session only, as before.

BigNoteBoxHistory_Loaded = true

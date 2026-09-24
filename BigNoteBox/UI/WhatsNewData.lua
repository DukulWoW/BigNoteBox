-- BigNoteBox UI/WhatsNewData.lua
--
-- EDITABLE PATCH NOTES FILE
-- Update this file before each release. The WhatsNew window reads it directly.
--
-- HOW TO UPDATE:
--   1. Change `version` to the new addon version string (must match Init.lua).
--   2. Replace the `entries` table with your new patch notes.
--   3. Each entry is a plain string. Prefix lines however you like:
--        "New: ..."   "Fixed: ..."   "Changed: ..."   "Removed: ..."
--   4. A line for one client only is a table instead of a string:
--        { forever = true, "..." }   -- WoW Forever only
--        { retail  = true, "..." }   -- Retail only
--      No "WoW Forever:" prefix needed; only that client sees the line.
--   That's it - no other files need to change for a routine version bump.
--
-- FORMAT RULES:
--   - Keep each entry to a single line of reasonable length.
--   - Plain ASCII only - no Unicode characters (they render as boxes in WoW).
--   - No markup - entries are rendered as plain GameFont text.
-- |cff66bb6aNew:|r
-- |cff66bb6aFixed:|r
-- |cff66bb6aChange:|r


local BNB = BigNoteBox

BNB.PATCH_NOTES = {
    version = "1.11.1",
    entries = {
        "|cff66bb6aChange:|r Deleting 2 or more notes always asks first, naming the notes",
        "|cff66bb6aChange:|r Trash window: Delete selected asks first",
        "|cff66bb6aFixed:|r Select All selected notes hidden by a search or tag filter",
        "|cff66bb6aFixed:|r A just-deselected note still looked selected in multi-select",
        "|cff66bb6aFixed:|r The Select button sometimes needed two clicks",
        "|cff66bb6aFixed:|r Deleting many notes at once froze the game for a moment",
        "|cff66bb6aFixed:|r 'Delete permanently' moved the note to Trash",
        "|cff66bb6aFixed:|r With Trash off, deleted notes were kept in a hidden Trash",
        "|cff66bb6aFixed:|r Multi-select stayed on after closing the window or Focus mode",
        "|cff66bb6aFixed:|r Duplicate and Copy/Move keep rich mode, tasks and all settings",
        "|cff66bb6aFixed:|r A copied note shared its tags with the original",
        "|cff66bb6aFixed:|r Empty gap in the toolbar with Trash turned off",
        { retail = true, "|cff66bb6aFixed:|r What's New, Feature List and Setup glow sat too far left" }
    },
}

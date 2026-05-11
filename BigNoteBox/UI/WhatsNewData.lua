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
--   That's it — no other files need to change for a routine version bump.
--
-- FORMAT RULES:
--   - Keep each entry to a single line of reasonable length.
--   - Plain ASCII only — no Unicode characters (they render as boxes in WoW).
--   - No markup — entries are rendered as plain GameFont text.
-- |cff66bb6aNew:|r
-- |cff66bb6aFixed:|r
-- |cff66bb6aChange:|r


local BNB = BigNoteBox

BNB.PATCH_NOTES = {
    version = "1.7.0",
    entries = {
        "|cff66bb6aNew:|r Sticky notes now have a focus mode. Open the sticky note settings and check Focus Mode",
        "|cff66bb6aChange:|r Removed eight background textures for sticky notes and added three new ones",
		"|cff66bb6aChange:|r Added a separate buttons graphic to when a sitcky note is in task mode, the button that switchs back to note mode is now a note",
		"|cff66bb6aFixed:|r The buttons in the task window now show as disabled when there are no tasks to clear/delete both in normal mode and skin mode",
		"|cff66bb6aFixed:|r Task mode in Sticky Notes should no longer flicker if the opacity is set to anything but 100% ",
		"|cff66bb6aFixed:|r Setting a situation or reset on a sub-task will now correctly show the icon in the task window in refbox",
    },
}
-- BigNoteBox UI/WhatsNewData.lua
--
-- EDITABLE PATCH NOTES FILE
-- Update this file before each release. The WhatsNew window reads it directly,
-- and after an update it becomes the pinned patch note (ALL-409, UI/WhatsNew.lua):
-- lines are grouped under their New / Change / Fixed label there, so keep the
-- "|cff66bb6aNew:|r " form. No {braces}: that note is a rich note (they are
-- turned into parentheses there).
--
-- HOW TO UPDATE:
--   1. Change `version` to the new addon version string (must match Init.lua).
--   2. Replace the `entries` table with your new patch notes.
--   3. Each entry is a plain string. Prefix lines however you like:
--        "New: ..."   "Fixed: ..."   "Changed: ..."   "Removed: ..."
--   4. A line for one client only is a table instead of a string:
--        { forever = true, "..." }   -- WoW Forever only
--        { retail  = true, "..." }   -- Retail only
--        { classic = true, "..." }   -- Classic only
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
    version = "1.25.0",
    entries = {
        "|cff66bb6aNew:|r Top bar menu. Pick which icons stay on the top bar and which go into the menu; icons that do not fit a narrow window move into it instead of covering the sort buttons. The sidebar toggle now lives at the bottom of this menu.",
        "|cff66bb6aNew:|r Two new icon categories, Stone tablets and Storage (49 bags).",
        "|cff66bb6aChange:|r Toast style arrows and button are greyed out while Follow my faction is ticked.",
        "|cff66bb6aFixed:|r In a narrow window the Select mode buttons no longer run off the window: the ones that do not fit are in the top bar menu.",
        "|cff66bb6aFixed:|r Turning off Sticky Notes no longer leaves an empty gap in the note's action bar.",
        "|cff66bb6aFixed:|r The right-click menu in a note now opens anywhere in the writing area, not only over the text.",
        { classic = true, "|cff66bb6aNew:|r Many more note icons: letters, books, race heads, faction tokens and gifts." },
    },
}

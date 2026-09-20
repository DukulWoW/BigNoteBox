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
    version = "1.7.4",
    entries = {
        "|cff66bb6aNew:|r Added a WoW Default font option that uses the game client's own font",
        "|cff66bb6aNew:|r Chinese, Korean and Japanese clients now default to that font on first use",
        "|cff66bb6aChange:|r Updated LibTourist, adding the new Midnight zones and delves",
        "|cff66bb6aChange:|r Updated LibCustomGlow, fixing the alarm glow on newer clients",
        "|cff66bb6aFixed:|r Right-clicking a task checkbox in RefBox also toggled the task",
        "|cff66bb6aFixed:|r Changing a task's reset type kept the old reset timestamp"
    },
}

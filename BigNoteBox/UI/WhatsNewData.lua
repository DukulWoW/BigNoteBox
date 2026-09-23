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
    version = "1.10.0",
    entries = {
        "|cff66bb6aNew:|r Traditional Chinese clients get their own font picker set",
        "|cff66bb6aChange:|r Buttons now use Blizzard's current, sharper button style",
        "|cff66bb6aChange:|r WoW Forever: sidebar slot borders match Forever's own UI art",
        "|cff66bb6aChange:|r WoW Forever: windows use a wood-grain background",
        "|cff66bb6aFixed:|r Note settings: Use Default and Random icon buttons sat below the edge",
        "|cff66bb6aFixed:|r WoW Forever: window borders no longer crowd the contents"
    },
}

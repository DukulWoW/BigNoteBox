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
    version = "1.7.3",
    entries = {
        "|cff66bb6aNew:|r Blizzard icon fields (Note config and Rich Note Ico tag) now support autocomplete search across 32,000+ icons",
        "|cff66bb6aNew:|r Type any part of an icon name to get suggestions with live previews. You can scroll the list with arrow keys and mouse wheel",
        "|cff66bb6aNew:|r Enable the icon list feature in Main Config > Advanced > Icons (off by default). This feature uses ~2 MB of memory",
        "|cff66bb6aChange:|r Default max amount of sticky notes changed from 10 > 20"
    },
}
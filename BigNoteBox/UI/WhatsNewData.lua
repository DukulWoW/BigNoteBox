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
    version = "1.9.0",
    entries = {
        "|cff66bb6aNew:|r Language selector: English or Simplified Chinese, whatever your client",
        "|cff66bb6aNew:|r Chinese font set: WoW Hei and WoW Kai in the pickers when Chinese is active",
        "|cff66bb6aNew:|r Font packs: BigNoteBox Fonts CN adds six Chinese fonts",
        "|cff66bb6aFixed:|r The font picker is a clean 8-font grid again, WoW's font is a checkbox",
        "|cff66bb6aFixed:|r LibSharedMedia fonts are a dropdown in sticky and New Note font pickers",
        "|cff66bb6aFixed:|r Sticky note titles in Chinese or Korean showed as boxes",
        "|cff66bb6aFixed:|r Chinese clients: deleting a tag caused an error",
        "|cff66bb6aFixed:|r Chinese translation completed for the migration windows"
    },
}

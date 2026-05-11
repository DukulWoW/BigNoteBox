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
    version = "1.7.2",
    entries = {
        "|cff66bb6aNew:|r You can now migrate notes from MyNotepad and AmmeNotepad",
		"|cff66bb6aNew:|r Sticky Notes can now live in the ESC menu screen (Sitcky Note Config > Pin to ESC Screen )",
		"|cff66bb6aNew:|r Sticky Notes can be set to always open in the ESC menu screen (Main Config > Features > Sticky Notes > Default to ESC screen only)",
		"|cff66bb6aNew:|r There is an overlay by default on the ESC screen, this can be turned off (Main Config > Features > Sticky Notes > Dim screen behind ESC sticky notes)",
        "|cff66bb6afixed:|r Dropdown menues i Sticky Note settings rendered below the window",
    },
}
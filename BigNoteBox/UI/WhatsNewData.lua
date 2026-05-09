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
        "|cff66bb6aNew:|r Task system! Add tasks and sub-tasks to any note",
        "|cff66bb6aNew:|r Tasks can have daily or weekly auto-reset (set in the task edit window)",
        "|cff66bb6aNew:|r Tasks can be bound to a situation (zone, instance, player) (set in the task edit window)",
        "|cff66bb6aNew:|r Sub-tasks can collapse and expand",
        "|cff66bb6aNew:|r Task panel in the Reference Box with header, footer, and splitter",
        "|cff66bb6aNew:|r Sticky notes can show task view instead of note body (toggle with the task button in the sticky header)",
        "|cff66bb6aNew:|r Task view in sticky notes with live checkbox toggling",
        "|cff66bb6aNew:|r Task filter button in the note list",
        "|cff66bb6aNew:|r Task icon shown in note list rows for notes with tasks",
        "|cff66bb6aNew:|r Tasks added as a share tier in the share system",
        "|cff66bb6aNew:|r Global reset and situation icons in sticky note task footer",
        "|cff66bb6aNew:|r Task list spacing setting -- Compact, Normal, Spacious (Config > Features > Tasks)",
        "|cff66bb6aNew:|r Stone background texture added to sticky note appearance (Sticky Settings > Appearance)",
        "|cff66bb6aChange:|r Background opacity in sticky notes can now be set to 0 (Sticky Settings > Appearance)",
        "|cff66bb6aChange:|r Sticky note task footer shows Tasks and Sub-tasks counts separately",
        "|cff66bb6aChange:|r Task toggle buttons match the Reference Box style",
    },
}
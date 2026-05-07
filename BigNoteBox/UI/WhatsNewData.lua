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
    version = "1.6.9",
    entries = {
		"|cff66bb6aAdded:|r You can now migrate notes from PurpleNotes, SimpleNote, QuickNote and OneWoW Notes",
		"|cff66bb6aAdded:|r Three new font outline options: \"SLUG\", \"SLUG Outline\", and \"SLUG Thick Outline\" that use WoW's Slug Text Rendering for smoother, crisper font edges. Available for normal notes and rich note editor in the Appearance tab",
		"|cff66bb6aAdded:|r Rich note view mode now renders with slug outline for crisper view",
		"|cff66bb6aAdded:|r Fun little stats view on the main config general tab showing how many notes you have and how much space they are taking up",
		"|cff66bb6aAdded:|r There is now a \"More features\" button in \"main config > general\" that shows all(?) features in BNB",
		"|cff66bb6aChange:|r Increased max open sticky notes from 20 to 50",
		"|cff66bb6aFixed:|r The Danger Zone overlay wouldn't properly go away when the window was closed",
		"|cff66bb6aFixed:|r Exporting notes should now export all fields. Was missing a bunch",
		"|cff66bb6aFixed:|r Sharing notes should now share all field if done with the \"Everything\" option",
    },
}
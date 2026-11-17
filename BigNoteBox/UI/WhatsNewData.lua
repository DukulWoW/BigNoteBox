-- BigNoteBox UI/WhatsNewData.lua
--
-- EDITABLE PATCH NOTES FILE
-- Update this file before each release. It is the newest page of the Help
-- book's Patch notes tab until the release tag puts it in PatchHistory.lua
-- (ALL-614, UI/WhatsNew.lua): lines are grouped under their New / Change /
-- Fixed label there, so keep the "|cff66bb6aNew:|r " form. No {braces}: the
-- page is rich markup (they are turned into parentheses there), except a
-- link to a part of BigNoteBox (ALL-617): {link*bnbui:settings.modules.spelling*}
-- (empty text = the place's name) or {link*bnbui:<key>*<own text>}. Keys:
-- Developer tools > UI link list. A line that names a Settings page links it.
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
--   - No markup but the BigNoteBox links above.
-- |cff66bb6aNew:|r
-- |cff66bb6aFixed:|r
-- |cff66bb6aChange:|r


local BNB = BigNoteBox

BNB.PATCH_NOTES = {
    version = "2.1.1",
    entries = {
        "|cff66bb6aFixed:|r A Lua error that repeated in dungeons and raids (Ragefire Chasm on WoW Forever) while a note had a situation: the game now hides some names there, and BigNoteBox skips them.",
    },
}

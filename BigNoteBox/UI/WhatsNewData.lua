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
--   4. A line for one client only is a table instead of a string:
--        { forever = true, "..." }   -- WoW Forever only
--        { retail  = true, "..." }   -- Retail only
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
    version = "1.10.0",
    entries = {
        "|cff66bb6aNew:|r Traditional Chinese clients get their own font picker set",
        "|cff66bb6aChange:|r Buttons now use Blizzard's current, sharper button style",
        "|cff66bb6aFixed:|r Note settings: Use Default and Random icon buttons sat below the edge",
        { forever = true, "|cff66bb6aChange:|r Sidebar slot borders match Forever's own UI art" },
        { forever = true, "|cff66bb6aChange:|r Windows use a wood-grain background" },
        { forever = true, "|cff66bb6aFixed:|r Window borders no longer crowd the contents" }
    },
}

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
    version = "1.23.1",
    entries = {
        "|cff66bb6aChange:|r The bundled fonts now ship with their license files (Assets/Fonts/OFL.txt and OpenDyslexic-LICENSE.txt).",
        "|cff66bb6aChange:|r Simplified Chinese: every string added since v1.21 is translated, and the older strings use the same words throughout (toasts, alarms, Reference Box, Oracle, snooze).",
        { classic = true, "|cff66bb6aChange:|r The Report a bug button sits beside the main window, with a red glow, as on WoW Forever (it was beside the Settings window)." },
        { classic = true, "|cff66bb6aChange:|r The language selector is now on Classic too (Settings > General and the setup wizard)." },
        { classic = true, "|cff66bb6aFixed:|r Reference Box \"Show IDs\" adds the ItemID and SpellID lines to tooltips (they were missing)." },
        { classic = true, "|cff66bb6aFixed:|r TBC Anniversary and MoP: the tl;dr line shows in the game tooltip of a player or NPC with a note." },
    },
}

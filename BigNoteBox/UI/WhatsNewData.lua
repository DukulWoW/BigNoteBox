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
    version = "1.8.0",
    entries = {
        "|cff66bb6aNew:|r Support for WoW Forever, as a beta",
        "|cff66bb6aNew:|r Simplified Chinese (zhCN) translation",
        "|cff66bb6aChange:|r The setup wizard's dimming is lighter, so the world shows through",
        "|cff66bb6aChange:|r The WaypointUI and TomTom buttons now open a copy box with the link",
        "|cff66bb6aFixed:|r Chinese and Korean clients showed boxes instead of text on buttons",
        "|cff66bb6aFixed:|r The font lists sometimes showed only Noto Serif until a /reload",
        "|cff66bb6aFixed:|r Outline names and some note settings headers are now translated",
        "|cff66bb6aFixed:|r Esc in the setup wizard now asks before closing",
        "|cff66bb6aFixed:|r The Waypoint Support window now closes with Esc",
        "|cff66bb6aFixed:|r A copy box could get stuck on screen after its window closed",
        "|cff66bb6aFixed:|r Two tooltips showed a stray code or a box instead of the right character",
        "|cff66bb6aFixed:|r WoW Forever: the glow around several windows was cut off"
    },
}

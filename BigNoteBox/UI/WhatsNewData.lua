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
    version = "1.11.0",
    entries = {
        "|cff66bb6aNew:|r Notes save automatically while you type (can be turned off)",
        "|cff66bb6aNew:|r Double-click a sticky note to edit it in place",
        "|cff66bb6aNew:|r NPC notes show the NPC's face in the list and on stickies",
        "|cff66bb6aNew:|r Inspected player notes show their face while targeted",
        "|cff66bb6aNew:|r Reference box: Model and Tasks are now icon tabs on its side",
        "|cff66bb6aNew:|r The model viewer shows a Horde or Alliance crest",
        "|cff66bb6aNew:|r Stickies show the lock, situation and character markers",
        "|cff66bb6aNew:|r Quick Note says 'Note created' in chat",
        "|cff66bb6aChange:|r Right-click an open sticky's icon to close it",
        "|cff66bb6aChange:|r Humanoid NPC notes without a portrait use a neutral icon",
        "|cff66bb6aChange:|r The Focus window always opens at screen centre",
        "|cff66bb6aChange:|r Quick Note buttons look pressed when clicked",
        "|cff66bb6aFixed:|r Boxes shown instead of dashes, bullets and arrows",
        "|cff66bb6aFixed:|r Insert bullet point button took focus from the note",
        "|cff66bb6aFixed:|r Export buttons in the restore comparison window",
        "|cff66bb6aFixed:|r Inspect window note button stayed greyed out for some players",
        "|cff66bb6aFixed:|r Show model viewer button spacing",
        "|cff66bb6aFixed:|r Adding a task to an NPC or player note shows the Tasks tab",
        "|cff66bb6aFixed:|r 'Open in BigNoteBox to edit' puts the cursor in the note",
        "|cff66bb6aFixed:|r Alarm glow colour updates the preview straight away",
        "|cff66bb6aFixed:|r Minimizing a sticky keeps its icon in place",
        "|cff66bb6aFixed:|r 'Dim screen behind ESC sticky notes' could not be turned back on",
        "|cff66bb6aFixed:|r Tag Manager: clicking an open tag closes it again",
        "|cff66bb6aFixed:|r Unsaved changes are saved on logout and /reload",
        "|cff66bb6aFixed:|r Lua error when dragging the Reference box Move/Copy window",
        "|cff66bb6aFixed:|r Reference box Clear and Delete task buttons: colour and spacing",
        { forever = true, "|cff66bb6aChange:|r A soft glow lifts panels off the wood background" },
        { forever = true, "|cff66bb6aChange:|r Setup wizard shows a Forever preview for Normal mode" },
        { forever = true, "|cff66bb6aChange:|r Darker stone background for Reference box tasks" },
        { forever = true, "|cff66bb6aFixed:|r Player notes use the full name, surname included" },
        { forever = true, "|cff66bb6aFixed:|r Quick Note button position on the inspect window" }
    },
}

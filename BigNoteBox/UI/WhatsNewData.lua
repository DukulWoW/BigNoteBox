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
    version = "1.12.0",
    entries = {
        { retail = true, "|cff66bb6aNew:|r Report a bug button beside the Settings window, with links to GitHub, CurseForge, Wago and WoWInterface" },
        { forever = true, "|cff66bb6aNew:|r Report a bug button next to the main window during the beta, with links to GitHub, CurseForge, Wago and WoWInterface" },
        "|cff66bb6aChange:|r New BigNoteBox logo and addon list icon",
        "|cff66bb6aChange:|r The version compare window now shows tasks alongside the note text, not just the body",
        "|cff66bb6aChange:|r The right-click menu now offers 'Create BNB Note' next to 'Open BNB Note' when a note already exists, so you can make a second note from it",
        "|cff66bb6aChange:|r A second note for the same NPC is now named 'Name (Duplicate)', the same as player notes, instead of 'Name (1)'",
        { forever = true, "|cff66bb6aChange:|r The Edit Task window now has the same background glow as the other windows" },
        "|cff66bb6aFixed:|r The Blizzard icon name field in Note Settings showed a box inside a box, and clicking near its edge did not select it or clear the hint text",
        "|cff66bb6aFixed:|r Icon suggestions in Note Settings stopped closing when you clicked away after switching notes",
        "|cff66bb6aFixed:|r The wowhead.com/icons link in Note Settings now opens a box to copy the address",
        "|cff66bb6aFixed:|r The Direct send name field in Share Note showed a box inside a box",
        "|cff66bb6aFixed:|r Notes created from a player or NPC (inspect, target, portrait menu) now write their text, tags and gear slot names in your game language instead of English",
        "|cff66bb6aFixed:|r Notes for NPCs showed a question-mark icon instead of the creature type icon on non-English clients",
        "|cff66bb6aFixed:|r Player notes for a character without a specialization said the class twice ('Rogue Rogue') and got the class tag twice",
        "|cff66bb6aFixed:|r Restoring an older note version did not bring back its tasks or rich text formatting",
        "|cff66bb6aFixed:|r Task changes did not show up in an open note after restoring an older version, until you reopened it",
        "|cff66bb6aFixed:|r The 'Compare' button when creating a manual restore point did nothing",
        "|cff66bb6aFixed:|r Right-clicking a player of the other faction had no 'Create BNB Note' option",
        "|cff66bb6aFixed:|r The right-click menu now shows 'Open BNB Note' for a player you already have an inspect note for",
        "|cff66bb6aFixed:|r In a new rich player note (from Inspect), the text cursor could sit in the wrong place below the Notes heading",
        "|cff66bb6aFixed:|r Inspecting a player you already have a note for now shows the 'note exists' window again, and automatic inspect notes no longer make a new duplicate note every time you inspect the same player",
        "|cff66bb6aFixed:|r In skin mode, the Note Task Defaults window was titled 'Edit Task'",
        "|cff66bb6aFixed:|r Adding a task could leave the Tasks pane blank, showing 'Tasks (0/1)' with no tasks and no way to add one until you reloaded, and empty tasks you never typed into piled up",
        "|cff66bb6aFixed:|r In skin mode, the divider lines in Sticky Note Settings now take the skin colour, like every other window",
    },
}

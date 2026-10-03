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
    version = "1.17.0",
    entries = {
        "|cff66bb6aNew:|r The note list's right-click menu is rebuilt: a shorter menu with icons and sub-menus that open on hover (Open, Create, Actions, History), with the note's icon and title colour at the top. The Tag Manager's note rows use it too",
        "|cff66bb6aNew:|r A situation note can show when you arrive, when you leave, or both (Situation tab > Trigger), and as often as you choose: every time, once per session, once per day, once per daily or weekly reset, or only once. Counted for each character",
        "|cff66bb6aNew:|r Right-click in Select mode for a menu that works on every selected note: open as sticky notes, pin, favorite or lock all, duplicate, move, convert, export as JSON, Markdown or HTML, create restore points, clear history, clear alarms, remove tasks or situations, move to trash or delete",
        "|cff66bb6aNew:|r Create or edit a note's situation straight from its right-click menu (Create > Create situation)",
        "|cff66bb6aNew:|r History in the right-click menu: create or replace the restore point, clear the auto snapshots, and Restore previous lists the restore point and the latest snapshots to compare and restore",
        "|cff66bb6aNew:|r Settings > Modules > Right-click menu: choose what a click on Open note, Create, Actions and History does, and how fast the sub-menus open, with a Try it button",
        "|cff66bb6aNew:|r Right-click an Oracle search result for the same note menu",
        "|cff66bb6aNew:|r Remove all tasks from a note with its right-click menu (Create > Remove all tasks)",
        "|cff66bb6aChange:|r Every right-click menu (Tag Manager, alarms, history, sidebar, stickies, Reference Box, tasks, Insert Info) now uses the new menu, and entries that cannot be undone are shown in red",
        "|cff66bb6aChange:|r Shift+click a note to start Select mode, and click anywhere outside the note list to leave it",
        "|cff66bb6aChange:|r Selected notes in Select mode have their own highlight",
        "|cff66bb6aChange:|r Rich notes switch between Markup and Note with labelled tabs under the editor, each with its icon beside the name",
        "|cff66bb6aFixed:|r The Settings tabs no longer run over the edges of the window",
        "|cff66bb6aFixed:|r The note list menu now says \"Close note settings\" while Note Settings is open for that note",
        "|cff66bb6aFixed:|r Override and Compare in the \"restore point already exists\" popup did nothing",
        "|cff66bb6aFixed:|r Opening a note from outside the note list (Oracle search, menus) now scrolls the list to it, opening the main window and clearing a list search that hides it",
        "|cff66bb6aFixed:|r \"When you leave the area: Minimize\" chosen in a sticky's settings did nothing. Notes already set that way are repaired",
        "|cff66bb6aFixed:|r Factory Reset and Clear migration flags in the Danger Zone were blocked from reloading the UI and left an error instead",
        "|cff66bb6aFixed:|r The Reference Box opened from Oracle search (Alt+Enter) did not close on ESC after the main window had opened it once",
        "|cff66bb6aFixed:|r The Tag Manager showed above the Danger Zone's red overlay",
        "|cff66bb6aFixed:|r Clicking a situation popup now opens its note, also when several notes popped up at once, when the main window had not been opened yet, or when the note list was filtered to another character",
    },
}

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
    version = "1.13.0",
    entries = {
        "|cff66bb6aNew:|r Right-click menus in Note History: Compare, Restore and Delete for each saved version. Restoring no longer has to go through the Compare window",
        "|cff66bb6aNew:|r Right-click menus in the History window: open a note's history, open the note, or clear that note's history",
        "|cff66bb6aNew:|r Right-click menus in the Tag Manager: rename, delete or show the notes of a tag. A note under a tag gets the usual note menu, plus Remove this tag",
        "|cff66bb6aNew:|r Right-click a sticky note (title bar, body, icon or minimized tile) for Open in editor, Settings, Alarm, Show tasks, Minimize or Restore, and Close",
        "|cff66bb6aChange:|r Settings have been restructured. Every feature now has its own row on the new Modules tab, with its on/off switch where it has one and a Settings button that opens a page with all of that feature's options. The Back button returns you to the list",
        "|cff66bb6aChange:|r Skin mode: the editor toolbar buttons now use skin buttons, including the rich note markup bar (H1, P, Col, Img and the rest, plus Live Preview) in both the editor and Focus mode",
        "|cff66bb6aChange:|r Skin mode: the Danger Zone buttons now follow your skin colour instead of always being red",
        "|cff66bb6aFixed:|r The Ascending/Descending sort direction dropdown could still be clicked in tag tree view, even though it does nothing there. It now greys out along with the sort dropdown",
        "|cff66bb6aFixed:|r Skin mode: every window now follows the Window opacity setting. Several (sticky note settings, alarm and task windows, Focus mode, the feature list, and the main window after leaving Focus mode) always kept a little transparency, even at 1.00",
        "|cff66bb6aFixed:|r Right-click menus now open at the mouse pointer. Several opened beside the row instead, some (tasks, attachments) past the edge of the window",
        "|cff66bb6aFixed:|r A right-click menu no longer stays open after its window is closed",
        "|cff66bb6aFixed:|r Skin mode: the Reference box's Model/Tasks switch is now the same icon side tabs normal mode uses, instead of the old text buttons underneath the window",
    },
}

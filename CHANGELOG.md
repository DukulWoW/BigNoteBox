# BigNoteBox v1.17.0

## All versions

### New
- The note list's right-click menu is rebuilt: a shorter menu with icons and sub-menus that open on hover (Open, Create, Actions, History), with the note's icon and title colour at the top. The Tag Manager's note rows use it too.
- A situation note can show when you arrive, when you leave, or both (Situation tab > Trigger), and as often as you choose: every time, once per session, once per day, once per daily or weekly reset, or only once. Counted for each character.
- Right-click in Select mode for a menu that works on every selected note: open as sticky notes, pin, favorite or lock all, duplicate, move, convert, export as JSON, Markdown or HTML, create restore points, clear history, clear alarms, remove tasks or situations, move to trash or delete.
- Create or edit a note's situation straight from its right-click menu (Create > Create situation).
- History in the right-click menu: create or replace the restore point, clear the auto snapshots, and Restore previous lists the restore point and the latest snapshots to compare and restore.
- Settings > Modules > Right-click menu: choose what a click on Open note, Create, Actions and History does, and how fast the sub-menus open, with a Try it button.
- Right-click an Oracle search result for the same note menu.
- Remove all tasks from a note with its right-click menu (Create > Remove all tasks).

### Change
- Every right-click menu (Tag Manager, alarms, history, sidebar, stickies, Reference Box, tasks, Insert Info) now uses the new menu, and entries that cannot be undone are shown in red.
- Shift+click a note to start Select mode, and click anywhere outside the note list to leave it.
- Selected notes in Select mode have their own highlight.
- Rich notes switch between Markup and Note with labelled tabs under the editor, each with its icon beside the name.

### Fixed
- The Settings tabs no longer run over the edges of the window.
- The note list menu now says "Close note settings" while Note Settings is open for that note.
- Override and Compare in the "restore point already exists" popup did nothing.
- Opening a note from outside the note list (Oracle search, menus) now scrolls the list to it, opening the main window and clearing a list search that hides it.
- "When you leave the area: Minimize" chosen in a sticky's settings did nothing. Notes already set that way are repaired.
- Factory Reset and Clear migration flags in the Danger Zone were blocked from reloading the UI and left an error instead.
- The Reference Box opened from Oracle search (Alt+Enter) did not close on ESC after the main window had opened it once.
- The Tag Manager showed above the Danger Zone's red overlay.
- Clicking a situation popup now opens its note, also when several notes popped up at once, when the main window had not been opened yet, or when the note list was filtered to another character.

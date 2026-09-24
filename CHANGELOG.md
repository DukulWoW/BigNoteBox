# BigNoteBox v1.11.1

## All versions

### Change
- Deleting two or more notes always asks first, even with "Warn before delete" turned off. The confirm names the notes and warns when you are about to delete every note you have
- Delete selected in the Trash window now asks before permanently deleting

### Fixed
- Select All in multi-select selected every note, not only the ones the list was showing, so a search or tag filter could hide notes that were about to be deleted
- In multi-select, a note you had just deselected still looked selected
- The Select button sometimes needed two clicks after a bulk delete, copy/move or export
- Deleting many notes at once no longer freezes the game for a few seconds
- "Delete permanently" in the note right-click menu moved the note to Trash instead of deleting it
- With Trash turned off in Settings, deleted notes were still kept in a hidden Trash
- Multi-select stayed on after closing the main window, entering Focus mode, or closing the Trash window, so its buttons were still there when you came back
- Duplicating a rich note made a normal note. Duplicate and Copy/Move now copy everything: rich mode, tasks, fonts, alignment, attachments and inspect data
- A copied note shared its tags with the original, so editing the tags of one changed both
- Turning Trash off left an empty gap in the main window toolbar, and the Trash icon came back after using multi-select

## Retail only

### Fixed
- The glow around the What's New, Feature List and Setup windows sat too far out on the left edge in normal mode

# BigNoteBox v1.11.0

## All versions

### New
- Notes now save automatically while you type, and open sticky notes update as you go. The Save button is hidden; turn "Save notes automatically" off in Settings > Editor to get it back and save by hand
- Double-click a sticky note to edit it right there. It saves when you press Escape or click outside the note, and can be turned off in the settings. Double-clicking a formatted note opens it in BigNoteBox, ready to type
- Notes about NPCs show the NPC's face in the note list and on sticky notes, even when the NPC is not targeted
- Notes about inspected players show the player's face while you have them targeted
- The Model and Tasks buttons under the Reference box are now icon tabs on its side: the character's race icon or the NPC's face for Model, a note for Tasks
- The model viewer shows a faint Horde or Alliance crest behind the character
- Sticky notes show a lock before the title on locked notes, and the situation and character markers on their icon, as in the note list
- Creating a note from a quest, gossip, book, the quest log or the inspect window now says "Note created" in chat, unless the note opens straight away

### Change
- Right-clicking the icon of an open sticky note now closes it, the same as on a minimized one
- Humanoid NPC notes without a portrait now use a neutral icon instead of a human face
- The Focus window now always opens in the centre of the screen, instead of over the main window
- The Quick Note button on quest, gossip, book, quest log and inspect windows now looks pressed when you click it

### Fixed
- Some chat messages, dialogs and close buttons showed a box where a dash, bullet or arrow should be
- The Insert bullet point button no longer takes keyboard focus from the note
- The Export buttons in the restore comparison window work again instead of showing a Lua error
- The note button on the inspect window no longer stays greyed out for some players
- The Show model viewer button now sits the same distance from the window edge as the Hide button
- Adding a task to an NPC or player note now switches the Reference box to the Tasks tab, so you see the new task
- "Open in BigNoteBox to edit" on a sticky note now puts the cursor in the note, so you can start typing right away
- Changing the glow colour in the alarm window now updates the preview straight away
- Minimizing a sticky note keeps its icon where it was, instead of moving it to the note's top-right corner
- "Dim screen behind ESC sticky notes" can be turned back on after it has been turned off
- Clicking an open tag in the Tag Manager closes it again
- Unsaved changes are now saved on logout and /reload
- Dragging the Move/Copy window in the Reference box no longer causes a Lua error
- The Clear and Delete task buttons in the Reference box use the same yellow text as other buttons, and Clear no longer sits against the window border

## WoW Forever only

### Change
- A soft glow behind the note list and in most windows lifts the panels off the wood background
- The setup wizard shows a Forever preview for Normal mode
- The task area in the Reference box has a darker stone background that sits better with the wood

### Fixed
- Notes about a player now use their full name, surname included
- The Quick Note button on the inspect window sits in the right place

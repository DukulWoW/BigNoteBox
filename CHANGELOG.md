# BigNoteBox v1.16.0

## All versions

### New
- Right-clicking the portrait of a player or NPC you have a note on now also offers "Open BNB Sticky Note".
- Reference Box: "Show model" shows gear, mounts and battle pets in the model viewer on any note, turning slowly; grab it to turn, move or zoom, and it starts turning again 3 seconds after you let go. Gear is framed on its slot: a helm on the head, shoulders on the shoulders; weapons, shields and off-hands are shown on their own. Drag up and down to tilt, Shift+wheel to move it nearer, and hover the bottom of the viewer for turn, reset and animation buttons.
- Reference Box: clicking an entry now works like a link in chat: click to view it (model viewer, or its item window), Shift+click to put it in chat, Ctrl+click for the dressing room.

### Change
- Send to Chat sends party, raid, guild, officer and whisper lines a moment apart, so the server no longer drops lines of long notes, and shows a live count. Closing the window stops it.
- Send to Chat to Say or Yell sends one message per click on Send, since the game only allows those from a click.
- Direct Send paces itself to the server's limit, shows its progress, and tells you in chat when the note went out or why it could not be sent (player offline, blocked in an instance).
- Typing in long notes is lighter: the word count, live preview and autosave wait for a pause in your typing instead of running on every key.
- The note list redraws only the note you are typing in, and only target notes when you change target, instead of the whole list.
- Note history now keeps the text, rich mode, tags and tasks of each version instead of a full copy of the note, so saved history takes far less space. Restoring a version leaves the note's icon, colours and font as they are now.
- Ticking a task or snoozing and dismissing an alarm no longer counts as editing the note, so it keeps its place in the "Edited" sort.
- Redrawn icon buttons (title bars, sticky headers, tasks, Reference Box, calendar), with a bronze edge on WoW Forever. In skin mode they now take the skin's colours, like every other skin button, instead of the stone look.
- Skin mode: the main window's title bar is now as tall as every other window's.
- Reference Box: item tooltips now open beside the window on the main window's side, with the "Equipped" comparison next to them, so they no longer cover the list.

### Fixed
- Direct Send with auto-reject on printed one chat line for every piece of an incoming note; now one per note.
- Situation waypoints were set again on every target change, taking the map tracking away from your quest.
- Player situations now match members of a 5-player party, not only a raid, and are checked when someone joins.
- Inspect notes for a party member you had not targeted were built from your target instead.
- The book button stayed greyed out for the rest of the session if the book was closed while it was reading the pages.
- Opening and closing sticky notes, ticking tasks and opening Settings used a little more memory every time, for the whole session.
- A zone change checked your note situations two or three times over.
- Hovering a sticky with high opacity snapped to full instead of fading; every hover fade now takes the same short time.
- Hiding a character from the sidebar now shows in Settings > Modules > Character sidebar's Hidden characters list at once.
- A sticky showing its tasks went blank when the last task was cleared or deleted; it now goes back to the note.
- The maximum number of open sticky notes now starts at 20, the same value its Reset button gives.
- Character sidebar on the left: small icons sat off-centre, and in normal mode the bar stood away from the main window.
- Skin mode: the Reference Box's Model and Tasks tabs could draw over the window's edge.
- The main window could jump toward the top of the screen as soon as you started dragging it.
- The main window sometimes opened in the middle of the screen at its default size instead of where you left it.
- Focus mode: the dark AFK screen now goes away when you move the mouse, as it was meant to.
- A situation alert that fired again while the previous one was fading out vanished straight away.

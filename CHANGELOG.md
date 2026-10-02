# BigNoteBox v1.15.0

## All versions

### New
- Ctrl+J brings all sticky notes to the front (Key Bindings > BigNoteBox > Bring Sticky Notes to Front).
- Esc or Ctrl+Enter finishes editing a sticky note (Enter still starts a new line).
- Settings > Notes > "Open Note Settings for new notes": untick it to create new notes without Note Settings popping up.
- Icon frames. Give a note's icon a frame made from game art (52 to pick from), chosen in a new picker window with All, Square, Circle and Edge borders tabs that previews your own icon. The frame shows everywhere the note's icon does: the note list, sticky notes, the Reference Box, search results and Trash.
- Default keys. F6 makes a note from your target, F7 a quick note, F8 a new note. They are only set where the action had no key and the key was free, so your own bindings stay as they are.
- The quick note key now opens the new note as a sticky note in the middle of the screen, ready to type in. Close it without typing and it is gone. Prefer the main window? Settings > Modules > Quick Note.
- Danger Zone > Reset Key Bindings puts every BigNoteBox key back to its default, without touching keys the game or other addons use.
- Choose how often an alarm's sound repeats until you answer it: once, or every 10 seconds, 30 seconds, minute or 5 minutes (alarm window, under Sound). Every 10 seconds is the default, as before.
- Pick what to share with checkboxes: tags, tasks, Reference Box, look, situation and unit data, in any mix. Title and text always go along. Your choice is remembered, and Send to player uses it too.
- Select several notes and press Export to get them as one JSON export, ready for Settings > Backup > Import.
- After a backup import, a line in chat says how many notes came in, how many were skipped and why, and how many had tasks, an alarm or Reference Box items.

### Change
- Sticky notes now act like windows: whichever you clicked last is in front, so the main window can cover them. Ctrl+J brings them all forward, and Settings > Modules > Sticky notes > "Keep sticky notes above BigNoteBox windows" keeps them on top as before.
- A single alarm missed while you were offline now shows just its popup; the Alarms overview opens only when several were missed.
- A quick note made with the Quick Note button or key in the main window is removed again if you leave it empty, the same as a quick sticky note.
- Reference Box items on a locked note keep their colour; the lock icon shows they cannot be removed.
- The alarm time can be typed: hour and minute are input fields (Tab or : moves between them) that still open a list from their arrow. Any minute can be set, not only steps of 5, a new alarm starts at the current time, and with a 12-hour clock (Appearance > Timestamp format) the hour runs 1-12 with an AM/PM field.
- Alarms glow steadily by default. Pick Pulse in the alarm window for 10 seconds on, 10 seconds off (until now Pulse looked steady because of a bug that restarted the glow).
- An alarm that goes off in combat posts one line in chat and glows on its note (also on an open or minimized sticky note); its sound and window follow when combat ends. The alarm, Note Settings and sticky settings windows are now as large as the Reference Box.
- Every slider now looks the same: name and default on top, the value beside it, and a Reset button next to the slider. Settings, sticky settings, Note Settings, alarms, the New Note window and the setup wizard all use it.
- A JSON backup now holds everything about a note: tasks, text size, icon frame, where it was made, player and NPC details, and the full alarm. Backups made with older versions still import.
- Share strings now start with BNB2: and carry tasks and sub-tasks. Older BNB1: strings still import. Players on an older version of BigNoteBox cannot read the new strings, or notes you send them directly, until they update.
- A shared note lands under the character you have selected in the sidebar, not under the sender's character, and never brings the sender's alarm, pin or lock.

### Fixed
- The reset filter button now lights up as soon as you type in the search box.
- A tab character in an imported or shared note showed as a box; it now becomes spaces.
- Importing a backup with another character's notes and choosing "Keep original" imported nothing.
- The zone and instance browser in Sticky settings opened behind the window and in the wrong place.
- The zone browser button in the task editor did nothing (it threw an error).
- "Reset to default" for a note's font size in Note Settings kept the size instead of going back to the global one, and switching notes with Note Settings open could save the sliders' values into the new note.
- The mouse wheel no longer changes sliders (in the setup wizard it still did); it scrolls the page.
- A ringing alarm now glows on the note's icon in the note list too, as it already did in the alarm overview.
- Moving a note to two or more characters at once only moved it to the first; the others now get a copy.
- Dragging an item into a note did nothing if you had not seen that item yet this session.
- Clearing the search box now also closes the tag suggestions under it.
- Picking the OLED skin preset now greys out the brightness and opacity sliders straight away.
- Shift-clicking a Reference Box item to send it to chat could also try to add it again and print "full" or "locked".
- The "Delete completed tasks" button showed the single-task tooltip "Delete task".
- Starting the setup wizard again now closes the share, alarm, history and preview windows.
- The minimap button's tooltip now shows how many notes match where you are; the line never appeared.
- Restoring a JSON backup lost every on/off setting of a note: pinned, favourite, locked, rich note, and an alarm's weekdays. Rich notes came back as plain text with the markup showing.
- A single note exported as JSON (right-click > Export note) could not be imported in Settings > Backup. It now can, and so can notes exported that way before this version.
- Character notes brought over from another notes addon only showed under "All". They now sit under their character, including notes you already moved over.
- The Reference Box could delete an item, spell or quest from a note when the game was slow to load it, or did not know it (a retired quest, an item from the other game client). It is now kept and shown as unavailable, and you decide whether to remove it.
- Importing or moving many notes at once could, rarely, overwrite one note with another.
- Restoring a note from History now updates its tags in the Tag Manager, and a saved version no longer changes when you tick a task afterwards.
- Delete All Notes in the Danger Zone now also closes open sticky notes and clears the old tags.
- With many notepad addons installed, the "move your notes over" window ran off the bottom of the screen and its buttons could not be reached. The list now scrolls.
- Alarm sounds other than Default never played when the alarm went off (only the Test button played them).
- Alarms set to an in-game (server) time never went off. They now ring at that time.
- A ringing alarm restarted itself every 10 seconds, so its glow animation started over each time and a sticky note alarm in combat printed a chat line every 10 seconds. It now rings once, and a sticky note alarm opens when combat ends.
- Alarms did not go off at all in Focus mode with "hide UI" on. They now ring and show their popup on top of Focus mode, and the AFK screen cover shows again.
- The "WoW weekly reset" alarm and the daily and weekly task resets used a fixed Tuesday 07:00. They now follow your region's real reset times.
- A daily, weekly or "every N days" task unticked itself within a minute the first time you ticked it.
- Moving an alarm that had already gone off to a new time did nothing until you pressed Reset in the alarm overview. Saving a new time now sets it again.
- When two alarms went off together, the first one lost its popup and could not be dismissed. They now take turns.
- With "Confirm before closing" on and the window set to hide in combat, entering combat brought the window straight back with a close confirmation. It now stays hidden until combat ends.
- With a BigNoteBox window open in combat, every key press caused an "action blocked" error and ability keys could stop working. In combat the windows now leave the keyboard to the game: your keys work as normal, and ESC does what the game does (closes the windows it knows, clears your target or opens the game menu). The Send to Chat window and the BigChatBox promo no longer hold on to keys you press while they are open.
- A JSON backup with an in-game time alarm caused an error after restoring it, and lost the alarm's after-combat setting. Backups made before this version restore correctly.
- Restoring a JSON backup lost every note's tasks, and a note whose text had a lone { or } could take the notes after it down with it.
- Shared notes lost their tasks and gear lists, and a waypoint name or tag with a comma in it came out cut in two.
- The Quick Note "confirm" window showed an empty title, or the title of the quick note before it.
- After a settings reset, the "move your notes over" window offered the same addon again, and accepting it copied all those notes a second time.
- Restoring a backup from the welcome page did nothing when the backup held notes for another character.
- Notes restored from a backup showed the time of the restore as their last edit.

## Retail only

### Fixed
- The instance browser in a note's Situation settings now shows the expansion name beside each dungeon and raid.

## WoW Forever only

### Fixed
- BigNoteBox no longer recognised WoW Forever after the October 1 client update, so windows lost their Forever spacing, glows and art and looked cramped.

# BigNoteBox v1.19.0

## All versions

### New
- Settings > Modules > Character Sidebar: "Tabs fill the window width" makes the character tabs on top of the main window share its whole width (on by default).
- Lock a sticky note in place: Lock in Sticky settings > General or in the sticky's right-click menu keeps its position and size, and everything else still works.
- Insert image has "Keep ratio": the height follows the width.
- Settings > Notes: "Reset all" beside "Lock notes by default" makes every note follow that setting again.
- Remove a character you no longer have: Settings > Modules > Character sidebar now lists every character (note count, "not seen for N days" after 90 days) with Hide / Show and Remove, also in the character's right-click menu. Its notes move to another character or Global first.
- Settings > Notes: "New notes belong to" picks where new notes go: the selected tab (as before), Global, or the character you are playing.
- The New note window has a character dropdown beside the title, so a note can go straight to any of your characters.
- Settings > Modules > Sticky Notes: turn off the Create task, Set alarm, Open in BigNoteBox and Sticky settings buttons that show when you hover a sticky. The right-click menu still has them all.
- Choose which side of the main window Note History, Trash, Alarms, the Tag Manager and the rich preview open on (Settings > Modules on each one's page; the Tag Manager under Settings > Notes).
- Settings > Modules > Window placement: reset the main window's placement and/or size every time you log in or reload.
- A situation's waypoint can be placed without taking over your map arrow: tick "Don't track it" under the waypoint on the Situation tab.
- Share > Send Directly shows how many messages a note takes before you send it; a note too large to send greys out Send.
- Receiving a large note by Direct Send now says so in chat while it arrives.
- A note can hold several waypoints: the Situation tab lists them under the spot where the note was made (Name, Zone, X, Y). Green ones are placed when the situation matches, grey ones are kept for Navigate; click a row to switch, double-click its name to rename it, its zone to move it to another zone or its X, Y to change the coordinates (not on the spot where the note was made), hover for Navigate and Remove, or right-click for all of these. The list shows with or without a situation.
- Right-click a situation on the Situation tab to edit or remove it.
- Settings > Modules > Window placement: every window placement setting in one page (main window resets on login, which side Note History, Trash, Alarms, the Tag Manager, the rich preview and the Reference Box open on, the situation popup position and the search bar position). Each one is still on its own page as well.
- Focus mode has the formatting toolbar's writing tools (undo, redo, font, size, bullet, timestamp); turn it off in Settings > Notes > Formatting Toolbar.
- Right-click in the Focus mode editor for the note's menu, with Close Focus Mode at the bottom.
- Shift+Left-click the minimap button to hide or show your sticky notes, Shift+Right-click to open Settings (the addon compartment too).
- Ctrl+Enter in a task adds a sub-task, as Shift+Enter adds a new task.
- Search field in the Reference Box Move / Copy window.
- Send to Chat is in the note's right-click menu (Actions), no BigChatBox needed.
- Dismiss an alarm that has gone off from the Alarm overview (button and right-click). Repeating alarms move on to their next time.
- The Welcome panel's Import takes shared note codes as well as JSON backups.
- /bnb whatsnew and /bnb features.
- Quick notes get the tag Quick Note, and player notes get the player's guild as a tag.
- Trash, Note History, the Tag Manager and Alarms look alike: rows as in Note History, buttons at the bottom, and a Select mode with Select all in each.
- Trash rows show how long a note has been in the trash and its size; click one to view it, with Restore and Delete on its page. A trashed rich note opens as it looks, with a Markup / Note button to see its source.
- Note History has a Select mode: clear the history of several notes at once.
- Restore button on each snapshot in Note History, between Compare and Delete.
- Tag Manager: select tags and add them to the notes you pick (with a search).
- Alarms: Clear all Alarms, and every alarm shows when it fires (date and time), what kind it is and how it repeats.
- Settings > Modules > Character sidebar: sort the character icons Newest first, By name, By class or By notes (most notes first). Pinned characters stay in front.
- Notes about Alliance or Horde players show a faint faction crest at the right of their row in the note list.

### Change
- The note list headers read "Pinned (N)" and "Notes (N)" in gold with a line running to the right, and the line between pinned and other notes is gone.
- Editing a waypoint on the Situation tab opens Name, X and Y boxes together: Tab moves between them, Enter or a click outside saves, Esc cancels. X and Y take a decimal comma too.
- Colour grids mark the colour in use; a colour of your own marks the colour picker tile.
- Settings > Modules is in alphabetical order. The Icons row is gone: switch all game icons on or off with the "All game icons" box in the icon picker.
- Sticky settings > General opens with four buttons, Minimal Sticky, ESC Pin, Rich / Normal Note and Lock, each showing what a click will do. Focus mode for stickies is now called Minimal sticky.
- Insert icon and Insert image: the size boxes have a list of common sizes (12 to 128) and still take any size you type, up to 256 for icons and 1024 for images.
- Stickies, Rich preview and the labs use the main window's resize grip.
- Note History and Trash no longer open a second window: a note's history and a trashed note's View open inside the same window, with a back arrow (ESC goes back too). Trash View has Delete beside Restore.
- Note Settings > General opens with four buttons, Pin, Favorite, Lock and Rich Note, each showing what a click will do.
- Note Settings no longer has a separate Lock section; use the Lock / Unlock button at the top.
- New colour palette: 23 named colours in every colour grid.
- The note editor's title shows the note's title colour.
- In Focus mode the Save button follows the save mode, and automatic mode saves as you type there too.
- The "Hide sticky notes" button is greyed while there is nothing to hide.
- In "Edited" sort the list follows the note you type in.
- Skin mode: the editor's divider lines take the skin colour.
- The character sidebar's Change icon now opens the same icon picker as Note Settings, with search and every icon category.
- The Report a bug window follows skin mode.
- Copy / Move no longer offers characters hidden from the sidebar, and adds the realm when two characters share a name.
- Note Settings no longer has a Note visibility section; use Copy/Move to character in the note's right-click menu, and the editor toolbar's Copy/Move button, now there with the sidebar off too.
- The New note window is a little wider, so the font previews have more room.
- Note History, Trash, Alarms and the Tag Manager open on the right of the main window, all the same width and as tall as the main window.
- Setup wizard: the language choice sits right above Get started.
- Setup wizard: pick your skin theme right on the style page; the reload happens when you click Next.
- A rich note's Note view shows only the title and the note: the formatting toolbar and the created / edited line come back in Markup view.
- Sticky right-click menu: Minimize sticky, Restore sticky, Close sticky, Sticky Note Settings (it opens the sticky's settings) and Open in BNB to Edit.
- Settings > Modules has four new pages: Rich Notes (with Live Preview), Note History, Trash and Alarms. Their settings moved there from the Notes and General tabs; Trash can be switched on and off from its row.
- Completed tasks sit under a small "Done (N)" title and a divider in the Reference Box.
- Drag an open sticky note by its icon, as you already could a minimized one.
- The Tag Manager button is greyed until a note has a tag, like Trash.
- Trash rows are more see-through and show each note's title colour.
- JSON is the default format in Settings > Backup > Export Notes.
- The setup wizard's last page has Wago.io, CurseForge and WoWInterface buttons, and Dukul.net Homepage.
- The resize grip lights up BNB green on hover.
- The New note window's "Sample size" is now "Font preview"; the Icon Frame picker's "Edge borders" tab is now "Shared borders".
- Wowhead links follow your client (Forever, Classic and so on), in the Reference Box and HTML exports.
- The collapsed note list is a little wider and shows square selection, hover and multi-select art around the icons.
- The location browser on the Situation tab uses the standard close button (the skin one in skin mode).
- Every window's close button (normal mode) uses the addon's own close button instead of the game's.
- The waypoint support window (the ? beside Waypoints on the Situation tab) has full-width link buttons, the addon's own close and ? icons, greys the link for an addon you already have, and the ? goes away when you have both TomTom and WaypointUI.
- Clicking outside the manual waypoint row closes it when nothing was typed.
- Note Settings > General uses the full window width (no scroll area).
- Note Settings > Situation has the same side margins as the other tabs.
- Every colour grid (sticky text and background, note title colour, New note, the Oracle's custom style) ends with a colour picker button in its last slot, replacing the separate "Click to pick color" box and the Custom color / Reset buttons.
- In skin mode, stickies you have not recoloured use the skin colour for their background, header and border, kept dark, and follow it when you change the skin.
- Sticky background opacity now defaults to 90% (was 96%); stickies still at 96% move to 90%.
- Skin brightness now defaults to 1.50.
- Simplified Chinese: the translation is complete again, every new text included.

### Fixed
- The Show checkboxes under Settings > Modules > Oracle search > Results could not be switched off.
- Picking an instance from the zone browser while the situation type said Zone saved it as a zone, so the note never showed there. The type now follows the tab you pick from (Situation tab and task editor).
- Setup wizard: the normal and skin mode pictures were squashed.
- Settings > Modules > Sticky Notes showed the alarm page's description.
- Rich notes: text after a closed {p} on the same line, or in a {p} never closed, made the whole note disappear.
- Making a link from selected text deleted the text instead of linking it.
- Tab and Shift+Tab move between the Insert Link fields.
- A locked plain note now shows the lock cursor like a locked rich note.
- Closing a Direct Send prompt with its X (normal mode) stopped later incoming notes from prompting until a reload.
- Col, Lnk, Ico and Img did nothing in Focus mode (their windows opened behind it, or hidden with "hide UI").
- Closing Focus mode and then the main window quickly with ESC left the live preview open on its own.
- Migrate Now (bringing notes over from another notes add-on) was blocked from reloading the UI; it now finishes with a "Reload Now" popup.
- The Settings window opened behind the live preview.
- A situation's waypoint kept the note's old title after the note was renamed; it now follows the title, also on the map right away.
- Danger Zone > Factory Reset no longer gives a Lua error and a blocked reload: it wipes everything, then asks you to reload.
- The character tabs on top of the main window show their tooltip below the tabs when the window is near the top of the screen.
- "Use WoW's default font" now shows in the New note window's font preview.
- The formatting toolbar's History button closes the History window again on a second click.
- Copy / Move opens with its top-left corner at the pointer, and also opens with the Character sidebar off.
- Sticky Note Settings on a minimized sticky restores it and opens its settings.
- The Alarm overview showed the BigNoteBox logo for a note using the default icon.
- The Reference Box showed a scrollbar with nothing to scroll.
- Danger Zone's confirm countdown was half hidden under the scrollbar.
- Settings > Backup > Data Summary updates at once after an import or delete.
- A damaged JSON backup is refused with the line where it breaks, instead of importing only part of it.
- Deleting the last snapshot of a note in Note History goes back to the list.
- Note History and the Alarms window show a note's icon frame.
- The Situation tab recognizes WaypointUI.
- The tabs in Note Settings and Sticky settings no longer overflow the window border in skin mode.

## Retail only

### Change
- Main window resize grip sits closer into the corner (normal look).

## WoW Forever only

### Change
- The character tabs on top of the main window (normal look) are wider, share the whole width, and tuck under the window's top border.
- The insert image / link / icon dialogs, Copy/Move, Send to Chat, Send to Chat confirm, Direct Send prompt, Trash, BigChatBox and Import from other addons windows get the Forever window glow.
- Main window resize grip sits closer into the corner, in normal and skin mode.

### Fixed
- The top character tabs no longer split their art after the window's position is reset.

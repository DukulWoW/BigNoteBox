# BigNoteBox v1.23.0

## All versions

### New
- The top bar's Send button opens a note search: type a name, pick the note with the mouse or the arrow keys, and it goes straight to the Send to Chat window, no need to open it first.
- Oracle prefix "m" sends the note you pick to the Send to Chat window.
- After an update, the patch notes no longer open a window over the screen: they come as a pinned, favourite note (tagged Bnb and the version number) and a toast that waits for your click. The next update replaces that note, unless you edited it or removed its Bnb tag. The What's New window is still on the version button in Settings > General.
- Settings > Modules > Toasts: "Messages from BigNoteBox" turns the update and welcome toasts off (the notes are still made).
- A fresh install starts with a welcome note from Dukul, pinned at the top, with a toast pointing to it.
- Settings > General: buttons under More Features copy the link to BigNoteBox on GitHub, CurseForge, Wago and WoWInterface.
- tl;dr notes: give a note one short line (up to 80 characters) at the top of Note Settings > Situation, typed or picked from a list of snippets (KOS, Friendly, Avoid, Vendor / trader and more). It shows under the note title, in the game tooltip of the player or NPC the note is about, on the note icon at the Target and Focus frames, and on the note's situation toast. Settings > Modules > tl;dr turns it on or off, chooses where it shows and edits the snippet list.
- Hovering a note in the note list shows a small box with its tl;dr, next alarm, situations and waypoints; hovering the note icon on the Target or Focus frame shows the same box. Settings > Modules > tl;dr, "Note details when hovering the note list" turns the list box off.
- Toast styles in a picker: on Settings > Modules > Toasts and in a note's Toast window, click the style name to see every style as a real toast, two side by side (the name shows on hover). Click one to use it, double-click to use it and close, Revert to go back; the arrows beside the name step through them. "Follow my faction" / "As in Settings" sits in the picker too. A note's picker shows that note's own toast.
- Situations can be on or off: on the Situation tab a green situation is on, a grey one is kept on the note but never shows. Click one to switch it, double-click to edit it.
- Every new player or NPC note gets a situation for that player or NPC, off unless you choose otherwise: Settings > Modules > Situations has "Turn on the player situation" and "Turn on the NPC situation", each with "Show the note as a toast" under it. So a KOS note is: make the note, pick KOS as its tl;dr, done.
- Note Settings > Situation, Show as: "Show nothing". The situation still marks the note and places its waypoints, but no toast or sticky pops up.

### Change
- Toasts that pop up together (at login, entering a zone) now come in one after another and leave one at a time, oldest first, instead of all at once.
- Toasts waiting for room show as a small "+N" box after the last toast, counting down as they come in. A toast's list (tasks, grouped situations) is a box of its own, dark like a sticky note, or in your skin's colours in skin mode.
- BigNoteBox's code is now licensed under the GNU GPL v3 (it was MIT). The logo and icon are All Rights Reserved; the rest of the art is Blizzard's. See LICENSE and LICENSE-ASSETS.
- Suggestion lists take the arrow keys: Up / Down pick a row, Enter or Tab takes it, Esc closes the list (Situations add row, waypoint sub-zone, note list "#" tags, Send directly names).
- Note Settings > Situations > Waypoints: clicking "(Addon required)" or the ? now opens Settings > Advanced > Addon integrations instead of a separate popup.
- The collapsed note list shows a note's title when you hover it.
- Toasts show in the upper left instead of the middle of the screen. A toast position you placed yourself stays where it is.
- Settings > Advanced > Addon integrations lists DialogueUI and Immersion too, with what BigNoteBox does with each (Immersion is not listed on TBC Anniversary, which it has no version for).

### Fixed
- Alarm window: the day boxes under Repeat name the full day when you hover them ("Ring on Monday").
- Toasts growing Left or Right: a toast with a list (tasks, grouped situations) no longer sits higher than the others; its list is now a box of its own beside it.
- Rich notes in the main window no longer cut off the end of each line when opened (it only went away after resizing the window).
- A toast for a player note now shows the player's face while you have them targeted, as the note list does (it showed the plain note icon). Its right-click menu and alarm toasts too.

## WoW Forever only

### Change
- The language selector is back in the setup wizard and Settings > General: a forced language now stays through reloads.

## Classic only

### Change
- Reference Box side tabs sit under the window edge.
- Addon integrations no longer lists WaypointUI and MapPinEnhanced, which have no Classic version.
- The icon picker has no "All game icons" list on Classic: almost none of those icons exist there, so Classic uses the curated icons.

### Fixed
- Three icon frames that do not exist on Classic (Golden Hunter, Solar Flare, Corner Ornament) are no longer offered there.
- Note Settings > Situations > Waypoints: without a waypoint addon, the red install hint no longer runs out of the window (the line is gone; "(Addon required)" says it).

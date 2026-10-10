# BigNoteBox v1.22.0

## All versions

### New
- Alarms: set the defaults for new alarms (snooze time, glow type, glow mode, glow colour) in Settings > Modules > Alarms. Alarms set to "Default" follow them.
- Alarm popup: alarms waiting their turn show as bars under the popup. Click one to show it now.
- Before an import or a migration, BigNoteBox offers to save a backup of the notes you already have.
- Rich notes: /way lines (as TomTom and Wowhead write them, "/way Zone 45.2 60.1" or "/way #84 45.2 60.1") are clickable links. Click to place the waypoint (TomTom, or the game's map pin), Shift+click to see it on the world map.
- Situations > Waypoints: "Show on map" in a waypoint's right-click menu, or Shift+click the row, opens the world map with a marker on the spot.
- Situations: the player name box suggests your friends (Battle.net friends too), your guild and your group, in class colours.
- Rich notes: broken formatting tags (a {p} never closed, a {/p} closing a heading, a close tag with nothing open) show as "Markup: N to fix" next to the word count, with the details on hover. They are fixed in the text when you open another note or close the window; Note History keeps the text from before.
- Settings > Advanced > Addon integrations: a page of its own with one section per addon (BigChatBox, TomTom, WaypointUI), with its logo, what it does and whether it is active, and the tab shows how many you have. An addon you do not have has a button that copies its CurseForge link.
- Reference Box: add mounts and battle pets straight from the Collections journals (drag them in or Shift+click), with their model.

### Change
- Set alarm: "Every N days" has < > buttons to change the number.
- Situations: Add with nothing typed adds where you are now (zone, sub-zone, instance) or your target (player, NPC, guild).
- Danger Zone: the confirm button says how much it changes, like "Delete all 312 notes".
- Copy boxes from link buttons show the start of the link you are copying.
- Skin mode: text buttons look pressed while held (the label moves down a pixel).
- Sticky notes: the border has its own opacity slider (Appearance), so the background opacity no longer fades the border.
- Sticky notes: the scrollbar shows only while the pointer is over the note.
- Sticky notes: the window border is picked from a thumbnail grid with < > arrows, as the background is. Note Settings' icon frame row has the < > arrows too.
- Skin mode: slider tracks are see-through (70%) instead of solid black.
- Skin mode: the OLED preset's softer white also reaches sticky note text that still has its default colour.
- Changing the note font updates skin-mode button labels and the welcome screen at once, without a reload.
- NPC notes show the creature's portrait again (switched off in v1.21.1 while a crash was tracked down).
- The toast position anchor is now exactly the size of a toast: a see-through box in normal mode, the skin's colours in skin mode.
- Esc closes the window in front first: Settings or Trash opened over Note History now close before it.
- The note list collapses on its own when the main window is made narrower than 530, and comes back when you widen it again.
- Settings > General: BCB Integration moved to Advanced > Addon integrations; a smaller More Features button sits beside Language.
- Settings tooltips: what a checkbox does when on and when off is shown as two paragraphs, with On: and Off: in green (or the skin colour).

### Fixed
- Import: pressing Esc on the "notes for another character" question now cancels the import instead of importing.
- Skin mode: the font cards in Note Settings and sticky note settings use the skin's colours instead of the old green.
- Target notes: a note imported from a file is found again when you make a note of the same NPC (it asks first instead of making a silent "(Duplicate)"), and a repeated press for the same target makes one note.
- Mount stands (one NPC ID shared by several invisible mounts, like the Orgrimmar Trading Post): each stand gets its own note, and the Reference Box shows its mount instead of an empty viewer.

## Retail only

### New
- MapPinEnhanced support (version 4.0 and newer): situation waypoints go to MapPinEnhanced as named pins in a BigNoteBox group, several at once, "Don't track it" is respected, and they are removed again when you leave. Navigate, Show on map and the coordinate button use it too. Settings > Advanced > Addon integrations has a MapPinEnhanced section, which says "Needs update" for older versions.

## WoW Forever only

### Change
- Skin mode: the beta notice is drawn in the skin's look.
- Skin mode uses the plain action bar icons, as on Retail (the detailed Forever icons stay in normal mode).

## Classic only

### Change
- Skin mode: the beta notice is drawn in the skin's look.

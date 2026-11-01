# BigNoteBox v2.0.0

## All versions

### New

#### Explorer view

- Explorer view: your notes as a grid of icons over the whole window, like a file explorer, with its own toolbar, multi-select, drag and drop, and a status bar. Turn it on or off in Settings > Modules > Explorer view.
- Explorer view: Small, Medium and Large tiles, List, Details (sortable columns) and Flat, in the View menu.
- Explorer view: View menu options to put pinned notes first without sections, or favorites first.
- Explorer view: New folder with selection, and Remember the open note (Settings > Modules > Explorer view)
- Explorer view: with the Reference Box's auto-open on, clicking a note opens its Reference Box when it has attachments or tasks.

#### Folders

- Folders: sort your notes into folders, with a color each, in the note list and the explorer. Folders come along in backups. Settings > Modules > Folders.

#### Help book and patch notes

- The help book: every help topic in one book, with chapters, a search and a Glossary. Open it with the new Help button on the top bar or /bnb help.
- Right-click a button on the formatting or rich toolbar to open its help topic.
- The help book has a Features tab (what BigNoteBox can do, A-Z), which replaces the old Features window.
- Patch notes: every release back to v1.6.9 in the help book's Patch notes tab. After an update a toast opens the new release there, and no pinned patch note is added to your note list any more.

#### Spelling and text shortcuts

- Spelling: red wavy lines under misspelled words, English (US) or English (UK), as you type or with the Check spelling button. Settings > Modules > Spelling.
- Spelling: right-click a marked word for suggestions, Add to dictionary or Ignore, and a Correct spelling window that goes through them one by one.
- Spelling: repeated words (the the) are marked, with options to ignore UPPERCASE words and words with numbers.
- Spelling works in Focus mode and sticky notes too.
- Key bindings: Check spelling (F9) and Correct spelling (F10)
- Text shortcuts: type brb and it becomes "be right back". Make your own in Settings > Modules > Spelling, with an "Only with !" option.

#### Writing notes

- Find and replace in a note: Ctrl+F or the new button on the formatting toolbar, in the editor and Focus mode.
- Rich notes: underline and strikethrough, two new buttons on the rich toolbar.
- Rich notes: dividers, a new button on the rich toolbar.
- Rich notes: {code}...{/code} shows text exactly as typed, tags and all.
- Links to BigNoteBox itself: the link button's new BigNoteBox tab links a note to a Settings page or window.
- An open note has two new buttons: Note settings on the formatting toolbar, and Situation on the action bar.
- Note right-click menu: Favorite, Pin, Lock, Rename and Delete are a row of icons at the bottom. Rename is new.
- Sort menus: Reset sort, and Make this the default.

#### Note Capture, player and NPC notes

- Note Capture: quest, book and dialogue notes can be rich notes, one setting per kind in Settings > Modules > Note Capture.
- Note Capture: quest notes show when you accepted or turned in the quest, its level and kind, a Wowhead address and a waypoint link.
- Note Capture: the NPC's name in a quest or dialogue note links to that NPC's own note.
- Note Capture: captured notes get the zone as a tag, and optionally the subzone.
- What an NPC says now goes into that NPC's own note instead of a note of its own.
- Dialogue UI: a BigNoteBox button beside its Copy Text button.
- Player and NPC notes made from a target or inspect get dividers between their sections.
- NPC notes are round like player notes, with an Elite or Rare frame (Retail and Forever)

#### Other languages in notes

- Notes with Korean, Chinese, Japanese, Cyrillic or Greek text use a font that can show them, and get a language shield on the title row and tooltip.

#### Accessibility

- Settings > Modules > Accessibility: a new page, starting with Motion settings for the sticky note animation.
- Smooth scrolling everywhere. Turn it off or change its speed under Accessibility > Motion.

### Change

#### Look and windows

- BigNoteBox has a new icon and is listed under Notes & Organization in the game's AddOns list.
- BigNoteBox windows and sticky notes come to the front when clicked, like normal windows.
- The main window and toasts get better default positions and sizes on ultrawide screens.
- Search boxes have a round X to clear them.
- Hiding and showing sticky notes is animated.
- The minimap button's situation count is a big green number in the middle of the icon.
- Setup wizard: two fewer questions on the Notes & behavior page.

#### Notes and editing

- Focus mode: a status bar at the bottom, more room for the note, and a two-row toolbar with the font picker.
- Player notes have a round icon, matching the live portrait shown while that player is targeted.
- The note list's sort now sorts your pinned notes too.
- Collapsing the note list clears the search and filters.
- Export from a note's right-click menu goes straight to the copy popup.
- Deleting several notes at once leaves locked notes alone.
- Importing a backup: a settings profile with a name you already have can replace yours or be added as a copy.

#### Reference Box and Note Capture

- Reference Box: the model viewer says "Loading..." while an NPC model loads.
- Immersion: the Note Capture button sits on the corner of Immersion's text box, so it no longer covers the text.

#### Translation

- Simplified Chinese: everything new in 2.0 is translated.

### Fixed

- Sticky notes: text color, font, size, outline, shadow and alignment changes show again.
- Changing the font in Settings no longer resets every open sticky's own font.
- Sticky notes: the Line height setting works.
- Note Settings: font changes on a rich note show at once.
- The rich note preview wraps its text when you resize it.
- Tasks: the row's buttons no longer cover the task you are editing.
- Settings no longer goes blank after Focus mode.
- Search bar: the tag suggestions have a background.
- Settings profiles: pressing Enter in the name and Import boxes works.
- OLED Flat skin: grayed-out toolbar buttons are visible again.

## Retail only

### Fixed

- A crash to desktop when an NPC note's model was loading in the Reference Box.

## WoW Forever only

### Change

- Ready for the WoW: Forever launch: the beta notice is gone, and Report a bug sits beside the Settings window.

## Classic only

### Fixed

- Cursors that were wrong or drew as a black square.

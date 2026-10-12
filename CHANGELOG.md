# BigNoteBox v1.24.0

## All versions

### New
- Item, spell and quest links in rich notes can be clicked as in chat: click shows the item card, Shift+click puts the link in chat, Ctrl+click opens the dressing room.
- Hover an item, spell or quest link in a plain note to see its tooltip.
- Shift+click an item while typing in a note to put its link in the text.
- An item, spell, quest or pet you drop or Shift+click into a note is also added to its Reference Box (Settings > Reference Box, on by default).
- A Reference Box button in the editor toolbar lists the note's Reference Box entries: click one to put it into the text at the cursor. Alt+click an entry in the Reference Box does the same.
- Mounts and your own battle pets dropped into a note are links too.
- Gear in inspect notes is made of item links: hover for the tooltip of the item as worn. Older notes get them with "Update gear and note" on the next inspect.
- Skin mode: a new OLED Flat skin, pure black with no borders or divider lines.
- Player notes say where you met the player, and both player and NPC notes get a /way line to the spot (a clickable link in rich notes).

### Change
- Skin mode: the Markup and Note tabs under a rich note follow the skin brightness, and their icon and label are centred.
- Skin mode: the selected tab in Settings shows its name in the skin's heading colour, so it reads well on every skin.
- Undo and Redo remember each note's history for the whole session, also after switching notes, using Focus mode or editing the note as a sticky.
- On a narrow main window the editor toolbar hides its right-hand buttons, then the font and size pickers, instead of drawing them over each other.

### Fixed
- The rich note icon beside a note's title shows its tooltip again, instead of a click on it opening the title for editing.
- An item dropped on the empty part of a note, below the text, is added at the end instead of being lost.
- Reference Box > Insert at text cursor now counts as a change to the note and can be undone.
- The green edit glow on a sticky note sometimes did not show until you scrolled or moved the cursor.

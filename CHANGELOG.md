# BigNoteBox v1.28.0

## All versions

### New
- Left-aligned paragraphs in rich notes: {p:l}...{/p}, with its own toolbar button next to the plain paragraph one.
- Note tokens: write {{me}}, {{class}}, {{spec}}, {{ilvl}}, {{guild}} or {{here}} in a note and it shows the reader's own name, class, item level and so on (in rich notes, stickies, toasts, the tl;dr and Send to Chat). Type {{date}}, {{time}}, {{zone}}, {{target}} or {{coords}} and it turns into today's date, the zone you are in, a waypoint link to where you stand and so on as you type (Ctrl+Z brings the token back).
- Note tokens for game data: {{item:6948}} shows the item's icon and link, {{quest:id}} and {{achievement:id}} a tick once done (a red cross until then), {{currency:id}} how much you have, {{rep:id}} your standing, {{mount:id}} and {{pet:id}} whether you have them, {{spell:id}} the spell. A new toolbar button lists every token: hover one to see what it does and what it gives right now, click to put it in the note.
- Note tokens for money, resets and lockouts: {{gold}} shows your money with its coins, {{reset:weekly}} and {{reset:daily}} count down to the reset, {{lockout:name}} shows the bosses you have killed in that dungeon or raid on each difficulty (or "not saved"), {{lockouts}} every lockout you have. Tokens now update by themselves while the note is open: level up, change zone, loot money, turn in a quest, kill a boss, and the note follows.
- Note templates: the New Note window has template cards (Blank, Boss strategy, Weekly checklist, Journal) and a More page with ten more (Dungeon route, Daily checklist, Farming route, Collection hunt, Crafting shopping list, Player / applicant, Guide / quest chain, Alt status, IOU, Raid night). The IOU template keeps track of what you owe and what others owe you, gold, items or reagents, ticked off when settled. A template fills in the title, icon, colour, text, tags and task list; checklists untick themselves at the daily or weekly reset, and Boss and Dungeon notes pop up in the instance you made them in.
- Your own note templates: right-click a note > Actions > Save as template, pick what goes with it (tags, tasks, Reference Box, look, situation), and it shows at the top of the New Note window's More page. Settings > Notes > Templates renames, duplicates, replaces or deletes them; duplicate a built-in for a copy you can change. Right-click a template on the More page for the same choices, and Share gives a code anyone can paste in Import shared note to get the template. Your templates are in the JSON backup too.
- Your own note tokens: Settings > Notes > Note tokens makes {{raidtime}} stand for any line of text, which can use other tokens too ("Wed and Sun 20:00, {{me}} brings {{item:6948}}"). They fill wherever note tokens do, are listed under My tokens on the token button, and go into the JSON backup.
- Type {{ in a note and a list of tokens opens right under the cursor: keep typing to narrow it, Up / Down to pick, Enter or Tab to put it in. Works in the editor, Focus mode, sticky editing and the tl;dr boxes.
- Tags for one note: right-click a note > Add tags / Edit tags opens a small window to add tags (several at once with commas), remove them, or tick them from a list of every tag you use. Right-click a tag under the note for Filter, Rename on this note, Remove, Colour and Edit tags.
- Tag colours: give a tag one of twelve colours from its right-click menu (on a note, in the tag window or in the Tag Manager). Its chips are tinted on every note, and the tag tree, the Tag Manager and the tag suggestions show it too. Tags named after a class or a faction (Priest, Shaman, Horde, Alliance...) start in the game's colour for it.
- Links in notes (spells, quests, tokens) and Reference Box entries show a pointing cursor while you hover them, items in notes and in the Reference Box an inspect cursor, links to other notes a trainer cursor, web links a map pin cursor, and waypoint links and waypoint rows a directions cursor (Retail and WoW Forever).

### Change
- The tl;dr line now sits above the note title, bigger and easier to read, with a button at its end: click it to add or edit the tl;dr right there (Enter saves, Esc cancels, the arrow has your snippets).
- The rich note toolbar has icons in place of the H1 / Pc / Col text buttons, at the same height as the formatting toolbar, and Live Preview is an icon too that shows whether the preview is open.
- The formatting toolbar keeps its note actions (restore, history, alarm, copy / move, share, map) in an overflow menu when the window is too narrow for them, and the icons and dividers have more room.
- On a narrow main window the line under the title drops the coordinates, shortens the dates and then the counts instead of running into itself.

### Fixed
- Tags that differ only in case are one tag again: "warcraft" joins an existing "WarCraft" whichever way it was added (templates, imports, player notes), and existing look-alikes are merged into one. New tags keep the rest of their capitals ("WoW Forever").
- "Created 1 weeks ago" now reads "1 week ago" (month and year too)
- Undo after a toolbar insert (bullet, timestamp, Reference Box entry, waypoint or note link) takes away only the insert, not the words you typed just before it.

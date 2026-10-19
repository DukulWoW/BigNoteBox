-- BigNoteBox_Dev/DocsSeed.lua - the first help topics for doc mode (ALL-512)
--
-- Written by Claude on 2026-10-19 for Dukul to edit in doc mode. The first
-- doc-mode load (BigNoteBoxDevDB.docsDB still nil) makes one note per entry,
-- in this order (Core/Database.lua BNB.SeedDocsFromFeatureList); after that
-- the notes in doc mode are the text, and this file is not read again.
-- _work/tools/docs-build.lua turns doc mode's notes into UI/HelpData.lua.
-- Titles become the topic keys on the first build ("Note list" -> note-list),
-- and the links below name those keys (help.<key>): until the first build they
-- draw grey in doc mode. rich = false: a plain note (the Rich notes topic shows
-- its tags as text). {link*bnbui:<key>*} with no text shows the place's real
-- name (Features/UILinks.lua). Never shipped (the dev addon is not packaged).

BigNoteBoxDevDocsSeed = {

{ title = "Getting started", body = [[
{p}BigNoteBox is a notepad inside the game. Your notes are kept for your whole account, and each one belongs to every character (Global) or to one character.{/p}
{h3}Open it{/h3}
- Type /bnb, press Ctrl+N, or click the minimap button.
- F8 makes a new note, F7 a quick note: {link*bnbui:help.quick-notes*Quick notes}.
- Ctrl+Space opens {link*bnbui:help.oracle-search*Oracle search} from anywhere.
{h3}Write{/h3}
{p}Pick a note on the left, write on the right: {link*bnbui:help.writing-notes*Writing notes}.{/p}
{h3}Choose what you use{/h3}
{p}Most parts of BigNoteBox are modules you can switch on or off: {link*bnbui:help.modules*Modules}. The {link*bnbui:wizard*setup wizard} sets them up for you.{/p}
]] },

{ title = "Note list", body = [[
{p}The list on the left of the main window, from top to bottom:{/p}
- Pinned: the notes you pinned (right-click > Pin to top).
- Your folders: {link*bnbui:help.folders*Folders}.
- Notes: everything else, in the sort you picked.
- Patch notes and Help: folders from BigNoteBox itself.
{h3}Find a note{/h3}
- The search box finds text in titles and notes as you type.
- The star and task buttons show only favourites, or notes with tasks.
- The folder view and tag tree buttons, left of the search box, group notes by folder or by tag.
{h3}Do things{/h3}
- Right-click a note for everything you can do with it.
- Hold a note and drag it: to reorder (Custom sort), or onto a folder.
- The arrow at the top folds the list to icons only.
{p}Character tabs beside the list show one character's notes at a time: {link*bnbui:settings.modules.sidebar*}.{/p}
]] },

{ title = "Folders", body = [[
{p}Folders keep notes together. They sit between Pinned and your notes, A-Z, and remember whether you left them open.{/p}
{h3}Put notes in a folder{/h3}
- Right-click a note > Move to folder, then a folder or New folder...
- Drag a note onto a folder header. Drop it on the Notes header to take it out again.
- Actions > Copy / Move to... can copy or move notes into a folder too.
{h3}The folder itself{/h3}
{p}Right-click a folder header to add a note to it, rename it, give it a colour or delete it. Deleting a folder never deletes its notes: they go back under Notes. A pinned note shows under Pinned and in its folder.{/p}
{p}Settings: {link*bnbui:settings.modules.folders*}.{/p}
]] },

{ title = "Tags", body = [[
{p}Tags are short words on a note, like Raid or Gold. A note can have as many as you like, and a tag is the same whatever its case.{/p}
- Right-click a note > Add tags, or add them under the title in the editor.
- Click a tag to show only the notes that have it.
- The tag tree button groups every note by tag.
- The {link*bnbui:tagmanager*} renames, colours and deletes tags across all your notes.
]] },

{ title = "Writing notes", body = [[
{p}The editor is the right side of the main window: the title on top, the text below.{/p}
- Notes save as you type. A setting can switch this to a Save button.
- Undo and Redo work per note: {link*bnbui:help.history-and-undo*History and undo}.
- A locked note cannot be changed: right-click > Lock note / Unlock note.
- The toolbar above the text inserts waypoints, links, time stamps and more.
- Right-click > Open note settings: the note's look, icon and situation.
{p}For headings, colours and pictures, make it a {link*bnbui:help.rich-notes*rich note}.{/p}
]] },

{ title = "Rich notes", rich = false, body = [[
A rich note is a small page: headings, colours, icons, pictures and links. The toolbar inserts every tag for you, and the preview beside the editor shows the result as you type.

Right-click a note > Convert to rich or normal note.

The tags:
- {h1}Title{/h1}, {h2}...{/h2}, {h3}...{/h3}: headings. {h1:c} centres one, {h1:r} puts it on the right.
- {p}text{/p}: a paragraph. {p:c} centred, {p:r} on the right.
- {col:ff8800}text{/col}: coloured text.
- {icon:INV_Misc_Note_01:16}: a game icon in the text, 16 pixels.
- {atlas:name:32} or {atlas:name:32:64}: game art by its atlas name, 32 high (and 64 wide). :c or :r at the end centres it or puts it on the right.
- {img:path:width:height}: a picture.
- {link*address*text}: a link. {link*bnbui:oracle*{icon:INV_Misc_Spyglass_03:16}} is a picture button that opens the Oracle bar.
- {br}: a new line inside a paragraph.

With the Rich Notes module off, every note shows as plain text with its tags visible, like this one (Settings > Modules > Rich Notes).
]] },

{ title = "Links in notes", body = [[
{p}The link button on the editor toolbar puts a link at the cursor. Right-click any link for more choices.{/p}
{h3}Note links{/h3}
{p}A link to another note. It keeps working when that note is renamed. If the note is deleted, the link turns grey; Shift-click it to bring the note back from the Trash.{/p}
{h3}Waypoint links{/h3}
- Click: place the waypoint and track it.
- Shift-click: put the map pin into chat.
- Ctrl-click: copy a /way line.
- Alt-click: show it on the map.
{p}In a rich note, a typed /way line becomes a link by itself.{/p}
{h3}BigNoteBox links{/h3}
{p}The link button's BigNoteBox tab links to a Settings page, a window or a help topic, like this one: {link*bnbui:settings.modules.situations*}. A rich note can make one a picture button: {link*bnbui:oracle*{icon:INV_Misc_Spyglass_03:20}} (see {link*bnbui:help.rich-notes*Rich notes}).{/p}
]] },

{ title = "Sticky notes", body = [[
{p}A sticky note is a note pinned to your screen as a small window, so it stays up while you play.{/p}
- Right-click a note > Open as sticky note.
- Drag it to move it, drag an edge or a corner to resize it.
- Each sticky has its own font, size, colour, background and border.
- A rich note shows as a rich page on its sticky.
- A note with tasks can show its tasks instead of its text.
- Ctrl+H shows or hides every sticky, Ctrl+J brings them to the front.
- Stickies come back where you left them after a reload.
{p}Settings: {link*bnbui:settings.modules.stickies*}.{/p}
]] },

{ title = "Situations", body = [[
{p}A situation makes a note show up by itself where it matters: a {link*bnbui:help.toasts*toast} shows the note, or it opens as a sticky note.{/p}
{h3}What can match{/h3}
- A zone, a sub-zone or an instance.
- An instance type: dungeon, raid, delve or battleground.
- A player, an NPC or a guild.
- A window: vendor, bank, mailbox, auction house or trainer.
- Being rested, in an inn or a city.
{h3}Set one{/h3}
{p}Right-click a note > Create situation, or Note Settings > Situation. With nothing typed, Add uses where you are now or your target. Then pick when it shows (when it starts, when it ends, or both) and how often (every time, once a session, once a day, once per reset, or only once). A situation can also place waypoints.{/p}
{p}Settings: {link*bnbui:settings.modules.situations*}.{/p}
]] },

{ title = "Toasts", body = [[
{p}Toasts are small pop-ups on your screen: when a note's situation matches, when tasks reset, after an update.{/p}
- Click a toast to open its note.
- You choose which kinds show, where they appear, how they look and how long they stay.
{p}Switched off, nothing pops up, but notes still match where they are set: {link*bnbui:settings.modules.toasts*}.{/p}
]] },

{ title = "Tasks", body = [[
{p}Tasks are a checklist inside a note, with sub-tasks.{/p}
- Right-click a note > Create task, or add them in the task panel beside the note.
- Tick a task when it is done; drag tasks to reorder them.
- Tasks can untick themselves at the daily or weekly reset, the whole list or one task at a time: good for dailies and weekly chores.
- A sticky note can show the note's tasks, and you can tick them there.
- The task button above the list shows only notes with tasks.
{p}Settings: {link*bnbui:settings.modules.tasks*}.{/p}
]] },

{ title = "Alarms", body = [[
{p}An alarm on a note rings at a time you pick: a real-world time, an in-game time, or the daily or weekly reset. It can ring once or repeat on the days you choose.{/p}
- Right-click a note > Create alarm.
- When it rings, the note pops up with a sound. Snooze it or dismiss it.
{p}Settings, and the window that lists every alarm: {link*bnbui:settings.modules.alarms*}.{/p}
]] },

{ title = "Reference Box", body = [[
{p}The Reference Box is a panel beside the editor for the items, spells, quests and links you attach to a note.{/p}
- Drag an item or a spell onto it, or Shift-click a link while it is open.
- Hover an entry for its tooltip.
- Notes about a player keep their gear here, with a model viewer to look at it.
{p}Settings: {link*bnbui:settings.modules.refBox*}.{/p}
]] },

{ title = "Oracle search", body = [[
{p}A search bar that finds any note from anywhere in the game, by title, text or tags. Open it with Ctrl+Space or /bnb search.{/p}
{h3}Open a note{/h3}
- Enter: open it.
- Shift: as a sticky note. Ctrl: in Focus mode. Alt: in the Reference Box.
{h3}Narrow it down{/h3}
{p}Type a letter and a space before your words. Type ? in the bar to see them all.{/p}
- p player notes, n NPC notes, i notes with an item, z notes tied to a zone.
- c this character, g global, t tasks, a alarms, x rich, l plain.
- d today, d week, d month: made or edited then.
- b searches the Trash, o searches the settings, m sends a note to chat.
- #tag, @who the note is about, * favourites, -word leaves a word out, "an exact phrase".
{p}Settings: {link*bnbui:settings.modules.oracle*}.{/p}
]] },

{ title = "Player and NPC notes", body = [[
{p}Make a note about a player or an NPC, with their details filled in.{/p}
- A player: from the Inspect window, or their right-click menu.
- An NPC: target it and press F6 (Create Note from Target).
- The note gets their portrait and details, and for a player their gear in the {link*bnbui:help.reference-box*Reference Box}.
- Give the note a tl;dr, one short line like KOS: it shows in the game tooltip when you hover them.
{p}Settings: {link*bnbui:settings.modules.unitNotes*} and {link*bnbui:settings.modules.tldr*}.{/p}
]] },

{ title = "Quick notes", body = [[
{p}Ways to make a note in a hurry.{/p}
- F7 makes a new note at once, in the main window or as a sticky note to type in.
- Quest, gossip, book and letter windows get a note button: one click makes a note of what they say.
- Dialogue UI and Immersion get the same button.
{p}Settings: {link*bnbui:settings.modules.quickNote*}.{/p}
]] },

{ title = "Focus mode", body = [[
{p}Write in full screen, with the game interface hidden and the camera slowly turning around your character.{/p}
- Open it from the editor toolbar, or with Ctrl+Enter in the Oracle bar.
- A rich note gets its preview beside the text.
- Esc or the close button brings everything back as it was.
{p}Settings: {link*bnbui:settings.modules.focus*}.{/p}
]] },

{ title = "History and undo", body = [[
{p}BigNoteBox keeps earlier versions of your notes.{/p}
- History: a version of each note is saved when you log out or reload. Compare two versions side by side and bring an old one back (right-click > History).
- Restore point: save one by hand before a big change.
- Undo: steps per note, and they can be kept between sessions.
- Rescue: a note that went missing without being deleted can be brought back from its history.
{p}History and kept undo need the BigNoteBox_History addon, which comes with BigNoteBox. Settings: {link*bnbui:settings.modules.history*} and {link*bnbui:settings.modules.undo*}.{/p}
]] },

{ title = "Trash", body = [[
{p}A deleted note goes to the Trash first, for 30 days unless you change it, so you can get it back.{/p}
- Open the {link*bnbui:trash*} to restore a note or delete it for good.
- Notes older than the days you set are removed by themselves.
- The Oracle's b prefix searches the Trash.
{p}Switched off, deleting a note is permanent: {link*bnbui:settings.modules.trash*}.{/p}
]] },

{ title = "Backup and import", body = [[
{p}{link*bnbui:settings.backup*} keeps your notes safe outside the game.{/p}
- Full backup: everything as JSON: your notes, templates, note tokens, tag colours and every settings profile.
- Settings backup: every settings profile, without notes.
- Selective backup: pick the format and what goes in. Markdown is for reading outside WoW.
{p}Copy the text and keep it in a file. To bring it back, paste it into Import on the same page. Import also takes shared notes, template codes and profile codes.{/p}
{p}Notes from other note addons can be moved over from {link*bnbui:settings.advanced*}.{/p}
]] },

{ title = "Sharing notes", body = [[
{p}Right-click a note > Share note.{/p}
- Pick what goes with it: tags, tasks, Reference Box, look, situation, player or NPC data.
- Send it straight to another player who has BigNoteBox, or copy a share code they paste into Import.
- Send to Chat posts the note's text in a chat channel, line by line.
]] },

{ title = "Settings profiles", body = [[
{p}A profile is a set of settings and window layout. Each character picks one; your notes are the same in every profile.{/p}
- Make a new profile as a copy of the current one, or from scratch.
- Export a profile as a code to share or keep; Import one from a code.
- Picking another profile reloads the UI.
{p}Settings: {link*bnbui:settings.advanced*}.{/p}
]] },

{ title = "Modules", body = [[
{p}Most parts of BigNoteBox are modules you can switch on or off in {link*bnbui:settings.modules*}. Switching one off hides it everywhere. Your notes keep everything that belongs to it, so switching it back on brings it all back.{/p}
{p}Minimal, Full and Custom at the top of that page switch many at once. The {link*bnbui:wizard*setup wizard} asks the same on your first login.{/p}
]] },

{ title = "Keys and commands", body = [[
{h3}Keys{/h3}
- Ctrl+N: open or close BigNoteBox.
- F8: new note. F7: quick note. F6: note from your target.
- Ctrl+Space: Oracle search.
- Ctrl+H: show or hide every sticky. Ctrl+J: bring stickies to the front.
{p}A key the game or another addon already uses is left alone. Change them in {link*bnbui:settings.general*}.{/p}
{h3}Commands{/h3}
- /bnb: open or close the window.
- /bnb new: a new note.
- /bnb search text: Oracle search.
- /bnb config: Settings.
- /bnb whatsnew: the latest patch notes.
]] },

}

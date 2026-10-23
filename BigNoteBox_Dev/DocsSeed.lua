-- BigNoteBox_Dev/DocsSeed.lua - the first help topics for doc mode (ALL-512)
--
-- Written by Claude on 2026-10-19 for Dukul to edit in doc mode. The first
-- doc-mode load (BigNoteBoxDevDB.docsDB still nil) makes one note per entry,
-- in this order (Core/Database.lua BNB.SeedDocsFromFeatureList); after that
-- the notes in doc mode are the text, and this file is not read again.
-- _work/tools/docs-build.lua turns doc mode's notes into UI/HelpData.lua.
-- Titles become the topic keys on the first build ("Note list" -> note-list),
-- and the links below name those keys (help.<key>): until the first build they
-- draw gray in doc mode. rich = false: a plain note (the Rich notes topic shows
-- its tags as text). {link*bnbui:<key>*} with no text shows the place's real
-- name (Features/UILinks.lua). Never shipped (the dev addon is not packaged).
--
-- Round 3 (2026-10-23, Dukul: "add icons/images ... to show what the
-- different options look like"): {icon:@Folder/name:16} is a picture from
-- BigNoteBox's Assets folder inside the text, the same art as the button it
-- names; {icon:@Documentation/doc-info:16} / doc-help / doc-important start
-- a tip, a pointer or a warning. Help topics only (Features/AdvancedMode.lua
-- AM.ExpandAssetImages).

BigNoteBoxDevDocsSeed = {

{ title = "Getting started", rev = 3, body = [[
{p}BigNoteBox is a notepad inside the game. Your notes are kept for your whole account, and each one belongs to every character (Global) or to one character.{/p}
{h3}Open it{/h3}
- Type /bnb, press Ctrl+N, or click the minimap button {icon:@icon:16}.
- F8 makes a new note, F7 a quick note: {link*bnbui:help.quick-notes*Quick notes}.
- Ctrl+Space opens {link*bnbui:help.oracle-search*Oracle search} from anywhere.
{h3}Find your notes{/h3}
{p}The main window shows your notes in one of two ways, and the icon at the top left switches between them:{/p}
- {icon:@Explorer/ex-explorer-mode:16} The {link*bnbui:help.explorer-view*Explorer view}: your notes and folders as a grid of icons over the whole window, like the file explorer on your computer.
- {icon:@Explorer/ex-list-mode:16} The {link*bnbui:help.note-list*Note list}: a list on the left, the open note on the right.
{h3}Write{/h3}
{p}Open a note and write: {link*bnbui:help.writing-notes*Writing notes}. A new note can start from a {link*bnbui:help.note-templates*template}.{/p}
{h3}Choose what you use{/h3}
{p}Most parts of BigNoteBox are modules you can switch on or off: {link*bnbui:help.modules*Modules}. The {link*bnbui:wizard*setup wizard} sets them up for you.{/p}
{p}{icon:@Documentation/doc-info:16} Right-click almost anything for more choices: a note, a folder, a link, empty space.{/p}
]] },

{ title = "Note list", rev = 3, body = [[
{p}The list on the left of the main window, beside the open note. The icon {icon:@Explorer/ex-explorer-mode:16} left of the sort dropdown switches to the {link*bnbui:help.explorer-view*Explorer view}. From top to bottom:{/p}
- {icon:@ContextMenu/Symbols/cm-pinned:16} Pinned: the notes you pinned (right-click > Pin to top).
- {icon:@ContextMenu/Symbols/cm-folder:16} Your folders: {link*bnbui:help.folders*Folders}.
- Notes: everything else, in the sort you picked.
- Patch notes and Help: folders from BigNoteBox itself.
{h3}Find a note{/h3}
- {icon:@Explorer/ex-search:16} The search box finds text in titles and notes as you type.
- {icon:@UI/ui-favorite:16} The star and {icon:@UI/ui-tasks:16} task buttons show only favorites, or notes with tasks.
- {icon:@UI/ui-folder:16} The folder view and {icon:@UI/ui-treeview:16} tag tree buttons, left of the search box, group notes by folder or by tag.
{h3}Do things{/h3}
- Right-click a note for everything you can do with it.
- Hold a note and drag it: to reorder (Custom sort), or onto a folder.
- The arrow at the top folds the list to icons only.
{p}Character tabs beside the list show one character's notes at a time: {link*bnbui:settings.modules.sidebar*}.{/p}
]] },

{ title = "Explorer view", rev = 3, body = [[
{p}The Explorer view shows your notes and folders as a grid of icons over the whole main window, the way the file explorer on your computer shows files. The icon at the top left switches between it {icon:@Explorer/ex-explorer-mode:16} and the {link*bnbui:help.note-list*Note list} {icon:@Explorer/ex-list-mode:16}.{/p}
{h3}Open and go back{/h3}
- Double-click a note or a folder to open it.
- The arrow at the top left, or Esc, takes you back. Next to it is where you are: click Notes there to go back to the top.
- {icon:@Explorer/ex-chevron-down:16} Pinned and Notes are headers you can fold away.
{h3}Pick notes{/h3}
- Click a note to pick it. Ctrl+click picks more, Shift+click picks a row of them, or drag a box around several.
- The bar at the bottom counts your notes and folders, and what you picked.
{h3}The buttons along the top{/h3}
- {icon:@Explorer/ex-new:16} New: a note {icon:@Explorer/ex-new-note:16} in the open folder, or a new folder {icon:@Explorer/ex-new-folder:16}.
- {icon:@Explorer/ex-copy:16} Copy, {icon:@Explorer/ex-move:16} Move, {icon:@Explorer/ex-delete:16} Delete, {icon:@Explorer/ex-rename:16} Rename, {icon:@Explorer/ex-pin:16} Pin, {icon:@Explorer/ex-favorite:16} Favorite, {icon:@Explorer/ex-share:16} Share and {icon:@Explorer/ex-export:16} Export work on the notes you picked.
- {icon:@Explorer/ex-sort:16} Sort and Order: how the notes are sorted.
- {icon:@Explorer/ex-view:16} View: small {icon:@Explorer/ex-view-small:16}, medium {icon:@Explorer/ex-view-medium:16} or large {icon:@Explorer/ex-view-large:16} icons, a list of titles {icon:@Explorer/ex-view-list:16}, details in columns {icon:@Explorer/ex-view-details:16}, or every note in one flat list {icon:@Explorer/ex-view-flat:16}.
- {icon:@Explorer/ex-search:16} The search button opens a search field; the buttons at its end show only favorites or notes with tasks.
- {icon:@Explorer/ex-more:16} In a small window, the buttons that do not fit go under More.
{h3}Drag and right-click{/h3}
- Drag notes onto a folder to file them. Drop them on Notes in the path to take them out again.
- {icon:@Explorer/ex-sort-custom:16} In Custom sort, drag the icons into the order you like.
- Right-click a note, a folder or empty space for everything else. Empty space has Sort by, New folder and the View choices, among them Pinned notes first and Favorites first.
{h3}Inside a note{/h3}
{p}The note fills the window. The Note settings button {icon:@Toolbar/tb-notesettings:16} at the right end of the toolbar opens Note settings, with the note's look and situations; right-clicking the text has Open note settings at the bottom. The icon beside the title changes the note's icon.{/p}
{p}Settings: {link*bnbui:settings.modules.explorer*}. There you pick which view the window opens on, and whether it opens on the note you had open when you closed it.{/p}
]] },

{ title = "Folders", rev = 3, body = [[
{p}Folders keep notes together. They sit between Pinned and your notes, A-Z, and remember whether you left them open.{/p}
{h3}Put notes in a folder{/h3}
- {icon:@ContextMenu/Symbols/cm-folder:16} Right-click a note > Move to folder, then a folder or {icon:@ContextMenu/Symbols/cm-folder-add:16} New folder...
- Drag a note onto a folder header. Drop it on the Notes header to take it out again.
- {icon:@ContextMenu/Symbols/cm-copy-move:16} Actions > Copy / Move to... can copy or move notes into a folder too.
- {icon:@Explorer/ex-new-folder:16} In the {link*bnbui:help.explorer-view*Explorer view}, drag notes onto a folder icon, or pick some and right-click empty space > New folder with selection.
{h3}The folder itself{/h3}
{p}Right-click a folder to add a note to it, rename it, give it a color or delete it. A pinned note shows under Pinned and in its folder.{/p}
{p}{icon:@Documentation/doc-info:16} Deleting a folder never deletes its notes: they go back under Notes.{/p}
{p}Settings: {link*bnbui:settings.modules.folders*}.{/p}
]] },

{ title = "Tags", rev = 3, body = [[
{p}Tags are short words on a note, like Raid or Gold. A note can have as many as you like, and a tag is the same whatever its case.{/p}
- {icon:@ContextMenu/Symbols/cm-tags-add:16} Right-click a note > Add tags, or add them under the title in the editor.
- Click a tag to show only the notes that have it.
- {icon:@UI/ui-treeview:16} The tag tree button groups every note by tag.
- {icon:@Topbar/Normal/tp-tagmanager-normal:16} The {link*bnbui:tagmanager*} renames, colors and deletes tags across all your notes.
]] },

{ title = "Writing notes", rev = 3, body = [[
{p}The editor shows the open note: the title on top, the text below. In the Note list it is the right side of the window; in the Explorer view the note fills the window.{/p}
- Notes save as you type. A setting can switch this to a Save button.
- {icon:@Toolbar/tb-undo:16} Undo and {icon:@Toolbar/tb-redo:16} Redo work per note: {link*bnbui:help.history-and-undo*History and undo}.
- {icon:@ContextMenu/Symbols/cm-locked:16} A locked note cannot be changed: right-click > Lock note / Unlock note.
- The toolbar above the text inserts waypoints {icon:@Toolbar/tb-way:16}, links {icon:@Toolbar/tb-link:16}, time stamps {icon:@Toolbar/tb-timestamp:16} and {link*bnbui:help.note-tokens*note tokens} {icon:@Toolbar/tb-syntax:16}.
- {icon:@Toolbar/tb-notesettings:16} The Note settings button at the right end of the toolbar opens Note settings: the note's look, icon and situation.
- Right-click the text to insert game info; Open note settings is at the bottom.
{p}{icon:@ContextMenu/Symbols/cm-rich-note:16} For headings, colors and pictures, make it a {link*bnbui:help.rich-notes*rich note}.{/p}
]] },

{ title = "Note templates", rev = 3, body = [[
{p}A template fills a new note for you: a title, text, tags and a look to start from.{/p}
{p:c}{icon:@Templates/tmp-blank:40} {icon:@Templates/tmp-boss:40} {icon:@Templates/tmp-weekly:40} {icon:@Templates/tmp-diary:40} {icon:@Templates/tmp-more:40}{/p}
- The New Note window has Blank, Boss, Weekly and Journal at the top. More shows every template.
- {icon:@ContextMenu/Symbols/cm-save-template:16} To make your own, right-click a note > Actions > Save as template.
- {icon:@ContextMenu/Symbols/cm-share:16} A template can be shared as a code, like a note.
{p}Rename, change or delete your templates, or copy a built-in one, in {link*bnbui:settings.notes.templates*}.{/p}
]] },

{ title = "Rich notes", rich = false, body = [[
A rich note is a small page: headings, colors, icons, pictures and links. The toolbar inserts every tag for you, and the preview beside the editor shows the result as you type.

Right-click a note > Convert to rich or normal note.

The tags:
- {h1}Title{/h1}, {h2}...{/h2}, {h3}...{/h3}: headings. {h1:c} centers one, {h1:r} puts it on the right.
- {p}text{/p}: a paragraph. {p:c} centerd, {p:r} on the right.
- {col:ff8800}text{/col}: colored text.
- {icon:INV_Misc_Note_01:16}: a game icon in the text, 16 pixels.
- {atlas:name:32} or {atlas:name:32:64}: game art by its atlas name, 32 high (and 64 wide). :c or :r at the end centers it or puts it on the right.
- {img:path:width:height}: a picture.
- {link*address*text}: a link. {link*bnbui:oracle*{icon:INV_Misc_Spyglass_03:16}} is a picture button that opens the Oracle bar.
- {br}: a new line inside a paragraph.

With the Rich Notes module off, every note shows as plain text with its tags visible, like this one (Settings > Modules > Rich Notes).
]] },

{ title = "Note tokens", rev = 2, rich = false, body = [[
A note token is a word in double braces that BigNoteBox fills in for you. Type {{ in a note to see the list, or use the token button on the toolbar.

Here and now, filled in once when you finish typing it:
- {{date}}, {{time}}, {{datetime}}: today's date and the time.
- {{zone}}, {{subzone}}, {{instance}}: where you are.
- {{target}}: your target's name. {{coords}}: where you stand, as a waypoint link.

Your character: {{me}}, {{name}}, {{realm}}, {{class}}, {{race}}, {{level}}, {{spec}}, {{ilvl}}, {{guild}}, {{gold}} and more. In a rich note these stay in the note and show the character of whoever reads it; in a normal note they become the value right away.

Game data by id: {{item:6948}} and the like show the link. The id is the number in the thing's Wowhead address.

Make tokens of your own in Settings > Notes > Tokens.
]] },

{ title = "Links in notes", rev = 3, body = [[
{p}The link button {icon:@Toolbar/tb-link:16} on the editor toolbar puts a link at the cursor. Right-click any link for more choices.{/p}
{h3}Note links{/h3}
{p}A link to another note. It keeps working when that note is renamed. If the note is deleted, the link turns gray; Shift-click it to bring the note back from the Trash.{/p}
{h3}Waypoint links{/h3}
{p}{icon:@Toolbar/tb-way:16} A place on the map.{/p}
- Click: place the waypoint and track it.
- Shift-click: put the map pin into chat.
- Ctrl-click: copy a /way line.
- Alt-click: show it on the map.
{p}In a rich note, a typed /way line becomes a link by itself.{/p}
{h3}BigNoteBox links{/h3}
{p}The link button's BigNoteBox tab links to a Settings page, a window or a help topic, like this one: {link*bnbui:settings.modules.situations*}. A rich note can make one a picture button: {link*bnbui:oracle*{icon:INV_Misc_Spyglass_03:20}} (see {link*bnbui:help.rich-notes*Rich notes}).{/p}
]] },

{ title = "Sticky notes", rev = 3, body = [[
{p}A sticky note is a note pinned to your screen as a small window, so it stays up while you play.{/p}
- {icon:@ContextMenu/Symbols/cm-sticky-note:16} Right-click a note > Open as sticky note.
- Drag it to move it, drag an edge or a corner to resize it.
- Each sticky has its own font, size, color, background and border.
- A rich note shows as a rich page on its sticky.
- {icon:@UI/ui-tasks:16} A note with tasks can show its tasks instead of its text.
- Stickies come back where you left them after a reload.
{p}{icon:@Documentation/doc-info:16} Ctrl+H shows or hides every sticky, Ctrl+J brings them to the front.{/p}
{p}Settings: {link*bnbui:settings.modules.stickies*}.{/p}
]] },

{ title = "Situations", rev = 3, body = [[
{p}{icon:@UI/ui-situation:16} A situation makes a note show up by itself where it matters: a {link*bnbui:help.toasts*toast} shows the note, or it opens as a sticky note.{/p}
{h3}What can match{/h3}
- A zone, a sub-zone or an instance.
- An instance type: dungeon, raid, delve or battleground.
- A player, an NPC or a guild.
- A window: vendor, bank, mailbox, auction house or trainer.
- Being rested, in an inn or a city.
{h3}Set one{/h3}
{p}{icon:@ContextMenu/Symbols/cm-create-situation:16} Right-click a note > Create situation, or Note Settings > Situation. With nothing typed, Add uses where you are now or your target. Then pick when it shows (when it starts, when it ends, or both) and how often {icon:@UI/ui-repeat:16} (every time, once a session, once a day, once per reset, or only once). A situation can also place waypoints.{/p}
{p}Settings: {link*bnbui:settings.modules.situations*}.{/p}
]] },

{ title = "Toasts", rev = 3, body = [[
{p}Toasts are small pop-ups on your screen: when a note's situation matches, when tasks reset, after an update.{/p}
- Click a toast to open its note.
- You choose which kinds show, where they appear, how they look and how long they stay.
{p}{icon:@Documentation/doc-info:16} Switched off, nothing pops up, but notes still match where they are set: {link*bnbui:settings.modules.toasts*}.{/p}
]] },

{ title = "Tasks", rev = 3, body = [[
{p}{icon:@UI/ui-tasks:16} Tasks are a checklist inside a note, with sub-tasks.{/p}
- {icon:@ContextMenu/Symbols/cm-create-task:16} Right-click a note > Create task, or add them in the task panel beside the note.
- Tick a task when it is done; drag tasks to reorder them.
- {icon:@UI/ui-reset:16} Tasks can untick themselves at the daily or weekly reset, the whole list or one task at a time: good for dailies and weekly chores.
- A sticky note can show the note's tasks, and you can tick them there.
- {icon:@UI/ui-tasks:16} The task button above the list shows only notes with tasks.
{p}Settings: {link*bnbui:settings.modules.tasks*}.{/p}
]] },

{ title = "Alarms", rev = 3, body = [[
{p}An alarm on a note rings at a time you pick: a real-world time, an in-game time, or the daily or weekly reset. It can ring once or repeat on the days you choose.{/p}
- {icon:@ContextMenu/Symbols/cm-create-alarm:16} Right-click a note > Create alarm, or use the alarm button {icon:@Toolbar/tb-alarm:16} on the toolbar.
- When it rings, the note pops up with a sound. Snooze it or dismiss it.
- {icon:@Topbar/Normal/tp-alarms-normal:16} The alarm button at the top of the main window lists every alarm.
{p}Settings: {link*bnbui:settings.modules.alarms*}.{/p}
]] },

{ title = "Reference Box", rev = 3, body = [[
{p}{icon:@ContextMenu/Symbols/cm-reference-box:16} The Reference Box is a panel beside the editor for the items, spells, quests and links you attach to a note.{/p}
- Drag an item or a spell onto it, or Shift-click a link while it is open.
- Hover an entry for its tooltip.
- {icon:@Toolbar/tb-refbox:16} The toolbar's Reference Box button puts an entry into the text.
- {icon:@ContextMenu/Symbols/cm-model-view:16} Notes about a player keep their gear here, with a model viewer to look at it.
{p}Settings: {link*bnbui:settings.modules.refBox*}.{/p}
]] },

{ title = "Oracle search", rev = 3, body = [[
{p}A search bar that finds any note from anywhere in the game, by title, text or tags. Open it with Ctrl+Space or /bnb search.{/p}
{h3}Open a note{/h3}
- Enter: open it.
- Shift: as a sticky note {icon:@ContextMenu/Symbols/cm-sticky-note:16}. Ctrl: in Focus mode {icon:@ContextMenu/Symbols/cm-focus-mode:16}. Alt: in the Reference Box {icon:@ContextMenu/Symbols/cm-reference-box:16}.
{h3}Narrow it down{/h3}
{p}Type a letter and a space before your words. Type ? in the bar to see them all.{/p}
- p player notes, n NPC notes {icon:@Search/s-icon-npc:16}, i notes with an item {icon:@Search/s-icon-items:16}, z notes tied to a zone {icon:@Search/s-icon-situation:16}.
- c this character, g global {icon:@Search/s-icon-global:16}, t tasks {icon:@Search/s-icon-tasks:16}, a alarms {icon:@Search/s-icon-alarm:16}, x rich {icon:@Search/s-icon-rich:16}, l plain.
- d today, d week, d month: made or edited then.
- b searches the Trash, o searches the settings, m sends a note to chat.
- #tag, @who the note is about, * favorites, -word leaves a word out, "an exact phrase".
{p}Settings: {link*bnbui:settings.modules.oracle*}.{/p}
]] },

{ title = "Player and NPC notes", rev = 3, body = [[
{p}Make a note about a player or an NPC, with their details filled in.{/p}
- A player: from the Inspect window, or their right-click menu.
- {icon:@Search/s-icon-npc:16} An NPC: target it and press F6 (Create Note from Target).
- The note gets their portrait and details, and for a player their gear in the {link*bnbui:help.reference-box*Reference Box}.
- {icon:@UI/ui-tldr-add:16} Give the note a tl;dr, one short line like KOS: it shows in the game tooltip when you hover them.
{p}Settings: {link*bnbui:settings.modules.unitNotes*} and {link*bnbui:settings.modules.tldr*}.{/p}
]] },

{ title = "Quick notes", rev = 3, body = [[
{p}{icon:@Explorer/ex-quick-note:16} Ways to make a note in a hurry.{/p}
- F7 makes a new note at once, in the main window or as a sticky note to type in.
- {icon:@UI/ui-icon-quest:16} Quest, gossip, book and letter windows get a note button: one click makes a note of what they say.
- {icon:@BCB/addon-dialogueui:16} Dialogue UI and {icon:@BCB/addon-immersion:16} Immersion get the same button.
{p}Settings: {link*bnbui:settings.modules.quickNote*}.{/p}
]] },

{ title = "Focus mode", rev = 3, body = [[
{p}{icon:@ContextMenu/Symbols/cm-focus-mode:16} Write in full screen, with the game interface hidden and the camera slowly turning around your character.{/p}
- Open it from the editor toolbar, or with Ctrl+Enter in the Oracle bar.
- A rich note gets its preview beside the text.
- Esc or the close button brings everything back as it was.
{p}Settings: {link*bnbui:settings.modules.focus*}.{/p}
]] },

{ title = "History and undo", rev = 3, body = [[
{p}BigNoteBox keeps earlier versions of your notes.{/p}
- {icon:@Toolbar/tb-history:16} History: a version of each note is saved when you log out or reload. Compare two versions side by side and bring an old one back (right-click > History).
- {icon:@Toolbar/tb-restore:16} Restore point: save one by hand before a big change.
- {icon:@Toolbar/tb-undo:16} Undo: steps per note, and they can be kept between sessions.
- {icon:@ContextMenu/Symbols/cm-restore-auto:16} Rescue: a note that went missing without being deleted can be brought back from its history.
{p}{icon:@Documentation/doc-important:16} History and kept undo need the BigNoteBox_History addon, which comes with BigNoteBox. Settings: {link*bnbui:settings.modules.history*} and {link*bnbui:settings.modules.undo*}.{/p}
]] },

{ title = "Trash", rev = 3, body = [[
{p}{icon:@ContextMenu/Symbols/cm-trash:16} A deleted note goes to the Trash first, for 30 days unless you change it, so you can get it back.{/p}
- {icon:@Topbar/Normal/tp-trash-normal:16} Open the {link*bnbui:trash*} to restore a note or delete it for good.
- Notes older than the days you set are removed by themselves.
- The Oracle's b prefix searches the Trash.
{p}{icon:@Documentation/doc-important:16} Switched off, deleting a note is permanent: {link*bnbui:settings.modules.trash*}.{/p}
]] },

{ title = "Backup and import", rev = 3, body = [[
{p}{link*bnbui:settings.backup*} keeps your notes safe outside the game.{/p}
- {icon:@ContextMenu/Symbols/cm-export-json:16} Full backup: everything as JSON: your notes, templates, note tokens, tag colors and every settings profile.
- Settings backup: every settings profile, without notes.
- {icon:@ContextMenu/Symbols/cm-export-markdown:16} Selective backup: pick the format and what goes in. Markdown is for reading outside WoW.
{p}Copy the text and keep it in a file. To bring it back, paste it into Import on the same page. Import also takes shared notes, template codes and profile codes.{/p}
{p}{icon:@Documentation/doc-info:16} Notes from other note addons can be moved over from {link*bnbui:settings.advanced*}.{/p}
]] },

{ title = "Sharing notes", rev = 3, body = [[
{p}{icon:@ContextMenu/Symbols/cm-share:16} Right-click a note > Share note.{/p}
- Pick what goes with it: tags, tasks, Reference Box, look, situation, player or NPC data.
- Send it straight to another player who has BigNoteBox, or copy a share code they paste into Import {icon:@Topbar/Normal/tp-import-normal:16}.
- {icon:@ContextMenu/Symbols/cm-send-chat:16} Send to Chat posts the note's text in a chat channel, line by line.
]] },

{ title = "Settings profiles", rev = 3, body = [[
{p}{icon:@Topbar/Normal/tp-settings-normal:16} A profile is a set of settings and window layout. Each character picks one; your notes are the same in every profile.{/p}
- Make a new profile as a copy of the current one, or from scratch.
- Export a profile as a code to share or keep; Import one from a code.
{p}{icon:@Documentation/doc-important:16} Picking another profile reloads the UI.{/p}
{p}Settings: {link*bnbui:settings.advanced*}.{/p}
]] },

{ title = "Modules", rev = 3, body = [[
{p}Most parts of BigNoteBox are modules you can switch on or off in {link*bnbui:settings.modules*}. Switching one off hides it everywhere. Your notes keep everything that belongs to it, so switching it back on brings it all back.{/p}
{p:c}{icon:@UI/ui-mode-minimal:64} {icon:@UI/ui-mode-full:64} {icon:@UI/ui-mode-custom:64}{/p}
{p}Minimal, Full and Custom at the top of that page switch many at once. The {link*bnbui:wizard*setup wizard} asks the same on your first login.{/p}
]] },

{ title = "Keys and commands", rev = 4, body = [[
{h3}Keys{/h3}
- Ctrl+N: open or close BigNoteBox.
- F8: new note. F7: quick note. F6: note from your target.
- Ctrl+Space: Oracle search.
- Ctrl+H: show or hide every sticky. Ctrl+J: bring stickies to the front.
{p}{icon:@Documentation/doc-info:16} A key the game or another addon already uses is left alone. Change them in {link*bnbui:settings.general*}.{/p}
{h3}Commands{/h3}
- /bnb: open or close the window.
- /bnb new: a new note.
- /bnb search text: Oracle search.
- /bnb config: Settings.
- /bnb whatsnew: the latest patch notes.
- /bnb help: this help book.
- /bnb commands: every command in chat.
]] },

}

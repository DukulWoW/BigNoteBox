-- BigNoteBox UI/FeatureListData.lua
--
-- EDITABLE FEATURE LIST
-- This file is the only file you need to edit to update the help book's Features tab.
--
-- FORMAT:
--   Each entry in BNB.FEATURE_LIST is a section with:
--     header  string   -- section title (gold, large)
--     blurb   string   -- one paragraph description shown below the header
--     items   table    -- bullet list of specific features
--     help    table    -- optional: help topic keys (UI/HelpData.lua) shown as
--                         "More in the help" links under the section
--
--   Shown in the help book's Features tab, sorted A-Z by header (Dukul,
--   2026-10-24), so the order here does not matter.
--
-- RULES:
--   - Plain ASCII only in string literals (no Unicode curly quotes, em-dashes etc.)
--   - WoW color codes are fine: |cffrrggbb...|r
--   - Keep blurb to 2-4 sentences. Wrap long lines with \n for readability here,
--     but the renderer does its own word-wrap so \n is optional.
--   - Item strings are plain text; one capability per line.
--   - US spelling (color, favorite, center, gray), as everywhere in BigNoteBox.
--   - Keep it in step with README.md and the Help topics (ALL-556, 2026-10-24).

local BNB = BigNoteBox

BNB.FEATURE_LIST = {

    -- ── Notes & Folders ──────────────────────────────────────────────────────
    {
        header = "Notes & Folders",
        help   = { "folders", "getting-started" },
        blurb  = "BigNoteBox is a full notepad inside World of Warcraft. Your notes " ..
                 "are kept for your whole account: each one belongs to every " ..
                 "character (Global) or to just one. Runs on Retail and WoW: Forever, " ..
                 "and in beta on Classic Era, TBC Anniversary and Mists of Pandaria Classic.",
        items  = {
            "As many notes as you like, each with a title and as much text as you want",
            "Global or per-character scope per note",
            "Folders: drag notes in, give a folder a color; deleting a folder never deletes its notes",
            "Pin notes to the top, mark favorites, lock a note against edits",
            "Sort by creation date, last modified, title or your own drag order",
            "Duplicate, copy or move notes, alone or several at once in Select mode",
            "Right-click any note for every action it has",
        },
    },

    -- ── Note List & Explorer View ────────────────────────────────────────────
    {
        header = "Note List & Explorer View",
        help   = { "note-list", "explorer-view" },
        blurb  = "Two ways to see your notes. The Note list sits beside the open note; " ..
                 "the Explorer view shows notes and folders as a grid of icons over " ..
                 "the whole window, like the file explorer on your computer. The " ..
                 "first button on the toolbar switches between them.",
        items  = {
            "Note list: Pinned, Folders and Notes sections, each remembering if it is open",
            "Explorer view: pick several notes and drag them onto a folder",
            "Explorer view: Pinned first or Favorites first from the View menu",
            "Explorer view can open on the note you left open",
            "Filter the list by tags, or to notes with tasks",
        },
    },

    -- ── Oracle Search ────────────────────────────────────────────────────────
    {
        header = "Oracle Search",
        help   = { "oracle-search" },
        blurb  = "A search bar that finds any note from anywhere in the game, by " ..
                 "title, text or tag. Open it with Ctrl+Space or /bnb search. Type ? " ..
                 "in the bar to see every way to narrow it down.",
        items  = {
            "Enter opens the note; Shift as a sticky note, Ctrl in Focus mode, Alt in the Reference Box",
            "Prefixes: p player notes, n NPC notes, i items, z zones, t tasks, a alarms",
            "c this character, g global, x rich, l plain, d today / week / month",
            "b searches the Trash, o searches the settings, m sends a note to chat",
            "#tag, @who the note is about, * favorites, -word to leave a word out, \"an exact phrase\"",
        },
    },

    -- ── Tags ─────────────────────────────────────────────────────────────────
    {
        header = "Tags",
        help   = { "tags" },
        blurb  = "Tags are short words on a note, like Raid or Gold. A note can have " ..
                 "as many as you like, and a tag is the same whatever its case.",
        items  = {
            "Add tags from the right-click menu or under the title in the editor",
            "Click a tag to show only the notes that have it",
            "The tag tree groups every note by tag",
            "The Tag Manager renames, colors and deletes tags across all your notes",
        },
    },

    -- ── Writing ──────────────────────────────────────────────────────────────
    {
        header = "Writing",
        help   = { "writing-notes", "links-in-notes" },
        blurb  = "Notes save as you type, or with a Save button if you prefer. The " ..
                 "toolbar above the text puts in waypoints, links, time stamps and " ..
                 "note tokens, and right-clicking the text inserts game info.",
        items  = {
            "Undo and redo per note, kept between sessions if you like",
            "Note links: link to another note; the link keeps working when it is renamed",
            "Waypoint links: click to track, Shift-click for chat, Ctrl-click to copy a /way line",
            "BigNoteBox links: a link to a Settings page, a window or a help topic",
            "Note settings: the note's icon, icon frame, border, background and font",
            "Spelling: a red line under words that are not in the dictionary (English US or UK), in the editor, Focus mode and a sticky you are typing in; nothing is changed for you",
            "Right-click a red-marked word for suggestions, Add to dictionary or Ignore; your own words in Settings, a Check spelling key",
            "Correct spelling window: goes through the marked words one by one, with suggestions, Ignore this, Ignore all and Add to dictionary",
            "Repeated words (the the) marked; choose whether words in capitals and words with numbers are checked",
            "Text shortcuts: your own, brb + space becomes be right back (Brb gives Be right back), one Undo brings back what you typed",
        },
    },

    -- ── Templates & Tokens ───────────────────────────────────────────────────
    {
        header = "Templates & Tokens",
        help   = { "note-templates", "note-tokens" },
        blurb  = "A template fills a new note for you: a title, text, tags and a look " ..
                 "to start from. A note token is a word in double braces that " ..
                 "BigNoteBox fills in for you; type {{ in a note to see the list.",
        items  = {
            "Built-in templates: Blank, Boss, Weekly, Journal and more",
            "Save any note as a template; share templates as a code",
            "Tokens for here and now: {{date}}, {{time}}, {{zone}}, {{target}}, {{coords}}",
            "Tokens for your character: {{name}}, {{class}}, {{spec}}, {{ilvl}}, {{gold}} and more",
            "Game data by id: {{item:6948}} shows the item link",
            "Make tokens of your own in Settings > Notes > Tokens",
        },
    },

    -- ── Rich Notes ───────────────────────────────────────────────────────────
    {
        header = "Rich Notes",
        help   = { "rich-notes" },
        blurb  = "A rich note is a small page: headings, colors, icons, pictures and " ..
                 "links. The toolbar inserts every tag for you, and the preview beside " ..
                 "the editor shows the result as you type. The tags are compatible " ..
                 "with Total RP 3.",
        items  = {
            "Headings {h1} {h2} {h3} and paragraphs {p}, left, centered or right",
            "Colored text with a color picker",
            "Underline {u} and strikethrough {s}",
            "Game icons {icon}, game art {atlas} and your own pictures {img}",
            "Clickable links; item and spell links show their tooltips",
            "Rich notes show as a page on sticky notes too",
            "Convert any note to rich or back from the right-click menu",
        },
    },

    -- ── Quick Notes & Note Capture ───────────────────────────────────────────
    {
        header = "Quick Notes & Note Capture",
        help   = { "quick-notes" },
        blurb  = "Ways to make a note in a hurry, or to keep what an NPC, a quest or " ..
                 "a book just told you.",
        items  = {
            "F7 makes a new note at once, in the main window or as a sticky note",
            "Quest, gossip, book and letter windows get a note button: one click keeps their text",
            "Dialogue UI and Immersion get the same button",
            "On or off in Settings > Modules > Note Capture",
        },
    },

    -- ── Focus Mode ───────────────────────────────────────────────────────────
    {
        header = "Focus Mode",
        help   = { "focus-mode" },
        blurb  = "Write in full screen, with the game interface hidden and the camera " ..
                 "slowly circling your character. Everything comes back as it was " ..
                 "when you leave.",
        items  = {
            "Open it from the editor toolbar, or with Ctrl+Enter in the Oracle bar",
            "A rich note gets its preview beside the text",
            "Camera turn speed can be changed or switched off",
            "Esc or the close button brings everything back",
        },
    },

    -- ── Sticky Notes ─────────────────────────────────────────────────────────
    {
        header = "Sticky Notes",
        help   = { "sticky-notes" },
        blurb  = "A sticky note is a note pinned to your screen as a small window, so " ..
                 "it stays up while you play. Up to 50 at once (20 by default, " ..
                 "Settings > Modules > Sticky Notes).",
        items  = {
            "Drag to move, drag an edge or a corner to resize",
            "Each sticky has its own font, size, color, background and border",
            "A note with tasks can show its tasks, ticked right on the sticky",
            "Focus look hides everything but the text and the background",
            "Stickies can stay on the Esc menu screen instead of the game screen",
            "Ctrl+H shows or hides every sticky, Ctrl+J brings them to the front",
            "They come back where you left them after a reload",
        },
    },

    -- ── Situations & Toasts ──────────────────────────────────────────────────
    {
        header = "Situations & Toasts",
        help   = { "situations", "toasts" },
        blurb  = "A situation makes a note show up by itself where it matters: a " ..
                 "toast shows the note, or it opens as a sticky note. Toasts are the " ..
                 "small pop-ups for situations, task resets and updates.",
        items  = {
            "Match a zone, a sub-zone, an instance or an instance type (dungeon, raid, delve, battleground)",
            "Match a player, an NPC or a guild",
            "Match a window: vendor, bank, mailbox, auction house or trainer",
            "Match being rested, in an inn or in a city",
            "Show it when the situation starts, ends or both; every time, once a session, a day, a reset or only once",
            "A situation can place waypoints",
            "Choose which toasts show, where, how they look and how long they stay",
        },
    },

    -- ── Tasks ────────────────────────────────────────────────────────────────
    {
        header = "Tasks",
        help   = { "tasks" },
        blurb  = "Tasks are a checklist inside a note, with sub-tasks. Good for " ..
                 "dailies and weekly chores: they can untick themselves at the reset.",
        items  = {
            "Add tasks from the right-click menu or the task panel beside the note",
            "Sub-tasks, drag to reorder",
            "Daily or weekly reset for the whole list or one task at a time",
            "Tick tasks on a sticky note",
            "Show only notes with tasks with one button",
            "Compact, Normal or Spacious task rows",
        },
    },

    -- ── Alarms ───────────────────────────────────────────────────────────────
    {
        header = "Alarms",
        help   = { "alarms" },
        blurb  = "An alarm on a note rings at a time you pick: a real-world time, an " ..
                 "in-game time, or the daily or weekly reset. It can ring once or " ..
                 "repeat on the days you choose.",
        items  = {
            "When it rings, the note pops up with a sound of your choice",
            "Snooze or dismiss",
            "The alarm list at the top of the main window shows every alarm",
        },
    },

    -- ── Reference Box ────────────────────────────────────────────────────────
    {
        header = "Reference Box",
        help   = { "reference-box" },
        blurb  = "A panel beside the editor for the items, spells, quests and links " ..
                 "you attach to a note.",
        items  = {
            "Drag an item or a spell onto it, or Shift-click a link while it is open",
            "Hover an entry for its tooltip; put an entry into the text with one click",
            "A note about a player keeps their gear, with a model viewer and a transmog view",
            "Ctrl-click a gear card to open the dressing room",
        },
    },

    -- ── Player & NPC Notes ───────────────────────────────────────────────────
    {
        header = "Player & NPC Notes",
        help   = { "player-and-npc-notes" },
        blurb  = "Make a note about a player or an NPC, with their portrait and " ..
                 "details filled in.",
        items  = {
            "A player: from the Inspect window or their right-click menu",
            "An NPC: target it and press F6",
            "A player note keeps their gear in the Reference Box",
            "tl;dr: one short line (like KOS) that shows in their tooltip when you hover them",
        },
    },

    -- ── History, Undo & Trash ────────────────────────────────────────────────
    {
        header = "History, Undo & Trash",
        help   = { "history-and-undo", "trash" },
        blurb  = "Nothing has to be lost. History and kept undo live in the " ..
                 "BigNoteBox_History addon, which comes with BigNoteBox: keep it enabled.",
        items  = {
            "A version of each note is saved when you log out or reload",
            "Compare two versions side by side and bring an old one back",
            "Restore point: save one by hand before a big change",
            "Rescue: a note that went missing without being deleted comes back from its history",
            "Deleted notes wait in the Trash for 30 days (you choose how long)",
            "The Oracle's b prefix searches the Trash",
        },
    },

    -- ── Backup, Import & Migration ───────────────────────────────────────────
    {
        header = "Backup, Import & Migration",
        help   = { "backup-and-import" },
        blurb  = "Settings > Backup keeps your notes safe outside the game. Copy the " ..
                 "text and keep it in a file; paste it into Import to bring it back.",
        items  = {
            "Full backup: notes, templates, tokens, tag colors and every settings profile, as JSON",
            "Settings backup: every settings profile, without notes",
            "Selective backup: pick the notes, the parts and JSON or Markdown",
            "Import takes backups, shared notes, template codes and profile codes",
            "Export a note as HTML in three styles: Note only, Plain HTML, Stylized",
            "Move your notes over from OneWoW Notes, Noteworthy II, Take A Note, Yet Another Notepad,",
            "Notepad, Notes, TinyPad, PurpleNotes, SimpleNote, Quick Notes, MyNotepad and AmmeNotepad",
            "See the notes before they come in; nothing is removed from the other addon",
        },
    },

    -- ── Sharing ──────────────────────────────────────────────────────────────
    {
        header = "Sharing",
        help   = { "sharing-notes" },
        blurb  = "Right-click a note > Share note. Pick what goes with it, then send " ..
                 "it straight to another player who has BigNoteBox, or copy a share " ..
                 "code they paste into Import.",
        items  = {
            "Choose the parts: tags, tasks, Reference Box, look, situation, player or NPC data",
            "Send to Chat posts the note's text in a chat channel, line by line",
            "Import adds the note beside yours; nothing is overwritten",
        },
    },

    -- ── BigChatBox ───────────────────────────────────────────────────────────
    {
        header = "BigChatBox",
        blurb  = "BigNoteBox works on its own. With BigChatBox installed it gets two " ..
                 "more ways to talk to chat.",
        items  = {
            "Send any note to chat line by line through BigChatBox",
            "Capture chat into a new note with one click",
        },
    },

    -- ── Look & Feel ──────────────────────────────────────────────────────────
    {
        header = "Look & Feel",
        blurb  = "BigNoteBox looks like Blizzard's own windows by default. Skin mode " ..
                 "gives every window a look of your choice instead.",
        items  = {
            "Skin mode: 14 colors, OLED and OLED Flat among them, with a brightness slider",
            "Random skin at login if you like",
            "Bundled fonts, OpenDyslexic among them, and every LibSharedMedia font you have",
            "Per note: font, size, icon, icon frame, border and background",
            "Accessibility: turn off or slow down the sticky note animation",
        },
    },

    -- ── Modules & Profiles ───────────────────────────────────────────────────
    {
        header = "Modules & Profiles",
        help   = { "modules", "settings-profiles" },
        blurb  = "Most parts of BigNoteBox are modules you can switch on or off. " ..
                 "Your notes keep everything, so switching one back on brings it all " ..
                 "back. A settings profile keeps settings and window layout per character.",
        items  = {
            "Minimal, Full and Custom switch many modules at once",
            "The setup wizard asks the same on your first login",
            "Profiles: copy the current one or start blank, rename, delete",
            "Export and import a profile as a code",
        },
    },

    -- ── Help, Keys & Commands ────────────────────────────────────────────────
    {
        header = "Help, Keys & Commands",
        help   = { "keys-and-commands", "getting-started" },
        blurb  = "The help book has every help topic in chapters, with a search. Open " ..
                 "it with the Help button at the top of the main window or /bnb help.",
        items  = {
            "Ctrl+N open or close, F8 new note, F7 quick note, F6 note from your target",
            "Ctrl+Space Oracle search, Ctrl+H hide stickies, Ctrl+J stickies to the front",
            "Change the keys in Settings > General; a key already in use is left alone",
            "/bnb, /bnb new, /bnb search, /bnb config, /bnb whatsnew, /bnb features",
            "/bnb help opens the help book, /bnb commands lists every command",
            "Minimap button: click to open, drag to move",
        },
    },

    -- ── Danger Zone ──────────────────────────────────────────────────────────
    {
        header = "Danger Zone",
        blurb  = "The Danger Zone resets settings, clears data and re-runs the setup " ..
                 "wizard. Be careful: most of it cannot be undone, so take a backup first.",
        items  = {
            "Re-run setup wizard",
            "Reset the profile in use, or all settings and profiles",
            "Clear the trash, the history or the restore points",
            "Reset sticky note layouts",
            "Delete all notes",
            "Factory reset",
        },
    },

}

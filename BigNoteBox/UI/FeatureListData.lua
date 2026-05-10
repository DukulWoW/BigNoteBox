-- BigNoteBox UI/FeatureListData.lua
--
-- EDITABLE FEATURE LIST
-- This file is the only file you need to edit to update the Features window.
--
-- FORMAT:
--   Each entry in BNB.FEATURE_LIST is a section with:
--     header  string   -- section title (gold, large)
--     blurb   string   -- one paragraph description shown below the header
--     items   table    -- bullet list of specific features
--
-- RULES:
--   - Plain ASCII only in string literals (no Unicode curly quotes, em-dashes etc.)
--   - WoW colour codes are fine: |cffrrggbb...|r
--   - Keep blurb to 2-4 sentences. Wrap long lines with \n for readability here,
--     but the renderer does its own word-wrap so \n is optional.
--   - Item strings are plain text; one capability per line.

local BNB = BigNoteBox

BNB.FEATURE_LIST = {

    -- ── Notes & Organisation ─────────────────────────────────────────────────
    {
        header = "Notes & Organisation",
        blurb  = "BigNoteBox is a full notepad companion for World of Warcraft. " ..
                 "Create as many notes as you like, organised by tags, scope, and " ..
                 "context. Notes are stored account-wide so every character shares " ..
                 "the same library, with optional per-character scoping when you need it.",
        items  = {
            "Unlimited notes with title and freeform body text",
            "Global or per-character scope per note",
            "Drag-to-reorder notes in the list",
            "Pin notes to the top of the list so they are always visible",
            "Mark notes as favourite for quick identification",
            "Sort by creation date, last modified, title, or manual order",
            "Search by title or body text with live filtering",
            "Right-click any note for a full context menu",
            "Duplicate any note with one click",
            "Lock a note to prevent accidental edits",
        },
    },

    -- ── Normal Mode & Skin Mode ──────────────────────────────────────────────
    {
        header = "Normal Mode & Skin Mode",
        blurb  = "BigNoteBox was originaly made with the standard WoW chrome, meaning " ..
                 "the one you see when you open the achievements panel, or the character " ..
                 "window. It looks like an official Blizzard UI in this mode. " ..
                 "But a lot of players like a less lore friendly look, so therefore " ..
                 "you can select Skin Mode, then choose a color and brightness.",
        items  = {
            "Found in Main Config > Appearance > Skins",
            "Select between 13 different colors",
            "Choose a brightness to make the color pop more",
            "Randomize the theme on login and reload",
            "Randomize the brightness together with the theme on login and reload",
            "One of the skins is an OLED one where it's as black as possible",
            "Every window is skinned and has their own buttons to tie everything togheter nicely",
        },
    },

    -- ── Tags & Trash ─────────────────────────────────────────────────────────
    {
        header = "Tags & Trash",
        blurb  = "Tags give you a flexible second dimension of organisation on top of " ..
                 "note titles. Filter the list to any combination of tags instantly. " ..
                 "Deleted notes go to the Trash and stay there until you choose to " ..
                 "restore or permanently remove them.",
        items  = {
            "Add any number of tags to each note",
            "Tag tree panel filters the note list to matching notes",
            "Multi-tag filter: show notes that match all selected tags",
            "Rename or delete tags globally from the Tag Manager",
            "Deleted notes move to Trash instead of being erased",
            "Restore any trashed note at any time",
            "Trash auto-purges notes older than a configurable number of days",
            "Empty Trash manually from the Trash window",
        },
    },

    -- ── Rich Notes ───────────────────────────────────────────────────────────
    {
        header = "Rich Notes",
        blurb  = "Rich Notes are an optional per-note formatting mode that lets you " ..
                 "turn plain text into a fully laid-out document, rendered right inside " ..
                 "the note window and on sticky notes. When you mark a note as rich, a " ..
                 "markup toolbar appears above the editor. Write your content using " ..
                 "simple tags, then switch to View mode to see it rendered. Rich Notes " ..
                 "use a tag syntax compatible with TotalRP3, so notes can be copied " ..
                 "between the two addons without reformatting.",
        items  = {
            "Three heading levels: {h1}, {h2}, {h3} with left, centre, or right alignment",
            "Paragraph blocks: {p}, {p:c}, {p:r} for structured body text",
            "Color: {col:rrggbb}...{/col} with a color picker in the toolbar",
            "Inline icons: {icon:IconName:size} embeds any WoW game icon inline",
            "Images: {img:filename:width:height} displays custom .tga or .blp files from UserImages/",
            "Links: {link*url*label} creates clickable hyperlinks; item and spell links show tooltips",
            "Markup toolbar: one-click insertion for all tags; wraps selected text automatically",
            "Editor / View toggle: switch between editing and rendered view with one click",
            "Sticky note rendering: rich notes display formatted on pinned sticky notes",
            "Convert anytime: right-click to convert to or from rich mode; tags are stripped cleanly",
            "TotalRP3 tag compatibility: markup copies cleanly between both addons",
        },
    },

    -- ── Sticky Notes ─────────────────────────────────────────────────────────
    {
        header = "Sticky Notes",
        blurb  = "Sticky Notes let you pin any note to your screen as a floating, " ..
                 "always-visible overlay. Each sticky has its own position, size, " ..
                 "font, and transparency. Rich notes render formatted on the sticky. " ..
                 "Open up to 50 sticky notes at once (config > features > sticky notes).",
        items  = {
            "Pin any note as a floating sticky note anywhere on screen",
            "Per-sticky font family, font size, and text colour",
            "Adjustable background colour and transparency",
            "Configurable border style and brightness",
            "Rich notes render with full formatting on the sticky",
            "Toggle between rendered view and raw markup per sticky",
            "Stickies persist across sessions and are restored on login",
            "Drag to reposition; resize from any corner or edge",
            "Sticky Notes have a Focus Mode which hides everything but the note/task and background",
        },
    },

    -- ── Tasks ────────────────────────────────────────────────────────────────
    {
        header = "Tasks",
        blurb  = "Add a task list to any note and track your progress without leaving " ..
                 "the game. Tasks live inside the Reference Box alongside your note, " ..
                 "and can also be shown directly in sticky notes for at-a-glance tracking.",
        items  = {
            "Add tasks and sub-tasks to any note",
            "Check and uncheck tasks to track progress",
            "Sub-tasks collapse and expand to keep things tidy",
            "Reorder tasks by dragging",
            "Set daily or weekly auto-reset per task or for the whole note",
            "Bind tasks to a situation so they reset when you leave a zone, instance, or player",
            "Task panel in the Reference Box with a completion counter and splitter",
            "Sticky notes can show task view instead of the note body",
            "Live checkbox toggling directly in sticky note task view",
            "Global reset and situation shown as icons in the sticky note footer",
            "Task filter in the note list to show only notes with tasks",
            "Task list spacing: Compact, Normal, or Spacious (Config > Features > Tasks)",
            "Tasks included as a tier in the note share system",
        },
    },

    -- ── Alarms ───────────────────────────────────────────────────────────────
    {
        header = "Alarms",
        blurb  = "Every note can have an alarm attached to it. Alarms fire at a " ..
                 "specific in-game time and can repeat daily, weekly, or on custom " ..
                 "days of the week. When an alarm fires, the note is highlighted " ..
                 "and optionally announced with a sound and chat message.",
        items  = {
            "Set a one-off or repeating alarm on any note",
            "Recurrence options: daily, weekly, or specific days of the week",
            "Sound alert from a selectable list of sounds on alarm fire",
            "Optional chat message printed when the alarm fires",
            "Optional glow effect on the note list entry",
            "Alarm Overview window lists all upcoming alarms",
            "Snooze or dismiss alarms from the overview or the note itself",
        },
    },

    -- ── Contextual Surfacing ─────────────────────────────────────────────────
    {
        header = "Contextual Surfacing",
        blurb  = "Notes can be tagged with a context so they surface automatically " ..
                 "when you enter the right zone, instance, or encounter a specific " ..
                 "player or NPC. The sidebar shows which notes are relevant to " ..
                 "your current situation at a glance.",
        items  = {
            "Trigger notes by zone or subzone name",
            "Trigger notes by instance (dungeon, raid, battleground)",
            "Trigger notes by player name for PvP or social notes",
            "Trigger notes by NPC name for boss or vendor notes",
            "Sidebar highlights contextually active notes with an indicator",
            "Configurable: show a popup when a contextual note becomes active",
            "Zone Picker UI for browsing and selecting zones without typing",
        },
    },

    -- ── BCB Integration ──────────────────────────────────────────────────────
    {
        header = "BigChatBox Integration",
        blurb  = "When BigChatBox is installed, BigNoteBox gains direct two-way " ..
                 "integration. Send note content to any chat channel line by line, " ..
                 "or capture chat input directly into a new note. Requires " ..
                 "BigChatBox to be installed and enabled.",
        items  = {
            "Send any note to chat line by line via BigChatBox",
            "Choose target channel: say, party, raid, guild, or whisper",
            "Capture BCB chat input as a new BNB note with one click",
            "QuickNote mode: pop open a note from the BCB input bar",
        },
    },

    -- ── DUI & Immersion Integration ──────────────────────────────────────────
    {
        header = "Dialogue UI & Immersion Integration",
        blurb  = "If you have DUI and/or Immersion installed, BigNoteBox will " ..
                 "integrate directly with the addons letting you create notes " ..
                 "of quests, notes, tomes and other ingame content.",
        items  = {
            "DUIs copy text button will automatically create a note",
            "Immersion has an extra floating button that when clicked creates a note",
            "You can turn this on and off in \"Main config > Features\"",
        },
    },

    -- ── Focus Mode ───────────────────────────────────────────────────────────
    {
        header = "Focus Mode",
        blurb  = "Focus Mode opens a distraction-free full-screen editor that hides " ..
                 "the main BNB window and companion panels. A dark overlay dims the " ..
                 "game world, and the camera slowly orbits while you write. " ..
                 "Everything is restored exactly as you left it when you exit.",
        items  = {
            "Distraction-free editor with dark full-screen overlay",
            "Slow camera orbit while writing (speed configurable, can be disabled)",
            "Camera orbit pauses on movement and resumes after a configurable delay",
            "Side-by-side rich preview pane in focus mode",
            "Orbit spin toggle button in the focus toolbar",
            "ESC or the close button exits and restores all windows",
            "AFK overlay shown if you go AFK while focus mode is open",
        },
    },

    -- ── History ──────────────────────────────────────────────────────────────
    {
        header = "Note History",
        blurb  = "BigNoteBox automatically snapshots every note when you log out or " ..
                 "reload. You can also save a manual snapshot at any time. The " ..
                 "History window lets you browse, compare, and restore any previous " ..
                 "version of a note.",
        items  = {
            "Auto-snapshot on every logout and reload",
            "Manual snapshot from the note toolbar or right-click menu",
            "Configurable maximum number of auto-slots per note (1-20, default 5)",
            "History window: browse all snapshots with timestamps",
            "Side-by-side diff view: compare any two snapshots",
            "One-click restore from any snapshot",
            "History size shown in the Data Summary section of Settings",
        },
    },

    -- ── Share & Import ───────────────────────────────────────────────────────
    {
        header = "Share & Import",
        blurb  = "Share any note with another player in one click by generating a " ..
                 "compressed share code that fits in a single chat message. The " ..
                 "recipient pastes the code into the Import field to add the note " ..
                 "to their library. You control exactly which fields are included.",
        items  = {
            "Generate a compressed share code for any note",
            "Choose share tier: title and body only, with tags, with icon, or everything",
            "Inspect tier: includes RefBox gear card data for player notes",
            "Import a shared note by pasting the code into the Import field",
            "Import merges alongside existing notes; nothing is overwritten",
            "Share codes are plain text and can be sent via any chat channel",
        },
    },

    -- ── Backup & Export ──────────────────────────────────────────────────────
    {
        header = "Backup & Export",
        blurb  = "Export your entire note library to Markdown or JSON at any time. " ..
                 "Markdown is human-readable and pasteable anywhere. JSON is " ..
                 "full-fidelity and can be imported back into BNB without data loss. " ..
                 "Both formats include all note metadata.",
        items  = {
            "Export all notes to Markdown (.md) format",
            "Export all notes to JSON format (full fidelity, re-importable)",
            "Import a JSON export back into BNB alongside existing notes",
            "Import a Markdown export with title, body, and scalar fields",
            "No data loss on JSON round-trip: all fields preserved",
        },
    },
    
    -- ── HTML Export ──────────────────────────────────────────────────────────
    {
        header = "HTML Export",
        blurb  = "You can export any note as HTML to add directly to your website " ..
                 "and there are three different styles to choose from.",
        items  = {
            "Right click any note and export as HTML",
            "Three styles to choose from",
            "Note only: Will give the HTML format needed to give you the note only",
            "Plain HTML: Will give you a formated note based on the skin you're using",
            "Stylized: Full HTML file with full CSS, animations and a book-ish look",
        },
    },


    -- ── Reference Box ────────────────────────────────────────────────────────
    {
        header = "Reference Box (RefBox)",
        blurb  = "The Reference Box is a companion panel that displays item and " ..
                 "gear information attached to a note. Inspect another player and " ..
                 "their equipped gear is captured and stored with the note as " ..
                 "interactive cards. Ctrl-click any card to open the dressing room.",
        items  = {
            "Attach items, spells, and quests to any note by drag and drop",
            "Inspect a player to capture their full gear set into the note",
            "Gear cards show item icon, name, item level, and slot",
            "Transmog mode: view the appearance of each gear slot separately",
            "Ctrl-click any gear card to open the WoW dressing room",
            "Gear data is stored with the note and persists across sessions",
            "RefBox floats alongside the main window and can be repositioned",
        },
    },

    -- ── Migration ────────────────────────────────────────────────────────────
    {
        header = "Migration from Other Addons",
        blurb  = "If you are switching from another note-taking addon, BigNoteBox " ..
                 "can import your existing notes automatically. Supported addons are " ..
                 "detected at login and a migration prompt is shown. Your notes in " ..
                 "the other addon are never modified.",
        items  = {
            "Supported: Noteworthy II, TakeANote, Yet Another Notepad, Notepad",
            "Supported: Notes, TinyPad, PurpleNotes, SimpleNote, QuickNotes",
            "Supported: OneWoW Notes (global and per-character notes)",
            "Per-character notes are imported with their correct character scope",
            "All imported notes are tagged with the source addon name",
            "Category and tag data from source addons is preserved as BNB tags",
            "Preview migration before committing: see exactly what will be imported",
            "Migration can be re-run from Settings > Advanced at any time",
        },
    },

    -- ── Appearance & Skins ───────────────────────────────────────────────────
    {
        header = "Appearance & Skins",
        blurb  = "BigNoteBox ships with a full skin system that replaces the default " ..
                 "WoW frame chrome with a custom styled look. Choose from multiple " ..
                 "colour presets and adjust brightness to your taste. Every window " ..
                 "in BNB — including Config, RefBox, and sticky notes — follows " ..
                 "the active skin.",
        items  = {
            "Skin mode toggle: switch between WoW default chrome and BNB skin",
            "Multiple colour presets: Emerald, Sapphire, Amber, Rose, and more",
            "Brightness slider: lighten or darken the skin independently",
            "All windows skinned: main, config, refbox, stickies, alarms, history",
            "Per-note font family from bundled fonts: Noto Serif, EB Garamond, Noto Sans, JetBrains Mono, Gloria Hallelujah, OpenDyslexic, Fredoka, Playwrite IE",
            "Per-note font size, font outline, and line height",
            "Per-note background texture from 20 bundled textures",
            "OpenDyslexic font available for accessibility",
        },
    },
    
    -- ── LSM font support ─────────────────────────────────────────────────────
    {
        header = "LSM font support",
        blurb  = "By default BNB has a currated list of fonts you can use, " ..
                 "but you can turn on support for all LibSharedMedia-3.0 fonts " ..
                 "that you have installed. " ..
                 "It will also show fonts installed by other addons through LSM.",
        items  = {
            "Turn on LSM font support in \"Main config > Advanced > Fonts\"",
            "Will give you the ability to use even more fonts for your notes and sticky notes",
            "Viewing rich notes will use the default font regardless",
        },
    },

    -- ── Minimap & Keybinds ───────────────────────────────────────────────────
    {
        header = "Minimap Button & Keybinds",
        blurb  = "BigNoteBox adds a minimap button for quick access and supports " ..
                 "configurable keybinds for the most common actions. All keybinds " ..
                 "are set directly in the Settings window without going through " ..
                 "the WoW keybind interface.",
        items  = {
            "Minimap button: left-click to toggle BNB, right-click for options",
            "Minimap button position is draggable",
            "Keybind for open/close BNB (default: Ctrl+N)",
            "Keybind for New Note",
            "Keybind for Quick Note",
            "Keybind for Focus Mode",
            "Keybind for Sticky Note (current note)",
            "All keybinds configurable from Settings > General",
        },
    },

    -- ── Danger Zone ──────────────────────────────────────────────────────────
    {
        header = "Danger zone",
        blurb  = "The Danger Zone is where you can reset settings, factory reset " ..
                 "the addon and re-run the setup wizard. " ..
                 "Be careful, most of these settings are irreversible.",
        items  = {
            "Re-run setup wizard",
            "Reset settings",
            "Clear out trash",
            "Clear all session history",
            "Clear all manual restore points",
            "Reset sticky note layouts",
            "Clear migration history",
            "Remove all characters",
            "Delete all notes",
            "Factory reset",
        },
    },

}


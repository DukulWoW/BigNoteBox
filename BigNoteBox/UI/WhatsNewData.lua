-- BigNoteBox UI/WhatsNewData.lua
--
-- EDITABLE PATCH NOTES FILE
-- Update this file before each release. The WhatsNew window reads it directly.
--
-- HOW TO UPDATE:
--   1. Change `version` to the new addon version string (must match Init.lua).
--   2. Replace the `entries` table with your new patch notes.
--   3. Each entry is a plain string. Prefix lines however you like:
--        "New: ..."   "Fixed: ..."   "Changed: ..."   "Removed: ..."
--   4. A line for one client only is a table instead of a string:
--        { forever = true, "..." }   -- WoW Forever only
--        { retail  = true, "..." }   -- Retail only
--      No "WoW Forever:" prefix needed; only that client sees the line.
--   That's it - no other files need to change for a routine version bump.
--
-- FORMAT RULES:
--   - Keep each entry to a single line of reasonable length.
--   - Plain ASCII only - no Unicode characters (they render as boxes in WoW).
--   - No markup - entries are rendered as plain GameFont text.
-- |cff66bb6aNew:|r
-- |cff66bb6aFixed:|r
-- |cff66bb6aChange:|r


local BNB = BigNoteBox

BNB.PATCH_NOTES = {
    version = "1.14.0",
    entries = {
        "|cff66bb6aNew:|r Oracle search: press Ctrl+Space anywhere to search all your notes, then open one in the main window. Hold Shift to open it as a sticky, Ctrl for Focus mode, or Alt for the Reference Box. Also /bnb search",
        "|cff66bb6aNew:|r Oracle search prefixes: start with a letter and a space to narrow the search, e.g. \"p\" player notes, \"n\" NPC notes, \"t\" notes with tasks, \"d week\" edited this week, \"s\" to open as a sticky. Also #tag, @name, -word, \"exact phrase\" and * for favourites. Type ? for the full list with examples",
        "|cff66bb6aNew:|r Oracle search ranks by what matters now: your target's note, notes for this zone and this character, favourites, recently opened or edited notes and alarms due soon come first, even with an empty box",
        "|cff66bb6aNew:|r Oracle search results show small icons for what a note is: NPC, elite, player (Alliance or Horde), quest, item, rich note, and notes with a situation or an alarm",
        "|cff66bb6aNew:|r Oracle search themes: Eye of Kilrogg, Alliance and Horde",
        "|cff66bb6aNew:|r Oracle search settings (Settings > Modules > Oracle search, or right-click the bar): theme, how many results, move the bar where you want it with a live preview, how notes open, keep the bar open to open several notes, and how much each ranking boost counts. The bar starts a little above the middle of the screen, in your faction's theme",
        "|cff66bb6aNew:|r Oracle search: a Custom border theme. Set it up like a sticky note: background colour and texture (the sticky note backgrounds, with the thumbnail picker), Colorize, brightness and opacity, border style, thickness, offset and brightness, the colour of the selected result, and a font (BigNoteBox fonts or LibSharedMedia) with its size. Start from the built-in Default style (a Blizzard window frame) or Plain, save your own styles, and share them with Export and Import. Other addons can register box themes like it",
        "|cff66bb6aNew:|r Oracle search results: a Results section in its settings sets the title and preview text size, the note icon size and the badge size, and can hide the icons or the badges. Whose note it is shows as the rightmost badge: a globe for global notes, otherwise the character's class icon in a circle, with the name on hover",
        "|cff66bb6aNew:|r The setup wizard's keybinding page now also lists Create note from target and Oracle search",
        "|cff66bb6aNew:|r Timestamp button in the note toolbar, right of the bullet button: insert the date, the time, or both at the cursor, in your timestamp format from Settings > Appearance",
        "|cff66bb6aNew:|r Choose what double-clicking a note in the list does (Settings > Notes): note settings, just open, sticky, ESC sticky, Focus mode, alarm, task, or switch lock, favorite or pin",
        "|cff66bb6aNew:|r Open as sticky note and Open as ESC sticky note close the sticky when it is already open that way. The right-click menu then says Close sticky note, so you can see that a note has a sticky open",
        "|cff66bb6aNew:|r Eye button in the main window title bar to hide and show all sticky notes. It shows a closed eye while they are hidden. Hiding them (also with the Ctrl+H keybind) now says so in chat, with the key to bring them back, and so does logging in with them still hidden. The minimap button tooltip shows it too",
        "|cff66bb6aNew:|r Double-click a rich note in View mode to open the editor",
        "|cff66bb6aNew:|r Mouse cursors that show what you can do: the move cursor over window title bars, a resize arrow on resize grips and splitters, a hand when you drag a note or turn the Reference Box model, and a lock over the text of a locked note. Silver on Retail, gold on WoW Forever",
        "|cff66bb6aNew:|r Tasks can be switched off (Settings > Modules > Tasks). Off hides the Tasks button, the task panel, the note list menu entry and filter, and the sticky task view. Your tasks are kept and come back when you switch it on",
        "|cff66bb6aNew:|r Use server time (Settings > Appearance): timestamps, the welcome clock, inserted dates and alarms show the server clock instead of your computer's, and alarm times are entered in server time. Everything is still saved with the real time, so switching it off changes nothing",
        "|cff66bb6aNew:|r 50 new sticky note backgrounds (45 on Retail) taken from the game's own art: stone, wood, parchment, skies, scenery and profession scenes. Each one fills the note in the way that suits it (tiled, scaled to cover, or anchored) and takes your note colour and Colorize setting. Pick one in sticky settings from a grid of thumbnails, each showing your note with that background and sorted into tabs by look, or step through them with the < and > arrows",
        "|cff66bb6aNew:|r Texture brightness slider for sticky note backgrounds, under Colorize texture: make the background art brighter or darker without changing the note colour",
        "|cff66bb6aNew:|r Sticky notes get a \"Window\" background, the main window's own (rock on Retail, wood on Forever)",
        "|cff66bb6aChange:|r Settings: less empty space between the tabs and the settings below them",
        "|cff66bb6aChange:|r Sticky note settings: every slider has its name and value on one line above a full-width slider, like Note settings, instead of the name wrapping beside it",
        "|cff66bb6aChange:|r The Reference Box keeps a fixed height, the same as Note settings, instead of stretching with the main window",
        "|cff66bb6aChange:|r Turning the Reference Box off hides its button under the note instead of greying it, and the other buttons close the gap",
        "|cff66bb6aChange:|r Focus mode is greyed out for a locked note. Unlock the note to use it",
        "|cff66bb6aChange:|r The Send to chat button sits a little further from the main window's resize corner",
        "|cff66bb6aChange:|r The right-click Insert Info menu offers Date, Time, and Date and time, in your timestamp format from Settings > Appearance, like the toolbar button",
        "|cff66bb6aChange:|r Sticky notes fade smoothly to full opacity while the pointer is anywhere on them, rich and task notes included, and fade back when it leaves",
        "|cff66bb6aChange:|r The selected note in the note list, and the drop line and dragged note in Custom sort, are BNB green",
        "|cff66bb6aChange:|r Tasks work without the Reference Box: with the Reference Box off, the Tasks button under the note opens the tasks in a window of their own",
        "|cff66bb6aChange:|r The Reference Box title says what it shows: Reference, Reference + Model, Reference + Tasks, Reference + Model + Tasks, or Tasks",
        "|cff66bb6aChange:|r Editing the text of a checked task unchecks it, so a changed task is not left marked done",
        "|cff66bb6aChange:|r EB Garamond is drawn larger for the same font size, so it no longer looks smaller than the other fonts",
        "|cff66bb6aChange:|r The \"Add tag...\" field under a note is easier to see",
        "|cff66bb6aChange:|r Task list: hover a task to get an X that deletes it right away and a + that adds a sub-task (both only while hovering). The > arrow only shows on tasks that have sub-tasks",
        "|cff66bb6aChange:|r The original sticky backgrounds moved to their own small addon, BigNoteBox Backgrounds. It comes in the same download and only loads when a note uses one of them. Notes that use them look the same. With that addon removed or disabled, they show their plain colour until it is back",
        "|cff66bb6aFixed:|r Settings > Modules > Focus mode: \"Tint overlay with skin color\" is greyed out in normal mode, where it does nothing",
        "|cff66bb6aFixed:|r In-game alarms fire at the server time you set, not your computer's local time at that hour",
        "|cff66bb6aFixed:|r Skin mode: the Reference Box Model and Tasks tabs no longer draw on top of the window",
        "|cff66bb6aFixed:|r The X in Focus mode closes only Focus mode and brings back the main window, same as Esc",
        "|cff66bb6aFixed:|r Custom sort: a dragged note now lands exactly where the drop line shows. This also works with the sidebar, favourite or task filter on, in the collapsed list, and with pinned notes",
        "|cff66bb6aFixed:|r Opening a note as an ESC sticky a second time no longer turns it into a normal sticky. Before, it alternated on every open and stayed that way after a reload",
        "|cff66bb6aFixed:|r Esc with an ESC sticky open over the game menu closes the game menu first, not the BigNoteBox windows behind it",
        "|cff66bb6aFixed:|r The window scale lock tooltip switches between Locked and Unlocked as soon as you click it",
        "|cff66bb6aFixed:|r More interface text can now be translated: the markup bar tooltips, Tag Manager buttons, waypoint chat messages, sticky note settings headers and a few settings tooltips",
        "|cff66bb6aFixed:|r Resizing a window from its bottom-right grip no longer makes it jump, grow or shrink when you click the grip, or fill the whole screen. The window also can no longer be sized past the screen edge",
        { forever = true, "|cff66bb6aNew:|r A soft glow behind the note area in the main window, like the one behind the note list" },
        { forever = true, "|cff66bb6aNew:|r New action bar icons under the note, drawn for WoW Forever, and a little bigger so the detail shows" },
        { forever = true, "|cff66bb6aNew:|r Rich notes switch between Markup and Note with two tabs under the window, in the Forever style" },
        { forever = true, "|cff66bb6aNew:|r The WoW Forever notice at login has a new ornate frame" },
        { forever = true, "|cff66bb6aFixed:|r Your character no longer shows up twice (first name, and first name plus surname) in the sidebar and in Copy / Move Note" },
    },
}

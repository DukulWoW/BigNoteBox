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
    version = "1.21.0",
    entries = {
        "|cff66bb6aNew:|r Situation toasts are rebuilt: one toast per note, stacked in the direction you pick (down, up, left or right), each with its own timer, up to 1-10 at once (more wait their turn), sliding into place. Pointing at a toast pauses them all. Settings > Modules > Toasts has a Test button, a new toast position anchor with Reset, and a choice for toasts in combat (show, wait until combat ends, or skip). The old grouped toast is still there as a layout.",
        "|cff66bb6aNew:|r Toast styles: the toasts now look like the game's loot toasts, Horde or Alliance by your faction. Untick Follow my faction to pick another style: Plain black, Skin colour (in skin mode), or the other faction's loot toast. Toast size makes them bigger or smaller.",
        "|cff66bb6aNew:|r Toasts show more: the note's icon with its icon frame (an NPC note shows the creature), why it showed (\"Thrall is here\", \"Vendor open\", the place), the first line of the note and a map pin when the note has a waypoint. Each can be switched off in Settings > Modules > Toasts.",
        "|cff66bb6aNew:|r Right-click a toast: Open, Open as sticky note, Navigate, Not again today, a toast style and time on screen for just that note, and Dismiss.",
        "|cff66bb6aNew:|r Toasts can play a sound (the alarm sounds, off by default).",
        "|cff66bb6aNew:|r Toasts are a module of their own (Settings > Modules > Toasts), with every toast setting on its page and a switch for each kind: situation notes and tasks. Switched off, no toast shows; situations still match, place waypoints and open stickies.",
        "|cff66bb6aNew:|r Note Settings and sticky settings > Situation: a Toast... button sets this note's own toast style and how long it shows, with a Test button.",
        "|cff66bb6aNew:|r Alarms can show as toasts (Settings > Modules > Alarms > Show alarms as). An alarm toast stays until you click it: left click dismisses, right click opens the note, snoozes or dismisses. Alarms you missed while offline or in combat now come as toasts instead of popups.",
        "|cff66bb6aNew:|r When the player or NPC you target or focus has a note, the note's icon shows at the corner of the Target and Focus frame portraits. Click it to open the note (Settings > Modules > Player & NPC Notes).",
        "|cff66bb6aNew:|r 11 new alarm and toast sounds: Apple Pay, Heartbeat, Horror Warning, Ka-Ching, MGS Alert, Quack, Sad Trombone, Toasty, Violin Sting, Warning Alert and Whistle.",
        "|cff66bb6aNew:|r Toasts show on top of all windows, Settings and dialogs included (Settings > Modules > Toasts > Show on top of all windows, on by default).",
        "|cff66bb6aNew:|r Point at a toast to show a close button in its top right corner; an alarm toast closed this way dismisses the alarm.",
        "|cff66bb6aChange:|r New toolbar icons in the main window: in normal mode with their own hover, pressed and greyed-out pictures, in skin mode drawn in a colour that pairs with the skin preset. On Retail and Classic the note editor's action bar uses the more detailed icons from WoW Forever in normal mode.",
        "|cff66bb6aChange:|r Context Popup is now the Situations module: switched off, no situation checks, popups or automatic waypoints, the Situation tab says it is off, and the situation markers hide. Notes keep their situations, and Navigate still works.",
        "|cff66bb6aChange:|r Trash, Note History and Alarms rows use new hover and selection art in normal mode, and Alarms rows highlight on hover.",
        "|cff66bb6aChange:|r New alarm, favourite and situation markers on note icons in the note list and on sticky notes (normal mode); the character's class icon is round to match. A new marker shows on notes that place a waypoint when their situation matches.",
        "|cff66bb6aChange:|r More checkboxes explain themselves on hover: the alarm weekdays and snooze, Send to Chat, export formats, Copy/Move, the migrate window, the setup wizard, and the Character Sidebar and Trash switches.",
        "|cff66bb6aChange:|r The note button in quest, gossip and book windows is now called Note Capture (Settings > Modules > Note Capture), so it is no longer confused with the Quick Note button and F7.",
        "|cff66bb6aChange:|r The Settings window is a little wider in normal mode, so every tab name fits (it was already this wide in skin mode, where the pages now use the full width).",
        "|cff66bb6aChange:|r The Reference Box window is now three parts that each follow their own module: attachments follow Reference Box, the player / NPC model follows Player & NPC Notes, and tasks follow Tasks. With the Reference Box off, player and NPC notes still show their model.",
        "|cff66bb6aChange:|r The Get BigChatBox window has the look of the Report a bug window, with a button that copies the CurseForge link.",
        "|cff66bb6aChange:|r Skin mode: scrollbars and sliders take the skin colours, and dropdowns are drawn like the other skin buttons, with a small arrow button at the end and their open list in the skin colours.",
        "|cff66bb6aChange:|r Settings > Advanced: debug mode is a checkbox of its own (for this session only, also /bnb debug on and off), and the developer tools are a page in Settings. They need the separate BigNoteBox_Dev addon, now a download on each GitHub release.",
        "|cff66bb6aChange:|r Less gold everywhere: headings take one colour (in skin mode a colour that pairs with your skin preset, a soft warm gold on Obsidian, OLED and Argent; in normal mode a soft green), while checkbox labels, setting names and other text are white. On the OLED skin preset white text is a softer grey. Game tooltips, chat lines and toasts keep their own colours.",
        "|cff66bb6aChange:|r Settings > General: \"by Dukul\" is a button that copies the link to dukul.net.",
        "|cff66bb6aChange:|r New icons on the formatting toolbar under the note title, with a new hover glow; in skin mode they are plain icons in the skin's accent colour, and the font and size boxes look like the other skin dropdowns.",
        "|cff66bb6aChange:|r New icons for the note list's tag tree, favourites, tasks and reset buttons and the list collapse arrow: gold in normal mode, the skin's accent colour in skin mode, with a hover glow.",
        "|cff66bb6aChange:|r The note editor's action bar icons show a soft glow behind them on hover instead of growing (gold in normal mode, the skin's accent colour in skin mode).",
        "|cff66bb6aChange:|r The main window's top bar icons have a little more room between them in normal mode.",
        "|cff66bb6aChange:|r Skin mode: checkboxes are drawn in the skin's colours, in Settings and in the task lists of sticky notes and the Reference Box; sticky note task checkboxes are bigger in both modes.",
        "|cff66bb6aChange:|r Skin mode: the rich note Source / Note tabs show the active tab's icon in the skin's accent colour and dim the other tab.",
        "|cff66bb6aChange:|r Skin mode: the selected font card in Settings, the New note dialog and the setup wizard (and the wizard's other choices) is drawn in the skin's colours instead of green.",
        "|cff66bb6aChange:|r Settings > Appearance: the skin options (preset, brightness, opacity, randomize) only show while skin mode is on, so the font settings move up in normal mode.",
        "|cff66bb6aChange:|r The grouped toast layout looks like the other toasts now and is used only when several notes show at once.",
        "|cff66bb6aChange:|r Skin mode: a new rich-note icon beside the note title, in the skin's accent colour, and the inactive rich tab dims its icon along with its label.",
        "|cff66bb6aFixed:|r The move cursor no longer stays stuck after moving from the main window's top bar into the window.",
        "|cff66bb6aFixed:|r The Trash window showed titles in the heading colour when the note had no title colour; they are white now. Note History shows each note's title in its own title colour.",
        "|cff66bb6aFixed:|r \"Use WoW's default font\" no longer sits right on the font cards in Note Settings and sticky settings.",
        "|cff66bb6aFixed:|r In skin mode, divider lines no longer turn glaring at high skin brightness.",
        "|cff66bb6aFixed:|r In skin mode, the icons on the main window's title bar and other icon buttons no longer turn white at high skin brightness.",
        "|cff66bb6aFixed:|r In skin mode, greyed-out buttons now look greyed out and no longer show a press when clicked.",
        "|cff66bb6aFixed:|r Switching off Dim screen behind ESC sticky notes now takes effect at once, not at the next ESC.",
    },
}

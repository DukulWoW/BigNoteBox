-- BigNoteBox UI/WhatsNewData.lua
--
-- EDITABLE PATCH NOTES FILE
-- Update this file before each release. It is the newest page of the Help
-- book's Patch notes tab until the release tag puts it in PatchHistory.lua
-- (ALL-614, UI/WhatsNew.lua): lines are grouped under their New / Change /
-- Fixed label there, so keep the "|cff66bb6aNew:|r " form. No {braces}: the
-- page is rich markup (they are turned into parentheses there), except a
-- link to a part of BigNoteBox (ALL-617): {link*bnbui:settings.modules.spelling*}
-- (empty text = the place's name) or {link*bnbui:<key>*<own text>}. Keys:
-- Developer tools > UI link list. A line that names a Settings page links it.
--
-- HOW TO UPDATE:
--   1. Change `version` to the new addon version string (must match Init.lua).
--   2. Replace the `entries` table with your new patch notes.
--   3. Each entry is a plain string. Prefix lines however you like:
--        "New: ..."   "Fixed: ..."   "Changed: ..."   "Removed: ..."
--   4. A line for one client only is a table instead of a string:
--        { forever = true, "..." }   -- WoW Forever only
--        { retail  = true, "..." }   -- Retail only
--        { classic = true, "..." }   -- Classic only
--      No "WoW Forever:" prefix needed; only that client sees the line.
--   That's it - no other files need to change for a routine version bump.
--
-- FORMAT RULES:
--   - Keep each entry to a single line of reasonable length.
--   - Plain ASCII only - no Unicode characters (they render as boxes in WoW).
--   - No markup but the BigNoteBox links above.
-- |cff66bb6aNew:|r
-- |cff66bb6aFixed:|r
-- |cff66bb6aChange:|r


local BNB = BigNoteBox

BNB.PATCH_NOTES = {
    version = "2.0.0",
    entries = {
        "|cff66bb6aNew:|r Explorer view: your notes as a grid of icons over the whole window, like a file explorer, with its own toolbar, multi-select, drag and drop, and a status bar. Turn it on or off in {link*bnbui:settings.modules.explorer*}.",
        "|cff66bb6aNew:|r Explorer view: Small, Medium and Large tiles, List, Details (sortable columns) and Flat, in the View menu.",
        "|cff66bb6aNew:|r Explorer view: View menu options to put pinned notes first without sections, or favorites first.",
        "|cff66bb6aNew:|r Explorer view: New folder with selection, and Remember the open note ({link*bnbui:settings.modules.explorer*})",
        "|cff66bb6aNew:|r Explorer view: with the Reference Box's auto-open on, clicking a note opens its Reference Box when it has attachments or tasks.",
        "|cff66bb6aNew:|r Folders: sort your notes into folders, with a color each, in the note list and the explorer. Folders come along in backups. {link*bnbui:settings.modules.folders*}.",
        "|cff66bb6aNew:|r The help book: every help topic in one book, with chapters, a search and a Glossary. Open it with the new Help button on the top bar or /bnb help.",
        "|cff66bb6aNew:|r Right-click a button on the formatting or rich toolbar to open its help topic.",
        "|cff66bb6aNew:|r The help book has a Features tab (what BigNoteBox can do, A-Z), which replaces the old Features window.",
        "|cff66bb6aNew:|r Patch notes: every release back to v1.6.9 in the help book's Patch notes tab. After an update a toast opens the new release there, and no pinned patch note is added to your note list any more.",
        "|cff66bb6aNew:|r Spelling: red wavy lines under misspelled words, English (US) or English (UK), as you type or with the Check spelling button. {link*bnbui:settings.modules.spelling*}.",
        "|cff66bb6aNew:|r Spelling: right-click a marked word for suggestions, Add to dictionary or Ignore, and a Correct spelling window that goes through them one by one.",
        "|cff66bb6aNew:|r Spelling: repeated words (the the) are marked, with options to ignore UPPERCASE words and words with numbers.",
        "|cff66bb6aNew:|r Spelling works in Focus mode and sticky notes too.",
        "|cff66bb6aNew:|r Key bindings: Check spelling (F9) and Correct spelling (F10)",
        "|cff66bb6aNew:|r Text shortcuts: type brb and it becomes \"be right back\". Make your own in {link*bnbui:settings.modules.spelling*}, with an \"Only with !\" option.",
        "|cff66bb6aNew:|r Find and replace in a note: Ctrl+F or the new button on the formatting toolbar, in the editor and Focus mode.",
        "|cff66bb6aNew:|r Rich notes: underline and strikethrough, two new buttons on the rich toolbar.",
        "|cff66bb6aNew:|r Rich notes: dividers, a new button on the rich toolbar.",
        "|cff66bb6aNew:|r Rich notes: a new code tag shows text exactly as typed, tags and all.",
        "|cff66bb6aNew:|r Links to BigNoteBox itself: the link button's new BigNoteBox tab links a note to a Settings page or window.",
        "|cff66bb6aNew:|r An open note has two new buttons: Note settings on the formatting toolbar, and Situation on the action bar.",
        "|cff66bb6aNew:|r Note right-click menu: Favorite, Pin, Lock, Rename and Delete are a row of icons at the bottom. Rename is new.",
        "|cff66bb6aNew:|r Sort menus: Reset sort, and Make this the default.",
        "|cff66bb6aNew:|r Note Capture: quest, book and dialogue notes can be rich notes, one setting per kind in {link*bnbui:settings.modules.quickNote*}.",
        "|cff66bb6aNew:|r Note Capture: quest notes show when you accepted or turned in the quest, its level and kind, a Wowhead address and a waypoint link.",
        "|cff66bb6aNew:|r Note Capture: the NPC's name in a quest or dialogue note links to that NPC's own note.",
        "|cff66bb6aNew:|r Note Capture: captured notes get the zone as a tag, and optionally the subzone.",
        "|cff66bb6aNew:|r What an NPC says now goes into that NPC's own note instead of a note of its own.",
        "|cff66bb6aNew:|r Dialogue UI: a BigNoteBox button beside its Copy Text button.",
        "|cff66bb6aNew:|r Player and NPC notes made from a target or inspect get dividers between their sections.",
        "|cff66bb6aNew:|r NPC notes are round like player notes, with an Elite or Rare frame (Retail and Forever)",
        "|cff66bb6aNew:|r Notes with Korean, Chinese, Japanese, Cyrillic or Greek text use a font that can show them, and get a language shield on the title row and tooltip.",
        "|cff66bb6aNew:|r {link*bnbui:settings.modules.accessibility*}: a new page, starting with Motion settings for the sticky note animation.",
        "|cff66bb6aNew:|r Smooth scrolling everywhere. Turn it off or change its speed under Accessibility > Motion.",
        "|cff66bb6aChange:|r BigNoteBox has a new icon and is listed under Notes & Organization in the game's AddOns list.",
        "|cff66bb6aChange:|r BigNoteBox windows and sticky notes come to the front when clicked, like normal windows.",
        "|cff66bb6aChange:|r The main window and toasts get better default positions and sizes on ultrawide screens.",
        "|cff66bb6aChange:|r Search boxes have a round X to clear them.",
        "|cff66bb6aChange:|r Hiding and showing sticky notes is animated.",
        "|cff66bb6aChange:|r The minimap button's situation count is a big green number in the middle of the icon.",
        "|cff66bb6aChange:|r Setup wizard: two fewer questions on the Notes & behavior page.",
        "|cff66bb6aChange:|r Focus mode: a status bar at the bottom, more room for the note, and a two-row toolbar with the font picker.",
        "|cff66bb6aChange:|r Player notes have a round icon, matching the live portrait shown while that player is targeted.",
        "|cff66bb6aChange:|r The note list's sort now sorts your pinned notes too.",
        "|cff66bb6aChange:|r Collapsing the note list clears the search and filters.",
        "|cff66bb6aChange:|r Export from a note's right-click menu goes straight to the copy popup.",
        "|cff66bb6aChange:|r Deleting several notes at once leaves locked notes alone.",
        "|cff66bb6aChange:|r Importing a backup: a settings profile with a name you already have can replace yours or be added as a copy.",
        "|cff66bb6aChange:|r Reference Box: the model viewer says \"Loading...\" while an NPC model loads.",
        "|cff66bb6aChange:|r Immersion: the Note Capture button sits on the corner of Immersion's text box, so it no longer covers the text.",
        "|cff66bb6aChange:|r Simplified Chinese: everything new in 2.0 is translated.",
        "|cff66bb6aFixed:|r Sticky notes: text color, font, size, outline, shadow and alignment changes show again.",
        "|cff66bb6aFixed:|r Changing the font in Settings no longer resets every open sticky's own font.",
        "|cff66bb6aFixed:|r Sticky notes: the Line height setting works.",
        "|cff66bb6aFixed:|r Note Settings: font changes on a rich note show at once.",
        "|cff66bb6aFixed:|r The rich note preview wraps its text when you resize it.",
        "|cff66bb6aFixed:|r Tasks: the row's buttons no longer cover the task you are editing.",
        "|cff66bb6aFixed:|r Settings no longer goes blank after Focus mode.",
        "|cff66bb6aFixed:|r Search bar: the tag suggestions have a background.",
        "|cff66bb6aFixed:|r Settings profiles: pressing Enter in the name and Import boxes works.",
        "|cff66bb6aFixed:|r OLED Flat skin: grayed-out toolbar buttons are visible again.",
        { retail = true, "|cff66bb6aFixed:|r A crash to desktop when an NPC note's model was loading in the Reference Box." },
        { forever = true, "|cff66bb6aChange:|r Ready for the WoW: Forever launch: the beta notice is gone, and Report a bug sits beside the Settings window." },
        { classic = true, "|cff66bb6aFixed:|r Cursors that were wrong or drew as a black square." },
    },
}

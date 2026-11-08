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
    version = "2.1.0",
    entries = {
        "|cff66bb6aNew:|r German translation: BigNoteBox speaks Deutsch, the Help book and Features tab included. It follows a German game client, or pick it under Language in {link*bnbui:settings.general*}.",
        "|cff66bb6aNew:|r Spelling in French and German: install the new BigNoteBox Spelling Pack and pick the language in {link*bnbui:settings.modules.spelling*}.",
        "|cff66bb6aNew:|r German spelling understands compound words (Gildenbank, Questgeber), checks every noun with its capital, and a long misspelled word gets suggestions for the broken part. {link*bnbui:settings.modules.spelling*} can limit it to the compounds the German dictionary allows.",
        "|cff66bb6aNew:|r Each note can have its own spelling language: right-click a marked word, then Language, or use the new language button on the formatting toolbar. A note checked in another language than your game's shows that language's shield next to its title.",
        "|cff66bb6aNew:|r Move your notes over from SimpleNotepad and Siggis Notepad in {link*bnbui:settings.backup*} (Siggis Notepad's trashed notes go to the Trash).",
        "|cff66bb6aNew:|r Vendor notes: a new button on the vendor window saves everything the vendor sells (with prices and limited stock) in its NPC note and Reference Box, tagged Vendor. Click again on a later visit to update the list.",
        "|cff66bb6aChange:|r {link*bnbui:settings.modules.spelling*}: pick the language by clicking its flag (the dropdown is gone); every installed dictionary's flag is in color.",
        "|cff66bb6aChange:|r A note's hover tooltip shows one language line for each script in it (Korean, Chinese, Russian...).",
        "|cff66bb6aChange:|r Quest notes: the quest is a link heading at the top (right-click it to copy the Wowhead address), Objectives and Rewards get their own headings and dividers. Every rich capture note (quests, books, letters, dialogue) ends on a Notes part for your own words. From Dialogue UI too: its quest and rewards become game links with their icons, money shows as coins and XP with its icon.",
        "|cff66bb6aChange:|r Right-click a quest, item, spell or currency link in a note: Copy Wowhead URL.",
        "|cff66bb6aChange:|r Undo: the Forced interval slider now goes down to 0.5 seconds.",
        "|cff66bb6aChange:|r {link*bnbui:settings.backup*}: a line under the import box says that a large backup can make the game seem frozen for a moment.",
        "|cff66bb6aChange:|r {link*bnbui:settings.modules.tags*}: the tag tree settings and where the Tag Manager opens have their own page now (they were on the Notes tab).",
        "|cff66bb6aChange:|r Buttons fit their labels in every language: a long label gets a little smaller, and if it still does not fit it ends in ... with the whole text on hover.",
        "|cff66bb6aFixed:|r Rich notes: drop shadows and the note's own font (Note Settings > Appearance) now show in the rich view. A sticky's rich view follows its Sticky settings font and outline, like a plain sticky.",
    },
}

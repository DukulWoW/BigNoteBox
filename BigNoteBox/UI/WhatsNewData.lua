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
    version = "1.30.0",
    entries = {
        "|cff66bb6aNew:|r Settings profiles: Settings > Advanced starts with Profiles. Keep different settings and window layouts for different characters (a bank alt, a raider): clone the one you use or start a blank one with the setup wizard, rename, delete, and export / import a profile as a code to share. Every character starts on Default; the profile you pick is the one it loads with. Notes are shared by every profile, and the full JSON backup keeps every profile too (importing it adds them; one whose name you already have, such as Default, comes in as \"Default (1)\"). Danger Zone can reset just the profile in use, or all settings and profiles.",
        "|cff66bb6aChange:|r Right-click menus: the menu of an item or spell link, and of a Reference Box entry, shows its icon beside the name; a web link's menu leaves out https:// and www. so more of the address shows. The menu of a link to another note has Open as sticky note, Share note, Copy note to clipboard and Copy / Move to...",
        "|cff66bb6aChange:|r Right-click menus: an item, spell or other game link in the note you are editing (also in View and Focus mode) has Add to Reference Box. A web link's menu shows a link symbol in front of the address.",
        "|cff66bb6aChange:|r Reference Box: Insert at text cursor reads Insert at bottom of note until you click into the note's text, and puts the link on a new line at the end instead of being greyed out.",
        "|cff66bb6aChange:|r Focus mode: link menus work there. Share note, Send to Chat, Copy / Move and the copy box open over Focus mode, Add to Reference Box opens the box beside it, and rows that need a game window (item card, dressing room, chat line, map) close Focus mode first. Focus mode's bottom bar has the Reference Box and Add task buttons too.",
        "|cff66bb6aChange:|r Settings > Backup: three buttons, Full backup (notes, templates, tokens, tag colours and settings profiles), Settings backup (profiles only) and Selective backup (pick JSON or Markdown and which notes and parts go in). Each copies straight away with Ctrl+C. Importing a backup that holds more than notes shows what is in it, so you can untick parts.",
        "|cff66bb6aChange:|r Back up first, offered before an import or a migration, shows the copy popup: Ctrl+C copies your notes and the import goes on, Esc stops it.",
        "|cff66bb6aChange:|r Simplified Chinese: settings profiles, the new Backup page and the new right-click menu lines are translated.",
        "|cff66bb6aFixed:|r Reference Box: the right-click menu no longer opens under the entry's tooltip.",
        "|cff66bb6aFixed:|r Tags: a tag that starts with a Chinese (or other non-Latin) letter is no longer broken when it is added, and tags already broken this way are repaired. A backup of notes with such a tag no longer comes up empty.",
    },
}

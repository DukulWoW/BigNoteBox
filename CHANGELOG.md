# BigNoteBox v1.30.0

## All versions

### New
- Settings profiles: Settings > Advanced starts with Profiles. Keep different settings and window layouts for different characters (a bank alt, a raider): clone the one you use or start a blank one with the setup wizard, rename, delete, and export / import a profile as a code to share. Every character starts on Default; the profile you pick is the one it loads with. Notes are shared by every profile, and the full JSON backup keeps every profile too (importing it adds them; one whose name you already have, such as Default, comes in as "Default (1)"). Danger Zone can reset just the profile in use, or all settings and profiles.

### Change
- Right-click menus: the menu of an item or spell link, and of a Reference Box entry, shows its icon beside the name; a web link's menu leaves out https:// and www. so more of the address shows. The menu of a link to another note has Open as sticky note, Share note, Copy note to clipboard and Copy / Move to...
- Right-click menus: an item, spell or other game link in the note you are editing (also in View and Focus mode) has Add to Reference Box. A web link's menu shows a link symbol in front of the address.
- Reference Box: Insert at text cursor reads Insert at bottom of note until you click into the note's text, and puts the link on a new line at the end instead of being greyed out.
- Focus mode: link menus work there. Share note, Send to Chat, Copy / Move and the copy box open over Focus mode, Add to Reference Box opens the box beside it, and rows that need a game window (item card, dressing room, chat line, map) close Focus mode first. Focus mode's bottom bar has the Reference Box and Add task buttons too.
- Settings > Backup: three buttons, Full backup (notes, templates, tokens, tag colours and settings profiles), Settings backup (profiles only) and Selective backup (pick JSON or Markdown and which notes and parts go in). Each copies straight away with Ctrl+C. Importing a backup that holds more than notes shows what is in it, so you can untick parts.
- Back up first, offered before an import or a migration, shows the copy popup: Ctrl+C copies your notes and the import goes on, Esc stops it.
- Simplified Chinese: settings profiles, the new Backup page and the new right-click menu lines are translated.

### Fixed
- Reference Box: the right-click menu no longer opens under the entry's tooltip.
- Tags: a tag that starts with a Chinese (or other non-Latin) letter is no longer broken when it is added, and tags already broken this way are repaired. A backup of notes with such a tag no longer comes up empty.

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
    version = "1.18.0",
    entries = {
        "|cff66bb6aNew:|r A new icon picker in Note Settings: icons sorted into categories (Notes, Books, Classes, Races, Zones and more), with search. Tick \"All game icons\" to browse and search every icon in the game",
        "|cff66bb6aNew:|r A note can have several situations: the Situation tab lists them, with an Add row and an X on each, and the note shows when any one of them matches. A note with both places and players says \"When it starts / When it ends\". A new \"NPC / Mob\" situation works like Player, for notes about an NPC or a mob. A new \"Guild\" situation shows a note when you target, or group with, a player in that guild",
        "|cff66bb6aNew:|r New situations: \"Instance type\" (any dungeon, raid, delve (Retail) or battleground), \"Window open\" (vendor, bank, mailbox, auction house or trainer: shows a note when you open it, or when you close it) and \"Rested\" (in an inn or a city)",
        "|cff66bb6aNew:|r The character sidebar can sit on top of the main window as long tabs: each tab shows the character's icon, name and note count, with the same tooltip and right-click menu. With many characters the tabs get smaller, and the rest are in a \"More...\" menu at the end; picking a character there moves it to the front. Choose Top, Right or Left in Settings > Modules > Character sidebar",
        "|cff66bb6aChange:|r The main window's resize grip is bigger, with its own hover and pressed look",
        "|cff66bb6aChange:|r The divider lines in the note editor now all match: one thin grey line, the same as the Pinned divider in the note list",
        "|cff66bb6aChange:|r Note icons now come from the game itself, so the download is about 20 MB smaller. Your notes keep their icons",
        "|cff66bb6aChange:|r The New note window and the Insert icon window use the new icon picker. In Insert icon, type a full game icon name or file id into the search and press Enter to use any icon in the game",
        "|cff66bb6aFixed:|r The rich note live preview is no longer covered by the sidebar icons",
        "|cff66bb6aFixed:|r Typing a sub-zone in the Situation tab now suggests sub-zones (every area the game knows, in your language) instead of zone names",
        { retail = true, "|cff66bb6aNew:|r A metal header strip behind the sort menus and toolbar icons at the top of the main window (normal mode); the header is a little taller to fit it" },
        { forever = true, "|cff66bb6aNew:|r A quest log header strip behind the sort menus and toolbar icons at the top of the main window (normal mode)" },
        { forever = true, "|cff66bb6aChange:|r The icon lists show only the races in the game (the original eight), and a few newer icons the game does not have are gone; a note that used one shows the default icon" },
    },
}

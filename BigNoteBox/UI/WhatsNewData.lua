-- BigNoteBox UI/WhatsNewData.lua
--
-- EDITABLE PATCH NOTES FILE
-- Update this file before each release. The WhatsNew window reads it directly,
-- and after an update it becomes the pinned patch note (ALL-409, UI/WhatsNew.lua):
-- lines are grouped under their New / Change / Fixed label there, so keep the
-- "|cff66bb6aNew:|r " form. No {braces}: that note is a rich note (they are
-- turned into parentheses there).
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
--   - No markup - entries are rendered as plain GameFont text.
-- |cff66bb6aNew:|r
-- |cff66bb6aFixed:|r
-- |cff66bb6aChange:|r


local BNB = BigNoteBox

BNB.PATCH_NOTES = {
    version = "1.29.0",
    entries = {
        "|cff66bb6aNew:|r Right-click a link in a note, rich or normal, for a menu: Send to chat, Show and Try on for items; Set waypoint, Show on map, Send to chat and Copy /way for waypoints; Open note and Share to chat for links to other notes; Send to chat and Copy link for web links.",
        "|cff66bb6aNew:|r The right-click menu in the note text now holds the note token groups, the same as the toolbar's token button, in place of the old insert rows; new token {{datetime}} for the date and time together.",
        "|cff66bb6aNew:|r Links to other notes show in that note's title colour, and follow it when it changes.",
        "|cff66bb6aChange:|r Note tokens in a normal note become their value as you type or pick them (your gold, an item's link, your own tokens); rich notes keep them live and filled each time they are shown. A rich note made normal gets the values of that moment.",
        "|cff66bb6aChange:|r Clicking an item or other game link in a normal note works as in a rich note (the card, Ctrl+click to try it on); Shift+click sends a link to chat in both, opening the chat line if it is closed.",
        "|cff66bb6aChange:|r Send to chat goes straight into BigChatBox's chat line when BigChatBox is on.",
        "|cff66bb6aChange:|r Reference Box right-click menus show the entry's name at the top and an icon on every row.",
        "|cff66bb6aChange:|r The note token lists call their groups Here and now and Character, and their tooltips say how tokens fill in rich and normal notes.",
        "|cff66bb6aChange:|r The note toolbar's overflow menu uses short names (Restore point, History, Alarm, Copy / Move, Share, Show on map); the longer text is in the tooltip.",
        "|cff66bb6aChange:|r Settings > Backup shows the Rescue section only while there are notes to rescue, at the top of the page, so the page no longer needs a scrollbar.",
        "|cff66bb6aChange:|r Simplified Chinese: everything added since the last translation is translated (templates, tags, note tokens, links, Rescue and more).",
        "|cff66bb6aFixed:|r Up and Down move through the token list again in notes, Focus mode, sticky editing and the tl;dr boxes.",
        "|cff66bb6aFixed:|r Pressing Enter at the bottom of a note scrolls the note along, so the line you are typing stays in view.",
        "|cff66bb6aFixed:|r Clicking the note title to rename it frames only the title, not the tl;dr line above it.",
    },
}

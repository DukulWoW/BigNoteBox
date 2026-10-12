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
    version = "1.24.0",
    entries = {
        "|cff66bb6aNew:|r Item, spell and quest links in rich notes can be clicked as in chat: click shows the item card, Shift+click puts the link in chat, Ctrl+click opens the dressing room.",
        "|cff66bb6aNew:|r Hover an item, spell or quest link in a plain note to see its tooltip.",
        "|cff66bb6aNew:|r Shift+click an item while typing in a note to put its link in the text.",
        "|cff66bb6aNew:|r An item, spell, quest or pet you drop or Shift+click into a note is also added to its Reference Box (Settings > Reference Box, on by default).",
        "|cff66bb6aNew:|r A Reference Box button in the editor toolbar lists the note's Reference Box entries: click one to put it into the text at the cursor. Alt+click an entry in the Reference Box does the same.",
        "|cff66bb6aNew:|r Mounts and your own battle pets dropped into a note are links too.",
        "|cff66bb6aNew:|r Gear in inspect notes is made of item links: hover for the tooltip of the item as worn. Older notes get them with \"Update gear and note\" on the next inspect.",
        "|cff66bb6aNew:|r Skin mode: a new OLED Flat skin, pure black with no borders or divider lines.",
        "|cff66bb6aNew:|r Player notes say where you met the player, and both player and NPC notes get a /way line to the spot (a clickable link in rich notes).",
        "|cff66bb6aChange:|r Skin mode: the Markup and Note tabs under a rich note follow the skin brightness, and their icon and label are centred.",
        "|cff66bb6aChange:|r Skin mode: the selected tab in Settings shows its name in the skin's heading colour, so it reads well on every skin.",
        "|cff66bb6aChange:|r Undo and Redo remember each note's history for the whole session, also after switching notes, using Focus mode or editing the note as a sticky.",
        "|cff66bb6aChange:|r On a narrow main window the editor toolbar hides its right-hand buttons, then the font and size pickers, instead of drawing them over each other.",
        "|cff66bb6aFixed:|r The rich note icon beside a note's title shows its tooltip again, instead of a click on it opening the title for editing.",
        "|cff66bb6aFixed:|r An item dropped on the empty part of a note, below the text, is added at the end instead of being lost.",
        "|cff66bb6aFixed:|r Reference Box > Insert at text cursor now counts as a change to the note and can be undone.",
        "|cff66bb6aFixed:|r The green edit glow on a sticky note sometimes did not show until you scrolled or moved the cursor.",
    },
}

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
    version = "1.22.0",
    entries = {
        "|cff66bb6aNew:|r Alarms: set the defaults for new alarms (snooze time, glow type, glow mode, glow colour) in Settings > Modules > Alarms. Alarms set to \"Default\" follow them.",
        "|cff66bb6aNew:|r Alarm popup: alarms waiting their turn show as bars under the popup. Click one to show it now.",
        "|cff66bb6aNew:|r Before an import or a migration, BigNoteBox offers to save a backup of the notes you already have.",
        "|cff66bb6aNew:|r Rich notes: /way lines (as TomTom and Wowhead write them, \"/way Zone 45.2 60.1\" or \"/way #84 45.2 60.1\") are clickable links. Click to place the waypoint (TomTom, or the game's map pin), Shift+click to see it on the world map.",
        "|cff66bb6aNew:|r Situations > Waypoints: \"Show on map\" in a waypoint's right-click menu, or Shift+click the row, opens the world map with a marker on the spot.",
        "|cff66bb6aNew:|r Situations: the player name box suggests your friends (Battle.net friends too), your guild and your group, in class colours.",
        "|cff66bb6aNew:|r Rich notes: broken formatting tags (a {p} never closed, a {/p} closing a heading, a close tag with nothing open) show as \"Markup: N to fix\" next to the word count, with the details on hover. They are fixed in the text when you open another note or close the window; Note History keeps the text from before.",
        "|cff66bb6aNew:|r Settings > Advanced > Addon integrations: a page of its own with one section per addon (BigChatBox, TomTom, WaypointUI), with its logo, what it does and whether it is active, and the tab shows how many you have. An addon you do not have has a button that copies its CurseForge link.",
        "|cff66bb6aNew:|r Reference Box: add mounts and battle pets straight from the Collections journals (drag them in or Shift+click), with their model.",
        "|cff66bb6aChange:|r Set alarm: \"Every N days\" has < > buttons to change the number.",
        "|cff66bb6aChange:|r Situations: Add with nothing typed adds where you are now (zone, sub-zone, instance) or your target (player, NPC, guild).",
        "|cff66bb6aChange:|r Danger Zone: the confirm button says how much it changes, like \"Delete all 312 notes\".",
        "|cff66bb6aChange:|r Copy boxes from link buttons show the start of the link you are copying.",
        "|cff66bb6aChange:|r Skin mode: text buttons look pressed while held (the label moves down a pixel).",
        "|cff66bb6aChange:|r Sticky notes: the border has its own opacity slider (Appearance), so the background opacity no longer fades the border.",
        "|cff66bb6aChange:|r Sticky notes: the scrollbar shows only while the pointer is over the note.",
        "|cff66bb6aChange:|r Sticky notes: the window border is picked from a thumbnail grid with < > arrows, as the background is. Note Settings' icon frame row has the < > arrows too.",
        "|cff66bb6aChange:|r Skin mode: slider tracks are see-through (70%) instead of solid black.",
        "|cff66bb6aChange:|r Skin mode: the OLED preset's softer white also reaches sticky note text that still has its default colour.",
        "|cff66bb6aChange:|r Changing the note font updates skin-mode button labels and the welcome screen at once, without a reload.",
        "|cff66bb6aChange:|r NPC notes show the creature's portrait again (switched off in v1.21.1 while a crash was tracked down).",
        "|cff66bb6aChange:|r The toast position anchor is now exactly the size of a toast: a see-through box in normal mode, the skin's colours in skin mode.",
        "|cff66bb6aChange:|r Esc closes the window in front first: Settings or Trash opened over Note History now close before it.",
        "|cff66bb6aChange:|r The note list collapses on its own when the main window is made narrower than 530, and comes back when you widen it again.",
        "|cff66bb6aChange:|r Settings > General: BCB Integration moved to Advanced > Addon integrations; a smaller More Features button sits beside Language.",
        "|cff66bb6aChange:|r Settings tooltips: what a checkbox does when on and when off is shown as two paragraphs, with On: and Off: in green (or the skin colour).",
        "|cff66bb6aFixed:|r Import: pressing Esc on the \"notes for another character\" question now cancels the import instead of importing.",
        "|cff66bb6aFixed:|r Skin mode: the font cards in Note Settings and sticky note settings use the skin's colours instead of the old green.",
        "|cff66bb6aFixed:|r Target notes: a note imported from a file is found again when you make a note of the same NPC (it asks first instead of making a silent \"(Duplicate)\"), and a repeated press for the same target makes one note.",
        "|cff66bb6aFixed:|r Mount stands (one NPC ID shared by several invisible mounts, like the Orgrimmar Trading Post): each stand gets its own note, and the Reference Box shows its mount instead of an empty viewer.",
        { retail = true, "|cff66bb6aNew:|r MapPinEnhanced support (version 4.0 and newer): situation waypoints go to MapPinEnhanced as named pins in a BigNoteBox group, several at once, \"Don't track it\" is respected, and they are removed again when you leave. Navigate, Show on map and the coordinate button use it too. Settings > Advanced > Addon integrations has a MapPinEnhanced section, which says \"Needs update\" for older versions." },
        { forever = true, "|cff66bb6aChange:|r Skin mode: the beta notice is drawn in the skin's look." },
        { forever = true, "|cff66bb6aChange:|r Skin mode uses the plain action bar icons, as on Retail (the detailed Forever icons stay in normal mode)." },
        { classic = true, "|cff66bb6aChange:|r Skin mode: the beta notice is drawn in the skin's look." },
    },
}

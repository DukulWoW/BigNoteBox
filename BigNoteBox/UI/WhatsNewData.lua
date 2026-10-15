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
    version = "1.26.0",
    entries = {
        "|cff66bb6aNew:|r Undo and redo can be kept between sessions: switch it on under Settings > Modules > Undo / Redo and each note's undo steps are still there after a reload or logout, for 1 to 30 days (7 by default). It is stored by the new BigNoteBox History addon that comes with BigNoteBox, the page shows how much space it takes and lists every note that has saved steps (click a title to open the note, X to delete just that note's steps), and one button deletes it all.",
        "|cff66bb6aNew:|r Rescue notes: if notes ever disappear without being deleted (a damaged or replaced notes file), they can be brought back from BigNoteBox History: each with its newest text and everything else as it was at your last logout or reload (look, tags, tasks, Reference Box, situations, alarm, its character), plus a \"Rescued\" tag. An alarm that was due meanwhile does not ring, it is listed in the Alarms window. The Rescue list is on Settings > Modules > Note History, with a button to it on Settings > Backup and in the History window, and BigNoteBox offers it by itself at login if all your notes are gone. A note that is suddenly empty can get its text back the same way.",
        "|cff66bb6aNew:|r Settings > General: a Dukul.net button at the start of the link buttons under More Features copies the link to Dukul.net.",
        "|cff66bb6aNew:|r Data broker bars: BigNoteBox shows your note count and the notes for where you are in Titan Panel, XIV Databar and other data broker bars (pick what it shows, or icon only, under Settings > Advanced). Its tooltip, on the minimap button too, lists the notes here and the 10 last edited notes with their icons and title colours.",
        "|cff66bb6aNew:|r Player notes update themselves: targeting or inspecting a player with a note keeps their level, guild, item level and gear current, and the note counts how often you have met (First met, Last seen, Encountered, Updated). Only the part above the Notes heading changes; what you write under Notes is never touched. Settings > Modules > Player & NPC Notes. Typing above Notes warns you first, and the note's right-click menu can stop or restart the updates.",
        "|cff66bb6aNew:|r Ctrl+click a /way line in a normal note (editor, Focus mode or sticky) to place the waypoint; Ctrl+Shift+click opens the map at it.",
        "|cff66bb6aNew:|r Waypoint links and note links: two new editor toolbar buttons put a link at the cursor, in normal and rich notes. A waypoint link (where you stand, a place you type, or one of a note's waypoints) places the waypoint when clicked; Shift+click puts a map pin in chat, Ctrl+click copies it as a /way line, Alt+click shows it on the map. A note link opens that note (Shift+click as a sticky) and keeps working when the note is renamed; a deleted note's links turn grey, and Shift+click on one restores the note from the Trash. Player and NPC notes write the place you met as a waypoint link. Links are turned into map pins and plain text when a note is sent to chat.",
        "|cff66bb6aChange:|r The Undo / Redo settings moved from the Notes tab to their own page under Settings > Modules.",
        "|cff66bb6aChange:|r Note History (the earlier versions of your notes) is now kept in the BigNoteBox History addon instead of the notes file, so the notes file stays small. Your existing versions move over by themselves during your first two logins or reloads, nothing is lost. BigNoteBox History comes with BigNoteBox and should stay enabled: if it is missing or disabled, a notice says so at login and Note History is off until it is back.",
        "|cff66bb6aFixed:|r A player note open as a sticky or in the editor shows the new text at once after \"Update gear and note\", and unsaved changes to that note are no longer lost when you use it.",
        { forever = true, "|cff66bb6aFixed:|r The Reference Box no longer shows a Transmog gear list that repeats the regular gear on players with a ranged weapon and no transmog; inspect notes now list the ranged item." },
    },
}

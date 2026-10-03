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
    version = "1.16.0",
    entries = {
        "|cff66bb6aNew:|r Right-clicking the portrait of a player or NPC you have a note on now also offers \"Open BNB Sticky Note\"",
        "|cff66bb6aNew:|r Reference Box: \"Show model\" shows gear, mounts and battle pets in the model viewer on any note, turning slowly; grab it to turn, move or zoom, and it starts turning again 3 seconds after you let go. Gear is framed on its slot: a helm on the head, shoulders on the shoulders; weapons, shields and off-hands are shown on their own. Drag up and down to tilt, Shift+wheel to move it nearer, and hover the bottom of the viewer for turn, reset and animation buttons",
        "|cff66bb6aNew:|r Reference Box: clicking an entry now works like a link in chat: click to view it (model viewer, or its item window), Shift+click to put it in chat, Ctrl+click for the dressing room",
        "|cff66bb6aChange:|r Send to Chat sends party, raid, guild, officer and whisper lines a moment apart, so the server no longer drops lines of long notes, and shows a live count. Closing the window stops it",
        "|cff66bb6aChange:|r Send to Chat to Say or Yell sends one message per click on Send, since the game only allows those from a click",
        "|cff66bb6aChange:|r Direct Send paces itself to the server's limit, shows its progress, and tells you in chat when the note went out or why it could not be sent (player offline, blocked in an instance)",
        "|cff66bb6aChange:|r Typing in long notes is lighter: the word count, live preview and autosave wait for a pause in your typing instead of running on every key",
        "|cff66bb6aChange:|r The note list redraws only the note you are typing in, and only target notes when you change target, instead of the whole list",
        "|cff66bb6aChange:|r Note history now keeps the text, rich mode, tags and tasks of each version instead of a full copy of the note, so saved history takes far less space. Restoring a version leaves the note's icon, colours and font as they are now",
        "|cff66bb6aChange:|r Ticking a task or snoozing and dismissing an alarm no longer counts as editing the note, so it keeps its place in the \"Edited\" sort",
        "|cff66bb6aChange:|r Redrawn icon buttons (title bars, sticky headers, tasks, Reference Box, calendar), with a bronze edge on WoW Forever. In skin mode they now take the skin's colours, like every other skin button, instead of the stone look",
        "|cff66bb6aChange:|r Skin mode: the main window's title bar is now as tall as every other window's",
        "|cff66bb6aChange:|r Reference Box: item tooltips now open beside the window on the main window's side, with the \"Equipped\" comparison next to them, so they no longer cover the list",
        "|cff66bb6aFixed:|r Direct Send with auto-reject on printed one chat line for every piece of an incoming note; now one per note",
        "|cff66bb6aFixed:|r Situation waypoints were set again on every target change, taking the map tracking away from your quest",
        "|cff66bb6aFixed:|r Player situations now match members of a 5-player party, not only a raid, and are checked when someone joins",
        "|cff66bb6aFixed:|r Inspect notes for a party member you had not targeted were built from your target instead",
        "|cff66bb6aFixed:|r The book button stayed greyed out for the rest of the session if the book was closed while it was reading the pages",
        "|cff66bb6aFixed:|r Opening and closing sticky notes, ticking tasks and opening Settings used a little more memory every time, for the whole session",
        "|cff66bb6aFixed:|r A zone change checked your note situations two or three times over",
        "|cff66bb6aFixed:|r Hovering a sticky with high opacity snapped to full instead of fading; every hover fade now takes the same short time",
        "|cff66bb6aFixed:|r Hiding a character from the sidebar now shows in Settings > Modules > Character sidebar's Hidden characters list at once",
        "|cff66bb6aFixed:|r A sticky showing its tasks went blank when the last task was cleared or deleted; it now goes back to the note",
        "|cff66bb6aFixed:|r The maximum number of open sticky notes now starts at 20, the same value its Reset button gives",
        "|cff66bb6aFixed:|r Character sidebar on the left: small icons sat off-centre, and in normal mode the bar stood away from the main window",
        "|cff66bb6aFixed:|r Skin mode: the Reference Box's Model and Tasks tabs could draw over the window's edge",
        "|cff66bb6aFixed:|r The main window could jump toward the top of the screen as soon as you started dragging it",
        "|cff66bb6aFixed:|r The main window sometimes opened in the middle of the screen at its default size instead of where you left it",
        "|cff66bb6aFixed:|r Focus mode: the dark AFK screen now goes away when you move the mouse, as it was meant to",
        "|cff66bb6aFixed:|r A situation alert that fired again while the previous one was fading out vanished straight away",
    },
}

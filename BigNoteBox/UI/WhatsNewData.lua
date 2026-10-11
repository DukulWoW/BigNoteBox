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
    version = "1.23.0",
    entries = {
        "|cff66bb6aNew:|r The top bar's Send button opens a note search: type a name, pick the note with the mouse or the arrow keys, and it goes straight to the Send to Chat window, no need to open it first.",
        "|cff66bb6aNew:|r Oracle prefix \"m\" sends the note you pick to the Send to Chat window.",
        "|cff66bb6aNew:|r After an update, the patch notes no longer open a window over the screen: they come as a pinned, favourite note (tagged Bnb and the version number) and a toast that waits for your click. The next update replaces that note, unless you edited it or removed its Bnb tag. The What's New window is still on the version button in Settings > General.",
        "|cff66bb6aNew:|r Settings > Modules > Toasts: \"Messages from BigNoteBox\" turns the update and welcome toasts off (the notes are still made).",
        "|cff66bb6aNew:|r A fresh install starts with a welcome note from Dukul, pinned at the top, with a toast pointing to it.",
        "|cff66bb6aNew:|r Settings > General: buttons under More Features copy the link to BigNoteBox on GitHub, CurseForge, Wago and WoWInterface.",
        "|cff66bb6aNew:|r tl;dr notes: give a note one short line (up to 80 characters) at the top of Note Settings > Situation, typed or picked from a list of snippets (KOS, Friendly, Avoid, Vendor / trader and more). It shows under the note title, in the game tooltip of the player or NPC the note is about, on the note icon at the Target and Focus frames, and on the note's situation toast. Settings > Modules > tl;dr turns it on or off, chooses where it shows and edits the snippet list.",
        "|cff66bb6aNew:|r Hovering a note in the note list shows a small box with its tl;dr, next alarm, situations and waypoints; hovering the note icon on the Target or Focus frame shows the same box. Settings > Modules > tl;dr, \"Note details when hovering the note list\" turns the list box off.",
        "|cff66bb6aNew:|r Toast styles in a picker: on Settings > Modules > Toasts and in a note's Toast window, click the style name to see every style as a real toast, two side by side (the name shows on hover). Click one to use it, double-click to use it and close, Revert to go back; the arrows beside the name step through them. \"Follow my faction\" / \"As in Settings\" sits in the picker too. A note's picker shows that note's own toast.",
        "|cff66bb6aNew:|r Situations can be on or off: on the Situation tab a green situation is on, a grey one is kept on the note but never shows. Click one to switch it, double-click to edit it.",
        "|cff66bb6aNew:|r Every new player or NPC note gets a situation for that player or NPC, off unless you choose otherwise: Settings > Modules > Situations has \"Turn on the player situation\" and \"Turn on the NPC situation\", each with \"Show the note as a toast\" under it. So a KOS note is: make the note, pick KOS as its tl;dr, done.",
        "|cff66bb6aNew:|r Note Settings > Situation, Show as: \"Show nothing\". The situation still marks the note and places its waypoints, but no toast or sticky pops up.",
        "|cff66bb6aChange:|r Toasts that pop up together (at login, entering a zone) now come in one after another and leave one at a time, oldest first, instead of all at once.",
        "|cff66bb6aChange:|r Toasts waiting for room show as a small \"+N\" box after the last toast, counting down as they come in. A toast's list (tasks, grouped situations) is a box of its own, dark like a sticky note, or in your skin's colours in skin mode.",
        "|cff66bb6aChange:|r BigNoteBox's code is now licensed under the GNU GPL v3 (it was MIT). The logo and icon are All Rights Reserved; the rest of the art is Blizzard's. See LICENSE and LICENSE-ASSETS.",
        "|cff66bb6aChange:|r Suggestion lists take the arrow keys: Up / Down pick a row, Enter or Tab takes it, Esc closes the list (Situations add row, waypoint sub-zone, note list \"#\" tags, Send directly names).",
        "|cff66bb6aChange:|r Note Settings > Situations > Waypoints: clicking \"(Addon required)\" or the ? now opens Settings > Advanced > Addon integrations instead of a separate popup.",
        "|cff66bb6aChange:|r The collapsed note list shows a note's title when you hover it.",
        "|cff66bb6aChange:|r Toasts show in the upper left instead of the middle of the screen. A toast position you placed yourself stays where it is.",
        "|cff66bb6aChange:|r Settings > Advanced > Addon integrations lists DialogueUI and Immersion too, with what BigNoteBox does with each (Immersion is not listed on TBC Anniversary, which it has no version for).",
        "|cff66bb6aFixed:|r Alarm window: the day boxes under Repeat name the full day when you hover them (\"Ring on Monday\").",
        "|cff66bb6aFixed:|r Toasts growing Left or Right: a toast with a list (tasks, grouped situations) no longer sits higher than the others; its list is now a box of its own beside it.",
        "|cff66bb6aFixed:|r Rich notes in the main window no longer cut off the end of each line when opened (it only went away after resizing the window).",
        "|cff66bb6aFixed:|r A toast for a player note now shows the player's face while you have them targeted, as the note list does (it showed the plain note icon). Its right-click menu and alarm toasts too.",
        { forever = true, "|cff66bb6aChange:|r The language selector is back in the setup wizard and Settings > General: a forced language now stays through reloads." },
        { classic = true, "|cff66bb6aChange:|r Reference Box side tabs sit under the window edge." },
        { classic = true, "|cff66bb6aChange:|r Addon integrations no longer lists WaypointUI and MapPinEnhanced, which have no Classic version." },
        { classic = true, "|cff66bb6aChange:|r The icon picker has no \"All game icons\" list on Classic: almost none of those icons exist there, so Classic uses the curated icons." },
        { classic = true, "|cff66bb6aFixed:|r Three icon frames that do not exist on Classic (Golden Hunter, Solar Flare, Corner Ornament) are no longer offered there." },
        { classic = true, "|cff66bb6aFixed:|r Note Settings > Situations > Waypoints: without a waypoint addon, the red install hint no longer runs out of the window (the line is gone; \"(Addon required)\" says it)." },
    },
}

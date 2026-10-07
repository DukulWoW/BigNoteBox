# BigNoteBox v1.20.0

## All versions

### New
- BigNoteBox now runs on WoW Classic: Classic Era, TBC Anniversary and Mists of Pandaria Classic, as a beta.
- The setup wizard asks how you want to use BigNoteBox: Minimal (just write notes), Full, or Custom to pick each module yourself, with a tooltip on every module.
- Settings > Modules has Minimal, Full and Custom at the top: one click switches every module to that set.
- Alarms can be switched off in Settings > Modules > Alarms. Off hides every alarm button and menu entry and nothing rings; your alarms are kept. Switched back on, repeating alarms carry on from their next time and any other alarm that came due is listed in the Alarms window instead of ringing.
- Note History and Focus Mode can be switched off too, in Settings > Modules. Off hides their buttons and menu entries; Note History also stops saving new versions on logout and keeps the ones you have.
- Sticky Notes can be switched off in Settings > Modules. Off closes every sticky and hides every way to open one; notes set to open as a sticky (situations, alarms) show as a popup, and the quick note key opens the main window. Switched back on, the stickies that were open come back.
- Rich Notes can be switched off in Settings > Modules. Off shows every rich note as plain text with its markup visible, so you can still read and edit it, and hides every way to make a rich note. Your notes stay rich: switch it back on and they look as before.
- Player & NPC Notes can be switched off in Settings > Modules. Off hides the Inspect window button, automatic inspect notes, the unit menu entries and the target note key, plus the live target portrait and the Reference Box Model tab. Your player and NPC notes stay in the list as ordinary notes.
- Alarms have two new types, Daily reset and Weekly reset: they ring at the reset itself, every day or every week, with no date, time or Repeat to set. "WoW weekly reset" moved out of Repeat into these; existing weekly reset alarms carry on as Weekly reset.
- Situation waypoints have a Sub-zone column: Pin Here fills it from where you stand, and a double-click on it lets you type one with suggestions. Each waypoint now takes two lines (name and X, Y, then zone and sub-zone) and the list shows four.
- 43 new sticky backgrounds from the game, among them four holiday ones under a new Events tab, the four flight maps, quest parchments for Alliance and Horde, and marble, brick and wood.
- Sticky notes have a Normal/Rich button that shows a rich note as plain text or as rich text.
- Settings > Modules > Sticky Notes can hide the Minimize button and the new Normal/Rich button.
- Right-click a note > Open > Open Reference Box (also a choice for the Open click)
- Right-click the icon in the New note window to give the note an icon frame.
- Turning a rich note into a normal note can make a restore point first.
- Note History's compare shows which tags a restore adds and removes.
- Right-click the Transmog gear or Regular gear title in the Reference Box to copy all Wowhead links.
- Settings > Backup > Import takes a share code too and opens it in the share preview.
- Your own images for rich notes can live in a small addon of your own, so updates no longer wipe them (UserImages/README.txt shows how)

### Change
- The New note title is typed in the title colour you picked.
- Set Alarm: the Remove Alarm button reads Cancel until the alarm is saved, and Every N days is a plain number field.
- The Alarms toolbar button is greyed while no note has an alarm.
- Focus mode no longer has a Restore button (the X and Esc already take you back)
- The OLED skin lets you change Window opacity.
- New installs hide everything and minimize sticky notes when you enter combat.
- Background and icon frame pickers show a name only when you hover a tile.
- The waypoint status in Note Settings > Situation lists which waypoint addons are installed.
- Bigger section titles in the Reference Box.
- The Stone background now uses the game's own rock texture, which makes the download smaller.
- The AddOns list shows BigNoteBox's folders together as one group.
- The 12 old bundled sticky backgrounds are gone (there are plenty from the game now), so the download is smaller. Stickies that used one go back to a plain background in their own colour; you can delete the BigNoteBox_BGs folder from your AddOns.
- Three backgrounds have new names: Dragon Parchment, Sand Stone and Dirty Paper.
- New look for the character tabs above the main window, in normal and skin mode.

### Fixed
- In-game alarms rang only once, although they say they ring every day at that time.
- Border brightness above 100% did nothing; it now brightens all the way to 200%, and stickies, Note Settings and the Oracle all use the same 0-200% scale.
- Character tab note counts update at once when notes are created, deleted, restored or moved.
- Send to Chat sent a rich note's formatting tags; it sends plain text now.
- The dropdown in Remove character opened under the window.
- The Copy/Move list could show a character name with no checkbox.
- Sticky notes show the live portrait while the note's player or NPC is your target.
- The Reference Box listed the same gear twice for players with no transmog.
- Some NPC notes showed an empty model viewer.
- Shift-clicking links into the Reference Box works with the newer chat code.
- The setup wizard now closes the Reference Box along with the other windows.
- Importing a broken share code on the welcome screen now says what is wrong with it.
- Send to BigChatBox did nothing when BigChatBox's multi-line box is switched off; the toolbar button now opens Send to Chat instead.

## Retail only

### Fixed
- A Blizzard achievement error when making an inspect note after opening the achievement window.

## WoW Forever only

### Fixed
- The game could crash to desktop when switching from a rich note to another note.

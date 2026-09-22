# BigNoteBox v1.8.0

## New
- Support for WoW Forever, as a beta
- Simplified Chinese (zhCN) translation

## Change
- The setup wizard's background dimming is lighter, so the game world shows through
- The WaypointUI and TomTom buttons in a note's waypoint settings now open a copy box with the download link, instead of printing it to chat

## Fixed
- On Chinese and Korean clients, buttons and the welcome greeting showed boxes instead of text unless the font was set to WoW Default. They now always use a font that can show your language, and the font settings say which font to pick for your notes
- The font lists in the setup wizard and settings sometimes showed only Noto Serif on the first login, until a /reload
- Font outline names and a few note settings headers are now translated
- Pressing Esc in the setup wizard now asks "Are you sure?", the same as the close button
- The Waypoint Support window now closes with Esc and when its settings window closes, one window per Esc press
- A copy box could get stuck on screen if the window behind it was closed first. It now closes with that window, or with a click
- The "Hide entire WoW UI in focus mode" tooltip showed a stray line-break code instead of a line break
- Some English tooltips and hints showed a box where a dash should be
- WoW Forever: the glow around the What's New, Features and setup wizard windows was cut off at the top and bottom

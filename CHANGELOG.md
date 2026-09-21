# BigNoteBox changelog

This file is what the packager sends to CurseForge, WoWInterface and Wago as the release
description. Replace its contents with section 3 of the release's
`_filearchive\BigNoteBox_vX.Y.Z.md` before tagging, so all six destinations carry the same
wording.

## New
- Added a "WoW Default" font option that uses the game client's own font
- First-time users on Chinese, Korean and Japanese clients now default to the WoW Default font, so notes are readable without any setup

## Change
- Updated LibTourist to r348, adding the new Midnight zones, delves and portal coordinates
- Updated LibCustomGlow to MINOR 25, fixing the alarm glow on clients where the animation helper moved

## Fixed
- Right-clicking a task checkbox in RefBox opened the context menu and toggled the task at the same time
- Changing a task's reset type kept the old reset timestamp, so the first reset after the change could fire at the wrong time

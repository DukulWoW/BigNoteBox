BigNoteBox search bar themes
============================

Every theme is one folder here: its art plus a theme.lua that registers it.
Kilrogg, Alliance, Horde and The-Eye are the built-in ones.

The art (32x32 TGA on a 32 px grid, the ornament any size):

  s-bg  s-top  s-bottom  s-left  s-right
  s-top-left  s-top-right  s-bottom-left  s-bottom-right  s-ornament

The smallest theme.lua is a name and a folder:

  local Register = BigNoteBox.RegisterSearchTheme
  Register({ name = "My theme", folder = "MyTheme" })

It then uses Eye of Kilrogg's layout, which fits art drawn on the same
32 px grid. To tune it: debug mode on, /bnb searchlayout, pick it with the
Theme button, adjust, and press Export. That gives the full Register call
with layout and size, to paste into theme.lua in place of the short one.

A theme without an ornament: files = { ornament = false }.

Optional middle pieces: s-top-ornament and s-bottom-ornament sit in the
middle of the top and bottom edge, with the edge art on either side:

  topleft  top  topornament  top2  topright

top2 / bottom2 reuse s-top / s-bottom. A theme using them needs its own
layout (The-Eye is the example). Any piece a layout leaves out is simply
not drawn, e.g. The Eye has no topleft, bottomleft or right.

The results panel under the bar: panelPos = { left, right, gap } in
screen px moves its edges in from the bar's (negative = wider) and sets
the space below the bar (negative = overlap). Up to four ornaments around
it, s-panel-ornament-1 .. -4 (pieces pornament1-4), are placed relative to
the panel. Hang a results ornament from the edge it belongs to (BOTTOMLEFT
for one on the bottom edge; the tool's Anchor button does it without
moving the piece): the panel grows and shrinks with the number of results.
The layout tool edits and exports all of this.

Ornament depth: layer = "back" on an ornament's layout line draws it
behind the borders, layer = "top" over everything, the other frame too
(the tool's Depth button).

A background of its own for the results panel: panelBg = "s-bg-results".
It is tiled, not stretched, so its size must be a power of two (128x128...),
and the Forever highlight glow is drawn over it.

The selected result is tinted with highlight = { r, g, b, alpha } (0-1
each). Left out, it is BigNoteBox gold. The tool's Highlight swatch and
Alpha box set it.

Where the results sit inside the panel art: panelPad = { left, right,
top, bottom } in screen px (the tool's "content" item). Left out, 0.6 x
the panel border on each side.

An unfinished theme: hidden = true keeps it out of the player's theme
picker in Settings; the layout tool still lists it.

A theme without art
-------------------
type = "backdrop" draws the bar and the results the way a sticky note is
drawn: a border around a background colour or texture, with the sticky
settings' own options. No folder, no files, but an id is required:

  Register({ id = "mybox", name = "My box", type = "backdrop", backdrop = {
      border = "Blizzard Tooltip", borderScale = 100, borderOffset = 3,
      borderLight = 0,
      bgR = 0.07, bgG = 0.07, bgB = 0.09, alpha = 0.96,
      bgTexture = "none", bgColorOpacity = 1, bgBrightness = 0,
      highlight = { 0.40, 0.73, 0.42, 0.18 },
      font = "lsm:Friz Quadrata TT", fontSize = 16,
  } })

border: "Default" (Blizzard's window border), "None", or a
LibSharedMedia border name / texture path. borderScale is its thickness
in % (1-200), borderOffset the px between the edge and the background
(0-12), borderLight its brightness -100..100 (0 = as drawn, below
darkens, above adds a lighter copy on top). bgTexture is a key from the
sticky note background list (UI\StickyBackgrounds.lua; "windowbg" = the
main window's own background), bgColorOpacity how much the colour tints
it (0-1), bgBrightness its brightness (-1..1), alpha the background's
opacity (0-1). font is "lsm:<name>", "bnb:<BigNoteBox font id>" or left
out for WoW's font. Anything left out takes the Default style's value
(Default border, windowbg background). The built-in "Custom border" theme
is this type, set by the player in Settings.

Your own theme
--------------
WoW only loads the files an addon's .toc lists, and an addon update
replaces this whole folder. So a theme of your own belongs in a small addon
of its own:

  MySearchTheme\MySearchTheme.toc   (## Dependencies: BigNoteBox, then theme.lua)
  MySearchTheme\theme.lua           Register({ name = ..., path = "Interface\\AddOns\\MySearchTheme\\" })
  MySearchTheme\s-bg.tga ...

path takes the place of folder and points at your art.

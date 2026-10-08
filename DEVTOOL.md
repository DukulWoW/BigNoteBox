# BigNoteBox Developer Tools

> [!WARNING]
> **You do not need this to use BigNoteBox.**
>
> `BigNoteBox_Dev` is a separate addon for people working on BigNoteBox itself: testing a change,
> making art for it, or tracking down a bug. It adds test windows and labs that are unfinished by
> design, prints extra text to chat, and can create fake data.
>
> **While it is enabled, BigNoteBox uses a separate copy of your notes.** Anything you write in dev
> mode stays in that copy and is not in your own notes. Disable `BigNoteBox_Dev` and reload to get
> your own notes back.
>
> If you only want to play with notes, close this page. Nothing in BigNoteBox needs the dev addon.

---

## What it is

BigNoteBox ships as three folders: `BigNoteBox`, `BigNoteBoxDB` and `BigNoteBox_Icons`. The
developer tools are a fourth folder, `BigNoteBox_Dev`, which is never part of the CurseForge,
WoWInterface or Wago download. With it enabled, BigNoteBox runs in **dev mode**:

- **A separate notes set.** The first dev-mode login copies your notes into the dev addon's own
  saved variables (`BigNoteBoxDevDB`). From then on dev mode reads and writes only that copy, so a
  test cannot touch your real notes. The copy is made once and never refreshed.
- **Settings are shared.** Settings (`BigNoteBoxDB`) are the same in both modes, so a setting
  changed in dev mode is changed for normal play too.
- **Debug mode is always on.** It is switched on at every load while the dev addon is enabled.
- **Settings > Advanced > Developer Tools** opens the tools page (also `/bnb debug`). `/bnb devtools`
  opens the same tools in a window of their own, without Settings.
- The main window title says *Development Mode Enabled*, and the main window, Settings and the
  Developer Tools window get a tiled overlay, so you always know which notes you are looking at.

## Debug mode without the dev addon

Debug mode alone does not need the dev addon. Switch it on in **Settings > Advanced > Activate
debug mode**, or with `/bnb debug on` (and `/bnb debug off`). It lasts until the next reload or
login. It turns on the debug slash commands and shows a missing translation as `!!KEY`.

**Translators:** the *Debug pseudo-locale* checkbox under it puts `@@` in front of every translated
string, so any text without the marker is still hard-coded and needs a locale key. It needs a
reload to reach windows that are already built.

## The tools page

**Options**

| Option | What it does |
|---|---|
| Test waypoint system | Prints waypoint debug info to chat; `/bnb testwp status / fire / leave / auto` |
| Debug Immersion button position | Prints the saved offset whenever you shift-drag the Immersion button |
| Trace situation checks | Prints a `[ctx]` line for every situation check, sticky and toast; survives reloads |

**Labs** (each Exports its result as Lua to paste into the addon)

| Lab | What it is for |
|---|---|
| Background Lab | Game textures for sticky note backgrounds (`/bnb bglab`) |
| Icon Lab | Measures game art for note icon frames (`/bnb iconlab`) |
| Toast Lab | Builds toast styles (`/bnb toastlab`) |
| Search Bar Layout Tool | Places the art of the Oracle search bar themes (`/bnb searchlayout`) |

**Tools and tests**

| Tool | What it does |
|---|---|
| Fire Test Toast | Runs a situation check as if you just arrived in your current zone |
| Open Setup Wizard | Opens the first-run wizard again |
| Seed Fake Migration Data | Fake notes for every supported note addon, then the Migrate popup (memory only) |
| Cursor Test | A hover box for each game cursor |
| Context Menu Test | A right-click menu with every kind of row |
| Top Tabs Test | Tuning panel for the sidebar tabs on top of the main window (`/bnbtabs`) |
| Skin Widgets Test | Skin-mode dropdowns and scrollbars (`/bnbskinw`) |
| Button Test | Every icon button symbol in each state (`/bnbbt`) |
| Icon Probe | Checks which note icon names exist on this client (`/bnbicons`) |

**Reload** reloads the UI; some options only take full effect after one.

## Download

1. Find the BigNoteBox version you have installed: the AddOn list, or the What's New window.
2. Open that version's release on the
   [GitHub releases page](https://github.com/DukulWoW/BigNoteBox/releases).
3. Download **`BigNoteBox_Dev-vX.Y.Z.zip`** from the release's *Assets*.

**Use the dev addon from the same version as your BigNoteBox.** The labs use BigNoteBox's internals,
which change between versions: a dev addon from another version can fail to load its tools or
throw errors.

The release zip leaves out one generated file, `Labs/IconLabAtlas.lua` (the atlas regions of every
game file, 1.6 MB). Without it the Icon Lab still works on its seeded files, but cannot look up the
atlas regions of a file you add yourself.

## Install

1. Unzip it into your `World of Warcraft\_retail_\Interface\AddOns\` folder (or the folder of the
   client you play: `_classic_`, `_classic_era_`, ...), next to the `BigNoteBox` folder.
2. Start the game, open the AddOn list and make sure **BigNoteBox Dev** is enabled.
3. Log in. The chat says how many notes were copied into the dev notes set.

## Going back to normal

Disable **BigNoteBox Dev** in the AddOn list and reload. BigNoteBox uses your own notes again.
The dev notes set stays in `BigNoteBoxDevDB` for next time; delete the addon folder and its saved
variables file (`WTF\Account\<account>\SavedVariables\BigNoteBox_Dev.lua`) to remove it completely.

## Found a bug?

Report it on [GitHub Issues](https://github.com/DukulWoW/BigNoteBox/issues) and say whether dev
mode was on.

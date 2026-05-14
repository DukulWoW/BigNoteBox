# BigNoteBox — Claude Code Project Context

## Project Overview

**BigNoteBox (BNB)** is a World of Warcraft notepad addon by Dukul. It is a companion to
**BigChatBox (BCB)** but does not require it. Notes surface contextually based on zone,
instance, or player name.

- **Target:** Retail WoW Midnight only.
- **Current version:** see `Init.lua` → `BNB.ADDON_VERSION`
- **SavedVariables:** `BigNoteBoxDB` (settings, shared across characters)
- **Notes DB:** `BigNoteBoxNotesDB` (owned by the companion addon `BigNoteBoxDB/`)

---

## Architecture

- Two-addon split: `BigNoteBox/` (main, owns settings DB) + `BigNoteBoxDB/` (owns notes DB)
- One TOC file: `BigNoteBox.toc`
- Modular structure: `Core/`, `UI/`, `Features/`, `Minimap/`, `Locales/`, `libs/`
- Skin logic is kept in separate files from core logic (e.g. `MainWindowSkin.lua` separate from `MainWindow.lua`)
- `SkinSystem.lua` loads first; all skin targets registered via `BNB.RegisterSkinRule` / `BNB.RegisterSkinTarget`

### TOC Load Order (key section)
```
Assets\Icons\IconManifest.lua
UI\BlizzardIconList.lua
UI\Widgets.lua
UI\IconsAC.lua
```

### DB Schema
- **SETTINGS:** v14 — bump `SETTINGS_SCHEMA_VERSION` in `Database.lua` and add a guarded migration block
- **NOTES:** v5
- Migration blocks are guarded: `if v < N then ... v = N end` inside `MigrateNotesDB()` / `MigrateSettingsDB()`

---

## Reference Addons

These are used as visual and code style references — do not copy blindly, but consult when patterns are unclear:
- **BigChatBox (BCB)** — primary visual and code style reference
- **TRP3** — SimpleHTML / HTMLFrame patterns
- **Horizon Suite** — SLUG font flag implementation
- **TooltipID, EnhanceQoL, Narcissus** — API pattern references
- **`AlarmManager.lua`** — working LibCustomGlow reference

---

## Companion Addon Detection

```lua
if BigChatBox and BigChatBox.SendDirect then
    -- BCB is loaded
end
```

---

## Code Style

- Dense but readable, consistent with BCB patterns
- `pcall` wrappers around non-critical features
- No unnecessary globals — everything in the `BigNoteBox` namespace
- UTF-8 without BOM for all files
- Plain ASCII only in all Lua string literals — no Unicode characters (they render as boxes in WoW)

---

## Workflow Rules

- Do not write or modify code until the approach is clearly agreed upon
- Ask questions instead of making assumptions
- State assumptions and risks explicitly before implementing
- Do not refactor large systems without approval
- Do not change behavior unless fixing a confirmed bug
- Only remove code if certain it is unused or redundant
- Never remove comments that explain intent or edge cases
- Do not truncate or summarize reported bugs, ideas, or suggestions
- No play-by-play commentary during coding — only surface important findings
- Split large responses across multiple replies rather than truncating

## Effort Scale

Use these labels (not numbers) for all backlog and task estimates:
**Trivial / Small / Small-Medium / Medium / Medium-Large / Large**

## Output Rules

- Return only files that were actually edited
- Always include file name, exact path, and line numbers or clear context for every change
- End every code delivery with a summary table:
  `| Filename | Location | Lines Changed | Changes |`
  Location column never includes the `BigNoteBox/` prefix — just the path within the addon
  (e.g. `Features/QuickNote.lua`, not `BigNoteBox/Features/QuickNote.lua`)
- Deliver handover documents as a `.md` file, never as inline chat text

## Debugging Priority

- When one item in a working group of identical items fails, check simplest differences first (asset names, nil fields) before diving into logic
- Diagnose root causes before proposing fixes — not symptoms
- Always verify changes survive when a file is touched again in the same session
- Cross-check actual source files rather than relying on session memory

---

## Critical WoW API Constraints (Midnight Retail)

- `UnitDisplayID` does NOT exist — use `SetCreature(npcID)`
- `DressUpModel:SetUnit()` MUST be pcall-wrapped
- `C_System.SetClipboard` is restricted — always use `BNB.ShowClipboardHint()`
- `GetSpellInfo` removed in TWW — use `C_Spell.GetSpellInfo(id)`
- `C_Item.GetItemLink` requires an `ItemLocation` object — use `GetItemInfo(id)` second return instead
- `ScrollFrameTemplate` manages scroll child height — never override; never call `SetSpacing()` on editboxes inside it
- `SetMinResize` does not exist on Midnight retail
- `MacroPopupFrame.iconDataProvider` is nil on Midnight retail
- `QUEST_LOG_SELECTION_CHANGED` does not exist on Midnight retail
- `QuestDetailFrame`/`QuestRewardFrame` replaced by `QuestFrameDetailPanel` on Midnight
- `WowStyle1DropdownTemplate` for dropdowns on retail — never `UIDropDownMenuTemplate`
- `RegisterForClicks` is Button-only — crashes on plain Frame widgets
- `FontString` uses `Show()`/`Hide()` — never `SetShown()`
- `CreateFont()` must be deferred to after `PLAYER_LOGIN`
- `HookScript` is cumulative — needs `_hooked` guard; never use `SetScript` where `HookScript` is appropriate
- `ScrollFrameTemplate` scrollbar renders outside frame bounds — use right clearance or left-side reanchor

---

## Lua 5.1 Gotchas

- `and false or true` ternary always returns `true` when the true-branch is `false` — use explicit `if/else`
- `pairs()` silently skips nil values — use `_clear` array pattern to nil note fields via `UpdateNote`/`UpdateTask`
- Multi-return truncation: `local a, b = X and Y()` loses `b` — use `if X then a, b = Y() end`
- `local function` must be defined before any closures that reference it as upvalues (`FadeTo` pattern)
- Colon-method-in-boolean expressions (e.g. `obj:Method and obj:Method()`) are invalid in Lua 5.1
- `\0` null byte as gsub sentinel acts as empty-pattern match — use safe multi-char placeholder e.g. `@@DNLBRK@@`
- `str_replace` on large blocks can leave orphaned code — always span from function declaration through closing `end`
- Unicode chars (ellipsis U+2026, em dash U+2014, Cyrillic homoglyphs) must never appear in WoW Lua string literals
- `HookScript` is cumulative — needs a `_hooked` guard to prevent double-registration
- `Narci.isActive = true` safely suppresses Narcissus AFK screensaver when needed

---

## SimpleHTML Rules

- `<P><br/></P>` for block spacing — plain `<P> </P>` collapses to zero
- Synchronous `GetWidth()` on a newly shown frame returns 0
- `swatchFunc` fires on every drag, not just OK

---

## Raw Texture / Icon Rules

- Raw `|T|t` escapes must never be embedded in EditBox body text — use `{icon}` markup instead
- `iconTex()` helper supports numeric fileIDs (pure-digit names skip the `Interface\ICONS\` prefix)
- `SetTexture()` = BLP files or standard textures; `SetAtlas()` = Atlas textures — cannot mix in the same script segment

---

## LibCustomGlow-1.0

Dot syntax only, never colon:
```lua
LibCustomGlow.AutoCastGlow_Start(frame, color, N, frequency, scale, xOffset, yOffset, key, frameLevel)
LibCustomGlow.AutoCastGlow_Stop(frame, key)
```
First arg is the target frame, not self. Passing the LCG table as first arg silently fails inside pcall.
See `AlarmManager.lua` for a working reference.

---

## Keyboard / Focus Routing

- Never put `EnableKeyboard(true)` on a TOOLTIP-strata frame if a focused editbox elsewhere needs those keys
- Every `OnKeyDown` handler with `EnableKeyboard(true)` must call `SetPropagateKeyboardInput(true)` for keys it does not handle
- Applies to all share/import/preview windows in `ShareNote.lua` and anywhere with `SetToplevel + EnableKeyboard`

---

## Clipboard Helper

```lua
BNB.ShowClipboardHint(content, anchorFrame, deferFocus)
```
- `deferFocus = true` defers `SetFocus`/`HighlightText` one tick via `C_Timer.After(0)`
- Use when the calling button's `OnClick` tick would steal focus back
- Helper editbox uses `InputBoxTemplate` (required for keyboard input on retail)

---

## MakeTexBtn Asset Names

`MakeTexBtn` appends `-normal` / `-hover` / `-pushed` to asset filenames and stores them as `_n` / `_h` / `_p`.
Desaturation/pcall code must use these keys, not `_tx`.
Always confirm required asset filenames (including suffixes) before Kim creates assets.

---

## Blizzard Icon Autocomplete (added v1.7.3)

- `BlizzardIconList.lua` — module-local `_BNB_RAW_ICON_LIST` holds the raw ~32k entry table
- `BNB.BlizzardIconList` — nil unless `db.blizzardIconComplete = true`
- `BNB.InitBlizzardIconList()` — called from `Events.lua` after `InitializeDB()`, nil-guarded
- `_iconAC` — module-local singleton popup in `IconsAC.lua`, shared by both locations
- Do NOT place `AttachIconAutocomplete` before any `AddPlaceholder` or `SetScript` call on the same editbox — `SetScript` silently destroys `HookScript` handlers
- Do NOT assume `FULLSCREEN_DIALOG` strata beats a `SetToplevel` frame — call `Raise()` at show time and on focus gain

---

## Bundled Fonts

Noto Serif (default), EB Garamond, Noto Sans, JetBrains Mono, OpenDyslexic,
Gloria Hallelujah, Fredoka Regular, Fredoka Bold, Playwrite IE Regular.
Future additions must be free Google Fonts.

---

## Bundled Libraries

LibDeflate, LibCustomGlow-1.0, LibSharedMedia-3.0, LibDBIcon, LibTourist-3.0,
LibStub, CallbackHandler, LibDataBroker, LibSerialize, LibAnimate.

**PTR watch:** LibDBIcon `error()` on PTR 12.0.7 — if it ships to live, change `error(...)` → `return`
on lines 10–11 of `libs/LibDBIcon-1.0/LibDBIcon-1.0.lua`.

---

## Open Bugs

| # | Bug | File | Effort | Fix |
|---|---|---|---|---|

---

## Backlog

| Feature | Effort | Notes |
|---|---|---|
| Quest-style floating task tracker | Large | Character/global/all toggle, context-aware by situation with manual override, eye-icon hide per character, note icon + title color matches note list, scalable/movable/lockable/dynamic width/configurable height, opt-in via main window top bar, minimizable with hover-reveal header, completion collapses or hides (config option), reset-aware, click task = toggle, click title = open note in BNB |
| Situation inheritance in TaskManager.OnContextChanged | Small | Falls back to `note.taskList.situation` when task has no situation set |
| Skin mode audit of task panel rows | Small | Task rows in RefBox and sticky not fully skin-aware |
| Warband Nexus integration | Medium | Read BNB char data from `WarbandNexusDB.global.characters`. Guard with `C_AddOns.IsAddOnLoaded`. No public API — reads internal DB directly |

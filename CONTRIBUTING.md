# Contributing to BigNoteBox

Thank you for helping! This page explains how to send a translation. Other kinds of changes are welcome too, but please open an issue first so we can agree on the idea before you write code.

## Translating

All text the player sees lives in `BigNoteBox/Locales/`:

| File | What it is |
|---|---|
| `enUS.lua` | English. The reference for every key. Please do not change this file. |
| `zhCN.lua` | Simplified Chinese |

Each line is one key and its text:

```lua
L["SAVE"] = "保存"
```

Only change the text on the right side. The key on the left (`"SAVE"`) must stay exactly as it is in `enUS.lua`.

### Rules

- **Keep placeholders.** `%s`, `%d` and `%%` are filled in by the addon. Every one in the English text must also be in your translation, in the same order.
- **Keep colour codes and line breaks.** Leave `|cffRRGGBB`, `|r` and `\n` where they are. You can move them to fit your sentence, but do not delete them.
- **Missing keys are fine.** Any key you do not translate shows in English, so a partial translation does not break anything.
- **Save as UTF-8 without BOM.**

### Adding a new language

Copy `enUS.lua` to a new file named after the WoW locale code (`zhTW.lua`, `koKR.lua`, `deDE.lua` and so on). `enUS.lua` always has every key, so you start from the complete list.

The top of `enUS.lua` sets up the locale system, and that part must not be copied. In your new file, delete everything above the first `L["..."]` line and put this there instead, with your own locale code:

```lua
-- BigNoteBox Localization -- Traditional Chinese (zhTW)

if GetLocale() ~= "zhTW" then return end

local L = BigNoteBox.L
```

Then translate. Say in your pull request that it is a new file, and Dukul will add it to the TOC files.

### Checking your work in game

Type `/reload` after changing the file. To see which text still is not translated, open the settings (`/bnb`), go to the **Advanced** tab, tick **Activate Debug mode** under **Developer**, then tick **Debug pseudo-locale** and `/reload`. Every string that goes through the locale file then starts with `@@`. Text without `@@` is hard-coded in the addon. Please report it so it can be moved to the locale file.

## Sending your changes

1. **Fork** this repository (the Fork button at the top right of the GitHub page).
2. Edit the locale file in your fork. You can do it directly on GitHub: open the file and click the pencil icon.
3. Open a **pull request** to `main` here. One language per pull request, please.

Dukul reviews every pull request before it is merged. Translations ship with the next release.

## License

BigNoteBox is MIT licensed. By sending a pull request you agree that your contribution is released under the same license.

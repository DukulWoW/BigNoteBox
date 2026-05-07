-- BigNoteBox Localization — English (Default)
-- This file defines ALL player-visible strings. Non-English locales override
-- only the keys they translate; missing keys fall back to English automatically.

BigNoteBox = BigNoteBox or {}
BigNoteBox.L = BigNoteBox.L or {}
local L = BigNoteBox.L

-- ── Addon identity ────────────────────────────────────────────────────────────
L["ADDON_NAME"]   = "BigNoteBox"
L["AUTHOR"]       = "by Dukul"
L["VERSION"]      = "Version"
L["LOADED_MSG"]   = "BigNoteBox v%s loaded! Type /bnb for options."

-- ── Shared UI ─────────────────────────────────────────────────────────────────
L["CLOSE"]        = "Close"
L["SAVE"]         = "Save"
L["DELETE"]       = "Delete"
L["CANCEL"]       = "Cancel"
L["OK"]           = "OK"
L["YES"]          = "Yes"
L["NO"]           = "No"
L["CONFIRM"]      = "Confirm"
L["RESET"]        = "Reset"
L["SEARCH"]       = "Search"
L["UNTITLED"]     = "Untitled Note"
L["NEW_NOTE"]     = "New Note"

-- ── Main window ───────────────────────────────────────────────────────────────
L["WINDOW_TITLE"]       = "BigNoteBox"
L["NOTE_LIST_EMPTY"]    = "No notes yet.\nClick New Note to get started."
L["SEARCH_PLACEHOLDER"] = "Search notes..."
L["NOTE_BODY_HINT"]     = "Start typing your note here..."
L["NOTE_TITLE_HINT"]    = "Note title"

-- ── Toolbar ───────────────────────────────────────────────────────────────────
L["BTN_NEW_NOTE"]       = "New Note"
L["BTN_SAVE_NOTE"]      = "Save"
L["BTN_DELETE_NOTE"]    = "Delete"
L["BTN_COPY_NOTE"]        = "Copy this entire note to your clipboard"
L["BTN_COPY_NOTE_DONE"]   = "Note copied to clipboard."
L["BTN_COPY_NOTE_CLASSIC"]= "Note selected — press Ctrl+C to copy."
L["BTN_SEND_TO_CHAT"]   = "Send to Chat"
L["BTN_COPY"]           = "Copy"
L["BTN_TAG"]            = "Tag"
L["BTN_CONTEXT"]        = "Context"

-- ── Tags ──────────────────────────────────────────────────────────────────────
L["TAGS"]               = "Tags"
L["TAG_ADD_HINT"]       = "Add tag..."
L["TAG_NONE"]           = "No tags"

-- ── Context binding ───────────────────────────────────────────────────────────
L["CONTEXT"]            = "Context"
L["CONTEXT_NONE"]       = "Anywhere"
L["CONTEXT_ZONE"]       = "Zone"
L["CONTEXT_INSTANCE"]   = "Instance"
L["CONTEXT_PLAYER"]     = "Player"

-- ── Send to Chat ──────────────────────────────────────────────────────────────
L["SEND_TITLE"]         = "Send to Chat"
L["SEND_CHANNEL_LABEL"] = "Channel:"
L["SEND_LINE_BY_LINE"]  = "Send each line as a separate message"
L["SEND_CONFIRM"]       = "Send %d line(s) to %s?"
L["SEND_CONFIRM_BTN"]   = "Send"
L["SEND_NO_BCB"]        = "Sending without BigChatBox (direct mode)"
L["SEND_EMPTY"]         = "Note is empty — nothing to send."
L["SEND_COMPLETE"]      = "Sent %d line(s) to %s."

-- ── Chat Capture ──────────────────────────────────────────────────────────────
L["CAPTURE_SAVED"]      = "Chat captured as note: %s"
L["CAPTURE_APPENDED"]   = "Appended to note: %s"
L["CAPTURE_EMPTY"]      = "Nothing to capture."
L["CAPTURE_MENU"]       = "Save to BigNoteBox"

-- ── Contextual surfacing ──────────────────────────────────────────────────────
L["CONTEXT_BADGE"]      = "%d note(s) for this area"
L["CONTEXT_TOAST"]      = "BigNoteBox: %d note(s) for %s"

-- ── Confirmations ─────────────────────────────────────────────────────────────
L["POPUP_DELETE_NOTE"]   = "Delete note '%s'? This cannot be undone."
L["BTN_DELETE_CONFIRM"]  = "Delete"
L["POPUP_RESET_ALL"]     = "Reset ALL BigNoteBox data? This deletes all notes and settings."
L["BTN_RESET_CONFIRM"]   = "Reset All"

-- ── Slash commands ────────────────────────────────────────────────────────────
L["SLASH_HELP"]          = "|cff66bb6aBigNoteBox|r commands:"
L["SLASH_HELP_OPEN"]     = "  /bnb — Toggle note window"
L["SLASH_HELP_NEW"]      = "  /bnb new — Create a new note"
L["SLASH_HELP_RESET"]    = "  /bnb reset — Reset all settings"
L["SLASH_HELP_CONFIG"]   = "  /bnb config — Open settings"
L["SLASH_RESET_DONE"]    = "All settings reset to defaults."
L["SLASH_NOTE_CREATED"]  = "New note created."

-- ── Minimap ───────────────────────────────────────────────────────────────────
L["MINIMAP_TOOLTIP"]     = "BigNoteBox"
L["MINIMAP_LEFT_CLICK"]  = "|cffffd100Left-click|r Toggle notes"
L["MINIMAP_RIGHT_CLICK"] = "|cffffd100Right-click|r New note"
L["MINIMAP_DRAG"]        = "|cffffd100Drag|r to reposition"

-- ── Config / Settings ─────────────────────────────────────────────────────────
L["CONFIG_TITLE"]           = "BigNoteBox Settings"
L["CONFIG_FONT_SIZE"]       = "Note body font size"
L["CONFIG_FONT_FAMILY"]     = "Note font"
L["CONFIG_AUTOSAVE"]        = "Autosave notes on switch"
L["CONFIG_CONTEXT_SURFACE"] = "Show contextual note alerts"
L["CONFIG_BCB_INTEGRATION"] = "Enable BigChatBox integration"
L["CONFIG_SHOW_MINIMAP"]    = "Show minimap button"
L["CONFIG_HIDE_LOGIN_MSG"]  = "Hide login message"

-- Config tab labels
L["CFG_TAB_GENERAL"]    = "General"
L["CFG_TAB_APPEARANCE"] = "Appearance"
L["CFG_TAB_FEATURES"]   = "Features"
L["CFG_TAB_EDITOR"]     = "Editor"
L["CFG_TAB_KEYBINDS"]   = "Keybinds"
L["CFG_TAB_ADVANCED"]   = "Advanced"
L["CFG_TAB_BACKUP"]     = "Backup"
L["CFG_TAB_RESET"]      = "Reset"

-- ── Backup / Export-Import ─────────────────────────────────────────────────────
L["BACKUP_EXPORT_HEADER"]      = "Export Notes"
L["BACKUP_EXPORT_DESC"]        = "Copies all notes to your clipboard. Paste into any text editor to save a backup outside of WoW."
L["BACKUP_FORMAT_MARKDOWN"]    = "Markdown  (.md)"
L["BACKUP_FORMAT_JSON"]        = "JSON  (.json)"
L["BACKUP_FMT_DESC_MARKDOWN"]  = "Human-readable plain text. Works with Obsidian, GitHub, and any text editor. Best for archiving and reading notes outside WoW."
L["BACKUP_FMT_DESC_JSON"]      = "Structured data format. Preserves all note fields exactly, including appearance settings. Best for re-importing into BigNoteBox or processing with external tools."
L["BACKUP_BTN_EXPORT"]         = "Export to Clipboard"
L["BACKUP_BTN_COPY_DONE"]      = "Copied! (%d notes)"
L["BACKUP_BTN_COPY_FALLBACK"]  = "Select all and press Ctrl+C to copy."
L["BACKUP_IMPORT_HEADER"]      = "Import Notes"
L["BACKUP_IMPORT_DESC"]        = "Paste an exported BigNoteBox backup below, then click Import. Imported notes are added alongside your existing notes — nothing is overwritten."
L["BACKUP_BTN_IMPORT"]         = "Import"
L["BACKUP_IMPORT_OK"]          = "Imported %d note(s) successfully."
L["BACKUP_IMPORT_NONE"]        = "Nothing to import — paste is empty or unrecognized."
L["BACKUP_IMPORT_ERR"]         = "Import failed: unrecognized format or corrupt data."
L["BACKUP_IMPORT_VERSION_WARN"]= "Warning: export version %d is newer than this addon supports (v%d). Some data may be ignored."
L["BACKUP_PASTE_HINT"]         = "Paste exported backup here..."

-- ── Sticky Notes ──────────────────────────────────────────────────────────────
L["STICKY_PIN_TIP"]     = "Open as a floating sticky note"
L["STICKY_UNPIN_TIP"]   = "Close this sticky note"
L["STICKY_COMBAT"]      = "Cannot open sticky notes during combat."
L["STICKY_MAX"]         = "Maximum of %d sticky notes already open."

-- ── Icon picker ───────────────────────────────────────────────────────────────
L["ICON_PICKER_TITLE"]  = "Choose Icon"
L["ICON_PICKER_SEARCH"] = "Search icons..."
L["ICON_PICKER_CLEAR"]  = "Clear icon (use default)"

-- ── Tag editing ───────────────────────────────────────────────────────────────
L["TAG_ADD_HINT"]        = "Add tag..."
L["TAG_MAX"]             = "Maximum 24 tags per note."
L["TAG_TOO_LONG"]        = "Tags must be 20 characters or less."

-- ── Tag Manager ───────────────────────────────────────────────────────────────
L["TAG_MGR_TITLE"]       = "Tag Manager"
L["TAG_MGR_TOOLTIP"]     = "Tag Manager"
L["TAG_MGR_EMPTY"]       = "No tags yet.\nAdd tags to your notes to see them here."
L["TAG_MGR_COUNT"]       = "%d note(s)"
L["TAG_MGR_RENAME"]      = "Rename"
L["TAG_MGR_DELETE"]      = "Delete"
L["TAG_MGR_RENAME_HINT"] = "New tag name..."
L["TAG_MGR_RENAME_CONFIRM"] = "Rename '%s' to '%s'?"
L["TAG_MGR_DELETE_CONFIRM"] = "Remove tag '%s' from all %d note(s)?"
L["TAG_MGR_MERGE_NOTE"]  = "Tip: rename a tag to an existing name to merge them."

-- ── Focus Mode ────────────────────────────────────────────────────────────────
L["FOCUS_MODE_TIP"]      = "Focus Mode"
L["FOCUS_MODE_TIP_SUB"]  = "Hide the note list and tools — just the note"
L["FOCUS_MODE_TITLE"]    = "BigNoteBox — Focus"
L["FOCUS_RESTORE_BTN"]   = "Restore"
L["FOCUS_RESTORE_TIP"]   = "Exit Focus Mode and return to the main window"

-- ── Drag and Drop ─────────────────────────────────────────────────────────────
L["DROP_INSERT_TIP"]      = "Drop to insert link"

-- ── Insert Game Info ──────────────────────────────────────────────────────────
L["INSERT_INFO_TITLE"]    = "Insert Info"
L["INSERT_LOCATION"]      = "Current location"
L["INSERT_TOMTOM"]        = "Set TomTom waypoint"
L["INSERT_TOMTOM_FAIL"]   = "Could not set TomTom waypoint."
L["INSERT_CHARNAME"]      = "Character name"
L["INSERT_TARGET"]        = "Target name"
L["INSERT_NO_TARGET"]     = "No target"
L["INSERT_DATE"]          = "Date"
L["INSERT_DATETIME"]      = "Date and time"

-- ── Print helper ──────────────────────────────────────────────────────────────
L["COMBAT_BLOCKED"]      = "Cannot open during combat."

-- ── Note scope ────────────────────────────────────────────────────────────────
L["SCOPE_GLOBAL"]        = "Global"
L["SCOPE_THIS_CHAR"]     = "This character"
L["SCOPE_SEND_LABEL"]    = "Send to alt:"
L["SCOPE_SEND_BTN"]      = "Choose character..."
L["SCOPE_NO_ALTS"]       = "No other characters registered yet. Log in on each alt at least once."

-- ── Reference Box ─────────────────────────────────────────────────────────────
L["REFBOX_TITLE"]           = "Reference Box"
L["REFBOX_TITLE_NOTE"]      = "Refbox: %s"
L["REFBOX_EMPTY"]           = "Drag items here,\nshift-click items, or\ntype an ID in the field above."
L["REFBOX_COUNT"]           = "Attachments (%d/%d)"
L["REFBOX_HINT"]            = "Drag items here · Shift-click to add"
L["REFBOX_PLACEHOLDER"]     = "Item ID, s:Spell ID, q:Quest ID"
L["REFBOX_ADD_BTN"]         = "Add"
L["REFBOX_CTX_SEND"]        = "Send to chat"
L["REFBOX_CTX_INSERT"]      = "Insert at text cursor"
L["REFBOX_CTX_WOWHEAD"]     = "Copy Wowhead URL"
L["REFBOX_CTX_DRESSUP"]     = "Try in dressing room"
L["REFBOX_CTX_MOVE_COPY"]   = "Move / Copy to note..."
L["REFBOX_CTX_REMOVE"]      = "Remove"
L["REFBOX_FULL"]            = "Reference Box full (%d max). Remove an entry first."
L["REFBOX_MOVE_FULL"]       = "Target note Reference Box is full."
L["REFBOX_DISABLED"]        = "Reference Box is disabled in Config -> Features."
L["REFBOX_LOCKED"]          = "|cffff9900Note is locked.|r Unlock in Note Settings to add attachments."
L["REFBOX_RESOLVE_MANUAL"]  = "|cffff6666Could not resolve:|r %s\nUse: item ID, or s:N for spells."
L["REFBOX_INVALID_ITEM"]    = "|cffff6666Removed invalid attachment:|r ID %s was not found."
L["REFBOX_LINK_FAIL"]       = "|cffff6666Could not build link|r -- item data not yet loaded."
L["REFBOX_TYPE_GEAR"]       = "Gear"
L["REFBOX_TYPE_SPELL"]      = "Spell"
L["REFBOX_TYPE_QUEST"]      = "Quest"
L["REFBOX_LOADING"]         = "Loading..."
-- Picker window
L["REFBOX_PICKER_TITLE"]    = "Move / Copy"
L["REFBOX_PICKER_PREFIX"]   = "Move/Copy: %s"
L["REFBOX_PICKER_MOVE"]     = "Move"
L["REFBOX_PICKER_COPY"]     = "Copy"
-- Picker row tooltips
L["REFBOX_MOVE_TO"]         = "Move to \"%s\""
L["REFBOX_MOVE_SUB"]        = "Removes from current note"
L["REFBOX_COPY_TO"]         = "Copy to \"%s\""
L["REFBOX_COPY_SUB"]        = "Keeps in current note too"
-- Info button tooltip (manual entry syntax)
L["REFBOX_INFO_TITLE"]      = "How to add attachments"
L["REFBOX_INFO_BARE"]       = "Bare number  ->  item ID"
L["REFBOX_INFO_SPELL"]      = "s:N  or  spell:N  ->  spell ID"
L["REFBOX_INFO_QUEST"]      = "q:N  or  quest:N  ->  quest ID"
L["REFBOX_INFO_ALSO"]       = "You can also:"
L["REFBOX_INFO_DRAG"]       = "- Drag items, spells or quests onto this panel"
L["REFBOX_INFO_SHIFT"]      = "- Shift-click an item from your bags"

-- ── Keybinding display names (read by WoW's binding UI) ───────────────────────
-- These must be plain globals, not inside the L table.
BINDING_NAME_BIGNOTEBOXOPEN           = "Open BigNoteBox"
BINDING_NAME_BIGNOTEBOXQUICKNOTE      = "Create Quick Note"
BINDING_NAME_BIGNOTEBOXNEWNOTE        = "Create New Note"
BINDING_NAME_BIGNOTEBOXHIDESTICKIES   = "Show/Hide All Sticky Notes"
BINDING_NAME_BIGNOTEBOXTOGGLERV       = "Open Rich Note Editor"
BINDING_NAME_BIGNOTEBOXNOTEONTARGET   = "Create Note from Target"
BINDING_HEADER_BIGNOTEBOXOPEN         = "BigNoteBox"

-- ── Config — Features > Sticky Notes ──────────────────────────────────────────
L["CFG_STICKY_HIDE_PERSIST"]     = "Keep sticky notes hidden"
L["CFG_STICKY_HIDE_PERSIST_TIP"] = "By default, sticky notes reappear automatically when you reload, relog, or change zones — so accidental hides are always recoverable.\n\nEnable this to make the Ctrl+H hide permanent: stickies will stay hidden until you press Ctrl+H again, even after a reload or relog."
L["CFG_STICKY_KEYBIND_LABEL"]    = "Show/Hide all stickies:"

-- ── Keybind capture button shared strings ─────────────────────────────────────
L["KEYBIND_NOT_BOUND"]      = "Not bound"
L["KEYBIND_PRESS_KEY"]      = "Press a key..."
L["KEYBIND_CONFLICT"]       = "\"%s\" is already bound to \"%s\".\nOverwrite it?"
L["KEYBIND_TOOLTIP_UNBIND"] = "Right-click to unbind"
L["KEYBIND_TOOLTIP_SET"]    = "Click to set a keybinding"

-- ── Config — General tab keybinds ─────────────────────────────────────────────
L["CFG_KB_OPEN_BNB"]        = "Open / close BigNoteBox:"

-- ── Config — Advanced tab keybinds ────────────────────────────────────────────
L["CFG_KB_NEW_NOTE"]        = "Create new note:"
L["CFG_KB_QUICK_NOTE"]      = "Create quick note:"

-- ── Session History ────────────────────────────────────────────────────────────
-- History Window (main browser)
L["HISTORY_WINDOW_TITLE"]        = "Note History"
L["HISTORY_EMPTY"]               = "No history yet.\nHistory is created automatically on logout or reload."
L["HISTORY_SIZE_NONE"]           = "No history yet."
L["HISTORY_SIZE_TOTAL"]          = "Total: %s"
L["HISTORY_CLEAR_ALL_BTN"]       = "Clear All History"
L["HISTORY_CLEAR_ALL_TIP"]       = "Delete all history for all notes"
L["HISTORY_CLEAR_ALL_CONFIRM"]   = "Delete ALL history for ALL notes? This cannot be undone."
L["HISTORY_SNAPSHOTS_ONE"]       = "1 snapshot"
L["HISTORY_SNAPSHOTS_MANY"]      = "%d snapshots"

-- Per-Note History Panel
L["HISTORY_NOTE_TITLE"]          = "History: %s"
L["HISTORY_NOTE_EMPTY"]          = "No history for this note yet."
L["HISTORY_SECTION_MANUAL"]      = "Manual Restore Point"
L["HISTORY_SECTION_AUTO"]        = "Auto Snapshots (%d)"
L["HISTORY_COMPARE_TIP"]         = "Compare this snapshot with the current note"
L["HISTORY_SLOT_DELETE_CONFIRM"] = "Sure?"
L["HISTORY_CLEAR_NOTE_BTN"]      = "Clear Note History"
L["HISTORY_CLEAR_NOTE_TIP"]      = "Delete all history for this note"
L["HISTORY_CLEAR_NOTE_SUB"]      = "Cannot be undone."

-- Compare Window
L["HISTORY_COMPARE_TITLE"]       = "Restore Comparison: %s"
L["HISTORY_COMPARE_CURRENT"]     = "Current Note"
L["HISTORY_COMPARE_SNAPSHOT"]    = "Snapshot"
L["HISTORY_COMPARE_MAKE_LIVE"]   = "Make Live"
L["HISTORY_COMPARE_MAKE_TIP"]    = "Use this version as the live note"
L["HISTORY_COMPARE_EXPORT"]      = "Export"
L["HISTORY_COMPARE_EXPORT_TIP"]  = "Export this version (JSON or Markdown)"
L["HISTORY_COMPARE_CANCEL"]      = "Cancel"
L["HISTORY_KEPT_CURRENT"]        = "|cff66bb6aKept current note.|r"
L["HISTORY_RESTORED"]            = "|cff66bb6aSnapshot restored. Previous version saved to history.|r"

-- Export popup
L["HISTORY_EXPORT_TITLE"]        = "Export Note"
L["HISTORY_EXPORT_FORMAT"]       = "Format:"
L["HISTORY_EXPORT_JSON"]         = "JSON"
L["HISTORY_EXPORT_MARKDOWN"]     = "Markdown"
L["HISTORY_EXPORT_COPY"]         = "Copy to Clipboard"

-- WYSIWYG bar restore / history buttons
L["HISTORY_RESTORE_BTN_TIP"]     = "Create manual restore point"
L["HISTORY_VIEW_BTN_TIP"]        = "View note history"

-- Manual restore point override popup
L["HISTORY_OVERRIDE_TEXT"]       = "A manual restore point already exists for this note.\nWhat would you like to do?"
L["HISTORY_OVERRIDE_OVERRIDE"]   = "Override"
L["HISTORY_OVERRIDE_COMPARE"]    = "Compare"
L["HISTORY_OVERRIDE_CANCEL"]     = "Cancel"
L["HISTORY_MANUAL_SAVED"]        = "|cff66bb6aManual restore point saved.|r"
L["HISTORY_MANUAL_UPDATED"]      = "|cff66bb6aManual restore point updated.|r"

-- Right-click menu
L["HISTORY_CTX_CREATE"]          = "Create restore point"
L["HISTORY_CTX_VIEW"]            = "View note history"

-- Toolbar button
L["HISTORY_TOOLBAR_TIP"]         = "Note History"

-- Welcome panel (BuildEmptyState)
L["WELCOME_MORNING"]   = "Good morning"
L["WELCOME_AFTERNOON"] = "Good afternoon"
L["WELCOME_EVENING"]   = "Good evening"
L["WELCOME_NIGHT"]     = "Good night"

L["WELCOME_WEEKDAYS"] = {
    [1] = "Sunday", [2] = "Monday", [3] = "Tuesday", [4] = "Wednesday",
    [5] = "Thursday", [6] = "Friday", [7] = "Saturday",
}
L["WELCOME_MONTHS"] = {
    [1]  = "January",  [2]  = "February", [3]  = "March",    [4]  = "April",
    [5]  = "May",      [6]  = "June",     [7]  = "July",     [8]  = "August",
    [9]  = "September",[10] = "October",  [11] = "November", [12] = "December",
}

L["WELCOME_LOC_NOTES"]  = "Current location notes"
L["WELCOME_FAV_NOTES"]  = "Favorite notes"
L["WELCOME_IMPORT_BTN"]       = "Import note(s)"
L["WELCOME_CONFIG_BTN"]       = "Open config"
L["WELCOME_CLOSE_CONFIG_BTN"] = "Close config"

-- Import popup
L["IMPORT_POPUP_TITLE"]  = "Import Notes"
L["IMPORT_POPUP_DESC"]   = "Paste a BigNoteBox JSON export below, then click Import."
L["IMPORT_POPUP_BTN"]    = "Import"
L["IMPORT_POPUP_CANCEL"] = "Cancel"
L["IMPORT_ERR_JSON"]     = "|cffff4444Import failed: the pasted text is not a valid BigNoteBox JSON export.|r"
L["IMPORT_SUCCESS"]      = "|cff66bb6aImported %d note(s) successfully.|r"

-- Tag Tree view
L["TAGTREE_EXPAND_ALL"]           = "Expand all"
L["TAGTREE_COLLAPSE_ALL"]         = "Collapse all"
L["TAGTREE_UNTAGGED"]             = "(untagged)"
L["TAGTREE_TOGGLE_TIP_ON"]        = "Switch to tag tree view"
L["TAGTREE_TOGGLE_TIP_OFF"]       = "Switch to list view"

-- Config: Features tab — Tag Tree
L["CFG_TAGTREE_HEADER"]           = "Tag Tree"
L["CFG_TAGTREE_STAY_OPEN"]        = "Stay in tag tree after selecting a note"
L["CFG_TAGTREE_STAY_OPEN_TIP"]    = "When enabled, selecting a note keeps the tag tree view active. Disable to return to list view automatically."
L["CFG_TAGTREE_START_EXPANDED"]   = "Tags start expanded"
L["CFG_TAGTREE_START_EXPANDED_TIP"] = "When enabled, all tag headers are expanded when you open the tag tree. Default is collapsed."

-- Config: Features tab — Focus Mode orbit/overlay
L["CFG_FOCUS_ORBIT_HEADER"]      = "Focus Mode"
L["CFG_FOCUS_ORBIT_ENABLE"]      = "Orbit camera slowly in focus mode"
L["CFG_FOCUS_ORBIT_ENABLE_TIP"]  = "Slowly rotates the camera while focus mode is active, creating a cinematic background. Stops on combat or movement."
L["CFG_FOCUS_ORBIT_SPEED"]       = "Orbit speed"
L["CFG_FOCUS_ORBIT_RESUME"]      = "Resume after movement (0 = never)"
L["CFG_FOCUS_OVERLAY_ALPHA"]     = "Overlay darkness"
L["CFG_FOCUS_ORBIT_TIP_ON"]      = "Turn on spinning"
L["CFG_FOCUS_ORBIT_TIP_OFF"]     = "Turn off spinning"
L["CFG_FOCUS_OVERLAY_SKIN_COLOR"]     = "Tint overlay with skin color (skin mode only)"
L["CFG_FOCUS_OVERLAY_SKIN_COLOR_TIP"] = "When enabled, the focus overlay uses your current skin color as a tint instead of plain black."

-- Rich Notes
L["CFG_RICH_NOTES_HEADER"]      = "Rich Notes"
L["CFG_RICH_NOTES_DEFAULT"]     = "New notes are rich by default"
L["CFG_RICH_NOTES_DEFAULT_TIP"] = "When enabled, new notes are created as rich notes with markup formatting support."
L["CFG_RICH_OPEN_EDITOR"]       = "Always open rich notes in editor mode"
L["CFG_RICH_OPEN_EDITOR_TIP"]   = "When switching between notes in the note list, rich notes will open in editor mode instead of view mode. New notes always open in editor mode regardless of this setting."
L["CFG_RICH_PREVIEW_AUTO"]      = "Show live preview automatically"
L["CFG_RICH_PREVIEW_AUTO_TIP"]  = "When enabled, the live preview window opens automatically whenever you select a rich note. You can also toggle it manually using the Live Preview button in the markup bar."
L["CFG_FOCUS_PREVIEW_ALWAYS"]      = "Always open preview window in focus mode"
L["CFG_FOCUS_PREVIEW_ALWAYS_TIP"]  = "When enabled, the live preview window always opens alongside focus mode for rich notes. When disabled, the preview only opens if it was already visible before entering focus mode."
L["CFG_KB_TOGGLE_RV"]           = "Open editor mode:"
L["CFG_KB_TOGGLE_RV_TIP"]       = "Opens the editor for the current rich note. If the note is already in editor mode, this does nothing."
L["CFG_SKIN_RANDOMIZE"]         = "Randomize theme on login/reload"
L["CFG_SKIN_RANDOMIZE_TIP"]     = "Randomly picks a different skin preset each time you log in or reload. Brightness is not affected."
L["RICH_MARKUP_TAB_EDITOR"]     = "Editor"
L["RICH_MARKUP_TAB_VIEW"]       = "View"
L["MARKUP_PREVIEW_BTN"]         = "Live Preview"
L["MARKUP_PREVIEW_TIP"]         = "Toggle the live preview window — renders the rich note as you type."
L["RICH_PREVIEW_TITLE"]         = "Live Preview"

-- Direct Send (Features/DirectSend.lua)
L["DS_SECTION_HEADER"]      = "Send Directly"
L["DS_TARGET_PLACEHOLDER"]  = "Player name (e.g. Dukul or Dukul-Realm)..."
L["DS_SEND_BUTTON"]         = "Send"
L["DS_ERR_NO_TARGET"]       = "Enter a player name first."
L["DS_ERR_NO_NOTE"]         = "No note selected."
L["DS_ERR_NOT_LOADED"]      = "DirectSend module not loaded."
L["DS_ERR_GENERIC"]         = "Send failed."
L["DS_ERR_TOO_LARGE"]       = "Note too large to send directly (%d chunks). Try a smaller tier."
L["DS_ERR_NO_NOTE_DATA"]    = "Could not encode note data."
L["DS_STATUS_SENT"]         = "Sending to %s... (%d chunks)"
L["DS_PROMPT_TITLE"]        = "Incoming Note"
L["DS_PROMPT_FROM"]         = "From: %s"
L["DS_PROMPT_VIA_BNB"]      = "Via: BigNoteBox"
L["DS_PROMPT_VIA_TAN"]      = "Via: TakeANote"
L["DS_PROMPT_NOTE_TITLE"]   = "Title: %s"
L["DS_ACCEPT"]              = "Accept"
L["DS_DECLINE"]             = "Decline"
L["DS_DECLINED_PRINT"]      = "|cffffcc00BigNoteBox:|r Incoming note from %s declined."
L["DS_AUTO_REJECTED"]       = "|cffffcc00BigNoteBox:|r Note from %s auto-rejected (auto-reject is on)."
-- Config: Features tab -- Direct Send
L["CFG_DS_HEADER"]          = "Direct Send"
L["CFG_DS_AUTO_REJECT"]     = "Auto-reject incoming note shares"
L["CFG_DS_AUTO_REJECT_TIP"] = "Silently decline notes sent directly from BigNoteBox or TakeANote, without showing a prompt. Similar to WoW's auto-decline duel option."

-- What's New window
L["WHATS_NEW_TITLE"]       = "What's New?"
L["WHATS_NEW_VERSION_TIP"] = "Click to see patch notes"

-- LibSharedMedia font opt-in
L["CFG_LSM_FONTS"]          = "Load LibSharedMedia fonts into the font picker"
L["CFG_LSM_FONTS_TIP"]      = "When enabled, fonts registered by other addons via LibSharedMedia-3.0 appear in the font picker below the bundled fonts. Requires a UI reload to take effect. Has no effect if LibSharedMedia is not installed."
L["CFG_LSM_FONTS_RELOAD"]   = "Reload required"
L["CFG_LSM_FONTS_OTHER"]    = "Other Installed Fonts"
L["CFG_LSM_FONTS_NONE"]     = "None (use bundled font)"
L["CFG_LSM_FONTS_MISSING"]  = "LibSharedMedia not found"

-- Rich Notes heading size settings (Editor tab)
L["CFG_RICH_SIZES_HEADER"]      = "Rich Notes"
L["CFG_RICH_SIZES_INDEPENDENT"] = "Set heading sizes independently"
L["CFG_RICH_SIZES_IND_TIP"]     = "When enabled, you can set exact pixel sizes for each heading level and body text in rich notes. When disabled, sizes are derived automatically from your base font size."
L["CFG_RICH_SIZE_H1"]           = "H1 size"
L["CFG_RICH_SIZE_H2"]           = "H2 size"
L["CFG_RICH_SIZE_H3"]           = "H3 size"
L["CFG_RICH_SIZE_P"]            = "Body (P) size"

-- Transmog gear cards (RefBox)
L["REFBOX_GEAR_HEADER_TMOG"]    = "Transmog gear"
L["REFBOX_GEAR_HEADER_REG"]     = "Regular gear"
L["REFBOX_GEAR_TYPE_TMOG"]      = "Transmog"
L["REFBOX_GEAR_TYPE_REG"]       = "Regular"
-- Config: Inspect Note -- gear show dropdown
L["CFG_INS_GEAR_SHOW"]          = "Gear to show"
L["CFG_INS_GEAR_BOTH"]          = "Show both regular and transmog gear"
L["CFG_INS_GEAR_REGULAR"]       = "Show only regular gear"
L["CFG_INS_GEAR_TRANSMOG"]      = "Show only transmog gear"
L["CFG_INS_GEAR_SHOW_TIP"]      = "Controls which gear sections appear in the Reference Box for inspect notes. All gear is always captured when you inspect; this only affects display."
-- Model viewer gear toggle
L["REFBOX_MV_GEAR_TMOG"]        = "Transmog gear"
L["REFBOX_MV_GEAR_REG"]         = "Regular gear"
-- Inspect note warning dialog: update buttons
L["INS_WARN_UPDATE_GEAR"]       = "Update gear"
L["INS_WARN_UPDATE_ALL"]        = "Update gear and note"
L["INS_WARN_UPDATE_ALL_CONFIRM"] = "This will overwrite the note body with fresh inspect data.\n\nAny edits you have made to the note text will be lost.\n\nBigNoteBox will create a restore point first so you can recover them."

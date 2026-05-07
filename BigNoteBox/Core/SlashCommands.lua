-- BigNoteBox Core/SlashCommands.lua — Slash commands and static popup dialogs

local BNB = BigNoteBox
local L = BNB.L

--------------------------------------------------------------------------------
-- SLASH COMMANDS
--------------------------------------------------------------------------------
function BNB.RegisterSlashCommands()
    SLASH_BIGNOTEBUTTON1 = "/bignotebutton"
    SLASH_BIGNOTEBUTTON2 = "/bnb"

    SlashCmdList["BIGNOTEBUTTON"] = function(msg)
        local cmd = string.lower(msg or "")

        if cmd == "new" then
            if BNB.CreateNewNote then
                BNB.CreateNewNote()
            else
                BNB:Print(L["SLASH_NOTE_CREATED"])
            end
        elseif cmd == "reset" then
            StaticPopup_Show("BNB_RESET_ALL")
        elseif cmd == "config" or cmd == "settings" then
            if BNB.OpenConfig then BNB.OpenConfig() end
        elseif cmd == "help" then
            print(L["SLASH_HELP"])
            print(L["SLASH_HELP_OPEN"])
            print(L["SLASH_HELP_NEW"])
            print(L["SLASH_HELP_CONFIG"])
            print(L["SLASH_HELP_RESET"])

        -- ── Developer: testwp ─────────────────────────────────────────────────
        elseif cmd:sub(1, 6) == "testwp" then
            if not BNB._debugWaypoint then
                BNB:Print("|cffff6666Enable Debug mode + Test waypoint system in Config → Advanced first.|r")
                return
            end
            local sub = cmd:sub(8) or ""
            if sub == "status" then
                local id = BNB._currentNoteID
                local note = id and BNB.GetNote(id)
                if not note then BNB:Print("No note selected."); return end
                local wp = note.waypoint
                if not wp then BNB:Print("Note has no waypoint data."); return end
                BNB:Print(string.format("|cff88bbffWaypoint data:|r mapID=%s  x=%s  y=%s  title=%s  label=%s",
                    tostring(wp.mapID), tostring(wp.x), tostring(wp.y),
                    tostring(wp.title), tostring(wp.label)))
                BNB:Print(string.format("|cff88bbffFlags:|r wpClearOnLeave=%s  context=%s",
                    tostring(note.wpClearOnLeave), tostring(note.context)))
            elseif sub == "fire" then
                BNB:Print("|cff88bbffSimulating zone-enter (calling CheckContextualNotes)...|r")
                if BNB.CheckContextualNotes then BNB.CheckContextualNotes() end
                C_Timer.After(1.5, function()
                    local count = 0
                    for _ in pairs(BNB._autoWaypoints or {}) do count = count + 1 end
                    BNB:Print(string.format("|cff88bbffAuto-waypoints tracked: %d|r", count))
                end)
            elseif sub == "leave" then
                BNB:Print("|cff88bbffSimulating zone-leave (clearing matches, re-checking)...|r")
                local prev = BNB._contextMatches or {}
                BNB:Print(string.format("|cff88bbffPrevious matches: %d|r", #prev))
                -- Temporarily clear the match function so nothing re-matches
                local oldMatches = BNB._contextMatches
                BNB._contextMatches = oldMatches  -- keep prev for leave logic
                if BNB.CheckContextualNotes then BNB.CheckContextualNotes() end
                C_Timer.After(1.5, function()
                    local count = 0
                    for _ in pairs(BNB._autoWaypoints or {}) do count = count + 1 end
                    BNB:Print(string.format("|cff88bbffAuto-waypoints remaining: %d|r", count))
                end)
            elseif sub == "auto" then
                local count = 0
                for id, uid in pairs(BNB._autoWaypoints or {}) do
                    local note = BNB.GetNote(id)
                    local title = note and note.title or "?"
                    BNB:Print(string.format("  |cff88bbff%s|r → uid=%s", title, tostring(uid)))
                    count = count + 1
                end
                if count == 0 then BNB:Print("|cff88bbffNo auto-placed waypoints tracked.|r") end
            else
                BNB:Print("|cffffff00Usage:|r /bnb testwp status|fire|leave|auto")
            end

        else
            if BNB.ToggleWindow then BNB.ToggleWindow() end
        end
    end
end

--------------------------------------------------------------------------------
-- PRINT HELPER
-- Prefixes messages with the addon name in color.
--------------------------------------------------------------------------------
function BNB:Print(msg)
    print("|cff66bb6aBigNoteBox|r: " .. tostring(msg))
end

--------------------------------------------------------------------------------
-- STATIC POPUP DIALOGS
--------------------------------------------------------------------------------
StaticPopupDialogs["BNB_RESET_ALL"] = {
    text = L["POPUP_RESET_ALL"],
    button1 = L["BTN_RESET_CONFIRM"],
    button2 = L["CANCEL"],
    OnAccept = function()
        BigNoteBoxDB = nil   -- wipes settings only; notes are in BigNoteBoxNotesDB
        C_UI.Reload()
    end,
    timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}

StaticPopupDialogs["BNB_DELETE_NOTE"] = {
    text = L["POPUP_DELETE_NOTE"],
    button1 = L["BTN_DELETE_CONFIRM"],
    button2 = L["CANCEL"],
    OnAccept = function(self)
        local id = self.data or BNB._currentNoteID
        if id and BNB.DeleteNote then BNB.DeleteNote(id) end
    end,
    timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}

-- Trash-aware variant: shown when trash is enabled and warn is on.
-- Text tells the player the note goes to trash rather than being gone forever.
StaticPopupDialogs["BNB_DELETE_NOTE_TRASH"] = {
    text = 'Move "%s" to Trash?',
    button1 = "Move to Trash",
    button2 = L["CANCEL"],
    OnAccept = function(self)
        local id = self.data or BNB._currentNoteID
        if id and BNB.DeleteNote then BNB.DeleteNote(id) end
    end,
    timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}

StaticPopupDialogs["BNB_DELETE_MULTI"] = {
    text = "Delete %s selected note(s)? This cannot be undone.",
    button1 = "Delete All",
    button2 = L["CANCEL"],
    OnAccept = function(self)
        local ids = self.data
        if not ids then return end
        for _, id in ipairs(ids) do
            if BNB.DeleteNote then BNB.DeleteNote(id) end
        end
        if BNB.SetMultiMode then BNB.SetMultiMode(false) end
    end,
    timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}

StaticPopupDialogs["BNB_DELETE_MULTI_TRASH"] = {
    text = "Move %s selected note(s) to Trash?",
    button1 = "Move to Trash",
    button2 = L["CANCEL"],
    OnAccept = function(self)
        local ids = self.data
        if not ids then return end
        for _, id in ipairs(ids) do
            if BNB.DeleteNote then BNB.DeleteNote(id) end
        end
        if BNB.SetMultiMode then BNB.SetMultiMode(false) end
    end,
    timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}

-- Helper: returns true when trash is active (trashRetainDays > 0).
-- Used by delete call sites to skip the confirmation popup — moving to trash
-- is non-destructive, so there is nothing to confirm.
function BNB.TrashEnabled()
    if not (BigNoteBoxDB and BigNoteBoxDB.trashFeature ~= false) then return false end
    local days = BigNoteBoxDB.trashRetainDays
    if days == nil then days = 30 end
    return days > 0
end

StaticPopupDialogs["BNB_EMPTY_TRASH"] = {
    text = "Permanently delete all notes in Trash? This cannot be undone.",
    button1 = "Empty Trash",
    button2 = L["CANCEL"],
    OnAccept = function()
        if BNB.EmptyTrash then BNB.EmptyTrash() end
    end,
    timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}

StaticPopupDialogs["BNB_CONFIRM_CLOSE"] = {
    text = "Close BigNoteBox?",
    button1 = "Close",
    button2 = L["CANCEL"],
    OnAccept = function()
        if BNB.mainFrame then
            -- Bypass the confirm check on the forced hide
            BNB.mainFrame._skipConfirm = true
            BNB.CloseCompanionWindows()
            BNB.mainFrame:Hide()
            BNB.mainFrame._skipConfirm = false
        end
    end,
    timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}

-- Shown during import when the backup contains notes scoped to a different
-- character. %s1 = original character name, %s2 = current character name.
-- button1 = remap to current char, button2 = keep original scope, ESC = abort.
StaticPopupDialogs["BNB_IMPORT_SCOPE_REMAP"] = {
    text = "Some imported notes are set to character-only visibility.\n\n"
        .. "Original character: |cffffcc00%s|r\n"
        .. "Current character:  |cff66cc66%s|r\n\n"
        .. "Character-scoped notes only appear when that specific character is logged in.\n\n"
        .. "|cffaaaaaa• Yes — reassign to your current character\n"
        .. "• No — keep the original character's scope\n"
        .. "• Press Escape to cancel the import entirely|r",
    button1 = "Yes, use current character",
    button2 = "No, keep original",
    OnAccept = function()
        local p = BNB._pendingImport
        if not p then return end
        local n = BNB._DoImport and BNB._DoImport(p.notes, true) or 0
        if p.status then
            if n > 0 then
                p.status:SetTextColor(0.55, 0.82, 0.55)
                p.status:SetText(string.format("|cff55cc55Imported %d note(s). Character scope updated to current character.|r", n))
            else
                p.status:SetTextColor(0.82, 0.55, 0.55)
                p.status:SetText("Nothing to import.")
            end
        end
        if p.paste then p.paste:SetRealText("") end
        BNB._pendingImport = nil
        BNB._pendingImportForeign = nil
    end,
    OnCancel = function(_, reason)
        if reason == "clicked" then
            -- button2: keep original scope
            local p = BNB._pendingImport
            if not p then return end
            local n = BNB._DoImport and BNB._DoImport(p.notes, false) or 0
            if p.status then
                if n > 0 then
                    p.status:SetTextColor(0.55, 0.82, 0.55)
                    p.status:SetText(string.format("|cff55cc55Imported %d note(s). Original character scope kept.|r", n))
                else
                    p.status:SetTextColor(0.82, 0.55, 0.55)
                    p.status:SetText("Nothing to import.")
                end
            end
            if p.paste then p.paste:SetRealText("") end
        end
        -- ESC or button2 both clean up
        BNB._pendingImport = nil
        BNB._pendingImportForeign = nil
    end,
    timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
    showAlert = true,
}

-- Confirmation popup for the same-character import path (no scope remap needed).
-- Fired by the Backup tab's Import button after the paste has parsed successfully
-- but before the notes are actually imported, so the user can back out.
StaticPopupDialogs["BNB_IMPORT_CONFIRM"] = {
    text = "About to import |cffffcc00%d|r note(s) from the pasted text.\n\nContinue?",
    button1 = "Import",
    button2 = "Cancel",
    OnAccept = function()
        local p = BNB._pendingImport
        if not p then return end
        local n = BNB._DoImport and BNB._DoImport(p.notes, false) or 0
        if p.status then
            if n > 0 then
                p.status:SetTextColor(0.55, 0.82, 0.55)
                p.status:SetText(string.format(L["BACKUP_IMPORT_OK"], n))
            else
                p.status:SetTextColor(0.82, 0.55, 0.55)
                p.status:SetText(L["BACKUP_IMPORT_NONE"])
            end
        end
        if p.paste then p.paste:SetRealText("") end
        BNB._pendingImport = nil
    end,
    OnCancel = function()
        -- User backed out — leave paste box intact so they can edit and retry
        BNB._pendingImport = nil
    end,
    timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}




--------------------------------------------------------------------------------
-- ADDON COMPARTMENT FRAME (global wrappers referenced in retail .toc)
--------------------------------------------------------------------------------
function BNB_OnAddonCompartmentClick(addonName, buttonName)
    if buttonName == "RightButton" then
        if BNB.CreateNewNote then BNB.CreateNewNote() end
    else
        if BNB.ToggleWindow then BNB.ToggleWindow() end
    end
end

function BNB_OnAddonCompartmentEnter(addonName, menuButtonFrame)
    GameTooltip:SetOwner(menuButtonFrame, "ANCHOR_LEFT")
    GameTooltip:AddLine("BigNoteBox", 0.4, 0.73, 0.42)
    GameTooltip:AddLine(L["MINIMAP_LEFT_CLICK"], 1, 1, 1)
    GameTooltip:AddLine(L["MINIMAP_RIGHT_CLICK"], 1, 1, 1)
    GameTooltip:Show()
end

function BNB_OnAddonCompartmentLeave()
    GameTooltip:Hide()
end

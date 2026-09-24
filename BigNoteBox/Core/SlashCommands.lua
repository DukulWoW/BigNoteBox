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
        elseif cmd == "debug" then
            if BNB.DebugWindow then BNB.DebugWindow.Toggle() end
        elseif cmd == "help" then
            print(L["SLASH_HELP"])
            print(L["SLASH_HELP_OPEN"])
            print(L["SLASH_HELP_NEW"])
            print(L["SLASH_HELP_CONFIG"])
            print(L["SLASH_HELP_RESET"])
            print(L["SLASH_HELP_DEBUG"])

        -- ── Developer: testwp ─────────────────────────────────────────────────
        elseif cmd:sub(1, 6) == "testwp" then
            if not BNB._debugWaypoint then
                BNB:Print("|cffff6666Enable Debug mode + Test waypoint system in Config -> Advanced first.|r")
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
                    BNB:Print(string.format("  |cff88bbff%s|r -> uid=%s", title, tostring(uid)))
                    count = count + 1
                end
                if count == 0 then BNB:Print("|cff88bbffNo auto-placed waypoints tracked.|r") end
            else
                BNB:Print("|cffffff00Usage:|r /bnb testwp status|fire|leave|auto")
            end

        -- ── Developer: chrome seating (FOR-05, UI/Chrome.lua) ─────────────────
        -- "chromeprobe" dumps the template layout; "chrome l t r b" re-seats
        -- every window live. Nothing is saved: Forever drops SavedVariables.
        elseif cmd:sub(1, 6) == "chrome" then
            if not (BigNoteBoxDB and BigNoteBoxDB.debugMode == true) then
                BNB:Print("|cffff6666Enable Debug mode in Config -> Advanced first.|r")
                return
            end
            local sub = cmd:sub(7):match("^%s*(.-)%s*$")
            local function Report(prefix, n)
                local d = BNB.CHROME_DELTA
                BNB:Print(string.format("|cff88bbff%s|r l=%s t=%s r=%s b=%s%s", prefix,
                    tostring(d.l), tostring(d.t), tostring(d.r), tostring(d.b),
                    n and string.format("  (%d windows re-seated)", n) or ""))
            end
            if sub == "probe" then
                if BNB.ChromeProbe then BNB.ChromeProbe() end
            elseif sub == "reset" then
                Report("Chrome delta reset to built-in:", BNB.SetChromeDelta(nil))
            elseif sub == "" then
                Report("Chrome delta:")
                BNB:Print("|cffffff00Usage:|r /bnb chromeprobe  |  /bnb chrome <left> <top> <right> <bottom>  |  /bnb chrome reset")
            else
                local l, t, r, b = sub:match("^(%S+)%s+(%S+)%s+(%S+)%s+(%S+)$")
                l, t, r, b = tonumber(l), tonumber(t), tonumber(r), tonumber(b)
                if not (l and t and r and b) then
                    BNB:Print("|cffffff00Usage:|r /bnb chrome <left> <top> <right> <bottom>  (pixels, positive = outward)")
                else
                    Report("Chrome delta set:", BNB.SetChromeDelta({ l = l, t = t, r = r, b = b }))
                end
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
-- Helper: returns true when trash is active (trashRetainDays > 0).
-- Used by delete call sites to skip the confirmation popup — moving to trash
-- is non-destructive, so there is nothing to confirm.
function BNB.TrashEnabled()
    if not (BigNoteBoxDB and BigNoteBoxDB.trashFeature ~= false) then return false end
    local days = BigNoteBoxDB.trashRetainDays
    if days == nil then days = 30 end
    return days > 0
end

-- Built at PLAYER_LOGIN, not file load: L[...] must resolve after the language is
-- known, or the popups stay in the load-time language (and the pseudo-locale misses them).
local function BuildPopups()
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

    -- Delete popups take the note id(s) as StaticPopup data (4th arg of
    -- StaticPopup_Show). They delete exactly what was confirmed: no fallback to
    -- the note open in the editor, so a popup without data deletes nothing.
    -- The non-trash popups say "cannot be undone" and delete permanently, even
    -- while trash is on ("Delete permanently" in the note context menu).
    StaticPopupDialogs["BNB_DELETE_NOTE"] = {
        text = L["POPUP_DELETE_NOTE"],
        button1 = L["BTN_DELETE_CONFIRM"],
        button2 = L["CANCEL"],
        OnAccept = function(self, data)
            local id = data or self.data
            if id and BNB.DeleteNote then BNB.DeleteNote(id, true) end
        end,
        timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
    }

    -- Trash-aware variant: shown when trash is enabled and warn is on.
    -- Text tells the player the note goes to trash rather than being gone forever.
    StaticPopupDialogs["BNB_DELETE_NOTE_TRASH"] = {
        text = L["POPUP_TRASH_NOTE"],
        button1 = L["BTN_TRASH_CONFIRM"],
        button2 = L["CANCEL"],
        OnAccept = function(self, data)
            local id = data or self.data
            if id and BNB.DeleteNote then BNB.DeleteNote(id) end
        end,
        timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
    }

    -- Bulk variants (ALL-58): %s1 = count, %s2 = the first titles plus
    -- "...and N more", and a red line when the selection is every note.
    -- Shown for any bulk delete of 2+ notes, even with "Warn before delete" off.
    local function AcceptMulti(self, data, permanent)
        local ids = data or self.data
        if type(ids) ~= "table" then return end
        if BNB.DeleteNotes then BNB.DeleteNotes(ids, permanent) end
        if BNB.SetMultiMode then BNB.SetMultiMode(false) end
    end

    StaticPopupDialogs["BNB_DELETE_MULTI"] = {
        text = L["POPUP_DELETE_MULTI"] .. "\n\n%s",
        button1 = L["BTN_DELETE_CONFIRM"],
        button2 = L["CANCEL"],
        OnAccept = function(self, data) AcceptMulti(self, data, true) end,
        timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
        showAlert = true,
    }

    StaticPopupDialogs["BNB_DELETE_MULTI_TRASH"] = {
        text = L["POPUP_TRASH_MULTI"] .. "\n\n%s",
        button1 = L["BTN_TRASH_CONFIRM"],
        button2 = L["CANCEL"],
        OnAccept = function(self, data) AcceptMulti(self, data, false) end,
        timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
        showAlert = true,
    }

    StaticPopupDialogs["BNB_EMPTY_TRASH"] = {
        text = L["POPUP_EMPTY_TRASH"],
        button1 = L["BTN_EMPTY_TRASH"],
        button2 = L["CANCEL"],
        OnAccept = function()
            if BNB.EmptyTrash then BNB.EmptyTrash() end
        end,
        timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
    }

    StaticPopupDialogs["BNB_CONFIRM_CLOSE"] = {
        text = L["POPUP_CONFIRM_CLOSE"],
        button1 = L["CLOSE"],
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
        text = L["POPUP_IMPORT_REMAP"],
        button1 = L["BTN_IMPORT_REMAP_YES"],
        button2 = L["BTN_IMPORT_REMAP_NO"],
        OnAccept = function()
            local p = BNB._pendingImport
            if not p then return end
            local n = BNB._DoImport and BNB._DoImport(p.notes, true) or 0
            if p.status then
                if n > 0 then
                    p.status:SetTextColor(0.55, 0.82, 0.55)
                    p.status:SetText(string.format(L["IMPORT_DONE_REMAP"], n))
                else
                    p.status:SetTextColor(0.82, 0.55, 0.55)
                    p.status:SetText(L["IMPORT_NOTHING"])
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
                        p.status:SetText(string.format(L["IMPORT_DONE_KEEP"], n))
                    else
                        p.status:SetTextColor(0.82, 0.55, 0.55)
                        p.status:SetText(L["IMPORT_NOTHING"])
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
        text = L["POPUP_IMPORT_CONFIRM"],
        button1 = L["IMPORT_POPUP_BTN"],
        button2 = L["CANCEL"],
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
end

BNB.RegisterEvent("PLAYER_LOGIN", BuildPopups)

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

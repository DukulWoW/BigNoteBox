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
            -- The dev tools page in dev mode, else the Advanced tab (ALL-395)
            if BNB.OpenDevTools then BNB.OpenDevTools() end
        elseif cmd == "devtools" then
            -- Only the Developer Tools, in a window of their own (dev addon only)
            if BNB.IsDevMode() and BNB.ToggleDevToolsWindow then BNB.ToggleDevToolsWindow()
            else BNB.DevToolMissing() end
        elseif cmd == "debug on" or cmd == "debug off" then
            if BNB.SetDebugMode then BNB.SetDebugMode(cmd == "debug on") end
        elseif cmd == "search" or cmd:sub(1, 7) == "search " then
            -- Oracle search (ALL-69); the text keeps its case
            if BNB.Oracle then BNB.Oracle.Open((msg:match("^%s*%S+%s+(.-)%s*$"))) end
        elseif cmd == "whatsnew" then
            -- Routes into existing windows (ALL-33); text resolves at call time
            if BNB.WhatsNew and BNB.WhatsNew.Open then BNB.WhatsNew.Open(false) end
        elseif cmd == "features" then
            -- The help book's Features tab (it replaced the Features window, ALL-554)
            if BNB.HelpBook then BNB.HelpBook.OpenFeatures() end
        elseif cmd == "help" then
            -- The help book (ALL-554); the command list moved to /bnb commands
            if BNB.HelpBook then BNB.HelpBook.Open() end
        elseif cmd == "commands" then
            print(L["SLASH_HELP"])
            print(L["SLASH_HELP_BOOK"])
            print(L["SLASH_HELP_COMMANDS"])
            print(L["SLASH_HELP_OPEN"])
            print(L["SLASH_HELP_NEW"])
            print(L["SLASH_HELP_SEARCH"])
            print(L["SLASH_HELP_CONFIG"])
            print(L["SLASH_HELP_RESET"])
            print(L["SLASH_HELP_WHATSNEW"])
            print(L["SLASH_HELP_FEATURES"])
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
                local list = {}
                local created = BNB.CreationWaypoint(note)
                if created then list[1] = created end
                for _, wp in ipairs(BNB.NoteWaypoints(note)) do list[#list + 1] = wp end
                if not list[1] then BNB:Print("Note has no waypoint data."); return end
                for _, wp in ipairs(list) do
                    BNB:Print(string.format("|cff88bbffWaypoint%s:|r mapID=%s  x=%s  y=%s  on=%s  name=%s  label=%s",
                        wp.created and " (created)" or "", tostring(wp.mapID), tostring(wp.x), tostring(wp.y),
                        tostring(wp.on == true), BNB.WaypointName(note, wp), tostring(wp.label)))
                end
                BNB:Print(string.format("|cff88bbffFlags:|r wpClearOnLeave=%s  wpNoTrack=%s  situations=%s",
                    tostring(note.wpClearOnLeave), tostring(note.wpNoTrack),
                    table.concat(BNB.NoteSituations(note), ", ")))
            elseif sub == "fire" then
                BNB:Print("|cff88bbffSimulating zone-enter (calling CheckContextualNotes)...|r")
                if BNB.CheckContextualNotes then BNB.CheckContextualNotes() end
                C_Timer.After(1.5, function()
                    local count = 0
                    for _ in pairs(BNB._autoWaypoints or {}) do count = count + 1 end
                    BNB:Print(string.format("|cff88bbffAuto-waypoints tracked: %d|r", count))
                end)
            elseif sub == "leave" then
                -- Re-checks with the current matches; it shows what a real leave
                -- would clear only after the player has actually left the place.
                BNB:Print("|cff88bbffRe-checking situations (leave logic)...|r")
                local prev = BNB._contextMatches or {}
                BNB:Print(string.format("|cff88bbffPrevious matches: %d|r", #prev))
                if BNB.CheckContextualNotes then BNB.CheckContextualNotes() end
                C_Timer.After(1.5, function()
                    local count = 0
                    for _ in pairs(BNB._autoWaypoints or {}) do count = count + 1 end
                    BNB:Print(string.format("|cff88bbffAuto-waypoints remaining: %d|r", count))
                end)
            elseif sub == "auto" then
                local count = 0
                for id, placed in pairs(BNB._autoWaypoints or {}) do
                    local note = BNB.GetNote(id)
                    local title = note and note.title or "?"
                    BNB:Print(string.format("  |cff88bbff%s|r -> %s", title,
                        placed == true and "map pin"
                        or (#placed .. (placed.mpe and " MapPinEnhanced pin(s)" or " TomTom waypoint(s)"))))
                    count = count + 1
                end
                if count == 0 then BNB:Print("|cff88bbffNo auto-placed waypoints tracked.|r") end
            else
                BNB:Print("|cffffff00Usage:|r /bnb testwp status|fire|leave|auto")
            end

        -- ── Developer: search bar art layout (ALL-69, UI/SearchChrome.lua) ────
        elseif cmd == "searchlayout" then
            if not (BigNoteBoxDB and BigNoteBoxDB.debugMode == true) then
                BNB:Print("|cffff6666Enable Debug mode in Config -> Advanced first.|r")
                return
            end
            if BNB.ToggleSearchLayoutTool then BNB.ToggleSearchLayoutTool() else BNB.DevToolMissing() end

        -- ── Developer: game background preview (ALL-110, BigNoteBox_Dev Labs/BackgroundLab.lua) ─
        elseif cmd == "bglab" then
            if not (BigNoteBoxDB and BigNoteBoxDB.debugMode == true) then
                BNB:Print("|cffff6666Enable Debug mode in Config -> Advanced first.|r")
                return
            end
            if BNB.OpenBackgroundLab then BNB.OpenBackgroundLab() else BNB.DevToolMissing() end

        -- ── Developer: toast styles (ALL-376, BigNoteBox_Dev Labs/ToastLab.lua) ─────────────
        elseif cmd == "toastlab" then
            if not (BigNoteBoxDB and BigNoteBoxDB.debugMode == true) then
                BNB:Print("|cffff6666Enable Debug mode in Config -> Advanced first.|r")
                return
            end
            if BNB.OpenToastLab then BNB.OpenToastLab() else BNB.DevToolMissing() end

        -- ── Developer: skin preset colours (ALL-403, BigNoteBox_Dev Labs/SkinLab.lua) ─────────
        elseif cmd == "skinlab" then
            if not (BigNoteBoxDB and BigNoteBoxDB.debugMode == true) then
                BNB:Print("|cffff6666Enable Debug mode in Config -> Advanced first.|r")
                return
            end
            if BNB.OpenSkinLab then BNB.OpenSkinLab() else BNB.DevToolMissing() end

        -- ── Developer: note icon frame measuring (ALL-126, BigNoteBox_Dev Labs/IconLab.lua) ────
        elseif cmd == "iconlab" then
            if not (BigNoteBoxDB and BigNoteBoxDB.debugMode == true) then
                BNB:Print("|cffff6666Enable Debug mode in Config -> Advanced first.|r")
                return
            end
            if BNB.OpenIconLab then BNB.OpenIconLab() else BNB.DevToolMissing() end

        -- ── Developer: skin accent hue turn (UI/SkinSystem.lua, not saved) ───
        elseif cmd == "skinhue" or cmd:sub(1, 8) == "skinhue " then
            if not (BigNoteBoxDB and BigNoteBoxDB.debugMode == true) then
                BNB:Print("|cffff6666Enable Debug mode in Config -> Advanced first.|r")
                return
            end
            local deg = tonumber(cmd:sub(9))
            if deg then
                BNB.skinAccentHue = deg
                if BNB.RefreshSkinAccents then BNB.RefreshSkinAccents() end
            end
            BNB:Print(string.format("|cff88bbffSkin accent hue:|r %s degrees  |cffffff00Usage:|r /bnb skinhue <degrees>  (live, not saved)",
                tostring(BNB.skinAccentHue)))

        -- ── Developer: main window toolbar strip art (ALL-240, UI/MainWindow.lua) ─
        elseif cmd == "topbar" or cmd:sub(1, 7) == "topbar " then
            if not (BigNoteBoxDB and BigNoteBoxDB.debugMode == true) then
                BNB:Print("|cffff6666Enable Debug mode in Config -> Advanced first.|r")
                return
            end
            if not BNB.TuneTopBarArt then return end
            local y, h, c, w, lf, li, hd = cmd:sub(8):match("^%s*(%S+)%s*(%S*)%s*(%S*)%s*(%S*)%s*(%S*)%s*(%S*)%s*(%S*)")
            local y2, h2, c2, w2, l2, i2, hd2, drawn = BNB.TuneTopBarArt(tonumber(y), tonumber(h), tonumber(c),
                tonumber(w), tonumber(lf), tonumber(li), tonumber(hd))
            BNB:Print(string.format("|cff88bbffTop bar art:|r y=%s h=%s cropTop=%s tileW=%s lift=%s left=%s header=%s%s",
                tostring(y2), tostring(h2), tostring(c2), tostring(w2), tostring(l2), tostring(i2), tostring(hd2),
                drawn and "" or "  (not drawn: skin mode, file missing, or window not built)"))
            if not y then
                BNB:Print("|cffffff00Usage:|r /bnb topbar <y> [h] [cropTop] [tileW] [lift] [left] [header]  (live, not saved)")
            end

        -- ── Developer: Target / Focus frame note badge (ALL-389, Features/UnitFrameBadge.lua)
        elseif cmd == "unitbadge" or cmd:sub(1, 10) == "unitbadge " then
            if not (BigNoteBoxDB and BigNoteBoxDB.debugMode == true) then
                BNB:Print("|cffff6666Enable Debug mode in Config -> Advanced first.|r")
                return
            end
            if not BNB.TuneUnitBadge then return end
            local x, y, s = cmd:sub(11):match("^%s*(%S*)%s*(%S*)%s*(%S*)")
            local x2, y2, s2 = BNB.TuneUnitBadge(tonumber(x), tonumber(y), tonumber(s))
            BNB:Print(string.format("|cff88bbffUnit frame badge:|r x=%s y=%s scale=%s  (live, not saved)",
                tostring(x2), tostring(y2), tostring(s2)))
            if not tonumber(x) then
                BNB:Print("|cffffff00Usage:|r /bnb unitbadge <x> <y> [scale]")
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
-- STATIC POPUP DIALOGS
--------------------------------------------------------------------------------
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

    -- The note delete / trash / empty trash confirms are our own dialog now
    -- (ALL-572): BNB.ConfirmDeleteNote / ConfirmDeleteNotes (UI/NoteList.lua),
    -- the Trash window's own (UI/TrashWindow.lua)

    -- Close the main window, import remap and import confirm: our own
    -- dialog (ALL-572 S3), below
end

BNB.RegisterEvent("PLAYER_LOGIN", BuildPopups)

-- "Confirm before closing" (Settings): asked on the main window (ALL-572 S3)
function BNB.ConfirmCloseMainWindow()
    BNB.Dialog.Confirm({
        text = L["POPUP_CONFIRM_CLOSE"], okLabel = L["CLOSE"], host = BNB.mainFrame,
        key = "closeMain",
        onAccept = function()
            if not BNB.mainFrame then return end
            -- Bypass the confirm check on the forced hide
            BNB.mainFrame._skipConfirm = true
            BNB.CloseCompanionWindows()
            BNB.mainFrame:Hide()
            BNB.mainFrame._skipConfirm = false
        end,
    })
end

-- The import's result on the Backup page's status line (Welcome import: none)
local function ImportReport(p, n, okText)
    if p.status then
        if n > 0 then
            p.status:SetTextColor(0.55, 0.82, 0.55)
            p.status:SetText(okText)
        else
            p.status:SetTextColor(0.82, 0.55, 0.55)
            p.status:SetText(L["IMPORT_NOTHING"])
        end
    end
    if p.paste then p.paste:SetRealText("") end
end

-- The import holds notes for another character (BNB._pendingImport, set by
-- the caller): Yes = move them to this character, No = keep their character,
-- Cancel / Esc = no import. Was a 2-button StaticPopup with Esc as the third
-- choice (ALL-572 S3: a Cancel button of its own now)
function BNB.ConfirmImportRemap(foreignChar)
    local p = BNB._pendingImport
    if not p then return end
    local function run(remap)
        BNB._pendingImport = nil
        local n = BNB._DoImport and BNB._DoImport(p.notes, remap) or 0
        ImportReport(p, n, string.format(L[remap and "IMPORT_DONE_REMAP" or "IMPORT_DONE_KEEP"], n))
    end
    BNB.Dialog.Confirm({
        text = string.format(L["POPUP_IMPORT_REMAP"], foreignChar or "", BNB.currentChar or ""),
        okLabel = L["BTN_IMPORT_REMAP_YES"], altLabel = L["BTN_IMPORT_REMAP_NO"],
        alert = true, width = 420, key = "importRemap",
        onAccept = function() run(true) end,
        onAlt = function() run(false) end,
        onCancel = function() BNB._pendingImport = nil end,
    })
end

-- The same-character import: the count, then the import. Cancel leaves the
-- paste box as it is, to edit and retry
function BNB.ConfirmImport()
    local p = BNB._pendingImport
    if not p then return end
    BNB.Dialog.Confirm({
        text = string.format(L["POPUP_IMPORT_CONFIRM"], #p.notes),
        okLabel = L["IMPORT_POPUP_BTN"], key = "importConfirm",
        onAccept = function()
            BNB._pendingImport = nil
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
        end,
        onCancel = function() BNB._pendingImport = nil end,
    })
end

--------------------------------------------------------------------------------
-- ADDON COMPARTMENT FRAME (global wrappers referenced in retail .toc)
--------------------------------------------------------------------------------
function BNB_OnAddonCompartmentClick(addonName, buttonName)
    BNB.MinimapClick(buttonName)   -- same clicks as the minimap button (Minimap.lua)
end

function BNB_OnAddonCompartmentEnter(addonName, menuButtonFrame)
    GameTooltip:SetOwner(menuButtonFrame, "ANCHOR_LEFT")
    BNB.FillMinimapTooltip(GameTooltip)   -- same tooltip as the minimap button (ALL-472)
    GameTooltip:Show()
end

function BNB_OnAddonCompartmentLeave()
    GameTooltip:Hide()
end

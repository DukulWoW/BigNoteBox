-- BigNoteBox Core/Events.lua — Central event frame & dispatcher
-- One event frame for the entire addon instead of scattered frames per module.

local BNB = BigNoteBox
local L = BNB.L

--------------------------------------------------------------------------------
-- Classic beta notice (ALL-168): a "still in development, keep backups" note
-- with bug links and a "Don't show this again" box (BigNoteBoxDB.foreverNoticeHidden,
-- named from the Forever beta, FOR-10). Forever no longer shows it: its beta
-- ended and 2.0.0 opens BigNoteBox for the Forever launch (ALL-10, Dukul
-- 2026-10-30; the Plunderstorm frame art it had went with it). Its own window
-- rather than a StaticPopup, so the button is the new SharedButtonTemplate one.
--------------------------------------------------------------------------------
local _foreverNotice

-- The game's dialog box
local function BuildClassicChrome(f)
    f:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 },
    })
end

-- Classic only, until "Don't show this again" is ticked, and never while the setup
-- wizard is still to be done: its Finish reloads (so the next login shows it) and
-- its Quit calls this directly (UI/SetupWizard.lua BNB_QUIT_SETUP).
function BNB.ShowForeverNoticeIfDue()
    local db = BigNoteBoxDB
    if not BNB.IsClassic or not db then return end
    if db.foreverNoticeHidden or db.setupComplete ~= true then return end
    -- After the Explorer welcome, which calls this when it closes (ALL-543)
    if BNB.ExplorerIntroHolding and BNB.ExplorerIntroHolding() then return end
    pcall(BNB.ShowForeverNotice)
end
-- The notice's chrome. Normal mode: a hand-built frame with the game's dialog
-- box art and its own title and X.
-- Skin mode (ALL-418): BNB.CreateToolWindow's skin frame, title strip and X,
-- so the window matches the rest instead of mixing game art with skin parts.
local function NewNoticeFrame(W, title)
    if BigNoteBoxDB and BigNoteBoxDB.skinMode then
        local f
        f = BNB.CreateToolWindow({
            name = "BNBForeverNoticeFrame", w = W, h = 200, title = title,
            toplevel = true, escClose = true, keyEsc = true,
            onClose = function() f:Hide() end,
        })
        f:SetPoint("CENTER", UIParent, "CENTER", 0, 120)
        f:SetClampedToScreen(true)
        return f, BNB.TOOL_SKIN_TITLE_H + 16, 16
    end
    local f = CreateFrame("Frame", "BNBForeverNoticeFrame", UIParent, "BackdropTemplate")
    f:SetWidth(W)
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 120)
    f:SetFrameStrata("DIALOG")
    f:SetToplevel(true)
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    BNB.SetMoveCursor(f)
    tinsert(UISpecialFrames, "BNBForeverNoticeFrame")
    -- ESC by hand as well: UISpecialFrames alone does not close a standalone
    -- window on Forever (see the Reference Box)
    BNB.AttachEscClose(f, f.Hide)

    local titleFS = f:CreateFontString(nil, "OVERLAY", "BNBFontNormalLarge")
    titleFS:SetPoint("TOP", f, "TOP", 0, -26)
    titleFS:SetText(title)
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -14, -14)
    close:SetFrameLevel(f:GetFrameLevel() + 5)   -- above the corner art
    return f, 58, 28
end

function BNB.ShowForeverNotice()
    local f = _foreverNotice
    if not f then
        local W, PAD = 420, 30
        local TOP, BOTTOM
        f, TOP, BOTTOM = NewNoticeFrame(W, L["CLASSIC_NOTICE_TITLE"])

        local body = f:CreateFontString(nil, "OVERLAY", "BNBFontHighlight")
        body:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, -TOP)
        body:SetWidth(W - PAD * 2)
        body:SetJustifyH("LEFT")
        body:SetSpacing(2)
        body:SetText(L["CLASSIC_TEST_NOTICE"])

        local ok = BNB.CreateButton(nil, f, L["OK"], 120, 26)
        ok:SetPoint("BOTTOM", f, "BOTTOM", 0, BOTTOM)
        ok:SetScript("OnClick", function() f:Hide() end)

        -- Report-a-bug links (ALL-73), under the text
        local bugs = f:CreateFontString(nil, "OVERLAY", "BNBFontNormal")
        bugs:SetPoint("TOPLEFT", body, "BOTTOMLEFT", 0, -16)
        bugs:SetWidth(W - PAD * 2)
        bugs:SetJustifyH("LEFT")
        bugs:SetText(L["FOREVER_NOTICE_BUGS"])
        local links = BNB.CreateBugLinkButtons(f, W - PAD * 2, f._isSkin)
        links:SetPoint("TOPLEFT", bugs, "BOTTOMLEFT", 0, -8)

        -- Checkbox + label, centred as a group above the OK button
        local row = CreateFrame("Frame", nil, f)
        row:SetHeight(24)
        row:SetPoint("BOTTOM", ok, "TOP", 0, 8)
        local cb = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
        BNB.LabelHit(cb)   -- the tooltip and click reach over its label too
        cb:SetSize(24, 24)
        cb:SetPoint("LEFT", row, "LEFT", 0, 0)
        local cbLabel = row:CreateFontString(nil, "OVERLAY", "BNBFontNormal")
        cbLabel:SetPoint("LEFT", cb, "RIGHT", 2, 0)
        cbLabel:SetText(L["FOREVER_NOTICE_DONT_SHOW"])
        BNB.CheckTip(cb, L["FOREVER_NOTICE_DONT_SHOW_TIP"])
        row:SetWidth(24 + 2 + cbLabel:GetStringWidth())
        -- Label clicks toggle the box too
        local hit = CreateFrame("Button", nil, f)
        hit:SetPoint("TOPLEFT", cbLabel, "TOPLEFT", -2, 4)
        hit:SetPoint("BOTTOMRIGHT", cbLabel, "BOTTOMRIGHT", 2, -4)
        hit:SetScript("OnClick", function() cb:Click() end)

        -- The box is saved on close (OK, X or Escape), not on each click
        f:HookScript("OnHide", function()
            if BigNoteBoxDB then
                BigNoteBoxDB.foreverNoticeHidden = cb:GetChecked() and true or nil
            end
        end)
        -- Height from the wrapped text: title bar, body, bug line + links, checkbox
        -- row, button row. Set here, not in OnShow: the frame is created shown, so
        -- OnShow never fired and the template's default size stayed.
        f:SetHeight(TOP + body:GetStringHeight() + 16 + bugs:GetStringHeight() + 8
            + BNB.BUG_LINKS_H + 16 + 24 + 8 + 26 + BOTTOM)
        if not f._isSkin then
            BuildClassicChrome(f)
        end
        f._cb = cb
        _foreverNotice = f
    end
    f._cb:SetChecked(false)
    f:Show()
    f:Raise()
end

--------------------------------------------------------------------------------
-- EVENT BUS
-- Modules register callbacks via BNB.RegisterEvent(event, callback).
-- Shared events funnel through this one frame. Some modules still keep their
-- own event frame for events only they use (Focus mode, setup wizard,
-- Reference Box, Direct Send...); that is fine, the bus is not exclusive.
-- Each handler runs through securecallfunction: an error is reported
-- (BugSack / scriptErrors) and the remaining handlers still run. At
-- PLAYER_LOGOUT that chain is note save, sticky inline-edit save, then history
-- snapshots, so one failure must not cost the rest (ARCH-01).
--------------------------------------------------------------------------------
local eventFrame = CreateFrame("Frame")
local handlers = {}

function BNB.RegisterEvent(event, callback)
    eventFrame:RegisterEvent(event)
    handlers[event] = handlers[event] or {}
    table.insert(handlers[event], callback)
end

-- Removes one handler; the frame event is unregistered only when none are
-- left. The list is replaced, not edited in place, so an OnEvent loop that is
-- running over the old list is not disturbed.
function BNB.UnregisterEvent(event, callback)
    local list = handlers[event]
    if not list then return end
    local kept = {}
    for _, h in ipairs(list) do
        if h ~= callback then kept[#kept + 1] = h end
    end
    if #kept == 0 then
        handlers[event] = nil
        eventFrame:UnregisterEvent(event)
    else
        handlers[event] = kept
    end
end

eventFrame:SetScript("OnEvent", function(self, event, ...)
    local list = handlers[event]
    if not list then return end
    for i = 1, #list do
        securecallfunction(list[i], event, ...)
    end
end)

--------------------------------------------------------------------------------
-- MESSAGE BUS  (BNB's own messages, ARCH-02 / LIB-03)
-- Game events go through RegisterEvent above; things that happen inside BNB go
-- through CallbackHandler, which the libs already carry:
--   BNB.RegisterMessage(owner, "NoteChanged", fn)   owner = a string or table
--   BNB.UnregisterMessage(owner, "NoteChanged")
--   BNB.UnregisterAllMessages(owner)
--   BNB.SendMessage("NoteChanged", id, fields)
-- fn gets the message name first: fn("NoteChanged", id, fields). One owner holds
-- one handler per message (registering again replaces it), so each subscriber
-- uses its own owner. Handlers run through securecallfunction: an error is
-- reported and the other handlers still run.
-- Use a message where one module would otherwise hook or wrap another's
-- function (hooksecurefunc on BNB, reassigning BNB.X); a new one is listed here.
-- Messages:
--   NoteCreated (id)               Core/NoteManager.lua CreateNote
--   NoteChanged (id, fields)       UpdateNote, after the write (fields as passed);
--                                  RenameTag / DeleteTag / RemoveNoteTag ({ tags })
--   NoteDeleted (ids, permanent)   DeleteNote / DeleteNotes / PurgeNote, after
--                                  removal; ids = the notes actually removed;
--                                  Danger Zone "Delete all notes"
--   NoteRestored (id)              RestoreNote, back from the trash
--   TrashChanged ()                any write to the trash: delete to trash,
--                                  RestoreNote, PurgeTrash, PurgeTrashed,
--                                  EmptyTrash (all in NoteManager)
--   NoteSelected (id)              UI/NoteList.lua SelectNote, after the editor
--                                  loaded the note (nil = none); Note Settings,
--                                  Reference Box, history panel follow it
--   TasksChanged (id)              Features/TaskManager.lua, any task change
--   NoteListRefreshed ()           UI/NoteList.lua, end of RefreshNoteList
--   EditorDirty ()                 UI/NoteEditor.lua MarkDirty, every edit
--   EditorViewMode (id)            AM_EnterViewMode (rich note view tab)
--   SituationsModule (on)          Features/ContextNotes.lua ApplySituationsModule
--   SituationMatches (count)       Features/ContextNotes.lua, every situation
--                                  check (count = notes matching now; 0 when
--                                  the module is off): the data broker text
--                                  (the Situation tabs cover / uncover)
--   TldrSettings (on)              Features/Tldr.lua: the tl;dr module switch, a
--                                  "show it" box or the snippet list changed
--                                  (on = the module's state, ALL-372)
--   SkinChanged ()                 UI/SkinSystem.lua, end of ApplyMainWindowSkin
--                                  (preset / brightness); default-coloured
--                                  stickies re-colour
--   EditorEditMode ()              AM_EnterEditMode, at its end
--   HistoryRescueChanged ()        Features/NoteHistory.lua, after a rescue or a
--                                  lost note's history dropped (ALL-466): the
--                                  Rescue list and its buttons re-count
--   TemplatesChanged ()            Features/NoteTemplates.lua, any write to the
--                                  player's templates (ALL-68 S2): the Settings
--                                  Templates page re-lists
--   TokensChanged ()               Features/Tokens.lua, an item / quest / spell
--                                  a note token waited for has loaded (ALL-481
--                                  S2): the editor's rich view and stickies redraw
--   SpellWordsChanged ()           Features/Spellcheck.lua, the player's own words
--                                  changed (ALL-559 S2): the Spelling page re-lists
--   SettingsShown / SettingsHidden ()   the Settings window's OnShow / OnHide
--   UIFontChanged ()               UI/Fonts.lua, end of ApplyFont: skin button
--                                  labels and the welcome panel re-read
--                                  GetUIFont (ALL-25)
-- Every way a note is created, edited or removed sends one of the Note*
-- messages (audited in ARCH-02 session 2). Writes that send none on purpose:
-- history snapshots, the target display-ID cache, the login scope merge,
-- lastOpened (StampOpened). The note list (UI/NoteList.lua), the Tag Manager,
-- the editor's tag strip and the Trash window + toolbar button redraw from
-- these messages, so code that changes a note or the trash never calls
-- RefreshNoteList / RefreshTagManager / RefreshTagStrip / RefreshTrashWindow /
-- SyncTrashBtnState; a new direct write onto a note must send NoteChanged
-- itself, and the trash is written only through NoteManager.
--------------------------------------------------------------------------------
BNB.callbacks = LibStub("CallbackHandler-1.0"):New(BNB,
    "RegisterMessage", "UnregisterMessage", "UnregisterAllMessages")

function BNB.SendMessage(msg, ...)
    BNB.callbacks:Fire(msg, ...)
end

--------------------------------------------------------------------------------
-- ADDON_LOADED — early initialization gate
--------------------------------------------------------------------------------
BNB.RegisterEvent("ADDON_LOADED", function(event, addonName)
    if addonName == BNB.ADDON_NAME then
        -- DB init happens here so it's available before PLAYER_LOGIN
        BNB.InitializeDB()
        BNB._addonLoaded = true
        -- The Blizzard icon list loads at PLAYER_LOGIN from its own
        -- load-on-demand addon (UI/BlizzardIconList.lua, ALL-62)
    elseif addonName == "BigNoteBoxDB" then
        -- BigNoteBoxDB loaded after BigNoteBox (unusual but possible).
        -- Notes are now in memory — initialise them and clear the unavailable flag.
        BNB.InitNotesDB()
        BNB.MigrateNotesDB()
        BNB._notesAvailable = true
    elseif addonName == "BigNoteBox_History" and BNB._addonLoaded then
        -- The history file loaded after BigNoteBox (it is in OptionalDeps, so
        -- this should not happen): set it up and run the move it missed
        BNB.InitHistoryDB()
        if BNB._notesAvailable then BNB.MoveAutoHistory() end
    end
end)

--------------------------------------------------------------------------------
-- PLAYER_LOGIN — main startup trigger
--------------------------------------------------------------------------------
BNB.RegisterEvent("PLAYER_LOGIN", function()
    -- The character's settings profile, when its name was not known at
    -- ADDON_LOADED (ALL-496; normally done there, Core/Profiles.lua)
    if BNB.Profiles then xpcall(BNB.Profiles.OnLogin, geterrorhandler()) end

    -- Randomize skin preset on login/reload if enabled (before window creation)
    local db = BigNoteBoxDB
    if db and db.skinMode and db.skinRandomize then
        local keys = {}
        for k in pairs(BNB.SKIN_PRESETS or {}) do
            if k ~= (db.skinPreset or "obsidian") then
                keys[#keys + 1] = k
            end
        end
        if #keys > 0 then
            db.skinPreset = keys[math.random(#keys)]
        end
        -- Randomize brightness too if enabled, unless the new preset ignores
        -- it (noBright: OLED, OLED Flat)
        local np = BNB.SKIN_PRESETS and BNB.SKIN_PRESETS[db.skinPreset]
        if db.skinRandomizeBrightness and not (np and np.noBright) then
            -- Pick a random brightness in the 0.5–2.0 range (avoids extremes)
            local MIN_BR, MAX_BR = 0.5, 2.0
            local steps = math.floor((MAX_BR - MIN_BR) / 0.05)
            db.skinBrightness = MIN_BR + math.random(0, steps) * 0.05
        end
    end

    -- Clear the transient "hide all stickies" flag unless the player has opted
    -- to keep stickies hidden persistently across sessions.
    C_Timer.After(0, function()
        local db = BigNoteBoxDB
        if db and db.stickiesHidden and not db.stickiesHiddenPersist then
            db.stickiesHidden = false
        end
    end)
    C_Timer.After(0.5, function()
        if BNB.Initialize then BNB.Initialize() end
        -- The Explorer welcome over the main window, once per account (ALL-543)
        if BNB.ShowExplorerIntroIfDue then pcall(BNB.ShowExplorerIntroIfDue) end
        BNB.ShowForeverNoticeIfDue()
        -- After an update: the patch note + its toast (ALL-409). During
        -- first-time setup the version is only stamped, so a new install gets
        -- no patch note and the wizard isn't interrupted.
        C_Timer.After(0.5, function()
            -- The welcome note (ALL-242): a fresh install only, once per account
            if BNB.WhatsNew and BNB.WhatsNew.CheckAndShow then
                local db = BigNoteBoxDB
                local newInstall = not (db and db.setupComplete == true)
                BNB.WhatsNew.CheckAndShow(newInstall)
                BNB.WhatsNew.CheckWelcome(newInstall)
                BNB.WhatsNew.ShowWelcomeToast()   -- held back until setup was done
            end
        end)
        -- Show migration popup if any supported addon is detected and not dismissed.
        -- Suppressed during first-time setup so the wizard isn't interrupted.
        C_Timer.After(1.0, function()
            if BNB.Migration and BNB.Migration.ShowPopup then
                local db = BigNoteBoxDB
                if not (db and db.setupComplete == true) then return end
                local available = BNB.Migration.DetectAvailable()
                if available and #available > 0 then
                    BNB.Migration.ShowPopup()
                end
            end
        end)
    end)
end)

--------------------------------------------------------------------------------
-- Situation checks (contextual surfacing). Every event below asks for one
-- check through ScheduleContextCheck, which keeps a single pending check
-- (PERF-05): a zone change fires two or three of these events, and each ran
-- its own full check. A request never makes a pending check run sooner, so the
-- zone events keep their settle time when a target change lands in between.
--------------------------------------------------------------------------------
local CONTEXT_CHECK_KEY = "contextCheck"
local _contextCheckAt   = nil   -- GetTime() of the pending check
local function RunContextCheck()
    _contextCheckAt = nil
    if BNB.CheckContextualNotes then BNB.CheckContextualNotes() end
end
local function ScheduleContextCheck(delay)
    if not BNB.CheckContextualNotes then return end
    local at = GetTime() + delay
    if _contextCheckAt and _contextCheckAt > at then at = _contextCheckAt end
    _contextCheckAt = at
    BNB.Debounce(CONTEXT_CHECK_KEY, at - GetTime(), RunContextCheck)
end

-- Target and group changes only matter to player situations
local function PlayerContextsInUse()
    return not BNB.HasPlayerContexts or BNB.HasPlayerContexts()
end

--------------------------------------------------------------------------------
-- PLAYER_ENTERING_WORLD — zone change detection (contextual surfacing)
--------------------------------------------------------------------------------
BNB.RegisterEvent("PLAYER_ENTERING_WORLD", function()
    ScheduleContextCheck(1)
end)

--------------------------------------------------------------------------------
-- ZONE_CHANGED_NEW_AREA — major zone transitions
--------------------------------------------------------------------------------
BNB.RegisterEvent("ZONE_CHANGED_NEW_AREA", function()
    ScheduleContextCheck(0.5)
end)

--------------------------------------------------------------------------------
-- ZONE_CHANGED — sub-zone transitions within the same zone
--------------------------------------------------------------------------------
BNB.RegisterEvent("ZONE_CHANGED", function()
    ScheduleContextCheck(0.5)
end)

--------------------------------------------------------------------------------
-- ZONE_CHANGED_INDOORS — entering/leaving buildings (can change sub-zone)
--------------------------------------------------------------------------------
BNB.RegisterEvent("ZONE_CHANGED_INDOORS", function()
    ScheduleContextCheck(0.5)
end)

--------------------------------------------------------------------------------
-- PLAYER_TARGET_CHANGED — target changed (player-context notes). Tab-targeting
-- keeps moving the check out, so it runs once the target settles.
--------------------------------------------------------------------------------
BNB.RegisterEvent("PLAYER_TARGET_CHANGED", function()
    if PlayerContextsInUse() then ScheduleContextCheck(0.1) end
end)

--------------------------------------------------------------------------------
-- GROUP_ROSTER_UPDATE — someone joined or left (player situations match group
-- members, BUG-25). Fires in bursts in a raid, so one check per second at most.
--------------------------------------------------------------------------------
local _rosterCheckPending = false
BNB.RegisterEvent("GROUP_ROSTER_UPDATE", function()
    if _rosterCheckPending or not BNB.CheckContextualNotes then return end
    if not PlayerContextsInUse() then return end
    _rosterCheckPending = true
    C_Timer.After(1, function()
        _rosterCheckPending = false
        ScheduleContextCheck(0)
    end)
end)

--------------------------------------------------------------------------------
-- Vendor / bank / mailbox / auction house / trainer windows (ALL-232 S4): an
-- "open:" situation matches while its window is open. The window is kept open
-- or shut on every event, the check runs only when a note has such a
-- situation. Both the old events and the interaction manager's, whichever the
-- client fires; a second "open" or "closed" for the same window changes nothing
--------------------------------------------------------------------------------
local WINDOW_EVENTS = {
    MERCHANT_SHOW     = { "vendor",  true }, MERCHANT_CLOSED      = { "vendor",  false },
    BANKFRAME_OPENED  = { "bank",    true }, BANKFRAME_CLOSED     = { "bank",    false },
    MAIL_SHOW         = { "mailbox", true }, MAIL_CLOSED          = { "mailbox", false },
    AUCTION_HOUSE_SHOW = { "auction", true }, AUCTION_HOUSE_CLOSED = { "auction", false },
    TRAINER_SHOW      = { "trainer", true }, TRAINER_CLOSED       = { "trainer", false },
}
local function WindowChanged(key, open)
    if not BNB.SetSituationWindow then return end
    BNB.SetSituationWindow(key, open)
    if BNB.HasSituationKind and BNB.HasSituationKind("open") then ScheduleContextCheck(0) end
end
for event, w in pairs(WINDOW_EVENTS) do
    BNB.RegisterEvent(event, function() WindowChanged(w[1], w[2]) end)
end

-- Enum.PlayerInteractionType names -> window key, for the types the client knows
local INTERACTION_WINDOWS = {}
do
    local PIT = Enum and Enum.PlayerInteractionType
    if PIT then
        for name, key in pairs({ Merchant = "vendor", Banker = "bank", MailInfo = "mailbox",
                                 Auctioneer = "auction", Trainer = "trainer" }) do
            if PIT[name] then INTERACTION_WINDOWS[PIT[name]] = key end
        end
    end
end
BNB.RegisterEvent("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", function(_, t)
    if INTERACTION_WINDOWS[t] then WindowChanged(INTERACTION_WINDOWS[t], true) end
end)
BNB.RegisterEvent("PLAYER_INTERACTION_MANAGER_FRAME_HIDE", function(_, t)
    if INTERACTION_WINDOWS[t] then WindowChanged(INTERACTION_WINDOWS[t], false) end
end)

-- PLAYER_UPDATE_RESTING: entered or left an inn or city ("state:rested")
BNB.RegisterEvent("PLAYER_UPDATE_RESTING", function()
    if BNB.HasSituationKind and BNB.HasSituationKind("state") then ScheduleContextCheck(0.5) end
end)

--------------------------------------------------------------------------------
-- PLAYER_REGEN_DISABLED — entered combat
--------------------------------------------------------------------------------
BNB.RegisterEvent("PLAYER_REGEN_DISABLED", function()
    local db = BigNoteBoxDB
    if not db then return end
    local action = db.combatAction or BNB.DEFAULTS.combatAction

    -- If focus mode is open, exit it first so UIParent is restored before
    -- we apply any combat visibility changes.
    if BNB.IsFocusModeOpen and BNB.IsFocusModeOpen() then
        if BNB.CloseFocusMode then BNB.CloseFocusMode() end
    end

    if action == "nothing" then return end

    -- Record what we hid so we can restore it on leaving combat.
    BNB._combatHiddenMain     = false
    BNB._combatHiddenStickies = false

    -- Hide main window + all companion windows if they are open.
    if BNB.mainFrame and BNB.mainFrame:IsShown() then
        BNB.CloseCompanionWindows()
        -- _skipConfirm: with "Confirm before closing" on, OnHide would re-show
        -- the window and open the confirm popup in combat (BUG-20)
        BNB.mainFrame._skipConfirm = true
        BNB.mainFrame:Hide()
        BNB.mainFrame._skipConfirm = false
        BNB._combatHiddenMain = true
    end

    -- Handle sticky notes based on action.
    if action == "hide_all" then
        -- Hide stickies entirely
        if BNB.Sticky and BNB.Sticky.HideAll then
            BNB.Sticky.HideAll()
            BNB._combatHiddenStickies = true
        end
    elseif action == "hide_minimize" then
        -- Collapse open stickies to their icon tile
        if BNB.Sticky and BNB.Sticky.MinimizeAll then
            BNB.Sticky.MinimizeAll()
            BNB._combatMinimizedStickies = true
        end
    end
end)

--------------------------------------------------------------------------------
-- PLAYER_REGEN_ENABLED — left combat
--------------------------------------------------------------------------------
BNB.RegisterEvent("PLAYER_REGEN_ENABLED", function()
    -- Restore windows that were hidden when combat started.
    if BNB._combatHiddenMain and BNB.mainFrame then
        BNB.mainFrame:Show()
    end
    if BNB._combatHiddenStickies and BNB.Sticky and BNB.Sticky.ShowAll then
        BNB.Sticky.ShowAll()
    end
    if BNB._combatMinimizedStickies and BNB.Sticky and BNB.Sticky.UnminimizeAll then
        BNB.Sticky.UnminimizeAll()
    end
    BNB._combatHiddenMain         = false
    BNB._combatHiddenStickies     = false
    BNB._combatMinimizedStickies  = false
end)

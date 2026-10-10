-- BigNoteBox Features/ContextNotes.lua — Contextual note surfacing
--
-- Matches a note's situations against the player's current environment and
-- surfaces matching notes via:
--   1. Minimap badge (a count overlay on the minimap button)
--   2. Toasts through the toast engine (UI/Toast.lua, ALL-376): one per
--      note, or one with a row per note (toastLayout "group")
--
-- note.situations: a list of situation strings, read through
-- BNB.NoteSituations (Core/NoteFields.lua); the note matches while any one
-- does (ALL-232, NOTES v10; it was the one string note.context). nil = no
-- situation, the note never surfaces by itself.
--   "zone:Elwynn Forest"
--   "instance:Molten Core"
--   "player:Thrall"
--   "subzone:The Canals"
--   "npc:Hogger", "guild:Some Guild"     (ALL-232 S3)
--   "itype:dungeon"  instance type, "open:vendor"  window open,
--   "state:rested"   (ALL-232 S4: values are keys, see SITUATION_CHOICES)
--
-- A note shows when it starts matching (arriving), when it stops (leaving) or
-- both (note.contextTrigger), as often as note.contextFreq allows (ALL-232 S2).
--
-- Public API (called from Events.lua):
--   BNB.CheckContextualNotes()   — call on zone change / login
--
-- Internal:
--   BNB._contextMatches          — list of noteIDs matching current context

local BNB = BigNoteBox
local L   = BNB.L

BNB._contextMatches = BNB._contextMatches or {}
-- noteID -> the situation string it matched by in the last check
BNB._contextMatchedBy = BNB._contextMatchedBy or {}
-- noteID -> list of TomTom uids placed for it, a list of MapPinEnhanced pin
-- ids marked `mpe = true` (ALL-421), or true for the game's own pin
BNB._autoWaypoints  = BNB._autoWaypoints  or {}
-- The next check only takes in where the player is, showing nothing: set when
-- the Situations module is switched back on (ALL-375)
local _quietCheck = false

-- The Situations module (ALL-375): the old Context Popup switch,
-- `contextSurface`, widened to every situation surface. Off = no checks, no
-- popups, no automatic waypoints, the Situation tabs covered, menu entries and
-- list / sticky / Oracle markers hidden; notes keep their situations and
-- waypoints, and Navigate still works (Dukul 2026-10-07)
function BNB.SituationsEnabled()
    return not BigNoteBoxDB or BigNoteBoxDB.contextSurface ~= false
end
-- noteID -> signature of the waypoints last placed for it while it matched
-- (WaypointSig). They are placed again only when the note newly matches or
-- its waypoints changed, not on every check (every target change stole quest
-- super-tracking, BUG-16).
local _wpSent = {}

-- Developer tools > "Trace situation checks" (ALL-192): one chat line per check,
-- per sticky open and per toast, plus the state 3 s later. Needs debug mode too.
local function Trace(fmt, ...)
    local db = BigNoteBoxDB
    if db and db.debugMode and db.debugContextTrace then
        BNB:Print("|cff88bbff[ctx " .. string.format("%.1f", GetTime()) .. "]|r " .. string.format(fmt, ...))
    end
end

-- ── Get current environment strings ───────────────────────────────────────────
local function GetCurrentZone()
    -- GetZoneText() = current zone (e.g. "Elwynn Forest")
    -- GetRealZoneText() = same but also works in instances
    -- GetInstanceInfo() = instance name if in one
    local inInst, instType = IsInInstance()
    if inInst and instType ~= "none" then
        local name = GetInstanceInfo and select(1, GetInstanceInfo()) or GetRealZoneText()
        return "instance", name or ""
    end
    return "zone", GetZoneText() or ""
end
-- Oracle search weights the notes for where the player is (ALL-69.3).
BNB.GetCurrentZone = GetCurrentZone

local function GetCurrentPlayer()
    return (BNB.UnitNameRealm("target"))   -- nil if no target
end

-- Lower-case names of everyone in the group (and you), bare and "-Realm", built
-- once per check from unit tokens. GetRaidRosterInfo only answers in a raid, so
-- party members never matched (BUG-25). Reset by CheckContextualNotes.
local _groupNames = nil
local _groupGuilds = nil   -- lower-case guild names of the others in the group, same lifetime

local function GroupNames()
    if _groupNames then return _groupNames end
    local set = {}
    local function add(unit)
        local name, realm = BNB.UnitNameRealm(unit)
        if not name then return end
        name = name:lower()
        set[name] = true
        if realm and realm ~= "" then set[name .. "-" .. realm:lower()] = true end
    end
    add("player")
    local n = GetNumGroupMembers and GetNumGroupMembers() or 0
    if n > 0 then
        local raid = IsInRaid and IsInRaid()
        for i = 1, raid and n or (n - 1) do
            add((raid and "raid" or "party") .. i)
        end
    end
    _groupNames = set
    return set
end

-- A unit's guild, lower case; never your own (Dukul, 2026-10-04: a note on
-- your own guild would match you all the time)
local function UnitGuild(unit)
    if not (UnitExists(unit) and UnitIsPlayer(unit)) or UnitIsUnit(unit, "player") then return nil end
    local g = GetGuildInfo(unit)
    return (g and g ~= "") and g:lower() or nil
end

-- Guilds of the others in the group, for guild situations
local function GroupGuilds()
    if _groupGuilds then return _groupGuilds end
    local set = {}
    local n = GetNumGroupMembers and GetNumGroupMembers() or 0
    if n > 0 then
        local raid = IsInRaid and IsInRaid()
        for i = 1, raid and n or (n - 1) do
            local g = UnitGuild((raid and "raid" or "party") .. i)
            if g then set[g] = true end
        end
    end
    _groupGuilds = set
    return set
end

-- ── Instance types, windows, rested (ALL-232 S4) ─────────────────────────────
-- Saved as keys, not names, so a note works in every language:
-- "itype:dungeon", "open:vendor", "state:rested". The Situation editor offers
-- the keys listed here (UI/SituationEditor.lua) and shows them through
-- BNB.SituationValueLabel.
local VALUE_LABELS = {
    itype = { dungeon = "SIT_ITYPE_DUNGEON", raid = "SIT_ITYPE_RAID",
              delve = "SIT_ITYPE_DELVE", battleground = "SIT_ITYPE_BATTLEGROUND" },
    open  = { vendor = "SIT_OPEN_VENDOR", bank = "SIT_OPEN_BANK", mailbox = "SIT_OPEN_MAILBOX",
              auction = "SIT_OPEN_AUCTION", trainer = "SIT_OPEN_TRAINER" },
    state = { rested = "SIT_STATE_RESTED" },
}
BNB.SITUATION_CHOICES = {
    -- No delves on Forever
    itype = BNB.IsForever and { "dungeon", "raid", "battleground" }
                           or { "dungeon", "raid", "delve", "battleground" },
    open  = { "vendor", "bank", "mailbox", "auction", "trainer" },
}

-- A situation's value as the player reads it: the label of a key, any other
-- value (a zone, a name) as it is
function BNB.SituationValueLabel(kind, value)
    local key = VALUE_LABELS[kind] and value and VALUE_LABELS[kind][value:lower()]
    return key and L[key] or value
end

-- A situation kind's short name ("Zone", "Player"...), nil for an unknown
-- kind: the Situation editor's rows and the compact note tooltip
local KIND_LABELS = { zone = "STICKY_KIND_ZONE", subzone = "STICKY_KIND_SUBZONE",
                      instance = "STICKY_KIND_INSTANCE", player = "STICKY_KIND_PLAYER",
                      npc = "STICKY_KIND_NPC", guild = "STICKY_KIND_GUILD",
                      itype = "SIT_ROWKIND_ITYPE", open = "SIT_ROWKIND_OPEN",
                      state = "SIT_KIND_RESTED" }
function BNB.SituationKindLabel(kind)
    local key = kind and KIND_LABELS[kind]
    if not key then return nil end
    return L[key]
end

local DELVE_DIFFICULTY = 208

-- The instance type key of the instance you are in, or nil (open world, or a
-- type no choice covers: arena, other scenarios)
local function CurrentInstanceType()
    local inInst, t = IsInInstance()
    if not inInst then return nil end
    local diff = GetInstanceInfo and select(3, GetInstanceInfo())
    if diff == DELVE_DIFFICULTY
       or (C_PartyInfo and C_PartyInfo.IsDelveInProgress and C_PartyInfo.IsDelveInProgress()) then
        return "delve"
    end
    if t == "party" then return "dungeon" end
    if t == "raid"  then return "raid" end
    if t == "pvp"   then return "battleground" end
    return nil
end

-- Window key -> true while that window is open. Kept from events
-- (Core/Events.lua calls BNB.SetSituationWindow): the game has no one
-- question for "is the mailbox open" that other addons' frames cannot fool
local _openWindows = {}
function BNB.SetSituationWindow(key, open)
    _openWindows[key] = open or nil
end

-- ── Match a single note against current context ────────────────────────────────
-- Where the player is, read once per check (PERF-05: it was read again for
-- every note): zone kind and name, sub-zone and target name, lower case.
-- Group names come from GroupNames(), only when a player situation is tested.
local function CurrentEnv()
    local kind, val = GetCurrentZone()
    local tgt = GetCurrentPlayer()
    return {
        zoneKind = kind,
        zone     = (val or ""):lower(),
        subzone  = (GetSubZoneText and GetSubZoneText() or ""):lower(),
        target   = tgt and tgt:lower(),
        tguild   = UnitGuild("target"),
        itype    = CurrentInstanceType(),
        rested   = (IsResting and IsResting()) and true or false,
    }
end

-- What "Use Current" fills in for a key kind: the instance type you are in,
-- the window that is open, or rested while you are. nil = none now
function BNB.CurrentSituationValue(kind)
    if kind == "itype" then return CurrentInstanceType() end
    if kind == "open" then
        for _, k in ipairs(BNB.SITUATION_CHOICES.open) do
            if _openWindows[k] then return k end
        end
        return nil
    end
    if kind == "state" then return (IsResting and IsResting()) and "rested" or nil end
    return nil
end

-- Does one situation string ("zone:Elwynn Forest", "player:Thrall", ...) match?
local function ContextMatches(ctx, env)
    local kind, value = ctx:match("^(%w+):(.+)$")
    if not kind or not value then return false end

    value = value:lower()

    if kind == "zone" or kind == "instance" then
        return env.zoneKind == kind and env.zone == value
    elseif kind == "subzone" then
        return env.subzone == value
    elseif kind == "player" or kind == "npc" then
        -- An NPC matches the same way: by target name, or in the group
        -- (follower dungeons)
        -- Match against full value or just the name portion (before realm hyphen)
        local valName = value:match("^([^-]+)") or value
        local tgt = env.target
        if tgt and (tgt == value or tgt == valName) then return true end
        local group = GroupNames()
        return (group[value] or group[valName]) and true or false
    elseif kind == "guild" then
        -- The target's guild or anyone's in the group; typed without a realm,
        -- so the name matches on any realm (Dukul, 2026-10-04)
        return env.tguild == value or GroupGuilds()[value] == true
    elseif kind == "itype" then
        return env.itype == value
    elseif kind == "open" then
        return _openWindows[value] == true
    elseif kind == "state" then
        return value == "rested" and env.rested
    end
    return false
end

-- Returns the first situation of the note that matches, or nil.
local function NoteMatches(note, env)
    -- Scope guard: character-scoped notes only surface for their owner.
    local sc = note.scope
    if sc and sc ~= "global" then
        local charKey = sc:match("^char:(.+)$")
        if charKey and charKey ~= BNB.currentChar then return false end
    end

    for _, ctx in ipairs(BNB.NoteSituations(note)) do
        if ContextMatches(ctx, env) then return ctx end
    end
    return nil
end

-- Target and group changes only matter to notes with a player situation
-- (PERF-05): Core/Events.lua skips those checks when no note has one, and
-- window / rested changes when no note has that kind (ALL-232 S4). A plain
-- scan, no API calls, so a newly set situation counts at once.
local PLAYER_KINDS = { player = true, npc = true, guild = true }
local function HasKinds(kinds, one)
    local ndb = BNB.NotesDB()
    if not (ndb and ndb.notes) then return false end
    for _, note in pairs(ndb.notes) do
        for _, c in ipairs(BNB.NoteSituations(note)) do
            local k = c:match("^(%w+):")
            if k and (k == one or (kinds and kinds[k])) then return true end
        end
    end
    return false
end
function BNB.HasPlayerContexts() return HasKinds(PLAYER_KINDS) end
function BNB.HasSituationKind(kind) return HasKinds(nil, kind) end

-- ── Minimap badge ──────────────────────────────────────────────────────────────
-- A small FontString overlaid on the minimap button icon showing a count.
local _badge = nil

local function GetOrCreateBadge()
    if _badge then return _badge end
    -- Find the LibDBIcon button (created in Minimap.lua)
    local icon = LibStub and LibStub("LibDBIcon-1.0", true)
    local btn   = icon and icon:GetMinimapButton("BigNoteBox")
    if not btn then return nil end

    _badge = btn:CreateFontString(nil, "OVERLAY", "BNBFontNormalSmall")
    _badge:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 2, -2)
    _badge:SetJustifyH("RIGHT")
    _badge:SetTextColor(1, 0.3, 0.3)
    _badge:Hide()
    return _badge
end

local function UpdateMinimapBadge(count)
    local b = GetOrCreateBadge()
    if not b then return end
    if count and count > 0 then
        b:SetText(tostring(count))
        b:Show()
    else
        b:Hide()
    end
end

-- ── Toasts (UI/Toast.lua, ALL-376) ──────────────────────────────────────────
-- One toast per note (toastLayout "each", the default), or one toast with a
-- row per note ("group", when more than one note shows at once). A note toast
-- shows the note's icon (its own icon frame, an NPC note's portrait), why it
-- showed, its tl;dr or first line and a pin when the situation places a
-- waypoint; each part is a setting (toastShowIcon / Why / Summary / Pin).
-- A note may carry its own style (note.toastStyle) and time on screen
-- (note.toastHold), set from the toast's right-click menu.

local function Setting(key)
    local db = BigNoteBoxDB
    local v  = db and db[key]
    if v == nil then v = BNB.DEFAULTS[key] end
    return v
end

-- A click on the toast opens the note in the main window: through the note
-- list's own Open (creates the window if needed, clears a sidebar or search
-- filter that hides the note). A bare mainFrame:Show() + SelectNote did
-- nothing before the window existed and left a filtered note unselected
local function OpenNote(id)
    if BNB.OpenNoteInMain and BNB.GetNote(id) then BNB.OpenNoteInMain(id) end
end

-- Left click follows the note's Show as: a note shown as toast and sticky
-- whose sticky was closed since opens it again; anything else opens in the
-- main window
local function ClickNote(id)
    local note = BNB.GetNote(id)
    if not note then return end
    if note.contextDisplay == "both" and BNB.StickiesEnabled() and BNB.Sticky
       and not BNB.Sticky.IsOpen(id) then
        BNB.Sticky.Open(id)
        return
    end
    OpenNote(id)
end

-- The demo notes of the Test button (TestSituationToasts), by id; nil while
-- no test ran. Looked up before the real notes, so the toasts need no fakes
local _demo = nil
local function ToastNote(id)
    return (_demo and _demo[id]) or BNB.GetNote(id)
end

-- leftBy: noteID -> the situation string it was left by, for notes shown on
-- leaving (ALL-232); the line under the title / the row tag says so
local function LeftTextFor(leftBy, id)
    local k, v = (leftBy[id] or ""):match("^(%w+):(.+)$")
    if not v then return nil end
    -- A player is not left but gone: "Thrall is gone", name without realm
    if k == "player" or k == "npc" or k == "guild" then return string.format(L["CONTEXT_GONE"], v:match("^([^-]+)") or v) end
    -- A window is closed, not left: "Vendor closed" (ALL-232 S4)
    if k == "open" then return string.format(L["CONTEXT_CLOSED"], BNB.SituationValueLabel(k, v)) end
    if k == "state" then return L["CONTEXT_NOT_RESTED"] end
    return string.format(L["CONTEXT_LEFT"], BNB.SituationValueLabel(k, v))
end

-- Why a note showed: what was left; else who is here, what is open, the
-- place it matched by; else the zone
-- What one matching situation string says on a toast (nil = not a situation)
local function SituationWhy(sit)
    local k, v = (sit or ""):match("^(%w+):(.+)$")
    if not v then return nil end
    if k == "player" or k == "npc" then return string.format(L["CONTEXT_HERE"], v:match("^([^-]+)") or v) end
    if k == "guild" then return string.format(L["CONTEXT_GUILD_HERE"], v) end
    if k == "open" then return string.format(L["CONTEXT_OPEN"], BNB.SituationValueLabel(k, v)) end
    if k == "state" then return L["CONTEXT_RESTED"] end
    return BNB.SituationValueLabel(k, v)
end

local function WhyText(id, leftBy, locationName)
    local left = LeftTextFor(leftBy, id)
    if left then return left end
    return SituationWhy(BNB._contextMatchedBy[id]) or locationName
end

-- The note's tl;dr (ALL-372, while the module and its "On situation toasts"
-- box are on), else the first line of its text with any rich markup taken
-- out. The toast cuts it at its width
local function Summary(note)
    local t = BNB.TldrShows("tldrToast") and BNB.NoteTldr(note)
    if t then return t end
    local body = note.body or ""
    local AMode = BNB.AdvancedMode
    if note.richMode and AMode and AMode.StripMarkup then body = AMode.StripMarkup(body) end
    for line in body:gmatch("[^\n]+") do
        line = line:gsub("^%s+", ""):gsub("%s+$", "")
        if line ~= "" then return line end
    end
end

local function NoteTitle(note)
    return (note.title and note.title ~= "") and note.title or L["UNTITLED"]
end

-- The note's own look on its icon: an NPC note's portrait, its icon frame
-- (true = a frame was drawn, which replaces the style's). ownFrame = the
-- toast style keeps its own border, so the note's frame is left off
local function NoteIconSetup(note)
    return function(tex, _, ownFrame)
        if BNB.SetNpcNotePortrait then BNB.SetNpcNotePortrait(tex, note) end
        if note.iconFrame and not ownFrame and BNB.ApplyIconFrame then
            return BNB.ApplyIconFrame(tex, note, tex:GetWidth())
        end
    end
end

-- "Not again today": the note stays quiet for this character until the
-- date changes. Written onto the note like Stamp: not an edit
local function QuietToday(note)
    if not BNB.currentChar then return end
    note.contextSeen = note.contextSeen or {}
    local rec = note.contextSeen[BNB.currentChar] or {}
    note.contextSeen[BNB.currentChar] = rec
    rec.q = BNB.Date("%Y-%m-%d", time())
end

local HOLD_CHOICES = { 5, 10, 30, 60 }
BNB.TOAST_HOLD_CHOICES = HOLD_CHOICES   -- the note's Toast window offers the same (ALL-383)
local NoteSpec   -- forward: the menu redraws the toast with the note's new style

-- The right-click menu of a note toast or a grouped toast's row. owner = the
-- toast or row (the menu closes with it); key = the toast to close after an
-- entry; why = the toast's why line, kept when it redraws
local function NoteMenu(id, owner, key, why)
    local note = BNB.GetNote(id)
    local CM = BNB.ContextMenu
    if not (note and CM) then return end
    local function Close() BNB.Toast.Dismiss(key) end
    local function Redraw()
        if key == "note:" .. id then BNB.Toast.Show(NoteSpec(note, why)) end
    end
    CM.Open(owner, function(root)
        root:CreateTitle(NoteTitle(note), { badge = true,
            icon = (note.icon and note.icon ~= "") and note.icon or nil,
            iconSetup = function(tex) if BNB.SetNpcNotePortrait then BNB.SetNpcNotePortrait(tex, note) end end })
        root:CreateButton(L["TOAST_CM_OPEN"], function() OpenNote(id); Close() end, { icon = "editor" })
        if BNB.StickiesEnabled() and BNB.Sticky then
            root:CreateButton(L["TOAST_CM_STICKY"], function()
                if not BNB.Sticky.IsOpen(id) then BNB.Sticky.Open(id) end
                Close()
            end, { icon = "sticky-note" })
        end
        local wps = BNB.ActiveWaypoints(note)
        if not wps[1] then wps = BNB.NoteWaypoints(note) end
        if wps[1] then
            root:CreateButton(L["TOAST_CM_NAVIGATE"], function() BNB.NavigateWaypoints(note, wps) end,
                { icon = "create-situation" })
        end
        root:CreateDivider()
        root:CreateButton(L["TOAST_CM_QUIET"], function() QuietToday(note); Close() end,
            { icon = "remove-situation", tip = L["TOAST_CM_QUIET_TIP"] })
        -- This note's own style and time on screen (nil = Settings)
        local st = root:CreateButton(L["TOAST_CM_STYLE"], nil, { icon = "note-settings" })
        st:CreateRadio(L["TOAST_CM_DEFAULT"], function() return note.toastStyle == nil end, function()
            BNB.UpdateNote(id, { _clear = { "toastStyle" } }); Redraw()
        end)
        for _, e in ipairs(BNB.ToastStyles.List()) do
            st:CreateRadio(e.label, function() return note.toastStyle == e.key end, function()
                BNB.UpdateNote(id, { toastStyle = e.key }); Redraw()
            end)
        end
        local hold = root:CreateButton(L["TOAST_CM_HOLD"], nil, { icon = "history" })
        hold:CreateRadio(L["TOAST_CM_DEFAULT"], function() return note.toastHold == nil end, function()
            BNB.UpdateNote(id, { _clear = { "toastHold" } }); Redraw()
        end)
        for _, secs in ipairs(HOLD_CHOICES) do
            hold:CreateRadio(string.format(L["TOAST_CM_SECONDS"], secs),
                function() return note.toastHold == secs end,
                function() BNB.UpdateNote(id, { toastHold = secs }); Redraw() end)
        end
        hold:CreateRadio(L["TOAST_CM_UNTIL_CLICKED"], function() return note.toastHold == 0 end,
            function() BNB.UpdateNote(id, { toastHold = 0 }); Redraw() end)
        root:CreateDivider()
        root:CreateButton(L["TOAST_CM_DISMISS"], Close)
    end)
end

-- The engine's spec for one note toast
NoteSpec = function(note, why)
    local id, demo = note.id, note._demo
    local pin = false
    if Setting("toastShowPin") ~= false then
        if demo then pin = note._pin and true or false else pin = BNB.HasActiveWaypoint(note) end
    end
    local spec = {
        key       = "note:" .. id,
        source    = demo and "test" or "situation",
        force     = demo,
        style     = note.toastStyle,
        hold      = note.toastHold,
        icon      = (note.icon and note.icon ~= "") and note.icon or nil,
        noIcon    = Setting("toastShowIcon") == false,
        title     = NoteTitle(note),
        titleColor = note.titleColor,
        text      = (Setting("toastShowWhy") ~= false) and why or nil,
        line2     = (Setting("toastShowSummary") ~= false) and Summary(note) or nil,
        pin       = pin,
        onClick   = function() ClickNote(id) end,
    }
    if not demo then
        spec.iconSetup = NoteIconSetup(note)
        spec.onRightClick = function(_, f) NoteMenu(id, f, spec.key, why) end
    end
    return spec
end

-- The note's own toast as it would show, from its Toast window (ALL-383):
-- shown even in combat and while situation toasts are off (source "test")
function BNB.TestNoteToast(id)
    local note = BNB.GetNote(id)
    if not note then return end
    local spec = NoteSpec(note, L["NOTE_TOAST_TEST_WHY"])
    spec.source, spec.force = "test", true
    BNB.Toast.Show(spec)
end

-- Grouped: one toast, a row per note (the last row says how many more)
local GROUP_ROWS = 8
local function ShowGrouped(ids, locationName, leftBy, demo)
    local rows = {}
    for i, id in ipairs(ids) do
        if #ids > GROUP_ROWS and i == GROUP_ROWS then
            rows[#rows + 1] = { title = string.format(L["TOAST_MORE"], #ids - GROUP_ROWS + 1) }
            break
        end
        local note = ToastNote(id)
        if note then
            local why = WhyText(id, leftBy, locationName)
            local row = { title = "|cffffd100-|r  " .. NoteTitle(note), titleColor = note.titleColor,
                          tag = (why ~= locationName) and why or nil }
            if not demo then
                row.onClick = function() ClickNote(id) end
                row.onRightClick = function(r) NoteMenu(id, r, "situation:group", nil) end
            end
            rows[#rows + 1] = row
        end
    end
    BNB.Toast.Show({
        key = "situation:group", source = demo and "test" or "situation", force = demo,
        title = string.format(L["CONTEXT_BADGE"], #ids), text = locationName, rows = rows,
        onClick = (not demo) and function() ClickNote(ids[1]) end or nil,
    })
end

local function ShowSituationToasts(matchIDs, locationName, leftBy, demo)
    if not BNB.SituationsEnabled() or #matchIDs == 0 then return end
    leftBy = leftBy or {}
    if Setting("toastLayout") == "group" and #matchIDs > 1 then
        ShowGrouped(matchIDs, locationName, leftBy, demo)
        return
    end
    for _, id in ipairs(matchIDs) do
        local note = ToastNote(id)
        if note then BNB.Toast.Show(NoteSpec(note, WhyText(id, leftBy, locationName))) end
    end
end

-- ── Task toasts (ALL-376 S4, ALL-202) ───────────────────────────────────────
-- A task with a situation (its own task.situation, else its list's
-- taskList.situation) shows when that situation newly matches: one toast per
-- note, a row per matching task that is not done and not quiet today. The
-- note's own situations do not count: the note has its own toast (Dukul,
-- 2026-10-07). Only tasks with a situation are looked at, from a list kept
-- until a task or note changes, so a check stays cheap (PERF-05).
local TASK_ROWS = 8
local _taskSits     = nil   -- { { noteID, task, situation }, ... }; nil = build again
local _taskMatchSet = {}    -- "noteID\ttaskID" -> situation, as of the last check
local _taskQuietNext = false   -- the next pass only remembers (a module back on)

local function TaskSituations()
    if _taskSits then return _taskSits end
    _taskSits = {}
    local ndb = BNB.NotesDB()
    for id, note in pairs(ndb and ndb.notes or {}) do
        if note.tasks and #note.tasks > 0 then
            local listSit = note.taskList and note.taskList.situation
            if listSit == "" then listSit = nil end
            for _, task in ipairs(note.tasks) do
                local sit = (task.situation and task.situation ~= "") and task.situation or listSit
                if sit then _taskSits[#_taskSits + 1] = { id, task, sit } end
            end
        end
    end
    return _taskSits
end
local function TaskSitsChanged() _taskSits = nil end
for _, msg in ipairs({ "TasksChanged", "NoteChanged", "NoteCreated", "NoteDeleted", "NoteRestored" }) do
    BNB.RegisterMessage("TaskToasts", msg, TaskSitsChanged)
end

local function TaskKey(noteID, taskID) return noteID .. "\t" .. tostring(taskID) end

-- "Not again today" for one task: in the note's contextSeen record (internal,
-- not an edit), today's date per task id; older days are dropped on write
local function Today() return BNB.Date("%Y-%m-%d", time()) end
local function TaskQuiet(note, taskID)
    local rec = BNB.currentChar and note.contextSeen and note.contextSeen[BNB.currentChar]
    return rec and rec.tq and rec.tq[taskID] == Today() or false
end
local function TaskQuietToday(note, taskID)
    if not BNB.currentChar then return end
    note.contextSeen = note.contextSeen or {}
    local rec = note.contextSeen[BNB.currentChar] or {}
    note.contextSeen[BNB.currentChar] = rec
    local today, keep = Today(), {}
    for k, d in pairs(rec.tq or {}) do if d == today then keep[k] = d end end
    keep[taskID] = today
    rec.tq = keep
end

-- Left click on a task toast or row: the note in the main window with its
-- task list beside it (the Reference Box, or its tasks-only layout)
local function OpenTasks(id)
    if not BNB.GetNote(id) then return end
    OpenNote(id)
    if BNB.OpenReferenceBox then BNB.OpenReferenceBox(id) end
end

local ShowTaskToast   -- forward: the row menu redraws the toast

-- Right click on a task row: Open tasks, Mark done, Not again today, Dismiss
local function TaskRowMenu(id, taskID, owner, key)
    local note = BNB.GetNote(id)
    local task = note and BNB.Task and BNB.Task.FindTask(id, taskID)
    local CM = BNB.ContextMenu
    if not (task and CM) then return end
    CM.Open(owner, function(root)
        root:CreateTitle(task.text or "", { badge = true,
            icon = (note.icon and note.icon ~= "") and note.icon or nil })
        root:CreateButton(L["TOAST_CM_OPEN_TASKS"], function() OpenTasks(id); BNB.Toast.Dismiss(key) end,
            { icon = "reference-box" })
        root:CreateButton(L["TOAST_CM_TASK_DONE"], function()
            if not task.completed then BNB.Task.ToggleTask(id, taskID) end
            ShowTaskToast(id)
        end, { icon = "action" })
        root:CreateDivider()
        root:CreateButton(L["TOAST_CM_QUIET"], function()
            TaskQuietToday(note, taskID)
            ShowTaskToast(id)
        end, { icon = "remove-situation", tip = L["TOAST_CM_TASK_QUIET_TIP"] })
        root:CreateDivider()
        root:CreateButton(L["TOAST_CM_DISMISS"], function() BNB.Toast.Dismiss(key) end)
    end)
end

-- Right click on the toast itself: the note's tasks or the note
local function TaskToastMenu(id, owner, key)
    local note = BNB.GetNote(id)
    local CM = BNB.ContextMenu
    if not (note and CM) then return end
    CM.Open(owner, function(root)
        root:CreateTitle(NoteTitle(note), { badge = true,
            icon = (note.icon and note.icon ~= "") and note.icon or nil,
            iconSetup = function(tex) if BNB.SetNpcNotePortrait then BNB.SetNpcNotePortrait(tex, note) end end })
        root:CreateButton(L["TOAST_CM_OPEN_TASKS"], function() OpenTasks(id); BNB.Toast.Dismiss(key) end,
            { icon = "reference-box" })
        root:CreateButton(L["TOAST_CM_OPEN"], function() OpenNote(id); BNB.Toast.Dismiss(key) end,
            { icon = "editor" })
        root:CreateDivider()
        root:CreateButton(L["TOAST_CM_DISMISS"], function() BNB.Toast.Dismiss(key) end)
    end)
end

-- The note's matching tasks in list order (a sub-task under its parent),
-- not done, not quiet today
local function MatchingTasks(note)
    local T, out = BNB.Task, {}
    local function Take(task, sub)
        local sit = _taskMatchSet[TaskKey(note.id, task.id)]
        if sit and not task.completed and not TaskQuiet(note, task.id) then
            out[#out + 1] = { task = task, sub = sub, sit = sit }
        end
    end
    for _, top in ipairs(T.GetTopLevel(note.id)) do
        Take(top, false)
        for _, sub in ipairs(T.GetSubTasks(note.id, top.id)) do Take(sub, true) end
    end
    return out
end

-- (Re)draws a note's task toast from what matches now; nothing left = the
-- toast goes. Rows list every matching task of the note, so a task that
-- matched earlier stays beside the new one
ShowTaskToast = function(id)
    local key  = "tasks:" .. id
    local note = BNB.GetNote(id)
    local list = note and BNB.TasksEnabled() and MatchingTasks(note) or {}
    if #list == 0 then BNB.Toast.Dismiss(key); return end
    local rows = {}
    for i, m in ipairs(list) do
        if #list > TASK_ROWS and i == TASK_ROWS then
            rows[#rows + 1] = { title = string.format(L["TOAST_MORE"], #list - TASK_ROWS + 1),
                                onClick = function() OpenTasks(id) end }
            break
        end
        local taskID = m.task.id
        rows[#rows + 1] = {
            title = (m.sub and "      " or "") .. "|cffffd100-|r  " .. (m.task.text or ""),
            onClick = function() OpenTasks(id) end,
            onRightClick = function(r) TaskRowMenu(id, taskID, r, key) end,
        }
    end
    local why = SituationWhy(list[1].sit)
    local spec = {
        key = key, source = "tasks",
        style = note.toastStyle, hold = note.toastHold,
        icon = (note.icon and note.icon ~= "") and note.icon or nil,
        noIcon = Setting("toastShowIcon") == false,
        iconSetup = NoteIconSetup(note),
        title = NoteTitle(note), titleColor = note.titleColor,
        text = (Setting("toastShowWhy") ~= false and why) and string.format(L["TOAST_TASKS_WHY"], why) or nil,
        rows = rows,
        onClick = function() OpenTasks(id) end,
    }
    spec.onRightClick = function(_, f) TaskToastMenu(id, f, key) end
    BNB.Toast.Show(spec)
end

-- One pass over the tasks with a situation: the new match set, and the notes
-- with a task that matches now and did not before (quiet = remember, show
-- nothing: Situations back on). Returns those note ids
local function CheckTaskSituations(env, quiet)
    local now, newBy, newIDs = {}, {}, {}
    if BNB.TasksEnabled() and BNB.Task then
        for _, e in ipairs(TaskSituations()) do
            local noteID, task, sit = e[1], e[2], e[3]
            if not task.completed and ContextMatches(sit, env) then
                local k = TaskKey(noteID, task.id)
                now[k] = sit
                if not _taskMatchSet[k] and not newBy[noteID] then
                    newBy[noteID] = true
                    newIDs[#newIDs + 1] = noteID
                end
            end
        end
    end
    _taskMatchSet = now
    if quiet or _taskQuietNext then _taskQuietNext = false; return {} end
    return newIDs
end

-- Situations or Tasks switched off: every task toast goes and the matches
-- are forgotten; the next pass (back on) only remembers where the player
-- is, so not every task here shows as new
function BNB.ResetTaskToasts()
    _taskMatchSet = {}
    _taskQuietNext = true
    BNB.Toast.DismissAll("tasks")
end

-- Settings > Modules > Toasts > Test: three demo notes in the chosen
-- layout. Their ids are not notes, so a click on one opens nothing
local DEMO = {
    { id = "demo:1", icon = "Interface\\Icons\\INV_Misc_Note_01", key = "TOAST_TEST_1", body = "TOAST_TEST_BODY_1", pin = true },
    { id = "demo:2", icon = "Interface\\Icons\\INV_Misc_Map_01",  key = "TOAST_TEST_2", body = "TOAST_TEST_BODY_2" },
    { id = "demo:3", icon = "Interface\\Icons\\INV_Letter_15",    key = "TOAST_TEST_3", body = "TOAST_TEST_BODY_3" },
}
function BNB.TestSituationToasts()
    _demo = {}
    local ids = {}
    for _, d in ipairs(DEMO) do
        _demo[d.id] = { id = d.id, icon = d.icon, title = L[d.key], body = L[d.body], _demo = true, _pin = d.pin }
        ids[#ids + 1] = d.id
    end
    local _, locName = GetCurrentZone()
    ShowSituationToasts(ids, locName, nil, true)
    -- A task toast too while Tasks is on (ALL-376 S4): demo rows, no clicks
    if BNB.TasksEnabled() then
        local rows = {}
        for _, k in ipairs({ "TOAST_TEST_TASK_1", "TOAST_TEST_TASK_2", "TOAST_TEST_TASK_3" }) do
            rows[#rows + 1] = { title = "|cffffd100-|r  " .. L[k] }
        end
        BNB.Toast.Show({
            key = "tasks:demo", source = "test", force = true,
            icon = "Interface\\Icons\\INV_Misc_Note_02", title = L["TOAST_TEST_TASKS"],
            text = (Setting("toastShowWhy") ~= false and locName) and string.format(L["TOAST_TASKS_WHY"], locName) or nil,
            noIcon = Setting("toastShowIcon") == false, rows = rows,
        })
    end
end

-- ── When and how often (ALL-232 S2) ──────────────────────────────────────────
-- note.contextTrigger: nil = the note shows on arriving, "leave" = on leaving,
-- "both". note.contextFreq: nil = every time, or once per "session" / "day" /
-- "daily" reset / "weekly" reset / "once" ever, counted per character and
-- separately for arriving ("a") and leaving ("l") in note.contextSeen.
local function ShowsOn(note, which)
    local t = note.contextTrigger
    if which == "a" then return t == nil or t == "both" end
    return t == "leave" or t == "both"
end

-- When this character's play session began. Kept in its knownChars record so
-- a /reload is not a new session: "once per session" would show again after
-- every reload otherwise.
local _sessionStart = time()
BNB.RegisterEvent("PLAYER_ENTERING_WORLD", function(_, isLogin)
    local kc  = BigNoteBoxDB and BigNoteBoxDB.knownChars
    local rec = kc and BNB.currentChar and kc[BNB.currentChar]
    if not rec then return end
    if isLogin or not rec.sessionStart then rec.sessionStart = time() end
    _sessionStart = rec.sessionStart
end)

-- The most recent daily / weekly reset (as TaskManager's LastDailyReset)
local function LastReset(kind, now)
    local api  = C_DateAndTime
    local fn   = api and (kind == "daily" and api.GetSecondsUntilDailyReset
                          or api.GetSecondsUntilWeeklyReset)
    local secs = fn and fn()
    if not secs then return nil end
    return now + secs - (kind == "daily" and 86400 or 7 * 86400)
end

local function Due(note, which)
    local rec  = note.contextSeen and note.contextSeen[BNB.currentChar]
    -- "Not again today" from the toast's menu (ALL-376)
    if rec and rec.q and rec.q == BNB.Date("%Y-%m-%d", time()) then return false end
    local freq = note.contextFreq
    if not freq then return true end
    local last = rec and rec[which]
    if not last then return true end
    if freq == "once" then return false end
    if freq == "session" then return last < _sessionStart end
    local now = time()
    if freq == "day" then return BNB.Date("%Y-%m-%d", last) ~= BNB.Date("%Y-%m-%d", now) end
    if freq == "daily" or freq == "weekly" then
        local reset = LastReset(freq, now)
        return not reset or last < reset
    end
    return true   -- a value from a newer build: every time
end

-- Written straight onto the note, not through UpdateNote: showing is not an
-- edit (no "Edited" bump, no NoteChanged)
local function Stamp(note, which)
    if not note.contextFreq or not BNB.currentChar then return end
    note.contextSeen = note.contextSeen or {}
    local rec = note.contextSeen[BNB.currentChar] or {}
    note.contextSeen[BNB.currentChar] = rec
    rec[which] = time()
end

-- Where a note that is due goes, by its display mode: a sticky, a toast.
-- Sticky Notes off (ALL-343): the toast, the mode is kept. Toasts off, or
-- situation toasts off (ALL-384): no toast
local function Destinations(note)
    local d = note.contextDisplay
    if not BNB.StickiesEnabled() then d = nil end
    local sticky = d == "sticky" or d == "both"
    local toast  = d ~= "sticky" and BNB.ToastsEnabled() and BNB.ToastSourceOn("situation")
    return sticky, toast
end

-- A note that would show nowhere is not counted as shown, so its how-often
-- is not used up while toasts are off
local function ShowsAnywhere(note)
    local sticky, toast = Destinations(note)
    return sticky or toast
end

-- Sorts a note that is due to show into the sticky / popup lists
local function AddByDisplay(note, stickyIDs, popupIDs)
    local sticky, toast = Destinations(note)
    if sticky then stickyIDs[#stickyIDs + 1] = note.id end
    if toast  then popupIDs[#popupIDs + 1] = note.id end
end

-- ── Main check ────────────────────────────────────────────────────────────────
-- ── Situation waypoints (ALL-282) ───────────────────────────────────────────
-- A note places every waypoint that is on (BNB.ActiveWaypoints) through
-- TomTom:AddWaypoint, else through MapPinEnhanced 4.0+'s pin groups (ALL-421),
-- or, without either, the first of them (WaypointUI has no
-- TomTom API: it draws the game's pin in the world, ALL-307)
-- as the game's own map pin, which holds one point.
local function HasTomTom() return BNB.HasTomTom() end

-- ── MapPinEnhanced 4.0+ (ALL-421) ───────────────────────────────────────────
-- Every pin BNB places there goes into its own "BigNoteBox" group, named, with
-- an id to remove it by. The group is registered on first use and again when
-- the user has deleted it; registering every time would print MPE's "added
-- hidden group" line on each pin while the user keeps it hidden. A failure (a
-- group of that name the user made) means the game's pin for this session.
-- MPE's group functions take no self: dot calls.
local MPE_GROUP = { name = "BigNoteBox", source = "BigNoteBox", groupID = "bignotebox",
                    icon = "Interface\\AddOns\\BigNoteBox\\Assets\\icon" }
local _mpeGroup, _mpeFailed
-- Pins added this session by position, so placing the same spot again (a
-- second Navigate) replaces the pin: MPE groups do not skip duplicates
local _mpeByPos = {}

function BNB.MPEUsable() return not _mpeFailed and BNB.HasMPEGroups() end

-- Adds one pin to BNB's group (x, y 0-1); returns its id, or nil
function BNB.MPEAddPin(mapID, x, y, title, track)
    if not BNB.MPEUsable() then return nil end
    local pos = string.format("%s:%.4f:%.4f", mapID, x, y)
    if _mpeByPos[pos] then
        pcall(MapPinEnhanced.DeletePin, _mpeByPos[pos]); _mpeByPos[pos] = nil
    end
    for _ = 1, 2 do
        if not _mpeGroup then
            local ok, gid = pcall(MapPinEnhanced.RegisterGroup, CopyTable(MPE_GROUP))
            if not (ok and gid) then _mpeFailed = true; return nil end
            _mpeGroup = gid
        end
        local ok, pinID = pcall(MapPinEnhanced.AddPinToGroup, _mpeGroup,
            { mapID = mapID, x = x, y = y, title = title, setTracked = track and true or nil })
        if ok and pinID then _mpeByPos[pos] = pinID; return pinID end
        _mpeGroup = nil   -- deleted by the user since: register it again, once
    end
    return nil
end

function BNB.MPEDeletePin(pinID)
    if pinID and BNB.HasMPEGroups() then pcall(MapPinEnhanced.DeletePin, pinID) end
end

-- A note's waypoints as MPE pins, tracking the first unless noTrack. Returns
-- the placed list ({ mpe = true, pinID, ... }) or nil when none went in
local function PlaceMPEPins(note, list, noTrack)
    local ids = { mpe = true }
    for i, wp in ipairs(list) do
        local pinID = BNB.MPEAddPin(wp.mapID, wp.x / 100, wp.y / 100,
            BNB.WaypointName(note, wp), i == 1 and not noTrack)
        if pinID then ids[#ids + 1] = pinID end
    end
    return ids[1] and ids or nil
end

-- MPE keeps its pins over a /reload, BNB's _autoWaypoints does not: the ids
-- of situation pins are saved (BigNoteBoxDB.mpePins) and removed once per
-- load, before the first placement, so a reload does not place them twice.
-- With MPE off they are kept for the next load that has it
local _mpeSwept = false
local function SweepSavedMPEPins()
    if _mpeSwept or not BNB.HasMPEGroups() then return end
    _mpeSwept = true
    local saved = BigNoteBoxDB and BigNoteBoxDB.mpePins
    if not saved then return end
    for id, ids in pairs(saved) do
        if not BNB._autoWaypoints[id] then
            for _, pinID in ipairs(ids) do BNB.MPEDeletePin(pinID) end
        end
    end
    wipe(saved)
end
BNB.RegisterEvent("PLAYER_ENTERING_WORLD", function() SweepSavedMPEPins() end)

local function SaveMPEPins(id, ids)
    local saved = BigNoteBoxDB and BigNoteBoxDB.mpePins
    if not saved then return end
    if ids then
        local copy = {}
        for i, pinID in ipairs(ids) do copy[i] = pinID end
        saved[id] = copy
    else
        saved[id] = nil
    end
end

-- Removes the TomTom waypoints or MPE pins placed for a note. The game's pin
-- (true) is left to the caller: it may belong to another note by now
local function RemoveTomTomWaypoints(id)
    local placed = BNB._autoWaypoints[id]
    if type(placed) ~= "table" then return end
    if placed.mpe then
        for _, pinID in ipairs(placed) do BNB.MPEDeletePin(pinID) end
        SaveMPEPins(id, nil)
    elseif TomTom and TomTom.RemoveWaypoint then
        for _, uid in ipairs(placed) do
            pcall(function() TomTom:RemoveWaypoint(uid) end)
        end
    end
end

-- The game's pin is one point: another note may have placed it since
local function NativePinTaken(byOtherThan)
    for id, placed in pairs(BNB._autoWaypoints) do
        if placed == true and id ~= byOtherThan then return true end
    end
    return false
end

local function ClearNativePin()
    if C_Map and C_Map.ClearUserWaypoint then pcall(C_Map.ClearUserWaypoint) end
end

-- What the placed waypoints look like: map, coordinates and, with TomTom, the
-- name (the game's pin has none, and placing it again would take quest
-- super-tracking back, BUG-16). nil = nothing to place
local function WaypointSig(note, list, withNames)
    if not list[1] then return nil end
    local parts = {}
    for i, wp in ipairs(list) do
        parts[i] = wp.mapID .. ":" .. wp.x .. ":" .. wp.y
            .. (withNames and (":" .. BNB.WaypointName(note, wp)) or "")
    end
    return table.concat(parts, "|")
end

-- Places a matching note's waypoints when they differ from what was placed
-- for it last; the old ones go first, so a moved waypoint is replaced, not
-- doubled. A note with none left has its own removed.
local function PlaceNoteWaypoints(id)
    SweepSavedMPEPins()   -- before the first placement of this load
    local note   = BNB.GetNote(id)
    local tomtom = HasTomTom()
    local mpe    = not tomtom and BNB.MPEUsable()
    local list   = note and BNB.ActiveWaypoints(note, not (tomtom or mpe)) or {}
    local sig    = note and WaypointSig(note, list, tomtom or mpe)
    if _wpSent[id] == sig then return end
    _wpSent[id] = sig

    local placed = BNB._autoWaypoints[id]
    RemoveTomTomWaypoints(id)
    BNB._autoWaypoints[id] = nil
    if not sig then
        if placed == true and not NativePinTaken(id) then ClearNativePin() end
        return
    end

    if tomtom then
        local uids = {}
        for i, wp in ipairs(list) do
            -- crazy = false: placed, but TomTom's arrow is not switched to it.
            -- The arrow goes to the first one only, never with "Don't track
            -- it" (note.wpNoTrack, SUG-10)
            local wpOpts = { title = BNB.WaypointName(note, wp), from = "BigNoteBox" }
            if note.wpNoTrack or i > 1 then wpOpts.crazy = false end
            local ok, uid = pcall(function()
                return TomTom:AddWaypoint(wp.mapID, wp.x / 100, wp.y / 100, wpOpts)
            end)
            if ok and uid then uids[#uids + 1] = uid end
        end
        if uids[1] then BNB._autoWaypoints[id] = uids end
        return
    end
    -- MapPinEnhanced 4.0+: every waypoint, named, the first tracked unless
    -- "Don't track it"; none went in = the game's pin below
    local ids = mpe and PlaceMPEPins(note, list, note.wpNoTrack)
    if ids then
        BNB._autoWaypoints[id] = ids
        SaveMPEPins(id, ids)
    elseif C_Map and C_Map.SetUserWaypoint then
        local wp = list[1]
        -- The pin moves here: no other note holds it any more
        for other, p in pairs(BNB._autoWaypoints) do
            if p == true then BNB._autoWaypoints[other] = nil end
        end
        pcall(function()
            C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(wp.mapID, wp.x / 100, wp.y / 100))
            if not note.wpNoTrack and C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then
                C_SuperTrack.SetSuperTrackedUserWaypoint(true)
            end
        end)
        BNB._autoWaypoints[id] = true
    end
end

-- The zone name of a waypoint: the map's own name in this client's language,
-- else the name saved with it
function BNB.WaypointZone(wp)
    local info = wp and wp.mapID and C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(wp.mapID)
    return (info and info.name) or (wp and wp.label) or ""
end

-- The sub-zone the player stands in, nil when none (the game answers "" or
-- the zone's own name there). Saved with a new note and a pinned waypoint
-- (ALL-354)
function BNB.CurrentSubzone()
    local sub = GetSubZoneText and GetSubZoneText() or ""
    if sub == "" or sub == (GetZoneText and GetZoneText() or "") then return nil end
    return sub
end

-- Navigate: places the given waypoints and tracks them, whatever "Don't track
-- it" says (only the situation's own placement honours it). TomTom takes them
-- all, its arrow on the first; so does MapPinEnhanced 4.0+; the game's pin
-- takes the first; with none, a /way line to copy into a waypoint addon
function BNB.NavigateWaypoints(note, list)
    local first = list and list[1]
    if not first then return end
    local name = BNB.WaypointName(note, first)
    if HasTomTom() then
        for i, wp in ipairs(list) do
            local opts = { title = BNB.WaypointName(note, wp), from = "BigNoteBox" }
            if i > 1 then opts.crazy = false end
            pcall(function() TomTom:AddWaypoint(wp.mapID, wp.x / 100, wp.y / 100, opts) end)
        end
        BNB:Print(string.format(L["NC_WP_TOMTOM_MSG"], name, first.x, first.y))
        return
    end
    -- MapPinEnhanced 4.0+: all of them in BNB's group, kept until the user
    -- removes them (asked for, unlike a situation's own)
    if BNB.MPEUsable() and PlaceMPEPins(note, list) then
        BNB:Print(string.format(L["NC_WP_MPE_MSG"], name, first.x, first.y))
        return
    end
    if C_Map and C_Map.SetUserWaypoint then
        local ok = pcall(function()
            C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(first.mapID, first.x / 100, first.y / 100))
            if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then
                C_SuperTrack.SetSuperTrackedUserWaypoint(true)
            end
        end)
        if ok then
            BNB:Print(string.format(L["NC_WP_MAP_PIN_MSG"], name, first.x, first.y))
            return
        end
    end
    local wayStr = string.format("/way %s %.1f %.1f %s", BNB.WaypointZone(first), first.x, first.y, name)
    BNB:Print(string.format(L["STICKY_WP_NO_ADDON_COPY_FMT"], wayStr))
end

-- Takes a note's placed waypoints off the map (Clear all situations), and
-- forgets them, so the next match places them again
function BNB.RemoveNoteWaypoints(id)
    local placed = BNB._autoWaypoints[id]
    RemoveTomTomWaypoints(id)
    if placed == true and not NativePinTaken(id) then ClearNativePin() end
    BNB._autoWaypoints[id] = nil
    _wpSent[id] = nil
end

-- ── /way lines (ALL-381) ────────────────────────────────────────────────────
-- A /way line as TomTom and Wowhead write it: "/way Zone 45.2 60.1 Name",
-- "/way #84 45.2 60.1 Name" (map id), "/way 45.2 60.1" (where you are); "/tway"
-- too, and "45.2,60.1". Only the shape is read here: the zone name is looked up
-- when the link is clicked (BNB.WayLineWaypoint). Returns x, y, zone (or nil),
-- mapID (the #id, or nil), name (or nil); nil when it is not a /way line (x
-- comes first, so the answer itself says whether it is one).
function BNB.ParseWayLine(s)
    local rest = s and s:match("^%s*/[Tt]?[Ww][Aa][Yy]%s+(.-)%s*$")
    if not rest then return nil end
    local mapID
    local id, after = rest:match("^#(%d+)%s+(.*)$")
    if id then mapID, rest = tonumber(id), after end
    local zone, x, y, name = rest:match("^(.-)%s*(%d+%.?%d*)%s*[,%s]%s*(%d+%.?%d*)%s*(.-)$")
    x, y = tonumber(x), tonumber(y)
    if not (x and y and x <= 100 and y <= 100) then return nil end
    if mapID and zone ~= "" then return nil end   -- "#84 Zone 45 60" is not a shape anyone writes
    if zone ~= "" and not zone:find("%a") then return nil end
    return x, y, zone ~= "" and zone or nil, mapID, name ~= "" and name or nil
end

-- The waypoint a /way line points at: { mapID, x, y, name } (name = the
-- line's own name, else the zone's), or nil + a chat line for the player
function BNB.WayLineWaypoint(s)
    local x, y, zone, mapID, name = BNB.ParseWayLine(s)
    if not x then return nil end
    if not mapID and zone then
        mapID = BNB.ZonePicker and BNB.ZonePicker.ZoneMapID and BNB.ZonePicker.ZoneMapID(zone)
        if not mapID then return nil, string.format(L["WAY_LINK_UNKNOWN_ZONE"], zone) end
    elseif not mapID then
        mapID = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    end
    if not (mapID and C_Map.GetMapInfo(mapID)) then
        return nil, string.format(L["WAY_LINK_UNKNOWN_ZONE"], zone or ("#" .. tostring(mapID)))
    end
    local wp = { mapID = mapID, x = x, y = y, name = name }
    if not name then wp.name = BNB.WaypointZone(wp) end
    return wp
end

-- A click on a /way link in a rich note: placed and tracked like Navigate;
-- Shift = show it on the map instead (ALL-381, ALL-319)
function BNB.FollowWayLine(s, onMap)
    local wp, err = BNB.WayLineWaypoint(s)
    if not wp then
        if err then BNB:Print(err) end
        return
    end
    if onMap then BNB.ShowWaypointOnMap(wp) else BNB.NavigateWaypoints(nil, { wp }) end
end

-- ── Show on map (ALL-319) ───────────────────────────────────────────────────
-- Opens the world map on the waypoint's map with a marker on the spot. Nothing
-- is placed or tracked. The marker is our own frame on the map canvas, held at
-- one size whatever the zoom, and shown only while the map shows that map.
local _mapMarker, _markerWP

local function MapCanvas()
    local wm = WorldMapFrame
    if not wm then return nil end
    return (wm.GetCanvas and wm:GetCanvas()) or (wm.ScrollContainer and wm.ScrollContainer.Child)
end

local MARKER_PX = 30
local function PlaceMapMarker()
    local m, wp, wm = _mapMarker, _markerWP, WorldMapFrame
    local canvas = MapCanvas()
    if not (m and wp and canvas and wm:IsShown()) or wm:GetMapID() ~= wp.mapID then
        if m then m:SetAlpha(0) end
        return
    end
    local s = 1 / math.max(canvas:GetScale(), 0.01)
    m:SetScale(s)
    m:ClearAllPoints()
    m:SetPoint("BOTTOM", canvas, "TOPLEFT",
        canvas:GetWidth() * wp.x / 100 / s, -canvas:GetHeight() * wp.y / 100 / s)
    m:SetAlpha(1)
end

local function MapMarker()
    if _mapMarker then return _mapMarker end
    local canvas = MapCanvas()
    local m = CreateFrame("Frame", nil, canvas)
    m:SetSize(MARKER_PX, MARKER_PX)
    m:SetFrameLevel(math.min(canvas:GetFrameLevel() + 500, 9000))   -- over the map's own pins
    m:EnableMouse(false)
    -- The note list's location marker, normal look (it sits on the game's map)
    local dir = "Interface\\AddOns\\BigNoteBox\\Assets\\Overlay\\"
    for i, path in ipairs({ dir .. "Layers\\ov-bottom", dir .. "Symbols\\ov-location", dir .. "Layers\\ov-top" }) do
        local t = m:CreateTexture(nil, "OVERLAY", nil, i)
        t:SetAllPoints()
        t:SetTexture(path)
    end
    -- A few pulses so the eye finds it
    local ag = m:CreateAnimationGroup()
    ag:SetLooping("BOUNCE")
    local a = ag:CreateAnimation("Alpha")
    a:SetFromAlpha(1); a:SetToAlpha(0.35); a:SetDuration(0.5)
    m._pulse = ag
    m:SetScript("OnUpdate", PlaceMapMarker)
    WorldMapFrame:HookScript("OnHide", function()
        _markerWP = nil
        m:Hide()
    end)
    _mapMarker = m
    return m
end

function BNB.ShowWaypointOnMap(wp)
    if not (wp and wp.mapID and wp.x and wp.y) then return end
    local ok = pcall(function()
        if C_Map.OpenWorldMap then
            C_Map.OpenWorldMap(wp.mapID)
        elseif OpenWorldMap then
            OpenWorldMap(wp.mapID)
        end
        local wm = WorldMapFrame
        if wm and wm:IsShown() and wm:GetMapID() ~= wp.mapID then wm:SetMapID(wp.mapID) end
    end)
    if not (ok and WorldMapFrame and WorldMapFrame:IsShown() and MapCanvas()) then
        BNB:Print(L["WP_MAP_FAILED"]); return
    end
    _markerWP = { mapID = wp.mapID, x = wp.x, y = wp.y }
    local m = MapMarker()
    m:Show()
    PlaceMapMarker()
    m._pulse:Stop(); m._pulse:Play()
    C_Timer.After(3, function() if m._pulse then m._pulse:Stop() end end)
end

function BNB.CheckContextualNotes()
    if not BNB.SituationsEnabled() then
        UpdateMinimapBadge(0)
        return
    end
    local ndb = BNB.NotesDB()
    if not ndb or not ndb.notes then return end

    _groupNames, _groupGuilds = nil, nil   -- group may have changed since the last check
    local env = CurrentEnv()
    local matches   = {}
    local matchSet  = {}
    local matchedBy = {}
    for _, note in pairs(ndb.notes) do
        if note and BNB.HasSituation(note) then
            local by = NoteMatches(note, env)
            if by then
                matches[#matches + 1]  = note.id
                matchSet[note.id]      = true
                matchedBy[note.id]     = by
            end
        end
    end

    local prev    = BNB._contextMatches or {}
    local prevBy  = BNB._contextMatchedBy or {}
    -- Tasks whose situation newly matches (ALL-376 S4), quiet as the notes
    local newTaskNotes = CheckTaskSituations(env, _quietCheck)
    -- Back on after the module was off: nothing arrived or was left, the
    -- player was simply somewhere (only the waypoints are placed)
    if _quietCheck then
        _quietCheck = false
        prev, prevBy = matches, matchedBy
    end
    local prevSet = {}
    for _, id in ipairs(prev) do prevSet[id] = true end

    BNB._contextMatches = matches
    BNB._contextMatchedBy = matchedBy

    -- Notes to show: newly matching ones that show on arriving, and notes
    -- left that show on leaving; each only when its how-often allows
    local newStickyIDs, newPopupIDs, leftBy = {}, {}, {}
    local arrived, left = 0, 0
    for _, id in ipairs(matches) do
        local note = BNB.GetNote(id)
        if not prevSet[id] and note and ShowsOn(note, "a") and Due(note, "a")
           and ShowsAnywhere(note) then
            Stamp(note, "a")
            AddByDisplay(note, newStickyIDs, newPopupIDs)
            arrived = arrived + 1
        end
    end
    for _, id in ipairs(prev) do
        local note = not matchSet[id] and BNB.GetNote(id)
        local by   = prevBy[id]
        -- Only a real departure: a note whose situation was just removed or
        -- changed in the editor also stops matching, and must not pop up
        if note and ShowsOn(note, "l") and by and BNB.NoteHasSituation(note, by)
           and Due(note, "l") and ShowsAnywhere(note) then
            Stamp(note, "l")
            AddByDisplay(note, newStickyIDs, newPopupIDs)
            leftBy[id] = by
            left = left + 1
        end
    end

    -- ── Zone-leave: notes that were matching but no longer are ─────────────────
    local hasKeepWP = false  -- track if any departing note wants to keep its WP
    for _, id in ipairs(prev) do
        if not matchSet[id] then
            _wpSent[id] = nil   -- set it again on the next entry
            local note = BNB.GetNote(id)
            -- nil/"keep", "minimize", "hide". Only for a note that shows on
            -- arriving alone: one that shows on leaving has just been shown
            local action = note and not ShowsOn(note, "l") and note.contextLeave
            if action and action ~= "keep" and BNB.Sticky and BNB.Sticky.IsOpen(id) then
                if action == "hide" then
                    pcall(function() BNB.Sticky.Close(id) end)
                elseif action == "minimize" then
                    pcall(function() BNB.Sticky.SetMinimized(id, true) end)
                end
            end
            -- Waypoint removal on zone leave. The game's own pin (true) is
            -- deferred: cleared after the loop only if no other departing note
            -- wants to keep it
            if note and note.wpClearOnLeave and BNB._autoWaypoints[id] then
                RemoveTomTomWaypoints(id)
                BNB._autoWaypoints[id] = nil
            elseif note and not note.wpClearOnLeave and BNB._autoWaypoints[id] then
                hasKeepWP = true
            end
        end
    end
    -- Retail single-waypoint: clear only if no departing note wants to keep it
    if not hasKeepWP then
        local shouldClear = false
        for _, id in ipairs(prev) do
            if not matchSet[id] then
                local note = BNB.GetNote(id)
                if note and note.wpClearOnLeave and BNB.HasActiveWaypoint(note) then
                    shouldClear = true; break
                end
            end
        end
        -- MapPinEnhanced: the note's own pins went above; the game's pin is
        -- whichever MPE pin is tracked now, maybe the user's own (ALL-421)
        if shouldClear and C_Map and C_Map.ClearUserWaypoint
            and not BNB.HasTomTom() and not BNB.MPEUsable() then
            pcall(function() C_Map.ClearUserWaypoint() end)
        end
    end

    -- Badge always reflects current count
    UpdateMinimapBadge(#matches)

    Trace("check: zone=%s matches=%d prev=%d arrived=%d left=%d newPopup=%d newSticky=%d",
        tostring((select(2, GetCurrentZone()))), #matches, #prev, arrived, left,
        #newPopupIDs, #newStickyIDs)

    -- Only fire alerts for notes that are genuinely new to this context, or
    -- just left
    if #newPopupIDs > 0 or #newStickyIDs > 0 then
        local _, locName = GetCurrentZone()
        C_Timer.After(0.5, function()
            if BNB.Sticky and BNB.Sticky.Open then
                for _, noteID in ipairs(newStickyIDs) do
                    local ok, err = pcall(function() BNB.Sticky.Open(noteID) end)
                    Trace("sticky open %s: ok=%s err=%s isOpen=%s", tostring(noteID), tostring(ok),
                        tostring(err), tostring(BNB.Sticky.IsOpen and BNB.Sticky.IsOpen(noteID)))
                end
            end
            if #newPopupIDs > 0 then
                ShowSituationToasts(newPopupIDs, locName, leftBy)
                Trace("toasts shown: %s uiParentShown=%s", tostring((BNB.Toast.Count())),
                    tostring(UIParent:IsShown()))
            end
            C_Timer.After(3, function()
                local open = 0
                for _, noteID in ipairs(newStickyIDs) do
                    if BNB.Sticky.IsOpen and BNB.Sticky.IsOpen(noteID) then open = open + 1 end
                end
                Trace("3 s later: toasts shown=%s, stickies open=%d of %d",
                    tostring((BNB.Toast.Count())), open, #newStickyIDs)
            end)
        end)
    end

    if #newTaskNotes > 0 then
        C_Timer.After(0.5, function()
            for _, id in ipairs(newTaskNotes) do ShowTaskToast(id) end
        end)
    end

    -- ── Waypoint dispatch on zone entry ───────────────────────────────────────
    -- Placed for every matching note whose waypoints were not placed yet while
    -- it has been matching: a new match, or waypoints changed since (also
    -- picked up at once through NoteChanged, below). Read when the timer
    -- fires, so a check that ran in between (left the zone) wins.
    C_Timer.After(1.0, function()
        for _, id in ipairs(BNB._contextMatches or {}) do PlaceNoteWaypoints(id) end
    end)
end

-- Switching the Situations module (Settings > Modules, setup wizard). Off:
-- the popup closes, every automatic waypoint comes off the map and the
-- matches are forgotten (on again must not "leave" a place left while off).
-- On: one quiet check. Then every place that shows a situation redraws.
function BNB.ApplySituationsModule(on)
    if on then
        _quietCheck = true
        BNB.CheckContextualNotes()
    else
        BNB.Toast.DismissAll("situation")
        BNB.ResetTaskToasts()
        local ids = {}
        for id in pairs(BNB._autoWaypoints) do ids[#ids + 1] = id end
        for _, id in ipairs(ids) do BNB.RemoveNoteWaypoints(id) end
        BNB._contextMatches, BNB._contextMatchedBy = {}, {}
        UpdateMinimapBadge(0)
    end
    BNB.SendMessage("SituationsModule", on)
    if BNB.RefreshNoteList then BNB.RefreshNoteList() end              -- row markers
    local ndb = BNB.NotesDB()
    if BNB.Sticky and BNB.Sticky.RefreshMarkers and ndb and ndb.notes then   -- icon badge markers
        for id in pairs(ndb.notes) do BNB.Sticky.RefreshMarkers(id) end
    end
end

-- A note's matching waypoints changed (a row turned on or off, added,
-- removed, or the note renamed): placed again at once rather than on the
-- next situation check. Debounced, so typing a title re-places once.
local _wpRefresh = {}
local function RefreshChangedWaypoints()
    for id in pairs(_wpRefresh) do PlaceNoteWaypoints(id) end
    wipe(_wpRefresh)
end
BNB.RegisterMessage("ContextWaypoints", "NoteChanged", function(_, id)
    for _, m in ipairs(BNB._contextMatches or {}) do
        if m == id then
            _wpRefresh[id] = true
            BNB.Debounce("contextWaypoints", 0.5, RefreshChangedWaypoints)
            return
        end
    end
end)

-- Match one situation string against where the player is now, as note
-- situations are matched. ctx e.g. "zone:stormwind city", "player:Arthas".
-- Unused since the per-task situation scan was removed (PERF-05, Dukul
-- 2026-10-02: it ran on every target change and its toast never existed);
-- kept for per-task situation toasts (ALL-202).
BNB._taskContextMatch = function(ctx)
    if not ctx or ctx == "" then return false end
    _groupNames, _groupGuilds = nil, nil
    return ContextMatches(ctx, CurrentEnv())
end

-- ── Decode context string for display ─────────────────────────────────────────
-- Returns kind (string), value (string) or nil, nil
function BNB.DecodeContext(ctx)
    if not ctx or ctx == "" then return nil, nil end
    local kind, value = ctx:match("^(%w+):(.+)$")
    return kind, value
end

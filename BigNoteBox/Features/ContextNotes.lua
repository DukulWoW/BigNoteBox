-- BigNoteBox Features/ContextNotes.lua — Contextual note surfacing
--
-- Matches a note's situations against the player's current environment and
-- surfaces matching notes via:
--   1. Minimap badge (a count overlay on the minimap button)
--   2. Toast notification (a small slide-in frame, auto-dismissed after 6s)
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
BNB._autoWaypoints  = BNB._autoWaypoints  or {}  -- noteID → TomTom uid (or true for retail)
-- noteID -> "mapID:x:y" of the waypoint last set for it while it matched. A
-- waypoint is set again only when the note newly matches or its waypoint changed,
-- not on every check (every target change stole quest super-tracking, BUG-16).
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

    _badge = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
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

-- ── Toast notification ────────────────────────────────────────────────────────
local _toast        = nil
local _toastRows    = {}
local TOAST_W       = 260
local TOAST_H_BASE  = 48
local TOAST_ROW_H   = 22
local TOAST_MAX_ROWS = 6
local TOAST_FADE    = 0.5
local TOAST_BAR_H   = 2

local function GetHoldTime()
    local db = BigNoteBoxDB
    return (db and db.popupHoldTime) or BNB.DEFAULTS.popupHoldTime
end

-- Countdown state (managed via OnUpdate, not C_Timer — gives us the bar)
local _countdown = {
    running  = false,
    paused   = false,
    elapsed  = 0,
    duration = 5,
}

local function DismissToast()
    local f = _toast; if not f then return end
    _countdown.running = false
    f:SetScript("OnUpdate", nil)
    -- BNB.FadeTo, not UIFrameFadeOut + a timed Hide (CMP-05): a toast shown
    -- again inside the fade-out starts a new fade, which drops this Hide
    BNB.FadeTo(f, f:GetAlpha(), 0, TOAST_FADE, function() f:Hide() end)
end

local function IsMouseOverToast()
    local f = _toast; if not f or not f:IsVisible() then return false end
    if f:IsMouseOver() then return true end
    for _, row in ipairs(_toastRows) do
        if row:IsVisible() and row:IsMouseOver() then return true end
    end
    return false
end

local function StartCountdown(f)
    local ht = GetHoldTime()
    if ht <= 0 then
        -- 0 = stay forever, hide bar
        _countdown.running = false
        if f._bar then f._bar:Hide() end
        f:SetScript("OnUpdate", nil)
        return
    end
    _countdown.running  = true
    _countdown.paused   = IsMouseOverToast()
    _countdown.elapsed  = 0
    _countdown.duration = ht
    if f._bar then
        f._bar:SetWidth(f:GetWidth())
        f._bar:Show()
    end
    f:SetScript("OnUpdate", function(self, dt)
        if not _countdown.running then self:SetScript("OnUpdate", nil); return end
        if _countdown.paused then return end
        _countdown.elapsed = _countdown.elapsed + dt
        -- Update bar width
        local frac = 1 - math.min(_countdown.elapsed / _countdown.duration, 1)
        if self._bar then
            local bw = math.max(0, self:GetWidth() * frac)
            self._bar:SetWidth(bw)
            -- Colour shift: green → yellow → red
            if frac > 0.5 then
                self._bar:SetColorTexture(0.3, 0.75, 0.3, 0.9)
            elseif frac > 0.2 then
                self._bar:SetColorTexture(0.85, 0.70, 0.2, 0.9)
            else
                self._bar:SetColorTexture(0.85, 0.25, 0.2, 0.9)
            end
        end
        if _countdown.elapsed >= _countdown.duration then
            DismissToast()
        end
    end)
end

local function PauseCountdown()
    _countdown.paused = true
end

local function ResumeCountdown()
    if not _countdown.running then return end
    _countdown.paused = false
end

local function GetOrCreateToast()
    if _toast then return _toast end

    local f = BNB.CreateBackdropFrame("Frame", "BigNoteBoxContextToast", UIParent)
    f:SetSize(TOAST_W, TOAST_H_BASE)
    f:SetFrameStrata("DIALOG")
    f:SetClampedToScreen(true)
    if BNB.GetPopupAnchorPoint then
        f:SetPoint(BNB.GetPopupAnchorPoint())
    else
        f:SetPoint("CENTER", UIParent, "CENTER", 0, 200)
    end
    BNB.SetBackdrop(f, 0.06, 0.06, 0.09, 0.94, 0.40, 0.40, 0.42, 1)
    f:SetAlpha(0)
    f:Hide()

    -- Countdown bar (anchored to bottom of the full toast including rows)
    local bar = f:CreateTexture(nil, "OVERLAY")
    bar:SetHeight(TOAST_BAR_H)
    bar:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, 0)
    bar:SetColorTexture(0.3, 0.75, 0.3, 0.9)
    bar:SetWidth(TOAST_W)
    bar:Hide()
    f._bar = bar

    -- Icon
    local icon = f:CreateTexture(nil, "ARTWORK")
    icon:SetSize(32, 32)
    icon:SetPoint("LEFT", f, "LEFT", 8, 0)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    f._icon = icon

    -- Main label (gold)
    local lbl = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    lbl:SetPoint("LEFT",  icon, "RIGHT",  8, 4)
    lbl:SetPoint("RIGHT", f,    "RIGHT", -8, 0)
    lbl:SetJustifyH("LEFT")
    lbl:SetWordWrap(true)
    lbl:SetMaxLines(1)
    lbl:SetTextColor(1, 0.82, 0, 1)
    f._lbl = lbl

    -- Sub label (grey)
    local sub = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    sub:SetPoint("LEFT",   icon,  "RIGHT",   8, -6)
    sub:SetPoint("RIGHT",  f,     "RIGHT",  -8,  0)
    sub:SetPoint("BOTTOM", f,     "BOTTOM",  0,  6)
    sub:SetJustifyH("LEFT")
    sub:SetWordWrap(false)
    sub:SetMaxLines(1)
    sub:SetTextColor(0.65, 0.65, 0.65)
    f._sub = sub

    f:EnableMouse(true)
    f:SetScript("OnEnter", PauseCountdown)
    f:SetScript("OnLeave", function()
        -- Only resume if mouse truly left the entire toast area
        if not IsMouseOverToast() then ResumeCountdown() end
    end)

    -- If the toast appears under the cursor, OnEnter never fires.
    -- Check on first frame after show.
    f:SetScript("OnShow", function()
        C_Timer.After(0, function()
            if IsMouseOverToast() then PauseCountdown() end
        end)
    end)

    _toast = f
    return f
end

local function GetToastRow(parent, index)
    if _toastRows[index] then return _toastRows[index] end
    local row = CreateFrame("Button", nil, parent)
    row:SetHeight(TOAST_ROW_H)
    local bg = row:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(); bg:SetColorTexture(0.10, 0.10, 0.13, 0.8)
    local hi = row:CreateTexture(nil, "ARTWORK")
    hi:SetAllPoints(); hi:SetColorTexture(0.25, 0.40, 0.25, 0.4)
    hi:Hide()
    row._hi = hi

    -- Right-aligned sub-zone tag (created first so title can anchor to it)
    local ctx = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    ctx:SetPoint("RIGHT", row, "RIGHT", -8, 0)
    ctx:SetJustifyH("RIGHT"); ctx:SetWordWrap(false); ctx:SetMaxLines(1)
    ctx:SetTextColor(0.50, 0.50, 0.50)
    row._ctx = ctx

    local lbl = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    lbl:SetPoint("LEFT",  row, "LEFT",  8, 0)
    lbl:SetPoint("RIGHT", ctx, "LEFT", -4, 0)
    lbl:SetJustifyH("LEFT"); lbl:SetWordWrap(false); lbl:SetMaxLines(1)
    lbl:SetTextColor(0.85, 0.85, 0.85)
    row._lbl = lbl

    _toastRows[index] = row
    return row
end

-- A click on the toast opens the note in the main window: through the note
-- list's own Open (creates the window if needed, clears a sidebar or search
-- filter that hides the note). A bare mainFrame:Show() + SelectNote did
-- nothing before the window existed and left a filtered note unselected
local function OpenNote(id)
    if BNB.OpenNoteInMain and BNB.GetNote(id) then BNB.OpenNoteInMain(id) end
end

-- leftBy: noteID -> the situation string it was left by, for notes shown on
-- leaving (ALL-232); the line under the title / the row tag says so
local function ShowToast(matchIDs, locationName, leftBy)
    leftBy = leftBy or {}
    local function LeftText(id)
        local k, v = (leftBy[id] or ""):match("^(%w+):(.+)$")
        if not v then return nil end
        -- A player is not left but gone: "Thrall is gone", name without realm
        if k == "player" or k == "npc" or k == "guild" then return string.format(L["CONTEXT_GONE"], v:match("^([^-]+)") or v) end
        -- A window is closed, not left: "Vendor closed" (ALL-232 S4)
        if k == "open" then return string.format(L["CONTEXT_CLOSED"], BNB.SituationValueLabel(k, v)) end
        if k == "state" then return L["CONTEXT_NOT_RESTED"] end
        return string.format(L["CONTEXT_LEFT"], BNB.SituationValueLabel(k, v))
    end
    if not BigNoteBoxDB or BigNoteBoxDB.contextSurface == false then return end
    local count = #matchIDs
    if count == 0 then return end

    local f = GetOrCreateToast()
    if not f then return end

    -- Stop any running countdown
    _countdown.running = false
    f:SetScript("OnUpdate", nil)

    -- Reposition
    f:ClearAllPoints()
    if BNB.GetPopupAnchorPoint then
        f:SetPoint(BNB.GetPopupAnchorPoint())
    else
        f:SetPoint("CENTER", UIParent, "CENTER", 0, 200)
    end

    -- Hide all existing rows
    for _, row in ipairs(_toastRows) do row:Hide() end

    if count == 1 then
        local note = BNB.GetNote(matchIDs[1])
        local title = (note and note.title and note.title ~= "") and note.title or L["UNTITLED"]
        local noteIcon = (note and note.icon and note.icon ~= "") and note.icon
            or "Interface\\AddOns\\BigNoteBox\\Assets\\icon"
        f._icon:SetTexture(noteIcon)
        f._lbl:SetText(title)
        local tc = note and note.titleColor
        if tc then f._lbl:SetTextColor(tc.r, tc.g, tc.b, 1)
        else       f._lbl:SetTextColor(1, 0.82, 0, 1) end
        f._sub:SetText(LeftText(matchIDs[1]) or locationName or "")

        f:SetScript("OnMouseDown", function(_, btn)
            if btn == "RightButton" then
                _countdown.running = false; f:SetScript("OnUpdate", nil); f:Hide()
                return
            end
            OpenNote(matchIDs[1])
            _countdown.running = false; f:SetScript("OnUpdate", nil); f:Hide()
        end)

        f:SetSize(TOAST_W, TOAST_H_BASE)
        f._rowCount = 0
    else
        f._icon:SetTexture("Interface\\AddOns\\BigNoteBox\\Assets\\icon")
        f._lbl:SetText(string.format(L["CONTEXT_BADGE"], count))
        f._sub:SetText(locationName or "")

        f:SetScript("OnMouseDown", function(_, btn)
            if btn == "RightButton" then
                _countdown.running = false; f:SetScript("OnUpdate", nil); f:Hide()
                return
            end
            OpenNote(matchIDs[1])   -- the first one listed (the rows open each)
            _countdown.running = false; f:SetScript("OnUpdate", nil); f:Hide()
        end)

        local rowCount = math.min(count, TOAST_MAX_ROWS)
        for i = 1, rowCount do
            local row = GetToastRow(f, i)
            row:SetParent(f)
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT",  f, "BOTTOMLEFT",  0, -(i - 1) * TOAST_ROW_H)
            row:SetPoint("TOPRIGHT", f, "BOTTOMRIGHT", 0, -(i - 1) * TOAST_ROW_H)

            local note = BNB.GetNote(matchIDs[i])
            local title = (note and note.title and note.title ~= "") and note.title or L["UNTITLED"]
            local tc = note and note.titleColor
            if tc then
                row._lbl:SetText("|cffffd100-|r  " .. title)
                row._lbl:SetTextColor(tc.r, tc.g, tc.b, 1)
            else
                row._lbl:SetText("|cffffd100-|r  " .. title)
                row._lbl:SetTextColor(0.85, 0.85, 0.85)
            end

            -- Show sub-zone tag if this note matched by a sub-zone, or
            -- "(Left X)" for a note shown on leaving
            local ctx = BNB._contextMatchedBy[matchIDs[i]] or ""
            local ctxKind, ctxVal = ctx:match("^(%w+):(.+)$")
            local left = LeftText(matchIDs[i])
            if left then
                row._ctx:SetText("(" .. left .. ")")
                row._ctx:Show()
            elseif ctxKind == "subzone" and ctxVal and ctxVal ~= "" then
                row._ctx:SetText("(" .. ctxVal .. ")")
                row._ctx:Show()
            else
                row._ctx:SetText("")
                row._ctx:Hide()
            end

            local noteID = matchIDs[i]
            row:SetScript("OnMouseDown", function(_, btn)
                if btn == "RightButton" then
                    _countdown.running = false; f:SetScript("OnUpdate", nil); f:Hide()
                    return
                end
                OpenNote(noteID)
                _countdown.running = false; f:SetScript("OnUpdate", nil); f:Hide()
            end)
            row:SetScript("OnEnter", function()
                if row._hi then row._hi:Show() end
                PauseCountdown()
            end)
            row:SetScript("OnLeave", function()
                if row._hi then row._hi:Hide() end
                if not IsMouseOverToast() then ResumeCountdown() end
            end)
            row:Show()
        end

        -- Header stays fixed size; rows hang below
        f:SetSize(TOAST_W, TOAST_H_BASE)
        f._rowCount = rowCount
    end

    -- Anchor countdown bar: left-anchored only so SetWidth controls shrinking
    local totalRowH = (f._rowCount or 0) * TOAST_ROW_H
    if f._bar then
        f._bar:ClearAllPoints()
        f._bar:SetPoint("TOPLEFT", f, "BOTTOMLEFT", 0, -totalRowH)
        f._bar:SetWidth(TOAST_W)
    end

    f:Show()
    BNB.FadeTo(f, 0, 1, TOAST_FADE)

    -- Start countdown after fade-in completes
    C_Timer.After(TOAST_FADE, function()
        if f:IsVisible() then StartCountdown(f) end
    end)
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
    local freq = note.contextFreq
    if not freq then return true end
    local rec  = note.contextSeen and note.contextSeen[BNB.currentChar]
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

-- Sorts a note that is due to show into the sticky / popup lists by its
-- display mode
local function AddByDisplay(note, stickyIDs, popupIDs)
    local d = note.contextDisplay
    if d == "sticky" or d == "both" then stickyIDs[#stickyIDs + 1] = note.id end
    if d ~= "sticky" then popupIDs[#popupIDs + 1] = note.id end
end

-- ── Main check ────────────────────────────────────────────────────────────────
function BNB.CheckContextualNotes()
    if not BigNoteBoxDB or BigNoteBoxDB.contextSurface == false then
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
        if not prevSet[id] and note and ShowsOn(note, "a") and Due(note, "a") then
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
           and Due(note, "l") then
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
            -- Waypoint removal on zone leave
            if note and note.wpClearOnLeave and BNB._autoWaypoints[id] then
                local uid = BNB._autoWaypoints[id]
                if TomTom and TomTom.RemoveWaypoint and type(uid) == "table" then
                    pcall(function() TomTom:RemoveWaypoint(uid) end)
                elseif uid == true and C_Map and C_Map.ClearUserWaypoint then
                    -- Retail: only clear if no other departing note wants to keep its WP
                    -- Deferred — checked after the full loop
                end
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
                if note and note.wpClearOnLeave and note.waypoint then
                    shouldClear = true; break
                end
            end
        end
        if shouldClear and C_Map and C_Map.ClearUserWaypoint
            and not (TomTom and TomTom.RemoveWaypoint) then
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
                ShowToast(newPopupIDs, locName, leftBy)
                Trace("toast shown: visible=%s uiParentShown=%s", tostring(_toast and _toast:IsVisible()),
                    tostring(UIParent:IsShown()))
            end
            C_Timer.After(3, function()
                local open = 0
                for _, noteID in ipairs(newStickyIDs) do
                    if BNB.Sticky.IsOpen and BNB.Sticky.IsOpen(noteID) then open = open + 1 end
                end
                Trace("3 s later: toast visible=%s, stickies open=%d of %d",
                    tostring(_toast and _toast:IsVisible()), open, #newStickyIDs)
            end)
        end)
    end

    -- ── Waypoint dispatch on zone entry ───────────────────────────────────────
    -- Set for every matching note whose waypoint was not set yet while it has
    -- been matching: a new match, or a waypoint added or moved since (e.g. saved
    -- while already in the zone, picked up by the next check). Read when the
    -- timer fires, so a check that ran in between (left the zone) wins.
    -- Uses TomTom:AddWaypoint (WaypointUI shims this) or the retail map pin API.
    C_Timer.After(1.0, function()
        for _, id in ipairs(BNB._contextMatches or {}) do
            local note = BNB.GetNote(id)
            local wp   = note and note.waypoint
            local sig  = wp and wp.x and wp.y and wp.mapID
                and (wp.mapID .. ":" .. wp.x .. ":" .. wp.y) or nil
            local due  = sig and _wpSent[id] ~= sig
            _wpSent[id] = sig
            if due then
                local wpTitle = (wp.title and wp.title ~= "") and wp.title
                           or  (note.title and note.title ~= "") and note.title
                           or  "BigNoteBox"
                if TomTom and TomTom.AddWaypoint then
                    -- A moved waypoint replaces the old one rather than adding a second
                    local old = BNB._autoWaypoints[id]
                    if type(old) == "table" and TomTom.RemoveWaypoint then
                        pcall(function() TomTom:RemoveWaypoint(old) end)
                    end
                    local ok, uid = pcall(function()
                        return TomTom:AddWaypoint(wp.mapID, wp.x / 100, wp.y / 100, {
                            title = wpTitle,
                            from  = "BigNoteBox",
                        })
                    end)
                    if ok and uid then BNB._autoWaypoints[id] = uid end
                elseif C_Map and C_Map.SetUserWaypoint then
                    pcall(function()
                        local pt = UiMapPoint.CreateFromCoordinates(
                            wp.mapID, wp.x / 100, wp.y / 100)
                        C_Map.SetUserWaypoint(pt)
                        if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then
                            C_SuperTrack.SetSuperTrackedUserWaypoint(true)
                        end
                    end)
                    BNB._autoWaypoints[id] = true  -- retail flag
                end
            end
        end
    end)
end

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

-- BigNoteBox Features/AlarmManager.lua
-- Alarm system: tick engine, fire logic, snooze, recurrence calculation,
-- glow dispatch (LibCustomGlow-1.0), sound, combat queue.
--
-- Public API surface:
--   BNB.Alarm.SetAlarm(noteID, alarmData)   -- write alarm to note; nil alarmData = clear
--   BNB.Alarm.ClearAlarm(noteID)            -- remove alarm entirely
--   BNB.Alarm.Dismiss(noteID)               -- dismiss fired popup, mark fired
--   BNB.Alarm.Snooze(noteID, minutes)       -- snooze by N minutes
--   BNB.Alarm.ResetFired(noteID)            -- re-arm a fired alarm
--   BNB.Alarm.GetNextFireTime(noteID)       -- returns Unix timestamp or nil
--   BNB.Alarm.ResetKind(alarm)              -- "daily" / "weekly" / nil (reset alarm types)
--   BNB.Alarm.NextResetTime(kind)           -- next daily / weekly reset, Unix timestamp
--   BNB.Alarm.GlowStart(noteID)             -- start glow on all targets for note
--   BNB.Alarm.GlowStop(noteID)              -- stop glow on all targets for note
--   BNB.Alarm.RegisterGlowTarget(noteID, frame)   -- called by NoteList / StickyNote
--   BNB.Alarm.UnregisterGlowTarget(noteID, frame) -- called on widget hide/destroy

local BNB = BigNoteBox
if not BNB then return end
local L = BNB.L

local LCG -- assigned after PLAYER_LOGIN once LibStub is available

-- ---------------------------------------------------------------------------
-- MODULE TABLE
-- ---------------------------------------------------------------------------
BNB.Alarm = BNB.Alarm or {}
local AM = BNB.Alarm

-- ---------------------------------------------------------------------------
-- CONSTANTS
-- ---------------------------------------------------------------------------
local TICK_INTERVAL   = 10      -- seconds between alarm checks
local SOUND_REPEAT    = 10      -- alarm.soundRepeat nil: seconds between sound repeats while ringing
local PULSE_ON        = 10      -- glow-on duration for "pulse" mode (seconds)
local PULSE_OFF       = 10      -- glow-off duration for "pulse" mode (seconds)
local ONCE_DURATION   = 10      -- glow duration for "once" mode (seconds)
local GLOW_KEY        = "bnb_alarm"

-- Forever-only AutoCast glow clearance, icon-sized target (FOR-16). Starting
-- point, not re-derived from the window pads above (icon frames are not
-- ButtonFrameTemplate chrome, so BNB.CHROME_DELTA does not apply here) --
-- re-tune against a live alarm-glowing note icon on Forever.
local GLOW_PAD_LEFT   = 0
local GLOW_PAD_TOP    = 2
local GLOW_PAD_RIGHT  = 1
local GLOW_PAD_BOTTOM = 2
local DEFAULT_SOUND   = "Interface/AddOns/BigNoteBox/Assets/Sounds/default.ogg"
local SOUND_CHANNEL   = "Master"

-- ---------------------------------------------------------------------------
-- STATE
-- ---------------------------------------------------------------------------
-- { [noteID] = { frame1, frame2, ... } }  -- active glow target frames
local _glowTargets   = {}
-- { [noteID] = { pulseTimer, mode, glowActive } } -- per-note glow state
local _glowState     = {}
-- Alarms that fired during combat, queued for post-combat delivery { noteID, ... }
local _combatQueue   = {}
-- Sticky/minimized alarms that fired in combat (SN.Open refuses there) { [noteID] = true }
local _stickyAfterCombat = {}
-- Alarms that fired and are not yet dismissed, snoozed or cleared. FireAlarm
-- runs once per ring; Tick skips these (BUG-08, it re-fired every 10 s)
local _ringing       = {}
-- { [noteID] = ticker } repeating the sound while ringing (alarm.soundRepeat)
local _nag           = {}
-- Popup note IDs: on screen or waiting their turn in _popupQueue (one popup frame)
local _activePopups  = {}
local _popupQueue    = {}
-- Alarms that fired in sticky/minimized mode and haven't been dismissed yet
local _activeStickyAlarms = {}
-- Accumulated offline-missed alarms shown in overview on login
local _missedOnLogin = {}

-- ---------------------------------------------------------------------------
-- HELPERS
-- ---------------------------------------------------------------------------
local function GetNote(id)
    return BNB.GetNote and BNB.GetNote(id)
end

-- state = true: the alarm only moved on (dismissed, snoozed, re-armed), which
-- is not an edit of the note, so `updated` stays (SV-08). Setting or clearing
-- an alarm is an edit.
local function SaveAlarm(noteID, alarmData, state)
    local opts = state and { noTouch = true } or nil
    -- alarmData == nil means clear the alarm field entirely
    if alarmData == nil then
        BNB.UpdateNote(noteID, { _clear = { "alarm" } }, opts)
    else
        BNB.UpdateNote(noteID, { alarm = alarmData }, opts)
    end
end

-- Returns alarmDefaults table from DB, with fallback so we never crash
local function Defaults()
    return (BigNoteBoxDB and BigNoteBoxDB.alarmDefaults) or BNB.DEFAULTS.alarmDefaults
end

-- The alarm window's own sounds (its Sound list). These were only known to
-- the window's Test button: ringing went to LSM, which answered an unknown key
-- with its silent "None" sound, so every one of them rang silent (ALL-136.3).
local SOUND_DIR   = "Interface/AddOns/BigNoteBox/Assets/Sounds/"
local SOUND_FILES = {}
for i = 1, 10 do
    SOUND_FILES[string.format("sound%02d", i)] = string.format("%ssound%02d.ogg", SOUND_DIR, i)
end

-- File path for an alarm sound key; nil for "silent"
local function ResolveSoundPath(soundKey)
    if not soundKey or soundKey == "default" then
        return DEFAULT_SOUND
    end
    if soundKey == "silent" then
        return nil
    end
    if SOUND_FILES[soundKey] then return SOUND_FILES[soundKey] end
    -- A LibSharedMedia sound; noDefault, so an unknown key is not LSM's silent default
    local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
    if LSM then
        local path = LSM:Fetch("sound", soundKey, true)
        if path then return path end
    end
    return DEFAULT_SOUND
end
AM.SoundPath = ResolveSoundPath

local function PlayAlarmSound(alarm)
    local path = ResolveSoundPath(alarm and alarm.sound)
    if path then
        PlaySoundFile(path, SOUND_CHANNEL)
    end
end

-- The wall clock an alarm is set in: in-game alarms always read the server
-- clock (ALL-104), real-time alarms follow the player's server-time setting.
local function ClockDate(alarm, fmt, ts)
    if alarm.timeType == "ingame" then return date(fmt, ts + BNB.ServerClockOffset()) end
    return BNB.Date(fmt, ts)
end
local function ClockTime(alarm, t)
    if alarm.timeType == "ingame" then return time(t) - BNB.ServerClockOffset() end
    return BNB.Time(t)
end

-- Next time the server clock reads igTime ("HH:MM"), strictly after `after`
-- (default now). nil for a missing or malformed igTime.
function AM.NextInGameTime(igTime, after)
    if type(igTime) ~= "string" then return nil end
    local h, m = igTime:match("^(%d+):(%d+)$")
    if not h then return nil end
    after = after or time()
    local off = BNB.ServerClockOffset()
    local t = date("*t", after + off)
    t.hour = tonumber(h); t.min = tonumber(m); t.sec = 0
    local candidate = time(t) - off
    if candidate <= after then
        t.day = t.day + 1   -- tomorrow by the calendar, not +86400 (DST)
        candidate = time(t) - off
    end
    return candidate
end

-- Daily / Weekly reset alarms (ALL-342): the Type is timeType "dailyreset" /
-- "weeklyreset" and they ring at the reset itself, every day / week. They
-- also save recur = "daily" / "weekly", so an older build still repeats a
-- weekly one. recur = "weekly" alone is the shape from before ALL-342 (a
-- Repeat choice) and reads as a weekly reset alarm. Ask this, never timeType.
function AM.ResetKind(alarm)
    if not alarm then return nil end
    if alarm.timeType == "dailyreset" then return "daily" end
    if alarm.timeType == "weeklyreset" or alarm.recur == "weekly" then return "weekly" end
    return nil
end

-- Next daily / weekly reset, from the client's own reset clock: the region's
-- day and hour, no hard-coded Tuesday 07:00 (BUG-09). nil if the client
-- cannot say.
local RESET_PERIOD = { daily = 86400, weekly = 7 * 86400 }
function AM.NextResetTime(kind)
    if not C_DateAndTime or not RESET_PERIOD[kind] then return nil end
    local fn = kind == "daily" and C_DateAndTime.GetSecondsUntilDailyReset
               or C_DateAndTime.GetSecondsUntilWeeklyReset
    local secs = fn and fn()
    if not secs then return nil end
    local now = time()
    local nextReset = now + secs
    -- Dismissed in the same minute as the reset: that one has fired, take the next
    if nextReset <= now + 60 then nextReset = nextReset + RESET_PERIOD[kind] end
    return nextReset
end

-- ---------------------------------------------------------------------------
-- RECURRENCE: compute next fire time from a fired alarm
-- Returns a new Unix timestamp, or nil if alarm should not recur.
-- ---------------------------------------------------------------------------
local function NextRecurTime(alarm)
    local kind = AM.ResetKind(alarm)
    if kind then return AM.NextResetTime(kind) end

    -- An in-game alarm without a Repeat choice rings every day at its server
    -- time, as its note in Set alarm says; Dismiss marked it fired (ALL-342)
    if alarm.timeType == "ingame" and not alarm.recur then
        return AM.NextInGameTime(alarm.igTime)
    end

    local r = alarm.recur
    if not r then return nil end

    local now = time()

    if r == "weekdays" then
        -- recurDays = {1,2,3,...} 1=Mon...7=Sun (mapped from Lua wday)
        local days = alarm.recurDays
        if not days or #days == 0 then return nil end
        -- Find the next weekday at the same HH:MM as original alarm
        -- Wall-clock maths in the clock the player set the alarm in (ALL-104)
        local orig = ClockDate(alarm, "*t", alarm.time or now)
        local t    = ClockDate(alarm, "*t", now)
        for offset = 1, 8 do
            t.day = (ClockDate(alarm, "*t", now)).day + offset
            local candidate = ClockTime(alarm, {
                year=t.year, month=t.month, day=t.day,
                hour=orig.hour, min=orig.min, sec=0
            })
            local ct = ClockDate(alarm, "*t", candidate)
            -- ct.wday: 1=Sun,2=Mon...7=Sat -> remap to 1=Mon..7=Sun
            local mapped = ct.wday == 1 and 7 or ct.wday - 1
            for _, d in ipairs(days) do
                if d == mapped then
                    return candidate
                end
            end
        end
        return nil

    elseif r == "interval" then
        local every = alarm.recurEvery
        if not every or every <= 0 then return nil end
        local base = alarm.time or now
        -- Find next interval from base that is in the future
        local n = math.ceil((now - base) / (every * 86400))
        return base + n * every * 86400
    end

    return nil
end

-- ---------------------------------------------------------------------------
-- GLOW TARGETS
-- ---------------------------------------------------------------------------
function AM.RegisterGlowTarget(noteID, frame)
    if not noteID or not frame then return end
    -- If this frame was previously registered under a different noteID, unregister it first.
    -- This prevents overview row pool reuse from leaving stale cross-note registrations.
    local prevNoteID = frame._bnbGlowNoteID
    if prevNoteID and prevNoteID ~= noteID and _glowTargets[prevNoteID] then
        for i, f in ipairs(_glowTargets[prevNoteID]) do
            if f == frame then table.remove(_glowTargets[prevNoteID], i); break end
        end
    end
    frame._bnbGlowNoteID = noteID
    _glowTargets[noteID] = _glowTargets[noteID] or {}
    -- avoid duplicates
    for _, f in ipairs(_glowTargets[noteID]) do
        if f == frame then return end
    end
    table.insert(_glowTargets[noteID], frame)
    -- If glow is already active for this note, start on the new target immediately
    local gs = _glowState[noteID]
    if gs and gs.glowActive and LCG then
        local note = GetNote(noteID)
        local alarm = note and note.alarm
        AM._LCGStart(frame, alarm)
    end
end

function AM.UnregisterGlowTarget(noteID, frame)
    if not noteID or not _glowTargets[noteID] then return end
    for i, f in ipairs(_glowTargets[noteID]) do
        if f == frame then
            table.remove(_glowTargets[noteID], i)
            break
        end
    end
end

-- Resolve effective glow type (alarm override or global default)
function AM.GetGlowType(alarm)
    local def = Defaults()
    return (alarm and alarm.glowType) or def.glowType or BNB.DEFAULTS.alarmDefaults.glowType
end

-- Internal: start LCG glow on a single frame using alarm's glow settings + advanced params
function AM._LCGStart(frame, alarm)
    if not LCG or not frame then return end
    local def    = Defaults()
    local gType  = AM.GetGlowType(alarm)
    local gColor = (alarm and alarm.glowColor) or def.glowColor or BNB.DEFAULTS.alarmDefaults.glowColor

    -- Per-type advanced params (nil = LCG default)
    local lines     = alarm and alarm.glowLines
    local frequency = alarm and alarm.glowFrequency
    local length    = alarm and alarm.glowLength
    local particles = alarm and alarm.glowParticles
    local acScale   = alarm and alarm.glowScale
    local duration  = alarm and alarm.glowDuration

    -- Stop any existing glow first (type may have changed)
    AM._LCGStop(frame)

    if gType == 1 then
        -- Pixel: lines (def 8), frequency (def 0.25), length (def ~10)
        LCG.PixelGlow_Start(frame, gColor, lines, frequency, length, nil, nil, nil, nil, GLOW_KEY)
    elseif gType == 2 then
        -- AutoCast: particles (def 4), frequency (def 0.125), scale
        LCG.AutoCastGlow_Start(frame, gColor, particles, frequency, acScale, nil, nil, GLOW_KEY)
        if BNB.IsForever then
            local g = frame["_AutoCastGlow" .. GLOW_KEY]
            if g then
                g:ClearAllPoints()
                g:SetPoint("TOPLEFT",     frame, "TOPLEFT",     -GLOW_PAD_LEFT, GLOW_PAD_TOP)
                g:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", GLOW_PAD_RIGHT, -GLOW_PAD_BOTTOM)
            end
        end
    elseif gType == 3 then
        -- Pulsing border: frequency controls pulse duration (def 0.6s)
        AM._PulsingBorderStart(frame, gColor, frequency)
    elseif gType == 4 then
        -- Proc: duration (def 1s)
        LCG.ProcGlow_Start(frame, { color = gColor, key = GLOW_KEY, duration = duration })
    end
end

function AM._LCGStop(frame)
    if not frame then return end
    pcall(function() if LCG then LCG.PixelGlow_Stop(frame, GLOW_KEY)    end end)
    pcall(function() if LCG then LCG.AutoCastGlow_Stop(frame, GLOW_KEY) end end)
    pcall(function() if LCG then LCG.ProcGlow_Stop(frame, GLOW_KEY)     end end)
    AM._PulsingBorderStop(frame)
end

-- ---------------------------------------------------------------------------
-- PULSING BORDER (Border glow type — no LCG dependency)
-- 4-edge colored border with bounce alpha animation, elevated above user borders.
-- ---------------------------------------------------------------------------
local BORDER_KEY = "_bnbAlarmBorder"

function AM._PulsingBorderStart(frame, color, duration)
    if not frame then return end
    color = color or { 0.400, 0.733, 0.416, 1.0 }
    duration = duration or 0.7
    local cr, cg, cb, ca = color[1] or 1, color[2] or 1, color[3] or 1, color[4] or 1

    local state = frame[BORDER_KEY]
    if not state then
        -- Use a high frame level so it renders above any user-set note border
        local level = frame:GetFrameLevel() + 20
        local holder = CreateFrame("Frame", nil, frame)
        holder:SetAllPoints(frame)
        holder:SetFrameLevel(level)

        local function Edge()
            return holder:CreateTexture(nil, "OVERLAY", nil, 7)
        end
        local t = Edge(); t:SetPoint("TOPLEFT");    t:SetPoint("TOPRIGHT");    t:SetHeight(2)
        local b = Edge(); b:SetPoint("BOTTOMLEFT"); b:SetPoint("BOTTOMRIGHT"); b:SetHeight(2)
        local l = Edge(); l:SetPoint("TOPLEFT");    l:SetPoint("BOTTOMLEFT");  l:SetWidth(2)
        local r = Edge(); r:SetPoint("TOPRIGHT");   r:SetPoint("BOTTOMRIGHT"); r:SetWidth(2)
        for _, e in ipairs({ t, b, l, r }) do e:SetColorTexture(cr, cg, cb, ca) end

        local ag   = holder:CreateAnimationGroup()
        ag:SetLooping("BOUNCE")
        local fade = ag:CreateAnimation("Alpha")
        fade:SetFromAlpha(1); fade:SetToAlpha(0.25)
        fade:SetDuration(duration); fade:SetSmoothing("IN_OUT")

        state = { holder = holder, anim = ag, edges = { t, b, l, r } }
        frame[BORDER_KEY] = state
    else
        -- Update color on existing edges
        for _, e in ipairs(state.edges) do e:SetColorTexture(cr, cg, cb, ca) end
    end

    state.holder:Show()
    if not state.anim:IsPlaying() then state.anim:Play() end
end

function AM._PulsingBorderStop(frame)
    if not frame then return end
    local state = frame[BORDER_KEY]
    if state then
        state.anim:Stop()
        state.holder:Hide()
    end
end

-- ---------------------------------------------------------------------------
-- GLOW START / STOP (public, handles pulse timer)
-- ---------------------------------------------------------------------------
function AM.GlowStart(noteID)
    if not noteID then return end
    local note  = GetNote(noteID)
    local alarm = note and note.alarm
    if not alarm then return end

    local def      = Defaults()
    local mode     = alarm.glowMode or def.glowMode or BNB.DEFAULTS.alarmDefaults.glowMode

    -- Cancel any existing glow timers
    AM.GlowStop(noteID)

    local gs = { glowActive = false, mode = mode, pulseTimer = nil }
    _glowState[noteID] = gs

    local function StartOnAllTargets()
        gs.glowActive = true
        for _, f in ipairs(_glowTargets[noteID] or {}) do
            AM._LCGStart(f, alarm)
        end
    end

    local function StopOnAllTargets()
        gs.glowActive = false
        for _, f in ipairs(_glowTargets[noteID] or {}) do
            AM._LCGStop(f)
        end
    end

    if mode == "continuous" then
        StartOnAllTargets()

    elseif mode == "pulse" then
        -- 10s on, 10s off, repeating
        local function PulseOn()
            StartOnAllTargets()
            gs.pulseTimer = C_Timer.NewTimer(PULSE_ON, function()
                StopOnAllTargets()
                gs.pulseTimer = C_Timer.NewTimer(PULSE_OFF, PulseOn)
            end)
        end
        PulseOn()

    elseif mode == "once" then
        StartOnAllTargets()
        gs.pulseTimer = C_Timer.NewTimer(ONCE_DURATION, function()
            StopOnAllTargets()
        end)
    end
end

function AM.GlowStop(noteID)
    if not noteID then return end
    local gs = _glowState[noteID]
    if gs then
        if gs.pulseTimer then
            gs.pulseTimer:Cancel()
            gs.pulseTimer = nil
        end
        gs.glowActive = false
    end
    for _, f in ipairs(_glowTargets[noteID] or {}) do
        AM._LCGStop(f)
    end
    _glowState[noteID] = nil
end

-- ---------------------------------------------------------------------------
-- SOUND REPEAT ("nag")
-- The sound repeats every alarm.soundRepeat seconds (nil = SOUND_REPEAT, 0 =
-- once) until the alarm is answered. Was a side effect of the 10 s re-fire;
-- kept as an option (Dukul, review question 1).
-- ---------------------------------------------------------------------------
local function StopNag(noteID)
    if _nag[noteID] then
        _nag[noteID]:Cancel()
        _nag[noteID] = nil
    end
end

local function StartNag(noteID)
    StopNag(noteID)
    local note  = GetNote(noteID)
    local alarm = note and note.alarm
    if not alarm or alarm.sound == "silent" then return end
    local every = tonumber(alarm.soundRepeat) or SOUND_REPEAT
    if every <= 0 then return end
    _nag[noteID] = C_Timer.NewTicker(every, function()
        local n = GetNote(noteID)
        local a = n and n.alarm
        if not a or not _ringing[noteID] then StopNag(noteID); return end
        if InCombatLockdown() and a.combatMode == "queue" then return end
        PlayAlarmSound(a)
    end)
end

-- ---------------------------------------------------------------------------
-- POPUP
-- There is one popup frame. An alarm that fires while it shows another one
-- waits in _popupQueue and gets the popup when that one is answered; it used to
-- take the frame over and leave the first alarm ringing with no popup (ALL-136.3).
-- ---------------------------------------------------------------------------
local function ShowAlarmPopup(noteID)
    local note  = GetNote(noteID)
    local alarm = note and note.alarm
    if not alarm then return end

    if _activePopups[noteID] then return end  -- on screen or already queued
    _activePopups[noteID] = true

    local AP = BNB.AlarmPopup
    if AP and AP.IsShowingOther and AP.IsShowingOther(noteID) then
        -- Quiet while it waits: its sound starts again with its popup
        _popupQueue[#_popupQueue + 1] = noteID
        StopNag(noteID)
        return
    end
    -- A custom frame (not StaticPopup_Show) because we need a snooze dropdown
    if AP and AP.Show then AP.Show(noteID, alarm) end
end

-- Deferred one frame: the popup's buttons hide the frame after Dismiss/Snooze return
local function ShowNextPopup()
    C_Timer.After(0, function()
        local AP = BNB.AlarmPopup
        if not (AP and AP.Show) then return end
        if AP.IsShowingOther and AP.IsShowingOther(nil) then return end
        while #_popupQueue > 0 do
            local id    = table.remove(_popupQueue, 1)
            local note  = GetNote(id)
            local alarm = note and note.alarm
            if _activePopups[id] and alarm then
                AP.Show(id, alarm)
                -- Its sound with its popup, not up to one repeat later
                if not (InCombatLockdown() and alarm.combatMode == "queue") then
                    PlayAlarmSound(alarm)
                end
                StartNag(id)
                return
            end
        end
    end)
end

-- ---------------------------------------------------------------------------
-- DELIVER: show a ringing alarm the way its fire mode asks
-- noPopup: login scan, which shows the popups itself after the missed list
-- ---------------------------------------------------------------------------
local function Deliver(noteID, noPopup)
    local note  = GetNote(noteID)
    local alarm = note and note.alarm
    if not alarm then return end

    local fireMode = alarm.fireMode or "popup"
    -- Stickies live on UIParent: while it is hidden (Focus mode "hide UI",
    -- Alt+Z) use the popup, which AP.Show puts on WorldFrame (BUG-10)
    if fireMode ~= "popup" and not UIParent:IsShown() then fireMode = "popup" end

    if fireMode ~= "popup" and InCombatLockdown() then
        -- SN.Open refuses in combat (and printed STICKY_COMBAT every 10 s):
        -- open it when combat ends. The note list row glows meanwhile.
        _activeStickyAlarms[noteID] = true
        _stickyAfterCombat[noteID] = true
        AM.GlowStart(noteID)
        return
    end

    -- Sticky modes: open/minimize the sticky note, then start glow on its icon.
    -- Glow must start AFTER the sticky frame exists, so we defer via C_Timer.After.
    if fireMode == "sticky" then
        _activeStickyAlarms[noteID] = true
        if BNB.Sticky and BNB.Sticky.Open then
            BNB.Sticky.Open(noteID)
        end
        C_Timer.After(0.1, function()
            if _ringing[noteID] then AM.GlowStart(noteID) end
        end)
    elseif fireMode == "minimized" then
        _activeStickyAlarms[noteID] = true
        if BNB.Sticky and BNB.Sticky.EnsureMinimizedForAlarm then
            BNB.Sticky.EnsureMinimizedForAlarm(noteID)
        end
        -- Icon frame registered by EnsureMinimizedForAlarm after 0.05s; use 0.1s to be safe
        C_Timer.After(0.1, function()
            if _ringing[noteID] then AM.GlowStart(noteID) end
        end)
    else
        -- "popup" (default): glow on the note list row now, AP.Show adds the popup
        AM.GlowStart(noteID)
        if not noPopup then ShowAlarmPopup(noteID) end
    end
end

-- ---------------------------------------------------------------------------
-- FIRE ALARM
-- Runs once per ring: Dismiss / Snooze / SetAlarm / ClearAlarm end it.
-- ---------------------------------------------------------------------------
local function FireAlarm(noteID, offline)
    local note  = GetNote(noteID)
    if not note then return end
    local alarm = note.alarm
    if not alarm then return end
    if _ringing[noteID] then return end
    _ringing[noteID] = true

    -- Sound (skip if silent, skip in combat if combatMode="queue")
    local combatWait = InCombatLockdown() and alarm.combatMode == "queue"
    if not combatWait then
        PlayAlarmSound(alarm)
    end
    StartNag(noteID)

    if combatWait then
        -- One chat line now; glow on the note list row and an open sticky's
        -- icon or tile; sound and popup or sticky come after combat
        local now = time()
        BNB:Print(string.format(L["ALARM_COMBAT_NOTICE"],
            (note.title and note.title ~= "") and note.title or "?",
            BNB.FmtDate(now) .. " " .. BNB.FmtClock(now)))
        AM.GlowStart(noteID)
        table.insert(_combatQueue, noteID)
        return
    end

    Deliver(noteID, offline)
    if offline then
        table.insert(_missedOnLogin, noteID)
    end
end

-- ---------------------------------------------------------------------------
-- DISMISS / SNOOZE / RESET
-- ---------------------------------------------------------------------------
-- Ends a ring: sound, glow, popup and the "active" flags. The popup frame is
-- hidden when it shows this note (answered elsewhere: overview, sticky close).
local function StopRinging(noteID)
    _ringing[noteID]           = nil
    _activePopups[noteID]      = nil
    _activeStickyAlarms[noteID] = nil
    _stickyAfterCombat[noteID] = nil
    StopNag(noteID)
    AM.GlowStop(noteID)
    if BNB.AlarmPopup and BNB.AlarmPopup.HideFor then BNB.AlarmPopup.HideFor(noteID) end
    ShowNextPopup()
end

function AM.Dismiss(noteID)
    StopRinging(noteID)

    local note  = GetNote(noteID)
    local alarm = note and note.alarm
    if not alarm then return end

    -- Check for recurrence
    local next = NextRecurTime(alarm)
    if next then
        alarm.time        = next
        alarm.fired       = false
        alarm.snoozedUntil = nil
        SaveAlarm(noteID, alarm, true)
    else
        alarm.fired        = true
        alarm.snoozedUntil = nil
        SaveAlarm(noteID, alarm, true)
    end

    -- The note list follows NoteChanged; the overview is refreshed here
    if BNB.AlarmOverview and BNB.AlarmOverview.Refresh then BNB.AlarmOverview.Refresh() end
end

function AM.Snooze(noteID, minutes)
    StopRinging(noteID)

    local note  = GetNote(noteID)
    local alarm = note and note.alarm
    if not alarm then return end
    -- Respect snoozeEnabled flag (default true for backwards compat)
    if alarm.snoozeEnabled == false then
        AM.Dismiss(noteID)
        return
    end

    minutes = minutes or alarm.snoozeDefault or Defaults().snoozeDefault or BNB.DEFAULTS.alarmDefaults.snoozeDefault
    alarm.snoozedUntil = time() + minutes * 60
    alarm.fired        = false
    SaveAlarm(noteID, alarm, true)

    if BNB.AlarmOverview and BNB.AlarmOverview.Refresh then BNB.AlarmOverview.Refresh() end
end

function AM.ResetFired(noteID)
    local note  = GetNote(noteID)
    local alarm = note and note.alarm
    if not alarm then return end
    alarm.fired        = false
    alarm.snoozedUntil = nil
    -- An in-game alarm re-arms for the next time the server clock reads its
    -- HH:MM, not for the past due time (that would ring at once)
    if alarm.timeType == "ingame" and (alarm.time or 0) <= time() then
        alarm.time = AM.NextInGameTime(alarm.igTime)
    end
    -- A reset alarm re-arms for the next reset (ALL-342)
    local kind = AM.ResetKind(alarm)
    if kind and (alarm.time or 0) <= time() then
        alarm.time = AM.NextResetTime(kind)
    end
    SaveAlarm(noteID, alarm, true)
    if BNB.AlarmOverview and BNB.AlarmOverview.Refresh then BNB.AlarmOverview.Refresh() end
end

function AM.SetAlarm(noteID, alarmData)
    -- A ringing alarm that gets edited starts over from its new settings
    if _ringing[noteID] then StopRinging(noteID) end
    SaveAlarm(noteID, alarmData)
    if BNB.AlarmOverview and BNB.AlarmOverview.Refresh then BNB.AlarmOverview.Refresh() end
end

function AM.ClearAlarm(noteID)
    StopRinging(noteID)
    SaveAlarm(noteID, nil)
    if BNB.AlarmOverview and BNB.AlarmOverview.Refresh then BNB.AlarmOverview.Refresh() end
end

-- ---------------------------------------------------------------------------
-- NEXT FIRE TIME UTILITY
-- ---------------------------------------------------------------------------

-- Returns true if this note's alarm has fired and not yet been dismissed/snoozed.
-- Works regardless of glow state (glow may be deferred or not yet started).
function AM.IsAlarmActive(noteID)
    return _activePopups[noteID] == true or _activeStickyAlarms[noteID] == true
end

function AM.GetNextFireTime(noteID)
    local note  = GetNote(noteID)
    local alarm = note and note.alarm
    if not alarm then return nil end
    if alarm.fired then return nil end
    if alarm.snoozedUntil then return alarm.snoozedUntil end
    if alarm.timeType == "ingame" and not alarm.time then
        -- In-game alarms keep a concrete due time in alarm.time (BUG-04: the
        -- next HH:MM was always in the future, so they never fired). Alarms
        -- saved before ALL-136.3 have none yet: the next time the server
        -- clock reads igTime. Written directly: runtime state, not an edit.
        alarm.time = AM.NextInGameTime(alarm.igTime)
    end
    if not alarm.time then
        -- A reset alarm without a due time yet (imported): the next reset
        local kind = AM.ResetKind(alarm)
        if kind then alarm.time = AM.NextResetTime(kind) end
    end
    return alarm.time
end

-- ---------------------------------------------------------------------------
-- TICK — checks all notes for due alarms
-- ---------------------------------------------------------------------------
local function Tick()
    local now = time()
    local ndb = BNB.NotesDB()
    if not ndb or not ndb.notes then return end

    for noteID, note in pairs(ndb.notes) do
        local alarm = note.alarm
        if alarm and not alarm.fired and not _ringing[noteID] then
            local fireAt = AM.GetNextFireTime(noteID)
            if fireAt and now >= fireAt then
                FireAlarm(noteID, false)
            end
        end
    end
end

-- ---------------------------------------------------------------------------
-- COMBAT EVENT HANDLERS
-- ---------------------------------------------------------------------------
local function OnCombatEnd()
    -- Sticky/minimized alarms that fired in combat: open their stickies now
    local stickies = _stickyAfterCombat
    _stickyAfterCombat = {}
    for id in pairs(stickies) do
        if _ringing[id] then Deliver(id) end
    end

    if #_combatQueue == 0 then return end

    -- Collect unique notes that fired during combat and still ring
    -- (one may have been dismissed from the overview in the meantime)
    local seen = {}
    local batch = {}
    for _, id in ipairs(_combatQueue) do
        if not seen[id] and _ringing[id] then
            seen[id] = true
            table.insert(batch, id)
        end
    end
    _combatQueue = {}
    if #batch == 0 then return end

    -- Determine post-combat delivery mode
    -- Use the first queued alarm's combatPost setting as representative
    local note  = GetNote(batch[1])
    local alarm = note and note.alarm
    local mode  = alarm and alarm.combatPost or "immediate"

    if mode == "summary" then
        BNB:Print(string.format("[BNB] %d alarm(s) fired during combat.", #batch))
        for _, id in ipairs(batch) do Deliver(id) end
    else  -- "immediate" and "chat"
        for _, id in ipairs(batch) do
            PlayAlarmSound(GetNote(id) and GetNote(id).alarm)
            Deliver(id)
        end
    end
end

-- ---------------------------------------------------------------------------
-- LOGIN SCAN — fire missed alarms
-- ---------------------------------------------------------------------------
local function LoginScan()
    local ndb = BNB.NotesDB()
    if not ndb or not ndb.notes then return end

    _missedOnLogin = {}
    local now = time()

    for noteID, note in pairs(ndb.notes) do
        local alarm = note.alarm
        if alarm and not alarm.fired then
            local fireAt = AM.GetNextFireTime(noteID)
            if fireAt and now >= fireAt then
                FireAlarm(noteID, true)  -- offline = true, collect to _missedOnLogin
            end
        end
    end

    if #_missedOnLogin > 0 then
        -- Two or more missed: the overview lists them (and says so in chat);
        -- a single one gets just its popup (ALL-190, Dukul 2026-10-02)
        if #_missedOnLogin > 1 and BNB.AlarmOverview and BNB.AlarmOverview.ShowMissed then
            BNB.AlarmOverview.ShowMissed(_missedOnLogin)
        end
        for _, id in ipairs(_missedOnLogin) do
            ShowAlarmPopup(id)
        end
        _missedOnLogin = {}
    end
end

-- ---------------------------------------------------------------------------
-- INIT — called from Events.lua on PLAYER_LOGIN
-- ---------------------------------------------------------------------------
function BNB.Alarm.Init()
    -- Resolve LibCustomGlow now that LibStub is available
    LCG = LibStub and LibStub("LibCustomGlow-1.0", true)
    if not LCG then
        -- LCG missing: Border type still works (no dependency), others degrade silently
        BNB:Print("[BNB] LibCustomGlow-1.0 not found. Alarm glow types Pixel/AutoCast/Proc unavailable.")
    end

    -- A timer, not a frame's OnUpdate: OnUpdate stops while UIParent is hidden
    -- (Focus mode "hide UI", Alt+Z), and alarms must still ring then (BUG-10)
    C_Timer.NewTicker(TICK_INTERVAL, Tick)

    -- Combat events
    local combatFrame = CreateFrame("Frame")
    combatFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    combatFrame:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_REGEN_ENABLED" then
            OnCombatEnd()
        end
    end)

    -- Login scan for missed alarms
    LoginScan()
end
